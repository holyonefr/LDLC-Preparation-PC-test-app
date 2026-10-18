$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'modules\60.Gpu.ps1')

$script:Assertions = 0
function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
    $script:Assertions++
}
function Assert-Throws {
    param([scriptblock]$Action, [string]$Pattern)
    $failure = $null
    try { & $Action | Out-Null } catch { $failure = $_.Exception.Message }
    Assert-True ($failure -and $failure -match $Pattern) "Expected '$Pattern', got '$failure'"
}
function Stop-IfRequested { if ($script:Cancel) { throw 'simulated cancellation' } }
function Test-LDLCStopRequestError($ErrorRecord) { return ($ErrorRecord.Exception.Message -match 'simulated cancellation') }
function Write-Step { param($Text) }
function Write-Info { param($Text) }
function Write-Warn { param($Text) $script:Warnings += [string]$Text }
function Write-Ok { param($Text) $script:Messages += [string]$Text }
function Write-Err { param($Text) throw $Text }
function Write-ProgressFile { param($Percent, $Message) }
function Clear-LDLCDetectionCaches {}
function Ensure-LDLCGpuDesktopShortcut { param($Vendor) $script:Shortcuts++ }
function Get-Date { return ([datetime]'2026-01-01T00:00:00Z').AddSeconds($script:Elapsed) }
function Start-Sleep {
    param([int]$Seconds, [int]$Milliseconds)
    $script:Elapsed += $Seconds + ($Milliseconds / 1000.0)
}
function Get-AuthenticodeSignature {
    param($LiteralPath)
    if ($script:SignatureThrows) { throw 'trust unavailable' }
    return [pscustomobject]@{ Status = $script:SignatureStatus; SignerCertificate = [pscustomobject]@{ Subject = $script:Signer } }
}
function Write-FakePe {
    param([string]$Path)
    $bytes = New-Object byte[] 128
    $bytes[0] = 0x4D; $bytes[1] = 0x5A; $bytes[0x3C] = 0x40
    $bytes[0x40] = 0x50; $bytes[0x41] = 0x45
    [System.IO.File]::WriteAllBytes($Path, $bytes)
}
function Invoke-WebRequest {
    param($Uri, $Headers, $OutFile, $TimeoutSec, [switch]$UseBasicParsing)
    if ($script:NetworkFailure) { throw 'simulated network failure' }
    if (-not $OutFile) {
        Assert-True ($Headers['Cache-Control'] -eq 'no-cache' -and $Headers.Pragma -eq 'no-cache') 'La recherche AMD doit demander la page actuelle.'
        $script:PageReads++
        return [pscustomobject]@{ Content = $script:Page }
    }
    $script:DownloadedUrls += [string]$Uri
    Assert-True ($Headers.Referer -eq 'https://www.amd.com/en/support/download/drivers.html') 'AMD download needs the official Referer'
    $script:Downloaded++
    if ($script:HtmlDownload) { [System.IO.File]::WriteAllText($OutFile, '<html>Download incomplete</html>') }
    else { Write-FakePe -Path $OutFile }
}
function Get-CimInstance {
    param($ClassName)
    switch ($ClassName) {
        'Win32_VideoController' { return $script:Adapters }
        'Win32_PnPEntity' { return @() }
        'Win32_PnPSignedDriver' {
            $script:DriverReads++
            if ($script:Elapsed -lt $script:DriverReadyAt) { return @() }
            return $script:Drivers
        }
        'Win32_Process' {
            # This unrelated setup must never be waited on or terminated.
            [pscustomobject]@{ ProcessId = 80; ParentProcessId = 1; Name = 'Setup.exe'; ExecutablePath = 'C:\Other\Setup.exe' }
            if ($script:Started -and $script:Elapsed -lt $script:RootExitAt) {
                [pscustomobject]@{ ProcessId = 100; ParentProcessId = 1; Name = 'bootstrap.exe'; ExecutablePath = 'C:\Temp\bootstrap.exe' }
            }
            if ($script:Started -and $script:Elapsed -ge $script:ChildStartsAt -and $script:Elapsed -lt $script:ChildEndsAt) {
                [pscustomobject]@{ ProcessId = 101; ParentProcessId = $script:ChildParent; Name = $script:ChildName; ExecutablePath = $script:ChildPath }
            }
            return
        }
        default { throw "Unexpected hardware query (host isolation): $ClassName" }
    }
}
function Get-WmiObject { param($Class) throw "Unexpected real WMI fallback: $Class" }
function Start-Process {
    param($FilePath, $ArgumentList, $WindowStyle, [switch]$PassThru)
    Assert-True ($WindowStyle -eq 'Hidden' -and $PassThru -and $ArgumentList -contains '-install') 'Preserve unattended AMD launch'
    Assert-True (-not ($ArgumentList -match '(?i)boot|reset|uninstall')) 'No forced restart or destructive reset'
    $script:Started = $true
    $script:Launches++
    $p = [pscustomobject]@{ Id = 100; ExitCode = $script:ExitCode }
    $p | Add-Member ScriptProperty HasExited { return $script:Elapsed -ge $script:RootExitAt }
    $p | Add-Member ScriptMethod WaitForExit { if (-not $this.HasExited) { throw 'Premature wait' } }
    $p | Add-Member ScriptMethod Dispose {}
    return $p
}
function Get-LDLCAmdSoftwareInstallation {
    param([switch]$Refresh)
    $script:SoftwareReads++
    if ($script:SoftwarePresent) {
        return [pscustomobject]@{ DisplayName = 'AMD Software: Adrenalin Edition'; DisplayVersion = '1.0.0'; ExePath = 'C:\Fake\AMDSoftware.exe' }
    }
    return $null
}
$script:Definition = Get-LDLCAmdAdrenalinInstallerDefinition
$script:Definition.MinBytes = 64
$script:Definition.TimeoutSeconds = 20
$script:Definition.PostInstallSettleSeconds = 3
$script:Definition.ValidationTimeoutSeconds = 6
function Get-LDLCAmdAdrenalinInstallerDefinition { return $script:Definition }

