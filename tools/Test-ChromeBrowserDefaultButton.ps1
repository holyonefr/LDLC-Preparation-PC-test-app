param([ValidateSet('modules','worker-modules')][string]$Tree='modules')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root "$Tree/70.DefaultApps.ps1")
$script:Assertions=0
function Assert-True([bool]$Value,[string]$Message) { if(-not $Value){throw $Message};$script:Assertions++ }
function Assert-Throws([scriptblock]$Action,[string]$Pattern) {
    $message='';try{& $Action | Out-Null}catch{$message=$_.Exception.Message}
    Assert-True ($message -match $Pattern) "Erreur attendue $Pattern : $message"
}
# Only pattern identifiers are needed by the real action code. No native UI,
# registry, mouse input or effective defaults on the test machine are accessed.
if($env:OS -eq 'Windows_NT'){Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes}
else {
    Add-Type @'
namespace System.Windows.Automation {
    public static class InvokePattern { public static readonly object Pattern = new object(); }
    public static class ScrollItemPattern { public static readonly object Pattern = new object(); }
}
'@
}
function New-Node([string]$Name,[string]$Type='Text') {
    $node=[pscustomobject]@{
        Current=[pscustomobject]@{Name=$Name;ControlType=[pscustomobject]@{ProgrammaticName="ControlType.$Type"};AutomationId='';IsEnabled=$true;IsOffscreen=$false}
        Parent=$null;Children=@();Id=[guid]::NewGuid().ToString();HasInvoke=($Type -eq 'Button')
    }
    $node | Add-Member ScriptMethod GetRuntimeId {return @($this.Id)}
    $node | Add-Member ScriptMethod TryGetCurrentPattern {
        param($Pattern,$Result)
        if($Pattern -eq [System.Windows.Automation.InvokePattern]::Pattern -and $this.HasInvoke){$Result.Value=$script:InvokePattern;return $true}
        return $false
    }
    return $node
}
function Add-Node($Parent,$Child){$Child.Parent=$Parent;$Parent.Children+=,$Child}
function Get-LDLCDefaultAppsParentElement($Element){return $Element.Parent}
function Get-LDLCDefaultAppsControls($Root){
    foreach($node in $Root.Children){
        [pscustomobject]@{Element=$node;Name=$node.Current.Name;AutomationId='';ControlType=$node.Current.ControlType.ProgrammaticName;Enabled=$node.Current.IsEnabled;Offscreen=$node.Current.IsOffscreen}
        Get-LDLCDefaultAppsControls $node
    }
}
function Write-Info($Text){}
function Stop-IfRequested{if($script:Cancelled){throw 'LDLC_STOP_REQUESTED'}}
function Test-LDLCStopRequestError($ErrorRecord){return $ErrorRecord.Exception.Message -eq 'LDLC_STOP_REQUESTED'}
function Get-LDLCDefaultAppsTick{return $script:Tick}
function Start-Sleep([int]$Milliseconds,[int]$Seconds){$script:Tick+=$Milliseconds+$Seconds*1000}
function Get-LDLCDefaultAppsWindows{return [pscustomobject]@{Handle=123;ProcessId=456;IsSettings=$true}}
function Get-LDLCDefaultAppsRoot($Window){return $script:Page}
function Set-LDLCDefaultAppsFocus($Window){return $true}
function Move-LDLCDefaultAppsScroll($Root,[switch]$Reset){
    Assert-True ([bool]$Reset) 'Le bouton navigateur doit etre recherche en haut, sans descendre dans les associations.'
    $script:Resets++
    if($script:ScrollWorks){foreach($control in @(Get-LDLCDefaultAppsControls $Root)){$control.Element.Current.IsOffscreen=$false}}
    return $script:ScrollWorks
}
function Invoke-LDLCDefaultAppsObservedClick($Control){
    $script:Clicks++
    if($script:MouseBlocked){throw 'HIT_TEST_REFUSED'}
    $script:Ready=$script:ApplyChange
    return $true
}
function Close-LDLCDefaultAppsPage{param([switch]$ExistingDefaultPage)}
function Ensure-LDLCDefaultAppsUiAutomation{}
function Start-Process{param($FilePath)$script:OpenedUri=$FilePath}
function Get-LDLCEffectiveAssociation([string]$Association){
    $good=$script:Ready -or ($script:HtmlOnly -and $Association -eq '.html')
    [pscustomobject]@{Association=$Association;ProgId=$(if($good){'ChromeHTML.Test'}else{'MSEdgeHTM'});Executable=(Join-Path ([IO.Path]::GetTempPath()) $(if($good){'chrome.exe'}else{'msedge.exe'}));Error=''}
}
function Reset-Case {
    $script:Page=New-Node 'Settings' 'Window'
    $script:Card=New-Node '' 'Group';Add-Node $script:Page $script:Card
    $script:Heading=New-Node 'Définir Google Chrome comme navigateur par défaut';Add-Node $script:Card $script:Heading
    $script:Button=New-Node 'Définir par défaut' 'Button';Add-Node $script:Card $script:Button
    $script:Other=New-Node 'Définir par défaut' 'Button';Add-Node $script:Page $script:Other
    $script:Tick=0;$script:Invokes=0;$script:Clicks=0;$script:Resets=0;$script:Cancelled=$false
    $script:InvokeFails=$false;$script:MouseBlocked=$false;$script:ScrollWorks=$true
    $script:Ready=$false;$script:HtmlOnly=$false;$script:ApplyChange=$true;$script:OpenedUri=''
    $script:InvokePattern=[pscustomobject]@{}
    $script:InvokePattern | Add-Member ScriptMethod Invoke {
        $script:Invokes++
        if($script:InvokeFails){throw 'INVOKE_UNAVAILABLE'}
        $script:Ready=$script:ApplyChange
    }
}
Reset-Case
$control=Get-LDLCChromeBrowserDefaultControl $script:Page
Assert-True (Test-LDLCDefaultAppsSameElement $control.Element $script:Button) 'Choisir la ligne navigateur, pas un autre Definir par defaut.'
foreach($label in @(
    'Définir Google Chrome en tant que navigateur par défaut, Définir par défaut',
    'Définir Google Chrome pour navigateur par défaut : Définir par défaut',
    'Définir Google Chrome comme votre navigateur par défaut; Définir par défaut',
    "Définir Google Chrome comme navigateur par défaut`r`nDéfinir par défaut",
    'Définir par défaut, Définir Google Chrome comme navigateur par défaut',
    'Make Google Chrome your default browser, Set default',
    'Set Google Chrome as your default browser: Set as default')){
    Reset-Case
    $script:Page.Children=@($script:Button,$script:Other);$script:Button.Parent=$script:Page
    $script:Button.Current.Name=$label
    $control=Get-LDLCChromeBrowserDefaultControl $script:Page
    Assert-True ($control -and (Test-LDLCDefaultAppsSameElement $control.Element $script:Button)) "Libelle combine reconnu sans titre Chrome separe : $label"
    Assert-True ($null -ne (Select-LDLCDefaultAppsControl @(Get-LDLCDefaultAppsControls $script:Page) Page -Application Chrome)) 'La fiche doit etre reconnue avant la tentative de clic.'
}
foreach($label in @('Définir Google Chrome par défaut pour les fichiers .pdf, Définir par défaut','Make Microsoft Edge your default browser, Set default','Rechercher Google Chrome dans le Store','Définir par défaut')){
    Reset-Case;$script:Page.Children=@($script:Button);$script:Button.Parent=$script:Page;$script:Button.Current.Name=$label
    Assert-True ($null -eq (Get-LDLCChromeBrowserDefaultControl $script:Page)) "Ne pas cliquer un autre controle : $label"
}
Reset-Case
$script:Card.Current.Name=$script:Heading.Current.Name;$script:Card.Children=@($script:Button)
$script:Button.Current.Name='';$label=New-Node 'Définir par défaut';Add-Node $script:Button $label
$control=Get-LDLCChromeBrowserDefaultControl $script:Page
Assert-True ($control -and (Test-LDLCDefaultAppsSameElement $control.Element $script:Button)) 'Retrouver le Button non nomme contenant le texte, dans le Group de la ligne Chrome.'
$script:Button.Current.IsEnabled=$false
Assert-True ($null -eq (Get-LDLCChromeBrowserDefaultControl $script:Page)) 'Ne pas choisir le bouton voisin quand celui de Chrome est desactive.'
Reset-Case
Add-Node $script:Card (New-Node 'Définir par défaut' 'Button')
Assert-True ($null -eq (Get-LDLCChromeBrowserDefaultControl $script:Page)) 'Ne pas cliquer si plusieurs boutons de la meme ligne sont ambigus.'

