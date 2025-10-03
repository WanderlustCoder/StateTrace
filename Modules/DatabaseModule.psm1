Set-StrictMode -Version Latest

<#+
Ensure a global debug flag exists.  Under strict mode, referencing an
undefined variable produces an error.  Some functions in this module
conditionally emit debug messages based on `$Global:StateTraceDebug`.
If the variable hasn't been set elsewhere (e.g. by the UI module), it
will be undefined and strict mode will throw.  Define it here with
a default value of `$false` when it does not already exist.
#>
if (-not (Get-Variable -Name StateTraceDebug -Scope Global -ErrorAction SilentlyContinue)) {
    Set-Variable -Scope Global -Name StateTraceDebug -Value $false -Option None
}

# Cache the last time we forced a Jet/ACE cache refresh
if (-not (Get-Variable -Name LastCacheRefresh -Scope Script -ErrorAction SilentlyContinue)) { $script:LastCacheRefresh = Get-Date '2000-01-01' }

# Escape single quotes when embedding values into SQL statements.
function Get-SqlLiteral {
    param([Parameter(Mandatory)][string]$Value)
    return $Value.Replace("'", "''")
}

function Invoke-AccessDatabase32BitCreation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Provider,
        [Parameter(Mandatory)][int]$Engine
    )

    $sysWowPath = Join-Path $env:WINDIR 'SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $sysWowPath)) {
        throw "32-bit PowerShell executable not found at '$sysWowPath'."
    }

    $parentDir = Split-Path -Path $Path -Parent
    if ($parentDir -and -not (Test-Path -LiteralPath $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }

    $scriptContent = @"
param(
    [Parameter(Mandatory=`$true)][string]`$Path,
    [Parameter(Mandatory=`$true)][string]`$Provider,
    [Parameter(Mandatory=`$true)][int]`$Engine
)

`$ErrorActionPreference = 'Stop'
`$parentDir = Split-Path -Path `$Path -Parent
if (`$parentDir -and -not (Test-Path -LiteralPath `$parentDir)) {
    New-Item -ItemType Directory -Path `$parentDir -Force | Out-Null
}

`$catalog = `$null
try {
    `$catalog = New-Object -ComObject ADOX.Catalog
    `$connectionString = "Provider=`$Provider;Data Source=`$Path;Jet OLEDB:Engine Type=`$Engine;"
    `$null = `$catalog.Create(`$connectionString)
} finally {
    if (`$catalog) {
        [System.Runtime.Interopservices.Marshal]::ReleaseComObject(`$catalog) | Out-Null
    }
}
"@

    $tempFile = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetTempFileName(), '.ps1')
    Set-Content -Path $tempFile -Value $scriptContent -Encoding ASCII

    $process = $null
    try {
        $arguments = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$tempFile,'-Path',$Path,'-Provider',$Provider,'-Engine',$Engine)
        $process = Start-Process -FilePath $sysWowPath -ArgumentList $arguments -PassThru -WindowStyle Hidden
        if (-not $process) {
            throw "Failed to start 32-bit PowerShell for Access database creation."
        }

        $process.WaitForExit()
        if ($process.ExitCode -ne 0) {
            throw "32-bit PowerShell exited with code $($process.ExitCode)."
        }
    } finally {
        if ($process) {
            $process.Dispose()
        }
        if (Test-Path -LiteralPath $tempFile) {
            Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
        }
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "32-bit fallback completed but database '$Path' was not created."
    }
}
###

function Open-DbReadSession {
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DatabasePath
    )
    $conn = $null
    $opened = $false
    try {
        $conn = New-Object System.Data.OleDb.OleDbConnection
        $providerErrors = [System.Collections.Generic.List[object]]::new()
        foreach ($prov in @('Microsoft.ACE.OLEDB.12.0','Microsoft.Jet.OLEDB.4.0')) {
            try {
                $conn.ConnectionString = "Provider=$prov;Data Source=$DatabasePath"
                $conn.Open()
                $opened = $true
                if ($Global:StateTraceDebug) {
                    Write-Host ("[DEBUG] Opened read session using provider '{0}'" -f $prov) -ForegroundColor Cyan
                }
                break
            } catch {
                $errorMessage = $_.Exception.Message
                $hresult = $null
                try { $hresult = ('0x{0:X8}' -f $_.Exception.HResult) } catch { }
                $providerErrors.Add([PSCustomObject]@{
                    Provider = $prov
                    Message  = $errorMessage
                    HResult  = $hresult
                })
                if ($Global:StateTraceDebug) {
                    Write-Host ("[DEBUG] Provider '{0}' failed to open read session: {1}" -f $prov, $errorMessage) -ForegroundColor Cyan
                }
            }
        }
        if (-not $opened) {
            $candidateList = 'Microsoft.ACE.OLEDB.12.0, Microsoft.Jet.OLEDB.4.0'
            $detailText = 'No provider-specific diagnostics were captured.'
            if ($providerErrors.Count -gt 0) {
                $detailLines = foreach ($entry in $providerErrors) {
                    $hrNote = if ($entry.HResult) { " (HRESULT=$($entry.HResult))" } else { '' }
                    "- Provider '{0}': {1}{2}" -f $entry.Provider, $entry.Message, $hrNote
                }
                $detailText = [string]::Join([System.Environment]::NewLine, $detailLines)
            }
            throw "Failed to open Access database '$DatabasePath' for read operations. Tried providers: $candidateList.`n$detailText"
        }

        # Construct a disposable session object.  The Close and Dispose
        $session = [PSCustomObject]@{
            PSTypeName = 'StateTrace.DbReadSession'
            Connection = $conn
            Close = {
                param()
                try {
                    if ($this.Connection -and $this.Connection.State -ne [System.Data.ConnectionState]::Closed) {
                        $this.Connection.Close()
                    }
                } catch {}
                if ($this.Connection) {
                    try { $this.Connection.Dispose() } catch {}
                }
                $this.Connection = $null
            }
            Dispose = { $this.Close.Invoke() }
        }
        return $session
    } catch {
        if ($conn) { try { $conn.Dispose() } catch {} }
        throw
    }
}

function Close-DbReadSession {
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Session
    )
    if ($Session -and ($Session.PSTypeName -eq 'StateTrace.DbReadSession')) {
        try { $Session.Dispose() } catch {}
    }
}

function New-AccessDatabase {
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$Path
    )

    # Resolve default path if none was supplied.  The default is a
    if (-not $Path) {
        $dataDir = Join-Path $PSScriptRoot '..\Data'
        if (-not (Test-Path $dataDir)) {
            New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
        }
        $Path = Join-Path $dataDir 'StateTrace.mdb'
    }

    # Ensure the parent directory exists.
    $parentDir = Split-Path $Path -Parent
    if (-not (Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }

    # If the database does not exist, create it using ADOX.  The provider and engine
    $needsCreate = -not (Test-Path $Path)
    if ($needsCreate) {
        if ($Global:StateTraceDebug) {
            Write-Host "[DEBUG] Creating new Access database at '$Path'" -ForegroundColor Cyan
        }

        $ext = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
        $providerCandidates = @()
        if ($ext -eq '.accdb') {
            $providerCandidates += 'Microsoft.ACE.OLEDB.16.0'
            $providerCandidates += 'Microsoft.ACE.OLEDB.12.0'
        }
        $providerCandidates += 'Microsoft.Jet.OLEDB.4.0'

        $creationDiagnostics = [System.Collections.Generic.List[string]]::new()
        $databaseCreated = $false

        foreach ($providerCandidate in $providerCandidates) {
            $cat = $null
            $engine = if ($providerCandidate -like 'Microsoft.Jet*') { 5 } else { 6 }

            try {
                $cat = New-Object -ComObject ADOX.Catalog
                $connStr = "Provider=$providerCandidate;Data Source=$Path;Jet OLEDB:Engine Type=$engine;"
                $null = $cat.Create($connStr)
                $databaseCreated = Test-Path -LiteralPath $Path
                if ($databaseCreated) {
                    if ($Global:StateTraceDebug) {
                        Write-Host "[DEBUG] Created Access database using provider '$providerCandidate' at '$Path'" -ForegroundColor Cyan
                    }
                    break
                }
            } catch {
                $creationDiagnostics.Add("Provider '$providerCandidate': `$($_.Exception.Message)")
                if ([Environment]::Is64BitProcess) {
                    try {
                        Invoke-AccessDatabase32BitCreation -Path $Path -Provider $providerCandidate -Engine $engine
                        $databaseCreated = Test-Path -LiteralPath $Path
                        if ($databaseCreated) {
                            if ($Global:StateTraceDebug) {
                                Write-Host "[DEBUG] Created Access database via 32-bit fallback using provider '$providerCandidate' at '$Path'" -ForegroundColor Cyan
                            }
                            break
                        }
                    } catch {
                        $creationDiagnostics.Add("32-bit fallback for provider '$providerCandidate': `$($_.Exception.Message)")
                    }
                }
            } finally {
                if ($cat) {
                    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($cat) | Out-Null
                }
            }
        }

        if (-not $databaseCreated) {
            $detailText = if ($creationDiagnostics.Count -gt 0) { [string]::Join([System.Environment]::NewLine, $creationDiagnostics) } else { 'No provider-specific diagnostics were captured.' }
            throw "Failed to create Access database at '$Path'. Tried providers: $([string]::Join(', ', $providerCandidates)).`n$detailText"
        }
    }

    $createSummaryTable = @'
CREATE TABLE DeviceSummary (
    Hostname           TEXT(64)    PRIMARY KEY,
    Make               TEXT(64),
    Model              TEXT(64),
    Uptime             TEXT(64),
    Site               TEXT(64),
    Building           TEXT(64),
    Room               TEXT(64),
    Ports              INTEGER,
    AuthDefaultVLAN    TEXT(32),
    AuthBlock          MEMO
);
'@

    $createInterfacesTable = @'
CREATE TABLE Interfaces (
    ID                COUNTER      PRIMARY KEY,
    Hostname          TEXT(64),
    Port              TEXT(64),
    Name              TEXT(128),
    Status            TEXT(32),
    VLAN              INTEGER,
    Duplex            TEXT(32),
    Speed             TEXT(32),
    Type              TEXT(32),
    LearnedMACs       MEMO,
    AuthState         TEXT(32),
    AuthMode          TEXT(32),
    AuthClientMAC     TEXT(64),
    AuthTemplate      TEXT(64),
    Config            MEMO,
    PortColor         TEXT(32),
    ConfigStatus      TEXT(32),
    ToolTip           MEMO,
    FOREIGN KEY (Hostname) REFERENCES DeviceSummary (Hostname)
);
'@

    $createDeviceHistoryTable = @'
CREATE TABLE DeviceHistory (
    ID               COUNTER PRIMARY KEY,
    Hostname         TEXT(64),
    RunDate          DATETIME,
    Make             TEXT(64),
    Model            TEXT(64),
    Uptime           TEXT(64),
    Site             TEXT(64),
    Building         TEXT(64),
    Room             TEXT(64),
    Ports            INTEGER,
    AuthDefaultVLAN  TEXT(32),
    AuthBlock        MEMO
);
'@

    $createInterfaceHistoryTable = @'
CREATE TABLE InterfaceHistory (
    ID                COUNTER PRIMARY KEY,
    Hostname          TEXT(64),
    RunDate           DATETIME,
    Port              TEXT(64),
    Name              TEXT(128),
    Status            TEXT(32),
    VLAN              INTEGER,
    Duplex            TEXT(32),
    Speed             TEXT(32),
    Type              TEXT(32),
    LearnedMACs       MEMO,
    AuthState         TEXT(32),
    AuthMode          TEXT(32),
    AuthClientMAC     TEXT(64),
    AuthTemplate      TEXT(64),
    Config            MEMO,
    PortColor         TEXT(32),
    ConfigStatus      TEXT(32),
    ToolTip           MEMO
);
'@

    try {
        $connection = New-Object -ComObject ADODB.Connection
        $opened = $false
        # Try the ACE provider first as it supports both .accdb and .mdb.  Fall
        $providerErrors = [System.Collections.Generic.List[object]]::new()
        foreach ($prov in @('Microsoft.ACE.OLEDB.12.0','Microsoft.Jet.OLEDB.4.0')) {
            try {
                $connection.Open("Provider=$prov;Data Source=$Path")
                $opened = $true
                if ($Global:StateTraceDebug) {
                    Write-Host ("[DEBUG] Opened Access database '{0}' using provider '{1}'" -f $Path, $prov) -ForegroundColor Cyan
                }
                break
            } catch {
                $errorMessage = $_.Exception.Message
                $hresult = $null
                try { $hresult = ('0x{0:X8}' -f $_.Exception.HResult) } catch { }
                $providerErrors.Add([PSCustomObject]@{
                    Provider = $prov
                    Message  = $errorMessage
                    HResult  = $hresult
                })
                if ($Global:StateTraceDebug) {
                    Write-Host ("[DEBUG] Provider '{0}' failed to open '{1}': {2}" -f $prov, $Path, $errorMessage) -ForegroundColor Cyan
                }
                try { $connection.Close() } catch { }
            }
        }
        if (-not $opened) {
            $candidateList = 'Microsoft.ACE.OLEDB.12.0, Microsoft.Jet.OLEDB.4.0'
            $detailText = 'No provider-specific diagnostics were captured.'
            if ($providerErrors.Count -gt 0) {
                $detailLines = foreach ($entry in $providerErrors) {
                    $hrNote = if ($entry.HResult) { " (HRESULT=$($entry.HResult))" } else { '' }
                    "- Provider '{0}': {1}{2}" -f $entry.Provider, $entry.Message, $hrNote
                }
                $detailText = [string]::Join([System.Environment]::NewLine, $detailLines)
            }
            throw "Failed to open Access database '$Path'. Tried providers: $candidateList.`n$detailText"
        }
        # Attempt to create DeviceSummary table if it doesn't exist
        try { $connection.Execute($createSummaryTable) | Out-Null } catch { }
        # Attempt to create Interfaces table if it doesn't exist
        try { $connection.Execute($createInterfacesTable) | Out-Null } catch { }
        # Attempt to create history tables if they don't exist
        try { $connection.Execute($createDeviceHistoryTable) | Out-Null } catch { }
        try { $connection.Execute($createInterfaceHistoryTable) | Out-Null } catch { }

        # Helpful indexes (ignore if they already exist)
        $createIndexes = @(
            "CREATE INDEX idx_devicesummary_host ON DeviceSummary (Hostname)",
            "CREATE INDEX idx_interfaces_host_port ON Interfaces (Hostname, Port)"
        )
        foreach ($stmt in $createIndexes) {
            try { $connection.Execute($stmt) | Out-Null } catch { }
        }
        $alterStmts = @(
            "ALTER TABLE Interfaces ADD COLUMN AuthTemplate TEXT(64)",
            "ALTER TABLE Interfaces ADD COLUMN Config MEMO",
            "ALTER TABLE Interfaces ADD COLUMN PortColor TEXT(32)",
            "ALTER TABLE Interfaces ADD COLUMN ConfigStatus TEXT(32)",
            "ALTER TABLE Interfaces ADD COLUMN ToolTip MEMO",
            "ALTER TABLE DeviceSummary ADD COLUMN AuthBlock MEMO",
            "ALTER TABLE DeviceHistory ADD COLUMN AuthBlock MEMO"
        )
        foreach ($stmt in $alterStmts) {
            try {
                $connection.Execute($stmt) | Out-Null
            } catch {
                # Swallow errors (e.g. column already exists)
            }
        }
        $connection.Close()
    } catch {
        Write-Warning "Failed to create tables in the Access database. $_"
        throw
    }
    return $Path
}

function Invoke-DbQuery {
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$DatabasePath,
        [Parameter(Mandatory=$true)]
        [string]$Sql,
        [Parameter()][object]$Session
    )

    # Use the provided session connection if available and valid, otherwise
    $mustClose = $false
    $conn = $null
    try {
        if ($Session -and $Session.PSTypeName -eq 'StateTrace.DbReadSession' -and $Session.Connection) {
            $conn = $Session.Connection
        } else {
            # Open a one‑shot connection
            $conn = New-Object System.Data.OleDb.OleDbConnection
            $opened = $false
            $providerErrors = [System.Collections.Generic.List[object]]::new()
            foreach ($prov in @('Microsoft.ACE.OLEDB.12.0','Microsoft.Jet.OLEDB.4.0')) {
                try {
                    $conn.ConnectionString = "Provider=$prov;Data Source=$DatabasePath"
                    $conn.Open()
                    $opened = $true
                    if ($Global:StateTraceDebug) {
                        Write-Host ("[DEBUG] Opened ad-hoc query connection using provider '{0}'" -f $prov) -ForegroundColor Cyan
                    }
                    break
                } catch {
                    $errorMessage = $_.Exception.Message
                    $hresult = $null
                    try { $hresult = ('0x{0:X8}' -f $_.Exception.HResult) } catch { }
                    $providerErrors.Add([PSCustomObject]@{
                        Provider = $prov
                        Message  = $errorMessage
                        HResult  = $hresult
                    })
                    if ($Global:StateTraceDebug) {
                        Write-Host ("[DEBUG] Provider '{0}' failed to open ad-hoc query connection: {1}" -f $prov, $errorMessage) -ForegroundColor Cyan
                    }
                }
            }
            if (-not $opened) {
                $candidateList = 'Microsoft.ACE.OLEDB.12.0, Microsoft.Jet.OLEDB.4.0'
                $detailText = 'No provider-specific diagnostics were captured.'
                if ($providerErrors.Count -gt 0) {
                    $detailLines = foreach ($entry in $providerErrors) {
                        $hrNote = if ($entry.HResult) { " (HRESULT=$($entry.HResult))" } else { '' }
                        "- Provider '{0}': {1}{2}" -f $entry.Provider, $entry.Message, $hrNote
                    }
                    $detailText = [string]::Join([System.Environment]::NewLine, $detailLines)
                }
                throw "Failed to open Access database '$DatabasePath' for query execution. Tried providers: $candidateList.`n$detailText"
            }
            $mustClose = $true
        }

        $dataTable = New-Object System.Data.DataTable
        $adapter = New-Object System.Data.OleDb.OleDbDataAdapter($Sql, $conn)
        [void]$adapter.Fill($dataTable)
        return ,$dataTable
    } finally {
        # Close and dispose connection only if we opened it (mustClose=true).
        if ($mustClose -and $conn) {
            try {
                if ($conn.State -ne [System.Data.ConnectionState]::Closed) { $conn.Close() }
            } catch {}
            try { $conn.Dispose() } catch {}
        }
    }
}

Export-ModuleMember -Function Get-SqlLiteral, New-AccessDatabase, Invoke-DbQuery, Open-DbReadSession, Close-DbReadSession






