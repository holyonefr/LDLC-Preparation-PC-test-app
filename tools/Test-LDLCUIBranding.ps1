$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$uiPath = Join-Path $root 'modules\99.UI.ps1'
$v2AssetPath = Join-Path $root 'assets\UI_Background.v2.png'
$content = Get-Content -LiteralPath $uiPath -Raw -Encoding UTF8
$removedTagline = "Informatique de Qualit$([char]0x00e9)"

if ($content -match [regex]::Escape($removedTagline)) {
    throw "Le slogan UI `"$removedTagline`" ne doit plus etre affiche par le code."
}

foreach ($badText in @("Informatique de Bualit$([char]0x00e9)", "Informatique de oualit$([char]0x00e9)")) {
    if ($content -match [regex]::Escape($badText)) {
        throw "Variante incorrecte trouvee dans la source UI : $badText"
    }
}

if ($content -match '\$script:LDLCBrandTagline') {
    throw 'La variable LDLCBrandTagline ne doit plus etre utilisee.'
}

if ($content -notmatch [regex]::Escape("'Version 1.0'")) {
    throw 'La mention UI "Version 1.0" est introuvable.'
}

if (-not (Test-Path -LiteralPath $v2AssetPath)) {
    throw 'Le fond UI versionne assets\UI_Background.v2.png est introuvable.'
}

if ($content -notmatch 'UI_Background\.v2\.png') {
    throw 'La resolution du fond UI doit prioriser UI_Background.v2.png.'
}

if ($content -notmatch 'function Draw-LDLCVersionOverlay') {
    throw 'Le rendu de la version UI doit rester centralise dans Draw-LDLCVersionOverlay.'
}

foreach ($removedMask in @('topCover', 'heroCover', 'coverBrush')) {
    if ($content -match $removedMask) {
        throw "Le masque noir $removedMask ne doit plus etre present avec le nouveau fond UI."
    }
}

if ($content -notmatch 'Draw-LDLCVersionOverlay -Graphics \$graphics') {
    throw 'Le rendu de la version doit etre appele pendant le rendu UI.'
}

if ($content -notmatch 'Remove-LDLCBitmapAlphaFringe -Bitmap \$bg -AlphaCutoff 254' -or $content -notmatch 'New-LDLCBitmapAlphaRegion -Bitmap \$bg -AlphaThreshold 254') {
    throw 'Le bord transparent UI doit etre nettoye avant de creer la region de fenetre.'
}

if ($content -notmatch 'Apply-LDLCBitmapRoundedWindowMask' -or $content -notmatch 'Convert-X 72') {
    throw 'Les coins noirs opaques du fond UI doivent etre decoupes par masque arrondi.'
}

if ($content -notmatch 'Draw-LDLCTextWithShadow' -or $content -notmatch 'Convert-FontSize 27') {
    throw 'Les textes UI doivent rester renforces et lisibles.'
}

if ($content -notmatch '\$form\.AutoScaleMode = \[System\.Windows\.Forms\.AutoScaleMode\]::None' -or $content -notmatch '\$form\.ClientSize') {
    throw 'La fenetre UI doit garder une taille client stable sans bord parasite.'
}

Write-Host 'OK UI branding'
