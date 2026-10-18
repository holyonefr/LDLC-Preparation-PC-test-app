param([string]$ModuleRoot = '')
$ErrorActionPreference = 'Stop'
if (-not $ModuleRoot) { $ModuleRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'modules' }
$script:Assertions = 0
function Assert-True([bool]$Condition, [string]$Message) {
    $script:Assertions++
    if (-not $Condition) { throw $Message }
}
function Assert-NoNativeMonitoring([string]$Operation) {
    $script:Forbidden.Add($Operation)
    throw "Unexpected monitoring/native side effect: $Operation"
}

# Import real entry points and orchestration, without the bootstrap, state,
# machine configuration or complete preparation workflow.
$trees = @{}
foreach ($name in @('80.WindowsUpdate.ps1', '90.Workflow.ps1')) {
    $path = Join-Path $ModuleRoot $name
    $tokens = $null; $errors = $null
    $tree = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
    Assert-True ($errors.Count -eq 0) "Invalid source: $name"
    Assert-True (@($tree.EndBlock.Statements | Where-Object {
        $_ -isnot [Management.Automation.Language.FunctionDefinitionAst]
    }).Count -eq 0) "Import must only define functions: $name"
    $trees[$name] = $tree
    . $path
}
$workflow = $trees['90.Workflow.ps1'].Find({
    param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-LDLCPreparation'
}, $true)
Assert-True ($null -ne $workflow) 'Preparation workflow missing.'
$oldCalls = @($workflow.FindAll({
    param($node)
    $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -in @(
        'Wait-LDLCWindowsUpdateWorkerCompletion', 'Start-LDLCWindowsUpdateWorker',
        'Invoke-LDLCWindowsUpdateFullMaintenance', 'Invoke-LDLCWindowsUpdateComInstallLegacy',
        'Invoke-LDLCWindowsUpdatesWithTimeout', 'Read-LDLCWindowsUpdateWorkerProgress'
    )
}, $true))
Assert-True ($oldCalls.Count -eq 0) 'Preparation must use the native trigger without the previous wait/COM paths.'
$oldCounters = @($workflow.FindAll({
    param($node)
    $node -is [Management.Automation.Language.MemberExpressionAst] -and $node.Member.Value -in @(
        'RemainingCount', 'DetectedCount', 'DownloadedCount', 'CycleCount', 'MaxCycles', 'TimedOut'
    )
}, $true))
Assert-True ($oldCounters.Count -eq 0) 'Preparation must not inspect update completion counters or an update timeout.'

function Reset-Fixture([string]$Mode = 'All') {
    $script:Mode = $Mode
    $script:Cancelled = $false
    $script:CancelAfterFirstLaunch = $false
    $script:Native = New-Object 'Collections.Generic.List[object]'
    $script:Tasks = New-Object 'Collections.Generic.List[string]'
    $script:Services = New-Object 'Collections.Generic.List[string]'
    $script:Forbidden = New-Object 'Collections.Generic.List[string]'
    $script:Messages = New-Object 'Collections.Generic.List[object]'
    $script:Progress = New-Object 'Collections.Generic.List[object]'
    $script:PendingReboot = $true
}
function Stop-IfRequested {
    if ($script:Cancelled -or ($script:CancelAfterFirstLaunch -and $script:Native.Count -gt 0)) {
        throw 'LDLC_STOP_REQUESTED'
    }
}
function Test-LDLCStopRequestError($ErrorRecord) { return $ErrorRecord.Exception.Message -match 'LDLC_STOP_REQUESTED' }
function Write-ProgressFile($Percent, $Message, [switch]$IgnoreStopRequest) {
    $script:Progress.Add([pscustomobject]@{ Percent = [int]$Percent; Message = [string]$Message })
}
function Write-Step($Message) {}
function Write-Section($Message) {}
function Write-Info($Message) {}
function Write-Ok($Message) {}
function Write-Warn($Message) { $script:Messages.Add([pscustomobject]@{ Severity = 'warning'; Message = $Message }) }
function Write-Err($Message) { $script:Messages.Add([pscustomobject]@{ Severity = 'error'; Message = $Message }) }
function Update-LDLCTelemetryRun { param($Status, $Step, $Message, $ProgressPercent, [switch]$Force) }
function Add-LDLCTelemetryEvent {
    param($Message, $Severity, $Type, $Status, $Details)
    $script:Messages.Add([pscustomobject]@{ Severity = $Severity; Message = $Message })
}

