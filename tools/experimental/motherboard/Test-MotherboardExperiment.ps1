#requires -Version 5.1
[CmdletBinding()]
param([switch]$Live, [switch]$DownloadAudit, [string]$OutputDirectory=(Join-Path $PSScriptRoot 'reports/tests'))
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'MotherboardExperiment.psm1') -Force
$module=Get-Module MotherboardExperiment
[void](New-Item -ItemType Directory -Path $OutputDirectory -Force)
$results=New-Object 'System.Collections.Generic.List[object]'
$script:assertions=0
function Assert-Mbx($Condition,[string]$Message) { $script:assertions++; if (-not $Condition) { throw $Message } }
function Case-Mbx([string]$Name,[scriptblock]$Body) {
    try { & $Body; $results.Add([pscustomobject]@{ Name=$Name; Result='passed'; Error='' }) }
    catch { $results.Add([pscustomobject]@{ Name=$Name; Result='failed'; Error=$_.Exception.Message }); Write-Warning ($Name+': '+$_.Exception.Message) }
}
function Throws-Mbx([scriptblock]$Body,[string]$Pattern='.') {
    $caught=$null; try { & $Body | Out-Null } catch { $caught=$_.Exception.Message }
    Assert-Mbx ($null -ne $caught -and $caught -match $Pattern) "Echec attendu ($Pattern), obtenu : $caught"
}
function Fixture-Mbx([string]$Vendor='ASUS',[string]$Model='ROG STRIX B650E-F GAMING WIFI',[string]$Revision='1.0') {
    $manufacturer=@{ ASUS='ASUSTeK COMPUTER INC.'; MSI='Micro-Star International Co., Ltd.'; GIGABYTE='Gigabyte Technology Co., Ltd.'; ASRock='ASRock' }[$Vendor]
    return [pscustomobject]@{
        Kind='Simulated'; BaseBoards=@([pscustomobject]@{Manufacturer=$manufacturer;Product=$Model;Revision=$Revision})
        Computers=@([pscustomobject]@{Manufacturer='System manufacturer';Model='System Product Name';PCSystemType=1})
        OperatingSystems=@([pscustomobject]@{ Caption='Microsoft Windows 11 Pro';Version='10.0.22631';BuildNumber='22631';Architecture='64-bit' })
        ChassisTypes=@(3); Bios=@([pscustomobject]@{SMBIOSBIOSVersion='fixture-only'})
    }
}

