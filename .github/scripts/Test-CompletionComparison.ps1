$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$baseline=Join-Path ([IO.Path]::GetTempPath()) ('Preparation-Baseline-'+[guid]::NewGuid().ToString('N'))
$reports=Join-Path $root 'artifacts/comparaison'
New-Item -ItemType Directory -Path $baseline,$reports -Force | Out-Null
$powershell=Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'
try {
    # The beta was copied without the private stable repository's Git history.
    # Use the frozen, sanitized test fixture rather than depending on that history.
    $fixture=Join-Path $root 'tools/fixtures/completion-before-c205efc'
    $manifest=Get-Content (Join-Path $fixture 'manifest.json') -Raw | ConvertFrom-Json
    if($manifest.SourceCommit -cne 'c205efc7150bc0d2af55b7c0a4dc3bce617f68ed'){throw 'Reference historique de comparaison incorrecte.'}
    $files=@('00.Core.ps1','05.Telemetry.ps1','90.Workflow.ps1','99.UI.ps1')
    if($manifest.Files.Count -ne $files.Count){throw 'Fixture de comparaison incomplete.'}
    foreach($file in $files) {
        $entry=@($manifest.Files|Where-Object Name -ceq $file)
        $path=Join-Path $fixture $file
        if($entry.Count -ne 1 -or (Get-FileHash $path).Hash -cne $entry[0].SHA256){throw "Fixture historique modifiee ou absente : $file"}
        Copy-Item -LiteralPath $path -Destination (Join-Path $baseline $file)
    }
    $test=Join-Path $root 'tools/Test-PreparationCompletion.ps1'
    $previous=$ErrorActionPreference
    try {
        $ErrorActionPreference='Continue'
        & $powershell -NoProfile -File $test -ModuleRoot $baseline -ReportPath (Join-Path $reports 'avant.json') *> (Join-Path $reports 'avant.log')
        $beforeCode=$LASTEXITCODE
    } finally { $ErrorActionPreference=$previous }
    $before=Get-Content -LiteralPath (Join-Path $reports 'avant.json') -Raw | ConvertFrom-Json
    if($beforeCode -eq 0 -or $before.Scenarios.Count -ne 7 -or @($before.Checks | Where-Object {-not $_.Passed}).Count -eq 0){throw 'Le test doit reproduire les anomalies de lancienne version.'}
    & $powershell -NoProfile -File $test -ReportPath (Join-Path $reports 'apres.json')
    $afterCode=$LASTEXITCODE
    if($afterCode -ne 0){throw "Correction en echec : $afterCode"}
    $after=Get-Content -LiteralPath (Join-Path $reports 'apres.json') -Raw | ConvertFrom-Json
    if($after.Scenarios.Count -ne 11 -or @($after.Checks | Where-Object {-not $_.Passed}).Count -ne 0){throw 'Scenarios corriges incomplets.'}
    Write-Host "OK comparaison Windows : 7 scenarios communs avant/apres et 3 scenarios de relance et echec de lancement Windows Update corriges; ancien code $beforeCode attendu, code corrige $afterCode."
} finally {
    if((Split-Path $baseline -Leaf) -like 'Preparation-Baseline-*'){Remove-Item -LiteralPath $baseline -Recurse -Force -ErrorAction SilentlyContinue}
}
