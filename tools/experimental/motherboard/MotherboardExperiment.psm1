#requires -Version 5.1
Set-StrictMode -Version 2

function Get-MbxValue {
    param($Object, [string]$Name, $Default = '')
    if ($null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]) { return $Object.$Name }
    return $Default
}

function Get-MbxVendor {
    param([string]$Name)
    switch -Regex ($Name.Trim()) {
        '^(Micro-Star International(?: Co\.,? Ltd\.?)?|MSI)$' { return 'MSI' }
        '^(ASUSTeK COMPUTER INC\.?|ASUS|ASUSTeK)$' { return 'ASUS' }
        '^(Gigabyte Technology Co\.,? Ltd\.?|GIGABYTE)$' { return 'GIGABYTE' }
        '^ASRock(?: Inc\.?)?$' { return 'ASRock' }
        default { return '' }
    }
}

function Test-MbxPlaceholder {
    param([string]$Text)
    return ([string]::IsNullOrWhiteSpace($Text) -or $Text.Trim() -match '^(?i:To be filled by O\.?E\.?M\.?|Default string|System (Product Name|manufacturer|Version)|OEM|Unknown|Not (Applicable|Specified)|N/A|None|All Series)$')
}

function Get-MbxInventory {
    [CmdletBinding()]
    param([ValidateRange(1,60)][int]$QueryTimeoutSeconds = 15)
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Inventaire reel disponible uniquement sous Windows.' }
    $errors = New-Object 'System.Collections.Generic.List[object]'
    $records = @{}
    foreach ($class in @('Win32_BaseBoard','Win32_ComputerSystem','Win32_SystemEnclosure','Win32_BIOS','Win32_OperatingSystem','Win32_PnPEntity','Win32_PnPSignedDriver')) {
        try {
            $records[$class] = @(Get-CimInstance -ClassName $class -OperationTimeoutSec $QueryTimeoutSeconds -ErrorAction Stop)
        }
        catch {
            $errors.Add([pscustomobject]@{ Class=$class; ErrorType=$_.Exception.GetType().Name; Message=$_.Exception.Message })
            $records[$class]=@()
        }
    }
    $boards = @($records.Win32_BaseBoard | ForEach-Object { [pscustomobject]@{
        Manufacturer=[string]$_.Manufacturer; Product=[string]$_.Product; Revision=[string]$_.Version
    } })
    $computers = @($records.Win32_ComputerSystem | ForEach-Object { [pscustomobject]@{
        Manufacturer=[string]$_.Manufacturer; Model=[string]$_.Model; PCSystemType=$_.PCSystemType
    } })
    $oses = @($records.Win32_OperatingSystem | ForEach-Object { [pscustomobject]@{
        Caption=[string]$_.Caption; Version=[string]$_.Version; BuildNumber=[string]$_.BuildNumber; Architecture=[string]$_.OSArchitecture
    } })
    $bios = @($records.Win32_BIOS | ForEach-Object { [pscustomobject]@{
        Manufacturer=[string]$_.Manufacturer; SMBIOSBIOSVersion=[string]$_.SMBIOSBIOSVersion; Version=[string]$_.Version; ReleaseDate=[string]$_.ReleaseDate
    } })
    $devices = @($records.Win32_PnPEntity | Where-Object { $_.Present -ne $false -and $_.ConfigManagerErrorCode -ne 45 } | ForEach-Object { [pscustomobject]@{
        Name=[string]$_.Name; Class=[string]$_.PNPClass; DeviceID=[string]$_.DeviceID; HardwareIDs=@($_.HardwareID); ErrorCode=$_.ConfigManagerErrorCode
    } })
    $drivers = @($records.Win32_PnPSignedDriver | ForEach-Object { [pscustomobject]@{
        Name=[string]$_.DeviceName; Class=[string]$_.DeviceClass; DeviceID=[string]$_.DeviceID; Version=[string]$_.DriverVersion
        Provider=[string]$_.DriverProviderName; IsSigned=[bool]$_.IsSigned; Inf=[string]$_.InfName; DriverDate=[string]$_.DriverDate
    } })
    # Registry reads only; Win32_Product is deliberately not used (MSI repair side effects).
    $utilities = @()
    foreach ($path in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
        $utilities += @(Get-ItemProperty -Path $path -ErrorAction SilentlyContinue | Where-Object {
            (Get-MbxValue $_ 'DisplayName') -match '(?i)MSI Center|ASUS DriverHub|GIGABYTE Control Center|ASRock (APP Shop|Auto Driver Installer)'
        } | ForEach-Object { [pscustomobject]@{ Name=[string]$_.DisplayName; Version=[string](Get-MbxValue $_ 'DisplayVersion'); Publisher=[string](Get-MbxValue $_ 'Publisher'); Evidence='uninstall registry entry only' } })
    }
    return [pscustomobject]@{
        Kind='RealCimInventory'; CapturedUtc=[DateTime]::UtcNow.ToString('o'); BaseBoards=$boards; Computers=$computers; OperatingSystems=$oses; Bios=$bios
        ChassisTypes=@($records.Win32_SystemEnclosure | ForEach-Object { $_.ChassisTypes })
        Devices=$devices; Drivers=$drivers; InstalledUtilityEntries=$utilities
        ChipsetEvidence=@($devices | Where-Object { $_.Class -eq 'System' -and $_.Name -match '(?i)chipset|SMBus|host bridge|LPC|ISA bridge' })
        ChipsetCertainty='PnP evidence only; exact chipset may be unavailable'; Errors=@($errors.ToArray())
    }
}

