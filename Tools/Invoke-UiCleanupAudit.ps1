<#
.SYNOPSIS
Audits XAML controls and code-behind handlers for potential cleanup.

.DESCRIPTION
ST-S-004: Identifies unused XAML controls and code-behind handlers in
Compare/Templates/other legacy flows. Reports candidates for removal
after confirming no bindings or telemetry rely on them.

Checks performed:
- XAML element names (x:Name) vs code-behind references
- Event handlers defined but potentially unreferenced
- Commented/disabled controls
- Legacy control patterns (older naming conventions)

.PARAMETER ViewsPath
Path to Views directory. Defaults to Views/.

.PARAMETER ModulesPath
Path to Modules directory. Defaults to Modules/.

.PARAMETER IncludeCommented
Include analysis of commented-out controls.

.PARAMETER RepositoryRoot
Repository root path. Defaults to parent of script directory.

.PARAMETER OutputPath
Optional JSON output path for the audit report.

.PARAMETER PassThru
Return the audit result as an object.

.EXAMPLE
.\Invoke-UiCleanupAudit.ps1

.EXAMPLE
.\Invoke-UiCleanupAudit.ps1 -OutputPath Logs\Reports\UiCleanupAudit.json -IncludeCommented
#>
param(
    [string]$ViewsPath,
    [string]$ModulesPath,
    [switch]$IncludeCommented,
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string]$OutputPath,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path

if (-not $ViewsPath) { $ViewsPath = Join-Path $repoRoot 'Views' }
if (-not $ModulesPath) { $ModulesPath = Join-Path $repoRoot 'Modules' }

Write-Host "Running UI cleanup audit..." -ForegroundColor Cyan

$views = [System.Collections.Generic.List[pscustomobject]]::new()
$candidates = [System.Collections.Generic.List[pscustomobject]]::new()
$handlers = [System.Collections.Generic.List[pscustomobject]]::new()
$legacyPatterns = [System.Collections.Generic.List[pscustomobject]]::new()

# Get all XAML files
$xamlFiles = @(Get-ChildItem -LiteralPath $ViewsPath -Filter '*.xaml' -File -ErrorAction SilentlyContinue)

# Get all module/code-behind files
$codeFiles = @()
$codeFiles += @(Get-ChildItem -LiteralPath $ModulesPath -Filter '*.psm1' -File -Recurse -ErrorAction SilentlyContinue)
$codeFiles += @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'Main') -Filter '*.ps1' -File -ErrorAction SilentlyContinue)

# Build code content index for reference checking
$codeContent = @{}
foreach ($codeFile in $codeFiles) {
    $codeContent[$codeFile.Name] = Get-Content -LiteralPath $codeFile.FullName -Raw -ErrorAction SilentlyContinue
}

$allCodeText = ($codeContent.Values -join "`n")

Write-Host ("  Found {0} XAML files, {1} code files" -f $xamlFiles.Count, $codeFiles.Count) -ForegroundColor Cyan

