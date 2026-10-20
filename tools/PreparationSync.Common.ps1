$ErrorActionPreference = 'Stop'

function Get-PreparationSyncPath {
    param([string]$Root, [string]$RelativePath)
    if (-not $RelativePath -or [IO.Path]::IsPathRooted($RelativePath) -or $RelativePath -match '[\\:*?]' -or
        @($RelativePath.Split('/') | Where-Object { $_ -in @('', '.', '..') }).Count) {
        throw "Chemin de synchronisation refuse : $RelativePath"
    }
    $base = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $path = [IO.Path]::GetFullPath((Join-Path $base $RelativePath))
    if (-not $path.StartsWith($base + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Chemin hors depot.' }
    $cursor = $path
    while ($cursor -and $cursor.Length -ge $base.Length) {
        if (Test-Path -LiteralPath $cursor) {
            if ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Lien/jonction refuse : $cursor" }
        }
        if ($cursor -eq $base) { break }
        $cursor = Split-Path -Parent $cursor
    }
    return $path
}

function Assert-PreparationSharedPath {
    param([string]$RelativePath, $Policies)
    $alwaysProtected = @('modules/99.UI.ps1','modules/45.Wallpaper.ps1','telemetry.config.json',
        'sync/edition.json','sync/state.json','README.md','PASSATION_PROJET.md','AGENTS.md',
        'tools/google-apps-script/*','tools/Deploy-LDLCDashboard.ps1','tools/Reset-LDLCTelemetrySheet.ps1',
        'tools/Configure-LDLCTelemetry.ps1','tools/update-google-dashboard.cjs','tools/Test-LDLCUIBranding.ps1')
    if ($RelativePath -match '(?i)(^|/)(assets|branding|themes|wallpapers|dist|\.git|\.github)(/|$)|(^|/)[^/]*(logo|wallpaper|background)[^/]*$|\.(ico|png|jpe?g|gif|webp|svg|bmp|html|css|woff2?|ttf|otf)$') {
        throw "Ressource/identite protegee : $RelativePath"
    }
    foreach ($pattern in $alwaysProtected + @($Policies | ForEach-Object { $_.ProtectedPaths })) {
        if ($RelativePath -like $pattern) { throw "Fichier propre a l'edition protege : $RelativePath" }
    }
}

function Get-PreparationSharedHash {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    # Text hashes are independent of Git's CRLF/LF and UTF-8 BOM conversions.
    $text = [IO.File]::ReadAllText($Path).Replace("`r`n", "`n")
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($algorithm.ComputeHash([Text.Encoding]::UTF8.GetBytes($text))).Replace('-', '') }
    finally { $algorithm.Dispose() }
}

function Get-PreparationSyncPlan {
    param([string]$SourceRepository, [string]$TargetRepository)
    $sourceRoot = [IO.Path]::GetFullPath($SourceRepository).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $targetRoot = [IO.Path]::GetFullPath($TargetRepository).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    if ($sourceRoot -eq $targetRoot -or $sourceRoot.StartsWith($targetRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or
        $targetRoot.StartsWith($sourceRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Deux depots distincts non imbriques sont requis.' }
    $policy = [IO.File]::ReadAllText((Get-PreparationSyncPath $sourceRoot 'sync/shared-files.json')) | ConvertFrom-Json
    $targetPolicy = [IO.File]::ReadAllText((Get-PreparationSyncPath $targetRoot 'sync/shared-files.json')) | ConvertFrom-Json
    if ($policy.SchemaVersion -ne 1 -or $targetPolicy.SchemaVersion -ne 1) { throw 'Schema de synchronisation inconnu.' }
    $sourceState = [IO.File]::ReadAllText((Get-PreparationSyncPath $sourceRoot 'sync/state.json')) | ConvertFrom-Json
    $targetState = [IO.File]::ReadAllText((Get-PreparationSyncPath $targetRoot 'sync/state.json')) | ConvertFrom-Json
    if ($sourceState.SchemaVersion -ne 1 -or $targetState.SchemaVersion -ne 1) { throw 'Etat de synchronisation inconnu.' }
    $paths = @($policy.SharedFiles)
    if (-not $paths.Count -or @($paths | Group-Object | Where-Object { $_.Count -gt 1 }).Count) { throw 'Liste partagee vide ou dupliquee.' }
    $entries = foreach ($relative in $paths) {
        Assert-PreparationSharedPath $relative @($policy, $targetPolicy)
        $source = Get-PreparationSyncPath $sourceRoot $relative
        $target = Get-PreparationSyncPath $targetRoot $relative
        $sourceHash = Get-PreparationSharedHash $source
        $targetHash = Get-PreparationSharedHash $target
        $a = $sourceState.Files.PSObject.Properties[$relative]
        $b = $targetState.Files.PSObject.Properties[$relative]
        $baseline = if ($a -and $b -and $a.Value -eq $b.Value) { $a.Value } else { $null }
        $action = if ($sourceHash -eq $targetHash -and ($sourceHash -or ($a -and $b -and $a.Value -eq $b.Value))) { 'Identical' }
            elseif ($a -and $b -and $a.Value -ne $b.Value) { 'Conflict' }
            elseif (-not $sourceHash -and -not $baseline) { 'Conflict' }
            elseif ($targetHash -and $targetHash -ne $baseline) { 'Conflict' }
            elseif (-not $targetHash -and $baseline) { 'Conflict' }
            elseif (-not $sourceHash) { 'Delete' }
            else { 'Copy' }
        [pscustomobject]@{ Path = $relative; Action = $action; Source = $source; Target = $target; SourceHash = $sourceHash; TargetHash = $targetHash }
    }
    # A removed allowlist entry must not leave obsolete executable code unnoticed.
    foreach ($relative in @($sourceState.Files.PSObject.Properties.Name)) {
        if ($relative -notin $paths) { throw "Retrait du manifeste a examiner explicitement : $relative. Garder l'entree et supprimer le fichier pour propager une suppression." }
    }
    return [pscustomobject]@{ SourceRoot = $sourceRoot; TargetRoot = $targetRoot; Entries = @($entries) }
}

function Invoke-PreparationSyncPlan {
    param($Plan)
    $conflicts = @($Plan.Entries | Where-Object Action -eq Conflict)
    if ($conflicts.Count) { throw "Conflits : $($conflicts.Path -join ', '). Aucun fichier synchronise." }
    # Revalidate the complete plan before its first write.
    foreach ($entry in $Plan.Entries) {
        if ((Get-PreparationSharedHash (Get-PreparationSyncPath $Plan.SourceRoot $entry.Path)) -ne $entry.SourceHash -or
            (Get-PreparationSharedHash (Get-PreparationSyncPath $Plan.TargetRoot $entry.Path)) -ne $entry.TargetHash) { throw "Fichier modifie depuis l'audit : $($entry.Path)" }
    }
    foreach ($entry in $Plan.Entries) {
        if ($entry.Action -eq 'Copy') {
            New-Item -ItemType Directory -Path (Split-Path -Parent $entry.Target) -Force | Out-Null
            Copy-Item -LiteralPath $entry.Source -Destination $entry.Target
        }
        elseif ($entry.Action -eq 'Delete') {
            & git -C $Plan.TargetRoot rm -- $entry.Path
            if ($LASTEXITCODE -ne 0) { throw "Suppression Git refusee : $($entry.Path)" }
        }
    }
    $hashes = [ordered]@{}
    foreach ($entry in $Plan.Entries) {
        $hash = Get-PreparationSharedHash $entry.Source
        if ($hash -ne (Get-PreparationSharedHash $entry.Target)) { throw "Synchronisation non confirmee : $($entry.Path)" }
        $hashes[$entry.Path] = $hash
    }
    $json = [ordered]@{ SchemaVersion = 1; Files = $hashes } | ConvertTo-Json -Depth 6
    foreach ($root in @($Plan.SourceRoot, $Plan.TargetRoot)) {
        [IO.File]::WriteAllText((Get-PreparationSyncPath $root 'sync/state.json'), $json, (New-Object Text.UTF8Encoding($false)))
    }
}
