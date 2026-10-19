# Rendering-only snapshot of the locally prepared Addon UI. No installer or runtime startup.
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

function Draw-LDLCProgressArea {
    param([System.Drawing.Graphics]$Graphics)

    $statusFont = New-Object System.Drawing.Font('Segoe UI', (Convert-FontSize 24 7), [System.Drawing.FontStyle]::Bold)
    $detailFont = New-Object System.Drawing.Font('Segoe UI', (Convert-FontSize 16 8), [System.Drawing.FontStyle]::Regular)
    $percentFont = New-Object System.Drawing.Font('Segoe UI', (Convert-FontSize 32 9), [System.Drawing.FontStyle]::Bold)
    $metaFont = New-Object System.Drawing.Font('Segoe UI', (Convert-FontSize 13 7), [System.Drawing.FontStyle]::Regular)
    $textFormat = New-Object System.Drawing.StringFormat
    $textFormat.Trimming = [System.Drawing.StringTrimming]::EllipsisCharacter
    $textFormat.FormatFlags = [System.Drawing.StringFormatFlags]::NoWrap

    $whiteBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $blueTextBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 78, 170, 255))
    $softBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(180, 170, 205, 235))

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
    $Graphics.DrawString($status, $statusFont, $whiteBrush, $statusRect, $textFormat)
    $Graphics.DrawString($detail, $detailFont, $blueTextBrush, $detailRect, $textFormat)
    $Graphics.DrawString($meta, $metaFont, $softBrush, $metaRect, $textFormat)

    $barBounds = New-Object System.Drawing.RectangleF((Convert-X 548), (Convert-Y 608), (Convert-X 832), (Convert-Y 35))
    $barPath = New-RoundedRectanglePath -Bounds $barBounds -Radius (Convert-X 18)
    $barBack = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(210, 2, 28, 72))
    $barPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 20, 145, 255), (Convert-X 1))
    $Graphics.FillPath($barBack, $barPath)

    $fillBrush = $null
    $fillPath = $null
    $innerClipPath = $null
    $oldClip = $null
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
        $innerClipPath = New-RoundedRectanglePath -Bounds $innerBarBounds -Radius ($innerBarBounds.Height / 2)
        $fillBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($innerBarBounds, [System.Drawing.Color]::FromArgb(255, 0, 182, 255), [System.Drawing.Color]::FromArgb(255, 0, 89, 255), 0)
        $oldClip = $Graphics.Clip.Clone()
        $Graphics.SetClip($innerClipPath, [System.Drawing.Drawing2D.CombineMode]::Intersect)
        $Graphics.FillPath($fillBrush, $fillPath)
        $Graphics.Clip = $oldClip
    }

    $Graphics.DrawPath($barPen, $barPath)

    $percentText = "$([int]$script:percent)%"
    $Graphics.DrawString($percentText, $percentFont, $whiteBrush, (Convert-X 1410), (Convert-Y 590))

    if ($fillBrush) { $fillBrush.Dispose() }
    if ($fillPath) { $fillPath.Dispose() }
    if ($innerClipPath) { $innerClipPath.Dispose() }
    if ($oldClip) { $oldClip.Dispose() }
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