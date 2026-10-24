#requires -Version 5.1
param([string]$ModuleRoot=(Join-Path (Split-Path -Parent $PSScriptRoot) 'modules'))
$ErrorActionPreference='Stop'
. (Join-Path $ModuleRoot '05.Telemetry.ps1')
. (Join-Path $ModuleRoot '70.DefaultApps.ps1')
$script:Checks=0
$script:Information=New-Object 'Collections.Generic.List[string]'
function Assert($Value,$Reason){$script:Checks++;if(-not $Value){throw $Reason}}
function Stop-IfRequested{if($script:Cancelled){throw 'LDLC_STOP_REQUESTED'}}
function Test-LDLCStopRequestError($ErrorRecord){$ErrorRecord.Exception.Message -eq 'LDLC_STOP_REQUESTED'}
function Test-LDLCTelemetryDisabled{$false}
function Update-LDLCTelemetryRun{param($Message,[switch]$Force)}
function Get-LDLCEntryPointPath{'FIXTURE-NONBLOCKING.ps1'}
function Write-Info($Text){$script:Information.Add($Text)}
function Write-Warn($Text){Add-LDLCTelemetryEvent -Severity warning -Message $Text}
function Write-Step($Text){}
function Write-Section($Text){}
function Write-Ok($Text){}
function Enter-LDLCDefaultAppsCompact{}
function Exit-LDLCDefaultAppsCompact{}
function Close-LDLCDefaultAppsPage{}
function Get-LDLCDefaultAppAttemptRoutes{param($Application,$State);return @()}
function Get-LDLCDefaultAppState{
    param($Application)
    if($script:ReadFailure){throw 'Windows association read denied (fixture)'}
    [pscustomobject]@{Confirmed=$script:ChromeReady;Missing=@('http','.html');Associations=@([pscustomobject]@{Association='.html';ProgId='MSEdgeHTM';Executable='msedge.exe';Error=''})}
}
function Wait-LDLCDefaultAppConfirmation{param($Application,$TimeoutMilliseconds);$state=Get-LDLCDefaultAppState $Application;[pscustomobject]@{Confirmed=$state.Confirmed;State=$state}}
function Reset-Case{
    $script:Cancelled=$false;$script:ChromeReady=$false;$script:ReadFailure=$false
    $script:Information.Clear()
    $script:LDLCTelemetryInitialized=$true;$script:LDLCTelemetryDisabled=$false;$script:LDLCTelemetrySending=$false
    $script:LDLCTelemetryComputerInfo=[pscustomobject]@{ComputerName='FIXTURE-NONBLOCKING'}
    $script:LDLCTelemetryEvents=New-Object 'Collections.Generic.List[object]';$script:LDLCTelemetryEventKeys=@{}
    $script:LDLCDefaultAppsPendingChecks=$null;$script:LDLCDefaultAppsFinalAuditDone=$false
}
Reset-Case
$script:ChromeReady=$true
Assert (Set-LDLCChromeDefaultBrowserWithUiAutomation) 'An actual confirmed Chrome state must remain successful'
Assert ((Get-LDLCTelemetryCounts).WarningCount -eq 0) 'Already configured Chrome produced a warning'
Reset-Case
Assert (-not (Set-LDLCChromeDefaultBrowserWithUiAutomation)) 'Diagnostic-only must not invent a configured Chrome state'
Assert ((Get-LDLCTelemetryCounts).WarningCount -eq 0) 'An unconfirmed Chrome preference became a blocking warning'
Assert (($script:Information -join ' ') -match 'Chrome non defini') 'Keep the precise Chrome diagnosis in the journal'
Reset-Case;$script:ReadFailure=$true
Assert (-not (Set-LDLCChromeDefaultBrowserWithUiAutomation)) 'An unreadable Chrome state was reported as confirmed'
Assert ((Get-LDLCTelemetryCounts).WarningCount -eq 0 -and ($script:Information -join ' ') -match 'read denied') 'Unreadable preference must stay informational with its cause'
Reset-Case;$script:Cancelled=$true;$stopped=$false
try{[void](Set-LDLCChromeDefaultBrowserWithUiAutomation)}catch{$stopped=Test-LDLCStopRequestError $_}
Assert $stopped 'The requested warning removal swallowed cancellation'
Reset-Case
Add-LDLCTelemetryEvent -Severity error -Message 'Chrome installer failed, code 1603 (fixture)'
[void](Set-LDLCChromeDefaultBrowserWithUiAutomation)
$counts=Get-LDLCTelemetryCounts
Assert ($counts.ErrorCount -eq 1 -and $counts.WarningCount -eq 0) 'A real installation failure was erased'
Assert ((Convert-LDLCTelemetryRunStatus -Status success -Counts $counts -Final) -ne 'success') 'A real installation failure became a validated success'
if(Get-Command Confirm-LDLCDefaultAppsFinalState -ErrorAction SilentlyContinue){
    Reset-Case;$script:LDLCDefaultAppsPendingChecks=@{Chrome=$true}
    $audit=Confirm-LDLCDefaultAppsFinalState
    Assert ($audit.Confirmed -and -not $audit.States.Chrome.Confirmed -and $audit.Failures.Count -eq 0) 'Final Chrome policy must be nonblocking while preserving the real unconfirmed state'
    Assert ((Get-LDLCTelemetryCounts).WarningCount -eq 0 -and ($script:Information -join ' ') -match 'MSEdgeHTM') 'Final association details disappeared or became a warning'
}

