-- Stages du Centre Départemental, saison 2026-2027 (à lancer APRÈS supabase-stages.sql)
-- Lieu : CREPS de Boulouris · 120 € · filles et garçons.
-- Un stage déjà créé à la même date n'est pas recréé. Tout reste modifiable dans l'admin du site
-- (date limite de réponse, horaires, lien des points travaillés…).

insert into stg_stages (titre, categorie, date_debut, date_fin, lieu, horaires, tarif, date_limite, documents, infos, paiement_infos, liste_publique, actif)
select 'Stage du Centre Départemental – Noël 2026', 'Centre Départemental · Filles et garçons', '2026-12-21', '2026-12-23', 'CREPS PACA de Boulouris, 346 boulevard des Mimosas, 83700 Saint-Raphaël',
  'Ouverture le lundi 21 décembre à 9h15 au complexe Anthéor – Salle Or (grand gymnase).
Clôture le mercredi 23 décembre à 16h au même endroit.
Hébergement en pension complète pendant les 3 jours.', 120, '2026-12-01',
  array['Fiche de renseignements et autorisation parentale', 'Fiche sanitaire', 'Code de vie'],
  'À apporter :
- 8 tee-shirts de sport et 3 shorts minimum (3 entraînements par jour)
- Bouteille d''eau ou gourde de 1 L minimum (obligatoire)
- Petite trousse à pharmacie personnelle (élasto, strap, pansements…)
- Vessie à glace conseillée (une machine à glace sera disponible)
- Chaussures de sport réservées à l''entraînement + chaussures de sport pour l''extérieur
- Survêtement ou tenue de sport obligatoire entre les entraînements
- Un stylo
- Un réveil autre que le téléphone portable
- Des jeux et quelques pièces de monnaie pour les temps libres
- Ton classeur de suivi et ton tee-shirt si tu as déjà fait un stage',
  'Participation de 120 €, au choix :
- 1 chèque de 120 € à l''ordre du Comité du Var de Volley-Ball (encaissé le 5 janvier)
- 2 chèques de 60 € (encaissés le 5 janvier et le 5 février)
- Virement de 120 € (RIB sur la convocation)
- Carte bancaire en ligne : https://www.helloasso.com/associations/comite-du-var-de-volley-ball/paiements/stage-de-la-commission-technique
- Carte bancaire, espèces ou chèques-vacances sur place au début du stage',
  true, true
where not exists (select 1 from stg_stages where date_debut = '2026-12-21');

insert into stg_stages (titre, categorie, date_debut, date_fin, lieu, horaires, tarif, date_limite, documents, infos, paiement_infos, liste_publique, actif)
select 'Stage du Centre Départemental – Hiver 2027', 'Centre Départemental · Filles et garçons', '2027-02-26', '2027-02-28', 'CREPS PACA de Boulouris, 346 boulevard des Mimosas, 83700 Saint-Raphaël',
  'Horaires d''ouverture et de clôture précisés dans la convocation.
Hébergement en pension complète pendant les 3 jours.', 120, null,
  array['Fiche de renseignements et autorisation parentale', 'Fiche sanitaire', 'Code de vie'],
  'À apporter :
- 8 tee-shirts de sport et 3 shorts minimum (3 entraînements par jour)
- Bouteille d''eau ou gourde de 1 L minimum (obligatoire)
- Petite trousse à pharmacie personnelle (élasto, strap, pansements…)
- Vessie à glace conseillée (une machine à glace sera disponible)
- Chaussures de sport réservées à l''entraînement + chaussures de sport pour l''extérieur
- Survêtement ou tenue de sport obligatoire entre les entraînements
- Un stylo
- Un réveil autre que le téléphone portable
- Des jeux et quelques pièces de monnaie pour les temps libres
- Ton classeur de suivi et ton tee-shirt si tu as déjà fait un stage',
  'Participation de 120 €, au choix :
- 1 chèque de 120 € à l''ordre du Comité du Var de Volley-Ball
- 2 chèques de 60 €
- Virement de 120 € (RIB sur la convocation)
- Carte bancaire en ligne : https://www.helloasso.com/associations/comite-du-var-de-volley-ball/paiements/stage-de-la-commission-technique
- Carte bancaire, espèces ou chèques-vacances sur place au début du stage',
  true, true
