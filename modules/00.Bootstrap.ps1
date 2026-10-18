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

