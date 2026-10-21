#requires -Version 5.1
[CmdletBinding()]
param([string]$ReportPath='artifacts/amd-chocolatey-package.json')
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor 3072
$report=[ordered]@{Success=$false;RealNetwork=$true;ChocolateyInstallExecuted=$false;HardwareInstallerExecuted=$false;Package='amd-software-adrenalin-edition';Commit=$env:GITHUB_SHA}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('Amd-Choco-Inspect-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($temp)
try {
 $cmd=Get-Command choco.exe -ErrorAction Stop
 $report.ChocolateyVersion=(& $cmd.Source --version | Out-String).Trim()
 $lines=@(& $cmd.Source search amd-software-adrenalin-edition --exact --all-versions --pre --limit-output --source https://community.chocolatey.org/api/v2)
 if($LASTEXITCODE -ne 0){throw ('Chocolatey search failed, code '+$LASTEXITCODE)}
 $versions=@($lines|Where-Object {$_ -match '^amd-software-adrenalin-edition\|'}|ForEach-Object {($_ -split '\|')[1]})
 if(-not $versions.Count){throw 'Package absent du catalogue Chocolatey.'}
 $ordered=@($versions|Sort-Object @{Expression={[version]([regex]::Match($_,'^\d+(?:\.\d+){1,3}').Value)};Descending=$true},@{Expression={$_ -notmatch '-'};Descending=$true})
 $report.PublishedVersions=@($ordered|Select-Object -First 16)
 $report.LatestIncludingPrerelease=$ordered[0]
 $report.LatestStable=$ordered|Where-Object {$_ -notmatch '-'}|Select-Object -First 1
 $selected=$ordered[0]
 $path=Join-Path $temp 'package.nupkg'
 Invoke-WebRequest -Uri ('https://community.chocolatey.org/api/v2/package/amd-software-adrenalin-edition/'+[uri]::EscapeDataString($selected)) -OutFile $path -UseBasicParsing -TimeoutSec 120
 Add-Type -AssemblyName System.IO.Compression.FileSystem
 $zip=[IO.Compression.ZipFile]::OpenRead($path)
 try {
  $entry=$zip.Entries|Where-Object {$_.FullName -match '(?i)(^|/)chocolateyinstall\.ps1$'}|Select-Object -First 1
  if(-not $entry){throw 'Install script not available for inspection'}
  $reader=New-Object IO.StreamReader($entry.Open());try{$scriptText=$reader.ReadToEnd()}finally{$reader.Dispose()}
  $report.InstallerUrl=[regex]::Match($scriptText,'(?im)^\s*url64\s*=\s*["''](?<u>[^"'']+)["'']').Groups['u'].Value
  $report.InstallerSHA256=[regex]::Match($scriptText,'(?im)^\s*checksum64\s*=\s*["''](?<h>[0-9a-f]{64})["'']').Groups['h'].Value
  $report.SilentArgs=[regex]::Match($scriptText,'(?im)^\s*silentArgs\s*=\s*["''](?<a>[^"'']+)["'']').Groups['a'].Value
  $report.InstallerVersion=[regex]::Match($report.InstallerUrl,'(?i)adrenalin-edition-(?<v>\d+(?:\.\d+){1,3})-').Groups['v'].Value
 }finally{$zip.Dispose()}
 . (Join-Path (Split-Path -Parent $PSScriptRoot) 'modules/60.Gpu.ps1')
 $runtimeInfo=Get-LDLCAmdChocolateyPackageMetadata -PackagePath $path
 if($runtimeInfo.Url -cne $report.InstallerUrl -or $runtimeInfo.SHA256 -ine $report.InstallerSHA256 -or $runtimeInfo.ChecksumType -ine 'sha256' -or $runtimeInfo.SilentArgs -cne '-install'){throw 'Runtime package reader does not confirm the real Chocolatey package metadata'}
 $report.RuntimeMetadataReaderVerified=$true
 $amd=Resolve-LDLCAmdGpuOfficialSource
 $report.OfficialLatestVersion=$amd.Version
 $report.CurrentEnough=($report.InstallerVersion -and [version]$report.InstallerVersion -ge [version]$amd.Version)
 $exact=Join-Path $temp 'official-version.nupkg'
 $report.ExactOfficialPackageUrl='https://community.chocolatey.org/api/v2/package/amd-software-adrenalin-edition/'+[uri]::EscapeDataString([string]$amd.Version)
 try{
  Invoke-WebRequest -Uri $report.ExactOfficialPackageUrl -OutFile $exact -UseBasicParsing -TimeoutSec 120
  $report.ExactOfficialPackageAvailable=$true
  $exactInfo=Get-LDLCAmdChocolateyPackageMetadata -PackagePath $exact
  $report.ExactOfficialPackageMetadata=$exactInfo
 }catch{
  $status=0;try{$status=[int]$_.Exception.Response.StatusCode}catch{}
  $report.ExactOfficialPackageStatus=$status
  $report.ExactOfficialPackageAvailable=$false
  $report.ExactOfficialPackageReason=$_.Exception.Message
  if($status -ne 404){throw}
 }
 $report.Success=$true
}catch{$report.ErrorType=$_.Exception.GetType().Name;$report.Reason=$_.Exception.Message}
finally {
 [void](New-Item -ItemType Directory -Path (Split-Path -Parent $ReportPath) -Force)
 $report|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $ReportPath -Encoding UTF8
 Write-Host ('::notice title=AMD Chocolatey catalog verification::'+(($report|ConvertTo-Json -Depth 8 -Compress).Replace('%','%25').Replace("`r",'%0D').Replace("`n",'%0A')))
 Remove-Item -LiteralPath $temp -Recurse -Force
}
if(-not $report.Success){exit 1}
