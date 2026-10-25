param([ValidateSet('modules', 'worker-modules')][string]$ModuleDirectory = 'modules')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$root = Split-Path -Parent $PSScriptRoot
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root "$ModuleDirectory/99.UI.ps1"), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Invalid production UI syntax.' }
foreach ($definition in $ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]}, $true)) {
    $source = $definition.Extent.Text
    if ($definition.Name -ne 'Draw-LDLCTextWithShadow') {
        $source = [regex]::Replace($source, '(?m)^(\s*)\$Graphics\.DrawString\(([^\r\n]+)\)\s*$', '$1Draw-ObservedText -Graphics $Graphics -Arguments @($2)')
    }
    if ($definition.Name -eq 'Draw-LDLCProgressArea') {
        # Observe the real final rectangles, including any edition-owned offsets.
        $source = $source.Substring(0, $source.Length - 1) + @'
    $script:MeasuredProgress = @{Status=$statusRect;Detail=$detailRect;Meta=$metaRect;Percent=$percentRect;Bar=$barBounds}
}
'@
    }
    . ([scriptblock]::Create($source))
}
$phaseAssignment = $ast.Find({param($n)
    $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$script:phases'
}, $true)
if (-not $phaseAssignment) { throw 'Production phase data not found.' }
. ([scriptblock]::Create($phaseAssignment.Extent.Text))
$shadowCommand = Get-Command Draw-LDLCTextWithShadow -ErrorAction SilentlyContinue
if ($shadowCommand) { $script:originalDrawText = $shadowCommand.ScriptBlock }
function Draw-LDLCTextWithShadow {
    param([Drawing.Graphics]$Graphics, [string]$Text, [Drawing.Font]$Font,
        [Drawing.Brush]$Brush, [Drawing.RectangleF]$Bounds, [Drawing.StringFormat]$Format,
        [int]$ShadowAlpha = 190)
    $script:MeasuredText.Add([pscustomobject]@{Text=$Text;Bounds=$Bounds;FontHeight=$Font.GetHeight($Graphics);TextWidth=$Graphics.MeasureString($Text,$Font).Width})
    & $script:originalDrawText @PSBoundParameters
}
function Draw-ObservedText {
    param([Drawing.Graphics]$Graphics, [object[]]$Arguments)
    $text = [string]$Arguments[0]; $font = [Drawing.Font]$Arguments[1]
    if ($Arguments[3] -is [Drawing.RectangleF]) {
        $bounds = $Arguments[3]
        $Graphics.DrawString($text, $font, $Arguments[2], $bounds, $Arguments[4])
    }
    else {
        $size = $Graphics.MeasureString($text, $font)
        $bounds = New-Object Drawing.RectangleF $Arguments[3], $Arguments[4], $size.Width, $size.Height
        $Graphics.DrawString($text, $font, $Arguments[2], [single]$Arguments[3], [single]$Arguments[4])
    }
    $script:MeasuredText.Add([pscustomobject]@{Text=$text;Bounds=$bounds;FontHeight=$font.GetHeight($Graphics);TextWidth=$Graphics.MeasureString($text,$font).Width})
    if ($text -match '^\d+%$') { $script:ObservedPercentBounds = $bounds }
}
$script:assertions = 0
function Assert-True([bool]$Condition, [string]$Message) {
    $script:assertions++
    if (-not $Condition) { throw $Message }
}
$asset = if (Test-Path (Join-Path $root 'assets/UI_BackgroundNKS.v2.png')) { 'assets/UI_BackgroundNKS.v2.png' }
    elseif (Test-Path (Join-Path $root 'assets/UI_Background.v2.png')) { 'assets/UI_Background.v2.png' }
    else { 'assets/UI_Background.png' }
