<#
.SYNOPSIS
Tests XAML views for responsive layout issues.

.DESCRIPTION
ST-O-002: Validates XAML for small-window and high-DPI compatibility:
- MinWidth/MinHeight settings on key containers
- Grid column/row definitions with flexible sizing (Star units)
- ScrollViewer wrapping for potentially overflowing content
- High-DPI settings (UseLayoutRounding, SnapsToDevicePixels)
- DataGrid column width flexibility

.PARAMETER RepositoryRoot
Repository root path. Defaults to parent of script directory.

.PARAMETER ViewPath
Optional path to a specific XAML file to test.

.PARAMETER MinWindowWidth
Minimum supported window width in pixels. Default 800.

.PARAMETER MinWindowHeight
Minimum supported window height in pixels. Default 600.

.PARAMETER OutputPath
Path for JSON report.

.PARAMETER FailOnIssues
Exit with error code if issues are found.

.PARAMETER PassThru
Return results object.

.EXAMPLE
.\Test-ResponsiveLayout.ps1 -PassThru

.EXAMPLE
.\Test-ResponsiveLayout.ps1 -MinWindowWidth 1024 -FailOnIssues
#>
param(
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string]$ViewPath,
    [int]$MinWindowWidth = 800,
    [int]$MinWindowHeight = 600,
    [string]$OutputPath,
    [switch]$FailOnIssues,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'

Write-Host "StateTrace Responsive Layout Validator" -ForegroundColor Cyan
Write-Host ("  Minimum window: {0}x{1}" -f $MinWindowWidth, $MinWindowHeight) -ForegroundColor Cyan

# Find XAML files
$xamlFiles = @()
if ($ViewPath) {
    if (Test-Path -LiteralPath $ViewPath) {
        $xamlFiles = @(Get-Item -LiteralPath $ViewPath)
    }
}
else {
    $viewsDir = Join-Path $repoRoot 'Views'
    $mainDir = Join-Path $repoRoot 'Main'

    if (Test-Path -LiteralPath $viewsDir) {
        $xamlFiles += Get-ChildItem -LiteralPath $viewsDir -Filter '*.xaml' -File -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $mainDir) {
        $xamlFiles += Get-ChildItem -LiteralPath $mainDir -Filter '*.xaml' -File -ErrorAction SilentlyContinue
    }
}

Write-Host ("  Found {0} XAML files to analyze" -f $xamlFiles.Count) -ForegroundColor Cyan

$results = [System.Collections.Generic.List[pscustomobject]]::new()
$issues = [System.Collections.Generic.List[pscustomobject]]::new()
$warnings = [System.Collections.Generic.List[pscustomobject]]::new()

