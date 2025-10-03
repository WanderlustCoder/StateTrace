Set-StrictMode -Version Latest

# ADODB helper constants and utilities for parameterized operations
if (-not (Get-Variable -Name AdCmdText -Scope Script -ErrorAction SilentlyContinue)) {
    $script:AdCmdText = 1
    $script:AdParamInput = 1
    $script:AdTypeVarWChar = 202
    $script:AdTypeLongVarWChar = 203
    $script:AdTypeInteger = 3
    $script:AdTypeDate = 7
    $script:AdLongTextDefaultSize = 262144
}

function Test-IsAdodbConnection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Connection
    )

    if ($null -eq $Connection) { return $false }
    if ($Connection -is [System.__ComObject]) { return $true }
    try {
        foreach ($name in $Connection.PSObject.TypeNames) {
            if ($name -eq 'ADODB.Connection') { return $true }
        }
    } catch { }
    return $false
}

function Release-ComObjectSafe {
    [CmdletBinding()]
    param(
        [Parameter()][object]$ComObject
    )

    if ($null -eq $ComObject) { return }
    if ($ComObject -is [System.__ComObject]) {
        try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($ComObject) } catch { }
    }
}

function New-AdodbTextCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Connection,
        [Parameter(Mandatory=$true)][string]$CommandText
    )

    try {
        $command = New-Object -ComObject 'ADODB.Command'
    } catch {
        return $null
    }

    try {
        $command.ActiveConnection = $Connection
        $command.CommandType = $script:AdCmdText
        $command.CommandText = $CommandText
        return $command
    } catch {
        Release-ComObjectSafe -ComObject $command
        return $null
    }
}

function Add-AdodbParameter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Command,
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][int]$Type,
        [Parameter()][object]$Size
    )

    if (-not $Command) { return $null }

    try {
        $sizeValue = $null
        if ($PSBoundParameters.ContainsKey('Size')) {
            $sizeValue = $Size
            if ($sizeValue -is [System.Array]) {
                if ($sizeValue.Length -gt 0) {
                    $sizeValue = $sizeValue[0]
                } else {
                    $sizeValue = $null
                }
            }
            if ($sizeValue -ne $null -and -not ($sizeValue -is [int])) {
                try { $sizeValue = [int]$sizeValue } catch { $sizeValue = 0 }
            }
        }

        if ($sizeValue -is [int] -and $sizeValue -gt 0) {
            $parameter = $Command.CreateParameter($Name, $Type, $script:AdParamInput, $sizeValue)
        } else {
            $parameter = $Command.CreateParameter($Name, $Type, $script:AdParamInput)
        }
        [void]$Command.Parameters.Append($parameter)
        return $parameter
    } catch {
        return $null
    }
}

function Set-AdodbParameterValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Parameter,
        [Parameter()][object]$Value
    )

    if (-not $Parameter) { return }
    if ($null -eq $Value) {
        $Parameter.Value = [System.DBNull]::Value
        return
    }

    $Parameter.Value = $Value
}

function ConvertTo-DbDateTime {
    [CmdletBinding()]
    param(
        [Parameter()][string]$RunDateString
    )

    if ([string]::IsNullOrWhiteSpace($RunDateString)) { return $null }

    $formats = @('yyyy-MM-dd HH:mm:ss', 'yyyy-MM-ddTHH:mm:ss', 'o')
    foreach ($fmt in $formats) {
        try {
            return [DateTime]::ParseExact($RunDateString, $fmt, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeLocal)
        } catch { }
    }

    try { return [DateTime]::Parse($RunDateString, [System.Globalization.CultureInfo]::InvariantCulture) } catch { }
    try { return [DateTime]::Parse($RunDateString) } catch { }

    return $null
}



function Update-DeviceSummaryInDb {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Connection,
        [Parameter(Mandatory=$true)][object]$Facts,
        [Parameter(Mandatory=$true)][string]$Hostname,
        [Parameter(Mandatory=$true)][string]$SiteCode,
        [Parameter(Mandatory=$true)][hashtable]$LocationDetails,
        [Parameter(Mandatory=$true)][string]$RunDateString
    )
    # Escape single quotes for SQL literals.  PowerShell 5.1 does not support the
    $escHostname = $Hostname -replace "'", "''"
    # Make
    $rawMake = ''
    if ($Facts.PSObject.Properties.Name -contains 'Make' -and $Facts.Make) {
        $rawMake = $Facts.Make
    }
    $escMake = $rawMake -replace "'", "''"
    # Model
    $rawModel = ''
    if ($Facts.PSObject.Properties.Name -contains 'Model' -and $Facts.Model) {
        $rawModel = $Facts.Model
    }
    $escModel = $rawModel -replace "'", "''"
    # Uptime
    $rawUptime = ''
    if ($Facts.PSObject.Properties.Name -contains 'Uptime' -and $Facts.Uptime) {
        $rawUptime = $Facts.Uptime
    }
    $escUptime = $rawUptime -replace "'", "''"
    # Site code (always provided)
    $escSite = $SiteCode -replace "'", "''"
    # Building
    $rawBuilding = ''
    if ($LocationDetails.ContainsKey('Building') -and $LocationDetails.Building) {
        $rawBuilding = $LocationDetails.Building
    }
    $escBuilding = $rawBuilding -replace "'", "''"
    # Room
    $rawRoom = ''
    if ($LocationDetails.ContainsKey('Room') -and $LocationDetails.Room) {
        $rawRoom = $LocationDetails.Room
    }
    $escRoom = $rawRoom -replace "'", "''"
    # Determine number of interfaces if provided
    $portCount = 0
    if ($Facts.PSObject.Properties.Name -contains 'InterfaceCount') {
        $portCount = $Facts.InterfaceCount
    }
    # Extract the default authentication VLAN
    $rawAuthVlan = ''
    if ($Facts.PSObject.Properties.Name -contains 'AuthDefaultVLAN' -and $Facts.AuthDefaultVLAN) {
        $rawAuthVlan = $Facts.AuthDefaultVLAN
    }
    $escAuthVlan = $rawAuthVlan -replace "'", "''"
    # Compose the authentication block text
    $authBlockText = ''
    if ($Facts.PSObject.Properties.Name -contains 'AuthenticationBlock' -and $Facts.AuthenticationBlock) {
        $authBlockText = ($Facts.AuthenticationBlock -join "`r`n")
    }
    $escAuthBlock = $authBlockText -replace "'", "''"

    $paramValues = @{
        Make            = $rawMake
        Model           = $rawModel
        Uptime          = $rawUptime
        Site            = $SiteCode
        Building        = $rawBuilding
        Room            = $rawRoom
        Ports           = $portCount
        AuthDefaultVlan = $rawAuthVlan
        AuthBlock       = $authBlockText
    }

    $runDateValue = ConvertTo-DbDateTime -RunDateString $RunDateString
    if ($runDateValue -and (Test-IsAdodbConnection -Connection $Connection)) {
        if (Invoke-DeviceSummaryParameterized -Connection $Connection -Hostname $Hostname -Values $paramValues -RunDate $runDateValue) {
            return
        }
    }

    # Build update and insert statements.  The update will modify an existing
    $updateSql = "UPDATE DeviceSummary SET Make='$escMake', Model='$escModel', Uptime='$escUptime', Site='$escSite', Building='$escBuilding', Room='$escRoom', Ports=$portCount, AuthDefaultVLAN='$escAuthVlan', AuthBlock='$escAuthBlock' WHERE Hostname='$escHostname'"
    $insertSql = "INSERT INTO DeviceSummary (Hostname, Make, Model, Uptime, Site, Building, Room, Ports, AuthDefaultVLAN, AuthBlock) VALUES ('$escHostname', '$escMake', '$escModel', '$escUptime', '$escSite', '$escBuilding', '$escRoom', $portCount, '$escAuthVlan', '$escAuthBlock')"
    # Execute update and insert sequentially
    try {
        $Connection.Execute($updateSql) | Out-Null
    } catch {
        # ignore update errors
    }
    try {
        $Connection.Execute($insertSql) | Out-Null
    } catch {
        # duplicate key is expected on upsert; ignore
    }
    # Insert a row into DeviceHistory.  Use the run date literal enclosed
    $runDateLiteral = "#$RunDateString#"
    $histSql = "INSERT INTO DeviceHistory (Hostname, RunDate, Make, Model, Uptime, Site, Building, Room, Ports, AuthDefaultVLAN, AuthBlock) VALUES ('$escHostname', $runDateLiteral, '$escMake', '$escModel', '$escUptime', '$escSite', '$escBuilding', '$escRoom', $portCount, '$escAuthVlan', '$escAuthBlock')"
    try {
        $Connection.Execute($histSql) | Out-Null
    } catch {
        Write-Warning "Failed to insert device history for host ${Hostname}: $($_.Exception.Message)"
    }
}




