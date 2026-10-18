$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$script:assertions = 0

function Assert-True([bool]$Value, [string]$Message) {
    if (-not $Value) { throw $Message }
    $script:assertions++
}

function Get-Callback($Ast, [string]$Target, [string]$Event) {
    $calls = @($Ast.FindAll({
        param($node)
        $node -is [Management.Automation.Language.InvokeMemberExpressionAst] -and
            $node.Expression.Extent.Text -eq $Target -and $node.Member.Value -eq $Event
    }, $true))
    Assert-True ($calls.Count -eq 1) "Expected one $Target.$Event callback."
    return $calls[0].Arguments[0].ScriptBlock
}

function Convert-Callback($Ast) {
    $text = $Ast.Extent.Text
    return [scriptblock]::Create($text.Substring(1, $text.Length - 2))
}

function New-FakeTimer {
    $fake = [pscustomobject]@{ Starts = 0; Stops = 0; Disposed = $false; Enabled = $false }
    $fake | Add-Member ScriptMethod Start { $this.Starts++; $this.Enabled = $true }
    $fake | Add-Member ScriptMethod Stop { $this.Stops++; $this.Enabled = $false }
    $fake | Add-Member ScriptMethod Dispose { $this.Disposed = $true }
    return $fake
}

function Reset-Scenario {
    $script:workerLaunchAttempted = $false
    $script:uiFirstPaintCompleted = $false
    $script:closing = $false
    $script:proc = $null
    $script:launches = 0
    $script:compactFlagSeen = $null
    $script:percent = 0
    $script:message = 'Initialisation de l environnement...'
}

