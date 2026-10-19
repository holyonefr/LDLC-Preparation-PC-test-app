# Dashboard légèrement plus lumineux — 19 octobre 2026

Le fond général, les cartes, le menu, les champs et les tableaux utilisent des
teintes ardoise un peu plus claires. Bordures et textes secondaires sont plus
visibles. Le thème reste sombre et mat ; les couleurs de statut et les tailles
de texte sont inchangées. Le résumé compact des exécutions est conservé.

[Vue d'ensemble](evidence/dashboard-light-2026-10-19/dashboard-lumineux.png) et
[exécutions](evidence/dashboard-light-2026-10-19/executions-lumineuses.png) : aperçus
Chromium locaux, avec données synthétiques uniquement.

Contrôles : douze combinaisons navigateur (trois éditions, quatre largeurs),
compatibilité et ingestion Node réussies ; aucune erreur JavaScript. La comparaison
avant/après relève les mêmes tailles de police (corps 14 px, titre 44 px et cellules
12 px dans la vue desktop testée). Le contraste calculé sur les couleurs réellement
appliquées est de 11,16:1 pour le texte principal et 7,38:1 pour le secondaire sur
les cartes. Mesures dans `evidence/dashboard-light-2026-10-19/render-results.json`.
Seule la fonction CSS du dashboard a changé, sans modification des opérations,
des données, des EXE ou des UI All in App.

Source enregistrée uniquement dans la bêta. Pas encore publiée sur Google :
l'autorisation du propriétaire est nécessaire. La configuration cloud OAuth a été
préparée séparément, avec un secret personnel protégé et des helpers dans
`/workspace/cloud-setup/google-oauth`. Les tests de préparation et les simulations
de contrôle d'accès passent ; ils ne prouvent pas une connexion Google réelle.
Après consentement Google, saisie du secret dans les paramètres et publication de
l'environnement, vérifier `connect.mjs --check` avant toute publication du
déploiement permanent. Ne jamais annoncer le rendu en ligne sur la seule base du
push GitHub ou des aperçus locaux.