function Update-InterfacesInDb {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Connection,
        [Parameter(Mandatory=$true)][object]$Facts,
        [Parameter(Mandatory=$true)][string]$Hostname,
        [Parameter(Mandatory=$true)][string]$RunDateString,
        [Parameter(Mandatory=$false)][object[]]$Templates
    )

    $escHostname = $Hostname -replace "'", "''"

    $ifaceRecords = $null
    if ($Facts.PSObject.Properties.Name -contains 'InterfacesCombined') {
        $ifaceRecords = $Facts.InterfacesCombined
    } elseif ($Facts.PSObject.Properties.Name -contains 'Interfaces') {
        $ifaceRecords = $Facts.Interfaces
    }
    if (-not $ifaceRecords) { $ifaceRecords = @() }

    $existingRows = @{}
    $selectSql = "SELECT Port, Name, Status, VLAN, Duplex, Speed, Type, LearnedMACs, AuthState, AuthMode, AuthClientMAC, AuthTemplate, Config, PortColor, ConfigStatus, ToolTip FROM Interfaces WHERE Hostname = '$escHostname'"
    $recordset = $null
    try {
        $recordset = $Connection.Execute($selectSql)
        if ($recordset -and $recordset.State -eq 1) {
            while (-not $recordset.EOF) {
                $portValue = '' + ($recordset.Fields.Item('Port').Value)
                if (-not [string]::IsNullOrWhiteSpace($portValue)) {
                    $normalizedPort = $portValue.Trim()
                    $existingRows[$normalizedPort] = [PSCustomObject]@{
                        Name      = '' + ($recordset.Fields.Item('Name').Value)
                        Status    = '' + ($recordset.Fields.Item('Status').Value)
                        VLAN      = '' + ($recordset.Fields.Item('VLAN').Value)
                        Duplex    = '' + ($recordset.Fields.Item('Duplex').Value)
                        Speed     = '' + ($recordset.Fields.Item('Speed').Value)
                        Type      = '' + ($recordset.Fields.Item('Type').Value)
                        Learned   = '' + ($recordset.Fields.Item('LearnedMACs').Value)
                        AuthState = '' + ($recordset.Fields.Item('AuthState').Value)
                        AuthMode  = '' + ($recordset.Fields.Item('AuthMode').Value)
                        AuthClient= '' + ($recordset.Fields.Item('AuthClientMAC').Value)
                        Template  = '' + ($recordset.Fields.Item('AuthTemplate').Value)
                        Config    = '' + ($recordset.Fields.Item('Config').Value)
                        PortColor = '' + ($recordset.Fields.Item('PortColor').Value)
                        StatusTag = '' + ($recordset.Fields.Item('ConfigStatus').Value)
                        ToolTip   = '' + ($recordset.Fields.Item('ToolTip').Value)
                    }
                }
                $recordset.MoveNext() | Out-Null
            }
        }
    } catch {
        $existingRows = @{}
    } finally {
        if ($recordset) {
            try { $recordset.Close() } catch { }
        }
    }

    $toInsert = New-Object 'System.Collections.Generic.List[object]'
    $toUpdate = New-Object 'System.Collections.Generic.List[object]'
    $seenPorts = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    $runDateLiteral = "#$RunDateString#"
    $runDateValue = ConvertTo-DbDateTime -RunDateString $RunDateString
    $useAdodbParameters = $runDateValue -and (Test-IsAdodbConnection -Connection $Connection)

    foreach ($iface in $ifaceRecords) {
        if (-not $iface) { continue }

        $port = '' + $iface.Port
        if ([string]::IsNullOrWhiteSpace($port)) { continue }
        $normalizedPort = $port.Trim()
        $seenPorts.Add($normalizedPort) | Out-Null

        $name   = '' + $iface.Name
        $status = '' + $iface.Status
        $vlan   = '' + $iface.VLAN
        $duplex = '' + $iface.Duplex
        $speed  = '' + $iface.Speed
        $type   = '' + $iface.Type

        $vlanNumeric = 0
        if (-not [int]::TryParse($vlan, [ref]$vlanNumeric)) { $vlanNumeric = 0 }

        $learned = ''
        if ($iface.PSObject.Properties.Name -contains 'LearnedMACsFull' -and ($iface.LearnedMACsFull)) {
            $learned = '' + $iface.LearnedMACsFull
        } elseif ($iface.PSObject.Properties.Name -contains 'LearnedMACs') {
            $lm = $iface.LearnedMACs
            if ($lm -is [string]) {
                $learned = $lm
            } elseif ($lm) {
                $macList = New-Object 'System.Collections.Generic.List[string]'
                foreach ($mac in $lm) {
                    if ($mac -and $mac -ne '') { [void]$macList.Add($mac) }
                }
                $learned = [string]::Join(',', $macList.ToArray())
            }
        }

        $authState = ''
        if ($iface.PSObject.Properties.Name -contains 'AuthState') { $authState = '' + $iface.AuthState }
        $authMode = ''
        if ($iface.PSObject.Properties.Name -contains 'AuthMode') { $authMode = '' + $iface.AuthMode }
        $authClient = ''
        if ($iface.PSObject.Properties.Name -contains 'AuthClientMAC') { $authClient = '' + $iface.AuthClientMAC }
        $authTemplate = ''
        if ($iface.PSObject.Properties.Name -contains 'AuthTemplate') { $authTemplate = '' + $iface.AuthTemplate }

        $configText = ''
        if ($iface.PSObject.Properties.Name -contains 'Config') { $configText = '' + $iface.Config }
        if (-not $configText -or ($configText -is [string] -and $configText.Trim() -eq '')) {
            if ($Facts -and $Facts.Make -eq 'Brocade') {
                if ($Facts.PSObject.Properties.Name -contains 'AuthenticationBlock' -and $Facts.AuthenticationBlock) {
                    $configText = "AUTH BLOCK (GLOBAL)`r`n" + ($Facts.AuthenticationBlock -join "`r`n")
                }
            }
        }

        $portColor = ''
        if ($iface.PSObject.Properties.Name -contains 'PortColor') { $portColor = '' + $iface.PortColor }
        $configStatus = ''
        if ($iface.PSObject.Properties.Name -contains 'ConfigStatus') { $configStatus = '' + $iface.ConfigStatus }
        $toolTip = ''
        if ($iface.PSObject.Properties.Name -contains 'ToolTip') { $toolTip = '' + $iface.ToolTip }

        if (-not $portColor -and $Templates) {
            foreach ($tpl in $Templates) {
                if (-not $tpl) { continue }

                $tplName = $null
                $tplColor = $null

                if ($tpl -is [hashtable]) {
                    if ($tpl.ContainsKey('TemplateName')) { $tplName = $tpl['TemplateName'] }
                    if ($tpl.ContainsKey('PortColor')) { $tplColor = $tpl['PortColor'] }
                } else {
                    $props = $tpl.PSObject.Properties
                    if ($props.Name -contains 'TemplateName') { $tplName = $tpl.TemplateName }
                    if ($props.Name -contains 'PortColor') { $tplColor = $tpl.PortColor }
                }

                if ($tplName -and $tplColor -and $tplName -eq $authTemplate) {
                    $portColor = '' + $tplColor
                    break
                }
            }
        }

        $newRow = [PSCustomObject]@{
            Port      = $normalizedPort
            Name      = $name
            Status    = $status
            VLAN      = $vlan
            VlanNumeric = $vlanNumeric
            Duplex    = $duplex
            Speed     = $speed
            Type      = $type
            Learned   = $learned
            AuthState = $authState
            AuthMode  = $authMode
            AuthClient= $authClient
            Template  = $authTemplate
            Config    = $configText
            PortColor = $portColor
            StatusTag = $configStatus
            ToolTip   = $toolTip
        }

        if ($existingRows.ContainsKey($normalizedPort)) {
            $existing = $existingRows[$normalizedPort]
            $changed = $false
            foreach ($prop in 'Name','Status','VLAN','Duplex','Speed','Type','Learned','AuthState','AuthMode','AuthClient','Template','Config','PortColor','StatusTag','ToolTip') {
                $newValue = '' + $newRow.$prop
                $existingValue = '' + $existing.$prop
                if (-not [System.StringComparer]::Ordinal.Equals($newValue, $existingValue)) {
                    $changed = $true
                    break
                }
            }

            if ($changed) {
                $toUpdate.Add($newRow) | Out-Null
            }
        } else {
            $toInsert.Add($newRow) | Out-Null
        }
    }

    $toDelete = New-Object 'System.Collections.Generic.List[string]'

    foreach ($existingPort in $existingRows.Keys) {

        if (-not $seenPorts.Contains($existingPort)) {

            $toDelete.Add($existingPort) | Out-Null

        }

    }



    if ($toDelete.Count -gt 0) {

        $batch = New-Object 'System.Collections.Generic.List[string]'

        foreach ($portToRemove in $toDelete) {

            $batch.Add($portToRemove) | Out-Null

            if ($batch.Count -ge 50) {

                $escaped = @()

                foreach ($item in $batch) { $escaped += "'" + ($item -replace "'", "''") + "'" }

                $deleteSql = "DELETE FROM Interfaces WHERE Hostname = '$escHostname' AND Port IN (" + ([string]::Join(',', $escaped)) + ")"

                try { $Connection.Execute($deleteSql) | Out-Null } catch { Write-Warning "Failed to delete stale port ${Hostname}/${item}: $($_.Exception.Message)" }

                $batch.Clear()

            }

        }



        if ($batch.Count -gt 0) {

            $escaped = @()

            foreach ($item in $batch) { $escaped += "'" + ($item -replace "'", "''") + "'" }

            $deleteSql = "DELETE FROM Interfaces WHERE Hostname = '$escHostname' AND Port IN (" + ([string]::Join(',', $escaped)) + ")"

            try { $Connection.Execute($deleteSql) | Out-Null } catch { Write-Warning "Failed to delete stale ports for host ${Hostname}: $($_.Exception.Message)" }

        }

    }



    foreach ($row in $toUpdate) {

        $escPortSingle = $row.Port -replace "'", "''"

        $deleteSql = "DELETE FROM Interfaces WHERE Hostname = '$escHostname' AND Port = '$escPortSingle'"

        try { $Connection.Execute($deleteSql) | Out-Null } catch { Write-Warning "Failed to clear existing port ${Hostname}/${row.Port}: $($_.Exception.Message)" }

    }



    function Add-InterfaceRow {

        param(

            [object]$Row

        )



        $escPort      = $Row.Port       -replace "'", "''"

        $escName      = $Row.Name       -replace "'", "''"

        $escStatus    = $Row.Status     -replace "'", "''"

        $escDuplex    = $Row.Duplex     -replace "'", "''"

        $escSpeed     = $Row.Speed      -replace "'", "''"

        $escType      = $Row.Type       -replace "'", "''"

        $escLearned   = $Row.Learned    -replace "'", "''"

        $escState     = $Row.AuthState  -replace "'", "''"

        $escModeFld   = $Row.AuthMode   -replace "'", "''"

        $escClient    = $Row.AuthClient -replace "'", "''"

        $escTemplate  = $Row.Template   -replace "'", "''"

        $escConfig    = $Row.Config     -replace "'", "''"

        $escColor     = $Row.PortColor  -replace "'", "''"

        $escCfgStat   = $Row.StatusTag  -replace "'", "''"

        $escToolTip   = $Row.ToolTip    -replace "'", "''"



        $vlanNumeric = 0

        if ($Row.PSObject.Properties.Name -contains 'VlanNumeric' -and $null -ne $Row.VlanNumeric) {

            try { $vlanNumeric = [int]$Row.VlanNumeric } catch { $vlanNumeric = 0 }

        } else {

            [void][int]::TryParse($Row.VLAN, [ref]$vlanNumeric)

        }



        $ifaceSql = "INSERT INTO Interfaces (Hostname, Port, Name, Status, VLAN, Duplex, Speed, Type, LearnedMACs, AuthState, AuthMode, AuthClientMAC, AuthTemplate, Config, PortColor, ConfigStatus, ToolTip) VALUES ('$escHostname', '$escPort', '$escName', '$escStatus', $vlanNumeric, '$escDuplex', '$escSpeed', '$escType', '$escLearned', '$escState', '$escModeFld', '$escClient', '$escTemplate', '$escConfig', '$escColor', '$escCfgStat', '$escToolTip')"

        try { $Connection.Execute($ifaceSql) | Out-Null } catch { Write-Warning "Failed to insert interface record for host ${Hostname} port ${Row.Port}: $($_.Exception.Message)" }



        $histIfaceSql = "INSERT INTO InterfaceHistory (Hostname, RunDate, Port, Name, Status, VLAN, Duplex, Speed, Type, LearnedMACs, AuthState, AuthMode, AuthClientMAC, AuthTemplate, Config, PortColor, ConfigStatus, ToolTip) VALUES ('$escHostname', $runDateLiteral, '$escPort', '$escName', '$escStatus', $vlanNumeric, '$escDuplex', '$escSpeed', '$escType', '$escLearned', '$escState', '$escModeFld', '$escClient', '$escTemplate', '$escConfig', '$escColor', '$escCfgStat', '$escToolTip')"

        try { $Connection.Execute($histIfaceSql) | Out-Null } catch { Write-Warning "Failed to insert interface history for host ${Hostname} port ${Row.Port}: $($_.Exception.Message)" }

    }



    $rowsToWrite = New-Object 'System.Collections.Generic.List[object]'

    foreach ($row in $toInsert) { $rowsToWrite.Add($row) | Out-Null }

    foreach ($row in $toUpdate) { $rowsToWrite.Add($row) | Out-Null }



    $bulkSucceeded = $false

    if ($useAdodbParameters -and $rowsToWrite.Count -gt 0) {

        try {

            $bulkSucceeded = Invoke-InterfaceBulkInsertInternal -Connection $Connection -Hostname $Hostname -RunDate $runDateValue -Rows $rowsToWrite

        } catch {

            Write-Verbose ("Bulk interface insert failed for {0}: {1}" -f $Hostname, $_.Exception.Message)

            $bulkSucceeded = $false

        }

    }



    if (-not $bulkSucceeded) {

        if ($useAdodbParameters) {

            foreach ($row in $toInsert) {

                $handled = Invoke-InterfaceRowParameterized -Connection $Connection -Hostname $Hostname -Row $row -RunDate $runDateValue

                if (-not $handled) { Add-InterfaceRow -Row $row }

            }



            foreach ($row in $toUpdate) {

                $handled = Invoke-InterfaceRowParameterized -Connection $Connection -Hostname $Hostname -Row $row -RunDate $runDateValue

                if (-not $handled) { Add-InterfaceRow -Row $row }

            }

        } else {

            foreach ($row in $toInsert) {

                Add-InterfaceRow -Row $row

            }



            foreach ($row in $toUpdate) {

                Add-InterfaceRow -Row $row

            }

        }

    }

    try {
        $rowsInserted = if ($toInsert) { [int]$toInsert.Count } else { 0 }
        $rowsUpdated  = if ($toUpdate) { [int]$toUpdate.Count } else { 0 }
        $rowsDeleted  = if ($toDelete) { [int]$toDelete.Count } else { 0 }
        $siteCode     = $null
        try { $siteCode = DeviceRepositoryModule\Get-SiteFromHostname -Hostname $Hostname } catch { }
        TelemetryModule\Write-StTelemetryEvent -Name 'RowsWritten' -Payload @{
            Hostname   = $Hostname
            Site       = $siteCode
            RunDate    = $RunDateString
            Rows       = ($rowsInserted + $rowsUpdated)
            DeletedRows= $rowsDeleted
        }
    } catch { }
}







