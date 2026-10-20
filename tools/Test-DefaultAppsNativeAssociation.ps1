#requires -Version 5.1
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { Write-Host 'SKIP native association APIs: requires Windows'; return }
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'modules/70.DefaultApps.ps1')
$id = [guid]::NewGuid().ToString('N')
$extension = '.ldlcfixture' + $id
$progId = 'LDLC.Association.Fixture.' + $id
$classRoot = 'HKCU:\Software\Classes\'
$directory = Join-Path ([IO.Path]::GetTempPath()) ('Association-API-' + $id)
try {
    [void](New-Item -ItemType Directory -Path $directory)
    $executable = Join-Path $directory 'chrome.exe'
    [IO.File]::WriteAllText($executable, 'native association test fixture, never executed')
    [void](New-Item -Path ($classRoot + $extension))
    Set-Item -LiteralPath ($classRoot + $extension) -Value $progId
    [void](New-Item -Path ($classRoot + $progId + '\shell\open\command') -Force)
    Set-Item -LiteralPath ($classRoot + $progId + '\shell\open\command') -Value ('"' + $executable + '" "%1"')
    Ensure-LDLCDefaultAppsNativeInterop
    $reportedId = [LDLCDefaultAppsNative]::CurrentDefault($extension)
    if ($reportedId -ne $progId) { throw 'Native Windows effective ProgID did not match the isolated test extension.' }
    $resolved = [LDLCDefaultAppsNative]::ExecutableForProgId($reportedId)
    if (-not [string]::Equals($resolved, $executable, [StringComparison]::OrdinalIgnoreCase)) { throw 'Native fixed-ProgID executable resolution failed.' }
    $effective = Get-LDLCEffectiveAssociation -Association $extension
    if ($effective.Error -or $effective.ProgId -ne $progId -or $effective.Executable -ne $executable) { throw 'Native effective association wrapper failed.' }
    Write-Host ('::notice title=Native association API::' + (@{ Status = 'passed'; Assertions = 3; Mode = 'real Windows association APIs, isolated temporary file extension and class'; BrowserDefaultsChanged = $false; FixtureExecuted = $false } | ConvertTo-Json -Compress))
} catch {
    $message = $_.Exception.Message.Replace('%', '%25').Replace("`r", '%0D').Replace("`n", '%0A')
    Write-Host ('::error title=Native association API::' + $message)
    throw
} finally {
    foreach ($key in @(($classRoot + $extension), ($classRoot + $progId))) {
        if (Test-Path -LiteralPath $key) { Remove-Item -LiteralPath $key -Recurse -Force }
    }
    if (Test-Path -LiteralPath $directory) { Remove-Item -LiteralPath $directory -Recurse -Force }
}
