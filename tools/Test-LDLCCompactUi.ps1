param([string]$ImagePath)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$root = Split-Path -Parent $PSScriptRoot
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'modules\99.UI.ps1'), [ref]$tokens, [ref]$errors)
$names = @('Initialize-LDLCCompactFormType', 'New-LDLCCompactForm', 'Set-LDLCCompactUiState', 'Read-LDLCCompactUiSignal', 'Confirm-LDLCCompactUiSignal', 'Update-LDLCCompactUi')
foreach ($function in $ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -in $names }, $true)) {
    . ([scriptblock]::Create($function.Extent.Text))
}
. (Join-Path $root 'modules\70.DefaultApps.ps1')
function Assert-True([bool]$Value,[string]$Message) { if (-not $Value) { throw $Message } }
function Write-Info($Message) { throw $Message }
function Pump-Ui([int]$Milliseconds) {
    $clock = [Diagnostics.Stopwatch]::StartNew()
    while ($clock.ElapsedMilliseconds -lt $Milliseconds) {
        [Windows.Forms.Application]::DoEvents()
        [Threading.Thread]::Sleep(12)
    }
}
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('LDLC-Compact-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
$main = New-Object Windows.Forms.Form
try {
    $main.WindowState = 'Normal'
    $main.TopMost = $true
    $main.Show()
    Pump-Ui 40
    Set-LDLCCompactUiState -MainForm $main -Active $true
    Pump-Ui 80
    $compact = $script:LDLCCompactForm
    Assert-True ($compact.Visible -and $compact.TopMost -and $main.WindowState -eq 'Minimized') 'Mode compact visible sans focus.'
    Assert-True ($null -ne $compact.Region -and -not $compact.Region.IsVisible(0,0)) 'Vrais coins arrondis, sans bord noir.'
    Assert-True ($compact.Text -notmatch 'Verification|Windows|LDLC') 'Titre neutre Preparation PC, sans Verification Windows.'
    $worker = [pscustomobject]@{ Id = $PID; HasExited = $false }
    $script:LDLCDefaultAppsCompactPath = Join-Path $fixture "LDLC_DEFAULT_APPS.$PID.json"
    Set-LDLCDefaultAppsCompactProgress -Percent 0 -Message "Configuration d'Adobe Acrobat Reader..."
    Assert-True (-not (Test-LDLCDefaultAppsCompactUiAck)) 'Un ancien affichage ne vaut pas acquittement du nouveau message.'
    Update-LDLCCompactUi $main $fixture $worker
    Assert-True (Test-LDLCDefaultAppsCompactUiAck) 'Acquitter la revision exacte seulement apres peinture.'
    $firstRevision = $script:LDLCDefaultAppsCompactProgress.Revision
    $ackPath = $script:LDLCDefaultAppsCompactPath + '.ack'
    $ack = [IO.File]::ReadAllText($ackPath) | ConvertFrom-Json
    Assert-True ($ack.Progress -eq 0 -and $ack.Message -eq $compact.StatusMessage -and $ack.RenderedAt) 'Preuve du texte et du palier reellement affiches.'
    Set-LDLCDefaultAppsActionProgress -Application Adobe -Association '.pdf' -Stage Selecting
    Assert-True (-not (Test-LDLCDefaultAppsCompactUiAck)) 'Le drapeau de visibilite precedent ne doit pas autoriser le clic suivant.'
    Update-LDLCCompactUi $main $fixture $worker
    Assert-True ((Test-LDLCDefaultAppsCompactUiAck) -and $compact.ProgressTarget -eq 0 -and $compact.StatusMessage -match 'Adobe.*\.pdf') 'Selection PDF affichee, sans faire progresser la barre.'
    Assert-True ($script:LDLCDefaultAppsCompactProgress.Revision -gt $firstRevision) 'Messages numerotes dans l ordre du worker.'
    $validAck = [IO.File]::ReadAllText($ackPath)
    $ack = $validAck | ConvertFrom-Json
    $ack.WorkerId = $PID + 1
    [IO.File]::WriteAllText($ackPath, ($ack | ConvertTo-Json -Compress))
    Assert-True (-not (Test-LDLCDefaultAppsCompactUiAck)) 'Refuser un acquittement d un autre worker.'
    [IO.File]::WriteAllText($ackPath, 'visible')
    Assert-True (-not (Test-LDLCDefaultAppsCompactUiAck)) 'Refuser un simple fichier visible perime.'
    [IO.File]::WriteAllText($ackPath, $validAck)
    $angle = $compact.SpinnerAngle
    $frames = $compact.AnimationFrames
    $child = Start-Process -FilePath (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList '-NoProfile','-Command','Start-Sleep -Seconds 2' -WindowStyle Hidden -PassThru
    try {
        Pump-Ui 650
        Assert-True (-not $child.HasExited -and $compact.AnimationFrames -gt $frames + 10 -and $compact.SpinnerAngle -ne $angle) 'Animation active pendant attente dans un autre processus.'
        Assert-True ($compact.ProgressTarget -eq 0 -and $compact.DisplayedProgress -eq 0) 'Ne jamais progresser avec le temps.'
        $child.WaitForExit()
    } finally { $child.Dispose() }
    Set-LDLCDefaultAppsCompactProgress -Percent 50 -Message 'Configuration de Chrome...'
    Update-LDLCCompactUi $main $fixture $worker
    Assert-True ($compact.ProgressTarget -eq 50 -and $compact.DisplayedProgress -lt 50) 'Transition animee, pas de saut instantane.'
    Pump-Ui 650
    Assert-True ([math]::Abs($compact.DisplayedProgress - 50) -lt 0.01 -and $compact.Running) 'Palier 50 stable ; cercle encore actif pour Chrome.'
    if ($ImagePath) {
        $bitmap = New-Object Drawing.Bitmap $compact.Width,$compact.Height
        try {
            $compact.DrawToBitmap($bitmap, (New-Object Drawing.Rectangle 0,0,$compact.Width,$compact.Height))
            $bitmap.Save([IO.Path]::GetFullPath($ImagePath), [Drawing.Imaging.ImageFormat]::Png)
        } finally { $bitmap.Dispose() }
    }
    [IO.File]::WriteAllText($script:LDLCDefaultAppsCompactPath,'{')
    Update-LDLCCompactUi $main $fixture $worker
    Assert-True ($compact.Visible -and $compact.ProgressTarget -eq 50) 'Lecture transitoire sans fermeture/recreation ni remise a zero.'
    Set-LDLCDefaultAppsCompactProgress -Percent 50 -Message 'Configuration non confirmee' -Running $false -ErrorApplication 'Chrome (https)'
    Update-LDLCCompactUi $main $fixture $worker
    $angle = $compact.SpinnerAngle
    Pump-Ui 300
    Assert-True (-not $compact.Running -and -not $compact.Success -and $compact.ProgressTarget -eq 50 -and $compact.SpinnerAngle -eq $angle -and $compact.ErrorApplication -match 'Chrome') 'Echec precis sans 100 pour cent ; cercle arrete.'
    $rejected = $false
    try { $compact.SetStatus(100,'Configuration terminee',$false,$false,'Adobe') } catch { $rejected = $true }
    Assert-True $rejected 'Interdire un faux 100 pour cent dans le rendu.'
    Set-LDLCDefaultAppsCompactProgress -Percent 100 -Message 'Configuration terminee' -Running $false -Success $true
    Update-LDLCCompactUi $main $fixture $worker
    Pump-Ui 650
    Assert-True ($compact.Success -and -not $compact.Running -and $compact.ProgressTarget -eq 100 -and $compact.DisplayedProgress -eq 100) 'Succes avec coche, arret du cercle et barre a 100.'
    Remove-Item -LiteralPath $script:LDLCDefaultAppsCompactPath
    Update-LDLCCompactUi $main $fixture $worker
    Pump-Ui 80
    Assert-True ($main.WindowState -eq 'Normal' -and $main.TopMost -and -not $script:LDLCCompactForm) 'Restaurer exactement la fenetre principale.'
    Write-Host 'OK WinForms compact: rounded render, real worker signals, independent animation during worker wait, truthful 0/50/100, eased bar, error, stopped spinner, transient JSON and restored main; no preparation.'
} finally {
    if ($script:LDLCCompactUiState) { Set-LDLCCompactUiState -MainForm $main -Active $false }
    $main.Dispose()
    $script:LDLCDefaultAppsCompactPath = $null
    $resolved = [IO.Path]::GetFullPath($fixture)
    if ($resolved.StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'LDLC-Compact-*') { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