Case-Mbx 'PowerShell syntax and isolation' {
    foreach ($file in Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps*1') {
        $tokens=$null; $errors=$null
        $ast=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
        Assert-Mbx (@($errors).Count -eq 0) "Syntaxe : $($file.Name)"
        if ($file.Name -in @('MotherboardExperiment.psm1','Invoke-MotherboardExperiment.ps1')) {
            $commands=@($ast.FindAll({param($node) $node -is [Management.Automation.Language.CommandAst]},$true) | ForEach-Object { $_.GetCommandName() })
            Assert-Mbx (@($commands | Where-Object { $_ -match '^(Start-Process|Invoke-Expression|Invoke-CimMethod|Set-CimInstance|Restart-Computer|Install-|Update-|Set-ItemProperty|Install-WindowsUpdates|Install-LDLCGpu)' }).Count -eq 0) 'Commande de mutation systeme dans le prototype.'
        }
    }
}
foreach ($vendor in @('MSI','ASUS','GIGABYTE','ASRock')) {
    Case-Mbx ("Selection simulated $vendor") {
        $r=Resolve-MbxTool (Fixture-Mbx $vendor)
        Assert-Mbx ($r.Vendor -eq $vendor) 'Fabricant incorrect.'
        Assert-Mbx ([bool]$r.Tool) 'Outil candidat absent.'
        Assert-Mbx ($r.Status -eq 'manual_required' -and $r.Compatibility -eq 'unverified') 'Compatibilite inventee.'
        Assert-Mbx (-not $r.CanDownloadForInstallation -and -not $r.CanScanAutomatically -and -not $r.CanInstallDriversAutomatically) 'Automatisation non prouvee autorisee.'
    }
}
Case-Mbx 'Unknown and partial SMBIOS' {
    $i=Fixture-Mbx; $i.BaseBoards[0].Manufacturer='Example vendor'
    Assert-Mbx (-not (Resolve-MbxTool $i).Tool) 'Outil choisi pour fabricant inconnu.'
    $i.BaseBoards=@(); Assert-Mbx (-not (Resolve-MbxTool $i).Tool) 'Outil choisi sans carte mere.'
    $i=Fixture-Mbx; $i.BaseBoards+=$i.BaseBoards[0]
    Assert-Mbx (-not (Resolve-MbxTool $i).Tool) 'Inventaire multicarte arbitrairement resolu.'
}
foreach ($oem in @('Dell Inc.','HP','LENOVO','Acer','An OEM not in a lookup table')) {
    Case-Mbx ("OEM takes precedence $oem") {
        $i=Fixture-Mbx; $i.Computers[0].Manufacturer=$oem
        $r=Resolve-MbxTool $i
        Assert-Mbx (-not $r.Tool -and $r.Reason -match 'OEM') 'Utilitaire retail propose a un PC OEM.'
    }
}
Case-Mbx 'Laptop same manufacturer and convertible' {
    $i=Fixture-Mbx; $i.Computers[0].Manufacturer='ASUS'; $i.Computers[0].PCSystemType=2
    Assert-Mbx (-not (Resolve-MbxTool $i).Tool) 'Portable accepte comme carte mere retail.'
    $i.Computers[0].PCSystemType=1; $i.ChassisTypes=@(31)
    Assert-Mbx (-not (Resolve-MbxTool $i).Tool) 'Convertible accepte.'
}
Case-Mbx 'Real runner-like virtual hardware' {
    $i=Fixture-Mbx; $i.Computers[0].Manufacturer='Microsoft Corporation'; $i.Computers[0].Model='Virtual Machine'
    $r=Resolve-MbxTool $i; Assert-Mbx (-not $r.Tool -and $r.Reason -match 'virtuelle') 'Outil physique choisi sur VM.'
}
Case-Mbx 'Missing revision and unsupported OS never authorize install' {
    $i=Fixture-Mbx -Revision 'To be filled by O.E.M.'
    Assert-Mbx ((Resolve-MbxTool $i).Reason -match 'revision') 'Revision absente acceptee.'
    $i=Fixture-Mbx; $i.OperatingSystems=@()
    Assert-Mbx (-not (Resolve-MbxTool $i).CanDownloadForInstallation) 'Windows absent accepte.'
}
Case-Mbx 'Exact supplied support evidence is not claimed as live proof' {
    $i=Fixture-Mbx
    $e=[pscustomobject]@{Vendor='ASUS';Model=$i.BaseBoards[0].Product;Revision='1.0';OsBuild='22631';Architecture='64-bit';ExplicitSupport=$true;Source='https://www.asus.com/support/'}
    $r=Resolve-MbxTool $i @($e)
    Assert-Mbx ($r.Compatibility -eq 'evidence_supplied_requires_vendor_confirmation' -and -not $r.CanDownloadForInstallation) 'Donnees injectees promues en compatibilite reelle.'
    foreach ($field in @('Model','Revision','OsBuild','Architecture','Source')) {
        $copy=$e | Select-Object *; $copy.$field='different'
        Assert-Mbx ((Resolve-MbxTool $i @($copy)).Compatibility -eq 'unverified') "Correspondance partielle $field acceptee."
    }
}
Case-Mbx 'Numeric version comparison' {
    Assert-Mbx ((ConvertTo-MbxVersion '1.10') -gt (ConvertTo-MbxVersion '1.9')) 'Comparaison lexicale.'
    Assert-Mbx ((ConvertTo-MbxVersion '1.2') -eq (ConvertTo-MbxVersion '1.2.0.0')) 'Normalisation incorrecte.'
    foreach ($v in @('1.2-beta','1.2.3.4.5','latest','','99999999999999.2')) { Assert-Mbx ($null -eq (ConvertTo-MbxVersion $v)) "Version invalide $v acceptee." }
}
$device=[pscustomobject]@{HardwareIDs=@('PCI\VEN_8086&DEV_1234&SUBSYS_1000');DeviceID='fixture-device'}
$installed=[pscustomobject]@{DeviceID='fixture-device';Version='1.9';Provider='Intel'}
function Driver-Mbx([string]$Name='Ethernet',[string]$Version='1.10',[string]$Class='Net') {
    return [pscustomobject]@{Name=$Name;Version=$Version;Class=$Class;Kind='Driver';Provider='Intel';HardwareIDs=@('PCI\VEN_8086&DEV_1234&SUBSYS_1000')}
}
Case-Mbx 'Supported driver categories yield candidates only' {
    foreach ($class in @('System','Net','Bluetooth','MEDIA','USB','HDC','SCSIAdapter','Storage')) {
        $r=@(Select-MbxDriverCandidates @(Driver-Mbx -Class $class) @($device) @($installed))[0]
        Assert-Mbx ($r.Status -eq 'candidate_only' -and -not $r.Installed) 'Faux succes installation.'
    }
}
Case-Mbx 'Security and commercial apps denied by default' {
    foreach ($name in @('Norton','McAfee','Avast','AVG','Kaspersky','Bitdefender','ESET','Trend Micro','BullGuard','Symantec','Windows Defender','Random Gaming Booster','Backup subscription')) {
        $x=Driver-Mbx -Name $name; if ($name -match 'Random|Backup') { $x.Kind='Application' }
        $r=@(Select-MbxDriverCandidates @($x) @($device) @($installed))[0]
        Assert-Mbx ($r.Status -eq 'ignored' -and -not $r.Installed) "Logiciel additionnel $name selectionne."
    }
}
Case-Mbx 'BIOS UEFI and firmware separated and never executed' {
    foreach ($name in @('BIOS update','UEFI update','Intel ME firmware','SSD firmware')) {
        $r=@(Select-MbxDriverCandidates @(Driver-Mbx -Name $name) @($device) @($installed))[0]
        Assert-Mbx ($r.Status -eq 'firmware_manual' -and -not $r.Installed -and -not $r.RebootInitiated) 'Firmware non exclu.'
    }
}
Case-Mbx 'GPU excluded and uncertain drivers need manual verification' {
    foreach ($x in @((Driver-Mbx -Class Display),(Driver-Mbx -Name 'AMD Adrenalin'),(Driver-Mbx -Name 'GeForce driver'))) {
        Assert-Mbx ((@(Select-MbxDriverCandidates @($x) @($device) @($installed)))[0].Status -eq 'ignored') 'Chevauchement GPU.'
    }
    foreach ($v in @('1.9','1.2')) { Assert-Mbx ((@(Select-MbxDriverCandidates @(Driver-Mbx -Version $v) @($device) @($installed)))[0].Status -eq 'up_to_date') 'Retrogradation candidate.' }
    $x=Driver-Mbx; $x.Provider='Different'
    Assert-Mbx ((@(Select-MbxDriverCandidates @($x) @($device) @($installed)))[0].Status -eq 'manual_required') 'Fournisseurs differents compares.'
    $x=Driver-Mbx; $x.HardwareIDs=@('PCI\VEN_FFFF')
    Assert-Mbx ((@(Select-MbxDriverCandidates @($x) @($device) @($installed)))[0].Status -eq 'manual_required') 'Materiel incompatible accepte.'
    Assert-Mbx ((@(Select-MbxDriverCandidates @(Driver-Mbx) @($device) @()))[0].Status -eq 'manual_required') 'Version installee absente ignoree.'
}
Case-Mbx 'Official URL allowlist resists host confusion' {
    Assert-Mbx (Test-MbxOfficialUri 'https://download.msi.com/file.exe' @('msi.com')) 'Sous domaine officiel rejete.'
    foreach ($url in @('http://msi.com/a','https://msi.com.evil.invalid/a','https://evilmsi.com/a','https://msi.com@evil.invalid/a','https://msi.com:444/a','https://user:pass@msi.com/a','file:///tmp/a')) {
        Assert-Mbx (-not (Test-MbxOfficialUri $url @('msi.com'))) "URL dangereuse acceptee $url."
    }
}
Case-Mbx 'Relative entity and direct JavaScript download links' {
    $tool=@(Get-MbxToolDefinitions | Where-Object Vendor -eq MSI)[0]
    $html='<a href="../uti_exe/MSI-Center.zip?a=1&amp;b=2">download</a><a href="https://evil.invalid/MSI-Center.exe">bad</a><script>const x="https://download.msi.com/MSI_Center.exe"</script>'
    $urls=@(Get-MbxDownloadLinks $html 'https://download.msi.com/support/index.html' $tool)
    Assert-Mbx ($urls.Count -eq 2) 'Extraction ambigue ou domaine externe accepte.'
    Assert-Mbx ($urls[0] -eq 'https://download.msi.com/uti_exe/MSI-Center.zip?a=1&b=2') 'Resolution relative ou entites incorrectes.'
    $asus=@(Get-MbxToolDefinitions | Where-Object Vendor -eq ASUS)[0]
    Assert-Mbx ('ASUS_DriverHubInstaller.exe' -match $asus.FilePattern) 'Nom de fichier DriverHub non reconnu.'
}

