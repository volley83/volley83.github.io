-- Championnats : l'admin peut AJOUTER une inscription (bouton « + Ajouter un club » dans Inscriptions),
-- même quand les inscriptions sont closes. iid = null => nouvelle inscription.
-- À lancer une fois : Supabase › SQL Editor › coller › Run. Peut être relancé sans risque.
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
