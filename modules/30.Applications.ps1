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

