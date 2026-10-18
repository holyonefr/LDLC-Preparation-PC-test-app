param([switch]$Benchmark)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$source = [IO.File]::ReadAllText((Join-Path $root 'modules/99.UI.ps1'))
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'UI syntax invalid.' }
function Import-UiFunction([string]$Name) {
    $definition = $ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $Name}, $true)
    if (-not $definition) { throw "Missing UI function: $Name" }
    . ([scriptblock]::Create('function script:' + $Name + ' ' + $definition.Body.Extent.Text))
}
Import-UiFunction 'Initialize-LDLCUiPixelBuffer'
Initialize-LDLCUiPixelBuffer
Initialize-LDLCUiPixelBuffer # Repeated calls must not try to redefine the type.
$addon = Test-Path (Join-Path $root 'worker-modules')
$script:assertions = 0
function Assert-Equal($Expected, $Actual, [string]$Label) {
    $script:assertions++
    if ($Expected -ne $Actual) { throw "Pixel regression: $Label" }
}
function Assert-Bytes([byte[]]$Expected, [byte[]]$Actual, [string]$Label) {
    Assert-Equal ([Convert]::ToBase64String($Expected)) ([Convert]::ToBase64String($Actual)) $Label
}

# Reference loops preserve the pre-optimization PowerShell algorithms, including
# transparent RGB bytes, cutoff equality, run order and the asymmetric corner centers.
function Invoke-ReferenceFringe([byte[]]$Bytes, $Width, $Height, $Stride, $Cutoff, [bool]$AddonMode) {
    for ($y = 0; $y -lt $Height; $y++) {
        for ($x = 0; $x -lt $Width; $x++) {
            $offset = $y * $Stride + $x * 4
            $alpha = $Bytes[$offset + 3]
            if ($AddonMode -and $alpha -eq 0) { continue }
            if ($alpha -lt $Cutoff) {
                if ($AddonMode) { $Bytes[$offset] = 255; $Bytes[$offset+1] = 255; $Bytes[$offset+2] = 255 }
                else { $Bytes[$offset] = 19; $Bytes[$offset+1] = 18; $Bytes[$offset+2] = 17 }
                $Bytes[$offset + 3] = 0
            }
            elseif ($alpha -lt 255) { $Bytes[$offset + 3] = 255 }
        }
    }
}
function Get-ReferenceRuns([byte[]]$Bytes, $Width, $Height, $Stride, $Threshold) {
    $runs = New-Object 'Collections.Generic.List[int]'
    for ($y = 0; $y -lt $Height; $y++) {
        $start = -1
        for ($x = 0; $x -lt $Width; $x++) {
            $visible = $Bytes[$y * $Stride + $x * 4 + 3] -ge $Threshold
            if ($visible -and $start -lt 0) { $start = $x }
            elseif (-not $visible -and $start -ge 0) {
                $runs.Add($start); $runs.Add($y); $runs.Add($x - $start); $start = -1
            }
        }
        if ($start -ge 0) { $runs.Add($start); $runs.Add($y); $runs.Add($Width - $start) }
    }
    return ,$runs.ToArray()
}
function Invoke-ReferenceMask([byte[]]$Bytes, $Width, $Height, $Stride, $Radius) {
    for ($y = 0; $y -lt $Height; $y++) {
        for ($x = 0; $x -lt $Width; $x++) {
            $cx = $null; $cy = $null
            if ($x -lt $Radius -and $y -lt $Radius) { $cx=$Radius; $cy=$Radius }
            elseif ($x -ge ($Width-$Radius) -and $y -lt $Radius) { $cx=$Width-$Radius-1; $cy=$Radius }
            elseif ($x -lt $Radius -and $y -ge ($Height-$Radius)) { $cx=$Radius; $cy=$Height-$Radius-1 }
            elseif ($x -ge ($Width-$Radius) -and $y -ge ($Height-$Radius)) { $cx=$Width-$Radius-1; $cy=$Height-$Radius-1 }
            if ($null -eq $cx) { continue }
            $dx=$x-$cx; $dy=$y-$cy
            if (($dx*$dx+$dy*$dy) -le $Radius*$Radius) { continue }
            $offset=$y*$Stride+$x*4
            $Bytes[$offset]=19; $Bytes[$offset+1]=18; $Bytes[$offset+2]=17; $Bytes[$offset+3]=0
        }
    }
}

