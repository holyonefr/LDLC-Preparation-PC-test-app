#requires -Version 5.1
[CmdletBinding()]
param([string]$OutputDirectory=(Join-Path $PSScriptRoot 'reports/package-verification-tests'))
$ErrorActionPreference='Stop'
[void](New-Item -ItemType Directory -Path $OutputDirectory -Force)
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression
$cases=New-Object 'System.Collections.Generic.List[object]'
$script:assertions=0
$fixtureRoot=Join-Path $OutputDirectory ('inert-fixtures-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $fixtureRoot)
Import-Module (Join-Path $PSScriptRoot 'VendorUtility.psm1') -Force
$module=Get-Module VendorUtility
# Exercise the actual Get-VutPackage and profile/version helpers. Only discovery,
# downloaded audit data and Authenticode are doubled. ZIPs and hashes are real;
# every .exe fixture contains inert text and is never executed.
& $module {
    function script:Resolve-VutAsrockDownload {
        param([string]$Model,[string]$TargetOs)
        $script:Fixture.DiscoveryCalls++
        if ($Model -cne 'B650M Pro RS' -or $TargetOs -cne 'Windows 11 64bit') { throw 'Fixture : modele ou systeme cible perdu.' }
        return $script:Fixture.Discovery
    }
    function script:Resolve-VutAsusDownload {
        $script:Fixture.DiscoveryCalls++
        return $script:Fixture.Discovery
    }
    function script:Invoke-MbxUtilityAudit {
        param($Tool,[string]$DownloadUrl,[string]$OutputDirectory)
        $f=$script:Fixture
        $f.AuditCalls++
        if ($DownloadUrl -cne $f.Discovery.DownloadUrl) { throw 'Fixture : URL officielle resolue perdue.' }
        if ($f.AuditError) { throw $f.AuditError }
        $owned=Join-Path $OutputDirectory ([guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $owned)
        $payload=Join-Path $owned 'payload-0.exe'
        $bytes=[Text.Encoding]::UTF8.GetBytes(('INERT TEST DATA; NEVER EXECUTE; '*50))
        if (-not $f.NoExecutable) { [IO.File]::WriteAllBytes($payload,$bytes) }
        if ($f.ExtraExecutable) { [IO.File]::WriteAllBytes((Join-Path $owned 'payload-1.exe'),$bytes) }
        $payloadHash=[BitConverter]::ToString(([Security.Cryptography.SHA256]::Create()).ComputeHash($bytes)).Replace('-','')
        $archiveHash=''
        if ($Tool.Vendor -eq 'ASRock' -and -not $f.NoArchive) {
            $zipPath=Join-Path $owned 'APPShop(v2.0.0.9).zip'
            $zip=[IO.Compression.ZipFile]::Open($zipPath,[IO.Compression.ZipArchiveMode]::Create)
            try {
                foreach ($name in $f.EntryNames) {
                    $entry=$zip.CreateEntry($name)
                    $stream=$entry.Open()
                    try { $stream.Write($bytes,0,$bytes.Length) } finally { $stream.Dispose() }
                }
            } finally { $zip.Dispose() }
            $archiveHash=(Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
            $f.Discovery.ArchiveSHA256=$archiveHash
            if ($f.ExtraArchive) { Copy-Item -LiteralPath $zipPath -Destination (Join-Path $owned 'duplicate.zip') }
        }
        if ($f.BadArchiveHash) { $archiveHash='F'*64 }
        $payloads=@([pscustomobject]@{SHA256=$payloadHash;Bytes=($bytes.Length+$f.LengthOffset);Status='Valid';FileVersion=$f.FileVersion})
        if ($f.MultiplePayloads) { $payloads+=,[pscustomobject]@{SHA256=$payloadHash;Bytes=$bytes.Length;Status='Valid';FileVersion=$f.FileVersion} }
        return [pscustomobject]@{SHA256=$archiveHash;Payloads=$payloads;Executed=$false;Installed=$false;Status='fixture_audit_only'}
    }
    function script:Test-MbxSignedPayload {
        param([string]$Path,[string[]]$Signers)
        $f=$script:Fixture
        $f.SignatureCalls++
        if ($f.SignatureError) { throw $f.SignatureError }
        if ($f.ChangePayload) { [IO.File]::AppendAllText($Path,'ACTUAL MUTATION AFTER AUDIT') }
        return [pscustomobject]@{SHA256=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash;FileVersion=$f.FileVersion;Status='simulated_valid_signature'}
    }
}
function Assert($Condition,[string]$Message) { $script:assertions++;if (-not $Condition) { throw $Message } }
function Case([string]$Name,[scriptblock]$Body) {
    try { & $Body;$cases.Add([pscustomobject]@{Name=$Name;Mode='simulation';Result='passed';Error=''}) }
    catch { $cases.Add([pscustomobject]@{Name=$Name;Mode='simulation';Result='failed';Error=$_.Exception.Message});Write-Warning ($Name+': '+$_.Exception.Message) }
}
function State { & $module { $script:Fixture } }
function Reset-Case([string]$Vendor='ASRock',[string]$Version='2.0.0.9') {
    $directory=Join-Path $fixtureRoot ([guid]::NewGuid().ToString('N'))
    & $module {
        param($v,$version,$directory)
        $script:Fixture=[pscustomobject]@{
            Vendor=$v;Directory=$directory;FileVersion=$version
            Discovery=[pscustomobject]@{
                Version=$version;ArchiveSHA256='';InstallerRelativePath='APPShop(v2.0.0.9)/APPShopSetup(v2.0.0.9).exe'
                DownloadUrl=if ($v -eq 'ASRock') { 'https://download.asrock.com/Utility/Others/APPShop(v2.0.0.9).zip' } else { 'https://driverhub.asus.com/download/'+$version+'/ASUS-DriverHub-Installer.exe' }
                Method='fixture_discovery_only'
            }
            EntryNames=@('APPShop(v2.0.0.9)/APPShopSetup(v2.0.0.9).exe')
            BadArchiveHash=$false;NoArchive=$false;ExtraArchive=$false;LengthOffset=0
            ExtraExecutable=$false;NoExecutable=$false;MultiplePayloads=$false;ChangePayload=$false
            AuditError='';SignatureError='';DiscoveryCalls=0;AuditCalls=0;SignatureCalls=0
        }
    } $Vendor $Version $directory
}
function Get-Package {
    & $module {
        $profile=Get-VutProfile -Vendor $script:Fixture.Vendor -BoardModel 'B650M Pro RS' -TargetOs 'Windows 11 64bit'
        Get-VutPackage -Profile $profile -Directory $script:Fixture.Directory
    }
}
function Expect-Failure([scriptblock]$Body,[string]$Pattern,[int]$SignatureCalls=-1) {
    $message='';try { & $Body | Out-Null } catch { $message=$_.Exception.Message }
    Assert ([bool]$message) 'Erreur attendue non signalee.'
    Assert ($message -match $Pattern) ('Cause inattendue : '+$message)
    if ($SignatureCalls -ge 0) { Assert ((State).SignatureCalls -eq $SignatureCalls) 'Verification Authenticode appelee au mauvais stade.' }
}
try {
    Case 'PowerShell syntax is valid' {
        $tokens=$null;$errors=$null;[void][Management.Automation.Language.Parser]::ParseFile($PSCommandPath,[ref]$tokens,[ref]$errors)
        Assert (@($errors).Count -eq 0) 'Syntaxe PowerShell invalide.'
    }
    Case 'Current ASRock package preserves verified version hash and discovery' {
        Reset-Case;$r=Get-Package
        Assert ($r.Version -ceq '2.0.0.9' -and (Test-Path -LiteralPath $r.Path -PathType Leaf)) 'Fichier courant absent ou mauvaise version.'
        Assert ($r.SHA256 -eq (Get-FileHash -LiteralPath $r.Path -Algorithm SHA256).Hash) 'Empreinte finale incorrecte.'
        Assert ($r.Discovery.ArchiveSHA256 -eq $r.Audit.SHA256 -and $r.Discovery.Method -eq 'fixture_discovery_only') 'Provenance perdue.'
        Assert ((State).DiscoveryCalls -eq 1 -and (State).AuditCalls -eq 1 -and (State).SignatureCalls -eq 1) 'Frontieres appelees plus dune fois ou ancien repli.'
        Assert (-not $r.Audit.Executed -and -not $r.Audit.Installed) 'Fixture presentee comme une installation reelle.'
    }
    Case 'ASRock archive SHA256 mismatch blocks before payload verification' {
        Reset-Case;(State).BadArchiveHash=$true
        Expect-Failure { Get-Package } 'Archive ASRock.*SHA256' 0
    }
    Case 'ASRock wrong internal installer path blocks even with valid archive metadata' {
        Reset-Case;(State).EntryNames=@('APPShop(v2.0.0.4)/APPShopSetup(v2.0.0.4).exe')
        Expect-Failure { Get-Package } 'Installateur ASRock interne' 0
    }
    Case 'ASRock duplicate expected ZIP entries are rejected' {
        Reset-Case;(State).EntryNames=@((State).Discovery.InstallerRelativePath,(State).Discovery.InstallerRelativePath)
        Expect-Failure { Get-Package } 'Installateur ASRock interne' 0
    }
    Case 'ASRock internal path comparison does not accept differently cased names' {
        Reset-Case;(State).EntryNames=@((State).Discovery.InstallerRelativePath.ToLowerInvariant())
        Expect-Failure { Get-Package } 'Installateur ASRock interne' 0
    }
    Case 'ASRock ZIP Windows separators normalize to the catalog path' {
        Reset-Case;(State).EntryNames=@((State).Discovery.InstallerRelativePath.Replace('/','\'))
        Assert ((Get-Package).Version -ceq '2.0.0.9') 'Separateurs Windows corrects rejetes.'
    }
    Case 'ASRock ZIP entry length must equal audited payload length' {
        Reset-Case;(State).LengthOffset=1
        Expect-Failure { Get-Package } 'Installateur ASRock interne' 0
    }
    Case 'ASRock missing archive fails explicitly' {
        Reset-Case;(State).NoArchive=$true
        Expect-Failure { Get-Package } 'Archive ASRock absente ou ambigue' 0
    }
    Case 'ASRock multiple archives fail explicitly' {
        Reset-Case;(State).ExtraArchive=$true
        Expect-Failure { Get-Package } 'Archive ASRock absente ou ambigue' 0
    }
    Case 'ASRock multiple audited payloads are rejected before signature recheck' {
        Reset-Case;(State).MultiplePayloads=$true
        Expect-Failure { Get-Package } 'Installateur ASRock interne' 0
    }
    Case 'ASRock additional extracted executable is rejected' {
        Reset-Case;(State).ExtraExecutable=$true
        Expect-Failure { Get-Package } 'Plusieurs executables|ambigu' 0
    }
    Case 'Missing extracted executable is rejected' {
        Reset-Case;(State).NoExecutable=$true
        Expect-Failure { Get-Package } 'Plusieurs executables|ambigu' 0
    }
    Case 'Actual payload mutation after audit changes SHA256 and is rejected' {
        Reset-Case;(State).ChangePayload=$true
        Expect-Failure { Get-Package } 'fichier a change apres' 1
    }
    Case 'ASRock older signed file version cannot pass as current catalog version' {
        Reset-Case;(State).FileVersion='2.0.0.4'
        Expect-Failure { Get-Package } 'Version ASRock.*differente du manifeste' 1
    }
    Case 'ASRock higher unexpected file version also fails catalog equality' {
        Reset-Case;(State).FileVersion='2.0.0.10'
        Expect-Failure { Get-Package } 'Version ASRock.*differente du manifeste' 1
    }
    Case 'Invalid PE file version cannot become a successful package' {
        Reset-Case;(State).FileVersion='not-a-version'
        Expect-Failure { Get-Package } 'Version ASRock.*differente du manifeste' 1
    }
    Case 'File version surrounding whitespace is trimmed after verification' {
        Reset-Case;(State).FileVersion=' 2.0.0.9 '
        Assert ((Get-Package).Version -ceq '2.0.0.9') 'Version complete avec espaces rejetee.'
    }
    Case 'Signature rejection is not converted into a successful download' {
        Reset-Case;(State).SignatureError='Fixture Authenticode : editeur non autorise.'
        Expect-Failure { Get-Package } 'editeur non autorise' 1
    }
    Case 'Interrupted audit is propagated with no signature verification or fallback' {
        Reset-Case;(State).AuditError='Fixture HTTP : telechargement interrompu avant longueur attendue.'
        Expect-Failure { Get-Package } 'telechargement interrompu' 0
        Assert ((State).AuditCalls -eq 1 -and (State).DiscoveryCalls -eq 1) 'Nouvelle tentative ou ancien repli non attendu.'
    }
    Case 'Current ASUS version matching the official discovery is accepted' {
        Reset-Case ASUS '1.0.7.1';$r=Get-Package
        Assert ($r.Version -ceq '1.0.7.1' -and $r.Discovery.Version -ceq $r.Version) 'Version ASUS courante non preservee.'
        Assert ((State).DiscoveryCalls -eq 1 -and (State).SignatureCalls -eq 1) 'Verification ASUS non effectuee.'
    }
    Case 'ASUS legacy flat installer 1.0.4.8 cannot stand in for current 1.0.7.1' {
        Reset-Case ASUS '1.0.7.1';(State).FileVersion='1.0.4.8'
        Expect-Failure { Get-Package } 'Version ASUS.*differente du manifeste' 1
    }
    Case 'ASUS version comparison rejects 1.9 when discovery requires 1.10' {
        Reset-Case ASUS '1.10.0.0';(State).FileVersion='1.9.0.0'
        Expect-Failure { Get-Package } 'Version ASUS.*differente du manifeste' 1
    }
    Case 'ASUS numeric current version 1.10 is accepted' {
        Reset-Case ASUS '1.10.0.0'
        Assert ((Get-Package).Version -ceq '1.10.0.0') 'Version ASUS 1.10 rejetee.'
    }
    Case 'ASUS multiple extracted installers cannot bypass package selection' {
        Reset-Case ASUS '1.0.7.1';(State).ExtraExecutable=$true
        Expect-Failure { Get-Package } 'Plusieurs executables|ambigu' 0
    }
    Case 'ASUS mutated payload is rejected even when the file version matches' {
        Reset-Case ASUS '1.0.7.1';(State).ChangePayload=$true
        Expect-Failure { Get-Package } 'fichier a change apres' 1
    }
} finally {
    Remove-Module VendorUtility -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}
$report=[ordered]@{
    Kind='utility_package_verification_tests';Mode='simulated_audit_and_signature_real_inert_zip_files'
    ActualNetworkRequests=0;ActualVendorInstallations=0;ActualVendorInstallerExecutions=0
    Assertions=$script:assertions;Cases=@($cases.ToArray());Failures=@($cases.ToArray() | Where-Object Result -eq 'failed').Count
}
$report | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $OutputDirectory 'utility-package-verification-tests.json') -Encoding UTF8
Import-Module (Join-Path $PSScriptRoot '../motherboard/MotherboardExperiment.psm1') -Force
Write-MbxEvidence -Kind 'utility_package_verification_tests' -Data $report
if ($report.Failures) { throw "$($report.Failures) scenario(s) de verification de paquet en echec." }
Write-Host "$($cases.Count) scenarios / $script:assertions assertions reussis ; ZIP et empreintes reels, donnees inertes et signatures simulees uniquement."
