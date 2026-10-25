# Affichage dynamique - BETA 2.6.21 - 25 octobre 2026

## Reprise et demande

Source : https://github.com/holyonefr/LDLC-Preparation-PC-test-app, main 4e3263b98202de74abd2f949a99909d8621e1a43.
Reprise de la derniere demande de la tache Cloud Configurer LDLC-Preparation :
barre parasite et bouton Quitter apres changement d'affichage. Le 25 octobre,
l'utilisateur a explicitement demande cette correction sur LDLC, LDLC test,
Numerik's et ADDON, avec publication sur les quatre GitHub.

## Correction limitee a l'interface

Windows redimensionnait la fenetre au changement de DPI, mais les coordonnees
scaleX/scaleY, l'image, la region arrondie et le bouton restaient ceux du demarrage.
Update-LDLCMainUiLayout reconstruit ensemble ces elements depuis l'image originale
lorsque le moniteur, le DPI, la zone de travail ou la taille client change.
Le timer UI existant execute ce controle sur son propre thread toutes les 250 ms.
Les polices du canvas utilisent maintenant des pixels : Windows ne multiplie
plus une deuxieme fois leur hauteur par le zoom. Les minima suivent aussi le
canvas aux petites resolutions. La taille compacte validee par l'utilisateur
a 200 % est conservee : pas d'agrandissement proportionnel au DPI (47 % de la
zone de travail, 50 % pour le style ADDON existant). La lecture native
GetDpiForWindow detecte les changements, sans modifier les parametres Windows.
La hauteur du titre de statut est mesuree avec GDI pour eviter le rognage
du dernier pixel. Le cadre du pourcentage accepte 100 % sur une seule ligne ;
les rectangles titre/detail des phases ne se chevauchent plus a cause des arrondis.
Cas supplementaire detecte par la VM Windows GitHub : Win32 peut limiter la
taille demandee sur un petit bureau/session distante. Le handle est cree avant
le calcul final et l'image est ajustee a la taille reelle acceptee, sans etirement
ni bande vide. Un test avec MaximumSize=700x400 reproduit l'echec precedent
et verifie sa correction. ClientSize seul pouvait rester en cache trop longtemps.
Sans changement, aucune image n'est recreee. Le mode minimise reste minimise.
Les anciennes ressources remplacees sont liberees sans detruire une police encore
utilisee par WinForms. L'aspect et le positionnement propres a l'edition restent
conserves ; la beta garde notamment son pied de fenetre natif et ses integrations.
Seul le mutex du mode Preview est isole par processus pour permettre les essais
cote a cote. Le verrou de la vraie preparation ne change pas.

Aucune modification des installations, associations Adobe/Chrome, telemetrie
hors numero de version ADDON, GPU, fonds Windows, logos ou choix des boutiques.
Aucun nouveau Google Sheet, lien, deploiement Apps Script ou remise a zero.

## Livraison et controles

- Version logique : 2.6.21.
- Executable : dist/LDLCPreparationPC.exe.
- SHA256 : D7DE8D07982525F5AE2BE630E67E7F33BE9652D5A5B866981ACD68C0908CA57F.
- Suite native : 54 PowerShell tests, 3 JavaScript suites, launcher bootstrap/selftest/worker. Resultat : reussie.
- Test-UiDisplayChanges : 838 assertions (806 dans ADDON), 32 changements de resolution/DPI,
  GDI natif a 67/96/120/144/168/192/216 DPI, quatre zones de travail dont un
  ecran aux coordonnees negatives, coins,
  surface sans bande vide, position du bouton, vrai rendu du texte et cache stable.
- Test-UiCanvasGeometry : 5355 assertions (5145 ADDON), 105 rendus GDI reels
  par arborescence, cinq tailles de canvas et sept DPI. Controle des textes,
  espaces entre phases, barre, detail, statut et pourcentage a 0/47/100 %.
- ADDON teste aussi worker-modules ; son lanceur PS2EXE historique est conserve
  et ses scripts sont reconditionnes avec Update-AddonEmbeddedScripts.ps1.
  Sa version native historique 2.0.0.0 est volontairement conservee ; le numero
  logique de livraison/remontee est 2.0.5. Les autres lanceurs sont recompiles.
- Les quatre vrais EXE ont ete ouverts puis fermes en Preview par le pilote
  Windows du depot, captures et geometries conservees dans evidence/ui-display-2026-10-25/.
- Cycle reel de zoom sur les quatre premieres compilations de cette livraison :
  150/100/125/175/200/150 %. LDLC, Numerik's et beta inspectes a l'ecran ;
  ADDON controle sur son propre thread WinForms avec captures/mesures a chaque
  palier (evidence/ui-display-2026-10-25/live-preview/). Le complement Win32
  a ensuite ete recompile/reteste separement, sans changer ce rendu. Vienne validee dans
  Numerik's. Un seul ecran physique : le changement de moniteur est simule
  par les tests de zones de travail, pas revendique comme deplacement reel.
  70 % est seulement simule au niveau du rendu : ce reglage ne figure pas dans
  le menu Windows de ce PC. Ne pas le presenter comme un essai reel du systeme.
- Reglage initial 2560 x 1440 et zoom 150 % conserve/restaure.

Les tests ne constituent PAS quatre preparations completes. Pas d'installation,
modification des applications par defaut ou envoi de nouvelles lignes client au
Google Sheet. Le premier essai de compilation ADDON et les incidents du lanceur
manuel de diagnostic ont ete corriges avant livraison et sont traces dans
validation.json ; ils ne sont pas comptes comme reussis. L'ancien apercu LDLC
2.6.18 eleve reste distinct du nouvel EXE : les outils non eleves ne peuvent pas
le fermer. Il n'est pas inclus dans la livraison.

## Publication et VM Windows

Premiere livraison publiee et verifiee par Git LFS. Le controle GitHub supplementaire
a reproduit un cas de taille HWND imposee sur petit bureau (run 40173825998).
Cette compilation corrige ce cas ; suite locale 54 tests et vrai Preview reussis.
Nouvelle verification distante en cours. Ne pas compter le premier run comme reussi.

## Reprise sur un autre PC

Lire AGENTS.md si present, PASSATION_PROJET.md et cette note. Recuperer origin/main
du depot de l'edition, sans importer une ancienne copie de Bureau. Ne pas recopier
le fichier UI complet d'une edition vers l'autre. Adapter seulement le calcul de
surface ; conserver logos, fonds, accueil boutiques, taille et pied de fenetre.
Lancer Test-UiDisplayChanges.ps1, Test-UiCanvasGeometry.ps1 et la suite de release/AddonSync sous Windows
PowerShell 5.1. Recompiler avec l'icone locale (ADDON : reconditionnement historique),
puis Test-PreparationUiLaunch.ps1. Ne jamais lancer le mode installation pour
une simple verification d'affichage. Captures, empreintes et limites dans
[evidence/ui-display-2026-10-25/validation.json](evidence/ui-display-2026-10-25/validation.json).

## Liens permanents inchanges

Google Sheet : https://docs.google.com/spreadsheets/d/1PtMhZC_7dQi7aw278XPQ1udmV9ol5hrD_G4mdSwXWA0/edit

Dashboard HTML : https://script.google.com/macros/s/AKfycbwYe2r5-y8HeyfLjslbq7wI2BdFH0sj7TLJQSiUyeRdt_z7yytyTKsPQPPcT0HUcAci3g/exec?key=LDLC-Dashboard-2026-288d06206918450293ed29d54fefc801