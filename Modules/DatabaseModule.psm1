<#
    .SYNOPSIS
    Helper module for working with a Microsoft Access database.

    This module encapsulates the logic required to create and work with an
    Access database using ADO via the COM interfaces available in Windows.

    The primary purpose of this module is to provide the network log reader
    application with a light‑weight database backend.  Storing parsed
    information in a database instead of memory or CSV files reduces
    memory pressure and enables much more efficient querying of the data
    when the user interacts with the GUI.

    The module exposes the following public functions:

        * New-AccessDatabase      – Creates a new Access database file and
                                     populates it with the required tables
                                     if it does not already exist.
        * Invoke-DbNonQuery        – Executes an INSERT/UPDATE/DELETE or
                                     DDL statement against the database.
        * Invoke-DbQuery           – Executes a SELECT statement and
                                     returns the results as a DataTable.

    You can import this module from your main script using

        Import-Module (Join-Path $scriptDir '..\Modules\DatabaseModule.psm1')

    Note that this module relies on the presence of the Microsoft Jet or
    ACE OLEDB providers.  On a 64‑bit system, the ACE provider
    (`Microsoft.ACE.OLEDB.12.0`) is required for `.accdb` files.  For
    simplicity, this module uses the Jet provider (`Microsoft.Jet.OLEDB.4.0`)
    and creates an Access 2002/2003 format `.mdb` file.
#>

Set-StrictMode -Version Latest

# === BEGIN Initialize-StateTraceDatabase (DatabaseModule.psm1) ===
function Initialize-StateTraceDatabase {
    [CmdletBinding()]
    param(
        # Allow override, but default to project Data folder relative to this module.
        [string]$DataDir = (Join-Path $PSScriptRoot '..\Data')
    )
    begin {
        try {
            [void][IO.Directory]::CreateDirectory($DataDir)
        } catch {
            throw ("Unable to access or create Data directory at {0}: {1}" -f $DataDir, $_.Exception.Message)
        }
    }
    process {
        $accdbPath = Join-Path $DataDir 'StateTrace.accdb'
        $mdbPath   = Join-Path $DataDir 'StateTrace.mdb'
        $dbPath    = $null

        # Prefer existing DBs to avoid noisy �create� attempts.
        if (Test-Path $accdbPath -PathType Leaf) {
            $dbPath = $accdbPath
        } elseif (Test-Path $mdbPath -PathType Leaf) {
            $dbPath = $mdbPath
        } else {
            # Try modern .accdb first, then fall back to .mdb
            try {
                $null = New-AccessDatabase -Path $accdbPath
            } catch {
                Write-Warning ("Failed to create .accdb at {0}: {1}" -f $accdbPath, $_.Exception.Message)
            }

            if (Test-Path $accdbPath -PathType Leaf) {
                $dbPath = $accdbPath
            } else {
                try {
                    $null = New-AccessDatabase -Path $mdbPath
                } catch {
                    Write-Error ("Failed to create .mdb at {0}: {1}" -f $mdbPath, $_.Exception.Message)
                }
                if (Test-Path $mdbPath -PathType Leaf) {
                    $dbPath = $mdbPath
                }
            }
        }

        if (-not $dbPath) {
            throw ("Database initialization failed � no usable database in {0}" -f $DataDir)
        }

        # Publish locations for the rest of the app (and child processes).
        $global:StateTraceDb   = $dbPath
        $env:StateTraceDbPath  = $dbPath

        # Return the chosen path for callers that want it.
        return $dbPath
    }
}
# === END Initialize-StateTraceDatabase (DatabaseModule.psm1) ===

