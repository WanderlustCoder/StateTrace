# DatabaseConcurrencyModule.psm1
# Database concurrency testing, monitoring, and maintenance

Set-StrictMode -Version Latest

$script:LockMetrics = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()
$script:ConnectionPool = @{}
$script:AccessProviderCache = @{}

function Get-AccessProvider {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DatabasePath
    )

    $key = $DatabasePath.ToLowerInvariant()
    if ($script:AccessProviderCache.ContainsKey($key)) {
        return $script:AccessProviderCache[$key]
    }

    $providers = @('Microsoft.ACE.OLEDB.16.0', 'Microsoft.ACE.OLEDB.12.0', 'Microsoft.Jet.OLEDB.4.0')
    foreach ($prov in $providers) {
        $conn = $null
        try {
            $conn = [System.Data.OleDb.OleDbConnection]::new("Provider=$prov;Data Source=$DatabasePath;Persist Security Info=False;")
            $conn.Open()
            $conn.Close()
            if ($conn) { $conn.Dispose() }
            $script:AccessProviderCache[$key] = $prov
            return $prov
        } catch {
            if ($conn) { $conn.Dispose() }
        }
    }

    throw "Failed to open Access database '$DatabasePath' with ACE/Jet providers."
}

function Get-AccessConnectionString {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DatabasePath
    )

    $provider = Get-AccessProvider -DatabasePath $DatabasePath
    return "Provider=$provider;Data Source=$DatabasePath;Persist Security Info=False;"
}

#region Concurrent Write Testing

