$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'modules\70.DefaultApps.ps1')
$script:RealPickerRoot = ${function:Get-LDLCDefaultAppsPickerRoot}
$script:RealControls = ${function:Get-LDLCDefaultAppsControls}
$script:RealInvokeControl = ${function:Invoke-LDLCDefaultAppsControl}
function Assert-True([bool]$Value, [string]$Message) { if (-not $Value) { throw $Message } }
function Stop-IfRequested { if ($script:Cancelled) { throw 'LDLC_STOP_REQUESTED' } }
function Test-LDLCStopRequestError($ErrorRecord) { return ($ErrorRecord.Exception.Message -match 'LDLC_STOP_REQUESTED') }
function Write-Step($Text) {}
function Write-Section($Text) {}
function Write-Info($Text) { $script:Infos.Add($Text) }
function Write-Ok($Text) { $script:Successes.Add($Text) }
function Write-Warn($Text) { $script:Warnings.Add($Text) }
function Get-LDLCDefaultAppsTick { return $script:Tick }
function Start-Sleep([int]$Milliseconds, [int]$Seconds) { $script:Tick += $Milliseconds + $Seconds * 1000 }
function Set-LDLCTaskbarOptionsWithRegistry { return $true }
function Get-LDLCEffectiveAssociation([string]$Association) {
    $name = if ($Association -eq '.pdf') { 'Adobe' } else { 'Chrome' }
    $good = $script:Ready[$name]
    [pscustomobject]@{
        Association = $Association
        ProgId = if ($good) { if ($name -eq 'Chrome') { 'ChromeHTML.Test' } else { 'AcroExch.Document.DC' } } else { 'MSEdgeHTM' }
        Executable = (Join-Path ([IO.Path]::GetTempPath()) $(if ($good) { if ($name -eq 'Chrome') { 'chrome.exe' } else { 'Acrobat.exe' } } else { 'msedge.exe' }))
        Error = ''
    }
}
$script:RealDefaultAppAttempt = ${function:Invoke-LDLCDefaultAppAttempt}
function Invoke-LDLCDefaultAppAttempt($Application, $State, [int]$Attempt, $Route) {
    $script:Attempts[$Application]++
    $script:ApplicationOrder.Add($Application)
    Assert-True ($script:LDLCDefaultAppsCompactDepth -gt 0) 'Le mode compact doit couvrir chaque tentative.'
    if ($script:Cancelled) { throw 'LDLC_STOP_REQUESTED' }
    if ($Attempt -ge $script:SucceedOn) { $script:Ready[$Application] = $true }
    else { throw 'Focus perdu ou Parametres lents (simulation)' }
}
function Ensure-LDLCDefaultAppsUiAutomation {}
function Get-LDLCDefaultAppsWindows {}
function Get-LDLCDefaultAppUris {
    param($Application)
    return @('ms-settings:defaultapps?registeredAppUser=Test', 'ms-settings:defaultapps?registeredAppUser=Test', 'ms-settings:defaultapps?registeredAppMachine=Test')
}
$script:Infos = New-Object 'Collections.Generic.List[string]'
$script:Warnings = New-Object 'Collections.Generic.List[string]'
$script:Successes = New-Object 'Collections.Generic.List[string]'
$script:Tick = 0
$script:Ready = @{ Chrome = $false; Adobe = $false }
$script:Attempts = @{ Chrome = 0; Adobe = 0 }
$script:SucceedOn = 2
$script:ProgressFile = $null
$script:Cancelled = $false
$script:ApplicationOrder = New-Object 'Collections.Generic.List[string]'
Invoke-LDLCChromeDefaultAppsSequence
Assert-True (($script:ApplicationOrder -join ',') -eq 'Adobe,Adobe,Chrome,Chrome') 'Adobe puis Chrome, y compris en cas de repli.'
Assert-True ($script:LDLCDefaultAppsCompactProgress.Progress -eq 100 -and $script:LDLCDefaultAppsCompactProgress.Success) '100 exige les deux resultats confirmes.'
Assert-True ($script:Attempts.Chrome -eq 2 -and $script:Attempts.Adobe -eq 2) 'Chrome et PDF doivent reessayer apres un premier echec.'
Assert-True ($script:Warnings.Count -eq 0) 'Une tentative recuperee ne doit pas laisser un faux avertissement.'
Assert-True ($script:Infos.Contains('Reglages des applications par defaut termines ; aucune confirmation Chrome demandee.')) 'Le bilan distingue la commande Chrome transmise et le PDF configure.'
Assert-True ($script:LDLCDefaultAppsCompactDepth -eq 0) 'Restaurer la fenetre apres succes.'
Assert-True ((Get-LDLCDefaultAppState Chrome).Associations.Count -eq 4) 'Verifier HTTP HTTPS .htm et .html.'
$script:Ready = @{ Chrome = $false; Adobe = $false }
$script:Attempts = @{ Chrome = 0; Adobe = 0 }
$script:SucceedOn = 99
Assert-True (-not (Invoke-LDLCDefaultAppConfiguration Adobe)) 'Une association non appliquee ne doit jamais reussir.'
Assert-True ($script:Attempts.Adobe -eq 2 -and $script:Warnings.Count -eq 1) 'Deux voies uniques puis un seul avertissement precis, pas de repetition modulo.'
Assert-True ($script:Warnings[0] -match 'Adobe.*\.pdf') 'Le bilan doit identifier PDF et Adobe.'
Assert-True ($script:LDLCDefaultAppsCompactDepth -eq 0) 'Restaurer la fenetre apres echec.'
Invoke-LDLCChromeDefaultAppsSequence
Assert-True ($script:LDLCDefaultAppsCompactProgress.Progress -eq 0 -and -not $script:LDLCDefaultAppsCompactProgress.Success) 'Deux echecs : zero, jamais termine.'
$script:Ready.Chrome = $true
Invoke-LDLCChromeDefaultAppsSequence
Assert-True ($script:LDLCDefaultAppsCompactProgress.Progress -eq 50 -and $script:LDLCDefaultAppsCompactProgress.ErrorApplication -match 'Adobe') 'Chrome deja configure mais Adobe en echec : 50, echec Adobe explicite.'
$script:Cancelled = $true
$stopped = $false
try { Invoke-LDLCDefaultAppConfiguration Chrome | Out-Null } catch { $stopped = Test-LDLCStopRequestError $_ }
Assert-True ($stopped -and $script:LDLCDefaultAppsCompactDepth -eq 0) 'L annulation doit remonter et restaurer la fenetre.'
$script:Cancelled = $false

