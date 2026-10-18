#requires -Version 5.1
[CmdletBinding()]
param([string]$OutputDirectory=(Join-Path $PSScriptRoot 'reports/gigabyte-core-download'))
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2
Import-Module (Join-Path $PSScriptRoot 'VendorUtility.psm1') -Force
$module=Get-Module VendorUtility
[void](New-Item -ItemType Directory -Path $OutputDirectory -Force)
$root=Join-Path ([IO.Path]::GetFullPath($OutputDirectory)) ('inert-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $root)
$cases=New-Object 'System.Collections.Generic.List[object]';$script:assertions=0
$manifest="[Info]`r`nApName=GIGABYTE Control Center`r`nDisplayName=GIGABYTE Control Center`r`nVer=26.08.28.01`r`nApNum=0`r`nSize=2048`r`n`r`n[Description]`r`neng=GCC Main Program`r`n"
function Assert($v,[string]$m){$script:assertions++;if(-not $v){throw $m}}
function Case([string]$n,[scriptblock]$b){try{&$b;$cases.Add([pscustomobject]@{Name=$n;Result='passed';Error=''})}catch{$cases.Add([pscustomobject]@{Name=$n;Result='failed';Error=$_.Exception.Message});Write-Warning ($n+': '+$_.Exception.Message)}}
function Rejects([scriptblock]$b,[string]$p){$m='';try{$null=&$b}catch{$m=$_.Exception.Message};Assert ($m -match $p) ('Cause incorrecte : '+$m)}
function Parse([string]$s){&$module {param($s) ConvertFrom-VutGigabyteCoreManifest -Text $s} $s}
function State {&$module {$script:CoreFixture}}
try {
    Case 'Official software manifest selects only GCC and preserves its version' {
        $r=Parse $manifest
        Assert ($r.Version -ceq '26.08.28.01' -and $r.ExpectedBytes -eq 2048) 'Version/taille incorrecte.'
        Assert ($r.Method -ceq 'official_gcc_software_update_manifest') 'Source non identifiee.'
        Assert ($r.DownloadUrl -ceq 'https://mb.download.gigabyte.com/FileList/Swhttp/LiveUpdate4/GCC/GIGABYTE%20Control%20Center/GIGABYTE%20Control%20Center_26.08.28.01.exe') 'URL ne correspondant pas au chemin officiel GCC.'
    }
    Case 'New manifest version changes the filename without a pinned release' {
        $r=Parse ($manifest.Replace('26.08.28.01','27.01.10.02'))
        Assert ($r.Version -ceq '27.01.10.02' -and $r.DownloadUrl -like '*_27.01.10.02.exe') 'Ancienne version figee.'
    }
    Case 'Description cannot overwrite the current version' {
        $r=Parse ($manifest+"Ver=99.99.99.99`nSize=9999`n")
        Assert ($r.Version -ceq '26.08.28.01' -and $r.ExpectedBytes -eq 2048) 'Description traitee comme metadata.'
    }
    foreach($test in @(
        @{Name='Another utility';Text=$manifest.Replace('GIGABYTE Control Center','EasyTune');Pattern='seul programme'},
        @{Name='Optional bundle';Text=$manifest.Replace('ApNum=0','ApNum=1');Pattern='seul programme'},
        @{Name='Missing version';Text=$manifest.Replace("Ver=26.08.28.01`r`n",'');Pattern='incomplet'},
        @{Name='Duplicate section';Text=$manifest+"[Info]`n";Pattern='ambigue'},
        @{Name='Duplicate version';Text=$manifest.Replace('ApNum=0',"Ver=1.0.0.0`nApNum=0");Pattern='dupliquee'},
        @{Name='Version URL injection';Text=$manifest.Replace('26.08.28.01','26.08.28.01/../../Norton');Pattern='Version'},
        @{Name='Version overflow';Text=$manifest.Replace('26.08.28.01','999999999999.0.0.0');Pattern='Version'},
        @{Name='Missing size';Text=$manifest.Replace("Size=2048`r`n",'');Pattern='incomplet'},
        @{Name='Invalid size';Text=$manifest.Replace('Size=2048','Size=unknown');Pattern='Taille'},
        @{Name='Negative size';Text=$manifest.Replace('Size=2048','Size=-1');Pattern='Taille'},
        @{Name='Empty payload size';Text=$manifest.Replace('Size=2048','Size=0');Pattern='Taille'},
        @{Name='Unbounded payload size';Text=$manifest.Replace('Size=2048','Size=1073741825');Pattern='Taille'},
        @{Name='Empty response';Text='';Pattern='Info'},
        @{Name='HTML challenge';Text='<html>Access denied</html>';Pattern='Info'},
        @{Name='Oversized response';Text=('x'*65537);Pattern='volumineux'}
    )) { Case $test.Name {Rejects {Parse $test.Text} $test.Pattern} }
    & $module {
        function script:Invoke-MbxHttp {
            param($Url,$Hosts,$TimeoutSeconds,$MaxBytes)
            $script:CoreFixture.Requests+=,[pscustomobject]@{Url=$Url;Hosts=$Hosts;MaxBytes=$MaxBytes}
            if ($script:CoreFixture.HttpError) { throw $script:CoreFixture.HttpError }
            return [pscustomobject]@{Text=$script:CoreFixture.Manifest;Url=$Url}
        }
        function script:Invoke-MbxUtilityAudit {
            param($Tool,$DownloadUrl,$OutputDirectory)
            $script:CoreFixture.AuditUrl=$DownloadUrl;$script:CoreFixture.AuditTool=$Tool
            if($script:CoreFixture.DownloadError){throw $script:CoreFixture.DownloadError}
            $owned=Join-Path $OutputDirectory ([guid]::NewGuid().ToString('N'));[void](New-Item -ItemType Directory -Path $owned -Force)
            $p=Join-Path $owned 'GIGABYTE Control Center_26.08.28.01.exe';[IO.File]::WriteAllText($p,'inert simulated installer; never execute')
            $hash=(Get-FileHash -LiteralPath $p).Hash
            $payloads=@([pscustomobject]@{SHA256=$hash;FileVersion=$script:CoreFixture.Version})
            if($script:CoreFixture.ExtraPayload){$payloads+=,$payloads[0]}
            return [pscustomobject]@{Bytes=$script:CoreFixture.Bytes;ExpectedBytes=$script:CoreFixture.ExpectedBytes;SHA256=$hash;Payloads=$payloads}
        }
        function script:Test-MbxSignedPayload {
            param($Path,$Signers)
            if($script:CoreFixture.SignatureError){throw $script:CoreFixture.SignatureError}
            return [pscustomobject]@{SHA256=if($script:CoreFixture.Changed){'changed'}else{(Get-FileHash -LiteralPath $Path).Hash};Bytes=$script:CoreFixture.SignedBytes;FileVersion=$script:CoreFixture.SignedVersion}
        }
        function script:Get-VutGigabyteBundlePackage {throw 'Forbidden bundle fallback'}
        function script:Resolve-VutGigabyteDownload {throw 'Forbidden HTML fallback'}
        function script:Get-VutPortableSevenZip {param($Directory) return 'fixture archive tool; never executed'}
        function script:Get-VutGccInstallerProductName {param($Path) return $script:CoreFixture.ProductName}
        function script:Invoke-VutArchiveTool {
            param($Path,$Arguments)
            if($Arguments[0] -eq 'l'){
                # 7-Zip's normal technical listing includes the outer archive's
                # absolute Path, which here has the same name as the core.
                if($Arguments -notcontains '-ba'){return ("Path = C:\fixture\GIGABYTE Control Center_26.08.28.01.exe`nType = Nsis`n----------`n"+$script:CoreFixture.Listing)}
                return $script:CoreFixture.Listing
            }
            $dir=$Arguments[2].Substring(2);[void](New-Item -ItemType Directory -Path $dir -Force)
            [IO.File]::WriteAllText((Join-Path $dir 'GIGABYTE Control Center_26.08.28.01.exe'),'inert core installer; never execute')
            if($script:CoreFixture.ExtraExtract){[IO.File]::WriteAllText((Join-Path $dir 'GBT_MB_Update.exe'),'inert optional module; never execute')}
            return 'fixture extraction'
        }
        function script:Invoke-VutInstallerProcess {throw 'Forbidden vendor execution'}
    }
    function Reset-Fixture {
        & $module {param($s) $script:CoreFixture=[pscustomobject]@{Manifest=$s;Requests=@();HttpError='';DownloadError='';AuditUrl='';AuditTool=$null;Version='26.08.28.01';SignedVersion='26.08.28.01';Bytes=2048;ExpectedBytes=2048;SignedBytes=2048;ExtraPayload=$false;Changed=$false;SignatureError='';ProductName='GIGABYTE Control Center';ExtraExtract=$false;Listing="Path = GBT_MB_Update_26.07.22.01.exe`nPath = GBT_RGB_Sync_Control_26.08.31.01.exe`nPath = GIGABYTE Control Center_26.08.28.01.exe"}} $manifest
    }
    function Package {&$module {param($d) Get-VutPackage -Profile (Get-VutProfile GIGABYTE) -Directory $d} (Join-Path $root ([guid]::NewGuid().ToString('N')))}
    Case 'Production path extracts the current core and excludes bundled MB Update and RGB Sync' {
        Reset-Fixture;$p=Package;$s=State
        Assert ($p.Kind -ceq 'gigabyte_core' -and $p.Version -ceq '26.08.28.01' -and -not $p.VendorInstallerExecuted) 'Mauvais paquet.'
        Assert ($s.Requests.Count -eq 1 -and $s.Requests[0].Url -eq $p.Discovery.ManifestUrl -and $s.Requests[0].Hosts[0] -ceq 'mb.download.gigabyte.com' -and $s.Requests[0].MaxBytes -eq 65536) 'Requete hors source officielle.'
        Assert ($s.AuditUrl -ceq $p.Discovery.DownloadUrl -and $p.CoreFileName -match $s.AuditTool.FilePattern) 'Fichier telecharge incorrect.'
        Assert ($p.Path -like '*core-only*' -and @((Get-ChildItem -LiteralPath (Split-Path -Parent $p.Path) -File)).Count -eq 1) 'Raccourci propose vers un bundle ou des modules facultatifs.'
    }
    foreach($test in @(
        @{Name='Live catalogue HTTP 403';Field='HttpError';Value='Fixture HTTP 403';Pattern='HTTP 403'},
        @{Name='Live catalogue timeout';Field='HttpError';Value='Fixture delai depasse';Pattern='delai depasse'},
        @{Name='Interrupted download';Field='DownloadError';Value='Fixture telechargement interrompu';Pattern='interrompu'},
        @{Name='HTTP transfer incomplete';Field='ExpectedBytes';Value=2049;Pattern='incomplet'},
        @{Name='Complete HTTP file shorter than manifest';Field='Bytes';Value=2047;Pattern='incomplet'},
        @{Name='Ambiguous payload';Field='ExtraPayload';Value=$true;Pattern='incomplet'},
        @{Name='Old executable rejected';Field='Version';Value='26.07.01.01';Pattern='aucun ancien'},
        @{Name='Signature failure';Field='SignatureError';Value='Fixture signature invalide';Pattern='signature invalide'},
        @{Name='Modified hash';Field='Changed';Value=$true;Pattern='modifie'},
        @{Name='Modified file length';Field='SignedBytes';Value=2049;Pattern='modifie'},
        @{Name='Modified executable version';Field='SignedVersion';Value='26.07.01.01';Pattern='modifie'},
        @{Name='Old core inside current update wrapper';Field='Listing';Value='Path = GIGABYTE Control Center_26.07.01.01.exe';Pattern='aucun ancien'},
        @{Name='Update wrapper masquerading as core';Field='ProductName';Value='Liveupdate_GCC';Pattern='Identite produit'},
        @{Name='Optional module extracted';Field='ExtraExtract';Value=$true;Pattern='limitee au seul coeur'}
    )) {Case $test.Name {Reset-Fixture;(State).($test.Field)=$test.Value;Rejects {Package} $test.Pattern}}
} finally {Remove-Module VendorUtility;Remove-Item -LiteralPath $root -Recurse -Force}
$report=[ordered]@{Kind='gigabyte_core_download_tests';Assertions=$script:assertions;Cases=@($cases.ToArray());Failures=@($cases.ToArray()|Where-Object Result -eq failed).Count;Mode='simulated_manifest_download_signature_inert_files';ActualNetworkRequests=0;VendorInstallerExecuted=$false}
$report|ConvertTo-Json -Depth 8|Set-Content (Join-Path $OutputDirectory 'gigabyte-core-download-tests.json') -Encoding UTF8
Import-Module (Join-Path $PSScriptRoot '../motherboard/MotherboardExperiment.psm1') -Force
Write-MbxEvidence -Kind 'gigabyte_core_download_tests' -Data $report
if($report.Failures){throw "$($report.Failures) scenario(s) GCC core en echec."}
Write-Host "$($cases.Count) scenarios / $script:assertions assertions reussis ; aucun installateur execute."