function Reset-Scenario {
    $script:Elapsed = 0.0
    $script:Started = $false
    $script:Launches = 0
    $script:Shortcuts = 0
    $script:Downloaded = 0
    $script:DownloadedUrls = @()
    $script:PageReads = 0
    $script:DriverReads = 0
    $script:SoftwareReads = 0
    $script:RootExitAt = 1
    $script:ChildStartsAt = 2
    $script:ChildEndsAt = 8
    $script:ChildParent = 100
    $script:ChildName = 'worker.exe'
    $script:ChildPath = 'C:\Temp\worker.exe'
    $script:ExitCode = 0
    $script:PendingReboot = $false
    $script:DriverReadyAt = 0
    $script:SoftwarePresent = $true
    $script:NetworkFailure = $false
    $script:HtmlDownload = $false
    $script:Cancel = $false
    $script:SignatureThrows = $false
    $script:SignatureStatus = 'Valid'
    $script:Signer = 'CN="Advanced Micro Devices, Inc.", O="Advanced Micro Devices, Inc.", C=US'
    $script:Messages = @()
    # Deliberately fictional versions; neither is a pinned production URL.
    $script:Page = '<a href="https://drivers.amd.com/drivers/installer/whql/amd-software-adrenalin-edition-99.1.1-minimalsetup-990101_web.exe">Download</a>'
    $script:Adapters = @([pscustomobject]@{ Name = 'AMD Radeon Graphics'; PNPDeviceID = 'PCI\VEN_1002&DEV_164E'; ConfigManagerErrorCode = 0 })
    $script:Drivers = @([pscustomobject]@{
        DeviceID = 'PCI\VEN_1002&DEV_164E'; DeviceClass = 'DISPLAY'; IsSigned = $true
        DriverProviderName = 'Advanced Micro Devices, Inc.'; InfName = 'oem12.inf'; DriverVersion = '32.0.1.2'
    })
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('LDLC-GpuAmdFlow-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot | Out-Null
try {
    Reset-Scenario
    $exe = Join-Path $tempRoot 'fixture.exe'
    Write-FakePe $exe
    Assert-True (Test-LDLCAmdGpuInstallerFile $exe -MinBytes 64) 'Valid AMD PE fixture'
    $script:Signer = 'CN=Advanced Micro Devices, O=Advanced Micro Devices, S=California, C=US'
    Assert-True (Test-LDLCAmdGpuInstallerFile $exe -MinBytes 64) 'Current official AMD certificate without Inc suffix'
    Assert-True (-not (Test-LDLCAmdGpuInstallerFile $exe)) 'Production minimum rejects a tiny executable'
    foreach ($status in @('NotSigned', 'HashMismatch', 'NotTrusted', 'UnknownError')) {
        $script:SignatureStatus = $status
        Assert-True (-not (Test-LDLCAmdGpuInstallerFile $exe -MinBytes 64)) "Reject $status"
    }
    $script:SignatureStatus = 'Valid'
    $script:Signer = 'CN=Someone AMD Else, O=Advanced Micro Devices Inc.'
    Assert-True (-not (Test-LDLCAmdGpuInstallerFile $exe -MinBytes 64)) 'Wrong signer cannot use AMD in its organization/name'
    Reset-Scenario
    $script:SignatureThrows = $true
    Assert-True (-not (Test-LDLCAmdGpuInstallerFile $exe -MinBytes 64)) 'Unavailable signature is not a pass'
    Reset-Scenario
    [System.IO.File]::WriteAllBytes($exe, [byte[]]@())
    Assert-True (-not (Test-LDLCAmdGpuInstallerFile $exe -MinBytes 64)) 'Reject empty file'
    [System.IO.File]::WriteAllText($exe, ('<html>not an executable</html>' * 10))
    Assert-True (-not (Test-LDLCAmdGpuInstallerFile $exe -MinBytes 64)) 'Reject HTML masquerading as EXE'
    Write-FakePe $exe
    $bytes = [System.IO.File]::ReadAllBytes($exe); $bytes[0x40] = 0
    [System.IO.File]::WriteAllBytes($exe, $bytes)
    Assert-True (-not (Test-LDLCAmdGpuInstallerFile $exe -MinBytes 64)) 'MZ alone is insufficient'
    Write-FakePe $exe
    $bytes = [System.IO.File]::ReadAllBytes($exe); $bytes[0x3C] = 255
    [System.IO.File]::WriteAllBytes($exe, $bytes)
    Assert-True (-not (Test-LDLCAmdGpuInstallerFile $exe -MinBytes 64)) 'Reject invalid PE offset'

    Reset-Scenario
    Assert-True ((Resolve-LDLCAmdGpuOfficialSource).Version -eq '99.1.1') 'Read current AMD page'
    $script:Page = $script:Page.Replace('99.1.1', '99.2.1') + $script:Page
    Assert-True ((Resolve-LDLCAmdGpuOfficialSource).Version -eq '99.2.1') 'Follow updated version without code changes'
    $script:Page = $script:Page.Replace('99.2.1', '99.2.1.4')
    Assert-True ((Resolve-LDLCAmdGpuOfficialSource).Version -eq '99.2.1.4') 'Accepter aussi la version AMD a quatre composantes.'
    foreach ($badHost in @('drivers.amd.com.evil.test', 'drivers.amd.com@evil.test', 'evil.test')) {
        $script:Page = '<a href="https://' + $badHost + '/amd-software-adrenalin-edition-99.1.1-minimalsetup-990101_web.exe">Download</a>'
        Assert-Throws { Resolve-LDLCAmdGpuOfficialSource } 'introuvable'
    }
    $script:Page = '<a href="https://drivers.amd.com/drivers/amd-software-adrenalin-edition-99.1.1-win11.exe">Full RDNA only</a>'
    Assert-Throws { Resolve-LDLCAmdGpuOfficialSource } 'introuvable'

    Reset-Scenario
    $ids = @('PCI\VEN_1002&DEV_164E')
    Assert-True (Test-LDLCAmdGpuDriversReady $ids) 'Healthy signed AMD DISPLAY driver'
    $script:Drivers[0].DriverProviderName = 'Microsoft'
    Assert-True (-not (Test-LDLCAmdGpuDriversReady $ids)) 'Basic Microsoft display driver is not AMD'
    foreach ($case in @('unsigned', 'chipset', 'missing-version', 'bad-inf', 'wrong-device', 'error43', 'reboot22', 'absent')) {
        Reset-Scenario
        switch ($case) {
            'unsigned' { $script:Drivers[0].IsSigned = $false }
            'chipset' { $script:Drivers[0].DeviceClass = 'SYSTEM' }
            'missing-version' { $script:Drivers[0].DriverVersion = '' }
            'bad-inf' { $script:Drivers[0].InfName = 'basicdisplay.inf' }
            'wrong-device' { $script:Drivers[0].DeviceID = 'PCI\VEN_1002&DEV_ABCD' }
            'error43' { $script:Adapters[0].ConfigManagerErrorCode = 43 }
            'reboot22' { $script:Adapters[0].ConfigManagerErrorCode = 22 }
            'absent' { $script:Adapters = @() }
        }
        Assert-True (-not (Test-LDLCAmdGpuDriversReady $ids)) "Reject driver scenario $case"
    }
    Reset-Scenario
    $script:Adapters += [pscustomobject]@{ Name = 'AMD Radeon RX'; PNPDeviceID = 'PCI\VEN_1002&DEV_ABCD'; ConfigManagerErrorCode = 0 }
    Assert-True (-not (Test-LDLCAmdGpuDriversReady @($ids[0], 'PCI\VEN_1002&DEV_ABCD'))) 'Every AMD GPU needs its own valid driver'

    Reset-Scenario
    Install-LDLCAmdStack
    Assert-True ($script:Elapsed -ge 11) 'Wait for late child after bootstrap exits, plus quiet period'
    Assert-True ($script:Downloaded -eq 1 -and $script:Launches -eq 1 -and $script:Shortcuts -eq 1) 'Existing software/driver must not skip current official installer'
    $script:Page = $script:Page.Replace('99.1.1', '99.3.1')
    Install-LDLCAmdStack
    Assert-True ($script:Downloaded -eq 2 -and $script:Launches -eq 2 -and $script:PageReads -eq 2) 'Chaque preparation doit rechercher, telecharger et executer AMD meme si deja installe.'
    Assert-True ($script:DownloadedUrls[-1] -match '99\.3\.1-minimalsetup') 'Suivre une nouvelle version AMD sans ancien cache.'

    Reset-Scenario
    $script:ChildParent = 4; $script:ChildName = 'Setup.exe'; $script:ChildPath = 'C:\AMD\Current\Setup.exe'
    Install-LDLCAmdStack
    Assert-True ($script:Elapsed -ge 11) 'Also wait for service-launched AMD setup'
    Reset-Scenario
    $script:ChildEndsAt = 0; $script:DriverReadyAt = 8
    Install-LDLCAmdStack
    Assert-True ($script:Elapsed -ge 8 -and $script:DriverReads -gt 1) 'Wait for driver readiness after process completion'
    Reset-Scenario
    $script:RootExitAt = 100
    Assert-Throws { Install-LDLCAmdStack } 'delai limite'
    Assert-True ($script:SoftwareReads -eq 0 -and $script:Shortcuts -eq 0) 'Active root cannot pass using existing software'
    Reset-Scenario
    $script:ChildEndsAt = 100
    Assert-Throws { Install-LDLCAmdStack } 'delai limite'
    Assert-True ($script:SoftwareReads -eq 0 -and $script:Shortcuts -eq 0) 'Active child cannot pass using existing software'
    Reset-Scenario
    $script:ExitCode = 1603
    Assert-Throws { Install-LDLCAmdStack } 'code 1603'
    Assert-True ($script:SoftwareReads -eq 0) 'Installer error cannot pass using existing software'
    Reset-Scenario
    $script:ExitCode = 3010
    Install-LDLCAmdStack
    Assert-True $script:PendingReboot 'Retain required reboot signal when driver already valid'
    Reset-Scenario
    $script:ExitCode = 3010; $script:Drivers = @()
    $script:Warnings = @()
    Install-LDLCAmdStack
    Assert-True ($script:Warnings.Count -eq 1 -and $script:Warnings[0] -match 'pas encore confirmes') 'Required reboot is a precise warning, never a fabricated success'
    Assert-True ($script:PendingReboot -and $script:Shortcuts -eq 0) 'Reboot alone is not driver validation'
    Reset-Scenario
    $script:SoftwarePresent = $false
    Assert-Throws { Install-LDLCAmdStack } 'application Adrenalin'
    Reset-Scenario
    $script:NetworkFailure = $true
    Assert-Throws { Install-LDLCAmdStack } 'network failure'
    Assert-True ($script:Launches -eq 0) 'No stale offline package after resolution failure'
    Reset-Scenario
    $script:HtmlDownload = $true
    Assert-Throws { Install-LDLCAmdStack } 'Installateur AMD refuse'
    Assert-True ($script:Launches -eq 0) 'Never launch invalid download'
    Reset-Scenario
    $script:Adapters = @([pscustomobject]@{ Name = 'NVIDIA'; PNPDeviceID = 'PCI\VEN_10DE&DEV_1234' })
    Install-LDLCAmdStack
    Assert-True ($script:Downloaded -eq 0 -and $script:Launches -eq 0 -and $script:Shortcuts -eq 0) 'Direct AMD entrypoint is non-applicable without Radeon'
    Reset-Scenario
    $script:Cancel = $true
    Assert-Throws { Install-LDLCAmdStack } 'cancellation'
    Assert-True ($script:Launches -eq 0) 'Cancellation does not launch installer'
    Write-Host "OK AMD isolated flow: $script:Assertions assertions; no real hardware query, network, or installation"
}
finally {
    $expectedParent = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd([char[]]@('\','/')) + [System.IO.Path]::DirectorySeparatorChar
    if (-not [System.IO.Path]::GetFullPath($tempRoot).StartsWith($expectedParent, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Unsafe test cleanup path'
    }
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
}
