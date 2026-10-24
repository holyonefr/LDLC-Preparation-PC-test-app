# Chrome informatif et ancienne méthode taskbar — 24 octobre 2026

La bêta 2.6.19 applique la nouvelle demande : une préférence Chrome non confirmée
reste dans le journal, sans avertissement ni blocage de validation. Son état réel
reste faux/inconnu et l'interface ne prétend pas que Chrome a été configuré.
L'installation de Chrome, les erreurs des autres étapes et un vrai défaut PDF
Adobe conservent leurs contrôles et leurs erreurs. Aucun événement existant n'est
effacé et aucune ancienne ligne du dashboard n'est réécrite.

Le faux avertissement Chocolatey vient uniquement de l'ADDON : son bootstrap
normal est informatif ; un véritable échec de téléchargement ou d'installation
reste signalé. Cette adaptation est préparée dans l'ADDON, avec main/worker
identiques. LDLC reçoit la même politique Chrome, sans importer les modifications
d'association propres à la bêta. Numerik's conserve sa politique actuelle.

Les quatre éditions utilisaient déjà la méthode historique d'épinglage depuis la
restauration du 22 octobre : layout XML Append ciblant Chrome et relance Explorer,
sans menu UIA ni attente de confirmation de l'épingle. Le dernier état LDLC avant
le 25 septembre est `3aec296b7468e7634815eccec5d549fc90689c9f` (commit du 18 juillet).
Le corps historique est identique à la fixture déjà utilisée. Il n'y a donc pas
lieu de remplacer le code par une autre méthode. La régression vérifie maintenant
aussi l'entrée appelée par le workflow et les deux scripts livrés dans les quatre
éditions : **92 assertions / neuf scénarios** par arborescence.

Tests ciblés : Chrome déjà correct, préférence non appliquée, lecture impossible,
annulation, erreur MSI réelle conservée ; quatre cas de bootstrap Chocolatey dans
l'ADDON. Les associations/UI/téléchargements sont simulés dans ces régressions ;
les écritures/lectures du XML historique sont réelles dans un dossier temporaire.
Ce n'est pas une preuve d'affichage de l'icône sur toutes les versions de Windows.

La synchronisation est auditée sur LDLC `3e21c92` propre ; overlays, constructeur,
versions et interface bêta sont conservés. Les trois productions restent sans
push conformément à l'instruction de publication. Les modifications UI locales
préexistantes sont exclues des candidats et conservées octet pour octet. Aucun
déploiement Apps Script, aucun changement des fonctions GPU ou de désinstallation.

Validation native Windows et empreintes des candidats : résultats à compléter
après exécution, avant toute déclaration de livraison vérifiée.
