#requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'modules/60.Gpu.ps1')
$script:checks=0
function Assert($v,$m){$script:checks++;if(-not $v){throw $m}}
function Reject([scriptblock]$Action,$Pattern){$msg='';try{&$Action|Out-Null}catch{$msg=$_.Exception.Message};Assert ($msg -match $Pattern) ('Expected '+$Pattern+', got '+$msg)}
function Get-ItemProperty {param($LiteralPath)return [pscustomobject]@{RadeonSoftwareVersion=$script:registryVersion}}
function Get-LDLCFileVersionText {param($Path)if($Path -eq $script:installedExe){return $script:installedFileVersion};return $script:packageFileVersion}
$meta=Join-Path ([IO.Path]::GetTempPath()) ('Preparation-AmdMetadata-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($meta)
try{
 $html='<a href="//drivers.amd.com/drivers/amd-software-adrenalin-edition-99.9.1-minimalsetup-990101_web.exe">Old</a><a href="https://drivers.amd.com/drivers/amd-software-adrenalin-edition-99.10.1-minimalsetup-990101_web.exe?a=1&amp;b=2">Latest</a>'
 $links=@(Get-LDLCAmdOfficialInstallerLinks -Html $html -PageUrl 'https://www.amd.com/en/support/download/drivers.html')
 Assert ($links.Count -eq 2 -and $links[1].Url -match 'a=1&b=2$') 'Protocol relative links and HTML encoding'
 $script:html=$html
 function Invoke-WebRequest {param($Uri,$Headers,[switch]$UseBasicParsing,$TimeoutSec)return [pscustomobject]@{Content=$script:html}}
 $latest=Resolve-LDLCAmdGpuOfficialSource
 Assert ($latest.Version -eq '99.10.1') 'Compare versions numerically: 99.10 > 99.9'
 foreach($bad in @('http://drivers.amd.com','https://drivers.amd.com.evil.test','https://drivers.amd.com@evil.test','https://drivers.amd.com:444','https://evil.test')){
  $badLink=$bad+'/amd-software-adrenalin-edition-99.10.1-minimalsetup-990101_web.exe'
  Assert (@(Get-LDLCAmdOfficialInstallerLinks -Html ('<a href="'+$badLink+'">Bad</a>') -PageUrl 'https://www.amd.com').Count -eq 0) ('Untrusted URL '+$bad)
 }
 $script:html='<a href="https://drivers.amd.com/drivers/whql-amd-software-adrenalin-edition-99.9.1-win10-win11.exe">Old</a><a href="//drivers.amd.com/drivers/whql-amd-software-adrenalin-edition-99.10.1-win10-win11.exe">Current</a>'
 $sources=@(Resolve-LDLCAmdGpuFullOfficialSources -AutoDetectSource $latest)
 Assert ($sources.Count -eq 1 -and $sources[0].Version -eq '99.10.1' -and $sources[0].IsFullPackage) 'Select full current release, never old package/bootstrap'
 $script:html=$script:html.Replace('99.10.1','99.8.1')
 Reject {Resolve-LDLCAmdGpuFullOfficialSources -AutoDetectSource $latest} 'Aucun ancien package'
 $id='PCI\VEN_1002&DEV_ABCD&SUBSYS_12345678&REV_01\4&INSTANCE'
 foreach($hw in @('PCI\VEN_1002&DEV_ABCD','PCI\VEN_1002&DEV_ABCD&SUBSYS_12345678','PCI\VEN_1002&DEV_ABCD&REV_01','PCI\VEN_1002&DEV_ABCD&REV_01&SUBSYS_12345678')){Assert (Test-LDLCAmdInfHardwareMatch $hw $id) 'Hardware ID must match every specified attribute regardless of order'}
 foreach($hw in @('PCI\VEN_1002&DEV_DEAD','PCI\VEN_1002&DEV_ABCD&SUBSYS_00000000','PCI\VEN_1002&DEV_ABCD&REV_02','PCI\VEN_10DE&DEV_ABCD','PCI\VEN_1002&DEV_ABCD&UNKNOWN_1')){Assert (-not (Test-LDLCAmdInfHardwareMatch $hw $id)) 'No wrong device/subsystem/revision/vendor allowed'}
 function Inf($Name,$Version,$Section,$Id='PCI\VEN_1002&DEV_ABCD',$Class='Display'){
  [IO.File]::WriteAllText((Join-Path $meta $Name),"[Version]`nClass=$Class`nDriverVer=10/20/2026,$Version`n[$Section]`n%AMD%=Install,$Id`n")
 }
 Inf old.inf '32.0.1.9' 'AMD.NTamd64'
 Inf current.inf '32.0.1.10' 'AMD.NTamd64'
 Inf x86.inf '99.0.0.0' 'AMD.NTx86'
 Inf arm.inf '99.0.0.0' 'AMD.NTarm64'
 Inf newerwindows.inf '32.0.2.0' 'AMD.NTamd64.10.0...22000'
 Inf chipset.inf '99.0.0.0' 'AMD.NTamd64' 'PCI\VEN_1002&DEV_ABCD' 'System'
 $t=@(Get-LDLCAmdPackageDriverTargets -MetadataPath $meta -PnpDeviceIds @($id) -WindowsBuild 19045)
 Assert ($t.Count -eq 1 -and $t[0].DriverVersion -eq '32.0.1.10') 'Windows 10 selects correct x64 INF numerically; exclude ARM/x86/chipset/new Windows'
 $t=@(Get-LDLCAmdPackageDriverTargets -MetadataPath $meta -PnpDeviceIds @($id) -WindowsBuild 26100)
 Assert ($t[0].DriverVersion -eq '32.0.2.0') 'Windows 11 models decoration accepted'
 Reject {Get-LDLCAmdPackageDriverTargets -MetadataPath $meta -PnpDeviceIds @($id,'PCI\VEN_1002&DEV_DEAD') -WindowsBuild 26100} 'non pris en charge'
 # Comments and strings are not device declarations.
 [IO.File]::WriteAllText((Join-Path $meta 'comment.inf'),"[Version]`nClass=Display`nDriverVer=10/20/2026,99.0.0.0`n[AMD.NTamd64]`n;device=Install,PCI\VEN_1002&DEV_DEAD`n[Strings]`nx=Install,PCI\VEN_1002&DEV_DEAD`n")
 Reject {Get-LDLCAmdPackageDriverTargets -MetadataPath $meta -PnpDeviceIds @('PCI\VEN_1002&DEV_DEAD')} 'non pris en charge'
 $script:registryVersion='';$script:installedFileVersion='';$script:packageFileVersion=''
 $script:installedExe=Join-Path $meta 'installed/AMDSoftware.exe'
 $soft=[pscustomobject]@{ExePath=$script:installedExe;DisplayVersion='99.9.1'}
 Assert (-not (Test-LDLCAmdSoftwareTargetReady $soft '99.10.1' $meta)) 'Old Adrenalin is not current'
 foreach($version in @('99.10.1','99.11.1')){$soft.DisplayVersion=$version;Assert (Test-LDLCAmdSoftwareTargetReady $soft '99.10.1' $meta) 'Current/newer marketing version accepted'}
 foreach($version in @('32.0.23031.1000','unknown','99.10.1.9')){$soft.DisplayVersion=$version;Assert (-not (Test-LDLCAmdSoftwareTargetReady $soft '99.10.1' $meta)) 'Never compare Windows driver build to marketing release'}
 $script:registryVersion='99.10.1';Assert (Test-LDLCAmdSoftwareTargetReady $soft '99.10.1' $meta) 'Explicit AMD registry release can verify marketing version'
 $script:registryVersion='';$script:installedFileVersion='10.2.1.8';$script:packageFileVersion='10.2.1.9'
 [IO.File]::WriteAllText((Join-Path $meta 'AMDSoftware.exe'),'isolated metadata fixture')
 Assert (-not (Test-LDLCAmdSoftwareTargetReady $soft '99.10.1' $meta)) 'Installed UI older than package must fail even with existing app'
 $script:installedFileVersion='10.2.1.9';Assert (Test-LDLCAmdSoftwareTargetReady $soft '99.10.1' $meta) 'Same executable version scale accepted'
 Write-Host ('::notice title=AMD package metadata tests::'+(@{Assertions=$script:checks;Failures=0;RealNetwork=$false;HardwareInstallExecuted=$false;Scope='Official link, version, PCI ID, INF Windows architecture/build and Adrenalin freshness fixtures'}|ConvertTo-Json -Compress))
}finally{Remove-Item -LiteralPath $meta -Recurse -Force}
