#requires -Version 5.1
# Private functions dot-sourced by VendorUtility.psm1. Discovery only: no installer execution.
function ConvertFrom-VutAsrockXml {
    param([Parameter(Mandatory)][string]$Text,[Parameter(Mandatory)][string]$Source)
    $settings=New-Object Xml.XmlReaderSettings
    $settings.DtdProcessing=[Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver=$null
    $settings.MaxCharactersInDocument=2097152
    $stringReader=New-Object IO.StringReader($Text)
    $reader=$null
    try {
        $reader=[Xml.XmlReader]::Create($stringReader,$settings)
        $document=New-Object Xml.XmlDocument
        $document.XmlResolver=$null
        $document.Load($reader)
        return ,$document
    } catch { throw ('Source ASRock '+$Source+' : XML officiel invalide ou page de protection ; aucun ancien fichier selectionne. '+$_.Exception.Message) }
    finally { if ($reader) { $reader.Dispose() }; $stringReader.Dispose() }
}

function Resolve-VutAsrockDownload {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Model,[Parameter(Mandatory)][string]$TargetOs)
    $requested=$Model.Trim()
    if (-not $requested -or $requested.Length -gt 150 -or $requested -match '[\x00-\x1F\x7F]') { throw 'ASRock : modele de carte mere absent ou invalide.' }
    if ($TargetOs -cnotin @('Windows 10 64bit','Windows 11 64bit')) { throw 'ASRock : systeme cible non autorise ; Windows 10/11 64 bits explicite requis.' }
    $modelSourceUrl='https://download.asrock.com/setup/Browser.xml'
    $response=Invoke-MbxHttp -Url $modelSourceUrl -Hosts @('download.asrock.com') -TimeoutSeconds 30 -MaxBytes 2097152
    $browser=ConvertFrom-VutAsrockXml -Text ([string](Get-MbxValue $response 'Text')) -Source 'Browser.xml'
    if (-not $browser.DocumentElement -or $browser.DocumentElement.Name -cne 'Root') { throw 'ASRock : structure Browser.xml inattendue ; compatibilite non confirmee.' }
    $matches=@($browser.SelectNodes('/Root/SupportModel/Item') | Where-Object { $_.GetAttribute('Model').Trim() -ieq $requested })
    if (-not $matches.Count) { throw ('ASRock : modele non present dans la liste officielle : '+$requested+'. Aucun installateur selectionne.') }
    $canonical=$matches[0].GetAttribute('Model').Trim()
    $manifestUrl='https://www.asrock.com/support/LiveUpdate.asp?Platform=App&Model='+[uri]::EscapeDataString($canonical)
    $response=Invoke-MbxHttp -Url $manifestUrl -Hosts @('www.asrock.com') -TimeoutSeconds 30 -MaxBytes 1048576
    $manifest=ConvertFrom-VutAsrockXml -Text ([string](Get-MbxValue $response 'Text')) -Source 'LiveUpdate'
    if (-not $manifest.DocumentElement -or $manifest.DocumentElement.Name -cne 'LiveUpdate' -or $manifest.DocumentElement.GetAttribute('Model').Trim() -ine $canonical) {
        throw 'ASRock : modele du catalogue officiel different du modele demande ; aucun alias ou ancien fichier suppose.'
    }
    # Restrict selection to the utility section. BIOS, drivers, adverts and their URLs are never inspected.
    $entries=@($manifest.SelectNodes('/LiveUpdate/Utility/*') | Where-Object {
        $description=$_.SelectSingleNode('Description')
        $_.GetAttribute('Title') -ieq 'ASRock APP Shop' -or ($description -and $description.InnerText.Trim() -ieq 'APP Shop')
    })
    if (-not $entries.Count) { throw ('ASRock : APP Shop absent du catalogue officiel pour '+$canonical+'. Aucun repli vers une ancienne version.') }
    $candidates=@()
    foreach ($entry in $entries) {
        $description=$entry.SelectSingleNode('Description')
        if ($entry.GetAttribute('Title') -ine 'ASRock APP Shop' -or -not $description -or $description.InnerText.Trim() -ine 'APP Shop') { throw 'ASRock : identite APP Shop incoherente dans le catalogue officiel.' }
        $versionText=$entry.GetAttribute('Version')
        $version=ConvertTo-MbxVersion $versionText
        if ($versionText -notmatch '\A[0-9]+(?:\.[0-9]+){1,3}\z' -or -not $version) { throw 'ASRock : version APP Shop absente ou invalide ; aucune ancienne version selectionnee.' }
        $candidates+=,[pscustomobject]@{Entry=$entry;Version=$version;VersionText=$versionText}
    }
    # Select the newest active version before checking its OS. Never silently fall back to an older compatible version.
    $latest=@($candidates | Sort-Object Version -Descending)[0].Version
    $candidates=@($candidates | Where-Object Version -eq $latest)
    $candidates=@($candidates | Where-Object {
        @($_.Entry.SelectNodes('File') | Where-Object { $_.GetAttribute('OS') -ceq $TargetOs }).Count -gt 0
    })
    if (-not $candidates.Count) { throw ('ASRock : derniere version '+$latest+' non proposee pour '+$TargetOs+' sur '+$canonical+' ; aucun repli ancien.') }
    $resolved=@()
    foreach ($candidate in $candidates) {
        $entry=$candidate.Entry; $versionText=$candidate.VersionText
        $hashNodes=@($entry.SelectNodes('HASH'))
        if ($hashNodes.Count -ne 1 -or $hashNodes[0].InnerText.Trim() -notmatch '\A[0-9a-fA-F]{64}\z') { throw 'ASRock : SHA256 officiel absent, multiple ou invalide.' }
        $hash=$hashNodes[0].InnerText.Trim().ToUpperInvariant()
        $exeNodes=@($entry.SelectNodes('FileExecute'))
        $parameterNodes=@($entry.SelectNodes('FileParameter'))
        if ($exeNodes.Count -ne 1 -or $parameterNodes.Count -ne 1) { throw 'ASRock : chemin executable ou parametres absents/ambigus.' }
        $exePath=$exeNodes[0].InnerText.Trim().Replace('\','/')
        $expectedExe='APPShop(v'+$versionText+')/APPShopSetup(v'+$versionText+').exe'
        if ($exePath -cne $expectedExe -or $exePath -match '\.\.|:|\A/') { throw 'ASRock : chemin executable inattendu ou version incoherente.' }
        $parameters=$parameterNodes[0].InnerText.Trim()
        if ($parameters -ine '/VerySilent') { throw 'ASRock : parametres officiels inattendus ; aucun commutateur prive ou lancement autorise.' }
        $files=@($entry.SelectNodes('File') | Where-Object { $_.GetAttribute('OS') -ceq $TargetOs })
        if (-not $files.Count) { throw ('ASRock : derniere version '+$versionText+' non proposee pour '+$TargetOs+' sur '+$canonical+' ; aucun repli ancien.') }
        foreach ($file in $files) {
            $value=$file.InnerText.Trim()
            $expectedPath='/Utility/Others/APPShop(v'+$versionText+').zip'
            if ($value -match '(?i)%2e|%2f|%5c|\\|\.\.' -or $value -match '[\x00-\x20\x7F]') { throw 'ASRock : URL de telechargement ou chemin non autorise.' }
            if ($value.StartsWith('/')) { $url='https://download.asrock.com'+$value } else { $url=$value }
            $uri=$null
            if (-not [uri]::TryCreate($url,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -cne 'https' -or $uri.Host -ine 'download.asrock.com' -or $uri.Port -ne 443 -or $uri.UserInfo -or $uri.Query -or $uri.Fragment -or [uri]::UnescapeDataString($uri.AbsolutePath) -cne $expectedPath) {
                throw 'ASRock : URL officielle, nom du ZIP ou version du fichier incoherent.'
            }
            $resolved+=,[pscustomobject]@{
                Model=$canonical;RequestedModel=$requested;TargetOs=$TargetOs;Version=$versionText
                ManifestUrl=$manifestUrl;ModelSourceUrl=$modelSourceUrl;DownloadUrl=$uri.AbsoluteUri
                ArchiveSHA256=$hash;InstallerRelativePath=$exePath;InstallerParameters=$parameters
                Method='official_asrock_model_xml'
            }
        }
    }
    $identities=@($resolved | ForEach-Object { $_.Version+'|'+$_.DownloadUrl+'|'+$_.ArchiveSHA256+'|'+$_.InstallerRelativePath+'|'+$_.InstallerParameters.ToLowerInvariant() } | Select-Object -Unique)
    if ($identities.Count -ne 1) { throw 'ASRock : plusieurs installateurs officiels incoherents pour la derniere version ; selection ambigue.' }
    return $resolved[0]
}
