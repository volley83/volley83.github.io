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
  - « ⏰ Envoyer rappel » (`mailRappel`) : affiché à côté, seulement pour les convoqués encore « Sans réponse ». Brouillon Gmail de relance (objet « RAPPEL – Réponse attendue – … »), qui rappelle l'échéance (« dans N jours », « demain », « aujourd'hui » ou date dépassée), demande de répondre même en cas d'absence (place pour la liste d'attente) et redonne les identifiants. Les frères et sœurs sans réponse à la même adresse sont regroupés. Chaque envoi est enregistré (colonne `stg_convocations.rappels`, fonction `stg_admin_rappel`, script `sql/stages/supabase-rappels.sql`) et affiché en rouge sous la réponse ; le lien devient « Envoyer 2e rappel ». À partir du 2e : objet « DERNIER RAPPEL », dates des rappels précédents citées, et avertissement « sans réponse, l'enfant ne sera plus convoqué sur aucun stage du Centre Départemental ».
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
  - inscription en ligne des équipes, close le jeudi précédent à 12 h (affiché), acceptée en réalité jusqu'à 14 h (`chp_ouvert` : + 2 h) ; de 14 h à 22 h le jour de la clôture, le tournoi reste proposé avec un message « inscriptions closes, écrivez à volley83@gmail.com » (`tardif()` dans la page) ;
  - le club recevant saisit le classement (bouton seulement en 4x4), puis Clément le valide ;
  - code club recevant pour **tous** les tournois (4x4 et OPEN). Bouton « ✉ Envoyer le code » dans Calendrier et codes : brouillon Gmail au club (adresse prise dans `fac_clubs.email` via `chp_admin_mails`, sinon contacts de ses inscriptions) avec le code, le lien de l'espace club, les documents et le rappel de la feuille de composition ;
  - espace club (`#club`) : équipes inscrites, **documents à imprimer** (`championnats/docs/` : composition-OPEN-2x2, composition-OPEN-4x4, composition-M15-M18-4x4, feuille-poule-3 à 6, règlement), rappel « envoyer la feuille de composition à volley83@gmail.com » ; saisie du classement en 4x4 seulement. Les tournois OPEN y figurent jusqu'à 10 jours après leur date ;
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
- **Catalogue** : refait d'après le document « Tarifs saison 2026 / 2027 » (`catalogue_version` = 2). Pénalités nommées « PÉNALITÉ - … » dans le catalogue ; à l'ajout sur une facture, « PÉNALITÉ RIS N°<dernier RIS généré> - … ». Les articles « auto » (cle : OPEN, Pitchoun', stages) ne sont pas proposés dans l'ajout manuel ni la saisie groupée. Sanctions terrain (RIS, Divers) : avertissement 50 €, pénalité 100 €. Engagement non conforme : sans prix (montant à saisir selon la catégorie). Compet'Lib : 90 € (le document des tarifs indique 80 € par erreur). Tournoi International : compte 706603. Pas de participation des clubs au stage Perfectionnement Beach cette saison.
- **Mail aux clubs** : objet et texte dans Réglages (`mail_objet`, `mail_modele`, champs {numero} {saison} {club} {sigle} {montant} {facture} {date} {contenu}) ; la liste « Ce bordereau comprend notamment » est propre à chaque bordereau (`fac_bordereaux.mail_contenu`), proposée d'après les lignes (catégories, sources OPEN/Pitchoun'/CDE/RIS). Signature : Eric CHASSAGNARD, trésorier ; paiement CB via HelloAsso.
- **Date du bordereau** : mise automatiquement à la date du jour quand on clique sur « Marquer comme envoyé » (confirmation indiquant l'ancienne et la nouvelle date) ; les lignes qui portaient l'ancienne date du bordereau prennent aussi la date d'envoi. Même proposition (confirmation) au premier « ✉ Mail » d'un bordereau en brouillon dont la date n'est pas celle du jour.
- **Avoirs** : un bordereau au total négatif pour un club (trop-perçu…) est soldé et son montant est déduit automatiquement des bordereaux suivants (etatClub : `avoir`, `creditRestant`). Facture PDF : « Avoir déduit (bordereau N° x) », « Reste à payer », « Avoir restant ». Mail : la phrase « Vous pouvez régler… » est remplacée par `mail_avoir_total` ou `mail_avoir_partiel` (Réglages).
- **Rappels** : bouton « ✉ Rappel » (Récapitulatif, bordereau envoyé, facture) pour un club ayant des bordereaux **envoyés** non réglés ; mail `rappel_objet`/`rappel_modele` ({impayes}, {reste}, {club}, {sigle}, {saison}), PDF des bordereaux concernés téléchargés, trace dans `fac_rappels` (« dernier rappel le … » dans le Récapitulatif).
- **PDF** : jsPDF, une page par club ; encadré « Règlement par virement » avec le réglage `banque` (IBAN du Comité, saisi dans la base par le script privé, pas dans le dépôt) ; numéro de facture `AAaa-NN-SIGLE` (ex. 2627-02-VCHPL). Bouton mail = brouillon Gmail, PDF à joindre.
- **RIS (Relevé des Infractions Sportives)** — onglet `#ris` : tables `fac_ris` (saison, numéro, date « au ») et `fac_ris_items` (rubrique 1-5 : Dossiers, Licences, Saisie des résultats et envoi des feuilles, Feuille de match, Divers ; n° de match, club, intitulé, montant). Choix de l'infraction dans les articles Pénalités/Forfaits/Arbitrage (intitulé et montant pré-remplis, modifiables) ou saisie libre. « Générer le RIS et facturer » : PDF au modèle du Comité (logos, 5 tableaux, phrase RGISA, pied `ris_pied`) + ajout des infractions avec montant au **premier bordereau en brouillon** (créé s'il n'y en a pas) : désignation = intitulé, précisions = « RIS n° X du JJ/MM/AAAA – match », source `ris:<id>`. Une infraction facturée n'est plus modifiable. Saisie : rubrique d'abord, puis infraction filtrée par rubrique (colonne `fac_articles.rubrique_ris`, modifiable dans Articles). Même infraction déjà saisie sur le même match (même club ou autre club) : confirmation demandée. Champ `note` (note explicative imprimée sur le RIS et en précision de facture), distinct de `commentaire` (interne). Les infractions avec montant non encore facturées sont signalées (pastille sur l'onglet RIS, encadré sur Récapitulatif, Bordereaux et RIS). Équipe absente = forfait un match ; retrait d'une équipe après publication des calendriers = forfait général de la catégorie ; joueuse non qualifiée = saisie libre. Infraction sans montant : signalée en rouge et à la génération, sauf si « Pas de sanction financière » est coché (colonne sans_sanction).
- **Signalements d'infractions** — page `ris/index.html` (https://volley83.github.io/ris/, non indexée) pour les personnes habilitées : code personnel à 6 caractères (table `fac_saisisseurs`, gérée dans l'onglet RIS › « Personnes habilitées », bouton « Envoyer l'accès » = brouillon Gmail avec le lien `?code=`). Saisie : date du match, n° de match, club, nature (tarifs Pénalités/Forfaits/Arbitrage ou « Autre »), précision, commentaires → table `fac_signalements` (statut nouveau / integre / rejete, motif visible par l'auteur). Dans l'onglet RIS, « Signalements à vérifier » : correction puis « Valider » (crée l'infraction dans le RIS choisi, commentaire conservé) ou « Rejeter ». Limite : 60 signalements par heure et par code.
- **Mails des clubs** : `email` = contacts généraux (copie), `email_finances` = trésoriers (destinataires des factures). Remplis par le script privé depuis le fichier de contacts du Comité.
- **GSD du Var (0833304)** = le Comité lui-même : jamais facturé, absent de fac_clubs (ses 125 € du bordereau FFVB n° 1 ne sont pas repris).
- **Reprise** : le bordereau FFVB n° 1 2026-2027 (détaillé depuis le PDF), l'IBAN et les mails/adresses des clubs (annuaire FFVB rech_aff_club.php, POST ws_new_comit=083 puis id_club=<n°>) sont importés, par un script **hors dépôt** (`facturation-import-2026-2027.sql`). Pas d'historique 2025-2026 : tout était réglé.
- **Idée pour plus tard** : affiliation (réaffiliation GSA) à facturer ici à partir de 2027-2028.

