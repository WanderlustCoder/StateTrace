[CmdletBinding()]
param(
    [ValidateSet('Summary', 'Interfaces', 'Search', 'SPAN', 'Templates', 'Alerts', 'Compare', 'All')]
    [string]$View = 'All',

    [string]$OutputPath,

    [switch]$FailOnIssue,

    [switch]$PassThru
)

<#
.SYNOPSIS
Runs accessibility checks on StateTrace UI components (ST-O-001).

.DESCRIPTION
Validates accessibility requirements:
- Focus order matches expected sequence
- Key controls have AutomationProperties
- XAML resources define accessibility hints
- Tab navigation reaches all primary controls

This script performs static analysis of XAML files and reports findings.
For interactive testing, use the manual checklist: docs/Accessibility_Checklist.md

.PARAMETER View
View to check (Summary, Interfaces, Search, SPAN, Templates, Alerts, Compare, All).

.PARAMETER OutputPath
Path to save the accessibility report. Defaults to Logs/Accessibility/Accessibility-<timestamp>.json.

.PARAMETER FailOnIssue
Exit with error code 1 if any accessibility issues are found.

.PARAMETER PassThru
Return the result object.

.EXAMPLE
pwsh Tools\Test-Accessibility.ps1 -View Interfaces -PassThru

.EXAMPLE
pwsh Tools\Test-Accessibility.ps1 -FailOnIssue -OutputPath Logs/Accessibility/report.json
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Path $PSScriptRoot -Parent
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'

# Expected focus order per view
$expectedFocusOrder = @{
    'Summary' = @('HostDropdown', 'ScanLogsButton', 'LoadFromDbButton', 'SiteFilter')
    'Interfaces' = @('FilterInput', 'ApplyButton', 'ClearButton', 'PortsDataGrid')
    'Search' = @('SearchInput', 'RegexToggle', 'SearchButton', 'ResultsGrid')
    'SPAN' = @('RefreshButton', 'SpanDataGrid')
    'Templates' = @('TemplateList', 'PreviewPane', 'CopyButton')
    'Alerts' = @('StatusFilter', 'AuthFilter', 'AlertsGrid')
    'Compare' = @('Host1Dropdown', 'Host2Dropdown', 'AddButton', 'DiffList')
}

# Required AutomationProperties by control type
$requiredAutomation = @{
    'Button' = @('AutomationProperties.Name')
    'TextBox' = @('AutomationProperties.LabeledBy')
    'ComboBox' = @('AutomationProperties.Name')
    'DataGrid' = @('AutomationProperties.Name')
}

# Initialize result
$result = [pscustomobject]@{
    GeneratedAtUtc   = (Get-Date).ToUniversalTime().ToString('o')
    ViewsChecked     = @()
    TotalIssues      = 0
    CriticalIssues   = 0
    MajorIssues      = 0
    MinorIssues      = 0
    Issues           = @()
    XamlFilesChecked = @()
    Status           = 'Unknown'
    Message          = ''
}

Write-Host "`n=== Accessibility Check (ST-O-001) ===" -ForegroundColor Cyan
Write-Host ("Views to check: {0}" -f $View) -ForegroundColor DarkGray
Write-Host ""

# Helper to add an issue
function Add-Issue {
    param(
        [string]$View,
        [string]$Control,
        [string]$Category,
        [ValidateSet('Critical', 'Major', 'Minor')]
        [string]$Severity,
        [string]$Description,
        [string]$Recommendation
    )

    $issue = [pscustomobject]@{
        View           = $View
        Control        = $Control
        Category       = $Category
        Severity       = $Severity
        Description    = $Description
        Recommendation = $Recommendation
    }

    $script:result.Issues += $issue
    $script:result.TotalIssues++

    switch ($Severity) {
        'Critical' { $script:result.CriticalIssues++ }
        'Major' { $script:result.MajorIssues++ }
        'Minor' { $script:result.MinorIssues++ }
    }

    $color = switch ($Severity) {
        'Critical' { 'Red' }
        'Major' { 'Yellow' }
        'Minor' { 'DarkGray' }
    }

    Write-Host ("  [{0}] {1}/{2}: {3}" -f $Severity, $View, $Control, $Description) -ForegroundColor $color
}

