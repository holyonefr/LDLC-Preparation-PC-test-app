# Corrections du 20 octobre 2026 — beta 2.6.9

Statut : beta 2.6.9 compilee, testee et livree sous Windows.

Run : https://github.com/holyonefr/LDLC-Preparation-PC-test-app/actions/runs/39447605123
Source : c13c115f9f1c9f132a491249a25c18b596116ae5.
Livraison : b6617532bcf4775b2eef002a1411de83326498a8.
SHA-256 EXE : DDEF45E5335000E477A80A8F0C2CB3A31C00F425DC99C40A15A93AFC2E7CBDD0.
Empreinte recontrolee sur le vrai binaire LFS recupere.
Preuves : evidence/corrections-2026-10-20/windows-evidence.json.

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
tests natifs sont maintenant passes : suite release, 4 vrais lancements Preview,
3 scenarios avant/apres, McAfee 14 cas/36 assertions (enfants Windows reels,
inventaire simule), Chrome 10 cas/28 assertions, epinglage 11 cas/26 assertions
avec raccourcis COM reels en dossier isole, transmission 12 cas/35 assertions.
Les trois vrais envois Windows sont acquittes et visibles avec les statuts
success/error/stopped, puis les seuls rapports de test sont supprimes (Cleaned=true).
Le serveur expose les statuts mais pas le sous-etat validation, donc ce sous-etat
n est pas certifie par le test live. Des candidats de transmission pour les trois
productions sont prepares en patchs et seront testes sans publication production.
Aucun test ne pretend qu'une VM Windows Server reproduit toutes les pages
Parametres de Windows 10/11, ni qu'un vrai McAfee a ete desinstalle.
