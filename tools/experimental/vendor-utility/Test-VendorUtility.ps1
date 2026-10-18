#requires -Version 5.1
[CmdletBinding()]
param([switch]$Live,[string]$OutputDirectory=(Join-Path $PSScriptRoot 'reports/tests'))
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'VendorUtility.psm1') -Force
$module=Get-Module VendorUtility
[void](New-Item -ItemType Directory -Path $OutputDirectory -Force)
$cases=New-Object 'System.Collections.Generic.List[object]'; $script:assertions=0
function Assert($value,[string]$message) { $script:assertions++; if (-not $value) { throw $message } }
function Case([string]$name,[scriptblock]$body) {
    try { & $body; $cases.Add([pscustomobject]@{Name=$name;Result='passed';Error=''}) }
    catch { $cases.Add([pscustomobject]@{Name=$name;Result='failed';Error=$_.Exception.Message}); Write-Warning ($name+': '+$_.Exception.Message) }
}
$fixture=Join-Path $OutputDirectory ('fixture-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $fixture)
$installer=Join-Path $fixture 'FixtureInstaller.exe'; $appPath=Join-Path $fixture 'FixtureApplication.exe'
[IO.File]::WriteAllText($installer,'inert fixture, never executed')
[IO.File]::WriteAllText($appPath,'inert application target, never executed')
$original=& $module {
    @{
        Profile=(Get-Command Get-VutProfile).ScriptBlock
        Shortcut=(Get-Command New-VutShortcut).ScriptBlock
        Process=(Get-Command Invoke-VutInstallerProcess).ScriptBlock
        Hardware=(Get-Command Get-VutHardware).ScriptBlock
        Probe=(Get-Command Get-VutInstalledApplication).ScriptBlock
    }
}
& $module {
    param($original,$installer,$appPath)
    $script:Original=$original; $script:FixtureInstaller=$installer; $script:FixtureApp=$appPath
    $script:UtilitySimulation=$true
    function script:Get-VutHardware { return $script:CaseState.Hardware }
    function script:Get-VutProfile {
        param($Vendor)
        $p=& $script:Original.Profile $Vendor
        if ($script:CaseState.CertifiedSimulation) { $p.Automatic=$true; $p.InstallerArguments='/FIXTURE_ONLY /NORESTART'; $p.ApprovedInstallerHashes=@($script:CaseState.PackageHash) }
        if ($script:CaseState.WrongApprovedHash) { $p.ApprovedInstallerHashes=@('different') }
        return $p
    }
    function script:Get-VutInstalledApplication {
        param($Profile)
        $script:CaseState.Probes++
        if ($script:CaseState.Existing -or ($script:CaseState.InstallerCalls -gt 0 -and $script:CaseState.PostInstalled)) {
            return [pscustomobject]@{ Verified=$true;Kind='Exe';Version=$script:CaseState.InstalledVersion;Target=$script:FixtureApp;Arguments='';Proof='Simulation only' }
        }
        return $null
    }
    function script:Get-VutPackage {
        param($Profile,$Directory)
        $script:CaseState.Downloads++
        if ($script:CaseState.NetworkFailure) { throw 'Fixture HTTP 503' }
        return [pscustomobject]@{Path=$script:FixtureInstaller;SHA256=$script:CaseState.PackageHash;Version=$script:CaseState.TargetVersion}
    }
    function script:Test-MbxSignedPayload {
        param($Path,$Signers)
        return [pscustomobject]@{SHA256=if($script:CaseState.ChangedFile){'changed'}else{$script:CaseState.PackageHash}}
    }
    function script:Invoke-VutInstallerProcess {
        param($Path,$Arguments)
        $script:CaseState.InstallerCalls++
        $script:CaseState.LastArguments=$Arguments
        if ($script:CaseState.Interrupted) { throw 'Fixture : installation interrompue' }
        if ($script:CaseState.Timeout) { throw 'Fixture : delai installateur depasse' }
        return $script:CaseState.ExitCode
    }
    function script:New-VutShortcut {
        param($Profile,$Application)
        $script:CaseState.Shortcuts++
        if ($script:CaseState.ShortcutFailure) { throw 'Fixture : Bureau inaccessible' }
        return 'fixture-desktop/'+$Profile.Name+'.lnk'
    }
    function script:New-VutInstallerShortcut {
        param($Profile,$Package)
        $script:CaseState.InstallerShortcuts++
        if ($script:CaseState.InstallerShortcutFailure) { throw 'Fixture : Bureau installateur inaccessible' }
        return [pscustomobject]@{Path=$Package.Path;Version=$Package.Version;Shortcut=('fixture-desktop/Installer '+$Profile.Name+'.lnk')}
    }
    function script:New-VutSupportShortcut {
        param($Profile)
        $script:CaseState.SupportShortcuts++
        return 'fixture-desktop/Telechargement officiel.url'
    }
} $original $installer $appPath

function Reset-Case {
    & $module {
        $script:CaseState=[pscustomobject]@{
            Hardware=[pscustomobject]@{BoardManufacturer='Micro-Star International Co., Ltd.';BoardModel='SIMULATED MSI MODEL';ComputerManufacturer='System manufacturer';ComputerModel='System Product Name';Portable=$false;WindowsCaption='Microsoft Windows 11 Pro';WindowsVersion='10.0.22631';ClientWindows=$true;Is64Bit=$true}
            CertifiedSimulation=$false; WrongApprovedHash=$false; Existing=$false; PostInstalled=$true
            InstalledVersion='2.0.74.0'; TargetVersion='2.0.74.0'; PackageHash=(Get-FileHash $script:FixtureInstaller).Hash
            Downloads=0; Probes=0; InstallerCalls=0; Shortcuts=0; InstallerShortcuts=0; SupportShortcuts=0; ExitCode=0; LastArguments=''
            NetworkFailure=$false; ChangedFile=$false; Timeout=$false; Interrupted=$false; ShortcutFailure=$false; InstallerShortcutFailure=$false
        }
    }
}
function State { & $module { $script:CaseState } }
try {
    Case 'Syntax and no driver/firmware/update invocations' {
        foreach ($file in Get-ChildItem $PSScriptRoot -Filter '*.ps*1') {
            $t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$t,[ref]$e)
            Assert (@($e).Count -eq 0) ('Syntaxe '+$file.Name)
            if ($file.Name -eq 'VendorUtility.psm1') {
                $names=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst]},$true) | ForEach-Object { $_.GetCommandName() })
                Assert (@($names | Where-Object { $_ -match 'Get-MbxInventory|Select-MbxDriver|WindowsUpdate|Install-.*Driver|Restart-Computer|Invoke-Expression|Invoke-CimMethod' }).Count -eq 0) 'Fonction hors du perimetre logiciel.'
            }
        }
    }
    foreach ($vendor in @('MSI','ASUS','GIGABYTE','ASRock')) {
        Case ('Identify '+$vendor+' with no guessed automatic mode') {
            Reset-Case; (State).Hardware.BoardManufacturer=$vendor
            $r=Invoke-VendorUtility -PlanOnly
            Assert ($r.Vendor -eq $vendor -and $r.Status -eq 'plan') 'Identification incorrecte.'
            Assert (-not $r.AutomaticInstallAvailable -and (State).InstallerCalls -eq 0) 'Methode silencieuse inventee.'
        }
    }
    foreach ($kind in @('unknown','missing_model','oem','portable','virtual','server','32bit')) {
        Case ('Unsupported '+$kind+' never installs') {
            Reset-Case; $h=(State).Hardware
            switch ($kind) {
                unknown {$h.BoardManufacturer='Other'}
                missing_model {$h.BoardModel='To be filled by O.E.M.'}
                oem {$h.ComputerManufacturer='Dell Inc.'}
                portable {$h.Portable=$true}
                virtual {$h.ComputerManufacturer='Microsoft Corporation';$h.ComputerModel='Virtual Machine'}
                server {$h.ClientWindows=$false}
                '32bit' {$h.Is64Bit=$false}
            }
            $r=Invoke-VendorUtility
            Assert ($r.Status -eq 'manual_required' -and -not $r.Installed) 'Materiel incompatible accepte.'
            Assert ((State).InstallerCalls -eq 0 -and (State).Downloads -eq 0 -and (State).Shortcuts -eq 0 -and (State).InstallerShortcuts -eq 0 -and (State).SupportShortcuts -eq 0) 'Effet inattendu.'
        }
    }
    Case 'Manual fallback never claims downloaded equals installed' {
        Reset-Case; $r=Invoke-VendorUtility
        Assert ($r.Status -eq 'manual_required' -and -not $r.Installed -and $r.InstallerPath -and $r.InstallerShortcut) 'Telechargement sans raccourci installateur ou faux succes.'
        Assert ((State).InstallerCalls -eq 0 -and (State).Shortcuts -eq 0 -and (State).InstallerShortcuts -eq 1) 'Installateur execute ou raccourci application cree sans installation.'
    }
    Case 'Portable with an existing app still receives no Desktop shortcut' {
        Reset-Case; (State).Hardware.Portable=$true; (State).Existing=$true
        $r=Invoke-VendorUtility
        Assert ($r.Status -eq 'manual_required' -and -not $r.Shortcut -and -not $r.InstallerShortcut) 'Raccourci ajoute sur un portable.'
        Assert ((State).Downloads -eq 0 -and (State).Probes -eq 0 -and (State).Shortcuts -eq 0 -and (State).InstallerShortcuts -eq 0) 'Portable non exclu avant les operations.'
    }
    Case 'Network failure precise and non successful' {
        Reset-Case; (State).NetworkFailure=$true; $r=Invoke-VendorUtility
        Assert ($r.Status -eq 'manual_required' -and $r.Reason -match '503' -and -not $r.Installed) 'Erreur reseau masquee.'
        Assert (-not $r.InstallerShortcut -and (State).InstallerShortcuts -eq 0) 'Raccourci cree malgre erreur de telechargement.'
        Assert ($r.SupportShortcut -and $r.FallbackUsed -and (State).SupportShortcuts -eq 1) 'Repli officiel absent.'
    }
    Case 'Installer Desktop error is explicit and never claims a shortcut exists' {
        Reset-Case; (State).InstallerShortcutFailure=$true; $r=Invoke-VendorUtility
        Assert ($r.Status -eq 'failed' -and $r.Reason -match 'Bureau installateur inaccessible' -and -not $r.InstallerShortcut -and -not $r.Installed) 'Erreur raccourci installateur masquee.'
        Assert ((State).InstallerCalls -eq 0) 'Installateur execute pour contourner un Bureau inaccessible.'
    }
    Case 'Already verified app creates shortcut without download or reinstall' {
        Reset-Case; (State).Existing=$true; $r=Invoke-VendorUtility
        Assert ($r.Status -eq 'already_installed' -and $r.ApplicationVerified -and $r.Shortcut) 'Application existante non prise en compte.'
        Assert ((State).Downloads -eq 0 -and (State).InstallerCalls -eq 0) 'Application deja installee modifiee.'
    }
    Case 'Simulated supported installation verifies app and shortcut' {
        Reset-Case; (State).CertifiedSimulation=$true; $r=Invoke-VendorUtility
        Assert ($r.Status -eq 'simulated_installed' -and $r.ApplicationVerified -and $r.Shortcut) 'Flux installation simule incorrect.'
        Assert ($r.Mode -eq 'simulation' -and -not $r.Installed -and -not $r.InstalledThisRun) 'Installation simulee annoncee comme reelle.'
        Assert ((State).InstallerCalls -eq 1 -and (State).Probes -eq 2) 'Installation non suivie d une verification.'
    }
    foreach ($code in @(1603,1641,1223)) {
        Case ('Simulated exit '+$code+' is not success') {
            Reset-Case; (State).CertifiedSimulation=$true; (State).ExitCode=$code; $r=Invoke-VendorUtility
            Assert ($r.Status -eq 'failed' -and $r.Reason -match [string]$code) 'Code retour ignore.'
            Assert ((State).Shortcuts -eq 0 -and -not $r.Installed) 'Faux succes apres code echec.'
        }
    }
    Case 'Simulated 3010 requests manual restart only' {
        Reset-Case; (State).CertifiedSimulation=$true; (State).ExitCode=3010; $r=Invoke-VendorUtility
        Assert ($r.RebootRequired -and $r.Status -eq 'simulated_installed') 'Redemarrage requis perdu.'
    }
    foreach ($kind in @('Timeout','Interrupted')) {
        Case ('Simulated '+$kind+' fails without shortcut') {
            Reset-Case; (State).CertifiedSimulation=$true; (State).$kind=$true; $r=Invoke-VendorUtility
            Assert ($r.Status -eq 'failed' -and (State).Shortcuts -eq 0 -and -not $r.Installed) 'Interruption/timeout confirme a tort.'
        }
    }
    Case 'Exit zero but no application fails verification' {
        Reset-Case; (State).CertifiedSimulation=$true; (State).PostInstalled=$false; $r=Invoke-VendorUtility
        Assert ($r.Status -eq 'failed' -and $r.Reason -match 'non confirmee' -and (State).Shortcuts -eq 0) 'Code zero suffit a tort.'
    }
    Case 'Version comparison numeric and stale installation rejected' {
        Reset-Case; (State).CertifiedSimulation=$true; (State).InstalledVersion='1.10'; (State).TargetVersion='1.9'
        Assert ((Invoke-VendorUtility).Status -eq 'simulated_installed') '1.10 considere inferieur a 1.9.'
        Reset-Case; (State).CertifiedSimulation=$true; (State).InstalledVersion='1.9'; (State).TargetVersion='1.10'
        Assert ((Invoke-VendorUtility).Status -eq 'failed') 'Version installee insuffisante acceptee.'
    }
    Case 'Unknown package hash and changed installer never execute' {
        Reset-Case; (State).CertifiedSimulation=$true; (State).WrongApprovedHash=$true
        Assert ((Invoke-VendorUtility).Status -eq 'manual_required' -and (State).InstallerCalls -eq 0) 'Package non audite execute.'
        Reset-Case; (State).CertifiedSimulation=$true; (State).ChangedFile=$true
        Assert ((Invoke-VendorUtility).Status -eq 'failed' -and (State).InstallerCalls -eq 0) 'Fichier change execute.'
    }
    Case 'Desktop error never claims complete success' {
        Reset-Case; (State).CertifiedSimulation=$true; (State).ShortcutFailure=$true; $r=Invoke-VendorUtility
        Assert ($r.Status -eq 'failed' -and $r.ApplicationVerified -and -not $r.Shortcut) 'Erreur raccourci masquee.'
    }
    Case 'Real native process boundary blocks all vendor installers on GitHub' {
        $previous=$env:GITHUB_ACTIONS; $blocked=$false
        try { $env:GITHUB_ACTIONS='true'; & $original.Process -Path $installer -Arguments '' }
        catch { $blocked=$_.Exception.Message -match 'interdit' }
        finally { $env:GITHUB_ACTIONS=$previous }
        Assert $blocked 'Installateur materiel reel autorise sur CI.'
    }
} finally { Remove-Item -LiteralPath $fixture -Recurse -Force }

