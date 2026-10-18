# Logiciel constructeur uniquement — prototype indépendant

Dans ce depot beta, les cinq sources utiles sont embarquees dans All in App : voir [BETA.md](../../../BETA.md). Les trois applications de production restent inchangees ; le script independant ci-dessous reste disponible pour les tests isoles.
Il identifie la carte mère et le PC par CIM, sans inventaire des pilotes ou du BIOS.
Il ne lance ni application constructeur, ni recherche de mises à jour, ni installation de pilote,
firmware, antivirus ou module facultatif.

## Utilisation sur le PC Windows

Depuis une session du technicien (Bureau de ce même utilisateur) :

```powershell
# Identifier seulement, sans téléchargement ni installation
powershell.exe -NoProfile -File .\Install-VendorUtility.ps1 -PlanOnly

# Vérifier l'application présente, ou préparer le repli manuel
powershell.exe -NoProfile -File .\Install-VendorUtility.ps1
```

Le rapport JSON distingue `Installed`, `InstalledThisRun`, `ApplicationVerified`,
`AutomaticInstallAvailable`, le fichier téléchargé et la cause d'un repli manuel.
`InstallerShortcut` désigne le raccourci pour lancer l'installateur manuellement ;
`Shortcut` désigne uniquement une application installée et reconnue.
Codes de sortie : 0 = opération terminée/plan ; 1 = erreur ; 2 = intervention manuelle requise.
Avec `InstallerShortcut` renseigné, le code 2 signifie que le raccourci est prêt et
que le technicien doit lancer l'installation manuellement.

**Aucun profil d'installation automatique réel n'est actuellement activé.** La mécanique
d'installation et de vérification est testée avec des simulations ; cela ne prouve pas une
installation réelle sur PC. Aucun argument silencieux supposé n'est utilisé. Un nouveau
profil nécessiterait une méthode officielle démontrant l'installation de la seule application,
sans lancement automatique, une empreinte d'installateur approuvée et un essai sur PC compatible.

| Fabricant | Application visée | État constaté |
|---|---|---|
| MSI | MSI Center | Bootstrap, bundle et Appx 2.0.74.0 signés ; manifeste avec tâche de démarrage activée ; finalisation SDK et absence de lancement à vérifier sur PC |
| ASUS | ASUS DriverHub | Manifeste officiel dynamique et téléchargement signé 1.0.7.1 vérifiés sous Windows ; démarrage auxiliaire et vérifications de catalogue incompatibles avec une activation automatique en l'état |
| GIGABYTE | GIGABYTE Control Center | Source officielle dynamique, téléchargement signé, extraction du seul cœur et raccourcis Bureau/OneDrive validés sous Windows GitHub avec source live ; version du programme 26.08.28.01 observée le 18 octobre 2026 |
| ASRock | APP Shop | Catalogue officiel par modèle/OS, version numérique, SHA256 et `/VerySilent` ; version actuelle 2.0.0.9 trouvée ; nettoyage de services/pilotes ASRock existants à évaluer sur PC |

Ces numéros décrivent les observations datées de l'étude, pas des versions épinglées
dans la détection ASUS/ASRock/GIGABYTE. ASRock refuse un modèle absent, un OS non
pris en charge ou une version/hash incohérente, sans télécharger une version plus
ancienne. L'ancien snapshot ASRock 2.0.0.4 reste uniquement un audit historique.

Chaque preparation consulte la source officielle courante avec demande de
revalidation du cache. Les coupures reseau, fichiers interrompus et erreurs HTTP
temporaires (408, 429, 500, 502, 503, 504) autorisent au maximum trois tentatives
dans le delai initial, en repartant de zero. Les erreurs de certificat, de domaine,
de signature ou d'integrite restent bloquantes. Aucun ancien paquet n'est utilise
pour masquer une source indisponible. Les tests simulent aussi de nouvelles versions
des quatre marques et comparent les numeros numeriquement, y compris 1.10 > 1.9.
Une refonte du site ou du format constructeur peut necessiter une adaptation :
elle doit produire une erreur precise et jamais un faux succes.

Si la detection ou le telechargement echoue, le repli cree sur le vrai Bureau un
raccourci **Telechargement officiel - nom du logiciel.url** vers la page officielle
de la marque, sans executer le navigateur. Il n'annonce ni version ni installateur
verifie : le technicien telecharge et installe manuellement. Le rapport conserve
la cause dans `DownloadFailure`, le raccourci dans `SupportShortcut` et l'etat
`manual_required`. L'integration All in App affiche cet etat comme avertissement.
Si le Bureau est inaccessible ou un raccourci homonyme pointe ailleurs, il est
preserve ; `FallbackError` explique le probleme et la page officielle reste dans
le rapport. Ce repli ne s'applique pas aux portables ou autres PC exclus.

