param([string]$ModuleRoot='', [ValidateSet('Parent','A','B')][string]$Role='Parent', [string]$QueueRoot='')
$ErrorActionPreference='Stop'
if(-not $ModuleRoot){$ModuleRoot=Join-Path (Split-Path -Parent $PSScriptRoot) 'modules'}
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $ModuleRoot '05.Telemetry.ps1'),[ref]$null,[ref]$null)
foreach($name in @('Read-LDLCQueuedTelemetryPayloads','Get-LDLCTelemetryOutboxDirectory','Get-LDLCTelemetryOutboxPath','Get-LDLCTelemetryPayloadRunId','Test-LDLCTelemetryPayloadFinal','Merge-LDLCQueuedTelemetryPayloads','Invoke-LDLCTelemetryOutboxLock','Write-LDLCQueuedTelemetryPayloads','Clear-LDLCQueuedTelemetryPayloads')){
 $fn=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
 if(-not $fn){throw 'Missing outbox function'}
 . ([scriptblock]::Create($fn.Extent.Text))
}
function Write-LDLCLocalLog {param($Level,$Text) Write-Host ($Level + ': ' + $Text)}
if($Role -ne 'Parent'){
 $script:LDLCTelemetryQueuePath=Join-Path $QueueRoot 'legacy.json'
 $script:RealMerge=${function:Merge-LDLCQueuedTelemetryPayloads};$script:MergeCalls=0
 function Merge-LDLCQueuedTelemetryPayloads {
  param([object[]]$Payloads)
  $script:MergeCalls++;$result=@(& $script:RealMerge -Payloads $Payloads)
  if($Role -eq 'A' -and $script:MergeCalls -eq 2){
   [IO.File]::WriteAllText((Join-Path $QueueRoot 'A-read'),'ready');$deadline=[datetime]::UtcNow.AddSeconds(15)
   while(-not [IO.File]::Exists((Join-Path $QueueRoot 'continue'))){if([datetime]::UtcNow -gt $deadline){throw 'Barrier timeout'};Start-Sleep -Milliseconds 20}
  }
  return $result
 }
 if($Role -eq 'B'){[IO.File]::WriteAllText((Join-Path $QueueRoot 'B-attempt'),'ready')}
 $payload=[pscustomobject]@{Run=[pscustomobject]@{RunId='CONCURRENT-TEST';IsFinal=($Role -eq 'B');Status=$(if($Role -eq 'B'){'success'}else{'running'});Sequence=$(if($Role -eq 'B'){3}else{2})};Events=@()}
 if(-not (Write-LDLCQueuedTelemetryPayloads -Payloads @($payload))){throw 'Save failed'}
 exit 0
}
function Wait-File($Path){$until=[datetime]::UtcNow.AddSeconds(15);while(-not [IO.File]::Exists($Path)){if([datetime]::UtcNow -gt $until){throw 'Child barrier unavailable'};Start-Sleep -Milliseconds 20}}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('Preparation-Outbox-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp -Force|Out-Null
$script:LDLCTelemetryQueuePath=Join-Path $temp 'legacy.json';$a=$null;$b=$null
try{
 $old=[pscustomobject]@{Run=[pscustomobject]@{RunId='CONCURRENT-TEST';IsFinal=$false;Status='running';Sequence=1};Events=@()}
 if(-not (Write-LDLCQueuedTelemetryPayloads -Payloads @($old))){throw 'Seed save failed'}
 $exe=[Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
 $common=@('-NoProfile','-File',('"{0}"' -f $PSCommandPath),'-ModuleRoot',('"{0}"' -f $ModuleRoot),'-QueueRoot',('"{0}"' -f $temp),'-Role')
 $a=Start-Process -FilePath $exe -ArgumentList ($common+@('A')) -PassThru -RedirectStandardOutput (Join-Path $temp 'A.out') -RedirectStandardError (Join-Path $temp 'A.err')
 # Windows PowerShell 5.1 needs a retained process handle to report ExitCode after WaitForExit.
 $a.Handle | Out-Null
 Wait-File (Join-Path $temp 'A-read')
 $b=Start-Process -FilePath $exe -ArgumentList ($common+@('B')) -PassThru -RedirectStandardOutput (Join-Path $temp 'B.out') -RedirectStandardError (Join-Path $temp 'B.err')
 $b.Handle | Out-Null
 Wait-File (Join-Path $temp 'B-attempt');Start-Sleep -Milliseconds 200
 if($b.HasExited){throw 'Concurrent writer bypassed lock'}
 [IO.File]::WriteAllText((Join-Path $temp 'continue'),'go')
 if(-not $a.WaitForExit(15000) -or -not $b.WaitForExit(15000) -or $a.ExitCode -ne 0 -or $b.ExitCode -ne 0){
  foreach($roleName in @('A','B')) { foreach($suffix in @('out','err')) {
   $log=Join-Path $temp ($roleName+'.'+$suffix)
   if(Test-Path -LiteralPath $log){Get-Content -LiteralPath $log -Tail 8 | ForEach-Object {Write-Host ($roleName+'.'+$suffix+': '+$_)}}
  }}
  throw ('Concurrent child failure: A='+$a.ExitCode+', B='+$b.ExitCode)
 }
 $pending=@(Read-LDLCQueuedTelemetryPayloads)
 if($pending.Count -ne 1 -or -not $pending[0].Run.IsFinal -or $pending[0].Run.Sequence -ne 3){throw 'Final payload overwritten'}
 Clear-LDLCQueuedTelemetryPayloads -AcknowledgedPayloads @($old)
 if(@(Read-LDLCQueuedTelemetryPayloads).Count -ne 1){throw 'Old acknowledgement erased newer final'}
 $final=$pending[0]
 try{Invoke-LDLCTelemetryOutboxLock -Path (Get-LDLCTelemetryOutboxPath $final) -Action {throw 'fixture'}|Out-Null}catch{}
 if(-not (Write-LDLCQueuedTelemetryPayloads -Payloads @($final))){throw 'Lock not released after failure'}
 Clear-LDLCQueuedTelemetryPayloads -AcknowledgedPayloads @($final)
 if(@(Read-LDLCQueuedTelemetryPayloads).Count -ne 0){throw 'Acknowledged final not cleared'}
 Write-Host 'OK concurrent outbox: real two-process lock, final preserved, old ACK rejected, failure releases lock, exact ACK cleared; no network.'
}finally{
 [IO.File]::WriteAllText((Join-Path $temp 'continue'),'go')
 foreach($p in @($a,$b)){if($p -and -not $p.HasExited){try{$p.Kill()}catch{}}}
 if(Test-Path $temp){Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
}
