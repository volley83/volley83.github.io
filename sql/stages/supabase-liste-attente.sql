-- Liste d'attente des stages (ordre, activation manuelle des convocations)
-- À lancer une fois dans Supabase › SQL Editor. Relançable, aucune donnée supprimée.

alter table stg_convocations add column if not exists statut text not null default 'convoque' check (statut in ('convoque','attente'));
alter table stg_convocations add column if not exists rang_attente int;

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

grant execute on function stg_admin_attente_deplacer(text, bigint, int) to anon;

-- Message attendu : « Success. No rows returned »
