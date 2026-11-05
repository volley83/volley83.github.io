-- Championnats : tolérance après la clôture des inscriptions (mode « Auto »).
-- La date et l'heure limites affichées restent les mêmes (jeudi 12 h), mais le formulaire accepte
-- encore les inscriptions pendant 2 heures (jusqu'à 14 h). Ensuite, le site affiche jusqu'à 22 h un message
-- invitant à écrire au Comité (géré dans la page).
-- À lancer une fois : Supabase › SQL Editor › coller › Run. Peut être relancé sans risque.
create or replace function chp_ouvert(t chp_tournois) returns boolean
language sql stable as $$
  select case t.inscriptions
    when 'ouvertes' then true
    when 'fermees'  then false
    else t.date_limite is not null and t.statut = 'ouvert'
         and current_date >= t.date - 42                      -- ouverture 6 semaines avant le tournoi
         and (now() at time zone 'Europe/Paris') <= (t.date_limite + coalesce(nullif(t.heure_limite,''),'23:59')::time) + interval '2 hours'   -- tolérance de 2 h
  end;
$$;
