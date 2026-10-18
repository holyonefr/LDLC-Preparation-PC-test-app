#requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputDirectory)

# Static inspection only. The portable, pinned unpacker is the only native program
# invoked here. MSI's installer, scripts, application and SDK are never executed.
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$ProgressPreference='SilentlyContinue'
Import-Module (Join-Path $PSScriptRoot '../motherboard/MotherboardExperiment.psm1') -Force
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression

function ConvertTo-MsiAppxArgument {
    param([AllowEmptyString()][string]$Value)
    # Windows CommandLineToArgvW-compatible quoting, including trailing backslashes.
    $escaped=[regex]::Replace($Value,'(\\*)"','$1$1\"')
    $escaped=[regex]::Replace($escaped,'(\\+)$','$1$1')
    return '"'+$escaped+'"'
}

function Invoke-MsiAppxUnpacker {
    param([string]$Path,[string[]]$Arguments)
    $process=New-Object Diagnostics.Process
    $process.StartInfo.FileName=$Path
    $process.StartInfo.Arguments=(@($Arguments | ForEach-Object { ConvertTo-MsiAppxArgument $_ }) -join ' ')
    $process.StartInfo.UseShellExecute=$false
    $process.StartInfo.CreateNoWindow=$true
    $process.StartInfo.RedirectStandardOutput=$true
    $process.StartInfo.RedirectStandardError=$true
    $started=$false
    try {
        $clock=[Diagnostics.Stopwatch]::StartNew()
        $started=$process.Start()
        if (-not $started) { throw 'Le decompresseur statique ne demarre pas.' }
        # Do not await ReadToEndAsync after WaitForExit: inherited pipe handles can
        # keep that task pending even after the parent exits. Drain both streams
        # together under one deadline, retaining at most 32 Ki characters each.
        $streams=@(
            [pscustomobject]@{Reader=$process.StandardOutput;Buffer=(New-Object char[] 8192);Task=$null;Done=$false;Text=(New-Object Text.StringBuilder);Total=[long]0},
            [pscustomobject]@{Reader=$process.StandardError;Buffer=(New-Object char[] 8192);Task=$null;Done=$false;Text=(New-Object Text.StringBuilder);Total=[long]0}
        )
        foreach ($state in $streams) { $state.Task=$state.Reader.ReadAsync($state.Buffer,0,$state.Buffer.Length) }
        while (-not $process.HasExited -or -not $streams[0].Done -or -not $streams[1].Done) {
            if ($clock.ElapsedMilliseconds -ge 120000) {
                throw 'Extraction statique interrompue apres 120 secondes, flux compris ; aucun programme MSI execute.'
            }
            foreach ($state in $streams) {
                if ($state.Done -or -not $state.Task.IsCompleted) { continue }
                $count=$state.Task.GetAwaiter().GetResult()
                if ($count -eq 0) { $state.Done=$true; continue }
                $state.Total+=$count
                if ($state.Total -gt 8388608) { throw 'Sortie du decompresseur superieure a 8 Mio de caracteres ; extraction statique arretee.' }
                $retained=[Math]::Min($count,32768-$state.Text.Length)
                if ($retained -gt 0) { [void]$state.Text.Append($state.Buffer,0,$retained) }
                $state.Task=$state.Reader.ReadAsync($state.Buffer,0,$state.Buffer.Length)
            }
            if (-not $process.HasExited) { [void]$process.WaitForExit(20) }
            elseif (-not $streams[0].Done -or -not $streams[1].Done) { [Threading.Thread]::Sleep(20) }
        }
        $text=$streams[0].Text.ToString()+$streams[1].Text.ToString()
        if ($streams[0].Total -gt 32768 -or $streams[1].Total -gt 32768) { $text+="`n[Sortie capturee tronquee ; les flux ont ete draines sous delai.]" }
        if ($process.ExitCode -ne 0) {
            throw ('Echec du decompresseur statique, code {0} : {1}' -f $process.ExitCode,$text.Substring(0,[Math]::Min(4096,$text.Length)))
        }
        return [pscustomobject]@{ExitCode=$process.ExitCode;Text=$text}
    } finally {
        try {
            if ($started -and -not $process.HasExited) { $process.Kill(); [void]$process.WaitForExit(5000) }
        } finally { $process.Dispose() }
    }
}

