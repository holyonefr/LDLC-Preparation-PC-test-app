$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'modules\60.Gpu.ps1')

$script:MockGpuControllers = @()
$script:MockPnpDevices = @()
$script:FailCim = $false
$script:AmdInstallCalled = $false
$script:NvidiaInstallCalled = $false
$script:GpuSteps = New-Object System.Collections.Generic.List[string]

function Stop-IfRequested {}
function Write-Section { param([string]$Text) [void]$script:GpuSteps.Add("SECTION:$Text") }
function Write-ProgressFile { param([int]$Percent, [string]$Message) [void]$script:GpuSteps.Add(("PROGRESS:{0}:{1}" -f $Percent, $Message)) }
function Write-Step { param([string]$Text) [void]$script:GpuSteps.Add($Text) }
function Write-Ok { param([string]$Text) [void]$script:GpuSteps.Add("OK:$Text") }
function Write-Warn { param([string]$Text) [void]$script:GpuSteps.Add("WARN:$Text") }
function Write-Err { param([string]$Text) throw $Text }

function Get-CimInstance {
    param([string]$ClassName)

    if ($script:FailCim) { throw 'CIM simulated failure' }
    if ($ClassName -eq 'Win32_Processor') { throw 'CPU must never decide GPU vendor' }
    if ($ClassName -eq 'Win32_PnPEntity') { return @($script:MockPnpDevices) }
    if ($ClassName -eq 'Win32_VideoController') {
        return @($script:MockGpuControllers)
    }

    return @()
}

function Get-WmiObject {
    param([string]$Class)

    if ($Class -eq 'Win32_Processor') { throw 'CPU must never decide GPU vendor' }
    if ($Class -eq 'Win32_PnPEntity') { return @($script:MockPnpDevices) }
    if ($Class -eq 'Win32_VideoController') {
        return @($script:MockGpuControllers)
    }

    return @()
}

function Install-LDLCAmdStack {
    param([int]$StartPercent = 84)
    $script:AmdInstallCalled = $true
    $script:AmdStartPercent = $StartPercent
}

function Install-LDLCNvidiaStack {
    param($StartPercent, $GpuName, $PnpDeviceId, [switch]$Professional)
    $script:NvidiaInstallCalled = $true
    $script:NvidiaProfessional = [bool]$Professional
}

$script:MockGpuControllers = @(
    [pscustomobject]@{
        Name = 'Intel(R) UHD Graphics'
        AdapterCompatibility = 'Intel Corporation'
        PNPDeviceID = 'PCI\VEN_8086&DEV_9A49'
    },
    [pscustomobject]@{
        Name = 'AMD Radeon(TM) Graphics'
        AdapterCompatibility = 'Advanced Micro Devices, Inc.'
        PNPDeviceID = 'PCI\VEN_1002&DEV_164E&SUBSYS_00000000'
    }
)

Install-LDLCGpuDriversAndApps -ProgressPercent 88

if (-not $script:AmdInstallCalled) {
    throw 'AMD Radeon(TM) Graphics doit declencher Install-LDLCAmdStack.'
}

if ($script:NvidiaInstallCalled) {
    throw 'Le test AMD ne doit pas declencher NVIDIA.'
}

if (-not (@($script:GpuSteps.ToArray()) -match 'GPU AMD integre pris en charge')) {
    throw 'Le log doit indiquer que le GPU AMD integre est pris en charge.'
}

$script:AmdInstallCalled = $false
$script:NvidiaInstallCalled = $false
$script:GpuSteps.Clear()
$script:MockGpuControllers = @(
    [pscustomobject]@{
        Name = 'Intel(R) Iris Xe Graphics'
        AdapterCompatibility = 'Intel Corporation'
        PNPDeviceID = 'PCI\VEN_8086&DEV_46A6'
    }
)

Install-LDLCGpuDriversAndApps -ProgressPercent 88

if ($script:AmdInstallCalled -or $script:NvidiaInstallCalled) {
    throw 'Un GPU Intel seul ne doit pas declencher AMD/NVIDIA.'
}

