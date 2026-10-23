#requires -Version 5.1
param([string]$OutputPath='')
$ErrorActionPreference='Stop'
if($env:OS -ne 'Windows_NT'){throw 'Ce diagnostic en lecture seule doit etre lance sous Windows, dans la session du technicien.'}
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'modules/70.DefaultApps.ps1')
$pdf=Get-LDLCDefaultAppState Adobe
$chrome=Get-LDLCDefaultAppState Chrome
$reader=@(foreach($key in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*')){
    Get-ItemProperty $key -ErrorAction SilentlyContinue|Where-Object {$_.DisplayName -match '(?i)(Adobe.*(Acrobat|Reader)|Acrobat Reader)'}|Select-Object DisplayName,DisplayVersion,Publisher
})
$raw=(Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.pdf\UserChoice' -ErrorAction SilentlyContinue).ProgId
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$session=[Diagnostics.Process]::GetCurrentProcess().SessionId
$shellOwners=@(Get-CimInstance Win32_Process -Filter ("Name='explorer.exe' AND SessionId="+$session) -ErrorAction SilentlyContinue|ForEach-Object { (Invoke-CimMethod -InputObject $_ -MethodName GetOwnerSid -ErrorAction SilentlyContinue).Sid }|Where-Object {$_}|Sort-Object -Unique)
$report=[ordered]@{
    ReadOnly=$true;ConfigurationChanged=$false;CapturedUtc=[DateTime]::UtcNow.ToString('o')
    WindowsBuild=Get-LDLCWindowsBuildNumber
    Context=@{UserSid=$identity.User.Value;SessionId=$session;ExplorerOwnerSids=$shellOwners;DifferentInteractiveAccount=($shellOwners.Count -gt 0 -and $identity.User.Value -notin $shellOwners)}
    AdobeInstalledPrograms=$reader;AdobeDefaultConfirmed=$pdf.Confirmed
    PdfEffective=$pdf.Associations;PdfUserChoiceProgId=$raw;AdobeRegisteredPdfProgIds=@(Get-LDLCRegisteredPdfProgIds)
    ChromeDefaultConfirmed=$chrome.Confirmed;BrowserAssociations=$chrome.Associations
    Widgets=Get-LDLCWidgetsTaskbarState
    Note='Les API Windows effectives font foi dans le compte qui execute ce diagnostic. Une inscription Adobe ou UserChoice seule ne prouve pas que les PDF sont ouverts avec Adobe. Aucun parametre ni association n est modifie.'
}
$json=$report|ConvertTo-Json -Depth 10
if($OutputPath){[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath),$json,(New-Object Text.UTF8Encoding($false)))}
$json
