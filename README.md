# LDLC Preparation PC — BETA

Ce depot est la version beta de LDLC Preparation PC, avec preparation du logiciel de carte mere et raccourci Bureau. Installation manuelle, portables exclus.

Lire [BETA.md](BETA.md) pour les fonctions ajoutees, les tests et la synchronisation. Livraison : [dist/LDLCPreparationPC.exe](dist/LDLCPreparationPC.exe). Aucun push sur les trois depots de production pour cette livraison.

---

# LDLC PrepTool

## Lanceur partage 2.6.2

Le lanceur accepte un accueil local optionnel avant PowerShell. Cet accueil boutiques
est fourni UNIQUEMENT dans Numerik's (branding/startup protege). LDLC ne contient pas
ces sources ni ce logo : demarrage, UI, fonds et liens Google inchanges.

## Mise a jour dashboard et identite des editions - 2026-10-13

Lire [DASHBOARD_PREPARATION_PC.md](DASHBOARD_PREPARATION_PC.md) pour la passation
complete : theme ardoise mat sans neon, titre Dashboard Preparation PC, colonne
All In App LDLC/Numerik's, compatibilite des anciens formats et liens permanents.
Release courante : 2.6.2.0. UI et fonds Windows des logiciels inchanges.

## Edition LDLC et coeur partage (2026-10-13)

Le projet complet est aussi disponible dans Numerik-s-Preparation-PC, avec un
coeur technique synchronisable sans ecraser les UI, logos, couleurs ou fonds.
Lire [SYNCHRONISATION.md](SYNCHRONISATION.md) pour le fonctionnement et la commande
`tools/Sync-PreparationCore.ps1 -Publish` qui compile, teste et publie les deux depots.
Une modification poussee seule ne met pas automatiquement l'autre depot a jour.
Aucun element graphique ni lien permanent n'a ete modifie pendant cette duplication.
Les outils de livraison partages lisent DeliveryBaseName dans sync/edition.json.
LDLC conserve LDLCPreparationPC ; seule Numerik's utilise Numerik'sPreparationPC.

Source maintenable, tableau de bord Google Apps Script et sortie compilable de
`LDLCPreparationPC.exe`.

Pour reprendre le projet depuis un autre PC ou avec une autre IA, lire d'abord
[`PASSATION_PROJET.md`](PASSATION_PROJET.md).
La source de verite est toujours le depot GitHub `origin/main`, pas un dossier
local potentiellement modifie sur un autre poste.

## Structure

- `modules/` : source PowerShell canonique, assemblee dans l'ordre de `build-order.txt`.
- `assets/` : ressources graphiques embarquees. Le composant de diagnostic retire n'est plus distribue.
- `tools/google-apps-script/` : reception de telemetrie et dashboard HTML permanent.
- `tools/` : reconstruction, compilation, verification et deploiement.
- `dist/` : scripts generes et executable compile.

## Commandes utiles

Verifier la syntaxe de tous les fichiers PowerShell :

```powershell
.\tools\Test-LDLCSyntax.ps1
```

Verifier les formats de telemetrie anciens/nouveaux et les couleurs :

```powershell
node .\tools\Test-LDLCDashboardCompatibility.cjs
```

Reconstruire le script principal depuis les modules :

```powershell
.\tools\Rebuild-LDLCPreparationPC.ps1
```

Reconstruire le worker embarque :

```powershell
.\tools\Rebuild-LDLCPreparationPC.ps1 -Source worker
```

Compiler le lanceur .NET 2.6.1 avec l'icone existante et le manifeste SHA-256 :

```powershell
.\tools\Build-LDLCPreparationPCExe.ps1
```

Verifier la livraison dans un runtime isole, sans preparation du PC :

```powershell
powershell -STA -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-LDLCRelease.ps1
```

Publier le Google Apps Script sur le deploiement permanent existant :

```powershell
.\tools\Deploy-LDLCDashboard.ps1
```

Mettre a jour `LDLCPreparationPC.exe` avec les scripts reconstruits et l'icone LDLC :

```powershell
.\tools\Update-LDLCExecutableResources.ps1
```

## Telemetrie erreurs Google Sheets

Le module `05.Telemetry.ps1` envoie un resume d'execution unique par lancement. Les erreurs reelles sont ajoutees a la feuille des incidents; les avertissements non bloquants restent attaches au statut de l'execution (`Réussi avec avertissement`) sans creer de fausse alerte.

1. Mettre a jour `tools/google-apps-script/LDLC_ErrorTelemetry.gs` dans le projet permanent existant.
2. Dans le deploiement Apps Script, utiliser `Executer en tant que moi` et `Acces : tout le monde`, afin que l'exe puisse poster sans connexion Google interactive.
3. Proteger l'ingestion avec `INGEST_SECRET` et le tableau de bord avec `DASHBOARD_PASSWORD`.
4. Copier l'URL web app `/exec` et le secret `INGEST_SECRET`.
5. Lancer :

```powershell
.\tools\Configure-LDLCTelemetry.ps1 -EndpointUrl "https://script.google.com/macros/s/XXX/exec" -ApiKey "SECRET" -Rebuild
```

