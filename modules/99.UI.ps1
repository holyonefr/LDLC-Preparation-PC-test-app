# region UI
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ===== ADMIN AUTO =====
function Test-LDLCIsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not $Preview -and -not (Test-LDLCIsAdmin)) {
    if (Get-Command Start-LDLCInstance -ErrorAction SilentlyContinue) {
        Start-LDLCInstance -Arguments @() -RunAs | Out-Null
    }
    else {
        $entryPoint = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
        $psExe = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"

        Start-Process $psExe `
            -Verb RunAs `
            -WindowStyle Minimized `
            -ArgumentList "-ExecutionPolicy Bypass -NoProfile -File `"$entryPoint`""
    }

    return
}

# ===== PATHS =====
function Get-LDLCUIBasePath {
    if (-not [string]::IsNullOrWhiteSpace($script:LDLCRoot)) {
        return $script:LDLCRoot
    }

    if ($PSScriptRoot) {
        return $PSScriptRoot
    }

    if ($PSCommandPath) {
        return (Split-Path -Parent $PSCommandPath)
    }

    if ($MyInvocation.MyCommand.Path) {
        return (Split-Path -Parent $MyInvocation.MyCommand.Path)
    }

    return (Get-Location).Path
}

function Get-LDLCUIEmbeddedAssetRoot {
    if (-not [string]::IsNullOrWhiteSpace($script:LDLCEmbeddedAssetRoot)) {
        return $script:LDLCEmbeddedAssetRoot
    }

    if (Get-Command Get-LDLCWritableRuntimeRoot -ErrorAction SilentlyContinue) {
        return Get-LDLCWritableRuntimeRoot
    }

    return $null
}

function Get-LDLCUIRuntimeRoot {
    $runtimeRoot = Get-LDLCUIEmbeddedAssetRoot

    if ([string]::IsNullOrWhiteSpace($runtimeRoot)) {
        $runtimeRoot = Join-Path (Get-LDLCUIBasePath) 'runtime'
    }

    if (-not (Test-Path -LiteralPath $runtimeRoot)) {
        New-Item -ItemType Directory -Path $runtimeRoot -Force | Out-Null
    }

    return $runtimeRoot
}

function Remove-LDLCUILegacyRuntimeFiles {
    foreach ($legacyPath in @(
        'C:\LDLC_PROGRESS.txt',
        'C:\LDLC_WORKER_LAUNCH.log',
        'C:\LDLC_WORKER_ERROR.log',
        'C:\LDLC_STOP'
    )) {
        Remove-Item -LiteralPath $legacyPath -Force -ErrorAction SilentlyContinue
    }
}

function Resolve-LDLCUIAssetPath {
    param([Parameter(Mandatory = $true)][string[]]$RelativePaths)

    $assetRoots = New-Object System.Collections.Generic.List[string]
    $baseRoot = Get-LDLCUIBasePath
    $embeddedRoot = Get-LDLCUIEmbeddedAssetRoot

    if (-not [string]::IsNullOrWhiteSpace($baseRoot)) {
        [void]$assetRoots.Add($baseRoot)

        $baseParent = Split-Path -Parent $baseRoot
        if (-not [string]::IsNullOrWhiteSpace($baseParent)) {
            [void]$assetRoots.Add($baseParent)
        }

        [void]$assetRoots.Add((Join-Path $baseRoot 'assets'))
        if (-not [string]::IsNullOrWhiteSpace($baseParent)) {
            [void]$assetRoots.Add((Join-Path $baseParent 'assets'))
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($embeddedRoot)) {
        [void]$assetRoots.Add($embeddedRoot)
    }

    foreach ($relativePath in $RelativePaths) {
        foreach ($assetRoot in ($assetRoots | Select-Object -Unique)) {
            $candidate = Join-Path $assetRoot $relativePath
            if (Test-Path $candidate) {
                return $candidate
            }
        }
    }

    return $null
}

$base = Get-LDLCUIBasePath
$bgPath = Resolve-LDLCUIAssetPath -RelativePaths @(
    'UI_Background.v2.png',
    'assets\UI_Background.v2.png',
    'UI_Background.png',
    'assets\UI_Background.png'
)
$installScript = Join-Path $base 'install.ps1'
$script:runtimeRoot = Get-LDLCUIRuntimeRoot
$script:progressFile = Join-Path $script:runtimeRoot 'LDLC_PROGRESS.txt'
$script:stopFile = Join-Path $script:runtimeRoot 'LDLC_STOP'
Remove-LDLCUILegacyRuntimeFiles

if ([string]::IsNullOrWhiteSpace($bgPath) -or -not (Test-Path $bgPath)) {
    [System.Windows.Forms.MessageBox]::Show("UI_Background.v2.png introuvable dans $base ou dans le dossier d'extraction.")
    return
}

if (-not $Preview -and -not $WorkerLauncher -and -not (Test-Path $installScript)) {
    [System.Windows.Forms.MessageBox]::Show("install.ps1 introuvable : $installScript")
    return
}

# ===== MUTEX =====
$mutexName = if ($Preview) { 'LDLC_PREPTOOL_PREVIEW_MUTEX' } else { 'LDLC_PREPTOOL_MUTEX' }
$created = $false
$mutex = New-Object System.Threading.Mutex($true, $mutexName, [ref]$created)
if (-not $created) { return }

$script:phases = @(
    @{
        Name = 'PREPARATION'
        Detail = 'Verification et nettoyage Windows'
        Min = 0
        Max = 24
    },
    @{
        Name = 'INSTALLATION'
        Detail = 'Installation des applications'
        Min = 25
        Max = 60
    },
    @{
        Name = 'CONFIGURATION'
        Detail = 'Bureau, wallpaper et pilotes'
        Min = 61
        Max = 89
    },
    @{
        Name = 'FINALISATION'
        Detail = 'Controles finaux'
        Min = 90
        Max = 100
    }
)

$script:previewTimeline = @(
    @{ Percent = 0;   Message = 'Initialisation de l environnement...' },
    @{ Percent = 5;   Message = 'Windows Update en arriere-plan...' },
    @{ Percent = 8;   Message = 'Verification de la connexion Internet...' },
    @{ Percent = 16;  Message = 'Suppression raccourcis Edge...' },
    @{ Percent = 20;  Message = 'Suppression Copilot barre des taches...' },
    @{ Percent = 25;  Message = 'Preparation des installations...' },
    @{ Percent = 38;  Message = 'Installation Google Chrome...' },
    @{ Percent = 50;  Message = 'Installation LibreOffice, Adobe, VLC et 7-Zip...' },
    @{ Percent = 76;  Message = 'Application du fond d ecran LDLC...' },
    @{ Percent = 88;  Message = 'Preparation des pilotes GPU...' },
    @{ Percent = 96;  Message = 'Restauration veille et controles finaux...' },
    @{ Percent = 100; Message = 'Preparation terminee, tu peux quitter !' }
)

$script:percent = 0
$script:message = if ($Preview) { $script:previewTimeline[0].Message } else { 'Initialisation de l environnement...' }
$script:proc = $null
$script:workerLaunchAttempted = $false
$script:uiFirstPaintCompleted = $false
$script:previewIndex = 0
$script:closing = $false
$script:closeStep = 0
$script:closeRequestedAt = $null
$script:stopFileCreated = $false
$script:forceStopDone = $false
$script:gracefulStopTimeoutSeconds = 8
$script:closeAfterForceSeconds = 10
$script:LDLCAppVersionLabel = 'Version 1.0'

function Convert-X {
    param([int]$Value)
    return [int]($Value * $script:scaleX)
}

function Convert-Y {
    param([int]$Value)
    return [int]($Value * $script:scaleY)
}

function Convert-FontSize {
    param(
        [double]$Value,
        [double]$Minimum = 7
    )

    $scale = [Math]::Min($script:scaleX, $script:scaleY)
    return [single][Math]::Max($Minimum, ($Value * $scale * 0.72))
}

function Limit-LDLCText {
    param(
        [string]$Text,
        [int]$MaxLength
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ''
    }

    $value = $Text.Trim()
    if ($value.Length -le $MaxLength) {
        return $value
    }

    return ($value.Substring(0, [Math]::Max(0, $MaxLength - 3)) + '...')
}

function Draw-LDLCTextWithShadow {
    param(
        [Parameter(Mandatory = $true)][System.Drawing.Graphics]$Graphics,
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][System.Drawing.Font]$Font,
        [Parameter(Mandatory = $true)][System.Drawing.Brush]$Brush,
        [Parameter(Mandatory = $true)][System.Drawing.RectangleF]$Bounds,
        [System.Drawing.StringFormat]$Format,
        [int]$ShadowAlpha = 190
    )

    $shadowBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb($ShadowAlpha, 0, 0, 0))
    $shadowBounds = New-Object System.Drawing.RectangleF(
        ($Bounds.X + 1),
        ($Bounds.Y + 1),
        $Bounds.Width,
        $Bounds.Height
    )

    if ($Format) {
        $Graphics.DrawString($Text, $Font, $shadowBrush, $shadowBounds, $Format)
        $Graphics.DrawString($Text, $Font, $Brush, $Bounds, $Format)
    }
    else {
        $Graphics.DrawString($Text, $Font, $shadowBrush, $shadowBounds)
        $Graphics.DrawString($Text, $Font, $Brush, $Bounds)
    }

    $shadowBrush.Dispose()
}

