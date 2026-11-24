-- Documents du Comité : liste des documents et leurs fichiers (PDF, Word, Excel…), gérés depuis l'Espace Comité.
-- Les fichiers sont gardés dans la base (colonne bytea), 8 Mo au plus par fichier.
-- À lancer une fois dans Supabase › SQL Editor (même projet que le reste du site). Relançable sans risque.

create table if not exists doc_documents (
  id          bigint generated always as identity primary key,
  slug        text not null unique,             -- identifiant stable, utilisé dans les liens (documents/?doc=…)
  titre       text not null,
  categorie   text not null,                    -- reglements, calendriers, feuilles, formulaires, formations, comite
  description text,
  ordre       int not null default 0,
  visible     boolean not null default true,
  cree_le     timestamptz not null default now()
);
create table if not exists doc_fichiers (
  document_id bigint primary key references doc_documents(id) on delete cascade,
  nom         text not null,                    -- nom du fichier proposé au téléchargement
  type        text not null,                    -- type MIME
  taille      int not null,
  data        bytea not null,
  maj_le      timestamptz not null default now()
);
alter table doc_documents enable row level security;   -- aucun accès direct : tout passe par les fonctions ci-dessous
alter table doc_fichiers enable row level security;

create or replace function doc_is_admin(pwd text) returns boolean
language sql security definer set search_path = public as $$
  select exists (select 1 from private_config where key = 'admin_password' and value = pwd);
$$;

-- « Calendrier général 2026 / 2027 » -> « calendrier-general-2026-2027 »
create or replace function doc_slug(t text) returns text
language sql immutable as $$
  select trim(both '-' from regexp_replace(lower(translate(coalesce(t, ''),
    'àâäáãåçéèêëíìîïñóòôöõúùûüýÿœæÀÂÄÁÃÅÇÉÈÊËÍÌÎÏÑÓÒÔÖÕÚÙÛÜÝŸŒÆ',
    'aaaaaaceeeeiiiinooooouuuuyyoaaaaaaaceeeeiiiinooooouuuuyyoa')), '[^a-z0-9]+', '-', 'g'));
$$;

-- ---------- Public ----------
create or replace function doc_public() returns jsonb
language sql security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'slug', d.slug, 'titre', d.titre, 'categorie', d.categorie, 'description', d.description,
      'nom', f.nom, 'type', f.type, 'taille', f.taille, 'maj_le', f.maj_le)
    order by d.ordre, d.titre), '[]'::jsonb)
  from doc_documents d join doc_fichiers f on f.document_id = d.id
  where d.visible;
$$;

create or replace function doc_fichier(p_slug text) returns jsonb
language sql security definer set search_path = public as $$
  select jsonb_build_object('nom', f.nom, 'type', f.type, 'data', encode(f.data, 'base64'))
  from doc_documents d join doc_fichiers f on f.document_id = d.id
  where d.slug = p_slug and d.visible;
$$;

-- ---------- Comité ----------
create or replace function doc_admin_get(pwd text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not doc_is_admin(pwd) then raise exception 'Accès refusé'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'id', d.id, 'slug', d.slug, 'titre', d.titre, 'categorie', d.categorie, 'description', d.description,
      'ordre', d.ordre, 'visible', d.visible, 'nom', f.nom, 'type', f.type, 'taille', f.taille, 'maj_le', f.maj_le)
    order by d.ordre, d.titre), '[]'::jsonb)
    from doc_documents d left join doc_fichiers f on f.document_id = d.id);
end $$;

