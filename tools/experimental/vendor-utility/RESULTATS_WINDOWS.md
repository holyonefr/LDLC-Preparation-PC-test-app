# Tests Windows — logiciel constructeur seul

## Dernier résultat GCC : source live et raccourcis validés — 18 octobre 2026

Le run [39152522107](https://github.com/holyonefr/LDLC-Preparation/actions/runs/39152522107),
code `122a837`, Windows Server 2025 / PowerShell 5.1, réussit **86 scénarios /
187 assertions / 0 échec**. La source n'est plus une réponse enregistrée : les deux
cas de Bureau consultent réellement le manifeste officiel et téléchargent son fichier.

| Suite du dernier run | Scénarios | Assertions | Échecs | Nature |
|---|---:|---:|---:|---|
| Utilitaire indépendant | 37 | 85 | 0 | Simulations, contrôle CIM de la VM et COM Windows |
| Raccourcis installateurs | 16 | 64 | 0 | 13 cas simulés, 2 vrais téléchargements/extractions/raccourcis, restauration du Bureau |
| Manifeste et paquet GCC | 33 | 38 | 0 | Données et fichiers inertes, réseau/signatures/extraction simulés |

Sur les deux Bureaux (classique et dossier redirigé « OneDrive - Fixture »), le
raccourci **Installer GIGABYTE Control Center 26.08.28.01.lnk** est créé et relu
par COM. Sa cible existe, les arguments sont vides, son Authenticode est `Valid`,
éditeur **GIGA-BYTE TECHNOLOGY CO., LTD.**, identité produit exacte
**GIGABYTE Control Center**. Le paquet identique est réutilisé, un raccourci tiers
est préservé. Aucun installateur constructeur n'est exécuté, `Installed=false`.
Le matériel et l'absence d'application sont simulés ; ce test ne prouve pas
l'installation ou la compatibilité sur un PC physique, ni une synchronisation OneDrive.

**Méthode retenue :** lecture du manifeste logiciel officiel utilisé par le code
distribué de GCC, puis construction du nom versionné suivant cette même méthode.
Aucune version d'utilitaire n'est épinglée et aucun catalogue ancien n'est utilisé
en repli. Le script ne consulte aucun catalogue de pilotes/BIOS pour ce parcours.

- Manifeste : <https://mb.download.gigabyte.com/FileList/Swhttp/LiveUpdate4/GCC/GIGABYTE%20Control%20Center/ver2.ini>
- Version du programme détectée : **26.08.28.01**.
- Téléchargement retenu : <https://mb.download.gigabyte.com/FileList/Swhttp/LiveUpdate4/GCC/GIGABYTE%20Control%20Center/GIGABYTE%20Control%20Center_26.08.28.01.exe>
- Paquet téléchargé : **52 064 856 octets**, SHA256 `86EF9762C631252958D52C499DDD1EC5334908845A08729FB52EA6088D2C2A10`.
- Ce petit paquet `Liveupdate_GCC` contient aussi MB Update et RGB Sync. Il n'est
  jamais proposé comme cible : les outils portables officiels 7-Zip vérifiés par
  empreintes extraient exclusivement **GIGABYTE Control Center_26.08.28.01.exe**.
- Cœur proposé : **49 095 256 octets**, SHA256 `886A910ABF855F947E6B92921C068CC13C06106951D3EE40CA24CC0B110D2F81`.
  Il correspond au cœur du gros bundle officiel précédemment audité. La version
  du bundle `26.09.10.01` et celle du programme `26.08.28.01` sont deux numérotations
  différentes ; elles ne sont pas comparées comme s'il s'agissait du même fichier.

La provenance du chemin est consignée dans
`evidence/gigabyte-software-manifest-discovery-2026-10-18.json` : analyse statique
des méthodes `Get_DL_Server_Addr` et `Get_Fource_Update_Info_Json_String`, sans
charger une DLL ou exécuter un logiciel constructeur. La preuve native complète
est `evidence/windows-39152522107.json`.

Les simulations refusent notamment un manifeste absent/ambigu ou un autre logiciel,
un dépassement de taille, une interruption, un HTTP 403/délai, une taille HTTP ou
manifeste incohérente, une signature invalide, un hash modifié, une version ancienne,
un wrapper se faisant passer pour le cœur et un module facultatif extrait. Les
portables restent exclus avant réseau et création de raccourcis.

### Essais intermédiaires conservés

| Run | Code | Résultat et portée |
|---|---|---|
| [39151768680](https://github.com/holyonefr/LDLC-Preparation/actions/runs/39151768680) | `f98f443` | Diagnostic : 3 pages officielles renvoient HTTP 403 avec curl système et HttpClient ; curl Git absent, donc non testé |
| [39152229944](https://github.com/holyonefr/LDLC-Preparation/actions/runs/39152229944) | `385065c` | 83 scénarios / 181 assertions / 0 échec, mais candidat pointant encore sur le wrapper ; **ne valide pas l'exclusion des modules**, remplacé |
| [39152385991](https://github.com/holyonefr/LDLC-Preparation/actions/runs/39152385991) | `45f2fae` | 86 scénarios / 167 assertions / 2 échecs : l'en-tête 7-Zip désigne l'archive externe avec le même nom que le cœur, pris à tort pour une entrée dangereuse |
| [39152522107](https://github.com/holyonefr/LDLC-Preparation/actions/runs/39152522107) | `122a837` | **86 / 187 / 0**, correction `-ba` qui liste seulement les entrées, cœur signé et raccourcis réels validés |

Toutes les preuves sont conservées dans `evidence/windows-<run>.json`. Les anciens
constats de blocage des pages web ci-dessous restent historiques ; le script utilise
désormais le manifeste officiel logiciel qui fonctionne sur Windows GitHub.

---

Le 17 octobre 2026, workflow manuel `vendor-utility.yml`, Windows Server 2022 et
Windows PowerShell 5.1. Aucun installateur constructeur exécuté, aucun pilote/BIOS installé.

| Passage réel GitHub Actions | Code testé | Scénarios | Assertions | Échecs |
|---|---|---:|---:|---:|
| [39050640575](https://github.com/holyonefr/LDLC-Preparation/actions/runs/39050640575) | `95c8b70` | 29 | 60 | 0 |
| [39051027579](https://github.com/holyonefr/LDLC-Preparation/actions/runs/39051027579) | `1024ef8` | 35 | 66 | 0 |

## Ce qui est simulé

- Identification MSI/ASUS/GIGABYTE/ASRock et refus OEM/portable/VM/inconnu/Windows incompatible.
- Installation minimale fictive, jamais un installateur matériel réel : succès suivi d'une
  preuve d'application, erreur 1603, annulation 1223, redémarrage imposé 1641 refusé,
  code 3010 avec redémarrage laissé au technicien, délai/interruption.
- Retour 0 sans application : échec ; versions numériques (`1.10 > 1.9`) ; installateur
  modifié/empreinte inconnue ; erreur réseau et Bureau inaccessible.
- Vérification des paquets MSI : famille exacte, manifeste/exécutable, signature Store,
  refus développement, mauvaise famille, application absente, entrée SDK/orpheline.
  Les objets de paquets sont des fixtures, pas des applications réellement installées.

## Ce qui est réellement exécuté sous Windows

- Requêtes CIM d'identification et refus de la VM GitHub, sans installation.
- Création et relecture COM d'un `.lnk` pointant vers un fichier inerte jamais exécuté,
  sur un Bureau utilisateur redirigé vers un dossier de test « OneDrive - Fixture ».
  Restauration de la redirection dans `finally`, réutilisation du raccourci identique
  et préservation d'une cible différente. Ce test ne connecte pas un compte OneDrive.
- Appel du vrai lanceur avec la variable GitHub activée : refus avant tout processus.

Les deux preuves JSON sont dans `evidence/`. La deuxième série ajoute six scénarios
à la première. Localement, PowerShell 7 a aussi passé 33 scénarios/57 assertions ;
cela ne remplace pas les deux contrôles natifs Windows supplémentaires.

## Limites et essai requis sur PC

Aucun profil automatique réel n'est activé : aucune méthode n'a encore démontré
toutes les contraintes d'installation minimale dans cette étude. Le téléchargement MSI réel antérieur
est vérifié (EXE 2.0.74.0, Authenticode valide), mais ne prouve ni installation, ni dernière
version, ni compatibilité de chaque modèle. Voir les preuves de l'étude voisine.

Sur un PC physique compatible, il reste à établir la procédure officielle minimale,
vérifier l'absence de modules facultatifs/ouverture/recherche et confirmer le programme
installé et son raccourci. Ne pas activer une installation automatique à partir des seules
simulations ou d'arguments génériques d'un moteur d'installation.

## Inspection statique MSI : premiers essais interrompus, puis correction

Les essais d'inspection `39037037064` et `39050576230` n'ont pas fourni de
rapport exploitable : le premier a atteint la limite de vingt minutes, le
second a été arrêté après blocage. L'essai instrumenté
[39051301298](https://github.com/holyonefr/LDLC-Preparation/actions/runs/39051301298)
a également dépassé six minutes sans rapport final ; il a été annulé. Les traces
récupérées après arrêt confirment néanmoins le téléchargement complet MSI, sa
signature valide, et les opérations de liste et extraction statiques terminées
avec un code 0. Le rapport final manque : le blocage est donc postérieur à ces
opérations, sans cause exacte démontrée. Voir `evidence/inspection-39051301298.json`.
Ces essais ne sont **pas** des tests réussis et n'établissent pas la cause exacte
du blocage. Ils n'ont exécuté aucun installateur constructeur : le seul outil
externe demandé est un extracteur statique portable dont l'empreinte est épinglée.

Le workflow borne désormais cette étape de recherche à huit minutes, en plus des
limites internes. Cette borne ne concerne pas Windows Update ni les applications
principales. Aucun profil réel n'a été activé à partir de ces essais incomplets.

### Inspection corrigée terminée

[39051962775](https://github.com/holyonefr/LDLC-Preparation/actions/runs/39051962775),
code `00150b0`, job `117452198460` : succès réel sous Windows. Étape d'inspection
terminée en **22 secondes** ; l'étape de validation simulée est volontairement
ignorée dans ce mode. Le traitement des métadonnées est désormais borné et ne
parcourt plus récursivement l'arborescence du contenu extrait. Les premières
traces ne permettent pas d'attribuer avec certitude le blocage à une seule de
ces modifications.

Téléchargement officiel MSI complet : **584 849 764 octets**, EXE **2.0.74.0**,
signature valide **MICRO-STAR INTERNATIONAL CO., LTD.** Empreintes identiques
aux téléchargements réels précédents. La liste et l'extraction statiques ont
retourné 0, un `install_script.iss` a été lu, sans troncature signalée. Preuve :
`evidence/inspection-39051962775.json`.

Le paquet est un Inno Setup **5.4.2 Unicode Custom**. Les actions récupérées
appellent `setup.ps1 -Force`, `SetAccessRight.exe` et un provisionnement Appx
via DISM avec `nowait`. Cela ne constitue pas une méthode MSI officiellement
confirmée d'installation minimale sans lancement ni composants supplémentaires.
Les directives récupérées ne prouvent pas l'ensemble du comportement du code
personnalisé ou des exécutables auxiliaires. Aucun argument silencieux générique
n'a donc été promu en profil réel ; **aucune installation automatique réelle
n'est activée**, pour aucun des quatre fabricants. Le repli manuel reste explicite.

### Lecture réelle du script interne, sans exécution

[39052097956](https://github.com/holyonefr/LDLC-Preparation/actions/runs/39052097956),
code `3bfdde7`, job `117452614141` : succès. Le script officiel `setup.ps1`
(1 212 octets) est extrait et lu comme texte uniquement. Il confirme le nom
`9426MICRO-STARINTERNATION.MSICenter`, retire les inscriptions/provisionnements
MSI Center existants (dont une commande `Remove-AppxPackage -AllUsers`), nettoie
les anciens dossiers de provisionnement puis appelle `Add-AppxPackage`.
Il ne démontre pas une méthode minimale officiellement supportée, sans effets
sur les inscriptions des autres utilisateurs ni comportement supplémentaire du
code personnalisé et du binaire auxiliaire. La politique reste donc manuelle.

Preuve complète : `evidence/inspection-39052097956.json`. Ce succès valide le
**téléchargement et la lecture statique** ; il ne valide aucune installation
réelle ou simulation d'installation supplémentaire. Aucun nouvel essai de scan,
pilote, firmware ou mise à jour n'a été ajouté.

## Détection officielle et téléchargements signés — 17 octobre

[39059978420](https://github.com/holyonefr/LDLC-Preparation/actions/runs/39059978420),
code `62369ab`, job `117475752843` : **succès**, 79 scénarios / 183 assertions / 0 échec.
35 scénarios concernent le prototype et 44 la détection ASUS (43 fixtures + 1 téléchargement réel).
Le raccourci COM et la détection CIM sont réels ; les installations restent simulées.

ASUS détecté par son manifeste : **1.0.7.1**, **5 168 024 octets** complets,
signature **ASUSTeK COMPUTER INC.** valide, SHA256
`C52343E16B608359223DF33EDC8D5789E7FEF4D2612986A883D29D915B76FF90`.
Lien retenu : `https://driverhub.asus.com/download/1.0.7.1/ASUS-DriverHub-Installer.exe`.
Le point de géolocalisation ne sert pas d'installateur. Le chemin plat servant une
ancienne version ne sert jamais de secours à une détection actuelle en échec.

Un audit séparé vérifie le snapshot ASRock **2.0.0.4** signé. Il ne constitue pas
un contrôle de dernière version et n'est pas utilisé par la nouvelle détection.
Preuve : `evidence/windows-39059978420.json`.

## Première passe approfondie — 18 octobre : échecs conservés

[39127513373](https://github.com/holyonefr/LDLC-Preparation/actions/runs/39127513373),
code `9dac485`, job `117675662952` : **échec global**, aucun installateur exécuté.

| Étape | Résultat réel |
|---|---|
| Prototype indépendant | 35 scénarios, 74 assertions, 0 échec |
| Détection ASUS | 44 scénarios, 116 assertions, 0 échec ; 1.0.7.1 téléchargée et signée |
| Détection ASRock | 54 scénarios, 115 assertions, 0 échec ; 2.0.0.9 téléchargée et signée |
| Détection GCC sur fixtures | 34 scénarios, 85 assertions, 0 échec |
| Audit GCC actuel depuis Windows | HTTP 403 du catalogue officiel ; aucun téléchargement effectué par cette étape |
| Audit MSI Appx | Bootstrap et bundle téléchargés/signatures valides ; lecture du paquet interne en échec |
| Inspection ASRock actuelle | Téléchargement terminé puis helper `Write-MbxEvidence` inaccessible après import imbriqué |
| Vérification des paquets sur fixtures | 17 échecs sur 26 : assembly ZIP non chargé explicitement sous PowerShell 5.1 |

Corrections : chargement `System.IO.Compression`, remise à disposition du helper
dans l'audit ASRock, gestion des noms de parties OPC (`%20`) des paquets Appx.
Une fixture de paquet ancien et une fixture de noms encodés dupliqués protègent
le correctif Appx ; aucune sélection de version plus ancienne autorisée.
Le refus HTTP n'est pas masqué : un mode explicite d'audit de réponse enregistrée
permet un contrôle distinct du téléchargement GCC, sans présenter la détection
du catalogue comme réussie sur Windows. La réponse officielle a été réellement
reçue HTTP 200 dans le cloud le même jour ; elle n'est pas un catalogue actuel garanti.

ASRock réel : modèle **B650M Pro RS**, Windows 11 x64, version **2.0.0.9**,
ZIP **5 275 382 octets** complets, signature **ASROCK INC.** valide.
SHA256 ZIP `2373443D3C5FAA717937F692B0F3DE5D2DB987197F29B523B305F65C5E9DC7A9` ;
SHA256 EXE `80E7078E81C4BD312D341B9CCC32631D72C188DBECA90A78F8E6765BA3C7AA83`.
Source : `https://www.asrock.com/support/LiveUpdate.asp?Platform=App&Model=B650M%20Pro%20RS` ;
lien retenu : `https://download.asrock.com/Utility/Others/APPShop(v2.0.0.9).zip`.
Méthode `official_asrock_model_xml`, sans repli vers 2.0.0.4.
Preuve : `evidence/windows-39127513373.json`.

## Passe corrigée — 18 octobre : succès natif

[39127977792](https://github.com/holyonefr/LDLC-Preparation/actions/runs/39127977792),
code **`b950fef`**, job **`117677019937`**, Windows Server 2022 / Windows PowerShell 5.1 :
**succès global, 212 scénarios / 501 assertions / 0 échec**, plus les trois audits
réels de contenu/signature ci-dessous. Preuve complète : `evidence/windows-39127977792.json`.

| Suite | Scénarios | Assertions | Échecs |
|---|---:|---:|---:|
| Prototype : simulations + CIM/COM natifs | 35 | 75 | 0 |
| ASUS : 43 fixtures + téléchargement réel | 44 | 116 | 0 |
| ASRock : 53 fixtures + catalogue/téléchargement réels | 54 | 115 | 0 |
| GCC : catalogues simulés, versions numériques et refus d'incohérence | 37 | 88 | 0 |
| MSI : ZIP/XML/Appx inertes, noms OPC et ambiguïtés | 16 | 35 | 0 |
| Paquets : ZIP/hash réels inertes, téléchargement/signature simulés | 26 | 72 | 0 |
| **Total** | **212** | **501** | **0** |

208 scénarios utilisent des données ou frontières simulées ; 4 sont les contrôles
natifs CIM, raccourci COM, ASUS et ASRock. Aucun de ces contrôles ne lance un logiciel
constructeur. Les audits suivants sont séparés du compte de scénarios.

### GIGABYTE : téléchargement réel, catalogue Windows toujours non validé

La consultation réelle du catalogue a reçu HTTP 403 dans la première passe. La
passe corrigée utilise **explicitement** la réponse officielle reçue HTTP 200 dans
le cloud le 18 octobre, conservée comme fixture. Elle ne démontre ni la disponibilité
actuelle de ce catalogue depuis Windows, ni une détection live réussie sur le runner.
Le JSON porte `CatalogueMode=recorded_response_2026-10-18_not_live_on_runner`.
Ce mode d'audit n'est jamais un repli de l'application vers une version antérieure.

Le téléchargement de `GCC_26.09.10.01.zip` depuis `download.gigabyte.com` est bien
**réel et complet : 902 526 290 octets**, SHA256
`B046A63AD3D53675017EBA4B1F58DEEF3D4297591A59B9A4FB9704D5001F2F1B`.
Lien : `https://download.gigabyte.com/FileList/Utility/GCC_26.09.10.01.zip?v=bd7c81fc9b9052caa13e7f70b0252f9e`.
Signatures Windows valides **GIGA-BYTE TECHNOLOGY CO., LTD.** pour :

- le programme externe 26.09.10.01 ;
- le cœur `GIGABYTE Control Center_26.08.28.01.exe`, 49 095 256 octets,
  SHA256 `886A910ABF855F947E6B92921C068CC13C06106951D3EE40CA24CC0B110D2F81` ;
- l'application `GCC.exe`, 25.09.12.1, 35 425 448 octets,
  SHA256 `16060ADA087A376BDCB35D9EA3B4FCCC8C6E865C24BE53879C91E8456A7B3937`.

Extraction 7-Zip uniquement. Aucun programme externe, cœur ou application exécuté.
Leurs versions appartiennent à des couches différentes, pas à trois versions
concurrentes à choisir arbitrairement. Le bundle complet n'est pas un installateur
minimal acceptable pour la demande.

### MSI : bundle et paquet x64 réellement lus et signés

Le bootstrap officiel est téléchargé de nouveau, même version/hash que les essais
précédents. Son bundle Appx **583 364 515 octets** et le paquet x64 interne
**583 354 219 octets** ont tous deux une signature Windows **Valid**, chaîne Microsoft
Marketplace. SHA256 du paquet x64 :
`7311BCBFD30958A90A68A9D38CD078D827C0D84D1F85A9170418C11F74A41042`.

Le correctif OPC permet de retrouver l'entrée ZIP encodant les espaces du nom
`MSI Center_2.0.74.0_x64.appx`. Les fixtures refusent un nom ancien et les doublons
raw/encodé. Aucun contrôle d'intégrité n'est contourné.

Le manifeste réel confirme l'identité MSI Center **2.0.74.0**, application
`DCv2\DCv2.exe`, et une tâche **`MSI_Center_UWP` avec `Enabled=true`**, pointant vers
`DCv2\DCv2_Startup.exe`. Cela établit une déclaration de démarrage, pas son exécution
effective dans toutes les configurations Windows. L'installation sans lancement
automatique reste donc non démontrée. Aucun Appx enregistré ; aucune acquisition
Store actuelle, aucun SDK ni programme auxiliaire exécuté.

### ASRock : version courante et extraction confirmées

Le catalogue par modèle résout de nouveau **2.0.0.9**, avec les mêmes empreintes et
signature valides que la première passe. L'inspection utilise cette version courante,
pas le snapshot 2.0.0.4. Liste et extraction : **codes 0**, un script récupéré,
aucune troncature. Version Inno **6.4.3** ; lancement normal `SkipIfSilent`, chemin
`AsrAPPShop.exe`, helper temporaire `RM_AsrDrv.exe` confirmé dans la liste des fichiers.
La lecture statique complémentaire du code compilé et du helper, effectuée localement,
identifie le nettoyage avant installation décrit dans RECHERCHE_APPROFONDIE.md.
Ce nettoyage n'a jamais été exécuté ; ses effets réels restent à vérifier sur PC.

### Ce qui reste impossible à conclure

Le succès du workflow prouve les comportements testés, pas une installation matérielle
réelle. Aucun profil automatique réel n'est activé, aucune garantie universelle de
compatibilité/raccourci des quatre marques. En particulier, la reconnaissance de GCC
installé reste à adapter à ses métadonnées réelles. Les essais physiques doivent vérifier
installation complète, raccourci fonctionnel, absence d'ouverture/recherche automatique
et absence d'actions supplémentaires. Les trois applications principales ne sont pas
modifiées. Les téléchargements MSI/ASUS/ASRock/GCC et les simulations sont clairement
distincts des vérifications qui exigent encore un PC physique compatible.

Reproduction : lancer manuellement `vendor-utility.yml`, phase `deep-research`.
`gcc_catalogue=live` exige la consultation actuelle du catalogue Windows ;
`gcc_catalogue=recorded-audit` teste explicitement le téléchargement issu de la capture.
Ne jamais présenter le second mode comme une validation du premier.

## Comparaison Windows GitHub 2025 — 18 octobre

À la demande de refaire l'essai sur Windows GitHub, la même batterie est exécutée
sur une seconde image Windows. Aucun script du prototype n'est modifié entre les
deux passages : seules la sélection du runner et la collecte de ses versions sont ajoutées.

| Environnement GitHub | Passage | Code testé | Scénarios | Assertions | Échecs |
|---|---|---|---:|---:|---:|
| Windows Server 2022 / PowerShell 5.1 | [39127977792](https://github.com/holyonefr/LDLC-Preparation/actions/runs/39127977792) | `b950fef` | 212 | 501 | 0 |
| Windows Server 2025 / PowerShell 5.1 | [39137210458](https://github.com/holyonefr/LDLC-Preparation/actions/runs/39137210458) | `4df3ba3` | 212 | 501 | 0 |

Second job **117704061728**, conclusion **success**. L'environnement effectivement
observé est `Microsoft Windows Server 2025 Datacenter`, build `10.0.26100`, x64,
PowerShell **5.1.26100.33438**, image **win25-vs2026 / 20261007.264.1**.
La version CLR observée est `4.0.30319.42000` ; elle ne décrit pas à elle seule la
version commerciale complète du .NET Framework.

Comparaison des preuves JSON : mêmes comptes et aucun nouvel échec, ASUS **1.0.7.1**
et ASRock **2.0.0.9**, mêmes octets et empreintes de téléchargement, signatures valides.
Les empreintes du bundle/cœur/application GCC et du bundle/Appx MSI sont également
identiques. L'inspection ASRock conserve ses deux codes 0 et aucune troncature.
Le manifeste MSI déclare toujours sa tâche de démarrage `Enabled=true`.

La portée reste identique : téléchargements et contrôles de signature réellement
exécutés sur Windows ; installations avec données simulées uniquement. Le catalogue
GCC de cette passe est la réponse officielle enregistrée, **pas une nouvelle détection
live sur Windows 2025**. Aucun logiciel constructeur installé ou lancé, aucune
installation matérielle et aucune compatibilité physique prouvées. Les limites du
rapport précédent restent applicables ; pas d'activation des profils automatiques.

Preuve : `evidence/windows-39137210458.json`. Reproduction : workflow manuel
`vendor-utility.yml`, `phase=deep-research`, `windows_runner=windows-2025`,
`gcc_catalogue=recorded-audit`. Le choix `windows-2022` reste le défaut.

## Raccourci Bureau vers l'installateur — 18 octobre

Demande utilisateur : disposer du raccourci pour ouvrir l'installateur téléchargé.
Implémentation limitée au script indépendant ; aucun changement des applications
principales. Le téléchargement n'est pas déclaré installé et aucun installateur lancé.

Après vérification du paquet, la cible est copiée dans le dossier local de l'utilisateur
`VendorUtility/Installers/{fabricant}/{version}/{SHA256}/Setup.exe`. Signature, empreinte
et version sont recontrôlées avant création du raccourci sur le vrai Bureau Windows.
Le nom est par exemple **Installer ASRock APP Shop 2.0.0.9.lnk** ; la version est résolue
dynamiquement. La cible ne dépend pas du fichier temporaire ni de la durée de vie du script.
Un paquet identique réutilise le même emplacement et le même raccourci. Un raccourci
existant pointant ailleurs est conservé et signalé. Aucun argument silencieux n'est ajouté.

`InstallerShortcut` et `InstallerVersion` sont distincts de `Shortcut`, réservé à une
application déjà installée et reconnue. Statut `manual_required`, `Installed=false` :
il reste au technicien à ouvrir le raccourci. Les portables sont exclus avant téléchargement,
détection d'application ou raccourci, y compris si le logiciel est déjà installé.
Le bundle GCC avec composants facultatifs n'est pas proposé par ce mécanisme.

[39149548075](https://github.com/holyonefr/LDLC-Preparation/actions/runs/39149548075),
code **5c1a17c**, job **117740191091**, Windows Server 2025 / PowerShell 5.1 :
**succès, 52 scénarios / 136 assertions / 0 échec**.

| Suite ciblée | Scénarios | Assertions | Échecs |
|---|---:|---:|---:|
| Prototype, refus portables et erreurs Bureau/réseau, CIM/COM natifs | 37 | 81 | 0 |
| Raccourci installateur, cache permanent et contrôles natifs ASRock | 15 | 55 | 0 |

Les 12 cas locaux du nouveau helper utilisent des fichiers inertes et une signature
simulée ; ils couvrent notamment les copies persistantes, répétitions, mutation du fichier
ou du cache, ancienne version, signature/hash invalides et Bureau inaccessible.
Les tests de flux utilisent aussi des frontières simulées pour les erreurs et portables.

Deux contrôles supplémentaires passent **réellement sous Windows** via le flux
`Invoke-VendorUtility` : une fixture de carte mère **B650M Pro RS / Windows 11 x64**
remplace l'identité de la VM et l'absence d'application est simulée ; le catalogue,
le téléchargement ASRock, Authenticode, la copie, le dossier spécial Bureau et la
création/relecture COM des `.lnk` sont réels. Un contrôle utilise un Bureau classique
de test, l'autre une redirection réelle vers un dossier « OneDrive - Fixture ».
Il ne s'agit pas d'une connexion OneDrive réelle ni d'une carte mère ASRock physique.

Les deux passages obtiennent **2.0.0.9**, signature **ASROCK INC. Valid**, SHA256 EXE
`80E7078E81C4BD312D341B9CCC32631D72C188DBECA90A78F8E6765BA3C7AA83`.
Le `.lnk` pointe bien vers le fichier présent, avec **arguments vides** ; répétition
sans doublon et préservation d'un raccourci tiers vérifiées. Le Bureau initial est
restauré après les tests, puis seuls les fichiers de test sont nettoyés. Aucun
installateur exécuté, aucune installation ni pilote/BIOS modifié.

Preuve : `evidence/windows-39149548075.json`. Reproduction : workflow manuel
`vendor-utility.yml`, `phase=installer-shortcut`, `windows_runner=windows-2025`.

## Raccourcis MSI, ASUS et GIGABYTE — 18 octobre

Le même mécanisme est étendu aux autres fabricants. MSI et ASUS réutilisent leurs
téléchargements officiels vérifiés. Pour GIGABYTE, la version du bundle courant
est résolue depuis une source officielle, le programme externe est signé et sa
version contrôlée, puis **seul le cœur Control Center** est extrait et signé.
Un bundle ambigu, incomplet, modifié, sans cœur unique ou avec une mauvaise version
est refusé. Aucune cible Bureau vers le lanceur `All_Setup` avec modules facultatifs.

L'extraction ne dépend pas d'une installation préalable de 7-Zip. Le script obtient
les outils portables officiels [7-Zip 26.04](https://github.com/ip7z/7zip/releases/tag/26.04)
et vérifie les empreintes avant tout appel. Il lit le setup 7-Zip comme une archive
avec `7zr.exe` pour extraire `7z.exe` et `7z.dll`, sans lancer ce setup ni installer 7-Zip.
L'outil appelé doit avoir un nom et une empreinte approuvés ; aucun exécutable constructeur
ne peut être utilisé comme décompresseur. Hashes approuvés :

| Fichier de l'outil | SHA256 |
|---|---|
| 7zr.exe | `256FECA8E274E5DA655E2A284FABAFD9F554365EB164862089DACD4E8276D282` |
| 7z2604-x64.exe, lu comme archive uniquement | `D54BF805F9F3704D1E8DB2FA3498AE7EF2DF0312B40B558E7C71C734430A665D` |
| 7z.exe extrait | `95FFF19B73EFF77C87C0D7BD32822E43FB90DD2932459F962EB532D8DFB6BA53` |
| 7z.dll extrait | `899CD73D7FC60E1C1C35C7DE0F5BED3DC69BFE2CECBD48014D868A347970A0B1` |

Ces versions épinglent l'outil d'archive ; elles ne fixent pas la version du logiciel
GIGABYTE. Les versions bundle et cœur restent distinctes. Le nom du raccourci conserve
le numéro officiel du cœur, y compris ses zéros, sans le comparer à celui du bundle.

### Sources live : MSI et ASUS réussissent, GCC reste bloqué

[39150418739](https://github.com/holyonefr/LDLC-Preparation/actions/runs/39150418739),
code **fa1fec0**, job **117742744266**, Windows Server 2025 / PowerShell 5.1 :
**117 scénarios / 286 assertions / 2 échecs**, conclusion globale **failure**.
Les deux échecs concernent exclusivement la consultation live GCC, sur les deux
types de Bureau. Toutes les suites simulées et les contrôles MSI/ASUS ont réussi.

| Fabricant | Contrôles natifs Bureau classique + redirigé | Fichier cible réel |
|---|---|---|
| MSI | Réussis : téléchargement, signature, copie, création/relecture COM, répétition et conflit | MSI Center **2.0.74.0**, signé MICRO-STAR INTERNATIONAL CO., LTD. |
| ASUS | Réussis, mêmes contrôles | ASUS DriverHub **1.0.7.1**, signé ASUSTeK COMPUTER INC. |
| GIGABYTE | Échec avant téléchargement/shortcut | Trois sources/clients officiels renvoient HTTP 403 ; aucun ancien fichier proposé |

Empreintes des cibles MSI et ASUS identiques aux précédents téléchargements signés :
MSI `95E6BE38ED8F1A0AD5055C9831DAB057F2B0BBA0EB33A25EB60A9486FD0D3EBD` ;
ASUS `C52343E16B608359223DF33EDC8D5789E7FEF4D2612986A883D29D915B76FF90`.
Les raccourcis s'appellent **Installer MSI Center 2.0.74.0.lnk** et
**Installer ASUS DriverHub 1.0.7.1.lnk**, cible présente, arguments vides,
sans lancement du programme. La carte mère et l'absence d'application sont des
fixtures ; tous ces contrôles fichier/signature/Bureau sont réels sous Windows.

Les trois tentatives GCC sont : catalogue officiel avec client par défaut, même
catalogue avec en-tête navigateur, puis page officielle du produit. Les trois
réponses restent **HTTP 403** dans les deux essais. Aucune cause plus précise
de ce refus n'est établie ; il n'est pas transformé en succès ou masqué par une
ancienne version. Preuve : `evidence/windows-39150418739.json`.

### GCC : extraction et raccourci réels, consultation du catalogue simulée

Pour vérifier le nouveau mécanisme malgré ce refus, le test utilise **explicitement**
la réponse officielle enregistrée du 18 octobre. Cette substitution est limitée
au script de test ; le script utilisateur consulte toujours les sources live.

[39150779657](https://github.com/holyonefr/LDLC-Preparation/actions/runs/39150779657),
code **1fffa1d**, job **117743804727**, Windows Server 2025 / PowerShell 5.1 :
**113 scénarios / 258 assertions / 0 échec**, conclusion **success**.

| Suite | Scénarios | Assertions | Échecs |
|---|---:|---:|---:|
| Prototype, refus portables, CIM/COM | 37 | 83 | 0 |
| Raccourcis : 13 cas inertes + 2 contrôles GCC + restauration du Bureau | 16 | 60 | 0 |
| Détection GCC sur catalogues simulés | 39 | 92 | 0 |
| Paquets/extraction GCC avec fichiers inertes et frontières simulées | 21 | 23 | 0 |

Dans les deux contrôles GCC, le téléchargement de l'archive officielle **26.09.10.01**,
les outils portables, l'extraction du cœur, sa signature, la copie persistante et
les raccourcis sont **réels**. La résolution du catalogue et le matériel restent
des fixtures explicites. Le `.lnk` réel s'appelle
**Installer GIGABYTE Control Center 26.08.28.01.lnk**, cible présente, arguments vides.
SHA256 cœur `886A910ABF855F947E6B92921C068CC13C06106951D3EE40CA24CC0B110D2F81`,
signature **GIGA-BYTE TECHNOLOGY CO., LTD. Valid**. Répétition sans doublon et
préservation d'un raccourci tiers confirmées sur les deux types de Bureau.

Le JSON porte `CatalogueMode=recorded_official_response_not_live`. Ce succès ne
valide donc **pas** la consultation live GCC depuis Windows. La résolution réelle
recontrôlée dans le cloud Linux le même jour sélectionne encore 26.09.10.01 ;
preuve séparée `evidence/gigabyte-current-cloud-2026-10-18.json`. Cela ne remplace
pas un test de cette consultation sur Windows.

Preuve complète : `evidence/windows-39150779657.json`. Aucun installateur constructeur
ou setup 7-Zip exécuté ; aucune installation, pilote ou BIOS modifié. Les portables
restent exclus. **Bilan : préparation du raccourci validée avec source live pour
ASRock, MSI et ASUS ; GCC reste partiellement validé à cause du HTTP 403.**
Les installations elles-mêmes restent manuelles et ne sont pas déclarées validées.

Reproduction : workflow `vendor-utility.yml`, phase `other-installer-shortcuts`,
`windows_runner=windows-2025`. `gcc_catalogue=live` teste MSI/ASUS/GCC avec sources
live ; `recorded-audit` teste uniquement le téléchargement/cœur/raccourci GCC depuis
la réponse enregistrée. Ne jamais confondre les deux résultats.
