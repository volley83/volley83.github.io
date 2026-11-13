-- =====================================================================
--  Championnats du Comité du Var : M15 / M18 4x4 et tournois OPEN 2x2 / 4x4
--  Inscriptions en ligne, saisie des classements par le club recevant,
--  validation par le Comité, classement général.
--
--  À lancer UNE FOIS dans Supabase › SQL Editor (coller tout › Run).
--  Relançable sans risque : aucune donnée n'est supprimée, les tournois
--  déjà créés ne sont pas recréés.
--  Le mot de passe admin est le même que pour le TIP et les stages.
-- =====================================================================

-- ---------- Tables ----------
create table if not exists chp_competitions (
  code     text primary key,               -- code FFVB de la poule : M4M, MFM, C4M, CFM, O11, O13
  nom      text not null,
  famille  text not null check (famille in ('4x4','open')),
  sexe     text,                           -- F / M pour les championnats 4x4
  niveaux  text[] default '{}',            -- niveaux proposés à l'inscription (OPEN)
  ordre    int default 0
);

create table if not exists chp_clubs (
  code  text primary key,
  nom   text not null,
  ordre int default 0
);

create table if not exists chp_tournois (
  id            bigint generated always as identity primary key,
  competition   text not null references chp_competitions(code),
  numero        int not null,
  date          date not null,
  heure         text,
  lieu          text,
  ville         text,
  organisateur  text,                      -- club recevant
  email_orga    text,
  date_limite   date,
  heure_limite  text default '12:00',
  inscriptions  text not null default 'auto' check (inscriptions in ('auto','ouvertes','fermees')),
  statut        text not null default 'ouvert' check (statut in ('ouvert','saisi','valide','annule')),
  code_orga     text,                      -- code donné au club recevant pour saisir le classement
  remarque      text,
  unique (competition, numero)
);

create table if not exists chp_inscriptions (
  id            bigint generated always as identity primary key,
  tournoi_id    bigint not null references chp_tournois(id) on delete cascade,
  club          text not null,
  contact_nom   text,
  contact_email text,
  contact_tel   text,
  niveau        text,                      -- OPEN : Débutant, Intermédiaire, Débrouillé
  sexe          text,                      -- OPEN : Filles, Garçons, Mixte
  nb_equipes    int not null check (nb_equipes between 1 and 30),
  commentaire   text,
  created_at    timestamptz not null default now()
);

create table if not exists chp_resultats (
  tournoi_id  bigint not null references chp_tournois(id) on delete cascade,
  rang        int not null,
  equipe      text not null,
  club        text,
  primary key (tournoi_id, rang)
);

alter table chp_competitions enable row level security;
alter table chp_clubs        enable row level security;
alter table chp_tournois     enable row level security;
alter table chp_inscriptions enable row level security;
alter table chp_resultats    enable row level security;
revoke all on chp_competitions, chp_clubs, chp_tournois, chp_inscriptions, chp_resultats from anon, authenticated;

-- ---------- Outils ----------
create or replace function chp_is_admin(pwd text) returns boolean
language sql security definer set search_path = public as $$
  select exists (select 1 from private_config where key = 'admin_password' and value = pwd);
$$;

-- Inscriptions ouvertes ? (auto = de 6 semaines avant le tournoi jusqu'à la date limite à l'heure limite, heure de Paris)
create or replace function chp_ouvert(t chp_tournois) returns boolean
language sql stable as $$
  select case t.inscriptions
    when 'ouvertes' then true
    when 'fermees'  then false
    else t.date_limite is not null and t.statut = 'ouvert'
         and current_date >= t.date - 42                      -- ouverture 6 semaines avant le tournoi
         and (now() at time zone 'Europe/Paris') <= (t.date_limite + coalesce(nullif(t.heure_limite,''),'23:59')::time) + interval '2 hours'   -- tolérance de 2 h
  end;
$$;

