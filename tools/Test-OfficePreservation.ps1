#requires -Version 5.1
param([string]$ModuleRoot=(Join-Path (Split-Path -Parent $PSScriptRoot) 'modules'),[switch]$SourceOnly,[switch]$Historical)
$ErrorActionPreference='Stop'
$script:Checks=0
function Assert($Value,$Reason){$script:Checks++;if(-not $Value){throw $Reason}}
function Read-Ast($Path){
    $errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($Path,[ref]$null,[ref]$errors)
    Assert ($errors.Count -eq 0) ('Invalid PowerShell: '+[IO.Path]::GetFileName($Path));return $ast
}
$cleanup=Read-Ast (Join-Path $ModuleRoot '50.Cleanup.ps1')
$workflow=Read-Ast (Join-Path $ModuleRoot '90.Workflow.ps1')
. (Join-Path $ModuleRoot '50.Cleanup.ps1')
$officeNames=@('Microsoft 365 - fr-fr','Microsoft 365 - en-us','Office 365 ProPlus - fr-fr','Microsoft 365 Apps for enterprise - en-us','Microsoft Office Professional Plus 2019','Microsoft Office Home and Student 2021','Microsoft Office LTSC Professional Plus 2024','Microsoft Office Click-to-Run','Microsoft.MicrosoftOfficeHub','Microsoft OneNote','Microsoft Visio','Microsoft Project','LibreOffice','OnlyOffice')
$script:Inventory=@($officeNames|ForEach-Object{[pscustomobject]@{DisplayName=$_;Publisher='Microsoft Corporation';DisplayVersion='16.0';PSChildName=$_}})
$workflowCalls=@($workflow.FindAll({param($n)$n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Remove-LDLCMicrosoftOffice'},$true))
if($Historical){
    Assert ($workflowCalls.Count -gt 0) 'Historical Office workflow call was not reproduced'
    foreach($name in $officeNames[0..3]){Assert (Test-LDLCMicrosoftOfficeName $name) ('Historical Office target was not reproduced: '+$name)}
    Write-Host ('::notice title=Office preservation regression::'+(@{Historical=$true;Assertions=$script:Checks;Result='historical_removal_path_detected';OfficeUninstallerExecuted=$false;Mode='actual historical source, simulated installed product names'}|ConvertTo-Json -Compress))
    return
}
function Assert-NoOfficeRemoval($Ast,$Label){
    $definitions=@($Ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -match '^(Remove-LDLCMicrosoftOffice|Test-LDLCMicrosoftOfficeName|(?:Get|Invoke|Stop|Write)-LDLCOffice)'},$true))
    $calls=@($Ast.FindAll({param($n)$n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -match '^(Remove-LDLCMicrosoftOffice|Test-LDLCMicrosoftOfficeName|(?:Get|Invoke|Stop|Write)-LDLCOffice)'},$true))
    Assert ($definitions.Count -eq 0 -and $calls.Count -eq 0) ('An Office removal entry point remains in '+$Label)
    Assert ($Ast.Extent.Text -notmatch '(?i)OfficeClickToRun\.exe|OfficeC2RClient\.exe|Suppression Microsoft Office') ('An Office remover or removal progress message remains in '+$Label)
}
Assert ($workflowCalls.Count -eq 0) 'The real workflow still invokes Office removal'
Assert-NoOfficeRemoval $cleanup 'cleanup module'
Assert-NoOfficeRemoval $workflow 'workflow module'
function Get-LDLCInstalledPrograms{param([switch]$Refresh);$script:Inventory}
function Stop-IfRequested{}
function Write-Section($Text){}
function Write-ProgressFile($Percent,$Text){}
function Write-Ok($Text){}
function Write-Step($Text){}
function Write-Warn($Text){throw ('Unexpected cleanup warning: '+$Text)}
function Remove-LDLCProgramSilently{throw 'Protected Office product reached the generic uninstaller'}
function Start-Process{throw 'Unexpected process launch'}
function Stop-Process{throw 'Unexpected process termination'}
function Invoke-WebRequest{throw 'Unexpected download'}
function Remove-AppxPackage{throw 'Unexpected package removal'}
foreach($program in $script:Inventory){Assert ($null -eq (Get-LDLCOemRemovalProfile $program)) ('Office was classified as an OEM/security removal target: '+$program.DisplayName)}
foreach($mode in @('All','Security','Oem')){
    Assert (@(Get-LDLCOemRemovalTargets -Mode $mode).Count -eq 0) ('The '+$mode+' selector targeted Office')
    $result=Remove-LDLCOemAndSecurityTrials -Mode $mode
    Assert ($result.Detected -eq 0 -and $result.Removed -eq 0 -and $result.Pending -eq 0) ('Office-only inventory was not left intact in '+$mode)
}
$script:Inventory+=@(
    [pscustomobject]@{DisplayName='Booking.com';Publisher='Booking';DisplayVersion='1';PSChildName='fixture-oem'},
    [pscustomobject]@{DisplayName='McAfee LiveSafe';Publisher='McAfee';DisplayVersion='1';PSChildName='fixture-mcafee'},
    [pscustomobject]@{DisplayName='Norton 360';Publisher='Norton';DisplayVersion='24';PSChildName='fixture-norton'}
)
Assert (@(Get-LDLCOemRemovalTargets -Mode Oem).Count -eq 1) 'Removing Office cleanup disabled ordinary OEM detection'
Assert (@(Get-LDLCOemRemovalTargets -Mode Security).Count -eq 2) 'Removing Office cleanup changed McAfee/Norton detection'
Assert (@(Get-LDLCOemRemovalTargets -Mode All).Count -eq 3) 'The mixed inventory selected an Office product or lost an existing cleanup target'
$delivered=0
if(-not $SourceOnly){
    $projectRoot=Split-Path -Parent ([IO.Path]::GetFullPath($ModuleRoot))
    $scripts=@(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'dist') -File -Filter '*.ps1')
    Assert ($scripts.Count -eq 2) 'Expected the main and worker delivered scripts'
    foreach($file in $scripts){Assert-NoOfficeRemoval (Read-Ast $file.FullName) $file.Name;$delivered++}
}
Write-Host ('::notice title=Office preservation regression::'+(@{Historical=$false;Result='passed';Assertions=$script:Checks;ProtectedProductNames=$officeNames.Count;CleanupModesTested=3;DeliveredScriptsVerified=$delivered;OfficeUninstallerExecuted=$false;AnyInstallerExecuted=$false;Mode='simulated installed products, real OEM selectors and no-target cleanup; actual source/delivery AST'}|ConvertTo-Json -Compress))
