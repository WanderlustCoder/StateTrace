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
    # Escape hostname once for reuse
    $escHostname = $Hostname -replace "'", "''"
    # Delete existing interface rows for this host using a retry loop to
    $delSql = "DELETE FROM Interfaces WHERE Hostname = '$escHostname'"
    $deleted = $false
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            $Connection.Execute($delSql) | Out-Null
            $deleted = $true
            break
        } catch {
            if ($attempt -lt 3) {
                Start-Sleep -Milliseconds 200
            } else {
                Write-Warning "Failed to delete old interface rows for host ${Hostname}: $($_.Exception.Message)"
            }
        }
    }
    # Determine which interface collection to use
    $ifaceRecords = $null
    if ($Facts.PSObject.Properties.Name -contains 'InterfacesCombined') {
        $ifaceRecords = $Facts.InterfacesCombined
    } elseif ($Facts.PSObject.Properties.Name -contains 'Interfaces') {
        $ifaceRecords = $Facts.Interfaces
    }
    if (-not $ifaceRecords) { return }
    # Prepare run date literal for history table
    $runDateLiteral = "#$RunDateString#"
    foreach ($iface in $ifaceRecords) {
        # Extract scalar fields safely
        $port   = '' + $iface.Port
        $name   = '' + $iface.Name
        $status = '' + $iface.Status
        $vlan   = '' + $iface.VLAN
        $duplex = '' + $iface.Duplex
        $speed  = '' + $iface.Speed
        $type   = '' + $iface.Type
        # Normalize LearnedMACs handling so that both strings and arrays
        # are written correctly.  Prefer the full list property when
        # provided; otherwise join array elements or accept the string as-is.
        $learned = ''
        if ($iface.PSObject.Properties.Name -contains 'LearnedMACsFull' -and ($iface.LearnedMACsFull)) {
            # The vendor module provided an explicit comma-separated string of
            # all learned MACs; use it directly.
            $learned = '' + $iface.LearnedMACsFull
        } elseif ($iface.PSObject.Properties.Name -contains 'LearnedMACs') {
            $lm = $iface.LearnedMACs
            if ($lm -is [string]) {
                # Already a single MAC string; assign as-is
                $learned = $lm
            } elseif ($lm -ne $null) {
                # Join a list of MACs into a comma-separated string.  Filter out
                # null or empty entries to avoid extraneous commas.  Use a
                # strongly typed list instead of a Where-Object pipeline.
                $macList = New-Object 'System.Collections.Generic.List[string]'
                foreach ($mac in $lm) {
                    if ($mac -and $mac -ne '') { [void]$macList.Add($mac) }
                }
                $learned = [string]::Join(',', $macList.ToArray())
            }
        }
        $authState = ''
        if ($iface.PSObject.Properties.Name -contains 'AuthState') {
            $authState = $iface.AuthState
        }
        $authMode = ''
        if ($iface.PSObject.Properties.Name -contains 'AuthMode') {
            $authMode = $iface.AuthMode
        }
        $authClient = ''
        if ($iface.PSObject.Properties.Name -contains 'AuthClientMAC') {
            $authClient = $iface.AuthClientMAC
        }
        $authTemplate = ''
        if ($iface.PSObject.Properties.Name -contains 'AuthTemplate') {
            $authTemplate = $iface.AuthTemplate
        }
        $configText = ''
        if ($iface.PSObject.Properties.Name -contains 'Config') {
            $configText = $iface.Config
        }
        # If the config is empty and this is a Brocade device, substitute
        if (-not $configText -or ($configText -is [string] -and $configText.Trim() -eq '')) {
            if ($Facts -and $Facts.Make -eq 'Brocade') {
                if ($Facts.PSObject.Properties.Name -contains 'AuthenticationBlock' -and $Facts.AuthenticationBlock) {
                    $configText = "AUTH BLOCK (GLOBAL)`r`n" + ($Facts.AuthenticationBlock -join "`r`n")
                }
            }
        }
        # Compose a tooltip combining the template name and the raw config
        $toolTip = "AuthTemplate: $authTemplate"
        if ($configText) { $toolTip = "$toolTip`n`n$configText" }
        # Compute compliance fields based on templates
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
        # Escape fields for SQL
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
        # Convert VLAN to numeric when possible
        $vlanNumeric = 0
        [void][int]::TryParse($vlan, [ref]$vlanNumeric)
        # Build insert SQL for Interfaces and InterfaceHistory
        $ifaceSql = "INSERT INTO Interfaces (Hostname, Port, Name, Status, VLAN, Duplex, Speed, Type, LearnedMACs, AuthState, AuthMode, AuthClientMAC, AuthTemplate, Config, PortColor, ConfigStatus, ToolTip) VALUES ('$escHostname', '$escPort', '$escName', '$escStatus', $vlanNumeric, '$escDuplex', '$escSpeed', '$escType', '$escLearned', '$escState', '$escModeFld', '$escClient', '$escTemplate', '$escConfig', '$escColor', '$escCfgStat', '$escToolTip')"
        try {
            $Connection.Execute($ifaceSql) | Out-Null
        } catch {
            Write-Warning "Failed to insert interface record for host ${Hostname} port ${port}: $($_.Exception.Message)"
        }
        $histIfaceSql = "INSERT INTO InterfaceHistory (Hostname, RunDate, Port, Name, Status, VLAN, Duplex, Speed, Type, LearnedMACs, AuthState, AuthMode, AuthClientMAC, AuthTemplate, Config, PortColor, ConfigStatus, ToolTip) VALUES ('$escHostname', $runDateLiteral, '$escPort', '$escName', '$escStatus', $vlanNumeric, '$escDuplex', '$escSpeed', '$escType', '$escLearned', '$escState', '$escModeFld', '$escClient', '$escTemplate', '$escConfig', '$escColor', '$escCfgStat', '$escToolTip')"
        try {
            $Connection.Execute($histIfaceSql) | Out-Null
        } catch {
            Write-Warning "Failed to insert interface history for host ${Hostname} port ${port}: $($_.Exception.Message)"
        }
    }
}

Export-ModuleMember -Function Update-DeviceSummaryInDb, Update-InterfacesInDb
