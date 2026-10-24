#requires -Version 5.1
param([string]$ModuleRoot=(Join-Path (Split-Path -Parent $PSScriptRoot) 'modules'),[switch]$Historical)
$ErrorActionPreference='Stop'
. (Join-Path $ModuleRoot '70.DefaultApps.ps1')
$script:Checks=0
function Assert($Value,$Reason){$script:Checks++;if(-not $Value){throw $Reason}}
function Stop-IfRequested{if($script:Cancelled){throw 'LDLC_STOP_REQUESTED'}}
function Test-LDLCStopRequestError($Record){$Record.Exception.Message -match 'LDLC_STOP_REQUESTED'}
function Write-Info($Text){}
function Set-LDLCDefaultAppsActionProgress{param($Application,$Association,$Stage)}
function Open-LDLCDefaultAppPage{param($Uri,$Application)}
function Invoke-LDLCChromeBrowserDefaultAction{[pscustomobject]@{Confirmed=$false;BrowserActionInvoked=$true}}
function Invoke-LDLCDefaultAppsUiAction{param($Kind,$Application,$Association)}
function Get-LDLCDefaultAppState{param($Application);[pscustomobject]@{Confirmed=($script:Ready.Count -eq 4);Missing=@('http','https','.htm','.html')|Where-Object {-not $script:Ready.ContainsKey($_)}}}
function Get-LDLCEffectiveAssociation{param($Association);[pscustomobject]@{Association=$Association;ProgId=$(if($script:Ready.ContainsKey($Association)){'ChromeHTML'}else{'MSEdgeHTM'});Executable=(Join-Path ([IO.Path]::GetTempPath()) $(if($script:Ready.ContainsKey($Association)){'chrome.exe'}else{'msedge.exe'}));Error=''}}
function Complete-LDLCDefaultAppsChoice{
    param($Association,$Application,$TimeoutMilliseconds)
    $script:Attempted.Add($Association)
    if($script:CancelOnConfirm){$script:Cancelled=$true;Stop-IfRequested}
    if(-not $script:PersistentFailure){$script:Ready[$Association]=$true}
    # Observed VM scenario: the native choice succeeds, but confirmation misses
    # the commit. The next independent read sees HTTP/HTTPS on Chrome.
    if($Association -eq 'http' -or $script:PersistentFailure){throw 'Delayed or refused Windows association (fixture)'}
}
$route=[pscustomobject]@{Kind='RegisteredPage';Uri='ms-settings:defaultapps?registeredAppMachine=ChromeFixture'}
$script:Ready=@{};$script:Attempted=New-Object 'Collections.Generic.List[string]'
$failed=$false
try{$null=Invoke-LDLCDefaultAppAttempt -Application Chrome -State (Get-LDLCDefaultAppState Chrome) -Attempt 1 -Route $route}catch{$failed=$true}
if($Historical){
    Assert ($failed -and $script:Attempted.Count -eq 1 -and -not $script:Ready.ContainsKey('.html')) 'Historical abandonment of remaining HTML associations was not reproduced'
}else{
    Assert (-not $failed -and (Get-LDLCDefaultAppState Chrome).Confirmed) 'A delayed HTTP commit prevented completion of the remaining associations'
    Assert (($script:Attempted -join ',') -eq 'http,https,.htm,.html') 'Not all missing associations were processed'
    $script:Ready=@{};$script:Attempted.Clear();$script:PersistentFailure=$true;$failed=$false
    try{$null=Invoke-LDLCDefaultAppAttempt -Application Chrome -State (Get-LDLCDefaultAppState Chrome) -Attempt 1 -Route $route}catch{$failed=$_.Exception.Message -match 'Associations Chrome restantes'}
    Assert ($failed -and -not (Get-LDLCDefaultAppState Chrome).Confirmed) 'A persistent real Windows refusal was reported as success'
    Assert ($script:Attempted.Count -eq 4) 'One refused association prevented the other independent attempts'
    $script:PersistentFailure=$false;$script:CancelOnConfirm=$true;$stopped=$false
    try{$null=Invoke-LDLCDefaultAppAttempt -Application Chrome -State (Get-LDLCDefaultAppState Chrome) -Attempt 1 -Route $route}catch{$stopped=Test-LDLCStopRequestError $_}
    Assert $stopped 'Cancellation was swallowed while processing the remaining associations'
    $script:Cancelled=$false
}

