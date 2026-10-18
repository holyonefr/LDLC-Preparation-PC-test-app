# LDLC Preparation PC — version beta

Depot de test : **holyonefr/LDLC-Preparation-PC-test-app**.
Base LDLC stable : commit `a2a57ee2d28203fded79802eae2a58883d996c7e`.
Les trois depots de production ne recoivent aucun push pour cette livraison.

La preparation LDLC habituelle est conservee. Apres les installations et avant
les applications par defaut, la beta prepare le logiciel de carte mere : MSI Center,
ASUS DriverHub, GIGABYTE Control Center ou ASRock APP Shop selon le constructeur
et les controles du prototype. Elle telecharge un installateur officiel verifie
et cree son raccourci sur le vrai Bureau, y compris OneDrive. **Installation manuelle**
par le technicien, aucun lancement constructeur automatique. Portables exclus
avant reseau/raccourci. Aucun nouveau pilote, BIOS, antivirus ou module facultatif
n'est installe par cette fonctionnalite. Le parcours GPU deja present reste celui
de LDLC. Un echec reel est signale avec sa cause ; le repli manuel normal n'est pas
une erreur de preparation. Rapport : `LDLC_VENDOR_UTILITY_RESULT.json` du runtime.

Les cinq modules PowerShell utiles sont embarques dans le worker et le script du
vrai EXE. Ils sont materialises et verifies par SHA256 uniquement a cette etape :
aucun telechargement constructeur au demarrage de l'interface. Le raccourci GCC
pointe uniquement vers le coeur signe, pas vers le wrapper MB Update/RGB Sync.

## Synchronisation pour les prochaines corrections

La beta doit rester a jour a chaque modification demandee. Pendant le gel de
publication des autres applications, travailler et pousser uniquement ici.
`beta/sync.json` indique le commit stable et les adaptations beta a conserver.

```powershell
# Audit en lecture seule, code non nul en cas de retard ou conflit.
./tools/Sync-LDLCBeta.ps1 -StableRepository ../LDLC-Preparation
# Appliquer les changements ordinaires sans ecraser les adaptations beta.
./tools/Sync-LDLCBeta.ps1 -StableRepository ../LDLC-Preparation -Apply
```

Un changement stable dans un fichier adapte a la beta demande une fusion explicite.
Apres cette fusion seulement, `-Apply -AcceptMergedOverlays` met a jour la reference.
Les conflits ordinaires restent refuses. Les fichiers propres a la beta sont gardes,
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
