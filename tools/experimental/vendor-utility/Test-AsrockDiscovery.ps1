#requires -Version 5.1
[CmdletBinding()]
param([switch]$Live,[string]$OutputDirectory=(Join-Path $PSScriptRoot 'reports/asrock-discovery-tests'))
$ErrorActionPreference='Stop'
[void](New-Item -ItemType Directory -Path $OutputDirectory -Force)
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
$cases=New-Object 'System.Collections.Generic.List[object]'
$script:assertions=0
$script:liveResult=$null
$baseModulePath=Join-Path $PSScriptRoot '../motherboard/MotherboardExperiment.psm1'
$discoveryPath=Join-Path $PSScriptRoot 'VendorDiscovery.Asrock.ps1'
$fixtureModule=New-Module -Name AsrockDiscoveryFixture -ArgumentList $baseModulePath,$discoveryPath -ScriptBlock {
    param($basePath,$sourcePath)
    Set-StrictMode -Version 2
    Import-Module $basePath -Force
    . $sourcePath
    function script:Invoke-MbxHttp {
        [CmdletBinding()]
        param([string]$Url,[string[]]$Hosts,[int]$TimeoutSeconds,[long]$MaxBytes)
        $script:Fixture.Calls+=,[pscustomobject]@{Url=$Url;Hosts=@($Hosts);MaxBytes=$MaxBytes}
        if ($script:Fixture.HttpError -and ($script:Fixture.ErrorAt -eq 0 -or $script:Fixture.Calls.Count -eq $script:Fixture.ErrorAt)) { throw $script:Fixture.HttpError }
        $text=if ($Url -eq 'https://download.asrock.com/setup/Browser.xml') { $script:Fixture.Browser } else { $script:Fixture.Manifest }
        return [pscustomobject]@{Text=$text;Url=$Url;HttpStatus=200}
    }
    function script:Invoke-VutInstallerProcess { throw 'Installateur reel interdit dans les tests de detection.' }
}
function Assert($Condition,[string]$Message) { $script:assertions++;if (-not $Condition) { throw $Message } }
function Case([string]$Name,[scriptblock]$Body) {
    try { & $Body;$cases.Add([pscustomobject]@{Name=$Name;Mode='simulation';Result='passed';Error=''}) }
    catch { $cases.Add([pscustomobject]@{Name=$Name;Mode='simulation';Result='failed';Error=$_.Exception.Message});Write-Warning ($Name+': '+$_.Exception.Message) }
}
function Expect-Failure([scriptblock]$Body,[string]$Pattern) {
    $message='';try { & $Body | Out-Null } catch { $message=$_.Exception.Message }
    Assert ([bool]$message) 'Erreur attendue non signalee.'
    Assert ($message -match $Pattern) ('Cause inattendue : '+$message)
}
function New-Entry {
    param([string]$Version='2.0.0.9',[string]$Hash=('A'*64),[string]$Url='',
        [string]$Exe='', [string]$Parameters='/VerySilent',[string[]]$Systems=@('Windows 10 64bit','Windows 11 64bit'))
    if (-not $Url) { $Url='/Utility/Others/APPShop(v'+$Version+').zip' }
    if (-not $Exe) { $Exe='APPShop(v'+$Version+')/APPShopSetup(v'+$Version+').exe' }
    $files=($Systems | ForEach-Object { '<File OS="'+[Security.SecurityElement]::Escape($_)+'" Size="4.5MB">'+[Security.SecurityElement]::Escape($Url)+'</File>' }) -join ''
    return '<Others Title="ASRock APP Shop" Version="'+[Security.SecurityElement]::Escape($Version)+'" Date="10/1/2026"><Description>APP Shop</Description><HASH>'+[Security.SecurityElement]::Escape($Hash)+'</HASH>'+$files+'<FileExecute>'+[Security.SecurityElement]::Escape($Exe)+'</FileExecute><FileParameter>'+[Security.SecurityElement]::Escape($Parameters)+'</FileParameter></Others>'
}
function New-Manifest([string]$Entries=(New-Entry),[string]$Model='B650M Pro RS') {
    return '<?xml version="1.0" encoding="utf-8"?><LiveUpdate Model="'+[Security.SecurityElement]::Escape($Model)+'"><Download URL="URL1"><URL1>https://download.asrock.com</URL1></Download><Utility>'+$Entries+'</Utility></LiveUpdate>'
}
function State { & $fixtureModule { $script:Fixture } }
function Reset-Case {
    $manifest=New-Manifest
    & $fixtureModule {
        param($text)
        $script:Fixture=[pscustomobject]@{
            Browser='<?xml version="1.0" encoding="utf-8"?><Root><Updates><Item Name="AsrAPPShop"><!-- <File Version="99.0.0.0">/old.exe</File> --></Item></Updates><SupportModel><Item Model="B650M Pro RS"><File Name="Config">/Config/Setup.txt</File></Item><Item Model="Z270 Extreme4" /></SupportModel></Root>'
            Manifest=$text;HttpError='';ErrorAt=0;Calls=@()
        }
    } $manifest
}
function Resolve-Download([string]$Model='B650M Pro RS',[string]$TargetOs='Windows 11 64bit') {
    & $fixtureModule { param($m,$os) Resolve-VutAsrockDownload -Model $m -TargetOs $os } $Model $TargetOs
}
try {
    Case 'PowerShell syntax is valid' {
        foreach ($path in @($PSCommandPath,$discoveryPath)) {
            $tokens=$null;$errors=$null;[void][Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
            Assert (@($errors).Count -eq 0) ('Syntaxe invalide : '+$path)
        }
    }
    Case 'Faithful official XML selects current APP Shop and records provenance' {
        Reset-Case;$r=Resolve-Download
        Assert ($r.Version -eq '2.0.0.9' -and $r.Model -ceq 'B650M Pro RS') 'Version ou modele incorrect.'
        Assert ($r.DownloadUrl -eq 'https://download.asrock.com/Utility/Others/APPShop(v2.0.0.9).zip') 'URL constructeur incorrecte.'
        Assert ($r.ArchiveSHA256 -ceq ('A'*64) -and $r.InstallerParameters -eq '/VerySilent') 'Contrat officiel perdu.'
        Assert ($r.InstallerRelativePath -ceq 'APPShop(v2.0.0.9)/APPShopSetup(v2.0.0.9).exe') 'Chemin interne incorrect.'
        Assert ($r.Method -eq 'official_asrock_model_xml' -and $r.ManifestUrl.EndsWith('Model=B650M%20Pro%20RS')) 'Provenance absente.'
        Assert ((State).Calls.Count -eq 2 -and (State).Calls[0].Hosts.Count -eq 1 -and (State).Calls[1].Hosts[0] -eq 'www.asrock.com') 'Frontiere HTTP inattendue.'
    }
    Case 'Model comparison trims and ignores case while retaining canonical name' {
        Reset-Case;$r=Resolve-Download '  b650m pro rs  '
        Assert ($r.RequestedModel -ceq 'b650m pro rs' -and $r.Model -ceq 'B650M Pro RS') 'Modele canonique non preserve.'
    }
    Case 'Numeric version comparison selects 1.10 over 1.9' {
        Reset-Case;(State).Manifest=New-Manifest ((New-Entry '1.9')+(New-Entry '1.10'))
        $r=Resolve-Download;Assert ($r.Version -eq '1.10' -and $r.DownloadUrl.EndsWith('APPShop(v1.10).zip')) 'Comparaison lexicographique ou ancienne version.'
    }
    Case 'Newest active release wins over older archives regardless of document order' {
        Reset-Case;(State).Manifest=New-Manifest ((New-Entry '2.0.0.9')+(New-Entry '2.0.0.4')+(New-Entry '1.3')+(New-Entry '1.2'))
        Assert ((Resolve-Download).Version -eq '2.0.0.9') 'Archive ancienne selectionnee.'
    }
    Case 'Commented higher version is ignored by the XML parser' {
        Reset-Case;(State).Manifest=New-Manifest ('<!--'+(New-Entry '99.0.0.0')+'-->'+(New-Entry))
        Assert ((Resolve-Download).Version -eq '2.0.0.9') 'Version commentee retenue.'
    }
    Case 'Newest OS-incompatible version never falls back to an older compatible release' {
        Reset-Case;(State).Manifest=New-Manifest ((New-Entry '2.0.0.4')+(New-Entry -Version '2.0.0.9' -Systems @('Windows 10 64bit')))
        Expect-Failure { Resolve-Download } 'derniere version.*non proposee.*aucun repli'
    }
    Case 'Same latest release split into OS-specific entries selects only the requested OS' {
        Reset-Case;(State).Manifest=New-Manifest ((New-Entry -Systems @('Windows 10 64bit'))+(New-Entry -Systems @('Windows 11 64bit')))
        Assert ((Resolve-Download).Version -eq '2.0.0.9') 'Version actuelle compatible masquee par un autre noeud OS.'
        Assert ((Resolve-Download 'B650M Pro RS' 'Windows 10 64bit').TargetOs -eq 'Windows 10 64bit') 'Mauvais noeud OS selectionne.'
    }
    Case 'Supported board may still be unsupported on Windows 11' {
        Reset-Case;(State).Manifest=New-Manifest (New-Entry -Systems @('Windows 7','Windows 7 64bit','Windows 10 64bit')) 'Z270 Extreme4'
        Expect-Failure { Resolve-Download 'Z270 Extreme4' } 'non proposee'
        Assert ((Resolve-Download 'Z270 Extreme4' 'Windows 10 64bit').Version -eq '2.0.0.9') 'Windows 10 explicitement pris en charge rejete.'
    }
    Case 'Unknown board fails before querying a catalog' {
        Reset-Case;Expect-Failure { Resolve-Download 'B650M Pro RS WiFi' } 'modele non present'
        Assert ((State).Calls.Count -eq 1) 'Correspondance approximative ou requete inutile.'
    }
    Case 'Root catalog model mismatch rejects manufacturer-only compatibility' {
        Reset-Case;(State).Manifest=New-Manifest (New-Entry) 'B650M Pro RS WiFi'
        Expect-Failure { Resolve-Download } 'modele du catalogue.*different'
    }
    Case 'Fatal1ty alias is not silently invented' {
        Reset-Case;(State).Manifest=New-Manifest (New-Entry) 'Fatal1ty B650M Pro RS'
        Expect-Failure { Resolve-Download } 'aucun alias'
    }
    Case 'Duplicate identical model records only establish membership' {
        Reset-Case;(State).Browser=(State).Browser.Replace('</SupportModel>','<Item Model="B650M Pro RS"><File Name="Config">/Other/Setup.txt</File></Item></SupportModel>')
        Assert ((Resolve-Download).Version -eq '2.0.0.9') 'Presence non ambigue rejetee.'
    }
    Case 'HTTP 200 catalog without APP Shop is not treated as success' {
        Reset-Case;(State).Manifest=New-Manifest '<Others Title="Other Utility"><Description>APP Shop helper</Description></Others>'
        Expect-Failure { Resolve-Download } 'APP Shop absent'
    }
    Case 'Driver BIOS and advertisement entries cannot become APP Shop candidates' {
        Reset-Case;$falseEntry=New-Entry '99.0.0.0'
        (State).Manifest=(New-Manifest).Replace('</LiveUpdate>','<Bios>'+ $falseEntry+'</Bios><Drivers>'+$falseEntry+'</Drivers><Advertisements>'+$falseEntry+'</Advertisements></LiveUpdate>')
        Assert ((Resolve-Download).Version -eq '2.0.0.9') 'Categorie BIOS/pilotes/publicite utilisee.'
        (State).Manifest=(State).Manifest.Replace('<Utility>'+(New-Entry)+'</Utility>','<Utility />')
        Expect-Failure { Resolve-Download } 'APP Shop absent'
    }
    Case 'Identical repeated release entries remain deterministic' {
        Reset-Case;(State).Manifest=New-Manifest ((New-Entry)+(New-Entry))
        Assert ((Resolve-Download).Version -eq '2.0.0.9') 'Double identique traite comme conflit.'
    }
    Case 'Conflicting hashes for the latest release are ambiguous' {
        Reset-Case;(State).Manifest=New-Manifest ((New-Entry)+(New-Entry -Hash ('B'*64)))
        Expect-Failure { Resolve-Download } 'selection ambigue'
    }
    foreach ($badVersion in @('','2.0.0.9-beta','1.2.3.4.5','2147483648.1','../2.0.0.9')) {
        Case ('Invalid release version rejected: '+$badVersion) {
            Reset-Case;(State).Manifest=New-Manifest (New-Entry -Version $badVersion)
            Expect-Failure { Resolve-Download } 'version.*invalide'
        }
    }
    foreach ($badHash in @('','ABC',('G'*64),('A'*63),('A'*65))) {
        Case ('Invalid SHA256 rejected: '+$badHash.Length) {
            Reset-Case;(State).Manifest=New-Manifest (New-Entry -Hash $badHash)
            Expect-Failure { Resolve-Download } 'SHA256'
        }
    }
    foreach ($badPath in @('../APPShopSetup.exe','C:/APPShopSetup.exe','/APPShop(v2.0.0.9)/APPShopSetup(v2.0.0.9).exe','APPShop(v2.0.0.9)/APPShopSetup(v2.0.0.4).exe','APPShop(v2.0.0.9)/other.exe')) {
        Case ('Unsafe or inconsistent inner executable rejected: '+$badPath) {
            Reset-Case;(State).Manifest=New-Manifest (New-Entry -Exe $badPath)
            Expect-Failure { Resolve-Download } 'chemin executable'
        }
    }
    foreach ($badUrl in @('http://download.asrock.com/Utility/Others/APPShop(v2.0.0.9).zip','https://example.invalid/Utility/Others/APPShop(v2.0.0.9).zip','https://download.asrock.com.evil.invalid/Utility/Others/APPShop(v2.0.0.9).zip','https://download.asrock.com/Utility/Others/APPShop(v2.0.0.4).zip','https://download.asrock.com/Utility/Others/APPShop(v2.0.0.9).zip?fallback=old','https://user@download.asrock.com/Utility/Others/APPShop(v2.0.0.9).zip','/Utility/Others/../Others/APPShop(v2.0.0.9).zip','/Utility/Others/APPShop%2ev2.0.0.9.zip')) {
        Case ('Unsafe or old download URL rejected: '+$badUrl) {
            Reset-Case;(State).Manifest=New-Manifest (New-Entry -Url $badUrl)
            Expect-Failure { Resolve-Download } 'URL.*(incoherent|autorise)'
        }
    }
    Case 'Absolute official URL and escaped parentheses are accepted' {
        Reset-Case;(State).Manifest=New-Manifest (New-Entry -Url 'https://download.asrock.com/Utility/Others/APPShop%28v2.0.0.9%29.zip')
        Assert ((Resolve-Download).Version -eq '2.0.0.9') 'URL officielle encodee rejetee.'
    }
    foreach ($badParameters in @('/VerySilent /IgnoreChkEZDrv','/EZDrvInstaller','/silent','')) {
        Case ('Unexpected installer parameter rejected: '+$badParameters) {
            Reset-Case;(State).Manifest=New-Manifest (New-Entry -Parameters $badParameters)
            Expect-Failure { Resolve-Download } 'parametres.*inattendus'
        }
    }
    foreach ($position in @(1,2)) {
        Case ('HTTP 503 at request '+$position+' has no historical fallback') {
            Reset-Case;(State).HttpError='HTTP 503 Service Unavailable';(State).ErrorAt=$position
            Expect-Failure { Resolve-Download } 'HTTP 503'
            Assert ((State).Calls.Count -eq $position) 'Tentative de repli ancien.'
        }
    }
    foreach ($source in @('Browser','Manifest')) {
        Case ('Bot protection HTTP 200 rejected at '+$source) {
            Reset-Case;(State).$source='<html><body>Request unsuccessful. Incapsula</body></html>'
            Expect-Failure { Resolve-Download } 'structure Browser|modele du catalogue'
        }
        Case ('Malformed XML rejected at '+$source) {
            Reset-Case;(State).$source='<Root><broken>'
            Expect-Failure { Resolve-Download } 'XML officiel invalide'
        }
    }
    Case 'DTD and external entities are prohibited' {
        Reset-Case;(State).Browser='<!DOCTYPE Root [<!ENTITY x SYSTEM "file:///never-read">]><Root><SupportModel>&x;</SupportModel></Root>'
        Expect-Failure { Resolve-Download } 'XML officiel invalide'
    }
    Case 'Unsupported OS fails before any network access' {
        Reset-Case;Expect-Failure { Resolve-Download 'B650M Pro RS' 'Windows11 64bit' } 'systeme cible non autorise'
        Assert ((State).Calls.Count -eq 0) 'Acces reseau pour un systeme non autorise.'
    }
} finally { Remove-Module AsrockDiscoveryFixture -ErrorAction SilentlyContinue }

if ($Live) {
    $started=[DateTime]::UtcNow
    try {
        if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or $PSVersionTable.PSVersion.Major -ne 5) { throw 'Verification reelle exige Windows PowerShell 5.1 natif.' }
        Import-Module (Join-Path $PSScriptRoot 'VendorUtility.psm1') -Force
        $module=Get-Module VendorUtility
        $directory=Join-Path $OutputDirectory ('live-asrock-'+[guid]::NewGuid().ToString('N'))
        $package=& $module { param($d) Get-VutPackage -Profile (Get-VutProfile ASRock -BoardModel 'B650M Pro RS' -TargetOs 'Windows 11 64bit') -Directory $d } $directory
        Assert ((Test-Path -LiteralPath $package.Path -PathType Leaf) -and $package.Audit.Status -eq 'download_and_signed_executables_verified') 'Telechargement reel non confirme.'
        Assert ($package.Audit.Bytes -gt 0 -and $package.Audit.Bytes -eq $package.Audit.ExpectedBytes) 'Longueur reelle incomplete.'
        Assert ($package.Audit.Payloads.Count -eq 1 -and $package.Audit.Payloads[0].Status -eq 'Valid') 'Signature Authenticode reelle invalide.'
        Assert ($package.Version -eq $package.Discovery.Version -and $package.Discovery.Method -eq 'official_asrock_model_xml') 'Version source et fichier incoherents.'
        Assert (-not $package.Audit.Executed -and -not $package.Audit.Installed) 'Un installateur constructeur a ete execute.'
        Assert ($package.Audit.SHA256 -eq $package.Discovery.ArchiveSHA256) 'Empreinte ZIP differente de la source officielle.'
        $script:liveResult=[pscustomobject]@{
            Status='download_and_signature_verified';Mode='real';Version=$package.Version;Model=$package.Discovery.Model
            TargetOs=$package.Discovery.TargetOs;SHA256=$package.SHA256;ArchiveSHA256=$package.Discovery.ArchiveSHA256
            Signer=$package.Audit.Payloads[0].Signer;Bytes=$package.Audit.Bytes;ExpectedBytes=$package.Audit.ExpectedBytes
            ManifestUrl=$package.Discovery.ManifestUrl;ModelSourceUrl=$package.Discovery.ModelSourceUrl
            DownloadUrl=$package.Discovery.DownloadUrl;FinalUrl=$package.Audit.FinalUrl;Method=$package.Discovery.Method
            InstallerParameters=$package.Discovery.InstallerParameters
            Seconds=[Math]::Round(([DateTime]::UtcNow-$started).TotalSeconds,2);Installed=$false;VendorInstallerExecuted=$false
        }
        $cases.Add([pscustomobject]@{Name='Real official ASRock model current download SHA256 and Authenticode on Windows 5.1';Mode='real';Result='passed';Error=''})
        Write-Host ('ASRock reel : '+$package.Version+' ; '+$package.Audit.Bytes+' octets ; signature valide ; aucun installateur execute.')
    } catch {
        $script:liveResult=[pscustomobject]@{Status='failed';Mode='real';Reason=$_.Exception.Message;Installed=$false;VendorInstallerExecuted=$false}
        $cases.Add([pscustomobject]@{Name='Real official ASRock model current download SHA256 and Authenticode on Windows 5.1';Mode='real';Result='failed';Error=$_.Exception.Message})
        Write-Warning ('ASRock reel : '+$_.Exception.Message)
    }
}
$failed=@($cases | Where-Object Result -eq 'failed')
$report=[pscustomobject]@{
    Kind='utility_asrock_discovery_tests';Cases=$cases.Count;Assertions=$script:assertions;Passed=($cases.Count-$failed.Count);Failed=$failed.Count
    SimulatedCases=@($cases | Where-Object Mode -eq 'simulation').Count;RealCases=@($cases | Where-Object Mode -eq 'real').Count
    VendorInstallerExecuted=$false;Installed=$false;Results=@($cases.ToArray());Live=$script:liveResult
}
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'asrock-discovery-tests.json') -Encoding UTF8
Import-Module $baseModulePath -Force
Write-MbxEvidence -Kind 'utility_asrock_discovery_tests' -Data $report
Write-Host ('ASRock discovery tests : '+$report.Passed+'/'+$report.Cases+' passes ; '+$report.Assertions+' assertions ; '+$report.Failed+' echec(s).')
if ($failed.Count) { exit 1 }
