# Applications par defaut - LDLC et Numerik's 2.6.5

## Synchronisation et parcours Chrome - 2026-10-15

Regle actuelle, commune aux deux editions : Adobe pour .pdf, puis Chrome pour
.html et ENFIN le bouton de la ligne "Definir Google Chrome comme navigateur
par defaut". Aucun clic individuel sur .htm, http ou https. Ces quatre associations
restent lues, sans ecriture registre, pour confirmer le resultat global.
Si .html est deja correct mais pas les autres associations, seul le bouton global
est utilise. Si tout est deja correct, deux lectures stables suffisent sans clic.

Windows expose parfois le nom complet du bouton sous la forme "Definir Google
Chrome comme navigateur par defaut, Definir par defaut". Le moteur reconnait ce
nom combine FR/EN. Autre representation : recherche du bouton dans le groupe
du titre navigateur Chrome. Ne jamais utiliser le bouton PDF Chrome ni un
"Definir par defaut" quelconque d'une autre carte. Si la ligne n'est pas exposee,
echec explicite BrowserDefault, sans revenir aux clics .htm/http/https.

Les messages de la mini-UI suivent maintenant ouverture, selection, validation
du choix, puis confirmation du resultat, avec l'application et l'association.
Le worker numerote chaque signal (Revision). Le processus UI applique SetStatus,
peint le texte avec Update SANS activer la fenetre, puis accuse reception par
JSON atomique : WorkerId + Revision. Le worker attend cet acquittement borne
avant de poursuivre. Un vieux fichier "visible"/"minimized" n'autorise plus le
clic physique suivant. Sans acquittement courant, clic physique desactive et
avertissement explicite ; les patterns UIA et les verifications restent proteges.
La lecture du signal partage autorise ReadWrite/Delete pour ne pas verrouiller
le remplacement atomique. Un incident transitoire conserve le dernier affichage.

Les paliers restent 0, 50 et 100 selon les applications CONFIRMEES par Windows,
jamais selon les clics, tentatives ou secondes ecoulees. Aucun changement de
taille (380x205), couleurs, animation, backgrounds, accueil Numerik's ou fonds.
Seul le bloc compact du module UI protege est adapte dans chaque edition.

### Tests reels sur le PC de travail

Tests manuels autorises du 2026-10-15, avec Test-LDLCDefaultAppsLive et le vrai
module 70, sans preparation globale. Edge a ete mis temporairement par defaut
via les boutons Windows dedies PDF et navigateur, puis Parametres a ete ferme.
Pas de modification UserChoice/Hash, d'installation, de fond ou de telemetrie.
Worker sous le compte courant, sans elevation ; ne pas confondre ce diagnostic
cible avec une preparation complete du .exe sur un PC neuf.

- Numerik's 09:38-09:39 : depart Edge pour .pdf/http/https/.htm/.html ; selection
  Adobe + validation PDF ; selection Chrome pour .html + validation ; clic du
  bouton global navigateur Chrome ; cinq associations confirmees, succes a 100.
  Les 18 revisions UI ont ete acquittees, animation active pendant les traitements.
- LDLC 09:36 : .html deja Chrome, mais http/https/.htm encore Edge ; le bouton
  global qualifie a ete clique une fois et les cinq associations sont confirmees.
  Aucun clic .htm/http/https. Succes final, neuf revisions affichees/acquittees.
- LDLC, nouveau diagnostic apres ces tests : deja configure, aucun clic ni
  ouverture de Parametres, succes 100 apres confirmation des deux applications.
- Cas d'echec reel avant reconnaissance du nom combine du bouton : .html et PDF
  corrects, mais http/https/.htm encore Edge ; mini-UI a 50 avec erreur Chrome,
  jamais de faux 100. Le nom combine observe a ensuite ete corrige et reteste.
- Tests isoles : noms Reader/Acrobat, ordre .html puis bouton global, exclusion
  de la carte PDF Chrome, FR/EN, mauvais worker/ancienne revision ACK, selection
  puis validation signalees avant clic, animation pendant attente, barre stable,
  JSON transitoire, erreur/annulation et restauration de la fenetre principale.

