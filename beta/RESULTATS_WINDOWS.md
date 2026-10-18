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
