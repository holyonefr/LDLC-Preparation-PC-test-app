$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$telemetryPath = Join-Path $root 'modules\05.Telemetry.ps1'
$appsPath = Join-Path $root 'modules\30.Applications.ps1'
$windowsUpdatePath = Join-Path $root 'modules\80.WindowsUpdate.ps1'
$appsScriptPath = Join-Path $root 'tools\google-apps-script\LDLC_ErrorTelemetry.gs'

$telemetry = Get-Content -LiteralPath $telemetryPath -Raw -Encoding UTF8
$apps = Get-Content -LiteralPath $appsPath -Raw -Encoding UTF8
$windowsUpdate = Get-Content -LiteralPath $windowsUpdatePath -Raw -Encoding UTF8
$appsScript = Get-Content -LiteralPath $appsScriptPath -Raw -Encoding UTF8

if ($telemetry -notmatch [regex]::Escape('$script:LDLCTelemetryEventKeys')) {
    throw 'La telemetrie doit dedupliquer les evenements identiques dans une execution.'
}

if ($apps -notmatch 'function Get-LDLCWingetCommandPath') {
    throw 'La detection winget robuste est introuvable.'
}

if ($apps -notmatch [regex]::Escape('Microsoft\WindowsApps') -or $apps -notmatch [regex]::Escape('Microsoft.DesktopAppInstaller')) {
    throw 'La detection winget doit couvrir WindowsApps et DesktopAppInstaller.'
}

if ($apps -notmatch 'function Get-LDLCAppInstallationState' -or
    $apps -notmatch 'IsInstalled\s*=\s*\[bool\]\(\$hasExecutable' -or
    $apps -match 'Test-AppReallyInstalled -App \$App -Refresh -or \(Test-AppInstalledInRegistry') {
    throw 'La validation installation doit exiger un executable et controler registre/version.'
}

if ($windowsUpdate -notmatch '0x80070103') {
    throw 'Windows Update doit ignorer les echecs pilotes 0x80070103 non bloquants.'
}

if ($windowsUpdate -match 'Windows Update lance en arriere-plan.*-Severity warning') {
    throw 'Windows Update lance avec succes en arriere-plan ne doit pas etre remonte comme warning.'
}

if ($telemetry -notmatch "return 'success'" -or $telemetry -notmatch 'WarningCount -gt 0' -or $telemetry -notmatch 'ErrorCount -gt 0') {
    throw 'Le statut final doit etre normalise et ne doit pas dependre des evenements informatifs.'
}

if ($telemetry -notmatch 'Seules les erreurs explicites error/critical comptent' -or $telemetry.Contains('return ($Message -match')) {
    throw 'La telemetrie ne doit plus envoyer les avertissements comme alertes dashboard.'
}

if ($telemetry -notmatch 'Reportable\s*=\s*\[bool\]\$isReportableError' -or
    $telemetry -notmatch 'reportableEvents\s*=\s*@\(\$events \| Where-Object \{ \$_.Severity -in @\(''error'', ''critical''\) \}\)') {
    throw 'Les avertissements doivent influencer le statut sans etre envoyes comme erreurs detaillees.'
}

if ($appsScript -notmatch 'const isRealError' -or $appsScript -notmatch 'hasFields_\(event\) && isRealError') {
    throw 'Apps Script doit ignorer les avertissements recus dans la feuille des erreurs.'
}

if ($appsScript -notmatch 'appendRowsUniqueByKey_\(errorSheet') {
    throw 'Apps Script doit eviter de reinserer les memes erreurs du meme RunId.'
}

if ($appsScript -notmatch 'function appendRowsUniqueByKey_') {
    throw 'La fonction appendRowsUniqueByKey_ est introuvable.'
}

if ($appsScript -notmatch 'function clearSheetDataValidations_') {
    throw 'Apps Script doit centraliser la suppression des anciennes validations de donnees.'
}

if ($appsScript -notmatch [regex]::Escape('getRange(1, 1, rows, columns).clearDataValidations()')) {
    throw 'Apps Script doit supprimer les validations via une plage complete de la feuille.'
}

if ($appsScript -match [regex]::Escape('sheet.clearDataValidations()')) {
    throw 'Apps Script ne doit pas appeler clearDataValidations directement sur l objet Sheet.'
}

Write-Host 'OK error report fixes'
