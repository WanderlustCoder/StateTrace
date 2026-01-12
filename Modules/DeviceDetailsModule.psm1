Set-StrictMode -Version Latest

function script:Ensure-LocalStateTraceModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ModuleName,
        [Parameter(Mandatory)][string]$ModuleFileName
    )

    try {
        if (Get-Module -Name $ModuleName -ErrorAction SilentlyContinue) { return $true }
    } catch { Write-Verbose "Caught exception in DeviceDetailsModule.psm1: $($_.Exception.Message)" }

    $modulePath = Join-Path $PSScriptRoot $ModuleFileName
    $imported = $false
    if (Test-Path -LiteralPath $modulePath) {
        try {
            Import-Module -Name $modulePath -Global -ErrorAction Stop | Out-Null
            $imported = $true
        } catch {
            Write-Warning ("[DeviceDetailsModule] Failed to import module '{0}' from '{1}': {2}" -f $ModuleName, $modulePath, $_.Exception.Message)
        }
    } else {
        try {
            Import-Module -Name $ModuleName -Global -ErrorAction Stop | Out-Null
            $imported = $true
        } catch {
            Write-Warning ("[DeviceDetailsModule] Failed to import module '{0}': {1}" -f $ModuleName, $_.Exception.Message)
        }
    }

    return $imported
}

function script:Ensure-DeviceRepositoryModule {
    $null = script:Ensure-LocalStateTraceModule -ModuleName 'DeviceRepositoryModule' -ModuleFileName 'DeviceRepositoryModule.psm1'
}

function script:Ensure-DatabaseModule {
    $imported = $false
    try {
        DeviceRepositoryModule\Import-DatabaseModule | Out-Null
        $imported = $true
    } catch {
        Write-Warning ("[DeviceDetailsModule] Failed to import DatabaseModule via DeviceRepositoryModule: {0}" -f $_.Exception.Message)
    }
    if (-not $imported) {
        $imported = [bool](script:Ensure-LocalStateTraceModule -ModuleName 'DatabaseModule' -ModuleFileName 'DatabaseModule.psm1')
    }
}

function Get-DeviceDetails {
    [CmdletBinding()]
    param([Parameter()][string]$Hostname)

    $hostTrim = ('' + $Hostname).Trim()
    if ([string]::IsNullOrWhiteSpace($hostTrim)) { return $null }

    Get-DeviceDetailsData -Hostname $hostTrim
}

function Get-DeviceDetailsData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Hostname,
        [string]$TemplatesPath = (Join-Path $PSScriptRoot '..\Templates')
    )

    $hostTrim = ('' + $Hostname).Trim()
    if ([string]::IsNullOrWhiteSpace($hostTrim)) { return $null }

    script:Ensure-DeviceRepositoryModule

    $dto = [PSCustomObject]@{
        Summary    = $null
        Interfaces = @()
        Templates  = @()
    }

    $dbPath = $null
    try { $dbPath = DeviceRepositoryModule\Get-DbPathForHost -Hostname $hostTrim } catch { $dbPath = $null }
    $useDb = $false
    if ($dbPath -and (Test-Path -LiteralPath $dbPath)) { $useDb = $true }

    if (-not $useDb) {
        Write-Verbose ("[DeviceDetailsModule] No database found for ''{0}''; returning empty details." -f $hostTrim)
        $dto.Summary = [PSCustomObject]@{
            Hostname        = $hostTrim
            Make            = ''
            Model           = ''
            Uptime          = ''
            Ports           = ''
            AuthDefaultVLAN = ''
            Building        = ''
            Room            = ''
        }
        return $dto
    }

    script:Ensure-DatabaseModule

    $dto.Summary = Get-DatabaseDeviceSummary -Hostname $hostTrim -DatabasePath $dbPath
    $dto.Interfaces = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
    try {
        $escHost = $hostTrim -replace "'", "''"
        try { $escHost = DatabaseModule\Get-SqlLiteral -Value $hostTrim } catch { Write-Verbose "Caught exception in DeviceDetailsModule.psm1: $($_.Exception.Message)" }
        $portsSql = "SELECT Hostname, Port, Name, Status, VLAN, Duplex, Speed, Type, LearnedMACs, AuthState, AuthMode, AuthClientMAC, AuthTemplate, Config, ConfigStatus, PortColor, ToolTip FROM Interfaces WHERE Hostname = '$escHost' ORDER BY Port"
        $dtPorts = DatabaseModule\Invoke-DbQuery -DatabasePath $dbPath -Sql $portsSql
        if ($dtPorts) {
            $convertedPorts = $null
            try {
                $convertedPorts = InterfaceModule\New-InterfaceObjectsFromDbRow -Data $dtPorts -Hostname $hostTrim -TemplatesPath $TemplatesPath
            } catch [System.Management.Automation.CommandNotFoundException] {
                $convertedPorts = $null
            } catch {
                $convertedPorts = $null
            }

            if ($convertedPorts -and $convertedPorts.Count -gt 0) {
                foreach ($row in $convertedPorts) {
                    if ($null -eq $row) { continue }
                    $dto.Interfaces.Add($row) | Out-Null
                }
            } else {
                $rows = DatabaseModule\ConvertTo-DbRowList -Data $dtPorts
                foreach ($row in $rows) {
                    if ($null -eq $row) { continue }
                    $dto.Interfaces.Add($row) | Out-Null
                }
            }
        }
    } catch {
        Write-Warning ("[DeviceDetailsModule] Interface query failed for '{0}' in '{1}': {2}" -f $hostTrim, $dbPath, $_.Exception.Message)
    }

    try {
        $dto.Templates = TemplatesModule\Get-ConfigurationTemplates -Hostname $hostTrim -DatabasePath $dbPath -TemplatesPath $TemplatesPath
    } catch {
        $dto.Templates = @()
    }

    return $dto
}

