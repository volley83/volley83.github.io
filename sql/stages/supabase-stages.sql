-- =====================================================================
--  STAGES DU COMITÉ DU VAR — installation dans Supabase
--  À exécuter UNE FOIS : SQL Editor > New query > coller tout > Run.
--  Même projet Supabase que le TIP : l'accès admin utilise le même
--  mot de passe « accès complet » que le site du TIP.
--  Relançable sans risque : aucune donnée n'est supprimée.
--
--  Sécurité : les tables ne sont lisibles par personne depuis le site.
--  Le public passe uniquement par les fonctions ci-dessous :
--   - la liste des convoqués n'expose que prénom, nom et club ;
--   - un parent ne voit que son enfant, avec nom + année de naissance + code ;
--   - tout le reste demande le mot de passe admin.
-- =====================================================================

-- ---------- Tables ----------
create table if not exists stg_stages (
  id               bigint generated always as identity primary key,
  titre            text not null,
  categorie        text,
  date_debut       date not null,
  date_fin         date,
  lieu             text,
  horaires         text,
  tarif            numeric(8,2) default 0,
  date_limite      date,                       -- date limite de réponse des familles
  documents        text[] default array['Fiche de renseignements et autorisation parentale','Fiche sanitaire','Code de vie'],
  infos            text,                       -- matériel, programme…
  paiement_infos   text,                       -- comment payer
  points_url       text,                       -- lien du document des points travaillés (classeur)
  liste_publique   boolean default true,       -- afficher la liste des convoqués
  actif            boolean default true,       -- visible sur le site
  created_at       timestamptz default now()
);

create table if not exists stg_enfants (
  id               bigint generated always as identity primary key,
  nom              text not null,
  prenom           text not null,
  annee_naissance  int not null,                -- année de naissance (identification des familles)
  club             text,
  email_parent     text,
  code             text not null unique,
  created_at       timestamptz default now()
);
alter table stg_enfants add column if not exists docs_recus text[] default '{}';
alter table stg_enfants add column if not exists sexe text check (sexe in ('F','M'));  -- F = fille, M = garçon  -- documents fournis, valables pour la saison
-- (mise à jour d'une installation précédente : date de naissance remplacée par l'année)
alter table stg_enfants add column if not exists annee_naissance int;
do $$ begin
  if exists (select 1 from information_schema.columns where table_name = 'stg_enfants' and column_name = 'date_naissance') then
    update stg_enfants set annee_naissance = extract(year from date_naissance)::int where annee_naissance is null;
    alter table stg_enfants drop column date_naissance;
  end if;
end $$;
drop index if exists stg_enfants_identite;
create unique index if not exists stg_enfants_identite_annee
  on stg_enfants (lower(nom), lower(prenom), annee_naissance);
drop function if exists stg_find_child(text, date, text);
drop function if exists stg_parent_login(text, date, text);
drop function if exists stg_parent_repondre(text, date, text, bigint, text, text, text);

create table if not exists stg_convocations (
  id               bigint generated always as identity primary key,
  stage_id         bigint not null references stg_stages(id) on delete cascade,
  enfant_id        bigint not null references stg_enfants(id) on delete cascade,
  reponse          text not null default 'attente' check (reponse in ('attente','present','absent')),
  reponse_le       timestamptz,
  tel_parent       text,
  commentaire      text,
  docs_recus       text[] default '{}',
  paye             boolean default false,
  paiement_mode    text,
  paiement_date    date,
  montant          numeric(8,2),
  recu_num         text,
  created_at       timestamptz default now(),
  unique (stage_id, enfant_id)
);

alter table stg_stages add column if not exists points_url text;
alter table stg_convocations add column if not exists statut text not null default 'convoque' check (statut in ('convoque','attente'));  -- attente = liste d'attente
alter table stg_convocations add column if not exists rang_attente int;   -- ordre dans la liste d'attente (1, 2, 3…)
alter table stg_stages add column if not exists convocation_url text;     -- PDF de la convocation (filles et garçons, ou filles seulement si une convocation garçons est donnée)
alter table stg_stages add column if not exists convocation_url_m text;   -- PDF de la convocation des garçons, si différente
alter table stg_stages add column if not exists documents_liens jsonb default '{}'::jsonb;  -- {"Fiche sanitaire": "https://…"} : documents vierges à télécharger
alter table stg_convocations add column if not exists rappels timestamptz[] not null default '{}';  -- dates des rappels envoyés aux familles sans réponse
create sequence if not exists stg_recu_seq;

alter table stg_stages       enable row level security;
alter table stg_enfants      enable row level security;
alter table stg_convocations enable row level security;
revoke all on stg_stages, stg_enfants, stg_convocations from anon, authenticated;

-- ---------- Outils ----------
create or replace function stg_norm(t text) returns text
language sql immutable as $$
  select lower(regexp_replace(translate(coalesce(t,''),
    'ÀÁÂÃÄÅàáâãäåÇçÈÉÊËèéêëÌÍÎÏìíîïÑñÒÓÔÕÖòóôõöÙÚÛÜùúûüÝýÿ',
    'AAAAAAaaaaaaCcEEEEeeeeIIIIiiiiNnOOOOOoooooUUUUuuuuYyy'), '[^A-Za-z]', '', 'g'));
$$;

create or replace function stg_new_code() returns text
language plpgsql as $$
declare
  alphabet text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  c text;
begin
  loop
    c := '';
    for i in 1..4 loop
      c := c || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;
    exit when not exists (select 1 from stg_enfants where code = c);
  end loop;
  return c;
end $$;

-- Mot de passe admin (accès complet) : même table que le TIP
create or replace function stg_is_admin(pwd text) returns boolean
language sql security definer set search_path = public as $$
  select exists (select 1 from private_config where key = 'admin_password' and value = pwd);