# Selection UIA ignores physical geometry: 100/125/150%, small and large displays.
foreach ($dpi in @(1, 1.25, 1.5)) {
    foreach ($width in @(1366, 1920, 2560)) {
        $controls = @(
            [pscustomobject]@{ Name = '.pdf Microsoft Edge'; ControlType = 'ControlType.Button'; Enabled = $true; Offscreen = $false; X = $width * $dpi; Y = 990 * $dpi },
            [pscustomobject]@{ Name = '.html Google Chrome'; ControlType = 'ControlType.Button'; Enabled = $true; Offscreen = $false; X = 1; Y = 2 }
        )
        $control = Select-LDLCDefaultAppsControl -Controls $controls -Kind Association -Association '.pdf' -Application Adobe
        Assert-True ($control.Name -eq '.pdf Microsoft Edge') 'Choisir le controle PDF par semantique, sans coordonnees.'
    }
}
foreach ($name in @('Acrobat Reader', 'Adobe Acrobat Reader', 'Adobe Acrobat', 'Adobe Reader', 'Acrobat Reader DC', 'Adobe Acrobat DC (64-bit)', '  ACROBAT   READER  ')) {
    $controls = @([pscustomobject]@{ Name = $name; ControlType = 'ControlType.ListItem'; Enabled = $true; Offscreen = $false })
    Assert-True ($null -ne (Select-LDLCDefaultAppsControl $controls Choice -Application Adobe)) "Choix Adobe lisible : $name."
    Assert-True ($null -eq (Select-LDLCDefaultAppsControl $controls Choice -Application Chrome)) 'Ne jamais choisir Adobe pour Chrome.'
    $controls[0].ControlType = 'ControlType.Text'
    Assert-True ($null -ne (Select-LDLCDefaultAppsControl $controls Page -Application Adobe)) 'La fiche utilise les memes variantes.'
    Assert-True (Test-LDLCDefaultAppsApplicationName -Name $name -Application Adobe -RegisteredName) 'Les noms enregistres acceptent les variantes.'
}
foreach ($name in @('Microsoft Edge', 'Reader', 'Acrobatics', 'Rechercher Adobe Acrobat dans le Store', 'Adobe Acrobat Help', 'Acrobat Reader - Site web')) {
    Assert-True (-not (Test-LDLCDefaultAppsApplicationName -Name $name -Application Adobe)) "Ne pas selectionner un controle non application : $name."
}
$controls = @(
    [pscustomobject]@{ Name = 'Adobe Acrobat'; ControlType = 'ControlType.ListItem'; Enabled = $true; Offscreen = $true },
    [pscustomobject]@{ Name = 'Acrobat Reader'; ControlType = 'ControlType.ListItem'; Enabled = $false; Offscreen = $false },
    [pscustomobject]@{ Name = 'Adobe Acrobat Reader'; ControlType = 'ControlType.ListItem'; Enabled = $true; Offscreen = $false }
)
Assert-True ((Select-LDLCDefaultAppsControl $controls Choice -Application Adobe).Name -eq 'Adobe Acrobat Reader') 'Priorite au choix visible et actif.'
foreach ($progId in @('AcroExch.Document', 'AcroExch.Document.DC', 'Acrobat.Document.DC')) {
    foreach ($exe in @('Acrobat.exe', 'AcroRd32.exe')) {
        $association = [pscustomobject]@{ ProgId = $progId; Executable = (Join-Path ([IO.Path]::GetTempPath()) $exe); Error = '' }
        Assert-True (Test-LDLCEffectiveAssociationTarget $association Adobe) 'Reader et Acrobat doivent etre reconnus par leur association effective.'
        $association.Executable = (Join-Path ([IO.Path]::GetTempPath()) 'msedge.exe')
        Assert-True (-not (Test-LDLCEffectiveAssociationTarget $association Adobe)) 'Un libelle/ProgID Adobe ne suffit pas si Edge ouvre les PDF.'
    }
}
$script:Tick = 0
$slowReady = Wait-LDLCDefaultAppsCondition -TimeoutMilliseconds 20000 -Probe { $script:Tick -ge 18000 }
Assert-True ([bool]$slowReady) 'Accepter un chargement Windows lent dans la limite prevue.'