function Ensure-InterfaceBulkSeedTable {

    [CmdletBinding()]

    param(

        [Parameter(Mandatory=$true)][object]$Connection

    )

    if (-not (Test-IsAdodbConnection -Connection $Connection)) { return $false }

    try {

        $Connection.Execute('SELECT TOP 1 BatchId FROM InterfaceBulkSeed') | Out-Null

        return $true

    } catch {

        try {

            $createSql = @"

CREATE TABLE InterfaceBulkSeed (

    BatchId TEXT(36) NOT NULL,

    Hostname TEXT(255),

    RunDateText TEXT(32),

    Port TEXT(255),

    Name TEXT(255),

    Status TEXT(255),

    VLAN INTEGER,

    Duplex TEXT(255),

    Speed TEXT(255),

    Type TEXT(255),

    LearnedMACs MEMO,

    AuthState TEXT(255),

    AuthMode TEXT(255),

    AuthClientMAC TEXT(255),

    AuthTemplate TEXT(255),

    Config MEMO,

    PortColor TEXT(255),

    ConfigStatus TEXT(255),

    ToolTip MEMO

)

"@

            $Connection.Execute($createSql) | Out-Null

            try { $Connection.Execute('CREATE INDEX IX_InterfaceBulkSeed_BatchId ON InterfaceBulkSeed (BatchId)') | Out-Null } catch { }

            return $true

        } catch {

            Write-Warning ("Failed to ensure InterfaceBulkSeed staging table: {0}" -f $_.Exception.Message)

            return $false

        }

    }

}

