# Corrections du 20 octobre 2026 — beta 2.6.9

Statut : beta 2.6.9 compilee, testee et livree sous Windows.

Run : https://github.com/holyonefr/LDLC-Preparation-PC-test-app/actions/runs/39447605123
Source : c13c115f9f1c9f132a491249a25c18b596116ae5.
Livraison : b6617532bcf4775b2eef002a1411de83326498a8.
SHA-256 EXE : DDEF45E5335000E477A80A8F0C2CB3A31C00F425DC99C40A15A93AFC2E7CBDD0.
Empreinte recontrolee sur le vrai binaire LFS recupere.
Preuves : evidence/corrections-2026-10-20/windows-evidence.json.

- Chrome : retour a InvokePattern avant le clic observe ; controle court des
  associations HTTP/HTTPS/.htm/.html. En absence de bouton global, repli sur chaque
  association manquante. Un clic sans effet ne vaut plus reussite. Adobe conserve
  son parcours ; ADDON reste exclusivement Chrome.
- Barre des taches : utiliser en priorite le raccourci Chrome du menu Demarrer
  dont la cible est verifiee ; laisser a Windows un court delai d'application et
  verifier l'epingle avant de signaler le succes. Aucun remplacement des autres
  epingles ni strategie forcee.
- Transmission (beta uniquement) : reessai borne pour panne transitoire, cause
  precise sans secret dans le journal, delai configure respecte, rapport courant
  prioritaire sur un lot limite de rapports en attente. Conservation durable et
  suppression uniquement apres acquittement.
- McAfee : meme nettoyage historique dans les editions, worker isole 90 s,
  chemin avec espaces correctement transmis. Test du worker genere sans vrai
  antivirus ; Norton garde son desinstallateur interactif.

La lecture et les trois vrais envois avant correction ont reussi depuis le cloud :
reussite, erreur 1603 et arret, puis suppression de ces seuls rapports CODEX-TEST.
Le serveur est donc joignable actuellement. La cause exacte de l'incident du PC
photographie n'est pas prouvee : l'ancien client masquait l'exception de transport.
Le jeton OAuth de modification du dashboard est independant de ces envois.

Les memes fixtures reproduisent les trois regressions sur ba825782 et passent
avec les corrections. Elles simulent les actions Windows/reponses HTTP ; les
tests natifs sont maintenant passes : suite release, 4 vrais lancements Preview,
3 scenarios avant/apres, McAfee 14 cas/36 assertions (enfants Windows reels,
inventaire simule), Chrome 10 cas/28 assertions, epinglage 11 cas/26 assertions
avec raccourcis COM reels en dossier isole, transmission 12 cas/35 assertions.
Les trois vrais envois Windows sont acquittes et visibles avec les statuts
success/error/stopped, puis les seuls rapports de test sont supprimes (Cleaned=true).
Le serveur expose les statuts mais pas le sous-etat validation, donc ce sous-etat
n est pas certifie par le test live. Des candidats de transmission pour les trois
productions sont prepares en patchs et seront testes sans publication production.
Aucun test ne pretend qu'une VM Windows Server reproduit toutes les pages
Parametres de Windows 10/11, ni qu'un vrai McAfee a ete desinstalle.

La tentative de checkout croise de trois depots prives depuis la beta a echoue
avant compilation (Git 128 : repository not found). Aucun code applicatif n est
execute dans ces trois jobs. Les tests candidats utilisent desormais les runners
de chaque depot et le patch beta transmis comme parametre, avec publication
explicitement interdite. Aucun nouveau jeton GitHub n est demande.

Dashboard permanent publie en version 46 : en-tetes/causes de validation,
details repliees et fin de la reconstruction de mise en forme a chaque POST ;
attente de verrou ingestion ramenee de 30 s a 5 s. Source relue identique au
canonique, manifeste/configuration/autres fichiers preserves. La version 45 est
sauvegardee hors Git. Le probleme de delai et la mise en forme repetees sont
confirmes dans le code distant ; leur responsabilite exacte dans la photo du
poste ne peut pas etre prouvee sans son journal.

