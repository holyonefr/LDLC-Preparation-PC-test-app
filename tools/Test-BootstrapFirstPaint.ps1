$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$source = [IO.File]::ReadAllText((Join-Path $root 'modules/00.Bootstrap.ps1'))
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw 'Syntaxe bootstrap invalide.' }
foreach ($fn in $ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$true)) {
    . ([scriptblock]::Create($fn.Extent.Text))
}
$bottom=[scriptblock]::Create($source.Substring($source.IndexOf('$script:LDLCRoot = Get-LDLCBasePath')))
$launcherSource=[IO.File]::ReadAllText((Join-Path $root 'modules/95.WorkerLauncher.ps1'))
$launcher=[scriptblock]::Create($launcherSource.Substring($launcherSource.LastIndexOf('$WorkerLauncher = {')))
. $launcher
$realInstall = ${function:Install-LDLCEmbeddedWorkerScript}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('Bootstrap-FirstPaint-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixture)
$workerFile=Join-Path $fixture 'worker.ps1'
[IO.File]::WriteAllText($workerFile,'# fixture non executee')
$saved=@{}
foreach ($key in @('WINDIR','LDLC_WORKER_SMOKE_TEST')) { $saved[$key]=[Environment]::GetEnvironmentVariable($key,'Process') }
$env:WINDIR=$fixture
$env:LDLC_WORKER_SMOKE_TEST=$null
$assertions=0
function Assert-True([bool]$Value,[string]$Message) { if (-not $Value) { throw $Message }; $script:assertions++ }
function Get-LDLCBasePath { return $fixture }
function Get-LDLCWritableRuntimeRoot { return $fixture }
function Remove-LDLCObsoleteEmbeddedFiles {}
function Write-LDLCBootstrapLog { param($Message) }
function Get-LDLCBootstrapSecurityProducts { $script:diagnostics++; return 'Protection test' }
function Install-LDLCEmbeddedUiAssets { param($RuntimeRoot) if ($script:failUi) { throw 'Image bloquee' }; return $true }
function Install-LDLCEmbeddedWorkerScript { param($RuntimeRoot) $script:extractions++; if ($script:failWorker) { throw 'Extraction bloquee' }; return $workerFile }
function Show-LDLCBootstrapFailure { param($Reason,$SecurityProducts) $script:failures++; $script:lastReason=$Reason }
function Start-Process { param($FilePath,$WindowStyle,$ArgumentList,[switch]$PassThru,$ErrorAction) $script:launches++; return [pscustomobject]@{Id=123;HasExited=$false} }
function Reset-Case {
    foreach ($flag in @('Preview','InstallWorker','WindowsUpdateWorker','SecurityCleanupWorker','SecurityIsolationSmokeTest','WorkerSmokeTest','BootstrapTest','SelfTest')) {
        Set-Variable -Name $flag -Value $false -Scope Script
    }
    $script:diagnostics=0; $script:extractions=0; $script:failures=0; $script:launches=0
    $script:failUi=$false; $script:failWorker=$false; $script:lastReason=''
}
try {
    foreach ($previewMode in @($false,$true)) {
        Reset-Case; $Preview=$previewMode
        . $bottom
        Assert-True ($script:diagnostics -eq 0 -and $script:extractions -eq 0) 'Diagnostic/extraction encore executes avant affichage.'
        Assert-True ($null -eq $script:LDLCEmbeddedWorkerScriptPath) 'Worker marque pret avant extraction.'
        if (-not $previewMode) {
            $proc=& $WorkerLauncher
            Assert-True ($script:extractions -eq 1 -and $script:launches -eq 1 -and $proc.Id -eq 123) 'Le lancement differe doit extraire puis lancer le worker.'
            Assert-True ($script:diagnostics -eq 0) 'Le diagnostic normal appartient au processus worker.'
        }
    }
    foreach ($flag in @('InstallWorker','WindowsUpdateWorker','SecurityCleanupWorker','SecurityIsolationSmokeTest','WorkerSmokeTest','BootstrapTest','SelfTest')) {
        Reset-Case
        Set-Variable -Name $flag -Value $true
        . $bottom
        Assert-True ($script:diagnostics -ge 1 -and $script:extractions -eq 1) "Mode explicite incomplet : $flag"
        Assert-True ($script:LDLCEmbeddedWorkerScriptPath -eq $workerFile) "Worker indisponible : $flag"
    }
    Reset-Case; $script:failUi=$true; $caught=$false
    try { . $bottom } catch { $caught=$true }
    Assert-True ($caught -and $script:diagnostics -eq 1 -and $script:failures -eq 1 -and $script:extractions -eq 0) 'Une image bloquee doit garder son diagnostic et interrompre le demarrage.'
    Reset-Case; . $bottom; $script:failWorker=$true; $caught=$false
    try { & $WorkerLauncher | Out-Null } catch { $caught=$true }
    Assert-True ($caught -and $script:launches -eq 0 -and $script:diagnostics -eq 1 -and $script:failures -eq 1) 'Extraction bloquee : aucun lancement, diagnostic et erreur conserves.'
    Reset-Case; $BootstrapTest=$true; $script:failWorker=$true; $caught=$false
    try { . $bottom } catch { $caught=$true }
    Assert-True ($caught -and $script:failures -eq 1 -and $script:lastReason -like 'Installation du worker impossible*') 'BootstrapTest doit signaler une extraction bloquee.'

    # Exercise the actual extractor: delaying it must not weaken payload/cache integrity.
    Set-Item Function:Install-LDLCEmbeddedWorkerScript $realInstall
    $bytes=[Text.Encoding]::UTF8.GetBytes('# worker de test, jamais lance')
    $script:LDLCEmbeddedWorkerPayload=@{Sha256=(Get-LDLCByteArraySha256 $bytes);Base64=[Convert]::ToBase64String($bytes)}
    Initialize-LDLCEmbeddedWorkerState
    Assert-True (Test-LDLCFileHash $script:LDLCEmbeddedWorkerScriptPath $script:LDLCEmbeddedWorkerPayload.Sha256) 'Extraction reelle non conforme.'
    [IO.File]::WriteAllText($script:LDLCEmbeddedWorkerScriptPath,'corrompu')
    Initialize-LDLCEmbeddedWorkerState
    Assert-True (Test-LDLCFileHash $script:LDLCEmbeddedWorkerScriptPath $script:LDLCEmbeddedWorkerPayload.Sha256) 'Cache corrompu non repare.'
    $script:LDLCEmbeddedWorkerPayload.Sha256=('0'*64); $caught=$false
    try { Initialize-LDLCEmbeddedWorkerState } catch { $caught=$true }
    Assert-True $caught 'Payload corrompu accepte.'
    Write-Host "OK : $assertions controles, affichage prioritaire et erreurs de demarrage conservees."
} finally {
    foreach ($key in $saved.Keys) { [Environment]::SetEnvironmentVariable($key,$saved[$key],'Process') }
    Remove-Item -LiteralPath $fixture -Recurse -Force
}
