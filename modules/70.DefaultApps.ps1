# region Module: 70.DefaultApps.ps1
# Only Windows-reported effective associations can confirm success. UI actions are attempts.

function Ensure-LDLCDefaultAppsNativeInterop {
    if ('LDLCDefaultAppsNative' -as [type]) { return }
    Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public delegate bool LDLCEnumWindowsProc(IntPtr hwnd, IntPtr parameter);
[StructLayout(LayoutKind.Sequential)] public struct LDLCDefaultAppsPoint { public int X; public int Y; }
[ComImport, Guid("4e530b0a-e611-4c77-a3ac-9031d022281b"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface ILDLCApplicationAssociationRegistration {
    [PreserveSig] int QueryCurrentDefault([MarshalAs(UnmanagedType.LPWStr)] string query,
        int associationType, int associationLevel, out IntPtr association);
}
public static class LDLCDefaultAppsNative {
    [DllImport("user32.dll")] public static extern bool EnumWindows(LDLCEnumWindowsProc callback, IntPtr parameter);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr parent, LDLCEnumWindowsProc callback, IntPtr parameter);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hwnd, uint message, IntPtr wparam, IntPtr lparam);
    [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(LDLCDefaultAppsPoint point);
    [DllImport("user32.dll")] public static extern bool SetPhysicalCursorPos(int x, int y);
    [StructLayout(LayoutKind.Sequential)] public struct MouseInput {
        public int dx, dy; public uint data, flags, time; public IntPtr extra;
    }
    [StructLayout(LayoutKind.Explicit)] public struct InputUnion { [FieldOffset(0)] public MouseInput mouse; }
    [StructLayout(LayoutKind.Sequential)] public struct Input { public uint type; public InputUnion data; }
    [DllImport("user32.dll", SetLastError=true)] private static extern uint SendInput(uint count, Input[] inputs, int size);
    public static void ClickAt(int x, int y) {
        if (!SetPhysicalCursorPos(x, y)) throw new InvalidOperationException("Positionnement souris refuse par Windows");
        System.Threading.Thread.Sleep(90);
        Input[] inputs = new Input[2];
        inputs[0].data.mouse.flags = 0x0002;
        inputs[1].data.mouse.flags = 0x0004;
        if (SendInput(2, inputs, Marshal.SizeOf(typeof(Input))) != 2)
            throw new InvalidOperationException("Clic refuse par Windows (focus/niveau de privileges); aucune association confirmee");
    }
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hwnd, int command);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr hwnd, uint flags);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint from, uint to, bool attach);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hwnd, StringBuilder text, int count);
    [DllImport("shlwapi.dll", CharSet=CharSet.Unicode, ExactSpelling=true)]
    private static extern int AssocQueryStringW(uint flags, uint kind, string association, string extra, StringBuilder output, ref uint count);
    public static string CurrentDefault(string association) {
        object instance = Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("591209c7-767b-42b2-9fba-44ee4615f2c7")));
        IntPtr value = IntPtr.Zero;
        try {
            // AT_FILEEXTENSION=0, AT_URLPROTOCOL=1, AL_EFFECTIVE=1. Read-only.
            int hr = ((ILDLCApplicationAssociationRegistration)instance).QueryCurrentDefault(
                association, association.StartsWith(".") ? 0 : 1, 1, out value);
            Marshal.ThrowExceptionForHR(hr);
            return Marshal.PtrToStringUni(value) ?? "";
        } finally {
            if (value != IntPtr.Zero) Marshal.FreeCoTaskMem(value);
            Marshal.ReleaseComObject(instance);
        }
    }
    public static string Executable(string association) {
        // NOFIXUPS prevents registry repair; IS_PROTOCOL honors the user's URL defaults.
        uint flags = 0x100u | (association.StartsWith(".") ? 0u : 0x1000u);
        uint count = 0;
        int hr = AssocQueryStringW(flags, 2, association, "open", null, ref count);
        if (hr < 0) Marshal.ThrowExceptionForHR(hr);
        if (count == 0 || count > 32768) throw new InvalidOperationException("Executable non resolu");
        StringBuilder text = new StringBuilder((int)count);
        Marshal.ThrowExceptionForHR(AssocQueryStringW(flags, 2, association, "open", text, ref count));
        return text.ToString();
    }
}
"@
}

function Ensure-LDLCDefaultAppsUiAutomation {
    Add-Type -AssemblyName UIAutomationClient
    Add-Type -AssemblyName UIAutomationTypes
}

function Get-LDLCDefaultAppsTick {
    return ([double][Diagnostics.Stopwatch]::GetTimestamp() * 1000 / [Diagnostics.Stopwatch]::Frequency)
}

function Wait-LDLCDefaultAppsCondition {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Probe,
        [ValidateRange(0, 120000)][int]$TimeoutMilliseconds = 15000,
        [ValidateRange(50, 2000)][int]$PollMilliseconds = 400
    )
    $deadline = (Get-LDLCDefaultAppsTick) + $TimeoutMilliseconds
    do {
        Stop-IfRequested
        $value = & $Probe
        if ($value) { return $value }
        $remaining = $deadline - (Get-LDLCDefaultAppsTick)
        if ($remaining -le 0) { break }
        Start-Sleep -Milliseconds ([int][math]::Min($PollMilliseconds, $remaining))
    } while ($true)
    return $null
}

function Convert-LDLCDefaultAppsComparableText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $builder = New-Object Text.StringBuilder
    foreach ($character in $Text.Normalize([Text.NormalizationForm]::FormD).ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($character) -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$builder.Append($character)
        }
    }
    return (($builder.ToString().ToLowerInvariant() -replace '\s+', ' ').Trim())
}

function Get-LDLCEffectiveAssociation {
    param([Parameter(Mandatory = $true)][string]$Association)
    $progId = ''; $executable = ''; $errorText = ''
    try {
        Ensure-LDLCDefaultAppsNativeInterop
        $progId = [LDLCDefaultAppsNative]::CurrentDefault($Association)
        $executable = [LDLCDefaultAppsNative]::Executable($Association)
        if ($progId -cne [LDLCDefaultAppsNative]::CurrentDefault($Association)) {
            throw 'Association modifiee pendant la lecture; nouvelle verification requise.'
        }
        if (-not $progId -or -not $executable -or -not (Test-Path -LiteralPath $executable -PathType Leaf)) {
            throw 'ProgID ou executable effectif absent.'
        }
    }
    catch { $errorText = $_.Exception.Message }
    return [pscustomobject]@{ Association = $Association; ProgId = $progId; Executable = $executable; Error = $errorText }
}

function Test-LDLCEffectiveAssociationTarget {
    param($State, [ValidateSet('Chrome', 'Adobe')][string]$Application)
    if (-not $State -or $State.Error -or -not $State.ProgId -or -not $State.Executable) { return $false }
    $fileName = [IO.Path]::GetFileName($State.Executable)
    if ($Application -eq 'Chrome') {
        return ($State.ProgId -match '^ChromeHTML(?:\.|$)' -and $fileName -ieq 'chrome.exe')
    }
    return ($State.ProgId -match '^(Acrobat|AcroExch)\.Document(?:\.|$)' -and $fileName -in @('Acrobat.exe', 'AcroRd32.exe'))
}

function Get-LDLCDefaultAppState {
    param([ValidateSet('Chrome', 'Adobe')][string]$Application)
    $keys = if ($Application -eq 'Chrome') { @('http', 'https', '.htm', '.html') } else { @('.pdf') }
    $states = @($keys | ForEach-Object { Get-LDLCEffectiveAssociation -Association $_ })
    $missing = @($states | Where-Object { -not (Test-LDLCEffectiveAssociationTarget -State $_ -Application $Application) })
    return [pscustomobject]@{ Application = $Application; Confirmed = ($missing.Count -eq 0); Associations = $states; Missing = @($missing | ForEach-Object { $_.Association }) }
}

function Get-LDLCChromeDefaultBrowserState {
    $state = Get-LDLCDefaultAppState -Application Chrome
    return [pscustomobject]@{
        IsChrome = $state.Confirmed; Associations = $state.Associations; Missing = $state.Missing
        HttpProgId = $state.Associations[0].ProgId; HttpsProgId = $state.Associations[1].ProgId
        HtmProgId = $state.Associations[2].ProgId; HtmlProgId = $state.Associations[3].ProgId
    }
}

function Get-LDLCAdobePdfDefaultState {
    $state = Get-LDLCDefaultAppState -Application Adobe
    return [pscustomobject]@{ IsAcrobat = $state.Confirmed; CurrentProgId = $state.Associations[0].ProgId; Associations = $state.Associations; Missing = $state.Missing }
}

