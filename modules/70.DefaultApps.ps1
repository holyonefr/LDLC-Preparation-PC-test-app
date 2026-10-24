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
        // ASSOCSTR_PROGID reads the effective Windows association without creating
        // a COM server for every poll. Keep COM as a compatibility fallback.
        try { return AssociationString(association, 20, 0x100u | (association.StartsWith(".") ? 0u : 0x1000u)); }
        catch (Exception) { }
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
        return AssociationString(association, 2, flags);
    }
    public static string ExecutableForProgId(string progId) {
        // Use only a ProgID already reported by Windows, never a guessed registry value.
        return AssociationString(progId, 2, 0x100u | 0x800u);
    }
    private static string AssociationString(string association, uint kind, uint flags) {
        uint count = 0;
        string extra = kind == 2 ? "open" : null;
        int hr = AssocQueryStringW(flags, kind, association, extra, null, ref count);
        if (hr < 0) Marshal.ThrowExceptionForHR(hr);
        if (count == 0 || count > 32768) throw new InvalidOperationException("Executable non resolu");
        StringBuilder text = new StringBuilder((int)count);
        Marshal.ThrowExceptionForHR(AssocQueryStringW(flags, kind, association, extra, text, ref count));
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
        try { $executable = [LDLCDefaultAppsNative]::Executable($Association) }
        catch { $executable = [LDLCDefaultAppsNative]::ExecutableForProgId($progId) }
        $executable = [Environment]::ExpandEnvironmentVariables($executable.Trim().Trim('"'))
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
        return (($State.ProgId -match '^ChromeHTML(?:\.|$)' -or $State.ProgId -ieq 'Applications\chrome.exe') -and $fileName -ieq 'chrome.exe')
    }
    if ($fileName -notin @('Acrobat.exe', 'AcroRd32.exe')) { return $false }
    if ($State.ProgId -match '^(Acrobat|AcroExch)\.Document(?:\.|$)' -or
        $State.ProgId -match '^Applications\\(?:Acrobat|AcroRd32)\.exe$') { return $true }
    # Adobe's registered PDF ProgID can change with its edition/package. The
    # effective executable must still be its PDF reader, not a registered app alone.
    return ($State.ProgId -in @(Get-LDLCRegisteredPdfProgIds -Application Adobe))
}