$image = [Drawing.Image]::FromFile((Join-Path $root $asset))
$script:LDLCUiOverlay = New-Object Windows.Forms.Panel
$script:LDLCQuitButton = New-Object Windows.Forms.Button
$script:LDLCAppVersionLabel = 'Version 1.0'
$Preview = $true; $script:closing = $false
$scenarios = 0
try {
    foreach ($scale in @(0.288, 0.42, 0.5, 0.72, 1.0)) {
        $script:scaleX = $scale; $script:scaleY = $scale
        $width = [int]($image.Width * $scale); $height = [int]($image.Height * $scale)
        $script:LDLCQuitButton.Top = $height - [Math]::Max(22, (Convert-Y 34)) - [Math]::Max(3, (Convert-Y 6))
        foreach ($dpi in @(67, 96, 120, 144, 168, 192, 216)) {
            foreach ($percent in @(0, 47, 100)) {
                $canvas = New-Object Drawing.Bitmap $width, $height
                $canvas.SetResolution($dpi, $dpi)
                $graphics = [Drawing.Graphics]::FromImage($canvas)
                try {
                    $graphics.DrawImage($image, 0, 0, $width, $height)
                    $graphics.SmoothingMode = 'AntiAlias'
                    $graphics.TextRenderingHint = 'ClearTypeGridFit'
                    $script:percent = $percent
                    $script:message = 'Configuration des applications et verification des associations du poste'
                    $script:MeasuredText = New-Object 'Collections.Generic.List[object]'
                    $script:MeasuredProgress = $null
                    $script:ObservedPercentBounds = $null
                    Draw-LDLCStageList -Graphics $graphics -ActiveIndex (Get-LDLCPhaseIndex $percent)
                    Draw-LDLCProgressArea -Graphics $graphics
                    if (Get-Command Draw-LDLCVersionOverlay -ErrorAction SilentlyContinue) { Draw-LDLCVersionOverlay -Graphics $graphics }
                    foreach ($text in $script:MeasuredText) {
                        $b = $text.Bounds
                        Assert-True ($b.Left -ge 0 -and $b.Top -ge 0 -and $b.Right -le $width + 1 -and $b.Bottom -le $height + 1) "Text outside canvas at $scale/$dpi : $($text.Text), $b"
                        Assert-True ($text.FontHeight -le $b.Height + 0.5) "Text clipped vertically at $scale/$dpi : $($text.Text), font=$($text.FontHeight), box=$($b.Height)"
                        if ($text.Text -match '^\d+%$') {
                            Assert-True ($text.TextWidth -le $b.Width + 0.5) "Percentage clipped horizontally at $scale/$dpi."
                        }
                    }
                    foreach ($phase in $script:phases) {
                        $title = @($script:MeasuredText | Where-Object Text -EQ $phase.Name)
                        $detail = @($script:MeasuredText | Where-Object Text -EQ $phase.Detail)
                        Assert-True ($title.Count -eq 1 -and $detail.Count -eq 1) 'Missing phase text in production renderer.'
                        Assert-True ($title[0].Bounds.Bottom -le $detail[0].Bounds.Top + 0.5) "Phase title and detail overlap at $scale/$dpi."
                    }
                    $layout = $script:MeasuredProgress
                    if ($script:ObservedPercentBounds) { $layout.Percent = $script:ObservedPercentBounds }
                    Assert-True ($null -ne $layout -and $layout.Bar.Width -gt 0 -and $layout.Bar.Height -gt 0) 'Missing real progress geometry.'
                    Assert-True ($layout.Status.Bottom -le $layout.Bar.Top + 0.5) "Status overlaps bar at $scale/$dpi."
                    Assert-True ($layout.Bar.Bottom -le $layout.Detail.Top + 0.5) "Bar overlaps detail at $scale/$dpi."
                    Assert-True ($layout.Detail.Bottom -le $layout.Meta.Top + 0.5) "Detail overlaps meta text at $scale/$dpi."
                    foreach ($part in @('Status', 'Bar', 'Detail', 'Meta')) {
                        Assert-True (-not $layout.Percent.IntersectsWith($layout[$part])) "Percentage overlaps $part at $scale/$dpi."
                    }
                    $scenarios++
                }
                finally { $graphics.Dispose(); $canvas.Dispose() }
            }
        }
    }
    Write-Host "OK $script:assertions canvas assertions, $scenarios actual GDI renders; production renderer instrumented for observation only, no preparation or system display changes."
}
finally {
    $script:LDLCUiOverlay.Dispose(); $script:LDLCQuitButton.Dispose(); $image.Dispose()
}
