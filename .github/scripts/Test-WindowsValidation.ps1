$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT' -or $PSVersionTable.PSEdition -ne 'Desktop') {
    throw 'Executer cette validation avec Windows PowerShell 5.1 sous Windows.'
}
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$artifacts = Join-Path $root 'artifacts'
New-Item -ItemType Directory -Path $artifacts -Force | Out-Null
$powershell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$checks = New-Object 'Collections.Generic.List[object]'
$transcriptStarted = $false
$success = $false

function Invoke-WindowsValidationCheck {
    param([string]$Name, [string]$Script, [string[]]$Arguments = @())
    $started = Get-Date
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $priorPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& $powershell -STA -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root $Script) @Arguments 2>&1)
        $code = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $priorPreference }
    $output | ForEach-Object { Write-Host $_ }
    if ($code -ne 0 -and $env:GITHUB_ACTIONS -eq 'true') {
        $detail = $Script + ' : ' + (($output | Select-Object -Last 16 | ForEach-Object { [string]$_ }) -join "`n")
        $detail = $detail -replace 'https?://\S+', '[adresse]' -replace 'LDLC-(Dashboard|PrepTool)-[A-Za-z0-9-]+', '[cle]'
        $detail = $detail.Replace('%', '%25').Replace("`r", '%0D').Replace("`n", '%0A')
        Write-Host "::error title=Windows sous-test::$detail"
    }
    $clock.Stop()
    $checks.Add([pscustomobject]@{
        Name = $Name; Started = $started.ToUniversalTime().ToString('o')
        ExitCode = $code; Seconds = [math]::Round($clock.Elapsed.TotalSeconds, 3)
    })
    if ($code -ne 0) { throw "Validation Windows en echec : $Name (code $code)." }
}

try {
    Start-Transcript -LiteralPath (Join-Path $artifacts 'validation-windows.log') -Force | Out-Null
    $transcriptStarted = $true
    . (Join-Path $root 'tools\PreparationDelivery.Common.ps1')
    $delivery = Get-PreparationDelivery $root
    $expected = (Get-Content -LiteralPath (Join-Path $root 'dist\SHA256SUMS.txt') -Raw).Trim()
    $hash = (Get-FileHash -LiteralPath $delivery.ExecutablePath -Algorithm SHA256).Hash
    $actual = '{0} *{1}' -f $hash, [IO.Path]::GetFileName($delivery.ExecutablePath)
    if ($expected -cne $actual) { throw 'La livraison Git LFS ne correspond pas a SHA256SUMS.txt.' }
    Write-Host "Livraison recue : $hash"

    Invoke-WindowsValidationCheck -Name 'Lancement Preview du vrai EXE livre et bouton Quitter' `
        -Script 'tools/Test-PreparationUiLaunch.ps1'

    Invoke-WindowsValidationCheck -Name 'Compilation Windows PowerShell 5.1 et C#' `
        -Script 'tools\Build-LDLCPreparationPCExe.ps1'
    Invoke-WindowsValidationCheck -Name 'Suite release Windows et diagnostics du lanceur compile' `
        -Script 'tools\Test-LDLCRelease.ps1'
    Invoke-WindowsValidationCheck -Name 'Comparaison avant apres des 7 scenarios de finalisation' `
        -Script '.github/scripts/Test-CompletionComparison.ps1'
    Invoke-WindowsValidationCheck -Name 'BETA modules embarques, portable exclu et erreurs visibles' `
        -Script 'tools/Test-LDLCBetaVendorUtility.ps1'
    Invoke-WindowsValidationCheck -Name 'BETA fin de la phase Installation et respect des arrets' `
        -Script 'tools/Test-LDLCBetaPlacement.ps1'
    Invoke-WindowsValidationCheck -Name 'BETA synchronisation sans modification des productions' `
        -Script 'tools/Test-LDLCBetaSync.ps1'
    for($launch=1;$launch -le 3;$launch++) {
        Invoke-WindowsValidationCheck -Name ("BETA ouverture fermeture du vrai EXE compile $launch sur 3") `
            -Script 'tools/Test-PreparationUiLaunch.ps1' `
            -Arguments @('-Artifacts',(Join-Path $artifacts ("compiled-launch-$launch")))
    }
    $success = $true
}
finally {
    $report = [ordered]@{
        Commit = $env:GITHUB_SHA; Passage = $env:NUMERIKS_VALIDATION_PASS
        Windows = [Environment]::OSVersion.VersionString
        PowerShell = $PSVersionTable.PSVersion.ToString()
        UserInteractive = [Environment]::UserInteractive
        Success = $success; Checks = @($checks.ToArray())
        Scope = 'Windows Server 2022: beta livree puis compilee, suite release, comparaison historique, integration constructeur, placement et synchronisation ; 4 Preview/fermetures par passage. Actions systeme/installeurs/Chrome simules ; aucune preparation destructive ni installation reelle.'
    }
    $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $artifacts 'resultat.json') -Encoding UTF8
    if ($transcriptStarted) { Stop-Transcript | Out-Null }
    if ($env:GITHUB_ACTIONS -eq 'true') {
        # Publish the actual process exit codes in the run's check annotations,
        # so they can be reviewed directly in the GitHub test overview.
        $message = ($report | ConvertTo-Json -Depth 6 -Compress).Replace('%', '%25').Replace("`r", '%0D').Replace("`n", '%0A')
        Write-Host "::notice title=LDLC Windows result::$message"
        if ($env:GITHUB_STEP_SUMMARY) {
            $summary = @('## LDLC - codes de sortie Windows', '', '| Controle | Code |', '| --- | --- |')
            foreach ($check in $checks) { $summary += '| {0} | {1} |' -f $check.Name, $check.ExitCode }
            $summary += '', ('Resultat du passage : {0}' -f $success)
            $summary | Out-File -LiteralPath $env:GITHUB_STEP_SUMMARY -Encoding utf8 -Append
        }
    }
}
