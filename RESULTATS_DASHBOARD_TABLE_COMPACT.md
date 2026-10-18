# Dashboard : tableau des exécutions compact

Le 17 octobre 2026 : retrait de la colonne « Dernier message » du tableau des
exécutions. Le message, les avertissements et la cause de blocage restent
accessibles dans « Détails », fermé par défaut, y compris pour les anciennes
lignes sans RunId. Les données reçues, le Sheet et l'export CSV sont conservés.
Aucun changement de validation, de lien permanent ou de logiciel principal.

## Vérification locale

- `node tools/Test-LDLCDashboardCompatibility.cjs` : succès, dont rendu de douze
  cellules, douze colonnes pour la ligne vide, échappement du message, présence
  des causes de blocage et compatibilité CSV.
- `node tools/Test-LDLCTelemetryIngestion.cjs` : succès ; persistance, doublons,
  rapports réordonnés, états terminaux et séparation des applications inchangés.
- Chromium réel en mode headless, données fictives et réseau bloqué : menus LDLC,
  Numerik's et ADDON vérifiés ; douze colonnes, détails fermés puis ouverts,
  contenu complet conservé, aucune erreur JavaScript ni injection HTML.
- À largeur 1 221 pixels, même message fictif de 5 700 caractères : hauteur de
  ligne avant **20 895,75 px**, après **83,17 px**. À largeur 1 365 pixels :
  entre 83,17 et 98,56 px selon l'application. Mesures de fixtures locales,
  pas de l'historique client du dashboard en ligne.

## Contrôles réels Windows GitHub Actions

Les deux scripts Node ont également réussi sous Windows Server 2022, sans
écriture sur le dashboard de production et sans lancer les applications :

- [LDLC : 39051480782](https://github.com/holyonefr/LDLC-Preparation/actions/runs/39051480782), code `c8c521b`, job `117450801648` : les deux étapes réussies.
- [Numerik's : 39051482528](https://github.com/holyonefr/Numerik-s-Preparation-PC/actions/runs/39051482528), code `5dbeb44`, job `117450805730` : les deux étapes réussies.

Le workflow `dashboard-validation.yml` est manuel uniquement, sans déclenchement
à chaque push. Ces contrôles portent sur le code Apps Script et son rendu ; ils
ne constituent pas un déploiement ou un essai du dashboard Google publié.

## Publication

Source et tests adaptés dans les dépôts LDLC et Numerik's ; le backend est commun
aux trois applications. **GitHub ne déploie pas automatiquement Apps Script.**
Aucune session OAuth Apps Script/clasp de l'utilisateur n'est disponible dans ce
cloud : le dashboard en ligne n'a pas été modifié ni validé après déploiement.
La publication reste à effectuer depuis le poste disposant du compte Google
Apps Script autorisé, avec `tools/Deploy-LDLCDashboard.ps1`, puis à vérifier sur
l'URL permanente. Ce déploiement publiera l'ensemble du backend local, y compris
ses corrections précédentes non encore déployées.
