-- Espace Comité (https://volley83.github.io/comite/) : résumé « À traiter » du tableau de bord.
-- À lancer une fois dans Supabase › SQL Editor (même projet que le TIP). Relançable sans risque.
-- Chaque partie est protégée : si une table n'existe pas (encore), son compteur est simplement absent.

create or replace function comite_resume(pwd text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r jsonb := '{}'::jsonb; x jsonb;
begin
  if not exists (select 1 from private_config where key = 'admin_password' and value = pwd) then
    raise exception 'Accès refusé';
  end if;

  -- Infractions signalées par les vérificateurs (page /ris/), à vérifier
  begin
    r := r || jsonb_build_object('signalements', (select count(*) from fac_signalements where statut = 'nouveau'));
  exception when others then null; end;

  -- Factures envoyées et pas encore réglées
  begin
    r := r || jsonb_build_object('factures_impayees', (select count(*) from fac_factures where statut = 'envoyee' and regle_date is null));
  exception when others then null; end;

  -- Fiches clubs envoyées par les clubs, à valider
  begin
    r := r || jsonb_build_object('fiches_clubs', (select count(*) from clb_clubs where proposition is not null and actif));
  exception when others then null; end;

  -- Classements OPEN / 4x4 saisis par le club recevant, à valider
  begin
    r := r || jsonb_build_object('classements', (select count(*) from chp_tournois where statut = 'saisi'));
  exception when others then null; end;

  -- Prochains tournois OPEN / 4x4 (30 jours) avec le nombre d'équipes inscrites
  begin
    select coalesce(jsonb_agg(jsonb_build_object('date', t.date, 'competition', coalesce(c.nom, t.competition), 'lieu', t.lieu,
             'equipes', (select coalesce(sum(i.nb_equipes), 0) from chp_inscriptions i where i.tournoi_id = t.id)) order by t.date), '[]')
      into x
      from chp_tournois t left join chp_competitions c on c.code = t.competition
     where t.statut <> 'annule' and t.date between current_date and current_date + 30;
    r := r || jsonb_build_object('tournois', x);
  exception when others then null; end;

  -- Prochains stages (60 jours) : convoqués sans réponse, non payés
  begin
    select coalesce(jsonb_agg(jsonb_build_object('titre', s.titre, 'date', s.date_debut, 'date_limite', s.date_limite,
             'convoques', (select count(*) from stg_convocations v where v.stage_id = s.id and v.statut = 'convoque'),
             'sans_reponse', (select count(*) from stg_convocations v where v.stage_id = s.id and v.statut = 'convoque' and v.reponse = 'attente'),
             'presents', (select count(*) from stg_convocations v where v.stage_id = s.id and v.statut = 'convoque' and v.reponse = 'present'),
             'non_payes', (select count(*) from stg_convocations v where v.stage_id = s.id and v.statut = 'convoque' and v.reponse = 'present' and not coalesce(v.paye, false))
           ) order by s.date_debut), '[]')
      into x
      from stg_stages s
     where s.actif and coalesce(s.date_fin, s.date_debut) >= current_date and s.date_debut <= current_date + 60;
    r := r || jsonb_build_object('stages', x);
  exception when others then null; end;

  -- Pitchoun' Volley : plateaux saisis à valider, prochain plateau
  begin
    r := r || jsonb_build_object('plateaux', (select count(*) from pitchoun_plateaux where statut = 'saisi'));
    select to_jsonb(p) into x from (
      select date, heure, lieu, ville from pitchoun_plateaux where date >= current_date order by date limit 1) p;
    r := r || jsonb_build_object('prochain_plateau', x);
  exception when others then null; end;

  return r;
end $$;

revoke all on function comite_resume(text) from public;
grant execute on function comite_resume(text) to anon, authenticated;

-- Contrôle : doit renvoyer « Accès refusé » (mot de passe volontairement faux)
-- select comite_resume('test');
