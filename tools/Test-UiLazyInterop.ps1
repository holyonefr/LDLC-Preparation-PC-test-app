[CmdletBinding()]
param([ValidateSet('modules', 'worker-modules')][string]$ModuleDirectory = 'modules')

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$script:Assertions = 0
function Assert-True([bool]$Condition, [string]$Message) {
    $script:Assertions++
    if (-not $Condition) { throw $Message }
}

# Run this script in a fresh PowerShell process. Real workflow helpers execute,
# while harmless managed stand-ins replace the three Windows-native APIs.
foreach ($name in @('DesktopRefresh', 'LDLCDesktopIconLayout', 'WallpaperManager')) {
    if (([Management.Automation.PSTypeName]$name).Type) {
        throw "Run Test-UiLazyInterop.ps1 in a fresh PowerShell process ($name is already loaded)."
    }
}
$script:Compilations = @{ DesktopRefresh = 0; LDLCDesktopIconLayout = 0; WallpaperManager = 0 }
function Add-Type {
    param([Parameter(Position = 0)][string]$TypeDefinition)
    $standIn = if ($TypeDefinition -match '\bclass DesktopRefresh\b') {
        $script:Compilations.DesktopRefresh++
        @'
using System;
public static class DesktopRefresh {
    public static int Calls;
    public static int LastEvent;
    public static void SHChangeNotify(int id, uint flags, IntPtr first, IntPtr second) { Calls++; LastEvent = id; }
}
'@
    } elseif ($TypeDefinition -match '\bclass LDLCDesktopIconLayout\b') {
        $script:Compilations.LDLCDesktopIconLayout++
        @'
public static class LDLCDesktopIconLayout {
    public static int Calls;
    public static string[] Names;
    public static bool PositionIcons(string[] names, int x, int y, int spacing) { Calls++; Names = names; return true; }
}
'@
    } elseif ($TypeDefinition -match '\bclass WallpaperManager\b') {
        $script:Compilations.WallpaperManager++
        @'
public static class WallpaperManager {
    public static int Calls;
    public static string LastPath;
    public static int LastAction;
    public static int LastFlags;
    public static bool SystemParametersInfo(int action, int parameter, string path, int flags) {
        Calls++; LastPath = path; LastAction = action; LastFlags = flags; return true;
    }
}
'@
    } else { throw 'An unexpected native type was compiled.' }
    Microsoft.PowerShell.Utility\Add-Type -TypeDefinition $standIn
}

foreach ($module in @('40.Desktop.ps1', '45.Wallpaper.ps1')) {
    . (Join-Path $root "$ModuleDirectory/$module")
}
Assert-True (($script:Compilations.Values | Measure-Object -Sum).Sum -eq 0) 'Importing the UI helper modules must not compile native APIs.'

