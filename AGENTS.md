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
