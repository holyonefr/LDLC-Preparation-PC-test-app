# Catalogues alternatifs — vérifications des 17 et 18 octobre 2026

Le repli manuel existant indique une méthode non validée dans ce prototype.
Il ne constitue pas la preuve qu'aucun gestionnaire de paquets ne propose le logiciel.

## WinGet : MSI Center trouvé, fiche en retard sur le fichier officiel vérifié

Le répertoire `manifests/m/MSI/MSICenter` du dépôt Microsoft `winget-pkgs`
contient uniquement `2.0.72` lors de cette consultation.
[Manifeste consulté](https://github.com/microsoft/winget-pkgs/blob/master/manifests/m/MSI/MSICenter/2.0.72/MSI.MSICenter.installer.yaml).

- Identifiant : `MSI.MSICenter`, architecture x64, ZIP avec installateur Inno.
- URL : `https://download-2.msi.com/uti_exe/desktop/MSI-Center.zip`.
- SHA-256 attendu par cette fiche : `86F0328F9EFCD3B4D9FEFCCFC8D8B66462ECA589F565269D1890213C103B1C33`.
- Le fichier réellement téléchargé dans les essais Windows documentés contient
  **2.0.74.0**, SHA-256 ZIP `FBFA35A0CD8B4A71F6F0CAC5090C50A97D082E1F5F93D5B95493526A34032E96`.

L'URL non versionnée sert donc un autre fichier que celui décrit par cette fiche.
Une commande utilisant cette fiche ne peut pas être considérée fonctionnelle avec
ces données ; le refus d'empreinte doit rester actif. Aucune installation WinGet
n'a été exécutée pour cette vérification et aucun contrôle d'intégrité n'a été désactivé.

La fiche confirme la famille `9426MICRO-STARINTERNATION.MSICenter_kzh8wxbdkxb8p`.
Une piste distincte est le Microsoft Store, identifiant cité dans plusieurs scripts
de déploiement publics : `9NVMNJCR03XV`. Ces références tierces ne valident ni la
disponibilité actuelle de l'offre Store ni son installation. Cette voie reste à tester.

## Autres applications WinGet recherchées

Aucune correspondance trouvée pour ASUS DriverHub, GIGABYTE Control Center ou
ASRock APP Shop dans les répertoires éditeurs et recherches de code consultés.
Le répertoire `Asus` propose notamment Armoury Crate, BIOSConfigTool,
DisplayWidgetCenter et GpuTweak3 ; `GIGABYTE` propose BIOS, DRMFixTool et RGBFusion.
Ces applications ne remplacent pas les logiciels demandés. Une recherche négative
ne prouve pas une absence définitive ou l'absence d'une offre Store distincte.

## Chocolatey et Ninite : nouvelles consultations directes réussies

Les premiers refus HTTP 403 ont été suivis de réponses HTTP 200 dans cette étude.
Les résultats suivants remplacent donc le constat initial d'accès impossible :

- **Chocolatey propose bien [app-shop 1.0.31](https://community.chocolatey.org/packages/app-shop/1.0.31)**.
  Fiche datant de 2018, test de paquet marqué `Failing` au 17 septembre 2026,
  ancienne URL HTTP BitGravity. Ce paquet ne convient pas : ASRock propose maintenant
  2.0.0.9 pour les modèles compatibles vérifiés. Ne pas installer l'ancien paquet.
- Les recherches ciblées Chocolatey n'ont pas trouvé de fiche exacte MSI Center,
  ASUS DriverHub ou GIGABYTE Control Center. EasyTune6 ne remplace pas GCC.
  Cela décrit les recherches effectuées, sans garantir l'absence de tout paquet tiers.
- Le sélecteur public [Ninite](https://ninite.com/) consulté ne propose aucun des quatre
  produits. Cela ne démontre rien sur d'éventuelles offres privées Ninite Pro.
- L'arbre complet public de [Scoop Extras](https://github.com/ScoopInstaller/Extras/tree/master/bucket)
  consulté ne contient pas ces quatre utilitaires. Les paquets de compilateur GCC sont
  sans rapport avec GIGABYTE Control Center.

UniGetUI regroupe des gestionnaires ; il ne corrige pas une version ou une empreinte
obsolète dans leur catalogue. Les liens des forums aident à retrouver les méthodes,
mais seuls les fichiers officiels et leur contenu sont utilisés pour l'audit.

## Microsoft Store : piste distincte encore non validée

L'API Store et la page `apps.microsoft.com` restent refusées par le proxy de ce cloud
lors des tentatives documentées. Le brouillon réseau contient les domaines nécessaires ;
sa sauvegarde ne vaut pas activation. Aucun paquet Store actuel n'a donc été acquis
ou installé. Le mécanisme Store utilisé par WinGet est étudié dans son code source,
mais ne constitue pas une preuve de fonctionnement MSI Center dans cette session.

L'API `AppInstallManager` est réservée aux applications Microsoft selon sa documentation ;
un wrapper PowerShell maison n'est pas une alternative officielle pour forcer ses options.
L'inspection du bundle Appx fourni dans le téléchargement MSI est une vérification
distincte de cette offre Store. Voir [RECHERCHE_APPROFONDIE.md](RECHERCHE_APPROFONDIE.md).

## État du prototype

Aucun profil réel activé sur la seule base d'une fiche de catalogue. Les
installations via gestionnaire, leurs éventuels lancements et leurs composants
ne sont pas encore validés. Les applications principales restent inchangées,
et l'exclusion des portables intervient avant le téléchargement et le raccourci.
