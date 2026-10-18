$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'modules\00.Core.ps1')
. (Join-Path $root 'modules\05.Telemetry.ps1')
. (Join-Path $root 'modules\80.WindowsUpdate.ps1')
$realSender = ${function:Send-LDLCTelemetryPayloads}

function Assert-True([bool]$Value, [string]$Message) { if (-not $Value) { throw $Message } }
function Get-LDLCComputerTelemetryInfo {
    [pscustomobject]@{ ComputerName = 'TEST-NO-USER'; UserName = ''; UserDomain = ''; SerialNumber = 'TEST'; Manufacturer = ''; Model = ''; OSCaption = ''; OSVersion = ''; TimeZone = '' }
}
function Get-LDLCEntryPointPath { return 'TEST-ONLY.ps1' }
function Get-LDLCRuntimeRoot { return $script:RuntimeRoot }
function Stop-IfRequested {}
function Start-Process { [pscustomobject]@{ Id = 12345 } }
function Send-LDLCTelemetryPayloads {
    param([object[]]$Payloads)
    if ($script:SimulateOffline) { throw 'Simulated offline' }
    foreach ($payload in $Payloads) { [void]$script:Sent.Add(($payload | ConvertTo-Json -Depth 14 | ConvertFrom-Json)) }
}

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('LDLC-Telemetry-Test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$originalDisabled = $env:LDLC_TELEMETRY_DISABLED
$originalRunId = $env:LDLC_TELEMETRY_RUN_ID
$originalMode = $env:LDLC_TELEMETRY_REMOTE_MODE
try {
    Remove-Item Env:\LDLC_TELEMETRY_DISABLED, Env:\LDLC_TELEMETRY_RUN_ID -ErrorAction SilentlyContinue
    $env:LDLC_TELEMETRY_REMOTE_MODE = 'start-final'
    $script:RuntimeRoot = $testRoot
    $script:ProgressFile = Join-Path $testRoot 'progress.txt'
    $script:LDLCEmbeddedWorkerScriptPath = $PSCommandPath
    $script:LDLCTelemetryInitialized = $false
    $script:Sent = New-Object 'System.Collections.Generic.List[object]'
    Initialize-LDLCTelemetry
    $runId = $script:LDLCTelemetryRunId
    Assert-True ($script:Sent.Count -eq 1) 'Un seul demarrage doit etre envoye.'
    $worker = Start-LDLCWindowsUpdateWorker
    Assert-True ($worker.Success -and -not $script:LDLCTelemetryDisabled) 'REGRESSION: le lancement Windows Update desactive la telemetrie du worker principal.'
    Set-LDLCTelemetryStep -Step 'Applications' -ProgressPercent 42
    $intermediate = New-LDLCTelemetryPayload
    Assert-True ($intermediate.Run.ProgressPercent -eq 42) 'La progression nullable PowerShell doit etre conservee.'
    Assert-True (-not $intermediate.Run.IsFinal -and $intermediate.Run.Status -eq 'running') 'Une mise a jour reste en cours.'
    Complete-LDLCTelemetryRun -ResultStatus success
    Complete-LDLCTelemetryRun -ResultStatus failed
    Assert-True ($script:Sent.Count -eq 2) 'La finalisation doit etre envoyee une seule fois apres Windows Update.'
    $final = $script:Sent[1].Run
    Assert-True ($final.RunId -eq $runId -and $script:Sent[0].Run.RunId -eq $runId) 'Le RunId doit rester identique du debut a la fin.'
    Assert-True ($final.Status -eq 'success' -and $final.IsFinal -and $final.FinishedAt) 'La fin reelle doit contenir success, IsFinal et FinishedAt.'
    Assert-True ($final.UserName -eq '') 'Un compte utilisateur vide ne doit pas bloquer la remontee.'

    $script:SimulateOffline = $true
    $script:LDLCTelemetryInitialized = $false
    Initialize-LDLCTelemetry
    $offlineRunId = $script:LDLCTelemetryRunId
    Add-LDLCTelemetryEvent -Message 'PDF non confirme apres tentatives' -Severity warning
    Complete-LDLCTelemetryRun -ResultStatus success
    $queued = @(Read-LDLCQueuedTelemetryPayloads)
    Assert-True ($queued.Count -eq 1 -and $queued[0].Run.RunId -eq $offlineRunId) 'La file hors ligne doit garder une seule version du RunId.'
    Assert-True ($queued[0].Run.Status -eq 'warning' -and $queued[0].Run.IsFinal) 'La file doit conserver la finalisation et son avertissement.'
    $script:SimulateOffline = $false
    $script:LDLCTelemetryInitialized = $false
    Initialize-LDLCTelemetry
    $newRunId = $script:LDLCTelemetryRunId
    Assert-True ($newRunId -ne $offlineRunId) 'Deux preparations du meme PC ont des RunId differents.'
    Assert-True (@(Read-LDLCQueuedTelemetryPayloads).Count -eq 0) 'Un renvoi acquitte doit vider uniquement les payloads envoyes.'
    Complete-LDLCTelemetryRun -ResultStatus stopped
    Assert-True ($script:Sent[$script:Sent.Count - 1].Run.Status -eq 'stopped') 'Un arret explicite ne doit jamais devenir une reussite.'
    $backlog = @(1..150 | ForEach-Object { [pscustomobject]@{ Run = [pscustomobject]@{ RunId = "TEST-BACKLOG-$_"; Status = 'running'; IsFinal = $false; Sequence = 1 }; Events = @() } })
    Assert-True (Write-LDLCQueuedTelemetryPayloads $backlog) 'La file doit etre sauvegardee durablement.'
    Assert-True (@(Read-LDLCQueuedTelemetryPayloads).Count -eq 150) 'Ne pas supprimer les rapports au-dela de 100 executions hors ligne.'
    $done = [pscustomobject]@{ Run = [pscustomobject]@{ RunId = 'TEST-BACKLOG-1'; Status = 'success'; IsFinal = $true; Sequence = 2 }; Events = @() }
    [void](Write-LDLCQueuedTelemetryPayloads @($done, $backlog[0]))
    $first = @(Read-LDLCQueuedTelemetryPayloads | Where-Object { $_.Run.RunId -eq 'TEST-BACKLOG-1' })
    Assert-True ($first.Count -eq 1 -and $first[0].Run.IsFinal) 'Un demarrage retarde ne doit pas ecraser la fin.'
    Clear-LDLCQueuedTelemetryPayloads -AcknowledgedPayloads $backlog
    Assert-True (@(Read-LDLCQueuedTelemetryPayloads).Count -eq 1) 'Un acquittement ancien ne doit pas supprimer une finalisation plus recente.'
    Clear-LDLCQueuedTelemetryPayloads -AcknowledgedPayloads @($done)
    Assert-True (@(Read-LDLCQueuedTelemetryPayloads).Count -eq 0) 'Supprimer le rapport uniquement apres acquittement de sa version exacte.'
    Set-Item Function:\Send-LDLCTelemetryPayloads $realSender
    function Invoke-RestMethod { return [pscustomobject]@{ ok = $false } }
    Assert-True (-not (SendOrQueue-LDLCTelemetryPayload $done)) 'Un HTTP 200 sans ok=true ne doit pas vider la file.'
    Assert-True (@(Read-LDLCQueuedTelemetryPayloads).Count -eq 1) 'Conserver la fin lorsque Apps Script refuse le POST.'
    Write-Host 'OK telemetry lifecycle: Windows Update, stable RunId, progress, empty user, offline replay, warning, stop.'
}
finally {
    foreach ($setting in @(@('LDLC_TELEMETRY_DISABLED', $originalDisabled), @('LDLC_TELEMETRY_RUN_ID', $originalRunId), @('LDLC_TELEMETRY_REMOTE_MODE', $originalMode))) {
        [Environment]::SetEnvironmentVariable($setting[0], $setting[1], 'Process')
    }
    $resolved = [IO.Path]::GetFullPath($testRoot)
    if ($resolved.StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'LDLC-Telemetry-Test-*') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