foreach ($xamlFile in $xamlFiles) {
    Write-Host ("  Analyzing: {0}" -f $xamlFile.Name) -ForegroundColor Cyan

    $xamlContent = Get-Content -LiteralPath $xamlFile.FullName -Raw -ErrorAction SilentlyContinue
    if (-not $xamlContent) { continue }

    $viewInfo = [pscustomobject]@{
        FileName      = $xamlFile.Name
        Path          = $xamlFile.FullName
        NamedElements = [System.Collections.Generic.List[pscustomobject]]::new()
        EventHandlers = [System.Collections.Generic.List[pscustomobject]]::new()
        CommentedOut  = [System.Collections.Generic.List[string]]::new()
    }

    # Extract x:Name attributes
    $nameMatches = [regex]::Matches($xamlContent, 'x:Name="([^"]+)"')
    foreach ($match in $nameMatches) {
        $elementName = $match.Groups[1].Value

        # Check if referenced in code
        $isReferenced = $allCodeText -match [regex]::Escape($elementName)

        $elementInfo = [pscustomobject]@{
            Name         = $elementName
            IsReferenced = $isReferenced
            View         = $xamlFile.Name
        }

        $viewInfo.NamedElements.Add($elementInfo)

        if (-not $isReferenced) {
            $candidates.Add([pscustomobject]@{
                Type    = 'UnreferencedElement'
                Name    = $elementName
                View    = $xamlFile.Name
                Message = "Element '$elementName' has x:Name but no code references found"
            })
        }
    }

    # Extract event handlers (Click, SelectionChanged, etc.)
    $handlerMatches = [regex]::Matches($xamlContent, '(Click|SelectionChanged|Loaded|TextChanged|Checked|Unchecked|MouseDoubleClick|PreviewKeyDown|KeyDown)="([^"]+)"')
    foreach ($match in $handlerMatches) {
        $eventType = $match.Groups[1].Value
        $handlerName = $match.Groups[2].Value

        # Check if handler exists in code
        $handlerExists = $allCodeText -match "function\s+$handlerName|$handlerName\s*="

        $handlerInfo = [pscustomobject]@{
            Event        = $eventType
            Handler      = $handlerName
            Exists       = $handlerExists
            View         = $xamlFile.Name
        }

        $viewInfo.EventHandlers.Add($handlerInfo)
        $handlers.Add($handlerInfo)

        if (-not $handlerExists) {
            $candidates.Add([pscustomobject]@{
                Type    = 'MissingHandler'
                Name    = $handlerName
                View    = $xamlFile.Name
                Event   = $eventType
                Message = "Handler '$handlerName' for $eventType event not found in code"
            })
        }
    }

    # Check for commented controls
    if ($IncludeCommented) {
        $commentMatches = [regex]::Matches($xamlContent, '<!--[\s\S]*?-->')
        foreach ($comment in $commentMatches) {
            $commentText = $comment.Value
            if ($commentText -match '<(Button|TextBox|DataGrid|ComboBox|CheckBox|ListView|TabItem)') {
                $viewInfo.CommentedOut.Add($commentText.Substring(0, [math]::Min(100, $commentText.Length)) + '...')
            }
        }
    }

    # Check for legacy naming patterns
    $legacyPatternChecks = @(
        @{ Pattern = '_btn$|btn_'; Description = 'Hungarian notation button naming' }
        @{ Pattern = '_txt$|txt_'; Description = 'Hungarian notation textbox naming' }
        @{ Pattern = '_lbl$|lbl_'; Description = 'Hungarian notation label naming' }
        @{ Pattern = 'OLD|LEGACY|DEPRECATED|TODO.*remove'; Description = 'Legacy/deprecated markers' }
    )

    foreach ($check in $legacyPatternChecks) {
        if ($xamlContent -match $check.Pattern) {
            $legacyPatterns.Add([pscustomobject]@{
                View        = $xamlFile.Name
                Pattern     = $check.Pattern
                Description = $check.Description
            })
        }
    }

    $views.Add($viewInfo)
}

# Check Compare/Templates specific legacy flows
$compareView = $xamlFiles | Where-Object { $_.Name -eq 'CompareView.xaml' }
$templatesView = $xamlFiles | Where-Object { $_.Name -eq 'TemplatesView.xaml' }

$legacyFlowCandidates = [System.Collections.Generic.List[pscustomobject]]::new()

if ($compareView) {
    $compareContent = Get-Content -LiteralPath $compareView.FullName -Raw
    # Check for legacy diff patterns
    if ($compareContent -match 'OldDiff|LegacyCompare|DeprecatedDiff') {
        $legacyFlowCandidates.Add([pscustomobject]@{
            View    = 'CompareView.xaml'
            Type    = 'LegacyDiffFlow'
            Message = 'Contains legacy diff patterns that may be removable'
        })
    }
}