function Invoke-InterfaceBulkInsertInternal {

    [CmdletBinding()]

    param(

        [Parameter(Mandatory=$true)][object]$Connection,

        [Parameter(Mandatory=$true)][string]$Hostname,

        [Parameter(Mandatory=$true)][datetime]$RunDate,

        [Parameter(Mandatory=$true)][System.Collections.IEnumerable]$Rows

    )

    if (-not (Test-IsAdodbConnection -Connection $Connection)) { return $false }

    $rowsBuffer = New-Object 'System.Collections.Generic.List[object]'

    foreach ($row in $Rows) {

        if ($null -ne $row) { $rowsBuffer.Add($row) | Out-Null }

    }

    if ($rowsBuffer.Count -eq 0) { return $true }

    if (-not (Ensure-InterfaceBulkSeedTable -Connection $Connection)) { return $false }

    $batchId = ([guid]::NewGuid()).ToString()

    $escBatch = $batchId -replace "'", "''"

    $escHostname = $Hostname -replace "'", "''"

    $runDateText = $RunDate.ToString('yyyy-MM-dd HH:mm:ss')

    $insertSql = 'INSERT INTO InterfaceBulkSeed (BatchId, Hostname, RunDateText, Port, Name, Status, VLAN, Duplex, Speed, Type, LearnedMACs, AuthState, AuthMode, AuthClientMAC, AuthTemplate, Config, PortColor, ConfigStatus, ToolTip) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'

    $insertCmd = New-AdodbTextCommand -Connection $Connection -CommandText $insertSql

    if (-not $insertCmd) { return $false }

    $cleanupSql = "DELETE FROM InterfaceBulkSeed WHERE BatchId = '$escBatch'"

    $stagedCount = 0

    try {

        $parameters = @(

            Add-AdodbParameter -Command $insertCmd -Name 'BatchId' -Type $script:AdTypeVarWChar -Size 36

            Add-AdodbParameter -Command $insertCmd -Name 'Hostname' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $insertCmd -Name 'RunDateText' -Type $script:AdTypeVarWChar -Size 32

            Add-AdodbParameter -Command $insertCmd -Name 'Port' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $insertCmd -Name 'Name' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $insertCmd -Name 'Status' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $insertCmd -Name 'VLAN' -Type $script:AdTypeInteger

            Add-AdodbParameter -Command $insertCmd -Name 'Duplex' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $insertCmd -Name 'Speed' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $insertCmd -Name 'Type' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $insertCmd -Name 'Learned' -Type $script:AdTypeLongVarWChar

            Add-AdodbParameter -Command $insertCmd -Name 'AuthState' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $insertCmd -Name 'AuthMode' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $insertCmd -Name 'AuthClient' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $insertCmd -Name 'AuthTemplate' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $insertCmd -Name 'Config' -Type $script:AdTypeLongVarWChar

            Add-AdodbParameter -Command $insertCmd -Name 'PortColor' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $insertCmd -Name 'ConfigStatus' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $insertCmd -Name 'ToolTip' -Type $script:AdTypeLongVarWChar

        )

        if ($parameters -contains $null) {

            try { $Connection.Execute($cleanupSql) | Out-Null } catch { }

            return $false

        }

        foreach ($row in $rowsBuffer) {

            $vlanNumeric = 0

            if ($row.PSObject.Properties.Name -contains 'VlanNumeric' -and $null -ne $row.VlanNumeric) {

                try { $vlanNumeric = [int]$row.VlanNumeric } catch { $vlanNumeric = 0 }

            } elseif ($row.PSObject.Properties.Name -contains 'VLAN') {

                [void][int]::TryParse($row.VLAN, [ref]$vlanNumeric)

            }

            Set-AdodbParameterValue -Parameter $parameters[0] -Value $batchId

            Set-AdodbParameterValue -Parameter $parameters[1] -Value $Hostname

            Set-AdodbParameterValue -Parameter $parameters[2] -Value $runDateText

            Set-AdodbParameterValue -Parameter $parameters[3] -Value ([string]$row.Port)

            Set-AdodbParameterValue -Parameter $parameters[4] -Value ([string]$row.Name)

            Set-AdodbParameterValue -Parameter $parameters[5] -Value ([string]$row.Status)

            Set-AdodbParameterValue -Parameter $parameters[6] -Value $vlanNumeric

            Set-AdodbParameterValue -Parameter $parameters[7] -Value ([string]$row.Duplex)

            Set-AdodbParameterValue -Parameter $parameters[8] -Value ([string]$row.Speed)

            Set-AdodbParameterValue -Parameter $parameters[9] -Value ([string]$row.Type)

            Set-AdodbParameterValue -Parameter $parameters[10] -Value ([string]$row.Learned)

            Set-AdodbParameterValue -Parameter $parameters[11] -Value ([string]$row.AuthState)

            Set-AdodbParameterValue -Parameter $parameters[12] -Value ([string]$row.AuthMode)

            Set-AdodbParameterValue -Parameter $parameters[13] -Value ([string]$row.AuthClient)

            Set-AdodbParameterValue -Parameter $parameters[14] -Value ([string]$row.Template)

            Set-AdodbParameterValue -Parameter $parameters[15] -Value ([string]$row.Config)

            Set-AdodbParameterValue -Parameter $parameters[16] -Value ([string]$row.PortColor)

            Set-AdodbParameterValue -Parameter $parameters[17] -Value ([string]$row.StatusTag)

            Set-AdodbParameterValue -Parameter $parameters[18] -Value ([string]$row.ToolTip)

            try {

                $insertCmd.Execute() | Out-Null

            } catch {

                try { $Connection.Execute($cleanupSql) | Out-Null } catch { }

                throw

            }

            $stagedCount++

        }

    } catch {

        Write-Warning ("Failed to stage interfaces for host {0}: {1}" -f $Hostname, $_.Exception.Message)

        return $false

    } finally {

        Release-ComObjectSafe -ComObject $insertCmd

    }

    if ($stagedCount -eq 0) {

        try { $Connection.Execute($cleanupSql) | Out-Null } catch { }

        return $true

    }

    $success = $false

    try {

        $insertInterfacesSql = "INSERT INTO Interfaces (Hostname, Port, Name, Status, VLAN, Duplex, Speed, Type, LearnedMACs, AuthState, AuthMode, AuthClientMAC, AuthTemplate, Config, PortColor, ConfigStatus, ToolTip)

SELECT Hostname, Port, Name, Status, VLAN, Duplex, Speed, Type, LearnedMACs, AuthState, AuthMode, AuthClientMAC, AuthTemplate, Config, PortColor, ConfigStatus, ToolTip

FROM InterfaceBulkSeed

WHERE BatchId = '$escBatch' AND Hostname = '$escHostname'"

        $Connection.Execute($insertInterfacesSql) | Out-Null

        $insertHistorySql = "INSERT INTO InterfaceHistory (Hostname, RunDate, Port, Name, Status, VLAN, Duplex, Speed, Type, LearnedMACs, AuthState, AuthMode, AuthClientMAC, AuthTemplate, Config, PortColor, ConfigStatus, ToolTip)

SELECT Hostname, CDate(RunDateText), Port, Name, Status, VLAN, Duplex, Speed, Type, LearnedMACs, AuthState, AuthMode, AuthClientMAC, AuthTemplate, Config, PortColor, ConfigStatus, ToolTip

FROM InterfaceBulkSeed

WHERE BatchId = '$escBatch' AND Hostname = '$escHostname'"

        $Connection.Execute($insertHistorySql) | Out-Null

        $success = $true

    } catch {

        Write-Warning ("Failed to commit bulk interface rows for host {0}: {1}" -f $Hostname, $_.Exception.Message)

    } finally {

        try { $Connection.Execute($cleanupSql) | Out-Null } catch { }

    }

    try {

        TelemetryModule\Write-StTelemetryEvent -Name 'InterfaceBulkInsert' -Payload @{

            Hostname = $Hostname

            BatchId  = $batchId

            Rows     = [int]$rowsBuffer.Count

            RunDate  = $runDateText

            Success  = $success

        }

    } catch { }

    return $success

}







