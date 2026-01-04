[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BundleZipPath,
    [Parameter(Mandatory = $true)]
    [string]$OutputRoot,
    [switch]$Overwrite,
    [switch]$SkipValidation,
    [switch]$AllowExtraFiles,
    [string]$ValidationOutputPath,
    [string]$SummaryPath,
    [switch]$UpdateLatest,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$latestPointerPath = Join-Path -Path $repoRoot -ChildPath 'Logs/Reports/RoutingBundles/RoutingBundleExpanded-latest.json'
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'

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

function Normalize-ZipEntryPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
    $normalized = $Path -replace '/', '\'
    return $normalized.TrimStart('\').TrimEnd('\')
}

if (-not (Test-Path -LiteralPath $BundleZipPath)) {
    throw "BundleZipPath '$BundleZipPath' was not found."
}
if ([System.IO.Path]::GetExtension($BundleZipPath) -ne '.zip') {
    throw "BundleZipPath '$BundleZipPath' must be a .zip file."
}

$resolvedBundleZipPath = Resolve-RepoPath -Path $BundleZipPath -RepoRoot $repoRoot
$resolvedOutputRoot = Resolve-RepoPath -Path $OutputRoot -RepoRoot $repoRoot

# LANDMARK: Routing bundle expand - output root preparation and overwrite safety
if (Test-Path -LiteralPath $resolvedOutputRoot) {
    $outputItem = Get-Item -LiteralPath $resolvedOutputRoot
    if (-not $outputItem.PSIsContainer) {
        throw "OutputRoot '$resolvedOutputRoot' must be a directory."
    }
    $existingItem = Get-ChildItem -LiteralPath $resolvedOutputRoot -Force | Select-Object -First 1
    if ($existingItem) {
        if (-not $Overwrite.IsPresent) {
            throw "OutputRoot '$resolvedOutputRoot' is not empty. Use -Overwrite to clear it."
        }
        Get-ChildItem -LiteralPath $resolvedOutputRoot -Force | Remove-Item -Recurse -Force
    }
} else {
    New-Item -ItemType Directory -Path $resolvedOutputRoot -Force | Out-Null
}

if ([string]::IsNullOrWhiteSpace($ValidationOutputPath)) {
    $ValidationOutputPath = Join-Path -Path $resolvedOutputRoot -ChildPath ("RoutingBundleValidation-{0}.json" -f $timestamp)
}
if ([string]::IsNullOrWhiteSpace($SummaryPath)) {
    $SummaryPath = Join-Path -Path $resolvedOutputRoot -ChildPath ("RoutingBundleExpandedSummary-{0}.json" -f $timestamp)
}

$resolvedValidationOutputPath = Resolve-RepoPath -Path $ValidationOutputPath -RepoRoot $repoRoot
$resolvedSummaryPath = Resolve-RepoPath -Path $SummaryPath -RepoRoot $repoRoot
$manifestExtractedPath = Join-Path -Path $resolvedOutputRoot -ChildPath 'BundleManifest.json'

$warnings = New-Object System.Collections.Generic.List[string]
$zipEntryCount = 0
$filesExtracted = 0
$directoriesCreated = 0
$validated = $false
$validationFailed = $false
$validationFailureMessage = $null
$extractionFailed = $false
$extractionFailureMessage = $null
$extractionFailureException = $null

# LANDMARK: Routing bundle expand - validate bundle first (unless skipped) and require PASS
if (-not $SkipValidation.IsPresent) {
    $validated = $true
    $validatorPath = Join-Path -Path $repoRoot -ChildPath 'Tools/Test-RoutingOfflineBundle.ps1'
    if (-not (Test-Path -LiteralPath $validatorPath)) {
        throw "Routing bundle validation tool not found at '$validatorPath'."
    }
    try {
        $validationResult = & $validatorPath -BundleZipPath $resolvedBundleZipPath -OutputPath $resolvedValidationOutputPath -AllowExtraFiles:$AllowExtraFiles.IsPresent -PassThru
        if ($validationResult.Status -ne 'Pass') {
            $validationFailed = $true
            $validationFailureMessage = "Bundle validation failed with status '$($validationResult.Status)'."
        }
    } catch {
        $validationFailed = $true
        $validationFailureMessage = $_.Exception.Message
    }
    if ($validationFailed) {
        $warnings.Add(("Validation failed: {0}" -f $validationFailureMessage)) | Out-Null
    }
} else {
    $warnings.Add('Validation skipped.') | Out-Null
}

if (-not $validationFailed) {
    # LANDMARK: Routing bundle expand - safe ZipArchive extraction with traversal defenses
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = $null
    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($resolvedBundleZipPath)
        $zipEntryCount = $zip.Entries.Count
        $createdDirectories = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)

        foreach ($entry in $zip.Entries) {
            if ([string]::IsNullOrWhiteSpace($entry.FullName)) { continue }
            Assert-SafeRelativePath -Path $entry.FullName -Label 'Zip entry'

            $normalizedPath = Normalize-ZipEntryPath -Path $entry.FullName
            if ([string]::IsNullOrWhiteSpace($normalizedPath)) { continue }
            $destinationPath = Join-Path -Path $resolvedOutputRoot -ChildPath $normalizedPath

            # Skip directory entries (can end with / or \ depending on how ZIP was created)
            if ($entry.FullName.EndsWith('/') -or $entry.FullName.EndsWith('\')) {
                if (-not (Test-Path -LiteralPath $destinationPath)) {
                    New-Item -ItemType Directory -Path $destinationPath -Force | Out-Null
                    if ($createdDirectories.Add($destinationPath)) {
                        $directoriesCreated++
                    }
                }
                continue
            }

            $parentDir = Split-Path -Parent $destinationPath
            if (-not [string]::IsNullOrWhiteSpace($parentDir) -and -not (Test-Path -LiteralPath $parentDir)) {
                New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
                if ($createdDirectories.Add($parentDir)) {
                    $directoriesCreated++
                }
            }

            $entryStream = $entry.Open()
            try {
                $fileStream = [System.IO.File]::Open($destinationPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
                try {
                    $entryStream.CopyTo($fileStream)
                } finally {
                    $fileStream.Dispose()
                }
            } finally {
                $entryStream.Dispose()
            }
            $filesExtracted++
        }
    } catch {
        $extractionFailed = $true
        $extractionFailureMessage = $_.Exception.Message
        $extractionFailureException = $_.Exception
        $warnings.Add($extractionFailureMessage) | Out-Null
    } finally {
        if ($zip) {
            $zip.Dispose()
        }
    }
}

$status = if ($validationFailed -or $extractionFailed) { 'Fail' } else { 'Pass' }
$validationPathValue = if ($validated) { $resolvedValidationOutputPath } else { $null }

# LANDMARK: Routing bundle expand - deterministic summary output and latest pointer
$summary = [ordered]@{
    SchemaVersion        = '1.0'
    BundleZipPath        = $resolvedBundleZipPath
    ExtractedAt          = (Get-Date -Format o)
    OutputRoot           = $resolvedOutputRoot
    Status               = $status
    Validated            = $validated
    ValidationOutputPath = $validationPathValue
    ManifestExtractedPath = $manifestExtractedPath
    Counts               = [ordered]@{
        ZipEntries         = $zipEntryCount
        FilesExtracted     = $filesExtracted
        DirectoriesCreated = $directoriesCreated
    }
    Warnings             = @($warnings)
}

Ensure-Directory -Path $resolvedSummaryPath
$summary | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $resolvedSummaryPath -Encoding UTF8

if ($UpdateLatest.IsPresent) {
    Ensure-Directory -Path $latestPointerPath
    Copy-Item -LiteralPath $resolvedSummaryPath -Destination $latestPointerPath -Force
}

if ($status -ne 'Pass') {
    if ($validationFailed) {
        throw ("Bundle validation failed. See '{0}'." -f $resolvedValidationOutputPath)
    }
    if ($extractionFailureException) {
        throw $extractionFailureException
    }
    throw ("Bundle extraction failed. See '{0}'." -f $resolvedSummaryPath)
}

Write-Host ("Bundle expanded: {0}" -f $resolvedBundleZipPath)
Write-Host ("OutputRoot: {0}" -f $resolvedOutputRoot)
Write-Host ("Validated: {0}" -f $validated)
Write-Host ("Manifest: {0}" -f $manifestExtractedPath)
Write-Host ("Summary: {0}" -f $resolvedSummaryPath)

if ($PassThru.IsPresent) {
    return $summary
}
