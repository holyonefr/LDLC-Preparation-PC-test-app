param(
    [string]$ExePath,
    [string]$Version,
    [string]$SigningThumbprint,
    [switch]$RequireSignature
)

$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'PreparationDelivery.Common.ps1')
if ([string]::IsNullOrWhiteSpace($ExePath)) { $ExePath = (Get-PreparationDelivery $root).ExecutablePath }
$exeFullPath = [System.IO.Path]::GetFullPath($ExePath)
$exeDirectory = Split-Path -Parent $exeFullPath
$backupPath = $null

if (Test-Path -LiteralPath $exeFullPath -PathType Leaf) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupPath = Join-Path $exeDirectory ($([IO.Path]::GetFileName($exeFullPath)) + ".backup-$stamp")
    Copy-Item -LiteralPath $exeFullPath -Destination $backupPath -Force
}

$buildArguments = @{
    OutputPath = $exeFullPath
}
if (-not [string]::IsNullOrWhiteSpace($Version)) { $buildArguments.Version = $Version }
if (-not [string]::IsNullOrWhiteSpace($SigningThumbprint)) {
    $buildArguments.SigningThumbprint = $SigningThumbprint
}
if ($RequireSignature) {
    $buildArguments.RequireSignature = $true
}

$result = & (Join-Path $PSScriptRoot 'Build-LDLCPreparationPCExe.ps1') @buildArguments
if (-not (Test-Path -LiteralPath $exeFullPath -PathType Leaf)) {
    throw "Executable non genere : $exeFullPath"
}

[pscustomobject]@{
    Executable = $exeFullPath
    Backup = $backupPath
    Build = $result
}
