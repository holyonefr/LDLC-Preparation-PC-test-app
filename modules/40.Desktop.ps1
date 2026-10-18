# region Module: 40.Desktop.ps1
# Desktop, shortcuts, icons, and wallpaper helpers.


function Get-LDLCDesktopPaths {
    $paths = @(
        [Environment]::GetFolderPath("CommonDesktopDirectory"),
        [Environment]::GetFolderPath("Desktop"),
        "$env:USERPROFILE\OneDrive\Desktop"
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

    return @($paths)
}

function Get-LDLCPreferredDesktopPath {
    $commonDesktop = [Environment]::GetFolderPath("CommonDesktopDirectory")
    if (-not [string]::IsNullOrWhiteSpace($commonDesktop) -and (Test-Path $commonDesktop)) {
        return $commonDesktop
    }

    return [Environment]::GetFolderPath("Desktop")
}

$DesktopPath = Get-LDLCPreferredDesktopPath


function Get-LDLCUserDesktopPath {
    # The shell-folder registry value is the authoritative desktop location when
    # OneDrive redirection is enabled on a newly created Windows profile.
    try {
        $shellFoldersPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
        $configuredDesktop = (Get-ItemProperty -LiteralPath $shellFoldersPath -Name 'Desktop' -ErrorAction Stop).Desktop
        if (-not [string]::IsNullOrWhiteSpace([string]$configuredDesktop)) {
            $expandedDesktop = [Environment]::ExpandEnvironmentVariables([string]$configuredDesktop)
            if (-not [string]::IsNullOrWhiteSpace($expandedDesktop)) {
                return $expandedDesktop
            }
        }
    }
    catch {}

    $userDesktop = [Environment]::GetFolderPath("Desktop")
    if (-not [string]::IsNullOrWhiteSpace($userDesktop)) {
        return $userDesktop
    }

    if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
        return (Join-Path $env:USERPROFILE 'Desktop')
    }

    return $DesktopPath
}

function Initialize-LDLCDesktopRefreshType {
    if (-not ([System.Management.Automation.PSTypeName]'DesktopRefresh').Type) {
        Add-Type @"
using System;
using System.Runtime.InteropServices;
public class DesktopRefresh {
    [DllImport("shell32.dll")]
    public static extern void SHChangeNotify(int wEventId, uint uFlags, IntPtr dwItem1, IntPtr dwItem2);
}
"@
    }
}

