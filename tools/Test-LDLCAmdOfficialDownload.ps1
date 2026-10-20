#requires -Version 5.1
[CmdletBinding()]
param([string]$ReportPath = 'artifacts/amd-official-download.json')
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'modules/60.Gpu.ps1')
$report = [ordered]@{ Success=$false; Commit=$env:GITHUB_SHA; Platform=[Environment]::OSVersion.VersionString; RealNetwork=$true; InstallerExecuted=$false; DriverInstalled=$false; Phase='resolution' }
$temp = Join-Path ([IO.Path]::GetTempPath()) ('Preparation-AmdLive-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072
    $source = Resolve-LDLCAmdGpuOfficialSource
    $report.Source = $source
    $report.Phase='download'
    $path=Join-Path $temp $source.FileName
    Invoke-WebRequest -Uri $source.Url -Headers @{Referer=$source.PageUrl;'Cache-Control'='no-cache';Pragma='no-cache'} -OutFile $path -UseBasicParsing -TimeoutSec 600 -ErrorAction Stop | Out-Null
    $report.Bytes=(Get-Item -LiteralPath $path).Length
    $report.SHA256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    $signature=Get-AuthenticodeSignature -LiteralPath $path
    $report.SignatureStatus=[string]$signature.Status
    $report.Signer=if($signature.SignerCertificate){[string]$signature.SignerCertificate.Subject}else{''}
    $report.Phase='verification'
    if(-not (Test-LDLCAmdGpuInstallerFile -Path $path)){throw 'Fichier AMD non valide : PE, taille ou signature.'}
    $report.Success=$true
}
catch {
    $report.FailureType=$_.Exception.GetType().Name
    $report.Reason=$_.Exception.Message
    # Diagnostics are restricted to public AMD download links, never machine/user data.
    try {
        $response=Invoke-WebRequest -Uri 'https://www.amd.com/en/support/download/drivers.html' -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
        $report.PageStatus=[int]$response.StatusCode
        $report.PublicInstallerLinks=@([regex]::Matches([Net.WebUtility]::HtmlDecode([string]$response.Content),'(?i)(?:https:)?//(?:drivers|download)\.amd\.com/[^"''<>\s]+\.exe') | ForEach-Object {$_.Value} | Select-Object -Unique -First 20)
    }catch{$report.DiagnosticRequestFailed=$true}
}
finally {
    New-Item -ItemType Directory -Path (Split-Path -Parent $ReportPath) -Force | Out-Null
    $json=$report | ConvertTo-Json -Depth 10
    $json | Set-Content -LiteralPath $ReportPath -Encoding UTF8
    Write-Host ('::notice title=AMD official live download::'+($json -replace '%','%25' -replace "`r",'%0D' -replace "`n",'%0A'))
    Remove-Item -LiteralPath $temp -Recurse -Force
}
if(-not $report.Success){exit 1}
