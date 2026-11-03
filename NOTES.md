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

## Rubrique Facturation — `facturation/index.html` (admin uniquement)

- **Adresse** : https://volley83.github.io/facturation/ (non indexée, aucun lien public). Mot de passe admin commun.
- **Tables `fac_*`** (script `sql/facturation/supabase-facturation.sql`) :
  - `fac_clubs` : sigle (clé, le même que partout sur le site), n° d'affiliation FFVB, nom, mail(s), adresse, « autres noms » pour reconnaître le club dans les inscriptions ;
  - `fac_articles` : catalogue (code comptable, désignation, prix, unité, catégorie). Les articles avec `cle` (open_XXX, pitchoun, stage) servent aux ajouts automatiques et ne se suppriment pas ;
  - `fac_bordereaux` (saison, numéro, date, statut brouillon/envoye, origine 'ffvb' pour l'historique) et `fac_lignes` (copie code/désignation/prix ; `source` = open:O11, pitchoun, stage:<id> pour ne pas refacturer) ;
  - `fac_paiements` : imputés à un bordereau ou, sinon, aux plus anciens d'abord ;
  - `fac_reglages` : `emetteur`, `mentions` (pied de facture), `open_tarifs` [1 tournoi, 2 tournois, 3 et plus] = [10, 30, 50].
- **Vues** : `#recap` (tableau club × bordereau, export Excel), `#bordereaux`, `#b/<id>`, `#b/<id>/<CLUB>` (facture), `#b/<id>/groupe` (saisie groupée), `#b/<id>/auto` (ajouts automatiques), `#paiements`, `#articles`, `#clubs`, `#reglages`.
- **Ajouts automatiques** (`fac_admin_sources`) — règles décidées avec Clément :
  - OPEN 2x2/4x4 et M15/M18 4x4 (tarifs 2026-2027 : 10 / 35 / 60 € par équipe) : seuls les tournois **déjà joués** comptent. Une équipe est facturée 60 € **dès qu'elle atteint 3 tournois** ; les équipes à 1 ou 2 tournois **après le dernier tournoi** de la compétition. Équipe n d'un club = présente aux tournois où le club a inscrit au moins n équipes (comme l'Excel « Engagements OPEN »). Source des lignes : `open:O11#1,3` (numéros d'équipes facturées) ;
  - Récapitulatif des participations : onglet **Participations** de l'admin des championnats (tableau club × équipe × tournoi, coût, état « facturé (bordereau n° X) », export CSV), via `fac_admin_open_facture` ;
  - Pitchoun' : **après le dernier plateau** (`pitchoun_plateaux`), tous les enfants ayant joué au moins un plateau, 7 € (756020) ;
  - Participation des clubs aux stages du Centre Départemental (706003) : après chaque stage CDE terminé, enfants convoqués non absents, 12 € × nb de jours (36 € pour 3 jours), noms des enfants en précisions. Source `cde:<stage_id>` ;
  - Stage réglé par le club à la place de la famille (mode « Autre : facturé au club ») : 706001 CDE, 706002 beach ;
  - Case « les facturer quand même maintenant » pour forcer la fin de saison.
- **Lignes** : désignation modifiable + champ **précisions** (affiché en italique sous la désignation sur le PDF).
- **Catalogue** : refait d'après le document « Tarifs saison 2026 / 2027 » (`catalogue_version` = 2). Compet'Lib : 90 € (le document des tarifs indique 80 € par erreur). Tournoi International : compte 706603. Pas de participation des clubs au stage Perfectionnement Beach cette saison.
- **PDF** : jsPDF, une page par club ; encadré « Règlement par virement » avec le réglage `banque` (IBAN du Comité, saisi dans la base par le script privé, pas dans le dépôt) ; numéro de facture `AAaa-NN-SIGLE` (ex. 2627-02-VCHPL). Bouton mail = brouillon Gmail, PDF à joindre.
- **RIS (Relevé des Infractions Sportives)** — onglet `#ris` : tables `fac_ris` (saison, numéro, date « au ») et `fac_ris_items` (rubrique 1-5 : Dossiers, Licences, Saisie des résultats et envoi des feuilles, Feuille de match, Divers ; n° de match, club, intitulé, montant). Choix de l'infraction dans les articles Pénalités/Forfaits/Arbitrage (intitulé et montant pré-remplis, modifiables) ou saisie libre. « Générer le RIS et facturer » : PDF au modèle du Comité (logos, 5 tableaux, phrase RGISA, pied `ris_pied`) + ajout des infractions avec montant au **premier bordereau en brouillon** (créé s'il n'y en a pas) : désignation = intitulé, précisions = « RIS n° X du JJ/MM/AAAA – match », source `ris:<id>`. Une infraction facturée n'est plus modifiable.
- **Mails des clubs** : `email` = contacts généraux (copie), `email_finances` = trésoriers (destinataires des factures). Remplis par le script privé depuis le fichier de contacts du Comité.
- **GSD du Var (0833304)** = le Comité lui-même : jamais facturé, absent de fac_clubs (ses 125 € du bordereau FFVB n° 1 ne sont pas repris).
- **Reprise** : le bordereau FFVB n° 1 2026-2027 (détaillé depuis le PDF), l'IBAN et les mails/adresses des clubs (annuaire FFVB rech_aff_club.php, POST ws_new_comit=083 puis id_club=<n°>) sont importés, par un script **hors dépôt** (`facturation-import-2026-2027.sql`). Pas d'historique 2025-2026 : tout était réglé.
- **Idée pour plus tard** : affiliation (réaffiliation GSA) à facturer ici à partir de 2027-2028.

## Scripts SQL — dossier `sql/`

- `sql/stages/supabase-stages.sql`, `sql/championnats/supabase-championnats.sql` et `sql/facturation/supabase-facturation.sql` : installation complète. Ils contiennent les dernières versions des fonctions.
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