function Get-DatabaseDeviceSummary {
    param(
        [Parameter(Mandatory)][string]$Hostname,
        [Parameter(Mandatory)][string]$DatabasePath
    )

    $escHost = $Hostname -replace "'", "''"
    try { $escHost = DatabaseModule\Get-SqlLiteral -Value $Hostname } catch { Write-Verbose "Caught exception in DeviceDetailsModule.psm1: $($_.Exception.Message)" }
    $summarySql = "SELECT Hostname, Make, Model, Uptime, Ports, AuthDefaultVLAN, Building, Room FROM DeviceSummary WHERE Hostname = '$escHost' OR Hostname LIKE '*$escHost*'"
    $dtSummary = $null
    try { $dtSummary = DatabaseModule\Invoke-DbQuery -DatabasePath $DatabasePath -Sql $summarySql } catch {
        Write-Warning ("[DeviceDetailsModule] Summary query failed for '{0}' in '{1}': {2}" -f $Hostname, $DatabasePath, $_.Exception.Message)
    }

    $row = $null
    if ($dtSummary) {
        $summaryRows = DatabaseModule\ConvertTo-DbRowList -Data $dtSummary
        if ($summaryRows.Count -gt 0) { $row = $summaryRows[0] }
    }

    $makeVal     = script:Get-RowValue -Row $row -Property 'Make'
    $modelVal    = script:Get-RowValue -Row $row -Property 'Model'
    $uptimeVal   = script:Get-RowValue -Row $row -Property 'Uptime'
    $portsVal    = script:Get-RowValue -Row $row -Property 'Ports'
    $authVal     = script:Get-RowValue -Row $row -Property 'AuthDefaultVLAN'
    $buildingVal = script:Get-RowValue -Row $row -Property 'Building'
    $roomVal     = script:Get-RowValue -Row $row -Property 'Room'

    # OPTIMIZATION: Only query DeviceHistory fallback if we're missing critical data
    # This avoids 2 extra DB queries when DeviceSummary has all the data we need
    $needFallback = (-not $makeVal) -or (-not $modelVal) -or (-not $portsVal -or $portsVal -eq 0)
    if ($needFallback) {
        $fallback = Get-DeviceHistoryFallback -Hostname $Hostname -DatabasePath $DatabasePath
        if (-not $makeVal)     { $makeVal     = $fallback.Make }
        if (-not $modelVal)    { $modelVal    = $fallback.Model }
        if (-not $uptimeVal)   { $uptimeVal   = $fallback.Uptime }
        if (-not $portsVal -or $portsVal -eq 0) { $portsVal = $fallback.Ports }
        if (-not $authVal)     { $authVal     = $fallback.AuthDefaultVLAN }
        if (-not $buildingVal) { $buildingVal = $fallback.Building }
        if (-not $roomVal)     { $roomVal     = $fallback.Room }
    }

    return [PSCustomObject]@{
        Hostname        = $Hostname
        Make            = '' + $makeVal
        Model           = '' + $modelVal
        Uptime          = '' + $uptimeVal
        Ports           = '' + $portsVal
        AuthDefaultVLAN = '' + $authVal
        Building        = '' + $buildingVal
        Room            = '' + $roomVal
    }
}

