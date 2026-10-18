param(
    [string]$Description = "Mise a jour dashboard permanent LDLC - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
)

$ErrorActionPreference = 'Stop'
$env:NO_UPDATE_NOTIFIER = '1'
$env:npm_config_update_notifier = 'false'
$env:npm_config_fund = 'false'
$env:npm_config_audit = 'false'

$projectId = '19Sn2qzKl3XwTV8Gxq1RLELhJcg5Uy-iXk_YglKJlggyduRai_xZL9WhP'
$deploymentId = 'AKfycbwYe2r5-y8HeyfLjslbq7wI2BdFH0sj7TLJQSiUyeRdt_z7yytyTKsPQPPcT0HUcAci3g'
$spreadsheetId = '1PtMhZC_7dQi7aw278XPQ1udmV9ol5hrD_G4mdSwXWA0'
$dashboardKey = 'LDLC-Dashboard-2026-288d06206918450293ed29d54fefc801'
$webAppUrl = "https://script.google.com/macros/s/$deploymentId/exec"
$sourcePath = Join-Path $PSScriptRoot 'google-apps-script\LDLC_ErrorTelemetry.gs'

if (-not (Test-Path -LiteralPath $sourcePath)) {
    throw "Source Apps Script introuvable : $sourcePath"
}

$claspCommand = Get-Command clasp -ErrorAction SilentlyContinue
$npxCommand = Get-Command npx -ErrorAction SilentlyContinue
$pnpmCommand = Get-Command pnpm -ErrorAction SilentlyContinue
if (-not $claspCommand -and -not $npxCommand -and -not $pnpmCommand) {
    throw 'clasp, npx ou pnpm est requis pour publier le dashboard permanent.'
}

function Invoke-LDLCClasp {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    if ($claspCommand) {
        $output = @(& $claspCommand.Source @Arguments 2>&1)
    }
    elseif ($npxCommand) {
        $output = @(& $npxCommand.Source --yes '@google/clasp' @Arguments 2>&1)
    }
    else {
        $output = @(& $pnpmCommand.Source --reporter=silent dlx '@google/clasp' @Arguments 2>&1)
    }
    $exitCode = $LASTEXITCODE
    $output | ForEach-Object { Write-Host $_ }

    if ($exitCode -ne 0) {
        $message = $output -join [Environment]::NewLine
        if ($message -match 'Apps Script API') {
            throw 'Active l API Google Apps Script sur https://script.google.com/home/usersettings puis relance le deploiement.'
        }
        throw "clasp a echoue avec le code $exitCode."
    }

    return $output
}

$tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\') + '\'
$workPath = [System.IO.Path]::GetFullPath((Join-Path $tempRoot ('LDLCAppsScriptDeploy-' + [guid]::NewGuid().ToString('N'))))
if (-not $workPath.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Dossier temporaire refuse : $workPath"
}

New-Item -ItemType Directory -Path $workPath -Force | Out-Null

try {
    Push-Location $workPath
    try {
        Invoke-LDLCClasp -Arguments @('clone', $projectId) | Out-Null
        Copy-Item -LiteralPath $sourcePath -Destination (Join-Path $workPath 'Code.js') -Force

        Invoke-LDLCClasp -Arguments @('push', '-f') | Out-Null
        $versionOutput = Invoke-LDLCClasp -Arguments @('version', $Description)
        $versionText = $versionOutput -join [Environment]::NewLine
        if ($versionText -notmatch 'Created version\s+(\d+)') {
            throw 'Numero de version Apps Script introuvable apres publication.'
        }

        $version = $Matches[1]
        Invoke-LDLCClasp -Arguments @(
            'redeploy',
            $deploymentId,
            '-V',
            $version,
            '-d',
            $Description
        ) | Out-Null

        $deployments = Invoke-LDLCClasp -Arguments @('deployments')
        $deploymentText = $deployments -join [Environment]::NewLine
        if ($deploymentText -notmatch [regex]::Escape("$deploymentId @$version")) {
            throw 'Le deploiement permanent ne pointe pas vers la nouvelle version.'
        }
    }
    finally {
        Pop-Location
    }

    $dashboardUri = $webAppUrl + '?format=json&key=' + [uri]::EscapeDataString($dashboardKey)
    $snapshot = Invoke-RestMethod -Uri $dashboardUri -Method Get -TimeoutSec 60
    if (-not $snapshot.ok -or $snapshot.spreadsheetId -ne $spreadsheetId) {
        throw 'Le dashboard publie ne pointe pas vers le Google Sheet permanent attendu.'
    }

    [pscustomobject]@{
        ProjectId = $projectId
        DeploymentId = $deploymentId
        Version = $version
        SpreadsheetId = $snapshot.spreadsheetId
        Runs = @($snapshot.runs).Count
        Errors = @($snapshot.errors).Count
        DashboardUrl = $snapshot.dashboardUrl
    }
}
finally {
    $resolvedWorkPath = [System.IO.Path]::GetFullPath($workPath)
    if ((Test-Path -LiteralPath $resolvedWorkPath) -and
        $resolvedWorkPath.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $resolvedWorkPath -Recurse -Force
    }
}