foreach ($file in $xamlFiles) {
    Write-Host ("`nAnalyzing: {0}" -f $file.Name) -ForegroundColor White

    $fileIssues = [System.Collections.Generic.List[pscustomobject]]::new()
    $fileWarnings = [System.Collections.Generic.List[pscustomobject]]::new()

    try {
        $content = Get-Content -LiteralPath $file.FullName -Raw

        # Check 1: MinWidth/MinHeight on Window or UserControl
        if ($content -match '<Window[^>]*>' -or $content -match '<UserControl[^>]*>') {
            $hasMinWidth = $content -match 'MinWidth\s*=\s*"(\d+)"'
            $hasMinHeight = $content -match 'MinHeight\s*=\s*"(\d+)"'

            if (-not $hasMinWidth) {
                $fileWarnings.Add([pscustomobject]@{
                    Check = 'MinWidth'
                    Message = 'No MinWidth specified on root element'
                    Suggestion = "Add MinWidth=`"$MinWindowWidth`" to prevent layout issues at small sizes"
                })
            }
            elseif ($Matches[1] -lt $MinWindowWidth) {
                $fileWarnings.Add([pscustomobject]@{
                    Check = 'MinWidth'
                    Message = ("MinWidth={0} is below recommended minimum {1}" -f $Matches[1], $MinWindowWidth)
                    Suggestion = "Consider increasing MinWidth to $MinWindowWidth"
                })
            }

            if (-not $hasMinHeight) {
                $fileWarnings.Add([pscustomobject]@{
                    Check = 'MinHeight'
                    Message = 'No MinHeight specified on root element'
                    Suggestion = "Add MinHeight=`"$MinWindowHeight`" to prevent layout issues at small sizes"
                })
            }
        }

        # Check 2: Grid flexibility (Star vs fixed sizing)
        $gridMatches = [regex]::Matches($content, '<Grid[^>]*>([\s\S]*?)</Grid>', 'IgnoreCase')
        $hasFlexibleGrid = $false
        $hasAllFixedGrid = $false

        foreach ($gridMatch in $gridMatches) {
            $gridContent = $gridMatch.Groups[1].Value

            # Check for ColumnDefinitions with Star
            if ($gridContent -match 'ColumnDefinition[^>]*Width\s*=\s*"[^"]*\*') {
                $hasFlexibleGrid = $true
            }
            # Check for all fixed-width columns
            if ($gridContent -match '<ColumnDefinitions>' -and $gridContent -notmatch 'Width\s*=\s*"[^"]*\*') {
                if ($gridContent -match 'Width\s*=\s*"\d+') {
                    $hasAllFixedGrid = $true
                }
            }
        }

        if ($hasAllFixedGrid -and -not $hasFlexibleGrid) {
            $fileWarnings.Add([pscustomobject]@{
                Check = 'GridFlexibility'
                Message = 'Grid uses all fixed-width columns'
                Suggestion = 'Consider using Star (*) sizing for at least one column to enable responsive behavior'
            })
        }

        # Check 3: ScrollViewer for potentially overflowing content
        $hasDataGrid = $content -match '<DataGrid[^>]*>'
        $hasListView = $content -match '<ListView[^>]*>'
        $hasScrollViewer = $content -match '<ScrollViewer[^>]*>'

        if (($hasDataGrid -or $hasListView) -and -not $hasScrollViewer) {
            # DataGrids have built-in scrolling, but check for nested content
            if ($content -match '<StackPanel[^>]*>' -and $content -match '<DataGrid') {
                $fileWarnings.Add([pscustomobject]@{
                    Check = 'ScrollViewer'
                    Message = 'StackPanel with DataGrid may cause layout issues'
                    Suggestion = 'Consider wrapping in ScrollViewer or using Grid layout for better responsiveness'
                })
            }
        }

        # Check 4: High-DPI settings
        $hasLayoutRounding = $content -match 'UseLayoutRounding\s*=\s*"True"'
        $hasSnapsToPixels = $content -match 'SnapsToDevicePixels\s*=\s*"True"'

        if (-not $hasLayoutRounding -and ($content -match '<Window' -or $content -match '<UserControl')) {
            $fileWarnings.Add([pscustomobject]@{
                Check = 'HighDPI'
                Message = 'UseLayoutRounding not enabled'
                Suggestion = 'Add UseLayoutRounding="True" to root element for sharper rendering at high DPI'
            })
        }

        # Check 5: DataGrid column flexibility
        $dataGridColMatches = [regex]::Matches($content, '<DataGridTextColumn[^>]*Width\s*=\s*"(\d+)"', 'IgnoreCase')
        $fixedWidthColumns = $dataGridColMatches.Count
        $starWidthColumns = ([regex]::Matches($content, '<DataGridTextColumn[^>]*Width\s*=\s*"[^"]*\*"', 'IgnoreCase')).Count

        if ($fixedWidthColumns -gt 3 -and $starWidthColumns -eq 0) {
            $fileWarnings.Add([pscustomobject]@{
                Check = 'DataGridColumns'
                Message = ("All {0} DataGrid columns have fixed widths" -f $fixedWidthColumns)
                Suggestion = 'Consider using Width="*" for at least one column to enable horizontal flexibility'
            })
        }

        # Check 6: TextBlock/Label wrapping
        $textBlockCount = ([regex]::Matches($content, '<TextBlock[^>]*>', 'IgnoreCase')).Count
        $wrappingTextBlocks = ([regex]::Matches($content, '<TextBlock[^>]*TextWrapping\s*=\s*"(Wrap|WrapWithOverflow)"', 'IgnoreCase')).Count

        if ($textBlockCount -gt 5 -and $wrappingTextBlocks -eq 0) {
            $fileWarnings.Add([pscustomobject]@{
                Check = 'TextWrapping'
                Message = ("None of {0} TextBlocks have TextWrapping enabled" -f $textBlockCount)
                Suggestion = 'Consider adding TextWrapping="Wrap" to labels that may overflow at small widths'
            })
        }

        # Check 7: Horizontal alignment patterns
        $stretchCount = ([regex]::Matches($content, 'HorizontalAlignment\s*=\s*"Stretch"', 'IgnoreCase')).Count
        $fixedAlignCount = ([regex]::Matches($content, 'HorizontalAlignment\s*=\s*"(Left|Right|Center)"', 'IgnoreCase')).Count

        if ($fixedAlignCount -gt 10 -and $stretchCount -eq 0) {
            $fileWarnings.Add([pscustomobject]@{
                Check = 'HorizontalAlignment'
                Message = 'Many elements use fixed HorizontalAlignment without any Stretch'
                Suggestion = 'Consider using HorizontalAlignment="Stretch" for container elements to improve responsiveness'
            })
        }

        # Summarize file results
        $status = 'Pass'
        if ($fileIssues.Count -gt 0) {
            $status = 'Fail'
        }
        elseif ($fileWarnings.Count -gt 0) {
            $status = 'Warnings'
        }

        $fileResult = [pscustomobject]@{
            File        = $file.Name
            Path        = $file.FullName
            Status      = $status
            IssueCount  = $fileIssues.Count
            WarningCount = $fileWarnings.Count
            Issues      = $fileIssues
            Warnings    = $fileWarnings
        }

        $results.Add($fileResult)

        foreach ($i in $fileIssues) { $issues.Add($i) }
        foreach ($w in $fileWarnings) { $warnings.Add($w) }

        # Display
        $statusColor = switch ($status) {
            'Pass' { 'Green' }
            'Warnings' { 'Yellow' }
            'Fail' { 'Red' }
        }

        Write-Host ("  Status: {0}" -f $status) -ForegroundColor $statusColor
        if ($fileWarnings.Count -gt 0) {
            foreach ($w in $fileWarnings) {
                Write-Host ("    [{0}] {1}" -f $w.Check, $w.Message) -ForegroundColor Yellow
            }
        }
    }
    catch {
        $fileResult = [pscustomobject]@{
            File        = $file.Name
            Path        = $file.FullName
            Status      = 'Error'
            IssueCount  = 1
            WarningCount = 0
            Issues      = @([pscustomobject]@{ Check = 'Parse'; Message = $_.Exception.Message })
            Warnings    = @()
        }
        $results.Add($fileResult)
        Write-Host ("  Error: {0}" -f $_.Exception.Message) -ForegroundColor Red
    }
}