Le diagnostic conserve result.json, default-apps-live.log et compact-ui.jsonl
dans son RuntimeRoot unique. Le dernier fichier contient les messages peints,
paliers, revisions, horodatages et compteurs de frames (pas de telemetrie envoyee).
Le PC est laisse avec Adobe Acrobat pour .pdf et Google Chrome pour le web.
Ces observations valident ce PC et ces versions Windows/applications : un autre
poste ou une autre version Windows peut exposer d'autres controles. Toujours
exiger la confirmation effective, jamais promettre un succes universel.

Release commune 2.6.5 / EXE 2.6.5.0. Synchroniser le coeur via l'allowlist, compiler
chaque edition avec ses ressources locales, lancer Test-LDLCRelease puis publier
les deux depots avec Sync-PreparationCore.ps1 -Publish. Les sections suivantes
documentent l'historique ; le parcours .html + bouton global ci-dessus fait foi.

## Mini-fenetre et validation Windows - 2026-10-14

Ordre reel du workflow : Adobe PDF, puis Chrome (http, https, .htm, .html).
Une association deja correcte reussit apres verification, sans manipulation.
Le worker transmet Progress/Message/Running/Success/ErrorApplication par JSON
atomique (File.Replace, backup NullString) au processus UI independant.
Paliers 0/50/100 : nombre d'applications effectivement confirmees. Aucun repli ni
temps d'attente ne fait progresser la barre. Le controle final relit les deux etats
deux fois ; seul leur succes autorise 100 et Configuration terminee.
En echec, progression = nombre de confirmations encore fiables * 50, nom de
l'application et associations manquantes, sans coche de succes. Le resultat
reste visible 1,4 seconde avant restauration de l'UI principale.

La mini-fenetre WinForms est dessinee en code dans le bloc compact du module 99
de CHAQUE edition (protege, adapte explicitement, jamais copie globalement).
Dimensions finales 380 x 205, bleu nuit, vrais coins arrondis, Preparation PC,
Applications par defaut, sous-titre Adobe/Chrome et consigne jaune. Aucune mention
Verification Windows ni compteur de temps. Timer C# 16 ms sur le processus UI,
cercle anime pendant le worker, transition de barre 420 ms entre paliers seulement.
Le cercle s'arrete sur le resultat : coche verte uniquement si succes integral.
La fenetre n'active pas le focus et reste en bas a gauche. Les autres blocs de
modules/99.UI.ps1 et les modules/45.Wallpaper.ps1 de chaque edition sont preserves.

Reference retrouvee avant introduction de la mini-fenetre : affa8b8^, module 70
au commit 90c1a7c. Ne pas restaurer ce module entier : il contiendrait d'anciens
controles de succes et des reprises que le moteur actuel corrige deja.

Cause REPRODUITE sur Windows : le selecteur OpenWith visible peut etre un HWND
enfant au premier plan (InputSiteWindowClass), absent de EnumWindows. Le dummy
HWND expose parfois zero descendant. On ajoute donc GetForegroundWindow aux
handles observes et explore EnumChildWindows, en gardant la racine la plus riche,
pas la barre de titre. Les noms Acrobat/Reader et les enfants Text restent geres.
Le dialogue est scope par son titre de choix ET l'extension demandee.

L'ancien comportement de clic est restaure uniquement sur les controles UIA
observes (pas de coordonnees fixes). SendInput/SetPhysicalCursorPos ciblent leur
rectangle courant apres controle natif du processus touche et comparaison UIA.
Pour OpenWith uniquement, FromPoint peut renvoyer la page Parametres derriere :
le repli exige alors que le processus touche soit exactement celui du controle
UIA ET du selecteur au premier plan. Une autre fenetre bloque le clic. La mini-UI
doit etre acquittee avant les clics physiques. Pas de frappe clavier globale,
pas de modification UserChoice/Hash ou SetUserFTA. Invoke/SelectionItem restent
disponibles sans clic si le signal compact n'est pas acquitte.
Les fiches d'applications pilotees sont fermees entre les etapes pour eviter un
ancien dialogue bloque. Aucun processus navigateur ou autre application n'est tue.