function Wait-LDLCDefaultAppConfirmation {
    param([ValidateSet('Chrome', 'Adobe')][string]$Application, [int]$TimeoutMilliseconds = 12000)
    # Two independent readings avoid accepting a transient association during a reset.
    $tracking = @{ Last = $null; Consecutive = 0 }
    $confirmed = Wait-LDLCDefaultAppsCondition -TimeoutMilliseconds $TimeoutMilliseconds -PollMilliseconds 500 -Probe {
        $tracking.Last = Get-LDLCDefaultAppState -Application $Application
        if ($tracking.Last.Confirmed) { $tracking.Consecutive++ } else { $tracking.Consecutive = 0 }
        return ($tracking.Consecutive -ge 2)
    }
    return [pscustomobject]@{ Confirmed = [bool]$confirmed; State = $tracking.Last }
}

function Wait-LDLCChromeDefaultBrowserConfirmation {
    param([int]$TimeoutSeconds = 24)
    return Wait-LDLCDefaultAppConfirmation -Application Chrome -TimeoutMilliseconds ($TimeoutSeconds * 1000)
}

function Wait-LDLCAdobePdfDefaultConfirmation {
    param([int]$TimeoutSeconds = 24)
    return Wait-LDLCDefaultAppConfirmation -Application Adobe -TimeoutMilliseconds ($TimeoutSeconds * 1000)
}

function Get-LDLCDefaultAppUris {
    param([ValidateSet('Chrome', 'Adobe')][string]$Application)
    $uris = New-Object 'Collections.Generic.List[string]'
    foreach ($hive in @([Microsoft.Win32.RegistryHive]::CurrentUser, [Microsoft.Win32.RegistryHive]::LocalMachine)) {
        foreach ($view in @([Microsoft.Win32.RegistryView]::Registry64, [Microsoft.Win32.RegistryView]::Registry32)) {
            $baseKey = $null; $key = $null
            try {
                $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey($hive, $view)
                $key = $baseKey.OpenSubKey('Software\RegisteredApplications')
                if (-not $key) { continue }
                foreach ($name in $key.GetValueNames()) {
                    if (-not (Test-LDLCDefaultAppsApplicationName -Name $name -Application $Application -RegisteredName)) { continue }
                    $parameter = if ($hive -eq [Microsoft.Win32.RegistryHive]::CurrentUser) { 'registeredAppUser' } else { 'registeredAppMachine' }
                    $uri = 'ms-settings:defaultapps?' + $parameter + '=' + [Uri]::EscapeDataString($name)
                    if (-not $uris.Contains($uri)) { $uris.Add($uri) }
                }
            }
            finally {
                if ($key) { $key.Dispose() }
                if ($baseKey) { $baseKey.Dispose() }
            }
        }
    }
    return $uris.ToArray()
}

function Get-LDLCDefaultAppsWindows {
    Ensure-LDLCDefaultAppsNativeInterop
    $handles = New-Object 'Collections.Generic.List[IntPtr]'
    $callback = [LDLCEnumWindowsProc]{ param([IntPtr]$handle, [IntPtr]$parameter)
        $handles.Add($handle)
        return $true
    }
    [void][LDLCDefaultAppsNative]::EnumWindows($callback, [IntPtr]::Zero)
    # The Windows 11 OpenWith foreground host can be a child/InputSite HWND,
    # absent from EnumWindows even while its chooser is visible to the technician.
    $foreground = [LDLCDefaultAppsNative]::GetForegroundWindow()
    if ($foreground -ne [IntPtr]::Zero -and -not $handles.Contains($foreground)) { $handles.Insert(0, $foreground) }
    foreach ($handle in $handles) {
        $processId = [uint32]0
        [void][LDLCDefaultAppsNative]::GetWindowThreadProcessId($handle, [ref]$processId)
        try { $process = Get-Process -Id $processId -ErrorAction Stop } catch { continue }
        if (-not [LDLCDefaultAppsNative]::IsWindowVisible($handle) -and $process.ProcessName -ne 'OpenWith') { continue }
        $text = New-Object Text.StringBuilder 512
        [void][LDLCDefaultAppsNative]::GetWindowText($handle, $text, $text.Capacity)
        $isSettings = $process.ProcessName -eq 'SystemSettings' -or ($process.ProcessName -eq 'ApplicationFrameHost' -and $text.ToString() -match '(?i)param|settings')
        if ($isSettings -or $process.ProcessName -in @('OpenWith', 'PickerHost', 'ShellExperienceHost', 'ApplicationFrameHost', 'AppResolverUX')) {
            [pscustomobject]@{ Handle = $handle; IsSettings = $isSettings; ProcessId = $processId }
        }
    }
}

function Set-LDLCDefaultAppsFocus {
    param($Window)
    $foreground = [LDLCDefaultAppsNative]::GetForegroundWindow()
    if ($foreground -eq $Window.Handle -or [LDLCDefaultAppsNative]::GetAncestor($foreground, 3) -eq $Window.Handle) { return $true }
    $foregroundProcess = [uint32]0
    [void][LDLCDefaultAppsNative]::GetWindowThreadProcessId($foreground, [ref]$foregroundProcess)
    if ($foregroundProcess -eq $Window.ProcessId -and $foregroundProcess -ne 0) { return $true }
    if ([LDLCDefaultAppsNative]::IsIconic($Window.Handle)) { [void][LDLCDefaultAppsNative]::ShowWindowAsync($Window.Handle, 4) }
    [void][LDLCDefaultAppsNative]::SetForegroundWindow($Window.Handle)
    if ([LDLCDefaultAppsNative]::GetForegroundWindow() -ne $Window.Handle) {
        $thread = [LDLCDefaultAppsNative]::GetCurrentThreadId()
        $foregroundThread = [LDLCDefaultAppsNative]::GetWindowThreadProcessId($foreground, [ref]$foregroundProcess)
        $attached = $false
        try {
            if ($foregroundThread -ne 0 -and $foregroundThread -ne $thread) { $attached = [LDLCDefaultAppsNative]::AttachThreadInput($thread, $foregroundThread, $true) }
            [void][LDLCDefaultAppsNative]::SetForegroundWindow($Window.Handle)
        }
        finally { if ($attached) { [void][LDLCDefaultAppsNative]::AttachThreadInput($thread, $foregroundThread, $false) } }
    }
    # The next poll checks focus again; never maximize or force input into another app.
    $foreground = [LDLCDefaultAppsNative]::GetForegroundWindow()
    [void][LDLCDefaultAppsNative]::GetWindowThreadProcessId($foreground, [ref]$foregroundProcess)
    return ($foreground -eq $Window.Handle -or [LDLCDefaultAppsNative]::GetAncestor($foreground, 3) -eq $Window.Handle -or
        ($foregroundProcess -eq $Window.ProcessId -and $foregroundProcess -ne 0))
}

function Get-LDLCDefaultAppsRoot {
    param($Window)
    Ensure-LDLCDefaultAppsUiAutomation
    Ensure-LDLCDefaultAppsNativeInterop
    $bestRoot = [System.Windows.Automation.AutomationElement]::FromHandle($Window.Handle)
    $bestCount = $bestRoot.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition).Count
    if ($Window.IsSettings -and $bestCount -gt 0) { return $bestRoot }
    # OpenWith can expose only a dummy top-level HWND; its child hosts own the UIA tree.
    $handles = New-Object 'Collections.Generic.List[IntPtr]'
    $callback = [LDLCEnumWindowsProc]{ param([IntPtr]$handle, [IntPtr]$parameter)
        $handles.Add($handle)
        return $true
    }
    [void][LDLCDefaultAppsNative]::EnumChildWindows($Window.Handle, $callback, [IntPtr]::Zero)
    foreach ($handle in $handles) {
        try {
            $root = [System.Windows.Automation.AutomationElement]::FromHandle($handle)
            $count = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition).Count
            if ($count -gt $bestCount) { $bestRoot = $root; $bestCount = $count }
        } catch { continue }
    }
    return $bestRoot
}

