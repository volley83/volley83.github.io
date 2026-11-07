-- Rappels aux familles qui n'ont pas répondu à une convocation (bouton « ⏰ Envoyer rappel » de l'admin des stages)
-- À lancer une fois dans Supabase › SQL Editor. Relançable, aucune donnée supprimée.

alter table stg_convocations add column if not exists rappels timestamptz[] not null default '{}';

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

-- Rappel aux familles sans réponse : enregistre la date de l'envoi pour chaque convocation (frères et sœurs compris)
create or replace function stg_admin_rappel(pwd text, cids bigint[])
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not stg_is_admin(pwd) then raise exception 'Accès refusé'; end if;
  update stg_convocations set rappels = coalesce(rappels, '{}') || now() where id = any(cids);
  return (select coalesce(jsonb_object_agg(id::text, to_jsonb(rappels)), '{}'::jsonb) from stg_convocations where id = any(cids));
end $$;

grant execute on function stg_admin_rappel(text, bigint[]) to anon;
