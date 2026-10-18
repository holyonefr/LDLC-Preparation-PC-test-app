$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'modules/60.Gpu.ps1')
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('AMD-Software-Detection-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixture)
$exe=Join-Path $fixture 'AMDSoftware.exe'
[IO.File]::WriteAllBytes($exe,[byte[]](1,2,3,4))
$assertions=0
function Assert-True([bool]$Value,[string]$Message) { if (-not $Value) { throw $Message }; $script:assertions++ }
function Write-Step { param($Text) }
function Get-StartMenuShortcutPath { param($Names) return $null }
function Get-LDLCInstalledPrograms { param([switch]$Refresh) $script:refreshed=[bool]$Refresh; return $script:programs }
function Get-LDLCExistingExePathByNames {
    param($ExePaths,$SearchFolders,$ExeNames)
    if (-not $script:exePresent) { return $null }
    if ($script:globalExe -or $exe -in $ExePaths) { return $exe }
    return $null
}
function New-TestProgram([string]$Name) {
    return [pscustomobject]@{DisplayName=$Name;DisplayVersion='23.4.1';Publisher='Advanced Micro Devices, Inc.';InstallLocation=$fixture;DisplayIcon=('"'+$exe+'",0')}
}
try {
    $script:exePresent=$true; $script:globalExe=$true
    foreach ($name in @('AMD Software: Adrenalin Edition','Radeon Software','AMD Software')) {
        $script:programs=@(New-TestProgram $name);$script:refreshed=$false
        $result=Get-LDLCAmdSoftwareInstallation -Refresh
        Assert-True ($result -and $result.ExePath -eq $exe -and $result.RegistryPresent -and $result.ExecutablePresent) "Adrenalin existant non reconnu : $name"
        Assert-True ($script:refreshed -and $result.DisplayVersion -eq '23.4.1') 'La detection doit rafraichir le registre et conserver la version constatee.'
    }
    foreach ($name in @('AMD Software: PRO Edition','Radeon Pro Enterprise')) {
        $script:programs=@(New-TestProgram $name)
        Assert-True ($null -eq (Get-LDLCAmdSoftwareInstallation -Refresh)) 'Un executable PRO homonyme ne prouve pas Adrenalin.'
    }
    $script:programs=@((New-TestProgram 'AMD Software: PRO Edition'),(New-TestProgram 'AMD Software: Adrenalin Edition'))
    Assert-True ($null -ne (Get-LDLCAmdSoftwareInstallation -Refresh)) 'Une entree Adrenalin complete doit rester reconnue meme avec une ancienne entree PRO.'
    $script:programs=@()
    $result=Get-LDLCAmdSoftwareInstallation -Refresh
    Assert-True ($result -and $result.DetectedBy -eq 'Executable' -and -not $result.RegistryPresent) 'Adrenalin sans entree registre doit rester detectable par son executable.'
    $script:exePresent=$false
    foreach ($name in @('AMD Software: Adrenalin Edition','AMD Chipset Software','AMD Software Installer','AMD Ryzen Master')) {
        $script:programs=@(New-TestProgram $name)
        Assert-True ($null -eq (Get-LDLCAmdSoftwareInstallation -Refresh)) "Ne pas confondre une entree seule avec Adrenalin : $name"
    }
    Write-Host "OK : $assertions controles de detection Adrenalin, aucune interrogation du poste hote."
} finally { Remove-Item -LiteralPath $fixture -Recurse -Force }