where not exists (select 1 from stg_stages where date_debut = '2027-02-26');

insert into stg_stages (titre, categorie, date_debut, date_fin, lieu, horaires, tarif, date_limite, documents, infos, paiement_infos, liste_publique, actif)
select 'Stage du Centre Départemental – Printemps 2027 (formation)', 'Centre Départemental · Filles et garçons', '2027-04-21', '2027-04-23', 'CREPS PACA de Boulouris, 346 boulevard des Mimosas, 83700 Saint-Raphaël',
  'Horaires d''ouverture et de clôture précisés dans la convocation.
Hébergement en pension complète pendant les 3 jours.', 120, null,
  array['Fiche de renseignements et autorisation parentale', 'Fiche sanitaire', 'Code de vie'],
  'À apporter :
- 8 tee-shirts de sport et 3 shorts minimum (3 entraînements par jour)
- Bouteille d''eau ou gourde de 1 L minimum (obligatoire)
- Petite trousse à pharmacie personnelle (élasto, strap, pansements…)
- Vessie à glace conseillée (une machine à glace sera disponible)
- Chaussures de sport réservées à l''entraînement + chaussures de sport pour l''extérieur
- Survêtement ou tenue de sport obligatoire entre les entraînements
- Un stylo
- Un réveil autre que le téléphone portable
- Des jeux et quelques pièces de monnaie pour les temps libres
- Ton classeur de suivi et ton tee-shirt si tu as déjà fait un stage',
  'Participation de 120 €, au choix :
- 1 chèque de 120 € à l''ordre du Comité du Var de Volley-Ball
- 2 chèques de 60 €
- Virement de 120 € (RIB sur la convocation)
- Carte bancaire en ligne : https://www.helloasso.com/associations/comite-du-var-de-volley-ball/paiements/stage-de-la-commission-technique
- Carte bancaire, espèces ou chèques-vacances sur place au début du stage',
  true, true
where not exists (select 1 from stg_stages where date_debut = '2027-04-21');

insert into stg_stages (titre, categorie, date_debut, date_fin, lieu, horaires, tarif, date_limite, documents, infos, paiement_infos, liste_publique, actif)
select 'Stage du Centre Départemental – Printemps 2027 (compétition)', 'Centre Départemental · Filles et garçons', '2027-04-24', '2027-04-26', 'CREPS PACA de Boulouris, 346 boulevard des Mimosas, 83700 Saint-Raphaël',
  'Horaires d''ouverture et de clôture précisés dans la convocation.
Hébergement en pension complète pendant les 3 jours.', 120, null,
  array['Fiche de renseignements et autorisation parentale', 'Fiche sanitaire', 'Code de vie'],
  'À apporter :
- 8 tee-shirts de sport et 3 shorts minimum (3 entraînements par jour)
- Bouteille d''eau ou gourde de 1 L minimum (obligatoire)
- Petite trousse à pharmacie personnelle (élasto, strap, pansements…)
- Vessie à glace conseillée (une machine à glace sera disponible)
- Chaussures de sport réservées à l''entraînement + chaussures de sport pour l''extérieur
- Survêtement ou tenue de sport obligatoire entre les entraînements
- Un stylo
- Un réveil autre que le téléphone portable
- Des jeux et quelques pièces de monnaie pour les temps libres
- Ton classeur de suivi et ton tee-shirt si tu as déjà fait un stage',
  'Participation de 120 €, au choix :
- 1 chèque de 120 € à l''ordre du Comité du Var de Volley-Ball
- 2 chèques de 60 €
- Virement de 120 € (RIB sur la convocation)
- Carte bancaire en ligne : https://www.helloasso.com/associations/comite-du-var-de-volley-ball/paiements/stage-de-la-commission-technique
- Carte bancaire, espèces ou chèques-vacances sur place au début du stage',
  true, true
where not exists (select 1 from stg_stages where date_debut = '2027-04-24');

-- Message attendu : « Success. No rows returned »