# Build summary
$passCount = @($results | Where-Object { $_.Status -eq 'Pass' }).Count
$warnCount = @($results | Where-Object { $_.Status -eq 'Warnings' }).Count
$failCount = @($results | Where-Object { $_.Status -eq 'Fail' -or $_.Status -eq 'Error' }).Count

$overallStatus = 'Pass'
if ($failCount -gt 0) {
    $overallStatus = 'Fail'
}
elseif ($warnCount -gt 0) {
    $overallStatus = 'Warnings'
}

$summary = [pscustomobject]@{
    Timestamp       = Get-Date -Format 'o'
    MinWindowWidth  = $MinWindowWidth
    MinWindowHeight = $MinWindowHeight
    FileCount       = $results.Count
    PassCount       = $passCount
    WarningCount    = $warnCount
    FailCount       = $failCount
    TotalIssues     = $issues.Count
    TotalWarnings   = $warnings.Count
    OverallStatus   = $overallStatus
    Results         = $results
}

# Output
if (-not $OutputPath) {
    $OutputPath = Join-Path $repoRoot ("Logs\Reports\ResponsiveLayout-{0}.json" -f $timestamp)
}

$outputDir = Split-Path -Path $OutputPath -Parent
if (-not (Test-Path -LiteralPath $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
Write-Host ("`nReport written to: {0}" -f $OutputPath) -ForegroundColor Green

# Display summary
Write-Host "`nResponsive Layout Summary:" -ForegroundColor Cyan
Write-Host ("  Files analyzed: {0}" -f $summary.FileCount)
Write-Host ("  Pass: {0}" -f $passCount) -ForegroundColor Green
if ($warnCount -gt 0) {
    Write-Host ("  Warnings: {0}" -f $warnCount) -ForegroundColor Yellow
}
if ($failCount -gt 0) {
    Write-Host ("  Fail: {0}" -f $failCount) -ForegroundColor Red
}
Write-Host ("  Overall: {0}" -f $summary.OverallStatus) -ForegroundColor $(if ($overallStatus -eq 'Pass') { 'Green' } elseif ($overallStatus -eq 'Warnings') { 'Yellow' } else { 'Red' })

if ($warnings.Count -gt 0) {
    Write-Host "`nTop recommendations:" -ForegroundColor Cyan
    $topSuggestions = $warnings | Group-Object -Property Check | Sort-Object Count -Descending | Select-Object -First 3
    foreach ($group in $topSuggestions) {
        $sample = $group.Group | Select-Object -First 1
        Write-Host ("  - {0} ({1} occurrences): {2}" -f $group.Name, $group.Count, $sample.Suggestion) -ForegroundColor White
    }
}

if ($FailOnIssues -and ($failCount -gt 0 -or $issues.Count -gt 0)) {
    Write-Error "Responsive layout validation failed with $failCount failures and $($issues.Count) issues"
    exit 2
}

if ($PassThru) {
    return $summary
}
