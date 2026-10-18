# Logiciels constructeurs seuls : recherche approfondie

Observations des 17–18 octobre 2026. Prototype PowerShell indépendant, jamais appelé
par les applications principales. Aucun installateur constructeur exécuté sur GitHub
Actions ou dans ce cloud. Les extractions utilisent uniquement des outils d'archive.
Les versions ci-dessous sont des observations datées, jamais un repli « dernière version ».

## Conclusion opérationnelle

Les méthodes silencieuses existent, mais leurs effets doivent aussi respecter les
contraintes demandées. Un `/S` ou `/VerySilent` ne démontre pas, à lui seul, une
installation limitée à l'application, sans démarrage, recherche ou action matérielle.
Les quatre profils automatiques restent désactivés. Un téléchargement vérifié
n'est jamais déclaré installé. Les portables sont exclus avant réseau et raccourci.

| Fabricant | Résultat concret de la recherche | Vérification restante sur PC compatible |
|---|---|---|
| MSI | Archive officielle 2.0.74.0 et Appx interne signés ; manifeste avec tâche de démarrage activée | Installation réellement complète, absence de démarrage automatique, SDK et effets des auxiliaires |
| ASUS | Manifeste dynamique et installateur 1.0.7.1 signé vérifiés ; paramètres silencieux retrouvés | Méthode officielle empêchant les auxiliaires et vérifications de catalogue automatiques |
| GIGABYTE | Bundle 26.09.10.01 et installateur du cœur 26.08.28.01 séparables statiquement | Installation du cœur sans le bundle facultatif et sans démarrage au prochain logon |
| ASRock | Catalogue par modèle/OS : APP Shop 2.0.0.9, SHA256 et `/VerySilent` officiels | Effets du nettoyage de services/pilotes existants avant installation et comportement final |

## MSI Center