function Get-LDLCDefaultAppsParentElement {
    param($Element)
    return [System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($Element)
}

function Test-LDLCDefaultAppsSameElement {
    param($Left, $Right)
    if (-not $Left -or -not $Right) { return $false }
    return (($Left.GetRuntimeId() -join '.') -eq ($Right.GetRuntimeId() -join '.'))
}

function Resolve-LDLCDefaultAppsChoiceElement {
    param($Element, $Root)
    # Windows can expose the app label as a Text child of an unnamed clickable row.
    # Stay inside the observed picker; never invoke an arbitrary page ancestor.
    $candidate = $Element
    for ($depth = 0; $candidate -and $depth -lt 5; $depth++) {
        if (Test-LDLCDefaultAppsSameElement $candidate $Root) { return $null }
        $type = $candidate.Current.ControlType.ProgrammaticName
        if ($type -in @('ControlType.Button', 'ControlType.ListItem', 'ControlType.RadioButton', 'ControlType.Hyperlink')) {
            return $candidate
        }
        $candidate = Get-LDLCDefaultAppsParentElement -Element $candidate
    }
    return $null
}

function Get-LDLCDefaultAppsControls {
    param($Root)
    $elements = $Root.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
    foreach ($element in $elements) {
        try {
            $current = $element.Current
            $target = $element
            $name = Convert-LDLCDefaultAppsComparableText $current.Name
            if ($current.ControlType.ProgrammaticName -eq 'ControlType.Text' -and
                ((Test-LDLCDefaultAppsApplicationName -Name $name -Application Adobe) -or
                 (Test-LDLCDefaultAppsApplicationName -Name $name -Application Chrome))) {
                $row = Resolve-LDLCDefaultAppsChoiceElement -Element $element -Root $Root
                if ($row) {
                    # Preserve the heading for page detection as well as the clickable alias.
                    [pscustomobject]@{ Element = $element; Name = $name; AutomationId = $current.AutomationId;
                        ControlType = $current.ControlType.ProgrammaticName; Enabled = $current.IsEnabled; Offscreen = $current.IsOffscreen }
                    $target = $row; $current = $row.Current
                }
            }
            [pscustomobject]@{
                Element = $target; Name = $name
                AutomationId = $current.AutomationId; ControlType = $current.ControlType.ProgrammaticName
                Enabled = $current.IsEnabled; Offscreen = $current.IsOffscreen
            }
        }
        catch { continue } # Virtualized controls may disappear between enumeration and reading.
    }
}

function Get-LDLCDefaultAppsPickerRoot {
    param($Window, $Root, [string]$Association)
    $candidates = @()
    if (-not $Window.IsSettings) { $candidates = @($Root) }
    else {
        $elements = $Root.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
        foreach ($element in $elements) {
            try {
                if (-not $element.Current.IsOffscreen -and
                    ($element.Current.ControlType -eq [System.Windows.Automation.ControlType]::Window -or
                     $element.Current.ClassName -match '^(ContentDialog|Popup)$')) { $candidates += $element }
            }
            catch { continue }
        }
    }
    $pattern = '(?i)(?<![a-z0-9.])' + [regex]::Escape($Association) + '(?![a-z0-9])'
    if ($Window.IsSettings) {
        # Modern XAML pickers can be Pane/Group rather than Window/ContentDialog.
        # Find the smallest chooser subtree, not the Settings page behind it.
        foreach ($element in $elements) {
            try {
                $name = Convert-LDLCDefaultAppsComparableText $element.Current.Name
                if ($element.Current.IsOffscreen -or $name -notmatch '(choisi|select|choose|comment.*ouvrir)') { continue }
                $parent = $element
                for ($depth = 0; $parent -and $depth -lt 9; $depth++) {
                    $candidates += $parent
                    if (Test-LDLCDefaultAppsSameElement $parent $Root) { break }
                    $parent = Get-LDLCDefaultAppsParentElement $parent
                }
            }
            catch { continue }
        }
    }
    $valid = @()
    foreach ($candidate in $candidates) {
        $controls = @(Get-LDLCDefaultAppsControls $candidate)
        $names = ((@([string]$candidate.Current.Name) + @(($controls | Where-Object { -not $_.Offscreen }).Name)) -join ' ')
        if ($names -notmatch $pattern -or (Convert-LDLCDefaultAppsComparableText $names) -notmatch '(choisi|select|choose|comment.*ouvrir)') { continue }
        # An association card on the underlying page is never a selector choice.
        if (@($controls | Where-Object { $_.ControlType -eq 'ControlType.Button' -and $_.Name -match '^\.[a-z0-9]+(?:\s|,|:)' }).Count) { continue }
        $choice = (Select-LDLCDefaultAppsControl $controls Choice -Application Adobe) -or
            (Select-LDLCDefaultAppsControl $controls Choice -Application Chrome)
        if ($choice) { $valid += [pscustomobject]@{ Root = $candidate; Count = $controls.Count } }
    }
    if ($valid.Count) { return ($valid | Sort-Object Count | Select-Object -First 1).Root }
    return $null
}

function Select-LDLCDefaultAppsControl {
    param($Controls, [ValidateSet('Association', 'Choice', 'Confirm', 'Page')][string]$Kind,
        [string]$Association, [ValidateSet('Chrome', 'Adobe')][string]$Application)
    foreach ($control in @($Controls | Sort-Object Offscreen)) {
        if (-not $control.Enabled) { continue }
        $name = Convert-LDLCDefaultAppsComparableText $control.Name
        $isApplication = Test-LDLCDefaultAppsApplicationName -Name $name -Application $Application
        $actionable = $control.ControlType -in @('ControlType.Button', 'ControlType.ListItem', 'ControlType.RadioButton', 'ControlType.Hyperlink')
        switch ($Kind) {
            'Page' {
                $chromeHeading = $Application -eq 'Chrome' -and (Test-LDLCChromeBrowserDefaultLabel -Name $name)
                $pageType = $control.ControlType -in @('ControlType.Text', 'ControlType.Button') -or ($chromeHeading -and $control.ControlType -eq 'ControlType.Group')
                if (($isApplication -or $chromeHeading) -and $pageType -and -not $control.Offscreen) { return $control }
            }
            'Association' {
                if ($actionable -and $name -match ('^' + [regex]::Escape($Association) + '(?:[,\s:]|$)')) { return $control }
            }
            'Choice' {
                if ($actionable -and $isApplication) { return $control }
            }
            'Confirm' {
                if (-not $control.Offscreen -and $control.ControlType -eq 'ControlType.Button' -and
                    $name -match '^(definir par defaut|set default|set as default|ok|toujours|always|changer quand meme|basculer quand meme|switch anyway)$') { return $control }
            }
        }
    }
    return $null
}

function Test-LDLCChromeBrowserDefaultLabel {
    param([string]$Name, [switch]$WithAction)
    $name = Convert-LDLCDefaultAppsComparableText $Name
    $heading = '(?:definir google chrome (?:comme |en tant que |pour )?(?:votre )?navigateur par defaut|make google chrome (?:your |the )?default browser|(?:set|use) google chrome as (?:your |the )?default browser)'
    $action = '(?:definir par defaut|set default|set as default)'
    $separator = '\s*[,;:\-]?\s*'
    if ($name -match ('^' + $heading + $separator + $action + '[.!]?$') -or
        $name -match ('^' + $action + $separator + $heading + '[.!]?$')) { return $true }
    return (-not $WithAction -and $name -match ('^' + $heading + '[.:!]?$'))
}

function Get-LDLCChromeBrowserDefaultControl {
    param($Root)
    $controls = @(Get-LDLCDefaultAppsControls $Root)
    $qualified = @($controls | Where-Object { $_.Enabled -and $_.ControlType -eq 'ControlType.Button' -and
        (Test-LDLCChromeBrowserDefaultLabel -Name $_.Name -WithAction) } | Sort-Object Offscreen)
    $visible = @($qualified | Where-Object { -not $_.Offscreen })
    if ($visible.Count -eq 1) { return $visible[0] }
    if ($qualified.Count -eq 1) { return $qualified[0] }
    if ($qualified.Count -gt 1) { return $null }
    $candidates = @{}
    foreach ($heading in @($controls | Where-Object { Test-LDLCChromeBrowserDefaultLabel -Name $_.Name })) {
        $parent = $heading.Element
        for ($depth = 0; $parent -and $depth -lt 8; $depth++) {
            if (Test-LDLCDefaultAppsSameElement $parent $Root) { break }
            $children = @(Get-LDLCDefaultAppsControls $parent)
            # Scope the button to the browser heading, never the PDF card or chooser.
            if (@($children | Where-Object { $_.Name -match '^\.[a-z0-9]+(?:\s|,|:)' }).Count) { break }
            $buttons = @{}
            $hasActionLabel = $false
            foreach ($child in $children) {
                if ((Convert-LDLCDefaultAppsComparableText $child.Name) -notmatch '^(definir par defaut|set default|set as default)$') { continue }
                $hasActionLabel = $true
                $button = $child
                if ($child.ControlType -eq 'ControlType.Text') {
                    # XAML can put the label inside an otherwise unnamed Button.
                    $element = Resolve-LDLCDefaultAppsChoiceElement -Element $child.Element -Root $parent
                    if (-not $element -or $element.Current.ControlType.ProgrammaticName -ne 'ControlType.Button') { continue }
                    $button = [pscustomobject]@{ Element = $element; Name = $child.Name; AutomationId = $element.Current.AutomationId;
                        ControlType = 'ControlType.Button'; Enabled = $element.Current.IsEnabled; Offscreen = $element.Current.IsOffscreen }
                }
                if ($button.ControlType -eq 'ControlType.Button' -and $button.Enabled) {
                    $buttons[($button.Element.GetRuntimeId() -join '.')] = $button
                }
            }
            if ($hasActionLabel) {
                foreach ($key in $buttons.Keys) { $candidates[$key] = $buttons[$key] }
                break
            }
            $parent = Get-LDLCDefaultAppsParentElement $parent
        }
    }
    $visible = @($candidates.Values | Where-Object { -not $_.Offscreen })
    if ($visible.Count -eq 1) { return $visible[0] }
    if ($candidates.Count -eq 1) { return @($candidates.Values)[0] }
    return $null
}

function Test-LDLCDefaultAppsApplicationName {
    param([string]$Name, [ValidateSet('Chrome', 'Adobe')][string]$Application, [switch]$RegisteredName)
    $name = Convert-LDLCDefaultAppsComparableText $Name
    $brand = if ($Application -eq 'Chrome') { 'google chrome' }
        else { '(?:adobe (?:acrobat(?: reader)?|reader)|acrobat(?: reader)?)' }
    # Registry names may contain edition/version suffixes. Picker names remain anchored
    # so a Store/search/help command containing the brand cannot be selected as an app.
    if ($RegisteredName) { return ($name -match ('(?<![a-z0-9])' + $brand + '(?![a-z0-9])')) }
    $suffix = if ($Application -eq 'Adobe') { '(?: dc)?' } else { '' }
    return ($name -match ('^' + $brand + $suffix + '(?:\s*\([^)]*\))?$'))
}

function Get-LDLCDefaultAppsVisibleChoice {
    param([string]$Association, [ValidateSet('Chrome', 'Adobe')][string]$Application)
    Ensure-LDLCDefaultAppsUiAutomation
    foreach ($window in @(Get-LDLCDefaultAppsWindows | Sort-Object IsSettings)) {
        try {
            $root = Get-LDLCDefaultAppsPickerRoot -Window $window -Root (Get-LDLCDefaultAppsRoot $window) -Association $Association
            if (-not $root) { continue }
            $control = Select-LDLCDefaultAppsControl -Controls @(Get-LDLCDefaultAppsControls $root) -Kind Choice -Application $Application
            if ($control -and -not $control.Offscreen) { return $control }
        }
        catch { if (Test-LDLCStopRequestError $_) { throw } }
    }
    return $null
}

function Get-LDLCDefaultAppAttemptRoutes {
    param([ValidateSet('Chrome', 'Adobe')][string]$Application, $State)
    # Reuse a selector already showing the requested app before navigating away from it.
    $pickerAssociation = if ($Application -eq 'Chrome') { '.html' } else { '.pdf' }
    if ($pickerAssociation -in $State.Missing -and (Get-LDLCDefaultAppsVisibleChoice -Association $pickerAssociation -Application $Application)) {
        [pscustomobject]@{ Kind = 'Picker'; Uri = ''; Association = $pickerAssociation }
    }
    foreach ($uri in @(Get-LDLCDefaultAppUris -Application $Application | Select-Object -Unique)) {
        [pscustomobject]@{ Kind = 'RegisteredPage'; Uri = $uri; Association = '' }
    }
}

function Invoke-LDLCDefaultAppsControl {
    param($Control, [ValidateSet('Association', 'Choice', 'Confirm', 'BrowserDefault')][string]$Kind)
    $element = $Control.Element
    if ($Control.Offscreen) {
        $scroll = $null
        if ($element.TryGetCurrentPattern([System.Windows.Automation.ScrollItemPattern]::Pattern, [ref]$scroll)) {
            $scroll.ScrollIntoView()
        }
        return $false # Reacquire after scrolling; coordinates and cached rectangles are never used.
    }
    if (-not $element.Current.IsEnabled -or $element.Current.IsOffscreen) { return $false }
    if ($Kind -eq 'BrowserDefault') {
        # The global browser button is an action, not an OpenWith picker row.
        # UIA Invoke also works when the Settings hit-test reports its XAML parent.
        $invoke = $null
        try {
            if ($element.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$invoke)) {
                $invoke.Invoke()
                Write-Info '[DEFAULT-APPS] Bouton navigateur Chrome active par Windows UIA.'
                return $true
            }
        }
        catch { Write-Info ('[DEFAULT-APPS] Activation UIA indisponible, tentative de clic observe : ' + $_.Exception.Message) }
        return (Invoke-LDLCDefaultAppsObservedClick -Control $Control)
    }
    # Preserve the pre-compact UI behavior: XAML Invoke can return without opening
    # the picker, and SelectionItem.Select alone may not commit an app choice.
    if (Invoke-LDLCDefaultAppsObservedClick -Control $Control) { return $true }
    $pattern = $null
    if ($element.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$pattern)) {
        $pattern.Invoke()
        return $true
    }
    if ($Kind -eq 'Choice' -and $element.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$pattern)) {
        $pattern.Select()
        if (-not $pattern.Current.IsSelected) { throw "Ligne non selectionnee par Windows : $($Control.Name)" }
        return $true
    }
    throw "Controle UIA sans pattern Invoke/SelectionItem : $($Control.Name)"
}

