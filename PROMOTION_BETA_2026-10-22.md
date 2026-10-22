# Promotion de la bêta dans les trois éditions — 22 octobre 2026

Livraison publiée et vérifiée : **LDLC, Numerik’s et bêta 2.6.14 ; ADDON 2.0.3**.
L’autorisation utilisateur du 22 octobre étend les fonctions acceptées de la bêta
aux trois productions. La carte mère n’est donc plus réservée à la bêta.

## Fonctions livrées

- En fin d’installation des applications (60 %), détection de la carte mère,
  téléchargement vérifié de MSI Center, ASUS DriverHub, GIGABYTE Control Center
  ou ASRock APP Shop et raccourci sur le vrai Bureau Windows, y compris redirigé.
  **Le technicien lance l’installation manuellement depuis le raccourci.**
  Aucun installateur constructeur ne démarre automatiquement ; aucun pilote,
  BIOS, antivirus ou module facultatif n’est installé par cette fonctionnalité.
  Les portables sont exclus avant toute requête réseau ou création de raccourci.
  Un téléchargement impossible produit un repli officiel explicitement signalé,
  jamais un faux succès d’installation. GCC utilise uniquement le cœur signé.
- Les cinq sources utiles sont embarquées dans principal et worker, vérifiées
  par SHA256 puis importées uniquement à cette étape, sans téléchargement au démarrage.
- Edge : être encore installé ne prouve plus qu’il reste épinglé. Une fenêtre
  Edge ouverte n’est plus une fausse erreur de retrait de l’épingle.
- Chrome : retour au `LayoutModification.xml` historique avec ajout de Chrome
  et rafraîchissement d’Explorer (référence `a2a57ee2d28203fded79802eae2a58883d996c7e`).
  La confirmation UIA récente et son faux avertissement sont retirés. Les erreurs
  réelles d’écriture ou de relance d’Explorer restent signalées. Le parcours du
  navigateur par défaut n’est pas modifié par ce retour de l’épinglage.
- AMD LDLC/Numerik’s/bêta : package officiel complet actuel, signature et INF
  compatibles contrôlés, vérification des versions application ET pilote après
  installation. Repli Chocolatey uniquement pour cette même version actuelle,
  URL officielle et SHA256 concordants, après échec officiel, sans installateurs
  concurrents ni retour à un ancien cache. Portables toujours exclus.
- ADDON garde NVIDIA uniquement, Trackman, ses différences Adobe/Validator et
  son identité. Numerik’s garde ses boutiques, logos et fonds. Les interfaces
  propres et modifications UI locales non publiées sont préservées ;
  l’agrandissement de texte annulé n’est pas transféré.

## Campagnes Windows natives

GitHub Actions `windows-2025`, PowerShell Windows 5.1. Chaque workflow compile
l’EXE de sa propre édition ; aucune copie de l’EXE bêta vers une production.

