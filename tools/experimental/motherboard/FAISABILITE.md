# Étude des mises à jour constructeur — 17 octobre 2026

Cette phase livre un prototype autonome, pas une nouvelle étape des applications
LDLC/Numerik's. Les essais sur des VM Windows prouvent l'inventaire et les contrôles
du prototype ; ils ne prouvent aucune installation sur une carte mère physique.

## Analyse des applications actuelles

Les dépôts LDLC `10dd623` et Numerik's `f668f06` ont été examinés après récupération
de `origin/main`, ainsi que leurs `AGENTS.md`, `PASSATION_PROJET.md` et
`SYNCHRONISATION.md`.

- `05.Telemetry.ps1` collecte déjà constructeur/modèle, BIOS et Windows pour la
  télémétrie. Il ne résout pas la compatibilité carte mère/utilitaire.
- `30.Applications.ps1` possède les installations, la détection registre et les
  sources officielles. Importer ce module dans le prototype couplerait les essais
  à l'état de préparation ; seuls ses principes sont repris ici.
- `60.Gpu.ps1` gère les adaptateurs, identifiants PnP, signatures et versions GPU.
  Le prototype exclut la classe Display et les suites AMD/NVIDIA.
- `90.Workflow.ps1` déclenche Windows Update tôt puis continue la préparation ;
  les applications et le GPU possèdent leurs propres étapes. Une future étape
  constructeur ne pourra donc pas supposer que Windows Update est terminé.
- `80.WindowsUpdate.ps1` n'est ni importé ni interrogé : aucune surveillance des
  mises à jour restantes n'a été ajoutée.

Le prototype a ses propres fonctions sans importer les modules de préparation,
leurs écritures d'état ou leurs connexions Google. Il n'est pas ajouté à
`build-order.txt`, aux manifestes de synchronisation ou aux ressources des EXE.

## Ce que le prototype fait réellement

L'inventaire en lecture seule utilise CIM (`Win32_BaseBoard`, `ComputerSystem`,
`SystemEnclosure`, `BIOS`, `OperatingSystem`, `PnPEntity`, `PnPSignedDriver`).
Chaque requête possède un délai de 15 s et conserve sa cause d'échec dans le JSON.
SMBIOS peut manquer la révision et ne donne pas toujours le chipset exact : les
indices PnP ne sont pas présentés comme une identification certaine du chipset.

La sélection distingue carte mère de bureau, PC OEM, portable et machine
virtuelle. Le fabricant du PC prime sur celui de la carte mère pour un OEM.
Une piste d'utilitaire ne devient jamais une compatibilité certifiée. Des données
de support injectées en test restent explicitement expérimentales ; il n'existe
pas de catalogue de compatibilité inventé dans le code.

Les versions comparables sont numériques (`1.10 > 1.9`). Une version inconnue,
un fournisseur différent ou des identifiants matériels ambigus imposent une
vérification manuelle. Le filtrage ne sélectionne que des candidats pilotes,
sépare BIOS/UEFI/firmware et ignore les logiciels additionnels et les GPU.
Aucun candidat n'est déclaré installé.

## Faisabilité par constructeur

| Constructeur | Identification et piste d'outil | Recherche/liste de mises à jour par script | Installation silencieuse des pilotes |
|---|---|---|---|
| MSI | Alias SMBIOS reconnus ; MSI Center candidat pour une carte mère de bureau, avec compatibilité à confirmer | Aucune CLI/API publique de scan et d'export confirmée au cours de cette étude ; Live Update est à distinguer de l'installateur MSI Center | Non démontrée ; un commutateur silencieux de l'installateur ne commande pas Live Update |
| ASUS | ASUS/ASUSTeK reconnus ; ASUS DriverHub candidat, contrôle OEM/portable | Page dynamique avec agent local et états « non pris en charge »/ancienne carte visibles dans son JavaScript ; les appels internes ne sont pas une API publique documentée | Non démontrée ; aucun appel au service local non documenté ni clic par coordonnées |
| GIGABYTE | Alias SMBIOS reconnus ; GIGABYTE Control Center candidat | Pages officielles refusées HTTP 403 depuis le runner ; aucune commande de scan/export vérifiée | Non démontrée ; aucun utilitaire ou paramètre supposé compatible |
| ASRock | Alias SMBIOS reconnus ; APP Shop candidat, Auto Driver Installer dépendant du modèle | APP Shop documente une interface « BIOS & Driver », sélection puis bouton Update ; pas de CLI/API de scan/export confirmée | Non démontrée ; aucun lancement global qui pourrait inclure BIOS ou applications additionnelles |