function Test-ConcurrentWrites {
    <#
    .SYNOPSIS
    Tests database behavior under concurrent write load.
    .PARAMETER DatabasePath
    Path to Access database.
    .PARAMETER ThreadCount
    Number of concurrent threads. Default 4.
    .PARAMETER OperationsPerThread
    Number of write operations per thread. Default 100.
    .PARAMETER TableName
    Table to write to. Default 'ConcurrencyTest'.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DatabasePath,

        [int]$ThreadCount = 4,

        [int]$OperationsPerThread = 100,

        [string]$TableName = 'ConcurrencyTest'
    )

    if (-not (Test-Path $DatabasePath)) {
        throw "Database not found: $DatabasePath"
    }

    $testId = [guid]::NewGuid().ToString('N').Substring(0, 8)
    $startTime = [datetime]::UtcNow

    $results = @{
        TestId = $testId
        DatabasePath = $DatabasePath
        ThreadCount = $ThreadCount
        OperationsPerThread = $OperationsPerThread
        StartTime = $startTime.ToString('o')
        Threads = @{}
        TotalOperations = 0
        SuccessfulOperations = 0
        FailedOperations = 0
        LockTimeouts = 0
        CorruptionDetected = $false
        DurationMs = 0
    }

    # Ensure test table exists
    Initialize-ConcurrencyTestTable -DatabasePath $DatabasePath -TableName $TableName
    $provider = Get-AccessProvider -DatabasePath $DatabasePath

    # Create runspaces for parallel execution
    $runspacePool = [runspacefactory]::CreateRunspacePool(1, $ThreadCount)
    $runspacePool.Open()

    $jobs = @()

    $scriptBlock = {
        param($DbPath, $TableName, $ThreadId, $Operations, $Provider, $TestId)

        $results = @{
            ThreadId = $ThreadId
            Successful = 0
            Failed = 0
            LockTimeouts = 0
            Errors = @()
            StartTime = [datetime]::UtcNow
        }

        $connString = "Provider=$Provider;Data Source=$DbPath;Persist Security Info=False;"

        for ($i = 0; $i -lt $Operations; $i++) {
            $conn = $null
            try {
                $conn = [System.Data.OleDb.OleDbConnection]::new($connString)
                $conn.Open()

                $timestamp = [datetime]::UtcNow.ToString('o')
                $value = "Thread${ThreadId}_Op${i}_$([guid]::NewGuid().ToString('N').Substring(0,8))"

                $sql = "INSERT INTO [$TableName] (TestId, ThreadId, OperationId, Timestamp, TestValue) VALUES ('$TestId', $ThreadId, $i, '$timestamp', '$value')"
                
                $cmd = $conn.CreateCommand()
                $cmd.CommandText = $sql
                $cmd.CommandTimeout = 30
                
                $cmd.ExecuteNonQuery() | Out-Null
                $results.Successful++

            } catch {
                $results.Failed++
                $errorMsg = $_.Exception.Message

                if ($errorMsg -match 'locked|timeout|busy') {
                    $results.LockTimeouts++
                }

                $results.Errors += @{
                    Operation = $i
                    Error = $errorMsg
                }
            } finally {
                if ($conn -and $conn.State -eq 'Open') {
                    $conn.Close()
                }
                if ($conn) {
                    $conn.Dispose()
                }
            }

            # Small delay to simulate realistic workload
            Start-Sleep -Milliseconds (Get-Random -Minimum 5 -Maximum 20)
        }

        $results.EndTime = [datetime]::UtcNow
        $results.DurationMs = ([datetime]::UtcNow - $results.StartTime).TotalMilliseconds

        return $results
    }

    # Start threads
    for ($t = 0; $t -lt $ThreadCount; $t++) {
        $powershell = [powershell]::Create()
        $powershell.RunspacePool = $runspacePool
        
        [void]$powershell.AddScript($scriptBlock)
        [void]$powershell.AddArgument($DatabasePath)
        [void]$powershell.AddArgument($TableName)
        [void]$powershell.AddArgument($t)
        [void]$powershell.AddArgument($OperationsPerThread)
        [void]$powershell.AddArgument($provider)
        [void]$powershell.AddArgument($testId)

        $jobs += @{
            PowerShell = $powershell
            Handle = $powershell.BeginInvoke()
            ThreadId = $t
        }
    }

    # Wait for completion and collect results
    foreach ($job in $jobs) {
        $threadResult = $job.PowerShell.EndInvoke($job.Handle)
        $job.PowerShell.Dispose()

        if ($threadResult) {
            $results.Threads[$job.ThreadId] = $threadResult
            $results.SuccessfulOperations += $threadResult.Successful
            $results.FailedOperations += $threadResult.Failed
            $results.LockTimeouts += $threadResult.LockTimeouts
        }
    }

    $runspacePool.Close()
    $runspacePool.Dispose()

    $results.TotalOperations = $ThreadCount * $OperationsPerThread
    $results.EndTime = [datetime]::UtcNow.ToString('o')
    $results.DurationMs = ([datetime]::UtcNow - $startTime).TotalMilliseconds

    # Verify data integrity
    $integrityCheck = Test-ConcurrencyDataIntegrity -DatabasePath $DatabasePath -TableName $TableName -TestId $testId -ExpectedCount $results.SuccessfulOperations
    $results.IntegrityCheck = $integrityCheck
    $results.CorruptionDetected = -not $integrityCheck.Passed

    # Calculate metrics
    $results.SuccessRate = if ($results.TotalOperations -gt 0) {
        [math]::Round($results.SuccessfulOperations / $results.TotalOperations * 100, 2)
    } else { 0 }

    $results.OperationsPerSecond = if ($results.DurationMs -gt 0) {
        [math]::Round($results.SuccessfulOperations / ($results.DurationMs / 1000), 2)
    } else { 0 }

    return [PSCustomObject]$results
}

function Initialize-ConcurrencyTestTable {
    param(
        [string]$DatabasePath,
        [string]$TableName
    )

    $connString = Get-AccessConnectionString -DatabasePath $DatabasePath
    $conn = $null

    try {
        $conn = [System.Data.OleDb.OleDbConnection]::new($connString)
        $conn.Open()

        # Check if table exists
        $schema = $conn.GetSchema('Tables')
        $tableExists = $schema.Rows | Where-Object { $_['TABLE_NAME'] -eq $TableName }

        if (-not $tableExists) {
            $sql = @"
CREATE TABLE [$TableName] (
    Id AUTOINCREMENT PRIMARY KEY,
    TestId TEXT(32),
    ThreadId INTEGER,
    OperationId INTEGER,
    Timestamp TEXT,
    TestValue TEXT
)
"@
            $cmd = $conn.CreateCommand()
            $cmd.CommandText = $sql
            $cmd.ExecuteNonQuery() | Out-Null
        } else {
            $columns = $conn.GetSchema('Columns')
            $hasTestId = $columns.Rows | Where-Object { $_['TABLE_NAME'] -eq $TableName -and $_['COLUMN_NAME'] -eq 'TestId' }
            if (-not $hasTestId) {
                $cmd = $conn.CreateCommand()
                $cmd.CommandText = "ALTER TABLE [$TableName] ADD COLUMN TestId TEXT(32)"
                $cmd.ExecuteNonQuery() | Out-Null
            }
        }

    } finally {
        if ($conn -and $conn.State -eq 'Open') {
            $conn.Close()
        }
        if ($conn) {
            $conn.Dispose()
        }
    }
}

