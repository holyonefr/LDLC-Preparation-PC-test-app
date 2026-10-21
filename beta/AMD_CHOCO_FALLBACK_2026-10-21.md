# Repli Chocolatey AMD — bêta 2.6.12

Publication uniquement dans `holyonefr/LDLC-Preparation-PC-test-app`.
Les productions, leurs modifications UI locales et les différences de la bêta sont préservées.

## Comportement

- Après un échec de l’installateur AMD officiel ou une absence de mise à jour effective,
  essayer Chocolatey pour la **même version actuelle vérifiée**. Utiliser `upgrade` avec
  une version précise et `--force` pour retenter une installation déjà enregistrée.
- Inspecter le nupkg sans exécuter son script. Son URL AMD, SHA256 et argument
  `-install` doivent correspondre au package complet dont la signature et les INF
  compatibles avec chaque GPU viennent d’être vérifiés. Lancer le nupkg inspecté
  depuis un dépôt local temporaire, conserver les vérifications de sommes et ignorer
  les dépendances facultatives. Ne jamais demander `--allow-downgrade`.
- Attendre les processus AMD descendants de Chocolatey ; vérifier ensuite les
  versions de l’application et des pilotes, puis seulement confirmer la réussite.
- Pas de seconde installation tant que la première est active ou demande un
  redémarrage. Quitter reste prioritaire. Recontrôler l’absence de version installée
  plus récente avant la seconde tentative.
- Si le package actuel n’est pas publié sur Chocolatey, afficher précisément son
  indisponibilité. Ne jamais remplacer par une ancienne version ni annoncer un succès.
- Si la source AMD ne permet pas de vérifier la version actuelle, le fichier signé
  et sa compatibilité, ne pas lancer Chocolatey à l’aveugle. Ce repli ne résout pas
  une panne du même CDN AMD auquel le package Chocolatey renvoie.
- Portables et format inconnu exclus avant le réseau. Parcours NVIDIA inchangé.

## Validation

En attente du résultat final du workflow Windows. Les essais locaux portent sur
29 scénarios simulés, ZIP/PE/INF et SHA256 réels isolés. Aucun pilote matériel réel
n’est exécuté sur une VM ; l’installation sur un PC AMD physique reste à confirmer.