« Non confirmée » ne signifie pas que le constructeur ne dispose d'aucune autre
solution : cela signifie qu'aucune interface officielle, documentée et validée
pour ce périmètre n'a été établie. La détection des quatre fabricants a été
**simulée** ; le runner n'est pas un PC physique de ces marques.

| Constructeur | Téléchargement automatisé réellement vérifié | Compatibilité/dernière version |
|---|---|---|
| MSI | Oui, archive officielle de 584 849 764 octets, EXE 2.0.74.0 signé MSI, obtenu et vérifié deux fois sous Windows | Manuel : Windows 10/11 64 bits et cartes MSI ; compatibilité exacte du modèle/révision et dernière version absolue non établies |
| ASUS | Non : page DriverHub accessible, mais adresse de téléchargement officielle à corps vide depuis le runner, après contrôles des redirections/en-têtes et tentative de lecture | Non établies ; pas de repli vers un ancien fichier |
| GIGABYTE | Non vérifié : deux pages officielles HTTP 403 | Non établies |
| ASRock | Non vérifié : APP Shop accessible mais pas de fichier/compatibilité universels validés ; adresse ADI essayée HTTP 404 | Dépend du modèle ; pas d'installation sur la simple reconnaissance ASRock |

Les sources et résultats de téléchargement réellement obtenus sont détaillés
dans `RESULTATS_WINDOWS.md` et les JSON de preuves associés. Un site joignable ou
une signature valide ne prouve ni la dernière version ni la compatibilité matérielle.

## Sécurité et limites de l'audit

Le prototype n'installe et n'ouvre aucun utilitaire. Il ne modifie ni Defender,
ni les mises à jour de sécurité, ni les associations de fichiers. Les tests de
catalogues refusent Norton, McAfee, Avast, AVG et plusieurs autres produits ; les
applications sans type pilote sont refusées par défaut. Une installation future
exigerait en plus un contrôle documenté des composants groupés de l'installateur.

L'audit HTTPS contrôle les domaines à chaque redirection, la complétude, les tailles,
le format PE, Authenticode `Valid`, le nom de l'éditeur et une empreinte SHA-256 de
traçabilité. Pour une archive, les EXE extraits sont vérifiés, sans lancement.
Une empreinte calculée localement n'est pas une empreinte publiée par l'éditeur.
Les ZIP sans EXE vérifiable sont refusés ; il n'existe aucun repli vers un ancien
fichier, aucune désactivation de TLS/signatures et aucune commande de flash BIOS.

Les entrées registre d'utilitaires installés ne prouvent pas leur exécutable, leur
compatibilité ou une installation Store/MSIX complète. Le prototype ne s'appuie
pas sur ces seules entrées pour installer ou annoncer un outil opérationnel.

## Proposition d'intégration ultérieure

1. Ajouter d'abord l'inventaire en lecture seule au diagnostic, après validation
   sur des PC physiques. Afficher fabricant, modèle, révision disponible et BIOS.
2. Construire un adaptateur distinct par outil, uniquement avec une preuve de
   support du modèle/révision/Windows et des commandes publiées par l'éditeur.
   Sinon proposer le lien du support officiel et des instructions au technicien.
3. Séparer le téléchargement vérifié de l'exécution. Contrôler l'outil déjà présent,
   son éditeur et sa version ; conserver l'état « intervention manuelle nécessaire »
   si une vérification manque. Ne pas annoncer « à jour » sans lecture réelle.
4. En cas de futur scan documenté, journaliser les pilotes proposés et ignorés,
   les versions avant/après et le redémarrage demandé. Exclure fermement les
   logiciels additionnels, la classe Display et tout firmware.
5. Sérialiser une éventuelle installation avec les installateurs d'applications et
   de GPU. Si l'installateur Windows est occupé, reporter l'étape constructeur ;
   ne pas arrêter/surveiller Windows Update et ne pas attendre ses mises à jour restantes.
6. Préserver l'annulation et le résultat global : outil inconnu ou serveur indisponible
   => diagnostic explicite et étape non bloquante ; intervention incomplète ou
   véritable erreur d'installation => aucune validation artificielle.
7. Faire valider cette intégration après les essais matériels, puis seulement
   déclarer ses fichiers dans le cœur partagé LDLC/Numerik's et reconstruire leurs
   livrables séparément. ADDON et le dépôt de test restent hors de ce périmètre.

## Validation matérielle encore nécessaire

Au moins un PC physique récent et un modèle ancien/non pris en charge par fabricant,
une révision différente et un portable/OEM. Vérifier l'outil installé réellement,
sa liste de pilotes, les options évitant antivirus/firmware, un échec réseau, une
annulation, les versions PnP après installation et l'absence de redémarrage automatique.
Ces validations ne peuvent pas être remplacées par les VM GitHub Actions.