function Test-GpuRouting {
    param([string]$Label, [object[]]$Controllers, [object[]]$PnpDevices = @(), [bool]$Amd = $false, [bool]$Nvidia = $false, [bool]$Professional = $false)
    $script:MockGpuControllers = $Controllers
    $script:MockPnpDevices = $PnpDevices
    $script:AmdInstallCalled = $false
    $script:NvidiaInstallCalled = $false
    $script:NvidiaProfessional = $false
    $script:GpuSteps.Clear()
    Install-LDLCGpuDriversAndApps -ProgressPercent 88
    if ($script:AmdInstallCalled -ne $Amd -or $script:NvidiaInstallCalled -ne $Nvidia -or $script:NvidiaProfessional -ne $Professional) {
        throw "Wrong GPU routing: $Label"
    }
    if (@($script:GpuSteps | Where-Object { $_ -match '^WARN:|^ERR:' }).Count) { throw "Non-applicable error: $Label" }
    Write-Host "OK $Label"
}

$amdBasic = [pscustomobject]@{ Name = 'Microsoft Basic Display Adapter'; AdapterCompatibility = 'Microsoft'; PNPDeviceID = 'PCI\VEN_1002&DEV_164E' }
$nvidia = [pscustomobject]@{ Name = 'NVIDIA GeForce RTX 5070'; PNPDeviceID = 'PCI\VEN_10DE&DEV_1ABC' }
$intel = [pscustomobject]@{ Name = 'Intel UHD Graphics'; PNPDeviceID = 'PCI\VEN_8086&DEV_1234' }
Test-GpuRouting -Label 'AMD basic display via PCI' -Controllers @($amdBasic) -Amd $true
Test-GpuRouting -Label 'NVIDIA plus AMD iGPU' -Controllers @($nvidia, $amdBasic) -Amd $true -Nvidia $true
Test-GpuRouting -Label 'Intel plus NVIDIA, even on Ryzen CPU' -Controllers @($intel, $nvidia) -Nvidia $true
Test-GpuRouting -Label 'No GPU' -Controllers @()
Test-GpuRouting -Label 'Non-GPU AMD PCI vendor excluded' -Controllers @([pscustomobject]@{ Name = 'AMD'; PNPDeviceID = 'PCI\VEN_1022&DEV_1234' })
Test-GpuRouting -Label 'SUBSYS AMD is not GPU vendor' -Controllers @([pscustomobject]@{ Name = 'AMD Radeon'; PNPDeviceID = 'PCI\VEN_8086&DEV_1234&SUBSYS_00001002' })
Test-GpuRouting -Label 'Unknown PCI vendor overrides AMD friendly name' -Controllers @([pscustomobject]@{ Name = 'AMD Radeon'; PNPDeviceID = 'PCI\VEN_1234&DEV_1234' })
Test-GpuRouting -Label 'ATI word is not part of unrelated name' -Controllers @([pscustomobject]@{ Name = 'Virtual Station Display'; PNPDeviceID = 'ROOT\DISPLAY' })
Test-GpuRouting -Label 'Adapter fallback without PCI ID' -Controllers @([pscustomobject]@{ Name = 'Radeon Graphics'; AdapterCompatibility = 'Advanced Micro Devices, Inc.'; PNPDeviceID = '' }) -Amd $true
Test-GpuRouting -Label 'NVIDIA professional retained' -Controllers @([pscustomobject]@{ Name = 'NVIDIA RTX A4000'; PNPDeviceID = 'PCI\VEN_10DE&DEV_1234' }) -Nvidia $true -Professional $true
Test-GpuRouting -Label 'PnP display fallback, chipset excluded' -Controllers @() -PnpDevices @(
    [pscustomobject]@{ Name = 'AMD Chipset'; PNPDeviceID = 'PCI\VEN_1022&DEV_1234'; PNPClass = 'System'; Present = $true },
    [pscustomobject]@{ Name = 'Microsoft Basic Display Adapter'; PNPDeviceID = 'PCI\VEN_1002&DEV_164E'; PNPClass = 'Display'; Present = $true }
) -Amd $true
Test-GpuRouting -Label 'Disconnected Radeon ignored' -Controllers @() -PnpDevices @(
    [pscustomobject]@{ Name = 'Radeon'; PNPDeviceID = 'PCI\VEN_1002&DEV_164E'; PNPClass = 'Display'; Present = $false }
)
$script:FailCim = $true
Test-GpuRouting -Label 'WMI fallback preserves mixed GPUs' -Controllers @($amdBasic, $nvidia) -Amd $true -Nvidia $true
Write-Host 'OK AMD GPU routing: 15 scenarios'
