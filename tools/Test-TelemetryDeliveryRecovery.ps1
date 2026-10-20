#requires -Version 5.1
param([string]$ModuleRoot=(Join-Path (Split-Path -Parent $PSScriptRoot) 'modules'))
$ErrorActionPreference='Stop'
. (Join-Path $ModuleRoot '05.Telemetry.ps1')
$checks=0;$cases=0
function Assert($Value,$Reason){$script:checks++;if(-not $Value){throw $Reason}}
function Get-LDLCTelemetryEndpointUrl {'https://telemetry-fixture.invalid/exec'}
function Get-LDLCTelemetryApiKey {'synthetic-credential-never-log'}
function Test-LDLCTelemetryConfigured {$true}
function Test-LDLCTelemetryDisabled {$false}
function Write-LDLCLocalLog($Level,$Text){$script:logs+=@($Text)}
function Start-Sleep { }
function New-Payload($Id){return @{Run=@{RunId=$Id;IsFinal=$true;Status='success';FinishedAt='2026-10-20T12:00:00Z';Sequence=1};Events=@()}}
function Reset-Case($Mode){$script:cases++;$script:mode=$Mode;$script:calls=0;$script:logs=@();$script:LDLCTelemetryRemoteRequestCount=0;$script:LDLCTelemetryLastTransportFailure=$null}
function Invoke-RestMethod($Uri,$Method,$ContentType,$Body,$TimeoutSec,$ErrorAction){
    $script:calls++;$script:request=$Body|ConvertFrom-Json;$script:timeout=$TimeoutSec
    if($script:mode -eq 'timeout' -or ($script:mode -eq 'timeout-once' -and $script:calls -eq 1)){throw [Net.WebException]::new('synthetic-credential-never-log',[Net.WebExceptionStatus]::Timeout)}
    if($script:mode -eq 'http503-once' -and $script:calls -eq 1){$exception=[Exception]::new('synthetic-credential-never-log');$exception|Add-Member NoteProperty Response ([pscustomobject]@{StatusCode=503});throw $exception}
    if($script:mode -eq 'busy-once' -and $script:calls -eq 1){return @{ok=$false;error='Lock timeout synthetic-credential-never-log'}}
    if($script:mode -eq 'unauthorized'){return @{ok=$false;error='unauthorized'}}
    if($script:mode -eq 'html'){return '<!doctype html><html>synthetic-credential-never-log</html>'}
    if($script:mode -eq 'wrong-count'){return @{ok=$true;payloads=0}}
    return @{ok=$true;payloads=@($script:request.payloads).Count}
}
$directory=Join-Path ([IO.Path]::GetTempPath()) ('Telemetry-Recovery-'+[guid]::NewGuid().ToString('N'))
$previous=$env:LDLC_TELEMETRY_TIMEOUT_SECONDS
try{
    [void](New-Item -ItemType Directory -Path $directory)
    $payload=New-Payload 'current-fixture'
    foreach($mode in @('ack','timeout-once','http503-once','busy-once')){
        Reset-Case $mode
        Send-LDLCTelemetryPayloads -Payloads @($payload)
        Assert ($calls -eq $(if($mode -eq 'ack'){1}else{2})) 'One retry only for temporary failures.'
        Assert (-not $script:LDLCTelemetryLastTransportFailure) 'Successful retry must clear the failure cause.'
        Assert (($logs -join '') -notmatch 'synthetic-credential-never-log') 'Do not log tokens, server response bodies or raw request exceptions.'
    }
    foreach($mode in @('unauthorized','html','wrong-count','timeout')){
        Reset-Case $mode;$failed=$false
        try{Send-LDLCTelemetryPayloads -Payloads @($payload)}catch{$failed=$true}
        Assert $failed 'Missing or invalid acknowledgement must never be success.'
        Assert ($calls -eq $(if($mode -eq 'timeout'){2}else{1})) 'Permanent errors must not be retried; outages must remain bounded.'
        Assert ($script:LDLCTelemetryLastTransportFailure.Message -and ($logs -join '') -notmatch 'synthetic-credential-never-log') 'Keep a precise sanitized cause.'
    }
    Reset-Case 'ack';$env:LDLC_TELEMETRY_TIMEOUT_SECONDS='45'
    Send-LDLCTelemetryPayloads -Payloads @($payload)
    Assert ($timeout -eq 45) 'A configured timeout above 20 seconds must not be silently capped to 20.'
    $env:LDLC_TELEMETRY_TIMEOUT_SECONDS='999'
    Assert ((Get-LDLCTelemetryNetworkTimeoutSeconds) -eq 60) 'Keep a finite timeout upper bound.'

    Reset-Case 'ack'
    $script:LDLCTelemetryDisabled=$false;$script:LDLCTelemetryQueuePath=Join-Path $directory 'queue.json'
    $old=@(1..23|ForEach-Object{New-Payload ('backlog-'+$_)})
    Assert (Write-LDLCQueuedTelemetryPayloads -Payloads $old) 'Prepare a durable backlog fixture.'
    Assert (SendOrQueue-LDLCTelemetryPayload -Payload $payload) 'The current final report must be acknowledged despite the backlog.'
    Assert (@($request.payloads).Count -eq 10 -and $request.payloads[0].Run.RunId -eq 'current-fixture') 'Prioritize the active run and bound the batch size.'
    $pending=@(Read-LDLCQueuedTelemetryPayloads)
    Assert ($pending.Count -eq 14 -and 'current-fixture' -notin @($pending.Run.RunId)) 'Delete only the ten acknowledged members and preserve all others.'

    Reset-Case 'timeout';$payload=New-Payload 'offline-fixture'
    Assert (-not (SendOrQueue-LDLCTelemetryPayload -Payload $payload)) 'Do not claim delivery after two timeouts.'
    Assert ('offline-fixture' -in @((Read-LDLCQueuedTelemetryPayloads).Run.RunId)) 'Failed current report must remain on disk for the next attempt.'
    Assert ($script:LDLCTelemetryLastTransportFailure.Code -eq 'Timeout') 'Expose the actual timeout cause instead of an undifferentiated network/server error.'
    Reset-Case 'ack'
    Assert (SendOrQueue-LDLCTelemetryPayload -Payload $payload) 'Retry the same durable report after recovery.'
    Assert ('offline-fixture' -notin @((Read-LDLCQueuedTelemetryPayloads).Run.RunId)) 'Clear the report only after acknowledgement.'
    Write-Host ('::notice title=Telemetry delivery recovery::'+(@{Cases=$cases;Assertions=$checks;Failures=0;Mode='simulated HTTP responses and real isolated durable queue';RealDashboardModified=$false}|ConvertTo-Json -Compress))
}finally{
    $env:LDLC_TELEMETRY_TIMEOUT_SECONDS=$previous
    if(Test-Path $directory){Remove-Item $directory -Recurse -Force}
}
