# Historical Chrome taskbar preparation, restored at the user's request.
# Reference: LDLC 32034cc^ / 3aec296, Invoke-LDLCChromeTaskbarPinBeforeWindowsUpdate.
# Write the Append layout and refresh Explorer; no UIA menu or pin-confirmation timeout.
# A prepared layout is not proof that Windows displayed the pin on every device.
function Invoke-LDLCChromeTaskbarPin {
    param(
        [int]$ProgressPercent = 90
    )

    Stop-IfRequested
    Write-Section "EPINGLAGE CHROME BARRE DES TACHES"

    $chromeExe = Get-LDLCChromeExecutablePath
    if (-not $chromeExe) {
        Write-Warn "Chrome introuvable : epinglage barre des taches ignore."
        return $false
    }

    $shellFolder = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Shell'
    $xmlPath = Join-Path $shellFolder 'LayoutModification.xml'

    try {
        New-Item -ItemType Directory -Path $shellFolder -Force | Out-Null

        $xml = @"
<?xml version="1.0" encoding="utf-8"?>
<LayoutModificationTemplate
    xmlns="http://schemas.microsoft.com/Start/2014/LayoutModification"
    xmlns:defaultlayout="http://schemas.microsoft.com/Start/2014/FullDefaultLayout"
    xmlns:start="http://schemas.microsoft.com/Start/2014/StartLayout"
    xmlns:taskbar="http://schemas.microsoft.com/Start/2014/TaskbarLayout"
    Version="1">
  <CustomTaskbarLayoutCollection PinListPlacement="Append">
    <defaultlayout:TaskbarLayout>
      <taskbar:TaskbarPinList>
        <taskbar:DesktopApp DesktopApplicationID="Chrome" />
      </taskbar:TaskbarPinList>
    </defaultlayout:TaskbarLayout>
  </CustomTaskbarLayoutCollection>
</LayoutModificationTemplate>
"@

        [System.IO.File]::WriteAllText($xmlPath, $xml, (New-Object System.Text.UTF8Encoding($false)))
        Write-Ok "Layout taskbar Chrome prepare : $xmlPath"
    }
    catch {
        if (Test-LDLCStopRequestError $_) { throw }
        Write-Warn "Impossible de preparer le layout taskbar Chrome : $($_.Exception.Message)"
        return $false
    }

    Write-ProgressFile $ProgressPercent "Epinglage de Chrome a la barre des taches..."

    try {
        Stop-IfRequested
        Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force -Confirm:$false -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 1000
        Start-Process explorer
        Start-Sleep -Milliseconds 1800
        Stop-IfRequested
        Close-LDLCExplorerFileWindows
        Write-Info "Relance Explorer effectuee sans fenetre Accueil."
    }
    catch {
        if (Test-LDLCStopRequestError $_) { throw }
        Write-Warn "Relance Explorer impossible : $($_.Exception.Message)"
    }

    return $true
}
