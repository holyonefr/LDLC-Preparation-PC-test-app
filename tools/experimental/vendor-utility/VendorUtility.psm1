#requires -Version 5.1
Set-StrictMode -Version 2
Import-Module (Join-Path $PSScriptRoot '../motherboard/MotherboardExperiment.psm1') -Force
. (Join-Path $PSScriptRoot 'VendorDiscovery.Gigabyte.ps1')
. (Join-Path $PSScriptRoot 'VendorDiscovery.Asrock.ps1')
. (Join-Path $PSScriptRoot 'VendorPackage.Gigabyte.ps1')
$script:UtilitySimulation=$false

function Get-VutProfile {
    param([string]$Vendor,[string]$BoardModel='',[string]$TargetOs='')
    $base=@(Get-MbxToolDefinitions | Where-Object Vendor -eq $Vendor)
    if ($base.Count -ne 1) { return $null }
    if ($Vendor -eq 'ASRock') { $base[0].Tool='ASRock APP Shop'; $base[0].FilePattern='(?i)^APPShop\(v[0-9]+(?:\.[0-9]+){1,3}\)\.zip$' }
    $names=@{ MSI='MSI Center'; ASUS='ASUS DriverHub'; GIGABYTE='GIGABYTE Control Center'; ASRock='ASRock APP Shop' }
    $executables=@{ MSI=@('MSI Center.exe','MSICenter.exe'); ASUS=@('ASUS DriverHub.exe','ASUSDriverHub.exe','DriverHub.exe'); GIGABYTE=@('GCC.exe'); ASRock=@('AsrAPPShop.exe','AppShop.exe') }
    $manualReasons=@{
        MSI='MSI Center : installation minimale et finalisation SDK sans lancement ni composants additionnels non validees sur PC compatible.'
        ASUS='ASUS DriverHub : le mode silencieux demarre un auxiliaire pouvant verifier le catalogue ; aucune methode officielle sans recherche automatique validee.'
        GIGABYTE='GIGABYTE Control Center : le bundle contient des composants facultatifs ; installation du coeur sans demarrage automatique non validee.'
        ASRock='ASRock APP Shop : /VerySilent annonce dans le catalogue, mais nettoyage de services et pilotes ASRock existants detecte dans la version actuelle ; installation minimale non validee sur PC.'
    }
    return [pscustomobject]@{
        Vendor=$Vendor; Name=$names[$Vendor]; OfficialPage=$base[0].Page; DownloadDefinition=$base[0]
        BoardModel=$BoardModel; TargetOs=$TargetOs
        FileNames=$executables[$Vendor]; Signers=$base[0].Signers
        DownloadUrl=if ($Vendor -eq 'MSI') { 'https://download-2.msi.com/uti_exe/desktop/MSI-Center.zip' } else { '' }
        DownloadManifestUrl=if ($Vendor -eq 'ASUS') { 'https://driverhub.asus.com/download/ASUS-DriverHub-Installer.json' } else { '' }
        # No guessed switches. This remains manual until an exact base-only installation is substantiated.
        Automatic=$false; ApprovedInstallerHashes=@(); InstallerArguments=''
        AutomaticReason=$manualReasons[$Vendor]
        PackageFamily=if ($Vendor -eq 'MSI') { '9426MICRO-STARINTERNATION.MSICenter_kzh8wxbdkxb8p' } else { '' }
    }
}

