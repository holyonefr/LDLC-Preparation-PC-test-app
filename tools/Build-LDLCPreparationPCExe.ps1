param(
    [string]$OutputPath,
    [string]$Version = '2.6.0.0',
    [string]$ReleaseBundlePath,
    [string]$SigningThumbprint,
    [switch]$RequireSignature
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'PreparationDelivery.Common.ps1')
$delivery = Get-PreparationDelivery $root
$coreVersionPath = Join-Path $root 'sync\core-version.json'
if (-not $PSBoundParameters.ContainsKey('Version') -and (Test-Path -LiteralPath $coreVersionPath)) {
    $coreVersion = (Get-Content -LiteralPath $coreVersionPath -Raw | ConvertFrom-Json).ToolVersion
    if ($coreVersion -notmatch '^\d+\.\d+\.\d+$') { throw 'Version du coeur partage invalide.' }
    $Version = $coreVersion + '.0'
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = $delivery.ExecutablePath
}

$outputFullPath = [System.IO.Path]::GetFullPath($OutputPath)
$outputDirectory = Split-Path -Parent $outputFullPath
if ([string]::IsNullOrWhiteSpace($ReleaseBundlePath)) {
    $ReleaseBundlePath = Join-Path $outputDirectory ("{0}-{1}.zip" -f $delivery.BaseName, $Version)
}
$releaseBundleFullPath = [System.IO.Path]::GetFullPath($ReleaseBundlePath)
$mainScript = $delivery.MainScriptPath
$iconPath = Join-Path $root 'logo-ldlc-com.ico'
$launcherSource = Join-Path $PSScriptRoot 'LDLCPreparationPC.Launcher\Program.cs'
$launcherManifest = Join-Path $PSScriptRoot 'LDLCPreparationPC.Launcher\app.manifest'
$editionStartupRoot = Join-Path $root 'branding\startup'
$editionSources = @()
$expectedResources = @('LDLCPreparationPC.ps1')
if (Test-Path -LiteralPath $editionStartupRoot -PathType Container) {
    $editionSources = @(Get-ChildItem -LiteralPath $editionStartupRoot -Filter '*.cs' -File | Sort-Object Name)
}
$editionLogo = Join-Path $editionStartupRoot 'logo.jpg'
if ($editionSources.Count) {
    if (-not (Test-Path -LiteralPath $editionLogo -PathType Leaf)) { throw 'Logo original de l accueil introuvable.' }
    $expectedResources += 'PreparationEdition.StoreLogo'
}
$edition = Get-Content -LiteralPath (Join-Path $root 'sync\edition.json') -Raw | ConvertFrom-Json
if ($edition.Edition -eq 'NUMERIKS' -and -not $editionSources.Count) {
    throw 'Accueil Numeriks obligatoire : sources locales manquantes.'
}

& (Join-Path $PSScriptRoot 'Rebuild-LDLCPreparationPC.ps1') -Source worker
& (Join-Path $PSScriptRoot 'Rebuild-LDLCPreparationPC.ps1') -Source main

foreach ($path in @($mainScript, $iconPath, $launcherSource, $launcherManifest)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Fichier requis introuvable : $path"
    }
}

$csc = @(
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
if (-not $csc) {
    throw 'Compilateur C# .NET Framework introuvable.'
}

$automationAssembly = [System.Management.Automation.PSObject].Assembly.Location
if (-not (Test-Path -LiteralPath $automationAssembly -PathType Leaf)) {
    throw 'System.Management.Automation.dll introuvable.'
}

New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

$versionSource = Join-Path $outputDirectory '.LDLCPreparationPC.Version.cs'
$stagedOutput = Join-Path $outputDirectory '.LDLCPreparationPC.new.exe'
$versionCode = @"
using System.Reflection;
[assembly: AssemblyVersion("$Version")]
[assembly: AssemblyFileVersion("$Version")]
"@
[System.IO.File]::WriteAllText($versionSource, $versionCode, (New-Object System.Text.UTF8Encoding($false)))

try {
    Remove-Item -LiteralPath $stagedOutput -Force -ErrorAction SilentlyContinue
    $compilerArguments = @(
        '/nologo',
        '/target:winexe',
        '/platform:anycpu',
        '/optimize+',
        "/out:$stagedOutput",
        "/win32icon:$iconPath",
        "/win32manifest:$launcherManifest",
        "/resource:$mainScript,LDLCPreparationPC.ps1",
        "/reference:$automationAssembly",
        '/reference:System.dll',
        '/reference:System.Core.dll',
        '/reference:System.Drawing.dll',
        '/reference:System.Windows.Forms.dll',
        $launcherSource,
        $versionSource
    )
    if ($editionSources.Count) {
        $compilerArguments += "/resource:$editionLogo,PreparationEdition.StoreLogo"
        $compilerArguments += @($editionSources.FullName)
    }

    & $csc @compilerArguments
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $stagedOutput -PathType Leaf)) {
        throw "Compilation du lanceur .NET en echec (code $LASTEXITCODE)."
    }

    if ((Get-Item -LiteralPath $stagedOutput).Length -gt 12582912) {
        throw 'Le binaire principal depasse 12 Mio. Un executable a probablement ete embarque par erreur.'
    }

    try {
        Move-Item -LiteralPath $stagedOutput -Destination $outputFullPath -Force -ErrorAction Stop
    }
    catch {
        throw "Remplacement de l executable impossible. Fermer $([IO.Path]::GetFileName($outputFullPath)) puis relancer le build. Detail : $($_.Exception.Message)"
    }
}
finally {
    Remove-Item -LiteralPath $versionSource, $stagedOutput -Force -ErrorAction SilentlyContinue
}

