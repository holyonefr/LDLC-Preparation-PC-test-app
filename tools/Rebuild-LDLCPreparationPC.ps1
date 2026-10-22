param(
    [ValidateSet('main', 'worker')]
    [string]$Source = 'main',

    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'PreparationDelivery.Common.ps1')
$delivery = Get-PreparationDelivery $root
$moduleDir = Join-Path $root 'modules'
$orderPath = Join-Path $moduleDir 'build-order.txt'
$telemetryConfigPath = Join-Path $root 'telemetry.config.json'

if (-not (Test-Path -LiteralPath $orderPath)) {
    throw "Build order introuvable : $orderPath"
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $dist = Join-Path $root 'dist'
    New-Item -ItemType Directory -Force -Path $dist | Out-Null
    $OutputPath = if ($Source -eq 'worker') { $delivery.WorkerScriptPath } else { $delivery.MainScriptPath }
}

$utf8Bom = New-Object System.Text.UTF8Encoding($true)
$parts = foreach ($entry in (Get-Content -LiteralPath $orderPath)) {
    if ([string]::IsNullOrWhiteSpace($entry)) { continue }
    $path = Join-Path $moduleDir $entry
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Module introuvable : $path"
    }

    [System.IO.File]::ReadAllText($path)
}

$content = ($parts -join '')

# Vendor payloads travel inside both worker and main script, so the EXE remains
# standalone. Only five audited PowerShell sources are packaged, no vendor EXE.
$vendorMarker='$script:LDLCVendorUtilityPayloads = @()'
if ($content.Contains($vendorMarker)) {
    $entries=@()
    foreach ($relative in @('motherboard/MotherboardExperiment.psm1','vendor-utility/VendorUtility.psm1','vendor-utility/VendorDiscovery.Gigabyte.ps1','vendor-utility/VendorDiscovery.Asrock.ps1','vendor-utility/VendorPackage.Gigabyte.ps1')) {
        $path=Join-Path $PSScriptRoot ('experimental/'+$relative)
        $hash=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        $base64=[Convert]::ToBase64String([IO.File]::ReadAllBytes($path))
        $entries+="    @{ Path = '$relative'; Sha256 = '$hash'; Base64 = '$base64' }"
    }
    $content=$content.Replace($vendorMarker,('$script:LDLCVendorUtilityPayloads = @(' + "`n" + ($entries -join "`n") + "`n)"))
}

if ($Source -eq 'main') {
    $backgroundPath = Join-Path $root 'assets\UI_Background.v2.png'
    $logoPath = Join-Path $root 'assets\LDLC.png'
    foreach ($assetPath in @($backgroundPath, $logoPath)) {
        if (-not (Test-Path -LiteralPath $assetPath -PathType Leaf)) {
            throw "Ressource UI introuvable : $assetPath"
        }
    }

    function ConvertTo-LDLCWrappedBase64 {
        param([Parameter(Mandatory = $true)][string]$Path)
        $base64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($Path))
        $builder = New-Object System.Text.StringBuilder
        for ($offset = 0; $offset -lt $base64.Length; $offset += 120) {
            $length = [math]::Min(120, $base64.Length - $offset)
            [void]$builder.AppendLine($base64.Substring($offset, $length))
        }
        return $builder.ToString().TrimEnd()
    }

    $backgroundHash = (Get-FileHash -LiteralPath $backgroundPath -Algorithm SHA256).Hash
    $logoHash = (Get-FileHash -LiteralPath $logoPath -Algorithm SHA256).Hash
    $backgroundBase64 = ConvertTo-LDLCWrappedBase64 -Path $backgroundPath
    $logoBase64 = ConvertTo-LDLCWrappedBase64 -Path $logoPath
    $embeddedAssetsLiteral = @"