Le 2026-10-14 a 21:20, diagnostic reel depuis LDLC : clic .pdf -> Adobe Acrobat ->
Definir par defaut, puis .html -> Google Chrome -> Definir par defaut.
Verification effective : .pdf = Acrobat.Document.DC / Acrobat.exe ; HTTP, HTTPS,
.htm, .html = ChromeHTML / chrome.exe. Nouveau test a 21:21 : deja par defaut,
succes sans ouverture ni clic. Ce sont des tests de l'etape reelle, pas une
preparation complete : aucune installation, changement de fond ou telemetrie.
Les echecs avant ce correctif restaient a zero sans afficher de faux succes.
Test reel depuis Numerik's apres synchronisation : les cinq associations
effectives confirmees, aucun clic car deja correctes, mini-UI a 100 avec succes.
Les deux modules 70 ont la meme empreinte ; les suites release compilent et
verifient chaque edition avec ses propres ressources (pas de preparation globale).

Pour les coordonnees UIA physiques, voir la documentation Microsoft :
https://learn.microsoft.com/en-us/dotnet/framework/ui-automation/ui-automation-and-screen-scaling

Tests : Test-LDLCDefaultApps couvre maintenant le vrai scoping Pane et la ligne
parente, l'ordre Adobe/Chrome, les cas deja par defaut et les progres en echec.
Test-LDLCCompactUi montre une animation pendant l'attente d'un processus enfant,
barre stable dans le temps, easing, erreur/100 garde, JSON transitoire et restauration.
Test-LDLCDefaultAppsLive est un diagnostic MANUEL, non inclus dans Test-LDLCRelease :
il change uniquement les defauts PDF/navigateur du compte courant, sans installation,
fond, securite, taskbar ou telemetrie. Ne pas le lancer automatiquement en CI.

```powershell
$runtime = Join-Path $env:TEMP ('Preparation-DefaultApps-Live-' + [guid]::NewGuid().ToString('N'))
powershell -STA -NoProfile -ExecutionPolicy Bypass -File tools/Test-LDLCDefaultAppsLive.ps1 -RuntimeRoot $runtime
```

Lire result.json (etats Windows et etat mini-UI) et default-apps-live.log dans ce
runtime local. Un seul diagnostic a la fois ; reutiliser un ancien runtime est
refuse. Ajouter -Elevated pour reproduire les droits du .exe (UAC a valider
manuellement). Le diagnostic termine en erreur si les associations ne sont pas
confirmees. Ce diagnostic ne remplace pas la livraison compilee ; apres tout
correctif, Sync-PreparationCore.ps1 -Publish compile/teste/pousse les deux depots.
Version partagee et telemetrie 2.6.4, EXE 2.6.4.0, icones locales conservees.
Les connexions Google en bas de ce document restent permanentes et inchangees.

## Historique 2.6.3

Correctif commun du 2026-10-13. Source : modules/70.DefaultApps.ps1.
Ne pas modifier modules/99.UI.ps1, modules/45.Wallpaper.ps1 ni branding/ pour ce correctif.

## Cause

Le nom du choix PDF devait commencer par Adobe. Windows affiche parfois Acrobat
Reader sans ce prefixe : ce choix visible etait ignore. Les noms des fiches et de
RegisteredApplications avaient la meme restriction. Le repli calculait l'URI avec
un modulo : avec une seule fiche, trois tentatives reproduisaient la meme methode.
La confirmation pouvait aussi invoquer le meme bouton chaque seconde.

## Correction

- Un matcher commun normalise casse et espaces et accepte Acrobat Reader,
  Adobe Acrobat Reader, Adobe Acrobat, Adobe Reader, les suffixes DC et entre
  parentheses (ex. 64-bit). Les choix restent ancres pour ne pas cliquer sur une
  recherche Store, une aide ou un site contenant le nom Adobe.
