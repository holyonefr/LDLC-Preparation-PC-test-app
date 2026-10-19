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
    $defaultTimeout = 0

    if (-not [string]::IsNullOrWhiteSpace($env:LDLC_WU_TIMEOUT_SECONDS)) {
        try {
            return [math]::Min(86400, [math]::Max(0, [int]$env:LDLC_WU_TIMEOUT_SECONDS))
        }
        catch {}
    }

    return $defaultTimeout
}

function Get-LDLCWindowsUpdateFinalWaitSeconds {
    $defaultTimeout = 14400

    if (-not [string]::IsNullOrWhiteSpace($env:LDLC_WU_FINAL_WAIT_SECONDS)) {
        try {
            return [math]::Min(28800, [math]::Max(60, [int]$env:LDLC_WU_FINAL_WAIT_SECONDS))
        }
        catch {}
    }

    return $defaultTimeout
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
        if (Get-Command Update-LDLCTelemetryRun -ErrorAction SilentlyContinue) {
            Update-LDLCTelemetryRun -Status 'En cours' -Step 'Windows Update' -Message 'Windows Update demarre en arriere-plan pendant la preparation.' -ProgressPercent $StartPercent -Force
        }

        $launch = Start-LDLCWindowsUpdateWorker -StartPercent $StartPercent -EndPercent $EndPercent
        if ($launch -and $launch.Success) {
            Write-ProgressFile $EndPercent 'Windows Update tourne en arriere-plan pendant la preparation.'
            return [pscustomobject]@{
                Started = $true
                ProcessId = [int]$launch.ProcessId
                ResultPath = [string]$launch.ResultPath
                ProgressPath = [string]$launch.ProgressPath
                Error = ''
            }
        }

        $errorText = if ($launch) { [string]$launch.Error } else { 'Worker Windows Update non retourne' }
        Write-Warn "Windows Update non lance en arriere-plan : $errorText"
        return [pscustomobject]@{
            Started = $false
            ProcessId = 0
            ResultPath = if ($launch) { [string]$launch.ResultPath } else { '' }
            ProgressPath = if ($launch) { [string]$launch.ProgressPath } else { '' }
            Error = $errorText
        }
    }
    catch {
        if (Test-LDLCStopRequestError $_) { throw }

        $message = "Lancement Windows Update en arriere-plan impossible : $($_.Exception.Message)"
        Write-Warn $message
        if (Get-Command Add-LDLCTelemetryEvent -ErrorAction SilentlyContinue) {
            Add-LDLCTelemetryEvent -Message $message -Severity warning -Type 'Windows Update' -Status 'avertissement'
        }

        Write-ProgressFile $EndPercent "Windows Update non lance, preparation continue."
        return [pscustomobject]@{
            Started = $false
            ProcessId = 0
            ResultPath = ''
            ProgressPath = ''
            Error = $_.Exception.Message
        }
    }
}

