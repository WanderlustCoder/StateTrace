<#
.SYNOPSIS
Generates module import graphs and public contract lists.

.DESCRIPTION
ST-L-001: Analyzes PowerShell modules to generate:
- Import/dependency graphs showing module relationships
- Public function contract lists (exported functions with signatures)
- Cross-module reference analysis

.PARAMETER RepositoryRoot
Repository root path. Defaults to parent of script directory.

.PARAMETER ModulePath
Optional path to a specific module to analyze.

.PARAMETER OutputPath
Path for JSON report.

.PARAMETER GenerateMarkdown
Also generate a markdown summary.

.PARAMETER PassThru
Return results object.

.EXAMPLE
.\Get-ModuleImportGraph.ps1 -PassThru

.EXAMPLE
.\Get-ModuleImportGraph.ps1 -GenerateMarkdown -OutputPath Logs/Reports/ModuleGraph.json
#>
param(
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string]$ModulePath,
    [string]$OutputPath,
    [switch]$GenerateMarkdown,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'

Write-Host "StateTrace Module Import Graph Generator" -ForegroundColor Cyan

# Find module files
$moduleFiles = @()
if ($ModulePath) {
    if (Test-Path -LiteralPath $ModulePath) {
        $moduleFiles = @(Get-Item -LiteralPath $ModulePath)
    }
}
else {
    $modulesDir = Join-Path $repoRoot 'Modules'
    if (Test-Path -LiteralPath $modulesDir) {
        $moduleFiles = Get-ChildItem -LiteralPath $modulesDir -Filter '*.psm1' -File -ErrorAction SilentlyContinue
    }
}

Write-Host ("  Found {0} modules to analyze" -f $moduleFiles.Count) -ForegroundColor Cyan

$modules = [System.Collections.Generic.List[pscustomobject]]::new()
$imports = [System.Collections.Generic.List[pscustomobject]]::new()
$exports = [System.Collections.Generic.List[pscustomobject]]::new()

