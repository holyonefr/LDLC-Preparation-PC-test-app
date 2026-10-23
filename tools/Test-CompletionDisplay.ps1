#requires -Version 5.1
param([string]$ModuleRoot=(Join-Path (Split-Path -Parent $PSScriptRoot) 'modules'))
$ErrorActionPreference='Stop'
. (Join-Path $ModuleRoot '05.Telemetry.ps1')
. (Join-Path $ModuleRoot '70.DefaultApps.ps1')
$script:Checks=0;$script:Warnings=New-Object 'Collections.Generic.List[string]';$script:Information=New-Object 'Collections.Generic.List[string]'
function Assert($Value,$Reason){$script:Checks++;if(-not $Value){throw $Reason}}
function Write-Warn($Text){$script:Warnings.Add($Text)}
function Write-Info($Text){$script:Information.Add($Text)}
function Write-Ok($Text){}
function Write-Step($Text){}
function Start-Sleep{}
function Stop-IfRequested{}
function Test-LDLCStopRequestError($ErrorRecord){$ErrorRecord.Exception.Message -match 'LDLC_STOP_REQUESTED'}
function Get-LDLCWidgetsTaskbarState {
    if($script:WidgetReadFailure){throw $script:WidgetReadFailure}
    [pscustomobject]@{Disabled=$false;TaskbarDa=1;PolicyDisabled=$false}
}
function Set-LDLCTaskbarAdvancedValue{throw 'Access denied (fixture)'}
function Set-LDLCTaskbarPolicyValue{throw 'Access denied (fixture)'}
function Get-LDLCTaskbarAdvancedValue{0}
function Disable-LDLCTaskbarOption{$false}
$script:WidgetReadFailure=''
$changed=Disable-LDLCWidgetsTaskbarOption
Assert (-not $changed -and $script:Warnings.Count -eq 0) 'Denied Widgets writes must not produce a final warning or a false disabled state.'
Assert ($script:Information.Count -gt 0) 'Keep the actual Widgets diagnostic in the local information stream.'
$script:WidgetReadFailure='Widgets state unreadable (fixture)'
$null=Set-LDLCTaskbarOptionsWithRegistry
Assert ($script:Warnings.Count -eq 0) 'An unreadable cosmetic Widgets setting must not become a blocking taskbar warning.'
if(Get-Command Confirm-LDLCDefaultAppsFinalState -ErrorAction SilentlyContinue){
    $script:LDLCDefaultAppsPendingChecks=@{Widgets=$true};$script:LDLCDefaultAppsFinalAuditDone=$false
    $audit=Confirm-LDLCDefaultAppsFinalState
    Assert ($audit.Confirmed -and $script:Warnings.Count -eq 0) 'The beta final audit reintroduced the removed Widgets warning.'
}
$script:WidgetReadFailure='LDLC_STOP_REQUESTED';$stopped=$false
try{$null=Set-LDLCTaskbarOptionsWithRegistry}catch{$stopped=Test-LDLCStopRequestError $_}
Assert $stopped 'Removing cosmetic warnings must not swallow an actual stop request.'

# Execute the real completion function. These boundary doubles never send a
# synthetic intervention to the permanent dashboard or change Windows settings.
function Test-LDLCTelemetryDisabled{$false}
function Write-LDLCLocalLog{param($Level,$Text);$script:Information.Add($Text)}
function Write-LDLCFinalProgress{param($Percent,$Message);$script:Screen=[pscustomobject]@{Percent=$Percent;Message=$Message}}
function Write-LDLCQueuedTelemetryPayloads{param($Payloads);$script:Written=$Payloads;return $script:QueueWritable}
function Publish-LDLCFinalizationReceipt{param($Payload,$PayloadSaved);$script:ReceiptSaved=$PayloadSaved}
function SendOrQueue-LDLCTelemetryPayload{param($Payload);$script:LDLCTelemetryLastQueueSaved=$script:QueueWritable;return $false}
function New-LDLCTelemetryPayload {
    param($ResultStatus,[switch]$Final)
    [pscustomobject]@{Run=[pscustomobject]@{RunId='DISPLAY-FIXTURE';IsFinal=[bool]$Final;Status=$ResultStatus;BlockingReason=$script:LDLCTelemetryBlockingReason};Events=@()}
}
function Reset-Completion {
    $script:LDLCTelemetryInitialized=$true;$script:LDLCTelemetryDisabled=$false;$script:LDLCTelemetryCompleted=$false
    $script:LDLCTelemetrySendSuccessfulRuns=$true;$script:LDLCTelemetryProgressPercent=100;$script:LDLCTelemetryCurrentStep='FIN DU SCRIPT'
    $script:LDLCTelemetryEvents=New-Object 'Collections.Generic.List[object]';$script:LDLCTelemetryStopwatch=$null
    $script:LDLCTelemetryLastTransportFailure=[pscustomobject]@{Code='Timeout';Message='Delai de transmission au serveur depasse.'}
    $script:LDLCTelemetryLastQueueSaved=$false;$script:QueueWritable=$true;$script:Screen=$null;$script:Written=$null;$script:ReceiptSaved=$false
}
Reset-Completion
Complete-LDLCTelemetryRun -ResultStatus success -WorkflowCompleted $true
Assert ($script:Screen.Message -eq 'Preparation terminee. Rapport enregistre localement.') 'The screen still shows a network error after a completed intervention with a saved report.'
Assert ($script:Screen.Message -notmatch 'reseau|non transmise|validation automatique') 'Do not expose the removed network alert or pretend server validation was acknowledged.'
Assert ($script:Written.Run.Status -eq 'success' -and $script:ReceiptSaved) 'Keep the actual completed result and local receipt.'
Assert (($script:Information -join ' ') -match 'Transmission finale non confirmee') 'Keep precise transport diagnostics in the local journal.'
Reset-Completion
$script:LDLCTelemetryEvents.Add([pscustomobject]@{Severity='error';Status='error';Step='Installation';Message='Installation refusee : code 1603.'})
Complete-LDLCTelemetryRun -ResultStatus failed -WorkflowCompleted $true
Assert ($script:Screen.Message -match 'Validation bloquee.*1603' -and $script:Written.Run.Status -eq 'failed') 'A real installation failure was hidden by the neutral transport display.'
Assert ($script:Screen.Message -match 'Rapport enregistre localement') 'A real error still needs its durable-report confirmation.'
Reset-Completion
Complete-LDLCTelemetryRun -ResultStatus stopped -WorkflowCompleted $false
Assert ($script:Written.Run.Status -eq 'stopped' -and $script:Screen.Percent -lt 100 -and $script:Screen.Message -match 'incomplete|interrompue') 'An incomplete intervention was converted to a successful completion.'
Reset-Completion;$script:QueueWritable=$false
Complete-LDLCTelemetryRun -ResultStatus success -WorkflowCompleted $true
Assert ($script:Screen.Message -match 'sauvegarde locale impossible' -and -not $script:ReceiptSaved) 'A genuine local-save failure was hidden.'
Write-Host ('::notice title=Completion display regression::'+(@{Assertions=$script:Checks;Result='passed';Mode='real completion and Widgets code, simulated Windows writes and HTTP boundary';DashboardModified=$false}|ConvertTo-Json -Compress))
