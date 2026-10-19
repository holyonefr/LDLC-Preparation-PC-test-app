# Rendu Addon préparé localement

`addon.ps1` contient uniquement les fonctions pures de dessin de la progression,
extraites par AST de `LDLC-Preparation-Addon/modules/99.UI.ps1` après agrandissement.
Aucun démarrage, installation, identité machine, secret ou asset de production.
Ce fichier est une fixture de test : ne jamais l'embarquer dans une application.

Le test Windows dessine réellement les deux lignes avec GDI+, vérifie leurs
hauteurs et pixels, leur séparation et les limites de la fenêtre. Ce rendu isolé
ne constitue pas un lancement de l'EXE Addon recompilé. LDLC stable et la bêta
partagent la même fonction de progression après cette correction ; Numerik's
est explicitement exclu. Les EXE de production restent inchangés tant que leur
publication n'est pas autorisée.
