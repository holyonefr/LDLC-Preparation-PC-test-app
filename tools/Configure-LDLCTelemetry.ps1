param(
    [Parameter(Mandatory = $true)]
    [string]$EndpointUrl,

    [Parameter(Mandatory = $true)]
    [string]$ApiKey,

    [string]$ToolVersion = '2.5.2',

    [switch]$DisableSuccessfulRunTelemetry,

    [switch]$Rebuild
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$telemetryConfigPath = Join-Path $root 'telemetry.config.json'
$modulePaths = @((Join-Path $root 'modules\05.Telemetry.ps1'))

function ConvertTo-LDLCPowerShellLiteral {
    param([string]$Value)
    return "'" + ($Value -replace "'", "''") + "'"
}

foreach ($path in $modulePaths) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Module introuvable : $path"
    }

    $content = Get-Content -LiteralPath $path -Raw
    $content = $content -replace "(?m)^\`$script:LDLCTelemetryEndpointUrl\s*=.*$", ('$script:LDLCTelemetryEndpointUrl = ' + (ConvertTo-LDLCPowerShellLiteral $EndpointUrl))
    $content = $content -replace "(?m)^\`$script:LDLCTelemetryApiKey\s*=.*$", ('$script:LDLCTelemetryApiKey = ' + (ConvertTo-LDLCPowerShellLiteral $ApiKey))
    $content = $content -replace "(?m)^\`$script:LDLCTelemetryToolVersion\s*=.*$", ('$script:LDLCTelemetryToolVersion = ' + (ConvertTo-LDLCPowerShellLiteral $ToolVersion))
    $content = $content -replace "(?m)^\`$script:LDLCTelemetrySendSuccessfulRuns\s*=.*$", ('$script:LDLCTelemetrySendSuccessfulRuns = $' + (-not $DisableSuccessfulRunTelemetry).ToString().ToLowerInvariant())
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8
    Write-Host "Telemetrie configuree : $path"
}

$telemetryConfig = [ordered]@{
    EndpointUrl        = $EndpointUrl
    ApiKey             = $ApiKey
    ToolVersion        = $ToolVersion
    SendSuccessfulRuns = (-not $DisableSuccessfulRunTelemetry)
}

($telemetryConfig | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $telemetryConfigPath -Encoding UTF8 -Force
Write-Host "Configuration persistante : $telemetryConfigPath"

if ($Rebuild) {
    & (Join-Path $PSScriptRoot 'Rebuild-LDLCPreparationPC.ps1')
    & (Join-Path $PSScriptRoot 'Rebuild-LDLCPreparationPC.ps1') -Source worker
}
