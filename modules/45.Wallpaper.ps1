# region Module: 45.Wallpaper.ps1
# Wallpaper configuration helpers.

function Initialize-LDLCWallpaperType {
    if (-not ([System.Management.Automation.PSTypeName]'WallpaperManager').Type) {
        Add-Type @"
using System.Runtime.InteropServices;
public class WallpaperManager {
    [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)]
    public static extern bool SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
"@
    }
}

function Set-LDLCWallpaperRegistryValues {
    param(
        [Parameter(Mandatory = $true)][string]$DesktopRegistryPath,
        [Parameter(Mandatory = $true)][string]$WallpaperPath
    )

    if (-not (Test-Path $DesktopRegistryPath)) {
        New-Item -Path $DesktopRegistryPath -Force | Out-Null
    }

    New-ItemProperty -Path $DesktopRegistryPath -Name Wallpaper -Value $WallpaperPath -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $DesktopRegistryPath -Name WallpaperStyle -Value "10" -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $DesktopRegistryPath -Name TileWallpaper -Value "0" -PropertyType String -Force | Out-Null
}

function Set-LDLCExplorerWallpaperMode {
    param([Parameter(Mandatory = $true)][string]$RegistryRoot)

    $wallpaperModePath = Join-Path $RegistryRoot 'Software\Microsoft\Windows\CurrentVersion\Explorer\Wallpapers'
    if (-not (Test-Path $wallpaperModePath)) {
        New-Item -Path $wallpaperModePath -Force | Out-Null
    }

    New-ItemProperty -Path $wallpaperModePath -Name BackgroundType -Value 0 -PropertyType DWord -Force | Out-Null
}

function Copy-LDLCWallpaperToThemeCache {
    param([Parameter(Mandatory = $true)][string]$WallpaperPath)

    if ([string]::IsNullOrWhiteSpace($env:APPDATA)) {
        return
    }

    $themesDir = Join-Path $env:APPDATA 'Microsoft\Windows\Themes'
    if (-not (Test-Path $themesDir)) {
        New-Item -ItemType Directory -Path $themesDir -Force | Out-Null
    }

    Copy-Item -Path $WallpaperPath -Destination (Join-Path $themesDir 'TranscodedWallpaper') -Force
}

function Set-LDLCCurrentUserWallpaper {
    param([Parameter(Mandatory = $true)][string]$WallpaperPath)

    Set-LDLCWallpaperRegistryValues -DesktopRegistryPath 'HKCU:\Control Panel\Desktop' -WallpaperPath $WallpaperPath
    Set-LDLCExplorerWallpaperMode -RegistryRoot 'HKCU:'
    Copy-LDLCWallpaperToThemeCache -WallpaperPath $WallpaperPath
}

function Set-LDLCLoadedUsersWallpaper {
    param([Parameter(Mandatory = $true)][string]$WallpaperPath)

    $loadedUserSids = Get-ChildItem 'Registry::HKEY_USERS' -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -match '^S-1-5-21-\d+-\d+-\d+-\d+$' } |
        Select-Object -ExpandProperty PSChildName

    foreach ($sid in $loadedUserSids) {
        try {
            $userRoot = "Registry::HKEY_USERS\$sid"
            Set-LDLCWallpaperRegistryValues -DesktopRegistryPath (Join-Path $userRoot 'Control Panel\Desktop') -WallpaperPath $WallpaperPath
            Set-LDLCExplorerWallpaperMode -RegistryRoot $userRoot
        }
        catch {
            Write-Step "Profil charge $sid ignore pour le fond d'ecran : $($_.Exception.Message)"
        }
    }
}

function Set-LDLCDefaultUserWallpaper {
    param(
        [Parameter(Mandatory = $true)][string]$WallpaperPath
    )

    $defaultProfileHivePath = Join-Path $env:SystemDrive 'Users\Default\NTUSER.DAT'
    if (-not (Test-Path $defaultProfileHivePath)) {
        Write-Step "Profil utilisateur par defaut introuvable : fond d'ecran futur profil ignore."
        return $false
    }

    $hiveName = 'HKU\LDLCDefaultUser'
    $registryRoot = 'Registry::HKEY_USERS\LDLCDefaultUser'
    $hiveLoadedHere = $false

    try {
        & reg.exe load $hiveName $defaultProfileHivePath | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Chargement du profil par defaut impossible (code $LASTEXITCODE)."
        }

        $hiveLoadedHere = $true

        Set-LDLCWallpaperRegistryValues -DesktopRegistryPath (Join-Path $registryRoot 'Control Panel\Desktop') -WallpaperPath $WallpaperPath
        Set-LDLCExplorerWallpaperMode -RegistryRoot $registryRoot
        Write-Ok "Fond d'ecran prepare pour les futurs utilisateurs."
        return $true
    }
    catch {
        Write-Step "Profil utilisateur par defaut ignore pour le fond d'ecran : $($_.Exception.Message)"
        return $false
    }
    finally {
        if ($hiveLoadedHere) {
            & reg.exe unload $hiveName | Out-Null
        }
    }
}

