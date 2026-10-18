$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$report=[ordered]@{Available=$false;Scope='Lecture du dashboard permanent uniquement; aucun rapport ajoute ou supprime.'}
try {
    # Reuse the repository's permanent endpoint/key without printing credentials.
    $config=Get-Content -LiteralPath (Join-Path $root 'tools/Deploy-LDLCDashboard.ps1') -Raw
    $deployment=[regex]::Match($config,'\$deploymentId = ''([^'']+)''').Groups[1].Value
    $key=[regex]::Match($config,'\$dashboardKey = ''([^'']+)''').Groups[1].Value
    if(-not $deployment -or -not $key){throw 'Configuration absente'}
    [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
    $watch=[Diagnostics.Stopwatch]::StartNew()
    $snapshot=Invoke-RestMethod -Uri ('https://script.google.com/macros/s/'+$deployment+'/exec?format=json&key='+[uri]::EscapeDataString($key)) -TimeoutSec 60
    $watch.Stop()
    if($snapshot.ok -eq $false -or $null -eq $snapshot.runs){throw 'Snapshot invalide'}
    $report.Available=$true
    $report.Seconds=[math]::Round($watch.Elapsed.TotalSeconds,3)
    $report.RunCount=@($snapshot.runs).Count
    $report.Statuses=@($snapshot.runs | Group-Object status | ForEach-Object{[ordered]@{Status=$_.Name;Count=$_.Count}})
    $reasons=@($snapshot.runs | Where-Object{$_.status -match 'warning|avert|timeout|delai|bloq|error|fail|echec|erreur'} | ForEach-Object{
        $reason=if($_.warningDetails){[string]$_.warningDetails}else{[string]$_.lastMessage}
        $reason=$reason -replace 'https?://\S+','[adresse]' -replace '[\w.+-]+@[\w.-]+\.[a-zA-Z]{2,}','[courriel]' -replace '[A-Za-z]:\\Users\\[^\\\s]+','[profil]'
        if($reason.Length -gt 500){$reason=$reason.Substring(0,500)}
        if($reason){$reason}
    })
    $report.Causes=@($reasons | Group-Object | Sort-Object Count -Descending | Select-Object -First 12 | ForEach-Object{[ordered]@{Reason=$_.Name;Count=$_.Count}})
} catch {
    $report.ErrorType=$_.Exception.GetType().Name
    # Exception text can contain the authenticated URI: never echo it.
    if($_.Exception.Response){$report.HttpStatus=[int]$_.Exception.Response.StatusCode}
}
$folder=Join-Path $root 'artifacts'
New-Item -ItemType Directory -Path $folder -Force | Out-Null
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $folder 'lecture-dashboard.json') -Encoding UTF8
$message=($report | ConvertTo-Json -Depth 8 -Compress).Replace('%','%25').Replace("`r",'%0D').Replace("`n",'%0A')
Write-Host "::notice title=PrepTool lecture Google::$message"
