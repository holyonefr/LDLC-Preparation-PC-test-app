#requires -Version 5.1
[CmdletBinding()]
param([switch]$PlanOnly, [string]$ReportPath=(Join-Path $env:TEMP 'VendorUtility-result.json'))
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'VendorUtility.psm1') -Force
$result=Invoke-VendorUtility -PlanOnly:$PlanOnly
$parent=Split-Path -Parent ([IO.Path]::GetFullPath($ReportPath))
[void](New-Item -ItemType Directory -Path $parent -Force)
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
Write-Host ("{0} / {1} : {2}" -f $result.Vendor,$result.Model,$result.Tool)
Write-Host ("Statut : {0}. {1}" -f $result.Status,$result.Reason)
if ($result.InstallerPath) { Write-Host ('Installateur verifie : '+$result.InstallerPath) }
if ($result.InstallerShortcut) { Write-Host ('Raccourci installateur sur le Bureau : '+$result.InstallerShortcut) }
if ($result.OfficialPage) { Write-Host ('Support officiel : '+$result.OfficialPage) }
if ($result.Shortcut) { Write-Host ('Raccourci application : '+$result.Shortcut) }
if ($result.RebootRequired) { Write-Host 'Redemarrage demande par le logiciel, a effectuer manuellement.' }
Write-Host ('Rapport : '+$ReportPath)
if ($result.Status -eq 'failed') { exit 1 }
if ($result.Status -eq 'manual_required') { exit 2 }