function Get-LDLCPhaseIndex {
    param([int]$Percent)

    for ($i = 0; $i -lt $script:phases.Count; $i++) {
        if ($Percent -ge $script:phases[$i].Min -and $Percent -le $script:phases[$i].Max) {
            return $i
        }
    }

    return ($script:phases.Count - 1)
}

function Get-LDLCStatusTitle {
    param([int]$Percent)

    if ($script:closing) {
        return 'ARRET EN COURS...'
    }

    $phaseIndex = Get-LDLCPhaseIndex -Percent $Percent
    switch ($script:phases[$phaseIndex].Name) {
        'PREPARATION'   { return 'PREPARATION DU SYSTEME...' }
        'INSTALLATION'  { return 'INSTALLATION DES APPLICATIONS...' }
        'CONFIGURATION' { return 'CONFIGURATION DU SYSTEME...' }
        default         { return 'FINALISATION...' }
    }
}

function Read-LDLCProgressFile {
    if (-not (Test-Path $script:progressFile)) {
        return
    }

    try {
        $line = Get-Content $script:progressFile -ErrorAction Stop | Select-Object -Last 1
        if ($line -match '^(\d+)\|(.*)$') {
            $script:percent = [Math]::Max(0, [Math]::Min(100, [int]$matches[1]))
            $script:message = Limit-LDLCText -Text $matches[2] -MaxLength 78
        }
    }
    catch {}
}

function Update-LDLCPreviewProgress {
    $target = $script:previewTimeline[$script:previewIndex]
    $script:message = $target.Message

    if ($script:percent -lt $target.Percent) {
        $script:percent = [Math]::Min($target.Percent, ($script:percent + 1))
        return
    }

    $script:previewIndex++
    if ($script:previewIndex -ge $script:previewTimeline.Count) {
        Start-Sleep -Milliseconds 350
        $script:previewIndex = 0
        $script:percent = 0
    }
}