# Exercise the real orchestration, selector action and confirmation loops with a UIA
# fixture. Only Windows/UIA side effects and the clock are replaced; no PC defaults change.
Set-Item Function:Invoke-LDLCDefaultAppAttempt $script:RealDefaultAppAttempt
function Get-LDLCDefaultAppsWindows { [pscustomobject]@{ Handle = 123; IsSettings = $true } }
function Set-LDLCDefaultAppsFocus { return $true }
function Get-LDLCDefaultAppsRoot { return 'Fixture' }
function Get-LDLCDefaultAppsPickerRoot { return 'PDF picker fixture' }
function Move-LDLCDefaultAppsScroll { return $false }
function Open-LDLCDefaultAppPage {
    param($Uri, $Application)
    $script:OpenedUris.Add($Uri)
    if ($script:PageFails -and $script:OpenedUris.Count -eq 1) { throw 'URI non prise en charge (simulation)' }
    $script:PickerPhase = 'Association'
}
$script:Element = [pscustomobject]@{}
$script:Element | Add-Member ScriptMethod GetRuntimeId { return @(1, 42) }
function Get-LDLCDefaultAppsControls {
    if ($script:PickerPhase -eq 'Association') {
        [pscustomobject]@{ Name = '.pdf Microsoft Edge'; ControlType = 'ControlType.Button'; Enabled = $true; Offscreen = $false; Element = $script:Element }
    }
    if ($script:PickerPhase -eq 'Choice') {
        [pscustomobject]@{ Name = 'Microsoft Edge'; ControlType = 'ControlType.ListItem'; Enabled = $true; Offscreen = $false; Element = $script:Element }
        if ($script:AppVisible) {
            [pscustomobject]@{ Name = $script:AppName; ControlType = 'ControlType.ListItem'; Enabled = $true; Offscreen = $false; Element = $script:Element }
        }
    }
    if ($script:PickerPhase -eq 'Confirm') {
        [pscustomobject]@{ Name = 'Definir par defaut'; ControlType = 'ControlType.Button'; Enabled = $true; Offscreen = $false; Element = $script:Element }
    }
}
function Invoke-LDLCDefaultAppsControl {
    param($Control, $Kind)
    $script:UiActions.Add("${Kind}:$($Control.Name)")
    $script:ActionSignals.Add([pscustomobject]@{ Kind=$Kind; Progress=$script:LDLCDefaultAppsCompactProgress.Progress; Message=$script:LDLCDefaultAppsCompactProgress.Message })
    if ($Kind -eq 'Association') { $script:PickerPhase = 'Choice' }
    if ($Kind -eq 'Choice') {
        Assert-True ($Control.Name -eq $script:AppName) 'Choisir Acrobat Reader, jamais Edge.'
        $script:PickerPhase = 'Confirm'
    }
    if ($Kind -eq 'Confirm' -and -not $script:ConfirmationNoEffect) { $script:Ready.Adobe = $true; $script:PickerPhase = 'Closed' }
    return $true
}
function Reset-PdfFixture {
    $script:Ready.Adobe = $false
    $script:Warnings.Clear(); $script:Successes.Clear()
    $script:OpenedUris = New-Object 'Collections.Generic.List[string]'
    $script:UiActions = New-Object 'Collections.Generic.List[string]'
    $script:ActionSignals = New-Object 'Collections.Generic.List[object]'
    $script:PickerPhase = 'Choice'; $script:AppVisible = $true
    $script:ConfirmationNoEffect = $false; $script:PageFails = $false
    $script:AppName = 'Acrobat Reader'
}
foreach ($name in @('Acrobat Reader', 'Adobe Acrobat Reader', 'Adobe Acrobat')) {
    Reset-PdfFixture
    $script:AppName = $name
    Assert-True (Invoke-LDLCDefaultAppConfiguration Adobe) "Le vrai flux doit choisir et confirmer $name."
    Assert-True ($script:OpenedUris.Count -eq 0 -and $script:UiActions.Count -eq 2) 'Selecteur deja visible : choisir, valider une fois, sans rouvrir Parametres.'
    Assert-True ($script:ActionSignals[0].Message -match 'Selection.*Adobe.*\.pdf' -and $script:ActionSignals[1].Message -match 'Validation.*Adobe.*\.pdf') 'Le signal doit preceder la selection puis le bouton Definir par defaut.'
    Assert-True (@($script:ActionSignals | Where-Object Progress -ne 0).Count -eq 0) 'Les clics/fallbacks Adobe ne doivent jamais faire avancer le palier.'
    Assert-True ($script:Warnings.Count -eq 0 -and $script:LDLCDefaultAppsCompactDepth -eq 0) 'Succes confirme et UI restauree.'
}
Reset-PdfFixture
$script:Ready.Adobe = $true
Assert-True (Invoke-LDLCDefaultAppConfiguration Adobe) 'Deja defini par defaut : succes apres deux lectures effectives.'
Assert-True ($script:UiActions.Count -eq 0 -and $script:OpenedUris.Count -eq 0) 'Ne pas toucher Windows si Acrobat est deja le defaut.'

