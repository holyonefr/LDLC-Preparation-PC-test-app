# Open each detected vendor's registered uninstaller, visibly and without silent flags.
function Get-LDLCSecurityInteractiveCommand {
    param($Program)
    $raw = [Environment]::ExpandEnvironmentVariables([string]$Program.UninstallString).Trim()
    if ($raw -notmatch '^(?:"(?<File>[^"]+\.exe)"|(?<File>.+?\.exe))(?<Args>(?:\s.*)?)$') {
        throw "Commande de desinstallation interactive absente/invalide pour $($Program.DisplayName)."
    }
    $file = $matches.File; $arguments = $matches.Args.Trim()
    $leaf = [IO.Path]::GetFileName($file)
    if ($leaf -ieq 'msiexec.exe') {
        $file = Join-Path $env:SystemRoot 'System32/msiexec.exe'
        $arguments = [regex]::Replace($arguments, '(?i)(^|\s)/I(?=\s|\{)', '$1/X')
        if ($arguments -notmatch '(?i)(^|\s)/X(?=\s|\{)') { throw 'Commande MSI de desinstallation sans produit /X.' }
        if ($arguments -notmatch '(?i)(^|\s)/norestart\b') { $arguments += ' /norestart' }
    }
    # Remove only standalone silent switches; retain the vendor's original uninstall arguments.
    $arguments = [regex]::Replace($arguments, '(?i)(^|\s)/(?:quiet|silent|verysilent|passive|suppressmsgboxes|s|q[nbrf]?[+!-]?)(?=\s|$)', ' ').Trim()
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Desinstallateur introuvable pour $($Program.DisplayName) : $file" }
    return [pscustomobject]@{ FilePath = $file; Arguments = $arguments }
}

function Start-LDLCSecurityInteractiveUninstaller {
    param($Command)
    $launch = @{ FilePath = $Command.FilePath; WindowStyle = 'Normal'; PassThru = $true; ErrorAction = 'Stop' }
    if ($Command.Arguments) { $launch.ArgumentList = $Command.Arguments }
    return Start-Process @launch
}

function Remove-LDLCSecurityTrialsInteractively {
    param([int]$StartPercent = 1, [int]$EndPercent = 3)
    Stop-IfRequested
    Write-Section 'DESINSTALLATION MCAFEE / NORTON'
    $targets = @(Get-LDLCOemRemovalTargets | Where-Object { $_.Profile.Group -in @('McAfee', 'Norton') })
    $removed = 0
    foreach ($target in $targets) {
        Stop-IfRequested
        $program = $target.Program
        if (-not (Test-LDLCProgramStillInstalled -Program $program)) { $removed++; continue }
        $command = Get-LDLCSecurityInteractiveCommand -Program $program
        Write-ProgressFile $StartPercent "Desinstallation de $($program.DisplayName) : terminer dans sa fenetre."
        Write-Step "Ouverture du desinstallateur de $($program.DisplayName)."
        $process = Start-LDLCSecurityInteractiveUninstaller -Command $command
        if (-not $process) { throw "Le desinstallateur de $($program.DisplayName) n'a pas demarre." }
        try {
            while ($true) {
                Stop-IfRequested
                Clear-LDLCDetectionCaches
                $stillInstalled = Test-LDLCProgramStillInstalled -Program $program
                $process.Refresh()
                if ($process.HasExited) {
                    $code = $process.ExitCode
                    if (-not $stillInstalled -and $code -in @(0, 1605, 1614, 3010, 1641)) { $removed++; break }
                    if ($code -in @(3010, 1641)) { throw "$($program.DisplayName) demande un redemarrage et reste present. Reprendre apres redemarrage." }
                    if ($code -notin @(0, 1605, 1614)) { throw "Desinstallation de $($program.DisplayName) interrompue/refusee (code $code). Preparation arretee." }
                    # A launcher may exit before its visible child. Wait for removal,
                    # not the launcher's lifetime; Quit remains available via Stop-IfRequested.
                    Write-ProgressFile $StartPercent "$($program.DisplayName) encore present : terminer sa desinstallation ou Quitter."
                }
                Start-Sleep -Milliseconds 500
            }
        } finally { $process.Dispose() }
        Write-Info "Desinstallation terminee : $($program.DisplayName)."
    }
    $remaining = @(Get-LDLCOemRemovalTargets | Where-Object {
        $_.Profile.Group -in @('McAfee', 'Norton') -and (Test-LDLCProgramStillInstalled -Program $_.Program)
    })
    if ($remaining.Count) { throw 'McAfee/Norton encore detecte apres desinstallation ; preparation arretee avant les installations.' }
    Write-ProgressFile $EndPercent 'Etape McAfee/Norton terminee.'
    return [pscustomobject]@{ Detected = $targets.Count; Removed = $removed; Pending = 0; Success = $true }
}
