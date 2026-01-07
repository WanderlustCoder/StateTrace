# IntegrationApiModule.psm1
# REST API endpoint handlers for StateTrace integrations

Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot

# Lazy load modules as needed
function Import-RequiredModule {
    param([string]$ModuleName)
    $path = Join-Path $projectRoot "Modules\$ModuleName.psm1"
    if (Test-Path $path) {
        Import-Module $path -Force -DisableNameChecking -ErrorAction SilentlyContinue
    }
}

#region Health & Info

function Get-ApiHealth {
    <#
    .SYNOPSIS
    Health check endpoint.
    #>
    return @{
        status = 'healthy'
        service = 'StateTrace API'
        version = '1.0.0'
        timestamp = [datetime]::UtcNow.ToString('o')
        uptime = [Math]::Round(([datetime]::UtcNow - $script:StartTime).TotalSeconds)
    }
}

function Get-ApiStats {
    <#
    .SYNOPSIS
    Returns API usage statistics.
    #>
    return @{
        requestCount = $script:RequestCount
        startTime = $script:StartTime.ToString('o')
        uptimeSeconds = [Math]::Round(([datetime]::UtcNow - $script:StartTime).TotalSeconds)
    }
}

function Get-ApiVendors {
    <#
    .SYNOPSIS
    Returns list of supported vendors.
    #>
    Import-RequiredModule 'VendorDetectionModule'

    try {
        $vendors = Get-SupportedVendors
        return @{
            vendors = $vendors
            count = $vendors.Count
        }
    } catch {
        return @{ vendors = @('Cisco', 'Arista', 'Juniper', 'Aruba', 'PaloAlto', 'Brocade'); count = 6 }
    }
}

#endregion

#region Devices

function Get-ApiDevices {
    <#
    .SYNOPSIS
    Returns device inventory with optional filtering.
    #>
    param([hashtable]$Request)

    Import-RequiredModule 'DeviceRepositoryModule'

    $query = $Request.Query

    try {
        # Get all devices
        $devices = Get-AllDevices -ErrorAction SilentlyContinue

        if (-not $devices) {
            # Return sample data if no devices loaded
            return @{
                devices = @()
                count = 0
                message = 'No devices currently loaded'
            }
        }

        # Apply filters
        if ($query.site) {
            $devices = $devices | Where-Object { $_.Site -like "*$($query.site)*" }
        }
        if ($query.vendor -or $query.make) {
            $vendorFilter = if ($query.vendor) { $query.vendor } else { $query.make }
            $devices = $devices | Where-Object { $_.Make -like "*$vendorFilter*" }
        }
        if ($query.hostname) {
            $devices = $devices | Where-Object { $_.Hostname -like "*$($query.hostname)*" }
        }

        # Pagination
        $page = if ($query.page) { [int]$query.page } else { 1 }
        $pageSize = if ($query.pageSize) { [int]$query.pageSize } else { 100 }
        $skip = ($page - 1) * $pageSize

        $totalCount = @($devices).Count
        $pagedDevices = $devices | Select-Object -Skip $skip -First $pageSize

        # Select fields to return
        $result = $pagedDevices | ForEach-Object {
            @{
                hostname = $_.Hostname
                site = $_.Site
                make = $_.Make
                model = $_.Model
                version = $_.Version
                uptime = $_.Uptime
                location = $_.Location
                interfaceCount = $_.InterfaceCount
            }
        }

        return @{
            devices = @($result)
            count = @($result).Count
            totalCount = $totalCount
            page = $page
            pageSize = $pageSize
            totalPages = [Math]::Ceiling($totalCount / $pageSize)
        }

    } catch {
        return @{ StatusCode = 500; Body = @{ error = $true; message = $_.Exception.Message } }
    }
}