function Get-MbxToolDefinitions {
    return @(
        [pscustomobject]@{ Vendor='MSI'; Tool='MSI Center'; Page='https://www.msi.com/Landing/MSI-Center'; Hosts=@('msi.com'); FilePattern='(?i)^MSI[_ -]?Center[^/]*\.(zip|exe)$'; Signers=@('Micro-Star International Co., Ltd.','MICRO-STAR INTERNATIONAL CO., LTD.'); DriverCli='NotConfirmed'; Note='MSI Driver Utility Installer is a separate motherboard/UEFI feature, not a universal silent driver CLI.' },
        [pscustomobject]@{ Vendor='ASUS'; Tool='ASUS DriverHub'; Page='https://driverhub.asus.com/en'; Hosts=@('asus.com'); FilePattern='(?i)^(ASUS[_ -]?)?DriverHub[^/]*\.(zip|exe)$'; Signers=@('ASUSTeK COMPUTER INC.'); DriverCli='NotConfirmed'; Note='Do not treat an installer silent flag as a documented driver scan or apply command.' },
        [pscustomobject]@{ Vendor='GIGABYTE'; Tool='GIGABYTE Control Center'; Page='https://www.gigabyte.com/Consumer/Software/GIGABYTE-Control-Center/global/'; Hosts=@('gigabyte.com'); FilePattern='(?i)^(GCC|GIGABYTE[-_ ]?Control[-_ ]?Center|mb_utility_gcc)[^/]*\.(zip|exe)$'; Signers=@('GIGA-BYTE TECHNOLOGY CO., LTD.','GIGABYTE TECHNOLOGY CO., LTD.'); DriverCli='NotConfirmed'; Note='App selection, firmware and optional software need explicit control in the vendor UI.' },
        [pscustomobject]@{ Vendor='ASRock'; Tool='APP Shop / Auto Driver Installer (model dependent)'; Page='https://www.asrock.com/feature/appshop/'; Hosts=@('asrock.com'); FilePattern='(?!)'; Signers=@('ASRock Inc.'); DriverCli='NotConfirmed'; Note='APP Shop is a UI with driver, BIOS and app choices. Auto Driver Installer is firmware/model dependent; no guessed universal package.' }
    )
}

