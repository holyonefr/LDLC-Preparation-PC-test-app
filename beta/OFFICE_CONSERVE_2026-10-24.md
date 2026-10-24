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

## Validation native terminée

| Édition | Exécution Windows GitHub | Résultat | Vrais Preview/fermetures |
| --- | --- | --- | --- |
| Bêta 2.6.20 publiée | [40080700297](https://github.com/holyonefr/LDLC-Preparation-PC-test-app/actions/runs/40080700297) | Réussi | 4 |
| ADDON 2.0.6 candidat | [40080808029](https://github.com/holyonefr/LDLC-Preparation-Addon/actions/runs/40080808029) | Réussi | 4 |
| LDLC 2.6.17 candidat | [40080908459](https://github.com/holyonefr/LDLC-Preparation/actions/runs/40080908459) | Réussi | 4 |
| Numerik’s 2.6.17 candidat | [40088688882](https://github.com/holyonefr/Numerik-s-Preparation-PC/actions/runs/40088688882) | Réussi | 4 |

Les quatre validations ont terminé avec succès au premier passage. Le contrôle
Office passe **37 assertions** par arborescence, principal/worker livrés compris :
quatorze noms de produits protégés, trois modes de nettoyage, aucun Office ciblé,
conservation des cibles McAfee/Norton/Booking. ADDON est contrôlé dans ses deux
arbres. La bêta est aussi vérifiée sous PowerShell 7, en plus de Windows
PowerShell 5.1 ; le chemin historique est reconnu par sept assertions, sans
exécuter son désinstalleur. Les suites complètes vérifient le workflow et les
cas de fin, erreur, interruption et transport. **Seize Preview/fermetures réels**
des EXE compilés sont confirmés.

Les trois candidats ont également envoyé des résultats simulés de réussite,
erreur 1603 et arrêt utilisateur via le vrai client et le dashboard : les trois
statuts ont été acquittés et relus, puis seules leurs propres lignes CODEX-TEST
ont été nettoyées. Ce sont des vérifications du transport réel, sans préparer
un PC ni modifier l'historique des interventions.

L'EXE bêta 2.6.20 testé est publié au commit
`72e4979b2f1fb264c5b252064e3e8425a23462a1`, source
`c4defdd00a143d93773c501cb3a6fb31323660d9`. Empreinte reçue et revérifiée :
`96B151A526A1E5C53DA5F13A62990D74AE967DD93CF133786ACE8746D49B0776`.
Les trois EXE candidats restent disponibles dans l'artefact
`chrome-amd-windows-preview`, dossier `candidate-delivery`, sur leurs exécutions.
Leur publication demeure en attente de l'accord demandé ; les trois refs de
production restent identiques à celles d'avant cette correction.

[Preuves structurées](evidence/office-preserved-2026-10-24/windows-validation.json).
Le préfixe du module de nettoyage est conservé octet pour octet : seul le bloc
Office a été retiré. Les empreintes des UI existantes sont inchangées. Les
patches des candidats utilisent le format binaire Git standard pour réduire
la taille des suppressions ; les modules obtenus sont identiques à la source
attendue, y compris lors du contrôle avec des fins de lignes Windows.

Ces essais sont natifs sur **Windows Server 2025 GitHub**, avec inventaires Office
simulés. Aucun Office réel installé/licencié ni nouveau parcours complet de VM
Windows 11 n'a été utilisé. Aucun désinstalleur Office n'a été lancé. Les tests
ne changent pas les réglages d'Office sur un vrai poste ; ils vérifient le retrait
de son code de suppression et la non-sélection de ses produits par le nettoyage.
