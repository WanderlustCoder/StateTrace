# DatabaseConnectionPool.psm1
# Provides connection pooling for ADODB database connections to reduce connection overhead.

Set-StrictMode -Version Latest

# Pool configuration
$script:PoolMaxSize = 4                  # Max connections per database
$script:PoolIdleTimeoutMs = 300000       # 5 minutes idle timeout
$script:PoolValidationIntervalMs = 30000 # Validate every 30 seconds

# Connection pools keyed by database path (case-insensitive)
$script:ConnectionPools = @{}
$script:PoolLock = [System.Threading.ReaderWriterLockSlim]::new()

class PooledConnection {
    [object]$Connection
    [string]$DatabasePath
    [datetime]$CreatedAt
    [datetime]$LastUsedAt
    [bool]$InUse
    [string]$Provider
}

function Get-PoolKey {
    param([string]$DatabasePath)
    return $DatabasePath.ToLowerInvariant()
}

function Test-ConnectionValid {
    param([object]$Connection)

    if (-not $Connection) { return $false }

    try {
        # Check if connection is still open and responsive
        if ($Connection.State -ne 1) { return $false }  # 1 = adStateOpen

        # Execute a simple query to verify connection is alive
        $null = $Connection.Execute("SELECT 1")
        return $true
    } catch {
        return $false
    }
}

function New-PooledConnection {
    param(
        [string]$DatabasePath,
        [string]$PreferredProvider
    )

    $connection = New-Object -ComObject ADODB.Connection
    $opened = $false
    $usedProvider = $null

    # Try preferred provider first if specified
    $providers = @('Microsoft.ACE.OLEDB.12.0', 'Microsoft.Jet.OLEDB.4.0')
    if ($PreferredProvider -and $PreferredProvider -in $providers) {
        $providers = @($PreferredProvider) + @($providers | Where-Object { $_ -ne $PreferredProvider })
    }

    foreach ($prov in $providers) {
        try {
            $connection.Open(("Provider={0};Data Source={1}" -f $prov, $DatabasePath))
            $opened = $true
            $usedProvider = $prov
            break
        } catch {
            try { $connection.Close() } catch { }
        }
    }

    if (-not $opened) {
        if ($connection -is [System.__ComObject]) {
            try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($connection) } catch { }
        }
        throw "Failed to open connection to '$DatabasePath' with any available provider."
    }

    $pooled = [PooledConnection]::new()
    $pooled.Connection = $connection
    $pooled.DatabasePath = $DatabasePath
    $pooled.CreatedAt = [datetime]::UtcNow
    $pooled.LastUsedAt = [datetime]::UtcNow
    $pooled.InUse = $false
    $pooled.Provider = $usedProvider

    return $pooled
}

function Get-PooledDbConnection {
    <#
    .SYNOPSIS
    Gets a connection from the pool, creating one if necessary.
    .PARAMETER DatabasePath
    The path to the Access database file.
    .OUTPUTS
    Returns a PooledConnection object with the ADODB connection.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DatabasePath
    )

    if (-not (Test-Path -LiteralPath $DatabasePath)) {
        throw "Database file not found: '$DatabasePath'"
    }

    $key = Get-PoolKey -DatabasePath $DatabasePath
    $acquired = $false
    $pooledConn = $null

    try {
        $script:PoolLock.EnterUpgradeableReadLock()
        $acquired = $true

        # Check if pool exists for this database
        if (-not $script:ConnectionPools.ContainsKey($key)) {
            $script:PoolLock.EnterWriteLock()
            try {
                if (-not $script:ConnectionPools.ContainsKey($key)) {
                    $script:ConnectionPools[$key] = [System.Collections.Generic.List[PooledConnection]]::new()
                }
            } finally {
                $script:PoolLock.ExitWriteLock()
            }
        }

        $pool = $script:ConnectionPools[$key]
        $now = [datetime]::UtcNow

        # Try to find an available connection in the pool
        $script:PoolLock.EnterWriteLock()
        try {
            # First, clean up expired/invalid connections
            $toRemove = @()
            foreach ($conn in $pool) {
                if (-not $conn.InUse) {
                    $idleMs = ($now - $conn.LastUsedAt).TotalMilliseconds
                    if ($idleMs -gt $script:PoolIdleTimeoutMs) {
                        $toRemove += $conn
                    }
                }
            }
            foreach ($conn in $toRemove) {
                try {
                    if ($conn.Connection) {
                        $conn.Connection.Close()
                        if ($conn.Connection -is [System.__ComObject]) {
                            [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($conn.Connection)
                        }
                    }
                } catch { }
                $pool.Remove($conn) | Out-Null
            }

            # Find an available valid connection
            foreach ($conn in $pool) {
                if (-not $conn.InUse) {
                    if (Test-ConnectionValid -Connection $conn.Connection) {
                        $conn.InUse = $true
                        $conn.LastUsedAt = $now
                        $pooledConn = $conn
                        break
                    } else {
                        # Connection is invalid, remove it
                        try {
                            $conn.Connection.Close()
                            if ($conn.Connection -is [System.__ComObject]) {
                                [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($conn.Connection)
                            }
                        } catch { }
                        $pool.Remove($conn) | Out-Null
                    }
                }
            }

            # No available connection, create new one if under limit
            if (-not $pooledConn -and $pool.Count -lt $script:PoolMaxSize) {
                $preferredProvider = $null
                if ($pool.Count -gt 0) {
                    $preferredProvider = $pool[0].Provider
                }
                $pooledConn = New-PooledConnection -DatabasePath $DatabasePath -PreferredProvider $preferredProvider
                $pooledConn.InUse = $true
                $pool.Add($pooledConn)
            }
        } finally {
            $script:PoolLock.ExitWriteLock()
        }

        # If still no connection (pool at max), wait and retry
        if (-not $pooledConn) {
            $retryCount = 0
            $maxRetries = 10
            while (-not $pooledConn -and $retryCount -lt $maxRetries) {
                Start-Sleep -Milliseconds 100
                $retryCount++

                $script:PoolLock.EnterWriteLock()
                try {
                    foreach ($conn in $pool) {
                        if (-not $conn.InUse) {
                            if (Test-ConnectionValid -Connection $conn.Connection) {
                                $conn.InUse = $true
                                $conn.LastUsedAt = [datetime]::UtcNow
                                $pooledConn = $conn
                                break
                            }
                        }
                    }
                } finally {
                    $script:PoolLock.ExitWriteLock()
                }
            }
        }

        if (-not $pooledConn) {
            throw "Connection pool exhausted for '$DatabasePath'. All connections are in use."
        }

        return $pooledConn

    } finally {
        if ($acquired) {
            $script:PoolLock.ExitUpgradeableReadLock()
        }
    }
}

function Release-PooledDbConnection {
    <#
    .SYNOPSIS
    Returns a connection to the pool for reuse.
    .PARAMETER PooledConnection
    The PooledConnection object to release.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][PooledConnection]$PooledConnection
    )

    if (-not $PooledConnection) { return }

    $PooledConnection.InUse = $false
    $PooledConnection.LastUsedAt = [datetime]::UtcNow
}

