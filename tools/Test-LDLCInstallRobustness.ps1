$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$appsPath = Join-Path $root 'modules\30.Applications.ps1'
$gpuPath = Join-Path $root 'modules\60.Gpu.ps1'
$cleanupPath = Join-Path $root 'modules\50.Cleanup.ps1'
$workflowPath = Join-Path $root 'modules\90.Workflow.ps1'

$apps = Get-Content -LiteralPath $appsPath -Raw -Encoding UTF8
$gpu = Get-Content -LiteralPath $gpuPath -Raw -Encoding UTF8
$cleanup = Get-Content -LiteralPath $cleanupPath -Raw -Encoding UTF8
$workflow = Get-Content -LiteralPath $workflowPath -Raw -Encoding UTF8

foreach ($required in @(
    'function Get-LDLCInstallerCacheRoot',
    'C:\LDLC_PREPTOOL\Installers',
    'function Get-LDLCOfficialInstallerSources',
    'function Test-LDLCInstallerFile',
    'function Invoke-LDLCOfficialInstaller',
    'function Install-LDLCApplication',
    'function Get-LDLCAppInstallationState',
    'Format-LDLCAppInstallationState'
)) {
    if ($apps -notmatch [regex]::Escape($required)) {
        throw "Brique d installation officielle/cache manquante : $required"
    }
}

if ($apps -match 'Install-ChocolateyIfNeeded' -or
    $apps -match 'community\.chocolatey\.org/install\.ps1') {
    throw 'Chocolatey ne doit jamais etre installe automatiquement.'
}

if ($apps -match 'Join-Path\s+\(if\s*\(') {
    throw 'Le moteur officiel ne doit pas utiliser Join-Path (if ...), invalide dans cette position PowerShell.'
}

if ($workflow -match 'Chocolatey|Install-Or-ReinstallWithChoco|Clear-InstallCaches') {
    throw 'Le workflow normal ne doit plus dependre de Winget/Chocolatey ni effacer le cache officiel.'
}

if ($workflow -notmatch 'Initialize-LDLCInstallerCache' -or
    $workflow -notmatch 'Install-LDLCApplication -App \$app') {
    throw 'Le workflow doit initialiser le cache puis utiliser la chaine officielle.'
}

$installBlock = [regex]::Match($apps, 'function Install-LDLCApplication \{(?s).*?\n\}')
if (-not $installBlock.Success) {
    throw 'Fonction Install-LDLCApplication introuvable.'
}

$officialIndex = $installBlock.Value.IndexOf('Install-LDLCAppWithDirectInstaller')
$wingetIndex = $installBlock.Value.IndexOf('Install-LDLCAppWithWinget')
$chocoIndex = $installBlock.Value.IndexOf('Install-LDLCAppWithChocolatey')
if ($officialIndex -lt 0 -or ($wingetIndex -ge 0 -and $wingetIndex -lt $officialIndex) -or ($chocoIndex -ge 0 -and $chocoIndex -lt $officialIndex)) {
    throw 'L installateur officiel/cache doit etre tente avant tout gestionnaire de paquets.'
}

if ($installBlock.Value -notmatch 'LDLC_ENABLE_PACKAGE_MANAGER_FALLBACK') {
    throw 'Winget/Chocolatey doivent etre proteges par un opt-in explicite.'
}

foreach ($name in 'Google Chrome', 'LibreOffice', 'Adobe Acrobat Reader', '7-Zip', 'VLC media player') {
    $pattern = '(?s)@\{\s*Name\s*=\s*"' + [regex]::Escape($name) + '".*?DirectInstaller\s*=\s*@\{.*?Provider.*?TrustedHosts.*?SignerPattern.*?CachePatterns'
    if ($apps -notmatch $pattern) {
        throw "Definition officielle/cache incomplete pour : $name"
    }
}

if ($apps -notmatch 'Resolver\s*=\s*"SevenZipLatestX64"' -or
    $apps -notmatch 'Resolver\s*=\s*"LibreOfficeStableX64"') {
    throw '7-Zip et LibreOffice doivent resoudre leur version depuis les pages officielles.'
}

if ($apps -match 'Test-AppReallyInstalled -App \$App -Refresh -or \(Test-AppInstalledInRegistry') {
    throw 'Une entree registre seule ne doit jamais valider une installation.'
}

if ($apps -notmatch 'HasExecutable' -or
    $apps -notmatch 'HasRegistry' -or
    $apps -notmatch 'FileVersion' -or
    $apps -notmatch 'IsInstalled\s*=\s*\[bool\]\(\$hasExecutable') {
    throw 'La validation finale doit combiner executable, registre et version.'
}

if ($cleanup -notmatch 'TimeoutSeconds' -or $cleanup -notmatch 'RetryCount') {
    throw 'Les telechargements doivent avoir un timeout et des reprises limitees.'
}

foreach ($required in @(
    'Resolve-LDLCNvidiaDriverOfficialSources',
    'Get-LDLCNvidiaAppInstallerDefinition',
    'Get-LDLCNvidiaDriverInstallerDefinition',
    'Get-LDLCAmdAdrenalinInstallerDefinition',
    'Install-LDLCNvidiaDriverOfficial',
    'PnpDeviceId'
)) {
    if ($gpu -notmatch [regex]::Escape($required)) {
        throw "Brique GPU officielle manquante : $required"
    }
}

$nvidiaStack = [regex]::Match($gpu, 'function Install-LDLCNvidiaStack \{(?s).*?\n\}')
if (-not $nvidiaStack.Success) {
    throw 'La pile NVIDIA est introuvable.'
}

$officialNvidiaIndex = $nvidiaStack.Value.IndexOf('Install-LDLCNvidiaDriverOfficial')
$nvidiaFallbackIndex = $nvidiaStack.Value.IndexOf('Invoke-LDLCNvidiaGameReadyChocolateyFallback')
if ($officialNvidiaIndex -lt 0 -or $nvidiaFallbackIndex -lt 0 -or $nvidiaFallbackIndex -lt $officialNvidiaIndex) {
    throw 'Le pilote NVIDIA officiel doit rester la methode principale avant le fallback Chocolatey.'
}

if ($gpu -match 'community\.chocolatey\.org/install\.ps1') {
    throw 'Le module GPU ne doit jamais installer Chocolatey automatiquement.'
}

Write-Host 'OK official installer robustness'