function Resolve-MbxTool {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Inventory, [object[]]$SupportEvidence = @())
    $result=[ordered]@{ Status='manual_required'; Vendor=''; BoardModel=''; BoardRevision=''; Tool=''; OfficialPage=''; Compatibility='unverified'; Reason=''; CanDownloadForInstallation=$false; CanScanAutomatically=$false; CanInstallDriversAutomatically=$false }
    $boards=@(Get-MbxValue $Inventory 'BaseBoards' @())
    $computers=@(Get-MbxValue $Inventory 'Computers' @())
    $os=@(Get-MbxValue $Inventory 'OperatingSystems' @())
    if ($boards.Count -ne 1 -or $computers.Count -ne 1 -or $os.Count -ne 1) {
        $result.Reason='Inventaire absent, partiel ou ambigu (carte mere, constructeur du PC ou Windows).'; return [pscustomobject]$result
    }
    $board=$boards[0]; $pc=$computers[0]
    $result.Vendor=Get-MbxVendor ([string](Get-MbxValue $board 'Manufacturer'))
    $result.BoardModel=[string](Get-MbxValue $board 'Product')
    $result.BoardRevision=[string](Get-MbxValue $board 'Revision')
    $pcManufacturer=[string](Get-MbxValue $pc 'Manufacturer'); $pcModel=[string](Get-MbxValue $pc 'Model')
    if (($pcManufacturer+' '+$pcModel) -match '(?i)Microsoft Corporation.*Virtual Machine|VMware|VirtualBox|KVM|QEMU|Xen|Amazon EC2|Google Compute') {
        $result.Reason='Machine virtuelle : aucun utilitaire de carte mere physique selectionne.'; return [pscustomobject]$result
    }
    if (-not $result.Vendor) { $result.Reason='Fabricant de carte mere inconnu : utiliser le support du constructeur du PC.'; return [pscustomobject]$result }
    $pcVendor=Get-MbxVendor $pcManufacturer
    if (-not (Test-MbxPlaceholder $pcManufacturer) -and $pcVendor -ne $result.Vendor) {
        $result.Reason="PC OEM ($pcManufacturer / $pcModel) : le support du PC prime sur le fabricant de la carte mere."; return [pscustomobject]$result
    }
    $portable=@(Get-MbxValue $Inventory 'ChassisTypes' @() | Where-Object { $_ -in @(8,9,10,11,12,14,30,31,32) }).Count -gt 0
    if ($portable -or (Get-MbxValue $pc 'PCSystemType' 0) -eq 2) {
        $result.Reason='Portable : un outil de carte mere de bureau ne prouve pas sa compatibilite avec ce modele OEM.'; return [pscustomobject]$result
    }
    $tool=@(Get-MbxToolDefinitions | Where-Object { $_.Vendor -eq $result.Vendor })[0]
    $result.Tool=$tool.Tool; $result.OfficialPage=$tool.Page
    if ((Test-MbxPlaceholder $result.BoardModel) -or (Test-MbxPlaceholder $result.BoardRevision)) {
        $result.Reason='Modele ou revision SMBIOS absent : compatibilite exacte non prouvee.'; return [pscustomobject]$result
    }
    $matches=@($SupportEvidence | Where-Object {
        (Get-MbxValue $_ 'Vendor') -eq $result.Vendor -and
        (Get-MbxValue $_ 'Model') -ieq $result.BoardModel -and
        (Get-MbxValue $_ 'Revision') -ieq $result.BoardRevision -and
        (Get-MbxValue $_ 'OsBuild') -eq [string](Get-MbxValue $os[0] 'BuildNumber') -and
        (Get-MbxValue $_ 'Architecture') -eq [string](Get-MbxValue $os[0] 'Architecture') -and
        (Get-MbxValue $_ 'ExplicitSupport' $false) -eq $true -and
        (Test-MbxOfficialUri ([string](Get-MbxValue $_ 'Source')) $tool.Hosts)
    })
    if ($matches.Count -ne 1) {
        $result.Reason='Outil candidat identifie ; aucune preuve actuelle de compatibilite exacte modele/revision/Windows. Verification manuelle requise.'
        return [pscustomobject]$result
    }
    # Injected evidence is useful to test selection, not a live compatibility declaration.
    $result.Compatibility='evidence_supplied_requires_vendor_confirmation'
    $result.Reason='Correspondance exacte dans les donnees fournies ; confirmer sur le support officiel du modele avant installation.'
    return [pscustomobject]$result
}