foreach ($file in $moduleFiles) {
    Write-Host ("`nAnalyzing: {0}" -f $file.Name) -ForegroundColor White

    try {
        $content = Get-Content -LiteralPath $file.FullName -Raw
        $fileSize = $file.Length

        # Extract module imports (Import-Module, using module, dot-sourcing)
        $moduleImports = [System.Collections.Generic.List[string]]::new()

        # Import-Module patterns
        $importMatches = [regex]::Matches($content, 'Import-Module\s+[''"]?([^''";\s]+)[''"]?', 'IgnoreCase')
        foreach ($match in $importMatches) {
            $moduleName = $match.Groups[1].Value
            if ($moduleName -and -not $moduleImports.Contains($moduleName)) {
                $moduleImports.Add($moduleName)
            }
        }

        # using module patterns
        $usingMatches = [regex]::Matches($content, 'using\s+module\s+[''"]?([^''";\s]+)[''"]?', 'IgnoreCase')
        foreach ($match in $usingMatches) {
            $moduleName = $match.Groups[1].Value
            if ($moduleName -and -not $moduleImports.Contains($moduleName)) {
                $moduleImports.Add($moduleName)
            }
        }

        # Dot-source patterns (. .\path\to\file.ps1)
        $dotSourceMatches = [regex]::Matches($content, '\.\s+[''"]?(\$PSScriptRoot[^''";\s]*|\.\\[^''";\s]+\.ps1)[''"]?', 'IgnoreCase')
        foreach ($match in $dotSourceMatches) {
            $sourcePath = $match.Groups[1].Value
            if ($sourcePath -and -not $moduleImports.Contains($sourcePath)) {
                $moduleImports.Add($sourcePath)
            }
        }

        # Extract function definitions
        $functionDefs = [System.Collections.Generic.List[pscustomobject]]::new()
        $funcMatches = [regex]::Matches($content, 'function\s+([A-Za-z][\w-]*)\s*(?:\{|\()', 'IgnoreCase')
        foreach ($match in $funcMatches) {
            $funcName = $match.Groups[1].Value

            # Try to extract parameters
            $paramBlock = $null
            $funcStart = $match.Index
            $afterFunc = $content.Substring($funcStart, [Math]::Min(2000, $content.Length - $funcStart))

            if ($afterFunc -match 'param\s*\(([^)]*)\)') {
                $paramBlock = $Matches[1].Trim()
            }

            $functionDefs.Add([pscustomobject]@{
                Name = $funcName
                Parameters = $paramBlock
                IsExported = $false
            })
        }

        # Check Export-ModuleMember
        $exportedFunctions = [System.Collections.Generic.List[string]]::new()
        $exportMatches = [regex]::Matches($content, 'Export-ModuleMember\s+-Function\s+([^\r\n]+)', 'IgnoreCase')
        foreach ($match in $exportMatches) {
            $exportList = $match.Groups[1].Value
            # Handle @('Func1', 'Func2') or 'Func1', 'Func2' or Func1, Func2
            $funcNames = [regex]::Matches($exportList, "['""]?([A-Za-z][\w-]*)['""]?")
            foreach ($fn in $funcNames) {
                $name = $fn.Groups[1].Value
                if ($name -and -not $exportedFunctions.Contains($name)) {
                    $exportedFunctions.Add($name)
                }
            }
        }

        # Mark exported functions
        foreach ($funcDef in $functionDefs) {
            if ($exportedFunctions.Contains($funcDef.Name)) {
                $funcDef.IsExported = $true
            }
        }

        # If no Export-ModuleMember, assume all are exported
        if ($exportedFunctions.Count -eq 0) {
            foreach ($funcDef in $functionDefs) {
                $funcDef.IsExported = $true
            }
        }

        $exportedCount = @($functionDefs | Where-Object { $_.IsExported }).Count
        $privateCount = @($functionDefs | Where-Object { -not $_.IsExported }).Count

        $moduleInfo = [pscustomobject]@{
            Name           = $file.BaseName
            Path           = $file.FullName
            SizeBytes      = $fileSize
            SizeKB         = [math]::Round($fileSize / 1024, 1)
            ImportCount    = $moduleImports.Count
            Imports        = $moduleImports
            FunctionCount  = $functionDefs.Count
            ExportedCount  = $exportedCount
            PrivateCount   = $privateCount
            Functions      = $functionDefs
        }

        $modules.Add($moduleInfo)

        # Record imports for graph
        foreach ($imp in $moduleImports) {
            $imports.Add([pscustomobject]@{
                Source = $file.BaseName
                Target = $imp
            })
        }

        # Record exports
        foreach ($func in $functionDefs | Where-Object { $_.IsExported }) {
            $exports.Add([pscustomobject]@{
                Module = $file.BaseName
                Function = $func.Name
                Parameters = $func.Parameters
            })
        }

        Write-Host ("  Size: {0:N0} KB | Functions: {1} ({2} exported, {3} private) | Imports: {4}" -f
            $moduleInfo.SizeKB, $moduleInfo.FunctionCount, $exportedCount, $privateCount, $moduleImports.Count) -ForegroundColor Gray
    }
    catch {
        Write-Host ("  Error: {0}" -f $_.Exception.Message) -ForegroundColor Red
    }
}

# Build summary
$totalSize = ($modules | Measure-Object -Property SizeBytes -Sum).Sum
$totalFunctions = ($modules | Measure-Object -Property FunctionCount -Sum).Sum
$totalExported = ($modules | Measure-Object -Property ExportedCount -Sum).Sum

$summary = [pscustomobject]@{
    Timestamp       = Get-Date -Format 'o'
    ModuleCount     = $modules.Count
    TotalSizeKB     = [math]::Round($totalSize / 1024, 1)
    TotalFunctions  = $totalFunctions
    TotalExported   = $totalExported
    ImportEdges     = $imports.Count
    Modules         = $modules
    ImportGraph     = $imports
    PublicContracts = $exports
}

# Output
if (-not $OutputPath) {
    $OutputPath = Join-Path $repoRoot ("Logs\Reports\ModuleImportGraph-{0}.json" -f $timestamp)
}

