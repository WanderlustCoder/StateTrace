[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BundleZipPath,
    [Parameter(Mandatory = $true)]
    [string]$OutputPath,
    [string]$RootPath,
    [switch]$AllowExtraFiles,
    [switch]$PassThru,
    [switch]$UpdateLatest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$latestPointerPath = Join-Path -Path $repoRoot -ChildPath 'Logs/Reports/RoutingBundles/RoutingBundleValidation-latest.json'

function Ensure-Directory {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    $directory = Split-Path -Parent $Path
    if ([string]::IsNullOrWhiteSpace($directory)) { return }
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
}

function Resolve-RepoPath {
    param(
        [string]$Path,
        [string]$RepoRoot
    )
    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }
    return [System.IO.Path]::GetFullPath((Join-Path -Path $RepoRoot -ChildPath $Path))
}

function Normalize-RelativePath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
    $normalized = $Path -replace '\\', '/'
    return $normalized.TrimStart('/')
}

function Test-UnsafeRelativePath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $true }
    if ($Path -match '^[a-zA-Z]:') { return $true }
    if ($Path.StartsWith('/') -or $Path.StartsWith('\')) { return $true }
    if ($Path -match '(^|[\\/])\.\.([\\/]|$)') { return $true }
    if ([System.IO.Path]::IsPathRooted($Path)) { return $true }
    return $false
}

function Assert-SafeRelativePath {
    param(
        [string]$Path,
        [string]$Label
    )
    if (Test-UnsafeRelativePath -Path $Path) {
        throw "$Label '$Path' is not a safe relative path (path traversal or absolute paths are not allowed)."
    }
}

function Read-EntryJson {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.Compression.ZipArchiveEntry]$Entry
    )
    $stream = $Entry.Open()
    try {
        $reader = New-Object System.IO.StreamReader($stream)
        try {
            $content = $reader.ReadToEnd()
        } finally {
            $reader.Dispose()
        }
    } finally {
        $stream.Dispose()
    }
    return ($content | ConvertFrom-Json -ErrorAction Stop)
}

function Get-EntryHash {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.Compression.ZipArchiveEntry]$Entry
    )
    $hasher = [System.Security.Cryptography.SHA256]::Create()
    $stream = $Entry.Open()
    try {
        $hashBytes = $hasher.ComputeHash($stream)
    } finally {
        $stream.Dispose()
        $hasher.Dispose()
    }
    return ([System.BitConverter]::ToString($hashBytes)).Replace('-', '')
}

if (-not (Test-Path -LiteralPath $BundleZipPath)) {
    throw "BundleZipPath '$BundleZipPath' was not found."
}
if ([System.IO.Path]::GetExtension($BundleZipPath) -ne '.zip') {
    throw "BundleZipPath '$BundleZipPath' must be a .zip file."
}

if ([string]::IsNullOrWhiteSpace($RootPath)) {
    $RootPath = $repoRoot
}

$resolvedBundleZipPath = Resolve-RepoPath -Path $BundleZipPath -RepoRoot $repoRoot
$resolvedOutputPath = Resolve-RepoPath -Path $OutputPath -RepoRoot $repoRoot

Add-Type -AssemblyName System.IO.Compression.FileSystem

