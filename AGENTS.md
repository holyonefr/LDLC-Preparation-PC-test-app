# LDLC Preparation PC — beta

Read BETA.md and PASSATION_PROJET.md before editing.
This repository is holyonefr/LDLC-Preparation-PC-test-app, the user-authorized beta.
Stable source: holyonefr/LDLC-Preparation. Preserve its UI, images and Google links.

Current user instruction: push changes ONLY to this beta repository. Do not run
Sync-PreparationCore.ps1 -Publish, deploy Apps Script, or push any of the three
production All in App repositories without a new explicit user instruction.

Keep this beta synchronized for every subsequent requested correction. Audit
tools/Sync-LDLCBeta.ps1 against the stable checkout, merge any reported overlay
conflicts, then rebuild and test the beta. Record source commit and overlay files
in beta/sync.json. Never overwrite beta integrations with an older stable EXE.
The sync helper never pushes; all publication commands must verify the beta origin.

The motherboard feature prepares verified installers and Desktop shortcuts only.
Exclude laptops before network or shortcuts. Do not execute real motherboard
installers on GitHub VMs or enable automatic driver/BIOS/firmware/module installation.
Run the native beta validation workflow after code changes; preserve test evidence.

2026-10-20: the user explicitly authorized "Push sur les trois" for this Chrome
default/taskbar and laptop AMD correction. Production publication of this delivery
is authorized; preserve the beta-only motherboard feature and resynchronize beta.

2026-10-20: the user also authorized the historical McAfee rollback in all three
production repositories, with Norton parity checks. Transmission recovery is
currently prepared in beta; other publication restrictions remain in effect.

2026-10-20: the user explicitly said "Oui envoie sur les 4" for transmission
recovery. Publish this correction and its Windows-tested deliveries in all four
repositories. Preserve beta-only motherboard integration and unrelated local UI.

2026-10-22 explicit user authorization: "Ok push sur les trois" for the verified
AMD official/Chocolatey correction, plus restoration of historical Chrome taskbar
preparation. Publish LDLC and Numerik's AMD changes, and Chrome changes in all three
production editions. ADDON stays NVIDIA-only. Keep beta synchronized, preserve
beta-only motherboard integration and pre-existing unpublished UI edits.

2026-10-22 further explicit authorization: the user requested synchronizing all
working beta features into Numeriks, LDLC and ADDON. The motherboard installer/
Desktop-shortcut feature is now authorized in all three productions (no longer
beta-only). Keep laptops excluded, manual vendor installation, each edition's
branding and existing exceptions; ADDON remains NVIDIA-only. Keep beta synchronized.
Preserve the canceled font enlargement and other unpublished UI edits.

2026-10-23 explicit user scope: "je veut que tu retire le message d'erreur pour les quatre". Implement and deliver the scoped Widgets nonblocking diagnostic and neutral saved-report completion display in all four editions, with native Windows checks and tested EXEs. Preserve unrelated beta differences and the pre-existing unpublished UI edits; no blanket production promotion or Apps Script deployment.

2026-10-24 explicit continuation after the LDLC candidate VM diagnosis: the user
said "Alors change .html et fait un clique chrome si tu peut, push avant ! Et
relance une vm w11 pour voir !". Publish the requested LDLC correction and its
Windows-validated EXE before one fresh Windows 11 test. Include the already
reviewed LDLC candidate changes (informational Chrome diagnostics and Office
preservation); preserve unpublished UI, branding, Google URLs and existing GPU
behavior. This authorizes LDLC only, not Numeriks or ADDON. Keep beta synchronized
without overwriting its additional fixes. No Apps Script deployment.
