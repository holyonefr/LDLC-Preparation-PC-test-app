#requires -Version 5.1
param([string]$LayoutModulePath)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $LayoutModulePath) { $LayoutModulePath = Join-Path $root 'modules/20.WindowsLayout.ps1' }
$ast = [Management.Automation.Language.Parser]::ParseFile($LayoutModulePath, [ref]$null, [ref]$null)
$names = @('Test-LDLCTaskbarItemMatch', 'Get-LDLCTaskbarItem', 'Wait-LDLCTaskbarItemAbsent', 'Remove-LDLCTaskbarPins')
foreach ($name in $names) {
    $node = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
    if (-not $node) { throw "Missing function: $name" }
    $text = $node.Extent.Text
    if ($name -eq 'Wait-LDLCTaskbarItemAbsent') { $text = $text.Replace('function Wait-LDLCTaskbarItemAbsent', 'function Wait-RealTaskbarItemAbsent') }
    . ([scriptblock]::Create($text))
}
# Shell state is simulated. No real pin, browser, registry or COM object is changed.
function Wait-LDLCTaskbarItemAbsent {
    param($ExactNames, $NamePatterns, $PathPatterns, $TimeoutSeconds)
    Wait-RealTaskbarItemAbsent -ExactNames $ExactNames -NamePatterns $NamePatterns -PathPatterns $PathPatterns -TimeoutSeconds 0
}
function Stop-IfRequested { if ($script:stop) { throw [OperationCanceledException]::new('Requested stop') } }
function Test-LDLCStopRequestError { param($e) $e.Exception -is [OperationCanceledException] }
function Start-Sleep { param($Milliseconds) }
function Refresh-Desktop {}
function Write-ProgressFile { param($Percent, $Message) }
function Write-Step { param($Message) }
function Write-Ok { param($Message) $script:okCount++ }
function Write-Warn { param($Message) $script:warnings += $Message }
function Test-Path { param($LiteralPath, $PathType) return $script:hasPinDirectory }
$item = [pscustomobject]@{ Name = 'Microsoft Edge'; Path = 'C:\Program Files\Microsoft\Edge\Application\msedge.exe' }
$item | Add-Member ScriptMethod Verbs {
    if ($script:pinned) { [pscustomobject]@{ Name = $script:unpinVerb } }
    else { [pscustomobject]@{ Name = '&Pin to taskbar' } }
}
$item | Add-Member ScriptMethod InvokeVerb {
    param($verb)
    if ($verb -ne 'taskbarunpin') { throw 'Unexpected command' }
    $script:unpinCalls++
    if (-not $script:refuse) { $script:pinned = $false; $script:hasShortcut = $false }
}
$apps = [pscustomobject]@{}
$apps | Add-Member ScriptMethod Items { return $script:item }
$pins = [pscustomobject]@{}
$pins | Add-Member ScriptMethod Items { if ($script:hasShortcut) { return $script:item } }
$shell = [pscustomobject]@{}
$shell | Add-Member ScriptMethod Namespace {
    param($name)
    if ($script:namespaceFailure) { return $null }
    if ($name -like 'shell:::*') { return $script:apps }
    return $script:pins
}
function Reset-Fixture {
    $script:pinned = $false; $script:hasShortcut = $false; $script:hasPinDirectory = $false
    $script:namespaceFailure = $false; $script:stop = $false; $script:refuse = $false
    $script:warnings = @(); $script:unpinCalls = 0; $script:okCount = 0
    $script:unpinVerb = '&Unpin from taskbar'
}
function Remove-TestPin {
    Remove-LDLCTaskbarPins -ExactNames @('Microsoft Edge', 'Edge') -PathPatterns @('*msedge.exe*') -Label 'Edge' -ProgressMessage 'Unpin Edge' -ProgressPercent 18
}
function Assert-True { param($Condition, $Message) if (-not $Condition) { throw $Message } }

Reset-Fixture
Assert-True (-not (Remove-TestPin)) 'Installed but unpinned Edge must not be removed again'
Assert-True ($warnings.Count -eq 0 -and $unpinCalls -eq 0) 'Installed application must not produce a false warning'
Assert-True (@($apps.Items()).Count -eq 1) 'Fixture must keep the installed app after unpinning'

Reset-Fixture; $script:pinned = $true
Assert-True (Remove-TestPin) 'English pin must be removed successfully'
Assert-True ($warnings.Count -eq 0 -and $unpinCalls -eq 1 -and $okCount -eq 1) 'Removal must be confirmed while the application remains installed'
Assert-True (@($apps.Items()).Count -eq 1) 'Unpinning must not uninstall Edge'

Reset-Fixture; $script:pinned = $true
$script:unpinVerb = 'D&' + [char]0xe9 + 'tacher de la barre des t' + [char]0xe2 + 'ches'
Assert-True (Remove-TestPin) 'French accented shell verb must be recognized'
Assert-True ($warnings.Count -eq 0) 'French removal must not produce a false warning'

Reset-Fixture; $script:pinned = $true; $script:refuse = $true
Assert-True (-not (Remove-TestPin)) 'Persisting real pin must fail verification'
Assert-True ($warnings.Count -eq 1 -and $okCount -eq 0) 'Real refusal must remain visible and must not report success'

Reset-Fixture; $script:hasShortcut = $true; $script:hasPinDirectory = $true
Assert-True (Remove-TestPin) 'Persisted shortcut must be removed even without an Unpin verb'
Assert-True ($warnings.Count -eq 0 -and $unpinCalls -eq 1) 'Shortcut removal must be confirmed'

Reset-Fixture; $script:hasShortcut = $true; $script:hasPinDirectory = $true; $script:refuse = $true
Assert-True (-not (Remove-TestPin)) 'Persisting pinned shortcut must fail verification'
Assert-True ($warnings.Count -eq 1 -and $okCount -eq 0) 'A real remaining shortcut must retain its warning'

Reset-Fixture; $script:namespaceFailure = $true
$failed = $false
try { Remove-TestPin | Out-Null } catch { $failed = $true }
Assert-True $failed 'Unreadable Shell must not be interpreted as an absent pin'

Reset-Fixture; $script:stop = $true
$stopped = $false
try { Remove-TestPin | Out-Null } catch { $stopped = $_.Exception -is [OperationCanceledException] }
Assert-True $stopped 'Stop requests must still interrupt preparation'
Write-Host 'OK taskbar pins: 8 scenarios; installed apps retained, English/French verbs, shortcut pins, actual refusal, unreadable Shell and stop. Shell operations simulated.'
