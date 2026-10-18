#requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputDirectory, [ValidateSet('MSI','ASRock')][string]$Vendor='MSI', [string]$CurrentAsrockModel)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
Import-Module (Join-Path $PSScriptRoot '../motherboard/MotherboardExperiment.psm1') -Force
[void](New-Item -ItemType Directory -Path $OutputDirectory -Force)
$discovery=$null
$package=$null
$currentAsrock=$PSBoundParameters.ContainsKey('CurrentAsrockModel')
if ($currentAsrock) {
    if ([string]::IsNullOrWhiteSpace($CurrentAsrockModel)) { throw 'Mode ASRock courant : modele requis ; aucun repli vers un ancien snapshot.' }
    $Vendor='ASRock'
}
Write-MbxEvidence -Kind 'utility_inspection_stage' -Data @{Stage='official_download_started';Vendor=$Vendor;CurrentAsrockModel=$CurrentAsrockModel;VendorInstallerExecuted=$false}
if ($currentAsrock) {
    Import-Module (Join-Path $PSScriptRoot 'VendorUtility.psm1') -Force
    $utilityModule=Get-Module VendorUtility
    # Explicit model/OS lookup and verified download only. Never invoke the utility or its installer.
    $package=& $utilityModule {
        param($model,$directory)
        $profile=Get-VutProfile ASRock -BoardModel $model -TargetOs 'Windows 11 64bit'
        Get-VutPackage -Profile $profile -Directory $directory
    } $CurrentAsrockModel.Trim() $OutputDirectory
    $audit=$package.Audit
    $discovery=$package.Discovery
    if (-not $discovery -or $discovery.Method -ne 'official_asrock_model_xml') { throw 'Detection ASRock courante absente ; aucun ancien snapshot inspecte.' }
    # The nested Force import moves the shared helpers into VendorUtility's scope
    # on Windows PowerShell 5.1. Re-import them for this standalone audit script.
    Import-Module (Join-Path $PSScriptRoot '../motherboard/MotherboardExperiment.psm1')
    $downloadUrl=$discovery.DownloadUrl
    $installer=Get-Item -LiteralPath $package.Path -ErrorAction Stop
} else {
    # Preserve the original MSI audit and explicitly selected historical ASRock snapshot.
    $tool=@(Get-MbxToolDefinitions | Where-Object Vendor -eq $Vendor)[0]
    $downloadUrl=if ($Vendor -eq 'MSI') { 'https://download-2.msi.com/uti_exe/desktop/MSI-Center.zip' } else { 'https://download.asrock.com/Utility/Others/APPShop%28v2.0.0.4%29.zip' }
    if ($Vendor -eq 'ASRock') { $tool.FilePattern='(?i)^APPShop\(v[0-9.]+\)\.zip$' }
    $audit=Invoke-MbxUtilityAudit -Tool $tool -DownloadUrl $downloadUrl -OutputDirectory $OutputDirectory -TimeoutSeconds 120
    $installer=Get-ChildItem -Path $OutputDirectory -Recurse -Filter 'payload-*.exe' | Select-Object -First 1
}
Write-MbxEvidence -Kind 'utility_inspection_stage' -Data @{Stage='official_download_verified';Audit=$audit;Discovery=$discovery;VendorInstallerExecuted=$false}
if (-not $installer) { throw 'Installateur extrait absent.' }
$installerHash=(Get-FileHash -LiteralPath $installer.FullName -Algorithm SHA256).Hash
$installerVersion=[Diagnostics.FileVersionInfo]::GetVersionInfo($installer.FullName).FileVersion
# Portable open-source unpacker, pinned release asset/hash. Not the GUI setup executable.
$unpackUrl='https://github.com/jrathlev/InnoUnpacker-Windows-GUI/releases/download/ui_2_2_13/innounp-2.zip'
$expected='10FCE27B6344B7674D5625CC34AFCA1C88C12183D957C6D93E401097FA2556CD'
$zip=Join-Path $OutputDirectory 'unpacker.zip'
Invoke-WebRequest -Uri $unpackUrl -UseBasicParsing -OutFile $zip -TimeoutSec 60
if ((Get-FileHash $zip).Hash -ne $expected) { throw 'Empreinte de l outil d inspection invalide.' }
$unpackDir=Join-Path $OutputDirectory 'unpacker'
Expand-Archive -LiteralPath $zip -DestinationPath $unpackDir
$unpacker=Get-ChildItem -LiteralPath $unpackDir -Recurse -Filter 'innounp*.exe' | Select-Object -First 1
if (-not $unpacker) { throw 'Outil portable d inspection absent.' }
Write-MbxEvidence -Kind 'utility_inspection_stage' -Data @{Stage='portable_unpacker_verified';VendorInstallerExecuted=$false}
function Invoke-Unpacker {
    param([string[]]$Arguments)
    $p=New-Object Diagnostics.Process
    $p.StartInfo.FileName=$unpacker.FullName
    $p.StartInfo.Arguments=(@($Arguments | ForEach-Object { '"'+$_.Replace('"','\"')+'"' }) -join ' ')
    $p.StartInfo.UseShellExecute=$false; $p.StartInfo.RedirectStandardOutput=$true; $p.StartInfo.RedirectStandardError=$true
    try {
        [void]$p.Start()
        $stdout=$p.StandardOutput.ReadToEndAsync(); $stderr=$p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit(120000)) { $p.Kill(); [void]$p.WaitForExit(5000); return [pscustomobject]@{ExitCode=-1;Text='Static unpacker exceeded 120 seconds; no vendor installer executed.'} }
        if (-not $stdout.Wait(5000) -or -not $stderr.Wait(5000)) { throw 'Flux du decompresseur statique non termines apres la fin du processus.' }
        return [pscustomobject]@{ExitCode=$p.ExitCode;Text=($stdout.GetAwaiter().GetResult()+$stderr.GetAwaiter().GetResult())}
    } finally { $p.Dispose() }
}
$listed=Invoke-Unpacker -Arguments @('-v','-b','-q','-o',$installer.FullName)
$listText=$listed.Text.Substring(0,[Math]::Min(262144,$listed.Text.Length))
$list=@($listText -split '\r?\n')
$listExit=$listed.ExitCode
Write-MbxEvidence -Kind 'utility_inspection_stage' -Data @{Stage='static_list_complete';ExitCode=$listExit;VendorInstallerExecuted=$false}
$list | Set-Content (Join-Path $OutputDirectory 'file-list.txt') -Encoding UTF8
$extractDir=Join-Path $OutputDirectory 'static-script'
[void](New-Item -ItemType Directory -Path $extractDir)
$extracted=Invoke-Unpacker -Arguments @('-x','-m','-b','-q','-o',('-d'+$extractDir),$installer.FullName,'install_script.iss','*setup.ps1')
$extractText=$extracted.Text.Substring(0,[Math]::Min(262144,$extracted.Text.Length))
$output=@($extractText -split '\r?\n'); $extractExit=$extracted.ExitCode
Write-MbxEvidence -Kind 'utility_inspection_stage' -Data @{Stage='static_extract_complete';ExitCode=$extractExit;VendorInstallerExecuted=$false}
$output | Set-Content (Join-Path $OutputDirectory 'unpacker-output.txt') -Encoding UTF8
# The unpacker's internal script has a fixed root name; never recurse into payload trees.
$scriptPath=Join-Path $extractDir 'install_script.iss'
$scripts=@(if (Test-Path -LiteralPath $scriptPath -PathType Leaf) { Get-Item -LiteralPath $scriptPath })
Write-MbxEvidence -Kind 'utility_inspection_stage' -Data @{Stage='bounded_metadata_started';ScriptFiles=$scripts.Count;ListCharacters=$listed.Text.Length;ExtractCharacters=$extracted.Text.Length;VendorInstallerExecuted=$false}
$sections=@{}
$truncated=($listText.Length -ne $listed.Text.Length -or $extractText.Length -ne $extracted.Text.Length)
foreach ($scriptFile in $scripts) {
    if ($scriptFile.Length -gt 4194304) { $truncated=$true; continue }
    $section=''
    $lines=[IO.File]::ReadAllLines($scriptFile.FullName)
    if ($lines.Count -gt 10000) { $truncated=$true; $lines=$lines[0..9999] }
    foreach ($line in $lines) {
        if ($line -match '^\[(.+)\]') { $section=$Matches[1]; if (-not $sections.ContainsKey($section)) { $sections[$section]=@() } }
        elseif ($section -in @('Setup','Run','Tasks','Components','Code','Registry','Icons')) {
            if ($sections[$section].Count -lt 200) { $sections[$section]+=$line } else { $truncated=$true }
        }
    }
}
$report=[ordered]@{
    Kind='static_installer_inspection'; Vendor=$Vendor; VendorInstallerExecuted=$false; Audit=$audit; PortableUnpackerSHA256=$expected
    InspectionMode=if ($currentAsrock) { 'current_official_asrock_model' } elseif ($Vendor -eq 'ASRock') { 'historical_asrock_snapshot' } else { 'official_msi_archive' }
    Discovery=$discovery; DownloadUrl=$downloadUrl; ArchiveSHA256=$audit.SHA256
    InstallerSHA256=$installerHash; InstallerFileVersion=$installerVersion
    SourceClaim=if ($currentAsrock) { 'Current APP Shop release selected from the official model and Windows 11 x64 catalog; download hash, signature and version verified. Installer not executed; physical PC installation and behavior not tested.' } else { 'Official archive inspected; latest release and motherboard model compatibility not established by this audit.' }
    ListExitCode=$listExit; ExtractExitCode=$extractExit; ScriptFiles=$scripts.Count; SectionsTruncated=$truncated
    RelevantFiles=@($list | Where-Object { $_ -match '(?i)SDK|\.msix|\.appx|\.msi|\.exe|\.sys|\.iss|driver|Norton|McAfee|unsupported|error|failed|Inno Setup' } | Select-Object -First 70)
    Sections=$sections
    FileList=$list
    BaseSetupScript=@(foreach ($candidate in @((Join-Path $extractDir '{app}\setup.ps1'),(Join-Path $extractDir 'setup.ps1'))) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $file=Get-Item -LiteralPath $candidate
            if ($file.Length -le 32768) { [IO.File]::ReadAllText($candidate) } else { 'Script exceeds static inspection size limit; automatic installation remains unconfirmed.' }
        }
    })
}
$report | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $OutputDirectory 'inspection.json') -Encoding UTF8
Write-MbxEvidence -Kind 'utility_inspection' -Data $report
if ($listExit -ne 0 -or $extractExit -ne 0 -or $scripts.Count -ne 1 -or $truncated) {
    throw 'Inspection statique incomplete : verifier codes de liste/extraction, presence du script et troncature dans le rapport ; aucun installateur execute.'
}
