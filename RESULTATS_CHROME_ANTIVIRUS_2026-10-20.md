# Chrome sans attente et désinstallateurs McAfee/Norton — 20 octobre 2026

Cette correction remplace les attentes de confirmation introduites auparavant.
Publication sur LDLC, Numerik's et Addon ; bêta synchronisée, module carte mère
exclusivement dans la bêta. Interfaces et anciens travaux UI locaux conservés.

## Comportement demandé

- Chrome : clic sur le bouton navigateur « Définir par défaut », puis poursuite.
  Aucun polling ni contrôle final bloquant des associations Chrome. Une lecture
  initiale immédiate peut éviter une action inutile quand Chrome est déjà choisi.
  Le repli HTML transmet aussi le bouton sans attendre la confirmation du registre.
  Le clic physique garde les protections de focus, contrôle exact et ACK de rendu.
- Épinglage : commande Windows envoyée, sans attente de confirmation de l'épingle.
  Le journal annonce une commande transmise, jamais un résultat vérifié non mesuré.
  L'absence de Chrome, de commande accessible ou un clic impossible reste signalé.
- Adobe : parcours existant conservé dans LDLC/Numerik's ; absent de l'Addon.
  Les erreurs d'installation et de préparation restent bloquantes. Supprimer la
  confirmation Chrome ne force pas la validation d'une intervention en erreur.
- McAfee/Norton : ouverture directe de leur `UninstallString` enregistrée, fenêtre
  normale, sans ajouter de switches silencieux ; MSI /I devient /X sans /qn.
  Les paramètres silencieux standards sont retirés, les arguments du constructeur
  et leurs guillemets conservés. Aucun panneau « Applications installées ».
- La préparation attend le retrait avant les installations. Aucun plafond de
  90 s dans ce parcours, aucune mise à mort du désinstallateur. Un parent terminé
  n'est pas une preuve de retrait : un enfant peut encore afficher son interface.
  À l'inverse, une entrée disparue ne suffit pas si le parent travaille encore.
  Quitter reste disponible. Refus, annulation explicite, redémarrage nécessaire ou
  désinstallateur absent arrêtent avec leur cause ; aucune fausse suppression.
- L'Addon effectue cette étape dès le début ; son nettoyage OEM ultérieur exclut
  les antivirus. Aucun ajout AMD, Adobe ou validateur dans cette édition.

L'historique consulté (`c80a6ae` et ses prédécesseurs) avait rétabli les tentatives
silencieuses avec repli téléchargé. Le parcours normal appelait ensuite un worker
caché tué après 90 s. La correction rétablit le comportement visible demandé,
sans rétablir le repli vers les paramètres Windows ni les changements sans rapport.
Le helper d'isolation historique reste disponible pour les diagnostics explicites,
mais n'est plus appelé par la préparation normale.

## Vérifications

Les tests locaux passent pour le flux Chrome sans attente, les vrais échecs de
commande, le clic protégé, la barre des tâches, les refus/annulations antivirus,
le retrait tardif après 95 s simulées et la fin de workflow. Deux cas supplémentaires
vérifient qu'un refus antivirus ou Quitter empêchent toute installation et toute
fausse preuve de fin. Le test Chrome contre le module précédent échoue comme attendu.

Les suites Windows doivent compiler/réassembler chaque édition, exécuter les
régressions et quatre vrais Preview/fermetures avant publication. Le test antivirus
Windows utilise un EXE factice compilé qui ouvre une vraie fenêtre temporaire puis
se ferme : aucune désinstallation McAfee/Norton réelle, aucune modification du
registre. La détection et le retrait sont simulés. Résultats Windows : en cours.