function Invoke-LDLCDefaultAppsObservedClick {
    param($Control)
    if ($Control.Element -isnot [System.Windows.Automation.AutomationElement]) { return $false }
    if ($script:LDLCDefaultAppsCompactPath -and -not (Test-LDLCDefaultAppsCompactUiAck)) { return $false }
    Ensure-LDLCDefaultAppsNativeInterop
    Stop-IfRequested
    $element = $Control.Element
    $rect = $element.Current.BoundingRectangle
    if ($rect.IsEmpty -or $rect.Width -le 0 -or $rect.Height -le 0) { return $false }
    $point = New-Object LDLCDefaultAppsPoint
    $point.X = [int][math]::Round($rect.Left + $rect.Width / 2)
    $point.Y = [int][math]::Round($rect.Top + $rect.Height / 2)
    $handle = [LDLCDefaultAppsNative]::WindowFromPoint($point)
    $processId = [uint32]0
    [void][LDLCDefaultAppsNative]::GetWindowThreadProcessId($handle, [ref]$processId)
    $process = Get-Process -Id $processId -ErrorAction Stop
    if ($process.ProcessName -notin @('SystemSettings','ApplicationFrameHost','OpenWith','PickerHost','ShellExperienceHost','AppResolverUX')) {
        throw "Controle masque par une autre fenetre; aucun clic envoye : $($Control.Name)"
    }
    $hit = [System.Windows.Automation.AutomationElement]::FromPoint((New-Object Windows.Point $point.X,$point.Y))
    $matched = $false
    for ($depth = 0; $hit -and $depth -lt 8; $depth++) {
        if (Test-LDLCDefaultAppsSameElement $hit $element) { $matched = $true; break }
        $hit = Get-LDLCDefaultAppsParentElement $hit
    }
    if (-not $matched) {
        # OpenWith's UIA point provider can incorrectly report the Settings page
        # behind its XAML popup. Native hit-testing must still hit the exact UIA
        # process, and that process must own the foreground picker.
        $foregroundProcess = [uint32]0
        [void][LDLCDefaultAppsNative]::GetWindowThreadProcessId([LDLCDefaultAppsNative]::GetForegroundWindow(), [ref]$foregroundProcess)
        if (-not (Test-LDLCDefaultAppsNativePickerHit -ProcessName $process.ProcessName -HitProcessId $processId -TargetProcessId $element.Current.ProcessId -ForegroundProcessId $foregroundProcess)) {
            throw "Cible UIA non confirmee sous la souris; aucun clic envoye : $($Control.Name)"
        }
    }
    [LDLCDefaultAppsNative]::ClickAt($point.X, $point.Y)
    Write-Info "[DEFAULT-APPS] Clic sur controle Windows observe : $($Control.Name)"
    return $true
}

