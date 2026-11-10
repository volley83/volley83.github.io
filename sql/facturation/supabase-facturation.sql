-- =====================================================================
--  Facturation aux clubs du Comité du Var de Volley-Ball
--  Catalogue d'articles (code comptable, désignation, prix), bordereaux
--  de facturation par club, paiements reçus et récapitulatif.
--  Ajouts automatiques : engagements des Compétitions OPEN, Pitchoun' Volley,
--  stages réglés par le club.
--
--  À lancer dans Supabase › SQL Editor (coller tout › Run).
--  Relançable sans risque : rien n'est supprimé, le catalogue et les clubs
--  ne sont ajoutés que s'ils n'existent pas encore.
--  Accès : mot de passe admin commun (table private_config).
-- =====================================================================

-- ---------- Tables ----------
create table if not exists fac_clubs (
  code      text primary key,                 -- sigle utilisé partout sur le site : VCHPL, FVV…
  numero    text,                             -- n° d'affiliation FFVB (0839914)
  nom       text not null,
  email     text,                             -- contact(s) général(aux), séparés par des virgules
  adresse   text,
  alias     text,                             -- autres écritures du nom (séparées par des virgules) pour les ajouts automatiques
  actif     boolean not null default true,
  ordre     int not null default 0
);

create table if not exists fac_articles (
  id           bigint generated always as identity primary key,
  code_compta  text,
  designation  text not null,
  prix         numeric(10,2) not null default 0,
  unite        text,                          -- équipe, match, licence… (affiché dans le choix)
  categorie    text,
  cle          text unique,                   -- article utilisé par les ajouts automatiques (open_O11, pitchoun, stage…)
  actif        boolean not null default true,
  ordre        int not null default 0
);

create table if not exists fac_bordereaux (
  id        bigint generated always as identity primary key,
  saison    text not null,                    -- 2026-2027
  numero    int not null,
  date      date,
  titre     text,                             -- facultatif : « Engagements », « Fin de saison »…
  statut    text not null default 'brouillon' check (statut in ('brouillon','envoye')),
  origine   text,                             -- 'ffvb' = bordereau établi sur le site fédéral (historique)
  created_at timestamptz not null default now(),
  unique (saison, numero)
);

create table if not exists fac_lignes (
  id            bigint generated always as identity primary key,
  bordereau_id  bigint not null references fac_bordereaux(id) on delete cascade,
  club          text not null references fac_clubs(code) on update cascade,
  article_id    bigint references fac_articles(id) on delete set null,
  date_ligne    date,
  code_compta   text,
  designation   text not null,
  quantite      numeric(10,2) not null default 1,
  prix          numeric(10,2) not null default 0,
  source        text,                         -- open:O11, pitchoun, stage:123 … (évite de facturer deux fois)
  ordre         int not null default 0,
  created_at    timestamptz not null default now()
);
alter table fac_lignes add column if not exists precisions text;
alter table fac_articles add column if not exists rubrique_ris int check (rubrique_ris between 1 and 5);  -- rubrique du RIS pour les pénalités   -- précisions sous la désignation (noms des enfants…)
alter table fac_bordereaux add column if not exists mail_contenu text;  -- liste « Ce bordereau comprend notamment » du mail aux clubs
create index if not exists fac_lignes_bord on fac_lignes(bordereau_id, club);

create table if not exists fac_paiements (
  id            bigint generated always as identity primary key,
  club          text not null references fac_clubs(code) on update cascade,
  saison        text not null,
  bordereau_id  bigint references fac_bordereaux(id) on delete set null,   -- null = à imputer sur les bordereaux les plus anciens
  date          date,
  montant       numeric(10,2) not null,
  mode          text,
  reference     text,
  remarque      text,
  created_at    timestamptz not null default now()
);

-- Relevés des Infractions Sportives (RIS) : les infractions sont facturées sur le prochain bordereau du club
create table if not exists fac_ris (
  id        bigint generated always as identity primary key,
  saison    text not null,
  numero    int not null,
  date      date not null default current_date,    -- « au 08 juin 2026 »
  remarque  text,
  created_at timestamptz not null default now(),
  unique (saison, numero)
);
create table if not exists fac_ris_items (
  id          bigint generated always as identity primary key,
  ris_id      bigint not null references fac_ris(id) on delete cascade,
  rubrique    int not null default 5 check (rubrique between 1 and 5),   -- 1 Dossiers … 5 Divers
  match       text,                                  -- n° de match ou tournoi
  club        text not null references fac_clubs(code) on update cascade,
  article_id  bigint references fac_articles(id) on delete set null,
  intitule    text not null,                         -- infraction relevée (texte du RIS et de la facture)
  montant     numeric(10,2) not null default 0,
  ordre       int not null default 0,
  created_at  timestamptz not null default now()
);

alter table fac_ris_items add column if not exists sans_sanction boolean not null default false;  -- infraction volontairement non facturée

-- Signalements d'infractions saisis par les personnes habilitées (arbitres, responsables de commission…)
create table if not exists fac_saisisseurs (
  id      bigint generated always as identity primary key,
  nom     text not null,
  email   text,
  code    text not null unique,                    -- code d'accès personnel à la page de signalement
  actif   boolean not null default true,
  created_at timestamptz not null default now()
);
create table if not exists fac_signalements (
  id            bigint generated always as identity primary key,
  saison        text not null,
  saisisseur_id bigint references fac_saisisseurs(id) on delete set null,
  auteur        text,
  date_match    date,
  match         text,
  club          text,
  article_id    bigint references fac_articles(id) on delete set null,
  nature        text not null,                     -- nature de l'infraction (texte choisi ou saisi)
  commentaire   text,
  statut        text not null default 'nouveau' check (statut in ('nouveau','integre','rejete')),
  motif_rejet   text,
  ris_item_id   bigint references fac_ris_items(id) on delete set null,
  traite_le     timestamptz,
  created_at    timestamptz not null default now()
);
alter table fac_ris_items add column if not exists commentaire text;   -- remarque interne (signalement…)
alter table fac_ris_items add column if not exists note text;          -- note explicative, imprimée sur le RIS et la facture
alter table fac_ris_items add column if not exists signalement_id bigint;

-- Rappels envoyés aux clubs pour les bordereaux non réglés
create table if not exists fac_rappels (
  id          bigint generated always as identity primary key,
  club        text not null references fac_clubs(code) on update cascade,
  saison      text not null,
  bordereaux  int[] not null default '{}',          -- numéros des bordereaux relancés
  montant     numeric(10,2),
  created_at  timestamptz not null default now()
);

create table if not exists fac_reglages (
  cle    text primary key,
  valeur jsonb
);

alter table fac_clubs add column if not exists email_finances text;   -- trésorier(s) : destinataires des factures
alter table fac_clubs      enable row level security;
alter table fac_articles   enable row level security;
alter table fac_bordereaux enable row level security;
alter table fac_lignes     enable row level security;
alter table fac_paiements  enable row level security;
alter table fac_reglages   enable row level security;
alter table fac_ris        enable row level security;
alter table fac_ris_items  enable row level security;
alter table fac_saisisseurs  enable row level security;
alter table fac_signalements enable row level security;
alter table fac_rappels      enable row level security;
revoke all on fac_clubs, fac_articles, fac_bordereaux, fac_lignes, fac_paiements, fac_reglages, fac_ris, fac_ris_items, fac_saisisseurs, fac_signalements, fac_rappels from anon, authenticated;

