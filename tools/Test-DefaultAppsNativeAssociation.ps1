#requires -Version 5.1
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { Write-Host 'SKIP native association APIs: requires Windows'; return }
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'modules/70.DefaultApps.ps1')
$id = [guid]::NewGuid().ToString('N')
$extension = '.ldlcfixture' + $id
$progId = 'LDLC.Association.Fixture.' + $id
$classRoot = 'HKCU:\Software\Classes\'
$adobeExtension='.ldlcadobefixture'+$id
$adobeProgId='LDLC.Adobe.Fixture.'+$id
$registrationName='LDLC test Adobe Acrobat '+$id
$registrationRoot='HKCU:\Software\RegisteredApplications'
$capabilityPath='Software\LDLCDefaultAppsTest\'+$id+'\Capabilities'
$pdfBefore=(Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.pdf\UserChoice' -ErrorAction SilentlyContinue).ProgId
$directory = Join-Path ([IO.Path]::GetTempPath()) ('Association-API-' + $id)
try {
    [void](New-Item -ItemType Directory -Path $directory)
    $executable = Join-Path $directory 'chrome.exe'
    [IO.File]::WriteAllText($executable, 'native association test fixture, never executed')
    [void](New-Item -Path ($classRoot + $extension))
    Set-Item -LiteralPath ($classRoot + $extension) -Value $progId
    [void](New-Item -Path ($classRoot + $progId + '\shell\open\command') -Force)
    Set-Item -LiteralPath ($classRoot + $progId + '\shell\open\command') -Value ('"' + $executable + '" "%1"')
    Ensure-LDLCDefaultAppsNativeInterop
    $reportedId = [LDLCDefaultAppsNative]::CurrentDefault($extension)
    if ($reportedId -ne $progId) { throw 'Native Windows effective ProgID did not match the isolated test extension.' }
    $resolved = [LDLCDefaultAppsNative]::ExecutableForProgId($reportedId)
    if (-not [string]::Equals($resolved, $executable, [StringComparison]::OrdinalIgnoreCase)) { throw 'Native fixed-ProgID executable resolution failed.' }
    $effective = Get-LDLCEffectiveAssociation -Association $extension
    if ($effective.Error -or $effective.ProgId -ne $progId -or $effective.Executable -ne $executable) { throw 'Native effective association wrapper failed.' }
    $reader=Join-Path $directory 'AcroRd32.exe'
    [IO.File]::WriteAllText($reader,'Adobe registration test fixture, not an installed or executed Adobe Reader')
    [void](New-Item -Path ($classRoot+$adobeExtension) -Force)
    Set-Item -LiteralPath ($classRoot+$adobeExtension) -Value $adobeProgId
    [void](New-Item -Path ($classRoot+$adobeProgId+'\shell\open\command') -Force)
    Set-Item -LiteralPath ($classRoot+$adobeProgId+'\shell\open\command') -Value ('"'+$reader+'" "%1"')
    [void](New-Item -Path $registrationRoot -Force)
    New-ItemProperty -LiteralPath $registrationRoot -Name $registrationName -Value $capabilityPath -PropertyType String -Force|Out-Null
    [void](New-Item -Path ('HKCU:\'+$capabilityPath+'\FileAssociations') -Force)
    New-ItemProperty -LiteralPath ('HKCU:\'+$capabilityPath+'\FileAssociations') -Name '.pdf' -Value $adobeProgId -PropertyType String -Force|Out-Null
    $adobe=Get-LDLCEffectiveAssociation -Association $adobeExtension
    if($adobeProgId -notin @(Get-LDLCRegisteredPdfProgIds)){throw 'Read-only Adobe capabilities discovery failed in the actual Windows registry.'}
    if($adobe.Error -or -not (Test-LDLCEffectiveAssociationTarget $adobe Adobe)){throw 'Actual native association with a registered alternate Adobe ProgID was rejected.'}
    $pdfAfter=(Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.pdf\UserChoice' -ErrorAction SilentlyContinue).ProgId
    if($pdfBefore -cne $pdfAfter){throw 'The real PDF user default was changed by an isolated test.'}
    Write-Host ('::notice title=Native association API::' + (@{ Status = 'passed'; Assertions = 6; Mode = 'real Windows association APIs and registry; isolated extensions; Adobe registration simulated'; BrowserDefaultsChanged = $false; PdfDefaultsChanged=$false; ActualAdobeReaderInstalled=$false; FixtureExecuted = $false } | ConvertTo-Json -Compress))
} catch {
    $message = $_.Exception.Message.Replace('%', '%25').Replace("`r", '%0D').Replace("`n", '%0A')
    Write-Host ('::error title=Native association API::' + $message)
    throw
} finally {
    Remove-ItemProperty -LiteralPath $registrationRoot -Name $registrationName -Force -ErrorAction SilentlyContinue
    foreach ($key in @(($classRoot + $extension), ($classRoot + $progId),($classRoot+$adobeExtension),($classRoot+$adobeProgId),('HKCU:\Software\LDLCDefaultAppsTest\'+$id))) {
        if (Test-Path -LiteralPath $key) { Remove-Item -LiteralPath $key -Recurse -Force }
    }
    if (Test-Path -LiteralPath $directory) { Remove-Item -LiteralPath $directory -Recurse -Force }
}
