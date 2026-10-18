param([switch]$SourceOnly)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'PreparationDelivery.Common.ps1')
$delivery = Get-PreparationDelivery $root
$exePath = $delivery.ExecutablePath
$hashManifestPath = Join-Path $root 'dist\SHA256SUMS.txt'
$launcherSourcePath = Join-Path $root 'tools\LDLCPreparationPC.Launcher\Program.cs'
$launcherManifestPath = Join-Path $root 'tools\LDLCPreparationPC.Launcher\app.manifest'
$buildPath = Join-Path $root 'tools\Build-LDLCPreparationPCExe.ps1'
$retiredPattern = '(?i)validator|LDLC_Valid_'

$build = Get-Content -LiteralPath $buildPath -Raw -Encoding UTF8
$launcherSource = Get-Content -LiteralPath $launcherSourcePath -Raw -Encoding UTF8
$launcherManifest = Get-Content -LiteralPath $launcherManifestPath -Raw -Encoding UTF8
foreach ($source in @($build, $launcherSource, $launcherManifest)) {
    if ($source -match $retiredPattern) { throw 'Le packaging ne doit plus dependre de LDLC Validator.' }
}
foreach ($needle in @('System.Management.Automation', 'RunspaceFactory.CreateRunspace', 'GetManifestResourceStream', 'AddScript')) {
    if ($launcherSource -notmatch [regex]::Escape($needle)) {
        throw "Garantie du lanceur .NET manquante : $needle"
    }
}
if ($launcherSource -notmatch 'LDLC_LAUNCHER_ERROR.log' -or
    $launcherSource -match 'Le moteur PowerShell a retourne une erreur inconnue') {
    throw 'Le lanceur doit journaliser les erreurs PowerShell sans erreur inconnue vide.'
}
if ($launcherManifest -notmatch 'requestedExecutionLevel level="requireAdministrator"') {
    throw 'Le manifeste du lanceur doit demander les droits administrateur.'
}
if ($build -match '(?i)Invoke-ps2exe|\bps2exe\b|ManagedResourceRewriter') {
    throw 'Le build contient encore une technique de packaging retiree pour Norton.'
}
foreach ($needle in @(
    '/resource:$mainScript,LDLCPreparationPC.ps1',
    'Compare-Object $expectedResources $resources',
    '$releaseFiles = @($outputFullPath, $manifestPath)',
    'foreach ($path in @($outputFullPath))',
    'SHA256SUMS.txt',
    'RequireSignature'
)) {
    if ($build -notmatch [regex]::Escape($needle)) { throw "Garantie de packaging manquante : $needle" }
}
if ($SourceOnly) {
    Write-Host 'OK launcher packaging sources, single embedded script and no diagnostic sidecar'
    return
}