function Get-ApiDeviceById {
    <#
    .SYNOPSIS
    Returns a specific device by hostname.
    #>
    param([string]$DeviceId)

    Import-RequiredModule 'DeviceRepositoryModule'

    try {
        $device = Get-DeviceByHostname -Hostname $DeviceId -ErrorAction SilentlyContinue

        if (-not $device) {
            return @{ StatusCode = 404; Body = @{ error = $true; message = "Device not found: $DeviceId" } }
        }

        return @{
            hostname = $device.Hostname
            site = $device.Site
            make = $device.Make
            model = $device.Model
            version = $device.Version
            uptime = $device.Uptime
            location = $device.Location
            interfaceCount = $device.InterfaceCount
            interfaces = $device.InterfacesCombined | ForEach-Object {
                @{
                    port = $_.Port
                    name = $_.Name
                    status = $_.Status
                    vlan = $_.VLAN
                    speed = $_.Speed
                    duplex = $_.Duplex
                }
            }
        }

    } catch {
        return @{ StatusCode = 500; Body = @{ error = $true; message = $_.Exception.Message } }
    }
}

#endregion

#region Interfaces

function Get-ApiInterfaces {
    <#
    .SYNOPSIS
    Returns interface status across all devices with filtering.
    #>
    param([hashtable]$Request)

    Import-RequiredModule 'DeviceRepositoryModule'

    $query = $Request.Query

    try {
        $devices = Get-AllDevices -ErrorAction SilentlyContinue

        if (-not $devices) {
            return @{ interfaces = @(); count = 0 }
        }

        $interfaces = [System.Collections.Generic.List[object]]::new()

        foreach ($device in $devices) {
            foreach ($iface in $device.InterfacesCombined) {
                $obj = @{
                    hostname = $device.Hostname
                    site = $device.Site
                    port = $iface.Port
                    name = $iface.Name
                    status = $iface.Status
                    vlan = $iface.VLAN
                    speed = $iface.Speed
                    duplex = $iface.Duplex
                    type = $iface.Type
                }
                [void]$interfaces.Add($obj)
            }
        }

        # Apply filters
        if ($query.status) {
            $interfaces = $interfaces | Where-Object { $_.status -eq $query.status }
        }
        if ($query.vlan) {
            $interfaces = $interfaces | Where-Object { $_.vlan -eq $query.vlan }
        }
        if ($query.hostname) {
            $interfaces = $interfaces | Where-Object { $_.hostname -like "*$($query.hostname)*" }
        }

        # Pagination
        $page = if ($query.page) { [int]$query.page } else { 1 }
        $pageSize = if ($query.pageSize) { [int]$query.pageSize } else { 500 }
        $skip = ($page - 1) * $pageSize

        $totalCount = $interfaces.Count
        $pagedInterfaces = $interfaces | Select-Object -Skip $skip -First $pageSize

        return @{
            interfaces = @($pagedInterfaces)
            count = @($pagedInterfaces).Count
            totalCount = $totalCount
            page = $page
            pageSize = $pageSize
        }

    } catch {
        return @{ StatusCode = 500; Body = @{ error = $true; message = $_.Exception.Message } }
    }
}

function Get-ApiInterfacesByDevice {
    <#
    .SYNOPSIS
    Returns interfaces for a specific device.
    #>
    param([string]$Device)

    Import-RequiredModule 'DeviceRepositoryModule'

    try {
        $deviceObj = Get-DeviceByHostname -Hostname $Device -ErrorAction SilentlyContinue

        if (-not $deviceObj) {
            return @{ StatusCode = 404; Body = @{ error = $true; message = "Device not found: $Device" } }
        }

        $interfaces = $deviceObj.InterfacesCombined | ForEach-Object {
            @{
                port = $_.Port
                name = $_.Name
                status = $_.Status
                vlan = $_.VLAN
                speed = $_.Speed
                duplex = $_.Duplex
                type = $_.Type
                learnedMACs = $_.LearnedMACs
                authState = $_.AuthState
            }
        }

        return @{
            device = $Device
            interfaces = @($interfaces)
            count = @($interfaces).Count
        }

    } catch {
        return @{ StatusCode = 500; Body = @{ error = $true; message = $_.Exception.Message } }
    }
}

#endregion

#region Alerts

