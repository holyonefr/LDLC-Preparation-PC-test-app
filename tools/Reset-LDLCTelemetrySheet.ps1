param(
    [string]$ConfigPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'telemetry.config.json'),
    [string]$AppsScriptPath = (Join-Path $PSScriptRoot 'google-apps-script\LDLC_ErrorTelemetry.gs')
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "Configuration introuvable : $ConfigPath"
}

if (-not (Test-Path -LiteralPath $AppsScriptPath)) {
    throw "Source Apps Script introuvable : $AppsScriptPath"
}

$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$endpointUrl = [string]$config.EndpointUrl
$apiKey = [string]$config.ApiKey

if ([string]::IsNullOrWhiteSpace($endpointUrl) -or [string]::IsNullOrWhiteSpace($apiKey)) {
    throw 'EndpointUrl ou ApiKey manquant dans telemetry.config.json.'
}

$appsScriptSource = Get-Content -LiteralPath $AppsScriptPath -Raw
if ($appsScriptSource -notmatch "DASHBOARD_PASSWORD:\s*'([^']+)'") {
    throw 'DASHBOARD_PASSWORD introuvable dans la source Apps Script.'
}
$dashboardKey = $Matches[1]

$resetBody = @{
    apiKey = $apiKey
    adminKey = $dashboardKey
    action = 'resetTelemetry'
    confirm = 'RESET_LDLC_TELEMETRY'
} | ConvertTo-Json -Depth 5

$resetResponse = Invoke-RestMethod -Method Post -Uri $endpointUrl -ContentType 'application/json' -Body $resetBody -TimeoutSec 60
if (-not $resetResponse.ok) {
    throw "Reset refuse par la Web App live : $($resetResponse.error)"
}

if ($resetResponse.action -ne 'resetTelemetry') {
    throw "La Web App live ne contient pas encore l'action resetTelemetry. Publie d'abord tools\google-apps-script\LDLC_ErrorTelemetry.gs sur le deploiement permanent."
}

$dashboardUri = $endpointUrl + '?format=json&key=' + [uri]::EscapeDataString($dashboardKey)
$snapshot = Invoke-RestMethod -Uri $dashboardUri -Method Get -TimeoutSec 60
$runsCount = @($snapshot.runs).Count
$errorsCount = @($snapshot.errors).Count

if ($runsCount -ne 0 -or $errorsCount -ne 0) {
    throw "Reset incomplet : $runsCount execution(s), $errorsCount erreur(s) encore visibles dans le dashboard."
}

[pscustomobject]@{
    Ok = $true
    DeletedRuns = $resetResponse.deletedRuns
    DeletedErrors = $resetResponse.deletedErrors
    Runs = $runsCount
    Errors = $errorsCount
    SpreadsheetUrl = $resetResponse.spreadsheetUrl
}
