#requires -Version 5.1
param([string]$ModuleRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'modules'))
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $ModuleRoot '70.DefaultApps.ps1')
. (Join-Path $ModuleRoot '72.ChromeTaskbar.ps1')
$script:realState = ${function:Get-LDLCChromeTaskbarPinState}
$script:checks = 0; $script:cases = 0
function Assert($Value, $Reason) { $script:checks++; if (-not $Value) { throw $Reason } }
function Stop-IfRequested { if ($script:cancel) { throw [OperationCanceledException]::new('test stop') } }
function Test-LDLCStopRequestError($ErrorRecord) { return $ErrorRecord.Exception -is [OperationCanceledException] }
function Write-Section($Text) { }
function Write-ProgressFile($Percent, $Text) { }
function Write-Info($Text) { }
function Write-Ok($Text) { $script:success++ }
function Write-Warn($Text) { $script:warnings += $Text }
function Get-LDLCDefaultAppsTick { return $script:tick }
function Start-Sleep([int]$Milliseconds) { $script:tick += $Milliseconds }
function Get-LDLCChromeExecutablePath { if ($script:missing) { return $null }; return 'C:\Fixture\chrome.exe' }
function Get-LDLCChromeTaskbarPinState {
    param($ChromeExecutable)
    if ($script:readFailure) { throw 'simulated Shell read failure' }
    if ($script:pinAt -gt 0 -and $script:tick -ge $script:pinAt) { $script:pinned=$true }
    return [pscustomobject]@{ Pinned = $script:pinned }
}
function Invoke-LDLCChromeShellPin {
    param($ChromeExecutable)
    $script:shellCalls++
    if ($script:shellWorks) { $script:pinned = $true }
    if ($script:shellDelayed) { $script:pinAt=200 }
    return $script:verbAvailable
}
function Invoke-LDLCChromeTaskbarContextAction {
    param($ChromeExecutable)
    $script:uiCalls++
    if ($script:uiFailure) { throw 'Windows pin command unavailable or denied' }
    if ($script:uiWorks) { $script:pinned = $true }
    return [pscustomobject]@{ ObservedPinned = $script:menuAlreadyPinned; Invoked = $true }
}
function Reset-Case {
    $script:cases++; $script:tick = 0; $script:pinned = $false; $script:cancel = $false
    $script:missing = $false; $script:readFailure = $false; $script:shellWorks = $false
    $script:verbAvailable = $false; $script:uiWorks = $false; $script:uiFailure = $false
    $script:menuAlreadyPinned = $false; $script:shellCalls = 0; $script:uiCalls = 0; $script:success = 0; $script:warnings = @()
    $script:pinAt=0; $script:shellDelayed=$false
}
foreach ($label in @('&Pin to taskbar', ('&' + [char]0xC9 + 'pingler ' + [char]0xE0 + ' la barre des t' + [char]0xE2 + 'ches'))) { Assert (Test-LDLCChromeTaskbarVerb $label) 'Recognize Windows pin command in English and French.' }
foreach ($label in @('&Unpin from taskbar', ('D&' + [char]0xE9 + 'tacher de la barre des t' + [char]0xE2 + 'ches'))) { Assert (Test-LDLCChromeTaskbarVerb $label -Unpin) 'Recognize Windows unpin command.' }
Assert (-not (Test-LDLCChromeTaskbarVerb 'Pin to Start')) 'Never invoke Start pin or Quick Access instead of taskbar.'
Reset-Case; $script:pinned = $true
Assert (Invoke-LDLCChromeTaskbarPinBeforeWindowsUpdate) 'Already pinned must succeed immediately.'
Assert ($shellCalls -eq 0 -and $uiCalls -eq 0 -and $tick -eq 0 -and $warnings.Count -eq 0) 'Already pinned must not restart Explorer or open UI.'
Reset-Case; $script:verbAvailable = $true; $script:shellWorks = $true
Assert (Invoke-LDLCChromeTaskbarPinBeforeWindowsUpdate) 'Working exposed Shell verb must be verified.'
Assert ($uiCalls -eq 0 -and $success -eq 0) 'No fallback UI after verified pin.'
Reset-Case; $script:verbAvailable = $true; $script:uiWorks = $true
Assert (Invoke-LDLCChromeTaskbarPinBeforeWindowsUpdate) 'Silent no-effect Shell command must fall back to real UI action.'
Assert ($uiCalls -eq 1 -and $warnings.Count -eq 0) 'Do not report an intermediate false warning.'
Reset-Case; $script:uiWorks = $true
Assert (Invoke-LDLCChromeTaskbarPinBeforeWindowsUpdate) 'Missing Shell verb must use the scoped Explorer menu.'
Reset-Case; $script:menuAlreadyPinned = $true
Assert (Invoke-LDLCChromeTaskbarPinBeforeWindowsUpdate) 'Scoped Windows Unpin menu is proof of an existing pin.'
Reset-Case
Assert (-not (Invoke-LDLCChromeTaskbarPinBeforeWindowsUpdate)) 'A no-effect pin command must not be reported as successful.'
Assert ($warnings.Count -eq 1 -and $tick -le 1000) 'Surface a short precise warning when Windows does not apply the pin.'
Reset-Case; $script:verbAvailable=$true; $script:shellDelayed=$true
Assert (Invoke-LDLCChromeTaskbarPinBeforeWindowsUpdate) 'Allow Windows to apply an asynchronous Shell pin.'
Assert ($uiCalls -eq 0 -and $tick -eq 200) 'Do not race the asynchronous Shell command by opening another context menu immediately.'
Reset-Case; $script:uiFailure = $true
Assert (-not (Invoke-LDLCChromeTaskbarPinBeforeWindowsUpdate)) 'Denied pin must remain a precise warning.'
Reset-Case; $script:missing = $true
Assert (-not (Invoke-LDLCChromeTaskbarPinBeforeWindowsUpdate)) 'Missing browser must not create an invalid layout.'
Assert ($shellCalls -eq 0 -and $uiCalls -eq 0) 'No attempt with missing Chrome.'
Reset-Case; $script:readFailure = $true
Assert (-not (Invoke-LDLCChromeTaskbarPinBeforeWindowsUpdate)) 'Unreadable pin state must not mean success.'
Reset-Case; $script:cancel = $true; $stopped = $false
try { Invoke-LDLCChromeTaskbarPinBeforeWindowsUpdate | Out-Null } catch { $stopped = Test-LDLCStopRequestError $_ }
Assert ($stopped) 'Cancellation must propagate.'
$native = 'not executed on Linux'
if ($env:OS -eq 'Windows_NT') {
    # Native WScript links in an isolated folder; never alter the real taskbar.
    $directory = Join-Path ([IO.Path]::GetTempPath()) ('Chrome-Pin-Read-' + [guid]::NewGuid().ToString('N'))
    try {
        [void](New-Item -ItemType Directory -Path $directory)
        $exe = Join-Path $directory 'chrome.exe'; [IO.File]::WriteAllBytes($exe, (New-Object byte[] 128))
        $other = Join-Path $directory 'msedge.exe'; [IO.File]::WriteAllBytes($other, (New-Object byte[] 128))
        function Get-LDLCChromeShellPinItem { param($ChromeExecutable) $item = [pscustomobject]@{}; $item | Add-Member ScriptMethod Verbs { return @() }; return $item }
        $ws = New-Object -ComObject WScript.Shell
        $linkPath = Join-Path $directory 'Chrome.lnk'; $link = $ws.CreateShortcut($linkPath); $link.TargetPath = $other; $link.Save()
        Assert (-not (& $script:realState -ChromeExecutable $exe -PinDirectory $directory).Pinned) 'A shortcut named Chrome pointing to Edge must not confirm a pin.'
        $link.TargetPath = $exe; $link.Save()
        Assert (& $script:realState -ChromeExecutable $exe -PinDirectory $directory).Pinned 'Read actual COM shortcut target without changing real pins.'
        $link.TargetPath=$other; $link.Save()
        Assert ((Get-LDLCChromeTaskbarLaunchPath -ChromeExecutable $exe -ShortcutRoots @($directory)) -eq $exe) 'Do not select a shortcut named Chrome that targets another application.'
        $link.TargetPath=$exe; $link.Save()
        Assert ((Get-LDLCChromeTaskbarLaunchPath -ChromeExecutable $exe -ShortcutRoots @($directory)) -eq $linkPath) 'Prefer the verified Chrome Start Menu shortcut to the raw executable for Windows pin actions.'
        $native = 'real WScript shortcut write/read in isolated folder; no taskbar changed'
    } finally { if (Test-Path -LiteralPath $directory) { Remove-Item -LiteralPath $directory -Recurse -Force } }
}
Write-Host ('::notice title=Chrome taskbar pin::' + (@{ Cases = $cases; Assertions = $checks; Failures = 0; Mode = 'controller and Windows actions simulated'; NativeShortcutCheck = $native; ActualUserTaskbarChanged = $false } | ConvertTo-Json -Compress))
