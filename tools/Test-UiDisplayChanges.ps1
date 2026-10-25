param([ValidateSet('modules', 'worker-modules')][string]$ModuleDirectory = 'modules')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$root = Split-Path -Parent $PSScriptRoot
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root "$ModuleDirectory/99.UI.ps1"), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'UI syntax invalid.' }
foreach ($name in @('Convert-X', 'Convert-Y', 'Convert-FontSize', 'Initialize-LDLCUiPixelBuffer',
    'Resize-LDLCBackgroundBitmap', 'Apply-LDLCBitmapRoundedWindowMask', 'Remove-LDLCBitmapAlphaFringe',
    'New-LDLCBitmapAlphaRegion', 'New-LDLCRoundedWindowRegion', 'New-RoundedRectanglePath', 'Update-LDLCMainUiLayout')) {
    $definition = $ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name}, $true)
    if ($definition) { . ([scriptblock]::Create($definition.Extent.Text)) }
}
$script:assertions = 0
function Assert-True([bool]$Condition, [string]$Message) {
    $script:assertions++
    if (-not $Condition) { throw $Message }
}
$asset = if (Test-Path (Join-Path $root 'assets/UI_BackgroundNKS.v2.png')) { 'assets/UI_BackgroundNKS.v2.png' }
    elseif (Test-Path (Join-Path $root 'assets/UI_Background.v2.png')) { 'assets/UI_Background.v2.png' }
    else { 'assets/UI_Background.png' }
