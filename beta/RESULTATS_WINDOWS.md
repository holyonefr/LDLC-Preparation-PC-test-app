# Validation de la beta LDLC — 18 octobre 2026

Run reussi : [39153783822](https://github.com/holyonefr/LDLC-Preparation-PC-test-app/actions/runs/39153783822).
Sources testees : `e9df3aa6d53a4d89def7fd8b82db404d1eda1ddb`.
Livraison compilee sous Windows et poussee apres les tests :
`2632098d07e7f4bf4097a153eb45815787a972d8`.

SHA256 de `dist/LDLCPreparationPC.exe` :
`C98364BA1221C684DE893D325E5C2F8A394CC68DAC54FF86B4F7EAE8EDE19643`.
L'EXE recupere depuis GitHub a ete compare a cette empreinte : identique.

## Controles passes sous Windows Server 2025 / PowerShell 5.1

| Controle | Resultat |
|---|---|
| Compilation native C# / scripts principal et worker | Reussie |
| Integration beta : sources embarquees, import reel, portable exclu avant reseau, resultat manuel, erreur precise, arret | 11 scenarios / 26 assertions / 0 echec |
| Synchronisation : audit, copie, conflit, overlay, suppression, protection du depot | 6 scenarios / 11 assertions / 0 echec, depots locaux fictifs sans reseau/push |
| Suite release existante | 35 suites PowerShell, 3 suites JS et diagnostics du lanceur BootstrapTest/SelfTest/WorkerSmokeTest passes |
| Telechargement GCC live et raccourcis | 16 scenarios / 64 assertions / 0 echec, dont 2 vrais telechargements et raccourcis COM Bureau normal/redirige OneDrive |
| Quatre ouvertures/fermetures du vrai EXE en Preview | 4/4 reussies dans quatre processus isoles, bouton Quitter visible et non coupe |

Temps observes depuis l'EntryPoint jusqu'a la fenetre Preview visible :
**1 739 ms, 1 516 ms, 1 481 ms et 1 494 ms**. Ces mesures ne comprennent ni le
clic utilisateur, ni l'UAC. Elles ne garantissent pas la meme duree sur tout PC.

GCC detecte en direct : **26.08.28.01**, methode
`official_gcc_software_update_manifest`, sur le serveur officiel
`mb.download.gigabyte.com`. Le coeur extrait est signe
**GIGA-BYTE TECHNOLOGY CO., LTD.**, empreinte
`886A910ABF855F947E6B92921C068CC13C06106951D3EE40CA24CC0B110D2F81`.
Le raccourci pointe vers ce coeur, pas vers le wrapper contenant MB Update/RGB Sync.
Les sources MSI/ASUS/ASRock, conservees du prototype deja teste, n'ont pas ete
retelechargees dans ce passage beta ; leurs precedentes preuves sont conservees
dans `tools/experimental/vendor-utility/evidence`.

## Limites des essais

Aucune preparation destructive complete et aucune installation constructeur reelle
sur la VM. Les operations systeme de la suite release sont simulees ; les tests
beta simulent le materiel et les resultats de l'etape. Pour GCC, reseau, extraction,
signature et raccourcis sont reels, mais l'identite de carte mere est simulee.
Le Bureau OneDrive est une vraie redirection de dossier Windows vers un dossier
de test, sans connexion a un compte OneDrive. Installation manuelle et compatibilite
materielle restent a verifier sur les PC physiques. Aucun succes d'installation
n'est annonce par ces essais.

## Premier passage et correction du test

Le run [39153507394](https://github.com/holyonefr/LDLC-Preparation-PC-test-app/actions/runs/39153507394)
avait deja reussi compilation, integration, synchronisation, suite release et GCC live.
Sa boucle d'interface reutilisait un meme processus : premiere ouverture reussie,
deuxieme refusee par Windows Forms avec
`SetCompatibleTextRenderingDefault must be called before the first IWin32Window object is created`.
La publication Windows etait donc bloquee.

Le test lance maintenant quatre processus PowerShell STA distincts, chacun appelant
l'EntryPoint du vrai EXE en Preview pour eviter un prompt UAC pendant le test.
Cette correction concerne le test, pas le fonctionnement de l'application.
Le second run reussit et publie uniquement les livraisons de ce depot beta.

Les deux preuves brutes sont dans `beta/evidence/windows-<run>.json`.
`production-freeze.json` conserve les trois references de production verifiees
inchangees. Aucun push ni deploiement Google effectue sur les trois applications.


## Raccourcis des quatre marques et vraie capture du Bureau

Runs reussis [39157346040](https://github.com/holyonefr/LDLC-Preparation-PC-test-app/actions/runs/39157346040)
et [39157773796](https://github.com/holyonefr/LDLC-Preparation-PC-test-app/actions/runs/39157773796).
Chaque passage : 23 scenarios / 136 assertions / 0 echec, dont huit vrais
telechargements, signatures et raccourcis COM (Bureau et redirection OneDrive de test).
Soit quatre telechargements et creations/verifications de raccourcis par marque
sur ces deux passages. Carte mere simulee, aucun installateur constructeur execute.

| Application | Version officielle constatee dans les deux passages |
|---|---|
| ASRock APP Shop | 2.0.0.9 |
| MSI Center | 2.0.74.0 |
| ASUS DriverHub | 1.0.7.1 |
| GIGABYTE Control Center, coeur seul | 26.08.28.01 |

La [capture Windows reelle](evidence/desktop-shortcuts/desktop-shortcuts.png) est
issue du second passage, mode `actual_windows_desktop_screenshot`, sans retouche
ni generation d'image. Les quatre liens sont regroupes pour la demonstration ;
sur un PC, seule sa marque est selectionnee. Les autres icones sont preinstallees
sur le runner. Les cibles signees existaient lors de la capture, puis les fichiers
de test ont ete nettoyes. Les cibles de production sont conservees en stockage local.
SHA256 image : `946A2F27F69AA4F3A9E4E34DF359EC5CED0120F647BB9E9AED912C0A0F945535`.
Les deux preuves et les rapports/image sont conserves dans `beta/evidence/`.

Le telechargement de l'artefact Azure du premier passage a ete refuse (HTTP 403)
par le proxy cloud. Le second passage a regenere la capture sur Windows et l'a
publiee directement dans le depot beta autorise ; aucune recuperation de l'artefact
bloque par un relais. Le clic sur Installer ouvre l'installateur local verifie,
pas un site web ; l'installation reste manuelle et non validee sur cette VM.


## Dernier passage : reprises reseau, nouvelles versions et repli manuel

Run [39158843568](https://github.com/holyonefr/LDLC-Preparation-PC-test-app/actions/runs/39158843568),
Windows Server 2025 / PowerShell 5.1 : reussi. Sources `3e384afbb977363198ff9f8c5af23734163be8af`.
EXE compile/teste puis publie en `69e63c9f6771c4997562b1eef0ecdde57e816fd6`.
SHA256 recupere et compare au rapport Windows et au manifeste :
`F84E27C13A2373552A6C6883339E1E3FB791838991E6847429454D820E172E45`.

| Controle | Scenarios | Assertions | Echecs |
|---|---:|---:|---:|
| Integration beta, dont repli avertissement et exclusion portable | 12 | 29 | 0 |
| Synchronisation par depots locaux fictifs | 6 | 11 | 0 |
| Reprises HTTP et nouvelles versions MSI simulees | 21 | 27 | 0 |
| Detection ASUS et versions numeriques simulees | 43 | 112 | 0 |
| Detection ASRock par modele/OS simulee | 53 | 109 | 0 |
| Detection/extraction GCC simulee | 33 | 38 | 0 |
| Parcours constructeur simule, aucune installation reelle | 35 | 80 | 0 |
| Transport HttpClient reel avec reponses/flux simules | 44 | 142 | 0 |
| Repli officiel .url : vrais fichiers/COM Windows, erreurs simulees | 54 | 110 | 0 |
| Installateurs et raccourcis, dont huit vrais telechargements | 22 | 130 | 0 |

Suite release existante egalement reussie (35 suites PowerShell, 3 JS et diagnostics
BootstrapTest/SelfTest/WorkerSmokeTest). Quatre Preview/fermetures dans des processus
isoles : 1298, 1131, 1146 et 1128 ms depuis l'EntryPoint, hors clic/UAC.

Les nouvelles versions, schema invalide, erreur 403/404, 408/429/5xx, coupure,
fichier incomplet, certificat invalide, conflits de raccourcis et Bureau inaccessible
sont des simulations clairement identifiees dans le JSON. La reprise d'un flux
interrompu recommence a zero et ne laisse aucun fichier .part. Les fichiers .url
sont relus par COM, les deux redirections du Bureau sont restaurees apres test.
Ce repli ouvre seulement la page officielle : **ce n'est pas un miroir binaire**.
L'utilisateur a ensuite demande des sites de telechargement alternatifs : etude
separee dans [REPLI_TELECHARGEMENTS.md](REPLI_TELECHARGEMENTS.md), aucun miroir
binaire non verifie ajoute au telechargement automatique.

Les huit telechargements live retrouvent APP Shop 2.0.0.9, MSI Center 2.0.74.0,
ASUS DriverHub 1.0.7.1 et GCC coeur 26.08.28.01, signatures valides, sans installation.
Avec les deux passages de capture precedents, cela represente six telechargements
et verifications de raccourcis par marque (trois Bureau, trois OneDrive-fixture).

Les runs 39158466171 et 39158519116 ont ete annules pendant l'elargissement du
perimetre, avant la validation finale. Ils ne sont pas comptes comme reussis.
Seul le depot beta a recu les modifications et la livraison Windows.


## Placement a la fin des applications — 19 octobre 2026

Run [39202137884](https://github.com/holyonefr/LDLC-Preparation-PC-test-app/actions/runs/39202137884),
sources `ca08dca2225d709778ac181a0b1c7672d3884451`, validation Windows reussie.
L'etape constructeur passe maintenant juste apres le dernier logiciel, a **60 %**,
dans la phase **INSTALLATION** (25-60). La configuration du bureau commence ensuite.
Le pourcentage et l'ordre de tous les autres modules restent ceux de la preparation.
Le module prepare l'installateur et son raccourci ; l'installation reste manuelle.

| Controle Windows | Resultat |
|---|---|
| Orchestration reelle + fonction de phase UI reelle, operations systeme simulees | 7 scenarios / 25 assertions / 0 echec |
| Sources embarquees, portables exclus, erreurs visibles | 12 scenarios / 29 assertions / 0 echec |
| Synchronisation, fixtures Git locales | 6 scenarios / 11 assertions / 0 echec |
| Suite release existante et diagnostics du lanceur compile | Reussis |
| Vrai EXE, quatre Preview/fermetures en processus separes | 4/4, 1448 / 1239 / 1231 / 1223 ms depuis EntryPoint, hors clic/UAC |

Les scenarios executent le vrai parcours avec trois logiciels, un seul, aucun,
un echec du premier ou du dernier, un arret apres le dernier logiciel et un arret
pendant l'etape constructeur. Ils verifient l'unicite de l'appel, son ordre et le
nom de phase UI, sans lancer d'operation systeme ni d'installateur constructeur.
Aucun nouveau telechargement constructeur ou miroir pendant ce passage : il
valide le deplacement du module deja teste, pas de nouveaux liens externes.

Livraison Windows publiee en `94c449d945ad8ecbabe8bd613be0d0f64c169579`, SHA256
`B8DA90B2805638DE294C1647C4323F717833A93808CEF063E503EF7F4F4AAD5C`, compare a l'EXE
Git LFS recupere et au manifeste SHA256SUMS : identiques. Preuves dans
`beta/evidence/placement-39202137884/`. Les trois refs de production sont inchangees.

Les appels API GitHub Actions sont refuses par le proxy cloud. Le workflow cible a
ete declenche une seule fois par le push beta ; il a publie ses propres resultats
et l'EXE apres succes dans ce depot. Il repasse maintenant en declenchement manuel
pour ne pas generer de tests/notifications a chaque modification. Aucun contenu
externe refuse n'a ete telecharge par un relais.
