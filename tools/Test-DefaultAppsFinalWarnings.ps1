#requires -Version 5.1
param([string]$ModuleRoot=(Join-Path (Split-Path -Parent $PSScriptRoot) 'modules'),[switch]$Historical)
$ErrorActionPreference='Stop'
. (Join-Path $ModuleRoot '05.Telemetry.ps1')
. (Join-Path $ModuleRoot '70.DefaultApps.ps1')
$script:Checks=0;$script:Infos=New-Object 'Collections.Generic.List[string]'
function Assert($Value,$Reason){$script:Checks++;if(-not $Value){throw $Reason}}
function Stop-IfRequested{if($script:Cancelled){throw 'LDLC_STOP_REQUESTED'}}
function Test-LDLCStopRequestError($ErrorRecord){$ErrorRecord.Exception.Message -match 'LDLC_STOP_REQUESTED'}
function Test-LDLCTelemetryDisabled{$false}
function Update-LDLCTelemetryRun{param($Message,[switch]$Force)}
function Get-LDLCEntryPointPath{'TEST-FINAL-DEFAULTS.ps1'}
function Write-Step($Text){}
function Write-Section($Text){}
function Write-Ok($Text){}
function Write-Info($Text){$script:Infos.Add($Text)}
function Write-Warn($Text){Add-LDLCTelemetryEvent -Severity warning -Message $Text}
function Get-LDLCDefaultAppsTick{$script:Tick}
function Start-Sleep([int]$Milliseconds,[int]$Seconds){$script:Tick+=$Milliseconds+$Seconds*1000}
function Enter-LDLCDefaultAppsCompact{}
function Exit-LDLCDefaultAppsCompact{}
function Set-LDLCDefaultAppsActionProgress{param($Application,$Association,$Stage)}
function Set-LDLCDefaultAppsCompactProgress{param($Percent,$Message,[switch]$Running,[switch]$Success,$ErrorApplication)}
function Close-LDLCDefaultAppsPage{}
function Get-LDLCDefaultAppAttemptRoutes{param($Application,$State);[pscustomobject]@{Kind='RegisteredPage';Uri='fixture'}}
function Invoke-LDLCDefaultAppAttempt{
    param($Application,$State,$Attempt,$Route)
    $script:UiAttempts++
    $error=New-Object InvalidOperationException('Observed UI action failed (fixture)')
    $error.Data['DefaultAppsStage']='Confirm';throw $error
}
function Set-LDLCTaskbarOptionsWithRegistry{param([switch]$DeferWidgetsFailureWarning);$true}
function Get-LDLCRegisteredPdfProgIds{param($Application);return @('Adobe.Pdf.Registered.Package')}
function Get-LDLCEffectiveAssociation{
    param($Association)
    $adobe=$Association -eq '.pdf';$ready=if($adobe){$script:AdobeReady}else{$script:ChromeReady}
    [pscustomobject]@{Association=$Association;ProgId=if($ready){if($adobe){$script:AdobeProgId}else{'ChromeHTML.Test'}}else{if($adobe){'MSEdgePDF'}else{'MSEdgeHTM'}};Executable=(Join-Path ([IO.Path]::GetTempPath()) $(if($ready){if($adobe){'AcroRd32.exe'}else{'chrome.exe'}}else{'msedge.exe'}));Error=if($script:ReadFailure){'Native effective association unavailable'}else{''}}
}
function Reset-Case{
    $script:Tick=0;$script:Cancelled=$false;$script:ReadFailure=$false;$script:UiAttempts=0
    $script:AdobeReady=$true;$script:ChromeReady=$true;$script:AdobeProgId='AcroExch.Document.DC'
    $script:LDLCTelemetryInitialized=$true;$script:LDLCTelemetryDisabled=$false;$script:LDLCTelemetrySending=$false
    $script:LDLCTelemetryComputerInfo=[pscustomobject]@{ComputerName='FIXTURE-FINAL-CHECK'}
    $script:LDLCTelemetryEvents=New-Object 'Collections.Generic.List[object]';$script:LDLCTelemetryEventKeys=@{}
    $script:LDLCDefaultAppsPendingChecks=$null;$script:LDLCDefaultAppsFinalAuditDone=$false
}
function Counts{Get-LDLCTelemetryCounts}
Reset-Case
$script:ChromeReady=$false
Invoke-LDLCChromeDefaultAppsSequence -DeferFinalValidation
Assert ($script:UiAttempts -gt 0) 'The failed initial Chrome attempt was not exercised'
if($Historical){Assert ((Counts).WarningCount -gt 0) 'Historical premature Chrome warning was not reproduced'}
else{Assert ((Counts).WarningCount -eq 0) 'A provisional failed action became a final warning'}
$script:ChromeReady=$true
if(-not $Historical){$result=Confirm-LDLCDefaultAppsFinalState;Assert $result.Confirmed 'Late effective Chrome success rejected'}
$status=Convert-LDLCTelemetryRunStatus -Status success -Counts (Counts) -Final
Assert ($status -eq $(if($Historical){'warning'}else{'success'})) 'Incorrect final dashboard status after late Chrome success'

