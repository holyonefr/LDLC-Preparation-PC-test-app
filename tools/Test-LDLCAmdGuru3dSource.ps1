#requires -Version 5.1
[CmdletBinding()]
param([string]$PageUrl='https://www.guru3d.com/download/amd-radeon-software-adrenalin-26101-driver-download/',[string]$ReportPath='artifacts/amd-guru3d-source.json')
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$report=[ordered]@{Success=$false;PageUrl=$PageUrl;RealNetwork=$true;InstallerExecuted=$false;FileDownloaded=$false}
try {
 [Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor 3072
 $r=Invoke-WebRequest -Uri $PageUrl -UseBasicParsing -Headers @{'User-Agent'='Mozilla/5.0 (Windows NT 10.0; Win64; x64)';'Cache-Control'='no-cache'} -TimeoutSec 60 -ErrorAction Stop
 $report.Status=[int]$r.StatusCode
 $text=[Net.WebUtility]::HtmlDecode([string]$r.Content)
 $report.Title=[regex]::Match($text,'(?is)<title>(.*?)</title>').Groups[1].Value
 $links=@();foreach($m in [regex]::Matches($text,'(?i)href\s*=\s*["''](?<u>[^"''<>]+)["'']')){
  try{$u=[uri]::new([uri]$PageUrl,$m.Groups['u'].Value)}catch{continue}
  if($u.AbsoluteUri -match '(?i)\.exe(?:\?|$)|files-get|files-details|getdownload|download\.guru3d|download_mirror|downloadmirror'){$links += $u.AbsoluteUri}
 }
 $report.DownloadLinks=@($links|Select-Object -Unique -First 30)
 $report.DownloadSectionText=@([regex]::Matches($text,'(?is).{0,150}(?:download mirror|getdownload|files-get|\.exe|sha256|MD5).{0,180}')|ForEach-Object {($_.Value -replace '<[^>]+>',' ' -replace '\s+',' ').Trim()}|Select-Object -First 12)
 $report.Success=$true
}catch{$report.ErrorType=$_.Exception.GetType().Name;$report.Reason=$_.Exception.Message}
[void](New-Item -ItemType Directory -Path (Split-Path -Parent $ReportPath) -Force)
$report|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $ReportPath -Encoding UTF8
Write-Host ('::notice title=AMD Guru3D source inspection::'+(($report|ConvertTo-Json -Depth 8 -Compress).Replace('%','%25').Replace("`r",'%0D').Replace("`n",'%0A')))
if(-not $report.Success){exit 1}
