-- =====================================================================
--  Espace club : connexion permanente des clubs du Comité du Var
--  Identifiant = n° de club FFVB (fac_clubs.numero), mot de passe créé par
--  le Comité (le club peut le changer ensuite).
--  Le club y retrouve : les tournois qu'il organise (OPEN, M15/M18 4x4,
--  plateaux Pitchoun') et l'accès à sa fiche de l'annuaire.
--
--  À lancer dans Supabase › SQL Editor (coller tout › Run).
--  Relançable sans risque : rien n'est supprimé.
--  Prérequis : scripts facturation (fac_clubs), championnats, clubs, Pitchoun'.
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

-- ---------- Tables ----------
create table if not exists ecl_comptes (
  club             text primary key references fac_clubs(code) on update cascade on delete cascade,
  mdp_hash         text,                      -- mot de passe chiffré (bcrypt), jamais en clair
  mdp_cree_le      timestamptz,               -- dernier mot de passe créé par le Comité
  mdp_change_le    timestamptz,               -- dernier changement par le club lui-même
  envoye_le        timestamptz,               -- identifiants envoyés par mail
  derniere_connexion timestamptz
);

create table if not exists ecl_sessions (
  jeton     text primary key,
  club      text not null references ecl_comptes(club) on update cascade on delete cascade,
  cree_le   timestamptz not null default now(),
  expire_le timestamptz not null
);

create table if not exists ecl_essais (       -- tentatives de connexion (limite anti-robot)
  id      bigint generated always as identity primary key,
  numero  text,
  ok      boolean not null default false,
  le      timestamptz not null default now()
);
create index if not exists ecl_essais_le on ecl_essais(le);

alter table ecl_comptes  enable row level security;
alter table ecl_sessions enable row level security;
alter table ecl_essais   enable row level security;
revoke all on ecl_comptes, ecl_sessions, ecl_essais from anon, authenticated;

-- ---------- Outils ----------
create or replace function ecl_is_admin(pwd text) returns boolean
language sql security definer set search_path = public as $$
  select exists (select 1 from private_config where key = 'admin_password' and value = pwd);
$$;

-- Nom simplifié pour comparer « Vidauban Volley-Ball » et « VIDAUBAN VOLLEY BALL »
create or replace function ecl_norm(t text) returns text
language sql immutable as $$
  select regexp_replace(lower(translate(coalesce(t, ''),
    'àâäáãéèêëíîïóôöõúùûüçÀÂÄÁÃÉÈÊËÍÎÏÓÔÖÕÚÙÛÜÇ', 'aaaaaeeeeiiiioooouuuucAAAAAEEEEIIIIOOOOUUUUC')), '[^a-z0-9]', '', 'g');
$$;

-- n° de club sans espaces ni zéros de tête : « 0839914 » = « 839914 »
create or replace function ecl_num(t text) returns text
language sql immutable as $$
  select nullif(ltrim(regexp_replace(coalesce(t, ''), '\D', '', 'g'), '0'), '');
$$;

-- Code aléatoire sans caractères ambigus (O/0, I/1, L)
create or replace function ecl_code(n int) returns text
language sql volatile as $$
  select string_agg(substr('ABCDEFGHJKMNPQRSTUVWXYZ23456789', 1 + floor(random() * 31)::int, 1), '') from generate_series(1, n);
$$;

-- Début de la saison en cours (1er août)
create or replace function ecl_debut_saison() returns date
language sql stable as $$
  select make_date(extract(year from current_date)::int - case when extract(month from current_date) < 8 then 1 else 0 end, 8, 1);
$$;

