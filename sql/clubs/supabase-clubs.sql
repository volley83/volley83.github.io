-- Clubs du Var : fiches publiques des clubs (annuaire du portail).
-- Chaque club remplit sa fiche par un lien personnel (clubs/?club=CODE) ; le Comité valide avant publication.
-- À lancer une fois dans Supabase › SQL Editor (même projet que le reste du site). Relançable sans risque.

create table if not exists clb_clubs (
  code            text primary key,             -- sigle, le même que partout sur le site (fac_clubs.code)
  nom             text not null,
  acces           text not null unique,         -- code du lien personnel du club
  fiche           jsonb,                        -- fiche publiée
  logo            text,                         -- logo publié (image réduite, « data:image/… »)
  proposition     jsonb,                        -- fiche envoyée par le club, en attente de validation
  logo_propose    text,
  propose_le      timestamptz,
  publie_le       timestamptz,
  lien_envoye_le  timestamptz,
  actif           boolean not null default true,
  ordre           int not null default 0
);
alter table clb_clubs enable row level security;   -- aucun accès direct : tout passe par les fonctions ci-dessous

create or replace function clb_is_admin(pwd text) returns boolean
language sql security definer set search_path = public as $$
  select exists (select 1 from private_config where key = 'admin_password' and value = pwd);
$$;

-- Code d'accès de 8 caractères, sans lettres ni chiffres ambigus (O/0, I/1)
create or replace function clb_code() returns text
language sql volatile as $$
  select string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', 1 + floor(random() * 32)::int, 1), '') from generate_series(1, 8);
$$;

-- ---------- Public ----------
-- Annuaire : clubs actifs, avec leur fiche publiée (null tant que rien n'est publié)
create or replace function clb_public() returns jsonb
language sql security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('code', c.code, 'nom', c.nom, 'fiche', c.fiche, 'logo', c.logo) order by c.ordre, c.nom), '[]'::jsonb)
  from clb_clubs c where c.actif;
$$;

-- ---------- Club (lien personnel) ----------
create or replace function clb_fiche(p_code text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c clb_clubs;
begin
  select * into c from clb_clubs where acces = upper(trim(coalesce(p_code, ''))) and actif;
  if not found then raise exception 'Code incorrect'; end if;
  return jsonb_build_object(
    'code', c.code, 'nom', c.nom,
    'fiche', coalesce(c.proposition, c.fiche),
    'logo', case when c.proposition is not null then c.logo_propose else c.logo end,
    'en_attente', c.proposition is not null,
    'publiee', c.fiche is not null,
    'propose_le', c.propose_le);
end $$;

-- p_logo : null = garder le logo actuel ; '' = pas de logo ; sinon la nouvelle image
create or replace function clb_proposer(p_code text, p_fiche jsonb, p_logo text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c clb_clubs;
begin
  select * into c from clb_clubs where acces = upper(trim(coalesce(p_code, ''))) and actif;
  if not found then raise exception 'Code incorrect'; end if;
  if p_fiche is null or jsonb_typeof(p_fiche) <> 'object' then raise exception 'Fiche vide'; end if;
  if octet_length(p_fiche::text) > 20000 then raise exception 'Fiche trop longue'; end if;
  if p_logo is not null and p_logo <> '' and (p_logo !~ '^data:image/(png|jpeg|webp);base64,' or length(p_logo) > 400000) then
    raise exception 'Logo non valide ou trop lourd';
  end if;
  update clb_clubs set
    proposition = p_fiche,
    logo_propose = case when p_logo is null then (case when c.proposition is not null then c.logo_propose else c.logo end) else nullif(p_logo, '') end,
    propose_le = now()
  where code = c.code;
  return clb_fiche(p_code);
end $$;

-- ---------- Comité ----------
create or replace function clb_admin_get(pwd text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not clb_is_admin(pwd) then raise exception 'Accès refusé'; end if;
  return (select coalesce(jsonb_agg(to_jsonb(c) || jsonb_build_object('email', (select f.email from fac_clubs f where f.code = c.code)) order by c.ordre, c.nom), '[]'::jsonb)
          from clb_clubs c);
end $$;

-- Publie une fiche (celle proposée par le club, éventuellement corrigée, ou une fiche saisie par le Comité)
create or replace function clb_admin_publier(pwd text, p_club text, p_fiche jsonb, p_logo text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not clb_is_admin(pwd) then raise exception 'Accès refusé'; end if;
  update clb_clubs set fiche = p_fiche, logo = nullif(p_logo, ''), proposition = null, logo_propose = null, publie_le = now() where code = p_club;
  if not found then raise exception 'Club inconnu'; end if;
end $$;

-- Écarte la proposition en attente (la fiche publiée, s'il y en a une, ne change pas)
create or replace function clb_admin_refuser(pwd text, p_club text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not clb_is_admin(pwd) then raise exception 'Accès refusé'; end if;
  update clb_clubs set proposition = null, logo_propose = null where code = p_club;
end $$;

-- Ajoute ou modifie un club : {code, nom, actif, ordre, nouveau_code (true = change le lien), lien_envoye (true = note l'envoi), depublier (true)}
create or replace function clb_admin_club(pwd text, p jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare k text := upper(trim(coalesce(p->>'code', '')));
begin
  if not clb_is_admin(pwd) then raise exception 'Accès refusé'; end if;
  if k = '' then raise exception 'Sigle manquant'; end if;
  insert into clb_clubs (code, nom, acces) values (k, coalesce(nullif(trim(p->>'nom'), ''), k), clb_code())
  on conflict (code) do nothing;
  update clb_clubs set
    nom   = coalesce(nullif(trim(p->>'nom'), ''), nom),
    actif = coalesce((p->>'actif')::boolean, actif),
    ordre = coalesce((p->>'ordre')::int, ordre),
    acces = case when coalesce((p->>'nouveau_code')::boolean, false) then clb_code() else acces end,
    lien_envoye_le = case when coalesce((p->>'lien_envoye')::boolean, false) then now() else lien_envoye_le end,
    fiche = case when coalesce((p->>'depublier')::boolean, false) then null else fiche end,
    logo  = case when coalesce((p->>'depublier')::boolean, false) then null else logo end
  where code = k;
end $$;

-- ---------- Droits ----------
revoke execute on function clb_is_admin(text) from public, anon, authenticated;
revoke execute on function clb_code() from public, anon, authenticated;
grant execute on function
  clb_public(),
  clb_fiche(text),
  clb_proposer(text, jsonb, text),
  clb_admin_get(text),
  clb_admin_publier(text, text, jsonb, text),
  clb_admin_refuser(text, text),
  clb_admin_club(text, jsonb)
to anon;

-- ---------- Clubs du Comité : repris de la facturation (sigle et nom), sans toucher à ceux déjà présents ----------
insert into clb_clubs (code, nom, acces, ordre)
select f.code, f.nom, clb_code(), f.ordre from fac_clubs f where f.actif
on conflict (code) do nothing;