# Simulated HTTPS transport, exercised through the real HTTP/redirect/download code.
Add-Type -AssemblyName System.Net.Http
if (-not ('MbxFakeHandler' -as [type])) {
    $references=if ($PSVersionTable.PSEdition -eq 'Core') { @(Get-ChildItem (Join-Path $PSHOME 'ref/*.dll') | ForEach-Object { $_.FullName }) } else { @('System.Net.Http.dll') }
    Add-Type -ReferencedAssemblies $references -TypeDefinition @'
using System;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
public class MbxSpec { public int Code; public string Location; public string Kind; public long Length; public string Name; public byte[] Body; }
public class MbxFakeHandler : HttpMessageHandler {
 public static Queue<MbxSpec> Specs = new Queue<MbxSpec>();
 public static List<string> Requests = new List<string>();
 public static byte[] Payload = new byte[2048];
 public static void Reset() { Specs.Clear(); Requests.Clear(); }
 public static void Add(int code,string location,string kind,long length) { Specs.Enqueue(new MbxSpec {Code=code,Location=location,Kind=kind,Length=length}); }
 public static void AddNamed(string name,long length) { Specs.Enqueue(new MbxSpec {Code=200,Location="",Kind="",Length=length,Name=name}); }
 public static void AddText(string text) { var b=System.Text.Encoding.UTF8.GetBytes(text); Specs.Enqueue(new MbxSpec {Code=200,Location="",Kind="",Length=b.Length,Body=b}); }
 protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage req,CancellationToken ct) {
  Requests.Add(req.RequestUri.AbsoluteUri); var s=Specs.Dequeue();
  if(s.Kind=="network") throw new HttpRequestException("simulated connection failure");
  if(s.Kind=="timeout") { var pending=new TaskCompletionSource<HttpResponseMessage>(); ct.Register(()=>pending.TrySetCanceled()); return pending.Task; }
  var r=new HttpResponseMessage((HttpStatusCode)s.Code); r.RequestMessage=req;
  if(s.Location!="") r.Headers.Location=new Uri(s.Location,UriKind.RelativeOrAbsolute);
  r.Content=s.Kind=="interrupt" ? (HttpContent)new StreamContent(new MbxInterruptedStream()) : new ByteArrayContent(s.Body ?? Payload);
  if(s.Length>=0) r.Content.Headers.ContentLength=s.Length;
  if(s.Name!=null) r.Content.Headers.ContentDisposition=new System.Net.Http.Headers.ContentDispositionHeaderValue("attachment") {FileName=s.Name};
  return Task.FromResult(r);
 }
}
public class MbxInterruptedStream : MemoryStream {
 int reads=0;
 public override Task<int> ReadAsync(byte[] b,int o,int c,CancellationToken ct) {
  if(reads++==0) { b[o]=77; return Task.FromResult(1); }
  throw new IOException("simulated stream interruption");
 }
}
'@
}
[MbxFakeHandler]::Payload=New-Object byte[] 2048
& $module { function script:New-MbxHttpHandler { return New-Object MbxFakeHandler } }
$testUrl='https://download.msi.com/MSI-Center.zip'
$temp=Join-Path $OutputDirectory ('transport-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $temp)
try {
    Case-Mbx 'Simulated HTTPS relative redirects and complete body' {
        [MbxFakeHandler]::Reset(); [MbxFakeHandler]::Add(302,'/releases/MSI-Center.zip','',-1); [MbxFakeHandler]::Add(200,'','',2048)
        $p=Join-Path $temp 'complete.zip'; $r=Invoke-MbxHttp $testUrl @('msi.com') -OutFile $p
        Assert-Mbx ($r.Bytes -eq 2048 -and $r.Redirects.Count -eq 2 -and (Get-Item $p).Length -eq 2048) 'Telechargement complet non verifie.'
        Assert-Mbx ([MbxFakeHandler]::Requests[1] -eq 'https://download.msi.com/releases/MSI-Center.zip') 'Redirection relative incorrecte.'
    }
    Case-Mbx 'Simulated HEAD checks metadata without reading a binary body' {
        [MbxFakeHandler]::Reset(); [MbxFakeHandler]::Add(200,'','',900000000)
        $r=Invoke-MbxHttp $testUrl @('msi.com') -Head
        Assert-Mbx ($r.HeadersOnly -and $r.Bytes -eq 0 -and $r.ExpectedBytes -eq 900000000) 'HEAD presente comme telechargement complet.'
    }
    Case-Mbx 'Simulated redirect to outside host blocked before request' {
        [MbxFakeHandler]::Reset(); [MbxFakeHandler]::Add(302,'https://evil.invalid/payload.exe','',-1)
        Throws-Mbx { Invoke-MbxHttp $testUrl @('msi.com') } 'refusee'
        Assert-Mbx ([MbxFakeHandler]::Requests.Count -eq 1) 'Requete externe effectuee.'
    }
    Case-Mbx 'Simulated redirect loop bounded' {
        [MbxFakeHandler]::Reset(); 1..7 | ForEach-Object { [MbxFakeHandler]::Add(302,'/loop','',-1) }
        Throws-Mbx { Invoke-MbxHttp $testUrl @('msi.com') } 'six sauts'
        Assert-Mbx ([MbxFakeHandler]::Requests.Count -eq 7) 'Limite de redirections ignoree.'
    }
    foreach ($status in @(403,404,429,500,503,206)) {
        Case-Mbx ("Simulated HTTP $status remains a failure") {
            [MbxFakeHandler]::Reset()
            $attempts=if($status -in @(429,500,503)){3}else{1}
            1..$attempts | ForEach-Object { [MbxFakeHandler]::Add($status,'','',2048) }
            Throws-Mbx { Invoke-MbxHttp $testUrl @('msi.com') } "HTTP $status"
            Assert-Mbx ([MbxFakeHandler]::Requests.Count -eq $attempts) 'Nombre de reprises incorrect.'
        }
    }
    Case-Mbx 'Simulated connection error and actual cancellation deadline' {
        [MbxFakeHandler]::Reset(); 1..3 | ForEach-Object { [MbxFakeHandler]::Add(200,'','network',-1) }
        Throws-Mbx { Invoke-MbxHttp $testUrl @('msi.com') } 'simulated connection'
        [MbxFakeHandler]::Reset(); [MbxFakeHandler]::Add(200,'','timeout',-1)
        $watch=[Diagnostics.Stopwatch]::StartNew()
        Throws-Mbx { Invoke-MbxHttp $testUrl @('msi.com') -TimeoutSeconds 1 }
        Assert-Mbx ($watch.Elapsed.TotalSeconds -lt 5) 'Delai non borne.'
    }
    foreach ($kind in @('short','interrupt','oversize')) {
        Case-Mbx ("Simulated $kind download cleans partial files") {
            [MbxFakeHandler]::Reset()
            if ($kind -eq 'short') { 1..3 | ForEach-Object { [MbxFakeHandler]::Add(200,'','',9999) } }
            elseif ($kind -eq 'interrupt') { 1..3 | ForEach-Object { [MbxFakeHandler]::Add(200,'','interrupt',2048) } }
            else { [MbxFakeHandler]::Add(200,'','',2048) }
            $p=Join-Path $temp ($kind+'.exe')
            $limit=if($kind -eq 'oversize'){1024}else{8388608}
            Throws-Mbx { Invoke-MbxHttp $testUrl @('msi.com') -OutFile $p -MaxBytes $limit }
            Assert-Mbx (-not (Test-Path $p)) 'Fichier incomplet conserve comme final.'
            Assert-Mbx (@(Get-ChildItem $temp -Filter '*.part').Count -eq 0) 'Fichier partiel non nettoye.'
        }
    }
    Case-Mbx 'Interrupted stream retries from scratch and leaves only the complete file' {
        [MbxFakeHandler]::Reset()
        [MbxFakeHandler]::Add(200,'','interrupt',2048)
        [MbxFakeHandler]::Add(200,'','',2048)
        $p=Join-Path $temp 'recovered.exe'
        $r=Invoke-MbxHttp $testUrl @('msi.com') -OutFile $p
        Assert-Mbx ($r.Attempts -eq 2 -and [MbxFakeHandler]::Requests.Count -eq 2) 'Coupure non reprise.'
        Assert-Mbx ((Get-Item $p).Length -eq 2048 -and $r.Bytes -eq 2048) 'Octets partiels reutilises.'
        Assert-Mbx (@(Get-ChildItem $temp -Filter '*.part').Count -eq 0) 'Fichier partiel restant apres reprise.'
    }
    Case-Mbx 'Existing file never overwritten' {
        [MbxFakeHandler]::Reset(); [MbxFakeHandler]::Add(200,'','',2048)
        $p=Join-Path $temp 'existing.exe'; [IO.File]::WriteAllText($p,'preserve')
        Throws-Mbx { Invoke-MbxHttp $testUrl @('msi.com') -OutFile $p }
        Assert-Mbx ([IO.File]::ReadAllText($p) -eq 'preserve') 'Fichier existant ecrase.'
        Assert-Mbx (@(Get-ChildItem $temp -Filter '*.part').Count -eq 0) 'Fichier partiel restant.'
    }
    Case-Mbx 'Invalid PE and unsigned payload rejected' {
        $p=Join-Path $temp 'unsigned.exe'
        [IO.File]::WriteAllText($p,'not a PE')
        Throws-Mbx { Test-MbxSignedPayload $p @('ASUSTeK COMPUTER INC.') } 'PE/MZ'
        if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
            $bytes=New-Object byte[] 2048; $bytes[0]=77; $bytes[1]=90; [IO.File]::WriteAllBytes($p,$bytes)
            Throws-Mbx { Test-MbxSignedPayload $p @('ASUSTeK COMPUTER INC.') } 'Signature'
        }
    }
    # Explicitly simulated certificate boundary. Actual Authenticode is exercised separately on Windows.
    & $module {
        $script:MbxFakeSignatureStatus='Valid'; $script:MbxFakeSigner='Micro-Star International Co., Ltd.'
        function script:Get-AuthenticodeSignature {
            param($LiteralPath)
            $cert=New-Object psobject
            $cert | Add-Member -MemberType ScriptMethod -Name GetNameInfo -Value { param($type,$issuer) return $script:MbxFakeSigner }
            return [pscustomobject]@{ Status=$script:MbxFakeSignatureStatus; SignerCertificate=$cert }
        }
    }
    Case-Mbx 'Simulated invalid signature and valid wrong publisher rejected' {
        $p=Join-Path $temp 'signature.exe'
        $bytes=New-Object byte[] 2048; $bytes[0]=77; $bytes[1]=90; [IO.File]::WriteAllBytes($p,$bytes)
        & $module { $script:MbxFakeSignatureStatus='HashMismatch' }
        Throws-Mbx { Test-MbxSignedPayload $p @('Micro-Star International Co., Ltd.') } 'non valide'
        & $module { $script:MbxFakeSignatureStatus='Valid'; $script:MbxFakeSigner='Not the manufacturer' }
        Throws-Mbx { Test-MbxSignedPayload $p @('Micro-Star International Co., Ltd.') } 'Editeur'
        & $module { $script:MbxFakeSigner='Micro-Star International Co., Ltd.' }
        $r=Test-MbxSignedPayload $p @('Micro-Star International Co., Ltd.')
        Assert-Mbx ($r.Status -eq 'Valid' -and $r.SHA256 -eq (Get-FileHash $p).Hash) 'Resultat de verification simule incorrect.'
    }
    Case-Mbx 'Simulated ZIP audit validates signed payload and never executes' {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        Add-Type -AssemblyName System.IO.Compression
        $p=Join-Path $temp 'fixture.zip'
        $zip=[IO.Compression.ZipFile]::Open($p,[IO.Compression.ZipArchiveMode]::Create)
        try {
            $entry=$zip.CreateEntry('MSI_Center.exe'); $s=$entry.Open()
            try { $bytes=New-Object byte[] 2048; $bytes[0]=77; $bytes[1]=90; $s.Write($bytes,0,$bytes.Length) } finally { $s.Dispose() }
        } finally { $zip.Dispose() }
        [MbxFakeHandler]::Payload=[IO.File]::ReadAllBytes($p)
        [MbxFakeHandler]::Reset(); [MbxFakeHandler]::Add(200,'','',[MbxFakeHandler]::Payload.Length)
        $tool=@(Get-MbxToolDefinitions | Where-Object Vendor -eq MSI)[0]
        $r=Invoke-MbxUtilityAudit -Tool $tool -DownloadUrl $testUrl -OutputDirectory $temp
        Assert-Mbx ($r.Status -eq 'download_and_signed_executables_verified' -and -not $r.Executed -and -not $r.Installed) 'Succes incorrect ou executable lance.'
        Assert-Mbx ($r.HardwareCompatibility -eq 'not_established' -and $r.LatestVersion -eq 'not_established') 'Audit transforme en preuve de compatibilite ou derniere version.'
    }
    Case-Mbx 'Simulated ZIP path traversal refused' {
        $p=Join-Path $temp 'traversal.zip'
        $zip=[IO.Compression.ZipFile]::Open($p,[IO.Compression.ZipArchiveMode]::Create)
        try { [void]$zip.CreateEntry('../outside.exe') } finally { $zip.Dispose() }
        [MbxFakeHandler]::Payload=[IO.File]::ReadAllBytes($p)
        [MbxFakeHandler]::Reset(); [MbxFakeHandler]::Add(200,'','',[MbxFakeHandler]::Payload.Length)
        $tool=@(Get-MbxToolDefinitions | Where-Object Vendor -eq MSI)[0]
        Throws-Mbx { Invoke-MbxUtilityAudit -Tool $tool -DownloadUrl $testUrl -OutputDirectory $temp } 'dangereux'
        Assert-Mbx (-not (Test-Path (Join-Path $OutputDirectory 'outside.exe'))) 'Archive extraite hors de sa zone.'
    }
    Case-Mbx 'Simulated ASUS streamed download with official Content-Disposition' {
        & $module { $script:MbxFakeSigner='ASUSTeK COMPUTER INC.' }
        $bytes=New-Object byte[] 2048; $bytes[0]=77; $bytes[1]=90; [MbxFakeHandler]::Payload=$bytes
        [MbxFakeHandler]::Reset()
        [MbxFakeHandler]::AddNamed('ASUS_DriverHubInstaller.exe',2048)
        [MbxFakeHandler]::AddNamed('ASUS_DriverHubInstaller.exe',2048)
        $tool=@(Get-MbxToolDefinitions | Where-Object Vendor -eq ASUS)[0]
        $r=Invoke-MbxUtilityAudit -Tool $tool -DownloadUrl 'https://geo.asus.com/driverhub/' -OutputDirectory $temp
        Assert-Mbx ($r.Status -eq 'download_and_signed_executables_verified' -and -not $r.Executed) 'Fichier servi directement non verifie.'
        Assert-Mbx ($r.RequestedUrl -eq 'https://geo.asus.com/driverhub/' -and $r.Bytes -eq 2048) 'Provenance ou completude perdue.'
    }
    Case-Mbx 'Simulated ASUS HTML download link without evaluating JavaScript' {
        [MbxFakeHandler]::Reset()
        [MbxFakeHandler]::Add(200,'','',2048)
        [MbxFakeHandler]::AddText('<script>window.location.href="/files/ASUS_DriverHubInstaller.exe";</script>')
        [MbxFakeHandler]::Add(200,'','',2048)
        $tool=@(Get-MbxToolDefinitions | Where-Object Vendor -eq ASUS)[0]
        $r=Invoke-MbxUtilityAudit -Tool $tool -DownloadUrl 'https://geo.asus.com/driverhub/' -OutputDirectory $temp
        Assert-Mbx ($r.FinalUrl -eq 'https://geo.asus.com/files/ASUS_DriverHubInstaller.exe' -and -not $r.Executed) 'Lien relatif incorrect ou code execute.'
        Assert-Mbx ([MbxFakeHandler]::Requests.Count -eq 3) 'Requetes inattendues.'
    }
} finally { Remove-Item -LiteralPath $temp -Recurse -Force }

