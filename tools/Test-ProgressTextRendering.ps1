#requires -Version 5.1
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Native Windows GDI+ required.' }
Add-Type -AssemblyName System.Drawing
$root = Split-Path -Parent $PSScriptRoot
$helpers = @('Convert-X','Convert-Y','Convert-FontSize','Limit-LDLCText','Draw-LDLCTextWithShadow','Get-LDLCPhaseIndex','Get-LDLCStatusTitle','New-RoundedRectanglePath','Draw-LDLCProgressArea')
$results = @()
$sources = @(
    @{Edition='LDLC et beta';Path=(Join-Path $root 'modules/99.UI.ps1')},
    @{Edition='Addon';Path=(Join-Path $PSScriptRoot 'fixtures/progress-ui/addon.ps1')}
)
foreach ($source in $sources) {
    $ast = [Management.Automation.Language.Parser]::ParseFile($source.Path,[ref]$null,[ref]$null)
    foreach ($name in $helpers) {
        $node = $ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
        if (-not $node) { if ($name -eq 'Draw-LDLCTextWithShadow') { continue }; throw "Missing renderer: $name" }
        $text = $node.Extent.Text
        if ($name -eq 'Draw-LDLCProgressArea') {
            # Observe the actual renderer's boxes and native font metrics before
            # it disposes its GDI resources; retain the original drawing calls.
            $capture = @'
    $script:TextMetrics = @{Blue=$detailRect;White=$metaRect;BlueFont=$detailFont.GetHeight($Graphics);WhiteFont=$metaFont.GetHeight($Graphics)}
'@
            $pattern = '(?m)^    \$metaRect = New-Object System.Drawing.RectangleF[^\r\n]*'
            if ([regex]::Matches($text,$pattern).Count -ne 1) { throw 'Renderer observation point missing.' }
            $text = [regex]::Replace($text,$pattern,[Text.RegularExpressions.MatchEvaluator]{param($m) $m.Value+"`n"+$capture})
        }
        . ([scriptblock]::Create($text))
    }
    foreach ($width in @(481,902,1280)) {
        $height = [int][Math]::Round($width * 772.0 / 1672)
        $script:scaleX = $width / 1672.0; $script:scaleY = $height / 772.0
        $script:percent = 100; $script:closing = $false; $Preview = $false
        $script:message = 'Configuration du poste terminee.'
        $script:phases = @(@{Name='FINALISATION';Min=0;Max=100})
        $bitmap = New-Object Drawing.Bitmap($width,$height)
        $graphics = [Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.Clear([Drawing.Color]::Black)
            Draw-LDLCProgressArea -Graphics $graphics
            $m = $script:TextMetrics
            if ($m.Blue.Height -lt $m.BlueFont -or $m.White.Height -lt $m.WhiteFont) { throw 'Text box clips the enlarged font.' }
            if ($m.Blue.Bottom -ge $m.White.Top -or $m.White.Bottom -gt $height) { throw 'Progress text overlaps or exceeds the window.' }
            $pixels = @()
            foreach ($bounds in @($m.Blue,$m.White)) {
                $count = 0
                for ($y=[int][Math]::Ceiling($bounds.Top); $y -lt [Math]::Min($height,$bounds.Bottom); $y++) {
                    for ($x=[int][Math]::Ceiling($bounds.Left); $x -lt [Math]::Min($width,$bounds.Right); $x++) {
                        $color = $bitmap.GetPixel($x,$y)
                        if (($color.R+$color.G+$color.B) -gt 150) { $count++ }
                    }
                }
                if ($count -lt 10) { throw 'A progress text line was not painted.' }
                $pixels += $count
            }
            $results += @{Edition=$source.Edition;Width=$width;Height=$height;BlueHeight=$m.Blue.Height;BlueFontHeight=$m.BlueFont;WhiteHeight=$m.White.Height;WhiteFontHeight=$m.WhiteFont;PaintedPixels=$pixels;Fits=$true}
        }
        finally { $graphics.Dispose(); $bitmap.Dispose() }
    }
}
$report = @{Mode='real native GDI+ rasterization of isolated source renderers; no application preparation';Cases=$results;Failures=0;Numeriks='unchanged and excluded'}
if ($env:GITHUB_ACTIONS -eq 'true') {
    $json = ($report|ConvertTo-Json -Depth 5 -Compress).Replace('%','%25').Replace("`r",'%0D').Replace("`n",'%0A')
    Write-Host "::notice title=Progress text rendering::$json"
}
Write-Host 'OK native progress rendering: 6 cases, enlarged blue/white lines painted, no clipping or overlap; Numeriks excluded.'
