# Étude indépendante des utilitaires de carte mère

Phase expérimentale demandée avant toute intégration. Ce dossier n'est ni appelé
par le workflow de préparation ni inclus dans les EXE. Il reste local au dépôt
LDLC ; aucune synchronisation avec Numerik's, ADDON ou le dépôt de test.

Le workflow manuel `motherboard-feasibility.yml` utilise Windows Server 2022 et
Windows PowerShell 5.1. La phase `research` lit les pages officielles. La phase
`validation` exécute trois passages du prototype et des scénarios simulés ; le
premier effectue aussi un audit de téléchargement et de signature numérique.
Les tests sont en lecture seule pour le système : aucune installation, mise à
jour Windows, modification de pilote, écriture BIOS, ouverture d'utilitaire ni
connexion Google. Les téléchargements de contrôle ne sont jamais exécutés.

## Exécution indépendante

Depuis Windows PowerShell 5.1, sans droits administrateur pour l'inventaire :

```powershell
powershell -NoProfile -File tools/experimental/motherboard/Invoke-MotherboardExperiment.ps1 -CheckOnline -OutputPath "$env:TEMP\motherboard-inventory.json"
```

Le JSON contient carte mère et révision SMBIOS, fabricant/modèle du PC, BIOS,
Windows, périphériques et pilotes installés. Le chipset est présenté comme un
indice PnP quand il est identifiable, sans inventer un nom de chipset exact.
Les champs absents et erreurs CIM restent visibles. Les numéros de série de la
machine, noms d'utilisateur et nom réseau du PC ne sont pas collectés.

`Selection.Tool` est une **piste de support**, pas une autorisation d'installation.
Le statut reste `manual_required` si le modèle/révision/Windows n'est pas confirmé.
Les portables, PC OEM et VM ne reçoivent aucun outil retail supposé compatible.
`InstalledUtilityEntries` ne prouve qu'une entrée registre : ni le bon fonctionnement
de l'utilitaire, ni son intégrité, ni sa compatibilité. Aucun EXE du registre n'est lancé.

```powershell
# Simulations : transport et signatures explicitement simulés, aucun accès Internet.
./tools/experimental/motherboard/Test-MotherboardExperiment.ps1 -OutputDirectory "$env:TEMP\motherboard-tests"

# Réservé à un runner Windows jetable : inventaire réel + fichiers officiels,
# aucune exécution/installation des fichiers téléchargés.
./tools/experimental/motherboard/Test-MotherboardExperiment.ps1 -Live -DownloadAudit -OutputDirectory "$env:TEMP\motherboard-live"
```

Pour examiner les documentations PDF, installer la dépendance de recherche isolée :
`python -m pip install -r tools/experimental/motherboard/requirements-research.txt`.
Elle n'est pas nécessaire à l'inventaire ou aux tests simulés.

Les JSON sous `reports/` et `artifacts/motherboard/` sont des résultats d'exécution,
pas des entrées du programme. Le script ne lit jamais ces rapports pour autoriser
une installation ultérieure. Les annotations GitHub utilisent de petits fragments
JSON récupérables avec `Collect-GitHubEvidence.py` et le CLI `gh` déjà authentifié.

## Limites intentionnelles de cette phase

Aucune liste de pilotes disponibles n'est inventée : `AvailableDrivers` reste
`null` tant qu'une interface officielle n'a pas été confirmée pour le modèle.
Le BIOS courant est relevé ; une version BIOS disponible exige une vérification
sur le support du modèle. Aucun flash, commande silencieuse supposée, clic par
coordonnées, redémarrage, scan Windows Update ou envoi Google.

Le filtrage de catalogues simulés compare numériquement des versions comparables,
avec identifiants matériels exacts et même fournisseur. Il produit des candidats,
jamais un statut « installé ». Les applications additionnelles sont refusées par
défaut ; les firmwares demandent une validation manuelle et les GPU restent hors
périmètre. Ce filtrage ne prouve pas qu'un installateur constructeur ne contient
aucun logiciel groupé : son installation reste donc interdite dans le prototype.

L'audit de téléchargement contrôle HTTPS et chaque redirection, taille, MZ,
Authenticode `Valid`, nom de l'éditeur et SHA-256. Pour un ZIP, il vérifie les
exécutables extraits ; cela ne vaut pas une signature ou une empreinte éditeur
de toute l'archive ni une preuve de dernière version/compatibilité. Les limites
sont 1 Gio téléchargé, 2 Gio déclarés après décompression et 600 s par requête de
téléchargement. Une erreur ne devient jamais un succès ou un repli vers un ancien fichier.

Voir [FAISABILITE.md](FAISABILITE.md), [RESULTATS_WINDOWS.md](RESULTATS_WINDOWS.md)
et les preuves d'exécution de ce dossier pour les
résultats Windows et les validations encore nécessaires sur matériel physique.