function Test-LDLCDefaultAppsNativePickerHit {
    param([string]$ProcessName, [uint32]$HitProcessId, [uint32]$TargetProcessId, [uint32]$ForegroundProcessId)
    return ($ProcessName -eq 'OpenWith' -and $HitProcessId -ne 0 -and $HitProcessId -eq $TargetProcessId -and $HitProcessId -eq $ForegroundProcessId)
}

function Move-LDLCDefaultAppsScroll {
    param($Root, [switch]$Reset)
    $elements = $Root.FindAll([System.Windows.Automation.TreeScope]::Descendants,
        (New-Object System.Windows.Automation.PropertyCondition ([System.Windows.Automation.AutomationElement]::IsScrollPatternAvailableProperty), $true))
    foreach ($element in $elements) {
        $pattern = $null
        if ($element.TryGetCurrentPattern([System.Windows.Automation.ScrollPattern]::Pattern, [ref]$pattern) -and $pattern.Current.VerticallyScrollable) {
            if ($Reset) { $pattern.SetScrollPercent(-1, 0) }
            else { $pattern.Scroll([System.Windows.Automation.ScrollAmount]::NoAmount, [System.Windows.Automation.ScrollAmount]::LargeIncrement) }
            return $true
        }
    }
    return $false
}

function Invoke-LDLCDefaultAppsUiAction {
    param([ValidateSet('Association', 'Choice', 'Confirm', 'BrowserDefault')][string]$Kind, [string]$Association,
        [ValidateSet('Chrome', 'Adobe')][string]$Application, [int]$TimeoutMilliseconds = 15000)
    $tracking = @{ Error = ''; Scrolls = 0; Seen = '' }
    $result = Wait-LDLCDefaultAppsCondition -TimeoutMilliseconds $TimeoutMilliseconds -Probe {
        try {
            $windows = @(Get-LDLCDefaultAppsWindows | Sort-Object IsSettings)
            foreach ($window in $windows) {
                if ($Kind -in @('Association', 'BrowserDefault') -and -not $window.IsSettings) { continue }
                $root = Get-LDLCDefaultAppsRoot -Window $window
                if ($Kind -in @('Association', 'BrowserDefault')) { [void](Set-LDLCDefaultAppsFocus $window) }
                $pageRoot = $root
                if ($Kind -notin @('Association', 'BrowserDefault')) {
                    $root = Get-LDLCDefaultAppsPickerRoot -Window $window -Root $root -Association $Association
                    if (-not $root) {
                        $tracking.Seen = @((Get-LDLCDefaultAppsControls $pageRoot) | Where-Object { $_.Name -match 'acrobat|adobe|chrome|pdf|html|defaut|default|choisi|select' } | Select-Object -First 18 |
                            ForEach-Object { "$($_.ControlType):$($_.Name)" }) -join ' | '
                        continue
                    }
                }
                # Do not reactivate the Settings owner while its picker is open.
                # The scoped row is clicked only after native/UIA hit checks;
                # otherwise Invoke/Select remains available without global input.
                $controls = @(Get-LDLCDefaultAppsControls -Root $root)
                $tracking.Seen = @($controls | Where-Object { $_.Name -match 'acrobat|adobe|chrome|pdf|html|defaut|default|choisi|select' } | Select-Object -First 18 |
                    ForEach-Object { "$($_.ControlType):$($_.Name)" }) -join ' | '
                $control = if ($Kind -eq 'BrowserDefault') { Get-LDLCChromeBrowserDefaultControl -Root $root }
                    else { Select-LDLCDefaultAppsControl -Controls $controls -Kind $Kind -Association $Association -Application $Application }
                if ($control) {
                    if (Invoke-LDLCDefaultAppsControl -Control $control -Kind $Kind) { return $true }
                    if ($Kind -ne 'BrowserDefault') { return $false }
                }
                if ($Kind -eq 'BrowserDefault' -and $tracking.Scrolls -lt 3) {
                    [void](Move-LDLCDefaultAppsScroll -Root $root -Reset)
                    $tracking.Scrolls++
                }
                elseif ($Kind -ne 'Confirm' -and $Kind -ne 'BrowserDefault' -and $tracking.Scrolls -lt 16) {
                    [void](Move-LDLCDefaultAppsScroll -Root $root)
                    $tracking.Scrolls++
                }
            }
        }
        catch {
            if (Test-LDLCStopRequestError $_) { throw }
            $tracking.Error = $_.Exception.Message
        }
        return $false
    }
    if (-not $result) { throw "Controle $Kind introuvable/inactif pour $Application $Association apres ${TimeoutMilliseconds}ms. $($tracking.Error). UIA : $($tracking.Seen)" }
    return $true
}

function Open-LDLCDefaultAppPage {
    param([string]$Uri, [ValidateSet('Chrome', 'Adobe')][string]$Application)
    Ensure-LDLCDefaultAppsUiAutomation
    Close-LDLCDefaultAppsPage -ExistingDefaultPage
    Start-Process -FilePath $Uri -ErrorAction Stop
    $tracking = @{ Seen = '' }
    $ready = Wait-LDLCDefaultAppsCondition -TimeoutMilliseconds 20000 -Probe {
        try {
            foreach ($window in @(Get-LDLCDefaultAppsWindows | Where-Object IsSettings)) {
                [void](Set-LDLCDefaultAppsFocus $window)
                $root = Get-LDLCDefaultAppsRoot $window
                $controls = @(Get-LDLCDefaultAppsControls $root)
                $tracking.Seen = @($controls | Where-Object { $_.Name -match 'acrobat|adobe|chrome|pdf|html|defaut|default|choisi|select' } | Select-Object -First 18 |
                    ForEach-Object { "$($_.ControlType):$($_.Name)" }) -join ' | '
                $page = Select-LDLCDefaultAppsControl -Controls $controls -Kind Page -Application $Application
                if ($page) { $script:LDLCDefaultAppsOwnedPage = $window; [void](Move-LDLCDefaultAppsScroll -Root $root -Reset); return $true }
            }
        }
        catch { if (Test-LDLCStopRequestError $_) { throw } }
        return $false
    }
    if (-not $ready) { throw "Fiche $Application non exposee par UIA apres 20s (URI non prise en charge, focus ou Parametres lents) : $Uri. UIA : $($tracking.Seen)" }
}

