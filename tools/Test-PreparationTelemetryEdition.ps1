$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'PreparationDelivery.Common.ps1')
$delivery = Get-PreparationDelivery $root
$expectedSource = if ($delivery.Edition -eq 'NUMERIKS') { 'NumeriksPreparationPC' } else { 'LDLCPreparationPC' }
$expectedApplication = if ($delivery.Edition -eq 'NUMERIKS') { 'NUMERIKS_PREPARATION_PC' } else { 'LDLC_PREPARATION_PC' }
function Assert-Edition([bool]$Value, [string]$Message) { if (-not $Value) { throw $Message } }
foreach ($path in @($delivery.MainScriptPath, $delivery.WorkerScriptPath)) {
    $text = [IO.File]::ReadAllText($path)
    foreach ($entry in @{ LDLCTelemetrySource=$expectedSource; LDLCTelemetryApplicationSource=$expectedApplication; LDLCTelemetryEdition=$delivery.Edition }.GetEnumerator()) {
        $pattern = '(?m)^\$script:' + $entry.Key + ' = ''([^'']*)'''
        Assert-Edition ([regex]::Match($text, $pattern).Groups[1].Value -ceq $entry.Value) "Embedded identity mismatch: $path / $($entry.Key)"
    }
}
. (Join-Path $root 'modules/00.Core.ps1')
. (Join-Path $root 'modules/05.Telemetry.ps1')
$script:LDLCTelemetrySource = $expectedSource
$script:LDLCTelemetryApplicationSource = $expectedApplication
$script:LDLCTelemetryEdition = $delivery.Edition
function Get-LDLCComputerTelemetryInfo {
    [pscustomobject]@{ ComputerName='TEST-EDITION'; UserName=''; UserDomain=''; SerialNumber='TEST'; Manufacturer=''; Model=''; OSCaption=''; OSVersion=''; TimeZone='' }
}
function Get-LDLCEntryPointPath { $delivery.ExecutablePath }
function Get-LDLCRuntimeRoot { $fixture }
function Send-LDLCTelemetryPayloads {
    param([object[]]$Payloads)
    foreach ($payload in $Payloads) { [void]$script:Captured.Add(($payload | ConvertTo-Json -Depth 14 | ConvertFrom-Json)) }
}
$savedDisabled = $env:LDLC_TELEMETRY_DISABLED
$savedRunId = $env:LDLC_TELEMETRY_RUN_ID
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('Preparation-Edition-Test-' + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $fixture | Out-Null
    Remove-Item Env:LDLC_TELEMETRY_DISABLED, Env:LDLC_TELEMETRY_RUN_ID -ErrorAction SilentlyContinue
    $script:Captured = New-Object 'System.Collections.Generic.List[object]'
    foreach ($status in @('success','error')) {
        $script:LDLCTelemetryInitialized = $false
        Initialize-LDLCTelemetry
        if ($status -eq 'error') { Add-LDLCTelemetryEvent -Message 'Erreur technique TEST EDITION' -Severity error }
        Complete-LDLCTelemetryRun -ResultStatus $status
        $payload = $script:Captured[$script:Captured.Count - 1]
        $expectedStatus = if ($status -eq 'error') { 'failed' } else { $status }
        Assert-Edition ($payload.Run.Edition -ceq $delivery.Edition -and $payload.Run.ApplicationSource -ceq $expectedApplication -and $payload.Run.Source -ceq $expectedSource) 'Run identity lost.'
        Assert-Edition ($payload.Run.UserName -eq '' -and $payload.Run.IsFinal -and $payload.Run.Status -eq $expectedStatus) "Empty user or final status regression: user='$($payload.Run.UserName)', final=$($payload.Run.IsFinal), actual=$($payload.Run.Status), expected=$expectedStatus."
        if ($status -eq 'error') {
            Assert-Edition (@($payload.Events).Count -eq 1 -and $payload.Events[0].Edition -ceq $delivery.Edition -and $payload.Events[0].ApplicationSource -ceq $expectedApplication) 'Error event identity lost.'
        }
    }
    Write-Host "OK telemetry edition $($delivery.Edition): embedded main/worker identity, start/final, success/error, empty user; no network."
} finally {
    $env:LDLC_TELEMETRY_DISABLED = $savedDisabled
    $env:LDLC_TELEMETRY_RUN_ID = $savedRunId
    $resolved = [IO.Path]::GetFullPath($fixture)
    if ($resolved.StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'Preparation-Edition-Test-*') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