if (-not [string]::IsNullOrWhiteSpace($SigningThumbprint)) {
    $certificate = Get-ChildItem Cert:\CurrentUser\My, Cert:\LocalMachine\My -ErrorAction SilentlyContinue |
        Where-Object { $_.Thumbprint -eq $SigningThumbprint -and $_.HasPrivateKey } |
        Select-Object -First 1
    if (-not $certificate) {
        throw "Certificat de signature introuvable : $SigningThumbprint"
    }

    $signed = Set-AuthenticodeSignature `
        -LiteralPath $outputFullPath `
        -Certificate $certificate `
        -TimestampServer 'http://timestamp.digicert.com' `
        -HashAlgorithm SHA256
    if ($signed.Status -ne 'Valid') {
        throw "Signature Authenticode en echec : $($signed.StatusMessage)"
    }
}

$signature = Get-AuthenticodeSignature -LiteralPath $outputFullPath
if ($RequireSignature -and $signature.Status -ne 'Valid') {
    throw 'Build refuse : aucun certificat de signature de code approuve n a ete applique.'
}

$manifestPath = Join-Path $outputDirectory 'SHA256SUMS.txt'
$manifestLines = @(foreach ($path in @($outputFullPath)) {
    '{0} *{1}' -f (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash, [System.IO.Path]::GetFileName($path)
})
[System.IO.File]::WriteAllLines($manifestPath, $manifestLines, (New-Object System.Text.UTF8Encoding($false)))

$releaseStagingRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('LDLCPreparationPC-Release-' + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $releaseStagingRoot -Force | Out-Null
    $releaseFiles = @($outputFullPath, $manifestPath)
    $exeConfigPath = "$outputFullPath.config"
    if (Test-Path -LiteralPath $exeConfigPath -PathType Leaf) {
        $releaseFiles += $exeConfigPath
    }

    foreach ($releaseFile in $releaseFiles) {
        Copy-Item -LiteralPath $releaseFile -Destination (Join-Path $releaseStagingRoot ([System.IO.Path]::GetFileName($releaseFile))) -Force
    }

    $releaseDirectory = Split-Path -Parent $releaseBundleFullPath
    if (-not (Test-Path -LiteralPath $releaseDirectory)) {
        New-Item -ItemType Directory -Path $releaseDirectory -Force | Out-Null
    }

    Remove-Item -LiteralPath $releaseBundleFullPath -Force -ErrorAction SilentlyContinue
    Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
    [System.IO.Compression.ZipFile]::CreateFromDirectory(
        $releaseStagingRoot,
        $releaseBundleFullPath,
        [System.IO.Compression.CompressionLevel]::Optimal,
        $false
    )
}
finally {
    Remove-Item -LiteralPath $releaseStagingRoot -Recurse -Force -ErrorAction SilentlyContinue
}

if (-not (Test-Path -LiteralPath $releaseBundleFullPath -PathType Leaf)) {
    throw "Archive de livraison introuvable apres build : $releaseBundleFullPath"
}

$assembly = [System.Reflection.Assembly]::LoadFile($outputFullPath)
$resources = @($assembly.GetManifestResourceNames())
if (@(Compare-Object $expectedResources $resources).Count) {
    throw 'Ressources du lanceur invalides.'
}

[pscustomobject]@{
    Executable = $outputFullPath
    Version = $Version
    Size = (Get-Item -LiteralPath $outputFullPath).Length
    Sha256 = (Get-FileHash -LiteralPath $outputFullPath -Algorithm SHA256).Hash
    Signature = [string]$signature.Status
    Launcher = '.NET Framework / System.Management.Automation'
    Resources = $resources
    HashManifest = $manifestPath
    ReleaseBundle = $releaseBundleFullPath
}
