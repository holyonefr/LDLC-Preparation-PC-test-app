#requires -Version 5.1
param([string]$ModuleRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'modules'))
$ErrorActionPreference = 'Stop'
. (Join-Path $ModuleRoot '52.SecurityUninstall.ps1')
$realLaunch = ${function:Start-LDLCSecurityInteractiveUninstaller}
$checks = 0; $cases = 0
function Assert($Value, $Reason) { $script:checks++; if (-not $Value) { throw $Reason } }
function Stop-IfRequested { if ($script:cancel -or ($script:cancelAt -and $script:tick -ge $script:cancelAt)) { throw [OperationCanceledException]::new('test stop') } }
function Write-Section($Text) { }
function Write-Step($Text) { }
function Write-Info($Text) { }
function Write-ProgressFile($Percent, $Text) { $script:progress = $Text }
function Clear-LDLCDetectionCaches { }
function Get-LDLCOemRemovalTargets { return $script:targets }
function Test-LDLCProgramStillInstalled($Program) {
    if ($script:nativeDone) { return -not [IO.File]::Exists($script:nativeDone) }
    return ($script:tick -lt $script:removedAt)
}
function Start-Sleep([int]$Milliseconds) { $script:tick += $Milliseconds }
function Start-LDLCSecurityInteractiveUninstaller($Command) {
    $script:launches++; $script:lastCommand = $Command
    $p = [pscustomobject]@{ HasExited = $script:exited; ExitCode = $script:exitCode }
    $p | Add-Member ScriptMethod Refresh { if ($script:tick -ge $script:exitAt) { $this.HasExited = $true } }
    $p | Add-Member ScriptMethod Dispose { }
    return $p
}
function Reset-Case {
    $script:cases++; $script:tick = 0; $script:removedAt = 1000; $script:cancel = $false; $script:cancelAt = 0
    $script:exited = $false; $script:exitCode = 0; $script:exitAt = 1000; $script:launches = 0; $script:targets = @(); $script:nativeDone = $null
}
$directory = Join-Path ([IO.Path]::GetTempPath()) ('Security fixture ' + [guid]::NewGuid().ToString('N'))
$oldRoot = $env:SystemRoot
$native = 'not executed: Windows required'
try {
    [void](New-Item -ItemType Directory -Path $directory)
    $fake = Join-Path $directory 'uninstaller.exe'; [IO.File]::WriteAllText($fake, 'fixture, never executed')
    $program = [pscustomobject]@{ DisplayName = 'McAfee fixture'; UninstallString = ('"'+$fake+'" /remove /quiet /S'); QuietUninstallString = 'must never be used' }
    Reset-Case
    $command = Get-LDLCSecurityInteractiveCommand $program
    Assert ($command.FilePath -eq $fake -and $command.Arguments -eq '/remove') 'Use the registered visible uninstaller, preserving remove and dropping silent flags.'
    Reset-Case; $program.UninstallString = $fake + ' /remove "keep quoted argument"'
    $command = Get-LDLCSecurityInteractiveCommand $program
    Assert ($command.FilePath -eq $fake -and $command.Arguments -eq '/remove "keep quoted argument"') 'Unquoted executable path with spaces must remain one file; retain quoted vendor arguments.'
    Reset-Case
    $env:SystemRoot = $directory; [void](New-Item -ItemType Directory -Path (Join-Path $directory 'System32'))
    [IO.File]::WriteAllText((Join-Path $directory 'System32/msiexec.exe'), 'fixture, never executed')
    $program.UninstallString = 'MsiExec.exe /I{11111111-1111-1111-1111-111111111111} /qn'
    $command = Get-LDLCSecurityInteractiveCommand $program
    Assert ($command.Arguments -match '^/X\{' -and $command.Arguments -notmatch '/qn' -and $command.Arguments -match '/norestart') 'MSI must open uninstall UI, not repair or silent mode.'
    $env:SystemRoot = $oldRoot
    foreach ($bad in @('', 'ms-settings:appsfeatures', '"C:\missing\uninstall.exe" /remove')) {
        Reset-Case; $program.UninstallString = $bad; $failed = $false
        try { Get-LDLCSecurityInteractiveCommand $program | Out-Null } catch { $failed = $true }
        Assert ($failed -and $launches -eq 0) 'No installed-apps fallback or guessed quiet command when interactive uninstall is unavailable.'
    }
    $program.UninstallString = '"'+$fake+'" /remove'
    foreach ($group in @('Norton')) {
        Reset-Case; $script:targets = @([pscustomobject]@{ Profile = @{ Group = $group }; Program = $program })
        $result = Remove-LDLCSecurityTrialsInteractively
        Assert ($launches -eq 1 -and $result.Removed -eq 1 -and $tick -ge 1000) 'Wait for removal after opening each detected vendor directly.'
    }
    Reset-Case; $script:targets = @([pscustomobject]@{ Profile = @{ Group = 'McAfee' }; Program = $program })
    Assert ((Remove-LDLCSecurityTrialsInteractively).Detected -eq 0 -and $launches -eq 0 -and $tick -eq 0) 'McAfee must never enter the new interactive launch or indefinite wait.'
    Reset-Case; $script:targets = @([pscustomobject]@{ Profile = @{ Group = 'OEM' }; Program = $program })
    Assert ((Remove-LDLCSecurityTrialsInteractively).Detected -eq 0 -and $launches -eq 0) 'Do not launch unrelated OEM uninstallers.'
    Reset-Case; $script:targets = @([pscustomobject]@{ Profile = @{ Group = 'Norton' }; Program = $program }); $script:exitAt = 2000
    Assert ((Remove-LDLCSecurityTrialsInteractively).Success -and $tick -eq 2000) 'A disappearing registry entry must not resume preparation while its uninstaller is still running.'
    Reset-Case; $script:targets = @([pscustomobject]@{ Profile = @{ Group = 'Norton' }; Program = $program }); $script:removedAt = 95000
    $script:exited = $true
    Assert ((Remove-LDLCSecurityTrialsInteractively).Success -and $tick -ge 95000 -and $launches -eq 1) 'A parent exit or 90-second limit must not kill a visible child or resume preparation early.'
    foreach ($code in @(1602,1603,3010)) {
        Reset-Case; $script:targets = @([pscustomobject]@{ Profile = @{ Group = 'Norton' }; Program = $program }); $script:exited = $true; $script:exitCode = $code; $message = ''
        try { Remove-LDLCSecurityTrialsInteractively | Out-Null } catch { $message = $_.Exception.Message }
        Assert ($message -and $tick -eq 0) 'A refused/cancelled uninstall or required reboot must stop with a cause, never report removal.'
    }
    Reset-Case; $script:targets = @([pscustomobject]@{ Profile = @{ Group = 'Norton' }; Program = $program }); $script:cancelAt = 1500; $script:removedAt = 10000; $stopped = $false
    try { Remove-LDLCSecurityTrialsInteractively | Out-Null } catch { $stopped = $_.Exception -is [OperationCanceledException] }
    Assert ($stopped -and $tick -eq 1500) 'Quit must remain responsive while waiting for manual removal.'
    Reset-Case; $script:targets = @([pscustomobject]@{ Profile = @{ Group = 'Norton' }; Program = $program }); $script:cancel = $true; $stopped = $false
    try { Remove-LDLCSecurityTrialsInteractively | Out-Null } catch { $stopped = $_.Exception -is [OperationCanceledException] }
    Assert ($stopped -and $launches -eq 0) 'Stop before opening any uninstaller.'
    if ($env:OS -eq 'Windows_NT') {
        # This executable only opens a temporary test form and writes its own markers.
        # It never installs/removes software and never changes the registry.
        $source = Join-Path $directory 'VisibleFixture.cs'
        [IO.File]::WriteAllText($source, @'
using System;
using System.IO;
using System.Windows.Forms;
class VisibleFixture {
 [STAThread] static void Main(string[] args) {
  Application.EnableVisualStyles();
  var form = new Form { Text="LDLC test uninstaller fixture", Width=320, Height=120 };
  var timer = new Timer { Interval=300 };
  form.Shown += (s,e) => { File.WriteAllText(args[0]+".shown", form.Visible.ToString()); timer.Start(); };
  timer.Tick += (s,e) => { timer.Stop(); form.Close(); };
  form.FormClosed += (s,e) => File.WriteAllText(args[0], "fixture finished");
  Application.Run(form);
 }
}
'@)
        $exe = Join-Path $directory 'VisibleFixture.exe'
        & (Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe') /nologo /target:winexe /reference:System.Windows.Forms.dll "/out:$exe" $source
        if ($LASTEXITCODE -ne 0) { throw 'Native uninstaller fixture compilation failed.' }
        Reset-Case; $script:nativeDone = Join-Path $directory 'completed marker'
        $program.UninstallString = '"'+$exe+'" "'+$script:nativeDone+'"'
        $script:targets = @([pscustomobject]@{ Profile = @{ Group = 'Norton' }; Program = $program })
        Set-Item Function:Start-LDLCSecurityInteractiveUninstaller $realLaunch
        function Start-Sleep([int]$Milliseconds) { Microsoft.PowerShell.Utility\Start-Sleep -Milliseconds $Milliseconds }
        # Test watchdog only: no timeout in the application's manual uninstall path.
        $script:watch = [Diagnostics.Stopwatch]::StartNew()
        function Stop-IfRequested { if ($script:watch.Elapsed.TotalSeconds -gt 12) { throw 'Native fixture watchdog expired.' } }
        Assert ((Remove-LDLCSecurityTrialsInteractively).Success) 'Execute the real visible-launch boundary with a harmless native fixture.'
        Assert ([IO.File]::ReadAllText($script:nativeDone+'.shown') -eq 'True') 'The native fixture window must actually be visible.'
        $native = 'real compiled Windows Form opened visibly and closed; marker-based removal fixture, no software removed'
    }
    Write-Host ('::notice title=Security interactive uninstall::'+(@{ Cases=$cases; Assertions=$checks; Failures=0; NativeWindow=$native; RealSecuritySoftwareRemoved=$false; RegistryChanged=$false; LongWaitMillisecondsSimulated=95000 } | ConvertTo-Json -Compress))
} catch {
    $message=$_.Exception.Message.Replace('%','%25').Replace("`r",'%0D').Replace("`n",'%0A')
    Write-Host ('::error title=Security interactive uninstall::'+$message)
    throw
} finally {
    $env:SystemRoot=$oldRoot
    if (Test-Path $directory) { Remove-Item -LiteralPath $directory -Recurse -Force -ErrorAction SilentlyContinue }
}
