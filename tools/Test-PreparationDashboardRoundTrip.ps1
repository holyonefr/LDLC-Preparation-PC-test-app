param([string]$ReportPath='')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'modules/00.Core.ps1')
. (Join-Path $root 'modules/05.Telemetry.ps1')
. (Join-Path $PSScriptRoot 'PreparationDashboardRead.Common.ps1')
$script:dashboardReads = New-Object 'Collections.Generic.List[object]'
$report=[ordered]@{Success=$false;Commit=$env:GITHUB_SHA;Checks=@();Cleaned=$false;Scope='Rapports CODEX-TEST uniquement; client reel, dashboard permanent, aucun historique modifie.'}
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('Preparation-Live-'+[guid]::NewGuid().ToString('N'))
$prefix='CODEX-TEST-CORRECTION-'+[guid]::NewGuid().ToString('N')
$ids=@();$saved=@{}
foreach($name in @('LDLC_TELEMETRY_DISABLED','LDLC_TELEMETRY_RUN_ID','LDLC_TELEMETRY_STARTED_AT','LDLC_TELEMETRY_REMOTE_MODE')){$saved[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
function Get-LDLCRuntimeRoot { return $script:RuntimeRoot }
function Get-LDLCComputerTelemetryInfo { [pscustomobject]@{ComputerName='CODEX-TEST-WINDOWS';UserName='';UserDomain='';SerialNumber='';Manufacturer='TEST';Model='TEST';OSCaption='Windows test';OSVersion='';TimeZone='UTC'} }
function Get-LDLCEntryPointPath { return 'CODEX-TEST-CORRECTION' }
function Post-Control($body) {
 $body.apiKey=Get-LDLCTelemetryApiKey
 $response=Invoke-RestMethod -Uri (Get-LDLCTelemetryEndpointUrl) -Method Post -ContentType 'application/json; charset=utf-8' -Body ($body|ConvertTo-Json -Depth 14 -Compress) -TimeoutSec 45
 if(-not $response -or $response.ok -ne $true){throw 'Controle serveur non acquitte'}
 return $response
}
function Snapshot {
 param([string]$Stage='preflight')
 return (Invoke-LDLCDashboardRead -Uri $script:snapshotUri -Stage $Stage -Diagnostics $script:dashboardReads)
}
try {
 $server=Get-Content -LiteralPath (Join-Path $root 'tools/google-apps-script/LDLC_ErrorTelemetry.gs') -Raw
 $script:dashboardKey=[regex]::Match($server,"DASHBOARD_PASSWORD:\s*'([^']+)'").Groups[1].Value
 if(-not $script:dashboardKey -or -not (Test-LDLCTelemetryConfigured)){throw 'Configuration live absente'}
 $script:snapshotUri=(Get-LDLCTelemetryEndpointUrl)+'?format=json&key='+[uri]::EscapeDataString($script:dashboardKey)
 $report.Phase='lecture dashboard et droit de nettoyage'
 $before=Snapshot
 [void](Post-Control @{action='auditruns';adminKey=$script:dashboardKey;includeRows=$false})
 $env:LDLC_TELEMETRY_DISABLED='0';$env:LDLC_TELEMETRY_REMOTE_MODE='start-final'
 Remove-Item Env:LDLC_TELEMETRY_STARTED_AT -ErrorAction SilentlyContinue
 # Read only constant telemetry metadata from the delivered script; never execute its preparation.
 $deliveryHelper=Join-Path $root 'tools/PreparationDelivery.Common.ps1'
 if(Test-Path $deliveryHelper){. $deliveryHelper;$mainScript=(Get-PreparationDelivery $root).MainScriptPath}else{$mainScript=Join-Path $root 'dist/LDLCPreparationPC.ps1'}
 $delivered=[Management.Automation.Language.Parser]::ParseFile($mainScript,[ref]$null,[ref]$null)
 foreach($name in @('LDLCTelemetryEndpointUrl','LDLCTelemetryApiKey','LDLCTelemetryToolVersion','LDLCTelemetrySource','LDLCTelemetryApplicationSource','LDLCTelemetryEdition','LDLCTelemetrySendSuccessfulRuns')){
  $assignment=$delivered.Find({param($n)$n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left -is [Management.Automation.Language.VariableExpressionAst] -and $n.Left.VariablePath.UserPath -eq ('script:'+$name)},$true)
  if(-not $assignment){throw 'Configuration livree absente'}
  $literal=$assignment.Right.Find({param($n)$n -is [Management.Automation.Language.StringConstantExpressionAst]},$true)
  if($literal){$value=$literal.Value}
  elseif($assignment.Right.Extent.Text.Trim() -eq '$true'){$value=$true}
  elseif($assignment.Right.Extent.Text.Trim() -eq '$false'){$value=$false}
  else{throw 'Configuration livree non constante'}
  Set-Variable -Scope Script -Name $name -Value $value
 }
 $script:snapshotUri=(Get-LDLCTelemetryEndpointUrl)+'?format=json&key='+[uri]::EscapeDataString($script:dashboardKey)
 foreach($case in @('success','failed','stopped')){
  $report.Phase='scenario '+$case
  $id=$prefix+'-'+$case;$ids+= $id;$env:LDLC_TELEMETRY_RUN_ID=$id
  if($env:GITHUB_ACTIONS -eq 'true'){Write-Host ('::notice title=PrepTool live test ownership::'+$id)}
  $script:RuntimeRoot=Join-Path $testRoot $case;New-Item -ItemType Directory -Path $script:RuntimeRoot -Force|Out-Null
  $script:ProgressFile=Join-Path $script:RuntimeRoot 'LDLC_PROGRESS.txt';$script:StopFile=Join-Path $script:RuntimeRoot 'LDLC_STOP'
  $script:LDLCTelemetryInitialized=$false
  Initialize-LDLCTelemetry
  if(-not $script:LDLCTelemetryLastSentAt -or $script:LDLCTelemetryLastSentAt -eq [datetime]::MinValue){throw 'Debut non acquitte'}
  $initial=Snapshot -Stage ("scenario_${case}_initial");$row=@($initial.runs|Where-Object runId -eq $id)
  if($row.Count -ne 1 -or $row[0].isFinal){throw 'Debut non visible sur dashboard'}
  if($case -eq 'failed'){Add-LDLCTelemetryEvent -Message 'CODEX-TEST uniquement : installation refusee code 1603' -Severity error -Type 'TEST' -Step 'CODEX-TEST'}
  Complete-LDLCTelemetryRun -ResultStatus $case -WorkflowCompleted ($case -ne 'stopped')
  if(@(Read-LDLCQueuedTelemetryPayloads).Count -ne 0){throw 'Fin non acquittee, file locale encore presente'}
  $final=Snapshot -Stage ("scenario_${case}_final");$rows=@($final.runs|Where-Object runId -eq $id)
  if($rows.Count -ne 1 -or -not $rows[0].isFinal){throw 'Fin non visible sur dashboard'}
  $observed=[string]$rows[0].status
  $allowed=switch($case){'success' {@('success','completed')} 'failed' {@('failed','error')} 'stopped' {@('stopped')}}
  if($observed -notin $allowed){throw 'Statut dashboard incorrect'}
  if([string]$rows[0].version -ne $script:LDLCTelemetryToolVersion){throw 'Edition/version dashboard incorrecte'}
  if($rows[0].applicationSource -and $rows[0].applicationSource -ne $script:LDLCTelemetryApplicationSource){throw 'Edition dashboard incorrecte'}
  if($case -eq 'failed' -and [string]$rows[0].lastMessage -notmatch '1603'){throw 'Cause 1603 non visible sur dashboard'}
  $validation=if($rows[0].validation){[string]$rows[0].validation.state}else{'non_exposee'}
  if($validation -ne 'non_exposee'){
   $expectedValidation=if($case -eq 'success'){'validated'}else{'blocked'}
   if($validation -ne $expectedValidation){throw 'Statut validation dashboard incorrect'}
  }
  $report.Checks+=@{Scenario=$case;Status=$observed;Validation=$validation;InitialVisible=$true;FinalVisible=$true;Acknowledged=$true;ApplicationSource=$script:LDLCTelemetryApplicationSource;ToolVersion=$script:LDLCTelemetryToolVersion}
 }
 $report.Success=$true
}
catch { $report.ErrorType=$_.Exception.GetType().Name; $report.Reason=if($_.Exception.Message -match '^(Debut|Fin|Statut|Edition|Cause|Dashboard|Controle|Configuration|Lecture dashboard)'){$_.Exception.Message}else{'Erreur reseau ou serveur, details sensibles masques.'} }
finally {
 $cleanupOk=$true
 foreach($id in $ids){try{[void](Post-Control @{action='deleterun';adminKey=$script:dashboardKey;RunId=$id})}catch{$cleanupOk=$false}}
 if($ids.Count){try{$after=Snapshot -Stage 'cleanup_verify';if(@($after.runs|Where-Object{$_.runId -in $ids}).Count){$cleanupOk=$false}}catch{$cleanupOk=$false}}
 $report.ReadAttempts=@($script:dashboardReads.ToArray())
 $report.Cleaned=$cleanupOk
 if(-not $cleanupOk){$report.Success=$false;$report.CleanupRunIds=$ids}
 foreach($name in $saved.Keys){[Environment]::SetEnvironmentVariable($name,$saved[$name],'Process')}
 if(Test-Path -LiteralPath $testRoot){Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue}
 if(-not $ReportPath){$ReportPath=Join-Path $root 'artifacts/dashboard-roundtrip.json'}
 New-Item -ItemType Directory -Path (Split-Path -Parent $ReportPath) -Force|Out-Null
 $report|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $ReportPath -Encoding UTF8
 if($env:GITHUB_ACTIONS -eq 'true'){$message=($report|ConvertTo-Json -Depth 8 -Compress).Replace('%','%25').Replace("`r",'%0D').Replace("`n",'%0A');Write-Host "::notice title=PrepTool dashboard roundtrip::$message"}
 else{Write-Host ($report|ConvertTo-Json -Depth 8 -Compress)}
}
if(-not $report.Success){exit 1}