# Restore the production HTTP factory before any live request.
Remove-Module MotherboardExperiment
Import-Module (Join-Path $PSScriptRoot 'MotherboardExperiment.psm1') -Force
$liveResults=New-Object 'System.Collections.Generic.List[object]'
if ($Live) {
    Case-Mbx 'Actual Windows PowerShell 5.1 CIM and isolated entry point' {
        Assert-Mbx ($PSVersionTable.PSEdition -eq 'Desktop' -and $PSVersionTable.PSVersion.Major -eq 5) 'Windows PowerShell 5.1 requis pour ce test reel.'
        $p=Join-Path $OutputDirectory 'real-inventory.json'
        & (Join-Path $PSScriptRoot 'Invoke-MotherboardExperiment.ps1') -OutputPath $p -CheckOnline
        $real=Get-Content $p -Raw | ConvertFrom-Json
        Assert-Mbx ($real.Inventory.BaseBoards.Count -gt 0 -and $real.Inventory.Computers.Count -gt 0 -and $real.Inventory.OperatingSystems.Count -gt 0) 'Inventaire reel essentiel absent.'
        Assert-Mbx ($real.Inventory.Drivers.Count -gt 0 -and $real.Inventory.Devices.Count -gt 0) 'Inventaire pilotes/PnP absent.'
        Assert-Mbx ($real.Changes.InstalledDrivers -eq 0 -and -not $real.Changes.RebootInitiated) 'Mutation systeme inattendue.'
        $safe=[ordered]@{ Kind=$real.Inventory.Kind; BaseBoards=$real.Inventory.BaseBoards.Count; Computers=$real.Inventory.Computers.Count; BIOS=$real.Inventory.Bios.Count; Drivers=$real.Inventory.Drivers.Count; PnP=$real.Inventory.Devices.Count; CimErrors=$real.Inventory.Errors; SelectionStatus=$real.Selection.Status; Reason=$real.Selection.Reason }
        $liveResults.Add([pscustomobject]$safe)
        Write-MbxEvidence -Kind 'real_inventory' -Data $safe
    }
}
if ($DownloadAudit) {
    if (-not $Live) { throw '-DownloadAudit exige -Live : verification Authenticode reelle sous Windows.' }
    Case-Mbx 'Actual official MSI archive download and Authenticode (no execution)' {
        $tool=@(Get-MbxToolDefinitions | Where-Object Vendor -eq MSI)[0]
        # Public winget metadata is a URL locator only, not proof of model support or latest release.
        # The URL has no fixed version; the actual bytes and publisher are checked independently.
        $url='https://download-2.msi.com/uti_exe/desktop/MSI-Center.zip'
        $r=Invoke-MbxUtilityAudit -Tool $tool -DownloadUrl $url -OutputDirectory (Join-Path $OutputDirectory 'download-audit')
        Assert-Mbx ($r.Bytes -gt 1024 -and $r.Payloads.Count -gt 0) 'Archive ou signature manquante.'
        Assert-Mbx (-not $r.Executed -and -not $r.Installed -and -not $r.FirmwareFlashed) 'Execution ou installation inattendue.'
        $liveResults.Add($r)
        $r | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $OutputDirectory 'real-download.json') -Encoding UTF8
        Write-MbxEvidence -Kind 'real_download' -Data $r
    }
    # This shortlink is published in DriverHub's own JavaScript; no unsupported driver API is called.
    # Network unavailability is reported as such, never counted as a successful download.
    try {
        $tool=@(Get-MbxToolDefinitions | Where-Object Vendor -eq ASUS)[0]
        $r=Invoke-MbxUtilityAudit -Tool $tool -DownloadUrl 'https://geo.asus.com/driverhub/' -OutputDirectory (Join-Path $OutputDirectory 'download-audit')
    } catch { $r=[pscustomobject]@{ Vendor='ASUS'; Status='download_audit_failed'; Error=$_.Exception.Message; Executed=$false; Installed=$false } }
    $liveResults.Add($r)
    $r | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $OutputDirectory 'real-asus-download.json') -Encoding UTF8
    Write-MbxEvidence -Kind 'real_download' -Data $r
}
$report=[ordered]@{ Passage=(Split-Path -Leaf $OutputDirectory); HostPowerShell=$PSVersionTable.PSVersion.ToString(); LiveRequested=[bool]$Live; DownloadAuditRequested=[bool]$DownloadAudit; SimulatedTransport=$true; Assertions=$script:assertions; Cases=@($results.ToArray()); Live=@($liveResults.ToArray()); Failures=@($results.ToArray() | Where-Object Result -eq failed).Count }
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'tests.json') -Encoding UTF8
Write-MbxEvidence -Kind 'test_report' -Data $report
if ($report.Failures -gt 0) { throw "$($report.Failures) scenario(s) en echec." }
Write-Host "$($results.Count) scenarios et $script:assertions assertions reussis."
