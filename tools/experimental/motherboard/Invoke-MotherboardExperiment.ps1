#requires -Version 5.1
[CmdletBinding()]
param([string]$OutputPath=(Join-Path $PSScriptRoot 'reports/inventory.json'), [switch]$CheckOnline)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'MotherboardExperiment.psm1') -Force
$inventory=Get-MbxInventory
$selection=Resolve-MbxTool -Inventory $inventory
$online=[ordered]@{ Requested=[bool]$CheckOnline; Status='not_checked'; Downloads=@(); Error='' }
if ($CheckOnline -and $selection.Tool) {
    try {
        $tool=@(Get-MbxToolDefinitions | Where-Object { $_.Vendor -eq $selection.Vendor })[0]
        $page=Invoke-MbxHttp -Url $tool.Page -Hosts $tool.Hosts
        $online.Status='official_page_available'
        $online.Downloads=@(Get-MbxDownloadLinks -Html $page.Text -PageUrl $page.Url -Tool $tool)
    } catch { $online.Status='failed'; $online.Error=$_.Exception.Message }
}
$report=[ordered]@{
    SchemaVersion=1; Mode='read_only_experiment'; Inventory=$inventory; Selection=$selection; Online=[pscustomobject]$online
    Updates=[ordered]@{ Status='manual_required'; AvailableDrivers=$null; Reason='Aucune API/CLI de recherche et installation de pilotes officiellement documentee et validee pour ce materiel.' }
    Firmware=[ordered]@{ Current=$inventory.Bios; AvailableVersion=$null; Status='manual_check_required'; AutoFlash=$false }
    Changes=[ordered]@{ InstalledDrivers=0; InstalledApplications=0; RebootInitiated=$false; WindowsUpdateTouched=$false; GoogleConnectionsTouched=$false }
}
$parent=Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath))
[void](New-Item -ItemType Directory -Path $parent -Force)
$report | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
Write-Host ('Carte mere : {0} / {1} / revision {2}' -f $selection.Vendor,$selection.BoardModel,$selection.BoardRevision)
Write-Host ('Statut : {0}. {1}' -f $selection.Status,$selection.Reason)
Write-Host "Rapport : $OutputPath"