Reset-PdfFixture
$script:PickerPhase = 'Closed'; $script:PageFails = $true
Assert-True (Invoke-LDLCDefaultAppConfiguration Adobe) 'Une autre URI enregistree peut recuperer une fiche inaccessible.'
Assert-True ($script:OpenedUris.Count -eq 2 -and $script:OpenedUris[0] -ne $script:OpenedUris[1]) 'Ne jamais reutiliser la meme voie.'
Assert-True ($script:Warnings.Count -eq 0) 'Pas de faux avertissement apres recuperation.'

Reset-PdfFixture
$script:ConfirmationNoEffect = $true
Assert-True (-not (Invoke-LDLCDefaultAppConfiguration Adobe)) 'Un clic sans association effective ne vaut jamais succes.'
Assert-True ($script:UiActions.Count -eq 2 -and $script:OpenedUris.Count -eq 0) 'Pas de clics repetes sur le meme bouton ni de repli aveugle apres confirmation sans effet.'
Assert-True ($script:Warnings.Count -eq 1 -and $script:Warnings[0] -match 'etape=Confirm.*Arret sans repetition' -and $script:Warnings[0] -match 'msedge.exe') 'Expliquer etape, arret et association Windows observee.'

Reset-PdfFixture
$script:PickerPhase = 'Closed'; $script:AppVisible = $false
Assert-True (-not (Invoke-LDLCDefaultAppConfiguration Adobe)) 'Acrobat absent du selecteur : echec precis.'
Assert-True ($script:OpenedUris.Count -eq 1 -and $script:Warnings[0] -match 'etape=Choice.*Arret sans repetition') 'Une selection impossible ne doit pas etre repetee sur trois fiches.'