function Initialize-LDLCCompactFormType {
    if ('LDLCCompactForm' -as [type]) { return }
    Add-Type -ReferencedAssemblies System.Windows.Forms,System.Drawing @"
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Diagnostics;
using System.Windows.Forms;
public class LDLCCompactForm : Form {
    readonly Timer animation = new Timer();
    readonly Stopwatch clock = Stopwatch.StartNew();
    double last, transitionStart, transitionFrom;
    double displayed;
    int target;
    public int ProgressTarget { get { return target; } }
    public double DisplayedProgress { get { return displayed; } }
    public double SpinnerAngle { get; private set; }
    public int AnimationFrames { get; private set; }
    public bool Running { get; private set; }
    public bool Success { get; private set; }
    public string StatusMessage { get; private set; }
    public string ErrorApplication { get; private set; }
    public LDLCCompactForm() {
        DoubleBuffered = true; FormBorderStyle = FormBorderStyle.None;
        ClientSize = new Size(380,205); BackColor = Color.FromArgb(8,25,46);
        ShowInTaskbar = false; TopMost = true; StartPosition = FormStartPosition.Manual;
        AutoScaleMode = AutoScaleMode.None;
        StatusMessage = "Configuration d'Adobe Acrobat Reader\u2026"; ErrorApplication = "";
        Running = true; Text = "Pr\u00e9paration PC - Applications par d\u00e9faut";
        AccessibleName = Text;
        animation.Interval = 16;
        animation.Tick += delegate {
            double now = clock.Elapsed.TotalMilliseconds;
            if (Running) SpinnerAngle = (SpinnerAngle + Math.Min(80, now-last)*0.24) % 360;
            last = now;
            double t = Math.Min(1, Math.Max(0, (now-transitionStart)/420));
            double ease = t*t*(3-2*t);
            displayed = transitionFrom + (target-transitionFrom)*ease;
            AnimationFrames++; Invalidate();
        };
    }
    public void SetStatus(int percent, string message, bool running, bool success, string error) {
        if (percent != 0 && percent != 50 && percent != 100) throw new ArgumentException("Invalid stage");
        if (percent == 100 && (!success || running || !String.IsNullOrEmpty(error))) throw new ArgumentException("Unconfirmed completion");
        if (percent != target) { transitionFrom = displayed; target = percent; transitionStart = clock.Elapsed.TotalMilliseconds; }
        StatusMessage = (message ?? "").Replace("...", "\u2026").Replace("terminee","termin\u00e9e").Replace("confirmee","confirm\u00e9e").Replace("Selection","S\u00e9lection").Replace("reglages","r\u00e9glages").Replace("resultat","r\u00e9sultat");
        Running = running; Success = success; ErrorApplication = error ?? "";
        AccessibleDescription = StatusMessage + " " + percent + "% " + ErrorApplication;
        Invalidate();
    }
    protected override void OnShown(EventArgs e) { last = clock.Elapsed.TotalMilliseconds; animation.Start(); base.OnShown(e); }
    protected override bool ShowWithoutActivation { get { return true; } }
    protected override CreateParams CreateParams {
        get { CreateParams p = base.CreateParams; p.ExStyle |= 0x08000000 | 0x00000080; return p; }
    }
    protected override void WndProc(ref Message m) {
        if (m.Msg == 0x0021) { m.Result = new IntPtr(3); return; }
        base.WndProc(ref m);
    }
    static GraphicsPath Round(RectangleF r, float radius) {
        GraphicsPath p = new GraphicsPath(); float d = radius*2;
        p.AddArc(r.X,r.Y,d,d,180,90); p.AddArc(r.Right-d,r.Y,d,d,270,90);
        p.AddArc(r.Right-d,r.Bottom-d,d,d,0,90); p.AddArc(r.X,r.Bottom-d,d,d,90,90); p.CloseFigure(); return p;
    }
    protected override void OnSizeChanged(EventArgs e) {
        using (GraphicsPath p = Round(new RectangleF(0,0,Width,Height),18*Width/620f)) {
            Region old = Region; Region = new Region(p); if (old != null) old.Dispose();
        }
        base.OnSizeChanged(e);
    }
    static void TextAt(Graphics g, string text, float size, FontStyle style, Color color, RectangleF rect) {
        using (Font font = new Font("Segoe UI",size,style,GraphicsUnit.Pixel))
        using (Brush brush = new SolidBrush(color))
        using (StringFormat format = new StringFormat()) {
            format.Trimming = StringTrimming.EllipsisCharacter;
            g.DrawString(text,font,brush,rect,format);
        }
    }
    protected override void OnPaint(PaintEventArgs e) {
        Graphics g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias;
        g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
        g.ScaleTransform(ClientSize.Width/620f,ClientSize.Height/334f);
        using (GraphicsPath outer = Round(new RectangleF(1,1,618,332),17))
        using (Brush bg = new LinearGradientBrush(new Point(0,0),new Point(620,334),Color.FromArgb(12,35,60),Color.FromArgb(6,20,38)))
        using (Pen border = new Pen(Color.FromArgb(72,99,127),1.5f)) { g.FillPath(bg,outer); g.DrawPath(border,outer); }
        using (Pen line = new Pen(Color.FromArgb(30,61,88))) g.DrawLine(line,1,45,619,45);
        TextAt(g,"Pr\u00e9paration PC",20,FontStyle.Bold,Color.FromArgb(39,195,238),new RectangleF(20,12,580,30));
        TextAt(g,"Applications par d\u00e9faut",29,FontStyle.Bold,Color.White,new RectangleF(28,63,570,40));
        TextAt(g,"Configuration d'Adobe Acrobat Reader et de Chrome",18,FontStyle.Regular,Color.FromArgb(181,202,224),new RectangleF(28,108,565,26));
        using (GraphicsPath card = Round(new RectangleF(20,144,580,78),12))
        using (Brush bg = new SolidBrush(Color.FromArgb(13,39,66)))
        using (Pen border = new Pen(Color.FromArgb(31,69,105),1.2f)) { g.FillPath(bg,card); g.DrawPath(border,card); }
        Color accent = Success ? Color.FromArgb(72,211,149) : (!Running ? Color.FromArgb(244,108,105) : Color.FromArgb(15,161,249));
        if (Running) {
            using (Pen track = new Pen(Color.FromArgb(25,66,103),5)) g.DrawEllipse(track,40,163,35,35);
            using (Pen arc = new Pen(accent,5)) { arc.StartCap=LineCap.Round; arc.EndCap=LineCap.Round; g.DrawArc(arc,40,163,35,35,(float)SpinnerAngle,100); }
        } else {
            using (Pen pen = new Pen(accent,4)) {
                pen.StartCap=LineCap.Round; pen.EndCap=LineCap.Round;
                if (Success) g.DrawLines(pen,new PointF[]{new PointF(42,181),new PointF(53,192),new PointF(75,169)});
                else { g.DrawLine(pen,45,170,70,195); g.DrawLine(pen,70,170,45,195); }
            }
        }
        TextAt(g,StatusMessage,20,FontStyle.Regular,Color.White,new RectangleF(96,155,490,String.IsNullOrEmpty(ErrorApplication)?52:30));
        if (!String.IsNullOrEmpty(ErrorApplication)) TextAt(g,"\u00c9chec : "+ErrorApplication,12,FontStyle.Regular,Color.FromArgb(255,151,140),new RectangleF(96,187,490,32));
        using (GraphicsPath track = Round(new RectangleF(20,236,580,10),5))
        using (Brush brush = new SolidBrush(Color.FromArgb(25,57,89))) g.FillPath(brush,track);
        if (displayed > 0.1) {
            using (GraphicsPath bar = Round(new RectangleF(20,236,(float)(580*displayed/100),10),Math.Min(5,(float)(580*displayed/200))))
            using (Brush brush = new SolidBrush(accent)) g.FillPath(brush,bar);
        }
        TextAt(g,target+" %",16,FontStyle.Bold,Color.FromArgb(181,202,224),new RectangleF(554,250,50,24));
        using (GraphicsPath warning = Round(new RectangleF(20,278,580,38),10))
        using (Brush brush = new SolidBrush(Color.FromArgb(49,43,28)))
        using (Pen pen = new Pen(Color.FromArgb(115,86,32),1)) { g.FillPath(brush,warning); g.DrawPath(pen,warning); }
        TextAt(g,"Ne touchez pas au clavier ni \u00e0 la souris.",19,FontStyle.Regular,Color.FromArgb(255,202,94),new RectangleF(38,286,550,27));
    }
    protected override void Dispose(bool disposing) { if (disposing) animation.Dispose(); base.Dispose(disposing); }
}
"@
}

function New-LDLCCompactForm {
    Initialize-LDLCCompactFormType
    $compact = New-Object LDLCCompactForm
    return $compact
}
function Set-LDLCCompactUiState {
    param($MainForm, [bool]$Active)
    if ($Active -eq [bool]$script:LDLCCompactUiState) { return }
    if ($Active) {
        $script:LDLCCompactUiState = @{ WindowState = $MainForm.WindowState; TopMost = $MainForm.TopMost }
        try {
            $script:LDLCCompactForm = New-LDLCCompactForm
            $MainForm.TopMost = $false
            $MainForm.WindowState = [System.Windows.Forms.FormWindowState]::Minimized
            # No owner: a minimized owner would also hide the compact form.
            $area = [System.Windows.Forms.Screen]::FromControl($MainForm).WorkingArea
            $script:LDLCCompactForm.Left = $area.Left + 16
            $script:LDLCCompactForm.Top = [Math]::Max($area.Top, $area.Bottom - $script:LDLCCompactForm.Height - 16)
            $script:LDLCCompactForm.Show()
            $script:LDLCCompactForm.Top = [Math]::Max($area.Top, $area.Bottom - $script:LDLCCompactForm.Height - 16)
        }
        catch {
            Set-LDLCCompactUiState -MainForm $MainForm -Active $false
            throw
        }
        return
    }
    try {
        if ($script:LDLCCompactForm) { $script:LDLCCompactForm.Close(); $script:LDLCCompactForm.Dispose() }
    }
    finally {
        $script:LDLCCompactForm = $null
        try {
            $MainForm.WindowState = $script:LDLCCompactUiState.WindowState
            $MainForm.TopMost = $script:LDLCCompactUiState.TopMost
        }
        finally { $script:LDLCCompactUiState = $null }
    }
}

function Read-LDLCCompactUiSignal {
    param([string]$RuntimeRoot, $Worker)
    if (-not $Worker -or $Worker.HasExited) { return $null }
    $path = Join-Path $RuntimeRoot "LDLC_DEFAULT_APPS.$($Worker.Id).json"
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try {
        $stream = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
        $reader = New-Object IO.StreamReader($stream)
        try { $signal = $reader.ReadToEnd() | ConvertFrom-Json -ErrorAction Stop }
        finally { $reader.Dispose() }
        if ($signal.Active -eq $true -and $signal.WorkerId -eq $Worker.Id) {
            $script:LDLCCompactLastSignal = $signal
            return $signal
        }
        return $null
    }
    catch {
        # A partial write must not restore/reminimize the form on consecutive ticks.
        if ($script:LDLCCompactLastSignal -and $script:LDLCCompactLastSignal.WorkerId -eq $Worker.Id) { return $script:LDLCCompactLastSignal }
        return $null
    }
}

