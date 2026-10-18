$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'PreparationDelivery.Common.ps1')
function Assert-Delivery([bool]$Value, [string]$Message) { if (-not $Value) { throw $Message } }
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('Preparation-Delivery-Test-' + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path (Join-Path $fixture 'sync') -Force | Out-Null
    $profilePath = Join-Path $fixture 'sync/edition.json'
    $default = Get-PreparationDelivery $fixture
    Assert-Delivery ($default.BaseName -eq 'LDLCPreparationPC') 'Legacy checkout keeps LDLC filenames.'
    @{ SchemaVersion=1; Edition='LDLC' } | ConvertTo-Json | Set-Content -LiteralPath $profilePath
    Assert-Delivery ((Get-PreparationDelivery $fixture).ExecutablePath -eq (Join-Path $fixture 'dist/LDLCPreparationPC.exe')) 'LDLC profile without overrides.'
    @{ SchemaVersion=1; Edition='NUMERIKS'; DeliveryBaseName="Numerik'sPreparationPC" } | ConvertTo-Json | Set-Content -LiteralPath $profilePath
    $numeriks = Get-PreparationDelivery $fixture
    Assert-Delivery ($numeriks.BaseName -ceq "Numerik'sPreparationPC") 'Keep requested spelling and apostrophe.'
    Assert-Delivery ($numeriks.ArtifactPaths.Count -eq 5 -and $numeriks.ArtifactPaths[1] -ceq "dist/Numerik'sPreparationPC.exe.config") 'Config has the exact executable basename.'
    Assert-Delivery ($numeriks.MainScriptPath -eq (Join-Path $fixture "dist/Numerik'sPreparationPC.ps1") -and
        $numeriks.WorkerScriptPath -eq (Join-Path $fixture "dist/Numerik'sPreparationPC.worker.embed.ps1")) 'Main script and worker use edition filenames.'
    $testPath = $numeriks.MainScriptPath
    New-Item -ItemType Directory -Path (Split-Path $testPath -Parent) -Force | Out-Null
    [IO.File]::WriteAllText($testPath, "'apostrophe path works'")
    Assert-Delivery ((& $testPath) -eq 'apostrophe path works') 'PowerShell executes a literal apostrophe filename.'
    foreach ($invalid in @('', '../outside', 'C:/outside', 'two names', 'NUL', 'CON', 'name.exe', 'name*')) {
        @{ SchemaVersion=1; DeliveryBaseName=$invalid } | ConvertTo-Json | Set-Content -LiteralPath $profilePath
        $rejected = $false
        try { Get-PreparationDelivery $fixture | Out-Null } catch { $rejected = $true }
        Assert-Delivery $rejected "Invalid delivery name rejected: $invalid"
    }
    Write-Host 'OK edition delivery: LDLC defaults, Numeriks filenames, matching config/worker, apostrophe execution, unsafe paths rejected.'
} finally {
    $resolved = [IO.Path]::GetFullPath($fixture)
    if ($resolved.StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path $resolved -Leaf) -like 'Preparation-Delivery-Test-*') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
