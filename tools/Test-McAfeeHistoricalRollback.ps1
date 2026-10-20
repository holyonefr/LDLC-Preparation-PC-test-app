#requires -Version 5.1
param([string]$ModuleRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'modules'))
$ErrorActionPreference = 'Stop'
. (Join-Path $ModuleRoot '50.Cleanup.ps1')
. (Join-Path $ModuleRoot '52.SecurityUninstall.ps1')
. (Join-Path $ModuleRoot '90.Workflow.ps1')
$checks = 0; $cases = 0; $native = 'not executed: Windows required'
function Assert($Value, $Reason) { $script:checks++; if (-not $Value) { throw $Reason } }
function Write-Section($Text) { }
function Write-Step($Text) { }
function Write-Info($Text) { }
function Write-Ok($Text) { }
function Write-Warn($Text) { $script:warnings += @($Text) }
function Write-ProgressFile($Percent, $Text) { }
function Clear-LDLCDetectionCaches { }
function Stop-IfRequested { if ($script:cancel) { throw 'LDLC_STOP_REQUESTED' } }
function Test-LDLCStopRequestError($ErrorRecord) { return ($ErrorRecord.Exception.Message -match 'LDLC_STOP_REQUESTED') }
function New-Target($Group, $Name = $Group) {
    return [pscustomobject]@{ Profile = @{ Group = $Group; Category = $(if ($Group -in @('McAfee','Norton')) {'Antivirus'} else {'OEM'}) }; Program = @{ DisplayName = $Name } }
}
function Reset-Targets([object[]]$Targets) {
    $script:cases++; $script:targets = $Targets; $script:remaining = @{}
    foreach ($target in $Targets) { $script:remaining[$target.Program.DisplayName] = $true }
    $script:attempts = @(); $script:fallbacks = @(); $script:removeSucceeds = $true; $script:cancel = $false
}
function Get-LDLCOemRemovalTargets($Mode = 'All') {
    return @($script:targets | Where-Object { $script:remaining.ContainsKey($_.Program.DisplayName) -and
        ($Mode -eq 'All' -or ($Mode -eq 'Security' -and $_.Profile.Category -eq 'Antivirus') -or ($Mode -eq 'Oem' -and $_.Profile.Category -eq 'OEM')) })
}
function Remove-LDLCProgramSilently($Target, $ProgressPercent) {
    $script:attempts += @($Target.Profile.Group)
    if ($script:removeSucceeds) { $script:remaining.Remove($Target.Program.DisplayName) }
    return $script:removeSucceeds
}
function Save-LDLCOemRemovalFallback($Target) { $script:fallbacks += @($Target.Profile.Group); return 'synthetic fallback, never downloaded' }
$realCleanup = ${function:Remove-LDLCOemAndSecurityTrials}
$directory = Join-Path ([IO.Path]::GetTempPath()) ('LDLC-McAfee-Rollback-' + [guid]::NewGuid().ToString('N'))
$saved = @{}
foreach ($name in @('WINDIR','LDLC_SECURITY_RESULT_PATH','LDLC_SECURITY_VENDOR_FILTER','LDLC_TELEMETRY_DISABLED','LDLC_TEST_MODE','LDLC_SECURITY_TEST_DELAY_SECONDS')) {
    $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
try {
    [void](New-Item -ItemType Directory -Path $directory)
    Reset-Targets @((New-Target 'McAfee'), (New-Target 'Norton'), (New-Target 'WildTangent'))
    $result = Remove-LDLCOemAndSecurityTrials -Mode Security -SecurityVendor McAfee
    Assert ($result.Detected -eq 1 -and $result.Removed -eq 1 -and $result.Pending -eq 0) 'McAfee uses the historical cleanup and reports real fixture removal.'
    Assert (($attempts -join ',') -eq 'McAfee' -and $remaining.ContainsKey('Norton') -and $remaining.ContainsKey('WildTangent')) 'McAfee rollback must never uninstall Norton or OEM software.'

    Reset-Targets @((New-Target 'McAfee' 'McAfee protection'), (New-Target 'McAfee' 'McAfee WebAdvisor'), (New-Target 'Norton'))
    $script:removeSucceeds = $false
    $result = Remove-LDLCOemAndSecurityTrials -Mode Security -SecurityVendor McAfee
    Assert ($result.Pending -eq 2 -and $result.Removed -eq 0 -and ($attempts -join ',') -eq 'McAfee,McAfee') 'Pending McAfee products must be reported, not falsely removed.'
    Assert (($fallbacks -join ',') -eq 'McAfee') 'Retain exactly one historical MCPR fallback per vendor.'

    Reset-Targets @((New-Target 'Norton'), (New-Target 'WildTangent'))
    $result = Remove-LDLCOemAndSecurityTrials -Mode Security -SecurityVendor McAfee
    Assert ($result.Detected -eq 0 -and $attempts.Count -eq 0 -and $fallbacks.Count -eq 0) 'No McAfee means no uninstall command or download.'

    Reset-Targets @((New-Target 'McAfee'), (New-Target 'Norton'), (New-Target 'WildTangent'))
    $result = Remove-LDLCOemAndSecurityTrials -Mode Oem -SecurityVendor McAfee
    Assert (($attempts -join ',') -eq 'WildTangent') 'Vendor selection must not change the separate OEM step.'

    $script:cases++
    $hashes = Get-Content (Join-Path $PSScriptRoot 'fixtures/mcafee-before-changes.json') -Raw | ConvertFrom-Json
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $ModuleRoot '50.Cleanup.ps1'), [ref]$tokens, [ref]$errors)
    Assert ($errors.Count -eq 0) 'Historical cleanup source must parse.'
    foreach ($item in $hashes.Functions.PSObject.Properties) {
        $name = $item.Name
        $node = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $actual = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($node.Extent.Text -replace "`r`n", "`n")))).Replace('-', '') } finally { $sha.Dispose() }
        Assert ($actual -eq $item.Value) ('Historical algorithm changed unexpectedly: ' + $name)
    }

    # Real isolated controller; only clock/process/target boundaries are simulated.
    $script:LDLCEmbeddedWorkerScriptPath = Join-Path $directory 'worker with spaces.ps1'
    [IO.File]::WriteAllText($script:LDLCEmbeddedWorkerScriptPath, '# harmless worker fixture')
    $script:StopFile = Join-Path $directory 'stop.flag'
    $env:WINDIR = $directory
    function Get-LDLCRuntimeRoot { return $directory }
    function Get-Date { return ([datetime]'2026-10-20T12:00:00Z').AddMilliseconds($script:clock) }
    function Start-Sleep([int]$Milliseconds) { $script:clock += $Milliseconds; if ($script:cancelAt -and $script:clock -ge $script:cancelAt) { [IO.File]::WriteAllText($script:StopFile,'stop'); $script:cancel = $true } }
    function taskkill.exe { $script:kills++ }
    function Start-Process($FilePath, $ArgumentList, $WindowStyle, [switch]$PassThru, $ErrorAction) {
        $script:launch = @{ Vendor = $env:LDLC_SECURITY_VENDOR_FILTER; Arguments = @($ArgumentList); WindowStyle = $WindowStyle }
        if ($script:outcome -notin @('timeout','missing')) {
            @{ Success = $true; Detected = 1; Removed = $(if ($script:outcome -eq 'pending') {0} else {1}); Pending = $(if ($script:outcome -eq 'pending') {1} else {0}); Error = '' } |
                ConvertTo-Json | Set-Content -LiteralPath $env:LDLC_SECURITY_RESULT_PATH -Encoding UTF8
        }
        $process = [pscustomobject]@{ Id = 999999 }
        $process | Add-Member ScriptProperty HasExited { return ($script:outcome -ne 'timeout') }
        return $process
    }
    foreach ($outcome in @('success','pending','missing','timeout')) {
        $script:cases++; $script:outcome = $outcome; $script:clock = 0; $script:kills = 0; $script:warnings = @(); $script:cancel = $false; $script:cancelAt = 0
        $env:LDLC_SECURITY_VENDOR_FILTER = 'original-value'; $env:LDLC_SECURITY_RESULT_PATH = 'original-result'
        $result = Invoke-LDLCSecurityCleanupIsolated -SecurityVendor McAfee -TimeoutSeconds 90
        Assert ($launch.Vendor -eq 'McAfee' -and '-SecurityCleanupWorker' -in $launch.Arguments) 'Historical worker must inherit McAfee-only selection.'
        Assert ($env:LDLC_SECURITY_VENDOR_FILTER -eq 'original-value' -and $env:LDLC_SECURITY_RESULT_PATH -eq 'original-result') 'Restore caller environment after the isolated worker.'
        if ($outcome -eq 'success') { Assert ($result.Success -and $result.Removed -eq 1) 'Read the completed historical worker result.' }
        if ($outcome -eq 'pending') { Assert ($result.Pending -eq 1 -and $warnings.Count -gt 0 -and $clock -eq 0) 'Unremoved McAfee must warn and return as before, without the new infinite wait.' }
        if ($outcome -eq 'missing') { Assert (-not $result.Success -and $result.Error -eq 'Resultat absent') 'Missing worker result must remain a visible failure result.' }
        if ($outcome -eq 'timeout') { Assert ($result.TimedOut -and $clock -eq 90000 -and $kills -eq 1) 'Restore exactly the historical 90-second bound and process-tree stop.' }
    }

    $script:cases++; $script:outcome = 'timeout'; $script:clock = 0; $script:kills = 0; $script:cancelAt = 500; $script:cancel = $false; $stopped = $false
    try { Invoke-LDLCSecurityCleanupIsolated -SecurityVendor McAfee | Out-Null } catch { $stopped = $_.Exception.Message -match 'LDLC_STOP_REQUESTED' }
    Assert ($stopped -and $kills -eq 1 -and $clock -eq 500) 'Quit remains responsive and does not become an ignored McAfee error.'
    Assert ($env:LDLC_SECURITY_VENDOR_FILTER -eq 'original-value') 'Restore selection on cancellation too.'
    Remove-Item $script:StopFile -Force
    $script:cancel = $false; $script:cancelAt = 0

    # Execute the actual SecurityCleanupWorker dispatch block with a fake remover.
    $script:cases++
    function Initialize-LDLCScriptState { }
    function Remove-LDLCOemAndSecurityTrials($Mode, $SecurityVendor, $StartPercent, $EndPercent) { $script:workerSelection = $SecurityVendor; return @{Detected=1;Removed=1;Pending=0} }
    $workerAst = [Management.Automation.Language.Parser]::ParseFile((Join-Path $ModuleRoot '95.WorkerLauncher.ps1'), [ref]$tokens, [ref]$errors)
    $workerIf = $workerAst.Find({ param($n) $n -is [Management.Automation.Language.IfStatementAst] -and $n.Clauses[0].Item1.Extent.Text -eq '$SecurityCleanupWorker' }, $true)
    $workerBody = [scriptblock]::Create(($workerIf.Clauses[0].Item2.Statements | ForEach-Object {$_.Extent.Text}) -join "`n")
    $env:LDLC_SECURITY_VENDOR_FILTER = 'McAfee'; $env:LDLC_SECURITY_RESULT_PATH = Join-Path $directory 'worker-result.json'; $env:LDLC_TEST_MODE = '0'; $script:LDLCRoot = $directory
    & $workerBody
    $workerResult = Get-Content $env:LDLC_SECURITY_RESULT_PATH -Raw | ConvertFrom-Json
    Assert ($script:workerSelection -eq 'McAfee' -and $workerResult.Success) 'The real worker dispatch must forward the selected vendor, not silently clean both suites.'

    # Assert application-level routing: McAfee historical first, Norton current second.
    $script:cases++
    $workflowAst = [Management.Automation.Language.Parser]::ParseFile((Join-Path $ModuleRoot '90.Workflow.ps1'), [ref]$tokens, [ref]$errors)
    $main = $workflowAst.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-LDLCPreparation'}, $true)
    $legacyCall = $main.Find({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Invoke-LDLCSecurityCleanupIsolated'}, $true)
    $interactiveCall = $main.Find({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Remove-LDLCSecurityTrialsInteractively'}, $true)
    Assert ($legacyCall.Extent.Text -match '-SecurityVendor McAfee' -and $legacyCall.Extent.Text -match '-TimeoutSeconds 90' -and $legacyCall.Extent.StartOffset -lt $interactiveCall.Extent.StartOffset) 'Normal preparation must actually use the rollback before Norton, not just expose an unused helper.'

    if ($env:OS -eq 'Windows_NT') {
        $script:cases++
        foreach ($command in @('Start-Process','Get-Date','Start-Sleep','taskkill.exe')) { Remove-Item ('Function:' + $command) -ErrorAction SilentlyContinue }
        $env:WINDIR = $saved.WINDIR
        $env:LDLC_SECURITY_RESULT_PATH = 'native-original-result'; $env:LDLC_SECURITY_VENDOR_FILTER = 'native-original-filter'
        [IO.File]::WriteAllText($script:LDLCEmbeddedWorkerScriptPath, @'
param([switch]$SecurityCleanupWorker)
if (-not $SecurityCleanupWorker -or $env:LDLC_SECURITY_VENDOR_FILTER -ne 'McAfee') { exit 2 }
@{Success=$true;Detected=1;Removed=1;Pending=0;Error='';FixtureOnly=$true} | ConvertTo-Json | Set-Content -LiteralPath $env:LDLC_SECURITY_RESULT_PATH -Encoding UTF8
'@)
        $result = Invoke-LDLCSecurityCleanupIsolated -SecurityVendor McAfee -TimeoutSeconds 90
        Assert ($result.Success -and $result.FixtureOnly) 'Run the actual Windows PowerShell child via the restored isolated controller.'
        Assert ($env:LDLC_SECURITY_VENDOR_FILTER -eq 'native-original-filter') 'Native child launch must restore caller selection.'
        $native = 'real Windows PowerShell child with synthetic result; no antivirus installed or removed'

        # Exercise the generated worker and its real mode dispatch too. Stub the
        # installed-program inventory and preparation entry point before launch:
        # this cannot uninstall a real product or start a full preparation.
        $script:cases++
        $generatedPath = Join-Path $directory 'generated security worker.ps1'
        & (Join-Path $PSScriptRoot 'Rebuild-LDLCPreparationPC.ps1') -Source worker -OutputPath $generatedPath | Out-Null
        $generated = [IO.File]::ReadAllText($generatedPath)
        $generatedAst = [Management.Automation.Language.Parser]::ParseInput($generated, [ref]$tokens, [ref]$errors)
        Assert ($errors.Count -eq 0 -and 'SecurityCleanupWorker' -in @($generatedAst.ParamBlock.Parameters | ForEach-Object {$_.Name.VariablePath.UserPath})) 'Generated worker must accept the security-only switch.'
        $replacements = @{
            'Get-LDLCInstalledPrograms' = 'function Get-LDLCInstalledPrograms { return @() }'
            'Invoke-LDLCPreparation' = 'function Invoke-LDLCPreparation { throw "SECURITY_WORKER_DISPATCH_FAILED" }'
        }
        $edits = foreach ($name in $replacements.Keys) {
            $node = $generatedAst.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name}, $true)
            if (-not $node) { throw ('Generated worker function missing: ' + $name) }
            [pscustomobject]@{ Start=$node.Extent.StartOffset; End=$node.Extent.EndOffset; Text=$replacements[$name] }
        }
        foreach ($edit in ($edits | Sort-Object Start -Descending)) { $generated = $generated.Remove($edit.Start, $edit.End-$edit.Start).Insert($edit.Start,$edit.Text) }
        [IO.File]::WriteAllText($generatedPath, $generated, (New-Object Text.UTF8Encoding($true)))
        $savedRuntime = @{}
        foreach ($name in @('ProgramData','LOCALAPPDATA','LDLC_PREP_INSTALL_WORKER')) { $savedRuntime[$name]=[Environment]::GetEnvironmentVariable($name,'Process') }
        try {
            $env:ProgramData=$directory; $env:LOCALAPPDATA=$directory
            # The security branch must take priority over an inherited install flag.
            $env:LDLC_PREP_INSTALL_WORKER='1'
            $script:LDLCEmbeddedWorkerScriptPath=$generatedPath
            $result=Invoke-LDLCSecurityCleanupIsolated -SecurityVendor McAfee -TimeoutSeconds 30
            Assert ($result.Success -and $result.Detected -eq 0 -and $result.Removed -eq 0 -and -not $result.Pending) 'Generated worker must run security-only cleanup, never recurse into full preparation or UI.'
        } finally { foreach ($name in $savedRuntime.Keys) { [Environment]::SetEnvironmentVariable($name,$savedRuntime[$name],'Process') } }
        $native = 'real PowerShell child plus generated security worker; inventory/preparation stubbed; no real antivirus installed or removed'
    }
    Write-Host ('::notice title=McAfee historical rollback::' + (@{Cases=$cases;Assertions=$checks;Failures=0;HistoricalCommit=$hashes.Commit;NativeWorker=$native;RealMcAfeeInstalled=$false;RealMcAfeeRemoved=$false;LegacyTimeoutSeconds=90;NortonChanged=$false} | ConvertTo-Json -Compress))
} catch {
    $message = $_.Exception.Message.Replace('%','%25').Replace("`r",'%0D').Replace("`n",'%0A')
    Write-Host ('::error title=McAfee historical rollback::' + $message)
    throw
} finally {
    foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process') }
    if (Test-Path $directory) { Remove-Item -LiteralPath $directory -Recurse -Force }
}
