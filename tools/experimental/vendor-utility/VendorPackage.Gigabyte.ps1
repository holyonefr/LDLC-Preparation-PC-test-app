#requires -Version 5.1
# Static extraction only. No vendor setup is used as a decompressor or executed.
function Test-VutArchiveTool {
    param([string]$Path)
    $expected=@{
        '7zr.exe'='256FECA8E274E5DA655E2A284FABAFD9F554365EB164862089DACD4E8276D282'
        '7z.exe'='95FFF19B73EFF77C87C0D7BD32822E43FB90DD2932459F962EB532D8DFB6BA53'
    }
    $name=[IO.Path]::GetFileName($Path)
    if (-not $expected.ContainsKey($name) -or (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ne $expected[$name]) {
        throw 'Outil de decompression absent ou empreinte non approuvee ; aucun executable constructeur autorise comme outil.'
    }
    if ($name -eq '7z.exe') {
        $dll=Join-Path (Split-Path -Parent $Path) '7z.dll'
        if ((Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash -ne '899CD73D7FC60E1C1C35C7DE0F5BED3DC69BFE2CECBD48014D868A347970A0B1') { throw 'Bibliotheque de decompression non conforme.' }
    }
}

function Invoke-VutArchiveTool {
    param([string]$Path,[string[]]$Arguments)
    Test-VutArchiveTool $Path
    $p=New-Object Diagnostics.Process
    $p.StartInfo.FileName=$Path
    $p.StartInfo.Arguments=(@($Arguments | ForEach-Object { '"'+$_.Replace('"','\"')+'"' }) -join ' ')
    $p.StartInfo.UseShellExecute=$false; $p.StartInfo.CreateNoWindow=$true
    $p.StartInfo.RedirectStandardOutput=$true; $p.StartInfo.RedirectStandardError=$true
    try {
        [void]$p.Start()
        $stdout=$p.StandardOutput.ReadToEndAsync(); $stderr=$p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit(120000)) { $p.Kill(); [void]$p.WaitForExit(5000); throw 'Delai de decompression statique depasse.' }
        if (-not $stdout.Wait(5000) -or -not $stderr.Wait(5000)) { throw 'Flux de decompression non termines.' }
        $text=$stdout.GetAwaiter().GetResult()+$stderr.GetAwaiter().GetResult()
        if ($p.ExitCode -ne 0) { throw ('Decompression statique : code '+$p.ExitCode+'. '+$text.Substring(0,[Math]::Min(400,$text.Length))) }
        if ($text.Length -gt 1048576) { throw 'Liste archive trop volumineuse.' }
        return $text
    } finally { $p.Dispose() }
}

function Get-VutPortableSevenZip {
    param([string]$Directory)
    [void](New-Item -ItemType Directory -Path $Directory -Force)
    # Official ip7z release 26.04; hashes match the publisher's GitHub asset digests.
    $assets=@(
        @{Name='7zr.exe';SHA256='256FECA8E274E5DA655E2A284FABAFD9F554365EB164862089DACD4E8276D282'},
        @{Name='7z2604-x64.exe';SHA256='D54BF805F9F3704D1E8DB2FA3498AE7EF2DF0312B40B558E7C71C734430A665D'}
    )
    foreach ($asset in $assets) {
        $path=Join-Path $Directory $asset.Name
        [void](Invoke-MbxHttp -Url ('https://github.com/ip7z/7zip/releases/download/26.04/'+$asset.Name) -Hosts @('github.com','githubusercontent.com') -TimeoutSeconds 120 -MaxBytes 16777216 -OutFile $path)
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $asset.SHA256) { throw 'Empreinte du paquet officiel de decompression incorrecte.' }
    }
    $portable=Join-Path $Directory 'portable'
    [void](New-Item -ItemType Directory -Path $portable)
    # The 7-Zip setup is read as a 7z archive, never launched or installed.
    [void](Invoke-VutArchiveTool -Path (Join-Path $Directory '7zr.exe') -Arguments @('e','-y',('-o'+$portable),(Join-Path $Directory '7z2604-x64.exe'),'7z.exe','7z.dll'))
    $tool=Join-Path $portable '7z.exe'
    Test-VutArchiveTool $tool
    return $tool
}

