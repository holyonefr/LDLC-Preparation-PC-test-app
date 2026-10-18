# Read-only dashboard checks. No change to telemetry POST/queue or validation rules.
function Get-LDLCDashboardReadFailure {
    param([Exception]$Exception)
    $current = $Exception
    while ($current.InnerException -and $current -isnot [Net.WebException]) { $current = $current.InnerException }
    $http = $null
    if ($current -is [Net.WebException] -and $current.Response) {
        try { $http = [int]$current.Response.StatusCode } catch {}
    }
    $status = if ($current -is [Net.WebException]) { [string]$current.Status } else { $current.GetType().Name }
    $transient = ($http -in @(408,429,500,502,503,504)) -or
        ($null -eq $http -and $status -in @('Timeout','ConnectFailure','ConnectionClosed','KeepAliveFailure','ReceiveFailure','SendFailure','NameResolutionFailure','ProxyNameResolutionFailure'))
    return [pscustomobject]@{ HttpStatus=$http; NetworkStatus=$status; Transient=[bool]$transient }
}

function Invoke-LDLCDashboardRead {
    param(
        [Parameter(Mandatory=$true)][uri]$Uri,
        [Parameter(Mandatory=$true)][string]$Stage,
        [ValidateRange(1,3)][int]$MaxAttempts=3,
        [ValidateRange(1,45)][int]$TimeoutSeconds=45,
        [AllowNull()][AllowEmptyCollection()]$Diagnostics=$null
    )
    for ($attempt=1; $attempt -le $MaxAttempts; $attempt++) {
        $clock=[Diagnostics.Stopwatch]::StartNew()
        $failure=$null; $response=$null
        try {
            $response=Invoke-RestMethod -Uri $Uri -Method Get -TimeoutSec $TimeoutSeconds -ErrorAction Stop
        }
        catch { $failure=Get-LDLCDashboardReadFailure -Exception $_.Exception }
        $clock.Stop()
        if ($null -eq $failure) {
            # A valid HTTP response is not evidence of a valid dashboard contract.
            $valid=($null -ne $response -and $response.ok -eq $true -and $null -ne $response.runs)
            if ($null -ne $Diagnostics) {
                [void]$Diagnostics.Add([pscustomobject]@{Stage=$Stage;Attempt=$attempt;Success=[bool]$valid;HttpStatus=200;NetworkStatus=if($valid){'OK'}else{'InvalidDashboardResponse'};Transient=$false;Milliseconds=$clock.ElapsedMilliseconds})
            }
            if (-not $valid) { throw [InvalidOperationException]::new("Lecture dashboard invalide ($Stage) : reponse non acquittee ou liste absente. Aucun resultat valide deduit.") }
            return $response
        }
        if ($null -ne $Diagnostics) {
            [void]$Diagnostics.Add([pscustomobject]@{Stage=$Stage;Attempt=$attempt;Success=$false;HttpStatus=$failure.HttpStatus;NetworkStatus=$failure.NetworkStatus;Transient=$failure.Transient;Milliseconds=$clock.ElapsedMilliseconds})
        }
        if (-not $failure.Transient -or $attempt -eq $MaxAttempts) {
            $detail=if($null -ne $failure.HttpStatus){'HTTP '+$failure.HttpStatus+' / '+$failure.NetworkStatus}else{$failure.NetworkStatus}
            # Do not retain the original exception/URL/body: they can contain credentials.
            throw [InvalidOperationException]::new("Lecture dashboard impossible ($Stage), tentative $attempt/$MaxAttempts : $detail.")
        }
        Start-Sleep -Seconds $attempt
    }
}
