<#
.SYNOPSIS
Reports functions that appear unused across Modules, Tools, and other code roots.

.DESCRIPTION
Parses function definitions from module/tool scripts, searches the repository for references,
and outputs a list of candidates with zero references beyond their definitions. Intended to
support Plan S deprecation cleanup by flagging removable code paths before manual review.

.PARAMETER Root
Repository root; defaults to the parent of this script.

.PARAMETER ModulesPath
Path to module definitions (default: <Root>\Modules).

.PARAMETER ToolsPath
Path to tooling scripts (default: <Root>\Tools).

.PARAMETER MainPath
Path to UI shell scripts (default: <Root>\Main).

.PARAMETER AdditionalSearchRoots
Extra directories to include when searching for references.

.PARAMETER Allowlist
Function names to exclude from unused checks (for intentionally exported entrypoints).

.PARAMETER OutputPath
Optional path to write the full report as JSON.

.PARAMETER FailOnUnused
If set, exits with code 2 when unused candidates are found.

.PARAMETER IncludeTests
If set, includes test folders when parsing definitions and searching for references.
#>
param(
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string]$ModulesPath,
    [string]$ToolsPath,
    [string]$MainPath,
    [string[]]$AdditionalSearchRoots,
    [string[]]$Allowlist,
    [string]$OutputPath,
    [switch]$FailOnUnused,
    [switch]$IncludeTests
)

Set-StrictMode -Version Latest
function Resolve-ExistingPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    try {
        return (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    } catch {
        Write-Warning "Path not found: $Path"
        return $null
    }
}

$resolvedRoot = Resolve-ExistingPath -Path $Root
if (-not $resolvedRoot) {
    throw "Repository root could not be resolved."
}

$ModulesPath = Resolve-ExistingPath -Path $(if ($ModulesPath) { $ModulesPath } else { Join-Path $resolvedRoot 'Modules' })
$ToolsPath   = Resolve-ExistingPath -Path $(if ($ToolsPath)   { $ToolsPath }   else { Join-Path $resolvedRoot 'Tools' })
$MainPath    = Resolve-ExistingPath -Path $(if ($MainPath)    { $MainPath }    else { Join-Path $resolvedRoot 'Main' })

if (-not $AdditionalSearchRoots) { $AdditionalSearchRoots = @() }
if (-not $Allowlist) { $Allowlist = @() }

$definitionRoots = @($ModulesPath, $ToolsPath, $MainPath) + $AdditionalSearchRoots
$definitionRoots = $definitionRoots | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique
if (-not $definitionRoots) {
    throw "No definition roots found. Check the provided paths."
}

$searchRoots = @($resolvedRoot) + $AdditionalSearchRoots
$searchRoots = $searchRoots | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique

$rgCommand = Get-Command rg -ErrorAction SilentlyContinue

function Get-FunctionDefinitions {
    param([string[]]$Roots, [switch]$IncludeTests)

    $definitionFiles = foreach ($root in $Roots) {
        if (-not $root) { continue }
        Get-ChildItem -Path $root -Recurse -File -Include *.ps1, *.psm1 -ErrorAction SilentlyContinue |
            Where-Object {
                $IncludeTests -or ($_.FullName -notmatch '\\Tests\\')
            }
    }

    $definitions = @()
    foreach ($file in $definitionFiles) {
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
        if ($errors -and $errors.Count -gt 0) {
            Write-Warning ("Skipping {0} due to parse errors: {1}" -f $file.FullName, ($errors | Select-Object -First 1).Message)
            continue
        }

        $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) |
            ForEach-Object {
                $definitions += [pscustomobject]@{
                    Name             = $_.Name
                    Path             = $file.FullName
                    DefinitionLine   = $_.Extent.StartLineNumber
                    DefinitionColumn = $_.Extent.StartColumnNumber
                }
            }
    }

    $definitions | Sort-Object Name, Path
}

function New-PatternForName {
    param([string]$Name)
    $escaped = [regex]::Escape($Name)
    "(?<![A-Za-z0-9_-])$escaped(?![A-Za-z0-9_-])"
}

