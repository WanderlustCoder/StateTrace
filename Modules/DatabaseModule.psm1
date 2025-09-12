

Set-StrictMode -Version Latest

# Cache the last time we forced a Jet/ACE cache refresh
if (-not (Get-Variable -Name LastCacheRefresh -Scope Script -ErrorAction SilentlyContinue)) { $script:LastCacheRefresh = Get-Date '2000-01-01' }

# === BEGIN Initialize-StateTraceDatabase (DatabaseModule.psm1) ===
function Initialize-StateTraceDatabase {
    [CmdletBinding()]
    param(
        [string]$DataDir = (Join-Path $PSScriptRoot '..\Data')
    )
    begin {
        try {
            # Ensure the Data directory exists but do not create any database.
            [void][IO.Directory]::CreateDirectory($DataDir)
        } catch {
            throw ("Unable to access or create Data directory at {0}: {1}" -f $DataDir, $_.Exception.Message)
        }
    }
    process {
        # Per-site databases are created on demand by the parser.  Do not
        # initialize a global StateTrace database or set global variables here.
        # Leave $global:StateTraceDb and $env:StateTraceDbPath unset so that
        # each module can determine its own database path based on the host.
        return $null
    }
}
# === END Initialize-StateTraceDatabase (DatabaseModule.psm1) ===

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
        foreach ($prov in @('Microsoft.ACE.OLEDB.12.0','Microsoft.Jet.OLEDB.4.0')) {
            try {
                $conn.ConnectionString = "Provider=$prov;Data Source=$DatabasePath"
                $conn.Open()
                $opened = $true
                break
            } catch {
                # try next provider
            }
        }
        if (-not $opened) { throw "No suitable OLE DB provider found." }

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
        Write-Host "[DEBUG] Creating new Access database at '$Path'" -ForegroundColor Cyan
        # Determine file extension and provider/engine type accordingly.
        $ext = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
        $provider = 'Microsoft.Jet.OLEDB.4.0'
        $engine   = 5  # Jet 4.0 (Access 2000/2003)
        if ($ext -eq '.accdb') {
            $provider = 'Microsoft.ACE.OLEDB.12.0'
            $engine   = 6  # ACE 2007
        }
        try {
            # Use ADOX Catalog to create the database.  ADOX is part of the
            $cat = New-Object -ComObject ADOX.Catalog
            $connStr = "Provider=$provider;Data Source=$Path;Jet OLEDB:Engine Type=$engine;"
            $null = $cat.Create($connStr)
            # Release COM object
            [System.Runtime.Interopservices.Marshal]::ReleaseComObject($cat) | Out-Null
        } catch {
            Write-Warning "Failed to create the Access database using ADOX: $($_.Exception.Message)"
            throw
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
        foreach ($prov in @('Microsoft.ACE.OLEDB.12.0','Microsoft.Jet.OLEDB.4.0')) {
            try {
                $connection.Open("Provider=$prov;Data Source=$Path")
                $opened = $true
                break
            } catch {
                # try next provider
            }
        }
        if (-not $opened) {
            throw "No suitable OLEDB provider found to open Access database. Install the Microsoft ACE OLEDB provider."
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

function Invoke-DbNonQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DatabasePath,
        [Parameter(Mandatory)][string]$Sql
    )
    $conn = New-Object System.Data.OleDb.OleDbConnection
    $opened = $false
    foreach ($prov in @('Microsoft.ACE.OLEDB.12.0','Microsoft.Jet.OLEDB.4.0')) {
        try {
            $conn.ConnectionString = "Provider=$prov;Data Source=$DatabasePath"
            $conn.Open(); $opened = $true; break
        } catch { }
    }
    if (-not $opened) { throw "No suitable OLE DB provider found." }
    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = $Sql
        [void]$cmd.ExecuteNonQuery()
    } finally {
        if ($conn.State -ne [System.Data.ConnectionState]::Closed) { $conn.Close() }
    }
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
            foreach ($prov in @('Microsoft.ACE.OLEDB.12.0','Microsoft.Jet.OLEDB.4.0')) {
                try {
                    $conn.ConnectionString = "Provider=$prov;Data Source=$DatabasePath"
                    $conn.Open()
                    $opened = $true
                    break
                } catch {
                    # try next provider
                }
            }
            if (-not $opened) { throw "No suitable OLE DB provider found." }
            $mustClose = $true
        }

        $dataTable = New-Object System.Data.DataTable
        $adapter = New-Object System.Data.OleDb.OleDbDataAdapter($Sql, $conn)
        [void]$adapter.Fill($dataTable)
        return $dataTable
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


Export-ModuleMember -Function New-AccessDatabase, Invoke-DbNonQuery, Invoke-DbQuery, Initialize-StateTraceDatabase, Open-DbReadSession, Close-DbReadSession