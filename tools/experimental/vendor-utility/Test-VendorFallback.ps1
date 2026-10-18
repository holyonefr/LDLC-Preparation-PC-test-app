#requires -Version 5.1
param([switch]$Native,[string]$OutputDirectory='artifacts/vendor-fallback')
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'VendorUtility.psm1') -Force
$module=Get-Module VendorUtility
$root=Join-Path ([IO.Path]::GetTempPath()) ('Vendor-Fallback-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $root)
$cases=New-Object 'Collections.Generic.List[object]';$script:Checks=0
function Assert($v,$m){$script:Checks++;if(-not $v){throw $m}}
function Case($n,[scriptblock]$b){try{&$b;$cases.Add(@{Name=$n;Result='passed'})}catch{$cases.Add(@{Name=$n;Result='failed';Error=$_.Exception.Message});Write-Warning ($n+': '+$_.Exception.Message)}}
&$module {
 $script:FallbackFixture=@{Vendor='MSI';Failure='HTTP 503 sur la source officielle.';Portable=$false;Downloads=0;InstallerCalls=0;Desktop=''}
 function script:Get-VutHardware {
  return [pscustomobject]@{BoardManufacturer=$script:FallbackFixture.Vendor;BoardModel='TEST MODEL';ComputerManufacturer='System manufacturer';ComputerModel='System Product Name';Portable=$script:FallbackFixture.Portable;ClientWindows=$true;Is64Bit=$true;WindowsCaption='Microsoft Windows 11 Pro'}
 }
 function script:Get-VutInstalledApplication {return $null}
 function script:Get-VutPackage {$script:FallbackFixture.Downloads++;throw $script:FallbackFixture.Failure}
 function script:Invoke-VutInstallerProcess {$script:FallbackFixture.InstallerCalls++;throw 'Forbidden installer execution'}
}
function State {&$module {$script:FallbackFixture}}
$originalDesktop='';$restored=$false;$com=$null
try {
 if($Native){
  if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){throw 'Native requires Windows'}
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class VutFallbackKnownFolder {
 [DllImport("shell32.dll", CharSet=CharSet.Unicode)]
 public static extern int SHSetKnownFolderPath(ref Guid id,uint flags,IntPtr token,string path);
}
'@
  $id=[guid]'B4BFCC3A-DB2C-424C-B029-7FE99A87C641'
  $originalDesktop=[Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory)
  $com=New-Object -ComObject WScript.Shell
 }else{&$module {function script:Get-VutDesktop {return $script:FallbackFixture.Desktop}}}
 foreach($mode in @('Bureau','OneDrive - Fixture/Bureau')){
  $desktop=Join-Path $root $mode;[void](New-Item -ItemType Directory -Path $desktop -Force)
  (State).Desktop=$desktop
  if($Native){
   $hr=[VutFallbackKnownFolder]::SHSetKnownFolderPath([ref]$id,0,[IntPtr]::Zero,$desktop)
   if($hr -ne 0){throw "Desktop redirect failed: $hr"}
  }
  foreach($vendor in @('MSI','ASUS','GIGABYTE','ASRock')){
   (State).Vendor=$vendor
   Case ($vendor+' official fallback on '+$mode){
    $r=Invoke-VendorUtility
    Assert ($r.Status -eq 'manual_required' -and $r.FallbackUsed -and (Test-Path -LiteralPath $r.SupportShortcut)) 'Repli absent.'
    Assert ((Split-Path $r.SupportShortcut) -eq $desktop) 'Mauvais Bureau.'
    Assert (-not $r.Installed -and -not $r.ApplicationVerified -and -not $r.InstallerPath -and -not $r.InstallerShortcut -and -not $r.InstallerVersion) 'Faux succes installateur/installation.'
    Assert ($r.DownloadFailure -match '503' -and $r.Reason -match 'Repli manuel' -and (State).InstallerCalls -eq 0) 'Cause perdue ou execution.'
    $content=[IO.File]::ReadAllText($r.SupportShortcut)
    Assert ($content -match ('(?m)^URL='+[regex]::Escape($r.OfficialPage)+'\r?$')) 'Mauvaise page officielle.'
    if($Native){Assert ($com.CreateShortcut($r.SupportShortcut).TargetPath -ceq $r.OfficialPage) 'Windows ne reconnait pas la cible Internet.'}
    $again=Invoke-VendorUtility
    Assert ($again.SupportShortcut -ceq $r.SupportShortcut -and -not $again.FallbackError) 'Repli non reutilisable.'
   }
   foreach($failure in @('Manifeste officiel invalide : format modifie','Signature numerique non valide','Telechargement interrompu : 10 octets recus','Delai de lecture depasse')){
    Case ($vendor+' fallback preserves '+$failure){
     (State).Failure=$failure;$r=Invoke-VendorUtility
     Assert ($r.FallbackUsed -and $r.DownloadFailure -ceq $failure -and -not $r.InstallerShortcut -and -not $r.Installed) 'Erreur masquee par un faux succes.'
    }
   }
   (State).Failure='HTTP 503 sur la source officielle.'
   Case ($vendor+' conflicting web shortcut is preserved'){
    $r=Invoke-VendorUtility;$p=$r.SupportShortcut
    [IO.File]::WriteAllText($p,"[InternetShortcut]`r`nURL=https://example.invalid/keep`r`n")
    $before=[IO.File]::ReadAllBytes($p);$r=Invoke-VendorUtility
    Assert (-not $r.FallbackUsed -and -not $r.SupportShortcut -and $r.FallbackError -match 'autre cible' -and $r.DownloadFailure -match '503') 'Conflit ignore ou cause perdue.'
    Assert ([Convert]::ToBase64String([IO.File]::ReadAllBytes($p)) -ceq [Convert]::ToBase64String($before)) 'Raccourci tiers ecrase.'
    Remove-Item -LiteralPath $p
   }
  }
  Case ('Laptop has no fallback, download or Desktop change on '+$mode){
   (State).Portable=$true;$count=(State).Downloads;$files=@(Get-ChildItem $desktop -File).Count
   try{$r=Invoke-VendorUtility;Assert (-not $r.SupportShortcut -and -not $r.FallbackUsed -and -not $r.Tool -and (State).Downloads -eq $count -and @(Get-ChildItem $desktop -File).Count -eq $files) 'Effet sur portable.'}finally{(State).Portable=$false}
  }
 }
 Case 'Plan does not create any fallback or request a download'{
  $count=(State).Downloads;$r=Invoke-VendorUtility -PlanOnly
  Assert ($r.Status -eq 'plan' -and -not $r.SupportShortcut -and (State).Downloads -eq $count) 'Effet dans plan.'
 }
 Case 'Untrusted fallback URL cannot create a shortcut'{
  $errorText='';try{&$module {$p=Get-VutProfile MSI;$p.OfficialPage='https://example.invalid/setup.exe';New-VutSupportShortcut $p}}catch{$errorText=$_.Exception.Message}
  Assert ($errorText -match 'officielle invalide') 'URL non officielle acceptee.'
 }
 Case 'Unavailable Desktop preserves original error and official page'{
  &$module {function script:Get-VutDesktop {throw 'Fixture Bureau inaccessible'}}
  $r=Invoke-VendorUtility
  Assert (-not $r.SupportShortcut -and -not $r.FallbackUsed -and $r.DownloadFailure -match '503' -and $r.FallbackError -match 'Bureau inaccessible' -and $r.Reason.Contains($r.OfficialPage)) 'Erreur Bureau masquee.'
 }
} finally {
 if($Native -and $originalDesktop){
  $hr=[VutFallbackKnownFolder]::SHSetKnownFolderPath([ref]$id,0,[IntPtr]::Zero,$originalDesktop)
  $restored=($hr -eq 0 -and [Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory) -eq $originalDesktop)
 }else{$restored=$true}
 if($com){[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($com)}
 if($restored){Remove-Item -LiteralPath $root -Recurse -Force}
}
Case 'Original Desktop restored after fallback tests'{Assert $restored 'Bureau initial non restaure.'}
[void](New-Item -ItemType Directory -Path $OutputDirectory -Force)
$report=@{Kind='vendor_fallback_tests';Cases=@($cases.ToArray());Assertions=$script:Checks;Failures=@($cases.ToArray()|Where-Object Result -eq failed).Count;NativeWindows=[bool]$Native;NetworkFailureSimulated=$true;ActualNetworkRequests=0;VendorInstallerExecuted=$false;Mode='real_url_files_with_simulated_vendor_failures';DesktopRestored=$restored}
$report|ConvertTo-Json -Depth 7|Set-Content (Join-Path $OutputDirectory 'vendor-fallback.json') -Encoding UTF8
Import-Module (Join-Path $PSScriptRoot '../motherboard/MotherboardExperiment.psm1') -Force
Write-MbxEvidence -Kind 'vendor_fallback_tests' -Data $report
if($report.Failures){throw "$($report.Failures) scenarios de repli en echec."}
Write-Host "$($cases.Count) scenarios / $script:Checks assertions reussis."