$$;

-- Retrouve l'enfant d'un parent (nom + année de naissance + code)
create or replace function stg_find_child(p_nom text, p_annee int, p_code text)
returns bigint language sql security definer set search_path = public as $$
  select id from stg_enfants
  where code = upper(trim(p_code))
    and annee_naissance = p_annee
    and stg_norm(nom) = stg_norm(p_nom)
  limit 1;
$$;

-- ---------- Public : stages et convoqués ----------
create or replace function stg_public_stages()
returns jsonb language sql security definer set search_path = public as $$
  select coalesce(jsonb_agg(x order by (x->>'date_debut')), '[]'::jsonb) from (
    select jsonb_build_object(
      'id', s.id, 'titre', s.titre, 'categorie', s.categorie,
      'date_debut', s.date_debut, 'date_fin', s.date_fin, 'lieu', s.lieu,
      'horaires', s.horaires, 'tarif', s.tarif, 'date_limite', s.date_limite,
      'documents', s.documents, 'documents_liens', s.documents_liens, 'infos', s.infos, 'paiement_infos', s.paiement_infos,
      'liste_publique', s.liste_publique,
      'convoques', case when s.liste_publique then (
          select coalesce(jsonb_agg(jsonb_build_object('prenom', e.prenom, 'nom', e.nom, 'club', e.club, 'reponse', c.reponse, 'sexe', e.sexe, 'statut', c.statut, 'rang', c.rang_attente)
                 order by c.statut, c.rang_attente, e.nom, e.prenom), '[]'::jsonb)
          from stg_convocations c join stg_enfants e on e.id = c.enfant_id
          where c.stage_id = s.id) else null end
    ) as x
    from stg_stages s
    where s.actif and coalesce(s.date_fin, s.date_debut) >= current_date
  ) t;
$$;

-- ---------- Parents ----------
create or replace function stg_parent_login(p_nom text, p_annee int, p_code text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  eid bigint := stg_find_child(p_nom, p_annee, p_code);
  r jsonb;
begin
  if eid is null then return null; end if;
  select jsonb_build_object(
    'prenom', e.prenom, 'nom', e.nom, 'club', e.club, 'annee_naissance', e.annee_naissance,
    'convocations', coalesce((
      select jsonb_agg(jsonb_build_object(
        'stage_id', s.id, 'titre', s.titre, 'categorie', s.categorie,
        'date_debut', s.date_debut, 'date_fin', s.date_fin, 'lieu', s.lieu, 'horaires', s.horaires,
        'tarif', s.tarif, 'date_limite', s.date_limite, 'infos', s.infos, 'paiement_infos', s.paiement_infos, 'points_url', s.points_url,
        'convocation_url', case when e.sexe = 'M' and s.convocation_url_m is not null then s.convocation_url_m else s.convocation_url end,
        'documents', s.documents, 'documents_liens', s.documents_liens, 'docs_recus', e.docs_recus,
        'reponse', c.reponse, 'reponse_le', c.reponse_le, 'tel_parent', c.tel_parent, 'commentaire', c.commentaire,
        'paye', c.paye, 'paiement_mode', c.paiement_mode, 'paiement_date', c.paiement_date,
        'montant', c.montant, 'recu_num', c.recu_num, 'statut', c.statut,
        'rang_attente', case when c.statut = 'attente' then (select count(*) from stg_convocations c2
                          join stg_enfants e2 on e2.id = c2.enfant_id
                          where c2.stage_id = c.stage_id and c2.statut = 'attente' and c2.rang_attente <= c.rang_attente
                            and coalesce(e2.sexe, '?') = coalesce(e.sexe, '?')) end
      ) order by s.date_debut desc)
      from stg_convocations c join stg_stages s on s.id = c.stage_id
      where c.enfant_id = e.id and s.actif), '[]'::jsonb)
  ) into r
  from stg_enfants e where e.id = eid;
  return r;
end $$;

create or replace function stg_parent_repondre(p_nom text, p_annee int, p_code text,
  p_stage bigint, p_reponse text, p_tel text, p_commentaire text)
returns boolean language plpgsql security definer set search_path = public as $$
declare eid bigint := stg_find_child(p_nom, p_annee, p_code);
begin
  if eid is null or p_reponse not in ('present','absent') then return false; end if;
  update stg_convocations
     set reponse = p_reponse, reponse_le = now(),
         tel_parent = left(nullif(trim(p_tel), ''), 30),
         commentaire = left(nullif(trim(p_commentaire), ''), 500)
   where enfant_id = eid and stage_id = p_stage and statut = 'convoque';
  return found;
end $$;

-- ---------- Admin ----------
create or replace function stg_admin_get(pwd text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not stg_is_admin(pwd) then raise exception 'Accès refusé'; end if;
  return jsonb_build_object(
    'stages', (select coalesce(jsonb_agg(to_jsonb(s) order by s.date_debut desc), '[]'::jsonb) from stg_stages s),
    'convocations', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', c.id, 'stage_id', c.stage_id, 'enfant_id', e.id,
        'nom', e.nom, 'prenom', e.prenom, 'annee_naissance', e.annee_naissance, 'club', e.club, 'sexe', e.sexe,
        'email_parent', e.email_parent, 'code', e.code,
        'reponse', c.reponse, 'reponse_le', c.reponse_le, 'tel_parent', c.tel_parent, 'commentaire', c.commentaire,
        'docs_recus', e.docs_recus, 'paye', c.paye, 'paiement_mode', c.paiement_mode,
        'paiement_date', c.paiement_date, 'montant', c.montant, 'recu_num', c.recu_num,
        'statut', c.statut, 'rang_attente', c.rang_attente
      ) order by e.nom, e.prenom), '[]'::jsonb)
      from stg_convocations c join stg_enfants e on e.id = c.enfant_id)
  );
