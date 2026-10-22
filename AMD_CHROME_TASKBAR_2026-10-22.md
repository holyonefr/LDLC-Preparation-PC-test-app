# Publication AMD et retour Chrome historique — 22 octobre 2026

Autorisation utilisateur : « Ok push sur les trois ». Les corrections et les EXE
seront publiés après les contrôles Windows. La bêta reste synchronisée ; son module
carte mère n’est pas transféré aux productions. Les modifications UI locales
préexistantes, logos, fonds, accueil Numerik’s et liens Google restent préservés.

## Chrome dans la barre des tâches

Retour à la méthode de `LDLC-Preparation` commit
`a2a57ee2d28203fded79802eae2a58883d996c7e` (parent de la nouvelle méthode) :
layout `LayoutModification.xml` avec `PinListPlacement="Append"` et application
Chrome, puis relance Explorer et fermeture des fenêtres ouvertes par cette relance.
Le corps historique est vérifié par fixture ; seules les vérifications de demande
d’arrêt sont ajoutées. Aucun contrôle de menu UIA ni délai de confirmation récent.

La réussite indique que le layout a été préparé, sans prétendre confirmer une
épingle réellement visible sur chaque version de Windows. Les vraies erreurs
(Chrome absent, écriture ou relance impossible) restent signalées. Aucun changement
aux associations Chrome par défaut ni aux autres réglages navigateur.

## AMD

LDLC et Numerik’s reprennent le parcours AMD testé dans la bêta 2.6.12 : découverte
actuelle AMD, package complet signé, compatibilité INF par GPU, versions de
l’application et des pilotes contrôlées. Repli Chocolatey après échec uniquement
pour le même package actuel, URL et SHA256 correspondants, sans rétrogradation.
Portables et format inconnu exclus avant le réseau. ADDON reste NVIDIA uniquement.

## Validation

Candidate en cours de validation Windows native : suite de régression, neuf scénarios
Chrome (XML réels isolés, processus Explorer simulés), quatre ouvertures du vrai EXE
et trois échanges réels avec le dashboard pour chaque édition. Pour les éditions AMD,
les 29 scénarios du repli, les autres tests GPU et un téléchargement officiel signé
sont également contrôlés. Aucun installateur matériel réel n’est exécuté sur la VM.
Installation AMD et épingle visible sur un poste client restent à vérifier.
