# region Module: 20.WindowsLayout.ps1
# Windows layout customization.

function Set-LDLCWindowsLayout {
    param(
        [int]$ProgressPercent = 15
    )

    Stop-IfRequested
    Write-Section "PERSONNALISATION WINDOWS"
    Write-ProgressFile $ProgressPercent "Personnalisation du bureau..."

    try {
        $ws = New-Object -ComObject WScript.Shell
        $shell = New-Object -ComObject Shell.Application
    }
    catch {
        Write-Warn "Impossible d'initialiser les objets COM : $($_.Exception.Message)"
        return
    }

    function Test-LDLCTaskbarItemMatch {
        param(
            [Parameter(Mandatory = $true)]$Item,
            [string[]]$ExactNames = @(),
            [string[]]$NamePatterns = @(),
            [string[]]$PathPatterns = @()
        )

        $candidateName = ""
        $candidatePath = ""

        try { $candidateName = [string]$Item.Name } catch {}
        try { $candidatePath = [string]$Item.Path } catch {}

        foreach ($exactName in $ExactNames) {
            if ($candidateName -ieq $exactName) {
                return $true
            }
        }

        foreach ($pattern in $NamePatterns) {
            if ($candidateName -like $pattern) {
                return $true
            }
        }

        foreach ($pattern in $PathPatterns) {
            if ($candidatePath -like $pattern) {
                return $true
            }
        }

        return $false
    }

    function Get-LDLCTaskbarItem {
        param(
            [string[]]$ExactNames = @(),
            [string[]]$NamePatterns = @(),
            [string[]]$PathPatterns = @()
        )

        # AppsFolder contains installed applications, including those no longer
        # pinned. Check persisted pins first, then the actual Unpin shell verb.
        $pinFolder = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'
        if (Test-Path -LiteralPath $pinFolder -PathType Container) {
            $pinNamespace = $shell.Namespace($pinFolder)
            if (-not $pinNamespace) { throw 'Lecture des raccourcis epingles impossible.' }
            foreach ($candidate in @($pinNamespace.Items())) {
                if (Test-LDLCTaskbarItemMatch -Item $candidate -ExactNames $ExactNames -NamePatterns $NamePatterns -PathPatterns $PathPatterns) {
                    return $candidate
                }
            }
        }

        $appsNamespace = $shell.Namespace("shell:::{4234d49b-0245-4df3-b780-3893943456e1}")
        if (-not $appsNamespace) { throw 'Lecture des applications Windows impossible.' }
        $items = @($appsNamespace.Items())

        foreach ($candidate in $items) {
            if (Test-LDLCTaskbarItemMatch -Item $candidate -ExactNames $ExactNames -NamePatterns $NamePatterns -PathPatterns $PathPatterns) {
                foreach ($verb in @($candidate.Verbs())) {
                    $verbName = ([string]$verb.Name).Replace('&', '').Normalize([Text.NormalizationForm]::FormD)
                    $verbName = ($verbName -replace '\p{Mn}', '').Trim()
                    if ($verbName -match '^(taskbarunpin|unpin from taskbar|detacher de la barre des taches|desepingler de la barre des taches)$') {
                        return $candidate
                    }
                }
            }
        }

        return $null
    }

    function Wait-LDLCTaskbarItemAbsent {
        param(
            [string[]]$ExactNames = @(),
            [string[]]$NamePatterns = @(),
            [string[]]$PathPatterns = @(),
            [int]$TimeoutSeconds = 4
        )

        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

        do {
            Stop-IfRequested

            if (-not (Get-LDLCTaskbarItem -ExactNames $ExactNames -NamePatterns $NamePatterns -PathPatterns $PathPatterns)) {
                return $true
            }

            Start-Sleep -Milliseconds 100
        }
        while ((Get-Date) -lt $deadline)

        return $false
    }

    function Remove-LDLCTaskbarPins {
        param(
            [string[]]$ExactNames = @(),
            [string[]]$NamePatterns = @(),
            [string[]]$PathPatterns = @(),
            [Parameter(Mandatory = $true)][string]$ProgressMessage,
            [Parameter(Mandatory = $true)][int]$ProgressPercent,
            [Parameter(Mandatory = $true)][string]$Label
        )

        Stop-IfRequested

        $itemToRemove = Get-LDLCTaskbarItem -ExactNames $ExactNames -NamePatterns $NamePatterns -PathPatterns $PathPatterns

        if (-not $itemToRemove) {
            Write-Step "Aucune epingle $Label detectee dans la barre des taches."
            return $false
        }

        Write-ProgressFile $ProgressPercent $ProgressMessage
        Start-Sleep -Milliseconds 100

        try {
            $removedLabel = [string]$itemToRemove.Name
            $itemToRemove.InvokeVerb("taskbarunpin")
            Start-Sleep -Milliseconds 200
            Refresh-Desktop

            if (Wait-LDLCTaskbarItemAbsent -ExactNames $ExactNames -NamePatterns $NamePatterns -PathPatterns $PathPatterns -TimeoutSeconds 4) {
                Write-Ok "Element retire de la barre des taches : $removedLabel"
                return $true
            }

            if ($Label -notin @("Copilot", "Microsoft Store")) {
                Write-Warn "$Label semble toujours present apres la tentative de retrait."
            }
            return $false
        }
        catch {
            if (Test-LDLCStopRequestError $_) { throw }
            Write-Warn "Impossible de retirer de la barre des taches : $([string]$itemToRemove.Name)"
            return $false
        }
    }

    Write-Step "Suppression raccourcis Edge..."

    $paths = @(
        [Environment]::GetFolderPath("Desktop"),
        [Environment]::GetFolderPath("CommonDesktopDirectory"),
        "$env:USERPROFILE\OneDrive\Desktop"
    )

    foreach ($path in $paths) {
        Stop-IfRequested

        if (Test-Path $path) {
            Get-ChildItem "$path\*.lnk" -ErrorAction SilentlyContinue | ForEach-Object {
                try {
                    $target = $ws.CreateShortcut($_.FullName).TargetPath
                    if ($target -like "*msedge*" -or $_.Name -like "*Edge*") {
                        Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
                        Write-Ok "Raccourci Edge supprime : $($_.FullName)"
                    }
                }
                catch {}
            }
        }
    }

    Write-Step "Suppression Edge / Microsoft Store / Copilot de la barre des taches..."

    try {
        [void](Remove-LDLCTaskbarPins -ExactNames @("Microsoft Edge", "Edge") -NamePatterns @("*Edge*") -PathPatterns @("*msedge.exe*") -ProgressMessage "Suppression Edge barre des taches..." -ProgressPercent 18 -Label "Edge")

        if (Get-Process -Name "msedge" -ErrorAction SilentlyContinue) {
            Write-Info "Edge est encore ouvert : une fenetre active peut afficher son icone meme apres desepinglage."
        }

        [void](Remove-LDLCTaskbarPins -ExactNames @("Copilot") -NamePatterns @("*Copilot*") -ProgressMessage "Suppression Copilot barre des taches..." -ProgressPercent 20 -Label "Copilot")

        [void](Remove-LDLCTaskbarPins -ExactNames @("Microsoft Store") -NamePatterns @("*Microsoft Store*") -PathPatterns @("*WinStore*") -ProgressMessage "Suppression Microsoft Store barre des taches..." -ProgressPercent 22 -Label "Microsoft Store")

    }
    catch {
        if (Test-LDLCStopRequestError $_) { throw }
        Write-Warn "Impossible de modifier la barre des taches : $($_.Exception.Message)"
    }

    try {
        Refresh-Desktop
    }
    catch {
        if (Test-LDLCStopRequestError $_) { throw }
        Write-Warn "Impossible d'actualiser le bureau apres modification de la barre des taches : $($_.Exception.Message)"
    }

    Write-ProgressFile 23 "Personnalisation Windows terminée."
}

# endregion Module: 20.WindowsLayout.ps1