-- Club de la session (erreur si la session n'existe plus)
create or replace function ecl_club(p_jeton text) returns text
language plpgsql security definer set search_path = public as $$
declare c text;
begin
  select club into c from ecl_sessions where jeton = p_jeton and expire_le > now();
  if c is null then raise exception 'Session expirée : reconnectez-vous'; end if;
  return c;
end $$;

-- Ce plateau Pitchoun' est-il organisé par ce club ? (nom, autres noms ou adresse mail)
create or replace function ecl_pitchoun_du_club(p_org text, p_email text, f fac_clubs) returns boolean
language sql stable as $$
  select ecl_norm(p_org) <> '' and (
           ecl_norm(p_org) = ecl_norm(f.nom)
        or ecl_norm(p_org) in (select ecl_norm(a) from unnest(string_to_array(coalesce(f.alias, ''), ',')) a where trim(a) <> '')
        or exists (select 1 from clb_clubs k where k.code = f.code and ecl_norm(k.nom) = ecl_norm(p_org)))
      or (coalesce(trim(p_email), '') <> '' and lower(trim(p_email)) in
          (select lower(trim(e)) from unnest(string_to_array(coalesce(f.email, ''), ',')) e where trim(e) <> ''));
$$;

-- ---------- Club ----------
-- Connexion : n° de club + mot de passe → jeton de session (90 jours)
create or replace function ecl_login(p_numero text, p_mdp text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare f fac_clubs; k ecl_comptes; j text; n text := ecl_num(p_numero);
begin
  delete from ecl_essais where le < now() - interval '1 day';
  delete from ecl_sessions where expire_le < now();
  if (select count(*) from ecl_essais where not ok and numero = n and le > now() - interval '15 minutes') >= 8
     or (select count(*) from ecl_essais where not ok and le > now() - interval '15 minutes') >= 60 then
    return jsonb_build_object('erreur', 'Trop d''essais : réessayez dans un quart d''heure');
  end if;
  select * into f from fac_clubs where actif and ecl_num(numero) = n limit 1;
  if f.code is not null then select * into k from ecl_comptes where club = f.code; end if;
  if f.code is null or k.mdp_hash is null or k.mdp_hash <> crypt(coalesce(p_mdp, ''), k.mdp_hash) then
    -- pas d'exception ici : elle annulerait l'enregistrement de l'essai raté (limite anti-robot)
    insert into ecl_essais (numero, ok) values (n, false);
    return jsonb_build_object('erreur', 'N° de club ou mot de passe incorrect');
  end if;
  insert into ecl_essais (numero, ok) values (n, true);
  j := encode(gen_random_bytes(24), 'hex');
  insert into ecl_sessions (jeton, club, expire_le) values (j, f.code, now() + interval '90 days');
  update ecl_comptes set derniere_connexion = now() where club = f.code;
  return jsonb_build_object('jeton', j, 'club', f.code, 'nom', f.nom);
end $$;

create or replace function ecl_logout(p_jeton text) returns void
language sql security definer set search_path = public as $$
  delete from ecl_sessions where jeton = p_jeton;
$$;

-- Changement du mot de passe par le club (les autres sessions sont fermées)
create or replace function ecl_mdp(p_jeton text, p_ancien text, p_nouveau text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare c text := ecl_club(p_jeton); h text;
begin
  select mdp_hash into h from ecl_comptes where club = c;
  if h is null or h <> crypt(coalesce(p_ancien, ''), h) then raise exception 'Mot de passe actuel incorrect'; end if;
  if length(coalesce(p_nouveau, '')) < 8 then raise exception 'Le nouveau mot de passe doit faire au moins 8 caractères'; end if;
  update ecl_comptes set mdp_hash = crypt(p_nouveau, gen_salt('bf')), mdp_change_le = now() where club = c;
  delete from ecl_sessions where club = c and jeton <> p_jeton;
end $$;

-- Tout ce que voit le club connecté
create or replace function ecl_get(p_jeton text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c text := ecl_club(p_jeton); f fac_clubs; d date := ecl_debut_saison(); r record; pit jsonb := '[]';
begin
  select * into f from fac_clubs where code = c;

  -- Tournois OPEN / M15-M18 4x4 de la saison : un code club recevant est créé s'il manque
  update chp_tournois t set code_orga = t.competition || '-' || ecl_code(4)
   where t.organisateur = c and t.date >= d and coalesce(t.code_orga, '') = '';

  -- Plateaux Pitchoun' de la saison organisés par le club (si le Pitchoun' est installé)
  if to_regclass('public.pitchoun_plateaux') is not null and to_regclass('public.pitchoun_codes') is not null then
    for r in execute 'select id from pitchoun_plateaux where date >= $1 and ecl_pitchoun_du_club(organisateur, email, $2)' using d, f loop
      execute 'insert into pitchoun_codes (plateau_id, code) select $1, ''PIT-'' || ecl_code(4)
               where not exists (select 1 from pitchoun_codes where plateau_id = $1)' using r.id;
    end loop;
    execute $q$
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', p.id, 'date', p.date, 'heure', p.heure, 'lieu', p.lieu, 'ville', p.ville,
               'date_limite', p.date_limite, 'statut', coalesce(p.statut, 'ouvert'),
               'code', (select k.code from pitchoun_codes k where k.plateau_id = p.id),
               'nb_enfants', (select count(*) from pitchoun_inscriptions i where i.plateau_id = p.id),
               'nb_clubs', (select count(distinct i.club) from pitchoun_inscriptions i where i.plateau_id = p.id)
             ) order by p.date), '[]')
        from pitchoun_plateaux p
       where p.date >= $1 and ecl_pitchoun_du_club(p.organisateur, p.email, $2)$q$
      into pit using d, f;
  end if;

  return jsonb_build_object(
    'club', jsonb_build_object('code', f.code, 'nom', f.nom, 'numero', f.numero),
    'compte', (select jsonb_build_object('mdp_change_le', k.mdp_change_le, 'mdp_cree_le', k.mdp_cree_le) from ecl_comptes k where k.club = c),
    'fiche', (select jsonb_build_object('acces', k.acces, 'publiee', k.fiche is not null, 'en_attente', k.proposition is not null,
                                        'publie_le', k.publie_le, 'propose_le', k.propose_le)
                from clb_clubs k where k.code = c),
    'tournois', (select coalesce(jsonb_agg(jsonb_build_object(
                   'id', t.id, 'competition', t.competition, 'nom', p.nom, 'famille', p.famille, 'numero', t.numero,
                   'date', t.date, 'heure', t.heure, 'lieu', t.lieu, 'ville', t.ville, 'statut', t.statut,
                   'date_limite', t.date_limite, 'code', t.code_orga,
                   'nb_equipes', (select coalesce(sum(i.nb_equipes), 0) from chp_inscriptions i where i.tournoi_id = t.id),
                   'nb_clubs', (select count(distinct i.club) from chp_inscriptions i where i.tournoi_id = t.id)
                 ) order by t.date, p.ordre), '[]')
                 from chp_tournois t join chp_competitions p on p.code = t.competition
                where t.organisateur = c and t.date >= d),
    'plateaux', pit
  );
