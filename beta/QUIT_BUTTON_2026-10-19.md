# Bouton Quitter — 19 octobre 2026

Retour utilisateur : le bas du libellé est coupé. Le contrôle précédent mesurait
le texte brut contre la taille du bouton, sans tenir compte de l'espace nécessaire
au rendu natif du contrôle. Le bouton pouvait mesurer seulement 14 pixels de haut.

Correction : AutoSize/GrowOnly, taille native préférée, minimum 24 pixels de haut,
marges internes explicites, libellé centré et ancrage en bas à droite. La police
lisible est conservée au lieu de la réduire jusqu'à 5,5 points. Marge extérieure
préservée pour rester à l'intérieur du bord arrondi. Gestion du clic/arrêt inchangée.

Publication : bêta uniquement. Même adaptation préparée localement dans LDLC et
les deux arbres Addon ; Numerik's reste inchangé. La bêta garde les modifications
précédentes (textes agrandis, Edge, intégration carte mère).

Les contrôles Windows du vrai EXE sont renforcés : taille préférée native,
centrage, espace disponible après padding, quatre coins dans la région de fenêtre
et pixels blancs du texte réellement dessiné, avec marge au-dessus et en dessous.
La capture du quatrième Preview (runtime isolé, sans préparation ni données client)
est publiée avec l'EXE comme preuve visuelle dans evidence/quit-button-2026-10-19/.

Validation Windows réussie : [run 39266577489](https://github.com/holyonefr/LDLC-Preparation-PC-test-app/actions/runs/39266577489),
source `8c215d0`, Windows Server 2025 / PowerShell 5.1. Suite release complète,
tests d'intégration/synchronisation et quatre ouvertures/fermetures du vrai EXE.
Les téléchargements constructeurs non modifiés sont exclus de ce passage ;
leurs tests simulés restent actifs et aucun installateur matériel n'est exécuté.

Sur le bureau du runner (fenêtre 481 × 222), bouton **75 × 26 pixels**, contre
50 × 14 dans la livraison précédente. Taille préférée native respectée sur les
quatre passages ; pixels blancs du libellé détectés de la ligne 10 à 17, sans
toucher les bords. Tous les coins sont dans la région de fenêtre. La
[capture Windows réelle](evidence/quit-button-2026-10-19/ui-preview.png) a été
inspectée : « Quitter » apparaît en entier et centré.

Livraison publiée uniquement dans la bêta, commit `fa07625` ; fichier Git LFS
vérifié contre le manifeste et la preuve du runner :
`3BE15311787BD6E55C84A91C659F4E157354A4ACBC94D18184381C62F72E03E5`.
[Preuves Windows](evidence/quit-button-2026-10-19/windows-evidence.json).

LDLC stable et Addon restent préparés localement, sans push ni EXE de production
modifié. Addon main/worker identiques et Test-AddonSync local réussi ; aucun
nouvel EXE Addon lancé pendant cette vérification. Numerik's intact.
