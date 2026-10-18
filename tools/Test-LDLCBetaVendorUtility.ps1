#requires -Version 5.1
param([string]$OutputDirectory='artifacts/beta-vendor')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$cases=New-Object 'Collections.Generic.List[object]';$script:Checks=0
function Assert($v,$m){$script:Checks++;if(-not $v){throw $m}}
function Case($n,[scriptblock]$b){try{&$b;$cases.Add(@{Name=$n;Result='passed'})}catch{$cases.Add(@{Name=$n;Result='failed';Error=$_.Exception.Message});Write-Warning ($n+': '+$_.Exception.Message)}}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('LDLC-Beta-Vendor-'+[guid]::NewGuid().ToString('N'))
$script:RuntimeRoot=$temp;[void](New-Item -ItemType Directory -Path $temp)
$script:Events=@();$script:Stopped=$false;$script:InitCalls=0
function Stop-IfRequested {if($script:Stopped){throw 'LDLC_STOP_REQUESTED'}}
function Test-LDLCStopRequestError($e){return $e.Exception.Message -match 'LDLC_STOP_REQUESTED'}
function Write-ProgressFile {param($p,$m)}
function Write-Ok($m){$script:Events+=@{Level='ok';Message=$m}}
function Write-Warn($m){$script:Events+=@{Level='warning';Message=$m}}
function Write-Step($m){$script:Events+=@{Level='step';Message=$m}}
. (Join-Path $root 'modules/85.VendorUtility.ps1')
$tree=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'dist/LDLCPreparationPC.worker.embed.ps1'),[ref]$null,[ref]$null)
$assignment=$tree.Find({param($n)$n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -ceq '$script:LDLCVendorUtilityPayloads'},$true)
try {
    Case 'Five actual utility sources are embedded with valid hashes' {
        Assert ($null -ne $assignment) 'Payload absent du worker.'
        . ([scriptblock]::Create($assignment.Extent.Text))
        Assert ($script:LDLCVendorUtilityPayloads.Count -eq 5) 'Nombre de modules incorrect.'
        $module=Initialize-LDLCVendorUtilityModule
        Assert ($module.Name -eq 'VendorUtility') 'Module reel non charge.'
        foreach($p in $script:LDLCVendorUtilityPayloads){
            $source=Join-Path $root ('tools/experimental/'+$p.Path)
            Assert ((Get-FileHash -LiteralPath $source).Hash -ceq $p.Sha256) ('Mauvaise empreinte source : '+$p.Path)
        }
        $script:LoadedBetaModule=$module
    }
    Case 'Portable is excluded by the real embedded utility before network and app probe' {
        $m=$script:LoadedBetaModule
        &$m {
            function script:Get-VutHardware {return [pscustomobject]@{BoardManufacturer='MSI';BoardModel='TEST';ComputerManufacturer='MSI';ComputerModel='Laptop';Portable=$true;ClientWindows=$true;Is64Bit=$true;WindowsCaption='Microsoft Windows 11 Pro'}}
            function script:Invoke-MbxHttp {throw 'Forbidden network on laptop'}
            function script:Get-VutInstalledApplication {throw 'Forbidden app probe on laptop'}
        }
        $r=&$m {Invoke-VendorUtility}
        Assert ($r.Status -eq 'manual_required' -and -not $r.Tool -and -not $r.InstallerShortcut -and $r.Reason -match '(?i)portable') 'Portable mal exclu.'
    }
    Case 'Changed extracted source is refused before import' {
        $path=Join-Path (Split-Path $script:LoadedBetaModule.Path) 'VendorDiscovery.Gigabyte.ps1'
        $original=[IO.File]::ReadAllBytes($path);[IO.File]::WriteAllText($path,'# changed inert fixture')
        $errorText='';try{$null=Initialize-LDLCVendorUtilityModule}catch{$errorText=$_.Exception.Message}
        Assert ($errorText -match 'modifie') 'Chargement malgre empreinte incorrecte.'
        [IO.File]::WriteAllBytes($path,$original)
    }
    function Initialize-LDLCVendorUtilityModule {$script:InitCalls++;return $script:LoadedBetaModule}
    &$script:LoadedBetaModule {function script:Invoke-VendorUtility {if($script:BetaFixture -eq 'throw'){throw 'Fixture download interrupted'};return $script:BetaFixture}}
    foreach($fixture in @(
        @{Name='Verified installer shortcut is a normal manual result';Status='manual_required';Tool='GIGABYTE Control Center';InstallerShortcut='fixture.lnk';ApplicationVerified=$false;Shortcut='';Reason='manual';Level='ok'},
        @{Name='Official web fallback remains a visible warning, never installer success';Status='manual_required';Tool='ASRock APP Shop';InstallerShortcut='';SupportShortcut='official.url';ApplicationVerified=$false;Shortcut='';Reason='HTTP 503, repli manuel officiel';Level='warning'},
        @{Name='Already installed application keeps its verified shortcut';Status='already_installed';Tool='MSI Center';InstallerShortcut='';ApplicationVerified=$true;Shortcut='fixture.lnk';Reason='existing';Level='ok'},
        @{Name='Laptop or unsupported PC is skipped without blocking warning';Status='manual_required';Tool='';InstallerShortcut='';ApplicationVerified=$false;Shortcut='';Reason='Portable exclu';Level='step'},
        @{Name='Real detection/download failure exposes the blocking cause';Status='manual_required';Tool='ASUS DriverHub';InstallerShortcut='';ApplicationVerified=$false;Shortcut='';Reason='HTTP 503 source officielle';Level='warning'},
        @{Name='Module error does not masquerade as installation';Status='failed';Tool='ASRock APP Shop';InstallerShortcut='';ApplicationVerified=$false;Shortcut='';Reason='Signature invalide';Level='warning'}
    )){
        Case $fixture.Name {
            &$script:LoadedBetaModule {param($f)$script:BetaFixture=[pscustomobject]$f} $fixture
            $script:Events=@();$r=Invoke-LDLCVendorUtility
            Assert ($r.Status -ceq $fixture.Status -and $script:Events.Count -eq 1 -and $script:Events[0].Level -ceq $fixture.Level) 'Mauvaise classification de resultat.'
            $saved=Get-Content (Join-Path $temp 'LDLC_VENDOR_UTILITY_RESULT.json') -Raw | ConvertFrom-Json
            Assert ($saved.Reason -ceq $fixture.Reason) 'Cause perdue dans le rapport.'
            if($fixture.Level -eq 'warning'){Assert ($script:Events[0].Message.Contains($fixture.Reason)) 'Cause absente du journal.'}
        }
    }
    Case 'Thrown failure is visible and does not abort the base preparation' {
        &$script:LoadedBetaModule {$script:BetaFixture='throw'}
        $script:Events=@();$r=Invoke-LDLCVendorUtility
        Assert ($r.Status -eq 'failed' -and -not $r.Installed -and $script:Events[0].Message -match 'interrupted') 'Exception masquee ou faux succes.'
    }
    Case 'Quit before this step prevents module/network work' {
        $script:Stopped=$true;$before=$script:InitCalls;$message=''
        try{$null=Invoke-LDLCVendorUtility}catch{$message=$_.Exception.Message}
        Assert ($message -match 'LDLC_STOP_REQUESTED' -and $script:InitCalls -eq $before) 'Arret ignore.'
        $script:Stopped=$false
    }
    Case 'The real workflow calls the beta step exactly once after apps and before defaults' {
        $workflow=[IO.File]::ReadAllText((Join-Path $root 'modules/90.Workflow.ps1'))
        $index=$workflow.IndexOf('[void](Invoke-LDLCVendorUtility -ProgressPercent 82)')
        Assert ($index -gt $workflow.IndexOf('Install-LDLCApplication -App $app') -and $index -lt $workflow.IndexOf('Invoke-LDLCChromeDefaultAppsSequence')) 'Mauvais emplacement du parcours beta.'
        Assert (([regex]::Matches($workflow,'Invoke-LDLCVendorUtility -ProgressPercent')).Count -eq 1) 'Etape doublee.'
    }
} finally {Remove-Module VendorUtility,MotherboardExperiment -ErrorAction SilentlyContinue;Remove-Item -LiteralPath $temp -Recurse -Force}
[void](New-Item -ItemType Directory -Path $OutputDirectory -Force)
$report=@{Kind='beta_vendor_integration';Cases=@($cases.ToArray());Assertions=$script:Checks;Failures=@($cases.ToArray()|Where-Object Result -eq failed).Count;Mode='real_embedded_import_with_simulated_hardware_and_adapter_results';VendorInstallerExecuted=$false}
$report|ConvertTo-Json -Depth 7|Set-Content (Join-Path $OutputDirectory 'beta-vendor.json') -Encoding UTF8
Import-Module (Join-Path $root 'tools/experimental/motherboard/MotherboardExperiment.psm1') -Force
Write-MbxEvidence -Kind 'beta_vendor_integration' -Data $report
if($report.Failures){throw "$($report.Failures) integration beta en echec."}
Write-Host "$($cases.Count) scenarios beta / $script:Checks assertions reussis."
