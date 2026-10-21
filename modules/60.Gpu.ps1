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

