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

