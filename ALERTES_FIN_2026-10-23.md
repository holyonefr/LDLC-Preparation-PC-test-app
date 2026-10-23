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

## Livraison vérifiée

| Édition | Version | Validation Windows |
| --- | --- | --- |
| LDLC | 2.6.15 | [Réussie — 39990038354](https://github.com/holyonefr/LDLC-Preparation/actions/runs/39990038354) |
| Numerik’s | 2.6.15 | [Réussie — 39990044085](https://github.com/holyonefr/Numerik-s-Preparation-PC/actions/runs/39990044085) |
| ADDON | 2.0.4 | [Réussie — 39990050694](https://github.com/holyonefr/LDLC-Preparation-Addon/actions/runs/39990050694) |
| Bêta | 2.6.17 | [Réussie — 39990326869](https://github.com/holyonefr/LDLC-Preparation-PC-test-app/actions/runs/39990326869) |

Les quatre suites natives et **16 lancements/fermetures réels en Preview** passent.
Les nouvelles vérifications d’affichage tournent sous PowerShell 5.1 et 7 :
12 assertions par production, dans les deux arbres ADDON ; 13 en bêta. La bêta
passe aussi 41 assertions des contrôles finaux et 14 scénarios / 100 contrôles
de clôture, dont erreur 1603 simultanée à une coupure réseau. Les frontières
Windows/HTTP de ces scénarios sont simulées ; les fonctions de clôture sont réelles.

LDLC, Numerik’s et ADDON effectuent chacun trois vrais échanges avec le dashboard :
fin normale → validée, erreur → bloquée, interruption → bloquée. Les rapports
synthétiques identifiés sont ensuite nettoyés ; aucun historique client modifié.
Le roundtrip synthétique est désactivé pour ce passage bêta. Les EXE publiés ont
tous été récupérés et leurs SHA-256 correspondent aux preuves Windows.

Ces Preview et scénarios ne constituent pas quatre préparations complètes dans
Windows 11. Les essais complets de VM sont consignés séparément dans le dépôt VM.
Aucun installateur de pilote matériel exécuté sur les runners. **Remplacer les
anciens EXE pour bénéficier de la correction** ; les copies 2.6.8 restent anciennes.
