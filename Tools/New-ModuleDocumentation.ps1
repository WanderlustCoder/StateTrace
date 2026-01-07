<#
.SYNOPSIS
Generates markdown documentation from PowerShell module help.

.DESCRIPTION
Scans all .psm1 files in the Modules directory and generates markdown documentation
from Get-Help output for each exported function.

.PARAMETER OutputPath
Path to write the generated documentation. Defaults to docs/modules/.

.PARAMETER ModulePath
Path to specific module to document. If not specified, documents all modules.

.PARAMETER IncludePrivate
Include private/internal functions (those not exported).

.EXAMPLE
.\New-ModuleDocumentation.ps1

.EXAMPLE
.\New-ModuleDocumentation.ps1 -ModulePath 'Modules\DatabaseModule.psm1' -OutputPath 'docs\api'
#>

[CmdletBinding()]
param(
    [string]$OutputPath,
    [string]$ModulePath,
    [switch]$IncludePrivate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$projectRoot = Split-Path -Parent $PSScriptRoot

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $projectRoot 'docs\modules'
}

function Get-FunctionDocumentation {
    <#
    .SYNOPSIS
    Extracts documentation for a single function.
    #>
    param(
        [string]$FunctionName,
        [string]$ModuleName
    )

    $help = $null
    try {
        $help = Get-Help -Name $FunctionName -Full -ErrorAction SilentlyContinue
    } catch {
        return $null
    }

    if (-not $help -or $help.Name -eq $FunctionName) {
        # Minimal help available
        return [PSCustomObject]@{
            Name = $FunctionName
            Synopsis = ''
            Description = ''
            Parameters = @()
            Examples = @()
            Outputs = ''
            Notes = ''
        }
    }

    $doc = [ordered]@{
        Name = $FunctionName
        Synopsis = ''
        Description = ''
        Parameters = @()
        Examples = @()
        Outputs = ''
        Notes = ''
    }

    # Synopsis
    if ($help.Synopsis) {
        $doc.Synopsis = ($help.Synopsis -replace '\s+', ' ').Trim()
    }

    # Description
    if ($help.Description) {
        $desc = ($help.Description | ForEach-Object { $_.Text }) -join "`n"
        $doc.Description = $desc.Trim()
    }

    # Parameters
    if ($help.Parameters -and $help.Parameters.Parameter) {
        foreach ($param in $help.Parameters.Parameter) {
            $paramDoc = [ordered]@{
                Name = $param.Name
                Type = if ($param.Type) { $param.Type.Name } else { 'object' }
                Required = $param.Required -eq 'true'
                Description = ''
                DefaultValue = $param.DefaultValue
            }

            if ($param.Description) {
                $paramDoc.Description = ($param.Description | ForEach-Object { $_.Text }) -join ' '
            }

            $doc.Parameters += [PSCustomObject]$paramDoc
        }
    }

    # Examples
    if ($help.Examples -and $help.Examples.Example) {
        foreach ($example in $help.Examples.Example) {
            $exDoc = [ordered]@{
                Title = $example.Title -replace '-+\s*EXAMPLE\s*\d+\s*-+', '' -replace '^\s+|\s+$', ''
                Code = $example.Code
                Remarks = if ($example.Remarks) { ($example.Remarks | ForEach-Object { $_.Text }) -join "`n" } else { '' }
            }
            $doc.Examples += [PSCustomObject]$exDoc
        }
    }

    # Outputs
    if ($help.ReturnValues -and $help.ReturnValues.ReturnValue) {
        $outputs = @()
        foreach ($rv in $help.ReturnValues.ReturnValue) {
            if ($rv.Type) { $outputs += $rv.Type.Name }
        }
        $doc.Outputs = $outputs -join ', '
    }

    # Notes
    if ($help.AlertSet -and $help.AlertSet.Alert) {
        $doc.Notes = ($help.AlertSet.Alert | ForEach-Object { $_.Text }) -join "`n"
    }

    return [PSCustomObject]$doc
}

function ConvertTo-Markdown {
    <#
    .SYNOPSIS
    Converts function documentation to markdown format.
    #>
    param(
        [PSCustomObject]$Doc
    )

    $sb = [System.Text.StringBuilder]::new()

    # Function header
    [void]$sb.AppendLine("### $($Doc.Name)")
    [void]$sb.AppendLine()

    # Synopsis
    if ($Doc.Synopsis) {
        [void]$sb.AppendLine($Doc.Synopsis)
        [void]$sb.AppendLine()
    }

    # Description
    if ($Doc.Description) {
        [void]$sb.AppendLine("**Description:**")
        [void]$sb.AppendLine()
        [void]$sb.AppendLine($Doc.Description)
        [void]$sb.AppendLine()
    }

    # Parameters
    if ($Doc.Parameters -and $Doc.Parameters.Count -gt 0) {
        [void]$sb.AppendLine("**Parameters:**")
        [void]$sb.AppendLine()
        [void]$sb.AppendLine("| Name | Type | Required | Description |")
        [void]$sb.AppendLine("|------|------|----------|-------------|")

        foreach ($param in $Doc.Parameters) {
            $req = if ($param.Required) { 'Yes' } else { 'No' }
            $desc = ($param.Description -replace '\|', '\|' -replace '\n', ' ').Trim()
            if ($desc.Length -gt 100) { $desc = $desc.Substring(0, 97) + '...' }
            [void]$sb.AppendLine("| $($param.Name) | $($param.Type) | $req | $desc |")
        }
        [void]$sb.AppendLine()
    }

    # Outputs
    if ($Doc.Outputs) {
        [void]$sb.AppendLine("**Returns:** $($Doc.Outputs)")
        [void]$sb.AppendLine()
    }

    # Examples
    if ($Doc.Examples -and $Doc.Examples.Count -gt 0) {
        [void]$sb.AppendLine("**Examples:**")
        [void]$sb.AppendLine()

        foreach ($example in $Doc.Examples) {
            if ($example.Code) {
                [void]$sb.AppendLine('```powershell')
                [void]$sb.AppendLine($example.Code)
                [void]$sb.AppendLine('```')
                [void]$sb.AppendLine()
            }
        }
    }

    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine()

    return $sb.ToString()
}