function Get-ReferenceHits {
    param(
        [string]$Pattern,
        [string[]]$Roots,
        [string[]]$DefinitionPaths,
        [int]$DefinitionLine
    )

    $hits = @()
    if ($rgCommand) {
        $args = @('--json', '--pcre2', '-g', '*.ps1', '-g', '*.psm1', '-g', '*.psd1', '-g', '*.xaml', $Pattern) + $Roots
        $rgOutput = & $rgCommand @args 2>$null

        if ($LASTEXITCODE -lt 2 -and $rgOutput) {
            foreach ($line in $rgOutput) {
                if (-not $line) { continue }
                $event = $null
                try { $event = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
                if ($event.type -ne 'match') { continue }
                $hitPath = $event.data.path.text
                $lineNumber = $event.data.line_number
                $hits += [pscustomobject]@{
                    Path       = $hitPath
                    LineNumber = $lineNumber
                    Line       = $event.data.lines.text.Trim()
                    IsDefinition = ($DefinitionPaths -contains $hitPath) -and ($lineNumber -eq $DefinitionLine)
                }
            }
        }
    } else {
        $filesToSearch = foreach ($root in $Roots) {
            Get-ChildItem -Path $root -Recurse -File -Include *.ps1, *.psm1, *.psd1, *.xaml -ErrorAction SilentlyContinue |
                Where-Object {
                    $IncludeTests -or ($_.FullName -notmatch '\\Tests\\')
                }
        }

        if ($filesToSearch) {
            $matches = Select-String -Path ($filesToSearch.FullName) -Pattern $Pattern -SimpleMatch:$false -ErrorAction SilentlyContinue
            foreach ($match in $matches) {
                $hits += [pscustomobject]@{
                    Path         = $match.Path
                    LineNumber   = $match.LineNumber
                    Line         = $match.Line.Trim()
                    IsDefinition = ($DefinitionPaths -contains $match.Path) -and ($match.LineNumber -eq $DefinitionLine)
                }
            }
        }
    }

    if (-not $hits) { $hits = @() }
    $hits
}

$functionDefinitions = Get-FunctionDefinitions -Roots $definitionRoots -IncludeTests:$IncludeTests
if (-not $functionDefinitions) {
    Write-Output "No function definitions found under provided roots."
    return
}

$report = @()
foreach ($group in $functionDefinitions | Group-Object Name) {
    foreach ($definition in $group.Group) {
        $pattern = New-PatternForName -Name $definition.Name
        $definitionPaths = $group.Group.Path
        $hits = Get-ReferenceHits -Pattern $pattern -Roots $searchRoots -DefinitionPaths $definitionPaths -DefinitionLine $definition.DefinitionLine
        if (-not $hits) { $hits = @() }
        $referenceHits = @($hits | Where-Object { -not $_.IsDefinition })

        $report += [pscustomobject]@{
            Name             = $definition.Name
            DefinedIn        = $definition.Path
            DefinitionLine   = $definition.DefinitionLine
            ReferenceCount   = $referenceHits.Count
            SampleReferences = ($referenceHits | Select-Object -First 5 | ForEach-Object { "{0}:{1}" -f $_.Path, $_.LineNumber })
            Allowlisted      = $Allowlist -contains $definition.Name
        }
    }
}

$unused = @($report | Where-Object { -not $_.Allowlisted -and $_.ReferenceCount -le 0 })

Write-Host ("Scanned {0} functions across {1} roots." -f $report.Count, $definitionRoots.Count)
Write-Host ("Unused candidates (excluding allowlist): {0}" -f $unused.Count)

if ($unused) {
    $unused | Select-Object Name, DefinedIn, ReferenceCount, SampleReferences | Format-Table -AutoSize
}

if ($OutputPath) {
    try {
        $report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
        Write-Host ("Full report written to {0}" -f $OutputPath)
    } catch {
        Write-Warning ("Failed to write report to {0}: {1}" -f $OutputPath, $_.Exception.Message)
    }
}

if ($FailOnUnused -and $unused.Count -gt 0) {
    exit 2
}
