# Corrections Chrome et McAfee — 20 octobre 2026

Livraison native Windows validee et publiee ; preuves dans
evidence/corrections-2026-10-20/windows.json. La publication de ces deux corrections est autorisee dans les
trois productions. La correction de transmission reste pour le moment en beta.

Chrome : la regression du clic physique force contournait InvokePattern. Le
bouton global reprend cette methode puis un clic observe si necessaire ; le
repli traite HTTP/HTTPS/.htm/.html. Les associations effectives, pas le retour
d'une commande sans effet, confirment le resultat. Verification courte, pas
l'ancienne longue attente. Les restrictions Windows restent respectees.

Epinglage : privilegier le vrai raccourci Chrome du menu Demarrer apres controle
de sa cible, laisser Windows appliquer l'action asynchrone puis verifier le
resultat. Un pin refuse/inoperant devient un avertissement precis. Les autres
applications epinglees ne sont pas remplacees.

McAfee : neuf fonctions historiques comparees a 3aec296b, worker isole borne a
90 secondes, selection McAfee transmise et restauree. Norton garde son parcours
interactif. Le worker genere est teste avec inventaire vide et preparation
interdite pour prouver son mode de lancement sans desinstaller un vrai antivirus.
Le chemin du worker avec espaces est correctement cite. Le module constructeur
reste exclusivement beta ; ADDON conserve Chrome seul et NVIDIA seul.

Tests Linux : actions Chrome, pin immediat/asynchrone/refuse/sans effet, lecture
de cible de raccourci reservee a Windows, annulation, historique McAfee/Norton,
ordre du workflow et syntaxe. Actions Windows et inventaires sont simules ; aucun
vrai antivirus n'est retire. Les tests natifs ajouteront quatre ouvertures de
chaque vrai EXE et trois rapports CODEX-TEST acquittes sur le dashboard permanent,
puis supprimeront uniquement ces propres rapports.

Run valide : https://github.com/holyonefr/LDLC-Preparation/actions/runs/39449343629
EXE SHA-256 : 25C2A85E395BAE74C26F5BE3154D5558926D643E037E98C969870D4649B01E5D
Suite release, quatre vrais lancements Preview et trois rapports reels
acquittes sur le dashboard (success/error/stopped), puis nettoyage confirme.
Le binaire LFS recupere correspond a l empreinte du runner.