| Édition | Version | Campagne réussie | Source testée | Commit de l’EXE |
| --- | --- | --- | --- | --- |
| LDLC-Preparation | 2.6.14 | [`39784261656`, essai 1](https://github.com/holyonefr/LDLC-Preparation/actions/runs/39784261656) | `e70eade11e3a` | `b0b8d5835158` |
| Numerik-s-Preparation-PC | 2.6.14 | [`39784276767`, essai 2](https://github.com/holyonefr/Numerik-s-Preparation-PC/actions/runs/39784276767) | `d55f606cbcea` | `ab1bff60a9cf` |
| LDLC-Preparation-Addon | 2.0.3 | [`39784290420`, essai 1](https://github.com/holyonefr/LDLC-Preparation-Addon/actions/runs/39784290420) | `99655d1398c7` | `b0f62795e377` |
| LDLC-Preparation-PC-test-app | 2.6.14 | [`39783467473`, essai 1](https://github.com/holyonefr/LDLC-Preparation-PC-test-app/actions/runs/39783467473) | `4ecba8042195` | `cb847a623285` |

Les quatre fichiers EXE ont été récupérés depuis GitHub : entête PE et SHA256
identiques aux fichiers testés. Suites release, intégration des cinq sources
dans principal ET worker, placement après les applications, portables et replis
passent dans les quatre éditions. Les tests destructifs et matériels sont simulés.

| Édition | Temps Preview en ms (quatre passages) | Ouvertures | Dashboard réel |
| --- | --- | --- | --- |
| LDLC-Preparation | 1194, 1129, 1167, 2071 | 4/4 | 3/3, nettoyés |
| Numerik-s-Preparation-PC | 1459, 1495, 1493, 1479 | 4/4 | 3/3, nettoyés |
| LDLC-Preparation-Addon | 984, 985, 972, 1260 | 4/4 | 3/3, nettoyés |
| LDLC-Preparation-PC-test-app | 1672, 1661, 1664, 1871 | 4/4 | 3/3, nettoyés |

Ces temps commencent à l’entrée de l’EXE et excluent clic, UAC et téléchargement.
Il s’agit d’ouvertures/fermetures réelles en mode Preview, sans préparation du runner.
Les échanges dashboard utilisent le vrai client et le serveur permanent : fin
normale → `validated`, erreur → `blocked`, abandon → `blocked`. Les rapports de
test possédés sont supprimés et leur absence vérifiée ; historique client préservé.

## Téléchargements constructeurs réels

La campagne LDLC teste les sources communes identiques dans les quatre éditions.
Les quatre catalogues, téléchargements, signatures et raccourcis COM sont réels.
Chaque marque est testée sur Bureau normal et Bureau Windows redirigé vers une
fixture « OneDrive - Fixture/Bureau » (8 cas). Le matériel est simulé et aucun
véritable compte OneDrive n’est utilisé. La cible du raccourci existe, est stable
après nettoyage temporaire, ne crée pas de doublon et préserve les autres raccourcis.

| Constructeur | Version téléchargée | Méthode / lien officiel retenu |
| --- | --- | --- |
| ASRock | 2.0.0.10 | [official_asrock_model_xml](https://download.asrock.com/Utility/Others/APPShop(v2.0.0.10).zip) |
| MSI | 2.0.75.0 | [archive officielle MSI](https://download-2.msi.com/uti_exe/desktop/MSI-Center.zip) |
| ASUS | 1.0.7.1 | [official_asus_json](https://driverhub.asus.com/download/1.0.7.1/ASUS-DriverHub-Installer.exe) |
| GIGABYTE | 26.08.28.01 | [official_gcc_software_update_manifest](https://mb.download.gigabyte.com/FileList/Swhttp/LiveUpdate4/GCC/GIGABYTE%20Control%20Center/GIGABYTE%20Control%20Center_26.08.28.01.exe) |

Versions ci-dessus observées au test, non figées comme dernière version dans le
script. Les suites simulent aussi changements de versions, indisponibilités HTTP,
signatures/empreintes incorrectes, Bureau inaccessible et replis manuels officiels.

AMD officiel réellement téléchargé dans les campagnes LDLC, Numerik’s et bêta :
**26.10.1**, 1 782 243 424 octets, signature AMD valide, deux INF DISPLAY examinés.
SHA256 : `EAF0B61DE6CE31793D05222FD57B50C6A55095F52796A33683093381F9345B82`.
Le paquet Chocolatey 26.10.1 a été réellement lu : même URL officielle et même
SHA256. Les 29 scénarios de repli (162 assertions) sont simulés ; ni Chocolatey ni
l’installateur AMD ne sont exécutés pour installer du matériel sur les VM.

## Incidents rencontrés et limites

- Premier passage de promotion : l’ancien test isolé de fin de préparation ne
  simulait pas encore la nouvelle étape carte mère. Ajout du stub déjà présent
  en bêta dans les trois suites de production ; leurs nouvelles campagnes passent.
- Numerik’s, premier essai de la campagne finale : absence d’acquittement final
  dans le scénario d’erreur. Publication bloquée, rapports de cet essai nettoyés.
  La relance isolée du même code passe les trois scénarios et le nettoyage, puis
  publie l’EXE. La cause de cet incident intermittent n’est pas établie ; aucune
  validation n’a été forcée et aucune erreur d’intervention n’est ignorée.
- Une ancienne candidate Numerik’s avait réussi les trois échanges mais échoué
  au contrôle de nettoyage. Les rapports restants ont été supprimés séparément
  (reste : zéro). Les seuls outils d’administration des TESTS ont été durcis :
  trois essais maximum sur erreur transitoire pour lecture/suppression idempotente
  des IDs CODEX-TEST possédés, puis état serveur acquitté prouvant leur absence.
  Autorisation refusée, réponse invalide ou rapport restant restent un échec.
  Le transport et les règles de validation du produit ne changent pas.
- L’ancien test comparatif bêta attendait encore l’échec de la confirmation
  Chrome abandonnée ; son attendu correspond maintenant au comportement historique.

**Non vérifié sur VM :** installation effective des logiciels constructeurs,
installation du pilote sur GPU AMD physique, compatibilité universelle des cartes
mères et apparition visuelle de l’épingle Chrome sur une vraie session préparée.
Le test Chrome compare le corps historique et écrit/lit réellement son XML dans
un dossier isolé ; les actions Explorer sont simulées. ADDON couvre principal et
worker via sa suite de parité ; les annotations individuelles ne sont pas toutes
exposées par GitHub. Aucun contournement des restrictions Windows n’est ajouté.

Preuves structurées : [campagnes](evidence/promotion-beta-2026-10-22/windows-results.json),
[EXE récupérés](evidence/promotion-beta-2026-10-22/delivery-verification.json),
[préservation et parité](evidence/promotion-beta-2026-10-22/preservation.json),
[incidents](evidence/promotion-beta-2026-10-22/incidents.json).
Les anciennes notes candidates 2.6.13 décrivent l’étape intermédiaire et sont
remplacées par cette livraison. Les anciens mentions « carte mère bêta seulement »
restent historiques, sans limiter l’autorisation du 22 octobre.
