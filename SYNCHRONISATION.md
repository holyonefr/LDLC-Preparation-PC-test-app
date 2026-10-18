# Priorite beta — instruction utilisateur du 18 octobre 2026

Pour ce depot, suivre BETA.md et tools/Sync-LDLCBeta.ps1. La commande de publication sur les deux depots ci-dessous est historique et ne doit pas etre utilisee pour la beta. Pousser uniquement LDLC-Preparation-PC-test-app, garder cette beta synchronisee pour les prochaines corrections.

# Synchronisation LDLC / Numerik's

Mise en place le 2026-10-13 depuis LDLC commit affa8b8, version technique 2.6.0.

Deux depots GitHub independants :
- https://github.com/holyonefr/LDLC-Preparation
- https://github.com/holyonefr/Numerik-s-Preparation-PC

Numerik's contient initialement TOUS les fichiers suivis de LDLC : fonctionnalites,
scripts, worker, lanceur, tests, images, icone et dashboard. Aucun visuel n'a ete
change lors de la duplication. Depuis 2.6.2, l'accueil boutiques demande ensuite
est implemente UNIQUEMENT dans le dossier branding/startup de Numerik's.

## Propriete des fichiers

`sync/shared-files.json` est la liste explicite des fichiers techniques partages.
Les modules de preparation, installations, GPU, applications par defaut, Windows
Update, telemetrie cliente et outils de build/tests y figurent. Les noms internes
LDLC restent volontairement compatibles ; renommer les fonctions n'est pas requis.

NE JAMAIS synchroniser automatiquement :
- `modules/99.UI.ps1` : interface de lancement et mini-interface propres a l'edition ;
- `modules/45.Wallpaper.ps1` : choix et configuration des fonds Windows ;
- `assets/`, `branding/`, `wallpapers/`, `themes/`, images, logos, icones et polices ;
- `telemetry.config.json`, profils `sync/edition.json`, README et passation propres ;
- le HTML/dashboard dans `tools/google-apps-script/` et ses outils de deploiement ;
- `dist/` : les EXE/scripts generes doivent etre recompiles depuis les ressources locales.

Ces protections sont imposees dans le code, en plus des deux manifestes locaux.
Un ajout au manifeste ne permet pas de contourner la protection d'une UI/image.
Tout fichier nouveau non declare dans SharedFiles reste propre au depot.
Une nouvelle fonctionnalite technique doit declarer ses fichiers dans SharedFiles
et son module dans build-order.txt si necessaire. Ne pas y introduire de module visuel.
Une correction interne aux fichiers UI/fond proteges doit etre adaptee explicitement
dans chaque edition : copier ces fichiers en entier detruirait leurs personnalisations.
L'accueil Numerik's reste dans branding/startup, sans synchronisation. Le lanceur
partage appelle le point optionnel PreparationEdition.Startup.BeforeStart AVANT
de lire le script PowerShell. Sans ce point local (LDLC), le demarrage reste inchange.
Le build compile les .cs locaux et embarque leur logo original, sans importer ceux
de l'autre depot. Les tests verifies couvrent annulation, validation et conservation
du choix ; lire BOUTIQUES_NUMERIKS.md dans Numerik's. Version commune : 2.6.2.0.

Le backend Apps Script reste commun et permanent, deploye uniquement depuis le depot
LDLC canonique. Depuis 2.6.1, les statistiques LDLC/Numerik's/ADDON sont separees dans
ce meme dashboard/Sheet par ApplicationSource. Le build lit Edition dans le profil
local et embarque Source, ApplicationSource et Edition dans principal ET worker.
Ne jamais synchroniser le profil d'une edition sur l'autre. Les anciens formats restent
acceptes ; une ancienne copie sans aucune indication Numerik's ne peut pas etre identifiee.
Lire DASHBOARD_PREPARATION_PC.md pour le contrat de compatibilite et les tests live.
Le dashboard protege a ete adapte explicitement dans les deux depots pour cette demande
commune ; cela n'autorise pas une synchronisation automatique des futurs visuels.

## Une commande pour les deux editions

