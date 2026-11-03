-- Met la même liste de documents sur tous les stages de la saison
-- (le stage de Noël avait encore l'ancien intitulé « Autorisation parentale »)
update stg_stages
   set documents = array['Fiche de renseignements et autorisation parentale', 'Fiche sanitaire', 'Code de vie']
 where date_debut >= '2026-09-01';
-- Message attendu : « Success. No rows returned »
