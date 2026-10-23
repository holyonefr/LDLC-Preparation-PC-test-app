$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$defaultAppsPath = Join-Path $root 'modules\70.DefaultApps.ps1'
$windowsUpdatePath = Join-Path $root 'modules\80.WindowsUpdate.ps1'
$gpuPath = Join-Path $root 'modules\60.Gpu.ps1'
$desktopPath = Join-Path $root 'modules\40.Desktop.ps1'
$cleanupPath = Join-Path $root 'modules\50.Cleanup.ps1'
$workflowPath = Join-Path $root 'modules\90.Workflow.ps1'
$wallpaperPath = Join-Path $root 'modules\45.Wallpaper.ps1'
$telemetryPath = Join-Path $root 'modules\05.Telemetry.ps1'
$uiPath = Join-Path $root 'modules\99.UI.ps1'

$defaultApps = Get-Content -LiteralPath $defaultAppsPath -Raw -Encoding UTF8
$windowsUpdate = Get-Content -LiteralPath $windowsUpdatePath -Raw -Encoding UTF8
$gpu = Get-Content -LiteralPath $gpuPath -Raw -Encoding UTF8
$desktop = Get-Content -LiteralPath $desktopPath -Raw -Encoding UTF8
$cleanup = Get-Content -LiteralPath $cleanupPath -Raw -Encoding UTF8
$workflow = Get-Content -LiteralPath $workflowPath -Raw -Encoding UTF8
$wallpaper = Get-Content -LiteralPath $wallpaperPath -Raw -Encoding UTF8
$telemetry = Get-Content -LiteralPath $telemetryPath -Raw -Encoding UTF8
$ui = Get-Content -LiteralPath $uiPath -Raw -Encoding UTF8

if ($defaultApps -match 'SendKeys|SendWait') {
    throw 'Default Apps ne doit pas utiliser SendKeys.'
}

if ($defaultApps -match 'deja navigateur par defaut') {
    throw 'Default Apps ne doit plus ignorer Chrome avec un faux deja par defaut.'
}

if ($defaultApps -match 'if \(Set-LDLCAdobePdfDefaultWithSetUserFTA\)\s*\{\s*return \$true\s*\}') {
    throw 'SetUserFTA ne doit plus valider seul Adobe PDF sans verification UI finale.'
}

if ($defaultApps -notmatch 'Get-LDLCEffectiveAssociation' -or
    $defaultApps -notmatch 'CurrentDefault' -or
    $defaultApps -notmatch 'Get-LDLCChromeDefaultBrowserState' -or
    $defaultApps -notmatch "@\('http', 'https', '\.htm', '\.html'\)" -or
    $defaultApps -notmatch 'Wait-LDLCChromeDefaultBrowserConfirmation' -or
    $defaultApps -notmatch 'Get-LDLCAdobePdfDefaultState' -or
    $defaultApps -notmatch 'Wait-LDLCAdobePdfDefaultConfirmation') {
    throw 'Default Apps doit forcer Chrome/PDF puis verifier les associations finales.'
}

if ($defaultApps -match [regex]::Escape('|((definir|set).*par defaut)|set default')) {
    throw 'Le bouton Chrome ne doit plus utiliser un libelle generique pouvant viser .PDF.'
}

if ($defaultApps -notmatch 'Select-LDLCDefaultAppsControl' -or $defaultApps -notmatch 'Get-LDLCDefaultAppsPickerRoot') {
    throw 'La selection Adobe Acrobat doit cibler la fenetre Ouvrir avec.'
}

if ($defaultApps -notmatch 'ScrollItemPattern' -or $defaultApps -notmatch 'ScrollPattern') {
    throw 'Le defilement Default Apps doit utiliser les patterns UIA.'
}

if ($defaultApps -notmatch '\$disabledByUserValue -or \$disabledByPolicy' -or
    $defaultApps -notmatch '\$policyValues\[\$supportedPolicy\]' -or $defaultApps -match '\$policyValues.Values\s*\|\s*Where-Object') {
    throw 'Widgets exige TaskbarDa=0 ou une strategie prise en charge pour cette version Windows ; une cle arbitraire ne suffit pas.'
}

if ($defaultApps -notmatch 'Wait-LDLCDefaultAppsCondition' -or
    $defaultApps -notmatch 'Set-LDLCDefaultAppsFocus') {
    throw 'Les lectures Default Apps doivent fonctionner meme si Windows refuse temporairement le premier plan.'
}

