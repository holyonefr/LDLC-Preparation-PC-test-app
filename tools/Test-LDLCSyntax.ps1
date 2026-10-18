$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$targets = @()
$targets += Get-ChildItem -LiteralPath (Join-Path $root 'modules') -Filter '*.ps1' -File
if (Test-Path -LiteralPath (Join-Path $root 'dist')) {
    $targets += Get-ChildItem -LiteralPath (Join-Path $root 'dist') -Filter '*.ps1' -File
}

$hadErrors = $false

foreach ($file in $targets) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors) | Out-Null

    if ($errors -and $errors.Count -gt 0) {
        $hadErrors = $true
        Write-Host "ERREUR $($file.FullName)"
        foreach ($errorItem in $errors) {
            Write-Host ("  ligne {0}: {1}" -f $errorItem.Extent.StartLineNumber, $errorItem.Message)
        }
    }
    else {
        Write-Host "OK $($file.Name)"
    }
}

if ($hadErrors) {
    exit 1
}
