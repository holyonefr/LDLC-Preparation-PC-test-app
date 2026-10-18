# region Module: 10.InitialSetup.ps1
# Initial workstation preparation steps.

function Invoke-LDLCInitialSetup {
param(
    [int]$InternetProgressPercent = 0,
    [int]$PowerProgressPercent = 1,
    [int]$TimeProgressPercent = 10
)

Wait-LDLCInternetConnection -ProgressPercent $InternetProgressPercent | Out-Null

Write-Section "ETAPES INITIALES"

Stop-IfRequested
Write-ProgressFile $PowerProgressPercent "Désactivation de la veille..."
Write-Step "Desactivation de la veille secteur et batterie..."
Start-Sleep -Milliseconds 250

try {
    $hasBattery = Test-LDLCBatteryPresent

    $script:OriginalMonitorTimeoutAC = TryGet-LDLCPowerSettingIndex -SubGroupAlias SUB_VIDEO -SettingAlias VIDEOIDLE -PowerSource AC
    $script:OriginalStandbyTimeoutAC = TryGet-LDLCPowerSettingIndex -SubGroupAlias SUB_SLEEP -SettingAlias STANDBYIDLE -PowerSource AC

    if ($hasBattery) {
        $script:OriginalMonitorTimeoutDC = TryGet-LDLCPowerSettingIndex -SubGroupAlias SUB_VIDEO -SettingAlias VIDEOIDLE -PowerSource DC
        $script:OriginalStandbyTimeoutDC = TryGet-LDLCPowerSettingIndex -SubGroupAlias SUB_SLEEP -SettingAlias STANDBYIDLE -PowerSource DC
    }
    else {
        $script:OriginalMonitorTimeoutDC = $null
        $script:OriginalStandbyTimeoutDC = $null
    }

    $script:PowerSettingsCaptured = $true
    $script:PowerSettingsRestored = $false

    $disableResults = @()
    $disableResults += Invoke-LDLCPowerCfgChange -SettingName "monitor-timeout-ac" -Value 0 -Label "ecran AC"
    $disableResults += Invoke-LDLCPowerCfgChange -SettingName "standby-timeout-ac" -Value 0 -Label "veille AC"

    if ($hasBattery) {
        $disableResults += Invoke-LDLCPowerCfgChange -SettingName "monitor-timeout-dc" -Value 0 -Label "ecran DC"
        $disableResults += Invoke-LDLCPowerCfgChange -SettingName "standby-timeout-dc" -Value 0 -Label "veille DC"
    }
    else {
        Write-Step "Aucune batterie detectee : delais DC ignores."
    }

    if ($disableResults -contains $false) {
        Write-Warn "Desactivation de la veille appliquee partiellement."
    }
    else {
        Write-Ok "Veille desactivee."
    }
}
catch {
    Write-Err "Erreur lors de la desactivation de la veille : $($_.Exception.Message)"
}

Stop-IfRequested
Write-ProgressFile $TimeProgressPercent "Synchronisation date et heure..."
Write-Step "Configuration de la date et de l'heure..."

try {
    Set-Service w32time -StartupType Automatic
    Start-Service w32time -ErrorAction SilentlyContinue

    reg add "HKLM\SYSTEM\CurrentControlSet\Services\tzautoupdate" /v Start /t REG_DWORD /d 3 /f | Out-Null
    tzutil /s "Romance Standard Time"

    w32tm /config /syncfromflags:manual /manualpeerlist:"time.windows.com,0x9" /update | Out-Null
    Restart-Service w32time
    w32tm /resync /force | Out-Null

    Write-Ok "Date et heure configurees et synchronisees."
}
catch {
    Write-Err "Erreur lors de la configuration date/heure : $($_.Exception.Message)"
}}

# endregion Module: 10.InitialSetup.ps1

