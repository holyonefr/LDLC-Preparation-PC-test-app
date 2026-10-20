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
- Windows GitHub : **13 cas / 34 assertions McAfee reussis**, incluant le vrai
  lancement d'un enfant PowerShell inoffensif. Norton : 17 cas / 18 assertions,
  dont la fenetre factice native ; aucune suppression reelle.
- La suite release complete, les controles beta et **quatre ouvertures/fermetures
  du vrai EXE en mode apercu** ont reussi. Les telechargements constructeurs live
  sont ignores pour ce changement sans rapport avec l'integration carte mere.

Workflow manuel reussi :
[Windows beta, execution 39426435114](https://github.com/holyonefr/LDLC-Preparation-PC-test-app/actions/runs/39426435114).
Source testee : `f4b1453da492976ccbce96ccc40c78a698672e38`.
Livraison Windows : `4bcb39f43c914da75dc34d3d5315a77e9dc43c9f`.
EXE 2.6.8 : `dist/LDLCPreparationPC.exe`.
SHA256 : `5619D50AE8928F84AFB0D5C3B09F9E403ABF472350B29C6DD58F238288A37370`.
L'EXE rapatrie apres publication a ete compare a cette empreinte.
Preuves : [windows-evidence.json](evidence/mcafee-rollback-2026-10-20/windows-evidence.json).

Les suppressions et detections d'antivirus sont **simulees**. Le test natif
utilise un enfant PowerShell inoffensif ; le test Norton utilise une fenetre
Windows Forms factice. Aucun vrai McAfee/Norton n'est installe ou retire sur
le runner GitHub. La compatibilite avec une version reelle de McAfee n'est donc
pas prouvee par ces tests. Les quatre ouvertures en mode apercu ont ete controlees
par le workflow beta avant la publication de l'EXE.
