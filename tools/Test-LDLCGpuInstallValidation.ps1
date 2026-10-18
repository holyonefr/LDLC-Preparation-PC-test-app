$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'modules\60.Gpu.ps1')

function Assert-LDLCCondition {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Write-Step { param([string]$Text) }
function Write-Info { param([string]$Text) }
function Write-Ok { param([string]$Text) }
function Write-Warn { param([string]$Text) }
function Write-Err { param([string]$Text) throw $Text }
function Stop-IfRequested {}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('LDLC-GpuValidation-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
$amdExe = Join-Path $tempRoot 'AMDSoftware.exe'
[System.IO.File]::WriteAllBytes($amdExe, [byte[]](1..16))

try {
    function Get-LDLCExistingExePathByNames {
        param($ExePaths, $SearchFolders, $ExeNames)
        # Never consult software installed on the test host.
        foreach ($path in $ExePaths) {
            if ($path -and $path.StartsWith($tempRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase) -and
                (Test-Path -LiteralPath $path -PathType Leaf)) { return $path }
        }
        return $null
    }
    $script:MockPrograms = @(
        [pscustomobject]@{
            DisplayName = 'AMD Software: Adrenalin Edition'
            DisplayVersion = '26.6.4'
            Publisher = 'Advanced Micro Devices, Inc.'
            InstallLocation = $tempRoot
            DisplayIcon = '"' + $amdExe + '",0'
        }
    )

    function Get-LDLCInstalledPrograms {
        param([switch]$Refresh)
        [void]$Refresh
        return @($script:MockPrograms)
    }

    $amd = Get-LDLCAmdSoftwareInstallation -Refresh
    Assert-LDLCCondition ($null -ne $amd) 'AMD Adrenalin doit etre detecte avec le registre et AMDSoftware.exe.'
    Assert-LDLCCondition ($amd.ExePath -eq $amdExe) 'La validation AMD doit privilegier l executable indique par DisplayIcon.'
    Assert-LDLCCondition ($amd.DetectedBy -eq 'Registry+Executable') 'La detection AMD doit confirmer registre et executable.'
    Assert-LDLCCondition ([bool]$amd.RegistryPresent -and [bool]$amd.ExecutablePresent) 'Les preuves AMD doivent etre explicites.'

    $script:MockPrograms = @(
        [pscustomobject]@{
            DisplayName = 'AMD Software: PRO Edition'
            DisplayVersion = '26.6.4'
            Publisher = 'Advanced Micro Devices, Inc.'
            InstallLocation = $tempRoot
            DisplayIcon = '"' + $amdExe + '",0'
        }
    )
    $amdPro = Get-LDLCAmdSoftwareInstallation -Refresh
    Assert-LDLCCondition ($null -eq $amdPro) 'AMD Software PRO Edition ne doit pas etre confondu avec Adrenalin.'

    $amdDefinition = Get-LDLCAmdAdrenalinInstallerDefinition
    Assert-LDLCCondition ([bool]$amdDefinition.CacheDownloaded) 'Le package AMD complet doit etre conserve dans le cache local.'
    Assert-LDLCCondition (@($amdDefinition.CachePatterns -match 'whql-amd-software-adrenalin-edition').Count -gt 0) 'Le cache AMD doit cibler le package WHQL complet.'
    Assert-LDLCCondition ([int]$amdDefinition.ValidationTimeoutSeconds -ge 600) 'AMD doit attendre la finalisation des sous-processus avant la validation.'

    Assert-LDLCCondition (Test-LDLCVersionAtLeast -InstalledVersion '32.0.16.1074' -RequiredVersion '610.74' -NvidiaDriver) 'Le pilote NVIDIA WMI 32.0.16.1074 doit correspondre a Game Ready 610.74.'
    Assert-LDLCCondition (-not (Test-LDLCVersionAtLeast -InstalledVersion '32.0.16.1047' -RequiredVersion '610.74' -NvidiaDriver)) 'Un pilote NVIDIA plus ancien ne doit pas etre considere a jour.'

    $gpuSource = Get-Content -LiteralPath (Join-Path $root 'modules\60.Gpu.ps1') -Raw -Encoding UTF8
    Assert-LDLCCondition ($gpuSource -match 'Resolve-LDLCNvidiaDriverOfficialSources') 'La pile NVIDIA doit resoudre la version officielle avant de decider un skip.'
    Assert-LDLCCondition ($gpuSource -match "'geforce-game-ready-driver'") 'Le fallback NVIDIA Game Ready Chocolatey doit rester disponible apres l officiel.'
    Assert-LDLCCondition ($gpuSource -match "'upgrade', 'geforce-game-ready-driver'") 'Le fallback NVIDIA doit demander une mise a jour, pas seulement verifier une ancienne version.'

    $script:MockNvidiaDriverVersion = '32.0.16.1047'
    $script:NvidiaOfficialInstallCalled = $false
    $script:NvidiaTargetVersion = ''
    $script:NvidiaAppEnsureCalled = 0
    function Write-ProgressFile { param([int]$Percent, [string]$Message) }
    function Get-LDLCInstalledVendorDisplayDriver {
        param([string]$Vendor)
        if ($Vendor -eq 'NVIDIA') {
            return [pscustomobject]@{ DriverVersion = $script:MockNvidiaDriverVersion }
        }
        return $null
    }
    function Get-LDLCDriverVersion { param([string]$Vendor) return $script:MockNvidiaDriverVersion }
    function Get-LDLCNvidiaSmiDriverVersion { return '' }
    function Test-LDLCForceGpuDriverInstall { return $false }
    function Resolve-LDLCNvidiaDriverOfficialSources {
        param($Context)
        [void]$Context
        return @([pscustomobject]@{ Url = 'https://download.nvidia.com/test-driver.exe'; Version = '610.74' })
    }
    function Install-LDLCNvidiaDriverOfficial {
        param($GpuName, $PnpDeviceId, $Professional, $ProgressPercent, $TargetVersion, $OfficialSources, [switch]$QuietFailure)
        [void]$GpuName; [void]$PnpDeviceId; [void]$Professional; [void]$ProgressPercent; [void]$OfficialSources; [void]$QuietFailure
        $script:NvidiaOfficialInstallCalled = $true
        $script:NvidiaTargetVersion = [string]$TargetVersion
        return $true
    }
    function Install-LDLCNvidiaAppIfNeeded {
        param([int]$ProgressPercent)
        [void]$ProgressPercent
        $script:NvidiaAppEnsureCalled++
        return $true
    }
    function Ensure-LDLCGpuDesktopShortcut { param([string]$Vendor) }

    Install-LDLCNvidiaStack -StartPercent 84 -GpuName 'NVIDIA GeForce GTX Test' -PnpDeviceId 'PCI\VEN_10DE&DEV_1ABC'
    Assert-LDLCCondition $script:NvidiaOfficialInstallCalled 'Un pilote NVIDIA plus ancien doit declencher une mise a jour officielle.'
    Assert-LDLCCondition ($script:NvidiaTargetVersion -eq '610.74') 'La mise a jour NVIDIA doit recevoir la version officielle cible.'
    Assert-LDLCCondition ($script:NvidiaAppEnsureCalled -eq 1) 'NVIDIA App doit etre verifiee apres la mise a jour du pilote.'

    $script:MockNvidiaDriverVersion = '32.0.16.1074'
    $script:NvidiaOfficialInstallCalled = $false
    $script:NvidiaAppEnsureCalled = 0
    Install-LDLCNvidiaStack -StartPercent 84 -GpuName 'NVIDIA GeForce GTX Test' -PnpDeviceId 'PCI\VEN_10DE&DEV_1ABC'
    Assert-LDLCCondition (-not $script:NvidiaOfficialInstallCalled) 'Un pilote NVIDIA deja a jour ne doit pas etre reinstalle.'
    Assert-LDLCCondition ($script:NvidiaAppEnsureCalled -eq 1) 'NVIDIA App doit rester verifiee meme quand le pilote est deja a jour.'

    Write-Host 'OK AMD validation and NVIDIA version update logic'
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        $expectedParent = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd([char[]]@('\','/')) + [System.IO.Path]::DirectorySeparatorChar
        if (-not [System.IO.Path]::GetFullPath($tempRoot).StartsWith($expectedParent, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw 'Unsafe test cleanup path'
        }
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
