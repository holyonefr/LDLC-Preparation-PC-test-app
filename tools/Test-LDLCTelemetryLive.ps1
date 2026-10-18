param([switch]$DeduplicateExisting)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$config = Get-Content -LiteralPath (Join-Path $root 'telemetry.config.json') -Raw | ConvertFrom-Json
$source = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'google-apps-script\LDLC_ErrorTelemetry.gs') -Raw
$dashboardKey = [regex]::Match($source, "DASHBOARD_PASSWORD:\s*'([^']+)'").Groups[1].Value
$expectedBook = '1PtMhZC_7dQi7aw278XPQ1udmV9ol5hrD_G4mdSwXWA0'
$snapshotUrl = $config.EndpointUrl + '?format=json&key=' + [uri]::EscapeDataString($dashboardKey)
function Send-TestPost($Body) {
    $Body.apiKey = $config.ApiKey
    $json = $Body | ConvertTo-Json -Depth 14 -Compress
    $result = Invoke-RestMethod -Uri $config.EndpointUrl -Method Post -ContentType 'application/json; charset=utf-8' -Body $json -TimeoutSec 60
    if (-not $result -or $result.ok -ne $true) { throw 'POST live non acquitte par Apps Script.' }
    return $result
}
function Get-TestSnapshot {
    $data = Invoke-RestMethod -Uri $snapshotUrl -TimeoutSec 60
    if (-not $data.ok -or $data.spreadsheetId -ne $expectedBook) { throw 'Le dashboard ne pointe pas vers le Sheet permanent.' }
    return $data
}
function Get-TestAudit {
    $audit = Send-TestPost @{ action = 'auditruns'; adminKey = $dashboardKey; includeRows = $true }
    if ($audit.spreadsheetId -ne $expectedBook -or $audit.sheetId -ne 1844459424) { throw 'Audit sur un onglet inattendu.' }
    return $audit
}
$before = Get-TestSnapshot
$audit = Get-TestAudit
$backupPath = Join-Path ([IO.Path]::GetTempPath()) ('LDLC-live-audit-' + [guid]::NewGuid().ToString('N') + '.json')
$audit | ConvertTo-Json -Depth 18 | Set-Content -LiteralPath $backupPath -Encoding UTF8
Write-Host "Audit: $($audit.rowsBefore) lignes, $(@($audit.duplicateGroups).Count) groupes de vrais doublons RunId; sauvegarde $backupPath"
if ($DeduplicateExisting -and @($audit.duplicateGroups).Count) {
    $cleanup = Send-TestPost @{ action = 'deduplicateruns'; adminKey = $dashboardKey; confirm = 'DEDUPLICATE_SAME_RUN_ID' }
    Write-Host "Doublons RunId retires : $($cleanup.removed)"
}
$prefix = 'CODEX-TEST-' + [guid]::NewGuid().ToString('N')
$ids = @(0..5 | ForEach-Object { $prefix + '-' + $_ })
$expected = @('success', 'warning', 'error', 'stopped', 'timeout', 'success')
try {
    $started = @()
    for ($i = 0; $i -lt $ids.Count; $i++) {
        $run = [ordered]@{
            RunId = $ids[$i]; Source = 'LDLC PREPTOOL'; ApplicationSource = 'LDLC_PREPARATION_PC'
            ToolVersion = if ($i -eq 5) { '2.5.2' } else { '2.6.0' }
            ComputerName = if ($i -lt 2) { 'CODEX-TEST-SAME-PC' } else { "CODEX-TEST-PC-$i" }
            UserName = ''; StartedAt = [datetime]::UtcNow.ToString('o'); Status = 'running'
            IsFinal = $false; Sequence = 1; ProgressPercent = 0
        }
        $started += @{ Run = $run; Events = @() }
    }
    [void](Send-TestPost @{ payloads = $started })
    $running = Get-TestSnapshot
    foreach ($id in $ids) {
        $rows = @($running.runs | Where-Object { $_.runId -eq $id })
        if ($rows.Count -ne 1 -or $rows[0].isFinal) { throw 'Le demarrage doit creer une ligne en cours par RunId.' }
    }
    $finals = @()
    for ($i = 0; $i -lt $ids.Count; $i++) {
        $run = @{}
        foreach ($key in $started[$i].Run.Keys) { $run[$key] = $started[$i].Run[$key] }
        $run.Status = $expected[$i]; $run.IsFinal = $true; $run.Sequence = 2
        $run.FinishedAt = [datetime]::UtcNow.ToString('o'); $run.DurationSeconds = 12
        $run.ProgressPercent = 100; $run.ErrorCount = if ($i -eq 2) { 2 } else { 0 }
        $run.WarningCount = if ($i -eq 1) { 1 } else { 0 }
        $run.WarningDetails = if ($i -eq 1) { 'TEST UNIQUEMENT : PDF non confirme (simulation)' } else { '' }
        $events = @()
        if ($i -eq 2) {
            foreach ($number in @(1, 2)) {
                $events += @{ RunId = $ids[$i]; Timestamp = [datetime]::UtcNow.ToString('o'); Severity = 'error'; Type = 'TEST'; Step = 'TEST'; Message = "TEST UNIQUEMENT : erreur simulee $number" }
            }
        }
        if ($i -eq 5) { $run.Remove('Sequence'); $run.Remove('WarningDetails') }
        $finals += @{ Run = $run; Events = $events }
    }
    [void](Send-TestPost @{ payloads = $finals })
    [void](Send-TestPost @{ payloads = $finals + $started })
    $after = Get-TestSnapshot
    $stored = Get-TestAudit
    $runIndex = [array]::IndexOf($stored.headers, 'RunId')
    $statusIndex = [array]::IndexOf($stored.headers, 'Statut')
    $versionIndex = [array]::IndexOf($stored.headers, 'Version')
    for ($i = 0; $i -lt $ids.Count; $i++) {
        $rows = @($stored.values | Where-Object { $_[$runIndex] -eq $ids[$i] })
        $display = @($after.runs | Where-Object { $_.runId -eq $ids[$i] })
        if ($rows.Count -ne 1 -or $rows[0][$statusIndex] -ne $expected[$i] -or $display.Count -ne 1 -or -not $display[0].isFinal) { throw "Finalisation/deduplication incorrecte : $($ids[$i])" }
        $version = if ($i -eq 5) { '2.5.2' } else { '2.6.0' }
        if ($rows[0][$versionIndex] -cne $version) { throw 'La version doit rester un texte, pas une date Sheets.' }
    }
    if (@($after.rawErrors | Where-Object { $_.runId -eq $ids[2] }).Count -ne 2) { throw 'Les deux erreurs doivent rester uniques apres relecture et renvoi.' }
    if ($after.sheetLayout.hiddenRunHeaders -notcontains 'EtapesTerminees') { throw 'La colonne EtapesTerminees doit rester masquee.' }
    $lost = @($before.runs | Where-Object { $_.runId -and $_.runId -notin @($after.runs.runId) })
    if ($lost.Count) { throw 'Des executions historiques ne sont plus visibles.' }
    Write-Host 'OK live permanent Sheet/dashboard: start/final/replay, success/warning/error/stop/timeout, legacy optional fields, empty user, separate runs/PCs, text version, hidden steps, history preserved.'
} finally {
    foreach ($id in $ids) {
        if ($id.StartsWith($prefix + '-', [StringComparison]::Ordinal)) {
            [void](Send-TestPost @{ action = 'deleterun'; adminKey = $dashboardKey; RunId = $id })
        }
    }
}
$final = Get-TestSnapshot
if (@($final.runs | Where-Object { $_.runId -in $ids }).Count) { throw 'Nettoyage des seules lignes de test non confirme.' }
Write-Host 'OK toutes les lignes de test ont ete retirees; liens permanents inchanges.'