function Test-ConcurrencyDataIntegrity {
    param(
        [string]$DatabasePath,
        [string]$TableName,
        [string]$TestId,
        [int]$ExpectedCount
    )

    $result = @{
        Passed = $true
        ExpectedCount = $ExpectedCount
        ActualCount = 0
        DuplicateCheck = $true
        Errors = @()
    }

    $connString = Get-AccessConnectionString -DatabasePath $DatabasePath
    $conn = $null

    try {
        $conn = [System.Data.OleDb.OleDbConnection]::new($connString)
        $conn.Open()

        # Count records
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "SELECT COUNT(*) FROM [$TableName] WHERE TestId = '$TestId'"
        $result.ActualCount = [int]$cmd.ExecuteScalar()

        # Check for duplicates (same ThreadId + OperationId)
        $cmd.CommandText = @"
SELECT ThreadId, OperationId, COUNT(*) as cnt
FROM [$TableName]
WHERE TestId = '$TestId'
GROUP BY ThreadId, OperationId
HAVING COUNT(*) > 1
"@
        $reader = $cmd.ExecuteReader()
        try {
            $duplicates = @()
            while ($reader.Read()) {
                $duplicates += @{
                    ThreadId = $reader['ThreadId']
                    OperationId = $reader['OperationId']
                    Count = $reader['cnt']
                }
            }
        } finally {
            if ($reader) { $reader.Dispose() }
        }

        if ($duplicates.Count -gt 0) {
            $result.DuplicateCheck = $false
            $result.Passed = $false
            $result.Errors += "Found $($duplicates.Count) duplicate records"
        }

    } catch {
        $result.Passed = $false
        $result.Errors += $_.Exception.Message
    } finally {
        if ($conn -and $conn.State -eq 'Open') {
            $conn.Close()
        }
        if ($conn) {
            $conn.Dispose()
        }
    }

    return $result
}

#endregion

#region Lock Contention Monitoring

function Start-LockMonitoring {
    <#
    .SYNOPSIS
    Starts monitoring database lock contention.
    #>
    [CmdletBinding()]
    param()

    $script:LockMetrics = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()
    
    [void]$script:LockMetrics.TryAdd('StartTime', [datetime]::UtcNow)
    [void]$script:LockMetrics.TryAdd('TotalAttempts', 0)
    [void]$script:LockMetrics.TryAdd('LockWaits', 0)
    [void]$script:LockMetrics.TryAdd('LockTimeouts', 0)
    [void]$script:LockMetrics.TryAdd('TotalWaitTimeMs', 0)
    [void]$script:LockMetrics.TryAdd('MaxWaitTimeMs', 0)
    [void]$script:LockMetrics.TryAdd('WaitEvents', [System.Collections.Concurrent.ConcurrentQueue[object]]::new())

    Write-Verbose "[LockMonitoring] Started"
}

