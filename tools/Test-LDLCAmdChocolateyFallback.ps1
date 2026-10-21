#requires -Version 5.1
[CmdletBinding()]
param([string]$ReportPath='')
$ErrorActionPreference='Stop'
trap {Write-Host ('::error title=AMD Chocolatey fallback tests::'+$_.Exception.Message+'; '+$_.ScriptStackTrace.Replace("`r",'%0D').Replace("`n",'%0A'));throw}
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'modules/60.Gpu.ps1')
$script:checks=0;$cases=New-Object 'Collections.Generic.List[object]'
function Assert($v,$m){$script:checks++;if(-not $v){throw $m}}
function Stop-IfRequested {if($script:cancel){throw 'LDLC_STOP_REQUESTED'}}
function Test-LDLCStopRequestError($ErrorRecord){return $ErrorRecord.Exception.Message -eq 'LDLC_STOP_REQUESTED'}
function Write-Step($Text){}
function Write-ProgressFile($Percent,$Text){}
function Write-Ok($Text){$script:ok+=[string]$Text}
function Write-Warn($Text){$script:warn+=[string]$Text}
function Write-Err($Text){$script:errors+=[string]$Text}
function Ensure-LDLCGpuDesktopShortcut($Vendor){$script:shortcuts++}
function Get-Date {return ([datetime]'2026-01-01').AddSeconds($script:elapsed)}
function Start-Sleep {param($Seconds,$Milliseconds)$script:elapsed+=[double]$Seconds+[double]$Milliseconds/1000}
function Clear-LDLCDetectionCaches {}
function Get-ItemProperty {param($LiteralPath)throw 'Isolated registry'}
function Get-Command {
 [CmdletBinding()]param([string]$Name)
 if($Name -eq 'choco.exe'){
  if($script:missingChoco){return $null}
  return [pscustomobject]@{Source='C:\Fixture\choco.exe'}
 }
 return Microsoft.PowerShell.Core\Get-Command -Name $Name -ErrorAction SilentlyContinue
}
function Get-LDLCGpuAdapters {
 if($script:noAmd){return @()}
 return [pscustomobject]@{Name='AMD fixture';PNPDeviceID='PCI\VEN_1002&DEV_ABCD';ConfigManagerErrorCode=0}
}
function Get-LDLCGpuComputerFormFactor {return [pscustomobject]@{Known=(-not $script:unknown);Portable=$script:laptop;Reason='fixture SMBIOS'}}
function Get-LDLCGpuHardwareRecords($ClassName){
 if($ClassName -eq 'Win32_PnPSignedDriver'){return [pscustomobject]@{DeviceID='PCI\VEN_1002&DEV_ABCD';DeviceClass='DISPLAY';IsSigned=$true;DriverProviderName='Advanced Micro Devices';InfName='oem1.inf';DriverVersion=$script:driver}}
 throw 'Unexpected host hardware query'
}
function Get-LDLCAmdSoftwareInstallation {param([switch]$Refresh)return [pscustomobject]@{ExePath='C:\Fixture\AMDSoftware.exe';DisplayVersion=$script:software}}
function Resolve-LDLCAmdGpuOfficialSource {
 $script:resolutions++
 if($script:offline){throw 'official discovery unavailable'}
 return [pscustomobject]@{Version='99.10.1';PageUrl='https://www.amd.com/en/support/download/drivers.html'}
}
function Resolve-LDLCAmdGpuFullOfficialSources($AutoDetectSource){return $script:source}
function Get-LDLCAmdAdrenalinInstallerDefinition {return @{MinBytes=64;DownloadTimeoutSeconds=1;ValidationTimeoutSeconds=2;TimeoutSeconds=20;PostInstallSettleSeconds=2;ExeArguments=@('-install')}}
function Get-AuthenticodeSignature {param($LiteralPath)return [pscustomobject]@{Status=$(if($script:badSignature){'HashMismatch'}else{'Valid'});SignerCertificate=[pscustomobject]@{Subject='CN=Advanced Micro Devices, O=Advanced Micro Devices'}}}
function Expand-LDLCAmdPackageMetadata {param($Path,$Destination)
 [void][IO.Directory]::CreateDirectory($Destination)
 $id=if($script:wrongInf){'DEAD'}else{'ABCD'}
 [IO.File]::WriteAllText((Join-Path $Destination 'amd.inf'),"[Version]`nClass=DISPLAY`nDriverVer=01/01/2026,32.0.2.5`n[Models.NTamd64]`n%AMD%=Install,PCI\VEN_1002&DEV_$id`n")
}
function Invoke-WebRequest {
 param($Uri,$Headers,$OutFile,$TimeoutSec,[switch]$UseBasicParsing)
 $script:paths+= $OutFile
 if([string]$Uri -like 'https://community.chocolatey.org/*'){
  $script:packageReads++
  Assert ([string]$Uri -eq 'https://community.chocolatey.org/api/v2/package/amd-software-adrenalin-edition/99.10.1') 'Must request the exact current release, never catalog latest/old cached versions'
  if($script:packageAbsent){throw 'HTTP 404: only 99.9.1 is published'}
  if($script:interruptedPackage){[IO.File]::WriteAllText($OutFile,'partial ZIP');throw 'interrupted nupkg download'}
  if($script:corruptPackage){[IO.File]::WriteAllText($OutFile,'not a ZIP');return}
  $zip=[IO.Compression.ZipFile]::Open($OutFile,[IO.Compression.ZipArchiveMode]::Create)
  try{
   $entry=$zip.CreateEntry('tools/chocolateyinstall.ps1');$w=New-Object IO.StreamWriter($entry.Open())
   $url=if($script:wrongUrl){'https://example.invalid/old.exe'}else{$script:source.Url}
   $sha=if($script:wrongHash){'0'*64}else{$script:packageHash}
   $text="`$packageArgs = @{`n url64 = '$url'`n checksum64 = '$sha'`n checksumType64 = 'sha256'`n silentArgs = '-install'`n}`nInstall-ChocolateyPackage @packageArgs"
   if($script:missingChecksum){$text=$text -replace '(?m)^ checksum64.*\r?\n',''}
   if($script:wrongArgs){$text=$text -replace "silentArgs = '-install'","silentArgs = '-uninstall'"}
   if($script:duplicateUrl){$text+="`n url64 = '$url'"}
   try{$w.Write($text)}finally{$w.Dispose()}
  }finally{$zip.Dispose()}
  return
 }
 $script:downloads++
 $bytes=New-Object byte[] 128;$bytes[0]=0x4d;$bytes[1]=0x5a;$bytes[0x3c]=0x40;$bytes[0x40]=0x50;$bytes[0x41]=0x45
 [IO.File]::WriteAllBytes($OutFile,$bytes)
 $script:packageHash=(Get-FileHash -LiteralPath $OutFile -Algorithm SHA256).Hash
 if($script:interrupted){throw 'interrupted official download'}
}
function Invoke-LDLCAmdGpuInstaller($Path,$Installer){
 if($Path -eq 'C:\Fixture\choco.exe'){
  $script:chocoCalls++
  $script:arguments=$Installer.ExeArguments
  Assert ($script:arguments[0] -eq 'upgrade' -and $script:arguments -contains '--force' -and $script:arguments -contains '--version=99.10.1') 'Fallback must retry exact version even if Chocolatey already marks it installed'
  Assert ($script:arguments -notcontains '--allow-downgrade' -and $script:arguments -notcontains '--ignore-checksums' -and $script:arguments -contains '--ignore-dependencies') 'No checksum bypass/downgrade/optional dependencies'
  Assert (@($script:arguments|Where-Object {$_ -like '--source="*chocolatey-feed"'}).Count -eq 1) 'Use the inspected pinned local nupkg feed, including spaces'
  if($script:chocoError){throw 'Chocolatey code 1: AMD installer code 1603'}
  if($script:chocoTimeout){$e=New-Object InvalidOperationException 'Chocolatey/AMD installer still active';$e.Data['LDLCAmdInstallerStillActive']=$true;throw $e}
  if($script:chocoChanges){$script:software='99.10.1';$script:driver='32.0.2.5'}
  if($script:chocoReboot){$script:PendingReboot=$true;return 3010}
  return 0
 }
 $script:officialCalls++
 if($script:cancelAfterOfficial){$script:cancel=$true;throw 'LDLC_STOP_REQUESTED'}
 if($script:active){$e=New-Object InvalidOperationException 'Official installer still active';$e.Data['LDLCAmdInstallerStillActive']=$true;throw $e}
 if($script:postNewer){$script:driver='33.0.0.0'}
 if($script:officialError){throw 'Official AMD code 1603'}
 if($script:officialChanges){$script:software='99.10.1';$script:driver='32.0.2.5'}
 if($script:officialReboot){$script:PendingReboot=$true;return 3010}
 return 0
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$script:source=[pscustomobject]@{Version='99.10.1';Url='https://drivers.amd.com/drivers/whql-amd-software-adrenalin-edition-99.10.1-win11-c.exe';PageUrl='https://www.amd.com/en/resources/support-articles/release-notes/RN-RAD-WIN-99-10-1.html';FileName='whql-amd-software-adrenalin-edition-99.10.1-win11-c.exe';IsFullPackage=$true}
foreach($name in @('official-success','installer-failure-choco-success','no-op-choco-success','choco-stale-99.9.1','missing-choco','wrong-url','wrong-sha256','wrong-arguments','duplicate-url','missing-checksum','corrupt-package','interrupted-package','choco-error-1603','choco-no-op','choco-reboot','choco-timeout','official-still-active','official-reboot','cancelled','newer-driver','newer-application','newer-driver-after-partial','source-offline','download-interrupted','bad-signature','wrong-device','laptop','unknown-form-factor','no-amd')){
 foreach($flag in @('missingChoco','noAmd','unknown','laptop','offline','badSignature','wrongInf','interrupted','packageAbsent','interruptedPackage','corruptPackage','wrongUrl','wrongHash','missingChecksum','wrongArgs','duplicateUrl','chocoError','chocoTimeout','chocoReboot','cancel','cancelAfterOfficial','active','postNewer','officialChanges','officialReboot')){Set-Variable -Name $flag -Value $false -Scope Script}
 $script:officialError=$true;$script:chocoChanges=$true;$script:elapsed=0;$script:officialCalls=0;$script:chocoCalls=0;$script:packageReads=0;$script:downloads=0;$script:resolutions=0;$script:paths=@();$script:arguments=@();$script:software='20.1.1';$script:driver='31.0.1.0';$script:ok=@();$script:errors=@();$script:warn=@();$script:shortcuts=0;$script:PendingReboot=$false
 $expected='error';$expectedPackages=1;$expectedChoco=0
 switch($name){
  'official-success' {$script:officialError=$false;$script:officialChanges=$true;$expected='success';$expectedPackages=0}
  'installer-failure-choco-success' {$expected='success';$expectedChoco=1}
  'no-op-choco-success' {$script:officialError=$false;$expected='success';$expectedChoco=1}
  'choco-stale-99.9.1' {$script:packageAbsent=$true}
  'missing-choco' {$script:missingChoco=$true;$expectedPackages=0}
  'wrong-url' {$script:wrongUrl=$true}
  'wrong-sha256' {$script:wrongHash=$true}
  'wrong-arguments' {$script:wrongArgs=$true}
  'duplicate-url' {$script:duplicateUrl=$true}
  'missing-checksum' {$script:missingChecksum=$true}
  'corrupt-package' {$script:corruptPackage=$true}
  'interrupted-package' {$script:interruptedPackage=$true}
  'choco-error-1603' {$script:chocoError=$true;$expectedChoco=1}
  'choco-no-op' {$script:chocoChanges=$false;$expectedChoco=1}
  'choco-reboot' {$script:chocoChanges=$false;$script:chocoReboot=$true;$expected='reboot_pending';$expectedChoco=1}
  'choco-timeout' {$script:chocoTimeout=$true;$expectedChoco=1}
  'official-still-active' {$script:active=$true;$expectedPackages=0}
  'official-reboot' {$script:officialError=$false;$script:officialReboot=$true;$expected='reboot_pending';$expectedPackages=0}
  'cancelled' {$script:cancelAfterOfficial=$true;$expected='cancelled';$expectedPackages=0}
  'newer-driver' {$script:driver='33.0.0.0';$expectedPackages=0}
  'newer-application' {$script:software='99.11.1';$expectedPackages=0}
  'newer-driver-after-partial' {$script:postNewer=$true;$expectedPackages=0}
  'source-offline' {$script:offline=$true;$expectedPackages=0}
  'download-interrupted' {$script:interrupted=$true;$expectedPackages=0}
  'bad-signature' {$script:badSignature=$true;$expectedPackages=0}
  'wrong-device' {$script:wrongInf=$true;$expectedPackages=0}
  'laptop' {$script:laptop=$true;$expected='skipped';$expectedPackages=0}
  'unknown-form-factor' {$script:unknown=$true;$expected='skipped';$expectedPackages=0}
  'no-amd' {$script:noAmd=$true;$expected='skipped';$expectedPackages=0}
 }
 $cancelled=$false
 try{Install-LDLCAmdStack}catch{if(Test-LDLCStopRequestError $_){$cancelled=$true}else{throw}}
 $observed=if($cancelled){'cancelled'}elseif($script:errors.Count){'error'}elseif($script:warn.Count -and $script:PendingReboot){'reboot_pending'}elseif($script:ok.Count){'success'}else{'skipped'}
 Assert ($observed -eq $expected) ($name+': expected '+$expected+', got '+$observed+'; '+($script:errors -join ';'))
 Assert ($script:packageReads -eq $expectedPackages -and $script:chocoCalls -eq $expectedChoco) ($name+': invalid fallback calls '+$script:packageReads+'/'+$script:chocoCalls+'; '+($script:errors -join ';'))
 Assert ($script:shortcuts -eq $(if($expected -eq 'success'){1}else{0})) ($name+': false shortcut/success')
 foreach($p in $script:paths){Assert (-not (Test-Path -LiteralPath $p)) ($name+': partial package retained')}
 if($expected -eq 'skipped'){Assert ($script:downloads -eq 0 -and $script:resolutions -eq 0) ($name+': network request before exclusion')}
 if($name -eq 'choco-stale-99.9.1'){Assert (($script:errors -join ';') -match 'Aucune ancienne version') 'Old 99.9.1 must not be installed instead of 99.10.1'}
 $cases.Add(@{Scenario=$name;Expected=$expected;Observed=$observed;OfficialCalls=$script:officialCalls;ChocolateyCalls=$script:chocoCalls;PackageReads=$script:packageReads})
}
$report=@{Success=$true;Failures=0;Assertions=$script:checks;Cases=@($cases.ToArray());HardwareInstallerExecuted=$false;ChocolateyInstallExecuted=$false;Simulated=$true;Scope='Real runtime module, ZIP/PE/INF files, SHA256 and cleanup; HTTP, registry, SMBIOS, signatures and installer processes simulated.'}
if($ReportPath){[void](New-Item -ItemType Directory -Path (Split-Path -Parent $ReportPath) -Force);$report|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $ReportPath -Encoding UTF8}
Write-Host ('::notice title=AMD Chocolatey fallback scenarios::'+($report|ConvertTo-Json -Depth 8 -Compress))
