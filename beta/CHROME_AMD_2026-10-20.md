# Chrome par défaut, barre des tâches et portables AMD

Publication limitée à `holyonefr/LDLC-Preparation-PC-test-app`. Les trois applications
de production restent gelées ; l'intégration carte mère de la bêta est conservée.

## Correction

- Chrome : tentative du bouton global « Définir par défaut » avant le sélecteur
  HTML. Si l'activation UIA ne change rien, un seul clic observé sur ce même bouton
  est autorisé, avec contrôle du focus, du point cliqué et de l'accusé de réception
  de l'interface compacte. Aucun clic à coordonnées fixes.
- Confirmation : lecture de l'association effective Windows par API native, avec
  repli COM et résolution de l'exécutable à partir du ProgID réellement retourné.
  Les chemins entre guillemets et l'enregistrement `Applications\chrome.exe` sont
  acceptés seulement si l'exécutable existe et correspond à Chrome. Deux lectures
  successives sont toujours exigées ; une association changeante est refusée.
- Si Chrome est déjà configuré, aucune ouverture des paramètres n'est nécessaire.
  La confirmation Chrome est bornée à 6 s par tentative au lieu de 12 s, les
  contrôles finaux ne répètent plus deux attentes de 12 s, et la pause finale est
  réduite. Le démarrage de Paramètres Windows conserve son propre délai : ces
  valeurs ne constituent pas une promesse de durée totale sur tout PC.
- Une difficulté intermédiaire ne laisse plus un avertissement lorsque Windows
  confirme finalement les applications par défaut. Un échec réel reste signalé,
  sans forcer la validation. La configuration PDF Adobe est conservée.
- Barre des tâches : l'ancien fichier XML suivi d'un redémarrage d'Explorer
  n'établissait pas que Chrome avait été épinglé. Utilisation du verbe Shell exposé
  par Windows, puis du menu contextuel de l'exécutable exact si nécessaire.
  Réussite seulement sur preuve d'épingle Windows ou de commande « Détacher ».
  Un refus/une commande absente reste un avertissement précis. Aucun redémarrage
  global d'Explorer, aucune copie forcée d'épingle, aucune modification de politique.
- AMD : exclusion des portables/tablettes détectés par `PCSystemType` ou les types
  de châssis SMBIOS, avant téléchargement, installation ou raccourci Adrenalin.
  Une batterie seule ne classe pas un PC comme portable. Un format indéterminé
  fait ignorer AMD avec explication. Sur un portable hybride, NVIDIA est conservé.

## Tests ciblés

Les reproductions sur les modules précédents (`725f775`) échouent comme attendu :
résolution Chrome effective non prise en charge et absence d'exclusion AMD portable.
Les tests après correction passent localement :

| Contrôle | Résultat local | Nature |
|---|---|---|
| Chrome : déjà prêt, bouton direct, clic sans effet, repli, erreur, annulation | 9 scénarios, 27 assertions | Associations, UI et horloge simulées |
| Sélection du bouton navigateur et protections du clic | 47 assertions | UI Windows simulée |
| Épinglage : existant, verbes, repli, absence d'effet, refus, annulation | 10 scénarios, 20 assertions | Contrôleur simulé |
| Portables, tablettes, fixe, format inconnu, hybride NVIDIA | 17 scénarios, 17 assertions | SMBIOS et frontière GPU simulés |

Avec Adobe et Chrome déjà prêts, le scénario mesure 1 250 ms d'horloge simulée ;
ce n'est pas une mesure réelle de Windows. Un bouton reconnu mais sans effet ne
génère pas de faux succès. Les suites existantes d'associations, AMD, ordre des
étapes et syntaxe passent également.

## Validation Windows GitHub

Compilation native, suite release et quatre lancements du vrai EXE : **en cours**.
Le workflow utilise `live_vendor_downloads=false` : aucun installateur matériel
n'est exécuté, aucun appel de télémétrie n'est envoyé.

Deux vérifications Windows supplémentaires ne simulent pas l'API : résolution
d'une extension/ProgID temporaire isolée, et lecture de vrais raccourcis `.lnk`
créés dans un dossier privé (une fausse cible Chrome doit être refusée). Les
associations navigateur et la barre des tâches du compte du runner restent intactes.

Les clics dans les vrais Paramètres Windows 11 et l'épingle visible sur le PC du
technicien restent à vérifier sur un poste réel. Les tests simulés ne prouvent
pas la compatibilité de tous les menus, politiques d'entreprise ou versions Windows.
