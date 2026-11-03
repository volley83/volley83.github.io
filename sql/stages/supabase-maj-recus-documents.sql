-- Mise à jour : documents vierges à télécharger, reçus seulement après le stage, mode « Autre (sans reçu) ».
-- À lancer une fois dans Supabase › SQL Editor.
alter table stg_stages add column if not exists documents_liens jsonb default '{}'::jsonb;

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
          select coalesce(jsonb_agg(jsonb_build_object('prenom', e.prenom, 'nom', e.nom, 'club', e.club, 'reponse', c.reponse, 'sexe', e.sexe)
                 order by e.nom, e.prenom), '[]'::jsonb)
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
        'montant', c.montant, 'recu_num', c.recu_num
      ) order by s.date_debut desc)
      from stg_convocations c join stg_stages s on s.id = c.stage_id
      where c.enfant_id = e.id and s.actif), '[]'::jsonb)
  ) into r
  from stg_enfants e where e.id = eid;
  return r;
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
    montant       = case when p ? 'montant' then nullif(p->>'montant','')::numeric else montant end
  where id = cid
  returning * into c;
  -- les documents fournis sont rattachés à l'enfant : valables pour tous ses stages de la saison
  if p ? 'docs_recus' then
    update stg_enfants set docs_recus = coalesce(array(select jsonb_array_elements_text(p->'docs_recus')), '{}')
     where id = c.enfant_id;
  end if;
  return to_jsonb(c) || jsonb_build_object('docs_recus', (select docs_recus from stg_enfants where id = c.enfant_id));
end $$;

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

revoke execute on function stg_recu_numero(bigint) from public, anon, authenticated;
grant execute on function stg_parent_recu(text, int, text, bigint), stg_admin_recu(text, bigint) to anon;
-- Message attendu : « Success. No rows returned »
