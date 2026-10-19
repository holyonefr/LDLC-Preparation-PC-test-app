# Détails du dashboard — 19 octobre 2026

Un seul encadré par exécution : compteurs d'erreurs/avertissements et résumé
limité à trois lignes et 160 caractères. Aucun empilement de la liste complète
dans le tableau. « Voir les détails » ouvre une fenêtre séparée, refermable par
Fermer ou Échap ; les messages complets restent accessibles et échappés.
Le bouton de suppression conserve sa propre colonne. Les statuts reviennent
à la ligne et ne débordent plus sur les actions.

Validation locale sur le code final :

- 12 combinaisons réelles Chromium : LDLC, Addon et Numerik's sur quatre largeurs
  (1600, 1024, 768 et 390 pixels), avec données synthétiques uniquement.
- Arrêt utilisateur, huit avertissements avec texte long, erreur 1603 simulée,
  réussite sans message et exécution historique sans identifiant.
- Encadrés contenus dans leur cellule, bouton de suppression séparé, résumé
  court, texte intégral conservé, fermeture du dialogue et maintien du dialogue
  pendant un rafraîchissement du tableau. Aucune erreur JavaScript.
- Texte HTML hostile affiché comme texte ; aucune balise injectée exécutée.
- Tests existants de compatibilité dashboard et d'ingestion Node réussis.

[Aperçu synthétique](evidence/dashboard-compact-2026-10-19/apercu-details-dashboard.png)
et [mesures navigateur](evidence/dashboard-compact-2026-10-19/browser-results.json).

Publication : uniquement le dépôt bêta. Aucun changement des applications,
EXE ou dépôts de production. Cette correction concerne le rendu Apps Script,
pas les opérations Windows de préparation.

**Pas encore déployé sur Google.** Le contrôle direct de script.google.com
renvoie un refus du proxy CONNECT HTTP 403. Aucune session clasp autorisée
n'est disponible. Les domaines Google nécessaires ont été ajoutés au brouillon
de configuration cloud, en préservant la liste existante ; ce brouillon doit
être appliqué dans les paramètres de l'environnement et l'accès Google de
déploiement doit être disponible. Un push GitHub ne met pas le dashboard en ligne.
Après rétablissement de ces accès, déployer sur le déploiement permanent avec
tools/Deploy-LDLCDashboard.ps1 et vérifier le rendu réel sans modifier les données.

Contrôle Windows GitHub réussi sur le commit `0b02a77` : compatibilité et ingestion,
codes de sortie 0, Windows Server 2022. [Passage réel](https://github.com/holyonefr/LDLC-Preparation-PC-test-app/actions/runs/39239344172).
