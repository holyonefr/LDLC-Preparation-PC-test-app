# Chrome par défaut et barre des tâches — 20 octobre 2026

Publication des corrections autorisée sur les trois éditions par l'utilisateur.
La fonctionnalité carte mère reste exclusivement dans la bêta.

- Bouton navigateur global « Définir par défaut » tenté avant le sélecteur HTML.
  Une activation UIA sans effet peut être suivie d'un clic observé protégé ; aucun
  clic à coordonnées fixes ou sans confirmation de l'interface compacte.
- Vérification des associations effectives Windows par API native, repli COM et
  résolution de l'exécutable du ProgID réel. Deux lectures successives conservées.
  Chrome déjà prêt évite l'ouverture des paramètres. Confirmation Chrome bornée
  à 6 s par tentative ; contrôles finaux courts, sans doubles attentes de 12 s.
  Le temps propre au chargement des Paramètres Windows peut s'ajouter.
- Plus d'avertissement provisoire restant lorsque l'état final est confirmé.
  Un véritable défaut d'association reste signalé et ne devient pas un succès.
- Épinglage Chrome par commande Windows exposée, puis menu de l'exécutable exact
  si nécessaire. Résultat vérifié ; le simple XML et le redémarrage global
  d'Explorer sont supprimés de cette étape. Refus de Windows signalé précisément.
- LDLC/Numerik's : AMD Adrenalin ignoré sur portable/tablette avant tout réseau,
  installation ou raccourci ; identification SMBIOS. Format inconnu ignoré avec
  diagnostic. NVIDIA inchangé, y compris sur portable hybride.
- Addon : Chrome seul, NVIDIA seulement, aucune étape Adobe ou AMD ajoutée.

Les identités visuelles de chaque édition sont conservées. Les modifications UI
locales antérieures non publiées ne sont pas incluses dans cette livraison.
Le cœur LDLC/Numerik's est synchronisé via son manifeste (version 2.6.6).
Le helper de synchronisation accepte aussi les séparateurs de chemins de l'hôte
cloud ; ses contrôles de traversals/jonctions et des fichiers protégés restent actifs.

## Vérification

Les scénarios ciblés réussissent localement. Le comportement des clics et des GPU
est simulé : aucune installation matérielle n'est exécutée. La campagne Windows
manuelle compile LDLC/Numerik's, réassemble les ressources PowerShell du lanceur
Addon existant, vérifie les suites complètes, puis ouvre/ferme quatre fois chaque
vrai EXE avant publication. Résultats natifs : réussis, tableau ci-dessous.

Les vrais appels Windows d'associations utilisent une extension/ProgID temporaire
isolée. La relecture des vrais fichiers .lnk COM est contrôlée dans un dossier privé.
Ces contrôles ne changent ni les navigateurs par défaut ni les épingles du compte.
Les clics réels dans Paramètres et l'épingle visible sur un PC Windows 11 physique
restent à vérifier sur le poste du technicien ; les simulations ne les prouvent pas.
Le workflow reste manuel, aucune télémétrie de test ni déploiement Google.

## Résultats Windows vérifiés

| Édition | Run Windows réussi | Source testée | Livraison EXE | Ouvertures / échecs UI |
|---|---|---|---|---|
| LDLC-Preparation | [`39407672991`](https://github.com/holyonefr/LDLC-Preparation/actions/runs/39407672991) | `32034cc` | `711989f` | 4 / 0 |
| Numerik-s-Preparation-PC | [`39407677065`](https://github.com/holyonefr/Numerik-s-Preparation-PC/actions/runs/39407677065) | `ff58deb` | `59b519c` | 4 / 0 |
| LDLC-Preparation-Addon | [`39408146830`](https://github.com/holyonefr/LDLC-Preparation-Addon/actions/runs/39408146830) | `72c92e6` | `ebb0892` | 4 / 0 |

- LDLC-Preparation SHA256 : `C3C63CB0F17AD84111BF02294D3272727F4F5A5DFB61786CFC3B800526E13068`.
- Numerik-s-Preparation-PC SHA256 : `CA700563C995A256F1AF85F62F009623C8BF5BF9CE021308434D516798D68A3E`.
- LDLC-Preparation-Addon SHA256 : `2346700DD7BEABD84F9263B179A8C42F732CAE48BB6BD508FE013907BDC0B33A`.

Les suites release complètes ont réussi ; les empreintes des EXE récupérés depuis
GitHub correspondent aux annotations du runner. Les trois fichiers ci-dessus sont
les livraisons réellement testées, pas des EXE anciens accompagnant un nouveau script.
Preuves structurées : [evidence/chrome-amd-2026-10-20/windows-evidence.json](evidence/chrome-amd-2026-10-20/windows-evidence.json).

Chrome rapide : 9 scénarios / 27 assertions sur chaque édition ; bouton navigateur :
47 contrôles sur LDLC/Numerik's et dans chacun des deux arbres Addon. Épinglage :
10 scénarios / 22 assertions dont deux raccourcis COM réels isolés. API natives
d'associations : 3 assertions réelles sur fixture isolée. AMD portable : 17 scénarios
/ 17 assertions sur LDLC/Numerik's, aucun réseau/installeur AMD sur portable simulé.
Les interactions Settings/menus et l'identité matérielle restent simulées.

Premier run Addon 39407680610 : suite et quatre Preview réussis, publication en
échec, donc aucun EXE publié par cet essai. Logs détaillés indisponibles depuis le
cloud (HTTP 403). Sorties générées normalisées en LF et cause de publication désormais
annotée ; relance complète 39408146830 réussie, y compris publication. Aucun contrôle
d'intégrité n'a été supprimé. Les fichiers UI locaux antérieurs sont restés hors
des commits et des builds GitHub. La bêta est aussi reconstruite/testée séparément
en 2.6.6, en conservant son module carte mère exclusif.
