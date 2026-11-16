-- Clubs du Var : ajoute le GSD du Var (0833304) à l'annuaire, placé après les clubs.
-- Ce n'est pas un club comme les autres (licences des arbitres, entraîneurs, personnes d'associations non affiliées ; sport santé),
-- mais il a sa fiche dans l'annuaire. Il n'est pas dans la facturation (jamais facturé).
-- À lancer une fois dans Supabase › SQL Editor, après supabase-clubs.sql. Relançable.
insert into clb_clubs (code, nom, acces, ordre) values ('GSD83', 'GSD du Var', clb_code(), 100)
on conflict (code) do update set ordre = 100, actif = true;