foreach ($directory in @('assets', 'dist')) {
    $retiredFiles = @(Get-ChildItem -LiteralPath (Join-Path $root $directory) -File -Recurse |
        Where-Object { $_.Name -match $retiredPattern })
    if ($retiredFiles.Count) { throw "Artefact retire encore present : $($retiredFiles.FullName -join ', ')" }
}
foreach ($path in @($exePath, $hashManifestPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Fichier de packaging manquant : $path" }
}

$exe = Get-Item -LiteralPath $exePath
if ($exe.Length -gt 12582912) { throw "Executable principal trop gros : $($exe.Length) octets" }
$versionMatch = [regex]::Match($build, '\[string\]\$Version\s*=\s*''([^'']+)''')
if (-not $versionMatch.Success) { throw 'Version par defaut introuvable dans le script de build.' }
$expectedVersion = $versionMatch.Groups[1].Value
if (Test-Path -LiteralPath (Join-Path $root 'sync\core-version.json')) {
    $expectedVersion = (Get-Content -LiteralPath (Join-Path $root 'sync\core-version.json') -Raw | ConvertFrom-Json).ToolVersion + '.0'
}
$releaseBundlePath = Join-Path $root ('dist\' + $delivery.BaseName + '-' + $expectedVersion + '.zip')
if ($exe.VersionInfo.FileVersion -ne $expectedVersion) { throw "Version du lanceur inattendue : $($exe.VersionInfo.FileVersion)" }

$assembly = [System.Reflection.Assembly]::LoadFile($exe.FullName)
$resources = @($assembly.GetManifestResourceNames())
$expectedResources = @('LDLCPreparationPC.ps1')
if (Test-Path -LiteralPath (Join-Path $root 'branding\startup\Startup.cs')) { $expectedResources += 'PreparationEdition.StoreLogo' }
if (@(Compare-Object $expectedResources $resources).Count) {
    throw "Ressources du lanceur inattendues : $($resources -join ', ')"
}
$resourceStream = $assembly.GetManifestResourceStream('LDLCPreparationPC.ps1')
$reader = $null
try {
    if (-not $resourceStream -or $resourceStream.Length -le 100000) { throw 'Script PowerShell embarque absent ou incomplet.' }
    $reader = New-Object System.IO.StreamReader($resourceStream)
    $embeddedScript = $reader.ReadToEnd()
}
finally {
    if ($reader) { $reader.Dispose() }
    elseif ($resourceStream) { $resourceStream.Dispose() }
}

# Inspect the embedded worker as data; never execute bootstrap or touch the host.
$workerMatch = [regex]::Match($embeddedScript, '(?ms)\$script:LDLCEmbeddedWorkerPayload\s*=\s*@\{\s*Sha256 = ''([A-Fa-f0-9]{64})''\s*Base64 = @''\r?\n(.*?)\r?\n''@\s*\}')
if (-not $workerMatch.Success) { throw 'Worker embarque absent ou illisible.' }
$workerBytes = [Convert]::FromBase64String($workerMatch.Groups[2].Value)
$sha256 = [System.Security.Cryptography.SHA256]::Create()
try { $workerHash = [BitConverter]::ToString($sha256.ComputeHash($workerBytes)).Replace('-', '') }
finally { $sha256.Dispose() }
if ($workerHash -ne $workerMatch.Groups[1].Value) { throw 'Empreinte du worker embarque incorrecte.' }
$workerScript = [System.Text.Encoding]::UTF8.GetString($workerBytes).TrimStart([char]0xFEFF)
foreach ($scriptText in @($embeddedScript, $workerScript)) {
    if ($scriptText -match $retiredPattern) { throw 'Une dependance retiree reste dans le script ou le worker embarque.' }
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseInput($scriptText, [ref]$tokens, [ref]$parseErrors) | Out-Null
    if ($parseErrors.Count) { throw 'Syntaxe invalide dans un script embarque.' }
}

$expectedLines = @('{0} *{1}' -f (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash, [System.IO.Path]::GetFileName($exePath))
$actualLines = @(Get-Content -LiteralPath $hashManifestPath -Encoding UTF8)
if (($expectedLines -join [Environment]::NewLine) -ne ($actualLines -join [Environment]::NewLine)) {
    throw 'SHA256SUMS.txt ne correspond pas a l executable seul.'
}
if (-not (Test-Path -LiteralPath $releaseBundlePath -PathType Leaf)) { throw "Archive de livraison manquante : $releaseBundlePath" }
$releaseFiles = @($exePath, $hashManifestPath)
if (Test-Path -LiteralPath "$exePath.config" -PathType Leaf) { $releaseFiles += "$exePath.config" }
$expectedNames = @($releaseFiles | ForEach-Object { [System.IO.Path]::GetFileName($_) })
Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop
Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
$releaseBundle = [System.IO.Compression.ZipFile]::OpenRead($releaseBundlePath)
try {
    $entries = @($releaseBundle.Entries)
    if ($entries.Count -ne $expectedNames.Count) { throw 'Nombre de fichiers inattendu dans le ZIP de livraison.' }
    foreach ($file in $releaseFiles) {
        $name = [System.IO.Path]::GetFileName($file)
        $matches = @($entries | Where-Object { $_.FullName -ceq $name })
        if ($matches.Count -ne 1) { throw "Fichier absent, duplique ou mal place dans le ZIP : $name" }
        $stream = $matches[0].Open()
        try { $entryHash = (Get-FileHash -InputStream $stream -Algorithm SHA256).Hash }
        finally { $stream.Dispose() }
        if ($entryHash -ne (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash) {
            throw "Contenu incorrect dans le ZIP de livraison : $name"
        }
    }
}
finally { $releaseBundle.Dispose() }

$signature = Get-AuthenticodeSignature -LiteralPath $exePath
Write-Host ("OK clean .NET launcher, size={0}, signature={1}, no diagnostic payload, release-bundle=verified" -f $exe.Length, $signature.Status)
