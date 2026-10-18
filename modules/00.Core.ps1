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