$paths = @(Join-Path $root 'modules/99.UI.ps1')
$workerUi = Join-Path $root 'worker-modules/99.UI.ps1'
if (Test-Path -LiteralPath $workerUi) { $paths += $workerUi }
$originalCompactUi = $env:LDLC_DEFAULT_APPS_UI
try {
    foreach ($path in $paths) {
        $tokens = $null; $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
        Assert-True ($errors.Count -eq 0) "Invalid PowerShell syntax: $path"
        $finalizationHelper = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Test-LDLCUiFinalizationReady' }, $true)
        if ($finalizationHelper) { . ([scriptblock]::Create($finalizationHelper.Extent.Text)) }
        $launchAst = Get-Callback $ast '$workerStartTimer' 'Add_Tick'
        $pollAst = Get-Callback $ast '$timer' 'Add_Tick'
        $paintAst = Get-Callback $ast '$overlay' 'Add_Paint'
        $shownAst = Get-Callback $ast '$form' 'Add_Shown'
        $launch = Convert-Callback $launchAst
        $poll = Convert-Callback $pollAst
        $shown = Convert-Callback $shownAst
        $armingNodes = @($paintAst.FindAll({
            param($node)
            $node -is [Management.Automation.Language.IfStatementAst] -and
                $node.Clauses[0].Item1.Extent.Text -eq '-not $script:uiFirstPaintCompleted'
        }, $true))
        Assert-True ($armingNodes.Count -eq 1) 'Worker must be armed by the first overlay paint.'
        $paintCompleted = [scriptblock]::Create($armingNodes[0].Extent.Text)
        Assert-True ($paintAst.Extent.Text.IndexOf('Draw-LDLCProgressArea -Graphics $graphics') -lt
            $paintAst.Extent.Text.IndexOf($armingNodes[0].Extent.Text)) 'The overlay must finish drawing before arming the worker.'
        $content = $ast.Extent.Text
        $launchSite = $content.IndexOf('$script:proc = & $WorkerLauncher')
        Assert-True ($launchSite -ge $launchAst.Extent.StartOffset -and
            $launchSite -lt $launchAst.Extent.EndOffset) 'Worker must not launch before the message loop.'
        Assert-True ($content.IndexOf('$script:workerLaunchAttempted = $true', $launchAst.Extent.StartOffset) -lt
            $launchSite) 'Mark the attempt before launching, including failures.'
        $cleanupNodes = @($ast.FindAll({
            param($node)
            $node -is [Management.Automation.Language.IfStatementAst] -and
                $node.Clauses[0].Item1.Extent.Text -eq '$workerStartTimer'
        }, $true))
        Assert-True ($cleanupNodes.Count -eq 1) 'Deferred timer must have one cleanup block.'
        $cleanup = [scriptblock]::Create($cleanupNodes[0].Extent.Text)
        Assert-True ($cleanupNodes[0].Parent.Parent -is [Management.Automation.Language.TryStatementAst] -and
            $cleanupNodes[0].Parent.Parent.Finally -eq $cleanupNodes[0].Parent) 'Deferred timer cleanup must remain in finally.'

        $Preview = $false
        $form = [pscustomobject]@{ IsDisposed = $false; Disposing = $false; CloseCalls = 0; Cursor = 'Default' }
        $form | Add-Member ScriptMethod Close { $this.CloseCalls++ }
        $timer = New-FakeTimer
        $workerStartTimer = New-FakeTimer
        $WorkerLauncher = {
            $script:launches++
            $script:compactFlagSeen = $env:LDLC_DEFAULT_APPS_UI
            [pscustomobject]@{ Id = 123; HasExited = $false }
        }
        Reset-Scenario
        & $shown
        Assert-True ($timer.Starts -eq 1 -and $script:launches -eq 0 -and $workerStartTimer.Starts -eq 0) 'Shown starts polling without starting preparation.'
        & $paintCompleted
        Assert-True ($script:uiFirstPaintCompleted -and $workerStartTimer.Starts -eq 1 -and $script:launches -eq 0) 'The first paint queues preparation without running it inside paint.'
        & $paintCompleted
        Assert-True ($workerStartTimer.Starts -eq 1) 'Repainting cannot queue a second launch.'
        $env:LDLC_DEFAULT_APPS_UI = 'existing-value'
        & $launch
        Assert-True ($script:launches -eq 1 -and $script:proc.Id -eq 123 -and $workerStartTimer.Stops -eq 1) 'Deferred callback starts one worker and stops its timer.'
        Assert-True ($script:compactFlagSeen -eq '1' -and $env:LDLC_DEFAULT_APPS_UI -eq 'existing-value') 'Worker inherits compact UI while the parent environment is restored.'
        & $launch
        Assert-True ($script:launches -eq 1) 'A duplicate tick cannot start another worker.'

        foreach ($guard in @('Preview', 'Closing', 'IsDisposed', 'Disposing')) {
            Reset-Scenario
            $Preview = $guard -eq 'Preview'
            $script:closing = $guard -eq 'Closing'
            $form.IsDisposed = $guard -eq 'IsDisposed'
            $form.Disposing = $guard -eq 'Disposing'
            $workerStartTimer = New-FakeTimer
            & $paintCompleted
            & $launch
            Assert-True ($script:launches -eq 0 -and -not $script:workerLaunchAttempted) "$guard must prevent preparation."
            if ($Preview -or $script:closing) {
                Assert-True ($workerStartTimer.Starts -eq 0) "$guard must not queue preparation."
            }
        }

        Reset-Scenario
        $Preview = $false
        $form.IsDisposed = $false
        $form.Disposing = $false
        $workerStartTimer = New-FakeTimer
        & $paintCompleted
        $script:closing = $true
        & $launch
        Assert-True ($script:launches -eq 0) 'Closing between paint and tick prevents preparation.'
        function Read-LDLCProgressFile {}
        function Update-LDLCCompactUi {}
        $script:stopFileCreated = $true
        $script:closeStep = 0
        & $poll
        Assert-True ($form.CloseCalls -eq 1 -and $script:allowFormClose) 'Existing close polling closes normally when the worker has not started.'
        & $cleanup
        Assert-True ($workerStartTimer.Disposed -and -not $workerStartTimer.Enabled) 'Leaving the UI stops and disposes the deferred timer.'

        Reset-Scenario
        $WorkerLauncher = { $script:launches++; throw 'Expected launcher failure' }
        Remove-Item Env:\LDLC_DEFAULT_APPS_UI -ErrorAction SilentlyContinue
        $caught = $false
        try { & $launch } catch { $caught = $_.Exception.Message -eq 'Expected launcher failure' }
        $hasExistingCatch = $launchAst.Extent.Text.Contains('Demarrage bloque.')
        Assert-True ($caught -eq (-not $hasExistingCatch)) 'Preserve the edition-specific launcher error handling.'
        Assert-True ($script:launches -eq 1 -and $script:workerLaunchAttempted -and $null -eq $script:proc -and
            $null -eq $env:LDLC_DEFAULT_APPS_UI) 'Failed launch restores the absent environment flag without creating a worker.'
        if ($hasExistingCatch) {
            Assert-True ($script:percent -eq 0 -and $script:message -like 'Demarrage bloque.*') 'Blocked launch remains at zero with its existing message.'
        }
        & $launch
        Assert-True ($script:launches -eq 1) 'A failed launch is not retried on another tick.'
        Write-Host "OK first-paint lifecycle: $path"
    }
    Write-Host "OK $script:assertions assertions; real callbacks, fake timers/workers; no preparation or telemetry."
}
finally {
    if ($null -eq $originalCompactUi) { Remove-Item Env:\LDLC_DEFAULT_APPS_UI -ErrorAction SilentlyContinue }
    else { $env:LDLC_DEFAULT_APPS_UI = $originalCompactUi }
}
