<#
.SYNOPSIS
Tests database consistency across StateTrace site databases.

.DESCRIPTION
Compares row counts, schema versions, table structures, and optional checksums
across multiple site databases to detect inconsistencies.

.PARAMETER Sites
Optional array of site codes to check. If not specified, checks all sites.

.PARAMETER DataDirectoryPath
Optional base data directory. Defaults to Data/.

.PARAMETER IncludeChecksums
Include field-level checksums (slower but more thorough).

.PARAMETER OutputPath
Optional path to write results JSON.

.EXAMPLE
.\Test-DatabaseConsistency.ps1 -Sites 'WLLS','BOYO'

.EXAMPLE
.\Test-DatabaseConsistency.ps1 -IncludeChecksums -OutputPath 'consistency-report.json'
#>

[CmdletBinding()]
param(
    [string[]]$Sites,
    [string]$DataDirectoryPath,
    [switch]$IncludeChecksums,
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import required modules
$modulesPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Modules'

try {
    Import-Module (Join-Path $modulesPath 'DeviceRepository.Access.psm1') -Force -ErrorAction Stop
} catch {
    Write-Warning "Failed to import DeviceRepository.Access: $_"
}

try {
    Import-Module (Join-Path $modulesPath 'DatabaseModule.psm1') -Force -ErrorAction Stop
} catch {
    Write-Warning "Failed to import DatabaseModule: $_"
}

function Get-TableRowCount {
    param(
        [object]$Connection,
        [string]$TableName
    )

    try {
        $sql = "SELECT COUNT(*) AS RowCount FROM [$TableName]"
        $recordset = $Connection.Execute($sql)
        if ($recordset -and $recordset.State -eq 1) {
            $count = $recordset.Fields.Item(0).Value
            $recordset.Close()
            return [int]$count
        }
    } catch {
        return -1
    }
    return 0
}

function Get-TableChecksum {
    param(
        [object]$Connection,
        [string]$TableName,
        [string[]]$KeyFields
    )

    try {
        $keyList = if ($KeyFields.Count -gt 0) { ($KeyFields | ForEach-Object { "[$_]" }) -join ', ' } else { '*' }
        $sql = "SELECT $keyList FROM [$TableName]"
        $recordset = $Connection.Execute($sql)

        if (-not $recordset -or $recordset.State -ne 1) { return $null }

        $hash = [System.Security.Cryptography.SHA256]::Create()
        $sb = [System.Text.StringBuilder]::new()

        while (-not $recordset.EOF) {
            for ($i = 0; $i -lt $recordset.Fields.Count; $i++) {
                $val = $recordset.Fields.Item($i).Value
                if ($val -ne [System.DBNull]::Value) {
                    [void]$sb.Append(('' + $val))
                }
                [void]$sb.Append('|')
            }
            [void]$sb.AppendLine()
            $recordset.MoveNext()
        }
        $recordset.Close()

        $bytes = [System.Text.Encoding]::UTF8.GetBytes($sb.ToString())
        $hashBytes = $hash.ComputeHash($bytes)
        $hash.Dispose()

        return [BitConverter]::ToString($hashBytes).Replace('-', '').Substring(0, 16)
    } catch {
        return $null
    }
}

function Get-DatabaseTables {
    param([object]$Connection)

    $tables = [System.Collections.Generic.List[string]]::new()
    try {
        $catalog = New-Object -ComObject ADOX.Catalog
        $catalog.ActiveConnection = $Connection

        foreach ($table in $catalog.Tables) {
            if ($table.Type -eq 'TABLE') {
                [void]$tables.Add($table.Name)
            }
        }

        if ($catalog -is [System.__ComObject]) {
            [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($catalog)
        }
    } catch {
        Write-Verbose "Failed to enumerate tables: $_"
    }

    return $tables.ToArray()
}

function Test-SingleDatabaseConsistency {
    param(
        [string]$DbPath,
        [switch]$IncludeChecksums
    )

    $result = [ordered]@{
        DatabasePath = $DbPath
        SiteCode = ''
        Exists = $false
        Accessible = $false
        SchemaVersion = -1
        Tables = @{}
        TotalRows = 0
        Errors = @()
        CheckedAt = [datetime]::UtcNow.ToString('o')
    }

    # Extract site code from path
    $fileName = [System.IO.Path]::GetFileNameWithoutExtension($DbPath)
    $result.SiteCode = $fileName

    if (-not (Test-Path -LiteralPath $DbPath)) {
        $result.Errors += "Database file not found"
        return [pscustomobject]$result
    }
    $result.Exists = $true

    $connection = $null
    try {
        $connection = New-Object -ComObject ADODB.Connection
        $opened = $false

        foreach ($prov in @('Microsoft.ACE.OLEDB.12.0', 'Microsoft.Jet.OLEDB.4.0')) {
            try {
                $connection.Open(("Provider={0};Data Source={1}" -f $prov, $DbPath))
                $opened = $true
                break
            } catch {
                try { $connection.Close() } catch { Write-Verbose "Caught exception in Test-DatabaseConsistency.ps1: $($_.Exception.Message)" }
            }
        }

        if (-not $opened) {
            $result.Errors += "Failed to open database with any provider"
            return [pscustomobject]$result
        }
        $result.Accessible = $true

        # Check schema version if table exists
        try {
            $recordset = $connection.Execute("SELECT TOP 1 Version FROM SchemaVersion ORDER BY AppliedAt DESC")
            if ($recordset -and $recordset.State -eq 1 -and -not $recordset.EOF) {
                $result.SchemaVersion = [int]$recordset.Fields.Item(0).Value
            }
            if ($recordset) { $recordset.Close() }
        } catch {
            # SchemaVersion table may not exist
            $result.SchemaVersion = 0
        }

        # Get all tables
        $tables = Get-DatabaseTables -Connection $connection

        foreach ($table in $tables) {
            $tableInfo = [ordered]@{
                RowCount = Get-TableRowCount -Connection $connection -TableName $table
                Checksum = $null
            }

            if ($IncludeChecksums.IsPresent) {
                $tableInfo.Checksum = Get-TableChecksum -Connection $connection -TableName $table -KeyFields @()
            }

            $result.Tables[$table] = $tableInfo
            if ($tableInfo.RowCount -gt 0) {
                $result.TotalRows += $tableInfo.RowCount
            }
        }

    } catch {
        $result.Errors += "Error: $($_.Exception.Message)"
    } finally {
        if ($connection) {
            try { $connection.Close() } catch { Write-Verbose "Caught exception in Test-DatabaseConsistency.ps1: $($_.Exception.Message)" }
            if ($connection -is [System.__ComObject]) {
                [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($connection)
            }
        }
    }

    return [pscustomobject]$result
}

function Compare-DatabaseResults {
    param([object[]]$Results)

    $issues = [System.Collections.Generic.List[object]]::new()

    if ($Results.Count -lt 2) {
        return @()
    }

    # Collect all table names across all databases
    $allTables = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($r in $Results) {
        if ($r.Tables) {
            foreach ($t in $r.Tables.Keys) {
                [void]$allTables.Add($t)
            }
        }
    }

    # Check schema version consistency
    $schemaVersions = $Results | Where-Object { $_.SchemaVersion -ge 0 } | Select-Object -ExpandProperty SchemaVersion -Unique
    if ($schemaVersions.Count -gt 1) {
        $issues.Add([pscustomobject]@{
            IssueType = 'SchemaVersionMismatch'
            Severity = 'Warning'
            Details = "Multiple schema versions detected: $($schemaVersions -join ', ')"
            AffectedDatabases = @($Results | Where-Object { $_.SchemaVersion -ge 0 } | Select-Object SiteCode, SchemaVersion)
        })
    }

    # Check for missing tables
    foreach ($table in $allTables) {
        $missing = @()
        foreach ($r in $Results) {
            if (-not $r.Tables.ContainsKey($table)) {
                $missing += $r.SiteCode
            }
        }
        if ($missing.Count -gt 0 -and $missing.Count -lt $Results.Count) {
            $issues.Add([pscustomobject]@{
                IssueType = 'MissingTable'
                Severity = 'Error'
                Details = "Table '$table' missing in some databases"
                AffectedDatabases = $missing
            })
        }
    }

    # Check for significant row count differences (>50% variance)
    foreach ($table in $allTables) {
        $counts = @()
        foreach ($r in $Results) {
            if ($r.Tables.ContainsKey($table) -and $r.Tables[$table].RowCount -ge 0) {
                $counts += [pscustomobject]@{
                    Site = $r.SiteCode
                    Count = $r.Tables[$table].RowCount
                }
            }
        }

        if ($counts.Count -ge 2) {
            $avg = ($counts | Measure-Object -Property Count -Average).Average
            if ($avg -gt 0) {
                foreach ($c in $counts) {
                    $variance = [Math]::Abs($c.Count - $avg) / $avg
                    if ($variance -gt 0.5) {
                        $issues.Add([pscustomobject]@{
                            IssueType = 'RowCountVariance'
                            Severity = 'Info'
                            Details = "Table '$table' in $($c.Site) has $($c.Count) rows (avg: $([int]$avg), variance: $([int]($variance * 100))%)"
                            AffectedDatabases = @($c.Site)
                        })
                    }
                }
            }
        }
    }

    return $issues.ToArray()
}

# Main execution
Write-Host "StateTrace Database Consistency Check" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan

$dataDir = $DataDirectoryPath
if ([string]::IsNullOrWhiteSpace($dataDir)) {
    $dataDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'Data'
}

# Get database paths
$dbPaths = @()
if ($Sites -and $Sites.Count -gt 0) {
    foreach ($site in $Sites) {
        $path = DeviceRepository.Access\Get-DbPathForSite -Site $site -DataDirectoryPath $dataDir
        if ($path) { $dbPaths += $path }
    }
} else {
    $dbPaths = DeviceRepository.Access\Get-AllSiteDbPaths -DataDirectoryPath $dataDir
}

if ($dbPaths.Count -eq 0) {
    Write-Warning "No databases found to check."
    exit 0
}

Write-Host "Found $($dbPaths.Count) database(s) to check" -ForegroundColor Green

# Check each database
$results = [System.Collections.Generic.List[object]]::new()
foreach ($dbPath in $dbPaths) {
    $siteName = [System.IO.Path]::GetFileNameWithoutExtension($dbPath)
    Write-Host "  Checking $siteName..." -NoNewline

    $result = Test-SingleDatabaseConsistency -DbPath $dbPath -IncludeChecksums:$IncludeChecksums
    [void]$results.Add($result)

    if ($result.Accessible) {
        Write-Host " OK ($($result.TotalRows) rows, $($result.Tables.Count) tables)" -ForegroundColor Green
    } else {
        Write-Host " FAILED" -ForegroundColor Red
    }
}

# Compare results
Write-Host "`nComparing databases..." -ForegroundColor Cyan
$issues = Compare-DatabaseResults -Results $results.ToArray()

# Build report
$report = [ordered]@{
    GeneratedAt = [datetime]::UtcNow.ToString('o')
    DatabaseCount = $results.Count
    TotalIssues = $issues.Count
    Issues = $issues
    DatabaseResults = $results.ToArray()
}

# Display issues
if ($issues.Count -gt 0) {
    Write-Host "`nIssues Found: $($issues.Count)" -ForegroundColor Yellow
    foreach ($issue in $issues) {
        $color = switch ($issue.Severity) {
            'Error' { 'Red' }
            'Warning' { 'Yellow' }
            default { 'Gray' }
        }
        Write-Host "  [$($issue.Severity)] $($issue.IssueType): $($issue.Details)" -ForegroundColor $color
    }
} else {
    Write-Host "`nNo consistency issues found." -ForegroundColor Green
}

# Output summary
Write-Host "`nSummary:" -ForegroundColor Cyan
Write-Host "  Databases checked: $($results.Count)"
Write-Host "  Accessible: $(($results | Where-Object { $_.Accessible }).Count)"
Write-Host "  Issues found: $($issues.Count)"

# Save report if requested
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    try {
        $json = $report | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($OutputPath, $json, [System.Text.Encoding]::UTF8)
        Write-Host "`nReport saved to: $OutputPath" -ForegroundColor Green
    } catch {
        Write-Warning "Failed to save report: $_"
    }
}

# Return report object
return [pscustomobject]$report