function Close-LDLCDefaultAppsPage {
    param([switch]$ExistingDefaultPage)
    $owned = $script:LDLCDefaultAppsOwnedPage
    $script:LDLCDefaultAppsOwnedPage = $null
    if (-not $owned -and -not $ExistingDefaultPage) { return }
    foreach ($window in @(Get-LDLCDefaultAppsWindows | Where-Object IsSettings)) {
        try {
            if ($owned -and ($window.Handle -ne $owned.Handle -or $window.ProcessId -ne $owned.ProcessId)) { continue }
            if (-not $owned) {
                $controls = @(Get-LDLCDefaultAppsControls (Get-LDLCDefaultAppsRoot $window))
                $page = (Select-LDLCDefaultAppsControl $controls Page -Application Adobe) -or (Select-LDLCDefaultAppsControl $controls Page -Application Chrome)
                if (-not $page) { continue }
            }
            [void][LDLCDefaultAppsNative]::PostMessage($window.Handle, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
            Start-Sleep -Milliseconds 700
        } catch { Write-Info "[DEFAULT-APPS] Fermeture de la fiche non confirmee : $($_.Exception.Message)" }
    }
}

function Complete-LDLCDefaultAppsChoice {
    param([string]$Association, [ValidateSet('Chrome', 'Adobe')][string]$Application)
    $tracking = @{ LastConfirmation = ''; Actions = @{}; Count = 0; UiError = ''; Seen = '' }
    $confirmed = Wait-LDLCDefaultAppsCondition -TimeoutMilliseconds 12000 -Probe {
        if (Test-LDLCEffectiveAssociationTarget -State (Get-LDLCEffectiveAssociation $Association) -Application $Application) { return $true }
        try {
            foreach ($window in @(Get-LDLCDefaultAppsWindows | Sort-Object IsSettings)) {
                $root = Get-LDLCDefaultAppsPickerRoot -Window $window -Root (Get-LDLCDefaultAppsRoot $window) -Association $Association
                if (-not $root) { $tracking.UiError = 'Dialogue de confirmation non expose/scoped par UIA'; continue }
                $controls = @(Get-LDLCDefaultAppsControls $root)
                $tracking.Seen = @($controls | Where-Object { $_.Name -match 'acrobat|adobe|chrome|pdf|defaut|default|toujours|always|choisi|select|^ok$' } |
                    Select-Object -First 15 | ForEach-Object { "$($_.ControlType):$($_.Name) [Enabled=$($_.Enabled), Offscreen=$($_.Offscreen)]" }) -join ' | '
                $button = Select-LDLCDefaultAppsControl -Controls $controls -Kind Confirm -Application $Application
                if ($button -and $tracking.Count -lt 3) {
                    $identity = "$($window.Handle):$($button.Element.GetRuntimeId() -join '.'):$($button.Name)"
                    if ($tracking.Actions.ContainsKey($identity)) { continue }
                    if (Invoke-LDLCDefaultAppsControl -Control $button -Kind Confirm) {
                        $tracking.LastConfirmation = $button.Name
                        $tracking.Actions[$identity] = $true
                        $tracking.Count++
                        Set-LDLCDefaultAppsActionProgress -Application $Application -Association $Association -Stage Confirming
                    }
                }
            }
        }
        catch { if (Test-LDLCStopRequestError $_) { throw }; $tracking.UiError = $_.Exception.Message }
        return $false
    }
    if (-not $confirmed) { throw "Association $Association non appliquee par Windows apres selection $Application (confirmation='$($tracking.LastConfirmation)'). UIA : $($tracking.UiError). Controles observes : $($tracking.Seen)." }
}

function Invoke-LDLCDefaultAppAttempt {
    param([ValidateSet('Chrome', 'Adobe')][string]$Application, $State, [int]$Attempt, $Route)
    if (-not $Route) {
        $routes = @(Get-LDLCDefaultAppAttemptRoutes -Application $Application -State $State)
        if ($Attempt -lt 1 -or $Attempt -gt $routes.Count) { throw "Aucune nouvelle voie UIA disponible pour $Application." }
        $Route = $routes[$Attempt - 1]
    }
    $associations = if ($Application -eq 'Chrome') { @('.html') } else { @($State.Missing) }
    foreach ($association in $associations) {
        Stop-IfRequested
        # Recheck before acting: an earlier choice may have changed several associations.
        if (Test-LDLCEffectiveAssociationTarget -State (Get-LDLCEffectiveAssociation $association) -Application $Application) { continue }
        $stage = 'Page'
        try {
            if ($Route.Kind -ne 'Picker') {
                Set-LDLCDefaultAppsActionProgress -Application $Application -Association $association -Stage Opening
                Open-LDLCDefaultAppPage -Uri $Route.Uri -Application $Application
                $stage = 'Association'
                [void](Invoke-LDLCDefaultAppsUiAction -Kind Association -Association $association -Application $Application)
            }
            $stage = 'Choice'
            Set-LDLCDefaultAppsActionProgress -Application $Application -Association $association -Stage Selecting
            [void](Invoke-LDLCDefaultAppsUiAction -Kind Choice -Association $association -Application $Application)
            $stage = 'Confirm'
            Set-LDLCDefaultAppsActionProgress -Application $Application -Association $association -Stage Validating
            Complete-LDLCDefaultAppsChoice -Association $association -Application $Application
        }
        catch {
            $_.Exception.Data['DefaultAppsStage'] = $stage
            throw
        }
    }
    if ($Application -eq 'Chrome') {
        try {
            $uri = $Route.Uri
            if (-not $uri) { $uri = Get-LDLCDefaultAppUris Chrome | Select-Object -First 1 }
            if (-not $uri) { throw 'Fiche Google Chrome enregistree absente pour le bouton navigateur par defaut.' }
            Set-LDLCDefaultAppsActionProgress -Application Chrome -Association 'navigateur' -Stage Opening
            Open-LDLCDefaultAppPage -Uri $uri -Application Chrome
            Set-LDLCDefaultAppsActionProgress -Application Chrome -Association 'navigateur par defaut' -Stage Validating
            [void](Invoke-LDLCDefaultAppsUiAction -Kind BrowserDefault -Application Chrome)
            Set-LDLCDefaultAppsActionProgress -Application Chrome -Association 'navigateur par defaut' -Stage Confirming
        }
        catch {
            $_.Exception.Data['DefaultAppsStage'] = 'BrowserDefault'
            throw
        }
    }
}

function Test-LDLCDefaultAppsCompactUiAck {
    if (-not $script:LDLCDefaultAppsCompactPath -or -not $script:LDLCDefaultAppsCompactProgress) { return $false }
    try {
        $ack = [IO.File]::ReadAllText($script:LDLCDefaultAppsCompactPath + '.ack') | ConvertFrom-Json -ErrorAction Stop
        return ($ack.WorkerId -eq $PID -and $ack.Revision -eq $script:LDLCDefaultAppsCompactProgress.Revision)
    }
    catch { return $false }
}

function Set-LDLCDefaultAppsActionProgress {
    param([ValidateSet('Chrome', 'Adobe')][string]$Application, [string]$Association,
        [ValidateSet('Opening', 'Selecting', 'Validating', 'Confirming')][string]$Stage)
    $name = if ($Application -eq 'Adobe') { 'Adobe Acrobat Reader' } else { 'Chrome' }
    $action = switch ($Stage) {
        Opening { 'Ouverture des reglages' }
        Selecting { 'Selection' }
        Validating { 'Validation du choix' }
        Confirming { 'Confirmation du resultat' }
    }
    $suffix = if ($Association) { " ($Association)" } else { '' }
    $percent = 0; $failed = ''
    if ($script:LDLCDefaultAppsCompactProgress) {
        $percent = [int]$script:LDLCDefaultAppsCompactProgress.Progress
        $failed = [string]$script:LDLCDefaultAppsCompactProgress.ErrorApplication
    }
    Set-LDLCDefaultAppsCompactProgress -Percent $percent -Message "${action} : ${name}${suffix}..." -ErrorApplication $failed
}

function Set-LDLCDefaultAppsCompactProgress {
    param([ValidateRange(0,100)][int]$Percent, [string]$Message, [bool]$Running = $true,
        [bool]$Success = $false, [string]$ErrorApplication = '')
    if ($Percent -eq 100 -and -not $Success) { throw '100 pour cent exige les deux applications confirmees.' }
    $previous = $script:LDLCDefaultAppsCompactProgress
    if ($previous -and $previous.Progress -eq $Percent -and $previous.Message -eq $Message -and
        $previous.Running -eq $Running -and $previous.Success -eq $Success -and $previous.ErrorApplication -eq $ErrorApplication -and
        (-not $script:LDLCDefaultAppsCompactPath -or (Test-LDLCDefaultAppsCompactUiAck))) { return }
    $script:LDLCDefaultAppsCompactRevision = [long]$script:LDLCDefaultAppsCompactRevision + 1
    $script:LDLCDefaultAppsCompactProgress = [pscustomobject]@{
        WorkerId = $PID; Active = $true; Progress = $Percent; Message = $Message
        Running = $Running; Success = $Success; ErrorApplication = $ErrorApplication; Revision = $script:LDLCDefaultAppsCompactRevision
    }
    if (-not $script:LDLCDefaultAppsCompactPath) { return }
    $path = $script:LDLCDefaultAppsCompactPath
    $temporary = $path + '.tmp'
    try {
        [IO.File]::WriteAllText($temporary, ($script:LDLCDefaultAppsCompactProgress | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding($false)))
        for ($retry = 0; $retry -lt 6; $retry++) {
            try {
                if (Test-Path -LiteralPath $path) { [IO.File]::Replace($temporary, $path, [NullString]::Value) }
                else { [IO.File]::Move($temporary, $path) }
                break
            }
            catch [IO.IOException] {
                if ($retry -eq 5) { throw }
                Start-Sleep -Milliseconds 25
            }
        }
    }
    catch { Write-Info "[DEFAULT-APPS] Signal de progression indisponible : $($_.Exception.Message)" }
    finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue } }
    if ($env:LDLC_DEFAULT_APPS_UI -eq '1') {
        # Wait for this exact message to be painted, not an old 'window visible' flag.
        $ack = Wait-LDLCDefaultAppsCondition -TimeoutMilliseconds 2500 -PollMilliseconds 50 -Probe { Test-LDLCDefaultAppsCompactUiAck }
        if ($ack) { Write-Info "[DEFAULT-APPS][UI] Affichage confirme r$($script:LDLCDefaultAppsCompactRevision) : $Percent% $Message" }
        else { Write-Info "[DEFAULT-APPS][UI] Message non acquitte r$($script:LDLCDefaultAppsCompactRevision); clic physique desactive : $Message" }
    }
}

