#requires -Version 5.1
[CmdletBinding()]
param([switch]$Live,[ValidateSet('ASRock','MSI','ASUS','GIGABYTE')][string[]]$Vendors=@('ASRock'),[string]$RecordedGigabyteCatalogue,[string]$OutputDirectory=(Join-Path $PSScriptRoot 'reports/installer-shortcut'))
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
[void](New-Item -ItemType Directory -Path $OutputDirectory -Force)
$root=Join-Path $OutputDirectory ('fixtures-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $root)
$cases=New-Object 'System.Collections.Generic.List[object]'
$script:assertions=0
$script:liveEvidence=@()
function Assert($Value,[string]$Message) { $script:assertions++; if (-not $Value) { throw $Message } }
function Case([string]$Name,[scriptblock]$Body,[string]$Mode='simulation') {
    try { & $Body; $cases.Add([pscustomobject]@{Name=$Name;Mode=$Mode;Result='passed';Error=''}) }
    catch { $cases.Add([pscustomobject]@{Name=$Name;Mode=$Mode;Result='failed';Error=$_.Exception.Message}); Write-Warning ($Name+': '+$_.Exception.Message) }
}
Import-Module (Join-Path $PSScriptRoot 'VendorUtility.psm1') -Force
$module=Get-Module VendorUtility
& $module {
    function script:Get-VutInstallerStore { return $script:Fixture.Store }
    function script:Test-MbxSignedPayload {
        param($Path,$Signers)
        if ($script:Fixture.InvalidSignature) { throw 'Fixture : signature invalide' }
        return [pscustomobject]@{SHA256=(Get-FileHash -LiteralPath $Path).Hash;FileVersion=$script:Fixture.FileVersion}
    }
    function script:New-VutShortcut {
        param($Profile,$Application)
        $script:Fixture.ShortcutCalls++
        if ($script:Fixture.DesktopFailure) { throw 'Fixture : Bureau inaccessible' }
        $script:Fixture.LastTarget=$Application.Target; $script:Fixture.LastArguments=$Application.Arguments
        $script:Fixture.LastName=$Profile.Name
        return Join-Path $script:Fixture.Store ($Profile.Name+'.lnk')
    }
}
function State { & $module { $script:Fixture } }
function Reset-Fixture {
    $directory=Join-Path $root ([guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $directory)
    $source=Join-Path $directory 'source.exe'
    [IO.File]::WriteAllText($source,'INERT FIXTURE; NEVER EXECUTED')
    & $module {
        param($directory,$source)
        $script:Fixture=[pscustomobject]@{
            Store=(Join-Path $directory 'persistent-store');Source=$source;FileVersion='2.0.0.9'
            InvalidSignature=$false;DesktopFailure=$false;ShortcutCalls=0;LastTarget='';LastArguments='';LastName=''
            Package=[pscustomobject]@{Path=$source;Version='2.0.0.9';SHA256=(Get-FileHash -LiteralPath $source).Hash}
        }
    } $directory $source
}
function Prepare([string]$Vendor='ASRock') { & $module { param($v) New-VutInstallerShortcut -Profile (Get-VutProfile $v) -Package $script:Fixture.Package } $Vendor }
function Rejects([scriptblock]$Body,[string]$Pattern) {
    $message=''; try { $null=& $Body } catch { $message=$_.Exception.Message }
    Assert ($message -match $Pattern) ('Cause attendue absente : '+$message)
}
try {
    foreach ($vendor in @('ASRock','MSI','ASUS','GIGABYTE')) {
        Case ('Verified '+$vendor+' installer becomes a manual Desktop shortcut') {
            Reset-Fixture
            if ($vendor -eq 'GIGABYTE') { (State).Package | Add-Member -NotePropertyName Kind -NotePropertyValue 'gigabyte_core' }
            $r=Prepare $vendor
            Assert (Test-Path -LiteralPath $r.Path -PathType Leaf) 'Cible permanente absente.'
            Assert ((Get-FileHash -LiteralPath $r.Path).Hash -eq (State).Package.SHA256) 'Contenu copie different.'
            Assert ((State).LastTarget -eq $r.Path -and (State).LastArguments -ceq '') 'Raccourci avec cible ou arguments incorrects.'
            Assert ((State).LastName -like 'Installer *2.0.0.9' -and $r.Version -eq '2.0.0.9') 'Version/nom installateur absents.'
            Assert ((State).ShortcutCalls -eq 1) 'Raccourci absent.'
        }
    }
    Case 'Repeated preparation reuses the same stable installer target' {
        Reset-Fixture; $first=Prepare
        $other=Join-Path (Split-Path -Parent (State).Source) 'second-download.exe'
        Copy-Item -LiteralPath (State).Source -Destination $other
        (State).Package.Path=$other
        $second=Prepare
        Assert ($first.Path -ceq $second.Path -and $first.Shortcut -ceq $second.Shortcut) 'Doublon pour un meme paquet.'
        Assert (@(Get-ChildItem -LiteralPath (State).Store -Recurse -File -Filter '*.exe').Count -eq 1) 'Plusieurs copies permanentes du meme paquet.'
    }
    Case 'Installer target survives removal of the temporary download' {
        Reset-Fixture; $r=Prepare
        Remove-Item -LiteralPath (State).Source
        Assert (Test-Path -LiteralPath $r.Path -PathType Leaf) 'Cible depend du fichier temporaire.'
        Assert ((Get-FileHash -LiteralPath $r.Path).Hash -eq (State).Package.SHA256) 'Cible permanente invalide.'
    }
    Case 'Changed downloaded installer cannot receive a shortcut' {
        Reset-Fixture; [IO.File]::AppendAllText((State).Source,'changed')
        Rejects { Prepare } 'modifie'
        Assert ((State).ShortcutCalls -eq 0) 'Raccourci cree pour un fichier modifie.'
    }
    Case 'Invalid signature prevents any shortcut' {
        Reset-Fixture; (State).InvalidSignature=$true
        Rejects { Prepare } 'signature invalide'
        Assert ((State).ShortcutCalls -eq 0) 'Raccourci cree sans signature.'
    }
    Case 'Changed persistent installer is rejected without overwrite' {
        Reset-Fixture; $r=Prepare; [IO.File]::AppendAllText($r.Path,'changed cache')
        $changed=(Get-FileHash -LiteralPath $r.Path).Hash
        Rejects { Prepare } 'permanente.*non conforme'
        Assert ((Get-FileHash -LiteralPath $r.Path).Hash -eq $changed -and (State).ShortcutCalls -eq 1) 'Cache existant ecrase ou nouveau raccourci cree.'
    }
    Case 'Wrong file version is rejected even if the hash is known' {
        Reset-Fixture; (State).FileVersion='2.0.0.4'
        Rejects { Prepare } 'modifie'
        Assert ((State).ShortcutCalls -eq 0) 'Ancien fichier accepte.'
    }
    Case 'Invalid version or hash cannot form a cache path' {
        Reset-Fixture; (State).Package.Version='../outside'
        Rejects { Prepare } 'identite/version'
        Reset-Fixture; (State).Package.SHA256='../outside'
        Rejects { Prepare } 'identite/version'
    }
    Case 'GIGABYTE full bundle cannot be offered as a minimal installer shortcut' {
        Reset-Fixture
        Rejects { Prepare GIGABYTE } 'identite/version'
        Assert ((State).ShortcutCalls -eq 0) 'Bundle GCC facultatif propose comme installateur minimal.'
    }
    Case 'Inaccessible Desktop reports an explicit error' {
        Reset-Fixture; (State).DesktopFailure=$true
        Rejects { Prepare } 'Bureau inaccessible'
    }
} finally {
    Remove-Module VendorUtility
    Remove-Item -LiteralPath $root -Recurse -Force
}

if ($Live) {
    Import-Module (Join-Path $PSScriptRoot 'VendorUtility.psm1') -Force
    $module=Get-Module VendorUtility
    if (-not ('VutInstallerKnownFolder' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class VutInstallerKnownFolder {
 [DllImport("shell32.dll", CharSet=CharSet.Unicode)]
 public static extern int SHSetKnownFolderPath(ref Guid id, uint flags, IntPtr token, string path);
}
'@
    }
    $liveRoot=Join-Path $OutputDirectory ('native-'+[guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $liveRoot)
    & $module {
        param($store)
        $script:ShortcutFixtureStore=$store
        function script:Get-VutInstallerStore { return $script:ShortcutFixtureStore }
        # The VM hardware and absence of an existing app are the only functional
        # doubles. Catalogue, download, Authenticode, copy, Desktop and .lnk are real.
        function script:Get-VutHardware {
            return [pscustomobject]@{
                BoardManufacturer=$script:ShortcutVendor;BoardModel=if($script:ShortcutVendor -eq 'ASRock'){'B650M Pro RS'}else{'SIMULATED '+$script:ShortcutVendor+' MODEL'};ComputerManufacturer='System manufacturer';ComputerModel='System Product Name'
                Portable=$false;WindowsCaption='Microsoft Windows 11 Pro';WindowsVersion='10.0.26100';ClientWindows=$true;Is64Bit=$true
            }
        }
        function script:Get-VutInstalledApplication { param($Profile) return $null }
    } (Join-Path $liveRoot 'InstallerStore')
    if ($RecordedGigabyteCatalogue) {
        $snapshot=Get-Item -LiteralPath $RecordedGigabyteCatalogue
        if ($snapshot.PSIsContainer -or $snapshot.Length -gt 2097152) { throw 'Capture officielle GCC invalide.' }
        & $module {
            param($html)
            $script:GccCatalogueFixture=$html
            # Explicit test-only substitution. Production always consults live sources.
            function script:Resolve-VutGigabyteDownload {
                $r=ConvertFrom-VutGigabyteCatalogue -Html $script:GccCatalogueFixture
                $r.Method='recorded_official_gigabyte_utility_html'
                return $r
            }
            function script:Get-VutGigabytePackage { param($Directory) Get-VutGigabyteBundlePackage -Directory $Directory }
        } ([IO.File]::ReadAllText($snapshot.FullName))
    }
    $id=[guid]'B4BFCC3A-DB2C-424C-B029-7FE99A87C641'
    $oldDesktop=[Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory)
    $restored=$false
    try {
        foreach ($liveVendor in $Vendors) {
          & $module {param($v) $script:ShortcutVendor=$v} $liveVendor
          foreach ($desktopMode in @('Bureau','OneDrive - Fixture/Bureau')) {
            Case ('Actual '+$liveVendor+' download and installer shortcut: '+$desktopMode) {
                $desktop=Join-Path $liveRoot ($liveVendor+'/'+$desktopMode)
                [void](New-Item -ItemType Directory -Path $desktop -Force)
                Assert ([VutInstallerKnownFolder]::SHSetKnownFolderPath([ref]$id,0,[IntPtr]::Zero,$desktop) -eq 0) 'Redirection Bureau fixture impossible.'
                $r=Invoke-VendorUtility
                Assert ($r.Status -eq 'manual_required' -and -not $r.Installed -and -not $r.InstalledThisRun) ('Statut incorrect : '+$r.Reason)
                Assert ($r.InstallerShortcut -and (Test-Path -LiteralPath $r.InstallerShortcut -PathType Leaf)) ('Raccourci installateur absent : '+$r.Reason)
                Assert ((Split-Path -Parent $r.InstallerShortcut) -eq $desktop) 'Mauvais Bureau utilise.'
                Assert (-not $r.Shortcut -and -not $r.ApplicationVerified) 'Installateur confondu avec application installee.'
                if ($liveVendor -eq 'GIGABYTE' -and -not $RecordedGigabyteCatalogue) {
                    Assert ($r.DetectionMethod -ceq 'official_gcc_software_update_manifest' -and ([uri]$r.DetectionSource).Host -ceq 'mb.download.gigabyte.com' -and ([uri]$r.InstallerSource).Host -ceq 'mb.download.gigabyte.com') 'La detection GCC live ne provient pas du manifeste logiciel officiel.'
                }
                $com=New-Object -ComObject WScript.Shell
                try {
                    $link=$com.CreateShortcut($r.InstallerShortcut)
                    Assert ($link.TargetPath -ieq $r.InstallerPath -and $link.Arguments -ceq '') 'Cible COM incorrecte ou arguments automatiques.'
                    Assert (Test-Path -LiteralPath $link.TargetPath -PathType Leaf) 'Cible du raccourci inexistante.'
                    $signature=& $module { param($p,$v) Test-MbxSignedPayload -Path $p -Signers (Get-VutProfile $v).Signers } $link.TargetPath $liveVendor
                    Assert ($signature.Status -eq 'Valid') 'Cible sans signature constructeur valide.'
                    if ($liveVendor -eq 'GIGABYTE') { Assert ([Diagnostics.FileVersionInfo]::GetVersionInfo($link.TargetPath).ProductName -ceq 'GIGABYTE Control Center') 'Le raccourci GCC pointe vers un lanceur de modules facultatifs.' }
                    $package=[pscustomobject]@{Path=$r.InstallerPath;SHA256=$signature.SHA256;Version=$r.InstallerVersion;Kind=if($liveVendor -eq 'GIGABYTE'){'gigabyte_core'}else{'vendor_setup'}}
                    $again=& $module {param($p,$v) New-VutInstallerShortcut -Profile (Get-VutProfile $v) -Package $p} $package $liveVendor
                    Assert ($again.Path -eq $r.InstallerPath -and $again.Shortcut -eq $r.InstallerShortcut) 'Relance non idempotente.'
                    # An unrelated shortcut with the same name must be preserved.
                    $other=Join-Path $desktop 'unrelated.exe'; [IO.File]::WriteAllText($other,'inert; never executed')
                    $link.TargetPath=$other; $link.Save()
                    $message=''; try { & $module {param($p,$v) New-VutInstallerShortcut -Profile (Get-VutProfile $v) -Package $p} $package $liveVendor | Out-Null } catch { $message=$_.Exception.Message }
                    Assert ($message -match 'autre cible') 'Raccourci tiers ecrase.'
                    Assert ($com.CreateShortcut($r.InstallerShortcut).TargetPath -ieq $other) 'Cible tierce non preservee.'
                    $script:liveEvidence+=@([pscustomobject]@{
                        Vendor=$liveVendor;HardwareSimulated=$true;DesktopMode=$desktopMode;OfficialDownloadReal=$true;SignatureReal=$true;ShortcutCOMReal=$true
                        CatalogueMode=if($liveVendor -eq 'GIGABYTE' -and $RecordedGigabyteCatalogue){'recorded_official_response_not_live'}else{'live'}
                        InstallerVersion=$r.InstallerVersion;InstallerSHA256=$signature.SHA256;Signer=$signature.Signer
                        DetectionMethod=$r.DetectionMethod;DetectionSource=$r.DetectionSource;InstallerSource=$r.InstallerSource
                        ShortcutFileName=[IO.Path]::GetFileName($r.InstallerShortcut);TargetExistedAtCheck=$true;Arguments=''
                        ReusedWithoutDuplicate=$true;UnrelatedShortcutPreserved=$true;VendorInstallerExecuted=$false;Installed=$false
                    })
                } finally { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($com) }
            } 'real_download_signature_and_com_with_hardware_fixture'
          }
        }
    } finally {
        $hr=[VutInstallerKnownFolder]::SHSetKnownFolderPath([ref]$id,0,[IntPtr]::Zero,$oldDesktop)
        $restored=($hr -eq 0 -and [Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory) -eq $oldDesktop)
        if ($restored) { Remove-Item -LiteralPath $liveRoot -Recurse -Force }
    }
    Case 'Original Windows Desktop is restored after native tests' { Assert $restored 'Bureau initial non restaure.' } 'real_com'
}
$report=[ordered]@{
    Kind='utility_installer_shortcut_tests';Assertions=$script:assertions;Cases=@($cases.ToArray())
    Failures=@($cases.ToArray() | Where-Object Result -eq 'failed').Count
    VendorInstallerExecuted=$false;ActualVendorInstallations=0;Live=$script:liveEvidence
}
$report | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $OutputDirectory 'installer-shortcut-tests.json') -Encoding UTF8
Import-Module (Join-Path $PSScriptRoot '../motherboard/MotherboardExperiment.psm1') -Force
Write-MbxEvidence -Kind 'utility_installer_shortcut_tests' -Data $report
if ($report.Failures) { throw "$($report.Failures) scenario(s) raccourci installateur en echec." }
Write-Host "$($cases.Count) scenarios / $script:assertions assertions reussis ; aucun installateur execute."
