param([string]$ModuleRoot = '', [string]$ReportPath = '')
$ErrorActionPreference = 'Stop'
if (-not $ModuleRoot) { $ModuleRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'modules' }
. (Join-Path $ModuleRoot '00.Core.ps1')
. (Join-Path $ModuleRoot '05.Telemetry.ps1')
. (Join-Path $ModuleRoot '90.Workflow.ps1')
$mainCommands = (Get-Item Function:\Invoke-LDLCPreparation).ScriptBlock.Ast.FindAll({ param($n) $n -is [Management.Automation.Language.CommandAst] }, $true) | ForEach-Object { $_.GetCommandName() }
$script:TriggerOnly = 'Wait-LDLCWindowsUpdateWorkerCompletion' -notin $mainCommands -and 'Invoke-LDLCWindowsUpdatesWithTimeout' -notin $mainCommands
# Execute the real Quit click handler with a form double. No desktop changes.
$ui = [Management.Automation.Language.Parser]::ParseFile((Join-Path $ModuleRoot '99.UI.ps1'), [ref]$null, [ref]$null)
$helper = $ui.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Test-LDLCUiFinalizationReady' }, $true)
if ($helper) { . ([scriptblock]::Create($helper.Extent.Text)) }
$click = $ui.Find({ param($n) $n -is [Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Member.Value -eq 'Add_Click' -and $n.Expression.VariablePath.UserPath -eq 'closeButton' }, $true)
$script:QuitHandler = [scriptblock]::Create($click.Arguments[0].ScriptBlock.Extent.Text.Trim().Substring(1).TrimEnd().TrimEnd('}'))
$script:Checks = New-Object 'Collections.Generic.List[object]'
$script:Rows = New-Object 'Collections.Generic.List[object]'
function Check([bool]$Value, [string]$Name) { $script:Checks.Add([pscustomobject]@{ Check=$Name; Passed=$Value }) }
function Get-LDLCComputerTelemetryInfo { [pscustomobject]@{ ComputerName='FIXTURE-PC'; UserName=''; UserDomain=''; SerialNumber='FIXTURE'; Manufacturer=''; Model=''; OSCaption=''; OSVersion=''; TimeZone='Europe/Paris' } }
function Get-LDLCEntryPointPath { 'FIXTURE.ps1' }
function Get-LDLCRuntimeRoot { $script:RuntimeRoot }
function Clear-Host {}
function Start-Sleep {}
function Write-Section {}
function Write-Step {}
function Write-LDLCLocalLog {}
function Invoke-LDLCSecurityCleanupIsolated {}
function Remove-LDLCSecurityTrialsInteractively {
    if ($script:Case -eq 'antivirus_refuse') { throw 'Desinstallation Norton interrompue/refusee (code 1602). Preparation arretee.' }
    if ($script:Case -eq 'antivirus_arret') { throw 'LDLC_STOP_REQUESTED' }
}
function Invoke-LDLCRestorePointCreation {}
function Get-FixtureWindowsUpdateLaunch {
    if ($script:Case -eq 'echec_lancement_windows_update') {
        Write-Err 'Impossible de lancer Windows Update en arriere-plan : acces refuse.'
        return @{ Started=$false; Success=$false; LastError='Acces refuse'; Error='Acces refuse' }
    }
    # La demande a ete transmise, sans aucune preuve de fin des mises a jour.
    return @{ Started=$true; Success=$true; Completed=$false; RemainingCount=12; TimedOut=$true; RebootRequired=$false }
}
function Start-LDLCWindowsUpdatesDuringPreparation { Get-FixtureWindowsUpdateLaunch }
function Invoke-LDLCWindowsUpdateTrigger { Get-FixtureWindowsUpdateLaunch }
function Invoke-LDLCInitialSetup {}
function Set-LDLCWindowsLayout {}
function Ensure-LDLCWallpaperApplied {}
function Initialize-LDLCInstallerCache {}
function Install-ChocolateyIfNeeded {}
function Clear-InstallCaches {}
function Install-LDLCApplication {
    $script:ApplicationCalls++
    if ($script:Case -eq 'erreur') { Write-Err 'Google Chrome non installe : code 1603.' }
    if ($script:Case -eq 'avertissement') { Write-Warn 'Commande Chrome non effectuee : controle Windows indisponible.' }
    if ($script:Case -eq 'delai' -and -not $script:TriggerOnly) { Write-Warn 'Verification partielle avant expiration du delai.' }
}
function Install-Or-ReinstallWithChoco { Install-LDLCApplication }
function Set-LDLCWallpaper {}
function Invoke-LDLCChromeDefaultAppsSequence {}
function Enable-DesktopSystemIcons {}
function Invoke-LDLCVendorUtility {} # Separate beta integration suite tests this step.
function Install-LDLCGpuDriversAndApps {}
function Remove-LDLCOemAndSecurityTrials {}
function Remove-LDLCMicrosoftOffice {}
function Invoke-LDLCChromeTaskbarPinBeforeWindowsUpdate {}
function Repair-LDLCDesktopShortcuts {}
function Set-LDLCDesktopOrderedLayout {}
function Restore-PowerSettings { $script:PowerSettingsRestored=$true }
function Wait-LDLCWindowsUpdateWorkerCompletion {
    $script:WaitCalls++
    if ($script:Case -eq 'delai') { return @{ Success=$false; TimedOut=$true; BackgroundFallbackStarted=$false; Completed=$false; LastError='Delai Windows Update depasse'; RemainingCount=2 } }
    return @{ Success=$true; TimedOut=$false; RebootRequired=$false; Completed=$true }
}
function Invoke-LDLCWindowsUpdatesWithTimeout { Wait-LDLCWindowsUpdateWorkerCompletion }
function Stop-IfRequested {
    $percent = 0
    if (Test-Path -LiteralPath $script:ProgressFile) {
        $raw = [IO.File]::ReadAllText($script:ProgressFile)
        [void][int]::TryParse(($raw -split '\|', 2)[0], [ref]$percent)
    }
    if ($script:Case -eq 'fermeture_anticipee' -and $percent -ge 25) { throw 'LDLC_STOP_REQUESTED' }
}
$script:RealWriteQueuedTelemetryPayloads = (Get-Item Function:\Write-LDLCQueuedTelemetryPayloads).ScriptBlock
function Write-LDLCQueuedTelemetryPayloads {
    param([object[]]$Payloads)
    if ($script:ForceQueueFailure) { return $false }
    return (& $script:RealWriteQueuedTelemetryPayloads -Payloads $Payloads)
}
function Send-LDLCTelemetryPayloads {
    param([object[]]$Payloads)
    foreach ($payload in $Payloads) {
        if (-not $payload.Run.IsFinal -and -not $payload.Run.FinishedAt) { continue }
        $script:Final = $payload
        if ($script:Case -eq 'fermeture_apres_fin') {
            $script:proc=[Diagnostics.Process]::GetCurrentProcess()
            $script:runtimeRoot=$script:RuntimeRoot
            $script:closing=$false; $script:allowFormClose=$false
            $script:closeMouseArmedUntil=(Get-Date).AddMinutes(1)
            $Preview=$false
            $form=[pscustomobject]@{Closed=$false;Cursor='Default'}
            $form | Add-Member ScriptMethod Close { $this.Closed=$true }
            $closeButton=[pscustomobject]@{Enabled=$true;Text='Quitter'}
            $before=[Diagnostics.Stopwatch]::StartNew()
            & $script:QuitHandler
            $before.Stop()
            $script:CloseSeconds=$before.Elapsed.TotalSeconds
            $script:ClosedDuringPost=$form.Closed
            $script:StopCreated=Test-Path -LiteralPath $script:stopFile
        }
        if ($script:Case -like 'relance_*') {
            # A second worker claims the shared runtime and has already reached
            # installation while the first worker's final POST is still pending.
            $script:NewRunId = [guid]::NewGuid().ToString('N')
            Initialize-LDLCProgressOwner -RunId $script:NewRunId
            $script:NewRunOwner = [IO.File]::ReadAllText($script:LDLCProgressOwnerPath)
            $script:NewRunProgress = '25|Installation du nouveau lancement...'
            [IO.File]::WriteAllText($script:ProgressFile, $script:NewRunProgress)
            if ($script:Case -eq 'relance_sauvegarde_impossible') { $script:ForceQueueFailure=$true }
            if ($script:Case -ne 'relance_post_acquitte') { throw 'Reseau de test indisponible apres relance' }
        }
        if ($script:Case -eq 'hors_ligne') { throw 'Reseau de test indisponible' }
    }
}
$saved=@{}
foreach ($name in @('LDLC_TELEMETRY_DISABLED','LDLC_TELEMETRY_RUN_ID','LDLC_TELEMETRY_REMOTE_MODE')) { $saved[$name]=[Environment]::GetEnvironmentVariable($name,'Process') }
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('LDLC-Final-Test-'+[guid]::NewGuid().ToString('N'))
try {
    $env:LDLC_TELEMETRY_DISABLED='0'; $env:LDLC_TELEMETRY_REMOTE_MODE='start-final'
    Remove-Item Env:\LDLC_TELEMETRY_RUN_ID -ErrorAction SilentlyContinue
    $cases = @('fin_normale','fermeture_apres_fin','erreur','avertissement','delai','fermeture_anticipee','hors_ligne')
    if ('Remove-LDLCSecurityTrialsInteractively' -in $mainCommands) { $cases += @('antivirus_refuse','antivirus_arret') }
    if ($script:TriggerOnly) { $cases += 'echec_lancement_windows_update' }
    if (Get-Command Initialize-LDLCProgressOwner -ErrorAction SilentlyContinue) { $cases += @('relance_post_acquitte','relance_hors_ligne','relance_sauvegarde_impossible') }
    foreach ($caseName in $cases) {
        $script:WaitCalls=0; $script:ApplicationCalls=0
        $script:Case=$caseName; $script:RuntimeRoot=Join-Path $testRoot $caseName
        New-Item -ItemType Directory -Path $script:RuntimeRoot -Force | Out-Null
        $script:ProgressFile=Join-Path $script:RuntimeRoot 'LDLC_PROGRESS.txt'
        $script:stopFile=Join-Path $script:RuntimeRoot 'LDLC_STOP'
        $script:LDLCTelemetryInitialized=$false; $script:Final=$null
        $script:ForceQueueFailure=$false
        $script:PowerSettingsCaptured=$true; $script:PowerSettingsRestored=$false; $script:PendingReboot=$false
        $Apps=@([pscustomobject]@{Name='Chrome'})
        Initialize-LDLCTelemetry
        Invoke-LDLCPreparation | Out-Null
        $run=$script:Final.Run
        $expected=switch($caseName){'antivirus_refuse' {'failed'} 'antivirus_arret' {'stopped'} 'erreur' {'failed'} 'avertissement' {'warning'} 'delai' {if ($script:TriggerOnly) {'success'} else {'timeout'}} 'echec_lancement_windows_update' {'failed'} 'fermeture_anticipee' {'stopped'} default {'success'}}
        Check ($run.Status -eq $expected) "$caseName : statut $expected (observe $($run.Status))"
        Check ([bool]$run.IsFinal -and [bool]$run.FinishedAt) "$caseName : resultat final explicite"
        Check ($run.CompletionConfirmed -eq ($caseName -notin @('fermeture_anticipee','antivirus_refuse','antivirus_arret'))) "$caseName : preuve de fin exacte"
        if ($expected -ne 'success') { Check (-not [string]::IsNullOrWhiteSpace($run.BlockingReason)) "$caseName : cause du blocage conservee" }
        if ($caseName -like 'antivirus_*') { Check ($script:ApplicationCalls -eq 0) 'Antivirus: aucune installation apres refus/arret'; if($caseName -eq 'antivirus_refuse'){Check ($run.BlockingReason -match '1602') 'Antivirus: cause 1602 conservee'} }
        if ($caseName -eq 'erreur') { Check ($run.LastMessage -match '1603') 'Erreur : code 1603 visible' }
        if ($caseName -eq 'delai' -and -not $script:TriggerOnly) { Check ($run.BlockingReason -match 'Delai|delai') 'Delai : cause non masquee par avertissement' }
        if ($script:TriggerOnly) { Check ($script:WaitCalls -eq 0) "$caseName : aucune attente Windows Update" }
        if ($caseName -eq 'echec_lancement_windows_update') { Check ($run.BlockingReason -match 'acces refuse') 'Echec lancement : cause precise conservee' }
        if ($caseName -eq 'fermeture_apres_fin') {
            Check $script:ClosedDuringPost 'Quitter ferme pendant le POST final'
            Check (-not $script:StopCreated) 'Quitter ne demande pas un arret du worker finalise'
            Check ($script:CloseSeconds -lt 1) 'Fermeture locale sans attente reseau'
        }
        $script:Rows.Add([pscustomobject]@{Scenario=$caseName;Status=$run.Status;CompletionConfirmed=$run.CompletionConfirmed;Reason=$run.BlockingReason;IsFinal=$run.IsFinal})
        if ($caseName -eq 'hors_ligne') {
            $pending=@(Read-LDLCQueuedTelemetryPayloads)
            Check ($pending.Count -eq 1 -and $pending[0].Run.IsFinal) 'Hors ligne : fin durable conservee'
            Check ((Get-Content -LiteralPath $script:ProgressFile -Raw) -match 'non transmise') 'Hors ligne : absence de confirmation visible'
        }
        if ($caseName -like 'relance_*') {
            Check ([IO.File]::ReadAllText($script:ProgressFile) -eq $script:NewRunProgress) "$caseName : ancien POST sans reecriture de la progression courante"
            Check ([IO.File]::ReadAllText($script:LDLCProgressOwnerPath) -eq $script:NewRunOwner) "$caseName : proprietaire du nouveau run conserve"
            Check ($script:Final.Run.RunId -ne $script:NewRunId) "$caseName : rapport final rattache uniquement a l'ancien run"
        }
    }
    if (Get-Command Test-LDLCFinalizationReady -ErrorAction SilentlyContinue) {
        Check (-not (Test-LDLCFinalizationReady -RuntimeRoot $script:RuntimeRoot -WorkerProcessId ($PID+1) -WorkerStartTicks 1)) 'Un accuse ancien ne finalise pas un autre worker'
    }
    if (Get-Command Initialize-LDLCProgressOwner -ErrorAction SilentlyContinue) {
        $ownerPath = $script:LDLCProgressOwnerPath
        $ownerBefore = [IO.File]::ReadAllText($ownerPath)
        $WindowsUpdateWorker = $true
        $env:LDLC_TELEMETRY_DISABLED = '1'
        $script:LDLCTelemetryInitialized = $false
        Initialize-LDLCTelemetry
        Check ([IO.File]::ReadAllText($ownerPath) -eq $ownerBefore) 'Un worker auxiliaire ne revendique pas la progression principale'
        $WindowsUpdateWorker = $false
    }
    $report=[ordered]@{Scenarios=@($script:Rows.ToArray());Checks=@($script:Checks.ToArray())}
    if ($ReportPath) { $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ReportPath -Encoding UTF8 }
    $failed=@($script:Checks | Where-Object { -not $_.Passed })
    $failed | ForEach-Object { Write-Host ('ECHEC : '+$_.Check) }
    if ($failed.Count) { throw "$($failed.Count) controles en echec sur $($script:Checks.Count)." }
    Write-Host "OK fin intervention : $($cases.Count) scenarios, $($script:Checks.Count) controles, fermeture et relance durant le POST sans installation reelle."
}
finally {
    foreach($name in $saved.Keys){[Environment]::SetEnvironmentVariable($name,$saved[$name],'Process')}
    if ((Split-Path $testRoot -Leaf) -like 'LDLC-Final-Test-*') { Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
