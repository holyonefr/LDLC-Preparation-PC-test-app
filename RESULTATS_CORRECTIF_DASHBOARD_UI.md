# Controle du dashboard et interface ADDON — 17 octobre 2026

## Incident observe

Lors des quatre passages par edition, les douze lancements et sous-tests Windows avaient reussi. Un controle distant ADDON avait echoue avec WebException pendant le scenario arret ; succes et erreur 1603 avaient deja ete confirmes, et les seuls rapports de test avaient ete nettoyes. Le code HTTP et la requete exacte de cet incident historique ne sont pas connus. Aucun diagnostic ne permet d’attribuer cet incident a un defaut du lancement ou d’affirmer une perte d’envoi.

Le controle lisait le dashboard une seule fois et abandonnait sur la premiere panne temporaire. Cette fragilite est corrigee dans l’outil de verification commun aux trois editions.

## Correctif

`PreparationDashboardRead.Common.ps1` relit uniquement les GET en echec temporaire : HTTP 408/429/500/502/503/504, expiration ou coupure reseau. Limite de trois tentatives, pauses de 1 puis 2 secondes, timeout de 45 secondes par requete. Les erreurs de droits, de certificat/TLS et de contrat JSON invalide ne sont pas retentees et restent clairement en echec. Aucune validation n’est inventee a partir d’une reponse invalide.

Les rapports indiquent maintenant la phase exacte (lecture initiale/finale de chaque scenario ou controle de nettoyage), le nombre de tentatives, la categorie reseau, le statut HTTP lorsqu’il est disponible et la duree. Les URL authentifiees, corps HTTP et messages d’exception susceptibles de contenir une cle ne sont pas exposes.

Cette modification concerne le banc de verification, pas les POST du client, la file durable, les associations, Windows Update ni les regles de validation. Aucun changement ou deploiement Apps Script.

## Interface ADDON

La mention « Informatique de bualite » est retiree du fond. Image 1672x771, alpha et pixels hors rectangle x337/y78/345x35 identiques a la version precedente. Les logos, panneaux, bouton Quitter et autres controles sont preserves. L’EXE ADDON embarque le nouvel asset ; ses 113 methodes et ses quatre ressources natives Windows restent identiques. Le fond LDLC et Numerik’s ne change pas.

## Verifications effectuees

- Ancien appel unique : erreur temporaire 503 reproduite et abandon immediat confirme dans le test comparatif.
- Nouveau lecteur : 29 scenarios, 140 assertions locales reussies. Reprise apres erreur temporaire, conservation du vrai statut arret, refus des erreurs permanentes/TLS, echec explicite apres trois tentatives, JSON invalide refuse, absence de fuite des donnees sensibles.
- Suite locale ADDON complete reussie, y compris correspondance entre les ressources de l’EXE et les assets, tests Trackman simules, demarrage, Chrome, absence du validateur et NVIDIA.
- Syntaxe des neuf scripts de controle des trois depots verifiee ; contenu et SHA-256 des 79 fichiers partages concordants.
- Comparaison du PNG : seule la zone du sous-titre differe, transparence exacte conservee ; image examinee apres integration.

Le test `Test-PreparationCoreSync.ps1` a echoue sous Linux avec « Chemin hors depot » dans son controle de chemin Windows. Ce resultat n’est pas presente comme une reussite. Les empreintes et contenus partages ont ete verifies directement ; le controle natif reste reserve a Windows. Le rendu natif WinForms est egalement signale non execute localement.

## Tests distants et e-mails

A la demande de l’utilisateur de stopper les e-mails, aucun nouveau workflow GitHub n’est declenche pour ce correctif. Aucun fichier de workflow n’est modifie ; les chemins modifies ne declenchent pas les workflows Windows existants. Les nouveaux controles et le nouvel EXE ne sont donc pas encore revalides sur un runner Windows apres cette correction.

Les sources PrepTool examinees ne contiennent pas d’envoi MailApp/GmailApp/sendEmail. L’origine des mails (notifications GitHub, Codex ou autre service) reste a confirmer. Les preferences d’e-mail du compte ne sont pas accessibles par les outils disponibles ; leur desactivation n’est pas revendiquee. Les lancements GitHub restent suspendus pour eviter de nouveaux messages de ce service.