Sans ces deux valeurs, le script continue de fonctionner normalement mais n'envoie rien.
Pour un verrouillage strict par email Google, deployer le tableau de bord separement avec un acces Google restreint; sur un endpoint public `Executer en tant que moi`, Google Apps Script ne fournit pas toujours l'email visiteur.

Le Google Sheet et le deploiement web app sont permanents. Une mise a jour doit
modifier le deploiement existant, jamais creer un nouveau Sheet ou une nouvelle
URL `/exec`. L'ingestion accepte les formats historiques et les nouveaux champs
restent optionnels.

## Ordre des modules

L'ordre canonique est stocke dans `modules/build-order.txt`.

Les modules numerotes correspondent aux regions presentes dans le script original.
Modifier uniquement `modules/`, puis reconstruire les deux scripts de `dist/`.

## Installateurs et ordre de demarrage

- Ordre initial : detection/desinstallation McAfee et Norton, point de restauration, lancement de Windows Update en arriere-plan, puis preparation normale.
- Windows Update tourne pendant toute la preparation dans un worker separe, boucle sur recherche, telechargement, installation et nouvelle recherche jusqu'a absence de mises a jour, puis le workflow attend son resultat avant la fin. Si Windows demande un redemarrage, le logiciel l'indique clairement mais ne redemarre jamais le PC automatiquement.
- Demarrage stable : l'EXE principal reste dans son emplacement de lancement. Le worker PowerShell est installe atomiquement, verifie et execute uniquement depuis `%ProgramData%\LDLCPreparationPC`. Un blocage ou une quarantaine Norton/McAfee produit un message explicite et `LDLC_BOOTSTRAP.log`.
- Distribution : `dist\LDLCPreparationPC.exe` embarque le script, le worker et les images. Le ZIP de livraison contient seulement l'EXE, sa configuration et `SHA256SUMS.txt`. Le PC neuf n'a besoin ni de GitHub ni d'une connexion Google interactive pour envoyer son rapport.
- Compatibilite antivirus : le binaire principal n'utilise plus PS2EXE et ne contient plus le Validator. Il s'agit d'un lanceur .NET Framework qui embarque uniquement le script applicatif. Le build refuse un EXE superieur a 12 Mio afin d'eviter de recreer un conteneur auto-extractible suspect.
- Ressources UI : les images sont decodees et installees atomiquement par le bootstrap. Un fichier deja correct et verrouille est reutilise sans reecriture.
- McAfee/Norton : la detection et la desinstallation s'executent dans un sous-processus limite a 90 secondes. Une erreur, un blocage ou un resultat absent n'arrete jamais le worker principal.
- Les applications utilisent d'abord les installateurs officiels et le cache persistant `C:\LDLC_PREPTOOL\Installers`.
- Winget et Chocolatey sont des fallbacks desactives par defaut pour les applications classiques. Pour les autoriser explicitement : `LDLC_ENABLE_PACKAGE_MANAGER_FALLBACK=1`. Exception NVIDIA : si l'installateur officiel Game Ready echoue, le script peut utiliser `choco upgrade geforce-game-ready-driver` uniquement si Chocolatey est deja present; il ne l'installe jamais.
- Les packages sont valides par executable, registre et version apres installation. Les packages signes sont controles par signataire; 7-Zip utilise un hash SHA-256 de cache car son MSI officiel n'est pas signe.
- GPU : AMD lit la page officielle pour recuperer l'outil Adrenalin Auto-Detect actuel, controle PE et signature, attend ses processus et verifie chaque pilote AMD ainsi que l'application. Le CPU seul ne declenche aucune installation GPU. NVIDIA conserve sa logique officielle et son fallback existant; une configuration mixte traite les deux GPU.
- Suivi 2.6.0 : un RunId stable, mises a jour limitees a une par minute, finalisation durable dans une file locale avant le POST. Windows Update ne desactive plus le suivi du worker principal. Le serveur protege une fin reelle contre un demarrage rejoue.
- Chrome/Adobe : verification Windows de HTTP, HTTPS, .htm, .html et .pdf; UI Automation sans coordonnees fixes, trois tentatives et mini-interface sans activation pendant les deux etapes. Seule une association confirmee est annoncee comme reussie.

## Signature et faux positifs antivirus

Le build accepte `-SigningThumbprint` pour appliquer une signature Authenticode et
`-RequireSignature` pour refuser une publication non signee. Sur un PC de build
officiel, utiliser un certificat de signature de code appartenant a GROUPE LDLC :

```powershell
.\tools\Build-LDLCPreparationPCExe.ps1 -SigningThumbprint "EMPREINTE_CERTIFICAT" -RequireSignature
```

Un executable non signe et nouvellement compile ne peut pas disposer d'une
reputation Norton garantie. En cas de faux positif, mettre Norton a jour puis
soumettre le fichier et l'Alert ID sur le portail officiel :
https://submit.norton.com/. Ne jamais desactiver globalement Norton et ne jamais
autoriser un fichier dont le SHA-256 ne correspond pas a `dist\SHA256SUMS.txt`.
