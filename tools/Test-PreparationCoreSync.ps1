$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'PreparationSync.Common.ps1')
$policy = Get-Content -LiteralPath (Join-Path $root 'sync/shared-files.json') -Raw | ConvertFrom-Json
foreach ($file in $policy.SharedFiles) {
    Assert-PreparationSharedPath $file @($policy)
    [void](Get-PreparationSyncPath $root $file)
}
function Assert-True([bool]$Value, [string]$Message) { if (-not $Value) { throw $Message } }
function Assert-Rejected([scriptblock]$Action, [string]$Message) {
    $rejected = $false
    try { & $Action | Out-Null } catch { $rejected = $true }
    Assert-True $rejected $Message
}
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('Preparation-Sync-Test-' + [guid]::NewGuid().ToString('N'))
try {
    $a = Join-Path $fixture 'LDLC'
    $b = Join-Path $fixture 'Numeriks'
    foreach ($repo in @($a, $b)) {
        New-Item -ItemType Directory -Path (Join-Path $repo 'sync'),(Join-Path $repo 'modules'),(Join-Path $repo 'assets') -Force | Out-Null
        & git -C $repo init --quiet
        if ($LASTEXITCODE -ne 0) { throw 'Git fixture init failed.' }
        @{ SchemaVersion=1; SharedFiles=@('modules/core.ps1'); ProtectedPaths=@() } | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $repo 'sync/shared-files.json')
        [IO.File]::WriteAllText((Join-Path $repo 'modules/core.ps1'), '# initial')
        [IO.File]::WriteAllText((Join-Path $repo 'assets/logo.png'), $repo)
        [IO.File]::WriteAllText((Join-Path $repo 'modules/99.UI.ps1'), "# UI propre : $repo")
        [IO.File]::WriteAllText((Join-Path $repo 'modules/45.Wallpaper.ps1'), "# fond propre : $repo")
    }
    function Reset-TestBaseline {
        $hash = Get-PreparationSharedHash (Join-Path $a 'modules/core.ps1')
        $state = @{ SchemaVersion=1; Files=@{ 'modules/core.ps1'=$hash } } | ConvertTo-Json -Depth 5
        foreach ($repo in @($a, $b)) { [IO.File]::WriteAllText((Join-Path $repo 'sync/state.json'), $state) }
    }
    Reset-TestBaseline
    [IO.File]::WriteAllText((Join-Path $a 'modules/core.ps1'), '# correction')
    $beforeUi = (Get-FileHash (Join-Path $b 'modules/99.UI.ps1')).Hash
    $beforeLogo = (Get-FileHash (Join-Path $b 'assets/logo.png')).Hash
    $beforeWallpaper = (Get-FileHash (Join-Path $b 'modules/45.Wallpaper.ps1')).Hash
    $plan = Get-PreparationSyncPlan $a $b
    Assert-True ($plan.Entries[0].Action -eq 'Copy') 'Detecter une correction source.'
    Assert-True ([IO.File]::ReadAllText((Join-Path $b 'modules/core.ps1')) -eq '# initial') 'Audit sans mutation.'
    Invoke-PreparationSyncPlan $plan
    Assert-True ([IO.File]::ReadAllText((Join-Path $b 'modules/core.ps1')) -eq '# correction') 'Appliquer le coeur technique.'
    Assert-True ((Get-FileHash (Join-Path $b 'modules/99.UI.ps1')).Hash -eq $beforeUi -and (Get-FileHash (Join-Path $b 'assets/logo.png')).Hash -eq $beforeLogo -and (Get-FileHash (Join-Path $b 'modules/45.Wallpaper.ps1')).Hash -eq $beforeWallpaper) 'Conserver les UI/logo/fond personnalises octet pour octet.'
    Assert-True ((Get-PreparationSyncPlan $a $b).Entries[0].Action -eq 'Identical') 'Synchronisation idempotente.'
    [IO.File]::WriteAllText((Join-Path $b 'modules/core.ps1'), '# correction Numeriks')
    Assert-Rejected { Invoke-PreparationSyncPlan (Get-PreparationSyncPlan $a $b) } 'Ne pas ecraser une correction faite dans Numeriks.'
    Invoke-PreparationSyncPlan (Get-PreparationSyncPlan $b $a)
    Assert-True ([IO.File]::ReadAllText((Join-Path $a 'modules/core.ps1')) -eq '# correction Numeriks') 'Synchroniser egalement Numeriks vers LDLC.'
    [IO.File]::WriteAllText((Join-Path $a 'modules/core.ps1'), '# A')
    [IO.File]::WriteAllText((Join-Path $b 'modules/core.ps1'), '# B')
    Assert-Rejected { Invoke-PreparationSyncPlan (Get-PreparationSyncPlan $a $b) } 'Conflit des deux cotes : aucune ecriture.'
    Assert-True ([IO.File]::ReadAllText((Join-Path $b 'modules/core.ps1')) -eq '# B') 'Conserver le conflit cible intact.'
    foreach ($path in @('assets/logo.png','modules/99.UI.ps1','modules/45.Wallpaper.ps1','branding/startup.ps1','dist/LDLCPreparationPC.exe','telemetry.config.json','tools/google-apps-script/LDLC_ErrorTelemetry.gs')) {
        Assert-Rejected { Assert-PreparationSharedPath $path @() } "Protection non contournable : $path"
    }
    foreach ($path in @('../outside.ps1','modules/../../outside.ps1','C:/outside.ps1','modules\core.ps1')) {
        Assert-Rejected { Get-PreparationSyncPath $a $path } 'Refuser une sortie du depot.'
    }
    [IO.File]::WriteAllText((Join-Path $a 'modules/core.ps1'), "# line`r`n# two")
    [IO.File]::WriteAllText((Join-Path $b 'modules/core.ps1'), "# line`n# two")
    Assert-True ((Get-PreparationSharedHash (Join-Path $a 'modules/core.ps1')) -eq (Get-PreparationSharedHash (Join-Path $b 'modules/core.ps1'))) 'Git CRLF/LF ne doit pas creer un faux conflit.'
    Reset-TestBaseline
    $plan = Get-PreparationSyncPlan $a $b
    [IO.File]::WriteAllText((Join-Path $b 'modules/core.ps1'), '# changed during audit')
    Assert-Rejected { Invoke-PreparationSyncPlan $plan } 'Bloquer un fichier modifie apres audit.'
    [IO.File]::WriteAllText((Join-Path $b 'modules/core.ps1'), [IO.File]::ReadAllText((Join-Path $a 'modules/core.ps1')))
    Reset-TestBaseline
    foreach ($repo in @($a, $b)) {
        & git -C $repo add -- modules/core.ps1
        if ($LASTEXITCODE -ne 0) { throw 'Git fixture staging failed.' }
        & git -C $repo -c user.name='Sync Test' -c user.email='sync-test@example.invalid' commit --quiet -m 'Fixture baseline'
        if ($LASTEXITCODE -ne 0) { throw 'Git fixture commit failed.' }
    }
    & git -C $a rm --quiet -- modules/core.ps1
    if ($LASTEXITCODE -ne 0) { throw 'Git fixture deletion failed.' }
    Invoke-PreparationSyncPlan (Get-PreparationSyncPlan $a $b)
    Assert-True (-not (Test-Path (Join-Path $b 'modules/core.ps1'))) 'Propager une suppression technique suivie par Git.'
    Assert-True ((Get-PreparationSyncPlan $a $b).Entries[0].Action -eq 'Identical') 'Une suppression reste idempotente.'
    @{ SchemaVersion=1; SharedFiles=@('modules/core.ps1','modules/new-feature.ps1'); ProtectedPaths=@() } | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $a 'sync/shared-files.json')
    [IO.File]::WriteAllText((Join-Path $a 'modules/new-feature.ps1'), '# new feature')
    Invoke-PreparationSyncPlan (Get-PreparationSyncPlan $a $b)
    Assert-True ([IO.File]::ReadAllText((Join-Path $b 'modules/new-feature.ps1')) -eq '# new feature') 'Ajouter une fonctionnalite declaree sans baseline preexistante.'
    Assert-Rejected { Assert-PreparationSharedPath 'AGENTS.md' @() } 'Instructions propres a chaque edition.'
    Assert-Rejected { Get-PreparationSyncPlan $a (Join-Path $a 'nested') } 'Refuser des depots imbriques.'
    Write-Host 'OK core sync: both directions, independent visuals, conflicts, dry run, path guards, CRLF, concurrent change, tracked deletion, new feature.'
} finally {
    $resolved = [IO.Path]::GetFullPath($fixture)
    if ($resolved.StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'Preparation-Sync-Test-*') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
