param([string]$Artifacts='')
$ErrorActionPreference='Stop'
if($env:OS -ne 'Windows_NT'){throw 'Native preview requires Windows.'}
$root=Split-Path -Parent $PSScriptRoot
if(-not $Artifacts){$Artifacts=Join-Path $root 'artifacts/preview'}
$delivery=Join-Path $root 'tools/PreparationDelivery.Common.ps1'
if(Test-Path $delivery){. $delivery;$exe=(Get-PreparationDelivery $root).ExecutablePath}else{$exe=Join-Path $root 'dist/LDLCPreparationPC_ADDON.exe'}
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('Preparation-UI-'+[guid]::NewGuid().ToString('N'))
$saved=@{}
foreach($name in @('ProgramData','LOCALAPPDATA','LDLC_TELEMETRY_DISABLED','LDLC_PREP_INSTALL_WORKER','NUMERIKS_PREP_STORE_ID','NUMERIKS_PREP_STORE_NAME')){$saved[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
try{
 New-Item -ItemType Directory -Path $testRoot,$Artifacts -Force|Out-Null
 $env:ProgramData=$testRoot;$env:LOCALAPPDATA=$testRoot;$env:LDLC_TELEMETRY_DISABLED='1'
 Remove-Item Env:LDLC_PREP_INSTALL_WORKER -ErrorAction SilentlyContinue
 $assembly=[Reflection.Assembly]::LoadFile($exe)
 $csc=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
 $dll=Join-Path $testRoot 'PreviewTest.dll'
 & $csc /nologo /target:library "/out:$dll" /reference:System.Core.dll /reference:System.Drawing.dll /reference:System.Windows.Forms.dll (Join-Path $PSScriptRoot 'PreparationUiLaunchTest.cs')
 if($LASTEXITCODE -ne 0){throw 'Preview driver compilation failed'}
 $driver=[Reflection.Assembly]::Load([IO.File]::ReadAllBytes($dll)).GetType('PreparationUiLaunchTest')
 try{$json=$driver.GetMethod('Run').Invoke($null,[object[]]@($assembly,$Artifacts))}catch{throw $_.Exception.GetBaseException()}
 $report=$json|ConvertFrom-Json
 $report|Add-Member NoteProperty Scope 'Entree reelle EXE en Preview; aucune installation. Temps depuis EntryPoint, hors UAC/clic utilisateur.'
 $report|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $Artifacts 'geometry.json') -Encoding UTF8
 if($env:GITHUB_ACTIONS -eq 'true'){$text=($report|ConvertTo-Json -Compress).Replace('%','%25').Replace("`r",'%0D').Replace("`n",'%0A');Write-Host "::notice title=PrepTool compiled preview::$text"}
 Write-Host 'OK actual shipped EXE Preview, visible window, usable Quit button; no preparation.'
}finally{
 foreach($name in $saved.Keys){[Environment]::SetEnvironmentVariable($name,$saved[$name],'Process')}
 if(Test-Path $testRoot){Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue}
}