function Record-LockEvent {
    <#
    .SYNOPSIS
    Records a lock wait event.
    .PARAMETER Database
    Database name/path.
    .PARAMETER WaitTimeMs
    Time spent waiting for lock.
    .PARAMETER TimedOut
    Whether the lock attempt timed out.
    #>
    [CmdletBinding()]
    param(
        [string]$Database,
        [int]$WaitTimeMs,
        [switch]$TimedOut
    )

    if (-not $script:LockMetrics.ContainsKey('StartTime')) {
        Start-LockMonitoring
    }

    # Update counters
    $script:LockMetrics['TotalAttempts'] = [int]$script:LockMetrics['TotalAttempts'] + 1

    if ($WaitTimeMs -gt 0) {
        $script:LockMetrics['LockWaits'] = [int]$script:LockMetrics['LockWaits'] + 1
        $script:LockMetrics['TotalWaitTimeMs'] = [int]$script:LockMetrics['TotalWaitTimeMs'] + $WaitTimeMs

        if ($WaitTimeMs -gt [int]$script:LockMetrics['MaxWaitTimeMs']) {
            $script:LockMetrics['MaxWaitTimeMs'] = $WaitTimeMs
        }
    }

    if ($TimedOut) {
        $script:LockMetrics['LockTimeouts'] = [int]$script:LockMetrics['LockTimeouts'] + 1
    }

    # Add event to queue (keep last 1000)
    $queue = $script:LockMetrics['WaitEvents']
    $event = @{
        Timestamp = [datetime]::UtcNow.ToString('o')
        Database = $Database
        WaitTimeMs = $WaitTimeMs
        TimedOut = $TimedOut.IsPresent
    }
    [void]$queue.Enqueue($event)

    # Trim queue if needed
    while ($queue.Count -gt 1000) {
        $dummy = $null
        [void]$queue.TryDequeue([ref]$dummy)
    }
}

function Get-LockMetrics {
    <#
    .SYNOPSIS
    Returns current lock contention metrics.
    #>
    [CmdletBinding()]
    param()

    if (-not $script:LockMetrics.ContainsKey('StartTime')) {
        return @{ Message = 'Lock monitoring not started' }
    }

    $totalAttempts = [int]$script:LockMetrics['TotalAttempts']
    $lockWaits = [int]$script:LockMetrics['LockWaits']
    $totalWaitTimeMs = [int]$script:LockMetrics['TotalWaitTimeMs']

    return @{
        StartTime = $script:LockMetrics['StartTime']
        UptimeMinutes = [math]::Round(([datetime]::UtcNow - $script:LockMetrics['StartTime']).TotalMinutes, 2)
        TotalAttempts = $totalAttempts
        LockWaits = $lockWaits
        LockTimeouts = [int]$script:LockMetrics['LockTimeouts']
        TotalWaitTimeMs = $totalWaitTimeMs
        MaxWaitTimeMs = [int]$script:LockMetrics['MaxWaitTimeMs']
        AvgWaitTimeMs = if ($lockWaits -gt 0) { [math]::Round($totalWaitTimeMs / $lockWaits, 2) } else { 0 }
        LockWaitRate = if ($totalAttempts -gt 0) { [math]::Round($lockWaits / $totalAttempts * 100, 2) } else { 0 }
        TimeoutRate = if ($totalAttempts -gt 0) { [math]::Round([int]$script:LockMetrics['LockTimeouts'] / $totalAttempts * 100, 2) } else { 0 }
    }
}

function Get-LockEvents {
    <#
    .SYNOPSIS
    Returns recent lock wait events.
    .PARAMETER Last
    Number of events to return. Default 100.
    #>
    [CmdletBinding()]
    param(
        [int]$Last = 100
    )

    if (-not $script:LockMetrics.ContainsKey('WaitEvents')) {
        return @()
    }

    $queue = $script:LockMetrics['WaitEvents']
    $events = $queue.ToArray()

    return $events | Select-Object -Last $Last
}

#endregion

#region Database Repair Automation

