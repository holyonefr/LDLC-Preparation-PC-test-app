# Chrome sans attente et désinstallateurs visibles — bêta

Correction de production synchronisée, intégration carte mère exclusivement bêta
préservée. Voir [le comportement commun](../RESULTATS_CHROME_ANTIVIRUS_2026-10-20.md).

Validation native réussie : [run 39413059512](https://github.com/holyonefr/LDLC-Preparation-PC-test-app/actions/runs/39413059512),
source `c37c725`, livraison `75f7cd0`. SHA256 EXE :
`E80699630145E474E6B97F073F46EE71BD830E4D66FA16AA59287D3760385380`.
Suite release et intégration bêta réussies ; quatre vrais Preview/fermetures.
Antivirus : 17 scénarios / 18 assertions, vraie fenêtre factice compilée/affichée/fermée,
retrait simulé, aucun antivirus réel supprimé. Chrome sans confirmation : 10 scénarios
/ 25 assertions, interactions simulées. Épinglage : 10 / 22 dont deux raccourcis COM
réels isolés ; aucune modification des épingles du compte. API d'associations :
3 contrôles natifs isolés ; AMD portable : 17 / 17, aucun pilote installé.

[Preuves Windows](evidence/no-confirm-security-2026-10-20/windows-evidence.json) et
[échec attendu sur l'ancien module Chrome](evidence/no-confirm-security-2026-10-20/baseline.json).
Les refus/annulations antivirus empêchent les installations et la preuve de fin,
sans réintroduire d'attente de confirmation Chrome ni forcer une réussite globale.
