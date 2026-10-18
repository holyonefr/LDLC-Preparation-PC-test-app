# Résultats de validation finale — 16 octobre 2026

Neuf passages natifs Windows réussis : trois par dépôt. Les 27 processus de contrôle enregistrés retournent tous le code 0. Aucune annotation warning/failure sur les neuf jobs finaux. Les résultats proviennent des rapports structurés de chaque job, avec révision, système et codes de sortie ; pas seulement du statut global GitHub.

| Dépôt et exécution vérifiable | Révision testée | Passages réussis | Processus de contrôle | Codes |
| --- | --- | --- | --- | --- |
| [LDLC-Preparation](https://github.com/holyonefr/LDLC-Preparation/actions/runs/38952537474) | `8d46757` | 3/3 | 9 | Tous à 0 |
| [Numerik-s-Preparation-PC](https://github.com/holyonefr/Numerik-s-Preparation-PC/actions/runs/38952539624) | `abe2ba9` | 3/3 | 12 | Tous à 0 |
| [LDLC-Preparation-Addon](https://github.com/holyonefr/LDLC-Preparation-Addon/actions/runs/38953169023) | `1e55dc4` | 3/3 | 6 | Tous à 0 |

Windows Server 2022, Windows PowerShell 5.1.20348.5622. Les sources produit et les exécutables restent ceux de ces révisions ; les commits de documentation suivants ne modifient pas le produit.

LDLC : compilation C# / PowerShell, suite release complète (dont trois suites JS), diagnostics du lanceur et comparaison avant/après. Numerik’s : mêmes contrôles et accueil/interface de l’EXE livré. ADDON : ressources exactes de l’EXE livré, régressions des deux arbres, rendu WinForms et comparaison avant/après ; aucune nouvelle compilation ps2exe n’est revendiquée.

Les installations, les pilotes, les appels réseau des scénarios et les associations Chrome utilisent des doubles de test. Ces contrôles ne sont pas une préparation complète d’un PC neuf et ne valident pas un clic Chrome réel sous Windows 11.

## Scénarios et différences observées

| Scénario | Ancienne version | Version corrigée |
| --- | --- | --- |
| Fin normale | Rapport success sans preuve distincte de fin | Fin explicitement confirmée, envoi automatique |
| Quitter pendant l’envoi final | Demande d’arrêt du worker ; envoi susceptible d’être coupé après 8 s | Fermeture sans arrêt du worker déjà finalisé |
| Erreur Chrome 1603 injectée | Cause perdue dans le message de fin générique | Validation bloquée, étape et code 1603 conservés |
| Chrome non confirmé par défaut | Avertissement compté comme réussite par le dashboard | À vérifier, cause visible, aucune validation réussie comptabilisée |
| Délai Windows Update dépassé | Statut failed/warning pouvant masquer le timeout | Timeout conservé et validation bloquée |
| Fermeture avant la fin | Interruption sans cause précise dans le message final | Intervention incomplète et étape indiquées ; aucune validation |
| Réseau indisponible | Rapport sauvegardé sans état d’envoi dans l’interface | Fin conservée, absence de transmission clairement indiquée |
| Nouveau lancement pendant un ancien POST | Ancien retour susceptible d’écraser la nouvelle progression | Propriétaire vérifié sous verrou ; nouvelle progression préservée |
| Erreur reçue après une fin success | Erreur possible dans la feuille sans blocage du run final | Blocage du RunId exact, sans effacer fin/dates/métadonnées |

Le client corrigé passe 10 scénarios et 52 contrôles. Les sept scénarios communs tournent aussi sur l’ancien code : 17/32 contrôles échouent comme attendu ; les trois scénarios de relance supplémentaires nécessitent le propriétaire ajouté par la correction. Les tests du serveur passent 82 contrôles / 16 scénarios contre 55 échecs attendus avant correction. Ces nombres comptent des assertions, pas des erreurs utilisateur distinctes.

La correction Chrome précédente a également été comparée localement : ancien sélecteur en échec sur la ligne navigateur, sélecteur actuel à 43/43 contrôles. Le code 1603 est volontairement injecté par les tests : ce n’est pas un échec réel d’installation sur le runner.

## Échecs de vérification rencontrés et corrigés

- Premier essai centralisé : git 128 / dépôt privé introuvable lors d’un checkout croisé. Aucun test applicatif exécuté à cet endroit. Chaque dépôt utilise maintenant son propre workflow et son propre jeton.
- ADDON : code 1 de Test-AddonNoValidator, empreinte du script différente de sa ressource EXE après conversion CRLF par Git Windows. `dist/*.ps1 -text` préserve désormais exactement les octets. L’assertion d’intégrité n’a pas été assouplie ; les trois derniers passages la réussissent.

## Lecture réelle de PrepTool et publication Google

Le runner Windows a lu le dashboard permanent en 5,367 s, sans ajouter ni supprimer de données. Ce temps est celui de la lecture HTTP du dashboard, pas celui de l’ouverture de l’EXE.

Photographie : 66 rapports, dont 39 en cours, 12 interrompus, 9 avec avertissement et 6 erreurs ; aucun timeout dans cette photographie. Les messages d’avertissement citent notamment Chrome restant associé à Edge (http/https/.htm), des éléments/processus Edge encore détectés, un contrôle Widgets non confirmé et un nettoyage McAfee/Norton dépassant 90 s. Les rapports d’erreur conservaient parfois seulement « Execution terminee : Échec » : le nouveau client transmet leur cause explicite.

Le correctif Apps Script est présent et testé dans le dépôt canonique LDLC. Il n’est PAS encore déployé sur Google : aucune session clasp autorisée au projet n’est disponible dans ce cloud. La lecture publique depuis Windows ne confère pas les droits de publication et n’accède pas aux journaux internes/quota du moteur Apps Script. Le réseau direct du cloud refuse toujours Google (403) ; les destinations nécessaires sont enregistrées dans le brouillon de configuration, non publié.

Pour activer le nouveau calcul de validation, ses causes et le rafraîchissement à 5 s : publier depuis une session Google autorisée avec tools/Deploy-LDLCDashboard.ps1, sur le même déploiement permanent. Aucun historique n’a été réécrit pour fabriquer une réussite. Voir VALIDATION_FINALE.md pour le contrat et les limites.