function Get-ModuleDocumentation {
    <#
    .SYNOPSIS
    Generates documentation for a single module.
    #>
    param(
        [string]$ModulePath
    )

    $moduleName = [System.IO.Path]::GetFileNameWithoutExtension($ModulePath)

    Write-Host "  Processing $moduleName..." -ForegroundColor Gray

    # Import module temporarily
    try {
        Import-Module $ModulePath -Force -ErrorAction Stop -DisableNameChecking
    } catch {
        Write-Warning "Failed to import $moduleName : $_"
        return $null
    }

    # Get exported functions
    $module = Get-Module -Name $moduleName
    if (-not $module) {
        Write-Warning "Module $moduleName not found after import"
        return $null
    }

    $functions = $module.ExportedFunctions.Keys | Sort-Object

    if ($functions.Count -eq 0) {
        Write-Verbose "No exported functions in $moduleName"
        return $null
    }

    $sb = [System.Text.StringBuilder]::new()

    # Module header
    [void]$sb.AppendLine("# $moduleName")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("**Module:** ``$($module.Path)``")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("**Functions:** $($functions.Count)")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine()

    # Table of contents
    [void]$sb.AppendLine("## Functions")
    [void]$sb.AppendLine()
    foreach ($fn in $functions) {
        [void]$sb.AppendLine("- [$fn](#$($fn.ToLower()))")
    }
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine()

    # Function documentation
    foreach ($fn in $functions) {
        $doc = Get-FunctionDocumentation -FunctionName $fn -ModuleName $moduleName
        if ($doc) {
            $md = ConvertTo-Markdown -Doc $doc
            [void]$sb.Append($md)
        }
    }

    # Footer
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine("*Generated by New-ModuleDocumentation.ps1 on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')*")

    return @{
        ModuleName = $moduleName
        FunctionCount = $functions.Count
        Content = $sb.ToString()
    }
}

# Main execution
Write-Host "StateTrace Module Documentation Generator" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# Ensure output directory exists
if (-not (Test-Path -LiteralPath $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

# Get modules to process
$modules = @()
if (-not [string]::IsNullOrWhiteSpace($ModulePath)) {
    $fullPath = if ([System.IO.Path]::IsPathRooted($ModulePath)) { $ModulePath } else { Join-Path $projectRoot $ModulePath }
    if (Test-Path -LiteralPath $fullPath) {
        $modules = @(Get-Item -LiteralPath $fullPath)
    }
} else {
    $modulesDir = Join-Path $projectRoot 'Modules'
    $modules = Get-ChildItem -Path $modulesDir -Filter '*.psm1' -File | Where-Object { $_.Name -notlike '*.Tests.*' }
}

if ($modules.Count -eq 0) {
    Write-Warning "No modules found to document"
    exit 0
}

Write-Host "Found $($modules.Count) module(s) to document" -ForegroundColor Green

$results = [System.Collections.Generic.List[object]]::new()
$totalFunctions = 0

foreach ($module in $modules) {
    $doc = Get-ModuleDocumentation -ModulePath $module.FullName

    if ($doc) {
        $outputFile = Join-Path $OutputPath "$($doc.ModuleName).md"
        [System.IO.File]::WriteAllText($outputFile, $doc.Content, [System.Text.Encoding]::UTF8)

        $results.Add([PSCustomObject]@{
            Module = $doc.ModuleName
            Functions = $doc.FunctionCount
            OutputFile = $outputFile
        })

        $totalFunctions += $doc.FunctionCount
        Write-Host "    Documented $($doc.FunctionCount) functions -> $outputFile" -ForegroundColor Green
    }
}

# Generate index
$indexPath = Join-Path $OutputPath 'README.md'
$indexSb = [System.Text.StringBuilder]::new()

[void]$indexSb.AppendLine("# StateTrace Module Documentation")
[void]$indexSb.AppendLine()
[void]$indexSb.AppendLine("Auto-generated API documentation for StateTrace PowerShell modules.")
[void]$indexSb.AppendLine()
[void]$indexSb.AppendLine("## Modules")
[void]$indexSb.AppendLine()
[void]$indexSb.AppendLine("| Module | Functions | Documentation |")
[void]$indexSb.AppendLine("|--------|-----------|---------------|")

foreach ($r in $results | Sort-Object -Property Module) {
    $link = "$($r.Module).md"
    [void]$indexSb.AppendLine("| $($r.Module) | $($r.Functions) | [$link]($link) |")
}

[void]$indexSb.AppendLine()
[void]$indexSb.AppendLine("---")
[void]$indexSb.AppendLine("*Generated on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | Total: $($results.Count) modules, $totalFunctions functions*")

[System.IO.File]::WriteAllText($indexPath, $indexSb.ToString(), [System.Text.Encoding]::UTF8)

Write-Host "`n==========================================" -ForegroundColor Cyan
Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "  Modules documented: $($results.Count)"
Write-Host "  Total functions: $totalFunctions"
Write-Host "  Output directory: $OutputPath"
Write-Host "  Index: $indexPath" -ForegroundColor Green