function Write-LDLCWallpaperFailure {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [switch]$QuietFailure
    )

    if ($QuietFailure) {
        Write-Step $Message
    }
    else {
        Write-Err $Message
    }
}

function Get-LDLCCurrentWallpaperPath {
    try {
        return [string](Get-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name Wallpaper -ErrorAction Stop).Wallpaper
    }
    catch {
        return ''
    }
}

function Test-LDLCWallpaperApplied {
    param([string]$ExpectedPath = $script:LDLCWallpaperExpectedPath)

    if ([string]::IsNullOrWhiteSpace($ExpectedPath)) {
        return $false
    }

    if (-not (Test-Path -LiteralPath $ExpectedPath)) {
        return $false
    }

    $currentPath = Get-LDLCCurrentWallpaperPath
    if ([string]::IsNullOrWhiteSpace($currentPath)) {
        return $false
    }

    try {
        $expectedFullPath = [System.IO.Path]::GetFullPath($ExpectedPath)
        $currentFullPath = [System.IO.Path]::GetFullPath($currentPath)
        return ($expectedFullPath -ieq $currentFullPath)
    }
    catch {
        return ($ExpectedPath -ieq $currentPath)
    }
}

function Set-LDLCWallpaper {
    param(
        [int]$ProgressPercent = 81,
        [switch]$IgnoreStopRequest,
        [switch]$QuietFailure
    )

    if (-not $IgnoreStopRequest) {
        Stop-IfRequested
    }

    Write-Section "CONFIGURATION DU FOND D'ECRAN"
    Write-ProgressFile $ProgressPercent "Configuration du fond d'ecran..." -IgnoreStopRequest:$IgnoreStopRequest

    try {
        $targetDir = Join-Path $env:ProgramData "LDLC\Wallpaper"
        $sourceWall = Resolve-LDLCAssetPath -RelativePaths @(
            'LDLC.png',
            'ldlc.png',
            'images\LDLC.png',
            'images\ldlc.png',
            'LDLC.jpg',
            'ldlc.jpg',
            'images\LDLC.jpg',
            'images\ldlc.jpg'
        )

        if (-not $sourceWall) {
            Write-LDLCWallpaperFailure -Message "Image source introuvable : LDLC.png ou LDLC.jpg" -QuietFailure:$QuietFailure
            return $false
        }

        $wallpaperExtension = [System.IO.Path]::GetExtension($sourceWall)
        if ([string]::IsNullOrWhiteSpace($wallpaperExtension)) {
            $wallpaperExtension = ".png"
        }

        $wallpaperFileName = "LDLC$wallpaperExtension"
        $machineWallpaperPath = Join-Path $targetDir $wallpaperFileName

        $userPicturesDir = Join-Path $env:USERPROFILE "Pictures"
        if (-not (Test-Path $userPicturesDir)) {
            New-Item -ItemType Directory -Path $userPicturesDir -Force | Out-Null
        }

        $userWallpaperPath = Join-Path $userPicturesDir $wallpaperFileName
        Copy-Item $sourceWall $userWallpaperPath -Force

        $targetWall = $machineWallpaperPath
        $machineWallpaperReady = $true

        try {
            if (-not (Test-Path $targetDir)) {
                Write-Step "Creation du dossier fond d'ecran machine..."
                New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
            }

            Write-Step "Copie de l'image du fond d'ecran machine..."
            Copy-Item $sourceWall $machineWallpaperPath -Force
        }
        catch {
            $machineWallpaperReady = $false
            $targetWall = $userWallpaperPath
            Write-Step "Copie machine indisponible, utilisation du fond d'ecran utilisateur : $($_.Exception.Message)"
        }

        $script:LDLCWallpaperExpectedPath = $targetWall

        Write-Step "Enregistrement du fond d'ecran dans le registre..."
        Set-LDLCCurrentUserWallpaper -WallpaperPath $targetWall

        if ($machineWallpaperReady) {
            Set-LDLCLoadedUsersWallpaper -WallpaperPath $targetWall
        }
        else {
            Write-Step "Persistance multi-utilisateur ignoree car le chemin machine n'est pas disponible."
        }

        Write-Step "Application du fond d'ecran..."
        Initialize-LDLCWallpaperType
        $result = [WallpaperManager]::SystemParametersInfo(20, 0, $targetWall, 3)

        if (-not $result) {
            $win32Error = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
            Write-LDLCWallpaperFailure -Message "Impossible d'appliquer le fond d'ecran. Code Win32 : $win32Error" -QuietFailure:$QuietFailure
            return $false
        }

        if ($machineWallpaperReady) {
            Set-LDLCDefaultUserWallpaper -WallpaperPath $targetWall | Out-Null
        }
        else {
            Write-Step "Profil utilisateur par defaut ignore car le chemin machine n'est pas disponible."
        }

        Write-Ok "Fond d'ecran LDLC applique et sauvegarde pour le redemarrage."
        Write-ProgressFile $ProgressPercent "Fond d'ecran configure." -IgnoreStopRequest:$IgnoreStopRequest
        return $true
    }
    catch {
        Write-LDLCWallpaperFailure -Message "Erreur configuration fond d'ecran : $($_.Exception.Message)" -QuietFailure:$QuietFailure
        return $false
    }
}

