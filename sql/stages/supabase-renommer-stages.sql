-- Harmonise les noms des stages de la saison 2026-2027 (à lancer une fois dans Supabase › SQL Editor)
update stg_stages set titre = 'Stage du Centre Départemental – Noël 2026'                     where date_debut = '2026-12-21';
update stg_stages set titre = 'Stage du Centre Départemental – Hiver 2027'                    where date_debut = '2027-02-26';
update stg_stages set titre = 'Stage du Centre Départemental – Printemps 2027 (formation)'   where date_debut = '2027-04-21';
update stg_stages set titre = 'Stage du Centre Départemental – Printemps 2027 (compétition)' where date_debut = '2027-04-24';
-- Message attendu : « Success. No rows returned »