function Get-LDLCDefaultAppUris { return @() }
Reset-PdfFixture
Assert-True (Invoke-LDLCDefaultAppConfiguration Adobe) 'Acrobat visible reste selectionnable sans RegisteredApplications.'
Reset-PdfFixture
$script:PickerPhase = 'Closed'
Assert-True (-not (Invoke-LDLCDefaultAppConfiguration Adobe)) 'Aucune voie disponible : avertissement clair, pas de faux succes.'
Assert-True ($script:OpenedUris.Count -eq 0 -and $script:Warnings[0] -match '0 tentative.*RegisteredApplications') 'Pas de tentatives fictives quand aucune fiche existe.'
Assert-True ($script:LDLCDefaultAppsCompactDepth -eq 0) 'Restaurer le compact aussi apres les echecs de selection.'

# Real picker scoping and text-child promotion, not a bypassed picker mock.
if ($env:OS -eq 'Windows_NT') {
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes
Set-Item Function:Get-LDLCDefaultAppsPickerRoot $script:RealPickerRoot
Set-Item Function:Get-LDLCDefaultAppsControls $script:RealControls
Set-Item Function:Invoke-LDLCDefaultAppsControl $script:RealInvokeControl
function Get-LDLCDefaultAppsParentElement($Element) { return $Element.Parent }
function New-UiaFixtureNode($Name,$Type) {
    $node = [pscustomobject]@{ Current = [pscustomobject]@{ Name=$Name; ControlType=$Type; ClassName='ModernXaml'; AutomationId=''; IsEnabled=$true; IsOffscreen=$false }; Parent=$null; Descendants=@() }
    $node | Add-Member ScriptMethod FindAll { return $this.Descendants }
    $node | Add-Member NoteProperty Runtime ([guid]::NewGuid().ToString())
    $node | Add-Member ScriptMethod GetRuntimeId { return @($this.Runtime) }
    return $node
}
$page = New-UiaFixtureNode 'Settings' ([System.Windows.Automation.ControlType]::Window)
$wrongRow = New-UiaFixtureNode 'Adobe Acrobat' ([System.Windows.Automation.ControlType]::Button)
$associationRow = New-UiaFixtureNode '.pdf Microsoft Edge' ([System.Windows.Automation.ControlType]::Button)
$dialog = New-UiaFixtureNode '' ([System.Windows.Automation.ControlType]::Pane)
$heading = New-UiaFixtureNode 'Selectionnez une application par defaut pour .pdf Fichiers' ([System.Windows.Automation.ControlType]::Text)
$row = New-UiaFixtureNode '' ([System.Windows.Automation.ControlType]::ListItem)
$label = New-UiaFixtureNode 'Acrobat Reader' ([System.Windows.Automation.ControlType]::Text)
$confirm = New-UiaFixtureNode 'Definir par defaut' ([System.Windows.Automation.ControlType]::Button)
$label.Parent=$row; $row.Parent=$dialog; $heading.Parent=$dialog; $confirm.Parent=$dialog; $dialog.Parent=$page
$row.Descendants=@($label); $dialog.Descendants=@($heading,$row,$label,$confirm)
$page.Descendants=@($wrongRow,$associationRow,$dialog)+$dialog.Descendants
$picker = Get-LDLCDefaultAppsPickerRoot -Window ([pscustomobject]@{IsSettings=$true}) -Root $page -Association '.pdf'
Assert-True (Test-LDLCDefaultAppsSameElement $picker $dialog) 'Scoper le vrai dialogue Pane, pas la page avec ses autres lignes Adobe.'
$choice = Select-LDLCDefaultAppsControl @(Get-LDLCDefaultAppsControls $picker) Choice -Application Adobe
Assert-True (Test-LDLCDefaultAppsSameElement $choice.Element $row) 'Cliquer la ligne parente du texte Acrobat Reader.'
Assert-True ($null -ne (Select-LDLCDefaultAppsControl @(Get-LDLCDefaultAppsControls $picker) Confirm -Application Adobe)) 'Retrouver Definir par defaut dans ce meme dialogue.'
Assert-True ($null -eq (Get-LDLCDefaultAppsPickerRoot -Window ([pscustomobject]@{IsSettings=$true}) -Root $page -Association '.html')) 'Ne jamais utiliser le selecteur PDF pour HTML.'
$page.Descendants=@($wrongRow,$associationRow)
Assert-True ($null -eq (Get-LDLCDefaultAppsPickerRoot -Window ([pscustomobject]@{IsSettings=$true}) -Root $page -Association '.pdf')) 'Une fiche Adobe contenant PDF ne suffit pas a prouver la presence du selecteur.'
Assert-True (Test-LDLCDefaultAppsNativePickerHit OpenWith 101 101 101) 'Accepter le hit natif exact du selecteur au premier plan si FromPoint renvoie la fiche derriere.'
Assert-True (-not (Test-LDLCDefaultAppsNativePickerHit OpenWith 101 102 101)) 'Refuser un autre processus que celui du controle UIA.'
Assert-True (-not (Test-LDLCDefaultAppsNativePickerHit OpenWith 101 101 102)) 'Refuser un selecteur qui ne possede plus le premier plan.'
Assert-True (-not (Test-LDLCDefaultAppsNativePickerHit SystemSettings 101 101 101)) 'Ne pas generaliser le repli OpenWith aux autres fenetres.'
Assert-True (-not (Test-LDLCDefaultAppsNativePickerHit OpenWith 0 0 0)) 'Ne jamais accepter un handle sans processus.'
$source = Get-Content -LiteralPath (Join-Path $root 'modules/70.DefaultApps.ps1') -Raw
Assert-True ($source -match 'GetForegroundWindow\(\).*' -and $source -match '\$handles\.Insert\(0, \$foreground\)') 'Garder le handle de premier plan absent de EnumWindows.'
Assert-True ($source -match 'EnumChildWindows\(\$Window.Handle' -and $source -match '\$count -gt \$bestCount') 'Explorer les vrais hotes enfants, pas seulement le dummy HWND ou la barre de titre.'
$script:Ready.Chrome = $true
Assert-True ((Get-LDLCDefaultAppState Chrome).Missing.Count -eq 0) 'Un succes doit exposer une liste Missing vide, pas un tableau contenant null.'

$chromePage = New-UiaFixtureNode 'Settings' ([System.Windows.Automation.ControlType]::Window)
$chromeTitle = New-UiaFixtureNode 'Google Chrome' ([System.Windows.Automation.ControlType]::Text)
$browserCard = New-UiaFixtureNode '' ([System.Windows.Automation.ControlType]::Group)
$browserHeading = New-UiaFixtureNode 'Definir Google Chrome comme navigateur par defaut' ([System.Windows.Automation.ControlType]::Text)
$browserButton = New-UiaFixtureNode 'Definir par defaut' ([System.Windows.Automation.ControlType]::Button)
$otherPdfButton = New-UiaFixtureNode 'Definir par defaut' ([System.Windows.Automation.ControlType]::Button)
$browserHeading.Parent=$browserCard; $browserButton.Parent=$browserCard; $browserCard.Parent=$chromePage
$browserCard.Descendants=@($browserHeading,$browserButton)
$chromePage.Descendants=@($chromeTitle,$otherPdfButton,$browserCard,$browserHeading,$browserButton)
$browserControl = Get-LDLCChromeBrowserDefaultControl $chromePage
Assert-True (Test-LDLCDefaultAppsSameElement $browserControl.Element $browserButton) 'Choisir le bouton de la ligne navigateur Chrome, jamais un autre Definir par defaut.'
$browserHeading.Current.Name = 'Make Google Chrome your default browser'
Assert-True ($null -ne (Get-LDLCChromeBrowserDefaultControl $chromePage)) 'Accepter la meme ligne Windows en anglais.'
$browserHeading.Current.Name = 'Definir Google Chrome par defaut pour les fichiers .pdf'
Assert-True ($null -eq (Get-LDLCChromeBrowserDefaultControl $chromePage)) 'Refuser la carte PDF et toute confirmation non liee au navigateur.'
$browserButton.Current.Name = 'Definir Google Chrome comme navigateur par defaut, Definir par defaut'
$otherPdfButton.Current.Name = 'Definir Google Chrome par defaut pour les fichiers .pdf, Definir par defaut'
$chromePage.Descendants=@($chromeTitle,$otherPdfButton,$browserButton)
Assert-True (Test-LDLCDefaultAppsSameElement (Get-LDLCChromeBrowserDefaultControl $chromePage).Element $browserButton) 'Libelle UIA reel combine : ligne navigateur et Definir par defaut dans le nom du bouton.'
$browserButton.Current.Name = 'Make Google Chrome your default browser, Set default'
Assert-True ($null -ne (Get-LDLCChromeBrowserDefaultControl $chromePage)) 'Libelle combine anglais, meme bouton navigateur.'
$browserButton.Current.Name = 'Definir Google Chrome par defaut pour les fichiers .pdf, Definir par defaut'
Assert-True ($null -eq (Get-LDLCChromeBrowserDefaultControl $chromePage)) 'Ne jamais remplacer le navigateur par le bouton PDF Chrome.'

}
else { Write-Host 'SKIP Windows UIAutomation tree fixtures (run under Windows)' }