function Refresh-Desktop {
    Stop-IfRequested
    Write-Step "Actualisation du bureau..."
    Initialize-LDLCDesktopRefreshType
    [DesktopRefresh]::SHChangeNotify(0x08000000, 0x0000, [IntPtr]::Zero, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 50
}

function Initialize-LDLCDesktopIconLayoutType {
    if (-not ([System.Management.Automation.PSTypeName]'LDLCDesktopIconLayout').Type) {
        Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;

public static class LDLCDesktopIconLayout
{
    private const int LVM_FIRST = 0x1000;
    private const int LVM_GETITEMCOUNT = LVM_FIRST + 4;
    private const int LVM_GETITEMTEXTW = LVM_FIRST + 115;
    private const int LVM_SETITEMPOSITION = LVM_FIRST + 15;
    private const uint PROCESS_VM_OPERATION = 0x0008;
    private const uint PROCESS_VM_READ = 0x0010;
    private const uint PROCESS_VM_WRITE = 0x0020;
    private const uint MEM_COMMIT = 0x1000;
    private const uint MEM_RESERVE = 0x2000;
    private const uint MEM_RELEASE = 0x8000;
    private const uint PAGE_READWRITE = 0x04;
    private const uint LVIF_TEXT = 0x0001;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct LVITEM
    {
        public uint mask;
        public int iItem;
        public int iSubItem;
        public uint state;
        public uint stateMask;
        public IntPtr pszText;
        public int cchTextMax;
        public int iImage;
        public IntPtr lParam;
        public int iIndent;
        public int iGroupId;
        public uint cColumns;
        public IntPtr puColumns;
        public IntPtr piColFmt;
        public int iGroup;
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr FindWindow(string lpClassName, string lpWindowName);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr FindWindowEx(IntPtr parentHandle, IntPtr childAfter, string className, string windowTitle);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr OpenProcess(uint desiredAccess, bool inheritHandle, uint processId);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(IntPtr handle);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr VirtualAllocEx(IntPtr process, IntPtr address, UIntPtr size, uint allocationType, uint protect);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool VirtualFreeEx(IntPtr process, IntPtr address, UIntPtr size, uint freeType);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool ReadProcessMemory(IntPtr process, IntPtr baseAddress, byte[] buffer, int size, out IntPtr numberOfBytesRead);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool WriteProcessMemory(IntPtr process, IntPtr baseAddress, byte[] buffer, int size, out IntPtr numberOfBytesWritten);

    private static IntPtr GetDesktopListView()
    {
        IntPtr progman = FindWindow("Progman", "Program Manager");
        IntPtr shellView = FindWindowEx(progman, IntPtr.Zero, "SHELLDLL_DefView", null);

        if (shellView == IntPtr.Zero)
        {
            IntPtr worker = IntPtr.Zero;
            while (true)
            {
                worker = FindWindowEx(IntPtr.Zero, worker, "WorkerW", null);
                if (worker == IntPtr.Zero) break;
                shellView = FindWindowEx(worker, IntPtr.Zero, "SHELLDLL_DefView", null);
                if (shellView != IntPtr.Zero) break;
            }
        }

        if (shellView == IntPtr.Zero) return IntPtr.Zero;
        return FindWindowEx(shellView, IntPtr.Zero, "SysListView32", "FolderView");
    }

    private static string GetItemText(IntPtr listView, IntPtr processHandle, IntPtr remoteLvi, IntPtr remoteText, int index)
    {
        LVITEM item = new LVITEM();
        item.mask = LVIF_TEXT;
        item.iItem = index;
        item.iSubItem = 0;
        item.pszText = remoteText;
        item.cchTextMax = 260;

        int lviSize = Marshal.SizeOf(typeof(LVITEM));
        byte[] lviBytes = new byte[lviSize];
        IntPtr localPtr = Marshal.AllocHGlobal(lviSize);
        try
        {
            Marshal.StructureToPtr(item, localPtr, false);
            Marshal.Copy(localPtr, lviBytes, 0, lviSize);
        }
        finally
        {
            Marshal.FreeHGlobal(localPtr);
        }

        IntPtr written;
        if (!WriteProcessMemory(processHandle, remoteLvi, lviBytes, lviBytes.Length, out written))
            return null;

        SendMessage(listView, LVM_GETITEMTEXTW, (IntPtr)index, remoteLvi);

        byte[] textBytes = new byte[520];
        IntPtr read;
        if (!ReadProcessMemory(processHandle, remoteText, textBytes, textBytes.Length, out read))
            return null;

        string value = Encoding.Unicode.GetString(textBytes);
        int zeroIndex = value.IndexOf('\0');
        if (zeroIndex >= 0) value = value.Substring(0, zeroIndex);
        return value.Trim();
    }

    public static bool PositionIcons(string[] orderedNames, int x, int startY, int stepY)
    {
        IntPtr listView = GetDesktopListView();
        if (listView == IntPtr.Zero) return false;

        uint processId;
        GetWindowThreadProcessId(listView, out processId);
        if (processId == 0) return false;

        IntPtr process = OpenProcess(PROCESS_VM_OPERATION | PROCESS_VM_READ | PROCESS_VM_WRITE, false, processId);
        if (process == IntPtr.Zero) return false;

        IntPtr remoteText = IntPtr.Zero;
        IntPtr remoteLvi = IntPtr.Zero;

        try
        {
            remoteText = VirtualAllocEx(process, IntPtr.Zero, (UIntPtr)520, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
            remoteLvi = VirtualAllocEx(process, IntPtr.Zero, (UIntPtr)Marshal.SizeOf(typeof(LVITEM)), MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
            if (remoteText == IntPtr.Zero || remoteLvi == IntPtr.Zero) return false;

            int itemCount = SendMessage(listView, LVM_GETITEMCOUNT, IntPtr.Zero, IntPtr.Zero).ToInt32();
            var indexByName = new System.Collections.Generic.Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);

            for (int i = 0; i < itemCount; i++)
            {
                string name = GetItemText(listView, process, remoteLvi, remoteText, i);
                if (!String.IsNullOrWhiteSpace(name) && !indexByName.ContainsKey(name))
                {
                    indexByName[name] = i;
                }
            }

            for (int pos = 0; pos < orderedNames.Length; pos++)
            {
                string wanted = orderedNames[pos];
                int idx;
                if (!indexByName.TryGetValue(wanted, out idx)) continue;

                int y = startY + (pos * stepY);
                int lParam = ((y & 0xFFFF) << 16) | (x & 0xFFFF);
                SendMessage(listView, LVM_SETITEMPOSITION, (IntPtr)idx, (IntPtr)lParam);
            }

            return true;
        }
        finally
        {
            if (remoteLvi != IntPtr.Zero) VirtualFreeEx(process, remoteLvi, UIntPtr.Zero, MEM_RELEASE);
            if (remoteText != IntPtr.Zero) VirtualFreeEx(process, remoteText, UIntPtr.Zero, MEM_RELEASE);
            CloseHandle(process);
        }
    }
}
"@
    }
}

function Set-LDLCDesktopOrderedLayout {
    Stop-IfRequested
    Write-Section "ORGANISATION DU BUREAU"

    $orderedNames = New-Object System.Collections.Generic.List[string]
    [void]$orderedNames.Add("Google Chrome")
    [void]$orderedNames.Add("LibreOffice")
    [void]$orderedNames.Add("Adobe Acrobat")
    [void]$orderedNames.Add("VLC media player")
    [void]$orderedNames.Add("Ce PC")
    [void]$orderedNames.Add("Utilisateur")

    try {
        $gpuInfo = Get-LDLCGpuVendor
        if ($gpuInfo -and (Test-LDLCDedicatedGpu -GpuInfo $gpuInfo)) {
            if ($gpuInfo.Vendor -eq 'NVIDIA') {
                [void]$orderedNames.Add("NVIDIA App")
            }
            elseif ($gpuInfo.Vendor -eq 'AMD') {
                [void]$orderedNames.Add("AMD Adrenalin")
            }

        }
    }
    catch {}

    Refresh-Desktop
    Start-Sleep -Milliseconds 1200

    try {
        Initialize-LDLCDesktopIconLayoutType
        $positioned = [LDLCDesktopIconLayout]::PositionIcons($orderedNames.ToArray(), 20, 90, 106)
        if ($positioned) {
            Write-Ok "Ordre visuel du bureau applique."
        }
        else {
            Write-Warn "Impossible de forcer l'ordre visuel du bureau."
        }
    }
    catch {
        Write-Warn "Impossible d'organiser le bureau : $($_.Exception.Message)"
    }

    Refresh-Desktop
}

function Remove-LDLCUserDiagDesktopItems {
    Stop-IfRequested

    foreach ($desktopRoot in (Get-LDLCDesktopPaths)) {
        Stop-IfRequested

        if (-not (Test-Path $desktopRoot)) {
            continue
        }

        foreach ($fileName in @('UserDiag.exe', 'userdiag.exe', 'UserDiag.lnk', 'userdiag.lnk')) {
            $candidatePath = Join-Path $desktopRoot $fileName

            if (Test-Path $candidatePath) {
                try {
                    Remove-Item -LiteralPath $candidatePath -Force -ErrorAction Stop
                    Write-Ok "Ancien element diagnostic supprime : $candidatePath"
                }
                catch {
                    Write-Warn "Ancien element diagnostic conserve car verrouille : $candidatePath"
                }
            }
        }

        $legacyArchives = @(Get-ChildItem -LiteralPath $desktopRoot -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like 'LDLCPreparationPC-*.zip' })
        foreach ($archive in $legacyArchives) {
            try {
                Remove-Item -LiteralPath $archive.FullName -Force -ErrorAction Stop
                Write-Ok "Archive LDLC obsolete supprimee du Bureau : $($archive.FullName)"
            }
            catch {
                Write-Warn "Archive LDLC obsolete conservee car verrouillee : $($archive.FullName)"
            }
        }
    }
}


function Get-StartMenuShortcutPath {
    param([string[]]$Names)

    $startMenuPaths = @(
        "$env:ProgramData\Microsoft\Windows\Start Menu\Programs",
        "$env:AppData\Microsoft\Windows\Start Menu\Programs"
    )

    foreach ($basePath in $startMenuPaths) {
        Stop-IfRequested

        if (-not (Test-Path $basePath)) { continue }

        try {
            $shortcuts = Get-ChildItem -Path $basePath -Filter *.lnk -Recurse -ErrorAction SilentlyContinue
            foreach ($shortcut in $shortcuts) {
                foreach ($name in $Names) {
                    if ($shortcut.BaseName -like "*$name*") {
                        return $shortcut.FullName
                    }
                }
            }
        }
        catch {}
    }

    return $null
}

function Remove-LibreOfficeDesktopShortcuts {
    Stop-IfRequested
    Write-Step "Nettoyage des raccourcis LibreOffice sur le bureau..."

    $desktopPaths = Get-LDLCDesktopPaths

    try {
        $ws = New-Object -ComObject WScript.Shell
    }
    catch {
        Write-Warn "Impossible d'initialiser WScript.Shell pour nettoyer les raccourcis LibreOffice : $($_.Exception.Message)"
        return
    }

    $canonicalShortcutPath = Join-Path $DesktopPath "LibreOffice.lnk"
    $removedCount = 0

    foreach ($path in $desktopPaths) {
        Stop-IfRequested

        if (-not (Test-Path $path)) {
            continue
        }

        try {
            $shortcuts = Get-ChildItem -Path $path -Filter *.lnk -File -ErrorAction SilentlyContinue

            foreach ($shortcut in $shortcuts) {
                $shouldRemove = $false

                if ($shortcut.BaseName -like "*LibreOffice*") {
                    $shouldRemove = $true
                }
                else {
                    try {
                        $target = $ws.CreateShortcut($shortcut.FullName).TargetPath
                        if ($target -and ($target -like "*LibreOffice*" -or $target -like "*soffice.exe")) {
                            $shouldRemove = $true
                        }
                    }
                    catch {}
                }

                if ($shouldRemove) {
                    if ($shortcut.FullName -ieq $canonicalShortcutPath) {
                        continue
                    }

                    Remove-Item $shortcut.FullName -Force -ErrorAction SilentlyContinue
                    Write-Ok "Raccourci LibreOffice supprime : $($shortcut.FullName)"
                    $removedCount++
                }
            }
        }
        catch {
            Write-Warn "Impossible d'analyser les raccourcis dans $path : $($_.Exception.Message)"
        }
    }

    if ($removedCount -eq 0) {
        Write-Step "Aucun raccourci LibreOffice a nettoyer."
        return
    }

    Refresh-Desktop
}

function Remove-LDLCShortcutDuplicates {
    param(
        [Parameter(Mandatory = $true)][string]$ShortcutName,
        [Parameter(Mandatory = $true)][string]$KeepPath
    )

    foreach ($desktopRoot in (Get-LDLCDesktopPaths)) {
        Stop-IfRequested

        $candidatePath = Join-Path $desktopRoot $ShortcutName
        if ($candidatePath -ieq $KeepPath) {
            continue
        }

        if (Test-Path $candidatePath) {
            Remove-Item $candidatePath -Force -ErrorAction SilentlyContinue
            Write-Ok "Ancien raccourci supprime : $candidatePath"
        }
    }
}


function Get-LDLCExistingExePathByNames {
    param(
        [string[]]$ExePaths,
        [string[]]$SearchFolders,
        [string[]]$ExeNames
    )

    foreach ($exeName in $ExeNames) {
        $targetExe = Get-ExistingExePath `
            -ExePaths $ExePaths `
            -SearchFolders $SearchFolders `
            -ExeName $exeName

        if ($targetExe) {
            return $targetExe
        }
    }

    return $null
}

function Ensure-LDLCDesktopShortcutFromTarget {
    param(
        [Parameter(Mandatory = $true)][string]$ShortcutName,
        [string]$TargetExe,
        [string[]]$StartMenuNames = @(),
        [switch]$MissingTargetIsInfo
    )

    Stop-IfRequested

    $desktopTargetPath = Get-LDLCUserDesktopPath
    $shortcutPath = Join-Path $desktopTargetPath $ShortcutName

    if ($StartMenuNames -and $StartMenuNames.Count -gt 0) {
        $startMenuShortcut = Get-StartMenuShortcutPath -Names $StartMenuNames

        if ($startMenuShortcut) {
            try {
                if (Test-Path $shortcutPath) {
                    Remove-Item $shortcutPath -Force -ErrorAction SilentlyContinue
                }

                Copy-Item $startMenuShortcut $shortcutPath -Force
                Remove-LDLCShortcutDuplicates -ShortcutName $ShortcutName -KeepPath $shortcutPath
                Write-Ok "Raccourci copie depuis le menu Demarrer : $ShortcutName"
                return
            }
            catch {
                Write-Warn "Impossible de copier le raccourci $ShortcutName depuis le menu Demarrer. Creation manuelle..."
            }
        }
    }

    if (-not $TargetExe -or -not (Test-Path $TargetExe)) {
        $message = "Executable introuvable, raccourci non cree : $ShortcutName"
        if ($MissingTargetIsInfo) { Write-Step $message } else { Write-Warn $message }
        return
    }

    if (Test-Path $shortcutPath) {
        try {
            $shell = New-Object -ComObject WScript.Shell
            $existingShortcut = $shell.CreateShortcut($shortcutPath)

            if ($existingShortcut.TargetPath -and (Test-Path $existingShortcut.TargetPath)) {
                if ($existingShortcut.TargetPath -ieq $TargetExe) {
                    Write-Ok "Raccourci deja present et valide : $ShortcutName"
                    return
                }
            }
        }
        catch {}

        Remove-Item $shortcutPath -Force -ErrorAction SilentlyContinue
    }

    try {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $TargetExe
        $shortcut.WorkingDirectory = Split-Path $TargetExe -Parent
        $shortcut.IconLocation = "$TargetExe,0"
        $shortcut.WindowStyle = 1
        $shortcut.Save()
        Remove-LDLCShortcutDuplicates -ShortcutName $ShortcutName -KeepPath $shortcutPath

        Write-Ok "Raccourci cree : $ShortcutName"
    }
    catch {
        Write-Warn "Impossible de creer le raccourci $ShortcutName : $($_.Exception.Message)"
    }
}

function Ensure-LDLCGpuDesktopShortcut {
    param([Parameter(Mandatory = $true)][string]$Vendor)

    switch ($Vendor) {
        'NVIDIA' {
            $targetExe = Get-LDLCExistingExePathByNames `
                -ExePaths @(
                    'C:\Program Files\NVIDIA Corporation\NVIDIA App\CEF\NVIDIA App.exe',
                    'C:\Program Files\NVIDIA Corporation\NVIDIA app\NVIDIA app.exe',
                    'C:\Program Files\NVIDIA Corporation\NVIDIA app\NVIDIAApp.exe'
                ) `
                -SearchFolders @(
                    "$env:ProgramFiles\NVIDIA Corporation\NVIDIA App",
                    "$env:ProgramFiles\NVIDIA Corporation",
                    "${env:ProgramFiles(x86)}\NVIDIA Corporation"
                ) `
                -ExeNames @('NVIDIA App.exe', 'NVIDIA app.exe', 'NVIDIAApp.exe')

            Ensure-LDLCDesktopShortcutFromTarget `
                -ShortcutName 'NVIDIA App.lnk' `
                -TargetExe $targetExe `
                -StartMenuNames @('NVIDIA App', 'NVIDIA app')
        }
        'AMD' {
            $targetExe = Get-LDLCExistingExePathByNames `
                -ExePaths @(
                    'C:\Program Files\AMD\CNext\CNext\RadeonSoftware.exe',
                    'C:\Program Files\AMD\CNext\CNext\AMDSoftware.exe',
                    'C:\Program Files\AMD\CNext\CNext\RadeonSoftware\RadeonSoftware.exe',
                    'C:\Program Files\AMD\CNext\CNext\RadeonSoftware\AMDSoftware.exe',
                    'C:\Program Files\AMD\CNext\CNext\AMDSoftware\AMDSoftware.exe',
                    'C:\Program Files (x86)\AMD\CNext\CNext\RadeonSoftware.exe',
                    'C:\Program Files (x86)\AMD\CNext\CNext\AMDSoftware.exe',
                    'C:\Program Files (x86)\AMD\CNext\CNext\RadeonSoftware\RadeonSoftware.exe',
                    'C:\Program Files (x86)\AMD\CNext\CNext\AMDSoftware\AMDSoftware.exe'
                ) `
                -SearchFolders @(
                    "$env:ProgramFiles\AMD",
                    "${env:ProgramFiles(x86)}\AMD",
                    'C:\AMD'
                ) `
                -ExeNames @('RadeonSoftware.exe', 'AMDSoftware.exe')

            Ensure-LDLCDesktopShortcutFromTarget `
                -ShortcutName 'AMD Adrenalin.lnk' `
                -TargetExe $targetExe `
                -StartMenuNames @('AMD Software', 'Adrenalin', 'Radeon Software') `
                -MissingTargetIsInfo
        }
    }
}

function Ensure-DesktopShortcut {
    param($App)

    Stop-IfRequested

    if ($App.Name -eq "LibreOffice") {
        Remove-LibreOfficeDesktopShortcuts
    }

    if (-not $App.CreateShortcut) {
        Write-Step "Aucun raccourci bureau demande pour cette application."
        return
    }

    $shortcutPath = Join-Path $DesktopPath $App.ShortcutName

    $startMenuNames = @()
    if ($App.ContainsKey('StartMenuNames') -and $App.StartMenuNames) {
        $startMenuNames += @($App.StartMenuNames)
    }

    if ($App.Name -eq "Adobe Acrobat Reader") {
        $startMenuNames += @(
            "Adobe Acrobat",
            "Adobe Acrobat Reader",
            "Adobe Reader"
        )
    }

    if ($startMenuNames.Count -gt 0) {
        $startMenuShortcut = Get-StartMenuShortcutPath -Names $startMenuNames

        if ($startMenuShortcut) {
            try {
                if (Test-Path $shortcutPath) {
                    Remove-Item $shortcutPath -Force -ErrorAction SilentlyContinue
                }

                Copy-Item $startMenuShortcut $shortcutPath -Force
                Remove-LDLCShortcutDuplicates -ShortcutName $App.ShortcutName -KeepPath $shortcutPath
                Write-Ok "Raccourci copie depuis le menu Demarrer : $($App.ShortcutName)"
                return
            }
            catch {
                Write-Warn "Impossible de copier le raccourci $($App.ShortcutName) depuis le menu Demarrer. Creation manuelle..."
            }
        }
        elseif ($App.Name -eq "Adobe Acrobat Reader") {
            Write-Warn "Raccourci Adobe introuvable dans le menu Demarrer. Creation manuelle..."
        }
    }

    $targetExe = Get-ExistingExePath `
        -ExePaths $App.ExePaths `
        -SearchFolders $App.SearchFolders `
        -ExeName $App.ExeName

    if (-not $targetExe) {
        Write-Warn "Executable introuvable, raccourci non cree : $($App.ShortcutName)"
        return
    }

    if (Test-Path $shortcutPath) {
        try {
            $shell = New-Object -ComObject WScript.Shell
            $existingShortcut = $shell.CreateShortcut($shortcutPath)

            if ($existingShortcut.TargetPath -and (Test-Path $existingShortcut.TargetPath)) {
                if ($existingShortcut.TargetPath -ieq $targetExe) {
                    Write-Ok "Raccourci deja present et valide : $($App.ShortcutName)"
                    return
                }
            }
        }
        catch {}

        Remove-Item $shortcutPath -Force -ErrorAction SilentlyContinue
    }

    try {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $targetExe
        $shortcut.WorkingDirectory = Split-Path $targetExe -Parent
        $shortcut.IconLocation = "$targetExe,0"
        $shortcut.WindowStyle = 1
        $shortcut.Save()
        Remove-LDLCShortcutDuplicates -ShortcutName $App.ShortcutName -KeepPath $shortcutPath

        Write-Ok "Raccourci cree : $($App.ShortcutName)"
    }
    catch {
        Write-Err "Impossible de creer le raccourci $($App.ShortcutName) : $($_.Exception.Message)"
    }
}

function Repair-LDLCDesktopShortcuts {
    Stop-IfRequested
    Write-Section "VERIFICATION DES RACCOURCIS"

    foreach ($app in $Apps | Where-Object { $_.CreateShortcut }) {
        try {
            Ensure-DesktopShortcut -App $app
        }
        catch {
            Write-Warn "Impossible de verifier le raccourci de $($app.Name) : $($_.Exception.Message)"
        }
    }


    try {
        $gpuInfo = Get-LDLCGpuVendor
        if ($gpuInfo -and (Test-LDLCDedicatedGpu -GpuInfo $gpuInfo)) {
            Ensure-LDLCGpuDesktopShortcut -Vendor $gpuInfo.Vendor
        }
        else {
            Write-Step "Pas de GPU dedie AMD/NVIDIA detecte : aucun element GPU ajoute au Bureau."
        }
    }
    catch {
        Write-Warn "Impossible de verifier les elements GPU du bureau : $($_.Exception.Message)"
    }
}
function Enable-DesktopSystemIcons {
    Stop-IfRequested

    Write-Section "CONFIGURATION DES ICONES DU BUREAU"

    $RegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel"

    if (-not (Test-Path $RegPath)) {
        New-Item -Path $RegPath -Force | Out-Null
    }

    $icons = @(
        @{
            Guid = "{20D04FE0-3AEA-1069-A2D8-08002B30309D}"
            Name = "Ce PC"
        },
        @{
            Guid = "{59031a47-3f72-44a7-89c5-5595fe6b30ee}"
            Name = "Dossier utilisateur"
        }
    )

    foreach ($icon in $icons) {
        Stop-IfRequested

        $guid = $icon.Guid
        $name = $icon.Name

        $current = (Get-ItemProperty -Path $RegPath -Name $guid -ErrorAction SilentlyContinue).$guid

        if ($current -eq 0) {
            Write-Ok "$name deja affiche"
        }
        else {
            Write-Step "Activation de $name..."
            Set-ItemProperty -Path $RegPath -Name $guid -Value 0 -Type DWord -Force
            Write-Ok "$name active"
        }
    }

    Refresh-Desktop
}


# endregion Module: 40.Desktop.ps1

