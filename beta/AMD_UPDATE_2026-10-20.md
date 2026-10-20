# AMD Adrenalin — correction en cours de validation, bêta 2.6.11

Le parcours précédent téléchargeait l’Auto-Detect actuel, mais son contrôle final
acceptait un Adrenalin ancien et un pilote ancien dès lors qu’ils étaient présents,
signés et sains. Un code retour 0 sans aucune mise à jour pouvait donc être annoncé
comme confirmé. Les mêmes scénarios sur la référence `f722c26` reproduisent ce défaut.
Sans le modèle et les journaux du PC signalé, cela ne prouve pas la cause unique
sur ce poste.

Le nouveau parcours découvre la version actuelle sur AMD, dérive sa note officielle,
télécharge un package complet de cette version et vérifie son format et sa signature.
Le contenu INF est extrait avec 7-Zip (déjà installé pendant la phase applications),
sans exécuter l’installateur. Chaque GPU doit être compatible et ses versions cibles
sont tirées des INF x64 correspondant à la version de Windows. Aucun ancien cache
ni ancien package n’est choisi si la découverte actuelle échoue.

Le package complet remplace le bootstrap web pour l’installation automatique.
Après la commande d’installation et ses sous-processus, le contrôle exige les
versions pilotes attendues et une preuve de version de l’application. Les numéros
marketing Adrenalin, les versions de ses exécutables et les numéros Windows du
pilote ne sont jamais comparés entre échelles différentes. Une installation partielle
ou sans effet est refusée, avec cause claire. Une version supérieure déjà installée
n’est pas rétrogradée. Un redémarrage requis n’est pas annoncé comme une réussite
si les versions restent non confirmées.

Les PC portables et les formats inconnus conservent leur exclusion avant tout réseau.
NVIDIA et le module carte mère restent inchangés. Publication limitée à la bêta.

Limites : si la version actuelle générale ne contient aucun pilote compatible avec
un GPU ancien, le script signale ce cas et ne force pas un mauvais package. Il ne
prétend pas avoir trouvé le dernier canal legacy propre à ce GPU. Un 7-Zip absent,
un INF non lisible ou une version Adrenalin non vérifiable est un blocage expliqué.
Les tests matériels réels ne sont pas exécutés sur une VM GitHub.

Premier essai Windows réel de la découverte précédente : run `39457868461`, réussi.
Auto-Detect détecté : **26.10.1**, 47 859 040 octets, signature AMD valide.
Cela confirme que le lien et le téléchargement du bootstrap fonctionnent sur ce
runner ; cela ne prouve pas son installation sur le PC signalé.

Les résultats du package complet, de la comparaison avant/après et de la suite
native seront ajoutés après leur exécution. Aucun EXE 2.6.11 n’est publié avant
réussite de ces vérifications.

## Vérification de la proposition Chocolatey

Tests réels Windows des runs `39460474378` et `39460667608` : Chocolatey 2.7.4,
recherche de toutes les versions, préversions incluses. Le dernier paquet publié
`amd-software-adrenalin-edition` est **26.8.1**, son URL AMD vise bien ce numéro,
avec somme SHA-256 et argument `-install`. La source officielle propose **26.10.1**.
Ce paquet n’est donc pas utilisé pour satisfaire une demande de dernière version.
`choco install` ne garantit pas non plus l’actualisation d’un paquet déjà présent ;
il faudrait `choco upgrade`, puis toujours vérifier version et compatibilité.
Aucun script Chocolatey d’installation matérielle n’a été exécuté sur le runner.

Premier téléchargement du package complet : version et URL 26.10.1 résolues,
mais job arrêté à 15 minutes pendant le téléchargement. Aucun succès déclaré.
La progression HTTP native PowerShell est désormais supprimée localement pour
éviter son coût sur les gros fichiers ; la progression de l’application est conservée.
Un nouvel essai réel est requis avant publication de l’EXE.

## Résultats complémentaires — source officielle et Guru3D

Run `39487792508` : le package complet officiel 26.10.1 a été téléchargé et vérifié,
1 782 243 424 octets, signature AMD valide, SHA-256
`EAF0B61DE6CE31793D05222FD57B50C6A55095F52796A33683093381F9345B82`.
Deux INF DISPLAY détectés ; plusieurs identifiants PCI complets donnent une cible
`32.0.32015.7029`. Aucun installateur matériel n’a été exécuté.
Le premier échantillonnage de test tronquait les attributs SUBSYS/REV des identifiants
PCI ; le test utilise maintenant les identifiants complets. Le filtre Include de
Get-ChildItem avec LiteralPath est remplacé pour PowerShell 5.1 afin de borner
correctement le rapport aux exécutables UI.

Le même passage identifie un défaut du nouveau test en processus enfant : le chemin
PSScriptRoot utilisé dans la valeur par défaut d’un paramètre avancé est vide sous
Windows PowerShell 5.1 avec -File. Son calcul est déplacé dans le corps du test.
Cette erreur empêchait la suite de terminer, sans prouver un défaut d’installation.

La page Guru3D fournie par l’utilisateur a été demandée réellement sur ce runner :
HTTP **403 Forbidden**, aucun fichier Guru3D téléchargé. Elle n’est pas retenue
comme repli automatique non testé. La source officielle complète fonctionne.
La sonde Guru3D reste disponible à la demande, indépendante des validations requises.

La suite du run `39488236462` passe les régressions complètes et le téléchargement
réel signé avec lecture des INF. La comparaison historique s’arrête ensuite car
le checkout GitHub est superficiel et n’avait pas récupéré le commit de référence.
Le workflow récupère désormais explicitement cette référence et extrait les octets
originaux avec git archive, sans réencodage du BOM par PowerShell 5.1.
La livraison reste bloquée jusqu’au passage complet de la campagne suivante.
