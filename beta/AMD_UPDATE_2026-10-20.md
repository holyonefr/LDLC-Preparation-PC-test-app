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
