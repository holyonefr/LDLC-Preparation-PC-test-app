# Dashboard — thème plus lumineux et titres, 20 octobre 2026

Publié sur le déploiement Google permanent en **version 47** (version précédente : 46).
Seule la fonction CSS a changé dans la source distante. La configuration, le
manifeste, les données et toute la logique serveur/client sont inchangés.
La relecture API de la version et du contenu déployés confirme l’empreinte de la
source ; la page réelle répond HTTP 200 avec le nouveau CSS et la police intégrée.

Le fond passe de `#11161c` à `#202b3a` et les panneaux de `#1b222c` à `#2b394b`.
Le titre centré et le sous-titre utilisent **Outfit**, une police variable intégrée
en WOFF2 avec accents français. Aucun appel à Google Fonts n’est nécessaire.
La licence SIL OFL et la provenance sont conservées dans `tools/google-apps-script/fonts/`.
Le sous-titre est présenté dans une petite pastille ; les tailles du titre restent
adaptatives. La police des tableaux et leurs détails repliés sont conservés.

Contrôles Chromium sur des données fictives à 1600, 1366 et 390 px : police chargée,
titres centrés, aucun texte coupé ni débordement de page, aucun appel réseau pour
la police, aucune erreur JavaScript. Le contraste des textes principaux contrôlés
est compris entre 6,29:1 et 10,82:1. Les longues erreurs restent repliées et les
contenus complets accessibles, avec échappement HTML et 12 colonnes d’exécution.
Les suites existantes de compatibilité, ingestion et validation passent.

Les aperçus contiennent uniquement des données de démonstration. Le navigateur
cloud n’a pas pu accéder au DOM du cadre Apps Script de la page réelle : son rendu
visuel n’a donc pas été confirmé par un navigateur connecté. La vérification en
ligne repose sur la relecture API du déploiement et le HTML servi réellement.
Les contrôles de mise en page et de chargement de police sont effectués sur le
même rendu avec données fictives, dans Chromium local.

Aperçus et résultats : `tools/google-apps-script/evidence/2026-10-20-style/`.