# Exercise the real ADDON bootstrap function with transport/installer doubles.
# No network, package installer, or real software installation is performed.
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $ModuleRoot '30.Applications.ps1'),[ref]$null,[ref]$null)
$bootstrap=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Install-ChocolateyIfNeeded'},$true)
$bootstrapCases=0
if($bootstrap){
    . ([scriptblock]::Create($bootstrap.Extent.Text))
    $savedPath=$env:Path;$savedProtocol=[Net.ServicePointManager]::SecurityProtocol
    $script:ClientDouble=[pscustomobject]@{}
    $script:ClientDouble|Add-Member ScriptMethod DownloadString {param($Uri);if($Uri -cne 'https://community.chocolatey.org/install.ps1'){throw 'Unexpected source'};return 'fixture-bootstrap'}
    function New-Object{
        param([Parameter(Position=0)][string]$TypeName,[Parameter(Position=1)][object[]]$ArgumentList)
        if($TypeName -eq 'System.Net.WebClient'){return $script:ClientDouble}
        Microsoft.PowerShell.Utility\New-Object @PSBoundParameters
    }
    function Test-WingetAvailable{$false}
    function Test-ChocoAvailable{param([switch]$Refresh);$script:ChocoAvailable}
    function Invoke-Expression{
        param([string]$Command)
        Assert ($Command -ceq 'fixture-bootstrap') 'Only the bootstrap double may be executed'
        if($script:TransportFailure){throw 'Chocolatey download interrupted (fixture)'}
        $script:ChocoAvailable=$script:BootstrapSucceeds
    }
    try{
        foreach($case in @('cold-success','already-present','download-failure','not-installed')){
            Reset-Case;$bootstrapCases++
            $script:ChocoAvailable=$case -eq 'already-present'
            $script:TransportFailure=$case -eq 'download-failure'
            $script:BootstrapSucceeds=$case -eq 'cold-success'
            $result=Install-ChocolateyIfNeeded -Force
            $counts=Get-LDLCTelemetryCounts
            if($case -in @('cold-success','already-present')){
                Assert ($result -and $counts.WarningCount -eq 0) 'Normal Chocolatey initialization must not create a warning'
            }else{
                Assert (-not $result -and $counts.WarningCount -gt 0) 'A real Chocolatey failure was hidden'
            }
        }
    }finally{$env:Path=$savedPath;[Net.ServicePointManager]::SecurityProtocol=$savedProtocol}
}
Write-Host ('::notice title=Requested nonblocking diagnostics::'+(@{Result='passed';Assertions=$script:Checks;ChocolateyCases=$bootstrapCases;ChromePreferenceDiagnosticOnly=$true;ActualConfigurationNotInvented=$true;RealInstallationErrorsPreserved=$true;Mode='simulated association, transport and package installer; actual application telemetry policy';HardwareInstallersExecuted=$false}|ConvertTo-Json -Compress))
