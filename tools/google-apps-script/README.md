# Dashboard Preparation PC - Google Apps Script

Voir ../../DASHBOARD_PREPARATION_PC.md : theme mat, identites LDLC/Numerik's/ADDON,
compatibilite historique et deploiement existant permanent. Les formats anciens
restent acceptes ; aucun champ neuf obligatoire. Backend actif gere depuis LDLC.

1. Garde le Google Sheet permanent existant.
2. Ouvre le projet Apps Script permanent existant.
3. Colle le contenu de `LDLC_ErrorTelemetry.gs`.
4. Garde `SPREADSHEET_ID`, `INGEST_SECRET`, `DASHBOARD_PASSWORD` et `WEB_APP_URL` sur les valeurs permanentes existantes.
5. Mets a jour le deploiement web app existant avec une nouvelle version, sans creer un nouveau deploiement.

Pour que l'exe puisse envoyer des logs depuis n'importe quel PC, l'endpoint d'ingestion doit etre joignable sans connexion Google interactive. La securite repose donc sur `INGEST_SECRET` cote ingestion, et sur le mot de passe/e-mail cote tableau de bord.

Pour un verrouillage strict par compte Google, separe l'ingestion publique et le tableau de bord prive dans deux deploiements Apps Script distincts. Sur un endpoint public execute par le proprietaire, l'email du visiteur peut etre vide.

Apres le deploiement, verifie que `telemetry.config.json` et `modules/05.Telemetry.ps1` gardent la meme URL `/exec` et le meme secret, puis reconstruis les scripts principal et worker depuis `modules/`.

Important : ne vide pas `SPREADSHEET_ID` et ne cree pas de nouveau deploiement web app pour une mise a jour. Le dashboard recharge automatiquement les donnees du Sheet permanent environ toutes les 5 secondes quand il est ouvert.

Compatibilite : conserve les en-tetes historiques `ERROR_HEADERS` et `RUN_HEADERS`.
Les nouveaux champs doivent rester optionnels et les variantes anciennes sont
normalisees avant leur ajout dans le Sheet.

Lisibilite : `EtapesTerminees` reste dans `RUN_HEADERS` uniquement pour la
retrocompatibilite et le debug. La colonne est masquee automatiquement dans
l'onglet principal `Executions` via `CONFIG.HIDDEN_RUN_HEADERS`. Le dashboard
HTML ne l'affiche pas et ne l'utilise pas pour ses statistiques.

Suivi 2.6.0 : RunId stable, finalisation protegee contre les anciens messages
rejoues, Sequence et DetailsAvertissements optionnels. La duree seule ne finalise
jamais une execution. Les regles de statut des cartes et lignes sont communes.

Verification locale : `node tools/Test-LDLCTelemetryIngestion.cjs` et
`node tools/Test-LDLCDashboardCompatibility.cjs` depuis la racine.
Verification live : `tools\Test-LDLCTelemetryLive.ps1` ajoute des rapports de test
identifies puis les retire. L'action `auditruns` permet une sauvegarde avant une
deduplication de RunId strictement identiques.

Ne jamais lancer une remise a zero pour publier une nouvelle version.
`tools\Reset-LDLCTelemetrySheet.ps1` est uniquement un outil de maintenance
destructif a utiliser sur demande explicite de suppression de l'historique.

Validation finale (2026-10-16) : `InterventionTerminee` et `CauseBlocage` sont optionnels pour les anciens clients. La fin confirmee sans anomalie est validee automatiquement. Une interruption, un delai depasse, une erreur ou une verification non confirmee bloque la validation avec sa cause. Un warning ne compte plus comme validation reussie. Les erreurs tardives restent bloquantes meme si les metadonnees du rapport sont anciennes ; elles sont rapprochees uniquement par RunId exact. La synthese est actualisee sur place, avec style initialise une seule fois. Voir VALIDATION_FINALE.md et RESULTATS_VALIDATION_FINALE.md a la racine.

Le runner Windows a pu lire le dashboard permanent sans modifier les donnees ; cela ne fournit pas une session clasp ni les droits de publication Apps Script. Publier la source corrigee sur le meme deploiement depuis une session Google deja autorisee.