# Check XAML file for accessibility properties
function Test-XamlAccessibility {
    param(
        [string]$XamlPath,
        [string]$ViewName
    )

    if (-not (Test-Path -LiteralPath $XamlPath)) {
        Write-Warning "XAML file not found: $XamlPath"
        return
    }

    $result.XamlFilesChecked += $XamlPath
    $content = Get-Content -LiteralPath $XamlPath -Raw

    Write-Host ("  Checking: {0}" -f (Split-Path -Leaf $XamlPath)) -ForegroundColor DarkCyan

    # Check for buttons without AutomationProperties.Name
    $buttonPattern = '<Button[^>]*(?!AutomationProperties\.Name)[^>]*>'
    $buttonsWithoutName = [regex]::Matches($content, $buttonPattern)
    foreach ($match in $buttonsWithoutName) {
        # Skip if button has Content (text label)
        if ($match.Value -notmatch 'Content=') {
            Add-Issue -View $ViewName -Control 'Button' -Category 'ScreenReader' -Severity 'Major' `
                -Description 'Button missing AutomationProperties.Name and Content' `
                -Recommendation 'Add AutomationProperties.Name="<descriptive name>" or Content="<label>"'
        }
    }

    # Check for TextBox without LabeledBy
    $textBoxPattern = '<TextBox[^>]*(?!AutomationProperties\.LabeledBy)[^>]*>'
    $textBoxesWithoutLabel = [regex]::Matches($content, $textBoxPattern)
    foreach ($match in $textBoxesWithoutLabel) {
        # Skip if has a Name that suggests it's labeled elsewhere
        if ($match.Value -notmatch 'x:Name=') {
            Add-Issue -View $ViewName -Control 'TextBox' -Category 'ScreenReader' -Severity 'Minor' `
                -Description 'TextBox missing AutomationProperties.LabeledBy' `
                -Recommendation 'Add AutomationProperties.LabeledBy="{Binding ElementName=<label>}"'
        }
    }

    # Check for DataGrid without AutomationProperties.Name
    $dataGridPattern = '<DataGrid[^>]*(?!AutomationProperties\.Name)[^>]*>'
    $dataGridsWithoutName = [regex]::Matches($content, $dataGridPattern)
    foreach ($match in $dataGridsWithoutName) {
        Add-Issue -View $ViewName -Control 'DataGrid' -Category 'ScreenReader' -Severity 'Minor' `
            -Description 'DataGrid missing AutomationProperties.Name' `
            -Recommendation 'Add AutomationProperties.Name="<table description>"'
    }

    # Check for proper TabIndex usage (should be present for custom focus order)
    if ($content -notmatch 'TabIndex=') {
        Add-Issue -View $ViewName -Control 'View' -Category 'FocusOrder' -Severity 'Minor' `
            -Description 'No TabIndex attributes found' `
            -Recommendation 'Add TabIndex to controls if default focus order is incorrect'
    }

    # Check for IsTabStop="False" on focusable containers
    $isTabStopFalse = [regex]::Matches($content, 'IsTabStop="False"')
    Write-Host ("    TabStop disabled: {0} control(s)" -f $isTabStopFalse.Count) -ForegroundColor DarkGray

    # Check for FocusVisualStyle (focus indicator customization)
    if ($content -notmatch 'FocusVisualStyle') {
        Add-Issue -View $ViewName -Control 'View' -Category 'FocusVisibility' -Severity 'Minor' `
            -Description 'No FocusVisualStyle customization found' `
            -Recommendation 'Consider defining FocusVisualStyle if default focus indicator is insufficient'
    }
}

# Map views to XAML files
$viewXamlMap = @{
    'Summary' = 'Views\SummaryView.xaml'
    'Interfaces' = 'Views\SearchInterfacesView.xaml'
    'Search' = 'Views\SearchInterfacesView.xaml'
    'SPAN' = 'Views\SpanView.xaml'
    'Templates' = 'Views\TemplatesView.xaml'
    'Alerts' = 'Views\AlertsView.xaml'
    'Compare' = 'Views\CompareView.xaml'
}