# Keep the product's native command helpers. Replace only OS boundaries, so a
# successful mock cannot hide a COM search, waiting process or result-file read.
function New-Object {
    [CmdletBinding()]
    param([Parameter(Position = 0)][string]$TypeName, [string]$ComObject, [object[]]$ArgumentList)
    if ($ComObject) { Assert-NoNativeMonitoring 'COM creation' }
    Microsoft.PowerShell.Utility\New-Object @PSBoundParameters
}
function Test-Path {
    [CmdletBinding()]
    param([Parameter(Position = 0)][string]$Path, [string]$LiteralPath, $PathType)
    $candidate = if ($LiteralPath) { $LiteralPath } else { $Path }
    if ($candidate -match '(?i)(?:^|[\\/])(UsoClient|wuauclt)\.exe$') { return $true }
    Assert-NoNativeMonitoring 'unexpected filesystem probe'
}
function Start-Process {
    [CmdletBinding()]
    param($FilePath, [string[]]$ArgumentList, $WindowStyle, [switch]$Wait, [switch]$PassThru)
    if ($Wait) { Assert-NoNativeMonitoring 'Start-Process -Wait' }
    $file = [IO.Path]::GetFileName(([string]$FilePath -replace '\\', '/'))
    if ($file -notin @('UsoClient.exe', 'wuauclt.exe')) { Assert-NoNativeMonitoring 'unexpected child process/worker' }
    $action = $ArgumentList -join ' '
    Assert-True ($action -in @('RefreshSettings', 'StartScan', 'StartDownload', 'StartInstall', '/detectnow', '/updatenow')) 'Only native update requests may be dispatched.'
    $script:Native.Add([pscustomobject]@{ File = $file; Action = $action })
    if ($script:Mode -in @('None', 'TaskOnly') -or
        ($script:Mode -eq 'ScanOnly' -and $action -ne 'StartScan') -or
        ($script:Mode -eq 'RefreshOnly' -and $action -ne 'RefreshSettings')) { throw 'Fixture: request rejected' }
    $process = [pscustomobject]@{ Id = 4242 }
    $process | Add-Member ScriptProperty HasExited { Assert-NoNativeMonitoring 'process exit polling' }
    $process | Add-Member ScriptMethod WaitForExit { Assert-NoNativeMonitoring 'process wait' }
    $process | Add-Member ScriptMethod Kill { Assert-NoNativeMonitoring 'process kill' }
    return $process
}
function Get-Service {
    [CmdletBinding()]
    param([string]$Name)
    $service = [pscustomobject]@{ Name = $Name; Status = 'Stopped' }
    $service | Add-Member ScriptMethod Refresh { $this.Status = 'Running' }
    return $service
}
function Start-Service {
    [CmdletBinding()]
    param([string]$Name)
    $script:Services.Add($Name)
    if ($script:Mode -eq 'ScanOnly' -and $Name -eq 'bits') { throw 'Fixture: service unavailable' }
}
function Get-ScheduledTask {
    [CmdletBinding()]
    param($TaskPath, $TaskName)
    return [pscustomobject]@{ TaskPath = $TaskPath; TaskName = $TaskName }
}
function Start-ScheduledTask {
    [CmdletBinding()]
    param($InputObject)
    $script:Tasks.Add($InputObject.TaskName)
    if ($script:Mode -notin @('All', 'TaskOnly')) { throw 'Fixture: scheduled request unavailable' }
}
function Start-Sleep { Assert-NoNativeMonitoring 'sleep' }
function Stop-Process { Assert-NoNativeMonitoring 'Stop-Process' }
function Wait-Process { Assert-NoNativeMonitoring 'Wait-Process' }
function Get-Process { Assert-NoNativeMonitoring 'process monitoring' }
function Get-Content { Assert-NoNativeMonitoring 'result/progress file read' }
function Start-LDLCWindowsUpdateWorker { Assert-NoNativeMonitoring 'COM worker launch' }
function Read-LDLCWindowsUpdateWorkerProgress { Assert-NoNativeMonitoring 'worker progress read' }
function Invoke-LDLCWindowsUpdateFullMaintenance { Assert-NoNativeMonitoring 'full COM maintenance' }
function New-LDLCWindowsUpdateSearchContext { Assert-NoNativeMonitoring 'COM search context' }
function Get-LDLCWindowsUpdateCollection { Assert-NoNativeMonitoring 'COM update search' }
function Invoke-LDLCWindowsUpdateDownload { Assert-NoNativeMonitoring 'synchronous update download' }
function Invoke-LDLCWindowsUpdateInstall { Assert-NoNativeMonitoring 'synchronous update install' }
function Test-WindowsUpdateBusy { Assert-NoNativeMonitoring 'update busy monitoring' }
function Stop-LDLCProcessTree { Assert-NoNativeMonitoring 'process tree stop' }
function taskkill.exe { Assert-NoNativeMonitoring 'taskkill' }