Remove-Module VendorUtility
Import-Module (Join-Path $PSScriptRoot 'VendorUtility.psm1') -Force
$module=Get-Module VendorUtility
$probeFixture=Join-Path $OutputDirectory ('package-probe-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $probeFixture)
$probeFixture=[IO.Path]::GetFullPath($probeFixture)
[IO.File]::WriteAllText((Join-Path $probeFixture 'App.exe'),'inert, never launched')
[IO.File]::WriteAllText((Join-Path $probeFixture 'AppxManifest.xml'),'<Package><Applications><Application Id="App" Executable="App.exe" /></Applications></Package>')
$previousWindir=$env:WINDIR
if (-not $env:WINDIR) { $env:WINDIR=$probeFixture }
& $module {
    param($fixture)
    $script:PackageFixture=[pscustomobject]@{PackageFamilyName='9426MICRO-STARINTERNATION.MSICenter_kzh8wxbdkxb8p';Status='Ok';SignatureKind='Store';IsDevelopmentMode=$false;InstallLocation=$fixture;Version='2.0.74.0'}
    $script:ProbeRegistry=@()
    function script:Get-AppxPackage { param($Name) return $script:PackageFixture }
    function script:Get-ItemProperty { param($Path) return $script:ProbeRegistry }
} $probeFixture
try {
    Case 'Probe exact registered Store package and declared app target' {
        $r=& $module { Get-VutInstalledApplication (Get-VutProfile MSI) }
        Assert ($r.Verified -and $r.Kind -eq 'Appx' -and $r.Arguments -eq 'shell:AppsFolder\9426MICRO-STARINTERNATION.MSICenter_kzh8wxbdkxb8p!App') 'Cible MSI Store non verifiee.'
    }
    foreach ($kind in @('wrong_family','developer_mode','unsigned','missing_app')) {
        Case ('Probe rejects '+$kind) {
            $saved=& $module { $script:PackageFixture | Select-Object * }
            try {
                & $module {
                    param($kind)
                    switch ($kind) {
                        wrong_family { $script:PackageFixture.PackageFamilyName='DifferentFamily' }
                        developer_mode { $script:PackageFixture.IsDevelopmentMode=$true }
                        unsigned { $script:PackageFixture.SignatureKind='None' }
                        missing_app { $script:PackageFixture.InstallLocation=Join-Path $script:PackageFixture.InstallLocation 'absent' }
                    }
                } $kind
                $r=& $module { Get-VutInstalledApplication (Get-VutProfile MSI) }
                Assert ($null -eq $r) 'Package non verifiable pris pour une application installee.'
            } finally { & $module {param($s) $script:PackageFixture=$s} $saved }
        }
    }
    Case 'Registry SDK or orphan entry cannot prove MSI Center installed' {
        & $module { $script:PackageFixture=$null; $script:ProbeRegistry=@([pscustomobject]@{DisplayName='MSI Center SDK';DisplayIcon='missing.exe'},[pscustomobject]@{DisplayName='MSI Center';DisplayIcon='"C:\nonexistent\MSICenter.exe" /update'}) }
        $r=& $module { Get-VutInstalledApplication (Get-VutProfile MSI) }
        Assert ($null -eq $r) 'SDK ou commande registre pris pour une application.'
    }
} finally { $env:WINDIR=$previousWindir; Remove-Item -LiteralPath $probeFixture -Recurse -Force }
Remove-Module VendorUtility
Import-Module (Join-Path $PSScriptRoot 'VendorUtility.psm1') -Force
$module=Get-Module VendorUtility
$real=@()
if ($Live) {
    Case 'Actual Windows 5.1 CIM and VM refusal' {
        Assert ($PSVersionTable.PSVersion.Major -eq 5 -and $PSVersionTable.PSEdition -eq 'Desktop') 'PowerShell 5.1 requis.'
        $r=Invoke-VendorUtility -PlanOnly
        Assert ($r.Status -eq 'manual_required' -and $r.Reason -match 'virtuelle' -and -not $r.Installed -and -not $r.Shortcut) 'VM non bloquee.'
        $script:real+=@([pscustomobject]@{Kind='ActualWindowsCim';Status=$r.Status;Reason=$r.Reason;VendorInstallerExecuted=$false})
    }
    Case 'Actual COM shortcuts on redirected user Desktop with restoration' {
        if (-not ('VutKnownFolder' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class VutKnownFolder {
 [DllImport("shell32.dll", CharSet=CharSet.Unicode)]
 public static extern int SHSetKnownFolderPath(ref Guid id, uint flags, IntPtr token, string path);
}
'@
        }
        $id=[guid]'B4BFCC3A-DB2C-424C-B029-7FE99A87C641'
        $old=[Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory)
        $dir=Join-Path ([IO.Path]::GetFullPath($OutputDirectory)) ('OneDrive - Fixture/Bureau-'+[guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $dir -Force)
        $target=Join-Path $dir 'FixtureApp.exe'; [IO.File]::WriteAllText($target,'inert target never executed')
        $restored=$false
        try {
            Assert ([VutKnownFolder]::SHSetKnownFolderPath([ref]$id,0,[IntPtr]::Zero,$dir) -eq 0) 'Redirection fixture impossible.'
            Assert ([Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory) -eq $dir) 'Bureau redirige ignore.'
            $p=& $module { Get-VutProfile MSI }
            $a=[pscustomobject]@{Verified=$true;Kind='Exe';Version='1.0';Target=$target;Arguments=''}
            $link=& $module {param($p,$a) New-VutShortcut $p $a} $p $a
            Assert ((Split-Path -Parent $link) -eq $dir -and (Test-Path $link)) 'Raccourci sur mauvais Bureau.'
            $com=New-Object -ComObject WScript.Shell
            $read=$com.CreateShortcut($link)
            Assert ($read.TargetPath -ieq $target -and $read.Arguments -eq '') 'Mauvaise cible COM.'
            [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($com)
            $again=& $module {param($p,$a) New-VutShortcut $p $a} $p $a
            Assert ($again -eq $link) 'Doublon de raccourci.'
            $a.Arguments='shell:AppsFolder\Fixture!App'
            $blocked=$false; try { & $module {param($p,$a) New-VutShortcut $p $a} $p $a } catch { $blocked=$true }
            Assert $blocked 'Raccourci existant different ecrase.'
        } finally {
            $hr=[VutKnownFolder]::SHSetKnownFolderPath([ref]$id,0,[IntPtr]::Zero,$old)
            $restored=($hr -eq 0 -and [Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory) -eq $old)
            if ($restored) { Remove-Item -LiteralPath $dir -Recurse -Force }
        }
        Assert $restored 'Bureau original non restaure.'
        $script:real+=@([pscustomobject]@{Kind='ActualCOMShortcut';RedirectedDesktop=$true;Restored=$restored;ApplicationExecuted=$false})
    }
}
$report=[ordered]@{Kind='utility_only_tests';SimulationCases=$true;ActualVendorInstallations=0;Assertions=$script:assertions;Cases=@($cases.ToArray());Real=$real;Failures=@($cases.ToArray()|Where-Object Result -eq failed).Count}
$report | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $OutputDirectory 'tests.json') -Encoding UTF8
Import-Module (Join-Path $PSScriptRoot '../motherboard/MotherboardExperiment.psm1') -Force
Write-MbxEvidence -Kind 'utility_tests' -Data $report
if ($report.Failures) { throw "$($report.Failures) scenario(s) en echec." }
Write-Host "$($cases.Count) scenarios / $script:assertions assertions reussis ; zero installateur constructeur reel execute."
