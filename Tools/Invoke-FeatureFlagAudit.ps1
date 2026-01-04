<#
.SYNOPSIS
Audits feature flags and configuration toggles across the StateTrace codebase.

.DESCRIPTION
ST-S-002: Enumerates feature flags from:
- Environment variables (STATETRACE_*)
- StateTraceSettings.json keys
- Script parameters that act as toggles

Outputs a report of all discovered flags with their locations, purposes, and deprecation status.

.PARAMETER RepositoryRoot
Repository root path. Defaults to parent of script directory.

.PARAMETER SettingsPath
Path to StateTraceSettings.json. Defaults to Data/StateTraceSettings.json.

.PARAMETER OutputPath
Optional JSON output path. If not specified, writes to Logs/Reports/FeatureFlagAudit-<timestamp>.json.

.PARAMETER PassThru
Return the audit result as an object.

.PARAMETER DeprecatedFlags
Array of flag names marked as deprecated. These will be flagged in the report.

.PARAMETER FailOnDeprecated
Exit with error code if deprecated flags are found in use.
#>
param(
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string]$SettingsPath,
    [string]$OutputPath,
    [switch]$PassThru,
    [string[]]$DeprecatedFlags = @(),
    [switch]$FailOnDeprecated
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
if (-not $SettingsPath) {
    $SettingsPath = Join-Path $repoRoot 'Data\StateTraceSettings.json'
}

$flags = [System.Collections.Generic.List[pscustomobject]]::new()

# 1. Scan for STATETRACE_* environment variables in code
Write-Host "Scanning for environment variable flags..." -ForegroundColor Cyan
$envVarPattern = '\$env:STATETRACE_[A-Z_]+'
$scriptExtensions = @('*.ps1', '*.psm1')

$envVarHits = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[string]]]::new()

foreach ($ext in $scriptExtensions) {
    $files = Get-ChildItem -LiteralPath $repoRoot -Recurse -Filter $ext -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\\.git\\' }

    foreach ($file in $files) {
        $content = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
        if (-not $content) { continue }

        $matches = [regex]::Matches($content, $envVarPattern)
        foreach ($match in $matches) {
            $varName = $match.Value -replace '\$env:', ''
            if (-not $envVarHits.ContainsKey($varName)) {
                $envVarHits[$varName] = [System.Collections.Generic.List[string]]::new()
            }
            $relativePath = $file.FullName.Substring($repoRoot.Length).TrimStart('\', '/')
            if (-not $envVarHits[$varName].Contains($relativePath)) {
                $envVarHits[$varName].Add($relativePath)
            }
        }
    }
}

foreach ($varName in $envVarHits.Keys) {
    $purpose = switch -Wildcard ($varName) {
        '*ALLOW_NET*' { 'Enables network access for online mode' }
        '*ALLOW_INSTALL*' { 'Enables package installation' }
        '*ALLOW_NETWORK_CAPTURE*' { 'Enables network device capture' }
        '*TELEMETRY_DIR*' { 'Overrides telemetry output directory' }
        '*SHARED_CACHE_SNAPSHOT*' { 'Path to shared cache snapshot for import' }
        '*DISABLE_SHARED_CACHE*' { 'Disables shared cache functionality' }
        '*SKIP_WARM_RUN*' { 'Skips warm run telemetry main block' }
        '*SITE_EXISTING_ROW*' { 'Path to site existing row cache snapshot' }
        '*SKIP_SITECACHE_UPDATE*' { 'Skips site cache update operations' }
        default { 'Environment toggle' }
    }

    $flags.Add([pscustomobject]@{
        Name        = $varName
        Type        = 'EnvironmentVariable'
        Purpose     = $purpose
        Locations   = ($envVarHits[$varName] -join '; ')
        LocationCount = $envVarHits[$varName].Count
        Deprecated  = $DeprecatedFlags -contains $varName
    })
}

# 2. Scan StateTraceSettings.json keys
Write-Host "Scanning StateTraceSettings.json..." -ForegroundColor Cyan
if (Test-Path -LiteralPath $SettingsPath) {
    try {
        $settings = Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json

        function Get-SettingsKeys {
            param($Obj, [string]$Prefix = '')

            $keys = [System.Collections.Generic.List[pscustomobject]]::new()
            if ($null -eq $Obj) { return $keys }

            foreach ($prop in $Obj.PSObject.Properties) {
                $fullKey = if ($Prefix) { "$Prefix.$($prop.Name)" } else { $prop.Name }

                if ($prop.Value -is [PSCustomObject]) {
                    $nestedKeys = Get-SettingsKeys -Obj $prop.Value -Prefix $fullKey
                    foreach ($nk in $nestedKeys) { $keys.Add($nk) }
                } else {
                    $valueType = if ($prop.Value -is [bool]) { 'Boolean' }
                                 elseif ($prop.Value -is [int]) { 'Integer' }
                                 elseif ($prop.Value -is [string]) { 'String' }
                                 else { 'Other' }

                    $keys.Add([pscustomobject]@{
                        Key       = $fullKey
                        Value     = $prop.Value
                        ValueType = $valueType
                    })
                }
            }
            $keys
        }

        $settingsKeys = Get-SettingsKeys -Obj $settings
        foreach ($key in $settingsKeys) {
            $purpose = switch -Wildcard ($key.Key) {
                '*DebugOnNextLaunch*' { 'Enables debug mode on next application launch' }
                '*AutoScaleConcurrency*' { 'Enables automatic concurrency scaling for parser' }
                '*MaxRunspaceCeiling*' { 'Maximum runspace ceiling (0 = default)' }
                '*MaxWorkersPerSite*' { 'Maximum workers per site (0 = default)' }
                '*MaxActiveSites*' { 'Maximum active sites (0 = default)' }
                '*MinRunspaceCount*' { 'Minimum runspace count' }
                '*JobsPerThread*' { 'Jobs per thread (0 = default)' }
                '*EnableAdaptiveThreads*' { 'Enables adaptive thread management' }
                '*SkipSiteCacheUpdate*' { 'Skips site cache update operations' }
                default { 'Settings toggle' }
            }

            $flags.Add([pscustomobject]@{
                Name        = $key.Key
                Type        = 'SettingsJson'
                Purpose     = $purpose
                CurrentValue = $key.Value
                ValueType   = $key.ValueType
                Locations   = (Split-Path -Leaf $SettingsPath)
                LocationCount = 1
                Deprecated  = $DeprecatedFlags -contains $key.Key
            })
        }
    } catch {
        Write-Warning "Failed to parse settings file: $($_.Exception.Message)"
    }
} else {
    Write-Warning "Settings file not found at $SettingsPath"
}

# 3. Scan for common toggle parameter patterns
Write-Host "Scanning for script toggle parameters..." -ForegroundColor Cyan
$togglePatterns = @(
    '\[switch\]\$Skip[A-Z][A-Za-z]+',
    '\[switch\]\$Disable[A-Z][A-Za-z]+',
    '\[switch\]\$Enable[A-Z][A-Za-z]+',
    '\[switch\]\$Force[A-Z][A-Za-z]+'
)

$toggleHits = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[string]]]::new()