function Has-Field($Result, [string]$Name) {
    if ($Result -is [Collections.IDictionary]) { return $Result.Contains($Name) }
    return $null -ne $Result.PSObject.Properties[$Name]
}
function Assert-RequestResult($Result, [bool]$Expected, [string]$Entry) {
    $success = if (Has-Field $Result 'Started') { [bool]$Result.Started } else { [bool]$Result.Success }
    Assert-True ($success -eq $Expected) "$Entry must report whether a native request was accepted."
    foreach ($name in @('Completed', 'TimedOut', 'RebootRequired', 'Count', 'RemainingCount', 'DetectedCount', 'DownloadedCount', 'CycleCount', 'MaxCycles', 'ProcessId')) {
        if (Has-Field $Result $name) { Assert-True (-not [bool]$Result.$name) "$Entry must not invent completion/monitoring metadata: $name" }
    }
    Assert-True ($script:PendingReboot) "$Entry must not clear another step's pending restart."
    Assert-True ($script:Forbidden.Count -eq 0) "$Entry must neither wait, search COM, read results nor stop a process."
    Assert-True (@($script:Progress | Where-Object { $_.Percent -gt 37 }).Count -eq 0) "$Entry must not publish false completion progress."
    Assert-True (@($script:Progress | Where-Object { $_.Message -match '(?i)\bcycle\b|\brestantes?\b|encore en cours|delai depasse' }).Count -eq 0) "$Entry must not publish update monitoring/cycle counters."
}

