# Notes de travail — site du Comité du Var de Volley-Ball

Ces notes servent à reprendre le projet dans une nouvelle conversation avec Claude. Elles disent comment le site est organisé, ce qui a été décidé, et ce qu'il reste à faire.
**Pour reprendre :** « Reprends le site volley83 à partir du dépôt GitHub volley83/volley83.github.io et de NOTES.md ».

## Organisation générale

- **Hébergement** : GitHub Pages, dépôt `volley83/volley83.github.io` → https://volley83.github.io/
  - Chaque rubrique est **une seule page HTML** (HTML, CSS et JS dans le même fichier), sans étape de compilation.
- **Données** : Supabase, projet `nssdhgpvkdbgdewsnlgl`. Ce projet est partagé avec le TIP.
  - Clé publique : `sb_publishable_…`, déjà présente dans les pages.
  - RLS activée sur toutes les tables. Le site ne lit **jamais** les tables directement : il appelle uniquement des fonctions `security definer` via `/rest/v1/rpc/<fonction>`.
  - Le mot de passe admin (« accès complet ») est dans la table `private_config` (clé `admin_password`). Il est commun au TIP, aux stages et aux championnats, et ne figure dans aucun fichier du dépôt.
  - Clément lance lui-même les scripts SQL : Supabase › SQL Editor › coller › Run. Tous les scripts sont prévus pour être relancés sans risque.
- **Style commun** : bleu marine `#0B2149`, jaune `#F6C21B`, polices Barlow Condensed (titres) et Inter (texte). Tutoiement avec Clément ; le site s'adresse aux familles et aux clubs en vouvoyant.
- **Commits** : auteur `volley83 <volley83@users.noreply.github.com>`. Push direct sur `main`.
- **Autres dépôts** :
  - `volley83/tip2026` : TIP, https://volley83.github.io/tip/
  - `volley83/pitchounvolley` : Pitchoun' Volley
- **But final** : tout regrouper sous www.volley83.fr (Sportsregions aujourd'hui) en fin de saison 2026-2027, avec transfert du domaine.

## Rubrique Stages — `stages/index.html`

- **Vues** :
  - `#stages` : Centre Départemental M11-M13, stages sur convocation ;
  - `#beach` : beach-volley, inscription en ligne ;
  - `#parents` : espace parents ;
  - `#admin` : accès organisateurs, lien en pied de page.
- **Tables** :
  - `stg_stages` : colonne `type` cde/beach/ete, plus `inscription`, `places`, `par_jour`, `contact`, `convocation_url(_m)`, `documents` et `documents_liens`.
  - `stg_enfants` : code personnel de 4 caractères, `docs_recus` valables toute la saison, `sexe`, `licence`, `naissance`.
  - `stg_convocations` : `statut` convoque/attente, `rang_attente`, `reponse`, paiement, `recu_num`, `jours`, `niveau`, `source`.
  - `stg_fiches_connues` : fiches de renseignements déjà fournies avant le site, reconnues par nom et prénom.
- **Connexion des parents** : nom de l'enfant + année de naissance + code. Le code est le même pour tous les stages de la saison.
- **Centre Départemental** :
  - L'admin importe les convoqués en collant depuis Excel, puis envoie les codes avec Mailmeteor (50 mails par jour ; YAMM est limité à 20). Il peut aussi envoyer un mail individuel avec « ✉ Envoyer le code », qui ouvre un brouillon Gmail.
  - Il y a une liste d'attente par sexe, que l'admin ordonne et active à la main.
  - L'admin peut produire la liste des convoqués en PDF ou en image, et la liste des présents avec les absents en rouge.
- **Beach (inscription en ligne)** : fonction `stg_inscrire(p jsonb)`.
  - Places vérifiées jour par jour ; si un jour est complet, l'inscription part en liste d'attente. Il n'y a qu'une liste d'attente, filles et garçons mélangés.
  - Le code n'est affiché qu'à un **nouvel** enfant. Un enfant déjà connu garde son code, qui n'est jamais réaffiché.
  - L'inscription est **validée** si la fiche de renseignements est reçue **ou** si au moins le tarif d'une journée est payé.
  - Protection : champ leurre anti-robot et limite de 40 inscriptions par heure.
- **Reçus PDF** (jsPDF) :
  - disponibles seulement **après** le stage ;
  - jamais pour le mode de paiement « Autre (sans reçu) » ;
  - numéro attribué une seule fois.
- **Données personnelles** : supprimées en fin de saison avec `stg_admin_purge`. Les listes d'enfants (scripts d'import) ne sont **pas** dans le dépôt.

## Rubrique Championnats — `championnats/index.html`

- **Championnats fédéraux** :
  - Ils sont récupérés de ffvbbeach.org par `scripts/ffvb.py`, via le workflow `.github/workflows/ffvb.yml` : toutes les 2 h, et toutes les heures de 11 h à 22 h le week-end.
  - Le workflow écrit `championnats/data/ffvb.json` et les agendas `.ics` dans `championnats/data/ics/`.
  - Onglets : Jeunes, Seniors, Compet'Lib, Coupe de France.
  - Catégories exclues : M4M, MFM, C4M, CFM, O11, O13, PIT, et les poules de qualification régionale.
- **Règles d'affichage décidées** :
  - pas de médailles en 1re phase ;
  - équipes mises en avant par la FFVB en gras ;
  - classement et résultats à gauche, « À venir » à droite ;
  - noms complets des clubs ;
  - pas de lien FDME.
- **Compétitions OPEN** (tables `chp_*`) :
  - M15/M18 4x4 avec classement, et tournois OPEN 2x2/4x4 sans classement ;
  - inscription en ligne des équipes, close le jeudi précédent à 12 h ;
  - le club recevant saisit le classement (bouton seulement en 4x4), puis Clément le valide ;
  - un tournoi final OPEN.
- **Coupe de France** : table `chp_coupe`, scripts `supabase-coupe-de-france*.sql`.

## Scripts SQL — dossier `sql/`

- `sql/stages/supabase-stages.sql` et `sql/championnats/supabase-championnats.sql` : installation complète. Ils contiennent les dernières versions des fonctions.
- Les autres fichiers sont des mises à jour déjà appliquées, gardées pour l'historique. Les plus récentes :
  - `supabase-stage-beach.sql` : inscription en ligne et stage beach des 2 et 3 janvier 2027 ;
  - `supabase-coupe-de-france*.sql`.
- Les listes d'enfants (filles et garçons 2026-2027, fiches beach d'octobre) sont volontairement **hors dépôt** : ce sont des données de mineurs et le dépôt est public.

## À faire / idées

- **Stages d'été** : le type `ete` est déjà prévu, avec l'inscription en ligne comme pour le beach.
- **Stages** : documents des points travaillés (lien `points_url`, déjà géré).
- **Possible** : un mail automatique avec le code après une inscription en ligne. Il faudrait une fonction edge Supabase et un service d'envoi (Brevo ou Resend).
- **TIP, avant mai** :
  - affichage par terrain ;
  - passage de la phase 1 à la phase 2 ;
  - verrouillage des scores ;
  - palmarès manquants.
- **Portail** : accueil, documents, contact, clubs, formations, bénévoles, actualités ; puis transfert du domaine volley83.fr.
