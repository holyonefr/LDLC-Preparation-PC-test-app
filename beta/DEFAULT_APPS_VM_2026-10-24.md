# Bêta 2.6.18 — corrections après les essais réels Windows 11

## Constats de référence

L'essai bêta réel du 23 octobre (VM 40009424476, analyse 40066113436) a installé
les cinq logiciels. Le dashboard contient une seule exécution, sans erreur mais
avec deux avertissements : PDF encore sur Edge, fichiers HTML encore sur Edge.
HTTP/HTTPS sont bien sur Chrome. Ce sont des réglages incomplets, pas un échec
d'installation des applications. Leur cause est confirmée par le journal filtré
de cette VM, sans modifier ni effacer ses événements historiques.

## Corrections

- Le contrôle PDF était masqué par une autre fenêtre : le refus du clic physique
  court-circuitait aussi Invoke. Le script conserve le refus du clic et active
  le contrôle exact par son pattern UIA. Un choix accessible utilise d'abord
  SelectionItem quand le clic physique est indisponible.
- Une confirmation HTTP tardive interrompait la boucle entière : les autres
  associations sont désormais tentées séparément, puis relues. Budget Chrome
  par association de 4 s, avec une dernière stabilisation de 1 s si nécessaire.
- Les alias d'un même bouton navigateur sont dédupliqués par identité UIA ;
  deux boutons différents restent ambigus et ne sont jamais choisis au hasard.
- Les tentatives restent informatives. Le contrôle final ne conserve aucune
  alerte si Windows confirme réellement le réglage ; aucun compteur n'est vidé.
  Une erreur réelle, un refus persistant ou une interruption reste signalé.
- Le contrôle final a sa propre rubrique, au lieu d'attribuer un défaut PDF
  au rétablissement de la veille.

La bêta n'utilise pas le bootstrap Chocolatey de TeamViewer de l'ADDON : aucun
avertissement correspondant n'est présent ici. Les trois productions, leur UI
locale, les fonctions constructeur/AMD et le serveur Apps Script ne sont pas
modifiés. Widgets reste informatif conformément à la demande précédente.

## Vérifications

Tests ciblés locaux réussis : nouveau test des échecs VM (10 assertions), Chrome
(10 scénarios / 28 assertions), bouton navigateur (47 contrôles), affichage
(14 assertions), contrôle final (41 assertions), parcours PDF existant.
Ces tests simulent les effets Windows, sans configurer les associations du poste.
La comparaison historique reproduit l'abandon HTML et le clic PDF masqué.

La [validation Windows native 40066568005](https://github.com/holyonefr/LDLC-Preparation-PC-test-app/actions/runs/40066568005) a réussi sous PowerShell 5.1 et 7 :
comparaison historique (2 assertions reproduisant les deux blocages), nouveau
contrôle (10 assertions), suite release complète et quatre vrais Preview/fermetures
à 1,341 / 1,163 / 1,207 / 1,161 s après EntryPoint, hors UAC. Aucun installateur
matériel n'est exécuté et aucun scénario simulé n'est envoyé au dashboard.

Source testée : `81dfa82bfb79f2efe83459147df6013dc1c7e8aa`. Livraison EXE :
`f554e3141f7486f3129001c6084a6f411ed693be`, SHA-256 récupéré et vérifié :
`4A87BC25654E4C406CF009C653272C7154662149AD95FE44CA079B18F52E5FA8`.
[Preuves natives](evidence/default-apps-vm-2026-10-24/native-validation.json).

Le premier run 40066422541 s'est arrêté dans la fixture isolée de clôture : elle
ne fournissait pas encore la nouvelle rubrique finale. Fixture corrigée et
assertion de rubrique ajoutée, puis validation complète ci-dessus réussie.
Ce premier essai n'a publié aucun EXE et n'a exécuté aucune préparation réelle.

Le [nouvel essai Windows 11 40066857427](https://github.com/holyonefr/VM/actions/runs/40066857427)
a été lancé sur une VM neuve avec l'EXE exact ci-dessus, capsule privée
`e8dfa908e0ad738fc72ba7c1097f2f1a73edbb98`. Il est **réussi**, ainsi que son
[analyse indépendante 40069824774](https://github.com/holyonefr/VM/actions/runs/40069824774).

## Résultat réel Windows 11

VM neuve Windows 11 Entreprise évaluation française, build **26300**, ProductType
**1**. Poste `VM-LDLC-BE357A`, intervention
`VM-LAB-LDLC-7f4caefc34f545e28e3915e79bbe357a`, du 24 octobre à 06:05:37 UTC
à 06:18:58 UTC. Le dashboard affiche **13 min 23 s**.

- Les cinq logiciels sont absents avant et installés après : Chrome
  156.0.8078.48, LibreOffice 26.8.1.1, Adobe Reader 26.001.21691, 7-Zip
  26.05.00.0 et VLC 3.0.23.
- Lecture indépendante des API Windows après préparation : HTTP, HTTPS, `.htm`
  et `.html` → `ChromeHTML` / `chrome.exe` ; `.pdf` → `Acrobat.Document.DC` /
  `Acrobat.exe`. **Adobe est réellement l'application PDF par défaut.**
- Fin normale, vrai clic observé sur Quitter, sortie **0**, aucune erreur du
  contrôleur ni collecte manquante.
- Dashboard réel : **« Validé »**, validation `validated`, **0 erreur / 0
  avertissement**, une ligne visible et une seule ligne physique dans Sheets.
  Identité, version et horaires correspondent au test.

| Contrôle réel | Bêta 2.6.17 du 23 octobre | Bêta 2.6.18 du 24 octobre |
| --- | --- | --- |
| PDF | Edge | Adobe Acrobat |
| HTTP / HTTPS | Chrome | Chrome |
| HTM / HTML | Edge | Chrome |
| Erreurs / avertissements | 0 / 2 | **0 / 0** |
| Libellé du dashboard | À vérifier | **Validé** |

Le bouton navigateur global n'a pas été activable dans cette VM ; le parcours
Windows par association a réussi. Cette tentative intermédiaire reste dans le
journal informatif, sans alerte finale périmée. L'extrait de journal des preuves
est explicitement tronqué ; le diagnostic final et les cinq associations sont
complets. Aucun avertissement réel n'a été effacé du compteur.

[Preuves structurées du test réel](evidence/default-apps-vm-2026-10-24/windows11-result.json).
Les comparaisons unitaires et les vrais Preview sur Server restent distincts de
cette préparation complète sur client Windows 11. GPU physique et épingle visible
ne sont pas qualifiés par cet essai. Les trois productions et leurs modifications
UI locales sont inchangées ; aucun déploiement Apps Script ni historique modifié.
