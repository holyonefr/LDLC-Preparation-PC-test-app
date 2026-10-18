$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PreparationDashboardRead.Common.ps1')
if(-not ('LDLCDashboardReadTestResponse' -as [type])) {
 Add-Type -TypeDefinition @'
using System.Net;
public sealed class LDLCDashboardReadTestResponse : WebResponse {
 public int StatusCode { get; private set; }
 public LDLCDashboardReadTestResponse(int code) { StatusCode=code; }
}
'@
}
$script:checks=0; $script:cases=0
function Assert([bool]$Value,[string]$Message){$script:checks++;if(-not $Value){throw $Message}}
function Start-Sleep {param($Seconds) $script:waits.Add([int]$Seconds)}
function Invoke-RestMethod {
 param($Uri,$Method,$TimeoutSec,$ErrorAction)
 $script:calls++
 Assert ($Method -eq 'Get') 'Retry helper must perform reads only.'
 Assert ($TimeoutSec -eq 45) 'Request timeout was changed unexpectedly.'
 $item=$script:sequence.Dequeue()
 if($item -is [Exception]) {throw $item}
 return $item
}
function New-Failure([int]$Http,[string]$Status='ProtocolError') {
 $response=if($Http){New-Object LDLCDashboardReadTestResponse $Http}else{$null}
 return [Net.WebException]::new('SECRET_TEST_KEY https://example.invalid/?key=SECRET_TEST_KEY',$null,[Net.WebExceptionStatus]$Status,$response)
}
function Reset-Case([object[]]$Sequence) {
 $script:sequence=New-Object 'Collections.Generic.Queue[object]';foreach($item in $Sequence){$script:sequence.Enqueue($item)}
 $script:diag=New-Object 'Collections.Generic.List[object]';$script:waits=New-Object 'Collections.Generic.List[int]';$script:calls=0;$script:cases++
}
$valid=[pscustomobject]@{ok=$true;runs=@([pscustomobject]@{runId='test';status='stopped';isFinal=$true})}
# Before: the old one-shot Snapshot call immediately fails on a temporary outage.
Reset-Case @((New-Failure 503),$valid)
$failed=$false;try{Invoke-RestMethod -Uri 'https://example.invalid/?key=SECRET_TEST_KEY' -Method Get -TimeoutSec 45 -ErrorAction Stop|Out-Null}catch{$failed=$true}
Assert ($failed -and $script:calls -eq 1) 'Old one-shot failure was not reproduced.'
foreach($code in @(408,429,500,502,503,504)) {
 Reset-Case @((New-Failure $code),$valid)
 $result=Invoke-LDLCDashboardRead -Uri 'https://example.invalid/?key=SECRET_TEST_KEY' -Stage 'stopped_final' -Diagnostics $script:diag
 Assert ($result.runs[0].status -eq 'stopped' -and $script:calls -eq 2) "HTTP $code did not recover with the actual stopped result."
 Assert ($script:diag.Count -eq 2 -and $script:diag[0].HttpStatus -eq $code -and $script:diag[1].Success) "HTTP $code diagnostic missing."
 Assert ($script:waits.Count -eq 1 -and $script:waits[0] -eq 1) 'Bounded backoff missing.'
}
foreach($status in @('Timeout','ConnectFailure','ConnectionClosed','KeepAliveFailure','ReceiveFailure','SendFailure','NameResolutionFailure','ProxyNameResolutionFailure')) {
 Reset-Case @((New-Failure 0 $status),$valid)
 $result=Invoke-LDLCDashboardRead -Uri 'https://example.invalid/' -Stage 'initial' -Diagnostics $script:diag
 Assert ($result.ok -and $script:calls -eq 2 -and $script:diag[0].NetworkStatus -eq $status) "$status not recovered/diagnosed."
}
foreach($code in @(400,401,403,404,409,422)) {
 Reset-Case @((New-Failure $code),$valid)
 $message='';try{Invoke-LDLCDashboardRead -Uri 'https://example.invalid/?key=SECRET_TEST_KEY' -Stage 'preflight' -Diagnostics $script:diag|Out-Null}catch{$message=[string]$_}
 Assert ($script:calls -eq 1 -and $script:waits.Count -eq 0 -and $message -match "HTTP $code") "Permanent HTTP $code was retried/hidden."
 Assert ($message -notmatch 'SECRET_TEST_KEY|example.invalid') 'Credentials/URL leaked in final error.'
}
foreach($status in @('TrustFailure','SecureChannelFailure','RequestCanceled')) {
 Reset-Case @((New-Failure 0 $status),$valid)
 $message='';try{Invoke-LDLCDashboardRead -Uri 'https://example.invalid/' -Stage 'initial' -Diagnostics $script:diag|Out-Null}catch{$message=[string]$_}
 Assert ($script:calls -eq 1 -and $message -match $status) "$status was hidden/retried."
}
Reset-Case @((New-Failure 503),(New-Failure 503),(New-Failure 503),$valid)
$message='';try{Invoke-LDLCDashboardRead -Uri 'https://example.invalid/?key=SECRET_TEST_KEY' -Stage 'stopped_final' -Diagnostics $script:diag|Out-Null}catch{$message=[string]$_}
Assert ($script:calls -eq 3 -and $script:waits.Count -eq 2 -and $script:waits[1] -eq 2 -and $message -match 'tentative 3/3.*HTTP 503') 'Persistent outage did not fail after exactly 3 attempts.'
Assert ($message -notmatch 'SECRET_TEST_KEY|example.invalid') 'Secret leaked on exhaustion.'
Assert (@($script:diag|Where-Object Success).Count -eq 0) 'Persistent outage recorded a false success.'
foreach($bad in @([pscustomobject]@{ok=$false;runs=@()},[pscustomobject]@{ok=$true},'HTML error page')) {
 Reset-Case @($bad,$valid)
 $message='';try{Invoke-LDLCDashboardRead -Uri 'https://example.invalid/' -Stage 'initial' -Diagnostics $script:diag|Out-Null}catch{$message=[string]$_}
 Assert ($script:calls -eq 1 -and $message -match 'Lecture dashboard invalide') 'Invalid contract was retried or accepted.'
}
Reset-Case @([pscustomobject]@{ok=$true;runs=@()})
$result=Invoke-LDLCDashboardRead -Uri 'https://example.invalid/' -Stage 'empty-cleanup' -Diagnostics $script:diag
Assert ($result.ok -and $script:calls -eq 1) 'A valid empty dashboard was rejected.'
$serialized=$script:diag|ConvertTo-Json -Depth 4 -Compress
Assert ($serialized -notmatch 'SECRET_TEST_KEY|example.invalid') 'Diagnostics leak credentials.'
$report=@{Success=$true;Simulated=$true;Cases=$script:cases;Assertions=$script:checks;Scope='Read-only HTTP boundary fixtures; old one-shot failure reproduced; transient retry, permanent refusal and no false validation.'}
Write-Host ('OK dashboard read resilience: '+($report|ConvertTo-Json -Compress))
if($env:GITHUB_ACTIONS -eq 'true'){Write-Host ('::notice title=Dashboard read resilience tests::'+($report|ConvertTo-Json -Compress))}
