param(
    [switch]$UninstallFirst,
    [switch]$NoElevate,
    [string]$ResultPath = (Join-Path $env:ProgramData 'LDLCPreparationPC\LDLC_ADOBE_LIVE_TEST.json'),
    [string]$LogPath = (Join-Path $env:ProgramData 'LDLCPreparationPC\LDLC_ADOBE_LIVE_TEST.log')
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

function Test-LDLCLiveTestAdmin {
    try {
        $principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
        return $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Get-LDLCAdobeRegistryEntriesForLiveTest {
    $entries = @()
    foreach ($registryRoot in @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )) {
        try {
            Get-ItemProperty -Path $registryRoot -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -match '(?i)Adobe.*(Acrobat|Reader)' } |
                ForEach-Object { $entries += $_ }
        }
        catch {}
    }

    return @($entries)
}

function ConvertTo-LDLCAdobeLiveState {
    param($App)

    $state = Get-LDLCAppInstallationState -App $App -Refresh
    $registryEntries = @(Get-LDLCAdobeRegistryEntriesForLiveTest | Select-Object DisplayName, DisplayVersion, Publisher, InstallLocation, UninstallString)
    return [ordered]@{
        IsInstalled = [bool]$state.IsInstalled
        ExePath = [string]$state.ExePath
        HasExecutable = [bool]$state.HasExecutable
        HasRegistry = [bool]$state.HasRegistry
        RegistryDisplayName = [string]$state.RegistryDisplayName
        RegistryVersion = [string]$state.RegistryVersion
        FileVersion = [string]$state.FileVersion
        Version = [string]$state.Version
        RegistryEntries = @($registryEntries)
    }
}

function Invoke-LDLCAdobeUninstallForLiveTest {
    $entries = @(Get-LDLCAdobeRegistryEntriesForLiveTest)
    if ($entries.Count -eq 0) {
        Write-Host '[LIVE-ADOBE] Aucun Adobe Acrobat/Reader installe avant test.'
        return @()
    }

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($entry in $entries) {
        $displayName = [string]$entry.DisplayName
        $uninstallString = [string]$entry.UninstallString
        $productCode = ''
        if ($entry.PSChildName -match '^\{[0-9A-Fa-f-]+\}$') {
            $productCode = [string]$entry.PSChildName
        }
        elseif ($uninstallString -match '\{[0-9A-Fa-f-]+\}') {
            $productCode = [string]$Matches[0]
        }

        if ([string]::IsNullOrWhiteSpace($productCode)) {
            Write-Host "[LIVE-ADOBE] Desinstallation ignoree, code MSI introuvable : $displayName"
            [void]$results.Add([ordered]@{
                DisplayName = $displayName
                ProductCode = ''
                ExitCode = -1
                TimedOut = $false
                Message = 'Code MSI introuvable'
            })
            continue
        }

        Write-Host "[LIVE-ADOBE] Desinstallation silencieuse : $displayName ($productCode)"
        $result = Invoke-LDLCInstallerCommand `
            -CommandName 'msiexec.exe' `
            -ArgumentList @('/x', $productCode, '/qn', '/norestart') `
            -Label "Desinstallation $displayName" `
            -TimeoutSeconds 900

        [void]$results.Add([ordered]@{
            DisplayName = $displayName
            ProductCode = $productCode
            ExitCode = [int]$result.ExitCode
            TimedOut = [bool]$result.TimedOut
            Message = if ($result.TimedOut) { 'Timeout' } else { 'Termine' }
        })
    }

    Clear-LDLCDetectionCaches
    Start-Sleep -Seconds 5
    return @($results)
}

if (-not (Test-LDLCLiveTestAdmin) -and -not $NoElevate) {
    function ConvertTo-LDLCQuotedProcessArgument {
        param([Parameter(Mandatory = $true)][string]$Value)
        return '"' + ($Value -replace '"', '\"') + '"'
    }

    $args = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', (ConvertTo-LDLCQuotedProcessArgument -Value $PSCommandPath),
        '-NoElevate',
        '-ResultPath', (ConvertTo-LDLCQuotedProcessArgument -Value $ResultPath),
        '-LogPath', (ConvertTo-LDLCQuotedProcessArgument -Value $LogPath)
    )
    if ($UninstallFirst) { $args += '-UninstallFirst' }

    $resultDirectory = Split-Path -Parent $ResultPath
    if (-not (Test-Path -LiteralPath $resultDirectory)) {
        New-Item -ItemType Directory -Path $resultDirectory -Force | Out-Null
    }

    $process = Start-Process `
        -FilePath (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') `
        -ArgumentList ($args -join ' ') `
        -Verb RunAs `
        -WindowStyle Hidden `
        -Wait `
        -PassThru

    if ($process.ExitCode -ne 0) {
        throw "Test live Adobe termine avec le code $($process.ExitCode). Voir $LogPath"
    }

    if (Test-Path -LiteralPath $ResultPath) {
        Get-Content -LiteralPath $ResultPath -Raw
    }
    else {
        throw "Resultat absent apres test live Adobe : $ResultPath"
    }
    return
}

$resultDirectory = Split-Path -Parent $ResultPath
if (-not (Test-Path -LiteralPath $resultDirectory)) {
    New-Item -ItemType Directory -Path $resultDirectory -Force | Out-Null
}

Start-Transcript -LiteralPath $LogPath -Force | Out-Null
try {
    . (Join-Path $root 'modules\00.Core.ps1')
    Initialize-LDLCScriptState -ProjectRoot $root
    . (Join-Path $root 'modules\50.Cleanup.ps1')
    . (Join-Path $root 'modules\30.Applications.ps1')

    $script:StopFile = Join-Path $env:ProgramData 'LDLCPreparationPC\LDLC_STOP'
    $script:ProgressFile = Join-Path $env:ProgramData 'LDLCPreparationPC\LDLC_ADOBE_LIVE_PROGRESS.txt'
    $script:LDLCSuppressWriteProgress = $true

    $app = $Apps | Where-Object { $_.Name -eq 'Adobe Acrobat Reader' } | Select-Object -First 1
    if (-not $app) {
        throw 'Definition Adobe Acrobat Reader introuvable dans le catalogue.'
    }

    $before = ConvertTo-LDLCAdobeLiveState -App $app
    $uninstallResults = @()
    if ($UninstallFirst) {
        $uninstallResults = @(Invoke-LDLCAdobeUninstallForLiveTest)
    }

    Clear-LDLCDetectionCaches
    $afterUninstall = ConvertTo-LDLCAdobeLiveState -App $app
    Write-Host '[LIVE-ADOBE] Installation via flux officiel LDLC...'
    $installSuccess = Install-LDLCAppWithDirectInstaller -App $app
    Clear-LDLCDetectionCaches
    $afterInstall = ConvertTo-LDLCAdobeLiveState -App $app

    $result = [ordered]@{
        Timestamp = (Get-Date).ToString('o')
        IsAdmin = Test-LDLCLiveTestAdmin
        UninstallFirst = [bool]$UninstallFirst
        Before = $before
        UninstallResults = @($uninstallResults)
        AfterUninstall = $afterUninstall
        InstallSuccess = [bool]$installSuccess
        AfterInstall = $afterInstall
        Passed = [bool]($installSuccess -and $afterInstall.IsInstalled -and $afterInstall.HasExecutable)
        LogPath = $LogPath
    }

    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ResultPath -Encoding UTF8 -Force
    $result | ConvertTo-Json -Depth 8

    if (-not $result.Passed) {
        throw 'Le test live Adobe a echoue apres verification finale.'
    }
}
finally {
    Stop-Transcript | Out-Null
}