function Repair-AccessDatabase {
    <#
    .SYNOPSIS
    Repairs and compacts an Access database.
    .PARAMETER DatabasePath
    Path to Access database.
    .PARAMETER BackupFirst
    Create backup before repair. Default true.
    .PARAMETER BackupPath
    Custom backup path. Default adds .backup suffix.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DatabasePath,

        [switch]$BackupFirst = $true,

        [string]$BackupPath
    )

    if (-not (Test-Path $DatabasePath)) {
        throw "Database not found: $DatabasePath"
    }

    $result = @{
        DatabasePath = $DatabasePath
        StartTime = [datetime]::UtcNow.ToString('o')
        BackupCreated = $false
        BackupPath = $null
        RepairSuccessful = $false
        OriginalSize = (Get-Item $DatabasePath).Length
        FinalSize = 0
        SizeReduction = 0
        Errors = @()
    }

    # Create backup
    if ($BackupFirst) {
        if (-not $BackupPath) {
            $BackupPath = $DatabasePath + ".backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        }

        try {
            Copy-Item -Path $DatabasePath -Destination $BackupPath -Force
            $result.BackupCreated = $true
            $result.BackupPath = $BackupPath
            Write-Verbose "[Repair] Backup created: $BackupPath"
        } catch {
            $result.Errors += "Backup failed: $($_.Exception.Message)"
            throw "Failed to create backup: $_"
        }
    }

    # Create temp file for compacted database
    $tempPath = $DatabasePath + ".compact-temp"

    try {
        # Use JRO (Jet Replication Objects) for compact/repair
        $jro = New-Object -ComObject JRO.JetEngine

        $provider = Get-AccessProvider -DatabasePath $DatabasePath
        $sourceConn = "Provider=$provider;Data Source=$DatabasePath"
        $destConn = "Provider=$provider;Data Source=$tempPath"

        $jro.CompactDatabase($sourceConn, $destConn)

        # Replace original with compacted
        Remove-Item -Path $DatabasePath -Force
        Move-Item -Path $tempPath -Destination $DatabasePath -Force

        $result.RepairSuccessful = $true
        $result.FinalSize = (Get-Item $DatabasePath).Length
        $result.SizeReduction = $result.OriginalSize - $result.FinalSize
        $result.SizeReductionPercent = if ($result.OriginalSize -gt 0) {
            [math]::Round($result.SizeReduction / $result.OriginalSize * 100, 2)
        } else { 0 }

        Write-Verbose "[Repair] Compact successful. Size reduced by $($result.SizeReductionPercent)%"

    } catch {
        $result.Errors += "Compact failed: $($_.Exception.Message)"

        # Cleanup temp file if exists
        if (Test-Path $tempPath) {
            Remove-Item -Path $tempPath -Force -ErrorAction SilentlyContinue
        }

        # Restore from backup if available
        if ($result.BackupCreated -and (Test-Path $BackupPath)) {
            try {
                Copy-Item -Path $BackupPath -Destination $DatabasePath -Force
                $result.Errors += "Restored from backup after failed repair"
            } catch {
                $result.Errors += "Failed to restore from backup: $($_.Exception.Message)"
            }
        }

    } finally {
        if ($jro) {
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($jro) | Out-Null
        }
    }

    $result.EndTime = [datetime]::UtcNow.ToString('o')

    # Log audit event
    try {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        Import-Module (Join-Path $projectRoot 'Modules\AuditTrailModule.psm1') -Force -DisableNameChecking -ErrorAction SilentlyContinue
        $auditResult = if ($result.RepairSuccessful) { 'Success' } else { 'Failure' }
        Write-AuditEvent -EventType 'SystemAction' -Category 'Database' -Action 'Execute' `
            -Target $DatabasePath -Details "Compact/Repair" -Result $auditResult
    } catch { Write-Verbose "Audit logging skipped for compact/repair: $_" }

    return [PSCustomObject]$result
}

function Test-DatabaseHealth {
    <#
    .SYNOPSIS
    Tests database health and integrity.
    .PARAMETER DatabasePath
    Path to Access database.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DatabasePath
    )

    if (-not (Test-Path $DatabasePath)) {
        return @{
            DatabasePath = $DatabasePath
            Exists = $false
            Healthy = $false
            Errors = @('Database file not found')
        }
    }

    $result = @{
        DatabasePath = $DatabasePath
        Exists = $true
        Healthy = $true
        FileSize = (Get-Item $DatabasePath).Length
        LastModified = (Get-Item $DatabasePath).LastWriteTime
        CanConnect = $false
        TableCount = 0
        Tables = @()
        Errors = @()
        Warnings = @()
    }

    $connString = Get-AccessConnectionString -DatabasePath $DatabasePath
    $conn = $null

    try {
        $conn = [System.Data.OleDb.OleDbConnection]::new($connString)
        $conn.Open()
        $result.CanConnect = $true

        # Get table list
        $schema = $conn.GetSchema('Tables')
        $tables = $schema.Rows | Where-Object { $_['TABLE_TYPE'] -eq 'TABLE' }

        foreach ($table in $tables) {
            $tableName = $table['TABLE_NAME']
            $tableInfo = @{
                Name = $tableName
                RowCount = 0
                CanQuery = $false
            }

            try {
                $cmd = $conn.CreateCommand()
                $cmd.CommandText = "SELECT COUNT(*) FROM [$tableName]"
                $cmd.CommandTimeout = 30
                $tableInfo.RowCount = [int]$cmd.ExecuteScalar()
                $tableInfo.CanQuery = $true
            } catch {
                $tableInfo.Error = $_.Exception.Message
                $result.Warnings += "Table $tableName query failed: $($_.Exception.Message)"
            }

            $result.Tables += $tableInfo
        }

        $result.TableCount = $result.Tables.Count

        # Check file size warning
        $sizeMB = $result.FileSize / 1MB
        if ($sizeMB -gt 1500) {
            $result.Warnings += "Database size ($([math]::Round($sizeMB, 2)) MB) approaching Access limit (2 GB)"
        }

    } catch {
        $result.Healthy = $false
        $result.Errors += "Connection failed: $($_.Exception.Message)"
    } finally {
        if ($conn -and $conn.State -eq 'Open') {
            $conn.Close()
        }
        if ($conn) {
            $conn.Dispose()
        }
    }

    if ($result.Errors.Count -gt 0) {
        $result.Healthy = $false
    }

    return [PSCustomObject]$result
}

#endregion

#region Backup Scheduler

function New-DatabaseBackup {
    <#
    .SYNOPSIS
    Creates a database backup.
    .PARAMETER DatabasePath
    Path to database.
    .PARAMETER BackupFolder
    Folder to store backups.
    .PARAMETER RetentionDays
    Days to keep backups. Default 30.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DatabasePath,

        [string]$BackupFolder,

        [int]$RetentionDays = 30
    )

    if (-not (Test-Path $DatabasePath)) {
        throw "Database not found: $DatabasePath"
    }

    $projectRoot = Split-Path -Parent $PSScriptRoot

    if (-not $BackupFolder) {
        $BackupFolder = Join-Path $projectRoot 'Data\Backups'
    }

    if (-not (Test-Path $BackupFolder)) {
        New-Item -Path $BackupFolder -ItemType Directory -Force | Out-Null
    }

    $dbName = [System.IO.Path]::GetFileNameWithoutExtension($DatabasePath)
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupName = "${dbName}_${timestamp}.accdb"
    $backupPath = Join-Path $BackupFolder $backupName

    $result = @{
        SourcePath = $DatabasePath
        BackupPath = $backupPath
        Timestamp = [datetime]::UtcNow.ToString('o')
        Success = $false
        Size = 0
        CleanedUp = 0
    }

    try {
        Copy-Item -Path $DatabasePath -Destination $backupPath -Force
        $result.Success = $true
        $result.Size = (Get-Item $backupPath).Length

        Write-Verbose "[Backup] Created: $backupPath"

        # Cleanup old backups
        $cutoff = (Get-Date).AddDays(-$RetentionDays)
        $oldBackups = Get-ChildItem -Path $BackupFolder -Filter "${dbName}_*.accdb" |
            Where-Object { $_.LastWriteTime -lt $cutoff }

        foreach ($old in $oldBackups) {
            Remove-Item -Path $old.FullName -Force
            $result.CleanedUp++
        }

        if ($result.CleanedUp -gt 0) {
            Write-Verbose "[Backup] Cleaned up $($result.CleanedUp) old backups"
        }

    } catch {
        $result.Error = $_.Exception.Message
    }

    return [PSCustomObject]$result
}

function Get-DatabaseBackups {
    <#
    .SYNOPSIS
    Lists available database backups.
    .PARAMETER DatabaseName
    Filter by database name.
    .PARAMETER BackupFolder
    Backup folder path.
    #>
    [CmdletBinding()]
    param(
        [string]$DatabaseName,
        [string]$BackupFolder
    )

    $projectRoot = Split-Path -Parent $PSScriptRoot

    if (-not $BackupFolder) {
        $BackupFolder = Join-Path $projectRoot 'Data\Backups'
    }

    if (-not (Test-Path $BackupFolder)) {
        return @()
    }

    $filter = if ($DatabaseName) { "${DatabaseName}_*.accdb" } else { "*.accdb" }

    Get-ChildItem -Path $BackupFolder -Filter $filter |
        Sort-Object LastWriteTime -Descending |
        ForEach-Object {
            [PSCustomObject]@{
                Name = $_.Name
                Path = $_.FullName
                Size = $_.Length
                SizeMB = [math]::Round($_.Length / 1MB, 2)
                Created = $_.LastWriteTime
                Age = [math]::Round(((Get-Date) - $_.LastWriteTime).TotalDays, 1)
            }
        }
}

function Restore-DatabaseBackup {
    <#
    .SYNOPSIS
    Restores a database from backup.
    .PARAMETER BackupPath
    Path to backup file.
    .PARAMETER TargetPath
    Target database path.
    .PARAMETER Force
    Overwrite existing database.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BackupPath,

        [Parameter(Mandatory)]
        [string]$TargetPath,

        [switch]$Force
    )

    if (-not (Test-Path $BackupPath)) {
        throw "Backup not found: $BackupPath"
    }

    if ((Test-Path $TargetPath) -and -not $Force) {
        throw "Target database exists. Use -Force to overwrite."
    }

    $result = @{
        BackupPath = $BackupPath
        TargetPath = $TargetPath
        Timestamp = [datetime]::UtcNow.ToString('o')
        Success = $false
    }

    try {
        Copy-Item -Path $BackupPath -Destination $TargetPath -Force
        $result.Success = $true
        $result.RestoredSize = (Get-Item $TargetPath).Length

        # Log audit event
        try {
            $projectRoot = Split-Path -Parent $PSScriptRoot
            Import-Module (Join-Path $projectRoot 'Modules\AuditTrailModule.psm1') -Force -DisableNameChecking -ErrorAction SilentlyContinue
            Write-AuditEvent -EventType 'SystemAction' -Category 'Database' -Action 'Execute' `
                -Target $TargetPath -Details "Restored from $BackupPath" -Result 'Success'
        } catch { Write-Verbose "Audit logging skipped for restore: $_" }

    } catch {
        $result.Error = $_.Exception.Message
    }

    return [PSCustomObject]$result
}