$outputDir = Split-Path -Path $OutputPath -Parent
if (-not (Test-Path -LiteralPath $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
Write-Host ("`nJSON report: {0}" -f $OutputPath) -ForegroundColor Green

# Generate markdown if requested
if ($GenerateMarkdown) {
    $mdPath = $OutputPath -replace '\.json$', '.md'

    $md = [System.Text.StringBuilder]::new()
    [void]$md.AppendLine("# Module Import Graph & Public Contracts")
    [void]$md.AppendLine("")
    [void]$md.AppendLine("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    [void]$md.AppendLine("")
    [void]$md.AppendLine("## Summary")
    [void]$md.AppendLine("")
    [void]$md.AppendLine("| Metric | Value |")
    [void]$md.AppendLine("|--------|-------|")
    [void]$md.AppendLine("| Modules | $($summary.ModuleCount) |")
    [void]$md.AppendLine("| Total Size | $($summary.TotalSizeKB) KB |")
    [void]$md.AppendLine("| Total Functions | $($summary.TotalFunctions) |")
    [void]$md.AppendLine("| Exported Functions | $($summary.TotalExported) |")
    [void]$md.AppendLine("| Import Edges | $($summary.ImportEdges) |")
    [void]$md.AppendLine("")

    # Module sizes (top 10)
    [void]$md.AppendLine("## Largest Modules")
    [void]$md.AppendLine("")
    [void]$md.AppendLine("| Module | Size (KB) | Functions | Exported |")
    [void]$md.AppendLine("|--------|-----------|-----------|----------|")
    $topModules = $modules | Sort-Object SizeBytes -Descending | Select-Object -First 10
    foreach ($m in $topModules) {
        [void]$md.AppendLine("| $($m.Name) | $($m.SizeKB) | $($m.FunctionCount) | $($m.ExportedCount) |")
    }
    [void]$md.AppendLine("")

    # Import graph
    [void]$md.AppendLine("## Import Graph")
    [void]$md.AppendLine("")
    [void]$md.AppendLine('```')
    foreach ($imp in $imports) {
        [void]$md.AppendLine(('{0} --> {1}' -f $imp.Source, $imp.Target))
    }
    [void]$md.AppendLine('```')
    [void]$md.AppendLine("")

    # Public contracts (top modules)
    [void]$md.AppendLine("## Public Contracts (Top Modules)")
    [void]$md.AppendLine("")

    foreach ($m in $topModules | Select-Object -First 5) {
        [void]$md.AppendLine("### $($m.Name)")
        [void]$md.AppendLine("")
        $modExports = $exports | Where-Object { $_.Module -eq $m.Name }
        if ($modExports) {
            [void]$md.AppendLine("| Function | Parameters |")
            [void]$md.AppendLine("|----------|------------|")
            foreach ($exp in $modExports | Select-Object -First 20) {
                $params = if ($exp.Parameters) { $exp.Parameters.Substring(0, [Math]::Min(50, $exp.Parameters.Length)) + "..." } else { "-" }
                [void]$md.AppendLine("| $($exp.Function) | $params |")
            }
            if (($modExports | Measure-Object).Count -gt 20) {
                [void]$md.AppendLine("| ... | $(($modExports | Measure-Object).Count - 20) more |")
            }
        }
        [void]$md.AppendLine("")
    }

    $md.ToString() | Set-Content -LiteralPath $mdPath -Encoding UTF8
    Write-Host ("Markdown report: {0}" -f $mdPath) -ForegroundColor Green
}

# Display summary
Write-Host "`nModule Import Graph Summary:" -ForegroundColor Cyan
Write-Host ("  Modules: {0}" -f $summary.ModuleCount)
Write-Host ("  Total size: {0:N0} KB" -f $summary.TotalSizeKB)
Write-Host ("  Functions: {0} ({1} exported)" -f $summary.TotalFunctions, $summary.TotalExported)
Write-Host ("  Import edges: {0}" -f $summary.ImportEdges)

# Show largest modules
Write-Host "`nLargest modules:" -ForegroundColor Cyan
$topModules = $modules | Sort-Object SizeBytes -Descending | Select-Object -First 5
foreach ($m in $topModules) {
    Write-Host ("  {0}: {1:N0} KB ({2} functions)" -f $m.Name, $m.SizeKB, $m.FunctionCount) -ForegroundColor White
}

if ($PassThru) {
    return $summary
}