-- ---------- Public ----------
create or replace function chp_public() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'competitions', (select coalesce(jsonb_agg(to_jsonb(c) order by c.ordre), '[]') from chp_competitions c),
    'clubs', (select coalesce(jsonb_agg(jsonb_build_object('code', k.code, 'nom', k.nom) order by k.ordre, k.nom), '[]') from chp_clubs k),
    'tournois', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', t.id, 'competition', t.competition, 'numero', t.numero, 'date', t.date, 'heure', t.heure,
        'lieu', t.lieu, 'ville', t.ville, 'organisateur', t.organisateur, 'date_limite', t.date_limite,
        'heure_limite', t.heure_limite, 'statut', t.statut, 'remarque', t.remarque, 'ouvert', chp_ouvert(t),
        'nb_inscrits', (select coalesce(sum(nb_equipes), 0) from chp_inscriptions i where i.tournoi_id = t.id),
        'resultats', case when t.statut = 'valide' then (select coalesce(jsonb_agg(jsonb_build_object('rang', r.rang, 'equipe', r.equipe, 'club', r.club) order by r.rang), '[]')
                                                         from chp_resultats r where r.tournoi_id = t.id) end
      ) order by t.date, t.competition), '[]') from chp_tournois t)
  );
$$;

-- Inscription d'un club. p_lignes = [{"nb":2}] (4x4) ou [{"niveau":"Débutant","sexe":"Filles","nb":2}, …] (OPEN)
create or replace function chp_inscrire(p_tournoi bigint, p_club text, p_contact jsonb, p_lignes jsonb, p_commentaire text, p_piege text)
returns int language plpgsql security definer set search_path = public as $$
declare t chp_tournois; l jsonb; n int := 0; nb int;
begin
  if coalesce(p_piege, '') <> '' then return 0; end if;                 -- robot
  select * into t from chp_tournois where id = p_tournoi;
  if t.id is null then raise exception 'Tournoi introuvable'; end if;
  if not chp_ouvert(t) then raise exception 'Les inscriptions sont closes pour ce tournoi'; end if;
  if coalesce(trim(p_club), '') = '' then raise exception 'Indiquez le club'; end if;
  if coalesce(trim(p_contact->>'email'), '') !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Adresse mail invalide'; end if;
  for l in select * from jsonb_array_elements(coalesce(p_lignes, '[]')) loop
    nb := coalesce(nullif(l->>'nb','')::int, 0);
    if nb < 1 then continue; end if;
    if nb > 30 then raise exception 'Nombre d''équipes trop élevé'; end if;
    insert into chp_inscriptions (tournoi_id, club, contact_nom, contact_email, contact_tel, niveau, sexe, nb_equipes, commentaire)
    values (t.id, left(trim(p_club), 120), left(trim(p_contact->>'nom'), 120), left(lower(trim(p_contact->>'email')), 160),
            left(trim(p_contact->>'tel'), 40), nullif(left(l->>'niveau', 40), ''), nullif(left(l->>'sexe', 20), ''), nb,
            nullif(left(trim(coalesce(p_commentaire, '')), 500), ''));
    n := n + nb;
  end loop;
  if n = 0 then raise exception 'Indiquez au moins une équipe'; end if;
  return n;
end $$;

