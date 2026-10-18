param([switch]$Worker, [switch]$Elevated, [Parameter(Mandatory=$true)][string]$RuntimeRoot)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $Worker) {
    $existing = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object {
        $_.CommandLine -and $_.CommandLine -match '(?i)[\\/]Test-LDLCDefaultAppsLive\.ps1(?:"|\s)' -and $_.CommandLine -match '(?:^|\s)-Worker(?:\s|$)'
    })
    if ($existing.Count) { throw 'Un diagnostic applications par defaut tourne deja. Attendre sa fin avant un nouveau test.' }
    if (Test-Path -LiteralPath $RuntimeRoot) {
        if (@(Get-ChildItem -LiteralPath $RuntimeRoot -Force).Count) { throw 'Utiliser un nouveau RuntimeRoot vide pour ne pas relire un ancien resultat ou signal stop.' }
    }
}
New-Item -ItemType Directory -Path $RuntimeRoot -Force | Out-Null
$log = Join-Path $RuntimeRoot 'default-apps-live.log'
$resultPath = Join-Path $RuntimeRoot 'result.json'
if ($Worker) {
    . (Join-Path $root 'modules/70.DefaultApps.ps1')
    function Stop-IfRequested { if (Test-Path (Join-Path $RuntimeRoot 'stop')) { throw 'LDLC_STOP_REQUESTED' } }
    function Test-LDLCStopRequestError($Record) { return $Record.Exception.Message -match 'LDLC_STOP_REQUESTED' }
    function Write-LiveLog($Level,$Message) { Add-Content -LiteralPath $log -Value "$(Get-Date -Format o) [$Level] $Message" -Encoding UTF8 }
    function Write-Section($Message) { Write-LiveLog SECTION $Message }
    function Write-Step($Message) { Write-LiveLog STEP $Message }
    function Write-Info($Message) { Write-LiveLog INFO $Message }
    function Write-Warn($Message) { Write-LiveLog WARN $Message }
    function Write-Ok($Message) { Write-LiveLog OK $Message }
    # This diagnostic configures ONLY PDF/browser defaults. No taskbar, installations,
    # security changes, wallpaper changes or production telemetry are executed.
    function Set-LDLCTaskbarOptionsWithRegistry { return $true }
    $script:ProgressFile = Join-Path $RuntimeRoot 'progress.txt'
    $env:LDLC_DEFAULT_APPS_UI = '1'
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    Write-LiveLog INFO "Worker administrateur : $isAdmin"
    try {
        Invoke-LDLCChromeDefaultAppsSequence
        [ordered]@{ Adobe = Get-LDLCDefaultAppState Adobe; Chrome = Get-LDLCDefaultAppState Chrome;
            Ui = $script:LDLCDefaultAppsCompactProgress } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding UTF8
    } catch { Write-LiveLog ERROR $_.Exception.Message; exit 1 }
    exit 0
}
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'modules/99.UI.ps1'),[ref]$tokens,[ref]$errors)
foreach ($definition in $ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -in @('Initialize-LDLCCompactFormType','New-LDLCCompactForm','Read-LDLCCompactUiSignal','Confirm-LDLCCompactUiSignal')},$true)) {
    . ([scriptblock]::Create($definition.Extent.Text))
}
$form=New-LDLCCompactForm
$area=[Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$form.Left=$area.Left+16; $form.Top=$area.Bottom-$form.Height-16
$powershell=Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'
$arguments='-STA -NoProfile -ExecutionPolicy Bypass -File "'+$PSCommandPath+'" -Worker -RuntimeRoot "'+$RuntimeRoot+'"'
if ($Elevated) { $process=Start-Process -FilePath $powershell -ArgumentList $arguments -WindowStyle Hidden -Verb RunAs -PassThru }
else { $process=Start-Process -FilePath $powershell -ArgumentList $arguments -WindowStyle Hidden -PassThru }
$timer=New-Object Windows.Forms.Timer
$timer.Interval=120
$script:FinishedAt=$null
$timer.Add_Tick({
    try {
        $signal = Read-LDLCCompactUiSignal -RuntimeRoot $RuntimeRoot -Worker $process
        if ($signal) {
            $form.SetStatus([int]$signal.Progress,[string]$signal.Message,[bool]$signal.Running,[bool]$signal.Success,[string]$signal.ErrorApplication)
            $rendered = Confirm-LDLCCompactUiSignal -Form $form -Signal $signal -RuntimeRoot $RuntimeRoot
            if ($rendered) { Add-Content -LiteralPath (Join-Path $RuntimeRoot 'compact-ui.jsonl') -Value ($rendered | ConvertTo-Json -Compress) -Encoding UTF8 }
        }
        if ($process.HasExited) {
            if (-not $script:FinishedAt) { $script:FinishedAt=Get-Date }
            if (((Get-Date)-$script:FinishedAt).TotalSeconds -gt 3) { $form.Close() }
        }
    } catch { Add-Content -LiteralPath $log -Value $_.Exception.Message }
})
try { $timer.Start(); [void]$form.ShowDialog() }
finally {
    $timer.Dispose(); $form.Dispose()
    if (-not $process.HasExited) { [IO.File]::WriteAllText((Join-Path $RuntimeRoot 'stop'),'stop'); [void]$process.WaitForExit(35000) }
    $process.Dispose()
}
if (Test-Path -LiteralPath $resultPath) {
    $result = Get-Content -LiteralPath $resultPath -Raw
    Write-Output $result
    $state = $result | ConvertFrom-Json
    if (-not $state.Adobe.Confirmed -or -not $state.Chrome.Confirmed -or -not $state.Ui.Success) { throw "Associations non confirmees; lire $log" }
}
else { throw "Diagnostic non termine. Lire $log" }
