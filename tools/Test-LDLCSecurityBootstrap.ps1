$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$bootstrap = Get-Content -LiteralPath (Join-Path $root 'modules\00.Bootstrap.ps1') -Raw -Encoding UTF8
$core = Get-Content -LiteralPath (Join-Path $root 'modules\00.Core.ps1') -Raw -Encoding UTF8
$launcher = Get-Content -LiteralPath (Join-Path $root 'modules\95.WorkerLauncher.ps1') -Raw -Encoding UTF8
$ui = Get-Content -LiteralPath (Join-Path $root 'modules\99.UI.ps1') -Raw -Encoding UTF8
$build = Get-Content -LiteralPath (Join-Path $root 'tools\Build-LDLCPreparationPCExe.ps1') -Raw -Encoding UTF8

foreach ($needle in @(
    'Get-LDLCBootstrapSecurityProducts',
    'Test-LDLCFileReadable',
    'Install-LDLCEmbeddedUiAssets',
    'Install-LDLCEmbeddedWorkerScript',
    'LDLCEmbeddedWorkerPayload',
    "GetFileName(`$PSCommandPath) -eq 'LDLCPreparationPC.worker.ps1'",
    'Test-LDLCFileHash',
    'Show-LDLCBootstrapFailure',
    'LDLC_BOOTSTRAP_TEST.json',
    'LDLC_BOOTSTRAP.log',
    'Unblock-File -LiteralPath $stagedPath',
    "'.write-test-' + [guid]::NewGuid().ToString('N')"
)) {
    if ($bootstrap -notmatch [regex]::Escape($needle)) {
        throw "Garantie bootstrap manquante : $needle"
    }
}

if ($bootstrap -match "Join-Path \`$env:TEMP 'LDLCPreparationPC'" -or
    $bootstrap -match 'GetTempPath\(\).*LDLCPreparationPC' -or
    $core -match "Join-Path \`$env:TEMP 'LDLCPreparationPC'" -or
    $core -match 'GetTempPath\(\).*LDLCPreparationPC') {
    throw 'Le runtime applicatif ne doit jamais utiliser Temp.'
}

if ($bootstrap -match 'Initialize-LDLCTrustedExecutableLaunch|LDLCPreparationPC\.new\.exe|TrustedLaunch') {
    throw 'Le bootstrap ne doit plus relancer automatiquement l executable principal.'
}
if ($launcher -notmatch 'LDLCEmbeddedWorkerScriptPath' -or
    $launcher -notmatch 'ExecutionPolicy' -or
    $launcher -notmatch 'powershell\.exe' -or
    $launcher -notmatch 'SecurityCleanupWorker' -or
    $launcher -notmatch 'SecurityIsolationSmokeTest' -or
    $launcher -notmatch 'LDLC_SECURITY_TEST_DELAY_SECONDS' -or
    $launcher -notmatch 'SecurityIsolationTimeoutSeconds' -or
    $launcher -notmatch 'WorkerSmokeTest' -or
    $launcher -notmatch 'LDLC_WORKER_SMOKE_TEST' -or
    $launcher -notmatch 'bloque, mis en quarantaine ou illisible') {
    throw 'Le worker stable ProgramData et ses modes isoles doivent etre presents.'
}
if ($ui -notmatch 'Demarrage bloque.*LDLC_BOOTSTRAP\.log') {
    throw 'L interface doit afficher un message exploitable si le worker est bloque.'
}
if ($bootstrap -match '(?i)validator|LDLC_Valid_' -or $build -match '(?i)validator|LDLC_Valid_') {
    throw 'Le bootstrap et le build ne doivent plus dependre de LDLC Validator.'
}
if ($build -match '(?i)Invoke-ps2exe|\bps2exe\b|-NoConsole|ManagedResourceRewriter') {
    throw 'Le build Norton-safe ne doit plus utiliser PS2EXE ni injecter de binaire supplementaire.'
}
foreach ($needle in @(
    'LDLCPreparationPC.Launcher\Program.cs',
    'System.Management.Automation',
    '/target:winexe',
    'SHA256SUMS.txt',
    'RequireSignature'
)) {
    if ($build -notmatch [regex]::Escape($needle)) {
        throw "Garantie du lanceur propre manquante : $needle"
    }
}

Write-Host 'OK stable worker bootstrap and Norton diagnostics'
