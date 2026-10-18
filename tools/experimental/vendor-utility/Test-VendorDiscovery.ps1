#requires -Version 5.1
[CmdletBinding()]
param([switch]$Live,[string]$OutputDirectory=(Join-Path $PSScriptRoot 'reports/discovery-tests'))

$ErrorActionPreference='Stop'
$modulePath=Join-Path $PSScriptRoot 'VendorUtility.psm1'
Import-Module $modulePath -Force
$module=Get-Module VendorUtility
[void](New-Item -ItemType Directory -Path $OutputDirectory -Force)
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
$cases=New-Object 'System.Collections.Generic.List[object]'
$script:assertions=0
$script:liveResult=$null
$fixture=Join-Path $OutputDirectory ('discovery-fixture-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $fixture)

function Assert($Value,[string]$Message) {
    $script:assertions++
    if (-not $Value) { throw $Message }
}
function Case([string]$Name,[scriptblock]$Body) {
    try {
        & $Body
        $cases.Add([pscustomobject]@{Name=$Name;Mode='simulation';Result='passed';Error=''})
    } catch {
        $cases.Add([pscustomobject]@{Name=$Name;Mode='simulation';Result='failed';Error=$_.Exception.Message})
        Write-Warning ($Name+': '+$_.Exception.Message)
    }
}
function Expect-Failure([scriptblock]$Body,[string]$Pattern) {
    $message=''
    try { & $Body | Out-Null } catch { $message=$_.Exception.Message }
    Assert ([bool]$message) 'Une erreur attendue a ete acceptee.'
    Assert ($message -match $Pattern) ('Cause de l erreur inattendue : '+$message)
}
function State { & $module { $script:DiscoveryFixture } }
function Reset-Case {
    & $module {
        $script:DiscoveryFixture=[pscustomobject]@{
            Text='{"latestVersion":"1.0.7.1","minimumSupportedVersion":"1.0.4.7"}'
            HttpError='';HttpCalls=0;HttpUrl='';HttpHosts=@();AuditCalls=0;AuditUrl=''
            AuditError='';FileVersion='1.0.7.1';SignatureError='';Replaced=$false
            FileCount=1;Signatures=0;InstallerCalls=0
        }
    }
}
function Resolve-Download { & $module { Resolve-VutAsusDownload } }
function Get-FixturePackage {
    $directory=Join-Path $fixture ([guid]::NewGuid().ToString('N'))
    & $module { param($d) Get-VutPackage -Profile (Get-VutProfile ASUS) -Directory $d } $directory
}

# Test seams replace only HTTP, download/signature and execution boundaries.
# The discovery and package validation implementations themselves remain real.
& $module {
    $script:DiscoveryInstallerCalls=0
    function script:Invoke-MbxHttp {
        [CmdletBinding()]
        param([string]$Url,[string[]]$Hosts,[int]$TimeoutSeconds,[long]$MaxBytes,[string]$OutFile,[switch]$Head)
        $script:DiscoveryFixture.HttpCalls++
        $script:DiscoveryFixture.HttpUrl=$Url
        $script:DiscoveryFixture.HttpHosts=@($Hosts)
        if ($script:DiscoveryFixture.HttpError) { throw $script:DiscoveryFixture.HttpError }
        return [pscustomobject]@{Text=$script:DiscoveryFixture.Text;Url=$Url;Redirects=@($Url);HttpStatus=200}
    }
    function script:Invoke-MbxUtilityAudit {
        [CmdletBinding()]
        param($Tool,[string]$DownloadUrl,[string]$OutputDirectory,[int]$TimeoutSeconds)
        $script:DiscoveryFixture.AuditCalls++
        $script:DiscoveryFixture.AuditUrl=$DownloadUrl
        if ($script:DiscoveryFixture.AuditError) { throw $script:DiscoveryFixture.AuditError }
        [void](New-Item -ItemType Directory -Path $OutputDirectory -Force)
        $payloads=@()
        for ($i=0; $i -lt $script:DiscoveryFixture.FileCount; $i++) {
            $path=Join-Path $OutputDirectory ('payload-'+$i+'.exe')
            [IO.File]::WriteAllText($path,'INERT TEST FIXTURE; NEVER EXECUTE')
            $payloads+=[pscustomobject]@{
                Status='Valid';Signer='ASUSTeK COMPUTER INC.';FileVersion=$script:DiscoveryFixture.FileVersion
                SHA256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
            }
        }
        return [pscustomobject]@{
            Status='simulated_download';RequestedUrl=$DownloadUrl;FinalUrl=$DownloadUrl
            Payloads=$payloads;Installed=$false;Executed=$false;FirmwareFlashed=$false
        }
    }
    function script:Test-MbxSignedPayload {
        [CmdletBinding()]
        param([string]$Path,[string[]]$Signers)
        $script:DiscoveryFixture.Signatures++
        if ($script:DiscoveryFixture.SignatureError) { throw $script:DiscoveryFixture.SignatureError }
        $hash=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
        if ($script:DiscoveryFixture.Replaced) { $hash='REPLACED_FIXTURE_HASH' }
        return [pscustomobject]@{Status='Valid';Signer='ASUSTeK COMPUTER INC.';SHA256=$hash;FileVersion=$script:DiscoveryFixture.FileVersion}
    }
    function script:Invoke-VutInstallerProcess {
        $script:DiscoveryInstallerCalls++
        $script:DiscoveryFixture.InstallerCalls++
        throw 'Execution d un installateur constructeur interdite dans ces tests.'
    }
}

try {
    Case 'Discovery test syntax is valid on native PowerShell' {
        $tokens=$null;$errors=$null
        [void][Management.Automation.Language.Parser]::ParseFile($PSCommandPath,[ref]$tokens,[ref]$errors)
        Assert (@($errors).Count -eq 0) 'Erreur de syntaxe PowerShell.'
    }
    Case 'ASUS profile selects manifest and correct application filename' {
        $p=& $module { Get-VutProfile ASUS }
        Assert (-not $p.DownloadUrl) 'Ancien raccourci geo conserve comme lien de fichier.'
        Assert ($p.DownloadManifestUrl -eq 'https://driverhub.asus.com/download/ASUS-DriverHub-Installer.json') 'Manifeste officiel absent.'
        Assert ($p.FileNames -contains 'ASUS DriverHub.exe') 'Nom de l executable installe incorrect.'
        Assert (-not $p.Automatic) 'Methode d installation automatique non validee activee.'
    }
    foreach ($version in @('1.0.7.1','1.0.4.8','1.9.0.0','1.10.0.0')) {
        Case ('Official versioned route '+$version) {
            Reset-Case
            (State).Text=(@{latestVersion=$version;minimumSupportedVersion='1.0.4.7'} | ConvertTo-Json -Compress)
            $r=Resolve-Download
            Assert ($r.Version -eq $version -and $r.MinimumSupportedVersion -eq '1.0.4.7') 'Version du manifeste non preservee.'
            Assert ($r.DownloadUrl -eq ('https://driverhub.asus.com/download/'+$version+'/ASUS-DriverHub-Installer.exe')) 'Mauvais routage versionne.'
            Assert ($r.Method -eq 'official_asus_json' -and $r.ManifestUrl -eq (State).HttpUrl) 'Methode ou source manquante.'
        }
    }
    Case 'Numeric comparison treats 1.10 as newer than 1.9' {
        Reset-Case
        (State).Text='{"latestVersion":"1.10.0.0","minimumSupportedVersion":"1.9.0.0"}'
        $r=Resolve-Download
        Assert ($r.Version -eq '1.10.0.0') 'Comparaison lexicographique utilisee.'
        (State).Text='{"latestVersion":"1.9.0.0","minimumSupportedVersion":"1.10.0.0"}'
        Expect-Failure { Resolve-Download } 'minimumSupportedVersion|incoherent'
    }
    foreach ($version in @('1.0.4.7','1.0.4.6','0.9.0.0')) {
        Case ('Official legacy route is checked against its manifest '+$version) {
            Reset-Case
            (State).Text=(@{latestVersion=$version;minimumSupportedVersion='0.9.0.0'} | ConvertTo-Json -Compress)
            $r=Resolve-Download
            Assert ($r.DownloadUrl -eq 'https://driverhub.asus.com/download/ASUS-DriverHub-Installer.exe') 'Seuil du contrat officiel incorrect.'
            Assert ($r.Version -eq $version) 'Version de comparaison perdue.'
        }
    }
    Case 'Manifest minimum may be absent without inventing an older version' {
        Reset-Case;(State).Text='{"latestVersion":"1.0.7.1"}'
        $r=Resolve-Download
        Assert ($r.Version -eq '1.0.7.1' -and -not $r.MinimumSupportedVersion) 'Version absente inventee.'
    }
    foreach ($text in @(
        '{}','{"latestVersion":""}','{"latestVersion":"1.0.7"}',
        '{"latestVersion":"1.0.7.1-beta"}','{"latestVersion":"1.0.7.1/../../old"}',
        '{"latestVersion":"https://example.invalid/file.exe"}',
        '{"latestVersion":"-1.0.7.1"}','{"latestVersion":"2147483648.0.0.0"}',
        '{"latestVersion":" 1.0.7.1"}'
    )) {
        Case ('Malformed or unsafe latest version rejected: '+$text) {
            Reset-Case;(State).Text=$text
            Expect-Failure { Resolve-Download } 'latestVersion|invalide'
            Assert ((State).HttpCalls -eq 1 -and (State).AuditCalls -eq 0) 'Repli vers un ancien fichier effectue.'
        }
    }
    foreach ($minimum in @('1.0.8.0','1.0.7','2147483648.0.0.0','1.0.7.1/old')) {
        Case ('Invalid minimum version rejected: '+$minimum) {
            Reset-Case
            (State).Text=(@{latestVersion='1.0.7.1';minimumSupportedVersion=$minimum} | ConvertTo-Json -Compress)
            Expect-Failure { Resolve-Download } 'minimumSupportedVersion|incoherent'
        }
    }
    Case 'Invalid JSON fails with precise reason and no fallback download' {
        Reset-Case;(State).Text='<html>Unavailable</html>'
        Expect-Failure { Get-FixturePackage } 'JSON illisible'
        Assert ((State).AuditCalls -eq 0 -and (State).HttpCalls -eq 1) 'Ancien fichier choisi apres manifeste invalide.'
    }
    Case 'Manifest HTTP 503 is not hidden by an older installer' {
        Reset-Case;(State).HttpError='Fixture HTTP 503 Service Unavailable'
        Expect-Failure { Get-FixturePackage } 'HTTP 503'
        Assert ((State).AuditCalls -eq 0 -and (State).HttpCalls -eq 1) 'Repli apres erreur du manifeste.'
    }
    Case 'Manifest request permits only the official ASUS host' {
        Reset-Case;[void](Resolve-Download)
        Assert ((State).HttpUrl -eq 'https://driverhub.asus.com/download/ASUS-DriverHub-Installer.json') 'Source officielle non consultee.'
        Assert ((State).HttpHosts.Count -eq 1 -and (State).HttpHosts[0] -eq 'driverhub.asus.com') 'Liste des destinations du manifeste trop large.'
    }
    Case 'Package pipeline verifies signature hash version and discovery metadata' {
        Reset-Case;$r=Get-FixturePackage
        Assert ((Test-Path -LiteralPath $r.Path -PathType Leaf) -and $r.Version -eq '1.0.7.1') 'Fichier ou version non verifie.'
        Assert ($r.SHA256 -eq (Get-FileHash -LiteralPath $r.Path -Algorithm SHA256).Hash) 'Empreinte finale incorrecte.'
        Assert ($r.Discovery.DownloadUrl -eq (State).AuditUrl -and $r.Discovery.Method -eq 'official_asus_json') 'Provenance perdue dans le resultat.'
        Assert ((State).AuditCalls -eq 1 -and (State).Signatures -eq 1 -and -not $r.Audit.Executed -and -not $r.Audit.Installed) 'Telechargement confondu avec installation.'
    }
    Case 'Signed old 1.0.4.8 is rejected when official manifest says 1.0.7.1' {
        Reset-Case;(State).FileVersion='1.0.4.8'
        Expect-Failure { Get-FixturePackage } 'Version ASUS.*differente|version.*manifeste'
        Assert ((State).AuditUrl -match '/1\.0\.7\.1/') 'Lien plus ancien selectionne.'
    }
    Case 'Signed unexpected newer file also fails manifest consistency' {
        Reset-Case;(State).FileVersion='1.0.8.0'
        Expect-Failure { Get-FixturePackage } 'Version ASUS.*differente|version.*manifeste'
    }
    foreach ($version in @('','1.0.7.1-beta','not-a-version')) {
        Case ('Invalid signed FileVersion is refused: '+$version) {
            Reset-Case;(State).FileVersion=$version
            Expect-Failure { Get-FixturePackage } 'Version ASUS.*differente|version.*manifeste'
        }
    }
    Case 'Whitespace in signed FileVersion is normalized' {
        Reset-Case;(State).FileVersion='1.0.7.1            '
        Assert ((Get-FixturePackage).Version -eq '1.0.7.1') 'Espaces de FileVersion non normalises.'
    }
    Case 'File replaced after download fails hash verification' {
        Reset-Case;(State).Replaced=$true
        Expect-Failure { Get-FixturePackage } 'change.*telechargement'
    }
    Case 'Authenticode validation failure is not reported as success' {
        Reset-Case;(State).SignatureError='Fixture Authenticode signature invalid'
        Expect-Failure { Get-FixturePackage } 'Authenticode.*invalid'
    }
    Case 'Interrupted download propagates without claiming a package' {
        Reset-Case;(State).AuditError='Fixture telechargement interrompu : longueur incomplete'
        Expect-Failure { Get-FixturePackage } 'interrompu.*incomplete'
        Assert ((State).Signatures -eq 0) 'Signature presentee comme verifiee apres interruption.'
    }
    foreach ($count in @(0,2)) {
        Case ('Missing or ambiguous executable count '+$count+' is refused') {
            Reset-Case;(State).FileCount=$count
            Expect-Failure { Get-FixturePackage } 'ambigu|executables'
        }
    }
    Case 'ASRock profile contains real APP Shop application executable' {
        $p=& $module { Get-VutProfile ASRock }
        Assert ($p.FileNames -contains 'AsrAPPShop.exe') 'Executable reel ASRock absent du profil.'
    }
    Case 'ASRock exact and versioned ARP names are accepted without case sensitivity' {
        foreach ($name in @('ASRock APP Shop','APP Shop v2.0.0.4','app shop V2.0.0.4')) {
            $accepted=& $module { param($n) Test-VutApplicationName -Profile (Get-VutProfile ASRock) -DisplayName $n } $name
            Assert $accepted ('Nom ARP ASRock officiel refuse : '+$name)
        }
    }
    Case 'ASRock ARP name excludes SDK paths invalid versions suffixes and other vendors' {
        foreach ($name in @('APP Shop SDK','APP Shop v2.0.0.4 SDK','C:\APP Shop v2.0.0.4','APP Shop v2.0.4','APP Shop v2.0.0.4-beta','APP Shop v2147483648.0.0.0',"APP Shop v2.0.0.4`n")) {
            $accepted=& $module { param($n) Test-VutApplicationName -Profile (Get-VutProfile ASRock) -DisplayName $n } $name
            Assert (-not $accepted) ('Nom ARP ambigu ou malforme accepte : '+$name)
        }
        foreach ($vendor in @('MSI','ASUS','GIGABYTE')) {
            $accepted=& $module { param($v) Test-VutApplicationName -Profile (Get-VutProfile $v) -DisplayName 'APP Shop v2.0.0.4' } $vendor
            Assert (-not $accepted) ('Nom ASRock accepte dans le profil '+$vendor)
        }
    }
    Case 'Discovery and download never invoke a vendor installer' {
        $calls=& $module { $script:DiscoveryInstallerCalls }
        Assert ($calls -eq 0) 'Un installateur constructeur a ete appele.'
    }
} finally {
    Remove-Module VendorUtility
    Remove-Item -LiteralPath $fixture -Recurse -Force
}

# Reload to discard every simulation seam before the explicitly requested live audit.
Import-Module $modulePath -Force
$module=Get-Module VendorUtility
if ($Live) {
    $started=[DateTime]::UtcNow
    try {
        if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or $PSVersionTable.PSVersion.Major -ne 5) {
            throw 'Verification reelle exige Windows natif avec Windows PowerShell 5.1.'
        }
        $directory=Join-Path $OutputDirectory ('live-asus-'+[guid]::NewGuid().ToString('N'))
        $package=& $module { param($d) Get-VutPackage -Profile (Get-VutProfile ASUS) -Directory $d } $directory
        Assert ((Test-Path -LiteralPath $package.Path -PathType Leaf) -and $package.Audit.Status -eq 'download_and_signed_executables_verified') 'Telechargement reel non verifie.'
        Assert ($package.Audit.Bytes -gt 0 -and $package.Audit.Bytes -eq $package.Audit.ExpectedBytes) 'Longueur reelle incomplete ou non verifiable.'
        Assert ($package.Audit.Payloads.Count -eq 1 -and $package.Audit.Payloads[0].Status -eq 'Valid') 'Signature Authenticode reelle invalide.'
        Assert ($package.Version -eq $package.Discovery.Version -and -not $package.Audit.Executed -and -not $package.Audit.Installed) 'Version reelle non coherente ou installateur execute.'
        $script:liveResult=[pscustomobject]@{
            Status='download_and_signature_verified';Mode='real';Version=$package.Version
            SHA256=$package.SHA256;Signer=$package.Audit.Payloads[0].Signer
            Bytes=$package.Audit.Bytes;ExpectedBytes=$package.Audit.ExpectedBytes
            ManifestUrl=$package.Discovery.ManifestUrl;DownloadUrl=$package.Discovery.DownloadUrl
            FinalUrl=$package.Audit.FinalUrl;Method=$package.Discovery.Method
            Seconds=[Math]::Round(([DateTime]::UtcNow-$started).TotalSeconds,2)
            Installed=$false;VendorInstallerExecuted=$false
        }
        $cases.Add([pscustomobject]@{Name='Real official ASUS download signature and version on Windows 5.1';Mode='real';Result='passed';Error=''})
        Write-Host ('ASUS reel : '+$package.Version+' ; '+$package.Audit.Bytes+' octets ; signature valide ; aucun installateur execute.')
    } catch {
        $script:liveResult=[pscustomobject]@{Status='failed';Mode='real';Reason=$_.Exception.Message;Installed=$false;VendorInstallerExecuted=$false}
        $cases.Add([pscustomobject]@{Name='Real official ASUS download signature and version on Windows 5.1';Mode='real';Result='failed';Error=$_.Exception.Message})
        Write-Warning ('ASUS reel : '+$_.Exception.Message)
    }
}
$failed=@($cases | Where-Object Result -eq 'failed')
$report=[pscustomobject]@{
    Kind='utility_discovery_tests';Cases=$cases.Count;Assertions=$script:assertions
    Passed=($cases.Count-$failed.Count);Failed=$failed.Count
    SimulatedCases=@($cases | Where-Object Mode -eq 'simulation').Count
    RealCases=@($cases | Where-Object Mode -eq 'real').Count
    VendorInstallerExecuted=$false;Installed=$false
    Results=@($cases.ToArray());Live=$script:liveResult
}
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'discovery-tests.json') -Encoding UTF8
& $module { param($r) Write-MbxEvidence -Kind 'utility_discovery_tests' -Data $r } $report
Write-Host ('Discovery tests: '+$report.Passed+'/'+$report.Cases+' passes ; '+$report.Assertions+' assertions ; '+$report.Failed+' echec(s).')
if ($failed.Count) { exit 1 }
