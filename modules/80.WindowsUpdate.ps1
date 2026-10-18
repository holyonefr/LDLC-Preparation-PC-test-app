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
