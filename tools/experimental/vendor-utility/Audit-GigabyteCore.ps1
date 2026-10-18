#requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputDirectory,[string]$RecordedOfficialCatalogue)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
Import-Module (Join-Path $PSScriptRoot 'VendorUtility.psm1') -Force
$module=Get-Module VendorUtility
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
[void](New-Item -ItemType Directory -Path $OutputDirectory -Force)
$report=[ordered]@{Kind='gigabyte_core_static_audit';Status='failed';VendorInstallerExecuted=$false;Installed=$false;CatalogueMode='live';CatalogueSnapshotSHA256='';Discovery=$null;Bundle=$null;Core=$null;Application=$null;Error=''}
try {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Audit de signature exige Windows natif.' }
    if ($PSBoundParameters.ContainsKey('RecordedOfficialCatalogue')) {
        # Explicit static-audit mode only. Never a silent fallback and never a
        # claim of current catalogue availability on this Windows runner.
        $snapshot=Get-Item -LiteralPath $RecordedOfficialCatalogue -ErrorAction Stop
        if ($snapshot.Length -gt 2097152 -or $snapshot.PSIsContainer) { throw 'Capture catalogue absente ou trop volumineuse.' }
        $html=[IO.File]::ReadAllText($snapshot.FullName)
        $discovery=& $module { param($h) ConvertFrom-VutGigabyteCatalogue -Html $h } $html
        $discovery.Method='recorded_official_gigabyte_utility_html'
        $report.CatalogueMode='recorded_response_2026-10-18_not_live_on_runner'
        $report.CatalogueSnapshotSHA256=(Get-FileHash -LiteralPath $snapshot.FullName).Hash
    } else { $discovery=& $module { Resolve-VutGigabyteDownload } }
    $report.Discovery=$discovery
    $bundle=& $module { param($u,$d) $tool=@(Get-MbxToolDefinitions | Where-Object Vendor -eq GIGABYTE)[0]; Invoke-MbxUtilityAudit -Tool $tool -DownloadUrl $u -OutputDirectory $d -TimeoutSeconds 180 } $discovery.DownloadUrl $OutputDirectory
    $report.Bundle=$bundle
    if ($bundle.Payloads.Count -ne 1 -or $bundle.Bytes -ne $bundle.ExpectedBytes) { throw 'Archive GCC incomplete ou executable externe ambigu.' }
    $outer=@(Get-ChildItem -LiteralPath $OutputDirectory -Directory | Where-Object Name -match '\A[0-9a-f]{32}\z' | ForEach-Object { $p=Join-Path $_.FullName 'payload-0.exe'; if (Test-Path -LiteralPath $p -PathType Leaf) { $p } })
    if ($outer.Count -ne 1) { throw 'Chemin de l executable archive ambigu.' }
    $sevenZip=Join-Path $env:ProgramFiles '7-Zip/7z.exe'
    if (-not (Test-Path -LiteralPath $sevenZip -PathType Leaf)) { throw '7-Zip du runner absent ; aucun installateur constructeur utilise comme outil extraction.' }
    function Invoke-StaticSevenZip {
        param([string[]]$Arguments)
        $p=New-Object Diagnostics.Process
        $p.StartInfo.FileName=$sevenZip
        $p.StartInfo.Arguments=(@($Arguments | ForEach-Object { '"'+$_.Replace('"','\"')+'"' }) -join ' ')
        $p.StartInfo.UseShellExecute=$false; $p.StartInfo.RedirectStandardOutput=$true; $p.StartInfo.RedirectStandardError=$true
        try {
            [void]$p.Start()
            $stdout=$p.StandardOutput.ReadToEndAsync(); $stderr=$p.StandardError.ReadToEndAsync()
            if (-not $p.WaitForExit(180000)) { $p.Kill(); [void]$p.WaitForExit(5000); throw 'Delai outil extraction statique depasse.' }
            if (-not $stdout.Wait(5000) -or -not $stderr.Wait(5000)) { throw 'Sortie outil extraction statique non terminee.' }
            $text=$stdout.GetAwaiter().GetResult()+$stderr.GetAwaiter().GetResult()
            if ($p.ExitCode -ne 0) { throw ('Outil extraction statique : code '+$p.ExitCode+'. '+$text.Substring(0,[Math]::Min(400,$text.Length))) }
            if ($text.Length -gt 1048576) { throw 'Liste archive trop longue pour cet audit borne.' }
            return $text
        } finally { $p.Dispose() }
    }
    function Find-StaticEntry {
        param([string]$Archive,[string]$LeafPattern)
        $listing=Invoke-StaticSevenZip -Arguments @('l','-slt',$Archive)
        $entries=@(foreach ($line in $listing -split '\r?\n') {
            if ($line -match '\APath = (.+)\z') {
                $entryPath=$Matches[1]
                if ([IO.Path]::GetFileName($entryPath) -match $LeafPattern) {
                    if ($entryPath -match '(^[/\\@-]|(^|[/\\])\.\.([/\\]|$)|[:"\x00-\x1f])') { throw 'Chemin archive dangereux refuse.' }
                    $entryPath
                }
            }
        })
        if ($entries.Count -ne 1) { throw 'Fichier principal archive absent ou ambigu.' }
        return $entries[0]
    }
    $coreEntry=Find-StaticEntry -Archive $outer[0] -LeafPattern '\AGIGABYTE Control Center_[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\.exe\z'
    $coreDir=Join-Path $OutputDirectory 'core'
    [void](New-Item -ItemType Directory -Path $coreDir)
    [void](Invoke-StaticSevenZip -Arguments @('e','-y',('-o'+$coreDir),$outer[0],$coreEntry))
    $corePath=Join-Path $coreDir ([IO.Path]::GetFileName($coreEntry))
    $core=& $module { param($p) $tool=@(Get-MbxToolDefinitions | Where-Object Vendor -eq GIGABYTE)[0]; Test-MbxSignedPayload -Path $p -Signers $tool.Signers } $corePath
    $report.Core=[ordered]@{FileName=[IO.Path]::GetFileName($corePath);Signature=$core}
    $appEntry=Find-StaticEntry -Archive $corePath -LeafPattern '\AGCC\.exe\z'
    $appDir=Join-Path $OutputDirectory 'application'
    [void](New-Item -ItemType Directory -Path $appDir)
    [void](Invoke-StaticSevenZip -Arguments @('e','-y',('-o'+$appDir),$corePath,$appEntry))
    $appPath=Join-Path $appDir 'GCC.exe'
    $app=& $module { param($p) $tool=@(Get-MbxToolDefinitions | Where-Object Vendor -eq GIGABYTE)[0]; Test-MbxSignedPayload -Path $p -Signers $tool.Signers } $appPath
    $info=[Diagnostics.FileVersionInfo]::GetVersionInfo($appPath)
    $report.Application=[ordered]@{FileName='GCC.exe';Signature=$app;ProductName=$info.ProductName;FileDescription=$info.FileDescription;ProductVersion=$info.ProductVersion}
    $report.Status='official_download_and_three_signed_executables_verified'
} catch { $report.Error=$_.Exception.Message }
$report | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'gigabyte-core-audit.json') -Encoding UTF8
& $module { param($r) Write-MbxEvidence -Kind 'gigabyte_core_static_audit' -Data $r } $report
if ($report.Status -eq 'failed') { throw $report.Error }
Write-Host ('GCC : bundle '+$report.Discovery.BundleVersion+' ; signatures controlees ; aucun installateur execute.')
