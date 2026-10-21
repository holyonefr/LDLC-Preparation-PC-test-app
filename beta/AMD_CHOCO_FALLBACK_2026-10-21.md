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

## Validation Windows terminée

[Campagne finale 39552519014](https://github.com/holyonefr/LDLC-Preparation-PC-test-app/actions/runs/39552519014) entièrement réussie, sous Windows 2025
et PowerShell 5.1. Source `731013aa2a0c7e53982e2ccba411ec23c8c20ad9` ; livraison `1fcc6eb6b3a5c293d3cc4e360d00e51e3b2d3664`.
L’EXE publié puis récupéré correspond à l’empreinte du runner :
`0679A886F29F21DC8E73A9C3D585C20380CBE7D08B1B8ADD15E001CCDA6388DB`.

- **Simulations natives** : 29 scénarios / 162 assertions,
  sans installateur matériel. Échec officiel puis succès Chocolatey, absence d’effet,
  erreur 1603, paquet périmé (99.9.1 contre 99.10.1), URL/empreinte/arguments refusés,
  ZIP corrompu/interrompu, annulation, délai, redémarrage, portable, aucun AMD,
  absence de Chocolatey et version installée supérieure. Les ZIP/PE/INF, empreintes
  et nettoyages sont réels et isolés ; HTTP, matériel, signatures et installation
  sont simulés. 14 scénarios AMD avant/après également vérifiés.
- **Suite complète** : 47 tests PowerShell, trois suites JavaScript et diagnostics
  du lanceur compilé réussis ; intégration carte mère et synchronisation préservées.
- **Réseau réel** : package AMD complet 26.10.1 téléchargé
  (1 782 243 424 octets), signature `Valid`, INF DISPLAY lus.
  URL retenue : https://drivers.amd.com/drivers/whql-amd-software-adrenalin-edition-26.10.1-win11-c.exe.
- **Chocolatey réel, sans installation** : catalogue et nupkg inspectés avec le
  parseur utilisé à l’exécution. Dernière version stable 26.10.1 ;
  version officielle AMD 26.10.1. Le nupkg de la version
  officielle est disponible : **oui**
  (HTTP 200). Le lien et le SHA256 du nupkg correspondent exactement au package AMD signé
  réellement téléchargé. Le repli dispose donc maintenant de la version actuelle.
  Une ancienne version reste refusée si le catalogue prend du retard à l’avenir.
- **Application réelle** : quatre ouvertures/fermetures du nouvel EXE en mode
  Preview ; trois échanges acquittés par le dashboard (succès validé, erreur et
  interruption bloquées), puis nettoyage de ces rapports de test.

Premier passage 39552312665 arrêté sans publier d’EXE : la fixture ZIP oubliait
le chargement explicite de `System.IO.Compression` requis sous PowerShell 5.1.
Après correction, tous les contrôles du passage final passent. Preuves JSON dans
`beta/evidence/amd-choco-fallback-2026-10-21/`.

**Limite réelle** : aucun `choco upgrade` AMD ni pilote matériel n’est exécuté sur
GitHub ; l’installation Chocolatey est simulée. Le téléchargement du nupkg, sa lecture
et sa correspondance avec le fichier AMD signé actuel sont réellement vérifiés.
L’installation sur un vrai PC AMD et son résultat matériel restent à confirmer. Les quatre marques de cartes mères n’ont pas été
retéléchargées dans cette campagne AMD ; leurs tests de régression passent.
Les trois productions et leurs modifications UI locales restent inchangées.
