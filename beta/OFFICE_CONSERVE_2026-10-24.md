# Microsoft Office / Microsoft 365 conservé — 24 octobre 2026

La désinstallation automatique d'Office est retirée dans les quatre éditions.
L'ancienne étape cherchait tout Microsoft Office, pas seulement Microsoft 365 :
elle pouvait fermer Word/Excel/Outlook, tenter MSI, Winget puis Click-to-Run.
Le workflow passe désormais directement du nettoyage OEM à l'épinglage Chrome.
Les fonctions spécifiques de suppression Office sont aussi retirées des scripts
principal et worker. Pas de paramètre caché permettant de les réactiver.

Le nettoyage OEM/antivirus conserve sa liste de cibles existante et ne sélectionne
aucun des quatorze noms Office/bureautique testés. LibreOffice reste dans le
catalogue des éditions qui l'installaient. Aucun changement d'interface, GPU,
constructeur, Chrome ou des corrections précédentes.

La nouvelle régression contrôle les sources et les deux scripts livrés : absence
des fonctions et appels Office, absence des exécutables Click-to-Run et de l'étape
de progression ; inventaire simulé avec Microsoft 365 FR/EN, Office 365 ProPlus,
Office perpétuel, OneNote, Visio, Project et autres suites. Elle exécute les vrais
sélecteurs et le nettoyage sans cible dans les modes All/Security/Oem, puis
vérifie que les détections McAfee, Norton et Booking restent actives.
Les anciens chemins sont identifiés dans une source historique sans lancer de
désinstalleur. Aucune installation Office réelle n'est utilisée pour ces tests.

Versions préparées : bêta **2.6.20**, candidats LDLC/Numerik's **2.6.17**,
ADDON **2.0.6**. ADDON est adapté dans ses deux arborescences. Les différences
entre éditions et les modifications UI locales préexistantes restent conservées.
Audit bêta sur le stable publié `3e21c92`, overlays préservés.

Publication autorisée uniquement en bêta selon l'instruction actuelle. Les trois
productions ne seront pas poussées sans l'accord demandé précédemment. Aucun
déploiement Apps Script ni suppression de lignes historiques du dashboard.

Validation native et preuves de cette livraison : à compléter après exécution.
