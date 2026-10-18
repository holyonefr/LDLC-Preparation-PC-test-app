$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'PreparationDelivery.Common.ps1')
$bootstrapPath = Join-Path $root 'modules\00.Bootstrap.ps1'
$buildPath = Join-Path $root 'tools\Build-LDLCPreparationPCExe.ps1'
$distPath = (Get-PreparationDelivery $root).MainScriptPath
$testRoot = Join-Path $env:LOCALAPPDATA ('LDLCPreparationPC\AssetTest-' + [guid]::NewGuid().ToString('N'))

. $bootstrapPath -Preview
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

try {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes('LDLC-UI-ASSET-TEST')
    $hash = Get-LDLCByteArraySha256 -Bytes $bytes
    $script:LDLCEmbeddedUiAssetPayloads = @(
        @{
            FileNames = @('UI_Background.v2.png', 'UI_Background.png')
            Sha256 = $hash
            Base64 = [Convert]::ToBase64String($bytes)
        }
    )

    if (-not (Install-LDLCEmbeddedUiAssets -RuntimeRoot $testRoot)) {
        throw 'Creation initiale des ressources UI en echec.'
    }

    $primaryPath = Join-Path $testRoot 'UI_Background.v2.png'
    $legacyPath = Join-Path $testRoot 'UI_Background.png'
    foreach ($path in @($primaryPath, $legacyPath)) {
        if (-not (Test-LDLCFileHash -Path $path -ExpectedSha256 $hash)) {
            throw "Ressource UI absente ou incorrecte : $path"
        }
    }

    $correctLock = [System.IO.File]::Open($primaryPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    try {
        if (-not (Install-LDLCEmbeddedUiAssets -RuntimeRoot $testRoot)) {
            throw 'Une ressource correcte et verrouillee doit etre reutilisee sans reecriture.'
        }
    }
    finally {
        $correctLock.Dispose()
    }

    [System.IO.File]::WriteAllText($primaryPath, 'ANCIENNE-IMAGE')
    if (-not (Install-LDLCEmbeddedUiAssets -RuntimeRoot $testRoot) -or
        -not (Test-LDLCFileHash -Path $primaryPath -ExpectedSha256 $hash)) {
        throw 'Une ressource obsolete non verrouillee doit etre remplacee atomiquement.'
    }

    [System.IO.File]::WriteAllText($primaryPath, 'ANCIENNE-IMAGE-VERROUILLEE')
    $staleLock = [System.IO.File]::Open($primaryPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    $blockedAsExpected = $false
    try {
        try {
            [void](Install-LDLCEmbeddedUiAssets -RuntimeRoot $testRoot)
        }
        catch {
            $blockedAsExpected = $true
        }
    }
    finally {
        $staleLock.Dispose()
    }
    if (-not $blockedAsExpected) {
        throw 'Une ressource obsolete verrouillee doit produire une erreur geree.'
    }
    if (@(Get-ChildItem -LiteralPath $testRoot -Filter '*.new' -Force -ErrorAction SilentlyContinue).Count -ne 0) {
        throw 'Un echec de remplacement ne doit pas laisser de fichier temporaire.'
    }
    [void](Install-LDLCEmbeddedUiAssets -RuntimeRoot $testRoot)

    $dist = Get-Content -LiteralPath $distPath -Raw -Encoding UTF8
    $build = Get-Content -LiteralPath $buildPath -Raw -Encoding UTF8
    foreach ($expectedHash in @(
        '7D4B9F2B91E9A4FB44D36009936D850644A6358CD3D78D05A020920EEBFE408D',
        'C2DBCEBE858AE488117CF678543A8D7ED866776EF6B19F249F0C4280EBCFA525'
    )) {
        if ($dist -notmatch $expectedHash) {
            throw "Empreinte UI absente du script compile : $expectedHash"
        }
    }
    if ($dist -match [regex]::Escape('$script:LDLCEmbeddedUiAssetPayloads = @()')) {
        throw 'Le script principal compile contient encore le marqueur vide des ressources UI.'
    }
    if ($build -match '-EmbedFiles') {
        throw 'ps2exe ne doit plus extraire les images automatiquement.'
    }
}
finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'OK atomic embedded UI assets'
