#requires -Version 5.1
[CmdletBinding()]
param([string]$OutputDirectory=(Join-Path $PSScriptRoot 'reports/gigabyte-discovery-tests'))
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2
Import-Module (Join-Path $PSScriptRoot 'VendorUtility.psm1') -Force
$module=Get-Module VendorUtility
[void](New-Item -ItemType Directory -Path $OutputDirectory -Force)
$manifestUrl='https://www.gigabyte.com/Ajax/SupportFunction/GetUtilityAjax?ClassGroup=2&Page=1&KeyWord=GIGABYTE%20Control%20Center'
$script:assertions=0
$cases=New-Object 'System.Collections.Generic.List[object]'

function Assert($Value,[string]$Message) {
    $script:assertions++
    if (-not $Value) { throw $Message }
}
function Case([string]$Name,[scriptblock]$Body) {
    try { & $Body; $cases.Add([pscustomobject]@{Name=$Name;Result='passed';Error=''}) }
    catch { $cases.Add([pscustomobject]@{Name=$Name;Result='failed';Error=$_.Exception.Message}); Write-Warning ($Name+': '+$_.Exception.Message) }
}
function Set-Page([string]$Html,[string]$Failure='') {
    & $module {
        param($html,$failure)
        $script:DiscoveryFixture=[pscustomobject]@{
            Html=$html; Failure=$failure; BrowserOnly=$false; Requests=(New-Object 'System.Collections.Generic.List[object]')
        }
    } $Html $Failure
}
function Discover { & $module { Resolve-VutGigabyteDownload } }
function Reject-Page([string]$Html,[string]$Pattern='',[string]$Failure='') {
    Set-Page $Html $Failure
    $caught=$null
    try { $null=Discover } catch { $caught=$_.Exception.Message }
    Assert ($null -ne $caught) 'Page invalide acceptee ou choix ancien presente comme fiable.'
    if ($Pattern) { Assert ($caught -match $Pattern) ('Cause imprecise : '+$caught) }
}
function Confirm-Selection([string]$Html,[string]$ExpectedVersion,[string]$ExpectedUrl='') {
    Set-Page $Html
    $r=Discover
    Assert ($r.BundleVersion -ceq $ExpectedVersion) ('Mauvaise version du bundle : '+$r.BundleVersion)
    Assert ($r.Method -ceq 'official_gigabyte_utility_html') 'Methode de detection non identifiee.'
    Assert ($r.ManifestUrl -ceq $manifestUrl) 'Source officielle non restituee.'
    Assert ([uri]$r.DownloadUrl -and ([uri]$r.DownloadUrl).Host -ieq 'download.gigabyte.com') 'Hote telechargement incorrect.'
    if ($ExpectedUrl) { Assert ($r.DownloadUrl -ceq $ExpectedUrl) ('Mauvais lien : '+$r.DownloadUrl) }
    $requests=@(& $module { $script:DiscoveryFixture.Requests.ToArray() })
    Assert ($requests.Count -eq 1) 'La detection ne consulte pas exactement une source officielle.'
    Assert ($requests[0].Url -ceq $manifestUrl -and $requests[0].Hosts.Count -eq 1 -and $requests[0].Hosts[0] -ceq 'www.gigabyte.com') 'Requete hors du contrat officiel ou hote trop large.'
}

# Only the HTTP seam is replaced: the resolver, URI checks and version sorting
# are the real module functions. No download, process or installer is executed.
& $module {
    function script:Invoke-MbxHttp {
        param([string]$Url,[string[]]$Hosts,[int]$TimeoutSeconds,[long]$MaxBytes,[string]$UserAgent)
        $script:DiscoveryFixture.Requests.Add([pscustomobject]@{Url=$Url;Hosts=@($Hosts)})
        if ($script:DiscoveryFixture.Failure -and (-not $script:DiscoveryFixture.BrowserOnly -or $UserAgent -notlike 'Mozilla/*')) { throw $script:DiscoveryFixture.Failure }
        return [pscustomobject]@{Text=$script:DiscoveryFixture.Html;Url=$Url}
    }
}

