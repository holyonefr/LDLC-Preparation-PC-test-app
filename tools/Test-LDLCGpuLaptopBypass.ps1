#requires -Version 5.1
param([string]$ModuleRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'modules'))
$ErrorActionPreference = 'Stop'
. (Join-Path $ModuleRoot '60.Gpu.ps1')
$script:checks = 0; $script:cases = 0
function Assert($Value, $Reason) { $script:checks++; if (-not $Value) { throw $Reason } }
function Stop-IfRequested { if ($script:cancel) { throw [OperationCanceledException]::new('test stop') } }
function Test-LDLCStopRequestError($ErrorRecord) { return $ErrorRecord.Exception -is [OperationCanceledException] }
function Write-Step($Text) { $script:messages += $Text }
function Write-Section($Text) { }
function Write-ProgressFile($Percent, $Text) { }
function Write-Ok($Text) { }
function Write-Info($Text) { }
function Write-Warn($Text) { $script:warnings++ }
function Write-Err($Text) { $script:errors += $Text }
function Get-CimInstance($ClassName) {
    if ($script:cimFailure) { throw 'simulated CIM failure' }
    if ($ClassName -eq 'Win32_ComputerSystem') { return [pscustomobject]@{ PCSystemType = $script:pcType } }
    if ($ClassName -eq 'Win32_SystemEnclosure') { return [pscustomobject]@{ ChassisTypes = $script:chassis } }
    throw "Unexpected hardware query: $ClassName"
}
function Get-WmiObject($Class) {
    if ($script:wmiFailure) { throw 'simulated WMI failure' }
    if ($Class -eq 'Win32_ComputerSystem') { return [pscustomobject]@{ PCSystemType = $script:pcType } }
    if ($Class -eq 'Win32_SystemEnclosure') { return [pscustomobject]@{ ChassisTypes = $script:chassis } }
    throw "Unexpected hardware query: $Class"
}
function Get-LDLCGpuAdapters { return $script:adapters }
function Resolve-LDLCAmdGpuOfficialSource { $script:sourceCalls++; throw 'desktop-source-boundary' }
function Install-LDLCNvidiaStack { param($StartPercent,$GpuName,$PnpDeviceId,[switch]$Professional) $script:nvidiaCalls++ }
function Reset-Case {
    $script:cases++; $script:pcType = 1; $script:chassis = @(3)
    $script:cimFailure = $false; $script:wmiFailure = $false; $script:cancel = $false
    $script:sourceCalls = 0; $script:nvidiaCalls = 0; $script:warnings = 0; $script:errors = @(); $script:messages = @()
    $script:adapters = @([pscustomobject]@{ Name = 'AMD Radeon Graphics'; AdapterCompatibility = 'AMD'; PNPDeviceID = 'PCI\VEN_1002&DEV_1234'; Status = 'OK'; ConfigManagerErrorCode = 0 })
}
foreach ($chassisType in @(8,9,10,11,14,30,31,32)) {
    Reset-Case; $script:chassis = @($chassisType)
    Install-LDLCAmdStack
    Assert ($script:sourceCalls -eq 0 -and $script:errors.Count -eq 0 -and $script:warnings -eq 0) "Portable chassis $chassisType must skip AMD without a network request or failure."
}
Reset-Case; $script:pcType = 2; $script:chassis = @(0)
Install-LDLCAmdStack
Assert ($sourceCalls -eq 0) 'Mobile system type must skip AMD even with missing chassis/battery.'
Reset-Case; Install-LDLCAmdStack
Assert ($sourceCalls -eq 1 -and $errors[0] -match 'desktop-source-boundary') 'Desktop must still enter the original AMD download path.'
Reset-Case; $script:pcType = 3; $script:chassis = @(13)
Install-LDLCAmdStack
Assert ($sourceCalls -eq 1) 'Desktop workstation/all-in-one must not be classified from GPU name or battery/UPS.'
Reset-Case; $script:pcType = 0; $script:chassis = @()
Install-LDLCAmdStack
Assert ($sourceCalls -eq 0 -and $errors.Count -eq 0 -and $warnings -eq 0) 'Unknown form factor must skip with information, never guess desktop.'
Reset-Case; $script:cimFailure = $true; $script:pcType = 2
Install-LDLCAmdStack
Assert ($sourceCalls -eq 0) 'WMI mobile fallback must skip AMD.'
Reset-Case; $script:cimFailure = $true
Install-LDLCAmdStack
Assert ($sourceCalls -eq 1) 'WMI desktop fallback must preserve AMD.'
Reset-Case; $script:cimFailure = $true; $script:wmiFailure = $true
Install-LDLCAmdStack
Assert ($sourceCalls -eq 0 -and $errors.Count -eq 0) 'Failed hardware reads must never launch AMD blindly.'
Reset-Case; $script:pcType = 2
$script:adapters += [pscustomobject]@{ Name = 'NVIDIA GeForce RTX 4060 Laptop GPU'; AdapterCompatibility = 'NVIDIA'; PNPDeviceID = 'PCI\VEN_10DE&DEV_5678'; Status = 'OK'; ConfigManagerErrorCode = 0 }
Install-LDLCGpuDriversAndApps
Assert ($sourceCalls -eq 0 -and $nvidiaCalls -eq 1) 'Hybrid laptop must keep NVIDIA while skipping AMD.'
Reset-Case; $script:cancel = $true; $stopped = $false
try { Install-LDLCAmdStack } catch { $stopped = Test-LDLCStopRequestError $_ }
Assert ($stopped -and $sourceCalls -eq 0) 'Cancellation must propagate before download.'
$result = @{ Cases = $cases; Assertions = $checks; Failures = 0; Mode = 'simulated SMBIOS and GPU boundaries; no driver installed'; PortableNetworkRequests = 0; NvidiaPreserved = $true }
Write-Host ('::notice title=AMD laptop bypass::' + ($result | ConvertTo-Json -Compress))
