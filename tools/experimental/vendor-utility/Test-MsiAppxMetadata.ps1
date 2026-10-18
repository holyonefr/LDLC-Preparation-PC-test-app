#requires -Version 5.1
[CmdletBinding()]
param([string]$OutputDirectory=(Join-Path $PSScriptRoot "reports/msi-appx-metadata-tests"))
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Inspect-MsiAppx.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Parse failed'}
$functions=$ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)
foreach($function in $functions){. ([scriptblock]::Create($function.Extent.Text))}
$script:cases=0;$script:asserts=0
function Assert($ok,$message){$script:asserts++;if(-not $ok){throw $message}}
function Case($name,$block){&$block;$script:cases++;Write-Host ('PASS '+$name)}
function Rejects($block){try{&$block;return $false}catch{return $true}}
$root=Join-Path ([IO.Path]::GetTempPath()) ('msi-appx-static-fixture-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $root)
function New-ZipFixture($name,$items){
 $p=Join-Path $root $name;$stream=[IO.File]::Create($p);$z=New-Object IO.Compression.ZipArchive($stream,[IO.Compression.ZipArchiveMode]::Create)
 try{foreach($item in $items){$e=$z.CreateEntry($item.Name);$s=$e.Open();try{$b=[Text.Encoding]::UTF8.GetBytes($item.Text);$s.Write($b,0,$b.Length)}finally{$s.Dispose()}}}finally{$z.Dispose();$stream.Dispose()};return $p
}
function Read-Fixture($path,$name){$a=[IO.Compression.ZipFile]::OpenRead($path);try{return ,(Read-MsiAppxManifest $a $name)}finally{$a.Dispose()}}
try{
 $xml='<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10" xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10" xmlns:desktop="http://schemas.microsoft.com/appx/manifest/desktop/windows10"><Identity Name="9426MICRO-STARINTERNATION.MSICenter" Publisher="CN=Fixture" Version="2.0.74.0" ProcessorArchitecture="x64"/><Dependencies><TargetDeviceFamily Name="Windows.Desktop" MinVersion="10.0.19041.0" MaxVersionTested="10.0.26100.0"/><PackageDependency Name="Microsoft.VCLibs.140.00" MinVersion="14.0.0.0" Publisher="CN=Microsoft"/></Dependencies><Applications><Application Id="App" Executable="MSICenter.exe" EntryPoint="Windows.FullTrustApplication"><Extensions><desktop:Extension Category="windows.startupTask" Executable="Startup.exe"><desktop:StartupTask TaskId="MSI-Startup" Enabled="true"/></desktop:Extension><desktop:Extension Category="windows.fullTrustProcess" Executable="Helper.exe"/></Extensions></Application></Applications><Capabilities><Capability Name="internetClient"/></Capabilities></Package>'
 $valid=New-ZipFixture valid.appx @(@{Name='AppxManifest.xml';Text=$xml})
 Case 'XML metadata identity, dependencies, startup task and full-trust extension' {
  $document=Read-Fixture $valid 'AppxManifest.xml';$m=Get-MsiAppxApplicationMetadata $document
  Assert ($m.Identity.Name -eq '9426MICRO-STARINTERNATION.MSICenter') 'Identity incorrect'
  Assert ($m.Identity.Version -eq '2.0.74.0') 'Version incorrect'
  Assert ($m.Applications.Count -eq 1 -and $m.Applications[0].Executable -eq 'MSICenter.exe') 'Application missing'
  Assert ($m.Dependencies.Count -eq 2) 'Dependencies missing'
  Assert ($m.Extensions.Count -eq 2 -and $m.Extensions[1].Attributes.Category -eq 'windows.fullTrustProcess') 'FullTrust missing'
  Assert ($m.Extensions[0].ApplicationId -eq 'App') 'Extension owner missing'
  Assert ($m.StartupTasks.Count -eq 1 -and $m.StartupTasks[0].Enabled -eq 'true' -and $m.StartupTasks[0].EnabledAttributePresent) 'Startup task flag missing'
  Assert ($m.Capabilities.Count -eq 1) 'Capabilities missing'
 }
 Case 'Valid ZIP header checked without executing archive' { Test-MsiAppxZipHeader $valid;Assert $true 'header' }
 Case 'Non-ZIP rejected' { $p=Join-Path $root bad.appx;[IO.File]::WriteAllText($p,'not an archive');Assert (Rejects {Test-MsiAppxZipHeader $p}) 'Bad header accepted' }
 Case 'DTD and external entity refused' { $p=New-ZipFixture dtd.appx @(@{Name='AppxManifest.xml';Text='<!DOCTYPE Package [<!ENTITY x SYSTEM "file:///etc/passwd">]><Package>&x;</Package>'});Assert (Rejects {Read-Fixture $p 'AppxManifest.xml'}) 'DTD accepted' }
 Case 'Manifest greater than 1 MiB refused' { $p=New-ZipFixture big.appx @(@{Name='AppxManifest.xml';Text=('a'*1048577)});Assert (Rejects {Read-Fixture $p 'AppxManifest.xml'}) 'Large XML accepted' }
 Case 'Case-insensitive duplicate manifest refused' { $p=New-ZipFixture dup.appx @(@{Name='AppxManifest.xml';Text=$xml},@{Name='appxmanifest.xml';Text=$xml});Assert (Rejects {Read-Fixture $p 'AppxManifest.xml'}) 'Ambiguous XML accepted' }
 Case 'Missing manifest refused' { Assert (Rejects {Read-Fixture $valid 'missing.xml'}) 'Missing XML accepted' }
 Case 'Package traversal and rooted names refused' { $a=[IO.Compression.ZipFile]::OpenRead($valid);try{foreach($n in @('../evil.appx','x/../../evil.appx','C:/evil.appx','/evil.appx','..\evil.appx')){Assert (Rejects {Get-MsiAppxZipEntry $a $n}) 'Unsafe path accepted'}}finally{$a.Dispose()} }
 Case 'Entry larger than 2 GiB refused before opening' { $a=[pscustomobject]@{Entries=@([pscustomobject]@{FullName='huge.appx';Length=[long]2147483649})};Assert (Rejects {Get-MsiAppxZipEntry $a 'huge.appx'}) 'Large entry accepted' }
 Case 'OPC encoded spaces match the manifest package name' { $a=[pscustomobject]@{Entries=@([pscustomobject]@{FullName='MSI%20Center_2.0.74.0_x64.appx';Length=1024})};$e=Get-MsiAppxZipEntry $a 'MSI Center_2.0.74.0_x64.appx';Assert ($e.FullName -eq 'MSI%20Center_2.0.74.0_x64.appx') 'OPC space not found' }
 Case 'Raw and OPC encoded duplicate package names are ambiguous' { $a=[pscustomobject]@{Entries=@([pscustomobject]@{FullName='MSI%20Center.appx';Length=1024},[pscustomobject]@{FullName='MSI Center.appx';Length=1024})};Assert (Rejects {Get-MsiAppxZipEntry $a 'MSI Center.appx'}) 'OPC duplicate accepted' }
 Case 'OPC encoded older package version is never selected' { $a=[pscustomobject]@{Entries=@([pscustomobject]@{FullName='MSI%20Center_2.0.72.0_x64.appx';Length=1024})};Assert (Rejects {Get-MsiAppxZipEntry $a 'MSI Center_2.0.74.0_x64.appx'}) 'Older appx selected' }
 Case 'No app identity rejected' { $doc=New-Object Xml.XmlDocument;$doc.LoadXml('<Package/>');Assert (Rejects {Get-MsiAppxApplicationMetadata $doc}) 'Missing identity accepted' }
 Case 'Argument quotes preserve spaces, quotes and final backslash' {
  Assert ((ConvertTo-MsiAppxArgument 'a b') -eq '"a b"') 'Space argument incorrect'
  Assert ((ConvertTo-MsiAppxArgument 'a"b') -eq '"a\"b"') 'Quote argument incorrect'
  Assert ((ConvertTo-MsiAppxArgument 'C:\test\') -eq '"C:\test\\"') 'Trailing slash incorrect'
 }
 Case 'Signature failure remains unestablished on unsupported platform' { $s=Get-MsiAppxSignature $valid;Assert ($s.State -eq 'not_established') 'Unsupported signature falsely validated' }
 Case 'No native vendor or install API commands in AST' {
  $commands=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.CommandAst]},$true) | ForEach-Object GetCommandName)
  foreach($bad in @('Add-AppxPackage','Add-AppxProvisionedPackage','Start-Process','dism.exe','msiexec.exe','SetAccessRight.exe','Invoke-Expression')){Assert ($bad -notin $commands) ('Unexpected execution command '+$bad)}
 }
 [void](New-Item -ItemType Directory -Path $OutputDirectory -Force)
 $report=[ordered]@{Kind='msi_appx_metadata_tests';Mode='inert_zip_and_xml_fixtures';Cases=$script:cases;Assertions=$script:asserts;Failures=0;VendorInstallerExecuted=$false}
 $report | ConvertTo-Json | Set-Content (Join-Path $OutputDirectory 'msi-appx-metadata-tests.json') -Encoding UTF8
 Import-Module (Join-Path $PSScriptRoot '../motherboard/MotherboardExperiment.psm1') -Force
 Write-MbxEvidence -Kind 'msi_appx_metadata_tests' -Data $report
 Write-Host ('RESULT '+($script:cases)+' cases '+($script:asserts)+' assertions')
}finally{Remove-Item -LiteralPath $root -Recurse -Force}