#endregion

#region Integrity Verification

function Test-DatabaseIntegrity {
    <#
    .SYNOPSIS
    Performs comprehensive database integrity checks.
    .PARAMETER DatabasePath
    Path to Access database.
    .PARAMETER IncludeRowCounts
    Include row count verification.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DatabasePath,

        [switch]$IncludeRowCounts
    )

    $result = @{
        DatabasePath = $DatabasePath
        CheckTime = [datetime]::UtcNow.ToString('o')
        OverallStatus = 'Unknown'
        Checks = @()
    }

    # Check 1: File exists and readable
    $fileCheck = @{
        Name = 'FileAccess'
        Status = 'Unknown'
        Details = ''
    }

    if (Test-Path $DatabasePath) {
        try {
            $bytes = [System.IO.File]::ReadAllBytes($DatabasePath) | Select-Object -First 100
            $fileCheck.Status = 'Pass'
            $fileCheck.Details = "File readable, size: $((Get-Item $DatabasePath).Length) bytes"
        } catch {
            $fileCheck.Status = 'Fail'
            $fileCheck.Details = "File read error: $($_.Exception.Message)"
        }
    } else {
        $fileCheck.Status = 'Fail'
        $fileCheck.Details = 'File not found'
    }
    $result.Checks += $fileCheck

    if ($fileCheck.Status -eq 'Fail') {
        $result.OverallStatus = 'Fail'
        return [PSCustomObject]$result
    }

    $connString = Get-AccessConnectionString -DatabasePath $DatabasePath
    $conn = $null

    try {
        $conn = [System.Data.OleDb.OleDbConnection]::new($connString)
        $conn.Open()

        # Check 2: Connection
        $connCheck = @{
            Name = 'Connection'
            Status = 'Pass'
            Details = 'Database connection successful'
        }
        $result.Checks += $connCheck

        # Check 3: Schema readable
        $schemaCheck = @{
            Name = 'Schema'
            Status = 'Unknown'
            Details = ''
        }

        try {
            $schema = $conn.GetSchema('Tables')
            $tableCount = @($schema.Rows | Where-Object { $_['TABLE_TYPE'] -eq 'TABLE' }).Count
            $schemaCheck.Status = 'Pass'
            $schemaCheck.Details = "Schema readable, $tableCount tables found"
        } catch {
            $schemaCheck.Status = 'Fail'
            $schemaCheck.Details = "Schema error: $($_.Exception.Message)"
        }
        $result.Checks += $schemaCheck

        # Check 4: Query each table
        if ($schemaCheck.Status -eq 'Pass') {
            $tables = $schema.Rows | Where-Object { $_['TABLE_TYPE'] -eq 'TABLE' }
            
            foreach ($table in $tables) {
                $tableName = $table['TABLE_NAME']
                $tableCheck = @{
                    Name = "Table_$tableName"
                    Status = 'Unknown'
                    Details = ''
                }

                try {
                    $cmd = $conn.CreateCommand()
                    $cmd.CommandTimeout = 60
                    
                    if ($IncludeRowCounts) {
                        $cmd.CommandText = "SELECT COUNT(*) FROM [$tableName]"
                        $count = [int]$cmd.ExecuteScalar()
                        $tableCheck.Details = "Queryable, $count rows"
                    } else {
                        $cmd.CommandText = "SELECT TOP 1 * FROM [$tableName]"
                        $reader = $cmd.ExecuteReader()
                        try {
                            $tableCheck.Details = "Queryable"
                        } finally {
                            if ($reader) { $reader.Dispose() }
                        }
                    }
                    $tableCheck.Status = 'Pass'
                } catch {
                    $tableCheck.Status = 'Fail'
                    $tableCheck.Details = "Query error: $($_.Exception.Message)"
                }

                $result.Checks += $tableCheck
            }
        }

        # Check 5: Index health (simplified check)
        $indexCheck = @{
            Name = 'Indexes'
            Status = 'Unknown'
            Details = ''
        }

        try {
            $indexSchema = $conn.GetSchema('Indexes')
            $indexCount = $indexSchema.Rows.Count
            $indexCheck.Status = 'Pass'
            $indexCheck.Details = "$indexCount indexes found"
        } catch {
            $indexCheck.Status = 'Warning'
            $indexCheck.Details = "Index check skipped: $($_.Exception.Message)"
        }
        $result.Checks += $indexCheck

    } catch {
        $result.Checks += @{
            Name = 'Connection'
            Status = 'Fail'
            Details = "Connection failed: $($_.Exception.Message)"
        }
    } finally {
        if ($conn -and $conn.State -eq 'Open') {
            $conn.Close()
        }
        if ($conn) {
            $conn.Dispose()
        }
    }

    # Determine overall status
    $failedChecks = @($result.Checks | Where-Object { $_.Status -eq 'Fail' })     
    $warningChecks = @($result.Checks | Where-Object { $_.Status -eq 'Warning' }) 

    if ($failedChecks.Count -gt 0) {
        $result.OverallStatus = 'Fail'
    } elseif ($warningChecks.Count -gt 0) {
        $result.OverallStatus = 'Warning'
    } else {
        $result.OverallStatus = 'Pass'
    }

    $result.PassedChecks = @($result.Checks | Where-Object { $_.Status -eq 'Pass' }).Count
    $result.TotalChecks = @($result.Checks).Count

    return [PSCustomObject]$result
}

#endregion

Export-ModuleMember -Function @(
    # Concurrent Write Testing
    'Test-ConcurrentWrites',
    'Test-ConcurrencyDataIntegrity',
    # Lock Monitoring
    'Start-LockMonitoring',
    'Record-LockEvent',
    'Get-LockMetrics',
    'Get-LockEvents',
    # Repair
    'Repair-AccessDatabase',
    'Test-DatabaseHealth',
    # Backup
    'New-DatabaseBackup',
    'Get-DatabaseBackups',
    'Restore-DatabaseBackup',
    # Integrity
    'Test-DatabaseIntegrity'
)