$script:Ready.Chrome = $false
$script:ChromeActions = New-Object 'Collections.Generic.List[string]'
function Open-LDLCDefaultAppPage { param($Uri,$Application) $script:ChromeActions.Add('Page') }
function Invoke-LDLCDefaultAppsUiAction {
    param($Kind,$Association,$Application)
    $script:ChromeActions.Add("${Kind}:${Association}")
    if ($Kind -eq 'BrowserDefault') { $script:Ready.Chrome = $true }
    return $true
}
function Complete-LDLCDefaultAppsChoice {
    param($Association,$Application)
    $script:ChromeActions.Add("Confirm:${Association}")
}
Set-LDLCDefaultAppsCompactProgress -Percent 50 -Message 'Configuration de Chrome...'
& $script:RealDefaultAppAttempt -Application Chrome -State (Get-LDLCDefaultAppState Chrome) -Attempt 1 -Route ([pscustomobject]@{Kind='RegisteredPage';Uri='ms-settings:defaultapps?registeredAppMachine=ChromeFixture'})
Assert-True (($script:ChromeActions -join ',') -eq 'Page,BrowserDefault:') 'Chrome doit essayer directement le bouton navigateur, sans ouvrir d abord le selecteur HTML.'
Assert-True ((Get-LDLCDefaultAppState Chrome).Confirmed) 'Le bouton global doit etre suivi de la lecture des quatre associations effectives.'
Write-Host 'OK default apps: Acrobat/Reader variants, already-default, real selection/confirmation loops with simulated UIA, effective result only, unique fallback routes, no repeated unchanged failure/confirmation, compact finally, cancellation, DPI and slow Settings.'
