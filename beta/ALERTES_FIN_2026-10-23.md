# Retrait des alertes Widgets et réseau en fin de préparation — 23 octobre 2026

Demande explicite : retirer le message pour les quatre All in App. Livraison
limitée à cette correction ; les personnalisations locales d'interface ne sont
pas intégrées. ADDON conserve Chrome seul, NVIDIA et le téléchargement Trackman.

Widgets devient une information de diagnostic, sans avertissement ni blocage de
validation. L'état observé reste conservé ; aucune désactivation n'est inventée.
Si le rapport final est sauvegardé mais sans accusé serveur, l'écran indique
« Préparation terminée. Rapport enregistré localement. ». Le journal garde la
cause réseau et la file durable reste disponible pour réessai. Si l'intervention
est interrompue ou comporte une vraie erreur, sa cause reste visible. Un échec de
sauvegarde locale reste signalé ; aucun succès serveur n'est inventé.

Un poste utilisait encore 2.6.8 ; son rapport était bien présent une seule fois,
avec 0 erreur et seulement l'avertissement Widgets. L'ancien client perdait la
cause détaillée du POST et affichait un message réseau générique. La cause HTTP
exacte de cet incident ne peut pas être reconstruite. Aucun historique du
dashboard n'a été modifié pour effacer son avertissement.

Le nouveau Test-CompletionDisplay couvre les refus de registre, lecture Widgets
indisponible, annulation, fin sauvegardée sans accusé, vraie erreur 1603, intervention
incomplète et sauvegarde locale impossible. Frontières Windows et HTTP simulées,
vraies fonctions de clôture et Widgets. Les workflows Windows exécutent ce contrat
sous PowerShell 5.1 et 7 avant la publication des EXE, plus la suite complète et
quatre vrais lancements Preview par édition. Les préparations complètes Windows 11
du dépôt VM restent distinguées de ces lancements Preview.

Version bêta : **2.6.17**. Contrôles finaux Chrome/Adobe et reconnaissance des
composants Widgets hérités de la bêta conservés. Aucune promotion de ces autres
changements bêta dans les productions pour cette livraison ciblée.