-- Crée (sans id) ou modifie (avec id) un document : {id, titre, categorie, description, ordre, visible}. Renvoie l'id.
create or replace function doc_admin_save(pwd text, p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_id bigint := nullif(p->>'id', '')::bigint; v_titre text := trim(coalesce(p->>'titre', '')); v_slug text; n int := 1;
begin
  if not doc_is_admin(pwd) then raise exception 'Accès refusé'; end if;
  if v_titre = '' then raise exception 'Titre manquant'; end if;
  if coalesce(p->>'categorie', '') not in ('reglements', 'calendriers', 'feuilles', 'formulaires', 'formations', 'comite') then raise exception 'Catégorie inconnue'; end if;
  if v_id is null then
    v_slug := coalesce(nullif(doc_slug(v_titre), ''), 'document');
    while exists (select 1 from doc_documents where slug = v_slug || case when n = 1 then '' else '-' || n end) loop n := n + 1; end loop;
    insert into doc_documents (slug, titre, categorie, description, ordre, visible)
    values (v_slug || case when n = 1 then '' else '-' || n end, v_titre, p->>'categorie', nullif(trim(p->>'description'), ''),
            coalesce((p->>'ordre')::int, 0), coalesce((p->>'visible')::boolean, true))
    returning id into v_id;
  else
    update doc_documents set titre = v_titre, categorie = p->>'categorie', description = nullif(trim(p->>'description'), ''),
      ordre = coalesce((p->>'ordre')::int, ordre), visible = coalesce((p->>'visible')::boolean, visible)
    where id = v_id;
    if not found then raise exception 'Document inconnu'; end if;
  end if;
  return v_id;
end $$;

-- Dépose ou remplace le fichier d'un document (p_data en base64)
create or replace function doc_admin_fichier(pwd text, p_id bigint, p_nom text, p_type text, p_data text) returns void
language plpgsql security definer set search_path = public as $$
declare b bytea;
begin
  if not doc_is_admin(pwd) then raise exception 'Accès refusé'; end if;
  if not exists (select 1 from doc_documents where id = p_id) then raise exception 'Document inconnu'; end if;
  b := decode(p_data, 'base64');
  if b is null or length(b) = 0 then raise exception 'Fichier vide'; end if;
  if length(b) > 8 * 1024 * 1024 then raise exception 'Fichier trop lourd (8 Mo au plus)'; end if;
  insert into doc_fichiers (document_id, nom, type, taille, data, maj_le)
  values (p_id, coalesce(nullif(trim(p_nom), ''), 'document'), coalesce(nullif(p_type, ''), 'application/octet-stream'), length(b), b, now())
  on conflict (document_id) do update set nom = excluded.nom, type = excluded.type, taille = excluded.taille, data = excluded.data, maj_le = now();
end $$;

create or replace function doc_admin_suppr(pwd text, p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not doc_is_admin(pwd) then raise exception 'Accès refusé'; end if;
  delete from doc_documents where id = p_id;
end $$;

-- ---------- Droits ----------
revoke execute on function doc_is_admin(text) from public, anon, authenticated;
grant execute on function
  doc_public(), doc_fichier(text),
  doc_admin_get(text), doc_admin_save(text, jsonb), doc_admin_fichier(text, bigint, text, text, text), doc_admin_suppr(text, bigint)
to anon;

-- ---------- Documents repris de volley83.fr (sans fichier : à déposer depuis l'Espace Comité) ----------
-- Feuilles électroniques non reprises (plus utilisées) ; Pitchoun' Volley et Tournoi International : sur leurs propres sites.
insert into doc_documents (slug, titre, categorie, ordre) values
  ('calendrier-general',             'Calendrier général CD Var 2026 / 2027',              'calendriers', 1),
  ('rpe-m11',                        'RPE Championnat M11',                                'reglements', 1),
  ('rpe-m13',                        'RPE Championnat M13',                                'reglements', 2),
  ('rpe-m15-4x4',                    'RPE Championnat M15 4x4',                            'reglements', 3),
  ('rpe-m15-6x6',                    'RPE Championnat M15 6x6',                            'reglements', 4),
  ('rpe-m18-4x4',                    'RPE Championnat M18 4x4',                            'reglements', 5),
  ('rpe-m18-6x6',                    'RPE Championnat M18 6x6',                            'reglements', 6),
  ('rpe-senior-accession-m21',       'RPE Championnat Senior Accession et M21',            'reglements', 7),
  ('rpe-competlib-4x4',              'RPE Championnat Compet''Lib 4x4',                    'reglements', 8),
  ('rpe-open',                       'RPE Championnats OPEN 2 contre 2 et 4 contre 4',     'reglements', 9),
  ('feuille-tournoi',                'Feuille de tournoi',                                 'feuilles', 1),
  ('feuille-tournoi-2x2-4x4',        'Feuille de match pour tournoi (2x2 et 4x4)',         'feuilles', 2),
  ('feuille-tournoi-6x6',            'Feuille de match pour tournoi 6x6',                  'feuilles', 3),
  ('feuille-m15-m18-5-sets',         'Feuille de match M15 - M18 - 5 sets',                'feuilles', 4),
  ('feuille-competlib-4x4',          'Feuille de match Compet''Lib 4x4',                   'feuilles', 5),
  ('demande-derogation',             'Demande de dérogation exceptionnelle',               'formulaires', 1),
  ('composition-equipe-pdf',         'Fiche de composition d''équipe (PDF)',               'formulaires', 2),
  ('composition-equipe-word',        'Fiche de composition d''équipe (Word)',              'formulaires', 3),
  ('recu-indemnites-marqueur',       'Reçu pour les indemnités de marqueur',               'formulaires', 4),
  ('presentation-cav-dre-1',         'Présentation CAV - DRE 1',                           'formations', 1),
  ('presentation-dre-2',             'Présentation DRE 2 - Accueil et Formation des jeunes', 'formations', 2),
  ('composition-commissions',        'Composition des Commissions',                        'comite', 1)
on conflict (slug) do nothing;