function Wait-LDLCWindowsUpdateWorkerCompletion {
    param(
        $Worker,
        [int]$ProgressPercent = 94,
        [int]$TimeoutSeconds = (Get-LDLCWindowsUpdateFinalWaitSeconds)
    )

    if (-not $Worker -or -not $Worker.Started) {
        $errorText = if ($Worker) { [string]$Worker.Error } else { 'Windows Update non demarre' }
        return New-LDLCWindowsUpdateWorkflowResult -Success $false -Skipped $false -LastError $errorText
    }

    $deadline = (Get-Date).AddSeconds([math]::Max(60, $TimeoutSeconds))
    $lastDisplayedMessage = ''
    $missingResultNoticeWritten = $false

    Write-Step "Windows Update : attente finale du worker pour terminer les cycles jusqu'a absence de mises a jour."
    Write-ProgressFile $ProgressPercent 'Windows Update encore en cours... Ne pas eteindre le PC.'

    while ($true) {
        Stop-IfRequested

        if (-not [string]::IsNullOrWhiteSpace([string]$Worker.ResultPath) -and
            (Test-Path -LiteralPath ([string]$Worker.ResultPath) -PathType Leaf)) {
            try {
                $payload = Get-Content -LiteralPath ([string]$Worker.ResultPath) -Raw -Encoding UTF8 | ConvertFrom-Json
                $result = Convert-LDLCWindowsUpdateWorkerPayload -Payload $payload
                Write-Step "Windows Update : resultat worker recupere (cycles=$($result.CycleCount), restantes=$($result.RemainingCount), reboot=$($result.RebootRequired))."
                return $result
            }
            catch {
                if (-not $missingResultNoticeWritten) {
                    Write-Step "Windows Update : resultat worker pas encore lisible, attente courte."
                    $missingResultNoticeWritten = $true
                }
            }
        }

        $isRunning = $false
        if ([int]$Worker.ProcessId -gt 0) {
            try {
                $process = Get-Process -Id ([int]$Worker.ProcessId) -ErrorAction Stop
                $isRunning = (-not $process.HasExited)
            }
            catch {
                $isRunning = $false
            }
        }

        if (-not $isRunning) {
            $message = 'Worker Windows Update termine sans resultat lisible.'
            Write-Warn $message
            return New-LDLCWindowsUpdateWorkflowResult -Success $false -Skipped $false -LastError $message
        }

        if ((Get-Date) -ge $deadline) {
            $message = "Windows Update encore en cours apres ${TimeoutSeconds}s d'attente finale."
            Write-Err $message
            try { Stop-Process -Id ([int]$Worker.ProcessId) -Force -ErrorAction SilentlyContinue } catch {}
            return New-LDLCWindowsUpdateWorkflowResult -Success $false -TimedOut $true -Skipped $false -LastError $message
        }

        $progress = Read-LDLCWindowsUpdateWorkerProgress -ProgressPath ([string]$Worker.ProgressPath)
        if ($progress -and -not [string]::IsNullOrWhiteSpace([string]$progress.Message) -and $progress.Message -ne $lastDisplayedMessage) {
            $lastDisplayedMessage = [string]$progress.Message
            Write-ProgressFile $ProgressPercent $lastDisplayedMessage
        }

        Start-Sleep -Seconds 2
    }
}

