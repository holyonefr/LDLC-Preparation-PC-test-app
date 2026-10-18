#requires -Version 5.1
# Definitions only, dot-sourced inside VendorUtility. No installer is ever invoked here.
function Resolve-VutGigabyteCoreDownload {
    # GCC's own ExtLIB_Loader_Lib.Web_Sync_Class reads this software-only
    # manifest and constructs this path. No hardware/driver catalogue is queried.
    $url='https://mb.download.gigabyte.com/FileList/Swhttp/LiveUpdate4/GCC/GIGABYTE%20Control%20Center/ver2.ini'
    $response=Invoke-MbxHttp -Url $url -Hosts @('mb.download.gigabyte.com') -TimeoutSeconds 30 -MaxBytes 65536
    $r=ConvertFrom-VutGigabyteCoreManifest -Text ([string]$response.Text)
    $r.ManifestUrl=$response.Url
    return $r
}

function ConvertFrom-VutGigabyteCoreManifest {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    if ($Text.Length -gt 65536 -or $Text -match '[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]') { throw 'Manifeste du programme GCC invalide ou trop volumineux.' }
    $info=@{}; $section=''; $infoCount=0
    foreach ($line in $Text -split '\r?\n') {
        $line=$line.Trim()
        if (-not $line -or $line.StartsWith(';')) { continue }
        if ($line -match '\A\[([^\]]+)\]\z') {
            $section=$Matches[1]
            if ($section -ieq 'Info') { $infoCount++ }
            continue
        }
        if ($section -ine 'Info') { continue }
        if ($line -notmatch '\A([A-Za-z]+)=(.*)\z') { throw 'Entree Info GCC mal formee.' }
        $key=$Matches[1]; $value=$Matches[2].Trim()
        if ($info.ContainsKey($key)) { throw 'Manifeste GCC ambigu : cle Info dupliquee.' }
        $info[$key]=$value
    }
    if ($infoCount -ne 1) { throw 'Section Info GCC absente ou ambigue.' }
    foreach ($key in @('ApName','DisplayName','ApNum','Ver','Size')) { if (-not $info.ContainsKey($key)) { throw ('Manifeste GCC incomplet : '+$key+' absent.') } }
    if ($info.ApName -cne 'GIGABYTE Control Center' -or $info.DisplayName -cne 'GIGABYTE Control Center' -or $info.ApNum -cne '0') { throw 'Manifeste hors du seul programme GIGABYTE Control Center.' }
    if ($info.Ver -notmatch '\A[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\z' -or -not (ConvertTo-MbxVersion $info.Ver)) { throw 'Version du programme GCC invalide.' }
    $size=[long]0
    if ($info.Size -notmatch '\A[0-9]+\z' -or -not [long]::TryParse($info.Size,[ref]$size) -or $size -lt 1024 -or $size -gt 1073741824) { throw 'Taille du programme GCC absente ou invalide.' }
    $file='GIGABYTE Control Center_'+$info.Ver+'.exe'
    return [pscustomobject]@{
        ManifestUrl='https://mb.download.gigabyte.com/FileList/Swhttp/LiveUpdate4/GCC/GIGABYTE%20Control%20Center/ver2.ini'
        Version=$info.Ver;ExpectedBytes=$size;FileName=$file
        DownloadUrl=('https://mb.download.gigabyte.com/FileList/Swhttp/LiveUpdate4/GCC/GIGABYTE%20Control%20Center/'+[uri]::EscapeDataString($file))
        Method='official_gcc_software_update_manifest'
    }
}

