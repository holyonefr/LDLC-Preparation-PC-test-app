param(
    [Parameter(Mandatory = $true)][string]$SourceRepository,
    [Parameter(Mandatory = $true)][string]$TargetRepository,
    [switch]$Apply,
    [switch]$BuildAndTest,
    [switch]$Publish
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'PreparationSync.Common.ps1')
. (Join-Path $PSScriptRoot 'PreparationDelivery.Common.ps1')
if ($Publish) { $Apply = $true; $BuildAndTest = $true }
if ($BuildAndTest -and -not $Apply) { throw '-BuildAndTest exige -Apply.' }
$plan = Get-PreparationSyncPlan $SourceRepository $TargetRepository
$allowedRepositories = @('https://github.com/holyonefr/LDLC-Preparation.git', 'https://github.com/holyonefr/Numerik-s-Preparation-PC.git')
$seenOrigins = @()
foreach ($root in @($plan.SourceRoot, $plan.TargetRoot)) {
    $edition = [IO.File]::ReadAllText((Get-PreparationSyncPath $root 'sync/edition.json')) | ConvertFrom-Json
    $origin = & git -C $root remote get-url origin
    if ($LASTEXITCODE -ne 0 -or $origin -ne $edition.Repository -or $origin -notin $allowedRepositories) { throw "Depot/edition incoherent : $root" }
    if ($origin -in $seenOrigins) { throw 'La synchronisation exige une edition LDLC et une edition Numeriks.' }
    $seenOrigins += $origin
    if ($Publish) {
        if ((& git -C $root branch --show-current) -ne 'main') { throw 'Publication uniquement depuis main.' }
        & git -C $root fetch origin
        if ($LASTEXITCODE -ne 0) { throw 'Verification GitHub impossible.' }
        & git -C $root merge-base --is-ancestor origin/main HEAD
        if ($LASTEXITCODE -ne 0) { throw "Recuperer et integrer origin/main avant publication : $root" }
        $dirty = @(& git -C $root -c core.quotepath=false diff --name-only HEAD) + @(& git -C $root -c core.quotepath=false ls-files --others --exclude-standard)
        $allowed = @($plan.Entries.Path) + @('sync/state.json') + (Get-PreparationDelivery $root).ArtifactPaths
        $other = @($dirty | Where-Object { $_ -notin $allowed })
        if ($other.Count) { throw "Commiter les personnalisations/documents separement avant -Publish : $($other -join ', ')" }
    }
}
$plan.Entries | Where-Object Action -ne Identical | Select-Object Action,Path | Format-Table -AutoSize
if (-not $Apply) {
    Write-Host 'Audit seul. Ajouter -Apply, ou -Publish pour synchroniser, compiler, tester et pousser les deux depots.'
    if (@($plan.Entries | Where-Object Action -eq Conflict).Count) { throw 'Conflits detectes : aucun fichier modifie.' }
    return
}
Invoke-PreparationSyncPlan $plan
if ($BuildAndTest) {
    $powershell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    foreach ($root in @($plan.SourceRoot, $plan.TargetRoot)) {
        $version = (Get-Content -LiteralPath (Join-Path $root 'sync/core-version.json') -Raw | ConvertFrom-Json).ToolVersion
        if ($version -notmatch '^\d+\.\d+\.\d+$') { throw 'Version technique invalide.' }
        & $powershell -STA -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tools\Build-LDLCPreparationPCExe.ps1') -Version ($version + '.0')
        if ($LASTEXITCODE -ne 0) { throw "Compilation en echec : $root" }
        & $powershell -STA -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tools\Test-LDLCRelease.ps1')
        if ($LASTEXITCODE -ne 0) { throw "Tests en echec : $root" }
    }
}
if ($Publish) {
    foreach ($root in @($plan.SourceRoot, $plan.TargetRoot)) {
        $files = @($plan.Entries.Path | Where-Object { Test-Path -LiteralPath (Join-Path $root $_) }) + @('sync/state.json') +
            @((Get-PreparationDelivery $root).ArtifactPaths | Where-Object { Test-Path -LiteralPath (Join-Path $root $_) })
        & git -C $root add -- @files
        if ($LASTEXITCODE -ne 0) { throw 'Git add en echec.' }
        & git -C $root diff --cached --check
        if ($LASTEXITCODE -ne 0) { throw 'Diff Git invalide.' }
        & git -C $root diff --cached --quiet
        if ($LASTEXITCODE -eq 1) {
            & git -C $root commit -m 'Synchronize shared preparation core; preserve edition visuals'
            if ($LASTEXITCODE -ne 0) { throw 'Commit en echec.' }
        }
    }
    # Both builds/tests/commits precede either push. Git cannot atomically push two repositories.
    foreach ($root in @($plan.SourceRoot, $plan.TargetRoot)) {
        & git -C $root push origin main
        if ($LASTEXITCODE -ne 0) { throw "Push en echec pour $root ; relancer apres correction reseau/authentification." }
    }
}
Write-Host 'Coeur synchronise. UI, logos, images, fonds Windows et connexions de chaque edition conserves.'
