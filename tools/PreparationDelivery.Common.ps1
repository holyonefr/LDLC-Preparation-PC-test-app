function Get-PreparationDelivery {
    param([Parameter(Mandatory = $true)][string]$RepositoryRoot)
    $root = [IO.Path]::GetFullPath($RepositoryRoot)
    $baseName = 'LDLCPreparationPC'
    $edition = 'LDLC'
    $profilePath = Join-Path $root 'sync/edition.json'
    if (Test-Path -LiteralPath $profilePath -PathType Leaf) {
        $profile = Get-Content -LiteralPath $profilePath -Raw | ConvertFrom-Json
        if ($profile.SchemaVersion -ne 1) { throw 'Profil de livraison inconnu.' }
        if ($profile.Edition) { $edition = [string]$profile.Edition }
        if ($null -ne $profile.PSObject.Properties['DeliveryBaseName']) {
            $baseName = [string]$profile.DeliveryBaseName
        }
    }
    if ($edition -notin @('LDLC','NUMERIKS')) { throw 'Edition de livraison inconnue.' }
    if ($baseName -notmatch "^[A-Za-z0-9][A-Za-z0-9'_-]*$" -or $baseName.Length -gt 100 -or
        $baseName -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$') {
        throw 'Nom de livraison invalide : utiliser un nom de fichier, pas un chemin.'
    }
    # Only delivery filenames vary; embedded resource and runtime names remain compatible.
    [pscustomobject]@{
        BaseName = $baseName
        Edition = $edition
        MainScriptPath = Join-Path $root ("dist/$baseName.ps1")
        WorkerScriptPath = Join-Path $root ("dist/$baseName.worker.embed.ps1")
        ExecutablePath = Join-Path $root ("dist/$baseName.exe")
        ArtifactPaths = @("dist/$baseName.exe", "dist/$baseName.exe.config", "dist/$baseName.ps1",
            "dist/$baseName.worker.embed.ps1", 'dist/SHA256SUMS.txt')
    }
}
