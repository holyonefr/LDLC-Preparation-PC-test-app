# Send Chrome pin commands through exposed Windows actions, without confirmation waits.
# Report transmission only; do not force layouts or restart Explorer globally.
function Test-LDLCChromeTaskbarVerb {
    param([string]$Name, [switch]$Unpin)
    $text = Convert-LDLCDefaultAppsComparableText ($Name -replace '&', '')
    if ($Unpin) { return $text -match '^(unpin from taskbar|detacher de la barre des taches|desepingler de la barre des taches)$' }
    return $text -match '^(pin to taskbar|epingler a la barre des taches|attacher a la barre des taches)$'
}

function Test-LDLCChromeTaskbarPath {
    param([string]$Actual, [string]$Expected)
    if (-not $Actual -or -not $Expected) { return $false }
    try {
        $left = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Actual.Trim('"')))
        $right = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Expected.Trim('"')))
        return [string]::Equals($left, $right, [StringComparison]::OrdinalIgnoreCase)
    } catch { return $false }
}

function Get-LDLCChromeShellPinItem {
    param([string]$ChromeExecutable)
    $shell = New-Object -ComObject Shell.Application
    $folder = $shell.Namespace((Split-Path -Parent $ChromeExecutable))
    if (-not $folder) { throw 'Dossier Chrome non expose par Windows Shell.' }
    $item = $folder.ParseName((Split-Path -Leaf $ChromeExecutable))
    if (-not $item) { throw 'Executable Chrome non expose par Windows Shell.' }
    return $item
}

function Get-LDLCChromeTaskbarPinState {
    param([string]$ChromeExecutable, [string]$PinDirectory)
    $item = Get-LDLCChromeShellPinItem -ChromeExecutable $ChromeExecutable
    foreach ($verb in @($item.Verbs())) {
        if (Test-LDLCChromeTaskbarVerb -Name ([string]$verb.Name) -Unpin) {
            return [pscustomobject]@{ Pinned = $true; Evidence = 'Windows expose Detacher de la barre des taches pour Chrome.' }
        }
    }
    if (-not $PinDirectory) { $PinDirectory = Join-Path $env:APPDATA 'Microsoft/Internet Explorer/Quick Launch/User Pinned/TaskBar' }
    if (Test-Path -LiteralPath $PinDirectory -PathType Container) {
        $wscript = New-Object -ComObject WScript.Shell
        foreach ($shortcut in @(Get-ChildItem -LiteralPath $PinDirectory -Filter '*.lnk' -File -ErrorAction Stop)) {
            $link = $wscript.CreateShortcut($shortcut.FullName)
            if (Test-LDLCChromeTaskbarPath -Actual ([string]$link.TargetPath) -Expected $ChromeExecutable) {
                return [pscustomobject]@{ Pinned = $true; Evidence = 'Raccourci epingle Windows cible l executable Chrome attendu.' }
            }
        }
    }
    return [pscustomobject]@{ Pinned = $false; Evidence = 'Aucune epingle Chrome confirmee par Windows.' }
}

function Invoke-LDLCChromeShellPin {
    param([string]$ChromeExecutable)
    $item = Get-LDLCChromeShellPinItem -ChromeExecutable $ChromeExecutable
    $verbs = @($item.Verbs() | Where-Object { Test-LDLCChromeTaskbarVerb -Name ([string]$_.Name) })
    if ($verbs.Count -ne 1) { return $false }
    [void]$verbs[0].DoIt()
    return $true
}

function Get-LDLCChromeExplorerSelection {
    param($Shell, [string]$ChromeExecutable)
    foreach ($window in @($Shell.Windows())) {
        try {
            if ((Split-Path -Leaf ([string]$window.FullName)) -ine 'explorer.exe') { continue }
            $selected = @($window.Document.SelectedItems())
            if ($selected.Count -eq 1 -and (Test-LDLCChromeTaskbarPath -Actual ([string]$selected[0].Path) -Expected $ChromeExecutable)) {
                return $window
            }
        } catch { }
    }
    return $null
}