$updateAst = [Management.Automation.Language.Parser]::ParseFile($windowsUpdatePath, [ref]$null, [ref]$null)
$installUpdate = $updateAst.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Install-WindowsUpdates' }, $true)
if ($installUpdate.Extent.Text -notmatch 'Start-LDLCWindowsUpdateInBackground' -or
    $installUpdate.Extent.Text -match 'Invoke-LDLCWindowsUpdateFullMaintenance|New-Object -ComObject') {
    throw 'Le point entree Windows Update doit seulement transmettre les commandes natives.'
}

if ($windowsUpdate -match 'Restart-Computer|shutdown.exe|/r /t|Start-Process.*shutdown') {
    throw 'Windows Update ne doit jamais redemarrer automatiquement le PC.'
}



if ($gpu -notmatch 'function Get-LDLCNvidiaAppInstallation' -or
    $gpu -notmatch 'Get-LDLCNvidiaAppInstallerDefinition' -or
    $gpu -notmatch "Resolver\s*=\s*'NvidiaApp'") {
    throw 'NVIDIA App doit etre detectee et installee separement du pilote.'
}

if ($gpu -match 'community\.chocolatey\.org/install\.ps1') {
    throw 'Le module GPU ne doit jamais installer Chocolatey automatiquement.'
}

$nvidiaStack = [regex]::Match($gpu, 'function Install-LDLCNvidiaStack \{(?s).*?\n\}')
if (-not $nvidiaStack.Success -or
    $nvidiaStack.Value.IndexOf('Install-LDLCNvidiaDriverOfficial') -lt 0 -or
    $nvidiaStack.Value.IndexOf('Invoke-LDLCNvidiaGameReadyChocolateyFallback') -lt $nvidiaStack.Value.IndexOf('Install-LDLCNvidiaDriverOfficial')) {
    throw 'Le fallback Chocolatey NVIDIA doit rester strictement apres la methode officielle.'
}

if ($gpu -notmatch 'Registry\+Executable' -or $gpu -notmatch 'Entree registre NVIDIA App ignoree' -or $gpu -notmatch 'Get-LDLCAmdSoftwareExecutablePath') {
    throw 'Les applications GPU doivent etre confirmees par executable, pas uniquement par registre ou pilote.'
}

if ($gpu -notmatch 'Entree registre AMD Software ignoree' -or $gpu -notmatch 'RadeonSoftware.exe') {
    throw 'AMD Software Adrenalin doit etre detecte via ses executables principaux.'
}

if ($gpu -match '\$isIntelIntegrated\s+-or\s+\$isAmdIntegrated' -or
    $gpu -notmatch 'GPU AMD integre pris en charge' -or
    $gpu -notmatch 'Test-LDLCAmdGpuDriversReady' -or
    $gpu -notmatch 'Resolve-LDLCAmdGpuOfficialSource' -or
    $gpu -match "\`$null -ne \(Get-LDLCInstalledVendorDisplayDriver -Vendor 'AMD'\)") {
    throw 'Les GPU AMD integres doivent declencher AMD Adrenalin sans faux avertissement pilote avant redemarrage.'
}

if ($nvidiaStack.Value -notmatch 'Install-LDLCNvidiaAppIfNeeded') {
    throw 'NVIDIA App doit etre verifiee meme lorsqu un pilote NVIDIA est deja present.'
}

if ($desktop -notmatch [regex]::Escape('NVIDIA App\CEF\NVIDIA App.exe')) {
    throw 'Le raccourci NVIDIA App doit cibler le chemin CEF actuel.'
}

if ($desktop -match 'GeForce Experience') {
    throw 'GeForce Experience ne doit plus etre considere comme NVIDIA App.'
}

if ($desktop -notmatch 'AMDSoftware.exe') {
    throw 'Le raccourci AMD doit aussi chercher AMDSoftware.exe.'
}

if ($cleanup -notmatch 'Get-LDLCOfficeClickToRunExecutables' -or $cleanup -notmatch 'OutputTail') {
    throw 'Office Click-to-Run doit journaliser executables, codes et sortie commande.'
}

if ($cleanup -notmatch 'Office Click-to-Run absent') {
    throw 'Office Click-to-Run absent doit etre ignore proprement.'
}

if ($workflow -match [regex]::Escape('Enable-ComputerRestore -Drive "C:\"')) {
    throw 'Le point de restauration ne doit pas forcer C:\.'
}

if ($workflow -notmatch [regex]::Escape('$env:SystemDrive')) {
    throw 'Le point de restauration doit utiliser le lecteur systeme reel.'
}

if ($workflow -notmatch 'Point de restauration recent deja present' -or $workflow -notmatch 'droits administrateur requis') {
    throw 'Le point de restauration doit gerer les cas non bloquants avec logs precis.'
}