function ConvertTo-MbxVersion {
    param([string]$Value)
    if ($Value -notmatch '^\d+(?:\.\d+){0,3}$') { return $null }
    try {
        $parts=@($Value.Split('.')); while ($parts.Count -lt 4) { $parts+='0' }
        return [version]($parts -join '.')
    } catch { return $null }
}

function Select-MbxDriverCandidates {
    [CmdletBinding()]
    param([object[]]$Candidates=@(), [object[]]$Devices=@(), [object[]]$InstalledDrivers=@())
    $results=@()
    foreach ($item in $Candidates) {
        $name=[string](Get-MbxValue $item 'Name'); $kind=[string](Get-MbxValue $item 'Kind')
        $status='ignored'; $reason='Type non autorise : aucun logiciel additionnel selectionne.'
        if (($name+' '+$kind) -match '(?i)antivirus|anti[- ]?malware|security suite|internet security|Norton|McAfee|Avast|AVG|Kaspersky|Bitdefender|ESET|Trend Micro|BullGuard|Symantec|protection|Defender') {
            $reason='Logiciel de protection exclu de la selection constructeur ; aucune modification de Defender ou Windows Update.'
        }
        elseif (($name+' '+$kind) -match '(?i)BIOS|UEFI|firmware') { $status='firmware_manual'; $reason='BIOS/UEFI/firmware : validation explicite du technicien, aucune execution.' }
        elseif ($kind -eq 'Driver') {
            $class=[string](Get-MbxValue $item 'Class')
            if ($class -eq 'Display' -or $name -match '(?i)Adrenalin|GeForce|Radeon|NVIDIA.*(driver|display)') { $reason='Pilote GPU reserve au mecanisme AMD/NVIDIA existant.' }
            elseif ($class -notin @('System','Net','Bluetooth','MEDIA','USB','HDC','SCSIAdapter','Storage')) { $reason='Classe de pilote hors perimetre.' }
            else {
                $ids=@(Get-MbxValue $item 'HardwareIDs' @())
                $matched=@($Devices | Where-Object { $dev=$_; @((Get-MbxValue $dev 'HardwareIDs' @()) | Where-Object { $ids -contains $_ }).Count -gt 0 })
                if (-not $ids.Count -or $matched.Count -ne 1) { $status='manual_required'; $reason='Identifiants materiels absents ou correspondance ambigue.' }
                else {
                    $installed=@($InstalledDrivers | Where-Object { (Get-MbxValue $_ 'DeviceID') -eq (Get-MbxValue $matched[0] 'DeviceID') })
                    $offered=ConvertTo-MbxVersion ([string](Get-MbxValue $item 'Version'))
                    $current=$null
                    if ($installed.Count -eq 1) { $current=ConvertTo-MbxVersion ([string](Get-MbxValue $installed[0] 'Version')) }
                    $provider=[string](Get-MbxValue $item 'Provider')
                    if (-not $current -or -not $offered -or $installed.Count -ne 1 -or [string]::IsNullOrWhiteSpace($provider) -or $provider -ine [string](Get-MbxValue $installed[0] 'Provider')) {
                        $status='manual_required'; $reason='Versions ou fournisseur non comparables ; aucune mise a niveau annoncee.'
                    }
                    elseif ($offered -le $current) { $status='up_to_date'; $reason='Version proposee egale ou anterieure : aucune retrogradation.' }
                    else { $status='candidate_only'; $reason='Version numerique plus recente pour le meme materiel/fournisseur ; installation non realisee ni autorisee par ce prototype.' }
                }
            }
        }
        $results+=[pscustomobject]@{ Name=$name; Status=$status; Reason=$reason; Installed=$false; RebootInitiated=$false }
    }
    return $results
}

