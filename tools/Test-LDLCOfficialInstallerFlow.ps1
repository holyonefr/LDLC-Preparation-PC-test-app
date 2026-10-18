$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'modules\00.Core.ps1')
. (Join-Path $root 'modules\30.Applications.ps1')

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('LDLCInstallerFlow-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
$previousCache = [Environment]::GetEnvironmentVariable('LDLC_INSTALLER_CACHE')

try {
    $script:StopFile = Join-Path $tempRoot 'NO_STOP'
    $script:ExePathCache = @{}
    $script:InstalledProgramsCache = $null
    $script:InstalledProgramsCacheTimestamp = [datetime]::MinValue
    $script:LDLCSuppressWriteProgress = $true

    function Get-LDLCInstalledPrograms {
        param([switch]$Refresh)
        [void]$Refresh
        return @([pscustomobject]@{
            DisplayName = 'Application Test Officielle'
            DisplayVersion = '9.8.7'
            Publisher = 'Editeur Test'
            InstallLocation = ''
            PSChildName = 'ApplicationTest'
        })
    }

    $powershellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $detectionApp = @{
        Name = 'Application Test Officielle'
        DetectNames = @('Application Test Officielle')
        ExePaths = @($powershellExe)
        SearchFolders = @()
        ExeName = 'powershell.exe'
    }
    $detectionState = Get-LDLCAppInstallationState -App $detectionApp -Refresh
    if (-not $detectionState.IsInstalled -or -not $detectionState.HasExecutable -or
        -not $detectionState.HasRegistry -or [string]::IsNullOrWhiteSpace($detectionState.Version)) {
        throw "Validation executable/registre/version non confirmee : $($detectionState | ConvertTo-Json -Compress)"
    }

    function New-TestInstallerDefinition {
        param([string]$FileName = 'test-official.exe')
        return @{
            Provider                = 'Editeur test officiel'
            Url                     = "https://downloads.example.test/$FileName"
            FileName                = $FileName
            CachePatterns           = @('test-*.exe')
            TrustedHosts            = @('downloads.example.test')
            SkipSignatureValidation = $true
            MinBytes                = 16
            CacheMinBytes           = 16
            ExeArguments            = @('/S')
            TimeoutSeconds          = 5
            ValidationTimeoutSeconds = 2
        }
    }

    $downloadAction = {
        param($Url, $Destination)
        [void]$Url
        [System.IO.File]::WriteAllBytes($Destination, ([byte[]](1..64)))
        return $Destination
    }
    $installAction = {
        param($Path, $Installer, $Label)
        [void]$Path; [void]$Installer; [void]$Label
        $script:FakeInstalled = $true
        return [pscustomobject]@{ ExitCode = 0; TimedOut = $false; OutputLines = @('simulation OK') }
    }
    $validation = { [bool]$script:FakeInstalled }

    $directCache = Join-Path $tempRoot 'direct'
    [Environment]::SetEnvironmentVariable('LDLC_INSTALLER_CACHE', $directCache)
    $script:LDLCInstallerCacheRoot = $null
    $script:FakeInstalled = $false
    $directDefinition = New-TestInstallerDefinition -FileName 'test-direct.exe'
    $directResult = Invoke-LDLCOfficialInstaller `
        -Installer $directDefinition `
        -Label 'Application test direct' `
        -ValidationScript $validation `
        -DownloadAction $downloadAction `
        -InstallAction $installAction

    if (-not $directResult.Success -or $directResult.Method -notmatch 'officiel direct') {
        throw "Scenario direct non valide : $($directResult | ConvertTo-Json -Compress)"
    }
    if (-not (Test-Path -LiteralPath (Join-Path $directCache 'test-direct.exe'))) {
        throw 'Le package officiel telecharge n a pas ete conserve dans le cache.'
    }

    $offlineCache = Join-Path $tempRoot 'offline'
    New-Item -ItemType Directory -Path $offlineCache -Force | Out-Null
    [System.IO.File]::WriteAllBytes((Join-Path $offlineCache 'test-cache.exe'), ([byte[]](1..64)))
    [Environment]::SetEnvironmentVariable('LDLC_INSTALLER_CACHE', $offlineCache)
    $script:LDLCInstallerCacheRoot = $null
    $script:FakeInstalled = $false
    $offlineDefinition = New-TestInstallerDefinition -FileName 'test-online.exe'
    $offlineResult = Invoke-LDLCOfficialInstaller `
        -Installer $offlineDefinition `
        -Label 'Application test cache' `
        -ValidationScript $validation `
        -DownloadAction { param($Url, $Destination) throw "reseau indisponible : $Url -> $Destination" } `
        -InstallAction $installAction

    if (-not $offlineResult.Success -or $offlineResult.Method -ne 'cache local') {
        throw "Scenario cache hors ligne non valide : $($offlineResult | ConvertTo-Json -Compress)"
    }

    $failureCache = Join-Path $tempRoot 'failure'
    [Environment]::SetEnvironmentVariable('LDLC_INSTALLER_CACHE', $failureCache)
    $script:LDLCInstallerCacheRoot = $null
    $script:FakeInstalled = $false
    $failureDefinition = New-TestInstallerDefinition -FileName 'test-failure.exe'
    $failureResult = Invoke-LDLCOfficialInstaller `
        -Installer $failureDefinition `
        -Label 'Application test echec' `
        -ValidationScript $validation `
        -DownloadAction { param($Url, $Destination) throw "connexion instable : $Url -> $Destination" } `
        -InstallAction $installAction

    if ($failureResult.Success -or $failureResult.Reason -notmatch 'connexion instable') {
        throw "Scenario echec detaille non valide : $($failureResult | ConvertTo-Json -Compress)"
    }

    Write-Host 'OK official installer direct/cache/failure flow'
}
finally {
    [Environment]::SetEnvironmentVariable('LDLC_INSTALLER_CACHE', $previousCache)
    $script:LDLCInstallerCacheRoot = $null
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