function Confirm-LDLCCompactUiSignal {
    param($Form, $Signal, [string]$RuntimeRoot)
    $path = Join-Path $RuntimeRoot "LDLC_DEFAULT_APPS.$($Signal.WorkerId).json.ack"
    $revision = [long]$Signal.Revision
    if ($script:LDLCCompactAckPath -eq $path -and $script:LDLCCompactAckRevision -eq $revision -and (Test-Path -LiteralPath $path)) { return }
    # Paint the new text before acknowledging it; do not activate or focus this form.
    $Form.Update()
    $ack = [ordered]@{
        WorkerId = $Signal.WorkerId; Revision = $revision; Progress = $Form.ProgressTarget
        Message = $Form.StatusMessage; Running = $Form.Running; Success = $Form.Success
        RenderedAt = [DateTime]::UtcNow.ToString('o'); AnimationFrames = $Form.AnimationFrames; SpinnerAngle = $Form.SpinnerAngle
    }
    $temporary = $path + '.tmp'
    try {
        [IO.File]::WriteAllText($temporary, ($ack | ConvertTo-Json -Compress))
        if (Test-Path -LiteralPath $path) { [IO.File]::Replace($temporary, $path, [NullString]::Value) }
        else { [IO.File]::Move($temporary, $path) }
        $script:LDLCCompactAckPath = $path; $script:LDLCCompactAckRevision = $revision
        return [pscustomobject]$ack
    }
    catch [IO.IOException] { return }
    finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue } }
}

function Update-LDLCCompactUi {
    param($MainForm, [string]$RuntimeRoot, $Worker)
    $signal = Read-LDLCCompactUiSignal -RuntimeRoot $RuntimeRoot -Worker $Worker
    $active = [bool]$signal
    Set-LDLCCompactUiState -MainForm $MainForm -Active $active
    if ($active -and $script:LDLCCompactUiState) {
        if ($signal.PSObject.Properties['Progress']) {
            $script:LDLCCompactForm.SetStatus([int]$signal.Progress, [string]$signal.Message,
                [bool]$signal.Running, [bool]$signal.Success, [string]$signal.ErrorApplication)
        }
        Confirm-LDLCCompactUiSignal -Form $script:LDLCCompactForm -Signal $signal -RuntimeRoot $RuntimeRoot | Out-Null
    }
}

function Test-LDLCUiFinalizationReady {
    if (-not $script:proc) { return $false }
    try {
        return (Test-LDLCFinalizationReady -RuntimeRoot $script:runtimeRoot -WorkerProcessId $script:proc.Id -WorkerStartTicks $script:proc.StartTime.ToUniversalTime().Ticks)
    }
    catch { return $false }
}

function Stop-LDLCProcessTree {
    param([int]$ProcessId)

    try {
        $children = Get-CimInstance Win32_Process -Filter "ParentProcessId = $ProcessId" -ErrorAction SilentlyContinue
        foreach ($child in $children) {
            Stop-LDLCProcessTree -ProcessId $child.ProcessId
        }
    }
    catch {}

    try {
        Stop-Process -Id $ProcessId -Force -Confirm:$false -ErrorAction SilentlyContinue
    }
    catch {}
}

function New-RoundedRectanglePath {
    param(
        [System.Drawing.RectangleF]$Bounds,
        [float]$Radius
    )

    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $safeRadius = [Math]::Max(0, [Math]::Min($Radius, ([Math]::Min($Bounds.Width, $Bounds.Height) / 2)))
    $diameter = $safeRadius * 2

    if ($diameter -le 0) {
        $path.AddRectangle($Bounds)
        return $path
    }

    $path.AddArc($Bounds.X, $Bounds.Y, $diameter, $diameter, 180, 90)
    $path.AddArc(($Bounds.Right - $diameter), $Bounds.Y, $diameter, $diameter, 270, 90)
    $path.AddArc(($Bounds.Right - $diameter), ($Bounds.Bottom - $diameter), $diameter, $diameter, 0, 90)
    $path.AddArc($Bounds.X, ($Bounds.Bottom - $diameter), $diameter, $diameter, 90, 90)
    $path.CloseFigure()
    return $path
}

function Initialize-LDLCUiPixelBuffer {
    if ('LDLCUiPixelBuffer' -as [type]) { return }

    # Keep the original alpha/mask rules; run the pixel loops outside PowerShell.
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;

public static class LDLCUiPixelBuffer
{
    public static void RemoveFringe(byte[] pixels, int width, int height, int stride,
        int cutoff, byte red, byte green, byte blue, bool preserveZeroAlpha)
    {
        for (int y = 0; y < height; y++)
        {
            for (int x = 0, offset = y * stride; x < width; x++, offset += 4)
            {
                byte alpha = pixels[offset + 3];
                if (preserveZeroAlpha && alpha == 0) continue;
                if (alpha < cutoff)
                {
                    pixels[offset] = blue;
                    pixels[offset + 1] = green;
                    pixels[offset + 2] = red;
                    pixels[offset + 3] = 0;
                }
                else if (alpha < 255) pixels[offset + 3] = 255;
            }
        }
    }

    // Each visible horizontal run is (x, y, length), in the original order.
    public static int[] GetAlphaRuns(byte[] pixels, int width, int height, int stride, int threshold)
    {
        List<int> runs = new List<int>();
        for (int y = 0; y < height; y++)
        {
            int start = -1;
            for (int x = 0; x < width; x++)
            {
                bool visible = pixels[y * stride + x * 4 + 3] >= threshold;
                if (visible && start < 0) start = x;
                else if (!visible && start >= 0)
                {
                    runs.Add(start); runs.Add(y); runs.Add(x - start);
                    start = -1;
                }
            }
            if (start >= 0)
            {
                runs.Add(start); runs.Add(y); runs.Add(width - start);
            }
        }
        return runs.ToArray();
    }

    public static void ApplyRoundedMask(byte[] pixels, int width, int height, int stride,
        double radius, byte red, byte green, byte blue)
    {
        for (int y = 0; y < height; y++)
        {
            for (int x = 0; x < width; x++)
            {
                double cx, cy;
                if (x < radius && y < radius) { cx = radius; cy = radius; }
                else if (x >= width - radius && y < radius) { cx = width - radius - 1; cy = radius; }
                else if (x < radius && y >= height - radius) { cx = radius; cy = height - radius - 1; }
                else if (x >= width - radius && y >= height - radius) { cx = width - radius - 1; cy = height - radius - 1; }
                else continue;
                double dx = x - cx, dy = y - cy;
                if (dx * dx + dy * dy <= radius * radius) continue;
                int offset = y * stride + x * 4;
                pixels[offset] = blue;
                pixels[offset + 1] = green;
                pixels[offset + 2] = red;
                pixels[offset + 3] = 0;
            }
        }
    }
}
'@
}