-- ---------- Club recevant (code organisateur) ----------
create or replace function chp_orga_charger(p_tournoi bigint, p_code text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare t chp_tournois;
begin
  select * into t from chp_tournois where id = p_tournoi and code_orga is not null and upper(code_orga) = upper(trim(p_code));
  if t.id is null then raise exception 'Code incorrect pour ce tournoi'; end if;
  return jsonb_build_object(
    'tournoi', to_jsonb(t) - 'code_orga',
    'competition', (select to_jsonb(c) from chp_competitions c where c.code = t.competition),
    'inscriptions', (select coalesce(jsonb_agg(jsonb_build_object('club', i.club, 'niveau', i.niveau, 'sexe', i.sexe, 'nb', i.nb_equipes,
                       'contact', i.contact_nom, 'email', i.contact_email, 'tel', i.contact_tel) order by i.club), '[]')
                     from chp_inscriptions i where i.tournoi_id = t.id),
    'resultats', (select coalesce(jsonb_agg(jsonb_build_object('rang', r.rang, 'equipe', r.equipe, 'club', r.club) order by r.rang), '[]')
                  from chp_resultats r where r.tournoi_id = t.id),
    'equipes_connues', (select coalesce(jsonb_agg(distinct r.equipe), '[]') from chp_resultats r join chp_tournois t2 on t2.id = r.tournoi_id
                        where t2.competition = t.competition and t2.statut = 'valide')
  );
end $$;

-- p_rows = [{"rang":1,"equipe":"HYERES 1","club":"VCHPL"}, …] ; p_envoyer = true : envoi au Comité pour validation
create or replace function chp_orga_enregistrer(p_tournoi bigint, p_code text, p_rows jsonb, p_envoyer boolean)
returns text language plpgsql security definer set search_path = public as $$
declare t chp_tournois;
begin
  select * into t from chp_tournois where id = p_tournoi and code_orga is not null and upper(code_orga) = upper(trim(p_code));
  if t.id is null then raise exception 'Code incorrect pour ce tournoi'; end if;
  if t.statut = 'valide' then raise exception 'Ce classement a déjà été validé par le Comité'; end if;
  delete from chp_resultats where tournoi_id = t.id;
  insert into chp_resultats (tournoi_id, rang, equipe, club)
  select t.id, (r->>'rang')::int, left(upper(trim(r->>'equipe')), 80), nullif(left(r->>'club', 120), '')
  from jsonb_array_elements(p_rows) r where coalesce(trim(r->>'equipe'), '') <> '';
  if p_envoyer then update chp_tournois set statut = 'saisi' where id = t.id; end if;
  return (select statut from chp_tournois where id = t.id);
end $$;

-- ---------- Admin ----------
create or replace function chp_admin_get(pwd text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not chp_is_admin(pwd) then raise exception 'Accès refusé'; end if;
  return jsonb_build_object(
    'competitions', (select coalesce(jsonb_agg(to_jsonb(c) order by c.ordre), '[]') from chp_competitions c),
    'clubs', (select coalesce(jsonb_agg(to_jsonb(k) order by k.ordre, k.nom), '[]') from chp_clubs k),
    'tournois', (select coalesce(jsonb_agg(to_jsonb(t) || jsonb_build_object('ouvert', chp_ouvert(t)) order by t.date, t.competition), '[]') from chp_tournois t),
    'inscriptions', (select coalesce(jsonb_agg(to_jsonb(i) order by i.created_at), '[]') from chp_inscriptions i),
    'resultats', (select coalesce(jsonb_agg(to_jsonb(r) order by r.tournoi_id, r.rang), '[]') from chp_resultats r)
  );
end $$;

create or replace function chp_admin_save_tournoi(pwd text, t jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare tid bigint := nullif(t->>'id','')::bigint;
begin
  if not chp_is_admin(pwd) then raise exception 'Accès refusé'; end if;
  if tid is null then
    insert into chp_tournois (competition, numero, date) values (t->>'competition', (t->>'numero')::int, (t->>'date')::date)
    returning id into tid;
  end if;
  update chp_tournois set
    numero       = coalesce(nullif(t->>'numero','')::int, numero),
    date         = coalesce(nullif(t->>'date','')::date, date),
    heure        = case when t ? 'heure' then nullif(trim(t->>'heure'), '') else heure end,
    lieu         = case when t ? 'lieu' then nullif(trim(t->>'lieu'), '') else lieu end,
    ville        = case when t ? 'ville' then nullif(trim(t->>'ville'), '') else ville end,
    organisateur = case when t ? 'organisateur' then nullif(trim(t->>'organisateur'), '') else organisateur end,
    email_orga   = case when t ? 'email_orga' then nullif(trim(t->>'email_orga'), '') else email_orga end,
    date_limite  = case when t ? 'date_limite' then nullif(t->>'date_limite','')::date else date_limite end,
    heure_limite = case when t ? 'heure_limite' then nullif(trim(t->>'heure_limite'), '') else heure_limite end,
    inscriptions = case when t->>'inscriptions' in ('auto','ouvertes','fermees') then t->>'inscriptions' else inscriptions end,
    statut       = case when t->>'statut' in ('ouvert','saisi','valide','annule') then t->>'statut' else statut end,
    code_orga    = case when t ? 'code_orga' then nullif(upper(trim(t->>'code_orga')), '') else code_orga end,
    remarque     = case when t ? 'remarque' then nullif(trim(t->>'remarque'), '') else remarque end
  where id = tid;
  return tid;
end $$;

create or replace function chp_admin_delete_tournoi(pwd text, tid bigint) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not chp_is_admin(pwd) then raise exception 'Accès refusé'; end if;
  delete from chp_tournois where id = tid;
end $$;

-- Remplace le classement d'un tournoi ; p_valider = true : le tournoi compte au classement général
create or replace function chp_admin_resultats(pwd text, tid bigint, p_rows jsonb, p_valider boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not chp_is_admin(pwd) then raise exception 'Accès refusé'; end if;
  delete from chp_resultats where tournoi_id = tid;
  insert into chp_resultats (tournoi_id, rang, equipe, club)
  select tid, (r->>'rang')::int, left(upper(trim(r->>'equipe')), 80), nullif(left(r->>'club', 120), '')
  from jsonb_array_elements(p_rows) r where coalesce(trim(r->>'equipe'), '') <> '';
  if p_valider then update chp_tournois set statut = 'valide' where id = tid; end if;
end $$;

-- Renomme une équipe dans tous les tournois d'une compétition (fusion de deux noms)
create or replace function chp_admin_renommer(pwd text, p_comp text, p_ancien text, p_nouveau text) returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not chp_is_admin(pwd) then raise exception 'Accès refusé'; end if;
  update chp_resultats r set equipe = left(upper(trim(p_nouveau)), 80)
  from chp_tournois t where t.id = r.tournoi_id and t.competition = p_comp and r.equipe = p_ancien;
  get diagnostics n = row_count;
  return n;
end $$;

create or replace function chp_admin_inscription(pwd text, iid bigint, p jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not chp_is_admin(pwd) then raise exception 'Accès refusé'; end if;
  if iid is null then
    if coalesce(trim(p->>'club'), '') = '' then raise exception 'Indiquez le club'; end if;
    insert into chp_inscriptions (tournoi_id, club, contact_nom, contact_email, contact_tel, niveau, sexe, nb_equipes, commentaire)
    values ((p->>'tournoi_id')::bigint, left(trim(p->>'club'), 120), nullif(left(trim(coalesce(p->>'contact_nom', '')), 120), ''),
            nullif(left(lower(trim(coalesce(p->>'contact_email', ''))), 160), ''), nullif(left(trim(coalesce(p->>'contact_tel', '')), 40), ''),
            nullif(left(p->>'niveau', 40), ''), nullif(left(p->>'sexe', 20), ''),
            greatest(1, least(30, coalesce(nullif(p->>'nb_equipes', '')::int, 1))),
            nullif(left(trim(coalesce(p->>'commentaire', '')), 500), ''));
    return;
  end if;
  if p is null then delete from chp_inscriptions where id = iid; return; end if;
  update chp_inscriptions set
    nb_equipes = coalesce(nullif(p->>'nb_equipes','')::int, nb_equipes),
    niveau     = case when p ? 'niveau' then nullif(p->>'niveau','') else niveau end,
    sexe       = case when p ? 'sexe' then nullif(p->>'sexe','') else sexe end
  where id = iid;
end $$;

create or replace function chp_admin_club(pwd text, p_code text, p_nom text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not chp_is_admin(pwd) then raise exception 'Accès refusé'; end if;
  if coalesce(trim(p_nom), '') = '' then delete from chp_clubs where code = p_code; return; end if;
  insert into chp_clubs (code, nom, ordre) values (upper(trim(p_code)), trim(p_nom), 0)
  on conflict (code) do update set nom = excluded.nom;
end $$;

-- ---------- Droits ----------
revoke execute on function chp_is_admin(text), chp_ouvert(chp_tournois) from public, anon, authenticated;
grant execute on function
  chp_public(),
  chp_inscrire(bigint, text, jsonb, jsonb, text, text),
  chp_orga_charger(bigint, text),
  chp_orga_enregistrer(bigint, text, jsonb, boolean),
  chp_admin_get(text),
  chp_admin_save_tournoi(text, jsonb),
  chp_admin_delete_tournoi(text, bigint),
  chp_admin_resultats(text, bigint, jsonb, boolean),
  chp_admin_renommer(text, text, text, text),
  chp_admin_inscription(text, bigint, jsonb),
  chp_admin_club(text, text, text)
to anon;

-- ---------- Données de la saison 2026-2027 ----------
insert into chp_competitions (code, nom, famille, sexe, niveaux, ordre) values
  ('MFM', 'M15 4x4 féminin',  '4x4',  'F', '{}', 1),
  ('M4M', 'M15 4x4 masculin', '4x4',  'M', '{}', 2),
  ('CFM', 'M18 4x4 féminin',  '4x4',  'F', '{}', 3),
  ('C4M', 'M18 4x4 masculin', '4x4',  'M', '{}', 4),
  ('O11', 'OPEN 2 contre 2',  'open', null, '{Débutant,Intermédiaire,Débrouillé}', 5),
  ('O13', 'OPEN 4 contre 4',  'open', null, '{Débutant,Intermédiaire}', 6)
on conflict (code) do nothing;

-- Clubs : repris de la liste du Pitchoun' Volley si elle existe (modifiable ensuite dans l'admin)
do $$ begin
  if exists (select 1 from information_schema.tables where table_name = 'pitchoun_clubs') then
    execute 'insert into chp_clubs (code, nom, ordre) select code, nom, coalesce(ordre, 0) from pitchoun_clubs on conflict (code) do nothing';
  end if;
end $$;

insert into chp_tournois (competition, numero, date, heure, lieu, ville, date_limite) values
  -- M15 4x4 féminin
  ('MFM', 1, '2026-11-07', '13:30', 'Gymnase Costebelle', 'Hyères', '2026-11-05'),
  ('MFM', 2, '2026-12-05', '14:00', 'Gymnase Piemontesi', 'Ollioules', '2026-12-03'),
  ('MFM', 3, '2027-01-09', '13:00', 'Gymnase Costebelle', 'Hyères', '2027-01-07'),
  ('MFM', 4, '2027-02-13', '13:00', 'Gymnase Jean-Yves Gosse', 'Le Luc', '2027-02-11'),
  ('MFM', 5, '2027-03-27', null, null, null, '2027-03-25'),
  ('MFM', 6, '2027-05-09', null, null, null, '2027-05-06'),
  -- M15 4x4 masculin
  ('M4M', 1, '2026-11-07', '13:30', 'Gymnase Costebelle', 'Hyères', '2026-11-05'),
  ('M4M', 2, '2026-12-05', null, null, null, '2026-12-03'),
  ('M4M', 3, '2027-01-09', '16:30', 'Gymnase Costebelle', 'Hyères', '2027-01-07'),
  ('M4M', 4, '2027-02-13', null, null, null, '2027-02-11'),
  ('M4M', 5, '2027-03-27', null, null, null, '2027-03-25'),
  ('M4M', 6, '2027-05-09', '13:00', 'Gymnase Jean-Yves Gosse', 'Le Luc', '2027-05-06'),
  -- M18 4x4 féminin
  ('CFM', 1, '2026-10-10', '14:00', 'Gymnase Piemontesi', 'Ollioules', '2026-10-08'),
  ('CFM', 2, '2026-11-22', '09:00', 'Gymnase Jean Marcel', 'Brignoles', '2026-11-12'),
  ('CFM', 3, '2026-12-12', '16:00', 'Gymnase Jean-Yves Gosse', 'Le Luc', '2026-12-10'),
  ('CFM', 4, '2027-01-16', '13:00', 'Gymnase Les Lices', 'Toulon', '2027-01-14'),
  ('CFM', 5, '2027-02-07', '14:00', 'Gymnase Jean Marcel', 'Brignoles', '2027-02-04'),
  ('CFM', 6, '2027-03-20', '16:00', 'Gymnase Les Lices', 'Toulon', '2027-03-18'),
  ('CFM', 7, '2027-04-10', '13:00', 'Gymnase Costebelle', 'Hyères', '2027-04-08'),
  ('CFM', 8, '2027-05-15', '13:00', 'Gymnase Les Lices', 'Toulon', '2027-05-13'),
  -- M18 4x4 masculin
  ('C4M', 1, '2026-10-10', null, null, null, '2026-10-08'),
  ('C4M', 2, '2026-11-14', '13:00', 'Gymnase Costebelle', 'Hyères', '2026-11-12'),
  ('C4M', 3, '2026-12-12', '13:00', 'Gymnase Les Lices', 'Toulon', '2026-12-10'),
  ('C4M', 4, '2027-01-16', null, null, null, '2027-01-14'),
  ('C4M', 5, '2027-02-06', '13:00', 'Gymnase Jean-Yves Gosse', 'Le Luc', '2027-02-04'),
  ('C4M', 6, '2027-03-20', '13:00', 'Gymnase Les Lices', 'Toulon', '2027-03-18'),
  ('C4M', 7, '2027-04-10', null, null, null, '2027-04-08'),
  ('C4M', 8, '2027-05-15', '13:00', 'Gymnase Jean-Yves Gosse', 'Le Luc', '2027-05-13'),
  -- OPEN 2 contre 2
  ('O11', 1, '2026-11-21', '13:30', 'Collège P.-E. Victor', 'Vidauban', '2026-11-19'),
  ('O11', 2, '2027-01-10', '09:30', 'Gymnase Costebelle', 'Hyères', '2027-01-07'),
  ('O11', 3, '2027-01-23', '13:00', 'Gymnase Jean-Yves Gosse', 'Le Luc', '2027-01-21'),
  ('O11', 4, '2027-03-27', null, null, null, null),
  ('O11', 5, '2027-05-09', null, null, null, null),
  ('O11', 6, '2027-05-30', null, null, null, null),
  -- OPEN 4 contre 4
  ('O13', 1, '2026-11-08', '09:30', 'Gymnase Costebelle', 'Hyères', '2026-11-06'),
  ('O13', 2, '2026-12-13', '09:30', 'Collège P.-E. Victor', 'Vidauban', '2026-12-10'),
  ('O13', 3, '2027-01-17', '09:30', 'Gymnase Rostand', 'Draguignan', '2027-01-14'),
  ('O13', 4, '2027-02-07', '09:30', 'Collège P.-E. Victor', 'Vidauban', '2027-02-04'),
  ('O13', 5, '2027-03-14', null, null, null, null),
  ('O13', 6, '2027-04-11', null, null, null, null),
  ('O13', 7, '2027-05-16', null, null, null, null),
  ('O13', 8, '2027-05-30', null, null, null, null)
on conflict (competition, numero) do nothing;

-- ---------- Règles de la saison ----------
-- Clôture des inscriptions : le jeudi précédant le tournoi à 12 h
alter table chp_tournois alter column heure_limite set default '12:00';
alter table chp_tournois drop constraint if exists chp_tournois_statut_check;
alter table chp_tournois add constraint chp_tournois_statut_check check (statut in ('ouvert','saisi','valide','annule'));
update chp_tournois set heure_limite = '12:00' where heure_limite is null or heure_limite = '20:00';
update chp_tournois set date_limite = date - case when (extract(dow from date)::int + 3) % 7 = 0 then 7 else (extract(dow from date)::int + 3) % 7 end
 where date_limite is null or date_limite <> date - case when (extract(dow from date)::int + 3) % 7 = 0 then 7 else (extract(dow from date)::int + 3) % 7 end;
-- M18 masculin du 10 octobre : tournoi non joué
update chp_tournois set statut = 'annule' where competition = 'C4M' and numero = 1 and statut = 'ouvert';

-- Message attendu : « Success. No rows returned »

-- ---------- Adresses mail des clubs (bouton « Envoyer le code ») ----------
create or replace function chp_admin_mails(pwd text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not chp_is_admin(pwd) then raise exception 'Accès refusé'; end if;
  return (select coalesce(jsonb_object_agg(f.code, f.email), '{}'::jsonb)
          from fac_clubs f where coalesce(trim(f.email), '') <> '');
end $$;
revoke all on function chp_admin_mails(text) from public;
grant execute on function chp_admin_mails(text) to anon, authenticated;

create table if not exists chp_formules (
  id          bigserial primary key,
  famille     text not null default '4x4',          -- '4x4' (M15/M18) ou 'open'
  nb_equipes  int  not null,
  nom         text not null default '',
  poules      text not null default '',             -- ex. « 4 (joue sur 2 terrains), 3 »
  texte       text not null default '',
  updated_at  timestamptz not null default now()
);
alter table chp_formules enable row level security;   -- aucun accès direct : seulement par les fonctions ci-dessous

create or replace function chp_admin_formules(pwd text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not chp_is_admin(pwd) then raise exception 'Accès refusé'; end if;
  return coalesce((select jsonb_agg(to_jsonb(f) order by f.famille, f.nb_equipes, f.nom) from chp_formules f), '[]'::jsonb);
end $$;

-- fid null = nouvelle formule ; p null = suppression
create or replace function chp_admin_formule(pwd text, fid bigint, p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare nid bigint;
begin
  if not chp_is_admin(pwd) then raise exception 'Accès refusé'; end if;
  if p is null then delete from chp_formules where id = fid; return fid; end if;
  if fid is null then
    insert into chp_formules (famille, nb_equipes, nom, poules, texte)
    values (coalesce(nullif(p->>'famille', ''), '4x4'), (p->>'nb_equipes')::int, coalesce(p->>'nom', ''), coalesce(p->>'poules', ''), coalesce(p->>'texte', ''))
    returning id into nid;
    return nid;
  end if;
  update chp_formules set
    famille    = coalesce(nullif(p->>'famille', ''), famille),
    nb_equipes = coalesce(nullif(p->>'nb_equipes', '')::int, nb_equipes),
    nom        = coalesce(p->>'nom', nom),
    poules     = coalesce(p->>'poules', poules),
    texte      = coalesce(p->>'texte', texte),
    updated_at = now()
  where id = fid;
  return fid;
end $$;

grant execute on function chp_admin_formules(text) to anon, authenticated;
grant execute on function chp_admin_formule(text, bigint, jsonb) to anon, authenticated;

-- Première formule : 7 équipes (M15 / M18 4x4)
insert into chp_formules (famille, nb_equipes, nom, poules, texte)
select '4x4', 7, '1 poule de 4 + 1 poule de 3', '4 (joue sur 2 terrains), 3',
$t$1ERE PHASE

1 poule de 4 et 1 poule de 3.
Matchs en 1 set de 21 points.

Composition des poules :

{POULES}

3 rotations de matchs.
Ne pas perdre de temps entre les rencontres avec de longs échauffements au filet, mais privilégier le jeu.

2EME PHASE

Places 1 à 4 - Poule D : Matchs en 2 sets gagnants de 15 points - Tie-break en 11 points (joue sur 2 terrains)
1 - 1er poule A
2 - 1er poule B
3 - 2ème poule A
4 - 2ème poule B

Places 5 à 7 - Poule E : Matchs en 2 sets gagnants de 15 points - Tie-break en 11 points
1 - 3ème poule A
2 - 3ème poule B
3 - 4ème poule A$t$
where not exists (select 1 from chp_formules where famille = '4x4' and nb_equipes = 7);

-- 4 équipes (M15 / M18 4x4)
insert into chp_formules (famille, nb_equipes, nom, poules, texte)
select '4x4', 4, '1 poule de 4', '4',
$t$4 équipes engagées. 1 poule de 4.
Matchs en 2 sets gagnants de 25 points - Tie-break en 15 points.

Composition de la poule :

{POULES}

3 rotations de matchs.$t$
where not exists (select 1 from chp_formules where famille = '4x4' and nb_equipes = 4);

-- 3 équipes (M15 / M18 4x4)
insert into chp_formules (famille, nb_equipes, nom, poules, texte)
select '4x4', 3, '1 poule de 3', '3',
$t$3 équipes engagées. 1 poule de 3.
Matchs en 3 sets de 25 points (on joue les 3 sets quel que soit le score).

Composition de la poule :

{POULES}

3 rotations de matchs.$t$
where not exists (select 1 from chp_formules where famille = '4x4' and nb_equipes = 3);
