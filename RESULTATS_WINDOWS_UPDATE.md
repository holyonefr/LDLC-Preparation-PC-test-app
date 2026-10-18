# Windows Update : déclenchement sans attente

All in App demande à Windows de rechercher, télécharger et installer les mises à jour en arrière-plan puis poursuit la préparation. Il ne vérifie ni leur achèvement ni leur nombre restant et ne les arrête plus à l’expiration d’un délai. Cela ne certifie pas que Windows Update a terminé : la finition reste à la charge du technicien.

Les tests couvrent lancement complet, lancement partiel, échec total, arrêt utilisateur et anciens réglages de délai. La fin de préparation est également testée avec une demande transmise mais des mises à jour non terminées : elle doit réussir si les autres étapes sont sans erreur. Un véritable échec de lancement ou une erreur Chrome restent bloquants et visibles.

Les neuf passages de tests Windows GitHub ont réussi : trois par application. Les commandes système et installations sont simulées ; ces tests ne remplacent pas une préparation complète sur un PC de boutique.

## Vérifications locales

- Ancienne version : 10 scénarios, 52 contrôles passés ; le scénario Windows Update non terminé donne `timeout`.
- Nouvelle version : 11 scénarios, 66 contrôles passés ; le même état de mises à jour n’empêche plus `success`. Le nouvel échec de lancement donne `failed`, avec « accès refusé » conservé.
- Les suites ciblées du déclencheur exécutent les vraies fonctions avec frontières système simulées : aucun COM, sommeil, lecture de résultat ou arrêt de processus autorisé.
- Ressources embarquées et code du lanceur préservés ; scripts principal et worker régénérés pour chaque édition.

## Passages Windows GitHub confirmés

Version testée : `070cf68`. [Exécution Windows](https://github.com/holyonefr/LDLC-Preparation/actions/runs/38959587495). Windows Server 2022, PowerShell 5.1.20348.5622.

| Passage | Résultat | Codes des phases | Durée des contrôles |
| --- | --- | --- | --- |
| 1 | Réussi | 0, 0, 0 | 68.4 s |
| 2 | Réussi | 0, 0, 0 | 68.7 s |
| 3 | Réussi | 0, 0, 0 | 51.8 s |

Codes lus dans les notices du runner, pour le commit indiqué ; aucun avertissement ni erreur dans les annotations de ces neuf passages. Toutes les 27 phases de contrôle des trois dépôts retournent zéro. Les cas négatifs attendus (ancien comportement, erreur 1603, interruption, lancement refusé) sont des simulations vérifiées par les suites, pas des installations en échec sur le runner.

La compilation PowerShell/C# native, la suite release et les comparaisons de finalisation passent à chaque passage. Le premier affichage et les diagnostics du lanceur sont couverts ; les associations navigateur et opérations de préparation restent simulées.
