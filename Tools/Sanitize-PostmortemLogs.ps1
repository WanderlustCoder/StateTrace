param(
    [Parameter(Mandatory)][string]$SourcePath,
    [Parameter(Mandatory)][string]$DestinationPath,
    [string[]]$RedactPatterns = @('password','secret','token','community'),
    [switch]$DryRun
)

<#
.SYNOPSIS
    Lightweight sanitizer for incident postmortem log bundles.
.DESCRIPTION
    Copies all files beneath $SourcePath into $DestinationPath, redacting lines
    that match any of the supplied patterns. Patterns are treated as case-insensitive
    plain text unless prefixed with 'regex:'. When DryRun is specified, a report is
    generated without writing sanitized files.
.NOTES
    Customize RedactPatterns locally per incident as needed. This is a starting point
    and should be expanded once specific sensitive markers are identified.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $SourcePath)) {
    throw "Source path '$SourcePath' was not found."
}

$resolvedSource = (Get-Item -LiteralPath $SourcePath).FullName
$resolvedDest   = Resolve-Path -LiteralPath $DestinationPath -ErrorAction SilentlyContinue
if (-not $resolvedDest) {
    $null = New-Item -ItemType Directory -Path $DestinationPath -Force
    $resolvedDest = (Get-Item -LiteralPath $DestinationPath).FullName
} else {
    $resolvedDest = $resolvedDest.ProviderPath
}

$reports = New-Object System.Collections.Generic.List[object]

function Test-Match {
    param(
        [string]$Line,
        [string]$Pattern
    )
    if ($Pattern -like 'regex:*') {
        $regex = $Pattern.Substring(6)
        return [regex]::IsMatch($Line, $regex, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }
    return $Line.IndexOf($Pattern, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
}

Get-ChildItem -LiteralPath $resolvedSource -File -Recurse | ForEach-Object {
    $relative = $_.FullName.Substring($resolvedSource.Length).TrimStart('\\','/')
    $destFile = Join-Path $resolvedDest $relative
    $destDir  = Split-Path -Parent $destFile
    if (-not (Test-Path -LiteralPath $destDir)) {
        $null = New-Item -ItemType Directory -Path $destDir -Force
    }

    $lineNumber = 0
    $redactedCount = 0
    $outputLines = New-Object System.Collections.Generic.List[string]

    foreach ($line in Get-Content -LiteralPath $_.FullName -ReadCount 1) {
        $lineNumber++
        $shouldRedact = $false
        foreach ($pattern in $RedactPatterns) {
            if ([string]::IsNullOrWhiteSpace($pattern)) { continue }
            if (Test-Match -Line $line -Pattern $pattern) {
                $shouldRedact = $true
                $reports.Add([PSCustomObject]@{
                    File = $_.FullName
                    RelativePath = $relative
                    LineNumber   = $lineNumber
                    Pattern      = $pattern
                })
                break
            }
        }

        if ($shouldRedact) {
            $redactedCount++
            $outputLines.Add('[REDACTED LINE]') | Out-Null
        } else {
            $outputLines.Add($line) | Out-Null
        }
    }

    if (-not $DryRun) {
        $outputLines | Set-Content -LiteralPath $destFile -Encoding UTF8
    }
}

$reportPath = Join-Path $resolvedDest 'sanitization-report.csv'
$reports | Export-Csv -Path $reportPath -NoTypeInformation

if ($DryRun) {
    Write-Host "Dry run complete. Report generated at $reportPath" -ForegroundColor Yellow
} else {
    Write-Host "Sanitized logs written to $resolvedDest. Report: $reportPath" -ForegroundColor Green
}
