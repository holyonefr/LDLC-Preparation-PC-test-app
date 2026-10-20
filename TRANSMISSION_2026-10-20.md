# Transmission des résultats — livraison du 20 octobre 2026

Publication autorisée par l’utilisateur : « Oui envoie sur les 4 ».
Les sources et les EXE ci-dessous sont publiés après validation Windows.

Le rapport est sauvegardé avant envoi. Le délai par défaut est de 30 s et le
réglage reste respecté jusqu’à 60 s. Une panne temporaire autorise un seul
réessai. Le rapport courant passe en premier dans un lot borné ; seuls les
rapports explicitement acquittés quittent la file durable. Une intervention
incomplète ou en erreur n’est jamais forcée en réussite.

| Dépôt | Version | Tests GitHub Actions | Livraison EXE |
| --- | --- | --- | --- |
| LDLC-Preparation | 2.6.10 | [Windows 39455086205](https://github.com/holyonefr/LDLC-Preparation/actions/runs/39455086205) | `b36234bfb002` |
| Numerik-s-Preparation-PC | 2.6.10 | [Windows 39455089955](https://github.com/holyonefr/Numerik-s-Preparation-PC/actions/runs/39455089955) | `b9fe1a4d7527` |
| LDLC-Preparation-Addon | 2.0.1 | [Windows 39455092562](https://github.com/holyonefr/LDLC-Preparation-Addon/actions/runs/39455092562) | `50684bf1ca57` |
| LDLC-Preparation-PC-test-app | 2.6.10 | [Windows 39455096015](https://github.com/holyonefr/LDLC-Preparation-PC-test-app/actions/runs/39455096015) | `dee5689627d0` |

Chaque édition a passé sa suite de régression, quatre ouvertures/fermetures du
véritable EXE en mode Preview et trois échanges réels avec le dashboard permanent :
fin normale → `validated`, erreur 1603 → `blocked`, arrêt → `blocked`. Les rapports
de test créés ont été supprimés ; aucun historique client n’a été effacé.
Les EXE récupérés de GitHub correspondent aux SHA-256 attestés par les runners.

La reprise d’envoi couvre 12 scénarios / 35 assertions avec réponses HTTP simulées
et une véritable file locale isolée. L’ADDON vérifie ses deux arbres de modules.
Les opérations Windows sensibles (clics Chrome, épinglage, antivirus et matériel)
sont simulées dans leurs scénarios ; ces tests ne prouvent pas une préparation
complète sur un PC client ni un clic réel dans les Paramètres Windows 10/11.

Le premier passage Numerik’s a échoué avant tout rapport, pendant le contrôle
réseau du droit de nettoyage. La nouvelle tentative du même commit a passé tous
les contrôles ; cet incident n’a pas été masqué en succès.

Le dashboard a ensuite été publié en version **47**, à la demande de l’utilisateur,
pour éclaircir le thème et revoir les titres. Cette publication ne change que
le CSS ; URL, configuration, Sheet, logique et manifeste sont conservés.
Voir [le compte rendu visuel](DASHBOARD_STYLE_2026-10-20.md).

Les anciens changements UI locaux des applications sont exclus des EXE publiés.
Les marques, ressources et particularités ADDON restent distinctes. L’intégration
carte mère reste exclusivement dans la bêta.

Les preuves détaillées et empreintes figurent dans
`tools/google-apps-script/evidence/2026-10-20-style/transmission-windows.json`.
