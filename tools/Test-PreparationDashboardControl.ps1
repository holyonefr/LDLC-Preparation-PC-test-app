#requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PreparationDashboardRead.Common.ps1')
. (Join-Path $PSScriptRoot 'PreparationDashboardControl.Common.ps1')
$script:checks=0
function Assert($v,$m){$script:checks++;if(-not $v){throw $m}}
function Start-Sleep {param($Seconds)}
function Invoke-RestMethod {
 param($Uri,$Method,$ContentType,$Body,$TimeoutSec)
 $script:calls++
 Assert ($Method -eq 'Post' -and $TimeoutSec -eq 45) 'Keep HTTPS POST contract and bounded timeout'
 if($script:mode -eq 'timeout' -or ($script:mode -eq 'retry' -and $script:calls -eq 1)){throw [Net.WebException]::new('synthetic-secret-do-not-log',[Net.WebExceptionStatus]::Timeout)}
 if($script:mode -eq 'tls'){throw [Net.WebException]::new('synthetic-secret-do-not-log',[Net.WebExceptionStatus]::TrustFailure)}
 if($script:mode -eq 'invalid'){return @{ok=$false;error='synthetic-secret-do-not-log'}}
 return @{ok=$true;deleted=1}
}
foreach($mode in @('success','retry','timeout','tls','invalid')){
 $script:mode=$mode;$script:calls=0;$caught='';$response=$null
 $diag=New-Object 'Collections.Generic.List[object]'
 try{$response=Invoke-LDLCDashboardTestControl -Uri 'https://example.invalid/private' -Body @{action='deleterun';RunId='CODEX-TEST-CORRECTION-0123456789abcdef0123456789abcdef-success';apiKey='synthetic-secret-do-not-log';adminKey='synthetic-secret-do-not-log'} -Diagnostics $diag}catch{$caught=$_.Exception.Message}
 Assert ($script:calls -eq $(switch($mode){'retry'{2};'timeout'{3};default{1}})) ($mode+': wrong retry count')
 Assert (($response -and $response.ok) -eq ($mode -in @('success','retry'))) ($mode+': false acknowledgement')
 Assert ($caught -notmatch 'synthetic-secret|https://|private') 'Sensitive HTTP details must stay out of the failure'
 Assert (($diag.ToArray()|ConvertTo-Json -Depth 6) -notmatch 'synthetic-secret|https://|private') 'Sensitive HTTP details must stay out of diagnostics'
}
foreach($body in @(@{action='deleterun';RunId='CUSTOMER-REPORT'},@{action='validate';RunId='CODEX-TEST'})){
 $script:calls=0;$caught=''
 try{Invoke-LDLCDashboardTestControl -Uri 'https://example.invalid' -Body $body|Out-Null}catch{$caught=$_.Exception.Message}
 Assert ($caught -and $script:calls -eq 0) 'Never retry or delete customer reports/unsupported control actions'
}
Write-Host ('::notice title=Dashboard test control resilience::'+(@{Success=$true;Assertions=$script:checks;RealNetwork=$false;CustomerHistoryModified=$false;Cases=7}|ConvertTo-Json -Compress))
