# McAfee : retour au traitement historique

Publication limitee a `holyonefr/LDLC-Preparation-PC-test-app`, beta 2.6.8.
Les trois applications de production ne sont pas poussees pour cette correction.

## Changement

McAfee retrouve son nettoyage historique dans un processus separe et sa limite
globale de 90 secondes. Le nouveau lancement interactif et son attente illimitee
ne s'appliquent plus a McAfee. Un produit restant, un resultat absent ou un delai
produit le retour/avertissement historique ; aucune suppression n'est deduite
sans resultat. Le processus enfant ne cible que McAfee, sans toucher Norton.

La reference Git est `holyonefr/LDLC-Preparation` au commit
`3aec296b7468e7634815eccec5d549fc90689c9f` : dernier etat disponible avant les
changements d'octobre, sans commit exactement trois semaines avant la demande.
Les neuf fonctions historiques impliquees dans la detection, les commandes et
le repli MCPR sont comparees par SHA256 de leur definition, fins de ligne
normalisees, dans `tools/fixtures/mcafee-before-changes.json`.

Norton garde son comportement actuel. Aucun changement Chrome, AMD, UI,
dashboard ou carte mere. Les adaptions beta sont declarees dans `beta/sync.json`.

## Validation

- Avant correction : le nouveau test echoue sur les anciens modules beta,
  car McAfee n'emprunte plus le traitement historique attendu.
- Apres correction, Linux : 12 cas / 32 assertions reussies pour le retour
  historique, dont produits multiples, absence de McAfee, protection Norton/OEM,
  produit restant, repli unique, delai de 90 secondes et Quitter.
- La suite Norton conserve son faux desinstallateur visible. Elle verifie aussi
  qu'aucun McAfee ne passe par son nouveau lancement ni par l'attente illimitee.
- Validation native Windows et nouvelle livraison : en attente du workflow manuel.

Les suppressions et detections d'antivirus sont **simulees**. Le test natif
utilise un enfant PowerShell inoffensif ; le test Norton utilise une fenetre
Windows Forms factice. Aucun vrai McAfee/Norton n'est installe ou retire sur
le runner GitHub. La compatibilite avec une version reelle de McAfee n'est donc
pas prouvee par ces tests. Quatre ouvertures du vrai EXE en mode apercu seront
controlees par le workflow beta avant publication.
