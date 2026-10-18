param([string]$ModuleRoot='')
$ErrorActionPreference='Stop'
if(-not $ModuleRoot){$ModuleRoot=Join-Path (Split-Path -Parent $PSScriptRoot) 'modules'}
# Import directly in script scope, not in the helper's disappearing scope.
$core=[Management.Automation.Language.Parser]::ParseFile((Join-Path $ModuleRoot '00.Core.ps1'),[ref]$null,[ref]$null)
foreach($name in @('Initialize-LDLCScriptState','Test-StopRequested','Test-LDLCStopRequestError','Stop-IfRequested')){
 $fn=$core.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
 . ([scriptblock]::Create($fn.Extent.Text))
}
$worker=[Management.Automation.Language.Parser]::ParseFile((Join-Path $ModuleRoot '95.WorkerLauncher.ps1'),[ref]$null,[ref]$null)
$main=$worker.EndBlock.Statements|Where-Object{$_ -is [Management.Automation.Language.IfStatementAst] -and $_.Clauses[0].Item1.Extent.Text -eq '$InstallWorker'}|Select-Object -First 1
$body=[scriptblock]::Create($main.Extent.Text)
$temp=Join-Path ([IO.Path]::GetTempPath()) ('Prep-Startup-Stop-'+[guid]::NewGuid().ToString('N'))
function Get-LDLCRuntimeRoot {return $script:Fixture}
function Get-LDLCBooleanEnvironmentValue {param($Name,$Default) return $Default}
function Remove-LDLCLegacyRuntimeFiles {}
function Initialize-LDLCTelemetry {}
function Write-LDLCLocalLog {param($Level,$Text)}
function Initialize-LDLCConsoleWindow {if($script:StopDuringInit){New-Item -ItemType File -Path (Join-Path $script:Fixture 'LDLC_STOP') -Force|Out-Null}}
function Complete-LDLCTelemetryRun {param($ResultStatus) $script:FinalStatus=$ResultStatus}
function Invoke-LDLCPreparation {Stop-IfRequested;$script:WorkflowEntered=$true}
$checks=0
try{
 foreach($case in @('normal','stop_before_init','stop_during_init')){
  $script:Fixture=Join-Path $temp $case;New-Item -ItemType Directory -Path $script:Fixture -Force|Out-Null
  $script:WorkflowEntered=$false;$script:FinalStatus='';$script:StopDuringInit=($case -eq 'stop_during_init')
  if($case -eq 'stop_before_init'){New-Item -ItemType File -Path (Join-Path $script:Fixture 'LDLC_STOP')|Out-Null}
  $InstallWorker=$true;$script:LDLCRoot=$temp
  & $body
  if($case -eq 'normal'){if(-not $script:WorkflowEntered){throw 'Normal startup blocked'}}
  else{if($script:WorkflowEntered -or $script:FinalStatus -ne 'stopped' -or -not (Test-Path (Join-Path $script:Fixture 'LDLC_STOP'))){throw 'Stop request lost before workflow'}}
  $checks++
 }
 $script:StopDuringInit=$false;$script:Fixture=Join-Path $temp 'direct';New-Item -ItemType Directory -Path $script:Fixture -Force|Out-Null
 $marker=Join-Path $script:Fixture 'LDLC_STOP';New-Item -ItemType File -Path $marker|Out-Null
 Initialize-LDLCScriptState -ProjectRoot $temp
 if(Test-Path $marker){throw 'Legacy initialization did not clean stale request'};$checks++
 New-Item -ItemType File -Path $marker|Out-Null
 Initialize-LDLCScriptState -ProjectRoot $temp -PreserveStopRequest
 if(-not (Test-Path $marker)){throw 'Preserving initialization lost request'};$checks++
 Write-Host "OK startup cancellation: $checks scenarios; normal, early/during-init stop, stale marker, explicit preservation; no installations."
}finally{if(Test-Path $temp){Remove-Item -LiteralPath $temp -Recurse -Force}}