function Invoke-DeviceSummaryParameterized {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Connection,
        [Parameter(Mandatory=$true)][string]$Hostname,
        [Parameter(Mandatory=$true)][hashtable]$Values,
        [Parameter(Mandatory=$true)][datetime]$RunDate
    )

    $updateSql = 'UPDATE DeviceSummary SET Make=?, Model=?, Uptime=?, Site=?, Building=?, Room=?, Ports=?, AuthDefaultVLAN=?, AuthBlock=? WHERE Hostname=?'
    $updateCmd = New-AdodbTextCommand -Connection $Connection -CommandText $updateSql
    if (-not $updateCmd) { return $false }

    try {
        $parameters = @(
            Add-AdodbParameter -Command $updateCmd -Name 'Make' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $updateCmd -Name 'Model' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $updateCmd -Name 'Uptime' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $updateCmd -Name 'Site' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $updateCmd -Name 'Building' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $updateCmd -Name 'Room' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $updateCmd -Name 'Ports' -Type $script:AdTypeInteger
            Add-AdodbParameter -Command $updateCmd -Name 'AuthDefaultVLAN' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $updateCmd -Name 'AuthBlock' -Type $script:AdTypeLongVarWChar
            Add-AdodbParameter -Command $updateCmd -Name 'Hostname' -Type $script:AdTypeVarWChar -Size 255
        )

        if ($parameters -contains $null) { return $false }

        Set-AdodbParameterValue -Parameter $parameters[0] -Value ([string]$Values.Make)
        Set-AdodbParameterValue -Parameter $parameters[1] -Value ([string]$Values.Model)
        Set-AdodbParameterValue -Parameter $parameters[2] -Value ([string]$Values.Uptime)
        Set-AdodbParameterValue -Parameter $parameters[3] -Value ([string]$Values.Site)
        Set-AdodbParameterValue -Parameter $parameters[4] -Value ([string]$Values.Building)
        Set-AdodbParameterValue -Parameter $parameters[5] -Value ([string]$Values.Room)
        Set-AdodbParameterValue -Parameter $parameters[6] -Value ([int]$Values.Ports)
        Set-AdodbParameterValue -Parameter $parameters[7] -Value ([string]$Values.AuthDefaultVlan)
        Set-AdodbParameterValue -Parameter $parameters[8] -Value ([string]$Values.AuthBlock)
        Set-AdodbParameterValue -Parameter $parameters[9] -Value $Hostname

        try { $updateCmd.Execute() | Out-Null } catch { }
    } finally {
        Release-ComObjectSafe -ComObject $updateCmd
    }

    $insertSql = 'INSERT INTO DeviceSummary (Hostname, Make, Model, Uptime, Site, Building, Room, Ports, AuthDefaultVLAN, AuthBlock) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
    $insertCmd = New-AdodbTextCommand -Connection $Connection -CommandText $insertSql
    if (-not $insertCmd) { return $false }

    try {
        $parameters = @(
            Add-AdodbParameter -Command $insertCmd -Name 'Hostname' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $insertCmd -Name 'Make' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $insertCmd -Name 'Model' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $insertCmd -Name 'Uptime' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $insertCmd -Name 'Site' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $insertCmd -Name 'Building' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $insertCmd -Name 'Room' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $insertCmd -Name 'Ports' -Type $script:AdTypeInteger
            Add-AdodbParameter -Command $insertCmd -Name 'AuthDefaultVLAN' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $insertCmd -Name 'AuthBlock' -Type $script:AdTypeLongVarWChar
        )

        if ($parameters -contains $null) { return $false }

        Set-AdodbParameterValue -Parameter $parameters[0] -Value $Hostname
        Set-AdodbParameterValue -Parameter $parameters[1] -Value ([string]$Values.Make)
        Set-AdodbParameterValue -Parameter $parameters[2] -Value ([string]$Values.Model)
        Set-AdodbParameterValue -Parameter $parameters[3] -Value ([string]$Values.Uptime)
        Set-AdodbParameterValue -Parameter $parameters[4] -Value ([string]$Values.Site)
        Set-AdodbParameterValue -Parameter $parameters[5] -Value ([string]$Values.Building)
        Set-AdodbParameterValue -Parameter $parameters[6] -Value ([string]$Values.Room)
        Set-AdodbParameterValue -Parameter $parameters[7] -Value ([int]$Values.Ports)
        Set-AdodbParameterValue -Parameter $parameters[8] -Value ([string]$Values.AuthDefaultVlan)
        Set-AdodbParameterValue -Parameter $parameters[9] -Value ([string]$Values.AuthBlock)

        try { $insertCmd.Execute() | Out-Null } catch { }
    } finally {
        Release-ComObjectSafe -ComObject $insertCmd
    }

    $historySql = 'INSERT INTO DeviceHistory (Hostname, RunDate, Make, Model, Uptime, Site, Building, Room, Ports, AuthDefaultVLAN, AuthBlock) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
    $historyCmd = New-AdodbTextCommand -Connection $Connection -CommandText $historySql
    if (-not $historyCmd) { return $false }

    try {
        $parameters = @(
            Add-AdodbParameter -Command $historyCmd -Name 'Hostname' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $historyCmd -Name 'RunDate' -Type $script:AdTypeVarWChar -Size 32
            Add-AdodbParameter -Command $historyCmd -Name 'Make' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $historyCmd -Name 'Model' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $historyCmd -Name 'Uptime' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $historyCmd -Name 'Site' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $historyCmd -Name 'Building' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $historyCmd -Name 'Room' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $historyCmd -Name 'Ports' -Type $script:AdTypeInteger
            Add-AdodbParameter -Command $historyCmd -Name 'AuthDefaultVLAN' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $historyCmd -Name 'AuthBlock' -Type $script:AdTypeLongVarWChar
        )

        if ($parameters -contains $null) { return $false }

        Set-AdodbParameterValue -Parameter $parameters[0] -Value $Hostname
        Set-AdodbParameterValue -Parameter $parameters[1] -Value ($RunDate.ToString('yyyy-MM-dd HH:mm:ss'))
        Set-AdodbParameterValue -Parameter $parameters[2] -Value ([string]$Values.Make)
        Set-AdodbParameterValue -Parameter $parameters[3] -Value ([string]$Values.Model)
        Set-AdodbParameterValue -Parameter $parameters[4] -Value ([string]$Values.Uptime)
        Set-AdodbParameterValue -Parameter $parameters[5] -Value ([string]$Values.Site)
        Set-AdodbParameterValue -Parameter $parameters[6] -Value ([string]$Values.Building)
        Set-AdodbParameterValue -Parameter $parameters[7] -Value ([string]$Values.Room)
        Set-AdodbParameterValue -Parameter $parameters[8] -Value ([int]$Values.Ports)
        Set-AdodbParameterValue -Parameter $parameters[9] -Value ([string]$Values.AuthDefaultVlan)
        Set-AdodbParameterValue -Parameter $parameters[10] -Value ([string]$Values.AuthBlock)

        try { $historyCmd.Execute() | Out-Null } catch {
            Write-Warning "Failed to insert device history for host ${Hostname}: $($_.Exception.Message)"
            Write-Verbose ("Device history exception details: {0}" -f ($_.Exception | Format-List * | Out-String))
        }
    } finally {
        Release-ComObjectSafe -ComObject $historyCmd
    }

    return $true
}

