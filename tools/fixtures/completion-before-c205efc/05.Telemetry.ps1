# region Module: 05.Telemetry.ps1
# Error telemetry and Google Sheets export.

# Fill these two values after deploying tools/google-apps-script/LDLC_ErrorTelemetry.gs.
# They are intentionally embedded so the compiled exe can report issues from any PC.
$script:LDLCTelemetryEndpointUrl = 'https://example.invalid/fixture'
$script:LDLCTelemetryApiKey = 'FIXTURE_DISABLED_KEY'
$script:LDLCTelemetryToolVersion = '2.6.4'
$script:LDLCTelemetrySource = 'LDLCPreparationPC'
$script:LDLCTelemetryApplicationSource = 'LDLC_PREPARATION_PC'
$script:LDLCTelemetryEdition = 'LDLC'
$script:LDLCTelemetrySendSuccessfulRuns = $true
$script:LDLCTelemetryUpdateIntervalSeconds = 60
$script:LDLCTelemetryRemoteWriteMode = 'live'
$script:LDLCTelemetryNetworkTimeoutSeconds = 20

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
        $key = if ($Final) { 'success' } else { 'running' }
    }

    $errorCount = if ($Counts) { [int]$Counts.ErrorCount + [int]$Counts.CriticalCount } else { 0 }
    $warningCount = if ($Counts) { [int]$Counts.WarningCount } else { 0 }

    if ($Final) {
        if ($key -match '^(stopped|stop|interrompu|interruption|cancelled|canceled|annule|annulé|annulee|annulée)$') {
            return 'stopped'
        }

        if ($errorCount -gt 0 -or $key -match '^(failed|fail|failure|echec|échec|error|erreur|critical|critique)$') {
            return 'failed'
        }

        if ($warningCount -gt 0 -or $key -match '^(warning|warn|avertissement|partial|partiel|partielle)$') {
            return 'warning'
        }

        if ($key -match '(timeout|bloque|bloqué|blocked|delai|délai|watchdog)') {
            return 'timeout'
        }

        return 'success'
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
        return [math]::Min(20, [math]::Max(2, [int]$value))
    }
    catch {
        return 5
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

function Initialize-LDLCTelemetry {
    if ($script:LDLCTelemetryInitialized) {
        return
    }

    if (Test-LDLCTelemetryDisabled) {
        $script:LDLCTelemetryInitialized = $true
        $script:LDLCTelemetryDisabled = $true
        return
    }

    $script:LDLCTelemetryInitialized = $true
    $script:LDLCTelemetryRunId = if (-not [string]::IsNullOrWhiteSpace($env:LDLC_TELEMETRY_RUN_ID)) {
        ConvertTo-LDLCTelemetryText $env:LDLC_TELEMETRY_RUN_ID 80
    }
    else {
        [guid]::NewGuid().ToString('N')
    }
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
        if (Test-Path -LiteralPath $path) {
            $json = ConvertTo-Json -InputObject $payload -Depth 14 -Compress
            # Ne pas effacer une mise a jour plus recente que celle acquittee.
            if ([IO.File]::ReadAllText($path).Trim() -eq $json) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
        }
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

    try {
        $script:LDLCTelemetrySending = $true
        Send-LDLCTelemetryPayloads -Payloads $payloads
        Clear-LDLCQueuedTelemetryPayloads -AcknowledgedPayloads $payloads
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
    $script:LDLCTelemetryRemoteRequestCount++
    $response = Invoke-RestMethod `
        -Uri $endpointUrl `
        -Method Post `
        -ContentType 'application/json; charset=utf-8' `
        -Body $body `
        -TimeoutSec (Get-LDLCTelemetryNetworkTimeoutSeconds)

    if (-not $response -or $response.ok -ne $true) {
        throw 'Google Apps Script n a pas acquitte la telemetrie.'
    }
}

function Complete-LDLCTelemetryRun {
    param([string]$ResultStatus = 'success')

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

    if (-not $script:LDLCTelemetrySendSuccessfulRuns -and $counts.EventCount -eq 0) {
        return
    }

    $script:LDLCTelemetryRunStatus = Convert-LDLCTelemetryRunStatus -Status $ResultStatus -Counts $counts -Final
    $displayStatus = Convert-LDLCTelemetryRunStatusDisplayText -Status $script:LDLCTelemetryRunStatus
    $script:LDLCTelemetryLastMessage = "Execution terminee : $displayStatus"
    if ($script:LDLCTelemetryProgressPercent -lt 100 -and $script:LDLCTelemetryRunStatus -in @('success', 'warning')) {
        $script:LDLCTelemetryProgressPercent = 100
    }

    $script:LDLCTelemetryLastUpdatedAt = Get-LDLCUtcTimestamp
    if ($script:LDLCTelemetryStopwatch) { $script:LDLCTelemetryStopwatch.Stop() }
    $payload = New-LDLCTelemetryPayload -ResultStatus $script:LDLCTelemetryRunStatus -Final
    $script:LDLCTelemetryCompleted = $true

    if (SendOrQueue-LDLCTelemetryPayload -Payload $payload) {
        Write-Host "[INFO] Telemetrie LDLC envoyee vers Google Sheets." -ForegroundColor DarkCyan
    }
    elseif ($script:LDLCTelemetryLastQueueSaved) {
        Write-Host "[INFO] Telemetrie LDLC non envoyee, sauvegardee pour un prochain essai." -ForegroundColor DarkCyan
    }
    else {
        Write-Host '[INFO] Telemetrie non envoyee et sauvegarde locale impossible; consulter le journal local.' -ForegroundColor Yellow
    }
}

# endregion Module: 05.Telemetry.ps1








