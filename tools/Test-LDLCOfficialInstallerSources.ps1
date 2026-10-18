param(
    [switch]$DownloadSmallPackages
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'modules\00.Core.ps1')
. (Join-Path $root 'modules\30.Applications.ps1')
. (Join-Path $root 'modules\60.Gpu.ps1')

$script:StopFile = Join-Path ([System.IO.Path]::GetTempPath()) ('LDLC-NO-STOP-' + [guid]::NewGuid().ToString('N'))
$definitions = New-Object System.Collections.Generic.List[object]
foreach ($app in $Apps) {
    [void]$definitions.Add([pscustomobject]@{ Label = $app.Name; Installer = $app.DirectInstaller })
}
[void]$definitions.Add([pscustomobject]@{ Label = 'NVIDIA App'; Installer = (Get-LDLCNvidiaAppInstallerDefinition) })
[void]$definitions.Add([pscustomobject]@{ Label = 'AMD Adrenalin'; Installer = (Get-LDLCAmdAdrenalinInstallerDefinition) })
[void]$definitions.Add([pscustomobject]@{
    Label = 'NVIDIA Game Ready RTX 4060'
    Installer = (Get-LDLCNvidiaDriverInstallerDefinition `
        -GpuName 'NVIDIA GeForce RTX 4060' `
        -PnpDeviceId 'PCI\VEN_10DE&DEV_2882')
})
[void]$definitions.Add([pscustomobject]@{
    Label = 'NVIDIA premiere session DEV_2882'
    Installer = (Get-LDLCNvidiaDriverInstallerDefinition `
        -GpuName 'Microsoft Basic Display Adapter' `
        -PnpDeviceId 'PCI\VEN_10DE&DEV_2882')
})

$resolved = @{}
foreach ($definition in $definitions) {
    $sources = @(Get-LDLCOfficialInstallerSources -Installer $definition.Installer)
    if ($sources.Count -eq 0) {
        throw "Aucune source officielle resolue pour $($definition.Label)."
    }

    $source = $sources[0]
    if ($definition.Label -eq 'AMD Adrenalin' -and $source.Url -match '(?i)minimalsetup|_web\.exe') {
        throw 'AMD Adrenalin doit privilegier le package WHQL complet plutot que le bootstrap web.'
    }

    $response = Invoke-WebRequest `
        -Uri $source.Url `
        -Method Head `
        -UseBasicParsing `
        -MaximumRedirection 5 `
        -TimeoutSec 90

    if ([int]$response.StatusCode -notin @(200, 206)) {
        throw "Source $($definition.Label) indisponible : HTTP $($response.StatusCode)."
    }

    $resolved[$definition.Label] = $source
    Write-Host ("OK source {0} -> {1}" -f $definition.Label, $source.Url)
}

if ($DownloadSmallPackages) {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('LDLC-SourceTest-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    try {
        foreach ($label in @('Adobe Acrobat Reader', '7-Zip')) {
            $definition = $definitions | Where-Object Label -eq $label | Select-Object -First 1
            $source = $resolved[$label]
            $path = Join-Path $tempRoot $source.FileName
            Invoke-WebRequest -Uri $source.Url -OutFile $path -UseBasicParsing -TimeoutSec 180
            if (-not (Test-LDLCInstallerFile -Path $path -Installer $definition.Installer -FreshDownload)) {
                throw "Package telecharge non valide pour $label."
            }
            Write-Host "OK package/signature $label"
        }
    }
    finally {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host 'OK official installer sources'
