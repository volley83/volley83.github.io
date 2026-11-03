-- Lien du PDF de convocation par stage (espace parents + mail « Envoyer le code »)
-- À lancer une fois dans Supabase › SQL Editor. Relançable, aucune donnée supprimée.

alter table stg_stages add column if not exists convocation_url text;
alter table stg_stages add column if not exists convocation_url_m text;

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

-- Convocation du stage de Noël 2026 (la même pour les filles et les garçons)
update stg_stages set convocation_url = 'https://volley83.github.io/stages/docs/convocation-noel-2026.pdf'
 where titre ilike '%Noël 2026%';

-- Vérification : le stage de Noël doit afficher le lien
select titre, convocation_url from stg_stages order by date_debut;
