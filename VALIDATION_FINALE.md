# Validation automatique en fin d’intervention — 16 octobre 2026

La fin réelle du workflow produit immédiatement un rapport final, avant toute fermeture. Le bouton Quitter laisse uniquement l’envoi de ce rapport se terminer lorsque les opérations système et la sauvegarde locale sont achevées. Il ne suffit jamais de fermer la fenêtre, d’atteindre 100 % ou d’attendre longtemps pour valider.

## Comparaison avec le code précédent

Les mêmes scénarios exécutent le vrai workflow, la télémétrie et le callback Quitter, avec des doubles pour les installations, le réseau et la fenêtre. Aucune préparation du poste de test n’est lancée.

| Scénario | Avant | Après |
| --- | --- | --- |
| Fin normale | Rapport success, sans preuve distincte de fin | Rapport success et preuve explicite de fin ; validation automatique |
| Quitter pendant le POST final | Création du fichier d’arrêt ; le délai de fermeture peut tuer l’envoi après 8 s | Fermeture locale sans attendre le réseau ; aucun arrêt du worker finalisé |
| Erreur Chrome 1603 simulée | Statut failed, mais message final générique | Validation bloquée ; code 1603 et étape conservés |
| Chrome par défaut non confirmé | Warning compté comme réussite par le dashboard | Contrôle requis ; cause affichée ; aucune validation réussie comptabilisée |
| Windows Update encore en cours | Ancienne attente finale limitée | Déclenchement seul : ni attente ni surveillance des mises à jour restantes |
| Fermeture anticipée | Stopped, sans cause explicite dans le message final | Intervention incomplète ; aucune validation ; étape indiquée |
| Réseau indisponible | Rapport sauvegardé ; état d’envoi absent de l’interface | Rapport final durable ; interface indique la validation non transmise et le renvoi ultérieur |

Un accusé de finalisation local porte l’identifiant du processus et son heure de démarrage : un ancien fichier ou un PID réutilisé ne permet pas de quitter prématurément. Une erreur détaillée bloque également côté serveur si un ancien client fournit des compteurs incohérents. Une mise à jour ultérieure ne gomme pas les erreurs déjà connues du même RunId. Un nouveau démarrage rejoué ne remplace pas une fin.

Les avertissements déjà classés comme purement informatifs restent exclus ; un avertissement non résolu conserve son contenu et bloque la validation. Le script ne prétend pas vérifier une correction manuelle faite hors de son contrôle.

## Apps Script

Les champs optionnels `InterventionTerminee` et `CauseBlocage` complètent les colonnes historiques. Les anciens clients restent acceptés. La validation affichée est calculée par le serveur à partir de l’état final, de la preuve disponible et des erreurs ; elle ne dépend pas d’une simple durée.

La synthèse était effacée, fusionnée et mise en forme à chaque POST sous verrou. Elle est désormais actualisée sur place, avec mise en forme lors du changement de structure seulement. Le verrou d’ingestion attend au plus 5 s, au lieu de 30 s face à un timeout HTTP client de 20 s. Le client conserve le rapport si le serveur est occupé. Le dashboard relit les résultats toutes les 5 s au lieu de 60 s : l’écriture finale est immédiate dès réception ; l’affichage dépend de ce rafraîchissement et du réseau.

Le backend permanent est publié uniquement depuis LDLC. La copie Numerik’s a reçu explicitement la même correction technique ; les liens Google et les identités sont conservés. L’ADDON garde ses opérations NVIDIA et Chrome, sans Adobe ni validateur.

## Vérifications

- `tools/Test-PreparationCompletion.ps1` : 10 scénarios, 52 contrôles. Workflow réel et callback Quitter ; système et réseau simulés.
- `node tools/Test-PreparationCompletion.cjs` : 16 scénarios et 82 contrôles ; ingestion et synthèse réelles avec une feuille simulée. Pas de requête Google.
- Ancienne version : 17 contrôles client sur 32 et 55 contrôles serveur sur 82 échouent comme attendu. Les trois scénarios de relance nécessitent le propriétaire introduit par la correction ; les sept scénarios initiaux sont comparés dans les deux versions.
- Les tests existants de cycle de télémétrie, de Chrome, de syntaxe, de workflow, de livraison et d’intégrité des ressources restent exécutés.
- La correction Chrome précédente est aussi comparée : l’ancien sélecteur échoue sur la ligne navigateur ; la version actuelle passe ses 43 contrôles.
- Chaque dépôt exécute trois passages Windows avec son propre jeton GitHub : compilations et suites LDLC/Numerik’s, comparaison avant/après, et régressions ADDON dans ses deux arbres. Le premier essai centralisé a échoué au checkout privé (git128), avant tout test applicatif ; ces checkouts croisés ont été retirés. Les résultats natifs sont consignés après exécution dans `RESULTATS_VALIDATION_FINALE.md`.

## Publication Google : limite actuelle

Le 16 octobre, la lecture du dashboard permanent depuis ce cloud est refusée par le proxy HTTP 403. Il n’existe pas de session clasp autorisée dans ce compte cloud ni d’identité Google sélectionnable dans son manifeste. Les destinations Google nécessaires ont été ajoutées au brouillon de configuration réseau, qui reste à publier dans les paramètres de l’environnement.

Le correctif source est testable et publié sur GitHub ; cela ne met pas à jour automatiquement le déploiement Google. La lecture du dashboard par le runner Windows a ensuite réussi (voir les résultats). Les journaux internes des exécutions Apps Script et ses quotas restent inaccessibles sans session Google autorisée. Les causes de statut ont été reproduites localement et comparées aux messages du dashboard ; les éventuels dépassements de durée du moteur Apps Script lui-même doivent encore être confirmés dans ses journaux internes.

Pour publier depuis une session Google autorisée : `tools/Deploy-LDLCDashboard.ps1` dans LDLC, sur le même déploiement permanent, puis les tests live dédiés. Ne pas créer de nouvel endpoint ni remettre le Sheet à zéro. Les rapports offline ne deviennent visibles sur Google qu’après un envoi acquitté.

Le propriétaire de progression est vérifié sous verrou avant les écritures finales ; un ancien POST ne peut pas réécrire les 25 % d’un nouveau lancement, même en cas d’échec réseau ou de sauvegarde. Les workers auxiliaires ne prennent pas cette propriété. Les preuves d’erreurs sont rapprochées par RunId indépendamment de l’ordre des rapports ; les replays restent idempotents. Les valeurs explicites false/0/'0' empêchent la validation.

Lecture distante du 16 octobre via Windows, sans ajout/suppression : 66 rapports (39 en cours, 12 interrompus, 9 avec avertissement, 6 erreurs), aucune entrée timeout dans cette photographie. Lecture en 5,367 s (temps HTTP du dashboard, pas un temps de lancement EXE). Causes visibles : associations Chrome restant sur Edge, éléments Edge encore présents, vérification Widgets non confirmée et nettoyage McAfee/Norton dépassant 90 s. Ces anciens rapports n’ont pas été réécrits ni validés sans preuve de fin. Le push GitHub ne déploie pas la nouvelle source sur Google.

Depuis la demande du 16 octobre, Windows Update est une exception explicite : seule la transmission des commandes est contrôlée. Aucun délai ni mise à jour restante ne bloque la validation. Un échec de transmission reste bloquant. Voir RESULTATS_WINDOWS_UPDATE.md.
