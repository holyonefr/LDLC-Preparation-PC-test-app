# LDLC Préparation PC — bêta 2.6.16

Widgets désinstallé est maintenant reconnu après une lecture Appx réussie ; une
lecture refusée reste inconnue. Un envoi sans accusé est affiché « Transmission
non confirmée », car le serveur peut déjà avoir enregistré le rapport. La file
durable et les vrais blocages sont conservés. Voir
[le diagnostic et les tests](beta/WIDGETS_TRANSMISSION_2026-10-23.md).

Correction des faux avertissements Chrome, Widgets et des variantes de détection
PDF Adobe, avec contrôle final Windows en lecture seule. Voir
[les causes et les limites des tests](beta/DEFAULT_WARNINGS_2026-10-23.md).
Cette nouvelle correction est publiée uniquement en bêta. La publication 2.6.14
dans les productions ci-dessous reste inchangée.

La livraison du 22 octobre 2026 est publiée et testée sous Windows. Sur autorisation
explicite de l’utilisateur, ses fonctions acceptées sont aussi intégrées à LDLC,
Numerik’s et ADDON. **Le module carte mère n’est plus réservé à la bêta.**
Voir [la livraison et les preuves Windows](PROMOTION_BETA_2026-10-22.md).

À la fin des applications (60 %), préparation d’un installateur constructeur
vérifié et de son raccourci sur le vrai Bureau, redirection comprise. MSI Center,
ASUS DriverHub, GIGABYTE Control Center ou ASRock APP Shop. Le technicien lance
l’installation manuellement. Les portables sont exclus avant réseau/raccourcis.
Aucun pilote, BIOS, antivirus, module facultatif ou recherche de mise à jour n’est
lancé par cette fonctionnalité. Le repli vers la page officielle est clairement
signalé et ne prétend jamais qu’un installateur a été téléchargé ou installé.

La bêta conserve ses adaptations et son identité. Les interfaces locales des
productions ne sont pas écrasées. Les sources communes sont maintenant synchronisées
avec la livraison LDLC ; `beta/sync.json` donne le commit source et les overlays,
`beta/stable-files.json` leurs empreintes de référence. Le checkout source garde
un ancien changement UI non publié : `SourceWorkingTreeDirty=true` l’indique.

```powershell
# Audit sans écriture : tout retard ou conflit exige une fusion explicite.
./tools/Sync-LDLCBeta.ps1 -StableRepository ../LDLC-Preparation
# Après revue des changements ordinaires :
./tools/Sync-LDLCBeta.ps1 -StableRepository ../LDLC-Preparation -Apply
```

`-AcceptMergedOverlays` ne s’utilise qu’après revue/fusion des adaptations signalées.
Le helper ne pousse pas et ne copie jamais les EXE stables. Chaque correction
future doit conserver cette synchronisation. Les exceptions de publication
autorisées sont consignées dans AGENTS.md ; ne pas en déduire une autorisation
générale de déployer Apps Script ou de publier un autre travail.

Utiliser `dist/LDLCPreparationPC.exe` de ce dépôt. Le workflow manuel
`beta-validation.yml` compile, teste et ouvre quatre fois son EXE avant publication.
Les installations matérielles sont simulées ; les téléchargements/signatures et
raccourcis réels sont distingués dans le rapport. Un GPU physique et l’épingle
Chrome visible restent à vérifier sur poste. Les anciennes notes dans `beta/`
et PASSATION_PROJET.md retracent les états antérieurs et leurs limites.
