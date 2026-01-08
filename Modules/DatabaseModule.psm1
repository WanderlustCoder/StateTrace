Set-StrictMode -Version Latest

if (-not (Get-Variable -Name StateTraceDebug -Scope Global -ErrorAction SilentlyContinue)) {
    Set-Variable -Scope Global -Name StateTraceDebug -Value $false -Option None
}
try {
    TelemetryModule\Initialize-StateTraceDebug
} catch {
    Write-Warning ("Failed to initialize debug telemetry: {0}" -f $_.Exception.Message)
}

# Escape single quotes when embedding values into SQL statements.
function Get-SqlLiteral {
    param([Parameter(Mandatory)][string]$Value)
    return $Value.Replace("'", "''")
}

function Invoke-DbSchemaStatement {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Connection,
        [Parameter(Mandatory)][string]$Statement,
        [Parameter()][string]$Label,
        [switch]$IgnoreIfExists,
        [switch]$ContinueOnFailure
    )

    try {
        $null = $Connection.Execute($Statement)
        return $true
    } catch {
        $message = $_.Exception.Message
        if ($IgnoreIfExists -and $null -ne $message -and $message -match '(?i)already exists|duplicate') {
            return $false
        }

        $labelText = if ($Label) { $Label } else { $Statement }
        $hresultText = ''
        try { $hresultText = ' (HRESULT=0x{0:X8})' -f $_.Exception.HResult } catch { }
        $detailText = if ($hresultText) { "$message$hresultText" } else { $message }
        $warningText = "Failed to apply schema change '$labelText': $detailText"
        if ($ContinueOnFailure) {
            Write-Warning $warningText
            return $false
        }
        throw $warningText
    }
}

function ConvertTo-DbRowList {
    [CmdletBinding()]
    param(
        [Parameter()][object]$Data
    )

    $list = [System.Collections.Generic.List[object]]::new()
    if (-not $Data) { return @() }

    if ($Data -is [System.Data.DataTable]) {
        foreach ($row in $Data.Rows) { $null = $list.Add($row) }
        return ,$list.ToArray()
    }

    if ($Data -is [System.Collections.IEnumerable]) {
        foreach ($item in $Data) {
            if ($null -ne $item) { $null = $list.Add($item) }
        }
    }

    return $list.ToArray()
}

function Invoke-AccessDatabase32BitCreation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Provider,
        [Parameter(Mandatory)][int]$Engine,
        [int]$TimeoutSeconds = 60
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
    Set-Content -Path $tempFile -Value $scriptContent -Encoding UTF8

    $process = $null
    try {
        $arguments = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$tempFile,'-Path',$Path,'-Provider',$Provider,'-Engine',$Engine)
        $process = Start-Process -FilePath $sysWowPath -ArgumentList $arguments -PassThru -WindowStyle Hidden
        if (-not $process) {
            throw "Failed to start 32-bit PowerShell for Access database creation."
        }

        $timeoutMs = [Math]::Max(1000, ($TimeoutSeconds * 1000))
        $exited = $process.WaitForExit($timeoutMs)
        if (-not $exited) {
            $killError = $null
            try {
                $process.Kill()
                $process.WaitForExit(5000)
            } catch {
                $killError = $_.Exception.Message
            }
            if ($killError) {
                Write-Warning ("Failed to terminate 32-bit PowerShell after timeout while creating '{0}': {1}" -f $Path, $killError)
            }
            throw "32-bit PowerShell timed out after $TimeoutSeconds seconds while creating '$Path'."
        }
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

