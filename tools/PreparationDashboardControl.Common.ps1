# Test administration only. Never used by the application's telemetry transport.
function Invoke-LDLCDashboardTestControl {
    param([uri]$Uri,[hashtable]$Body,[ValidateRange(1,3)][int]$MaxAttempts=3,$Diagnostics=$null)
    $action=[string]$Body.action
    if($action -notin @('auditruns','deleterun')){throw 'Unsupported dashboard test control action.'}
    if($action -eq 'deleterun' -and [string]$Body.RunId -notmatch '^CODEX-TEST-CORRECTION-[0-9a-f]{32}-(success|failed|stopped)$'){throw 'Refusing deletion outside owned dashboard test reports.'}
    for($attempt=1;$attempt -le $MaxAttempts;$attempt++){
        $failure=$null;$response=$null
        try{$response=Invoke-RestMethod -Uri $Uri -Method Post -ContentType 'application/json; charset=utf-8' -Body ($Body|ConvertTo-Json -Depth 14 -Compress) -TimeoutSec 45 -ErrorAction Stop}
        catch{$failure=Get-LDLCDashboardReadFailure -Exception $_.Exception}
        if($null -eq $failure){
            $valid=($null -ne $response -and $response.ok -eq $true)
            if($null -ne $Diagnostics){[void]$Diagnostics.Add(@{Action=$action;Attempt=$attempt;Success=[bool]$valid;HttpStatus=200;NetworkStatus=if($valid){'OK'}else{'InvalidAcknowledgement'};Transient=$false})}
            if(-not $valid){throw [InvalidOperationException]::new('Dashboard test control not acknowledged: '+$action+'.')}
            return $response
        }
        if($null -ne $Diagnostics){[void]$Diagnostics.Add(@{Action=$action;Attempt=$attempt;Success=$false;HttpStatus=$failure.HttpStatus;NetworkStatus=$failure.NetworkStatus;Transient=$failure.Transient})}
        if(-not $failure.Transient -or $attempt -eq $MaxAttempts){
            throw [InvalidOperationException]::new('Dashboard test control failed: '+$action+', attempt '+$attempt+'/'+$MaxAttempts+', '+$failure.NetworkStatus+'.')
        }
        Start-Sleep -Seconds $attempt
    }
}