end $$;

-- ---------- Comité ----------
-- Liste des clubs et état de leur accès
create or replace function ecl_admin_get(pwd text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not ecl_is_admin(pwd) then raise exception 'Accès refusé'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
            'code', f.code, 'nom', f.nom, 'numero', f.numero, 'email', f.email,
            'acces', k.mdp_hash is not null, 'mdp_cree_le', k.mdp_cree_le, 'mdp_change_le', k.mdp_change_le,
            'envoye_le', k.envoye_le, 'derniere_connexion', k.derniere_connexion
          ) order by f.ordre, f.nom), '[]')
          from fac_clubs f left join ecl_comptes k on k.club = f.code
         where f.actif);
end $$;

-- p_action : 'nouveau' (crée un mot de passe, renvoyé une seule fois en clair), 'envoye' (mail envoyé), 'supprimer' (accès coupé)
create or replace function ecl_admin_acces(pwd text, p_club text, p_action text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare m text;
begin
  if not ecl_is_admin(pwd) then raise exception 'Accès refusé'; end if;
  if not exists (select 1 from fac_clubs where code = p_club) then raise exception 'Club inconnu'; end if;
  if p_action = 'nouveau' then
    if coalesce((select ecl_num(numero) from fac_clubs where code = p_club), '') = '' then
      raise exception 'Ce club n''a pas de n° de club dans la Facturation (onglet Clubs) : ajoutez-le d''abord';
    end if;
    m := ecl_code(4) || '-' || ecl_code(4);
    insert into ecl_comptes (club, mdp_hash, mdp_cree_le) values (p_club, crypt(m, gen_salt('bf')), now())
    on conflict (club) do update set mdp_hash = excluded.mdp_hash, mdp_cree_le = now(), mdp_change_le = null;
    delete from ecl_sessions where club = p_club;
    return jsonb_build_object('mdp', m);
  elsif p_action = 'envoye' then
    update ecl_comptes set envoye_le = now() where club = p_club;
  elsif p_action = 'supprimer' then
    delete from ecl_comptes where club = p_club;
  else
    raise exception 'Action inconnue';
  end if;
  return '{}'::jsonb;
end $$;

-- ---------- Droits ----------
revoke execute on function ecl_is_admin(text), ecl_club(text), ecl_code(int), ecl_pitchoun_du_club(text, text, fac_clubs)
  from public, anon, authenticated;
grant execute on function
  ecl_login(text, text),
  ecl_logout(text),
  ecl_mdp(text, text, text),
  ecl_get(text),
  ecl_admin_get(text),
  ecl_admin_acces(text, text, text)
to anon;

-- Contrôle : clubs sans n° de club (ils ne pourront pas se connecter)
select code, nom, numero from fac_clubs where actif and ecl_num(numero) is null;
