#requires -Version 5.1
# Read-only source diagnostics. No vendor executable is downloaded or launched.
[CmdletBinding()]
param([string]$OutputDirectory='artifacts/vendor-utility/gigabyte-source')
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot '../motherboard/MotherboardExperiment.psm1') -Force
$output=New-Item -ItemType Directory -Path $OutputDirectory -Force
$sources=@(
    'https://www.gigabyte.com/Ajax/SupportFunction/GetUtilityAjax?ClassGroup=2&Page=1&KeyWord=GIGABYTE%20Control%20Center',
    'https://www.gigabyte.com/Support/Utility?kw=GIGABYTE+Control+Center&p=1',
    'https://www.gigabyte.com/Consumer/Software/GIGABYTE-Control-Center/global/'
)
$curlPaths=@(
    @{Name='windows_curl';Path=(Join-Path $env:SystemRoot 'System32/curl.exe')},
    @{Name='git_curl';Path=(Join-Path $env:ProgramFiles 'Git/mingw64/bin/curl.exe')}
)
$results=@()
foreach ($url in $sources) {
    foreach ($client in $curlPaths) {
        if (-not (Test-Path -LiteralPath $client.Path -PathType Leaf)) {
            $results+=@{Url=$url;Client=$client.Name;Available=$false}; continue
        }
        $bodyFile=Join-Path $output.FullName ([guid]::NewGuid().ToString('N')+'.txt')
        $errorFile=$bodyFile+'.stderr'
        try {
            # No redirects: a different destination must be reviewed separately.
            $code=& $client.Path --silent --show-error --proto '=https' --connect-timeout 10 --max-time 30 --max-filesize 2097152 --output $bodyFile --write-out '%{http_code}' $url 2> $errorFile
            $exit=$LASTEXITCODE
            $body=if (Test-Path -LiteralPath $bodyFile) { [IO.File]::ReadAllText($bodyFile) } else { '' }
            $links=@([regex]::Matches($body,'GCC_([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)\.zip') | ForEach-Object {$_.Groups[1].Value} | Select-Object -Unique)
            $results+=@{Url=$url;Client=$client.Name;Available=$true;ExitCode=$exit;HttpStatus=([string]$code).Trim();Bytes=([Text.Encoding]::UTF8.GetByteCount($body));BundleVersions=$links;HasAccessDenied=($body -match '(?i)access denied|request rejected')}
        } catch {
            $results+=@{Url=$url;Client=$client.Name;Available=$true;Error=$_.Exception.Message}
        } finally {
            Remove-Item -LiteralPath $bodyFile,$errorFile -Force -ErrorAction SilentlyContinue
        }
    }
    try {
        $response=Invoke-MbxHttp -Url $url -Hosts @('www.gigabyte.com') -TimeoutSeconds 30 -MaxBytes 2097152
        $links=@([regex]::Matches($response.Text,'GCC_([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)\.zip') | ForEach-Object {$_.Groups[1].Value} | Select-Object -Unique)
        $results+=@{Url=$url;Client='powershell_http';HttpStatus=200;BundleVersions=$links}
    } catch { $results+=@{Url=$url;Client='powershell_http';Error=$_.Exception.Message} }
}
$report=[ordered]@{Kind='gigabyte_live_source_probe';RecordedAtUtc=[DateTime]::UtcNow.ToString('o');Results=$results;VendorInstallerExecuted=$false;InstallerDownloaded=$false}
$report | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $output.FullName 'source.json') -Encoding UTF8
Write-MbxEvidence -Kind 'gigabyte_live_source_probe' -Data $report
$results | ForEach-Object { Write-Host ($_.Client+' '+$_.HttpStatus+' '+$_.Error+' '+$_.Url) }
