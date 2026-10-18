$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$windowsUpdatePath = Join-Path $root 'modules\80.WindowsUpdate.ps1'
$windowsUpdate = Get-Content -LiteralPath $windowsUpdatePath -Raw -Encoding UTF8

if ($windowsUpdate -match 'Restart-Computer|shutdown\.exe|/r /t') {
    throw 'Windows Update ne doit pas redemarrer automatiquement.'
}

. (Join-Path $root 'modules\00.Core.ps1')
. $windowsUpdatePath

Initialize-LDLCScriptState -ProjectRoot $root

$script:MockSearchCalls = 0
$script:MockInstallCalls = 0
$script:MockRebootAfterInstall = $false

function Start-LDLCWindowsUpdateRequiredServices {
    [pscustomobject]@{
        Started = @('wuauserv')
        Running = @('wuauserv', 'bits', 'UsoSvc', 'DoSvc')
        Failed = @()
    }
}

function Invoke-LDLCDefenderSignatureUpdate { return $true }

function Test-LDLCWindowsPendingReboot {
    [pscustomobject]@{
        IsPending = $false
        Reasons = @()
    }
}

function New-LDLCWindowsUpdateSearchContext {
    [pscustomobject]@{
        Session = [pscustomobject]@{}
        Searcher = [pscustomobject]@{}
    }
}

function Get-LDLCWindowsUpdateCollection {
    param(
        $UpdateSearcher,
        [string]$Label
    )

    [void]$UpdateSearcher
    [void]$Label
    $script:MockSearchCalls++

    if ($script:MockSearchCalls -eq 1) {
        return [pscustomobject]@{
            Updates = @('KB-TEST-1', 'KB-TEST-2')
            DetectedCount = 2
        }
    }

    return [pscustomobject]@{
        Updates = @()
        DetectedCount = 0
    }
}

function Invoke-LDLCWindowsUpdateDownload {
    param(
        $UpdateSession,
        $Updates,
        [string]$Label,
        [int]$ProgressPercent
    )

    [void]$UpdateSession
    [void]$Label
    [void]$ProgressPercent
    return [pscustomobject]@{
        Updates = @($Updates)
        RebootRequired = $false
        DownloadedCount = @($Updates).Count
    }
}

function Invoke-LDLCWindowsUpdateInstall {
    param(
        $UpdateSession,
        $Updates,
        [string]$Label,
        [int]$ProgressPercent
    )

    [void]$UpdateSession
    [void]$Label
    [void]$ProgressPercent
    $script:MockInstallCalls++

    return [pscustomobject]@{
        ResultCode = 2
        RebootRequired = [bool]$script:MockRebootAfterInstall
        InstalledCount = @($Updates).Count
        WarningCount = 0
        FailedCount = 0
        IgnoredFailureCount = 0
    }
}

$env:LDLC_WU_POST_CYCLE_DELAY_SECONDS = '3'
$result = Invoke-LDLCWindowsUpdateFullMaintenance -StartPercent 5 -EndPercent 7 -MaxCycles 3

if (-not $result.Success -or -not $result.Completed -or $result.RebootRequired -or $result.Count -ne 2 -or $result.CycleCount -ne 2) {
    throw "Boucle Windows Update incorrecte : $($result | ConvertTo-Json -Compress -Depth 5)"
}

if ($script:MockSearchCalls -ne 2 -or $script:MockInstallCalls -ne 1) {
    throw "Cycles attendus incorrects : search=$script:MockSearchCalls install=$script:MockInstallCalls"
}

$script:MockSearchCalls = 0
$script:MockInstallCalls = 0
$script:MockRebootAfterInstall = $true
$script:PendingReboot = $false

$rebootResult = Invoke-LDLCWindowsUpdateFullMaintenance -StartPercent 5 -EndPercent 7 -MaxCycles 3
if (-not $rebootResult.Success -or $rebootResult.Completed -or -not $rebootResult.RebootRequired -or -not $script:PendingReboot) {
    throw "Redemarrage requis mal gere : $($rebootResult | ConvertTo-Json -Compress -Depth 5)"
}

Write-Host 'OK Windows Update full loop'
