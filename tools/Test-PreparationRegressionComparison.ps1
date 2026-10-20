#requires -Version 5.1
param([string]$ReferenceRevision='ba8257821e7d5aaf53b5c0508116e6107dfc3e46')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$shell=[Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
$directory=Join-Path ([IO.Path]::GetTempPath()) ('Preparation-BeforeAfter-'+[guid]::NewGuid().ToString('N'))
$checks=@()
try {
    [void](New-Item -ItemType Directory -Path $directory)
    foreach($module in @('05.Telemetry.ps1','70.DefaultApps.ps1','72.ChromeTaskbar.ps1')) {
        $text=@(& git -C $root show ($ReferenceRevision+':modules/'+$module))
        if($LASTEXITCODE -ne 0){throw 'Historical reference missing; fetch the exact revision before this test.'}
        [IO.File]::WriteAllText((Join-Path $directory $module),($text -join "`n").TrimStart([char]0xFEFF),(New-Object Text.UTF8Encoding($true)))
    }
    foreach($test in @(
        @{File='Test-TelemetryDeliveryRecovery.ps1';Failure='synthetic-credential-never-log'},
        @{File='Test-ChromeQuickConfirmation.ps1';Failure='working UIA Invoke'},
        @{File='Test-LDLCChromeTaskbarPin.ps1';Failure='no-effect pin command'}
    )) {
        foreach($phase in @('before','after')) {
            $moduleRoot=if($phase -eq 'before'){$directory}else{Join-Path $root 'modules'}
            $previousPreference=$ErrorActionPreference
            try {
                $ErrorActionPreference='Continue'
                $output=@(& $shell -NoProfile -File (Join-Path $PSScriptRoot $test.File) -ModuleRoot $moduleRoot 2>&1)
                $code=$LASTEXITCODE
            } finally { $ErrorActionPreference=$previousPreference }
            if($phase -eq 'before') {
                if($code -eq 0 -or ($output -join "`n") -notmatch [regex]::Escape($test.Failure)){
                    $output | ForEach-Object { Write-Host ([string]$_) }
                    throw ('Expected historical regression was not reproduced: '+$test.File+' (exit '+$code+')')
                }
            } elseif($code -ne 0) {
                # Only local synthetic fixture output; never include HTTP/token details.
                throw ('Corrected regression test failed: '+$test.File)
            }
            $checks+=@{Test=$test.File;Phase=$phase;ExitCode=$code;ExpectedResult=$true}
        }
    }
    $evidence=@{ReferenceRevision=$ReferenceRevision;Checks=$checks;Failures=0;Mode='same simulated OS/HTTP fixtures before and after; native isolated shortcuts on Windows';RealDefaultsOrTaskbarChanged=$false}
    Write-Host ('::notice title=Preparation regression comparison::'+($evidence|ConvertTo-Json -Depth 5 -Compress))
} finally {
    if(Test-Path $directory){Remove-Item $directory -Recurse -Force}
}