Sources : [page officielle](https://www.msi.com/Landing/MSI-Center),
[archive officielle](https://download-2.msi.com/uti_exe/desktop/MSI-Center.zip),
[discussion WinGet 407476](https://github.com/microsoft/winget-pkgs/pull/407476).
La page propose aussi une archive Norton distincte : sélectionner le premier ZIP
de la page serait incorrect. Aucun téléchargement Norton utilisé.

L'archive observée fait **584 849 764 octets**, SHA256
`FBFA35A0CD8B4A71F6F0CAC5090C50A97D082E1F5F93D5B95493526A34032E96`.
Le bootstrap 2.0.74.0 est signé MICRO-STAR INTERNATIONAL CO., LTD.
Le script interne retire d'anciennes inscriptions/provisionnements MSI Center,
y compris une commande `Remove-AppxPackage -AllUsers`, puis appelle `Add-AppxPackage`.
Les actions Inno appellent aussi `SetAccessRight.exe` et DISM avec `nowait`.
Le contenu des exécutables auxiliaires n'est pas validé par la seule lecture du script.

L'audit Windows corrigé **39127977792** a réellement extrait le bundle puis le
paquet x64 : **les deux signatures internes sont valides**, indépendamment de celle
du bootstrap. Le manifeste confirme la version 2.0.74.0, l'application `App` vers
`DCv2\DCv2.exe`, et une extension `windows.startupTask` vers `DCv2\DCv2_Startup.exe`
avec **`TaskId=MSI_Center_UWP`, `Enabled=true`**. Ce constat ne prouve pas l'exécution
de la tâche dans toutes les configurations Windows ; il interdit de promettre
une installation sans préparation de lancement automatique. Aucun Appx enregistré.

La documentation de démarrage décrit une finalisation du SDK lors du premier
lancement administrateur ; les modules sont ensuite proposés dans Feature Sets.
La discussion WinGet confirme ce point. Ce n'est pas encore la preuve d'une
installation entièrement prête sans lancer l'application.

Le Microsoft Store est une piste différente : produit `9NVMNJCR03XV`, famille
`9426MICRO-STARINTERNATION.MSICenter_kzh8wxbdkxb8p`. Le code WinGet attend la fin
de `StartProductInstallAsync` sans appel explicite de lancement. Cela ne démontre
pas les effets propres de MSI Center. Les accès Store actuels restent refusés par
le proxy de ce cloud ; aucune version Store acquise ou installée dans cette étude.
L'[API AppInstallManager](https://github.com/MicrosoftDocs/winrt-api/blob/docs/windows.applicationmodel.store.preview.installcontrol/appinstallmanager.md)
est réservée aux applications Microsoft : pas de wrapper privé présenté comme méthode officielle.

Les [forums MSI](https://forum-en.msi.com/) consultés ne fournissent pas de procédure
administrateur minimale vérifiée ; plusieurs résultats « silent » concernent les profils
ventilation de portables. Ils ne démontrent pas une option d'installation silencieuse.

## ASUS DriverHub

Sources : [site officiel](https://driverhub.asus.com/en),
[manifeste officiel](https://driverhub.asus.com/download/ASUS-DriverHub-Installer.json).
Le point `geo.asus.com/driverhub` est une réponse de région via en-tête, pas un
installateur ; son corps vide ne prouve pas un téléchargement en panne.

La logique officielle du site utilise `latestVersion` et, après 1.0.4.7, le chemin
`/download/{version}/ASUS-DriverHub-Installer.exe`. Le prototype suit ce contrat,
compare numériquement et refuse un EXE dont la version diffère du manifeste.
Le chemin plat non versionné sert encore 1.0.4.8 dans les observations : aucun repli
vers ce fichier n'est autorisé en cas d'échec de la version courante.

**1.0.7.1**, 5 168 024 octets, signature ASUSTeK COMPUTER INC. valide sous Windows.
SHA256 EXE `C52343E16B608359223DF33EDC8D5789E7FEF4D2612986A883D29D915B76FF90`.
Lien observé :
`https://driverhub.asus.com/download/1.0.7.1/ASUS-DriverHub-Installer.exe`.

L'analyse statique retrouve `--silent`, `/s`, `-s` et `--autorun`. Sans autorun,
le navigateur final n'est pas lancé, mais l'installateur démarre encore `ADU.exe`
et enregistre une tâche de logon. L'auxiliaire lance `ASUS DriverHub.exe` avec des
paramètres de notification. Son code contient des contrôles de catalogue lorsque
le cache vieillit, avec un minuteur distinct des notifications. Désactiver les
notifications ne démontre donc pas l'absence de recherche de mises à jour.
**Aucune installation automatique de pilotes n'est démontrée par ces observations**,
mais la recherche automatique suffit à empêcher l'activation dans ce prototype.

## GIGABYTE Control Center

Sources : [page officielle](https://www.gigabyte.com/Consumer/Software/GIGABYTE-Control-Center/global/),
[catalogue officiel](https://www.gigabyte.com/Ajax/SupportFunction/GetUtilityAjax?ClassGroup=2&Page=1&KeyWord=GIGABYTE%20Control%20Center),
[discussion WinGet 298513](https://github.com/microsoft/winget-pkgs/pull/298513),
[signalement WinGet 202058](https://github.com/microsoft/winget-pkgs/issues/202058).

Le catalogue expose actuellement **GCC_26.09.10.01.zip**, **902 526 290 octets**,
SHA256 `B046A63AD3D53675017EBA4B1F58DEEF3D4297591A59B9A4FB9704D5001F2F1B`.
La détection privée nouvelle sélectionne la version numérique, refuse des fichiers
différents pour une même version et un catalogue explicitement incomplet/paginé.

Le programme externe `All_Setup` contient des modules matériel, SSD/firmware et
Norton : **il ne doit pas être lancé pour cette demande**. L'extraction statique
isole `GIGABYTE Control Center_26.08.28.01.exe`, 49 095 256 octets, SHA256
`886A910ABF855F947E6B92921C068CC13C06106951D3EE40CA24CC0B110D2F81`.
Son application `GCC.exe` porte encore la version **25.09.12.1** et le nom produit
`GCC`. Ces trois numéros correspondent à des couches différentes ; les comparer
comme trois versions du même fichier provoquerait une fausse alerte.

Le script NSIS du cœur inscrit `HKLM RunOnce/GCC` vers `GCC.exe`, même en mode `/S`.
Cela suffit à préparer un lancement au prochain logon. Aucune exécution immédiate
du cœur sur installation neuve n'est trouvée dans les instructions inspectées ;
ce constat statique ne démontre pas toute la conduite du programme sur un vrai PC.

Les fonctions de l'interface exposent `SettingPre4=5` pour désactiver le calendrier
et `SettingPre0=0` pour désactiver le démarrage, avec suppression de sa tâche/RunOnce.
Ce sont des observations du code, **pas une interface d'administration officiellement
documentée**. Une automatisation qui modifie ces valeurs n'est pas activée sans
contrat et essai physique ; elle ne garantirait pas tous les accès catalogue au lancement.

Les scripts communautaires trouvés mélangent souvent nettoyage de pilotes, redémarrage
et lancement automatique. Ils servent de pistes de recherche, sans être repris.
Les anciens liens WinGet 404/403 et versions précédentes proposées ne sont jamais
utilisés pour contourner un téléchargement courant défaillant.

## ASRock APP Shop

Sources : [liste officielle de modèles](https://download.asrock.com/setup/Browser.xml),
[catalogue officiel B650M Pro RS](https://www.asrock.com/support/LiveUpdate.asp?Platform=App&Model=B650M%20Pro%20RS),
[présentation APP Shop](https://www.asrock.com/feature/appshop/).

Le catalogue fournit **2.0.0.9**, Windows 10/11 x64 pour ce modèle, l'argument
**`/VerySilent`**, le chemin interne et le SHA256. ZIP officiel observé :
`https://download.asrock.com/Utility/Others/APPShop(v2.0.0.9).zip`, **5 275 382 octets**,
SHA256 `2373443D3C5FAA717937F692B0F3DE5D2DB987197F29B523B305F65C5E9DC7A9`.
Le script valide d'abord le modèle exact puis le flux XML correspondant et son OS.
Il choisit la version la plus récente avant de contrôler l'OS ; aucune ancienne
version n'est choisie simplement parce qu'elle prend en charge un autre Windows.
Les nœuds BIOS/pilotes sont ignorés. DTD/XML externes et chemins ambigus sont refusés.

Les consultations réelles de B550 Pro4, B650M Pro RS, B850 Pro RS WiFi, Z890 Pro RS
et N100M proposent APP Shop actuel pour Windows 10/11. Z270 Extreme4 ne confirme
que Windows 7/10 pour ce produit ; Windows 11 doit être refusé. Des modèles anciens
ne proposent aucun APP Shop. Certaines cartes proposent Motherboard Utility à la
place : ce logiciel distinct n'est pas substitué sans une étude dédiée.

L'installateur actuel est Inno 6.4.3. Les actions déclaratives APP Shop utilisent
`SkipIfSilent` pour le lancement normal ; tâches et composants facultatifs déclarés
sont vides. Toutefois, **`PrepareToInstall` exécute `RM_AsrDrv.exe` même en silencieux**.
Ce helper contient des appels d'arrêt/suppression de services et de suppression
d'anciens fichiers ASRock (`AsrDrv10`, `AsrDrv20`, `AsrSetupDrv10`). L'analyse ne
démontre pas l'installation d'un pilote neuf ; elle montre un nettoyage matériel
supplémentaire qui doit être évalué sur un PC. Ne pas revenir à 2.0.0.4 pour l'éviter.
Ne jamais passer `/IgnoreChkEZDrv`, dont les actions post-installation diffèrent.

Les forums officiels décrivent déjà les incompatibilités par modèle :
[B550 Pro4](https://forum.asrock.com/forum_posts.asp?TID=14809&PN=1),
[Z68](https://forum.asrock.com/forum_posts.asp?TID=14268),
[liste Browser.xml](https://forum.asrock.com/forum_posts.asp?TID=13386).
Ces témoignages historiques expliquent le contrôle du modèle ; ils ne remplacent
pas le catalogue constructeur actuel ni un essai d'installation physique.

## Résultats et limites

Les résultats natifs, échecs compris, sont conservés dans
[RESULTATS_WINDOWS.md](RESULTATS_WINDOWS.md), avec JSON d'évidence et liens GitHub.
Les tests de comparaison, hash, XML, redirections et installations utilisent des
fixtures explicites. Les téléchargements officiels et signatures sont contrôlés
réellement sous Windows. Les essais d'installation sur les quatre marques restent
à effectuer sur PC compatible ; aucune simulation n'est présentée comme un logiciel
réellement installé. Aucun changement des applications LDLC, Numerik's ou ADDON.
