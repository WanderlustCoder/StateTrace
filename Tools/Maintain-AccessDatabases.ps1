param(
    [Parameter(Mandatory)][string]$DataRoot,
    [string]$BackupDir = $(Join-Path $DataRoot 'Backups'),
    [switch]$IndexAudit
)

<#
.SYNOPSIS
    Compact and audit Access databases to maintain ingestion performance.
.DESCRIPTION
    Iterates over all `.accdb` files beneath `$DataRoot` and performs maintenance operations:
    1. Creates a timestamped backup in `$BackupDir` before making any changes.
    2. Runs `JRO.CompactDatabase` to compact and repair the database when its size exceeds a threshold (default 100 MB).
    3. When `-IndexAudit` is specified, inspects key tables and outputs a CSV report of missing indexes.  You can extend the audit to rebuild indexes if desired.
    The script writes a summary log to `Logs/Maintenance/<date>.log`.
.NOTES
    Schedule this script to run nightly using `Register-ScheduledTask` or a similar scheduler.  Ensure that no ingestion jobs are running concurrently, as compaction requires exclusive access to the database file.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $DataRoot)) {
    throw "Data root '$DataRoot' does not exist."
}

if (-not (Test-Path -LiteralPath $BackupDir)) {
    $null = New-Item -ItemType Directory -Path $BackupDir -Force
}

# Prepare maintenance log directory
$logRoot = Join-Path -Path $PSScriptRoot -ChildPath '..\Logs\Maintenance'
if (-not (Test-Path -LiteralPath $logRoot)) {
    $null = New-Item -ItemType Directory -Path $logRoot -Force
}
$logFile = Join-Path $logRoot ((Get-Date).ToString('yyyyMMdd-HHmmss') + '.log')
$indexAuditReportPath = Join-Path $logRoot ((Get-Date).ToString('yyyyMMdd-HHmmss') + '-index-audit.csv')

$indexModulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\Modules\DatabaseIndexes.psm1'
if (Test-Path -LiteralPath $indexModulePath) {
    Import-Module -Name $indexModulePath -Force
} else {
    throw "Database index definitions module not found at '$indexModulePath'."
}

function Write-Log {
    param([string]$Message)
    $timestamp = (Get-Date).ToString('s')
    $entry = "[$timestamp] $Message"
    $entry | Tee-Object -FilePath $logFile -Append | Out-Null
}

function Compact-Database {
    param([string]$DbPath)
    $provider = 'Provider=Microsoft.ACE.OLEDB.12.0;'
    $source = $provider + 'Data Source=' + $DbPath
    $tmpPath = [System.IO.Path]::ChangeExtension($DbPath, '.tmp')
    $dest   = $provider + 'Data Source=' + $tmpPath
    $jetEngine = $null
    try {
        $jetEngine = New-Object -ComObject 'JRO.JetEngine'
        $jetEngine.CompactDatabase($source, $dest)
        # Replace original with compacted
        Remove-Item -LiteralPath $DbPath -Force
        Move-Item -LiteralPath $tmpPath -Destination $DbPath
        Write-Log "Compacted '$DbPath' successfully."
    } catch {
        Write-Log "Failed to compact '$DbPath': $_"
        if (Test-Path -LiteralPath $tmpPath) { Remove-Item -LiteralPath $tmpPath -Force }
    } finally {
        if ($jetEngine -is [System.__ComObject]) {
            try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($jetEngine) } catch { }
        }
    }
}

function Audit-Indexes {
    param([string]$DbPath)
    $providers = @('Microsoft.ACE.OLEDB.12.0', 'Microsoft.Jet.OLEDB.4.0')
    $catalog = $null
    $connectedProvider = $null
    foreach ($provider in $providers) {
        try {
            $catalog = New-Object -ComObject ADOX.Catalog
            $catalog.ActiveConnection = "Provider=$provider;Data Source=$DbPath"
            $connectedProvider = $provider
            break
        } catch {
            if ($catalog) {
                try { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($catalog) | Out-Null } catch { }
                $catalog = $null
            }
            continue
        }
    }

    if (-not $catalog) {
        Write-Log "Index audit skipped for '$DbPath' (no usable provider)."
        return
    }

    $existingByColumns = @{}
    try {
        foreach ($table in $catalog.Tables) {
            $tableName = '' + $table.Name
            foreach ($index in $table.Indexes) {
                $cols = [System.Collections.Generic.List[string]]::new()
                foreach ($col in $index.Columns) {
                    $cols.Add(('' + $col.Name))
                }
                $key = "{0}|{1}" -f $tableName.ToLowerInvariant(), ([string]::Join(',', ($cols | ForEach-Object { $_.ToLowerInvariant() })))
                $existingByColumns[$key] = [pscustomobject]@{
                    IndexName  = '' + $index.Name
                    Table      = $tableName
                    Columns    = $cols
                    PrimaryKey = [bool]$index.PrimaryKey
                    Unique     = [bool]$index.Unique
                }
            }
        }
    } catch {
        Write-Log "Index audit failed for '$DbPath': $_"
        try { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($catalog) | Out-Null } catch { }
        return
    }

    $missing = [System.Collections.Generic.List[pscustomobject]]::new()
    $expectedIndexes = Get-StateTraceIndexDefinitions
    foreach ($expected in $expectedIndexes) {
        $key = "{0}|{1}" -f $expected.Table.ToLowerInvariant(), ([string]::Join(',', ($expected.Columns | ForEach-Object { $_.ToLowerInvariant() })))
        if (-not $existingByColumns.ContainsKey($key)) {
            $missing.Add([pscustomobject]@{
                Database        = $DbPath
                Table           = $expected.Table
                ExpectedIndex   = $expected.Name
                ExpectedColumns = [string]::Join(',', $expected.Columns)
                Status          = 'Missing'
            })
        }
    }

    if ($missing.Count -eq 0) {
        Write-Log "Index audit passed for '$DbPath' using provider '$connectedProvider'."
    } else {
        Write-Log ("Index audit found {0} missing indexes for '{1}'." -f $missing.Count, $DbPath)
        if (-not (Test-Path -LiteralPath $indexAuditReportPath)) {
            $missing | Export-Csv -Path $indexAuditReportPath -NoTypeInformation
        } else {
            $missing | Export-Csv -Path $indexAuditReportPath -NoTypeInformation -Append
        }
    }

    try { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($catalog) | Out-Null } catch { }
}

Get-ChildItem -Path $DataRoot -Filter '*.accdb' -Recurse | ForEach-Object {
    $db = $_.FullName
    $sizeMB = [math]::Round($_.Length / 1MB, 2)
    # Create backup
    $timestamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $backupPath = Join-Path $BackupDir ("$($_.BaseName)_$timestamp.accdb")
    Copy-Item -LiteralPath $db -Destination $backupPath -Force
    Write-Log "Backed up '$db' to '$backupPath' ($sizeMB MB)."
    # Compact if size > 100MB
    if ($sizeMB -gt 100) {
        Write-Log "Compacting '$db' (size $sizeMB MB) ..."
        Compact-Database -DbPath $db
    }
    # Optional index audit
    if ($IndexAudit) {
        Audit-Indexes -DbPath $db
    }
}

Write-Log 'Maintenance run complete.'
