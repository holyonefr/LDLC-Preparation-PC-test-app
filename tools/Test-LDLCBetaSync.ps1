#requires -Version 5.1
param([string]$OutputDirectory='artifacts/beta-sync')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'PreparationSync.Common.ps1')
$temp=Join-Path ([IO.Path]::GetTempPath()) ('LDLC-Beta-Sync-'+[guid]::NewGuid().ToString('N'))
$a=Join-Path $temp 'stable';$b=Join-Path $temp 'beta';$sync=Join-Path $PSScriptRoot 'Sync-LDLCBeta.ps1'
$cases=New-Object 'Collections.Generic.List[object]';$script:Checks=0
function Assert($v,$m){$script:Checks++;if(-not $v){throw $m}}
function Case($n,[scriptblock]$s){try{&$s;$cases.Add(@{Name=$n;Result='passed'})}catch{$cases.Add(@{Name=$n;Result='failed';Error=$_.Exception.Message});Write-Warning ($n+': '+$_.Exception.Message)}}
function Reject([scriptblock]$s,$pattern){$m='';try{&$s|Out-Null}catch{$m=$_.Exception.Message};Assert ($m -match $pattern) ('Refus attendu : '+$m)}
try{
 foreach($p in @($a,$b)){[void](New-Item -ItemType Directory -Path (Join-Path $p 'modules'),(Join-Path $p 'beta') -Force);& git -C $p init -q}
 & git -C $a remote add origin https://github.com/holyonefr/LDLC-Preparation.git
 & git -C $b remote add origin https://github.com/holyonefr/LDLC-Preparation-PC-test-app.git
 foreach($n in @('a.ps1','overlay.ps1')){foreach($p in @($a,$b)){[IO.File]::WriteAllText((Join-Path $p ('modules/'+$n)),'# initial')}}
 & git -C $a add .
 & git -C $a -c user.name=BetaTest -c user.email=beta-test@example.invalid commit -qm fixture
 @{SourceCommit='fixture';SourceWorkingTreeDirty=$false;OverlayPaths=@('modules/overlay.ps1')}|ConvertTo-Json|Set-Content (Join-Path $b 'beta/sync.json')
 @{'modules/a.ps1'=(Get-PreparationSharedHash (Join-Path $a 'modules/a.ps1'));'modules/overlay.ps1'=(Get-PreparationSharedHash (Join-Path $a 'modules/overlay.ps1'))}|ConvertTo-Json|Set-Content (Join-Path $b 'beta/stable-files.json')
 Case 'Audit leaves identical files unchanged'{&$sync -StableRepository $a -BetaRepository $b|Out-Null;Assert ([IO.File]::ReadAllText((Join-Path $b 'modules/a.ps1')) -eq '# initial') 'Audit modificateur.'}
 Case 'Missing stable correction is detected, then copied only into beta'{
  [IO.File]::WriteAllText((Join-Path $a 'modules/a.ps1'),'# correction')
  Reject {&$sync -StableRepository $a -BetaRepository $b} 'synchroniser'
  &$sync -StableRepository $a -BetaRepository $b -Apply|Out-Null
  Assert ([IO.File]::ReadAllText((Join-Path $b 'modules/a.ps1')) -eq '# correction') 'Correction non copiee.'
  Assert ([IO.File]::ReadAllText((Join-Path $a 'modules/a.ps1')) -eq '# correction') 'Source modifiee.'
 }
 Case 'Conflicting beta edit is preserved'{
  [IO.File]::WriteAllText((Join-Path $b 'modules/a.ps1'),'# beta edit');[IO.File]::WriteAllText((Join-Path $a 'modules/a.ps1'),'# stable edit')
  Reject {&$sync -StableRepository $a -BetaRepository $b -Apply} 'Conflit'
  Assert ([IO.File]::ReadAllText((Join-Path $b 'modules/a.ps1')) -eq '# beta edit') 'Conflit ecrase.'
  Copy-Item (Join-Path $a 'modules/a.ps1') (Join-Path $b 'modules/a.ps1') -Force
  &$sync -StableRepository $a -BetaRepository $b -Apply|Out-Null
 }
 Case 'Overlay change requires explicit merge and keeps beta integration'{
  [IO.File]::WriteAllText((Join-Path $b 'modules/overlay.ps1'),'# beta integration');[IO.File]::WriteAllText((Join-Path $a 'modules/overlay.ps1'),'# newer stable')
  Reject {&$sync -StableRepository $a -BetaRepository $b -Apply} 'fusionner'
  &$sync -StableRepository $a -BetaRepository $b -Apply -AcceptMergedOverlays|Out-Null
  Assert ([IO.File]::ReadAllText((Join-Path $b 'modules/overlay.ps1')) -eq '# beta integration') 'Integration beta perdue.'
 }
 Case 'Stable deletion is propagated while beta-only files remain'{
  [IO.File]::WriteAllText((Join-Path $b 'modules/beta-only.ps1'),'# preserve')
  & git -C $a rm -fq modules/a.ps1
  &$sync -StableRepository $a -BetaRepository $b -Apply|Out-Null
  Assert (-not(Test-Path (Join-Path $b 'modules/a.ps1'))) 'Suppression non propagee.'
  Assert (Test-Path (Join-Path $b 'modules/beta-only.ps1')) 'Fichier beta supprime.'
 }
 Case 'Wrong repository cannot receive a synchronization'{& git -C $b remote set-url origin https://github.com/holyonefr/LDLC-Preparation-Addon.git;Reject {&$sync -StableRepository $a -BetaRepository $b -Apply} 'incorrect'}
}finally{Remove-Item -LiteralPath $temp -Recurse -Force}
[void](New-Item -ItemType Directory -Path $OutputDirectory -Force)
$report=@{Kind='beta_sync_tests';Cases=@($cases.ToArray());Assertions=$script:Checks;Failures=@($cases.ToArray()|Where-Object Result -eq failed).Count;Mode='local_git_fixtures_no_push_no_network'}
$report|ConvertTo-Json -Depth 6|Set-Content (Join-Path $OutputDirectory 'beta-sync.json') -Encoding UTF8
Import-Module (Join-Path $root 'tools/experimental/motherboard/MotherboardExperiment.psm1') -Force
Write-MbxEvidence -Kind 'beta_sync_tests' -Data $report
if($report.Failures){throw "$($report.Failures) synchronisation beta en echec."}
Write-Host "$($cases.Count) scenarios synchro / $script:Checks assertions reussis."