function Get-VutHardware {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Ce script doit etre execute sous Windows.' }
    # Only identity/compatibility. No BIOS query, driver inventory or update search.
    $boards=@(Get-CimInstance Win32_BaseBoard -OperationTimeoutSec 15 -ErrorAction Stop)
    $pcs=@(Get-CimInstance Win32_ComputerSystem -OperationTimeoutSec 15 -ErrorAction Stop)
    $os=@(Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 15 -ErrorAction Stop)
    $chassis=@(Get-CimInstance Win32_SystemEnclosure -OperationTimeoutSec 15 -ErrorAction Stop)
    if ($boards.Count -ne 1 -or $pcs.Count -ne 1 -or $os.Count -ne 1) { throw 'Identification materielle absente ou ambigue.' }
    return [pscustomobject]@{
        BoardManufacturer=[string]$boards[0].Manufacturer; BoardModel=[string]$boards[0].Product
        ComputerManufacturer=[string]$pcs[0].Manufacturer; ComputerModel=[string]$pcs[0].Model
        Portable=($pcs[0].PCSystemType -eq 2 -or @($chassis | ForEach-Object { $_.ChassisTypes } | Where-Object { $_ -in @(8,9,10,11,12,14,30,31,32) }).Count -gt 0)
        WindowsCaption=[string]$os[0].Caption; WindowsVersion=[string]$os[0].Version
        ClientWindows=($os[0].ProductType -eq 1); Is64Bit=[Environment]::Is64BitOperatingSystem
    }
}

function Resolve-VutSelection {
    param([Parameter(Mandatory)]$Hardware)
    $vendor=Get-MbxVendor $Hardware.BoardManufacturer
    $r=[ordered]@{ Vendor=$vendor; Model=$Hardware.BoardModel; Eligible=$false; Reason=''; Tool='' }
    if (($Hardware.ComputerManufacturer+' '+$Hardware.ComputerModel) -match '(?i)Virtual Machine|VMware|VirtualBox|KVM|QEMU|Xen|Amazon EC2|Google Compute') {
        $r.Reason='Machine virtuelle : aucune installation de logiciel materiel autorisee.'
    } elseif (-not $vendor -or (Test-MbxPlaceholder $Hardware.BoardModel)) {
        $r.Reason='Fabricant ou modele inconnu : utiliser le support du PC.'
    } elseif ($Hardware.Portable) {
        $r.Reason='Portable : utilitaire du modele OEM a confirmer manuellement.'
    } elseif (-not (Test-MbxPlaceholder $Hardware.ComputerManufacturer) -and (Get-MbxVendor $Hardware.ComputerManufacturer) -ne $vendor) {
        $r.Reason='PC OEM : ne pas installer un utilitaire de carte mere retail sans preuve de compatibilite.'
    } elseif (-not $Hardware.ClientWindows -or -not $Hardware.Is64Bit -or $Hardware.WindowsCaption -notmatch '\bWindows\s+(10|11)\b') {
        $r.Reason='Windows client 10/11 64 bits requis ; compatibilite non confirmee pour ce systeme.'
    } else {
        $r.Tool=(Get-VutProfile $vendor).Name
        $r.Eligible=$true
        $r.Reason='Fabricant et modele identifies ; la methode du logiciel est controlee separement.'
    }
    return [pscustomobject]$r
}

function Test-VutApplicationName {
    param($Profile, [string]$DisplayName)
    if ($DisplayName -ieq $Profile.Name) { return $true }
    if ($Profile.Vendor -eq 'ASRock' -and $DisplayName -match '\AAPP Shop v([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)\z') {
        return $null -ne (ConvertTo-MbxVersion $Matches[1])
    }
    return $false
}