function New-LDLCBitmapAlphaRegion {
    param(
        [Parameter(Mandatory = $true)][System.Drawing.Bitmap]$Bitmap,
        [int]$AlphaThreshold = 32
    )

    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $rect = New-Object System.Drawing.Rectangle 0, 0, $Bitmap.Width, $Bitmap.Height
    $data = $Bitmap.LockBits(
        $rect,
        [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
    )

    try {
        $stride = [Math]::Abs($data.Stride)
        $bytes = New-Object byte[] ($stride * $Bitmap.Height)
        [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $bytes.Length)

        Initialize-LDLCUiPixelBuffer
        $runs = [LDLCUiPixelBuffer]::GetAlphaRuns($bytes, $Bitmap.Width, $Bitmap.Height, $stride, $AlphaThreshold)
        for ($i = 0; $i -lt $runs.Length; $i += 3) {
            $path.AddRectangle((New-Object System.Drawing.Rectangle -ArgumentList $runs[$i], $runs[$i + 1], $runs[$i + 2], 1))
        }
    }
    finally {
        $Bitmap.UnlockBits($data)
    }

    if ($path.PointCount -eq 0) {
        $path.Dispose()
        return $null
    }

    $region = New-Object System.Drawing.Region $path
    $path.Dispose()
    return $region
}

function Remove-LDLCBitmapAlphaFringe {
    param(
        [Parameter(Mandatory = $true)][System.Drawing.Bitmap]$Bitmap,
        [int]$AlphaCutoff = 245,
        [System.Drawing.Color]$TransparentColor = ([System.Drawing.Color]::FromArgb(17, 18, 19))
    )

    $rect = New-Object System.Drawing.Rectangle 0, 0, $Bitmap.Width, $Bitmap.Height
    $data = $Bitmap.LockBits(
        $rect,
        [System.Drawing.Imaging.ImageLockMode]::ReadWrite,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
    )

    try {
        $stride = [Math]::Abs($data.Stride)
        $bytes = New-Object byte[] ($stride * $Bitmap.Height)
        [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $bytes.Length)

        Initialize-LDLCUiPixelBuffer
        [LDLCUiPixelBuffer]::RemoveFringe($bytes, $Bitmap.Width, $Bitmap.Height, $stride,
            $AlphaCutoff, $TransparentColor.R, $TransparentColor.G, $TransparentColor.B, $false)

        [System.Runtime.InteropServices.Marshal]::Copy($bytes, 0, $data.Scan0, $bytes.Length)
    }
    finally {
        $Bitmap.UnlockBits($data)
    }
}

function Apply-LDLCBitmapRoundedWindowMask {
    param(
        [Parameter(Mandatory = $true)][System.Drawing.Bitmap]$Bitmap,
        [Parameter(Mandatory = $true)][int]$Radius,
        [System.Drawing.Color]$TransparentColor = ([System.Drawing.Color]::FromArgb(17, 18, 19))
    )

    $safeRadius = [Math]::Max(1, [Math]::Min($Radius, [Math]::Min($Bitmap.Width, $Bitmap.Height) / 2))
    $rect = New-Object System.Drawing.Rectangle 0, 0, $Bitmap.Width, $Bitmap.Height
    $data = $Bitmap.LockBits(
        $rect,
        [System.Drawing.Imaging.ImageLockMode]::ReadWrite,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
    )

    try {
        $stride = [Math]::Abs($data.Stride)
        $bytes = New-Object byte[] ($stride * $Bitmap.Height)
        [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $bytes.Length)

        Initialize-LDLCUiPixelBuffer
        [LDLCUiPixelBuffer]::ApplyRoundedMask($bytes, $Bitmap.Width, $Bitmap.Height, $stride,
            $safeRadius, $TransparentColor.R, $TransparentColor.G, $TransparentColor.B)

        [System.Runtime.InteropServices.Marshal]::Copy($bytes, 0, $data.Scan0, $bytes.Length)
    }
    finally {
        $Bitmap.UnlockBits($data)
    }
}

function Resize-LDLCBackgroundBitmap {
    param(
        [Parameter(Mandatory = $true)][System.Drawing.Image]$Image,
        [Parameter(Mandatory = $true)][int]$Width,
        [Parameter(Mandatory = $true)][int]$Height
    )

    $bitmap = New-Object System.Drawing.Bitmap $Width, $Height, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)

    try {
        $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $targetRect = New-Object System.Drawing.Rectangle 0, 0, $Width, $Height
        $sourceRect = New-Object System.Drawing.Rectangle 0, 0, $Image.Width, $Image.Height
        $graphics.DrawImage($Image, $targetRect, $sourceRect, [System.Drawing.GraphicsUnit]::Pixel)
    }
    finally {
        $graphics.Dispose()
    }

    return $bitmap
}

function New-LDLCRoundedWindowRegion {
    param(
        [Parameter(Mandatory = $true)][int]$Width,
        [Parameter(Mandatory = $true)][int]$Height
    )

    $bounds = New-Object System.Drawing.RectangleF 0, 0, $Width, $Height
    $path = New-RoundedRectanglePath -Bounds $bounds -Radius (Convert-X 72)

    try {
        return (New-Object System.Drawing.Region $path)
    }
    finally {
        $path.Dispose()
    }
}

function New-StagePath {
    param([System.Drawing.RectangleF]$Bounds)

    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $cut = Convert-X 28
    $radius = Convert-X 18

    $path.StartFigure()
    $path.AddArc($Bounds.X, $Bounds.Y, ($radius * 2), ($radius * 2), 180, 90)
    $path.AddLine(($Bounds.X + $radius), $Bounds.Y, ($Bounds.Right - $cut), $Bounds.Y)
    $path.AddLine(($Bounds.Right - $cut), $Bounds.Y, $Bounds.Right, ($Bounds.Y + ($Bounds.Height / 2)))
    $path.AddLine($Bounds.Right, ($Bounds.Y + ($Bounds.Height / 2)), ($Bounds.Right - $cut), $Bounds.Bottom)
    $path.AddLine(($Bounds.Right - $cut), $Bounds.Bottom, ($Bounds.X + $radius), $Bounds.Bottom)
    $path.AddArc($Bounds.X, ($Bounds.Bottom - ($radius * 2)), ($radius * 2), ($radius * 2), 90, 90)
    $path.CloseFigure()
    return $path
}

