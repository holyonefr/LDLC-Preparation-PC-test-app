param(
    [switch]$SourceOnly,
    [switch]$AllModules
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$retiredPattern = '(?i)validator|LDLC_Valid_|8B6356C13D2566AB686A9AA505DC423317CD66C65310F7E74799C684B7137966|F4D9677E8269145AB59B31082376BBFDB508BC745CED015B6B4D9E3366D6A04A'
$sourcePaths = @(
    'modules\00.Bootstrap.ps1',
    'modules\00.Core.ps1',
    'modules\40.Desktop.ps1',
    'modules\50.Cleanup.ps1',
    'tools\Build-LDLCPreparationPCExe.ps1',
    'tools\Rebuild-LDLCPreparationPC.ps1',
    'tools\Update-LDLCExecutableResources.ps1',
    'tools\ManagedResourceRewriter\Program.cs'
) | ForEach-Object { Join-Path $root $_ }
$sourcePaths += @(Get-ChildItem -LiteralPath (Join-Path $root 'tools\LDLCPreparationPC.Launcher') -File | Select-Object -ExpandProperty FullName)
if ($AllModules) {
    $sourcePaths += @(Get-ChildItem -LiteralPath (Join-Path $root 'modules') -Filter '*.ps1' -File | Select-Object -ExpandProperty FullName)
}
foreach ($path in ($sourcePaths | Select-Object -Unique)) {
    if ((Get-Content -LiteralPath $path -Raw -Encoding UTF8) -match $retiredPattern) {
        throw "Dependance retiree encore presente : $path"
    }
}

if (-not $SourceOnly) {
    foreach ($directory in @('assets', 'dist')) {
        $retiredFiles = @(Get-ChildItem -LiteralPath (Join-Path $root $directory) -File -Recurse |
            Where-Object { $_.Name -match '(?i)validator|LDLC_Valid_' })
        if ($retiredFiles.Count) {
            throw "Artefact retire encore present : $($retiredFiles.FullName -join ', ')"
        }
    }
}

# Import function definitions only: bootstrap/desktop top-level code touches Windows.
$requiredFunctions = @{
    'modules\00.Bootstrap.ps1' = @(
        'Get-LDLCByteArraySha256', 'Test-LDLCFileHash', 'Test-LDLCFileReadable',
        'Install-LDLCEmbeddedUiAssets', 'Install-LDLCEmbeddedWorkerScript'
    )
    'modules\40.Desktop.ps1' = @('Repair-LDLCDesktopShortcuts', 'Remove-LDLCUserDiagDesktopItems')
}
foreach ($relative in $requiredFunctions.Keys) {
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root $relative), [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count) { throw "Syntaxe invalide : $relative" }
    foreach ($name in $requiredFunctions[$relative]) {
        $definitions = @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
        }, $true))
        if ($definitions.Count -ne 1) { throw "Fonction partagee absente ou dupliquee : $name" }
        . ([scriptblock]::Create($definitions[0].Extent.Text))
    }
}

function Write-LDLCBootstrapLog { param([string]$Message) }
function Stop-IfRequested {}
function Write-Section { param([string]$Text) }
function Write-Step { param([string]$Text) }
function Write-Ok { param([string]$Text) }
function Write-Warn { param([string]$Text) throw "Avertissement inattendu : $Text" }
function Get-LDLCDesktopPaths { return @($script:testDesktop) }
function Ensure-DesktopShortcut { param($App) [void]$script:shortcutCalls.Add($App.Name) }
function Get-LDLCGpuVendor { return @{ Vendor = 'Intel' } }
function Test-LDLCDedicatedGpu { param($GpuInfo) return $false }
function Ensure-LDLCGpuDesktopShortcut { param($Vendor) throw 'Aucun raccourci GPU attendu.' }