function Test-MbxOfficialUri {
    param([string]$Url, [string[]]$Hosts)
    try {
        $u=[uri]$Url
        if (-not $u.IsAbsoluteUri -or $u.Scheme -ne 'https' -or $u.Port -ne 443 -or $u.UserInfo) { return $false }
        foreach ($h in $Hosts) { if ($u.DnsSafeHost -ieq $h -or $u.DnsSafeHost.EndsWith('.'+$h,[StringComparison]::OrdinalIgnoreCase)) { return $true } }
    } catch {}
    return $false
}

function New-MbxHttpHandler {
    $handler=New-Object Net.Http.HttpClientHandler
    $handler.AllowAutoRedirect=$false
    return $handler
}

function Invoke-MbxHttp {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Url, [Parameter(Mandatory)][string[]]$Hosts,
        [ValidateRange(1,600)][int]$TimeoutSeconds=30, [ValidateRange(1024,1073741824)][long]$MaxBytes=8388608,
        [string]$OutFile, [switch]$Head,[string]$UserAgent='MotherboardFeasibility/1.0')
    Add-Type -AssemblyName System.Net.Http
    $handler=New-MbxHttpHandler
    $client=New-Object Net.Http.HttpClient($handler)
    $client.Timeout=[Threading.Timeout]::InfiniteTimeSpan
    $client.DefaultRequestHeaders.UserAgent.ParseAdd($UserAgent)
    $cts=New-Object Threading.CancellationTokenSource
    $cts.CancelAfter([TimeSpan]::FromSeconds($TimeoutSeconds))
    $response=$null; $stream=$null; $sink=$null; $part=$null; $total=[long]0; $expected=$null
    $chain=New-Object 'System.Collections.Generic.List[string]'
    try {
        $current=[uri]$Url
        for ($hop=0; $hop -le 6; $hop++) {
            if (-not (Test-MbxOfficialUri $current.AbsoluteUri $Hosts)) { throw 'Destination HTTPS officielle refusee (y compris redirection).' }
            $chain.Add($current.AbsoluteUri)
            $request=New-Object Net.Http.HttpRequestMessage
            $request.RequestUri=$current
            $request.Method=if ($Head) { [Net.Http.HttpMethod]::Head } else { [Net.Http.HttpMethod]::Get }
            try { $response=$client.SendAsync($request,[Net.Http.HttpCompletionOption]::ResponseHeadersRead,$cts.Token).GetAwaiter().GetResult() }
            finally { $request.Dispose() }
            $code=[int]$response.StatusCode
            if ($code -in @(301,302,303,307,308)) {
                if ($hop -eq 6 -or -not $response.Headers.Location) { throw 'Redirection sans destination ou limite de six sauts atteinte.' }
                $current=New-Object uri($current,$response.Headers.Location)
                $response.Dispose(); $response=$null; continue
            }
            if (-not $response.IsSuccessStatusCode) { throw "HTTP $code sur la source officielle." }
            if ($code -ne 200) { throw "Reponse incomplete ou inattendue : HTTP $code." }
            break
        }
        $expected=$response.Content.Headers.ContentLength
        $suggestedName=''
        if ($response.Content.Headers.ContentDisposition) {
            $disposition=$response.Content.Headers.ContentDisposition
            $suggestedName=if ($disposition.FileNameStar) { [string]$disposition.FileNameStar } else { [string]$disposition.FileName }
            $suggestedName=$suggestedName.Trim('"')
        }
        if ($Head) { return [pscustomobject]@{ Url=$current.AbsoluteUri; Redirects=@($chain.ToArray()); HttpStatus=$code; Bytes=0; ExpectedBytes=$expected; Text=''; File=''; HeadersOnly=$true; SuggestedFileName=$suggestedName } }
        if ($null -ne $expected -and $expected -gt $MaxBytes) { throw "Taille annoncee ($expected octets) superieure a la limite de lecture ($MaxBytes octets)." }
        $stream=$response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        if ($OutFile) {
            $part=$OutFile+'.'+[guid]::NewGuid().ToString('N')+'.part'
            $sink=[IO.File]::Open($part,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        } else { $sink=New-Object IO.MemoryStream }
        $buffer=New-Object byte[] 65536; $total=[long]0
        $progressClock=[Diagnostics.Stopwatch]::StartNew(); $lastProgress=[long]-500; $progressUpdates=0
        while (($read=$stream.ReadAsync($buffer,0,$buffer.Length,$cts.Token).GetAwaiter().GetResult()) -gt 0) {
            $total+=$read
            if ($total -gt $MaxBytes) { throw 'Taille maximale de lecture depassee.' }
            $sink.Write($buffer,0,$read)
            if ($OutFile -and $expected -gt 0 -and ($progressClock.ElapsedMilliseconds-$lastProgress) -ge 500) {
                Write-Progress -Activity 'Controle du telechargement officiel (sans execution)' -Status "$total / $expected octets" -PercentComplete ([Math]::Min(99,[int](100*$total/$expected)))
                $lastProgress=$progressClock.ElapsedMilliseconds; $progressUpdates++
            }
        }
        if ($null -ne $expected -and $total -ne $expected) { throw "Telechargement interrompu : $total octets recus, $expected attendus." }
        if ($total -eq 0) { throw 'Reponse vide.' }
        $text=''
        if ($OutFile) {
            $sink.Dispose(); $sink=$null
            # Never overwrite a pre-existing file silently.
            [IO.File]::Move($part,$OutFile); $part=$null
            Write-Progress -Activity 'Controle du telechargement officiel (sans execution)' -Completed
        } else { $text=[Text.Encoding]::UTF8.GetString($sink.ToArray()) }
        return [pscustomobject]@{ Url=$current.AbsoluteUri; Redirects=@($chain.ToArray()); HttpStatus=$code; Bytes=$total; ExpectedBytes=$expected; Text=$text; File=$OutFile; ProgressUpdates=$progressUpdates; SuggestedFileName=$suggestedName }
    }
    catch {
        if ($cts.IsCancellationRequested) { throw "Delai de lecture depasse ($TimeoutSeconds s) : $total octets recus, $expected attendus ; aucun telechargement valide." }
        throw
    }
    finally {
        if ($sink) { $sink.Dispose() }; if ($stream) { $stream.Dispose() }; if ($response) { $response.Dispose() }
        $cts.Dispose(); $client.Dispose(); $handler.Dispose()
        if ($part -and [IO.File]::Exists($part)) { [IO.File]::Delete($part) }
    }
}