function Test-LDLCChromeExplorerForeground {
    param([IntPtr]$Handle)
    $foreground = [LDLCDefaultAppsNative]::GetForegroundWindow()
    return ($foreground -eq $Handle -or [LDLCDefaultAppsNative]::GetAncestor($foreground, 3) -eq $Handle)
}

function Get-LDLCChromeTaskbarContextItems {
    param([uint32]$ProcessId)
    $desktop = [System.Windows.Automation.AutomationElement]::RootElement
    $windows = $desktop.FindAll([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition)
    $condition = New-Object System.Windows.Automation.PropertyCondition ([System.Windows.Automation.AutomationElement]::ControlTypeProperty), ([System.Windows.Automation.ControlType]::MenuItem)
    foreach ($window in $windows) {
        try {
            if ($window.Current.ProcessId -ne $ProcessId) { continue }
            foreach ($element in $window.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condition)) {
                if (-not $element.Current.IsOffscreen -and $element.Current.IsEnabled) {
                    [pscustomobject]@{ Element = $element; Name = [string]$element.Current.Name }
                }
            }
        } catch [System.Windows.Automation.ElementNotAvailableException] { continue }
    }
}

function Invoke-LDLCChromeTaskbarMenuItem {
    param($Item)
    $pattern = $null
    if (-not $Item.Element.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$pattern)) {
        throw 'Windows n expose pas l activation de cette commande de barre des taches.'
    }
    [void]$pattern.Invoke()
}

function Invoke-LDLCChromeTaskbarContextAction {
    param([string]$ChromeExecutable)
    Ensure-LDLCDefaultAppsNativeInterop
    Ensure-LDLCDefaultAppsUiAutomation
    Add-Type -AssemblyName System.Windows.Forms
    $shell = New-Object -ComObject Shell.Application
    $previousHandles = @($shell.Windows() | ForEach-Object { try { [long]$_.HWND } catch { } })
    $previousForeground = [LDLCDefaultAppsNative]::GetForegroundWindow()
    $window = $null; $handle = [IntPtr]::Zero; $menuOpened = $false
    try {
        Start-Process -FilePath explorer.exe -ArgumentList ('/select,"' + $ChromeExecutable + '"') -ErrorAction Stop | Out-Null
        $window = Wait-LDLCDefaultAppsCondition -TimeoutMilliseconds 4000 -PollMilliseconds 200 -Probe {
            Get-LDLCChromeExplorerSelection -Shell $shell -ChromeExecutable $ChromeExecutable
        }
        if (-not $window) { throw 'Selection de l executable Chrome non confirmee dans Explorer ; aucune touche envoyee.' }
        $handle = [IntPtr][long]$window.HWND
        [void](Set-LDLCDefaultAppsFocus -Window ([pscustomobject]@{ Handle = $handle }))
        if (-not (Test-LDLCChromeExplorerForeground -Handle $handle)) { throw 'Explorer ne possede pas le premier plan ; aucune touche envoyee.' }
        $selected = Get-LDLCChromeExplorerSelection -Shell $shell -ChromeExecutable $ChromeExecutable
        if (-not $selected -or [long]$selected.HWND -ne [long]$handle) { throw 'La selection Chrome a change ; epinglage annule.' }
        [System.Windows.Forms.SendKeys]::SendWait('+{F10}')
        $menuOpened = $true
        $tracking = @{ More = $false }
        $result = Wait-LDLCDefaultAppsCondition -TimeoutMilliseconds 4000 -PollMilliseconds 200 -Probe {
            if (-not (Test-LDLCChromeExplorerForeground -Handle $handle)) { return $false }
            $selected = Get-LDLCChromeExplorerSelection -Shell $shell -ChromeExecutable $ChromeExecutable
            if (-not $selected -or [long]$selected.HWND -ne [long]$handle) { return $false }
            $ownerProcess = [uint32]0
            [void][LDLCDefaultAppsNative]::GetWindowThreadProcessId($handle, [ref]$ownerProcess)
            $items = @(Get-LDLCChromeTaskbarContextItems -ProcessId $ownerProcess)
            $unpin = @($items | Where-Object { Test-LDLCChromeTaskbarVerb -Name $_.Name -Unpin })
            if ($unpin.Count -eq 1) { return [pscustomobject]@{ ObservedPinned = $true; Invoked = $false } }
            $pin = @($items | Where-Object { Test-LDLCChromeTaskbarVerb -Name $_.Name })
            if ($pin.Count -eq 1) {
                Invoke-LDLCChromeTaskbarMenuItem -Item $pin[0]
                return [pscustomobject]@{ ObservedPinned = $false; Invoked = $true }
            }
            if ($pin.Count -gt 1 -or $unpin.Count -gt 1) { throw 'Menu Windows ambigu ; aucun element choisi.' }
            if (-not $tracking.More) {
                $more = @($items | Where-Object { (Convert-LDLCDefaultAppsComparableText $_.Name) -match '^(afficher plus d.options|show more options)$' })
                if ($more.Count -eq 1) { Invoke-LDLCChromeTaskbarMenuItem -Item $more[0]; $tracking.More = $true }
            }
            return $false
        }
        if (-not $result) { throw 'Commande Epingler a la barre des taches absente, desactivee ou non accessible dans le menu Windows de Chrome.' }
        return $result
    }
    finally {
        if ($menuOpened -and (Test-LDLCChromeExplorerForeground -Handle $handle)) { [System.Windows.Forms.SendKeys]::SendWait('{ESC}') }
        if ($window -and [long]$handle -notin $previousHandles) { try { $window.Quit() } catch { } }
        if ($previousForeground -ne [IntPtr]::Zero) { [void][LDLCDefaultAppsNative]::SetForegroundWindow($previousForeground) }
    }
}