-- ---------- Outils ----------
create or replace function fac_is_admin(pwd text) returns boolean
language sql security definer set search_path = public as $$
  select exists (select 1 from private_config where key = 'admin_password' and value = pwd);
$$;

-- ---------- Lecture ----------
create or replace function fac_admin_get(pwd text, p_saison text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not fac_is_admin(pwd) then raise exception 'Accès refusé'; end if;
  return jsonb_build_object(
    'clubs',      (select coalesce(jsonb_agg(to_jsonb(c) order by c.ordre, c.nom), '[]') from fac_clubs c),
    'articles',   (select coalesce(jsonb_agg(to_jsonb(a) order by a.ordre, a.code_compta, a.designation), '[]') from fac_articles a),
    'reglages',   (select coalesce(jsonb_object_agg(r.cle, r.valeur), '{}') from fac_reglages r),
    'saisons',    (select coalesce(jsonb_agg(distinct b.saison), '[]') from fac_bordereaux b),
    'bordereaux', (select coalesce(jsonb_agg(to_jsonb(b) order by b.numero), '[]') from fac_bordereaux b where b.saison = p_saison),
    'lignes',     (select coalesce(jsonb_agg(to_jsonb(l) order by l.bordereau_id, l.club, l.ordre, l.id), '[]')
                   from fac_lignes l join fac_bordereaux b on b.id = l.bordereau_id where b.saison = p_saison),
    'paiements',  (select coalesce(jsonb_agg(to_jsonb(p) order by p.date nulls first, p.id), '[]') from fac_paiements p where p.saison = p_saison),
    'ris',        (select coalesce(jsonb_agg(to_jsonb(r) order by r.numero), '[]') from fac_ris r where r.saison = p_saison),
    'ris_items',  (select coalesce(jsonb_agg(to_jsonb(i) order by i.ris_id, i.rubrique, i.ordre, i.id), '[]')
                   from fac_ris_items i join fac_ris r on r.id = i.ris_id where r.saison = p_saison),
    'rappels',      (select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at), '[]') from fac_rappels x where x.saison = p_saison),
    'saisisseurs',  (select coalesce(jsonb_agg(to_jsonb(x) order by x.nom), '[]') from fac_saisisseurs x),
    'signalements', (select coalesce(jsonb_agg(to_jsonb(g) order by g.created_at desc), '[]') from fac_signalements g
                     where g.saison = p_saison or g.statut = 'nouveau')
  );
end $$;

