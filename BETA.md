# LDLC Preparation PC — version beta

Depot de test : **holyonefr/LDLC-Preparation-PC-test-app**.
Base LDLC stable : commit `a2a57ee2d28203fded79802eae2a58883d996c7e`.
Les trois depots de production ne recoivent aucun push pour cette livraison.

La preparation LDLC habituelle est conservee. Tout a la fin de la phase
Installation des applications (60 %), apres le dernier logiciel et avant toute
configuration du bureau, la beta prepare le logiciel de carte mere : MSI Center,
ASUS DriverHub, GIGABYTE Control Center ou ASRock APP Shop selon le constructeur
et les controles du prototype. Elle telecharge un installateur officiel verifie
et cree son raccourci sur le vrai Bureau, y compris OneDrive. **Installation manuelle**
par le technicien, aucun lancement constructeur automatique. Portables exclus
avant reseau/raccourci. Aucun nouveau pilote, BIOS, antivirus ou module facultatif
n'est installe par cette fonctionnalite. Le parcours GPU deja present reste celui
de LDLC. Un echec reel est signale avec sa cause ; le repli manuel normal n'est pas
une erreur de preparation. Rapport : `LDLC_VENDOR_UTILITY_RESULT.json` du runtime.

Si la detection ou le telechargement constructeur echoue, un raccourci
**Telechargement officiel - nom du logiciel** ouvre sa page officielle pour une
recuperation manuelle. Cet etat reste un avertissement avec la cause exacte ;
il n'est jamais presente comme un installateur telecharge ou une installation
reussie. Un Bureau inaccessible est signale avec l'adresse officielle.

Les cinq modules PowerShell utiles sont embarques dans le worker et le script du
vrai EXE. Ils sont materialises et verifies par SHA256 uniquement a cette etape :
aucun telechargement constructeur au demarrage de l'interface. Le raccourci GCC
pointe uniquement vers le coeur signe, pas vers le wrapper MB Update/RGB Sync.

## Synchronisation pour les prochaines corrections

La beta doit rester a jour a chaque modification demandee. Pendant le gel de
publication des autres applications, pousser uniquement ici. Exception de travail
local demandee le 19 octobre : agrandir les deux textes de progression dans LDLC
et Addon, en conservant Numerik's intact ; leurs EXE et publications restent geles.
`beta/sync.json` indique le commit stable et les adaptations beta a conserver.

```powershell
# Audit en lecture seule, code non nul en cas de retard ou conflit.
./tools/Sync-LDLCBeta.ps1 -StableRepository ../LDLC-Preparation
# Appliquer les changements ordinaires sans ecraser les adaptations beta.
./tools/Sync-LDLCBeta.ps1 -StableRepository ../LDLC-Preparation -Apply
```

Un changement stable dans un fichier adapte a la beta demande une fusion explicite.
Apres cette fusion seulement, `-Apply -AcceptMergedOverlays` met a jour la reference.
Les conflits ordinaires restent refuses. Pendant le gel de la production, chaque
correction propre a cette beta doit aussi etre ajoutee aux OverlayPaths, afin que
la synchronisation ne remplace jamais la correction par un ancien fichier stable. Les fichiers propres a la beta sont gardes,
les suppressions stables sont propagees, les livraisons `dist/` sont reconstruites.
Le helper n'a aucune commande de push et ne modifie pas le depot source.
Ne jamais utiliser `Sync-PreparationCore.ps1 -Publish` pour cette beta.

## Livraison et validation

Le fichier a utiliser est `dist/LDLCPreparationPC.exe` de **ce depot**.
Le workflow manuel `beta-validation.yml` compile le vrai EXE sous Windows, execute
les tests release et beta, puis fait quatre ouvertures/fermetures de l'interface.
Les operations destructives et installations materielles sont simulees ; aucun
installateur constructeur reel n'est execute sur la VM. La publication finale des
livraisons est limitee au depot beta, apres reussite des controles.
Les workflows de test restent manuels pour eviter un lancement a chaque push.
Une validation VM ne prouve pas l'installation ni la compatibilite sur tout PC physique.

Validation Windows terminee : voir [beta/RESULTATS_WINDOWS.md](beta/RESULTATS_WINDOWS.md).
Quatre ouvertures/fermetures, suite release, vrais telechargements constructeurs
et raccourcis sont controles par le workflow. Voir le rapport pour les versions
du code effectivement validees et la distinction entre essais reels et simulations.


Derniere campagne multi-editions : [12 passages Windows des quatre applications](beta/TESTS_QUATRE_APPLICATIONS_2026-10-19.md).
La comparaison historique de la beta utilise les fixtures controlees dans
`tools/fixtures/completion-before-c205efc`, car l'historique stable n'a pas ete copie.
Aucune fixture historique ne doit entrer dans le build de l'application.

Dernière correction UI : [bouton Quitter entier et centré, validation Windows](beta/QUIT_BUTTON_2026-10-19.md).
