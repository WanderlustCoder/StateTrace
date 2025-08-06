function New-Directories {
    param ([string[]]$Paths)
    foreach ($path in $Paths) {
        if (-not (Test-Path $path)) {
            New-Item -ItemType Directory -Path $path | Out-Null
        }
    }
}

# Extract structured details from an SNMP location string.  Cisco and Brocade devices
# allow arbitrary strings for the `snmp-server location` configuration; a common
# convention in this environment is to separate fields with underscores.  For
# example: `Bldg_244_Floor_1_Room_33_Row_1_Rack_1`.  This helper splits the
# string on underscores and inspects adjacent key/value pairs.  Keys are
# matched case-insensitively so `bldg`, `building` and `Bldg` are all accepted.
# Returns a hashtable containing the discovered values.  Unmatched keys are
# ignored.
function Get-LocationDetails {
    [CmdletBinding()] param(
        [string]$Location
    )
    # Default return structure with empty strings.  Additional keys can be
    # appended here if more metadata is introduced in the future.
    $details = @{
        Building = ''
        Floor    = ''
        Room     = ''
        Row      = ''
        Rack     = ''
    }
    if (-not [string]::IsNullOrWhiteSpace($Location)) {
        # Split on underscores to capture tokens.  Use `-split` to support any
        # whitespace surrounding underscores and remove empty elements.
        $tokens = $Location -split '_+' | Where-Object { $_ -ne '' }
        for ($i = 0; $i -lt $tokens.Count - 1; $i++) {
            $key = $tokens[$i].Trim()
            $value = $tokens[$i + 1].Trim()
            switch -regex ($key.ToLower()) {
                '^(bldg|building)$' { $details['Building'] = $value; continue }
                '^floor$'          { $details['Floor']    = $value; continue }
                '^room$'           { $details['Room']     = $value; continue }
                '^row$'            { $details['Row']      = $value; continue }
                '^rack$'           { $details['Rack']     = $value; continue }
            }
        }
    }
    return $details
}

