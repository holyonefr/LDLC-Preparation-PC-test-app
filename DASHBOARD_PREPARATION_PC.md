# Dashboard Preparation PC - passation du 2026-10-13

## Etat livre

Version logicielle commune : 2.6.1, executables 2.6.1.0.
Le dashboard permanent est commun aux deux editions et a l'ADDON. Il affiche
Dashboard Preparation PC, avec un theme ardoise mat : plus de neon, de halo,
de vert fluorescent ni d'image de circuits. Les fonds Windows et UI des EXE
ne sont PAS modifies. L'icone Numerik's reste icoNKS et l'icone LDLC est conservee.

Les menus, statistiques, erreurs, rapports et historiques sont separes entre :
- All In App LDLC : LDLC_PREPARATION_PC ;
- All In App Numerik's : NUMERIKS_PREPARATION_PC ;
- Preparation ADDON : LDLC_PREPARATION_ADDON, traitement historique conserve.

Les tableaux gardent le nom de machine dans Poste et ajoutent la colonne
All In App. Les CSV ajoutent cette information sans retirer les anciens champs.
Reussite : vert doux ; erreur : rouge doux ; avertissement : ambre ; information : bleu gris.

## Identification durable des EXE

Le moteur commun reste dans modules/05.Telemetry.ps1. Pendant l'assemblage,
tools/Rebuild-LDLCPreparationPC.ps1 lit Edition dans sync/edition.json et embarque
l'identite dans le script principal ET dans le worker :

| Edition locale | Source envoyee | ApplicationSource | Edition envoyee |
| --- | --- | --- | --- |
| LDLC | LDLCPreparationPC | LDLC_PREPARATION_PC | LDLC |
| NUMERIKS | NumeriksPreparationPC | NUMERIKS_PREPARATION_PC | NUMERIKS |

Edition est un champ optionnel ajoute aux executions et evenements. RunId,
ComputerName, UserName, ToolVersion, erreurs, durees et anciens champs restent
compatibles. UserName peut etre vide : aucun compte utilisateur ou Google
interactif n'est necessaire pour une remontee. Endpoint et cle existants conserves.

Le serveur accepte les anciens formats et recherche aussi Numerik dans Source,
ApplicationSource, Edition/Brand/Marque et ScriptPath. Un ancien EXE Numerik's
clairement nomme peut donc etre reconnu meme s'il envoie encore la source LDLC.
Une ancienne copie identique, encore nommee LDLC et sans aucune indication
Numerik's dans ses donnees, est INDISTINGUABLE : ne pas inventer sa marque ni
reclasser l'historique au hasard. Distribuer l'EXE 2.6.1.0 pour une identification fiable.

## Sources et synchronisation

Depots : https://github.com/holyonefr/LDLC-Preparation et
https://github.com/holyonefr/Numerik-s-Preparation-PC. Toujours git fetch et
repartir de la version GitHub, jamais d'une ancienne copie Desktop ou du depot ADDON.

Le coeur technique et ses tests sont synchronises par tools/Sync-PreparationCore.ps1.
Lire SYNCHRONISATION.md. Les profils d'edition, icones, modules/99.UI.ps1,
modules/45.Wallpaper.ps1 et assets sont proteges. Ne jamais copier une UI/fond
d'une edition sur l'autre. Aucun nouvel accueil Numerik's n'est ajoute.

tools/google-apps-script/LDLC_ErrorTelemetry.gs contient le backend, le HTML,
le CSS et le JavaScript. Le dashboard reste un fichier protege de la synchronisation
automatique. Pour cette demande commune, les changements du dashboard ont ete
appliques explicitement aux deux depots. Deployer UNIQUEMENT depuis LDLC canonique,
avec tools/Deploy-LDLCDashboard.ps1 : mettre a jour le deploiement EXISTANT,
ne jamais creer un nouveau Sheet, une nouvelle URL ou changer les proprietes d'acces.

## Verification

Les deux editions passent 22 tests PowerShell, 2 suites JavaScript et les diagnostics
du lanceur compile, dans un runtime isole sans preparation reelle du PC hote.
Le test Test-PreparationTelemetryEdition.ps1 verifie les identites embarquees,
les succes et erreurs ainsi qu'un utilisateur vide, sans reseau.

Test-PreparationEditionLive.ps1 est un test reseau volontaire, NON inclus dans la
suite automatique de release : il cree cinq RunId synthetiques uniques, teste
LDLC, Numerik's nouveau/ancien, LDLC ancien, ADDON, les replays et l'historique.
Il sauvegarde le JSON initial dans TEMP et supprime uniquement SES propres RunId
dans finally. Ne pas le lancer pour une simple compilation ou sans accord de test.
Le test live du 2026-10-13 a reussi, ses lignes ont ete retirees ; les 1169 executions
et 71 groupes d'erreurs (408 details) presents avant la mise a jour ont ete conserves.

## Remise a zero demandee ensuite

L'utilisateur a explicitement demande une remise a zero globale des executions,
erreurs et rapports du Sheet permanent, toutes editions comprises. Le suivi initial
a d'abord ete sauvegarde et relu dans un JSON local NON publie sur GitHub :
%LOCALAPPDATA%/LDLCPrepTool/TelemetryBackups/avant-remise-a-zero-20261013-214452.json.
Il contient les 1169 executions et les 408 erreurs detaillees avant suppression.
Ce JSON est l'export du suivi HTML, pas une copie integrale du classeur : les
autres evenements techniques non affiches n'y figurent pas. Le reset a retire
1169 lignes Executions et 559 lignes de la feuille Erreurs (evenements compris).
tools/Reset-LDLCTelemetrySheet.ps1 utilise l'action resetTelemetry du backend,
vide les feuilles Executions/Erreurs en gardant les en-tetes et recalcule Synthese.
Les rapports HTML sont derives de ces donnees : aucun historique parallele a vider.
Le deploiement Apps Script final est la version 45, sur la MEME URL.
Verification apres reset : 0 execution, 0 erreur et rapports vides.
Les futurs rapports et nouvelles executions restent acceptes apres la remise a zero.
Une ancienne file hors ligne d'un technicien peut renvoyer des anciens RunId :
cette demande n'introduit pas de blocage des anciens EXE ou des replays legitimes.

Le rendu permanent a ete verifie sur ordinateur et mobile. Aucune execution metier
complete n'a ete lancee sur une vraie machine neuve pendant cette modification.
Les executables ne sont pas signes Authenticode : aucun certificat disponible.

## Livraison

- LDLC : dist/LDLCPreparationPC.exe, scripts generes et SHA256SUMS.txt.
- Numerik's : dist/Numerik'sPreparationPC.exe, scripts generes et SHA256SUMS.txt.
- Les ZIP 2.6.1.0 sont generes localement, ignores par Git ; EXE suivis via Git LFS.
- Compiler et tester chaque edition depuis son profil et ses ressources propres.

## Liens permanents

Google Sheet : https://docs.google.com/spreadsheets/d/1PtMhZC_7dQi7aw278XPQ1udmV9ol5hrD_G4mdSwXWA0/edit

Dashboard HTML : https://script.google.com/macros/s/AKfycbwYe2r5-y8HeyfLjslbq7wI2BdFH0sj7TLJQSiUyeRdt_z7yytyTKsPQPPcT0HUcAci3g/exec?key=LDLC-Dashboard-2026-288d06206918450293ed29d54fefc801

Projet Apps Script : https://script.google.com/home/projects/19Sn2qzKl3XwTV8Gxq1RLELhJcg5Uy-iXk_YglKJlggyduRai_xZL9WhP/edit
