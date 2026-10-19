# Tests Windows des quatre applications — 19 octobre 2026

**12 passages sur 12 reussis**, sur Windows Server 2022 / Windows PowerShell 5.1.
Aucun echec des applications detecte dans ces batteries. Les 66 controles de haut
niveau terminent avec le code de sortie 0 ; ils contiennent eux-memes les suites
release, comparaisons et controles specialises. 21 Preview/fermetures explicites
du vrai EXE sont confirmes, sans compter les diagnostics et formulaires internes.

| Application | Passages | Controles de haut niveau | Preview/fermetures explicites | Dashboard permanent |
|---|---|---:|---:|---|
| LDLC-Preparation | [3/3](https://github.com/holyonefr/LDLC-Preparation/actions/runs/39214000180) | 12 | 3 | 3 scenarios reels reussis, essais nettoyes |
| LDLC-Preparation-Addon | [3/3](https://github.com/holyonefr/LDLC-Preparation-Addon/actions/runs/39214000300) | 9 | 3 | 3 scenarios reels reussis, essais nettoyes |
| LDLC-Preparation-PC-test-app | [3/3](https://github.com/holyonefr/LDLC-Preparation-PC-test-app/actions/runs/39214348903) | 30 | 12 | Non execute sur le backend permanent |
| Numerik-s-Preparation-PC | [3/3](https://github.com/holyonefr/Numerik-s-Preparation-PC/actions/runs/39214000170) | 15 | 3 | 3 scenarios reels reussis, essais nettoyes |

## Ce qui a ete teste

- Integrite de l'EXE livre, veritable entree Preview, affichage et bouton Quitter.
- Compilation native et suites release de LDLC, Numerik's et beta ; pour l'Addon,
  synchronisation principale/worker, ressources, regressions et diagnostics de
  l'EXE existant, sans nouvelle compilation ps2exe.
- Onze scenarios de finalisation corriges par passage, soit **132 executions**
  dans les douze passages : fin normale, fermeture apres fin, erreur, avertissement,
  delai simule, fermeture anticipee, hors ligne, echec du declenchement Windows Update,
  relances avec acquittement, hors ligne et impossibilite de sauvegarde de la file.
- Comparaison avec les sept scenarios historiques communs : l'ancien code doit
  reproduire les anomalies, le code actuel doit passer tous les controles.
- Chrome, associations par defaut, raccourcis, securite, Windows Update et autres
  etapes couvertes par les suites release, avec operations systeme simulees.
- Addon : les deux arbres principal/worker, Chrome, Trackman avec donnees de test,
  fraicheur NVIDIA, absence de validateur et des dependances Adobe selon les tests
  de l'edition. Ces tests n'installent pas Trackman/NVIDIA sur la VM.
- Numerik's : selecteur de boutique, ressources et tests propres a son edition.
- Beta : trois fois les tests d'integration constructeur, exclusion des portables,
  erreurs explicites, placement a 60 % en fin Installation et synchronisation ;
  quatre Preview par passage, dont une de l'EXE livre et trois du nouvel EXE compile.

## Dashboard : neuf scenarios reels

LDLC, Numerik's et Addon ont chacun envoye trois rapports d'essai uniques :
succes, erreur injectee 1603 et arret. La presence initiale, la fin explicite,
l'acquittement, l'edition/version et la cause 1603 ont ete verifies sur le serveur.
Les statuts observes sont respectivement `success`, `error` et `stopped`.
Les neuf lignes creees par les tests ont ete supprimees et leur absence controlee ;
aucun historique client n'a ete supprime.

**Limite : le champ detaille `validation.state` n'est pas expose par les reponses
live consultees** (`non_exposee` dans les neuf observations). Ces tests confirment
la reception et les statuts, pas l'etat metier detaille `validated/blocked` du
service deploye. Le code Apps Script local est teste par les suites JS ; cela
ne prouve pas que le meme code est actuellement deploye.

La beta ne fait pas de test live separe sur le backend de production, conformement
au garde du workflow. Les tests de telemetrie et de finalisation de la beta utilisent
des fixtures ; les tests reels des trois editions restent une preuve distincte.

## Correction du test beta

Le depot beta a ete copie sans l'historique Git du depot stable. Son test avant/apres
cherchait donc un commit absent, `c205efc7150bc0d2af55b7c0a4dc3bce617f68ed`.
Le helper beta utilise maintenant quatre fichiers historiques de test figes,
accompagnes d'empreintes SHA256. Adresses et identifiants de configuration sont
remplaces par des valeurs inertes. Ces fichiers ne sont pas embarques dans l'EXE.

Verification locale : ancien code, 7 scenarios / 32 controles avec 17 anomalies
attendues et code de test 1 ; code actuel, 11 scenarios / 66 controles sans echec
et code 0. Les trois passages Windows de la beta confirment ensuite la comparaison.
Aucun controle n'a ete retire ou rendu facultatif pour obtenir ces reussites.
Seuls les tests et leur documentation beta ont ete modifies ; aucun fonctionnement
d'application de production, endpoint permanent, UI ou image n'a ete change.

## Limites et preuves

Les lancements d'EXE, les compilations et les echanges dashboard sont reels.
Les installations, desinstallations et actions systeme du parcours sont simulees.
Ces passages ne sont pas une preparation destructive de PC neuf et ne prouvent
pas l'installation de pilotes/logiciels sur du materiel physique. Les nouveaux
miroirs et telechargements constructeurs ne sont pas retestes par cette batterie.
Les mesures de sous-tests en secondes incluent le processus de test ; elles ne
sont pas des mesures du temps d'ouverture de l'interface.

Les rapports dans `evidence/full-suite-2026-10-19/` sont une projection des resultats
GitHub : codes, etapes, compteurs de tests et donnees d'essai uniquement. Aucun
poste, journal client, identifiant de connexion ni URL d'administration n'est publie.
Une annotation de lecture globale du dashboard LDLC est tronquee par GitHub ;
seuls ses champs initiaux complets sont conserves et elle est marquee comme telle.
Les trois rapports roundtrip sont complets.

Les trois references de production sont verifiees inchangees dans
`production-freeze.json`. Les workflows existants y ont ete declenches manuellement,
sans aucun push ni deploiement. Seul le depot beta recoit la correction du test
et les comptes rendus. Tous les workflows de la beta restent manuels.
