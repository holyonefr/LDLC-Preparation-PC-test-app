# Historical completion fixture: tests only

Sanitized copies of four modules from LDLC-Preparation commit
`c205efc7150bc0d2af55b7c0a4dc3bce617f68ed`, used only by
`.github/scripts/Test-CompletionComparison.ps1`.

The beta does not contain that stable repository's Git history. The fixture makes
the expected before/after regression reproducible without a private history fetch.
`manifest.json` records the source commit, original file hashes, stored hashes and
redaction counts. Windows checkout preserves exact bytes using `.gitattributes`.
All URLs and known configuration credentials have inert replacements. The scenario
harness replaces network and system operations; old failures are expected.

These files are not runtime modules and must never be added to `modules/build-order.txt`,
packaged into the EXE or invoked as a preparation on a PC. The test must still fail
on the historical defects and pass the current eleven scenarios.
