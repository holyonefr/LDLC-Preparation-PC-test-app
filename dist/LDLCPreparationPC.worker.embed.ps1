param(
    [switch]$Preview,
    [switch]$InstallWorker,
    [switch]$WindowsUpdateWorker,
    [switch]$SecurityCleanupWorker,
    [switch]$SecurityIsolationSmokeTest,
    [switch]$WorkerSmokeTest,
    [switch]$TestMode,
    [int]$SecurityTestDelaySeconds = 0,
    [int]$SecurityIsolationTimeoutSeconds = 30,
    [switch]$SelfTest,
    [switch]$BootstrapTest
)

$ErrorActionPreference = "Stop"
$script:LDLCEmbeddedUiAssetPayloads = @()
$script:LDLCEmbeddedWorkerPayload = $null

if ($env:LDLC_PREP_INSTALL_WORKER -eq '1') {
    $InstallWorker = $true
}

function Get-LDLCBasePath {
    if ($PSScriptRoot) {
        return $PSScriptRoot
    }

    if ($PSCommandPath) {
        return (Split-Path -Parent $PSCommandPath)
    }

    try {
        $processPath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        $processName = [System.IO.Path]::GetFileName($processPath)
        if ($processPath -and (Test-Path $processPath) -and $processName -notmatch '^(powershell|pwsh)(\.exe)?$') {
            return (Split-Path -Parent $processPath)
        }
    }
    catch {}

    return (Get-Location).Path
}

function Get-LDLCEntryPointPath {
    try {
        $processPath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        $processName = [System.IO.Path]::GetFileName($processPath)
        if ($processPath -and $processName -notmatch '^(powershell|pwsh)(\.exe)?$') {
            return $processPath
        }
    }
    catch {}

    if ($PSCommandPath) {
        return $PSCommandPath
    }

    return $MyInvocation.MyCommand.Path
}

function Test-LDLCRunningAsExecutable {
    try {
        $processPath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        $processName = [System.IO.Path]::GetFileName($processPath)
        return ($processName -notmatch '^(powershell|pwsh)(\.exe)?$')
    }
    catch {
        return $false
    }
}

function Remove-LDLCObsoleteEmbeddedFiles {
    foreach ($legacyPath in @(
        'C:\LDLC_PROGRESS.txt',
        'C:\LDLC_WORKER_LAUNCH.log',
        'C:\LDLC_WORKER_ERROR.log',
        'C:\LDLC_STOP'
    )) {
        Remove-Item -LiteralPath $legacyPath -Force -ErrorAction SilentlyContinue
    }

    if (-not [string]::IsNullOrWhiteSpace($script:LDLCEmbeddedAssetRoot) -and (Test-Path -LiteralPath $script:LDLCEmbeddedAssetRoot)) {
        foreach ($fileName in @(
            'UserDiag.exe',
            'userdiag.exe',
            'LDLC.jpg',
            'ldlc.jpg'
        )) {
            $candidatePath = Join-Path $script:LDLCEmbeddedAssetRoot $fileName
            if (Test-Path -LiteralPath $candidatePath) {
                Remove-Item -LiteralPath $candidatePath -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

function Get-LDLCWritableRuntimeRoot {
    $candidates = New-Object System.Collections.Generic.List[string]

    if (-not [string]::IsNullOrWhiteSpace($env:ProgramData)) {
        [void]$candidates.Add((Join-Path $env:ProgramData 'LDLCPreparationPC'))
    }

    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        [void]$candidates.Add((Join-Path $env:LOCALAPPDATA 'LDLCPreparationPC'))
    }

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }

        try {
            if (-not (Test-Path -LiteralPath $candidate)) {
                New-Item -ItemType Directory -Path $candidate -Force | Out-Null
            }

            $probePath = Join-Path $candidate ('.write-test-' + [guid]::NewGuid().ToString('N'))
            try {
                [System.IO.File]::WriteAllText($probePath, 'LDLC')
            }
            finally {
                Remove-Item -LiteralPath $probePath -Force -ErrorAction SilentlyContinue
            }

            return $candidate
        }
        catch {}
    }

    return $null
}

function Write-LDLCBootstrapLog {
    param([Parameter(Mandatory = $true)][string]$Message)

    try {
        $runtimeRoot = Get-LDLCWritableRuntimeRoot
        if (-not [string]::IsNullOrWhiteSpace($runtimeRoot)) {
            $line = "{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
            Add-Content -LiteralPath (Join-Path $runtimeRoot 'LDLC_BOOTSTRAP.log') -Value $line -Encoding UTF8
        }
    }
    catch {}
}

function Get-LDLCBootstrapSecurityProducts {
    $products = New-Object System.Collections.Generic.List[string]

    foreach ($root in @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )) {
        try {
            foreach ($entry in (Get-ItemProperty -Path $root -ErrorAction SilentlyContinue)) {
                $displayName = [string]$entry.DisplayName
                $publisher = [string]$entry.Publisher
                if ($displayName -match '(?i)\bNorton\b|LifeLock' -or $publisher -match '(?i)Norton|Symantec|Gen Digital') {
                    [void]$products.Add("Norton: $displayName")
                }
                elseif ($displayName -match '(?i)\bMcAfee\b|True Key|WebAdvisor' -or $publisher -match '(?i)\bMcAfee\b') {
                    [void]$products.Add("McAfee: $displayName")
                }
            }
        }
        catch {}
    }

    try {
        foreach ($product in (Get-CimInstance -Namespace 'root\SecurityCenter2' -ClassName AntiVirusProduct -ErrorAction SilentlyContinue)) {
            if ([string]$product.displayName -match '(?i)Norton|Symantec|McAfee') {
                [void]$products.Add("Windows Security: $($product.displayName)")
            }
        }
    }
    catch {}

    return @($products | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
}

function Test-LDLCFileReadable {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }

    try {
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $stream.Dispose()
        return $true
    }
    catch {
        return $false
    }
}

function Get-LDLCByteArraySha256 {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($sha256.ComputeHash($Bytes))).Replace('-', '')
    }
    finally {
        $sha256.Dispose()
    }
}

function Test-LDLCFileHash {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ExpectedSha256
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }

    try {
        return ((Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash -eq $ExpectedSha256)
    }
    catch {
        return $false
    }
}

function Install-LDLCEmbeddedUiAssets {
    param([Parameter(Mandatory = $true)][string]$RuntimeRoot)

    if (-not $script:LDLCEmbeddedUiAssetPayloads -or $script:LDLCEmbeddedUiAssetPayloads.Count -eq 0) {
        return $true
    }

    foreach ($payload in $script:LDLCEmbeddedUiAssetPayloads) {
        $expectedHash = [string]$payload.Sha256
        $bytes = [Convert]::FromBase64String([string]$payload.Base64)
        if ((Get-LDLCByteArraySha256 -Bytes $bytes) -ne $expectedHash) {
            throw 'Une ressource UI embarquee ne correspond pas a son empreinte.'
        }

        foreach ($fileName in @($payload.FileNames)) {
            if ([string]::IsNullOrWhiteSpace([string]$fileName) -or
                [System.IO.Path]::GetFileName([string]$fileName) -ne [string]$fileName) {
                throw "Nom de ressource UI refuse : $fileName"
            }

            $destinationPath = Join-Path $RuntimeRoot ([string]$fileName)
            if (Test-LDLCFileHash -Path $destinationPath -ExpectedSha256 $expectedHash) {
                Write-LDLCBootstrapLog "Ressource UI deja valide, aucune reecriture : $destinationPath"
                continue
            }

            $stagedPath = Join-Path $RuntimeRoot ('.' + [string]$fileName + '.' + [guid]::NewGuid().ToString('N') + '.new')
            try {
                [System.IO.File]::WriteAllBytes($stagedPath, $bytes)
                if (-not (Test-LDLCFileHash -Path $stagedPath -ExpectedSha256 $expectedHash)) {
                    throw "Ressource UI temporaire invalide : $fileName"
                }

                Move-Item -LiteralPath $stagedPath -Destination $destinationPath -Force -ErrorAction Stop
                if (-not (Test-LDLCFileHash -Path $destinationPath -ExpectedSha256 $expectedHash)) {
                    throw "Ressource UI finale invalide : $fileName"
                }

                Write-LDLCBootstrapLog "Ressource UI installee atomiquement : $destinationPath"
            }
            finally {
                Remove-Item -LiteralPath $stagedPath -Force -ErrorAction SilentlyContinue
            }
        }
    }

    return $true
}

function Show-LDLCBootstrapFailure {
    param(
        [Parameter(Mandatory = $true)][string]$Reason,
        [string[]]$SecurityProducts = @()
    )

    $securityText = if ($SecurityProducts.Count) {
        "Protection detectee : $($SecurityProducts -join ', ')."
    }
    else {
        'Aucun produit Norton ou McAfee n a pu etre confirme dans Windows.'
    }

    $message = @(
        'LDLC PREPTOOL ne peut pas demarrer depuis son emplacement securise.',
        '',
        $securityText,
        "Cause : $Reason",
        '',
        'Verifiez l historique de securite Norton, la quarantaine et les autorisations du fichier.',
        'Ne desactivez pas la protection : restaurez ou autorisez uniquement LDLCPreparationPC.exe, puis relancez-le.',
        '',
        'Journal : C:\ProgramData\LDLCPreparationPC\LDLC_BOOTSTRAP.log'
    ) -join [Environment]::NewLine

    Write-LDLCBootstrapLog "ECHEC DEMARRAGE : $Reason | $securityText"
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        [System.Windows.Forms.MessageBox]::Show($message, 'LDLC PREPTOOL - blocage de securite', 'OK', 'Error') | Out-Null
    }
    catch {
        Write-Host $message
    }
}


function Install-LDLCEmbeddedWorkerScript {
    param([Parameter(Mandatory = $true)][string]$RuntimeRoot)

    if (-not $script:LDLCEmbeddedWorkerPayload) {
        return $null
    }

    $expectedHash = [string]$script:LDLCEmbeddedWorkerPayload.Sha256
    $bytes = [Convert]::FromBase64String([string]$script:LDLCEmbeddedWorkerPayload.Base64)
    if ((Get-LDLCByteArraySha256 -Bytes $bytes) -ne $expectedHash) {
        throw 'Le worker embarque ne correspond pas a son empreinte.'
    }

    $destinationPath = Join-Path $RuntimeRoot 'LDLCPreparationPC.worker.ps1'
    if (Test-LDLCFileHash -Path $destinationPath -ExpectedSha256 $expectedHash) {
        Write-LDLCBootstrapLog "Worker deja valide, aucune reecriture : $destinationPath"
        return $destinationPath
    }

    $stagedPath = Join-Path $RuntimeRoot ('.LDLCPreparationPC.worker.' + [guid]::NewGuid().ToString('N') + '.new.ps1')
    try {
        [System.IO.File]::WriteAllBytes($stagedPath, $bytes)
        if (-not (Test-LDLCFileHash -Path $stagedPath -ExpectedSha256 $expectedHash)) {
            throw 'Le worker temporaire ne correspond pas a son empreinte.'
        }
        try { Unblock-File -LiteralPath $stagedPath -ErrorAction Stop } catch {}
        Move-Item -LiteralPath $stagedPath -Destination $destinationPath -Force -ErrorAction Stop
        if (-not (Test-LDLCFileHash -Path $destinationPath -ExpectedSha256 $expectedHash)) {
            throw 'La validation finale du worker a echoue.'
        }
        Write-LDLCBootstrapLog "Worker installe atomiquement : $destinationPath"
        return $destinationPath
    }
    finally {
        Remove-Item -LiteralPath $stagedPath -Force -ErrorAction SilentlyContinue
    }
}

function Initialize-LDLCEmbeddedWorkerState {
    $script:LDLCEmbeddedWorkerScriptPath = Install-LDLCEmbeddedWorkerScript -RuntimeRoot $script:LDLCEmbeddedAssetRoot
    if ([string]::IsNullOrWhiteSpace($script:LDLCEmbeddedWorkerScriptPath) -and
        -not [string]::IsNullOrWhiteSpace($PSCommandPath) -and
        [System.IO.Path]::GetFileName($PSCommandPath) -eq 'LDLCPreparationPC.worker.ps1' -and
        (Test-LDLCFileReadable -Path $PSCommandPath)) {
        $script:LDLCEmbeddedWorkerScriptPath = $PSCommandPath
    }
}

function Start-LDLCInstance {
    param(
        [string[]]$Arguments = @(),
        [switch]$RunAs
    )

    $entryPoint = Get-LDLCEntryPointPath
    $launchAsWorker = ($Arguments -contains '-InstallWorker')
    $previousWorkerEnv = $env:LDLC_PREP_INSTALL_WORKER

    try {
        if ($launchAsWorker) {
            $env:LDLC_PREP_INSTALL_WORKER = '1'
        }

        if (Test-LDLCRunningAsExecutable) {
            $argumentList = @('-end') + $Arguments
            $startParams = @{
                FilePath = $entryPoint
                WindowStyle = 'Minimized'
                ArgumentList = $argumentList
                PassThru = $true
            }
            if ($RunAs) {
                $startParams.Verb = 'RunAs'
            }

            return Start-Process @startParams
        }

        $psExe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $argumentList = @('-ExecutionPolicy', 'Bypass', '-NoProfile', '-File', $entryPoint) + $Arguments
        $startParams = @{
            FilePath = $psExe
            WindowStyle = 'Minimized'
            ArgumentList = $argumentList
            PassThru = $true
        }
        if ($RunAs) {
            $startParams.Verb = 'RunAs'
        }

        return Start-Process @startParams
    }
    finally {
        if ($launchAsWorker) {
            if ($null -eq $previousWorkerEnv) {
                Remove-Item Env:\LDLC_PREP_INSTALL_WORKER -ErrorAction SilentlyContinue
            }
            else {
                $env:LDLC_PREP_INSTALL_WORKER = $previousWorkerEnv
            }
        }
    }
}

$script:LDLCRoot = Get-LDLCBasePath
$script:LDLCEmbeddedAssetRoot = Get-LDLCWritableRuntimeRoot
Remove-LDLCObsoleteEmbeddedFiles

# Le diagnostic normal sera fait par le worker, une fois la fenetre affichee.
# Les modes de diagnostic explicites gardent leur initialisation complete.
$script:LDLCDeferBootstrapWork = -not ($InstallWorker -or $WindowsUpdateWorker -or
    $SecurityCleanupWorker -or $SecurityIsolationSmokeTest -or $WorkerSmokeTest -or
    $BootstrapTest -or $SelfTest)
$securityProductsAtStartup = @()
if (-not $script:LDLCDeferBootstrapWork) {
    $securityProductsAtStartup = @(Get-LDLCBootstrapSecurityProducts)
    if ($securityProductsAtStartup.Count) {
        Write-LDLCBootstrapLog "Protection detectee au lancement : $($securityProductsAtStartup -join ', ')"
    }
}


try {
    [void](Install-LDLCEmbeddedUiAssets -RuntimeRoot $script:LDLCEmbeddedAssetRoot)
}
catch {
    $securityProducts = @(Get-LDLCBootstrapSecurityProducts)
    Show-LDLCBootstrapFailure -Reason "Creation des ressources d interface impossible : $($_.Exception.Message)" -SecurityProducts $securityProducts
    throw
}

$script:LDLCEmbeddedWorkerScriptPath = $null
if (-not $script:LDLCDeferBootstrapWork) {
    try {
        Initialize-LDLCEmbeddedWorkerState
    }
    catch {
        Show-LDLCBootstrapFailure -Reason "Installation du worker impossible : $($_.Exception.Message)" -SecurityProducts $securityProductsAtStartup
        throw
    }
}

if ($BootstrapTest) {
    $bootstrapTestPath = Join-Path $script:LDLCEmbeddedAssetRoot 'LDLC_BOOTSTRAP_TEST.json'
    [ordered]@{
        EntryPoint = Get-LDLCEntryPointPath
        RuntimeRoot = $script:LDLCEmbeddedAssetRoot
        WorkerPath = $script:LDLCEmbeddedWorkerScriptPath
        WorkerReady = [bool]($script:LDLCEmbeddedWorkerScriptPath -and (Test-LDLCFileReadable -Path $script:LDLCEmbeddedWorkerScriptPath))
        SecurityProducts = @(Get-LDLCBootstrapSecurityProducts)
        Timestamp = (Get-Date).ToString('o')
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $bootstrapTestPath -Encoding UTF8 -Force
    Write-LDLCBootstrapLog "Test bootstrap reussi depuis : $(Get-LDLCEntryPointPath)"
    return
}

if ($SelfTest) {
    $selfTestRoot = Get-LDLCWritableRuntimeRoot
    if ([string]::IsNullOrWhiteSpace($selfTestRoot)) {
        $selfTestRoot = $script:LDLCRoot
    }

    $selfTestPath = Join-Path $selfTestRoot 'LDLCPreparationPC.selftest'
    "SelfTest OK - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Set-Content -Path $selfTestPath -Encoding UTF8 -Force
    return
}

# region Module: 00.Core.ps1
# Core helpers, progress handling, connectivity, and power management.

function Initialize-LDLCConsoleWindow {
    try {
        if (-not ('Win32' -as [type])) {
            Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Win32 {
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool BringWindowToTop(IntPtr hWnd);
}
"@
        }

        $consoleHandle = [Win32]::GetConsoleWindow()
        if ($consoleHandle -ne [IntPtr]::Zero) {
            [Win32]::ShowWindow($consoleHandle, 2) | Out-Null
        }
    }
    catch {
        Write-Warn "Impossible de reduire la console : $($_.Exception.Message)"
    }
}
function Write-Section {
    param([string]$Text)
    Write-Host ""
    Write-Host "==================================================" -ForegroundColor DarkCyan
    Write-Host $Text -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor DarkCyan
    Write-LDLCLocalLog -Level 'SECTION' -Text $Text
    if (Get-Command Set-LDLCTelemetryStep -ErrorAction SilentlyContinue) {
        Set-LDLCTelemetryStep -Step $Text
    }
}

function Write-LDLCLocalLog {
    param(
        [string]$Level = 'INFO',
        [string]$Text = ''
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return
    }

    try {
        if ([string]::IsNullOrWhiteSpace($script:LDLCLocalLogPath)) {
            if ([string]::IsNullOrWhiteSpace($script:RuntimeRoot)) {
                return
            }

            $script:LDLCLocalLogPath = Join-Path $script:RuntimeRoot 'LDLC_PREPARATION.log'
        }

        $logDir = Split-Path -Parent $script:LDLCLocalLogPath
        if ($logDir -and -not (Test-Path -LiteralPath $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }

        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Add-Content -LiteralPath $script:LDLCLocalLogPath -Encoding UTF8 -Value ("[{0}] [{1}] {2}" -f $timestamp, $Level, $Text)
    }
    catch {}
}

function Get-LDLCBooleanEnvironmentValue {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [bool]$Default = $false
    )

    $value = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $Default
    }

    $normalized = ($value -replace '[^\p{L}\p{Nd}]', '').ToLowerInvariant()
    if ($normalized -in @('1', 'true', 'yes', 'oui', 'on', 'enabled', 'active')) {
        return $true
    }

    if ($normalized -in @('0', 'false', 'no', 'non', 'off', 'disabled', 'inactive')) {
        return $false
    }

    return $Default
}

function Write-Step {
    param([string]$Text)
    Write-Host "-> $Text" -ForegroundColor White
    Write-LDLCLocalLog -Level 'INFO' -Text $Text
    if (Get-Command Update-LDLCTelemetryRun -ErrorAction SilentlyContinue) {
        Update-LDLCTelemetryRun -Message $Text
    }
}

function Write-Ok {
    param([string]$Text)
    Write-Host "[OK] $Text" -ForegroundColor Green
    Write-LDLCLocalLog -Level 'OK' -Text $Text
}

function Write-Warn {
    param([string]$Text)
    Write-Host "[ATTENTION] $Text" -ForegroundColor Yellow
    Write-LDLCLocalLog -Level 'WARN' -Text $Text
    if (Get-Command Add-LDLCTelemetryEvent -ErrorAction SilentlyContinue) {
        Add-LDLCTelemetryEvent -Message $Text -Severity warning
    }
}

function Write-Info {
    param([string]$Text)
    Write-Host "[INFO] $Text" -ForegroundColor Cyan
    Write-LDLCLocalLog -Level 'INFO' -Text $Text
}

function Write-Err {
    param([string]$Text)
    Write-Host "[ERREUR] $Text" -ForegroundColor Red
    Write-LDLCLocalLog -Level 'ERROR' -Text $Text
    if (Get-Command Add-LDLCTelemetryEvent -ErrorAction SilentlyContinue) {
        Add-LDLCTelemetryEvent -Message $Text -Severity error
    }
}
function Get-LDLCProjectRoot {
    if (-not [string]::IsNullOrWhiteSpace($script:LDLCRoot)) {
        return $script:LDLCRoot
    }

    if ($PSScriptRoot) {
        return (Split-Path -Parent $PSScriptRoot)
    }

    return (Get-Location).Path
}

function Get-LDLCWritableRuntimeRoot {
    $candidates = New-Object System.Collections.Generic.List[string]

    if (-not [string]::IsNullOrWhiteSpace($env:ProgramData)) {
        [void]$candidates.Add((Join-Path $env:ProgramData 'LDLCPreparationPC'))
    }

    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        [void]$candidates.Add((Join-Path $env:LOCALAPPDATA 'LDLCPreparationPC'))
    }

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }

        try {
            if (-not (Test-Path -LiteralPath $candidate)) {
                New-Item -ItemType Directory -Path $candidate -Force | Out-Null
            }

            $probePath = Join-Path $candidate ('.write-test-' + [guid]::NewGuid().ToString('N'))
            try {
                [System.IO.File]::WriteAllText($probePath, 'LDLC')
            }
            finally {
                Remove-Item -LiteralPath $probePath -Force -ErrorAction SilentlyContinue
            }

            return $candidate
        }
        catch {}
    }

    return $null
}

function Get-LDLCEmbeddedAssetRoot {
    if (-not [string]::IsNullOrWhiteSpace($script:LDLCEmbeddedAssetRoot)) {
        return $script:LDLCEmbeddedAssetRoot
    }

    return Get-LDLCWritableRuntimeRoot
}

function Get-LDLCRuntimeRoot {
    $runtimeRoot = Get-LDLCEmbeddedAssetRoot

    if ([string]::IsNullOrWhiteSpace($runtimeRoot)) {
        $runtimeRoot = Join-Path (Get-LDLCProjectRoot) 'runtime'
    }

    if (-not (Test-Path -LiteralPath $runtimeRoot)) {
        New-Item -ItemType Directory -Path $runtimeRoot -Force | Out-Null
    }

    return $runtimeRoot
}

function Remove-LDLCLegacyRuntimeFiles {
    foreach ($legacyPath in @(
        'C:\LDLC_PROGRESS.txt',
        'C:\LDLC_WORKER_LAUNCH.log',
        'C:\LDLC_WORKER_ERROR.log',
        'C:\LDLC_STOP'
    )) {
        Remove-Item -LiteralPath $legacyPath -Force -ErrorAction SilentlyContinue
    }
}

function Resolve-LDLCAssetPath {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$RelativePaths
    )

    $projectRoot = Get-LDLCProjectRoot
    $assetRoots = New-Object System.Collections.Generic.List[string]

    if (-not [string]::IsNullOrWhiteSpace($projectRoot)) {
        [void]$assetRoots.Add($projectRoot)
    }

    $embeddedAssetRoot = Get-LDLCEmbeddedAssetRoot
    if (-not [string]::IsNullOrWhiteSpace($embeddedAssetRoot)) {
        [void]$assetRoots.Add($embeddedAssetRoot)
    }

    foreach ($assetRoot in ($assetRoots | Select-Object -Unique)) {
        foreach ($relativePath in $RelativePaths) {
            $candidate = Join-Path $assetRoot $relativePath
            if (Test-Path $candidate) {
                return $candidate
            }
        }
    }

    return $null
}

function Initialize-LDLCScriptState {
    param([string]$ProjectRoot, [switch]$PreserveStopRequest)

    if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
        $ProjectRoot = Get-LDLCProjectRoot
    }

    $script:LDLCRoot = $ProjectRoot
    $script:RuntimeRoot = Get-LDLCRuntimeRoot
    $script:StopFile = Join-Path $script:RuntimeRoot "LDLC_STOP"
    $script:ProgressFile = Join-Path $script:RuntimeRoot "LDLC_PROGRESS.txt"
    $script:LDLCLocalLogPath = Join-Path $script:RuntimeRoot "LDLC_PREPARATION.log"

    $script:WU_IncludeDrivers = Get-LDLCBooleanEnvironmentValue -Name 'LDLC_WU_INCLUDE_DRIVERS' -Default $true
    $script:WU_InstallOptional = Get-LDLCBooleanEnvironmentValue -Name 'LDLC_WU_INSTALL_OPTIONAL' -Default $true
    $script:WU_VerifyAfterInstall = Get-LDLCBooleanEnvironmentValue -Name 'LDLC_WU_VERIFY_AFTER_INSTALL' -Default $false
    $script:WU_AutoReboot = $false
    $script:PendingReboot = $false
    $script:PowerSettingsCaptured = $false
    $script:PowerSettingsRestored = $false
    $script:CommandAvailabilityCache = @{}
    $script:InstalledProgramsCache = $null
    $script:InstalledProgramsCacheTimestamp = [datetime]::MinValue
    $script:InstalledProgramsCacheTtlSeconds = 5
    $script:ExePathCache = @{}

    Remove-LDLCLegacyRuntimeFiles
    if (-not $PreserveStopRequest) { Remove-Item $script:StopFile -Force -ErrorAction SilentlyContinue }
    Write-LDLCLocalLog -Level 'INFO' -Text "===== Nouvelle execution LDLC Preparation PC ====="
    Initialize-LDLCConsoleWindow

    if (Get-Command Initialize-LDLCTelemetry -ErrorAction SilentlyContinue) {
        Initialize-LDLCTelemetry
    }
}
function Test-StopRequested {
    return (Test-Path $script:StopFile)
}

function Test-LDLCStopRequestError {
    param($ErrorRecord)

    if ($null -eq $ErrorRecord) {
        return $false
    }

    $message = ''
    if ($ErrorRecord -is [System.Management.Automation.ErrorRecord]) {
        $message = [string]$ErrorRecord.Exception.Message
    }
    elseif ($ErrorRecord -is [System.Exception]) {
        $message = [string]$ErrorRecord.Message
    }
    else {
        $message = [string]$ErrorRecord
    }

    return ($message -match 'LDLC_STOP_REQUESTED')
}

function Stop-IfRequested {
    if (Test-StopRequested) {
        try {
            $progressDir = Split-Path -Parent $script:ProgressFile
            if ($progressDir -and -not (Test-Path -LiteralPath $progressDir)) {
                New-Item -ItemType Directory -Path $progressDir -Force | Out-Null
            }

            "0|Installation annulee." | Set-Content -Path $script:ProgressFile -Encoding UTF8 -Force
        }
        catch {}

        Write-Host "[ATTENTION] Arret demande par l'utilisateur." -ForegroundColor Yellow
        throw "LDLC_STOP_REQUESTED"
    }
}

function Write-ProgressFile {
    param(
        [int]$Percent,
        [string]$Message,
        [switch]$IgnoreStopRequest
    )

    if (-not $IgnoreStopRequest) {
        Stop-IfRequested
    }

    if (Get-Command Set-LDLCTelemetryStep -ErrorAction SilentlyContinue) {
        Set-LDLCTelemetryStep -Step $Message -ProgressPercent $Percent
    }

    try {
        $Percent = [math]::Max(0, [math]::Min(100, $Percent))
        $progressDir = Split-Path -Parent $script:ProgressFile
        if ($progressDir -and -not (Test-Path -LiteralPath $progressDir)) {
            New-Item -ItemType Directory -Path $progressDir -Force | Out-Null
        }

        "$Percent|$Message" | Set-Content -Path $script:ProgressFile -Encoding UTF8 -Force
    }
    catch {}

    if (-not $script:LDLCSuppressWriteProgress) {
        Write-Progress `
            -Activity "Preparation du PC" `
            -Status $Message `
            -PercentComplete $Percent
    }
}
function Test-LDLCInternetConnection {
    try {
        $hasActiveRoute = @(
            Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
                Where-Object { $_.NextHop -and $_.NextHop -ne '0.0.0.0' }
        ).Count -gt 0
    }
    catch {
        $hasActiveRoute = $false
    }

    try {
        $hasUpAdapter = @(
            Get-NetAdapter -ErrorAction SilentlyContinue |
                Where-Object { $_.Status -eq 'Up' -and $_.HardwareInterface }
        ).Count -gt 0
    }
    catch {
        $hasUpAdapter = $false
    }

    if (-not $hasActiveRoute -and -not $hasUpAdapter) {
        return $false
    }

    $probeUris = @(
        'http://www.msftconnecttest.com/connecttest.txt',
        'http://connectivitycheck.gstatic.com/generate_204'
    )

    foreach ($probeUri in $probeUris) {
        try {
            $response = Invoke-WebRequest -Uri $probeUri -UseBasicParsing -TimeoutSec 5 -Headers @{ 'Cache-Control' = 'no-cache' }
            if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 400) {
                return $true
            }
        }
        catch {}
    }

    try {
        return (Test-Connection -ComputerName '1.1.1.1' -Count 1 -Quiet -ErrorAction Stop)
    }
    catch {
        return $false
    }
}
function Wait-LDLCInternetConnection {
    param(
        [int]$ProgressPercent = 0,
        [int]$RetryDelaySeconds = 5
    )

    Stop-IfRequested
    Write-Section "VERIFICATION INTERNET"
    Write-Step "Verification de la connexion Internet..."

    if (Test-LDLCInternetConnection) {
        Write-Ok "Connexion Internet detectee."
        Write-ProgressFile $ProgressPercent "Connexion Internet detectee."
        return $true
    }

    Write-Warn "Aucune connexion Internet detectee. Connecte le PC au Wi-Fi pour continuer."

    $attempt = 0
    while (-not (Test-LDLCInternetConnection)) {
        Stop-IfRequested
        $attempt++

        Write-ProgressFile $ProgressPercent "Aucune connexion Internet. Connecte le PC au Wi-Fi pour continuer..."

        if ($attempt -eq 1 -or ($attempt % 6) -eq 0) {
            Write-Step "En attente d'une connexion Internet..."
        }

        Start-Sleep -Seconds $RetryDelaySeconds
    }

    Write-Ok "Connexion Internet detectee. Demarrage du script."
    Write-ProgressFile $ProgressPercent "Connexion Internet detectee. Demarrage du script..."
    Start-Sleep -Seconds 1
    return $true
}


function Wait-LDLCCondition {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Condition,
        [int]$TimeoutSeconds = 30,
        [int]$PollMilliseconds = 1000,
        [switch]$IgnoreErrors
    )

    $deadline = (Get-Date).AddSeconds([math]::Max(1, $TimeoutSeconds))

    while ((Get-Date) -lt $deadline) {
        Stop-IfRequested

        try {
            if (& $Condition) {
                return $true
            }
        }
        catch {
            if (-not $IgnoreErrors) {
                throw
            }
        }

        Start-Sleep -Milliseconds ([math]::Max(100, $PollMilliseconds))
    }

    try {
        return [bool](& $Condition)
    }
    catch {
        if (-not $IgnoreErrors) {
            throw
        }
    }

    return $false
}

function Get-LDLCPowerSettingIndex {
    param(
        [Parameter(Mandatory = $true)][string]$SubGroupAlias,
        [Parameter(Mandatory = $true)][string]$SettingAlias,
        [ValidateSet("AC", "DC")]
        [string]$PowerSource
    )

    $output = powercfg /query SCHEME_CURRENT $SubGroupAlias $SettingAlias | Out-String

    $pattern = switch ($PowerSource) {
        "AC" { '(?im)(?:Current AC Power Setting Index|Index actuel du paramètre de courant alternatif)\s*:\s*(0x[0-9a-f]+)' }
        "DC" { '(?im)(?:Current DC Power Setting Index|Index actuel du paramètre de courant continu)\s*:\s*(0x[0-9a-f]+)' }
    }

    $match = [regex]::Match($output, $pattern)
    if (-not $match.Success) {
        throw "Valeur $PowerSource introuvable pour $SubGroupAlias/$SettingAlias."
    }

    return $match.Groups[1].Value
}

function Test-LDLCBatteryPresent {
    try {
        return @((Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)).Count -gt 0
    }
    catch {
        return $false
    }
}

function Get-LDLCPowerRestoreTimeouts {
    $hasBattery = Test-LDLCBatteryPresent

    $fallbacks = @{
        MonitorTimeoutAC = 10
        StandbyTimeoutAC = 30
        MonitorTimeoutDC = $(if ($hasBattery) { 5 } else { 10 })
        StandbyTimeoutDC = $(if ($hasBattery) { 15 } else { 30 })
    }

    $capturedHexValues = @{
        MonitorTimeoutAC = $script:OriginalMonitorTimeoutAC
        StandbyTimeoutAC = $script:OriginalStandbyTimeoutAC
        MonitorTimeoutDC = $script:OriginalMonitorTimeoutDC
        StandbyTimeoutDC = $script:OriginalStandbyTimeoutDC
    }

    function Convert-LDLCCapturedPowerValueToMinutes {
        param(
            [string]$RawValue,
            [int]$FallbackMinutes,
            [string]$Label
        )

        if ([string]::IsNullOrWhiteSpace($RawValue)) {
            return $FallbackMinutes
        }

        try {
            # powercfg /query returns timeout indices in seconds, while
            # powercfg /change expects minutes.
            $capturedSeconds = [int][convert]::ToInt32($RawValue, 16)
            if ($capturedSeconds -le 0) {
                return $FallbackMinutes
            }

            $capturedMinutes = [int][math]::Ceiling($capturedSeconds / 60.0)

            if ($capturedMinutes -gt 240) {
                Write-Warn "Valeur capturee anormale pour $Label ($capturedMinutes min). Valeur par defaut retenue : $FallbackMinutes min."
                return $FallbackMinutes
            }

            return $capturedMinutes
        }
        catch {
            return $FallbackMinutes
        }
    }

    $resolved = @{}

    foreach ($entry in $capturedHexValues.GetEnumerator()) {
        $name = $entry.Key
        $rawValue = $entry.Value
        $resolved[$name] = Convert-LDLCCapturedPowerValueToMinutes -RawValue $rawValue -FallbackMinutes $fallbacks[$name] -Label $name
    }

    return [pscustomobject]$resolved
}

function TryGet-LDLCPowerSettingIndex {
    param(
        [Parameter(Mandatory = $true)][string]$SubGroupAlias,
        [Parameter(Mandatory = $true)][string]$SettingAlias,
        [ValidateSet("AC", "DC")]
        [string]$PowerSource
    )

    try {
        return Get-LDLCPowerSettingIndex -SubGroupAlias $SubGroupAlias -SettingAlias $SettingAlias -PowerSource $PowerSource
    }
    catch {
        Write-Warn "Lecture impossible pour $SettingAlias en mode $PowerSource : $($_.Exception.Message)"
        return $null
    }
}

function Invoke-LDLCPowerCfgChange {
    param(
        [Parameter(Mandatory = $true)][string]$SettingName,
        [Parameter(Mandatory = $true)][int]$Value,
        [Parameter(Mandatory = $true)][string]$Label
    )

    try {
        & powercfg /change $SettingName $Value | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "powercfg a retourne le code $LASTEXITCODE."
        }

        return $true
    }
    catch {
        Write-Warn "Impossible d'appliquer $Label : $($_.Exception.Message)"
        return $false
    }
}

function Restore-PowerSettings {
    param(
        [int]$ProgressPercent = 97,
        [switch]$IgnoreStopRequest
    )

    if (-not $IgnoreStopRequest) {
        Stop-IfRequested
    }

    Write-Section "RESTAURATION DES PARAMETRES D'ALIMENTATION"
    Write-ProgressFile $ProgressPercent "Restauration des paramètres d’alimentation…" -IgnoreStopRequest

    if (-not $script:PowerSettingsCaptured) {
        Write-Warn "Parametres d'alimentation initiaux indisponibles. Restauration ignoree."
        return $false
    }

    if ($script:PowerSettingsRestored) {
        Write-Ok "Parametres d'alimentation deja restaures."
        return $true
    }

    try {
        Write-Step "Restauration des delais veille/ecran..."
        $restoreTimeouts = Get-LDLCPowerRestoreTimeouts
        $hasBattery = Test-LDLCBatteryPresent
        $restoreResults = @()

        $restoreResults += Invoke-LDLCPowerCfgChange -SettingName "monitor-timeout-ac" -Value $restoreTimeouts.MonitorTimeoutAC -Label "ecran AC"
        $restoreResults += Invoke-LDLCPowerCfgChange -SettingName "standby-timeout-ac" -Value $restoreTimeouts.StandbyTimeoutAC -Label "veille AC"

        if ($hasBattery) {
            $restoreResults += Invoke-LDLCPowerCfgChange -SettingName "monitor-timeout-dc" -Value $restoreTimeouts.MonitorTimeoutDC -Label "ecran DC"
            $restoreResults += Invoke-LDLCPowerCfgChange -SettingName "standby-timeout-dc" -Value $restoreTimeouts.StandbyTimeoutDC -Label "veille DC"
        }
        else {
            Write-Step "Aucune batterie detectee : restauration DC ignoree."
        }

        $script:PowerSettingsRestored = (-not ($restoreResults -contains $false))
        if ($script:PowerSettingsRestored) {
            Write-Ok "Parametres d'alimentation restaures."
        }
        else {
            Write-Warn "Restauration des parametres d'alimentation partielle."
        }

        Write-Step "Valeurs appliquees : ecran AC=$($restoreTimeouts.MonitorTimeoutAC) min, veille AC=$($restoreTimeouts.StandbyTimeoutAC) min, ecran DC=$($restoreTimeouts.MonitorTimeoutDC) min, veille DC=$($restoreTimeouts.StandbyTimeoutDC) min."
        Write-ProgressFile $ProgressPercent "Reactivation de la veille par defaut" -IgnoreStopRequest
        return $script:PowerSettingsRestored
    }
    catch {
        Write-Err "Erreur lors de la restauration des parametres d'alimentation : $($_.Exception.Message)"
        return $false
    }
}

# endregion Module: 00.Core.ps1

# region Module: 05.Telemetry.ps1
# Error telemetry and Google Sheets export.

# Fill these two values after deploying tools/google-apps-script/LDLC_ErrorTelemetry.gs.
# They are intentionally embedded so the compiled exe can report issues from any PC.
$script:LDLCTelemetryEndpointUrl = 'https://script.google.com/macros/s/AKfycbwYe2r5-y8HeyfLjslbq7wI2BdFH0sj7TLJQSiUyeRdt_z7yytyTKsPQPPcT0HUcAci3g/exec'
$script:LDLCTelemetryApiKey = 'LDLC-PrepTool-2026-ea2653c3d8f94cad9bbe4a2fa6fe8e18'
$script:LDLCTelemetryToolVersion = '2.6.16'
$script:LDLCTelemetrySource = 'LDLCPreparationPC'
$script:LDLCTelemetryApplicationSource = 'LDLC_PREPARATION_PC'
$script:LDLCTelemetryEdition = 'LDLC'
$script:LDLCTelemetrySendSuccessfulRuns = $true
$script:LDLCTelemetryUpdateIntervalSeconds = 60
$script:LDLCTelemetryRemoteWriteMode = 'live'
$script:LDLCTelemetryNetworkTimeoutSeconds = 30

function Test-LDLCTelemetryDisabled {
    $value = [string]$env:LDLC_TELEMETRY_DISABLED
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $false
    }

    $normalized = ($value -replace '[^\p{L}\p{Nd}]', '').ToLowerInvariant()
    return ($normalized -in @('1', 'true', 'yes', 'oui', 'on', 'disabled', 'disable'))
}

function Convert-LDLCTelemetryRunStatus {
    param(
        [string]$Status,
        [object]$Counts,
        [switch]$Final
    )

    $normalized = ConvertTo-LDLCTelemetryText $Status 120
    $key = ($normalized -replace '[^\p{L}\p{Nd}]', '').ToLowerInvariant()

    if ([string]::IsNullOrWhiteSpace($key)) {
        $key = if ($Final) { 'stopped' } else { 'running' }
    }

    $errorCount = if ($Counts) { [int]$Counts.ErrorCount + [int]$Counts.CriticalCount } else { 0 }
    $warningCount = if ($Counts) { [int]$Counts.WarningCount } else { 0 }

    if ($Final) {
        if ($key -match '^(stopped|stop|interrompu|interruption|cancelled|canceled|annule|annulé|annulee|annulée)$') {
            return 'stopped'
        }

        # Un avertissement ne doit jamais masquer un delai reellement depasse.
        if ($key -match '(timeout|bloque|bloqué|blocked|delai|délai|watchdog)') {
            return 'timeout'
        }

        if ($errorCount -gt 0 -or $key -match '^(failed|fail|failure|echec|échec|error|erreur|critical|critique)$') {
            return 'failed'
        }

        if ($warningCount -gt 0 -or $key -match '^(warning|warn|avertissement|partial|partiel|partielle)$') {
            return 'warning'
        }

        if ($key -match '^(success|ok|reussi|réussi|completed|complete|done|finished|termine|terminé|termineavecsucces|terminéavecsuccès)$') { return 'success' }
        return 'stopped'
    }

    switch -Regex ($key) {
        '^(running|encours|inprogress)$' { return 'running' }
        '^(success|ok|reussi|réussi|completed|complete|done|finished|termine|terminé|termineavecsucces|terminéavecsuccès)$' { return 'success' }
        '^(warning|warn|avertissement|partial|partiel|partielle)$' { return 'warning' }
        '^(stopped|stop|interrompu|interruption|cancelled|canceled|annule|annulé|annulee|annulée)$' { return 'stopped' }
        '(timeout|bloque|bloqué|blocked|delai|délai|watchdog)' { return 'timeout' }
        '^(failed|fail|failure|echec|échec|error|erreur|critical|critique)$' { return 'failed' }
        default { return 'running' }
    }
}

function Convert-LDLCTelemetryRunStatusDisplayText {
    param([string]$Status)

    $key = ((ConvertTo-LDLCTelemetryText $Status 120) -replace '[^\p{L}\p{Nd}]', '').ToLowerInvariant()
    switch -Regex ($key) {
        '^(success|ok|reussi|réussi|completed|complete|done|finished|termine|terminé|termineavecsucces|terminéavecsuccès)$' { return 'Réussi' }
        '^(warning|warn|avertissement|partial|partiel|partielle|termineavecavertissement|terminéavecavertissement)$' { return 'Réussi avec avertissement' }
        '^(failed|fail|failure|echec|échec|error|erreur|critical|critique)$' { return 'Échec' }
        '^(timeout|bloque|bloqué|blocked|delai|délai|watchdog)$' { return 'Délai dépassé' }
        '^(stopped|stop|interrompu|interruption|cancelled|canceled|annule|annulé|annulee|annulée)$' { return 'Interrompu' }
        '^(running|encours|inprogress)$' { return 'En cours' }
        default {
            if ([string]::IsNullOrWhiteSpace($Status)) {
                return ''
            }

            return $Status
        }
    }
}

function Get-LDLCUtcTimestamp {
    return ([datetime]::UtcNow.ToString('o'))
}

function Get-LDLCTelemetryEndpointUrl {
    if (-not [string]::IsNullOrWhiteSpace($env:LDLC_TELEMETRY_URL)) {
        return [string]$env:LDLC_TELEMETRY_URL
    }

    return [string]$script:LDLCTelemetryEndpointUrl
}

function Get-LDLCTelemetryApiKey {
    if (-not [string]::IsNullOrWhiteSpace($env:LDLC_TELEMETRY_KEY)) {
        return [string]$env:LDLC_TELEMETRY_KEY
    }

    return [string]$script:LDLCTelemetryApiKey
}

function Test-LDLCTelemetryConfigured {
    $endpointUrl = Get-LDLCTelemetryEndpointUrl
    $apiKey = Get-LDLCTelemetryApiKey

    return (
        -not [string]::IsNullOrWhiteSpace($endpointUrl) -and
        -not [string]::IsNullOrWhiteSpace($apiKey) -and
        $endpointUrl -notmatch 'A_REMPLACER|CHANGE_ME|PASTE_' -and
        $apiKey -notmatch 'A_REMPLACER|CHANGE_ME|PASTE_'
    )
}

function Get-LDLCTelemetryRemoteWriteMode {
    $mode = if (-not [string]::IsNullOrWhiteSpace($env:LDLC_TELEMETRY_REMOTE_MODE)) {
        [string]$env:LDLC_TELEMETRY_REMOTE_MODE
    }
    else {
        [string]$script:LDLCTelemetryRemoteWriteMode
    }

    $normalized = ($mode -replace '[^\p{L}\p{Nd}]', '').ToLowerInvariant()
    if ($normalized -in @('live', 'realtime', 'reel', 'continuous', 'continu')) {
        return 'live'
    }

    return 'start-final'
}

function Test-LDLCTelemetryStartFinalOnly {
    return ((Get-LDLCTelemetryRemoteWriteMode) -eq 'start-final')
}

function Get-LDLCTelemetryNetworkTimeoutSeconds {
    $value = if (-not [string]::IsNullOrWhiteSpace($env:LDLC_TELEMETRY_TIMEOUT_SECONDS)) {
        [string]$env:LDLC_TELEMETRY_TIMEOUT_SECONDS
    }
    else {
        [string]$script:LDLCTelemetryNetworkTimeoutSeconds
    }

    try {
        return [math]::Min(60, [math]::Max(2, [int]$value))
    }
    catch {
        return 20
    }
}

function ConvertTo-LDLCTelemetryText {
    param(
        $Value,
        [int]$MaxLength = 4000
    )

    if ($null -eq $Value) {
        return ''
    }

    $text = [string]$Value
    $text = $text -replace "`0", ''
    $text = $text.Trim()

    if ($MaxLength -gt 0 -and $text.Length -gt $MaxLength) {
        return ($text.Substring(0, $MaxLength - 3) + '...')
    }

    return $text
}

function Get-LDLCComputerTelemetryInfo {
    $info = [ordered]@{
        ComputerName = [System.Environment]::MachineName
        UserName     = [System.Environment]::UserName
        UserDomain   = [System.Environment]::UserDomainName
        SerialNumber = ''
        Manufacturer = ''
        Model        = ''
        OSCaption    = ''
        OSVersion    = ''
        TimeZone     = ''
    }

    try {
        $bios = Get-CimInstance Win32_BIOS -ErrorAction Stop
        $info.SerialNumber = ConvertTo-LDLCTelemetryText $bios.SerialNumber 120
    }
    catch {}

    try {
        $computer = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        $info.Manufacturer = ConvertTo-LDLCTelemetryText $computer.Manufacturer 160
        $info.Model = ConvertTo-LDLCTelemetryText $computer.Model 160
    }
    catch {}

    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $info.OSCaption = ConvertTo-LDLCTelemetryText $os.Caption 180
        $info.OSVersion = ConvertTo-LDLCTelemetryText $os.Version 80
    }
    catch {}

    try {
        $info.TimeZone = ConvertTo-LDLCTelemetryText ([System.TimeZoneInfo]::Local.Id) 120
    }
    catch {}

    return [pscustomobject]$info
}

function Get-LDLCTelemetryQueueRoot {
    if (-not [string]::IsNullOrWhiteSpace($script:RuntimeRoot)) {
        try {
            if (-not (Test-Path -LiteralPath $script:RuntimeRoot)) {
                New-Item -ItemType Directory -Path $script:RuntimeRoot -Force | Out-Null
            }

            return $script:RuntimeRoot
        }
        catch {}
    }

    if (Get-Command Get-LDLCWritableRuntimeRoot -ErrorAction SilentlyContinue) {
        $runtimeRoot = Get-LDLCWritableRuntimeRoot
        if (-not [string]::IsNullOrWhiteSpace($runtimeRoot)) {
            return $runtimeRoot
        }
    }

    $candidates = New-Object System.Collections.Generic.List[string]

    if (-not [string]::IsNullOrWhiteSpace($env:ProgramData)) {
        [void]$candidates.Add((Join-Path $env:ProgramData 'LDLCPreparationPC'))
    }

    if (-not [string]::IsNullOrWhiteSpace($env:TEMP)) {
        [void]$candidates.Add((Join-Path $env:TEMP 'LDLCPreparationPC'))
    }

    try {
        $systemTemp = [System.IO.Path]::GetTempPath()
        if (-not [string]::IsNullOrWhiteSpace($systemTemp)) {
            [void]$candidates.Add((Join-Path $systemTemp 'LDLCPreparationPC'))
        }
    }
    catch {}

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }

        try {
            if (-not (Test-Path -LiteralPath $candidate)) {
                New-Item -ItemType Directory -Path $candidate -Force | Out-Null
            }

            return $candidate
        }
        catch {}
    }

    return $null
}

function Invoke-LDLCProgressOwnerLock {
    param([Parameter(Mandatory = $true)][scriptblock]$Action)
    if ([string]::IsNullOrWhiteSpace($script:LDLCProgressOwnerPath)) { return $false }
    $stream = $null
    try {
        # Claiming a new run and checking an old final write use the same lock.
        for ($attempt = 0; $attempt -lt 20 -and -not $stream; $attempt++) {
            try {
                $stream = [IO.File]::Open($script:LDLCProgressOwnerPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
            }
            catch [IO.IOException] {
                if ($attempt -ge 19) { throw }
                Start-Sleep -Milliseconds 25
            }
        }
        return (& $Action $stream)
    }
    catch {
        Write-LDLCLocalLog -Level 'INFO' -Text 'Proprietaire de progression indisponible ; progression finale conservee sans reecriture.'
        return $false
    }
    finally { if ($stream) { $stream.Dispose() } }
}

function Initialize-LDLCProgressOwner {
    param([Parameter(Mandatory = $true)][string]$RunId)
    $script:LDLCProgressOwnerPath = $null
    try {
        $root = Get-LDLCRuntimeRoot
        $script:LDLCProgressOwnerPath = Join-Path $root 'LDLC_PROGRESS_OWNER.json'
        [void](Invoke-LDLCProgressOwnerLock -Action {
            param($stream)
            $owner = [ordered]@{ RunId = $RunId; WorkerProcessId = $PID; WorkerStartTicks = [Diagnostics.Process]::GetCurrentProcess().StartTime.ToUniversalTime().Ticks }
            $bytes = [Text.Encoding]::UTF8.GetBytes(($owner | ConvertTo-Json -Compress))
            $stream.SetLength(0)
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Flush()
            return $true
        })
    }
    catch { Write-LDLCLocalLog -Level 'INFO' -Text 'Initialisation du proprietaire de progression indisponible.' }
}

function Write-LDLCFinalProgress {
    param([int]$Percent, [string]$Message)
    # A previous worker may still be sending its POST after Quitter released the UI.
    # It must not replace the progress of a preparation started in the meantime.
    [void](Invoke-LDLCProgressOwnerLock -Action {
        param($stream)
        if ($stream.Length -le 0 -or $stream.Length -gt 16384) { return $false }
        $bytes = New-Object byte[] ([int]$stream.Length)
        $offset = 0
        while ($offset -lt $bytes.Length) {
            $read = $stream.Read($bytes, $offset, $bytes.Length - $offset)
            if ($read -le 0) { return $false }
            $offset += $read
        }
        $owner = [Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json -ErrorAction Stop
        $startTicks = [Diagnostics.Process]::GetCurrentProcess().StartTime.ToUniversalTime().Ticks
        if ($owner.RunId -ne $script:LDLCTelemetryRunId -or $owner.WorkerProcessId -ne $PID -or $owner.WorkerStartTicks -ne $startTicks) { return $false }
        Write-ProgressFile $Percent $Message -IgnoreStopRequest
        return $true
    })
}

function Initialize-LDLCTelemetry {
    if ($script:LDLCTelemetryInitialized) {
        return
    }

    $script:LDLCTelemetryLastTransportFailure = $null

    $script:LDLCTelemetryRunId = if (-not [string]::IsNullOrWhiteSpace($env:LDLC_TELEMETRY_RUN_ID)) {
        ConvertTo-LDLCTelemetryText $env:LDLC_TELEMETRY_RUN_ID 80
    }
    else {
        [guid]::NewGuid().ToString('N')
    }
    # Auxiliary workers share the runtime but never own the main progress file.
    $auxiliaryWorker = ($WindowsUpdateWorker -or $SecurityCleanupWorker -or $SecurityIsolationSmokeTest -or $WorkerSmokeTest -or $SelfTest -or $BootstrapTest)
    if (-not $auxiliaryWorker) { Initialize-LDLCProgressOwner -RunId $script:LDLCTelemetryRunId }
    if (Test-LDLCTelemetryDisabled) {
        $script:LDLCTelemetryInitialized = $true
        $script:LDLCTelemetryDisabled = $true
        return
    }

    $script:LDLCTelemetryInitialized = $true
    $script:LDLCTelemetryStartedAt = if (-not [string]::IsNullOrWhiteSpace($env:LDLC_TELEMETRY_STARTED_AT)) {
        ConvertTo-LDLCTelemetryText $env:LDLC_TELEMETRY_STARTED_AT 80
    }
    else {
        Get-LDLCUtcTimestamp
    }
    $script:LDLCTelemetryLastUpdatedAt = $script:LDLCTelemetryStartedAt
    $script:LDLCTelemetryLastSentAt = [datetime]::MinValue
    $script:LDLCTelemetryLastAttemptAt = [datetime]::MinValue
    $script:LDLCTelemetryStopwatch = [Diagnostics.Stopwatch]::StartNew()
    $script:LDLCTelemetrySequence = 0
    $script:LDLCTelemetryFinishedAt = ''
    $script:LDLCTelemetryEvents = New-Object System.Collections.Generic.List[object]
    $script:LDLCTelemetryEventKeys = @{}
    $script:LDLCTelemetryCompletedSteps = New-Object System.Collections.Generic.List[string]
    $script:LDLCTelemetryCurrentStep = 'Initialisation'
    $script:LDLCTelemetryLastMessage = 'Execution demarree'
    $script:LDLCTelemetryProgressPercent = 0
    $script:LDLCTelemetryRunStatus = 'En cours'
    $script:LDLCTelemetrySending = $false
    $script:LDLCTelemetryCompleted = $false
    $script:LDLCTelemetryWorkflowCompleted = $null
    $script:LDLCTelemetryBlockingReason = ''
    $script:LDLCTelemetryComputerInfo = Get-LDLCComputerTelemetryInfo
    $script:LDLCTelemetryInitialRemoteAttempted = $false
    $script:LDLCTelemetryRemoteRequestCount = 0
    $script:LDLCTelemetrySuppressedRemoteUpdateCount = 0

    $queueRoot = Get-LDLCTelemetryQueueRoot
    if (-not [string]::IsNullOrWhiteSpace($queueRoot)) {
        $script:LDLCTelemetryQueuePath = Join-Path $queueRoot 'LDLC_ERROR_TELEMETRY_QUEUE.json'
    }

    Update-LDLCTelemetryRun -Status 'En cours' -Step 'Initialisation' -Message 'Execution demarree' -ProgressPercent 0 -Force
}

function Set-LDLCTelemetryStep {
    param(
        [string]$Step,
        [Nullable[int]]$ProgressPercent = $null,
        [switch]$Force
    )

    if ($script:LDLCTelemetryDisabled -or (Test-LDLCTelemetryDisabled)) {
        $script:LDLCTelemetryInitialized = $true
        $script:LDLCTelemetryDisabled = $true
        return
    }

    if ([string]::IsNullOrWhiteSpace($Step)) {
        return
    }

    if (-not $script:LDLCTelemetryInitialized) {
        Initialize-LDLCTelemetry
    }

    $cleanStep = ConvertTo-LDLCTelemetryText $Step 220
    $previousStep = ConvertTo-LDLCTelemetryText $script:LDLCTelemetryCurrentStep 220
    $changed = ($cleanStep -ne $previousStep)

    if ($changed -and -not [string]::IsNullOrWhiteSpace($previousStep) -and $previousStep -ne 'Initialisation') {
        $existing = @($script:LDLCTelemetryCompletedSteps.ToArray())
        if ($existing -notcontains $previousStep) {
            [void]$script:LDLCTelemetryCompletedSteps.Add($previousStep)
        }
    }

    $script:LDLCTelemetryCurrentStep = $cleanStep

    $updateParams = @{
        Step    = $cleanStep
        Message = $cleanStep
    }

    if ($null -ne $ProgressPercent) {
        $updateParams.ProgressPercent = [int]$ProgressPercent
    }

    if ($Force -or $changed) {
        $updateParams.Force = $true
    }

    Update-LDLCTelemetryRun @updateParams
}

function Test-LDLCTelemetryInformationalWarningMessage {
    param([Parameter(Mandatory = $true)][string]$Message)

    $normalized = ($Message -replace '[^\p{L}\p{Nd}\s]', ' ').ToLowerInvariant()
    $normalized = ($normalized -replace '\s+', ' ').Trim()

    if ($normalized -match '(erreur|echec|échec|impossible|non aboutie|non confirme|non confirmee|bloque|bloqué|timeout|delai|délai|suite a une erreur|suite à une erreur)') {
        return $false
    }

    return ($normalized -match '(deja present|déjà présent|deja presente|déjà présente|deja installe|déjà installé|installation longue ignoree|installation ignoree|ignoree volontairement|ignore volontairement|aucun gpu|aucune action|action non necessaire|verification reussie|verification ok|confirmee apres|confirmée après|lance en arriere plan|lancé en arrière plan)')
}

function Test-LDLCTelemetryReportableMessage {
    param(
        [Parameter(Mandatory = $true)][string]$Severity,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if ($Message -match 'LDLC_STOP_REQUESTED') {
        return $false
    }

    if ($Severity -in @('error', 'critical')) {
        return $true
    }

    # Les avertissements restent dans le log local, mais ne creent pas d'alerte
    # Sheet/dashboard. Seules les erreurs explicites error/critical comptent.
    if ($Severity -eq 'warning' -and $Message -match '(?i)^\[DEFAULT-APPS\]\[ERREUR\].*(Fenetre Parametres non active|Fenetre Parametres introuvable|non maximisee avant ouverture ms-settings|ms-settings:defaultapps)') {
        return $false
    }

    if ($Severity -eq 'warning' -and $Message -match '(?i)^Fenetre Parametres introuvable apres ouverture ms-settings\.?$') {
        return $false
    }

    return $false
}

function Get-LDLCErrorType {
    param(
        [string]$Message,
        [string]$Severity
    )

    if ($Message -match '(?i)(application|logiciel|adobe|chrome|7-zip|libreoffice|nvidia|amd).{0,90}(non installee|non installe|non confirmee|non confirme|introuvable|executable.{0,40}absent)|non confirmee apres installation|non confirme apres installation|executable principal introuvable') {
        return 'Application non installée ou non détectée'
    }

    if ($Message -match '(?i)winget|chocolatey|installation|installer|paquet|application|mise a jour|windows update|office|gpu|pilote') {
        return 'Erreur de traitement'
    }

    if ($Message -match '(?i)timeout|bloque|hresult|code retour|exception|powershell|com|processus|execution') {
        return 'Erreur technique'
    }

    if ($Message -match '(?i)ignore|non installee|introuvable|indisponible|impossible|echec') {
        return 'Action non aboutie'
    }

    if ($Severity -eq 'warning') {
        return 'Avertissement'
    }

    return 'Erreur technique'
}

function Add-LDLCTelemetryEvent {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('info', 'warning', 'error', 'critical')]
        [string]$Severity = 'error',
        [string]$Type,
        [string]$Step,
        [string]$Status,
        [string]$Details = '',
        [string[]]$Tags = @()
    )

    if ($script:LDLCTelemetryDisabled -or (Test-LDLCTelemetryDisabled)) {
        $script:LDLCTelemetryInitialized = $true
        $script:LDLCTelemetryDisabled = $true
        return
    }

    if ($script:LDLCTelemetrySending) {
        return
    }

    if (-not $script:LDLCTelemetryInitialized) {
        Initialize-LDLCTelemetry
    }

    $cleanMessage = ConvertTo-LDLCTelemetryText $Message 1800
    if ([string]::IsNullOrWhiteSpace($cleanMessage)) {
        return
    }

    $isReportableError = Test-LDLCTelemetryReportableMessage -Severity $Severity -Message $cleanMessage
    $isNonBlockingWarning = $Severity -eq 'warning' -and -not (Test-LDLCTelemetryInformationalWarningMessage -Message $cleanMessage)
    if ($Severity -eq 'warning' -and -not $isNonBlockingWarning) {
        return
    }

    if ($Severity -in @('error', 'critical') -and -not $isReportableError) {
        return
    }

    if ($Severity -notin @('warning', 'error', 'critical')) {
        return
    }

    if ([string]::IsNullOrWhiteSpace($Step)) {
        $Step = $script:LDLCTelemetryCurrentStep
    }

    if ([string]::IsNullOrWhiteSpace($Type)) {
        $Type = Get-LDLCErrorType -Message $cleanMessage -Severity $Severity
    }

    if ([string]::IsNullOrWhiteSpace($Status)) {
        $Status = if ($Severity -in @('critical', 'error')) { 'critique' } else { 'en_attente' }
    }

    $dedupeKey = @(
        (ConvertTo-LDLCTelemetryText $Step 220),
        (ConvertTo-LDLCTelemetryText $Type 120),
        $Severity,
        (ConvertTo-LDLCTelemetryText $Status 80),
        $cleanMessage
    ) -join '|'

    if ($script:LDLCTelemetryEventKeys -and $script:LDLCTelemetryEventKeys.ContainsKey($dedupeKey)) {
        return
    }

    $info = $script:LDLCTelemetryComputerInfo
    $event = [ordered]@{
        Timestamp    = Get-LDLCUtcTimestamp
        RunId        = $script:LDLCTelemetryRunId
        Source       = $script:LDLCTelemetrySource
        ApplicationSource = $script:LDLCTelemetryApplicationSource
        Edition      = $script:LDLCTelemetryEdition
        ToolVersion  = $script:LDLCTelemetryToolVersion
        ComputerName = $info.ComputerName
        UserName     = $info.UserName
        UserDomain   = $info.UserDomain
        SerialNumber = $info.SerialNumber
        Manufacturer = $info.Manufacturer
        Model        = $info.Model
        OSCaption    = $info.OSCaption
        OSVersion    = $info.OSVersion
        TimeZone     = $info.TimeZone
        Step         = ConvertTo-LDLCTelemetryText $Step 220
        Type         = ConvertTo-LDLCTelemetryText $Type 120
        Severity     = $Severity
        Status       = ConvertTo-LDLCTelemetryText $Status 80
        Message      = $cleanMessage
        Details      = ConvertTo-LDLCTelemetryText $Details 6000
        Tags         = @($Tags)
        Reportable   = [bool]$isReportableError
        ScriptPath   = ConvertTo-LDLCTelemetryText (Get-LDLCEntryPointPath) 800
    }

    [void]$script:LDLCTelemetryEvents.Add([pscustomobject]$event)
    if (-not $script:LDLCTelemetryEventKeys) {
        $script:LDLCTelemetryEventKeys = @{}
    }
    $script:LDLCTelemetryEventKeys[$dedupeKey] = $true

    Update-LDLCTelemetryRun -Message $cleanMessage -Force
}

function Get-LDLCTelemetryCounts {
    $events = @(if ($script:LDLCTelemetryEvents) { $script:LDLCTelemetryEvents.ToArray() })
    $warningCount = @($events | Where-Object { $_.Severity -eq 'warning' }).Count
    $errorCount = @($events | Where-Object { $_.Severity -in @('error', 'critical') }).Count
    $criticalCount = @($events | Where-Object { $_.Severity -eq 'critical' -or $_.Status -eq 'critique' }).Count

    return [pscustomobject]@{
        WarningCount  = $warningCount
        ErrorCount    = $errorCount
        CriticalCount = $criticalCount
        EventCount    = $events.Count
    }
}

function Read-LDLCQueuedTelemetryPayloads {
    if ([string]::IsNullOrWhiteSpace($script:LDLCTelemetryQueuePath)) { return @() }
    $paths = @()
    if (Test-Path -LiteralPath $script:LDLCTelemetryQueuePath) { $paths += $script:LDLCTelemetryQueuePath }
    $directory = Get-LDLCTelemetryOutboxDirectory
    if (Test-Path -LiteralPath $directory) {
        $paths += @(Get-ChildItem -LiteralPath $directory -Filter '*.json' -File | Sort-Object LastWriteTimeUtc | Select-Object -ExpandProperty FullName)
    }
    $payloads = foreach ($path in $paths) {
        try {
            $raw = [IO.File]::ReadAllText($path)
            if ($raw.Trim()) { $raw | ConvertFrom-Json -ErrorAction Stop }
        }
        catch { Write-LDLCLocalLog -Level 'INFO' -Text "File telemetrie illisible conservee : $path" }
    }
    return @(Merge-LDLCQueuedTelemetryPayloads -Payloads @($payloads))
}

function Get-LDLCTelemetryOutboxDirectory {
    return Join-Path (Split-Path -Parent $script:LDLCTelemetryQueuePath) 'telemetry-outbox'
}

function Get-LDLCTelemetryOutboxPath {
    param($Payload)
    $key = Get-LDLCTelemetryPayloadRunId -Payload $Payload
    if (-not $key) { $key = ConvertTo-Json -InputObject $Payload -Depth 14 -Compress }
    $hash = [Security.Cryptography.SHA256]::Create()
    try { $name = ([BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($key)))).Replace('-', '') }
    finally { $hash.Dispose() }
    return Join-Path (Get-LDLCTelemetryOutboxDirectory) ($name + '.json')
}

function Invoke-LDLCTelemetryOutboxLock {
    param([Parameter(Mandatory = $true)][string]$Path,
          [Parameter(Mandatory = $true)][scriptblock]$Action,
          [int]$TimeoutMilliseconds = 5000)
    # Only local read/merge/replace/delete operations run under this lock, never HTTP.
    # Keep one stable lock file: deleting it would let two processes lock different files.
    $lockPath = Join-Path (Split-Path -Parent $Path) '.outbox.lock'
    $deadline = [datetime]::UtcNow.AddMilliseconds([math]::Max(1, $TimeoutMilliseconds))
    $handle = $null
    try {
        while ($null -eq $handle) {
            try { $handle = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None) }
            catch [IO.IOException] {
                if ([datetime]::UtcNow -ge $deadline) { throw [TimeoutException]::new('File de telemetrie occupee; resultat conserve pour nouvel essai.') }
                Start-Sleep -Milliseconds 20
            }
        }
        return (& $Action)
    }
    finally { if ($handle) { $handle.Dispose() } }
}

function Write-LDLCQueuedTelemetryPayloads {
    param([object[]]$Payloads)

    if ([string]::IsNullOrWhiteSpace($script:LDLCTelemetryQueuePath)) {
        return $false
    }

    try {
        $queueDir = Get-LDLCTelemetryOutboxDirectory
        if ($queueDir -and -not (Test-Path -LiteralPath $queueDir)) {
            New-Item -ItemType Directory -Path $queueDir -Force | Out-Null
        }

        foreach ($payload in @(Merge-LDLCQueuedTelemetryPayloads -Payloads $Payloads)) {
            $path = Get-LDLCTelemetryOutboxPath -Payload $payload
            [void](Invoke-LDLCTelemetryOutboxLock -Path $path -Action {
                $previous = if (Test-Path -LiteralPath $path) { [IO.File]::ReadAllText($path) | ConvertFrom-Json } else { $null }
                $selected = @(Merge-LDLCQueuedTelemetryPayloads -Payloads @($previous, $payload))[-1]
                $json = ConvertTo-Json -InputObject $selected -Depth 14 -Compress
                $temporary = $path + '.new.' + [guid]::NewGuid().ToString('N')
                try {
                    [IO.File]::WriteAllText($temporary, $json, (New-Object Text.UTF8Encoding($false)))
                    if (Test-Path -LiteralPath $path) {
                        [IO.File]::Replace($temporary, $path, ($path + '.bak'))
                        Remove-Item -LiteralPath ($path + '.bak') -Force -ErrorAction SilentlyContinue
                    }
                    else { [IO.File]::Move($temporary, $path) }
                }
                finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force } }
            })
        }
        return $true
    }
    catch {
        Write-LDLCLocalLog -Level 'INFO' -Text "Ecriture file telemetrie impossible : $($_.Exception.Message)"
        return $false
    }
}

function Clear-LDLCQueuedTelemetryPayloads {
    param([object[]]$AcknowledgedPayloads)
    if ([string]::IsNullOrWhiteSpace($script:LDLCTelemetryQueuePath)) {
        return
    }

    foreach ($payload in @($AcknowledgedPayloads)) {
        $path = Get-LDLCTelemetryOutboxPath -Payload $payload
        try {
            if (Test-Path -LiteralPath (Split-Path -Parent $path)) {
                [void](Invoke-LDLCTelemetryOutboxLock -Path $path -Action {
                    if (Test-Path -LiteralPath $path) {
                        $json = ConvertTo-Json -InputObject $payload -Depth 14 -Compress
                        # Ne pas effacer une mise a jour plus recente que celle acquittee.
                        if ([IO.File]::ReadAllText($path).Trim() -eq $json) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
                    }
                })
            }
        }
        catch { Write-LDLCLocalLog -Level 'INFO' -Text 'Nettoyage file telemetrie differe; resultat conserve.' }
    }
    if (Test-Path -LiteralPath $script:LDLCTelemetryQueuePath) {
        try {
            $legacy = @([IO.File]::ReadAllText($script:LDLCTelemetryQueuePath) | ConvertFrom-Json)
            $ids = @($AcknowledgedPayloads | ForEach-Object { Get-LDLCTelemetryPayloadRunId $_ })
            $remaining = @($legacy | Where-Object { (Get-LDLCTelemetryPayloadRunId $_) -notin $ids })
            if ($remaining.Count -eq 0) { Remove-Item -LiteralPath $script:LDLCTelemetryQueuePath -Force }
        }
        catch {}
    }
}

function Get-LDLCTelemetryPayloadRunId {
    param($Payload)

    if (-not $Payload) {
        return ''
    }

    try {
        if ($Payload.Run -and $Payload.Run.RunId) {
            return [string]$Payload.Run.RunId
        }
    }
    catch {}

    try {
        if ($Payload.Execution -and $Payload.Execution.RunId) {
            return [string]$Payload.Execution.RunId
        }
    }
    catch {}

    return ''
}

function Merge-LDLCQueuedTelemetryPayloads {
    param([object[]]$Payloads)

    $merged = New-Object System.Collections.Generic.List[object]
    $indexes = @{}

    foreach ($payload in @($Payloads)) {
        if (-not $payload) {
            continue
        }

        $runId = Get-LDLCTelemetryPayloadRunId -Payload $payload
        if ([string]::IsNullOrWhiteSpace($runId)) {
            [void]$merged.Add($payload)
            continue
        }

        if ($indexes.ContainsKey($runId)) {
            $current = $merged[$indexes[$runId]]
            $oldRun = if ($current.Run) { $current.Run } else { $current.Execution }
            $newRun = if ($payload.Run) { $payload.Run } else { $payload.Execution }
            $oldFinal = Test-LDLCTelemetryPayloadFinal $oldRun
            $newFinal = Test-LDLCTelemetryPayloadFinal $newRun
            if ($oldFinal -and -not $newFinal) { continue }
            if ($oldFinal -eq $newFinal -and $oldRun.Sequence -and $newRun.Sequence -and [int64]$oldRun.Sequence -gt [int64]$newRun.Sequence) { continue }
            $merged[$indexes[$runId]] = $payload
        }
        else {
            $indexes[$runId] = $merged.Count
            [void]$merged.Add($payload)
        }
    }

    return @($merged.ToArray())
}

function Test-LDLCTelemetryPayloadFinal {
    param($Run)
    if ($Run.FinishedAt -or $Run.IsFinal -eq $true) { return $true }
    if ($Run.IsFinal -eq $false) { return $false }
    return ([string]$Run.Status -match '^(success|warning|failed|error|stopped|timeout|completed)$')
}

function SendOrQueue-LDLCTelemetryPayload {
    param([Parameter(Mandatory = $true)]$Payload)

    if ($script:LDLCTelemetryDisabled -or (Test-LDLCTelemetryDisabled)) {
        return $false
    }

    if (-not (Test-LDLCTelemetryConfigured)) {
        return $false
    }

    $queuedPayloads = @(Read-LDLCQueuedTelemetryPayloads)
    $payloads = @(Merge-LDLCQueuedTelemetryPayloads -Payloads ($queuedPayloads + @($Payload)))
    # Persister avant le POST : un crash ou une coupure ne doit pas perdre la fin.
    $script:LDLCTelemetryLastQueueSaved = Write-LDLCQueuedTelemetryPayloads -Payloads $payloads
    # A previous outage must not make this final report wait behind an unbounded
    # archive of other preparations. Only acknowledged members are removed.
    $batch = @(Get-LDLCTelemetrySendBatch -Payloads $payloads -CurrentPayload $Payload)

    try {
        $script:LDLCTelemetrySending = $true
        Send-LDLCTelemetryPayloads -Payloads $batch
        Clear-LDLCQueuedTelemetryPayloads -AcknowledgedPayloads $batch
        $script:LDLCTelemetryLastSentAt = [datetime]::UtcNow
        return $true
    }
    catch {
        $script:LDLCTelemetryLastQueueSaved = Write-LDLCQueuedTelemetryPayloads -Payloads $payloads
        return $false
    }
    finally {
        $script:LDLCTelemetrySending = $false
    }
}

function Update-LDLCTelemetryRun {
    param(
        [string]$Status,
        [string]$Step,
        [string]$Message,
        [Nullable[int]]$ProgressPercent = $null,
        [switch]$Final,
        [switch]$Force
    )

    if ($script:LDLCTelemetryDisabled -or (Test-LDLCTelemetryDisabled)) {
        $script:LDLCTelemetryInitialized = $true
        $script:LDLCTelemetryDisabled = $true
        return
    }

    if ($script:LDLCTelemetrySending) {
        return
    }

    if (-not $script:LDLCTelemetryInitialized) {
        Initialize-LDLCTelemetry
        return
    }

    if ($script:LDLCTelemetryCompleted -and -not $Final) {
        return
    }

    if (-not [string]::IsNullOrWhiteSpace($Status)) {
        $script:LDLCTelemetryRunStatus = Convert-LDLCTelemetryRunStatus -Status $Status -Counts (Get-LDLCTelemetryCounts) -Final:$Final
    }
    elseif ([string]::IsNullOrWhiteSpace($script:LDLCTelemetryRunStatus)) {
        $script:LDLCTelemetryRunStatus = 'En cours'
    }

    if (-not [string]::IsNullOrWhiteSpace($Step)) {
        $script:LDLCTelemetryCurrentStep = ConvertTo-LDLCTelemetryText $Step 220
    }

    if (-not [string]::IsNullOrWhiteSpace($Message)) {
        $script:LDLCTelemetryLastMessage = ConvertTo-LDLCTelemetryText $Message 1200
    }

    if ($null -ne $ProgressPercent) {
        $script:LDLCTelemetryProgressPercent = [int][math]::Max(0, [math]::Min(100, [int]$ProgressPercent))
    }

    $now = [datetime]::UtcNow
    $script:LDLCTelemetryLastUpdatedAt = $now.ToString('o')

    $shouldSend = $false
    if ($Final) {
        $shouldSend = $true
    }
    elseif (Test-LDLCTelemetryStartFinalOnly) {
        if (-not $script:LDLCTelemetryInitialRemoteAttempted) {
            $script:LDLCTelemetryInitialRemoteAttempted = $true
            $shouldSend = $true
        }
        else {
            $script:LDLCTelemetrySuppressedRemoteUpdateCount++
        }
    }
    else {
        $elapsedSeconds = if ($script:LDLCTelemetryLastAttemptAt -eq [datetime]::MinValue) {
            [double]::PositiveInfinity
        }
        else {
            ($now - $script:LDLCTelemetryLastAttemptAt).TotalSeconds
        }

        if (-not $script:LDLCTelemetryInitialRemoteAttempted -or $elapsedSeconds -ge $script:LDLCTelemetryUpdateIntervalSeconds) {
            $script:LDLCTelemetryInitialRemoteAttempted = $true
            $shouldSend = $true
        }
    }

    if (-not $shouldSend) {
        return
    }

    $payload = New-LDLCTelemetryPayload -ResultStatus $script:LDLCTelemetryRunStatus -Final:$Final
    $script:LDLCTelemetryLastAttemptAt = $now
    [void](SendOrQueue-LDLCTelemetryPayload -Payload $payload)
}

function New-LDLCTelemetryPayload {
    param(
        [string]$ResultStatus,
        [switch]$Final
    )

    $counts = Get-LDLCTelemetryCounts
    $now = Get-LDLCUtcTimestamp
    $finishedAt = if ($Final) {
        if ([string]::IsNullOrWhiteSpace($script:LDLCTelemetryFinishedAt)) { $script:LDLCTelemetryFinishedAt = $now }
        $script:LDLCTelemetryFinishedAt
    } else { '' }

    if ([string]::IsNullOrWhiteSpace($ResultStatus)) {
        $ResultStatus = if ($Final) { 'success' } else { $script:LDLCTelemetryRunStatus }
    }

    $ResultStatus = Convert-LDLCTelemetryRunStatus -Status $ResultStatus -Counts $counts -Final:$Final

    $startedDate = [datetime]::Parse($script:LDLCTelemetryStartedAt).ToUniversalTime()
    $currentDate = [datetime]::Parse($now).ToUniversalTime()
    $durationSeconds = [int][math]::Max(0, [math]::Round(($currentDate - $startedDate).TotalSeconds))
    if ($script:LDLCTelemetryStopwatch) {
        $durationSeconds = [int][math]::Round($script:LDLCTelemetryStopwatch.Elapsed.TotalSeconds)
    }
    $script:LDLCTelemetrySequence++
    $info = $script:LDLCTelemetryComputerInfo

    $run = [ordered]@{
        RunId           = $script:LDLCTelemetryRunId
        Source          = $script:LDLCTelemetrySource
        ApplicationSource = $script:LDLCTelemetryApplicationSource
        Edition         = $script:LDLCTelemetryEdition
        ToolVersion     = $script:LDLCTelemetryToolVersion
        StartedAt       = $script:LDLCTelemetryStartedAt
        FinishedAt      = $finishedAt
        DurationSeconds = $durationSeconds
        Status          = $ResultStatus
        CurrentStep     = ConvertTo-LDLCTelemetryText $script:LDLCTelemetryCurrentStep 220
        CompletedSteps  = (@($script:LDLCTelemetryCompletedSteps.ToArray()) -join ' | ')
        LastMessage     = ConvertTo-LDLCTelemetryText $script:LDLCTelemetryLastMessage 1200
        LastUpdatedAt   = $script:LDLCTelemetryLastUpdatedAt
        LastHeartbeatAt = $now
        ProgressPercent = [int][math]::Max(0, [math]::Min(100, $script:LDLCTelemetryProgressPercent))
        IsFinal         = [bool]$Final
        Sequence        = $script:LDLCTelemetrySequence
        WarningDetails  = (@($script:LDLCTelemetryEvents | Where-Object Severity -eq 'warning' | ForEach-Object { '{0}: {1}' -f $_.Step, $_.Message }) -join ' | ')
        CompletionConfirmed = $script:LDLCTelemetryWorkflowCompleted
        BlockingReason  = $script:LDLCTelemetryBlockingReason
        ErrorCount      = $counts.ErrorCount
        WarningCount    = $counts.WarningCount
        CriticalCount   = $counts.CriticalCount
        EventCount      = $counts.EventCount
        ComputerName    = $info.ComputerName
        UserName        = $info.UserName
        UserDomain      = $info.UserDomain
        SerialNumber    = $info.SerialNumber
        Manufacturer    = $info.Manufacturer
        Model           = $info.Model
        OSCaption       = $info.OSCaption
        OSVersion       = $info.OSVersion
        TimeZone        = $info.TimeZone
        ScriptPath      = ConvertTo-LDLCTelemetryText (Get-LDLCEntryPointPath) 800
    }

    $events = @(if ($script:LDLCTelemetryEvents) { $script:LDLCTelemetryEvents.ToArray() })
    $reportableEvents = @($events | Where-Object { $_.Severity -in @('error', 'critical') })

    return [pscustomobject]@{
        Run    = [pscustomobject]$run
        # Les avertissements influencent le statut de l'execution, mais ne
        # doivent pas etre inseres dans la feuille des erreurs reelles.
        Events = $reportableEvents
    }
}

function Get-LDLCTelemetrySendBatch {
    param([object[]]$Payloads, $CurrentPayload, [int]$MaxCount = 10, [int]$MaxBytes = 524288)
    $currentId = Get-LDLCTelemetryPayloadRunId $CurrentPayload
    $ordered = if ($currentId) {
        @($Payloads | Where-Object { (Get-LDLCTelemetryPayloadRunId $_) -eq $currentId }) +
        @($Payloads | Where-Object { (Get-LDLCTelemetryPayloadRunId $_) -ne $currentId })
    } else { @($CurrentPayload) + @($Payloads | Where-Object { $_ -ne $CurrentPayload }) }
    $selected = New-Object 'Collections.Generic.List[object]'
    $bytes = 0
    foreach ($item in $ordered) {
        $size = [Text.Encoding]::UTF8.GetByteCount((ConvertTo-Json -InputObject $item -Depth 14 -Compress))
        if ($selected.Count -and ($selected.Count -ge $MaxCount -or $bytes + $size -gt $MaxBytes)) { break }
        $selected.Add($item); $bytes += $size
    }
    return @($selected.ToArray())
}

function Get-LDLCTelemetryTransportFailure {
    param($ErrorRecord)
    $exception = $ErrorRecord.Exception
    if ($exception.Data['LDLCTelemetryFailure']) { return $exception.Data['LDLCTelemetryFailure'] }
    $current = $exception; $http = $null; $network = ''
    while ($current) {
        try { if ($current.Response) { $http = [int]$current.Response.StatusCode } } catch {}
        if ($current -is [Net.WebException]) { $network = [string]$current.Status }
        $current = $current.InnerException
    }
    $code = 'TransportUnknown'; $message = 'Echec de transmission non identifie ; consulter le journal local.'; $transient = $false
    if ($http -in @(401,403)) { $code='HttpAuthorization'; $message="Acces au serveur refuse (HTTP $http). Verifier le deploiement ou le proxy." }
    elseif ($http -in @(408,429,500,502,503,504)) { $code='HttpTransient'; $message="Serveur temporairement indisponible (HTTP $http)."; $transient=$true }
    elseif ($http) { $code='HttpError'; $message="Serveur en erreur HTTP $http." }
    elseif ($network -eq 'Timeout' -or $exception.GetType().Name -match 'Timeout|TaskCanceled') { $code='Timeout'; $message='Delai de transmission au serveur depasse.'; $transient=$true }
    elseif ($network -in @('NameResolutionFailure','ProxyNameResolutionFailure')) { $code='Dns'; $message='Adresse du serveur ou du proxy introuvable (DNS).'; $transient=$true }
    elseif ($network -in @('ConnectFailure','ConnectionClosed','KeepAliveFailure','ReceiveFailure','SendFailure')) { $code='Connection'; $message='Connexion au serveur interrompue ou impossible.'; $transient=$true }
    elseif ($network -in @('TrustFailure','SecureChannelFailure')) { $code='Tls'; $message='Connexion HTTPS refusee : certificat ou protocole TLS a verifier.' }
    return [pscustomobject]@{ Code=$code; Message=$message; HttpStatus=$http; Transient=$transient }
}

function Send-LDLCTelemetryPayloads {
    param([object[]]$Payloads)

    $endpointUrl = Get-LDLCTelemetryEndpointUrl
    $apiKey = Get-LDLCTelemetryApiKey

    $body = @{
        apiKey   = $apiKey
        sentAt   = Get-LDLCUtcTimestamp
        payloads = @($Payloads)
    } | ConvertTo-Json -Depth 14 -Compress

    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    $script:LDLCTelemetryLastTransportFailure = $null
    for ($attempt=1; $attempt -le 2; $attempt++) {
        try {
            $script:LDLCTelemetryRemoteRequestCount++
            $response = Invoke-RestMethod -Uri $endpointUrl -Method Post -ContentType 'application/json; charset=utf-8' -Body $body -TimeoutSec (Get-LDLCTelemetryNetworkTimeoutSeconds) -ErrorAction Stop
            $failure = $null
            if (-not $response -or $response.ok -ne $true) {
                $serverError = [string]$response.error
                $failure = [pscustomobject]@{ Code='InvalidAcknowledgement'; Message='Le serveur ne renvoie pas un accuse JSON valide.'; HttpStatus=200; Transient=$false }
                if ($serverError -eq 'unauthorized') { $failure.Code='IngestAuthorization'; $failure.Message='Cle d envoi refusee par le serveur.' }
                elseif ($serverError -match '(?i)lock|verrou') { $failure.Code='ServerBusy'; $failure.Message='Google Sheets occupe : verrou serveur indisponible.'; $failure.Transient=$true }
                elseif ($serverError -match '(?i)quota|too many|rate.limit') { $failure.Code='ServerQuota'; $failure.Message='Quota Google Apps Script ou Sheets atteint.'; $failure.Transient=$true }
                elseif ($serverError -match '(?i)timeout|timed.out|execution.time') { $failure.Code='ServerTimeout'; $failure.Message='Temps d execution du serveur Google depasse.'; $failure.Transient=$true }
                elseif ($response -is [string] -and $response -match '(?i)<html|<!doctype') { $failure.Code='HtmlResponse'; $failure.Message='Page HTML recue au lieu de JSON : connexion Google ou deploiement a verifier.' }
            } elseif ($null -ne $response.payloads -and [int]$response.payloads -ne @($Payloads).Count) {
                $failure = [pscustomobject]@{ Code='IncompleteAcknowledgement'; Message='Accuse serveur incomplet : nombre de rapports incorrect.'; HttpStatus=200; Transient=$false }
            }
            if ($failure) { $transportException = New-Object InvalidOperationException $failure.Message; $transportException.Data['LDLCTelemetryFailure']=$failure; throw $transportException }
            $script:LDLCTelemetryLastTransportFailure=$null
            return
        } catch {
            $failure=Get-LDLCTelemetryTransportFailure $_
            $script:LDLCTelemetryLastTransportFailure=$failure
            if (Get-Command Write-LDLCLocalLog -ErrorAction SilentlyContinue) { Write-LDLCLocalLog -Level 'INFO' -Text ("Transmission rapport : {0}, HTTP={1}, tentative={2}/2. {3}" -f $failure.Code,$failure.HttpStatus,$attempt,$failure.Message) }
            if (-not $failure.Transient -or $attempt -eq 2) { throw [InvalidOperationException]::new($failure.Message) }
            Start-Sleep -Milliseconds 500
        }
    }
}

function Test-LDLCFinalizationReady {
    param([string]$RuntimeRoot, [int]$WorkerProcessId, [long]$WorkerStartTicks)
    if ($WorkerProcessId -le 0 -or $WorkerStartTicks -le 0 -or [string]::IsNullOrWhiteSpace($RuntimeRoot)) { return $false }
    try {
        $receipt = [IO.File]::ReadAllText((Join-Path $RuntimeRoot 'LDLC_FINALIZATION.json')) | ConvertFrom-Json
        return ($receipt.WorkerProcessId -eq $WorkerProcessId -and $receipt.WorkerStartTicks -eq $WorkerStartTicks -and $receipt.PayloadSaved -eq $true -and
            $receipt.IsFinal -eq $true -and -not [string]::IsNullOrWhiteSpace($receipt.RunId) -and
            -not [string]::IsNullOrWhiteSpace($receipt.FinishedAt))
    }
    catch { return $false }
}

function Publish-LDLCFinalizationReceipt {
    param($Payload, [bool]$PayloadSaved)
    # Ce point est atteint apres les derniers changements systeme et la sauvegarde
    # durable du resultat. Quitter peut alors laisser uniquement le POST se terminer.
    if (-not $PayloadSaved) { return }
    try {
        $path = Join-Path (Get-LDLCRuntimeRoot) 'LDLC_FINALIZATION.json'
        $temporary = $path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
        $receipt = [ordered]@{ WorkerProcessId = $PID; WorkerStartTicks = [Diagnostics.Process]::GetCurrentProcess().StartTime.ToUniversalTime().Ticks; RunId = $Payload.Run.RunId
            IsFinal = $Payload.Run.IsFinal; FinishedAt = $Payload.Run.FinishedAt; PayloadSaved = $true }
        [IO.File]::WriteAllText($temporary, ($receipt | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $temporary -Destination $path -Force
    }
    catch { Write-Host '[INFO] Accuse local de finalisation indisponible.' }
    finally { if ($temporary -and (Test-Path -LiteralPath $temporary)) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue } }
}

function Complete-LDLCTelemetryRun {
    param([string]$ResultStatus = 'stopped', [Nullable[bool]]$WorkflowCompleted = $null)

    if ($script:LDLCTelemetryDisabled -or (Test-LDLCTelemetryDisabled)) {
        $script:LDLCTelemetryInitialized = $true
        $script:LDLCTelemetryDisabled = $true
        return
    }

    if ($script:LDLCTelemetryCompleted) {
        return
    }

    if (-not $script:LDLCTelemetryInitialized) {
        Initialize-LDLCTelemetry
    }

    $counts = Get-LDLCTelemetryCounts

    $script:LDLCTelemetryWorkflowCompleted = $WorkflowCompleted
    if ($null -ne $WorkflowCompleted -and -not $WorkflowCompleted -and $ResultStatus -notin @('stopped', 'timeout', 'failed')) {
        $ResultStatus = 'stopped'
    }

    if (-not $script:LDLCTelemetrySendSuccessfulRuns -and $counts.EventCount -eq 0) {
        return
    }

    $script:LDLCTelemetryRunStatus = Convert-LDLCTelemetryRunStatus -Status $ResultStatus -Counts $counts -Final
    $displayStatus = Convert-LDLCTelemetryRunStatusDisplayText -Status $script:LDLCTelemetryRunStatus
    $causes = @($script:LDLCTelemetryEvents | Where-Object Severity -in @('error', 'critical', 'warning') | ForEach-Object { '{0}: {1}' -f $_.Step, $_.Message })
    if ($script:LDLCTelemetryRunStatus -eq 'success') { $reason = '' }
    elseif ($script:LDLCTelemetryRunStatus -eq 'timeout') { $reason = "Delai depasse a l'etape : $($script:LDLCTelemetryCurrentStep). " + ($causes -join ' | ') }
    elseif ($causes.Count -gt 0) { $reason = $causes -join ' | ' }
    elseif ($script:LDLCTelemetryRunStatus -eq 'stopped') { $reason = "Intervention incomplete ou interrompue a l'etape : $($script:LDLCTelemetryCurrentStep)." }
    else { $reason = "$displayStatus a l'etape : $($script:LDLCTelemetryCurrentStep). $($script:LDLCTelemetryLastMessage)" }
    $script:LDLCTelemetryBlockingReason = ConvertTo-LDLCTelemetryText $reason 6000
    $script:LDLCTelemetryLastMessage = if ($reason) { "Validation bloquee : $reason" } else { 'Preparation terminee : validation automatique.' }
    if ($script:LDLCTelemetryProgressPercent -lt 100 -and $script:LDLCTelemetryRunStatus -in @('success', 'warning')) {
        $script:LDLCTelemetryProgressPercent = 100
    }

    $script:LDLCTelemetryLastUpdatedAt = Get-LDLCUtcTimestamp
    if ($script:LDLCTelemetryStopwatch) { $script:LDLCTelemetryStopwatch.Stop() }
    $payload = New-LDLCTelemetryPayload -ResultStatus $script:LDLCTelemetryRunStatus -Final
    $script:LDLCTelemetryCompleted = $true

    $saved = Write-LDLCQueuedTelemetryPayloads -Payloads @($payload)
    $script:LDLCTelemetryLastQueueSaved = [bool]$saved
    Publish-LDLCFinalizationReceipt -Payload $payload -PayloadSaved ([bool]$saved)
    if ($null -ne $WorkflowCompleted) {
        $percent = if ($WorkflowCompleted) { 100 } else { [math]::Min(99, $script:LDLCTelemetryProgressPercent) }
        $message = if ($reason) { $script:LDLCTelemetryLastMessage } else { 'Preparation terminee. Transmission de la validation...' }
        Write-LDLCFinalProgress $percent $message
    }

    if (SendOrQueue-LDLCTelemetryPayload -Payload $payload) {
        Write-Host "[INFO] Telemetrie LDLC envoyee vers Google Sheets." -ForegroundColor DarkCyan
        if ($null -ne $WorkflowCompleted) { Write-LDLCFinalProgress $percent $script:LDLCTelemetryLastMessage }
    }
    elseif ($script:LDLCTelemetryLastQueueSaved) {
        Write-Host "[INFO] Telemetrie LDLC non envoyee, sauvegardee pour un prochain essai." -ForegroundColor DarkCyan
        $cause = if ($script:LDLCTelemetryLastTransportFailure) { $script:LDLCTelemetryLastTransportFailure.Message } else { 'Envoi au serveur non acquitte.' }
        if ($null -ne $WorkflowCompleted) { Write-LDLCFinalProgress $percent ("Transmission non confirmee : $cause Resultat sauvegarde, nouvel envoi au prochain lancement.") }
    }
    else {
        Write-Host '[INFO] Telemetrie non envoyee et sauvegarde locale impossible; consulter le journal local.' -ForegroundColor Yellow
        if ($null -ne $WorkflowCompleted) { Write-LDLCFinalProgress $percent 'Validation non transmise : sauvegarde locale impossible. Consulter le journal.' }
    }
}

# endregion Module: 05.Telemetry.ps1








# region Module: 10.InitialSetup.ps1
# Initial workstation preparation steps.

function Invoke-LDLCInitialSetup {
param(
    [int]$InternetProgressPercent = 0,
    [int]$PowerProgressPercent = 1,
    [int]$TimeProgressPercent = 10
)

Wait-LDLCInternetConnection -ProgressPercent $InternetProgressPercent | Out-Null

Write-Section "ETAPES INITIALES"

Stop-IfRequested
Write-ProgressFile $PowerProgressPercent "Désactivation de la veille..."
Write-Step "Desactivation de la veille secteur et batterie..."
Start-Sleep -Milliseconds 250

try {
    $hasBattery = Test-LDLCBatteryPresent

    $script:OriginalMonitorTimeoutAC = TryGet-LDLCPowerSettingIndex -SubGroupAlias SUB_VIDEO -SettingAlias VIDEOIDLE -PowerSource AC
    $script:OriginalStandbyTimeoutAC = TryGet-LDLCPowerSettingIndex -SubGroupAlias SUB_SLEEP -SettingAlias STANDBYIDLE -PowerSource AC

    if ($hasBattery) {
        $script:OriginalMonitorTimeoutDC = TryGet-LDLCPowerSettingIndex -SubGroupAlias SUB_VIDEO -SettingAlias VIDEOIDLE -PowerSource DC
        $script:OriginalStandbyTimeoutDC = TryGet-LDLCPowerSettingIndex -SubGroupAlias SUB_SLEEP -SettingAlias STANDBYIDLE -PowerSource DC
    }
    else {
        $script:OriginalMonitorTimeoutDC = $null
        $script:OriginalStandbyTimeoutDC = $null
    }

    $script:PowerSettingsCaptured = $true
    $script:PowerSettingsRestored = $false

    $disableResults = @()
    $disableResults += Invoke-LDLCPowerCfgChange -SettingName "monitor-timeout-ac" -Value 0 -Label "ecran AC"
    $disableResults += Invoke-LDLCPowerCfgChange -SettingName "standby-timeout-ac" -Value 0 -Label "veille AC"

    if ($hasBattery) {
        $disableResults += Invoke-LDLCPowerCfgChange -SettingName "monitor-timeout-dc" -Value 0 -Label "ecran DC"
        $disableResults += Invoke-LDLCPowerCfgChange -SettingName "standby-timeout-dc" -Value 0 -Label "veille DC"
    }
    else {
        Write-Step "Aucune batterie detectee : delais DC ignores."
    }

    if ($disableResults -contains $false) {
        Write-Warn "Desactivation de la veille appliquee partiellement."
    }
    else {
        Write-Ok "Veille desactivee."
    }
}
catch {
    Write-Err "Erreur lors de la desactivation de la veille : $($_.Exception.Message)"
}

Stop-IfRequested
Write-ProgressFile $TimeProgressPercent "Synchronisation date et heure..."
Write-Step "Configuration de la date et de l'heure..."

try {
    Set-Service w32time -StartupType Automatic
    Start-Service w32time -ErrorAction SilentlyContinue

    reg add "HKLM\SYSTEM\CurrentControlSet\Services\tzautoupdate" /v Start /t REG_DWORD /d 3 /f | Out-Null
    tzutil /s "Romance Standard Time"

    w32tm /config /syncfromflags:manual /manualpeerlist:"time.windows.com,0x9" /update | Out-Null
    Restart-Service w32time
    w32tm /resync /force | Out-Null

    Write-Ok "Date et heure configurees et synchronisees."
}
catch {
    Write-Err "Erreur lors de la configuration date/heure : $($_.Exception.Message)"
}}

# endregion Module: 10.InitialSetup.ps1

# region Module: 20.WindowsLayout.ps1
# Windows layout customization.

function Set-LDLCWindowsLayout {
    param(
        [int]$ProgressPercent = 15
    )

    Stop-IfRequested
    Write-Section "PERSONNALISATION WINDOWS"
    Write-ProgressFile $ProgressPercent "Personnalisation du bureau..."

    try {
        $ws = New-Object -ComObject WScript.Shell
        $shell = New-Object -ComObject Shell.Application
    }
    catch {
        Write-Warn "Impossible d'initialiser les objets COM : $($_.Exception.Message)"
        return
    }

    function Test-LDLCTaskbarItemMatch {
        param(
            [Parameter(Mandatory = $true)]$Item,
            [string[]]$ExactNames = @(),
            [string[]]$NamePatterns = @(),
            [string[]]$PathPatterns = @()
        )

        $candidateName = ""
        $candidatePath = ""

        try { $candidateName = [string]$Item.Name } catch {}
        try { $candidatePath = [string]$Item.Path } catch {}

        foreach ($exactName in $ExactNames) {
            if ($candidateName -ieq $exactName) {
                return $true
            }
        }

        foreach ($pattern in $NamePatterns) {
            if ($candidateName -like $pattern) {
                return $true
            }
        }

        foreach ($pattern in $PathPatterns) {
            if ($candidatePath -like $pattern) {
                return $true
            }
        }

        return $false
    }

    function Get-LDLCTaskbarItem {
        param(
            [string[]]$ExactNames = @(),
            [string[]]$NamePatterns = @(),
            [string[]]$PathPatterns = @()
        )

        # AppsFolder contains installed applications, including those no longer
        # pinned. Check persisted pins first, then the actual Unpin shell verb.
        $pinFolder = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'
        if (Test-Path -LiteralPath $pinFolder -PathType Container) {
            $pinNamespace = $shell.Namespace($pinFolder)
            if (-not $pinNamespace) { throw 'Lecture des raccourcis epingles impossible.' }
            foreach ($candidate in @($pinNamespace.Items())) {
                if (Test-LDLCTaskbarItemMatch -Item $candidate -ExactNames $ExactNames -NamePatterns $NamePatterns -PathPatterns $PathPatterns) {
                    return $candidate
                }
            }
        }

        $appsNamespace = $shell.Namespace("shell:::{4234d49b-0245-4df3-b780-3893943456e1}")
        if (-not $appsNamespace) { throw 'Lecture des applications Windows impossible.' }
        $items = @($appsNamespace.Items())

        foreach ($candidate in $items) {
            if (Test-LDLCTaskbarItemMatch -Item $candidate -ExactNames $ExactNames -NamePatterns $NamePatterns -PathPatterns $PathPatterns) {
                foreach ($verb in @($candidate.Verbs())) {
                    $verbName = ([string]$verb.Name).Replace('&', '').Normalize([Text.NormalizationForm]::FormD)
                    $verbName = ($verbName -replace '\p{Mn}', '').Trim()
                    if ($verbName -match '^(taskbarunpin|unpin from taskbar|detacher de la barre des taches|desepingler de la barre des taches)$') {
                        return $candidate
                    }
                }
            }
        }

        return $null
    }

    function Wait-LDLCTaskbarItemAbsent {
        param(
            [string[]]$ExactNames = @(),
            [string[]]$NamePatterns = @(),
            [string[]]$PathPatterns = @(),
            [int]$TimeoutSeconds = 4
        )

        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

        do {
            Stop-IfRequested

            if (-not (Get-LDLCTaskbarItem -ExactNames $ExactNames -NamePatterns $NamePatterns -PathPatterns $PathPatterns)) {
                return $true
            }

            Start-Sleep -Milliseconds 100
        }
        while ((Get-Date) -lt $deadline)

        return $false
    }

    function Remove-LDLCTaskbarPins {
        param(
            [string[]]$ExactNames = @(),
            [string[]]$NamePatterns = @(),
            [string[]]$PathPatterns = @(),
            [Parameter(Mandatory = $true)][string]$ProgressMessage,
            [Parameter(Mandatory = $true)][int]$ProgressPercent,
            [Parameter(Mandatory = $true)][string]$Label
        )

        Stop-IfRequested

        $itemToRemove = Get-LDLCTaskbarItem -ExactNames $ExactNames -NamePatterns $NamePatterns -PathPatterns $PathPatterns

        if (-not $itemToRemove) {
            Write-Step "Aucune epingle $Label detectee dans la barre des taches."
            return $false
        }

        Write-ProgressFile $ProgressPercent $ProgressMessage
        Start-Sleep -Milliseconds 100

        try {
            $removedLabel = [string]$itemToRemove.Name
            $itemToRemove.InvokeVerb("taskbarunpin")
            Start-Sleep -Milliseconds 200
            Refresh-Desktop

            if (Wait-LDLCTaskbarItemAbsent -ExactNames $ExactNames -NamePatterns $NamePatterns -PathPatterns $PathPatterns -TimeoutSeconds 4) {
                Write-Ok "Element retire de la barre des taches : $removedLabel"
                return $true
            }

            if ($Label -notin @("Copilot", "Microsoft Store")) {
                Write-Warn "$Label semble toujours present apres la tentative de retrait."
            }
            return $false
        }
        catch {
            if (Test-LDLCStopRequestError $_) { throw }
            Write-Warn "Impossible de retirer de la barre des taches : $([string]$itemToRemove.Name)"
            return $false
        }
    }

    Write-Step "Suppression raccourcis Edge..."

    $paths = @(
        [Environment]::GetFolderPath("Desktop"),
        [Environment]::GetFolderPath("CommonDesktopDirectory"),
        "$env:USERPROFILE\OneDrive\Desktop"
    )

    foreach ($path in $paths) {
        Stop-IfRequested

        if (Test-Path $path) {
            Get-ChildItem "$path\*.lnk" -ErrorAction SilentlyContinue | ForEach-Object {
                try {
                    $target = $ws.CreateShortcut($_.FullName).TargetPath
                    if ($target -like "*msedge*" -or $_.Name -like "*Edge*") {
                        Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
                        Write-Ok "Raccourci Edge supprime : $($_.FullName)"
                    }
                }
                catch {}
            }
        }
    }

    Write-Step "Suppression Edge / Microsoft Store / Copilot de la barre des taches..."

    try {
        [void](Remove-LDLCTaskbarPins -ExactNames @("Microsoft Edge", "Edge") -NamePatterns @("*Edge*") -PathPatterns @("*msedge.exe*") -ProgressMessage "Suppression Edge barre des taches..." -ProgressPercent 18 -Label "Edge")

        if (Get-Process -Name "msedge" -ErrorAction SilentlyContinue) {
            Write-Info "Edge est encore ouvert : une fenetre active peut afficher son icone meme apres desepinglage."
        }

        [void](Remove-LDLCTaskbarPins -ExactNames @("Copilot") -NamePatterns @("*Copilot*") -ProgressMessage "Suppression Copilot barre des taches..." -ProgressPercent 20 -Label "Copilot")

        [void](Remove-LDLCTaskbarPins -ExactNames @("Microsoft Store") -NamePatterns @("*Microsoft Store*") -PathPatterns @("*WinStore*") -ProgressMessage "Suppression Microsoft Store barre des taches..." -ProgressPercent 22 -Label "Microsoft Store")

    }
    catch {
        if (Test-LDLCStopRequestError $_) { throw }
        Write-Warn "Impossible de modifier la barre des taches : $($_.Exception.Message)"
    }

    try {
        Refresh-Desktop
    }
    catch {
        if (Test-LDLCStopRequestError $_) { throw }
        Write-Warn "Impossible d'actualiser le bureau apres modification de la barre des taches : $($_.Exception.Message)"
    }

    Write-ProgressFile 23 "Personnalisation Windows terminée."
}

# endregion Module: 20.WindowsLayout.ps1

# region Module: 30.Applications.ps1
# Application catalog and installation helpers.

$Apps = @(
    @{
        Name           = "Google Chrome"
        ChocoId        = "googlechrome"
        WingetId       = "Google.Chrome"
        WingetTimeoutSeconds = 900
        ChocoTimeoutSeconds  = 420
        CreateShortcut = $true
        ShortcutName   = "Google Chrome.lnk"
        DetectNames    = @("Google Chrome")
        ExePaths       = @(
            "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
            "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
            "$env:LocalAppData\Google\Chrome\Application\chrome.exe"
        )
        SearchFolders  = @(
            "$env:ProgramFiles\Google",
            "${env:ProgramFiles(x86)}\Google",
            "$env:LocalAppData\Google"
        )
        ExeName        = "chrome.exe"
        DirectInstaller = @{
            Provider        = "Google officiel"
            Url             = "https://dl.google.com/chrome/install/GoogleChromeStandaloneEnterprise64.msi"
            FileName        = "GoogleChromeStandaloneEnterprise64.msi"
            CachePatterns   = @('GoogleChromeStandaloneEnterprise64*.msi')
            TrustedHosts    = @('dl.google.com')
            SignerPattern   = 'Google'
            MinBytes        = 20000000
            CacheMinBytes   = 20000000
            Command         = "msiexec.exe"
            Arguments       = @('/i', '{0}', '/qn', '/norestart')
            TimeoutSeconds  = 900
        }
    },
    @{
        Name           = "LibreOffice"
        ChocoId        = "libreoffice-fresh"
        WingetId       = "TheDocumentFoundation.LibreOffice"
        WingetTimeoutSeconds = 1200
        ChocoTimeoutSeconds  = 420
        CreateShortcut = $true
        ShortcutName   = "LibreOffice.lnk"
        DetectNames    = @("LibreOffice")
        ExePaths       = @(
            "$env:ProgramFiles\LibreOffice\program\soffice.exe",
            "${env:ProgramFiles(x86)}\LibreOffice\program\soffice.exe"
        )
        SearchFolders  = @(
            "$env:ProgramFiles\LibreOffice",
            "${env:ProgramFiles(x86)}\LibreOffice"
        )
        ExeName        = "soffice.exe"
        DirectInstaller = @{
            Provider        = "The Document Foundation officiel"
            Resolver        = "LibreOfficeStableX64"
            Url             = "https://download.documentfoundation.org/libreoffice/stable/26.2.4/win/x86_64/LibreOffice_26.2.4_Win_x86-64.msi"
            CachePatterns   = @('LibreOffice_*_Win_x86-64.msi')
            TrustedHosts    = @('download.documentfoundation.org')
            SignerPattern   = 'The Document Foundation'
            MinBytes        = 100000000
            CacheMinBytes   = 100000000
            Command         = "msiexec.exe"
            Arguments       = @('/i', '{0}', '/qn', '/norestart')
            TimeoutSeconds  = 1500
        }
    },
    @{
        Name           = "Adobe Acrobat Reader"
        ChocoId        = "adobereader"
        WingetId       = "Adobe.Acrobat.Reader.64-bit"
        WingetTimeoutSeconds = 1200
        ChocoTimeoutSeconds  = 300
        CreateShortcut = $true
        ShortcutName   = "Adobe Acrobat.lnk"
        DetectNames    = @("Adobe Acrobat", "Adobe Acrobat Reader", "Adobe Acrobat Reader DC")
        ExePaths       = @(
            "$env:ProgramFiles\Adobe\Acrobat Reader DC\Reader\AcroRd32.exe",
            "${env:ProgramFiles(x86)}\Adobe\Acrobat Reader DC\Reader\AcroRd32.exe",
            "$env:ProgramFiles\Adobe\Acrobat Reader\Reader\AcroRd32.exe",
            "${env:ProgramFiles(x86)}\Adobe\Acrobat Reader\Reader\AcroRd32.exe",
            "$env:ProgramFiles\Adobe\Acrobat DC\Acrobat\Acrobat.exe"
        )
        SearchFolders  = @(
            "$env:ProgramFiles\Adobe",
            "${env:ProgramFiles(x86)}\Adobe"
        )
        ExeName        = "AcroRd32.exe"
        DirectInstaller = @{
            Provider        = "Adobe officiel"
            Urls            = @(
                "https://ardownload3.adobe.com/pub/adobe/acrobat/win/AcrobatDC/2600121691/AcroRdrDCx642600121691_fr_FR.exe",
                "https://ardownload3.adobe.com/pub/adobe/acrobat/win/AcrobatDC/2600121691/AcroRdrDCx642600121691_MUI.exe"
            )
            CachePatterns   = @('AcroRdrDCx64*.exe', 'AcroRdrDC*.exe')
            TrustedHosts    = @('admdownload.adobe.com', 'ardownload2.adobe.com', 'ardownload3.adobe.com', 'download.adobe.com')
            SignerPattern   = 'Adobe'
            MinBytes        = 50000000
            CacheMinBytes   = 50000000
            Arguments       = @('/sAll', '/rs', '/rps', '/msi', 'EULA_ACCEPT=YES')
            TimeoutSeconds  = 1800
            ValidationTimeoutSeconds = 360
            PostInstallProcessNames = @(
                'AcroRdrDCx642600121691_fr_FR',
                'AcroRdrDCx642600121691_MUI',
                'readerdc_fr_xa_install',
                'readerdc64',
                'Setup',
                'msiexec',
                'RdrServicesUpdater',
                'AcroServicesUpdater',
                'Adobe Installer'
            )
            PostInstallProcessTimeoutSeconds = 900
            PostInstallSettleSeconds = 10
        }
    },
    @{
        Name           = "7-Zip"
        ChocoId        = "7zip"
        WingetId       = "7zip.7zip"
        WingetTimeoutSeconds = 600
        ChocoTimeoutSeconds  = 300
        CreateShortcut = $false
        ShortcutName   = $null
        DetectNames    = @("7-Zip")
        ExePaths       = @(
            "$env:ProgramFiles\7-Zip\7zFM.exe",
            "${env:ProgramFiles(x86)}\7-Zip\7zFM.exe"
        )
        SearchFolders  = @(
            "$env:ProgramFiles\7-Zip",
            "${env:ProgramFiles(x86)}\7-Zip"
        )
        ExeName        = "7zFM.exe"
        DirectInstaller = @{
            Provider        = "7-Zip officiel"
            Resolver        = "SevenZipLatestX64"
            Url             = "https://github.com/ip7z/7zip/releases/download/26.01/7z2601-x64.msi"
            CachePatterns   = @('7z*-x64.msi', '7z*-x64.exe')
            TrustedHosts    = @('www.7-zip.org', '7-zip.org', 'github.com', 'objects.githubusercontent.com')
            SignerPattern   = 'Igor Pavlov|7-Zip'
            AllowUnsigned   = $true
            KnownHashes     = @('A47EA8DCF8BC08E6DE474CAE77C828E031FA22CB528F6095DEFFFEBF11CD02F2')
            MinBytes        = 1000000
            CacheMinBytes   = 1000000
            Command         = "msiexec.exe"
            Arguments       = @('/i', '{0}', '/qn', '/norestart')
            ExeArguments    = @('/S')
            TimeoutSeconds  = 420
        }
    },
    @{
        Name           = "VLC media player"
        ChocoId        = "vlc"
        WingetId       = "VideoLAN.VLC"
        WingetTimeoutSeconds = 900
        ChocoTimeoutSeconds  = 420
        CreateShortcut = $true
        ShortcutName   = "VLC media player.lnk"
        DetectNames    = @("VLC media player", "VLC")
        ExePaths       = @(
            "$env:ProgramFiles\VideoLAN\VLC\vlc.exe",
            "${env:ProgramFiles(x86)}\VideoLAN\VLC\vlc.exe",
            "$env:LocalAppData\Programs\VideoLAN\VLC\vlc.exe"
        )
        SearchFolders  = @(
            "$env:ProgramFiles\VideoLAN",
            "${env:ProgramFiles(x86)}\VideoLAN",
            "$env:LocalAppData\Programs\VideoLAN"
        )
        ExeName        = "vlc.exe"
        DirectInstaller = @{
            Provider        = "VideoLAN officiel"
            Url             = "https://get.videolan.org/vlc/3.0.23/win64/vlc-3.0.23-win64.exe"
            FileName        = "vlc-3.0.23-win64.exe"
            CachePatterns   = @('vlc-*-win64.exe')
            TrustedHosts    = @('get.videolan.org', 'download.videolan.org')
            SignerPattern   = 'VideoLAN'
            MinBytes        = 20000000
            CacheMinBytes   = 20000000
            Arguments       = @('/S')
            TimeoutSeconds  = 600
        }
    }
)

function Get-LDLCInstallerCacheRoot {
    if (-not [string]::IsNullOrWhiteSpace($script:LDLCInstallerCacheRoot)) {
        try {
            if (-not (Test-Path -LiteralPath $script:LDLCInstallerCacheRoot)) {
                New-Item -ItemType Directory -Path $script:LDLCInstallerCacheRoot -Force | Out-Null
            }
            return $script:LDLCInstallerCacheRoot
        }
        catch {}
    }

    $candidates = New-Object System.Collections.Generic.List[string]
    $configured = [Environment]::GetEnvironmentVariable('LDLC_INSTALLER_CACHE')
    if (-not [string]::IsNullOrWhiteSpace($configured)) {
        [void]$candidates.Add($configured)
    }

    [void]$candidates.Add('C:\LDLC_PREPTOOL\Installers')
    if (-not [string]::IsNullOrWhiteSpace($env:ProgramData)) {
        [void]$candidates.Add((Join-Path $env:ProgramData 'LDLC_PREPTOOL\Installers'))
    }

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        try {
            if (-not (Test-Path -LiteralPath $candidate)) {
                New-Item -ItemType Directory -Path $candidate -Force | Out-Null
            }

            $script:LDLCInstallerCacheRoot = [System.IO.Path]::GetFullPath($candidate)
            return $script:LDLCInstallerCacheRoot
        }
        catch {
            Write-Info "Cache installateurs inaccessible : $candidate ($($_.Exception.Message))"
        }
    }

    throw 'Aucun dossier de cache installateurs accessible.'
}

function Initialize-LDLCInstallerCache {
    $root = Get-LDLCInstallerCacheRoot
    Write-Ok "Cache installateurs pret : $root"
    return $root
}

function Get-LDLCInstallerFileNameFromUrl {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [string]$FallbackName = 'installer.exe'
    )

    try {
        $name = [System.IO.Path]::GetFileName(([uri]$Url).AbsolutePath)
        if (-not [string]::IsNullOrWhiteSpace($name)) {
            return ($name -replace '[^a-zA-Z0-9._-]', '_')
        }
    }
    catch {}

    return ($FallbackName -replace '[^a-zA-Z0-9._-]', '_')
}

function Test-LDLCOfficialInstallerUrl {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [string[]]$TrustedHosts = @()
    )

    try {
        $uri = [uri]$Url
        if ($uri.Scheme -ne 'https') {
            return $false
        }

        if (-not $TrustedHosts -or $TrustedHosts.Count -eq 0) {
            return $true
        }

        foreach ($trustedHost in $TrustedHosts) {
            $suffix = ([string]$trustedHost).Trim().TrimStart('*').TrimStart('.')
            if ([string]::IsNullOrWhiteSpace($suffix)) {
                continue
            }

            if ($uri.Host -ieq $suffix -or $uri.Host.EndsWith(".$suffix", [System.StringComparison]::OrdinalIgnoreCase)) {
                return $true
            }
        }
    }
    catch {}

    return $false
}

function New-LDLCOfficialInstallerSource {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [string]$FileName,
        [string]$Provider = 'editeur officiel'
    )

    if ([string]::IsNullOrWhiteSpace($FileName)) {
        $FileName = Get-LDLCInstallerFileNameFromUrl -Url $Url
    }

    return [pscustomobject]@{
        Url      = $Url
        FileName = $FileName
        Provider = $Provider
    }
}

function Resolve-LDLCSevenZipOfficialSources {
    $pageUrl = 'https://www.7-zip.org/download.html'
    $response = Invoke-WebRequest -Uri $pageUrl -UseBasicParsing -TimeoutSec 45
    $matches = [regex]::Matches($response.Content, 'href=["'']([^"'']+(?:x64|64)[^"'']*\.(?:msi|exe))["'']', 'IgnoreCase')
    $candidates = New-Object System.Collections.Generic.List[object]

    foreach ($match in $matches) {
        $relative = [string]$match.Groups[1].Value
        if ($relative -match '(?i)arm64') {
            continue
        }

        try {
            $absolute = ([uri]::new([uri]$pageUrl, $relative)).AbsoluteUri
            $fileName = Get-LDLCInstallerFileNameFromUrl -Url $absolute
            $versionNumber = 0
            if ($fileName -match '(?i)^7z(\d+)') {
                [void][int]::TryParse($Matches[1], [ref]$versionNumber)
            }

            [void]$candidates.Add([pscustomobject]@{
                Url        = $absolute
                FileName   = $fileName
                Provider   = '7-Zip officiel'
                VersionKey = $versionNumber
                MsiRank    = [int]($fileName -notmatch '(?i)\.msi$')
            })
        }
        catch {}
    }

    return @($candidates |
        Sort-Object -Property @{ Expression = 'VersionKey'; Descending = $true }, @{ Expression = 'MsiRank'; Ascending = $true } |
        Select-Object -First 2)
}

function Resolve-LDLCLibreOfficeOfficialSources {
    $rootUrl = 'https://download.documentfoundation.org/libreoffice/stable/'
    $response = Invoke-WebRequest -Uri $rootUrl -UseBasicParsing -TimeoutSec 45
    $versions = New-Object System.Collections.Generic.List[version]

    foreach ($match in [regex]::Matches($response.Content, 'href=["'']([0-9]+(?:\.[0-9]+){1,3})/["'']', 'IgnoreCase')) {
        try { [void]$versions.Add([version]$match.Groups[1].Value) } catch {}
    }

    $latest = $versions | Sort-Object -Descending | Select-Object -First 1
    if (-not $latest) {
        throw 'Aucune version stable LibreOffice trouvee sur le serveur officiel.'
    }

    $versionText = $latest.ToString()
    $fileName = "LibreOffice_${versionText}_Win_x86-64.msi"
    $url = "${rootUrl}${versionText}/win/x86_64/$fileName"
    return @(New-LDLCOfficialInstallerSource -Url $url -FileName $fileName -Provider 'The Document Foundation officiel')
}

function Resolve-LDLCNvidiaAppOfficialSources {
    $pageUrl = 'https://www.nvidia.com/en-us/software/nvidia-app/'
    $response = Invoke-WebRequest -Uri $pageUrl -UseBasicParsing -TimeoutSec 60
    $matches = [regex]::Matches($response.Content, 'https://[^"''<> ]*download\.nvidia\.com/[^"''<> ]*NVIDIA_app_v[^"''<> ]*\.exe', 'IgnoreCase')
    if ($matches.Count -eq 0) {
        throw 'Lien NVIDIA App introuvable sur la page officielle.'
    }

    $sources = foreach ($match in $matches) {
        $url = $match.Value -replace '&amp;', '&'
        $source = New-LDLCOfficialInstallerSource -Url $url -Provider 'NVIDIA officiel'
        $versionMatch = [regex]::Match($url, '(?i)NVIDIA_app_v([0-9]+(?:\.[0-9]+){1,3})\.exe')
        if ($versionMatch.Success) {
            Add-Member -InputObject $source -NotePropertyName Version -NotePropertyValue $versionMatch.Groups[1].Value -Force
        }
        $source
    }

    return @($sources |
        Sort-Object -Property @{ Expression = {
            try { [version]([string]$_.Version) } catch { [version]'0.0' }
        }; Descending = $true } |
        Select-Object -Unique -Property Url, FileName, Provider, Version)
}

function Resolve-LDLCAmdAdrenalinOfficialSources {
    $pageUrl = 'https://www.amd.com/en/support/download/drivers.html'
    $response = Invoke-WebRequest -Uri $pageUrl -UseBasicParsing -TimeoutSec 60
    $candidateUrls = New-Object System.Collections.Generic.List[string]

    foreach ($match in [regex]::Matches($response.Content, 'https://drivers\.amd\.com/[^"''<> ]*amd-software-adrenalin-edition-[^"''<> ]*\.exe', 'IgnoreCase')) {
        [void]$candidateUrls.Add(($match.Value -replace '&amp;', '&'))
    }

    # La page generale AMD expose souvent seulement le petit Auto-Detect.
    # Les notes de version officielles donnent aussi le package WHQL complet,
    # qui peut etre conserve dans le cache local et reutilise hors ligne.
    $releaseNoteLinks = New-Object System.Collections.Generic.List[string]
    foreach ($match in [regex]::Matches($response.Content, '(?:https://www\.amd\.com)?/en/resources/support-articles/release-notes/RN-RAD-WIN-[0-9-]+\.html', 'IgnoreCase')) {
        $relativeOrAbsolute = $match.Value -replace '&amp;', '&'
        try {
            $releaseUrl = ([uri]::new([uri]$pageUrl, $relativeOrAbsolute)).AbsoluteUri
            [void]$releaseNoteLinks.Add($releaseUrl)
        }
        catch {}
    }

    # AMD publie souvent sur la page generale uniquement le bootstrap web.
    # Son nom contient toutefois la version Adrenalin : la note RN-RAD-WIN
    # correspondante expose le package WHQL complet, plus fiable et cacheable.
    foreach ($candidateUrl in @($candidateUrls | Select-Object -Unique)) {
        $versionMatch = [regex]::Match($candidateUrl, '(?i)adrenalin-edition-([0-9]+(?:\.[0-9]+){1,3})')
        if (-not $versionMatch.Success) {
            continue
        }

        $releaseVersion = $versionMatch.Groups[1].Value -replace '\.', '-'
        [void]$releaseNoteLinks.Add("https://www.amd.com/en/resources/support-articles/release-notes/RN-RAD-WIN-$releaseVersion.html")
    }

    foreach ($releaseUrl in ($releaseNoteLinks | Select-Object -Unique)) {
        try {
            $releasePage = Invoke-WebRequest -Uri $releaseUrl -UseBasicParsing -TimeoutSec 60
            foreach ($match in [regex]::Matches($releasePage.Content, 'https://drivers\.amd\.com/[^"''<> ]*amd-software-adrenalin-edition-[^"''<> ]*\.exe', 'IgnoreCase')) {
                [void]$candidateUrls.Add(($match.Value -replace '&amp;', '&'))
            }
        }
        catch {
            Write-Info "Notes AMD indisponibles pour la resolution Adrenalin : $($_.Exception.Message)"
        }
    }

    if ($candidateUrls.Count -eq 0) {
        throw 'Lien AMD Adrenalin introuvable sur la page officielle.'
    }

    $sources = foreach ($url in ($candidateUrls | Select-Object -Unique)) {
        $source = New-LDLCOfficialInstallerSource -Url $url -Provider 'AMD officiel'
        $versionMatch = [regex]::Match($url, '(?i)adrenalin-edition-([0-9]+(?:\.[0-9]+){1,3})')
        if ($versionMatch.Success) {
            Add-Member -InputObject $source -NotePropertyName Version -NotePropertyValue $versionMatch.Groups[1].Value -Force
        }
        Add-Member -InputObject $source -NotePropertyName IsFullPackage -NotePropertyValue (-not ($url -match '(?i)minimalsetup|_web\.exe')) -Force
        $source
    }

    return @($sources |
        Sort-Object -Property @{ Expression = 'IsFullPackage'; Descending = $true }, @{ Expression = {
            try { [version]([string]$_.Version) } catch { [version]'0.0' }
        }; Descending = $true } |
        Select-Object -Unique -Property Url, FileName, Provider, Version, IsFullPackage)
}

function Get-LDLCOfficialInstallerSources {
    param([Parameter(Mandatory = $true)]$Installer)

    $sources = New-Object System.Collections.Generic.List[object]
    $provider = if ($Installer.ContainsKey('Provider')) { [string]$Installer.Provider } else { 'editeur officiel' }
    $resolver = if ($Installer.ContainsKey('Resolver')) { [string]$Installer.Resolver } else { '' }

    try {
        $resolved = switch ($resolver) {
            'SevenZipLatestX64'      { @(Resolve-LDLCSevenZipOfficialSources) }
            'LibreOfficeStableX64'  { @(Resolve-LDLCLibreOfficeOfficialSources) }
            'NvidiaApp'             { @(Resolve-LDLCNvidiaAppOfficialSources) }
            'AmdAdrenalin'          { @(Resolve-LDLCAmdAdrenalinOfficialSources) }
            'NvidiaDriver' {
                if (Get-Command Resolve-LDLCNvidiaDriverOfficialSources -ErrorAction SilentlyContinue) {
                    @(Resolve-LDLCNvidiaDriverOfficialSources -Context $Installer.ResolverContext)
                }
                else { @() }
            }
            default { @() }
        }

        foreach ($item in @($resolved)) {
            if ($item -and -not [string]::IsNullOrWhiteSpace([string]$item.Url)) {
                [void]$sources.Add($item)
            }
        }
    }
    catch {
        Write-Info "Resolution de la source $provider impossible : $($_.Exception.Message)"
    }

    $configuredUrls = New-Object System.Collections.Generic.List[string]
    if ($Installer.ContainsKey('Urls')) {
        foreach ($url in @($Installer.Urls)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$url)) { [void]$configuredUrls.Add([string]$url) }
        }
    }
    if ($Installer.ContainsKey('Url') -and -not [string]::IsNullOrWhiteSpace([string]$Installer.Url)) {
        [void]$configuredUrls.Add([string]$Installer.Url)
    }

    foreach ($url in ($configuredUrls | Select-Object -Unique)) {
        $fileName = if ($Installer.ContainsKey('FileName')) { [string]$Installer.FileName } else { '' }
        [void]$sources.Add((New-LDLCOfficialInstallerSource -Url $url -FileName $fileName -Provider $provider))
    }

    $trustedHosts = if ($Installer.ContainsKey('TrustedHosts')) { @($Installer.TrustedHosts) } else { @() }
    $seen = @{}
    $validSources = foreach ($source in $sources) {
        if (-not (Test-LDLCOfficialInstallerUrl -Url $source.Url -TrustedHosts $trustedHosts)) {
            Write-Info "Source refusee car hors domaines editeur : $($source.Url)"
            continue
        }

        if ($seen.ContainsKey($source.Url)) {
            continue
        }

        $seen[$source.Url] = $true
        $source
    }

    return @($validSources)
}

function Test-LDLCInstallerFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Installer,
        [switch]$ForCache,
        [switch]$FreshDownload
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }

    $extension = [System.IO.Path]::GetExtension($Path)
    if ($extension -notin @('.exe', '.msi')) {
        Write-Info "Installateur refuse (extension inattendue) : $Path"
        return $false
    }

    $minimum = 1024
    if ($ForCache -and $Installer.ContainsKey('CacheMinBytes')) {
        $minimum = [int64]$Installer.CacheMinBytes
    }
    elseif ($Installer.ContainsKey('MinBytes')) {
        $minimum = [int64]$Installer.MinBytes
    }

    $length = (Get-Item -LiteralPath $Path).Length
    if ($length -lt $minimum) {
        Write-Info "Installateur refuse (taille $length octets, minimum $minimum) : $Path"
        return $false
    }

    if ($Installer.ContainsKey('SkipSignatureValidation') -and [bool]$Installer.SkipSignatureValidation) {
        return $true
    }

    $signerPattern = if ($Installer.ContainsKey('SignerPattern')) { [string]$Installer.SignerPattern } else { '' }
    if ([string]::IsNullOrWhiteSpace($signerPattern)) {
        return $true
    }

    try {
        $signature = Get-AuthenticodeSignature -LiteralPath $Path
        $subject = if ($signature.SignerCertificate) { [string]$signature.SignerCertificate.Subject } else { '' }
        if ($signature.Status -eq 'NotSigned' -and $Installer.ContainsKey('AllowUnsigned') -and [bool]$Installer.AllowUnsigned) {
            $hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
            $knownHashes = if ($Installer.ContainsKey('KnownHashes')) { @($Installer.KnownHashes) } else { @() }
            $sidecarPath = "$Path.sha256"
            $sidecarHash = if (Test-Path -LiteralPath $sidecarPath) {
                ([string](Get-Content -LiteralPath $sidecarPath -Raw -ErrorAction SilentlyContinue)).Trim().ToUpperInvariant()
            }
            else { '' }

            if ($FreshDownload -or $knownHashes -contains $hash -or $sidecarHash -eq $hash) {
                Write-Info "Package officiel non signe accepte avec controle SHA-256 : $hash"
                return $true
            }

            Write-Info "Installateur non signe refuse sans hash approuve : $Path"
            return $false
        }

        if ($signature.Status -eq 'HashMismatch') {
            Write-Info "Installateur refuse (signature $($signature.Status)) : $Path"
            return $false
        }

        if ($subject -notmatch $signerPattern) {
            Write-Info "Installateur refuse (signataire inattendu : $subject) : $Path"
            return $false
        }

        if ($signature.Status -ne 'Valid') {
            Write-Info "Signature editeur reconnue mais statut local $($signature.Status) : $subject"
        }
        return $true
    }
    catch {
        Write-Info "Verification de signature impossible pour $Path : $($_.Exception.Message)"
        return $false
    }
}

function Get-LDLCCachedInstallerPaths {
    param([Parameter(Mandatory = $true)]$Installer)

    $cacheRoot = Get-LDLCInstallerCacheRoot
    $patterns = if ($Installer.ContainsKey('CachePatterns')) { @($Installer.CachePatterns) } else { @('*.exe', '*.msi') }
    $excludePatterns = if ($Installer.ContainsKey('CacheExcludePatterns')) { @($Installer.CacheExcludePatterns) } else { @() }
    $files = New-Object System.Collections.Generic.List[object]

    foreach ($pattern in $patterns) {
        Get-ChildItem -LiteralPath $cacheRoot -Filter $pattern -File -ErrorAction SilentlyContinue |
            ForEach-Object { [void]$files.Add($_) }
    }

    return @($files |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -ExpandProperty FullName -Unique |
        Where-Object {
            $fileName = [System.IO.Path]::GetFileName($_)
            -not @($excludePatterns | Where-Object { $fileName -like $_ }).Count
        } |
        Where-Object { Test-LDLCInstallerFile -Path $_ -Installer $Installer -ForCache })
}

function Test-ChocoAvailable {
    param([switch]$Refresh)

    if (-not $Refresh -and $script:CommandAvailabilityCache.ContainsKey('choco')) {
        return [bool]$script:CommandAvailabilityCache['choco']
    }

    try {
        $command = Get-Command choco -ErrorAction Stop
        $version = & $command.Source --version 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$version)) {
            throw "Chocolatey ne repond pas correctement."
        }

        $script:CommandAvailabilityCache['choco'] = $true
        return $true
    }
    catch {
        $script:CommandAvailabilityCache['choco'] = $false
        return $false
    }
}

function Get-LDLCWingetCommandPath {
    $candidates = New-Object System.Collections.Generic.List[string]

    try {
        $command = Get-Command winget -ErrorAction SilentlyContinue
        if ($command -and -not [string]::IsNullOrWhiteSpace($command.Source)) {
            [void]$candidates.Add($command.Source)
        }
    }
    catch {}

    $searchRoots = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        [void]$searchRoots.Add((Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps'))
    }
    if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
        [void]$searchRoots.Add((Join-Path $env:ProgramFiles 'WindowsApps'))
    }

    foreach ($basePath in $searchRoots) {
        if ([string]::IsNullOrWhiteSpace($basePath) -or -not (Test-Path -LiteralPath $basePath)) {
            continue
        }

        try {
            if ($basePath -like '*\WindowsApps') {
                Get-ChildItem -LiteralPath $basePath -Directory -Filter 'Microsoft.DesktopAppInstaller_*' -ErrorAction SilentlyContinue |
                    ForEach-Object {
                        $candidate = Join-Path $_.FullName 'winget.exe'
                        if (Test-Path -LiteralPath $candidate) {
                            [void]$candidates.Add($candidate)
                        }
                    }
            }

            Get-ChildItem -LiteralPath $basePath -Filter 'winget.exe' -Recurse -ErrorAction SilentlyContinue |
                Sort-Object FullName -Descending |
                ForEach-Object { [void]$candidates.Add($_.FullName) }
        }
        catch {}
    }

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $candidate)) {
            continue
        }

        try {
            $version = & $candidate --version 2>$null
            if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace([string]$version)) {
                return $candidate
            }
        }
        catch {}
    }

    return $null
}

function Test-WingetAvailable {
    param([switch]$Refresh)

    if (-not $Refresh -and $script:CommandAvailabilityCache.ContainsKey('winget')) {
        return [bool]$script:CommandAvailabilityCache['winget']
    }

    $wingetPath = Get-LDLCWingetCommandPath
    if (-not [string]::IsNullOrWhiteSpace($wingetPath)) {
        $script:LDLCWingetCommandPath = $wingetPath
        $script:CommandAvailabilityCache['winget'] = $true
        return $true
    }

    $script:LDLCWingetCommandPath = $null
    $script:CommandAvailabilityCache['winget'] = $false
    return $false
}

function Test-LDLCWingetSourcesAvailable {
    param([switch]$Refresh)

    if (-not $Refresh -and $script:CommandAvailabilityCache.ContainsKey('wingetSources')) {
        return [bool]$script:CommandAvailabilityCache['wingetSources']
    }

    if (-not (Test-WingetAvailable -Refresh:$Refresh)) {
        $script:CommandAvailabilityCache['wingetSources'] = $false
        return $false
    }

    try {
        $result = Invoke-LDLCInstallerCommand `
            -CommandName 'winget' `
            -ArgumentList @('source', 'list', '--disable-interactivity') `
            -Label 'Winget sources' `
            -TimeoutSeconds 30

        Write-LDLCInstallerOutputTail -Result $result -Prefix 'winget-source'
        if (-not $result.TimedOut -and $result.ExitCode -eq 0 -and ($result.OutputLines -match '(?i)\bwinget\b|Microsoft\.Winget\.Source')) {
            $script:CommandAvailabilityCache['wingetSources'] = $true
            return $true
        }

        Write-Warn "Sources Winget non confirmees. Tentative de reinitialisation rapide..."
        [void](Invoke-LDLCInstallerCommand -CommandName 'winget' -ArgumentList @('source', 'reset', '--force', '--disable-interactivity') -Label 'Winget source reset' -TimeoutSeconds 45)
        [void](Invoke-LDLCInstallerCommand -CommandName 'winget' -ArgumentList @('source', 'update', '--disable-interactivity') -Label 'Winget source update' -TimeoutSeconds 45)

        $retry = Invoke-LDLCInstallerCommand `
            -CommandName 'winget' `
            -ArgumentList @('source', 'list', '--disable-interactivity') `
            -Label 'Winget sources retry' `
            -TimeoutSeconds 30

        Write-LDLCInstallerOutputTail -Result $retry -Prefix 'winget-source'
        $ok = (-not $retry.TimedOut -and $retry.ExitCode -eq 0 -and ($retry.OutputLines -match '(?i)\bwinget\b|Microsoft\.Winget\.Source'))
        $script:CommandAvailabilityCache['wingetSources'] = [bool]$ok
        return [bool]$ok
    }
    catch {
        Write-Warn "Sources Winget indisponibles : $($_.Exception.Message)"
        $script:CommandAvailabilityCache['wingetSources'] = $false
        return $false
    }
}

# --------------------------------------------------
# DETECTION DES APPLICATIONS
# --------------------------------------------------
function Clear-LDLCDetectionCaches {
    $script:InstalledProgramsCache = $null
    $script:InstalledProgramsCacheTimestamp = [datetime]::MinValue
    $script:ExePathCache = @{}
}

function Test-AppInstalledInRegistry {
    param(
        [string[]]$DetectNames,
        [switch]$Refresh
    )

    foreach ($item in (Get-LDLCInstalledPrograms -Refresh:$Refresh)) {
        foreach ($name in $DetectNames) {
            if ($item.DisplayName -and $item.DisplayName -like "*$name*") {
                return $true
            }
        }
    }

    return $false
}

function Get-ExistingExePath {
    param(
        [string[]]$ExePaths,
        [string[]]$SearchFolders,
        [string]$ExeName,
        [switch]$RefreshCache
    )

    $cacheKey = "{0}|{1}|{2}" -f ($ExeName -as [string]), (($ExePaths | ForEach-Object { $_ }) -join ';'), (($SearchFolders | ForEach-Object { $_ }) -join ';')

    if ($RefreshCache) {
        [void]$script:ExePathCache.Remove($cacheKey)
    }

    if ($script:ExePathCache.ContainsKey($cacheKey)) {
        $cachedPath = [string]$script:ExePathCache[$cacheKey]
        if (-not [string]::IsNullOrWhiteSpace($cachedPath) -and (Test-Path $cachedPath)) {
            return $cachedPath
        }

        [void]$script:ExePathCache.Remove($cacheKey)
    }

    foreach ($path in $ExePaths) {
        Stop-IfRequested

        if (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path $path)) {
            $script:ExePathCache[$cacheKey] = $path
            return $path
        }
    }

    foreach ($folder in $SearchFolders) {
        Stop-IfRequested

        if (-not [string]::IsNullOrWhiteSpace($folder) -and (Test-Path $folder)) {
            try {
                $found = Get-ChildItem -Path $folder -Filter $ExeName -File -Recurse -ErrorAction SilentlyContinue |
                    Select-Object -First 1
                if ($found) {
                    $script:ExePathCache[$cacheKey] = $found.FullName
                    return $found.FullName
                }
            }
            catch {}
        }
    }

    return $null
}

function Get-LDLCAppInstallationState {
    param(
        $App,
        [switch]$Refresh
    )

    $exe = Get-ExistingExePath `
        -ExePaths $App.ExePaths `
        -SearchFolders $App.SearchFolders `
        -ExeName $App.ExeName `
        -RefreshCache:$Refresh

    $registryMatch = $null
    foreach ($item in (Get-LDLCInstalledPrograms -Refresh:$Refresh)) {
        foreach ($name in @($App.DetectNames)) {
            if ($item.DisplayName -and $item.DisplayName -like "*$name*") {
                $registryMatch = $item
                break
            }
        }
        if ($registryMatch) { break }
    }

    $fileVersion = ''
    if (-not [string]::IsNullOrWhiteSpace($exe)) {
        try {
            $fileVersion = [string](Get-Item -LiteralPath $exe).VersionInfo.ProductVersion
            if ([string]::IsNullOrWhiteSpace($fileVersion)) {
                $fileVersion = [string](Get-Item -LiteralPath $exe).VersionInfo.FileVersion
            }
        }
        catch {}
    }

    $registryVersion = if ($registryMatch) { [string]$registryMatch.DisplayVersion } else { '' }
    $version = if (-not [string]::IsNullOrWhiteSpace($registryVersion)) { $registryVersion } else { $fileVersion }
    $hasExecutable = -not [string]::IsNullOrWhiteSpace($exe)
    $hasRegistry = $null -ne $registryMatch
    $hasVersion = -not [string]::IsNullOrWhiteSpace($version)

    return [pscustomobject]@{
        IsInstalled        = [bool]($hasExecutable -and ($hasRegistry -or $hasVersion))
        ExePath            = $exe
        HasExecutable      = $hasExecutable
        HasRegistry        = $hasRegistry
        RegistryDisplayName = if ($registryMatch) { [string]$registryMatch.DisplayName } else { '' }
        RegistryVersion    = $registryVersion
        FileVersion        = $fileVersion
        Version            = $version
    }
}

function Format-LDLCAppInstallationState {
    param([Parameter(Mandatory = $true)]$State)

    $exeLabel = if ($State.HasExecutable) { [string]$State.ExePath } else { 'absent' }
    $registryLabel = if ($State.HasRegistry) { [string]$State.RegistryDisplayName } else { 'absent' }
    $versionLabel = if (-not [string]::IsNullOrWhiteSpace([string]$State.Version)) { [string]$State.Version } else { 'inconnue' }
    return "exe=$exeLabel; registre=$registryLabel; version=$versionLabel"
}

function Test-AppReallyInstalled {
    param(
        $App,
        [switch]$Refresh
    )

    $state = Get-LDLCAppInstallationState -App $App -Refresh:$Refresh
    if ($state.HasRegistry -and -not $state.HasExecutable) {
        Write-Info "$($App.Name) apparait dans le registre mais l'executable principal est absent."
    }

    return [bool]$state.IsInstalled
}

function Wait-LDLCAppInstallValidation {
    param(
        $App,
        [int]$TimeoutSeconds = 45
    )

    return Wait-LDLCCondition `
        -Condition {
            Test-AppReallyInstalled -App $App -Refresh
        } `
        -TimeoutSeconds $TimeoutSeconds `
        -PollMilliseconds 2000 `
        -IgnoreErrors
}

function Get-LDLCAppWingetId {
    param($App)

    if ($App.ContainsKey('WingetId') -and -not [string]::IsNullOrWhiteSpace($App.WingetId)) {
        return [string]$App.WingetId
    }

    switch ($App.Name) {
        "Google Chrome"        { return "Google.Chrome" }
        "Adobe Acrobat Reader" { return "Adobe.Acrobat.Reader.64-bit" }
        "7-Zip"                { return "7zip.7zip" }
        "LibreOffice"          { return "TheDocumentFoundation.LibreOffice" }
        "VLC media player"     { return "VideoLAN.VLC" }
        default                 { return $null }
    }
}

function Get-LDLCAppTimeout {
    param(
        $App,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][int]$DefaultSeconds
    )

    if ($App.ContainsKey($Key) -and [int]$App[$Key] -gt 0) {
        return [int]$App[$Key]
    }

    return $DefaultSeconds
}

function Invoke-LDLCInstallerCommand {
    param(
        [Parameter(Mandatory = $true)][string]$CommandName,
        [Parameter(Mandatory = $true)][string[]]$ArgumentList,
        [Parameter(Mandatory = $true)][string]$Label,
        [int]$TimeoutSeconds = 900
    )

    Stop-IfRequested

    if ($CommandName -eq 'winget') {
        $commandPath = if (-not [string]::IsNullOrWhiteSpace($script:LDLCWingetCommandPath)) {
            [string]$script:LDLCWingetCommandPath
        }
        else {
            Get-LDLCWingetCommandPath
        }

        if ([string]::IsNullOrWhiteSpace($commandPath)) {
            throw 'Winget introuvable.'
        }
    }
    elseif (Test-Path -LiteralPath $CommandName) {
        $commandPath = $CommandName
    }
    else {
        $command = Get-Command $CommandName -ErrorAction Stop
        $commandPath = $command.Source
    }
    $tempRoot = if ($env:TEMP) { $env:TEMP } else { Get-LDLCProjectRoot }
    $safeLabel = ($Label -replace '[^a-zA-Z0-9]+', '_').Trim('_')
    $id = [guid]::NewGuid().ToString('N')
    $stdoutPath = Join-Path $tempRoot "LDLC_${safeLabel}_${id}.out.log"
    $stderrPath = Join-Path $tempRoot "LDLC_${safeLabel}_${id}.err.log"
    $process = $null
    $didTimeout = $false

    try {
        Write-Step "$Label : demarrage avec timeout ${TimeoutSeconds}s."

        $process = Start-Process `
            -FilePath $commandPath `
            -ArgumentList $ArgumentList `
            -WindowStyle Minimized `
            -RedirectStandardOutput $stdoutPath `
            -RedirectStandardError $stderrPath `
            -PassThru

        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

        while (-not $process.HasExited) {
            Stop-IfRequested

            if ((Get-Date) -ge $deadline) {
                Write-Warn "$Label bloque depuis ${TimeoutSeconds}s. Arret force pour bascule rapide."
                $didTimeout = $true
                try {
                    & taskkill.exe /PID $process.Id /T /F | Out-Null
                }
                catch {
                    try { $process.Kill() } catch {}
                }

                Start-Sleep -Milliseconds 500
                break
            }

            Start-Sleep -Milliseconds 500
        }

        $exitCode = if ($process.HasExited) { [int]$process.ExitCode } else { -1 }
        $outputLines = New-Object System.Collections.Generic.List[string]

        foreach ($logPath in @($stdoutPath, $stderrPath)) {
            if (Test-Path -LiteralPath $logPath) {
                try {
                    foreach ($line in (Get-Content -LiteralPath $logPath -ErrorAction SilentlyContinue | Select-Object -Last 12)) {
                        if (-not [string]::IsNullOrWhiteSpace($line)) {
                            [void]$outputLines.Add($line)
                        }
                    }
                }
                catch {}
            }
        }

        return [pscustomobject]@{
            ExitCode    = $exitCode
            TimedOut    = $didTimeout
            OutputLines = @($outputLines.ToArray())
        }
    }
    finally {
        Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue
    }
}

function Write-LDLCInstallerOutputTail {
    param(
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)][string]$Prefix
    )

    if (-not $Result -or -not $Result.OutputLines) {
        return
    }

    foreach ($line in ($Result.OutputLines | Select-Object -Last 10)) {
        Write-Host "   [$Prefix] $line" -ForegroundColor DarkGray
    }
}

function Install-LDLCAppWithWinget {
    param(
        $App,
        [Parameter(Mandatory = $true)][string]$WingetId
    )

    if ([string]::IsNullOrWhiteSpace($WingetId)) {
        Write-Warn "Aucun identifiant Winget configure pour $($App.Name)."
        return $false
    }

    if (-not (Test-WingetAvailable)) {
        Write-Warn "Winget indisponible pour $($App.Name)."
        return $false
    }

    if (-not (Test-LDLCWingetSourcesAvailable)) {
        Write-Warn "Winget disponible mais sources non fonctionnelles pour $($App.Name)."
        return $false
    }

    $timeoutSeconds = Get-LDLCAppTimeout -App $App -Key 'WingetTimeoutSeconds' -DefaultSeconds 900
    $wingetArgs = @(
        'install',
        '-e',
        '--id',
        $WingetId,
        '--silent',
        '--source',
        'winget',
        '--disable-interactivity',
        '--accept-source-agreements',
        '--accept-package-agreements'
    )

    try {
        $result = Invoke-LDLCInstallerCommand -CommandName 'winget' -ArgumentList $wingetArgs -Label "Winget $($App.Name)" -TimeoutSeconds $timeoutSeconds
        $codeLabel = if ($result.TimedOut) { "TIMEOUT" } else { [string]$result.ExitCode }
        Write-Step "Code retour Winget pour $($App.Name) : $codeLabel"
        Write-LDLCInstallerOutputTail -Result $result -Prefix 'winget'

        Clear-LDLCDetectionCaches
        $validationTimeout = if (-not $result.TimedOut -and $result.ExitCode -eq 0) { 120 } else { 75 }
        if (Wait-LDLCAppInstallValidation -App $App -TimeoutSeconds $validationTimeout) {
            Write-Ok "$($App.Name) validee apres installation Winget."
            return $true
        }

        Write-Warn "Winget n'a pas permis de valider l'installation de $($App.Name) (Code $codeLabel)."
        return $false
    }
    catch {
        Write-Warn "Erreur lors de l'execution de Winget pour $($App.Name) : $($_.Exception.Message)"
        return $false
    }
}

function Install-LDLCAppWithChocolatey {
    param($App)

    if ([string]::IsNullOrWhiteSpace($App.ChocoId)) {
        Write-Warn "Aucun paquet Chocolatey configure pour $($App.Name)."
        return $false
    }

    if (-not (Test-ChocoAvailable)) {
        Write-Warn "Chocolatey indisponible pour $($App.Name)."
        return $false
    }

    $timeoutSeconds = Get-LDLCAppTimeout -App $App -Key 'ChocoTimeoutSeconds' -DefaultSeconds 420
    $chocoArgs = @(
        'install',
        $App.ChocoId,
        '-y',
        '--no-progress',
        '--ignore-checksums',
        "--execution-timeout=$timeoutSeconds"
    )

    try {
        $result = Invoke-LDLCInstallerCommand -CommandName 'choco' -ArgumentList $chocoArgs -Label "Chocolatey $($App.Name)" -TimeoutSeconds $timeoutSeconds
        $codeLabel = if ($result.TimedOut) { "TIMEOUT" } else { [string]$result.ExitCode }
        Write-Step "Code retour Chocolatey pour $($App.Name) : $codeLabel"
        Write-LDLCInstallerOutputTail -Result $result -Prefix 'choco'

        Clear-LDLCDetectionCaches
        $validationTimeout = if (-not $result.TimedOut -and $result.ExitCode -eq 0) { 120 } else { 75 }
        if (Wait-LDLCAppInstallValidation -App $App -TimeoutSeconds $validationTimeout) {
            Write-Ok "$($App.Name) validee apres installation Chocolatey."
            return $true
        }

        Write-Warn "Echec Chocolatey pour $($App.Name) (Code $codeLabel)."
        return $false
    }
    catch {
        Write-Warn "Erreur lors de l'execution de Chocolatey pour $($App.Name) : $($_.Exception.Message)"
        return $false
    }
}

function Invoke-LDLCInstallerFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Installer,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $extension = [System.IO.Path]::GetExtension($Path)
    $timeoutSeconds = if ($Installer.ContainsKey('TimeoutSeconds') -and [int]$Installer.TimeoutSeconds -gt 0) {
        [int]$Installer.TimeoutSeconds
    }
    else { 900 }

    if ($extension -ieq '.msi') {
        $commandName = 'msiexec.exe'
        $argumentTemplate = if ($Installer.ContainsKey('MsiArguments') -and $Installer.MsiArguments) {
            @($Installer.MsiArguments)
        }
        elseif ($Installer.ContainsKey('Arguments') -and $Installer.Arguments) {
            @($Installer.Arguments)
        }
        else { @('/i', '{0}', '/qn', '/norestart') }
    }
    else {
        $commandName = $Path
        $argumentTemplate = if ($Installer.ContainsKey('ExeArguments') -and $Installer.ExeArguments) {
            @($Installer.ExeArguments)
        }
        elseif ($Installer.ContainsKey('Arguments') -and $Installer.Arguments -and [string]$Installer.Command -ne 'msiexec.exe') {
            @($Installer.Arguments)
        }
        else { @('/S') }
    }

    $arguments = @($argumentTemplate | ForEach-Object { ([string]$_).Replace('{0}', $Path) })
    return Invoke-LDLCInstallerCommand `
        -CommandName $commandName `
        -ArgumentList ([string[]]$arguments) `
        -Label $Label `
        -TimeoutSeconds $timeoutSeconds
}

function Wait-LDLCPostInstallProcesses {
    param(
        [Parameter(Mandatory = $true)]$Installer,
        [Parameter(Mandatory = $true)][string]$Label,
        [scriptblock]$ValidationScript
    )

    if (-not $Installer.ContainsKey('PostInstallProcessNames') -or -not $Installer.PostInstallProcessNames) {
        return
    }

    $processNames = @($Installer.PostInstallProcessNames) |
        ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension([string]$_) } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -Unique

    if ($processNames.Count -eq 0) {
        return
    }

    $timeoutSeconds = if ($Installer.ContainsKey('PostInstallProcessTimeoutSeconds') -and [int]$Installer.PostInstallProcessTimeoutSeconds -gt 0) {
        [int]$Installer.PostInstallProcessTimeoutSeconds
    }
    else { 300 }

    $settleSeconds = if ($Installer.ContainsKey('PostInstallSettleSeconds') -and [int]$Installer.PostInstallSettleSeconds -gt 0) {
        [int]$Installer.PostInstallSettleSeconds
    }
    else { 0 }

    $deadline = (Get-Date).AddSeconds($timeoutSeconds)
    $sawProcess = $false

    do {
        Stop-IfRequested
        $running = @()
        foreach ($name in $processNames) {
            try {
                $running += @(Get-Process -Name $name -ErrorAction SilentlyContinue)
            }
            catch {}
        }

        if ($running.Count -eq 0) {
            if ($sawProcess -and $settleSeconds -gt 0) {
                Write-Step "[INSTALL] $Label : finalisation post-install ${settleSeconds}s."
                Start-Sleep -Seconds $settleSeconds
            }
            return
        }

        if (-not $sawProcess) {
            $sawProcess = $true
            $runningNames = @($running | Select-Object -ExpandProperty ProcessName -Unique)
            Write-Step "[INSTALL] $Label : attente des processus post-install ($($runningNames -join ', '))."
        }

        if ($ValidationScript) {
            try {
                if (& $ValidationScript) {
                    if ($settleSeconds -gt 0) {
                        Write-Step "[INSTALL] $Label : verification deja positive, finalisation ${settleSeconds}s."
                        Start-Sleep -Seconds $settleSeconds
                    }
                    return
                }
            }
            catch {}
        }

        if ((Get-Date) -ge $deadline) {
            Write-Warn "[INSTALL] $Label : processus post-install encore actifs apres ${timeoutSeconds}s, verification finale lancee quand meme."
            return
        }

        Start-Sleep -Seconds 2
    } while ($true)
}

function Wait-LDLCInstallerValidation {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$ValidationScript,
        [int]$TimeoutSeconds = 120,
        [int]$PollMilliseconds = 2000
    )

    $deadline = (Get-Date).AddSeconds([math]::Max(1, $TimeoutSeconds))
    do {
        Stop-IfRequested
        try {
            if (& $ValidationScript) { return $true }
        }
        catch {}

        if ((Get-Date) -ge $deadline) { break }
        Start-Sleep -Milliseconds $PollMilliseconds
    } while ($true)

    return $false
}

function Invoke-LDLCOfficialInstallerAttempt {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Installer,
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][string]$Method,
        [Parameter(Mandatory = $true)][scriptblock]$ValidationScript,
        [scriptblock]$InstallAction
    )

    Write-Step "[INSTALL] Methode : $Method"
    Write-Step "[INSTALL] Package : $Path"

    try {
        $result = if ($InstallAction) {
            & $InstallAction $Path $Installer $Label
        }
        else {
            Invoke-LDLCInstallerFile -Path $Path -Installer $Installer -Label "$Method - $Label"
        }

        $timedOut = [bool]($result -and $result.PSObject.Properties['TimedOut'] -and $result.TimedOut)
        $exitCode = if ($result -and $result.PSObject.Properties['ExitCode']) { [int]$result.ExitCode } else { 0 }
        $codeLabel = if ($timedOut) { 'TIMEOUT' } else { [string]$exitCode }
        Write-Step "[INSTALL] Code retour $Label : $codeLabel"
        if ($result -and (Get-Command Write-LDLCInstallerOutputTail -ErrorAction SilentlyContinue)) {
            Write-LDLCInstallerOutputTail -Result $result -Prefix 'officiel'
        }

        if ($exitCode -in @(3010, 1641)) {
            $script:PendingReboot = $true
            Write-Info "$Label demande un redemarrage, verification finale maintenue."
        }

        if (Get-Command Clear-LDLCDetectionCaches -ErrorAction SilentlyContinue) {
            Clear-LDLCDetectionCaches
        }

        Wait-LDLCPostInstallProcesses -Installer $Installer -Label $Label -ValidationScript $ValidationScript
        if (Get-Command Clear-LDLCDetectionCaches -ErrorAction SilentlyContinue) {
            Clear-LDLCDetectionCaches
        }

        $validationTimeout = if ($Installer.ContainsKey('ValidationTimeoutSeconds')) {
            [int]$Installer.ValidationTimeoutSeconds
        }
        else { 120 }

        if (Wait-LDLCInstallerValidation -ValidationScript $ValidationScript -TimeoutSeconds $validationTimeout) {
            return [pscustomobject]@{
                Success  = $true
                Method   = $Method
                Path     = $Path
                ExitCode = $exitCode
                TimedOut = $timedOut
                Reason   = ''
            }
        }

        return [pscustomobject]@{
            Success  = $false
            Method   = $Method
            Path     = $Path
            ExitCode = $exitCode
            TimedOut = $timedOut
            Reason   = "verification finale negative apres code $codeLabel"
        }
    }
    catch {
        return [pscustomobject]@{
            Success  = $false
            Method   = $Method
            Path     = $Path
            ExitCode = -1
            TimedOut = $false
            Reason   = $_.Exception.Message
        }
    }
}

function Invoke-LDLCOfficialInstaller {
    param(
        [Parameter(Mandatory = $true)]$Installer,
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][scriptblock]$ValidationScript,
        [scriptblock]$DownloadAction,
        [scriptblock]$InstallAction
    )

    $cacheRoot = Get-LDLCInstallerCacheRoot
    $attemptedPaths = @{}
    $reasons = New-Object System.Collections.Generic.List[string]
    $sources = @(Get-LDLCOfficialInstallerSources -Installer $Installer)
    $downloadTimeout = if ($Installer.ContainsKey('DownloadTimeoutSeconds')) { [int]$Installer.DownloadTimeoutSeconds } else { 900 }
    $cacheDownloaded = -not ($Installer.ContainsKey('CacheDownloaded') -and -not [bool]$Installer.CacheDownloaded)

    foreach ($source in $sources) {
        Stop-IfRequested
        $fileName = if (-not [string]::IsNullOrWhiteSpace([string]$source.FileName)) {
            [string]$source.FileName
        }
        else {
            Get-LDLCInstallerFileNameFromUrl -Url $source.Url -FallbackName (($Label -replace '[^a-zA-Z0-9]+', '_') + '.exe')
        }

        $extension = [System.IO.Path]::GetExtension($fileName)
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
        $incomingPath = Join-Path $cacheRoot (".{0}.{1}.download{2}" -f $baseName, [guid]::NewGuid().ToString('N'), $extension)
        $downloadedPath = $incomingPath

        try {
            Write-Step "[INSTALL] Methode : officiel direct ($($source.Provider))"
            Write-Step "[INSTALL] Telechargement : $($source.Url)"
            if ($DownloadAction) {
                & $DownloadAction $source.Url $incomingPath
            }
            else {
                Invoke-LDLCWebDownload -Url $source.Url -Destination $incomingPath -TimeoutSeconds $downloadTimeout -RetryCount 2 | Out-Null
            }

            if (-not (Test-LDLCInstallerFile -Path $incomingPath -Installer $Installer -FreshDownload)) {
                throw 'package telecharge non valide (taille, format ou signature)'
            }

            if ($cacheDownloaded -and (Test-LDLCInstallerFile -Path $incomingPath -Installer $Installer -ForCache -FreshDownload)) {
                $downloadedPath = Join-Path $cacheRoot $fileName
                Move-Item -LiteralPath $incomingPath -Destination $downloadedPath -Force
                $downloadedHash = (Get-FileHash -LiteralPath $downloadedPath -Algorithm SHA256).Hash
                $downloadedHash | Set-Content -LiteralPath "$downloadedPath.sha256" -Encoding ASCII -Force
                Write-Ok "Installateur officiel mis en cache : $downloadedPath"
            }

            $attemptedPaths[[System.IO.Path]::GetFullPath($downloadedPath)] = $true
            $attempt = Invoke-LDLCOfficialInstallerAttempt `
                -Path $downloadedPath `
                -Installer $Installer `
                -Label $Label `
                -Method "officiel direct ($($source.Provider))" `
                -ValidationScript $ValidationScript `
                -InstallAction $InstallAction

            if ($attempt.Success) { return $attempt }
            [void]$reasons.Add("$($attempt.Method) : $($attempt.Reason)")
            Write-Info "[INSTALL] $Label non confirme via $($attempt.Method) : $($attempt.Reason)"
        }
        catch {
            $reason = $_.Exception.Message
            [void]$reasons.Add("telechargement $($source.Provider) : $reason")
            Write-Info "[INSTALL] Telechargement officiel indisponible pour $Label : $reason"
        }
        finally {
            if (Test-Path -LiteralPath $incomingPath) {
                Remove-Item -LiteralPath $incomingPath -Force -ErrorAction SilentlyContinue
            }
            if (-not $cacheDownloaded -and $downloadedPath -and (Test-Path -LiteralPath $downloadedPath)) {
                Remove-Item -LiteralPath $downloadedPath -Force -ErrorAction SilentlyContinue
            }
        }
    }

    foreach ($cachedPath in @(Get-LDLCCachedInstallerPaths -Installer $Installer)) {
        $fullCachedPath = [System.IO.Path]::GetFullPath($cachedPath)
        if ($attemptedPaths.ContainsKey($fullCachedPath)) {
            continue
        }

        $attemptedPaths[$fullCachedPath] = $true
        $attempt = Invoke-LDLCOfficialInstallerAttempt `
            -Path $cachedPath `
            -Installer $Installer `
            -Label $Label `
            -Method 'cache local' `
            -ValidationScript $ValidationScript `
            -InstallAction $InstallAction

        if ($attempt.Success) { return $attempt }
        [void]$reasons.Add("cache local $cachedPath : $($attempt.Reason)")
        Write-Info "[INSTALL] Cache local non valide pour $Label : $($attempt.Reason)"
    }

    $reasonText = if ($reasons.Count) { $reasons.ToArray() -join ' | ' } else { 'aucune source officielle ni aucun cache valide disponible' }
    return [pscustomobject]@{
        Success  = $false
        Method   = 'aucune'
        Path     = ''
        ExitCode = -1
        TimedOut = $false
        Reason   = $reasonText
    }
}

function Install-LDLCAppWithDirectInstaller {
    param($App)

    $script:LDLCLastOfficialInstallResult = $null
    if (-not $App.ContainsKey('DirectInstaller') -or -not $App.DirectInstaller) {
        return $false
    }

    $validation = { Test-AppReallyInstalled -App $App -Refresh }.GetNewClosure()
    $result = Invoke-LDLCOfficialInstaller `
        -Installer $App.DirectInstaller `
        -Label $App.Name `
        -ValidationScript $validation

    $script:LDLCLastOfficialInstallResult = $result
    if (-not $result.Success) {
        return $false
    }

    $state = Get-LDLCAppInstallationState -App $App -Refresh
    Write-Ok "$($App.Name) installee et confirmee via $($result.Method) ($(Format-LDLCAppInstallationState -State $state))."
    return $true
}

function Test-LDLCPackageManagerFallbackEnabled {
    if (Get-Command Get-LDLCBooleanEnvironmentValue -ErrorAction SilentlyContinue) {
        return (Get-LDLCBooleanEnvironmentValue -Name 'LDLC_ENABLE_PACKAGE_MANAGER_FALLBACK' -Default $false)
    }

    return $false
}

function Install-LDLCApplication {
    param(
        $App,
        [int]$ProgressPercent
    )

    Stop-IfRequested
    Write-Section "APPLICATION : $($App.Name)"

    $initialState = Get-LDLCAppInstallationState -App $App -Refresh
    if ($initialState.IsInstalled) {
        Write-Ok "$($App.Name) deja presente et confirmee ($(Format-LDLCAppInstallationState -State $initialState)). Installation ignoree."
        Write-ProgressFile $ProgressPercent "$($App.Name) deja presente. Verification du raccourci..."
        Ensure-DesktopShortcut -App $App
        return
    }

    if ($initialState.HasRegistry -and -not $initialState.HasExecutable) {
        Write-Info "$($App.Name) est referencee dans le registre mais son executable principal est absent : installation forcee."
    }

    Write-ProgressFile $ProgressPercent "Installation de $($App.Name)..."

    $installSuccess = $false
    $attemptedMethods = New-Object System.Collections.Generic.List[string]
    $failureReasons = New-Object System.Collections.Generic.List[string]

    Write-Step "[INSTALL] Methode prioritaire : installateur officiel avec cache local."
    [void]$attemptedMethods.Add('officiel direct/cache local')
    $installSuccess = Install-LDLCAppWithDirectInstaller -App $App
    if (-not $installSuccess -and $script:LDLCLastOfficialInstallResult) {
        [void]$failureReasons.Add([string]$script:LDLCLastOfficialInstallResult.Reason)
    }

    if (-not $installSuccess -and (Test-LDLCPackageManagerFallbackEnabled)) {
        Write-Info "Fallback gestionnaire de paquets active par LDLC_ENABLE_PACKAGE_MANAGER_FALLBACK."
        $wingetId = Get-LDLCAppWingetId -App $App

        if (-not [string]::IsNullOrWhiteSpace($wingetId)) {
            [void]$attemptedMethods.Add('winget optionnel')
            $installSuccess = Install-LDLCAppWithWinget -App $App -WingetId $wingetId
            if (-not $installSuccess) { [void]$failureReasons.Add('Winget optionnel non valide') }
        }

        if (-not $installSuccess -and -not [string]::IsNullOrWhiteSpace([string]$App.ChocoId)) {
            [void]$attemptedMethods.Add('chocolatey optionnel')
            $installSuccess = Install-LDLCAppWithChocolatey -App $App
            if (-not $installSuccess) { [void]$failureReasons.Add('Chocolatey optionnel non valide') }
        }
    }
    elseif (-not $installSuccess) {
        Write-Info "Winget/Chocolatey non utilises : fallback optionnel desactive."
    }

    if ($installSuccess) {
        $finalState = Get-LDLCAppInstallationState -App $App -Refresh
        if (-not $finalState.IsInstalled) {
            $installSuccess = $false
            [void]$failureReasons.Add("etat final incoherent : $(Format-LDLCAppInstallationState -State $finalState)")
        }
    }

    if ($installSuccess) {
        Write-ProgressFile $ProgressPercent "$($App.Name) installee et validee."
        Ensure-DesktopShortcut -App $App
        return
    }

    $methods = if ($attemptedMethods.Count) { ($attemptedMethods.ToArray() -join ', ') } else { 'aucune' }
    $causes = if ($failureReasons.Count) { ($failureReasons.ToArray() -join ' | ') } else { 'application absente apres verification finale' }
    Write-Err "Installation de $($App.Name) en echec. Methodes tentees : $methods. Cause : $causes."
}

# endregion Module: 30.Applications.ps1

# region Module: 40.Desktop.ps1
# Desktop, shortcuts, icons, and wallpaper helpers.


function Get-LDLCDesktopPaths {
    $paths = @(
        [Environment]::GetFolderPath("CommonDesktopDirectory"),
        [Environment]::GetFolderPath("Desktop"),
        "$env:USERPROFILE\OneDrive\Desktop"
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

    return @($paths)
}

function Get-LDLCPreferredDesktopPath {
    $commonDesktop = [Environment]::GetFolderPath("CommonDesktopDirectory")
    if (-not [string]::IsNullOrWhiteSpace($commonDesktop) -and (Test-Path $commonDesktop)) {
        return $commonDesktop
    }

    return [Environment]::GetFolderPath("Desktop")
}

$DesktopPath = Get-LDLCPreferredDesktopPath


function Get-LDLCUserDesktopPath {
    # The shell-folder registry value is the authoritative desktop location when
    # OneDrive redirection is enabled on a newly created Windows profile.
    try {
        $shellFoldersPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
        $configuredDesktop = (Get-ItemProperty -LiteralPath $shellFoldersPath -Name 'Desktop' -ErrorAction Stop).Desktop
        if (-not [string]::IsNullOrWhiteSpace([string]$configuredDesktop)) {
            $expandedDesktop = [Environment]::ExpandEnvironmentVariables([string]$configuredDesktop)
            if (-not [string]::IsNullOrWhiteSpace($expandedDesktop)) {
                return $expandedDesktop
            }
        }
    }
    catch {}

    $userDesktop = [Environment]::GetFolderPath("Desktop")
    if (-not [string]::IsNullOrWhiteSpace($userDesktop)) {
        return $userDesktop
    }

    if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
        return (Join-Path $env:USERPROFILE 'Desktop')
    }

    return $DesktopPath
}

function Initialize-LDLCDesktopRefreshType {
    if (-not ([System.Management.Automation.PSTypeName]'DesktopRefresh').Type) {
        Add-Type @"
using System;
using System.Runtime.InteropServices;
public class DesktopRefresh {
    [DllImport("shell32.dll")]
    public static extern void SHChangeNotify(int wEventId, uint uFlags, IntPtr dwItem1, IntPtr dwItem2);
}
"@
    }
}

function Refresh-Desktop {
    Stop-IfRequested
    Write-Step "Actualisation du bureau..."
    Initialize-LDLCDesktopRefreshType
    [DesktopRefresh]::SHChangeNotify(0x08000000, 0x0000, [IntPtr]::Zero, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 50
}

function Initialize-LDLCDesktopIconLayoutType {
    if (-not ([System.Management.Automation.PSTypeName]'LDLCDesktopIconLayout').Type) {
        Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;

public static class LDLCDesktopIconLayout
{
    private const int LVM_FIRST = 0x1000;
    private const int LVM_GETITEMCOUNT = LVM_FIRST + 4;
    private const int LVM_GETITEMTEXTW = LVM_FIRST + 115;
    private const int LVM_SETITEMPOSITION = LVM_FIRST + 15;
    private const uint PROCESS_VM_OPERATION = 0x0008;
    private const uint PROCESS_VM_READ = 0x0010;
    private const uint PROCESS_VM_WRITE = 0x0020;
    private const uint MEM_COMMIT = 0x1000;
    private const uint MEM_RESERVE = 0x2000;
    private const uint MEM_RELEASE = 0x8000;
    private const uint PAGE_READWRITE = 0x04;
    private const uint LVIF_TEXT = 0x0001;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct LVITEM
    {
        public uint mask;
        public int iItem;
        public int iSubItem;
        public uint state;
        public uint stateMask;
        public IntPtr pszText;
        public int cchTextMax;
        public int iImage;
        public IntPtr lParam;
        public int iIndent;
        public int iGroupId;
        public uint cColumns;
        public IntPtr puColumns;
        public IntPtr piColFmt;
        public int iGroup;
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr FindWindow(string lpClassName, string lpWindowName);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr FindWindowEx(IntPtr parentHandle, IntPtr childAfter, string className, string windowTitle);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr OpenProcess(uint desiredAccess, bool inheritHandle, uint processId);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(IntPtr handle);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr VirtualAllocEx(IntPtr process, IntPtr address, UIntPtr size, uint allocationType, uint protect);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool VirtualFreeEx(IntPtr process, IntPtr address, UIntPtr size, uint freeType);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool ReadProcessMemory(IntPtr process, IntPtr baseAddress, byte[] buffer, int size, out IntPtr numberOfBytesRead);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool WriteProcessMemory(IntPtr process, IntPtr baseAddress, byte[] buffer, int size, out IntPtr numberOfBytesWritten);

    private static IntPtr GetDesktopListView()
    {
        IntPtr progman = FindWindow("Progman", "Program Manager");
        IntPtr shellView = FindWindowEx(progman, IntPtr.Zero, "SHELLDLL_DefView", null);

        if (shellView == IntPtr.Zero)
        {
            IntPtr worker = IntPtr.Zero;
            while (true)
            {
                worker = FindWindowEx(IntPtr.Zero, worker, "WorkerW", null);
                if (worker == IntPtr.Zero) break;
                shellView = FindWindowEx(worker, IntPtr.Zero, "SHELLDLL_DefView", null);
                if (shellView != IntPtr.Zero) break;
            }
        }

        if (shellView == IntPtr.Zero) return IntPtr.Zero;
        return FindWindowEx(shellView, IntPtr.Zero, "SysListView32", "FolderView");
    }

    private static string GetItemText(IntPtr listView, IntPtr processHandle, IntPtr remoteLvi, IntPtr remoteText, int index)
    {
        LVITEM item = new LVITEM();
        item.mask = LVIF_TEXT;
        item.iItem = index;
        item.iSubItem = 0;
        item.pszText = remoteText;
        item.cchTextMax = 260;

        int lviSize = Marshal.SizeOf(typeof(LVITEM));
        byte[] lviBytes = new byte[lviSize];
        IntPtr localPtr = Marshal.AllocHGlobal(lviSize);
        try
        {
            Marshal.StructureToPtr(item, localPtr, false);
            Marshal.Copy(localPtr, lviBytes, 0, lviSize);
        }
        finally
        {
            Marshal.FreeHGlobal(localPtr);
        }

        IntPtr written;
        if (!WriteProcessMemory(processHandle, remoteLvi, lviBytes, lviBytes.Length, out written))
            return null;

        SendMessage(listView, LVM_GETITEMTEXTW, (IntPtr)index, remoteLvi);

        byte[] textBytes = new byte[520];
        IntPtr read;
        if (!ReadProcessMemory(processHandle, remoteText, textBytes, textBytes.Length, out read))
            return null;

        string value = Encoding.Unicode.GetString(textBytes);
        int zeroIndex = value.IndexOf('\0');
        if (zeroIndex >= 0) value = value.Substring(0, zeroIndex);
        return value.Trim();
    }

    public static bool PositionIcons(string[] orderedNames, int x, int startY, int stepY)
    {
        IntPtr listView = GetDesktopListView();
        if (listView == IntPtr.Zero) return false;

        uint processId;
        GetWindowThreadProcessId(listView, out processId);
        if (processId == 0) return false;

        IntPtr process = OpenProcess(PROCESS_VM_OPERATION | PROCESS_VM_READ | PROCESS_VM_WRITE, false, processId);
        if (process == IntPtr.Zero) return false;

        IntPtr remoteText = IntPtr.Zero;
        IntPtr remoteLvi = IntPtr.Zero;

        try
        {
            remoteText = VirtualAllocEx(process, IntPtr.Zero, (UIntPtr)520, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
            remoteLvi = VirtualAllocEx(process, IntPtr.Zero, (UIntPtr)Marshal.SizeOf(typeof(LVITEM)), MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
            if (remoteText == IntPtr.Zero || remoteLvi == IntPtr.Zero) return false;

            int itemCount = SendMessage(listView, LVM_GETITEMCOUNT, IntPtr.Zero, IntPtr.Zero).ToInt32();
            var indexByName = new System.Collections.Generic.Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);

            for (int i = 0; i < itemCount; i++)
            {
                string name = GetItemText(listView, process, remoteLvi, remoteText, i);
                if (!String.IsNullOrWhiteSpace(name) && !indexByName.ContainsKey(name))
                {
                    indexByName[name] = i;
                }
            }

            for (int pos = 0; pos < orderedNames.Length; pos++)
            {
                string wanted = orderedNames[pos];
                int idx;
                if (!indexByName.TryGetValue(wanted, out idx)) continue;

                int y = startY + (pos * stepY);
                int lParam = ((y & 0xFFFF) << 16) | (x & 0xFFFF);
                SendMessage(listView, LVM_SETITEMPOSITION, (IntPtr)idx, (IntPtr)lParam);
            }

            return true;
        }
        finally
        {
            if (remoteLvi != IntPtr.Zero) VirtualFreeEx(process, remoteLvi, UIntPtr.Zero, MEM_RELEASE);
            if (remoteText != IntPtr.Zero) VirtualFreeEx(process, remoteText, UIntPtr.Zero, MEM_RELEASE);
            CloseHandle(process);
        }
    }
}
"@
    }
}

function Set-LDLCDesktopOrderedLayout {
    Stop-IfRequested
    Write-Section "ORGANISATION DU BUREAU"

    $orderedNames = New-Object System.Collections.Generic.List[string]
    [void]$orderedNames.Add("Google Chrome")
    [void]$orderedNames.Add("LibreOffice")
    [void]$orderedNames.Add("Adobe Acrobat")
    [void]$orderedNames.Add("VLC media player")
    [void]$orderedNames.Add("Ce PC")
    [void]$orderedNames.Add("Utilisateur")

    try {
        $gpuInfo = Get-LDLCGpuVendor
        if ($gpuInfo -and (Test-LDLCDedicatedGpu -GpuInfo $gpuInfo)) {
            if ($gpuInfo.Vendor -eq 'NVIDIA') {
                [void]$orderedNames.Add("NVIDIA App")
            }
            elseif ($gpuInfo.Vendor -eq 'AMD') {
                [void]$orderedNames.Add("AMD Adrenalin")
            }

        }
    }
    catch {}

    Refresh-Desktop
    Start-Sleep -Milliseconds 1200

    try {
        Initialize-LDLCDesktopIconLayoutType
        $positioned = [LDLCDesktopIconLayout]::PositionIcons($orderedNames.ToArray(), 20, 90, 106)
        if ($positioned) {
            Write-Ok "Ordre visuel du bureau applique."
        }
        else {
            Write-Warn "Impossible de forcer l'ordre visuel du bureau."
        }
    }
    catch {
        Write-Warn "Impossible d'organiser le bureau : $($_.Exception.Message)"
    }

    Refresh-Desktop
}

function Remove-LDLCUserDiagDesktopItems {
    Stop-IfRequested

    foreach ($desktopRoot in (Get-LDLCDesktopPaths)) {
        Stop-IfRequested

        if (-not (Test-Path $desktopRoot)) {
            continue
        }

        foreach ($fileName in @('UserDiag.exe', 'userdiag.exe', 'UserDiag.lnk', 'userdiag.lnk')) {
            $candidatePath = Join-Path $desktopRoot $fileName

            if (Test-Path $candidatePath) {
                try {
                    Remove-Item -LiteralPath $candidatePath -Force -ErrorAction Stop
                    Write-Ok "Ancien element diagnostic supprime : $candidatePath"
                }
                catch {
                    Write-Warn "Ancien element diagnostic conserve car verrouille : $candidatePath"
                }
            }
        }

        $legacyArchives = @(Get-ChildItem -LiteralPath $desktopRoot -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like 'LDLCPreparationPC-*.zip' })
        foreach ($archive in $legacyArchives) {
            try {
                Remove-Item -LiteralPath $archive.FullName -Force -ErrorAction Stop
                Write-Ok "Archive LDLC obsolete supprimee du Bureau : $($archive.FullName)"
            }
            catch {
                Write-Warn "Archive LDLC obsolete conservee car verrouillee : $($archive.FullName)"
            }
        }
    }
}


function Get-StartMenuShortcutPath {
    param([string[]]$Names)

    $startMenuPaths = @(
        "$env:ProgramData\Microsoft\Windows\Start Menu\Programs",
        "$env:AppData\Microsoft\Windows\Start Menu\Programs"
    )

    foreach ($basePath in $startMenuPaths) {
        Stop-IfRequested

        if (-not (Test-Path $basePath)) { continue }

        try {
            $shortcuts = Get-ChildItem -Path $basePath -Filter *.lnk -Recurse -ErrorAction SilentlyContinue
            foreach ($shortcut in $shortcuts) {
                foreach ($name in $Names) {
                    if ($shortcut.BaseName -like "*$name*") {
                        return $shortcut.FullName
                    }
                }
            }
        }
        catch {}
    }

    return $null
}

function Remove-LibreOfficeDesktopShortcuts {
    Stop-IfRequested
    Write-Step "Nettoyage des raccourcis LibreOffice sur le bureau..."

    $desktopPaths = Get-LDLCDesktopPaths

    try {
        $ws = New-Object -ComObject WScript.Shell
    }
    catch {
        Write-Warn "Impossible d'initialiser WScript.Shell pour nettoyer les raccourcis LibreOffice : $($_.Exception.Message)"
        return
    }

    $canonicalShortcutPath = Join-Path $DesktopPath "LibreOffice.lnk"
    $removedCount = 0

    foreach ($path in $desktopPaths) {
        Stop-IfRequested

        if (-not (Test-Path $path)) {
            continue
        }

        try {
            $shortcuts = Get-ChildItem -Path $path -Filter *.lnk -File -ErrorAction SilentlyContinue

            foreach ($shortcut in $shortcuts) {
                $shouldRemove = $false

                if ($shortcut.BaseName -like "*LibreOffice*") {
                    $shouldRemove = $true
                }
                else {
                    try {
                        $target = $ws.CreateShortcut($shortcut.FullName).TargetPath
                        if ($target -and ($target -like "*LibreOffice*" -or $target -like "*soffice.exe")) {
                            $shouldRemove = $true
                        }
                    }
                    catch {}
                }

                if ($shouldRemove) {
                    if ($shortcut.FullName -ieq $canonicalShortcutPath) {
                        continue
                    }

                    Remove-Item $shortcut.FullName -Force -ErrorAction SilentlyContinue
                    Write-Ok "Raccourci LibreOffice supprime : $($shortcut.FullName)"
                    $removedCount++
                }
            }
        }
        catch {
            Write-Warn "Impossible d'analyser les raccourcis dans $path : $($_.Exception.Message)"
        }
    }

    if ($removedCount -eq 0) {
        Write-Step "Aucun raccourci LibreOffice a nettoyer."
        return
    }

    Refresh-Desktop
}

function Remove-LDLCShortcutDuplicates {
    param(
        [Parameter(Mandatory = $true)][string]$ShortcutName,
        [Parameter(Mandatory = $true)][string]$KeepPath
    )

    foreach ($desktopRoot in (Get-LDLCDesktopPaths)) {
        Stop-IfRequested

        $candidatePath = Join-Path $desktopRoot $ShortcutName
        if ($candidatePath -ieq $KeepPath) {
            continue
        }

        if (Test-Path $candidatePath) {
            Remove-Item $candidatePath -Force -ErrorAction SilentlyContinue
            Write-Ok "Ancien raccourci supprime : $candidatePath"
        }
    }
}


function Get-LDLCExistingExePathByNames {
    param(
        [string[]]$ExePaths,
        [string[]]$SearchFolders,
        [string[]]$ExeNames
    )

    foreach ($exeName in $ExeNames) {
        $targetExe = Get-ExistingExePath `
            -ExePaths $ExePaths `
            -SearchFolders $SearchFolders `
            -ExeName $exeName

        if ($targetExe) {
            return $targetExe
        }
    }

    return $null
}

function Ensure-LDLCDesktopShortcutFromTarget {
    param(
        [Parameter(Mandatory = $true)][string]$ShortcutName,
        [string]$TargetExe,
        [string[]]$StartMenuNames = @(),
        [switch]$MissingTargetIsInfo
    )

    Stop-IfRequested

    $desktopTargetPath = Get-LDLCUserDesktopPath
    $shortcutPath = Join-Path $desktopTargetPath $ShortcutName

    if ($StartMenuNames -and $StartMenuNames.Count -gt 0) {
        $startMenuShortcut = Get-StartMenuShortcutPath -Names $StartMenuNames

        if ($startMenuShortcut) {
            try {
                if (Test-Path $shortcutPath) {
                    Remove-Item $shortcutPath -Force -ErrorAction SilentlyContinue
                }

                Copy-Item $startMenuShortcut $shortcutPath -Force
                Remove-LDLCShortcutDuplicates -ShortcutName $ShortcutName -KeepPath $shortcutPath
                Write-Ok "Raccourci copie depuis le menu Demarrer : $ShortcutName"
                return
            }
            catch {
                Write-Warn "Impossible de copier le raccourci $ShortcutName depuis le menu Demarrer. Creation manuelle..."
            }
        }
    }

    if (-not $TargetExe -or -not (Test-Path $TargetExe)) {
        $message = "Executable introuvable, raccourci non cree : $ShortcutName"
        if ($MissingTargetIsInfo) { Write-Step $message } else { Write-Warn $message }
        return
    }

    if (Test-Path $shortcutPath) {
        try {
            $shell = New-Object -ComObject WScript.Shell
            $existingShortcut = $shell.CreateShortcut($shortcutPath)

            if ($existingShortcut.TargetPath -and (Test-Path $existingShortcut.TargetPath)) {
                if ($existingShortcut.TargetPath -ieq $TargetExe) {
                    Write-Ok "Raccourci deja present et valide : $ShortcutName"
                    return
                }
            }
        }
        catch {}

        Remove-Item $shortcutPath -Force -ErrorAction SilentlyContinue
    }

    try {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $TargetExe
        $shortcut.WorkingDirectory = Split-Path $TargetExe -Parent
        $shortcut.IconLocation = "$TargetExe,0"
        $shortcut.WindowStyle = 1
        $shortcut.Save()
        Remove-LDLCShortcutDuplicates -ShortcutName $ShortcutName -KeepPath $shortcutPath

        Write-Ok "Raccourci cree : $ShortcutName"
    }
    catch {
        Write-Warn "Impossible de creer le raccourci $ShortcutName : $($_.Exception.Message)"
    }
}

function Ensure-LDLCGpuDesktopShortcut {
    param([Parameter(Mandatory = $true)][string]$Vendor)

    switch ($Vendor) {
        'NVIDIA' {
            $targetExe = Get-LDLCExistingExePathByNames `
                -ExePaths @(
                    'C:\Program Files\NVIDIA Corporation\NVIDIA App\CEF\NVIDIA App.exe',
                    'C:\Program Files\NVIDIA Corporation\NVIDIA app\NVIDIA app.exe',
                    'C:\Program Files\NVIDIA Corporation\NVIDIA app\NVIDIAApp.exe'
                ) `
                -SearchFolders @(
                    "$env:ProgramFiles\NVIDIA Corporation\NVIDIA App",
                    "$env:ProgramFiles\NVIDIA Corporation",
                    "${env:ProgramFiles(x86)}\NVIDIA Corporation"
                ) `
                -ExeNames @('NVIDIA App.exe', 'NVIDIA app.exe', 'NVIDIAApp.exe')

            Ensure-LDLCDesktopShortcutFromTarget `
                -ShortcutName 'NVIDIA App.lnk' `
                -TargetExe $targetExe `
                -StartMenuNames @('NVIDIA App', 'NVIDIA app')
        }
        'AMD' {
            $targetExe = Get-LDLCExistingExePathByNames `
                -ExePaths @(
                    'C:\Program Files\AMD\CNext\CNext\RadeonSoftware.exe',
                    'C:\Program Files\AMD\CNext\CNext\AMDSoftware.exe',
                    'C:\Program Files\AMD\CNext\CNext\RadeonSoftware\RadeonSoftware.exe',
                    'C:\Program Files\AMD\CNext\CNext\RadeonSoftware\AMDSoftware.exe',
                    'C:\Program Files\AMD\CNext\CNext\AMDSoftware\AMDSoftware.exe',
                    'C:\Program Files (x86)\AMD\CNext\CNext\RadeonSoftware.exe',
                    'C:\Program Files (x86)\AMD\CNext\CNext\AMDSoftware.exe',
                    'C:\Program Files (x86)\AMD\CNext\CNext\RadeonSoftware\RadeonSoftware.exe',
                    'C:\Program Files (x86)\AMD\CNext\CNext\AMDSoftware\AMDSoftware.exe'
                ) `
                -SearchFolders @(
                    "$env:ProgramFiles\AMD",
                    "${env:ProgramFiles(x86)}\AMD",
                    'C:\AMD'
                ) `
                -ExeNames @('RadeonSoftware.exe', 'AMDSoftware.exe')

            Ensure-LDLCDesktopShortcutFromTarget `
                -ShortcutName 'AMD Adrenalin.lnk' `
                -TargetExe $targetExe `
                -StartMenuNames @('AMD Software', 'Adrenalin', 'Radeon Software') `
                -MissingTargetIsInfo
        }
    }
}

function Ensure-DesktopShortcut {
    param($App)

    Stop-IfRequested

    if ($App.Name -eq "LibreOffice") {
        Remove-LibreOfficeDesktopShortcuts
    }

    if (-not $App.CreateShortcut) {
        Write-Step "Aucun raccourci bureau demande pour cette application."
        return
    }

    $shortcutPath = Join-Path $DesktopPath $App.ShortcutName

    $startMenuNames = @()
    if ($App.ContainsKey('StartMenuNames') -and $App.StartMenuNames) {
        $startMenuNames += @($App.StartMenuNames)
    }

    if ($App.Name -eq "Adobe Acrobat Reader") {
        $startMenuNames += @(
            "Adobe Acrobat",
            "Adobe Acrobat Reader",
            "Adobe Reader"
        )
    }

    if ($startMenuNames.Count -gt 0) {
        $startMenuShortcut = Get-StartMenuShortcutPath -Names $startMenuNames

        if ($startMenuShortcut) {
            try {
                if (Test-Path $shortcutPath) {
                    Remove-Item $shortcutPath -Force -ErrorAction SilentlyContinue
                }

                Copy-Item $startMenuShortcut $shortcutPath -Force
                Remove-LDLCShortcutDuplicates -ShortcutName $App.ShortcutName -KeepPath $shortcutPath
                Write-Ok "Raccourci copie depuis le menu Demarrer : $($App.ShortcutName)"
                return
            }
            catch {
                Write-Warn "Impossible de copier le raccourci $($App.ShortcutName) depuis le menu Demarrer. Creation manuelle..."
            }
        }
        elseif ($App.Name -eq "Adobe Acrobat Reader") {
            Write-Warn "Raccourci Adobe introuvable dans le menu Demarrer. Creation manuelle..."
        }
    }

    $targetExe = Get-ExistingExePath `
        -ExePaths $App.ExePaths `
        -SearchFolders $App.SearchFolders `
        -ExeName $App.ExeName

    if (-not $targetExe) {
        Write-Warn "Executable introuvable, raccourci non cree : $($App.ShortcutName)"
        return
    }

    if (Test-Path $shortcutPath) {
        try {
            $shell = New-Object -ComObject WScript.Shell
            $existingShortcut = $shell.CreateShortcut($shortcutPath)

            if ($existingShortcut.TargetPath -and (Test-Path $existingShortcut.TargetPath)) {
                if ($existingShortcut.TargetPath -ieq $targetExe) {
                    Write-Ok "Raccourci deja present et valide : $($App.ShortcutName)"
                    return
                }
            }
        }
        catch {}

        Remove-Item $shortcutPath -Force -ErrorAction SilentlyContinue
    }

    try {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $targetExe
        $shortcut.WorkingDirectory = Split-Path $targetExe -Parent
        $shortcut.IconLocation = "$targetExe,0"
        $shortcut.WindowStyle = 1
        $shortcut.Save()
        Remove-LDLCShortcutDuplicates -ShortcutName $App.ShortcutName -KeepPath $shortcutPath

        Write-Ok "Raccourci cree : $($App.ShortcutName)"
    }
    catch {
        Write-Err "Impossible de creer le raccourci $($App.ShortcutName) : $($_.Exception.Message)"
    }
}

function Repair-LDLCDesktopShortcuts {
    Stop-IfRequested
    Write-Section "VERIFICATION DES RACCOURCIS"

    foreach ($app in $Apps | Where-Object { $_.CreateShortcut }) {
        try {
            Ensure-DesktopShortcut -App $app
        }
        catch {
            Write-Warn "Impossible de verifier le raccourci de $($app.Name) : $($_.Exception.Message)"
        }
    }


    try {
        $gpuInfo = Get-LDLCGpuVendor
        if ($gpuInfo -and (Test-LDLCDedicatedGpu -GpuInfo $gpuInfo)) {
            Ensure-LDLCGpuDesktopShortcut -Vendor $gpuInfo.Vendor
        }
        else {
            Write-Step "Pas de GPU dedie AMD/NVIDIA detecte : aucun element GPU ajoute au Bureau."
        }
    }
    catch {
        Write-Warn "Impossible de verifier les elements GPU du bureau : $($_.Exception.Message)"
    }
}
function Enable-DesktopSystemIcons {
    Stop-IfRequested

    Write-Section "CONFIGURATION DES ICONES DU BUREAU"

    $RegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel"

    if (-not (Test-Path $RegPath)) {
        New-Item -Path $RegPath -Force | Out-Null
    }

    $icons = @(
        @{
            Guid = "{20D04FE0-3AEA-1069-A2D8-08002B30309D}"
            Name = "Ce PC"
        },
        @{
            Guid = "{59031a47-3f72-44a7-89c5-5595fe6b30ee}"
            Name = "Dossier utilisateur"
        }
    )

    foreach ($icon in $icons) {
        Stop-IfRequested

        $guid = $icon.Guid
        $name = $icon.Name

        $current = (Get-ItemProperty -Path $RegPath -Name $guid -ErrorAction SilentlyContinue).$guid

        if ($current -eq 0) {
            Write-Ok "$name deja affiche"
        }
        else {
            Write-Step "Activation de $name..."
            Set-ItemProperty -Path $RegPath -Name $guid -Value 0 -Type DWord -Force
            Write-Ok "$name active"
        }
    }

    Refresh-Desktop
}


# endregion Module: 40.Desktop.ps1

# region Module: 45.Wallpaper.ps1
# Wallpaper configuration helpers.

function Initialize-LDLCWallpaperType {
    if (-not ([System.Management.Automation.PSTypeName]'WallpaperManager').Type) {
        Add-Type @"
using System.Runtime.InteropServices;
public class WallpaperManager {
    [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)]
    public static extern bool SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
"@
    }
}

function Set-LDLCWallpaperRegistryValues {
    param(
        [Parameter(Mandatory = $true)][string]$DesktopRegistryPath,
        [Parameter(Mandatory = $true)][string]$WallpaperPath
    )

    if (-not (Test-Path $DesktopRegistryPath)) {
        New-Item -Path $DesktopRegistryPath -Force | Out-Null
    }

    New-ItemProperty -Path $DesktopRegistryPath -Name Wallpaper -Value $WallpaperPath -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $DesktopRegistryPath -Name WallpaperStyle -Value "10" -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $DesktopRegistryPath -Name TileWallpaper -Value "0" -PropertyType String -Force | Out-Null
}

function Set-LDLCExplorerWallpaperMode {
    param([Parameter(Mandatory = $true)][string]$RegistryRoot)

    $wallpaperModePath = Join-Path $RegistryRoot 'Software\Microsoft\Windows\CurrentVersion\Explorer\Wallpapers'
    if (-not (Test-Path $wallpaperModePath)) {
        New-Item -Path $wallpaperModePath -Force | Out-Null
    }

    New-ItemProperty -Path $wallpaperModePath -Name BackgroundType -Value 0 -PropertyType DWord -Force | Out-Null
}

function Copy-LDLCWallpaperToThemeCache {
    param([Parameter(Mandatory = $true)][string]$WallpaperPath)

    if ([string]::IsNullOrWhiteSpace($env:APPDATA)) {
        return
    }

    $themesDir = Join-Path $env:APPDATA 'Microsoft\Windows\Themes'
    if (-not (Test-Path $themesDir)) {
        New-Item -ItemType Directory -Path $themesDir -Force | Out-Null
    }

    Copy-Item -Path $WallpaperPath -Destination (Join-Path $themesDir 'TranscodedWallpaper') -Force
}

function Set-LDLCCurrentUserWallpaper {
    param([Parameter(Mandatory = $true)][string]$WallpaperPath)

    Set-LDLCWallpaperRegistryValues -DesktopRegistryPath 'HKCU:\Control Panel\Desktop' -WallpaperPath $WallpaperPath
    Set-LDLCExplorerWallpaperMode -RegistryRoot 'HKCU:'
    Copy-LDLCWallpaperToThemeCache -WallpaperPath $WallpaperPath
}

function Set-LDLCLoadedUsersWallpaper {
    param([Parameter(Mandatory = $true)][string]$WallpaperPath)

    $loadedUserSids = Get-ChildItem 'Registry::HKEY_USERS' -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -match '^S-1-5-21-\d+-\d+-\d+-\d+$' } |
        Select-Object -ExpandProperty PSChildName

    foreach ($sid in $loadedUserSids) {
        try {
            $userRoot = "Registry::HKEY_USERS\$sid"
            Set-LDLCWallpaperRegistryValues -DesktopRegistryPath (Join-Path $userRoot 'Control Panel\Desktop') -WallpaperPath $WallpaperPath
            Set-LDLCExplorerWallpaperMode -RegistryRoot $userRoot
        }
        catch {
            Write-Step "Profil charge $sid ignore pour le fond d'ecran : $($_.Exception.Message)"
        }
    }
}

function Set-LDLCDefaultUserWallpaper {
    param(
        [Parameter(Mandatory = $true)][string]$WallpaperPath
    )

    $defaultProfileHivePath = Join-Path $env:SystemDrive 'Users\Default\NTUSER.DAT'
    if (-not (Test-Path $defaultProfileHivePath)) {
        Write-Step "Profil utilisateur par defaut introuvable : fond d'ecran futur profil ignore."
        return $false
    }

    $hiveName = 'HKU\LDLCDefaultUser'
    $registryRoot = 'Registry::HKEY_USERS\LDLCDefaultUser'
    $hiveLoadedHere = $false

    try {
        & reg.exe load $hiveName $defaultProfileHivePath | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Chargement du profil par defaut impossible (code $LASTEXITCODE)."
        }

        $hiveLoadedHere = $true

        Set-LDLCWallpaperRegistryValues -DesktopRegistryPath (Join-Path $registryRoot 'Control Panel\Desktop') -WallpaperPath $WallpaperPath
        Set-LDLCExplorerWallpaperMode -RegistryRoot $registryRoot
        Write-Ok "Fond d'ecran prepare pour les futurs utilisateurs."
        return $true
    }
    catch {
        Write-Step "Profil utilisateur par defaut ignore pour le fond d'ecran : $($_.Exception.Message)"
        return $false
    }
    finally {
        if ($hiveLoadedHere) {
            & reg.exe unload $hiveName | Out-Null
        }
    }
}

function Write-LDLCWallpaperFailure {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [switch]$QuietFailure
    )

    if ($QuietFailure) {
        Write-Step $Message
    }
    else {
        Write-Err $Message
    }
}

function Get-LDLCCurrentWallpaperPath {
    try {
        return [string](Get-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name Wallpaper -ErrorAction Stop).Wallpaper
    }
    catch {
        return ''
    }
}

function Test-LDLCWallpaperApplied {
    param([string]$ExpectedPath = $script:LDLCWallpaperExpectedPath)

    if ([string]::IsNullOrWhiteSpace($ExpectedPath)) {
        return $false
    }

    if (-not (Test-Path -LiteralPath $ExpectedPath)) {
        return $false
    }

    $currentPath = Get-LDLCCurrentWallpaperPath
    if ([string]::IsNullOrWhiteSpace($currentPath)) {
        return $false
    }

    try {
        $expectedFullPath = [System.IO.Path]::GetFullPath($ExpectedPath)
        $currentFullPath = [System.IO.Path]::GetFullPath($currentPath)
        return ($expectedFullPath -ieq $currentFullPath)
    }
    catch {
        return ($ExpectedPath -ieq $currentPath)
    }
}

function Set-LDLCWallpaper {
    param(
        [int]$ProgressPercent = 81,
        [switch]$IgnoreStopRequest,
        [switch]$QuietFailure
    )

    if (-not $IgnoreStopRequest) {
        Stop-IfRequested
    }

    Write-Section "CONFIGURATION DU FOND D'ECRAN"
    Write-ProgressFile $ProgressPercent "Configuration du fond d'ecran..." -IgnoreStopRequest:$IgnoreStopRequest

    try {
        $targetDir = Join-Path $env:ProgramData "LDLC\Wallpaper"
        $sourceWall = Resolve-LDLCAssetPath -RelativePaths @(
            'LDLC.png',
            'ldlc.png',
            'images\LDLC.png',
            'images\ldlc.png',
            'LDLC.jpg',
            'ldlc.jpg',
            'images\LDLC.jpg',
            'images\ldlc.jpg'
        )

        if (-not $sourceWall) {
            Write-LDLCWallpaperFailure -Message "Image source introuvable : LDLC.png ou LDLC.jpg" -QuietFailure:$QuietFailure
            return $false
        }

        $wallpaperExtension = [System.IO.Path]::GetExtension($sourceWall)
        if ([string]::IsNullOrWhiteSpace($wallpaperExtension)) {
            $wallpaperExtension = ".png"
        }

        $wallpaperFileName = "LDLC$wallpaperExtension"
        $machineWallpaperPath = Join-Path $targetDir $wallpaperFileName

        $userPicturesDir = Join-Path $env:USERPROFILE "Pictures"
        if (-not (Test-Path $userPicturesDir)) {
            New-Item -ItemType Directory -Path $userPicturesDir -Force | Out-Null
        }

        $userWallpaperPath = Join-Path $userPicturesDir $wallpaperFileName
        Copy-Item $sourceWall $userWallpaperPath -Force

        $targetWall = $machineWallpaperPath
        $machineWallpaperReady = $true

        try {
            if (-not (Test-Path $targetDir)) {
                Write-Step "Creation du dossier fond d'ecran machine..."
                New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
            }

            Write-Step "Copie de l'image du fond d'ecran machine..."
            Copy-Item $sourceWall $machineWallpaperPath -Force
        }
        catch {
            $machineWallpaperReady = $false
            $targetWall = $userWallpaperPath
            Write-Step "Copie machine indisponible, utilisation du fond d'ecran utilisateur : $($_.Exception.Message)"
        }

        $script:LDLCWallpaperExpectedPath = $targetWall

        Write-Step "Enregistrement du fond d'ecran dans le registre..."
        Set-LDLCCurrentUserWallpaper -WallpaperPath $targetWall

        if ($machineWallpaperReady) {
            Set-LDLCLoadedUsersWallpaper -WallpaperPath $targetWall
        }
        else {
            Write-Step "Persistance multi-utilisateur ignoree car le chemin machine n'est pas disponible."
        }

        Write-Step "Application du fond d'ecran..."
        Initialize-LDLCWallpaperType
        $result = [WallpaperManager]::SystemParametersInfo(20, 0, $targetWall, 3)

        if (-not $result) {
            $win32Error = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
            Write-LDLCWallpaperFailure -Message "Impossible d'appliquer le fond d'ecran. Code Win32 : $win32Error" -QuietFailure:$QuietFailure
            return $false
        }

        if ($machineWallpaperReady) {
            Set-LDLCDefaultUserWallpaper -WallpaperPath $targetWall | Out-Null
        }
        else {
            Write-Step "Profil utilisateur par defaut ignore car le chemin machine n'est pas disponible."
        }

        Write-Ok "Fond d'ecran LDLC applique et sauvegarde pour le redemarrage."
        Write-ProgressFile $ProgressPercent "Fond d'ecran configure." -IgnoreStopRequest:$IgnoreStopRequest
        return $true
    }
    catch {
        Write-LDLCWallpaperFailure -Message "Erreur configuration fond d'ecran : $($_.Exception.Message)" -QuietFailure:$QuietFailure
        return $false
    }
}

function Ensure-LDLCWallpaperApplied {
    param(
        [int]$ProgressPercent = 81,
        [switch]$IgnoreStopRequest,
        [switch]$VerifyOnly
    )

    if (-not $IgnoreStopRequest) {
        Stop-IfRequested
    }

    if ($VerifyOnly -and (Test-LDLCWallpaperApplied)) {
        Write-Ok "Fond d'ecran LDLC confirme lors de la verification finale."
        Write-ProgressFile $ProgressPercent "Fond d'ecran confirme." -IgnoreStopRequest:$IgnoreStopRequest
        return $true
    }

    if ($VerifyOnly) {
        $currentWallpaper = Get-LDLCCurrentWallpaperPath
        Write-Step "Fond d'ecran LDLC non confirme lors de la verification finale. Actuel : $(if ($currentWallpaper) { $currentWallpaper } else { 'non renseigne' })"
    }

    for ($attempt = 1; $attempt -le 2; $attempt++) {
        if (-not $IgnoreStopRequest) {
            Stop-IfRequested
        }

        $attemptMessage = if ($attempt -eq 1) { "Application du fond d'ecran LDLC..." } else { "Nouvelle tentative fond d'ecran LDLC..." }
        Write-ProgressFile $ProgressPercent $attemptMessage -IgnoreStopRequest:$IgnoreStopRequest

        $applied = Set-LDLCWallpaper -ProgressPercent $ProgressPercent -IgnoreStopRequest:$IgnoreStopRequest -QuietFailure
        if ($applied -and (Test-LDLCWallpaperApplied)) {
            if ($attempt -eq 1 -and -not $VerifyOnly) {
                Write-Ok "Fond d'ecran LDLC verifie."
            }
            elseif ($attempt -gt 1) {
                Write-Ok "Fond d'ecran LDLC confirme apres nouvelle tentative."
            }
            else {
                Write-Ok "Fond d'ecran LDLC confirme lors de la verification finale."
            }

            Write-ProgressFile $ProgressPercent "Fond d'ecran confirme." -IgnoreStopRequest:$IgnoreStopRequest
            return $true
        }

        if ($attempt -lt 2) {
            Write-Step "Fond d'ecran LDLC non confirme apres tentative $attempt. Nouvelle tentative..."
            Start-Sleep -Milliseconds 600
        }
    }

    $expectedWallpaper = if ($script:LDLCWallpaperExpectedPath) { $script:LDLCWallpaperExpectedPath } else { 'non renseigne' }
    $currentWallpaper = Get-LDLCCurrentWallpaperPath
    if ([string]::IsNullOrWhiteSpace($currentWallpaper)) {
        $currentWallpaper = 'non renseigne'
    }

    Write-Warn "Fond d'ecran LDLC non confirme apres deux tentatives. Attendu : $expectedWallpaper ; actuel : $currentWallpaper"
    Write-ProgressFile $ProgressPercent "Fond d'ecran non confirme, preparation continue." -IgnoreStopRequest:$IgnoreStopRequest
    return $false
}

# endregion Module: 45.Wallpaper.ps1

# region Module: 50.Cleanup.ps1
# Installed-program inventory and cleanup helpers.

function Get-LDLCInstalledPrograms {
    param([switch]$Refresh)

    $cacheIsValid = (
        -not $Refresh -and
        $null -ne $script:InstalledProgramsCache -and
        ((Get-Date) - $script:InstalledProgramsCacheTimestamp).TotalSeconds -lt $script:InstalledProgramsCacheTtlSeconds
    )

    if ($cacheIsValid) {
        return $script:InstalledProgramsCache
    }

    $paths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    $programs = foreach ($path in $paths) {
        Get-ItemProperty -Path $path -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName } |
            Select-Object DisplayName, DisplayVersion, Publisher, InstallLocation, DisplayIcon, UninstallString, QuietUninstallString, PSChildName
    }

    $script:InstalledProgramsCache = @($programs)
    $script:InstalledProgramsCacheTimestamp = Get-Date
    return $script:InstalledProgramsCache
}

function Test-LDLCDedicatedGpu {
    param(
        [Parameter(Mandatory = $true)]$GpuInfo
    )

    if (-not $GpuInfo -or -not $GpuInfo.Gpu) {
        return $false
    }

    $gpuName = [string]$GpuInfo.Gpu.Name
    $adapterRam = 0

    try {
        $adapterRam = [int64]$GpuInfo.Gpu.AdapterRAM
    }
    catch {}

    switch ($GpuInfo.Vendor) {
        'NVIDIA' {
            return $true
        }
        'AMD' {
            return ($gpuName -match '(?i)AMD|ATI|Radeon' -or $adapterRam -gt 0)
        }
        default {
            return $false
        }
    }
}

function Get-LDLCGpuVendor {
    try {
        $gpu = Get-CimInstance Win32_VideoController -ErrorAction Stop |
            Where-Object {
                $_.PNPDeviceID -match 'VEN_10DE|VEN_1002|VEN_1022' -or
                $_.AdapterCompatibility -match 'NVIDIA|AMD|ATI'
            } |
            Select-Object -First 1

        if (-not $gpu) { return $null }

        $vendorText = @(
            $gpu.Name,
            $gpu.AdapterCompatibility,
            $gpu.PNPDeviceID
        ) -join ' '

        if ($vendorText -match 'NVIDIA|VEN_10DE') {
            return [pscustomobject]@{ Vendor = 'NVIDIA'; Gpu = $gpu }
        }

        if ($vendorText -match 'AMD|ATI|VEN_1002|VEN_1022') {
            return [pscustomobject]@{ Vendor = 'AMD'; Gpu = $gpu }
        }
    }
    catch {
        Write-Warn "Impossible de detecter le GPU : $($_.Exception.Message)"
    }

    return $null
}

function Get-LDLCDriverVersion {
    param([string]$Vendor)

    $driver = Get-LDLCDisplayDriverInfo -Vendor $Vendor
    if ($driver) {
        return $driver.DriverVersion
    }

    return $null
}

function Get-LDLCDisplayDriverInfo {
    param([string]$Vendor)

    try {
        $match = switch ($Vendor) {
            'NVIDIA' { 'NVIDIA|VEN_10DE' }
            'AMD'    { 'Advanced Micro Devices|AMD|ATI|VEN_1002|VEN_1022' }
            default  { $null }
        }

        if (-not $match) { return $null }

        $driver = Get-CimInstance Win32_PnPSignedDriver -ErrorAction Stop |
            Where-Object {
                $_.DeviceClass -eq 'DISPLAY' -and
                (($_.Manufacturer -as [string]) -match $match -or (($_.DeviceID -as [string]) -match $match))
            } |
            Sort-Object DriverDate -Descending |
            Select-Object -First 1

        return $driver
    }
    catch {}

    return $null
}

function Get-LDLCInstalledVendorDisplayDriver {
    param([string]$Vendor)

    $driver = Get-LDLCDisplayDriverInfo -Vendor $Vendor
    if (-not $driver) {
        return $null
    }

    $driverText = @(
        [string]$driver.Manufacturer,
        [string]$driver.DriverProviderName,
        [string]$driver.DeviceName,
        [string]$driver.FriendlyName
    ) -join ' '

    if ($driverText -match '(?i)Microsoft Basic Display|Microsoft Corporation|Microsoft$') {
        return $null
    }

    switch ($Vendor) {
        'NVIDIA' {
            if ($driverText -match '(?i)NVIDIA') { return $driver }
        }
        'AMD' {
            if ($driverText -match '(?i)Advanced Micro Devices|AMD|ATI') { return $driver }
        }
    }

    return $null
}

function Invoke-LDLCWebDownload {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$Destination,
        [int]$TimeoutSeconds = 300,
        [int]$RetryCount = 2
    )

    Stop-IfRequested

    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    }
    catch {}

    $headers = @{ 'User-Agent' = 'LDLCPrepTool/2.4' }
    $lastError = $null
    $attemptCount = [math]::Max(1, $RetryCount)

    for ($attempt = 1; $attempt -le $attemptCount; $attempt++) {
        Stop-IfRequested
        Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue

        try {
            $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
            if ($curl -and -not [string]::IsNullOrWhiteSpace($curl.Source)) {
                $stdoutPath = Join-Path ([System.IO.Path]::GetTempPath()) ('LDLC_curl_' + [guid]::NewGuid().ToString('N') + '.out.log')
                $stderrPath = Join-Path ([System.IO.Path]::GetTempPath()) ('LDLC_curl_' + [guid]::NewGuid().ToString('N') + '.err.log')
                try {
                    $curlArgs = @(
                        '-L',
                        '--fail',
                        '--silent',
                        '--show-error',
                        '--connect-timeout', '30',
                        '--max-time', ([string][math]::Max(30, $TimeoutSeconds)),
                        '-A', $headers['User-Agent'],
                        '-o', $Destination,
                        $Url
                    )

                    & $curl.Source @curlArgs > $stdoutPath 2> $stderrPath
                    $curlExitCode = [int]$LASTEXITCODE
                    if ($curlExitCode -ne 0) {
                        $tail = ''
                        if (Test-Path -LiteralPath $stderrPath) {
                            $tail = ((Get-Content -LiteralPath $stderrPath -ErrorAction SilentlyContinue | Select-Object -Last 6) -join ' ')
                        }
                        throw "curl retourne le code $curlExitCode. $tail"
                    }

                    if (-not (Test-Path -LiteralPath $Destination -PathType Leaf) -or (Get-Item -LiteralPath $Destination).Length -le 0) {
                        throw 'curl a termine sans produire de fichier valide.'
                    }
                }
                finally {
                    Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue
                }
            }
            else {
                Invoke-WebRequest `
                    -Uri $Url `
                    -Headers $headers `
                    -OutFile $Destination `
                    -UseBasicParsing `
                    -TimeoutSec ([math]::Max(30, $TimeoutSeconds))
            }

            return $Destination
        }
        catch {
            $lastError = $_
            if ($attempt -lt $attemptCount) {
                Write-Info "Telechargement interrompu (tentative $attempt/$attemptCount), nouvelle tentative dans 2 secondes."
                Start-Sleep -Seconds 2
            }
        }
    }

    Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
    throw "Telechargement impossible apres $attemptCount tentative(s) : $($lastError.Exception.Message)"
}

function Get-LDLCRemoversFolder {
    $folder = Join-Path $env:TEMP "LDLC_Removers"

    if (-not (Test-Path $folder)) {
        New-Item -Path $folder -ItemType Directory -Force | Out-Null
    }

    return $folder
}

function Get-LDLCOemRemovalProfile {
    param($Program)

    $displayName = [string]$Program.DisplayName
    $publisher = [string]$Program.Publisher

    if (
        $displayName -match '(?i)\bMcAfee\b|True Key|WebAdvisor|Security Scan Plus|Safe Connect' -or
        $publisher -match '(?i)\bMcAfee\b'
    ) {
        return [pscustomobject]@{
            Group      = 'McAfee'
            Category   = 'Antivirus'
            Label      = 'McAfee'
            SupportUrl = 'https://www.mcafee.com/support/?articleId=TS101331&page=shell&shell=article-view'
            ToolUrl    = 'https://download.mcafee.com/products/licensed/cust_support_patches/MCPR.exe'
            ToolName   = 'MCPR.exe'
        }
    }

    $nortonExcluded = '(?i)Private Browser|Utilities|Password Manager|Family|VPN|AntiTrack|Driver Updater|Software Updater'
    $nortonDisplayPattern = '(?i)\bNorton\b|LifeLock'
    $nortonSecurityHintPattern = '(?i)Security|AntiVirus|Device Security|Internet Security|360'

    if (
        (
            $displayName -match $nortonDisplayPattern -or
            (($publisher -match '(?i)Norton|Symantec|Gen Digital') -and $displayName -match $nortonSecurityHintPattern)
        ) -and
        $displayName -notmatch $nortonExcluded
    ) {
        $versionMajor = 0
        try { $versionMajor = [int](([string]$Program.DisplayVersion -split '\.')[0]) } catch {}

        return [pscustomobject]@{
            Group      = 'Norton'
            Category   = 'Antivirus'
            Label      = 'Norton'
            SupportUrl = 'https://support.norton.com/sp/en/us/home/current/solutions/kb20090505015136EN'
            ToolUrl    = $(if ($versionMajor -ge 24) { 'https://www.norton.com/nortonremover' } else { 'https://norton.com/nrnr' })
            ToolName   = $(if ($versionMajor -ge 24) { 'Norton_360_remover.exe' } else { 'NRnR.exe' })
        }
    }

    $promoProfiles = @(
        @{ Pattern = '(?i)WildTangent'; Publisher = '(?i)WildTangent'; Label = 'WildTangent'; Group = 'WildTangent' },
        @{ Pattern = '(?i)\bBooking\.com\b'; Publisher = '(?i)Booking'; Label = 'Booking.com'; Group = 'Booking' },
        @{ Pattern = '(?i)\bExpressVPN\b'; Publisher = '(?i)ExpressVPN'; Label = 'ExpressVPN'; Group = 'ExpressVPN' },
        @{ Pattern = '(?i)Dropbox Promotion'; Publisher = '(?i)Dropbox'; Label = 'Dropbox Promotion'; Group = 'DropboxPromotion' },
        @{ Pattern = '(?i)\bKeeper(\sPassword Manager)?\b'; Publisher = '(?i)Keeper'; Label = 'Keeper'; Group = 'Keeper' }
    )

    foreach ($promoProfile in $promoProfiles) {
        if ($displayName -match $promoProfile.Pattern -or $publisher -match $promoProfile.Publisher) {
            return [pscustomobject]@{
                Group      = $promoProfile.Group
                Category   = 'OEM'
                Label      = $promoProfile.Label
                SupportUrl = $null
                ToolUrl    = $null
                ToolName   = $null
            }
        }
    }

    return $null
}

function Get-LDLCOemRemovalTargets {
    param(
        [ValidateSet('All', 'Security', 'Oem')]
        [string]$Mode = 'All'
    )

    $targets = foreach ($program in (Get-LDLCInstalledPrograms -Refresh)) {
        $profile = Get-LDLCOemRemovalProfile -Program $program
        $include = (
            $profile -and (
                $Mode -eq 'All' -or
                ($Mode -eq 'Security' -and $profile.Category -eq 'Antivirus') -or
                ($Mode -eq 'Oem' -and $profile.Category -eq 'OEM')
            )
        )

        if ($include) {
            [pscustomobject]@{
                Profile = $profile
                Program = $program
            }
        }
    }

    return @(
        $targets |
            Group-Object { "{0}|{1}|{2}" -f $_.Profile.Group, $_.Program.DisplayName, $_.Program.PSChildName } |
            ForEach-Object { $_.Group[0] } |
            Sort-Object { if ($_.Profile.Category -eq 'Antivirus') { 0 } else { 1 } }, { $_.Program.DisplayName }
    )
}

function Split-LDLCCommandLine {
    param([string]$CommandLine)

    if ([string]::IsNullOrWhiteSpace($CommandLine)) {
        return $null
    }

    $trimmed = $CommandLine.Trim()
    if ($trimmed -match '^(?:"([^"]+)"|([^\s]+))\s*(.*)$') {
        $filePath = if ($matches[1]) { $matches[1] } else { $matches[2] }
        $arguments = $matches[3]

        return [pscustomobject]@{
            FilePath  = $filePath
            Arguments = $arguments.Trim()
        }
    }

    return $null
}

function ConvertTo-LDLCSilentMsiArgs {
    param([string]$RawCommandLine)

    $arguments = ($RawCommandLine -replace '^(?i)\s*(?:msiexec(?:\.exe)?)\s*', '').Trim()

    if ($arguments -match '^(?i)/I\s*({[^}]+})$') {
        $arguments = "/X $($matches[1])"
    }
    elseif ($arguments -match '^(?i)/I({[^}]+})$') {
        $arguments = "/X $($matches[1])"
    }
    else {
        $arguments = [regex]::Replace($arguments, '(?i)(^|\s)/I(\s*{[^}]+})', '$1/X$2')
    }

    if ($arguments -notmatch '(?i)\s/q(?:n|b|r|f)?\b|\s/quiet\b') {
        $arguments = "$arguments /qn"
    }

    if ($arguments -notmatch '(?i)REBOOT=ReallySuppress|/norestart\b') {
        $arguments = "$arguments /norestart REBOOT=ReallySuppress"
    }

    return $arguments.Trim()
}

function Test-LDLCCommandLooksSilent {
    param([string]$Arguments)

    return ($Arguments -match '(?i)\s/q(?:n|b|r|f)?\b|\s/quiet\b|\s/silent\b|\s/verysilent\b')
}

function Get-LDLCSilentUninstallCommands {
    param($Program)

    $candidates = New-Object System.Collections.Generic.List[object]
    $seen = @{}

    foreach ($entry in @(
        @{ Source = 'QuietUninstallString'; CommandLine = $Program.QuietUninstallString },
        @{ Source = 'UninstallString'; CommandLine = $Program.UninstallString }
    )) {
        $rawCommandLine = [string]$entry.CommandLine
        if ([string]::IsNullOrWhiteSpace($rawCommandLine)) {
            continue
        }

        if ($rawCommandLine -match '(?i)\bmsiexec(?:\.exe)?\b') {
            $filePath = Join-Path $env:SystemRoot 'System32\msiexec.exe'
            $arguments = ConvertTo-LDLCSilentMsiArgs -RawCommandLine $rawCommandLine
            $fingerprint = "{0}|{1}" -f $filePath.ToLowerInvariant(), $arguments.ToLowerInvariant()

            if (-not $seen.ContainsKey($fingerprint)) {
                $seen[$fingerprint] = $true
                $candidates.Add([pscustomobject]@{
                    FilePath    = $filePath
                    Arguments   = $arguments
                    Description = "$($entry.Source) MSI silencieux"
                })
            }

            continue
        }

        $parsed = Split-LDLCCommandLine -CommandLine $rawCommandLine
        if (-not $parsed) {
            continue
        }

        $argumentCandidates = New-Object System.Collections.Generic.List[string]
        $baseArguments = [string]$parsed.Arguments

        if (Test-LDLCCommandLooksSilent -Arguments $baseArguments) {
            $argumentCandidates.Add($baseArguments)
        }
        else {
            $exeName = [System.IO.Path]::GetFileName([string]$parsed.FilePath)
            $looksLikeUninstaller = (
                $exeName -match '(?i)^unins' -or
                $baseArguments -match '(?i)\buninstall\b|\bremove\b' -or
                $parsed.FilePath -match '(?i)mcafee|norton|symantec|wildtangent|booking|expressvpn|keeper|dropbox'
            )

            if ($looksLikeUninstaller) {
                if ($exeName -match '(?i)^unins') {
                    $argumentCandidates.Add(("$baseArguments /VERYSILENT /SUPPRESSMSGBOXES /NORESTART").Trim())
                }

                $argumentCandidates.Add(("$baseArguments /quiet /norestart").Trim())
                $argumentCandidates.Add(("$baseArguments /silent").Trim())
                $argumentCandidates.Add(("$baseArguments /S").Trim())
            }
        }

        foreach ($arguments in $argumentCandidates | Select-Object -Unique) {
            $fingerprint = "{0}|{1}" -f ([string]$parsed.FilePath).ToLowerInvariant(), ([string]$arguments).ToLowerInvariant()
            if (-not $seen.ContainsKey($fingerprint)) {
                $seen[$fingerprint] = $true
                $candidates.Add([pscustomobject]@{
                    FilePath    = $parsed.FilePath
                    Arguments   = $arguments
                    Description = "$($entry.Source) tente silencieuse"
                })
            }
        }
    }

    return $candidates
}

function Test-LDLCProgramStillInstalled {
    param($Program)

    foreach ($current in (Get-LDLCInstalledPrograms -Refresh)) {
        if ($Program.PSChildName -and $current.PSChildName -eq $Program.PSChildName) {
            return $true
        }

        if (
            $current.DisplayName -eq $Program.DisplayName -and
            [string]::Equals([string]$current.Publisher, [string]$Program.Publisher, [System.StringComparison]::OrdinalIgnoreCase)
        ) {
            return $true
        }
    }

    return $false
}

function Save-LDLCOemRemovalFallback {
    param($Target)

    $profile = $Target.Profile
    if ([string]::IsNullOrWhiteSpace([string]$profile.ToolUrl)) {
        return $null
    }

    $folder = Get-LDLCRemoversFolder
    $destination = Join-Path $folder $profile.ToolName

    try {
        Invoke-LDLCWebDownload -Url $profile.ToolUrl -Destination $destination | Out-Null
        Write-Warn "$($profile.Label) detecte mais la desinstallation silencieuse n'a pas suffi."
        Write-Step "Outil officiel telecharge : $destination"

        if ($profile.Group -eq 'McAfee') {
            Write-Warn "MCPR peut demander une validation manuelle. Le script ne contourne pas le CAPTCHA."
        }

        return $destination
    }
    catch {
        if (-not [string]::IsNullOrWhiteSpace([string]$profile.SupportUrl)) {
            Write-Warn "Impossible de telecharger l'outil officiel $($profile.Label). Ouvre si besoin : $($profile.SupportUrl)"
        }
        else {
            Write-Warn "Impossible de telecharger un outil de secours pour $($profile.Label)."
        }

        return $null
    }
}

function Remove-LDLCProgramSilently {
    param(
        $Target,
        [int]$ProgressPercent
    )

    $program = $Target.Program

    Stop-IfRequested
    Write-ProgressFile $ProgressPercent "Suppression de $($program.DisplayName)..."
    Write-Step "Tentative de desinstallation silencieuse : $($program.DisplayName)"

    $commands = Get-LDLCSilentUninstallCommands -Program $program
    if (-not $commands -or $commands.Count -eq 0) {
        Write-Step "Aucune commande silencieuse exploitable pour $($program.DisplayName)."
        return $false
    }

    $isSecuritySuite = ($Target.Profile.Group -in @('Norton', 'McAfee'))
    $processTimeoutSeconds = if ($isSecuritySuite) { 240 } else { 120 }
    $removalWaitSeconds = if ($isSecuritySuite) { 75 } else { 30 }

    foreach ($command in $commands) {
        Stop-IfRequested

        try {
            Write-Step "Essai : $($command.Description)"
            Start-LDLCSilentProcess -FilePath $command.FilePath -Arguments $command.Arguments -SuccessExitCodes @(0, 1605, 1614, 3010, 1641) -TimeoutSeconds $processTimeoutSeconds -QuietFailure | Out-Null
            Clear-LDLCDetectionCaches

            if (Wait-LDLCCondition -Condition { -not (Test-LDLCProgramStillInstalled -Program $program) } -TimeoutSeconds $removalWaitSeconds -PollMilliseconds 2500 -IgnoreErrors) {
                Write-Ok "Produit supprime : $($program.DisplayName)"
                return $true
            }

            Write-Step "$($program.DisplayName) encore detecte apres la tentative silencieuse."
        }
        catch {
            Write-Step "Tentative silencieuse non concluante pour $($program.DisplayName) : $($_.Exception.Message)"
        }
    }

    Write-Step "$($program.DisplayName) semble toujours present apres les tentatives silencieuses."
    return $false
}

function Remove-LDLCOemAndSecurityTrials {
    param(
        [int]$StartPercent = 20,
        [int]$EndPercent = 24,
        [ValidateSet('All', 'Security', 'Oem')]
        [string]$Mode = 'All',
        [ValidateSet('All', 'McAfee', 'Norton')]
        [string]$SecurityVendor = 'All'
    )

    Stop-IfRequested
    $sectionLabel = switch ($Mode) {
        'Security' { 'DETECTION ET SUPPRESSION MCAFEE / NORTON' }
        'Oem'      { 'SUPPRESSION DES LOGICIELS OEM' }
        default    { 'SUPPRESSION OEM / ANTIVIRUS' }
    }
    $targetLabel = switch ($Mode) {
        'Security' { 'McAfee / Norton' }
        'Oem'      { 'logiciels OEM' }
        default    { 'trialwares OEM et antivirus' }
    }

    Write-Section $sectionLabel
    Write-ProgressFile $StartPercent "Recherche : $targetLabel..."

    $targets = @(Get-LDLCOemRemovalTargets -Mode $Mode | Where-Object {
        $SecurityVendor -eq 'All' -or $_.Profile.Category -ne 'Antivirus' -or $_.Profile.Group -eq $SecurityVendor
    })
    if ($targets.Count -eq 0) {
        Write-Ok "Aucun element cible detecte : $targetLabel."
        Write-ProgressFile $EndPercent "Aucun element detecte : $targetLabel."
        return @{
            Detected = 0
            Removed  = 0
            Pending  = 0
        }
    }

    Write-Step "Elements detectes :"
    foreach ($target in $targets) {
        Write-Host ("   - [{0}] {1}" -f $target.Profile.Category, $target.Program.DisplayName) -ForegroundColor DarkGray
    }

    $removedCount = 0
    $fallbackByGroup = @{}

    for ($index = 0; $index -lt $targets.Count; $index++) {
        Stop-IfRequested

        $target = $targets[$index]
        $progressPercent = if ($targets.Count -gt 1) {
            [int][math]::Round($StartPercent + (($index / ($targets.Count - 1)) * [math]::Max(1, ($EndPercent - $StartPercent - 1))))
        }
        else {
            $StartPercent + 1
        }

        if (Remove-LDLCProgramSilently -Target $target -ProgressPercent $progressPercent) {
            $removedCount++
            continue
        }

        if (-not $fallbackByGroup.ContainsKey($target.Profile.Group)) {
            $fallbackByGroup[$target.Profile.Group] = Save-LDLCOemRemovalFallback -Target $target
        }
    }

    Clear-LDLCDetectionCaches
    $remainingTargets = @(Get-LDLCOemRemovalTargets -Mode $Mode | Where-Object {
        $SecurityVendor -eq 'All' -or $_.Profile.Category -ne 'Antivirus' -or $_.Profile.Group -eq $SecurityVendor
    })

    if ($remainingTargets.Count -gt 0) {
        Write-Warn "Des elements restent presents apres le passage silencieux : $targetLabel."
        foreach ($remainingTarget in $remainingTargets) {
            Write-Host ("   - [{0}] {1}" -f $remainingTarget.Profile.Category, $remainingTarget.Program.DisplayName) -ForegroundColor Yellow
        }
    }
    else {
        Write-Ok "Nettoyage termine : $targetLabel."
    }

    Write-ProgressFile $EndPercent "Traitement termine : $targetLabel."
    return @{
        Detected = $targets.Count
        Removed  = $removedCount
        Pending  = $remainingTargets.Count
    }
}


function Test-LDLCMicrosoftOfficeName {
    param([string]$DisplayName)

    if ([string]::IsNullOrWhiteSpace($DisplayName)) {
        return $false
    }

    if ($DisplayName -match '(?i)LibreOffice|OpenOffice|OnlyOffice') {
        return $false
    }

    return ($DisplayName -match '(?i)office\s*365|office365|microsoft\s*365|office')
}

function Stop-LDLCOfficeProcesses {
    $processNames = @(
        'winword',
        'excel',
        'powerpnt',
        'outlook',
        'onenote',
        'onenotem',
        'msaccess',
        'mspub',
        'visio',
        'winproj',
        'lync',
        'groove'
    )

    try {
        Get-Process -Name $processNames -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
    catch {
    }
}

function Get-LDLCOfficeCulture {
    param($Program)

    foreach ($value in @($Program.DisplayName, $Program.QuietUninstallString, $Program.UninstallString)) {
        $text = [string]$value
        if ([string]::IsNullOrWhiteSpace($text)) {
            continue
        }

        if ($text -match '(?i)culture=([a-z]{2}-[a-z]{2})') {
            return $matches[1].ToLowerInvariant()
        }

        if ($text -match '(?i)\b([a-z]{2}-[a-z]{2})\b') {
            return $matches[1].ToLowerInvariant()
        }
    }

    return 'fr-fr'
}

function Invoke-LDLCOfficeUninstallCommand {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string]$Arguments = '',
        [Parameter(Mandatory = $true)][string]$Label,
        [int]$TimeoutSeconds = 180,
        [int[]]$SuccessExitCodes = @(0, 1605, 1614, 3010, 1641)
    )

    Stop-IfRequested

    $resolvedFilePath = $FilePath
    if (-not (Test-Path -LiteralPath $resolvedFilePath)) {
        try {
            $resolvedFilePath = (Get-Command $FilePath -ErrorAction Stop).Source
        }
        catch {
            throw "Executable introuvable pour $Label : $FilePath"
        }
    }

    Write-Step "$Label : demarrage avec timeout ${TimeoutSeconds}s."
    $tempRoot = if ($env:TEMP) { $env:TEMP } else { Get-LDLCProjectRoot }
    $safeLabel = ($Label -replace '[^a-zA-Z0-9]+', '_').Trim('_')
    $id = [guid]::NewGuid().ToString('N')
    $stdoutPath = Join-Path $tempRoot "LDLC_${safeLabel}_${id}.out.log"
    $stderrPath = Join-Path $tempRoot "LDLC_${safeLabel}_${id}.err.log"
    $outputTail = @()
    $process = $null

    try {
        $process = Start-Process `
            -FilePath $resolvedFilePath `
            -ArgumentList $Arguments `
            -WindowStyle Hidden `
            -RedirectStandardOutput $stdoutPath `
            -RedirectStandardError $stderrPath `
            -PassThru `
            -ErrorAction Stop
    }
    catch {
        $process = Start-Process -FilePath $resolvedFilePath -ArgumentList $Arguments -WindowStyle Hidden -PassThru -ErrorAction Stop
    }

    $timeoutMilliseconds = [math]::Max(1, $TimeoutSeconds) * 1000
    if (-not $process.WaitForExit($timeoutMilliseconds)) {
        Write-Warn "$Label bloque depuis ${TimeoutSeconds}s. Arret force de la tentative."
        try {
            & taskkill.exe /PID $process.Id /T /F | Out-Null
        }
        catch {
            try { $process.Kill() } catch {}
        }

        foreach ($logPath in @($stdoutPath, $stderrPath)) {
            if (Test-Path -LiteralPath $logPath) {
                try {
                    $outputTail += @(Get-Content -LiteralPath $logPath -ErrorAction SilentlyContinue | Select-Object -Last 8)
                }
                catch {}
                Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue
            }
        }

        return [pscustomobject]@{
            Succeeded = $false
            ExitCode  = -1
            TimedOut  = $true
            FilePath   = $resolvedFilePath
            Arguments  = $Arguments
            OutputTail = $outputTail
        }
    }

    $exitCode = [int]$process.ExitCode
    foreach ($logPath in @($stdoutPath, $stderrPath)) {
        if (Test-Path -LiteralPath $logPath) {
            try {
                $outputTail += @(Get-Content -LiteralPath $logPath -ErrorAction SilentlyContinue | Select-Object -Last 8)
            }
            catch {}
        }
    }

    if ($exitCode -in @(3010, 1641)) {
        $script:PendingReboot = $true
        Write-Warn "Un redemarrage sera necessaire suite a la suppression Office."
    }

    foreach ($logPath in @($stdoutPath, $stderrPath)) {
        Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue
    }

    return [pscustomobject]@{
        Succeeded = ($SuccessExitCodes -contains $exitCode)
        ExitCode  = $exitCode
        TimedOut  = $false
        FilePath   = $resolvedFilePath
        Arguments  = $Arguments
        OutputTail = $outputTail
    }
}

function Write-LDLCOfficeCommandOutputTail {
    param(
        $Result,
        [string]$Prefix = 'office'
    )

    if (-not $Result -or -not $Result.OutputTail) {
        return
    }

    $lines = @($Result.OutputTail) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Last 8
    foreach ($line in $lines) {
        Write-Host "   [$Prefix] $line" -ForegroundColor DarkGray
    }
}

function Get-LDLCOfficeClickToRunExecutables {
    $candidatePaths = @(
        (Join-Path $env:ProgramFiles 'Common Files\Microsoft Shared\ClickToRun\OfficeClickToRun.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Common Files\Microsoft Shared\ClickToRun\OfficeClickToRun.exe')
    )

    return @($candidatePaths | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique)
}

function Invoke-LDLCOfficeWingetUninstall {
    param(
        $Program,
        [int]$TimeoutSeconds = 120
    )

    if (-not (Test-WingetAvailable)) {
        Write-Warn "Winget indisponible pour supprimer $($Program.DisplayName)."
        return $false
    }

    $displayName = [string]$Program.DisplayName
    if ([string]::IsNullOrWhiteSpace($displayName)) {
        return $false
    }

    $argumentSets = New-Object System.Collections.Generic.List[object]
    [void]$argumentSets.Add(@(
        'uninstall',
        '-e',
        '--name',
        $displayName,
        '--silent',
        '--disable-interactivity',
        '--accept-source-agreements'
    ))

    $productCode = [string]$Program.PSChildName
    if ($productCode -match '^\{[0-9A-Fa-f-]+\}$') {
        [void]$argumentSets.Add(@(
            'uninstall',
            '--product-code',
            $productCode,
            '--silent',
            '--disable-interactivity',
            '--accept-source-agreements'
        ))
    }

    foreach ($arguments in $argumentSets) {
        Stop-IfRequested

        try {
            $result = Invoke-LDLCInstallerCommand -CommandName 'winget' -ArgumentList ([string[]]$arguments) -Label "Winget uninstall $displayName" -TimeoutSeconds $TimeoutSeconds
            $codeLabel = if ($result.TimedOut) { 'TIMEOUT' } else { [string]$result.ExitCode }
            Write-Step "Code retour Winget uninstall pour $displayName : $codeLabel"
            Write-LDLCInstallerOutputTail -Result $result -Prefix 'winget'

            Clear-LDLCDetectionCaches
            if (-not $result.TimedOut -and (Wait-LDLCCondition -Condition {
                -not (Test-LDLCProgramStillInstalled -Program $Program)
            } -TimeoutSeconds 25 -PollMilliseconds 1500 -IgnoreErrors)) {
                Write-Ok "Produit Office supprime via Winget : $displayName"
                return $true
            }
        }
        catch {
            Write-Warn "Winget uninstall en echec pour $displayName : $($_.Exception.Message)"
        }
    }

    return $false
}

function Invoke-LDLCOfficeClickToRunFallback {
    param(
        [object[]]$Targets,
        [scriptblock]$GetOfficeTargets,
        [int]$ProgressPercent = 90
    )

    if (-not $Targets -or @($Targets).Count -eq 0) {
        Write-Ok "Fallback Office Click-to-Run non necessaire : aucun Office restant."
        return $true
    }

    $clickToRunCandidates = @(Get-LDLCOfficeClickToRunExecutables)

    if ($clickToRunCandidates.Count -eq 0) {
        Write-Step "Office Click-to-Run absent : fallback ignore."
        return $false
    }

    $culture = 'fr-fr'
    foreach ($target in @($Targets)) {
        $culture = Get-LDLCOfficeCulture -Program $target
        if (-not [string]::IsNullOrWhiteSpace($culture)) {
            break
        }
    }

    $fallbackArg = "scenario=install scenariosubtype=ARP sourcetype=None productstoremove=AllProducts culture=$culture displaylevel=False forceappshutdown=True"
    $lastFailure = $null

    foreach ($clickToRunExe in $clickToRunCandidates) {
        Stop-IfRequested
        Write-Step "Fallback Click-to-Run detecte : $clickToRunExe"
        Write-ProgressFile $ProgressPercent "Suppression Office Click-to-Run..."

        try {
            $result = Invoke-LDLCOfficeUninstallCommand -FilePath $clickToRunExe -Arguments $fallbackArg -Label 'Office Click-to-Run fallback' -TimeoutSeconds 180
            $codeLabel = if ($result.TimedOut) { 'TIMEOUT' } else { [string]$result.ExitCode }
            Write-Step "Code retour Click-to-Run fallback : $codeLabel"
            Write-LDLCOfficeCommandOutputTail -Result $result -Prefix 'click-to-run'

            if ($result.TimedOut) {
                $lastFailure = "delai depasse apres 180s"
                Write-Warn "Office Click-to-Run fallback interrompu : $lastFailure."
            }
            elseif (-not $result.Succeeded) {
                $lastFailure = "code retour $($result.ExitCode)"
                Write-Warn "Office Click-to-Run fallback non valide : $lastFailure."
            }
        }
        catch {
            $lastFailure = $_.Exception.Message
            Write-Warn "Fallback Click-to-Run en echec : $lastFailure"
        }

        Clear-LDLCDetectionCaches
        if (Wait-LDLCCondition -Condition {
            (& $GetOfficeTargets).Count -eq 0
        } -TimeoutSeconds 45 -PollMilliseconds 2000 -IgnoreErrors) {
            Write-Ok "Suppression Office Click-to-Run terminee."
            return $true
        }
    }

    if ($lastFailure) {
        Write-Warn "Suppression Office Click-to-Run non confirmee : $lastFailure."
    }
    else {
        Write-Warn "Suppression Office Click-to-Run non confirmee : Office reste detecte apres fallback."
    }

    return $false
}

function Remove-LDLCMicrosoftOffice {
    param(
        [int]$ProgressPercent = 90
    )

    Stop-IfRequested
    Write-Section "SUPPRESSION MICROSOFT OFFICE"
    Write-ProgressFile $ProgressPercent "Recherche de Microsoft Office / Microsoft 365..."

    $getOfficeTargets = {
        @(Get-LDLCInstalledPrograms -Refresh | Where-Object {
            Test-LDLCMicrosoftOfficeName -DisplayName ([string]$_.DisplayName)
        } | Sort-Object DisplayName, PSChildName -Unique)
    }

    $targets = & $getOfficeTargets

    if ($targets.Count -eq 0) {
        Write-Ok "Aucun Microsoft Office ou Microsoft 365 detecte."
        Write-ProgressFile $ProgressPercent "Aucun Microsoft Office detecte."
        return @{ Detected = 0; Removed = 0; Pending = 0 }
    }

    Write-Step "Produits Office detectes :"
    foreach ($target in $targets) {
        Write-Host ("   - {0}" -f $target.DisplayName) -ForegroundColor DarkGray
    }

    $removedCount = 0
    Stop-LDLCOfficeProcesses

    foreach ($target in $targets) {
        Stop-IfRequested
        Write-ProgressFile $ProgressPercent ("Suppression de {0}..." -f $target.DisplayName)
        Write-Step ("Tentative de desinstallation silencieuse : {0}" -f $target.DisplayName)

        $removedThisTarget = $false
        $commands = @(Get-LDLCSilentUninstallCommands -Program $target)
        if (-not $commands -or $commands.Count -eq 0) {
            Write-Warn "Aucune commande silencieuse exploitable pour $($target.DisplayName)."
        }

        foreach ($command in $commands) {
            Stop-IfRequested

            try {
                Write-Step "Essai : $($command.Description)"
                $result = Invoke-LDLCOfficeUninstallCommand -FilePath $command.FilePath -Arguments $command.Arguments -Label $command.Description -TimeoutSeconds 180
                Write-Step "Code retour suppression Office : $($result.ExitCode)"
                Clear-LDLCDetectionCaches

                if ($result.Succeeded -and (Wait-LDLCCondition -Condition {
                    -not (Test-LDLCProgramStillInstalled -Program $target)
                } -TimeoutSeconds 25 -PollMilliseconds 1500 -IgnoreErrors)) {
                    Write-Ok "Produit Office supprime : $($target.DisplayName)"
                    $removedCount++
                    $removedThisTarget = $true
                    break
                }
            }
            catch {
                Write-Warn "Echec tentative silencieuse pour $($target.DisplayName) : $($_.Exception.Message)"
            }
        }

        if (-not $removedThisTarget) {
            Write-Step "Fallback Winget pour $($target.DisplayName)."
            if (Invoke-LDLCOfficeWingetUninstall -Program $target -TimeoutSeconds 120) {
                $removedCount++
                $removedThisTarget = $true
            }
        }

        if (-not $removedThisTarget) {
            Write-Warn "$($target.DisplayName) semble toujours present apres les tentatives standard."
        }
    }

    Clear-LDLCDetectionCaches
    $remainingTargets = & $getOfficeTargets

    if ($remainingTargets.Count -gt 0) {
        if (Invoke-LDLCOfficeClickToRunFallback -Targets $remainingTargets -GetOfficeTargets $getOfficeTargets -ProgressPercent $ProgressPercent) {
            $remainingTargets = @()
        }
    }

    Clear-LDLCDetectionCaches
    $remainingTargets = & $getOfficeTargets

    if ($remainingTargets.Count -gt 0) {
        Write-Warn "Des composants Microsoft Office restent presents :"
        foreach ($remaining in $remainingTargets) {
            Write-Host ("   - {0}" -f $remaining.DisplayName) -ForegroundColor Yellow
        }
    }
    else {
        Write-Ok "Suppression Microsoft Office terminee."
    }

    Write-ProgressFile $ProgressPercent "Traitement Microsoft Office termine."
    return @{ Detected = $targets.Count; Removed = $removedCount; Pending = $remainingTargets.Count }
}

# endregion Module: 50.Cleanup.ps1

# Norton retains its current interactive path. McAfee uses the historical isolated cleanup.
function Get-LDLCSecurityInteractiveCommand {
    param($Program)
    $raw = [Environment]::ExpandEnvironmentVariables([string]$Program.UninstallString).Trim()
    if ($raw -notmatch '^(?:"(?<File>[^"]+\.exe)"|(?<File>.+?\.exe))(?<Args>(?:\s.*)?)$') {
        throw "Commande de desinstallation interactive absente/invalide pour $($Program.DisplayName)."
    }
    $file = $matches.File; $arguments = $matches.Args.Trim()
    $leaf = [IO.Path]::GetFileName($file)
    if ($leaf -ieq 'msiexec.exe') {
        $file = Join-Path $env:SystemRoot 'System32/msiexec.exe'
        $arguments = [regex]::Replace($arguments, '(?i)(^|\s)/I(?=\s|\{)', '$1/X')
        if ($arguments -notmatch '(?i)(^|\s)/X(?=\s|\{)') { throw 'Commande MSI de desinstallation sans produit /X.' }
        if ($arguments -notmatch '(?i)(^|\s)/norestart\b') { $arguments += ' /norestart' }
    }
    # Remove only standalone silent switches; retain the vendor's original uninstall arguments.
    $arguments = [regex]::Replace($arguments, '(?i)(^|\s)/(?:quiet|silent|verysilent|passive|suppressmsgboxes|s|q[nbrf]?[+!-]?)(?=\s|$)', ' ').Trim()
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Desinstallateur introuvable pour $($Program.DisplayName) : $file" }
    return [pscustomobject]@{ FilePath = $file; Arguments = $arguments }
}

function Start-LDLCSecurityInteractiveUninstaller {
    param($Command)
    $launch = @{ FilePath = $Command.FilePath; WindowStyle = 'Normal'; PassThru = $true; ErrorAction = 'Stop' }
    if ($Command.Arguments) { $launch.ArgumentList = $Command.Arguments }
    return Start-Process @launch
}

function Remove-LDLCSecurityTrialsInteractively {
    param([int]$StartPercent = 1, [int]$EndPercent = 3)
    Stop-IfRequested
    Write-Section 'DESINSTALLATION NORTON'
    $targets = @(Get-LDLCOemRemovalTargets | Where-Object { $_.Profile.Group -eq 'Norton' })
    $removed = 0
    foreach ($target in $targets) {
        Stop-IfRequested
        $program = $target.Program
        if (-not (Test-LDLCProgramStillInstalled -Program $program)) { $removed++; continue }
        $command = Get-LDLCSecurityInteractiveCommand -Program $program
        Write-ProgressFile $StartPercent "Desinstallation de $($program.DisplayName) : terminer dans sa fenetre."
        Write-Step "Ouverture du desinstallateur de $($program.DisplayName)."
        $process = Start-LDLCSecurityInteractiveUninstaller -Command $command
        if (-not $process) { throw "Le desinstallateur de $($program.DisplayName) n'a pas demarre." }
        try {
            while ($true) {
                Stop-IfRequested
                Clear-LDLCDetectionCaches
                $stillInstalled = Test-LDLCProgramStillInstalled -Program $program
                $process.Refresh()
                if ($process.HasExited) {
                    $code = $process.ExitCode
                    if (-not $stillInstalled -and $code -in @(0, 1605, 1614, 3010, 1641)) { $removed++; break }
                    if ($code -in @(3010, 1641)) { throw "$($program.DisplayName) demande un redemarrage et reste present. Reprendre apres redemarrage." }
                    if ($code -notin @(0, 1605, 1614)) { throw "Desinstallation de $($program.DisplayName) interrompue/refusee (code $code). Preparation arretee." }
                    # A launcher may exit before its visible child. Wait for removal,
                    # not the launcher's lifetime; Quit remains available via Stop-IfRequested.
                    Write-ProgressFile $StartPercent "$($program.DisplayName) encore present : terminer sa desinstallation ou Quitter."
                }
                Start-Sleep -Milliseconds 500
            }
        } finally { $process.Dispose() }
        Write-Info "Desinstallation terminee : $($program.DisplayName)."
    }
    $remaining = @(Get-LDLCOemRemovalTargets | Where-Object {
        $_.Profile.Group -eq 'Norton' -and (Test-LDLCProgramStillInstalled -Program $_.Program)
    })
    if ($remaining.Count) { throw 'Norton encore detecte apres desinstallation ; preparation arretee avant les installations.' }
    Write-ProgressFile $EndPercent 'Etape Norton terminee.'
    return [pscustomobject]@{ Detected = $targets.Count; Removed = $removed; Pending = 0; Success = $true }
}
# region Module: 60.Gpu.ps1
# GPU detection and driver helpers.

function Start-LDLCSilentProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string]$Arguments = '',
        [int[]]$SuccessExitCodes = @(0, 3010, 1641),
        [int]$TimeoutSeconds = 120,
        [switch]$QuietFailure
    )

    Stop-IfRequested

    $proc = Start-Process -FilePath $FilePath -ArgumentList $Arguments -PassThru -WindowStyle Hidden
    $timeoutMilliseconds = [math]::Max(1, $TimeoutSeconds) * 1000
    if (-not $proc.WaitForExit($timeoutMilliseconds)) {
        $timeoutMessage = "Execution bloquee depuis ${TimeoutSeconds}s ($FilePath). Arret force de la tentative."
        if ($QuietFailure) { Write-Step $timeoutMessage } else { Write-Warn $timeoutMessage }
        try {
            & taskkill.exe /PID $proc.Id /T /F | Out-Null
        }
        catch {
            try { $proc.Kill() } catch {}
        }

        throw "Execution bloquee ou delai depasse ($FilePath)."
    }

    if ($SuccessExitCodes -notcontains $proc.ExitCode) {
        throw "Execution en echec ($FilePath) - code retour $($proc.ExitCode)."
    }

    if ($proc.ExitCode -in @(3010, 1641)) {
        $script:PendingReboot = $true
        Write-Warn "Un redemarrage sera necessaire suite a l'execution de $FilePath."
    }

    return $proc.ExitCode
}

function Test-LDLCNvidiaProfessionalGpuName {
    param([string]$GpuName)

    if ([string]::IsNullOrWhiteSpace($GpuName)) {
        return $false
    }

    $name = $GpuName.Trim()

    $professionalPatterns = @(
        '(?i)\bQuadro\b',
        '(?i)\bNVS\b',
        '(?i)\bTesla\b',
        '(?i)\bRTX\s+PRO\b',
        '(?i)\bRTX\s+A\d{3,4}\b',
        '(?i)\bNVIDIA\s+RTX\s+(500|1000|2000|3000|3500|4000|4500|5000|6000)\b',
        '(?i)\bRTX\s+(500|1000|2000|3000|3500|4000|4500|5000|6000)\s+(Ada|SFF|Generation)\b',
        '(?i)\bNVIDIA\s+A(10|16|30|40|100)\b',
        '(?i)\bNVIDIA\s+L(4|40)\b',
        '(?i)\bNVIDIA\s+H100\b',
        '(?i)\bNVIDIA\s+T(400|600|1000|2000)\b',
        '(?i)\bNVIDIA\s+P(400|600|1000|2000|2200|3200|4000|5000|6000)\b',
        '(?i)\bNVIDIA\s+K(600|1200|2200|4200|5200|6000)\b',
        '(?i)\bNVIDIA\s+M(600|1000M|2000M|2200|4000M|5000M|6000)\b'
    )

    foreach ($pattern in $professionalPatterns) {
        if ($name -match $pattern) {
            return $true
        }
    }

    return $false
}

function ConvertTo-LDLCNvidiaLookupName {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) { return '' }
    return (($Name -replace '(?i)\(R\)|\(TM\)', '' -replace '(?i)^NVIDIA\s+', '' -replace '[^a-zA-Z0-9]+', ' ').Trim().ToLowerInvariant())
}

function Resolve-LDLCNvidiaDriverOfficialSources {
    param([Parameter(Mandatory = $true)]$Context)

    $gpuName = [string]$Context.GpuName
    $pnpDeviceId = [string]$Context.PnpDeviceId
    $professional = [bool]$Context.Professional
    $lookupName = ConvertTo-LDLCNvidiaLookupName -Name $gpuName
    $deviceId = ''
    if ($pnpDeviceId -match '(?i)DEV_([0-9A-F]{4})') {
        $deviceId = $Matches[1]
    }

    $product = $null
    if (-not [string]::IsNullOrWhiteSpace($lookupName) -and $lookupName -notmatch 'microsoft basic display') {
        [xml]$catalog = (Invoke-WebRequest `
            -Uri 'https://www.nvidia.com/Download/API/lookupValueSearch.aspx?TypeID=3' `
            -UseBasicParsing `
            -TimeoutSec 60).Content

        $entries = @($catalog.LookupValueSearch.LookupValues.LookupValue)
        $product = $entries |
            Where-Object { (ConvertTo-LDLCNvidiaLookupName -Name ([string]$_.Name)) -eq $lookupName } |
            Select-Object -First 1

        if (-not $product) {
            $product = $entries |
                Where-Object {
                    $candidate = ConvertTo-LDLCNvidiaLookupName -Name ([string]$_.Name)
                    -not [string]::IsNullOrWhiteSpace($candidate) -and
                    ($lookupName.Contains($candidate) -or $candidate.Contains($lookupName))
                } |
                Sort-Object { ([string]$_.Name).Length } -Descending |
                Select-Object -First 1
        }
    }

    if (-not $product -and [string]::IsNullOrWhiteSpace($deviceId)) {
        throw "GPU NVIDIA absent du catalogue officiel et identifiant DEV indisponible : $gpuName"
    }

    $osId = if ([Environment]::OSVersion.Version.Build -ge 22000) { 135 } else { 57 }
    $profiles = if ($professional) {
        @(
            @{ upCRD = 1; qnf = 1 },
            @{ upCRD = 1; qnf = 0 },
            @{ upCRD = 0; qnf = 1 }
        )
    }
    else {
        @(@{ upCRD = 0; qnf = 0 })
    }

    foreach ($profile in $profiles) {
        $productQuery = if ($product) {
            "&psid=$($product.ParentID)&pfid=$($product.Value)"
        }
        else {
            "&deviceID=$deviceId"
        }

        $uri = 'https://gfwsl.geforce.com/services_toolkit/services/com/nvidia/services/AjaxDriverService.php' +
            '?func=DriverManualLookup' +
            $productQuery +
            "&osID=$osId" +
            '&languageCode=1036&beta=0&isWHQL=1&dltype=-1&dch=1' +
            "&upCRD=$($profile.upCRD)&qnf=$($profile.qnf)" +
            '&sort1=0&numberOfResults=1'

        $response = Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec 60
        $info = $response.IDS[0].downloadInfo
        $downloadUrl = [string]$info.DownloadURL
        if ($response.Success -ne '1' -or [string]::IsNullOrWhiteSpace($downloadUrl)) {
            continue
        }

        $decodedName = [uri]::UnescapeDataString([string]$info.NameLocalized)
        if ($professional -and $decodedName -notmatch '(?i)Studio|RTX|Quadro|Enterprise|Production|ODE') {
            continue
        }
        if (-not $professional -and ($downloadUrl -match '(?i)/tesla/' -or $decodedName -match '(?i)Data Center')) {
            continue
        }

        $source = New-LDLCOfficialInstallerSource -Url $downloadUrl -Provider 'NVIDIA officiel'
        Add-Member -InputObject $source -NotePropertyName Version -NotePropertyValue ([string]$info.Version) -Force
        Write-Step "Pilote NVIDIA officiel resolu : $decodedName $($info.Version) pour $gpuName"
        return @($source)
    }

    throw "Aucun pilote NVIDIA officiel compatible trouve pour $gpuName."
}

function Get-LDLCNvidiaAppInstallerDefinition {
    return @{
        Provider       = 'NVIDIA officiel'
        Resolver       = 'NvidiaApp'
        CachePatterns  = @('NVIDIA_app_v*.exe')
        TrustedHosts   = @('download.nvidia.com')
        SignerPattern  = 'NVIDIA'
        MinBytes       = 50000000
        CacheMinBytes  = 50000000
        ExeArguments   = @('-s')
        TimeoutSeconds = 1200
        DownloadTimeoutSeconds = 900
        ValidationTimeoutSeconds = 300
        PostInstallProcessNames = @('NVIDIAInstaller', 'NVIDIA App', 'NVIDIAApp')
        PostInstallProcessTimeoutSeconds = 300
        PostInstallSettleSeconds = 5
    }
}

function Get-LDLCNvidiaDriverInstallerDefinition {
    param(
        [Parameter(Mandatory = $true)][string]$GpuName,
        [string]$PnpDeviceId = '',
        [switch]$Professional
    )

    $isNotebook = ($GpuName -match '(?i)Laptop|Notebook|\bM\b')
    $patterns = if ($Professional) {
        @('NVIDIA-RTX-Driver-*.exe', '*rtx*win10*win11*64bit*dch*.exe')
    }
    elseif ($isNotebook) {
        @('NVIDIA-Driver-Notebook-*.exe', '*notebook-win10-win11-64bit*international*dch*whql.exe')
    }
    else {
        @('NVIDIA-Driver-Desktop-*.exe', '*desktop-win10-win11-64bit*international*dch*whql.exe')
    }

    return @{
        Provider        = 'NVIDIA officiel'
        Resolver        = 'NvidiaDriver'
        ResolverContext = @{ GpuName = $GpuName; PnpDeviceId = $PnpDeviceId; Professional = [bool]$Professional }
        CachePatterns   = $patterns
        TrustedHosts    = @('download.nvidia.com')
        SignerPattern   = 'NVIDIA'
        MinBytes        = 100000000
        CacheMinBytes   = 100000000
        ExeArguments    = @('-s', '-noreboot')
        TimeoutSeconds  = 2400
        DownloadTimeoutSeconds = 2400
        ValidationTimeoutSeconds = 240
    }
}

function Get-LDLCAmdAdrenalinInstallerDefinition {
    return @{
        Provider       = 'AMD officiel'
        Resolver       = 'AmdAdrenalin'
        CachePatterns  = @('whql-amd-software-adrenalin-edition-*.exe', 'amd-software-adrenalin-edition-*-win*.exe')
        CacheExcludePatterns = @('*minimalsetup*', '*_web.exe')
        TrustedHosts   = @('drivers.amd.com', 'download.amd.com')
        SignerPattern  = 'Advanced Micro Devices|AMD'
        MinBytes       = 10000000
        CacheMinBytes  = 100000000
        CacheDownloaded = $true
        ExeArguments   = @('-install')
        TimeoutSeconds = 2400
        DownloadTimeoutSeconds = 1200
        ValidationTimeoutSeconds = 600
        PostInstallProcessNames = @('AMDSoftwareInstaller', 'AMDInstaller', 'RadeonInstaller', 'AMDSetup', 'Setup')
        PostInstallProcessTimeoutSeconds = 600
        PostInstallSettleSeconds = 8
    }
}

function Get-LDLCGpuHardwareRecords {
    param([Parameter(Mandatory = $true)][string]$ClassName)

    try { return @(Get-CimInstance -ClassName $ClassName -ErrorAction Stop) }
    catch {
        if (Get-Command Get-WmiObject -ErrorAction SilentlyContinue) {
            return @(Get-WmiObject -Class $ClassName -ErrorAction Stop)
        }
        throw
    }
}

function Get-LDLCGpuAdapters {
    $adapters = @()
    try { $adapters = @(Get-LDLCGpuHardwareRecords -ClassName 'Win32_VideoController') } catch {}
    # A GPU without its vendor driver can be absent from Win32_VideoController.
    try {
        $displayDevices = @(Get-LDLCGpuHardwareRecords -ClassName 'Win32_PnPEntity' | Where-Object {
            ($_.PNPClass -eq 'Display' -or $_.ClassGuid -eq '{4d36e968-e325-11ce-bfc1-08002be10318}') -and
            $_.Present -ne $false -and $_.ConfigManagerErrorCode -ne 45
        })
        foreach ($device in $displayDevices) {
            if (-not @($adapters | Where-Object { $_.PNPDeviceID -eq $device.PNPDeviceID }).Count) {
                $adapters += $device
            }
        }
    }
    catch {}
    return @($adapters | Where-Object { $_.Present -ne $false -and $_.ConfigManagerErrorCode -ne 45 })
}

function Get-LDLCGpuAdapterVendor {
    param([Parameter(Mandatory = $true)]$Adapter)

    # The PCI vendor wins over a friendly name, a SUBSYS vendor or the CPU brand.
    if ([string]$Adapter.PNPDeviceID -match '(?i)^PCI\\VEN_([0-9A-F]{4})(?:&|$)') {
        switch ($Matches[1]) {
            '1002' { return 'AMD' }
            '10DE' { return 'NVIDIA' }
            '8086' { return 'Intel' }
            default { return '' }
        }
    }
    $text = @([string]$Adapter.Name, [string]$Adapter.AdapterCompatibility) -join ' '
    if ($text -match '(?i)\bNVIDIA\b') { return 'NVIDIA' }
    if ($text -match '(?i)\bIntel\b|\bIris\b|\bUHD\b') { return 'Intel' }
    if ($text -match '(?i)\bAMD\b|Advanced Micro Devices|\bATI\b|\bRadeon\b') { return 'AMD' }
    return ''
}

function Get-LDLCAmdOfficialInstallerLinks {
    param([Parameter(Mandatory=$true)][string]$Html,[Parameter(Mandatory=$true)][string]$PageUrl)
    $decoded=[Net.WebUtility]::HtmlDecode($Html).Replace('\/','/')
    $links=New-Object 'Collections.Generic.List[string]'
    foreach($m in [regex]::Matches($decoded,'(?i)(?:href|data-href)\s*=\s*["''](?<url>[^"''<>]+)["'']')){[void]$links.Add($m.Groups['url'].Value)}
    foreach($m in [regex]::Matches($decoded,'(?i)https://(?:drivers|download)\.amd\.com/[^"''<>\s]+\.exe(?:\?[^"''<>\s]*)?')){[void]$links.Add($m.Value)}
    foreach($link in @($links | Select-Object -Unique)){
        try{$uri=[uri]::new([uri]$PageUrl,$link)}catch{continue}
        if($uri.Scheme -ne 'https' -or $uri.Host -notin @('drivers.amd.com','download.amd.com') -or $uri.UserInfo -or $uri.Port -ne 443){continue}
        $name=[IO.Path]::GetFileName($uri.AbsolutePath)
        $m=[regex]::Match($name,'(?i)^(?:whql-)?amd-software-adrenalin-edition-(?<v>\d+(?:\.\d+){1,3})-[\w.-]+\.exe$')
        if(-not $m.Success){continue}
        [pscustomobject]@{Url=$uri.AbsoluteUri;FileName=$name;Version=$m.Groups['v'].Value;PageUrl=$PageUrl;IsFullPackage=($name -notmatch '(?i)minimalsetup|_web\.exe$')}
    }
}

function Resolve-LDLCAmdGpuOfficialSource {
    # Auto-Detect is discovery metadata only; it is not proof that a driver updated.
    $pageUrl='https://www.amd.com/en/support/download/drivers.html'
    $response=Invoke-WebRequest -Uri $pageUrl -Headers @{'Cache-Control'='no-cache';Pragma='no-cache'} -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
    $latest=Get-LDLCAmdOfficialInstallerLinks -Html ([string]$response.Content) -PageUrl $pageUrl |
        Where-Object {-not $_.IsFullPackage} | Sort-Object {[version]$_.Version} -Descending | Select-Object -First 1
    if(-not $latest){throw 'Lien Auto-Detect Adrenalin actuel introuvable sur la page AMD officielle.'}
    $latest | Add-Member -NotePropertyName Provider -NotePropertyValue 'AMD officiel (Auto-Detect)' -Force
    return $latest
}

function Resolve-LDLCAmdGpuFullOfficialSources {
    param([Parameter(Mandatory=$true)]$AutoDetectSource)
    # Derive the current official release note, never a pinned driver URL/version.
    $releaseVersion=[version]$AutoDetectSource.Version
    $releaseUrl='https://www.amd.com/en/resources/support-articles/release-notes/RN-RAD-WIN-'+($releaseVersion.ToString() -replace '\.','-')+'.html'
    $response=Invoke-WebRequest -Uri $releaseUrl -Headers @{'Cache-Control'='no-cache';Pragma='no-cache'} -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
    $sources=@(Get-LDLCAmdOfficialInstallerLinks -Html ([string]$response.Content) -PageUrl $releaseUrl | Where-Object {$_.IsFullPackage -and [version]$_.Version -eq $releaseVersion} | Sort-Object Url -Unique)
    if(-not $sources.Count){throw ('Package Adrenalin complet '+$AutoDetectSource.Version+' introuvable dans la note AMD officielle. Aucun ancien package reutilise.')}
    return $sources
}

function Get-LDLCAmdArchiveTool {
    foreach($folder in @($env:ProgramFiles,${env:ProgramFiles(x86)})){
        if(-not $folder){continue}
        $path=Join-Path $folder '7-Zip/7z.exe'
        if(Test-Path -LiteralPath $path -PathType Leaf){return $path}
    }
    $command=Get-Command 7z.exe -ErrorAction SilentlyContinue
    if($command){return $command.Source}
    throw '7-Zip indisponible : impossible de verifier le contenu du package AMD avant installation.'
}

function Expand-LDLCAmdPackageMetadata {
    param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][string]$Destination)
    Stop-IfRequested
    $seven=Get-LDLCAmdArchiveTool
    [void][IO.Directory]::CreateDirectory($Destination)
    $output=@(& $seven x '-y' '-bd' '-r' ('-o'+$Destination) $Path '*.inf' 'RadeonSoftware.exe' 'AMDSoftware.exe' 2>&1)
    if($LASTEXITCODE -ne 0){throw ('Lecture du package AMD impossible (7-Zip '+$LASTEXITCODE+'). Aucun pilote installe.')}
    Stop-IfRequested
    if(-not @(Get-ChildItem -LiteralPath $Destination -Filter '*.inf' -File -Recurse).Count){throw 'Aucun manifeste pilote INF dans le package AMD complet. Installation non lancee.'}
}

function Test-LDLCAmdInfHardwareMatch {
    param([string]$HardwareId,[string]$PnpDeviceId)
    if($HardwareId -notmatch '(?i)^PCI\\VEN_1002&DEV_[0-9A-F]{4}(?:&(?:SUBSYS_[0-9A-F]{8}|REV_[0-9A-F]{2}))*$'){return $false}
    $device=([string]$PnpDeviceId).ToUpperInvariant().Split('\')
    if($device.Count -lt 2 -or $device[0] -ne 'PCI'){return $false}
    $attributes=@($device[1].Split('&'))
    foreach($part in $HardwareId.ToUpperInvariant().Substring(4).Split('&')){if($part -notin $attributes){return $false}}
    return $true
}

function Get-LDLCAmdPackageDriverTargets {
    param([Parameter(Mandatory=$true)][string]$MetadataPath,[Parameter(Mandatory=$true)][string[]]$PnpDeviceIds,[int]$WindowsBuild=[Environment]::OSVersion.Version.Build)
    $targets=@{}
    foreach($inf in @(Get-ChildItem -LiteralPath $MetadataPath -Filter '*.inf' -File -Recurse)){
        $text=[IO.File]::ReadAllText($inf.FullName)
        if($text -notmatch '(?im)^\s*Class\s*=\s*Display\s*(?:;.*)?$'){continue}
        $versionMatch=[regex]::Match($text,'(?im)^\s*DriverVer\s*=\s*[^,\r\n]+,\s*(?<v>\d+\.\d+\.\d+\.\d+)\s*(?:;.*)?$')
        if(-not $versionMatch.Success){continue}
        $version=$versionMatch.Groups['v'].Value
        # Only eligible x64 models sections: x86/ARM and newer Windows builds cannot supply a target.
        $eligible=$false
        foreach($line in ($text -split '\r?\n')){
            $section=[regex]::Match($line,'^\s*\[(?<name>[^]]+)\]')
            if($section.Success){
                $sectionName=$section.Groups['name'].Value
                $eligible=($sectionName -match '(?i)\.NTamd64(?:\.|$)')
                $build=[regex]::Match($sectionName,'(?i)\.NTamd64\.\d+\.\d+\.[^.]*\.[^.]*\.(?<build>\d+)(?:\.|$)')
                if($build.Success -and [int]$build.Groups['build'].Value -gt $WindowsBuild){$eligible=$false}
                continue
            }
            if(-not $eligible){continue}
            # Match a complete hardware ID on a models entry, never a comment or substring.
            foreach($m in [regex]::Matches($line,'(?i)^\s*[^;=]+=[^;]*?,\s*(?<id>PCI\\VEN_1002&DEV_[0-9A-F]{4}(?:&(?:SUBSYS_[0-9A-F]{8}|REV_[0-9A-F]{2}))*)\s*(?:,|;|$)')){
                foreach($id in $PnpDeviceIds){
                    if((Test-LDLCAmdInfHardwareMatch -HardwareId $m.Groups['id'].Value -PnpDeviceId $id) -and
                        (-not $targets.ContainsKey($id) -or [version]$version -gt [version]$targets[$id].DriverVersion)){
                        $targets[$id]=[pscustomobject]@{PnpDeviceId=$id;DriverVersion=$version;InfPath=$inf.FullName;HardwareId=$m.Groups['id'].Value}
                    }
                }
            }
        }
    }
    foreach($id in $PnpDeviceIds){
        if(-not $targets.ContainsKey($id)){throw ('GPU '+$id+' non pris en charge par ce package AMD actuel. Aucun ancien pilote installe en repli.')}
    }
    return @($PnpDeviceIds | ForEach-Object {$targets[$_]})
}

function Test-LDLCAmdDriverTargetsReady {
    param([Parameter(Mandatory=$true)][object[]]$Targets)
    if(-not $Targets.Count){return $false}
    if(-not (Test-LDLCAmdGpuDriversReady -PnpDeviceIds @($Targets | ForEach-Object {$_.PnpDeviceId}))){return $false}
    try{
        $drivers=@(Get-LDLCGpuHardwareRecords -ClassName 'Win32_PnPSignedDriver')
        foreach($target in $Targets){
            $driver=$drivers | Where-Object {$_.DeviceID -eq $target.PnpDeviceId -and $_.DeviceClass -eq 'DISPLAY' -and $_.IsSigned -eq $true} | Select-Object -First 1
            if(-not $driver -or [version]$driver.DriverVersion -lt [version]$target.DriverVersion){return $false}
        }
        return $true
    }catch{return $false}
}

function Test-LDLCAmdSoftwareTargetReady {
    param($Software,[Parameter(Mandatory=$true)][string]$ReleaseVersion,[Parameter(Mandatory=$true)][string]$MetadataPath)
    if(-not $Software -or -not $Software.ExePath){return $false}
    # Compare UI executable versions only to the same executable in the package.
    $name=[IO.Path]::GetFileName([string]$Software.ExePath)
    $uiFiles=@(Get-ChildItem -LiteralPath $MetadataPath -Filter $name -File -Recurse)
    foreach($file in $uiFiles){
        $target=Get-LDLCFileVersionText -Path $file.FullName
        $installed=Get-LDLCFileVersionText -Path $Software.ExePath
        if($target -match '^\d+(?:\.\d+){1,3}$' -and $installed -match '^\d+(?:\.\d+){1,3}$'){
            return ([version]$target -gt [version]'0.0' -and [version]$installed -ge [version]$target)
        }
    }
    # AMD's marketing version and the Windows driver version are different scales.
    # Accept only an unambiguous three-component Adrenalin release, never a 4-part driver build.
    $versions=@([string]$Software.DisplayVersion)
    foreach($key in @('HKLM:\SOFTWARE\AMD\CN','HKLM:\SOFTWARE\WOW6432Node\AMD\CN')){
        try{
            $cn=Get-ItemProperty -LiteralPath $key -ErrorAction Stop
            foreach($property in @('RadeonSoftwareVersion','ReleaseVersion')){if($cn.PSObject.Properties[$property]){$versions += [string]$cn.$property}}
        }catch{}
    }
    foreach($v in $versions){
        if($v -match '^\s*\d{2}\.(?:[1-9]|1[0-2])\.\d{1,2}\s*$' -and [version]$v.Trim() -ge [version]$ReleaseVersion){return $true}
    }
    return $false
}

function Test-LDLCAmdGpuInstallerFile {
    param([Parameter(Mandatory = $true)][string]$Path, [int64]$MinBytes = 10000000)

    $reader = $null
    try {
        if ([System.IO.Path]::GetExtension($Path) -ine '.exe') { return $false }
        $reader = New-Object System.IO.BinaryReader([System.IO.File]::OpenRead($Path))
        if ($reader.BaseStream.Length -lt [math]::Max(64, $MinBytes) -or $reader.ReadUInt16() -ne 0x5A4D) { return $false }
        $reader.BaseStream.Position = 0x3C
        $peOffset = $reader.ReadInt32()
        if ($peOffset -lt 64 -or $peOffset -gt ($reader.BaseStream.Length - 24)) { return $false }
        $reader.BaseStream.Position = $peOffset
        if ($reader.ReadUInt32() -ne 0x00004550) { return $false }
    }
    catch { return $false }
    finally { if ($reader) { $reader.Dispose() } }

    try {
        $signature = Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop
        # Fail closed even when the local trust chain cannot be checked.
        return ($signature.Status -eq 'Valid' -and $signature.SignerCertificate -and
            $signature.SignerCertificate.Subject -match '(?i)(?:^|,\s*)CN="?Advanced Micro Devices(?:,?\s+Inc\.?)?"?(?:,|$)')
    }
    catch { return $false }
}

function Test-LDLCAmdGpuDriversReady {
    param([Parameter(Mandatory = $true)][string[]]$PnpDeviceIds)

    if (-not $PnpDeviceIds.Count -or @($PnpDeviceIds | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count) { return $false }
    try {
        $adapters = @(Get-LDLCGpuAdapters)
        $drivers = @(Get-LDLCGpuHardwareRecords -ClassName 'Win32_PnPSignedDriver')
        foreach ($deviceId in $PnpDeviceIds) {
            $adapter = $adapters | Where-Object { $_.PNPDeviceID -eq $deviceId } | Select-Object -First 1
            if (-not $adapter -or (Get-LDLCGpuAdapterVendor -Adapter $adapter) -ne 'AMD' -or
                $null -eq $adapter.ConfigManagerErrorCode -or $adapter.ConfigManagerErrorCode -ne 0) { return $false }
            $driver = $drivers | Where-Object {
                $_.DeviceID -eq $deviceId -and $_.DeviceClass -eq 'DISPLAY' -and $_.IsSigned -eq $true -and
                $_.DriverProviderName -match '(?i)Advanced Micro Devices|^AMD$|^ATI(?: Technologies)?' -and
                $_.InfName -match '(?i)^oem\d+\.inf$'
            } | Select-Object -First 1
            if (-not $driver -or [string]$driver.DriverVersion -notmatch '^\d+(?:\.\d+){1,3}$' -or
                [version]$driver.DriverVersion -le [version]'0.0') { return $false }
        }
        return $true
    }
    catch { return $false }
}

function Invoke-LDLCAmdGpuInstaller {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)]$Installer)

    Stop-IfRequested
    $before = @(Get-LDLCGpuHardwareRecords -ClassName 'Win32_Process')
    $known = @{}
    $initialIds = @($before | ForEach-Object { [int]$_.ProcessId })
    $started = Get-Date
    $deadline = $started.AddSeconds([int]$Installer.TimeoutSeconds)
    $quietSince = $null
    $process = Start-Process -FilePath $Path -ArgumentList $Installer.ExeArguments -PassThru -WindowStyle Hidden -ErrorAction Stop
    $known[[int]$process.Id] = $true
    $completed = $false
    try {
        do {
            Stop-IfRequested
            $now = Get-Date
            $rows = @(Get-LDLCGpuHardwareRecords -ClassName 'Win32_Process')
            # Follow descendants even after the self-extractor exits. Also catch
            # AMD setup launched via a service, but never an unrelated Setup.exe.
            do {
                $added = $false
                foreach ($row in $rows) {
                    $id = [int]$row.ProcessId
                    if ($known.ContainsKey($id) -or $initialIds -contains $id) { continue }
                    $amdSetup = ([string]$row.Name -match '(?i)^(?:AMDSoftwareInstaller|AMDInstaller|RadeonInstaller|AMDSetup|InstallManagerApp|Setup)\.exe$' -and
                        [string]$row.ExecutablePath -match '(?i)^[A-Z]:\\(?:AMD\\|Program Files(?: \(x86\))?\\AMD\\)')
                    if ($known.ContainsKey([int]$row.ParentProcessId) -or $amdSetup) {
                        $known[$id] = $true
                        $added = $true
                    }
                }
            } while ($added)
            $running = @($rows | Where-Object { $known.ContainsKey([int]$_.ProcessId) })
            if ($process.HasExited -and $running.Count -eq 0) {
                if ($null -eq $quietSince) { $quietSince = $now }
                if (($now - $quietSince).TotalSeconds -ge [int]$Installer.PostInstallSettleSeconds) { break }
            }
            else { $quietSince = $null }
            if ($now -ge $deadline) {
                throw 'Installation AMD encore active ou bloquee au delai limite. Aucun succes declare; ne pas relancer avant sa fin.'
            }
            Start-Sleep -Milliseconds 1000
        } while ($true)
        $completed = $true
        $process.WaitForExit()
        if ($process.ExitCode -notin @(0, 3010, 1641)) { throw "Installation AMD en echec, code $($process.ExitCode)." }
        if ($process.ExitCode -in @(3010, 1641)) { $script:PendingReboot = $true }
        return [int]$process.ExitCode
    }
    catch {
        # A timeout/query failure may leave the installer running. Never start a
        # second installer in that case, even when the root extractor has exited.
        if (-not $completed) { $_.Exception.Data['LDLCAmdInstallerStillActive'] = $true }
        throw
    }
    finally { $process.Dispose() }
}

function Get-LDLCFileVersionText {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return ''
    }

    try {
        $versionInfo = (Get-Item -LiteralPath $Path -ErrorAction Stop).VersionInfo
        foreach ($candidate in @([string]$versionInfo.FileVersion, [string]$versionInfo.ProductVersion)) {
            $match = [regex]::Match($candidate, '\d+(?:\.\d+){1,3}')
            if ($match.Success) {
                return $match.Value
            }
        }
    }
    catch {}

    return ''
}

function Get-LDLCProgramDisplayIconExecutablePath {
    param($Program)

    if (-not $Program) {
        return $null
    }

    $rawValue = [string]$Program.DisplayIcon
    if ([string]::IsNullOrWhiteSpace($rawValue)) {
        return $null
    }

    $candidate = $rawValue.Trim().Trim('"') -replace ',\s*-?\d+\s*$', ''
    if ($candidate -match '(?i)([a-z]:\\[^"'']+?\.exe)') {
        $candidate = $Matches[1]
    }

    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        return $candidate
    }

    return $null
}

function Get-LDLCNvidiaDriverComparableVersion {
    param([string]$DriverVersion)

    $match = [regex]::Match([string]$DriverVersion, '\d+(?:\.\d+){1,3}')
    if (-not $match.Success) {
        return $null
    }

    $parts = $match.Value -split '\.'
    if ($parts.Count -ge 4) {
        $driverBranch = ($parts[$parts.Count - 2] -replace '\D', '')
        $lastPart = ($parts[$parts.Count - 1] -replace '\D', '')
        if ($driverBranch.Length -gt 0 -and $lastPart.Length -gt 1) {
            # Exemple WMI 32.0.16.1047 -> version Game Ready 610.47.
            # Le dernier chiffre du troisieme composant appartient au numero
            # public du pilote; les deux derniers chiffres restent les decimales.
            $publicDigits = $driverBranch.Substring($driverBranch.Length - 1) + $lastPart
            $displayVersion = '{0}.{1}' -f $publicDigits.Substring(0, $publicDigits.Length - 2), $publicDigits.Substring($publicDigits.Length - 2)
            try { return [version]$displayVersion } catch {}
        }
    }

    try { return [version]$match.Value } catch {}
    return $null
}

function Get-LDLCNvidiaSmiDriverVersion {
    $candidatePaths = @(
        (Join-Path $env:WINDIR 'System32\nvidia-smi.exe'),
        'C:\Program Files\NVIDIA Corporation\NVSMI\nvidia-smi.exe'
    ) | Select-Object -Unique

    foreach ($path in $candidatePaths) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            continue
        }

        $process = $null
        try {
            $startInfo = New-Object System.Diagnostics.ProcessStartInfo
            $startInfo.FileName = $path
            $startInfo.Arguments = '--query-gpu=driver_version --format=csv,noheader'
            $startInfo.UseShellExecute = $false
            $startInfo.RedirectStandardOutput = $true
            $startInfo.RedirectStandardError = $true
            $startInfo.CreateNoWindow = $true

            $process = New-Object System.Diagnostics.Process
            $process.StartInfo = $startInfo
            if (-not $process.Start()) {
                continue
            }

            if (-not $process.WaitForExit(5000)) {
                try { $process.Kill() } catch {}
                continue
            }

            $output = $process.StandardOutput.ReadToEnd().Trim()
            $versionMatch = [regex]::Match($output, '\d+(?:\.\d+){1,3}')
            if ($versionMatch.Success) {
                return $versionMatch.Value
            }
        }
        catch {}
        finally {
            if ($process) {
                $process.Dispose()
            }
        }
    }

    return ''
}

function Get-LDLCNvidiaGameReadyDriverVersion {
    param($DriverInfo)

    $smiVersion = Get-LDLCNvidiaSmiDriverVersion
    if (-not [string]::IsNullOrWhiteSpace($smiVersion)) {
        return $smiVersion
    }

    if ($DriverInfo -and -not [string]::IsNullOrWhiteSpace([string]$DriverInfo.DriverVersion)) {
        return [string]$DriverInfo.DriverVersion
    }

    return [string](Get-LDLCDriverVersion -Vendor 'NVIDIA')
}

function Test-LDLCVersionAtLeast {
    param(
        [string]$InstalledVersion,
        [string]$RequiredVersion,
        [switch]$NvidiaDriver
    )

    if ([string]::IsNullOrWhiteSpace($InstalledVersion) -or [string]::IsNullOrWhiteSpace($RequiredVersion)) {
        return $false
    }

    try {
        $installed = if ($NvidiaDriver) { Get-LDLCNvidiaDriverComparableVersion -DriverVersion $InstalledVersion } else { [version]$InstalledVersion }
        $required = [version]$RequiredVersion
        return ($installed -and $installed -ge $required)
    }
    catch {
        return $false
    }
}

function Test-LDLCForceGpuDriverInstall {
    if (Get-Command Get-LDLCBooleanEnvironmentValue -ErrorAction SilentlyContinue) {
        return (Get-LDLCBooleanEnvironmentValue -Name 'LDLC_FORCE_GPU_DRIVER_INSTALL' -Default $false)
    }

    return $false
}

function Get-LDLCNvidiaAppExecutablePath {
    param([string[]]$AdditionalSearchFolders = @())

    $exePaths = @(
        'C:\Program Files\NVIDIA Corporation\NVIDIA App\CEF\NVIDIA App.exe',
        'C:\Program Files\NVIDIA Corporation\NVIDIA App\NVIDIA App.exe',
        'C:\Program Files\NVIDIA Corporation\NVIDIA app\NVIDIA app.exe',
        'C:\Program Files\NVIDIA Corporation\NVIDIA app\NVIDIAApp.exe'
    )

    $searchFolders = @(
        "$env:ProgramFiles\NVIDIA Corporation\NVIDIA App",
        "$env:ProgramFiles\NVIDIA Corporation",
        "${env:ProgramFiles(x86)}\NVIDIA Corporation"
    )

    foreach ($folder in @($AdditionalSearchFolders)) {
        if ([string]::IsNullOrWhiteSpace($folder)) {
            continue
        }

        $normalizedFolder = $folder.Trim('"')
        $searchFolders += @(
            $normalizedFolder,
            (Join-Path $normalizedFolder 'CEF')
        )
        $exePaths += @(
            (Join-Path $normalizedFolder 'NVIDIA App.exe'),
            (Join-Path $normalizedFolder 'NVIDIA app.exe'),
            (Join-Path $normalizedFolder 'NVIDIAApp.exe'),
            (Join-Path $normalizedFolder 'CEF\NVIDIA App.exe'),
            (Join-Path $normalizedFolder 'CEF\NVIDIA app.exe'),
            (Join-Path $normalizedFolder 'CEF\NVIDIAApp.exe')
        )
    }

    if (Get-Command Get-LDLCExistingExePathByNames -ErrorAction SilentlyContinue) {
        return Get-LDLCExistingExePathByNames `
            -ExePaths $exePaths `
            -SearchFolders $searchFolders `
            -ExeNames @('NVIDIA App.exe', 'NVIDIA app.exe', 'NVIDIAApp.exe')
    }

    foreach ($path in $exePaths) {
        if (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path -LiteralPath $path)) {
            return $path
        }
    }

    return $null
}

function Get-LDLCNvidiaAppInstallation {
    param([switch]$Refresh)

    $programs = @()
    if (Get-Command Get-LDLCInstalledPrograms -ErrorAction SilentlyContinue) {
        $programs = @(Get-LDLCInstalledPrograms -Refresh:$Refresh)
    }

    foreach ($program in $programs) {
        $displayName = [string]$program.DisplayName
        $publisher = [string]$program.Publisher

        if ([string]::IsNullOrWhiteSpace($displayName)) {
            continue
        }

        $isNvidiaPublisher = ($publisher -match '(?i)NVIDIA')
        $isNvidiaApp = ($displayName -match '(?i)^NVIDIA\s+App$|NVIDIA\s+App')
        $isDriverComponent = ($displayName -match '(?i)Graphics Driver|Studio Driver|Game Ready|HD Audio|PhysX|FrameView|Control Panel|GeForce Experience')

        if ($isNvidiaApp -and (-not $isDriverComponent) -and ($isNvidiaPublisher -or $displayName -match '(?i)NVIDIA')) {
            $displayIconExe = Get-LDLCProgramDisplayIconExecutablePath -Program $program
            $additionalFolders = @([string]$program.InstallLocation)
            if ($displayIconExe) {
                $additionalFolders += (Split-Path -Parent $displayIconExe)
            }
            $exePath = if ($displayIconExe) { $displayIconExe } else { Get-LDLCNvidiaAppExecutablePath -AdditionalSearchFolders $additionalFolders }
            if (-not $exePath) {
                Write-Step "Entree registre NVIDIA App ignoree : executable principal introuvable pour $displayName."
                continue
            }

            return [pscustomobject]@{
                DisplayName    = $displayName
                DisplayVersion = if ($program.DisplayVersion) { [string]$program.DisplayVersion } else { Get-LDLCFileVersionText -Path $exePath }
                Publisher      = $publisher
                InstallLocation = [string]$program.InstallLocation
                ExePath        = $exePath
                DetectedBy     = 'Registry+Executable'
                RegistryPresent = $true
                ExecutablePresent = $true
            }
        }
    }

    $exePath = Get-LDLCNvidiaAppExecutablePath
    if ($exePath) {
        return [pscustomobject]@{
            DisplayName     = 'NVIDIA App'
            DisplayVersion  = Get-LDLCFileVersionText -Path $exePath
            Publisher       = 'NVIDIA'
            InstallLocation = Split-Path $exePath -Parent
            ExePath         = $exePath
            DetectedBy      = 'Executable'
            RegistryPresent = $false
            ExecutablePresent = $true
        }
    }

    return $null
}

function Get-LDLCNvidiaAppLatestSource {
    $definition = Get-LDLCNvidiaAppInstallerDefinition
    $sources = @(Get-LDLCOfficialInstallerSources -Installer $definition)
    if ($sources.Count -eq 0) {
        return $null
    }

    return $sources | Select-Object -First 1
}

function Install-LDLCNvidiaAppIfNeeded {
    param([int]$ProgressPercent = 86)

    $nvidiaApp = Get-LDLCNvidiaAppInstallation -Refresh
    $latestSource = $null
    $targetVersion = ''
    try {
        $latestSource = Get-LDLCNvidiaAppLatestSource
        if ($latestSource) {
            $targetVersion = [string]$latestSource.Version
            if ([string]::IsNullOrWhiteSpace($targetVersion) -and [string]$latestSource.FileName -match '(?i)NVIDIA_app_v([0-9]+(?:\.[0-9]+){1,3})\.exe') {
                $targetVersion = $Matches[1]
            }
        }
    }
    catch {
        Write-Info "Verification de version NVIDIA App indisponible : $($_.Exception.Message)"
    }

    $mustInstall = (-not $nvidiaApp)
    if ($nvidiaApp) {
        $source = if ($nvidiaApp.ExePath) { $nvidiaApp.ExePath } else { $nvidiaApp.DetectedBy }
        $installedVersion = [string]$nvidiaApp.DisplayVersion
        if (-not [string]::IsNullOrWhiteSpace($targetVersion)) {
            if (Test-LDLCVersionAtLeast -InstalledVersion $installedVersion -RequiredVersion $targetVersion) {
                Write-Ok "NVIDIA App confirmee a jour (version $installedVersion, cible officielle $targetVersion)."
                Write-ProgressFile $ProgressPercent 'NVIDIA App deja a jour.'
                Ensure-LDLCGpuDesktopShortcut -Vendor 'NVIDIA'
                return $true
            }

            $mustInstall = $true
            $versionText = if ($installedVersion) { $installedVersion } else { 'inconnue' }
            Write-Step "NVIDIA App detectee ($source, version $versionText) : mise a jour vers la version officielle $targetVersion."
        }
        else {
            Write-Warn "NVIDIA App confirmee ($source), mais la version officielle est indisponible : mise a jour non forcee."
            Write-ProgressFile $ProgressPercent 'NVIDIA App presente, verification de version indisponible.'
            Ensure-LDLCGpuDesktopShortcut -Vendor 'NVIDIA'
            return $true
        }
    }

    if (-not $mustInstall) {
        return $true
    }

    if (-not $nvidiaApp) {
        Write-Step "NVIDIA App absente : installation de l'application NVIDIA."
    }
    Write-ProgressFile $ProgressPercent 'Installation ou mise a jour de NVIDIA App...'

    $definition = Get-LDLCNvidiaAppInstallerDefinition
    if ($latestSource -and -not [string]::IsNullOrWhiteSpace([string]$latestSource.Url)) {
        $definition.Resolver = ''
        $definition.Urls = @([string]$latestSource.Url)
    }

    $validation = {
        $candidate = Get-LDLCNvidiaAppInstallation -Refresh
        if (-not $candidate) {
            return $false
        }

        if (-not [string]::IsNullOrWhiteSpace($targetVersion) -and -not [string]::IsNullOrWhiteSpace([string]$candidate.DisplayVersion)) {
            return (Test-LDLCVersionAtLeast -InstalledVersion ([string]$candidate.DisplayVersion) -RequiredVersion $targetVersion)
        }

        return $true
    }.GetNewClosure()
    $result = Invoke-LDLCOfficialInstaller `
        -Installer $definition `
        -Label 'NVIDIA App' `
        -ValidationScript $validation

    if (Get-Command Clear-LDLCDetectionCaches -ErrorAction SilentlyContinue) {
        Clear-LDLCDetectionCaches
    }

    $verifiedApp = Get-LDLCNvidiaAppInstallation -Refresh
    if ($verifiedApp) {
        $source = if ($verifiedApp.ExePath) { $verifiedApp.ExePath } else { $verifiedApp.DetectedBy }
        $verifiedVersion = [string]$verifiedApp.DisplayVersion
        if (-not [string]::IsNullOrWhiteSpace($targetVersion) -and -not [string]::IsNullOrWhiteSpace($verifiedVersion) -and
            -not (Test-LDLCVersionAtLeast -InstalledVersion $verifiedVersion -RequiredVersion $targetVersion)) {
            Write-Err "NVIDIA App presente mais version insuffisante apres mise a jour. Installee=$verifiedVersion; attendue=$targetVersion."
            Ensure-LDLCGpuDesktopShortcut -Vendor 'NVIDIA'
            return $false
        }

        if (-not [string]::IsNullOrWhiteSpace($targetVersion) -and [string]::IsNullOrWhiteSpace($verifiedVersion)) {
            Write-Warn "NVIDIA App confirmee apres installation ($source), mais sa version est illisible : la derniere version ne peut pas etre confirmee."
        }
        else {
            $versionSuffix = if ($verifiedVersion) { ", version $verifiedVersion" } else { ', version non lisible' }
            Write-Ok "NVIDIA App confirmee apres installation ($source$versionSuffix, methode $($result.Method))."
        }
        Ensure-LDLCGpuDesktopShortcut -Vendor 'NVIDIA'
        return $true
    }

    $reason = if ($result) { [string]$result.Reason } else { 'resultat installateur absent' }
    Write-Err "NVIDIA App non confirmee apres installation officielle. Cause : $reason"
    Ensure-LDLCGpuDesktopShortcut -Vendor 'NVIDIA'
    return $false
}

function Get-LDLCAmdSoftwareExecutablePath {
    param(
        [string[]]$AdditionalSearchFolders = @(),
        [string[]]$AdditionalExePaths = @()
    )

    $exePaths = @(
        'C:\Program Files\AMD\CNext\CNext\RadeonSoftware.exe',
        'C:\Program Files\AMD\CNext\CNext\AMDSoftware.exe',
        'C:\Program Files\AMD\CNext\CNext\RadeonSoftware\RadeonSoftware.exe',
        'C:\Program Files\AMD\CNext\CNext\RadeonSoftware\AMDSoftware.exe',
        'C:\Program Files\AMD\CNext\CNext\AMDSoftware\AMDSoftware.exe',
        'C:\Program Files (x86)\AMD\CNext\CNext\RadeonSoftware.exe',
        'C:\Program Files (x86)\AMD\CNext\CNext\AMDSoftware.exe',
        'C:\Program Files (x86)\AMD\CNext\CNext\RadeonSoftware\RadeonSoftware.exe',
        'C:\Program Files (x86)\AMD\CNext\CNext\AMDSoftware\AMDSoftware.exe'
    )

    $searchFolders = @(
        "$env:ProgramFiles\AMD\CNext\CNext",
        "$env:ProgramFiles\AMD",
        "${env:ProgramFiles(x86)}\AMD\CNext\CNext",
        "${env:ProgramFiles(x86)}\AMD"
    )

    $exePaths += @($AdditionalExePaths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    foreach ($folder in @($AdditionalSearchFolders)) {
        if ([string]::IsNullOrWhiteSpace($folder)) {
            continue
        }

        $normalizedFolder = $folder.Trim('"')
        $searchFolders += @(
            $normalizedFolder,
            (Join-Path $normalizedFolder 'CNext'),
            (Join-Path $normalizedFolder 'CNext\CNext')
        )
        $exePaths += @(
            (Join-Path $normalizedFolder 'RadeonSoftware.exe'),
            (Join-Path $normalizedFolder 'AMDSoftware.exe'),
            (Join-Path $normalizedFolder 'CNext\RadeonSoftware.exe'),
            (Join-Path $normalizedFolder 'CNext\AMDSoftware.exe'),
            (Join-Path $normalizedFolder 'CNext\CNext\RadeonSoftware.exe'),
            (Join-Path $normalizedFolder 'CNext\CNext\AMDSoftware.exe'),
            (Join-Path $normalizedFolder 'CNext\CNext\RadeonSoftware\RadeonSoftware.exe'),
            (Join-Path $normalizedFolder 'CNext\CNext\RadeonSoftware\AMDSoftware.exe'),
            (Join-Path $normalizedFolder 'CNext\CNext\AMDSoftware\AMDSoftware.exe')
        )
    }

    if (Get-Command Get-LDLCExistingExePathByNames -ErrorAction SilentlyContinue) {
        return Get-LDLCExistingExePathByNames `
            -ExePaths $exePaths `
            -SearchFolders $searchFolders `
            -ExeNames @('RadeonSoftware.exe', 'AMDSoftware.exe')
    }

    foreach ($path in $exePaths) {
        if (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path -LiteralPath $path)) {
            return $path
        }
    }

    return $null
}

function Get-LDLCAmdSoftwareInstallation {
    param([switch]$Refresh)

    $programs = @()
    if (Get-Command Get-LDLCInstalledPrograms -ErrorAction SilentlyContinue) {
        $programs = @(Get-LDLCInstalledPrograms -Refresh:$Refresh)
    }

    $hasProEdition = $false
    foreach ($program in $programs) {
        $displayName = [string]$program.DisplayName
        $publisher = [string]$program.Publisher

        if ([string]::IsNullOrWhiteSpace($displayName)) {
            continue
        }

        $isAmdPublisher = ($publisher -match '(?i)Advanced Micro Devices|^AMD$')
        $isAmdSoftware = ($displayName -match '(?i)Adrenalin|Radeon Software|AMD Software:\s*Adrenalin|^AMD Software$')
        $isAmdNonAdrenalin = ($displayName -match '(?i)PRO Edition|Radeon Pro|Enterprise')
        if ($isAmdNonAdrenalin -and ($isAmdPublisher -or $displayName -match '(?i)AMD|Radeon')) { $hasProEdition = $true }
        $isDriverOnly = ($displayName -match '(?i)Chipset|Audio|Bluetooth|Ryzen Master|Software Installer')

        if ($isAmdSoftware -and (-not $isAmdNonAdrenalin) -and (-not $isDriverOnly) -and ($isAmdPublisher -or $displayName -match '(?i)AMD|Radeon')) {
            $displayIconExe = Get-LDLCProgramDisplayIconExecutablePath -Program $program
            $additionalFolders = @([string]$program.InstallLocation)
            if ($displayIconExe) {
                $additionalFolders += (Split-Path -Parent $displayIconExe)
            }
            $exePath = Get-LDLCAmdSoftwareExecutablePath `
                -AdditionalSearchFolders $additionalFolders `
                -AdditionalExePaths @($displayIconExe)
            if (-not $exePath) {
                Write-Step "Entree registre AMD Software ignoree : executable principal introuvable pour $displayName."
                continue
            }

            $shortcutPath = $null
            try {
                if (Get-Command Get-StartMenuShortcutPath -ErrorAction SilentlyContinue) {
                    $shortcutPath = Get-StartMenuShortcutPath -Names @('AMD Software', 'AMD Software: Adrenalin Edition', 'Radeon Software')
                }
            }
            catch {}

            return [pscustomobject]@{
                DisplayName     = $displayName
                DisplayVersion  = if ($program.DisplayVersion) { [string]$program.DisplayVersion } else { Get-LDLCFileVersionText -Path $exePath }
                Publisher       = $publisher
                InstallLocation = [string]$program.InstallLocation
                ExePath         = $exePath
                DetectedBy      = 'Registry+Executable'
                RegistryPresent = $true
                ExecutablePresent = $true
                ShortcutPath    = $shortcutPath
            }
        }
    }

    # PRO peut utiliser les memes noms d'executables : sa presence seule ne prouve pas Adrenalin.
    if ($hasProEdition) { return $null }

    $exePath = Get-LDLCAmdSoftwareExecutablePath
    if ($exePath) {
        $shortcutPath = $null
        try {
            if (Get-Command Get-StartMenuShortcutPath -ErrorAction SilentlyContinue) {
                $shortcutPath = Get-StartMenuShortcutPath -Names @('AMD Software', 'AMD Software: Adrenalin Edition', 'Radeon Software')
            }
        }
        catch {}

        return [pscustomobject]@{
            DisplayName     = 'AMD Software: Adrenalin Edition'
            DisplayVersion  = Get-LDLCFileVersionText -Path $exePath
            Publisher       = 'Advanced Micro Devices, Inc.'
            InstallLocation = (Split-Path $exePath -Parent)
            ExePath         = $exePath
            DetectedBy      = 'Executable'
            RegistryPresent = $false
            ExecutablePresent = $true
            ShortcutPath    = $shortcutPath
        }
    }

    return $null
}

function Skip-LDLCGpuDriverInstallIfReady {
    param(
        [Parameter(Mandatory = $true)][string]$Vendor,
        [Parameter(Mandatory = $true)][string]$Label,
        [int]$ProgressPercent = 86
    )

    if (Test-LDLCForceGpuDriverInstall) {
        Write-Step "Installation $Label forcee par LDLC_FORCE_GPU_DRIVER_INSTALL."
        return $false
    }

    if (-not (Get-Command Get-LDLCInstalledVendorDisplayDriver -ErrorAction SilentlyContinue)) {
        return $false
    }

    $installedDriver = Get-LDLCInstalledVendorDisplayDriver -Vendor $Vendor
    if (-not $installedDriver) {
        return $false
    }

    $driverVersion = [string]$installedDriver.DriverVersion
    if ([string]::IsNullOrWhiteSpace($driverVersion)) {
        $driverVersion = 'version inconnue'
    }

    Write-Ok "$Label deja present ($driverVersion). Installation longue ignoree."
    Write-ProgressFile $ProgressPercent "$Label deja present, installation ignoree."
    Ensure-LDLCGpuDesktopShortcut -Vendor $Vendor
    return $true
}

function Install-LDLCNvidiaDriverOfficial {
    param(
        [Parameter(Mandatory = $true)][string]$GpuName,
        [string]$PnpDeviceId = '',
        [switch]$Professional,
        [int]$ProgressPercent = 86,
        [string]$TargetVersion = '',
        [object[]]$OfficialSources = @(),
        [switch]$QuietFailure
    )

    $label = if ($Professional) { 'pilote NVIDIA Studio/RTX' } else { 'pilote NVIDIA Game Ready' }
    Write-ProgressFile $ProgressPercent "Installation du $label via NVIDIA officiel..."
    $definition = Get-LDLCNvidiaDriverInstallerDefinition -GpuName $GpuName -PnpDeviceId $PnpDeviceId -Professional:$Professional
    if (@($OfficialSources).Count -gt 0) {
        $definition.Resolver = ''
        $definition.Urls = @($OfficialSources | ForEach-Object { [string]$_.Url } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ([string]::IsNullOrWhiteSpace($TargetVersion)) {
            $firstOfficialSource = @($OfficialSources | Select-Object -First 1)[0]
            $TargetVersion = [string]$firstOfficialSource.Version
        }
    }

    $validation = {
        $candidate = Get-LDLCInstalledVendorDisplayDriver -Vendor 'NVIDIA'
        if (-not $candidate) {
            return $false
        }

        if (-not [string]::IsNullOrWhiteSpace($TargetVersion)) {
            $candidateVersion = Get-LDLCNvidiaGameReadyDriverVersion -DriverInfo $candidate
            return (Test-LDLCVersionAtLeast -InstalledVersion $candidateVersion -RequiredVersion $TargetVersion -NvidiaDriver)
        }

        return $true
    }.GetNewClosure()
    $result = Invoke-LDLCOfficialInstaller `
        -Installer $definition `
        -Label $label `
        -ValidationScript $validation

    $driver = Get-LDLCInstalledVendorDisplayDriver -Vendor 'NVIDIA'
    $installedDriverVersion = Get-LDLCNvidiaGameReadyDriverVersion -DriverInfo $driver
    if ($result.Success -and $driver -and
        ([string]::IsNullOrWhiteSpace($TargetVersion) -or (Test-LDLCVersionAtLeast -InstalledVersion $installedDriverVersion -RequiredVersion $TargetVersion -NvidiaDriver))) {
        Write-Ok "$label confirme apres installation officielle (version $installedDriverVersion, methode $($result.Method))."
        return $true
    }

    $reason = if ($result) { [string]$result.Reason } else { 'resultat installateur absent' }
    $message = "$label non confirme apres installation officielle. GPU=$GpuName; PNP=$PnpDeviceId; cible=$TargetVersion; cause=$reason"
    if ($QuietFailure) { Write-Info $message } else { Write-Err $message }
    return $false
}

function Invoke-LDLCNvidiaGameReadyChocolateyFallback {
    param(
        [string]$TargetVersion = '',
        [string]$PreviousDriverVersion = ''
    )

    $choco = Get-Command choco -ErrorAction SilentlyContinue
    if (-not $choco) {
        Write-Info 'Fallback NVIDIA Chocolatey indisponible : choco non installe.'
        return $false
    }

    if (-not (Get-Command Invoke-LDLCInstallerCommand -ErrorAction SilentlyContinue)) {
        Write-Info 'Fallback NVIDIA Chocolatey indisponible : moteur installateur absent.'
        return $false
    }

    Write-Step 'Pilote NVIDIA Game Ready : fallback Chocolatey vers la derniere version disponible.'
    try {
        $result = Invoke-LDLCInstallerCommand `
            -CommandName 'choco' `
            -ArgumentList @('upgrade', 'geforce-game-ready-driver', '-y', '--no-progress', '--limit-output', '--execution-timeout=2400') `
            -Label 'Chocolatey NVIDIA Game Ready' `
            -TimeoutSeconds 2700
        $codeLabel = if ($result.TimedOut) { 'TIMEOUT' } else { [string]$result.ExitCode }
        Write-Step "NVIDIA Game Ready Chocolatey : code retour $codeLabel."
        if ($result.TimedOut -or $result.ExitCode -notin @(0, 3010, 1641)) {
            Write-Info "Fallback NVIDIA Chocolatey en echec : code $codeLabel."
            return $false
        }
        if ($result.ExitCode -in @(3010, 1641)) {
            $script:PendingReboot = $true
            Write-Warn 'NVIDIA : redemarrage requis apres la mise a jour.'
        }
        if ([string]::IsNullOrWhiteSpace($TargetVersion)) {
            Write-Info 'Fallback NVIDIA : derniere version non verifiable, cible officielle indisponible.'
            return $false
        }

        if (Get-Command Clear-LDLCDetectionCaches -ErrorAction SilentlyContinue) {
            Clear-LDLCDetectionCaches
        }

        $driver = Get-LDLCInstalledVendorDisplayDriver -Vendor 'NVIDIA'
        if (-not $driver) {
            Write-Info 'Fallback NVIDIA Chocolatey termine sans pilote NVIDIA verifiable.'
            return $false
        }

        $installedVersion = Get-LDLCNvidiaGameReadyDriverVersion -DriverInfo $driver
        if (-not [string]::IsNullOrWhiteSpace($TargetVersion) -and
            -not (Test-LDLCVersionAtLeast -InstalledVersion $installedVersion -RequiredVersion $TargetVersion -NvidiaDriver)) {
            Write-Info "Fallback NVIDIA Chocolatey non valide : version $installedVersion inferieure a la cible $TargetVersion."
            return $false
        }

        if ([string]::IsNullOrWhiteSpace($TargetVersion) -and -not [string]::IsNullOrWhiteSpace($PreviousDriverVersion) -and
            -not (Test-LDLCVersionAtLeast -InstalledVersion $installedVersion -RequiredVersion $PreviousDriverVersion -NvidiaDriver)) {
            Write-Info "Fallback NVIDIA Chocolatey non valide : version pilote non amelioree ($installedVersion)."
            return $false
        }

        Write-Ok "Pilote NVIDIA Game Ready confirme apres fallback Chocolatey (version $installedVersion)."
        return $true
    }
    catch {
        if (Test-LDLCStopRequestError $_) { throw }
        Write-Info "Fallback NVIDIA Chocolatey en echec : $($_.Exception.Message)"
        return $false
    }
}

function Install-LDLCNvidiaStack {
    param(
        [int]$StartPercent = 84,
        [string]$GpuName = '',
        [string]$PnpDeviceId = '',
        [switch]$Professional
    )

    $driverLabel = if ($Professional) { 'pilote NVIDIA Studio' } else { 'pilote NVIDIA Game Ready' }

    Write-Step "GPU detecte : $(if ($Professional) { 'NVIDIA Pro' } else { 'NVIDIA' })"
    Write-ProgressFile $StartPercent "Installation du $driverLabel"

    if ($GpuName) {
        Write-ProgressFile ($StartPercent + 1) "Carte graphique detectee : $GpuName"
        Write-Step "Carte graphique : $GpuName"
    }

    $currentDriverInfo = $null
    if (Get-Command Get-LDLCInstalledVendorDisplayDriver -ErrorAction SilentlyContinue) {
        $currentDriverInfo = Get-LDLCInstalledVendorDisplayDriver -Vendor 'NVIDIA'
    }

    $currentDriver = Get-LDLCNvidiaGameReadyDriverVersion -DriverInfo $currentDriverInfo
    if ($currentDriver) {
        Write-Ok "Version pilote NVIDIA detectee avant installation : $currentDriver"
    }

    $officialSources = @()
    $targetDriverVersion = ''
    try {
        $driverContext = @{ GpuName = $GpuName; PnpDeviceId = $PnpDeviceId; Professional = [bool]$Professional }
        $officialSources = @(Resolve-LDLCNvidiaDriverOfficialSources -Context $driverContext)
        if ($officialSources.Count -gt 0) {
            $targetDriverVersion = [string]$officialSources[0].Version
            Write-Step "$driverLabel officiel disponible : version $targetDriverVersion."
        }
    }
    catch {
        Write-Warn "Verification de la derniere version $driverLabel indisponible : $($_.Exception.Message)"
    }

    $installDriver = Test-LDLCForceGpuDriverInstall
    if (-not $installDriver -and -not $currentDriverInfo) {
        $installDriver = $true
        Write-Step "$driverLabel absent : installation requise."
    }
    elseif (-not $installDriver -and $currentDriverInfo -and -not [string]::IsNullOrWhiteSpace($targetDriverVersion)) {
        if (Test-LDLCVersionAtLeast -InstalledVersion $currentDriver -RequiredVersion $targetDriverVersion -NvidiaDriver) {
            Write-Ok "$driverLabel deja a jour (installe=$currentDriver, cible=$targetDriverVersion)."
        }
        else {
            $installDriver = $true
            Write-Step "$driverLabel a mettre a jour (installe=$currentDriver, cible=$targetDriverVersion)."
        }
    }
    elseif (-not $installDriver -and $currentDriverInfo) {
        Write-Info "$driverLabel present ($currentDriver), mais la version officielle n'a pas pu etre determinee. Mise a jour non forcee."
    }

    if ($installDriver) {
        $driverInstalled = Install-LDLCNvidiaDriverOfficial `
            -GpuName $GpuName `
            -PnpDeviceId $PnpDeviceId `
            -Professional:$Professional `
            -ProgressPercent ($StartPercent + 2) `
            -TargetVersion $targetDriverVersion `
            -OfficialSources $officialSources `
            -QuietFailure

        if (-not $driverInstalled -and -not $Professional) {
            $driverInstalled = Invoke-LDLCNvidiaGameReadyChocolateyFallback `
                -TargetVersion $targetDriverVersion `
                -PreviousDriverVersion $currentDriver
        }

        if (-not $driverInstalled) {
            $targetLabel = if ($targetDriverVersion) { "; cible=$targetDriverVersion" } else { '' }
            Write-Err "$driverLabel non confirme apres les methodes NVIDIA officiel et fallback$targetLabel."
        }
    }

    if (Get-Command Clear-LDLCDetectionCaches -ErrorAction SilentlyContinue) {
        Clear-LDLCDetectionCaches
    }

    [void](Install-LDLCNvidiaAppIfNeeded -ProgressPercent ($StartPercent + 3))
    Ensure-LDLCGpuDesktopShortcut -Vendor 'NVIDIA'
}

function Get-LDLCGpuComputerFormFactor {
    # SMBIOS identity, not a GPU name or a battery/UPS, decides laptop exclusion.
    $computers = @(); $enclosures = @()
    foreach ($className in @('Win32_ComputerSystem', 'Win32_SystemEnclosure')) {
        $records = @()
        try { $records = @(Get-CimInstance -ClassName $className -OperationTimeoutSec 5 -ErrorAction Stop) }
        catch {
            try { $records = @(Get-WmiObject -Class $className -ErrorAction Stop) }
            catch { $records = @() }
        }
        if ($className -eq 'Win32_ComputerSystem') { $computers = $records } else { $enclosures = $records }
    }
    $types = @($computers | ForEach-Object { $_.PCSystemType })
    $chassis = @($enclosures | ForEach-Object { $_.ChassisTypes })
    if (2 -in $types -or @($chassis | Where-Object { $_ -in @(8,9,10,11,14,30,31,32) }).Count -gt 0) {
        return [pscustomobject]@{ Portable = $true; Known = $true; Reason = 'PC portable/tablette identifie par Windows (SMBIOS).' }
    }
    if (@($types | Where-Object { $_ -in @(1,3) }).Count -gt 0 -or @($chassis | Where-Object { $_ -in @(3,4,5,6,7,13,15,16,17,23) }).Count -gt 0) {
        return [pscustomobject]@{ Portable = $false; Known = $true; Reason = 'PC fixe identifie par Windows (SMBIOS).' }
    }
    return [pscustomobject]@{ Portable = $false; Known = $false; Reason = 'Format du PC non confirme par Windows ; installation AMD automatique ignoree par precaution.' }
}


function Wait-LDLCAmdTargetVersions {
    param([string]$ReleaseVersion,[string]$MetadataPath,[object[]]$Targets,[int]$TimeoutSeconds)
    $deadline=(Get-Date).AddSeconds($TimeoutSeconds)
    do {
        Stop-IfRequested
        if(Get-Command Clear-LDLCDetectionCaches -ErrorAction SilentlyContinue){Clear-LDLCDetectionCaches}
        $software=Get-LDLCAmdSoftwareInstallation -Refresh
        if((Test-LDLCAmdSoftwareTargetReady -Software $software -ReleaseVersion $ReleaseVersion -MetadataPath $MetadataPath) -and
            (Test-LDLCAmdDriverTargetsReady -Targets $Targets)){return $true}
        if((Get-Date) -ge $deadline){return $false}
        Start-Sleep -Seconds 2
    }while($true)
}

function Assert-LDLCAmdNoDowngrade {
    param([string]$ReleaseVersion,[object[]]$Targets,$Software)
    $drivers=@(Get-LDLCGpuHardwareRecords -ClassName 'Win32_PnPSignedDriver')
    foreach($target in $Targets){
        $installed=$drivers | Where-Object {$_.DeviceID -eq $target.PnpDeviceId -and $_.DeviceClass -eq 'DISPLAY'} | Select-Object -First 1
        if($installed -and [string]$installed.DriverVersion -match '^\d+(?:\.\d+){1,3}$' -and [version]$installed.DriverVersion -gt [version]$target.DriverVersion){
            throw ('Pilote AMD '+$installed.DriverVersion+' deja plus recent que le package officiel '+$target.DriverVersion+'. Aucun retour a une ancienne version ; application a verifier manuellement.')
        }
    }
    if($Software -and [string]$Software.DisplayVersion -match '^\s*\d{2}\.(?:[1-9]|1[0-2])\.\d{1,2}\s*$' -and [version]$Software.DisplayVersion.Trim() -gt [version]$ReleaseVersion){
        throw ('Adrenalin '+$Software.DisplayVersion+' deja plus recent que le package '+$ReleaseVersion+'. Aucun retour a une ancienne version ; pilote a verifier manuellement.')
    }
}

function Get-LDLCAmdChocolateyPackageMetadata {
    param([string]$PackagePath)
    # Read metadata only: never evaluate the downloaded PowerShell script.
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip=[IO.Compression.ZipFile]::OpenRead($PackagePath)
    try {
        $scripts=@($zip.Entries | Where-Object {$_.FullName -match '(?i)^tools/chocolateyinstall\.ps1$'})
        if($scripts.Count -ne 1 -or $scripts[0].Length -gt 131072){throw 'Script du package Chocolatey AMD absent ou ambigu.'}
        $reader=New-Object IO.StreamReader($scripts[0].Open())
        try{$content=$reader.ReadToEnd()}finally{$reader.Dispose()}
        $values=@{}
        foreach($key in @('url64','checksum64','checksumType64','silentArgs')){
            $matches=[regex]::Matches($content,('(?im)^\s*'+$key+'\s*=\s*["''](?<v>[^"'']+)["'']\s*(?:#.*)?$'))
            if($matches.Count -ne 1){throw ('Metadonnee Chocolatey AMD non verifiable : '+$key)}
            $values[$key]=$matches[0].Groups['v'].Value
        }
        return [pscustomobject]@{Url=$values.url64;SHA256=$values.checksum64;ChecksumType=$values.checksumType64;SilentArgs=$values.silentArgs}
    }finally{$zip.Dispose()}
}

function Invoke-LDLCAmdChocolateyFallback {
    param($Source,[string]$InstallerPath,[string]$WorkDirectory,$Definition,[object[]]$Targets,[int]$StartPercent)
    Stop-IfRequested
    # Both method and post-install validation use the exact same current signed
    # full package and matching INF targets. No fallback to an unknown/older release.
    if(-not $Source -or [string]$Source.Version -notmatch '^\d+(?:\.\d+){1,3}$' -or -not $Targets.Count){throw 'Repli Chocolatey refuse : derniere version AMD et compatibilite non verifiees.'}
    $choco=Get-Command choco.exe -ErrorAction SilentlyContinue
    if(-not $choco){throw 'Repli Chocolatey indisponible : Chocolatey non installe.'}
    Assert-LDLCAmdNoDowngrade -ReleaseVersion $Source.Version -Targets $Targets -Software (Get-LDLCAmdSoftwareInstallation -Refresh)
    $feed=Join-Path $WorkDirectory 'chocolatey-feed'
    [void][IO.Directory]::CreateDirectory($feed)
    $name='amd-software-adrenalin-edition';$version=[string]$Source.Version
    $package=Join-Path $feed ($name+'.'+$version+'.nupkg')
    $url='https://community.chocolatey.org/api/v2/package/'+$name+'/'+[uri]::EscapeDataString($version)
    Write-ProgressFile $StartPercent ('Repli Chocolatey : verification AMD Adrenalin '+$version)
    try{Invoke-WebRequest -Uri $url -OutFile $package -UseBasicParsing -TimeoutSec 120 -ErrorAction Stop | Out-Null}
    catch{
        if(Test-LDLCStopRequestError -ErrorRecord $_){throw}
        throw ('Package Chocolatey AMD '+$version+' indisponible ou inaccessible : '+$_.Exception.Message+'. Aucune ancienne version utilisee.')
    }
    $info=Get-LDLCAmdChocolateyPackageMetadata -PackagePath $package
    if($info.Url -cne [string]$Source.Url -or $info.ChecksumType -ine 'sha256' -or $info.SHA256 -notmatch '^[a-fA-F0-9]{64}$' -or $info.SilentArgs -cne '-install'){
        throw 'Repli Chocolatey refuse : URL officielle, SHA256 ou mode installation differents du package AMD verifie.'
    }
    if(-not (Test-LDLCAmdGpuInstallerFile -Path $InstallerPath -MinBytes $Definition.MinBytes) -or
        (Get-FileHash -LiteralPath $InstallerPath -Algorithm SHA256).Hash -ine $info.SHA256){
        throw 'Repli Chocolatey refuse : empreinte ou signature du package AMD non conforme.'
    }
    # A local feed pins the inspected nupkg, rather than fetching a different
    # script between inspection and execution. Keep Chocolatey's checksum checks.
    $installer=@{};foreach($key in $Definition.Keys){$installer[$key]=$Definition[$key]}
    $installer.ExeArguments=@('upgrade',$name,('--version='+$version),('--source="'+$feed+'"'),'--yes','--force','--ignore-dependencies','--no-progress','--limit-output',('--execution-timeout='+$Definition.TimeoutSeconds))
    Write-Step ('Repli Chocolatey : installation AMD '+$version+', package et SHA256 verifies ; aucun pilote anterieur autorise.')
    Write-ProgressFile $StartPercent ('Installation AMD Adrenalin '+$version+' via Chocolatey')
    # This also waits for AMD descendants after Chocolatey/the extractor exits.
    return Invoke-LDLCAmdGpuInstaller -Path $choco.Source -Installer $installer
}

function Install-LDLCAmdStack {
    param([int]$StartPercent = 84)
    Stop-IfRequested
    $amdAdapters=@(Get-LDLCGpuAdapters | Where-Object {(Get-LDLCGpuAdapterVendor -Adapter $_) -eq 'AMD'})
    if(-not $amdAdapters.Count){Write-Step 'AMD non applicable : aucun adaptateur graphique AMD present.';return}
    $formFactor=Get-LDLCGpuComputerFormFactor
    if($formFactor.Portable -or -not $formFactor.Known){Write-Step ('AMD Adrenalin ignore : '+$formFactor.Reason);return}
    $deviceIds=@($amdAdapters | ForEach-Object {[string]$_.PNPDeviceID} | Select-Object -Unique)
    $tempRoot=$null;$fallbackAllowed=$false;$exitCode=$null
    # Scope-local: Windows PowerShell HTTP progress can severely slow large packages.
    # Application progress still comes from Write-ProgressFile.
    $ProgressPreference='SilentlyContinue'
    try {
        if(@($deviceIds | Where-Object {[string]::IsNullOrWhiteSpace($_)}).Count){throw 'Identifiant PCI du GPU AMD indisponible : compatibilite impossible a verifier.'}
        Write-Step ('GPU AMD detectes : '+($amdAdapters.Name -join ', '))
        Write-ProgressFile $StartPercent 'Recherche de la derniere version AMD Adrenalin officielle'
        $definition=Get-LDLCAmdAdrenalinInstallerDefinition
        $discovery=Resolve-LDLCAmdGpuOfficialSource
        $sources=@(Resolve-LDLCAmdGpuFullOfficialSources -AutoDetectSource $discovery)
        Write-Step ('Version Adrenalin officielle actuelle : '+$discovery.Version+'. Recherche du package complet compatible, sans ancien cache.')
        $tempRoot=Join-Path ([IO.Path]::GetTempPath()) ('LDLC-AMD-'+[guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($tempRoot)
        $selected=$null;$targets=@();$failures=@();$index=0
        foreach($source in $sources){
            Stop-IfRequested
            # Every candidate belongs to the current release; no fallback to an older cached driver.
            $index++;$downloadPath=Join-Path $tempRoot $source.FileName;$metadata=Join-Path $tempRoot ('metadata-'+$index)
            Write-ProgressFile $StartPercent ('Telechargement AMD Adrenalin '+$source.Version+' (package complet)')
            Write-Step ('Telechargement AMD officiel : '+$source.Url)
            try {
                Invoke-WebRequest -Uri $source.Url -Headers @{Referer=$source.PageUrl;'Cache-Control'='no-cache';Pragma='no-cache'} -OutFile $downloadPath -UseBasicParsing -TimeoutSec $definition.DownloadTimeoutSeconds -ErrorAction Stop | Out-Null
                if(-not (Test-LDLCAmdGpuInstallerFile -Path $downloadPath -MinBytes $definition.MinBytes)){throw 'Installateur AMD refuse : taille, entetes MZ/PE ou signature AMD valide non confirmes.'}
                Expand-LDLCAmdPackageMetadata -Path $downloadPath -Destination $metadata
                $targets=@(Get-LDLCAmdPackageDriverTargets -MetadataPath $metadata -PnpDeviceIds $deviceIds)
                $selected=$source;break
            }catch{
                if(Test-LDLCStopRequestError -ErrorRecord $_){throw}
                $failures += $_.Exception.Message
                Write-Step ('Package AMD non retenu : '+$_.Exception.Message)
                if(Test-Path -LiteralPath $downloadPath){Remove-Item -LiteralPath $downloadPath -Force -ErrorAction SilentlyContinue}
            }
        }
        if(-not $selected){throw ('Aucun package AMD '+$discovery.Version+' verifie pour tous les GPU : '+($failures -join ' | '))}
        foreach($target in $targets){Write-Step ('Cible pilote AMD '+$target.PnpDeviceId+' : '+$target.DriverVersion+' (INF du package signe).')}
        $beforeSoftware=Get-LDLCAmdSoftwareInstallation -Refresh
        if((Test-LDLCAmdSoftwareTargetReady -Software $beforeSoftware -ReleaseVersion $selected.Version -MetadataPath $metadata) -and (Test-LDLCAmdDriverTargetsReady -Targets $targets)){
            Write-Ok ('AMD Adrenalin '+$selected.Version+' : versions cibles deja atteintes ou depassees ; aucun ancien pilote impose.')
            Ensure-LDLCGpuDesktopShortcut -Vendor 'AMD';return
        }
        Assert-LDLCAmdNoDowngrade -ReleaseVersion $selected.Version -Targets $targets -Software $beforeSoftware
        $fallbackAllowed=$true
        Write-ProgressFile $StartPercent ('Installation du package complet AMD Adrenalin '+$selected.Version)
        $exitCode=Invoke-LDLCAmdGpuInstaller -Path $downloadPath -Installer $definition
        if(Wait-LDLCAmdTargetVersions -ReleaseVersion $selected.Version -MetadataPath $metadata -Targets $targets -TimeoutSeconds $definition.ValidationTimeoutSeconds){
            Write-Ok ('AMD Adrenalin '+$selected.Version+' confirme : application actuelle et versions pilotes du package atteintes pour chaque GPU (code '+$exitCode+').')
            Ensure-LDLCGpuDesktopShortcut -Vendor 'AMD';return
        }
        if($exitCode -in @(3010,1641)){
            Write-Warn ('AMD '+$selected.Version+' demande un redemarrage : versions cibles non confirmees. Verification requise apres redemarrage ; aucun succes declare.');return
        }
        $software=Get-LDLCAmdSoftwareInstallation -Refresh
        $observed=if($software){[string]$software.DisplayVersion}else{'absente'}
        throw ('AMD non confirme : application Adrenalin actuelle '+$selected.Version+' attendue (observee : '+$observed+'), pilote DISPLAY AMD signe/sain a la version INF requise pour chaque GPU. Code '+$exitCode+'.')
    }catch{
        if(Test-LDLCStopRequestError -ErrorRecord $_){throw}
        $officialError=$_.Exception.Message
        if($fallbackAllowed -and $exitCode -notin @(3010,1641) -and -not $_.Exception.Data['LDLCAmdInstallerStillActive']){
            try {
                Write-Step ('Installation AMD officielle non confirmee : '+$officialError+'. Tentative Chocolatey de la meme version actuelle verifiee.')
                $exitCode=Invoke-LDLCAmdChocolateyFallback -Source $selected -InstallerPath $downloadPath -WorkDirectory $tempRoot -Definition $definition -Targets $targets -StartPercent $StartPercent
                if(Wait-LDLCAmdTargetVersions -ReleaseVersion $selected.Version -MetadataPath $metadata -Targets $targets -TimeoutSeconds $definition.ValidationTimeoutSeconds){
                    Write-Ok ('AMD Adrenalin '+$selected.Version+' confirme apres repli Chocolatey : application et pilotes a la version requise pour chaque GPU (code '+$exitCode+').')
                    Ensure-LDLCGpuDesktopShortcut -Vendor 'AMD';return
                }
                if($exitCode -in @(3010,1641)){
                    Write-Warn ('AMD '+$selected.Version+' via Chocolatey demande un redemarrage : versions non confirmees, aucun succes declare.');return
                }
                throw 'Chocolatey termine mais versions actuelles de l application et des pilotes AMD non confirmees.'
            }catch{
                if(Test-LDLCStopRequestError -ErrorRecord $_){throw}
                Write-Err ('Installation AMD non confirmee : officiel : '+$officialError+' | repli Chocolatey : '+$_.Exception.Message)
            }
        }else{
            Write-Err ('Installation AMD non confirmee : '+$officialError+' Repli Chocolatey non lance : package actuel/compatibilite non verifies ou installateur encore actif.')
        }
    }finally{
        if($tempRoot -and (Test-Path -LiteralPath $tempRoot)){Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue}
    }
}

function Install-LDLCGpuDriversAndApps {
    param([int]$ProgressPercent = 84)

    Stop-IfRequested
    Write-Section "PILOTES GPU"
    Write-ProgressFile $ProgressPercent "Détection GPU et préparation des pilotes"

    $gpus = @(Get-LDLCGpuAdapters)

    $nvidiaGpuNames = New-Object System.Collections.Generic.List[string]
    $nvidiaGpuPnpIds = New-Object System.Collections.Generic.List[string]
    $amdGpuNames = New-Object System.Collections.Generic.List[string]
    $hasNvidiaPro = $false

    foreach ($gpu in $gpus) {
        Stop-IfRequested

        $gpuText = @(
            [string]$gpu.Name,
            [string]$gpu.AdapterCompatibility,
            [string]$gpu.PNPDeviceID
        ) -join ' '

        if ([string]::IsNullOrWhiteSpace($gpuText)) {
            continue
        }

        $vendor = Get-LDLCGpuAdapterVendor -Adapter $gpu

        if ($vendor -eq 'Intel') {
            Write-Step "GPU integre ignore : $($gpu.Name)"
            continue
        }

        if ($vendor -eq 'NVIDIA') {
            [void]$nvidiaGpuNames.Add([string]$gpu.Name)
            [void]$nvidiaGpuPnpIds.Add([string]$gpu.PNPDeviceID)

            if (Test-LDLCNvidiaProfessionalGpuName -GpuName ([string]$gpu.Name)) {
                $hasNvidiaPro = $true
            }

            continue
        }

        if ($vendor -eq 'AMD') {
            if ($gpuText -match '(?i)Radeon\(TM\)\s+Graphics|Radeon\s+Graphics|Vega\s*\d*\s*Graphics|Graphics\s+Family') {
                Write-Step "GPU AMD integre pris en charge : $($gpu.Name)"
            }

            [void]$amdGpuNames.Add([string]$gpu.Name)
        }
    }

    if ($nvidiaGpuNames.Count -eq 0 -and $amdGpuNames.Count -eq 0) {
        Write-Step "Aucun GPU NVIDIA/AMD present : pilotes GPU non applicables."
        return
    }

    Write-Host "   ______ ____  _   _ " -ForegroundColor DarkCyan
    Write-Host "  / ____// __ \| | | |" -ForegroundColor DarkCyan
    Write-Host " | |  __| |  | | | | |" -ForegroundColor Cyan
    Write-Host " | | |_ | |  | | | | |" -ForegroundColor Cyan
    Write-Host " | |__| | |__| | |_| |" -ForegroundColor Blue
    Write-Host "  \_____|\____/ \___/ " -ForegroundColor Blue

    if ($nvidiaGpuNames.Count -gt 0) {
        $gpuName = ($nvidiaGpuNames | Select-Object -Unique) -join ', '
        $pnpDeviceId = $nvidiaGpuPnpIds | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1

        if ($hasNvidiaPro) {
            Write-Ok "GPU NVIDIA Pro detecte : installation NVIDIA Studio Driver"
            Install-LDLCNvidiaStack -StartPercent $ProgressPercent -GpuName $gpuName -PnpDeviceId $pnpDeviceId -Professional
        }
        else {
            Write-Ok "GPU NVIDIA grand public detecte : installation NVIDIA Game Ready Driver"
            Install-LDLCNvidiaStack -StartPercent $ProgressPercent -GpuName $gpuName -PnpDeviceId $pnpDeviceId
        }
    }
    if ($amdGpuNames.Count -gt 0) {
        Write-Step "GPU AMD detecte : verification du format du PC avant installation"
        Install-LDLCAmdStack -StartPercent $ProgressPercent
    }
}

# endregion Module: 60.Gpu.ps1

# region Module: 70.DefaultApps.ps1
# Only Windows-reported effective associations can confirm success. UI actions are attempts.

function Ensure-LDLCDefaultAppsNativeInterop {
    if ('LDLCDefaultAppsNative' -as [type]) { return }
    Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public delegate bool LDLCEnumWindowsProc(IntPtr hwnd, IntPtr parameter);
[StructLayout(LayoutKind.Sequential)] public struct LDLCDefaultAppsPoint { public int X; public int Y; }
[ComImport, Guid("4e530b0a-e611-4c77-a3ac-9031d022281b"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface ILDLCApplicationAssociationRegistration {
    [PreserveSig] int QueryCurrentDefault([MarshalAs(UnmanagedType.LPWStr)] string query,
        int associationType, int associationLevel, out IntPtr association);
}
public static class LDLCDefaultAppsNative {
    [DllImport("user32.dll")] public static extern bool EnumWindows(LDLCEnumWindowsProc callback, IntPtr parameter);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr parent, LDLCEnumWindowsProc callback, IntPtr parameter);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hwnd, uint message, IntPtr wparam, IntPtr lparam);
    [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(LDLCDefaultAppsPoint point);
    [DllImport("user32.dll")] public static extern bool SetPhysicalCursorPos(int x, int y);
    [StructLayout(LayoutKind.Sequential)] public struct MouseInput {
        public int dx, dy; public uint data, flags, time; public IntPtr extra;
    }
    [StructLayout(LayoutKind.Explicit)] public struct InputUnion { [FieldOffset(0)] public MouseInput mouse; }
    [StructLayout(LayoutKind.Sequential)] public struct Input { public uint type; public InputUnion data; }
    [DllImport("user32.dll", SetLastError=true)] private static extern uint SendInput(uint count, Input[] inputs, int size);
    public static void ClickAt(int x, int y) {
        if (!SetPhysicalCursorPos(x, y)) throw new InvalidOperationException("Positionnement souris refuse par Windows");
        System.Threading.Thread.Sleep(90);
        Input[] inputs = new Input[2];
        inputs[0].data.mouse.flags = 0x0002;
        inputs[1].data.mouse.flags = 0x0004;
        if (SendInput(2, inputs, Marshal.SizeOf(typeof(Input))) != 2)
            throw new InvalidOperationException("Clic refuse par Windows (focus/niveau de privileges); aucune association confirmee");
    }
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hwnd, int command);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr hwnd, uint flags);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint from, uint to, bool attach);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hwnd, StringBuilder text, int count);
    [DllImport("shlwapi.dll", CharSet=CharSet.Unicode, ExactSpelling=true)]
    private static extern int AssocQueryStringW(uint flags, uint kind, string association, string extra, StringBuilder output, ref uint count);
    public static string CurrentDefault(string association) {
        // ASSOCSTR_PROGID reads the effective Windows association without creating
        // a COM server for every poll. Keep COM as a compatibility fallback.
        try { return AssociationString(association, 20, 0x100u | (association.StartsWith(".") ? 0u : 0x1000u)); }
        catch (Exception) { }
        object instance = Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("591209c7-767b-42b2-9fba-44ee4615f2c7")));
        IntPtr value = IntPtr.Zero;
        try {
            // AT_FILEEXTENSION=0, AT_URLPROTOCOL=1, AL_EFFECTIVE=1. Read-only.
            int hr = ((ILDLCApplicationAssociationRegistration)instance).QueryCurrentDefault(
                association, association.StartsWith(".") ? 0 : 1, 1, out value);
            Marshal.ThrowExceptionForHR(hr);
            return Marshal.PtrToStringUni(value) ?? "";
        } finally {
            if (value != IntPtr.Zero) Marshal.FreeCoTaskMem(value);
            Marshal.ReleaseComObject(instance);
        }
    }
    public static string Executable(string association) {
        // NOFIXUPS prevents registry repair; IS_PROTOCOL honors the user's URL defaults.
        uint flags = 0x100u | (association.StartsWith(".") ? 0u : 0x1000u);
        return AssociationString(association, 2, flags);
    }
    public static string ExecutableForProgId(string progId) {
        // Use only a ProgID already reported by Windows, never a guessed registry value.
        return AssociationString(progId, 2, 0x100u | 0x800u);
    }
    private static string AssociationString(string association, uint kind, uint flags) {
        uint count = 0;
        string extra = kind == 2 ? "open" : null;
        int hr = AssocQueryStringW(flags, kind, association, extra, null, ref count);
        if (hr < 0) Marshal.ThrowExceptionForHR(hr);
        if (count == 0 || count > 32768) throw new InvalidOperationException("Executable non resolu");
        StringBuilder text = new StringBuilder((int)count);
        Marshal.ThrowExceptionForHR(AssocQueryStringW(flags, kind, association, extra, text, ref count));
        return text.ToString();
    }
}
"@
}

function Ensure-LDLCDefaultAppsUiAutomation {
    Add-Type -AssemblyName UIAutomationClient
    Add-Type -AssemblyName UIAutomationTypes
}

function Get-LDLCDefaultAppsTick {
    return ([double][Diagnostics.Stopwatch]::GetTimestamp() * 1000 / [Diagnostics.Stopwatch]::Frequency)
}

function Wait-LDLCDefaultAppsCondition {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Probe,
        [ValidateRange(0, 120000)][int]$TimeoutMilliseconds = 15000,
        [ValidateRange(50, 2000)][int]$PollMilliseconds = 400
    )
    $deadline = (Get-LDLCDefaultAppsTick) + $TimeoutMilliseconds
    do {
        Stop-IfRequested
        $value = & $Probe
        if ($value) { return $value }
        $remaining = $deadline - (Get-LDLCDefaultAppsTick)
        if ($remaining -le 0) { break }
        Start-Sleep -Milliseconds ([int][math]::Min($PollMilliseconds, $remaining))
    } while ($true)
    return $null
}

function Convert-LDLCDefaultAppsComparableText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $builder = New-Object Text.StringBuilder
    foreach ($character in $Text.Normalize([Text.NormalizationForm]::FormD).ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($character) -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$builder.Append($character)
        }
    }
    return (($builder.ToString().ToLowerInvariant() -replace '\s+', ' ').Trim())
}

function Get-LDLCEffectiveAssociation {
    param([Parameter(Mandatory = $true)][string]$Association)
    $progId = ''; $executable = ''; $errorText = ''
    try {
        Ensure-LDLCDefaultAppsNativeInterop
        $progId = [LDLCDefaultAppsNative]::CurrentDefault($Association)
        try { $executable = [LDLCDefaultAppsNative]::Executable($Association) }
        catch { $executable = [LDLCDefaultAppsNative]::ExecutableForProgId($progId) }
        $executable = [Environment]::ExpandEnvironmentVariables($executable.Trim().Trim('"'))
        if ($progId -cne [LDLCDefaultAppsNative]::CurrentDefault($Association)) {
            throw 'Association modifiee pendant la lecture; nouvelle verification requise.'
        }
        if (-not $progId -or -not $executable -or -not (Test-Path -LiteralPath $executable -PathType Leaf)) {
            throw 'ProgID ou executable effectif absent.'
        }
    }
    catch { $errorText = $_.Exception.Message }
    return [pscustomobject]@{ Association = $Association; ProgId = $progId; Executable = $executable; Error = $errorText }
}

function Test-LDLCEffectiveAssociationTarget {
    param($State, [ValidateSet('Chrome', 'Adobe')][string]$Application)
    if (-not $State -or $State.Error -or -not $State.ProgId -or -not $State.Executable) { return $false }
    $fileName = [IO.Path]::GetFileName($State.Executable)
    if ($Application -eq 'Chrome') {
        return (($State.ProgId -match '^ChromeHTML(?:\.|$)' -or $State.ProgId -ieq 'Applications\chrome.exe') -and $fileName -ieq 'chrome.exe')
    }
    if ($fileName -notin @('Acrobat.exe', 'AcroRd32.exe')) { return $false }
    if ($State.ProgId -match '^(Acrobat|AcroExch)\.Document(?:\.|$)' -or
        $State.ProgId -match '^Applications\\(?:Acrobat|AcroRd32)\.exe$') { return $true }
    # Adobe's registered PDF ProgID can change with its edition/package. The
    # effective executable must still be its PDF reader, not a registered app alone.
    return ($State.ProgId -in @(Get-LDLCRegisteredPdfProgIds -Application Adobe))
}

function Get-LDLCRegisteredPdfProgIds {
    param([ValidateSet('Adobe')][string]$Application = 'Adobe')
    $ids = New-Object 'Collections.Generic.List[string]'
    foreach ($hive in @([Microsoft.Win32.RegistryHive]::CurrentUser, [Microsoft.Win32.RegistryHive]::LocalMachine)) {
        foreach ($view in @([Microsoft.Win32.RegistryView]::Registry64, [Microsoft.Win32.RegistryView]::Registry32)) {
            $base = $null; $registered = $null; $capabilities = $null
            try {
                $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey($hive, $view)
                $registered = $base.OpenSubKey('Software\RegisteredApplications')
                if (-not $registered) { continue }
                foreach ($name in $registered.GetValueNames()) {
                    if (-not (Test-LDLCDefaultAppsApplicationName -Name $name -Application Adobe -RegisteredName)) { continue }
                    try {
                        $path = [string]$registered.GetValue($name)
                        if (-not $path) { continue }
                        $capabilities = $base.OpenSubKey($path.TrimEnd('\') + '\FileAssociations')
                        if ($capabilities) {
                            $id = [string]$capabilities.GetValue('.pdf')
                            if ($id -and -not $ids.Contains($id)) { $ids.Add($id) }
                        }
                    } finally { if ($capabilities) { $capabilities.Dispose(); $capabilities = $null } }
                }
            } catch { Write-Verbose ('Adobe PDF registration unavailable in ' + $hive + '/' + $view) }
            finally { if ($registered) { $registered.Dispose() }; if ($base) { $base.Dispose() } }
        }
    }
    return $ids.ToArray()
}

function Set-LDLCDefaultAppsDeferredDetail {
    param([ValidateSet('Chrome','Adobe','Widgets')][string]$Application, [string]$Detail)
    if (-not $script:LDLCDefaultAppsDeferredDetails) { $script:LDLCDefaultAppsDeferredDetails = @{} }
    $script:LDLCDefaultAppsDeferredDetails[$Application] = $Detail
}

function Confirm-LDLCDefaultAppsFinalState {
    # Read-only final audit. A failed UI attempt is not a final configuration error.
    # Do not touch unrelated errors, earlier runs, settings, UserChoice or its hash.
    if (-not $script:LDLCDefaultAppsPendingChecks -or $script:LDLCDefaultAppsFinalAuditDone) { return }
    $states = [ordered]@{}; $failures = New-Object 'Collections.Generic.List[string]'
    foreach ($application in @('Adobe','Chrome','Widgets')) {
        if (-not $script:LDLCDefaultAppsPendingChecks.ContainsKey($application)) { continue }
        Stop-IfRequested
        try {
            if ($application -eq 'Widgets') {
                $state = Get-LDLCWidgetsTaskbarState
                $states[$application] = $state
                if ($state.Disabled) { Write-Info '[FINAL-CHECK] Widgets desactives : etat Windows confirme.'; continue }
                $failure = '[TASKBAR] Widgets : desactivation non confirmee par Windows (TaskbarDa=' + $state.TaskbarDa + '; strategie reconnue=' + $state.PolicyDisabled + ').'
            } else {
                $verification = Wait-LDLCDefaultAppConfirmation -Application $application -TimeoutMilliseconds 1000
                $states[$application] = $verification.State
                if ($verification.Confirmed) { Write-Info ('[FINAL-CHECK] ' + $application + ' confirme par Windows ; aucune alerte de tentative conservee.'); continue }
                $details = @($verification.State.Associations | ForEach-Object { $_.Association + '=' + $_.ProgId + ' [' + $_.Executable + '] ' + $_.Error }) -join '; '
                $failure = '[DEFAULT-APPS] ' + $application + ' : configuration finale non confirmee. ' + $details
            }
        } catch {
            if (Test-LDLCStopRequestError $_) { throw }
            $failure = '[FINAL-CHECK] Verification ' + $application + ' impossible : ' + $_.Exception.Message
        }
        $failures.Add($failure); Write-Warn $failure
    }
    $script:LDLCDefaultAppsFinalAuditDone = $true
    return [pscustomobject]@{ Confirmed = ($failures.Count -eq 0); States = [pscustomobject]$states; Failures = $failures.ToArray() }
}

function Get-LDLCDefaultAppState {
    param([ValidateSet('Chrome', 'Adobe')][string]$Application)
    $keys = if ($Application -eq 'Chrome') { @('http', 'https', '.htm', '.html') } else { @('.pdf') }
    $states = @($keys | ForEach-Object { Get-LDLCEffectiveAssociation -Association $_ })
    $missing = @($states | Where-Object { -not (Test-LDLCEffectiveAssociationTarget -State $_ -Application $Application) })
    return [pscustomobject]@{ Application = $Application; Confirmed = ($missing.Count -eq 0); Associations = $states; Missing = @($missing | ForEach-Object { $_.Association }) }
}

function Get-LDLCChromeDefaultBrowserState {
    $state = Get-LDLCDefaultAppState -Application Chrome
    return [pscustomobject]@{
        IsChrome = $state.Confirmed; Associations = $state.Associations; Missing = $state.Missing
        HttpProgId = $state.Associations[0].ProgId; HttpsProgId = $state.Associations[1].ProgId
        HtmProgId = $state.Associations[2].ProgId; HtmlProgId = $state.Associations[3].ProgId
    }
}

function Get-LDLCAdobePdfDefaultState {
    $state = Get-LDLCDefaultAppState -Application Adobe
    return [pscustomobject]@{ IsAcrobat = $state.Confirmed; CurrentProgId = $state.Associations[0].ProgId; Associations = $state.Associations; Missing = $state.Missing }
}

function Wait-LDLCDefaultAppConfirmation {
    param([ValidateSet('Chrome', 'Adobe')][string]$Application, [int]$TimeoutMilliseconds = 12000)
    if ($Application -eq 'Chrome' -and -not $PSBoundParameters.ContainsKey('TimeoutMilliseconds')) { $TimeoutMilliseconds = 6000 }
    # Two independent readings avoid accepting a transient association during a reset.
    $tracking = @{ Last = $null; Consecutive = 0 }
    $confirmed = Wait-LDLCDefaultAppsCondition -TimeoutMilliseconds $TimeoutMilliseconds -PollMilliseconds 250 -Probe {
        $tracking.Last = Get-LDLCDefaultAppState -Application $Application
        if ($tracking.Last.Confirmed) { $tracking.Consecutive++ } else { $tracking.Consecutive = 0 }
        return ($tracking.Consecutive -ge 2)
    }
    return [pscustomobject]@{ Confirmed = [bool]$confirmed; State = $tracking.Last }
}

function Wait-LDLCChromeDefaultBrowserConfirmation {
    param([int]$TimeoutSeconds = 6)
    return Wait-LDLCDefaultAppConfirmation -Application Chrome -TimeoutMilliseconds ($TimeoutSeconds * 1000)
}

function Wait-LDLCAdobePdfDefaultConfirmation {
    param([int]$TimeoutSeconds = 24)
    return Wait-LDLCDefaultAppConfirmation -Application Adobe -TimeoutMilliseconds ($TimeoutSeconds * 1000)
}

function Get-LDLCDefaultAppUris {
    param([ValidateSet('Chrome', 'Adobe')][string]$Application)
    $uris = New-Object 'Collections.Generic.List[string]'
    foreach ($hive in @([Microsoft.Win32.RegistryHive]::CurrentUser, [Microsoft.Win32.RegistryHive]::LocalMachine)) {
        foreach ($view in @([Microsoft.Win32.RegistryView]::Registry64, [Microsoft.Win32.RegistryView]::Registry32)) {
            $baseKey = $null; $key = $null
            try {
                $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey($hive, $view)
                $key = $baseKey.OpenSubKey('Software\RegisteredApplications')
                if (-not $key) { continue }
                foreach ($name in $key.GetValueNames()) {
                    if (-not (Test-LDLCDefaultAppsApplicationName -Name $name -Application $Application -RegisteredName)) { continue }
                    $parameter = if ($hive -eq [Microsoft.Win32.RegistryHive]::CurrentUser) { 'registeredAppUser' } else { 'registeredAppMachine' }
                    $uri = 'ms-settings:defaultapps?' + $parameter + '=' + [Uri]::EscapeDataString($name)
                    if (-not $uris.Contains($uri)) { $uris.Add($uri) }
                }
            }
            finally {
                if ($key) { $key.Dispose() }
                if ($baseKey) { $baseKey.Dispose() }
            }
        }
    }
    return $uris.ToArray()
}

function Get-LDLCDefaultAppsWindows {
    Ensure-LDLCDefaultAppsNativeInterop
    $handles = New-Object 'Collections.Generic.List[IntPtr]'
    $callback = [LDLCEnumWindowsProc]{ param([IntPtr]$handle, [IntPtr]$parameter)
        $handles.Add($handle)
        return $true
    }
    [void][LDLCDefaultAppsNative]::EnumWindows($callback, [IntPtr]::Zero)
    # The Windows 11 OpenWith foreground host can be a child/InputSite HWND,
    # absent from EnumWindows even while its chooser is visible to the technician.
    $foreground = [LDLCDefaultAppsNative]::GetForegroundWindow()
    if ($foreground -ne [IntPtr]::Zero -and -not $handles.Contains($foreground)) { $handles.Insert(0, $foreground) }
    foreach ($handle in $handles) {
        $processId = [uint32]0
        [void][LDLCDefaultAppsNative]::GetWindowThreadProcessId($handle, [ref]$processId)
        try { $process = Get-Process -Id $processId -ErrorAction Stop } catch { continue }
        if (-not [LDLCDefaultAppsNative]::IsWindowVisible($handle) -and $process.ProcessName -ne 'OpenWith') { continue }
        $text = New-Object Text.StringBuilder 512
        [void][LDLCDefaultAppsNative]::GetWindowText($handle, $text, $text.Capacity)
        $isSettings = $process.ProcessName -eq 'SystemSettings' -or ($process.ProcessName -eq 'ApplicationFrameHost' -and $text.ToString() -match '(?i)param|settings')
        if ($isSettings -or $process.ProcessName -in @('OpenWith', 'PickerHost', 'ShellExperienceHost', 'ApplicationFrameHost', 'AppResolverUX')) {
            [pscustomobject]@{ Handle = $handle; IsSettings = $isSettings; ProcessId = $processId }
        }
    }
}

function Set-LDLCDefaultAppsFocus {
    param($Window)
    $foreground = [LDLCDefaultAppsNative]::GetForegroundWindow()
    if ($foreground -eq $Window.Handle -or [LDLCDefaultAppsNative]::GetAncestor($foreground, 3) -eq $Window.Handle) { return $true }
    $foregroundProcess = [uint32]0
    [void][LDLCDefaultAppsNative]::GetWindowThreadProcessId($foreground, [ref]$foregroundProcess)
    if ($foregroundProcess -eq $Window.ProcessId -and $foregroundProcess -ne 0) { return $true }
    if ([LDLCDefaultAppsNative]::IsIconic($Window.Handle)) { [void][LDLCDefaultAppsNative]::ShowWindowAsync($Window.Handle, 4) }
    [void][LDLCDefaultAppsNative]::SetForegroundWindow($Window.Handle)
    if ([LDLCDefaultAppsNative]::GetForegroundWindow() -ne $Window.Handle) {
        $thread = [LDLCDefaultAppsNative]::GetCurrentThreadId()
        $foregroundThread = [LDLCDefaultAppsNative]::GetWindowThreadProcessId($foreground, [ref]$foregroundProcess)
        $attached = $false
        try {
            if ($foregroundThread -ne 0 -and $foregroundThread -ne $thread) { $attached = [LDLCDefaultAppsNative]::AttachThreadInput($thread, $foregroundThread, $true) }
            [void][LDLCDefaultAppsNative]::SetForegroundWindow($Window.Handle)
        }
        finally { if ($attached) { [void][LDLCDefaultAppsNative]::AttachThreadInput($thread, $foregroundThread, $false) } }
    }
    # The next poll checks focus again; never maximize or force input into another app.
    $foreground = [LDLCDefaultAppsNative]::GetForegroundWindow()
    [void][LDLCDefaultAppsNative]::GetWindowThreadProcessId($foreground, [ref]$foregroundProcess)
    return ($foreground -eq $Window.Handle -or [LDLCDefaultAppsNative]::GetAncestor($foreground, 3) -eq $Window.Handle -or
        ($foregroundProcess -eq $Window.ProcessId -and $foregroundProcess -ne 0))
}

function Get-LDLCDefaultAppsRoot {
    param($Window)
    Ensure-LDLCDefaultAppsUiAutomation
    Ensure-LDLCDefaultAppsNativeInterop
    $bestRoot = [System.Windows.Automation.AutomationElement]::FromHandle($Window.Handle)
    $bestCount = $bestRoot.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition).Count
    if ($Window.IsSettings -and $bestCount -gt 0) { return $bestRoot }
    # OpenWith can expose only a dummy top-level HWND; its child hosts own the UIA tree.
    $handles = New-Object 'Collections.Generic.List[IntPtr]'
    $callback = [LDLCEnumWindowsProc]{ param([IntPtr]$handle, [IntPtr]$parameter)
        $handles.Add($handle)
        return $true
    }
    [void][LDLCDefaultAppsNative]::EnumChildWindows($Window.Handle, $callback, [IntPtr]::Zero)
    foreach ($handle in $handles) {
        try {
            $root = [System.Windows.Automation.AutomationElement]::FromHandle($handle)
            $count = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition).Count
            if ($count -gt $bestCount) { $bestRoot = $root; $bestCount = $count }
        } catch { continue }
    }
    return $bestRoot
}

function Get-LDLCDefaultAppsParentElement {
    param($Element)
    return [System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($Element)
}

function Test-LDLCDefaultAppsSameElement {
    param($Left, $Right)
    if (-not $Left -or -not $Right) { return $false }
    return (($Left.GetRuntimeId() -join '.') -eq ($Right.GetRuntimeId() -join '.'))
}

function Resolve-LDLCDefaultAppsChoiceElement {
    param($Element, $Root)
    # Windows can expose the app label as a Text child of an unnamed clickable row.
    # Stay inside the observed picker; never invoke an arbitrary page ancestor.
    $candidate = $Element
    for ($depth = 0; $candidate -and $depth -lt 5; $depth++) {
        if (Test-LDLCDefaultAppsSameElement $candidate $Root) { return $null }
        $type = $candidate.Current.ControlType.ProgrammaticName
        if ($type -in @('ControlType.Button', 'ControlType.ListItem', 'ControlType.RadioButton', 'ControlType.Hyperlink')) {
            return $candidate
        }
        $candidate = Get-LDLCDefaultAppsParentElement -Element $candidate
    }
    return $null
}

function Get-LDLCDefaultAppsControls {
    param($Root)
    $elements = $Root.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
    foreach ($element in $elements) {
        try {
            $current = $element.Current
            $target = $element
            $name = Convert-LDLCDefaultAppsComparableText $current.Name
            if ($current.ControlType.ProgrammaticName -eq 'ControlType.Text' -and
                ((Test-LDLCDefaultAppsApplicationName -Name $name -Application Adobe) -or
                 (Test-LDLCDefaultAppsApplicationName -Name $name -Application Chrome))) {
                $row = Resolve-LDLCDefaultAppsChoiceElement -Element $element -Root $Root
                if ($row) {
                    # Preserve the heading for page detection as well as the clickable alias.
                    [pscustomobject]@{ Element = $element; Name = $name; AutomationId = $current.AutomationId;
                        ControlType = $current.ControlType.ProgrammaticName; Enabled = $current.IsEnabled; Offscreen = $current.IsOffscreen }
                    $target = $row; $current = $row.Current
                }
            }
            [pscustomobject]@{
                Element = $target; Name = $name
                AutomationId = $current.AutomationId; ControlType = $current.ControlType.ProgrammaticName
                Enabled = $current.IsEnabled; Offscreen = $current.IsOffscreen
            }
        }
        catch { continue } # Virtualized controls may disappear between enumeration and reading.
    }
}

function Get-LDLCDefaultAppsPickerRoot {
    param($Window, $Root, [string]$Association)
    $candidates = @()
    if (-not $Window.IsSettings) { $candidates = @($Root) }
    else {
        $elements = $Root.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
        foreach ($element in $elements) {
            try {
                if (-not $element.Current.IsOffscreen -and
                    ($element.Current.ControlType -eq [System.Windows.Automation.ControlType]::Window -or
                     $element.Current.ClassName -match '^(ContentDialog|Popup)$')) { $candidates += $element }
            }
            catch { continue }
        }
    }
    $pattern = '(?i)(?<![a-z0-9.])' + [regex]::Escape($Association) + '(?![a-z0-9])'
    if ($Window.IsSettings) {
        # Modern XAML pickers can be Pane/Group rather than Window/ContentDialog.
        # Find the smallest chooser subtree, not the Settings page behind it.
        foreach ($element in $elements) {
            try {
                $name = Convert-LDLCDefaultAppsComparableText $element.Current.Name
                if ($element.Current.IsOffscreen -or $name -notmatch '(choisi|select|choose|comment.*ouvrir)') { continue }
                $parent = $element
                for ($depth = 0; $parent -and $depth -lt 9; $depth++) {
                    $candidates += $parent
                    if (Test-LDLCDefaultAppsSameElement $parent $Root) { break }
                    $parent = Get-LDLCDefaultAppsParentElement $parent
                }
            }
            catch { continue }
        }
    }
    $valid = @()
    foreach ($candidate in $candidates) {
        $controls = @(Get-LDLCDefaultAppsControls $candidate)
        $names = ((@([string]$candidate.Current.Name) + @(($controls | Where-Object { -not $_.Offscreen }).Name)) -join ' ')
        if ($names -notmatch $pattern -or (Convert-LDLCDefaultAppsComparableText $names) -notmatch '(choisi|select|choose|comment.*ouvrir)') { continue }
        # An association card on the underlying page is never a selector choice.
        if (@($controls | Where-Object { $_.ControlType -eq 'ControlType.Button' -and $_.Name -match '^\.[a-z0-9]+(?:\s|,|:)' }).Count) { continue }
        $choice = (Select-LDLCDefaultAppsControl $controls Choice -Application Adobe) -or
            (Select-LDLCDefaultAppsControl $controls Choice -Application Chrome)
        if ($choice) { $valid += [pscustomobject]@{ Root = $candidate; Count = $controls.Count } }
    }
    if ($valid.Count) { return ($valid | Sort-Object Count | Select-Object -First 1).Root }
    return $null
}

function Select-LDLCDefaultAppsControl {
    param($Controls, [ValidateSet('Association', 'Choice', 'Confirm', 'Page')][string]$Kind,
        [string]$Association, [ValidateSet('Chrome', 'Adobe')][string]$Application)
    foreach ($control in @($Controls | Sort-Object Offscreen)) {
        if (-not $control.Enabled) { continue }
        $name = Convert-LDLCDefaultAppsComparableText $control.Name
        $isApplication = Test-LDLCDefaultAppsApplicationName -Name $name -Application $Application
        $actionable = $control.ControlType -in @('ControlType.Button', 'ControlType.ListItem', 'ControlType.RadioButton', 'ControlType.Hyperlink')
        switch ($Kind) {
            'Page' {
                $chromeHeading = $Application -eq 'Chrome' -and (Test-LDLCChromeBrowserDefaultLabel -Name $name)
                $pageType = $control.ControlType -in @('ControlType.Text', 'ControlType.Button') -or ($chromeHeading -and $control.ControlType -eq 'ControlType.Group')
                if (($isApplication -or $chromeHeading) -and $pageType -and -not $control.Offscreen) { return $control }
            }
            'Association' {
                if ($actionable -and $name -match ('^' + [regex]::Escape($Association) + '(?:[,\s:]|$)')) { return $control }
            }
            'Choice' {
                if ($actionable -and $isApplication) { return $control }
            }
            'Confirm' {
                if (-not $control.Offscreen -and $control.ControlType -eq 'ControlType.Button' -and
                    $name -match '^(definir par defaut|set default|set as default|ok|toujours|always|changer quand meme|basculer quand meme|switch anyway)$') { return $control }
            }
        }
    }
    return $null
}

function Test-LDLCChromeBrowserDefaultLabel {
    param([string]$Name, [switch]$WithAction)
    $name = Convert-LDLCDefaultAppsComparableText $Name
    $heading = '(?:definir google chrome (?:comme |en tant que |pour )?(?:votre )?navigateur par defaut|make google chrome (?:your |the )?default browser|(?:set|use) google chrome as (?:your |the )?default browser)'
    $action = '(?:definir par defaut|set default|set as default)'
    $separator = '\s*[,;:\-]?\s*'
    if ($name -match ('^' + $heading + $separator + $action + '[.!]?$') -or
        $name -match ('^' + $action + $separator + $heading + '[.!]?$')) { return $true }
    return (-not $WithAction -and $name -match ('^' + $heading + '[.:!]?$'))
}

function Get-LDLCChromeBrowserDefaultControl {
    param($Root)
    $controls = @(Get-LDLCDefaultAppsControls $Root)
    $qualified = @($controls | Where-Object { $_.Enabled -and $_.ControlType -eq 'ControlType.Button' -and
        (Test-LDLCChromeBrowserDefaultLabel -Name $_.Name -WithAction) } | Sort-Object Offscreen)
    $visible = @($qualified | Where-Object { -not $_.Offscreen })
    if ($visible.Count -eq 1) { return $visible[0] }
    if ($qualified.Count -eq 1) { return $qualified[0] }
    if ($qualified.Count -gt 1) { return $null }
    $candidates = @{}
    foreach ($heading in @($controls | Where-Object { Test-LDLCChromeBrowserDefaultLabel -Name $_.Name })) {
        $parent = $heading.Element
        for ($depth = 0; $parent -and $depth -lt 8; $depth++) {
            if (Test-LDLCDefaultAppsSameElement $parent $Root) { break }
            $children = @(Get-LDLCDefaultAppsControls $parent)
            # Scope the button to the browser heading, never the PDF card or chooser.
            if (@($children | Where-Object { $_.Name -match '^\.[a-z0-9]+(?:\s|,|:)' }).Count) { break }
            $buttons = @{}
            $hasActionLabel = $false
            foreach ($child in $children) {
                if ((Convert-LDLCDefaultAppsComparableText $child.Name) -notmatch '^(definir par defaut|set default|set as default)$') { continue }
                $hasActionLabel = $true
                $button = $child
                if ($child.ControlType -eq 'ControlType.Text') {
                    # XAML can put the label inside an otherwise unnamed Button.
                    $element = Resolve-LDLCDefaultAppsChoiceElement -Element $child.Element -Root $parent
                    if (-not $element -or $element.Current.ControlType.ProgrammaticName -ne 'ControlType.Button') { continue }
                    $button = [pscustomobject]@{ Element = $element; Name = $child.Name; AutomationId = $element.Current.AutomationId;
                        ControlType = 'ControlType.Button'; Enabled = $element.Current.IsEnabled; Offscreen = $element.Current.IsOffscreen }
                }
                if ($button.ControlType -eq 'ControlType.Button' -and $button.Enabled) {
                    $buttons[($button.Element.GetRuntimeId() -join '.')] = $button
                }
            }
            if ($hasActionLabel) {
                foreach ($key in $buttons.Keys) { $candidates[$key] = $buttons[$key] }
                break
            }
            $parent = Get-LDLCDefaultAppsParentElement $parent
        }
    }
    $visible = @($candidates.Values | Where-Object { -not $_.Offscreen })
    if ($visible.Count -eq 1) { return $visible[0] }
    if ($candidates.Count -eq 1) { return @($candidates.Values)[0] }
    return $null
}

function Test-LDLCDefaultAppsApplicationName {
    param([string]$Name, [ValidateSet('Chrome', 'Adobe')][string]$Application, [switch]$RegisteredName)
    $name = Convert-LDLCDefaultAppsComparableText $Name
    $brand = if ($Application -eq 'Chrome') { 'google chrome' }
        else { '(?:adobe (?:acrobat(?: reader)?|reader)|acrobat(?: reader)?)' }
    # Registry names may contain edition/version suffixes. Picker names remain anchored
    # so a Store/search/help command containing the brand cannot be selected as an app.
    if ($RegisteredName) { return ($name -match ('(?<![a-z0-9])' + $brand + '(?![a-z0-9])')) }
    $suffix = if ($Application -eq 'Adobe') { '(?: dc)?' } else { '' }
    return ($name -match ('^' + $brand + $suffix + '(?:\s*\([^)]*\))?$'))
}

function Get-LDLCDefaultAppsVisibleChoice {
    param([string]$Association, [ValidateSet('Chrome', 'Adobe')][string]$Application)
    Ensure-LDLCDefaultAppsUiAutomation
    foreach ($window in @(Get-LDLCDefaultAppsWindows | Sort-Object IsSettings)) {
        try {
            $root = Get-LDLCDefaultAppsPickerRoot -Window $window -Root (Get-LDLCDefaultAppsRoot $window) -Association $Association
            if (-not $root) { continue }
            $control = Select-LDLCDefaultAppsControl -Controls @(Get-LDLCDefaultAppsControls $root) -Kind Choice -Application $Application
            if ($control -and -not $control.Offscreen) { return $control }
        }
        catch { if (Test-LDLCStopRequestError $_) { throw } }
    }
    return $null
}

function Get-LDLCDefaultAppAttemptRoutes {
    param([ValidateSet('Chrome', 'Adobe')][string]$Application, $State)
    # Reuse a selector already showing the requested app before navigating away from it.
    $pickerAssociation = if ($Application -eq 'Chrome') { '.html' } else { '.pdf' }
    if ($pickerAssociation -in $State.Missing -and (Get-LDLCDefaultAppsVisibleChoice -Association $pickerAssociation -Application $Application)) {
        [pscustomobject]@{ Kind = 'Picker'; Uri = ''; Association = $pickerAssociation }
    }
    foreach ($uri in @(Get-LDLCDefaultAppUris -Application $Application | Select-Object -Unique)) {
        [pscustomobject]@{ Kind = 'RegisteredPage'; Uri = $uri; Association = '' }
    }
}

function Invoke-LDLCDefaultAppsControl {
    param($Control, [ValidateSet('Association', 'Choice', 'Confirm', 'BrowserDefault')][string]$Kind)
    $element = $Control.Element
    if ($Control.Offscreen) {
        $scroll = $null
        if ($element.TryGetCurrentPattern([System.Windows.Automation.ScrollItemPattern]::Pattern, [ref]$scroll)) {
            $scroll.ScrollIntoView()
        }
        return $false # Reacquire after scrolling; coordinates and cached rectangles are never used.
    }
    if (-not $element.Current.IsEnabled -or $element.Current.IsOffscreen) { return $false }
    if ($Kind -eq 'BrowserDefault') {
        # The global browser button is an action, not an OpenWith picker row.
        # UIA Invoke also works when the Settings hit-test reports its XAML parent.
        $invoke = $null
        try {
            if ($element.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$invoke)) {
                $invoke.Invoke()
                Write-Info '[DEFAULT-APPS] Bouton navigateur Chrome active par Windows UIA.'
                return $true
            }
        }
        catch { Write-Info ('[DEFAULT-APPS] Activation UIA indisponible, tentative de clic observe : ' + $_.Exception.Message) }
        return (Invoke-LDLCDefaultAppsObservedClick -Control $Control)
    }
    # Preserve the pre-compact UI behavior: XAML Invoke can return without opening
    # the picker, and SelectionItem.Select alone may not commit an app choice.
    if (Invoke-LDLCDefaultAppsObservedClick -Control $Control) { return $true }
    $pattern = $null
    if ($element.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$pattern)) {
        $pattern.Invoke()
        return $true
    }
    if ($Kind -eq 'Choice' -and $element.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$pattern)) {
        $pattern.Select()
        if (-not $pattern.Current.IsSelected) { throw "Ligne non selectionnee par Windows : $($Control.Name)" }
        return $true
    }
    throw "Controle UIA sans pattern Invoke/SelectionItem : $($Control.Name)"
}

function Invoke-LDLCDefaultAppsObservedClick {
    param($Control)
    if ($Control.Element -isnot [System.Windows.Automation.AutomationElement]) { return $false }
    if ($script:LDLCDefaultAppsCompactPath -and -not (Test-LDLCDefaultAppsCompactUiAck)) { return $false }
    Ensure-LDLCDefaultAppsNativeInterop
    Stop-IfRequested
    $element = $Control.Element
    $rect = $element.Current.BoundingRectangle
    if ($rect.IsEmpty -or $rect.Width -le 0 -or $rect.Height -le 0) { return $false }
    $point = New-Object LDLCDefaultAppsPoint
    $point.X = [int][math]::Round($rect.Left + $rect.Width / 2)
    $point.Y = [int][math]::Round($rect.Top + $rect.Height / 2)
    $handle = [LDLCDefaultAppsNative]::WindowFromPoint($point)
    $processId = [uint32]0
    [void][LDLCDefaultAppsNative]::GetWindowThreadProcessId($handle, [ref]$processId)
    $process = Get-Process -Id $processId -ErrorAction Stop
    if ($process.ProcessName -notin @('SystemSettings','ApplicationFrameHost','OpenWith','PickerHost','ShellExperienceHost','AppResolverUX')) {
        throw "Controle masque par une autre fenetre; aucun clic envoye : $($Control.Name)"
    }
    $hit = [System.Windows.Automation.AutomationElement]::FromPoint((New-Object Windows.Point $point.X,$point.Y))
    $matched = $false
    for ($depth = 0; $hit -and $depth -lt 8; $depth++) {
        if (Test-LDLCDefaultAppsSameElement $hit $element) { $matched = $true; break }
        $hit = Get-LDLCDefaultAppsParentElement $hit
    }
    if (-not $matched) {
        # OpenWith's UIA point provider can incorrectly report the Settings page
        # behind its XAML popup. Native hit-testing must still hit the exact UIA
        # process, and that process must own the foreground picker.
        $foregroundProcess = [uint32]0
        [void][LDLCDefaultAppsNative]::GetWindowThreadProcessId([LDLCDefaultAppsNative]::GetForegroundWindow(), [ref]$foregroundProcess)
        if (-not (Test-LDLCDefaultAppsNativePickerHit -ProcessName $process.ProcessName -HitProcessId $processId -TargetProcessId $element.Current.ProcessId -ForegroundProcessId $foregroundProcess)) {
            throw "Cible UIA non confirmee sous la souris; aucun clic envoye : $($Control.Name)"
        }
    }
    [LDLCDefaultAppsNative]::ClickAt($point.X, $point.Y)
    Write-Info "[DEFAULT-APPS] Clic sur controle Windows observe : $($Control.Name)"
    return $true
}

function Test-LDLCDefaultAppsNativePickerHit {
    param([string]$ProcessName, [uint32]$HitProcessId, [uint32]$TargetProcessId, [uint32]$ForegroundProcessId)
    return ($ProcessName -eq 'OpenWith' -and $HitProcessId -ne 0 -and $HitProcessId -eq $TargetProcessId -and $HitProcessId -eq $ForegroundProcessId)
}

function Move-LDLCDefaultAppsScroll {
    param($Root, [switch]$Reset)
    $elements = $Root.FindAll([System.Windows.Automation.TreeScope]::Descendants,
        (New-Object System.Windows.Automation.PropertyCondition ([System.Windows.Automation.AutomationElement]::IsScrollPatternAvailableProperty), $true))
    foreach ($element in $elements) {
        $pattern = $null
        if ($element.TryGetCurrentPattern([System.Windows.Automation.ScrollPattern]::Pattern, [ref]$pattern) -and $pattern.Current.VerticallyScrollable) {
            if ($Reset) { $pattern.SetScrollPercent(-1, 0) }
            else { $pattern.Scroll([System.Windows.Automation.ScrollAmount]::NoAmount, [System.Windows.Automation.ScrollAmount]::LargeIncrement) }
            return $true
        }
    }
    return $false
}

function Invoke-LDLCDefaultAppsUiAction {
    param([ValidateSet('Association', 'Choice', 'Confirm', 'BrowserDefault')][string]$Kind, [string]$Association,
        [ValidateSet('Chrome', 'Adobe')][string]$Application, [int]$TimeoutMilliseconds = 15000, [switch]$ObservedBrowserClick)
    $tracking = @{ Error = ''; Scrolls = 0; Seen = '' }
    $result = Wait-LDLCDefaultAppsCondition -TimeoutMilliseconds $TimeoutMilliseconds -Probe {
        try {
            $windows = @(Get-LDLCDefaultAppsWindows | Sort-Object IsSettings)
            foreach ($window in $windows) {
                if ($Kind -in @('Association', 'BrowserDefault') -and -not $window.IsSettings) { continue }
                $root = Get-LDLCDefaultAppsRoot -Window $window
                if ($Kind -in @('Association', 'BrowserDefault')) { [void](Set-LDLCDefaultAppsFocus $window) }
                $pageRoot = $root
                if ($Kind -notin @('Association', 'BrowserDefault')) {
                    $root = Get-LDLCDefaultAppsPickerRoot -Window $window -Root $root -Association $Association
                    if (-not $root) {
                        $tracking.Seen = @((Get-LDLCDefaultAppsControls $pageRoot) | Where-Object { $_.Name -match 'acrobat|adobe|chrome|pdf|html|defaut|default|choisi|select' } | Select-Object -First 18 |
                            ForEach-Object { "$($_.ControlType):$($_.Name)" }) -join ' | '
                        continue
                    }
                }
                # Do not reactivate the Settings owner while its picker is open.
                # The scoped row is clicked only after native/UIA hit checks;
                # otherwise Invoke/Select remains available without global input.
                $controls = @(Get-LDLCDefaultAppsControls -Root $root)
                $tracking.Seen = @($controls | Where-Object { $_.Name -match 'acrobat|adobe|chrome|pdf|html|defaut|default|choisi|select' } | Select-Object -First 18 |
                    ForEach-Object { "$($_.ControlType):$($_.Name)" }) -join ' | '
                $control = if ($Kind -eq 'BrowserDefault') { Get-LDLCChromeBrowserDefaultControl -Root $root }
                    else { Select-LDLCDefaultAppsControl -Controls $controls -Kind $Kind -Association $Association -Application $Application }
                if ($control) {
                    $activated = if ($Kind -eq 'BrowserDefault' -and $ObservedBrowserClick) {
                        if ($control.Offscreen -or -not $control.Element.Current.IsEnabled -or $control.Element.Current.IsOffscreen) { $false }
                        else { Invoke-LDLCDefaultAppsObservedClick -Control $control }
                    }
                        else { Invoke-LDLCDefaultAppsControl -Control $control -Kind $Kind }
                    if ($activated) { return $true }
                    if ($Kind -ne 'BrowserDefault') { return $false }
                }
                if ($Kind -eq 'BrowserDefault' -and $tracking.Scrolls -lt 3) {
                    [void](Move-LDLCDefaultAppsScroll -Root $root -Reset)
                    $tracking.Scrolls++
                }
                elseif ($Kind -ne 'Confirm' -and $Kind -ne 'BrowserDefault' -and $tracking.Scrolls -lt 16) {
                    [void](Move-LDLCDefaultAppsScroll -Root $root)
                    $tracking.Scrolls++
                }
            }
        }
        catch {
            if (Test-LDLCStopRequestError $_) { throw }
            $tracking.Error = $_.Exception.Message
        }
        return $false
    }
    if (-not $result) { throw "Controle $Kind introuvable/inactif pour $Application $Association apres ${TimeoutMilliseconds}ms. $($tracking.Error). UIA : $($tracking.Seen)" }
    return $true
}

function Open-LDLCDefaultAppPage {
    param([string]$Uri, [ValidateSet('Chrome', 'Adobe')][string]$Application)
    Ensure-LDLCDefaultAppsUiAutomation
    Close-LDLCDefaultAppsPage -ExistingDefaultPage
    Start-Process -FilePath $Uri -ErrorAction Stop
    $tracking = @{ Seen = '' }
    $ready = Wait-LDLCDefaultAppsCondition -TimeoutMilliseconds 20000 -Probe {
        try {
            foreach ($window in @(Get-LDLCDefaultAppsWindows | Where-Object IsSettings)) {
                [void](Set-LDLCDefaultAppsFocus $window)
                $root = Get-LDLCDefaultAppsRoot $window
                $controls = @(Get-LDLCDefaultAppsControls $root)
                $tracking.Seen = @($controls | Where-Object { $_.Name -match 'acrobat|adobe|chrome|pdf|html|defaut|default|choisi|select' } | Select-Object -First 18 |
                    ForEach-Object { "$($_.ControlType):$($_.Name)" }) -join ' | '
                $page = Select-LDLCDefaultAppsControl -Controls $controls -Kind Page -Application $Application
                if ($page) { $script:LDLCDefaultAppsOwnedPage = $window; [void](Move-LDLCDefaultAppsScroll -Root $root -Reset); return $true }
            }
        }
        catch { if (Test-LDLCStopRequestError $_) { throw } }
        return $false
    }
    if (-not $ready) { throw "Fiche $Application non exposee par UIA apres 20s (URI non prise en charge, focus ou Parametres lents) : $Uri. UIA : $($tracking.Seen)" }
}

function Close-LDLCDefaultAppsPage {
    param([switch]$ExistingDefaultPage)
    $owned = $script:LDLCDefaultAppsOwnedPage
    $script:LDLCDefaultAppsOwnedPage = $null
    if (-not $owned -and -not $ExistingDefaultPage) { return }
    foreach ($window in @(Get-LDLCDefaultAppsWindows | Where-Object IsSettings)) {
        try {
            if ($owned -and ($window.Handle -ne $owned.Handle -or $window.ProcessId -ne $owned.ProcessId)) { continue }
            if (-not $owned) {
                $controls = @(Get-LDLCDefaultAppsControls (Get-LDLCDefaultAppsRoot $window))
                $page = (Select-LDLCDefaultAppsControl $controls Page -Application Adobe) -or (Select-LDLCDefaultAppsControl $controls Page -Application Chrome)
                if (-not $page) { continue }
            }
            [void][LDLCDefaultAppsNative]::PostMessage($window.Handle, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
            Start-Sleep -Milliseconds 700
        } catch { Write-Info "[DEFAULT-APPS] Fermeture de la fiche non confirmee : $($_.Exception.Message)" }
    }
}

function Complete-LDLCDefaultAppsChoice {
    param([string]$Association, [ValidateSet('Chrome', 'Adobe')][string]$Application, [int]$TimeoutMilliseconds = 12000)
    $tracking = @{ LastConfirmation = ''; Actions = @{}; Count = 0; UiError = ''; Seen = '' }
    $confirmed = Wait-LDLCDefaultAppsCondition -TimeoutMilliseconds $TimeoutMilliseconds -Probe {
        if (Test-LDLCEffectiveAssociationTarget -State (Get-LDLCEffectiveAssociation $Association) -Application $Application) { return $true }
        try {
            foreach ($window in @(Get-LDLCDefaultAppsWindows | Sort-Object IsSettings)) {
                $root = Get-LDLCDefaultAppsPickerRoot -Window $window -Root (Get-LDLCDefaultAppsRoot $window) -Association $Association
                if (-not $root) { $tracking.UiError = 'Dialogue de confirmation non expose/scoped par UIA'; continue }
                $controls = @(Get-LDLCDefaultAppsControls $root)
                $tracking.Seen = @($controls | Where-Object { $_.Name -match 'acrobat|adobe|chrome|pdf|defaut|default|toujours|always|choisi|select|^ok$' } |
                    Select-Object -First 15 | ForEach-Object { "$($_.ControlType):$($_.Name) [Enabled=$($_.Enabled), Offscreen=$($_.Offscreen)]" }) -join ' | '
                $button = Select-LDLCDefaultAppsControl -Controls $controls -Kind Confirm -Application $Application
                if ($button -and $tracking.Count -lt 3) {
                    $identity = "$($window.Handle):$($button.Element.GetRuntimeId() -join '.'):$($button.Name)"
                    if ($tracking.Actions.ContainsKey($identity)) { continue }
                    if (Invoke-LDLCDefaultAppsControl -Control $button -Kind Confirm) {
                        $tracking.LastConfirmation = $button.Name
                        $tracking.Actions[$identity] = $true
                        $tracking.Count++
                        Set-LDLCDefaultAppsActionProgress -Application $Application -Association $Association -Stage Confirming
                    }
                }
            }
        }
        catch { if (Test-LDLCStopRequestError $_) { throw }; $tracking.UiError = $_.Exception.Message }
        return $false
    }
    if (-not $confirmed) { throw "Association $Association non appliquee par Windows apres selection $Application (confirmation='$($tracking.LastConfirmation)'). UIA : $($tracking.UiError). Controles observes : $($tracking.Seen)." }
}

function Invoke-LDLCChromeBrowserDefaultAction {
    # Restore UIA Invoke first: the guarded physical click can be unavailable
    # even when Windows exposes a working, accessible Set default action.
    [void](Invoke-LDLCDefaultAppsUiAction -Kind BrowserDefault -Application Chrome -TimeoutMilliseconds 5000)
    $verification = Wait-LDLCDefaultAppConfirmation -Application Chrome -TimeoutMilliseconds 750
    if (-not $verification.Confirmed) {
        try { [void](Invoke-LDLCDefaultAppsUiAction -Kind BrowserDefault -Application Chrome -TimeoutMilliseconds 1000 -ObservedBrowserClick) }
        catch { if (Test-LDLCStopRequestError $_) { throw }; Write-Info '[DEFAULT-APPS] Clic observe indisponible ; verification du resultat Windows.' }
        $verification = Wait-LDLCDefaultAppConfirmation -Application Chrome -TimeoutMilliseconds 1000
    }
    return [pscustomobject]@{ BrowserActionInvoked = $true; Confirmed = $verification.Confirmed }
}

function Invoke-LDLCDefaultAppAttempt {
    param([ValidateSet('Chrome', 'Adobe')][string]$Application, $State, [int]$Attempt, $Route)
    if (-not $Route) {
        $routes = @(Get-LDLCDefaultAppAttemptRoutes -Application $Application -State $State)
        if ($Attempt -lt 1 -or $Attempt -gt $routes.Count) { throw "Aucune nouvelle voie UIA disponible pour $Application." }
        $Route = $routes[$Attempt - 1]
    }
    if ($Application -eq 'Chrome' -and $Route.Kind -ne 'Picker') {
        # Windows 11's browser-wide action first; do not spend time in the HTML
        # chooser before attempting the exact "Set default" browser button.
        try {
            Set-LDLCDefaultAppsActionProgress -Application Chrome -Association 'navigateur' -Stage Opening
            Open-LDLCDefaultAppPage -Uri $Route.Uri -Application Chrome
            Set-LDLCDefaultAppsActionProgress -Application Chrome -Association 'navigateur par defaut' -Stage Validating
            $browserAction = Invoke-LDLCChromeBrowserDefaultAction
            if ($browserAction.Confirmed) { return $browserAction }
            Write-Info '[DEFAULT-APPS] Bouton transmis sans changement effectif ; utilisation des associations Windows enregistrees.'
        }
        catch {
            if (Test-LDLCStopRequestError $_) { throw }
            if ((Get-LDLCDefaultAppState Chrome).Confirmed) { return }
            Write-Info ('[DEFAULT-APPS] Action navigateur non disponible ; essai du selecteur HTML enregistre : ' + $_.Exception.Message)
        }
    }
    # Windows 10 and older Windows 11 pages may not have a browser-wide button.
    # HTML alone does not configure HTTP, HTTPS and HTM.
    $associations = @($State.Missing)
    foreach ($association in $associations) {
        Stop-IfRequested
        # Recheck before acting: an earlier choice may have changed several associations.
        if (Test-LDLCEffectiveAssociationTarget -State (Get-LDLCEffectiveAssociation $association) -Application $Application) { continue }
        $stage = 'Page'
        try {
            if ($Route.Kind -ne 'Picker') {
                Set-LDLCDefaultAppsActionProgress -Application $Application -Association $association -Stage Opening
                Open-LDLCDefaultAppPage -Uri $Route.Uri -Application $Application
                $stage = 'Association'
                [void](Invoke-LDLCDefaultAppsUiAction -Kind Association -Association $association -Application $Application)
            }
            $stage = 'Choice'
            Set-LDLCDefaultAppsActionProgress -Application $Application -Association $association -Stage Selecting
            [void](Invoke-LDLCDefaultAppsUiAction -Kind Choice -Association $association -Application $Application)
            $stage = 'Confirm'
            Set-LDLCDefaultAppsActionProgress -Application $Application -Association $association -Stage Validating
            if ($Application -eq 'Chrome') {
                Complete-LDLCDefaultAppsChoice -Association $association -Application Chrome -TimeoutMilliseconds 1500
            } else { Complete-LDLCDefaultAppsChoice -Association $association -Application $Application }
        }
        catch {
            $_.Exception.Data['DefaultAppsStage'] = $stage
            throw
        }
    }
    if ($Application -eq 'Chrome') {
        if ((Get-LDLCDefaultAppState Chrome).Confirmed) { return [pscustomobject]@{ BrowserActionInvoked=$false; Confirmed=$true } }
        try {
            $uri = $Route.Uri
            if (-not $uri) { $uri = Get-LDLCDefaultAppUris Chrome | Select-Object -First 1 }
            if (-not $uri) { throw 'Fiche Google Chrome enregistree absente pour le bouton navigateur par defaut.' }
            Set-LDLCDefaultAppsActionProgress -Application Chrome -Association 'navigateur' -Stage Opening
            Open-LDLCDefaultAppPage -Uri $uri -Application Chrome
            Set-LDLCDefaultAppsActionProgress -Application Chrome -Association 'navigateur par defaut' -Stage Validating
            $action = Invoke-LDLCChromeBrowserDefaultAction
            return $action
        }
        catch {
            $_.Exception.Data['DefaultAppsStage'] = 'BrowserDefault'
            throw
        }
    }
}

function Test-LDLCDefaultAppsCompactUiAck {
    if (-not $script:LDLCDefaultAppsCompactPath -or -not $script:LDLCDefaultAppsCompactProgress) { return $false }
    try {
        $ack = [IO.File]::ReadAllText($script:LDLCDefaultAppsCompactPath + '.ack') | ConvertFrom-Json -ErrorAction Stop
        return ($ack.WorkerId -eq $PID -and $ack.Revision -eq $script:LDLCDefaultAppsCompactProgress.Revision)
    }
    catch { return $false }
}

function Set-LDLCDefaultAppsActionProgress {
    param([ValidateSet('Chrome', 'Adobe')][string]$Application, [string]$Association,
        [ValidateSet('Opening', 'Selecting', 'Validating', 'Confirming')][string]$Stage)
    $name = if ($Application -eq 'Adobe') { 'Adobe Acrobat Reader' } else { 'Chrome' }
    $action = switch ($Stage) {
        Opening { 'Ouverture des reglages' }
        Selecting { 'Selection' }
        Validating { 'Validation du choix' }
        Confirming { 'Confirmation du resultat' }
    }
    $suffix = if ($Association) { " ($Association)" } else { '' }
    $percent = 0; $failed = ''
    if ($script:LDLCDefaultAppsCompactProgress) {
        $percent = [int]$script:LDLCDefaultAppsCompactProgress.Progress
        $failed = [string]$script:LDLCDefaultAppsCompactProgress.ErrorApplication
    }
    Set-LDLCDefaultAppsCompactProgress -Percent $percent -Message "${action} : ${name}${suffix}..." -ErrorApplication $failed
}

function Set-LDLCDefaultAppsCompactProgress {
    param([ValidateRange(0,100)][int]$Percent, [string]$Message, [bool]$Running = $true,
        [bool]$Success = $false, [string]$ErrorApplication = '')
    if ($Percent -eq 100 -and -not $Success) { throw '100 pour cent exige le traitement termine sans erreur.' }
    $previous = $script:LDLCDefaultAppsCompactProgress
    if ($previous -and $previous.Progress -eq $Percent -and $previous.Message -eq $Message -and
        $previous.Running -eq $Running -and $previous.Success -eq $Success -and $previous.ErrorApplication -eq $ErrorApplication -and
        (-not $script:LDLCDefaultAppsCompactPath -or (Test-LDLCDefaultAppsCompactUiAck))) { return }
    $script:LDLCDefaultAppsCompactRevision = [long]$script:LDLCDefaultAppsCompactRevision + 1
    $script:LDLCDefaultAppsCompactProgress = [pscustomobject]@{
        WorkerId = $PID; Active = $true; Progress = $Percent; Message = $Message
        Running = $Running; Success = $Success; ErrorApplication = $ErrorApplication; Revision = $script:LDLCDefaultAppsCompactRevision
    }
    if (-not $script:LDLCDefaultAppsCompactPath) { return }
    $path = $script:LDLCDefaultAppsCompactPath
    $temporary = $path + '.tmp'
    try {
        [IO.File]::WriteAllText($temporary, ($script:LDLCDefaultAppsCompactProgress | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding($false)))
        for ($retry = 0; $retry -lt 6; $retry++) {
            try {
                if (Test-Path -LiteralPath $path) { [IO.File]::Replace($temporary, $path, [NullString]::Value) }
                else { [IO.File]::Move($temporary, $path) }
                break
            }
            catch [IO.IOException] {
                if ($retry -eq 5) { throw }
                Start-Sleep -Milliseconds 25
            }
        }
    }
    catch { Write-Info "[DEFAULT-APPS] Signal de progression indisponible : $($_.Exception.Message)" }
    finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue } }
    if ($env:LDLC_DEFAULT_APPS_UI -eq '1') {
        # Wait for this exact message to be painted, not an old 'window visible' flag.
        $ack = Wait-LDLCDefaultAppsCondition -TimeoutMilliseconds 2500 -PollMilliseconds 50 -Probe { Test-LDLCDefaultAppsCompactUiAck }
        if ($ack) { Write-Info "[DEFAULT-APPS][UI] Affichage confirme r$($script:LDLCDefaultAppsCompactRevision) : $Percent% $Message" }
        else { Write-Info "[DEFAULT-APPS][UI] Message non acquitte r$($script:LDLCDefaultAppsCompactRevision); clic physique desactive : $Message" }
    }
}

function Enter-LDLCDefaultAppsCompact {
    if ($script:LDLCDefaultAppsCompactDepth -gt 0) { $script:LDLCDefaultAppsCompactDepth++; return }
    $script:LDLCDefaultAppsCompactDepth = 1
    $script:LDLCDefaultAppsCompactPath = $null
    $script:LDLCDefaultAppsCompactProgress = $null
    if ([string]::IsNullOrWhiteSpace($script:ProgressFile)) { return }
    $path = Join-Path (Split-Path -Parent $script:ProgressFile) "LDLC_DEFAULT_APPS.$PID.json"
    $script:LDLCDefaultAppsCompactPath = $path
    try {
        Remove-Item -LiteralPath ($path + '.ack') -Force -ErrorAction SilentlyContinue
        Set-LDLCDefaultAppsCompactProgress -Percent 0 -Message "Configuration d'Adobe Acrobat Reader..."
    }
    catch {
        if (Test-LDLCStopRequestError $_) { throw }
        Write-Info "[DEFAULT-APPS] Signal UI compacte indisponible : $($_.Exception.Message)"
    }
}

function Exit-LDLCDefaultAppsCompact {
    $script:LDLCDefaultAppsCompactDepth = [math]::Max(0, $script:LDLCDefaultAppsCompactDepth - 1)
    if ($script:LDLCDefaultAppsCompactDepth -gt 0) { return }
    if ($script:LDLCDefaultAppsCompactPath) {
        Remove-Item -LiteralPath $script:LDLCDefaultAppsCompactPath -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath ($script:LDLCDefaultAppsCompactPath + '.ack') -Force -ErrorAction SilentlyContinue
        $script:LDLCDefaultAppsCompactPath = $null
    }
}

function Invoke-LDLCDefaultAppConfiguration {
    param([ValidateSet('Chrome', 'Adobe')][string]$Application, [ValidateRange(1, 3)][int]$MaxAttempts = 3, [switch]$DeferFailureWarning)
    if ($Application -eq 'Chrome') { return Set-LDLCChromeDefaultBrowserWithUiAutomation -MaxAttempts $MaxAttempts -DeferFailureWarning:$DeferFailureWarning }
    $errors = New-Object 'Collections.Generic.List[string]'
    $verification = $null
    $attempt = 0
    $entered = $false
    try {
        Stop-IfRequested
        if ((Get-LDLCDefaultAppState -Application $Application).Confirmed) {
            $verification = Wait-LDLCDefaultAppConfirmation -Application $Application -TimeoutMilliseconds 1000
            if ($verification.Confirmed) {
                Write-Ok "[DEFAULT-APPS] $Application deja confirme par Windows ; aucune action necessaire."
                return $true
            }
        }
        $entered = $true
        Enter-LDLCDefaultAppsCompact
        Set-LDLCDefaultAppsActionProgress -Application $Application -Stage Confirming
        Write-Step "[DEFAULT-APPS] Verification effective $Application, puis correction si necessaire."
        $state = Get-LDLCDefaultAppState -Application $Application
        $routes = @()
        if (-not $state.Confirmed) { $routes = @(Get-LDLCDefaultAppAttemptRoutes -Application $Application -State $state | Select-Object -First $MaxAttempts) }
        if (-not $state.Confirmed -and -not $routes.Count) {
            $errors.Add('Aucun selecteur present ni fiche RegisteredApplications compatible. Verifier installation/integration Windows.')
        }
        do {
            Stop-IfRequested
            $state = Get-LDLCDefaultAppState -Application $Application
            $stage = ''
            $actionResult = $null
            if (-not $state.Confirmed -and $attempt -lt $routes.Count) {
                $route = $routes[$attempt]
                $attempt++
                try { $actionResult = Invoke-LDLCDefaultAppAttempt -Application $Application -State $state -Attempt $attempt -Route $route }
                catch {
                    if (Test-LDLCStopRequestError $_) { throw }
                    $stage = [string]$_.Exception.Data['DefaultAppsStage']
                    $errors.Add("Tentative ${attempt} ($($route.Kind) $($route.Uri), etape=$stage): $($_.Exception.Message)")
                }
            }
            Set-LDLCDefaultAppsActionProgress -Application $Application -Stage Confirming
            $confirmationBudget = if ($Application -eq 'Chrome') { 6000 } else { 12000 }
            $verification = Wait-LDLCDefaultAppConfirmation -Application $Application -TimeoutMilliseconds $confirmationBudget
            if ($verification.Confirmed) {
                Write-Ok "[DEFAULT-APPS] $Application confirme par Windows : $($verification.State.Associations.Association -join ', ')."
                return $true
            }
            $before = @($state.Associations | ForEach-Object { "$($_.Association)|$($_.ProgId)|$($_.Executable)|$($_.Error)" }) -join ';'
            $after = @($verification.State.Associations | ForEach-Object { "$($_.Association)|$($_.ProgId)|$($_.Executable)|$($_.Error)" }) -join ';'
            if ($before -eq $after -and ($stage -in @('Association', 'Choice', 'Confirm', 'BrowserDefault') -or ($Application -eq 'Chrome' -and $actionResult.BrowserActionInvoked))) {
                $errors.Add("Arret sans repetition : etape $stage en echec, associations inchangees apres stabilisation.")
                break
            }
            if ($attempt -lt $routes.Count) { Write-Info "[DEFAULT-APPS] $Application non confirme; autre voie enregistree $($attempt + 1)/$($routes.Count), sans reutiliser la precedente." }
        } while ($attempt -lt $routes.Count)
        $details = @($verification.State.Associations | ForEach-Object {
            "$($_.Association)=$($_.ProgId) [$($_.Executable)] erreur='$($_.Error)'"
        }) -join '; '
        $failure = "[DEFAULT-APPS] $Application non confirme apres $attempt tentative(s) distincte(s). Manquants : $($verification.State.Missing -join ', '). $details. $($errors -join ' | '). Corriger dans Parametres > Applications > Applications par defaut."
        Set-LDLCDefaultAppsDeferredDetail -Application $Application -Detail $failure
        if ($DeferFailureWarning) { Write-Info $failure } else { Write-Warn $failure }
        return $false
    }
    catch {
        if (Test-LDLCStopRequestError $_) { throw }
        $failure = "[DEFAULT-APPS] Verification $Application interrompue, resultat non confirme : $($_.Exception.Message). Controle manuel necessaire."
        Set-LDLCDefaultAppsDeferredDetail -Application $Application -Detail $failure
        if ($DeferFailureWarning) { Write-Info $failure } else { Write-Warn $failure }
        return $false
    }
    finally { if ($entered) { Close-LDLCDefaultAppsPage; Exit-LDLCDefaultAppsCompact } }
}

function Set-LDLCChromeDefaultBrowserWithUiAutomation {
    param([switch]$DeferFailureWarning, [ValidateRange(1,3)][int]$MaxAttempts=3)
    Stop-IfRequested
    $entered = $false
    try {
        $state = Get-LDLCDefaultAppState Chrome
        if ($state.Confirmed) { Write-Info 'Chrome deja selectionne ; aucune action necessaire.'; return $true }
        Enter-LDLCDefaultAppsCompact; $entered = $true
        $routes = @(Get-LDLCDefaultAppAttemptRoutes -Application Chrome -State $state | Select-Object -First $MaxAttempts)
        $errors = @(); $attempt = 0
        foreach ($route in $routes) {
            Stop-IfRequested; $attempt++
            try {
                [void](Invoke-LDLCDefaultAppAttempt -Application Chrome -State $state -Attempt $attempt -Route $route)
                $state=Get-LDLCDefaultAppState Chrome
                if ($state.Confirmed) { Write-Info 'Chrome defini comme navigateur par defaut par Windows.'; return $true }
                $errors += ('Windows n a pas applique Chrome pour : ' + ($state.Missing -join ', '))
                break
            } catch {
                if (Test-LDLCStopRequestError $_) { throw }
                $errors += $_.Exception.Message
                if ($_.Exception.Data['DefaultAppsStage'] -in @('Choice','Confirm','BrowserDefault')) { break }
            }
        }
        if (-not $routes.Count) { $errors += 'Aucune fiche Chrome ni aucun selecteur compatible.' }
        $failure='Chrome non defini par defaut : ' + ($errors -join ' | ') + '. Verifier Parametres > Applications > Applications par defaut.'
        Set-LDLCDefaultAppsDeferredDetail -Application Chrome -Detail $failure
        if ($DeferFailureWarning) { Write-Info $failure } else { Write-Warn $failure }
        return $false
    } catch {
        if (Test-LDLCStopRequestError $_) { throw }
        $failure='Configuration Chrome interrompue : ' + $_.Exception.Message
        Set-LDLCDefaultAppsDeferredDetail -Application Chrome -Detail $failure
        if ($DeferFailureWarning) { Write-Info $failure } else { Write-Warn $failure }
        return $false
    } finally { if ($entered) { Close-LDLCDefaultAppsPage; Exit-LDLCDefaultAppsCompact } }
}

function Set-LDLCAdobePdfDefaultWithUiAutomation {
    param([switch]$DeferFailureWarning)
    return Invoke-LDLCDefaultAppConfiguration -Application Adobe -DeferFailureWarning:$DeferFailureWarning
}

function Get-LDLCTaskbarAdvancedValue {
    param([Parameter(Mandatory = $true)][string]$Name)

    $path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    try {
        $item = Get-ItemProperty -Path $path -Name $Name -ErrorAction Stop
        return [int]$item.$Name
    }
    catch {
        return $null
    }
}

function Set-LDLCTaskbarAdvancedValue {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][int]$Value
    )

    $path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    if (-not (Test-Path -LiteralPath $path)) {
        New-Item -Path $path -Force -ErrorAction Stop | Out-Null
    }
    New-ItemProperty -Path $path -Name $Name -Value $Value -PropertyType DWord -Force -ErrorAction Stop | Out-Null
}

function Get-LDLCTaskbarPolicyValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name
    )

    try {
        $item = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
        return [int]$item.$Name
    }
    catch {
        return $null
    }
}

function Set-LDLCTaskbarPolicyValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][int]$Value
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
    }

    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType DWord -Force -ErrorAction Stop | Out-Null
}

function Get-LDLCWindowsBuildNumber {
    try { return [int](Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name CurrentBuildNumber -ErrorAction Stop).CurrentBuildNumber }
    catch { return [Environment]::OSVersion.Version.Build }
}

function Get-LDLCWidgetsComponentPresence {
    # Read the current Windows user's installed packages only. An unavailable or
    # failed Appx query is unknown, never evidence that Widgets were removed.
    if (-not (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue)) { return 'Unknown' }
    try {
        $packages = @(Get-AppxPackage -ErrorAction Stop)
        $widgets = @($packages | Where-Object { $_.Name -in @('MicrosoftWindows.Client.WebExperience', 'Microsoft.WidgetsPlatformRuntime') })
        if ($widgets.Count -gt 0) { return 'Present' }
        return 'Absent'
    } catch { return 'Unknown' }
}

function Get-LDLCWidgetsTaskbarState {
    $taskbarDa = Get-LDLCTaskbarAdvancedValue -Name 'TaskbarDa'
    $taskbarMn = Get-LDLCTaskbarAdvancedValue -Name 'TaskbarMn'
    $policyPaths = @(
        'HKCU:\Software\Policies\Microsoft\Dsh',
        'HKLM:\SOFTWARE\Policies\Microsoft\Dsh',
        'HKCU:\Software\Policies\Microsoft\Windows\Windows Feeds',
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds'
    )

    $policyValues = @{}
    foreach ($policyPath in $policyPaths) {
        foreach ($policyName in @('AllowNewsAndInterests', 'AllowWidgets', 'EnableFeeds')) {
            $policyValues["$policyPath\$policyName"] = Get-LDLCTaskbarPolicyValue -Path $policyPath -Name $policyName
        }
    }

    # Computer policies supported by the corresponding Windows feature. A zero
    # in an arbitrary legacy/guessed key is not proof that Widgets are disabled.
    $build = Get-LDLCWindowsBuildNumber
    $supportedPolicy = if ($build -ge 22000) { 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh\AllowNewsAndInterests' }
        elseif ($build -ge 19041) { 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds\EnableFeeds' } else { '' }
    $disabledByPolicy = ($supportedPolicy -and $null -ne $policyValues[$supportedPolicy] -and [int]$policyValues[$supportedPolicy] -eq 0)
    $disabledByUserValue = ($null -ne $taskbarDa -and [int]$taskbarDa -eq 0)
    $componentPresence = 'NotChecked'
    if ($build -ge 22000 -and -not $disabledByUserValue -and -not $disabledByPolicy) {
        $componentPresence = Get-LDLCWidgetsComponentPresence
    }
    $componentRemoved = ($componentPresence -eq 'Absent')

    return [pscustomobject]@{
        Disabled = [bool]($disabledByUserValue -or $disabledByPolicy -or $componentRemoved)
        TaskbarDa = $taskbarDa
        TaskbarMn = $taskbarMn
        PolicyDisabled = [bool]$disabledByPolicy
        PolicyValues = $policyValues
        SupportedPolicy = $supportedPolicy
        WindowsBuild = $build
        ComponentPresence = $componentPresence
        ComponentRemoved = $componentRemoved
    }
}

function Disable-LDLCTaskbarOption {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][string]$SuccessLog
    )

    $currentValue = Get-LDLCTaskbarAdvancedValue -Name $Name
    if ($null -ne $currentValue -and $currentValue -eq 0) {
        Write-Ok "$SuccessLog deja desactivee"
        return $false
    }

    Set-LDLCTaskbarAdvancedValue -Name $Name -Value 0
    Start-Sleep -Milliseconds 150

    $verifiedValue = Get-LDLCTaskbarAdvancedValue -Name $Name
    if ($null -eq $verifiedValue -or $verifiedValue -ne 0) {
        Write-Warn "[TASKBAR][ERREUR] Option $Label introuvable ou non verifiee"
        return $false
    }

    Write-Ok $SuccessLog
    return $true
}

function Disable-LDLCWidgetsTaskbarOption {
    param([switch]$DeferFailureWarning)
    if ($DeferFailureWarning -and $script:LDLCDefaultAppsPendingChecks) { $script:LDLCDefaultAppsPendingChecks['Widgets'] = $true }
    $initialState = Get-LDLCWidgetsTaskbarState
    if ($initialState.Disabled) {
        Write-Ok "[TASKBAR] Widgets deja desactives"
        return $false
    }

    $attemptErrors = New-Object System.Collections.Generic.List[string]

    try {
        Set-LDLCTaskbarAdvancedValue -Name 'TaskbarDa' -Value 0
        Start-Sleep -Milliseconds 150

        if ((Get-LDLCWidgetsTaskbarState).Disabled) {
            Write-Ok "[TASKBAR] Widgets desactives"
            return $true
        }
    }
    catch {
        [void]$attemptErrors.Add("TaskbarDa: $($_.Exception.Message)")
        Write-Info "[TASKBAR] Modification directe de Widgets non autorisee, tentative via strategie policy."
    }

    foreach ($policyPath in @(
        'HKCU:\Software\Policies\Microsoft\Dsh',
        'HKLM:\SOFTWARE\Policies\Microsoft\Dsh',
        'HKCU:\Software\Policies\Microsoft\Windows\Windows Feeds',
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds'
    )) {
        foreach ($policyName in @('AllowNewsAndInterests', 'AllowWidgets', 'EnableFeeds')) {
            try {
                Set-LDLCTaskbarPolicyValue -Path $policyPath -Name $policyName -Value 0
                Start-Sleep -Milliseconds 150

                if ((Get-LDLCWidgetsTaskbarState).Disabled) {
                    Write-Ok "[TASKBAR] Widgets desactives"
                    return $true
                }
            }
            catch {
                [void]$attemptErrors.Add("${policyPath}\${policyName}: $($_.Exception.Message)")
            }
            # A protected TaskbarDa must not turn a successful supported policy
            # write into an error attributed to that policy.
            try {
                Set-LDLCTaskbarAdvancedValue -Name 'TaskbarDa' -Value 0
                if ((Get-LDLCWidgetsTaskbarState).Disabled) { return $true }
            } catch { [void]$attemptErrors.Add("TaskbarDa: $($_.Exception.Message)") }
        }
    }

    $finalState = Get-LDLCWidgetsTaskbarState
    if ($finalState.Disabled) {
        Write-Ok "[TASKBAR] Widgets desactives apres verification finale"
        return $true
    }

    $details = (($attemptErrors | ForEach-Object { [string]$_ }) -join ' | ')
    if ([string]::IsNullOrWhiteSpace($details)) {
        $details = "TaskbarDa=$($finalState.TaskbarDa); PolicyDisabled=$($finalState.PolicyDisabled)"
    }

    $failure = "[TASKBAR][ERREUR] Impossible de desactiver Widgets apres verification finale. $details"
    Set-LDLCDefaultAppsDeferredDetail -Application Widgets -Detail $failure
    if ($DeferFailureWarning) { Write-Info $failure } else { Write-Warn $failure }
    return $false
}

function Set-LDLCTaskbarOptionsWithRegistry {
    param([switch]$DeferWidgetsFailureWarning)
    Write-Step "[TASKBAR] Configuration de la barre des taches"

    $changed = $false
    if (Disable-LDLCTaskbarOption -Name 'ShowTaskViewButton' -Label 'Vue des taches' -SuccessLog '[TASKBAR] Vue des taches desactivee') {
        $changed = $true
    }

    if (Disable-LDLCWidgetsTaskbarOption -DeferFailureWarning:$DeferWidgetsFailureWarning) {
        $changed = $true
    }

    if ($changed) {
        try {
            Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force -Confirm:$false -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 800
            Start-Process explorer
            Start-Sleep -Milliseconds 1400
            Close-LDLCExplorerFileWindows
            Write-Info "[TASKBAR] Explorer relance pour appliquer les options."
        }
        catch {
            Write-Warn "[TASKBAR] Relance Explorer impossible : $($_.Exception.Message)"
        }
    }

    $taskViewOk = ((Get-LDLCTaskbarAdvancedValue -Name 'ShowTaskViewButton') -eq 0)
    $widgetsOk = (Get-LDLCWidgetsTaskbarState).Disabled
    if ($taskViewOk -and $widgetsOk) {
        Write-Ok "[TASKBAR] Configuration de la barre des taches terminee"
        return $true
    }

    return $false
}

function Invoke-LDLCChromeDefaultAppsSequence {
    param([switch]$DeferFinalValidation)
    $script:LDLCDefaultAppsPendingChecks = @{ Adobe = $true; Chrome = $true }
    $script:LDLCDefaultAppsDeferredDetails = @{}
    $script:LDLCDefaultAppsFinalAuditDone = $false
    Write-Section 'APPLICATIONS PAR DEFAUT'
    try {
        Enter-LDLCDefaultAppsCompact
        $adobe = Set-LDLCAdobePdfDefaultWithUiAutomation -DeferFailureWarning
        Set-LDLCDefaultAppsCompactProgress -Percent $(if ($adobe) { 50 } else { 0 }) -Message 'Configuration de Chrome...'
        $chrome = Set-LDLCChromeDefaultBrowserWithUiAutomation -DeferFailureWarning
        if ($adobe -and $chrome) {
            Set-LDLCDefaultAppsCompactProgress -Percent 100 -Message 'Configuration terminee' -Running $false -Success $true
            Write-Info 'Applications par defaut configurees ; controle Windows termine.'
        } else {
            $failed = @(); if (-not $adobe) { $failed += 'Adobe Acrobat Reader (.pdf)' }; if (-not $chrome) { $failed += 'Chrome (HTTP/HTTPS/.htm/.html)' }
            Set-LDLCDefaultAppsCompactProgress -Percent (50 * ([int][bool]$adobe + [int][bool]$chrome)) -Message 'Reglage non effectue' -Running $false -ErrorApplication ($failed -join ' ; ')
        }
    } finally { Exit-LDLCDefaultAppsCompact }
    try { [void](Set-LDLCTaskbarOptionsWithRegistry -DeferWidgetsFailureWarning) } catch {
        if (Test-LDLCStopRequestError $_) { throw }
        Write-Warn ('[TASKBAR] Configuration impossible : ' + $_.Exception.Message)
    }
    if (-not $DeferFinalValidation) { [void](Confirm-LDLCDefaultAppsFinalState) }
}

function Get-LDLCChromeExecutablePath {
    $candidates = @(
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "$env:LocalAppData\Google\Chrome\Application\chrome.exe"
    )

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path $candidate)) {
            return $candidate
        }
    }

    return $null
}

function Close-LDLCExplorerFileWindows {
    param(
        [int]$TimeoutSeconds = 6
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

    do {
        $closedCount = 0

        try {
            $shell = New-Object -ComObject Shell.Application
            foreach ($window in @($shell.Windows())) {
                try {
                    $fullName = [string]$window.FullName
                    if ((Split-Path -Path $fullName -Leaf) -ieq 'explorer.exe') {
                        $window.Quit()
                        $closedCount++
                    }
                }
                catch {
                }
            }
        }
        catch {
            Write-Warn "Impossible de fermer les fenetres Explorer : $($_.Exception.Message)"
            return
        }

        if ($closedCount -le 0) {
            return
        }

        Write-Info "$closedCount fenetre(s) Explorer fermee(s) apres relance."
        Start-Sleep -Milliseconds 500
    }
    while ((Get-Date) -lt $deadline)
}

function Invoke-LDLCChromeTaskbarPinBeforeWindowsUpdate {
    param([int]$ProgressPercent = 90)
    return Invoke-LDLCChromeTaskbarPin -ProgressPercent $ProgressPercent
}

# endregion Module: 70.DefaultApps.ps1
# Historical Chrome taskbar preparation, restored at the user's request.
# Reference: LDLC 32034cc^ / 3aec296, Invoke-LDLCChromeTaskbarPinBeforeWindowsUpdate.
# Write the Append layout and refresh Explorer; no UIA menu or pin-confirmation timeout.
# A prepared layout is not proof that Windows displayed the pin on every device.
function Invoke-LDLCChromeTaskbarPin {
    param(
        [int]$ProgressPercent = 90
    )

    Stop-IfRequested
    Write-Section "EPINGLAGE CHROME BARRE DES TACHES"

    $chromeExe = Get-LDLCChromeExecutablePath
    if (-not $chromeExe) {
        Write-Warn "Chrome introuvable : epinglage barre des taches ignore."
        return $false
    }

    $shellFolder = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Shell'
    $xmlPath = Join-Path $shellFolder 'LayoutModification.xml'

    try {
        New-Item -ItemType Directory -Path $shellFolder -Force | Out-Null

        $xml = @"
<?xml version="1.0" encoding="utf-8"?>
<LayoutModificationTemplate
    xmlns="http://schemas.microsoft.com/Start/2014/LayoutModification"
    xmlns:defaultlayout="http://schemas.microsoft.com/Start/2014/FullDefaultLayout"
    xmlns:start="http://schemas.microsoft.com/Start/2014/StartLayout"
    xmlns:taskbar="http://schemas.microsoft.com/Start/2014/TaskbarLayout"
    Version="1">
  <CustomTaskbarLayoutCollection PinListPlacement="Append">
    <defaultlayout:TaskbarLayout>
      <taskbar:TaskbarPinList>
        <taskbar:DesktopApp DesktopApplicationID="Chrome" />
      </taskbar:TaskbarPinList>
    </defaultlayout:TaskbarLayout>
  </CustomTaskbarLayoutCollection>
</LayoutModificationTemplate>
"@

        [System.IO.File]::WriteAllText($xmlPath, $xml, (New-Object System.Text.UTF8Encoding($false)))
        Write-Ok "Layout taskbar Chrome prepare : $xmlPath"
    }
    catch {
        if (Test-LDLCStopRequestError $_) { throw }
        Write-Warn "Impossible de preparer le layout taskbar Chrome : $($_.Exception.Message)"
        return $false
    }

    Write-ProgressFile $ProgressPercent "Epinglage de Chrome a la barre des taches..."

    try {
        Stop-IfRequested
        Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force -Confirm:$false -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 1000
        Start-Process explorer
        Start-Sleep -Milliseconds 1800
        Stop-IfRequested
        Close-LDLCExplorerFileWindows
        Write-Info "Relance Explorer effectuee sans fenetre Accueil."
    }
    catch {
        if (Test-LDLCStopRequestError $_) { throw }
        Write-Warn "Relance Explorer impossible : $($_.Exception.Message)"
    }

    return $true
}
# region Module: 80.WindowsUpdate.ps1
# Windows Update helpers.

function Get-WUResultCodeText {
    param([int]$Code)

    switch ($Code) {
        0 { return "NotStarted" }
        1 { return "InProgress" }
        2 { return "Succeeded" }
        3 { return "SucceededWithErrors" }
        4 { return "Failed" }
        5 { return "Aborted" }
        default { return "Unknown($Code)" }
    }
}

function Get-LDLCWindowsUpdateTitle {
    param($Update)

    try {
        $title = [string]$Update.Title
        if (-not [string]::IsNullOrWhiteSpace($title)) {
            return $title
        }
    }
    catch {}

    return "Mise a jour sans titre"
}

function Format-LDLCHResult {
    param($HResult)

    if ($null -eq $HResult -or [int64]$HResult -eq 0) {
        return $null
    }

    try {
        $value = [int64]$HResult
        if ($value -lt 0) {
            $value += 0x100000000
        }

        return ("0x{0:X8}" -f ([uint32]$value))
    }
    catch {
        return [string]$HResult
    }
}

function Test-LDLCDefenderSignatureUpdateTitle {
    param([string]$Title)

    if ([string]::IsNullOrWhiteSpace($Title)) {
        return $false
    }

    return (
        $Title -match '(?i)(^|[^0-9])(?:KB)?2267602([^0-9]|$)' -or
        $Title -match '(?i)Security Intelligence|Microsoft Defender Antivirus.*version|Defender Antivirus.*version|d.finition.*Defender|Defender.*d.finition|renseignement.*s.curit.|s.lection.*Defender'
    )
}

function Test-LDLCIgnorableWindowsUpdateFailure {
    param(
        [string]$Title,
        $HResult,
        [int]$ResultCode
    )

    $hresultText = Format-LDLCHResult -HResult $HResult

    if ($hresultText -eq '0x80070103') {
        return $true
    }

    if (Test-LDLCDefenderSignatureUpdateTitle -Title $Title) {
        return ($ResultCode -in @(3, 4, 5))
    }

    return $false
}

function Invoke-LDLCDefenderSignatureUpdate {
    Stop-IfRequested

    try {
        $command = Get-Command -Name Update-MpSignature -ErrorAction SilentlyContinue
        if (-not $command) {
            Write-Warn "Mise a jour Microsoft Defender ignoree : Update-MpSignature indisponible."
            return $false
        }

        Write-Step "Mise a jour des signatures Microsoft Defender..."
        Update-MpSignature -ErrorAction Stop | Out-Null
        Write-Ok "Signatures Microsoft Defender mises a jour."
        return $true
    }
    catch {
        Write-Warn "Mise a jour Microsoft Defender non bloquante : $($_.Exception.Message)"
        return $false
    }
}

function Invoke-LDLCUsoClientAction {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('RefreshSettings', 'StartScan', 'StartDownload', 'StartInstall')]
        [string]$Action,
        [switch]$QuietFailure
    )

    try {
        $usoClient = Join-Path $env:WINDIR 'System32\UsoClient.exe'
        if (-not (Test-Path -LiteralPath $usoClient)) {
            if ($QuietFailure) {
                Write-Info "Windows Update systeme : UsoClient indisponible pour $Action."
            }
            return $false
        }

        Start-Process -FilePath $usoClient -ArgumentList $Action -WindowStyle Hidden -ErrorAction Stop | Out-Null
        Write-Step "Windows Update systeme : $Action lance."
        return $true
    }
    catch {
        if ($QuietFailure) {
            Write-Info "Windows Update systeme : $Action non confirme ($($_.Exception.Message))."
        }
        else {
            Write-Warn "Impossible de lancer UsoClient $Action : $($_.Exception.Message)"
        }

        return $false
    }
}

function Start-LDLCWindowsUpdateRequiredServices {
    $serviceNames = @('wuauserv', 'bits', 'UsoSvc', 'DoSvc')
    $started = New-Object System.Collections.Generic.List[string]
    $running = New-Object System.Collections.Generic.List[string]
    $failed = New-Object System.Collections.Generic.List[string]

    foreach ($serviceName in $serviceNames) {
        Stop-IfRequested

        try {
            $service = Get-Service -Name $serviceName -ErrorAction Stop
            if ($service.Status -ne 'Running') {
                Write-Step "Windows Update : demarrage du service $serviceName..."
                Start-Service -Name $serviceName -ErrorAction Stop

                $service.Refresh()
                if ($service.Status -eq 'Running') {
                    [void]$started.Add($serviceName)
                    [void]$running.Add($serviceName)
                    Write-Ok "Windows Update : service $serviceName actif."
                }
                else {
                    [void]$failed.Add($serviceName)
                    Write-Info "Windows Update : service $serviceName non confirme, etat=$($service.Status)."
                }
            }
            else {
                [void]$running.Add($serviceName)
                Write-Info "Windows Update : service $serviceName deja actif."
            }
        }
        catch {
            [void]$failed.Add($serviceName)
            Write-Info "Windows Update : service $serviceName non demarre ($($_.Exception.Message))."
        }
    }

    return [pscustomobject]@{
        Started = @($started.ToArray())
        Running = @($running.ToArray())
        Failed  = @($failed.ToArray())
    }
}

function Invoke-LDLCWuaUcltAction {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('/detectnow', '/updatenow')]
        [string]$Action
    )

    try {
        $wuauclt = Join-Path $env:WINDIR 'System32\wuauclt.exe'
        if (-not (Test-Path -LiteralPath $wuauclt -PathType Leaf)) {
            Write-Info "Windows Update legacy : wuauclt indisponible pour $Action."
            return $false
        }

        Start-Process -FilePath $wuauclt -ArgumentList $Action -WindowStyle Hidden -ErrorAction Stop | Out-Null
        Write-Step "Windows Update legacy : wuauclt $Action lance."
        return $true
    }
    catch {
        Write-Info "Windows Update legacy : wuauclt $Action non confirme ($($_.Exception.Message))."
        return $false
    }
}

function Invoke-LDLCWindowsUpdateScheduledTask {
    param(
        [Parameter(Mandatory = $true)][string]$TaskPath,
        [Parameter(Mandatory = $true)][string]$TaskName,
        [Parameter(Mandatory = $true)][string]$Label
    )

    try {
        $task = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction Stop
        Start-ScheduledTask -InputObject $task -ErrorAction Stop
        Write-Step "Windows Update tache planifiee : $Label lancee."
        return $true
    }
    catch {
        Write-Info "Windows Update tache planifiee : $Label non lancee ($($_.Exception.Message))."
        return $false
    }
}

function Get-LDLCWindowsUpdateKickoffDelaySeconds {
    # Compatibilite : aucun ancien override ne doit retablir une attente.
    return 0
}

function Get-LDLCWindowsUpdateMaxAttempts {
    $defaultAttempts = 2

    if (-not [string]::IsNullOrWhiteSpace($env:LDLC_WU_MAX_ATTEMPTS)) {
        try {
            return [math]::Min(3, [math]::Max(1, [int]$env:LDLC_WU_MAX_ATTEMPTS))
        }
        catch {}
    }

    return $defaultAttempts
}

function Get-LDLCWindowsUpdateMaxCycles {
    $defaultCycles = 8

    if (-not [string]::IsNullOrWhiteSpace($env:LDLC_WU_MAX_CYCLES)) {
        try {
            return [math]::Min(20, [math]::Max(1, [int]$env:LDLC_WU_MAX_CYCLES))
        }
        catch {}
    }

    return $defaultCycles
}

function Get-LDLCWindowsUpdatePostCycleDelaySeconds {
    # Compatibilite : aucun ancien override ne doit retablir une attente.
    return 0
}

function Test-LDLCWindowsPendingReboot {
    $hardReasons = New-Object System.Collections.Generic.List[string]
    $softReasons = New-Object System.Collections.Generic.List[string]

    foreach ($path in @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    )) {
        try {
            if (Test-Path -LiteralPath $path) {
                [void]$hardReasons.Add($path)
            }
        }
        catch {}
    }

    try {
        $servicePendingPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Services\Pending'
        if (Test-Path -LiteralPath $servicePendingPath) {
            [void]$softReasons.Add($servicePendingPath)
        }
    }
    catch {}

    try {
        $sessionManager = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
        if ($sessionManager -and $sessionManager.PendingFileRenameOperations) {
            [void]$softReasons.Add('PendingFileRenameOperations')
        }
    }
    catch {}

    try {
        $volatile = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Updates' -Name UpdateExeVolatile -ErrorAction SilentlyContinue
        if ($volatile -and [int]$volatile.UpdateExeVolatile -ne 0) {
            [void]$hardReasons.Add('UpdateExeVolatile')
        }
    }
    catch {}

    $allReasons = @($hardReasons.ToArray()) + @($softReasons.ToArray())
    return [pscustomobject]@{
        IsPending   = ($hardReasons.Count -gt 0)
        Reasons     = $allReasons
        HardReasons = @($hardReasons.ToArray())
        SoftReasons = @($softReasons.ToArray())
    }
}

function Add-LDLCWindowsUpdateTelemetryEvent {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('info', 'warning', 'error', 'critical')]
        [string]$Severity = 'warning',
        [string]$Status = 'avertissement',
        [string]$Details
    )

    if (Get-Command Add-LDLCTelemetryEvent -ErrorAction SilentlyContinue) {
        $eventParams = @{
            Message  = $Message
            Severity = $Severity
            Type     = 'Windows Update'
            Status   = $Status
        }

        if (-not [string]::IsNullOrWhiteSpace($Details)) {
            $eventParams.Details = $Details
        }

        Add-LDLCTelemetryEvent @eventParams
    }
}

function Get-LDLCRecentWindowsUpdateFailureSummary {
    try {
        $events = @(
            Get-WinEvent -FilterHashtable @{
                LogName   = 'Microsoft-Windows-WindowsUpdateClient/Operational'
                StartTime = (Get-Date).AddMinutes(-45)
            } -MaxEvents 25 -ErrorAction Stop |
                Where-Object { $_.Id -in @(20, 24, 25, 31, 34, 35, 43, 44) }
        )

        if ($events.Count -le 0) {
            return $null
        }

        $event = $events | Select-Object -First 1
        $message = ([string]$event.Message -replace '\s+', ' ').Trim()
        if ($message.Length -gt 260) {
            $message = $message.Substring(0, 260) + '...'
        }

        return "EventId=$($event.Id) - $message"
    }
    catch {
        return $null
    }
}

function Invoke-LDLCWindowsUpdateRetry {
    param(
        [Parameter(Mandatory = $true)][string]$Reason,
        [Parameter(Mandatory = $true)][int]$Attempt,
        [Parameter(Mandatory = $true)][int]$MaxAttempts
    )

    Stop-IfRequested
    Write-Warn "Relance Windows Update $Attempt/$MaxAttempts : $Reason"
    Add-LDLCWindowsUpdateTelemetryEvent -Message "Relance Windows Update $Attempt/$MaxAttempts : $Reason" -Severity warning

    $started = $false
    foreach ($action in @('StartScan', 'StartDownload', 'StartInstall')) {
        if (Invoke-LDLCUsoClientAction -Action $action) {
            $started = $true
        }
        Start-Sleep -Seconds 1
    }

    Start-Sleep -Seconds 3
    return $started
}

function Invoke-LDLCWindowsUpdateBackgroundFallback {
    param([string]$Reason = 'delai atteint')

    Stop-IfRequested
    Write-Warn "Declenchement Windows Update trop long ($Reason). Nouvelle tentative en arriere-plan."

    $started = $false
    foreach ($action in @('StartScan', 'StartDownload', 'StartInstall')) {
        if (Invoke-LDLCUsoClientAction -Action $action) {
            $started = $true
        }
        Start-Sleep -Seconds 1
    }

    if ($started) {
        Write-Warn "Windows Update continue via le service Windows. La preparation peut continuer sans attendre."
        if (Get-Command Add-LDLCTelemetryEvent -ErrorAction SilentlyContinue) {
            Add-LDLCWindowsUpdateTelemetryEvent `
                -Message "Windows Update bascule en arriere-plan : $Reason" `
                -Severity warning `
                -Status 'avertissement'
        }
    }
    else {
        Write-Warn "Impossible de lancer Windows Update en arriere-plan."
    }

    return $started
}

function Invoke-LDLCWindowsUpdateDownload {
    param(
        [Parameter(Mandatory = $true)]$UpdateSession,
        [Parameter(Mandatory = $true)]$Updates,
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][int]$ProgressPercent
    )

    if (-not $Updates -or $Updates.Count -eq 0) {
        return [pscustomobject]@{
            Updates         = (New-Object -ComObject "Microsoft.Update.UpdateColl")
            RebootRequired  = $false
            DownloadedCount = 0
        }
    }

    Stop-IfRequested
    Write-ProgressFile $ProgressPercent "Téléchargement $Label..."
    Write-Step "Telechargement $Label..."
    if (Get-Command Update-LDLCTelemetryRun -ErrorAction SilentlyContinue) {
        Update-LDLCTelemetryRun -Status 'En cours' -Step "Telechargement $Label" -Message "Debut du telechargement $Label." -ProgressPercent $ProgressPercent -Force
    }

    $downloader = $UpdateSession.CreateUpdateDownloader()
    try { $downloader.ClientApplicationID = "LDLC PrepTool" } catch {}
    try { $downloader.IsForced = $true } catch {}
    $downloader.Updates = $Updates
    $downloadResult = $downloader.Download()
    $resultCode = [int]$downloadResult.ResultCode

    if ($resultCode -notin @(2, 3)) {
        throw "Echec du telechargement $Label : $(Get-WUResultCodeText -Code $resultCode)"
    }

    $downloadedUpdates = New-Object -ComObject "Microsoft.Update.UpdateColl"
    for ($index = 0; $index -lt $Updates.Count; $index++) {
        $candidate = $Updates.Item($index)
        if ($candidate.IsDownloaded) {
            [void]$downloadedUpdates.Add($candidate)
        }
    }

    Write-Ok "$Label telechargees : $($downloadedUpdates.Count)"
    return [pscustomobject]@{
        Updates         = $downloadedUpdates
        RebootRequired  = $false
        DownloadedCount = $downloadedUpdates.Count
    }
}

function Invoke-LDLCWindowsUpdateInstall {
    param(
        [Parameter(Mandatory = $true)]$UpdateSession,
        [Parameter(Mandatory = $true)]$Updates,
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][int]$ProgressPercent
    )

    if (-not $Updates -or $Updates.Count -eq 0) {
        return [pscustomobject]@{
            ResultCode      = 2
            RebootRequired  = $false
            InstalledCount  = 0
        }
    }

    Stop-IfRequested
    Write-ProgressFile $ProgressPercent "Installation $Label..."
    Write-Step "Installation $Label..."
    if (Get-Command Update-LDLCTelemetryRun -ErrorAction SilentlyContinue) {
        Update-LDLCTelemetryRun -Status 'En cours' -Step "Installation $Label" -Message "Debut de l'installation $Label." -ProgressPercent $ProgressPercent -Force
    }

    $installer = $UpdateSession.CreateUpdateInstaller()
    try { $installer.ClientApplicationID = "LDLC PrepTool" } catch {}
    try { $installer.IsForced = $true } catch {}
    try { $installer.ForceQuiet = $true } catch {}
    $installer.Updates = $Updates
    $installResult = $installer.Install()
    $resultCode = [int]$installResult.ResultCode

    $installedCount = 0
    $warningCount = 0
    $failedCount = 0
    $ignoredFailureCount = 0

    for ($index = 0; $index -lt $Updates.Count; $index++) {
        $update = $Updates.Item($index)
        $title = Get-LDLCWindowsUpdateTitle -Update $update
        $itemCode = $resultCode
        $itemHResult = $null

        try {
            $itemResult = $installResult.GetUpdateResult($index)
            $itemCode = [int]$itemResult.ResultCode
            $itemHResult = $itemResult.HResult
        }
        catch {}

        $itemCodeText = Get-WUResultCodeText -Code $itemCode
        $itemHResultText = Format-LDLCHResult -HResult $itemHResult
        $detail = if ($itemHResultText) { "$itemCodeText / $itemHResultText" } else { $itemCodeText }

        if ($itemCode -eq 2) {
            $installedCount++
            Write-Ok "$Label installee : $title"
        }
        elseif (Test-LDLCIgnorableWindowsUpdateFailure -Title $title -HResult $itemHResult -ResultCode $itemCode) {
            $ignoredFailureCount++
            $ignoredReason = if ((Format-LDLCHResult -HResult $itemHResult) -eq '0x80070103') {
                'pilote deja present ou non applicable'
            }
            else {
                'geree par Microsoft Defender'
            }
            Write-Warn "$Label non bloquante, $ignoredReason : $title ($detail)"
        }
        elseif ($itemCode -eq 3) {
            $warningCount++
            Write-Warn "$Label installee avec erreurs : $title ($detail)"
        }
        else {
            $failedCount++
            Write-Warn "$Label non installee : $title ($detail)"
        }
    }

    if ($resultCode -notin @(2, 3)) {
        if ($failedCount -gt 0 -or $ignoredFailureCount -eq 0) {
            throw "Echec de l'installation $Label : $(Get-WUResultCodeText -Code $resultCode)"
        }

        Write-Warn "$Label : echec Windows Update limite aux signatures Microsoft Defender, non bloquant."
    }

    if ($installResult.RebootRequired) {
        $script:PendingReboot = $true
        Write-Warn "Un redemarrage sera necessaire suite a l'installation $Label."
    }

    if ($failedCount -gt 0) {
        Write-Warn "$Label : $failedCount echec(s) detecte(s), une relance Windows Update sera tentee."
    }

    Write-Ok "$Label validees par Windows Update : $installedCount reussie(s), $warningCount avec avertissement(s), $failedCount echec(s), $ignoredFailureCount non bloquant(s)."
    return [pscustomobject]@{
        ResultCode          = $resultCode
        RebootRequired      = [bool]$installResult.RebootRequired
        InstalledCount      = $installedCount
        WarningCount        = $warningCount
        FailedCount         = $failedCount
        IgnoredFailureCount = $ignoredFailureCount
    }
}

# --------------------------------------------------
# WINDOWS UPDATE - DETECTION ACTIVITE EN COURS
# --------------------------------------------------

function Test-WindowsUpdateBusy {
    Stop-IfRequested

    try {
        $busyProcesses = @(
            "TiWorker",
            "TrustedInstaller",
            "wuauclt",
            "UsoClient",
            "MoUsoCoreWorker",
            "MusNotification",
            "MusNotificationUx"
        )

        foreach ($procName in $busyProcesses) {
            $procs = Get-Process -Name $procName -ErrorAction SilentlyContinue
            if ($procs) {
                Write-Warn "Windows Update semble deja en cours (processus detecte : $procName)."
                return $true
            }
        }

        $trustedInstaller = Get-Service -Name "TrustedInstaller" -ErrorAction SilentlyContinue
        if ($trustedInstaller -and $trustedInstaller.Status -eq "Running") {
            Write-Warn "Windows Modules Installer (TrustedInstaller) est deja en cours."
            return $true
        }

        return $false
    }
    catch {
        Write-Warn "Impossible de verifier si Windows Update est deja en cours : $($_.Exception.Message)"
        return $false
    }
}

function Ensure-LDLCMicrosoftUpdateService {
    try {
        $muServiceId = "7971f918-a847-4430-9279-4a52d1efe18d"
        $serviceManager = New-Object -ComObject "Microsoft.Update.ServiceManager"
        $serviceManager.ClientApplicationID = "LDLC PrepTool"

        $alreadyRegistered = $false
        try {
            foreach ($svc in $serviceManager.Services) {
                if ($svc.ServiceID -eq $muServiceId) {
                    $alreadyRegistered = $true
                    break
                }
            }
        }
        catch {
        }

        if (-not $alreadyRegistered) {
            Write-Step "Activation du service Microsoft Update..."
            $null = $serviceManager.AddService2($muServiceId, 7, "")
            Start-Sleep -Seconds 2
        }

        return $true
    }
    catch {
        Write-Warn "Impossible d'activer Microsoft Update : $($_.Exception.Message)"
        return $false
    }
}

function New-LDLCWindowsUpdateSearchContext {
    Write-Step "Initialisation de Windows Update..."

    $updateSession = New-Object -ComObject "Microsoft.Update.Session"
    try { $updateSession.ClientApplicationID = "LDLC PrepTool" } catch {}
    [void](Ensure-LDLCMicrosoftUpdateService)
    $updateSearcher = $updateSession.CreateUpdateSearcher()
    try { $updateSearcher.Online = $true } catch {}

    try {
        $updateSearcher.ServerSelection = 3
        $updateSearcher.ServiceID = "7971f918-a847-4430-9279-4a52d1efe18d"
    }
    catch {
        Write-Warn "Recherche Microsoft Update non forcee : $($_.Exception.Message)"
    }

    return [pscustomobject]@{
        Session  = $updateSession
        Searcher = $updateSearcher
    }
}

function Get-LDLCWindowsUpdateCollection {
    param(
        [Parameter(Mandatory = $true)]$UpdateSearcher,
        [Parameter(Mandatory = $true)][string]$Label,
        [switch]$StandardOnly,
        [switch]$OptionalOnly
    )

    Stop-IfRequested
    Write-Step "Recherche $Label..."
    if (Get-Command Update-LDLCTelemetryRun -ErrorAction SilentlyContinue) {
        Update-LDLCTelemetryRun -Status 'En cours' -Step "Recherche $Label" -Message "Debut de la recherche $Label." -Force
    }

    $updates = New-Object -ComObject "Microsoft.Update.UpdateColl"
    $searchResult = $UpdateSearcher.Search("IsInstalled=0 and IsHidden=0")
    $detectedCount = 0

    if ($searchResult -and $searchResult.Updates) {
        $detectedCount = $searchResult.Updates.Count

        for ($i = 0; $i -lt $searchResult.Updates.Count; $i++) {
            Stop-IfRequested

            $update = $searchResult.Updates.Item($i)
            $title = Get-LDLCWindowsUpdateTitle -Update $update

            if (Test-LDLCDefenderSignatureUpdateTitle -Title $title) {
                Write-Step "$Label : mise a jour Microsoft Defender geree separement : $title"
                continue
            }

            $isDriver = $false
            try { $isDriver = ($update.Type -eq 2) } catch {}

            if ($isDriver -and -not $script:WU_IncludeDrivers) {
                continue
            }

            $isOptional = $false
            try { $isOptional = [bool]$update.BrowseOnly } catch {}

            if ($StandardOnly -and $isOptional) {
                continue
            }

            if ($OptionalOnly -and -not $isOptional) {
                continue
            }

            if ($isOptional -and -not $script:WU_InstallOptional) {
                continue
            }

            try {
                if (-not $update.EulaAccepted) {
                    $update.AcceptEula()
                }
            }
            catch {
                Write-Warn "Mise a jour ignoree, EULA non acceptee : $($update.Title)"
                continue
            }

            [void]$updates.Add($update)
        }
    }

    Write-Step "$Label : $($updates.Count) eligible(s) sur $detectedCount detectee(s)."
    return [pscustomobject]@{
        Updates       = $updates
        DetectedCount = $detectedCount
    }
}

function Invoke-LDLCWindowsUpdateInstallCycle {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][int]$DownloadPercent,
        [Parameter(Mandatory = $true)][int]$InstallPercent,
        [switch]$StandardOnly,
        [switch]$OptionalOnly,
        [int]$MaxPasses = 1
    )

    $handledCount = 0
    $rebootRequired = $false
    $usoFallbackUsed = $false
    $remainingCount = 0
    $attemptedUpdates = $false

    for ($pass = 1; $pass -le $MaxPasses; $pass++) {
        Stop-IfRequested

        if ($pass -gt 1) {
            Write-Warn "$Label encore presente(s) apres verification. Nouvelle tentative $pass/$MaxPasses."
            Start-Sleep -Seconds 2
        }

        $context = New-LDLCWindowsUpdateSearchContext
        $searchParams = @{
            UpdateSearcher = $context.Searcher
            Label          = "$Label (passe $pass/$MaxPasses)"
        }

        if ($StandardOnly) { $searchParams.StandardOnly = $true }
        if ($OptionalOnly) { $searchParams.OptionalOnly = $true }

        $search = Get-LDLCWindowsUpdateCollection @searchParams
        $remainingCount = $search.Updates.Count

        if ($search.Updates.Count -eq 0) {
            Write-Ok "$Label : aucune mise a jour restante."
            break
        }

        $attemptedUpdates = $true
        $downloadResult = Invoke-LDLCWindowsUpdateDownload -UpdateSession $context.Session -Updates $search.Updates -Label $Label -ProgressPercent $DownloadPercent
        $rebootRequired = ($rebootRequired -or $downloadResult.RebootRequired)

        if ($downloadResult.Updates.Count -eq 0) {
            Write-Warn "$Label : aucune mise a jour telechargee malgre $($search.Updates.Count) detectee(s)."
            [void](Invoke-LDLCUsoClientAction -Action StartDownload)
            Start-Sleep -Seconds 1
            [void](Invoke-LDLCUsoClientAction -Action StartInstall)
            $usoFallbackUsed = $true
            break
        }

        $installResult = Invoke-LDLCWindowsUpdateInstall -UpdateSession $context.Session -Updates $downloadResult.Updates -Label $Label -ProgressPercent $InstallPercent
        $rebootRequired = ($rebootRequired -or $installResult.RebootRequired)
        $handledCount += $installResult.InstalledCount

        if ($installResult.RebootRequired) {
            Write-Warn "$Label : verification interrompue, un redemarrage est necessaire."
            break
        }

        if (($installResult.InstalledCount -eq 0 -and $installResult.IgnoredFailureCount -eq 0) -or $installResult.FailedCount -gt 0) {
            Write-Warn "$Label : Windows Update COM n'a pas valide toutes les installations. Tentative via le service Windows Update."
            [void](Invoke-LDLCUsoClientAction -Action StartInstall)
            $usoFallbackUsed = $true
            Start-Sleep -Seconds 3
        }
    }

    if (-not $rebootRequired -and $attemptedUpdates) {
        Stop-IfRequested
        if (-not $script:WU_VerifyAfterInstall) {
            Write-Info "$Label : verification finale ignoree pour reduire le temps Windows Update."
            if (-not $usoFallbackUsed) {
                $remainingCount = 0
            }

            return [pscustomobject]@{
                Count           = $handledCount
                RebootRequired  = $rebootRequired
                RemainingCount  = $remainingCount
                UsoFallbackUsed = $usoFallbackUsed
            }
        }

        $verifyContext = New-LDLCWindowsUpdateSearchContext
        $verifyParams = @{
            UpdateSearcher = $verifyContext.Searcher
            Label          = "$Label apres installation"
        }

        if ($StandardOnly) { $verifyParams.StandardOnly = $true }
        if ($OptionalOnly) { $verifyParams.OptionalOnly = $true }

        $verifySearch = Get-LDLCWindowsUpdateCollection @verifyParams
        $remainingCount = $verifySearch.Updates.Count

        if ($remainingCount -gt 0) {
            Write-Warn "$Label : $remainingCount mise(s) a jour encore proposee(s) apres tentative."
            if (-not $usoFallbackUsed) {
                [void](Invoke-LDLCUsoClientAction -Action StartInstall)
                $usoFallbackUsed = $true
            }
        }
        else {
            Write-Ok "$Label : verification OK, plus rien a installer."
        }
    }

    return [pscustomobject]@{
        Count           = $handledCount
        RebootRequired  = $rebootRequired
        RemainingCount  = $remainingCount
        UsoFallbackUsed = $usoFallbackUsed
    }
}

function Invoke-LDLCWindowsUpdateFullMaintenance {
    param(
        [int]$StartPercent = 5,
        [int]$EndPercent = 24,
        [int]$MaxCycles = (Get-LDLCWindowsUpdateMaxCycles)
    )

    Stop-IfRequested
    Write-Section "WINDOWS UPDATE"
    Write-Step "Windows Update complet : recherche, telechargement, installation et verification jusqu'a absence de mises a jour."
    Write-Step "Redemarrage automatique desactive : si Windows demande un redemarrage, la boucle s'arrete proprement."

    if (Get-Command Update-LDLCTelemetryRun -ErrorAction SilentlyContinue) {
        Update-LDLCTelemetryRun `
            -Status 'En cours' `
            -Step 'Windows Update' `
            -Message 'Windows Update en cours : cycles complets jusqu a absence de mises a jour.' `
            -ProgressPercent $StartPercent `
            -Force
    }

    $services = Start-LDLCWindowsUpdateRequiredServices
    [void](Invoke-LDLCDefenderSignatureUpdate)

    $progressSpan = [math]::Max(1, $EndPercent - $StartPercent)
    $handledCount = 0
    $downloadedCount = 0
    $detectedTotal = 0
    $remainingCount = 0
    $failedCount = 0
    $warningCount = 0
    $ignoredFailureCount = 0
    $usoFallbackUsed = $false
    $completed = $false
    $rebootRequired = $false
    $timedOut = $false
    $lastError = $null
    $cycle = 0
    $postCycleDelay = Get-LDLCWindowsUpdatePostCycleDelaySeconds

    for ($cycle = 1; $cycle -le $MaxCycles; $cycle++) {
        Stop-IfRequested

        $pendingBeforeSearch = Test-LDLCWindowsPendingReboot
        if ($pendingBeforeSearch.IsPending) {
            $rebootRequired = $true
            $script:PendingReboot = $true
            $reasonText = ($pendingBeforeSearch.Reasons -join ', ')
            Write-Warn "Windows Update suspendu : redemarrage requis avant nouvelle recherche ($reasonText). Aucun redemarrage automatique."
            Write-ProgressFile $EndPercent "Windows Update en pause : redemarrage requis. Ne pas eteindre le PC."
            break
        }

        $cycleBasePercent = $StartPercent + [math]::Floor(($progressSpan * [math]::Min($cycle - 1, $MaxCycles - 1)) / [math]::Max(1, $MaxCycles))
        $searchPercent = [int][math]::Min($EndPercent - 1, [math]::Max($StartPercent, $cycleBasePercent))
        $downloadPercent = [int][math]::Min($EndPercent - 1, $searchPercent + 1)
        $installPercent = [int][math]::Min($EndPercent - 1, $searchPercent + 2)

        $searchMessage = "Windows Update en cours... Cycle $cycle/$MaxCycles - Recherche de mises a jour. Ne pas eteindre le PC."
        Write-ProgressFile $searchPercent $searchMessage
        Write-Step $searchMessage

        if (Get-Command Update-LDLCTelemetryRun -ErrorAction SilentlyContinue) {
            Update-LDLCTelemetryRun `
                -Status 'En cours' `
                -Step 'Windows Update' `
                -Message "Cycle $cycle/$MaxCycles : recherche de nouvelles mises a jour." `
                -ProgressPercent $searchPercent `
                -Force
        }

        try {
            $context = New-LDLCWindowsUpdateSearchContext
            $search = Get-LDLCWindowsUpdateCollection `
                -UpdateSearcher $context.Searcher `
                -Label "des mises a jour Windows (cycle $cycle/$MaxCycles)"

            $detectedTotal += [int]$search.DetectedCount
            $remainingCount = [int]$search.Updates.Count

            if ($remainingCount -le 0) {
                $completed = $true
                Write-Ok "Windows Update termine : aucune mise a jour restante apres $cycle cycle(s)."
                Write-ProgressFile $EndPercent "Windows Update termine : aucune mise a jour restante."
                break
            }

            Write-ProgressFile $downloadPercent "Windows Update en cours... Cycle $cycle/$MaxCycles - Telechargement de $remainingCount mise(s) a jour. Ne pas eteindre le PC."
            $downloadResult = Invoke-LDLCWindowsUpdateDownload `
                -UpdateSession $context.Session `
                -Updates $search.Updates `
                -Label "des mises a jour Windows (cycle $cycle/$MaxCycles)" `
                -ProgressPercent $downloadPercent

            $downloadedCount += [int]$downloadResult.DownloadedCount

            if ($downloadResult.Updates.Count -le 0) {
                $lastError = "Cycle $cycle/$MaxCycles : aucune mise a jour telechargee malgre $remainingCount detectee(s)."
                Write-Warn $lastError
                if (Invoke-LDLCUsoClientAction -Action StartDownload -QuietFailure) { $usoFallbackUsed = $true }
                if (Invoke-LDLCUsoClientAction -Action StartInstall -QuietFailure) { $usoFallbackUsed = $true }
            }
            else {
                Write-ProgressFile $installPercent "Windows Update en cours... Cycle $cycle/$MaxCycles - Installation des mises a jour. Ne pas eteindre le PC."
                $installResult = Invoke-LDLCWindowsUpdateInstall `
                    -UpdateSession $context.Session `
                    -Updates $downloadResult.Updates `
                    -Label "des mises a jour Windows (cycle $cycle/$MaxCycles)" `
                    -ProgressPercent $installPercent

                $handledCount += [int]$installResult.InstalledCount
                $warningCount += [int]$installResult.WarningCount
                $failedCount += [int]$installResult.FailedCount
                $ignoredFailureCount += [int]$installResult.IgnoredFailureCount
                $rebootRequired = ($rebootRequired -or [bool]$installResult.RebootRequired)

                if ($rebootRequired) {
                    $script:PendingReboot = $true
                    Write-Warn "Windows Update demande un redemarrage apres le cycle $cycle/$MaxCycles. Aucun redemarrage automatique ne sera effectue."
                    Write-ProgressFile $EndPercent "Windows Update en pause : redemarrage requis. Ne pas eteindre le PC."
                    break
                }
            }
        }
        catch {
            if (Test-LDLCStopRequestError $_) { throw }

            $lastError = $_.Exception.Message
            $failedSummary = Get-LDLCRecentWindowsUpdateFailureSummary
            $details = if ($failedSummary) { "$lastError`n$failedSummary" } else { $lastError }

            Write-Warn "Windows Update cycle $cycle/$MaxCycles en echec : $lastError"
            Write-Step "Windows Update : relance systeme non bloquante avant le prochain cycle."
            if (Invoke-LDLCUsoClientAction -Action StartScan -QuietFailure) { $usoFallbackUsed = $true }
            if (Invoke-LDLCUsoClientAction -Action StartDownload -QuietFailure) { $usoFallbackUsed = $true }
            if (Invoke-LDLCUsoClientAction -Action StartInstall -QuietFailure) { $usoFallbackUsed = $true }

            Add-LDLCWindowsUpdateTelemetryEvent `
                -Message "Windows Update cycle $cycle/$MaxCycles en echec : $lastError" `
                -Severity warning `
                -Status 'avertissement' `
                -Details $details
        }

        $pendingAfterInstall = Test-LDLCWindowsPendingReboot
        if ($pendingAfterInstall.IsPending) {
            $rebootRequired = $true
            $script:PendingReboot = $true
            $reasonText = ($pendingAfterInstall.Reasons -join ', ')
            Write-Warn "Windows Update suspendu : redemarrage requis apres installation ($reasonText). Aucun redemarrage automatique."
            Write-ProgressFile $EndPercent "Windows Update en pause : redemarrage requis. Ne pas eteindre le PC."
            break
        }

        if ($cycle -lt $MaxCycles) {
            Write-ProgressFile $installPercent "Windows Update en cours... Cycle $cycle/$MaxCycles termine. Nouvelle recherche dans ${postCycleDelay}s."
            Write-Step "Recherche de nouvelles mises a jour apres installation precedente..."
            Start-Sleep -Seconds $postCycleDelay
        }
    }

    if (-not $completed -and -not $rebootRequired -and $cycle -gt $MaxCycles) {
        $timedOut = $true
        $message = "Windows Update non termine apres $MaxCycles cycle(s)."
        Write-Err $message
        Add-LDLCWindowsUpdateTelemetryEvent -Message $message -Severity error -Status 'erreur' -Details $lastError
        Write-ProgressFile $EndPercent "Windows Update incomplet apres $MaxCycles cycle(s)."
    }

    if ($rebootRequired) {
        Add-LDLCWindowsUpdateTelemetryEvent `
            -Message 'Windows Update en pause : redemarrage requis pour continuer les mises a jour. Aucun redemarrage automatique effectue.' `
            -Severity warning `
            -Status 'avertissement'
    }

    return @{
        Success = ($completed -or $rebootRequired)
        RebootRequired = $rebootRequired
        Count = $handledCount
        DownloadedCount = $downloadedCount
        DetectedCount = $detectedTotal
        Skipped = $false
        TimedOut = $timedOut
        BackgroundFallbackStarted = $false
        RemainingCount = $remainingCount
        UsoFallbackUsed = $usoFallbackUsed
        Completed = $completed
        CycleCount = [math]::Min($cycle, $MaxCycles)
        MaxCycles = $MaxCycles
        WarningCount = $warningCount
        FailedCount = $failedCount
        IgnoredFailureCount = $ignoredFailureCount
        StartedActions = @('Search', 'Download', 'Install', 'VerifyLoop')
        FailedActions = @()
        ServicesRunning = @($services.Running)
        ServicesFailed = @($services.Failed)
        LastError = $lastError
    }
}

function Invoke-LDLCWindowsUpdateComInstallLegacy {
    param(
        [int]$StartPercent = 82,
        [int]$EndPercent = 96
    )

    Stop-IfRequested
    Write-Section "WINDOWS UPDATE"
    Write-Step "Mode Windows Update complet active : cycles jusqu'a absence de mises a jour."
    return Install-WindowsUpdates -StartPercent $StartPercent -EndPercent $EndPercent

    if (Test-WindowsUpdateBusy) {
        Write-Warn "Une activite de maintenance Windows semble en cours. Tentative de Windows Update maintenue."
    }

    try {
        $progressSpan = [math]::Max(2, ($EndPercent - $StartPercent))
        $standardDownloadPercent = [int][math]::Min(($EndPercent - 3), ($StartPercent + [math]::Max(1, [int][math]::Floor($progressSpan * 0.25))))
        $standardInstallPercent = [int][math]::Min(($EndPercent - 2), ($StartPercent + [math]::Max(2, [int][math]::Floor($progressSpan * 0.5))))
        $optionalDownloadPercent = [int][math]::Min(($EndPercent - 1), ($StartPercent + [math]::Max(3, [int][math]::Floor($progressSpan * 0.7))))
        $optionalInstallPercent = [int][math]::Min($EndPercent, ($StartPercent + [math]::Max(4, [int][math]::Floor($progressSpan * 0.9))))

        $handledCount = 0
        $rebootRequired = $false
        $remainingCount = 0
        $usoFallbackUsed = $false

        $maxAttempts = Get-LDLCWindowsUpdateMaxAttempts
        $completed = $false
        $lastError = $null
        $lastFailureSummary = $null

        for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
            Stop-IfRequested

            if ($attempt -gt 1) {
                [void](Invoke-LDLCWindowsUpdateRetry -Reason "etat Windows Update incomplet ou bouton Reessayer probable" -Attempt $attempt -MaxAttempts $maxAttempts)
            }

            try {
                $remainingCount = 0
                Write-Step "Tentative Windows Update $attempt/$maxAttempts..."

        Write-ProgressFile $StartPercent "Recherche des mises à jour Windows..."
        Write-Step "Mode Windows Update rapide : facultatives=$($script:WU_InstallOptional), pilotes=$($script:WU_IncludeDrivers), verification finale=$($script:WU_VerifyAfterInstall), tentatives=$maxAttempts."
        [void](Invoke-LDLCDefenderSignatureUpdate)
        [void](Invoke-LDLCUsoClientAction -Action StartScan)

        $standardResult = Invoke-LDLCWindowsUpdateInstallCycle `
            -Label "des mises a jour Windows standard" `
            -DownloadPercent $standardDownloadPercent `
            -InstallPercent $standardInstallPercent `
            -StandardOnly

        $handledCount += $standardResult.Count
        $rebootRequired = ($rebootRequired -or $standardResult.RebootRequired)
        $remainingCount += $standardResult.RemainingCount
        $usoFallbackUsed = ($usoFallbackUsed -or $standardResult.UsoFallbackUsed)

        if ($script:WU_InstallOptional) {
            Stop-IfRequested
            Write-ProgressFile $optionalDownloadPercent "Recherche des mises à jour facultatives..."

            $optionalResult = Invoke-LDLCWindowsUpdateInstallCycle `
                -Label "des mises a jour facultatives" `
                -DownloadPercent $optionalDownloadPercent `
                -InstallPercent $optionalInstallPercent `
                -OptionalOnly

            $handledCount += $optionalResult.Count
            $rebootRequired = ($rebootRequired -or $optionalResult.RebootRequired)
            $remainingCount += $optionalResult.RemainingCount
            $usoFallbackUsed = ($usoFallbackUsed -or $optionalResult.UsoFallbackUsed)
        }
        else {
            Write-Warn "Recherche des mises a jour facultatives desactivee dans la configuration."
        }

                if ($usoFallbackUsed -and -not $rebootRequired -and $attempt -lt $maxAttempts) {
                    $lastError = "Windows Update a necessite une relance systeme pendant la tentative $attempt/$maxAttempts."
                    Add-LDLCWindowsUpdateTelemetryEvent -Message $lastError -Severity warning
                    continue
                }

                $completed = $true
                $lastError = $null
                break
            }
            catch {
                if (Test-LDLCStopRequestError $_) { throw }

                $lastError = $_.Exception.Message
                $lastFailureSummary = Get-LDLCRecentWindowsUpdateFailureSummary
                $detail = if ($lastFailureSummary) { "$lastError`n$lastFailureSummary" } else { $lastError }

                Write-Warn "Windows Update tentative $attempt/$maxAttempts en echec : $lastError"
                Add-LDLCWindowsUpdateTelemetryEvent `
                    -Message "Windows Update tentative $attempt/$maxAttempts en echec : $lastError" `
                    -Severity warning `
                    -Status 'avertissement' `
                    -Details $detail

                if ($attempt -lt $maxAttempts) {
                    continue
                }
            }
        }

        if (-not $completed) {
            $message = if ($lastError) {
                "Windows Update abandonne apres $maxAttempts tentative(s) : $lastError"
            }
            else {
                "Windows Update abandonne apres $maxAttempts tentative(s)."
            }

            Write-Err $message
            Add-LDLCWindowsUpdateTelemetryEvent -Message $message -Severity error -Status 'erreur' -Details $lastFailureSummary
            Write-ProgressFile $EndPercent "Windows Update en erreur, preparation continue."

            return @{
                Success = $false
                RebootRequired = $rebootRequired
                Count = $handledCount
                Skipped = $false
                TimedOut = $false
                BackgroundFallbackStarted = $false
                RemainingCount = $remainingCount
                UsoFallbackUsed = $usoFallbackUsed
            }
        }

        if ($remainingCount -gt 0 -or $usoFallbackUsed) {
            Write-ProgressFile $EndPercent "Windows Update lance, verification manuelle possible."
            Add-LDLCWindowsUpdateTelemetryEvent -Message "Windows Update lance, verification manuelle possible." -Severity warning
        }
        elseif ($handledCount -gt 0) {
            Write-ProgressFile $EndPercent "Mises à jour Windows installées et vérifiées."
        }
        else {
            Write-ProgressFile $EndPercent "Aucune mise à jour Windows à installer."
        }

        return @{
            Success = $true
            RebootRequired = $rebootRequired
            Count = $handledCount
            Skipped = $false
            TimedOut = $false
            BackgroundFallbackStarted = $false
            RemainingCount = $remainingCount
            UsoFallbackUsed = $usoFallbackUsed
        }
    }
    catch {
        Write-Err "Erreur Windows Update : $($_.Exception.Message)"
        Write-ProgressFile $EndPercent "Erreur pendant Windows Update."
        return @{
            Success = $false
            RebootRequired = $false
            Count = 0
            Skipped = $false
            TimedOut = $false
            BackgroundFallbackStarted = $false
            RemainingCount = 0
            UsoFallbackUsed = $false
        }
    }
}

function Start-LDLCWindowsUpdateInBackground {
    param(
        [int]$ProgressPercent = 90,
        [int]$KickoffDelaySeconds = (Get-LDLCWindowsUpdateKickoffDelaySeconds)
    )

    Stop-IfRequested
    Write-ProgressFile $ProgressPercent "Declenchement Windows Update..."
    Write-Step "Declenchement rapide et non bloquant de Windows Update..."

    if (Get-Command Update-LDLCTelemetryRun -ErrorAction SilentlyContinue) {
        Update-LDLCTelemetryRun -Status 'En cours' -Step 'Windows Update' -Message 'Declenchement Windows Update en arriere-plan.' -ProgressPercent $ProgressPercent -Force
    }

    $services = Start-LDLCWindowsUpdateRequiredServices
    $startedSignals = New-Object System.Collections.Generic.List[string]
    $failedSignals = New-Object System.Collections.Generic.List[string]

    if (Invoke-LDLCWuaUcltAction -Action '/detectnow') {
        [void]$startedSignals.Add('wuauclt /detectnow')
    }
    else {
        [void]$failedSignals.Add('wuauclt /detectnow')
    }

    if (Invoke-LDLCWindowsUpdateScheduledTask -TaskPath '\Microsoft\Windows\UpdateOrchestrator\' -TaskName 'Schedule Scan' -Label 'UpdateOrchestrator Schedule Scan') {
        [void]$startedSignals.Add('Schedule Scan')
    }
    else {
        [void]$failedSignals.Add('Schedule Scan')
    }

    if (Invoke-LDLCWindowsUpdateScheduledTask -TaskPath '\Microsoft\Windows\WindowsUpdate\' -TaskName 'Scheduled Start' -Label 'WindowsUpdate Scheduled Start') {
        [void]$startedSignals.Add('Scheduled Start')
    }
    else {
        [void]$failedSignals.Add('Scheduled Start')
    }

    foreach ($action in @('RefreshSettings', 'StartScan')) {
        Stop-IfRequested
        if (Invoke-LDLCUsoClientAction -Action $action -QuietFailure) {
            [void]$startedSignals.Add($action)
        }
        else {
            [void]$failedSignals.Add($action)
        }

    }

    # Les actions sont confiees a Windows sans pause ni verification des mises a jour.
    foreach ($action in @('StartDownload', 'StartInstall')) {
        Stop-IfRequested
        if (Invoke-LDLCUsoClientAction -Action $action -QuietFailure) {
            [void]$startedSignals.Add($action)
        }
        else {
            [void]$failedSignals.Add($action)
        }

    }

    if (Invoke-LDLCWuaUcltAction -Action '/updatenow') {
        [void]$startedSignals.Add('wuauclt /updatenow')
    }
    else {
        [void]$failedSignals.Add('wuauclt /updatenow')
    }

    $startedSignalArray = @($startedSignals.ToArray())
    $failedSignalArray = @($failedSignals.ToArray())
    $runningServiceArray = @($services.Running)
    $startedTriggerArray = @($startedSignalArray | Where-Object { $_ -ne 'RefreshSettings' })

    if ($startedTriggerArray.Count -gt 0) {
        Write-Ok "Windows Update declenche : $($startedSignalArray -join ', ')."
    }

    if ($failedSignalArray.Count -gt 0 -and $startedTriggerArray.Count -gt 0) {
        Write-Info "Windows Update : signaux non confirmes mais non bloquants : $($failedSignalArray -join ', ')."
    }

    if ($startedTriggerArray.Count -eq 0) {
        $message = "Impossible de lancer Windows Update en arriere-plan."
        Write-Err $message
        Add-LDLCWindowsUpdateTelemetryEvent -Message $message -Severity error -Status 'erreur'
        Write-ProgressFile $ProgressPercent "Windows Update non lance, preparation continue."

        return [pscustomobject]@{
            Success = $false
            LastError = $message
            StartedActions = $startedSignalArray
            FailedActions = $failedSignalArray
            ServicesRunning = $runningServiceArray
            ServicesFailed = @($services.Failed)
        }
    }

    Add-LDLCWindowsUpdateTelemetryEvent -Message "Windows Update lance en arriere-plan : $($startedSignalArray -join ', ')." -Severity info -Status 'ok'
    Write-ProgressFile $ProgressPercent "Windows Update lance en arriere-plan."

    return [pscustomobject]@{
        Success = $true
        LastError = ''
        StartedActions = $startedSignalArray
        FailedActions = $failedSignalArray
        ServicesRunning = $runningServiceArray
        ServicesFailed = @($services.Failed)
    }
}

function Start-LDLCWindowsUpdateWorker {
    param(
        [int]$StartPercent = 5,
        [int]$EndPercent = 7
    )

    Stop-IfRequested

    $workerScript = $script:LDLCEmbeddedWorkerScriptPath
    if ([string]::IsNullOrWhiteSpace($workerScript) -or -not (Test-Path -LiteralPath $workerScript -PathType Leaf)) {
        Write-Info 'Worker Windows Update indisponible, declenchement direct utilise.'
        return [pscustomobject]@{
            Success = $false
            ProcessId = 0
            ResultPath = ''
            ProgressPath = ''
            Error = 'Worker indisponible'
        }
    }

    $runtimeRoot = Get-LDLCRuntimeRoot
    $resultPath = Join-Path $runtimeRoot 'LDLC_WINDOWS_UPDATE_RESULT.json'
    $progressPath = Join-Path $runtimeRoot 'LDLC_WINDOWS_UPDATE_PROGRESS.txt'
    Remove-Item -LiteralPath $resultPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $progressPath -Force -ErrorAction SilentlyContinue

    $previousResultPath = $env:LDLC_WU_RESULT_PATH
    $previousProgressPath = $env:LDLC_WU_PROGRESS_PATH
    $previousStartPercent = $env:LDLC_WU_START_PERCENT
    $previousEndPercent = $env:LDLC_WU_END_PERCENT

    try {
        $env:LDLC_WU_RESULT_PATH = $resultPath
        $env:LDLC_WU_PROGRESS_PATH = $progressPath
        $env:LDLC_WU_START_PERCENT = [string]$StartPercent
        $env:LDLC_WU_END_PERCENT = [string]$EndPercent
        # -WindowsUpdateWorker desactive sa propre telemetrie dans le processus enfant.
        # Ne pas desactiver celle du parent pendant Write-ProgressFile.

        $psExe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $quotedWorkerScript = '"' + ($workerScript -replace '"', '\"') + '"'
        $argumentList = "-ExecutionPolicy Bypass -NoProfile -File $quotedWorkerScript -WindowsUpdateWorker"
        $process = Start-Process `
            -FilePath $psExe `
            -ArgumentList $argumentList `
            -WindowStyle Hidden `
            -PassThru `
            -ErrorAction Stop

        Write-Ok "Worker Windows Update lance en arriere-plan (PID $($process.Id))."
        Write-ProgressFile $StartPercent 'Windows Update lance en arriere-plan.'

        return [pscustomobject]@{
            Success = $true
            ProcessId = [int]$process.Id
            ResultPath = $resultPath
            ProgressPath = $progressPath
            Error = ''
        }
    }
    catch {
        Write-Info "Worker Windows Update non lance : $($_.Exception.Message)"
        return [pscustomobject]@{
            Success = $false
            ProcessId = 0
            ResultPath = $resultPath
            ProgressPath = $progressPath
            Error = $_.Exception.Message
        }
    }
    finally {
        if ($null -eq $previousResultPath) { Remove-Item Env:\LDLC_WU_RESULT_PATH -ErrorAction SilentlyContinue } else { $env:LDLC_WU_RESULT_PATH = $previousResultPath }
        if ($null -eq $previousProgressPath) { Remove-Item Env:\LDLC_WU_PROGRESS_PATH -ErrorAction SilentlyContinue } else { $env:LDLC_WU_PROGRESS_PATH = $previousProgressPath }
        if ($null -eq $previousStartPercent) { Remove-Item Env:\LDLC_WU_START_PERCENT -ErrorAction SilentlyContinue } else { $env:LDLC_WU_START_PERCENT = $previousStartPercent }
        if ($null -eq $previousEndPercent) { Remove-Item Env:\LDLC_WU_END_PERCENT -ErrorAction SilentlyContinue } else { $env:LDLC_WU_END_PERCENT = $previousEndPercent }
    }
}

function Install-WindowsUpdates {
    param(
        [int]$StartPercent = 82,
        [int]$EndPercent = 96
    )

    Stop-IfRequested
    try {
        # Le meme point d'entree sert aussi a -WindowsUpdateWorker : il ne lance
        # plus de boucle COM, de recherche finale ou de surveillance des resultats.
        $launch = Start-LDLCWindowsUpdateInBackground -ProgressPercent $StartPercent -KickoffDelaySeconds 0
        if (-not $launch) { throw 'Aucun resultat de declenchement Windows Update retourne.' }
        $message = if ($launch.Success) { 'Windows Update lance en arriere-plan.' } else { 'Windows Update non lance, preparation continue.' }
        Write-ProgressFile $EndPercent $message

        # Champs historiques conserves pour les anciens consommateurs seulement.
        # Completed=false signifie que seule la demande de lancement est connue.
        return @{
            Success = [bool]$launch.Success
            RebootRequired = $false
            Count = 0
            Skipped = $false
            TimedOut = $false
            BackgroundFallbackStarted = $false
            RemainingCount = 0
            UsoFallbackUsed = $false
            Completed = $false
            CycleCount = 0
            MaxCycles = 0
            DownloadedCount = 0
            DetectedCount = 0
            LastError = [string]$launch.LastError
            StartedActions = @($launch.StartedActions)
            FailedActions = @($launch.FailedActions)
            ServicesRunning = @($launch.ServicesRunning)
            ServicesFailed = @($launch.ServicesFailed)
        }
    }
    catch {
        if (Test-LDLCStopRequestError $_) { throw }

        $message = "Erreur au declenchement Windows Update : $($_.Exception.Message)"
        Write-Err $message
        Add-LDLCWindowsUpdateTelemetryEvent -Message $message -Severity error -Status 'erreur'
        Write-ProgressFile $EndPercent "Erreur Windows Update, preparation continue."

        return @{
            Success = $false
            RebootRequired = $false
            Count = 0
            Skipped = $false
            TimedOut = $false
            BackgroundFallbackStarted = $false
            RemainingCount = 0
            UsoFallbackUsed = $false
            Completed = $false
            CycleCount = 0
            MaxCycles = 0
            DownloadedCount = 0
            DetectedCount = 0
            LastError = $message
            StartedActions = @()
            FailedActions = @()
            ServicesRunning = @()
            ServicesFailed = @()
        }
    }
}

# endregion Module: 80.WindowsUpdate.ps1
# Manufacturer utility integration. Payloads are filled at build time, not at UI startup.
$script:LDLCVendorUtilityPayloads = @(
    @{ Path = 'motherboard/MotherboardExperiment.psm1'; Sha256 = 'A9903EC8D9463A1A27524BD3B8F35667D8E49C32021ECCB93FE5FE4CC51322CD'; Base64 = 'I3JlcXVpcmVzIC1WZXJzaW9uIDUuMQ0KU2V0LVN0cmljdE1vZGUgLVZlcnNpb24gMg0KDQpmdW5jdGlvbiBHZXQtTWJ4VmFsdWUgew0KICAgIHBhcmFtKCRPYmplY3QsIFtzdHJpbmddJE5hbWUsICREZWZhdWx0ID0gJycpDQogICAgaWYgKCRudWxsIC1uZSAkT2JqZWN0IC1hbmQgJG51bGwgLW5lICRPYmplY3QuUFNPYmplY3QuUHJvcGVydGllc1skTmFtZV0pIHsgcmV0dXJuICRPYmplY3QuJE5hbWUgfQ0KICAgIHJldHVybiAkRGVmYXVsdA0KfQ0KDQpmdW5jdGlvbiBHZXQtTWJ4VmVuZG9yIHsNCiAgICBwYXJhbShbc3RyaW5nXSROYW1lKQ0KICAgIHN3aXRjaCAtUmVnZXggKCROYW1lLlRyaW0oKSkgew0KICAgICAgICAnXihNaWNyby1TdGFyIEludGVybmF0aW9uYWwoPzogQ29cLiw/IEx0ZFwuPyk/fE1TSSkkJyB7IHJldHVybiAnTVNJJyB9DQogICAgICAgICdeKEFTVVNUZUsgQ09NUFVURVIgSU5DXC4/fEFTVVN8QVNVU1RlSykkJyB7IHJldHVybiAnQVNVUycgfQ0KICAgICAgICAnXihHaWdhYnl0ZSBUZWNobm9sb2d5IENvXC4sPyBMdGRcLj98R0lHQUJZVEUpJCcgeyByZXR1cm4gJ0dJR0FCWVRFJyB9DQogICAgICAgICdeQVNSb2NrKD86IEluY1wuPyk/JCcgeyByZXR1cm4gJ0FTUm9jaycgfQ0KICAgICAgICBkZWZhdWx0IHsgcmV0dXJuICcnIH0NCiAgICB9DQp9DQoNCmZ1bmN0aW9uIFRlc3QtTWJ4UGxhY2Vob2xkZXIgew0KICAgIHBhcmFtKFtzdHJpbmddJFRleHQpDQogICAgcmV0dXJuIChbc3RyaW5nXTo6SXNOdWxsT3JXaGl0ZVNwYWNlKCRUZXh0KSAtb3IgJFRleHQuVHJpbSgpIC1tYXRjaCAnXig/aTpUbyBiZSBmaWxsZWQgYnkgT1wuP0VcLj9NXC4/fERlZmF1bHQgc3RyaW5nfFN5c3RlbSAoUHJvZHVjdCBOYW1lfG1hbnVmYWN0dXJlcnxWZXJzaW9uKXxPRU18VW5rbm93bnxOb3QgKEFwcGxpY2FibGV8U3BlY2lmaWVkKXxOL0F8Tm9uZXxBbGwgU2VyaWVzKSQnKQ0KfQ0KDQpmdW5jdGlvbiBHZXQtTWJ4SW52ZW50b3J5IHsNCiAgICBbQ21kbGV0QmluZGluZygpXQ0KICAgIHBhcmFtKFtWYWxpZGF0ZVJhbmdlKDEsNjApXVtpbnRdJFF1ZXJ5VGltZW91dFNlY29uZHMgPSAxNSkNCiAgICBpZiAoW0Vudmlyb25tZW50XTo6T1NWZXJzaW9uLlBsYXRmb3JtIC1uZSBbUGxhdGZvcm1JRF06OldpbjMyTlQpIHsgdGhyb3cgJ0ludmVudGFpcmUgcmVlbCBkaXNwb25pYmxlIHVuaXF1ZW1lbnQgc291cyBXaW5kb3dzLicgfQ0KICAgICRlcnJvcnMgPSBOZXctT2JqZWN0ICdTeXN0ZW0uQ29sbGVjdGlvbnMuR2VuZXJpYy5MaXN0W29iamVjdF0nDQogICAgJHJlY29yZHMgPSBAe30NCiAgICBmb3JlYWNoICgkY2xhc3MgaW4gQCgnV2luMzJfQmFzZUJvYXJkJywnV2luMzJfQ29tcHV0ZXJTeXN0ZW0nLCdXaW4zMl9TeXN0ZW1FbmNsb3N1cmUnLCdXaW4zMl9CSU9TJywnV2luMzJfT3BlcmF0aW5nU3lzdGVtJywnV2luMzJfUG5QRW50aXR5JywnV2luMzJfUG5QU2lnbmVkRHJpdmVyJykpIHsNCiAgICAgICAgdHJ5IHsNCiAgICAgICAgICAgICRyZWNvcmRzWyRjbGFzc10gPSBAKEdldC1DaW1JbnN0YW5jZSAtQ2xhc3NOYW1lICRjbGFzcyAtT3BlcmF0aW9uVGltZW91dFNlYyAkUXVlcnlUaW1lb3V0U2Vjb25kcyAtRXJyb3JBY3Rpb24gU3RvcCkNCiAgICAgICAgfQ0KICAgICAgICBjYXRjaCB7DQogICAgICAgICAgICAkZXJyb3JzLkFkZChbcHNjdXN0b21vYmplY3RdQHsgQ2xhc3M9JGNsYXNzOyBFcnJvclR5cGU9JF8uRXhjZXB0aW9uLkdldFR5cGUoKS5OYW1lOyBNZXNzYWdlPSRfLkV4Y2VwdGlvbi5NZXNzYWdlIH0pDQogICAgICAgICAgICAkcmVjb3Jkc1skY2xhc3NdPUAoKQ0KICAgICAgICB9DQogICAgfQ0KICAgICRib2FyZHMgPSBAKCRyZWNvcmRzLldpbjMyX0Jhc2VCb2FyZCB8IEZvckVhY2gtT2JqZWN0IHsgW3BzY3VzdG9tb2JqZWN0XUB7DQogICAgICAgIE1hbnVmYWN0dXJlcj1bc3RyaW5nXSRfLk1hbnVmYWN0dXJlcjsgUHJvZHVjdD1bc3RyaW5nXSRfLlByb2R1Y3Q7IFJldmlzaW9uPVtzdHJpbmddJF8uVmVyc2lvbg0KICAgIH0gfSkNCiAgICAkY29tcHV0ZXJzID0gQCgkcmVjb3Jkcy5XaW4zMl9Db21wdXRlclN5c3RlbSB8IEZvckVhY2gtT2JqZWN0IHsgW3BzY3VzdG9tb2JqZWN0XUB7DQogICAgICAgIE1hbnVmYWN0dXJlcj1bc3RyaW5nXSRfLk1hbnVmYWN0dXJlcjsgTW9kZWw9W3N0cmluZ10kXy5Nb2RlbDsgUENTeXN0ZW1UeXBlPSRfLlBDU3lzdGVtVHlwZQ0KICAgIH0gfSkNCiAgICAkb3NlcyA9IEAoJHJlY29yZHMuV2luMzJfT3BlcmF0aW5nU3lzdGVtIHwgRm9yRWFjaC1PYmplY3QgeyBbcHNjdXN0b21vYmplY3RdQHsNCiAgICAgICAgQ2FwdGlvbj1bc3RyaW5nXSRfLkNhcHRpb247IFZlcnNpb249W3N0cmluZ10kXy5WZXJzaW9uOyBCdWlsZE51bWJlcj1bc3RyaW5nXSRfLkJ1aWxkTnVtYmVyOyBBcmNoaXRlY3R1cmU9W3N0cmluZ10kXy5PU0FyY2hpdGVjdHVyZQ0KICAgIH0gfSkNCiAgICAkYmlvcyA9IEAoJHJlY29yZHMuV2luMzJfQklPUyB8IEZvckVhY2gtT2JqZWN0IHsgW3BzY3VzdG9tb2JqZWN0XUB7DQogICAgICAgIE1hbnVmYWN0dXJlcj1bc3RyaW5nXSRfLk1hbnVmYWN0dXJlcjsgU01CSU9TQklPU1ZlcnNpb249W3N0cmluZ10kXy5TTUJJT1NCSU9TVmVyc2lvbjsgVmVyc2lvbj1bc3RyaW5nXSRfLlZlcnNpb247IFJlbGVhc2VEYXRlPVtzdHJpbmddJF8uUmVsZWFzZURhdGUNCiAgICB9IH0pDQogICAgJGRldmljZXMgPSBAKCRyZWNvcmRzLldpbjMyX1BuUEVudGl0eSB8IFdoZXJlLU9iamVjdCB7ICRfLlByZXNlbnQgLW5lICRmYWxzZSAtYW5kICRfLkNvbmZpZ01hbmFnZXJFcnJvckNvZGUgLW5lIDQ1IH0gfCBGb3JFYWNoLU9iamVjdCB7IFtwc2N1c3RvbW9iamVjdF1Aew0KICAgICAgICBOYW1lPVtzdHJpbmddJF8uTmFtZTsgQ2xhc3M9W3N0cmluZ10kXy5QTlBDbGFzczsgRGV2aWNlSUQ9W3N0cmluZ10kXy5EZXZpY2VJRDsgSGFyZHdhcmVJRHM9QCgkXy5IYXJkd2FyZUlEKTsgRXJyb3JDb2RlPSRfLkNvbmZpZ01hbmFnZXJFcnJvckNvZGUNCiAgICB9IH0pDQogICAgJGRyaXZlcnMgPSBAKCRyZWNvcmRzLldpbjMyX1BuUFNpZ25lZERyaXZlciB8IEZvckVhY2gtT2JqZWN0IHsgW3BzY3VzdG9tb2JqZWN0XUB7DQogICAgICAgIE5hbWU9W3N0cmluZ10kXy5EZXZpY2VOYW1lOyBDbGFzcz1bc3RyaW5nXSRfLkRldmljZUNsYXNzOyBEZXZpY2VJRD1bc3RyaW5nXSRfLkRldmljZUlEOyBWZXJzaW9uPVtzdHJpbmddJF8uRHJpdmVyVmVyc2lvbg0KICAgICAgICBQcm92aWRlcj1bc3RyaW5nXSRfLkRyaXZlclByb3ZpZGVyTmFtZTsgSXNTaWduZWQ9W2Jvb2xdJF8uSXNTaWduZWQ7IEluZj1bc3RyaW5nXSRfLkluZk5hbWU7IERyaXZlckRhdGU9W3N0cmluZ10kXy5Ecml2ZXJEYXRlDQogICAgfSB9KQ0KICAgICMgUmVnaXN0cnkgcmVhZHMgb25seTsgV2luMzJfUHJvZHVjdCBpcyBkZWxpYmVyYXRlbHkgbm90IHVzZWQgKE1TSSByZXBhaXIgc2lkZSBlZmZlY3RzKS4NCiAgICAkdXRpbGl0aWVzID0gQCgpDQogICAgZm9yZWFjaCAoJHBhdGggaW4gQCgnSEtMTTpcU09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3NcQ3VycmVudFZlcnNpb25cVW5pbnN0YWxsXConLCdIS0xNOlxTT0ZUV0FSRVxXT1c2NDMyTm9kZVxNaWNyb3NvZnRcV2luZG93c1xDdXJyZW50VmVyc2lvblxVbmluc3RhbGxcKicsJ0hLQ1U6XFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzXEN1cnJlbnRWZXJzaW9uXFVuaW5zdGFsbFwqJykpIHsNCiAgICAgICAgJHV0aWxpdGllcyArPSBAKEdldC1JdGVtUHJvcGVydHkgLVBhdGggJHBhdGggLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBXaGVyZS1PYmplY3Qgew0KICAgICAgICAgICAgKEdldC1NYnhWYWx1ZSAkXyAnRGlzcGxheU5hbWUnKSAtbWF0Y2ggJyg/aSlNU0kgQ2VudGVyfEFTVVMgRHJpdmVySHVifEdJR0FCWVRFIENvbnRyb2wgQ2VudGVyfEFTUm9jayAoQVBQIFNob3B8QXV0byBEcml2ZXIgSW5zdGFsbGVyKScNCiAgICAgICAgfSB8IEZvckVhY2gtT2JqZWN0IHsgW3BzY3VzdG9tb2JqZWN0XUB7IE5hbWU9W3N0cmluZ10kXy5EaXNwbGF5TmFtZTsgVmVyc2lvbj1bc3RyaW5nXShHZXQtTWJ4VmFsdWUgJF8gJ0Rpc3BsYXlWZXJzaW9uJyk7IFB1Ymxpc2hlcj1bc3RyaW5nXShHZXQtTWJ4VmFsdWUgJF8gJ1B1Ymxpc2hlcicpOyBFdmlkZW5jZT0ndW5pbnN0YWxsIHJlZ2lzdHJ5IGVudHJ5IG9ubHknIH0gfSkNCiAgICB9DQogICAgcmV0dXJuIFtwc2N1c3RvbW9iamVjdF1Aew0KICAgICAgICBLaW5kPSdSZWFsQ2ltSW52ZW50b3J5JzsgQ2FwdHVyZWRVdGM9W0RhdGVUaW1lXTo6VXRjTm93LlRvU3RyaW5nKCdvJyk7IEJhc2VCb2FyZHM9JGJvYXJkczsgQ29tcHV0ZXJzPSRjb21wdXRlcnM7IE9wZXJhdGluZ1N5c3RlbXM9JG9zZXM7IEJpb3M9JGJpb3MNCiAgICAgICAgQ2hhc3Npc1R5cGVzPUAoJHJlY29yZHMuV2luMzJfU3lzdGVtRW5jbG9zdXJlIHwgRm9yRWFjaC1PYmplY3QgeyAkXy5DaGFzc2lzVHlwZXMgfSkNCiAgICAgICAgRGV2aWNlcz0kZGV2aWNlczsgRHJpdmVycz0kZHJpdmVyczsgSW5zdGFsbGVkVXRpbGl0eUVudHJpZXM9JHV0aWxpdGllcw0KICAgICAgICBDaGlwc2V0RXZpZGVuY2U9QCgkZGV2aWNlcyB8IFdoZXJlLU9iamVjdCB7ICRfLkNsYXNzIC1lcSAnU3lzdGVtJyAtYW5kICRfLk5hbWUgLW1hdGNoICcoP2kpY2hpcHNldHxTTUJ1c3xob3N0IGJyaWRnZXxMUEN8SVNBIGJyaWRnZScgfSkNCiAgICAgICAgQ2hpcHNldENlcnRhaW50eT0nUG5QIGV2aWRlbmNlIG9ubHk7IGV4YWN0IGNoaXBzZXQgbWF5IGJlIHVuYXZhaWxhYmxlJzsgRXJyb3JzPUAoJGVycm9ycy5Ub0FycmF5KCkpDQogICAgfQ0KfQ0KDQpmdW5jdGlvbiBHZXQtTWJ4VG9vbERlZmluaXRpb25zIHsNCiAgICByZXR1cm4gQCgNCiAgICAgICAgW3BzY3VzdG9tb2JqZWN0XUB7IFZlbmRvcj0nTVNJJzsgVG9vbD0nTVNJIENlbnRlcic7IFBhZ2U9J2h0dHBzOi8vd3d3Lm1zaS5jb20vTGFuZGluZy9NU0ktQ2VudGVyJzsgSG9zdHM9QCgnbXNpLmNvbScpOyBGaWxlUGF0dGVybj0nKD9pKV5NU0lbXyAtXT9DZW50ZXJbXi9dKlwuKHppcHxleGUpJCc7IFNpZ25lcnM9QCgnTWljcm8tU3RhciBJbnRlcm5hdGlvbmFsIENvLiwgTHRkLicsJ01JQ1JPLVNUQVIgSU5URVJOQVRJT05BTCBDTy4sIExURC4nKTsgRHJpdmVyQ2xpPSdOb3RDb25maXJtZWQnOyBOb3RlPSdNU0kgRHJpdmVyIFV0aWxpdHkgSW5zdGFsbGVyIGlzIGEgc2VwYXJhdGUgbW90aGVyYm9hcmQvVUVGSSBmZWF0dXJlLCBub3QgYSB1bml2ZXJzYWwgc2lsZW50IGRyaXZlciBDTEkuJyB9LA0KICAgICAgICBbcHNjdXN0b21vYmplY3RdQHsgVmVuZG9yPSdBU1VTJzsgVG9vbD0nQVNVUyBEcml2ZXJIdWInOyBQYWdlPSdodHRwczovL2RyaXZlcmh1Yi5hc3VzLmNvbS9lbic7IEhvc3RzPUAoJ2FzdXMuY29tJyk7IEZpbGVQYXR0ZXJuPScoP2kpXihBU1VTW18gLV0/KT9Ecml2ZXJIdWJbXi9dKlwuKHppcHxleGUpJCc7IFNpZ25lcnM9QCgnQVNVU1RlSyBDT01QVVRFUiBJTkMuJyk7IERyaXZlckNsaT0nTm90Q29uZmlybWVkJzsgTm90ZT0nRG8gbm90IHRyZWF0IGFuIGluc3RhbGxlciBzaWxlbnQgZmxhZyBhcyBhIGRvY3VtZW50ZWQgZHJpdmVyIHNjYW4gb3IgYXBwbHkgY29tbWFuZC4nIH0sDQogICAgICAgIFtwc2N1c3RvbW9iamVjdF1AeyBWZW5kb3I9J0dJR0FCWVRFJzsgVG9vbD0nR0lHQUJZVEUgQ29udHJvbCBDZW50ZXInOyBQYWdlPSdodHRwczovL3d3dy5naWdhYnl0ZS5jb20vQ29uc3VtZXIvU29mdHdhcmUvR0lHQUJZVEUtQ29udHJvbC1DZW50ZXIvZ2xvYmFsLyc7IEhvc3RzPUAoJ2dpZ2FieXRlLmNvbScpOyBGaWxlUGF0dGVybj0nKD9pKV4oR0NDfEdJR0FCWVRFWy1fIF0/Q29udHJvbFstXyBdP0NlbnRlcnxtYl91dGlsaXR5X2djYylbXi9dKlwuKHppcHxleGUpJCc7IFNpZ25lcnM9QCgnR0lHQS1CWVRFIFRFQ0hOT0xPR1kgQ08uLCBMVEQuJywnR0lHQUJZVEUgVEVDSE5PTE9HWSBDTy4sIExURC4nKTsgRHJpdmVyQ2xpPSdOb3RDb25maXJtZWQnOyBOb3RlPSdBcHAgc2VsZWN0aW9uLCBmaXJtd2FyZSBhbmQgb3B0aW9uYWwgc29mdHdhcmUgbmVlZCBleHBsaWNpdCBjb250cm9sIGluIHRoZSB2ZW5kb3IgVUkuJyB9LA0KICAgICAgICBbcHNjdXN0b21vYmplY3RdQHsgVmVuZG9yPSdBU1JvY2snOyBUb29sPSdBUFAgU2hvcCAvIEF1dG8gRHJpdmVyIEluc3RhbGxlciAobW9kZWwgZGVwZW5kZW50KSc7IFBhZ2U9J2h0dHBzOi8vd3d3LmFzcm9jay5jb20vZmVhdHVyZS9hcHBzaG9wLyc7IEhvc3RzPUAoJ2Fzcm9jay5jb20nKTsgRmlsZVBhdHRlcm49Jyg/ISknOyBTaWduZXJzPUAoJ0FTUm9jayBJbmMuJyk7IERyaXZlckNsaT0nTm90Q29uZmlybWVkJzsgTm90ZT0nQVBQIFNob3AgaXMgYSBVSSB3aXRoIGRyaXZlciwgQklPUyBhbmQgYXBwIGNob2ljZXMuIEF1dG8gRHJpdmVyIEluc3RhbGxlciBpcyBmaXJtd2FyZS9tb2RlbCBkZXBlbmRlbnQ7IG5vIGd1ZXNzZWQgdW5pdmVyc2FsIHBhY2thZ2UuJyB9DQogICAgKQ0KfQ0KDQpmdW5jdGlvbiBSZXNvbHZlLU1ieFRvb2wgew0KICAgIFtDbWRsZXRCaW5kaW5nKCldDQogICAgcGFyYW0oW1BhcmFtZXRlcihNYW5kYXRvcnkpXSRJbnZlbnRvcnksIFtvYmplY3RbXV0kU3VwcG9ydEV2aWRlbmNlID0gQCgpKQ0KICAgICRyZXN1bHQ9W29yZGVyZWRdQHsgU3RhdHVzPSdtYW51YWxfcmVxdWlyZWQnOyBWZW5kb3I9Jyc7IEJvYXJkTW9kZWw9Jyc7IEJvYXJkUmV2aXNpb249Jyc7IFRvb2w9Jyc7IE9mZmljaWFsUGFnZT0nJzsgQ29tcGF0aWJpbGl0eT0ndW52ZXJpZmllZCc7IFJlYXNvbj0nJzsgQ2FuRG93bmxvYWRGb3JJbnN0YWxsYXRpb249JGZhbHNlOyBDYW5TY2FuQXV0b21hdGljYWxseT0kZmFsc2U7IENhbkluc3RhbGxEcml2ZXJzQXV0b21hdGljYWxseT0kZmFsc2UgfQ0KICAgICRib2FyZHM9QChHZXQtTWJ4VmFsdWUgJEludmVudG9yeSAnQmFzZUJvYXJkcycgQCgpKQ0KICAgICRjb21wdXRlcnM9QChHZXQtTWJ4VmFsdWUgJEludmVudG9yeSAnQ29tcHV0ZXJzJyBAKCkpDQogICAgJG9zPUAoR2V0LU1ieFZhbHVlICRJbnZlbnRvcnkgJ09wZXJhdGluZ1N5c3RlbXMnIEAoKSkNCiAgICBpZiAoJGJvYXJkcy5Db3VudCAtbmUgMSAtb3IgJGNvbXB1dGVycy5Db3VudCAtbmUgMSAtb3IgJG9zLkNvdW50IC1uZSAxKSB7DQogICAgICAgICRyZXN1bHQuUmVhc29uPSdJbnZlbnRhaXJlIGFic2VudCwgcGFydGllbCBvdSBhbWJpZ3UgKGNhcnRlIG1lcmUsIGNvbnN0cnVjdGV1ciBkdSBQQyBvdSBXaW5kb3dzKS4nOyByZXR1cm4gW3BzY3VzdG9tb2JqZWN0XSRyZXN1bHQNCiAgICB9DQogICAgJGJvYXJkPSRib2FyZHNbMF07ICRwYz0kY29tcHV0ZXJzWzBdDQogICAgJHJlc3VsdC5WZW5kb3I9R2V0LU1ieFZlbmRvciAoW3N0cmluZ10oR2V0LU1ieFZhbHVlICRib2FyZCAnTWFudWZhY3R1cmVyJykpDQogICAgJHJlc3VsdC5Cb2FyZE1vZGVsPVtzdHJpbmddKEdldC1NYnhWYWx1ZSAkYm9hcmQgJ1Byb2R1Y3QnKQ0KICAgICRyZXN1bHQuQm9hcmRSZXZpc2lvbj1bc3RyaW5nXShHZXQtTWJ4VmFsdWUgJGJvYXJkICdSZXZpc2lvbicpDQogICAgJHBjTWFudWZhY3R1cmVyPVtzdHJpbmddKEdldC1NYnhWYWx1ZSAkcGMgJ01hbnVmYWN0dXJlcicpOyAkcGNNb2RlbD1bc3RyaW5nXShHZXQtTWJ4VmFsdWUgJHBjICdNb2RlbCcpDQogICAgaWYgKCgkcGNNYW51ZmFjdHVyZXIrJyAnKyRwY01vZGVsKSAtbWF0Y2ggJyg/aSlNaWNyb3NvZnQgQ29ycG9yYXRpb24uKlZpcnR1YWwgTWFjaGluZXxWTXdhcmV8VmlydHVhbEJveHxLVk18UUVNVXxYZW58QW1hem9uIEVDMnxHb29nbGUgQ29tcHV0ZScpIHsNCiAgICAgICAgJHJlc3VsdC5SZWFzb249J01hY2hpbmUgdmlydHVlbGxlIDogYXVjdW4gdXRpbGl0YWlyZSBkZSBjYXJ0ZSBtZXJlIHBoeXNpcXVlIHNlbGVjdGlvbm5lLic7IHJldHVybiBbcHNjdXN0b21vYmplY3RdJHJlc3VsdA0KICAgIH0NCiAgICBpZiAoLW5vdCAkcmVzdWx0LlZlbmRvcikgeyAkcmVzdWx0LlJlYXNvbj0nRmFicmljYW50IGRlIGNhcnRlIG1lcmUgaW5jb25udSA6IHV0aWxpc2VyIGxlIHN1cHBvcnQgZHUgY29uc3RydWN0ZXVyIGR1IFBDLic7IHJldHVybiBbcHNjdXN0b21vYmplY3RdJHJlc3VsdCB9DQogICAgJHBjVmVuZG9yPUdldC1NYnhWZW5kb3IgJHBjTWFudWZhY3R1cmVyDQogICAgaWYgKC1ub3QgKFRlc3QtTWJ4UGxhY2Vob2xkZXIgJHBjTWFudWZhY3R1cmVyKSAtYW5kICRwY1ZlbmRvciAtbmUgJHJlc3VsdC5WZW5kb3IpIHsNCiAgICAgICAgJHJlc3VsdC5SZWFzb249IlBDIE9FTSAoJHBjTWFudWZhY3R1cmVyIC8gJHBjTW9kZWwpIDogbGUgc3VwcG9ydCBkdSBQQyBwcmltZSBzdXIgbGUgZmFicmljYW50IGRlIGxhIGNhcnRlIG1lcmUuIjsgcmV0dXJuIFtwc2N1c3RvbW9iamVjdF0kcmVzdWx0DQogICAgfQ0KICAgICRwb3J0YWJsZT1AKEdldC1NYnhWYWx1ZSAkSW52ZW50b3J5ICdDaGFzc2lzVHlwZXMnIEAoKSB8IFdoZXJlLU9iamVjdCB7ICRfIC1pbiBAKDgsOSwxMCwxMSwxMiwxNCwzMCwzMSwzMikgfSkuQ291bnQgLWd0IDANCiAgICBpZiAoJHBvcnRhYmxlIC1vciAoR2V0LU1ieFZhbHVlICRwYyAnUENTeXN0ZW1UeXBlJyAwKSAtZXEgMikgew0KICAgICAgICAkcmVzdWx0LlJlYXNvbj0nUG9ydGFibGUgOiB1biBvdXRpbCBkZSBjYXJ0ZSBtZXJlIGRlIGJ1cmVhdSBuZSBwcm91dmUgcGFzIHNhIGNvbXBhdGliaWxpdGUgYXZlYyBjZSBtb2RlbGUgT0VNLic7IHJldHVybiBbcHNjdXN0b21vYmplY3RdJHJlc3VsdA0KICAgIH0NCiAgICAkdG9vbD1AKEdldC1NYnhUb29sRGVmaW5pdGlvbnMgfCBXaGVyZS1PYmplY3QgeyAkXy5WZW5kb3IgLWVxICRyZXN1bHQuVmVuZG9yIH0pWzBdDQogICAgJHJlc3VsdC5Ub29sPSR0b29sLlRvb2w7ICRyZXN1bHQuT2ZmaWNpYWxQYWdlPSR0b29sLlBhZ2UNCiAgICBpZiAoKFRlc3QtTWJ4UGxhY2Vob2xkZXIgJHJlc3VsdC5Cb2FyZE1vZGVsKSAtb3IgKFRlc3QtTWJ4UGxhY2Vob2xkZXIgJHJlc3VsdC5Cb2FyZFJldmlzaW9uKSkgew0KICAgICAgICAkcmVzdWx0LlJlYXNvbj0nTW9kZWxlIG91IHJldmlzaW9uIFNNQklPUyBhYnNlbnQgOiBjb21wYXRpYmlsaXRlIGV4YWN0ZSBub24gcHJvdXZlZS4nOyByZXR1cm4gW3BzY3VzdG9tb2JqZWN0XSRyZXN1bHQNCiAgICB9DQogICAgJG1hdGNoZXM9QCgkU3VwcG9ydEV2aWRlbmNlIHwgV2hlcmUtT2JqZWN0IHsNCiAgICAgICAgKEdldC1NYnhWYWx1ZSAkXyAnVmVuZG9yJykgLWVxICRyZXN1bHQuVmVuZG9yIC1hbmQNCiAgICAgICAgKEdldC1NYnhWYWx1ZSAkXyAnTW9kZWwnKSAtaWVxICRyZXN1bHQuQm9hcmRNb2RlbCAtYW5kDQogICAgICAgIChHZXQtTWJ4VmFsdWUgJF8gJ1JldmlzaW9uJykgLWllcSAkcmVzdWx0LkJvYXJkUmV2aXNpb24gLWFuZA0KICAgICAgICAoR2V0LU1ieFZhbHVlICRfICdPc0J1aWxkJykgLWVxIFtzdHJpbmddKEdldC1NYnhWYWx1ZSAkb3NbMF0gJ0J1aWxkTnVtYmVyJykgLWFuZA0KICAgICAgICAoR2V0LU1ieFZhbHVlICRfICdBcmNoaXRlY3R1cmUnKSAtZXEgW3N0cmluZ10oR2V0LU1ieFZhbHVlICRvc1swXSAnQXJjaGl0ZWN0dXJlJykgLWFuZA0KICAgICAgICAoR2V0LU1ieFZhbHVlICRfICdFeHBsaWNpdFN1cHBvcnQnICRmYWxzZSkgLWVxICR0cnVlIC1hbmQNCiAgICAgICAgKFRlc3QtTWJ4T2ZmaWNpYWxVcmkgKFtzdHJpbmddKEdldC1NYnhWYWx1ZSAkXyAnU291cmNlJykpICR0b29sLkhvc3RzKQ0KICAgIH0pDQogICAgaWYgKCRtYXRjaGVzLkNvdW50IC1uZSAxKSB7DQogICAgICAgICRyZXN1bHQuUmVhc29uPSdPdXRpbCBjYW5kaWRhdCBpZGVudGlmaWUgOyBhdWN1bmUgcHJldXZlIGFjdHVlbGxlIGRlIGNvbXBhdGliaWxpdGUgZXhhY3RlIG1vZGVsZS9yZXZpc2lvbi9XaW5kb3dzLiBWZXJpZmljYXRpb24gbWFudWVsbGUgcmVxdWlzZS4nDQogICAgICAgIHJldHVybiBbcHNjdXN0b21vYmplY3RdJHJlc3VsdA0KICAgIH0NCiAgICAjIEluamVjdGVkIGV2aWRlbmNlIGlzIHVzZWZ1bCB0byB0ZXN0IHNlbGVjdGlvbiwgbm90IGEgbGl2ZSBjb21wYXRpYmlsaXR5IGRlY2xhcmF0aW9uLg0KICAgICRyZXN1bHQuQ29tcGF0aWJpbGl0eT0nZXZpZGVuY2Vfc3VwcGxpZWRfcmVxdWlyZXNfdmVuZG9yX2NvbmZpcm1hdGlvbicNCiAgICAkcmVzdWx0LlJlYXNvbj0nQ29ycmVzcG9uZGFuY2UgZXhhY3RlIGRhbnMgbGVzIGRvbm5lZXMgZm91cm5pZXMgOyBjb25maXJtZXIgc3VyIGxlIHN1cHBvcnQgb2ZmaWNpZWwgZHUgbW9kZWxlIGF2YW50IGluc3RhbGxhdGlvbi4nDQogICAgcmV0dXJuIFtwc2N1c3RvbW9iamVjdF0kcmVzdWx0DQp9DQoNCmZ1bmN0aW9uIENvbnZlcnRUby1NYnhWZXJzaW9uIHsNCiAgICBwYXJhbShbc3RyaW5nXSRWYWx1ZSkNCiAgICBpZiAoJFZhbHVlIC1ub3RtYXRjaCAnXlxkKyg/OlwuXGQrKXswLDN9JCcpIHsgcmV0dXJuICRudWxsIH0NCiAgICB0cnkgew0KICAgICAgICAkcGFydHM9QCgkVmFsdWUuU3BsaXQoJy4nKSk7IHdoaWxlICgkcGFydHMuQ291bnQgLWx0IDQpIHsgJHBhcnRzKz0nMCcgfQ0KICAgICAgICByZXR1cm4gW3ZlcnNpb25dKCRwYXJ0cyAtam9pbiAnLicpDQogICAgfSBjYXRjaCB7IHJldHVybiAkbnVsbCB9DQp9DQoNCmZ1bmN0aW9uIFNlbGVjdC1NYnhEcml2ZXJDYW5kaWRhdGVzIHsNCiAgICBbQ21kbGV0QmluZGluZygpXQ0KICAgIHBhcmFtKFtvYmplY3RbXV0kQ2FuZGlkYXRlcz1AKCksIFtvYmplY3RbXV0kRGV2aWNlcz1AKCksIFtvYmplY3RbXV0kSW5zdGFsbGVkRHJpdmVycz1AKCkpDQogICAgJHJlc3VsdHM9QCgpDQogICAgZm9yZWFjaCAoJGl0ZW0gaW4gJENhbmRpZGF0ZXMpIHsNCiAgICAgICAgJG5hbWU9W3N0cmluZ10oR2V0LU1ieFZhbHVlICRpdGVtICdOYW1lJyk7ICRraW5kPVtzdHJpbmddKEdldC1NYnhWYWx1ZSAkaXRlbSAnS2luZCcpDQogICAgICAgICRzdGF0dXM9J2lnbm9yZWQnOyAkcmVhc29uPSdUeXBlIG5vbiBhdXRvcmlzZSA6IGF1Y3VuIGxvZ2ljaWVsIGFkZGl0aW9ubmVsIHNlbGVjdGlvbm5lLicNCiAgICAgICAgaWYgKCgkbmFtZSsnICcrJGtpbmQpIC1tYXRjaCAnKD9pKWFudGl2aXJ1c3xhbnRpWy0gXT9tYWx3YXJlfHNlY3VyaXR5IHN1aXRlfGludGVybmV0IHNlY3VyaXR5fE5vcnRvbnxNY0FmZWV8QXZhc3R8QVZHfEthc3BlcnNreXxCaXRkZWZlbmRlcnxFU0VUfFRyZW5kIE1pY3JvfEJ1bGxHdWFyZHxTeW1hbnRlY3xwcm90ZWN0aW9ufERlZmVuZGVyJykgew0KICAgICAgICAgICAgJHJlYXNvbj0nTG9naWNpZWwgZGUgcHJvdGVjdGlvbiBleGNsdSBkZSBsYSBzZWxlY3Rpb24gY29uc3RydWN0ZXVyIDsgYXVjdW5lIG1vZGlmaWNhdGlvbiBkZSBEZWZlbmRlciBvdSBXaW5kb3dzIFVwZGF0ZS4nDQogICAgICAgIH0NCiAgICAgICAgZWxzZWlmICgoJG5hbWUrJyAnKyRraW5kKSAtbWF0Y2ggJyg/aSlCSU9TfFVFRkl8ZmlybXdhcmUnKSB7ICRzdGF0dXM9J2Zpcm13YXJlX21hbnVhbCc7ICRyZWFzb249J0JJT1MvVUVGSS9maXJtd2FyZSA6IHZhbGlkYXRpb24gZXhwbGljaXRlIGR1IHRlY2huaWNpZW4sIGF1Y3VuZSBleGVjdXRpb24uJyB9DQogICAgICAgIGVsc2VpZiAoJGtpbmQgLWVxICdEcml2ZXInKSB7DQogICAgICAgICAgICAkY2xhc3M9W3N0cmluZ10oR2V0LU1ieFZhbHVlICRpdGVtICdDbGFzcycpDQogICAgICAgICAgICBpZiAoJGNsYXNzIC1lcSAnRGlzcGxheScgLW9yICRuYW1lIC1tYXRjaCAnKD9pKUFkcmVuYWxpbnxHZUZvcmNlfFJhZGVvbnxOVklESUEuKihkcml2ZXJ8ZGlzcGxheSknKSB7ICRyZWFzb249J1BpbG90ZSBHUFUgcmVzZXJ2ZSBhdSBtZWNhbmlzbWUgQU1EL05WSURJQSBleGlzdGFudC4nIH0NCiAgICAgICAgICAgIGVsc2VpZiAoJGNsYXNzIC1ub3RpbiBAKCdTeXN0ZW0nLCdOZXQnLCdCbHVldG9vdGgnLCdNRURJQScsJ1VTQicsJ0hEQycsJ1NDU0lBZGFwdGVyJywnU3RvcmFnZScpKSB7ICRyZWFzb249J0NsYXNzZSBkZSBwaWxvdGUgaG9ycyBwZXJpbWV0cmUuJyB9DQogICAgICAgICAgICBlbHNlIHsNCiAgICAgICAgICAgICAgICAkaWRzPUAoR2V0LU1ieFZhbHVlICRpdGVtICdIYXJkd2FyZUlEcycgQCgpKQ0KICAgICAgICAgICAgICAgICRtYXRjaGVkPUAoJERldmljZXMgfCBXaGVyZS1PYmplY3QgeyAkZGV2PSRfOyBAKChHZXQtTWJ4VmFsdWUgJGRldiAnSGFyZHdhcmVJRHMnIEAoKSkgfCBXaGVyZS1PYmplY3QgeyAkaWRzIC1jb250YWlucyAkXyB9KS5Db3VudCAtZ3QgMCB9KQ0KICAgICAgICAgICAgICAgIGlmICgtbm90ICRpZHMuQ291bnQgLW9yICRtYXRjaGVkLkNvdW50IC1uZSAxKSB7ICRzdGF0dXM9J21hbnVhbF9yZXF1aXJlZCc7ICRyZWFzb249J0lkZW50aWZpYW50cyBtYXRlcmllbHMgYWJzZW50cyBvdSBjb3JyZXNwb25kYW5jZSBhbWJpZ3VlLicgfQ0KICAgICAgICAgICAgICAgIGVsc2Ugew0KICAgICAgICAgICAgICAgICAgICAkaW5zdGFsbGVkPUAoJEluc3RhbGxlZERyaXZlcnMgfCBXaGVyZS1PYmplY3QgeyAoR2V0LU1ieFZhbHVlICRfICdEZXZpY2VJRCcpIC1lcSAoR2V0LU1ieFZhbHVlICRtYXRjaGVkWzBdICdEZXZpY2VJRCcpIH0pDQogICAgICAgICAgICAgICAgICAgICRvZmZlcmVkPUNvbnZlcnRUby1NYnhWZXJzaW9uIChbc3RyaW5nXShHZXQtTWJ4VmFsdWUgJGl0ZW0gJ1ZlcnNpb24nKSkNCiAgICAgICAgICAgICAgICAgICAgJGN1cnJlbnQ9JG51bGwNCiAgICAgICAgICAgICAgICAgICAgaWYgKCRpbnN0YWxsZWQuQ291bnQgLWVxIDEpIHsgJGN1cnJlbnQ9Q29udmVydFRvLU1ieFZlcnNpb24gKFtzdHJpbmddKEdldC1NYnhWYWx1ZSAkaW5zdGFsbGVkWzBdICdWZXJzaW9uJykpIH0NCiAgICAgICAgICAgICAgICAgICAgJHByb3ZpZGVyPVtzdHJpbmddKEdldC1NYnhWYWx1ZSAkaXRlbSAnUHJvdmlkZXInKQ0KICAgICAgICAgICAgICAgICAgICBpZiAoLW5vdCAkY3VycmVudCAtb3IgLW5vdCAkb2ZmZXJlZCAtb3IgJGluc3RhbGxlZC5Db3VudCAtbmUgMSAtb3IgW3N0cmluZ106OklzTnVsbE9yV2hpdGVTcGFjZSgkcHJvdmlkZXIpIC1vciAkcHJvdmlkZXIgLWluZSBbc3RyaW5nXShHZXQtTWJ4VmFsdWUgJGluc3RhbGxlZFswXSAnUHJvdmlkZXInKSkgew0KICAgICAgICAgICAgICAgICAgICAgICAgJHN0YXR1cz0nbWFudWFsX3JlcXVpcmVkJzsgJHJlYXNvbj0nVmVyc2lvbnMgb3UgZm91cm5pc3NldXIgbm9uIGNvbXBhcmFibGVzIDsgYXVjdW5lIG1pc2UgYSBuaXZlYXUgYW5ub25jZWUuJw0KICAgICAgICAgICAgICAgICAgICB9DQogICAgICAgICAgICAgICAgICAgIGVsc2VpZiAoJG9mZmVyZWQgLWxlICRjdXJyZW50KSB7ICRzdGF0dXM9J3VwX3RvX2RhdGUnOyAkcmVhc29uPSdWZXJzaW9uIHByb3Bvc2VlIGVnYWxlIG91IGFudGVyaWV1cmUgOiBhdWN1bmUgcmV0cm9ncmFkYXRpb24uJyB9DQogICAgICAgICAgICAgICAgICAgIGVsc2UgeyAkc3RhdHVzPSdjYW5kaWRhdGVfb25seSc7ICRyZWFzb249J1ZlcnNpb24gbnVtZXJpcXVlIHBsdXMgcmVjZW50ZSBwb3VyIGxlIG1lbWUgbWF0ZXJpZWwvZm91cm5pc3NldXIgOyBpbnN0YWxsYXRpb24gbm9uIHJlYWxpc2VlIG5pIGF1dG9yaXNlZSBwYXIgY2UgcHJvdG90eXBlLicgfQ0KICAgICAgICAgICAgICAgIH0NCiAgICAgICAgICAgIH0NCiAgICAgICAgfQ0KICAgICAgICAkcmVzdWx0cys9W3BzY3VzdG9tb2JqZWN0XUB7IE5hbWU9JG5hbWU7IFN0YXR1cz0kc3RhdHVzOyBSZWFzb249JHJlYXNvbjsgSW5zdGFsbGVkPSRmYWxzZTsgUmVib290SW5pdGlhdGVkPSRmYWxzZSB9DQogICAgfQ0KICAgIHJldHVybiAkcmVzdWx0cw0KfQ0KDQpmdW5jdGlvbiBUZXN0LU1ieE9mZmljaWFsVXJpIHsNCiAgICBwYXJhbShbc3RyaW5nXSRVcmwsIFtzdHJpbmdbXV0kSG9zdHMpDQogICAgdHJ5IHsNCiAgICAgICAgJHU9W3VyaV0kVXJsDQogICAgICAgIGlmICgtbm90ICR1LklzQWJzb2x1dGVVcmkgLW9yICR1LlNjaGVtZSAtbmUgJ2h0dHBzJyAtb3IgJHUuUG9ydCAtbmUgNDQzIC1vciAkdS5Vc2VySW5mbykgeyByZXR1cm4gJGZhbHNlIH0NCiAgICAgICAgZm9yZWFjaCAoJGggaW4gJEhvc3RzKSB7IGlmICgkdS5EbnNTYWZlSG9zdCAtaWVxICRoIC1vciAkdS5EbnNTYWZlSG9zdC5FbmRzV2l0aCgnLicrJGgsW1N0cmluZ0NvbXBhcmlzb25dOjpPcmRpbmFsSWdub3JlQ2FzZSkpIHsgcmV0dXJuICR0cnVlIH0gfQ0KICAgIH0gY2F0Y2gge30NCiAgICByZXR1cm4gJGZhbHNlDQp9DQoNCmZ1bmN0aW9uIE5ldy1NYnhIdHRwSGFuZGxlciB7DQogICAgJGhhbmRsZXI9TmV3LU9iamVjdCBOZXQuSHR0cC5IdHRwQ2xpZW50SGFuZGxlcg0KICAgICRoYW5kbGVyLkFsbG93QXV0b1JlZGlyZWN0PSRmYWxzZQ0KICAgIHJldHVybiAkaGFuZGxlcg0KfQ0KDQpmdW5jdGlvbiBJbnZva2UtTWJ4SHR0cCB7DQogICAgW0NtZGxldEJpbmRpbmcoKV0NCiAgICBwYXJhbShbUGFyYW1ldGVyKE1hbmRhdG9yeSldW3N0cmluZ10kVXJsLCBbUGFyYW1ldGVyKE1hbmRhdG9yeSldW3N0cmluZ1tdXSRIb3N0cywNCiAgICAgICAgW1ZhbGlkYXRlUmFuZ2UoMSw2MDApXVtpbnRdJFRpbWVvdXRTZWNvbmRzPTMwLCBbVmFsaWRhdGVSYW5nZSgxMDI0LDEwNzM3NDE4MjQpXVtsb25nXSRNYXhCeXRlcz04Mzg4NjA4LA0KICAgICAgICBbc3RyaW5nXSRPdXRGaWxlLCBbc3dpdGNoXSRIZWFkLFtzdHJpbmddJFVzZXJBZ2VudD0nTW90aGVyYm9hcmRGZWFzaWJpbGl0eS8xLjAnKQ0KICAgICMgUmVzdGFydCBhIHRlbXBvcmFyeSBmYWlsdXJlIGZyb20gYnl0ZSB6ZXJvOyBuZXZlciByZXVzZSBhIHBhcnRpYWwgcGF5bG9hZC4NCiAgICAjIFRocmVlIGF0dGVtcHRzIHNoYXJlIG9uZSB0aW1lb3V0LiBUTFMsIGhvc3QgYW5kIGludGVncml0eSBjaGVja3Mgc3RheSBzdHJpY3QuDQogICAgJGJ1ZGdldD1bRGlhZ25vc3RpY3MuU3RvcHdhdGNoXTo6U3RhcnROZXcoKQ0KICAgIGZvcigkYXR0ZW1wdD0xOyRhdHRlbXB0IC1sZSAzOyRhdHRlbXB0KyspIHsNCiAgICAgICAgJHJlbWFpbmluZz1baW50XVtNYXRoXTo6Q2VpbGluZygkVGltZW91dFNlY29uZHMtJGJ1ZGdldC5FbGFwc2VkLlRvdGFsU2Vjb25kcykNCiAgICAgICAgaWYoJHJlbWFpbmluZyAtbGUgMCl7dGhyb3cgJ0RlbGFpIGdsb2JhbCBkZSB0ZWxlY2hhcmdlbWVudCBkZXBhc3NlIDsgYXVjdW4gZmljaGllciB2YWxpZGUuJ30NCiAgICAgICAgdHJ5IHsNCiAgICAgICAgICAgICRyZXN1bHQ9SW52b2tlLU1ieEh0dHBBdHRlbXB0IC1VcmwgJFVybCAtSG9zdHMgJEhvc3RzIC1UaW1lb3V0U2Vjb25kcyAkcmVtYWluaW5nIC1NYXhCeXRlcyAkTWF4Qnl0ZXMgLU91dEZpbGUgJE91dEZpbGUgLUhlYWQ6JEhlYWQgLVVzZXJBZ2VudCAkVXNlckFnZW50DQogICAgICAgICAgICAkcmVzdWx0IHwgQWRkLU1lbWJlciAtTm90ZVByb3BlcnR5TmFtZSBBdHRlbXB0cyAtTm90ZVByb3BlcnR5VmFsdWUgJGF0dGVtcHQgLUZvcmNlDQogICAgICAgICAgICByZXR1cm4gJHJlc3VsdA0KICAgICAgICB9IGNhdGNoIHsNCiAgICAgICAgICAgIGlmKCRhdHRlbXB0IC1lcSAzIC1vciAtbm90IChUZXN0LU1ieFRlbXBvcmFyeUh0dHBGYWlsdXJlICRfLkV4Y2VwdGlvbikpe3Rocm93fQ0KICAgICAgICAgICAgJGRlbGF5PSRhdHRlbXB0DQogICAgICAgICAgICBpZigkYnVkZ2V0LkVsYXBzZWQuVG90YWxTZWNvbmRzKyRkZWxheSAtZ2UgJFRpbWVvdXRTZWNvbmRzKXt0aHJvd30NCiAgICAgICAgICAgIFdhaXQtTWJ4SHR0cFJldHJ5IC1TZWNvbmRzICRkZWxheQ0KICAgICAgICB9DQogICAgfQ0KfQ0KDQpmdW5jdGlvbiBUZXN0LU1ieFRlbXBvcmFyeUh0dHBGYWlsdXJlIHsNCiAgICBwYXJhbShbRXhjZXB0aW9uXSRFeGNlcHRpb24pDQogICAgJG5ldHdvcms9JGZhbHNlOyRjdXJyZW50PSRFeGNlcHRpb24NCiAgICB3aGlsZSgkY3VycmVudCl7DQogICAgICAgIGlmKCRjdXJyZW50IC1pcyBbU2VjdXJpdHkuQXV0aGVudGljYXRpb24uQXV0aGVudGljYXRpb25FeGNlcHRpb25dKXtyZXR1cm4gJGZhbHNlfQ0KICAgICAgICBpZigkY3VycmVudC5EYXRhWydNYnhOZXR3b3JrRmFpbHVyZSddKXskbmV0d29yaz0kdHJ1ZX0NCiAgICAgICAgJGN1cnJlbnQ9JGN1cnJlbnQuSW5uZXJFeGNlcHRpb24NCiAgICB9DQogICAgcmV0dXJuICgkbmV0d29yayAtb3IgJEV4Y2VwdGlvbi5NZXNzYWdlIC1tYXRjaCAnXEFIVFRQICg0MDh8NDI5fDUwMHw1MDJ8NTAzfDUwNClcYnxcQVRlbGVjaGFyZ2VtZW50IGludGVycm9tcHUgOicpDQp9DQoNCmZ1bmN0aW9uIFdhaXQtTWJ4SHR0cFJldHJ5IHtwYXJhbShbaW50XSRTZWNvbmRzKSBTdGFydC1TbGVlcCAtU2Vjb25kcyAkU2Vjb25kc30NCg0KZnVuY3Rpb24gSW52b2tlLU1ieEh0dHBBdHRlbXB0IHsNCiAgICBbQ21kbGV0QmluZGluZygpXQ0KICAgIHBhcmFtKFtQYXJhbWV0ZXIoTWFuZGF0b3J5KV1bc3RyaW5nXSRVcmwsIFtQYXJhbWV0ZXIoTWFuZGF0b3J5KV1bc3RyaW5nW11dJEhvc3RzLA0KICAgICAgICBbVmFsaWRhdGVSYW5nZSgxLDYwMCldW2ludF0kVGltZW91dFNlY29uZHM9MzAsIFtWYWxpZGF0ZVJhbmdlKDEwMjQsMTA3Mzc0MTgyNCldW2xvbmddJE1heEJ5dGVzPTgzODg2MDgsDQogICAgICAgIFtzdHJpbmddJE91dEZpbGUsIFtzd2l0Y2hdJEhlYWQsW3N0cmluZ10kVXNlckFnZW50PSdNb3RoZXJib2FyZEZlYXNpYmlsaXR5LzEuMCcpDQogICAgQWRkLVR5cGUgLUFzc2VtYmx5TmFtZSBTeXN0ZW0uTmV0Lkh0dHANCiAgICAkaGFuZGxlcj1OZXctTWJ4SHR0cEhhbmRsZXINCiAgICAkY2xpZW50PU5ldy1PYmplY3QgTmV0Lkh0dHAuSHR0cENsaWVudCgkaGFuZGxlcikNCiAgICAkY2xpZW50LlRpbWVvdXQ9W1RocmVhZGluZy5UaW1lb3V0XTo6SW5maW5pdGVUaW1lU3Bhbg0KICAgICRjbGllbnQuRGVmYXVsdFJlcXVlc3RIZWFkZXJzLlVzZXJBZ2VudC5QYXJzZUFkZCgkVXNlckFnZW50KQ0KICAgICRjbGllbnQuRGVmYXVsdFJlcXVlc3RIZWFkZXJzLkNhY2hlQ29udHJvbD1OZXctT2JqZWN0IE5ldC5IdHRwLkhlYWRlcnMuQ2FjaGVDb250cm9sSGVhZGVyVmFsdWUNCiAgICAkY2xpZW50LkRlZmF1bHRSZXF1ZXN0SGVhZGVycy5DYWNoZUNvbnRyb2wuTm9DYWNoZT0kdHJ1ZQ0KICAgICRjbGllbnQuRGVmYXVsdFJlcXVlc3RIZWFkZXJzLlByYWdtYS5QYXJzZUFkZCgnbm8tY2FjaGUnKQ0KICAgICRjdHM9TmV3LU9iamVjdCBUaHJlYWRpbmcuQ2FuY2VsbGF0aW9uVG9rZW5Tb3VyY2UNCiAgICAkY3RzLkNhbmNlbEFmdGVyKFtUaW1lU3Bhbl06OkZyb21TZWNvbmRzKCRUaW1lb3V0U2Vjb25kcykpDQogICAgJHJlc3BvbnNlPSRudWxsOyAkc3RyZWFtPSRudWxsOyAkc2luaz0kbnVsbDsgJHBhcnQ9JG51bGw7ICR0b3RhbD1bbG9uZ10wOyAkZXhwZWN0ZWQ9JG51bGwNCiAgICAkY2hhaW49TmV3LU9iamVjdCAnU3lzdGVtLkNvbGxlY3Rpb25zLkdlbmVyaWMuTGlzdFtzdHJpbmddJw0KICAgIHRyeSB7DQogICAgICAgICRjdXJyZW50PVt1cmldJFVybA0KICAgICAgICBmb3IgKCRob3A9MDsgJGhvcCAtbGUgNjsgJGhvcCsrKSB7DQogICAgICAgICAgICBpZiAoLW5vdCAoVGVzdC1NYnhPZmZpY2lhbFVyaSAkY3VycmVudC5BYnNvbHV0ZVVyaSAkSG9zdHMpKSB7IHRocm93ICdEZXN0aW5hdGlvbiBIVFRQUyBvZmZpY2llbGxlIHJlZnVzZWUgKHkgY29tcHJpcyByZWRpcmVjdGlvbikuJyB9DQogICAgICAgICAgICAkY2hhaW4uQWRkKCRjdXJyZW50LkFic29sdXRlVXJpKQ0KICAgICAgICAgICAgJHJlcXVlc3Q9TmV3LU9iamVjdCBOZXQuSHR0cC5IdHRwUmVxdWVzdE1lc3NhZ2UNCiAgICAgICAgICAgICRyZXF1ZXN0LlJlcXVlc3RVcmk9JGN1cnJlbnQNCiAgICAgICAgICAgICRyZXF1ZXN0Lk1ldGhvZD1pZiAoJEhlYWQpIHsgW05ldC5IdHRwLkh0dHBNZXRob2RdOjpIZWFkIH0gZWxzZSB7IFtOZXQuSHR0cC5IdHRwTWV0aG9kXTo6R2V0IH0NCiAgICAgICAgICAgIHRyeSB7ICRyZXNwb25zZT0kY2xpZW50LlNlbmRBc3luYygkcmVxdWVzdCxbTmV0Lkh0dHAuSHR0cENvbXBsZXRpb25PcHRpb25dOjpSZXNwb25zZUhlYWRlcnNSZWFkLCRjdHMuVG9rZW4pLkdldEF3YWl0ZXIoKS5HZXRSZXN1bHQoKSB9DQogICAgICAgICAgICBjYXRjaCB7JF8uRXhjZXB0aW9uLkRhdGFbJ01ieE5ldHdvcmtGYWlsdXJlJ109JHRydWU7dGhyb3d9DQogICAgICAgICAgICBmaW5hbGx5IHsgJHJlcXVlc3QuRGlzcG9zZSgpIH0NCiAgICAgICAgICAgICRjb2RlPVtpbnRdJHJlc3BvbnNlLlN0YXR1c0NvZGUNCiAgICAgICAgICAgIGlmICgkY29kZSAtaW4gQCgzMDEsMzAyLDMwMywzMDcsMzA4KSkgew0KICAgICAgICAgICAgICAgIGlmICgkaG9wIC1lcSA2IC1vciAtbm90ICRyZXNwb25zZS5IZWFkZXJzLkxvY2F0aW9uKSB7IHRocm93ICdSZWRpcmVjdGlvbiBzYW5zIGRlc3RpbmF0aW9uIG91IGxpbWl0ZSBkZSBzaXggc2F1dHMgYXR0ZWludGUuJyB9DQogICAgICAgICAgICAgICAgJGN1cnJlbnQ9TmV3LU9iamVjdCB1cmkoJGN1cnJlbnQsJHJlc3BvbnNlLkhlYWRlcnMuTG9jYXRpb24pDQogICAgICAgICAgICAgICAgJHJlc3BvbnNlLkRpc3Bvc2UoKTsgJHJlc3BvbnNlPSRudWxsOyBjb250aW51ZQ0KICAgICAgICAgICAgfQ0KICAgICAgICAgICAgaWYgKC1ub3QgJHJlc3BvbnNlLklzU3VjY2Vzc1N0YXR1c0NvZGUpIHsgdGhyb3cgIkhUVFAgJGNvZGUgc3VyIGxhIHNvdXJjZSBvZmZpY2llbGxlLiIgfQ0KICAgICAgICAgICAgaWYgKCRjb2RlIC1uZSAyMDApIHsgdGhyb3cgIlJlcG9uc2UgaW5jb21wbGV0ZSBvdSBpbmF0dGVuZHVlIDogSFRUUCAkY29kZS4iIH0NCiAgICAgICAgICAgIGJyZWFrDQogICAgICAgIH0NCiAgICAgICAgJGV4cGVjdGVkPSRyZXNwb25zZS5Db250ZW50LkhlYWRlcnMuQ29udGVudExlbmd0aA0KICAgICAgICAkc3VnZ2VzdGVkTmFtZT0nJw0KICAgICAgICBpZiAoJHJlc3BvbnNlLkNvbnRlbnQuSGVhZGVycy5Db250ZW50RGlzcG9zaXRpb24pIHsNCiAgICAgICAgICAgICRkaXNwb3NpdGlvbj0kcmVzcG9uc2UuQ29udGVudC5IZWFkZXJzLkNvbnRlbnREaXNwb3NpdGlvbg0KICAgICAgICAgICAgJHN1Z2dlc3RlZE5hbWU9aWYgKCRkaXNwb3NpdGlvbi5GaWxlTmFtZVN0YXIpIHsgW3N0cmluZ10kZGlzcG9zaXRpb24uRmlsZU5hbWVTdGFyIH0gZWxzZSB7IFtzdHJpbmddJGRpc3Bvc2l0aW9uLkZpbGVOYW1lIH0NCiAgICAgICAgICAgICRzdWdnZXN0ZWROYW1lPSRzdWdnZXN0ZWROYW1lLlRyaW0oJyInKQ0KICAgICAgICB9DQogICAgICAgIGlmICgkSGVhZCkgeyByZXR1cm4gW3BzY3VzdG9tb2JqZWN0XUB7IFVybD0kY3VycmVudC5BYnNvbHV0ZVVyaTsgUmVkaXJlY3RzPUAoJGNoYWluLlRvQXJyYXkoKSk7IEh0dHBTdGF0dXM9JGNvZGU7IEJ5dGVzPTA7IEV4cGVjdGVkQnl0ZXM9JGV4cGVjdGVkOyBUZXh0PScnOyBGaWxlPScnOyBIZWFkZXJzT25seT0kdHJ1ZTsgU3VnZ2VzdGVkRmlsZU5hbWU9JHN1Z2dlc3RlZE5hbWUgfSB9DQogICAgICAgIGlmICgkbnVsbCAtbmUgJGV4cGVjdGVkIC1hbmQgJGV4cGVjdGVkIC1ndCAkTWF4Qnl0ZXMpIHsgdGhyb3cgIlRhaWxsZSBhbm5vbmNlZSAoJGV4cGVjdGVkIG9jdGV0cykgc3VwZXJpZXVyZSBhIGxhIGxpbWl0ZSBkZSBsZWN0dXJlICgkTWF4Qnl0ZXMgb2N0ZXRzKS4iIH0NCiAgICAgICAgJHN0cmVhbT0kcmVzcG9uc2UuQ29udGVudC5SZWFkQXNTdHJlYW1Bc3luYygpLkdldEF3YWl0ZXIoKS5HZXRSZXN1bHQoKQ0KICAgICAgICBpZiAoJE91dEZpbGUpIHsNCiAgICAgICAgICAgICRwYXJ0PSRPdXRGaWxlKycuJytbZ3VpZF06Ok5ld0d1aWQoKS5Ub1N0cmluZygnTicpKycucGFydCcNCiAgICAgICAgICAgICRzaW5rPVtJTy5GaWxlXTo6T3BlbigkcGFydCxbSU8uRmlsZU1vZGVdOjpDcmVhdGVOZXcsW0lPLkZpbGVBY2Nlc3NdOjpXcml0ZSxbSU8uRmlsZVNoYXJlXTo6Tm9uZSkNCiAgICAgICAgfSBlbHNlIHsgJHNpbms9TmV3LU9iamVjdCBJTy5NZW1vcnlTdHJlYW0gfQ0KICAgICAgICAkYnVmZmVyPU5ldy1PYmplY3QgYnl0ZVtdIDY1NTM2OyAkdG90YWw9W2xvbmddMA0KICAgICAgICAkcHJvZ3Jlc3NDbG9jaz1bRGlhZ25vc3RpY3MuU3RvcHdhdGNoXTo6U3RhcnROZXcoKTsgJGxhc3RQcm9ncmVzcz1bbG9uZ10tNTAwOyAkcHJvZ3Jlc3NVcGRhdGVzPTANCiAgICAgICAgd2hpbGUgKCR0cnVlKSB7DQogICAgICAgICAgICB0cnkgeyRyZWFkPSRzdHJlYW0uUmVhZEFzeW5jKCRidWZmZXIsMCwkYnVmZmVyLkxlbmd0aCwkY3RzLlRva2VuKS5HZXRBd2FpdGVyKCkuR2V0UmVzdWx0KCl9DQogICAgICAgICAgICBjYXRjaCB7JF8uRXhjZXB0aW9uLkRhdGFbJ01ieE5ldHdvcmtGYWlsdXJlJ109JHRydWU7dGhyb3d9DQogICAgICAgICAgICBpZigkcmVhZCAtbGUgMCl7YnJlYWt9DQogICAgICAgICAgICAkdG90YWwrPSRyZWFkDQogICAgICAgICAgICBpZiAoJHRvdGFsIC1ndCAkTWF4Qnl0ZXMpIHsgdGhyb3cgJ1RhaWxsZSBtYXhpbWFsZSBkZSBsZWN0dXJlIGRlcGFzc2VlLicgfQ0KICAgICAgICAgICAgJHNpbmsuV3JpdGUoJGJ1ZmZlciwwLCRyZWFkKQ0KICAgICAgICAgICAgaWYgKCRPdXRGaWxlIC1hbmQgJGV4cGVjdGVkIC1ndCAwIC1hbmQgKCRwcm9ncmVzc0Nsb2NrLkVsYXBzZWRNaWxsaXNlY29uZHMtJGxhc3RQcm9ncmVzcykgLWdlIDUwMCkgew0KICAgICAgICAgICAgICAgIFdyaXRlLVByb2dyZXNzIC1BY3Rpdml0eSAnQ29udHJvbGUgZHUgdGVsZWNoYXJnZW1lbnQgb2ZmaWNpZWwgKHNhbnMgZXhlY3V0aW9uKScgLVN0YXR1cyAiJHRvdGFsIC8gJGV4cGVjdGVkIG9jdGV0cyIgLVBlcmNlbnRDb21wbGV0ZSAoW01hdGhdOjpNaW4oOTksW2ludF0oMTAwKiR0b3RhbC8kZXhwZWN0ZWQpKSkNCiAgICAgICAgICAgICAgICAkbGFzdFByb2dyZXNzPSRwcm9ncmVzc0Nsb2NrLkVsYXBzZWRNaWxsaXNlY29uZHM7ICRwcm9ncmVzc1VwZGF0ZXMrKw0KICAgICAgICAgICAgfQ0KICAgICAgICB9DQogICAgICAgIGlmICgkbnVsbCAtbmUgJGV4cGVjdGVkIC1hbmQgJHRvdGFsIC1uZSAkZXhwZWN0ZWQpIHsgdGhyb3cgIlRlbGVjaGFyZ2VtZW50IGludGVycm9tcHUgOiAkdG90YWwgb2N0ZXRzIHJlY3VzLCAkZXhwZWN0ZWQgYXR0ZW5kdXMuIiB9DQogICAgICAgIGlmICgkdG90YWwgLWVxIDApIHsgdGhyb3cgJ1JlcG9uc2UgdmlkZS4nIH0NCiAgICAgICAgJHRleHQ9JycNCiAgICAgICAgaWYgKCRPdXRGaWxlKSB7DQogICAgICAgICAgICAkc2luay5EaXNwb3NlKCk7ICRzaW5rPSRudWxsDQogICAgICAgICAgICAjIE5ldmVyIG92ZXJ3cml0ZSBhIHByZS1leGlzdGluZyBmaWxlIHNpbGVudGx5Lg0KICAgICAgICAgICAgW0lPLkZpbGVdOjpNb3ZlKCRwYXJ0LCRPdXRGaWxlKTsgJHBhcnQ9JG51bGwNCiAgICAgICAgICAgIFdyaXRlLVByb2dyZXNzIC1BY3Rpdml0eSAnQ29udHJvbGUgZHUgdGVsZWNoYXJnZW1lbnQgb2ZmaWNpZWwgKHNhbnMgZXhlY3V0aW9uKScgLUNvbXBsZXRlZA0KICAgICAgICB9IGVsc2UgeyAkdGV4dD1bVGV4dC5FbmNvZGluZ106OlVURjguR2V0U3RyaW5nKCRzaW5rLlRvQXJyYXkoKSkgfQ0KICAgICAgICByZXR1cm4gW3BzY3VzdG9tb2JqZWN0XUB7IFVybD0kY3VycmVudC5BYnNvbHV0ZVVyaTsgUmVkaXJlY3RzPUAoJGNoYWluLlRvQXJyYXkoKSk7IEh0dHBTdGF0dXM9JGNvZGU7IEJ5dGVzPSR0b3RhbDsgRXhwZWN0ZWRCeXRlcz0kZXhwZWN0ZWQ7IFRleHQ9JHRleHQ7IEZpbGU9JE91dEZpbGU7IFByb2dyZXNzVXBkYXRlcz0kcHJvZ3Jlc3NVcGRhdGVzOyBTdWdnZXN0ZWRGaWxlTmFtZT0kc3VnZ2VzdGVkTmFtZSB9DQogICAgfQ0KICAgIGNhdGNoIHsNCiAgICAgICAgaWYgKCRjdHMuSXNDYW5jZWxsYXRpb25SZXF1ZXN0ZWQpIHsgdGhyb3cgIkRlbGFpIGRlIGxlY3R1cmUgZGVwYXNzZSAoJFRpbWVvdXRTZWNvbmRzIHMpIDogJHRvdGFsIG9jdGV0cyByZWN1cywgJGV4cGVjdGVkIGF0dGVuZHVzIDsgYXVjdW4gdGVsZWNoYXJnZW1lbnQgdmFsaWRlLiIgfQ0KICAgICAgICB0aHJvdw0KICAgIH0NCiAgICBmaW5hbGx5IHsNCiAgICAgICAgaWYgKCRzaW5rKSB7ICRzaW5rLkRpc3Bvc2UoKSB9OyBpZiAoJHN0cmVhbSkgeyAkc3RyZWFtLkRpc3Bvc2UoKSB9OyBpZiAoJHJlc3BvbnNlKSB7ICRyZXNwb25zZS5EaXNwb3NlKCkgfQ0KICAgICAgICAkY3RzLkRpc3Bvc2UoKTsgJGNsaWVudC5EaXNwb3NlKCk7ICRoYW5kbGVyLkRpc3Bvc2UoKQ0KICAgICAgICBpZiAoJHBhcnQgLWFuZCBbSU8uRmlsZV06OkV4aXN0cygkcGFydCkpIHsgW0lPLkZpbGVdOjpEZWxldGUoJHBhcnQpIH0NCiAgICB9DQp9DQoNCmZ1bmN0aW9uIEdldC1NYnhEb3dubG9hZExpbmtzIHsNCiAgICBwYXJhbShbc3RyaW5nXSRIdG1sLCBbc3RyaW5nXSRQYWdlVXJsLCBbUGFyYW1ldGVyKE1hbmRhdG9yeSldJFRvb2wpDQogICAgJGxpbmtzPUAoKQ0KICAgIGZvcmVhY2ggKCRtIGluIFtyZWdleF06Ok1hdGNoZXMoJEh0bWwsJyg/aXMpKD86aHJlZnxzcmMpXHMqPVxzKlsiJyddKFteIicnXSspWyInJ118aHR0cHM6Ly9bXiInJzw+XHNcXF0rJykpIHsNCiAgICAgICAgdHJ5IHsNCiAgICAgICAgICAgICR2YWx1ZT1pZiAoJG0uR3JvdXBzWzFdLlN1Y2Nlc3MpIHsgJG0uR3JvdXBzWzFdLlZhbHVlIH0gZWxzZSB7ICRtLlZhbHVlIH0NCiAgICAgICAgICAgICR1cmw9KE5ldy1PYmplY3QgdXJpKFt1cmldJFBhZ2VVcmwsW05ldC5XZWJVdGlsaXR5XTo6SHRtbERlY29kZSgkdmFsdWUpKSkuQWJzb2x1dGVVcmkNCiAgICAgICAgICAgICRmaWxlPVt1cmldOjpVbmVzY2FwZURhdGFTdHJpbmcoKFt1cmldJHVybCkuU2VnbWVudHNbLTFdKQ0KICAgICAgICAgICAgaWYgKCRmaWxlIC1tYXRjaCAkVG9vbC5GaWxlUGF0dGVybiAtYW5kIChUZXN0LU1ieE9mZmljaWFsVXJpICR1cmwgJFRvb2wuSG9zdHMpKSB7ICRsaW5rcys9JHVybCB9DQogICAgICAgIH0gY2F0Y2gge30NCiAgICB9DQogICAgcmV0dXJuIEAoJGxpbmtzIHwgU2VsZWN0LU9iamVjdCAtVW5pcXVlKQ0KfQ0KDQpmdW5jdGlvbiBUZXN0LU1ieFNpZ25lZFBheWxvYWQgew0KICAgIHBhcmFtKFtQYXJhbWV0ZXIoTWFuZGF0b3J5KV1bc3RyaW5nXSRQYXRoLCBbUGFyYW1ldGVyKE1hbmRhdG9yeSldW3N0cmluZ1tdXSRTaWduZXJzKQ0KICAgICRsZW5ndGg9KEdldC1JdGVtIC1MaXRlcmFsUGF0aCAkUGF0aCkuTGVuZ3RoDQogICAgJHM9W0lPLkZpbGVdOjpPcGVuUmVhZCgkUGF0aCkNCiAgICB0cnkgeyAkZmlyc3Q9JHMuUmVhZEJ5dGUoKTsgJHNlY29uZD0kcy5SZWFkQnl0ZSgpIH0gZmluYWxseSB7ICRzLkRpc3Bvc2UoKSB9DQogICAgaWYgKCRsZW5ndGggLWx0IDEwMjQgLW9yICRmaXJzdCAtbmUgNzcgLW9yICRzZWNvbmQgLW5lIDkwKSB7IHRocm93ICdGaWNoaWVyIFBFL01aIGFic2VudCBvdSB0cm9wIHBldGl0LicgfQ0KICAgICRzaWduYXR1cmU9R2V0LUF1dGhlbnRpY29kZVNpZ25hdHVyZSAtTGl0ZXJhbFBhdGggJFBhdGggLUVycm9yQWN0aW9uIFN0b3ANCiAgICBpZiAoW3N0cmluZ10kc2lnbmF0dXJlLlN0YXR1cyAtbmUgJ1ZhbGlkJyAtb3IgLW5vdCAkc2lnbmF0dXJlLlNpZ25lckNlcnRpZmljYXRlKSB7IHRocm93ICJTaWduYXR1cmUgbnVtZXJpcXVlIG5vbiB2YWxpZGUgOiAkKCRzaWduYXR1cmUuU3RhdHVzKS4iIH0NCiAgICAkc2lnbmVyPSRzaWduYXR1cmUuU2lnbmVyQ2VydGlmaWNhdGUuR2V0TmFtZUluZm8oW1NlY3VyaXR5LkNyeXB0b2dyYXBoeS5YNTA5Q2VydGlmaWNhdGVzLlg1MDlOYW1lVHlwZV06OlNpbXBsZU5hbWUsJGZhbHNlKQ0KICAgIGlmICgkU2lnbmVycyAtbm90Y29udGFpbnMgJHNpZ25lcikgeyB0aHJvdyAiRWRpdGV1ciBkdSBmaWNoaWVyIG5vbiBhdXRvcmlzZSA6ICRzaWduZXIuIiB9DQogICAgJHZlcnNpb249Jyc7IHRyeSB7ICR2ZXJzaW9uPVtEaWFnbm9zdGljcy5GaWxlVmVyc2lvbkluZm9dOjpHZXRWZXJzaW9uSW5mbygkUGF0aCkuRmlsZVZlcnNpb24gfSBjYXRjaCB7fQ0KICAgIHJldHVybiBbcHNjdXN0b21vYmplY3RdQHsgU3RhdHVzPSdWYWxpZCc7IFNpZ25lcj0kc2lnbmVyOyBTSEEyNTY9KEdldC1GaWxlSGFzaCAtTGl0ZXJhbFBhdGggJFBhdGggLUFsZ29yaXRobSBTSEEyNTYpLkhhc2g7IEJ5dGVzPSRsZW5ndGg7IEZpbGVWZXJzaW9uPSR2ZXJzaW9uIH0NCn0NCg0KZnVuY3Rpb24gSW52b2tlLU1ieFV0aWxpdHlBdWRpdCB7DQogICAgW0NtZGxldEJpbmRpbmcoKV0NCiAgICBwYXJhbShbUGFyYW1ldGVyKE1hbmRhdG9yeSldJFRvb2wsIFtQYXJhbWV0ZXIoTWFuZGF0b3J5KV1bc3RyaW5nXSREb3dubG9hZFVybCwNCiAgICAgICAgW1BhcmFtZXRlcihNYW5kYXRvcnkpXVtzdHJpbmddJE91dHB1dERpcmVjdG9yeSwgW1ZhbGlkYXRlUmFuZ2UoMSw2MDApXVtpbnRdJFRpbWVvdXRTZWNvbmRzPTYwMCkNCiAgICAjIERvd25sb2FkIGF1ZGl0IGlzIGluZGVwZW5kZW50IG9mIGhhcmR3YXJlIHJlY29tbWVuZGF0aW9uLiBOZXZlciBpbnZva2UgdGhlIHBheWxvYWQuDQogICAgJHJlcXVlc3RlZFVybD0kRG93bmxvYWRVcmw7ICRzaG9ydGxpbmtSZWRpcmVjdHM9QCgpOyAkcmVzb2x2ZWROYW1lPScnDQogICAgaWYgKC1ub3QgKFRlc3QtTWJ4T2ZmaWNpYWxVcmkgJERvd25sb2FkVXJsICRUb29sLkhvc3RzKSkgeyB0aHJvdyAnTGllbiBub24gb2ZmaWNpZWwgcmVmdXNlLicgfQ0KICAgIGlmICgkVG9vbC5WZW5kb3IgLWVxICdBU1VTJyAtYW5kICREb3dubG9hZFVybCAtZXEgJ2h0dHBzOi8vZ2VvLmFzdXMuY29tL2RyaXZlcmh1Yi8nKSB7DQogICAgICAgICMgT2ZmaWNpYWwgc2hvcnRsaW5rIG9ic2VydmVkIGluIERyaXZlckh1YidzIG93biBjdXJyZW50IEphdmFTY3JpcHQuIEluc3BlY3QgSFRUUFMgcmVkaXJlY3RzIG9ubHkuDQogICAgICAgICRyZXNvbHZlZD1JbnZva2UtTWJ4SHR0cCAtVXJsICREb3dubG9hZFVybCAtSG9zdHMgJFRvb2wuSG9zdHMgLVRpbWVvdXRTZWNvbmRzICRUaW1lb3V0U2Vjb25kcyAtSGVhZA0KICAgICAgICAkc2hvcnRsaW5rUmVkaXJlY3RzPUAoJHJlc29sdmVkLlJlZGlyZWN0cykNCiAgICAgICAgJERvd25sb2FkVXJsPSRyZXNvbHZlZC5VcmwNCiAgICAgICAgaWYgKCRyZXNvbHZlZC5TdWdnZXN0ZWRGaWxlTmFtZSkgew0KICAgICAgICAgICAgJHJlc29sdmVkTmFtZT0kcmVzb2x2ZWQuU3VnZ2VzdGVkRmlsZU5hbWUNCiAgICAgICAgfSBlbHNlaWYgKFt1cmldOjpVbmVzY2FwZURhdGFTdHJpbmcoKFt1cmldJERvd25sb2FkVXJsKS5TZWdtZW50c1stMV0pIC1ub3RtYXRjaCAkVG9vbC5GaWxlUGF0dGVybikgew0KICAgICAgICAgICAgIyBBIHB1YmxpYyBIVE1ML0phdmFTY3JpcHQgZG93bmxvYWQgbGluayBpcyByZWFkIGFzIHRleHQsIG5ldmVyIGV2YWx1YXRlZC4NCiAgICAgICAgICAgICRsYW5kaW5nPUludm9rZS1NYnhIdHRwIC1VcmwgJERvd25sb2FkVXJsIC1Ib3N0cyAkVG9vbC5Ib3N0cyAtVGltZW91dFNlY29uZHMgMzAgLU1heEJ5dGVzIDIwOTcxNTINCiAgICAgICAgICAgICRodG1sPSRsYW5kaW5nLlRleHQgLXJlcGxhY2UgJ1xcLycsJy8nIC1yZXBsYWNlICdcXHUwMDI2JywnJicNCiAgICAgICAgICAgICRsaW5rcz1AKEdldC1NYnhEb3dubG9hZExpbmtzIC1IdG1sICRodG1sIC1QYWdlVXJsICRsYW5kaW5nLlVybCAtVG9vbCAkVG9vbCkNCiAgICAgICAgICAgIGlmICgkbGlua3MuQ291bnQgLW5lIDEpIHsgdGhyb3cgIlBhZ2Ugb2ZmaWNpZWxsZSBBU1VTIDogJCgkbGlua3MuQ291bnQpIGxpZW4ocykgZGUgZmljaGllciBub24gYW1iaWd1cyA7IHZlcmlmaWNhdGlvbiBtYW51ZWxsZSByZXF1aXNlLiIgfQ0KICAgICAgICAgICAgJERvd25sb2FkVXJsPSRsaW5rc1swXQ0KICAgICAgICB9DQogICAgfQ0KICAgICRuYW1lPWlmICgkcmVzb2x2ZWROYW1lKSB7ICRyZXNvbHZlZE5hbWUgfSBlbHNlIHsgW3VyaV06OlVuZXNjYXBlRGF0YVN0cmluZygoW3VyaV0kRG93bmxvYWRVcmwpLlNlZ21lbnRzWy0xXSkgfQ0KICAgIGlmICgkbmFtZSAtbm90bWF0Y2ggJFRvb2wuRmlsZVBhdHRlcm4gLW9yICRuYW1lIC1uZSBbSU8uUGF0aF06OkdldEZpbGVOYW1lKCRuYW1lKSAtb3IgJG5hbWUgLW1hdGNoICdbXFwvOio/Ijw+fF0nKSB7IHRocm93ICJOb20gZGUgZmljaGllciBob3JzIGR1IHBlcmltZXRyZSBkZSBjZXQgdXRpbGl0YWlyZSA6ICRuYW1lIChzb3VyY2Ugb2ZmaWNpZWxsZSAkRG93bmxvYWRVcmwpLiIgfQ0KICAgICRhdWRpdERpcj1Kb2luLVBhdGggJE91dHB1dERpcmVjdG9yeSAoW2d1aWRdOjpOZXdHdWlkKCkuVG9TdHJpbmcoJ04nKSkNCiAgICBbdm9pZF0oTmV3LUl0ZW0gLUl0ZW1UeXBlIERpcmVjdG9yeSAtUGF0aCAkYXVkaXREaXIgLUZvcmNlKQ0KICAgICRwYXRoPUpvaW4tUGF0aCAkYXVkaXREaXIgJG5hbWUNCiAgICAkcmVzdWx0PUludm9rZS1NYnhIdHRwIC1VcmwgJERvd25sb2FkVXJsIC1Ib3N0cyAkVG9vbC5Ib3N0cyAtVGltZW91dFNlY29uZHMgJFRpbWVvdXRTZWNvbmRzIC1NYXhCeXRlcyAxMDczNzQxODI0IC1PdXRGaWxlICRwYXRoDQogICAgIyBSZWRpcmVjdHMgbXVzdCBhbHNvIHByZXNlcnZlIHRoZSBpbnRlbmRlZCB1dGlsaXR5IGlkZW50aXR5Lg0KICAgICRmaW5hbE5hbWU9W3VyaV06OlVuZXNjYXBlRGF0YVN0cmluZygoW3VyaV0kcmVzdWx0LlVybCkuU2VnbWVudHNbLTFdKQ0KICAgIGlmICgkZmluYWxOYW1lIC1ub3RtYXRjaCAkVG9vbC5GaWxlUGF0dGVybiAtYW5kICRyZXN1bHQuU3VnZ2VzdGVkRmlsZU5hbWUgLWluZSAkbmFtZSkgeyB0aHJvdyAnTGEgcmVkaXJlY3Rpb24gbmUgcHJlc2VydmUgcGFzIGxlIG5vbSBhdHRlbmR1IGRlIGwgdXRpbGl0YWlyZS4nIH0NCiAgICAkcGF5bG9hZHM9QCgpDQogICAgaWYgKFtJTy5QYXRoXTo6R2V0RXh0ZW5zaW9uKCRwYXRoKSAtaWVxICcuZXhlJykgew0KICAgICAgICAkcGF5bG9hZHMrPVRlc3QtTWJ4U2lnbmVkUGF5bG9hZCAtUGF0aCAkcGF0aCAtU2lnbmVycyAkVG9vbC5TaWduZXJzDQogICAgfSBlbHNlIHsNCiAgICAgICAgQWRkLVR5cGUgLUFzc2VtYmx5TmFtZSBTeXN0ZW0uSU8uQ29tcHJlc3Npb24uRmlsZVN5c3RlbQ0KICAgICAgICBBZGQtVHlwZSAtQXNzZW1ibHlOYW1lIFN5c3RlbS5JTy5Db21wcmVzc2lvbg0KICAgICAgICAkemlwPVtJTy5Db21wcmVzc2lvbi5aaXBGaWxlXTo6T3BlblJlYWQoJHBhdGgpDQogICAgICAgIHRyeSB7DQogICAgICAgICAgICAkZXhwYW5kZWQ9W2xvbmddMDsgJGluZGV4PTANCiAgICAgICAgICAgIGZvcmVhY2ggKCRlbnRyeSBpbiAkemlwLkVudHJpZXMpIHsNCiAgICAgICAgICAgICAgICBpZiAoJGVudHJ5LkZ1bGxOYW1lIC1tYXRjaCAnKF5bL1xcXXwoXnxbL1xcXSlcLlwuKFsvXFxdfCQpfDopJykgeyB0aHJvdyAnQXJjaGl2ZSBhdmVjIGNoZW1pbiBkYW5nZXJldXggcmVmdXNlZS4nIH0NCiAgICAgICAgICAgICAgICAkZXhwYW5kZWQrPSRlbnRyeS5MZW5ndGgNCiAgICAgICAgICAgICAgICBpZiAoJGV4cGFuZGVkIC1ndCAyMTQ3NDgzNjQ4KSB7IHRocm93ICdBcmNoaXZlIHRyb3Agdm9sdW1pbmV1c2UgdW5lIGZvaXMgZGVjb21wcmVzc2VlLicgfQ0KICAgICAgICAgICAgICAgIGlmIChbSU8uUGF0aF06OkdldEV4dGVuc2lvbigkZW50cnkuTmFtZSkgLWluZSAnLmV4ZScpIHsgY29udGludWUgfQ0KICAgICAgICAgICAgICAgICMgRml4ZWQgZXh0cmFjdGlvbiBuYW1lcyBwcmV2ZW50IGFyY2hpdmUgcGF0aCB0cmF2ZXJzYWwsIG5vIGV4dGVybmFsIGFyY2hpdmVyIGlzIHJ1bi4NCiAgICAgICAgICAgICAgICAkcGF5bG9hZD1Kb2luLVBhdGggJGF1ZGl0RGlyICgncGF5bG9hZC0nKyRpbmRleCsnLmV4ZScpOyAkaW5kZXgrKw0KICAgICAgICAgICAgICAgICRpbnB1dFN0cmVhbT0kZW50cnkuT3BlbigpOyAkb3V0cHV0U3RyZWFtPVtJTy5GaWxlXTo6Q3JlYXRlKCRwYXlsb2FkKQ0KICAgICAgICAgICAgICAgIHRyeSB7ICRpbnB1dFN0cmVhbS5Db3B5VG8oJG91dHB1dFN0cmVhbSkgfSBmaW5hbGx5IHsgJGlucHV0U3RyZWFtLkRpc3Bvc2UoKTsgJG91dHB1dFN0cmVhbS5EaXNwb3NlKCkgfQ0KICAgICAgICAgICAgICAgICRwYXlsb2Fkcys9VGVzdC1NYnhTaWduZWRQYXlsb2FkIC1QYXRoICRwYXlsb2FkIC1TaWduZXJzICRUb29sLlNpZ25lcnMNCiAgICAgICAgICAgIH0NCiAgICAgICAgfSBmaW5hbGx5IHsgJHppcC5EaXNwb3NlKCkgfQ0KICAgICAgICBpZiAoLW5vdCAkcGF5bG9hZHMuQ291bnQpIHsgdGhyb3cgJ0FyY2hpdmUgc2FucyBleGVjdXRhYmxlIHNpZ25lIHZlcmlmaWFibGUgOyBhdWN1bmUgdmFsaWRhdGlvbiBhbm5vbmNlZS4nIH0NCiAgICB9DQogICAgcmV0dXJuIFtwc2N1c3RvbW9iamVjdF1Aew0KICAgICAgICBWZW5kb3I9JFRvb2wuVmVuZG9yOyBUb29sPSRUb29sLlRvb2w7IFN0YXR1cz0nZG93bmxvYWRfYW5kX3NpZ25lZF9leGVjdXRhYmxlc192ZXJpZmllZCcNCiAgICAgICAgUmVxdWVzdGVkVXJsPSRyZXF1ZXN0ZWRVcmw7IEZpbmFsVXJsPSRyZXN1bHQuVXJsOyBSZWRpcmVjdHM9QCgkc2hvcnRsaW5rUmVkaXJlY3RzICsgQCgkcmVzdWx0LlJlZGlyZWN0cykgfCBTZWxlY3QtT2JqZWN0IC1VbmlxdWUpOyBCeXRlcz0kcmVzdWx0LkJ5dGVzOyBFeHBlY3RlZEJ5dGVzPSRyZXN1bHQuRXhwZWN0ZWRCeXRlcw0KICAgICAgICBQcm9ncmVzc1VwZGF0ZXM9JHJlc3VsdC5Qcm9ncmVzc1VwZGF0ZXMNCiAgICAgICAgU0hBMjU2PShHZXQtRmlsZUhhc2ggLUxpdGVyYWxQYXRoICRwYXRoIC1BbGdvcml0aG0gU0hBMjU2KS5IYXNoOyBQYXlsb2Fkcz0kcGF5bG9hZHMNCiAgICAgICAgUmVwb3J0ZWRFeGVjdXRhYmxlVmVyc2lvbj1pZiAoJHBheWxvYWRzLkNvdW50IC1lcSAxKSB7ICRwYXlsb2Fkc1swXS5GaWxlVmVyc2lvbiB9IGVsc2UgeyAnJyB9DQogICAgICAgIEFyY2hpdmVQdWJsaXNoZXJIYXNoPSdub3RfYXZhaWxhYmxlJzsgTGF0ZXN0VmVyc2lvbj0nbm90X2VzdGFibGlzaGVkJzsgSGFyZHdhcmVDb21wYXRpYmlsaXR5PSdub3RfZXN0YWJsaXNoZWQnDQogICAgICAgIEluc3RhbGxlZD0kZmFsc2U7IEV4ZWN1dGVkPSRmYWxzZTsgRmlybXdhcmVGbGFzaGVkPSRmYWxzZQ0KICAgIH0NCn0NCg0KZnVuY3Rpb24gV3JpdGUtTWJ4RXZpZGVuY2Ugew0KICAgIHBhcmFtKFtzdHJpbmddJEtpbmQsIFtQYXJhbWV0ZXIoTWFuZGF0b3J5KV0kRGF0YSkNCiAgICAjIFNtYWxsIGluZGVwZW5kZW50IGFubm90YXRpb25zIGtlZXAgSlNPTiByZXRyaWV2YWJsZSB3aGVuIGxvbmcgbG9nIGxpbmVzIGFyZSB0cnVuY2F0ZWQuDQogICAgIyBDYWxsZXJzIHBhc3MgcHVibGljIHZlbmRvciBldmlkZW5jZSBvciBpbnZlbnRvcnkgY291bnRzLCBuZXZlciBob3N0L3VzZXIgaWRlbnRpZmllcnMuDQogICAgQWRkLVR5cGUgLUFzc2VtYmx5TmFtZSBTeXN0ZW0uSU8uQ29tcHJlc3Npb24NCiAgICAkYnVmZmVyPU5ldy1PYmplY3QgSU8uTWVtb3J5U3RyZWFtDQogICAgJGd6aXA9TmV3LU9iamVjdCBJTy5Db21wcmVzc2lvbi5HWmlwU3RyZWFtKCRidWZmZXIsW0lPLkNvbXByZXNzaW9uLkNvbXByZXNzaW9uTW9kZV06OkNvbXByZXNzLCR0cnVlKQ0KICAgICRieXRlcz1bVGV4dC5FbmNvZGluZ106OlVURjguR2V0Qnl0ZXMoKCREYXRhIHwgQ29udmVydFRvLUpzb24gLURlcHRoIDE0IC1Db21wcmVzcykpDQogICAgdHJ5IHsgJGd6aXAuV3JpdGUoJGJ5dGVzLDAsJGJ5dGVzLkxlbmd0aCkgfSBmaW5hbGx5IHsgJGd6aXAuRGlzcG9zZSgpIH0NCiAgICAkZW5jb2RlZD1bQ29udmVydF06OlRvQmFzZTY0U3RyaW5nKCRidWZmZXIuVG9BcnJheSgpKTsgJGJ1ZmZlci5EaXNwb3NlKCkNCiAgICAkaWQ9W2d1aWRdOjpOZXdHdWlkKCkuVG9TdHJpbmcoJ04nKTsgJGNvdW50PVtpbnRdW01hdGhdOjpDZWlsaW5nKCRlbmNvZGVkLkxlbmd0aC8zMDAwLjApDQogICAgaWYgKCRjb3VudCAtZ3QgOCkgeyB0aHJvdyAnUHJldXZlIHRyb3Agdm9sdW1pbmV1c2UgcG91ciBsZXMgYW5ub3RhdGlvbnMgOiBjb25zdWx0ZXIgbCBhcnRlZmFjdCBKU09OLicgfQ0KICAgIGZvciAoJGluZGV4PTA7ICRpbmRleCAtbHQgJGNvdW50OyAkaW5kZXgrKykgew0KICAgICAgICAkcGFydD0kZW5jb2RlZC5TdWJzdHJpbmcoJGluZGV4KjMwMDAsW01hdGhdOjpNaW4oMzAwMCwkZW5jb2RlZC5MZW5ndGgtJGluZGV4KjMwMDApKQ0KICAgICAgICAkbGluZT1bb3JkZXJlZF1AeyBJZD0kaWQ7IEtpbmQ9JEtpbmQ7IENvZGVjPSdnemlwLWJhc2U2NCc7IEluZGV4PSRpbmRleDsgQ291bnQ9JGNvdW50OyBEYXRhPSRwYXJ0IH0gfCBDb252ZXJ0VG8tSnNvbiAtQ29tcHJlc3MNCiAgICAgICAgV3JpdGUtSG9zdCAoJzo6bm90aWNlIHRpdGxlPU9FTSBldmlkZW5jZSBjaHVuazo6ezB9JyAtZiAkbGluZSkNCiAgICB9DQp9DQoNCkV4cG9ydC1Nb2R1bGVNZW1iZXIgLUZ1bmN0aW9uICotTWJ4Kg0K' }
    @{ Path = 'vendor-utility/VendorUtility.psm1'; Sha256 = '7F8FE2FC1E7BE60EA0FA85F6B1C5C650CB3BAFDCE0E159F150E364B5E68B2FCD'; Base64 = 'I3JlcXVpcmVzIC1WZXJzaW9uIDUuMQ0KU2V0LVN0cmljdE1vZGUgLVZlcnNpb24gMg0KSW1wb3J0LU1vZHVsZSAoSm9pbi1QYXRoICRQU1NjcmlwdFJvb3QgJy4uL21vdGhlcmJvYXJkL01vdGhlcmJvYXJkRXhwZXJpbWVudC5wc20xJykgLUZvcmNlDQouIChKb2luLVBhdGggJFBTU2NyaXB0Um9vdCAnVmVuZG9yRGlzY292ZXJ5LkdpZ2FieXRlLnBzMScpDQouIChKb2luLVBhdGggJFBTU2NyaXB0Um9vdCAnVmVuZG9yRGlzY292ZXJ5LkFzcm9jay5wczEnKQ0KLiAoSm9pbi1QYXRoICRQU1NjcmlwdFJvb3QgJ1ZlbmRvclBhY2thZ2UuR2lnYWJ5dGUucHMxJykNCiRzY3JpcHQ6VXRpbGl0eVNpbXVsYXRpb249JGZhbHNlDQoNCmZ1bmN0aW9uIEdldC1WdXRQcm9maWxlIHsNCiAgICBwYXJhbShbc3RyaW5nXSRWZW5kb3IsW3N0cmluZ10kQm9hcmRNb2RlbD0nJyxbc3RyaW5nXSRUYXJnZXRPcz0nJykNCiAgICAkYmFzZT1AKEdldC1NYnhUb29sRGVmaW5pdGlvbnMgfCBXaGVyZS1PYmplY3QgVmVuZG9yIC1lcSAkVmVuZG9yKQ0KICAgIGlmICgkYmFzZS5Db3VudCAtbmUgMSkgeyByZXR1cm4gJG51bGwgfQ0KICAgIGlmICgkVmVuZG9yIC1lcSAnQVNSb2NrJykgeyAkYmFzZVswXS5Ub29sPSdBU1JvY2sgQVBQIFNob3AnOyAkYmFzZVswXS5GaWxlUGF0dGVybj0nKD9pKV5BUFBTaG9wXCh2WzAtOV0rKD86XC5bMC05XSspezEsM31cKVwuemlwJCcgfQ0KICAgICRuYW1lcz1AeyBNU0k9J01TSSBDZW50ZXInOyBBU1VTPSdBU1VTIERyaXZlckh1Yic7IEdJR0FCWVRFPSdHSUdBQllURSBDb250cm9sIENlbnRlcic7IEFTUm9jaz0nQVNSb2NrIEFQUCBTaG9wJyB9DQogICAgJGV4ZWN1dGFibGVzPUB7IE1TST1AKCdNU0kgQ2VudGVyLmV4ZScsJ01TSUNlbnRlci5leGUnKTsgQVNVUz1AKCdBU1VTIERyaXZlckh1Yi5leGUnLCdBU1VTRHJpdmVySHViLmV4ZScsJ0RyaXZlckh1Yi5leGUnKTsgR0lHQUJZVEU9QCgnR0NDLmV4ZScpOyBBU1JvY2s9QCgnQXNyQVBQU2hvcC5leGUnLCdBcHBTaG9wLmV4ZScpIH0NCiAgICAkbWFudWFsUmVhc29ucz1Aew0KICAgICAgICBNU0k9J01TSSBDZW50ZXIgOiBpbnN0YWxsYXRpb24gbWluaW1hbGUgZXQgZmluYWxpc2F0aW9uIFNESyBzYW5zIGxhbmNlbWVudCBuaSBjb21wb3NhbnRzIGFkZGl0aW9ubmVscyBub24gdmFsaWRlZXMgc3VyIFBDIGNvbXBhdGlibGUuJw0KICAgICAgICBBU1VTPSdBU1VTIERyaXZlckh1YiA6IGxlIG1vZGUgc2lsZW5jaWV1eCBkZW1hcnJlIHVuIGF1eGlsaWFpcmUgcG91dmFudCB2ZXJpZmllciBsZSBjYXRhbG9ndWUgOyBhdWN1bmUgbWV0aG9kZSBvZmZpY2llbGxlIHNhbnMgcmVjaGVyY2hlIGF1dG9tYXRpcXVlIHZhbGlkZWUuJw0KICAgICAgICBHSUdBQllURT0nR0lHQUJZVEUgQ29udHJvbCBDZW50ZXIgOiBsZSBidW5kbGUgY29udGllbnQgZGVzIGNvbXBvc2FudHMgZmFjdWx0YXRpZnMgOyBpbnN0YWxsYXRpb24gZHUgY29ldXIgc2FucyBkZW1hcnJhZ2UgYXV0b21hdGlxdWUgbm9uIHZhbGlkZWUuJw0KICAgICAgICBBU1JvY2s9J0FTUm9jayBBUFAgU2hvcCA6IC9WZXJ5U2lsZW50IGFubm9uY2UgZGFucyBsZSBjYXRhbG9ndWUsIG1haXMgbmV0dG95YWdlIGRlIHNlcnZpY2VzIGV0IHBpbG90ZXMgQVNSb2NrIGV4aXN0YW50cyBkZXRlY3RlIGRhbnMgbGEgdmVyc2lvbiBhY3R1ZWxsZSA7IGluc3RhbGxhdGlvbiBtaW5pbWFsZSBub24gdmFsaWRlZSBzdXIgUEMuJw0KICAgIH0NCiAgICByZXR1cm4gW3BzY3VzdG9tb2JqZWN0XUB7DQogICAgICAgIFZlbmRvcj0kVmVuZG9yOyBOYW1lPSRuYW1lc1skVmVuZG9yXTsgT2ZmaWNpYWxQYWdlPSRiYXNlWzBdLlBhZ2U7IERvd25sb2FkRGVmaW5pdGlvbj0kYmFzZVswXQ0KICAgICAgICBCb2FyZE1vZGVsPSRCb2FyZE1vZGVsOyBUYXJnZXRPcz0kVGFyZ2V0T3MNCiAgICAgICAgRmlsZU5hbWVzPSRleGVjdXRhYmxlc1skVmVuZG9yXTsgU2lnbmVycz0kYmFzZVswXS5TaWduZXJzDQogICAgICAgIERvd25sb2FkVXJsPWlmICgkVmVuZG9yIC1lcSAnTVNJJykgeyAnaHR0cHM6Ly9kb3dubG9hZC0yLm1zaS5jb20vdXRpX2V4ZS9kZXNrdG9wL01TSS1DZW50ZXIuemlwJyB9IGVsc2UgeyAnJyB9DQogICAgICAgIERvd25sb2FkTWFuaWZlc3RVcmw9aWYgKCRWZW5kb3IgLWVxICdBU1VTJykgeyAnaHR0cHM6Ly9kcml2ZXJodWIuYXN1cy5jb20vZG93bmxvYWQvQVNVUy1Ecml2ZXJIdWItSW5zdGFsbGVyLmpzb24nIH0gZWxzZSB7ICcnIH0NCiAgICAgICAgIyBObyBndWVzc2VkIHN3aXRjaGVzLiBUaGlzIHJlbWFpbnMgbWFudWFsIHVudGlsIGFuIGV4YWN0IGJhc2Utb25seSBpbnN0YWxsYXRpb24gaXMgc3Vic3RhbnRpYXRlZC4NCiAgICAgICAgQXV0b21hdGljPSRmYWxzZTsgQXBwcm92ZWRJbnN0YWxsZXJIYXNoZXM9QCgpOyBJbnN0YWxsZXJBcmd1bWVudHM9JycNCiAgICAgICAgQXV0b21hdGljUmVhc29uPSRtYW51YWxSZWFzb25zWyRWZW5kb3JdDQogICAgICAgIFBhY2thZ2VGYW1pbHk9aWYgKCRWZW5kb3IgLWVxICdNU0knKSB7ICc5NDI2TUlDUk8tU1RBUklOVEVSTkFUSU9OLk1TSUNlbnRlcl9remg4d3hiZGt4YjhwJyB9IGVsc2UgeyAnJyB9DQogICAgfQ0KfQ0KDQpmdW5jdGlvbiBHZXQtVnV0SGFyZHdhcmUgew0KICAgIGlmIChbRW52aXJvbm1lbnRdOjpPU1ZlcnNpb24uUGxhdGZvcm0gLW5lIFtQbGF0Zm9ybUlEXTo6V2luMzJOVCkgeyB0aHJvdyAnQ2Ugc2NyaXB0IGRvaXQgZXRyZSBleGVjdXRlIHNvdXMgV2luZG93cy4nIH0NCiAgICAjIE9ubHkgaWRlbnRpdHkvY29tcGF0aWJpbGl0eS4gTm8gQklPUyBxdWVyeSwgZHJpdmVyIGludmVudG9yeSBvciB1cGRhdGUgc2VhcmNoLg0KICAgICRib2FyZHM9QChHZXQtQ2ltSW5zdGFuY2UgV2luMzJfQmFzZUJvYXJkIC1PcGVyYXRpb25UaW1lb3V0U2VjIDE1IC1FcnJvckFjdGlvbiBTdG9wKQ0KICAgICRwY3M9QChHZXQtQ2ltSW5zdGFuY2UgV2luMzJfQ29tcHV0ZXJTeXN0ZW0gLU9wZXJhdGlvblRpbWVvdXRTZWMgMTUgLUVycm9yQWN0aW9uIFN0b3ApDQogICAgJG9zPUAoR2V0LUNpbUluc3RhbmNlIFdpbjMyX09wZXJhdGluZ1N5c3RlbSAtT3BlcmF0aW9uVGltZW91dFNlYyAxNSAtRXJyb3JBY3Rpb24gU3RvcCkNCiAgICAkY2hhc3Npcz1AKEdldC1DaW1JbnN0YW5jZSBXaW4zMl9TeXN0ZW1FbmNsb3N1cmUgLU9wZXJhdGlvblRpbWVvdXRTZWMgMTUgLUVycm9yQWN0aW9uIFN0b3ApDQogICAgaWYgKCRib2FyZHMuQ291bnQgLW5lIDEgLW9yICRwY3MuQ291bnQgLW5lIDEgLW9yICRvcy5Db3VudCAtbmUgMSkgeyB0aHJvdyAnSWRlbnRpZmljYXRpb24gbWF0ZXJpZWxsZSBhYnNlbnRlIG91IGFtYmlndWUuJyB9DQogICAgcmV0dXJuIFtwc2N1c3RvbW9iamVjdF1Aew0KICAgICAgICBCb2FyZE1hbnVmYWN0dXJlcj1bc3RyaW5nXSRib2FyZHNbMF0uTWFudWZhY3R1cmVyOyBCb2FyZE1vZGVsPVtzdHJpbmddJGJvYXJkc1swXS5Qcm9kdWN0DQogICAgICAgIENvbXB1dGVyTWFudWZhY3R1cmVyPVtzdHJpbmddJHBjc1swXS5NYW51ZmFjdHVyZXI7IENvbXB1dGVyTW9kZWw9W3N0cmluZ10kcGNzWzBdLk1vZGVsDQogICAgICAgIFBvcnRhYmxlPSgkcGNzWzBdLlBDU3lzdGVtVHlwZSAtZXEgMiAtb3IgQCgkY2hhc3NpcyB8IEZvckVhY2gtT2JqZWN0IHsgJF8uQ2hhc3Npc1R5cGVzIH0gfCBXaGVyZS1PYmplY3QgeyAkXyAtaW4gQCg4LDksMTAsMTEsMTIsMTQsMzAsMzEsMzIpIH0pLkNvdW50IC1ndCAwKQ0KICAgICAgICBXaW5kb3dzQ2FwdGlvbj1bc3RyaW5nXSRvc1swXS5DYXB0aW9uOyBXaW5kb3dzVmVyc2lvbj1bc3RyaW5nXSRvc1swXS5WZXJzaW9uDQogICAgICAgIENsaWVudFdpbmRvd3M9KCRvc1swXS5Qcm9kdWN0VHlwZSAtZXEgMSk7IElzNjRCaXQ9W0Vudmlyb25tZW50XTo6SXM2NEJpdE9wZXJhdGluZ1N5c3RlbQ0KICAgIH0NCn0NCg0KZnVuY3Rpb24gUmVzb2x2ZS1WdXRTZWxlY3Rpb24gew0KICAgIHBhcmFtKFtQYXJhbWV0ZXIoTWFuZGF0b3J5KV0kSGFyZHdhcmUpDQogICAgJHZlbmRvcj1HZXQtTWJ4VmVuZG9yICRIYXJkd2FyZS5Cb2FyZE1hbnVmYWN0dXJlcg0KICAgICRyPVtvcmRlcmVkXUB7IFZlbmRvcj0kdmVuZG9yOyBNb2RlbD0kSGFyZHdhcmUuQm9hcmRNb2RlbDsgRWxpZ2libGU9JGZhbHNlOyBSZWFzb249Jyc7IFRvb2w9JycgfQ0KICAgIGlmICgoJEhhcmR3YXJlLkNvbXB1dGVyTWFudWZhY3R1cmVyKycgJyskSGFyZHdhcmUuQ29tcHV0ZXJNb2RlbCkgLW1hdGNoICcoP2kpVmlydHVhbCBNYWNoaW5lfFZNd2FyZXxWaXJ0dWFsQm94fEtWTXxRRU1VfFhlbnxBbWF6b24gRUMyfEdvb2dsZSBDb21wdXRlJykgew0KICAgICAgICAkci5SZWFzb249J01hY2hpbmUgdmlydHVlbGxlIDogYXVjdW5lIGluc3RhbGxhdGlvbiBkZSBsb2dpY2llbCBtYXRlcmllbCBhdXRvcmlzZWUuJw0KICAgIH0gZWxzZWlmICgtbm90ICR2ZW5kb3IgLW9yIChUZXN0LU1ieFBsYWNlaG9sZGVyICRIYXJkd2FyZS5Cb2FyZE1vZGVsKSkgew0KICAgICAgICAkci5SZWFzb249J0ZhYnJpY2FudCBvdSBtb2RlbGUgaW5jb25udSA6IHV0aWxpc2VyIGxlIHN1cHBvcnQgZHUgUEMuJw0KICAgIH0gZWxzZWlmICgkSGFyZHdhcmUuUG9ydGFibGUpIHsNCiAgICAgICAgJHIuUmVhc29uPSdQb3J0YWJsZSA6IHV0aWxpdGFpcmUgZHUgbW9kZWxlIE9FTSBhIGNvbmZpcm1lciBtYW51ZWxsZW1lbnQuJw0KICAgIH0gZWxzZWlmICgtbm90IChUZXN0LU1ieFBsYWNlaG9sZGVyICRIYXJkd2FyZS5Db21wdXRlck1hbnVmYWN0dXJlcikgLWFuZCAoR2V0LU1ieFZlbmRvciAkSGFyZHdhcmUuQ29tcHV0ZXJNYW51ZmFjdHVyZXIpIC1uZSAkdmVuZG9yKSB7DQogICAgICAgICRyLlJlYXNvbj0nUEMgT0VNIDogbmUgcGFzIGluc3RhbGxlciB1biB1dGlsaXRhaXJlIGRlIGNhcnRlIG1lcmUgcmV0YWlsIHNhbnMgcHJldXZlIGRlIGNvbXBhdGliaWxpdGUuJw0KICAgIH0gZWxzZWlmICgtbm90ICRIYXJkd2FyZS5DbGllbnRXaW5kb3dzIC1vciAtbm90ICRIYXJkd2FyZS5JczY0Qml0IC1vciAkSGFyZHdhcmUuV2luZG93c0NhcHRpb24gLW5vdG1hdGNoICdcYldpbmRvd3NccysoMTB8MTEpXGInKSB7DQogICAgICAgICRyLlJlYXNvbj0nV2luZG93cyBjbGllbnQgMTAvMTEgNjQgYml0cyByZXF1aXMgOyBjb21wYXRpYmlsaXRlIG5vbiBjb25maXJtZWUgcG91ciBjZSBzeXN0ZW1lLicNCiAgICB9IGVsc2Ugew0KICAgICAgICAkci5Ub29sPShHZXQtVnV0UHJvZmlsZSAkdmVuZG9yKS5OYW1lDQogICAgICAgICRyLkVsaWdpYmxlPSR0cnVlDQogICAgICAgICRyLlJlYXNvbj0nRmFicmljYW50IGV0IG1vZGVsZSBpZGVudGlmaWVzIDsgbGEgbWV0aG9kZSBkdSBsb2dpY2llbCBlc3QgY29udHJvbGVlIHNlcGFyZW1lbnQuJw0KICAgIH0NCiAgICByZXR1cm4gW3BzY3VzdG9tb2JqZWN0XSRyDQp9DQoNCmZ1bmN0aW9uIFRlc3QtVnV0QXBwbGljYXRpb25OYW1lIHsNCiAgICBwYXJhbSgkUHJvZmlsZSwgW3N0cmluZ10kRGlzcGxheU5hbWUpDQogICAgaWYgKCREaXNwbGF5TmFtZSAtaWVxICRQcm9maWxlLk5hbWUpIHsgcmV0dXJuICR0cnVlIH0NCiAgICBpZiAoJFByb2ZpbGUuVmVuZG9yIC1lcSAnQVNSb2NrJyAtYW5kICREaXNwbGF5TmFtZSAtbWF0Y2ggJ1xBQVBQIFNob3AgdihbMC05XStcLlswLTldK1wuWzAtOV0rXC5bMC05XSspXHonKSB7DQogICAgICAgIHJldHVybiAkbnVsbCAtbmUgKENvbnZlcnRUby1NYnhWZXJzaW9uICRNYXRjaGVzWzFdKQ0KICAgIH0NCiAgICByZXR1cm4gJGZhbHNlDQp9DQoNCmZ1bmN0aW9uIEdldC1WdXRJbnN0YWxsZWRBcHBsaWNhdGlvbiB7DQogICAgcGFyYW0oW1BhcmFtZXRlcihNYW5kYXRvcnkpXSRQcm9maWxlKQ0KICAgIGlmICgkUHJvZmlsZS5QYWNrYWdlRmFtaWx5IC1hbmQgKEdldC1Db21tYW5kIEdldC1BcHB4UGFja2FnZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSkpIHsNCiAgICAgICAgJHBhY2thZ2VzPUAoR2V0LUFwcHhQYWNrYWdlIC1OYW1lICc5NDI2TUlDUk8tU1RBUklOVEVSTkFUSU9OLk1TSUNlbnRlcicgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBXaGVyZS1PYmplY3Qgew0KICAgICAgICAgICAgJF8gLWFuZCBbc3RyaW5nXShHZXQtTWJ4VmFsdWUgJF8gJ1BhY2thZ2VGYW1pbHlOYW1lJykgLWVxICRQcm9maWxlLlBhY2thZ2VGYW1pbHkgLWFuZCBbc3RyaW5nXShHZXQtTWJ4VmFsdWUgJF8gJ1N0YXR1cycpIC1lcSAnT2snIC1hbmQNCiAgICAgICAgICAgIFtzdHJpbmddKEdldC1NYnhWYWx1ZSAkXyAnU2lnbmF0dXJlS2luZCcpIC1lcSAnU3RvcmUnIC1hbmQgLW5vdCBbYm9vbF0oR2V0LU1ieFZhbHVlICRfICdJc0RldmVsb3BtZW50TW9kZScgJGZhbHNlKQ0KICAgICAgICB9KQ0KICAgICAgICBpZiAoJHBhY2thZ2VzLkNvdW50IC1lcSAxKSB7DQogICAgICAgICAgICAkcD0kcGFja2FnZXNbMF07ICRtYW5pZmVzdFBhdGg9Sm9pbi1QYXRoICRwLkluc3RhbGxMb2NhdGlvbiAnQXBweE1hbmlmZXN0LnhtbCcNCiAgICAgICAgICAgIGlmIChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRtYW5pZmVzdFBhdGggLVBhdGhUeXBlIExlYWYpIHsNCiAgICAgICAgICAgICAgICBbeG1sXSRtYW5pZmVzdD1HZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggJG1hbmlmZXN0UGF0aCAtUmF3DQogICAgICAgICAgICAgICAgJGFwcHM9QCgkbWFuaWZlc3QuUGFja2FnZS5BcHBsaWNhdGlvbnMuQXBwbGljYXRpb24pDQogICAgICAgICAgICAgICAgaWYgKCRhcHBzLkNvdW50IC1lcSAxIC1hbmQgW3N0cmluZ10kYXBwc1swXS5JZCAtbWF0Y2ggJ15bQS1aYS16MC05Ll8tXSskJykgew0KICAgICAgICAgICAgICAgICAgICAkZXhlPVtzdHJpbmddJGFwcHNbMF0uRXhlY3V0YWJsZQ0KICAgICAgICAgICAgICAgICAgICAkcmVsYXRpdmU9JGV4ZSAtYW5kIC1ub3QgW0lPLlBhdGhdOjpJc1BhdGhSb290ZWQoJGV4ZSkgLWFuZCAkZXhlIC1ub3RtYXRjaCAnKF58Wy9cXF0pXC5cLihbL1xcXXwkKXw6Jw0KICAgICAgICAgICAgICAgICAgICBpZiAoJHJlbGF0aXZlIC1hbmQgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggKEpvaW4tUGF0aCAkcC5JbnN0YWxsTG9jYXRpb24gJGV4ZSkgLVBhdGhUeXBlIExlYWYpKSB7DQogICAgICAgICAgICAgICAgICAgICAgICByZXR1cm4gW3BzY3VzdG9tb2JqZWN0XUB7IFZlcmlmaWVkPSR0cnVlOyBLaW5kPSdBcHB4JzsgVmVyc2lvbj1bc3RyaW5nXSRwLlZlcnNpb247IFRhcmdldD0oSm9pbi1QYXRoICRlbnY6V0lORElSICdleHBsb3Jlci5leGUnKTsgQXJndW1lbnRzPSgnc2hlbGw6QXBwc0ZvbGRlclwnKyRwLlBhY2thZ2VGYW1pbHlOYW1lKychJytbc3RyaW5nXSRhcHBzWzBdLklkKTsgUHJvb2Y9J1JlZ2lzdGVyZWQgZXhhY3QgTVNJIHBhY2thZ2UgZmFtaWx5LCBzdGF0dXMgT2sgYW5kIG1hbmlmZXN0IGV4ZWN1dGFibGUgcHJlc2VudCcgfQ0KICAgICAgICAgICAgICAgICAgICB9DQogICAgICAgICAgICAgICAgfQ0KICAgICAgICAgICAgfQ0KICAgICAgICB9DQogICAgfQ0KICAgICRlbnRyaWVzPUAoKQ0KICAgIGZvcmVhY2ggKCRwYXRoIGluIEAoJ0hLTE06XFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzXEN1cnJlbnRWZXJzaW9uXFVuaW5zdGFsbFwqJywnSEtMTTpcU09GVFdBUkVcV09XNjQzMk5vZGVcTWljcm9zb2Z0XFdpbmRvd3NcQ3VycmVudFZlcnNpb25cVW5pbnN0YWxsXConLCdIS0NVOlxTT0ZUV0FSRVxNaWNyb3NvZnRcV2luZG93c1xDdXJyZW50VmVyc2lvblxVbmluc3RhbGxcKicpKSB7DQogICAgICAgICRlbnRyaWVzKz1AKEdldC1JdGVtUHJvcGVydHkgLVBhdGggJHBhdGggLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgfCBXaGVyZS1PYmplY3QgeyBUZXN0LVZ1dEFwcGxpY2F0aW9uTmFtZSAkUHJvZmlsZSAoW3N0cmluZ10oR2V0LU1ieFZhbHVlICRfICdEaXNwbGF5TmFtZScpKSB9KQ0KICAgIH0NCiAgICBmb3JlYWNoICgkZW50cnkgaW4gJGVudHJpZXMpIHsNCiAgICAgICAgJGljb249W0Vudmlyb25tZW50XTo6RXhwYW5kRW52aXJvbm1lbnRWYXJpYWJsZXMoW3N0cmluZ10oR2V0LU1ieFZhbHVlICRlbnRyeSAnRGlzcGxheUljb24nKSkNCiAgICAgICAgJHRhcmdldD0nJw0KICAgICAgICBpZiAoJGljb24gLW1hdGNoICdeIihbXiJcclxuXStcLmV4ZSkiKD86LFxzKi0/XGQrKT8kJykgeyAkdGFyZ2V0PSRNYXRjaGVzWzFdIH0NCiAgICAgICAgZWxzZWlmICgkaWNvbiAtbWF0Y2ggJ14oW14iXHJcbl0rXC5leGUpKD86LFxzKi0/XGQrKT8kJykgeyAkdGFyZ2V0PSRNYXRjaGVzWzFdIH0NCiAgICAgICAgaWYgKC1ub3QgJHRhcmdldCAtb3IgJFByb2ZpbGUuRmlsZU5hbWVzIC1ub3Rjb250YWlucyBbSU8uUGF0aF06OkdldEZpbGVOYW1lKCR0YXJnZXQpIC1vciAtbm90IFtJTy5QYXRoXTo6SXNQYXRoUm9vdGVkKCR0YXJnZXQpIC1vciAtbm90IChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICR0YXJnZXQgLVBhdGhUeXBlIExlYWYpKSB7IGNvbnRpbnVlIH0NCiAgICAgICAgdHJ5IHsNCiAgICAgICAgICAgICRzaWduYXR1cmU9VGVzdC1NYnhTaWduZWRQYXlsb2FkIC1QYXRoICR0YXJnZXQgLVNpZ25lcnMgJFByb2ZpbGUuU2lnbmVycw0KICAgICAgICAgICAgJGluZm89W0RpYWdub3N0aWNzLkZpbGVWZXJzaW9uSW5mb106OkdldFZlcnNpb25JbmZvKCR0YXJnZXQpDQogICAgICAgICAgICBpZiAoW3N0cmluZ10kaW5mby5Qcm9kdWN0TmFtZSAtaW5lICRQcm9maWxlLk5hbWUgLWFuZCBbc3RyaW5nXSRpbmZvLkZpbGVEZXNjcmlwdGlvbiAtaW5lICRQcm9maWxlLk5hbWUpIHsgY29udGludWUgfQ0KICAgICAgICAgICAgcmV0dXJuIFtwc2N1c3RvbW9iamVjdF1AeyBWZXJpZmllZD0kdHJ1ZTsgS2luZD0nRXhlJzsgVmVyc2lvbj0kc2lnbmF0dXJlLkZpbGVWZXJzaW9uLlRyaW0oKTsgVGFyZ2V0PSR0YXJnZXQ7IEFyZ3VtZW50cz0nJzsgUHJvb2Y9J0V4YWN0IGFwcGxpY2F0aW9uIHJlZ2lzdHJ5IG5hbWUsIGV4cGVjdGVkIHNpZ25lZCBleGVjdXRhYmxlIGFuZCBwcm9kdWN0IGlkZW50aXR5JyB9DQogICAgICAgIH0gY2F0Y2ggeyBjb250aW51ZSB9DQogICAgfQ0KICAgIHJldHVybiAkbnVsbA0KfQ0KDQpmdW5jdGlvbiBHZXQtVnV0RGVza3RvcCB7DQogICAgJGRlc2t0b3A9W0Vudmlyb25tZW50XTo6R2V0Rm9sZGVyUGF0aChbRW52aXJvbm1lbnQrU3BlY2lhbEZvbGRlcl06OkRlc2t0b3BEaXJlY3RvcnkpDQogICAgaWYgKC1ub3QgJGRlc2t0b3AgLW9yIC1ub3QgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJGRlc2t0b3AgLVBhdGhUeXBlIENvbnRhaW5lcikpIHsgdGhyb3cgJ0J1cmVhdSByZWVsIGRlIGNldCB1dGlsaXNhdGV1ciBXaW5kb3dzIGludHJvdXZhYmxlIDsgYXVjdW4gcmVwbGkgdmVycyBsZSBCdXJlYXUgcHVibGljLicgfQ0KICAgIHJldHVybiAkZGVza3RvcA0KfQ0KDQpmdW5jdGlvbiBOZXctVnV0U2hvcnRjdXQgew0KICAgIHBhcmFtKFtQYXJhbWV0ZXIoTWFuZGF0b3J5KV0kUHJvZmlsZSwgW1BhcmFtZXRlcihNYW5kYXRvcnkpXSRBcHBsaWNhdGlvbikNCiAgICBpZiAoLW5vdCAkQXBwbGljYXRpb24uVmVyaWZpZWQgLW9yIC1ub3QgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJEFwcGxpY2F0aW9uLlRhcmdldCAtUGF0aFR5cGUgTGVhZikpIHsgdGhyb3cgJ0FwcGxpY2F0aW9uIG5vbiB2ZXJpZmllZSA6IGF1Y3VuIHJhY2NvdXJjaSBjcmVlLicgfQ0KICAgICRkZXNrdG9wPUdldC1WdXREZXNrdG9wDQogICAgJHBhdGg9Sm9pbi1QYXRoICRkZXNrdG9wICgkUHJvZmlsZS5OYW1lKycubG5rJykNCiAgICAkc2hlbGw9TmV3LU9iamVjdCAtQ29tT2JqZWN0IFdTY3JpcHQuU2hlbGwNCiAgICB0cnkgew0KICAgICAgICAkbGluaz0kc2hlbGwuQ3JlYXRlU2hvcnRjdXQoJHBhdGgpDQogICAgICAgIGlmIChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRwYXRoKSB7DQogICAgICAgICAgICBpZiAoJGxpbmsuVGFyZ2V0UGF0aCAtaW5lICRBcHBsaWNhdGlvbi5UYXJnZXQgLW9yICRsaW5rLkFyZ3VtZW50cyAtY25lICRBcHBsaWNhdGlvbi5Bcmd1bWVudHMpIHsgdGhyb3cgJ1VuIHJhY2NvdXJjaSBkdSBtZW1lIG5vbSBhIHVuZSBhdXRyZSBjaWJsZSA6IGlsIGVzdCBjb25zZXJ2ZS4nIH0NCiAgICAgICAgICAgIHJldHVybiAkcGF0aA0KICAgICAgICB9DQogICAgICAgICRsaW5rLlRhcmdldFBhdGg9JEFwcGxpY2F0aW9uLlRhcmdldDsgJGxpbmsuQXJndW1lbnRzPSRBcHBsaWNhdGlvbi5Bcmd1bWVudHMNCiAgICAgICAgJGxpbmsuV29ya2luZ0RpcmVjdG9yeT1TcGxpdC1QYXRoIC1QYXJlbnQgJEFwcGxpY2F0aW9uLlRhcmdldA0KICAgICAgICAkbGluay5EZXNjcmlwdGlvbj0nT3V2cmlyIG1hbnVlbGxlbWVudCAnKyRQcm9maWxlLk5hbWUNCiAgICAgICAgJGxpbmsuU2F2ZSgpDQogICAgICAgICRyZWFkPSRzaGVsbC5DcmVhdGVTaG9ydGN1dCgkcGF0aCkNCiAgICAgICAgaWYgKCRyZWFkLlRhcmdldFBhdGggLWluZSAkQXBwbGljYXRpb24uVGFyZ2V0IC1vciAkcmVhZC5Bcmd1bWVudHMgLWNuZSAkQXBwbGljYXRpb24uQXJndW1lbnRzKSB7IHRocm93ICdSYWNjb3VyY2kgZWNyaXQgbWFpcyB2ZXJpZmljYXRpb24gZGUgc2EgY2libGUgZW4gZWNoZWMuJyB9DQogICAgICAgIHJldHVybiAkcGF0aA0KICAgIH0gZmluYWxseSB7IGlmICgkc2hlbGwpIHsgW3ZvaWRdW1J1bnRpbWUuSW50ZXJvcFNlcnZpY2VzLk1hcnNoYWxdOjpGaW5hbFJlbGVhc2VDb21PYmplY3QoJHNoZWxsKSB9IH0NCn0NCg0KZnVuY3Rpb24gR2V0LVZ1dEluc3RhbGxlclN0b3JlIHsNCiAgICAkbG9jYWw9W0Vudmlyb25tZW50XTo6R2V0Rm9sZGVyUGF0aChbRW52aXJvbm1lbnQrU3BlY2lhbEZvbGRlcl06OkxvY2FsQXBwbGljYXRpb25EYXRhKQ0KICAgIGlmICgtbm90ICRsb2NhbCkgeyB0aHJvdyAnRG9zc2llciBsb2NhbCBkZSBjZXQgdXRpbGlzYXRldXIgV2luZG93cyBpbnRyb3V2YWJsZSBwb3VyIGNvbnNlcnZlciBsIGluc3RhbGxhdGV1ci4nIH0NCiAgICByZXR1cm4gSm9pbi1QYXRoICRsb2NhbCAnVmVuZG9yVXRpbGl0eS9JbnN0YWxsZXJzJw0KfQ0KDQpmdW5jdGlvbiBOZXctVnV0U3VwcG9ydFNob3J0Y3V0IHsNCiAgICBwYXJhbShbUGFyYW1ldGVyKE1hbmRhdG9yeSldJFByb2ZpbGUpDQogICAgIyBGaXhlZCBvZmZpY2lhbCBsYW5kaW5nIHBhZ2UsIG5ldmVyIGEgZ3Vlc3NlZCBiaW5hcnkgb3IgYSBjYWNoZWQgb2xkIHJlbGVhc2UuDQogICAgJG9mZmljaWFsPUdldC1WdXRQcm9maWxlIC1WZW5kb3IgJFByb2ZpbGUuVmVuZG9yDQogICAgaWYgKC1ub3QgJG9mZmljaWFsIC1vciAkUHJvZmlsZS5PZmZpY2lhbFBhZ2UgLWNuZSAkb2ZmaWNpYWwuT2ZmaWNpYWxQYWdlIC1vcg0KICAgICAgICAtbm90IChUZXN0LU1ieE9mZmljaWFsVXJpICRvZmZpY2lhbC5PZmZpY2lhbFBhZ2UgJG9mZmljaWFsLkRvd25sb2FkRGVmaW5pdGlvbi5Ib3N0cykpIHsNCiAgICAgICAgdGhyb3cgJ1BhZ2UgZGUgcmVwbGkgb2ZmaWNpZWxsZSBpbnZhbGlkZSA7IGF1Y3VuIHJhY2NvdXJjaSBJbnRlcm5ldCBjcmVlLicNCiAgICB9DQogICAgJHBhdGg9Sm9pbi1QYXRoIChHZXQtVnV0RGVza3RvcCkgKCdUZWxlY2hhcmdlbWVudCBvZmZpY2llbCAtICcrJG9mZmljaWFsLk5hbWUrJy51cmwnKQ0KICAgICRjb250ZW50PSJbSW50ZXJuZXRTaG9ydGN1dF1gcmBuVVJMPSQoJG9mZmljaWFsLk9mZmljaWFsUGFnZSlgcmBuIg0KICAgIGlmIChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRwYXRoKSB7DQogICAgICAgIGlmIChbSU8uRmlsZV06OlJlYWRBbGxUZXh0KCRwYXRoKS5UcmltKCkgLWNuZSAkY29udGVudC5UcmltKCkpIHsNCiAgICAgICAgICAgIHRocm93ICdVbiByYWNjb3VyY2kgSW50ZXJuZXQgZHUgbWVtZSBub20gYSB1bmUgYXV0cmUgY2libGUgOiBpbCBlc3QgY29uc2VydmUuJw0KICAgICAgICB9DQogICAgICAgIHJldHVybiAkcGF0aA0KICAgIH0NCiAgICAkc3RyZWFtPVtJTy5GaWxlXTo6T3BlbigkcGF0aCxbSU8uRmlsZU1vZGVdOjpDcmVhdGVOZXcsW0lPLkZpbGVBY2Nlc3NdOjpXcml0ZSxbSU8uRmlsZVNoYXJlXTo6Tm9uZSkNCiAgICB0cnkgew0KICAgICAgICAkYnl0ZXM9W1RleHQuRW5jb2RpbmddOjpBU0NJSS5HZXRCeXRlcygkY29udGVudCkNCiAgICAgICAgJHN0cmVhbS5Xcml0ZSgkYnl0ZXMsMCwkYnl0ZXMuTGVuZ3RoKQ0KICAgIH0gZmluYWxseSB7JHN0cmVhbS5EaXNwb3NlKCl9DQogICAgaWYgKFtJTy5GaWxlXTo6UmVhZEFsbFRleHQoJHBhdGgpIC1jbmUgJGNvbnRlbnQpIHt0aHJvdyAnVmVyaWZpY2F0aW9uIGR1IHJhY2NvdXJjaSBJbnRlcm5ldCBvZmZpY2llbCBlbiBlY2hlYy4nfQ0KICAgIHJldHVybiAkcGF0aA0KfQ0KDQpmdW5jdGlvbiBOZXctVnV0SW5zdGFsbGVyU2hvcnRjdXQgew0KICAgIHBhcmFtKFtQYXJhbWV0ZXIoTWFuZGF0b3J5KV0kUHJvZmlsZSxbUGFyYW1ldGVyKE1hbmRhdG9yeSldJFBhY2thZ2UpDQogICAgJGRpc3BsYXlWZXJzaW9uPShbc3RyaW5nXSRQYWNrYWdlLlZlcnNpb24pLlRyaW0oKQ0KICAgICR2ZXJzaW9uPUNvbnZlcnRUby1NYnhWZXJzaW9uICRkaXNwbGF5VmVyc2lvbg0KICAgICRhbGxvd2VkPSgkUHJvZmlsZS5WZW5kb3IgLWluIEAoJ01TSScsJ0FTVVMnLCdBU1JvY2snKSAtb3IgKCRQcm9maWxlLlZlbmRvciAtZXEgJ0dJR0FCWVRFJyAtYW5kIChHZXQtTWJ4VmFsdWUgJFBhY2thZ2UgJ0tpbmQnKSAtZXEgJ2dpZ2FieXRlX2NvcmUnKSkNCiAgICBpZiAoLW5vdCAkdmVyc2lvbiAtb3IgLW5vdCAkYWxsb3dlZCAtb3IgJFBhY2thZ2UuU0hBMjU2IC1ub3RtYXRjaCAnXEFbMC05QS1GYS1mXXs2NH1ceicpIHsNCiAgICAgICAgdGhyb3cgJ0luc3RhbGxhdGV1ciBzYW5zIGlkZW50aXRlL3ZlcnNpb24gdmVyaWZpZWUgOiBhdWN1biByYWNjb3VyY2kgY3JlZS4nDQogICAgfQ0KICAgICRzb3VyY2U9W0lPLlBhdGhdOjpHZXRGdWxsUGF0aCgkUGFja2FnZS5QYXRoKQ0KICAgICR2ZXJpZmllZD1UZXN0LU1ieFNpZ25lZFBheWxvYWQgLVBhdGggJHNvdXJjZSAtU2lnbmVycyAkUHJvZmlsZS5TaWduZXJzDQogICAgaWYgKCR2ZXJpZmllZC5TSEEyNTYgLWluZSAkUGFja2FnZS5TSEEyNTYgLW9yIChDb252ZXJ0VG8tTWJ4VmVyc2lvbiAkdmVyaWZpZWQuRmlsZVZlcnNpb24uVHJpbSgpKSAtbmUgJHZlcnNpb24pIHsNCiAgICAgICAgdGhyb3cgJ0luc3RhbGxhdGV1ciBtb2RpZmllIGRlcHVpcyBsZSB0ZWxlY2hhcmdlbWVudCA6IGF1Y3VuIHJhY2NvdXJjaSBjcmVlLicNCiAgICB9DQogICAgIyBBIHN0YWJsZSwgcGVyLXVzZXIgbG9jYXRpb24ga2VlcHMgdGhlIHNob3J0Y3V0IHVzYWJsZSBhZnRlciB0aGlzIHNjcmlwdA0KICAgICMgZXhpdHMgYW5kIGxldHMgcmVwZWF0ZWQgZG93bmxvYWRzIHJldXNlIHRoZSBzYW1lIHZlcmlmaWVkIHRhcmdldC4NCiAgICAkZGlyZWN0b3J5PUpvaW4tUGF0aCAoR2V0LVZ1dEluc3RhbGxlclN0b3JlKSAoJFByb2ZpbGUuVmVuZG9yKycvJyskdmVyc2lvbi5Ub1N0cmluZygpKycvJyskUGFja2FnZS5TSEEyNTYuVG9VcHBlckludmFyaWFudCgpKQ0KICAgIFt2b2lkXShOZXctSXRlbSAtSXRlbVR5cGUgRGlyZWN0b3J5IC1QYXRoICRkaXJlY3RvcnkgLUZvcmNlKQ0KICAgICR0YXJnZXQ9Sm9pbi1QYXRoICRkaXJlY3RvcnkgJ1NldHVwLmV4ZScNCiAgICBpZiAoLW5vdCAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkdGFyZ2V0KSkgeyBbSU8uRmlsZV06OkNvcHkoJHNvdXJjZSwkdGFyZ2V0LCRmYWxzZSkgfQ0KICAgICRzdG9yZWQ9VGVzdC1NYnhTaWduZWRQYXlsb2FkIC1QYXRoICR0YXJnZXQgLVNpZ25lcnMgJFByb2ZpbGUuU2lnbmVycw0KICAgIGlmICgkc3RvcmVkLlNIQTI1NiAtaW5lICRQYWNrYWdlLlNIQTI1NiAtb3IgKENvbnZlcnRUby1NYnhWZXJzaW9uICRzdG9yZWQuRmlsZVZlcnNpb24uVHJpbSgpKSAtbmUgJHZlcnNpb24pIHsNCiAgICAgICAgdGhyb3cgJ0NvcGllIHBlcm1hbmVudGUgZGUgbCBpbnN0YWxsYXRldXIgbm9uIGNvbmZvcm1lIDogYXVjdW4gcmFjY291cmNpIGNyZWUuJw0KICAgIH0NCiAgICAkc2hvcnRjdXRQcm9maWxlPVtwc2N1c3RvbW9iamVjdF1Ae05hbWU9KCdJbnN0YWxsZXIgJyskUHJvZmlsZS5OYW1lKycgJyskZGlzcGxheVZlcnNpb24pfQ0KICAgICRhcHBsaWNhdGlvbj1bcHNjdXN0b21vYmplY3RdQHtWZXJpZmllZD0kdHJ1ZTtLaW5kPSdJbnN0YWxsZXInO1RhcmdldD0kdGFyZ2V0O0FyZ3VtZW50cz0nJ30NCiAgICAkc2hvcnRjdXQ9TmV3LVZ1dFNob3J0Y3V0IC1Qcm9maWxlICRzaG9ydGN1dFByb2ZpbGUgLUFwcGxpY2F0aW9uICRhcHBsaWNhdGlvbg0KICAgIHJldHVybiBbcHNjdXN0b21vYmplY3RdQHtQYXRoPSR0YXJnZXQ7VmVyc2lvbj0kZGlzcGxheVZlcnNpb247U2hvcnRjdXQ9JHNob3J0Y3V0fQ0KfQ0KDQpmdW5jdGlvbiBSZXNvbHZlLVZ1dEFzdXNEb3dubG9hZCB7DQogICAgIyBUaGUgZ2VvIGVuZHBvaW50IHJldHVybnMgYSByZWdpb24gaGVhZGVyLCBub3QgYW4gaW5zdGFsbGVyLiBGb2xsb3cgRHJpdmVySHViJ3Mgb3duIEpTT04gY29udHJhY3QuDQogICAgJG1hbmlmZXN0VXJsPSdodHRwczovL2RyaXZlcmh1Yi5hc3VzLmNvbS9kb3dubG9hZC9BU1VTLURyaXZlckh1Yi1JbnN0YWxsZXIuanNvbicNCiAgICAkcmVzcG9uc2U9SW52b2tlLU1ieEh0dHAgLVVybCAkbWFuaWZlc3RVcmwgLUhvc3RzIEAoJ2RyaXZlcmh1Yi5hc3VzLmNvbScpIC1UaW1lb3V0U2Vjb25kcyAzMCAtTWF4Qnl0ZXMgNjU1MzYNCiAgICB0cnkgeyAkbWFuaWZlc3Q9JHJlc3BvbnNlLlRleHQgfCBDb252ZXJ0RnJvbS1Kc29uIC1FcnJvckFjdGlvbiBTdG9wIH0NCiAgICBjYXRjaCB7IHRocm93ICdNYW5pZmVzdGUgQVNVUyBvZmZpY2llbCBpbnZhbGlkZSA6IEpTT04gaWxsaXNpYmxlIDsgYXVjdW4gcmVwbGkgdmVycyB1biBhbmNpZW4gaW5zdGFsbGF0ZXVyLicgfQ0KICAgICRsYXRlc3Q9W3N0cmluZ10oR2V0LU1ieFZhbHVlICRtYW5pZmVzdCAnbGF0ZXN0VmVyc2lvbicpDQogICAgJG1pbmltdW09W3N0cmluZ10oR2V0LU1ieFZhbHVlICRtYW5pZmVzdCAnbWluaW11bVN1cHBvcnRlZFZlcnNpb24nKQ0KICAgICR2ZXJzaW9uPUNvbnZlcnRUby1NYnhWZXJzaW9uICRsYXRlc3QNCiAgICBpZiAoJGxhdGVzdCAtbm90bWF0Y2ggJ1xBWzAtOV0rXC5bMC05XStcLlswLTldK1wuWzAtOV0rXHonIC1vciAtbm90ICR2ZXJzaW9uKSB7IHRocm93ICdNYW5pZmVzdGUgQVNVUyBvZmZpY2llbCA6IGxhdGVzdFZlcnNpb24gYWJzZW50IG91IGludmFsaWRlIDsgYXVjdW4gYW5jaWVuIGZpY2hpZXIgc2VsZWN0aW9ubmUuJyB9DQogICAgaWYgKCRtaW5pbXVtKSB7DQogICAgICAgICRtaW5pbXVtVmVyc2lvbj1Db252ZXJ0VG8tTWJ4VmVyc2lvbiAkbWluaW11bQ0KICAgICAgICBpZiAoJG1pbmltdW0gLW5vdG1hdGNoICdcQVswLTldK1wuWzAtOV0rXC5bMC05XStcLlswLTldK1x6JyAtb3IgLW5vdCAkbWluaW11bVZlcnNpb24gLW9yICRtaW5pbXVtVmVyc2lvbiAtZ3QgJHZlcnNpb24pIHsgdGhyb3cgJ01hbmlmZXN0ZSBBU1VTIG9mZmljaWVsIGluY29oZXJlbnQgOiBtaW5pbXVtU3VwcG9ydGVkVmVyc2lvbiBpbnZhbGlkZSBvdSBzdXBlcmlldXIgYSBsYXRlc3RWZXJzaW9uLicgfQ0KICAgIH0NCiAgICAjIFRoaXMgdGhyZXNob2xkIGlzIHRoZSB2ZW5kb3IncyBVUkwgcm91dGluZyBydWxlLCBub3QgYSBwaW5uZWQgbGF0ZXN0IHJlbGVhc2UuDQogICAgJHVybD1pZiAoJHZlcnNpb24gLWd0IFt2ZXJzaW9uXScxLjAuNC43JykgeyAnaHR0cHM6Ly9kcml2ZXJodWIuYXN1cy5jb20vZG93bmxvYWQvJyskbGF0ZXN0KycvQVNVUy1Ecml2ZXJIdWItSW5zdGFsbGVyLmV4ZScgfSBlbHNlIHsgJ2h0dHBzOi8vZHJpdmVyaHViLmFzdXMuY29tL2Rvd25sb2FkL0FTVVMtRHJpdmVySHViLUluc3RhbGxlci5leGUnIH0NCiAgICByZXR1cm4gW3BzY3VzdG9tb2JqZWN0XUB7IE1hbmlmZXN0VXJsPSRtYW5pZmVzdFVybDsgVmVyc2lvbj0kbGF0ZXN0OyBNaW5pbXVtU3VwcG9ydGVkVmVyc2lvbj0kbWluaW11bTsgRG93bmxvYWRVcmw9JHVybDsgTWV0aG9kPSdvZmZpY2lhbF9hc3VzX2pzb24nIH0NCn0NCg0KZnVuY3Rpb24gR2V0LVZ1dFBhY2thZ2Ugew0KICAgIHBhcmFtKFtQYXJhbWV0ZXIoTWFuZGF0b3J5KV0kUHJvZmlsZSwgW1BhcmFtZXRlcihNYW5kYXRvcnkpXVtzdHJpbmddJERpcmVjdG9yeSkNCiAgICBpZiAoJFByb2ZpbGUuVmVuZG9yIC1lcSAnR0lHQUJZVEUnKSB7IHJldHVybiBHZXQtVnV0R2lnYWJ5dGVQYWNrYWdlIC1EaXJlY3RvcnkgJERpcmVjdG9yeSB9DQogICAgJGRpc2NvdmVyeT0kbnVsbDsgJGRvd25sb2FkVXJsPSRQcm9maWxlLkRvd25sb2FkVXJsDQogICAgaWYgKCRQcm9maWxlLlZlbmRvciAtZXEgJ0FTVVMnKSB7ICRkaXNjb3Zlcnk9UmVzb2x2ZS1WdXRBc3VzRG93bmxvYWQ7ICRkb3dubG9hZFVybD0kZGlzY292ZXJ5LkRvd25sb2FkVXJsIH0NCiAgICBpZiAoJFByb2ZpbGUuVmVuZG9yIC1lcSAnQVNSb2NrJykgeyAkZGlzY292ZXJ5PVJlc29sdmUtVnV0QXNyb2NrRG93bmxvYWQgLU1vZGVsICRQcm9maWxlLkJvYXJkTW9kZWwgLVRhcmdldE9zICRQcm9maWxlLlRhcmdldE9zOyAkZG93bmxvYWRVcmw9JGRpc2NvdmVyeS5Eb3dubG9hZFVybCB9DQogICAgaWYgKC1ub3QgJGRvd25sb2FkVXJsKSB7IHRocm93ICdBdWN1biBpbnN0YWxsYXRldXIgb2ZmaWNpZWwgbm9uIGFtYmlndSByZXNvbHUgcG91ciBjZSBtb2RlbGUuIFV0aWxpc2VyIGxhIHBhZ2UgZGUgc3VwcG9ydC4nIH0NCiAgICBbdm9pZF0oTmV3LUl0ZW0gLUl0ZW1UeXBlIERpcmVjdG9yeSAtUGF0aCAkRGlyZWN0b3J5IC1Gb3JjZSkNCiAgICAkYXVkaXQ9SW52b2tlLU1ieFV0aWxpdHlBdWRpdCAtVG9vbCAkUHJvZmlsZS5Eb3dubG9hZERlZmluaXRpb24gLURvd25sb2FkVXJsICRkb3dubG9hZFVybCAtT3V0cHV0RGlyZWN0b3J5ICREaXJlY3RvcnkNCiAgICBpZiAoJFByb2ZpbGUuVmVuZG9yIC1lcSAnQVNSb2NrJykgew0KICAgICAgICBpZiAoJGF1ZGl0LlNIQTI1NiAtaW5lICRkaXNjb3ZlcnkuQXJjaGl2ZVNIQTI1NikgeyB0aHJvdyAnQXJjaGl2ZSBBU1JvY2sgZGlmZmVyZW50ZSBkZSBsIGVtcHJlaW50ZSBTSEEyNTYgZHUgY2F0YWxvZ3VlIGNvbnN0cnVjdGV1ci4nIH0NCiAgICAgICAgJGFyY2hpdmVzPUAoR2V0LUNoaWxkSXRlbSAtTGl0ZXJhbFBhdGggJERpcmVjdG9yeSAtUmVjdXJzZSAtRmlsZSAtRmlsdGVyICcqLnppcCcpDQogICAgICAgIGlmICgkYXJjaGl2ZXMuQ291bnQgLW5lIDEpIHsgdGhyb3cgJ0FyY2hpdmUgQVNSb2NrIGFic2VudGUgb3UgYW1iaWd1ZS4nIH0NCiAgICAgICAgQWRkLVR5cGUgLUFzc2VtYmx5TmFtZSBTeXN0ZW0uSU8uQ29tcHJlc3Npb24uRmlsZVN5c3RlbQ0KICAgICAgICAkYXJjaGl2ZT1bSU8uQ29tcHJlc3Npb24uWmlwRmlsZV06Ok9wZW5SZWFkKCRhcmNoaXZlc1swXS5GdWxsTmFtZSkNCiAgICAgICAgdHJ5IHsNCiAgICAgICAgICAgICRleHBlY3RlZEVudHJ5PUAoJGFyY2hpdmUuRW50cmllcyB8IFdoZXJlLU9iamVjdCB7ICRfLkZ1bGxOYW1lLlJlcGxhY2UoJ1wnLCcvJykgLWNlcSAkZGlzY292ZXJ5Lkluc3RhbGxlclJlbGF0aXZlUGF0aCB9KQ0KICAgICAgICAgICAgaWYgKCRleHBlY3RlZEVudHJ5LkNvdW50IC1uZSAxIC1vciAkYXVkaXQuUGF5bG9hZHMuQ291bnQgLW5lIDEgLW9yICRleHBlY3RlZEVudHJ5WzBdLkxlbmd0aCAtbmUgJGF1ZGl0LlBheWxvYWRzWzBdLkJ5dGVzKSB7IHRocm93ICdJbnN0YWxsYXRldXIgQVNSb2NrIGludGVybmUgZGlmZmVyZW50IGR1IGZpY2hpZXIgYW5ub25jZSBwYXIgbGUgY29uc3RydWN0ZXVyLicgfQ0KICAgICAgICB9IGZpbmFsbHkgeyAkYXJjaGl2ZS5EaXNwb3NlKCkgfQ0KICAgIH0NCiAgICAkZmlsZXM9QChHZXQtQ2hpbGRJdGVtIC1MaXRlcmFsUGF0aCAkRGlyZWN0b3J5IC1SZWN1cnNlIC1GaWxlIC1GaWx0ZXIgJyouZXhlJyB8IFdoZXJlLU9iamVjdCB7ICRfLk5hbWUgLWxpa2UgJ3BheWxvYWQtKi5leGUnIC1vciAkXy5OYW1lIC1tYXRjaCAkUHJvZmlsZS5Eb3dubG9hZERlZmluaXRpb24uRmlsZVBhdHRlcm4gfSkNCiAgICBpZiAoJGZpbGVzLkNvdW50IC1uZSAxIC1vciAkYXVkaXQuUGF5bG9hZHMuQ291bnQgLW5lIDEpIHsgdGhyb3cgJ1BsdXNpZXVycyBleGVjdXRhYmxlcyBvdSBpbnN0YWxsYXRldXIgcHJpbmNpcGFsIGFtYmlndSA6IGluc3RhbGxhdGlvbiBtYW51ZWxsZSByZXF1aXNlLicgfQ0KICAgICR2ZXJpZmllZD1UZXN0LU1ieFNpZ25lZFBheWxvYWQgLVBhdGggJGZpbGVzWzBdLkZ1bGxOYW1lIC1TaWduZXJzICRQcm9maWxlLlNpZ25lcnMNCiAgICBpZiAoJHZlcmlmaWVkLlNIQTI1NiAtbmUgJGF1ZGl0LlBheWxvYWRzWzBdLlNIQTI1NikgeyB0aHJvdyAnTGUgZmljaGllciBhIGNoYW5nZSBhcHJlcyBsZSB0ZWxlY2hhcmdlbWVudC4nIH0NCiAgICBpZiAoJGRpc2NvdmVyeSkgew0KICAgICAgICAkZmlsZVZlcnNpb249Q29udmVydFRvLU1ieFZlcnNpb24gJHZlcmlmaWVkLkZpbGVWZXJzaW9uLlRyaW0oKQ0KICAgICAgICBpZiAoLW5vdCAkZmlsZVZlcnNpb24gLW9yICRmaWxlVmVyc2lvbiAtbmUgKENvbnZlcnRUby1NYnhWZXJzaW9uICRkaXNjb3ZlcnkuVmVyc2lvbikpIHsgdGhyb3cgKCdWZXJzaW9uICcrJFByb2ZpbGUuVmVuZG9yKycgZHUgZmljaGllciBkaWZmZXJlbnRlIGR1IG1hbmlmZXN0ZSBvZmZpY2llbCA7IGF1Y3VuIHRlbGVjaGFyZ2VtZW50IHByZXNlbnRlIGNvbW1lIGxhIGRlcm5pZXJlIHZlcnNpb24uJykgfQ0KICAgIH0NCiAgICByZXR1cm4gW3BzY3VzdG9tb2JqZWN0XUB7IFBhdGg9JGZpbGVzWzBdLkZ1bGxOYW1lOyBTSEEyNTY9JHZlcmlmaWVkLlNIQTI1NjsgVmVyc2lvbj0kdmVyaWZpZWQuRmlsZVZlcnNpb24uVHJpbSgpOyBBdWRpdD0kYXVkaXQ7IERpc2NvdmVyeT0kZGlzY292ZXJ5IH0NCn0NCg0KZnVuY3Rpb24gSW52b2tlLVZ1dEluc3RhbGxlclByb2Nlc3Mgew0KICAgIHBhcmFtKFtzdHJpbmddJFBhdGgsIFtzdHJpbmddJEFyZ3VtZW50cywgW2ludF0kVGltZW91dFNlY29uZHM9NjAwKQ0KICAgICMgQSBoYXJkIGJvdW5kYXJ5OiByZWFsIGhhcmR3YXJlIHZlbmRvciBpbnN0YWxsZXJzIG11c3QgbmV2ZXIgZXhlY3V0ZSBvbiBHaXRIdWIgaG9zdGVkIHJ1bm5lcnMuDQogICAgaWYgKCRlbnY6R0lUSFVCX0FDVElPTlMgLWVxICd0cnVlJykgeyB0aHJvdyAnSW5zdGFsbGF0ZXVyIGNvbnN0cnVjdGV1ciByZWVsIGludGVyZGl0IGRhbnMgR2l0SHViIEFjdGlvbnMuJyB9DQogICAgJGlkZW50aXR5PVtTZWN1cml0eS5QcmluY2lwYWwuV2luZG93c0lkZW50aXR5XTo6R2V0Q3VycmVudCgpDQogICAgaWYgKC1ub3QgKE5ldy1PYmplY3QgU2VjdXJpdHkuUHJpbmNpcGFsLldpbmRvd3NQcmluY2lwYWwoJGlkZW50aXR5KSkuSXNJblJvbGUoW1NlY3VyaXR5LlByaW5jaXBhbC5XaW5kb3dzQnVpbHRJblJvbGVdOjpBZG1pbmlzdHJhdG9yKSkgeyB0aHJvdyAnRHJvaXRzIGFkbWluaXN0cmF0ZXVyIHJlcXVpcyBwb3VyIGluc3RhbGxlciBsZSBsb2dpY2llbC4nIH0NCiAgICAkcD1OZXctT2JqZWN0IERpYWdub3N0aWNzLlByb2Nlc3MNCiAgICAkc3RhcnRlZD0kZmFsc2UNCiAgICAkcC5TdGFydEluZm8uRmlsZU5hbWU9JFBhdGg7ICRwLlN0YXJ0SW5mby5Bcmd1bWVudHM9JEFyZ3VtZW50czsgJHAuU3RhcnRJbmZvLlVzZVNoZWxsRXhlY3V0ZT0kZmFsc2UNCiAgICB0cnkgew0KICAgICAgICBpZiAoLW5vdCAkcC5TdGFydCgpKSB7IHRocm93ICdMIGluc3RhbGxhdGV1ciBuZSBkZW1hcnJlIHBhcy4nIH0NCiAgICAgICAgJHN0YXJ0ZWQ9JHRydWUNCiAgICAgICAgaWYgKC1ub3QgJHAuV2FpdEZvckV4aXQoJFRpbWVvdXRTZWNvbmRzKjEwMDApKSB7IHRocm93ICdEZWxhaSBkZSBsIGluc3RhbGxhdGV1ciBkZXBhc3NlIDsgaW5zdGFsbGF0aW9uIG5vbiBjb25maXJtZWUuJyB9DQogICAgICAgIHJldHVybiAkcC5FeGl0Q29kZQ0KICAgIH0gZmluYWxseSB7DQogICAgICAgIGlmICgkc3RhcnRlZCAtYW5kIC1ub3QgJHAuSGFzRXhpdGVkKSB7ICYgKEpvaW4tUGF0aCAkZW52OldJTkRJUiAnU3lzdGVtMzIvdGFza2tpbGwuZXhlJykgL1BJRCAkcC5JZCAvVCAvRiB8IE91dC1OdWxsIH0NCiAgICAgICAgJHAuRGlzcG9zZSgpDQogICAgfQ0KfQ0KDQpmdW5jdGlvbiBJbnZva2UtVmVuZG9yVXRpbGl0eSB7DQogICAgW0NtZGxldEJpbmRpbmcoKV0NCiAgICBwYXJhbShbc3dpdGNoXSRQbGFuT25seSkNCiAgICAkcj1bb3JkZXJlZF1AeyBNb2RlPWlmICgkc2NyaXB0OlV0aWxpdHlTaW11bGF0aW9uKSB7ICdzaW11bGF0aW9uJyB9IGVsc2UgeyAncmVhbCcgfTsgU3RhdHVzPSdmYWlsZWQnOyBWZW5kb3I9Jyc7IE1vZGVsPScnOyBUb29sPScnOyBSZWFzb249Jyc7IE9mZmljaWFsUGFnZT0nJzsgSW5zdGFsbGVyUGF0aD0nJzsgSW5zdGFsbGVyVmVyc2lvbj0nJzsgSW5zdGFsbGVyU2hvcnRjdXQ9Jyc7IEluc3RhbGxlclNvdXJjZT0nJzsgRGV0ZWN0aW9uU291cmNlPScnOyBEZXRlY3Rpb25NZXRob2Q9Jyc7IFN1cHBvcnRTaG9ydGN1dD0nJzsgRmFsbGJhY2tVc2VkPSRmYWxzZTsgRG93bmxvYWRGYWlsdXJlPScnOyBGYWxsYmFja0Vycm9yPScnOyBJbnN0YWxsZWQ9JGZhbHNlOyBJbnN0YWxsZWRUaGlzUnVuPSRmYWxzZTsgQXBwbGljYXRpb25WZXJpZmllZD0kZmFsc2U7IEFwcGxpY2F0aW9uVmVyc2lvbj0nJzsgUmVib290UmVxdWlyZWQ9JGZhbHNlOyBTaG9ydGN1dD0nJzsgQXV0b21hdGljSW5zdGFsbEF2YWlsYWJsZT0kZmFsc2UgfQ0KICAgIHRyeSB7DQogICAgICAgICRoYXJkd2FyZT1HZXQtVnV0SGFyZHdhcmUNCiAgICAgICAgJHNlbGVjdGlvbj1SZXNvbHZlLVZ1dFNlbGVjdGlvbiAkaGFyZHdhcmUNCiAgICAgICAgJHIuVmVuZG9yPSRzZWxlY3Rpb24uVmVuZG9yOyAkci5Nb2RlbD0kc2VsZWN0aW9uLk1vZGVsDQogICAgICAgIGlmICgtbm90ICRzZWxlY3Rpb24uRWxpZ2libGUpIHsgJHIuU3RhdHVzPSdtYW51YWxfcmVxdWlyZWQnOyAkci5SZWFzb249JHNlbGVjdGlvbi5SZWFzb247IHJldHVybiBbcHNjdXN0b21vYmplY3RdJHIgfQ0KICAgICAgICAkdGFyZ2V0T3M9aWYgKCRoYXJkd2FyZS5XaW5kb3dzQ2FwdGlvbiAtbWF0Y2ggJ1xiV2luZG93c1xzKzExXGInKSB7ICdXaW5kb3dzIDExIDY0Yml0JyB9IGVsc2UgeyAnV2luZG93cyAxMCA2NGJpdCcgfQ0KICAgICAgICAkcHJvZmlsZT1HZXQtVnV0UHJvZmlsZSAtVmVuZG9yICRzZWxlY3Rpb24uVmVuZG9yIC1Cb2FyZE1vZGVsICRzZWxlY3Rpb24uTW9kZWwgLVRhcmdldE9zICR0YXJnZXRPcw0KICAgICAgICAkci5Ub29sPSRwcm9maWxlLk5hbWU7ICRyLk9mZmljaWFsUGFnZT0kcHJvZmlsZS5PZmZpY2lhbFBhZ2U7ICRyLkF1dG9tYXRpY0luc3RhbGxBdmFpbGFibGU9JHByb2ZpbGUuQXV0b21hdGljDQogICAgICAgIGlmICgkUGxhbk9ubHkpIHsgJHIuU3RhdHVzPSdwbGFuJzsgJHIuUmVhc29uPSRwcm9maWxlLkF1dG9tYXRpY1JlYXNvbjsgcmV0dXJuIFtwc2N1c3RvbW9iamVjdF0kciB9DQogICAgICAgICRhcHA9R2V0LVZ1dEluc3RhbGxlZEFwcGxpY2F0aW9uICRwcm9maWxlDQogICAgICAgIGlmICgkYXBwIC1hbmQgJGFwcC5WZXJpZmllZCkgew0KICAgICAgICAgICAgJHIuQXBwbGljYXRpb25WZXJpZmllZD0kdHJ1ZTsgJHIuQXBwbGljYXRpb25WZXJzaW9uPSRhcHAuVmVyc2lvbjsgJHIuSW5zdGFsbGVkPS1ub3QgJHNjcmlwdDpVdGlsaXR5U2ltdWxhdGlvbg0KICAgICAgICAgICAgJHIuU2hvcnRjdXQ9TmV3LVZ1dFNob3J0Y3V0ICRwcm9maWxlICRhcHANCiAgICAgICAgICAgICRyLlN0YXR1cz0nYWxyZWFkeV9pbnN0YWxsZWQnOyAkci5SZWFzb249J0FwcGxpY2F0aW9uIHByZXNlbnRlIGV0IHJhY2NvdXJjaSB2ZXJpZmllIDsgYXVjdW5lIG1pc2UgYSBqb3VyIGxhbmNlZS4nDQogICAgICAgICAgICByZXR1cm4gW3BzY3VzdG9tb2JqZWN0XSRyDQogICAgICAgIH0NCiAgICAgICAgJGNhY2hlPUpvaW4tUGF0aCAoW0Vudmlyb25tZW50XTo6R2V0Rm9sZGVyUGF0aChbRW52aXJvbm1lbnQrU3BlY2lhbEZvbGRlcl06OkxvY2FsQXBwbGljYXRpb25EYXRhKSkgKCdWZW5kb3JVdGlsaXR5LycrW2d1aWRdOjpOZXdHdWlkKCkuVG9TdHJpbmcoJ04nKSkNCiAgICAgICAgdHJ5IHsgJHBhY2thZ2U9R2V0LVZ1dFBhY2thZ2UgJHByb2ZpbGUgJGNhY2hlOyAkci5JbnN0YWxsZXJQYXRoPSRwYWNrYWdlLlBhdGggfQ0KICAgICAgICBjYXRjaCB7DQogICAgICAgICAgICAkci5TdGF0dXM9J21hbnVhbF9yZXF1aXJlZCc7ICRyLkRvd25sb2FkRmFpbHVyZT0kXy5FeGNlcHRpb24uTWVzc2FnZQ0KICAgICAgICAgICAgJHIuUmVhc29uPSdEZXRlY3Rpb24vdGVsZWNoYXJnZW1lbnQgYXV0b21hdGlxdWUgaW1wb3NzaWJsZSA6ICcrJHIuRG93bmxvYWRGYWlsdXJlDQogICAgICAgICAgICB0cnkgew0KICAgICAgICAgICAgICAgICRyLlN1cHBvcnRTaG9ydGN1dD1OZXctVnV0U3VwcG9ydFNob3J0Y3V0IC1Qcm9maWxlICRwcm9maWxlDQogICAgICAgICAgICAgICAgJHIuRmFsbGJhY2tVc2VkPSR0cnVlDQogICAgICAgICAgICAgICAgJHIuUmVhc29uKz0nIFJlcGxpIG1hbnVlbCA6IHJhY2NvdXJjaSBUZWxlY2hhcmdlbWVudCBvZmZpY2llbCBzdXIgbGUgQnVyZWF1IHZlcnMgJyskci5PZmZpY2lhbFBhZ2UrJy4gQXVjdW4gaW5zdGFsbGF0ZXVyIHZhbGlkZSBuaSBpbnN0YWxsYXRpb24gY29uZmlybWVlLicNCiAgICAgICAgICAgIH0gY2F0Y2ggew0KICAgICAgICAgICAgICAgICRyLkZhbGxiYWNrRXJyb3I9JF8uRXhjZXB0aW9uLk1lc3NhZ2UNCiAgICAgICAgICAgICAgICAkci5SZWFzb24rPScgUmVwbGkgQnVyZWF1IGltcG9zc2libGUgOiAnKyRyLkZhbGxiYWNrRXJyb3IrJyBQYWdlIG9mZmljaWVsbGUgOiAnKyRyLk9mZmljaWFsUGFnZQ0KICAgICAgICAgICAgfQ0KICAgICAgICAgICAgcmV0dXJuIFtwc2N1c3RvbW9iamVjdF0kcg0KICAgICAgICB9DQogICAgICAgICRkaXNjb3Zlcnk9R2V0LU1ieFZhbHVlICRwYWNrYWdlICdEaXNjb3ZlcnknDQogICAgICAgICRyLkRldGVjdGlvblNvdXJjZT1bc3RyaW5nXShHZXQtTWJ4VmFsdWUgJGRpc2NvdmVyeSAnTWFuaWZlc3RVcmwnKQ0KICAgICAgICAkci5EZXRlY3Rpb25NZXRob2Q9W3N0cmluZ10oR2V0LU1ieFZhbHVlICRkaXNjb3ZlcnkgJ01ldGhvZCcpDQogICAgICAgICRyLkluc3RhbGxlclNvdXJjZT1bc3RyaW5nXShHZXQtTWJ4VmFsdWUgKEdldC1NYnhWYWx1ZSAkcGFja2FnZSAnQXVkaXQnKSAnRmluYWxVcmwnKQ0KICAgICAgICBpZiAoLW5vdCAkcHJvZmlsZS5BdXRvbWF0aWMgLW9yICRwcm9maWxlLkFwcHJvdmVkSW5zdGFsbGVySGFzaGVzIC1ub3Rjb250YWlucyAkcGFja2FnZS5TSEEyNTYpIHsNCiAgICAgICAgICAgICRwcmVwYXJlZD1OZXctVnV0SW5zdGFsbGVyU2hvcnRjdXQgLVByb2ZpbGUgJHByb2ZpbGUgLVBhY2thZ2UgJHBhY2thZ2UNCiAgICAgICAgICAgICRyLkluc3RhbGxlclBhdGg9JHByZXBhcmVkLlBhdGg7ICRyLkluc3RhbGxlclZlcnNpb249JHByZXBhcmVkLlZlcnNpb247ICRyLkluc3RhbGxlclNob3J0Y3V0PSRwcmVwYXJlZC5TaG9ydGN1dA0KICAgICAgICAgICAgJHIuU3RhdHVzPSdtYW51YWxfcmVxdWlyZWQnOyAkci5SZWFzb249JHByb2ZpbGUuQXV0b21hdGljUmVhc29uKycgSW5zdGFsbGF0ZXVyIHZlcmlmaWUgOiB1dGlsaXNleiBzb24gcmFjY291cmNpIHN1ciBsZSBCdXJlYXUgcG91ciBpbnN0YWxsZXIgbWFudWVsbGVtZW50LiBBdWN1biBpbnN0YWxsYXRldXIgZXhlY3V0ZSBwYXIgY2Ugc2NyaXB0LicNCiAgICAgICAgICAgIHJldHVybiBbcHNjdXN0b21vYmplY3RdJHINCiAgICAgICAgfQ0KICAgICAgICAkY2hlY2tlZD1UZXN0LU1ieFNpZ25lZFBheWxvYWQgLVBhdGggJHBhY2thZ2UuUGF0aCAtU2lnbmVycyAkcHJvZmlsZS5TaWduZXJzDQogICAgICAgIGlmICgkY2hlY2tlZC5TSEEyNTYgLW5lICRwYWNrYWdlLlNIQTI1NikgeyB0aHJvdyAnSW5zdGFsbGF0ZXVyIHJlbXBsYWNlIGRlcHVpcyBzYSB2ZXJpZmljYXRpb24uJyB9DQogICAgICAgICRleGl0Q29kZT1JbnZva2UtVnV0SW5zdGFsbGVyUHJvY2VzcyAtUGF0aCAkcGFja2FnZS5QYXRoIC1Bcmd1bWVudHMgJHByb2ZpbGUuSW5zdGFsbGVyQXJndW1lbnRzDQogICAgICAgIGlmICgkZXhpdENvZGUgLW5vdGluIEAoMCwzMDEwKSkgeyB0aHJvdyAiRWNoZWMgaW5zdGFsbGF0ZXVyIDogY29kZSAkZXhpdENvZGUuIEF1Y3VuZSBpbnN0YWxsYXRpb24gcmV1c3NpZSBhbm5vbmNlZS4iIH0NCiAgICAgICAgJHIuUmVib290UmVxdWlyZWQ9KCRleGl0Q29kZSAtZXEgMzAxMCkNCiAgICAgICAgJGFwcD1HZXQtVnV0SW5zdGFsbGVkQXBwbGljYXRpb24gJHByb2ZpbGUNCiAgICAgICAgJGluc3RhbGxlZFZlcnNpb249aWYgKCRhcHApIHsgQ29udmVydFRvLU1ieFZlcnNpb24gJGFwcC5WZXJzaW9uIH0gZWxzZSB7ICRudWxsIH0NCiAgICAgICAgJHRhcmdldFZlcnNpb249Q29udmVydFRvLU1ieFZlcnNpb24gJHBhY2thZ2UuVmVyc2lvbg0KICAgICAgICBpZiAoLW5vdCAkYXBwIC1vciAtbm90ICRhcHAuVmVyaWZpZWQgLW9yIC1ub3QgJGluc3RhbGxlZFZlcnNpb24gLW9yIC1ub3QgJHRhcmdldFZlcnNpb24gLW9yICRpbnN0YWxsZWRWZXJzaW9uIC1sdCAkdGFyZ2V0VmVyc2lvbikgeyB0aHJvdyAnSW5zdGFsbGF0ZXVyIHRlcm1pbmUgbWFpcyBhcHBsaWNhdGlvbi92ZXJzaW9uIG5vbiBjb25maXJtZWUgOyBhdWN1biByYWNjb3VyY2kgY3JlZS4nIH0NCiAgICAgICAgJHIuSW5zdGFsbGVkPS1ub3QgJHNjcmlwdDpVdGlsaXR5U2ltdWxhdGlvbg0KICAgICAgICAkci5JbnN0YWxsZWRUaGlzUnVuPS1ub3QgJHNjcmlwdDpVdGlsaXR5U2ltdWxhdGlvbjsgJHIuQXBwbGljYXRpb25WZXJpZmllZD0kdHJ1ZTsgJHIuQXBwbGljYXRpb25WZXJzaW9uPSRhcHAuVmVyc2lvbg0KICAgICAgICAkci5TaG9ydGN1dD1OZXctVnV0U2hvcnRjdXQgJHByb2ZpbGUgJGFwcA0KICAgICAgICAkci5TdGF0dXM9aWYgKCRzY3JpcHQ6VXRpbGl0eVNpbXVsYXRpb24pIHsgJ3NpbXVsYXRlZF9pbnN0YWxsZWQnIH0gZWxzZSB7ICdpbnN0YWxsZWQnIH0NCiAgICAgICAgJHIuUmVhc29uPSdBcHBsaWNhdGlvbiBldCByYWNjb3VyY2kgdmVyaWZpZXMuIE91dmVydHVyZSBtYW51ZWxsZSBwYXIgbGUgdGVjaG5pY2llbi4nDQogICAgICAgIHJldHVybiBbcHNjdXN0b21vYmplY3RdJHINCiAgICB9IGNhdGNoIHsgJHIuU3RhdHVzPSdmYWlsZWQnOyAkci5SZWFzb249JF8uRXhjZXB0aW9uLk1lc3NhZ2U7IHJldHVybiBbcHNjdXN0b21vYmplY3RdJHIgfQ0KfQ0KDQpFeHBvcnQtTW9kdWxlTWVtYmVyIC1GdW5jdGlvbiBJbnZva2UtVmVuZG9yVXRpbGl0eQ0K' }
    @{ Path = 'vendor-utility/VendorDiscovery.Gigabyte.ps1'; Sha256 = '10358E903E08825BB0892090C8B63C9793622A035FD2228F2D761425296A107C'; Base64 = 'I3JlcXVpcmVzIC1WZXJzaW9uIDUuMQ0KIyBEZWZpbml0aW9ucyBvbmx5LCBkb3Qtc291cmNlZCBpbnNpZGUgVmVuZG9yVXRpbGl0eS4gTm8gaW5zdGFsbGVyIGlzIGV2ZXIgaW52b2tlZCBoZXJlLg0KZnVuY3Rpb24gUmVzb2x2ZS1WdXRHaWdhYnl0ZUNvcmVEb3dubG9hZCB7DQogICAgIyBHQ0MncyBvd24gRXh0TElCX0xvYWRlcl9MaWIuV2ViX1N5bmNfQ2xhc3MgcmVhZHMgdGhpcyBzb2Z0d2FyZS1vbmx5DQogICAgIyBtYW5pZmVzdCBhbmQgY29uc3RydWN0cyB0aGlzIHBhdGguIE5vIGhhcmR3YXJlL2RyaXZlciBjYXRhbG9ndWUgaXMgcXVlcmllZC4NCiAgICAkdXJsPSdodHRwczovL21iLmRvd25sb2FkLmdpZ2FieXRlLmNvbS9GaWxlTGlzdC9Td2h0dHAvTGl2ZVVwZGF0ZTQvR0NDL0dJR0FCWVRFJTIwQ29udHJvbCUyMENlbnRlci92ZXIyLmluaScNCiAgICAkcmVzcG9uc2U9SW52b2tlLU1ieEh0dHAgLVVybCAkdXJsIC1Ib3N0cyBAKCdtYi5kb3dubG9hZC5naWdhYnl0ZS5jb20nKSAtVGltZW91dFNlY29uZHMgMzAgLU1heEJ5dGVzIDY1NTM2DQogICAgJHI9Q29udmVydEZyb20tVnV0R2lnYWJ5dGVDb3JlTWFuaWZlc3QgLVRleHQgKFtzdHJpbmddJHJlc3BvbnNlLlRleHQpDQogICAgJHIuTWFuaWZlc3RVcmw9JHJlc3BvbnNlLlVybA0KICAgIHJldHVybiAkcg0KfQ0KDQpmdW5jdGlvbiBDb252ZXJ0RnJvbS1WdXRHaWdhYnl0ZUNvcmVNYW5pZmVzdCB7DQogICAgcGFyYW0oW1BhcmFtZXRlcihNYW5kYXRvcnkpXVtBbGxvd0VtcHR5U3RyaW5nKCldW3N0cmluZ10kVGV4dCkNCiAgICBpZiAoJFRleHQuTGVuZ3RoIC1ndCA2NTUzNiAtb3IgJFRleHQgLW1hdGNoICdbXHgwMC1ceDA4XHgwYlx4MGNceDBlLVx4MWZceDdmXScpIHsgdGhyb3cgJ01hbmlmZXN0ZSBkdSBwcm9ncmFtbWUgR0NDIGludmFsaWRlIG91IHRyb3Agdm9sdW1pbmV1eC4nIH0NCiAgICAkaW5mbz1Ae307ICRzZWN0aW9uPScnOyAkaW5mb0NvdW50PTANCiAgICBmb3JlYWNoICgkbGluZSBpbiAkVGV4dCAtc3BsaXQgJ1xyP1xuJykgew0KICAgICAgICAkbGluZT0kbGluZS5UcmltKCkNCiAgICAgICAgaWYgKC1ub3QgJGxpbmUgLW9yICRsaW5lLlN0YXJ0c1dpdGgoJzsnKSkgeyBjb250aW51ZSB9DQogICAgICAgIGlmICgkbGluZSAtbWF0Y2ggJ1xBXFsoW15cXV0rKVxdXHonKSB7DQogICAgICAgICAgICAkc2VjdGlvbj0kTWF0Y2hlc1sxXQ0KICAgICAgICAgICAgaWYgKCRzZWN0aW9uIC1pZXEgJ0luZm8nKSB7ICRpbmZvQ291bnQrKyB9DQogICAgICAgICAgICBjb250aW51ZQ0KICAgICAgICB9DQogICAgICAgIGlmICgkc2VjdGlvbiAtaW5lICdJbmZvJykgeyBjb250aW51ZSB9DQogICAgICAgIGlmICgkbGluZSAtbm90bWF0Y2ggJ1xBKFtBLVphLXpdKyk9KC4qKVx6JykgeyB0aHJvdyAnRW50cmVlIEluZm8gR0NDIG1hbCBmb3JtZWUuJyB9DQogICAgICAgICRrZXk9JE1hdGNoZXNbMV07ICR2YWx1ZT0kTWF0Y2hlc1syXS5UcmltKCkNCiAgICAgICAgaWYgKCRpbmZvLkNvbnRhaW5zS2V5KCRrZXkpKSB7IHRocm93ICdNYW5pZmVzdGUgR0NDIGFtYmlndSA6IGNsZSBJbmZvIGR1cGxpcXVlZS4nIH0NCiAgICAgICAgJGluZm9bJGtleV09JHZhbHVlDQogICAgfQ0KICAgIGlmICgkaW5mb0NvdW50IC1uZSAxKSB7IHRocm93ICdTZWN0aW9uIEluZm8gR0NDIGFic2VudGUgb3UgYW1iaWd1ZS4nIH0NCiAgICBmb3JlYWNoICgka2V5IGluIEAoJ0FwTmFtZScsJ0Rpc3BsYXlOYW1lJywnQXBOdW0nLCdWZXInLCdTaXplJykpIHsgaWYgKC1ub3QgJGluZm8uQ29udGFpbnNLZXkoJGtleSkpIHsgdGhyb3cgKCdNYW5pZmVzdGUgR0NDIGluY29tcGxldCA6ICcrJGtleSsnIGFic2VudC4nKSB9IH0NCiAgICBpZiAoJGluZm8uQXBOYW1lIC1jbmUgJ0dJR0FCWVRFIENvbnRyb2wgQ2VudGVyJyAtb3IgJGluZm8uRGlzcGxheU5hbWUgLWNuZSAnR0lHQUJZVEUgQ29udHJvbCBDZW50ZXInIC1vciAkaW5mby5BcE51bSAtY25lICcwJykgeyB0aHJvdyAnTWFuaWZlc3RlIGhvcnMgZHUgc2V1bCBwcm9ncmFtbWUgR0lHQUJZVEUgQ29udHJvbCBDZW50ZXIuJyB9DQogICAgaWYgKCRpbmZvLlZlciAtbm90bWF0Y2ggJ1xBWzAtOV0rXC5bMC05XStcLlswLTldK1wuWzAtOV0rXHonIC1vciAtbm90IChDb252ZXJ0VG8tTWJ4VmVyc2lvbiAkaW5mby5WZXIpKSB7IHRocm93ICdWZXJzaW9uIGR1IHByb2dyYW1tZSBHQ0MgaW52YWxpZGUuJyB9DQogICAgJHNpemU9W2xvbmddMA0KICAgIGlmICgkaW5mby5TaXplIC1ub3RtYXRjaCAnXEFbMC05XStceicgLW9yIC1ub3QgW2xvbmddOjpUcnlQYXJzZSgkaW5mby5TaXplLFtyZWZdJHNpemUpIC1vciAkc2l6ZSAtbHQgMTAyNCAtb3IgJHNpemUgLWd0IDEwNzM3NDE4MjQpIHsgdGhyb3cgJ1RhaWxsZSBkdSBwcm9ncmFtbWUgR0NDIGFic2VudGUgb3UgaW52YWxpZGUuJyB9DQogICAgJGZpbGU9J0dJR0FCWVRFIENvbnRyb2wgQ2VudGVyXycrJGluZm8uVmVyKycuZXhlJw0KICAgIHJldHVybiBbcHNjdXN0b21vYmplY3RdQHsNCiAgICAgICAgTWFuaWZlc3RVcmw9J2h0dHBzOi8vbWIuZG93bmxvYWQuZ2lnYWJ5dGUuY29tL0ZpbGVMaXN0L1N3aHR0cC9MaXZlVXBkYXRlNC9HQ0MvR0lHQUJZVEUlMjBDb250cm9sJTIwQ2VudGVyL3ZlcjIuaW5pJw0KICAgICAgICBWZXJzaW9uPSRpbmZvLlZlcjtFeHBlY3RlZEJ5dGVzPSRzaXplO0ZpbGVOYW1lPSRmaWxlDQogICAgICAgIERvd25sb2FkVXJsPSgnaHR0cHM6Ly9tYi5kb3dubG9hZC5naWdhYnl0ZS5jb20vRmlsZUxpc3QvU3dodHRwL0xpdmVVcGRhdGU0L0dDQy9HSUdBQllURSUyMENvbnRyb2wlMjBDZW50ZXIvJytbdXJpXTo6RXNjYXBlRGF0YVN0cmluZygkZmlsZSkpDQogICAgICAgIE1ldGhvZD0nb2ZmaWNpYWxfZ2NjX3NvZnR3YXJlX3VwZGF0ZV9tYW5pZmVzdCcNCiAgICB9DQp9DQoNCmZ1bmN0aW9uIFJlc29sdmUtVnV0R2lnYWJ5dGVEb3dubG9hZCB7DQogICAgJG1hbmlmZXN0VXJsPSdodHRwczovL3d3dy5naWdhYnl0ZS5jb20vQWpheC9TdXBwb3J0RnVuY3Rpb24vR2V0VXRpbGl0eUFqYXg/Q2xhc3NHcm91cD0yJlBhZ2U9MSZLZXlXb3JkPUdJR0FCWVRFJTIwQ29udHJvbCUyMENlbnRlcicNCiAgICAkc291cmNlcz1AKA0KICAgICAgICBAe1VybD0kbWFuaWZlc3RVcmw7QWdlbnQ9J01vdGhlcmJvYXJkRmVhc2liaWxpdHkvMS4wJztDbGllbnQ9J2RlZmF1bHQnfSwNCiAgICAgICAgQHtVcmw9JG1hbmlmZXN0VXJsO0FnZW50PSdNb3ppbGxhLzUuMCAoV2luZG93cyBOVCAxMC4wOyBXaW42NDsgeDY0KSc7Q2xpZW50PSdicm93c2VyX3VzZXJfYWdlbnQnfSwNCiAgICAgICAgQHtVcmw9J2h0dHBzOi8vd3d3LmdpZ2FieXRlLmNvbS9Db25zdW1lci9Tb2Z0d2FyZS9HSUdBQllURS1Db250cm9sLUNlbnRlci9nbG9iYWwvJztBZ2VudD0nTW96aWxsYS81LjAgKFdpbmRvd3MgTlQgMTAuMDsgV2luNjQ7IHg2NCknO0NsaWVudD0nb2ZmaWNpYWxfcHJvZHVjdF9wYWdlJ30NCiAgICApDQogICAgJGZhaWx1cmVzPUAoKQ0KICAgIGZvcmVhY2ggKCRzb3VyY2UgaW4gJHNvdXJjZXMpIHsNCiAgICAgICAgdHJ5IHsgJHJlc3BvbnNlPUludm9rZS1NYnhIdHRwIC1VcmwgJHNvdXJjZS5VcmwgLUhvc3RzIEAoJ3d3dy5naWdhYnl0ZS5jb20nKSAtVGltZW91dFNlY29uZHMgMzAgLU1heEJ5dGVzIDIwOTcxNTIgLVVzZXJBZ2VudCAkc291cmNlLkFnZW50IH0NCiAgICAgICAgY2F0Y2ggew0KICAgICAgICAgICAgaWYgKCRfLkV4Y2VwdGlvbi5NZXNzYWdlIC1ub3RtYXRjaCAnSFRUUCA0MDNcYicpIHsgdGhyb3cgfQ0KICAgICAgICAgICAgJGZhaWx1cmVzKz0oJHNvdXJjZS5DbGllbnQrJzogSFRUUCA0MDMnKTsgY29udGludWUNCiAgICAgICAgfQ0KICAgICAgICAkcmVzb2x2ZWQ9Q29udmVydEZyb20tVnV0R2lnYWJ5dGVDYXRhbG9ndWUgLUh0bWwgKFtzdHJpbmddJHJlc3BvbnNlLlRleHQpDQogICAgICAgICRyZXNvbHZlZC5NYW5pZmVzdFVybD0kcmVzcG9uc2UuVXJsDQogICAgICAgICRyZXNvbHZlZCB8IEFkZC1NZW1iZXIgLU5vdGVQcm9wZXJ0eU5hbWUgU291cmNlQ2xpZW50IC1Ob3RlUHJvcGVydHlWYWx1ZSAkc291cmNlLkNsaWVudA0KICAgICAgICByZXR1cm4gJHJlc29sdmVkDQogICAgfQ0KICAgIHRocm93ICgnQ2F0YWxvZ3VlIEdJR0FCWVRFIG9mZmljaWVsIGluYWNjZXNzaWJsZSAoJysoJGZhaWx1cmVzIC1qb2luICc7ICcpKycpLiBBdWN1bmUgYW5jaWVubmUgdmVyc2lvbiB1dGlsaXNlZS4nKQ0KfQ0KDQpmdW5jdGlvbiBDb252ZXJ0RnJvbS1WdXRHaWdhYnl0ZUNhdGFsb2d1ZSB7DQogICAgcGFyYW0oW1BhcmFtZXRlcihNYW5kYXRvcnkpXVtzdHJpbmddJEh0bWwpDQogICAgJG1hbmlmZXN0VXJsPSdodHRwczovL3d3dy5naWdhYnl0ZS5jb20vQWpheC9TdXBwb3J0RnVuY3Rpb24vR2V0VXRpbGl0eUFqYXg/Q2xhc3NHcm91cD0yJlBhZ2U9MSZLZXlXb3JkPUdJR0FCWVRFJTIwQ29udHJvbCUyMENlbnRlcicNCiAgICBpZiAoJEh0bWwuTGVuZ3RoIC1ndCAyMDk3MTUyKSB7IHRocm93ICdDYXRhbG9ndWUgR0lHQUJZVEUgdHJvcCB2b2x1bWluZXV4LicgfQ0KICAgICRjYW5kaWRhdGVzPUAoKQ0KICAgIGZvcmVhY2ggKCRtYXRjaCBpbiBbcmVnZXhdOjpNYXRjaGVzKCRodG1sLCcoP2lzKVxiaHJlZlxzKj1ccypbIicnXShbXiInJ10rKVsiJyddJykpIHsNCiAgICAgICAgJGhyZWY9W05ldC5XZWJVdGlsaXR5XTo6SHRtbERlY29kZSgkbWF0Y2guR3JvdXBzWzFdLlZhbHVlKQ0KICAgICAgICBpZiAoJGhyZWYgLW1hdGNoICdbXHgwMC1ceDIwXHg3Zl0nKSB7IGNvbnRpbnVlIH0NCiAgICAgICAgdHJ5IHsgJHVyaT1OZXctT2JqZWN0IHVyaShbdXJpXSRtYW5pZmVzdFVybCwkaHJlZikgfSBjYXRjaCB7IGNvbnRpbnVlIH0NCiAgICAgICAgaWYgKCR1cmkuU2NoZW1lIC1uZSAnaHR0cHMnIC1vciAkdXJpLlBvcnQgLW5lIDQ0MyAtb3IgJHVyaS5Vc2VySW5mbyAtb3IgJHVyaS5GcmFnbWVudCAtb3IgJHVyaS5EbnNTYWZlSG9zdCAtaW5lICdkb3dubG9hZC5naWdhYnl0ZS5jb20nKSB7IGNvbnRpbnVlIH0NCiAgICAgICAgJGZpbGU9W3VyaV06OlVuZXNjYXBlRGF0YVN0cmluZygkdXJpLlNlZ21lbnRzWy0xXSkNCiAgICAgICAgaWYgKCRmaWxlIC1ub3RtYXRjaCAnXEFHQ0NfKFswLTldK1wuWzAtOV0rXC5bMC05XStcLlswLTldKylcLnppcFx6JykgeyBjb250aW51ZSB9DQogICAgICAgICRyYXdWZXJzaW9uPSRNYXRjaGVzWzFdOyAkdmVyc2lvbj1Db252ZXJ0VG8tTWJ4VmVyc2lvbiAkcmF3VmVyc2lvbg0KICAgICAgICBpZiAoLW5vdCAkdmVyc2lvbikgeyBjb250aW51ZSB9DQogICAgICAgICRjYW5kaWRhdGVzKz1AKFtwc2N1c3RvbW9iamVjdF1AeyBCdW5kbGVWZXJzaW9uPSRyYXdWZXJzaW9uOyBQYXJzZWRWZXJzaW9uPSR2ZXJzaW9uOyBEb3dubG9hZFVybD0kdXJpLkFic29sdXRlVXJpIH0pDQogICAgfQ0KICAgIGlmICgtbm90ICRjYW5kaWRhdGVzLkNvdW50KSB7IHRocm93ICdDYXRhbG9ndWUgR0lHQUJZVEUgb2ZmaWNpZWwgc2FucyBsaWVuIEdDQyB2YWxpZGUgOyBhdWN1bmUgYW5jaWVubmUgdmVyc2lvbiBkZSBzZWNvdXJzLicgfQ0KICAgICRncm91cHM9QCgkY2FuZGlkYXRlcyB8IEdyb3VwLU9iamVjdCB7ICRfLlBhcnNlZFZlcnNpb24uVG9TdHJpbmcoKSB9KQ0KICAgIGZvcmVhY2ggKCRncm91cCBpbiAkZ3JvdXBzKSB7DQogICAgICAgICR1cmxzPUAoJGdyb3VwLkdyb3VwIHwgU2VsZWN0LU9iamVjdCAtRXhwYW5kUHJvcGVydHkgRG93bmxvYWRVcmwgLVVuaXF1ZSkNCiAgICAgICAgaWYgKCR1cmxzLkNvdW50IC1uZSAxKSB7IHRocm93ICdDYXRhbG9ndWUgR0lHQUJZVEUgYW1iaWd1IDogcGx1c2lldXJzIGZpY2hpZXJzIHBvdXIgdW5lIG1lbWUgdmVyc2lvbi4nIH0NCiAgICB9DQogICAgZm9yZWFjaCAoJGlucHV0VGFnIGluIFtyZWdleF06Ok1hdGNoZXMoJGh0bWwsJyg/aXMpPGlucHV0XGJbXj5dKj4nKSkgew0KICAgICAgICBpZiAoJGlucHV0VGFnLlZhbHVlIC1tYXRjaCAnKD9pKVxiaWRccyo9XHMqWyInJ11ub3dfcGFnZVsiJyddJyAtYW5kICRpbnB1dFRhZy5WYWx1ZSAtbWF0Y2ggJyg/aSlcYnZhbHVlXHMqPVxzKlsiJyddKFteIicnXSspWyInJ10nKSB7DQogICAgICAgICAgICBpZiAoJE1hdGNoZXNbMV0gLW5lICcxJykgeyB0aHJvdyAnQ2F0YWxvZ3VlIEdJR0FCWVRFIHBhZ2luZSBpbmNvbXBsZXQgOiBwcmVtaWVyZSBwYWdlIG5vbiBjb25maXJtZWUuJyB9DQogICAgICAgIH0NCiAgICB9DQogICAgZm9yZWFjaCAoJHRvdGFsIGluIFtyZWdleF06Ok1hdGNoZXMoJGh0bWwsJyg/aXMpPHNwYW5cYltePl0qY2xhc3Nccyo9XHMqWyInJ11pdGVtc1siJyddW14+XSo+XHMqKFtePF0rKVxzKjwvc3Bhbj4nKSkgew0KICAgICAgICAkY291bnRUZXh0PSR0b3RhbC5Hcm91cHNbMV0uVmFsdWUuVHJpbSgpOyAkY291bnQ9MA0KICAgICAgICBpZiAoLW5vdCBbaW50XTo6VHJ5UGFyc2UoJGNvdW50VGV4dCxbcmVmXSRjb3VudCkgLW9yICRjb3VudCAtbmUgJGdyb3Vwcy5Db3VudCkgeyB0aHJvdyAnQ2F0YWxvZ3VlIEdJR0FCWVRFIHBhZ2luZSBpbmNvbXBsZXQgb3UgaW5jb2hlcmVudCA6IHRvdXMgbGVzIGVsZW1lbnRzIG5lIHNvbnQgcGFzIGRpc3BvbmlibGVzIDsgZGVybmllcmUgdmVyc2lvbiBub24gZXRhYmxpZS4nIH0NCiAgICB9DQogICAgJGxhdGVzdD1AKCRjYW5kaWRhdGVzIHwgU29ydC1PYmplY3QgUGFyc2VkVmVyc2lvbiAtRGVzY2VuZGluZylbMF0NCiAgICByZXR1cm4gW3BzY3VzdG9tb2JqZWN0XUB7DQogICAgICAgIE1hbmlmZXN0VXJsPSRtYW5pZmVzdFVybDsgQnVuZGxlVmVyc2lvbj0kbGF0ZXN0LkJ1bmRsZVZlcnNpb24NCiAgICAgICAgRG93bmxvYWRVcmw9JGxhdGVzdC5Eb3dubG9hZFVybDsgTWV0aG9kPSdvZmZpY2lhbF9naWdhYnl0ZV91dGlsaXR5X2h0bWwnDQogICAgfQ0KfQ0K' }
    @{ Path = 'vendor-utility/VendorDiscovery.Asrock.ps1'; Sha256 = '9DE7665FA6C2B9F7C61F1E6A482D2959F7ECD9359D8892F29B53D7BA277BB7C7'; Base64 = 'I3JlcXVpcmVzIC1WZXJzaW9uIDUuMQ0KIyBQcml2YXRlIGZ1bmN0aW9ucyBkb3Qtc291cmNlZCBieSBWZW5kb3JVdGlsaXR5LnBzbTEuIERpc2NvdmVyeSBvbmx5OiBubyBpbnN0YWxsZXIgZXhlY3V0aW9uLg0KZnVuY3Rpb24gQ29udmVydEZyb20tVnV0QXNyb2NrWG1sIHsNCiAgICBwYXJhbShbUGFyYW1ldGVyKE1hbmRhdG9yeSldW3N0cmluZ10kVGV4dCxbUGFyYW1ldGVyKE1hbmRhdG9yeSldW3N0cmluZ10kU291cmNlKQ0KICAgICRzZXR0aW5ncz1OZXctT2JqZWN0IFhtbC5YbWxSZWFkZXJTZXR0aW5ncw0KICAgICRzZXR0aW5ncy5EdGRQcm9jZXNzaW5nPVtYbWwuRHRkUHJvY2Vzc2luZ106OlByb2hpYml0DQogICAgJHNldHRpbmdzLlhtbFJlc29sdmVyPSRudWxsDQogICAgJHNldHRpbmdzLk1heENoYXJhY3RlcnNJbkRvY3VtZW50PTIwOTcxNTINCiAgICAkc3RyaW5nUmVhZGVyPU5ldy1PYmplY3QgSU8uU3RyaW5nUmVhZGVyKCRUZXh0KQ0KICAgICRyZWFkZXI9JG51bGwNCiAgICB0cnkgew0KICAgICAgICAkcmVhZGVyPVtYbWwuWG1sUmVhZGVyXTo6Q3JlYXRlKCRzdHJpbmdSZWFkZXIsJHNldHRpbmdzKQ0KICAgICAgICAkZG9jdW1lbnQ9TmV3LU9iamVjdCBYbWwuWG1sRG9jdW1lbnQNCiAgICAgICAgJGRvY3VtZW50LlhtbFJlc29sdmVyPSRudWxsDQogICAgICAgICRkb2N1bWVudC5Mb2FkKCRyZWFkZXIpDQogICAgICAgIHJldHVybiAsJGRvY3VtZW50DQogICAgfSBjYXRjaCB7IHRocm93ICgnU291cmNlIEFTUm9jayAnKyRTb3VyY2UrJyA6IFhNTCBvZmZpY2llbCBpbnZhbGlkZSBvdSBwYWdlIGRlIHByb3RlY3Rpb24gOyBhdWN1biBhbmNpZW4gZmljaGllciBzZWxlY3Rpb25uZS4gJyskXy5FeGNlcHRpb24uTWVzc2FnZSkgfQ0KICAgIGZpbmFsbHkgeyBpZiAoJHJlYWRlcikgeyAkcmVhZGVyLkRpc3Bvc2UoKSB9OyAkc3RyaW5nUmVhZGVyLkRpc3Bvc2UoKSB9DQp9DQoNCmZ1bmN0aW9uIFJlc29sdmUtVnV0QXNyb2NrRG93bmxvYWQgew0KICAgIFtDbWRsZXRCaW5kaW5nKCldDQogICAgcGFyYW0oW1BhcmFtZXRlcihNYW5kYXRvcnkpXVtzdHJpbmddJE1vZGVsLFtQYXJhbWV0ZXIoTWFuZGF0b3J5KV1bc3RyaW5nXSRUYXJnZXRPcykNCiAgICAkcmVxdWVzdGVkPSRNb2RlbC5UcmltKCkNCiAgICBpZiAoLW5vdCAkcmVxdWVzdGVkIC1vciAkcmVxdWVzdGVkLkxlbmd0aCAtZ3QgMTUwIC1vciAkcmVxdWVzdGVkIC1tYXRjaCAnW1x4MDAtXHgxRlx4N0ZdJykgeyB0aHJvdyAnQVNSb2NrIDogbW9kZWxlIGRlIGNhcnRlIG1lcmUgYWJzZW50IG91IGludmFsaWRlLicgfQ0KICAgIGlmICgkVGFyZ2V0T3MgLWNub3RpbiBAKCdXaW5kb3dzIDEwIDY0Yml0JywnV2luZG93cyAxMSA2NGJpdCcpKSB7IHRocm93ICdBU1JvY2sgOiBzeXN0ZW1lIGNpYmxlIG5vbiBhdXRvcmlzZSA7IFdpbmRvd3MgMTAvMTEgNjQgYml0cyBleHBsaWNpdGUgcmVxdWlzLicgfQ0KICAgICRtb2RlbFNvdXJjZVVybD0naHR0cHM6Ly9kb3dubG9hZC5hc3JvY2suY29tL3NldHVwL0Jyb3dzZXIueG1sJw0KICAgICRyZXNwb25zZT1JbnZva2UtTWJ4SHR0cCAtVXJsICRtb2RlbFNvdXJjZVVybCAtSG9zdHMgQCgnZG93bmxvYWQuYXNyb2NrLmNvbScpIC1UaW1lb3V0U2Vjb25kcyAzMCAtTWF4Qnl0ZXMgMjA5NzE1Mg0KICAgICRicm93c2VyPUNvbnZlcnRGcm9tLVZ1dEFzcm9ja1htbCAtVGV4dCAoW3N0cmluZ10oR2V0LU1ieFZhbHVlICRyZXNwb25zZSAnVGV4dCcpKSAtU291cmNlICdCcm93c2VyLnhtbCcNCiAgICBpZiAoLW5vdCAkYnJvd3Nlci5Eb2N1bWVudEVsZW1lbnQgLW9yICRicm93c2VyLkRvY3VtZW50RWxlbWVudC5OYW1lIC1jbmUgJ1Jvb3QnKSB7IHRocm93ICdBU1JvY2sgOiBzdHJ1Y3R1cmUgQnJvd3Nlci54bWwgaW5hdHRlbmR1ZSA7IGNvbXBhdGliaWxpdGUgbm9uIGNvbmZpcm1lZS4nIH0NCiAgICAkbWF0Y2hlcz1AKCRicm93c2VyLlNlbGVjdE5vZGVzKCcvUm9vdC9TdXBwb3J0TW9kZWwvSXRlbScpIHwgV2hlcmUtT2JqZWN0IHsgJF8uR2V0QXR0cmlidXRlKCdNb2RlbCcpLlRyaW0oKSAtaWVxICRyZXF1ZXN0ZWQgfSkNCiAgICBpZiAoLW5vdCAkbWF0Y2hlcy5Db3VudCkgeyB0aHJvdyAoJ0FTUm9jayA6IG1vZGVsZSBub24gcHJlc2VudCBkYW5zIGxhIGxpc3RlIG9mZmljaWVsbGUgOiAnKyRyZXF1ZXN0ZWQrJy4gQXVjdW4gaW5zdGFsbGF0ZXVyIHNlbGVjdGlvbm5lLicpIH0NCiAgICAkY2Fub25pY2FsPSRtYXRjaGVzWzBdLkdldEF0dHJpYnV0ZSgnTW9kZWwnKS5UcmltKCkNCiAgICAkbWFuaWZlc3RVcmw9J2h0dHBzOi8vd3d3LmFzcm9jay5jb20vc3VwcG9ydC9MaXZlVXBkYXRlLmFzcD9QbGF0Zm9ybT1BcHAmTW9kZWw9JytbdXJpXTo6RXNjYXBlRGF0YVN0cmluZygkY2Fub25pY2FsKQ0KICAgICRyZXNwb25zZT1JbnZva2UtTWJ4SHR0cCAtVXJsICRtYW5pZmVzdFVybCAtSG9zdHMgQCgnd3d3LmFzcm9jay5jb20nKSAtVGltZW91dFNlY29uZHMgMzAgLU1heEJ5dGVzIDEwNDg1NzYNCiAgICAkbWFuaWZlc3Q9Q29udmVydEZyb20tVnV0QXNyb2NrWG1sIC1UZXh0IChbc3RyaW5nXShHZXQtTWJ4VmFsdWUgJHJlc3BvbnNlICdUZXh0JykpIC1Tb3VyY2UgJ0xpdmVVcGRhdGUnDQogICAgaWYgKC1ub3QgJG1hbmlmZXN0LkRvY3VtZW50RWxlbWVudCAtb3IgJG1hbmlmZXN0LkRvY3VtZW50RWxlbWVudC5OYW1lIC1jbmUgJ0xpdmVVcGRhdGUnIC1vciAkbWFuaWZlc3QuRG9jdW1lbnRFbGVtZW50LkdldEF0dHJpYnV0ZSgnTW9kZWwnKS5UcmltKCkgLWluZSAkY2Fub25pY2FsKSB7DQogICAgICAgIHRocm93ICdBU1JvY2sgOiBtb2RlbGUgZHUgY2F0YWxvZ3VlIG9mZmljaWVsIGRpZmZlcmVudCBkdSBtb2RlbGUgZGVtYW5kZSA7IGF1Y3VuIGFsaWFzIG91IGFuY2llbiBmaWNoaWVyIHN1cHBvc2UuJw0KICAgIH0NCiAgICAjIFJlc3RyaWN0IHNlbGVjdGlvbiB0byB0aGUgdXRpbGl0eSBzZWN0aW9uLiBCSU9TLCBkcml2ZXJzLCBhZHZlcnRzIGFuZCB0aGVpciBVUkxzIGFyZSBuZXZlciBpbnNwZWN0ZWQuDQogICAgJGVudHJpZXM9QCgkbWFuaWZlc3QuU2VsZWN0Tm9kZXMoJy9MaXZlVXBkYXRlL1V0aWxpdHkvKicpIHwgV2hlcmUtT2JqZWN0IHsNCiAgICAgICAgJGRlc2NyaXB0aW9uPSRfLlNlbGVjdFNpbmdsZU5vZGUoJ0Rlc2NyaXB0aW9uJykNCiAgICAgICAgJF8uR2V0QXR0cmlidXRlKCdUaXRsZScpIC1pZXEgJ0FTUm9jayBBUFAgU2hvcCcgLW9yICgkZGVzY3JpcHRpb24gLWFuZCAkZGVzY3JpcHRpb24uSW5uZXJUZXh0LlRyaW0oKSAtaWVxICdBUFAgU2hvcCcpDQogICAgfSkNCiAgICBpZiAoLW5vdCAkZW50cmllcy5Db3VudCkgeyB0aHJvdyAoJ0FTUm9jayA6IEFQUCBTaG9wIGFic2VudCBkdSBjYXRhbG9ndWUgb2ZmaWNpZWwgcG91ciAnKyRjYW5vbmljYWwrJy4gQXVjdW4gcmVwbGkgdmVycyB1bmUgYW5jaWVubmUgdmVyc2lvbi4nKSB9DQogICAgJGNhbmRpZGF0ZXM9QCgpDQogICAgZm9yZWFjaCAoJGVudHJ5IGluICRlbnRyaWVzKSB7DQogICAgICAgICRkZXNjcmlwdGlvbj0kZW50cnkuU2VsZWN0U2luZ2xlTm9kZSgnRGVzY3JpcHRpb24nKQ0KICAgICAgICBpZiAoJGVudHJ5LkdldEF0dHJpYnV0ZSgnVGl0bGUnKSAtaW5lICdBU1JvY2sgQVBQIFNob3AnIC1vciAtbm90ICRkZXNjcmlwdGlvbiAtb3IgJGRlc2NyaXB0aW9uLklubmVyVGV4dC5UcmltKCkgLWluZSAnQVBQIFNob3AnKSB7IHRocm93ICdBU1JvY2sgOiBpZGVudGl0ZSBBUFAgU2hvcCBpbmNvaGVyZW50ZSBkYW5zIGxlIGNhdGFsb2d1ZSBvZmZpY2llbC4nIH0NCiAgICAgICAgJHZlcnNpb25UZXh0PSRlbnRyeS5HZXRBdHRyaWJ1dGUoJ1ZlcnNpb24nKQ0KICAgICAgICAkdmVyc2lvbj1Db252ZXJ0VG8tTWJ4VmVyc2lvbiAkdmVyc2lvblRleHQNCiAgICAgICAgaWYgKCR2ZXJzaW9uVGV4dCAtbm90bWF0Y2ggJ1xBWzAtOV0rKD86XC5bMC05XSspezEsM31ceicgLW9yIC1ub3QgJHZlcnNpb24pIHsgdGhyb3cgJ0FTUm9jayA6IHZlcnNpb24gQVBQIFNob3AgYWJzZW50ZSBvdSBpbnZhbGlkZSA7IGF1Y3VuZSBhbmNpZW5uZSB2ZXJzaW9uIHNlbGVjdGlvbm5lZS4nIH0NCiAgICAgICAgJGNhbmRpZGF0ZXMrPSxbcHNjdXN0b21vYmplY3RdQHtFbnRyeT0kZW50cnk7VmVyc2lvbj0kdmVyc2lvbjtWZXJzaW9uVGV4dD0kdmVyc2lvblRleHR9DQogICAgfQ0KICAgICMgU2VsZWN0IHRoZSBuZXdlc3QgYWN0aXZlIHZlcnNpb24gYmVmb3JlIGNoZWNraW5nIGl0cyBPUy4gTmV2ZXIgc2lsZW50bHkgZmFsbCBiYWNrIHRvIGFuIG9sZGVyIGNvbXBhdGlibGUgdmVyc2lvbi4NCiAgICAkbGF0ZXN0PUAoJGNhbmRpZGF0ZXMgfCBTb3J0LU9iamVjdCBWZXJzaW9uIC1EZXNjZW5kaW5nKVswXS5WZXJzaW9uDQogICAgJGNhbmRpZGF0ZXM9QCgkY2FuZGlkYXRlcyB8IFdoZXJlLU9iamVjdCBWZXJzaW9uIC1lcSAkbGF0ZXN0KQ0KICAgICRjYW5kaWRhdGVzPUAoJGNhbmRpZGF0ZXMgfCBXaGVyZS1PYmplY3Qgew0KICAgICAgICBAKCRfLkVudHJ5LlNlbGVjdE5vZGVzKCdGaWxlJykgfCBXaGVyZS1PYmplY3QgeyAkXy5HZXRBdHRyaWJ1dGUoJ09TJykgLWNlcSAkVGFyZ2V0T3MgfSkuQ291bnQgLWd0IDANCiAgICB9KQ0KICAgIGlmICgtbm90ICRjYW5kaWRhdGVzLkNvdW50KSB7IHRocm93ICgnQVNSb2NrIDogZGVybmllcmUgdmVyc2lvbiAnKyRsYXRlc3QrJyBub24gcHJvcG9zZWUgcG91ciAnKyRUYXJnZXRPcysnIHN1ciAnKyRjYW5vbmljYWwrJyA7IGF1Y3VuIHJlcGxpIGFuY2llbi4nKSB9DQogICAgJHJlc29sdmVkPUAoKQ0KICAgIGZvcmVhY2ggKCRjYW5kaWRhdGUgaW4gJGNhbmRpZGF0ZXMpIHsNCiAgICAgICAgJGVudHJ5PSRjYW5kaWRhdGUuRW50cnk7ICR2ZXJzaW9uVGV4dD0kY2FuZGlkYXRlLlZlcnNpb25UZXh0DQogICAgICAgICRoYXNoTm9kZXM9QCgkZW50cnkuU2VsZWN0Tm9kZXMoJ0hBU0gnKSkNCiAgICAgICAgaWYgKCRoYXNoTm9kZXMuQ291bnQgLW5lIDEgLW9yICRoYXNoTm9kZXNbMF0uSW5uZXJUZXh0LlRyaW0oKSAtbm90bWF0Y2ggJ1xBWzAtOWEtZkEtRl17NjR9XHonKSB7IHRocm93ICdBU1JvY2sgOiBTSEEyNTYgb2ZmaWNpZWwgYWJzZW50LCBtdWx0aXBsZSBvdSBpbnZhbGlkZS4nIH0NCiAgICAgICAgJGhhc2g9JGhhc2hOb2Rlc1swXS5Jbm5lclRleHQuVHJpbSgpLlRvVXBwZXJJbnZhcmlhbnQoKQ0KICAgICAgICAkZXhlTm9kZXM9QCgkZW50cnkuU2VsZWN0Tm9kZXMoJ0ZpbGVFeGVjdXRlJykpDQogICAgICAgICRwYXJhbWV0ZXJOb2Rlcz1AKCRlbnRyeS5TZWxlY3ROb2RlcygnRmlsZVBhcmFtZXRlcicpKQ0KICAgICAgICBpZiAoJGV4ZU5vZGVzLkNvdW50IC1uZSAxIC1vciAkcGFyYW1ldGVyTm9kZXMuQ291bnQgLW5lIDEpIHsgdGhyb3cgJ0FTUm9jayA6IGNoZW1pbiBleGVjdXRhYmxlIG91IHBhcmFtZXRyZXMgYWJzZW50cy9hbWJpZ3VzLicgfQ0KICAgICAgICAkZXhlUGF0aD0kZXhlTm9kZXNbMF0uSW5uZXJUZXh0LlRyaW0oKS5SZXBsYWNlKCdcJywnLycpDQogICAgICAgICRleHBlY3RlZEV4ZT0nQVBQU2hvcCh2JyskdmVyc2lvblRleHQrJykvQVBQU2hvcFNldHVwKHYnKyR2ZXJzaW9uVGV4dCsnKS5leGUnDQogICAgICAgIGlmICgkZXhlUGF0aCAtY25lICRleHBlY3RlZEV4ZSAtb3IgJGV4ZVBhdGggLW1hdGNoICdcLlwufDp8XEEvJykgeyB0aHJvdyAnQVNSb2NrIDogY2hlbWluIGV4ZWN1dGFibGUgaW5hdHRlbmR1IG91IHZlcnNpb24gaW5jb2hlcmVudGUuJyB9DQogICAgICAgICRwYXJhbWV0ZXJzPSRwYXJhbWV0ZXJOb2Rlc1swXS5Jbm5lclRleHQuVHJpbSgpDQogICAgICAgIGlmICgkcGFyYW1ldGVycyAtaW5lICcvVmVyeVNpbGVudCcpIHsgdGhyb3cgJ0FTUm9jayA6IHBhcmFtZXRyZXMgb2ZmaWNpZWxzIGluYXR0ZW5kdXMgOyBhdWN1biBjb21tdXRhdGV1ciBwcml2ZSBvdSBsYW5jZW1lbnQgYXV0b3Jpc2UuJyB9DQogICAgICAgICRmaWxlcz1AKCRlbnRyeS5TZWxlY3ROb2RlcygnRmlsZScpIHwgV2hlcmUtT2JqZWN0IHsgJF8uR2V0QXR0cmlidXRlKCdPUycpIC1jZXEgJFRhcmdldE9zIH0pDQogICAgICAgIGlmICgtbm90ICRmaWxlcy5Db3VudCkgeyB0aHJvdyAoJ0FTUm9jayA6IGRlcm5pZXJlIHZlcnNpb24gJyskdmVyc2lvblRleHQrJyBub24gcHJvcG9zZWUgcG91ciAnKyRUYXJnZXRPcysnIHN1ciAnKyRjYW5vbmljYWwrJyA7IGF1Y3VuIHJlcGxpIGFuY2llbi4nKSB9DQogICAgICAgIGZvcmVhY2ggKCRmaWxlIGluICRmaWxlcykgew0KICAgICAgICAgICAgJHZhbHVlPSRmaWxlLklubmVyVGV4dC5UcmltKCkNCiAgICAgICAgICAgICRleHBlY3RlZFBhdGg9Jy9VdGlsaXR5L090aGVycy9BUFBTaG9wKHYnKyR2ZXJzaW9uVGV4dCsnKS56aXAnDQogICAgICAgICAgICBpZiAoJHZhbHVlIC1tYXRjaCAnKD9pKSUyZXwlMmZ8JTVjfFxcfFwuXC4nIC1vciAkdmFsdWUgLW1hdGNoICdbXHgwMC1ceDIwXHg3Rl0nKSB7IHRocm93ICdBU1JvY2sgOiBVUkwgZGUgdGVsZWNoYXJnZW1lbnQgb3UgY2hlbWluIG5vbiBhdXRvcmlzZS4nIH0NCiAgICAgICAgICAgIGlmICgkdmFsdWUuU3RhcnRzV2l0aCgnLycpKSB7ICR1cmw9J2h0dHBzOi8vZG93bmxvYWQuYXNyb2NrLmNvbScrJHZhbHVlIH0gZWxzZSB7ICR1cmw9JHZhbHVlIH0NCiAgICAgICAgICAgICR1cmk9JG51bGwNCiAgICAgICAgICAgIGlmICgtbm90IFt1cmldOjpUcnlDcmVhdGUoJHVybCxbVXJpS2luZF06OkFic29sdXRlLFtyZWZdJHVyaSkgLW9yICR1cmkuU2NoZW1lIC1jbmUgJ2h0dHBzJyAtb3IgJHVyaS5Ib3N0IC1pbmUgJ2Rvd25sb2FkLmFzcm9jay5jb20nIC1vciAkdXJpLlBvcnQgLW5lIDQ0MyAtb3IgJHVyaS5Vc2VySW5mbyAtb3IgJHVyaS5RdWVyeSAtb3IgJHVyaS5GcmFnbWVudCAtb3IgW3VyaV06OlVuZXNjYXBlRGF0YVN0cmluZygkdXJpLkFic29sdXRlUGF0aCkgLWNuZSAkZXhwZWN0ZWRQYXRoKSB7DQogICAgICAgICAgICAgICAgdGhyb3cgJ0FTUm9jayA6IFVSTCBvZmZpY2llbGxlLCBub20gZHUgWklQIG91IHZlcnNpb24gZHUgZmljaGllciBpbmNvaGVyZW50LicNCiAgICAgICAgICAgIH0NCiAgICAgICAgICAgICRyZXNvbHZlZCs9LFtwc2N1c3RvbW9iamVjdF1Aew0KICAgICAgICAgICAgICAgIE1vZGVsPSRjYW5vbmljYWw7UmVxdWVzdGVkTW9kZWw9JHJlcXVlc3RlZDtUYXJnZXRPcz0kVGFyZ2V0T3M7VmVyc2lvbj0kdmVyc2lvblRleHQNCiAgICAgICAgICAgICAgICBNYW5pZmVzdFVybD0kbWFuaWZlc3RVcmw7TW9kZWxTb3VyY2VVcmw9JG1vZGVsU291cmNlVXJsO0Rvd25sb2FkVXJsPSR1cmkuQWJzb2x1dGVVcmkNCiAgICAgICAgICAgICAgICBBcmNoaXZlU0hBMjU2PSRoYXNoO0luc3RhbGxlclJlbGF0aXZlUGF0aD0kZXhlUGF0aDtJbnN0YWxsZXJQYXJhbWV0ZXJzPSRwYXJhbWV0ZXJzDQogICAgICAgICAgICAgICAgTWV0aG9kPSdvZmZpY2lhbF9hc3JvY2tfbW9kZWxfeG1sJw0KICAgICAgICAgICAgfQ0KICAgICAgICB9DQogICAgfQ0KICAgICRpZGVudGl0aWVzPUAoJHJlc29sdmVkIHwgRm9yRWFjaC1PYmplY3QgeyAkXy5WZXJzaW9uKyd8JyskXy5Eb3dubG9hZFVybCsnfCcrJF8uQXJjaGl2ZVNIQTI1NisnfCcrJF8uSW5zdGFsbGVyUmVsYXRpdmVQYXRoKyd8JyskXy5JbnN0YWxsZXJQYXJhbWV0ZXJzLlRvTG93ZXJJbnZhcmlhbnQoKSB9IHwgU2VsZWN0LU9iamVjdCAtVW5pcXVlKQ0KICAgIGlmICgkaWRlbnRpdGllcy5Db3VudCAtbmUgMSkgeyB0aHJvdyAnQVNSb2NrIDogcGx1c2lldXJzIGluc3RhbGxhdGV1cnMgb2ZmaWNpZWxzIGluY29oZXJlbnRzIHBvdXIgbGEgZGVybmllcmUgdmVyc2lvbiA7IHNlbGVjdGlvbiBhbWJpZ3VlLicgfQ0KICAgIHJldHVybiAkcmVzb2x2ZWRbMF0NCn0NCg==' }
    @{ Path = 'vendor-utility/VendorPackage.Gigabyte.ps1'; Sha256 = '34D4C5B541E3338D5463EEF6B12C7B7198C6B001B77D023A1D5DF9D09375F8DD'; Base64 = 'I3JlcXVpcmVzIC1WZXJzaW9uIDUuMQ0KIyBTdGF0aWMgZXh0cmFjdGlvbiBvbmx5LiBObyB2ZW5kb3Igc2V0dXAgaXMgdXNlZCBhcyBhIGRlY29tcHJlc3NvciBvciBleGVjdXRlZC4NCmZ1bmN0aW9uIFRlc3QtVnV0QXJjaGl2ZVRvb2wgew0KICAgIHBhcmFtKFtzdHJpbmddJFBhdGgpDQogICAgJGV4cGVjdGVkPUB7DQogICAgICAgICc3enIuZXhlJz0nMjU2RkVDQThFMjc0RTVEQTY1NUUyQTI4NEZBQkFGRDlGNTU0MzY1RUIxNjQ4NjIwODlEQUNENEU4Mjc2RDI4MicNCiAgICAgICAgJzd6LmV4ZSc9Jzk1RkZGMTlCNzNFRkY3N0M4N0MwRDdCRDMyODIyRTQzRkI5MEREMjkzMjQ1OUY5NjJFQjUzMkQ4REZCNkJBNTMnDQogICAgfQ0KICAgICRuYW1lPVtJTy5QYXRoXTo6R2V0RmlsZU5hbWUoJFBhdGgpDQogICAgaWYgKC1ub3QgJGV4cGVjdGVkLkNvbnRhaW5zS2V5KCRuYW1lKSAtb3IgKEdldC1GaWxlSGFzaCAtTGl0ZXJhbFBhdGggJFBhdGggLUFsZ29yaXRobSBTSEEyNTYpLkhhc2ggLW5lICRleHBlY3RlZFskbmFtZV0pIHsNCiAgICAgICAgdGhyb3cgJ091dGlsIGRlIGRlY29tcHJlc3Npb24gYWJzZW50IG91IGVtcHJlaW50ZSBub24gYXBwcm91dmVlIDsgYXVjdW4gZXhlY3V0YWJsZSBjb25zdHJ1Y3RldXIgYXV0b3Jpc2UgY29tbWUgb3V0aWwuJw0KICAgIH0NCiAgICBpZiAoJG5hbWUgLWVxICc3ei5leGUnKSB7DQogICAgICAgICRkbGw9Sm9pbi1QYXRoIChTcGxpdC1QYXRoIC1QYXJlbnQgJFBhdGgpICc3ei5kbGwnDQogICAgICAgIGlmICgoR2V0LUZpbGVIYXNoIC1MaXRlcmFsUGF0aCAkZGxsIC1BbGdvcml0aG0gU0hBMjU2KS5IYXNoIC1uZSAnODk5Q0Q3M0Q3RkM2MEUxQzFDMzVDN0RFMEY1QkVEM0RDNjlCRkUyQ0VDQkQ0ODAxNEQ4NjhBMzQ3OTcwQTBCMScpIHsgdGhyb3cgJ0JpYmxpb3RoZXF1ZSBkZSBkZWNvbXByZXNzaW9uIG5vbiBjb25mb3JtZS4nIH0NCiAgICB9DQp9DQoNCmZ1bmN0aW9uIEludm9rZS1WdXRBcmNoaXZlVG9vbCB7DQogICAgcGFyYW0oW3N0cmluZ10kUGF0aCxbc3RyaW5nW11dJEFyZ3VtZW50cykNCiAgICBUZXN0LVZ1dEFyY2hpdmVUb29sICRQYXRoDQogICAgJHA9TmV3LU9iamVjdCBEaWFnbm9zdGljcy5Qcm9jZXNzDQogICAgJHAuU3RhcnRJbmZvLkZpbGVOYW1lPSRQYXRoDQogICAgJHAuU3RhcnRJbmZvLkFyZ3VtZW50cz0oQCgkQXJndW1lbnRzIHwgRm9yRWFjaC1PYmplY3QgeyAnIicrJF8uUmVwbGFjZSgnIicsJ1wiJykrJyInIH0pIC1qb2luICcgJykNCiAgICAkcC5TdGFydEluZm8uVXNlU2hlbGxFeGVjdXRlPSRmYWxzZTsgJHAuU3RhcnRJbmZvLkNyZWF0ZU5vV2luZG93PSR0cnVlDQogICAgJHAuU3RhcnRJbmZvLlJlZGlyZWN0U3RhbmRhcmRPdXRwdXQ9JHRydWU7ICRwLlN0YXJ0SW5mby5SZWRpcmVjdFN0YW5kYXJkRXJyb3I9JHRydWUNCiAgICB0cnkgew0KICAgICAgICBbdm9pZF0kcC5TdGFydCgpDQogICAgICAgICRzdGRvdXQ9JHAuU3RhbmRhcmRPdXRwdXQuUmVhZFRvRW5kQXN5bmMoKTsgJHN0ZGVycj0kcC5TdGFuZGFyZEVycm9yLlJlYWRUb0VuZEFzeW5jKCkNCiAgICAgICAgaWYgKC1ub3QgJHAuV2FpdEZvckV4aXQoMTIwMDAwKSkgeyAkcC5LaWxsKCk7IFt2b2lkXSRwLldhaXRGb3JFeGl0KDUwMDApOyB0aHJvdyAnRGVsYWkgZGUgZGVjb21wcmVzc2lvbiBzdGF0aXF1ZSBkZXBhc3NlLicgfQ0KICAgICAgICBpZiAoLW5vdCAkc3Rkb3V0LldhaXQoNTAwMCkgLW9yIC1ub3QgJHN0ZGVyci5XYWl0KDUwMDApKSB7IHRocm93ICdGbHV4IGRlIGRlY29tcHJlc3Npb24gbm9uIHRlcm1pbmVzLicgfQ0KICAgICAgICAkdGV4dD0kc3Rkb3V0LkdldEF3YWl0ZXIoKS5HZXRSZXN1bHQoKSskc3RkZXJyLkdldEF3YWl0ZXIoKS5HZXRSZXN1bHQoKQ0KICAgICAgICBpZiAoJHAuRXhpdENvZGUgLW5lIDApIHsgdGhyb3cgKCdEZWNvbXByZXNzaW9uIHN0YXRpcXVlIDogY29kZSAnKyRwLkV4aXRDb2RlKycuICcrJHRleHQuU3Vic3RyaW5nKDAsW01hdGhdOjpNaW4oNDAwLCR0ZXh0Lkxlbmd0aCkpKSB9DQogICAgICAgIGlmICgkdGV4dC5MZW5ndGggLWd0IDEwNDg1NzYpIHsgdGhyb3cgJ0xpc3RlIGFyY2hpdmUgdHJvcCB2b2x1bWluZXVzZS4nIH0NCiAgICAgICAgcmV0dXJuICR0ZXh0DQogICAgfSBmaW5hbGx5IHsgJHAuRGlzcG9zZSgpIH0NCn0NCg0KZnVuY3Rpb24gR2V0LVZ1dFBvcnRhYmxlU2V2ZW5aaXAgew0KICAgIHBhcmFtKFtzdHJpbmddJERpcmVjdG9yeSkNCiAgICBbdm9pZF0oTmV3LUl0ZW0gLUl0ZW1UeXBlIERpcmVjdG9yeSAtUGF0aCAkRGlyZWN0b3J5IC1Gb3JjZSkNCiAgICAjIE9mZmljaWFsIGlwN3ogcmVsZWFzZSAyNi4wNDsgaGFzaGVzIG1hdGNoIHRoZSBwdWJsaXNoZXIncyBHaXRIdWIgYXNzZXQgZGlnZXN0cy4NCiAgICAkYXNzZXRzPUAoDQogICAgICAgIEB7TmFtZT0nN3pyLmV4ZSc7U0hBMjU2PScyNTZGRUNBOEUyNzRFNURBNjU1RTJBMjg0RkFCQUZEOUY1NTQzNjVFQjE2NDg2MjA4OURBQ0Q0RTgyNzZEMjgyJ30sDQogICAgICAgIEB7TmFtZT0nN3oyNjA0LXg2NC5leGUnO1NIQTI1Nj0nRDU0QkY4MDVGOUYzNzA0RDFFOERCMkZBMzQ5OEFFN0VGMkRGMDMxMkI0MEI1NThFN0M3MUM3MzQ0MzBBNjY1RCd9DQogICAgKQ0KICAgIGZvcmVhY2ggKCRhc3NldCBpbiAkYXNzZXRzKSB7DQogICAgICAgICRwYXRoPUpvaW4tUGF0aCAkRGlyZWN0b3J5ICRhc3NldC5OYW1lDQogICAgICAgIFt2b2lkXShJbnZva2UtTWJ4SHR0cCAtVXJsICgnaHR0cHM6Ly9naXRodWIuY29tL2lwN3ovN3ppcC9yZWxlYXNlcy9kb3dubG9hZC8yNi4wNC8nKyRhc3NldC5OYW1lKSAtSG9zdHMgQCgnZ2l0aHViLmNvbScsJ2dpdGh1YnVzZXJjb250ZW50LmNvbScpIC1UaW1lb3V0U2Vjb25kcyAxMjAgLU1heEJ5dGVzIDE2Nzc3MjE2IC1PdXRGaWxlICRwYXRoKQ0KICAgICAgICBpZiAoKEdldC1GaWxlSGFzaCAtTGl0ZXJhbFBhdGggJHBhdGggLUFsZ29yaXRobSBTSEEyNTYpLkhhc2ggLW5lICRhc3NldC5TSEEyNTYpIHsgdGhyb3cgJ0VtcHJlaW50ZSBkdSBwYXF1ZXQgb2ZmaWNpZWwgZGUgZGVjb21wcmVzc2lvbiBpbmNvcnJlY3RlLicgfQ0KICAgIH0NCiAgICAkcG9ydGFibGU9Sm9pbi1QYXRoICREaXJlY3RvcnkgJ3BvcnRhYmxlJw0KICAgIFt2b2lkXShOZXctSXRlbSAtSXRlbVR5cGUgRGlyZWN0b3J5IC1QYXRoICRwb3J0YWJsZSkNCiAgICAjIFRoZSA3LVppcCBzZXR1cCBpcyByZWFkIGFzIGEgN3ogYXJjaGl2ZSwgbmV2ZXIgbGF1bmNoZWQgb3IgaW5zdGFsbGVkLg0KICAgIFt2b2lkXShJbnZva2UtVnV0QXJjaGl2ZVRvb2wgLVBhdGggKEpvaW4tUGF0aCAkRGlyZWN0b3J5ICc3enIuZXhlJykgLUFyZ3VtZW50cyBAKCdlJywnLXknLCgnLW8nKyRwb3J0YWJsZSksKEpvaW4tUGF0aCAkRGlyZWN0b3J5ICc3ejI2MDQteDY0LmV4ZScpLCc3ei5leGUnLCc3ei5kbGwnKSkNCiAgICAkdG9vbD1Kb2luLVBhdGggJHBvcnRhYmxlICc3ei5leGUnDQogICAgVGVzdC1WdXRBcmNoaXZlVG9vbCAkdG9vbA0KICAgIHJldHVybiAkdG9vbA0KfQ0KDQpmdW5jdGlvbiBSZXNvbHZlLVZ1dEdjY0NvcmVFbnRyeSB7DQogICAgcGFyYW0oW3N0cmluZ10kTGlzdGluZykNCiAgICAkZW50cmllcz1AKGZvcmVhY2ggKCRsaW5lIGluICRMaXN0aW5nIC1zcGxpdCAnXHI/XG4nKSB7DQogICAgICAgIGlmICgkbGluZSAtbm90bWF0Y2ggJ1xBUGF0aCA9ICguKylceicpIHsgY29udGludWUgfQ0KICAgICAgICAkcGF0aD0kTWF0Y2hlc1sxXTsgJGxlYWY9KCRwYXRoLlJlcGxhY2UoJ1wnLCcvJykgLXNwbGl0ICcvJylbLTFdDQogICAgICAgICRtYXRjaD1bcmVnZXhdOjpNYXRjaCgkbGVhZiwnXEFHSUdBQllURSBDb250cm9sIENlbnRlcl8oWzAtOV0rXC5bMC05XStcLlswLTldK1wuWzAtOV0rKVwuZXhlXHonKQ0KICAgICAgICBpZiAoLW5vdCAkbWF0Y2guU3VjY2VzcykgeyBjb250aW51ZSB9DQogICAgICAgIGlmICgkcGF0aCAtbWF0Y2ggJyheWy9cXEAtXXwoXnxbL1xcXSlcLlwuKFsvXFxdfCQpfFs6Iio/XHgwMC1ceDFmXSknKSB7IHRocm93ICdDaGVtaW4gZHUgY29ldXIgR0lHQUJZVEUgZGFuZ2VyZXV4IHJlZnVzZS4nIH0NCiAgICAgICAgJHZlcnNpb249Q29udmVydFRvLU1ieFZlcnNpb24gJG1hdGNoLkdyb3Vwc1sxXS5WYWx1ZQ0KICAgICAgICBpZiAoLW5vdCAkdmVyc2lvbikgeyB0aHJvdyAnVmVyc2lvbiBkdSBjb2V1ciBHSUdBQllURSBpbnZhbGlkZS4nIH0NCiAgICAgICAgW3BzY3VzdG9tb2JqZWN0XUB7UGF0aD0kcGF0aDtGaWxlTmFtZT0kbGVhZjtWZXJzaW9uPSRtYXRjaC5Hcm91cHNbMV0uVmFsdWV9DQogICAgfSkNCiAgICBpZiAoJGVudHJpZXMuQ291bnQgLW5lIDEpIHsgdGhyb3cgJ0NvZXVyIEdJR0FCWVRFIGFic2VudCBvdSBhbWJpZ3UgOyBhdWN1biByYWNjb3VyY2kgdmVycyBsZSBidW5kbGUgY29tcGxldC4nIH0NCiAgICByZXR1cm4gJGVudHJpZXNbMF0NCn0NCg0KZnVuY3Rpb24gR2V0LVZ1dEdpZ2FieXRlUGFja2FnZSB7DQogICAgcGFyYW0oW3N0cmluZ10kRGlyZWN0b3J5KQ0KICAgICRkaXNjb3Zlcnk9UmVzb2x2ZS1WdXRHaWdhYnl0ZUNvcmVEb3dubG9hZA0KICAgICR2ZW5kb3I9QChHZXQtTWJ4VG9vbERlZmluaXRpb25zIHwgV2hlcmUtT2JqZWN0IFZlbmRvciAtZXEgR0lHQUJZVEUpWzBdDQogICAgJHRvb2w9W3BzY3VzdG9tb2JqZWN0XUB7VmVuZG9yPSdHSUdBQllURSc7VG9vbD0nR0lHQUJZVEUgQ29udHJvbCBDZW50ZXInO0hvc3RzPUAoJ21iLmRvd25sb2FkLmdpZ2FieXRlLmNvbScpO1NpZ25lcnM9JHZlbmRvci5TaWduZXJzO0ZpbGVQYXR0ZXJuPSgnXEEnK1tyZWdleF06OkVzY2FwZSgkZGlzY292ZXJ5LkZpbGVOYW1lKSsnXHonKX0NCiAgICAkYXVkaXQ9SW52b2tlLU1ieFV0aWxpdHlBdWRpdCAtVG9vbCAkdG9vbCAtRG93bmxvYWRVcmwgJGRpc2NvdmVyeS5Eb3dubG9hZFVybCAtT3V0cHV0RGlyZWN0b3J5ICREaXJlY3RvcnkNCiAgICBpZiAoJGF1ZGl0LlBheWxvYWRzLkNvdW50IC1uZSAxIC1vciAkYXVkaXQuQnl0ZXMgLW5lICRhdWRpdC5FeHBlY3RlZEJ5dGVzIC1vciAkYXVkaXQuQnl0ZXMgLW5lICRkaXNjb3ZlcnkuRXhwZWN0ZWRCeXRlcykgeyB0aHJvdyAnVGVsZWNoYXJnZW1lbnQgR0NDIGluY29tcGxldCBvdSB0YWlsbGUgZGlmZmVyZW50ZSBkdSBtYW5pZmVzdGUgb2ZmaWNpZWwuJyB9DQogICAgaWYgKChDb252ZXJ0VG8tTWJ4VmVyc2lvbiAkYXVkaXQuUGF5bG9hZHNbMF0uRmlsZVZlcnNpb24uVHJpbSgpKSAtbmUgKENvbnZlcnRUby1NYnhWZXJzaW9uICRkaXNjb3ZlcnkuVmVyc2lvbikpIHsgdGhyb3cgJ1ZlcnNpb24gZHUgcHJvZ3JhbW1lIEdDQyBkaWZmZXJlbnRlIGR1IG1hbmlmZXN0ZSBvZmZpY2llbCA7IGF1Y3VuIGFuY2llbiBmaWNoaWVyIGFjY2VwdGUuJyB9DQogICAgJGZpbGVzPUAoR2V0LUNoaWxkSXRlbSAtTGl0ZXJhbFBhdGggJERpcmVjdG9yeSAtRGlyZWN0b3J5IHwgV2hlcmUtT2JqZWN0IE5hbWUgLW1hdGNoICdcQVswLTlhLWZdezMyfVx6JyB8IEZvckVhY2gtT2JqZWN0IHsNCiAgICAgICAgJHA9Sm9pbi1QYXRoICRfLkZ1bGxOYW1lICRkaXNjb3ZlcnkuRmlsZU5hbWUNCiAgICAgICAgaWYgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJHAgLVBhdGhUeXBlIExlYWYpIHsgJHAgfQ0KICAgIH0pDQogICAgaWYgKCRmaWxlcy5Db3VudCAtbmUgMSkgeyB0aHJvdyAnSW5zdGFsbGF0ZXVyIEdDQyBhYnNlbnQgb3UgYW1iaWd1IGFwcmVzIHRlbGVjaGFyZ2VtZW50LicgfQ0KICAgICRzaWduYXR1cmU9VGVzdC1NYnhTaWduZWRQYXlsb2FkIC1QYXRoICRmaWxlc1swXSAtU2lnbmVycyAkdmVuZG9yLlNpZ25lcnMNCiAgICBpZiAoJHNpZ25hdHVyZS5TSEEyNTYgLW5lICRhdWRpdC5TSEEyNTYgLW9yICRzaWduYXR1cmUuU0hBMjU2IC1uZSAkYXVkaXQuUGF5bG9hZHNbMF0uU0hBMjU2IC1vciAkc2lnbmF0dXJlLkJ5dGVzIC1uZSAkZGlzY292ZXJ5LkV4cGVjdGVkQnl0ZXMgLW9yIChDb252ZXJ0VG8tTWJ4VmVyc2lvbiAkc2lnbmF0dXJlLkZpbGVWZXJzaW9uLlRyaW0oKSkgLW5lIChDb252ZXJ0VG8tTWJ4VmVyc2lvbiAkZGlzY292ZXJ5LlZlcnNpb24pKSB7IHRocm93ICdJbnN0YWxsYXRldXIgR0NDIG1vZGlmaWUgYXByZXMgdmVyaWZpY2F0aW9uLicgfQ0KICAgICMgVGhlIG9mZmljaWFsIHVwZGF0ZSBkb3dubG9hZCBpcyBpdHNlbGYgYSBzbWFsbCBOU0lTIGJ1bmRsZSBjb250YWluaW5nDQogICAgIyBNQiBVcGRhdGUgYW5kIFJHQiBTeW5jLiBOZXZlciBvZmZlciB0aGF0IHdyYXBwZXIgYXMgdGhlIGNvcmUgaW5zdGFsbGVyLg0KICAgIHJldHVybiBFeHBhbmQtVnV0R2lnYWJ5dGVDb3JlIC1PdXRlclBhdGggJGZpbGVzWzBdIC1Ub29sICR2ZW5kb3IgLURpcmVjdG9yeSAkRGlyZWN0b3J5IC1BdWRpdCAkYXVkaXQgLURpc2NvdmVyeSAkZGlzY292ZXJ5IC1FeHBlY3RlZFZlcnNpb24gJGRpc2NvdmVyeS5WZXJzaW9uDQp9DQoNCiMgSGlzdG9yaWNhbCBidW5kbGUgZXh0cmFjdGlvbiBpcyByZXRhaW5lZCBmb3IgZXhwbGljaXQgcmVjb3JkZWQtc291cmNlIGF1ZGl0cy4NCiMgVGhlIHVzZXItZmFjaW5nIHBhdGggYWJvdmUgbmV2ZXIgZmFsbHMgYmFjayB0byB0aGlzIGJ1bmRsZSBvciBhbiBvbGQgc25hcHNob3QuDQpmdW5jdGlvbiBHZXQtVnV0R2lnYWJ5dGVCdW5kbGVQYWNrYWdlIHsNCiAgICBwYXJhbShbc3RyaW5nXSREaXJlY3RvcnkpDQogICAgW3ZvaWRdKE5ldy1JdGVtIC1JdGVtVHlwZSBEaXJlY3RvcnkgLVBhdGggJERpcmVjdG9yeSAtRm9yY2UpDQogICAgJGRpc2NvdmVyeT1SZXNvbHZlLVZ1dEdpZ2FieXRlRG93bmxvYWQNCiAgICAkdG9vbD1AKEdldC1NYnhUb29sRGVmaW5pdGlvbnMgfCBXaGVyZS1PYmplY3QgVmVuZG9yIC1lcSBHSUdBQllURSlbMF0NCiAgICAkYXVkaXQ9SW52b2tlLU1ieFV0aWxpdHlBdWRpdCAtVG9vbCAkdG9vbCAtRG93bmxvYWRVcmwgJGRpc2NvdmVyeS5Eb3dubG9hZFVybCAtT3V0cHV0RGlyZWN0b3J5ICREaXJlY3RvcnkNCiAgICBpZiAoJGF1ZGl0LlBheWxvYWRzLkNvdW50IC1uZSAxIC1vciAkYXVkaXQuQnl0ZXMgLW5lICRhdWRpdC5FeHBlY3RlZEJ5dGVzIC1vciAoQ29udmVydFRvLU1ieFZlcnNpb24gJGF1ZGl0LlBheWxvYWRzWzBdLkZpbGVWZXJzaW9uLlRyaW0oKSkgLW5lIChDb252ZXJ0VG8tTWJ4VmVyc2lvbiAkZGlzY292ZXJ5LkJ1bmRsZVZlcnNpb24pKSB7DQogICAgICAgIHRocm93ICdCdW5kbGUgR0lHQUJZVEUgaW5jb21wbGV0LCBhbWJpZ3Ugb3UgZGlmZmVyZW50IGRlIGxhIHZlcnNpb24gYW5ub25jZWUuJw0KICAgIH0NCiAgICAkb3V0ZXI9QChHZXQtQ2hpbGRJdGVtIC1MaXRlcmFsUGF0aCAkRGlyZWN0b3J5IC1EaXJlY3RvcnkgfCBXaGVyZS1PYmplY3QgTmFtZSAtbWF0Y2ggJ1xBWzAtOWEtZl17MzJ9XHonIHwgRm9yRWFjaC1PYmplY3Qgew0KICAgICAgICAkcD1Kb2luLVBhdGggJF8uRnVsbE5hbWUgJ3BheWxvYWQtMC5leGUnOyBpZiAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkcCAtUGF0aFR5cGUgTGVhZikgeyAkcCB9DQogICAgfSkNCiAgICBpZiAoJG91dGVyLkNvdW50IC1uZSAxKSB7IHRocm93ICdFeGVjdXRhYmxlIGV4dGVybmUgR0lHQUJZVEUgYWJzZW50IG91IGFtYmlndS4nIH0NCiAgICAkb3V0ZXJTaWduYXR1cmU9VGVzdC1NYnhTaWduZWRQYXlsb2FkIC1QYXRoICRvdXRlclswXSAtU2lnbmVycyAkdG9vbC5TaWduZXJzDQogICAgaWYgKCRvdXRlclNpZ25hdHVyZS5TSEEyNTYgLW5lICRhdWRpdC5QYXlsb2Fkc1swXS5TSEEyNTYpIHsgdGhyb3cgJ0J1bmRsZSBHSUdBQllURSBtb2RpZmllIGFwcmVzIHZlcmlmaWNhdGlvbi4nIH0NCiAgICByZXR1cm4gRXhwYW5kLVZ1dEdpZ2FieXRlQ29yZSAtT3V0ZXJQYXRoICRvdXRlclswXSAtVG9vbCAkdG9vbCAtRGlyZWN0b3J5ICREaXJlY3RvcnkgLUF1ZGl0ICRhdWRpdCAtRGlzY292ZXJ5ICRkaXNjb3ZlcnkNCn0NCg0KZnVuY3Rpb24gR2V0LVZ1dEdjY0luc3RhbGxlclByb2R1Y3ROYW1lIHsNCiAgICBwYXJhbShbc3RyaW5nXSRQYXRoKQ0KICAgIHJldHVybiBbRGlhZ25vc3RpY3MuRmlsZVZlcnNpb25JbmZvXTo6R2V0VmVyc2lvbkluZm8oJFBhdGgpLlByb2R1Y3ROYW1lDQp9DQoNCmZ1bmN0aW9uIEV4cGFuZC1WdXRHaWdhYnl0ZUNvcmUgew0KICAgIHBhcmFtKFtzdHJpbmddJE91dGVyUGF0aCwkVG9vbCxbc3RyaW5nXSREaXJlY3RvcnksJEF1ZGl0LCREaXNjb3ZlcnksW3N0cmluZ10kRXhwZWN0ZWRWZXJzaW9uKQ0KICAgICRzZXZlblppcD1HZXQtVnV0UG9ydGFibGVTZXZlblppcCAtRGlyZWN0b3J5IChKb2luLVBhdGggJERpcmVjdG9yeSAnYXJjaGl2ZS10b29sJykNCiAgICAjIC1iYSBzdXBwcmVzc2VzIHRoZSBhcmNoaXZlIGhlYWRlciBpdHNlbGY6IGl0cyBhYnNvbHV0ZSBQYXRoIGNhbiBoYXZlIHRoZQ0KICAgICMgc2FtZSBmaWxlbmFtZSBhcyB0aGUgaW50ZXJuYWwgY29yZSBhbmQgbXVzdCBub3QgYmUgcGFyc2VkIGFzIGFuIGVudHJ5Lg0KICAgICRlbnRyeT1SZXNvbHZlLVZ1dEdjY0NvcmVFbnRyeSAtTGlzdGluZyAoSW52b2tlLVZ1dEFyY2hpdmVUb29sIC1QYXRoICRzZXZlblppcCAtQXJndW1lbnRzIEAoJ2wnLCctc2x0JywnLWJhJywkT3V0ZXJQYXRoKSkNCiAgICBpZiAoJEV4cGVjdGVkVmVyc2lvbiAtYW5kIChDb252ZXJ0VG8tTWJ4VmVyc2lvbiAkZW50cnkuVmVyc2lvbikgLW5lIChDb252ZXJ0VG8tTWJ4VmVyc2lvbiAkRXhwZWN0ZWRWZXJzaW9uKSkgeyB0aHJvdyAnVmVyc2lvbiBkdSBjb2V1ciBHQ0MgZGlmZmVyZW50ZSBkdSBtYW5pZmVzdGUgb2ZmaWNpZWwgOyBhdWN1biBhbmNpZW4gZmljaGllciBhY2NlcHRlLicgfQ0KICAgICRjb3JlRGlyZWN0b3J5PUpvaW4tUGF0aCAkRGlyZWN0b3J5ICdjb3JlLW9ubHknDQogICAgW3ZvaWRdKE5ldy1JdGVtIC1JdGVtVHlwZSBEaXJlY3RvcnkgLVBhdGggJGNvcmVEaXJlY3RvcnkpDQogICAgW3ZvaWRdKEludm9rZS1WdXRBcmNoaXZlVG9vbCAtUGF0aCAkc2V2ZW5aaXAgLUFyZ3VtZW50cyBAKCdlJywnLXknLCgnLW8nKyRjb3JlRGlyZWN0b3J5KSwkT3V0ZXJQYXRoLCRlbnRyeS5QYXRoKSkNCiAgICAkZmlsZXM9QChHZXQtQ2hpbGRJdGVtIC1MaXRlcmFsUGF0aCAkY29yZURpcmVjdG9yeSAtRmlsZSkNCiAgICBpZiAoJGZpbGVzLkNvdW50IC1uZSAxIC1vciAkZmlsZXNbMF0uTmFtZSAtY25lICRlbnRyeS5GaWxlTmFtZSkgeyB0aHJvdyAnRXh0cmFjdGlvbiBHSUdBQllURSBub24gbGltaXRlZSBhdSBzZXVsIGNvZXVyIGF0dGVuZHUuJyB9DQogICAgJHNpZ25hdHVyZT1UZXN0LU1ieFNpZ25lZFBheWxvYWQgLVBhdGggJGZpbGVzWzBdLkZ1bGxOYW1lIC1TaWduZXJzICR0b29sLlNpZ25lcnMNCiAgICBpZiAoKENvbnZlcnRUby1NYnhWZXJzaW9uICRzaWduYXR1cmUuRmlsZVZlcnNpb24uVHJpbSgpKSAtbmUgKENvbnZlcnRUby1NYnhWZXJzaW9uICRlbnRyeS5WZXJzaW9uKSkgeyB0aHJvdyAnVmVyc2lvbiBkdSBjb2V1ciBHSUdBQllURSBkaWZmZXJlbnRlIGR1IG5vbSBvZmZpY2llbC4nIH0NCiAgICBpZiAoKEdldC1WdXRHY2NJbnN0YWxsZXJQcm9kdWN0TmFtZSAtUGF0aCAkZmlsZXNbMF0uRnVsbE5hbWUpIC1jbmUgJ0dJR0FCWVRFIENvbnRyb2wgQ2VudGVyJykgeyB0aHJvdyAnSWRlbnRpdGUgcHJvZHVpdCBHQ0MgaW5jb3JyZWN0ZSA6IGxhbmNldXIgTGl2ZXVwZGF0ZSBvdSBidW5kbGUgcmVmdXNlLicgfQ0KICAgIHJldHVybiBbcHNjdXN0b21vYmplY3RdQHsNCiAgICAgICAgUGF0aD0kZmlsZXNbMF0uRnVsbE5hbWU7U0hBMjU2PSRzaWduYXR1cmUuU0hBMjU2O1ZlcnNpb249JHNpZ25hdHVyZS5GaWxlVmVyc2lvbi5UcmltKCk7S2luZD0nZ2lnYWJ5dGVfY29yZScNCiAgICAgICAgQXVkaXQ9JGF1ZGl0O0Rpc2NvdmVyeT0kZGlzY292ZXJ5O0NvcmVGaWxlTmFtZT0kZW50cnkuRmlsZU5hbWU7Q29yZVNpZ25hdHVyZT0kc2lnbmF0dXJlO1ZlbmRvckluc3RhbGxlckV4ZWN1dGVkPSRmYWxzZQ0KICAgIH0NCn0NCg==' }
)

function Initialize-LDLCVendorUtilityModule {
    if (-not $script:LDLCVendorUtilityPayloads.Count) { throw 'Modules constructeurs absents de cette compilation.' }
    $identity=($script:LDLCVendorUtilityPayloads | ForEach-Object { $_.Sha256 }) -join ''
    $sha=[Security.Cryptography.SHA256]::Create()
    try { $id=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($identity)))).Replace('-','') } finally { $sha.Dispose() }
    $root=Join-Path $script:RuntimeRoot ('VendorUtility/'+$id)
    foreach ($entry in $script:LDLCVendorUtilityPayloads) {
        if ($entry.Path -notmatch '\A(?:motherboard|vendor-utility)/[A-Za-z0-9.-]+\.psm?1\z') { throw 'Chemin du module constructeur embarque invalide.' }
        $path=Join-Path $root $entry.Path
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            [void](New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force)
            $bytes=[Convert]::FromBase64String($entry.Base64)
            $sha=[Security.Cryptography.SHA256]::Create()
            try { $hash=([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','') } finally { $sha.Dispose() }
            if ($hash -cne $entry.Sha256) { throw 'Empreinte du module constructeur embarque incorrecte.' }
            [IO.File]::WriteAllBytes($path,$bytes)
        }
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -cne $entry.Sha256) { throw 'Module constructeur local modifie ; chargement refuse.' }
    }
    return Import-Module (Join-Path $root 'vendor-utility/VendorUtility.psm1') -Force -PassThru -ErrorAction Stop
}

function Invoke-LDLCVendorUtility {
    param([int]$ProgressPercent=60)
    Stop-IfRequested
    Write-ProgressFile $ProgressPercent 'Logiciel de carte mere : detection et preparation du raccourci...'
    try {
        $module=Initialize-LDLCVendorUtilityModule
        $result=& $module { Invoke-VendorUtility }
        Stop-IfRequested
        $report=Join-Path $script:RuntimeRoot 'LDLC_VENDOR_UTILITY_RESULT.json'
        $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $report -Encoding UTF8
        if ($result.Status -eq 'already_installed' -and $result.ApplicationVerified -and $result.Shortcut) {
            Write-Ok ($result.Tool+' : application presente, raccourci Bureau verifie.')
        } elseif ($result.Status -eq 'manual_required' -and $result.InstallerShortcut) {
            Write-Ok ($result.Tool+' : installateur verifie, raccourci sur le Bureau. Installation manuelle par le technicien.')
        } elseif ($result.Status -eq 'manual_required' -and $result.PSObject.Properties['SupportShortcut'] -and $result.SupportShortcut) {
            Write-Warn ($result.Tool+' : telechargement manuel requis. '+$result.Reason)
        } elseif ($result.Status -eq 'manual_required' -and -not $result.Tool) {
            Write-Step ('Logiciel de carte mere non applicable : '+$result.Reason)
        } else {
            Write-Warn ('Logiciel de carte mere non prepare : '+$result.Reason)
        }
        return $result
    } catch {
        if (Test-LDLCStopRequestError $_) { throw }
        Write-Warn ('Logiciel de carte mere : '+$_.Exception.Message)
        return [pscustomobject]@{Status='failed';Reason=$_.Exception.Message;Installed=$false;InstallerShortcut=''}
    }
}
# region Module: 90.Workflow.ps1
# Main preparation workflow.

function Invoke-LDLCRestorePointCreation {
    param([int]$ProgressPercent = 1)

    Stop-IfRequested
    Write-ProgressFile $ProgressPercent "Activation et creation du point de restauration..."
    Write-Step "Preparation du point de restauration systeme..."

    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            Write-Warn "Point de restauration impossible : droits administrateur requis."
            Write-ProgressFile $ProgressPercent "Point de restauration ignore : droits administrateur requis."
            return $false
        }

        $systemDrive = [string]$env:SystemDrive
        if ([string]::IsNullOrWhiteSpace($systemDrive)) {
            $systemDrive = 'C:'
        }

        if (-not $systemDrive.EndsWith('\')) {
            $systemDrive = "$systemDrive\"
        }

        Write-Step "Lecteur systeme pour la restauration : $systemDrive"

        $latestRestorePoint = $null
        try {
            $restorePoints = @(Get-ComputerRestorePoint -ErrorAction Stop)
            foreach ($restorePoint in $restorePoints) {
                $createdAt = $null
                try {
                    $rawCreationTime = $restorePoint.CreationTime
                    if ($rawCreationTime -is [datetime]) {
                        $createdAt = $rawCreationTime
                    }
                    elseif (-not [string]::IsNullOrWhiteSpace([string]$rawCreationTime)) {
                        $createdAt = [System.Management.ManagementDateTimeConverter]::ToDateTime([string]$rawCreationTime)
                    }
                }
                catch {}

                if ($createdAt) {
                    $candidate = [pscustomobject]@{
                        Description = [string]$restorePoint.Description
                        CreatedAt   = $createdAt
                    }

                    if (-not $latestRestorePoint -or $candidate.CreatedAt -gt $latestRestorePoint.CreatedAt) {
                        $latestRestorePoint = $candidate
                    }
                }
            }
        }
        catch {
            Write-Step "Aucun point de restauration existant lisible avant creation : $($_.Exception.Message)"
        }

        if ($latestRestorePoint -and ((Get-Date) - $latestRestorePoint.CreatedAt).TotalHours -lt 24) {
            Write-Ok ("Point de restauration recent deja present ({0:yyyy-MM-dd HH:mm}, {1}). Creation non necessaire." -f $latestRestorePoint.CreatedAt, $latestRestorePoint.Description)
            Write-ProgressFile $ProgressPercent "Point de restauration recent deja present."
            return $true
        }

        Write-Step "Activation de la restauration systeme sur $systemDrive..."
        Enable-ComputerRestore -Drive $systemDrive -ErrorAction Stop

        Write-Step "Creation du point de restauration..."
        Checkpoint-Computer -Description "Avant Configuration Entreprise" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop

        Write-Ok "Point de restauration cree avec succes."
        Write-ProgressFile $ProgressPercent "Point de restauration cree."
        return $true
    }
    catch {
        if (Test-LDLCStopRequestError $_) { throw }
        $errorMessage = [string]$_.Exception.Message
        $hint = 'cause Windows non precisee'

        if ($errorMessage -match '(?i)1440|24\s*hour|24\s*heures|already.*restore point|deja.*point') {
            $hint = 'restriction Windows : un point de restauration recent existe deja'
        }
        elseif ($errorMessage -match '(?i)access.*denied|acces refuse|0x80070005') {
            $hint = 'droits administrateur ou strategie Windows insuffisants'
        }
        elseif ($errorMessage -match '(?i)disabled|desactive|0x81000203|system restore') {
            $hint = 'protection systeme desactivee ou bloquee par Windows'
        }
        elseif ($errorMessage -match '(?i)shadow|vss|volume') {
            $hint = 'service VSS / Volume Shadow Copy indisponible'
        }

        Write-Warn "Point de restauration non cree ($hint) : $errorMessage"
        Write-ProgressFile $ProgressPercent "Point de restauration non cree, preparation continue."
        return $false
    }
}

function Get-LDLCWindowsUpdateTimeoutSeconds {
    # Compatibilite : les anciens overrides n'imposent plus de delai.
    return 0
}

function Get-LDLCWindowsUpdateFinalWaitSeconds {
    # Compatibilite : les anciens overrides n'imposent plus de delai.
    return 0
}

function New-LDLCWindowsUpdateWorkflowResult {
    param(
        [bool]$Success = $false,
        [bool]$RebootRequired = $false,
        [int]$Count = 0,
        [bool]$Skipped = $false,
        [bool]$TimedOut = $false,
        [bool]$BackgroundFallbackStarted = $false,
        [int]$RemainingCount = 0,
        [bool]$UsoFallbackUsed = $false,
        [bool]$Completed = $false,
        [int]$CycleCount = 0,
        [int]$MaxCycles = 0,
        [int]$DownloadedCount = 0,
        [int]$DetectedCount = 0,
        [string]$LastError = '',
        [string[]]$StartedActions = @(),
        [string[]]$FailedActions = @(),
        [string[]]$ServicesRunning = @(),
        [string[]]$ServicesFailed = @()
    )

    return [pscustomobject]@{
        Success = $Success
        RebootRequired = $RebootRequired
        Count = $Count
        Skipped = $Skipped
        TimedOut = $TimedOut
        BackgroundFallbackStarted = $BackgroundFallbackStarted
        RemainingCount = $RemainingCount
        UsoFallbackUsed = $UsoFallbackUsed
        Completed = $Completed
        CycleCount = $CycleCount
        MaxCycles = $MaxCycles
        DownloadedCount = $DownloadedCount
        DetectedCount = $DetectedCount
        LastError = $LastError
        StartedActions = @($StartedActions)
        FailedActions = @($FailedActions)
        ServicesRunning = @($ServicesRunning)
        ServicesFailed = @($ServicesFailed)
    }
}

function Convert-LDLCWindowsUpdateWorkerPayload {
    param([Parameter(Mandatory = $true)]$Payload)

    return New-LDLCWindowsUpdateWorkflowResult `
        -Success ([bool]$Payload.Success) `
        -RebootRequired ([bool]$Payload.RebootRequired) `
        -Count ([int]$Payload.Count) `
        -Skipped ([bool]$Payload.Skipped) `
        -TimedOut ([bool]$Payload.TimedOut) `
        -BackgroundFallbackStarted ([bool]$Payload.BackgroundFallbackStarted) `
        -RemainingCount ([int]$Payload.RemainingCount) `
        -UsoFallbackUsed ([bool]$Payload.UsoFallbackUsed) `
        -Completed ([bool]$Payload.Completed) `
        -CycleCount ([int]$Payload.CycleCount) `
        -MaxCycles ([int]$Payload.MaxCycles) `
        -DownloadedCount ([int]$Payload.DownloadedCount) `
        -DetectedCount ([int]$Payload.DetectedCount) `
        -LastError ([string]$Payload.LastError) `
        -StartedActions @($Payload.StartedActions) `
        -FailedActions @($Payload.FailedActions) `
        -ServicesRunning @($Payload.ServicesRunning) `
        -ServicesFailed @($Payload.ServicesFailed)
}

function Read-LDLCWindowsUpdateWorkerProgress {
    param([string]$ProgressPath)

    if ([string]::IsNullOrWhiteSpace($ProgressPath) -or -not (Test-Path -LiteralPath $ProgressPath -PathType Leaf)) {
        return $null
    }

    try {
        $raw = Get-Content -LiteralPath $ProgressPath -Raw -Encoding UTF8 -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return $null
        }

        $parts = ([string]$raw).Trim() -split '\|', 2
        $percent = 94
        if ($parts.Count -gt 0) {
            try { $percent = [int]$parts[0] } catch {}
        }

        $message = if ($parts.Count -gt 1) { [string]$parts[1] } else { [string]$raw }
        return [pscustomobject]@{
            Percent = [math]::Max(90, [math]::Min(99, $percent))
            Message = $message
        }
    }
    catch {
        return $null
    }
}

function Start-LDLCWindowsUpdatesDuringPreparation {
    param(
        [int]$StartPercent = 5,
        [int]$EndPercent = 7
    )

    Stop-IfRequested

    try {
        $launch = Install-WindowsUpdates -StartPercent $StartPercent -EndPercent $EndPercent
        $started = ($null -ne $launch -and [bool]$launch.Success)
        $errorText = if ($started) { '' } elseif ($launch -and $launch.LastError) { [string]$launch.LastError } else { 'Declenchement Windows Update non confirme.' }
        return [pscustomobject]@{
            Started = $started
            ProcessId = 0
            ResultPath = ''
            ProgressPath = ''
            Error = $errorText
        }
    }
    catch {
        if (Test-LDLCStopRequestError $_) { throw }

        $message = "Lancement Windows Update en arriere-plan impossible : $($_.Exception.Message)"
        Write-Err $message
        Add-LDLCWindowsUpdateTelemetryEvent -Message $message -Severity error -Status 'erreur'
        Write-ProgressFile $EndPercent "Windows Update non lance, preparation continue."
        return [pscustomobject]@{
            Started = $false
            ProcessId = 0
            ResultPath = ''
            ProgressPath = ''
            Error = $message
        }
    }
}

function Wait-LDLCWindowsUpdateWorkerCompletion {
    param(
        $Worker,
        [int]$ProgressPercent = 94,
        [int]$TimeoutSeconds = (Get-LDLCWindowsUpdateFinalWaitSeconds)
    )

    # Adaptateur historique immediat : aucun resultat ou processus n'est consulte.
    $started = ($null -ne $Worker -and [bool]$Worker.Started)
    $errorText = if ($started) { '' } elseif ($Worker) { [string]$Worker.Error } else { 'Windows Update non demarre' }
    return New-LDLCWindowsUpdateWorkflowResult -Success $started -LastError $errorText
}

function Invoke-LDLCSecurityCleanupIsolated {
    param(
        [int]$StartPercent = 1,
        [int]$EndPercent = 3,
        [int]$TimeoutSeconds = 90,
        [ValidateSet('All', 'McAfee', 'Norton')]
        [string]$SecurityVendor = 'All'
    )

    Stop-IfRequested
    $workerScript = $script:LDLCEmbeddedWorkerScriptPath
    if ([string]::IsNullOrWhiteSpace($workerScript) -or -not (Test-Path -LiteralPath $workerScript -PathType Leaf)) {
        Write-Warn 'Worker de securite indisponible. Etape McAfee/Norton ignoree, preparation continue.'
        return [pscustomobject]@{ Success = $false; Detected = 0; Removed = 0; Pending = 0; TimedOut = $false; Error = 'Worker indisponible' }
    }

    $runtimeRoot = Get-LDLCRuntimeRoot
    $resultPath = Join-Path $runtimeRoot 'LDLC_SECURITY_CLEANUP_RESULT.json'
    Remove-Item -LiteralPath $resultPath -Force -ErrorAction SilentlyContinue
    $previousResultPath = $env:LDLC_SECURITY_RESULT_PATH
    $previousVendorFilter = $env:LDLC_SECURITY_VENDOR_FILTER
    $process = $null

    try {
        $env:LDLC_SECURITY_RESULT_PATH = $resultPath
        $env:LDLC_SECURITY_VENDOR_FILTER = $SecurityVendor
        $psExe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        Write-Step "McAfee/Norton : lancement isole avec limite globale de ${TimeoutSeconds}s."
        $process = Start-Process `
            -FilePath $psExe `
            -ArgumentList @('-ExecutionPolicy', 'Bypass', '-NoProfile', '-File', ('"{0}"' -f $workerScript), '-SecurityCleanupWorker') `
            -WindowStyle Hidden `
            -PassThru `
            -ErrorAction Stop

        $deadline = (Get-Date).AddSeconds([math]::Max(10, $TimeoutSeconds))
        while (-not $process.HasExited -and (Get-Date) -lt $deadline) {
            if ($script:StopFile -and (Test-Path -LiteralPath $script:StopFile)) {
                try { & taskkill.exe /PID $process.Id /T /F | Out-Null } catch { try { $process.Kill() } catch {} }
                Stop-IfRequested
            }
            Start-Sleep -Milliseconds 500
        }

        if (-not $process.HasExited) {
            Write-Warn "McAfee/Norton depasse ${TimeoutSeconds}s. Sous-processus arrete, preparation continue."
            try { & taskkill.exe /PID $process.Id /T /F | Out-Null } catch { try { $process.Kill() } catch {} }
            Write-ProgressFile $EndPercent 'McAfee/Norton non termine, preparation continue.'
            return [pscustomobject]@{ Success = $false; Detected = 0; Removed = 0; Pending = 0; TimedOut = $true; Error = 'Delai global depasse' }
        }

        if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
            Write-Warn 'McAfee/Norton n a retourne aucun resultat. Preparation continue.'
            return [pscustomobject]@{ Success = $false; Detected = 0; Removed = 0; Pending = 0; TimedOut = $false; Error = 'Resultat absent' }
        }

        $result = Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $result.Success) {
            Write-Warn "McAfee/Norton isole en echec : $($result.Error). Preparation continue."
        }
        elseif ([int]$result.Pending -gt 0) {
            Write-Warn "McAfee/Norton : $($result.Pending) produit(s) encore present(s). Preparation continue."
        }
        else {
            Write-Ok "McAfee/Norton termine en mode isole : detectes=$($result.Detected), supprimes=$($result.Removed)."
        }

        Write-ProgressFile $EndPercent 'Etape McAfee/Norton terminee, suite de la preparation.'
        return $result
    }
    catch {
        if (Test-LDLCStopRequestError $_) { throw }
        Write-Warn "McAfee/Norton isole non lance : $($_.Exception.Message). Preparation continue."
        Write-ProgressFile $EndPercent 'McAfee/Norton ignore, preparation continue.'
        return [pscustomobject]@{ Success = $false; Detected = 0; Removed = 0; Pending = 0; TimedOut = $false; Error = $_.Exception.Message }
    }
    finally {
        if ($null -eq $previousResultPath) {
            Remove-Item Env:\LDLC_SECURITY_RESULT_PATH -ErrorAction SilentlyContinue
        }
        else {
            $env:LDLC_SECURITY_RESULT_PATH = $previousResultPath
        }
        if ($null -eq $previousVendorFilter) {
            Remove-Item Env:\LDLC_SECURITY_VENDOR_FILTER -ErrorAction SilentlyContinue
        }
        else {
            $env:LDLC_SECURITY_VENDOR_FILTER = $previousVendorFilter
        }
    }
}

function Invoke-LDLCPreparation {
    $script:LDLCWorkflowStatus = 'running'
    $script:LDLCWorkflowCompleted = $false
    $wuLaunch = $null

    try {
        Clear-Host
        Write-Section "PREPARATION DU POSTE"

        Stop-IfRequested
        Write-ProgressFile 1 "Detection de McAfee et Norton..."
        # Restore McAfee's pre-change isolated path; Norton remains interactive.
        [void](Invoke-LDLCSecurityCleanupIsolated -StartPercent 1 -EndPercent 2 -TimeoutSeconds 90 -SecurityVendor McAfee)
        [void](Remove-LDLCSecurityTrialsInteractively -StartPercent 2 -EndPercent 3)

        Stop-IfRequested
        Write-ProgressFile 4 "Creation du point de restauration avant Windows Update..."
        [void](Invoke-LDLCRestorePointCreation -ProgressPercent 4)

        Stop-IfRequested
        Write-ProgressFile 5 "Demarrage de Windows Update en arriere-plan..."
        $wuLaunch = Start-LDLCWindowsUpdatesDuringPreparation -StartPercent 5 -EndPercent 7

        Invoke-LDLCInitialSetup `
            -InternetProgressPercent 8 `
            -PowerProgressPercent 9 `
            -TimeProgressPercent 12

        Stop-IfRequested
        Write-ProgressFile 15 "Personnalisation Windows..."

        try {
            Set-LDLCWindowsLayout -ProgressPercent 15
        }
        catch {
            if (Test-LDLCStopRequestError $_) { throw }
            Write-Err "Erreur lors de la personnalisation Windows : $($_.Exception.Message)"
        }

        Stop-IfRequested
        Write-ProgressFile 18 "Configuration du fond d'ecran..."

        try {
            Ensure-LDLCWallpaperApplied -ProgressPercent 18 | Out-Null
        }
        catch {
            if (Test-LDLCStopRequestError $_) { throw }
            Write-Warn "Fond d'ecran non confirme au demarrage : $($_.Exception.Message)"
        }

        Write-ProgressFile 24 "Préparation du cache des installateurs officiels..."
        Initialize-LDLCInstallerCache | Out-Null

        Write-ProgressFile 25 "Préparation des installations..."

        $totalInstallSteps = $Apps.Count
        $installStart = 25
        $installEnd = 60
        $currentStep = 0

        foreach ($app in $Apps) {
            Stop-IfRequested
            $currentStep++

            if ($totalInstallSteps -gt 1) {
                $percent = $installStart + (($currentStep - 1) / ($totalInstallSteps - 1)) * ($installEnd - $installStart)
            }
            else {
                $percent = $installStart
            }

            $percent = [int][math]::Round($percent)

            try {
                Install-LDLCApplication -App $app -ProgressPercent $percent
            }
            catch {
                if (Test-LDLCStopRequestError $_) { throw }
                Write-Err "Erreur sur $($app.Name) : $($_.Exception.Message)"
            }
        }

        # Last step of the applications phase (25-60), before configuration.
        # Prepare only the verified manufacturer installer shortcut.
        [void](Invoke-LDLCVendorUtility -ProgressPercent 60)

        Stop-IfRequested
        Write-ProgressFile 80 "Configuration du bureau..."
        Write-Step "Configuration des icones systeme du bureau reportee en fin de script pour conserver l'ordre des icones."

        Stop-IfRequested
        Write-ProgressFile 87 "Configuration des applications par défaut avant les pilotes GPU..."

        try {
            Invoke-LDLCChromeDefaultAppsSequence -DeferFinalValidation
            Write-Step "Courte stabilisation apres les applications par defaut..."
            Start-Sleep -Milliseconds 1200
        }
        catch {
            if (Test-LDLCStopRequestError $_) { throw }
            Write-Info "Etape applications par defaut a verifier au bilan final : $($_.Exception.Message)"
        }

        Stop-IfRequested
        Write-ProgressFile 87 "Configuration finale des icones du bureau..."

        try {
            Enable-DesktopSystemIcons
        }
        catch {
            if (Test-LDLCStopRequestError $_) { throw }
            Write-Warn "Configuration finale des icones du bureau ignoree suite a une erreur : $($_.Exception.Message)"
        }

        Stop-IfRequested
        Write-ProgressFile 87 "Détection et installation des pilotes GPU..."

        try {
            Install-LDLCGpuDriversAndApps -ProgressPercent 88
        }
        catch {
            if (Test-LDLCStopRequestError $_) { throw }
            Write-Warn "Etape GPU ignoree suite a une erreur : $($_.Exception.Message)"
        }

        Stop-IfRequested
        Write-ProgressFile 89 "Suppression des logiciels OEM restants..."

        try {
            Remove-LDLCOemAndSecurityTrials -Mode Oem -StartPercent 89 -EndPercent 90 | Out-Null
        }
        catch {
            if (Test-LDLCStopRequestError $_) { throw }
            Write-Warn "Etape logiciels OEM ignoree suite a une erreur : $($_.Exception.Message)"
        }

        Stop-IfRequested
        Write-ProgressFile 90 "Suppression Microsoft Office..."

        try {
            Remove-LDLCMicrosoftOffice -ProgressPercent 90 | Out-Null
        }
        catch {
            if (Test-LDLCStopRequestError $_) { throw }
            Write-Warn "Etape Microsoft Office ignoree suite a une erreur : $($_.Exception.Message)"
        }

        Stop-IfRequested
        Write-ProgressFile 90 "Preparation du pin Chrome..."

        try {
            [void](Invoke-LDLCChromeTaskbarPinBeforeWindowsUpdate -ProgressPercent 90)
        }
        catch {
            if (Test-LDLCStopRequestError $_) { throw }
            Write-Warn "Epinglage Chrome ignore suite a une erreur : $($_.Exception.Message)"
        }

        Stop-IfRequested
        Write-ProgressFile 90 "Verification finale du fond d'ecran..."

        try {
            Ensure-LDLCWallpaperApplied -ProgressPercent 90 -VerifyOnly | Out-Null
        }
        catch {
            if (Test-LDLCStopRequestError $_) { throw }
            Write-Warn "Verification finale du fond d'ecran ignoree : $($_.Exception.Message)"
        }

        try {
            Repair-LDLCDesktopShortcuts
        }
        catch {
            if (Test-LDLCStopRequestError $_) { throw }
            Write-Warn "Verification finale des raccourcis ignoree suite a une erreur : $($_.Exception.Message)"
        }

        try {
            Set-LDLCDesktopOrderedLayout
        }
        catch {
            if (Test-LDLCStopRequestError $_) { throw }
            Write-Warn "Organisation finale du bureau ignoree suite a une erreur : $($_.Exception.Message)"
        }

        Restore-PowerSettings -ProgressPercent 97 -IgnoreStopRequest | Out-Null

        Stop-IfRequested
        [void](Confirm-LDLCDefaultAppsFinalState)
        Write-Section "FIN DU SCRIPT"

        $rebootRequired = $script:PendingReboot

        if ($rebootRequired) {
            Write-Warn "Preparation terminee. Un redemarrage est requis."
        }
        else {
            Write-Ok "Preparation terminee."
        }
        # Windows gere desormais la suite des mises a jour. Seul le declenchement
        # est notre responsabilite ; les autres erreurs restent traitees par le suivi.
        $script:LDLCWorkflowStatus = if ($wuLaunch -and $wuLaunch.Started) { 'success' } else { 'failed' }
        $script:LDLCWorkflowCompleted = $true
    }
    catch {
        if (Test-LDLCStopRequestError $_) {
            $script:LDLCWorkflowStatus = 'stopped'
            Write-Section "ARRET DU SCRIPT"
            Write-Warn "Le script a ete interrompu proprement par l'utilisateur."
        }
        else {
            $script:LDLCWorkflowStatus = 'failed'
            Write-Section "ERREUR FATALE"
            Write-Err $_.Exception.Message
        }
    }
    finally {
        try {
            if ($script:PowerSettingsCaptured -and -not $script:PowerSettingsRestored) {
                Restore-PowerSettings -ProgressPercent 97 -IgnoreStopRequest | Out-Null
            }
        }
        catch {
            Write-Warn "Impossible de restaurer les parametres d'alimentation en sortie : $($_.Exception.Message)"
        }
        if (Get-Command Complete-LDLCTelemetryRun -ErrorAction SilentlyContinue) {
            Complete-LDLCTelemetryRun -ResultStatus $script:LDLCWorkflowStatus -WorkflowCompleted $script:LDLCWorkflowCompleted
            if (Test-LDLCTelemetryDisabled) {
                $percent = if ($script:LDLCWorkflowCompleted) { 100 } else { 0 }
                Write-ProgressFile $percent "Suivi desactive : $($script:LDLCWorkflowStatus)." -IgnoreStopRequest
            }
        }
    }
}

# endregion Module: 90.Workflow.ps1
if ($SecurityIsolationSmokeTest) {
    # Ces workers auxiliaires ne sont pas des executions du PrepTool.
    # La telemetrie est reservee au worker principal afin d'eviter les lignes
    # "Initialisation" orphelines dans le tableau de bord.
    $env:LDLC_TELEMETRY_DISABLED = '1'
    $runtimeRoot = Get-LDLCRuntimeRoot
    $resultPath = Join-Path $runtimeRoot 'LDLC_SECURITY_ISOLATION_SMOKE_RESULT.json'
    $previousTestMode = $env:LDLC_TEST_MODE
    $previousTestDelay = $env:LDLC_SECURITY_TEST_DELAY_SECONDS
    try {
        Initialize-LDLCScriptState -ProjectRoot $script:LDLCRoot
        Remove-Item -LiteralPath $script:StopFile -Force -ErrorAction SilentlyContinue
        $isolationTimeout = if ($TestMode) {
            [math]::Min(30, [math]::Max(2, $SecurityIsolationTimeoutSeconds))
        }
        else {
            30
        }
        if ($TestMode) {
            $env:LDLC_TEST_MODE = '1'
            $env:LDLC_SECURITY_TEST_DELAY_SECONDS = [string]([math]::Min(30, [math]::Max(0, $SecurityTestDelaySeconds)))
        }
        $result = Invoke-LDLCSecurityCleanupIsolated -StartPercent 1 -EndPercent 3 -TimeoutSeconds $isolationTimeout
        [ordered]@{
            Success = [bool]$result.Success
            TimedOut = [bool]$result.TimedOut
            Detected = [int]$result.Detected
            Removed = [int]$result.Removed
            Pending = [int]$result.Pending
            Error = [string]$result.Error
        } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $resultPath -Encoding UTF8 -Force
    }
    catch {
        [ordered]@{ Success = $false; TimedOut = $false; Detected = 0; Removed = 0; Pending = 0; Error = $_.Exception.Message } |
            ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $resultPath -Encoding UTF8 -Force
    }
    finally {
        if ($null -eq $previousTestMode) { Remove-Item Env:\LDLC_TEST_MODE -ErrorAction SilentlyContinue } else { $env:LDLC_TEST_MODE = $previousTestMode }
        if ($null -eq $previousTestDelay) { Remove-Item Env:\LDLC_SECURITY_TEST_DELAY_SECONDS -ErrorAction SilentlyContinue } else { $env:LDLC_SECURITY_TEST_DELAY_SECONDS = $previousTestDelay }
    }
    return
}

if ($SecurityCleanupWorker) {
    $env:LDLC_TELEMETRY_DISABLED = '1'
    $ProgressPreference = 'Continue'
    $InformationPreference = 'Continue'
    $ConfirmPreference = 'None'
    $runtimeRoot = Get-LDLCRuntimeRoot
    $resultPath = if ($env:LDLC_SECURITY_RESULT_PATH) {
        [string]$env:LDLC_SECURITY_RESULT_PATH
    }
    else {
        Join-Path $runtimeRoot 'LDLC_SECURITY_CLEANUP_RESULT.json'
    }

    try {
        Initialize-LDLCScriptState -ProjectRoot $script:LDLCRoot
        if ($env:LDLC_TEST_MODE -eq '1' -and $env:LDLC_SECURITY_TEST_DELAY_SECONDS) {
            $testDelay = 0
            try { $testDelay = [math]::Min(30, [math]::Max(0, [int]$env:LDLC_SECURITY_TEST_DELAY_SECONDS)) } catch {}
            if ($testDelay -gt 0) { Start-Sleep -Seconds $testDelay }
        }
        $securityVendor = if ($env:LDLC_SECURITY_VENDOR_FILTER) { [string]$env:LDLC_SECURITY_VENDOR_FILTER } else { 'All' }
        $result = Remove-LDLCOemAndSecurityTrials -Mode Security -SecurityVendor $securityVendor -StartPercent 1 -EndPercent 3
        $payload = [ordered]@{
            Success = $true
            Detected = [int]$result.Detected
            Removed = [int]$result.Removed
            Pending = [int]$result.Pending
            Error = ''
        }
    }
    catch {
        $payload = [ordered]@{
            Success = $false
            Detected = 0
            Removed = 0
            Pending = 0
            Error = $_.Exception.Message
        }
    }

    try { $payload | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $resultPath -Encoding UTF8 -Force } catch {}
    return
}

if ($WorkerSmokeTest) {
    $env:LDLC_TELEMETRY_DISABLED = '1'
    $runtimeRoot = Get-LDLCRuntimeRoot
    $resultPath = if ($env:LDLC_WORKER_SMOKE_RESULT_PATH) {
        [string]$env:LDLC_WORKER_SMOKE_RESULT_PATH
    }
    else {
        Join-Path $runtimeRoot 'LDLC_WORKER_SMOKE_RESULT.json'
    }

    try {
        Initialize-LDLCScriptState -ProjectRoot $script:LDLCRoot
        $targets = @(Get-LDLCOemRemovalTargets -Mode Security)
        $requiredFunctions = @(
            'Invoke-LDLCPreparation',
            'Install-LDLCApplication',
            'Set-LDLCWindowsLayout',
            'Invoke-LDLCChromeDefaultAppsSequence',
            'Install-WindowsUpdates'
        )
        $missing = @($requiredFunctions | Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) })
        $payload = [ordered]@{
            Success = ($missing.Count -eq 0)
            WorkerPath = $PSCommandPath
            RuntimeRoot = $runtimeRoot
            SecurityTargets = $targets.Count
            MissingFunctions = $missing
            Error = ''
        }
    }
    catch {
        $payload = [ordered]@{
            Success = $false
            WorkerPath = $PSCommandPath
            RuntimeRoot = $runtimeRoot
            SecurityTargets = 0
            MissingFunctions = @()
            Error = $_.Exception.Message
        }
    }

    try { $payload | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $resultPath -Encoding UTF8 -Force } catch {}
    return
}

if ($WindowsUpdateWorker) {
    $env:LDLC_TELEMETRY_DISABLED = '1'
    $ProgressPreference = 'Continue'
    $InformationPreference = 'Continue'
    $VerbosePreference = 'SilentlyContinue'
    $ConfirmPreference = 'None'
    $script:LDLCSuppressWriteProgress = $false

    $runtimeRoot = Get-LDLCRuntimeRoot
    $resultPath = if (-not [string]::IsNullOrWhiteSpace($env:LDLC_WU_RESULT_PATH)) {
        [string]$env:LDLC_WU_RESULT_PATH
    }
    else {
        Join-Path $runtimeRoot 'LDLC_WINDOWS_UPDATE_RESULT.json'
    }
    $progressPath = if (-not [string]::IsNullOrWhiteSpace($env:LDLC_WU_PROGRESS_PATH)) {
        [string]$env:LDLC_WU_PROGRESS_PATH
    }
    else {
        Join-Path $runtimeRoot 'LDLC_WINDOWS_UPDATE_PROGRESS.txt'
    }

    $startPercent = 90
    $endPercent = 96
    try { if (-not [string]::IsNullOrWhiteSpace($env:LDLC_WU_START_PERCENT)) { $startPercent = [int]$env:LDLC_WU_START_PERCENT } } catch {}
    try { if (-not [string]::IsNullOrWhiteSpace($env:LDLC_WU_END_PERCENT)) { $endPercent = [int]$env:LDLC_WU_END_PERCENT } } catch {}

    try {
        Initialize-LDLCScriptState -ProjectRoot $script:LDLCRoot
        $script:ProgressFile = $progressPath
        Write-ProgressFile $startPercent "Windows Update en cours..."
        $result = Install-WindowsUpdates -StartPercent $startPercent -EndPercent $endPercent

        $payload = [ordered]@{
            Success = [bool]$result.Success
            RebootRequired = [bool]$result.RebootRequired
            Count = if ($result -is [hashtable] -and $result.ContainsKey('Count')) { [int]$result['Count'] } else { [int]$result.Count }
            Skipped = [bool]$result.Skipped
            TimedOut = $false
            BackgroundFallbackStarted = [bool]$result.BackgroundFallbackStarted
            RemainingCount = [int]$result.RemainingCount
            UsoFallbackUsed = [bool]$result.UsoFallbackUsed
            Completed = [bool]$result.Completed
            CycleCount = [int]$result.CycleCount
            MaxCycles = [int]$result.MaxCycles
            DownloadedCount = [int]$result.DownloadedCount
            DetectedCount = [int]$result.DetectedCount
            StartedActions = @($result.StartedActions)
            FailedActions = @($result.FailedActions)
            ServicesRunning = @($result.ServicesRunning)
            ServicesFailed = @($result.ServicesFailed)
            LastError = [string]$result.LastError
        }

        ($payload | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $resultPath -Encoding UTF8 -Force

        Write-LDLCLocalLog -Level 'INFO' -Text 'Worker Windows Update termine, resultat local ecrit.'
    }
    catch {
        $details = @(
            "Message: $($_.Exception.Message)",
            "Script: $($_.InvocationInfo.ScriptName)",
            "Line: $($_.InvocationInfo.ScriptLineNumber)",
            "Position: $($_.InvocationInfo.PositionMessage)",
            "Stack: $($_.ScriptStackTrace)"
        ) -join [Environment]::NewLine

        try {
            if (Get-Command Add-LDLCTelemetryEvent -ErrorAction SilentlyContinue) {
                Add-LDLCTelemetryEvent `
                    -Message "Erreur worker Windows Update : $($_.Exception.Message)" `
                    -Severity critical `
                    -Type 'Erreur Windows Update' `
                    -Status 'critique' `
                    -Details $details
            }
        }
        catch {}

        $payload = [ordered]@{
            Success = $false
            RebootRequired = $false
            Count = 0
            Skipped = $false
            TimedOut = $false
            BackgroundFallbackStarted = $false
            RemainingCount = 0
            UsoFallbackUsed = $false
            Completed = $false
            CycleCount = 0
            MaxCycles = 0
            DownloadedCount = 0
            DetectedCount = 0
            StartedActions = @()
            FailedActions = @()
            ServicesRunning = @()
            ServicesFailed = @()
            LastError = $_.Exception.Message
        }
        try { ($payload | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $resultPath -Encoding UTF8 -Force } catch {}
    }

    return
}

if ($InstallWorker) {
    Remove-Item Env:\LDLC_PREP_INSTALL_WORKER -ErrorAction SilentlyContinue

    $ProgressPreference = 'Continue'
    $InformationPreference = 'Continue'
    $VerbosePreference = 'SilentlyContinue'
    $ConfirmPreference = 'None'
    $script:LDLCSuppressWriteProgress = $false

    $runtimeRoot = Get-LDLCRuntimeRoot
    $progressPath = Join-Path $runtimeRoot 'LDLC_PROGRESS.txt'
    $stopPath = Join-Path $runtimeRoot 'LDLC_STOP'
    $workerLog = Join-Path $runtimeRoot 'LDLC_WORKER_ERROR.log'

    try {
        "0|Demarrage de la preparation..." | Set-Content -Path $progressPath -Encoding UTF8 -Force
        # The UI cleared stale requests before launching us. A new request must survive initialization.
        Initialize-LDLCScriptState -ProjectRoot $script:LDLCRoot -PreserveStopRequest
        Stop-IfRequested
        Invoke-LDLCPreparation | Out-Null
    }
    catch {
        if (Test-LDLCStopRequestError $_) {
            try {
                if (Get-Command Complete-LDLCTelemetryRun -ErrorAction SilentlyContinue) {
                    Complete-LDLCTelemetryRun -ResultStatus 'stopped'
                }
            }
            catch {}

            try { "0|Installation annulee." | Set-Content -Path $progressPath -Encoding UTF8 -Force } catch {}
            return
        }

        $details = @(
            "Message: $($_.Exception.Message)",
            "Script: $($_.InvocationInfo.ScriptName)",
            "Line: $($_.InvocationInfo.ScriptLineNumber)",
            "Position: $($_.InvocationInfo.PositionMessage)",
            "Stack: $($_.ScriptStackTrace)"
        ) -join [Environment]::NewLine

        try {
            if (Get-Command Add-LDLCTelemetryEvent -ErrorAction SilentlyContinue) {
                Add-LDLCTelemetryEvent `
                    -Message $_.Exception.Message `
                    -Severity critical `
                    -Type 'Erreur fatale worker' `
                    -Status 'critique' `
                    -Details $details
            }

            if (Get-Command Complete-LDLCTelemetryRun -ErrorAction SilentlyContinue) {
                Complete-LDLCTelemetryRun -ResultStatus 'failed'
            }
        }
        catch {}

        try { $details | Set-Content -Path $workerLog -Encoding UTF8 -Force } catch {}
        try { "0|Erreur worker : $($_.Exception.Message)" | Set-Content -Path $progressPath -Encoding UTF8 -Force } catch {}
    }

    return
}

$WorkerLauncher = {
    try {
        Initialize-LDLCEmbeddedWorkerState
        $workerScript = $script:LDLCEmbeddedWorkerScriptPath
        if ([string]::IsNullOrWhiteSpace($workerScript) -or -not (Test-LDLCFileReadable -Path $workerScript)) {
            throw "Worker absent, bloque, mis en quarantaine ou illisible : $workerScript"
        }

        $psExe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $workerMode = if ($env:LDLC_WORKER_SMOKE_TEST -eq '1') { '-WorkerSmokeTest' } else { '-InstallWorker' }
        Write-LDLCBootstrapLog "Lancement du worker stable depuis ProgramData : $workerScript"
        return Start-Process `
            -FilePath $psExe `
            -WindowStyle Hidden `
            -ArgumentList @('-ExecutionPolicy', 'Bypass', '-NoProfile', '-File', ('"{0}"' -f $workerScript), $workerMode) `
            -PassThru `
            -ErrorAction Stop
    }
    catch {
        $securityProducts = @(Get-LDLCBootstrapSecurityProducts)
        Show-LDLCBootstrapFailure -Reason "Impossible de lancer le module de preparation : $($_.Exception.Message)" -SecurityProducts $securityProducts
        throw
    }
}

# region UI
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ===== ADMIN AUTO =====
function Test-LDLCIsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not $Preview -and -not (Test-LDLCIsAdmin)) {
    if (Get-Command Start-LDLCInstance -ErrorAction SilentlyContinue) {
        Start-LDLCInstance -Arguments @() -RunAs | Out-Null
    }
    else {
        $entryPoint = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
        $psExe = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"

        Start-Process $psExe `
            -Verb RunAs `
            -WindowStyle Minimized `
            -ArgumentList "-ExecutionPolicy Bypass -NoProfile -File `"$entryPoint`""
    }

    return
}

# ===== PATHS =====
function Get-LDLCUIBasePath {
    if (-not [string]::IsNullOrWhiteSpace($script:LDLCRoot)) {
        return $script:LDLCRoot
    }

    if ($PSScriptRoot) {
        return $PSScriptRoot
    }

    if ($PSCommandPath) {
        return (Split-Path -Parent $PSCommandPath)
    }

    if ($MyInvocation.MyCommand.Path) {
        return (Split-Path -Parent $MyInvocation.MyCommand.Path)
    }

    return (Get-Location).Path
}

function Get-LDLCUIEmbeddedAssetRoot {
    if (-not [string]::IsNullOrWhiteSpace($script:LDLCEmbeddedAssetRoot)) {
        return $script:LDLCEmbeddedAssetRoot
    }

    if (Get-Command Get-LDLCWritableRuntimeRoot -ErrorAction SilentlyContinue) {
        return Get-LDLCWritableRuntimeRoot
    }

    return $null
}

function Get-LDLCUIRuntimeRoot {
    $runtimeRoot = Get-LDLCUIEmbeddedAssetRoot

    if ([string]::IsNullOrWhiteSpace($runtimeRoot)) {
        $runtimeRoot = Join-Path (Get-LDLCUIBasePath) 'runtime'
    }

    if (-not (Test-Path -LiteralPath $runtimeRoot)) {
        New-Item -ItemType Directory -Path $runtimeRoot -Force | Out-Null
    }

    return $runtimeRoot
}

function Remove-LDLCUILegacyRuntimeFiles {
    foreach ($legacyPath in @(
        'C:\LDLC_PROGRESS.txt',
        'C:\LDLC_WORKER_LAUNCH.log',
        'C:\LDLC_WORKER_ERROR.log',
        'C:\LDLC_STOP'
    )) {
        Remove-Item -LiteralPath $legacyPath -Force -ErrorAction SilentlyContinue
    }
}

function Resolve-LDLCUIAssetPath {
    param([Parameter(Mandatory = $true)][string[]]$RelativePaths)

    $assetRoots = New-Object System.Collections.Generic.List[string]
    $baseRoot = Get-LDLCUIBasePath
    $embeddedRoot = Get-LDLCUIEmbeddedAssetRoot

    if (-not [string]::IsNullOrWhiteSpace($baseRoot)) {
        [void]$assetRoots.Add($baseRoot)

        $baseParent = Split-Path -Parent $baseRoot
        if (-not [string]::IsNullOrWhiteSpace($baseParent)) {
            [void]$assetRoots.Add($baseParent)
        }

        [void]$assetRoots.Add((Join-Path $baseRoot 'assets'))
        if (-not [string]::IsNullOrWhiteSpace($baseParent)) {
            [void]$assetRoots.Add((Join-Path $baseParent 'assets'))
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($embeddedRoot)) {
        [void]$assetRoots.Add($embeddedRoot)
    }

    foreach ($relativePath in $RelativePaths) {
        foreach ($assetRoot in ($assetRoots | Select-Object -Unique)) {
            $candidate = Join-Path $assetRoot $relativePath
            if (Test-Path $candidate) {
                return $candidate
            }
        }
    }

    return $null
}

$base = Get-LDLCUIBasePath
$bgPath = Resolve-LDLCUIAssetPath -RelativePaths @(
    'UI_Background.v2.png',
    'assets\UI_Background.v2.png',
    'UI_Background.png',
    'assets\UI_Background.png'
)
$installScript = Join-Path $base 'install.ps1'
$script:runtimeRoot = Get-LDLCUIRuntimeRoot
$script:progressFile = Join-Path $script:runtimeRoot 'LDLC_PROGRESS.txt'
$script:stopFile = Join-Path $script:runtimeRoot 'LDLC_STOP'
Remove-LDLCUILegacyRuntimeFiles

if ([string]::IsNullOrWhiteSpace($bgPath) -or -not (Test-Path $bgPath)) {
    [System.Windows.Forms.MessageBox]::Show("UI_Background.v2.png introuvable dans $base ou dans le dossier d'extraction.")
    return
}

if (-not $Preview -and -not $WorkerLauncher -and -not (Test-Path $installScript)) {
    [System.Windows.Forms.MessageBox]::Show("install.ps1 introuvable : $installScript")
    return
}

# ===== MUTEX =====
$mutexName = if ($Preview) { 'LDLC_PREPTOOL_PREVIEW_MUTEX' } else { 'LDLC_PREPTOOL_MUTEX' }
$created = $false
$mutex = New-Object System.Threading.Mutex($true, $mutexName, [ref]$created)
if (-not $created) { return }

$script:phases = @(
    @{
        Name = 'PREPARATION'
        Detail = 'Verification et nettoyage Windows'
        Min = 0
        Max = 24
    },
    @{
        Name = 'INSTALLATION'
        Detail = 'Installation des applications'
        Min = 25
        Max = 60
    },
    @{
        Name = 'CONFIGURATION'
        Detail = 'Bureau, wallpaper et pilotes'
        Min = 61
        Max = 89
    },
    @{
        Name = 'FINALISATION'
        Detail = 'Controles finaux'
        Min = 90
        Max = 100
    }
)

$script:previewTimeline = @(
    @{ Percent = 0;   Message = 'Initialisation de l environnement...' },
    @{ Percent = 5;   Message = 'Windows Update en arriere-plan...' },
    @{ Percent = 8;   Message = 'Verification de la connexion Internet...' },
    @{ Percent = 16;  Message = 'Suppression raccourcis Edge...' },
    @{ Percent = 20;  Message = 'Suppression Copilot barre des taches...' },
    @{ Percent = 25;  Message = 'Preparation des installations...' },
    @{ Percent = 38;  Message = 'Installation Google Chrome...' },
    @{ Percent = 50;  Message = 'Installation LibreOffice, Adobe, VLC et 7-Zip...' },
    @{ Percent = 76;  Message = 'Application du fond d ecran LDLC...' },
    @{ Percent = 88;  Message = 'Preparation des pilotes GPU...' },
    @{ Percent = 96;  Message = 'Restauration veille et controles finaux...' },
    @{ Percent = 100; Message = 'Preparation terminee, tu peux quitter !' }
)

$script:percent = 0
$script:message = if ($Preview) { $script:previewTimeline[0].Message } else { 'Initialisation de l environnement...' }
$script:proc = $null
$script:workerLaunchAttempted = $false
$script:uiFirstPaintCompleted = $false
$script:previewIndex = 0
$script:closing = $false
$script:closeStep = 0
$script:closeRequestedAt = $null
$script:stopFileCreated = $false
$script:forceStopDone = $false
$script:gracefulStopTimeoutSeconds = 8
$script:closeAfterForceSeconds = 10
$script:LDLCAppVersionLabel = 'Version 1.0'

function Convert-X {
    param([int]$Value)
    return [int]($Value * $script:scaleX)
}

function Convert-Y {
    param([int]$Value)
    return [int]($Value * $script:scaleY)
}

function Convert-FontSize {
    param(
        [double]$Value,
        [double]$Minimum = 7
    )

    $scale = [Math]::Min($script:scaleX, $script:scaleY)
    return [single][Math]::Max($Minimum, ($Value * $scale * 0.72))
}

function Limit-LDLCText {
    param(
        [string]$Text,
        [int]$MaxLength
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ''
    }

    $value = $Text.Trim()
    if ($value.Length -le $MaxLength) {
        return $value
    }

    return ($value.Substring(0, [Math]::Max(0, $MaxLength - 3)) + '...')
}

function Draw-LDLCTextWithShadow {
    param(
        [Parameter(Mandatory = $true)][System.Drawing.Graphics]$Graphics,
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][System.Drawing.Font]$Font,
        [Parameter(Mandatory = $true)][System.Drawing.Brush]$Brush,
        [Parameter(Mandatory = $true)][System.Drawing.RectangleF]$Bounds,
        [System.Drawing.StringFormat]$Format,
        [int]$ShadowAlpha = 190
    )

    $shadowBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb($ShadowAlpha, 0, 0, 0))
    $shadowBounds = New-Object System.Drawing.RectangleF(
        ($Bounds.X + 1),
        ($Bounds.Y + 1),
        $Bounds.Width,
        $Bounds.Height
    )

    if ($Format) {
        $Graphics.DrawString($Text, $Font, $shadowBrush, $shadowBounds, $Format)
        $Graphics.DrawString($Text, $Font, $Brush, $Bounds, $Format)
    }
    else {
        $Graphics.DrawString($Text, $Font, $shadowBrush, $shadowBounds)
        $Graphics.DrawString($Text, $Font, $Brush, $Bounds)
    }

    $shadowBrush.Dispose()
}

function Get-LDLCPhaseIndex {
    param([int]$Percent)

    for ($i = 0; $i -lt $script:phases.Count; $i++) {
        if ($Percent -ge $script:phases[$i].Min -and $Percent -le $script:phases[$i].Max) {
            return $i
        }
    }

    return ($script:phases.Count - 1)
}

function Get-LDLCStatusTitle {
    param([int]$Percent)

    if ($script:closing) {
        return 'ARRET EN COURS...'
    }

    $phaseIndex = Get-LDLCPhaseIndex -Percent $Percent
    switch ($script:phases[$phaseIndex].Name) {
        'PREPARATION'   { return 'PREPARATION DU SYSTEME...' }
        'INSTALLATION'  { return 'INSTALLATION DES APPLICATIONS...' }
        'CONFIGURATION' { return 'CONFIGURATION DU SYSTEME...' }
        default         { return 'FINALISATION...' }
    }
}

function Read-LDLCProgressFile {
    if (-not (Test-Path $script:progressFile)) {
        return
    }

    try {
        $line = Get-Content $script:progressFile -ErrorAction Stop | Select-Object -Last 1
        if ($line -match '^(\d+)\|(.*)$') {
            $script:percent = [Math]::Max(0, [Math]::Min(100, [int]$matches[1]))
            $script:message = Limit-LDLCText -Text $matches[2] -MaxLength 78
        }
    }
    catch {}
}

function Update-LDLCPreviewProgress {
    $target = $script:previewTimeline[$script:previewIndex]
    $script:message = $target.Message

    if ($script:percent -lt $target.Percent) {
        $script:percent = [Math]::Min($target.Percent, ($script:percent + 1))
        return
    }

    $script:previewIndex++
    if ($script:previewIndex -ge $script:previewTimeline.Count) {
        Start-Sleep -Milliseconds 350
        $script:previewIndex = 0
        $script:percent = 0
    }
}

function Initialize-LDLCCompactFormType {
    if ('LDLCCompactForm' -as [type]) { return }
    Add-Type -ReferencedAssemblies System.Windows.Forms,System.Drawing @"
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Diagnostics;
using System.Windows.Forms;
public class LDLCCompactForm : Form {
    readonly Timer animation = new Timer();
    readonly Stopwatch clock = Stopwatch.StartNew();
    double last, transitionStart, transitionFrom;
    double displayed;
    int target;
    public int ProgressTarget { get { return target; } }
    public double DisplayedProgress { get { return displayed; } }
    public double SpinnerAngle { get; private set; }
    public int AnimationFrames { get; private set; }
    public bool Running { get; private set; }
    public bool Success { get; private set; }
    public string StatusMessage { get; private set; }
    public string ErrorApplication { get; private set; }
    public LDLCCompactForm() {
        DoubleBuffered = true; FormBorderStyle = FormBorderStyle.None;
        ClientSize = new Size(380,205); BackColor = Color.FromArgb(8,25,46);
        ShowInTaskbar = false; TopMost = true; StartPosition = FormStartPosition.Manual;
        AutoScaleMode = AutoScaleMode.None;
        StatusMessage = "Configuration d'Adobe Acrobat Reader\u2026"; ErrorApplication = "";
        Running = true; Text = "Pr\u00e9paration PC - Applications par d\u00e9faut";
        AccessibleName = Text;
        animation.Interval = 16;
        animation.Tick += delegate {
            double now = clock.Elapsed.TotalMilliseconds;
            if (Running) SpinnerAngle = (SpinnerAngle + Math.Min(80, now-last)*0.24) % 360;
            last = now;
            double t = Math.Min(1, Math.Max(0, (now-transitionStart)/420));
            double ease = t*t*(3-2*t);
            displayed = transitionFrom + (target-transitionFrom)*ease;
            AnimationFrames++; Invalidate();
        };
    }
    public void SetStatus(int percent, string message, bool running, bool success, string error) {
        if (percent != 0 && percent != 50 && percent != 100) throw new ArgumentException("Invalid stage");
        if (percent == 100 && (!success || running || !String.IsNullOrEmpty(error))) throw new ArgumentException("Unconfirmed completion");
        if (percent != target) { transitionFrom = displayed; target = percent; transitionStart = clock.Elapsed.TotalMilliseconds; }
        StatusMessage = (message ?? "").Replace("...", "\u2026").Replace("terminee","termin\u00e9e").Replace("confirmee","confirm\u00e9e").Replace("Selection","S\u00e9lection").Replace("reglages","r\u00e9glages").Replace("resultat","r\u00e9sultat");
        Running = running; Success = success; ErrorApplication = error ?? "";
        AccessibleDescription = StatusMessage + " " + percent + "% " + ErrorApplication;
        Invalidate();
    }
    protected override void OnShown(EventArgs e) { last = clock.Elapsed.TotalMilliseconds; animation.Start(); base.OnShown(e); }
    protected override bool ShowWithoutActivation { get { return true; } }
    protected override CreateParams CreateParams {
        get { CreateParams p = base.CreateParams; p.ExStyle |= 0x08000000 | 0x00000080; return p; }
    }
    protected override void WndProc(ref Message m) {
        if (m.Msg == 0x0021) { m.Result = new IntPtr(3); return; }
        base.WndProc(ref m);
    }
    static GraphicsPath Round(RectangleF r, float radius) {
        GraphicsPath p = new GraphicsPath(); float d = radius*2;
        p.AddArc(r.X,r.Y,d,d,180,90); p.AddArc(r.Right-d,r.Y,d,d,270,90);
        p.AddArc(r.Right-d,r.Bottom-d,d,d,0,90); p.AddArc(r.X,r.Bottom-d,d,d,90,90); p.CloseFigure(); return p;
    }
    protected override void OnSizeChanged(EventArgs e) {
        using (GraphicsPath p = Round(new RectangleF(0,0,Width,Height),18*Width/620f)) {
            Region old = Region; Region = new Region(p); if (old != null) old.Dispose();
        }
        base.OnSizeChanged(e);
    }
    static void TextAt(Graphics g, string text, float size, FontStyle style, Color color, RectangleF rect) {
        using (Font font = new Font("Segoe UI",size,style,GraphicsUnit.Pixel))
        using (Brush brush = new SolidBrush(color))
        using (StringFormat format = new StringFormat()) {
            format.Trimming = StringTrimming.EllipsisCharacter;
            g.DrawString(text,font,brush,rect,format);
        }
    }
    protected override void OnPaint(PaintEventArgs e) {
        Graphics g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias;
        g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
        g.ScaleTransform(ClientSize.Width/620f,ClientSize.Height/334f);
        using (GraphicsPath outer = Round(new RectangleF(1,1,618,332),17))
        using (Brush bg = new LinearGradientBrush(new Point(0,0),new Point(620,334),Color.FromArgb(12,35,60),Color.FromArgb(6,20,38)))
        using (Pen border = new Pen(Color.FromArgb(72,99,127),1.5f)) { g.FillPath(bg,outer); g.DrawPath(border,outer); }
        using (Pen line = new Pen(Color.FromArgb(30,61,88))) g.DrawLine(line,1,45,619,45);
        TextAt(g,"Pr\u00e9paration PC",20,FontStyle.Bold,Color.FromArgb(39,195,238),new RectangleF(20,12,580,30));
        TextAt(g,"Applications par d\u00e9faut",29,FontStyle.Bold,Color.White,new RectangleF(28,63,570,40));
        TextAt(g,"Configuration d'Adobe Acrobat Reader et de Chrome",18,FontStyle.Regular,Color.FromArgb(181,202,224),new RectangleF(28,108,565,26));
        using (GraphicsPath card = Round(new RectangleF(20,144,580,78),12))
        using (Brush bg = new SolidBrush(Color.FromArgb(13,39,66)))
        using (Pen border = new Pen(Color.FromArgb(31,69,105),1.2f)) { g.FillPath(bg,card); g.DrawPath(border,card); }
        Color accent = Success ? Color.FromArgb(72,211,149) : (!Running ? Color.FromArgb(244,108,105) : Color.FromArgb(15,161,249));
        if (Running) {
            using (Pen track = new Pen(Color.FromArgb(25,66,103),5)) g.DrawEllipse(track,40,163,35,35);
            using (Pen arc = new Pen(accent,5)) { arc.StartCap=LineCap.Round; arc.EndCap=LineCap.Round; g.DrawArc(arc,40,163,35,35,(float)SpinnerAngle,100); }
        } else {
            using (Pen pen = new Pen(accent,4)) {
                pen.StartCap=LineCap.Round; pen.EndCap=LineCap.Round;
                if (Success) g.DrawLines(pen,new PointF[]{new PointF(42,181),new PointF(53,192),new PointF(75,169)});
                else { g.DrawLine(pen,45,170,70,195); g.DrawLine(pen,70,170,45,195); }
            }
        }
        TextAt(g,StatusMessage,20,FontStyle.Regular,Color.White,new RectangleF(96,155,490,String.IsNullOrEmpty(ErrorApplication)?52:30));
        if (!String.IsNullOrEmpty(ErrorApplication)) TextAt(g,"\u00c9chec : "+ErrorApplication,12,FontStyle.Regular,Color.FromArgb(255,151,140),new RectangleF(96,187,490,32));
        using (GraphicsPath track = Round(new RectangleF(20,236,580,10),5))
        using (Brush brush = new SolidBrush(Color.FromArgb(25,57,89))) g.FillPath(brush,track);
        if (displayed > 0.1) {
            using (GraphicsPath bar = Round(new RectangleF(20,236,(float)(580*displayed/100),10),Math.Min(5,(float)(580*displayed/200))))
            using (Brush brush = new SolidBrush(accent)) g.FillPath(brush,bar);
        }
        TextAt(g,target+" %",16,FontStyle.Bold,Color.FromArgb(181,202,224),new RectangleF(554,250,50,24));
        using (GraphicsPath warning = Round(new RectangleF(20,278,580,38),10))
        using (Brush brush = new SolidBrush(Color.FromArgb(49,43,28)))
        using (Pen pen = new Pen(Color.FromArgb(115,86,32),1)) { g.FillPath(brush,warning); g.DrawPath(pen,warning); }
        TextAt(g,"Ne touchez pas au clavier ni \u00e0 la souris.",19,FontStyle.Regular,Color.FromArgb(255,202,94),new RectangleF(38,286,550,27));
    }
    protected override void Dispose(bool disposing) { if (disposing) animation.Dispose(); base.Dispose(disposing); }
}
"@
}

function New-LDLCCompactForm {
    Initialize-LDLCCompactFormType
    $compact = New-Object LDLCCompactForm
    return $compact
}
function Set-LDLCCompactUiState {
    param($MainForm, [bool]$Active)
    if ($Active -eq [bool]$script:LDLCCompactUiState) { return }
    if ($Active) {
        $script:LDLCCompactUiState = @{ WindowState = $MainForm.WindowState; TopMost = $MainForm.TopMost }
        try {
            $script:LDLCCompactForm = New-LDLCCompactForm
            $MainForm.TopMost = $false
            $MainForm.WindowState = [System.Windows.Forms.FormWindowState]::Minimized
            # No owner: a minimized owner would also hide the compact form.
            $area = [System.Windows.Forms.Screen]::FromControl($MainForm).WorkingArea
            $script:LDLCCompactForm.Left = $area.Left + 16
            $script:LDLCCompactForm.Top = [Math]::Max($area.Top, $area.Bottom - $script:LDLCCompactForm.Height - 16)
            $script:LDLCCompactForm.Show()
            $script:LDLCCompactForm.Top = [Math]::Max($area.Top, $area.Bottom - $script:LDLCCompactForm.Height - 16)
        }
        catch {
            Set-LDLCCompactUiState -MainForm $MainForm -Active $false
            throw
        }
        return
    }
    try {
        if ($script:LDLCCompactForm) { $script:LDLCCompactForm.Close(); $script:LDLCCompactForm.Dispose() }
    }
    finally {
        $script:LDLCCompactForm = $null
        try {
            $MainForm.WindowState = $script:LDLCCompactUiState.WindowState
            $MainForm.TopMost = $script:LDLCCompactUiState.TopMost
        }
        finally { $script:LDLCCompactUiState = $null }
    }
}

function Read-LDLCCompactUiSignal {
    param([string]$RuntimeRoot, $Worker)
    if (-not $Worker -or $Worker.HasExited) { return $null }
    $path = Join-Path $RuntimeRoot "LDLC_DEFAULT_APPS.$($Worker.Id).json"
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try {
        $stream = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
        $reader = New-Object IO.StreamReader($stream)
        try { $signal = $reader.ReadToEnd() | ConvertFrom-Json -ErrorAction Stop }
        finally { $reader.Dispose() }
        if ($signal.Active -eq $true -and $signal.WorkerId -eq $Worker.Id) {
            $script:LDLCCompactLastSignal = $signal
            return $signal
        }
        return $null
    }
    catch {
        # A partial write must not restore/reminimize the form on consecutive ticks.
        if ($script:LDLCCompactLastSignal -and $script:LDLCCompactLastSignal.WorkerId -eq $Worker.Id) { return $script:LDLCCompactLastSignal }
        return $null
    }
}

function Confirm-LDLCCompactUiSignal {
    param($Form, $Signal, [string]$RuntimeRoot)
    $path = Join-Path $RuntimeRoot "LDLC_DEFAULT_APPS.$($Signal.WorkerId).json.ack"
    $revision = [long]$Signal.Revision
    if ($script:LDLCCompactAckPath -eq $path -and $script:LDLCCompactAckRevision -eq $revision -and (Test-Path -LiteralPath $path)) { return }
    # Paint the new text before acknowledging it; do not activate or focus this form.
    $Form.Update()
    $ack = [ordered]@{
        WorkerId = $Signal.WorkerId; Revision = $revision; Progress = $Form.ProgressTarget
        Message = $Form.StatusMessage; Running = $Form.Running; Success = $Form.Success
        RenderedAt = [DateTime]::UtcNow.ToString('o'); AnimationFrames = $Form.AnimationFrames; SpinnerAngle = $Form.SpinnerAngle
    }
    $temporary = $path + '.tmp'
    try {
        [IO.File]::WriteAllText($temporary, ($ack | ConvertTo-Json -Compress))
        if (Test-Path -LiteralPath $path) { [IO.File]::Replace($temporary, $path, [NullString]::Value) }
        else { [IO.File]::Move($temporary, $path) }
        $script:LDLCCompactAckPath = $path; $script:LDLCCompactAckRevision = $revision
        return [pscustomobject]$ack
    }
    catch [IO.IOException] { return }
    finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue } }
}

function Update-LDLCCompactUi {
    param($MainForm, [string]$RuntimeRoot, $Worker)
    $signal = Read-LDLCCompactUiSignal -RuntimeRoot $RuntimeRoot -Worker $Worker
    $active = [bool]$signal
    Set-LDLCCompactUiState -MainForm $MainForm -Active $active
    if ($active -and $script:LDLCCompactUiState) {
        if ($signal.PSObject.Properties['Progress']) {
            $script:LDLCCompactForm.SetStatus([int]$signal.Progress, [string]$signal.Message,
                [bool]$signal.Running, [bool]$signal.Success, [string]$signal.ErrorApplication)
        }
        Confirm-LDLCCompactUiSignal -Form $script:LDLCCompactForm -Signal $signal -RuntimeRoot $RuntimeRoot | Out-Null
    }
}

function Test-LDLCUiFinalizationReady {
    if (-not $script:proc) { return $false }
    try {
        return (Test-LDLCFinalizationReady -RuntimeRoot $script:runtimeRoot -WorkerProcessId $script:proc.Id -WorkerStartTicks $script:proc.StartTime.ToUniversalTime().Ticks)
    }
    catch { return $false }
}

function Stop-LDLCProcessTree {
    param([int]$ProcessId)

    try {
        $children = Get-CimInstance Win32_Process -Filter "ParentProcessId = $ProcessId" -ErrorAction SilentlyContinue
        foreach ($child in $children) {
            Stop-LDLCProcessTree -ProcessId $child.ProcessId
        }
    }
    catch {}

    try {
        Stop-Process -Id $ProcessId -Force -Confirm:$false -ErrorAction SilentlyContinue
    }
    catch {}
}

function New-RoundedRectanglePath {
    param(
        [System.Drawing.RectangleF]$Bounds,
        [float]$Radius
    )

    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $safeRadius = [Math]::Max(0, [Math]::Min($Radius, ([Math]::Min($Bounds.Width, $Bounds.Height) / 2)))
    $diameter = $safeRadius * 2

    if ($diameter -le 0) {
        $path.AddRectangle($Bounds)
        return $path
    }

    $path.AddArc($Bounds.X, $Bounds.Y, $diameter, $diameter, 180, 90)
    $path.AddArc(($Bounds.Right - $diameter), $Bounds.Y, $diameter, $diameter, 270, 90)
    $path.AddArc(($Bounds.Right - $diameter), ($Bounds.Bottom - $diameter), $diameter, $diameter, 0, 90)
    $path.AddArc($Bounds.X, ($Bounds.Bottom - $diameter), $diameter, $diameter, 90, 90)
    $path.CloseFigure()
    return $path
}

function Initialize-LDLCUiPixelBuffer {
    if ('LDLCUiPixelBuffer' -as [type]) { return }

    # Keep the original alpha/mask rules; run the pixel loops outside PowerShell.
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;

public static class LDLCUiPixelBuffer
{
    public static void RemoveFringe(byte[] pixels, int width, int height, int stride,
        int cutoff, byte red, byte green, byte blue, bool preserveZeroAlpha)
    {
        for (int y = 0; y < height; y++)
        {
            for (int x = 0, offset = y * stride; x < width; x++, offset += 4)
            {
                byte alpha = pixels[offset + 3];
                if (preserveZeroAlpha && alpha == 0) continue;
                if (alpha < cutoff)
                {
                    pixels[offset] = blue;
                    pixels[offset + 1] = green;
                    pixels[offset + 2] = red;
                    pixels[offset + 3] = 0;
                }
                else if (alpha < 255) pixels[offset + 3] = 255;
            }
        }
    }

    // Each visible horizontal run is (x, y, length), in the original order.
    public static int[] GetAlphaRuns(byte[] pixels, int width, int height, int stride, int threshold)
    {
        List<int> runs = new List<int>();
        for (int y = 0; y < height; y++)
        {
            int start = -1;
            for (int x = 0; x < width; x++)
            {
                bool visible = pixels[y * stride + x * 4 + 3] >= threshold;
                if (visible && start < 0) start = x;
                else if (!visible && start >= 0)
                {
                    runs.Add(start); runs.Add(y); runs.Add(x - start);
                    start = -1;
                }
            }
            if (start >= 0)
            {
                runs.Add(start); runs.Add(y); runs.Add(width - start);
            }
        }
        return runs.ToArray();
    }

    public static void ApplyRoundedMask(byte[] pixels, int width, int height, int stride,
        double radius, byte red, byte green, byte blue)
    {
        for (int y = 0; y < height; y++)
        {
            for (int x = 0; x < width; x++)
            {
                double cx, cy;
                if (x < radius && y < radius) { cx = radius; cy = radius; }
                else if (x >= width - radius && y < radius) { cx = width - radius - 1; cy = radius; }
                else if (x < radius && y >= height - radius) { cx = radius; cy = height - radius - 1; }
                else if (x >= width - radius && y >= height - radius) { cx = width - radius - 1; cy = height - radius - 1; }
                else continue;
                double dx = x - cx, dy = y - cy;
                if (dx * dx + dy * dy <= radius * radius) continue;
                int offset = y * stride + x * 4;
                pixels[offset] = blue;
                pixels[offset + 1] = green;
                pixels[offset + 2] = red;
                pixels[offset + 3] = 0;
            }
        }
    }
}
'@
}

function New-LDLCBitmapAlphaRegion {
    param(
        [Parameter(Mandatory = $true)][System.Drawing.Bitmap]$Bitmap,
        [int]$AlphaThreshold = 32
    )

    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $rect = New-Object System.Drawing.Rectangle 0, 0, $Bitmap.Width, $Bitmap.Height
    $data = $Bitmap.LockBits(
        $rect,
        [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
    )

    try {
        $stride = [Math]::Abs($data.Stride)
        $bytes = New-Object byte[] ($stride * $Bitmap.Height)
        [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $bytes.Length)

        Initialize-LDLCUiPixelBuffer
        $runs = [LDLCUiPixelBuffer]::GetAlphaRuns($bytes, $Bitmap.Width, $Bitmap.Height, $stride, $AlphaThreshold)
        for ($i = 0; $i -lt $runs.Length; $i += 3) {
            $path.AddRectangle((New-Object System.Drawing.Rectangle -ArgumentList $runs[$i], $runs[$i + 1], $runs[$i + 2], 1))
        }
    }
    finally {
        $Bitmap.UnlockBits($data)
    }

    if ($path.PointCount -eq 0) {
        $path.Dispose()
        return $null
    }

    $region = New-Object System.Drawing.Region $path
    $path.Dispose()
    return $region
}

function Remove-LDLCBitmapAlphaFringe {
    param(
        [Parameter(Mandatory = $true)][System.Drawing.Bitmap]$Bitmap,
        [int]$AlphaCutoff = 245,
        [System.Drawing.Color]$TransparentColor = ([System.Drawing.Color]::FromArgb(17, 18, 19))
    )

    $rect = New-Object System.Drawing.Rectangle 0, 0, $Bitmap.Width, $Bitmap.Height
    $data = $Bitmap.LockBits(
        $rect,
        [System.Drawing.Imaging.ImageLockMode]::ReadWrite,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
    )

    try {
        $stride = [Math]::Abs($data.Stride)
        $bytes = New-Object byte[] ($stride * $Bitmap.Height)
        [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $bytes.Length)

        Initialize-LDLCUiPixelBuffer
        [LDLCUiPixelBuffer]::RemoveFringe($bytes, $Bitmap.Width, $Bitmap.Height, $stride,
            $AlphaCutoff, $TransparentColor.R, $TransparentColor.G, $TransparentColor.B, $false)

        [System.Runtime.InteropServices.Marshal]::Copy($bytes, 0, $data.Scan0, $bytes.Length)
    }
    finally {
        $Bitmap.UnlockBits($data)
    }
}

function Apply-LDLCBitmapRoundedWindowMask {
    param(
        [Parameter(Mandatory = $true)][System.Drawing.Bitmap]$Bitmap,
        [Parameter(Mandatory = $true)][int]$Radius,
        [System.Drawing.Color]$TransparentColor = ([System.Drawing.Color]::FromArgb(17, 18, 19))
    )

    $safeRadius = [Math]::Max(1, [Math]::Min($Radius, [Math]::Min($Bitmap.Width, $Bitmap.Height) / 2))
    $rect = New-Object System.Drawing.Rectangle 0, 0, $Bitmap.Width, $Bitmap.Height
    $data = $Bitmap.LockBits(
        $rect,
        [System.Drawing.Imaging.ImageLockMode]::ReadWrite,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
    )

    try {
        $stride = [Math]::Abs($data.Stride)
        $bytes = New-Object byte[] ($stride * $Bitmap.Height)
        [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $bytes.Length)

        Initialize-LDLCUiPixelBuffer
        [LDLCUiPixelBuffer]::ApplyRoundedMask($bytes, $Bitmap.Width, $Bitmap.Height, $stride,
            $safeRadius, $TransparentColor.R, $TransparentColor.G, $TransparentColor.B)

        [System.Runtime.InteropServices.Marshal]::Copy($bytes, 0, $data.Scan0, $bytes.Length)
    }
    finally {
        $Bitmap.UnlockBits($data)
    }
}

function Resize-LDLCBackgroundBitmap {
    param(
        [Parameter(Mandatory = $true)][System.Drawing.Image]$Image,
        [Parameter(Mandatory = $true)][int]$Width,
        [Parameter(Mandatory = $true)][int]$Height
    )

    $bitmap = New-Object System.Drawing.Bitmap $Width, $Height, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)

    try {
        $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $targetRect = New-Object System.Drawing.Rectangle 0, 0, $Width, $Height
        $sourceRect = New-Object System.Drawing.Rectangle 0, 0, $Image.Width, $Image.Height
        $graphics.DrawImage($Image, $targetRect, $sourceRect, [System.Drawing.GraphicsUnit]::Pixel)
    }
    finally {
        $graphics.Dispose()
    }

    return $bitmap
}

function New-LDLCRoundedWindowRegion {
    param(
        [Parameter(Mandatory = $true)][int]$Width,
        [Parameter(Mandatory = $true)][int]$Height
    )

    $bounds = New-Object System.Drawing.RectangleF 0, 0, $Width, $Height
    $path = New-RoundedRectanglePath -Bounds $bounds -Radius (Convert-X 72)

    try {
        return (New-Object System.Drawing.Region $path)
    }
    finally {
        $path.Dispose()
    }
}

function New-StagePath {
    param([System.Drawing.RectangleF]$Bounds)

    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $cut = Convert-X 28
    $radius = Convert-X 18

    $path.StartFigure()
    $path.AddArc($Bounds.X, $Bounds.Y, ($radius * 2), ($radius * 2), 180, 90)
    $path.AddLine(($Bounds.X + $radius), $Bounds.Y, ($Bounds.Right - $cut), $Bounds.Y)
    $path.AddLine(($Bounds.Right - $cut), $Bounds.Y, $Bounds.Right, ($Bounds.Y + ($Bounds.Height / 2)))
    $path.AddLine($Bounds.Right, ($Bounds.Y + ($Bounds.Height / 2)), ($Bounds.Right - $cut), $Bounds.Bottom)
    $path.AddLine(($Bounds.Right - $cut), $Bounds.Bottom, ($Bounds.X + $radius), $Bounds.Bottom)
    $path.AddArc($Bounds.X, ($Bounds.Bottom - ($radius * 2)), ($radius * 2), ($radius * 2), 90, 90)
    $path.CloseFigure()
    return $path
}

function Draw-LDLCStageList {
    param(
        [System.Drawing.Graphics]$Graphics,
        [int]$ActiveIndex
    )

    $overlayBounds = New-Object System.Drawing.RectangleF((Convert-X 50), (Convert-Y 175), (Convert-X 430), (Convert-Y 475))
    $overlayPath = New-RoundedRectanglePath -Bounds $overlayBounds -Radius (Convert-X 18)
    $overlayBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 2, 18, 45))
    $Graphics.FillPath($overlayBrush, $overlayPath)
    $overlayBrush.Dispose()
    $overlayPath.Dispose()

    $fontTitle = New-Object System.Drawing.Font('Segoe UI', (Convert-FontSize 20 7), [System.Drawing.FontStyle]::Bold)
    $fontDetail = New-Object System.Drawing.Font('Segoe UI', (Convert-FontSize 13 6.5), [System.Drawing.FontStyle]::Regular)
    $fontNumber = New-Object System.Drawing.Font('Segoe UI', (Convert-FontSize 22 7), [System.Drawing.FontStyle]::Bold)
    $textFormat = New-Object System.Drawing.StringFormat
    $textFormat.Trimming = [System.Drawing.StringTrimming]::EllipsisCharacter
    $textFormat.FormatFlags = [System.Drawing.StringFormatFlags]::NoWrap

    for ($i = 0; $i -lt $script:phases.Count; $i++) {
        $y = 192 + ($i * 112)
        $bounds = New-Object System.Drawing.RectangleF((Convert-X 67), (Convert-Y $y), (Convert-X 417), (Convert-Y 90))
        $circleBounds = New-Object System.Drawing.RectangleF((Convert-X 88), (Convert-Y ($y + 12)), (Convert-X 58), (Convert-Y 58))
        $isActive = ($i -eq $ActiveIndex)

        if ($isActive) {
            $stagePath = New-StagePath -Bounds $bounds
            $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($bounds, [System.Drawing.Color]::FromArgb(255, 12, 145, 255), [System.Drawing.Color]::FromArgb(255, 0, 68, 218), 0)
            $Graphics.FillPath($brush, $stagePath)
            $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(230, 170, 225, 255), (Convert-X 1))
            $Graphics.DrawPath($pen, $stagePath)
            $pen.Dispose()
            $brush.Dispose()
            $stagePath.Dispose()

            $numberFill = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(230, 240, 248, 255))
            $numberPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 40, 145, 255), (Convert-X 3))
            $titleBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
            $detailBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(252, 232, 246, 255))
        }
        else {
            $stagePath = New-RoundedRectanglePath -Bounds $bounds -Radius (Convert-X 16)
            $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 8, 24, 56))
            $Graphics.FillPath($brush, $stagePath)
            $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(70, 60, 130, 200), (Convert-X 1))
            $Graphics.DrawPath($pen, $stagePath)
            $pen.Dispose()
            $brush.Dispose()
            $stagePath.Dispose()

            $numberFill = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 18, 40, 76))
            $numberPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(130, 95, 135, 180), (Convert-X 2))
            $titleBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(245, 230, 240, 255))
            $detailBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(225, 205, 225, 248))
        }

        $Graphics.FillEllipse($numberFill, $circleBounds)
        $Graphics.DrawEllipse($numberPen, $circleBounds)

        $numberFormat = New-Object System.Drawing.StringFormat
        $numberFormat.Alignment = 'Center'
        $numberFormat.LineAlignment = 'Center'
        Draw-LDLCTextWithShadow -Graphics $Graphics -Text ([string]($i + 1)) -Font $fontNumber -Brush $titleBrush -Bounds $circleBounds -Format $numberFormat -ShadowAlpha 155
        $titleHeight = [Math]::Ceiling($fontTitle.GetHeight($Graphics)) + 1
        $detailHeight = [Math]::Ceiling($fontDetail.GetHeight($Graphics)) + 1
        $textTop = $bounds.Top + [Math]::Max(0, ($bounds.Height - $titleHeight - $detailHeight) / 2)
        $titleRect = New-Object System.Drawing.RectangleF((Convert-X 152), $textTop, (Convert-X 300), $titleHeight)
        $detailRect = New-Object System.Drawing.RectangleF((Convert-X 152), $titleRect.Bottom, (Convert-X 300), $detailHeight)
        Draw-LDLCTextWithShadow -Graphics $Graphics -Text $script:phases[$i].Name -Font $fontTitle -Brush $titleBrush -Bounds $titleRect -Format $textFormat
        Draw-LDLCTextWithShadow -Graphics $Graphics -Text $script:phases[$i].Detail -Font $fontDetail -Brush $detailBrush -Bounds $detailRect -Format $textFormat

        $numberFormat.Dispose()
        $numberFill.Dispose()
        $numberPen.Dispose()
        $titleBrush.Dispose()
        $detailBrush.Dispose()
    }

    $fontTitle.Dispose()
    $fontDetail.Dispose()
    $fontNumber.Dispose()
    $textFormat.Dispose()
}

function Draw-LDLCProgressArea {
    param([System.Drawing.Graphics]$Graphics)

    $statusFont = New-Object System.Drawing.Font('Segoe UI', (Convert-FontSize 27 8), [System.Drawing.FontStyle]::Bold)
    $detailFont = New-Object System.Drawing.Font('Segoe UI', (Convert-FontSize 18 8.5), [System.Drawing.FontStyle]::Regular)
    $percentFont = New-Object System.Drawing.Font('Segoe UI', (Convert-FontSize 34 10), [System.Drawing.FontStyle]::Bold)
    $metaFont = New-Object System.Drawing.Font('Segoe UI', (Convert-FontSize 14 7.5), [System.Drawing.FontStyle]::Regular)
    $textFormat = New-Object System.Drawing.StringFormat
    $textFormat.Trimming = [System.Drawing.StringTrimming]::EllipsisCharacter
    $textFormat.FormatFlags = [System.Drawing.StringFormatFlags]::NoWrap

    $whiteBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $blueTextBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 105, 205, 255))
    $softBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(235, 205, 228, 255))

    $status = Limit-LDLCText -Text (Get-LDLCStatusTitle -Percent ([int]$script:percent)) -MaxLength 48
    $detail = Limit-LDLCText -Text $script:message -MaxLength 82
    $meta = if ($Preview) { 'MODE PREVISUALISATION - aucune installation lancee' } else { 'Progression en temps reel' }

    $statusRect = New-Object System.Drawing.RectangleF((Convert-X 548), (Convert-Y 552), (Convert-X 790), (Convert-Y 50))
    # Minimum font sizes stay readable even when the entire window is scaled
    # down. Reserve their real pixel height instead of scaling the text box
    # below the font height (notably on the small GitHub runner desktop).
    $detailHeight = [Math]::Max((Convert-Y 32), [Math]::Ceiling($detailFont.GetHeight($Graphics)) + 2)
    $metaHeight = [Math]::Max((Convert-Y 26), [Math]::Ceiling($metaFont.GetHeight($Graphics)) + 2)
    $detailRect = New-Object System.Drawing.RectangleF((Convert-X 548), (Convert-Y 648), (Convert-X 805), $detailHeight)
    $metaTop = [Math]::Max((Convert-Y 684), $detailRect.Bottom + 1)
    $metaRect = New-Object System.Drawing.RectangleF((Convert-X 548), $metaTop, (Convert-X 805), $metaHeight)
    $barBounds = New-Object System.Drawing.RectangleF((Convert-X 548), (Convert-Y 608), (Convert-X 832), (Convert-Y 35))
    $percentRect = New-Object System.Drawing.RectangleF((Convert-X 1410), (Convert-Y 584), (Convert-X 135), (Convert-Y 70))

    # Reserve the footer first. Move the progress content up as one block when
    # minimum font heights need more room than the scaled background provides.
    $footerTop = (Convert-Y 772) - [Math]::Max(26, (Convert-Y 50))
    if ($script:LDLCQuitButton -and -not $script:LDLCQuitButton.IsDisposed) {
        $footerTop = $script:LDLCQuitButton.Top - [Math]::Max(3, (Convert-Y 6))
    }
    $panelBottom = [Math]::Min((Convert-Y 720), $footerTop - [Math]::Max(2, (Convert-Y 6)))
    $contentPadding = [Math]::Max(4, (Convert-Y 12))
    $shiftUp = [Math]::Max(0, $metaRect.Bottom + $contentPadding - $panelBottom)
    $statusRect.Y -= $shiftUp
    $detailRect.Y -= $shiftUp
    $metaRect.Y -= $shiftUp
    $barBounds.Y -= $shiftUp
    $percentRect.Y -= $shiftUp
    $panelTop = [Math]::Min((Convert-Y 485), $statusRect.Top - $contentPadding)
    $panelBounds = New-Object System.Drawing.RectangleF((Convert-X 540), $panelTop, (Convert-X 1110), ($panelBottom - $panelTop))
    $workspaceBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 2, 18, 45))
    $panelBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 3, 17, 42))
    $panelBorder = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 24, 75, 139), 1)
    $clearTop = [Math]::Min((Convert-Y 485), $panelTop) - 2
    $clearBounds = New-Object System.Drawing.RectangleF(($panelBounds.Left - 2), $clearTop, ($panelBounds.Width + 4), ((Convert-Y 766) - $clearTop))
    $Graphics.FillRectangle($workspaceBrush, $clearBounds)
    $panelPath = New-RoundedRectanglePath -Bounds $panelBounds -Radius ([Math]::Max(5, (Convert-X 32)))
    $Graphics.FillPath($panelBrush, $panelPath)
    $Graphics.DrawPath($panelBorder, $panelPath)
    $panelPath.Dispose(); $panelBorder.Dispose(); $panelBrush.Dispose(); $workspaceBrush.Dispose()
    if ($script:LDLCUiOverlay -and -not $script:LDLCUiOverlay.IsDisposed) {
        $script:LDLCUiOverlay.Tag = @{Panel=$panelBounds;Status=$statusRect;Bar=$barBounds;Detail=$detailRect;Meta=$metaRect;Percent=$percentRect;FooterTop=$footerTop}
    }
    Draw-LDLCTextWithShadow -Graphics $Graphics -Text $status -Font $statusFont -Brush $whiteBrush -Bounds $statusRect -Format $textFormat -ShadowAlpha 210
    Draw-LDLCTextWithShadow -Graphics $Graphics -Text $detail -Font $detailFont -Brush $blueTextBrush -Bounds $detailRect -Format $textFormat -ShadowAlpha 190
    Draw-LDLCTextWithShadow -Graphics $Graphics -Text $meta -Font $metaFont -Brush $softBrush -Bounds $metaRect -Format $textFormat -ShadowAlpha 180

    $barPath = New-RoundedRectanglePath -Bounds $barBounds -Radius (Convert-X 18)
    $barBack = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(210, 2, 28, 72))
    $barPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 20, 145, 255), (Convert-X 1))
    $Graphics.FillPath($barBack, $barPath)

    $fillBrush = $null
    $fillPath = $null
    if ($script:percent -gt 0) {
        $innerBarBounds = New-Object System.Drawing.RectangleF(
            ($barBounds.X + (Convert-X 1)),
            ($barBounds.Y + (Convert-Y 1)),
            ($barBounds.Width - (Convert-X 2)),
            ($barBounds.Height - (Convert-Y 2))
        )
        $fillWidth = [Math]::Min($innerBarBounds.Width, [Math]::Max((Convert-X 6), [single]($innerBarBounds.Width * ($script:percent / 100))))
        $fillBounds = New-Object System.Drawing.RectangleF($innerBarBounds.X, $innerBarBounds.Y, $fillWidth, $innerBarBounds.Height)
        $fillPath = New-RoundedRectanglePath -Bounds $fillBounds -Radius ($innerBarBounds.Height / 2)
        $fillBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($innerBarBounds, [System.Drawing.Color]::FromArgb(255, 0, 182, 255), [System.Drawing.Color]::FromArgb(255, 0, 89, 255), 0)
        $Graphics.FillPath($fillBrush, $fillPath)
    }

    $Graphics.DrawPath($barPen, $barPath)

    $percentText = "$([int]$script:percent)%"
    Draw-LDLCTextWithShadow -Graphics $Graphics -Text $percentText -Font $percentFont -Brush $whiteBrush -Bounds $percentRect -ShadowAlpha 210

    if ($fillBrush) { $fillBrush.Dispose() }
    if ($fillPath) { $fillPath.Dispose() }
    $barPen.Dispose()
    $barBack.Dispose()
    $barPath.Dispose()
    $whiteBrush.Dispose()
    $blueTextBrush.Dispose()
    $softBrush.Dispose()
    $statusFont.Dispose()
    $detailFont.Dispose()
    $percentFont.Dispose()
    $metaFont.Dispose()
    $textFormat.Dispose()
}

function Draw-LDLCVersionOverlay {
    param([System.Drawing.Graphics]$Graphics)

    $versionFont = New-Object System.Drawing.Font('Segoe UI', (Convert-FontSize 12 7), [System.Drawing.FontStyle]::Regular)
    $format = New-Object System.Drawing.StringFormat
    $format.Alignment = 'Center'
    $format.LineAlignment = 'Center'
    $format.Trimming = [System.Drawing.StringTrimming]::EllipsisCharacter
    $format.FormatFlags = [System.Drawing.StringFormatFlags]::NoWrap

    $versionBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(240, 215, 235, 255))
    $versionText = New-Object System.Drawing.RectangleF((Convert-X 58), (Convert-Y 720), (Convert-X 235), (Convert-Y 28))

    Draw-LDLCTextWithShadow -Graphics $Graphics -Text $script:LDLCAppVersionLabel -Font $versionFont -Brush $versionBrush -Bounds $versionText -Format $format -ShadowAlpha 180

    $versionFont.Dispose()
    $format.Dispose()
    $versionBrush.Dispose()
}

try {
    Remove-Item $script:progressFile -ErrorAction SilentlyContinue
    if (-not $Preview) {
        Remove-Item $script:stopFile -Force -ErrorAction SilentlyContinue
    }

    $bgOriginal = [System.Drawing.Image]::FromFile($bgPath)
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $maxWidth = [int]($screen.Width * 0.47)
    $maxHeight = [int]($screen.Height * 0.47)
    $scale = [Math]::Min($maxWidth / $bgOriginal.Width, $maxHeight / $bgOriginal.Height)
    if ($scale -gt 1) { $scale = 1 }

    $displayWidth = [int]($bgOriginal.Width * $scale)
    $displayHeight = [int]($bgOriginal.Height * $scale)
    $script:scaleX = $displayWidth / $bgOriginal.Width
    $script:scaleY = $displayHeight / $bgOriginal.Height

    $transparentKey = [System.Drawing.Color]::FromArgb(17, 18, 19)
    $bg = Resize-LDLCBackgroundBitmap -Image $bgOriginal -Width $displayWidth -Height $displayHeight
    Apply-LDLCBitmapRoundedWindowMask -Bitmap $bg -Radius (Convert-X 72) -TransparentColor $transparentKey
    Remove-LDLCBitmapAlphaFringe -Bitmap $bg -AlphaCutoff 254 -TransparentColor $transparentKey

    $form = New-Object System.Windows.Forms.Form
    $form.Text = if ($Preview) { 'LDLC UI Preview' } else { 'LDLC Preparation PC' }
    $form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
    $form.FormBorderStyle = 'None'
    $form.StartPosition = 'Manual'
    $form.TopMost = $true
    $form.ShowInTaskbar = $true
    $form.Padding = New-Object System.Windows.Forms.Padding 0
    $form.Margin = New-Object System.Windows.Forms.Padding 0
    $form.ClientSize = New-Object System.Drawing.Size $displayWidth, $displayHeight
    $form.Left = $screen.Left + 20
    $form.Top = [Math]::Max($screen.Top, ($screen.Bottom - $form.Height - 20))
    $form.BackColor = $transparentKey
    $form.TransparencyKey = $transparentKey
    $form.KeyPreview = $true
    $form.Cursor = 'AppStarting'
    $form.Region = New-LDLCBitmapAlphaRegion -Bitmap $bg -AlphaThreshold 254
    if (-not $form.Region) {
        $form.Region = New-LDLCRoundedWindowRegion -Width $displayWidth -Height $displayHeight
    }

    $picture = New-Object System.Windows.Forms.PictureBox
    $picture.Image = $bg
    $picture.Dock = 'Fill'
    $picture.SizeMode = 'StretchImage'
    $picture.BackColor = $transparentKey
    $picture.Margin = New-Object System.Windows.Forms.Padding 0
    $picture.Padding = New-Object System.Windows.Forms.Padding 0
    $form.Controls.Add($picture)

    $overlay = New-Object System.Windows.Forms.Panel
    $overlay.Dock = 'Fill'
    $overlay.BackColor = [System.Drawing.Color]::Transparent
    $overlay.Margin = New-Object System.Windows.Forms.Padding 0
    $overlay.Padding = New-Object System.Windows.Forms.Padding 0
    $doubleBufferedProperty = $overlay.GetType().GetProperty(
        'DoubleBuffered',
        [System.Reflection.BindingFlags]'NonPublic, Instance'
    )
    if ($doubleBufferedProperty) {
        $doubleBufferedProperty.SetValue($overlay, $true, $null)
    }
    $picture.Controls.Add($overlay)

    $closeButton = New-Object System.Windows.Forms.Button
    $closeButton.Name = 'QuitButton'
    $closeButton.Text = 'Quitter'
    # Let native Button layout include its text inset and the current Windows DPI.
    $closeButton.AutoSize = $true
    $closeButton.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
    $closeButton.MinimumSize = New-Object System.Drawing.Size([Math]::Max(50, (Convert-X 174)), [Math]::Max(18, (Convert-Y 34)))
    $closeButton.Padding = New-Object System.Windows.Forms.Padding(4, 0, 4, 0)
    $closeButton.Margin = New-Object System.Windows.Forms.Padding 0
    $closeButton.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $closeButton.UseCompatibleTextRendering = $false
    $closeButton.FlatStyle = 'Flat'
    $closeButton.FlatAppearance.BorderSize = 0
    $closeButton.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(245, 55, 55)
    $closeButton.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(170, 20, 20)
    $closeButton.BackColor = [System.Drawing.Color]::FromArgb(215, 35, 35)
    $closeButton.ForeColor = 'White'
    $closeButton.Font = New-Object System.Drawing.Font('Segoe UI', (Convert-FontSize 17 7.5), [System.Drawing.FontStyle]::Bold)
    $closeButton.Cursor = 'Hand'
    $closeButton.TabStop = $false
    $overlay.Controls.Add($closeButton)
    $closeButton.Size = $closeButton.GetPreferredSize([System.Drawing.Size]::Empty)
    $closeButton.Left = [Math]::Min((Convert-X 1450), ($displayWidth - $closeButton.Width - [Math]::Max(12, (Convert-X 48))))
    $closeButton.Top = $displayHeight - $closeButton.Height - [Math]::Max(3, (Convert-Y 6))
    $closeButton.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right
    $script:LDLCQuitButton = $closeButton
    $script:LDLCUiOverlay = $overlay

    $script:closeMouseArmedUntil = [datetime]::MinValue
    $script:allowFormClose = [bool]$Preview
    $closeButton.Add_MouseDown({
        if ($_.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
            $script:closeMouseArmedUntil = (Get-Date).AddMilliseconds(750)
        }
    })
    $closeButton.Add_KeyDown({
        if ($_.KeyCode -eq 'Enter' -or $_.KeyCode -eq 'Space') {
            $_.Handled = $true
            $_.SuppressKeyPress = $true
        }
    })
    $closeButton.Add_KeyUp({
        if ($_.KeyCode -eq 'Enter' -or $_.KeyCode -eq 'Space') {
            $_.Handled = $true
            $_.SuppressKeyPress = $true
        }
    })
    $closeButton.Add_MouseEnter({ $closeButton.BackColor = [System.Drawing.Color]::FromArgb(245, 55, 55) })
    $closeButton.Add_MouseLeave({ $closeButton.BackColor = [System.Drawing.Color]::FromArgb(215, 35, 35) })

    # Launch only after the first overlay paint has returned to the message loop.
    $workerStartTimer = New-Object System.Windows.Forms.Timer
    $workerStartTimer.Interval = 1
    $workerStartTimer.Add_Tick({
        $workerStartTimer.Stop()
        if ($script:workerLaunchAttempted -or $Preview -or $script:closing -or $form.IsDisposed -or $form.Disposing) {
            return
        }
        $script:workerLaunchAttempted = $true

        if (-not $Preview) {
            $previousCompactUi = $env:LDLC_DEFAULT_APPS_UI
            try {
                $env:LDLC_DEFAULT_APPS_UI = '1'
                if ($WorkerLauncher) {
                    $script:proc = & $WorkerLauncher
                }
                elseif (Get-Command Start-LDLCInstance -ErrorAction SilentlyContinue) {
                    $script:proc = Start-LDLCInstance -Arguments @('-InstallWorker')
                }
                else {
                    throw 'Lanceur interne indisponible.'
                }
            }
            catch {
                $script:proc = $null
                $script:message = 'Demarrage bloque. Consulte le message de securite et LDLC_BOOTSTRAP.log.'
                $script:percent = 0
            }
            finally {
                if ($null -eq $previousCompactUi) { Remove-Item Env:\LDLC_DEFAULT_APPS_UI -ErrorAction SilentlyContinue }
                else { $env:LDLC_DEFAULT_APPS_UI = $previousCompactUi }
            }
        }
    })

    $overlay.Add_Paint({
        param($sender, $eventArgs)

        $graphics = $eventArgs.Graphics
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit

        $activeIndex = Get-LDLCPhaseIndex -Percent ([int]$script:percent)
        Draw-LDLCVersionOverlay -Graphics $graphics
        Draw-LDLCStageList -Graphics $graphics -ActiveIndex $activeIndex
        Draw-LDLCProgressArea -Graphics $graphics

        if (-not $script:uiFirstPaintCompleted) {
            $script:uiFirstPaintCompleted = $true
            if (-not $Preview -and -not $script:closing) {
                $workerStartTimer.Start()
            }
        }
    })

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 250
    $timer.Add_Tick({
        $previousDisplay = "$($script:percent)|$($script:message)"
        if ($Preview) {
            Update-LDLCPreviewProgress
        }
        else {
            Read-LDLCProgressFile
            try { Update-LDLCCompactUi -MainForm $form -RuntimeRoot $script:runtimeRoot -Worker $script:proc }
            catch {
                Set-LDLCCompactUiState -MainForm $form -Active $false
                $script:message = 'Mode compact indisponible. Configuration des applications par defaut en cours.'
            }

            if ($script:proc -and $script:proc.HasExited) {
                $form.Cursor = 'Default'
                if ($script:percent -lt 100 -and -not $script:closing) {
                    $script:message = 'Script termine avant 100%. Consulte la console ou les logs.'
                }
            }
        }

        if ($script:closing) {
            if (Test-LDLCUiFinalizationReady) {
                $script:allowFormClose = $true
                $form.Close()
                return
            }
            $script:closeStep++

            if ($Preview) {
                $script:allowFormClose = $true
                $form.Close()
                return
            }

            if (-not $script:stopFileCreated) {
                try {
                    New-Item $script:stopFile -ItemType File -Force | Out-Null
                }
                catch {}

                $script:stopFileCreated = $true
                $script:message = 'Arret demande, attente de fermeture propre...'
            }

            if (-not $script:proc -or $script:proc.HasExited) {
                $script:message = 'Installation arretee proprement.'
                $script:allowFormClose = $true
                $form.Close()
                return
            }

            $elapsedSeconds = 0
            if ($script:closeRequestedAt) {
                $elapsedSeconds = ((Get-Date) - $script:closeRequestedAt).TotalSeconds
            }

            if ($elapsedSeconds -ge $script:gracefulStopTimeoutSeconds -and -not $script:forceStopDone) {
                $script:message = 'Arret force du processus bloque...'
                Stop-LDLCProcessTree -ProcessId $script:proc.Id
                $script:forceStopDone = $true
            }

            if ($script:forceStopDone -and ($elapsedSeconds -ge $script:closeAfterForceSeconds)) {
                $script:allowFormClose = $true
                $form.Close()
                return
            }
        }

        if (-not $script:LDLCCompactUiState -and $previousDisplay -ne "$($script:percent)|$($script:message)") {
            $overlay.Invalidate()
        }
    })

    $closeButton.Add_Click({
        if ((Get-Date) -gt $script:closeMouseArmedUntil) {
            return
        }
        $script:closeMouseArmedUntil = [datetime]::MinValue

        if ($Preview) {
            $script:allowFormClose = $true
            $form.Close()
            return
        }

        if ($script:closing) { return }
        if (Test-LDLCUiFinalizationReady) {
            $script:allowFormClose = $true
            $form.Close()
            return
        }
        $script:closing = $true
        $script:closeStep = 0
        $script:closeRequestedAt = Get-Date
        $script:stopFileCreated = $false
        $script:forceStopDone = $false
        $closeButton.Enabled = $false
        $closeButton.Text = 'Fermeture...'
        $form.Cursor = 'WaitCursor'
        try {
            New-Item $script:stopFile -ItemType File -Force | Out-Null
            $script:stopFileCreated = $true
            $script:message = 'Arret demande, fermeture en cours...'
        }
        catch {
            $script:message = 'Fermeture demandee, nouvelle tentative...'
        }
    })

    $form.Add_KeyDown({
        if (-not $Preview) {
            if (
                ($_.Alt -and $_.KeyCode -eq 'F4') -or
                $_.KeyCode -eq 'Enter' -or
                $_.KeyCode -eq 'Space' -or
                $_.KeyCode -eq 'Escape'
            ) {
                $_.Handled = $true
                $_.SuppressKeyPress = $true
                return
            }
        }

        if ($_.KeyCode -eq 'Escape') {
            if ($Preview) {
                $script:allowFormClose = $true
                $form.Close()
            }
        }
    })

    $form.Add_FormClosing({
        if (-not $Preview -and -not $script:allowFormClose) {
            if (Test-LDLCUiFinalizationReady) { return }
            if ($script:proc -and $script:proc.HasExited) {
                return
            }

            $_.Cancel = $true
            $script:message = 'Fermeture clavier ignoree pendant la preparation.'
            $overlay.Invalidate()
        }
    })

    $form.Add_Shown({ $timer.Start() })
    [System.Windows.Forms.Application]::Run($form)
}
finally {
    if ($form -and $script:LDLCCompactUiState) { Set-LDLCCompactUiState -MainForm $form -Active $false }
    if ($timer) { $timer.Stop(); $timer.Dispose() }
    if ($workerStartTimer) { $workerStartTimer.Stop(); $workerStartTimer.Dispose() }
    if ($bgOriginal) { $bgOriginal.Dispose() }
    if ($bg) { $bg.Dispose() }
    if ($mutex) { $mutex.ReleaseMutex() | Out-Null }
}

# endregion UI