function Get-DeviceHistoryFallback {
    param(
        [Parameter(Mandatory)][string]$Hostname,
        [Parameter(Mandatory)][string]$DatabasePath
    )

    $fallback = [PSCustomObject]@{
        Make            = ''
        Model           = ''
        Uptime          = ''
        AuthDefaultVLAN = ''
        Building        = ''
        Room            = ''
        Ports           = ''
    }

    $escHost = $Hostname -replace "'", "''"
    try { $escHost = DatabaseModule\Get-SqlLiteral -Value $Hostname } catch { Write-Verbose "Caught exception in DeviceDetailsModule.psm1: $($_.Exception.Message)" }
    try {
        $hist = DatabaseModule\Invoke-DbQuery -DatabasePath $DatabasePath -Sql "SELECT TOP 1 Make, Model, Uptime, AuthDefaultVLAN, Building, Room FROM DeviceHistory WHERE Trim(Hostname) = '$escHost' ORDER BY RunDate DESC"
        $row = $null
        if ($hist) {
            $histRows = DatabaseModule\ConvertTo-DbRowList -Data $hist
            if ($histRows.Count -gt 0) { $row = $histRows[0] }
        }
        if ($row) {
            $mk = script:Get-RowValue -Row $row -Property 'Make'
            $md = script:Get-RowValue -Row $row -Property 'Model'
            $up = script:Get-RowValue -Row $row -Property 'Uptime'
            $av = script:Get-RowValue -Row $row -Property 'AuthDefaultVLAN'
            $bd = script:Get-RowValue -Row $row -Property 'Building'
            $rm = script:Get-RowValue -Row $row -Property 'Room'
            if ($mk) { $fallback.Make = '' + $mk }
            if ($md) { $fallback.Model = '' + $md }
            if ($up) { $fallback.Uptime = '' + $up }
            if ($av) { $fallback.AuthDefaultVLAN = '' + $av }
            if ($bd) { $fallback.Building = '' + $bd }
            if ($rm) { $fallback.Room = '' + $rm }
        }
    } catch { Write-Verbose "Caught exception in DeviceDetailsModule.psm1: $($_.Exception.Message)" }

    try {
        $cnt = DatabaseModule\Invoke-DbQuery -DatabasePath $DatabasePath -Sql "SELECT COUNT(*) AS PortCount FROM Interfaces WHERE Trim(Hostname) = '$escHost'"
        $cntRow = $null
        if ($cnt) {
            $cntRows = DatabaseModule\ConvertTo-DbRowList -Data $cnt
            if ($cntRows.Count -gt 0) { $cntRow = $cntRows[0] }
        }
        if ($cntRow) {
            $pc = script:Get-RowValue -Row $cntRow -Property 'PortCount'
            if ($pc -ne $null) { $fallback.Ports = '' + $pc }
        }
    } catch { Write-Verbose "Caught exception in DeviceDetailsModule.psm1: $($_.Exception.Message)" }

    return $fallback
}


function script:Get-RowValue {
    param(
        $Row,
        [string]$Property
    )

    if (-not $Row) { return $null }
    try {
        $value = $null
        if ($Row -is [System.Data.DataRow]) {
            $value = $Row.$Property
        } elseif ($Row.PSObject -and $Row.PSObject.Properties[$Property]) {
            $value = $Row.$Property
        } else {
            return $null
        }
        if ($null -eq $value -or $value -eq [System.DBNull]::Value) { return $null }
        return $value
    } catch {
        return $null
    }
}

Export-ModuleMember -Function Get-DeviceDetails, Get-DeviceDetailsData