-- Données des autres rubriques pour les ajouts automatiques
create or replace function fac_admin_sources(pwd text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_open jsonb := '[]'; v_open_t jsonb := '[]'; v_pit jsonb := '[]'; v_pit_saison text; v_pit_fin date;
        v_stg jsonb := '[]'; v_cde jsonb := '[]';
begin
  if not fac_is_admin(pwd) then raise exception 'Accès refusé'; end if;
  -- Compétitions OPEN et M15/M18 4x4 : équipes inscrites par club et par tournoi (tournois annulés exclus)
  if to_regclass('public.chp_inscriptions') is not null then
    execute $q$
      select coalesce(jsonb_agg(x order by x->>'competition', x->>'club', (x->>'numero')::int), '[]') from (
        select jsonb_build_object('competition', t.competition, 'numero', t.numero, 'date', t.date, 'club', i.club, 'nb', sum(i.nb_equipes)) x
        from chp_inscriptions i join chp_tournois t on t.id = i.tournoi_id
        where t.statut <> 'annule'
        group by t.competition, t.numero, t.date, i.club) s $q$ into v_open;
    execute $q$
      select coalesce(jsonb_agg(jsonb_build_object('competition', t.competition, 'nom', c.nom, 'numero', t.numero, 'date', t.date) order by c.ordre, t.numero), '[]')
      from chp_tournois t join chp_competitions c on c.code = t.competition where t.statut <> 'annule' $q$ into v_open_t;
  end if;
  -- Pitchoun' Volley : enfants ayant participé à au moins un plateau, par club ; date du dernier plateau
  if to_regclass('public.pitchoun_joueurs') is not null then
    execute $q$
      select coalesce(jsonb_agg(jsonb_build_object('club', j.club, 'nb', j.n) order by j.club), '[]')
      from (select club, count(*) n from pitchoun_joueurs where coalesce(plateaux, 0) > 0 group by club) j $q$ into v_pit;
    if to_regclass('public.pitchoun_reglages') is not null then
      execute $q$ select valeur::text from pitchoun_reglages where cle = 'saison' $q$ into v_pit_saison;
    end if;
    if to_regclass('public.pitchoun_plateaux') is not null then
      execute $q$ select max(date) from pitchoun_plateaux $q$ into v_pit_fin;
    end if;
  end if;
  if to_regclass('public.stg_convocations') is not null then
    -- Participations réglées par le club (mode « Autre : facturé au club » dans la gestion des stages)
    execute $q$
      select coalesce(jsonb_agg(jsonb_build_object(
          'id', c.id, 'stage', s.titre, 'type', s.type, 'date', s.date_debut, 'prenom', e.prenom, 'nom', e.nom, 'club', e.club,
          'montant', coalesce(c.montant, s.tarif * case when s.par_jour then greatest(coalesce(array_length(c.jours, 1), array_length(s.jours, 1), 1), 1) else 1 end, 0)
        ) order by s.date_debut, e.club, e.nom), '[]')
      from stg_convocations c join stg_stages s on s.id = c.stage_id join stg_enfants e on e.id = c.enfant_id
      where c.paiement_mode ilike '%factur%club%' $q$ into v_stg;
    -- Participation des clubs aux stages du Centre Départemental : stages terminés, enfants convoqués non absents
    execute $q$
      select coalesce(jsonb_agg(jsonb_build_object('stage_id', s.id, 'stage', s.titre, 'debut', s.date_debut, 'fin', coalesce(s.date_fin, s.date_debut),
          'jours', coalesce(s.date_fin, s.date_debut) - s.date_debut + 1,
          'enfants', (select coalesce(jsonb_agg(jsonb_build_object('prenom', e.prenom, 'nom', e.nom, 'club', e.club, 'reponse', c.reponse) order by e.nom, e.prenom), '[]')
                      from stg_convocations c join stg_enfants e on e.id = c.enfant_id
                      where c.stage_id = s.id and c.statut = 'convoque' and c.reponse <> 'absent')
        ) order by s.date_debut), '[]')
      from stg_stages s where coalesce(s.type, 'cde') = 'cde' and coalesce(s.date_fin, s.date_debut) < current_date $q$ into v_cde;
  end if;
  return jsonb_build_object('open', v_open, 'open_tournois', v_open_t, 'pitchoun', v_pit, 'pitchoun_saison', v_pit_saison,
                            'pitchoun_fin', v_pit_fin, 'stages', v_stg, 'cde', v_cde, 'aujourdhui', current_date);
end $$;

-- Pour la page des championnats : ce qui a déjà été facturé en OPEN et M15/M18 4x4, et les tarifs
create or replace function fac_admin_open_facture(pwd text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not fac_is_admin(pwd) then raise exception 'Accès refusé'; end if;
  return jsonb_build_object(
    'tarifs', (select valeur from fac_reglages where cle = 'open_tarifs'),
    'lignes', (select coalesce(jsonb_agg(jsonb_build_object('club', l.club, 'source', l.source, 'montant', l.quantite * l.prix,
                 'bordereau', b.numero, 'saison', b.saison, 'statut', b.statut) order by b.numero), '[]')
               from fac_lignes l join fac_bordereaux b on b.id = l.bordereau_id where l.source like 'open:%'));
end $$;

-- ---------- Clubs ----------
-- p = {code, numero, nom, email, email_finances, adresse, alias, actif, ordre, ancien_code?} ; p = {code, supprimer:true} pour supprimer
create or replace function fac_admin_club(pwd text, p jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare k text := upper(trim(p->>'code')); old text := nullif(upper(trim(coalesce(p->>'ancien_code', ''))), '');
begin
  if not fac_is_admin(pwd) then raise exception 'Accès refusé'; end if;
  if coalesce(k, '') = '' then raise exception 'Indiquez le sigle du club'; end if;
  if (p->>'supprimer')::boolean then
    if exists (select 1 from fac_lignes where club = k) or exists (select 1 from fac_paiements where club = k) then
      update fac_clubs set actif = false where code = k;   -- déjà facturé : on le masque seulement
    else delete from fac_clubs where code = k; end if;
    return;
  end if;
  if coalesce(trim(p->>'nom'), '') = '' then raise exception 'Indiquez le nom du club'; end if;
  if old is not null and old <> k then
    update fac_clubs set code = k where code = old;          -- les lignes et paiements suivent (on update cascade)
  end if;
  insert into fac_clubs (code, numero, nom, email, email_finances, adresse, alias, actif, ordre)
  values (k, nullif(trim(p->>'numero'), ''), trim(p->>'nom'), nullif(trim(p->>'email'), ''), nullif(trim(p->>'email_finances'), ''), nullif(trim(p->>'adresse'), ''),
          nullif(trim(p->>'alias'), ''), coalesce((p->>'actif')::boolean, true), coalesce(nullif(p->>'ordre', '')::int, 0))
  on conflict (code) do update set numero = excluded.numero, nom = excluded.nom, email = excluded.email, email_finances = excluded.email_finances,
    adresse = excluded.adresse, alias = excluded.alias, actif = excluded.actif, ordre = excluded.ordre;
end $$;

-- ---------- Articles ----------
-- p = {id?, code_compta, designation, prix, unite, categorie, actif, ordre} ; {id, supprimer:true}
create or replace function fac_admin_article(pwd text, p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare aid bigint := nullif(p->>'id', '')::bigint;
begin
  if not fac_is_admin(pwd) then raise exception 'Accès refusé'; end if;
  if (p->>'supprimer')::boolean then
    if exists (select 1 from fac_articles where id = aid and cle is not null) then
      raise exception 'Cet article sert aux ajouts automatiques : modifiez-le ou désactivez-le plutôt';
    end if;
    delete from fac_articles where id = aid; return aid;
  end if;
  if coalesce(trim(p->>'designation'), '') = '' then raise exception 'Indiquez la désignation'; end if;
  if aid is null then
    insert into fac_articles (designation) values (trim(p->>'designation')) returning id into aid;
  end if;
  update fac_articles set
    code_compta = nullif(trim(p->>'code_compta'), ''),
    designation = upper(trim(p->>'designation')),
    prix        = coalesce(nullif(replace(p->>'prix', ',', '.'), '')::numeric, 0),
    unite       = nullif(trim(p->>'unite'), ''),
    categorie   = nullif(trim(p->>'categorie'), ''),
    actif       = coalesce((p->>'actif')::boolean, true),
    ordre       = coalesce(nullif(p->>'ordre', '')::int, ordre),
    rubrique_ris = case when p ? 'rubrique_ris' then nullif(p->>'rubrique_ris', '')::int else rubrique_ris end
  where id = aid;
  return aid;
end $$;

-- ---------- Bordereaux ----------
-- p = {id?, saison, numero, date, titre, statut} ; {id, supprimer:true}
create or replace function fac_admin_bordereau(pwd text, p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare bid bigint := nullif(p->>'id', '')::bigint; v_num int;
begin
  if not fac_is_admin(pwd) then raise exception 'Accès refusé'; end if;
  if (p->>'supprimer')::boolean then delete from fac_bordereaux where id = bid; return bid; end if;
  if bid is null then
    v_num := coalesce(nullif(p->>'numero', '')::int,
                      (select coalesce(max(numero), 0) + 1 from fac_bordereaux where saison = p->>'saison'));
    if exists (select 1 from fac_bordereaux where saison = p->>'saison' and numero = v_num) then
      raise exception 'Le bordereau n° % existe déjà pour cette saison', v_num;
    end if;
    insert into fac_bordereaux (saison, numero, date) values (p->>'saison', v_num, coalesce(nullif(p->>'date', '')::date, current_date))
    returning id into bid;
  end if;
  update fac_bordereaux set
    numero = coalesce(nullif(p->>'numero', '')::int, numero),
    date   = case when p ? 'date' then nullif(p->>'date', '')::date else date end,
    titre  = case when p ? 'titre' then nullif(trim(p->>'titre'), '') else titre end,
    mail_contenu = case when p ? 'mail_contenu' then nullif(trim(p->>'mail_contenu'), '') else mail_contenu end,
    statut = case when p->>'statut' in ('brouillon','envoye') then p->>'statut' else statut end
  where id = bid;
  return bid;
end $$;

-- ---------- Lignes ----------
-- p_lignes = [{id?, bordereau_id, club, article_id, date_ligne, code_compta, designation, precisions, quantite, prix, source, ordre}]
-- p_suppr  = identifiants des lignes à supprimer
-- Renvoie les identifiants des lignes enregistrées, dans l'ordre reçu
drop function if exists fac_admin_lignes(text, jsonb, bigint[]);
create or replace function fac_admin_lignes(pwd text, p_lignes jsonb, p_suppr bigint[]) returns bigint[]
language plpgsql security definer set search_path = public as $$
declare l jsonb; ids bigint[] := '{}'; lid bigint; st text;
begin
  if not fac_is_admin(pwd) then raise exception 'Accès refusé'; end if;
  if exists (select 1 from fac_lignes x join fac_bordereaux b on b.id = x.bordereau_id where x.id = any(coalesce(p_suppr, '{}')) and b.statut = 'envoye') then
    raise exception 'Ce bordereau est marqué « envoyé » : rouvrez-le pour le modifier';
  end if;
  delete from fac_lignes where id = any(coalesce(p_suppr, '{}'));
  for l in select * from jsonb_array_elements(coalesce(p_lignes, '[]')) loop
    select statut into st from fac_bordereaux where id = (l->>'bordereau_id')::bigint;
    if st is null then raise exception 'Bordereau introuvable'; end if;
    if st = 'envoye' then raise exception 'Ce bordereau est marqué « envoyé » : rouvrez-le pour le modifier'; end if;
    if coalesce(trim(l->>'designation'), '') = '' then raise exception 'Une ligne n''a pas de désignation'; end if;
    lid := nullif(l->>'id', '')::bigint;
    if lid is null then
      insert into fac_lignes (bordereau_id, club, designation) values ((l->>'bordereau_id')::bigint, upper(l->>'club'), trim(l->>'designation'))
      returning id into lid;
    end if;
    update fac_lignes set
      club        = upper(l->>'club'),
      article_id  = nullif(l->>'article_id', '')::bigint,
      date_ligne  = nullif(l->>'date_ligne', '')::date,
      code_compta = nullif(trim(l->>'code_compta'), ''),
      designation = left(trim(l->>'designation'), 300),
      precisions  = case when l ? 'precisions' then nullif(left(trim(l->>'precisions'), 2000), '') else precisions end,
      quantite    = coalesce(nullif(replace(l->>'quantite', ',', '.'), '')::numeric, 1),
      prix        = coalesce(nullif(replace(l->>'prix', ',', '.'), '')::numeric, 0),
      source      = case when l ? 'source' then nullif(l->>'source', '') else source end,
      ordre       = coalesce(nullif(l->>'ordre', '')::int, ordre)
    where id = lid;
    ids := ids || lid;
  end loop;
  return ids;
end $$;

-- ---------- Paiements ----------
-- p = {id?, club, saison, bordereau_id, date, montant, mode, reference, remarque} ; {id, supprimer:true}
create or replace function fac_admin_paiement(pwd text, p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare pid bigint := nullif(p->>'id', '')::bigint;
begin
  if not fac_is_admin(pwd) then raise exception 'Accès refusé'; end if;
  if (p->>'supprimer')::boolean then delete from fac_paiements where id = pid; return pid; end if;
  if coalesce(nullif(replace(p->>'montant', ',', '.'), '')::numeric, 0) = 0 then raise exception 'Indiquez le montant'; end if;
  if pid is null then
    insert into fac_paiements (club, saison, montant) values (upper(p->>'club'), p->>'saison', 0) returning id into pid;
  end if;
  update fac_paiements set
    club         = upper(p->>'club'),
    saison       = p->>'saison',
    bordereau_id = nullif(p->>'bordereau_id', '')::bigint,
    date         = nullif(p->>'date', '')::date,
    montant      = replace(p->>'montant', ',', '.')::numeric,
    mode         = nullif(trim(p->>'mode'), ''),
    reference    = nullif(trim(p->>'reference'), ''),
    remarque     = nullif(trim(p->>'remarque'), '')
  where id = pid;
  return pid;
end $$;

-- RIS : p = {id?, saison, numero?, date, remarque} ; {id, supprimer:true}
create or replace function fac_admin_ris(pwd text, p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare rid bigint := nullif(p->>'id', '')::bigint; v_num int;
begin
  if not fac_is_admin(pwd) then raise exception 'Accès refusé'; end if;
  if (p->>'supprimer')::boolean then delete from fac_ris where id = rid; return rid; end if;
  if rid is null then
    v_num := coalesce(nullif(p->>'numero', '')::int, (select coalesce(max(numero), 0) + 1 from fac_ris where saison = p->>'saison'));
    if exists (select 1 from fac_ris where saison = p->>'saison' and numero = v_num) then raise exception 'Le RIS n° % existe déjà', v_num; end if;
    insert into fac_ris (saison, numero, date) values (p->>'saison', v_num, coalesce(nullif(p->>'date', '')::date, current_date)) returning id into rid;
  end if;
  update fac_ris set
    numero   = coalesce(nullif(p->>'numero', '')::int, numero),
    date     = coalesce(nullif(p->>'date', '')::date, date),
    remarque = case when p ? 'remarque' then nullif(trim(p->>'remarque'), '') else remarque end
  where id = rid;
  return rid;
end $$;

-- Infraction : p = {id?, ris_id, rubrique, match, club, article_id, intitule, montant, ordre} ; {id, supprimer:true}
create or replace function fac_admin_ris_item(pwd text, p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare iid bigint := nullif(p->>'id', '')::bigint;
begin
  if not fac_is_admin(pwd) then raise exception 'Accès refusé'; end if;
  if (p->>'supprimer')::boolean then delete from fac_ris_items where id = iid; return iid; end if;
  if coalesce(trim(p->>'intitule'), '') = '' then raise exception 'Indiquez l''infraction relevée'; end if;
  if coalesce(trim(p->>'club'), '') = '' then raise exception 'Indiquez le club'; end if;
  if iid is null then
    insert into fac_ris_items (ris_id, club, intitule) values ((p->>'ris_id')::bigint, upper(p->>'club'), trim(p->>'intitule')) returning id into iid;
  end if;
  update fac_ris_items set
    rubrique   = coalesce(nullif(p->>'rubrique', '')::int, rubrique),
    match      = nullif(trim(p->>'match'), ''),
    club       = upper(p->>'club'),
    article_id = nullif(p->>'article_id', '')::bigint,
    intitule   = left(trim(p->>'intitule'), 200),
    montant    = coalesce(nullif(replace(p->>'montant', ',', '.'), '')::numeric, 0),
    sans_sanction = coalesce((p->>'sans_sanction')::boolean, sans_sanction),
    commentaire = case when p ? 'commentaire' then nullif(trim(p->>'commentaire'), '') else commentaire end,
    note        = case when p ? 'note' then nullif(left(trim(p->>'note'), 300), '') else note end,
    ordre      = coalesce(nullif(p->>'ordre', '')::int, ordre)
  where id = iid;
  return iid;
end $$;

-- ---------- Signalements (page /ris/ pour les personnes habilitées) ----------
create or replace function fac_signal_qui(p_code text) returns fac_saisisseurs
language sql stable security definer set search_path = public as $$
  select * from fac_saisisseurs where actif and upper(code) = upper(trim(p_code));
$$;

create or replace function fac_signal_login(p_code text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare u fac_saisisseurs;
begin
  u := fac_signal_qui(p_code);
  if u.id is null then raise exception 'Code incorrect'; end if;
  return jsonb_build_object(
    'nom', u.nom,
    'clubs', (select coalesce(jsonb_agg(jsonb_build_object('code', c.code, 'nom', c.nom) order by c.code), '[]') from fac_clubs c where c.actif),
    'natures', (select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'designation', a.designation, 'categorie', a.categorie) order by a.ordre), '[]')
                from fac_articles a where a.actif and a.categorie in ('Pénalités', 'Forfaits', 'Arbitrage')),
    'mes', (select coalesce(jsonb_agg(jsonb_build_object('id', g.id, 'date_match', g.date_match, 'match', g.match, 'club', g.club, 'nature', g.nature,
              'commentaire', g.commentaire, 'statut', g.statut, 'motif_rejet', g.motif_rejet, 'created_at', g.created_at) order by g.created_at desc), '[]')
            from fac_signalements g where g.saisisseur_id = u.id and g.created_at > now() - interval '1 year'));
end $$;

-- p = {date_match, match, club, article_id, nature, commentaire}
create or replace function fac_signal_envoyer(p_code text, p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare u fac_saisisseurs; gid bigint; d date := nullif(p->>'date_match', '')::date;
begin
  u := fac_signal_qui(p_code);
  if u.id is null then raise exception 'Code incorrect'; end if;
  if (select count(*) from fac_signalements where saisisseur_id = u.id and created_at > now() - interval '1 hour') >= 60 then
    raise exception 'Trop de signalements en une heure, réessayez plus tard';
  end if;
  if coalesce(trim(p->>'nature'), '') = '' then raise exception 'Indiquez la nature de l''infraction'; end if;
  if coalesce(trim(p->>'club'), '') = '' then raise exception 'Indiquez le club concerné'; end if;
  if d is null then raise exception 'Indiquez la date du match'; end if;
  insert into fac_signalements (saison, saisisseur_id, auteur, date_match, match, club, article_id, nature, commentaire)
  values (case when extract(month from d) >= 7 then extract(year from d)::int || '-' || (extract(year from d)::int + 1)
               else (extract(year from d)::int - 1) || '-' || extract(year from d)::int end,
          u.id, u.nom, d, nullif(left(trim(p->>'match'), 80), ''), upper(left(trim(p->>'club'), 20)),
          (select id from fac_articles where id = nullif(p->>'article_id', '')::bigint),
          left(trim(p->>'nature'), 200), nullif(left(trim(p->>'commentaire'), 2000), ''))
  returning id into gid;
  return gid;
end $$;

create or replace function fac_signal_supprimer(p_code text, p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare u fac_saisisseurs;
begin
  u := fac_signal_qui(p_code);
  if u.id is null then raise exception 'Code incorrect'; end if;
  delete from fac_signalements where id = p_id and saisisseur_id = u.id and statut = 'nouveau';
end $$;

-- Personnes habilitées : p = {id?, nom, email, actif} ; {id, supprimer:true}. Le code est créé automatiquement.
create or replace function fac_admin_saisisseur(pwd text, p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare sid bigint := nullif(p->>'id', '')::bigint; c text;
begin
  if not fac_is_admin(pwd) then raise exception 'Accès refusé'; end if;
  if (p->>'supprimer')::boolean then delete from fac_saisisseurs where id = sid; return sid; end if;
  if coalesce(trim(p->>'nom'), '') = '' then raise exception 'Indiquez le nom'; end if;
  if sid is null then
    loop
      c := (select string_agg(substr('ABCDEFGHJKMNPQRSTUVWXYZ23456789', 1 + floor(random() * 31)::int, 1), '') from generate_series(1, 6));
      exit when not exists (select 1 from fac_saisisseurs where code = c);
    end loop;
    insert into fac_saisisseurs (nom, code) values (trim(p->>'nom'), c) returning id into sid;
  end if;
  update fac_saisisseurs set nom = trim(p->>'nom'), email = nullif(trim(p->>'email'), ''), actif = coalesce((p->>'actif')::boolean, true) where id = sid;
  return sid;
end $$;

-- Traitement d'un signalement : p = {action:'integrer', ris_id, item:{rubrique, match, club, article_id, intitule, montant, commentaire}}
--                               ou {action:'rejeter', motif} ou {action:'rouvrir'}
create or replace function fac_admin_signalement(pwd text, p_id bigint, p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare g fac_signalements; iid bigint; it jsonb := p->'item';
begin
  if not fac_is_admin(pwd) then raise exception 'Accès refusé'; end if;
  select * into g from fac_signalements where id = p_id;
  if g.id is null then raise exception 'Signalement introuvable'; end if;
  if p->>'action' = 'rejeter' then
    update fac_signalements set statut = 'rejete', motif_rejet = nullif(trim(p->>'motif'), ''), traite_le = now() where id = p_id;
    return null;
  elsif p->>'action' = 'rouvrir' then
    if g.ris_item_id is not null then raise exception 'Ce signalement est déjà dans un RIS : supprimez d''abord l''infraction du RIS'; end if;
    update fac_signalements set statut = 'nouveau', motif_rejet = null, traite_le = null where id = p_id;
    return null;
  elsif p->>'action' = 'integrer' then
    if g.statut = 'integre' and g.ris_item_id is not null then raise exception 'Déjà intégré à un RIS'; end if;
    iid := fac_admin_ris_item(pwd, jsonb_build_object('ris_id', p->>'ris_id', 'rubrique', it->>'rubrique', 'match', it->>'match', 'club', it->>'club',
             'article_id', it->>'article_id', 'intitule', it->>'intitule', 'montant', it->>'montant', 'ordre', 999));
    update fac_ris_items set commentaire = nullif(trim(it->>'commentaire'), ''), signalement_id = p_id where id = iid;
    update fac_signalements set statut = 'integre', ris_item_id = iid, traite_le = now() where id = p_id;
    return iid;
  end if;
  raise exception 'Action inconnue';
end $$;

create or replace function fac_admin_rappel(pwd text, p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare rid bigint;
begin
  if not fac_is_admin(pwd) then raise exception 'Accès refusé'; end if;
  insert into fac_rappels (club, saison, bordereaux, montant)
  values (upper(p->>'club'), p->>'saison', coalesce(array(select jsonb_array_elements_text(p->'bordereaux')::int), '{}'), nullif(p->>'montant', '')::numeric)
  returning id into rid;
  return rid;
end $$;

create or replace function fac_admin_reglage(pwd text, p_cle text, p_valeur jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not fac_is_admin(pwd) then raise exception 'Accès refusé'; end if;
  insert into fac_reglages (cle, valeur) values (p_cle, p_valeur) on conflict (cle) do update set valeur = excluded.valeur;
end $$;

-- ---------- Droits ----------
revoke execute on function fac_is_admin(text) from public, anon, authenticated;
grant execute on function
  fac_admin_get(text, text),
  fac_admin_sources(text),
  fac_admin_open_facture(text),
  fac_admin_club(text, jsonb),
  fac_admin_article(text, jsonb),
  fac_admin_bordereau(text, jsonb),
  fac_admin_lignes(text, jsonb, bigint[]),
  fac_admin_paiement(text, jsonb),
  fac_admin_reglage(text, text, jsonb),
  fac_admin_ris(text, jsonb),
  fac_admin_rappel(text, jsonb),
  fac_admin_ris_item(text, jsonb),
  fac_admin_saisisseur(text, jsonb),
  fac_admin_signalement(text, bigint, jsonb),
  fac_signal_login(text),
  fac_signal_envoyer(text, jsonb),
  fac_signal_supprimer(text, bigint)
to anon;
revoke execute on function fac_signal_qui(text) from public, anon, authenticated;

-- ---------- Clubs du Comité (n° d'affiliation des bordereaux FFVB) ----------
insert into fac_clubs (code, numero, nom, ordre) values
  ('CSB',   '0836712', 'Club Sportif Brignolais', 0),
  ('DVVB',  '0836296', 'Draguignan Union Club Var VB', 0),
  ('ESCS',  '0837939', 'ES Canton des Solliès', 0),
  ('FVV',   '0839557', 'Fréjus Var Volley', 0),
  ('LLVB',  '0834743', 'Le Luc Volley-Ball', 0),
  ('MVA',   '0833315', 'Mourillon Volley Asso', 0),
  ('RCVB',  '0833352', 'Rocbaron Club Volley-Ball', 0),
  ('SMCV',  '0836446', 'Sainte-Maxime Cogolin Volley', 0),
  ('SFBV',  '0833308', 'Six-Fours Beach Volley', 0),
  ('2SBVC', '0833309', 'Sud Sainte-Baume Volley Club', 0),
  ('UAV',   '0837903', 'Union Athlétique Valettoise', 0),
  ('VVB',   '0833351', 'Vidauban Volley-Ball', 0),
  ('VBO',   '0837251', 'Volley-Ball Ollioulais', 0),
  ('VCHPL', '0839914', 'Volley Club Hyères / Pierrefeu La Londe', 0),
  ('VCSM',  '0833353', 'Volley Club de Saint-Maximin', 0),
  ('VCM',   '0833310', 'Volley Club Méditerranée', 0),
  ('VCS',   '0833356', 'Volley Club Seynois', 0),
  ('VPG',   '0833350', 'Volley Pradétan Gardéen', 0)
on conflict (code) do nothing;
update fac_clubs set alias = 'Hyères, Pierrefeu, La Londe, VC Hyères' where code = 'VCHPL' and alias is null;
update fac_clubs set alias = 'Draguignan, Draguignan Var Volley-Ball' where code = 'DVVB' and alias is null;
update fac_clubs set alias = 'Sainte-Maxime, Ste-Maxime, Cogolin' where code = 'SMCV' and alias is null;
update fac_clubs set alias = 'Ollioules' where code = 'VBO' and alias is null;
update fac_clubs set alias = 'La Valette, UA Valettoise' where code = 'UAV' and alias is null;
update fac_clubs set alias = 'Fréjus' where code = 'FVV' and alias is null;
update fac_clubs set alias = 'Vidauban' where code = 'VVB' and alias is null;
update fac_clubs set alias = 'Le Luc' where code = 'LLVB' and alias is null;
update fac_clubs set alias = 'Mourillon' where code = 'MVA' and alias is null;
update fac_clubs set alias = 'Brignoles' where code = 'CSB' and alias is null;
update fac_clubs set alias = 'Six-Fours, Six Fours' where code = 'SFBV' and alias is null;
update fac_clubs set alias = 'La Seyne' where code = 'VCS' and alias is null;
update fac_clubs set alias = 'Le Pradet, La Garde, Pradétan' where code = 'VPG' and alias is null;
update fac_clubs set alias = 'Toulon, VCM' where code = 'VCM' and alias is null;
update fac_clubs set alias = 'Saint-Maximin' where code = 'VCSM' and alias is null;
update fac_clubs set alias = 'Rocbaron' where code = 'RCVB' and alias is null;
update fac_clubs set alias = 'Sainte-Baume, Sud Sainte Baume' where code = '2SBVC' and alias is null;
update fac_clubs set alias = 'Solliès, Sollies' where code = 'ESCS' and alias is null;

-- ---------- Catalogue (repris des bordereaux FFVB 2025-2026 et 2026-2027) ----------
do $$ begin
  if not exists (select 1 from fac_articles) then
    insert into fac_articles (code_compta, designation, prix, unite, categorie, cle, ordre) values
      (null,     'RÉAFFILIATION GSA FÉDÉRAL',                               140, 'club',     'Affiliation', null, 10),
      (null,     'RÉAFFILIATION GSA RÉGIONAL',                              125, 'club',     'Affiliation', null, 11),
      (null,     'RÉAFFILIATION AUTRE GSA',                                 125, 'club',     'Affiliation', null, 12),
      ('756000', 'ENGAGEMENTS SENIOR ACCESSION / M21 (100 € / ÉQUIPE)',     100, 'équipe',   'Engagements', null, 20),
      ('756000', 'ENGAGEMENTS M18 ET M15 (70 € / ÉQUIPE)',                   70, 'équipe',   'Engagements', null, 21),
      ('756000', 'ENGAGEMENTS M13 (100 € / ÉQUIPE)',                        100, 'équipe',   'Engagements', null, 22),
      ('756000', 'ENGAGEMENTS M11 (80 € / ÉQUIPE)',                          80, 'équipe',   'Engagements', null, 23),
      ('756000', 'ENGAGEMENTS COMPET''LIB (90 € / ÉQUIPE)',                  90, 'équipe',   'Engagements', null, 24),
      ('756010', 'ENGAGEMENT OPEN M15 4X4 FÉMININ',                          10, 'équipe',   'Compétitions OPEN', 'open_MFM', 30),
      ('756010', 'ENGAGEMENT OPEN M15 4X4 MASCULIN',                         10, 'équipe',   'Compétitions OPEN', 'open_M4M', 31),
      ('756010', 'ENGAGEMENT OPEN M18 4X4 FÉMININ',                          10, 'équipe',   'Compétitions OPEN', 'open_CFM', 32),
      ('756010', 'ENGAGEMENT OPEN M18 4X4 MASCULIN',                         10, 'équipe',   'Compétitions OPEN', 'open_C4M', 33),
      ('756010', 'ENGAGEMENT OPEN 2 CONTRE 2',                               10, 'équipe',   'Compétitions OPEN', 'open_O11', 34),
      ('756010', 'ENGAGEMENT OPEN 4 CONTRE 4',                               10, 'équipe',   'Compétitions OPEN', 'open_O13', 35),
      ('756020', 'ENGAGEMENT PITCHOUN'' VOLLEY (5 € / ENFANT / SAISON)',      5, 'enfant',   'Pitchoun'' Volley', 'pitchoun', 40),
      ('756030', 'ENGAGEMENTS BEACH VAR TOUR (10 € / JOUEUR)',               10, 'joueur',   'Beach', null, 50),
      (null,     'PARTICIPATION STAGE',                                       0, 'stagiaire','Stages', 'stage', 55),
      ('706003', 'INSCRIPTION TOURNOI INTERNATIONAL (160 € / ÉQUIPE)',      160, 'équipe',   'Tournoi International', null, 60),
      ('706009', 'INSCRIPTION FORMATION MARQUEUR (40 € / STAGIAIRE)',        40, 'stagiaire','Formations', null, 70),
      ('706100', 'INDEMNITÉS ARBITRAGE SENIOR ACCESSION (30 € / MATCH)',     30, 'match',    'Arbitrage', null, 80),
      ('706100', 'FRAIS DÉPLACEMENT ARBITRAGE SENIOR ACCESSION (16 € / MATCH)', 16, 'match', 'Arbitrage', null, 81),
      ('708800', 'ADHÉSIF POUR TRAÇAGE DE TERRAIN (4 € / ROULEAU)',           4, 'rouleau',  'Matériel', null, 90),
      ('756300', 'AIDE À L''EMPLOI (3 € / LICENCE)',                          3, 'licence',  'Aide à l''emploi', null, 100),
      ('771001', 'PÉNALITÉ RIS N°4 - RÉSULTAT NON SAISI',                    25, 'pénalité', 'Pénalités', null, 110),
      ('771001', 'PÉNALITÉ RIS N°4 - FEUILLE NON PARVENUE',                  50, 'pénalité', 'Pénalités', null, 111),
      ('771001', 'PÉNALITÉ RIS N°4 - FEUILLE MAL TENUE',                     15, 'pénalité', 'Pénalités', null, 112),
      ('771001', 'PÉNALITÉ RIS N°4 - DEMANDE DE MODIFICATION HORS DÉLAI',    20, 'pénalité', 'Pénalités', null, 113),
      ('771001', 'PÉNALITÉ RIS N°4 - DEMANDE DE REPORT DE RENCONTRE',        20, 'pénalité', 'Pénalités', null, 114),
      ('771001', 'PÉNALITÉ RIS N°4 - ÉQUIPE ABSENTE',                        50, 'pénalité', 'Pénalités', null, 115),
      ('771001', 'PÉNALITÉ RIS N°4 - ÉQUIPE ABSENTE TOURNOI FINAL',          95, 'pénalité', 'Pénalités', null, 116),
      ('771001', 'PÉNALITÉ RIS N°4 - AVERTISSEMENT ENTRAÎNEUR',              50, 'pénalité', 'Pénalités', null, 117),
      ('771001', 'PÉNALITÉ RIS N°4 - AVERTISSEMENT JOUEUR',                  50, 'pénalité', 'Pénalités', null, 118),
      ('771001', 'PÉNALITÉ RIS N°4 - LICENCE NON PRÉSENTÉE',                  5, 'pénalité', 'Pénalités', null, 119),
      ('771001', 'PÉNALITÉ RIS N°4 - ENGAGEMENT NON CONFORME',               30, 'équipe',   'Pénalités', null, 120);
  end if;
end $$;

-- ---------- Réglages par défaut ----------
insert into fac_reglages (cle, valeur) values
  ('open_tarifs', '[10, 35, 60]'),   -- par équipe : 1 tournoi, 2 tournois, 3 tournois ou plus
  ('emetteur', '"Comité du Var de Volley-Ball\nMaison des Sports du Var\n133, boulevard Général Brosset\n83200 Toulon\ncontact@volley83.fr"'),
  ('ris_pied', '"Maison des sports du Var – 133, Boulevard du Général Brosset - 83200 TOULON\nTéléphone : 06-13-30-34-25 / e-mail : contact@volley83.fr / www.volley83.fr\nN° Siret : 42463014300024 / Code APE : 9312 Z"'),
  ('mail_objet', '"Bordereau de facturation N° {numero} – saison {saison} – {club}"'),
  ('mail_modele', '"Madame la présidente, Monsieur le président,\n\nVeuillez trouver ci-joint le bordereau de facturation N° {numero} de votre club pour la saison {saison}, d''un montant de {montant}.\nCe bordereau comprend notamment :\n\n{contenu}\n\nEn cas de questions ou de demandes de précisions, n''hésitez pas à nous contacter.\nVous pouvez régler cette facture par virement, par chèque à l''ordre du Comité du Var de Volley-Ball, ou par carte bancaire : https://www.helloasso.com/associations/comite-du-var-de-volley-ball/paiements/paiement-des-clubs\n\nSportivement,\n\nEric CHASSAGNARD\nTrésorier\nComité du Var de Volley-Ball"'),
  ('rappel_objet', '"Rappel – facturation non réglée – {club}"'),
  ('rappel_modele', '"Madame la présidente, Monsieur le président,\n\nSauf erreur de notre part, nous n''avons pas encore reçu le règlement des sommes suivantes, dues par votre club pour la saison {saison} :\n\n{impayes}\n\nSoit un total restant dû de {reste}. Vous trouverez ci-joint le(s) bordereau(x) concerné(s).\n\nSi votre règlement est déjà parti, merci de ne pas tenir compte de ce message. Dans le cas contraire, nous vous remercions de bien vouloir procéder au paiement dans les meilleurs délais, par virement, par chèque à l''ordre du Comité du Var de Volley-Ball, ou par carte bancaire : https://www.helloasso.com/associations/comite-du-var-de-volley-ball/paiements/paiement-des-clubs\n\nEn cas de question ou de difficulté, n''hésitez pas à nous contacter.\n\nSportivement,\n\nEric CHASSAGNARD\nTrésorier\nComité du Var de Volley-Ball"'),
  ('mentions', '"Règlement à réception, par virement ou par chèque à l''ordre du Comité du Var de Volley-Ball, en rappelant le numéro de la facture."')
on conflict (cle) do nothing;

-- ---------- Tarifs 2026-2027 (document « Tarifs saison 2026 / 2027 ») ----------
-- Remplace une seule fois le catalogue de départ ; les articles créés à la main (ordre 999) sont gardés.
do $$ begin
  if coalesce((select valeur #>> '{}' from fac_reglages where cle = 'catalogue_version'), '1') < '2' then
    delete from fac_articles where cle is null and ordre < 999;
    update fac_articles set cle = 'stage_cde' where cle = 'stage';
    insert into fac_articles (code_compta, designation, prix, unite, categorie, cle, ordre) values
      (null,     'AFFILIATION CLUB DÉPARTEMENTAL / RÉGIONAL',                 125, 'club',      'Affiliation', null, 10),
      (null,     'AFFILIATION CLUB NATIONAL',                                 140, 'club',      'Affiliation', null, 11),
      ('756000', 'ENGAGEMENT SENIORS ET M21 (100 € / ÉQUIPE)',                100, 'équipe',    'Engagements', null, 20),
      ('756000', 'ENGAGEMENT COMPET''LIB (90 € / ÉQUIPE)',                     90, 'équipe',    'Engagements', null, 21),
      ('756000', 'ENGAGEMENT M18 ET M15 (70 € / ÉQUIPE)',                      70, 'équipe',    'Engagements', null, 22),
      ('756000', 'ENGAGEMENT M13 (100 € / ÉQUIPE)',                           100, 'équipe',    'Engagements', null, 23),
      ('756000', 'ENGAGEMENT M11 (80 € / ÉQUIPE)',                             80, 'équipe',    'Engagements', null, 24),
      ('756030', 'ENGAGEMENT BEACH – CHAMPIONNAT OPEN (26 €)',                 26, null,        'Beach', null, 50),
      ('771001', 'ENGAGEMENT NON CONFORME OPEN (30 €)',                        30, 'équipe',    'Pénalités', null, 109),
      ('771001', 'PÉNALITÉ RIS N°4 - IMPLANTATIONS COMMUNIQUÉES HORS DÉLAI', 200, 'pénalité',  'Pénalités', null, 110),
      ('771001', 'PÉNALITÉ RIS N°4 - DEMANDE DE MODIFICATION AU CALENDRIER HORS DÉLAI (J-10)', 30, 'pénalité', 'Pénalités', null, 111),
      ('771001', 'PÉNALITÉ RIS N°4 - DEMANDE DE REPORT DE MATCH',              20, 'pénalité',  'Pénalités', null, 112),
      ('771001', 'PÉNALITÉ RIS N°4 - ANNULATION D''IMPLANTATION SANS MOTIF (J-5)', 100, 'pénalité', 'Pénalités', null, 113),
      ('771001', 'PÉNALITÉ RIS N°4 - LICENCE NON PRÉSENTÉE',                    6, 'pénalité',  'Pénalités', null, 114),
      ('771001', 'PÉNALITÉ RIS N°4 - MANAGER NON RÉGLEMENTAIREMENT LICENCIÉ',  60, 'pénalité',  'Pénalités', null, 115),
      ('771001', 'PÉNALITÉ RIS N°4 - MANAGER NON RÉGLEMENTAIREMENT LICENCIÉ – CHAMPIONNATS JEUNES', 30, 'pénalité', 'Pénalités', null, 116),
      ('771001', 'PÉNALITÉ RIS N°4 - MISE EN PLACE EN RETARD',                 15, 'pénalité',  'Pénalités', null, 117),
      ('771001', 'PÉNALITÉ RIS N°4 - RÉSULTAT COMMUNIQUÉ HORS DÉLAI',          30, 'pénalité',  'Pénalités', null, 118),
      ('771001', 'PÉNALITÉ RIS N°4 - FEUILLE DE MATCH MAL TENUE',              20, 'pénalité',  'Pénalités', null, 119),
      ('771001', 'PÉNALITÉ RIS N°4 - FEUILLE DE MATCH PARVENUE HORS DÉLAI',    40, 'pénalité',  'Pénalités', null, 120),
      ('771001', 'PÉNALITÉ RIS N°4 - FEUILLE DE MATCH NON PARVENUE (+ DE 30 JOURS)', 50, 'pénalité', 'Pénalités', null, 121),
      ('771001', 'PÉNALITÉ RIS N°4 - ENVOI À MAUVAISE ADRESSE',                10, 'pénalité',  'Pénalités', null, 122),
      ('771001', 'PÉNALITÉ RIS N°4 - ENVOI INSUFFISAMMENT AFFRANCHI',          10, 'pénalité',  'Pénalités', null, 123),
      ('771001', 'PÉNALITÉ RIS N°4 - MAUVAISE FEUILLE UTILISÉE',               15, 'pénalité',  'Pénalités', null, 124),
      ('771001', 'PÉNALITÉ RIS N°4 - FORFAIT UN MATCH SENIOR',                120, 'forfait',   'Forfaits', null, 130),
      ('771001', 'PÉNALITÉ RIS N°4 - FORFAIT UN MATCH COMPET''LIB',            60, 'forfait',   'Forfaits', null, 131),
      ('771001', 'PÉNALITÉ RIS N°4 - FORFAIT UN MATCH JEUNE (M18 ET MOINS)',   60, 'forfait',   'Forfaits', null, 132),
      ('771001', 'PÉNALITÉ RIS N°4 - PÉNALITÉ SENIOR',                         60, 'pénalité',  'Forfaits', null, 133),
      ('771001', 'PÉNALITÉ RIS N°4 - PÉNALITÉ COMPET''LIB',                    30, 'pénalité',  'Forfaits', null, 134),
      ('771001', 'PÉNALITÉ RIS N°4 - PÉNALITÉ JEUNE',                          30, 'pénalité',  'Forfaits', null, 135),
      ('771001', 'PÉNALITÉ RIS N°4 - FORFAIT GÉNÉRAL SENIOR',                 420, 'forfait',   'Forfaits', null, 136),
      ('771001', 'PÉNALITÉ RIS N°4 - FORFAIT GÉNÉRAL COMPET''LIB',            210, 'forfait',   'Forfaits', null, 137),
      ('771001', 'PÉNALITÉ RIS N°4 - FORFAIT GÉNÉRAL JEUNE',                  210, 'forfait',   'Forfaits', null, 138),
      ('771001', 'PÉNALITÉ RIS N°4 - FORFAIT GÉNÉRAL SENIOR AVEC MODIFICATION DU CALENDRIER', 620, 'forfait', 'Forfaits', null, 139),
      ('771001', 'PÉNALITÉ RIS N°4 - FORFAIT GÉNÉRAL COMPET''LIB AVEC MODIFICATION DU CALENDRIER', 410, 'forfait', 'Forfaits', null, 140),
      ('771001', 'PÉNALITÉ RIS N°4 - FORFAIT GÉNÉRAL JEUNE AVEC MODIFICATION DU CALENDRIER', 620, 'forfait', 'Forfaits', null, 141),
      ('771001', 'PÉNALITÉ RIS N°4 - FORFAIT PHASE FINALE',                   100, 'forfait',   'Forfaits', null, 142),
      ('771001', 'PÉNALITÉ RIS N°4 - ABSENCE D''OBLIGATION D''ARBITRAGE',     120, 'pénalité',  'Arbitrage', null, 150),
      ('706100', 'INDEMNITÉS ARBITRAGE DÉPARTEMENTALE ACCESSION (30 € / MATCH)', 30, 'match',   'Arbitrage', null, 151),
      ('706100', 'INDEMNITÉS MARQUEUR DÉPARTEMENTALE ACCESSION (25 € / MATCH)',  25, 'match',   'Arbitrage', null, 152),
      ('706100', 'FRAIS DÉPLACEMENT ARBITRAGE DÉPARTEMENTALE ACCESSION (16 € / MATCH)', 16, 'match', 'Arbitrage', null, 153),
      ('706009', 'INSCRIPTION FORMATION MARQUEUR (40 € / STAGIAIRE)',          40, 'stagiaire', 'Formations', null, 160),
      ('706603', 'INSCRIPTION TOURNOI INTERNATIONAL (160 € / ÉQUIPE)',        160, 'équipe',    'Tournoi International', null, 165),
      ('756300', 'AIDE À L''EMPLOI (4 € / LICENCE)',                            4, 'licence',   'Divers', null, 170),
      ('708800', 'ADHÉSIF BLANC POUR TRAÇAGE DE TERRAIN (4 € / ROULEAU)',       4, 'rouleau',   'Divers', null, 171),
      ('708800', 'ADHÉSIF BLEU POUR TRAÇAGE DE TERRAIN (5 € / ROULEAU)',        5, 'rouleau',   'Divers', null, 172);
    insert into fac_articles (code_compta, designation, prix, unite, categorie, cle, ordre) values
      ('706001', 'PARTICIPATION STAGE CENTRE DÉPARTEMENTAL',                    0, 'stagiaire', 'Stages', 'stage_cde', 60),
      ('706002', 'PARTICIPATION STAGE BEACH',                                   0, 'stagiaire', 'Stages', 'stage_beach', 61),
      ('706003', 'PARTICIPATION DES CLUBS AUX STAGES DU CENTRE DÉPARTEMENTAL (12 € / JOUR)', 12, 'jour', 'Stages', 'cde_club', 62)
    on conflict (cle) do nothing;
    update fac_articles set code_compta = '706001', designation = 'PARTICIPATION STAGE CENTRE DÉPARTEMENTAL' where cle = 'stage_cde';
    update fac_articles set prix = 7, designation = 'ENGAGEMENT PITCHOUN'' VOLLEY (7 € / ENFANT / SAISON)' where cle = 'pitchoun';
    update fac_articles set designation = replace(designation, 'ENGAGEMENT OPEN M1', 'ENGAGEMENT M1') where cle like 'open_%';
    update fac_reglages set valeur = '[10, 35, 60]' where cle = 'open_tarifs' and valeur = '[10, 30, 50]';
    insert into fac_reglages (cle, valeur) values ('catalogue_version', '"2"') on conflict (cle) do update set valeur = '"2"';
  end if;
end $$;

-- ---------- Articles ajoutés en cours de saison (ajoutés une seule fois) ----------
insert into fac_articles (code_compta, designation, prix, unite, categorie, rubrique_ris, ordre)
select v.* from (values
  ('771001', 'PÉNALITÉ RIS N°4 - SANCTION TERRAIN - AVERTISSEMENT', 50::numeric, 'sanction', 'Pénalités', 5, 125),
  ('771001', 'PÉNALITÉ RIS N°4 - SANCTION TERRAIN - PÉNALITÉ', 100::numeric, 'sanction', 'Pénalités', 5, 126)
) as v(code_compta, designation, prix, unite, categorie, rubrique_ris, ordre)
where not exists (select 1 from fac_articles a where a.designation = v.designation);

-- ---------- Rubrique du RIS des pénalités (une seule fois, modifiable ensuite dans Articles) ----------
-- 1 Dossiers · 2 Licences · 3 Saisie des résultats et envoi des feuilles · 4 Feuille de match · 5 Divers
update fac_articles set rubrique_ris = case
    when designation ~* 'LICENCE|LICENCIÉ|QUALIFI|SURCLASSEMENT' then 2
    when designation ~* 'RÉSULTAT|PARVENUE|ADRESSE|AFFRANCHI' then 3
    when designation ~* 'MAL TENUE|MAUVAISE FEUILLE' then 4
    when designation ~* 'FORFAIT|ABSENTE|INCOMPLÈTE|PÉNALITÉ (SENIOR|COMPET|JEUNE)' then 1
    else 5 end
  where rubrique_ris is null and categorie in ('Pénalités', 'Forfaits', 'Arbitrage');

-- Message attendu : « Success. No rows returned »
