#requires -Version 5.1
[CmdletBinding()]
param([string]$OutputDirectory = (Join-Path $PSScriptRoot 'reports'))
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'MotherboardExperiment.psm1') -Force
[void](New-Item -ItemType Directory -Path $OutputDirectory -Force)
$sources = @(
    @{ Vendor='MSI'; Url='https://www.msi.com/Landing/MSI-Center' },
    @{ Vendor='MSI'; Url='https://www.msi.com/Landing/msi-drivers-utility-installer' },
    @{ Vendor='MSI'; Url='https://www.msi.com/support/technical_details/MB_SW_MSI_Center' },
    @{ Vendor='MSI'; Url='https://download.msi.com/manual/mb/MSICENTER.pdf' },
    @{ Vendor='ASUS'; Url='https://driverhub.asus.com/en' },
    @{ Vendor='ASUS'; Url='https://geo.asus.com/driverhub/' },
    @{ Vendor='GIGABYTE'; Url='https://www.gigabyte.com/Consumer/Software/GIGABYTE-Control-Center/global/' },
    @{ Vendor='GIGABYTE'; Url='https://www.gigabyte.com/Support/Utility/Motherboard' },
    @{ Vendor='ASRock'; Url='https://www.asrock.com/feature/AutoDriverInstaller/' },
    @{ Vendor='ASRock'; Url='https://www.asrock.com/feature/appshop/' },
    @{ Vendor='ASRock'; Url='https://www.asrock.com/' }
)
$report=@()
foreach ($source in $sources) {
    $tool=@(Get-MbxToolDefinitions | Where-Object Vendor -eq $source.Vendor)[0]
    $item=[ordered]@{ Vendor=$source.Vendor; Url=$source.Url; Status='unavailable'; HttpStatus=0; FinalUrl=''; Links=@(); Excerpts=@(); Error='' }
    try {
        if ($source.Url -match '\.pdf$') {
            # PDF bytes must never be processed by the HTML text/regex pipeline.
            $pdf=Join-Path $OutputDirectory 'MSICENTER.pdf'
            if (Test-Path $pdf) { throw 'Fichier de preuve deja present : choisir un nouveau dossier.' }
            $r=Invoke-MbxHttp -Url $source.Url -Hosts $tool.Hosts -OutFile $pdf -MaxBytes 67108864
            $text=& python (Join-Path $PSScriptRoot 'Read-VendorManual.py') $pdf
            if ($LASTEXITCODE -ne 0) { throw 'Extraction PDF impossible.' }
            $item.Excerpts=@(($text | ConvertFrom-Json).excerpts)
        } elseif ($source.Url -eq 'https://geo.asus.com/driverhub/') {
            $r=Invoke-MbxHttp -Url $source.Url -Hosts $tool.Hosts -Head
            if ($r.SuggestedFileName) {
                $item.Links=@($r.Url)
                $item.Excerpts=@("Content-Disposition: $($r.SuggestedFileName); Content-Length: $($r.ExpectedBytes). Metadata only; binary audit separate.")
            } else {
                $r=Invoke-MbxHttp -Url $source.Url -Hosts $tool.Hosts
                $item.Links=@(Get-MbxDownloadLinks -Html $r.Text -PageUrl $r.Url -Tool $tool)
                $item.Excerpts=@('Official shortlink landing page read without executing JavaScript.')
            }
        } else {
            $r=Invoke-MbxHttp -Url $source.Url -Hosts $tool.Hosts
            $html=$r.Text
            Set-Content -LiteralPath (Join-Path $OutputDirectory (('{0}-{1}.html' -f $source.Vendor,$report.Count))) -Value $html -Encoding UTF8
            $item.Links=@([regex]::Matches($html,'(?is)(?:href|src)\s*=\s*["'']([^"'']+)["'']|(?:https?:)?//[^"''<>\s\\]+') | ForEach-Object { if ($_.Groups[1].Success) { $_.Groups[1].Value } else { $_.Value } } | Where-Object { $_ -match '(?i)\.zip|\.exe|\.msi|support|compatib|model|driver|download|\.pdf|\.json|\.js' } | Select-Object -Unique -First 80)
            $plain=[Net.WebUtility]::HtmlDecode(($html -replace '(?is)<(script|style)\b.*?</\1>',' ' -replace '(?s)<[^>]+>',' ' -replace '\s+',' '))
            $rx=New-Object regex('(?i).{0,100}(?:support|compatib|Windows|silent|command.line|motherboard|Norton|McAfee|antivirus|BIOS|reboot|restart|driver).{0,200}',[Text.RegularExpressions.RegexOptions]::None,[TimeSpan]::FromSeconds(2))
            $item.Excerpts=@($rx.Matches($plain) | ForEach-Object { $_.Value } | Select-Object -Unique -First 25)
            if ($source.Vendor -eq 'ASUS') {
                foreach ($link in @($item.Links | Where-Object { $_ -match '/app/.+/(page|layout)-.+\.js$' } | Select-Object -First 3)) {
                    try {
                        $url=(New-Object uri([uri]$r.Url,$link)).AbsoluteUri
                        $bundle=Invoke-MbxHttp -Url $url -Hosts $tool.Hosts
                        $item.Links+=@([regex]::Matches($bundle.Text,'https://[^"''<>\s\\]+') | ForEach-Object { $_.Value } | Where-Object { $_ -match 'asus\.com' } | Select-Object -Unique -First 20)
                        $rx=New-Object regex('(?i).{0,80}(?:download|\.exe|\.zip|supported|compatib|api/|silent|scan|norton|mcafee).{0,180}',[Text.RegularExpressions.RegexOptions]::None,[TimeSpan]::FromSeconds(2))
                        $item.Excerpts+=@($rx.Matches($bundle.Text) | ForEach-Object { $_.Value } | Select-Object -Unique -First 15)
                    } catch { $item.Excerpts+=('Official JavaScript unavailable: '+$_.Exception.Message) }
                }
            }
        }
        $item.HttpStatus=$r.HttpStatus; $item.FinalUrl=$r.Url; $item.Status='available'
    } catch {
        $item.Error=$_.Exception.Message
        if ($item.Error -match 'HTTP (\d{3})') { $item.HttpStatus=[int]$Matches[1] }
    }
    $report+=[pscustomobject]$item
    Write-Host ('{0} {1} HTTP {2}: {3}' -f $source.Vendor,$source.Url,$item.HttpStatus,$item.Status)
}
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'official-sources.json') -Encoding UTF8
Write-MbxEvidence -Kind 'official_sources' -Data $report
