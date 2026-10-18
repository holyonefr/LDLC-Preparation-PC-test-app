param([ValidateRange(0,120)][int]$VisualCheckSeconds = 0)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$config = Get-Content -LiteralPath (Join-Path $root 'telemetry.config.json') -Raw | ConvertFrom-Json
$key = 'LDLC-Dashboard-2026-288d06206918450293ed29d54fefc801'
function Read-EditionSnapshot {
    Invoke-RestMethod -Uri ($config.EndpointUrl + '?format=json&key=' + $key) -TimeoutSec 60
}
function Send-EditionTest($Body) {
    $Body.apiKey = $config.ApiKey
    $bytes = [Text.Encoding]::UTF8.GetBytes(($Body | ConvertTo-Json -Depth 14 -Compress))
    $result = Invoke-RestMethod -Uri $config.EndpointUrl -Method Post -Body $bytes -ContentType 'application/json; charset=utf-8' -TimeoutSec 60
    if (-not $result.ok) { throw 'Live Apps Script request not acknowledged.' }
    $result
}
$before = Read-EditionSnapshot
if ($before.spreadsheetId -ne '1PtMhZC_7dQi7aw278XPQ1udmV9ol5hrD_G4mdSwXWA0') { throw 'Unexpected permanent spreadsheet.' }
$prefix = 'CODEX-EDITION-TEST-' + [guid]::NewGuid().ToString('N')
$ids = @(0..4 | ForEach-Object { $prefix + '-' + $_ })
if (@($before.runs | Where-Object { $_.runId -in $ids }).Count) { throw 'Test RunId collision.' }
$backup = Join-Path ([IO.Path]::GetTempPath()) ($prefix + '.json')
$before | ConvertTo-Json -Depth 25 | Set-Content -LiteralPath $backup -Encoding UTF8
$expected = @('LDLC_PREPARATION_PC','NUMERIKS_PREPARATION_PC','NUMERIKS_PREPARATION_PC','LDLC_PREPARATION_PC','LDLC_PREPARATION_ADDON')
try {
    $starts = @()
    for ($i=0; $i -lt $ids.Count; $i++) {
        $run = @{ RunId=$ids[$i]; Source='LDLCPreparationPC'; ApplicationSource='LDLC_PREPARATION_PC'; ComputerName="CODEX-TEST-EDITION-$i"; UserName=''; ToolVersion='2.6.1'; StartedAt=[datetime]::UtcNow.ToString('o'); Status='running'; IsFinal=$false; Sequence=1 }
        if ($i -eq 1) { $run.Source='NumeriksPreparationPC'; $run.ApplicationSource='NUMERIKS_PREPARATION_PC'; $run.Edition='NUMERIKS' }
        if ($i -eq 2) { $run.ScriptPath="D:\TEST\Numerik'sPreparationPC.exe"; $run.ToolVersion='2.6.0' }
        if ($i -eq 3) { $run.Remove('ApplicationSource'); $run.ToolVersion='1.8' }
        if ($i -eq 4) { $run.Source='Preparation Addon Sport'; $run.ApplicationSource='LDLC_PREPARATION_ADDON' }
        $starts += @{ Run=$run; Events=@() }
    }
    [void](Send-EditionTest @{ payloads=$starts })
    $finals = @()
    for ($i=0; $i -lt $ids.Count; $i++) {
        $run = @{}; foreach ($name in $starts[$i].Run.Keys) { $run[$name]=$starts[$i].Run[$name] }
        $run.Status = if ($i -eq 2) { 'failed' } else { 'success' }
        $run.IsFinal=$true; $run.Sequence=2; $run.FinishedAt=[datetime]::UtcNow.ToString('o'); $run.DurationSeconds=12
        $run.ErrorCount = if ($i -eq 2) { 1 } else { 0 }
        $events = if ($i -eq 2) { @(@{ RunId=$run.RunId; Source=$run.Source; ApplicationSource=$run.ApplicationSource; ScriptPath=$run.ScriptPath; Timestamp=$run.FinishedAt; Message='TEST UNIQUEMENT - erreur Numeriks simulee'; Severity='error'; Status='error'; Type='Erreur technique' }) } else { @() }
        $finals += @{ Run=$run; Events=@($events) }
    }
    [void](Send-EditionTest @{ payloads=($finals + $finals + $starts) })
    $after = Read-EditionSnapshot
    for ($i=0; $i -lt $ids.Count; $i++) {
        $rows = @($after.runs | Where-Object runId -eq $ids[$i])
        if ($rows.Count -ne 1 -or $rows[0].applicationSource -ne $expected[$i] -or -not $rows[0].isFinal) { throw "Live classification/finalization failed: $i" }
    }
    $errors = @($after.rawErrors | Where-Object runId -eq $ids[2])
    if ($errors.Count -ne 1 -or $errors[0].applicationSource -ne 'NUMERIKS_PREPARATION_PC') { throw 'Numeriks error classification or dedupe failed.' }
    if (@($before.runs | Where-Object { $_.runId -and $_.runId -notin @($after.runs.runId) }).Count) { throw 'Historical executions lost.' }
    Write-Host "OK LIVE: LDLC/Numeriks/legacy/ADDON, empty user, success/error, repeated POST dedupe, history preserved. Backup: $backup"
    if ($VisualCheckSeconds) { Write-Host 'Synthetic rows available for visual verification, then automatic cleanup.'; Start-Sleep -Seconds $VisualCheckSeconds }
} finally {
    foreach ($id in $ids) {
        if ($id.StartsWith($prefix + '-', [StringComparison]::Ordinal)) {
            [void](Send-EditionTest @{ action='deleterun'; adminKey=$key; RunId=$id })
        }
    }
}
$clean = Read-EditionSnapshot
if (@($clean.runs | Where-Object { $_.runId -in $ids }).Count -or @($clean.rawErrors | Where-Object { $_.runId -in $ids }).Count) { throw 'Synthetic-row cleanup not confirmed.' }
Write-Host 'OK LIVE: only this test synthetic rows removed; permanent links and original history preserved.'