function Get-MsiAppxZipEntry {
    param($Archive,[string]$Name)
    $normalized=$Name.Replace('\','/')
    if ($normalized -match '(^/|(^|/)\.\.(/|$)|:)' -or [string]::IsNullOrWhiteSpace($normalized)) {
        throw 'Chemin de contenu AppX dangereux refuse.'
    }
    # Appx bundles use OPC part names: spaces in a manifest FileName may be %20
    # in the ZIP directory. Accept exactly that encoded spelling, never another
    # version or a guessed package. Reject raw/encoded duplicates as ambiguous.
    $encoded=(@($normalized -split '/' | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/')
    $matches=@($Archive.Entries | Where-Object { $_.FullName.Replace('\','/') -ieq $normalized -or $_.FullName.Replace('\','/') -ieq $encoded })
    if ($matches.Count -ne 1) { throw ('Entree AppX {0} absente ou ambigue ({1}).' -f $Name,$matches.Count) }
    if ($matches[0].Length -gt 2147483648) { throw 'Entree AppX superieure a 2 Gio refusee.' }
    return $matches[0]
}

function Read-MsiAppxManifest {
    param($Archive,[string]$Name)
    $entry=Get-MsiAppxZipEntry -Archive $Archive -Name $Name
    if ($entry.Length -gt 1048576) { throw ('Manifeste {0} superieur a 1 Mio refuse.' -f $Name) }
    $settings=New-Object Xml.XmlReaderSettings
    $settings.DtdProcessing=[Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver=$null
    $settings.MaxCharactersInDocument=1048576
    $settings.IgnoreComments=$true
    $settings.IgnoreProcessingInstructions=$true
    $document=New-Object Xml.XmlDocument
    $document.XmlResolver=$null
    $stream=$entry.Open()
    $reader=$null
    try {
        $reader=[Xml.XmlReader]::Create($stream,$settings)
        $document.Load($reader)
        return ,$document
    } finally {
        if ($null -ne $reader) { $reader.Dispose() }
        $stream.Dispose()
    }
}

function Get-MsiAppxAttributes {
    param([Xml.XmlNode]$Node)
    $attributes=[ordered]@{}
    foreach ($attribute in $Node.Attributes) {
        if ($attribute.Prefix -ne 'xmlns' -and $attribute.Name -ne 'xmlns') {
            $attributes[$attribute.Name]=[string]$attribute.Value
        }
    }
    return [pscustomobject]$attributes
}

function Get-MsiAppxSignature {
    param([string]$Path)
    $result=[ordered]@{State='not_established';AuthenticodeStatus='not_available';Subject='';Issuer='';Thumbprint='';Reason=''}
    if (-not (Get-Command Get-AuthenticodeSignature -ErrorAction SilentlyContinue)) {
        $result.Reason='Get-AuthenticodeSignature indisponible ; la signature du bootstrap ne valide pas le paquet interieur.'
        return [pscustomobject]$result
    }
    try {
        $signature=Get-AuthenticodeSignature -LiteralPath $Path
        $result.AuthenticodeStatus=[string]$signature.Status
        if ($null -ne $signature.SignerCertificate) {
            $result.Subject=[string]$signature.SignerCertificate.Subject
            $result.Issuer=[string]$signature.SignerCertificate.Issuer
            $result.Thumbprint=[string]$signature.SignerCertificate.Thumbprint
        }
        if ($signature.Status -eq 'Valid') {
            $result.State='valid'
            $result.Reason='Signature de ce fichier verifiee par Windows ; aucune deduction depuis la signature externe.'
        } else {
            $result.Reason='Signature interieure non etablie par ce controle Windows : '+[string]$signature.StatusMessage
        }
    } catch { $result.Reason='Verification interieure indisponible : '+$_.Exception.Message }
    return [pscustomobject]$result
}

function Test-MsiAppxZipHeader {
    param([string]$Path)
    $file=Get-Item -LiteralPath $Path
    if ($file.Length -lt 4 -or $file.Length -gt 2147483648) { throw 'Taille du paquet AppX hors limites (4 octets a 2 Gio).' }
    $stream=[IO.File]::OpenRead($Path)
    try {
        if ($stream.ReadByte() -ne 0x50 -or $stream.ReadByte() -ne 0x4B -or $stream.ReadByte() -ne 0x03 -or $stream.ReadByte() -ne 0x04) {
            throw 'En-tete ZIP PK du paquet AppX invalide.'
        }
    } finally { $stream.Dispose() }
}

function Get-MsiAppxApplicationMetadata {
    param([Xml.XmlDocument]$Manifest)
    $identities=@($Manifest.SelectNodes('/*[local-name()="Package"]/*[local-name()="Identity"]'))
    if ($identities.Count -ne 1) { throw 'Identite unique du paquet x64 non etablie.' }
    $applications=@($Manifest.SelectNodes('/*[local-name()="Package"]/*[local-name()="Applications"]/*[local-name()="Application"]'))
    $dependencies=@($Manifest.SelectNodes('/*[local-name()="Package"]/*[local-name()="Dependencies"]/*'))
    $extensions=@($Manifest.SelectNodes('//*[local-name()="Extension"]'))
    $startupTasks=@($Manifest.SelectNodes('//*[local-name()="StartupTask"]'))
    if ($applications.Count -gt 128 -or $dependencies.Count -gt 256 -or $extensions.Count -gt 512 -or $startupTasks.Count -gt 128) {
        throw 'Nombre de metadonnees AppX trop eleve pour cet audit borne.'
    }
    return [pscustomobject]@{
        Identity=Get-MsiAppxAttributes $identities[0]
        Applications=@($applications | ForEach-Object { Get-MsiAppxAttributes $_ })
        Dependencies=@($dependencies | ForEach-Object { [pscustomobject]@{Kind=$_.LocalName;Attributes=Get-MsiAppxAttributes $_} })
        Extensions=@($extensions | ForEach-Object {
            $node=$_
            $owner=$node.ParentNode
            while ($null -ne $owner -and $owner.LocalName -ne 'Application') { $owner=$owner.ParentNode }
            [pscustomobject]@{
                ApplicationId=if ($null -ne $owner) { $owner.GetAttribute('Id') } else { '' }
                Attributes=Get-MsiAppxAttributes $node
                Children=@($node.ChildNodes | Where-Object NodeType -eq ([Xml.XmlNodeType]::Element) | ForEach-Object {
                    [pscustomobject]@{Kind=$_.LocalName;Namespace=$_.NamespaceURI;Attributes=Get-MsiAppxAttributes $_}
                })
            }
        })
        StartupTasks=@($startupTasks | ForEach-Object {
            [pscustomobject]@{
                TaskId=$_.GetAttribute('TaskId');Enabled=$_.GetAttribute('Enabled')
                EnabledAttributePresent=$_.HasAttribute('Enabled');Attributes=Get-MsiAppxAttributes $_
            }
        })
        Capabilities=@($Manifest.SelectNodes('/*[local-name()="Package"]/*[local-name()="Capabilities"]/*') | ForEach-Object {
            [pscustomobject]@{Kind=$_.LocalName;Namespace=$_.NamespaceURI;Attributes=Get-MsiAppxAttributes $_}
        })
    }
}

$output=[IO.Path]::GetFullPath($OutputDirectory)
[void](New-Item -ItemType Directory -Path $output -Force)
$report=[ordered]@{
    Kind='msi_appx_static_metadata';Status='started';Error=''
    VendorInstallerExecuted=$false;ApplicationExecuted=$false;AppxRegistered=$false;Installed=$false
    DriverScanStarted=$false;DriverInstalled=$false;FirmwareFlashed=$false;DesktopShortcutCreated=$false
    LatestStoreVersion='not_established';BaseOnlyInstallSafety='not_established';AutomaticInstallSupported='not_established'
    SourceClaim='Official MSI archive inspected statically; no Store query, installation, application launch or driver operation.'
    OuterAudit=$null;Bundle=$null;ApplicationPackage=$null;UnpackerExitCode=$null
}
$failure=$null
try {
    $bootstrap=Join-Path $output 'bootstrap'
    if (Test-Path -LiteralPath $bootstrap) { throw 'Le sous-dossier bootstrap existe deja ; choisir un nouveau dossier d audit pour eviter une preuve ancienne.' }
    & (Join-Path $PSScriptRoot 'Inspect-MsiUtility.ps1') -Vendor MSI -OutputDirectory $bootstrap
    $inspectionPath=Join-Path $bootstrap 'inspection.json'
    if (-not (Test-Path -LiteralPath $inspectionPath -PathType Leaf) -or (Get-Item -LiteralPath $inspectionPath).Length -gt 4194304) {
        throw 'Rapport du bootstrap absent ou superieur a 4 Mio.'
    }
    $inspection=[IO.File]::ReadAllText($inspectionPath) | ConvertFrom-Json
    $report.OuterAudit=$inspection.Audit
    $auditDirectories=@(Get-ChildItem -LiteralPath $bootstrap -Directory | Where-Object Name -match '^[a-fA-F0-9]{32}$')
    if ($auditDirectories.Count -ne 1) { throw 'Dossier unique de la charge officielle MSI non etabli.' }
    $payloads=@(Get-ChildItem -LiteralPath $auditDirectories[0].FullName -File | Where-Object Name -match '^payload-[0-9]+\.exe$')
    if ($payloads.Count -ne 1 -or $payloads[0].Name -ne 'payload-0.exe') { throw 'Charge MSI payload-0.exe absente ou ambigue.' }
    $unpacker=Join-Path (Join-Path $bootstrap 'unpacker') 'innounp.exe'
    if (-not (Test-Path -LiteralPath $unpacker -PathType Leaf)) { throw 'Decompresseur portable attendu introuvable dans unpacker/innounp.exe.' }
    $expectedUnpackerZip='10FCE27B6344B7674D5625CC34AFCA1C88C12183D957C6D93E401097FA2556CD'
    if ((Get-FileHash -LiteralPath (Join-Path $bootstrap 'unpacker.zip') -Algorithm SHA256).Hash -ne $expectedUnpackerZip) {
        throw 'Empreinte de l archive du decompresseur portable invalide.'
    }
    $extractDir=Join-Path $output 'static-appx'
    if (Test-Path -LiteralPath $extractDir) { throw 'Le dossier d extraction AppX existe deja.' }
    [void](New-Item -ItemType Directory -Path $extractDir)
    $extraction=Invoke-MsiAppxUnpacker -Path $unpacker -Arguments @('-x','-m','-b','-q','-o',('-d'+$extractDir),$payloads[0].FullName,'*.appxbundle')
    $report.UnpackerExitCode=$extraction.ExitCode
    $extraction.Text.Substring(0,[Math]::Min(32768,$extraction.Text.Length)) | Set-Content (Join-Path $output 'appx-unpacker-output.txt') -Encoding UTF8
    $appDirectory=Join-Path $extractDir '{app}'
    if (-not (Test-Path -LiteralPath $appDirectory -PathType Container)) { throw 'Dossier direct {app} du bundle MSI absent.' }
    $bundles=@(Get-ChildItem -LiteralPath $appDirectory -File | Where-Object Extension -ieq '.appxbundle')
    if ($bundles.Count -ne 1) { throw 'Bundle MSI direct absent ou ambigu ; aucune exploration recursive du payload.' }
    $bundle=$bundles[0]
    Test-MsiAppxZipHeader $bundle.FullName
    $report.Bundle=[ordered]@{FileName=$bundle.Name;Bytes=$bundle.Length;SHA256=(Get-FileHash -LiteralPath $bundle.FullName -Algorithm SHA256).Hash;Signature=Get-MsiAppxSignature $bundle.FullName;Identity=$null;Packages=@()}
    $archive=[IO.Compression.ZipFile]::OpenRead($bundle.FullName)
    try {
        $manifest=Read-MsiAppxManifest -Archive $archive -Name 'AppxMetadata/AppxBundleManifest.xml'
        $identities=@($manifest.SelectNodes('/*[local-name()="Bundle"]/*[local-name()="Identity"]'))
        if ($identities.Count -ne 1) { throw 'Identite unique du bundle MSI non etablie.' }
        $report.Bundle.Identity=Get-MsiAppxAttributes $identities[0]
        $packages=@($manifest.SelectNodes('/*[local-name()="Bundle"]/*[local-name()="Packages"]/*[local-name()="Package"]'))
        if ($packages.Count -gt 128) { throw 'Le bundle propose trop de paquets pour cet audit borne.' }
        $report.Bundle.Packages=@($packages | ForEach-Object { Get-MsiAppxAttributes $_ })
        $candidates=@($packages | Where-Object { $_.GetAttribute('Type') -ieq 'application' -and $_.GetAttribute('Architecture') -ieq 'x64' })
        if ($candidates.Count -ne 1) { throw 'Paquet applicatif x64 unique absent ou ambigu dans le bundle.' }
        $packageName=$candidates[0].GetAttribute('FileName')
        if ([IO.Path]::GetExtension($packageName) -notin @('.appx','.msix')) { throw 'Extension du paquet applicatif x64 non reconnue.' }
        $entry=Get-MsiAppxZipEntry -Archive $archive -Name $packageName
        $packagePath=Join-Path $output 'package-x64.appx'
        if (Test-Path -LiteralPath $packagePath) { throw 'Le fichier fixe package-x64.appx existe deja.' }
        $inputStream=$entry.Open()
        $outputStream=$null
        try {
            $outputStream=[IO.File]::Open($packagePath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
            $buffer=New-Object byte[] 65536
            $copied=[long]0
            while (($count=$inputStream.Read($buffer,0,$buffer.Length)) -gt 0) {
                $copied+=$count
                if ($copied -gt $entry.Length -or $copied -gt 2147483648) { throw 'Extraction du paquet x64 superieure a la taille declaree.' }
                $outputStream.Write($buffer,0,$count)
            }
            if ($copied -ne $entry.Length) { throw 'Extraction du paquet x64 incomplete.' }
        } finally {
            $inputStream.Dispose()
            if ($null -ne $outputStream) { $outputStream.Dispose() }
        }
        # Export XML loaded with DTD/external resolution disabled, never evaluate it.
        $manifest.Save((Join-Path $output 'AppxBundleManifest.xml'))
    } finally { $archive.Dispose() }
    Test-MsiAppxZipHeader $packagePath
    $applicationArchive=[IO.Compression.ZipFile]::OpenRead($packagePath)
    try {
        $applicationManifest=Read-MsiAppxManifest -Archive $applicationArchive -Name 'AppxManifest.xml'
        $metadata=Get-MsiAppxApplicationMetadata $applicationManifest
        $applicationManifest.Save((Join-Path $output 'AppxManifest.xml'))
    } finally { $applicationArchive.Dispose() }
    $report.ApplicationPackage=[ordered]@{
        OriginalFileName=$packageName;ExtractedFileName='package-x64.appx';Bytes=(Get-Item -LiteralPath $packagePath).Length
        SHA256=(Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash;Signature=Get-MsiAppxSignature $packagePath
        Identity=$metadata.Identity;Applications=$metadata.Applications;Dependencies=$metadata.Dependencies
        Extensions=$metadata.Extensions;StartupTasks=$metadata.StartupTasks;Capabilities=$metadata.Capabilities
    }
    $report.Status='metadata_inspected_signatures_not_established'
    if ($report.Bundle.Signature.State -eq 'valid' -and $report.ApplicationPackage.Signature.State -eq 'valid') {
        $report.Status='metadata_inspected_signed_packages'
    }
} catch {
    $failure=$_
    $report.Status='failed'
    $report.Error=$_.Exception.Message
} finally {
    $report | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $output 'msi-appx-inspection.json') -Encoding UTF8
    Write-MbxEvidence -Kind 'msi_appx_static_metadata' -Data $report
}
if ($null -ne $failure) { throw $failure }