if(-not $Historical){
    Reset-Case;$script:ChromeReady=$false
    Invoke-LDLCChromeDefaultAppsSequence -DeferFinalValidation
    $result=Confirm-LDLCDefaultAppsFinalState
    Assert (-not $result.Confirmed -and (Counts).WarningCount -eq 1) 'A real remaining Chrome failure was hidden or repeated'
    Assert (@($script:LDLCTelemetryEvents|Where-Object Message -match 'Chrome.*http').Count -eq 1) 'Real Chrome failure has no precise cause'
    [void](Confirm-LDLCDefaultAppsFinalState);Assert ((Counts).WarningCount -eq 1) 'Final check emitted the same warning twice'

    Reset-Case;$script:AdobeReady=$false
    Invoke-LDLCChromeDefaultAppsSequence -DeferFinalValidation
    $script:AdobeReady=$true
    $result=Confirm-LDLCDefaultAppsFinalState
    Assert ($result.Confirmed -and (Counts).WarningCount -eq 0) 'Adobe selected later still produced a false warning'

    Reset-Case;$script:AdobeReady=$false
    Invoke-LDLCChromeDefaultAppsSequence -DeferFinalValidation
    $result=Confirm-LDLCDefaultAppsFinalState
    Assert (-not $result.Confirmed -and (Counts).WarningCount -eq 1) 'PDF still assigned to Edge was reported as success'
    Assert (@($script:LDLCTelemetryEvents|Where-Object Message -match 'Adobe.*pdf=MSEdgePDF').Count -eq 1) 'Real PDF mismatch is not explicit'

    Reset-Case
    Add-LDLCTelemetryEvent -Severity warning -Message 'GPU installation actually failed (fixture)'
    Invoke-LDLCChromeDefaultAppsSequence -DeferFinalValidation
    [void](Confirm-LDLCDefaultAppsFinalState)
    Assert ((Counts).WarningCount -eq 1 -and $script:LDLCTelemetryEvents[0].Message -match 'GPU') 'An unrelated real warning was erased'

    Reset-Case
    Invoke-LDLCChromeDefaultAppsSequence -DeferFinalValidation
    $script:ReadFailure=$true
    $result=Confirm-LDLCDefaultAppsFinalState
    Assert (-not $result.Confirmed -and (Counts).WarningCount -eq 2) 'An unreadable Windows association was falsely accepted'

    Reset-Case
    Invoke-LDLCChromeDefaultAppsSequence -DeferFinalValidation
    $script:Cancelled=$true;$stopped=$false
    try{[void](Confirm-LDLCDefaultAppsFinalState)}catch{$stopped=Test-LDLCStopRequestError $_}
    Assert $stopped 'Cancellation was swallowed by the final audit'
    Assert (-not $script:LDLCDefaultAppsFinalAuditDone) 'An interrupted final audit was marked complete'
    $script:Cancelled=$false

    Reset-Case
    Invoke-LDLCChromeDefaultAppsSequence -DeferFinalValidation
    Assert ($script:UiAttempts -eq 0) 'Existing valid defaults were reconfigured'
    [void](Confirm-LDLCDefaultAppsFinalState)
    Assert ($script:UiAttempts -eq 0 -and (Counts).WarningCount -eq 0) 'Read-only final verification changed current defaults'
}