$source = [System.Drawing.Image]::FromFile((Join-Path $root $asset))
$form = New-Object System.Windows.Forms.Form
$picture = New-Object System.Windows.Forms.PictureBox
$overlay = New-Object System.Windows.Forms.Panel
$button = New-Object System.Windows.Forms.Button
try {
    $form.AutoScaleMode = 'None'
    $form.StartPosition = 'Manual'
    $form.FormBorderStyle = 'None'
    $form.TransparencyKey = [Drawing.Color]::FromArgb(17, 18, 19)
    $picture.Dock = 'Fill'; $overlay.Dock = 'Fill'
    $form.Controls.Add($picture); $picture.Controls.Add($overlay); $overlay.Controls.Add($button)
    $button.Text = 'Quitter'
    $button.BackColor = [Drawing.Color]::FromArgb(215, 35, 35)
    $button.ForeColor = [Drawing.Color]::White
    $button.FlatStyle = 'Flat'
    $button.FlatAppearance.BorderSize = 0
    if ($ast.Extent.Text -match '\$closeButton.AutoSize = \$true') {
        $button.AutoSize = $true
        $button.AutoSizeMode = 'GrowAndShrink'
        $button.Padding = New-Object System.Windows.Forms.Padding 4, 0, 4, 0
    }
    $script:percent = 73; $script:message = 'Unchanged preparation state'
    $scenarios = 0
    foreach ($area in @(
        (New-Object Drawing.Rectangle 0, 0, 2560, 1392),
        (New-Object Drawing.Rectangle 0, 0, 1920, 1040),
        (New-Object Drawing.Rectangle 0, 0, 1366, 728),
        (New-Object Drawing.Rectangle -1024, 40, 1024, 728)
    )) {
        $expectedSize = $null
        foreach ($dpi in @(144, 67, 96, 120, 168, 192, 216, 144)) {
            # Simulate Windows resizing the HWND while the old canvas is still installed.
            $form.ClientSize = New-Object Drawing.Size 399, 183
            $changed = Update-LDLCMainUiLayout $form $picture $overlay $button $source -WorkingArea $area -DisplayDpi $dpi
            Assert-True $changed 'Display changes must rebuild the layout.'
            Assert-True ($form.ClientSize -eq $picture.Image.Size) 'Image and window size differ: uncovered strip possible.'
            Assert-True ($picture.Bounds -eq $form.ClientRectangle) 'Picture does not fill the window.'
            Assert-True ($overlay.Bounds -eq $picture.ClientRectangle) 'Overlay uses stale DPI bounds.'
            Assert-True ($form.ClientRectangle.Contains($button.Bounds)) "Quit button outside client area: form=$($form.ClientRectangle), button=$($button.Bounds), area=$area, dpi=$dpi."
            Assert-True ($button.TextAlign -eq 'MiddleCenter') 'Quit label not centered.'
            if ($null -eq $expectedSize) { $expectedSize = $form.ClientSize }
            Assert-True ($form.ClientSize -eq $expectedSize) 'Windows zoom must not enlarge the compact window.'
            Assert-True ($button.Font.Unit -eq [Drawing.GraphicsUnit]::Pixel) 'The canvas must not apply Windows DPI to its font a second time.'
            $raster = New-Object Drawing.Bitmap $button.Width, $button.Height
            try {
                $button.DrawToBitmap($raster, (New-Object Drawing.Rectangle 0, 0, $button.Width, $button.Height))
                $white = 0
                for ($y = 0; $y -lt $raster.Height; $y++) {
                    for ($x = 0; $x -lt $raster.Width; $x++) {
                        $pixel = $raster.GetPixel($x, $y)
                        if ($pixel.R -gt 200 -and $pixel.G -gt 200 -and $pixel.B -gt 200) { $white++ }
                    }
                }
                Assert-True ($white -ge 10 -and $white -lt $button.Width * $button.Height / 2) 'Quit label missing or WinForms paint-error raster present.'
            }
            finally { $raster.Dispose() }
            Assert-True ($form.Region.IsVisible($button.Left + $button.Width / 2, $button.Top + $button.Height / 2)) 'Quit button clipped by stale region.'
            Assert-True (-not $form.Region.IsVisible(0, 0)) 'Window has an opaque corner.'
            Assert-True ($form.Left -eq $area.Left + 20 -and $form.Bottom -eq $area.Bottom - 20) 'Window not anchored on its current monitor.'
            Assert-True ([Math]::Abs($form.Width / $form.Height - $source.Width / $source.Height) -lt 0.01) 'Background proportions changed.'
            $image = $picture.Image
            Assert-True (-not (Update-LDLCMainUiLayout $form $picture $overlay $button $source -WorkingArea $area -DisplayDpi $dpi)) 'Stable layout must not allocate every timer tick.'
            Assert-True ([object]::ReferenceEquals($image, $picture.Image)) 'Stable bitmap was replaced.'
            Assert-True ($script:percent -eq 73 -and $script:message -eq 'Unchanged preparation state') 'Layout changed workflow progress.'
            $scenarios++
        }
    }
    # Win32 can clamp an HWND's requested size on a smaller/remote desktop.
    $form.MaximumSize = New-Object Drawing.Size 700, 400
    $form.Tag = $null
    [void](Update-LDLCMainUiLayout $form $picture $overlay $button $source -WorkingArea (New-Object Drawing.Rectangle 0, 0, 2560, 1392) -DisplayDpi 192)
    Assert-True ($form.ClientSize -eq $picture.Image.Size) "Native size clamping left an uncovered or stretched canvas: client=$($form.ClientSize), image=$($picture.Image.Size), max=$($form.MaximumSize)."
    Assert-True ([Math]::Abs($form.Width / $form.Height - $source.Width / $source.Height) -lt 0.01) 'Native size clamping changed background proportions.'
    Assert-True ($form.ClientRectangle.Contains($button.Bounds)) 'Native size clamping hid the Quit button.'
    $form.MaximumSize = [Drawing.Size]::Empty
    $image = $picture.Image
    $form.WindowState = 'Minimized'
    Assert-True (-not (Update-LDLCMainUiLayout $form $picture $overlay $button $source)) 'Compact/minimized UI must not be restored by layout polling.'
    Assert-True ([object]::ReferenceEquals($image, $picture.Image)) 'Minimized UI was repainted.'
    $fonts = @($ast.FindAll({param($n)
        $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'New-Object' -and
        $n.Extent.Text -match 'System.Drawing.Font\(' -and $n.Extent.Text -match 'Convert-FontSize'
    }, $true))
    Assert-True ($fonts.Count -ge 7) 'Production font constructors were not found.'
    foreach ($canvasScale in @(0.288, 0.5, 0.72, 1.0)) {
        $script:scaleX = $canvasScale; $script:scaleY = $canvasScale
        foreach ($constructor in $fonts) {
            $font = & ([scriptblock]::Create($constructor.Extent.Text))
            try {
                Assert-True ($font.Unit -eq [Drawing.GraphicsUnit]::Pixel) 'A production font still uses DPI-dependent point units.'
                $referenceHeight = $null
                foreach ($dpi in @(67, 96, 120, 144, 168, 192, 216)) {
                    $canvas = New-Object Drawing.Bitmap 32, 32
                    $canvas.SetResolution($dpi, $dpi)
                    $graphics = [Drawing.Graphics]::FromImage($canvas)
                    try {
                        $height = $font.GetHeight($graphics)
                        if ($null -eq $referenceHeight) { $referenceHeight = $height }
                        Assert-True ([Math]::Abs($height - $referenceHeight) -lt 0.01) 'Font height changes with DPI and can clip its fixed canvas text rectangle.'
                    }
                    finally { $graphics.Dispose(); $canvas.Dispose() }
                }
            }
            finally { $font.Dispose() }
        }
    }
    Write-Host "OK $script:assertions display/font assertions, $scenarios resolution/DPI changes; real production helpers, native GDI at 67/96/120/144/168/192/216 DPI, no system setting changed."
}
finally {
    if ($picture.Image) { $picture.Image.Dispose() }
    if ($form.Region) { $form.Region.Dispose() }
    $form.Dispose()
    $source.Dispose()
}