$testRoot = Join-Path $root ('.packaging-unit-' + [guid]::NewGuid().ToString('N') + '.tmp')
New-Item -ItemType Directory -Path $testRoot | Out-Null
try {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes('abc')
    $hash = 'BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD'
    if ((Get-LDLCByteArraySha256 -Bytes $bytes) -ne $hash) { throw 'Calcul SHA-256 partage incorrect.' }
    $missingPath = Join-Path $testRoot 'absent.bin'
    if ((Test-LDLCFileHash -Path $missingPath -ExpectedSha256 $hash) -or (Test-LDLCFileReadable -Path $missingPath)) {
        throw 'Un fichier absent ne doit pas etre valide.'
    }

    $script:LDLCEmbeddedUiAssetPayloads = @()
    $script:LDLCEmbeddedWorkerPayload = $null
    if (-not (Install-LDLCEmbeddedUiAssets -RuntimeRoot $testRoot) -or
        $null -ne (Install-LDLCEmbeddedWorkerScript -RuntimeRoot $testRoot)) {
        throw 'Les ressources facultatives vides doivent rester prises en charge.'
    }
    $script:LDLCEmbeddedUiAssetPayloads = @(@{
        FileNames = @('UI_Background.v2.png', 'UI_Background.png')
        Sha256 = $hash
        Base64 = [Convert]::ToBase64String($bytes)
    })
    [void](Install-LDLCEmbeddedUiAssets -RuntimeRoot $testRoot)
    $assetPath = Join-Path $testRoot 'UI_Background.v2.png'
    foreach ($name in $script:LDLCEmbeddedUiAssetPayloads[0].FileNames) {
        if (-not (Test-LDLCFileHash -Path (Join-Path $testRoot $name) -ExpectedSha256 $hash)) {
            throw "Ressource UI invalide : $name"
        }
    }
    $lock = [System.IO.File]::Open($assetPath, 'Open', 'Read', 'Read')
    try { [void](Install-LDLCEmbeddedUiAssets -RuntimeRoot $testRoot) }
    finally { $lock.Dispose() }
    [System.IO.File]::WriteAllText($assetPath, 'stale')
    if (Test-LDLCFileHash -Path $assetPath -ExpectedSha256 $hash) { throw 'Hash altere accepte.' }
    [void](Install-LDLCEmbeddedUiAssets -RuntimeRoot $testRoot)
    if (-not (Test-LDLCFileHash -Path $assetPath -ExpectedSha256 $hash)) { throw 'Remplacement atomique UI en echec.' }

    $script:LDLCEmbeddedUiAssetPayloads[0].Base64 = [Convert]::ToBase64String([byte[]]@(1, 2, 3))
    $rejected = $false
    try { [void](Install-LDLCEmbeddedUiAssets -RuntimeRoot $testRoot) } catch { $rejected = $true }
    if (-not $rejected -or -not (Test-LDLCFileHash -Path $assetPath -ExpectedSha256 $hash)) {
        throw 'Une charge UI alteree doit etre refusee sans modifier la ressource valide.'
    }
    $script:LDLCEmbeddedUiAssetPayloads[0].Base64 = [Convert]::ToBase64String($bytes)
    $script:LDLCEmbeddedUiAssetPayloads[0].FileNames = @('..\outside.png')
    $rejected = $false
    try { [void](Install-LDLCEmbeddedUiAssets -RuntimeRoot $testRoot) } catch { $rejected = $true }
    if (-not $rejected) { throw 'Un chemin UI sortant du runtime doit etre refuse.' }

    $script:LDLCEmbeddedWorkerPayload = @{ Sha256 = $hash; Base64 = [Convert]::ToBase64String($bytes) }
    $workerPath = Install-LDLCEmbeddedWorkerScript -RuntimeRoot $testRoot
    if (-not (Test-LDLCFileHash -Path $workerPath -ExpectedSha256 $hash) -or -not (Test-LDLCFileReadable -Path $workerPath)) {
        throw 'Worker partage invalide ou illisible.'
    }
    $lock = [System.IO.File]::Open($workerPath, 'Open', 'Read', 'Read')
    try {
        if ((Install-LDLCEmbeddedWorkerScript -RuntimeRoot $testRoot) -ne $workerPath) { throw 'Worker valide non reutilise.' }
    }
    finally { $lock.Dispose() }
    $script:LDLCEmbeddedWorkerPayload.Base64 = [Convert]::ToBase64String([byte[]]@(1, 2, 3))
    $rejected = $false
    try { [void](Install-LDLCEmbeddedWorkerScript -RuntimeRoot $testRoot) } catch { $rejected = $true }
    if (-not $rejected -or -not (Test-LDLCFileHash -Path $workerPath -ExpectedSha256 $hash)) {
        throw 'Un worker altere doit etre refuse sans modifier le worker valide.'
    }

    $script:testDesktop = Join-Path $testRoot 'DesktopFixture'
    New-Item -ItemType Directory -Path $script:testDesktop | Out-Null
    foreach ($name in @('UserDiag.exe', 'UserDiag.lnk', 'notes.txt', 'LDLC Validator.exe', 'LDLC_Valid_fixture.zip')) {
        [System.IO.File]::WriteAllText((Join-Path $script:testDesktop $name), 'fixture')
    }
    Remove-LDLCUserDiagDesktopItems
    foreach ($name in @('UserDiag.exe', 'UserDiag.lnk')) {
        if (Test-Path -LiteralPath (Join-Path $script:testDesktop $name)) { throw "Nettoyage UserDiag perdu : $name" }
    }
    foreach ($name in @('notes.txt', 'LDLC Validator.exe', 'LDLC_Valid_fixture.zip')) {
        if ([System.IO.File]::ReadAllText((Join-Path $script:testDesktop $name)) -ne 'fixture') {
            throw "Un fichier hors nettoyage UserDiag a ete modifie : $name"
        }
    }
    $Apps = @(@{ Name = 'App'; CreateShortcut = $true }, @{ Name = 'Skip'; CreateShortcut = $false })
    $script:shortcutCalls = New-Object System.Collections.Generic.List[string]
    Repair-LDLCDesktopShortcuts
    if ($script:shortcutCalls.Count -ne 1 -or $script:shortcutCalls[0] -ne 'App') {
        throw 'La reparation des raccourcis applicatifs doit rester fonctionnelle sans outil diagnostic.'
    }
    if (@(Get-ChildItem -LiteralPath $testRoot -Filter '*.new*' -File).Count) { throw 'Fichiers temporaires non nettoyes.' }
}
finally {
    $resolvedTestRoot = [System.IO.Path]::GetFullPath($testRoot)
    $workspacePrefix = [System.IO.Path]::GetFullPath($root).TrimEnd('\') + '\'
    if (-not $resolvedTestRoot.StartsWith($workspacePrefix, [System.StringComparison]::OrdinalIgnoreCase) -or
        [System.IO.Path]::GetFileName($resolvedTestRoot) -notmatch '^\.packaging-unit-[a-f0-9]{32}\.tmp$') {
        throw 'Nettoyage refuse hors dossier de test du depot.'
    }
    Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
}

Write-Host 'OK no Validator source dependencies; shared hashes, UI assets, worker and desktop helpers preserved'