function Get-ApiAlerts {
    <#
    .SYNOPSIS
    Returns alert history with optional filtering.
    #>
    param([hashtable]$Request)

    Import-RequiredModule 'AlertRuleModule'

    $query = $Request.Query

    try {
        $limit = if ($query.limit) { [int]$query.limit } else { 100 }
        $severity = $query.severity

        $params = @{ Last = $limit }
        if ($severity) { $params.Severity = $severity }

        $history = Get-AlertHistory @params

        return @{
            alerts = @($history | ForEach-Object {
                @{
                    id = $_.Id
                    ruleId = $_.RuleId
                    ruleName = $_.RuleName
                    source = $_.Source
                    severity = $_.Severity
                    category = $_.Category
                    message = $_.Message
                    firedAt = $_.FiredAt.ToString('o')
                    resolvedAt = if ($_.ResolvedAt) { $_.ResolvedAt.ToString('o') } else { $null }
                    state = $_.State
                }
            })
            count = @($history).Count
        }

    } catch {
        return @{ alerts = @(); count = 0 }
    }
}

function Get-ApiActiveAlerts {
    <#
    .SYNOPSIS
    Returns currently active alerts.
    #>
    Import-RequiredModule 'AlertRuleModule'

    try {
        $alerts = Get-ActiveAlerts

        return @{
            alerts = @($alerts | ForEach-Object {
                @{
                    id = $_.Id
                    ruleId = $_.RuleId
                    ruleName = $_.RuleName
                    source = $_.Source
                    severity = $_.Severity
                    category = $_.Category
                    message = $_.Message
                    firedAt = $_.FiredAt.ToString('o')
                    state = $_.State
                    acknowledgedBy = $_.AcknowledgedBy
                }
            })
            count = @($alerts).Count
        }

    } catch {
        return @{ alerts = @(); count = 0 }
    }
}

function Get-ApiAlertSummary {
    <#
    .SYNOPSIS
    Returns alert summary counts.
    #>
    Import-RequiredModule 'AlertRuleModule'

    try {
        $summary = Get-AlertSummary
        return $summary
    } catch {
        return @{ totalActive = 0; critical = 0; high = 0; medium = 0; low = 0 }
    }
}

function Set-ApiAlertAcknowledged {
    <#
    .SYNOPSIS
    Acknowledges an alert.
    #>
    param([string]$AlertId)

    Import-RequiredModule 'AlertRuleModule'

    try {
        $result = Set-AlertAcknowledged -AlertId $AlertId
        if ($result) {
            return @{ success = $true; message = "Alert $AlertId acknowledged" }
        } else {
            return @{ StatusCode = 404; Body = @{ error = $true; message = "Alert not found: $AlertId" } }
        }
    } catch {
        return @{ StatusCode = 500; Body = @{ error = $true; message = $_.Exception.Message } }
    }
}

function Remove-ApiAlert {
    <#
    .SYNOPSIS
    Clears/resolves an alert.
    #>
    param([string]$AlertId)

    Import-RequiredModule 'AlertRuleModule'

    try {
        $result = Clear-Alert -AlertId $AlertId
        if ($result) {
            return @{ success = $true; message = "Alert $AlertId cleared" }
        } else {
            return @{ StatusCode = 404; Body = @{ error = $true; message = "Alert not found: $AlertId" } }
        }
    } catch {
        return @{ StatusCode = 500; Body = @{ error = $true; message = $_.Exception.Message } }
    }
}

#endregion

# Module state
$script:StartTime = [datetime]::UtcNow
$script:RequestCount = 0

Export-ModuleMember -Function @(
    'Get-ApiHealth',
    'Get-ApiStats',
    'Get-ApiVendors',
    'Get-ApiDevices',
    'Get-ApiDeviceById',
    'Get-ApiInterfaces',
    'Get-ApiInterfacesByDevice',
    'Get-ApiAlerts',
    'Get-ApiActiveAlerts',
    'Get-ApiAlertSummary',
    'Set-ApiAlertAcknowledged',
    'Remove-ApiAlert'
)