# LANDMARK: Routing bundle validation - open zip safely and enforce manifest presence + schema checks
$zip = $null
try {
    $zip = [System.IO.Compression.ZipFile]::OpenRead($resolvedBundleZipPath)

    foreach ($entry in $zip.Entries) {
        Assert-SafeRelativePath -Path $entry.FullName -Label 'Zip entry'
    }

    $manifestEntry = $zip.Entries | Where-Object { $_.FullName -eq 'BundleManifest.json' } | Select-Object -First 1
    if (-not $manifestEntry) {
        throw "BundleManifest.json not found at zip root in '$resolvedBundleZipPath'."
    }

    try {
        $manifest = Read-EntryJson -Entry $manifestEntry
    } catch {
        throw "Failed to parse BundleManifest.json in '$resolvedBundleZipPath'."
    }

    $manifestProps = @($manifest.PSObject.Properties | ForEach-Object { $_.Name })
    if ($manifestProps -notcontains 'SchemaVersion') {
        throw 'BundleManifest.json missing SchemaVersion.'
    }
    if ($manifestProps -notcontains 'IncludedFiles') {
        throw 'BundleManifest.json missing IncludedFiles array.'
    }

    $warnings = New-Object System.Collections.Generic.List[string]
    if ($manifest.SchemaVersion -ne '1.0') {
        $warnings.Add(("BundleManifest.json SchemaVersion '{0}' differs from expected '1.0'." -f $manifest.SchemaVersion)) | Out-Null
    }

    # LANDMARK: Routing bundle validation - path traversal safety and expected/extra file set validation
    $includedFiles = @($manifest.IncludedFiles)
    $expectedSet = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
    $expectedSet.Add('BundleManifest.json') | Out-Null
    $normalizedIncluded = New-Object System.Collections.Generic.List[object]
    $fatalMessage = $null

    for ($i = 0; $i -lt $includedFiles.Count; $i++) {
        $item = $includedFiles[$i]
        if ($null -eq $item) {
            throw ("BundleManifest.json IncludedFiles entry at index {0} is null." -f $i)
        }
        $itemProps = @($item.PSObject.Properties | ForEach-Object { $_.Name })
        foreach ($required in @('RelativePath', 'Sha256', 'Bytes')) {
            if ($itemProps -notcontains $required) {
                throw ("BundleManifest.json IncludedFiles entry at index {0} missing {1}." -f $i, $required)
            }
        }

        $relativePath = [string]$item.RelativePath
        if ([string]::IsNullOrWhiteSpace($relativePath)) {
            throw ("BundleManifest.json IncludedFiles entry at index {0} has an empty RelativePath." -f $i)
        }
        Assert-SafeRelativePath -Path $relativePath -Label 'Manifest RelativePath'

        $normalizedPath = Normalize-RelativePath -Path $relativePath
        $expectedSet.Add($normalizedPath) | Out-Null
        $normalizedIncluded.Add([ordered]@{
            RelativePath = $normalizedPath
            Sha256       = [string]$item.Sha256
            Bytes        = $item.Bytes
        }) | Out-Null
    }

    $entryMap = @{}
    foreach ($entry in $zip.Entries) {
        # Skip directory entries (can end with / or \ depending on how ZIP was created)
        if ($entry.FullName.EndsWith('/') -or $entry.FullName.EndsWith('\')) { continue }
        $normalizedEntry = Normalize-RelativePath -Path $entry.FullName
        # Also skip if normalized path ends with / (defensive check after normalization)
        if ($normalizedEntry.EndsWith('/')) { continue }
        if (-not $entryMap.ContainsKey($normalizedEntry)) {
            $entryMap[$normalizedEntry] = $entry
        }
    }

    $missingFiles = New-Object System.Collections.Generic.List[string]
    foreach ($item in $normalizedIncluded) {
        if (-not $entryMap.ContainsKey($item.RelativePath)) {
            $missingFiles.Add($item.RelativePath) | Out-Null
        }
    }

    $extraFiles = @($entryMap.Keys | Where-Object { -not $expectedSet.Contains($_) } | Sort-Object)
    if ($extraFiles.Count -gt 0) {
        if ($AllowExtraFiles.IsPresent) {
            $warnings.Add(("Bundle contains extra files: {0}" -f ($extraFiles -join ', '))) | Out-Null
        } else {
            $fatalMessage = "Bundle contains unexpected files: {0}. Use -AllowExtraFiles to permit extras." -f ($extraFiles -join ', ')
        }
    }

    # LANDMARK: Routing bundle validation - SHA256 + byte-length verification with deterministic output + latest pointer
    $hashMismatches = New-Object System.Collections.Generic.List[object]
    foreach ($item in $normalizedIncluded) {
        if (-not $entryMap.ContainsKey($item.RelativePath)) { continue }
        $entry = $entryMap[$item.RelativePath]
        $expectedHash = [string]$item.Sha256
        $expectedBytes = [int64]$item.Bytes
        $actualHash = Get-EntryHash -Entry $entry
        $actualBytes = [int64]$entry.Length

        $hashMatches = $actualHash.Equals($expectedHash, [System.StringComparison]::OrdinalIgnoreCase)
        $bytesMatch = $actualBytes -eq $expectedBytes
        if (-not $hashMatches -or -not $bytesMatch) {
            $hashMismatches.Add([ordered]@{
                RelativePath  = $item.RelativePath
                ExpectedSha256 = $expectedHash
                ActualSha256   = $actualHash
                ExpectedBytes  = $expectedBytes
                ActualBytes    = $actualBytes
            }) | Out-Null
        }
    }

    $missingSorted = @($missingFiles | Sort-Object)
    $extraSorted = @($extraFiles)
    $mismatchSorted = @($hashMismatches | Sort-Object RelativePath)
    $warningsArray = @($warnings)

    $status = 'Pass'
    if ($missingSorted.Count -gt 0 -or $mismatchSorted.Count -gt 0 -or $fatalMessage) {
        $status = 'Fail'
    }

    $expectedCount = $expectedSet.Count
    $foundCount = $expectedCount - $missingSorted.Count
    $validation = [ordered]@{
        SchemaVersion = '1.0'
        BundleZipPath = $resolvedBundleZipPath
        ValidatedAt   = (Get-Date -Format o)
        Status        = $status
        Counts        = [ordered]@{
            ExpectedFiles  = $expectedCount
            FoundFiles     = $foundCount
            Extras         = $extraSorted.Count
            Missing        = $missingSorted.Count
            HashMismatches = $mismatchSorted.Count
        }
        MissingFiles  = $missingSorted
        ExtraFiles    = $extraSorted
        HashMismatches = $mismatchSorted
        Warnings      = $warningsArray
    }

    Ensure-Directory -Path $resolvedOutputPath
    $validation | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $resolvedOutputPath -Encoding UTF8

    if ($UpdateLatest.IsPresent) {
        Ensure-Directory -Path $latestPointerPath
        Copy-Item -LiteralPath $resolvedOutputPath -Destination $latestPointerPath -Force
    }

    if ($status -ne 'Pass') {
        if ($fatalMessage) { throw $fatalMessage }
        throw ("Bundle validation failed with {0} missing file(s) and {1} hash mismatch(es)." -f `
            $missingSorted.Count, $mismatchSorted.Count)
    }

    if ($PassThru.IsPresent) {
        return $validation
    }
} finally {
    if ($zip) {
        $zip.Dispose()
    }
}