Toujours recuperer les derniers commits GitHub des DEUX depots avant de modifier.
Exemple Windows (adapter les chemins aux checkouts de l'autre PC) :

```powershell
$ldlc = 'D:\Codage LDLC\GitHubSource\LDLC-Preparation-20260621-102420'
$numeriks = 'D:\Codage LDLC\Numerik-s-Preparation-PC'
& "$ldlc\tools\Sync-PreparationCore.ps1" -SourceRepository $ldlc -TargetRepository $numeriks
```

Sans option : audit seulement. Pour copier le coeur technique : ajouter `-Apply`.
Pour reconstruire les EXE et tester les DEUX editions : `-Apply -BuildAndTest`.
Pour appliquer, compiler, tester, commiter et pousser les DEUX depots :

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$ldlc\tools\Sync-PreparationCore.ps1" -SourceRepository $ldlc -TargetRepository $numeriks -Publish
```

Le sens peut etre inverse pour une correction commencee dans Numerik's.
`sync/state.json` conserve les empreintes communes de la derniere synchronisation.
Les empreintes texte tolerent les differences CRLF/LF et BOM de Git Windows.
Si la cible a change depuis la base commune, le transfert est bloque AVANT ecriture.
Si les deux cotes ont change differemment, fusionner la correction puis relancer.
Ne jamais choisir automatiquement un fichier parce que sa date est plus recente.
Une suppression technique se fait avec git rm, en gardant son entree dans le manifeste
pour que le tombstone soit propage ; les fichiers visuels ne sont jamais supprimes.

La compilation lit `sync/core-version.json` pour la version technique commune,
et les images/UI/icone/configuration de CHAQUE checkout. Elle ne copie pas l'EXE
d'une marque sur l'autre. Actualiser la version commune lors d'une nouvelle release.

Les noms de livraison sont lus par tools/PreparationDelivery.Common.ps1 depuis
DeliveryBaseName dans sync/edition.json, protege et propre a chaque edition.
Sans ce champ, LDLC conserve LDLCPreparationPC. Numerik's utilise Numerik'sPreparationPC
pour l'EXE, sa configuration .exe.config, les scripts principal/worker et le ZIP.
Les ressources embarquees et noms internes du runtime restent stables pour compatibilite.
Ne pas remplacer ces identifiants internes globalement pour changer un nom de livraison.
La publication et les tests calculent leurs chemins depuis le profil local de chaque depot.
Verification de ce changement : les deux builds passent 21 tests PowerShell,
2 suites JavaScript et les diagnostics du lanceur. Le test de livraison couvre
l'apostrophe du nom Numerik's, les fichiers associes et le rejet des chemins invalides.

`-Publish` exige main dans les deux depots, une connexion Git autorisee et des
modifications limitees au coeur/artefacts generes. Commiter les personnalisations
et documents propres separement avant ce mode. Tous les tests/commits precedent
les deux pushes. Git ne peut pas rendre deux pushes atomiques : si le second echoue,
le script indique le depot restant ; relancer apres correction reseau/authentification.
Un simple git push dans un seul depot ne synchronise pas automatiquement l'autre.
La procedure normale pour une mise a jour technique commune est donc -Publish.

## Verification

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/Test-PreparationCoreSync.ps1
powershell -STA -NoProfile -ExecutionPolicy Bypass -File tools/Test-LDLCRelease.ps1
```

Les tests de synchronisation simulent deux UI/logos/fonds differents, une correction
dans chaque sens, conflits, audit sans mutation, traversals, changements concurrents
et suppressions techniques. Ils verifient la conservation exacte des visuels locaux.
La suite de release teste le lanceur compile et le workflow dans un runtime isole,
sans lancer de preparation ni modifier les applications par defaut du PC hote.

Resultats du 2026-10-13 : commande -Apply -BuildAndTest executee avec succes sur
les deux checkouts. Chaque edition passe 20 tests PowerShell, 2 suites JavaScript
et les diagnostics du lanceur compile (bootstrap, selftest, worker). Les 68 fichiers
suivis du projet initial sont presents dans Numerik's ; les 9 fichiers visuels/UI,
configuration et backend proteges sont identiques octet pour octet a la source.
Les 53 fichiers techniques partages sont identiques apres synchronisation.
Les EXE 2.6.0.0 et ZIP sont generes dans dist/ de chaque depot. Les EXE restent
non signes Authenticode. Ces tests ne remplacent pas une preparation sur PC neuf :
aucun logiciel, pilote ou parametre systeme du poste hote n'a ete modifie.

## Liens permanents herites

Google Sheet : https://docs.google.com/spreadsheets/d/1PtMhZC_7dQi7aw278XPQ1udmV9ol5hrD_G4mdSwXWA0/edit
Dashboard : https://script.google.com/macros/s/AKfycbwYe2r5-y8HeyfLjslbq7wI2BdFH0sj7TLJQSiUyeRdt_z7yytyTKsPQPPcT0HUcAci3g/exec?key=LDLC-Dashboard-2026-288d06206918450293ed29d54fefc801
