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

    try { DeviceRepositoryModule\Import-DatabaseModule } catch {}

    $dto.Summary = Get-DatabaseDeviceSummary -Hostname $hostTrim -DatabasePath $dbPath
    $dto.Interfaces = DeviceRepositoryModule\Get-InterfaceInfo -Hostname $hostTrim -TemplatesPath $TemplatesPath
    if (-not $dto.Interfaces) { $dto.Interfaces = @() }

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
        if ($dtSummary -is [System.Data.DataTable]) {
            if ($dtSummary.Rows.Count -gt 0) { $row = $dtSummary.Rows[0] }
        } elseif ($dtSummary -is [System.Collections.IEnumerable]) {
            try { $row = ($dtSummary | Select-Object -First 1) } catch { $row = $null }
        }
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
            if ($hist -is [System.Data.DataTable]) {
                if ($hist.Rows.Count -gt 0) { $row = $hist.Rows[0] }
            } elseif ($hist -is [System.Collections.IEnumerable]) {
                try { $row = ($hist | Select-Object -First 1) } catch { $row = $null }
            }
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
            if ($cnt -is [System.Data.DataTable]) {
                if ($cnt.Rows.Count -gt 0) { $cntRow = $cnt.Rows[0] }
            } elseif ($cnt -is [System.Collections.IEnumerable]) {
                try { $cntRow = ($cnt | Select-Object -First 1) } catch { $cntRow = $null }
            }
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
            if ($mkDt -is [System.Data.DataTable]) {
                if ($mkDt.Rows.Count -gt 0) { $row = $mkDt.Rows[0] }
            } elseif ($mkDt -is [System.Collections.IEnumerable]) {
                try { $row = ($mkDt | Select-Object -First 1) } catch { $row = $null }
            }
        }
        $mk = script:Get-RowValue -Row $row -Property 'Make'
        if ($mk -and ($mk -match '(?i)brocade')) { $vendor = 'Brocade' }
    } catch {}
    return $vendor
}


Export-ModuleMember -Function Get-DeviceDetails, Get-DeviceDetailsData