function Wait-LDLCChromeTaskbarPin {
    param([string]$ChromeExecutable, [int]$TimeoutMilliseconds = 2000)
    return [bool](Wait-LDLCDefaultAppsCondition -TimeoutMilliseconds $TimeoutMilliseconds -PollMilliseconds 200 -Probe {
        (Get-LDLCChromeTaskbarPinState -ChromeExecutable $ChromeExecutable).Pinned
    })
}

function Invoke-LDLCChromeTaskbarPin {
    param([int]$ProgressPercent = 90)
    Stop-IfRequested
    Write-Section 'EPINGLAGE CHROME BARRE DES TACHES'
    Write-ProgressFile $ProgressPercent 'Epinglage de Chrome a la barre des taches...'
    $chrome = Get-LDLCChromeExecutablePath
    if (-not $chrome) { Write-Warn 'Chrome introuvable : epinglage non effectue.'; return $false }
    try {
        if ((Get-LDLCChromeTaskbarPinState -ChromeExecutable $chrome).Pinned) {
            Write-Info 'Chrome deja epingle ; aucune action necessaire.'
            return $true
        }
        $verbInvoked = Invoke-LDLCChromeShellPin -ChromeExecutable $chrome
        if ($verbInvoked -and (Get-LDLCChromeTaskbarPinState -ChromeExecutable $chrome).Pinned) {
            Write-Info 'Commande d epinglage Chrome transmise.'
            return $true
        }
        $action = Invoke-LDLCChromeTaskbarContextAction -ChromeExecutable $chrome
        if (-not $action.ObservedPinned -and -not $action.Invoked) { throw 'Aucune commande d epinglage Windows accessible.' }
        Write-Info 'Commande d epinglage Chrome transmise ; poursuite sans attente de confirmation.'
        return $true
    } catch {
        if (Test-LDLCStopRequestError $_) { throw }
        Write-Warn ('Commande d epinglage Chrome impossible : ' + $_.Exception.Message)
        return $false
    }
}
