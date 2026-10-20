$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$workflowPath = Join-Path $root 'modules\90.Workflow.ps1'
$windowsUpdatePath = Join-Path $root 'modules\80.WindowsUpdate.ps1'
$workflow = Get-Content -LiteralPath $workflowPath -Raw -Encoding UTF8
$windowsUpdate = Get-Content -LiteralPath $windowsUpdatePath -Raw -Encoding UTF8

$securityIndex = $workflow.IndexOf('Invoke-LDLCSecurityCleanupIsolated -StartPercent 1 -EndPercent 2 -TimeoutSeconds 90 -SecurityVendor McAfee')
$nortonIndex = $workflow.IndexOf('Remove-LDLCSecurityTrialsInteractively -StartPercent 2 -EndPercent 3')
$restoreIndex = $workflow.IndexOf('Invoke-LDLCRestorePointCreation -ProgressPercent 4')
$windowsUpdateIndex = $workflow.IndexOf('Start-LDLCWindowsUpdatesDuringPreparation -StartPercent 5 -EndPercent 7')
$initialSetupIndex = $workflow.IndexOf('Invoke-LDLCInitialSetup')
$applicationsIndex = $workflow.IndexOf('Install-LDLCApplication -App $app')
$oemIndex = $workflow.IndexOf('Remove-LDLCOemAndSecurityTrials -Mode Oem')
$powerRestoreIndex = $workflow.IndexOf('Restore-PowerSettings -ProgressPercent 97')

if (-not ($securityIndex -ge 0 -and $nortonIndex -ge 0 -and $securityIndex -lt $nortonIndex -and $nortonIndex -lt $restoreIndex -and
    $restoreIndex -lt $windowsUpdateIndex -and $windowsUpdateIndex -lt $initialSetupIndex -and
    $initialSetupIndex -lt $applicationsIndex -and $applicationsIndex -lt $oemIndex -and
    $oemIndex -lt $powerRestoreIndex)) {
    throw 'Ordre du workflow incorrect.'
}

foreach ($needle in @(
    'function Invoke-LDLCSecurityCleanupIsolated',
    '-SecurityCleanupWorker',
    'LDLC_SECURITY_CLEANUP_RESULT.json',
    'Sous-processus arrete, preparation continue',
    'Resultat absent'
)) {
    if ($workflow -notmatch [regex]::Escape($needle)) {
        throw "Isolation McAfee/Norton incomplete : $needle"
    }
}

foreach ($needle in @(
    'function Start-LDLCWindowsUpdateRequiredServices',
    'function Invoke-LDLCWuaUcltAction',
    'function Invoke-LDLCWindowsUpdateScheduledTask',
    'ServicesRunning',
    'StartedActions'
)) {
    if ($windowsUpdate -notmatch [regex]::Escape($needle)) {
        throw "Declenchement Windows Update incomplet : $needle"
    }
}

$ast = [Management.Automation.Language.Parser]::ParseFile($workflowPath, [ref]$null, [ref]$null)
$main = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-LDLCPreparation' }, $true)
if ($main.Extent.Text -match 'Wait-LDLCWindowsUpdateWorkerCompletion|Start-LDLCWindowsUpdateWorker|RemainingCount|TimedOut|wuResult') {
    throw 'La preparation ne doit plus attendre ni surveiller la fin des mises a jour.'
}

if ((Get-Content -LiteralPath (Join-Path $root 'modules\95.WorkerLauncher.ps1') -Raw) -notmatch 'LDLC_TELEMETRY_DISABLED' -or
    $windowsUpdate -match '\$env:LDLC_TELEMETRY_DISABLED\s*=') {
    throw 'Seul le sous-processus Windows Update doit desactiver sa telemetrie.'
}

. (Join-Path $root 'modules\00.Core.ps1')
. (Join-Path $root 'modules\50.Cleanup.ps1')

function Get-LDLCInstalledPrograms {
    param([switch]$Refresh)
    [void]$Refresh
    return @(
        [pscustomobject]@{ DisplayName='McAfee LiveSafe'; DisplayVersion='16.0'; Publisher='McAfee, LLC'; PSChildName='McAfee'; UninstallString=''; QuietUninstallString='' },
        [pscustomobject]@{ DisplayName='Norton 360'; DisplayVersion='24.1'; Publisher='Gen Digital Inc.'; PSChildName='Norton'; UninstallString=''; QuietUninstallString='' },
        [pscustomobject]@{ DisplayName='WildTangent Games'; DisplayVersion='1.0'; Publisher='WildTangent'; PSChildName='WildTangent'; UninstallString=''; QuietUninstallString='' },
        [pscustomobject]@{ DisplayName='Application normale'; DisplayVersion='1.0'; Publisher='Editeur'; PSChildName='Normal'; UninstallString=''; QuietUninstallString='' }
    )
}

$securityTargets = @(Get-LDLCOemRemovalTargets -Mode Security)
$oemTargets = @(Get-LDLCOemRemovalTargets -Mode Oem)
if ($securityTargets.Count -ne 2 -or @($securityTargets.Profile.Group | Sort-Object) -join ',' -ne 'McAfee,Norton') {
    throw "Filtrage Security incorrect : $($securityTargets.Profile.Group -join ',')"
}
if ($oemTargets.Count -ne 1 -or $oemTargets[0].Profile.Group -ne 'WildTangent') {
    throw "Filtrage Oem incorrect : $($oemTargets.Profile.Group -join ',')"
}

Write-Host 'OK workflow order and Security/Oem filtering'