function Get-MbxDownloadLinks {
    param([string]$Html, [string]$PageUrl, [Parameter(Mandatory)]$Tool)
    $links=@()
    foreach ($m in [regex]::Matches($Html,'(?is)(?:href|src)\s*=\s*["'']([^"'']+)["'']|https://[^"''<>\s\\]+')) {
        try {
            $value=if ($m.Groups[1].Success) { $m.Groups[1].Value } else { $m.Value }
            $url=(New-Object uri([uri]$PageUrl,[Net.WebUtility]::HtmlDecode($value))).AbsoluteUri
            $file=[uri]::UnescapeDataString(([uri]$url).Segments[-1])
            if ($file -match $Tool.FilePattern -and (Test-MbxOfficialUri $url $Tool.Hosts)) { $links+=$url }
        } catch {}
    }
    return @($links | Select-Object -Unique)
}

function Test-MbxSignedPayload {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string[]]$Signers)
    $length=(Get-Item -LiteralPath $Path).Length
    $s=[IO.File]::OpenRead($Path)
    try { $first=$s.ReadByte(); $second=$s.ReadByte() } finally { $s.Dispose() }
    if ($length -lt 1024 -or $first -ne 77 -or $second -ne 90) { throw 'Fichier PE/MZ absent ou trop petit.' }
    $signature=Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop
    if ([string]$signature.Status -ne 'Valid' -or -not $signature.SignerCertificate) { throw "Signature numerique non valide : $($signature.Status)." }
    $signer=$signature.SignerCertificate.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName,$false)
    if ($Signers -notcontains $signer) { throw "Editeur du fichier non autorise : $signer." }
    $version=''; try { $version=[Diagnostics.FileVersionInfo]::GetVersionInfo($Path).FileVersion } catch {}
    return [pscustomobject]@{ Status='Valid'; Signer=$signer; SHA256=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash; Bytes=$length; FileVersion=$version }
}