foreach($id in @('AcroExch.Document.DC','Acrobat.Document.DC','Applications\Acrobat.exe','Applications\AcroRd32.exe','Adobe.Pdf.Registered.Package')){
    $state=[pscustomobject]@{ProgId=$id;Executable=(Join-Path ([IO.Path]::GetTempPath()) 'AcroRd32.exe');Error=''}
    if($id -eq 'Applications\Acrobat.exe'){$state.Executable=Join-Path ([IO.Path]::GetTempPath()) 'Acrobat.exe'}
    $expected=(-not $Historical -or $id -match '^(AcroExch|Acrobat)\.Document')
    Assert ((Test-LDLCEffectiveAssociationTarget $state Adobe) -eq $expected) ('Unexpected Adobe detection for '+$id)
}
foreach($bad in @(
    @{ProgId='AcroExch.Document.DC';Executable='msedge.exe';Error=''},
    @{ProgId='MSEdgePDF';Executable='Acrobat.exe';Error=''},
    @{ProgId='Unknown.PDF';Executable='AcroRd32.exe';Error=''},
    @{ProgId='AcroExch.Document.DC';Executable='Acrobat.exe';Error='Read denied'}
)){
    $bad.Executable=Join-Path ([IO.Path]::GetTempPath()) $bad.Executable
    Assert (-not (Test-LDLCEffectiveAssociationTarget ([pscustomobject]$bad) Adobe)) 'An invalid/unreadable/non-Adobe effective handler was accepted'
}

# The command mocks below model only policy data and denied writes, never change
# the real taskbar or policy keys on a runner.
$script:Build=26100;$script:Da=1;$script:Policy=@{};$script:DenyUserWrite=$false
function Get-LDLCWindowsBuildNumber{$script:Build}
function Get-LDLCTaskbarAdvancedValue{param($Name);if($Name -eq 'TaskbarDa'){$script:Da}}
function Get-LDLCTaskbarPolicyValue{param($Path,$Name);$script:Policy[$Path+'\'+$Name]}
function Set-LDLCTaskbarAdvancedValue{param($Name,$Value);if($script:DenyUserWrite){throw 'Protected TaskbarDa (fixture)'};$script:Da=$Value}
function Set-LDLCTaskbarPolicyValue{param($Path,$Name,$Value);$script:Policy[$Path+'\'+$Name]=$Value}
$valid='HKLM:\SOFTWARE\Policies\Microsoft\Dsh\AllowNewsAndInterests'
$script:Policy[$valid]=0
$state=Get-LDLCWidgetsTaskbarState
Assert ($state.PolicyDisabled -and $state.Disabled -eq (-not $Historical)) 'Supported disabled Widgets policy was ignored'
if(-not $Historical){
    foreach($fake in @('HKCU:\Software\Policies\Microsoft\Dsh\AllowNewsAndInterests','HKLM:\SOFTWARE\Policies\Microsoft\Dsh\AllowWidgets','HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds\EnableFeeds')){
        $script:Policy=@{};$script:Policy[$fake]=0
        Assert (-not (Get-LDLCWidgetsTaskbarState).Disabled) ('Unsupported Windows 11 policy falsely disabled Widgets: '+$fake)
    }
    Reset-Case;$script:Policy=@{};$script:Da=1;$script:DenyUserWrite=$true
    $changed=Disable-LDLCWidgetsTaskbarOption
    Assert ($changed -and (Get-LDLCWidgetsTaskbarState).Disabled -and (Counts).WarningCount -eq 0) 'Protected TaskbarDa invalidated successful supported policy'
    $script:Policy=@{};$script:Da=0
    Assert (Get-LDLCWidgetsTaskbarState).Disabled 'Existing disabled user setting rejected'
    $script:Da=1;$script:Build=19045;$script:Policy=@{'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds\EnableFeeds'=0}
    Assert (Get-LDLCWidgetsTaskbarState).Disabled 'Supported Windows 10 feeds policy rejected'
    $script:Build=26100;$script:Policy=@{};$script:Da=1
    Reset-Case;$script:LDLCDefaultAppsPendingChecks=@{Widgets=$true}
    $result=Confirm-LDLCDefaultAppsFinalState
    Assert (-not $result.Confirmed -and (Counts).WarningCount -eq 1) 'Still enabled Widgets without supported disable policy were silently accepted'
}
Write-Host ('::notice title=Final default warning regression::'+(@{Historical=[bool]$Historical;Assertions=$script:Checks;Result='passed';Mode='simulated association and policy states, actual final audit and telemetry status code';ProductionConfigurationChanged=$false}|ConvertTo-Json -Compress))
