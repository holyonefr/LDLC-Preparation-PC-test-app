$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'modules\00.Core.ps1')
. (Join-Path $root 'modules\05.Telemetry.ps1')

function Assert-LDLCCondition {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

$cleanCounts = [pscustomobject]@{ ErrorCount = 0; CriticalCount = 0; WarningCount = 0 }
$warningCounts = [pscustomobject]@{ ErrorCount = 0; CriticalCount = 0; WarningCount = 1 }
$errorCounts = [pscustomobject]@{ ErrorCount = 1; CriticalCount = 0; WarningCount = 0 }

Assert-LDLCCondition (('success' -eq (Convert-LDLCTelemetryRunStatus -Status 'success' -Counts $cleanCounts -Final))) 'Une execution saine doit etre envoyee avec le statut success.'
Assert-LDLCCondition (('warning' -eq (Convert-LDLCTelemetryRunStatus -Status 'success' -Counts $warningCounts -Final))) 'Un avertissement reel doit produire le statut warning.'
Assert-LDLCCondition (('failed' -eq (Convert-LDLCTelemetryRunStatus -Status 'success' -Counts $errorCounts -Final))) 'Une erreur reelle doit produire le statut failed.'
Assert-LDLCCondition (('running' -eq (Convert-LDLCTelemetryRunStatus -Status 'En cours' -Counts $cleanCounts))) 'Une execution en cours doit rester running.'
Assert-LDLCCondition (('timeout' -eq (Convert-LDLCTelemetryRunStatus -Status 'Bloque ou delai depasse' -Counts $cleanCounts -Final))) 'Un timeout explicite doit rester distinct.'
$successLabel = 'R' + [char]0x00E9 + 'ussi'
$warningLabel = $successLabel + ' avec avertissement'
$failureLabel = [char]0x00C9 + 'chec'
$missingAppCategory = 'Application non install' + [char]0x00E9 + 'e ou non d' + [char]0x00E9 + 'tect' + [char]0x00E9 + 'e'
Assert-LDLCCondition (($successLabel -eq (Convert-LDLCTelemetryRunStatusDisplayText -Status 'success'))) 'Le libelle success doit etre Reussi.'
Assert-LDLCCondition (($warningLabel -eq (Convert-LDLCTelemetryRunStatusDisplayText -Status 'warning'))) 'Le libelle warning doit etre explicite et non bloquant.'
Assert-LDLCCondition (($failureLabel -eq (Convert-LDLCTelemetryRunStatusDisplayText -Status 'failed'))) 'Le libelle failed doit etre Echec.'
Assert-LDLCCondition ((Get-LDLCErrorType -Severity error -Message 'AMD Software Adrenalin non confirmee apres installation officielle.') -eq $missingAppCategory) 'Une application absente doit etre classee distinctement.'

$script:LDLCTelemetryDisabled = $false
$script:LDLCTelemetryInitialized = $true
$script:LDLCTelemetrySending = $false
$script:LDLCTelemetryEvents = New-Object System.Collections.Generic.List[object]
$script:LDLCTelemetryEventKeys = @{}
$script:LDLCTelemetryRunId = 'TEST-WARNING-STATUS'
$script:LDLCTelemetrySource = 'LDLC PREPTOOL'
$script:LDLCTelemetryApplicationSource = 'LDLC_PREPARATION_PC'
$script:LDLCTelemetryToolVersion = '2.5.2'
$script:LDLCTelemetryCurrentStep = 'TEST'
$script:LDLCTelemetryComputerInfo = [pscustomobject]@{ ComputerName = 'TEST-PC'; UserName = 'test'; UserDomain = 'TEST'; SerialNumber = ''; Manufacturer = ''; Model = ''; OSCaption = ''; OSVersion = ''; TimeZone = 'Europe/Paris' }
function Update-LDLCTelemetryRun { param([string]$Message, [switch]$Force) }
function Get-LDLCEntryPointPath { return 'C:\LDLC_PREPTOOL\LDLCPreparationPC.ps1' }

Add-LDLCTelemetryEvent -Severity warning -Message 'Verification de la derniere version NVIDIA indisponible : reseau temporairement inaccessible.'
$capturedWarningCounts = Get-LDLCTelemetryCounts
Assert-LDLCCondition ($capturedWarningCounts.WarningCount -eq 1 -and $capturedWarningCounts.ErrorCount -eq 0) 'Un avertissement reel doit etre conserve dans le statut sans devenir une erreur.'
Assert-LDLCCondition (-not [bool]$script:LDLCTelemetryEvents[0].Reportable) 'Un avertissement ne doit pas etre transmis a la feuille des erreurs.'

$workerSource = Get-Content -LiteralPath (Join-Path $root 'modules\95.WorkerLauncher.ps1') -Raw -Encoding UTF8
foreach ($workerName in @('SecurityIsolationSmokeTest', 'SecurityCleanupWorker', 'WorkerSmokeTest', 'WindowsUpdateWorker')) {
    $pattern = 'if\s*\(\$' + [regex]::Escape($workerName) + '\)\s*\{[\s\S]{0,500}?\$env:LDLC_TELEMETRY_DISABLED\s*=\s*''1'''
    Assert-LDLCCondition ($workerSource -match $pattern) "Le worker $workerName doit desactiver sa telemetrie autonome."
}

Write-Host 'OK telemetry statuses and worker isolation'