## Resultats finaux et portee

Les trois productions ont leurs sources Chrome/McAfee et leurs vrais EXE publies
apres reussite de la suite native et de quatre ouvertures/fermetures chacune.
Les empreintes des binaires LFS recuperes correspondent aux preuves des runners :
voir evidence/corrections-2026-10-20/three-production-releases.json.
ADDON garde son lanceur PS2EXE avec ressources actualisees et controlees, sa
version 2.0, Chrome seul, NVIDIA seul et aucun validateur/Adobe. LDLC et Numerik's
sont compiles nativement en 2.6.9. Le constructeur de carte mere reste beta seul.

Le renforcement client de transmission est aussi valide dans chaque production
comme candidat non publie : suite complete, 12 cas/35 assertions de transport,
quatre vrais lancements de chaque EXE candidat et trois echanges reels avec le
serveur 46. Les etats observes sont validated pour la fin normale, blocked pour
l'erreur 1603 et blocked pour l'arret. Nettoyage des seuls rapports CODEX-TEST
confirme. L'etape de publication est verifiee skipped dans les trois jobs :
voir evidence/corrections-2026-10-20/transmission-candidates-windows.json.
Les patchs sont dans beta/patches/transmission, egalement prepares localement dans
les trois autres checkouts. Ils ne sont pas commits/pushes dans leurs sources
applicatives. L'instruction /workspace/AGENTS.md n'autorise pour le moment en
production que Chrome/epinglage/AMD-portables et le retour McAfee ; une autorisation
explicite est encore requise pour publier ce renforcement client de transmission.

Tests reels : EXE/Preview, enfants PowerShell et dispatch du worker genere,
raccourcis COM en dossier isole, POST/GET dashboard et nettoyage propre, lecture
API du code Apps Script publie et page HTML live. Tests simules : effets des clics
Chrome/epinglage, inventaire/desinstallation antivirus, erreurs HTTP/interruption
et horloge. Aucun vrai McAfee/Norton ni pilote/BIOS/logiciel constructeur installe
ou desinstalle sur les runners. Windows Server 2025 ne valide pas un clic reel
dans les pages Parametres d'un poste Windows 10 ou 11 ; essai technicien requis.

Erreurs rencontrees puis resolues :
- Code 1 de la premiere suite LDLC/Numerik's : un test propre a la beta etait
  reference dans la suite de production. Liste restauree puis tests passes.
- Git 128/repository not found lors du checkout croise de depots prives : methode
  remplacee par des runs propres a chaque depot, sans jeton supplementaire.
- Trois timeouts GET a 45 s observes pendant le run de livraison Numerik's ; les
  reessais de lecture ont reussi. Aucun faux acquittement ni perte de rapport.
  Le meme run termine avec succes. Aucune promesse d'absence de panne reseau.
- La premiere relecture API apres publication Google etait transitoirement
  differente ; la relecture suivante confirme la version 46 et chaque fichier
  strictement identique au contenu prepare. Ni manifeste ni configuration changes.

Le code distant 45 confirme l'attente de verrou 30 s et la remise en forme de
Synthese a chaque POST. Le client ancien imposait 20 s meme si la configuration
prevoyait davantage. Ces defauts sont corriges respectivement sur le serveur 46
et dans les clients candidats. Ils expliquent un risque reel de non-acquittement ;
la cause exacte du message photographie reste impossible a etablir sans le journal
du poste. Ni validation forcee, ni disparition d'une erreur reelle.

Les jetons OAuth fournis sont utilises dans les processus cloud uniquement,
aucun n'est ajoute a Git ou aux jobs Windows. L'acces de modification Google est
confirme pour cette session ; le binding personnel de l'environnement n'est pas
encore enregistre. Les sauvegardes du code Google sont privees et hors Git.