$random = New-Object Random 9473
foreach ($size in @(@(1,1), @(2,3), @(17,13), @(31,9))) {
    $width, $height = $size
    foreach ($padding in @(0,8)) {
        $stride = $width * 4 + $padding
        $bytes = New-Object byte[] ($stride * $height)
        $random.NextBytes($bytes)
        # Cover every alpha value at cutoff boundaries across deterministic cases.
        foreach ($cutoff in @(0,1,32,245,254,255,256)) {
            for ($a=0; $a -lt 256; $a++) {
                $bytes[3] = $a
                $expected = $bytes.Clone(); $actual = $bytes.Clone()
                Invoke-ReferenceFringe $expected $width $height $stride $cutoff $addon
                if ($addon) { [LDLCUiPixelBuffer]::RemoveFringe($actual,$width,$height,$stride,$cutoff,255,255,255,$true) }
                else { [LDLCUiPixelBuffer]::RemoveFringe($actual,$width,$height,$stride,$cutoff,17,18,19,$false) }
                Assert-Bytes $expected $actual "fringe $width x $height, alpha=$a cutoff=$cutoff padding=$padding"
            }
            $expected = Get-ReferenceRuns $bytes $width $height $stride $cutoff
            $actual = [LDLCUiPixelBuffer]::GetAlphaRuns($bytes,$width,$height,$stride,$cutoff)
            Assert-Equal ($expected -join ',') ($actual -join ',') 'alpha region run order and edges'
        }
        foreach ($radius in @(1,2,6.5,100)) {
            $safeRadius = [Math]::Max(1,[Math]::Min($radius,[Math]::Min($width,$height)/2))
            $expected = $bytes.Clone(); $actual = $bytes.Clone()
            Invoke-ReferenceMask $expected $width $height $stride $safeRadius
            [LDLCUiPixelBuffer]::ApplyRoundedMask($actual,$width,$height,$stride,$safeRadius,17,18,19)
            Assert-Bytes $expected $actual 'corner mask and stride padding'
        }
    }
}

if ($env:OS -eq 'Windows_NT') {
    Add-Type -AssemblyName System.Drawing
    foreach ($name in @('Remove-LDLCBitmapAlphaFringe','New-LDLCBitmapAlphaRegion')) { Import-UiFunction $name }
    if (-not $addon) { Import-UiFunction 'Apply-LDLCBitmapRoundedWindowMask' }
    $bitmap = New-Object Drawing.Bitmap 17,13,([Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $rect = New-Object Drawing.Rectangle 0,0,17,13
    try {
        $data = $bitmap.LockBits($rect,[Drawing.Imaging.ImageLockMode]::ReadWrite,[Drawing.Imaging.PixelFormat]::Format32bppArgb)
        try {
            $stride = [Math]::Abs($data.Stride)
            $original = New-Object byte[] ($stride*13); $random.NextBytes($original)
            [Runtime.InteropServices.Marshal]::Copy($original,0,$data.Scan0,$original.Length)
        } finally { $bitmap.UnlockBits($data) }
        $expected = $original.Clone()
        Invoke-ReferenceFringe $expected 17 13 $stride 245 $addon
        Remove-LDLCBitmapAlphaFringe $bitmap -AlphaCutoff 245
        $data = $bitmap.LockBits($rect,[Drawing.Imaging.ImageLockMode]::ReadOnly,[Drawing.Imaging.PixelFormat]::Format32bppArgb)
        try {
            $actual = New-Object byte[] $original.Length
            [Runtime.InteropServices.Marshal]::Copy($data.Scan0,$actual,0,$actual.Length)
        } finally { $bitmap.UnlockBits($data) }
        Assert-Bytes $expected $actual 'real bitmap wrapper'
        $region = New-LDLCBitmapAlphaRegion $bitmap -AlphaThreshold 254
        try {
            for ($y=0; $y -lt 13; $y++) { for ($x=0; $x -lt 17; $x++) {
                Assert-Equal ($expected[$y*$stride+$x*4+3] -ge 254) ($region.IsVisible($x,$y)) 'real region coverage'
            } }
        } finally { if ($region) { $region.Dispose() } }
    } finally { $bitmap.Dispose() }
} else { Write-Host 'SKIP real System.Drawing wrappers: Windows required.' }

if ($Benchmark) {
    $width=900; $height=414; $stride=$width*4
    $bytes = New-Object byte[] ($stride*$height); $random.NextBytes($bytes)
    $expected=$bytes.Clone(); $actual=$bytes.Clone()
    $old = Measure-Command { Invoke-ReferenceFringe $expected $width $height $stride 254 $addon }
    $new = Measure-Command { [LDLCUiPixelBuffer]::RemoveFringe($actual,$width,$height,$stride,254,17,18,19,$false) }
    if (-not $addon) { Assert-Bytes $expected $actual 'benchmark equivalence' }
    Write-Host ('Pixel loop only (not EXE startup): PowerShell {0:N1} ms; compiled {1:N1} ms.' -f $old.TotalMilliseconds,$new.TotalMilliseconds)
}
Write-Host "OK UI pixel buffer: $script:assertions assertions; edition alpha rules preserved."
