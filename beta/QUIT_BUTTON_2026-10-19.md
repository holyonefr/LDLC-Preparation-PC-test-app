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
sera publiée avec l'EXE comme preuve visuelle dans evidence/quit-button-2026-10-19/.

Validation Windows et livraison finale : en cours, à compléter après le workflow
beta-validation.yml. Les téléchargements constructeurs non modifiés sont exclus
de ce passage ; leurs tests simulés et la suite release restent actifs.
