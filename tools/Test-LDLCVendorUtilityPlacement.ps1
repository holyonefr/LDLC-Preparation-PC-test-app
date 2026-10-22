#requires -Version 5.1
param([string]$OutputDirectory='artifacts/beta-placement')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$tree=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'modules/90.Workflow.ps1'),[ref]$null,[ref]$null)
$main=$tree.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-LDLCPreparation'},$true)
# Execute the actual orchestration with all external/system operations replaced.
foreach($name in @($main.Body.FindAll({param($n)$n -is [Management.Automation.Language.CommandAst]},$true)|ForEach-Object {$_.GetCommandName()}|Sort-Object -Unique)){
 if($name -and $name -notin @('Get-Command','Out-Null')){Set-Item -Path ('Function:'+ $name) -Value {}}
}
. ([scriptblock]::Create($main.Extent.Text))
$ui=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'modules/99.UI.ps1'),[ref]$null,[ref]$null)
$phases=$ui.Find({param($n)$n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -ceq '$script:phases'},$true)
. ([scriptblock]::Create($phases.Extent.Text))
$phaseFunction=$ui.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-LDLCPhaseIndex'},$true)
. ([scriptblock]::Create($phaseFunction.Extent.Text))
function Start-LDLCWindowsUpdatesDuringPreparation {return @{Started=$true}}
function Test-LDLCTelemetryDisabled {return $false}
function Stop-IfRequested {if($script:Stop){throw 'LDLC_STOP_REQUESTED'}}
function Test-LDLCStopRequestError {param($e)return $e.Exception.Message -eq 'LDLC_STOP_REQUESTED'}
function Write-ProgressFile {param($Percent,$Message)if($Percent -eq 80){$script:Trace.Add('configuration')}}
function Record-ApplicationFixture {
 param($App,$ProgressPercent)
 $script:Trace.Add('app:'+ $App.Name)
 if($script:Scenario -eq 'stop_after_last' -and $App.Name -eq 'C'){$script:Stop=$true}
 if($script:Scenario -eq 'failed_first' -and $App.Name -eq 'A'){throw 'Fixture app A failure'}
 if($script:Scenario -eq 'failed_last' -and $App.Name -eq 'C'){throw 'Fixture app C failure'}
}
function Install-LDLCApplication {param($App,$ProgressPercent) Record-ApplicationFixture -App $App -ProgressPercent $ProgressPercent}
function Install-Or-ReinstallWithChoco {param($App,$ProgressPercent) Record-ApplicationFixture -App $App -ProgressPercent $ProgressPercent}
function Invoke-LDLCVendorUtility {
 param($ProgressPercent)
 Stop-IfRequested
 $script:Trace.Add('vendor')
 $script:VendorPercent=$ProgressPercent
 $script:VendorPhase=$script:phases[(Get-LDLCPhaseIndex $ProgressPercent)].Name
 if($script:Scenario -eq 'stop_in_vendor'){throw 'LDLC_STOP_REQUESTED'}
}
function Invoke-LDLCChromeDefaultAppsSequence {$script:Trace.Add('defaults')}
$cases=New-Object 'Collections.Generic.List[object]';$script:Checks=0
function Assert($v,$m){$script:Checks++;if(-not $v){throw $m}}
foreach($scenario in @('normal','one_app','no_apps','failed_first','failed_last','stop_after_last','stop_in_vendor')){
 try{
  $script:Scenario=$scenario;$script:Stop=$false;$script:PendingReboot=$false;$script:PowerSettingsCaptured=$false
  $script:Trace=New-Object 'Collections.Generic.List[string]';$script:VendorPercent=-1;$script:VendorPhase=''
  $script:Apps=if($scenario -eq 'no_apps'){@()}elseif($scenario -eq 'one_app'){@(@{Name='A'})}else{@(@{Name='A'},@{Name='B'},@{Name='C'})}
  Invoke-LDLCPreparation | Out-Null
  $trace=@($script:Trace.ToArray());$vendorIndex=[Array]::IndexOf($trace,'vendor');$configIndex=[Array]::IndexOf($trace,'configuration')
  if($scenario -eq 'stop_after_last'){
   Assert ($vendorIndex -eq -1 -and $configIndex -eq -1 -and $script:LDLCWorkflowStatus -eq 'stopped') 'Quitter ne doit pas demarrer le module constructeur.'
  }else{
   Assert (@($trace|Where-Object {$_ -eq 'vendor'}).Count -eq 1) 'Module absent ou execute plusieurs fois.'
   Assert ($vendorIndex -eq @($script:Apps).Count) 'Module constructeur pas immediatement apres les logiciels.'
   Assert ($script:VendorPercent -eq 60 -and $script:VendorPhase -ceq 'INSTALLATION') 'Module affiche dans la mauvaise phase UI.'
   if($scenario -eq 'stop_in_vendor'){
    Assert ($configIndex -eq -1 -and 'defaults' -notin $trace -and $script:LDLCWorkflowStatus -eq 'stopped') 'Configuration lancee apres arret.'
   }else{
    Assert ($configIndex -eq $vendorIndex+1 -and [Array]::IndexOf($trace,'defaults') -gt $configIndex) 'Configuration avant la fin des applications.'
   }
  }
  $cases.Add(@{Name=$scenario;Result='passed';Trace=$trace;VendorPhase=$script:VendorPhase;VendorPercent=$script:VendorPercent})
 }catch{$cases.Add(@{Name=$scenario;Result='failed';Error=$_.Exception.Message});Write-Warning ($scenario+': '+$_.Exception.Message)}
}
[void](New-Item -ItemType Directory -Path $OutputDirectory -Force)
$report=@{Kind='beta_placement_tests';Cases=@($cases.ToArray());Assertions=$script:Checks;Failures=@($cases.ToArray()|Where-Object Result -eq failed).Count;Mode='actual_orchestration_and_ui_phase_function_with_system_operations_simulated';NetworkRequests=0;VendorInstallerExecuted=$false}
$report|ConvertTo-Json -Depth 7|Set-Content (Join-Path $OutputDirectory 'beta-placement.json') -Encoding UTF8
if($report.Failures){throw "$($report.Failures) tests de placement en echec."}
Write-Host "$($cases.Count) scenarios / $script:Checks assertions reussis."
