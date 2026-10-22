$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'PreparationDelivery.Common.ps1')
$powershell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('LDLC-Release-Test-' + [guid]::NewGuid().ToString('N'))
$saved = @{}
foreach ($name in @('ProgramData', 'LOCALAPPDATA', 'LDLC_TELEMETRY_DISABLED')) { $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    $env:ProgramData = $testRoot
    $env:LOCALAPPDATA = $testRoot
    $env:LDLC_TELEMETRY_DISABLED = '1'
    $tests = @(
        'Test-LDLCSyntax', 'Test-LDLCTelemetryStatus', 'Test-LDLCTelemetryLifecycle', 'Test-TelemetryDeliveryRecovery', 'Test-PreparationCompletion', 'Test-PreparationStartupStop', 'Test-PreparationOutboxConcurrency', 'Test-PreparationDashboardRead', 'Test-PreparationDashboardControl',
        'Test-LDLCDefaultApps', 'Test-DefaultAppsUiWarning', 'Test-ChromeBrowserDefaultButton', 'Test-ChromeQuickConfirmation', 'Test-DefaultAppsNativeAssociation', 'Test-LDLCChromeTaskbarPin', 'Test-LDLCCompactUi', 'Test-LDLCGpuAmdFlow', 'Test-LDLCGpuLaptopBypass',
        'Test-LDLCAmdChocolateyFallback', 'Test-LDLCAmdPackageMetadata', 'Test-LDLCAmdUpdateRegression', 'Test-LDLCGpuAmdDetection', 'Test-LDLCAmdSoftwareDetection', 'Test-LDLCGpuInstallValidation', 'Test-NvidiaFallbackResult',
        'Test-LDLCNoValidatorDependencies', 'Test-LDLCHardening', 'Test-LDLCTaskbarPins', 'Test-LDLCWorkflowOrder',
        'Test-WindowsUpdateTrigger', 'Test-LDLCSecurityBootstrap', 'Test-SecurityInteractiveUninstall', 'Test-McAfeeHistoricalRollback', 'Test-LDLCEmbeddedAssets',
        'Test-LDLCErrorReportFixes', 'Test-LDLCInstallRobustness', 'Test-LDLCOfficialInstallerFlow',
        'Test-LDLCUIBranding', 'Test-ProgressTextRendering', 'Test-LDLCLauncherPackaging', 'Test-PreparationCoreSync', 'Test-PreparationDelivery', 'Test-PreparationTelemetryEdition',
        'Test-PreparationStartup', 'Test-BootstrapFirstPaint', 'Test-UiFirstPaint', 'Test-UiLazyInterop', 'Test-UiPixelBuffer'
    )
    foreach ($test in $tests) {
        $env:LDLC_TELEMETRY_DISABLED = if ($test -eq 'Test-LDLCTelemetryStatus') { '0' } else { '1' }
        & $powershell -STA -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot ($test + '.ps1'))
        if ($LASTEXITCODE -ne 0) { Write-Host ("::error title=Release test failure::$test, exit code $LASTEXITCODE"); throw "Test en echec : $test" }
    }
    foreach ($test in @('Test-LDLCDashboardCompatibility.cjs', 'Test-LDLCTelemetryIngestion.cjs', 'Test-PreparationCompletion.cjs')) {
        & node (Join-Path $PSScriptRoot $test)
        if ($LASTEXITCODE -ne 0) { Write-Host ("::error title=Release test failure::$test, exit code $LASTEXITCODE"); throw "Test en echec : $test" }
    }
    # Execute the compiled launcher's real entry point in this isolated process.
    # Reflection avoids an elevation prompt for diagnostic-only modes.
    $env:LDLC_TELEMETRY_DISABLED = '1'
    $assembly = [Reflection.Assembly]::LoadFile((Get-PreparationDelivery $root).ExecutablePath)
    foreach ($mode in @('BootstrapTest', 'SelfTest', 'WorkerSmokeTest')) {
        $code = $assembly.EntryPoint.Invoke($null, [object[]]@(,[string[]]@('-' + $mode)))
        if ($code -ne 0) { throw "Lanceur compile en echec : $mode ($code)" }
    }
    $runtime = Join-Path $testRoot 'LDLCPreparationPC'
    $bootstrap = Get-Content -LiteralPath (Join-Path $runtime 'LDLC_BOOTSTRAP_TEST.json') -Raw | ConvertFrom-Json
    $smoke = Get-Content -LiteralPath (Join-Path $runtime 'LDLC_WORKER_SMOKE_RESULT.json') -Raw | ConvertFrom-Json
    if (-not $bootstrap.WorkerReady -or -not $smoke.Success -or -not (Test-Path (Join-Path $runtime 'LDLCPreparationPC.selftest'))) {
        throw 'Diagnostic du lanceur compile non confirme.'
    }
    Write-Host "OK release: $($tests.Count) PowerShell tests, 3 JS suites, compiled launcher bootstrap/selftest/worker; isolated runtime."
} finally {
    foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process') }
    $resolved = [IO.Path]::GetFullPath($testRoot)
    if ($resolved.StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'LDLC-Release-Test-*') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
