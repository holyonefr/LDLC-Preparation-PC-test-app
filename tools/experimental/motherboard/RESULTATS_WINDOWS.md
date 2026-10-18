# Résultats Windows — prototype indépendant de carte mère

Validation réelle du 17 octobre 2026. Code exécuté : `e16f234171bcd0d98af8f30976e2b148a1906a7a`.
[Exécution GitHub Actions](https://github.com/holyonefr/LDLC-Preparation/actions/runs/39035069864), job `117403123520`, Windows Server
2022, Windows PowerShell `5.1.20348.5622`. Les étapes de recherche,
tests et conservation des rapports sont toutes terminées avec succès.

## Résultat des trois passages

| Passage | Scénarios exécutés | Assertions | Échecs de scénarios |
|---|---:|---:|---:|
| validation-1 | 45 | 139 | 0 |
| validation-2 | 44 | 137 | 0 |
| validation-3 | 44 | 137 | 0 |
| **Total** | **133** | **413** | **0** |

Cela comprend 43 scénarios simulés par passage, trois inventaires Windows réels
et un contrôle réel de téléchargement MSI. L'audit réseau ASUS est consigné
**séparément en échec** ci-dessous ; le succès du workflow ne signifie pas que
chaque site et chaque téléchargement constructeur fonctionne.

Les simulations couvrent MSI, ASUS, GIGABYTE, ASRock, fabricant inconnu, données
SMBIOS partielles, plusieurs cartes, OEM Dell/HP/Lenovo/Acer/inconnu, portable,
convertible et VM. Elles vérifient notamment `1.10 > 1.9`, le refus des antivirus
et applications additionnelles, BIOS/UEFI/firmware séparés, GPU ignorés,
identifiants incompatibles et versions non comparables. Aucun candidat n'est
présenté comme installé.

Le transport simulé traverse le vrai code HTTP : liens relatifs, redirections
externes interdites, boucle limitée, HEAD distinct d'un téléchargement, HTTP
403/404/429/500/503/206, perte de connexion, annulation après une seconde,
transfert interrompu ou trop court, taille excessive, ancien fichier préservé,
PE invalide, certificat invalide/mauvais éditeur, ZIP avec traversée de chemin,
Content-Disposition ASUS et lien HTML/JavaScript relatif sans exécuter ce code.
Les certificats du transport simulé restent des fixtures : ils ne remplacent pas
la vérification Authenticode réelle ci-dessous.

## Inventaire réel de la VM

Les trois passages ont relevé une carte mère, un ordinateur, un BIOS, 59 pilotes
et 57 périphériques PnP. Zéro erreur CIM. La VM Microsoft est reconnue comme
virtuelle : aucun outil de carte mère physique sélectionné. Aucun pilote,
utilitaire constructeur, antivirus ou firmware installé/exécuté ; aucun
redémarrage. Les rapports complets d'inventaire restent dans l'artefact GitHub.
Les preuves versionnées ne contiennent que les comptes, pas l'identité de l'hôte.

## Téléchargement MSI réellement terminé et vérifié

- Source officielle : `https://download-2.msi.com/uti_exe/desktop/MSI-Center.zip`.
- Fichier : `MSI-Center.zip`, **584,849,764 octets**, taille reçue égale à
  Content-Length. L'archive contient un EXE de 584,849,584 octets.
- Version de l'EXE : **2.0.74.0**.
- Authenticode : **Valid**, éditeur `MICRO-STAR INTERNATIONAL CO., LTD.`.
- SHA-256 archive : `FBFA35A0CD8B4A71F6F0CAC5090C50A97D082E1F5F93D5B95493526A34032E96`.
- SHA-256 EXE : `95E6BE38ED8F1A0AD5055C9831DAB057F2B0BBA0EB33A25EB60A9486FD0D3EBD`.
- 10 mises à jour de progression, limitée à deux par seconde.
- Aucun lancement, aucune installation et aucun flash.

Une précédente exécution Windows réussie a aussi téléchargé ces mêmes octets et
vérifié la même signature : [run 39034773229](https://github.com/holyonefr/LDLC-Preparation/actions/runs/39034773229).
La version n'est pas codée dans le lien. Le lien a été localisé via les métadonnées
publiques winget, puis le fichier a été obtenu et vérifié sur le CDN MSI : la
version du manifeste communautaire n'est pas utilisée comme preuve de dernière
version ou de compatibilité. **Dernière version absolue et compatibilité avec un
modèle physique : non établies.** Le SHA-256 calculé est une trace d'audit, pas une
empreinte publiée par MSI pour toute l'archive.

## Sources consultées et limites réelles

| Constructeur/source | Résultat réel | Conséquence |
|---|---|---|
| MSI Center, Driver Utility Installer, page d'aide MSI | HTTP 403 sur les trois pages | Compatibilité détaillée du modèle non vérifiée depuis ces pages |
| Manuel officiel MSI Center | HTTP 200, redirection vers `https://download-2.msi.com/archive/mnu_exe/mb/MSICENTER.pdf` | Exigences Windows 10/11 64 bits p. 6 ; Live Update p. 107 décrit Scan, sélection, Install et peut proposer pilotes, BIOS et utilitaires |
| ASUS DriverHub et ses JavaScript officiels | HTTP 200 | Agent local et états matériel non pris en charge visibles ; pas une API/CLI publique documentée |
| Adresse officielle `https://geo.asus.com/driverhub/` | **Échec réel : « Reponse vide. »** | Téléchargement/signature/version ASUS non vérifiés ; aucun fichier ancien ou lien inventé utilisé |
| Deux pages officielles GIGABYTE GCC/utilitaires | HTTP 403 | Téléchargement, compatibilité et automatisation non confirmés |
| ASRock APP Shop et accueil officiel | HTTP 200 | Interface BIOS & Driver documentée ; pas de commandes silencieuses de pilotes confirmées |
| Adresse ASRock `/feature/AutoDriverInstaller/` essayée | HTTP 404 | Adresse non valable ; cela ne prouve pas que la fonctionnalité n'existe plus |

Pour ASUS, les méthodes réelles ont contrôlé les redirections HTTP, les en-têtes
Content-Disposition et une lecture de la page de téléchargement. Le corps vide
empêche la récupération fiable d'un installateur. Les méthodes d'extraction d'un
lien relatif/JavaScript et d'un fichier servi directement sont vérifiées avec des
fixtures ; elles ne sont pas annoncées comme réussies sur le téléchargement ASUS
réel. Un HttpStatus `0` dans le collecteur signifie « non enregistré après erreur
de lecture », pas un code HTTP retourné par le serveur.

## Incidents rencontrés puis corrections

| Exécution | Résultat et analyse |
|---|---|
| [39033346986](https://github.com/holyonefr/LDLC-Preparation/actions/runs/39033346986) | Collecte initiale effectuée ; limites HTTP 403/404 et page dynamique ASUS constatées |
| [39033534404](https://github.com/holyonefr/LDLC-Preparation/actions/runs/39033534404) | Collecte arrêtée volontairement ; traitement PDF/HTML séparé et expressions régulières bornées dans la nouvelle version |
| [39034015504](https://github.com/holyonefr/LDLC-Preparation/actions/runs/39034015504) | Trois scénarios en échec : deux types ZIP non chargés sous PS 5.1 et plafond MSI trop bas ; inventaire réel déjà réussi |
| [39034228189](https://github.com/holyonefr/LDLC-Preparation/actions/runs/39034228189) | Scénarios ZIP corrigés ; audit MSI expiré après 120 s. Progression par bloc remplacée par un rafraîchissement limité, délai de gros téléchargement porté à 600 s, diagnostic octets reçus/attendus ajouté |
| [39034773229](https://github.com/holyonefr/LDLC-Preparation/actions/runs/39034773229) | Trois passages réussis, 127 scénarios/401 assertions, MSI complet/signé ; ASUS restait non récupérable |
| [39035069864](https://github.com/holyonefr/LDLC-Preparation/actions/runs/39035069864) | Dernier code : trois passages réussis, 133 scénarios/413 assertions ; MSI à nouveau vérifié ; ASUS toujours en échec explicite |

L'accélération MSI a été observée après limitation de la progression. L'ancien
échec n'avait pas enregistré son débit détaillé : le réseau n'est donc pas exclu
comme facteur, et aucune durée de téléchargement garantie n'est annoncée.
Les longues annotations initiales étaient tronquées/limitées par GitHub ; les
preuves sont maintenant compressées, fragmentées et reconstituées. Les neuf
objets de preuve de la dernière exécution sont complets. Les artefacts contiennent
les JSON/textes/pages de recherche, sans réhéberger les gros installateurs.

## Préservation et décision d'intégration

Empreintes vérifiées : **112 fichiers préexistants LDLC, 132 Numerik's et 97 ADDON
inchangés**. Modules, EXE, interfaces, fonds, manifests de synchronisation,
télémétrie et connexions Google n'ont pas changé. Le dépôt de test n'a pas été
modifié. Les suites de release des applications ne sont pas relancées pour cette
expérimentation isolée ; aucun EXE n'a été reconstruit.

L'inventaire, la sélection prudente et les contrôles de fichiers sont opérationnels
et testés. **La recherche/export et l'installation silencieuse de pilotes ne sont
pas validées pour les quatre constructeurs.** Aucun outil n'a été installé pour
tenter de les prouver sur une VM incompatible. Aucun BIOS disponible n'est inventé :
seul le BIOS courant est lu, et les offres BIOS/firmware simulées sont séparées.
Une installation réellement interrompue, les redémarrages nécessaires et les
versions de pilotes après mise à jour nécessitent des PC physiques appropriés.

Voir [FAISABILITE.md](FAISABILITE.md) pour la proposition d'intégration progressive
et [README.md](README.md) pour l'exécution du prototype. Les données de support
injectées n'autorisent jamais une installation. Le prototype n'est intégré ni à
LDLC ni à Numerik's.

Preuves : [JSON Windows final](evidence/windows-final.json),
[précédent succès](evidence/windows-previous-success.json),
[échecs initiaux](evidence/initial-failures.json),
[préservation](evidence/preservation.json).

## Environnement de développement

Le dernier passage local Linux/PowerShell 7.4.13 a exécuté 43 scénarios et 132
assertions sans échec. Il ne remplace pas les essais PowerShell 5.1 ci-dessus.
Le contrôle de reconstitution des preuves compressées a également restitué le
JSON local exactement. Aucun service permanent ou outil Windows émulé n'est requis.

Le brouillon de configuration cloud ajoute les domaines officiels MSI, ASUS,
GIGABYTE et ASRock en conservant les domaines personnalisés connus. Cet
enregistrement n'est pas une publication ni une preuve d'accès local appliqué ;
les vérifications réelles rapportées ici proviennent du runner Windows demandé.
Les scripts d'installation/démarrage existants du cloud n'ont pas été remplacés.
