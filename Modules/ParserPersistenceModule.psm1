Set-StrictMode -Version Latest

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

        $toolTip = "AuthTemplate: $authTemplate"
        if ($configText) { $toolTip = "$toolTip`n`n$configText" }

        $portColor    = 'Gray'
        $configStatus = 'Mismatch'
        if ($Templates) {
            foreach ($tpl in $Templates) {
                $nameMatch  = $false
                if ($tpl.name) {
                    if ($tpl.name -ieq $authTemplate) { $nameMatch = $true }
                }
                $aliasMatch = $false
                if (-not $nameMatch -and $tpl.aliases) {
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

        $newRow = [PSCustomObject]@{
            Port       = $normalizedPort
            Name       = $name
            Status     = $status
            VLAN       = '' + $vlan
            Duplex     = $duplex
            Speed      = $speed
            Type       = $type
            Learned    = $learned
            AuthState  = $authState
            AuthMode   = $authMode
            AuthClient = $authClient
            Template   = $authTemplate
            Config     = $configText
            PortColor  = $portColor
            StatusTag  = $configStatus
            ToolTip    = $toolTip
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
        [void][int]::TryParse($Row.VLAN, [ref]$vlanNumeric)

        $ifaceSql = "INSERT INTO Interfaces (Hostname, Port, Name, Status, VLAN, Duplex, Speed, Type, LearnedMACs, AuthState, AuthMode, AuthClientMAC, AuthTemplate, Config, PortColor, ConfigStatus, ToolTip) VALUES ('$escHostname', '$escPort', '$escName', '$escStatus', $vlanNumeric, '$escDuplex', '$escSpeed', '$escType', '$escLearned', '$escState', '$escModeFld', '$escClient', '$escTemplate', '$escConfig', '$escColor', '$escCfgStat', '$escToolTip')"
        try { $Connection.Execute($ifaceSql) | Out-Null } catch { Write-Warning "Failed to insert interface record for host ${Hostname} port ${Row.Port}: $($_.Exception.Message)" }

        $histIfaceSql = "INSERT INTO InterfaceHistory (Hostname, RunDate, Port, Name, Status, VLAN, Duplex, Speed, Type, LearnedMACs, AuthState, AuthMode, AuthClientMAC, AuthTemplate, Config, PortColor, ConfigStatus, ToolTip) VALUES ('$escHostname', $runDateLiteral, '$escPort', '$escName', '$escStatus', $vlanNumeric, '$escDuplex', '$escSpeed', '$escType', '$escLearned', '$escState', '$escModeFld', '$escClient', '$escTemplate', '$escConfig', '$escColor', '$escCfgStat', '$escToolTip')"
        try { $Connection.Execute($histIfaceSql) | Out-Null } catch { Write-Warning "Failed to insert interface history for host ${Hostname} port ${Row.Port}: $($_.Exception.Message)" }
    }

    foreach ($row in $toInsert) {
        Add-InterfaceRow -Row $row
    }

    foreach ($row in $toUpdate) {
        $escPortSingle = $row.Port -replace "'", "''"
        $deleteSql = "DELETE FROM Interfaces WHERE Hostname = '$escHostname' AND Port = '$escPortSingle'"
        try { $Connection.Execute($deleteSql) | Out-Null } catch { Write-Warning "Failed to clear existing port ${Hostname}/${row.Port}: $($_.Exception.Message)" }
        Add-InterfaceRow -Row $row
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
Export-ModuleMember -Function Update-DeviceSummaryInDb, Update-InterfacesInDb, Update-SpanInfoInDb