function Get-VutInstalledApplication {
    param([Parameter(Mandatory)]$Profile)
    if ($Profile.PackageFamily -and (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue)) {
        $packages=@(Get-AppxPackage -Name '9426MICRO-STARINTERNATION.MSICenter' -ErrorAction SilentlyContinue | Where-Object {
            $_ -and [string](Get-MbxValue $_ 'PackageFamilyName') -eq $Profile.PackageFamily -and [string](Get-MbxValue $_ 'Status') -eq 'Ok' -and
            [string](Get-MbxValue $_ 'SignatureKind') -eq 'Store' -and -not [bool](Get-MbxValue $_ 'IsDevelopmentMode' $false)
        })
        if ($packages.Count -eq 1) {
            $p=$packages[0]; $manifestPath=Join-Path $p.InstallLocation 'AppxManifest.xml'
            if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
                [xml]$manifest=Get-Content -LiteralPath $manifestPath -Raw
                $apps=@($manifest.Package.Applications.Application)
                if ($apps.Count -eq 1 -and [string]$apps[0].Id -match '^[A-Za-z0-9._-]+$') {
                    $exe=[string]$apps[0].Executable
                    $relative=$exe -and -not [IO.Path]::IsPathRooted($exe) -and $exe -notmatch '(^|[/\\])\.\.([/\\]|$)|:'
                    if ($relative -and (Test-Path -LiteralPath (Join-Path $p.InstallLocation $exe) -PathType Leaf)) {
                        return [pscustomobject]@{ Verified=$true; Kind='Appx'; Version=[string]$p.Version; Target=(Join-Path $env:WINDIR 'explorer.exe'); Arguments=('shell:AppsFolder\'+$p.PackageFamilyName+'!'+[string]$apps[0].Id); Proof='Registered exact MSI package family, status Ok and manifest executable present' }
                    }
                }
            }
        }
    }
    $entries=@()
    foreach ($path in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
        $entries+=@(Get-ItemProperty -Path $path -ErrorAction SilentlyContinue | Where-Object { Test-VutApplicationName $Profile ([string](Get-MbxValue $_ 'DisplayName')) })
    }
    foreach ($entry in $entries) {
        $icon=[Environment]::ExpandEnvironmentVariables([string](Get-MbxValue $entry 'DisplayIcon'))
        $target=''
        if ($icon -match '^"([^"\r\n]+\.exe)"(?:,\s*-?\d+)?$') { $target=$Matches[1] }
        elseif ($icon -match '^([^"\r\n]+\.exe)(?:,\s*-?\d+)?$') { $target=$Matches[1] }
        if (-not $target -or $Profile.FileNames -notcontains [IO.Path]::GetFileName($target) -or -not [IO.Path]::IsPathRooted($target) -or -not (Test-Path -LiteralPath $target -PathType Leaf)) { continue }
        try {
            $signature=Test-MbxSignedPayload -Path $target -Signers $Profile.Signers
            $info=[Diagnostics.FileVersionInfo]::GetVersionInfo($target)
            if ([string]$info.ProductName -ine $Profile.Name -and [string]$info.FileDescription -ine $Profile.Name) { continue }
            return [pscustomobject]@{ Verified=$true; Kind='Exe'; Version=$signature.FileVersion.Trim(); Target=$target; Arguments=''; Proof='Exact application registry name, expected signed executable and product identity' }
        } catch { continue }
    }
    return $null
}

function Get-VutDesktop {
    $desktop=[Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory)
    if (-not $desktop -or -not (Test-Path -LiteralPath $desktop -PathType Container)) { throw 'Bureau reel de cet utilisateur Windows introuvable ; aucun repli vers le Bureau public.' }
    return $desktop
}

function New-VutShortcut {
    param([Parameter(Mandatory)]$Profile, [Parameter(Mandatory)]$Application)
    if (-not $Application.Verified -or -not (Test-Path -LiteralPath $Application.Target -PathType Leaf)) { throw 'Application non verifiee : aucun raccourci cree.' }
    $desktop=Get-VutDesktop
    $path=Join-Path $desktop ($Profile.Name+'.lnk')
    $shell=New-Object -ComObject WScript.Shell
    try {
        $link=$shell.CreateShortcut($path)
        if (Test-Path -LiteralPath $path) {
            if ($link.TargetPath -ine $Application.Target -or $link.Arguments -cne $Application.Arguments) { throw 'Un raccourci du meme nom a une autre cible : il est conserve.' }
            return $path
        }
        $link.TargetPath=$Application.Target; $link.Arguments=$Application.Arguments
        $link.WorkingDirectory=Split-Path -Parent $Application.Target
        $link.Description='Ouvrir manuellement '+$Profile.Name
        $link.Save()
        $read=$shell.CreateShortcut($path)
        if ($read.TargetPath -ine $Application.Target -or $read.Arguments -cne $Application.Arguments) { throw 'Raccourci ecrit mais verification de sa cible en echec.' }
        return $path
    } finally { if ($shell) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) } }
}

