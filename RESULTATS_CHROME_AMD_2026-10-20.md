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
vrai EXE avant publication. Résultats natifs : en cours.

Les vrais appels Windows d'associations utilisent une extension/ProgID temporaire
isolée. La relecture des vrais fichiers .lnk COM est contrôlée dans un dossier privé.
Ces contrôles ne changent ni les navigateurs par défaut ni les épingles du compte.
Les clics réels dans Paramètres et l'épingle visible sur un PC Windows 11 physique
restent à vérifier sur le poste du technicien ; les simulations ne les prouvent pas.
Le workflow reste manuel, aucune télémétrie de test ni déploiement Google.
