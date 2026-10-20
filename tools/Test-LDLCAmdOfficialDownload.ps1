#requires -Version 5.1
[CmdletBinding()]
param([string]$ReportPath = 'artifacts/amd-official-download.json',[switch]$FullPackage)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
function Stop-IfRequested {}
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'modules/60.Gpu.ps1')
$report = [ordered]@{ Success=$false; Commit=$env:GITHUB_SHA; Platform=[Environment]::OSVersion.VersionString; RealNetwork=$true; InstallerExecuted=$false; DriverInstalled=$false; Phase='resolution' }
$temp = Join-Path ([IO.Path]::GetTempPath()) ('Preparation-AmdLive-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072
    $source = Resolve-LDLCAmdGpuOfficialSource
    if($FullPackage){
        $sources=@(Resolve-LDLCAmdGpuFullOfficialSources -AutoDetectSource $source)
        $report.FullSources=$sources
        $source=$sources | Where-Object {$_.FileName -match '(?i)win10|win11'} | Select-Object -First 1
        if(-not $source){throw 'Package Windows 10/11 introuvable.'}
    }
    $report.Source = $source
    $report.Phase='download'
    Write-Host ('::notice title=AMD official selected source::'+($source|ConvertTo-Json -Depth 6 -Compress))
    $path=Join-Path $temp $source.FileName
    Invoke-WebRequest -Uri $source.Url -Headers @{Referer=$source.PageUrl;'Cache-Control'='no-cache';Pragma='no-cache'} -OutFile $path -UseBasicParsing -TimeoutSec 600 -ErrorAction Stop | Out-Null
    $report.Bytes=(Get-Item -LiteralPath $path).Length
    $report.SHA256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    $signature=Get-AuthenticodeSignature -LiteralPath $path
    $report.SignatureStatus=[string]$signature.Status
    $report.Signer=if($signature.SignerCertificate){[string]$signature.SignerCertificate.Subject}else{''}
    $report.Phase='verification'
    if(-not (Test-LDLCAmdGpuInstallerFile -Path $path)){throw 'Fichier AMD non valide : PE, taille ou signature.'}
    if($FullPackage){
        $seven=Join-Path $env:ProgramFiles '7-Zip/7z.exe'
        $listing=@(& $seven l -slt $path)
        if($LASTEXITCODE -ne 0){throw 'Lecture archive AMD en echec.'}
        $report.UiPackagePaths=@($listing | Where-Object {$_ -match '(?i)^Path = .*?(?:CNext|CNBrand|ccc2|RadeonSoftware|AMDSoftware)'} | Select-Object -First 25)
        $metadata=Join-Path $temp 'metadata'
        Expand-LDLCAmdPackageMetadata -Path $path -Destination $metadata
        $infs=@(Get-ChildItem -LiteralPath $metadata -Filter '*.inf' -File -Recurse | Where-Object {[IO.File]::ReadAllText($_.FullName) -match '(?im)^\s*Class\s*=\s*Display\s*$'})
        if(-not $infs.Count){throw 'Aucune preuve de pilote DISPLAY dans le package complet.'}
        $ids=New-Object 'Collections.Generic.List[string]'
        foreach($inf in $infs){
            $text=[IO.File]::ReadAllText($inf.FullName)
            foreach($m in [regex]::Matches($text,'(?i)PCI\\VEN_1002&DEV_[0-9A-F]{4}(?:&(?:SUBSYS_[0-9A-F]{8}|REV_[0-9A-F]{2}))*')){[void]$ids.Add($m.Value)}
        }
        $targets=@();foreach($id in @($ids|Select-Object -Unique -First 50)){
            try{$targets+=@(Get-LDLCAmdPackageDriverTargets -MetadataPath $metadata -PnpDeviceIds @($id) -WindowsBuild 26100);if($targets.Count -ge 3){break}}catch{}
        }
        if(-not $targets.Count){
            $report.InfExamples=@($infs|Select-Object -First 2|ForEach-Object {@{Name=$_.Name;Lines=@([IO.File]::ReadAllLines($_.FullName)|Where-Object {$_ -match '^DriverVer|^Class|^\[|PCI\\VEN_1002'}|Select-Object -First 20)}})
            throw 'Aucune cible de version INF lisible pour les GPU proposes.'
        }
        $report.DisplayInfCount=$infs.Count
        $report.SampleTargets=@($targets|Select-Object PnpDeviceId,DriverVersion,HardwareId)
        $report.ExtractedUiFiles=@(Get-ChildItem -LiteralPath $metadata -File -Recurse | Where-Object {$_.Name -in @('RadeonSoftware.exe','AMDSoftware.exe')} | Select-Object -First 4 | ForEach-Object {@{FileName=$_.Name;Version=(Get-LDLCFileVersionText -Path $_.FullName)}})

    }
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