function Get-VutInstallerStore {
    $local=[Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    if (-not $local) { throw 'Dossier local de cet utilisateur Windows introuvable pour conserver l installateur.' }
    return Join-Path $local 'VendorUtility/Installers'
}

function New-VutSupportShortcut {
    param([Parameter(Mandatory)]$Profile)
    # Fixed official landing page, never a guessed binary or a cached old release.
    $official=Get-VutProfile -Vendor $Profile.Vendor
    if (-not $official -or $Profile.OfficialPage -cne $official.OfficialPage -or
        -not (Test-MbxOfficialUri $official.OfficialPage $official.DownloadDefinition.Hosts)) {
        throw 'Page de repli officielle invalide ; aucun raccourci Internet cree.'
    }
    $path=Join-Path (Get-VutDesktop) ('Telechargement officiel - '+$official.Name+'.url')
    $content="[InternetShortcut]`r`nURL=$($official.OfficialPage)`r`n"
    if (Test-Path -LiteralPath $path) {
        if ([IO.File]::ReadAllText($path).Trim() -cne $content.Trim()) {
            throw 'Un raccourci Internet du meme nom a une autre cible : il est conserve.'
        }
        return $path
    }
    $stream=[IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try {
        $bytes=[Text.Encoding]::ASCII.GetBytes($content)
        $stream.Write($bytes,0,$bytes.Length)
    } finally {$stream.Dispose()}
    if ([IO.File]::ReadAllText($path) -cne $content) {throw 'Verification du raccourci Internet officiel en echec.'}
    return $path
}

function New-VutInstallerShortcut {
    param([Parameter(Mandatory)]$Profile,[Parameter(Mandatory)]$Package)
    $displayVersion=([string]$Package.Version).Trim()
    $version=ConvertTo-MbxVersion $displayVersion
    $allowed=($Profile.Vendor -in @('MSI','ASUS','ASRock') -or ($Profile.Vendor -eq 'GIGABYTE' -and (Get-MbxValue $Package 'Kind') -eq 'gigabyte_core'))
    if (-not $version -or -not $allowed -or $Package.SHA256 -notmatch '\A[0-9A-Fa-f]{64}\z') {
        throw 'Installateur sans identite/version verifiee : aucun raccourci cree.'
    }
    $source=[IO.Path]::GetFullPath($Package.Path)
    $verified=Test-MbxSignedPayload -Path $source -Signers $Profile.Signers
    if ($verified.SHA256 -ine $Package.SHA256 -or (ConvertTo-MbxVersion $verified.FileVersion.Trim()) -ne $version) {
        throw 'Installateur modifie depuis le telechargement : aucun raccourci cree.'
    }
    # A stable, per-user location keeps the shortcut usable after this script
    # exits and lets repeated downloads reuse the same verified target.
    $directory=Join-Path (Get-VutInstallerStore) ($Profile.Vendor+'/'+$version.ToString()+'/'+$Package.SHA256.ToUpperInvariant())
    [void](New-Item -ItemType Directory -Path $directory -Force)
    $target=Join-Path $directory 'Setup.exe'
    if (-not (Test-Path -LiteralPath $target)) { [IO.File]::Copy($source,$target,$false) }
    $stored=Test-MbxSignedPayload -Path $target -Signers $Profile.Signers
    if ($stored.SHA256 -ine $Package.SHA256 -or (ConvertTo-MbxVersion $stored.FileVersion.Trim()) -ne $version) {
        throw 'Copie permanente de l installateur non conforme : aucun raccourci cree.'
    }
    $shortcutProfile=[pscustomobject]@{Name=('Installer '+$Profile.Name+' '+$displayVersion)}
    $application=[pscustomobject]@{Verified=$true;Kind='Installer';Target=$target;Arguments=''}
    $shortcut=New-VutShortcut -Profile $shortcutProfile -Application $application
    return [pscustomobject]@{Path=$target;Version=$displayVersion;Shortcut=$shortcut}
}

function Resolve-VutAsusDownload {
    # The geo endpoint returns a region header, not an installer. Follow DriverHub's own JSON contract.
    $manifestUrl='https://driverhub.asus.com/download/ASUS-DriverHub-Installer.json'
    $response=Invoke-MbxHttp -Url $manifestUrl -Hosts @('driverhub.asus.com') -TimeoutSeconds 30 -MaxBytes 65536
    try { $manifest=$response.Text | ConvertFrom-Json -ErrorAction Stop }
    catch { throw 'Manifeste ASUS officiel invalide : JSON illisible ; aucun repli vers un ancien installateur.' }
    $latest=[string](Get-MbxValue $manifest 'latestVersion')
    $minimum=[string](Get-MbxValue $manifest 'minimumSupportedVersion')
    $version=ConvertTo-MbxVersion $latest
    if ($latest -notmatch '\A[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\z' -or -not $version) { throw 'Manifeste ASUS officiel : latestVersion absent ou invalide ; aucun ancien fichier selectionne.' }
    if ($minimum) {
        $minimumVersion=ConvertTo-MbxVersion $minimum
        if ($minimum -notmatch '\A[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\z' -or -not $minimumVersion -or $minimumVersion -gt $version) { throw 'Manifeste ASUS officiel incoherent : minimumSupportedVersion invalide ou superieur a latestVersion.' }
    }
    # This threshold is the vendor's URL routing rule, not a pinned latest release.
    $url=if ($version -gt [version]'1.0.4.7') { 'https://driverhub.asus.com/download/'+$latest+'/ASUS-DriverHub-Installer.exe' } else { 'https://driverhub.asus.com/download/ASUS-DriverHub-Installer.exe' }
    return [pscustomobject]@{ ManifestUrl=$manifestUrl; Version=$latest; MinimumSupportedVersion=$minimum; DownloadUrl=$url; Method='official_asus_json' }
}

function Get-VutPackage {
    param([Parameter(Mandatory)]$Profile, [Parameter(Mandatory)][string]$Directory)
    if ($Profile.Vendor -eq 'GIGABYTE') { return Get-VutGigabytePackage -Directory $Directory }
    $discovery=$null; $downloadUrl=$Profile.DownloadUrl
    if ($Profile.Vendor -eq 'ASUS') { $discovery=Resolve-VutAsusDownload; $downloadUrl=$discovery.DownloadUrl }
    if ($Profile.Vendor -eq 'ASRock') { $discovery=Resolve-VutAsrockDownload -Model $Profile.BoardModel -TargetOs $Profile.TargetOs; $downloadUrl=$discovery.DownloadUrl }
    if (-not $downloadUrl) { throw 'Aucun installateur officiel non ambigu resolu pour ce modele. Utiliser la page de support.' }
    [void](New-Item -ItemType Directory -Path $Directory -Force)
    $audit=Invoke-MbxUtilityAudit -Tool $Profile.DownloadDefinition -DownloadUrl $downloadUrl -OutputDirectory $Directory
    if ($Profile.Vendor -eq 'ASRock') {
        if ($audit.SHA256 -ine $discovery.ArchiveSHA256) { throw 'Archive ASRock differente de l empreinte SHA256 du catalogue constructeur.' }
        $archives=@(Get-ChildItem -LiteralPath $Directory -Recurse -File -Filter '*.zip')
        if ($archives.Count -ne 1) { throw 'Archive ASRock absente ou ambigue.' }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive=[IO.Compression.ZipFile]::OpenRead($archives[0].FullName)
        try {
            $expectedEntry=@($archive.Entries | Where-Object { $_.FullName.Replace('\','/') -ceq $discovery.InstallerRelativePath })
            if ($expectedEntry.Count -ne 1 -or $audit.Payloads.Count -ne 1 -or $expectedEntry[0].Length -ne $audit.Payloads[0].Bytes) { throw 'Installateur ASRock interne different du fichier annonce par le constructeur.' }
        } finally { $archive.Dispose() }
    }
    $files=@(Get-ChildItem -LiteralPath $Directory -Recurse -File -Filter '*.exe' | Where-Object { $_.Name -like 'payload-*.exe' -or $_.Name -match $Profile.DownloadDefinition.FilePattern })
    if ($files.Count -ne 1 -or $audit.Payloads.Count -ne 1) { throw 'Plusieurs executables ou installateur principal ambigu : installation manuelle requise.' }
    $verified=Test-MbxSignedPayload -Path $files[0].FullName -Signers $Profile.Signers
    if ($verified.SHA256 -ne $audit.Payloads[0].SHA256) { throw 'Le fichier a change apres le telechargement.' }
    if ($discovery) {
        $fileVersion=ConvertTo-MbxVersion $verified.FileVersion.Trim()
        if (-not $fileVersion -or $fileVersion -ne (ConvertTo-MbxVersion $discovery.Version)) { throw ('Version '+$Profile.Vendor+' du fichier differente du manifeste officiel ; aucun telechargement presente comme la derniere version.') }
    }
    return [pscustomobject]@{ Path=$files[0].FullName; SHA256=$verified.SHA256; Version=$verified.FileVersion.Trim(); Audit=$audit; Discovery=$discovery }
}

function Invoke-VutInstallerProcess {
    param([string]$Path, [string]$Arguments, [int]$TimeoutSeconds=600)
    # A hard boundary: real hardware vendor installers must never execute on GitHub hosted runners.
    if ($env:GITHUB_ACTIONS -eq 'true') { throw 'Installateur constructeur reel interdit dans GitHub Actions.' }
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Droits administrateur requis pour installer le logiciel.' }
    $p=New-Object Diagnostics.Process
    $started=$false
    $p.StartInfo.FileName=$Path; $p.StartInfo.Arguments=$Arguments; $p.StartInfo.UseShellExecute=$false
    try {
        if (-not $p.Start()) { throw 'L installateur ne demarre pas.' }
        $started=$true
        if (-not $p.WaitForExit($TimeoutSeconds*1000)) { throw 'Delai de l installateur depasse ; installation non confirmee.' }
        return $p.ExitCode
    } finally {
        if ($started -and -not $p.HasExited) { & (Join-Path $env:WINDIR 'System32/taskkill.exe') /PID $p.Id /T /F | Out-Null }
        $p.Dispose()
    }
}

function Invoke-VendorUtility {
    [CmdletBinding()]
    param([switch]$PlanOnly)
    $r=[ordered]@{ Mode=if ($script:UtilitySimulation) { 'simulation' } else { 'real' }; Status='failed'; Vendor=''; Model=''; Tool=''; Reason=''; OfficialPage=''; InstallerPath=''; InstallerVersion=''; InstallerShortcut=''; InstallerSource=''; DetectionSource=''; DetectionMethod=''; SupportShortcut=''; FallbackUsed=$false; DownloadFailure=''; FallbackError=''; Installed=$false; InstalledThisRun=$false; ApplicationVerified=$false; ApplicationVersion=''; RebootRequired=$false; Shortcut=''; AutomaticInstallAvailable=$false }
    try {
        $hardware=Get-VutHardware
        $selection=Resolve-VutSelection $hardware
        $r.Vendor=$selection.Vendor; $r.Model=$selection.Model
        if (-not $selection.Eligible) { $r.Status='manual_required'; $r.Reason=$selection.Reason; return [pscustomobject]$r }
        $targetOs=if ($hardware.WindowsCaption -match '\bWindows\s+11\b') { 'Windows 11 64bit' } else { 'Windows 10 64bit' }
        $profile=Get-VutProfile -Vendor $selection.Vendor -BoardModel $selection.Model -TargetOs $targetOs
        $r.Tool=$profile.Name; $r.OfficialPage=$profile.OfficialPage; $r.AutomaticInstallAvailable=$profile.Automatic
        if ($PlanOnly) { $r.Status='plan'; $r.Reason=$profile.AutomaticReason; return [pscustomobject]$r }
        $app=Get-VutInstalledApplication $profile
        if ($app -and $app.Verified) {
            $r.ApplicationVerified=$true; $r.ApplicationVersion=$app.Version; $r.Installed=-not $script:UtilitySimulation
            $r.Shortcut=New-VutShortcut $profile $app
            $r.Status='already_installed'; $r.Reason='Application presente et raccourci verifie ; aucune mise a jour lancee.'
            return [pscustomobject]$r
        }
        $cache=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) ('VendorUtility/'+[guid]::NewGuid().ToString('N'))
        try { $package=Get-VutPackage $profile $cache; $r.InstallerPath=$package.Path }
        catch {
            $r.Status='manual_required'; $r.DownloadFailure=$_.Exception.Message
            $r.Reason='Detection/telechargement automatique impossible : '+$r.DownloadFailure
            try {
                $r.SupportShortcut=New-VutSupportShortcut -Profile $profile
                $r.FallbackUsed=$true
                $r.Reason+=' Repli manuel : raccourci Telechargement officiel sur le Bureau vers '+$r.OfficialPage+'. Aucun installateur valide ni installation confirmee.'
            } catch {
                $r.FallbackError=$_.Exception.Message
                $r.Reason+=' Repli Bureau impossible : '+$r.FallbackError+' Page officielle : '+$r.OfficialPage
            }
            return [pscustomobject]$r
        }
        $discovery=Get-MbxValue $package 'Discovery'
        $r.DetectionSource=[string](Get-MbxValue $discovery 'ManifestUrl')
        $r.DetectionMethod=[string](Get-MbxValue $discovery 'Method')
        $r.InstallerSource=[string](Get-MbxValue (Get-MbxValue $package 'Audit') 'FinalUrl')
        if (-not $profile.Automatic -or $profile.ApprovedInstallerHashes -notcontains $package.SHA256) {
            $prepared=New-VutInstallerShortcut -Profile $profile -Package $package
            $r.InstallerPath=$prepared.Path; $r.InstallerVersion=$prepared.Version; $r.InstallerShortcut=$prepared.Shortcut
            $r.Status='manual_required'; $r.Reason=$profile.AutomaticReason+' Installateur verifie : utilisez son raccourci sur le Bureau pour installer manuellement. Aucun installateur execute par ce script.'
            return [pscustomobject]$r
        }
        $checked=Test-MbxSignedPayload -Path $package.Path -Signers $profile.Signers
        if ($checked.SHA256 -ne $package.SHA256) { throw 'Installateur remplace depuis sa verification.' }
        $exitCode=Invoke-VutInstallerProcess -Path $package.Path -Arguments $profile.InstallerArguments
        if ($exitCode -notin @(0,3010)) { throw "Echec installateur : code $exitCode. Aucune installation reussie annoncee." }
        $r.RebootRequired=($exitCode -eq 3010)
        $app=Get-VutInstalledApplication $profile
        $installedVersion=if ($app) { ConvertTo-MbxVersion $app.Version } else { $null }
        $targetVersion=ConvertTo-MbxVersion $package.Version
        if (-not $app -or -not $app.Verified -or -not $installedVersion -or -not $targetVersion -or $installedVersion -lt $targetVersion) { throw 'Installateur termine mais application/version non confirmee ; aucun raccourci cree.' }
        $r.Installed=-not $script:UtilitySimulation
        $r.InstalledThisRun=-not $script:UtilitySimulation; $r.ApplicationVerified=$true; $r.ApplicationVersion=$app.Version
        $r.Shortcut=New-VutShortcut $profile $app
        $r.Status=if ($script:UtilitySimulation) { 'simulated_installed' } else { 'installed' }
        $r.Reason='Application et raccourci verifies. Ouverture manuelle par le technicien.'
        return [pscustomobject]$r
    } catch { $r.Status='failed'; $r.Reason=$_.Exception.Message; return [pscustomobject]$r }
}

Export-ModuleMember -Function Invoke-VendorUtility