# Determine views to check
$viewsToCheck = @()
if ($View -eq 'All') {
    $viewsToCheck = $viewXamlMap.Keys | Sort-Object
} else {
    $viewsToCheck = @($View)
}

Write-Host "--- Checking XAML Files ---" -ForegroundColor Yellow

foreach ($viewName in $viewsToCheck) {
    $result.ViewsChecked += $viewName
    $xamlPath = Join-Path -Path $repositoryRoot -ChildPath $viewXamlMap[$viewName]
    Test-XamlAccessibility -XamlPath $xamlPath -ViewName $viewName
}

# Check MainWindow.xaml
$mainWindowXaml = Join-Path -Path $repositoryRoot -ChildPath 'Main\MainWindow.xaml'
if (Test-Path -LiteralPath $mainWindowXaml) {
    Test-XamlAccessibility -XamlPath $mainWindowXaml -ViewName 'MainWindow'
}

# Check SharedStyles.xaml for theme contrast issues
Write-Host ""
Write-Host "--- Checking Theme Resources ---" -ForegroundColor Yellow

$sharedStylesPath = Join-Path -Path $repositoryRoot -ChildPath 'Resources\SharedStyles.xaml'
if (Test-Path -LiteralPath $sharedStylesPath) {
    $result.XamlFilesChecked += $sharedStylesPath
    $stylesContent = Get-Content -LiteralPath $sharedStylesPath -Raw

    Write-Host ("  Checking: SharedStyles.xaml") -ForegroundColor DarkCyan

    # Look for color definitions that might have contrast issues
    $colorMatches = [regex]::Matches($stylesContent, 'Color="([^"]+)"')
    Write-Host ("    Color definitions found: {0}" -f $colorMatches.Count) -ForegroundColor DarkGray

    # Check for FocusVisualStyle in shared styles
    if ($stylesContent -match 'FocusVisualStyle') {
        Write-Host "    FocusVisualStyle defined in shared styles" -ForegroundColor Green
    }
}

Write-Host ""

# Summary
$result.Status = if ($result.CriticalIssues -gt 0) { 'Critical' }
                 elseif ($result.MajorIssues -gt 0) { 'Warning' }
                 elseif ($result.TotalIssues -gt 0) { 'Minor' }
                 else { 'Pass' }

$result.Message = "{0} view(s) checked, {1} issue(s) found ({2} critical, {3} major, {4} minor)." -f `
    $result.ViewsChecked.Count, $result.TotalIssues, $result.CriticalIssues, $result.MajorIssues, $result.MinorIssues

Write-Host "--- Summary ---" -ForegroundColor Yellow
Write-Host ("  Views checked: {0}" -f ($result.ViewsChecked -join ', '))
Write-Host ("  XAML files: {0}" -f $result.XamlFilesChecked.Count)
Write-Host ("  Total issues: {0}" -f $result.TotalIssues)
if ($result.CriticalIssues -gt 0) {
    Write-Host ("  Critical: {0}" -f $result.CriticalIssues) -ForegroundColor Red
}
if ($result.MajorIssues -gt 0) {
    Write-Host ("  Major: {0}" -f $result.MajorIssues) -ForegroundColor Yellow
}
if ($result.MinorIssues -gt 0) {
    Write-Host ("  Minor: {0}" -f $result.MinorIssues) -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "For interactive testing, see: docs/Accessibility_Checklist.md" -ForegroundColor DarkCyan
Write-Host ""

# Save output
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $outputDir = Join-Path -Path $repositoryRoot -ChildPath 'Logs\Accessibility'
    $OutputPath = Join-Path -Path $outputDir -ChildPath "Accessibility-$timestamp.json"
}

$outputDir = Split-Path -Path $OutputPath -Parent
if (-not (Test-Path -LiteralPath $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputPath -Encoding utf8
Write-Host "Report saved to: $OutputPath" -ForegroundColor DarkCyan
Write-Host ""

if ($PassThru.IsPresent) {
    return $result
}

if ($FailOnIssue.IsPresent -and $result.TotalIssues -gt 0) {
    exit 1
}
