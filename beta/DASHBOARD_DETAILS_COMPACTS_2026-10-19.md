# Détails du dashboard — 19 octobre 2026

Un seul encadré par exécution : compteurs d'erreurs/avertissements et résumé
limité à deux lignes et 160 caractères, avec hauteur maximale de 33 pixels même
sans prise en charge du line-clamp. Aucun empilement de la liste complète
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

[Aperçu synthétique du tableau complet](evidence/dashboard-compact-2026-10-19/apercu-tableau-dashboard.png)
et [mesures navigateur](evidence/dashboard-compact-2026-10-19/browser-results.json).
Les en-têtes et statuts ne sont plus découpés au milieu des mots ; les largeurs
s'adaptent au contenu. Les tailles de police restent inchangées.

Publication : uniquement le dépôt bêta. Aucun changement des applications,
EXE ou dépôts de production. Cette correction concerne le rendu Apps Script,
pas les opérations Windows de préparation.

**Pas encore déployé sur Google.** Lors de la reprise du 19 octobre, le dashboard
permanent est de nouveau accessible en lecture (HTTP 200). Son HTML embarqué
contient encore l'ancien en-tête « Dernier message » et aucun `run-detail-card` :
la version en ligne reste ancienne. Aucun contenu client n'a été sauvegardé.
Aucune session clasp ni identité Google de publication n'est configurée ; les
fichiers de configuration ADC présents ne prouvent pas cette autorisation.
Un push GitHub ne met pas le dashboard en ligne.

Pour appliquer le correctif, dans le projet Apps Script permanent existant,
remplacer le code par `tools/google-apps-script/LDLC_ErrorTelemetry.gs`, conserver
les propriétés permanentes, puis Déployer → Gérer les déploiements → Modifier →
Nouvelle version → Déployer. Conserver le même déploiement, la même URL et le même
Sheet ; aucune remise à zéro ni suppression de l'historique. Avec une session
clasp autorisée, le helper existant `tools/Deploy-LDLCDashboard.ps1` effectue cette
mise à jour. Vérifier ensuite l'absence de l'ancienne colonne, le résumé court et
l'ouverture du texte complet sans modifier les exécutions.

Les 12 combinaisons Chromium, la compatibilité et l'ingestion ont été rejouées
sur ce correctif plus compact : aucun échec ni erreur JavaScript. L'aperçu reste
une validation locale avec données synthétiques, pas une capture du dashboard
de production corrigé.

Contrôle Windows GitHub réussi sur le commit `0b02a77` : compatibilité et ingestion,
codes de sortie 0, Windows Server 2022. [Passage réel](https://github.com/holyonefr/LDLC-Preparation-PC-test-app/actions/runs/39239344172).
