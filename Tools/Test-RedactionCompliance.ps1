[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string[]]$Path,

    [string[]]$RedactPatterns = @('password', 'secret', 'token', 'community', 'snmpv3', 'credential', 'api[_-]?key'),

    [string[]]$ExcludePatterns = @('*.accdb', '*.clixml', '*.dll', '*.exe', '*.zip'),

    [string]$OutputPath,

    [switch]$FailOnMatch,

    [switch]$PassThru
)

<#
.SYNOPSIS
Validates files do not contain unredacted sensitive patterns (ST-M-003).

.DESCRIPTION
Scans files for common sensitive patterns that should have been redacted
before inclusion in telemetry bundles or shared artifacts.

.PARAMETER Path
One or more file or directory paths to scan.

.PARAMETER RedactPatterns
Regex patterns to detect sensitive data. Defaults to common secrets.

.PARAMETER ExcludePatterns
File patterns to exclude from scanning (binary files, etc.).

.PARAMETER OutputPath
If specified, writes the compliance report to a JSON file.

.PARAMETER FailOnMatch
If set, exits with code 1 when sensitive patterns are found.

.PARAMETER PassThru
Returns the compliance result as an object.

.EXAMPLE
pwsh Tools\Test-RedactionCompliance.ps1 -Path Logs\TelemetryBundles\Release-2026-01-04 -FailOnMatch

.EXAMPLE
pwsh Tools\Test-RedactionCompliance.ps1 -Path Data\Postmortems -OutputPath Logs\Reports\RedactionCompliance.json -PassThru
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Initialize result
$result = [pscustomobject]@{
    GeneratedAtUtc   = (Get-Date).ToUniversalTime().ToString('o')
    PathsScanned     = @()
    FilesScanned     = 0
    FilesSkipped     = 0
    MatchesFound     = 0
    Violations       = @()
    Status           = 'Unknown'
    Message          = ''
}

Write-Host "`n=== Redaction Compliance Check (ST-M-003) ===" -ForegroundColor Cyan
Write-Host ("Timestamp: {0}" -f $result.GeneratedAtUtc) -ForegroundColor DarkGray
Write-Host ("Patterns: {0}" -f ($RedactPatterns -join ', ')) -ForegroundColor DarkGray
Write-Host ""

# Build combined regex
$combinedPattern = '(?i)(' + ($RedactPatterns -join '|') + ')'

# Collect files to scan
$filesToScan = [System.Collections.Generic.List[object]]::new()

foreach ($p in $Path) {
    if (-not (Test-Path -LiteralPath $p)) {
        Write-Warning "Path not found: $p"
        continue
    }

    $result.PathsScanned += $p

    $item = Get-Item -LiteralPath $p
    if ($item.PSIsContainer) {
        $children = Get-ChildItem -LiteralPath $p -File -Recurse -ErrorAction SilentlyContinue
        foreach ($child in $children) {
            $filesToScan.Add($child)
        }
    } else {
        $filesToScan.Add($item)
    }
}

Write-Host ("Files to scan: {0}" -f $filesToScan.Count) -ForegroundColor DarkGray

# Scan files
foreach ($file in $filesToScan) {
    # Check exclusions
    $excluded = $false
    foreach ($exclude in $ExcludePatterns) {
        if ($file.Name -like $exclude) {
            $excluded = $true
            break
        }
    }

    if ($excluded) {
        $result.FilesSkipped++
        continue
    }

    $result.FilesScanned++

    try {
        $content = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($content)) {
            continue
        }

        $matches = [regex]::Matches($content, $combinedPattern)
        if ($matches.Count -gt 0) {
            $result.MatchesFound += $matches.Count

            # Get unique matched patterns
            $uniqueMatches = @($matches | ForEach-Object { $_.Value.ToLower() } | Sort-Object -Unique)

            $violation = [pscustomobject]@{
                FilePath       = $file.FullName
                MatchCount     = $matches.Count
                MatchedPatterns = $uniqueMatches
            }
            $result.Violations += $violation

            Write-Host ("  VIOLATION: {0} ({1} matches: {2})" -f $file.FullName, $matches.Count, ($uniqueMatches -join ', ')) -ForegroundColor Red
        }
    } catch {
        Write-Warning ("Failed to read {0}: {1}" -f $file.FullName, $_.Exception.Message)
    }
}

Write-Host ""

# Determine status
if ($result.MatchesFound -gt 0) {
    $result.Status = 'Fail'
    $result.Message = "Found $($result.MatchesFound) potential sensitive data matches in $($result.Violations.Count) file(s). Run Tools\Sanitize-PostmortemLogs.ps1 or Tools\Invoke-SanitizationWorkflow.ps1 to redact."
    Write-Host ("FAIL: {0}" -f $result.Message) -ForegroundColor Red
} else {
    $result.Status = 'Pass'
    $result.Message = "No sensitive patterns detected in $($result.FilesScanned) files."
    Write-Host ("PASS: {0}" -f $result.Message) -ForegroundColor Green
}

Write-Host ("  Files scanned: {0}" -f $result.FilesScanned) -ForegroundColor DarkGray
Write-Host ("  Files skipped: {0}" -f $result.FilesSkipped) -ForegroundColor DarkGray
Write-Host ""

# Write output
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    try {
        $outputDir = Split-Path -Path $OutputPath -Parent
        if ($outputDir -and -not (Test-Path -LiteralPath $outputDir)) {
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        }
        $result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputPath -Encoding utf8
        Write-Host "Report saved to: $OutputPath" -ForegroundColor DarkCyan
    } catch {
        Write-Warning "Failed to save report: $($_.Exception.Message)"
    }
}

if ($PassThru.IsPresent) {
    return $result
}

if ($FailOnMatch.IsPresent -and $result.Status -eq 'Fail') {
    exit 1
}