function Open-OleDbConnectionWithFallback {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DatabasePath,
        [Parameter(Mandatory)][string]$FailureContext,
        [Parameter(Mandatory)][string]$SuccessDebugTemplate,
        [Parameter(Mandatory)][string]$FailureDebugTemplate
    )

    $connection = New-Object System.Data.OleDb.OleDbConnection
    $providerErrors = [System.Collections.Generic.List[object]]::new()
    foreach ($prov in @('Microsoft.ACE.OLEDB.12.0','Microsoft.Jet.OLEDB.4.0')) {
        try {
            $connection.ConnectionString = "Provider=$prov;Data Source=$DatabasePath"
            $connection.Open()
            if ($Global:StateTraceDebug) {
                Write-Host ($SuccessDebugTemplate -f $prov) -ForegroundColor Cyan
            }
            return $connection
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
                Write-Host ($FailureDebugTemplate -f $prov, $errorMessage) -ForegroundColor Cyan
            }
        }
    }

    $disposeError = $null
    try { $connection.Dispose() } catch { $disposeError = $_.Exception.Message }
    if ($disposeError) {
        Write-Warning ("Failed to dispose Access connection after provider failures: {0}" -f $disposeError)
    }

    $candidateList = 'Microsoft.ACE.OLEDB.12.0, Microsoft.Jet.OLEDB.4.0'
    $detailText = 'No provider-specific diagnostics were captured.'
    if ($providerErrors.Count -gt 0) {
        $detailLines = foreach ($entry in $providerErrors) {
            $hrNote = if ($entry.HResult) { " (HRESULT=$($entry.HResult))" } else { '' }
            "- Provider '{0}': {1}{2}" -f $entry.Provider, $entry.Message, $hrNote
        }
        $detailText = [string]::Join([System.Environment]::NewLine, $detailLines)
    }
    throw "Failed to open Access database '$DatabasePath' $FailureContext. Tried providers: $candidateList.`n$detailText"
}

function Open-DbReadSession {
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DatabasePath
    )

    $conn = $null
    try {
        $conn = Open-OleDbConnectionWithFallback -DatabasePath $DatabasePath -FailureContext 'for read operations' -SuccessDebugTemplate "[DEBUG] Opened read session using provider '{0}'" -FailureDebugTemplate "[DEBUG] Provider '{0}' failed to open read session: {1}"

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
    if (Test-IsDbReadSession -Session $Session) {
        try { $Session.Dispose() } catch {}
    }
}

