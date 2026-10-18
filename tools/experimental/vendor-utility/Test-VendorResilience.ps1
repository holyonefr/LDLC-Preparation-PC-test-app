#requires -Version 5.1
param([string]$OutputDirectory='artifacts/vendor-resilience')
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot '../motherboard/MotherboardExperiment.psm1') -Force
$module=Get-Module MotherboardExperiment
$cases=New-Object 'Collections.Generic.List[object]';$script:Assertions=0
function Assert($v,$m){$script:Assertions++;if(-not $v){throw $m}}
function Case($n,[scriptblock]$b){try{&$b;$cases.Add(@{Name=$n;Result='passed'})}catch{$cases.Add(@{Name=$n;Result='failed';Error=$_.Exception.Message});Write-Warning ($n+': '+$_.Exception.Message)}}
&$module {
 function script:Invoke-MbxHttpAttempt {
  param($Url,$Hosts,$TimeoutSeconds,$MaxBytes,$OutFile,$Head,$UserAgent)
  $script:RetryFixture.Calls++;$script:RetryFixture.Timeouts+=,$TimeoutSeconds
  if($script:RetryFixture.Failures.Count -ge $script:RetryFixture.Calls){
   $message=$script:RetryFixture.Failures[$script:RetryFixture.Calls-1]
   if($message -eq 'network'){$e=New-Object IO.IOException('Fixture connection reset');$e.Data['MbxNetworkFailure']=$true;throw $e}
   if($message -eq 'tls'){$e=New-Object Security.Authentication.AuthenticationException('Fixture certificate invalid');$e.Data['MbxNetworkFailure']=$true;throw $e}
   throw $message
  }
  return [pscustomobject]@{Url=$Url;Text='current official response';Bytes=1024}
 }
 function script:Wait-MbxHttpRetry {param($Seconds)$script:RetryFixture.Delays+=,$Seconds}
}
function Reset($Failures){&$module {param($f)$script:RetryFixture=[pscustomobject]@{Failures=@($f);Calls=0;Delays=@();Timeouts=@()}} $Failures}
function State {&$module {$script:RetryFixture}}
function Fetch {&$module {Invoke-MbxHttp -Url 'https://example.invalid/current' -Hosts @('example.invalid') -TimeoutSeconds 30}}
try{
 Case 'Immediate success performs no retry'{Reset @();$r=Fetch;Assert ($r.Attempts -eq 1 -and (State).Calls -eq 1 -and (State).Delays.Count -eq 0) 'Requete dupliquee.'}
 foreach($code in @(408,429,500,502,503,504)){
  Case ('Temporary HTTP '+$code+' then recovery') {Reset @('HTTP '+$code+' sur la source officielle.');$r=Fetch;Assert ($r.Attempts -eq 2 -and (State).Calls -eq 2) 'Panne temporaire non reprise.';Assert ((State).Delays[0] -eq 1) 'Reessai sans attente.'}
 }
 Case 'Interrupted network stream is retried'{Reset @('network');$r=Fetch;Assert ($r.Attempts -eq 2) 'Coupure non reprise.'}
 Case 'Incomplete byte count is retried from a fresh request'{Reset @('Telechargement interrompu : 10 octets recus, 100 attendus.');$r=Fetch;Assert ($r.Attempts -eq 2) 'Fichier partiel accepte ou pas de reprise.'}
 Case 'Two temporary failures then recovery use three attempts'{Reset @('HTTP 503 sur la source officielle.','network');$r=Fetch;Assert ($r.Attempts -eq 3 -and ((State).Delays -join ',') -eq '1,2') 'Reprises non bornees.'}
 Case 'Persistent temporary failure stops after three attempts'{Reset @('HTTP 503 sur la source officielle.','HTTP 503 sur la source officielle.','HTTP 503 sur la source officielle.');$m='';try{$null=Fetch}catch{$m=$_.Exception.Message};Assert ($m -match '503' -and (State).Calls -eq 3) 'Erreur persistante masquee ou boucle infinie.'}
 foreach($failure in @('HTTP 403 sur la source officielle.','HTTP 404 sur la source officielle.','Destination HTTPS officielle refusee.','Signature numerique non valide.','Taille maximale de lecture depassee.','Fixture disk full','tls')){
  Case ('Permanent error is not hidden by retries: '+$failure){Reset @($failure);$m='';try{$null=Fetch}catch{$m=$_.Exception.Message};Assert ($m -and (State).Calls -eq 1 -and (State).Delays.Count -eq 0) 'Erreur permanente ignoree.'}
 }
 Case 'Attempt deadlines never increase the original time budget'{Reset @('network','network');$null=Fetch;Assert (@((State).Timeouts|Where-Object {$_ -gt 30 -or $_ -lt 1}).Count -eq 0) 'Delai augmente a chaque reprise.'}
}finally{Remove-Module MotherboardExperiment}
# Exercise the real MSI package function with changing signed file versions;
# bytes/signatures/network are doubles, not a real installation.
Import-Module (Join-Path $PSScriptRoot 'VendorUtility.psm1') -Force
$v=Get-Module VendorUtility
$temp=Join-Path ([IO.Path]::GetTempPath()) ('Vendor-Future-'+[guid]::NewGuid().ToString('N'))
&$v {
 function script:Invoke-MbxUtilityAudit {
  param($Tool,$DownloadUrl,$OutputDirectory)
  $d=Join-Path $OutputDirectory 'owned';[void](New-Item -ItemType Directory -Path $d -Force)
  $p=Join-Path $d 'payload-0.exe';[IO.File]::WriteAllText($p,'inert future installer')
  return [pscustomobject]@{Payloads=@([pscustomobject]@{SHA256=(Get-FileHash $p).Hash})}
 }
 function script:Test-MbxSignedPayload {param($Path,$Signers)return [pscustomobject]@{SHA256=(Get-FileHash $Path).Hash;FileVersion=$script:FutureVersion}}
}
try{
 foreach($version in @('2.0.75.0','3.10.0.1')){
  Case ('Future MSI installer version '+$version+' is discovered without a release pin'){
   &$v {param($x)$script:FutureVersion=$x} $version
   $r=&$v {param($d)Get-VutPackage -Profile (Get-VutProfile MSI) -Directory $d} (Join-Path $temp $version)
   Assert ($r.Version -ceq $version) 'Ancienne version MSI imposee.'
  }
 }
}finally{Remove-Module VendorUtility,MotherboardExperiment -ErrorAction SilentlyContinue;if(Test-Path $temp){Remove-Item $temp -Recurse -Force}}
[void](New-Item -ItemType Directory -Path $OutputDirectory -Force)
$report=@{Kind='vendor_resilience_tests';Cases=@($cases.ToArray());Assertions=$script:Assertions;Failures=@($cases.ToArray()|Where-Object Result -eq failed).Count;Mode='simulated_http_failures_and_future_msi_versions';ActualNetworkRequests=0;VendorInstallerExecuted=$false}
$report|ConvertTo-Json -Depth 6|Set-Content (Join-Path $OutputDirectory 'vendor-resilience.json') -Encoding UTF8
Import-Module (Join-Path $PSScriptRoot '../motherboard/MotherboardExperiment.psm1') -Force
Write-MbxEvidence -Kind 'vendor_resilience_tests' -Data $report
if($report.Failures){throw "$($report.Failures) scenarios de resilience en echec."}
Write-Host "$($cases.Count) scenarios / $script:Assertions assertions reussis."
