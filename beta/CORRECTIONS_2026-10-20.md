# Corrections du 20 octobre 2026 — beta 2.6.9

Statut : sources preparees, validation Windows en cours avant livraison.

- Chrome : retour a InvokePattern avant le clic observe ; controle court des
  associations HTTP/HTTPS/.htm/.html. En absence de bouton global, repli sur chaque
  association manquante. Un clic sans effet ne vaut plus reussite. Adobe conserve
  son parcours ; ADDON reste exclusivement Chrome.
- Barre des taches : utiliser en priorite le raccourci Chrome du menu Demarrer
  dont la cible est verifiee ; laisser a Windows un court delai d'application et
  verifier l'epingle avant de signaler le succes. Aucun remplacement des autres
  epingles ni strategie forcee.
- Transmission (beta uniquement) : reessai borne pour panne transitoire, cause
  precise sans secret dans le journal, delai configure respecte, rapport courant
  prioritaire sur un lot limite de rapports en attente. Conservation durable et
  suppression uniquement apres acquittement.
- McAfee : meme nettoyage historique dans les editions, worker isole 90 s,
  chemin avec espaces correctement transmis. Test du worker genere sans vrai
  antivirus ; Norton garde son desinstallateur interactif.

La lecture et les trois vrais envois avant correction ont reussi depuis le cloud :
reussite, erreur 1603 et arret, puis suppression de ces seuls rapports CODEX-TEST.
Le serveur est donc joignable actuellement. La cause exacte de l'incident du PC
photographie n'est pas prouvee : l'ancien client masquait l'exception de transport.
Le jeton OAuth de modification du dashboard est independant de ces envois.

Les memes fixtures reproduisent les trois regressions sur ba825782 et passent
avec les corrections. Elles simulent les actions Windows/reponses HTTP ; les
resultats natifs GitHub, envois reels et limites seront ajoutes apres execution.
Aucun test ne pretend qu'une VM Windows Server reproduit toutes les pages
Parametres de Windows 10/11, ni qu'un vrai McAfee a ete desinstalle.