end $$;

create or replace function stg_admin_save_stage(pwd text, s jsonb)
returns bigint language plpgsql security definer set search_path = public as $$
declare sid bigint := nullif(s->>'id','')::bigint;
begin
  if not stg_is_admin(pwd) then raise exception 'Accès refusé'; end if;
  if sid is null then
    insert into stg_stages (titre, categorie, date_debut, date_fin, lieu, horaires, tarif, date_limite,
                            documents, documents_liens, infos, paiement_infos, points_url, liste_publique, actif)
    values (s->>'titre', s->>'categorie', (s->>'date_debut')::date, nullif(s->>'date_fin','')::date,
            s->>'lieu', s->>'horaires', coalesce(nullif(s->>'tarif','')::numeric, 0),
            nullif(s->>'date_limite','')::date,
            coalesce(array(select jsonb_array_elements_text(s->'documents')), '{}'),
            coalesce(s->'documents_liens', '{}'::jsonb),
            s->>'infos', s->>'paiement_infos', nullif(trim(s->>'points_url'), ''),
            coalesce((s->>'liste_publique')::boolean, true), coalesce((s->>'actif')::boolean, true))
    returning id into sid;
  else
    update stg_stages set
      titre = s->>'titre', categorie = s->>'categorie',
      date_debut = (s->>'date_debut')::date, date_fin = nullif(s->>'date_fin','')::date,
      lieu = s->>'lieu', horaires = s->>'horaires',
      tarif = coalesce(nullif(s->>'tarif','')::numeric, 0),
      date_limite = nullif(s->>'date_limite','')::date,
      documents = coalesce(array(select jsonb_array_elements_text(s->'documents')), '{}'),
      documents_liens = coalesce(s->'documents_liens', '{}'::jsonb),
      infos = s->>'infos', paiement_infos = s->>'paiement_infos', points_url = nullif(trim(s->>'points_url'), ''),
      liste_publique = coalesce((s->>'liste_publique')::boolean, true),
      actif = coalesce((s->>'actif')::boolean, true)
    where id = sid;
  end if;
  update stg_stages set
    convocation_url   = case when s ? 'convocation_url'   then nullif(trim(s->>'convocation_url'), '')   else convocation_url end,
    convocation_url_m = case when s ? 'convocation_url_m' then nullif(trim(s->>'convocation_url_m'), '') else convocation_url_m end
  where id = sid;
  return sid;
end $$;

create or replace function stg_admin_delete_stage(pwd text, sid bigint)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not stg_is_admin(pwd) then raise exception 'Accès refusé'; end if;
  delete from stg_stages where id = sid;
end $$;