function Close-AllPooledConnections {
    <#
    .SYNOPSIS
    Closes all pooled connections and clears the pools.
    #>
    [CmdletBinding()]
    param()

    $script:PoolLock.EnterWriteLock()
    try {
        foreach ($key in @($script:ConnectionPools.Keys)) {
            $pool = $script:ConnectionPools[$key]
            foreach ($conn in @($pool)) {
                try {
                    if ($conn.Connection) {
                        $conn.Connection.Close()
                        if ($conn.Connection -is [System.__ComObject]) {
                            [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($conn.Connection)
                        }
                    }
                } catch { }
            }
            $pool.Clear()
        }
        $script:ConnectionPools.Clear()
    } finally {
        $script:PoolLock.ExitWriteLock()
    }
}

function Get-ConnectionPoolStats {
    <#
    .SYNOPSIS
    Returns statistics about the connection pools.
    #>
    [CmdletBinding()]
    param()

    $stats = @()

    $script:PoolLock.EnterReadLock()
    try {
        foreach ($key in $script:ConnectionPools.Keys) {
            $pool = $script:ConnectionPools[$key]
            $total = $pool.Count
            $inUse = @($pool | Where-Object { $_.InUse }).Count
            $available = $total - $inUse

            $stats += [PSCustomObject]@{
                DatabasePath = $key
                TotalConnections = $total
                InUse = $inUse
                Available = $available
                MaxSize = $script:PoolMaxSize
            }
        }
    } finally {
        $script:PoolLock.ExitReadLock()
    }

    return $stats
}

function Invoke-PooledDbQuery {
    <#
    .SYNOPSIS
    Executes a query using a pooled connection.
    .PARAMETER DatabasePath
    The path to the Access database file.
    .PARAMETER Sql
    The SQL query to execute.
    .OUTPUTS
    Returns an array of PSCustomObject rows.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DatabasePath,
        [Parameter(Mandatory)][string]$Sql
    )

    $pooledConn = $null
    try {
        $pooledConn = Get-PooledDbConnection -DatabasePath $DatabasePath
        $connection = $pooledConn.Connection

        $recordset = $connection.Execute($Sql)
        $results = [System.Collections.Generic.List[object]]::new()

        if ($recordset -and $recordset.State -eq 1) {
            $fieldCount = 0
            try { $fieldCount = [int]$recordset.Fields.Count } catch { $fieldCount = 0 }

            if ($fieldCount -gt 0) {
                $fieldNames = New-Object string[] $fieldCount
                for ($i = 0; $i -lt $fieldCount; $i++) {
                    try { $fieldNames[$i] = '' + $recordset.Fields.Item($i).Name } catch { $fieldNames[$i] = '' }
                }

                $rawRows = $null
                try { $rawRows = $recordset.GetRows() } catch { $rawRows = $null }

                if ($rawRows -and ($rawRows.Rank -ge 2)) {
                    $rowCount = 0
                    try { $rowCount = $rawRows.GetUpperBound(1) + 1 } catch { $rowCount = 0 }

                    for ($rowIndex = 0; $rowIndex -lt $rowCount; $rowIndex++) {
                        $rowMap = [ordered]@{}
                        for ($fieldIndex = 0; $fieldIndex -lt $fieldCount; $fieldIndex++) {
                            $name = $fieldNames[$fieldIndex]
                            if ([string]::IsNullOrWhiteSpace($name)) { continue }

                            $value = $null
                            try { $value = $rawRows[$fieldIndex, $rowIndex] } catch { $value = $null }
                            if ($value -eq [System.DBNull]::Value) { $value = $null }
                            $rowMap[$name] = $value
                        }
                        [void]$results.Add([pscustomobject]$rowMap)
                    }
                }
            }
        }

        if ($recordset) {
            try { $recordset.Close() } catch { }
            if ($recordset -is [System.__ComObject]) {
                try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($recordset) } catch { }
            }
        }

        return ,$results.ToArray()

    } finally {
        if ($pooledConn) {
            Release-PooledDbConnection -PooledConnection $pooledConn
        }
    }
}

Export-ModuleMember -Function Get-PooledDbConnection, Release-PooledDbConnection, Close-AllPooledConnections, Get-ConnectionPoolStats, Invoke-PooledDbQuery
