# AMD Adrenalin — bêta 2.6.11 publiée le 20 octobre 2026

La correction et l’EXE sont publiés **uniquement** dans `LDLC-Preparation-PC-test-app`.
Campagne Windows finale : [run 39489152311](https://github.com/holyonefr/LDLC-Preparation-PC-test-app/actions/runs/39489152311), entièrement réussie.
Source testée : `8ff91324c2b5fde0b3316c0417033e2b3036516c`. Livraison : `39dadd61bc459dcf41503ce184a87bd790416d1e`.
L’EXE récupéré depuis GitHub correspond à l’empreinte attestée par le runner :
`0D7D4C4E5923D46C29E3D381D18B92B3B0FC74B9C589062574B0E44A8FD75CE4`.

## Défaut et correction

Sur la référence `f722c26`, une ancienne application et un ancien pilote pouvaient
être confirmés après un installateur sans effet. Le même scénario est maintenant
refusé. Le modèle et les journaux du PC signalé n’ont pas été fournis : la cause
unique de l’échec sur ce poste reste non prouvée.

Le parcours actif est dans `modules/60.Gpu.ps1` : `Install-LDLCAmdStack` découvre
la version actuelle sur AMD, résout sa note officielle et télécharge son package
complet. L’Auto-Detect sert à la découverte de version ; l’installation utilise
le package complet. Aucun ancien cache n’est utilisé comme dernière version.

La signature AMD et le format PE sont vérifiés. Les INF sont extraits avec 7-Zip,
déjà prévu dans la phase applications. Chaque GPU doit être compatible et atteindre
la cible de son INF x64 correspondant à Windows. La version de l’application est
contrôlée séparément : numéro marketing Adrenalin, version de son exécutable et
version Windows du pilote ne sont pas comparés entre échelles différentes.
Une installation partielle, sans effet ou incompatible n’est pas annoncée comme
réussie. Les versions supérieures déjà présentes ne sont pas rétrogradées.
Un redémarrage requis garde un résultat non confirmé tant que les cibles manquent.

Les portables et formats inconnus sont exclus avant toute requête AMD. NVIDIA,
les interfaces, le dashboard et les trois productions restent inchangés. Le module
carte mère reste exclusivement dans la bêta. Les 16 fonctions NVIDIA/format du PC
comparées à la référence sont identiques.

## Sources réellement vérifiées sur Windows

| Source | Version observée | Résultat |
| --- | --- | --- |
| AMD officiel | 26.10.1 | Package complet téléchargé, signature valide, INF lus |
| Chocolatey, préversions incluses | 26.8.1 | En retard sur AMD ; non utilisé pour installer la dernière version |
| Guru3D, page fournie | Non vérifiée | HTTP 403 Forbidden depuis le runner ; aucun fichier téléchargé |

Package officiel retenu : [whql-amd-software-adrenalin-edition-26.10.1-win11-c.exe](https://drivers.amd.com/drivers/whql-amd-software-adrenalin-edition-26.10.1-win11-c.exe).
Résolution : page AMD actuelle → note officielle dérivée de sa version → lien complet.
Aucun numéro ni lien d’installateur n’est fixé dans le parcours de production.
Taille : 1,782,243,424 octets. Signature : `Valid`, éditeur AMD.
SHA-256 : `EAF0B61DE6CE31793D05222FD57B50C6A55095F52796A33683093381F9345B82`.
Deux INF DISPLAY ont été lus. Les identifiants matériels d’exemple donnent notamment
la version pilote `32.0.32015.7029` ; la cible réelle dépend du GPU, pas de ce numéro
fixé dans les tests. Les identifiants complets SUBSYS/REV sont préservés.

Le catalogue Chocolatey a été interrogé réellement avec Chocolatey 2.7.4, puis son
nupkg a été lu sans exécution du script. Son URL vise le site AMD officiel, son script utilise `-install` et une somme SHA-256,
mais son URL vise 26.8.1. Cette lecture ne prouve pas une installation réelle.
Pour un paquet déjà présent, `choco upgrade` serait nécessaire plutôt qu’un simple
`choco install` ; cela ne résout pas le retard du catalogue.

## Résultats et limites

- Suite native : **46 scripts PowerShell, 3 suites JavaScript**, diagnostics du vrai
  lanceur et intégration bêta. Les contrôles non destructifs de la carte mère passent.
- Comparaison native avant/après : **14 scénarios**, 32 assertions avant et 43 après.
  Sept résultats changent : ancien état inchangé, mises à jour partielles, mauvais
  GPU, redémarrage non confirmé et risques de rétrogradation sont désormais refusés
  ou signalés correctement. Les cas source indisponible, téléchargement interrompu,
  signature incorrecte, erreur 1603 et exclusion portable restent couverts.
- Métadonnées : 31 assertions ; flux AMD : 125 assertions ; exclusion portable :
  17 scénarios sans réseau AMD ; routage GPU : 15 scénarios.
- **Quatre ouvertures/fermetures du véritable EXE** en Preview, sans installation.
  Les quatre fenêtres sont visibles et le bouton Quitter reste entier.
- Trois échanges réels avec le dashboard : fin normale `validated`, erreur 1603 et
  arrêt `blocked`. Les seuls rapports de test créés ont été supprimés.
- Téléchargement, signature et lecture des INF sont réels. Les installations
  matérielles, les actions UI et les réponses système des scénarios sont simulées.
  **Aucun installateur AMD n’a été exécuté sur les VM. L’installation physique sur
  le GPU du client reste à confirmer.** Windows 10 est couvert par des fixtures de
  sélection INF, pas par une installation réelle sur Windows 10.

Si aucun INF actuel ne prend en charge un GPU ancien, si 7-Zip manque ou si la
version de l’application ne peut pas être prouvée, le script explique le blocage
et ne force pas une installation incompatible ni un faux succès.

Les premières campagnes ont identifié des défauts de tests corrigés avant livraison :
progression HTTP PowerShell trop coûteuse sur le gros fichier (premier job arrêté
à 15 minutes), échantillon PCI tronqué, PSScriptRoot vide dans une valeur par défaut
avancée sous PowerShell 5.1 avec `-File`, et historique absent d’un checkout superficiel.
Le workflow récupère l’ancienne référence explicitement et conserve ses octets/BOM
avec `git archive`. Aucun échec n’a été converti en validation de livraison.

Les domaines AMD et Guru3D ont été ajoutés au brouillon de configuration cloud,
en conservant les destinations existantes. Le brouillon n’a pas été appliqué à
l’environnement local ; les vérifications réseau annoncées sont celles des runners.
Les preuves détaillées sont dans `beta/evidence/amd-update-2026-10-20/`.
