param([string]$ModuleRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'modules'))
$ErrorActionPreference='Stop'
. (Join-Path $ModuleRoot '05.Telemetry.ps1')
. (Join-Path $ModuleRoot '70.DefaultApps.ps1')
$script:checks=0
function Assert([bool]$Condition,[string]$Reason) {$script:checks++; if(-not $Condition){throw $Reason}}
function Test-LDLCTelemetryDisabled { return $false }
function Update-LDLCTelemetryRun { param($Message,[switch]$Force) }
function Get-LDLCEntryPointPath { return 'TEST-UI-ACK.ps1' }
function Write-Section {param($Text)}
function Write-Step {param($Text)}
function Write-Ok {param($Text)}
function Write-Info {param($Text) $script:infos++}
function Write-Warn {param($Text) Add-LDLCTelemetryEvent -Severity warning -Message $Text}
function Stop-IfRequested {if($script:cancel){throw 'LDLC_STOP_REQUESTED'}}
function Test-LDLCStopRequestError {param($ErrorRecord) return ($ErrorRecord.Exception.Message -eq 'LDLC_STOP_REQUESTED')}
function Wait-LDLCDefaultAppsCondition {param($TimeoutMilliseconds,$PollMilliseconds,$Probe) Stop-IfRequested; return $false}
function Close-LDLCDefaultAppsPage {}
function Set-LDLCTaskbarOptionsWithRegistry {return $true}
function Get-LDLCDefaultAppState {
 param($Application)
 $confirmed=($script:case -ne 'real-association-failure' -or $Application -ne 'Chrome')
 return [pscustomobject]@{Confirmed=$confirmed;Missing=@('https');Associations=@([pscustomobject]@{Association='https';ProgId=$(if($confirmed){'ChromeHTML'}else{'MSEdgeHTM'});Executable='test.exe';Error=''})}
}
function Wait-LDLCDefaultAppConfirmation {param($Application,$TimeoutMilliseconds) $state=Get-LDLCDefaultAppState $Application;return [pscustomobject]@{Confirmed=$state.Confirmed;State=$state}}
function Get-LDLCDefaultAppAttemptRoutes {param($Application,$State) return @()}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('DefaultApps-UI-ACK-'+[guid]::NewGuid().ToString('N'))
$oldUi=$env:LDLC_DEFAULT_APPS_UI
try {
 [IO.Directory]::CreateDirectory($fixture)|Out-Null
 $env:LDLC_DEFAULT_APPS_UI='1';$script:ProgressFile=Join-Path $fixture 'progress.txt'
 $script:LDLCTelemetryInitialized=$true;$script:LDLCTelemetryDisabled=$false;$script:LDLCTelemetrySending=$false
 $script:LDLCTelemetryComputerInfo=[pscustomobject]@{ComputerName='TEST-ACK'}
 foreach($caseName in @('confirmed-no-ui-ack','real-association-failure','cancellation')) {
  $script:case=$caseName;$script:cancel=($caseName -eq 'cancellation');$script:infos=0
  $script:LDLCTelemetryEvents=New-Object 'System.Collections.Generic.List[object]';$script:LDLCTelemetryEventKeys=@{}
  $script:LDLCDefaultAppsCompactDepth=0;$script:LDLCDefaultAppsCompactPath=$null;$script:LDLCDefaultAppsCompactProgress=$null
  $cancelled=$false
  try{Invoke-LDLCChromeDefaultAppsSequence}catch{$cancelled=Test-LDLCStopRequestError $_;if(-not $cancelled){throw}}
  $counts=Get-LDLCTelemetryCounts
  $status=Convert-LDLCTelemetryRunStatus -Status 'success' -Counts $counts -Final
  switch($caseName){
   'confirmed-no-ui-ack' {
    Assert ($status -eq 'success' -and $counts.WarningCount -eq 0) 'Missing render ACK turned confirmed Windows associations into a blocking warning.'
    Assert ($script:LDLCDefaultAppsCompactProgress.Success -and $script:LDLCDefaultAppsCompactProgress.Progress -eq 100) 'Confirmed final state not displayed.'
    Assert ($script:infos -gt 0) 'UI diagnostics disappeared instead of remaining informative.'
   }
   'real-association-failure' {
    Assert ($status -ne 'success' -and $counts.WarningCount -gt 0) 'Real association failure was hidden.'
    Assert (-not $script:LDLCDefaultAppsCompactProgress.Success -and $script:LDLCDefaultAppsCompactProgress.Progress -lt 100) 'False success after real association failure.'
    Assert (@($script:LDLCTelemetryEvents|Where-Object Message -match 'Chrome').Count -gt 0) 'Missing precise cause of real blockage.'
   }
   'cancellation' {Assert $cancelled 'Cancellation was swallowed.'}
  }
  Assert ($script:LDLCDefaultAppsCompactDepth -eq 0 -and -not $script:LDLCDefaultAppsCompactPath) 'Compact state was not cleaned.'
 }
 # The existing physical-click guard must remain before any native interop.
 $source=[IO.File]::ReadAllText((Join-Path $ModuleRoot '70.DefaultApps.ps1'))
 $tokens=$null;$errors=$null
 $ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
 $click=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-LDLCDefaultAppsObservedClick'},$true).Extent.Text
 $guard=$click.IndexOf('if ($script:LDLCDefaultAppsCompactPath -and -not (Test-LDLCDefaultAppsCompactUiAck)) { return $false }')
 Assert ($guard -gt 0 -and $guard -lt $click.IndexOf('Ensure-LDLCDefaultAppsNativeInterop')) 'Physical click must stay disabled without matching ACK.'
 Write-Host "OK compact UI warning: $script:checks assertions, confirmed/real failure/cancel, telemetry statuses; OS boundaries simulated."
}
finally{$env:LDLC_DEFAULT_APPS_UI=$oldUi;Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue}
