<#
.SYNOPSIS
Validates WCAG 2.1 AA accessibility compliance for StateTrace XAML views.

.DESCRIPTION
Performs automated accessibility checks including:
- AutomationProperties.Name presence on interactive elements
- Keyboard navigation (TabIndex, IsTabStop)
- Color contrast ratios
- Focus visual styles
- Live region configuration

.PARAMETER XamlPath
Path to a specific XAML file to validate. If not specified, validates all views.

.PARAMETER OutputPath
Optional path to write results JSON.

.PARAMETER Strict
Enable strict mode - fails on warnings.

.EXAMPLE
.\Test-Accessibility.ps1

.EXAMPLE
.\Test-Accessibility.ps1 -XamlPath 'Views\InterfacesView.xaml' -Strict
#>

[CmdletBinding()]
param(
    [string]$XamlPath,
    [string]$OutputPath,
    [switch]$Strict
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Results = [System.Collections.Generic.List[object]]::new()
$script:TotalIssues = 0
$script:TotalWarnings = 0
$script:TotalPassed = 0

function Add-AccessibilityResult {
    param(
        [string]$File,
        [string]$Element,
        [string]$Check,
        [ValidateSet('Pass', 'Fail', 'Warning')]
        [string]$Status,
        [string]$Message,
        [string]$WCAGCriteria
    )

    $result = [PSCustomObject]@{
        File = $File
        Element = $Element
        Check = $Check
        Status = $Status
        Message = $Message
        WCAGCriteria = $WCAGCriteria
        Timestamp = [datetime]::UtcNow.ToString('o')
    }

    $script:Results.Add($result)

    switch ($Status) {
        'Pass' { $script:TotalPassed++ }
        'Fail' { $script:TotalIssues++ }
        'Warning' { $script:TotalWarnings++ }
    }
}

function Test-AutomationProperties {
    <#
    .SYNOPSIS
    Checks that interactive elements have AutomationProperties.Name set.
    #>
    param(
        [string]$XamlContent,
        [string]$FilePath
    )

    $fileName = Split-Path -Leaf $FilePath

    # Interactive elements that should have AutomationProperties.Name
    $interactiveElements = @(
        'Button',
        'ToggleButton',
        'ComboBox',
        'CheckBox',
        'RadioButton',
        'TextBox',
        'PasswordBox',
        'Slider',
        'ListBox',
        'ListView',
        'DataGrid',
        'TreeView',
        'TabControl',
        'TabItem',
        'Menu',
        'MenuItem'
    )

    foreach ($element in $interactiveElements) {
        # Find elements with Name attribute (named controls)
        $pattern = "<$element\s+[^>]*Name\s*=\s*`"([^`"]+)`"[^>]*>"
        $matches = [regex]::Matches($XamlContent, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

        foreach ($match in $matches) {
            $elementName = $match.Groups[1].Value
            $fullMatch = $match.Value

            if ($fullMatch -match 'AutomationProperties\.Name') {
                Add-AccessibilityResult `
                    -File $fileName `
                    -Element "$element[$elementName]" `
                    -Check 'AutomationProperties.Name' `
                    -Status 'Pass' `
                    -Message "Element has AutomationProperties.Name" `
                    -WCAGCriteria '4.1.2'
            } else {
                Add-AccessibilityResult `
                    -File $fileName `
                    -Element "$element[$elementName]" `
                    -Check 'AutomationProperties.Name' `
                    -Status 'Fail' `
                    -Message "Missing AutomationProperties.Name for screen readers" `
                    -WCAGCriteria '4.1.2'
            }
        }
    }
}

function Test-KeyboardNavigation {
    <#
    .SYNOPSIS
    Checks keyboard navigation attributes.
    #>
    param(
        [string]$XamlContent,
        [string]$FilePath
    )

    $fileName = Split-Path -Leaf $FilePath

    # Check for IsTabStop="False" on interactive elements (potential issue)
    $pattern = 'IsTabStop\s*=\s*"False"'
    $matches = [regex]::Matches($XamlContent, $pattern)

    if ($matches.Count -gt 0) {
        Add-AccessibilityResult `
            -File $fileName `
            -Element 'Multiple' `
            -Check 'KeyboardNavigation' `
            -Status 'Warning' `
            -Message "$($matches.Count) elements have IsTabStop=False - verify these are not interactive" `
            -WCAGCriteria '2.1.1'
    } else {
        Add-AccessibilityResult `
            -File $fileName `
            -Element 'Document' `
            -Check 'KeyboardNavigation' `
            -Status 'Pass' `
            -Message "No explicit IsTabStop=False found" `
            -WCAGCriteria '2.1.1'
    }

    # Check for FocusVisualStyle
    if ($XamlContent -match 'FocusVisualStyle') {
        Add-AccessibilityResult `
            -File $fileName `
            -Element 'Document' `
            -Check 'FocusVisualStyle' `
            -Status 'Pass' `
            -Message "Custom focus visual styles defined" `
            -WCAGCriteria '2.4.7'
    }
}

function Test-ColorContrast {
    <#
    .SYNOPSIS
    Checks for potential color contrast issues in theme references.
    #>
    param(
        [string]$XamlContent,
        [string]$FilePath
    )

    $fileName = Split-Path -Leaf $FilePath

    # Check for hardcoded colors (potential accessibility issue)
    $hardcodedColorPattern = '(Foreground|Background|Fill|Stroke)\s*=\s*"#[0-9A-Fa-f]{6}"'
    $matches = [regex]::Matches($XamlContent, $hardcodedColorPattern)

    if ($matches.Count -gt 0) {
        Add-AccessibilityResult `
            -File $fileName `
            -Element 'Multiple' `
            -Check 'ColorContrast' `
            -Status 'Warning' `
            -Message "$($matches.Count) hardcoded colors found - verify contrast ratios meet WCAG 4.5:1" `
            -WCAGCriteria '1.4.3'
    }

    # Check for theme resource usage (good practice)
    $themePattern = '\{DynamicResource Theme\.'
    $themeMatches = [regex]::Matches($XamlContent, $themePattern)

    if ($themeMatches.Count -gt 0) {
        Add-AccessibilityResult `
            -File $fileName `
            -Element 'Document' `
            -Check 'ThemeResources' `
            -Status 'Pass' `
            -Message "$($themeMatches.Count) theme resource references found (supports high-contrast themes)" `
            -WCAGCriteria '1.4.3'
    }
}

function Test-LiveRegions {
    <#
    .SYNOPSIS
    Checks for live region configuration for dynamic content.
    #>
    param(
        [string]$XamlContent,
        [string]$FilePath
    )

    $fileName = Split-Path -Leaf $FilePath

    # Check for AutomationProperties.LiveSetting
    if ($XamlContent -match 'AutomationProperties\.LiveSetting') {
        $politeMatches = [regex]::Matches($XamlContent, 'LiveSetting\s*=\s*"Polite"')
        $assertiveMatches = [regex]::Matches($XamlContent, 'LiveSetting\s*=\s*"Assertive"')

        Add-AccessibilityResult `
            -File $fileName `
            -Element 'Document' `
            -Check 'LiveRegions' `
            -Status 'Pass' `
            -Message "Live regions configured: $($politeMatches.Count) Polite, $($assertiveMatches.Count) Assertive" `
            -WCAGCriteria '4.1.3'
    }
}

function Test-ToolTips {
    <#
    .SYNOPSIS
    Checks that interactive elements have tooltips for additional context.
    #>
    param(
        [string]$XamlContent,
        [string]$FilePath
    )

    $fileName = Split-Path -Leaf $FilePath

    # Count tooltips
    $tooltipMatches = [regex]::Matches($XamlContent, 'ToolTip\s*=\s*"[^"]+"')

    if ($tooltipMatches.Count -gt 0) {
        Add-AccessibilityResult `
            -File $fileName `
            -Element 'Document' `
            -Check 'ToolTips' `
            -Status 'Pass' `
            -Message "$($tooltipMatches.Count) tooltips defined for additional context" `
            -WCAGCriteria '3.3.2'
    }
}

function Test-AcceleratorKeys {
    <#
    .SYNOPSIS
    Checks for keyboard accelerator definitions.
    #>
    param(
        [string]$XamlContent,
        [string]$FilePath
    )

    $fileName = Split-Path -Leaf $FilePath

    # Check for AccessKey (underscore prefix in Content)
    $accessKeyMatches = [regex]::Matches($XamlContent, 'Content\s*=\s*"_[^"]+"')

    # Check for AutomationProperties.AcceleratorKey
    $accelKeyMatches = [regex]::Matches($XamlContent, 'AutomationProperties\.AcceleratorKey')

    $totalKeys = $accessKeyMatches.Count + $accelKeyMatches.Count

    if ($totalKeys -gt 0) {
        Add-AccessibilityResult `
            -File $fileName `
            -Element 'Document' `
            -Check 'AcceleratorKeys' `
            -Status 'Pass' `
            -Message "$totalKeys keyboard shortcuts defined (access keys: $($accessKeyMatches.Count), accelerators: $($accelKeyMatches.Count))" `
            -WCAGCriteria '2.1.4'
    }
}

function Test-XamlFile {
    param([string]$FilePath)

    if (-not (Test-Path -LiteralPath $FilePath)) {
        Write-Warning "File not found: $FilePath"
        return
    }

    Write-Host "  Checking $FilePath..." -ForegroundColor Gray

    try {
        $content = [System.IO.File]::ReadAllText($FilePath, [System.Text.Encoding]::UTF8)

        Test-AutomationProperties -XamlContent $content -FilePath $FilePath
        Test-KeyboardNavigation -XamlContent $content -FilePath $FilePath
        Test-ColorContrast -XamlContent $content -FilePath $FilePath
        Test-LiveRegions -XamlContent $content -FilePath $FilePath
        Test-ToolTips -XamlContent $content -FilePath $FilePath
        Test-AcceleratorKeys -XamlContent $content -FilePath $FilePath

    } catch {
        Write-Warning "Failed to analyze $FilePath : $_"
    }
}

# Main execution
Write-Host "StateTrace Accessibility Validation (WCAG 2.1 AA)" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

$projectRoot = Split-Path -Parent $PSScriptRoot

if (-not [string]::IsNullOrWhiteSpace($XamlPath)) {
    # Single file mode
    $fullPath = if ([System.IO.Path]::IsPathRooted($XamlPath)) { $XamlPath } else { Join-Path $projectRoot $XamlPath }
    Test-XamlFile -FilePath $fullPath
} else {
    # Scan all XAML files
    Write-Host "`nScanning XAML files..." -ForegroundColor Green

    $xamlPaths = @(
        (Join-Path $projectRoot 'Main\MainWindow.xaml'),
        (Join-Path $projectRoot 'Views\*.xaml'),
        (Join-Path $projectRoot 'Resources\*.xaml')
    )

    foreach ($pathPattern in $xamlPaths) {
        $files = Get-ChildItem -Path $pathPattern -ErrorAction SilentlyContinue
        foreach ($file in $files) {
            Test-XamlFile -FilePath $file.FullName
        }
    }
}

# Summary
Write-Host "`n==================================================" -ForegroundColor Cyan
Write-Host "Results Summary" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "  Passed:   $script:TotalPassed" -ForegroundColor Green
Write-Host "  Warnings: $script:TotalWarnings" -ForegroundColor Yellow
Write-Host "  Failed:   $script:TotalIssues" -ForegroundColor Red

# Show failures
$failures = $script:Results | Where-Object { $_.Status -eq 'Fail' }
if ($failures.Count -gt 0) {
    Write-Host "`nFailures:" -ForegroundColor Red
    foreach ($f in $failures) {
        Write-Host "  [$($f.File)] $($f.Element): $($f.Message) (WCAG $($f.WCAGCriteria))" -ForegroundColor Red
    }
}

# Show warnings
$warnings = $script:Results | Where-Object { $_.Status -eq 'Warning' }
if ($warnings.Count -gt 0) {
    Write-Host "`nWarnings:" -ForegroundColor Yellow
    foreach ($w in $warnings) {
        Write-Host "  [$($w.File)] $($w.Element): $($w.Message) (WCAG $($w.WCAGCriteria))" -ForegroundColor Yellow
    }
}

# Save results if requested
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $report = [PSCustomObject]@{
        GeneratedAt = [datetime]::UtcNow.ToString('o')
        TotalPassed = $script:TotalPassed
        TotalWarnings = $script:TotalWarnings
        TotalIssues = $script:TotalIssues
        Results = $script:Results.ToArray()
    }

    $json = $report | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($OutputPath, $json, [System.Text.Encoding]::UTF8)
    Write-Host "`nReport saved to: $OutputPath" -ForegroundColor Green
}

# Exit code
if ($script:TotalIssues -gt 0) {
    Write-Host "`nAccessibility validation FAILED" -ForegroundColor Red
    exit 1
}

if ($Strict.IsPresent -and $script:TotalWarnings -gt 0) {
    Write-Host "`nAccessibility validation FAILED (strict mode - warnings treated as failures)" -ForegroundColor Red
    exit 1
}

Write-Host "`nAccessibility validation PASSED" -ForegroundColor Green
exit 0
