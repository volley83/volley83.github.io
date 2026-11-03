-- Mise à jour : séparation filles / garçons.
-- À lancer une fois dans Supabase › SQL Editor (remplace aussi supabase-maj-liste-publique.sql).
alter table stg_enfants add column if not exists sexe text check (sexe in ('F','M'));
-- Les enfants déjà enregistrés sont les filles de la saison (liste d'octobre) :
update stg_enfants set sexe = 'F' where sexe is null;

create or replace function stg_public_stages()
returns jsonb language sql security definer set search_path = public as $$
  select coalesce(jsonb_agg(x order by (x->>'date_debut')), '[]'::jsonb) from (
    select jsonb_build_object(
      'id', s.id, 'titre', s.titre, 'categorie', s.categorie,
      'date_debut', s.date_debut, 'date_fin', s.date_fin, 'lieu', s.lieu,
      'horaires', s.horaires, 'tarif', s.tarif, 'date_limite', s.date_limite,
      'documents', s.documents, 'infos', s.infos, 'paiement_infos', s.paiement_infos,
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
        'paiement_date', c.paiement_date, 'montant', c.montant, 'recu_num', c.recu_num
      ) order by e.nom, e.prenom), '[]'::jsonb)
      from stg_convocations c join stg_enfants e on e.id = c.enfant_id)
  );
end $$;

create or replace function stg_admin_import(pwd text, sid bigint, rows jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  r jsonb; eid bigint; nouveaux int := 0; ajoutes int := 0;
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
      insert into stg_convocations (stage_id, enfant_id) values (sid, eid)
      on conflict (stage_id, enfant_id) do nothing;
      if found then ajoutes := ajoutes + 1; end if;
    end if;
  end loop;
  return jsonb_build_object('nouveaux_enfants', nouveaux, 'ajoutes_au_stage', ajoutes);
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

-- Message attendu : « Success. No rows returned »
