# Bouton Quitter et bandeau bas — 19 octobre 2026

Sur une petite fenêtre, les hauteurs minimales de police et les marges natives
rendaient le bouton trop massif ; il recouvrait le bas du cadre de progression.
La première correction (75 × 26 px) gardait le texte entier mais son rendu a été
refusé par l'utilisateur. Elle est remplacée par la disposition décrite ici.

Le bouton utilise la taille native préférée avec GrowAndShrink, un padding
horizontal réduit et aucune marge verticale ajoutée. Les événements de clic et
d'arrêt restent identiques. Un espace est réservé en bas avant de placer les
textes : le cadre de progression et son contenu remontent ensemble si nécessaire.
Le bouton ne peut plus empiéter sur ce cadre. Une marge à droite protège ses
quatre coins du masque arrondi. La taille de fenêtre reste inchangée.

Les rectangles des deux lignes de chaque étape utilisent la vraie hauteur des
polices : plus de lettres coupées verticalement. Les longs libellés gardent les
points de suspension prévus par l'interface. Images, logos, couleurs des textes
et opérations de préparation sont conservés. Numerik's est exclu.

## Revue avant livraison

[Revue Windows réussie](https://github.com/holyonefr/LDLC-Preparation-PC-test-app/actions/runs/39270324865),
source `509f8d4` : six rendus GDI+ et quatre vrais lancements Preview isolés.
Fenêtre 481 × 222 inchangée ; bouton **57 × 22**, cadre terminé à y=192,
bouton à y=197 : **5 pixels de séparation**. Texte centré, pixels blancs conservés,
quatre coins entièrement dans la fenêtre. [Capture réelle inspectée](evidence/quit-layout-review-2026-10-19/ui-preview.png).
Cette étape de revue n'a publié aucun EXE.

Les contrôles natifs vérifient maintenant les limites de chaque texte/barre et la
séparation cadre/bouton. Une première revue a correctement échoué sur un coin
encore trop proche de l'arrondi ; la marge a été corrigée, sans affaiblir le test.
Le workflow rapide `ui-preview.yml` garde aussi la capture et le statut des essais
en échec, pour permettre le diagnostic sans prétendre que le rendu est validé.

## Portée et publication

Modifications préparées dans LDLC et Addon localement (deux arbres Addon identiques),
sans push ni nouvel EXE de production. La fixture de dessin Addon est extraite de
son vrai fichier local ; la bêta conserve l'intégration carte mère et les autres
corrections. Seule la bêta est autorisée à publier son EXE.

Validation release complète et nouvelle livraison : en cours après la revue.
Les tests UI/GDI+ sont réels ; opérations Shell/installation simulées. Aucun
installateur matériel réel et aucun téléchargement constructeur non modifié
ne sont exécutés pour cette correction. Les essais ne constituent pas un
lancement d'un nouvel EXE Addon ou LDLC de production.