function Invoke-MbxUtilityAudit {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Tool, [Parameter(Mandatory)][string]$DownloadUrl,
        [Parameter(Mandatory)][string]$OutputDirectory, [ValidateRange(1,600)][int]$TimeoutSeconds=600)
    # Download audit is independent of hardware recommendation. Never invoke the payload.
    $requestedUrl=$DownloadUrl; $shortlinkRedirects=@(); $resolvedName=''
    if (-not (Test-MbxOfficialUri $DownloadUrl $Tool.Hosts)) { throw 'Lien non officiel refuse.' }
    if ($Tool.Vendor -eq 'ASUS' -and $DownloadUrl -eq 'https://geo.asus.com/driverhub/') {
        # Official shortlink observed in DriverHub's own current JavaScript. Inspect HTTPS redirects only.
        $resolved=Invoke-MbxHttp -Url $DownloadUrl -Hosts $Tool.Hosts -TimeoutSeconds $TimeoutSeconds -Head
        $shortlinkRedirects=@($resolved.Redirects)
        $DownloadUrl=$resolved.Url
        if ($resolved.SuggestedFileName) {
            $resolvedName=$resolved.SuggestedFileName
        } elseif ([uri]::UnescapeDataString(([uri]$DownloadUrl).Segments[-1]) -notmatch $Tool.FilePattern) {
            # A public HTML/JavaScript download link is read as text, never evaluated.
            $landing=Invoke-MbxHttp -Url $DownloadUrl -Hosts $Tool.Hosts -TimeoutSeconds 30 -MaxBytes 2097152
            $html=$landing.Text -replace '\\/','/' -replace '\\u0026','&'
            $links=@(Get-MbxDownloadLinks -Html $html -PageUrl $landing.Url -Tool $Tool)
            if ($links.Count -ne 1) { throw "Page officielle ASUS : $($links.Count) lien(s) de fichier non ambigus ; verification manuelle requise." }
            $DownloadUrl=$links[0]
        }
    }
    $name=if ($resolvedName) { $resolvedName } else { [uri]::UnescapeDataString(([uri]$DownloadUrl).Segments[-1]) }
    if ($name -notmatch $Tool.FilePattern -or $name -ne [IO.Path]::GetFileName($name) -or $name -match '[\\/:*?"<>|]') { throw "Nom de fichier hors du perimetre de cet utilitaire : $name (source officielle $DownloadUrl)." }
    $auditDir=Join-Path $OutputDirectory ([guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $auditDir -Force)
    $path=Join-Path $auditDir $name
    $result=Invoke-MbxHttp -Url $DownloadUrl -Hosts $Tool.Hosts -TimeoutSeconds $TimeoutSeconds -MaxBytes 1073741824 -OutFile $path
    # Redirects must also preserve the intended utility identity.
    $finalName=[uri]::UnescapeDataString(([uri]$result.Url).Segments[-1])
    if ($finalName -notmatch $Tool.FilePattern -and $result.SuggestedFileName -ine $name) { throw 'La redirection ne preserve pas le nom attendu de l utilitaire.' }
    $payloads=@()
    if ([IO.Path]::GetExtension($path) -ieq '.exe') {
        $payloads+=Test-MbxSignedPayload -Path $path -Signers $Tool.Signers
    } else {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        Add-Type -AssemblyName System.IO.Compression
        $zip=[IO.Compression.ZipFile]::OpenRead($path)
        try {
            $expanded=[long]0; $index=0
            foreach ($entry in $zip.Entries) {
                if ($entry.FullName -match '(^[/\\]|(^|[/\\])\.\.([/\\]|$)|:)') { throw 'Archive avec chemin dangereux refusee.' }
                $expanded+=$entry.Length
                if ($expanded -gt 2147483648) { throw 'Archive trop volumineuse une fois decompressee.' }
                if ([IO.Path]::GetExtension($entry.Name) -ine '.exe') { continue }
                # Fixed extraction names prevent archive path traversal, no external archiver is run.
                $payload=Join-Path $auditDir ('payload-'+$index+'.exe'); $index++
                $inputStream=$entry.Open(); $outputStream=[IO.File]::Create($payload)
                try { $inputStream.CopyTo($outputStream) } finally { $inputStream.Dispose(); $outputStream.Dispose() }
                $payloads+=Test-MbxSignedPayload -Path $payload -Signers $Tool.Signers
            }
        } finally { $zip.Dispose() }
        if (-not $payloads.Count) { throw 'Archive sans executable signe verifiable ; aucune validation annoncee.' }
    }
    return [pscustomobject]@{
        Vendor=$Tool.Vendor; Tool=$Tool.Tool; Status='download_and_signed_executables_verified'
        RequestedUrl=$requestedUrl; FinalUrl=$result.Url; Redirects=@($shortlinkRedirects + @($result.Redirects) | Select-Object -Unique); Bytes=$result.Bytes; ExpectedBytes=$result.ExpectedBytes
        ProgressUpdates=$result.ProgressUpdates
        SHA256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash; Payloads=$payloads
        ReportedExecutableVersion=if ($payloads.Count -eq 1) { $payloads[0].FileVersion } else { '' }
        ArchivePublisherHash='not_available'; LatestVersion='not_established'; HardwareCompatibility='not_established'
        Installed=$false; Executed=$false; FirmwareFlashed=$false
    }
}