function Enter-LDLCDefaultAppsCompact {
    if ($script:LDLCDefaultAppsCompactDepth -gt 0) { $script:LDLCDefaultAppsCompactDepth++; return }
    $script:LDLCDefaultAppsCompactDepth = 1
    $script:LDLCDefaultAppsCompactPath = $null
    $script:LDLCDefaultAppsCompactProgress = $null
    if ([string]::IsNullOrWhiteSpace($script:ProgressFile)) { return }
    $path = Join-Path (Split-Path -Parent $script:ProgressFile) "LDLC_DEFAULT_APPS.$PID.json"
    $script:LDLCDefaultAppsCompactPath = $path
    try {
        Remove-Item -LiteralPath ($path + '.ack') -Force -ErrorAction SilentlyContinue
        Set-LDLCDefaultAppsCompactProgress -Percent 0 -Message "Configuration d'Adobe Acrobat Reader..."
    }
    catch {
        if (Test-LDLCStopRequestError $_) { throw }
        Write-Info "[DEFAULT-APPS] Signal UI compacte indisponible : $($_.Exception.Message)"
    }
}

function Exit-LDLCDefaultAppsCompact {
    $script:LDLCDefaultAppsCompactDepth = [math]::Max(0, $script:LDLCDefaultAppsCompactDepth - 1)
    if ($script:LDLCDefaultAppsCompactDepth -gt 0) { return }
    if ($script:LDLCDefaultAppsCompactPath) {
        Remove-Item -LiteralPath $script:LDLCDefaultAppsCompactPath -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath ($script:LDLCDefaultAppsCompactPath + '.ack') -Force -ErrorAction SilentlyContinue
        $script:LDLCDefaultAppsCompactPath = $null
    }
}

function Invoke-LDLCDefaultAppConfiguration {
    param([ValidateSet('Chrome', 'Adobe')][string]$Application, [ValidateRange(1, 3)][int]$MaxAttempts = 3)
    $errors = New-Object 'Collections.Generic.List[string]'
    $verification = $null
    $attempt = 0
    try {
        Enter-LDLCDefaultAppsCompact
        Set-LDLCDefaultAppsActionProgress -Application $Application -Stage Confirming
        Write-Step "[DEFAULT-APPS] Verification effective $Application, puis correction si necessaire."
        $state = Get-LDLCDefaultAppState -Application $Application
        $routes = @()
        if (-not $state.Confirmed) { $routes = @(Get-LDLCDefaultAppAttemptRoutes -Application $Application -State $state | Select-Object -First $MaxAttempts) }
        if (-not $state.Confirmed -and -not $routes.Count) {
            $errors.Add('Aucun selecteur present ni fiche RegisteredApplications compatible. Verifier installation/integration Windows.')
        }
        do {
            Stop-IfRequested
            $state = Get-LDLCDefaultAppState -Application $Application
            $stage = ''
            if (-not $state.Confirmed -and $attempt -lt $routes.Count) {
                $route = $routes[$attempt]
                $attempt++
                try { Invoke-LDLCDefaultAppAttempt -Application $Application -State $state -Attempt $attempt -Route $route }
                catch {
                    if (Test-LDLCStopRequestError $_) { throw }
                    $stage = [string]$_.Exception.Data['DefaultAppsStage']
                    $errors.Add("Tentative ${attempt} ($($route.Kind) $($route.Uri), etape=$stage): $($_.Exception.Message)")
                }
            }
            Set-LDLCDefaultAppsActionProgress -Application $Application -Stage Confirming
            $verification = Wait-LDLCDefaultAppConfirmation -Application $Application -TimeoutMilliseconds 12000
            if ($verification.Confirmed) {
                Write-Ok "[DEFAULT-APPS] $Application confirme par Windows : $($verification.State.Associations.Association -join ', ')."
                return $true
            }
            $before = @($state.Associations | ForEach-Object { "$($_.Association)|$($_.ProgId)|$($_.Executable)|$($_.Error)" }) -join ';'
            $after = @($verification.State.Associations | ForEach-Object { "$($_.Association)|$($_.ProgId)|$($_.Executable)|$($_.Error)" }) -join ';'
            if ($before -eq $after -and $stage -in @('Association', 'Choice', 'Confirm', 'BrowserDefault')) {
                $errors.Add("Arret sans repetition : etape $stage en echec, associations inchangees apres stabilisation.")
                break
            }
            if ($attempt -lt $routes.Count) { Write-Info "[DEFAULT-APPS] $Application non confirme; autre voie enregistree $($attempt + 1)/$($routes.Count), sans reutiliser la precedente." }
        } while ($attempt -lt $routes.Count)
        $details = @($verification.State.Associations | ForEach-Object {
            "$($_.Association)=$($_.ProgId) [$($_.Executable)] erreur='$($_.Error)'"
        }) -join '; '
        Write-Warn "[DEFAULT-APPS] $Application non confirme apres $attempt tentative(s) distincte(s). Manquants : $($verification.State.Missing -join ', '). $details. $($errors -join ' | '). Corriger dans Parametres > Applications > Applications par defaut."
        return $false
    }
    catch {
        if (Test-LDLCStopRequestError $_) { throw }
        Write-Warn "[DEFAULT-APPS] Verification $Application interrompue, resultat non confirme : $($_.Exception.Message). Controle manuel necessaire."
        return $false
    }
    finally { Close-LDLCDefaultAppsPage; Exit-LDLCDefaultAppsCompact }
}

function Set-LDLCChromeDefaultBrowserWithUiAutomation {
    return Invoke-LDLCDefaultAppConfiguration -Application Chrome
}

function Set-LDLCAdobePdfDefaultWithUiAutomation {
    return Invoke-LDLCDefaultAppConfiguration -Application Adobe
}

function Get-LDLCTaskbarAdvancedValue {
    param([Parameter(Mandatory = $true)][string]$Name)

    $path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    try {
        $item = Get-ItemProperty -Path $path -Name $Name -ErrorAction Stop
        return [int]$item.$Name
    }
    catch {
        return $null
    }
}

function Set-LDLCTaskbarAdvancedValue {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][int]$Value
    )

    $path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    if (-not (Test-Path -LiteralPath $path)) {
        New-Item -Path $path -Force -ErrorAction Stop | Out-Null
    }
    New-ItemProperty -Path $path -Name $Name -Value $Value -PropertyType DWord -Force -ErrorAction Stop | Out-Null
}

function Get-LDLCTaskbarPolicyValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name
    )

    try {
        $item = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
        return [int]$item.$Name
    }
    catch {
        return $null
    }
}

function Set-LDLCTaskbarPolicyValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][int]$Value
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
    }

    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType DWord -Force -ErrorAction Stop | Out-Null
}

function Get-LDLCWidgetsTaskbarState {
    $taskbarDa = Get-LDLCTaskbarAdvancedValue -Name 'TaskbarDa'
    $taskbarMn = Get-LDLCTaskbarAdvancedValue -Name 'TaskbarMn'
    $policyPaths = @(
        'HKCU:\Software\Policies\Microsoft\Dsh',
        'HKLM:\SOFTWARE\Policies\Microsoft\Dsh',
        'HKCU:\Software\Policies\Microsoft\Windows\Windows Feeds',
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds'
    )

    $policyValues = @{}
    foreach ($policyPath in $policyPaths) {
        foreach ($policyName in @('AllowNewsAndInterests', 'AllowWidgets', 'EnableFeeds')) {
            $policyValues["$policyPath\$policyName"] = Get-LDLCTaskbarPolicyValue -Path $policyPath -Name $policyName
        }
    }

    $disabledByPolicy = ($policyValues.Values | Where-Object { $null -ne $_ -and [int]$_ -eq 0 }).Count -gt 0
    $disabledByUserValue = ($null -ne $taskbarDa -and [int]$taskbarDa -eq 0)

    return [pscustomobject]@{
        Disabled = [bool]$disabledByUserValue
        TaskbarDa = $taskbarDa
        TaskbarMn = $taskbarMn
        PolicyDisabled = [bool]$disabledByPolicy
        PolicyValues = $policyValues
    }
}

function Disable-LDLCTaskbarOption {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][string]$SuccessLog
    )

    $currentValue = Get-LDLCTaskbarAdvancedValue -Name $Name
    if ($null -ne $currentValue -and $currentValue -eq 0) {
        Write-Ok "$SuccessLog deja desactivee"
        return $false
    }

    Set-LDLCTaskbarAdvancedValue -Name $Name -Value 0
    Start-Sleep -Milliseconds 150

    $verifiedValue = Get-LDLCTaskbarAdvancedValue -Name $Name
    if ($null -eq $verifiedValue -or $verifiedValue -ne 0) {
        Write-Warn "[TASKBAR][ERREUR] Option $Label introuvable ou non verifiee"
        return $false
    }

    Write-Ok $SuccessLog
    return $true
}

