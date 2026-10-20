Livraison actuelle **2.6.11** : [correction AMD et résultats Windows](beta/AMD_UPDATE_2026-10-20.md).
Package AMD complet actuel, compatibilité et versions contrôlées. Publication
exclusivement dans cette bêta. Quatre lancements EXE et trois échanges dashboard validés.
L’installation matérielle sur un véritable GPU AMD reste à confirmer.

Livraison précédente : [transmission 2.6.10](TRANSMISSION_2026-10-20.md), autorisée
alors dans les quatre dépôts. Dashboard permanent en version 47.

# LDLC Preparation PC — version beta

Depot de test : **holyonefr/LDLC-Preparation-PC-test-app**.
Base LDLC stable : commit `978b498608586efffb173bee237a294b1452fa0a`, voir `beta/sync.json`.
Le 20 octobre, l'utilisateur autorise aussi la livraison de la correction
Chrome/epinglage/portables AMD dans les trois productions. Le module carte mere
reste exclusivement dans cette beta.

La preparation LDLC habituelle est conservee. Tout a la fin de la phase
Installation des applications (60 %), apres le dernier logiciel et avant toute
configuration du bureau, la beta prepare le logiciel de carte mere : MSI Center,
ASUS DriverHub, GIGABYTE Control Center ou ASRock APP Shop selon le constructeur
et les controles du prototype. Elle telecharge un installateur officiel verifie
et cree son raccourci sur le vrai Bureau, y compris OneDrive. **Installation manuelle**
par le technicien, aucun lancement constructeur automatique. Portables exclus
avant reseau/raccourci. Aucun nouveau pilote, BIOS, antivirus ou module facultatif
n'est installe par cette fonctionnalite. Dans cette beta, AMD Adrenalin est ignore
sur les portables ; le parcours NVIDIA reste inchange. Un echec reel est signale avec sa cause ; le repli manuel normal n'est pas
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

Livraison historique precedente : [retour au traitement historique McAfee](beta/MCAFEE_ROLLBACK_2026-10-20.md),
version beta 2.6.8. La livraison historique 2.6.9 est décrite dans son rapport ; la livraison courante est 2.6.11. McAfee quitte le nouveau parcours interactif et retrouve le
worker historique limite a 90 secondes. Norton et les autres corrections restent
conserves. Cette nouvelle publication est limitee au depot beta.

Livraison precedente : [Chrome sans attente et désinstallateurs antivirus visibles](beta/CHROME_ANTIVIRUS_2026-10-20.md).
Le parcours McAfee de ce rapport historique est remplace par le retour ci-dessus.

## Synchronisation pour les prochaines corrections

La beta reste synchronisee pour chaque correction demandee. La publication de
cette correction Chrome/epinglage/portables AMD dans les trois productions est
autorisee le 20 octobre. L'integration carte mere reste reservee a la beta.
Les anciens agrandissements UI locaux de production sont laisses hors livraison.
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

Correction Chrome/AMD du 20 octobre : bouton global « Definir par defaut » tente
en premier, verification Windows plus courte, epinglage Chrome reellement controle
et exclusion AMD des portables avant tout telechargement. Resultats et limites :
[beta/CHROME_AMD_2026-10-20.md](beta/CHROME_AMD_2026-10-20.md).

Validation Windows terminee : voir [beta/RESULTATS_WINDOWS.md](beta/RESULTATS_WINDOWS.md).
Quatre ouvertures/fermetures, suite release, vrais telechargements constructeurs
et raccourcis sont controles par le workflow. Voir le rapport pour les versions
du code effectivement validees et la distinction entre essais reels et simulations.


Derniere campagne multi-editions : [12 passages Windows des quatre applications](beta/TESTS_QUATRE_APPLICATIONS_2026-10-19.md).
La comparaison historique de la beta utilise les fixtures controlees dans
`tools/fixtures/completion-before-c205efc`, car l'historique stable n'a pas ete copie.
Aucune fixture historique ne doit entrer dans le build de l'application.

Dernière correction UI : [bouton Quitter entier et centré, validation Windows](beta/QUIT_BUTTON_2026-10-19.md).