function Invoke-InterfaceRowParameterized {

    [CmdletBinding()]

    param(

        [Parameter(Mandatory=$true)][object]$Connection,

        [Parameter(Mandatory=$true)][string]$Hostname,

        [Parameter(Mandatory=$true)][object]$Row,

        [Parameter(Mandatory=$true)][datetime]$RunDate

    )



    $insertSql = 'INSERT INTO Interfaces (Hostname, Port, Name, Status, VLAN, Duplex, Speed, Type, LearnedMACs, AuthState, AuthMode, AuthClientMAC, AuthTemplate, Config, PortColor, ConfigStatus, ToolTip) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'

    $insertCmd = New-AdodbTextCommand -Connection $Connection -CommandText $insertSql

    if (-not $insertCmd) { return $false }



    $vlanNumeric = 0

    if ($Row.PSObject.Properties.Name -contains 'VlanNumeric' -and $null -ne $Row.VlanNumeric) {

        try { $vlanNumeric = [int]$Row.VlanNumeric } catch { $vlanNumeric = 0 }

    } else {

        [void][int]::TryParse($Row.VLAN, [ref]$vlanNumeric)

    }



    try {

        $parameters = @(

            Add-AdodbParameter -Command $insertCmd -Name 'Hostname' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $insertCmd -Name 'Port' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $insertCmd -Name 'Name' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $insertCmd -Name 'Status' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $insertCmd -Name 'VLAN' -Type $script:AdTypeInteger

            Add-AdodbParameter -Command $insertCmd -Name 'Duplex' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $insertCmd -Name 'Speed' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $insertCmd -Name 'Type' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $insertCmd -Name 'Learned' -Type $script:AdTypeLongVarWChar

            Add-AdodbParameter -Command $insertCmd -Name 'AuthState' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $insertCmd -Name 'AuthMode' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $insertCmd -Name 'AuthClient' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $insertCmd -Name 'AuthTemplate' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $insertCmd -Name 'Config' -Type $script:AdTypeLongVarWChar

            Add-AdodbParameter -Command $insertCmd -Name 'PortColor' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $insertCmd -Name 'ConfigStatus' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $insertCmd -Name 'ToolTip' -Type $script:AdTypeLongVarWChar

        )



        if ($parameters -contains $null) { return $false }



        Set-AdodbParameterValue -Parameter $parameters[0] -Value $Hostname

        Set-AdodbParameterValue -Parameter $parameters[1] -Value ([string]$Row.Port)

        Set-AdodbParameterValue -Parameter $parameters[2] -Value ([string]$Row.Name)

        Set-AdodbParameterValue -Parameter $parameters[3] -Value ([string]$Row.Status)

        Set-AdodbParameterValue -Parameter $parameters[4] -Value $vlanNumeric

        Set-AdodbParameterValue -Parameter $parameters[5] -Value ([string]$Row.Duplex)

        Set-AdodbParameterValue -Parameter $parameters[6] -Value ([string]$Row.Speed)

        Set-AdodbParameterValue -Parameter $parameters[7] -Value ([string]$Row.Type)

        Set-AdodbParameterValue -Parameter $parameters[8] -Value ([string]$Row.Learned)

        Set-AdodbParameterValue -Parameter $parameters[9] -Value ([string]$Row.AuthState)

        Set-AdodbParameterValue -Parameter $parameters[10] -Value ([string]$Row.AuthMode)

        Set-AdodbParameterValue -Parameter $parameters[11] -Value ([string]$Row.AuthClient)

        Set-AdodbParameterValue -Parameter $parameters[12] -Value ([string]$Row.Template)

        Set-AdodbParameterValue -Parameter $parameters[13] -Value ([string]$Row.Config)

        Set-AdodbParameterValue -Parameter $parameters[14] -Value ([string]$Row.PortColor)

        Set-AdodbParameterValue -Parameter $parameters[15] -Value ([string]$Row.StatusTag)

        Set-AdodbParameterValue -Parameter $parameters[16] -Value ([string]$Row.ToolTip)



        try {

            $insertCmd.Execute() | Out-Null

        } catch {

            Write-Warning "Failed to insert interface record for host ${Hostname} port ${Row.Port}: $($_.Exception.Message)"

            Write-Verbose ("Interface insert exception details: {0}" -f ($_.Exception | Format-List * | Out-String))

            return $false

        }

    } finally {

        Release-ComObjectSafe -ComObject $insertCmd

    }



    $historySql = 'INSERT INTO InterfaceHistory (Hostname, RunDate, Port, Name, Status, VLAN, Duplex, Speed, Type, LearnedMACs, AuthState, AuthMode, AuthClientMAC, AuthTemplate, Config, PortColor, ConfigStatus, ToolTip) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'

    $historyCmd = New-AdodbTextCommand -Connection $Connection -CommandText $historySql

    if (-not $historyCmd) { return $true }



    try {

        $parameters = @(

            Add-AdodbParameter -Command $historyCmd -Name 'Hostname' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $historyCmd -Name 'RunDate' -Type $script:AdTypeVarWChar -Size 32

            Add-AdodbParameter -Command $historyCmd -Name 'Port' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $historyCmd -Name 'Name' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $historyCmd -Name 'Status' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $historyCmd -Name 'VLAN' -Type $script:AdTypeInteger

            Add-AdodbParameter -Command $historyCmd -Name 'Duplex' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $historyCmd -Name 'Speed' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $historyCmd -Name 'Type' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $historyCmd -Name 'Learned' -Type $script:AdTypeLongVarWChar

            Add-AdodbParameter -Command $historyCmd -Name 'AuthState' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $historyCmd -Name 'AuthMode' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $historyCmd -Name 'AuthClient' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $historyCmd -Name 'AuthTemplate' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $historyCmd -Name 'Config' -Type $script:AdTypeLongVarWChar

            Add-AdodbParameter -Command $historyCmd -Name 'PortColor' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $historyCmd -Name 'ConfigStatus' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $historyCmd -Name 'ToolTip' -Type $script:AdTypeLongVarWChar

        )



        if ($parameters -contains $null) { return $true }



        Set-AdodbParameterValue -Parameter $parameters[0] -Value $Hostname

        Set-AdodbParameterValue -Parameter $parameters[1] -Value ($RunDate.ToString('yyyy-MM-dd HH:mm:ss'))

        Set-AdodbParameterValue -Parameter $parameters[2] -Value ([string]$Row.Port)

        Set-AdodbParameterValue -Parameter $parameters[3] -Value ([string]$Row.Name)

        Set-AdodbParameterValue -Parameter $parameters[4] -Value ([string]$Row.Status)

        Set-AdodbParameterValue -Parameter $parameters[5] -Value $vlanNumeric

        Set-AdodbParameterValue -Parameter $parameters[6] -Value ([string]$Row.Duplex)

        Set-AdodbParameterValue -Parameter $parameters[7] -Value ([string]$Row.Speed)

        Set-AdodbParameterValue -Parameter $parameters[8] -Value ([string]$Row.Type)

        Set-AdodbParameterValue -Parameter $parameters[9] -Value ([string]$Row.Learned)

        Set-AdodbParameterValue -Parameter $parameters[10] -Value ([string]$Row.AuthState)

        Set-AdodbParameterValue -Parameter $parameters[11] -Value ([string]$Row.AuthMode)

        Set-AdodbParameterValue -Parameter $parameters[12] -Value ([string]$Row.AuthClient)

        Set-AdodbParameterValue -Parameter $parameters[13] -Value ([string]$Row.Template)

        Set-AdodbParameterValue -Parameter $parameters[14] -Value ([string]$Row.Config)

        Set-AdodbParameterValue -Parameter $parameters[15] -Value ([string]$Row.PortColor)

        Set-AdodbParameterValue -Parameter $parameters[16] -Value ([string]$Row.StatusTag)

        Set-AdodbParameterValue -Parameter $parameters[17] -Value ([string]$Row.ToolTip)



        try {

            $historyCmd.Execute() | Out-Null

        } catch {

            Write-Warning "Failed to insert interface history for host ${Hostname} port ${Row.Port}: $($_.Exception.Message)"

        }

    } finally {

        Release-ComObjectSafe -ComObject $historyCmd

    }



    return $true

}





