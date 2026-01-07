<#
.SYNOPSIS
Repairs and compacts Microsoft Access databases used by StateTrace.

.DESCRIPTION
Provides database recovery functionality including:
- Compact and repair operations
- Automatic backup before repair
- Integrity verification
- Corruption detection

.PARAMETER DatabasePath
Path to the Access database to repair.

.PARAMETER Site
Site code. Used to find the database if DatabasePath not specified.

.PARAMETER BackupFirst
Creates a backup before repair (default: true).

.PARAMETER BackupPath
Custom path for backup. Defaults to <database>.backup.<timestamp>.accdb.

.PARAMETER Force
Proceed with repair even if backup fails.

.PARAMETER Verify
Verify database integrity after repair.

.PARAMETER All
Repair all site databases.

.EXAMPLE
.\Repair-AccessDatabase.ps1 -Site 'WLLS'

.EXAMPLE
.\Repair-AccessDatabase.ps1 -DatabasePath 'C:\Data\WLLS\WLLS.accdb' -BackupFirst

.EXAMPLE
.\Repair-AccessDatabase.ps1 -All -Verify
#>

[CmdletBinding(DefaultParameterSetName = 'BySite')]
param(
    [Parameter(ParameterSetName = 'ByPath', Mandatory)]
    [string]$DatabasePath,

    [Parameter(ParameterSetName = 'BySite')]
    [string]$Site,

    [Parameter(ParameterSetName = 'All')]
    [switch]$All,

    [switch]$BackupFirst = $true,
    [string]$BackupPath,
    [switch]$Force,
    [switch]$Verify
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

function Test-DatabaseIntegrity {
    <#
    .SYNOPSIS
    Tests basic database integrity by attempting common operations.
    #>
    param([string]$DbPath)

    $result = [ordered]@{
        Path = $DbPath
        Exists = $false
        CanOpen = $false
        CanReadTables = $false
        CanQuery = $false
        TableCount = 0
        Errors = @()
    }

    if (-not (Test-Path -LiteralPath $DbPath)) {
        $result.Errors += "File not found"
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
                try { $connection.Close() } catch { }
            }
        }

        if (-not $opened) {
            $result.Errors += "Cannot open database with any provider"
            return [pscustomobject]$result
        }
        $result.CanOpen = $true

        # Try to enumerate tables
        try {
            $catalog = New-Object -ComObject ADOX.Catalog
            $catalog.ActiveConnection = $connection

            $tableCount = 0
            foreach ($table in $catalog.Tables) {
                if ($table.Type -eq 'TABLE') {
                    $tableCount++
                }
            }
            $result.TableCount = $tableCount
            $result.CanReadTables = $true

            if ($catalog -is [System.__ComObject]) {
                [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($catalog)
            }
        } catch {
            $result.Errors += "Cannot read tables: $($_.Exception.Message)"
        }

        # Try a simple query
        try {
            $recordset = $connection.Execute("SELECT 1")
            if ($recordset) {
                $recordset.Close()
                $result.CanQuery = $true
            }
        } catch {
            $result.Errors += "Cannot execute queries: $($_.Exception.Message)"
        }

    } catch {
        $result.Errors += "Error: $($_.Exception.Message)"
    } finally {
        if ($connection) {
            try { $connection.Close() } catch { }
            if ($connection -is [System.__ComObject]) {
                [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($connection)
            }
        }
    }

    return [pscustomobject]$result
}

function Backup-AccessDatabase {
    <#
    .SYNOPSIS
    Creates a backup of an Access database.
    #>
    param(
        [string]$SourcePath,
        [string]$DestinationPath
    )

    if (-not (Test-Path -LiteralPath $SourcePath)) {
        throw "Source database not found: $SourcePath"
    }

    if ([string]::IsNullOrWhiteSpace($DestinationPath)) {
        $timestamp = [datetime]::Now.ToString('yyyyMMdd-HHmmss')
        $dir = Split-Path -Parent $SourcePath
        $name = [System.IO.Path]::GetFileNameWithoutExtension($SourcePath)
        $ext = [System.IO.Path]::GetExtension($SourcePath)
        $DestinationPath = Join-Path $dir "${name}.backup.${timestamp}${ext}"
    }

    $destDir = Split-Path -Parent $DestinationPath
    if (-not (Test-Path -LiteralPath $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    Copy-Item -LiteralPath $SourcePath -Destination $DestinationPath -Force
    return $DestinationPath
}

function Invoke-DatabaseCompactRepair {
    <#
    .SYNOPSIS
    Performs Compact and Repair on an Access database using JRO.
    #>
    param(
        [string]$SourcePath,
        [string]$TargetPath
    )

    if ([string]::IsNullOrWhiteSpace($TargetPath)) {
        $dir = Split-Path -Parent $SourcePath
        $name = [System.IO.Path]::GetFileNameWithoutExtension($SourcePath)
        $ext = [System.IO.Path]::GetExtension($SourcePath)
        $TargetPath = Join-Path $dir "${name}.compacted${ext}"
    }

    # Remove target if it exists
    if (Test-Path -LiteralPath $TargetPath) {
        Remove-Item -LiteralPath $TargetPath -Force
    }

    $jro = $null
    $success = $false
    $lastError = $null

    foreach ($prov in @('Microsoft.ACE.OLEDB.12.0', 'Microsoft.Jet.OLEDB.4.0')) {
        try {
            $jro = New-Object -ComObject JRO.JetEngine

            $sourceConn = "Provider=$prov;Data Source=$SourcePath"
            $targetConn = "Provider=$prov;Data Source=$TargetPath"

            $jro.CompactDatabase($sourceConn, $targetConn)
            $success = $true
            break
        } catch {
            $lastError = $_
            if (Test-Path -LiteralPath $TargetPath) {
                Remove-Item -LiteralPath $TargetPath -Force -ErrorAction SilentlyContinue
            }
        } finally {
            if ($jro -and $jro -is [System.__ComObject]) {
                [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($jro)
            }
            $jro = $null
        }
    }

    if (-not $success) {
        throw "Compact and Repair failed: $($lastError.Exception.Message)"
    }

    return $TargetPath
}

function Repair-SingleDatabase {
    <#
    .SYNOPSIS
    Repairs a single Access database.
    #>
    param(
        [string]$DbPath,
        [switch]$BackupFirst,
        [string]$BackupPath,
        [switch]$Force,
        [switch]$Verify
    )

    $result = [ordered]@{
        DatabasePath = $DbPath
        SiteCode = [System.IO.Path]::GetFileNameWithoutExtension($DbPath)
        StartedAt = [datetime]::UtcNow.ToString('o')
        BackupPath = $null
        CompactedPath = $null
        OriginalSize = 0
        FinalSize = 0
        SizeReduction = 0
        Success = $false
        VerificationPassed = $null
        Errors = @()
        Steps = @()
    }

    try {
        # Get original size
        if (Test-Path -LiteralPath $DbPath) {
            $result.OriginalSize = (Get-Item -LiteralPath $DbPath).Length
        } else {
            throw "Database file not found: $DbPath"
        }

        $result.Steps += "Original size: $([int]($result.OriginalSize / 1024)) KB"

        # Create backup
        if ($BackupFirst.IsPresent) {
            try {
                $backupDest = Backup-AccessDatabase -SourcePath $DbPath -DestinationPath $BackupPath
                $result.BackupPath = $backupDest
                $result.Steps += "Backup created: $backupDest"
            } catch {
                $result.Errors += "Backup failed: $($_.Exception.Message)"
                if (-not $Force.IsPresent) {
                    throw "Backup failed and -Force not specified. Aborting."
                }
                $result.Steps += "Backup failed but continuing due to -Force"
            }
        }

        # Perform compact and repair
        $result.Steps += "Starting Compact and Repair..."
        $compactedPath = Invoke-DatabaseCompactRepair -SourcePath $DbPath
        $result.CompactedPath = $compactedPath
        $result.Steps += "Compacted to: $compactedPath"

        # Get compacted size
        $compactedSize = (Get-Item -LiteralPath $compactedPath).Length
        $result.Steps += "Compacted size: $([int]($compactedSize / 1024)) KB"

        # Replace original with compacted
        Remove-Item -LiteralPath $DbPath -Force
        Move-Item -LiteralPath $compactedPath -Destination $DbPath -Force
        $result.Steps += "Replaced original with compacted database"

        # Get final size
        $result.FinalSize = (Get-Item -LiteralPath $DbPath).Length
        $result.SizeReduction = $result.OriginalSize - $result.FinalSize

        if ($result.OriginalSize -gt 0) {
            $pct = [int](($result.SizeReduction / $result.OriginalSize) * 100)
            $result.Steps += "Size reduced by $([int]($result.SizeReduction / 1024)) KB ($pct%)"
        }

        $result.Success = $true

        # Verify if requested
        if ($Verify.IsPresent) {
            $result.Steps += "Verifying database integrity..."
            $verification = Test-DatabaseIntegrity -DbPath $DbPath
            $result.VerificationPassed = ($verification.CanOpen -and $verification.CanQuery)

            if ($result.VerificationPassed) {
                $result.Steps += "Verification passed: $($verification.TableCount) tables accessible"
            } else {
                $result.Steps += "Verification FAILED: $($verification.Errors -join '; ')"
                $result.Errors += $verification.Errors
            }
        }

    } catch {
        $result.Errors += $_.Exception.Message
        $result.Steps += "ERROR: $($_.Exception.Message)"
    }

    $result.CompletedAt = [datetime]::UtcNow.ToString('o')
    return [pscustomobject]$result
}

# Main execution
Write-Host "StateTrace Database Repair Tool" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan

$dataDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'Data'
$dbPaths = @()

if ($PSCmdlet.ParameterSetName -eq 'ByPath') {
    $dbPaths = @($DatabasePath)
} elseif ($All.IsPresent) {
    $dbPaths = DeviceRepository.Access\Get-AllSiteDbPaths -DataDirectoryPath $dataDir
} elseif (-not [string]::IsNullOrWhiteSpace($Site)) {
    $path = DeviceRepository.Access\Get-DbPathForSite -Site $Site -DataDirectoryPath $dataDir
    if ($path) { $dbPaths = @($path) }
} else {
    Write-Warning "Please specify -DatabasePath, -Site, or -All"
    exit 1
}

if ($dbPaths.Count -eq 0) {
    Write-Warning "No databases found to repair."
    exit 0
}

Write-Host "Found $($dbPaths.Count) database(s) to repair" -ForegroundColor Green
if ($BackupFirst.IsPresent) {
    Write-Host "Backups will be created before repair" -ForegroundColor Yellow
}

$results = [System.Collections.Generic.List[object]]::new()

foreach ($dbPath in $dbPaths) {
    $siteName = [System.IO.Path]::GetFileNameWithoutExtension($dbPath)
    Write-Host "`nRepairing $siteName..." -ForegroundColor Cyan

    # Check if file exists
    if (-not (Test-Path -LiteralPath $dbPath)) {
        Write-Host "  Database not found: $dbPath" -ForegroundColor Red
        continue
    }

    # Pre-repair integrity check
    Write-Host "  Checking current integrity..."
    $preCheck = Test-DatabaseIntegrity -DbPath $dbPath
    if (-not $preCheck.CanOpen) {
        Write-Host "  WARNING: Database may be corrupted (cannot open)" -ForegroundColor Yellow
    }

    $result = Repair-SingleDatabase `
        -DbPath $dbPath `
        -BackupFirst:$BackupFirst `
        -BackupPath $BackupPath `
        -Force:$Force `
        -Verify:$Verify

    [void]$results.Add($result)

    foreach ($step in $result.Steps) {
        Write-Host "  $step"
    }

    if ($result.Success) {
        Write-Host "  Repair completed successfully" -ForegroundColor Green
    } else {
        Write-Host "  Repair FAILED" -ForegroundColor Red
        foreach ($err in $result.Errors) {
            Write-Host "    Error: $err" -ForegroundColor Red
        }
    }
}

# Summary
Write-Host "`n================================" -ForegroundColor Cyan
Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "  Databases processed: $($results.Count)"
Write-Host "  Successful: $(($results | Where-Object { $_.Success }).Count)"
Write-Host "  Failed: $(($results | Where-Object { -not $_.Success }).Count)"

$totalReduction = ($results | Where-Object { $_.Success } | Measure-Object -Property SizeReduction -Sum).Sum
if ($totalReduction -gt 0) {
    Write-Host "  Total size reduction: $([int]($totalReduction / 1024)) KB"
}

if ($Verify.IsPresent) {
    $verified = ($results | Where-Object { $_.VerificationPassed -eq $true }).Count
    Write-Host "  Verification passed: $verified"
}

return $results.ToArray()
