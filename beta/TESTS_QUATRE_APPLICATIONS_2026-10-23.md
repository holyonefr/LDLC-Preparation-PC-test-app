# Nouveaux tests des quatre All in App — 23 octobre 2026

**Quatre workflows Windows réussis, 16 ouvertures/fermetures Preview réelles,
aucun échec inattendu.** Les éditions de production restent inchangées.

| Édition | Version | Workflow Windows | EXE ouvert et fermé | Dashboard réel |
| --- | --- | --- | --- | --- |
| LDLC | 2.6.14 | [Réussi](https://github.com/holyonefr/LDLC-Preparation/actions/runs/39949578969) | 4/4 | 3 scénarios réussis, nettoyés |
| Numerik’s | 2.6.14 | [Réussi](https://github.com/holyonefr/Numerik-s-Preparation-PC/actions/runs/39949579205) | 4/4 | 3 scénarios réussis, nettoyés |
| ADDON | 2.0.3 | [Réussi](https://github.com/holyonefr/LDLC-Preparation-Addon/actions/runs/39949581589) | 4/4 | 3 scénarios réussis, nettoyés |
| Bêta LDLC | 2.6.15 | [Réussi](https://github.com/holyonefr/LDLC-Preparation-PC-test-app/actions/runs/39949584554) | 4/4 | Tests serveur en mémoire, aucun nouveau POST réel |

## Ce qui a été vérifié

- Recompilation native depuis chaque commit immuable, suites de régression,
  intégration carte mère, exclusion des portables et quatre lancements de chaque
  véritable EXE compilé dans un processus distinct. Aucun patch candidat appliqué.
- Les empreintes des EXE déjà livrés correspondent aussi à leurs manifestes
  propres : `SHA256SUMS.txt` pour LDLC/Numerik’s/bêta et
  `resources.addon.manifest.json` pour ADDON. Les nouveaux EXE de test ne sont pas
  publiés. Les empreintes avant/après compilation sont consignées séparément ;
  les ouvertures portent sur les EXE recompilés. ADDON conserve le même binaire.
- Chrome/PDF, finalisation, interruptions, hors ligne, sécurité, raccourcis,
  Windows Update, GPU et intégration constructeur suivant les tests de chaque
  édition. Les opérations destructives et identités matérielles sont simulées.
  ADDON garde NVIDIA/Trackman et ne requiert pas Adobe.
- Bêta : 49 suites PowerShell, 3 suites JavaScript, comparaison des anciens faux
  avertissements, 33 contrôles corrigés et 6 contrôles d'API Windows natives sous
  PowerShell 5.1 et 7. Le vrai workflow de clôture passe 13 scénarios / 92 contrôles
  sur des états système simulés.
- LDLC : téléchargements officiels, signatures et raccourcis COM réels des quatre
  constructeurs, sur Bureau standard et Bureau redirigé vers un dossier OneDrive
  de test. **22 cas / 130 assertions**, aucun échec. Matériel simulé, aucun logiciel
  constructeur exécuté/installé ; ce test ne prouve pas une synchronisation OneDrive.
- Les vérifications AMD officiel/Chocolatey passent pour LDLC, Numerik’s et bêta,
  sans lancer d'installateur matériel. ADDON reste NVIDIA uniquement.

## Dashboard et erreurs attendues

Pour chacune des trois productions, le vrai client envoie trois rapports
`CODEX-TEST` identifiés. Le serveur retourne les états suivants :

| Scénario injecté | Statut observé | Validation observée |
| --- | --- | --- |
| Réussite | `success` | `validated` |
| Erreur volontaire d'installation 1603 | `error` | `blocked` |
| Arrêt volontaire | `stopped` | `blocked` |

Début, fin explicite, acquittement, édition/version et une seule exécution visible
par identifiant d'essai sont contrôlés. Les **neuf rapports d'essai sont supprimés
et leur absence vérifiée** ; les suppressions ciblent uniquement ces identifiants.
Ce parcours n'audite pas l'unicité des lignes physiques de la feuille Google.

Les codes/avertissements volontairement injectés par les fixtures servent à
vérifier le blocage : ils ne sont pas des échecs réels d'installation sur ces
runners. **Aucune erreur inattendue ni échec de workflow n'a été relevé.**

## Problème connu encore reproductible en production

Les correctifs récents des faux avertissements restent **uniquement en bêta**.
Un test séparé du même scénario simulé sur les modules inchangés de LDLC,
Numerik’s et ADDON reproduit encore un avertissement Chrome conservé après
réussite tardive : 13 assertions historiques par édition, sous PowerShell 7 local.
Ce test est simulé et distinct des quatre workflows Windows natifs.

Le contrôle Widgets qui ignore une stratégie valide et le filtre PDF Adobe trop
strict sont également présents dans les anciens modules LDLC/Numerik’s. Adobe
n'entre pas dans le parcours ADDON. Aucun correctif n'est promu dans les
productions pendant cette demande de tests.

## Limites et preuves

Ces runners sont des Windows Server 2025 jetables. Les 16 Preview ne sont pas
16 préparations complètes de Windows 11 ni une qualification sur GPU/PC physique.
Le runner bêta n'a pas Adobe installé ; son diagnostic lit `MSEdgePDF` sans changer
le choix PDF. Cela ne permet pas de connaître l'association du PC du technicien.

Les [preuves structurées](evidence/four-editions-retest-2026-10-23/windows-results.json)
conservent commits, étapes, empreintes, géométrie et états du dashboard. Aucun
identifiant d'accès ni historique client n'est inclus. Les têtes Git et modifications
UI locales des trois productions ont été comparées avant/après : inchangées.
Le workflow bêta a seulement actualisé sa preuve de géométrie ; le présent compte
rendu et ses preuves sont publiés en bêta, sans changement du code applicatif.