`$script:LDLCEmbeddedUiAssetPayloads = @(
    @{
        FileNames = @('UI_Background.v2.png', 'UI_Background.png')
        Sha256 = '$backgroundHash'
        Base64 = @'
$backgroundBase64
'@
    },
    @{
        FileNames = @('LDLC.png')
        Sha256 = '$logoHash'
        Base64 = @'
$logoBase64
'@
    }
)
"@

    $payloadMarker = '$script:LDLCEmbeddedUiAssetPayloads = @()'
    if (-not $content.Contains($payloadMarker)) {
        throw 'Marqueur des ressources UI embarquees introuvable.'
    }
    $content = $content.Replace($payloadMarker, $embeddedAssetsLiteral.TrimEnd())

    $workerPath = $delivery.WorkerScriptPath
    if (-not (Test-Path -LiteralPath $workerPath -PathType Leaf)) {
        throw "Worker reconstruit introuvable : $workerPath"
    }
    $workerHash = (Get-FileHash -LiteralPath $workerPath -Algorithm SHA256).Hash
    $workerBase64 = ConvertTo-LDLCWrappedBase64 -Path $workerPath
    $embeddedWorkerLiteral = @"
`$script:LDLCEmbeddedWorkerPayload = @{
    Sha256 = '$workerHash'
    Base64 = @'
$workerBase64
'@
}
"@
    $workerMarker = '$script:LDLCEmbeddedWorkerPayload = $null'
    if (-not $content.Contains($workerMarker)) {
        throw 'Marqueur du worker embarque introuvable.'
    }
    $content = $content.Replace($workerMarker, $embeddedWorkerLiteral.TrimEnd())
}

function ConvertTo-LDLCPowerShellLiteral {
    param([string]$Value)
    return "'" + ($Value -replace "'", "''") + "'"
}

if (Test-Path -LiteralPath $telemetryConfigPath) {
    $telemetryConfig = Get-Content -LiteralPath $telemetryConfigPath -Raw | ConvertFrom-Json

    if (-not [string]::IsNullOrWhiteSpace($telemetryConfig.EndpointUrl)) {
        $content = $content -replace "(?m)^\`$script:LDLCTelemetryEndpointUrl\s*=.*$", ('$script:LDLCTelemetryEndpointUrl = ' + (ConvertTo-LDLCPowerShellLiteral $telemetryConfig.EndpointUrl))
    }

    if (-not [string]::IsNullOrWhiteSpace($telemetryConfig.ApiKey)) {
        $content = $content -replace "(?m)^\`$script:LDLCTelemetryApiKey\s*=.*$", ('$script:LDLCTelemetryApiKey = ' + (ConvertTo-LDLCPowerShellLiteral $telemetryConfig.ApiKey))
    }

    if (-not [string]::IsNullOrWhiteSpace($telemetryConfig.ToolVersion)) {
        $content = $content -replace "(?m)^\`$script:LDLCTelemetryToolVersion\s*=.*$", ('$script:LDLCTelemetryToolVersion = ' + (ConvertTo-LDLCPowerShellLiteral $telemetryConfig.ToolVersion))
    }

    if ($null -ne $telemetryConfig.SendSuccessfulRuns) {
        $content = $content -replace "(?m)^\`$script:LDLCTelemetrySendSuccessfulRuns\s*=.*$", ('$script:LDLCTelemetrySendSuccessfulRuns = $' + ([bool]$telemetryConfig.SendSuccessfulRuns).ToString().ToLowerInvariant())
    }
}

$coreVersionPath = Join-Path $root 'sync\core-version.json'
$telemetryIdentity = @{
    LDLCTelemetrySource = if ($delivery.Edition -eq 'NUMERIKS') { 'NumeriksPreparationPC' } else { 'LDLCPreparationPC' }
    LDLCTelemetryApplicationSource = if ($delivery.Edition -eq 'NUMERIKS') { 'NUMERIKS_PREPARATION_PC' } else { 'LDLC_PREPARATION_PC' }
    LDLCTelemetryEdition = $delivery.Edition
}
foreach ($name in $telemetryIdentity.Keys) {
    $content = $content -replace ('(?m)^\$script:' + $name + '\s*=.*$'),
        ('$script:' + $name + ' = ' + (ConvertTo-LDLCPowerShellLiteral $telemetryIdentity[$name]))
}
if (Test-Path -LiteralPath $coreVersionPath) {
    $coreVersion = (Get-Content -LiteralPath $coreVersionPath -Raw | ConvertFrom-Json).ToolVersion
    if ($coreVersion -notmatch '^\d+\.\d+\.\d+$') { throw 'Version du coeur partage invalide.' }
    $content = $content -replace "(?m)^\`$script:LDLCTelemetryToolVersion\s*=.*$", ('$script:LDLCTelemetryToolVersion = ' + (ConvertTo-LDLCPowerShellLiteral $coreVersion))
}
$content = $content -replace "`r?`n", "`r`n"
[System.IO.File]::WriteAllText($OutputPath, $content, $utf8Bom)

Write-Host "Script reconstruit : $OutputPath"