$saved = @{}
$variables = @('WINDIR', 'LDLC_WU_TIMEOUT_SECONDS', 'LDLC_WU_FINAL_WAIT_SECONDS', 'LDLC_WU_KICKOFF_DELAY_SECONDS', 'LDLC_WU_POST_CYCLE_DELAY_SECONDS', 'LDLC_WU_MAX_CYCLES', 'LDLC_WU_MAX_ATTEMPTS')
foreach ($name in $variables) { $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
try {
    $env:WINDIR = Join-Path ([IO.Path]::GetTempPath()) 'Preparation-WindowsUpdate-OS-Fixture'
    foreach ($name in $variables | Where-Object { $_ -ne 'WINDIR' }) { [Environment]::SetEnvironmentVariable($name, '86400', 'Process') }
    foreach ($getter in @('Get-LDLCWindowsUpdateTimeoutSeconds', 'Get-LDLCWindowsUpdateFinalWaitSeconds', 'Get-LDLCWindowsUpdateKickoffDelaySeconds', 'Get-LDLCWindowsUpdatePostCycleDelaySeconds')) {
        if (Get-Command $getter -ErrorAction SilentlyContinue) {
            Assert-True ((& $getter) -eq 0) "$getter must ignore the previous timeout/delay override."
        }
    }
    $entries = @('Start-LDLCWindowsUpdateInBackground', 'Install-WindowsUpdates')
    $hasScheduledFallback = [bool](Get-Command Invoke-LDLCWindowsUpdateScheduledTask -ErrorAction SilentlyContinue)
    foreach ($entry in @('Start-LDLCWindowsUpdatesDuringPreparation', 'Invoke-LDLCWindowsUpdateTrigger', 'Invoke-LDLCWindowsUpdatesWithTimeout', 'Invoke-LDLCWindowsUpdateComInstallLegacy')) {
        if (Get-Command $entry -ErrorAction SilentlyContinue) { $entries += $entry }
    }
    foreach ($entry in $entries) {
        $arguments = if ($entry -eq 'Start-LDLCWindowsUpdateInBackground') { @{ ProgressPercent = 33 } } else { @{ StartPercent = 33; EndPercent = 37 } }
        if ($entry -eq 'Invoke-LDLCWindowsUpdatesWithTimeout') { $arguments.TimeoutSeconds = 86400 }
        foreach ($mode in @('All', 'ScanOnly', 'TaskOnly', 'RefreshOnly', 'None')) {
            Reset-Fixture $mode
            $result = & $entry @arguments
            $expectedSuccess = $mode -in @('All', 'ScanOnly') -or ($mode -eq 'TaskOnly' -and $hasScheduledFallback)
            Assert-RequestResult $result $expectedSuccess $entry
            foreach ($action in @('StartScan', 'StartDownload', 'StartInstall')) {
                Assert-True (@($script:Native | Where-Object { $_.Action -eq $action }).Count -eq 1) "$entry must dispatch each native scan/download/install request once."
            }
            if (-not $expectedSuccess) {
                Assert-True (@($script:Messages | Where-Object Severity -eq 'error').Count -gt 0) "$entry must expose a total trigger failure."
            } else {
                Assert-True (@($script:Messages | Where-Object Severity -eq 'error').Count -eq 0) "$entry must accept successful native delivery without a false blocking error."
                Assert-True (@($script:Messages | Where-Object Severity -in @('warning', 'critical')).Count -eq 0) "$entry must keep accepted/partial requests informational."
            }
        }
        Reset-Fixture
        $script:Cancelled = $true
        $stopped = $false
        try { & $entry @arguments | Out-Null } catch { $stopped = Test-LDLCStopRequestError $_ }
        Assert-True $stopped "$entry must propagate user cancellation."
        Assert-True ($script:Native.Count -eq 0 -and $script:Tasks.Count -eq 0 -and $script:Services.Count -eq 0) "$entry must not dispatch work after an existing cancellation."
    }
    Reset-Fixture
    $script:CancelAfterFirstLaunch = $true
    $stopped = $false
    try { Install-WindowsUpdates -StartPercent 33 -EndPercent 37 | Out-Null } catch { $stopped = Test-LDLCStopRequestError $_ }
    Assert-True $stopped 'Cancellation during triggering must remain an interruption, not a failed/successful launch result.'
    Assert-True (@($script:Native | Where-Object { $_.Action -in @('StartDownload', 'StartInstall') }).Count -eq 0) 'Cancellation must prevent subsequent native download/install requests.'
    Assert-True ($script:Forbidden.Count -eq 0) 'Cancellation must not stop Windows update processes.'

    if (Get-Command Wait-LDLCWindowsUpdateWorkerCompletion -ErrorAction SilentlyContinue) {
        foreach ($started in @($true, $false)) {
            Reset-Fixture
            $worker = [pscustomobject]@{ Started = $started; ProcessId = 4242; ResultPath = 'DO-NOT-READ.json'; ProgressPath = 'DO-NOT-READ.txt'; Error = 'Fixture: no launch' }
            $result = Wait-LDLCWindowsUpdateWorkerCompletion -Worker $worker -ProgressPercent 37 -TimeoutSeconds 86400
            Assert-RequestResult $result $started 'Wait compatibility adapter'
            Assert-True ($script:Native.Count -eq 0 -and $script:Tasks.Count -eq 0 -and $script:Services.Count -eq 0) 'The compatibility wait must return without re-triggering or inspecting Windows.'
        }
    }
    Write-Host "OK Windows Update native trigger: $script:Assertions assertions; real entry points/helpers, mocked OS; success/partial/failure/cancellation, no COM or update completion wait."
}
finally {
    foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process') }
}
