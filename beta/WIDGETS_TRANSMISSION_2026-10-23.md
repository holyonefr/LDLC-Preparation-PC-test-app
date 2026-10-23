# Widgets et confirmation d'envoi — bêta 2.6.16

Un poste réel exécutait encore LDLC **2.6.8**. Le dashboard et l'audit de la feuille
confirment une seule ligne finale, **0 erreur et 1 avertissement Widgets**.
Le rapport est donc arrivé malgré le message affiché sur le PC. Aucune ligne
historique ni validation de production n'a été modifiée pour masquer cet incident.

## Cause du message réseau

La version 2.6.8 utilise « réseau ou serveur indisponible » pour tout échec du POST
ou de son accusé. Son `catch` conserve le rapport mais ne conserve pas la cause
détaillée. Il est impossible d'attribuer cet incident précis à un timeout, proxy,
code HTTP ou quota avec cette photo et la seule ligne serveur. Une réponse perdue
après écriture est possible ; ce n'est pas une preuve de coupure réseau.

Le client récent possède déjà un délai par défaut de 30 secondes, un réessai borné
pour erreurs temporaires, un lot borné donnant priorité au rapport courant et une
cause précise dans le journal. La bêta 2.6.16 dit désormais **« Transmission non
confirmée »** sans affirmer que le serveur n'a rien reçu. La copie locale reste
conservée tant que l'accusé attendu n'est pas obtenu. Même RunId lors du réessai ;
aucune intervention incomplète ou en erreur n'est convertie en réussite.

## Widgets

La 2.6.15 reconnaissait déjà la stratégie Windows prise en charge même quand la
valeur utilisateur `TaskbarDa` était protégée. La 2.6.16 reconnaît aussi les
composants **réellement absents** de la session Windows 11 après une requête Appx
réussie : `MicrosoftWindows.Client.WebExperience` et
`Microsoft.WidgetsPlatformRuntime`. Si l'un est présent, l'absence n'est pas
confirmée. Si la requête échoue ou si Appx est indisponible, l'état reste inconnu.
Windows 10 garde son contrôle distinct de News and Interests.

Ce contrôle ne désinstalle rien et ne change aucun paramètre. Les erreurs Chrome,
PDF, installations, GPU ou interruption restent signalées. L'état réel des
composants du PC du technicien n'a pas pu être lu à distance dans cette session.

## Tests et livraison

Tests ciblés locaux réussis :

- 39 assertions des contrôles finaux, dont composants absents, chacun des deux
  composants présent, lecture Appx refusée et Windows 10 ; états Windows simulés.
- 14 scénarios / 42 assertions d'envoi, dont serveur simulé qui enregistre puis
  perd sa réponse, reprise du même identifiant et conservation locale sans accusé.
- 13 scénarios / 92 contrôles du vrai workflow de clôture, dont hors ligne,
  fermeture pendant le POST, erreur réelle et interruption ; installations et
  frontière HTTP simulées, vraie file locale isolée.

La validation Windows, la compilation et les quatre vrais lancements Preview de
l'EXE doivent être terminés avant de qualifier cette livraison. Les préparations
Windows 11 complètes antérieures utilisaient la 2.6.15 et ne prouvent pas une
préparation complète de la nouvelle 2.6.16. Aucun nouveau scénario simulé n'est
envoyé au dashboard permanent. Publication exclusivement dans le dépôt bêta.