function Disable-LDLCWidgetsTaskbarOption {
    $initialState = Get-LDLCWidgetsTaskbarState
    if ($initialState.Disabled) {
        Write-Ok "[TASKBAR] Widgets deja desactives"
        return $false
    }

    $attemptErrors = New-Object System.Collections.Generic.List[string]

    try {
        Set-LDLCTaskbarAdvancedValue -Name 'TaskbarDa' -Value 0
        Start-Sleep -Milliseconds 150

        if ((Get-LDLCWidgetsTaskbarState).Disabled) {
            Write-Ok "[TASKBAR] Widgets desactives"
            return $true
        }
    }
    catch {
        [void]$attemptErrors.Add("TaskbarDa: $($_.Exception.Message)")
        Write-Info "[TASKBAR] Modification directe de Widgets non autorisee, tentative via strategie policy."
    }

    foreach ($policyPath in @(
        'HKCU:\Software\Policies\Microsoft\Dsh',
        'HKLM:\SOFTWARE\Policies\Microsoft\Dsh',
        'HKCU:\Software\Policies\Microsoft\Windows\Windows Feeds',
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds'
    )) {
        foreach ($policyName in @('AllowNewsAndInterests', 'AllowWidgets', 'EnableFeeds')) {
            try {
                Set-LDLCTaskbarPolicyValue -Path $policyPath -Name $policyName -Value 0
                Set-LDLCTaskbarAdvancedValue -Name 'TaskbarDa' -Value 0
                Start-Sleep -Milliseconds 150

                if ((Get-LDLCWidgetsTaskbarState).Disabled) {
                    Write-Ok "[TASKBAR] Widgets desactives"
                    return $true
                }
            }
            catch {
                [void]$attemptErrors.Add("${policyPath}\${policyName}: $($_.Exception.Message)")
            }
        }
    }

    $finalState = Get-LDLCWidgetsTaskbarState
    if ($finalState.Disabled) {
        Write-Ok "[TASKBAR] Widgets desactives apres verification finale"
        return $true
    }

    $details = (($attemptErrors | ForEach-Object { [string]$_ }) -join ' | ')
    if ([string]::IsNullOrWhiteSpace($details)) {
        $details = "TaskbarDa=$($finalState.TaskbarDa); PolicyDisabled=$($finalState.PolicyDisabled)"
    }

    Write-Warn "[TASKBAR][ERREUR] Impossible de desactiver Widgets apres verification finale. $details"
    return $false
}

function Set-LDLCTaskbarOptionsWithRegistry {
    Write-Step "[TASKBAR] Configuration de la barre des taches"

    $changed = $false
    if (Disable-LDLCTaskbarOption -Name 'ShowTaskViewButton' -Label 'Vue des taches' -SuccessLog '[TASKBAR] Vue des taches desactivee') {
        $changed = $true
    }

    if (Disable-LDLCWidgetsTaskbarOption) {
        $changed = $true
    }

    if ($changed) {
        try {
            Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force -Confirm:$false -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 800
            Start-Process explorer
            Start-Sleep -Milliseconds 1400
            Close-LDLCExplorerFileWindows
            Write-Info "[TASKBAR] Explorer relance pour appliquer les options."
        }
        catch {
            Write-Warn "[TASKBAR] Relance Explorer impossible : $($_.Exception.Message)"
        }
    }

    $taskViewOk = ((Get-LDLCTaskbarAdvancedValue -Name 'ShowTaskViewButton') -eq 0)
    $widgetsOk = (Get-LDLCWidgetsTaskbarState).Disabled
    if ($taskViewOk -and $widgetsOk) {
        Write-Ok "[TASKBAR] Configuration de la barre des taches terminee"
        return $true
    }

    return $false
}

function Invoke-LDLCChromeDefaultAppsSequence {
    Write-Section "APPLICATIONS PAR DEFAUT"

    try {
        Enter-LDLCDefaultAppsCompact
        Set-LDLCDefaultAppsCompactProgress -Percent 0 -Message "Configuration d'Adobe Acrobat Reader..."
        $adobeConfirmed = Set-LDLCAdobePdfDefaultWithUiAutomation
        if ($adobeConfirmed) {
            Set-LDLCDefaultAppsCompactProgress -Percent 50 -Message 'Configuration de Chrome...'
        }
        else {
            Set-LDLCDefaultAppsCompactProgress -Percent 0 -Message "Adobe Acrobat Reader non confirme. Configuration de Chrome..." -ErrorApplication 'Adobe Acrobat Reader (.pdf)'
        }
        $chromeConfirmed = Set-LDLCChromeDefaultBrowserWithUiAutomation
        # La seconde configuration peut modifier des associations communes.
        $chromeVerification = Wait-LDLCDefaultAppConfirmation -Application Chrome
        $adobeVerification = Wait-LDLCDefaultAppConfirmation -Application Adobe
        $chromeFinal = $chromeVerification.State
        $adobeFinal = $adobeVerification.State
        if ($chromeVerification.Confirmed -and $adobeVerification.Confirmed) {
            Set-LDLCDefaultAppsCompactProgress -Percent 100 -Message 'Configuration terminee' -Running $false -Success $true
            Write-Ok 'Applications par defaut configurees avec succes'
        }
        else {
            if ($chromeConfirmed -and -not $chromeFinal.Confirmed) { Write-Warn "Chrome n'a pas pu etre confirme comme navigateur par defaut lors du controle final : $($chromeFinal.Missing -join ', ')." }
            if ($adobeConfirmed -and -not $adobeFinal.Confirmed) { Write-Warn "Adobe Reader n'a pas pu etre confirme comme application PDF par defaut lors du controle final." }
            $failed = @()
            if (-not $adobeVerification.Confirmed) { $failed += 'Adobe Acrobat Reader (.pdf)' }
            if (-not $chromeVerification.Confirmed) { $failed += "Chrome ($($chromeFinal.Missing -join ', '))" }
            $completed = [int][bool]$adobeVerification.Confirmed + [int][bool]$chromeVerification.Confirmed
            Set-LDLCDefaultAppsCompactProgress -Percent ($completed * 50) -Message 'Configuration non confirmee' -Running $false -ErrorApplication ($failed -join ' ; ')
        }
        # Give the independent UI process time to show the verified final state.
        [void](Wait-LDLCDefaultAppsCondition -TimeoutMilliseconds 1400 -Probe { $false })
    }
    finally { Exit-LDLCDefaultAppsCompact }

    try {
        [void](Set-LDLCTaskbarOptionsWithRegistry)
    }
    catch {
        if (Test-LDLCStopRequestError $_) { throw }
        Write-Warn "[TASKBAR][ERREUR] Configuration barre des taches : $($_.Exception.Message)"
    }
}

function Get-LDLCChromeExecutablePath {
    $candidates = @(
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "$env:LocalAppData\Google\Chrome\Application\chrome.exe"
    )

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path $candidate)) {
            return $candidate
        }
    }

    return $null
}

function Close-LDLCExplorerFileWindows {
    param(
        [int]$TimeoutSeconds = 6
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

    do {
        $closedCount = 0

        try {
            $shell = New-Object -ComObject Shell.Application
            foreach ($window in @($shell.Windows())) {
                try {
                    $fullName = [string]$window.FullName
                    if ((Split-Path -Path $fullName -Leaf) -ieq 'explorer.exe') {
                        $window.Quit()
                        $closedCount++
                    }
                }
                catch {
                }
            }
        }
        catch {
            Write-Warn "Impossible de fermer les fenetres Explorer : $($_.Exception.Message)"
            return
        }

        if ($closedCount -le 0) {
            return
        }

        Write-Info "$closedCount fenetre(s) Explorer fermee(s) apres relance."
        Start-Sleep -Milliseconds 500
    }
    while ((Get-Date) -lt $deadline)
}

function Invoke-LDLCChromeTaskbarPinBeforeWindowsUpdate {
    param(
        [int]$ProgressPercent = 90
    )

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
        Write-Warn "Impossible de preparer le layout taskbar Chrome : $($_.Exception.Message)"
        return $false
    }

    Write-ProgressFile $ProgressPercent "Epinglage de Chrome a la barre des taches..."

    try {
        Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force -Confirm:$false -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 1000
        Start-Process explorer
        Start-Sleep -Milliseconds 1800
        Close-LDLCExplorerFileWindows
        Write-Info "Relance Explorer effectuee sans fenetre Accueil."
    }
    catch {
        Write-Warn "Relance Explorer impossible : $($_.Exception.Message)"
    }

    return $true
}

# endregion Module: 70.DefaultApps.ps1
