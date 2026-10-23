# Bêta 2.6.17 — retrait explicite des alertes dans les quatre éditions

L'utilisateur a redemandé de retirer le message pour les quatre All in App.
Widgets devient informatif, y compris lecture/refus registre impossibles ; l'état
réel reste dans les diagnostics et aucune désactivation n'est inventée. L'alerte
réseau de l'écran de fin est remplacée par une confirmation d'enregistrement local
si le rapport est durablement sauvegardé. Le journal précis et la file de renvoi
restent actifs. Erreurs réelles, interruptions et sauvegarde impossible restent
signalées. Voir [beta/ALERTES_FIN_2026-10-23.md](beta/ALERTES_FIN_2026-10-23.md).
Sources LDLC/Numerik’s synchronisées ; bêta liée au nouveau source stable f36cd9e,
ses autres corrections restent préservées. Anciennes modifications UI locales
exclues des livraisons. Tests ciblés réussis : 41 assertions de contrôles finaux,
13 contrôles d'affichage, 14 scénarios / 100 contrôles de clôture dont erreur 1603
avec panne réseau. Validation Windows 39990326869 réussie ; EXE publié 82f6c47,
récupéré et hash vérifié. Quatre vrais Preview, contrat d’affichage 5.1/7, suite
complète. Les trois productions sont également publiées après vérification Windows.
Preuves : beta/evidence/completion-display-2026-10-23/windows-validation.json.

# Bêta 2.6.16 — Widgets retiré et réponse réseau non confirmée

Voir [beta/WIDGETS_TRANSMISSION_2026-10-23.md](beta/WIDGETS_TRANSMISSION_2026-10-23.md).
Un poste réel utilisait encore 2.6.8 : son rapport final est présent une seule fois,
0 erreur et seul Widgets en avertissement. L'ancien catch perd le détail de
l'exception et affiche « réseau ou serveur indisponible » par défaut : la photo
ne démontre donc pas une panne réseau. Aucun historique de dashboard modifié.
Reconnaissance en lecture seule de l'absence des composants Appx Widgets sur
Windows 11 ; échec de lecture inconnu, jamais assimilé à une désinstallation.
Transmission sans accusé renommée « non confirmée », sans faux succès ni perte
de la copie locale. Tests ciblés : 39 assertions de contrôles finaux, 14 cas / 42
assertions transport et 13 scénarios / 92 contrôles de clôture. Réponses HTTP,
installations et états Windows simulés ; aucune écriture dans le dashboard.
Validation Windows 39987078747 réussie : suite complète, 39 assertions des contrôles
finaux sous PowerShell 5.1 et 7, 14 cas / 42 assertions transport, 13 scénarios / 92
contrôles de clôture, quatre vrais Preview avec fermeture. EXE publié 0e421cd puis
récupéré ; SHA-256 conforme aux preuves Windows et au manifeste publié. Aucun
scénario simulé envoyé au dashboard. Les trois productions restent inchangées.

# Nouveaux tests des quatre éditions — 23 octobre 2026

Voir [beta/TESTS_QUATRE_APPLICATIONS_2026-10-23.md](beta/TESTS_QUATRE_APPLICATIONS_2026-10-23.md).
Quatre workflows Windows réussis, 16 vrais Preview, aucun échec inattendu ; neuf
rapports d'essai dashboard acquittés/validés ou bloqués selon scénario, puis nettoyés.
Les anciennes fausses alertes Chrome restent reproductibles dans les productions,
leur correction n'étant qu'en bêta. Aucun code de production ni ancien changement UI
modifié. Essais de régression Windows Server, pas des préparations Windows 11 complètes.

# Livraison bêta 2.6.15 — faux avertissements, 23 octobre 2026

Voir [beta/DEFAULT_WARNINGS_2026-10-23.md](beta/DEFAULT_WARNINGS_2026-10-23.md).
Contrôle final Chrome/Adobe/Widgets en lecture seule, variantes Adobe enregistrées
reconnues et stratégie Widgets prise en charge. Les vrais défauts restent bloquants.
Publication exclusivement bêta, productions/UI et données du dashboard préservées.
Validation Windows 39947432903 réussie : 49 suites PowerShell, 3 JavaScript,
comparaison historique/correction, API natives 5.1 et 7, quatre lancements Preview.
EXE publié 040db21 puis récupéré : SHA256 conforme. Aucun POST simulé au dashboard.
Le premier essai échouait dans une fixture de clôture incomplète, corrigée et retestée.
Ne pas confondre une inscription Adobe simulée avec sa sélection réelle : le
runner n'a pas Reader, son PDF reste Edge ; le PC utilisateur est inaccessible ici.

# Livraison 2.6.14 — promotion bêta publiée, 22 octobre 2026

Voir [PROMOTION_BETA_2026-10-22.md](PROMOTION_BETA_2026-10-22.md) et ses preuves.
Les fonctions carte mère/Bureau et correction des fausses épingles Edge sont
publiées dans LDLC, Numerik’s et ADDON ; la bêta reste synchronisée. Installation
constructeur manuelle, portables exclus ; ADDON conserve NVIDIA/Trackman et son
identité. AMD officiel/Chocolatey courant et Chrome historique livrés selon édition.
Quatre vrais lancements EXE et trois échanges dashboard acquittés par édition ;
empreintes des EXE récupérés identiques aux tests. L’incident intermittent de
transport Numerik’s au premier essai et les tests corrigés restent documentés.
Les modifications UI locales non publiées restent intactes. Les notes candidates
et restrictions bêta ci-dessous sont historiques et remplacées pour cette livraison.

# Candidate bêta 2.6.13 — AMD et Chrome historique, 22 octobre 2026

Publication autorisée sur les trois productions pour AMD (hors ADDON NVIDIA) et
retour au layout Chrome historique. Bêta synchronisée ; ses tests et sa carte mère
restent préservés. Voir AMD_CHROME_TASKBAR_2026-10-22.md après synchronisation.
Validation Windows, quatre ouvertures et dashboard en cours.

# Livraison AMD — bêta 2.6.12, 21 octobre 2026

Voir beta/AMD_CHOCO_FALLBACK_2026-10-21.md : repli Chocolatey après échec officiel,
version actuelle/URL/SHA256 liés au package AMD signé et compatible. Aucun retour
à un ancien pilote, aucun second installateur actif, portables exclus. 29 scénarios
natifs, suite complète, quatre lancements du vrai EXE et dashboard réussis. EXE
publié puis récupéré, hash vérifié. Chocolatey propose maintenant 26.10.1,
avec la même URL et le même SHA256 que le package AMD signé téléchargé. Installation matérielle simulée ; essai sur PC AMD à faire.
Publication bêta seulement ; productions et leurs changements UI locaux préservés.
Les notes ci-dessous retracent les livraisons précédentes.

# Livraison AMD — bêta 2.6.11, 20 octobre 2026

Voir beta/AMD_UPDATE_2026-10-20.md : package complet officiel 26.10.1 réellement
téléchargé/signé et versions INF vérifiées. Correction du faux succès sur un ancien
Adrenalin/pilote. Suite Windows complète, comparaison avant/après, quatre lancements
EXE et trois échanges dashboard réussis ; EXE publié et empreinte récupérée vérifiée.
Installation matérielle simulée sur la VM ; vérification sur le GPU client à faire.
Publication exclusivement bêta ; portables exclus, carte mère et UI préservées.
Chocolatey reste en 26.8.1 ; Guru3D renvoie 403, aucun faux repli annoncé.
Les notes ci-dessous retracent les livraisons précédentes.

# Livraison vérifiée et dashboard — 20 octobre 2026

Transmission durcie publiée dans les quatre dépôts avec leurs EXE testés sous
Windows : quatre vrais lancements Preview et trois échanges dashboard par édition.
Voir TRANSMISSION_2026-10-20.md et ses preuves. Dashboard permanent en version 47 :
thème éclairci et titres Outfit ; voir DASHBOARD_STYLE_2026-10-20.md.
Les anciennes modifications UI locales restent exclues ; carte mère en bêta seule.
Les notes suivantes retracent les états antérieurs.

# Etat final du 20 octobre 2026

Lire beta/CORRECTIONS_2026-10-20.md : beta 2.6.9 livree, productions Chrome/McAfee
publiees avec quatre lancements par edition, dashboard Google publie en version 46.
Les clients de transmission durcis passent aussi les tests natifs/les trois vrais
echanges dans chaque edition mais restent non publies en production, conformement
a /workspace/AGENTS.md. Patchs et preuves regroupes dans beta/patches/transmission
et beta/evidence/corrections-2026-10-20. Les autres checkouts gardent ces modifications
locales et les anciens changements UI non publies ; ne pas les ecraser ni les pousser
par inadvertance. L'integration carte mere reste exclusivement beta.

# Passation 2.6.9 beta — corrections validees sous Windows

Voir beta/CORRECTIONS_2026-10-20.md et ses preuves natives : compilation, suite
release, comparaison avant/apres, quatre vrais lancements et trois echanges
dashboard acquittes. La transmission corrigee des productions reste non publiee.

# Passation LDLC PrepTool 2.6.8 beta

