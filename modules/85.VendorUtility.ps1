# Beta-only integration. Payloads are filled at build time, not at UI startup.
$script:LDLCVendorUtilityPayloads = @()

function Initialize-LDLCVendorUtilityModule {
    if (-not $script:LDLCVendorUtilityPayloads.Count) { throw 'Modules constructeurs absents de cette compilation beta.' }
    $identity=($script:LDLCVendorUtilityPayloads | ForEach-Object { $_.Sha256 }) -join ''
    $sha=[Security.Cryptography.SHA256]::Create()
    try { $id=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($identity)))).Replace('-','') } finally { $sha.Dispose() }
    $root=Join-Path $script:RuntimeRoot ('VendorUtility/'+$id)
    foreach ($entry in $script:LDLCVendorUtilityPayloads) {
        if ($entry.Path -notmatch '\A(?:motherboard|vendor-utility)/[A-Za-z0-9.-]+\.psm?1\z') { throw 'Chemin du module constructeur embarque invalide.' }
        $path=Join-Path $root $entry.Path
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            [void](New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force)
            $bytes=[Convert]::FromBase64String($entry.Base64)
            $sha=[Security.Cryptography.SHA256]::Create()
            try { $hash=([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','') } finally { $sha.Dispose() }
            if ($hash -cne $entry.Sha256) { throw 'Empreinte du module constructeur embarque incorrecte.' }
            [IO.File]::WriteAllBytes($path,$bytes)
        }
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -cne $entry.Sha256) { throw 'Module constructeur local modifie ; chargement refuse.' }
    }
    return Import-Module (Join-Path $root 'vendor-utility/VendorUtility.psm1') -Force -PassThru -ErrorAction Stop
}

function Invoke-LDLCVendorUtility {
    param([int]$ProgressPercent=60)
    Stop-IfRequested
    Write-ProgressFile $ProgressPercent 'Logiciel de carte mere : detection et preparation du raccourci...'
    try {
        $module=Initialize-LDLCVendorUtilityModule
        $result=& $module { Invoke-VendorUtility }
        Stop-IfRequested
        $report=Join-Path $script:RuntimeRoot 'LDLC_VENDOR_UTILITY_RESULT.json'
        $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $report -Encoding UTF8
        if ($result.Status -eq 'already_installed' -and $result.ApplicationVerified -and $result.Shortcut) {
            Write-Ok ($result.Tool+' : application presente, raccourci Bureau verifie.')
        } elseif ($result.Status -eq 'manual_required' -and $result.InstallerShortcut) {
            Write-Ok ($result.Tool+' : installateur verifie, raccourci sur le Bureau. Installation manuelle par le technicien.')
        } elseif ($result.Status -eq 'manual_required' -and $result.PSObject.Properties['SupportShortcut'] -and $result.SupportShortcut) {
            Write-Warn ($result.Tool+' : telechargement manuel requis. '+$result.Reason)
        } elseif ($result.Status -eq 'manual_required' -and -not $result.Tool) {
            Write-Step ('Logiciel de carte mere non applicable : '+$result.Reason)
        } else {
            Write-Warn ('Logiciel de carte mere non prepare : '+$result.Reason)
        }
        return $result
    } catch {
        if (Test-LDLCStopRequestError $_) { throw }
        Write-Warn ('Logiciel de carte mere : '+$_.Exception.Message)
        return [pscustomobject]@{Status='failed';Reason=$_.Exception.Message;Installed=$false;InstallerShortcut=''}
    }
}

