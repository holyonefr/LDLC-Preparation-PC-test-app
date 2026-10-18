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

function Resolve-LDLCAmdGpuOfficialSource {
    # GPU-131: Auto-Detect selects the latest compatible package for each GPU,
    # unlike a generic full RDNA package which may not support an older iGPU.
    $pageUrl = 'https://www.amd.com/en/support/download/drivers.html'
    $response = Invoke-WebRequest -Uri $pageUrl -Headers @{ 'Cache-Control' = 'no-cache'; Pragma = 'no-cache' } -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
    $html = [System.Net.WebUtility]::HtmlDecode([string]$response.Content)
    $sources = foreach ($match in [regex]::Matches($html, '(?i)href\s*=\s*["''](?<url>https://(?:drivers|download)\.amd\.com/[^"''<>\s]+)["'']')) {
        $uri = [uri]$match.Groups['url'].Value
        $fileName = [System.IO.Path]::GetFileName($uri.AbsolutePath)
        if ($uri.UserInfo -or $uri.Port -ne 443 -or $fileName -notmatch '(?i)^amd-software-adrenalin-edition-(?<version>\d+(?:\.\d+){1,3})-minimalsetup-[\w-]+_web\.exe$') {
            continue
        }
        [pscustomobject]@{
            Url = $uri.AbsoluteUri
            FileName = $fileName
            Version = $Matches['version']
            Provider = 'AMD officiel (Auto-Detect)'
            PageUrl = $pageUrl
        }
    }
    $latest = $sources | Sort-Object { [version]$_.Version } -Descending | Select-Object -First 1
    if (-not $latest) { throw 'Lien Auto-Detect Adrenalin actuel introuvable sur la page AMD officielle.' }
    return $latest
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
        $process.WaitForExit()
        if ($process.ExitCode -notin @(0, 3010, 1641)) { throw "Installation AMD en echec, code $($process.ExitCode)." }
        if ($process.ExitCode -in @(3010, 1641)) { $script:PendingReboot = $true }
        return [int]$process.ExitCode
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

function Install-LDLCAmdStack {
    param([int]$StartPercent = 84)

    Stop-IfRequested
    $amdAdapters = @(Get-LDLCGpuAdapters | Where-Object { (Get-LDLCGpuAdapterVendor -Adapter $_) -eq 'AMD' })
    if (-not $amdAdapters.Count) {
        Write-Step 'AMD non applicable : aucun adaptateur graphique AMD present.'
        return
    }
    $deviceIds = @($amdAdapters | ForEach-Object { [string]$_.PNPDeviceID } | Select-Object -Unique)
    Write-Step "GPU AMD detectes : $(($amdAdapters.Name) -join ', ')"
    Write-ProgressFile $StartPercent 'Recherche de AMD Software: Adrenalin Edition actuel'
    Write-Step 'Recherche et telechargement AMD systematiques, meme si un pilote ou Adrenalin est deja installe.'

    $downloadPath = $null
    try {
        $definition = Get-LDLCAmdAdrenalinInstallerDefinition
        $source = Resolve-LDLCAmdGpuOfficialSource
        Write-Step "Auto-Detect Adrenalin actuel : $($source.Version), source $($source.PageUrl)"
        Write-Step "Telechargement AMD officiel : $($source.Url)"
        # No unversioned/offline cache fallback: it cannot prove freshness.
        $downloadPath = Join-Path ([System.IO.Path]::GetTempPath()) ('LDLC-AMD-' + [guid]::NewGuid().ToString('N') + '.exe')
        Invoke-WebRequest -Uri $source.Url -Headers @{ Referer = $source.PageUrl; 'Cache-Control' = 'no-cache'; Pragma = 'no-cache' } -OutFile $downloadPath `
            -UseBasicParsing -TimeoutSec $definition.DownloadTimeoutSeconds -ErrorAction Stop | Out-Null
        if (-not (Test-LDLCAmdGpuInstallerFile -Path $downloadPath -MinBytes $definition.MinBytes)) {
            throw 'Installateur AMD refuse : taille, entetes MZ/PE ou signature AMD valide non confirmes.'
        }
        Write-Ok "Installateur AMD PE signe valide, $((Get-Item -LiteralPath $downloadPath).Length) octets."
        Write-ProgressFile $StartPercent 'Installation AMD et attente de tous ses sous-processus'
        $exitCode = Invoke-LDLCAmdGpuInstaller -Path $downloadPath -Installer $definition
        $deadline = (Get-Date).AddSeconds([int]$definition.ValidationTimeoutSeconds)
        do {
            Stop-IfRequested
            if (Get-Command Clear-LDLCDetectionCaches -ErrorAction SilentlyContinue) { Clear-LDLCDetectionCaches }
            $software = Get-LDLCAmdSoftwareInstallation -Refresh
            if ($software -and (Test-LDLCAmdGpuDriversReady -PnpDeviceIds $deviceIds)) {
                Write-Ok "AMD Adrenalin confirme apres fin de l'installation (code $exitCode), pilote signe et peripherique sain pour chaque GPU AMD."
                Ensure-LDLCGpuDesktopShortcut -Vendor 'AMD'
                return
            }
            if ((Get-Date) -ge $deadline) { break }
            Start-Sleep -Seconds 2
        } while ($true)
        if ($exitCode -in @(3010, 1641)) {
            Write-Warn 'AMD demande un redemarrage : pilote/application pas encore confirmes. Verification requise apres redemarrage; aucun succes declare.'
            return
        }
        throw "AMD non confirme : application Adrenalin et pilote DISPLAY AMD signe/sain requis pour chaque GPU. Code $exitCode."
    }
    catch {
        if (Test-LDLCStopRequestError -ErrorRecord $_) { throw }
        Write-Err "Installation AMD non confirmee : $($_.Exception.Message)"
    }
    finally {
        if ($downloadPath -and (Test-Path -LiteralPath $downloadPath)) {
            Remove-Item -LiteralPath $downloadPath -Force -ErrorAction SilentlyContinue
        }
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
        Write-Ok "GPU AMD detecte : installation driver"
        Install-LDLCAmdStack -StartPercent $ProgressPercent
    }
}

# endregion Module: 60.Gpu.ps1

