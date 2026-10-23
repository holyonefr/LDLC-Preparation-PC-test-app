# Bêta 2.6.15 — contrôles finaux Chrome, Widgets et PDF

Publication exclusivement dans `holyonefr/LDLC-Preparation-PC-test-app`. Les trois
productions, leur UI locale et les données historiques du dashboard sont préservées.
Le serveur Apps Script n'est pas redéployé.

## Causes et correction

- **Chrome** : une tentative UIA échouée alimentait immédiatement le compteur
  d'avertissements, même si Windows confirmait Chrome à la fin. Les tentatives
  restent dans le diagnostic local ; le bilan final lit à nouveau HTTP, HTTPS,
  `.htm` et `.html`. Un défaut encore présent ou une lecture impossible reste signalé.
- **Widgets** : `PolicyDisabled` était calculé mais ignoré par `Disabled`. Une
  stratégie ordinateur prise en charge pouvait réussir alors que la valeur
  utilisateur `TaskbarDa` restait protégée. Le contrôle reconnaît désormais cette
  stratégie selon la version Windows ; une clé arbitraire à zéro ne suffit pas.
  Les erreurs de la valeur utilisateur ne sont plus attribuées à la stratégie.
- **Adobe** : l'ancien filtre exigeait un ProgID `Acrobat.Document…` ou
  `AcroExch.Document…`. Il refusait `Applications\Acrobat.exe`,
  `Applications\AcroRd32.exe` et les identifiants PDF propres à une édition
  enregistrée d'Adobe. Le contrôle accepte ces variantes seulement si les API
  Windows les donnent effectivement comme association et résolvent un exécutable
  Reader/Acrobat présent. Adobe simplement installé ou enregistré ne suffit pas.

Le nouveau bilan est en lecture seule, juste avant la clôture normale. Il conserve
les vrais avertissements et erreurs des autres étapes et respecte l'annulation.
Les actions de configuration PDF et le choix actuel de l'utilisateur sont inchangés.
Le dashboard reçoit donc les avertissements du résultat final, sans effacer ses
anciennes lignes ni forcer une validation en cas de problème restant.

## Adobe est-il réellement sélectionné ?

Sur les trois anciens tests complets Windows 11 du laboratoire VM, **non** :
Windows indiquait `MSEdgePDF` / `msedge.exe`, confirmé par une lecture indépendante
de `UserChoice`. Leur avertissement Adobe était réel. Ces essais portaient sur LDLC
2.6.14, avant la présente correction. Ils ne prouvent pas l'état du PC du technicien.

Le PC concerné n'est pas accessible dans cette session. Le script
`tools/Get-DefaultAppsDiagnostic.ps1`, lancé dans sa session Windows, relève
l'association effective, l'exécutable, les inscriptions Adobe et le compte actif,
**sans changer aucun paramètre**. Il permet de distinguer un vrai défaut PDF d'un
identifiant Adobe autrefois rejeté ou d'un contrôle exécuté dans un autre compte.

## Validation

- Comparaison avant/après sur les mêmes états simulés : ancien avertissement
  Chrome conservé malgré réussite tardive ; anciennes variantes Adobe rejetées ;
  ancienne stratégie Widgets ignorée. 13 assertions de reproduction historique.
- Correction : 33 assertions couvrant réussite tardive Chrome/Adobe, vrai défaut
  restant, API illisible, annulation, avertissement GPU conservé, non-duplication,
  associations Adobe alternatives et stratégies Widgets Windows 10/11.
- Test natif Windows : API d'association et registre réels, extensions temporaires
  isolées, inscription Adobe simulée et fichier inerte jamais exécuté. Le vrai choix
  PDF reste inchangé. Ce test ne prétend pas installer ni ouvrir Adobe Reader.
- [Validation Windows réussie](https://github.com/holyonefr/LDLC-Preparation-PC-test-app/actions/runs/39947432903)
  le 23 octobre 2026 : compilation, **49 suites PowerShell et 3 suites JavaScript**,
  13 assertions historiques et 33 après correction. Les 33 assertions passent aussi
  sous PowerShell 7. Les 6 contrôles d'API natives passent sous 5.1 et 7.
- Le vrai workflow de clôture passe **13 scénarios / 92 assertions**, y compris
  fermeture après fin, interruption, erreur réelle, hors ligne et relance. Son
  contrôle final réel est exécuté sur des états Windows simulés. Les tests serveur
  utilisent le vrai code Apps Script en mémoire : aucun scénario simulé n'est envoyé
  au dashboard de production, aucun acquittement Google réel n'est revendiqué ici.
- **Quatre ouvertures/fermetures réelles de l'EXE compilé en mode Preview**,
  sans erreur, affichage en 2,205 / 1,127 / 1,105 / 1,136 secondes depuis EntryPoint
  (hors UAC). Ce ne sont pas quatre préparations complètes.
- Le diagnostic en lecture seule sur le runner indique **0 Adobe installé** et
  **MSEdgePDF**. Il ne modifie pas cette association et ne peut donc pas démontrer
  une sélection réelle d'Adobe sur le PC utilisateur.
- Premier passage [39947045335](https://github.com/holyonefr/LDLC-Preparation-PC-test-app/actions/runs/39947045335)
  arrêté dans le test de clôture : sa fixture ne chargeait pas le nouveau contrôle.
  Fixture corrigée puis suite entière relancée ; aucun EXE publié par cet essai.

Les [preuves structurées](evidence/default-warnings-2026-10-23/windows-validation.json)
conservent les étapes, limites et annotations du runner. Livraison EXE :
`040db21f494e1fd1271d00ff50052d8f2f3b1ee8`, source testée :
`2509ca996943d066786fd60cfcdc79fa9064057d`. Le fichier publié a été récupéré et
son SHA256 correspond à celui testé :
`773803383B5E8F02B073150DB418D517A2C39DAB940E1C51EAB668CAE2500948`.
