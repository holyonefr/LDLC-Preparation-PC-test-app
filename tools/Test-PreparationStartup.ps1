$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'PreparationDelivery.Common.ps1')
$launcher = Get-Content -LiteralPath (Join-Path $root 'tools\LDLCPreparationPC.Launcher\Program.cs') -Raw
if ($launcher.IndexOf('beforeStart.Invoke') -lt 0 -or $launcher.IndexOf('beforeStart.Invoke') -gt $launcher.IndexOf('string script = ReadEmbeddedScript')) {
    throw 'L accueil doit preceder le chargement du script et toute execution PowerShell.'
}
$edition = Get-Content -LiteralPath (Join-Path $root 'sync\edition.json') -Raw | ConvertFrom-Json
$assembly = [Reflection.Assembly]::LoadFile((Get-PreparationDelivery $root).ExecutablePath)
$startup = $assembly.GetType('PreparationEdition.Startup', $false)
if ($edition.Edition -eq 'NUMERIKS') {
    if (-not $startup) { throw 'Accueil Numeriks absent de l executable.' }
    $logoPath = Join-Path $root 'branding\startup\logo.jpg'
    $stream = $assembly.GetManifestResourceStream('PreparationEdition.StoreLogo')
    if (-not $stream) { throw 'Logo original absent.' }
    try { $embeddedHash = (Get-FileHash -InputStream $stream -Algorithm SHA256).Hash }
    finally { $stream.Dispose() }
    if ($embeddedHash -ne (Get-FileHash -LiteralPath $logoPath -Algorithm SHA256).Hash) { throw 'Logo altere au packaging.' }
    $editionTests = Join-Path $root 'branding\startup\tests\Test-StoreStartup.ps1'
    if (-not (Test-Path -LiteralPath $editionTests)) { throw 'Tests de lancement Numeriks manquants.' }
    & $editionTests
} elseif ($startup) { throw 'L edition LDLC ne doit pas afficher l accueil Numeriks.' }
Write-Host "OK edition startup: $($edition.Edition), gate before PowerShell, local branding only."