function Resolve-VutGccCoreEntry {
    param([string]$Listing)
    $entries=@(foreach ($line in $Listing -split '\r?\n') {
        if ($line -notmatch '\APath = (.+)\z') { continue }
        $path=$Matches[1]; $leaf=($path.Replace('\','/') -split '/')[-1]
        $match=[regex]::Match($leaf,'\AGIGABYTE Control Center_([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)\.exe\z')
        if (-not $match.Success) { continue }
        if ($path -match '(^[/\\@-]|(^|[/\\])\.\.([/\\]|$)|[:"*?\x00-\x1f])') { throw 'Chemin du coeur GIGABYTE dangereux refuse.' }
        $version=ConvertTo-MbxVersion $match.Groups[1].Value
        if (-not $version) { throw 'Version du coeur GIGABYTE invalide.' }
        [pscustomobject]@{Path=$path;FileName=$leaf;Version=$match.Groups[1].Value}
    })
    if ($entries.Count -ne 1) { throw 'Coeur GIGABYTE absent ou ambigu ; aucun raccourci vers le bundle complet.' }
    return $entries[0]
}

function Get-VutGigabytePackage {
    param([string]$Directory)
    $discovery=Resolve-VutGigabyteCoreDownload
    $vendor=@(Get-MbxToolDefinitions | Where-Object Vendor -eq GIGABYTE)[0]
    $tool=[pscustomobject]@{Vendor='GIGABYTE';Tool='GIGABYTE Control Center';Hosts=@('mb.download.gigabyte.com');Signers=$vendor.Signers;FilePattern=('\A'+[regex]::Escape($discovery.FileName)+'\z')}
    $audit=Invoke-MbxUtilityAudit -Tool $tool -DownloadUrl $discovery.DownloadUrl -OutputDirectory $Directory
    if ($audit.Payloads.Count -ne 1 -or $audit.Bytes -ne $audit.ExpectedBytes -or $audit.Bytes -ne $discovery.ExpectedBytes) { throw 'Telechargement GCC incomplet ou taille differente du manifeste officiel.' }
    if ((ConvertTo-MbxVersion $audit.Payloads[0].FileVersion.Trim()) -ne (ConvertTo-MbxVersion $discovery.Version)) { throw 'Version du programme GCC differente du manifeste officiel ; aucun ancien fichier accepte.' }
    $files=@(Get-ChildItem -LiteralPath $Directory -Directory | Where-Object Name -match '\A[0-9a-f]{32}\z' | ForEach-Object {
        $p=Join-Path $_.FullName $discovery.FileName
        if (Test-Path -LiteralPath $p -PathType Leaf) { $p }
    })
    if ($files.Count -ne 1) { throw 'Installateur GCC absent ou ambigu apres telechargement.' }
    $signature=Test-MbxSignedPayload -Path $files[0] -Signers $vendor.Signers
    if ($signature.SHA256 -ne $audit.SHA256 -or $signature.SHA256 -ne $audit.Payloads[0].SHA256 -or $signature.Bytes -ne $discovery.ExpectedBytes -or (ConvertTo-MbxVersion $signature.FileVersion.Trim()) -ne (ConvertTo-MbxVersion $discovery.Version)) { throw 'Installateur GCC modifie apres verification.' }
    # The official update download is itself a small NSIS bundle containing
    # MB Update and RGB Sync. Never offer that wrapper as the core installer.
    return Expand-VutGigabyteCore -OuterPath $files[0] -Tool $vendor -Directory $Directory -Audit $audit -Discovery $discovery -ExpectedVersion $discovery.Version
}

# Historical bundle extraction is retained for explicit recorded-source audits.
# The user-facing path above never falls back to this bundle or an old snapshot.
function Get-VutGigabyteBundlePackage {
    param([string]$Directory)
    [void](New-Item -ItemType Directory -Path $Directory -Force)
    $discovery=Resolve-VutGigabyteDownload
    $tool=@(Get-MbxToolDefinitions | Where-Object Vendor -eq GIGABYTE)[0]
    $audit=Invoke-MbxUtilityAudit -Tool $tool -DownloadUrl $discovery.DownloadUrl -OutputDirectory $Directory
    if ($audit.Payloads.Count -ne 1 -or $audit.Bytes -ne $audit.ExpectedBytes -or (ConvertTo-MbxVersion $audit.Payloads[0].FileVersion.Trim()) -ne (ConvertTo-MbxVersion $discovery.BundleVersion)) {
        throw 'Bundle GIGABYTE incomplet, ambigu ou different de la version annoncee.'
    }
    $outer=@(Get-ChildItem -LiteralPath $Directory -Directory | Where-Object Name -match '\A[0-9a-f]{32}\z' | ForEach-Object {
        $p=Join-Path $_.FullName 'payload-0.exe'; if (Test-Path -LiteralPath $p -PathType Leaf) { $p }
    })
    if ($outer.Count -ne 1) { throw 'Executable externe GIGABYTE absent ou ambigu.' }
    $outerSignature=Test-MbxSignedPayload -Path $outer[0] -Signers $tool.Signers
    if ($outerSignature.SHA256 -ne $audit.Payloads[0].SHA256) { throw 'Bundle GIGABYTE modifie apres verification.' }
    return Expand-VutGigabyteCore -OuterPath $outer[0] -Tool $tool -Directory $Directory -Audit $audit -Discovery $discovery
}

function Get-VutGccInstallerProductName {
    param([string]$Path)
    return [Diagnostics.FileVersionInfo]::GetVersionInfo($Path).ProductName
}

function Expand-VutGigabyteCore {
    param([string]$OuterPath,$Tool,[string]$Directory,$Audit,$Discovery,[string]$ExpectedVersion)
    $sevenZip=Get-VutPortableSevenZip -Directory (Join-Path $Directory 'archive-tool')
    # -ba suppresses the archive header itself: its absolute Path can have the
    # same filename as the internal core and must not be parsed as an entry.
    $entry=Resolve-VutGccCoreEntry -Listing (Invoke-VutArchiveTool -Path $sevenZip -Arguments @('l','-slt','-ba',$OuterPath))
    if ($ExpectedVersion -and (ConvertTo-MbxVersion $entry.Version) -ne (ConvertTo-MbxVersion $ExpectedVersion)) { throw 'Version du coeur GCC differente du manifeste officiel ; aucun ancien fichier accepte.' }
    $coreDirectory=Join-Path $Directory 'core-only'
    [void](New-Item -ItemType Directory -Path $coreDirectory)
    [void](Invoke-VutArchiveTool -Path $sevenZip -Arguments @('e','-y',('-o'+$coreDirectory),$OuterPath,$entry.Path))
    $files=@(Get-ChildItem -LiteralPath $coreDirectory -File)
    if ($files.Count -ne 1 -or $files[0].Name -cne $entry.FileName) { throw 'Extraction GIGABYTE non limitee au seul coeur attendu.' }
    $signature=Test-MbxSignedPayload -Path $files[0].FullName -Signers $tool.Signers
    if ((ConvertTo-MbxVersion $signature.FileVersion.Trim()) -ne (ConvertTo-MbxVersion $entry.Version)) { throw 'Version du coeur GIGABYTE differente du nom officiel.' }
    if ((Get-VutGccInstallerProductName -Path $files[0].FullName) -cne 'GIGABYTE Control Center') { throw 'Identite produit GCC incorrecte : lanceur Liveupdate ou bundle refuse.' }
    return [pscustomobject]@{
        Path=$files[0].FullName;SHA256=$signature.SHA256;Version=$signature.FileVersion.Trim();Kind='gigabyte_core'
        Audit=$audit;Discovery=$discovery;CoreFileName=$entry.FileName;CoreSignature=$signature;VendorInstallerExecuted=$false
    }
}