$securityIndex = $workflow.IndexOf('Invoke-LDLCSecurityCleanupIsolated -StartPercent 1 -EndPercent 2 -TimeoutSeconds 90 -SecurityVendor McAfee')
$nortonIndex = $workflow.IndexOf('Remove-LDLCSecurityTrialsInteractively -StartPercent 2 -EndPercent 3')
$restoreIndex = $workflow.IndexOf('Invoke-LDLCRestorePointCreation -ProgressPercent 4')
$windowsUpdateIndex = $workflow.IndexOf('Start-LDLCWindowsUpdatesDuringPreparation -StartPercent 5 -EndPercent 7')
$initialSetupIndex = $workflow.IndexOf('Invoke-LDLCInitialSetup')
$applicationIndex = $workflow.IndexOf('Install-LDLCApplication -App $app')
$oemIndex = $workflow.IndexOf('Remove-LDLCOemAndSecurityTrials -Mode Oem')
$powerRestoreIndex = $workflow.IndexOf('Restore-PowerSettings -ProgressPercent 97')
if (
    $securityIndex -lt 0 -or $nortonIndex -lt 0 -or $restoreIndex -lt 0 -or $windowsUpdateIndex -lt 0 -or
    $initialSetupIndex -lt 0 -or $applicationIndex -lt 0 -or $oemIndex -lt 0 -or
    $powerRestoreIndex -lt 0 -or
    -not ($securityIndex -lt $nortonIndex -and $nortonIndex -lt $restoreIndex -and $restoreIndex -lt $windowsUpdateIndex -and
        $windowsUpdateIndex -lt $initialSetupIndex -and $initialSetupIndex -lt $applicationIndex -and
        $applicationIndex -lt $oemIndex -and $oemIndex -lt $powerRestoreIndex)
) {
    throw 'Ordre requis invalide : McAfee/Norton, restauration, lancement Windows Update, initialisation, applications, OEM, restauration alimentation sans attente Windows Update.'
}

if ($workflow.IndexOf('Ensure-LDLCWallpaperApplied -ProgressPercent 18') -lt 0 -or $workflow.IndexOf('Write-ProgressFile 25') -lt 0 -or $workflow.IndexOf('Ensure-LDLCWallpaperApplied -ProgressPercent 18') -gt $workflow.IndexOf('Write-ProgressFile 25')) {
    throw 'Le fond d ecran doit etre applique avant les installations.'
}

if ($workflow -notmatch 'Ensure-LDLCWallpaperApplied -ProgressPercent 90 -VerifyOnly') {
    throw 'Le fond d ecran doit conserver une verification finale.'
}

if ($wallpaper -notmatch 'function Ensure-LDLCWallpaperApplied' -or $wallpaper -notmatch 'Test-LDLCWallpaperApplied' -or $wallpaper -notmatch 'non confirme apres deux tentatives') {
    throw 'Le fond d ecran doit etre verifie avec nouvelle tentative et warning final uniquement.'
}

if ($windowsUpdate -match 'Windows Update lance en arriere-plan.*-Severity warning') {
    throw 'Le lancement reussi de Windows Update en arriere-plan ne doit pas creer un avertissement.'
}

$workflowAst = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'modules/90.Workflow.ps1'), [ref]$null, [ref]$null)
$mainWorkflow = $workflowAst.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-LDLCPreparation' }, $true)
if ($mainWorkflow.Extent.Text -notmatch 'Start-LDLCWindowsUpdatesDuringPreparation' -or
    $mainWorkflow.Extent.Text -match 'Wait-LDLCWindowsUpdateWorkerCompletion|RemainingCount|TimedOut') {
    throw 'Windows Update doit etre declenche sans attente finale ni surveillance des mises a jour restantes.'
}

if ($telemetry -notmatch "return 'success'" -or $telemetry -notmatch 'Test-LDLCTelemetryInformationalWarningMessage') {
    throw 'La telemetrie doit distinguer succes final et messages informatifs avec un statut normalise.'
}

if ($telemetry -notmatch "return 'success'" -or $telemetry -match "return 'Terminé avec succès'") {
    throw 'La telemetrie doit envoyer success comme statut final normalise.'
}

if ($ui -notmatch 'AlphaCutoff 254' -or $ui -notmatch 'AlphaThreshold 254' -or $ui -notmatch 'AutoScaleMode') {
    throw 'La fenetre UI doit nettoyer le bord transparent et desactiver l autoscale WinForms.'
}

Write-Host 'OK hardening'