if ($templatesView) {
    $templatesContent = Get-Content -LiteralPath $templatesView.FullName -Raw
    # Check for legacy template patterns
    if ($templatesContent -match 'OldTemplate|LegacyTemplate|DeprecatedTemplate') {
        $legacyFlowCandidates.Add([pscustomobject]@{
            View    = 'TemplatesView.xaml'
            Type    = 'LegacyTemplateFlow'
            Message = 'Contains legacy template patterns that may be removable'
        })
    }
}

# Build result
$result = [pscustomobject]@{
    Timestamp           = Get-Date -Format 'o'
    ViewsAnalyzed       = $views.Count
    TotalNamedElements  = ($views | ForEach-Object { $_.NamedElements.Count } | Measure-Object -Sum).Sum
    TotalEventHandlers  = $handlers.Count
    CandidateCount      = $candidates.Count
    LegacyPatternCount  = $legacyPatterns.Count
    Views               = $views
    CleanupCandidates   = $candidates
    LegacyPatterns      = $legacyPatterns
    LegacyFlowCandidates = $legacyFlowCandidates
    Summary             = [pscustomobject]@{
        UnreferencedElements = @($candidates | Where-Object { $_.Type -eq 'UnreferencedElement' }).Count
        MissingHandlers      = @($candidates | Where-Object { $_.Type -eq 'MissingHandler' }).Count
    }
}

# Output
if ($OutputPath) {
    $outputDir = Split-Path -Path $OutputPath -Parent
    if ($outputDir -and -not (Test-Path -LiteralPath $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }
    $result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
    Write-Host ("`nReport written to: {0}" -f $OutputPath) -ForegroundColor Green
}

# Display summary
Write-Host "`nUI Cleanup Audit Summary:" -ForegroundColor Cyan
Write-Host ("  Views analyzed: {0}" -f $views.Count)
Write-Host ("  Named elements: {0}" -f $result.TotalNamedElements)
Write-Host ("  Event handlers: {0}" -f $result.TotalEventHandlers)

if ($candidates.Count -gt 0) {
    Write-Host ("`nCleanup Candidates: {0}" -f $candidates.Count) -ForegroundColor Yellow
    Write-Host ("  - Unreferenced elements: {0}" -f $result.Summary.UnreferencedElements)
    Write-Host ("  - Missing handlers: {0}" -f $result.Summary.MissingHandlers)

    Write-Host "`n  Top candidates:" -ForegroundColor Yellow
    $topCandidates = $candidates | Select-Object -First 10
    foreach ($candidate in $topCandidates) {
        Write-Host ("    [{0}] {1} in {2}" -f $candidate.Type, $candidate.Name, $candidate.View) -ForegroundColor Yellow
    }
}

if ($legacyPatterns.Count -gt 0) {
    Write-Host ("`nLegacy Patterns Found: {0}" -f $legacyPatterns.Count) -ForegroundColor Yellow
    foreach ($pattern in ($legacyPatterns | Select-Object -First 5)) {
        Write-Host ("    - {0}: {1}" -f $pattern.View, $pattern.Description) -ForegroundColor Yellow
    }
}

if ($legacyFlowCandidates.Count -gt 0) {
    Write-Host ("`nLegacy Flow Candidates:" -f $legacyFlowCandidates.Count) -ForegroundColor Yellow
    foreach ($flow in $legacyFlowCandidates) {
        Write-Host ("    - {0}: {1}" -f $flow.View, $flow.Message) -ForegroundColor Yellow
    }
}

if ($candidates.Count -eq 0 -and $legacyPatterns.Count -eq 0) {
    Write-Host "`nStatus: CLEAN - No obvious cleanup candidates found" -ForegroundColor Green
}
else {
    Write-Host "`nStatus: REVIEW REQUIRED - Manual verification needed before removal" -ForegroundColor Yellow
}

if ($PassThru) {
    return $result
}
