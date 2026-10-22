#requires -Version 5.1
[CmdletBinding()]
param([string]$ModuleRoot='')
$ErrorActionPreference='Stop'
if(-not $ModuleRoot){$ModuleRoot=Join-Path (Split-Path -Parent $PSScriptRoot) 'modules'}
. (Join-Path $ModuleRoot '70.DefaultApps.ps1')
. (Join-Path $ModuleRoot '72.ChromeTaskbar.ps1')
$script:checks=0;$cases=New-Object 'Collections.Generic.List[object]'
function Assert($Value,$Message){$script:checks++;if(-not $Value){throw $Message}}
function Write-Section($Text){}
function Write-ProgressFile($Percent,$Text){$script:progress++}
function Write-Info($Text){$script:info+=[string]$Text}
function Write-Ok($Text){$script:ok+=[string]$Text}
function Write-Warn($Text){$script:warn+=[string]$Text}
function Stop-IfRequested {$script:stopChecks++;if($script:stopAt -gt 0 -and $script:stopChecks -ge $script:stopAt){throw [OperationCanceledException]::new('fixture stop')}}
function Test-LDLCStopRequestError($ErrorRecord){return $ErrorRecord.Exception -is [OperationCanceledException]}
function Get-LDLCChromeExecutablePath {if($script:missing){return $null};return 'C:\Fixture\chrome.exe'}
function Start-Sleep {param([int]$Milliseconds)$script:elapsed+=$Milliseconds}
function Get-Process {param($Name)Assert ($Name -eq 'explorer') 'Only Explorer may be refreshed';return [pscustomobject]@{Name='explorer';Id=123}}
function Stop-Process {
 [CmdletBinding()]param([Parameter(ValueFromPipeline=$true)]$InputObject,[switch]$Force,[switch]$Confirm)
 process{$script:stopCalls++;Assert ($Force -and -not $Confirm) 'Preserve historical Explorer refresh contract'}
}
function Start-Process {param($FilePath)$script:startCalls++;Assert ($FilePath -eq 'explorer') 'Never start another program';if($script:restartFailure){throw 'fixture Explorer restart denied'}}
function Close-LDLCExplorerFileWindows {$script:closeCalls++;if($script:closeFailure){throw 'fixture Explorer cleanup failed'}}
# Any restored call to the recent UIA/confirmation path fails this suite.
function Get-LDLCChromeTaskbarPinState {throw 'Unexpected recent pin-state confirmation'}
function Invoke-LDLCChromeTaskbarContextAction {throw 'Unexpected recent Explorer UI menu'}
function Wait-LDLCChromeTaskbarPin {throw 'Unexpected recent pin timeout'}

# Compare the actual function body to the historical fixture. Only the public
# implementation name and stop-request checks are deliberately different.
$fixture=Get-Content (Join-Path $PSScriptRoot 'fixtures/chrome-taskbar-before-changes.json') -Raw | ConvertFrom-Json
$historical=$fixture.HistoricalFunction.Replace('function Invoke-LDLCChromeTaskbarPinBeforeWindowsUpdate','function Invoke-LDLCChromeTaskbarPin').Replace("`r`n","`n").Trim()
$current=(Get-Command Invoke-LDLCChromeTaskbarPin).ScriptBlock.Ast.Parent.Extent.Text.Replace("`r`n","`n")
$current=[regex]::Replace($current,'(?m)^[ \t]*Stop-IfRequested\n','')
$current=[regex]::Replace($current,'(?m)^[ \t]*if \(Test-LDLCStopRequestError \$_\) \{ throw \}\n','')
Assert ($current.Trim() -ceq $historical) 'Chrome taskbar implementation differs from the historical method beyond stop handling'