try {
    Case 'Numeric comparison selects 1.10 over 1.9' {
        Confirm-Selection '<a href="https://download.gigabyte.com/FileList/Utility/GCC_1.9.99.99.zip">old</a><a href="https://download.gigabyte.com/FileList/Utility/GCC_1.10.0.0.zip">new</a>' '1.10.0.0' 'https://download.gigabyte.com/FileList/Utility/GCC_1.10.0.0.zip'
    }
    Case 'Official catalogue can be retried with browser content negotiation after HTTP 403' {
        Set-Page '<a href="https://download.gigabyte.com/FileList/Utility/GCC_1.10.0.0.zip">current</a>' 'Fixture HTTP 403'
        & $module { $script:DiscoveryFixture.BrowserOnly=$true }
        $r=Discover
        Assert ($r.BundleVersion -eq '1.10.0.0' -and $r.SourceClient -eq 'browser_user_agent') 'Contenu officiel non resolu avec le second client.'
        Assert ((@(& $module { $script:DiscoveryFixture.Requests.ToArray() })).Count -eq 2) 'Nombre de requetes incorrect.'
    }
    Case 'HTTP 403 on every official source stays an explicit error without old-file fallback' {
        Reject-Page '' 'inaccessible.*HTTP 403' 'Fixture HTTP 403'
    }
    Case 'Date versions retain all four components and leading zeroes' {
        Confirm-Selection '<a href="https://download.gigabyte.com/FileList/Utility/GCC_26.08.31.99.zip">old</a><a href="https://download.gigabyte.com/FileList/Utility/GCC_26.09.10.01.zip">new</a>' '26.09.10.01'
    }
    Case 'Newest candidate is independent of display order and old versions' {
        Confirm-Selection '<a href="https://download.gigabyte.com/FileList/Utility/GCC_3.0.0.0.zip">new</a><a href="https://download.gigabyte.com/FileList/Utility/GCC_1.3.0.0.zip">old</a><a href="https://download.gigabyte.com/FileList/Utility/GCC_1.2.0.0.zip">older</a>' '3.0.0.0'
    }
    Case 'Single-quoted href and protocol-relative official link' {
        Confirm-Selection "<a href='//download.gigabyte.com/FileList/Utility/GCC_1.10.0.0.zip'>Download</a>" '1.10.0.0' 'https://download.gigabyte.com/FileList/Utility/GCC_1.10.0.0.zip'
    }
    Case 'HTML entities in official download query are decoded' {
        Confirm-Selection '<a href="https://download.gigabyte.com/FileList/Utility/GCC_1.10.0.0.zip?v=example&amp;region=fr">Download</a>' '1.10.0.0' 'https://download.gigabyte.com/FileList/Utility/GCC_1.10.0.0.zip?v=example&region=fr'
    }
    Case 'Duplicate identical URL is harmless' {
        Confirm-Selection '<a href="https://download.gigabyte.com/FileList/Utility/GCC_1.10.0.0.zip">one</a><a href="https://download.gigabyte.com/FileList/Utility/GCC_1.10.0.0.zip">two</a>' '1.10.0.0'
    }
    Case 'Distinct links advertising the same newest bundle are ambiguous' {
        Reject-Page '<a href="https://download.gigabyte.com/FileList/Utility/GCC_1.10.0.0.zip?v=one">one</a><a href="https://download.gigabyte.com/FileList/Utility/GCC_1.10.0.0.zip?v=two">two</a>' 'ambigu'
    }
    Case 'Ambiguous older bundle is not silently accepted as trustworthy metadata' {
        Reject-Page '<a href="https://download.gigabyte.com/FileList/Utility/GCC_1.9.0.0.zip?v=one">one</a><a href="https://download.gigabyte.com/FileList/Utility/GCC_1.9.0.0.zip?v=two">two</a><a href="https://download.gigabyte.com/FileList/Utility/GCC_1.10.0.0.zip">new</a>' 'ambigu'
    }
    Case 'HTTPS default port and case-insensitive official hostname' {
        Confirm-Selection '<a href="https://DOWNLOAD.GIGABYTE.COM:443/FileList/Utility/GCC_1.10.0.0.zip">Download</a>' '1.10.0.0'
    }
    Case 'Invalid external higher release cannot override valid official release' {
        Confirm-Selection '<a href="https://download.gigabyte.com/FileList/Utility/GCC_1.10.0.0.zip">official</a><a href="https://example.invalid/GCC_99.0.0.0.zip">external</a><a href="http://download.gigabyte.com/FileList/Utility/GCC_100.0.0.0.zip">HTTP</a>' '1.10.0.0'
    }
    foreach ($test in @(
        @{Name='HTTP link rejected';Href='http://download.gigabyte.com/FileList/Utility/GCC_1.10.0.0.zip'},
        @{Name='Third-party hostname rejected';Href='https://example.invalid/GCC_1.10.0.0.zip'},
        @{Name='Lookalike hostname rejected';Href='https://download.gigabyte.com.example.invalid/GCC_1.10.0.0.zip'},
        @{Name='Hostname suffix attack rejected';Href='https://evildownload.gigabyte.com/GCC_1.10.0.0.zip'},
        @{Name='User information in URL rejected';Href='https://attacker@download.gigabyte.com/FileList/Utility/GCC_1.10.0.0.zip'},
        @{Name='Nonstandard HTTPS port rejected';Href='https://download.gigabyte.com:8443/FileList/Utility/GCC_1.10.0.0.zip'},
        @{Name='Root-relative www path is not a verified download host';Href='/FileList/Utility/GCC_1.10.0.0.zip'},
        @{Name='Relative www path is not a verified download host';Href='GCC_1.10.0.0.zip'},
        @{Name='JavaScript URL rejected';Href='javascript:alert(1)'},
        @{Name='Executable masquerading as ZIP rejected';Href='https://download.gigabyte.com/FileList/Utility/GCC_1.10.0.0.zip.exe'},
        @{Name='Three-component filename rejected';Href='https://download.gigabyte.com/FileList/Utility/GCC_1.10.0.zip'},
        @{Name='Five-component filename rejected';Href='https://download.gigabyte.com/FileList/Utility/GCC_1.10.0.0.1.zip'},
        @{Name='Filename with arbitrary prefix rejected';Href='https://download.gigabyte.com/FileList/Utility/Old_GCC_1.10.0.0.zip'},
        @{Name='Filename with arbitrary suffix rejected';Href='https://download.gigabyte.com/FileList/Utility/GCC_1.10.0.0_backup.zip'},
        @{Name='Another manufacturer utility rejected';Href='https://download.gigabyte.com/FileList/Utility/APP_Center_1.10.0.0.zip'},
        @{Name='Filename supplied only by query string rejected';Href='https://download.gigabyte.com/Download?file=GCC_1.10.0.0.zip'},
        @{Name='Version overflow rejected';Href='https://download.gigabyte.com/FileList/Utility/GCC_99999999999999999.0.0.0.zip'}
    )) {
        Case $test.Name { Reject-Page ('<a href="'+$test.Href+'">Download</a>') }
    }
    Case 'Version text without a download anchor is not an installer' {
        Reject-Page '<html><body><span>Latest GCC_99.0.0.0.zip</span><script>var text="GCC_100.0.0.0.zip";</script></body></html>'
    }
    Case 'Bot challenge produces an explicit failure without stale fallback' {
        Reject-Page '<html><title>Just a moment...</title><body>Checking your browser before accessing GIGABYTE</body></html>'
    }
    Case 'Empty source fails explicitly' { Reject-Page '' }
    Case 'HTTP 503 is preserved rather than returning a cached older release' {
        Reject-Page '' '503' 'Fixture HTTP 503 Service Unavailable'
    }
    Case 'Page one with all announced results remains usable' {
        Confirm-Selection '<input type="hidden" id="now_page" value="1" /><a href="https://download.gigabyte.com/FileList/Utility/GCC_1.9.0.0.zip">old</a><a href="https://download.gigabyte.com/FileList/Utility/GCC_1.10.0.0.zip">new</a><div class="totalItem"><span class="paging-result"><span class="items">2</span> items</span></div>' '1.10.0.0'
    }
    Case 'Incomplete pagination never claims latest release' {
        Reject-Page '<input type="hidden" id="now_page" value="1" /><a href="https://download.gigabyte.com/FileList/Utility/GCC_1.10.0.0.zip">one</a><div class="totalItem"><span class="paging-result"><span class="items">99</span> items</span></div>'
    }
    Case 'Unexpected page two never claims latest release' {
        Reject-Page '<input type="hidden" id="now_page" value="2" /><a href="https://download.gigabyte.com/FileList/Utility/GCC_1.10.0.0.zip">one</a><div class="totalItem"><span class="paging-result"><span class="items">1</span> items</span></div>'
    }
    foreach ($badCount in @('-1','0','invalid')) {
        Case ('Inconsistent catalogue item count rejected: '+$badCount) {
            Reject-Page ('<a href="https://download.gigabyte.com/FileList/Utility/GCC_1.10.0.0.zip">one</a><span class="items">'+$badCount+'</span>')
        }
    }
} finally {
    Remove-Module VendorUtility -ErrorAction SilentlyContinue
}

$report=[ordered]@{
    Kind='gigabyte_discovery_tests'; Mode='simulated_html'; ActualNetworkRequests=0
    ActualVendorInstallations=0; Assertions=$script:assertions; Cases=@($cases.ToArray())
    Failures=@($cases.ToArray() | Where-Object Result -eq 'failed').Count
}
$report | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $OutputDirectory 'gigabyte-discovery-tests.json') -Encoding UTF8
Import-Module (Join-Path $PSScriptRoot '../motherboard/MotherboardExperiment.psm1') -Force
Write-MbxEvidence -Kind 'gigabyte_discovery_tests' -Data $report
if ($report.Failures) { throw "$($report.Failures) scenario(s) de detection GIGABYTE en echec." }
Write-Host "$($cases.Count) scenarios / $script:assertions assertions reussis ; fixtures HTML uniquement, aucun installateur execute."
