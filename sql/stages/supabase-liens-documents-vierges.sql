-- Liens des documents vierges (espace parents) pour tous les stages
-- À lancer dans Supabase › SQL Editor. Relançable sans risque.
update stg_stages set documents_liens = coalesce(documents_liens, '{}'::jsonb) || jsonb_build_object(
  'Fiche de renseignements et autorisation parentale', 'https://volley83.github.io/stages/docs/fiche-de-renseignements-et-autorisation-parentale.pdf',
  'Fiche sanitaire', 'https://volley83.github.io/stages/docs/fiche-sanitaire-de-liaison.pdf',
  'Code de vie', 'https://volley83.github.io/stages/docs/code-de-vie.pdf');
select titre, documents, documents_liens from stg_stages order by date_debut;
