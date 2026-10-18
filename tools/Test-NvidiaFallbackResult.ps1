param([string]$ModuleRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'modules'))
$ErrorActionPreference = 'Stop'
. (Join-Path $ModuleRoot '60.Gpu.ps1')
$script:checks = 0
function Assert([bool]$Condition, [string]$Reason) { $script:checks++; if (-not $Condition) { throw $Reason } }
function choco {}
function Write-Step { param($Message) }
function Write-Info { param($Message) }
function Write-Ok { param($Message) }
function Write-Warn { param($Message) $script:warnings++ }
function Clear-LDLCDetectionCaches {}
function Get-LDLCInstalledVendorDisplayDriver { param($Vendor) return [pscustomobject]@{DriverVersion=$script:observed} }
function Get-LDLCNvidiaSmiDriverVersion { return '' }
function Test-LDLCStopRequestError { param($ErrorRecord) return ($ErrorRecord.Exception.Message -eq 'LDLC_STOP_REQUESTED') }
function Invoke-LDLCInstallerCommand {
    param($CommandName, $ArgumentList, $Label, $TimeoutSeconds)
    $script:arguments = $ArgumentList
    if ($script:cancel) { throw 'LDLC_STOP_REQUESTED' }
    return [pscustomobject]@{ExitCode=$script:exit;TimedOut=$script:timeout}
}
foreach ($case in @(
    @{Name='updated';Code=0;Timeout=$false;Target='620.77';Version='32.0.16.2077';Expected=$true;Reboot=$false},
    @{Name='error1603-existing-driver';Code=1603;Timeout=$false;Target='620.77';Version='32.0.16.2077';Expected=$false;Reboot=$false},
    @{Name='timeout-existing-driver';Code=0;Timeout=$true;Target='620.77';Version='32.0.16.2077';Expected=$false;Reboot=$false},
    @{Name='restart3010';Code=3010;Timeout=$false;Target='620.77';Version='32.0.16.2077';Expected=$true;Reboot=$true},
    @{Name='restart1641';Code=1641;Timeout=$false;Target='620.77';Version='32.0.16.2077';Expected=$true;Reboot=$true},
    @{Name='unknown-target';Code=0;Timeout=$false;Target='';Version='32.0.16.2077';Expected=$false;Reboot=$false},
    @{Name='unchanged-old-driver';Code=0;Timeout=$false;Target='620.77';Version='32.0.16.1047';Expected=$false;Reboot=$false}
)) {
    $script:exit=$case.Code; $script:timeout=$case.Timeout; $script:observed=$case.Version
    $script:PendingReboot=$false; $script:warnings=0; $script:cancel=$false
    $actual=Invoke-LDLCNvidiaGameReadyChocolateyFallback -TargetVersion $case.Target -PreviousDriverVersion '610.47'
    Assert ($actual -eq $case.Expected) "$($case.Name): invalid success result."
    Assert ($script:PendingReboot -eq $case.Reboot) "$($case.Name): reboot state lost."
    if ($case.Reboot) { Assert ($script:warnings -eq 1) "$($case.Name): missing restart warning." }
    Assert ($script:arguments[0] -eq 'upgrade' -and $script:arguments -notcontains '--ignore-checksums') "$($case.Name): update/checksum contract changed."
}
$script:cancel=$true; $cancelled=$false
try { Invoke-LDLCNvidiaGameReadyChocolateyFallback -TargetVersion '620.77' | Out-Null }
catch { $cancelled=Test-LDLCStopRequestError $_ }
Assert $cancelled 'Cancellation was swallowed by NVIDIA fallback.'
Write-Host "OK NVIDIA fallback: $script:checks assertions, 8 scenarios; no actual installation."