Reset-Case;$script:MouseBlocked=$true
Assert-True (Invoke-LDLCDefaultAppsUiAction -Kind BrowserDefault -Application Chrome) 'Activer le bouton via UIA meme si le hit-test souris serait refuse.'
Assert-True ($script:Invokes -eq 1 -and $script:Clicks -eq 0) 'Utiliser Invoke avant le clic physique pour le seul bouton navigateur.'
Assert-True (Wait-LDLCDefaultAppConfirmation Chrome).Confirmed 'Confirmer les quatre associations apres activation.'
Reset-Case;$script:Button.HasInvoke=$false
Assert-True (Invoke-LDLCDefaultAppsUiAction -Kind BrowserDefault -Application Chrome) 'Repli clic observe si Invoke est absent.'
Assert-True ($script:Invokes -eq 0 -and $script:Clicks -eq 1) 'Un seul clic observe de repli.'
Reset-Case;$script:InvokeFails=$true
Assert-True (Invoke-LDLCDefaultAppsUiAction -Kind BrowserDefault -Application Chrome) 'Repli clic observe si Invoke echoue.'
Assert-True ($script:Invokes -eq 1 -and $script:Clicks -eq 1) 'Essai UIA puis un clic observe.'
Reset-Case;$script:Heading.Current.IsOffscreen=$true;$script:Button.Current.IsOffscreen=$true
Assert-True (Invoke-LDLCDefaultAppsUiAction -Kind BrowserDefault -Application Chrome) 'Remonter puis reacquerir la ligne hors ecran.'
Assert-True ($script:Resets -eq 1 -and $script:Invokes -eq 1) 'Une seule remise en haut, puis activation du vrai bouton.'
Reset-Case;$script:Page.Children=@($script:Other)
Assert-Throws {Invoke-LDLCDefaultAppsUiAction -Kind BrowserDefault -Application Chrome -TimeoutMilliseconds 1000} 'BrowserDefault introuvable'
Assert-True ($script:Clicks -eq 0 -and $script:Invokes -eq 0 -and $script:Resets -le 3) 'Ne pas cliquer Definir par defaut sans la ligne navigateur Chrome.'
Reset-Case;$script:ApplyChange=$false
[void](Invoke-LDLCDefaultAppsUiAction -Kind BrowserDefault -Application Chrome)
Assert-True (-not (Wait-LDLCDefaultAppConfirmation Chrome -TimeoutMilliseconds 1000).Confirmed) 'Un Invoke sans changement Windows ne vaut jamais succes.'
$script:HtmlOnly=$true
Assert-True (-not (Wait-LDLCDefaultAppConfirmation Chrome -TimeoutMilliseconds 1000).Confirmed) '.html seul ne suffit pas a confirmer le navigateur par defaut.'
Reset-Case
Open-LDLCDefaultAppPage -Uri 'ms-settings:defaultapps?registeredAppMachine=ChromeFixture' -Application Chrome
Assert-True ($script:OpenedUri -match 'ChromeFixture' -and $script:Resets -eq 1) 'Reconnaissance et remise en haut de la fiche sans titre Chrome distinct.'
Reset-Case;$script:Cancelled=$true
Assert-Throws {Invoke-LDLCDefaultAppsUiAction -Kind BrowserDefault -Application Chrome} 'LDLC_STOP_REQUESTED'
Assert-True ($script:Clicks -eq 0 -and $script:Invokes -eq 0) 'Quitter interrompt avant le clic.'
Write-Host "OK : $script:Assertions controles du bouton navigateur Chrome ($Tree), interactions Windows simulees."
