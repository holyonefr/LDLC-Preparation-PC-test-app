# Verification des corrections — 17 octobre 2026

Les corrections ci-dessous sont publiees sur main, avec leurs scripts et EXE actualises. Chaque etape a passe trois executions Windows GitHub et un aller-retour reel vers le dashboard permanent avant la publication de l’etape suivante. Les essais distants creent leurs propres RunId CODEX-TEST et suppriment uniquement ces rapports ; le nettoyage est confirme.

## Passages verifies pour cette edition

| Correction | Commit teste | Windows | Dashboard reel |
| --- | --- | --- | --- |
| Arret au demarrage et bouton Quitter | `27ef909` | [3 passages reussis](https://github.com/holyonefr/LDLC-Preparation/actions/runs/39003253233) | Debut, succes, erreur 1603, arret : recus ; essais nettoyes |
| Sauvegardes concurrentes | `48dd895` | [3 passages reussis](https://github.com/holyonefr/LDLC-Preparation/actions/runs/39004410924) | Debut, succes, erreur 1603, arret : recus ; essais nettoyes |
| Pilotes NVIDIA | `f11e485` | [3 passages reussis](https://github.com/holyonefr/LDLC-Preparation/actions/runs/39009270027) | Debut, succes, erreur 1603, arret : recus ; essais nettoyes |
| Avertissements de mini-interface | `85c5c6b` | [3 passages reussis](https://github.com/holyonefr/LDLC-Preparation/actions/runs/39009719735) | Debut, succes, erreur 1603, arret : recus ; essais nettoyes |

## Comparaison avant / apres

| Cas | Avant | Apres |
| --- | --- | --- |
| Quitter pendant le demarrage | Une demande pouvait etre effacee par l’initialisation du worker. | La demande nouvelle est preservee ; le workflow ne demarre pas apres annulation. |
| Deux ecritures du meme rapport | Un ancien etat pouvait remplacer une fin recente. | Lecture, fusion, remplacement et acquittement sont serialises ; fin conservee et ancien acquittement refuse. |
| Worker ADDON dans un chemin avec espaces | PowerShell recevait un chemin fractionne et ne lancait pas le worker. | Trois vrais lancements reussis ; l’ancienne commande reproduit encore l’echec dans le test comparatif. |
| Repli NVIDIA, code 1603 ou expiration | Un pilote deja present pouvait faire conclure a un succes malgre l’echec de l’installateur. | Retour en echec ; aucune confirmation avec une cible officielle inconnue. Codes 3010/1641 conservent le besoin de redemarrage. |
| Mise a jour NVIDIA ADDON | Chocolatey pouvait garder le paquet installe sans verifier la version du pilote apres l’operation. | Source officielle actuelle, controle du paquet signe, mise a niveau de repli avec checksums, puis comparaison de la version observee a la cible compatible. |
| Mini-interface sans acquittement | Un message non peint a temps pouvait bloquer un resultat pourtant confirme par Windows. | Diagnostic informatif ; les associations reellement absentes et les annulations restent bloquantes. Aucun clic physique sans acquittement. |
| Raccourci ADDON orphelin | La seule presence du .lnk pouvait faire ignorer une installation manquante. | La cible executable doit exister ; un reste de registre seul ne suffit pas. Lecture du raccourci sans modification. |

Le bouton Quitter LDLC reprend l’alignement Numerik’s sous la progression. Les deux editions conservent une taille minimale et un texte lisible lorsque la fenetre est reduite. Le comportement du bouton reste identique ; le bouton ADDON n’a pas ete deplace.

## Portee des tests et incidents observes

Les vrais EXE livres sont executes en Preview sous Windows PowerShell 5.1, avec mesure des limites du formulaire et du bouton Quitter. Les suites verifient aussi les diagnostics du lanceur, le workflow, les demandes d’arret, Windows Update sans attente ni surveillance des mises a jour restantes, et les statuts de fin.

Pour la derniere version de cette edition, les trois mesures d’apparition de la fenetre Preview sont comprises entre **2.42 et 4.92 secondes** depuis l’entree du lanceur. Ce ne sont pas des mesures entre clic utilisateur et affichage : UAC, lancement du processus hote et choix manuel de la boutique Numerik’s sont exclus.

Les installations, GPU et associations Windows sont testes avec leurs frontieres systeme simulees. Aucune installation de pilote sur une vraie carte graphique, desinstallation d’antivirus ou preparation destructive d’un PC neuf n’est revendiquee. Les tests ADDON de raccourcis utilisent aussi de vrais fichiers .lnk sous Windows.

Les premiers essais ont revele un bouton trop petit sur un petit bureau et deux problemes du banc de test Windows (thread WinForms de PS2EXE et lecture du code de sortie des processus concurrents) ; ils ont ete corriges avant validation. Deux controles Numerik’s n’ont pas obtenu d’acquittement distant lors de leur premiere tentative ; les rapports sont restes sauvegardes, les essais ont ete nettoyes, et les relances ont confirme les trois statuts. La cause reseau/serveur exacte de ces absences d’acquittement n’est pas etablie. Une relecture de resultat GitHub a egalement rencontre un HTTP 503 temporaire, sans echec de l’application.

Le dashboard actif confirme les informations recues (RunId, edition, version, fin, statut et cause 1603). Il n’expose pas le nouveau champ `validation` : les tests le signalent `non_exposee`. Le nouveau backend Apps Script present dans les sources n’a pas ete redeploye depuis ce cloud, faute de session Google autorisee. Le push GitHub ne vaut pas deploiement Apps Script ; aucune validation serveur supplementaire ni rafraichissement de sa page n’est revendique.
