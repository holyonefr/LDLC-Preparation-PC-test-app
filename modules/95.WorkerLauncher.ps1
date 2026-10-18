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
        $result = Remove-LDLCOemAndSecurityTrials -Mode Security -StartPercent 1 -EndPercent 3
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