function Draw-LDLCStageList {
    param(
        [System.Drawing.Graphics]$Graphics,
        [int]$ActiveIndex
    )

    $overlayBounds = New-Object System.Drawing.RectangleF((Convert-X 50), (Convert-Y 175), (Convert-X 430), (Convert-Y 475))
    $overlayPath = New-RoundedRectanglePath -Bounds $overlayBounds -Radius (Convert-X 18)
    $overlayBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 2, 18, 45))
    $Graphics.FillPath($overlayBrush, $overlayPath)
    $overlayBrush.Dispose()
    $overlayPath.Dispose()

    $fontTitle = New-Object System.Drawing.Font('Segoe UI', (Convert-FontSize 20 7), [System.Drawing.FontStyle]::Bold)
    $fontDetail = New-Object System.Drawing.Font('Segoe UI', (Convert-FontSize 13 6.5), [System.Drawing.FontStyle]::Regular)
    $fontNumber = New-Object System.Drawing.Font('Segoe UI', (Convert-FontSize 22 7), [System.Drawing.FontStyle]::Bold)
    $textFormat = New-Object System.Drawing.StringFormat
    $textFormat.Trimming = [System.Drawing.StringTrimming]::EllipsisCharacter
    $textFormat.FormatFlags = [System.Drawing.StringFormatFlags]::NoWrap

    for ($i = 0; $i -lt $script:phases.Count; $i++) {
        $y = 192 + ($i * 112)
        $bounds = New-Object System.Drawing.RectangleF((Convert-X 67), (Convert-Y $y), (Convert-X 417), (Convert-Y 90))
        $circleBounds = New-Object System.Drawing.RectangleF((Convert-X 88), (Convert-Y ($y + 12)), (Convert-X 58), (Convert-Y 58))
        $isActive = ($i -eq $ActiveIndex)

        if ($isActive) {
            $stagePath = New-StagePath -Bounds $bounds
            $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($bounds, [System.Drawing.Color]::FromArgb(255, 12, 145, 255), [System.Drawing.Color]::FromArgb(255, 0, 68, 218), 0)
            $Graphics.FillPath($brush, $stagePath)
            $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(230, 170, 225, 255), (Convert-X 1))
            $Graphics.DrawPath($pen, $stagePath)
            $pen.Dispose()
            $brush.Dispose()
            $stagePath.Dispose()

            $numberFill = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(230, 240, 248, 255))
            $numberPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 40, 145, 255), (Convert-X 3))
            $titleBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
            $detailBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(252, 232, 246, 255))
        }
        else {
            $stagePath = New-RoundedRectanglePath -Bounds $bounds -Radius (Convert-X 16)
            $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 8, 24, 56))
            $Graphics.FillPath($brush, $stagePath)
            $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(70, 60, 130, 200), (Convert-X 1))
            $Graphics.DrawPath($pen, $stagePath)
            $pen.Dispose()
            $brush.Dispose()
            $stagePath.Dispose()

            $numberFill = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 18, 40, 76))
            $numberPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(130, 95, 135, 180), (Convert-X 2))
            $titleBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(245, 230, 240, 255))
            $detailBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(225, 205, 225, 248))
        }

        $Graphics.FillEllipse($numberFill, $circleBounds)
        $Graphics.DrawEllipse($numberPen, $circleBounds)

        $numberFormat = New-Object System.Drawing.StringFormat
        $numberFormat.Alignment = 'Center'
        $numberFormat.LineAlignment = 'Center'
        Draw-LDLCTextWithShadow -Graphics $Graphics -Text ([string]($i + 1)) -Font $fontNumber -Brush $titleBrush -Bounds $circleBounds -Format $numberFormat -ShadowAlpha 155
        $titleRect = New-Object System.Drawing.RectangleF((Convert-X 152), (Convert-Y ($y + 10)), (Convert-X 300), (Convert-Y 44))
        $detailRect = New-Object System.Drawing.RectangleF((Convert-X 152), (Convert-Y ($y + 54)), (Convert-X 300), (Convert-Y 28))
        Draw-LDLCTextWithShadow -Graphics $Graphics -Text $script:phases[$i].Name -Font $fontTitle -Brush $titleBrush -Bounds $titleRect -Format $textFormat
        Draw-LDLCTextWithShadow -Graphics $Graphics -Text $script:phases[$i].Detail -Font $fontDetail -Brush $detailBrush -Bounds $detailRect -Format $textFormat

        $numberFormat.Dispose()
        $numberFill.Dispose()
        $numberPen.Dispose()
        $titleBrush.Dispose()
        $detailBrush.Dispose()
    }

    $fontTitle.Dispose()
    $fontDetail.Dispose()
    $fontNumber.Dispose()
    $textFormat.Dispose()
}

function Draw-LDLCProgressArea {
    param([System.Drawing.Graphics]$Graphics)

    $statusFont = New-Object System.Drawing.Font('Segoe UI', (Convert-FontSize 27 8), [System.Drawing.FontStyle]::Bold)
    $detailFont = New-Object System.Drawing.Font('Segoe UI', (Convert-FontSize 18 8.5), [System.Drawing.FontStyle]::Regular)
    $percentFont = New-Object System.Drawing.Font('Segoe UI', (Convert-FontSize 34 10), [System.Drawing.FontStyle]::Bold)
    $metaFont = New-Object System.Drawing.Font('Segoe UI', (Convert-FontSize 14 7.5), [System.Drawing.FontStyle]::Regular)
    $textFormat = New-Object System.Drawing.StringFormat
    $textFormat.Trimming = [System.Drawing.StringTrimming]::EllipsisCharacter
    $textFormat.FormatFlags = [System.Drawing.StringFormatFlags]::NoWrap

    $whiteBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $blueTextBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 105, 205, 255))
    $softBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(235, 205, 228, 255))

    $status = Limit-LDLCText -Text (Get-LDLCStatusTitle -Percent ([int]$script:percent)) -MaxLength 48
    $detail = Limit-LDLCText -Text $script:message -MaxLength 82
    $meta = if ($Preview) { 'MODE PREVISUALISATION - aucune installation lancee' } else { 'Progression en temps reel' }

    $statusRect = New-Object System.Drawing.RectangleF((Convert-X 548), (Convert-Y 552), (Convert-X 790), (Convert-Y 50))
    # Minimum font sizes stay readable even when the entire window is scaled
    # down. Reserve their real pixel height instead of scaling the text box
    # below the font height (notably on the small GitHub runner desktop).
    $detailHeight = [Math]::Max((Convert-Y 32), [Math]::Ceiling($detailFont.GetHeight($Graphics)) + 2)
    $metaHeight = [Math]::Max((Convert-Y 26), [Math]::Ceiling($metaFont.GetHeight($Graphics)) + 2)
    $detailRect = New-Object System.Drawing.RectangleF((Convert-X 548), (Convert-Y 648), (Convert-X 805), $detailHeight)
    $metaTop = [Math]::Max((Convert-Y 684), $detailRect.Bottom + 1)
    $metaRect = New-Object System.Drawing.RectangleF((Convert-X 548), $metaTop, (Convert-X 805), $metaHeight)
    Draw-LDLCTextWithShadow -Graphics $Graphics -Text $status -Font $statusFont -Brush $whiteBrush -Bounds $statusRect -Format $textFormat -ShadowAlpha 210
    Draw-LDLCTextWithShadow -Graphics $Graphics -Text $detail -Font $detailFont -Brush $blueTextBrush -Bounds $detailRect -Format $textFormat -ShadowAlpha 190
    Draw-LDLCTextWithShadow -Graphics $Graphics -Text $meta -Font $metaFont -Brush $softBrush -Bounds $metaRect -Format $textFormat -ShadowAlpha 180

    $barBounds = New-Object System.Drawing.RectangleF((Convert-X 548), (Convert-Y 608), (Convert-X 832), (Convert-Y 35))
    $barPath = New-RoundedRectanglePath -Bounds $barBounds -Radius (Convert-X 18)
    $barBack = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(210, 2, 28, 72))
    $barPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 20, 145, 255), (Convert-X 1))
    $Graphics.FillPath($barBack, $barPath)

    $fillBrush = $null
    $fillPath = $null
    if ($script:percent -gt 0) {
        $innerBarBounds = New-Object System.Drawing.RectangleF(
            ($barBounds.X + (Convert-X 1)),
            ($barBounds.Y + (Convert-Y 1)),
            ($barBounds.Width - (Convert-X 2)),
            ($barBounds.Height - (Convert-Y 2))
        )
        $fillWidth = [Math]::Min($innerBarBounds.Width, [Math]::Max((Convert-X 6), [single]($innerBarBounds.Width * ($script:percent / 100))))
        $fillBounds = New-Object System.Drawing.RectangleF($innerBarBounds.X, $innerBarBounds.Y, $fillWidth, $innerBarBounds.Height)
        $fillPath = New-RoundedRectanglePath -Bounds $fillBounds -Radius ($innerBarBounds.Height / 2)
        $fillBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($innerBarBounds, [System.Drawing.Color]::FromArgb(255, 0, 182, 255), [System.Drawing.Color]::FromArgb(255, 0, 89, 255), 0)
        $Graphics.FillPath($fillBrush, $fillPath)
    }

    $Graphics.DrawPath($barPen, $barPath)

    $percentText = "$([int]$script:percent)%"
    $percentRect = New-Object System.Drawing.RectangleF((Convert-X 1410), (Convert-Y 584), (Convert-X 135), (Convert-Y 70))
    Draw-LDLCTextWithShadow -Graphics $Graphics -Text $percentText -Font $percentFont -Brush $whiteBrush -Bounds $percentRect -ShadowAlpha 210

    if ($fillBrush) { $fillBrush.Dispose() }
    if ($fillPath) { $fillPath.Dispose() }
    $barPen.Dispose()
    $barBack.Dispose()
    $barPath.Dispose()
    $whiteBrush.Dispose()
    $blueTextBrush.Dispose()
    $softBrush.Dispose()
    $statusFont.Dispose()
    $detailFont.Dispose()
    $percentFont.Dispose()
    $metaFont.Dispose()
    $textFormat.Dispose()
}