function Resolve-VutGigabyteDownload {
    $manifestUrl='https://www.gigabyte.com/Ajax/SupportFunction/GetUtilityAjax?ClassGroup=2&Page=1&KeyWord=GIGABYTE%20Control%20Center'
    $sources=@(
        @{Url=$manifestUrl;Agent='MotherboardFeasibility/1.0';Client='default'},
        @{Url=$manifestUrl;Agent='Mozilla/5.0 (Windows NT 10.0; Win64; x64)';Client='browser_user_agent'},
        @{Url='https://www.gigabyte.com/Consumer/Software/GIGABYTE-Control-Center/global/';Agent='Mozilla/5.0 (Windows NT 10.0; Win64; x64)';Client='official_product_page'}
    )
    $failures=@()
    foreach ($source in $sources) {
        try { $response=Invoke-MbxHttp -Url $source.Url -Hosts @('www.gigabyte.com') -TimeoutSeconds 30 -MaxBytes 2097152 -UserAgent $source.Agent }
        catch {
            if ($_.Exception.Message -notmatch 'HTTP 403\b') { throw }
            $failures+=($source.Client+': HTTP 403'); continue
        }
        $resolved=ConvertFrom-VutGigabyteCatalogue -Html ([string]$response.Text)
        $resolved.ManifestUrl=$response.Url
        $resolved | Add-Member -NotePropertyName SourceClient -NotePropertyValue $source.Client
        return $resolved
    }
    throw ('Catalogue GIGABYTE officiel inaccessible ('+($failures -join '; ')+'). Aucune ancienne version utilisee.')
}

function ConvertFrom-VutGigabyteCatalogue {
    param([Parameter(Mandatory)][string]$Html)
    $manifestUrl='https://www.gigabyte.com/Ajax/SupportFunction/GetUtilityAjax?ClassGroup=2&Page=1&KeyWord=GIGABYTE%20Control%20Center'
    if ($Html.Length -gt 2097152) { throw 'Catalogue GIGABYTE trop volumineux.' }
    $candidates=@()
    foreach ($match in [regex]::Matches($html,'(?is)\bhref\s*=\s*["'']([^"'']+)["'']')) {
        $href=[Net.WebUtility]::HtmlDecode($match.Groups[1].Value)
        if ($href -match '[\x00-\x20\x7f]') { continue }
        try { $uri=New-Object uri([uri]$manifestUrl,$href) } catch { continue }
        if ($uri.Scheme -ne 'https' -or $uri.Port -ne 443 -or $uri.UserInfo -or $uri.Fragment -or $uri.DnsSafeHost -ine 'download.gigabyte.com') { continue }
        $file=[uri]::UnescapeDataString($uri.Segments[-1])
        if ($file -notmatch '\AGCC_([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)\.zip\z') { continue }
        $rawVersion=$Matches[1]; $version=ConvertTo-MbxVersion $rawVersion
        if (-not $version) { continue }
        $candidates+=@([pscustomobject]@{ BundleVersion=$rawVersion; ParsedVersion=$version; DownloadUrl=$uri.AbsoluteUri })
    }
    if (-not $candidates.Count) { throw 'Catalogue GIGABYTE officiel sans lien GCC valide ; aucune ancienne version de secours.' }
    $groups=@($candidates | Group-Object { $_.ParsedVersion.ToString() })
    foreach ($group in $groups) {
        $urls=@($group.Group | Select-Object -ExpandProperty DownloadUrl -Unique)
        if ($urls.Count -ne 1) { throw 'Catalogue GIGABYTE ambigu : plusieurs fichiers pour une meme version.' }
    }
    foreach ($inputTag in [regex]::Matches($html,'(?is)<input\b[^>]*>')) {
        if ($inputTag.Value -match '(?i)\bid\s*=\s*["'']now_page["'']' -and $inputTag.Value -match '(?i)\bvalue\s*=\s*["'']([^"'']+)["'']') {
            if ($Matches[1] -ne '1') { throw 'Catalogue GIGABYTE pagine incomplet : premiere page non confirmee.' }
        }
    }
    foreach ($total in [regex]::Matches($html,'(?is)<span\b[^>]*class\s*=\s*["'']items["''][^>]*>\s*([^<]+)\s*</span>')) {
        $countText=$total.Groups[1].Value.Trim(); $count=0
        if (-not [int]::TryParse($countText,[ref]$count) -or $count -ne $groups.Count) { throw 'Catalogue GIGABYTE pagine incomplet ou incoherent : tous les elements ne sont pas disponibles ; derniere version non etablie.' }
    }
    $latest=@($candidates | Sort-Object ParsedVersion -Descending)[0]
    return [pscustomobject]@{
        ManifestUrl=$manifestUrl; BundleVersion=$latest.BundleVersion
        DownloadUrl=$latest.DownloadUrl; Method='official_gigabyte_utility_html'
    }
}