function Write-MbxEvidence {
    param([string]$Kind, [Parameter(Mandatory)]$Data)
    # Small independent annotations keep JSON retrievable when long log lines are truncated.
    # Callers pass public vendor evidence or inventory counts, never host/user identifiers.
    Add-Type -AssemblyName System.IO.Compression
    $buffer=New-Object IO.MemoryStream
    $gzip=New-Object IO.Compression.GZipStream($buffer,[IO.Compression.CompressionMode]::Compress,$true)
    $bytes=[Text.Encoding]::UTF8.GetBytes(($Data | ConvertTo-Json -Depth 14 -Compress))
    try { $gzip.Write($bytes,0,$bytes.Length) } finally { $gzip.Dispose() }
    $encoded=[Convert]::ToBase64String($buffer.ToArray()); $buffer.Dispose()
    $id=[guid]::NewGuid().ToString('N'); $count=[int][Math]::Ceiling($encoded.Length/3000.0)
    if ($count -gt 8) { throw 'Preuve trop volumineuse pour les annotations : consulter l artefact JSON.' }
    for ($index=0; $index -lt $count; $index++) {
        $part=$encoded.Substring($index*3000,[Math]::Min(3000,$encoded.Length-$index*3000))
        $line=[ordered]@{ Id=$id; Kind=$Kind; Codec='gzip-base64'; Index=$index; Count=$count; Data=$part } | ConvertTo-Json -Compress
        Write-Host ('::notice title=OEM evidence chunk::{0}' -f $line)
    }
}

Export-ModuleMember -Function *-Mbx*