function Get-LDLCRegisteredPdfProgIds {
    param([ValidateSet('Adobe')][string]$Application = 'Adobe')
    $ids = New-Object 'Collections.Generic.List[string]'
    foreach ($hive in @([Microsoft.Win32.RegistryHive]::CurrentUser, [Microsoft.Win32.RegistryHive]::LocalMachine)) {
        foreach ($view in @([Microsoft.Win32.RegistryView]::Registry64, [Microsoft.Win32.RegistryView]::Registry32)) {
            $base = $null; $registered = $null; $capabilities = $null
            try {
                $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey($hive, $view)
                $registered = $base.OpenSubKey('Software\RegisteredApplications')
                if (-not $registered) { continue }
                foreach ($name in $registered.GetValueNames()) {
                    if (-not (Test-LDLCDefaultAppsApplicationName -Name $name -Application Adobe -RegisteredName)) { continue }
                    try {
                        $path = [string]$registered.GetValue($name)
                        if (-not $path) { continue }
                        $capabilities = $base.OpenSubKey($path.TrimEnd('\') + '\FileAssociations')
                        if ($capabilities) {
                            $id = [string]$capabilities.GetValue('.pdf')
                            if ($id -and -not $ids.Contains($id)) { $ids.Add($id) }
                        }
                    } finally { if ($capabilities) { $capabilities.Dispose(); $capabilities = $null } }
                }
            } catch { Write-Verbose ('Adobe PDF registration unavailable in ' + $hive + '/' + $view) }
            finally { if ($registered) { $registered.Dispose() }; if ($base) { $base.Dispose() } }
        }
    }
    return $ids.ToArray()
}

function Set-LDLCDefaultAppsDeferredDetail {
    param([ValidateSet('Chrome','Adobe','Widgets')][string]$Application, [string]$Detail)
    if (-not $script:LDLCDefaultAppsDeferredDetails) { $script:LDLCDefaultAppsDeferredDetails = @{} }
    $script:LDLCDefaultAppsDeferredDetails[$Application] = $Detail
}

function Confirm-LDLCDefaultAppsFinalState {
    # Read-only final audit. A failed UI attempt is not a final configuration error.
    # Do not touch unrelated errors, earlier runs, settings, UserChoice or its hash.
    if (-not $script:LDLCDefaultAppsPendingChecks -or $script:LDLCDefaultAppsFinalAuditDone) { return }
    Write-Section 'VERIFICATION FINALE DES APPLICATIONS PAR DEFAUT'
    $states = [ordered]@{}; $failures = New-Object 'Collections.Generic.List[string]'
    foreach ($application in @('Adobe','Chrome','Widgets')) {
        if (-not $script:LDLCDefaultAppsPendingChecks.ContainsKey($application)) { continue }
        Stop-IfRequested
        try {
            if ($application -eq 'Widgets') {
                $state = Get-LDLCWidgetsTaskbarState
                $states[$application] = $state
                if ($state.Disabled) { Write-Info '[FINAL-CHECK] Widgets desactives : etat Windows confirme.'; continue }
                # User-requested cosmetic option: keep the real observed state
                # in diagnostics, but it no longer blocks intervention validation.
                Write-Info ('[FINAL-CHECK] Widgets : desactivation non confirmee (TaskbarDa=' + $state.TaskbarDa + '; strategie reconnue=' + $state.PolicyDisabled + '). Information uniquement.')
                continue
            } else {
                $verification = Wait-LDLCDefaultAppConfirmation -Application $application -TimeoutMilliseconds 1000
                $states[$application] = $verification.State
                if ($verification.Confirmed) { Write-Info ('[FINAL-CHECK] ' + $application + ' confirme par Windows ; aucune alerte de tentative conservee.'); continue }
                $details = @($verification.State.Associations | ForEach-Object { $_.Association + '=' + $_.ProgId + ' [' + $_.Executable + '] ' + $_.Error }) -join '; '
                $failure = '[DEFAULT-APPS] ' + $application + ' : configuration finale non confirmee. ' + $details
            }
        } catch {
            if (Test-LDLCStopRequestError $_) { throw }
            if ($application -eq 'Widgets') { Write-Info ('[FINAL-CHECK] Widgets : verification indisponible. ' + $_.Exception.Message); continue }
            $failure = '[FINAL-CHECK] Verification ' + $application + ' impossible : ' + $_.Exception.Message
        }
        $failures.Add($failure); Write-Warn $failure
    }
    $script:LDLCDefaultAppsFinalAuditDone = $true
    return [pscustomobject]@{ Confirmed = ($failures.Count -eq 0); States = [pscustomobject]$states; Failures = $failures.ToArray() }
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
    if ($Application -eq 'Chrome' -and -not $PSBoundParameters.ContainsKey('TimeoutMilliseconds')) { $TimeoutMilliseconds = 6000 }
    # Two independent readings avoid accepting a transient association during a reset.
    $tracking = @{ Last = $null; Consecutive = 0 }
    $confirmed = Wait-LDLCDefaultAppsCondition -TimeoutMilliseconds $TimeoutMilliseconds -PollMilliseconds 250 -Probe {
        $tracking.Last = Get-LDLCDefaultAppState -Application $Application
        if ($tracking.Last.Confirmed) { $tracking.Consecutive++ } else { $tracking.Consecutive = 0 }
        return ($tracking.Consecutive -ge 2)
    }
    return [pscustomobject]@{ Confirmed = [bool]$confirmed; State = $tracking.Last }
}

function Wait-LDLCChromeDefaultBrowserConfirmation {
    param([int]$TimeoutSeconds = 6)
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
    # UIA can expose aliases of one XAML button. Count native identities, not
    # aliases, while still refusing two genuinely different browser actions.
    $unique = @{}
    foreach ($control in @($controls | Where-Object { $_.Enabled -and $_.ControlType -eq 'ControlType.Button' -and
        (Test-LDLCChromeBrowserDefaultLabel -Name $_.Name -WithAction) } | Sort-Object Offscreen)) {
        $identity = $control.Element.GetRuntimeId() -join '.'
        if (-not $unique.ContainsKey($identity)) { $unique[$identity] = $control }
    }
    $qualified = @($unique.Values)
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
    try {
        if (Invoke-LDLCDefaultAppsObservedClick -Control $Control) { return $true }
    } catch {
        if (Test-LDLCStopRequestError $_) { throw }
        # The compact preparation window can cover a Settings card. Never click
        # through it: use the exact observed control's accessibility pattern.
        Write-Info ('[DEFAULT-APPS] Clic physique indisponible ; activation du controle UIA observe : ' + $_.Exception.Message)
    }
    $pattern = $null
    if ($Kind -eq 'Choice' -and $element.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$pattern)) {
        $pattern.Select()
        if (-not $pattern.Current.IsSelected) { throw "Ligne non selectionnee par Windows : $($Control.Name)" }
        return $true
    }
    if ($element.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$pattern)) {
        $pattern.Invoke()
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
        [ValidateSet('Chrome', 'Adobe')][string]$Application, [int]$TimeoutMilliseconds = 15000, [switch]$ObservedBrowserClick)
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
                    $activated = if ($Kind -eq 'BrowserDefault' -and $ObservedBrowserClick) {
                        if ($control.Offscreen -or -not $control.Element.Current.IsEnabled -or $control.Element.Current.IsOffscreen) { $false }
                        else { Invoke-LDLCDefaultAppsObservedClick -Control $control }
                    }
                        else { Invoke-LDLCDefaultAppsControl -Control $control -Kind $Kind }
                    if ($activated) { return $true }
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
    param([string]$Association, [ValidateSet('Chrome', 'Adobe')][string]$Application, [int]$TimeoutMilliseconds = 12000)
    $tracking = @{ LastConfirmation = ''; Actions = @{}; Count = 0; UiError = ''; Seen = '' }
    $confirmed = Wait-LDLCDefaultAppsCondition -TimeoutMilliseconds $TimeoutMilliseconds -Probe {
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

function Invoke-LDLCChromeBrowserDefaultAction {
    # Restore UIA Invoke first: the guarded physical click can be unavailable
    # even when Windows exposes a working, accessible Set default action.
    [void](Invoke-LDLCDefaultAppsUiAction -Kind BrowserDefault -Application Chrome -TimeoutMilliseconds 5000)
    $verification = Wait-LDLCDefaultAppConfirmation -Application Chrome -TimeoutMilliseconds 750
    if (-not $verification.Confirmed) {
        try { [void](Invoke-LDLCDefaultAppsUiAction -Kind BrowserDefault -Application Chrome -TimeoutMilliseconds 1000 -ObservedBrowserClick) }
        catch { if (Test-LDLCStopRequestError $_) { throw }; Write-Info '[DEFAULT-APPS] Clic observe indisponible ; verification du resultat Windows.' }
        $verification = Wait-LDLCDefaultAppConfirmation -Application Chrome -TimeoutMilliseconds 1000
    }
    return [pscustomobject]@{ BrowserActionInvoked = $true; Confirmed = $verification.Confirmed }
}

function Invoke-LDLCDefaultAppAttempt {
    param([ValidateSet('Chrome', 'Adobe')][string]$Application, $State, [int]$Attempt, $Route)
    if (-not $Route) {
        $routes = @(Get-LDLCDefaultAppAttemptRoutes -Application $Application -State $State)
        if ($Attempt -lt 1 -or $Attempt -gt $routes.Count) { throw "Aucune nouvelle voie UIA disponible pour $Application." }
        $Route = $routes[$Attempt - 1]
    }
    if ($Application -eq 'Chrome' -and $Route.Kind -ne 'Picker') {
        # Windows 11's browser-wide action first; do not spend time in the HTML
        # chooser before attempting the exact "Set default" browser button.
        try {
            Set-LDLCDefaultAppsActionProgress -Application Chrome -Association 'navigateur' -Stage Opening
            Open-LDLCDefaultAppPage -Uri $Route.Uri -Application Chrome
            Set-LDLCDefaultAppsActionProgress -Application Chrome -Association 'navigateur par defaut' -Stage Validating
            $browserAction = Invoke-LDLCChromeBrowserDefaultAction
            if ($browserAction.Confirmed) { return $browserAction }
            Write-Info '[DEFAULT-APPS] Bouton transmis sans changement effectif ; utilisation des associations Windows enregistrees.'
        }
        catch {
            if (Test-LDLCStopRequestError $_) { throw }
            if ((Get-LDLCDefaultAppState Chrome).Confirmed) { return }
            Write-Info ('[DEFAULT-APPS] Action navigateur non disponible ; essai du selecteur HTML enregistre : ' + $_.Exception.Message)
        }
    }
    # Windows 10 and older Windows 11 pages may not have a browser-wide button.
    # HTML alone does not configure HTTP, HTTPS and HTM.
    $associations = @($State.Missing)
    $associationErrors = New-Object 'Collections.Generic.List[string]'
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
            if ($Application -eq 'Chrome') {
                Complete-LDLCDefaultAppsChoice -Association $association -Application Chrome -TimeoutMilliseconds 4000
            } else { Complete-LDLCDefaultAppsChoice -Association $association -Application $Application }
        }
        catch {
            if (Test-LDLCStopRequestError $_) { throw }
            $_.Exception.Data['DefaultAppsStage'] = $stage
            if ($Application -eq 'Chrome') {
                # A slow HTTP commit must not skip HTM/HTML. Each next action
                # reopens its own observed page and rechecks the actual handler.
                $associationErrors.Add($association + ' (' + $stage + ') : ' + $_.Exception.Message)
                Write-Info ('[DEFAULT-APPS] Tentative ' + $association + ' non confirmee ; poursuite des autres associations Windows.')
                continue
            }
            throw
        }
    }
    if ($Application -eq 'Chrome') {
        if ((Get-LDLCDefaultAppState Chrome).Confirmed) { return [pscustomobject]@{ BrowserActionInvoked=$false; Confirmed=$true } }
        if ($associationErrors.Count) {
            $failure = New-Object InvalidOperationException ('Associations Chrome restantes : ' + ($associationErrors -join ' | '))
            $failure.Data['DefaultAppsStage'] = 'Confirm'
            throw $failure
        }
        try {
            $uri = $Route.Uri
            if (-not $uri) { $uri = Get-LDLCDefaultAppUris Chrome | Select-Object -First 1 }
            if (-not $uri) { throw 'Fiche Google Chrome enregistree absente pour le bouton navigateur par defaut.' }
            Set-LDLCDefaultAppsActionProgress -Application Chrome -Association 'navigateur' -Stage Opening
            Open-LDLCDefaultAppPage -Uri $uri -Application Chrome
            Set-LDLCDefaultAppsActionProgress -Application Chrome -Association 'navigateur par defaut' -Stage Validating
            $action = Invoke-LDLCChromeBrowserDefaultAction
            return $action
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
    if ($Percent -eq 100 -and -not $Success) { throw '100 pour cent exige le traitement termine sans erreur.' }
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
    param([ValidateSet('Chrome', 'Adobe')][string]$Application, [ValidateRange(1, 3)][int]$MaxAttempts = 3, [switch]$DeferFailureWarning)
    if ($Application -eq 'Chrome') { return Set-LDLCChromeDefaultBrowserWithUiAutomation -MaxAttempts $MaxAttempts -DeferFailureWarning:$DeferFailureWarning }
    $errors = New-Object 'Collections.Generic.List[string]'
    $verification = $null
    $attempt = 0
    $entered = $false
    try {
        Stop-IfRequested
        if ((Get-LDLCDefaultAppState -Application $Application).Confirmed) {
            $verification = Wait-LDLCDefaultAppConfirmation -Application $Application -TimeoutMilliseconds 1000
            if ($verification.Confirmed) {
                Write-Ok "[DEFAULT-APPS] $Application deja confirme par Windows ; aucune action necessaire."
                return $true
            }
        }
        $entered = $true
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
            $actionResult = $null
            if (-not $state.Confirmed -and $attempt -lt $routes.Count) {
                $route = $routes[$attempt]
                $attempt++
                try { $actionResult = Invoke-LDLCDefaultAppAttempt -Application $Application -State $state -Attempt $attempt -Route $route }
                catch {
                    if (Test-LDLCStopRequestError $_) { throw }
                    $stage = [string]$_.Exception.Data['DefaultAppsStage']
                    $errors.Add("Tentative ${attempt} ($($route.Kind) $($route.Uri), etape=$stage): $($_.Exception.Message)")
                }
            }
            Set-LDLCDefaultAppsActionProgress -Application $Application -Stage Confirming
            $confirmationBudget = if ($Application -eq 'Chrome') { 6000 } else { 12000 }
            $verification = Wait-LDLCDefaultAppConfirmation -Application $Application -TimeoutMilliseconds $confirmationBudget
            if ($verification.Confirmed) {
                Write-Ok "[DEFAULT-APPS] $Application confirme par Windows : $($verification.State.Associations.Association -join ', ')."
                return $true
            }
            $before = @($state.Associations | ForEach-Object { "$($_.Association)|$($_.ProgId)|$($_.Executable)|$($_.Error)" }) -join ';'
            $after = @($verification.State.Associations | ForEach-Object { "$($_.Association)|$($_.ProgId)|$($_.Executable)|$($_.Error)" }) -join ';'
            if ($before -eq $after -and ($stage -in @('Association', 'Choice', 'Confirm', 'BrowserDefault') -or ($Application -eq 'Chrome' -and $actionResult.BrowserActionInvoked))) {
                $errors.Add("Arret sans repetition : etape $stage en echec, associations inchangees apres stabilisation.")
                break
            }
            if ($attempt -lt $routes.Count) { Write-Info "[DEFAULT-APPS] $Application non confirme; autre voie enregistree $($attempt + 1)/$($routes.Count), sans reutiliser la precedente." }
        } while ($attempt -lt $routes.Count)
        $details = @($verification.State.Associations | ForEach-Object {
            "$($_.Association)=$($_.ProgId) [$($_.Executable)] erreur='$($_.Error)'"
        }) -join '; '
        $failure = "[DEFAULT-APPS] $Application non confirme apres $attempt tentative(s) distincte(s). Manquants : $($verification.State.Missing -join ', '). $details. $($errors -join ' | '). Corriger dans Parametres > Applications > Applications par defaut."
        Set-LDLCDefaultAppsDeferredDetail -Application $Application -Detail $failure
        if ($DeferFailureWarning) { Write-Info $failure } else { Write-Warn $failure }
        return $false
    }
    catch {
        if (Test-LDLCStopRequestError $_) { throw }
        $failure = "[DEFAULT-APPS] Verification $Application interrompue, resultat non confirme : $($_.Exception.Message). Controle manuel necessaire."
        Set-LDLCDefaultAppsDeferredDetail -Application $Application -Detail $failure
        if ($DeferFailureWarning) { Write-Info $failure } else { Write-Warn $failure }
        return $false
    }
    finally { if ($entered) { Close-LDLCDefaultAppsPage; Exit-LDLCDefaultAppsCompact } }
}

function Set-LDLCChromeDefaultBrowserWithUiAutomation {
    param([switch]$DeferFailureWarning, [ValidateRange(1,3)][int]$MaxAttempts=3)
    Stop-IfRequested
    $entered = $false
    try {
        $state = Get-LDLCDefaultAppState Chrome
        if ($state.Confirmed) { Write-Info 'Chrome deja selectionne ; aucune action necessaire.'; return $true }
        Enter-LDLCDefaultAppsCompact; $entered = $true
        $routes = @(Get-LDLCDefaultAppAttemptRoutes -Application Chrome -State $state | Select-Object -First $MaxAttempts)
        $errors = @(); $attempt = 0
        foreach ($route in $routes) {
            Stop-IfRequested; $attempt++
            try {
                [void](Invoke-LDLCDefaultAppAttempt -Application Chrome -State $state -Attempt $attempt -Route $route)
                $state=Get-LDLCDefaultAppState Chrome
                if ($state.Confirmed) { Write-Info 'Chrome defini comme navigateur par defaut par Windows.'; return $true }
                $errors += ('Windows n a pas applique Chrome pour : ' + ($state.Missing -join ', '))
                break
            } catch {
                if (Test-LDLCStopRequestError $_) { throw }
                $errors += $_.Exception.Message
                $verification = Wait-LDLCDefaultAppConfirmation -Application Chrome -TimeoutMilliseconds 1000
                if ($verification.Confirmed) { Write-Info 'Chrome defini comme navigateur par defaut par Windows apres stabilisation.'; return $true }
                if ($_.Exception.Data['DefaultAppsStage'] -in @('Choice','Confirm','BrowserDefault')) { break }
            }
        }
        if (-not $routes.Count) { $errors += 'Aucune fiche Chrome ni aucun selecteur compatible.' }
        $failure='Chrome non defini par defaut : ' + ($errors -join ' | ') + '. Verifier Parametres > Applications > Applications par defaut.'
        Set-LDLCDefaultAppsDeferredDetail -Application Chrome -Detail $failure
        if ($DeferFailureWarning) { Write-Info $failure } else { Write-Warn $failure }
        return $false
    } catch {
        if (Test-LDLCStopRequestError $_) { throw }
        $failure='Configuration Chrome interrompue : ' + $_.Exception.Message
        Set-LDLCDefaultAppsDeferredDetail -Application Chrome -Detail $failure
        if ($DeferFailureWarning) { Write-Info $failure } else { Write-Warn $failure }
        return $false
    } finally { if ($entered) { Close-LDLCDefaultAppsPage; Exit-LDLCDefaultAppsCompact } }
}

function Set-LDLCAdobePdfDefaultWithUiAutomation {
    param([switch]$DeferFailureWarning)
    return Invoke-LDLCDefaultAppConfiguration -Application Adobe -DeferFailureWarning:$DeferFailureWarning
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

function Get-LDLCWindowsBuildNumber {
    try { return [int](Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name CurrentBuildNumber -ErrorAction Stop).CurrentBuildNumber }
    catch { return [Environment]::OSVersion.Version.Build }
}

function Get-LDLCWidgetsComponentPresence {
    # Read the current Windows user's installed packages only. An unavailable or
    # failed Appx query is unknown, never evidence that Widgets were removed.
    if (-not (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue)) { return 'Unknown' }
    try {
        $packages = @(Get-AppxPackage -ErrorAction Stop)
        $widgets = @($packages | Where-Object { $_.Name -in @('MicrosoftWindows.Client.WebExperience', 'Microsoft.WidgetsPlatformRuntime') })
        if ($widgets.Count -gt 0) { return 'Present' }
        return 'Absent'
    } catch { return 'Unknown' }
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

    # Computer policies supported by the corresponding Windows feature. A zero
    # in an arbitrary legacy/guessed key is not proof that Widgets are disabled.
    $build = Get-LDLCWindowsBuildNumber
    $supportedPolicy = if ($build -ge 22000) { 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh\AllowNewsAndInterests' }
        elseif ($build -ge 19041) { 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds\EnableFeeds' } else { '' }
    $disabledByPolicy = ($supportedPolicy -and $null -ne $policyValues[$supportedPolicy] -and [int]$policyValues[$supportedPolicy] -eq 0)
    $disabledByUserValue = ($null -ne $taskbarDa -and [int]$taskbarDa -eq 0)
    $componentPresence = 'NotChecked'
    if ($build -ge 22000 -and -not $disabledByUserValue -and -not $disabledByPolicy) {
        $componentPresence = Get-LDLCWidgetsComponentPresence
    }
    $componentRemoved = ($componentPresence -eq 'Absent')

    return [pscustomobject]@{
        Disabled = [bool]($disabledByUserValue -or $disabledByPolicy -or $componentRemoved)
        TaskbarDa = $taskbarDa
        TaskbarMn = $taskbarMn
        PolicyDisabled = [bool]$disabledByPolicy
        PolicyValues = $policyValues
        SupportedPolicy = $supportedPolicy
        WindowsBuild = $build
        ComponentPresence = $componentPresence
        ComponentRemoved = $componentRemoved
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
    param([switch]$DeferFailureWarning)
    if ($DeferFailureWarning -and $script:LDLCDefaultAppsPendingChecks) { $script:LDLCDefaultAppsPendingChecks['Widgets'] = $true }
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
                Start-Sleep -Milliseconds 150

                if ((Get-LDLCWidgetsTaskbarState).Disabled) {
                    Write-Ok "[TASKBAR] Widgets desactives"
                    return $true
                }
            }
            catch {
                [void]$attemptErrors.Add("${policyPath}\${policyName}: $($_.Exception.Message)")
            }
            # A protected TaskbarDa must not turn a successful supported policy
            # write into an error attributed to that policy.
            try {
                Set-LDLCTaskbarAdvancedValue -Name 'TaskbarDa' -Value 0
                if ((Get-LDLCWidgetsTaskbarState).Disabled) { return $true }
            } catch { [void]$attemptErrors.Add("TaskbarDa: $($_.Exception.Message)") }
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

    $failure = "[TASKBAR] Widgets : desactivation non confirmee. $details"
    Set-LDLCDefaultAppsDeferredDetail -Application Widgets -Detail $failure
    Write-Info $failure
    return $false
}

function Set-LDLCTaskbarOptionsWithRegistry {
    param([switch]$DeferWidgetsFailureWarning)
    Write-Step "[TASKBAR] Configuration de la barre des taches"

    $changed = $false
    if (Disable-LDLCTaskbarOption -Name 'ShowTaskViewButton' -Label 'Vue des taches' -SuccessLog '[TASKBAR] Vue des taches desactivee') {
        $changed = $true
    }

    try {
        if (Disable-LDLCWidgetsTaskbarOption -DeferFailureWarning:$DeferWidgetsFailureWarning) { $changed = $true }
    } catch {
        if (Test-LDLCStopRequestError $_) { throw }
        Write-Info ('[TASKBAR] Widgets : configuration indisponible. ' + $_.Exception.Message)
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
    $widgetsOk = $false
    try { $widgetsOk = (Get-LDLCWidgetsTaskbarState).Disabled } catch {
        if (Test-LDLCStopRequestError $_) { throw }
        Write-Info ('[TASKBAR] Widgets : verification indisponible. ' + $_.Exception.Message)
    }
    if ($taskViewOk -and $widgetsOk) {
        Write-Ok "[TASKBAR] Configuration de la barre des taches terminee"
        return $true
    }

    return $false
}

function Invoke-LDLCChromeDefaultAppsSequence {
    param([switch]$DeferFinalValidation)
    $script:LDLCDefaultAppsPendingChecks = @{ Adobe = $true; Chrome = $true }
    $script:LDLCDefaultAppsDeferredDetails = @{}
    $script:LDLCDefaultAppsFinalAuditDone = $false
    Write-Section 'APPLICATIONS PAR DEFAUT'
    try {
        Enter-LDLCDefaultAppsCompact
        $adobe = Set-LDLCAdobePdfDefaultWithUiAutomation -DeferFailureWarning
        Set-LDLCDefaultAppsCompactProgress -Percent $(if ($adobe) { 50 } else { 0 }) -Message 'Configuration de Chrome...'
        $chrome = Set-LDLCChromeDefaultBrowserWithUiAutomation -DeferFailureWarning
        if ($adobe -and $chrome) {
            Set-LDLCDefaultAppsCompactProgress -Percent 100 -Message 'Configuration terminee' -Running $false -Success $true
            Write-Info 'Applications par defaut configurees ; controle Windows termine.'
        } else {
            $failed = @(); if (-not $adobe) { $failed += 'Adobe Acrobat Reader (.pdf)' }; if (-not $chrome) { $failed += 'Chrome (HTTP/HTTPS/.htm/.html)' }
            Set-LDLCDefaultAppsCompactProgress -Percent (50 * ([int][bool]$adobe + [int][bool]$chrome)) -Message 'Reglage non effectue' -Running $false -ErrorApplication ($failed -join ' ; ')
        }
    } finally { Exit-LDLCDefaultAppsCompact }
    try { [void](Set-LDLCTaskbarOptionsWithRegistry -DeferWidgetsFailureWarning) } catch {
        if (Test-LDLCStopRequestError $_) { throw }
        Write-Warn ('[TASKBAR] Configuration impossible : ' + $_.Exception.Message)
    }
    if (-not $DeferFinalValidation) { [void](Confirm-LDLCDefaultAppsFinalState) }
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
    param([int]$ProgressPercent = 90)
    return Invoke-LDLCChromeTaskbarPin -ProgressPercent $ProgressPercent
}

# endregion Module: 70.DefaultApps.ps1