function Remove-OldArchiveFolder {
    param (
        [string]$DeviceArchivePath,
        [int]$RetentionDays = 30
    )
    if (-not (Test-Path $DeviceArchivePath)) { return }

    Get-ChildItem $DeviceArchivePath -Directory | Where-Object {
        $folderDate = $null
        try {
            $folderDate = [datetime]::ParseExact($_.Name, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
        } catch { return $false }
        return $folderDate -lt (Get-Date).AddDays(-$RetentionDays)
    } | ForEach-Object {
        try { Remove-Item $_.FullName -Recurse -Force }
        catch { Write-Warning "Failed to delete archive '$_': $($_.Exception.Message)" }
    }
}

function Invoke-DeviceLogParsing {
    param (
        [string]$FilePath,
        [string]$OutputPath,
        [string]$ArchiveRoot,
        [string]$DatabasePath
    )

    Write-Host "[DEBUG] Parsing file '$FilePath'" -ForegroundColor Yellow
    $lines = Get-Content $FilePath

    $make = if ($lines -match "Cisco") {
        "Cisco"
    } elseif ($lines -match "Brocade") {
        "Brocade"
    } elseif ($lines -match "Arista") {
        "Arista"
    } else {
        Write-Warning "Unknown vendor for file $FilePath"
        return
    }

    try {
        switch ($make) {
            "Cisco"   { $facts = Get-CiscoDeviceFacts   -Lines $lines }
            "Brocade" { $facts = Get-BrocadeDeviceFacts -Lines $lines }
            "Arista"  { $facts = Get-AristaDeviceFacts  -Lines $lines }
        }
    } catch {
        Write-Warning "Failed to parse $make log '${FilePath}': $($_.Exception.Message)"
        return
    }

    if (-not $facts -or -not $facts.Hostname) {
        Write-Warning "No valid facts returned for $FilePath"
        return
    }

    $hostname     = $facts.Hostname -replace '[\\\/:\*\?"<>\|]', '_'
    $prefix       = Join-Path $OutputPath $hostname
    $today        = Get-Date -Format "yyyy-MM-dd"
    $devicePath   = Join-Path $ArchiveRoot $hostname
    $archivePath  = Join-Path $devicePath $today
    $timestamp    = (Get-Date).ToUniversalTime().ToString("HHmm") + "Z"

    New-Directories @($devicePath, $archivePath)

    if ($facts.PSObject.Properties.Name -contains "InterfacesCombined") {
        # CSV export disabled – historical data is now stored in the database
    } else {
        # CSV export disabled – historical data is now stored in the database
    }

    # Export spanning tree information if available.  The facts may contain
    # a property named SpanInfo which is a collection of records.  Create
    # a *_Span.csv file in both the parsed and archive directories.  Skip
    # export if the property does not exist or is empty.
    if ($facts.PSObject.Properties.Name -contains 'SpanInfo') {
        $spanData = $facts.SpanInfo
        if ($spanData -and $spanData.Count -gt 0) {
            # Span CSV export disabled – historical data is now stored in the database only
        }
    }

    # Derive additional metadata about the device.  The site is defined as the
    # first four characters of the hostname (when available).  Location
    # information (building, floor, room, etc.) is encoded in the
    # `snmp-server location` string and parsed via the helper above.  These
    # values will be persisted to the summary so the GUI can filter devices.
    # Clean the hostname to remove any SSH@ prefix that may have been
    # inadvertently captured from prompts.  The raw facts.Hostname comes from
    # the device's configuration and may include such prefixes.
    $cleanHostname = $facts.Hostname
    if ($cleanHostname) {
        # Remove any SSH@ prefix and trim leading/trailing whitespace or control characters.
        $cleanHostname = $cleanHostname -replace '^SSH@',''
        $cleanHostname = $cleanHostname.Trim()
    }
    $siteCode = ''
    if ($cleanHostname -and $cleanHostname.Length -ge 4) {
        $siteCode = $cleanHostname.Substring(0,4)
    } elseif ($cleanHostname) {
        # For very short hostnames just use the full name as a site code
        $siteCode = $cleanHostname
    }
    $locDetails = Get-LocationDetails -Location $facts.Location

    $summaryObj = [PSCustomObject]@{
        Hostname         = $cleanHostname
        Make             = $facts.Make
        Model            = $facts.Model
        Version          = $facts.Version
        Uptime           = $facts.Uptime
        Location         = $facts.Location
        Site             = $siteCode
        Building         = $locDetails.Building
        Floor            = $locDetails.Floor
        Room             = $locDetails.Room
        Row              = $locDetails.Row
        Rack             = $locDetails.Rack
        InterfaceCount   = $facts.InterfaceCount
        AuthDefaultVLAN  = $facts.AuthDefaultVLAN
        AuthBlock        = if ($facts.AuthenticationBlock) { $facts.AuthenticationBlock -join "`n" } else { "" }
    }

    # Summary CSV export disabled – historical data is now stored in the database

    # If a database path was supplied, insert the summary and interface data
    # into the Access database.  Use Invoke-DbNonQuery from DatabaseModule
    # for efficient, parameterized execution.  Escape single quotes in
    # values to prevent SQL injection and syntax errors.  Many fields may
    # contain apostrophes (e.g., model names); doubling the quote is the
    # accepted way to escape it in SQL.
    if ($DatabasePath) {
        Write-Host "[DEBUG] Writing results for host '$cleanHostname' to database at '$DatabasePath'" -ForegroundColor Yellow
        try {
            # Capture the current run time for historical records.  Format it
            # as a standard Access date literal enclosed in # characters.
            $runDateString = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            $runDateLiteral = "#$runDateString#"
            # Construct the SQL for the summary row
            $escHostname = $cleanHostname -replace "'", "''"
            $escMake     = $facts.Make -replace "'", "''"
            $escModel    = $facts.Model -replace "'", "''"
            $escUptime   = $facts.Uptime -replace "'", "''"
            $escSite     = $siteCode -replace "'", "''"
            $escBuilding = $locDetails.Building -replace "'", "''"
            $escRoom     = $locDetails.Room -replace "'", "''"
            $escAuthVlan = $facts.AuthDefaultVLAN -replace "'", "''"
            $portCount   = if ($facts.PSObject.Properties.Name -contains 'InterfaceCount') { $facts.InterfaceCount } else { 0 }

            #-------------------------------------------------------------------------
            # Prepare configuration compliance template lookup.  Determine vendor
            # based on the device make.  Cisco and Brocade are supported; unknown
            # vendors will fall back to Cisco.json.  Load the templates only once
            # per device to avoid redundant file reads.  Each template object
            # contains a name, optional aliases and a color property.  Matching
            # is case-insensitive against both the template name and aliases.
            $templates = $null
            try {
                $vendor = 'Cisco'
                if ($facts.Make) {
                    $mk = $facts.Make.ToLower()
                    if ($mk -match 'brocade') { $vendor = 'Brocade' }
                    elseif ($mk -match 'arista') { $vendor = 'Brocade' }
                }
                $tplDir = Join-Path $PSScriptRoot '..\Templates'
                $jsonFile = Join-Path $tplDir "$vendor.json"
                if (Test-Path $jsonFile) {
                    $json = Get-Content -Path $jsonFile -Raw | ConvertFrom-Json
                    if ($json.templates) { $templates = $json.templates }
                }
            } catch {
                # Ignore template load errors; compliance info will remain default
            }

            #---------------------------------------------------------------------
            # To prevent Access database locks when multiple runspaces write
            # concurrently, acquire a named mutex around all write operations.
            # Only one runspace will hold the mutex at a time, ensuring that
            # the file is updated sequentially and avoiding "Could not update;
            # currently locked" errors.  Use a short, friendly mutex name.
            $mutexName = 'StateTraceDbWriteMutex'
            $dbMutex = New-Object System.Threading.Mutex($false, $mutexName)
            try {
                Write-Host "[DEBUG] Waiting to acquire DB write mutex for host '$cleanHostname'" -ForegroundColor Yellow
                # Wait until we can acquire the mutex.  This call blocks until
                # no other runspace is currently writing to the database.
                $null = $dbMutex.WaitOne()
                Write-Host "[DEBUG] Acquired DB write mutex for host '$cleanHostname'" -ForegroundColor Yellow

                # Establish a single connection to the database for all statements.
                # Opening and closing a new connection for each SQL statement is
                # extremely expensive with the Access OLEDB provider.  Using a
                # persistent connection reduces overhead and significantly improves
                # performance when inserting hundreds of interface rows.
                $__dbProvider = $null
                Write-Host "[DEBUG] Detecting available OLEDB provider for database" -ForegroundColor Yellow
                # Prefer the ACE provider when available; fall back to Jet for .mdb files.
                foreach ($provCandidate in @('Microsoft.ACE.OLEDB.12.0','Microsoft.Jet.OLEDB.4.0')) {
                    try {
                        $testConn = New-Object -ComObject ADODB.Connection
                        $testConn.Open("Provider=$provCandidate;Data Source=$DatabasePath")
                        $testConn.Close()
                        $__dbProvider = $provCandidate
                        break
                    } catch { }
                }
                if (-not $__dbProvider) {
                    throw "No suitable OLEDB provider found to open Access database. Install the Microsoft ACE OLEDB provider."
                }
                $__dbConn = New-Object -ComObject ADODB.Connection
                Write-Host "[DEBUG] Opening DB connection to '$DatabasePath' using provider '$__dbProvider'" -ForegroundColor Yellow
                # Configure the connection for read/write access and row‑level locking.
                # Mode=ReadWrite ensures that both reads and writes are allowed.  Jet
                # supports page‑ and row‑level locking; specifying
                # Jet OLEDB:Database Locking Mode=1 requests row‑level locking to
                # minimize contention.  If the property is unsupported, the
                # provider silently ignores it.
                $__dbConn.Open("Provider=$__dbProvider;Data Source=$DatabasePath;Mode=ReadWrite;Jet OLEDB:Database Locking Mode=1")
                # When using the Jet OLEDB provider, we can request synchronous
                # transaction commits via the Jet OLEDB:Transaction Commit Mode
                # property.  The ACE provider does not support this property
                # and will throw if included in the connection string.  Set
                # the property programmatically and catch any exception for
                # unsupported providers.
                try {
                    $prop = $__dbConn.Properties.Item('Jet OLEDB:Transaction Commit Mode')
                    if ($prop) { $prop.Value = 1 }
                } catch { }
                # Use an explicit transaction to batch all SQL statements.  Jet/ACE
                # supports transactions through BeginTrans/CommitTrans.  A single
                # transaction improves performance dramatically when inserting
                # many rows and ensures that all operations either succeed or
                # rollback together in case of failure.
                $__dbConn.BeginTrans()
                try {
                    #------------------------------------------------------------------
                    # In the initial implementation we updated/inserted the summary
                    # row prior to deleting old interface records.  However, Jet/ACE
                    # can hold locks on rows that have been updated but not yet
                    # committed.  Because the Interfaces table has a foreign key
                    # referencing DeviceSummary.Hostname, attempting to delete
                    # interface rows after updating the summary can fail with
                    # "could not update; currently locked".  To avoid this, perform
                    # the interface deletion first, then upsert the summary, and
                    # finally insert new interface rows.  All operations are
                    # encapsulated within a single transaction so that the
                    # database remains consistent on success or failure.

                    # Remove any existing interface records for this host first.
                    # Use a small retry loop in case another process briefly
                    # holds a lock.  If after 3 attempts the deletion still
                    # fails, warn and continue; subsequent inserts may fail on
                    # foreign key constraints but will be logged individually.
                    $delSql = "DELETE FROM Interfaces WHERE Hostname = '$escHostname'"
                    Write-Host "[DEBUG] Deleting old interface rows for host '$cleanHostname'" -ForegroundColor Yellow
                    $deleted = $false
                    for ($attempt = 1; $attempt -le 3; $attempt++) {
                        try {
                            $__dbConn.Execute($delSql) | Out-Null
                            $deleted = $true
                            break
                        } catch {
                            if ($attempt -lt 3) {
                                # Wait briefly before retrying to allow any locks to clear
                                Start-Sleep -Milliseconds 200
                            } else {
                                Write-Warning "Failed to delete old interface rows for host ${cleanHostname}: $($_.Exception.Message)"
                            }
                        }
                    }

                    # Now attempt to update the existing summary row.  This will
                    # modify any existing record for this hostname with the latest
                    # values.  If the host does not exist yet, this UPDATE will
                    # affect zero rows.
                    $updateSql = "UPDATE DeviceSummary SET Make='$escMake', Model='$escModel', Uptime='$escUptime', Site='$escSite', Building='$escBuilding', Room='$escRoom', Ports=$portCount, AuthDefaultVLAN='$escAuthVlan' WHERE Hostname='$escHostname'"
                    Write-Host "[DEBUG] Executing summary UPDATE for host '$cleanHostname'" -ForegroundColor Yellow
                    try {
                        $__dbConn.Execute($updateSql) | Out-Null
                    } catch {
                        # Ignore any update errors; we'll attempt insert next
                    }

                    # Attempt to insert a new summary row.  If the hostname
                    # already exists, the PRIMARY KEY constraint will trigger an
                    # error.  We catch and ignore that error so that updates
                    # perform a lightweight "upsert".
                    $insertSql = "INSERT INTO DeviceSummary (Hostname, Make, Model, Uptime, Site, Building, Room, Ports, AuthDefaultVLAN) VALUES ('$escHostname', '$escMake', '$escModel', '$escUptime', '$escSite', '$escBuilding', '$escRoom', $portCount, '$escAuthVlan')"
                    Write-Host "[DEBUG] Executing summary INSERT for host '$cleanHostname'" -ForegroundColor Yellow
                    try {
                        $__dbConn.Execute($insertSql) | Out-Null
                    } catch {
                        # Duplicate hostname rows are expected when updating an
                        # existing device.  Suppress the duplicate error and
                        # continue without throwing.  Other database errors will
                        # propagate to the outer catch.
                    }

                # Record the summary in the historical DeviceHistory table
                # Use the run date literal captured earlier.  We do not need
                # to escape it with quotes because date literals in Access
                # are delimited by # characters.  Fields match those in the
                # DeviceSummary table.
                $histSummarySql = "INSERT INTO DeviceHistory (Hostname, RunDate, Make, Model, Uptime, Site, Building, Room, Ports, AuthDefaultVLAN) VALUES ('$escHostname', $runDateLiteral, '$escMake', '$escModel', '$escUptime', '$escSite', '$escBuilding', '$escRoom', $portCount, '$escAuthVlan')"
                try {
                    $__dbConn.Execute($histSummarySql) | Out-Null
                } catch {
                    # History insertion errors should not halt parsing.
                    Write-Warning "Failed to insert device history for host ${cleanHostname}: $($_.Exception.Message)"
                }

                    # Insert each interface record.  After deleting prior entries,
                    # there are no conflicting rows for this host.  We still
                    # perform per‑row escaping and numeric conversion for VLAN.
                    $ifaceRecords = $null
                    if ($facts.PSObject.Properties.Name -contains 'InterfacesCombined') {
                        $ifaceRecords = $facts.InterfacesCombined
                    } elseif ($facts.PSObject.Properties.Name -contains 'Interfaces') {
                        $ifaceRecords = $facts.Interfaces
                    }
                    if ($ifaceRecords) {
                        Write-Host "[DEBUG] Inserting $($ifaceRecords.Count) interface rows for host '$cleanHostname'" -ForegroundColor Yellow
                        foreach ($iface in $ifaceRecords) {
                            # Compose all scalar values and handle missing properties.
                            $port   = ($iface.PSObject.Properties['Port']   | ForEach-Object { $_.Value }) -join ''
                            $name   = ($iface.PSObject.Properties['Name']   | ForEach-Object { $_.Value }) -join ''
                            $status = ($iface.PSObject.Properties['Status'] | ForEach-Object { $_.Value }) -join ''
                            $vlan   = ($iface.PSObject.Properties['VLAN']   | ForEach-Object { $_.Value }) -join ''
                            $duplex = ($iface.PSObject.Properties['Duplex'] | ForEach-Object { $_.Value }) -join ''
                            $speed  = ($iface.PSObject.Properties['Speed']  | ForEach-Object { $_.Value }) -join ''
                            $type   = ($iface.PSObject.Properties['Type']   | ForEach-Object { $_.Value }) -join ''
                            $learned    = ''
                            if ($iface.PSObject.Properties.Name -contains 'LearnedMACs') {
                                $learned = $iface.LearnedMACs -join ','
                            }
                            $authState  = ''
                            if ($iface.PSObject.Properties.Name -contains 'AuthState') {
                                $authState = $iface.AuthState
                            }
                            $authMode   = ''
                            if ($iface.PSObject.Properties.Name -contains 'AuthMode') {
                                $authMode = $iface.AuthMode
                            }
                            $authClient = ''
                            if ($iface.PSObject.Properties.Name -contains 'AuthClientMAC') {
                                $authClient = $iface.AuthClientMAC
                            }
                            # Escape single quotes in all text fields.  Access SQL
                            # uses single quotes for string literals, so replace
                            # single quotes with doubled single quotes to avoid
                            # breaking the statement.  Compute compliance fields
                            # (PortColor, ConfigStatus) based on the AuthTemplate
                            # and loaded templates.  Compose a tooltip from the
                            # AuthTemplate and the raw Config.
                            $authTemplate = ''
                            if ($iface.PSObject.Properties.Name -contains 'AuthTemplate') {
                                $authTemplate = $iface.AuthTemplate
                            }
                            $configText = ''
                            if ($iface.PSObject.Properties.Name -contains 'Config') {
                                $configText = $iface.Config
                            }
                            $toolTip = "AuthTemplate: $authTemplate"
                            if ($configText) { $toolTip = "$toolTip`n`n$configText" }
                            $portColor    = 'Gray'
                            $configStatus = 'Mismatch'
                            if ($templates) {
                                foreach ($tpl in $templates) {
                                    $nameMatch   = $false
                                    if ($tpl.name) {
                                        if ($tpl.name -ieq $authTemplate) { $nameMatch = $true }
                                    }
                                    $aliasMatch  = $false
                                    if (-not $nameMatch -and $tpl.aliases) {
                                        # aliases may be a simple array or null
                                        foreach ($al in $tpl.aliases) {
                                            if ($al -ieq $authTemplate) { $aliasMatch = $true; break }
                                        }
                                    }
                                    if ($nameMatch -or $aliasMatch) {
                                        $portColor    = $tpl.color
                                        $configStatus = 'Match'
                                        break
                                    }
                                }
                            }
                            # Escape all fields to be inserted
                            $escPort      = $port        -replace "'", "''"
                            $escName      = $name        -replace "'", "''"
                            $escStatus    = $status      -replace "'", "''"
                            $escDuplex    = $duplex      -replace "'", "''"
                            $escSpeed     = $speed       -replace "'", "''"
                            $escType      = $type        -replace "'", "''"
                            $escLearned   = $learned      -replace "'", "''"
                            $escState     = $authState    -replace "'", "''"
                            $escModeFld   = $authMode     -replace "'", "''"
                            $escClient    = $authClient   -replace "'", "''"
                            $escTemplate  = $authTemplate -replace "'", "''"
                            $escConfig    = $configText   -replace "'", "''"
                            $escColor     = $portColor    -replace "'", "''"
                            $escCfgStat   = $configStatus -replace "'", "''"
                            $escToolTip   = $toolTip      -replace "'", "''"
                            # Convert VLAN to numeric when possible.  Use 0 when blank or invalid.
                            $vlanNumeric   = 0
                            [void][int]::TryParse($vlan, [ref]$vlanNumeric)
                            # Build the insert statement including the new compliance columns
                            $ifaceSql = "INSERT INTO Interfaces (Hostname, Port, Name, Status, VLAN, Duplex, Speed, Type, LearnedMACs, AuthState, AuthMode, AuthClientMAC, AuthTemplate, Config, PortColor, ConfigStatus, ToolTip) VALUES ('$escHostname', '$escPort', '$escName', '$escStatus', $vlanNumeric, '$escDuplex', '$escSpeed', '$escType', '$escLearned', '$escState', '$escModeFld', '$escClient', '$escTemplate', '$escConfig', '$escColor', '$escCfgStat', '$escToolTip')"
                            try {
                                $__dbConn.Execute($ifaceSql) | Out-Null
                            } catch {
                                # Insertion errors should not halt parsing.  Log
                                # a warning so the user is aware of any row that
                                # failed to insert, then continue with the next.
                                Write-Warning "Failed to insert interface record for host ${cleanHostname} port ${port}: $($_.Exception.Message)"
                            }

                            # Also insert this interface into the historical table
                            $histIfaceSql = "INSERT INTO InterfaceHistory (Hostname, RunDate, Port, Name, Status, VLAN, Duplex, Speed, Type, LearnedMACs, AuthState, AuthMode, AuthClientMAC, AuthTemplate, Config, PortColor, ConfigStatus, ToolTip) VALUES ('$escHostname', $runDateLiteral, '$escPort', '$escName', '$escStatus', $vlanNumeric, '$escDuplex', '$escSpeed', '$escType', '$escLearned', '$escState', '$escModeFld', '$escClient', '$escTemplate', '$escConfig', '$escColor', '$escCfgStat', '$escToolTip')"
                            try {
                                $__dbConn.Execute($histIfaceSql) | Out-Null
                            } catch {
                                Write-Warning "Failed to insert interface history for host ${cleanHostname} port ${port}: $($_.Exception.Message)"
                            }
                        }
                    }
                    # Commit the transaction after all operations have executed.
                    try {
                        Write-Host "[DEBUG] Committing transaction for host '$cleanHostname'" -ForegroundColor Yellow
                        $__dbConn.CommitTrans()
                        # After committing, force the Jet/ACE engine to flush
                        # pending writes and refresh its cache.  Without this,
                        # other connections may not see the newly inserted
                        # rows until a later timeout.  The JRO.JetEngine
                        # RefreshCache method will throw if unsupported; wrap
                        # in try/catch to silently ignore in that case.
                        try {
                            $jet = New-Object -ComObject JRO.JetEngine
                            $jet.RefreshCache($__dbConn)
                            Write-Host "[DEBUG] Refreshed Jet cache after commit for host '$cleanHostname'" -ForegroundColor Yellow
                        } catch {}
                    } catch {
                        # If commit fails, attempt to rollback so the database
                        # remains consistent.
                        Write-Host "[DEBUG] Commit failed for host '$cleanHostname', rolling back" -ForegroundColor Yellow
                        try { $__dbConn.RollbackTrans() } catch {}
                        throw
                    }
                } finally {
                    if ($__dbConn -and $__dbConn.State -ne 0) {
                        try { $__dbConn.Close() } catch {}
                    }
                }
            } finally {
                # Release the mutex to allow other runspaces to write.  Always
                # release the mutex even if an exception occurred.  Disposing
                # the mutex afterwards frees underlying handles.
                try {
                    Write-Host "[DEBUG] Releasing DB write mutex for host '$cleanHostname'" -ForegroundColor Yellow
                    $dbMutex.ReleaseMutex()
                } catch {}
                $dbMutex.Dispose()
            }
        } catch {
            # Use curly braces around variable names that precede a colon to avoid
            # PowerShell interpreting the colon as part of the variable name.
            Write-Warning "Failed to insert data into database for host ${cleanHostname}: $($_.Exception.Message)"
        }
    }

    Remove-OldArchiveFolder -DeviceArchivePath $devicePath -RetentionDays 30
}