-- Import d'une liste de convoqués : [{nom, prenom, annee_naissance, club, email_parent, sexe ('F'/'M'), docs_recus?}]
-- sid peut être null : les enfants sont alors seulement créés (codes, documents), sans convocation.
-- Un enfant déjà connu garde son code ; il est simplement ajouté au stage.
create or replace function stg_admin_import(pwd text, sid bigint, rows jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  r jsonb; eid bigint; nouveaux int := 0; ajoutes int := 0; st text; rg int;
begin
  if not stg_is_admin(pwd) then raise exception 'Accès refusé'; end if;
  for r in select * from jsonb_array_elements(rows) loop
    select id into eid from stg_enfants
     where lower(nom) = lower(trim(r->>'nom')) and lower(prenom) = lower(trim(r->>'prenom'))
       and annee_naissance = (r->>'annee_naissance')::int;
    if eid is null then
      insert into stg_enfants (nom, prenom, annee_naissance, club, email_parent, sexe, code)
      values (upper(trim(r->>'nom')), initcap(trim(r->>'prenom')), (r->>'annee_naissance')::int,
              nullif(trim(r->>'club'), ''), nullif(trim(r->>'email_parent'), ''), nullif(r->>'sexe', ''), stg_new_code())
      returning id into eid;
      nouveaux := nouveaux + 1;
    else
      update stg_enfants set
        club = coalesce(nullif(trim(r->>'club'), ''), club),
        email_parent = coalesce(nullif(trim(r->>'email_parent'), ''), email_parent),
        sexe = coalesce(nullif(r->>'sexe', ''), sexe)
      where id = eid;
    end if;
    if r ? 'docs_recus' then
      update stg_enfants set docs_recus = array(select distinct unnest(docs_recus || array(select jsonb_array_elements_text(r->'docs_recus'))))
       where id = eid;
    end if;
    if sid is not null then
      st := case when r->>'statut' = 'attente' then 'attente' else 'convoque' end;
      rg := null;
      if st = 'attente' then
        select coalesce(max(rang_attente), 0) + 1 into rg from stg_convocations where stage_id = sid and statut = 'attente';
      end if;
      insert into stg_convocations (stage_id, enfant_id, statut, rang_attente) values (sid, eid, st, rg)
      on conflict (stage_id, enfant_id) do nothing;
      if found then ajoutes := ajoutes + 1; end if;
    end if;
  end loop;
  return jsonb_build_object('nouveaux_enfants', nouveaux, 'ajoutes_au_stage', ajoutes);
end $$;

-- Mise à jour du suivi d'un enfant pour un stage (champs présents dans p uniquement)
create or replace function stg_admin_update_conv(pwd text, cid bigint, p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare c stg_convocations;
begin
  if not stg_is_admin(pwd) then raise exception 'Accès refusé'; end if;
  update stg_convocations set
    reponse       = case when p ? 'reponse' then p->>'reponse' else reponse end,
    reponse_le    = case when p ? 'reponse' and p->>'reponse' <> reponse then now() else reponse_le end,
    paye          = case when p ? 'paye' then (p->>'paye')::boolean else paye end,
    paiement_mode = case when p ? 'paiement_mode' then nullif(p->>'paiement_mode','') else paiement_mode end,
    paiement_date = case when p ? 'paiement_date' then nullif(p->>'paiement_date','')::date else paiement_date end,
    montant       = case when p ? 'montant' then nullif(p->>'montant','')::numeric else montant end,
    statut        = case when p->>'statut' in ('convoque','attente') then p->>'statut' else statut end,
    rang_attente  = case when p->>'statut' = 'convoque' then null
                         when p->>'statut' = 'attente' and statut <> 'attente' then
                           (select coalesce(max(c2.rang_attente), 0) + 1 from stg_convocations c2 where c2.stage_id = stg_convocations.stage_id and c2.statut = 'attente')
                         else rang_attente end
  where id = cid
  returning * into c;
  -- les documents fournis sont rattachés à l'enfant : valables pour tous ses stages de la saison
  if p ? 'docs_recus' then
    update stg_enfants set docs_recus = coalesce(array(select jsonb_array_elements_text(p->'docs_recus')), '{}')
     where id = c.enfant_id;
  end if;
  return to_jsonb(c) || jsonb_build_object('docs_recus', (select docs_recus from stg_enfants where id = c.enfant_id));
end $$;

-- Liste d'attente : monter (sens = -1) ou descendre (sens = 1) un enfant d'un cran (parmi les enfants du même sexe)
create or replace function stg_admin_attente_deplacer(pwd text, cid bigint, sens int)
returns void language plpgsql security definer set search_path = public as $$
declare c stg_convocations; v stg_convocations;
begin
  if not stg_is_admin(pwd) then raise exception 'Accès refusé'; end if;
  select * into c from stg_convocations where id = cid and statut = 'attente';
  if c.id is null then return; end if;
  if sens < 0 then
    select v2.* into v from stg_convocations v2 join stg_enfants e2 on e2.id = v2.enfant_id
     where v2.stage_id = c.stage_id and v2.statut = 'attente' and v2.rang_attente < c.rang_attente
       and coalesce(e2.sexe, '?') = (select coalesce(sexe, '?') from stg_enfants where id = c.enfant_id)
     order by v2.rang_attente desc limit 1;
  else
    select v2.* into v from stg_convocations v2 join stg_enfants e2 on e2.id = v2.enfant_id
     where v2.stage_id = c.stage_id and v2.statut = 'attente' and v2.rang_attente > c.rang_attente
       and coalesce(e2.sexe, '?') = (select coalesce(sexe, '?') from stg_enfants where id = c.enfant_id)
     order by v2.rang_attente limit 1;
  end if;
  if v.id is null then return; end if;
  update stg_convocations set rang_attente = v.rang_attente where id = c.id;
  update stg_convocations set rang_attente = c.rang_attente where id = v.id;
end $$;

create or replace function stg_admin_update_enfant(pwd text, eid bigint, p jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not stg_is_admin(pwd) then raise exception 'Accès refusé'; end if;
  update stg_enfants set
    nom = coalesce(upper(nullif(trim(p->>'nom'),'')), nom),
    prenom = coalesce(nullif(trim(p->>'prenom'),''), prenom),
    annee_naissance = coalesce(nullif(p->>'annee_naissance','')::int, annee_naissance),
    club = case when p ? 'club' then nullif(trim(p->>'club'),'') else club end,
    email_parent = case when p ? 'email_parent' then nullif(trim(p->>'email_parent'),'') else email_parent end,
    sexe = case when p ? 'sexe' then nullif(p->>'sexe','') else sexe end
  where id = eid;
end $$;

-- ---------- Reçus ----------
-- Un reçu n'est délivré que si : paiement enregistré, mode autre que « Autre (sans reçu) », et stage terminé.
-- Le numéro est attribué à la première édition, puis conservé (pas de numéro perdu en cas d'annulation).
create or replace function stg_recu_numero(cid bigint)
returns text language plpgsql security definer set search_path = public as $$
declare c stg_convocations; fin date;
begin
  select * into c from stg_convocations where id = cid;
  select coalesce(date_fin, date_debut) into fin from stg_stages where id = c.stage_id;
  if c.id is null or not c.paye or coalesce(c.paiement_mode, '') like 'Autre%' or fin >= current_date then return null; end if;
  if c.recu_num is null then
    update stg_convocations
       set recu_num = to_char(current_date, 'YYYY') || '-' || lpad(nextval('stg_recu_seq')::text, 4, '0')
     where id = cid returning recu_num into c.recu_num;
  end if;
  return c.recu_num;
end $$;

create or replace function stg_parent_recu(p_nom text, p_annee int, p_code text, p_stage bigint)
returns text language plpgsql security definer set search_path = public as $$
declare eid bigint := stg_find_child(p_nom, p_annee, p_code); cid bigint;
begin
  if eid is null then return null; end if;
  select id into cid from stg_convocations where enfant_id = eid and stage_id = p_stage;
  return stg_recu_numero(cid);
end $$;

create or replace function stg_admin_recu(pwd text, cid bigint)
returns text language plpgsql security definer set search_path = public as $$
begin
  if not stg_is_admin(pwd) then raise exception 'Accès refusé'; end if;
  return stg_recu_numero(cid);
end $$;

create or replace function stg_admin_remove_conv(pwd text, cid bigint)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not stg_is_admin(pwd) then raise exception 'Accès refusé'; end if;
  delete from stg_convocations where id = cid;
end $$;

-- Purge de fin de saison : supprime les enfants qui ne sont plus convoqués à aucun stage
create or replace function stg_admin_purge(pwd text)
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not stg_is_admin(pwd) then raise exception 'Accès refusé'; end if;
  delete from stg_enfants e where not exists (select 1 from stg_convocations c where c.enfant_id = e.id);
  -- (pour repartir de zéro en début de saison : supprimer d'abord les stages de la saison passée)
  get diagnostics n = row_count;
  return n;
end $$;

-- ---------- Droits : seules les fonctions sont appelables depuis le site ----------
revoke execute on function stg_norm(text), stg_new_code(), stg_is_admin(text), stg_find_child(text, int, text), stg_recu_numero(bigint) from public, anon, authenticated;
grant execute on function
  stg_public_stages(),
  stg_parent_login(text, int, text),
  stg_parent_repondre(text, int, text, bigint, text, text, text),
  stg_parent_recu(text, int, text, bigint),
  stg_admin_recu(text, bigint),
  stg_admin_get(text),
  stg_admin_save_stage(text, jsonb),
  stg_admin_delete_stage(text, bigint),
  stg_admin_import(text, bigint, jsonb),
  stg_admin_update_conv(text, bigint, jsonb),
  stg_admin_update_enfant(text, bigint, jsonb),
  stg_admin_remove_conv(text, bigint),
  stg_admin_attente_deplacer(text, bigint, int),
  stg_admin_purge(text)
to anon;

-- Message attendu : « Success. No rows returned »

-- (ajout) le compteur des reçus n'est utilisable que par les fonctions
revoke all on sequence stg_recu_seq from anon, authenticated;

-- =====================================================================
--  Inscription en ligne (beach-volley, stages d'été) — remplace les versions ci-dessus
-- =====================================================================
-- ---------- Nouvelles colonnes ----------
alter table stg_stages add column if not exists type        text not null default 'cde';  -- cde = Centre Départemental, beach, ete
alter table stg_stages add column if not exists inscription boolean not null default false; -- inscription en ligne ouverte à tous (sinon : sur convocation)
alter table stg_stages add column if not exists places      int;                          -- places maximum (par jour si par_jour)
alter table stg_stages add column if not exists par_jour    boolean not null default false; -- inscription possible à la journée
alter table stg_stages add column if not exists jours       date[];                       -- journées du stage (choix des familles)
alter table stg_stages add column if not exists contact     text;                         -- contact du stage (texte libre)
alter table stg_enfants add column if not exists licence    text;
alter table stg_enfants add column if not exists naissance  date;                         -- date de naissance complète (inscriptions en ligne)
alter table stg_convocations add column if not exists jours  date[];                      -- journées choisies (null = tout le stage)
alter table stg_convocations add column if not exists niveau text;                        -- niveau déclaré (beach…)
alter table stg_convocations add column if not exists source text;                        -- 'inscription' = formulaire en ligne
alter table stg_convocations add column if not exists email  text;                        -- mail donné à l'inscription

-- Documents déjà fournis avant le site (ex. stage beach d'octobre 2026) : reconnus à l'inscription par nom + prénom
create table if not exists stg_fiches_connues (
  nom_norm    text not null,
  prenom_norm text not null,
  docs        text[] not null,
  origine     text,
  primary key (nom_norm, prenom_norm)
);
alter table stg_fiches_connues enable row level security;
revoke all on stg_fiches_connues from anon, authenticated;

-- ---------- Places restantes par journée ----------
create or replace function stg_jours(s stg_stages) returns date[]
language sql stable as $$
  select coalesce(nullif(s.jours, '{}'),
    array(select d::date from generate_series(s.date_debut, coalesce(s.date_fin, s.date_debut), interval '1 day') d));
$$;

create or replace function stg_places_restantes(sid bigint) returns jsonb
language sql stable security definer set search_path = public as $$
  select case when s.places is null then null else coalesce((
    select jsonb_object_agg(d::text, s.places - (
      select count(*) from stg_convocations c
       where c.stage_id = s.id and c.statut = 'convoque' and c.reponse <> 'absent'
         and (c.jours is null or d = any(c.jours))))
    from unnest(stg_jours(s)) d), '{}'::jsonb) end
  from stg_stages s where s.id = sid;
$$;

-- ---------- Public ----------
create or replace function stg_public_stages()
returns jsonb language sql security definer set search_path = public as $$
  select coalesce(jsonb_agg(x order by (x->>'date_debut')), '[]'::jsonb) from (
    select jsonb_build_object(
      'id', s.id, 'titre', s.titre, 'categorie', s.categorie, 'type', s.type,
      'date_debut', s.date_debut, 'date_fin', s.date_fin, 'lieu', s.lieu,
      'horaires', s.horaires, 'tarif', s.tarif, 'date_limite', s.date_limite,
      'documents', s.documents, 'documents_liens', s.documents_liens, 'infos', s.infos, 'paiement_infos', s.paiement_infos,
      'inscription', s.inscription, 'places', s.places, 'par_jour', s.par_jour, 'jours', stg_jours(s), 'contact', s.contact,
      'restantes', stg_places_restantes(s.id),
      'nb_attente', (select count(*) from stg_convocations c where c.stage_id = s.id and c.statut = 'attente'),
      'liste_publique', s.liste_publique,
      'convoques', case when s.liste_publique then (
          select coalesce(jsonb_agg(jsonb_build_object('prenom', e.prenom, 'nom', e.nom, 'club', e.club, 'reponse', c.reponse, 'sexe', e.sexe, 'statut', c.statut, 'rang', c.rang_attente)
                 order by c.statut, c.rang_attente, e.nom, e.prenom), '[]'::jsonb)
          from stg_convocations c join stg_enfants e on e.id = c.enfant_id
          where c.stage_id = s.id) else null end
    ) as x
    from stg_stages s
    where s.actif and coalesce(s.date_fin, s.date_debut) >= current_date
  ) t;
$$;

-- Inscription en ligne. p = {stage_id, nom, prenom, naissance 'AAAA-MM-JJ', sexe, club, licence, email, tel, niveau, jours [...], commentaire, site (leurre)}
-- Renvoie {ok, statut ('convoque' = inscrit, 'attente'), rang, nouveau, code (seulement pour un nouvel enfant)} ou {ok:false, erreur}.
create or replace function stg_inscrire(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  s stg_stages; eid bigint; nouveau boolean := false; v_code text;
  v_nom text := upper(trim(coalesce(p->>'nom', '')));
  v_prenom text := initcap(trim(coalesce(p->>'prenom', '')));
  v_naiss date; v_jours date[]; st text := 'convoque'; rg int; d date; rest jsonb;
begin
  if coalesce(p->>'site', '') <> '' then return jsonb_build_object('ok', false, 'erreur', 'refus'); end if;
  select * into s from stg_stages where id = nullif(p->>'stage_id', '')::bigint;
  if s.id is null or not s.actif or not s.inscription then return jsonb_build_object('ok', false, 'erreur', 'stage'); end if;
  if s.date_debut <= current_date or (s.date_limite is not null and s.date_limite < current_date) then
    return jsonb_build_object('ok', false, 'erreur', 'clos'); end if;
  begin v_naiss := (p->>'naissance')::date; exception when others then v_naiss := null; end;
  if v_nom = '' or v_prenom = '' or v_naiss is null or extract(year from v_naiss) not between 1990 and extract(year from current_date)
     or coalesce(p->>'sexe', '') not in ('F', 'M') or coalesce(p->>'email', '') !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'
     or length(trim(coalesce(p->>'tel', ''))) < 8 then
    return jsonb_build_object('ok', false, 'erreur', 'champs'); end if;
  -- anti-abus : pas plus de 40 inscriptions en ligne par heure, tous stages confondus
  if (select count(*) from stg_convocations where source = 'inscription' and created_at > now() - interval '1 hour') >= 40 then
    return jsonb_build_object('ok', false, 'erreur', 'trop'); end if;

  if s.par_jour then
    v_jours := array(select distinct x::date from jsonb_array_elements_text(coalesce(p->'jours', '[]')) x
                      where x ~ '^\d{4}-\d{2}-\d{2}$' and x::date = any(stg_jours(s)) order by 1);
    if cardinality(v_jours) = 0 then return jsonb_build_object('ok', false, 'erreur', 'jours'); end if;
    if cardinality(v_jours) = cardinality(stg_jours(s)) then v_jours := null; end if;   -- tout le stage
  end if;

  perform pg_advisory_xact_lock(7300, s.id::int);   -- une inscription à la fois par stage (places)

  select id into eid from stg_enfants
   where stg_norm(nom) = stg_norm(v_nom) and stg_norm(prenom) = stg_norm(v_prenom)
     and annee_naissance = extract(year from v_naiss)::int
   limit 1;
  if eid is not null and exists (select 1 from stg_convocations where stage_id = s.id and enfant_id = eid) then
    return jsonb_build_object('ok', false, 'erreur', 'deja'); end if;

  if eid is null then
    v_code := stg_new_code();
    insert into stg_enfants (nom, prenom, annee_naissance, naissance, sexe, club, licence, email_parent, code)
    values (v_nom, v_prenom, extract(year from v_naiss)::int, v_naiss, p->>'sexe',
            nullif(left(trim(p->>'club'), 80), ''), nullif(left(trim(p->>'licence'), 20), ''),
            left(trim(p->>'email'), 120), v_code)
    returning id into eid;
    nouveau := true;
  else
    update stg_enfants set
      naissance = coalesce(naissance, v_naiss), sexe = coalesce(sexe, p->>'sexe'),
      club = coalesce(club, nullif(left(trim(p->>'club'), 80), '')),
      licence = coalesce(nullif(left(trim(p->>'licence'), 20), ''), licence),
      email_parent = coalesce(email_parent, left(trim(p->>'email'), 120))
    where id = eid;
  end if;

  -- documents déjà fournis avant le site (fiche de renseignements du stage beach d'octobre…)
  update stg_enfants e set docs_recus = array(select distinct unnest(coalesce(e.docs_recus, '{}') || f.docs))
    from stg_fiches_connues f
   where e.id = eid and f.nom_norm = stg_norm(e.nom) and f.prenom_norm = stg_norm(e.prenom);

  if s.places is not null then
    rest := stg_places_restantes(s.id);
    foreach d in array coalesce(v_jours, stg_jours(s)) loop
      if coalesce((rest->>d::text)::int, 0) <= 0 then st := 'attente'; end if;
    end loop;
  end if;
  if st = 'attente' then
    select coalesce(max(rang_attente), 0) + 1 into rg from stg_convocations where stage_id = s.id and statut = 'attente';
  end if;

  insert into stg_convocations (stage_id, enfant_id, statut, rang_attente, reponse, reponse_le, tel_parent, commentaire, jours, niveau, source, email)
  values (s.id, eid, st, rg, 'present', now(), left(trim(p->>'tel'), 30), nullif(left(trim(p->>'commentaire'), 500), ''),
          v_jours, nullif(left(trim(p->>'niveau'), 60), ''), 'inscription', left(trim(p->>'email'), 120));

  return jsonb_build_object('ok', true, 'statut', st, 'rang', rg, 'nouveau', nouveau,
    'code', case when nouveau then v_code end, 'prenom', (select prenom from stg_enfants where id = eid),
    'nom', (select nom from stg_enfants where id = eid), 'annee', extract(year from v_naiss)::int,
    'fiche', (select s.documents <@ docs_recus from stg_enfants where id = eid));
end $$;

-- ---------- Parents ----------
create or replace function stg_parent_login(p_nom text, p_annee int, p_code text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  eid bigint := stg_find_child(p_nom, p_annee, p_code);
  r jsonb;
begin
  if eid is null then return null; end if;
  select jsonb_build_object(
    'prenom', e.prenom, 'nom', e.nom, 'club', e.club, 'annee_naissance', e.annee_naissance,
    'convocations', coalesce((
      select jsonb_agg(jsonb_build_object(
        'stage_id', s.id, 'titre', s.titre, 'categorie', s.categorie, 'type', s.type, 'inscription', s.inscription,
        'date_debut', s.date_debut, 'date_fin', s.date_fin, 'lieu', s.lieu, 'horaires', s.horaires,
        'tarif', s.tarif, 'date_limite', s.date_limite, 'infos', s.infos, 'paiement_infos', s.paiement_infos, 'points_url', s.points_url,
        'par_jour', s.par_jour, 'jours_stage', stg_jours(s), 'contact', s.contact,
        'convocation_url', case when e.sexe = 'M' and s.convocation_url_m is not null then s.convocation_url_m else s.convocation_url end,
        'documents', s.documents, 'documents_liens', s.documents_liens, 'docs_recus', e.docs_recus,
        'reponse', c.reponse, 'reponse_le', c.reponse_le, 'tel_parent', c.tel_parent, 'commentaire', c.commentaire,
        'paye', c.paye, 'paiement_mode', c.paiement_mode, 'paiement_date', c.paiement_date,
        'montant', c.montant, 'recu_num', c.recu_num, 'statut', c.statut, 'jours', c.jours, 'niveau', c.niveau,
        'rang_attente', case when c.statut = 'attente' then (select count(*) from stg_convocations c2
                          join stg_enfants e2 on e2.id = c2.enfant_id
                          where c2.stage_id = c.stage_id and c2.statut = 'attente' and c2.rang_attente <= c.rang_attente
                            and (s.type <> 'cde' or coalesce(e2.sexe, '?') = coalesce(e.sexe, '?'))) end
      ) order by s.date_debut desc)
      from stg_convocations c join stg_stages s on s.id = c.stage_id
      where c.enfant_id = e.id and s.actif), '[]'::jsonb)
  ) into r
  from stg_enfants e where e.id = eid;
  return r;
end $$;

-- ---------- Admin ----------
create or replace function stg_admin_get(pwd text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not stg_is_admin(pwd) then raise exception 'Accès refusé'; end if;
  return jsonb_build_object(
    'stages', (select coalesce(jsonb_agg(to_jsonb(s) || jsonb_build_object('jours', stg_jours(s), 'restantes', stg_places_restantes(s.id))
                 order by s.date_debut desc), '[]'::jsonb) from stg_stages s),
    'convocations', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', c.id, 'stage_id', c.stage_id, 'enfant_id', e.id,
        'nom', e.nom, 'prenom', e.prenom, 'annee_naissance', e.annee_naissance, 'naissance', e.naissance, 'licence', e.licence,
        'club', e.club, 'sexe', e.sexe,
        'email_parent', coalesce(c.email, e.email_parent), 'code', e.code,
        'reponse', c.reponse, 'reponse_le', c.reponse_le, 'tel_parent', c.tel_parent, 'commentaire', c.commentaire, 'rappels', c.rappels,
        'docs_recus', e.docs_recus, 'paye', c.paye, 'paiement_mode', c.paiement_mode,
        'paiement_date', c.paiement_date, 'montant', c.montant, 'recu_num', c.recu_num,
        'statut', c.statut, 'rang_attente', c.rang_attente,
        'jours', c.jours, 'niveau', c.niveau, 'source', c.source, 'inscrit_le', c.created_at,
        'fiche_origine', (select f.origine from stg_fiches_connues f where f.nom_norm = stg_norm(e.nom) and f.prenom_norm = stg_norm(e.prenom))
      ) order by e.nom, e.prenom), '[]'::jsonb)
      from stg_convocations c join stg_enfants e on e.id = c.enfant_id)
  );
end $$;

create or replace function stg_admin_save_stage(pwd text, s jsonb)
returns bigint language plpgsql security definer set search_path = public as $$
declare sid bigint := nullif(s->>'id','')::bigint;
begin
  if not stg_is_admin(pwd) then raise exception 'Accès refusé'; end if;
  if sid is null then
    insert into stg_stages (titre, categorie, date_debut, date_fin, lieu, horaires, tarif, date_limite,
                            documents, documents_liens, infos, paiement_infos, points_url, liste_publique, actif)
    values (s->>'titre', s->>'categorie', (s->>'date_debut')::date, nullif(s->>'date_fin','')::date,
            s->>'lieu', s->>'horaires', coalesce(nullif(s->>'tarif','')::numeric, 0),
            nullif(s->>'date_limite','')::date,
            coalesce(array(select jsonb_array_elements_text(s->'documents')), '{}'),
            coalesce(s->'documents_liens', '{}'::jsonb),
            s->>'infos', s->>'paiement_infos', nullif(trim(s->>'points_url'), ''),
            coalesce((s->>'liste_publique')::boolean, true), coalesce((s->>'actif')::boolean, true))
    returning id into sid;
  else
    update stg_stages set
      titre = s->>'titre', categorie = s->>'categorie',
      date_debut = (s->>'date_debut')::date, date_fin = nullif(s->>'date_fin','')::date,
      lieu = s->>'lieu', horaires = s->>'horaires',
      tarif = coalesce(nullif(s->>'tarif','')::numeric, 0),
      date_limite = nullif(s->>'date_limite','')::date,
      documents = coalesce(array(select jsonb_array_elements_text(s->'documents')), '{}'),
      documents_liens = coalesce(s->'documents_liens', '{}'::jsonb),
      infos = s->>'infos', paiement_infos = s->>'paiement_infos', points_url = nullif(trim(s->>'points_url'), ''),
      liste_publique = coalesce((s->>'liste_publique')::boolean, true),
      actif = coalesce((s->>'actif')::boolean, true)
    where id = sid;
  end if;
  update stg_stages set
    convocation_url   = case when s ? 'convocation_url'   then nullif(trim(s->>'convocation_url'), '')   else convocation_url end,
    convocation_url_m = case when s ? 'convocation_url_m' then nullif(trim(s->>'convocation_url_m'), '') else convocation_url_m end,
    type        = case when s->>'type' in ('cde','beach','ete') then s->>'type' else type end,
    inscription = case when s ? 'inscription' then coalesce((s->>'inscription')::boolean, false) else inscription end,
    places      = case when s ? 'places' then nullif(s->>'places','')::int else places end,
    par_jour    = case when s ? 'par_jour' then coalesce((s->>'par_jour')::boolean, false) else par_jour end,
    contact     = case when s ? 'contact' then nullif(trim(s->>'contact'), '') else contact end,
    jours       = null   -- journées = du premier au dernier jour
  where id = sid;
  return sid;
end $$;

create or replace function stg_admin_update_conv(pwd text, cid bigint, p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare c stg_convocations;
begin
  if not stg_is_admin(pwd) then raise exception 'Accès refusé'; end if;
  update stg_convocations set
    reponse       = case when p ? 'reponse' then p->>'reponse' else reponse end,
    reponse_le    = case when p ? 'reponse' and p->>'reponse' <> reponse then now() else reponse_le end,
    paye          = case when p ? 'paye' then (p->>'paye')::boolean else paye end,
    paiement_mode = case when p ? 'paiement_mode' then nullif(p->>'paiement_mode','') else paiement_mode end,
    paiement_date = case when p ? 'paiement_date' then nullif(p->>'paiement_date','')::date else paiement_date end,
    montant       = case when p ? 'montant' then nullif(p->>'montant','')::numeric else montant end,
    jours         = case when p ? 'jours' then nullif(array(select jsonb_array_elements_text(p->'jours')::date order by 1), '{}') else jours end,
    niveau        = case when p ? 'niveau' then nullif(trim(p->>'niveau'), '') else niveau end,
    statut        = case when p->>'statut' in ('convoque','attente') then p->>'statut' else statut end,
    rang_attente  = case when p->>'statut' = 'convoque' then null
                         when p->>'statut' = 'attente' and statut <> 'attente' then
                           (select coalesce(max(c2.rang_attente), 0) + 1 from stg_convocations c2 where c2.stage_id = stg_convocations.stage_id and c2.statut = 'attente')
                         else rang_attente end
  where id = cid
  returning * into c;
  if p ? 'docs_recus' then
    update stg_enfants set docs_recus = coalesce(array(select jsonb_array_elements_text(p->'docs_recus')), '{}')
     where id = c.enfant_id;
  end if;
  return to_jsonb(c) || jsonb_build_object('docs_recus', (select docs_recus from stg_enfants where id = c.enfant_id));
end $$;

create or replace function stg_admin_attente_deplacer(pwd text, cid bigint, sens int)
returns void language plpgsql security definer set search_path = public as $$
declare c stg_convocations; v stg_convocations; mixte boolean;
begin
  if not stg_is_admin(pwd) then raise exception 'Accès refusé'; end if;
  select * into c from stg_convocations where id = cid and statut = 'attente';
  if c.id is null then return; end if;
  select type <> 'cde' into mixte from stg_stages where id = c.stage_id;   -- beach, été : une seule liste d'attente
  select v2.* into v from stg_convocations v2 join stg_enfants e2 on e2.id = v2.enfant_id
   where v2.stage_id = c.stage_id and v2.statut = 'attente'
     and (case when sens < 0 then v2.rang_attente < c.rang_attente else v2.rang_attente > c.rang_attente end)
     and (mixte or coalesce(e2.sexe, '?') = (select coalesce(sexe, '?') from stg_enfants where id = c.enfant_id))
   order by case when sens < 0 then -v2.rang_attente else v2.rang_attente end limit 1;
  if v.id is null then return; end if;
  update stg_convocations set rang_attente = v.rang_attente where id = c.id;
  update stg_convocations set rang_attente = c.rang_attente where id = v.id;
end $$;

create or replace function stg_admin_update_enfant(pwd text, eid bigint, p jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not stg_is_admin(pwd) then raise exception 'Accès refusé'; end if;
  update stg_enfants set
    nom = coalesce(upper(nullif(trim(p->>'nom'),'')), nom),
    prenom = coalesce(nullif(trim(p->>'prenom'),''), prenom),
    annee_naissance = coalesce(nullif(p->>'annee_naissance','')::int, annee_naissance),
    club = case when p ? 'club' then nullif(trim(p->>'club'),'') else club end,
    email_parent = case when p ? 'email_parent' then nullif(trim(p->>'email_parent'),'') else email_parent end,
    sexe = case when p ? 'sexe' then nullif(p->>'sexe','') else sexe end,
    licence = case when p ? 'licence' then nullif(trim(p->>'licence'),'') else licence end
  where id = eid;
end $$;

-- Rappel aux familles sans réponse : enregistre la date de l'envoi pour chaque convocation (frères et sœurs compris)
create or replace function stg_admin_rappel(pwd text, cids bigint[])
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not stg_is_admin(pwd) then raise exception 'Accès refusé'; end if;
  update stg_convocations set rappels = coalesce(rappels, '{}') || now() where id = any(cids);
  return (select coalesce(jsonb_object_agg(id::text, to_jsonb(rappels)), '{}'::jsonb) from stg_convocations where id = any(cids));
end $$;

-- ---------- Droits ----------
revoke execute on function stg_jours(stg_stages), stg_places_restantes(bigint) from public, anon, authenticated;
grant execute on function stg_inscrire(jsonb) to anon;
grant execute on function stg_admin_rappel(text, bigint[]) to anon;