function Test-IsDbReadSession {
    [CmdletBinding()]
    param(
        [Parameter()][object]$Session
    )

    if (-not $Session) { return $false }

    try {
        if ($Session.PSObject -and $Session.PSObject.TypeNames -contains 'StateTrace.DbReadSession') {
            return $true
        }
    } catch { }

    try {
        if ($Session.PSTypeName -eq 'StateTrace.DbReadSession') {
            return $true
        }
    } catch { }

    return $false
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
                $creationDiagnostics.Add("Provider '$providerCandidate': $($_.Exception.Message)")
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
                        $creationDiagnostics.Add("32-bit fallback for provider '$providerCandidate': $($_.Exception.Message)")
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

    $createSpanInfoTable = @'
CREATE TABLE SpanInfo (
    Hostname    TEXT(64),
    Vlan        TEXT(32),
    RootSwitch  TEXT(64),
    RootPort    TEXT(32),
    Role        TEXT(32),
    Upstream    TEXT(64),
    LastUpdated DATETIME
);
'@

    $createSpanHistoryTable = @'
CREATE TABLE SpanHistory (
    ID          COUNTER     PRIMARY KEY,
    Hostname    TEXT(64),
    RunDate     DATETIME,
    Vlan        TEXT(32),
    RootSwitch  TEXT(64),
    RootPort    TEXT(32),
    Role        TEXT(32),
    Upstream    TEXT(64)
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

    $connection = $null
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
        # Schema versioning table for tracking migrations
        $createSchemaVersionTable = @'
CREATE TABLE SchemaVersion (
    ID              COUNTER     PRIMARY KEY,
    Version         INTEGER     NOT NULL,
    MigrationName   TEXT(128),
    AppliedAt       DATETIME,
    AppliedBy       TEXT(64)
);
'@

        $schemaStatements = @(
            @{ Label = 'Create SchemaVersion table'; Statement = $createSchemaVersionTable }
            @{ Label = 'Create DeviceSummary table'; Statement = $createSummaryTable }
            @{ Label = 'Create Interfaces table'; Statement = $createInterfacesTable }
            @{ Label = 'Create DeviceHistory table'; Statement = $createDeviceHistoryTable }
            @{ Label = 'Create InterfaceHistory table'; Statement = $createInterfaceHistoryTable }
            @{ Label = 'Create SpanInfo table'; Statement = $createSpanInfoTable }
            @{ Label = 'Create SpanHistory table'; Statement = $createSpanHistoryTable }
        )
        foreach ($entry in $schemaStatements) {
            Invoke-DbSchemaStatement -Connection $connection -Statement $entry.Statement -Label $entry.Label -IgnoreIfExists
        }

        # Helpful indexes (ignore if they already exist)
        $createIndexes = @(
            "CREATE INDEX idx_devicesummary_host ON DeviceSummary (Hostname)",
            "CREATE INDEX idx_interfaces_host_port ON Interfaces (Hostname, Port)",
            "CREATE INDEX idx_spaninfo_host_vlan ON SpanInfo (Hostname, Vlan)",
            "CREATE INDEX idx_spanhistory_host ON SpanHistory (Hostname)"
        )
        foreach ($stmt in $createIndexes) {
            Invoke-DbSchemaStatement -Connection $connection -Statement $stmt -Label $stmt -IgnoreIfExists -ContinueOnFailure
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
            Invoke-DbSchemaStatement -Connection $connection -Statement $stmt -Label $stmt -IgnoreIfExists -ContinueOnFailure
        }
    } catch {
        Write-Warning "Failed to create tables in the Access database. $_"
        throw
    } finally {
        if ($connection) {
            $closeError = $null
            try { $connection.Close() } catch { $closeError = $_.Exception.Message }
            if ($closeError) {
                Write-Warning ("Failed to close Access schema connection for '{0}': {1}" -f $Path, $closeError)
            }
            if ($connection -is [System.__ComObject]) {
                try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($connection) } catch {
                    Write-Warning ("Failed to release COM connection for '{0}': {1}" -f $Path, $_.Exception.Message)
                }
            }
        }
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
        $isDbSession = Test-IsDbReadSession -Session $Session
        if ($isDbSession -and $Session.Connection) {
            $conn = $Session.Connection
        } else {
            # Open a one-shot connection
            $conn = Open-OleDbConnectionWithFallback -DatabasePath $DatabasePath -FailureContext 'for query execution' -SuccessDebugTemplate "[DEBUG] Opened ad-hoc query connection using provider '{0}'" -FailureDebugTemplate "[DEBUG] Provider '{0}' failed to open ad-hoc query connection: {1}"
            $mustClose = $true
        }

        $dataTable = New-Object System.Data.DataTable
        $adapter = $null
        try {
            $adapter = New-Object System.Data.OleDb.OleDbDataAdapter($Sql, $conn)
            [void]$adapter.Fill($dataTable)
        } finally {
            if ($adapter) {
                try { $adapter.Dispose() } catch { }
            }
        }
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

# ============================================================================
# Schema Versioning System
# ============================================================================

$script:CurrentSchemaVersion = 1

function Get-DatabaseSchemaVersion {
    <#
    .SYNOPSIS
    Gets the current schema version of a database.
    .PARAMETER DatabasePath
    Path to the Access database file.
    .OUTPUTS
    Returns the current schema version number, or 0 if not versioned.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DatabasePath
    )

    if (-not (Test-Path -LiteralPath $DatabasePath)) {
        return 0
    }

    try {
        $sql = "SELECT MAX(Version) AS CurrentVersion FROM SchemaVersion"
        $result = Invoke-DbQuery -DatabasePath $DatabasePath -Sql $sql
        if ($result -and $result.Rows.Count -gt 0) {
            $version = $result.Rows[0]['CurrentVersion']
            if ($null -ne $version -and $version -ne [System.DBNull]::Value) {
                return [int]$version
            }
        }
        return 0
    } catch {
        # Table may not exist yet
        return 0
    }
}

function Set-DatabaseSchemaVersion {
    <#
    .SYNOPSIS
    Records a schema version in the database.
    .PARAMETER DatabasePath
    Path to the Access database file.
    .PARAMETER Version
    The schema version number to record.
    .PARAMETER MigrationName
    Name of the migration that was applied.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DatabasePath,
        [Parameter(Mandatory)][int]$Version,
        [string]$MigrationName = ''
    )

    $escapedMigration = Get-SqlLiteral -Value $MigrationName
    $appliedBy = $env:USERNAME
    if (-not $appliedBy) { $appliedBy = 'System' }
    $escapedAppliedBy = Get-SqlLiteral -Value $appliedBy

    $sql = "INSERT INTO SchemaVersion (Version, MigrationName, AppliedAt, AppliedBy) VALUES ($Version, '$escapedMigration', Now(), '$escapedAppliedBy')"

    try {
        Invoke-DbQuery -DatabasePath $DatabasePath -Sql $sql | Out-Null
        return $true
    } catch {
        Write-Warning ("Failed to record schema version: {0}" -f $_.Exception.Message)
        return $false
    }
}