$saved=[Environment]::GetEnvironmentVariable('LOCALAPPDATA','Process')
$temp=Join-Path ([IO.Path]::GetTempPath()) ('Chrome-Historical-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
try {
 foreach($name in @('normal','pre-existing-layout','missing-chrome','layout-write-denied','explorer-restart-denied','explorer-cleanup-denied','cancel-before-layout','cancel-before-restart','cancel-after-restart')){
  $script:missing=$false;$script:restartFailure=$false;$script:closeFailure=$false;$script:stopAt=0;$script:stopChecks=0;$script:progress=0;$script:elapsed=0;$script:stopCalls=0;$script:startCalls=0;$script:closeCalls=0;$script:warn=@();$script:ok=@();$script:info=@()
  $env:LOCALAPPDATA=Join-Path $temp $name
  [void][IO.Directory]::CreateDirectory($env:LOCALAPPDATA)
  $layout=Join-Path $env:LOCALAPPDATA 'Microsoft/Windows/Shell/LayoutModification.xml'
  $expected='prepared';$expectedWarning=0
  switch($name){
   'pre-existing-layout' {[void][IO.Directory]::CreateDirectory((Split-Path -Parent $layout));[IO.File]::WriteAllText($layout,'<old/>')}
   'missing-chrome' {$script:missing=$true;$expected='not_prepared';$expectedWarning=1}
   'layout-write-denied' {[void][IO.Directory]::CreateDirectory($layout);$expected='not_prepared';$expectedWarning=1}
   'explorer-restart-denied' {$script:restartFailure=$true;$expectedWarning=1}
   'explorer-cleanup-denied' {$script:closeFailure=$true;$expectedWarning=1}
   'cancel-before-layout' {$script:stopAt=1;$expected='cancelled'}
   'cancel-before-restart' {$script:stopAt=2;$expected='cancelled'}
   'cancel-after-restart' {$script:stopAt=3;$expected='cancelled'}
  }
  $result=$false;$stopped=$false
  try{$result=Invoke-LDLCChromeTaskbarPinBeforeWindowsUpdate -ProgressPercent 90}catch{if(Test-LDLCStopRequestError $_){$stopped=$true}else{throw}}
  $observed=if($stopped){'cancelled'}elseif($result){'prepared'}else{'not_prepared'}
  Assert ($observed -eq $expected) ($name+': unexpected result '+$observed)
  Assert ($script:warn.Count -eq $expectedWarning) ($name+': false warning or hidden real failure')
  Assert ($script:elapsed -le 2800) ($name+': recent confirmation timeout returned')
  Assert (-not (($script:ok+$script:info) -match '^Chrome epingle')) ($name+': layout must not claim visual pin verification')
  if(Test-Path -LiteralPath $layout -PathType Leaf){
   $bytes=[IO.File]::ReadAllBytes($layout);Assert (-not ($bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191)) 'Historical layout is UTF8 without BOM'
   [xml]$xml=[IO.File]::ReadAllText($layout)
   $ns=New-Object Xml.XmlNamespaceManager($xml.NameTable)
   $ns.AddNamespace('l','http://schemas.microsoft.com/Start/2014/LayoutModification');$ns.AddNamespace('t','http://schemas.microsoft.com/Start/2014/TaskbarLayout')
   Assert ($xml.SelectSingleNode('//l:CustomTaskbarLayoutCollection',$ns).PinListPlacement -eq 'Append') 'Append Chrome; never replace the current pin list'
   Assert ($xml.SelectSingleNode('//t:DesktopApp',$ns).DesktopApplicationID -eq 'Chrome') 'Historical layout must select Chrome'
   Assert ($script:ok.Count -eq 1 -and $script:ok[0] -match 'Layout taskbar Chrome prepare') 'Report layout preparation accurately'
  }
  if($name -in @('normal','pre-existing-layout')){Assert ($script:stopCalls -eq 1 -and $script:startCalls -eq 1 -and $script:closeCalls -eq 1) 'Complete the historical Explorer refresh without opening the recent pin menu'}
  if($name -in @('missing-chrome','layout-write-denied','cancel-before-layout','cancel-before-restart')){Assert ($script:stopCalls -eq 0 -and $script:startCalls -eq 0) 'Never refresh Explorer when layout preparation fails or stop is requested'}
  if($name -eq 'cancel-after-restart'){Assert ($script:stopCalls -eq 1 -and $script:startCalls -eq 1) 'Stop must never leave Explorer killed without restarting it'}
  $cases.Add(@{Scenario=$name;Result=$observed;Warnings=$script:warn.Count;ExplorerRestartRequests=$script:startCalls;VisualPinVerified=$false})
 }
}finally{
 [Environment]::SetEnvironmentVariable('LOCALAPPDATA',$saved,'Process')
 Remove-Item -LiteralPath $temp -Force -Recurse
}
Write-Host ('::notice title=Chrome historical taskbar::'+(@{Success=$true;Assertions=$script:checks;Cases=@($cases.ToArray());HistoricalReference=$fixture.Revision;HistoricalBodyVerified=$true;RealXMLWriteRead=$true;ExplorerActionsSimulated=$true;ActualUserTaskbarChanged=$false;VisualPinVerified=$false}|ConvertTo-Json -Depth 8 -Compress))
