-- Championnats : adresses mail des clubs pour le bouton « ✉ Envoyer le code » (admin, Calendrier et codes).
-- Les adresses viennent de la table fac_clubs (page Facturation). À lancer une fois : SQL Editor › coller › Run.
-- Peut être relancé sans risque.
create or replace function chp_admin_mails(pwd text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not chp_is_admin(pwd) then raise exception 'Accès refusé'; end if;
  return (select coalesce(jsonb_object_agg(f.code, f.email), '{}'::jsonb)
          from fac_clubs f where coalesce(trim(f.email), '') <> '');
end $$;
revoke all on function chp_admin_mails(text) from public;
grant execute on function chp_admin_mails(text) to anon, authenticated;