Si l'application n'est pas déjà installée, le script tente le téléchargement lorsqu'un lien
officiel vérifié est disponible. Un téléchargement ne donne jamais le statut « installé ».
Après téléchargement vérifié, il ajoute sur le **Bureau réel de l'utilisateur** un
raccourci nommé par exemple **« Installer ASRock APP Shop 2.0.0.9 »**, sans lancer
l'installateur. La version du nom provient du fichier et du catalogue, pas d'une valeur
fixée dans le script. La cible est conservée dans le dossier local de l'utilisateur,
hors des fichiers temporaires. Un même paquet réutilise sa cible et son raccourci.
Un raccourci existant vers une autre cible est préservé et signalé.

MSI Center et ASUS DriverHub ont aussi leurs raccourcis installateurs réellement
validés sur Windows, avec téléchargement et signature réels, sur Bureau classique
et redirigé OneDrive. Pour GIGABYTE, le script consulte maintenant le manifeste
logiciel officiel `LiveUpdate4/GCC/GIGABYTE Control Center/ver2.ini` et télécharge
le petit paquet de mise à jour indiqué. Ce chemin est celui lu par le
code distribué de GCC ; aucune application constructeur n'est exécutée pour le trouver.
La taille du manifeste, la taille HTTP, la signature constructeur et la version du
fichier doivent correspondre. Le paquet inclut MB Update et RGB Sync : seul son
installateur interne **GIGABYTE Control Center** est extrait, signé et contrôlé par
version et identité produit avant création du raccourci. Aucun paquet `All_Setup`,
pilote, BIOS ni module facultatif n'est proposé ou exécuté. L'extraction utilise
les outils portables officiels 7-Zip vérifiés par empreintes, sans installer 7-Zip.
L'ancien gros bundle reste réservé aux audits avec catalogue enregistré ; aucun
repli automatique vers ce paquet ou une ancienne réponse n'est utilisé.

Le technicien lance ce raccourci pour installer manuellement, refuse les modules additionnels
et l'ouverture/recherche automatique, puis relance le script : le raccourci d'application sera créé uniquement
si l'application est réellement détectée et vérifiée. L'identité Windows Store exacte est
contrôlée pour MSI Center ; les programmes classiques exigent l'entrée d'application, le
fichier attendu, sa signature et son identité produit. Une installation dont ces preuves ne
sont pas reconnues reste un échec de vérification, jamais un faux succès.

La reconnaissance de certaines installations classiques reste à compléter :
GCC utilise notamment une icône de désinstalleur et le nom produit `GCC`, différents
du contrat strict actuel. Un refus de reconnaissance reste manuel ; ce prototype
ne garantit donc pas encore un raccourci sur toute installation réelle des quatre marques.

Le Bureau est obtenu par le dossier spécial Windows de l'utilisateur courant, y compris
une redirection OneDrive. Un raccourci existant vers une autre cible est préservé et signalé.
Les VM, portables, OEM incompatibles, identités inconnues et systèmes non confirmés sont
orientés vers le support manuel. Aucun redémarrage automatique.

**Portable : aucun téléchargement, aucune installation et aucun raccourci**, même
si l'application constructeur est déjà présente.

## Validation

Voir [RESULTATS_WINDOWS.md](RESULTATS_WINDOWS.md). Les installations constructeur sont
strictement simulées sur GitHub Actions ; une barrière dans le lanceur refuse l'exécution
réelle lorsque `GITHUB_ACTIONS=true`. Les raccourcis et la détection CIM sont testés réellement.
La batterie historique de 212 scénarios / 501 assertions a réussi sur Windows Server 2022 et
Windows Server 2025, tous deux avec PowerShell 5.1. L'ajout du raccourci installateur
est validé séparément sous Windows 2025 : **52 scénarios / 136 assertions / 0 échec**,
avec vrai téléchargement ASRock et vrais raccourcis COM sur les deux types de Bureau.
La carte mère est simulée pour ces deux contrôles sur la VM. Ces VM ne prouvent pas une
installation sur carte mère physique ; les profils automatiques restent désactivés.
Les contrôles réels des sources et téléchargements antérieurs sont détaillés dans
[l'étude indépendante](../motherboard/RESULTATS_WINDOWS.md).

La recherche complémentaire WinGet, Chocolatey et Ninite est consignée dans
[CATALOGUES.md](CATALOGUES.md), avec les résultats confirmés et les accès bloqués.
Les recherches officielles et forums, ainsi que les comportements annexes observés,
sont détaillés dans [RECHERCHE_APPROFONDIE.md](RECHERCHE_APPROFONDIE.md).
La préparation des raccourcis est validée pour les quatre fabricants. Le test GCC
avec source live a réussi : **86 scénarios / 187 assertions / 0 échec**, dont deux
vrais téléchargements/extractions et créations de raccourcis sur Windows avec matériel
simulé. Les anciens contrôles avec source enregistrée restent distincts. Voir la
dernière section du rapport pour les preuves natives et les essais intermédiaires.
