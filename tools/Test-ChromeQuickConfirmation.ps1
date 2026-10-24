#requires -Version 5.1
param([string]$ModuleRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'modules'))
$ErrorActionPreference = 'Stop'
. (Join-Path $ModuleRoot '70.DefaultApps.ps1')
$script:realAssociation = ${function:Get-LDLCEffectiveAssociation}
$script:checks = 0; $script:cases = 0
function Assert($Value, $Reason) { $script:checks++; if (-not $Value) { throw $Reason } }
function Stop-IfRequested { if ($script:cancel) { throw [OperationCanceledException]::new('test stop') } }
function Test-LDLCStopRequestError($ErrorRecord) { return $ErrorRecord.Exception -is [OperationCanceledException] }
function Write-Step($Text) { }
function Write-Section($Text) { }
function Write-Info($Text) { }
function Write-Ok($Text) { }
function Write-Warn($Text) { $script:warnings += $Text }
function Get-LDLCDefaultAppsTick { return $script:tick }
function Start-Sleep([int]$Milliseconds) { $script:tick += $Milliseconds }
function Close-LDLCDefaultAppsPage { $script:closed++ }
function Set-LDLCTaskbarOptionsWithRegistry { return $true }
function Get-LDLCDefaultAppsVisibleChoice { return $null }
function Get-LDLCDefaultAppUris { return @('ms-settings:defaultapps?registeredAppUser=ChromeFixture', 'ms-settings:defaultapps?registeredAppMachine=ChromeFixture') }
function Open-LDLCDefaultAppPage($Uri, $Application) { $script:actions += 'Page' }
function Invoke-LDLCDefaultAppsUiAction {
    param($Kind, $Association, $Application, $TimeoutMilliseconds, [switch]$ObservedBrowserClick)
    $script:actions += $Kind
    if ($script:allUiFailure) { throw 'simulated unavailable UI action' }
    if ($Kind -eq 'Confirm') { $script:htmlReady = $true }
    if ($Kind -eq 'BrowserDefault') {
        Assert ($TimeoutMilliseconds -le 5000) 'Browser button discovery must have a bounded budget.'
        if ($script:failFirstGlobal) { $script:failFirstGlobal = $false; throw 'simulated unavailable global action' }
        if ($ObservedBrowserClick) { $script:observedClicks++ }
        if (-not $script:ignoreGlobal -or ($ObservedBrowserClick -and $script:physicalWorks)) { $script:chromeReady = $true }
    }
    return $true
}
function Complete-LDLCDefaultAppsChoice($Association, $Application, $TimeoutMilliseconds) {
    $script:actions += 'Confirm'
    if ($script:confirmNoEffect) { throw 'Windows did not apply this association' }
    $script:associationReady[$Association]=$true
}
function Reset-Case {
    $script:cases++; $script:tick = 0; $script:cancel = $false; $script:closed = 0
    $script:warnings = @(); $script:actions = @(); $script:chromeReady = $true; $script:adobeReady = $true
    $script:htmlReady = $false; $script:failFirstGlobal = $false; $script:ignoreGlobal = $false
    $script:physicalWorks = $false; $script:observedClicks = 0; $script:allUiFailure = $false
    $script:associationReady=@{}; $script:confirmNoEffect=$false
    $script:ProgressFile = $null; $script:LDLCDefaultAppsCompactDepth = 0; $script:LDLCDefaultAppsCompactPath = $null
    $script:LDLCDefaultAppsCompactProgress = $null
}
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('Chrome-Confirm-' + [guid]::NewGuid().ToString('N'))
$oldUi = $env:LDLC_DEFAULT_APPS_UI
try {
    [void](New-Item -ItemType Directory -Path $fixture)
    $chromePath = Join-Path $fixture 'chrome.exe'; [IO.File]::WriteAllText($chromePath, 'fixture, never executed')
    # OS API shim only: exercise the production fallback and path normalization.
    Add-Type @'
using System;
public static class LDLCDefaultAppsNative {
    public static string Id = "Applications\\chrome.exe";
    public static string PathValue;
    public static bool FailDirect = true;
    public static bool Race;
    public static int Reads;
    public static int FixedReads;
    public static string CurrentDefault(string association) { Reads++; return Race && Reads % 2 == 0 ? "MSEdgeHTM" : Id; }
    public static string Executable(string association) { if (FailDirect) throw new Exception("simulated protocol resolution failure"); return PathValue; }
    public static string ExecutableForProgId(string progId) { FixedReads++; return PathValue; }
}
'@
    [LDLCDefaultAppsNative]::PathValue = '"' + $chromePath + '"'
    Reset-Case
    $association = & $script:realAssociation -Association 'https'
    Assert (-not $association.Error -and $association.Executable -eq $chromePath -and [LDLCDefaultAppsNative]::FixedReads -eq 1) 'Resolve the Windows-reported ProgID when protocol executable resolution fails, and normalize quoted paths.'
    Assert (Test-LDLCEffectiveAssociationTarget -State $association -Application Chrome) 'Applications\chrome.exe is a valid Windows effective Chrome registration.'
    [LDLCDefaultAppsNative]::Race = $true; [LDLCDefaultAppsNative]::Reads = 0
    $association = & $script:realAssociation -Association 'https'
    Assert ([bool]$association.Error) 'Changing Windows association must not be confirmed.'
    Assert (-not (Test-LDLCEffectiveAssociationTarget -State $association -Application Chrome)) 'A transient or failed read must not mean success.'
    function Get-LDLCEffectiveAssociation($Association) {
        $isPdf = $Association -eq '.pdf'
        $ready = if ($isPdf) { $script:adobeReady } else { $script:chromeReady -or $script:associationReady.ContainsKey($Association) }
        $program = if (-not $ready) { 'msedge.exe' } elseif ($isPdf) { 'Acrobat.exe' } else { 'chrome.exe' }
        $id = if (-not $ready) { 'MSEdgeHTM' } elseif ($isPdf) { 'AcroExch.Document.DC' } else { 'ChromeHTML.Fixture' }
        [pscustomobject]@{ Association = $Association; ProgId = $id; Executable = (Join-Path $fixture $program); Error = '' }
    }
    $env:LDLC_DEFAULT_APPS_UI = '0'
    Reset-Case
    Assert (Invoke-LDLCDefaultAppConfiguration Chrome) 'Already-default Chrome must succeed without opening Settings.'
    Assert ($actions.Count -eq 0 -and $closed -eq 0 -and $tick -le 500) 'Already-default Chrome must be confirmed quickly without window changes.'
    Reset-Case; Invoke-LDLCChromeDefaultAppsSequence
    $readyDuration = $tick
    Assert ($script:LDLCDefaultAppsCompactProgress.Success -and $warnings.Count -eq 0 -and $tick -le 1500) 'Two already-correct applications must avoid repeated twelve-second waits and false warnings.'
    Reset-Case; $script:chromeReady = $false
    Assert (Invoke-LDLCDefaultAppConfiguration Chrome) 'The browser-wide action must configure Chrome.'
    Assert (($actions -join ',') -eq 'Page,BrowserDefault') 'Click the exact global browser action before any HTML picker.'
    Assert ($observedClicks -eq 0) 'A working UIA Invoke must not be replaced by an unnecessary physical click.'
    Assert ((Get-LDLCDefaultAppState Chrome).Associations.Count -eq 4) 'Keep all four real effective associations in the verification.'
    Reset-Case; $script:chromeReady = $false; $script:failFirstGlobal = $true
    Assert (Invoke-LDLCDefaultAppConfiguration Chrome) 'Keep the HTML picker fallback when the global action is unavailable.'
    Assert ($actions -contains 'Association' -and $associationReady.Count -eq 4 -and $warnings.Count -eq 0) 'Fallback without a global button must configure HTTP, HTTPS, HTM and HTML, including Windows 10 style pages.'
    Reset-Case; $script:chromeReady = $false; $script:ignoreGlobal = $true; $script:physicalWorks = $true
    Assert (Invoke-LDLCDefaultAppConfiguration Chrome) 'Use the exact guarded observed button after a no-effect UIA activation.'
    Assert ($observedClicks -eq 1 -and $warnings.Count -eq 0) 'One observed activation must not create an association-confirmation warning.'
    Reset-Case; $script:chromeReady = $false; $script:ignoreGlobal = $true; $script:confirmNoEffect=$true
    Assert (-not (Invoke-LDLCDefaultAppConfiguration Chrome)) 'An invoked button with unchanged associations must never report Chrome configured.'
    Assert ($warnings.Count -eq 0 -and $tick -le 2750 -and $observedClicks -eq 1) 'Keep verification bounded, allow one final stabilization read and surface the real unchanged state.'
    Reset-Case; $script:chromeReady = $false; $script:ignoreGlobal = $true; $script:allUiFailure = $true
    Invoke-LDLCChromeDefaultAppsSequence
    Assert ($warnings.Count -eq 0 -and -not $script:LDLCDefaultAppsCompactProgress.Success) 'An unavailable Chrome preference stays informational without claiming it was configured.'
    Reset-Case; $script:chromeReady = $false
    $script:savedWait = ${function:Wait-LDLCDefaultAppConfirmation}
    function Wait-LDLCDefaultAppConfirmation {
        param($Application,$TimeoutMilliseconds)
        Assert ($Application -ne 'Chrome' -or $TimeoutMilliseconds -le 1500) 'No repeated long Chrome confirmation waits.'
        return (& $script:savedWait -Application $Application -TimeoutMilliseconds $TimeoutMilliseconds)
    }
    Assert (Invoke-LDLCDefaultAppConfiguration Chrome) 'Legacy entry point must use the same short verified action.'
    Set-Item Function:Wait-LDLCDefaultAppConfirmation $script:savedWait
    Reset-Case; $script:cancel = $true; $stopped = $false
    try { Invoke-LDLCDefaultAppConfiguration Chrome | Out-Null } catch { $stopped = Test-LDLCStopRequestError $_ }
    Assert ($stopped -and $actions.Count -eq 0) 'Cancellation must propagate before any UI action.'
    Write-Host ('::notice title=Chrome default actions::' + (@{ Cases = $cases; Assertions = $checks; Failures = 0; AlreadyConfiguredMilliseconds = $readyDuration; Mode = 'simulated Windows associations, UI actions and clock'; RealBrowserDefaultsChanged = $false } | ConvertTo-Json -Compress))
} finally {
    $env:LDLC_DEFAULT_APPS_UI = $oldUi
    if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force }
}