function New-AccessDatabase {
    <#
        .SYNOPSIS
            Creates the StateTrace Access database and tables if they do not exist.

        .DESCRIPTION
            This function checks for the presence of the StateTrace database at
            the provided path.  If the file is not present, it uses the
            Access.Application COM automation object to create a new database in
            the Access 2002/2003 format.  It then opens a connection to the
            database using ADO and creates two tables: DeviceSummary and
            Interfaces.  The DeviceSummary table stores per‑device metadata
            such as hostname, make, model and location; the Interfaces table
            stores per‑interface information including port, VLAN, duplex,
            authentication state and learned MAC addresses.  If the database
            already exists, the function simply returns without modifying
            anything.

        .PARAMETER Path
            The filesystem path where the `.mdb` file should be located.  If
            omitted, the database will be created in the `Data` folder under
            the project's root directory.  The caller is responsible for
            ensuring that the directory exists.

        .EXAMPLE
            New-AccessDatabase -Path "C:\Temp\StateTrace.mdb"

            Creates a new Access database at the specified location if it
            doesn't already exist and populates it with the required tables.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$Path
    )

    # Resolve default path if none was supplied.  The default is a
    # 'StateTrace.mdb' file in a 'Data' subfolder relative to the module
    # location.  We rely on $PSScriptRoot here rather than $scriptDir from
    # the main script because this module may be imported from multiple
    # contexts.
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
    # type depend on the file extension.  An .accdb file uses the ACE provider and
    # engine type 6 (Access 2007 format).  A .mdb file uses the Jet provider and
    # engine type 5 (Jet 4.0).  Falling back to Access.Application complicates
    # deployment because Access may not be installed.  Using ADOX avoids that
    # dependency and allows creation of either format solely via the data engine.
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
            # Microsoft Office data access components and is available on systems
            # with the ACE/Jet providers installed.  The Jet OLEDB:Engine Type
            # property controls the file format.  See https://support.microsoft.com/kb/271246
            $cat = New-Object -ComObject ADOX.Catalog
            $connStr = "Provider=$provider;Data Source=$Path;Jet OLEDB:Engine Type=$engine;"
            # The Create method returns a COM object representing the connection.
            # If we do not discard the return value, it will be emitted to the
            # pipeline and inadvertently become part of the function's return
            # value.  Assign the return to $null to suppress it, ensuring only
            # the database path is returned from this function.
            $null = $cat.Create($connStr)
            # Release COM object
            [System.Runtime.Interopservices.Marshal]::ReleaseComObject($cat) | Out-Null
        } catch {
            Write-Warning "Failed to create the Access database using ADOX: $($_.Exception.Message)"
            throw
        }
    }

    # Build the DDL statements to create the tables.  Note that Jet SQL
    # requires the use of square brackets around field names that are
    # reserved words or contain special characters.
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

    # Define the Interfaces table with additional columns for configuration
    # compliance.  AuthTemplate and Config store the template name and raw
    # interface configuration, respectively.  PortColor and ConfigStatus
    # capture the compliance result (e.g. green for match).  ToolTip stores
    # helpful descriptive text for UI hover.  MEMO is used for potentially
    # lengthy text values.
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

    # History tables allow storing all parsed runs.  DeviceHistory mirrors
    # DeviceSummary but includes a RunDate column.  InterfaceHistory mirrors
    # Interfaces but includes RunDate.  RunDate is stored as a DATETIME.
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

    # Ensure the tables exist using ADO.  We attempt to create the tables
    # regardless of whether the database was freshly created.  If a table
    # already exists, the CREATE TABLE statement will fail; we catch and
    # ignore the specific error.  This ensures that missing tables are
    # created while preserving existing data.
    try {
        $connection = New-Object -ComObject ADODB.Connection
        $opened = $false
        # Try the ACE provider first as it supports both .accdb and .mdb.  Fall
        # back to the older Jet provider if ACE is unavailable.
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

        # Ensure new compliance columns exist on the Interfaces table.  Earlier
        # versions of the database may not have included these columns.  Attempt
        # to add each column individually; ignore errors if the column already
        # exists.  These ALTER statements will succeed on Jet/ACE and will
        # gracefully no-op when the column is present.
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
    <#
        .SYNOPSIS
            Executes a SELECT statement against the Access database and returns a DataTable.

        .DESCRIPTION
            This function opens a connection to the specified database and
            executes the given SELECT statement.  The results are loaded
            into a .NET DataTable, which can be bound directly to WPF data
            grids or further manipulated in PowerShell.  The caller is
            responsible for disposing of the returned DataTable when it is
            no longer needed.

        .PARAMETER DatabasePath
            The path to the `.mdb` file.

        .PARAMETER Sql
            The SELECT statement to execute.  Use WHERE clauses to limit
            returned rows and improve performance.

        .EXAMPLE
            $dt = Invoke-DbQuery -DatabasePath $db -Sql "SELECT * FROM DeviceSummary"
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$DatabasePath,
        [Parameter(Mandatory=$true)]
        [string]$Sql
    )
    $connection = New-Object -ComObject ADODB.Connection
    $recordset  = $null
    $provider   = $null
    try {
        # Attempt to open the connection with available providers
        foreach ($prov in @('Microsoft.ACE.OLEDB.12.0','Microsoft.Jet.OLEDB.4.0')) {
            try {
                $connection.Open("Provider=$prov;Data Source=$DatabasePath")
                $provider = $prov
                break
            } catch {
                # try next provider
            }
        }
        if (-not $provider) { throw "No suitable OLEDB provider found." }
        # Debug output removed to reduce verbosity
        # Force Jet/ACE to flush writes and refresh its cache by opening a
        # lightweight ADODB connection and calling RefreshCache.  We do
        # this on a separate connection rather than the one used to fill
        # the DataTable.  If the provider does not support the method,
        # silently ignore the error.
        try {
            $cacheConn = New-Object -ComObject ADODB.Connection
            $cacheConn.Open("Provider=$provider;Data Source=$DatabasePath")
            try {
                $jet = New-Object -ComObject JRO.JetEngine
                $jet.RefreshCache($cacheConn)
            } catch {}
            $cacheConn.Close()
        } catch {}
        # Now open a purely managed OleDbConnection to execute the query and
        # fill a DataTable.  This avoids issues with COM DataRow objects
        # exposing unexpected members in PowerShell.
        $dataTable = New-Object System.Data.DataTable
        $oledbConnection = New-Object System.Data.OleDb.OleDbConnection("Provider=$provider;Data Source=$DatabasePath")
        try {
            $adapter = New-Object System.Data.OleDb.OleDbDataAdapter($Sql, $oledbConnection)
            [void]$adapter.Fill($dataTable)
        } finally {
            if ($oledbConnection) { $oledbConnection.Close() }
        }
        # Debug output removed to reduce verbosity
        return $dataTable
    } finally {
        if ($recordset -ne $null) {
            try { $recordset.Close() } catch {}
        }
        if ($connection -and $connection.State -ne 0) { $connection.Close() }
    }
}

Export-ModuleMember -Function New-AccessDatabase, Invoke-DbNonQuery, Invoke-DbQuery, Initialize-StateTraceDatabase