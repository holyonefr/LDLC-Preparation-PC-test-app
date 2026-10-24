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

## Validation native achevée

| Édition | Windows GitHub | Résultat final | Vrais Preview/fermetures |
| --- | --- | --- | --- |
| Bêta 2.6.19 publiée | [40078651074](https://github.com/holyonefr/LDLC-Preparation-PC-test-app/actions/runs/40078651074) | Réussi | 4 |
| LDLC 2.6.16 candidat | [40078654013](https://github.com/holyonefr/LDLC-Preparation/actions/runs/40078654013) | Réussi au deuxième passage | 4 |
| ADDON 2.0.5 candidat | [40078656720](https://github.com/holyonefr/LDLC-Preparation-Addon/actions/runs/40078656720) | Réussi | 4 |
| Numerik’s 2.6.15, méthode déjà historique | [40078659440](https://github.com/holyonefr/Numerik-s-Preparation-PC/actions/runs/40078659440) | Réussi | 4 |

Seize ouvertures/fermetures réelles des EXE, suite release et contrôles ciblés
réussis. Chrome informatif : 10 assertions LDLC, 12 bêta (PowerShell 5.1 et 7) ;
ADDON : 17 assertions incluant les quatre cas Chocolatey, vérifiés dans les deux
arbres. Méthode taskbar : 92 assertions et neuf scénarios, entrée workflow et
scripts principal/worker contrôlés. Les notices de certains sous-tests ADDON
sont limitées par le quota GitHub ; le contrôleur a bien exécuté les deux arbres
et sa suite entière a terminé avec code 0.

Les trois candidats ont aussi envoyé puis relu via l'API du dashboard les cas
réussite, erreur 1603 injectée et arrêt utilisateur : accusés reçus, statuts
respectivement success/validated, error/blocked et stopped/blocked. Nettoyage
limité à leurs propres lignes CODEX-TEST, confirmé ; aucun historique client
modifié. Ces envois contrôlent le transport réel et le code client avec des
scénarios simulés, ils ne constituent pas trois préparations matérielles.

Le premier passage LDLC a échoué : l'accusé final du cas erreur n'était pas reçu,
avec un élément encore en file locale. Le cas réussite était acquitté ; le
nettoyage a été confirmé. La cause exacte du défaut d'accusé n'est pas démontrée.
La seconde tentative utilise exactement la même source et le même patch, après
la fin des autres essais ; les trois cas et quatre Preview passent. Le premier
échec reste enregistré et n'est pas présenté comme réussi.

EXE bêta Windows testé et publié au commit
`1aebac37957054bc5b9f0497a22b986724549067`, source `b05e07b23c70acab5e478dab3370cdf9aa8115e9`.
SHA-256 reçu et revérifié :
`62AB90853AE54F03E6D1A7D4A5B128AFD7206B7FB5B74413BE3408F57CE75147`.
Les EXE candidats sont téléchargeables dans l'artefact
`chrome-amd-windows-preview`, sous `candidate-delivery`, sur leurs exécutions
GitHub ; aucune publication de production n'a été effectuée.

[Preuves structurées](evidence/chrome-diagnostics-taskbar-2026-10-24/windows-validation.json).
Les tests natifs sont exécutés sur Windows Server 2025 ; aucun nouveau parcours
complet dans une VM Windows 11 n'a été lancé pour cette politique d'avertissement.
Les associations/installeurs et la relance Explorer sont simulés dans les tests
ciblés ; la lecture/écriture du XML est réelle. L'affichage réel de l'épingle n'a
pas été requalifié. Les deux préparations Windows 11 neuves sans avertissement
déjà documentées appartiennent à l'EXE précédent, la bêta 2.6.18.