foreach ($ext in $scriptExtensions) {
    $files = Get-ChildItem -LiteralPath (Join-Path $repoRoot 'Tools') -Filter $ext -File -ErrorAction SilentlyContinue
    $files += Get-ChildItem -LiteralPath (Join-Path $repoRoot 'Modules') -Filter $ext -File -ErrorAction SilentlyContinue

    foreach ($file in $files) {
        $content = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
        if (-not $content) { continue }

        foreach ($pattern in $togglePatterns) {
            $matches = [regex]::Matches($content, $pattern)
            foreach ($match in $matches) {
                $paramName = $match.Value -replace '\[switch\]\$', ''
                if (-not $toggleHits.ContainsKey($paramName)) {
                    $toggleHits[$paramName] = [System.Collections.Generic.List[string]]::new()
                }
                $relativePath = $file.FullName.Substring($repoRoot.Length).TrimStart('\', '/')
                if (-not $toggleHits[$paramName].Contains($relativePath)) {
                    $toggleHits[$paramName].Add($relativePath)
                }
            }
        }
    }
}

foreach ($paramName in $toggleHits.Keys) {
    $flags.Add([pscustomobject]@{
        Name        = $paramName
        Type        = 'SwitchParameter'
        Purpose     = 'Script toggle parameter'
        Locations   = ($toggleHits[$paramName] -join '; ')
        LocationCount = $toggleHits[$paramName].Count
        Deprecated  = $DeprecatedFlags -contains $paramName
    })
}

# Build summary
$summary = [pscustomobject]@{
    Timestamp       = Get-Date -Format 'o'
    TotalFlags      = $flags.Count
    EnvironmentVars = @($flags | Where-Object { $_.Type -eq 'EnvironmentVariable' }).Count
    SettingsKeys    = @($flags | Where-Object { $_.Type -eq 'SettingsJson' }).Count
    SwitchParams    = @($flags | Where-Object { $_.Type -eq 'SwitchParameter' }).Count
    DeprecatedCount = @($flags | Where-Object { $_.Deprecated }).Count
    DeprecatedFlags = $DeprecatedFlags
}

$report = [pscustomobject]@{
    Summary = $summary
    Flags   = $flags
}

# Output
if (-not $OutputPath) {
    $reportDir = Join-Path $repoRoot 'Logs\Reports'
    if (-not (Test-Path -LiteralPath $reportDir)) {
        New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
    }
    $OutputPath = Join-Path $reportDir ("FeatureFlagAudit-{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
}

$outputDir = Split-Path -Path $OutputPath -Parent
if ($outputDir -and -not (Test-Path -LiteralPath $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
Write-Host ("Feature flag audit written to: {0}" -f $OutputPath) -ForegroundColor Green

# Display summary
Write-Host "`nFeature Flag Audit Summary:" -ForegroundColor Cyan
Write-Host ("  Total flags found: {0}" -f $summary.TotalFlags)
Write-Host ("  Environment variables: {0}" -f $summary.EnvironmentVars)
Write-Host ("  Settings keys: {0}" -f $summary.SettingsKeys)
Write-Host ("  Switch parameters: {0}" -f $summary.SwitchParams)

if ($summary.DeprecatedCount -gt 0) {
    Write-Host ("  Deprecated flags in use: {0}" -f $summary.DeprecatedCount) -ForegroundColor Yellow
    $deprecatedInUse = $flags | Where-Object { $_.Deprecated }
    foreach ($dep in $deprecatedInUse) {
        Write-Host ("    - {0} ({1})" -f $dep.Name, $dep.Type) -ForegroundColor Yellow
    }
}

if ($FailOnDeprecated -and $summary.DeprecatedCount -gt 0) {
    Write-Error "Deprecated flags found in use. See report for details."
    exit 2
}

if ($PassThru) {
    return $report
}