- Un choix visible et actif est prioritaire sur un controle hors ecran.
- Un selecteur PDF deja ouvert montrant Acrobat est utilise sans rouvrir Parametres,
  meme si RegisteredApplications ne fournit aucune fiche.
- Si Acrobat est deja le defaut effectif, aucune navigation/selection n'est lancee.
- Les voies de repli sont les URI RegisteredApplications distinctes, chacune au
  plus une fois, dans la limite MaxAttempts (1 a 3). Une fiche inaccessible peut
  etre remplacee par une autre fiche enregistree. Aucun URI non documente ni outil
  de modification du hash UserChoice n'est ajoute.
- Si l'ouverture de l'association, le choix ou la confirmation echoue et que les
  associations restent inchangees apres stabilisation, arret sans rejouer la meme
  manipulation. Aucun faux succes base uniquement sur l'apparence du selecteur.
- Chaque bouton de confirmation (fenetre, identifiant UIA, libelle) est invoque au
  plus une fois ; maximum trois boutons distincts, pour les confirmations successives
  Windows. Attente de l'association effective jusqu'a 12 secondes.
- Deux lectures Windows successives doivent confirmer ProgID Acrobat/AcroExch.Document
  et executable Acrobat.exe/AcroRd32.exe. Chrome conserve ses quatre controles
  http, https, .htm et .html. Aucun succes sur simple libelle ou ProgID isole.
- L'avertissement contient nombre reel de tentatives, etape en echec, associations
  manquantes, ProgID/executable observes et raison d'arret. Le mode compact et
  l'annulation conservent leur restauration dans finally.

## Tests et limites

tools/Test-LDLCDefaultApps.ps1 execute les vraies boucles d'orchestration, selection
et confirmation avec des controles UIA et lectures Windows simules : les trois
noms demandes, Reader/Acrobat executables, deja par defaut sans action, choix visible
sans fiche enregistree, autre URI apres fiche inaccessible, doublons, selection
absente, confirmation sans effet (un seul clic), annulation, DPI et chargement lent.
Ces tests ne changent pas les associations du PC hote et n'envoient pas de telemetrie.
Ils ne remplacent pas un essai sur chaque version/build de Windows en production.
Test-LDLCRelease.ps1 complete ces regressions dans chaque edition et controle les
EXE/worker embarques. Les tests locaux Numerik's verifient encore l'accueil bloque
avant Continuer et les cinq JPG de boutique. Les personnalisations restent locales.

## Reprise depuis un autre PC

Recuperer origin/main des deux depots principaux, lire AGENTS.md et PASSATION_PROJET.md.
Modifier les modules/tests partages, puis utiliser tools/Sync-PreparationCore.ps1
-Publish pour synchroniser, compiler, tester, commiter et pousser les deux editions.
Ce document est lui-meme dans la liste commune sync/shared-files.json.
Version courante de reprise : sync/core-version.json et telemetrie 2.6.4 ; EXE 2.6.4.0.
Livraisons : dist/LDLCPreparationPC.exe et dist/Numerik'sPreparationPC.exe, avec
leur icone locale. Les interfaces, backgrounds et fonds Numerik's par boutique
ne sont ni copies ni remplaces. EXE non signes faute de certificat disponible.

## Connexions permanentes inchangees

- Sheet : https://docs.google.com/spreadsheets/d/1PtMhZC_7dQi7aw278XPQ1udmV9ol5hrD_G4mdSwXWA0/edit
- Dashboard : https://script.google.com/macros/s/AKfycbwYe2r5-y8HeyfLjslbq7wI2BdFH0sj7TLJQSiUyeRdt_z7yytyTKsPQPPcT0HUcAci3g/exec?key=LDLC-Dashboard-2026-288d06206918450293ed29d54fefc801
- Apps Script : https://script.google.com/home/projects/19Sn2qzKl3XwTV8Gxq1RLELhJcg5Uy-iXk_YglKJlggyduRai_xZL9WhP/edit

Aucun changement du serveur, du HTML, des liens ou des donnees permanentes pour ce correctif.
