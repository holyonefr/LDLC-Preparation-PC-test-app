#requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory)][string]$StableRepository,[string]$BetaRepository=(Split-Path -Parent $PSScriptRoot),[switch]$Apply,[switch]$AcceptMergedOverlays)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PreparationSync.Common.ps1')
function Get-BetaFileHash([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }
    if ([IO.Path]::GetExtension($Path) -in @('.exe','.png','.jpg','.jpeg','.ico','.zip','.ttf','.woff','.woff2')) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
    return Get-PreparationSharedHash $Path
}
function Get-BetaSafePath([string]$Root,[string]$Relative) {
    if ($Relative -match '(^[/\\]|\\|(^|/)\.\.(/|$)|:|^\.git(/|$))') { throw 'Chemin de synchronisation beta dangereux.' }
    return Join-Path $Root $Relative
}
$stable=[IO.Path]::GetFullPath($StableRepository);$beta=[IO.Path]::GetFullPath($BetaRepository)
foreach ($item in @(@{Path=$stable;Url='https://github.com/holyonefr/LDLC-Preparation.git'},@{Path=$beta;Url='https://github.com/holyonefr/LDLC-Preparation-PC-test-app.git'})) {
    $origin=& git -C $item.Path remote get-url origin
    if ($LASTEXITCODE -ne 0 -or ($origin.TrimEnd('/') -replace '\.git$','') -cne ($item.Url -replace '\.git$','')) { throw 'Depot source/cible beta incorrect ; aucune modification.' }
}
$configPath=Join-Path $beta 'beta/sync.json';$statePath=Join-Path $beta 'beta/stable-files.json'
$config=Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$state=Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
$previous=@{};foreach($p in $state.PSObject.Properties){$previous[$p.Name]=[string]$p.Value}
$files=@(& git -C $stable -c core.quotepath=false ls-files)
if($LASTEXITCODE -ne 0){throw 'Inventaire du depot stable impossible.'}
$incoming=@{};foreach($file in $files){$incoming[$file]=Get-BetaFileHash (Get-BetaSafePath $stable $file)}
$plan=@();$conflicts=@()
foreach($file in @(@($previous.Keys)+$files | Sort-Object -Unique)){
    $old=if($previous.ContainsKey($file)){$previous[$file]}else{''}
    $next=if($incoming.ContainsKey($file)){$incoming[$file]}else{''}
    $current=Get-BetaFileHash (Get-BetaSafePath $beta $file)
    if($file -like 'dist/*'){continue} # Always rebuild beta deliveries, never copy stable binaries.
    if($file -in $config.OverlayPaths){
        if($next -ne $old -and -not $AcceptMergedOverlays){$conflicts+=('Overlay a fusionner : '+$file)}
        continue
    }
    if($current -eq $next){continue}
    if($current -ne $old){$conflicts+=('Conflit beta/source : '+$file);continue}
    if($next -ne $old){$plan+=@([pscustomobject]@{Path=$file;Action=if($next){'copy'}else{'delete'}})}
}
if($conflicts.Count){throw ($conflicts -join "`n")}
$plan | Format-Table -AutoSize
if(-not $Apply){
    if($plan.Count){throw ('Beta a synchroniser : '+$plan.Count+' fichier(s). Ajouter -Apply apres audit.')}
    Write-Host ('Beta synchronisee avec les sources disponibles ; overlays preserves. Source : '+$config.SourceCommit)
    return
}
foreach($entry in $plan){
    $target=Get-BetaSafePath $beta $entry.Path
    if($entry.Action -eq 'delete'){Remove-Item -LiteralPath $target -Force}else{
        [void](New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force)
        Copy-Item -LiteralPath (Get-BetaSafePath $stable $entry.Path) -Destination $target -Force
    }
}
$sourceCommit=& git -C $stable rev-parse HEAD
if($LASTEXITCODE -ne 0){throw 'Commit source indisponible.'}
$config.SourceCommit=[string]$sourceCommit
$config.SourceWorkingTreeDirty=[bool]@(& git -C $stable status --porcelain).Count
$incoming | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $statePath -Encoding UTF8
$config | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $configPath -Encoding UTF8
Write-Host 'Sources beta synchronisees. Recompiler et tester avant publication. Aucun push effectue.'