function Draw-LDLCVersionOverlay {
    param([System.Drawing.Graphics]$Graphics)

    $versionFont = New-Object System.Drawing.Font('Segoe UI', (Convert-FontSize 12 7), [System.Drawing.FontStyle]::Regular)
    $format = New-Object System.Drawing.StringFormat
    $format.Alignment = 'Center'
    $format.LineAlignment = 'Center'
    $format.Trimming = [System.Drawing.StringTrimming]::EllipsisCharacter
    $format.FormatFlags = [System.Drawing.StringFormatFlags]::NoWrap

    $versionBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(240, 215, 235, 255))
    $versionText = New-Object System.Drawing.RectangleF((Convert-X 58), (Convert-Y 720), (Convert-X 235), (Convert-Y 28))

    Draw-LDLCTextWithShadow -Graphics $Graphics -Text $script:LDLCAppVersionLabel -Font $versionFont -Brush $versionBrush -Bounds $versionText -Format $format -ShadowAlpha 180

    $versionFont.Dispose()
    $format.Dispose()
    $versionBrush.Dispose()
}

try {
    Remove-Item $script:progressFile -ErrorAction SilentlyContinue
    if (-not $Preview) {
        Remove-Item $script:stopFile -Force -ErrorAction SilentlyContinue
    }

    $bgOriginal = [System.Drawing.Image]::FromFile($bgPath)
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $maxWidth = [int]($screen.Width * 0.47)
    $maxHeight = [int]($screen.Height * 0.47)
    $scale = [Math]::Min($maxWidth / $bgOriginal.Width, $maxHeight / $bgOriginal.Height)
    if ($scale -gt 1) { $scale = 1 }

    $displayWidth = [int]($bgOriginal.Width * $scale)
    $displayHeight = [int]($bgOriginal.Height * $scale)
    $script:scaleX = $displayWidth / $bgOriginal.Width
    $script:scaleY = $displayHeight / $bgOriginal.Height

    $transparentKey = [System.Drawing.Color]::FromArgb(17, 18, 19)
    $bg = Resize-LDLCBackgroundBitmap -Image $bgOriginal -Width $displayWidth -Height $displayHeight
    Apply-LDLCBitmapRoundedWindowMask -Bitmap $bg -Radius (Convert-X 72) -TransparentColor $transparentKey
    Remove-LDLCBitmapAlphaFringe -Bitmap $bg -AlphaCutoff 254 -TransparentColor $transparentKey

    $form = New-Object System.Windows.Forms.Form
    $form.Text = if ($Preview) { 'LDLC UI Preview' } else { 'LDLC Preparation PC' }
    $form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
    $form.FormBorderStyle = 'None'
    $form.StartPosition = 'Manual'
    $form.TopMost = $true
    $form.ShowInTaskbar = $true
    $form.Padding = New-Object System.Windows.Forms.Padding 0
    $form.Margin = New-Object System.Windows.Forms.Padding 0
    $form.ClientSize = New-Object System.Drawing.Size $displayWidth, $displayHeight
    $form.Left = $screen.Left + 20
    $form.Top = [Math]::Max($screen.Top, ($screen.Bottom - $form.Height - 20))
    $form.BackColor = $transparentKey
    $form.TransparencyKey = $transparentKey
    $form.KeyPreview = $true
    $form.Cursor = 'AppStarting'
    $form.Region = New-LDLCBitmapAlphaRegion -Bitmap $bg -AlphaThreshold 254
    if (-not $form.Region) {
        $form.Region = New-LDLCRoundedWindowRegion -Width $displayWidth -Height $displayHeight
    }

    $picture = New-Object System.Windows.Forms.PictureBox
    $picture.Image = $bg
    $picture.Dock = 'Fill'
    $picture.SizeMode = 'StretchImage'
    $picture.BackColor = $transparentKey
    $picture.Margin = New-Object System.Windows.Forms.Padding 0
    $picture.Padding = New-Object System.Windows.Forms.Padding 0
    $form.Controls.Add($picture)

    $overlay = New-Object System.Windows.Forms.Panel
    $overlay.Dock = 'Fill'
    $overlay.BackColor = [System.Drawing.Color]::Transparent
    $overlay.Margin = New-Object System.Windows.Forms.Padding 0
    $overlay.Padding = New-Object System.Windows.Forms.Padding 0
    $doubleBufferedProperty = $overlay.GetType().GetProperty(
        'DoubleBuffered',
        [System.Reflection.BindingFlags]'NonPublic, Instance'
    )
    if ($doubleBufferedProperty) {
        $doubleBufferedProperty.SetValue($overlay, $true, $null)
    }
    $picture.Controls.Add($overlay)

    $closeButton = New-Object System.Windows.Forms.Button
    $closeButton.Text = 'Quitter'
    # Footer alignment shared with the Numerik's reference; keep a usable target at small resolutions.
    $closeButton.Width = [Math]::Max(50, (Convert-X 174))
    $closeButton.Height = [Math]::Max(14, (Convert-Y 34))
    $closeButton.Left = [Math]::Min((Convert-X 1450), ($displayWidth - $closeButton.Width - 2))
    $closeButton.Top = [Math]::Min((Convert-Y 725), ($displayHeight - $closeButton.Height - [Math]::Max(2, (Convert-Y 13))))
    $closeButton.FlatStyle = 'Flat'
    $closeButton.FlatAppearance.BorderSize = 0
    $closeButton.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(245, 55, 55)
    $closeButton.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(170, 20, 20)
    $closeButton.BackColor = [System.Drawing.Color]::FromArgb(215, 35, 35)
    $closeButton.ForeColor = 'White'
    $closeButton.Font = New-Object System.Drawing.Font('Segoe UI', (Convert-FontSize 17 7.5), [System.Drawing.FontStyle]::Bold)
    # A point-size floor can otherwise exceed the scaled button's pixel height.
    while ($closeButton.Font.Size -gt 5.5 -and
        [System.Windows.Forms.TextRenderer]::MeasureText($closeButton.Text, $closeButton.Font).Height -gt ($closeButton.Height - 2)) {
        $previousFont = $closeButton.Font
        $closeButton.Font = New-Object System.Drawing.Font('Segoe UI', ($previousFont.Size - 0.5), [System.Drawing.FontStyle]::Bold)
        $previousFont.Dispose()
    }
    $closeButton.Cursor = 'Hand'
    $closeButton.TabStop = $false
    $overlay.Controls.Add($closeButton)

    $script:closeMouseArmedUntil = [datetime]::MinValue
    $script:allowFormClose = [bool]$Preview
    $closeButton.Add_MouseDown({
        if ($_.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
            $script:closeMouseArmedUntil = (Get-Date).AddMilliseconds(750)
        }
    })
    $closeButton.Add_KeyDown({
        if ($_.KeyCode -eq 'Enter' -or $_.KeyCode -eq 'Space') {
            $_.Handled = $true
            $_.SuppressKeyPress = $true
        }
    })
    $closeButton.Add_KeyUp({
        if ($_.KeyCode -eq 'Enter' -or $_.KeyCode -eq 'Space') {
            $_.Handled = $true
            $_.SuppressKeyPress = $true
        }
    })
    $closeButton.Add_MouseEnter({ $closeButton.BackColor = [System.Drawing.Color]::FromArgb(245, 55, 55) })
    $closeButton.Add_MouseLeave({ $closeButton.BackColor = [System.Drawing.Color]::FromArgb(215, 35, 35) })

    # Launch only after the first overlay paint has returned to the message loop.
    $workerStartTimer = New-Object System.Windows.Forms.Timer
    $workerStartTimer.Interval = 1
    $workerStartTimer.Add_Tick({
        $workerStartTimer.Stop()
        if ($script:workerLaunchAttempted -or $Preview -or $script:closing -or $form.IsDisposed -or $form.Disposing) {
            return
        }
        $script:workerLaunchAttempted = $true

        if (-not $Preview) {
            $previousCompactUi = $env:LDLC_DEFAULT_APPS_UI
            try {
                $env:LDLC_DEFAULT_APPS_UI = '1'
                if ($WorkerLauncher) {
                    $script:proc = & $WorkerLauncher
                }
                elseif (Get-Command Start-LDLCInstance -ErrorAction SilentlyContinue) {
                    $script:proc = Start-LDLCInstance -Arguments @('-InstallWorker')
                }
                else {
                    throw 'Lanceur interne indisponible.'
                }
            }
            catch {
                $script:proc = $null
                $script:message = 'Demarrage bloque. Consulte le message de securite et LDLC_BOOTSTRAP.log.'
                $script:percent = 0
            }
            finally {
                if ($null -eq $previousCompactUi) { Remove-Item Env:\LDLC_DEFAULT_APPS_UI -ErrorAction SilentlyContinue }
                else { $env:LDLC_DEFAULT_APPS_UI = $previousCompactUi }
            }
        }
    })

    $overlay.Add_Paint({
        param($sender, $eventArgs)

        $graphics = $eventArgs.Graphics
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit

        $activeIndex = Get-LDLCPhaseIndex -Percent ([int]$script:percent)
        Draw-LDLCVersionOverlay -Graphics $graphics
        Draw-LDLCStageList -Graphics $graphics -ActiveIndex $activeIndex
        Draw-LDLCProgressArea -Graphics $graphics

        if (-not $script:uiFirstPaintCompleted) {
            $script:uiFirstPaintCompleted = $true
            if (-not $Preview -and -not $script:closing) {
                $workerStartTimer.Start()
            }
        }
    })

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 250
    $timer.Add_Tick({
        $previousDisplay = "$($script:percent)|$($script:message)"
        if ($Preview) {
            Update-LDLCPreviewProgress
        }
        else {
            Read-LDLCProgressFile
            try { Update-LDLCCompactUi -MainForm $form -RuntimeRoot $script:runtimeRoot -Worker $script:proc }
            catch {
                Set-LDLCCompactUiState -MainForm $form -Active $false
                $script:message = 'Mode compact indisponible. Configuration des applications par defaut en cours.'
            }

            if ($script:proc -and $script:proc.HasExited) {
                $form.Cursor = 'Default'
                if ($script:percent -lt 100 -and -not $script:closing) {
                    $script:message = 'Script termine avant 100%. Consulte la console ou les logs.'
                }
            }
        }

        if ($script:closing) {
            if (Test-LDLCUiFinalizationReady) {
                $script:allowFormClose = $true
                $form.Close()
                return
            }
            $script:closeStep++

            if ($Preview) {
                $script:allowFormClose = $true
                $form.Close()
                return
            }

            if (-not $script:stopFileCreated) {
                try {
                    New-Item $script:stopFile -ItemType File -Force | Out-Null
                }
                catch {}

                $script:stopFileCreated = $true
                $script:message = 'Arret demande, attente de fermeture propre...'
            }

            if (-not $script:proc -or $script:proc.HasExited) {
                $script:message = 'Installation arretee proprement.'
                $script:allowFormClose = $true
                $form.Close()
                return
            }

            $elapsedSeconds = 0
            if ($script:closeRequestedAt) {
                $elapsedSeconds = ((Get-Date) - $script:closeRequestedAt).TotalSeconds
            }

            if ($elapsedSeconds -ge $script:gracefulStopTimeoutSeconds -and -not $script:forceStopDone) {
                $script:message = 'Arret force du processus bloque...'
                Stop-LDLCProcessTree -ProcessId $script:proc.Id
                $script:forceStopDone = $true
            }

            if ($script:forceStopDone -and ($elapsedSeconds -ge $script:closeAfterForceSeconds)) {
                $script:allowFormClose = $true
                $form.Close()
                return
            }
        }

        if (-not $script:LDLCCompactUiState -and $previousDisplay -ne "$($script:percent)|$($script:message)") {
            $overlay.Invalidate()
        }
    })

    $closeButton.Add_Click({
        if ((Get-Date) -gt $script:closeMouseArmedUntil) {
            return
        }
        $script:closeMouseArmedUntil = [datetime]::MinValue

        if ($Preview) {
            $script:allowFormClose = $true
            $form.Close()
            return
        }

        if ($script:closing) { return }
        if (Test-LDLCUiFinalizationReady) {
            $script:allowFormClose = $true
            $form.Close()
            return
        }
        $script:closing = $true
        $script:closeStep = 0
        $script:closeRequestedAt = Get-Date
        $script:stopFileCreated = $false
        $script:forceStopDone = $false
        $closeButton.Enabled = $false
        $closeButton.Text = 'Fermeture...'
        $form.Cursor = 'WaitCursor'
        try {
            New-Item $script:stopFile -ItemType File -Force | Out-Null
            $script:stopFileCreated = $true
            $script:message = 'Arret demande, fermeture en cours...'
        }
        catch {
            $script:message = 'Fermeture demandee, nouvelle tentative...'
        }
    })

    $form.Add_KeyDown({
        if (-not $Preview) {
            if (
                ($_.Alt -and $_.KeyCode -eq 'F4') -or
                $_.KeyCode -eq 'Enter' -or
                $_.KeyCode -eq 'Space' -or
                $_.KeyCode -eq 'Escape'
            ) {
                $_.Handled = $true
                $_.SuppressKeyPress = $true
                return
            }
        }

        if ($_.KeyCode -eq 'Escape') {
            if ($Preview) {
                $script:allowFormClose = $true
                $form.Close()
            }
        }
    })

    $form.Add_FormClosing({
        if (-not $Preview -and -not $script:allowFormClose) {
            if (Test-LDLCUiFinalizationReady) { return }
            if ($script:proc -and $script:proc.HasExited) {
                return
            }

            $_.Cancel = $true
            $script:message = 'Fermeture clavier ignoree pendant la preparation.'
            $overlay.Invalidate()
        }
    })

    $form.Add_Shown({ $timer.Start() })
    [System.Windows.Forms.Application]::Run($form)
}
finally {
    if ($form -and $script:LDLCCompactUiState) { Set-LDLCCompactUiState -MainForm $form -Active $false }
    if ($timer) { $timer.Stop(); $timer.Dispose() }
    if ($workerStartTimer) { $workerStartTimer.Stop(); $workerStartTimer.Dispose() }
    if ($bgOriginal) { $bgOriginal.Dispose() }
    if ($bg) { $bg.Dispose() }
    if ($mutex) { $mutex.ReleaseMutex() | Out-Null }
}

# endregion UI