function Write-InterfacePersistenceFailure {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Stage,
        [Parameter(Mandatory=$true)][string]$Hostname,
        [Parameter(Mandatory=$true)][System.Exception]$Exception,
        [Parameter()][hashtable]$Metadata
    )

    $payload = @{
        Stage = $Stage
        Hostname = $Hostname
        ExceptionMessage = $Exception.Message
        ExceptionType = $Exception.GetType().FullName
    }

    if ($Metadata) {
        foreach ($key in $Metadata.Keys) {
            $payload[$key] = $Metadata[$key]
        }
    }

    try {
        TelemetryModule\Write-StTelemetryEvent -Name 'InterfacePersistenceFailure' -Payload $payload
    } catch {
        Write-Warning ("Failed to emit interface persistence telemetry: {0}" -f $_.Exception.Message)
    }
}

function Update-SpanInfoInDb {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Connection,
        [Parameter(Mandatory=$true)][string]$Hostname,
        [Parameter(Mandatory=$true)][string]$RunDateString,
        [Parameter()][object[]]$SpanInfo
    )

    $escHostname = $Hostname -replace "'", "''"
    $runDateLiteral = "#$RunDateString#"

    try {
        $Connection.Execute("DELETE FROM SpanInfo WHERE Hostname = '$escHostname'") | Out-Null
    } catch {
        Write-Warning "Failed to clear span data for host ${Hostname}: $($_.Exception.Message)"
    }

    if (-not $SpanInfo) { return }

    foreach ($item in $SpanInfo) {
        if ($null -eq $item) { continue }

        $vlan = ''
        if ($item.PSObject.Properties['VLAN']) { $vlan = '' + $item.VLAN }

        $rootSwitch = ''
        if ($item.PSObject.Properties['RootSwitch']) { $rootSwitch = '' + $item.RootSwitch }

        $rootPort = ''
        if ($item.PSObject.Properties['RootPort']) { $rootPort = '' + $item.RootPort }

        $role = ''
        if ($item.PSObject.Properties['Role']) { $role = '' + $item.Role }

        $upstream = ''
        if ($item.PSObject.Properties['Upstream']) { $upstream = '' + $item.Upstream }

        $escVlan     = $vlan -replace "'", "''"
        $escRoot     = $rootSwitch -replace "'", "''"
        $escPort     = $rootPort -replace "'", "''"
        $escRole     = $role -replace "'", "''"
        $escUpstream = $upstream -replace "'", "''"

        $insertSql = "INSERT INTO SpanInfo (Hostname, Vlan, RootSwitch, RootPort, Role, Upstream, LastUpdated) VALUES ('$escHostname', '$escVlan', '$escRoot', '$escPort', '$escRole', '$escUpstream', $runDateLiteral)"
        try {
            $Connection.Execute($insertSql) | Out-Null
        } catch {
            Write-Warning "Failed to insert span info for host ${Hostname}: $($_.Exception.Message)"
        }

        $histSql = "INSERT INTO SpanHistory (Hostname, RunDate, Vlan, RootSwitch, RootPort, Role, Upstream) VALUES ('$escHostname', $runDateLiteral, '$escVlan', '$escRoot', '$escPort', '$escRole', '$escUpstream')"
        try {
            $Connection.Execute($histSql) | Out-Null
        } catch {
            Write-Warning "Failed to insert span history for host ${Hostname}: $($_.Exception.Message)"
        }
    }
}
Export-ModuleMember -Function Update-DeviceSummaryInDb, Update-InterfacesInDb, Update-SpanInfoInDb, Write-InterfacePersistenceFailure