if($env:OS -eq 'Windows_NT'){Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes}
else{Add-Type @'
namespace System.Windows.Automation {
    public static class InvokePattern { public static readonly object Pattern = new object(); }
    public static class SelectionItemPattern { public static readonly object Pattern = new object(); }
}
'@}
$script:Invokes=0;$script:Selections=0
$script:Invocation=[pscustomobject]@{}
$script:Invocation|Add-Member ScriptMethod Invoke {$script:Invokes++}
$script:Selection=[pscustomobject]@{Current=[pscustomobject]@{IsSelected=$false}}
$script:Selection|Add-Member ScriptMethod Select {$script:Selections++;$this.Current.IsSelected=$true}
$element=[pscustomobject]@{Current=[pscustomobject]@{IsEnabled=$true;IsOffscreen=$false};Choice=$false}
$element|Add-Member ScriptMethod TryGetCurrentPattern {
    param($Pattern,$Result)
    if($this.Choice -and $Pattern -eq [System.Windows.Automation.SelectionItemPattern]::Pattern){$Result.Value=$script:Selection;return $true}
    if($Pattern -eq [System.Windows.Automation.InvokePattern]::Pattern){$Result.Value=$script:Invocation;return $true}
    return $false
}
$element|Add-Member ScriptMethod GetRuntimeId {return @(42,71)}
$control=[pscustomobject]@{Name='.pdf Microsoft Edge';Offscreen=$false;Element=$element;Enabled=$true;ControlType='ControlType.Button'}
function Invoke-LDLCDefaultAppsObservedClick{param($Control);Stop-IfRequested;throw 'Control covered by compact preparation window; physical input refused (fixture)'}
$failed=$false
try{$activated=Invoke-LDLCDefaultAppsControl -Control $control -Kind Association}catch{$failed=$true}
if($Historical){Assert ($failed -and $script:Invokes -eq 0) 'Historical compact-window obstruction did not prevent the native accessibility fallback'}
else{
    Assert (-not $failed -and $activated -and $script:Invokes -eq 1) 'A covered PDF card did not use its exact accessibility action'
    $element.Choice=$true
    Assert (Invoke-LDLCDefaultAppsControl -Control $control -Kind Choice) 'Application choice could not be selected through its native pattern'
    Assert ($script:Selections -eq 1 -and $script:Invokes -eq 1) 'The choice was invoked instead of explicitly selected'
    $script:Cancelled=$true;$stopped=$false
    try{$null=Invoke-LDLCDefaultAppsControl -Control $control -Kind Confirm}catch{$stopped=Test-LDLCStopRequestError $_}
    Assert ($stopped -and $script:Invokes -eq 1) 'Cancellation activated the confirmation control'
    $script:Cancelled=$false
    # Duplicate accessibility aliases of one observed global browser button.
    $control.Name='Definir Google Chrome comme navigateur par defaut, Definir par defaut'
    function Get-LDLCDefaultAppsControls{param($Root);$control;$control}
    Assert ($null -ne (Get-LDLCChromeBrowserDefaultControl -Root 'fixture')) 'Two aliases of the same browser button were mistaken for ambiguous separate controls'
}
Write-Host ('::notice title=VM default-app regression::'+(@{Result='passed';Historical=[bool]$Historical;Assertions=$script:Checks;Mode='actual control/orchestration code with simulated observed VM obstruction and delayed commit';RealDefaultsChanged=$false;PhysicalInputSent=$false}|ConvertTo-Json -Compress))
