# Chrome sans attente et désinstallateurs McAfee/Norton — 20 octobre 2026

Cette correction remplace les attentes de confirmation introduites auparavant.
Publication sur LDLC, Numerik's et Addon ; bêta synchronisée, module carte mère
exclusivement dans la bêta. Interfaces et anciens travaux UI locaux conservés.

## Comportement demandé

- Chrome : clic sur le bouton navigateur « Définir par défaut », puis poursuite.
  Aucun polling ni contrôle final bloquant des associations Chrome. Une lecture
  initiale immédiate peut éviter une action inutile quand Chrome est déjà choisi.
  Le repli HTML transmet aussi le bouton sans attendre la confirmation du registre.
  Le clic physique garde les protections de focus, contrôle exact et ACK de rendu.
- Épinglage : commande Windows envoyée, sans attente de confirmation de l'épingle.
  Le journal annonce une commande transmise, jamais un résultat vérifié non mesuré.
  L'absence de Chrome, de commande accessible ou un clic impossible reste signalé.
- Adobe : parcours existant conservé dans LDLC/Numerik's ; absent de l'Addon.
  Les erreurs d'installation et de préparation restent bloquantes. Supprimer la
  confirmation Chrome ne force pas la validation d'une intervention en erreur.
- McAfee/Norton : ouverture directe de leur `UninstallString` enregistrée, fenêtre
  normale, sans ajouter de switches silencieux ; MSI /I devient /X sans /qn.
  Les paramètres silencieux standards sont retirés, les arguments du constructeur
  et leurs guillemets conservés. Aucun panneau « Applications installées ».
- La préparation attend le retrait avant les installations. Aucun plafond de
  90 s dans ce parcours, aucune mise à mort du désinstallateur. Un parent terminé
  n'est pas une preuve de retrait : un enfant peut encore afficher son interface.
  À l'inverse, une entrée disparue ne suffit pas si le parent travaille encore.
  Quitter reste disponible. Refus, annulation explicite, redémarrage nécessaire ou
  désinstallateur absent arrêtent avec leur cause ; aucune fausse suppression.
- L'Addon effectue cette étape dès le début ; son nettoyage OEM ultérieur exclut
  les antivirus. Aucun ajout AMD, Adobe ou validateur dans cette édition.

L'historique consulté (`c80a6ae` et ses prédécesseurs) avait rétabli les tentatives
silencieuses avec repli téléchargé. Le parcours normal appelait ensuite un worker
caché tué après 90 s. La correction rétablit le comportement visible demandé,
sans rétablir le repli vers les paramètres Windows ni les changements sans rapport.
Le helper d'isolation historique reste disponible pour les diagnostics explicites,
mais n'est plus appelé par la préparation normale.

## Vérifications

Les tests locaux passent pour le flux Chrome sans attente, les vrais échecs de
commande, le clic protégé, la barre des tâches, les refus/annulations antivirus,
le retrait tardif après 95 s simulées et la fin de workflow. Deux cas supplémentaires
vérifient qu'un refus antivirus ou Quitter empêchent toute installation et toute
fausse preuve de fin. Le test Chrome contre le module précédent échoue comme attendu.

Les suites Windows doivent compiler/réassembler chaque édition, exécuter les
régressions et quatre vrais Preview/fermetures avant publication. Le test antivirus
Windows utilise un EXE factice compilé qui ouvre une vraie fenêtre temporaire puis
se ferme : aucune désinstallation McAfee/Norton réelle, aucune modification du
registre. La détection et le retrait sont simulés. Résultats Windows : réussis, voir ci-dessous.

## Résultats Windows

| Édition | Run réussi | Source testée | Livraison EXE | Preview / échecs |
|---|---|---|---|---|
| LDLC-Preparation | [39412857978](https://github.com/holyonefr/LDLC-Preparation/actions/runs/39412857978) | `c741bd3` | `392b3f9` | 4 / 0 |
| Numerik-s-Preparation-PC | [39412861967](https://github.com/holyonefr/Numerik-s-Preparation-PC/actions/runs/39412861967) | `f59e72a` | `d8409cb` | 4 / 0 |
| LDLC-Preparation-Addon | [39412866385](https://github.com/holyonefr/LDLC-Preparation-Addon/actions/runs/39412866385) | `01fd6a1` | `71baf73` | 4 / 0 |

- LDLC-Preparation SHA256 : `38C4B7095AAEF635B498E950C83B93A66A081E07E5B7AA61C57245786B2DC268`.
- Numerik-s-Preparation-PC SHA256 : `63979E7D9DCEF94431E632B0CB3A60BBFC5276A4366D02C2E2535BC2D0360356`.
- LDLC-Preparation-Addon SHA256 : `61C3B098E4DC64680C7B4F0CB03BDE6E46C4F03CB939408DA1BB11EBAC6FC030`.

Suites complètes réussies et EXE récupérés depuis GitHub, empreintes vérifiées.
Chrome sans confirmation : 10 scénarios / 25 assertions ; scénario déjà prêt
à 250 ms d'horloge simulée, pas une mesure de clic Windows. Antivirus : 17 scénarios
/ 18 assertions par arbre sous Windows (deux arbres Addon), dont une vraie fenêtre
factice compilée, affichée et fermée. Attente longue de 95 s simulées, parent terminé
avant retrait, registre disparu avant la sortie du parent, chemins avec espaces,
MSI, commande absente, refus 1602/1603, redémarrage 3010, arrêt avant/pendant attente.
Deux scénarios de fin supplémentaires prouvent qu'un refus ou Quitter à cette étape
empêche les installations suivantes et ne valide pas une intervention incomplète.

Aucun McAfee/Norton réel désinstallé sur runner ; détection/retrait simulés. Les
clics Chrome et les menus restent simulés, avec vérifications natives API/COM isolées
conservées. Aucun installateur matériel exécuté, aucun envoi de télémétrie ni
déploiement Google. L'échec attendu du test Chrome sur le module précédent est
conservé dans la preuve bêta. La vérification locale initiale des payloads carte
mère bêta a détecté les scripts générés Windows anciens (empreintes CRLF/LF) :
régénération avant test, 12 scénarios / 29 assertions réussis, puis build Windows
complet ; aucun contrôle d'empreinte n'a été affaibli.

Preuves : [evidence/no-confirm-security-2026-10-20/windows-evidence.json](evidence/no-confirm-security-2026-10-20/windows-evidence.json).