## McAfee : retour au traitement historique - 2026-10-20

Sur demande utilisateur, McAfee sort du nouveau parcours interactif et de son
attente illimitee. La beta reutilise le nettoyage historique dans un worker
separe, avec sa limite globale de 90 secondes et ses avertissements/retours
precedents. Le filtre McAfee est transmis au worker pour ne pas traiter Norton
avec cet ancien nettoyage. Les neuf fonctions historiques de detection,
commandes, verifications et repli MCPR restent identiques a la reference
`3aec296b7468e7634815eccec5d549fc90689c9f` (dernier etat disponible avant les
changements d'octobre ; pas de commit exactement trois semaines auparavant).

Norton conserve son parcours actuel. Chrome, l'exclusion AMD des portables,
l'interface et l'integration carte mere beta ne changent pas. Publication de ce
retour arriere uniquement dans LDLC-Preparation-PC-test-app, version 2.6.8.
Le test compare le nettoyage a cette reference et simule retrait, produit
restant, absence de resultat, delai et Quitter. Le test Windows lance aussi
un vrai enfant PowerShell inoffensif ; aucun vrai McAfee n'est installe ou retire.
Resultats et limite de validation : `beta/MCAFEE_ROLLBACK_2026-10-20.md`.

## Bouton navigateur Chrome par defaut - 2026-10-16

Le bouton global de la ligne Chrome avait un libelle combine trop strict et
dependait d'un titre Chrome distinct. Les variantes francaises/anglaises, noms
combines dans les deux ordres et texte enfant d'un Button non nomme sont reconnus.
La ligne navigateur identifie aussi la fiche ; le bouton reste lie a cette ligne,
jamais a un bouton generique PDF/Edge. Un choix ambigu n'est pas clique.

BrowserDefault conserve maintenant son type d'action jusqu'a l'activation :
InvokePattern est tente avant le clic physique observe. En cas d'indisponibilite
ou d'erreur UIA, les controles de cible du clic observe restent appliques. La
recherche peut remonter la fiche trois fois au maximum et reacquiert le bouton.
Les parcours .html/Adobe restent identiques. Seules les associations effectives
HTTP/HTTPS/.htm/.html peuvent confirmer Chrome, pas le simple retour du clic.

Test-ChromeBrowserDefaultButton : 43 controles portables de selection/activation,
defilement, erreurs, annulation et absence de faux succes. Suite DefaultApps
rendue portable pour ses fixtures de chemins, sans changer les assertions ;
ses arbres UIAutomation natifs restent reserves a Windows. Syntaxe, hardening,
ordre du workflow et premier affichage passent. Scripts/ressource EXE, sommes
SHA-256 et ZIP actualises par la methode Linux documentee ci-dessous ; lanceur,
icone et manifeste conserves. Le clic sur un vrai poste Windows reste a valider.

## Retour au parcours Norton/McAfee precedent - 2026-10-16

Suite au retour utilisateur sur PC neuf (Applications installees ouvertes et
preparation bloquee a 1 %), annulation du commit 265466b. Sources, tests et
livraisons retrouvent exactement l'etat 50af771, hors cette note de passation.
La barriere Wait-LDLCSecurityRemoval, sa lecture SecurityCenter stricte, son
repli ms-settings:appsfeatures et son placement de fenetres sont retires.
Le workflow reprend son ancien nettoyage isole Norton/McAfee avec limite de
90 secondes, commandes de desinstallation et outils editeurs historiques.
L'ouverture de leurs interfaces reste celle de ces outils ; aucune nouvelle
attente illimitee ajoutee. Les optimisations de demarrage et le parcours AMD
du parent sont conserves.

Restauration de l'EXE deja genere de cette version, sans reecriture du lanceur.
Empreintes et ressources embarquees verifiees ; syntaxe, ordre du workflow,
hardening, bootstrap de securite et deux suites de premier affichage passent.
La desinstallation et l'affichage natif ne peuvent pas etre exerces sous Linux.

## AMD : controle de la recherche de version actuelle - 2026-10-15

Perimetre LDLC et Numerik's uniquement ; ADDON explicitement exclu a la demande
utilisateur (usage NVIDIA). Le parcours AMD existant recherche et telecharge deja
l'Auto-Detect officiel a CHAQUE preparation, meme si Adrenalin et le pilote sont
presents. Pas de version/package fige ni de repli vers un vieux cache hors ligne.
Auto-Detect choisit le pilote compatible avec la ou les Radeon presentes.

Recherche et telechargement demandent maintenant Cache-Control/Pragma no-cache.
Les noms de bootstrap AMD a deux, trois ou quatre composantes de version sont
acceptes et compares. La detection d'Adrenalin ne valide plus une installation
PRO/Enterprise par son seul executable homonyme. Une entree Adrenalin avec son
executable reste reconnue meme en presence d'une ancienne entree PRO.

Verifications apres installation conservees : fin des sous-processus AMD,
executable Adrenalin present, pilote DISPLAY AMD signe et peripherique sain pour
CHAQUE Radeon. Erreur ou redemarrage necessaire explicitement signales ; aucun
succes deduit d'un seul code retour ou d'une ancienne installation. Ni confusion
avec un processeur/chipset AMD, ni exclusion des iGPU Radeon ou des PC AMD/NVIDIA.

Tests passes dans chaque depot : 15 scenarios de detection, 103 assertions de
flux AMD isole, 14 controles logiciels Adrenalin et validation GPU/NVIDIA existante.
Les tests couvrent nouvelle version publiee entre deux executions, installation
existante, panne reseau, EXE invalide, mauvaise signature, GPU absent/deconnecte,
pilote absent/non signe et attente des sous-processus. Nettoyage des fixtures de
tests rendu portable sans modifier leurs assertions Windows.

Scripts, ressource de l'EXE 2.6.5.0, SHA256SUMS et ZIP actualises selon la methode
Linux documentee ci-dessous. Lanceur, ressources Windows, images et fonctions
NVIDIA compares et conserves. Test reel telechargement/installation non execute :
le proxy cloud refuse www.amd.com (CONNECT 403) et le poste est Linux sans GPU AMD.
Acces live requis vers www.amd.com, drivers.amd.com et download.amd.com ; lancer
Test-LDLCGpuAmdFlow.ps1 et Test-LDLCAmdSoftwareDetection.ps1 puis valider sur un
poste Windows AMD connecte avant de revendiquer la derniere version installee.

## Demarrage : diagnostic et extraction differes - 2026-10-15

Le lancement normal affiche la fenetre avant le diagnostic des antivirus et
l'extraction du worker. Le diagnostic est conserve dans le processus worker ;
les erreurs d'image/extraction continuent d'afficher leur diagnostic. Tous les
SHA-256, reparations de cache, modes workers et BootstrapTest/SelfTest sont
conserves. Aucun changement du workflow ni des installations.
Test-BootstrapFirstPaint.ps1 ajoute a la release : 26 controles portables,
extraction reelle et cache corrompu compris. Tests syntaxe, bootstrap de securite
et callbacks premier affichage passent. Scripts/ressource de l'EXE, SHA256SUMS
et ZIP actualises par le meme procede Linux documente ci-dessous. Le temps de
lancement reel et les diagnostics natifs restent a valider sous Windows.

## Affichage initial accelere, fonctionnement conserve - 2026-10-15

La fenetre principale finit sa premiere peinture avant le lancement du worker.
Un timer ponctuel evite les doubles lancements et ne lance rien en apercu ou si
Quitter a deja ete demande. Le suivi, la mini-interface et l'arret propre restent
identiques. Les trois compilations des API du bureau/fond sont effectuees a leur
premier usage, dans les fonctions existantes, au lieu de retarder la fenetre.
Les boucles de pixels du fond passent dans un helper C# en memoire : memes seuils,
couleurs, segments alpha, masque arrondi, dimensions et images. Aucune modification
du workflow, des applications installees, de Chrome/Adobe ni du choix des boutiques.

Tests ajoutes : tools/Test-UiFirstPaint.ps1, Test-UiLazyInterop.ps1 et
Test-UiPixelBuffer.ps1 ; ils sont inclus dans la suite release. Sous Linux,
callbacks reels testes avec doubles inoffensifs, calculs compares aux anciennes
boucles et scripts verifies. Les wrappers GDI/WinForms et le temps reel entre clic
et affichage restent a verifier sous Windows ; aucune mesure Windows revendiquee.

Scripts et EXE 2.6.5.0 actualises, SHA256SUMS et ZIP regeneres. Faute de compilateur
Windows dans le cloud, seule la ressource PowerShell du lanceur existant est
reecrite : identite, instructions, exceptions, icone, manifeste et autres ressources
verifies identiques. La commande Sync-PreparationCore.ps1 -Publish exige Windows
et main ; controle equivalent des fichiers partages et de leurs SHA-256 effectue
ici sans contourner ses controles. Seuls les fichiers autorises sont communs ;
les fichiers UI/fond proteges sont adaptes localement. Compilation et suite release
Windows completes restent a executer.

## Applications par defaut synchronisees - 2026-10-15

Lire APPLICATIONS_PAR_DEFAUT.md, section 2.6.5 : Adobe .pdf puis Chrome .html,
ensuite le bouton de la ligne navigateur par defaut. Aucun clic individuel sur
.htm/http/https ; lecture des quatre associations pour confirmer Chrome.
Nom UIA combine du bouton FR/EN reconnu, carte PDF Chrome explicitement exclue.
Mini-UI 380x205 : texte de chaque action peint et acquitte (worker + revision)
avant le clic, paliers reels 0/50/100. Ancien ACK perime refuse, lecture partagee
sans verrouillage du signal. Cas reels succes, deja configure et echec sans
faux 100 verifies ; pas de preparation complete. Release commune 2.6.5.0,
compilation et tests des deux editions, sans ecraser les interfaces principales,
backgrounds, boutiques, logos, icones, fonds Windows ni connexions Google.

## Applications par defaut et mini-UI - 2026-10-14

Lire APPLICATIONS_PAR_DEFAUT.md : cause reproduite, reference 90c1a7c avant
mini-fenetre, handle OpenWith au premier plan + enfants natifs, clic sur le
controle observe puis Definir par defaut et verification effective Windows.
Test reel reussi : .pdf Adobe Acrobat, HTTP/HTTPS/.htm/.html Google Chrome.
Test deja configure reussi sans ouverture ni clic ; echecs testes sans faux 100.
Mini-UI 380x205, animation independante, Adobe puis Chrome, paliers reels 0/50/100.
Version commune 2.6.4, dist/LDLCPreparationPC.exe 2.6.4.0, icone LDLC conservee.
UI principale, fonds, profil edition et liens Google inchanges. Tests release
isoles et lancement de l'etape seule : aucune preparation complete sur ce PC.
Synchronisation technique via Sync-PreparationCore.ps1 -Publish ; seule la zone
compacte du module UI protege est adaptee explicitement dans chaque edition.
Anciennes versions ci-dessous = historique, pas consignes de version courante.

## Correctif applications par defaut - 2026-10-13

Lire APPLICATIONS_PAR_DEFAUT.md. Le module 70 commun accepte Acrobat Reader sans
prefixe Adobe, reutilise le selecteur visible, confirme l'association effective
et evite les reprises identiques sans progres. Version commune 2.6.3, EXE 2.6.3.0.
Tests UIA/association simules, puis suites release des deux editions ; aucun changement
des defauts du PC hote. UI, fonds, icones et connexions Google inchanges.
Les versions indiquees dans les sections ci-dessous sont des etats historiques.

## Accueil propre a Numerik's - 2026-10-13

Le contrat optionnel PreparationEdition.Startup.BeforeStart est partage dans le lanceur
et appele avant lecture/execution PowerShell. Seule Numerik's fournit ce point et son
logo depuis branding/startup, protege contre la synchronisation. LDLC n'affiche aucun
accueil boutiques et conserve integralement sa propre UI, ses fonds, son icone et son
workflow. La compilation locale garde cette separation ; Test-PreparationStartup
verifie l'absence de l'accueil dans l'EXE LDLC. Release commune : 2.6.2.0.

## Mise a jour dashboard et identite des editions - 2026-10-13

Lire [DASHBOARD_PREPARATION_PC.md](DASHBOARD_PREPARATION_PC.md) pour la passation
complete : theme ardoise mat sans neon, titre Dashboard Preparation PC, colonne
All In App LDLC/Numerik's, compatibilite des anciens formats et liens permanents.
Release courante : 2.6.2.0. UI et fonds Windows des logiciels inchanges.

## Livraison par edition : 2026-10-13

Les builds/tests communs utilisent tools/PreparationDelivery.Common.ps1. Le champ
DeliveryBaseName de sync/edition.json choisit uniquement les noms distribues.
LDLC conserve LDLCPreparationPC (valeur par defaut), son icone et tous ses visuels.
Numerik's utilise Numerik'sPreparationPC dans son profil local protege. Ne pas
copier ce profil dans LDLC ni renommer globalement les identifiants internes du moteur.
Le nom du ZIP, les fichiers .exe/.exe.config/.ps1/.worker.embed.ps1 et les chemins
de publication sont calcules pour chaque edition. Aucun lien Google n'est change.

## Ajout du 2026-10-13 : seconde edition Numerik's

Lire SYNCHRONISATION.md avant toute modification technique commune. Numerik's
est une duplication complete du commit affa8b8 avec les outils de synchronisation.
sync/shared-files.json declare le coeur partage ; sync/state.json est la base
commune ; sync/core-version.json pilote la version technique des deux builds.
sync/edition.json, UI, fonds, assets, configuration de suivi et dashboard sont locaux.
Utiliser Sync-PreparationCore.ps1 -Publish pour compiler/tester/pousser les deux.
Ne jamais copier une UI/fond entre editions apres personnalisation. Les correctifs
techniques dans ces fichiers proteges doivent etre adaptes explicitement des deux cotes.
Les liens Google existants restent inchanges ; aucun accueil Numerik's n'est ajoute.

Etat de reference : 2026-10-04. Lire ce document avant toute reprise depuis un autre PC.
Depot principal : https://github.com/holyonefr/LDLC-Preparation ; branche main.
Toujours git fetch puis repartir de origin/main dans le checkout principal.
Ne pas utiliser un ancien dossier Desktop comme source et ne pas modifier le depot ADDON.

## Sources et livraison

- modules/ : source PowerShell canonique, ordre dans modules/build-order.txt.
- tools/google-apps-script/LDLC_ErrorTelemetry.gs : source canonique du serveur ET du HTML.
- dist/LDLCPreparationPC.ps1 et dist/LDLCPreparationPC.worker.embed.ps1 : generes, ne pas modifier directement.
- dist/LDLCPreparationPC.exe : lanceur .NET Framework, version 2.6.1.0.
- logo-ldlc-com.ico : icone conservee a la compilation.
- dist/SHA256SUMS.txt : empreinte de l'EXE.
- dist/LDLCPreparationPC-2.6.1.0.zip : livraison generee, ignoree par Git ; EXE, configuration et empreinte.
- L'EXE embarque script principal, worker et images ; aucune archive compagnon de diagnostic requise.
- L'EXE est non signe Authenticode : aucun certificat de signature LDLC disponible ici.

## Cause des executions bloquees et correction

Le lancement Windows Update mettait temporairement LDLC_TELEMETRY_DISABLED=1 dans
le worker PRINCIPAL. Write-ProgressFile appelait alors la telemetrie, qui memorisait
Disabled=true. Restaurer ensuite l'environnement ne restaurait pas ce flag :
la finalisation n'etait plus envoyee.

modules/80.WindowsUpdate.ps1 ne modifie plus ce flag parent.
modules/95.WorkerLauncher.ps1 le desactive uniquement dans les workers auxiliaires
Windows Update, nettoyage securite et diagnostics. Ces workers ne sont pas des preparations.

Le test Test-LDLCTelemetryLifecycle.ps1 a reproduit le defaut original et confirme
la correction sous Windows PowerShell 5.1, avec utilisateur vide et RunId stable.
La progression Nullable[int] a aussi ete corrigee (boxing PowerShell, pas de .HasValue).

Les deux lignes DESKTOP-948Q4AF du 24 septembre ont des RunId DIFFERENTS :
elles ne peuvent pas etre fusionnees sur le seul PC ou une coincidence de dates.
Un ancien debut rejoue depuis la file hors ligne peut arriver en meme temps qu'un nouveau debut.
Une duree non nulle ne prouve pas une finalisation. Aucun running historique n'est
converti artificiellement en success. Les anciens EXE gardent leur ancien code :
installer la nouvelle version pour corriger le defaut client. Le serveur accepte
toujours leurs rapports correctement finalises, mais ne peut inventer une fin jamais envoyee.

## Contrat de suivi permanent

1. Le worker principal genere un RunId au demarrage et le conserve jusqu'au finally.
2. Un premier POST enregistre running ; les mises a jour suivantes retrouvent ce RunId.
3. Mode distant live par defaut : une tentative au maximum toutes les 60 secondes.
4. Le finally construit IsFinal, FinishedAt, statut reel et duree Stopwatch monotone.
5. Avant chaque POST, le payload est sauvegarde dans telemetry-outbox sous le runtime.
6. Un fichier par RunId, ecriture temporaire puis remplacement atomique ; pas de limite arbitraire de 100 runs.
7. HTTP 200 seul ne suffit pas : Apps Script doit renvoyer ok=true.
8. Seule la version exacte acquittee est effacee. Une fin prime sur un demarrage rejoue.
9. Les anciens LDLC_ERROR_TELEMETRY_QUEUE.json restent lus ; renvoi au prochain envoi disponible.
10. Apps Script travaille sous ScriptLock et upsert par RunId ; Sequence est optionnel.
11. Les mises a jour hors ordre ne peuvent ramener une execution finalisee a running.
12. Le dashboard lit le meme Sheet et recharge automatiquement environ toutes les 60 secondes.

Runtime : %ProgramData%\LDLCPreparationPC, puis dossier accessible de repli.
Un compte Google interactif n'est pas necessaire ; UserName peut etre vide.
L'envoi necessite reseau/HTTPS et le droit d'ecrire dans le runtime. Hors ligne,
les rapports sont conserves et rejoues au prochain lancement/envoi.
Un kill brutal avant la construction de la fin reste une execution non confirmee.

Donnees : RunId, dates, PC/serie, utilisateur optionnel, version, source applicative,
statut, compteurs, erreurs detaillees, etape, progression et duree.
DetailsAvertissements et Sequence sont AJOUTES, sans rendre les anciens champs obligatoires.
Les erreurs error/critical alimentent Erreurs. Les warnings restent attaches a l'execution.

## Serveur, historique et compatibilite

Secrets et URL deja configures : telemetry.config.json et modules/05.Telemetry.ps1 ;
ne pas changer leurs valeurs permanentes. Deployment actuel : version Apps Script 42.

Formats acceptes : apiKey/ingestSecret/secret/key ; payloads/reports/items ;
Run/Execution/ResultatExecution ou corps direct ; Events/Errors/Erreurs/Incidents ;
alias anglais/francais/camelCase/snake_case. Version absente : legacy.
Ne jamais supprimer les alias historiques ou imposer un nouveau champ.

RunId est la cle. Sans identifiant, seul un debut ISO precis et immutable + machine
permet une cle historique deterministe. Sinon conserver des executions distinctes.
Ne jamais dedupliquer seulement par PC. Les erreurs rejouees utilisent la cle
RunId + Etape + TypeErreur + Gravite + Message, pas l'heure de reception.

La colonne EtapesTerminees est conservee pour compatibilite/debug, automatiquement
masquee dans Executions, et ne participe pas aux statistiques.
Les colonnes version/identifiants sont formatees texte avant ecriture ; les compteurs
et durees sont numeriques. Les anciennes versions deja converties en dates par Sheets
ne sont pas reconstituees par supposition.

Les actions auditruns et deduplicateruns demandent secret ingestion ET cle admin.
La deduplication demande aussi DEDUPLICATE_SAME_RUN_ID, sauvegarde avant intervention
et ne retire que les doubles lignes portant exactement le meme RunId.
Ne jamais lancer Reset-LDLCTelemetrySheet.ps1 pour une mise a jour normale.

## Statuts et design

Une regle commune serveur/client determine lignes, cartes et graphiques :
running reste en cours, success vert, warning orange, error rouge,
stopped et timeout distincts. Un heartbeat ancien signale une absence de nouvelle,
sans affirmer une reussite. Les executions interrompues ne comptent pas comme reussites.
Le taux de reussite reste reussites/(reussites+echecs), hors running et interruptions.

Conserver le theme bleu LDLC, l'arriere-plan technologique et le titre centre agrandi :
68px desktop, 48px tablette, 34px mobile.
PC et ADDON partagent le serveur, mais jamais leurs compteurs : ApplicationSource
LDLC_PREPARATION_PC / LDLC_PREPARATION_ADDON, menu Preparation PC par defaut.
Source du serveur partage : uniquement ce depot principal.

## Suppression du composant de diagnostic

LDLC Validator a ete retire completement du runtime et de la livraison.
Supprimes : assets/LDLC Validator.zip, dist/LDLC Validator.zip,
tools/Test-LDLCValidatorDownload.ps1.
Retires : bootstrap/ressources specifiques, fonctions Bureau de telechargement/copie,
verification/cleanup/raccourci specifique, etape du workflow et regles LFS des archives.
Les anciennes erreurs du Sheet restent de l'historique ; aucune nouvelle verification
ne doit produire une erreur liee a ce composant. Ne pas supprimer les fichiers du client
hors depot ni lancer une desinstallation non demandee.

Conserves : fonctions partagees de hashes, ecriture atomique, assets UI, worker,
raccourcis des applications, nettoyage UserDiag et outils de ressources .NET.
Les anciens dossiers worker-modules et source-brute, ainsi que les index generes
inutiles, avaient deja ete retires lors du nettoyage initial.

## GPU AMD et NVIDIA

modules/60.Gpu.ps1 lit les adaptateurs graphiques presents, CIM puis WMI en repli.
PCI VEN_1002 = AMD, VEN_10DE = NVIDIA, VEN_8086 = Intel. CPU AMD seul et
constructeur SUBSYS ne declenchent pas Adrenalin. Un GPU deconnecte est exclu.
Un PC avec iGPU AMD + NVIDIA traite chacun sans remplacer la logique NVIDIA.

AMD lit https://www.amd.com/en/support/download/drivers.html et selectionne
le lien Adrenalin Auto-Detect minimalsetup ACTUEL sur drivers.amd.com/download.amd.com.
Aucun numero de release n'est fige. Pas de cache perime utilise pour promettre une version actuelle.
L'outil AMD choisit le pilote compatible ; la derniere release Recommended/Optional
depend du materiel et des choix exposes par AMD, surtout sur OEM/anciens GPU.

Verifier taille minimale, MZ/PE, Authenticode Valid et CN AMD exact (avec ou sans Inc).
Lancer -install, suivre le processus et ses descendants, y compris setup AMD demarre
par service, puis attendre une periode sans processus. Timeout : aucune reussite declaree.
Verifier chaque PNPDeviceID AMD : adaptateur sain, pilote DISPLAY signe AMD,
INF oem, version valide, et executable de l'application Adrenalin.
Un code exigeant redemarrage sans pilote encore confirme donne un warning precis.
L'annulation remonte au workflow pour finaliser stopped. Aucun reboot automatique.

Telechargement reel du 2026-10-04 : outil officiel 26.8.1, 47 822 008 octets,
signature Valid, CN Advanced Micro Devices, accepte par le validateur.
Installation AMD complete sur materiel Radeon NON testee ici ; les scenarios
d'installation/processus/pilote sont simules. Ne pas promettre qu'un ancien pilote
a ete mis a jour sur un GPU physique sur la seule base de ces tests.

NVIDIA conserve detection professionnelle, source officielle prioritaire,
comparaison Game Ready et NVIDIA App. Chocolatey n'est utilise comme repli existant
que s'il est deja installe ; ne pas l'installer automatiquement.

Sources primaires :
https://www.amd.com/en/resources/support-articles/faqs/GPU-131.html
https://www.amd.com/en/resources/support-articles/faqs/RSX2-INSTALL.html

## Chrome, Adobe et interface compacte

modules/70.DefaultApps.ps1 lit les associations EFFECTIVES Windows :
QueryCurrentDefault AL_EFFECTIVE, puis AssocQueryString executable et ProgID stable.
Chrome : HTTP, HTTPS, .htm, .html vers ChromeHTML et chrome.exe.
PDF : .pdf vers Acrobat/AcroExch.Document et Acrobat.exe/AcroRd32.exe.
Ne pas considerer un simple clic ou une valeur registre isolee comme un succes.

URI ms-settings par application enregistree, UI Automation semantique,
patterns Invoke/Selection/ScrollItem/Scroll ; aucun clic par coordonnees fixes.
Attendre le vrai chargement, gerer le focus et retenter au maximum trois fois.
Deux lectures effectives consecutives confirment le resultat.
Les tentatives recuperees sont informatives ; seul l'echec final produit un warning precis.
Le bilan global relit Chrome ET PDF apres les deux etapes.

Le worker signale le mode compact dans LDLC_DEFAULT_APPS.<PID>.json et attend l'ACK UI.
modules/99.UI.ps1 minimise la grande fenetre et montre une petite fenetre bleu LDLC,
sans activation, double buffer, textes visibles, sans compteur/animation.
Le mode couvre Chrome ET Adobe ; finally et sortie worker restaurent l'etat precedent.
Le timer UI limite les repeints aux changements utiles pour eviter les saccades.

Lecture reelle sur ce PC : Chrome confirme pour HTTP/HTTPS/.htm/.html ;
.pdf est actuellement ChromePDF et n'est donc PAS faussement considere Adobe.
Ce controle en lecture seule ne change pas les choix utilisateur du PC de developpement.
Tests de 100/125/150% et resolutions : selection semantique simulee,
pas essais physiques sur chaque modele de portable.
Mini-fenetre WinForms affichee/rendue et restauration testees reellement.

Sources :
https://learn.microsoft.com/en-us/windows/apps/develop/launch/launch-default-apps-settings
https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nf-shobjidl_core-iapplicationassociationregistration-querycurrentdefault

## Verification et publication

Depuis Windows PowerShell 5.1 :
powershell -NoProfile -ExecutionPolicy Bypass -File tools/Build-LDLCPreparationPCExe.ps1
powershell -STA -NoProfile -ExecutionPolicy Bypass -File tools/Test-LDLCRelease.ps1

19 tests PowerShell, 2 suites JS et diagnostics du lanceur compile passent.
SHA-256 EXE : 31B41C2ED2F19111A3FD65285C1F1051B5D6D7222FB6667F2E3DB9B6AC35B396.
Le lanceur compile est execute via son EntryPoint dans un processus de test isole
pour BootstrapTest, SelfTest et WorkerSmokeTest. Aucune preparation du PC hote lancee.
Le test couvre le stockage de 150 runs offline, acquittement refuse, fin protegee,
les GPU mixtes et 79 assertions AMD, la syntaxe et le ZIP sans composant retire.

Publier Apps Script : tools/Deploy-LDLCDashboard.ps1, compte clasp deja autorise,
nouvelle VERSION sur le MEME deployment ID, executer comme proprietaire, acces public
a l'ingestion protegee par secret. Ne pas creer de nouvel endpoint.
Test live : tools/Test-LDLCTelemetryLive.ps1 cree des rapports CODEX-TEST,
verifie le Sheet et le JSON dashboard, puis supprime uniquement ses propres RunId.
-DeduplicateExisting sert uniquement a une maintenance explicitement demandee.

Controle live du 2026-10-04 confirme en version Apps Script 42 : 1086 lignes
existantes, aucun doublon exact RunId, aucune ligne historique supprimee.
Six rapports simules : success, warning, error (deux erreurs), stopped, timeout,
et rapport 2.5.2 sans nouveaux champs. Demarrages puis fins et replays restent
une ligne par RunId, meme avec UserName vide. Versions stockees en texte.
Les six rapports de test et leurs erreurs ont ete retires, nettoyage confirme.
Dans le navigateur, badges reels : reussite rgb(156,255,36), warning
rgb(255,148,31), echec rgb(255,49,59). Le titre et le theme sont conserves.
La connexion interactive Sheets du navigateur de test n'est pas disponible ;
valeurs, onglet permanent et colonne masquee verifies via le serveur autorise.

Apres toute modification : mettre a jour ce MD, reconstruire les deux scripts,
compiler EXE, tests pertinents, git diff --check, commit et push origin main.
Ne pas annoncer un push/deploiement/test reel avant confirmation.

## Liens permanents

Google Sheet : https://docs.google.com/spreadsheets/d/1PtMhZC_7dQi7aw278XPQ1udmV9ol5hrD_G4mdSwXWA0/edit
Onglet Executions : gid=1844459424.
Dashboard HTML : https://script.google.com/macros/s/AKfycbwYe2r5-y8HeyfLjslbq7wI2BdFH0sj7TLJQSiUyeRdt_z7yytyTKsPQPPcT0HUcAci3g/exec?key=LDLC-Dashboard-2026-288d06206918450293ed29d54fefc801
Projet Apps Script : https://script.google.com/home/projects/19Sn2qzKl3XwTV8Gxq1RLELhJcg5Uy-iXk_YglKJlggyduRai_xZL9WhP/edit

## Validation finale et fermeture — 2026-10-16

Lire VALIDATION_FINALE.md. Le workflow confirme explicitement sa fin après les opérations système ; le rapport final est sauvegardé avant son POST. Quitter reconnaît cet état par processus/heure de démarrage et laisse l’envoi finir, sans tuer le worker après 8 s. Les erreurs, délais dépassés, avertissements non résolus et interruptions bloquent la validation et gardent leur cause. Le backend ne compte plus les avertissements comme validations réussies ; synthèse actualisée sur place et rafraîchissement du dashboard toutes les 5 s. Aucun lien permanent changé. Le déploiement Google reste bloqué dans ce cloud (proxy 403 et absence de session Google autorisée) : le push GitHub ne vaut pas déploiement Apps Script. Tests comparatifs locaux passés ; voir RESULTATS_VALIDATION_FINALE.md pour les passages Windows.

## Windows Update sans surveillance — 2026-10-16

À la demande du technicien, All in App transmet les commandes natives Windows Update puis continue. Aucune attente de fin, aucun contrôle du nombre de mises à jour restantes, aucun arrêt de Windows Update après un délai. Les anciens réglages de délai sont ignorés. Une demande transmise est informative ; l’échec de toutes les commandes reste une erreur avec sa cause. Les erreurs des autres étapes et l’arrêt avant la fin restent bloquants. Les helpers COM historiques ne sont plus appelés par les chemins actifs, y compris le mode WindowsUpdateWorker.

Les trois EXE sont régénérés séparément en conservant leurs interfaces et ressources. La validation Windows GitHub exécute trois passages par dépôt, avec frontières système simulées pour éviter toute installation sur les runners ; elle vérifie aussi la fermeture et le suivi final. Résultats détaillés dans RESULTATS_WINDOWS_UPDATE.md.

Confirmation Windows GitHub : trois passages réussis sur la version `070cf68`, codes réels des phases tous à zéro. [Rapports](https://github.com/holyonefr/LDLC-Preparation/actions/runs/38959587495). Les neuf passages des trois éditions et leurs 27 phases sont vérifiés ; portée et limites détaillées dans RESULTATS_WINDOWS_UPDATE.md.

## Corrections de l’audit — 17 octobre 2026

Chaque correction est publiee et testee sous Windows GitHub avant la suivante. Le premier passage verifie aussi le vrai client vers le dashboard permanent (debut/fin, erreur1603, arret), puis supprime uniquement ses rapports CODEX-TEST. Aucun historique client ni endpoint modifie.

### Correction 1 — demande Quitter au demarrage
Le worker principal preserve maintenant toute demande LDLC_STOP creee apres le lancement de l’UI, y compris pendant son initialisation. Les anciennes demandes restent nettoyees par l’UI avant le lancement ; l’initialisation hors worker conserve son nettoyage historique. Test de demarrage/annulation ajoute aux suites Windows.

### Correction UI — bouton Quitter
LDLC reprend l’alignement Numerik’s dans le pied de fenetre, sous la zone de progression (reference174x34 a1450/725). Les deux editions gardent une cible minimale et ajustent le texte quand la fenetre est reduite, pour eviter le bouton trop petit detecte par le nouveau Preview natif. L’action de fermeture reste identique.

### Correction 2 — sauvegardes concurrentes
La lecture/fusion/remplacement et la suppression apres acquittement sont serialisees par un verrou fichier stable de l’outbox. Aucun verrou maintenu pendant HTTP. Une ancienne requete ne peut plus ecraser ou supprimer un resultat plus recent ; la fin reste sauvegardee avant transmission.

### Correction pilotes NVIDIA
Le repli commun refuse les codes d’echec, les expirations et une cible officielle inconnue, et conserve le besoin de redemarrage. ADDON utilise la resolution et l’installateur officiels existants pour la derniere version compatible, puis une vraie mise a niveau Chocolatey avec checksums et verification de la version effective. Ni NVIDIA App supplementaire, ni ajout AMD/Adobe/validateur. Le helper de comparaison Trackman reste distinct.

### Correction 5 — confirmation de la mini-interface
Un message de progression non acquitte par la mini-interface reste un diagnostic informatif. Il ne transforme plus en avertissement une association effectivement confirmee par Windows. Le clic physique reste interdit sans acquittement ; une association absente, une erreur reelle et une annulation restent bloquantes. Tests du statut de telemetrie ajoutes pour les trois cas.

### Validation finale des corrections
Les passages Windows et les remontées réelles au dashboard sont détaillés dans [RESULTATS_CORRECTIONS_AUDIT.md](RESULTATS_CORRECTIONS_AUDIT.md), avec les comparaisons avant/après, les incidents résolus et les limites des essais.

### Lecture de controle du dashboard — 17 octobre 2026
Le controle GitHub abandonnait a la premiere WebException pendant un GET de verification, malgre des tests Windows et des acquittements precedents reussis. Le helper de lecture limite maintenant les essais a trois, uniquement pour erreurs HTTP temporaires (408/429/500/502/503/504), timeout ou coupure reseau. Les erreurs de droits, TLS et contrat JSON invalide restent en echec immediat. Etape exacte, nombre de tentatives, statut HTTP/reseau et duree sont journalises sans URL authentifiee ni valeur sensible. Aucun changement du POST client, de la file durable ou des regles de validation ; aucun deploiement Apps Script. Le test reproduit l’ancien echec puis couvre 29 scenarios / 140 assertions.

Resultats et limites de ces modifications dans [RESULTATS_CORRECTIF_DASHBOARD_UI.md](RESULTATS_CORRECTIF_DASHBOARD_UI.md). Les nouveaux essais GitHub sont suspendus a la demande utilisateur concernant les e-mails.

### Tableau du dashboard compact — 17 octobre 2026

Colonne « Dernier message » retirée du tableau, contenu conservé dans Détails
fermé par défaut et dans le CSV. Cause de blocage et avertissements consultables.
Tests Node et Chromium locaux réussis pour LDLC, Numerik’s et ADDON. Source
adaptée séparément dans les deux dépôts ; aucun EXE/module principal modifié.
Publication Apps Script non effectuée : session Google autorisée absente du cloud.
Voir [RESULTATS_DASHBOARD_TABLE_COMPACT.md](RESULTATS_DASHBOARD_TABLE_COMPACT.md).

## Recherche indépendante logiciels constructeurs — 18 octobre 2026

Travail limité à `tools/experimental/vendor-utility` et son workflow manuel.
Détection ASRock par modèle/OS sur catalogue officiel, version numérique et SHA256 ;
détection dynamique GCC ; contrôles de substitution/version des paquets ; inspections
statiques MSI Appx et cœur GCC. Aucun profil automatique réel activé. Les installateurs
constructeurs ne sont jamais exécutés sur les VM GitHub ; aucun changement des trois
applications, ressources, modules ou EXE, conformément à la demande utilisateur.
La compilation/synchronisation des applications ne s'applique donc pas à ce prototype.
Résultats et limites conservés dans `tools/experimental/vendor-utility/RESULTATS_WINDOWS.md`.

Passe approfondie corrigée du 18 octobre : run GitHub 39127977792, code b950fef,
212 scénarios / 501 assertions / 0 échec, sans installation constructeur.
Téléchargements et signatures réels ; catalogue GCC Windows HTTP 403 distinct de
l'audit sur réponse officielle enregistrée. MSI Appx déclare une tâche de démarrage
Enabled=true ; aucun profil automatique activé. Échecs précédents et corrections
conservés dans le rapport et les preuves JSON, recherches dans RECHERCHE_APPROFONDIE.md.

Comparaison Windows GitHub supplémentaire : le workflow manuel indépendant permet
désormais windows-2022 et windows-2025. Il enregistre uniquement versions OS, PowerShell,
.NET et image runner, sans nom du poste/utilisateur. Aucun installateur constructeur
exécuté ; aucun module/EXE des applications principales changé.

Comparaison terminée : run Windows Server 2025 39137210458 (code 4df3ba3),
212 scénarios / 501 assertions / 0 échec, comme Windows Server 2022.
Versions, empreintes et signatures comparées sans différence ; installation toujours
simulée et catalogue GCC issu de la réponse enregistrée explicitement. Preuve JSON
conservée avec le rapport ; aucun profil réel activé.

## Raccourci de l’installateur sur le Bureau — 18 octobre 2026

Demande utilisateur : après téléchargement vérifié, créer un raccourci Bureau vers
l’installateur pour installation manuelle. Prototype indépendant uniquement : copie
persistante par utilisateur/version/hash, signature et version recontrôlées, raccourci
« Installer … version » sur le vrai Bureau, y compris OneDrive. Aucun lancement
automatique et aucune installation annoncée. Champs InstallerShortcut/InstallerVersion
distincts du raccourci de l’application déjà installée. Portables toujours exclus
avant réseau/raccourci ; bundle GCC facultatif non proposé. Tests ciblés et workflow
manuel installer-shortcut, sans modification des trois applications principales.

Raccourci installateur confirmé sur Windows GitHub : run 39149548075, code 5c1a17c,
52 scénarios / 136 assertions / 0 échec. Deux vrais téléchargements ASRock 2.0.0.9
et créations/relectures COM des raccourcis sur Bureau classique et redirigé OneDrive
avec identité carte mère simulée ; signature et cible réelles. Aucun installateur
exécuté. Preuve JSON et portée détaillée dans le rapport indépendant.

## Raccourcis installateurs des autres fabricants — 18 octobre 2026

Demande étendue à MSI/ASUS/GIGABYTE. Les raccourcis restent manuels, dans le prototype
indépendant. GCC : résolution de la source actuelle, téléchargement officiel signé,
extraction statique du seul cœur Control Center, jamais du lanceur All_Setup. Outils
portables officiels 7-Zip épinglés par empreintes, lus/extraits sans installation de
7-Zip ; aucun installateur constructeur exécuté. Comparaison séparée bundle/cœur.
Tests Windows dédiés avec vrais téléchargements et vrais raccourcis, données matérielles
simulées, plus refus des paquets ambigus et empreintes invalides. Aucun EXE principal
recompilé ou modifié.

Résultats raccourcis autres fabricants : run 39150418739 (fa1fec0), MSI et ASUS
réussis sur Bureau classique/OneDrive ; deux échecs GCC uniquement HTTP 403 sur
les trois sources/clients officiels. Run 39150779657 (1fffa1d), 113 scénarios /
258 assertions / 0 échec pour extraction/raccourci GCC avec catalogue enregistré
explicitement. Vrais téléchargements, outils portables officiels, signatures et
raccourcis ; matériel simulé. GCC n’est pas annoncé entièrement validé : source
live Windows toujours bloquée. Aucun ancien paquet de secours dans le script
utilisateur. Rapports et JSON conservés ; profils d’installation automatique désactivés.

## GCC : manifeste officiel du programme seul — 18 octobre 2026

Nouvelle recherche demandée pour GIGABYTE Control Center. Diagnostic Windows natif
39151768680 : curl système et HttpClient reçoivent HTTP 403 sur les trois pages web
officielles ; curl Git absent de ce runner, donc non testé. Analyse statique des DLL
distribuées, sans chargement/exécution constructeur : le logiciel lit son manifeste
LiveUpdate4/GCC/GIGABYTE Control Center/ver2.ini puis construit le lien de son seul
installateur. Cette source officielle renvoie 26.08.28.01 / 52 064 856 octets dans
le cloud. Le prototype utilise désormais ce manifeste dynamique, vérifie taille
HTTP/manifeste, signature, version et hash avant raccourci manuel. Aucun fallback
vers ancien paquet/catalogue, aucun pilote/BIOS/module sélectionné. Tests ciblés et
nouvelle phase Windows gigabyte-installer-shortcut ; résultat natif à consigner.
Aucune application principale modifiée, aucun installateur constructeur exécuté.

Inspection complémentaire : le téléchargement LiveUpdate_GCC de 52 Mo contient
GCC plus MB Update/RGB Sync. Extraction statique du seul installateur interne GCC,
avec identité produit exacte et version égale au manifeste ; raccourci vers ce
fichier uniquement. Le cœur extrait correspond par hash à celui audité auparavant
(886A910A…D2F81), pas au wrapper Liveupdate_GCC (86EF9762…C2A10).
Le run 39152229944 du premier candidat démontre l'accès réseau et les raccourcis
mais précède cette correction : il ne valide pas l'exclusion des modules. Nouveau
test natif requis sur le code corrigé ; les cas simulés refusent aussi un wrapper
se faisant passer pour le cœur, une version interne ancienne et un fichier facultatif extrait.

Validation finale GCC live : run 39152522107, code 122a837, Windows Server 2025 /
PowerShell 5.1, 86 scénarios / 187 assertions / 0 échec. Deux consultations live,
vrais téléchargements signés et extraction du cœur 26.08.28.01, raccourcis COM sur
Bureau normal/redirigé OneDrive-fixture, arguments vides et cible vérifiée. Aucun
installateur constructeur exécuté ; matériel simulé et installation physique non
vérifiée. L'essai précédent 39152385991 avait deux échecs de lecture d'archive :
son en-tête contenait le nom absolu du wrapper identique au cœur. Correction par
liste des seules entrées 7-Zip (-ba), avec régression simulée et test natif réussi.
README, rapport et quatre preuves Windows conservés ; source statique détaillée
dans le JSON de découverte du manifeste. Les trois applications restent inchangées.


## Depot beta et integration constructeur — 18 octobre 2026

Copie des 174 fichiers suivis de LDLC stable a2a57ee dans le depot vide LDLC-Preparation-PC-test-app. Publication reservee a ce depot a la demande utilisateur. Integration beta du prototype constructeur a 82 %, apres applications et avant associations : cinq modules embarques et verifies par hash, chargement differe, rapport local, installation manuelle, portables exclus, erreurs visibles et repli manuel normal informatif. UI, assets et configuration Google preserves. Regle de synchronisation durable dans AGENTS/BETA, helper de synchronisation sans aucun push et refus de conflits. Tests beta et workflow Windows natif a consigner apres execution.

Validation beta finale : run 39153783822, sources e9df3aa, EXE Windows publie en
2632098. Integration 11/26/0, synchronisation 6/11/0, raccourcis GCC live 16/64/0,
suite release 35 PowerShell + 3 JS + diagnostics du lanceur reussis, quatre vrais
Preview/fermetures en processus isoles reussis (1,481 a 1,739 s depuis EntryPoint,
hors UAC). Le premier run 39153507394 echouait au deuxieme Preview par reutilisation
du processus Windows Forms ; test corrige sans modifier le lanceur ni l'UI.
SHA256 EXE C98364BA1221C684DE893D325E5C2F8A394CC68DAC54FF86B4F7EAE8EDE19643,
verifie apres recuperation Git LFS. Rapport et JSON dans beta/. Aucune installation
constructeur reelle ; preuve GCC reseau/signature/COM reelle avec materiel simule.
Les trois refs de production sont restees inchangees, aucun push sur ces depots.


## Fiabilite constructeur et capture Bureau — 18 octobre 2026

Deux passages photo reussis 39157346040/39157773796 : 23 scenarios / 136 assertions
chacun, quatre telechargements par marque au total, vraie capture Windows dans
beta/evidence/desktop-shortcuts. Nouveau code : requetes courantes sans cache,
maximum trois reprises dans un budget de temps unique, controles TLS/signature/
integrite conserves, nouvelles versions des quatre marques testees sans epinglage.
Repli ajoute vers une page officielle via .url, toujours un avertissement manuel.
Version avant ce repli poussee en af5d0f3, puis candidat 3e384af, validation native
complete 39158843568 et livraison Windows 69e63c9. EXE SHA256
F84E27C13A2373552A6C6883339E1E3FB791838991E6847429454D820E172E45 verifie localement.
Huit nouveaux telechargements reels et quatre Preview/fermetures reussis ;
54 scenarios / 110 assertions de repli .url reussis sous Windows, erreurs simulees.
Aucune installation constructeur executee sur la VM, aucun push des trois productions.

Derniere precision utilisateur : un lien de page officielle ne suffit pas comme
fallback ; rechercher d'autres sites/liens de telechargement des quatre applications.
Aucun miroir binaire alternatif valide ni active pour l'instant. MSI Store : fiche
reelle 200 et identite confirmee, acquisition du paquet non testee. WinGet MSI reste
2.0.72 et son URL retourne vers MSI ; Chocolatey app-shop 1.0.31 trop ancien ;
Ninite/Scoop Extras sans correspondance demandee. Les miroirs explores rencontrent
un refus 403 du tunnel cloud ; autorisations reseau sauvegardees en brouillon,
publication de l'environnement requise avant verification. Voir beta/REPLI_TELECHARGEMENTS.md.


## Fin du module Installation des applications — 19 octobre 2026

Instruction utilisateur maintenue : publication uniquement sur le depot beta.
Module constructeur deplace de 82 % (Configuration) a 60 % (fin Installation),
immediatement apres la boucle des logiciels, avant la configuration du bureau.
Defaut Invoke-LDLCVendorUtility=60. Aucune installation automatique constructeur
ajoutee et aucun miroir binaire non verifie active. Sept scenarios d'orchestration
reelle/phase UI avec actions simulees, 25 assertions, passes sous Linux puis Windows.
Source ca08dca, run Windows 39202137884, integration 12/29/0, synchro 6/11/0,
suite release et quatre Preview/fermetures reels passes. EXE Windows publie en
94c449d, SHA256 B8DA90B2805638DE294C1647C4323F717833A93808CEF063E503EF7F4F4AAD5C
recupere/compare au rapport et au manifeste. Preuves dans beta/evidence/placement-39202137884.
Workflow de placement declenche une fois par push car l'API Actions est refusee,
puis repasse en manuel ; pas de nouveau telechargement materiel a ce passage.

Recherche de replis : deux adresses retrouvees dans les copies de sources officielles :
MSI download.msi.com/uti_exe/desktop/MSI-Center.zip et ASUS geo.asus.com/driverhubcn/.
Provenance hash dans beta/evidence/official-alternative-links.json, destinations/
versions non validees car CONNECT 403. Ni basculement regional ni miroir non valide
active. Brouillon reseau sauvegarde avec les domaines miroirs, ces points officiels,
Store et API/docs GitHub ; requires_publish=true, pas applique a l'instance.
La suite de cette recherche reste bloquee par l'activation reseau ; ne pas la declarer
terminee ni utiliser une version ancienne pour forcer le succes.


## Retest de la beta — 19 octobre 2026

A la demande utilisateur, nouvelle execution Windows sur 565373c : run 39202911489
compile/release/placement/integration/synchro et quatre Preview/fermetures reussis.
Run independant 39202954609 phase validate, Windows 2025 : 37 scenarios / 89
assertions / 0 echec, CIM reel (VM refusee), vrai raccourci COM dans Bureau redirige
OneDrive-fixture et restauration ; cible inerte, aucune application executee.
Total groupes comptes : 62 scenarios / 154 assertions, plus suite release et UI4.
Livraison Windows f12249d, SHA256
3402ACFCDD9D6FADD77FD30BB531B618BFABA6C1F6914CC1B02123201115DC88 verifiee.
Les quatre sondes reseau cloud constructeurs sont bloquees CONNECT 403 ; aucun
telechargement materiel reel ni miroir externe teste dans cette relance.
Acces API GitHub de nouveau fonctionnel : declenchements manuels et collecte des
annotations officiels reussis, sans modifier les workflows ni le code application.
Rapports dans beta/RESULTATS_WINDOWS.md et beta/evidence/. Production inchangee.


## Tests des quatre All in App — 19 octobre 2026

A la demande utilisateur : trois passages Windows 2022 par application, douze jobs
reussis, 66 controles de haut niveau code 0, 21 Preview/fermetures explicites.
LDLC 39214000180 (a2a57ee), Addon 39214000300 (22ad812), Numerik's 39214000170
(1a4dae5), beta 39214348903 (9f510de). Chaque comparaison finale rejoue 11 scenarios
corriges et les 7 scenarios historiques attendus en echec. Les suites release et
les tests specialises d'edition passent ; la beta ajoute integration/placement/
synchro et trois Preview compiles en plus du Preview de l'EXE livre par passage.

Defaut trouve dans le test beta uniquement : c205efc absent de l'historique copie.
Helper adapte a quatre fichiers historiques figes, SHA256 verifies, URLs et valeurs
de configuration inertes, exclus du build. .gitattributes preserve les octets sous
Windows. Controle local avant : 7 scenarios, 32 checks, 17 echecs attendus, exit 1 ;
apres : 11 scenarios, 66 checks, zero echec, exit 0. Puis trois passages Windows
beta reussis, sans retirer aucun controle ni changer la logique des applications.
Les deux helpers beta sont ajoutes aux OverlayPaths. Correction de test en 9f510de.

Dashboard reel : LDLC, Addon et Numerik's ont chacun transmis success/failed/stopped ;
serveur observe success/error/stopped, isFinal/edition/version/ack et cause 1603
controles. Neuf lignes CODEX-TEST uniques supprimees puis absence verifiee.
Le champ validation.state est absent des reponses live (non_exposee), contrairement
au contrat local Apps Script : etat validated/blocked du service deploye non prouve.
Ne pas annoncer cette partie comme validee et ne pas deployer le backend dans le gel.
La beta ne lance pas de roundtrip permanent distinct. Les actions systeme et toutes
installations restent simulees ; les Preview, compilations et roundtrips sont reels.

Rapport beta/TESTS_QUATRE_APPLICATIONS_2026-10-19.md, projections des annotations sans
identifiants/URLs/donnees clients dans beta/evidence/full-suite-2026-10-19/.
Une annotation de lecture globale LDLC est tronquee, champs complets conserves ;
les trois roundtrips sont complets. Pas de push des productions ni de deploiement.
Leurs trois refs sont verifiees inchangees. Tous les workflows beta restent manuels.

### Détails dashboard compacts — 19 octobre 2026

Un encadré par exécution, compteurs et résumé court ; aucune liste complète
d'avertissements empilée dans le tableau. Texte complet dans un dialogue séparé.
12 combinaisons navigateur validées, compatibilité et ingestion locales réussies.
Voir beta/DASHBOARD_DETAILS_COMPACTS_2026-10-19.md. Déploiement Google encore bloqué
par CONNECT 403 et absence de session clasp autorisée ; ne pas annoncer le rendu
en ligne sur la seule base du push bêta. Aucun EXE modifié pour cette correction.

### Texte sous progression et Edge — 19 octobre 2026

Deux lignes agrandies dans la bêta uniquement. Le contrôle de désépinglage ne
confond plus AppsFolder avec la barre des tâches : dossier des épingles et verbe
Shell français/anglais. Une épingle réellement persistante garde son avertissement,
Edge seulement ouvert devient informatif. Comparaison avant/après et huit scénarios
simulés : tools/Test-LDLCTaskbarPins.ps1, ajouté à la suite release.
Voir beta/UI_EDGE_2026-10-19.md pour la validation Windows et la portée exacte.

Précision utilisateur : agrandir aussi LDLC stable et Addon, jamais Numerik's.
Corrections de polices préparées localement dans ces deux dépôts, sans publication
de production. Bêta synchronisée avec l'UI LDLC locale (SourceWorkingTreeDirty=true).
Hauteurs GDI+ réelles réservées pour éviter la coupe dans la petite fenêtre du
runner. Test natif du dessin isolé LDLC/bêta et Addon à trois tailles ajouté à la
suite release ; fixture Addon limitée aux fonctions de dessin, jamais embarquée.

Validation finale réussie : run 39241128195, source c1d78dc, six rendus GDI+ natifs
LDLC/bêta/Addon et quatre vrais lancements/fermetures. Livraison bêta 7b1dcba,
SHA256 B8BC83FDF8D469C09F698B2D30911BD7C025F04556E574187DA88C25A9BBA288.
LDLC et Addon : sources de polices locales seulement, aucun EXE de production
reconstruit/poussé. Addon main/worker identiques et Test-AddonSync Linux réussi.
Numerik's intact. Dashboard préparé mais non déployé (Google CONNECT 403).

### Bouton Quitter tronqué — 19 octobre 2026

Dimensions natives préférées et AutoSize/GrowOnly remplacent la hauteur de 14 px
et la réduction excessive de police. Padding explicite, texte centré, ancrage
bas/droite ; aucun changement du clic ni de la demande d'arrêt. Même correction
préparée localement dans LDLC et Addon, aucune publication de production.
Contrôle Windows renforcé (préférence native, coins, pixels du libellé) et Preview
isolé publié avec la livraison pour inspection visuelle. Rapport :
beta/QUIT_BUTTON_2026-10-19.md ; attendre les résultats avant d'annoncer la réussite.

Résultat final : run Windows 39266577489 réussi sur 8c215d0 ; quatre vrais Preview
et fermetures, libellé vérifié par ses pixels, centrage, taille native et région.
Bouton 75 × 26 dans la petite fenêtre 481 × 222, au lieu de 50 × 14. Capture réelle
inspectée dans beta/evidence/quit-button-2026-10-19/ui-preview.png. Livraison bêta
fa07625, SHA256 3BE15311787BD6E55C84A91C659F4E157354A4ACBC94D18184381C62F72E03E5.
Pas de publication LDLC/Addon/Numerik's. Addon local main/worker et suite locale OK.

### Reprise visuelle du bouton — 19 octobre 2026

L'utilisateur a refusé la capture 75 × 26 : le contrôle ne tenait pas compte du
cadre de progression. Disposition revue sans changer la taille de fenêtre :
bouton compact GrowAndShrink, bandeau bas réservé, contenu/cadre de progression
remontés ensemble à petite taille et hauteur native des textes d'étapes.
La revue ui-preview.yml run 39270324865 est passée : quatre vrais Preview,
57 × 22, cinq pixels entre cadre et bouton, image complète inspectée. Aucun EXE
publié pendant cette revue. Le premier essai avait échoué sur un coin de fenêtre ;
marge corrigée sans affaiblir le test. Capture même en échec et cause native
disponibles via workflow UI dédié. Sources LDLC/Addon locales adaptées ; Numerik's
intact. Livraison complète réussie : run 39271341285 sur e24ab79, six rendus natifs
et quatre nouveaux Preview/fermetures (huit avec la revue), aucun échec.
EXE bêta publié en 2547252, SHA256
0646BA6C805B3BA3D1D60B527A728C3EEB2E9D03655B0463438F5FC0E96FE218.
Capture finale inspectée et annotations/empreinte vérifiées. Les anciennes mesures
75 × 26 et l'ancienne empreinte ci-dessus sont historiques et remplacées par cette
livraison. Voir beta/QUIT_BUTTON_2026-10-19.md et ses preuves Windows.

### Nouvelle vérification des lignes du dashboard — 19 octobre 2026

Google sert encore l'ancienne version : réponse HTTP 200, en-tête « Dernier
message » dans le HTML sandbox encodé, aucune classe run-detail-card. Ce constat
explique la capture utilisateur malgré le correctif GitHub. Pas de données client
conservées ni de modification de l'historique. Aucune session Google autorisée
pour publier ; ne pas annoncer le dashboard corrigé en ligne.

Résumé désormais limité à deux lignes et 33 px même sans line-clamp, colonnes
adaptatives et en-têtes/statuts sans coupure de mots. Douze essais Chromium et
contrôles Node compatibilité/ingestion réussis. Aperçu synthétique complet et
procédure de mise à jour du déploiement permanent dans
beta/DASHBOARD_DETAILS_COMPACTS_2026-10-19.md. Aucun changement des EXE ou de l'UI
All in App, aucun push des productions.

### Luminosité dashboard et préparation OAuth — 19 octobre 2026

Teintes ardoise éclaircies dans dashboardCss_ uniquement : fond, menu, cartes,
champs, tableau et bordures. Statuts, tailles de police et fonctionnement
inchangés. Aperçus inspectés, 12 essais Chromium et tests Node réussis ; voir
beta/DASHBOARD_LUMINOSITE_2026-10-19.md. Aucun EXE changé.

À la demande de l'utilisateur, préparation OAuth dans /workspace/cloud-setup/google-oauth,
hors Git : assistant Windows Connexion-Google-Dashboard.zip, SDK officiel clasp
3.4.1, contrôle en lecture seule du projet/déploiement permanents et erreurs
expurgées. Le brouillon cloud enregistre le secret personnel
GOOGLE_APPS_SCRIPT_REFRESH_TOKEN, destiné uniquement à oauth2.googleapis.com,
et les instructions d'installation/démarrage. Aucune valeur saisie ni session
Google réelle à ce stade. Le propriétaire doit autoriser Google sur son PC,
coller le jeton via les paramètres secrets, puis enregistrer/publier
l'environnement. Jamais de jeton/mot de passe/code OAuth dans le chat ou Git.
Contrôles hors ligne et préparation PowerShell sans login réussis ; connexion
réelle, consentement Windows et publication Google restent à vérifier ensuite.

### Chrome par défaut, épinglage vérifié et portables AMD — 20 octobre 2026

Correction uniquement bêta : bouton navigateur global tenté avant HTML, un clic
observé protégé si Invoke reste sans effet, confirmation native des associations
plus courte et absence d'avertissement intermédiaire périmé. Épinglage vérifié par
Windows, avec repli sur le menu du fichier Chrome exact ; suppression de l'ancien
succès XML sans preuve et de son redémarrage global Explorer. Nouveau module
72.ChromeTaskbar.ps1 dans l'ordre du build. Portables/tablettes et format inconnu
exclus de l'installation automatique Adrenalin, avant réseau ; NVIDIA conservé.

Tests ciblés locaux réussis, reproductions avant correction en échec attendu.
Nouveaux tests intégrés à la suite release, dont API d'associations et raccourcis
COM natifs isolés sous Windows. Audit Sync-LDLCBeta requis avant publication ;
overlays enregistrés. Rapport et validation native : beta/CHROME_AMD_2026-10-20.md.
Ne pas présenter les interactions Settings/épinglage simulées comme des essais
sur un PC Windows 11 physique. Aucun push de production, aucune installation
constructeur ou matérielle réelle sur runner, aucun déploiement Google.

Première validation Chrome/AMD réussie : run Windows 39406284841, source 749d5eb,
quatre vrais Preview/fermetures, suite release et API natives isolées. EXE bêta
d3f6a73, SHA256 5A019D347988301C82102C2F7BA6D0A9C6EE35B4E05EFE46E07D3D4600C52918.
L'utilisateur a ensuite autorisé « Push sur les trois » pour cette correction.
Cœur 2.6.6 intégré depuis LDLC/Numerik's ; les overlays Chrome sont identiques,
module carte mère et tests/rendu bêta préservés. Workflow de livraison production
volontairement absent de la bêta (overlay) : beta-validation.yml reste sa voie
de build. Nouvelle validation native après synchronisation requise.

Validation synchronisée 2.6.6 terminée : run 39407935800 sur 862340d, suite release,
intégration carte mère et quatre vrais Preview/fermetures réussis. Livraison bêta
93ba2d6, SHA256 79C2C4C288A23191A492C647347EE25434DE5C8F7FF6C0BE5554D6A5833C9BF5.
Productions : LDLC run 39407672991, Numerik's 39407677065, Addon 39408146830,
quatre lancements par édition et suites complètes passés, EXE effectivement publiés
puis empreintes vérifiées. Premier essai Addon validé en tests mais refusé en
publication, puis sorties LF et diagnostic ajoutés avant relance complète réussie.
Nouvelle synchronisation finale : seuls résultats/docs et métadonnées arrivent
depuis LDLC ; aucun changement de code après les compilations validées.
Les anciens agrandissements UI locaux de production sont laissés hors livraison.

### Retrait des attentes Chrome et désinstallateurs visibles — 20 octobre 2026

À la demande utilisateur, le parcours Chrome transmet ses commandes sans attendre
ni recontrôler les associations ou l'épingle finale. Pas de succès vérifié inventé ;
les vraies commandes impossibles restent signalées. Adobe conserve son parcours
dans LDLC/Numerik's, aucune étape Adobe/AMD dans l'Addon.
Nouveau module 52.SecurityUninstall.ps1 : ouverture normale du désinstallateur
enregistré McAfee/Norton avant les installations, retrait des switches silencieux,
attente de retrait et de sortie du parent sans limite de 90 s ni taskkill. Quitter
reste réactif. Refus/annulation/redémarrage avec produit présent : arrêt et cause,
aucune validation forcée. Addon : étape au début et antivirus exclus du nettoyage
OEM tardif. Tests de commande, attente longue, processus parent/enfant, erreurs,
annulation et absence d'installations après blocage ajoutés.
Voir RESULTATS_CHROME_ANTIVIRUS_2026-10-20.md pour les résultats natifs et la portée
des fixtures ; ne pas prétendre une désinstallation antivirus réelle sur runner.

Bêta 2.6.7 livrée : run Windows 39413059512, source c37c725, EXE 75f7cd0,
SHA256 E80699630145E474E6B97F073F46EE71BD830E4D66FA16AA59287D3760385380.
Suite complète, carte mère préservée, fenêtre factice de désinstallation affichée
et quatre vrais Preview/fermetures réussis. Productions également livrées : LDLC
39412857978, Numerik's 39412861967, Addon 39412866385. Source classique partagée
2.6.7 ; aucun antivirus réel désinstallé sur runner, clics Chrome simulés. Les
regroupements d'erreurs AV et les sorties anticipées restent bloquants. Résultats
communs fusionnés ici sans supprimer les overlays bêta ni publier les UI locales
précédentes. Dernière synchronisation : docs/preuves/métadonnées seulement.