## Factures hors clubs — onglet « Hors clubs » de la facturation

- Pour un club extérieur, une mairie, une entreprise… Table `fac_factures` (coordonnées du client et lignes jsonb dans la facture), RPC `fac_admin_facture`, `fac_admin_get` renvoie `factures` (saison) et `clients` (derniers clients connus, pour l'autocomplétion).
- Numéro `2627-F001` (saison + numéro auto, modifiable). Articles du catalogue ou lignes libres ; règlement saisi sur la facture (montant, date, mode).
- PDF : même mise en page que les factures clubs (fonction commune `dessinFacture`). Mail Gmail avec les modèles `facture_objet` / `facture_modele` (Réglages). « Marquer comme envoyée » / préparer le mail proposent de passer la date au jour d'envoi.
- **Devis** : même table (`type` = 'devis', numéro `2627-D001`, numérotation séparée, `validite` = date + 30 jours par défaut). Statuts brouillon / envoyé / accepté / refusé. « Devis accepté → créer la facture » : RPC `fac_admin_devis_facture` (copie client, objet et lignes dans une nouvelle facture datée du jour, `devis_id` = lien). PDF « DEVIS » sans coordonnées bancaires, avec cadre « Bon pour accord ». Mail : `devis_objet` / `devis_modele` (+ {validite}).
- Export Excel : feuille « Hors clubs » (factures seulement).
- Mention TVA (réglage `mention_tva`, modifiable dans Réglages) imprimée sous le total de toutes les factures (clubs et hors clubs) et des devis. Défaut : « TVA non applicable – article 261-7-1° b du CGI ». Recodification de la TVA dans le CIBS au 1er janvier 2027 (anciennes références CGI tolérées jusqu'au 31/12/2027).

## Reçus de dons — onglet « Reçus de dons » de la facturation

- Tables `fac_donateurs` (coordonnées mémorisées) et `fac_recus` (copie des coordonnées, montant, date du don, type don / abandon de frais, mode, date du reçu, annulé). RPC `fac_admin_recu` (numéro attribué à la création : année du reçu + n° à la suite, `2026-001` ; mise à jour du donateur ; suppression seulement du dernier reçu de l'année, sinon « annuler » pour garder une numérotation continue) et `fac_admin_donateur`.
- PDF reprenant le modèle Cerfa n° 11580*05 : bénéficiaire (SIREN, objet = réglage `recu_objet_asso`, RNA facultatif `recu_rna`), donateur, montant en chiffres et en lettres (`enLettres`), cases art. 200, forme (don manuel / Autres pour l'abandon de frais), nature (numéraire / Autres : frais de bénévole abandonnés), mode de versement. Signataire `recu_signataire`, signature image `recu_signature` (dataURL déposée dans Réglages, jamais dans le dépôt public).
- Totaux par année (nombre de reçus et montant) pour la déclaration annuelle (art. 222 bis du CGI). Mail Gmail : `recu_mail_objet` / `recu_mail_modele`.

## Frais de déplacement — `frais/index.html` (accès libre)

- **Adresse** : https://volley83.github.io/frais/ (non indexée ; lien sur l'écran de connexion de la facturation et dans son menu « Frais dépl. »). Aucune base de données : tout se passe dans le navigateur.
- Le bénévole / intervenant choisit **Remboursement de frais** ou **Abandon de frais** (don à l'association, reçu fiscal), l'imputation (Bureau Directeur 625101 / Intervenants – Com. Technique 625110 / Salarié 625111), ses coordonnées, puis ses déplacements (date, trajet, motif, km A/R × 0,25 €, frais annexes + nature).
- Adresse obligatoire dans les 2 onglets (vérification des km) : n° et rue + code postal (5 chiffres) + ville, champs séparés. Encadré **carte grise** obligatoire : déjà fournie / jointe à l'envoi / aucun véhicule (refusé s'il y a des km) ; mention reprise sur le PDF et dans le mail. Si coordonnées mémorisées, « déjà fournie » est pré-cochée la fois suivante.
- Dès qu'il y a des frais annexes : encadré « justificatifs obligatoires » + case à cocher obligatoire.
- Signature facultative au doigt/souris (sinon signer la fiche imprimée). Coordonnées mémorisables sur l'appareil (localStorage `frais_coord`).
- PDF A4 paysage reprenant les 2 modèles du Comité (titre, tableau 5 lignes mini, total, « Je soussigné… » pour l'abandon, Visa du Président, pied Maison des sports). « Envoyer au Comité » : partage direct du PDF sur téléphone, sinon téléchargement + ouverture de la messagerie vers volley83@gmail.com (joindre le PDF à la main).
- **2 onglets** : « Frais de déplacement » (par défaut) et « Note de frais » (`/frais/#note`) pour les autres dépenses (billet, achat de matériel…) : date, **famille** (liste `FAMILLES` [libellé, code compta] en haut du script, + « Autre » sans code), précisions, montant ; pas de « Vous intervenez en tant que » ; justificatifs toujours obligatoires (case à cocher) ; remboursement uniquement ; PDF A4 portrait reprenant le modèle Word « Note de frais » (colonne Code, 8 lignes mini, récapitulatif des totaux par code comptable, Le demandeur / Le président : constante `PRESIDENT` = Gérald HENRY).
- Taux kilométrique selon l'imputation (objet `IMPUT` en haut du script) : 0,25 €/km bénévoles et intervenants, 0,60 €/km salariés (abandon de frais impossible pour un salarié : option grisée).

## Page d'accueil du portail — `accueil/index.html` (adresse provisoire)

- **Adresse** : https://volley83.github.io/accueil/ (non indexée). La racine `index.html` redirige toujours vers www.volley83.fr : ne la remplacer que sur demande de Clément.
- Maquette validée par Clément le 11/11/2026 (artifact Design « Portail Comité du Var – maquette accueil »).
- En-tête blanc : logo du Comité à gauche, nom centré, logo FFvolley à droite ; menu sur une 2e ligne avec « Nous contacter » à droite. Bandeau bleu : « Toutes les informations sur le volley-ball dans le Var », 3 gros boutons, bande « Prochain rendez-vous ».
- **Actualités** = publications Facebook récupérées par un robot (le Page Plugin officiel de Meta n'affiche plus les publications, seulement l'en-tête : abandonné le 11/11/2026).
  - `scripts/facebook.py`, lancé par `.github/workflows/facebook.yml` (toutes les 2 h en journée + bouton « Run workflow ») : lit `graph.facebook.com/me/posts` avec un jeton de Page par page, écrit `accueil/data/actus.json` (12 publications au plus, les 2 pages mélangées par date) et copie les images dans `accueil/data/img/` (les adresses d'images Facebook expirent).
  - Secrets GitHub : `FB_TOKEN_COMITE` (facebook.com/varvolley) et `FB_TOKEN_BEACH` (facebook.com/beachvolley83). Jetons de Page obtenus depuis un jeton utilisateur longue durée (application Meta en mode développement, permissions `pages_show_list` + `pages_read_engagement`). Jamais dans le dépôt ni dans une conversation. Sans secret ou en cas d'erreur, le robot garde l'existant.
  - Page : filtres Toutes / Comité / Beach-volley, texte coupé à 420 caractères avec « Lire la suite sur Facebook », 4 publications puis « Voir plus ». Sans `actus.json` : encadré renvoyant vers les 2 pages. Plus aucun contenu chargé depuis Facebook, donc pas de bandeau cookies.
- **À venir** : automatique. Stages (`stg_public_stages`) et tournois OPEN / M15-M18 4x4 (`chp_public`, regroupés par date et par famille, hors annulés), plus le petit tableau manuel `AGENDA` en haut du script pour ce qui n'existe nulle part ailleurs (dates du TIP). 6 lignes au plus ; ce qui tombe entièrement sur le week-end en cours n'y est pas répété (déjà dans « Ce week-end ») ; le premier rendez-vous à venir, week-end compris, alimente « Prochain rendez-vous ». Plateaux Pitchoun' Volley lus directement dans la table `pitchoun_plateaux` (lecture publique), dans « À venir » comme dans « Ce week-end ». **Formations** : à relier de la même façon quand la rubrique existera (demande de Clément du 13/11).
- **Ce week-end** (`chargeWeekend`) : samedi et dimanche de la semaine en cours. Matchs FFVB lus dans `championnats/data/ffvb.json`, résumés par catégorie et par jour (nombre de matchs, première heure, « résultats en ligne » quand tout est joué), sans les matchs contre un exempt (équipe « xxxxx », sans horaire, datés du samedi) ; tournois OPEN et M15/M18 4x4 lus par `chp_public` (hors annulés). Stages du Comité lus par `stg_public_stages` : affichés en tête de chaque jour du week-end qu'ils couvrent (un stage en semaine n'y figure pas). Sans rien ce week-end : « Pas de match… Prochain rendez-vous : <date> ». Si rien n'est lisible, le texte par défaut reste.
- Robot Facebook : une clé refusée fait échouer l'exécution (croix rouge + mail GitHub), les anciennes actualités restent affichées.
- Cartes Documents, Clubs, Formations, Bénévoles : « Bientôt disponible » (pages à construire). Pas de lien public vers `facturation/` ni `frais/`.
- Pied de page : adresse, 06 13 30 34 25, contact@volley83.fr, itinéraire Google Maps (fiche du Comité), Facebook ×2, Instagram `comite_var_volley`.

## Signalement d'infractions — `ris/index.html` (mise à jour 13/11)

- Plusieurs infractions par rencontre (date + n° de match communs, puis club / nature / précision par infraction ; envoi d'un signalement par infraction).
- Natures proposées : « Forfait ou pénalité (décision du Comité) » = Équipe absente, Joueur non réglementairement licencié, Absence du surclassement requis × Senior / Compet'Lib / Jeunes (sans article : la sanction est choisie à l'intégration) ; Pénalités du catalogue sauf engagements non conformes et implantations (filtre dans `fac_signal_login`) ; Marqueur non réglementairement licencié, Marqueur invalide ; Autre. Forfaits et arbitrage retirés de la liste.
- Confidentialité : champ « Précisions : nom du joueur, n° de licence… » (`fac_signalements.details` → `fac_ris_items.detail`). Jamais imprimé sur le RIS ; ajouté aux précisions de la ligne de facture du club. L'intitulé (publié sur le RIS) reste général.

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
- **Portail** : accueil fait (adresse provisoire `accueil/`, actualités = Facebook). Restent : documents, clubs, formations, bénévoles ; puis mettre l'accueil à la racine et transférer le domaine volley83.fr.

### Formules sportives (M15/M18 4x4 et OPEN)
- Table `chp_formules` (famille, nb_equipes, nom, poules « 4 (remarque), 3 », texte avec `{POULES}`) ; RPC `chp_admin_formules` / `chp_admin_formule` (fid null = création, p null = suppression). Script : `sql/championnats/supabase-championnats-formules.sql`.
- Admin › « Formules sportives » : bibliothèque modifiable. Admin › Inscriptions › Écrire aux inscrits : menu des formules (celles du nombre d'équipes engagées en premier), `{POULES}` remplacé par `poulesSerpentin()`.
- Serpentin d'après `classement()` ; non classées à la fin (ordre d'inscription) ; équilibrage des clubs : écart max 1 entre poules (échange avec l'équipe la plus proche au classement, à écart égal on déplace la moins bien classée). Le serpentin exact de Clément reste à recevoir.

