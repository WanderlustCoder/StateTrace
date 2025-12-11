Set-StrictMode -Version Latest

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

    try {
        if (-not (Get-Module -Name DeviceRepositoryModule)) {
            $repoPath = Join-Path $PSScriptRoot 'DeviceRepositoryModule.psm1'
            if (Test-Path -LiteralPath $repoPath) {
                Import-Module -Name $repoPath -Global -ErrorAction SilentlyContinue | Out-Null
            } else {
                Import-Module -Name DeviceRepositoryModule -Global -ErrorAction SilentlyContinue | Out-Null
            }
        }
    } catch {}

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

    try { DeviceRepositoryModule\Import-DatabaseModule } catch {
        try {
            $dbModulePath = Join-Path $PSScriptRoot 'DatabaseModule.psm1'
            if (Test-Path -LiteralPath $dbModulePath) {
                Import-Module -Name $dbModulePath -Global -ErrorAction SilentlyContinue | Out-Null
            } else {
                Import-Module -Name DatabaseModule -Global -ErrorAction SilentlyContinue | Out-Null
            }
        } catch {}
    }

    $dto.Summary = Get-DatabaseDeviceSummary -Hostname $hostTrim -DatabasePath $dbPath
    $dto.Interfaces = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
    try {
        $hostEsc = $hostTrim -replace "'", "''"
        try {
            $hostEsc = DatabaseModule\Get-SqlLiteral -Value $hostTrim
            # Get-SqlLiteral returns a quoted literal; if so, do not add extra quotes.
            if ($hostEsc -notmatch "^'.*'$") {
                $hostEsc = "'" + $hostEsc + "'"
            }
        } catch {
            $hostEsc = "'" + $hostEsc + "'"
        }
        $portsSql = "SELECT Hostname, Port, Name, Status, VLAN, Duplex, Speed, Type, LearnedMACs, AuthState, AuthMode, AuthClientMAC, AuthTemplate, Config, ConfigStatus, PortColor, ToolTip FROM Interfaces WHERE Hostname = $hostEsc ORDER BY Port"
        $dtPorts = DatabaseModule\Invoke-DbQuery -DatabasePath $dbPath -Sql $portsSql
        if ($dtPorts) {
            $convertedPorts = $null
            try {
                if (Get-Command -Name 'InterfaceModule\New-InterfaceObjectsFromDbRow' -ErrorAction SilentlyContinue) {
                    $convertedPorts = InterfaceModule\New-InterfaceObjectsFromDbRow -Data $dtPorts -Hostname $hostTrim -TemplatesPath $TemplatesPath
                }
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
        # keep summary even if interface query fails
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
    $summarySql = "SELECT Hostname, Make, Model, Uptime, Ports, AuthDefaultVLAN, Building, Room FROM DeviceSummary WHERE Hostname = '$escHost' OR Hostname LIKE '*$escHost*'"
    $dtSummary = $null
    try { $dtSummary = DatabaseModule\Invoke-DbQuery -DatabasePath $DatabasePath -Sql $summarySql } catch {}

    $row = $null
    if ($dtSummary) {
        $summaryRows = DatabaseModule\ConvertTo-DbRowList -Data $dtSummary
        if ($summaryRows.Count -gt 0) { $row = $summaryRows[0] }
    }

    $fallback = Get-DeviceHistoryFallback -Hostname $Hostname -DatabasePath $DatabasePath

    $makeVal     = script:Get-RowValue -Row $row -Property 'Make'
    $modelVal    = script:Get-RowValue -Row $row -Property 'Model'
    $uptimeVal   = script:Get-RowValue -Row $row -Property 'Uptime'
    $portsVal    = script:Get-RowValue -Row $row -Property 'Ports'
    $authVal     = script:Get-RowValue -Row $row -Property 'AuthDefaultVLAN'
    $buildingVal = script:Get-RowValue -Row $row -Property 'Building'
    $roomVal     = script:Get-RowValue -Row $row -Property 'Room'

    if (-not $makeVal)     { $makeVal     = $fallback.Make }
    if (-not $modelVal)    { $modelVal    = $fallback.Model }
    if (-not $uptimeVal)   { $uptimeVal   = $fallback.Uptime }
    if (-not $portsVal -or $portsVal -eq 0) { $portsVal = $fallback.Ports }
    if (-not $authVal)     { $authVal     = $fallback.AuthDefaultVLAN }
    if (-not $buildingVal) { $buildingVal = $fallback.Building }
    if (-not $roomVal)     { $roomVal     = $fallback.Room }

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
    } catch {}

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
    } catch {}

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

function Get-DeviceVendorFromSummary {
    param(
        [Parameter(Mandatory)][string]$Hostname,
        [Parameter(Mandatory)][string]$DatabasePath
    )

    $vendor = 'Cisco'
    $escHost = $Hostname -replace "'", "''"
    try {
        $mkDt = DatabaseModule\Invoke-DbQuery -DatabasePath $DatabasePath -Sql "SELECT Make FROM DeviceSummary WHERE Hostname = '$escHost'"
        $row = $null
        if ($mkDt) {
            $mkRows = DatabaseModule\ConvertTo-DbRowList -Data $mkDt
            if ($mkRows.Count -gt 0) { $row = $mkRows[0] }
        }
        $mk = script:Get-RowValue -Row $row -Property 'Make'
        if ($mk -and ($mk -match '(?i)brocade')) { $vendor = 'Brocade' }
    } catch {}
    return $vendor
}


Export-ModuleMember -Function Get-DeviceDetails, Get-DeviceDetailsData
