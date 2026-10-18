#requires -Version 5.1
[CmdletBinding()]
param([string]$OutputDirectory=(Join-Path $PSScriptRoot 'reports/gigabyte-package'))
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2
Import-Module (Join-Path $PSScriptRoot 'VendorUtility.psm1') -Force
$module=Get-Module VendorUtility
[void](New-Item -ItemType Directory -Path $OutputDirectory -Force)
$root=Join-Path ([IO.Path]::GetFullPath($OutputDirectory)) ('inert-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $root)
$cases=New-Object 'System.Collections.Generic.List[object]';$script:assertions=0
function Assert($v,[string]$m){$script:assertions++;if(-not $v){throw $m}}
function Case([string]$n,[scriptblock]$b){try{&$b;$cases.Add([pscustomobject]@{Name=$n;Result='passed';Error=''})}catch{$cases.Add([pscustomobject]@{Name=$n;Result='failed';Error=$_.Exception.Message});Write-Warning ($n+': '+$_.Exception.Message)}}
function Rejects([scriptblock]$b,[string]$p){$m='';try{$null=&$b}catch{$m=$_.Exception.Message};Assert ($m -match $p) ('Cause incorrecte : '+$m)}
function Parse([string]$s){&$module {param($s) Resolve-VutGccCoreEntry -Listing $s} $s}
try {
    Case 'Only the core is selected among optional vendor modules' {
        $r=Parse "Path = NortonInstaller.exe`nPath = GIGABYTE Control Center_26.08.28.01.exe`nPath = EasyTune.exe"
        Assert ($r.FileName -ceq 'GIGABYTE Control Center_26.08.28.01.exe' -and $r.Version -ceq '26.08.28.01') 'Mauvais composant selectionne.'
    }
    Case 'A second core version is ambiguous rather than guessed' {Rejects {Parse "Path = GIGABYTE Control Center_26.08.28.01.exe`nPath = GIGABYTE Control Center_26.07.01.01.exe"} 'ambigu'}
    Case 'Missing core never returns the outer bundle' {Rejects {Parse 'Path = GIGABYTE Control Center_All_Setup.exe'} 'absent'}
    foreach($prefix in @('../','/','C:/','@list/','-option/','*/','?/')){
        Case ('Unsafe core path rejected: '+$prefix) {Rejects {Parse ('Path = '+$prefix+'GIGABYTE Control Center_26.08.28.01.exe')} 'dangereux'}
    }
    Case 'Overflow version is refused' {Rejects {Parse 'Path = GIGABYTE Control Center_999999999999.0.0.0.exe'} 'invalide'}
    Case 'Vendor executable cannot be invoked as an archive tool' {Rejects {&$module {Invoke-VutArchiveTool -Path 'VendorInstaller.exe' -Arguments @('/S')}} 'aucun executable constructeur'}
    Case 'Wrong archive tool checksum prevents execution' {
        $p=Join-Path $root '7zr.exe';[IO.File]::WriteAllText($p,'inert')
        Rejects {&$module {param($p) Invoke-VutArchiveTool -Path $p -Arguments @('l')} $p} 'empreinte'
    }
    & $module {
        function script:Resolve-VutGigabyteDownload {return [pscustomobject]@{BundleVersion='26.09.10.01';DownloadUrl='https://download.gigabyte.com/fixture.zip';Method='fixture'}}
        function script:Invoke-MbxUtilityAudit {
            param($Tool,$DownloadUrl,$OutputDirectory)
            $owned=Join-Path $OutputDirectory ([guid]::NewGuid().ToString('N'));[void](New-Item -ItemType Directory -Path $owned -Force)
            $p=Join-Path $owned 'payload-0.exe';[IO.File]::WriteAllText($p,'inert outer bundle; never execute')
            $hash=(Get-FileHash -LiteralPath $p).Hash
            $payloads=@([pscustomobject]@{SHA256=$hash;FileVersion=$script:Fixture.OuterVersion})
            if($script:Fixture.ExtraPayload){$payloads+=,[pscustomobject]@{SHA256=$hash;FileVersion=$script:Fixture.OuterVersion}}
            return [pscustomobject]@{Bytes=100;ExpectedBytes=if($script:Fixture.Incomplete){101}else{100};Payloads=$payloads}
        }
        function script:Test-MbxSignedPayload {
            param($Path,$Signers)
            if($script:Fixture.BadSignature){throw 'Fixture signature invalide'}
            $core=([IO.Path]::GetFileName($Path) -like 'GIGABYTE Control Center_*')
            return [pscustomobject]@{SHA256=if($script:Fixture.ChangedOuter -and -not $core){'changed'}else{(Get-FileHash -LiteralPath $Path).Hash};FileVersion=if($core){$script:Fixture.CoreVersion}else{$script:Fixture.OuterVersion};Status='simulated_valid'}
        }
        function script:Get-VutPortableSevenZip {param($Directory) return 'fixture archive tool, never executed'}
        function script:Get-VutGccInstallerProductName {param($Path) return 'GIGABYTE Control Center'}
        function script:Invoke-VutArchiveTool {
            param($Path,$Arguments)
            if($Arguments[0] -eq 'l'){return $script:Fixture.Listing}
            $dir=$Arguments[2].Substring(2);[void](New-Item -ItemType Directory -Path $dir -Force)
            [IO.File]::WriteAllText((Join-Path $dir 'GIGABYTE Control Center_26.08.28.01.exe'),'inert core, never execute')
            if($script:Fixture.ExtraExtract){[IO.File]::WriteAllText((Join-Path $dir 'Norton.exe'),'inert extra, never execute')}
            return 'fixture extraction only'
        }
    }
    function Reset-Fixture {
        &$module {$script:Fixture=[pscustomobject]@{OuterVersion='26.09.10.01';CoreVersion='26.08.28.01';ExtraPayload=$false;Incomplete=$false;ChangedOuter=$false;BadSignature=$false;ExtraExtract=$false;Listing='Path = GIGABYTE Control Center_26.08.28.01.exe'}}
    }
    function State {&$module {$script:Fixture}}
    function Package {&$module {param($d) Get-VutGigabyteBundlePackage -Directory $d} (Join-Path $root ([guid]::NewGuid().ToString('N')))}
    Case 'Signed core is the returned package, not the bundle or its version' {
        Reset-Fixture;$p=Package
        Assert ($p.Kind -eq 'gigabyte_core' -and $p.Version -ceq '26.08.28.01') 'Mauvais type/version du paquet.'
        Assert ($p.Discovery.BundleVersion -ceq '26.09.10.01' -and $p.Path -like '*core-only*') 'Coeur et bundle confondus.'
        Assert ((Get-FileHash -LiteralPath $p.Path).Hash -eq $p.SHA256 -and -not $p.VendorInstallerExecuted) 'Fichier non verifie ou execute.'
    }
    foreach($test in @(
        @{Name='Incomplete bundle';Field='Incomplete';Value=$true;Pattern='incomplet'},
        @{Name='Ambiguous outer payload';Field='ExtraPayload';Value=$true;Pattern='ambigu'},
        @{Name='Stale outer file';Field='OuterVersion';Value='26.07.01.01';Pattern='version annoncee'},
        @{Name='Changed outer hash';Field='ChangedOuter';Value=$true;Pattern='modifie'},
        @{Name='Invalid vendor signature';Field='BadSignature';Value=$true;Pattern='signature invalide'},
        @{Name='Optional file extracted';Field='ExtraExtract';Value=$true;Pattern='limitee au seul coeur'},
        @{Name='Stale core file';Field='CoreVersion';Value='26.07.01.01';Pattern='Version du coeur'}
    )){
        Case $test.Name {Reset-Fixture;(State).($test.Field)=$test.Value;Rejects {Package} $test.Pattern}
    }
} finally {Remove-Module VendorUtility;Remove-Item -LiteralPath $root -Recurse -Force}
$report=[ordered]@{Kind='gigabyte_package_tests';Assertions=$script:assertions;Cases=@($cases.ToArray());Failures=@($cases.ToArray()|Where-Object Result -eq failed).Count;Mode='inert_files_simulated_download_signature_and_extraction';VendorInstallerExecuted=$false}
$report|ConvertTo-Json -Depth 8|Set-Content (Join-Path $OutputDirectory 'gigabyte-package-tests.json') -Encoding UTF8
Import-Module (Join-Path $PSScriptRoot '../motherboard/MotherboardExperiment.psm1') -Force
Write-MbxEvidence -Kind 'gigabyte_package_tests' -Data $report
if($report.Failures){throw "$($report.Failures) scenario(s) GCC package en echec."}
Write-Host "$($cases.Count) scenarios / $script:assertions assertions reussis ; aucun installateur execute."
