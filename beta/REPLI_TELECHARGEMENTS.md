# Recherche d'un vrai telechargement alternatif — 18 octobre 2026

La demande porte sur un installateur recuperable sur une autre source lorsque le
fabricant devient indisponible. Un raccourci vers sa page officielle ne repond pas
a cette demande : ce repli manuel deja teste reste distinct de la recherche ici.
**Aucun miroir binaire externe n'est actuellement valide ou active.**

## Sources effectivement consultees

| Logiciel | Source | Observation actuelle | Conclusion |
|---|---|---|---|
| MSI Center | [Microsoft Store](https://apps.microsoft.com/detail/9nvmnjcr03xv) | HTTP 200, titre MSI Center et editeur MICRO-STAR INTERNATIONAL CO., LTD. ; produit 9NVMNJCR03XV, paquet Store propose | Source independante du serveur MSI, candidat ; paquet actuel, version et telechargement pas encore verifies |
| MSI Center | [WinGet](https://github.com/microsoft/winget-pkgs/tree/master/manifests/m/MSI/MSICenter) | Une fiche 2.0.72, URL download-2.msi.com ; empreinte differente du ZIP 2.0.74.0 valide sous Windows | Catalogue obsolete lors de cette consultation, meme serveur MSI : pas un miroir independant ; aucun contournement du hash |
| ASRock APP Shop | [Chocolatey app-shop](https://community.chocolatey.org/packages/app-shop/1.0.31) | Recherche API : app-shop 1.0.31 ; la version constructeur validee est 2.0.0.9 | Ancienne fiche rejetee, pas d'installation ni de reutilisation comme derniere version |
| ASUS DriverHub | WinGet / Chocolatey / Scoop Extras | Aucune correspondance exacte dans les recherches et catalogues consultes | Aucun repli binaire verifie ; DriverHub.DriverHub est un autre produit, non ASUS |
| GIGABYTE Control Center | WinGet / Chocolatey / Scoop Extras | Aucun paquet actuel correspondant dans les repertoires consultes ; anciennes propositions WinGet GCC retrouvees | Pas de remplacement par EasyTune, RGBFusion ou un compilateur GCC |
| Les quatre logiciels | [Ninite](https://ninite.com/) | Page publique obtenue, aucun de ces quatre logiciels dans le selecteur | Cette offre publique n'apporte pas le repli demande |

Consultations GitHub : repertoires editeurs, arbre public complet Scoop Extras et
chocolatey-packages (sans troncature), recherches de propositions/paquets. Ces
recherches negatives ne prouvent pas l'absence de tout depot tiers. Les recherches
Chocolatey ont utilise son API ; MSI donne des produits Starface sans rapport,
ASUS/GIGABYTE aucune correspondance et ASRock app-shop 1.0.31.
Les resultats Bing sans rapport avec la requete n'ont pas ete utilises comme preuve.

## Verifications actuellement impossibles

Le proxy cloud refuse le tunnel HTTPS (403) vers les sites miroirs ci-dessous.
Leurs catalogues, liens directs, signatures et versions ne sont **pas verifies**.
Aucun de ces refus n'a ete contourne en passant par un runner ou un relais.

- www.techpowerup.com
- www.majorgeeks.com
- www.techspot.com
- www.filehorse.com
- www.softpedia.com
- msi-center.en.lo4d.com
- msi-center.en.uptodown.com
- www.malavida.com
- www.filepuma.com

L'acquisition du paquet Microsoft Store reste aussi a tester ; la page produit
HTTP 200 n'est pas une preuve de telechargement. La source WinGet StoreEdge avait
un refus documente dans l'etude precedente, sans contournement.

Le brouillon de configuration reseau a ete sauvegarde avec ces destinations,
www.google.com (recherche), apps.microsoft.com et
storeedgefd.dsx.mp.microsoft.com. Le retour de l'outil indique
`status=saved`, `requires_publish=true` : enregistrer les parametres puis publier
l'environnement avant de reprendre les acces refuses. Le reseau de l'instance
actuelle n'est pas declare modifie ni valide pour ces sites.

## Conditions d'activation d'un miroir

Il faut retrouver le vrai installateur, sans gestionnaire publicitaire, confirmer
son identite et sa signature constructeur, son contenu et sa version, puis verifier
le telechargement complet sous Windows sans executer d'installateur materiel.
Si une version courante ou un hash officiel est connu, le miroir doit correspondre
exactement. Une source dont la version est inconnue ou plus ancienne n'est pas
presentee comme la derniere. Si toutes les sources de version deviennent
indisponibles, on ne peut pas garantir que la copie d'un miroir est la derniere :
la cause doit rester explicite au lieu de choisir automatiquement un vieux fichier.

Voir [RESULTATS_WINDOWS.md](RESULTATS_WINDOWS.md) pour les telechargements
constructeurs reels et les tests de la beta deja termines. Aucun test de miroir
externe n'est inclus dans ces reussites.