$saved = @{}
foreach ($name in @('ProgramData', 'USERPROFILE', 'NUMERIKS_PREP_STORE_ID')) {
    $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('Preparation-LazyInterop-' + [guid]::NewGuid().ToString('N'))
try {
    [void][IO.Directory]::CreateDirectory($testRoot)
    $env:ProgramData = Join-Path $testRoot 'Machine'
    $env:USERPROFILE = Join-Path $testRoot 'User'
    $env:NUMERIKS_PREP_STORE_ID = 'morestel'
    $script:Fixture = Join-Path $testRoot 'source.jpg'
    [IO.File]::WriteAllBytes($script:Fixture, [byte[]](1, 2, 3, 4))
    $script:Cancel = $false
    $script:PersistenceCalls = 0
    function Stop-IfRequested { if ($script:Cancel) { throw 'Test cancellation' } }
    function Write-Step { param($Text) }
    function Write-Section { param($Text) }
    function Write-Ok { param($Text) }
    function Write-Warn { param($Text) throw $Text }
    function Write-Err { param($Text) throw $Text }
    function Write-ProgressFile { param($Percent, $Text, [switch]$IgnoreStopRequest) }
    function Start-Sleep { param($Milliseconds) }
    function Get-LDLCGpuVendor { return [pscustomobject]@{ Vendor = 'Intel' } }
    function Test-LDLCDedicatedGpu { param($GpuInfo) return $false }
    function Resolve-LDLCAssetPath { param($RelativePaths) return $script:Fixture }
    function Get-LDLCWritableRuntimeRoot { return (Join-Path $testRoot 'Runtime') }
    function Set-LDLCCurrentUserWallpaper { param($WallpaperPath) $script:PersistenceCalls++ }
    function Set-LDLCLoadedUsersWallpaper { param($WallpaperPath) $script:PersistenceCalls++ }
    function Set-LDLCDefaultUserWallpaper { param($WallpaperPath) $script:PersistenceCalls++; return $true }

    $script:Cancel = $true
    foreach ($helper in @('Refresh-Desktop', 'Set-LDLCDesktopOrderedLayout', 'Set-LDLCWallpaper')) {
        $cancelled = $false
        try { & $helper | Out-Null } catch { $cancelled = $_.Exception.Message -eq 'Test cancellation' }
        Assert-True $cancelled "$helper must still respect cancellation before any native work."
    }
    Assert-True (($script:Compilations.Values | Measure-Object -Sum).Sum -eq 0) 'Cancelled work must not initialize native APIs.'
    $script:Cancel = $false

    Refresh-Desktop
    Refresh-Desktop
    Assert-True ($script:Compilations.DesktopRefresh -eq 1 -and [DesktopRefresh]::Calls -eq 2 -and [DesktopRefresh]::LastEvent -eq 0x08000000) 'Refresh must initialize once and preserve both shell notifications.'
    Assert-True ($script:Compilations.LDLCDesktopIconLayout -eq 0 -and $script:Compilations.WallpaperManager -eq 0) 'Refresh must not initialize unrelated APIs.'

    Set-LDLCDesktopOrderedLayout
    Set-LDLCDesktopOrderedLayout
    Assert-True ($script:Compilations.LDLCDesktopIconLayout -eq 1 -and [LDLCDesktopIconLayout]::Calls -eq 2) 'Desktop ordering must initialize once and still position icons on every request.'
    Assert-True ([DesktopRefresh]::Calls -eq 6 -and $script:Compilations.DesktopRefresh -eq 1) 'Desktop ordering must preserve its refresh before and after positioning.'
    Assert-True ([LDLCDesktopIconLayout]::Names -contains 'Google Chrome' -and [LDLCDesktopIconLayout]::Names -contains 'Ce PC') 'The edition desktop shortcut list must remain in use.'
    Assert-True ($script:Compilations.WallpaperManager -eq 0) 'Desktop ordering must not initialize the wallpaper API.'

    Assert-True (Set-LDLCWallpaper) 'The first wallpaper application must succeed with the deferred native API.'
    $expected = [WallpaperManager]::LastPath
    $expectedHash = (Get-FileHash -LiteralPath $expected).Hash
    Assert-True (Set-LDLCWallpaper) 'A repeated wallpaper application must still succeed.'
    Assert-True ($script:Compilations.WallpaperManager -eq 1 -and [WallpaperManager]::Calls -eq 2) 'Wallpaper applications must initialize once and preserve every native call.'
    Assert-True ([WallpaperManager]::LastPath -ceq $expected -and [WallpaperManager]::LastAction -eq 20 -and [WallpaperManager]::LastFlags -eq 3) 'The native wallpaper path, action and persistence flags must remain unchanged.'
    Assert-True ($script:PersistenceCalls -eq 6 -and (Get-FileHash -LiteralPath $expected).Hash -ceq $expectedHash) 'Current, loaded and default user persistence and image bytes must be preserved.'
    if (Get-Command Get-NumeriksSelectedWallpaperDefinition -ErrorAction SilentlyContinue) {
        Assert-True ([IO.Path]::GetFileName($expected) -ceq 'numeriksmorestel.jpg' -and $expectedHash -ceq $script:NumeriksWallpaperCatalog.morestel.Sha256) 'Numeriks must still use the exact selected store JPG.'
    }
    Assert-True (($script:Compilations.Values | Measure-Object -Sum).Sum -eq 3) 'Exactly the three APIs used by the workflow should have initialized.'
    Write-Host "OK deferred native APIs: $($script:Assertions) assertions ($ModuleDirectory); no Windows API or registry calls."
} finally {
    foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process') }
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
