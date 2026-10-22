# Promotion de la bêta dans les trois éditions — 22 octobre 2026

Autorisation explicite utilisateur : synchroniser les fonctions validées de la bêta
avec LDLC, Numerik’s et ADDON. Cette demande remplace la restriction carte mère
réservée à la bêta. Versions candidates : LDLC/Numerik’s/bêta 2.6.14, ADDON 2.0.3.

- Le module carte mère intervient à la fin des applications (60 %), avant la
  configuration. MSI Center, ASUS DriverHub, GIGABYTE Control Center ou ASRock
  APP Shop : téléchargement vérifié et raccourci sur le Bureau réel, y compris
  OneDrive. Installation manuelle par le technicien ; aucun logiciel constructeur,
  module facultatif, antivirus, pilote ou BIOS n’est installé automatiquement par
  ce module. Portables exclus avant réseau et raccourcis. Si le téléchargement
  échoue, un repli officiel est clairement indiqué ; aucun faux succès.
- Les cinq sources PowerShell utiles sont embarquées dans principal et worker ;
  leurs empreintes sont vérifiées avant import. Aucun téléchargement constructeur
  au lancement de l’interface. Les sources et tests du prototype validé sont repris.
- Détection corrigée d’Edge encore épinglé : une application installée ne suffit
  plus à conclure que son épingle reste présente. Une fenêtre Edge encore ouverte
  n’est plus présentée comme un échec de retrait de l’épingle.
- AMD officiel/Chocolatey et retour Chrome historique sont conservés. ADDON reste
  NVIDIA uniquement, garde Trackman, son absence d’Adobe/Validator et son identité.
  Les boutiques et fonds Numerik’s sont préservés. Les changements UI locaux et
  l’agrandissement de texte annulé ne sont pas transférés.

Les trois scénarios dashboard Numerik’s de la tentative précédente ont été
acquittés, mais le contrôle de nettoyage a échoué. Les trois rapports d’essai ont
été supprimés séparément et leur absence vérifiée. Le helper d’administration des
TESTS retente désormais au maximum trois fois les seuls appels idempotents sur
erreur réseau transitoire. Le résultat du nettoyage repose sur un état serveur
acquitté et l’absence effective des seuls rapports CODEX-TEST possédés. Les erreurs
d’autorisation et réponses invalides ne sont pas ignorées. Aucun changement au
transport de production, à l’acquittement d’une intervention ou à sa validation.

Validation Windows native en cours : suites, intégration embarquée des deux scripts,
placement, exclusions portables, replis, vrais téléchargements des quatre marques
sur une campagne commune, quatre lancements EXE et trois échanges dashboard par
édition. Aucun installateur matériel réel n’est lancé sur GitHub. Les tests simulés
et les opérations réelles seront distingués dans les preuves de livraison.
