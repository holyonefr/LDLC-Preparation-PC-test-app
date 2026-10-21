#requires -Version 5.1
[CmdletBinding()]
param([string]$GpuModulePath='',[switch]$Historical,[string]$ReportPath='')
$ErrorActionPreference='Stop'
trap { Write-Host ('::error title=AMD regression failure::'+$_.Exception.Message.Replace('%','%25').Replace("`r",'%0D').Replace("`n",'%0A')+'; '+$_.ScriptStackTrace.Replace("`r",'%0D').Replace("`n",'%0A')); throw }

# Windows PowerShell 5.1 -File does not populate PSScriptRoot during advanced parameter defaults.
if(-not $GpuModulePath){$GpuModulePath=Join-Path (Split-Path -Parent $PSScriptRoot) 'modules/60.Gpu.ps1'}
. $GpuModulePath
$cases=New-Object 'Collections.Generic.List[object]';$script:checks=0
function Assert($v,$m){$script:checks++;if(-not $v){throw $m}}
# Baseline cases isolate the optional fallback; its own suite covers both methods.
function Invoke-LDLCAmdChocolateyFallback { throw 'Chocolatey fallback unavailable in isolated baseline scenario' }
function Stop-IfRequested {}
function Test-LDLCStopRequestError($ErrorRecord){return $false}
function Write-Step($Text){}
function Write-ProgressFile($Percent,$Text){}
function Write-Ok($Text){$script:ok+=[string]$Text}
function Write-Warn($Text){$script:warn+=[string]$Text}
function Write-Err($Text){$script:errors+=[string]$Text}
function Get-Date {return ([datetime]'2026-01-01').AddSeconds($script:elapsed)}
function Start-Sleep {param($Seconds,$Milliseconds)$script:elapsed+=[double]$Seconds+[double]$Milliseconds/1000}
function Clear-LDLCDetectionCaches {}
function Ensure-LDLCGpuDesktopShortcut($Vendor){$script:shortcuts++}
function Get-ItemProperty {param($LiteralPath)throw 'Isolated registry'}
function Get-LDLCGpuAdapters {return @([pscustomobject]@{Name='AMD Radeon';PNPDeviceID='PCI\VEN_1002&DEV_ABCD';ConfigManagerErrorCode=0})}
function Get-LDLCGpuHardwareRecords($ClassName){
 if($ClassName -eq 'Win32_PnPSignedDriver'){return [pscustomobject]@{DeviceID='PCI\VEN_1002&DEV_ABCD';DeviceClass='DISPLAY';IsSigned=$true;DriverProviderName='Advanced Micro Devices';InfName='oem12.inf';DriverVersion=$script:driver}}
 throw 'Unexpected host hardware access'
}
function Get-LDLCGpuComputerFormFactor {return [pscustomobject]@{Known=$true;Portable=$script:laptop;Reason='simulated form factor'}}
function Get-LDLCAmdSoftwareInstallation {param([switch]$Refresh)return [pscustomobject]@{ExePath='AMDSoftware.exe';DisplayVersion=$script:software}}
function Resolve-LDLCAmdGpuOfficialSource {
 $script:resolutions++
 if($script:offline){throw 'simulated official source unavailable'}
 return [pscustomobject]@{Version='99.10.1';PageUrl='https://www.amd.com/en/support/download/drivers.html';Url='https://drivers.amd.com/drivers/amd-software-adrenalin-edition-99.10.1-minimalsetup-990101_web.exe';FileName='amd-software-adrenalin-edition-99.10.1-minimalsetup-990101_web.exe'}
}
function Resolve-LDLCAmdGpuFullOfficialSources($AutoDetectSource){
 return [pscustomobject]@{Version='99.10.1';PageUrl='https://www.amd.com/en/resources/support-articles/release-notes/RN-RAD-WIN-99-10-1.html';Url='https://drivers.amd.com/drivers/whql-amd-software-adrenalin-edition-99.10.1-win10-win11.exe';FileName='whql-amd-software-adrenalin-edition-99.10.1-win10-win11.exe';IsFullPackage=$true}
}
function Get-LDLCAmdAdrenalinInstallerDefinition {return @{MinBytes=64;DownloadTimeoutSeconds=1;ValidationTimeoutSeconds=2}}
function Invoke-WebRequest {param($Uri,$Headers,$OutFile,$TimeoutSec,[switch]$UseBasicParsing)
 $script:downloads++;$script:paths+= $OutFile
 $bytes=New-Object byte[] 128;$bytes[0]=0x4d;$bytes[1]=0x5a;$bytes[0x3c]=0x40;$bytes[0x40]=0x50;$bytes[0x41]=0x45
 [IO.File]::WriteAllBytes($OutFile,$bytes)
 if($script:interrupted){throw 'simulated interrupted download'}
}
function Get-AuthenticodeSignature {param($LiteralPath)return [pscustomobject]@{Status=$(if($script:badSignature){'HashMismatch'}else{'Valid'});SignerCertificate=[pscustomobject]@{Subject='CN=Advanced Micro Devices, O=Advanced Micro Devices'}}}
function Expand-LDLCAmdPackageMetadata {param($Path,$Destination)
 [void][IO.Directory]::CreateDirectory($Destination)
 $id=if($script:wrongInf){'DEAD'}else{'ABCD'}
 [IO.File]::WriteAllText((Join-Path $Destination 'amd.inf'),"[Version]`nClass=DISPLAY`nDriverVer=10/20/2026,32.0.2.5`n[Models.NTamd64]`n%AMD%=Install,PCI\VEN_1002&DEV_$id`n")
}
function Invoke-LDLCAmdGpuInstaller($Path,$Installer){
 $script:launches++
 if($script:installerError){throw 'Installation AMD en echec, code 1603.'}
 if($script:updateDriver){$script:driver='32.0.2.5'}
 if($script:updateSoftware){$script:software='99.10.1'}
 if($script:reboot){$script:PendingReboot=$true;return 3010}
 return 0
}
foreach($name in @('no-op-old','update-both','application-only','driver-only','already-current','wrong-device','signature-error','installer-1603','reboot-incomplete','source-offline','download-interrupted','newer-driver-older-app','newer-app-older-driver','laptop')){
 $script:elapsed=0;$script:ok=@();$script:warn=@();$script:errors=@();$script:shortcuts=0;$script:downloads=0;$script:launches=0;$script:resolutions=0;$script:paths=@()
 $script:driver='31.0.1.2';$script:software='20.1.1';$script:laptop=$false;$script:offline=$false;$script:interrupted=$false;$script:badSignature=$false;$script:wrongInf=$false;$script:installerError=$false;$script:reboot=$false;$script:PendingReboot=$false;$script:updateDriver=$false;$script:updateSoftware=$false
 $expected='error'
 switch($name){
  'update-both' {$script:updateDriver=$true;$script:updateSoftware=$true;$expected='success'}
  'application-only' {$script:updateSoftware=$true}
  'driver-only' {$script:updateDriver=$true}
  'already-current' {$script:driver='32.0.2.5';$script:software='99.10.1';$expected='success'}
  'wrong-device' {$script:wrongInf=$true;$script:updateDriver=$true;$script:updateSoftware=$true}
  'signature-error' {$script:badSignature=$true}
  'installer-1603' {$script:installerError=$true}
  'reboot-incomplete' {$script:reboot=$true;$expected='reboot_pending'}
  'source-offline' {$script:offline=$true}
  'download-interrupted' {$script:interrupted=$true}
  'newer-driver-older-app' {$script:driver='33.0.0.0'}
  'newer-app-older-driver' {$script:software='99.11.1'}
  'laptop' {$script:laptop=$true;$expected='skipped'}
 }
 if($Historical -and $name -in @('no-op-old','application-only','driver-only','wrong-device','reboot-incomplete','newer-driver-older-app','newer-app-older-driver')){$expected='success'}
 Install-LDLCAmdStack
 $actual=if($script:errors.Count){'error'}elseif($script:warn.Count -and $script:PendingReboot){'reboot_pending'}elseif($script:ok.Count){'success'}else{'skipped'}
 Assert ($actual -eq $expected) ($name+': expected '+$expected+', observed '+$actual+'; '+($script:errors -join ';'))
 if($actual -in @('error','reboot_pending','skipped')){Assert ($script:shortcuts -eq 0 -and -not ($script:ok -match 'Adrenalin.*confirme|versions cibles.*atteintes')) ($name+': false success')}
 foreach($p in $script:paths){Assert (-not (Test-Path -LiteralPath $p)) ($name+': partial installer retained')}
 if($name -eq 'laptop'){Assert ($script:downloads -eq 0 -and $script:resolutions -eq 0) 'Laptop network request'}
 if(-not $Historical -and $name -eq 'already-current'){Assert ($script:downloads -eq 1 -and $script:launches -eq 0) 'Current versions must be checked online without reinstall/downgrade'}
 if(-not $Historical -and $name -in @('wrong-device','newer-driver-older-app','newer-app-older-driver')){Assert ($script:launches -eq 0) 'Incompatible INF must block before installation'}
 $cases.Add(@{Scenario=$name;Expected=$expected;Observed=$actual;Downloads=$script:downloads;InstallerCalls=$script:launches;Shortcuts=$script:shortcuts})
}
$report=@{Historical=[bool]$Historical;Cases=@($cases.ToArray());Assertions=$script:checks;Failures=0;Scope='Same scenarios against actual module; HTTP, SMBIOS, signature and hardware installation simulated; real isolated PE/INF files and cleanup.';RealDriverInstalled=$false}
if($ReportPath){[void](New-Item -ItemType Directory -Path (Split-Path -Parent $ReportPath) -Force);$report|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $ReportPath -Encoding UTF8}
Write-Host ('::notice title=AMD before after regressions::'+($report|ConvertTo-Json -Depth 8 -Compress))