function Ensure-LDLCWallpaperApplied {
    param(
        [int]$ProgressPercent = 81,
        [switch]$IgnoreStopRequest,
        [switch]$VerifyOnly
    )

    if (-not $IgnoreStopRequest) {
        Stop-IfRequested
    }

    if ($VerifyOnly -and (Test-LDLCWallpaperApplied)) {
        Write-Ok "Fond d'ecran LDLC confirme lors de la verification finale."
        Write-ProgressFile $ProgressPercent "Fond d'ecran confirme." -IgnoreStopRequest:$IgnoreStopRequest
        return $true
    }

    if ($VerifyOnly) {
        $currentWallpaper = Get-LDLCCurrentWallpaperPath
        Write-Step "Fond d'ecran LDLC non confirme lors de la verification finale. Actuel : $(if ($currentWallpaper) { $currentWallpaper } else { 'non renseigne' })"
    }

    for ($attempt = 1; $attempt -le 2; $attempt++) {
        if (-not $IgnoreStopRequest) {
            Stop-IfRequested
        }

        $attemptMessage = if ($attempt -eq 1) { "Application du fond d'ecran LDLC..." } else { "Nouvelle tentative fond d'ecran LDLC..." }
        Write-ProgressFile $ProgressPercent $attemptMessage -IgnoreStopRequest:$IgnoreStopRequest

        $applied = Set-LDLCWallpaper -ProgressPercent $ProgressPercent -IgnoreStopRequest:$IgnoreStopRequest -QuietFailure
        if ($applied -and (Test-LDLCWallpaperApplied)) {
            if ($attempt -eq 1 -and -not $VerifyOnly) {
                Write-Ok "Fond d'ecran LDLC verifie."
            }
            elseif ($attempt -gt 1) {
                Write-Ok "Fond d'ecran LDLC confirme apres nouvelle tentative."
            }
            else {
                Write-Ok "Fond d'ecran LDLC confirme lors de la verification finale."
            }

            Write-ProgressFile $ProgressPercent "Fond d'ecran confirme." -IgnoreStopRequest:$IgnoreStopRequest
            return $true
        }

        if ($attempt -lt 2) {
            Write-Step "Fond d'ecran LDLC non confirme apres tentative $attempt. Nouvelle tentative..."
            Start-Sleep -Milliseconds 600
        }
    }

    $expectedWallpaper = if ($script:LDLCWallpaperExpectedPath) { $script:LDLCWallpaperExpectedPath } else { 'non renseigne' }
    $currentWallpaper = Get-LDLCCurrentWallpaperPath
    if ([string]::IsNullOrWhiteSpace($currentWallpaper)) {
        $currentWallpaper = 'non renseigne'
    }

    Write-Warn "Fond d'ecran LDLC non confirme apres deux tentatives. Attendu : $expectedWallpaper ; actuel : $currentWallpaper"
    Write-ProgressFile $ProgressPercent "Fond d'ecran non confirme, preparation continue." -IgnoreStopRequest:$IgnoreStopRequest
    return $false
}

# endregion Module: 45.Wallpaper.ps1

