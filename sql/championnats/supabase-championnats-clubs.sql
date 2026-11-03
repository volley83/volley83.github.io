-- Championnats : liste complète des clubs du Comité (code court = nom d'équipe à la saisie)
-- À lancer dans Supabase › SQL Editor. Relançable.
insert into chp_clubs (code, nom, ordre) values
  ('DVVB',  'Draguignan Union Club Var VB', 0),
  ('CSB',   'Club Sportif Brignolais', 0),
  ('FVV',   'Fréjus Var Volley', 0),
  ('LLVB',  'Le Luc Volley-Ball', 0),
  ('SMCV',  'Sainte-Maxime Cogolin Volley', 0),
  ('2SBVC', 'Sud Sainte-Baume Volley Club', 0),
  ('UAV',   'Union Athlétique Valettoise', 0),
  ('VVB',   'Vidauban Volley-Ball', 0),
  ('VBO',   'Volley-Ball Ollioulais', 0),
  ('VCHPL', 'Volley Club Hyères / Pierrefeu La Londe', 0),
  ('VCM',   'Volley Club Méditerranée', 0),
  ('VCS',   'Volley Club Seynois', 0),
  ('VPG',   'Volley Pradétan Gardéen', 0)
on conflict (code) do update set nom = excluded.nom, ordre = excluded.ordre;

-- Retire les anciens clubs (repris du Pitchoun') qui ne sont pas dans cette liste et ne servent nulle part
delete from chp_clubs k
where k.code not in ('DVVB','CSB','FVV','LLVB','SMCV','2SBVC','UAV','VVB','VBO','VCHPL','VCM','VCS','VPG')
  and not exists (select 1 from chp_inscriptions i where i.club = k.code)
  and not exists (select 1 from chp_resultats r where r.club = k.code)
  and not exists (select 1 from chp_tournois t where t.organisateur = k.code);

select code, nom from chp_clubs order by ordre, nom;