function Get-PendingMigrations {
    <#
    .SYNOPSIS
    Gets list of migrations that need to be applied.
    .PARAMETER DatabasePath
    Path to the Access database file.
    .OUTPUTS
    Returns array of pending migration definitions.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DatabasePath
    )

    $currentVersion = Get-DatabaseSchemaVersion -DatabasePath $DatabasePath

    # Define migrations in order
    $migrations = @(
        @{
            Version = 1
            Name = 'Initial schema with versioning'
            Statements = @()  # Base schema already applied
        }
    )

    return @($migrations | Where-Object { $_.Version -gt $currentVersion })
}

function Invoke-DatabaseMigration {
    <#
    .SYNOPSIS
    Applies pending migrations to a database.
    .PARAMETER DatabasePath
    Path to the Access database file.
    .PARAMETER Force
    Apply migrations even if database appears up to date.
    .OUTPUTS
    Returns count of migrations applied.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DatabasePath,
        [switch]$Force
    )

    $pending = Get-PendingMigrations -DatabasePath $DatabasePath

    if ($pending.Count -eq 0 -and -not $Force) {
        Write-Verbose "Database is up to date."
        return 0
    }

    $applied = 0
    foreach ($migration in $pending) {
        Write-Verbose ("Applying migration v{0}: {1}" -f $migration.Version, $migration.Name)

        $success = $true
        foreach ($stmt in $migration.Statements) {
            try {
                Invoke-DbQuery -DatabasePath $DatabasePath -Sql $stmt | Out-Null
            } catch {
                Write-Warning ("Migration v{0} failed: {1}" -f $migration.Version, $_.Exception.Message)
                $success = $false
                break
            }
        }

        if ($success) {
            Set-DatabaseSchemaVersion -DatabasePath $DatabasePath -Version $migration.Version -MigrationName $migration.Name | Out-Null
            $applied++
        }
    }

    return $applied
}

function Test-DatabaseSchemaHealth {
    <#
    .SYNOPSIS
    Validates database schema integrity.
    .PARAMETER DatabasePath
    Path to the Access database file.
    .OUTPUTS
    Returns a health check result object.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DatabasePath
    )

    $result = [PSCustomObject]@{
        DatabasePath = $DatabasePath
        Exists = (Test-Path -LiteralPath $DatabasePath)
        SchemaVersion = 0
        ExpectedVersion = $script:CurrentSchemaVersion
        IsUpToDate = $false
        MissingTables = @()
        Errors = @()
    }

    if (-not $result.Exists) {
        $result.Errors += "Database file not found"
        return $result
    }

    try {
        $result.SchemaVersion = Get-DatabaseSchemaVersion -DatabasePath $DatabasePath
        $result.IsUpToDate = ($result.SchemaVersion -ge $result.ExpectedVersion)

        # Check for required tables
        $requiredTables = @('DeviceSummary', 'Interfaces', 'SpanInfo', 'SchemaVersion')
        foreach ($table in $requiredTables) {
            try {
                $sql = "SELECT TOP 1 * FROM [$table]"
                Invoke-DbQuery -DatabasePath $DatabasePath -Sql $sql | Out-Null
            } catch {
                $result.MissingTables += $table
            }
        }
    } catch {
        $result.Errors += $_.Exception.Message
    }

    return $result
}

Export-ModuleMember -Function Get-SqlLiteral, ConvertTo-DbRowList, New-AccessDatabase, Invoke-DbQuery, Open-DbReadSession, Close-DbReadSession, Get-DatabaseSchemaVersion, Set-DatabaseSchemaVersion, Get-PendingMigrations, Invoke-DatabaseMigration, Test-DatabaseSchemaHealth