function Invoke-LDLCSecurityCleanupIsolated {
    param(
        [int]$StartPercent = 1,
        [int]$EndPercent = 3,
        [int]$TimeoutSeconds = 90
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
    $process = $null

    try {
        $env:LDLC_SECURITY_RESULT_PATH = $resultPath
        $psExe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        Write-Step "McAfee/Norton : lancement isole avec limite globale de ${TimeoutSeconds}s."
        $process = Start-Process `
            -FilePath $psExe `
            -ArgumentList @('-ExecutionPolicy', 'Bypass', '-NoProfile', '-File', $workerScript, '-SecurityCleanupWorker') `
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
    }
}

function Invoke-LDLCPreparation {
    $script:LDLCWorkflowStatus = 'running'
    $wuWorker = $null
    $wuResult = New-LDLCWindowsUpdateWorkflowResult -Success $true -Skipped $true

    try {
        Clear-Host
        Write-Section "PREPARATION DU POSTE"

        Stop-IfRequested
        Write-ProgressFile 1 "Detection de McAfee et Norton..."
        [void](Invoke-LDLCSecurityCleanupIsolated -StartPercent 1 -EndPercent 3 -TimeoutSeconds 90)

        Stop-IfRequested
        Write-ProgressFile 4 "Creation du point de restauration avant Windows Update..."
        [void](Invoke-LDLCRestorePointCreation -ProgressPercent 4)

        Stop-IfRequested
        Write-ProgressFile 5 "Demarrage de Windows Update en arriere-plan..."
        $wuWorker = Start-LDLCWindowsUpdatesDuringPreparation -StartPercent 5 -EndPercent 7

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

        Stop-IfRequested
        Write-ProgressFile 80 "Configuration du bureau..."
        Write-Step "Configuration des icones systeme du bureau reportee en fin de script pour conserver l'ordre des icones."

        Stop-IfRequested
        Write-ProgressFile 87 "Configuration des applications par défaut avant les pilotes GPU..."

        try {
            Invoke-LDLCChromeDefaultAppsSequence
            Write-Step "Courte stabilisation apres les applications par defaut..."
            Start-Sleep -Milliseconds 1200
        }
        catch {
            if (Test-LDLCStopRequestError $_) { throw }
            Write-Warn "Etape applications par defaut ignoree suite a une erreur : $($_.Exception.Message)"
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

        Stop-IfRequested
        Write-ProgressFile 94 "Finalisation Windows Update..."
        $wuResult = Wait-LDLCWindowsUpdateWorkerCompletion -Worker $wuWorker -ProgressPercent 94
        if ($wuResult -and $wuResult.RebootRequired) {
            Write-Warn "Windows Update demande un redemarrage pour continuer les mises a jour. Aucun redemarrage automatique : la preparation continue."
        }
        elseif ($wuResult -and $wuResult.TimedOut) {
            Write-Err "Windows Update incomplet : limite de cycles ou d'attente finale atteinte."
        }
        elseif ($wuResult -and -not $wuResult.Success) {
            Write-Warn "Windows Update non termine. La preparation continue avec l'information dans les logs."
        }
        elseif ($wuResult -and $wuResult.Completed) {
            Write-Ok "Windows Update termine : aucune mise a jour restante."
        }

        if ($wuResult -and ($wuResult.TimedOut -or (-not $wuResult.Success -and -not $wuResult.RebootRequired))) {
            $wuDetails = @(
                "Cycles: $($wuResult.CycleCount)/$($wuResult.MaxCycles)",
                "Detectees: $($wuResult.DetectedCount)",
                "Installees: $($wuResult.Count)",
                "Restantes: $($wuResult.RemainingCount)",
                "UsoFallback: $($wuResult.UsoFallbackUsed)",
                "Derniere erreur: $($wuResult.LastError)"
            ) -join [Environment]::NewLine

            if (Get-Command Add-LDLCTelemetryEvent -ErrorAction SilentlyContinue) {
                Add-LDLCTelemetryEvent `
                    -Message "Windows Update n'a pas pu aller jusqu'a l'absence totale de mises a jour." `
                    -Severity error `
                    -Type 'Windows Update' `
                    -Status 'critique' `
                    -Details $wuDetails
            }
        }

        Restore-PowerSettings -ProgressPercent 97 -IgnoreStopRequest | Out-Null

        Stop-IfRequested
        Write-Section "FIN DU SCRIPT"

        $rebootRequired = (($wuResult -and $wuResult.RebootRequired) -or $script:PendingReboot)

        if ($rebootRequired) {
            Write-ProgressFile 100 "Préparation terminée - redémarrage requis."
            Write-Warn "Preparation terminee. Un redemarrage est requis."
        }
        else {
            Write-ProgressFile 100 "Préparation terminée, tu peux quitter !"
            Write-Ok "Preparation terminee."
        }
        if ($wuResult -and $wuResult.TimedOut -and $wuResult.BackgroundFallbackStarted) {
            $script:LDLCWorkflowStatus = 'warning'
        }
        elseif ($wuResult -and $wuResult.TimedOut) {
            $script:LDLCWorkflowStatus = 'timeout'
        }
        elseif ($wuResult -and -not $wuResult.Success) {
            $script:LDLCWorkflowStatus = 'warning'
        }
        else {
            $script:LDLCWorkflowStatus = 'success'
        }
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
            Complete-LDLCTelemetryRun -ResultStatus $script:LDLCWorkflowStatus
        }
    }
}

# endregion Module: 90.Workflow.ps1
