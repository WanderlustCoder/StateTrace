#Requires -Version 5.1
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Capacity planning and forecasting module for StateTrace.

.DESCRIPTION
    Provides utilization tracking, growth forecasting, threshold alerting,
    what-if scenario modeling, and budget planning for network capacity.

.NOTES
    Plan AC - Capacity Planning & Forecasting
#>

# Module-level databases
$script:UtilizationSnapshots = $null
$script:CapacityThresholds = $null
$script:GrowthForecasts = $null
$script:PlanningScenarios = $null
$script:DatabasePath = $null

#region Initialization

function Initialize-CapacityPlanningDatabase {
    <#
    .SYNOPSIS
        Initializes the capacity planning database structures.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Path,

        [Parameter()]
        [switch]$TestMode
    )

    if ($TestMode) {
        $script:DatabasePath = $null
    } elseif ($Path) {
        $script:DatabasePath = $Path
    } else {
        $dataDir = Join-Path $PSScriptRoot '..\Data'
        if (-not (Test-Path $dataDir)) {
            New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
        }
        $script:DatabasePath = Join-Path $dataDir 'CapacityPlanningDatabase.json'
    }

    # Initialize empty databases
    $script:UtilizationSnapshots = New-Object System.Collections.ArrayList
    $script:CapacityThresholds = New-Object System.Collections.ArrayList
    $script:GrowthForecasts = New-Object System.Collections.ArrayList
    $script:PlanningScenarios = New-Object System.Collections.ArrayList

    # Load existing data if available
    if ($script:DatabasePath -and (Test-Path $script:DatabasePath)) {
        Import-CapacityPlanningDatabase -Path $script:DatabasePath
    }

    # Initialize default thresholds
    Initialize-DefaultThresholds
}

function Initialize-DefaultThresholds {
    <#
    .SYNOPSIS
        Sets up default capacity thresholds.
    #>
    $defaults = @(
        @{
            ThresholdID = 'DEFAULT-PORT-WARNING'
            ScopeType = 'Global'
            ScopeID = '*'
            MetricName = 'PortUtilization'
            WarningLevel = 70
            CriticalLevel = 85
            IsEnabled = $true
            NotifyOnBreach = $true
        }
        @{
            ThresholdID = 'DEFAULT-POE-WARNING'
            ScopeType = 'Global'
            ScopeID = '*'
            MetricName = 'PoEUtilization'
            WarningLevel = 75
            CriticalLevel = 90
            IsEnabled = $true
            NotifyOnBreach = $true
        }
    )

    foreach ($threshold in $defaults) {
        $existing = $script:CapacityThresholds | Where-Object { $_.ThresholdID -eq $threshold.ThresholdID }
        if (-not $existing) {
            $thresholdObj = [PSCustomObject]$threshold
            [void]$script:CapacityThresholds.Add($thresholdObj)
        }
    }
}

#endregion

#region Utilization Calculations

function Get-PortUtilization {
    <#
    .SYNOPSIS
        Calculates port utilization for a device.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Device
    )

    $totalPorts = 0
    $usedPorts = 0

    if ($Device -is [hashtable]) {
        $totalPorts = [int]$Device['TotalPorts']
        $usedPorts = [int]$Device['UsedPorts']
    } else {
        $totalPorts = [int]$Device.TotalPorts
        $usedPorts = [int]$Device.UsedPorts
    }

    $percentage = if ($totalPorts -gt 0) { [Math]::Round(($usedPorts / $totalPorts) * 100, 1) } else { 0 }
    $availablePorts = $totalPorts - $usedPorts

    return [PSCustomObject]@{
        TotalPorts = $totalPorts
        UsedPorts = $usedPorts
        AvailablePorts = $availablePorts
        Percentage = $percentage
    }
}

function Get-PoEUtilization {
    <#
    .SYNOPSIS
        Calculates PoE power utilization for a device.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Device
    )

    $budgetWatts = 0
    $usedWatts = 0

    if ($Device -is [hashtable]) {
        $budgetWatts = [int]$Device['PoEBudgetWatts']
        $usedWatts = [int]$Device['PoEUsedWatts']
    } else {
        $budgetWatts = [int]$Device.PoEBudgetWatts
        $usedWatts = [int]$Device.PoEUsedWatts
    }

    $percentage = if ($budgetWatts -gt 0) { [Math]::Round(($usedWatts / $budgetWatts) * 100, 1) } else { 0 }
    $availableWatts = $budgetWatts - $usedWatts

    return [PSCustomObject]@{
        BudgetWatts = $budgetWatts
        UsedWatts = $usedWatts
        AvailableWatts = $availableWatts
        Percentage = $percentage
    }
}

function Get-SiteUtilization {
    <#
    .SYNOPSIS
        Aggregates port utilization across devices by site.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$Devices
    )

    $siteGroups = @{}

    foreach ($device in $Devices) {
        $siteId = if ($device -is [hashtable]) { $device['SiteID'] } else { $device.SiteID }
        if (-not $siteId) { $siteId = 'Unknown' }

        if (-not $siteGroups.ContainsKey($siteId)) {
            $siteGroups[$siteId] = @{
                TotalPorts = 0
                UsedPorts = 0
                DeviceCount = 0
            }
        }

        $totalPorts = if ($device -is [hashtable]) { [int]$device['TotalPorts'] } else { [int]$device.TotalPorts }
        $usedPorts = if ($device -is [hashtable]) { [int]$device['UsedPorts'] } else { [int]$device.UsedPorts }

        $siteGroups[$siteId]['TotalPorts'] += $totalPorts
        $siteGroups[$siteId]['UsedPorts'] += $usedPorts
        $siteGroups[$siteId]['DeviceCount']++
    }

    $results = @()
    foreach ($siteId in $siteGroups.Keys) {
        $site = $siteGroups[$siteId]
        $percentage = if ($site['TotalPorts'] -gt 0) {
            [Math]::Round(($site['UsedPorts'] / $site['TotalPorts']) * 100, 1)
        } else { 0 }

        $results += [PSCustomObject]@{
            SiteID = $siteId
            TotalPorts = $site['TotalPorts']
            UsedPorts = $site['UsedPorts']
            AvailablePorts = $site['TotalPorts'] - $site['UsedPorts']
            Percentage = $percentage
            DeviceCount = $site['DeviceCount']
        }
    }

    return $results | Sort-Object Percentage -Descending
}

function Get-VLANUtilization {
    <#
    .SYNOPSIS
        Calculates port utilization by VLAN.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$Ports
    )

    $vlanGroups = @{}

    foreach ($port in $Ports) {
        $vlan = if ($port -is [hashtable]) { $port['VLAN'] } else { $port.VLAN }
        if (-not $vlan) { $vlan = 0 }

        if (-not $vlanGroups.ContainsKey($vlan)) {
            $vlanGroups[$vlan] = @{
                TotalPorts = 0
                UsedPorts = 0
            }
        }

        $vlanGroups[$vlan]['TotalPorts']++

        $isUsed = if ($port -is [hashtable]) { $port['IsUsed'] } else { $port.IsUsed }
        if ($isUsed) {
            $vlanGroups[$vlan]['UsedPorts']++
        }
    }

    $results = @()
    foreach ($vlan in $vlanGroups.Keys) {
        $group = $vlanGroups[$vlan]
        $percentage = if ($group['TotalPorts'] -gt 0) {
            [Math]::Round(($group['UsedPorts'] / $group['TotalPorts']) * 100, 1)
        } else { 0 }

        $results += [PSCustomObject]@{
            VLAN = $vlan
            TotalPorts = $group['TotalPorts']
            UsedPorts = $group['UsedPorts']
            AvailablePorts = $group['TotalPorts'] - $group['UsedPorts']
            Percentage = $percentage
        }
    }

    return $results | Sort-Object VLAN
}

#endregion

#region Snapshot Management

function New-UtilizationSnapshot {
    <#
    .SYNOPSIS
        Creates a utilization snapshot for capacity tracking.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Device', 'Site', 'Enterprise')]
        [string]$Scope,

        [Parameter()]
        [string]$ScopeID,

        [Parameter()]
        [int]$TotalPorts = 0,

        [Parameter()]
        [int]$UsedPorts = 0,

        [Parameter()]
        [int]$AccessPorts = 0,

        [Parameter()]
        [int]$TrunkPorts = 0,

        [Parameter()]
        [int]$PoEBudgetWatts = 0,

        [Parameter()]
        [int]$PoEUsedWatts = 0,

        [Parameter()]
        [hashtable]$AvailableByVLAN,

        [Parameter()]
        [string]$Notes
    )

    $snapshotId = [Guid]::NewGuid().ToString()

    $snapshot = [PSCustomObject]@{
        SnapshotID = $snapshotId
        SnapshotDate = Get-Date
        ScopeType = $Scope
        ScopeID = $ScopeID
        TotalPorts = $TotalPorts
        UsedPorts = $UsedPorts
        AccessPorts = $AccessPorts
        TrunkPorts = $TrunkPorts
        PoEBudgetWatts = $PoEBudgetWatts
        PoEUsedWatts = $PoEUsedWatts
        AvailableByVLAN = $AvailableByVLAN
        Notes = $Notes
        Utilization = if ($TotalPorts -gt 0) { [Math]::Round(($UsedPorts / $TotalPorts) * 100, 1) } else { 0 }
    }

    [void]$script:UtilizationSnapshots.Add($snapshot)

    return $snapshot
}

function Get-UtilizationSnapshot {
    <#
    .SYNOPSIS
        Retrieves utilization snapshots.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$SnapshotID,

        [Parameter()]
        [string]$Scope,

        [Parameter()]
        [string]$ScopeID,

        [Parameter()]
        [datetime]$StartDate,

        [Parameter()]
        [datetime]$EndDate
    )

    $snapshots = $script:UtilizationSnapshots

    if ($SnapshotID) {
        $snapshots = $snapshots | Where-Object { $_.SnapshotID -eq $SnapshotID }
    }

    if ($Scope) {
        $snapshots = $snapshots | Where-Object { $_.ScopeType -eq $Scope }
    }

    if ($ScopeID) {
        $snapshots = $snapshots | Where-Object { $_.ScopeID -eq $ScopeID }
    }

    if ($StartDate) {
        $snapshots = $snapshots | Where-Object { $_.SnapshotDate -ge $StartDate }
    }

    if ($EndDate) {
        $snapshots = $snapshots | Where-Object { $_.SnapshotDate -le $EndDate }
    }

    return $snapshots | Sort-Object SnapshotDate -Descending
}

function Get-UtilizationHistory {
    <#
    .SYNOPSIS
        Gets historical utilization data for trend analysis.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Scope,

        [Parameter(Mandatory)]
        [string]$ScopeID,

        [Parameter()]
        [datetime]$StartDate,

        [Parameter()]
        [datetime]$EndDate
    )

    $params = @{
        Scope = $Scope
        ScopeID = $ScopeID
    }

    if ($StartDate) { $params['StartDate'] = $StartDate }
    if ($EndDate) { $params['EndDate'] = $EndDate }

    return Get-UtilizationSnapshot @params | Sort-Object SnapshotDate
}

#endregion

#region Trend Analysis & Forecasting

function Get-GrowthRate {
    <#
    .SYNOPSIS
        Calculates growth rate from historical data.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$History,

        [Parameter()]
        [ValidateSet('Monthly', 'Weekly', 'Daily')]
        [string]$Period = 'Monthly'
    )

    if ($History.Count -lt 2) {
        return [PSCustomObject]@{
            PortsPerMonth = 0
            PortsPerWeek = 0
            PercentageGrowth = 0
            DataPoints = $History.Count
        }
    }

    # Sort by date
    $sorted = $History | Sort-Object {
        if ($_ -is [hashtable]) { [datetime]$_['Date'] } else { [datetime]$_.Date }
    }

    $first = $sorted[0]
    $last = $sorted[-1]

    $firstDate = if ($first -is [hashtable]) { [datetime]$first['Date'] } else { [datetime]$first.Date }
    $lastDate = if ($last -is [hashtable]) { [datetime]$last['Date'] } else { [datetime]$last.Date }
    $firstPorts = if ($first -is [hashtable]) { [int]$first['UsedPorts'] } else { [int]$first.UsedPorts }
    $lastPorts = if ($last -is [hashtable]) { [int]$last['UsedPorts'] } else { [int]$last.UsedPorts }

    $totalDays = ($lastDate - $firstDate).TotalDays
    if ($totalDays -le 0) { $totalDays = 1 }

    $portChange = $lastPorts - $firstPorts
    $portsPerDay = $portChange / $totalDays
    $portsPerMonth = $portsPerDay * 30.44  # Average days per month
    $portsPerWeek = $portsPerDay * 7

    $percentageGrowth = if ($firstPorts -gt 0) {
        [Math]::Round((($lastPorts - $firstPorts) / $firstPorts) * 100, 2)
    } else { 0 }

    return [PSCustomObject]@{
        PortsPerMonth = [Math]::Round($portsPerMonth, 2)
        PortsPerWeek = [Math]::Round($portsPerWeek, 2)
        PortsPerDay = [Math]::Round($portsPerDay, 2)
        PercentageGrowth = $percentageGrowth
        TotalChange = $portChange
        DaysAnalyzed = [Math]::Round($totalDays, 0)
        DataPoints = $History.Count
    }
}

function Get-LinearForecast {
    <#
    .SYNOPSIS
        Performs linear regression for capacity forecasting.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$History
    )

    if ($History.Count -lt 2) {
        return [PSCustomObject]@{
            Slope = 0
            Intercept = 0
            RSquared = 0
            DataPoints = $History.Count
        }
    }

    # Convert to numeric arrays
    $sorted = $History | Sort-Object {
        if ($_ -is [hashtable]) { [datetime]$_['Date'] } else { [datetime]$_.Date }
    }

    $baseDate = if ($sorted[0] -is [hashtable]) { [datetime]$sorted[0]['Date'] } else { [datetime]$sorted[0].Date }

    $xValues = @()
    $yValues = @()

    foreach ($item in $sorted) {
        $date = if ($item -is [hashtable]) { [datetime]$item['Date'] } else { [datetime]$item.Date }
        $ports = if ($item -is [hashtable]) { [double]$item['UsedPorts'] } else { [double]$item.UsedPorts }

        $xValues += ($date - $baseDate).TotalDays
        $yValues += $ports
    }

    $n = $xValues.Count
    $sumX = ($xValues | Measure-Object -Sum).Sum
    $sumY = ($yValues | Measure-Object -Sum).Sum
    $sumXY = 0
    $sumX2 = 0
    $sumY2 = 0

    for ($i = 0; $i -lt $n; $i++) {
        $sumXY += $xValues[$i] * $yValues[$i]
        $sumX2 += $xValues[$i] * $xValues[$i]
        $sumY2 += $yValues[$i] * $yValues[$i]
    }

    # Calculate slope and intercept
    $denominator = ($n * $sumX2 - $sumX * $sumX)
    if ($denominator -eq 0) { $denominator = 1 }

    $slope = ($n * $sumXY - $sumX * $sumY) / $denominator
    $intercept = ($sumY - $slope * $sumX) / $n

    # Calculate R-squared
    $meanY = $sumY / $n
    $ssTot = 0
    $ssRes = 0

    for ($i = 0; $i -lt $n; $i++) {
        $predicted = $intercept + $slope * $xValues[$i]
        $ssRes += [Math]::Pow($yValues[$i] - $predicted, 2)
        $ssTot += [Math]::Pow($yValues[$i] - $meanY, 2)
    }

    $rSquared = if ($ssTot -gt 0) { 1 - ($ssRes / $ssTot) } else { 0 }

    return [PSCustomObject]@{
        Slope = [Math]::Round($slope, 4)
        Intercept = [Math]::Round($intercept, 2)
        RSquared = [Math]::Round($rSquared, 4)
        BaseDate = $baseDate
        DataPoints = $n
        PortsPerDay = [Math]::Round($slope, 4)
        PortsPerMonth = [Math]::Round($slope * 30.44, 2)
    }
}

function Get-ThresholdBreachDate {
    <#
    .SYNOPSIS
        Predicts when a capacity threshold will be breached.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$History,

        [Parameter(Mandatory)]
        [int]$TotalCapacity,

        [Parameter()]
        [double]$Threshold = 0.80
    )

    if ($TotalCapacity -le 0) {
        return [PSCustomObject]@{
            ProjectedDate = $null
            DaysUntilBreach = -1
            WillBreach = $false
            Message = 'Invalid total capacity (must be > 0)'
        }
    }

    $forecast = Get-LinearForecast -History $History

    if ($forecast.Slope -le 0) {
        return [PSCustomObject]@{
            ProjectedDate = $null
            DaysUntilBreach = -1
            WillBreach = $false
            Message = 'No growth detected - capacity is stable or declining'
        }
    }

    # Calculate target value
    $targetPorts = $TotalCapacity * $Threshold

    # Current value from most recent data point
    $sorted = $History | Sort-Object {
        if ($_ -is [hashtable]) { [datetime]$_['Date'] } else { [datetime]$_.Date }
    }
    $latest = $sorted[-1]
    $currentPorts = if ($latest -is [hashtable]) { [int]$latest['UsedPorts'] } else { [int]$latest.UsedPorts }
    $currentDate = if ($latest -is [hashtable]) { [datetime]$latest['Date'] } else { [datetime]$latest.Date }

    if ($currentPorts -ge $targetPorts) {
        return [PSCustomObject]@{
            ProjectedDate = $currentDate
            DaysUntilBreach = 0
            WillBreach = $true
            Message = 'Threshold already breached'
            CurrentUtilization = [Math]::Round(($currentPorts / $TotalCapacity) * 100, 1)
        }
    }

    # Calculate days until breach
    $portsNeeded = $targetPorts - $currentPorts
    $daysUntilBreach = $portsNeeded / $forecast.Slope
    $projectedDate = $currentDate.AddDays($daysUntilBreach)

    return [PSCustomObject]@{
        ProjectedDate = $projectedDate
        DaysUntilBreach = [Math]::Round($daysUntilBreach, 0)
        WillBreach = $true
        Message = "Threshold of $([Math]::Round($Threshold * 100))% projected to be reached in $([Math]::Round($daysUntilBreach, 0)) days"
        CurrentUtilization = [Math]::Round(($currentPorts / $TotalCapacity) * 100, 1)
        GrowthRate = $forecast.PortsPerMonth
    }
}

function Get-SeasonalForecast {
    <#
    .SYNOPSIS
        Analyzes data for seasonal patterns.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$History
    )

    if ($History.Count -lt 4) {
        return [PSCustomObject]@{
            HasSeasonalPattern = $false
            SeasonalFactor = 1.0
            Message = 'Insufficient data for seasonal analysis'
        }
    }

    # Group by quarter/season and look for patterns
    $sorted = $History | Sort-Object {
        if ($_ -is [hashtable]) { [datetime]$_['Date'] } else { [datetime]$_.Date }
    }

    $quarters = @{}
    foreach ($item in $sorted) {
        $date = if ($item -is [hashtable]) { [datetime]$item['Date'] } else { [datetime]$item.Date }
        $ports = if ($item -is [hashtable]) { [int]$item['UsedPorts'] } else { [int]$item.UsedPorts }

        $quarter = [Math]::Ceiling($date.Month / 3)
        if (-not $quarters.ContainsKey($quarter)) {
            $quarters[$quarter] = @()
        }
        $quarters[$quarter] += $ports
    }

    # Calculate variance between quarters
    $quarterAverages = @{}
    foreach ($q in $quarters.Keys) {
        $quarterAverages[$q] = ($quarters[$q] | Measure-Object -Average).Average
    }

    $overallAvg = ($quarterAverages.Values | Measure-Object -Average).Average
    $variance = ($quarterAverages.Values | Measure-Object -Maximum).Maximum - ($quarterAverages.Values | Measure-Object -Minimum).Minimum
    $variancePercent = if ($overallAvg -gt 0) { ($variance / $overallAvg) * 100 } else { 0 }

    $hasPattern = $variancePercent -gt 10  # More than 10% variance suggests seasonality

    return [PSCustomObject]@{
        HasSeasonalPattern = $hasPattern
        VariancePercent = [Math]::Round($variancePercent, 1)
        QuarterAverages = $quarterAverages
        OverallAverage = [Math]::Round($overallAvg, 1)
        Message = if ($hasPattern) { "Seasonal pattern detected with $([Math]::Round($variancePercent, 1))% variance" } else { "No significant seasonal pattern" }
    }
}

#endregion

#region Threshold Management

function Get-CapacityThreshold {
    <#
    .SYNOPSIS
        Retrieves capacity thresholds.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$ThresholdID,

        [Parameter()]
        [string]$ScopeType,

        [Parameter()]
        [string]$MetricName
    )

    $thresholds = $script:CapacityThresholds

    if ($ThresholdID) {
        $thresholds = $thresholds | Where-Object { $_.ThresholdID -eq $ThresholdID }
    }

    if ($ScopeType) {
        $thresholds = $thresholds | Where-Object { $_.ScopeType -eq $ScopeType }
    }

    if ($MetricName) {
        $thresholds = $thresholds | Where-Object { $_.MetricName -eq $MetricName }
    }

    return $thresholds
}

function New-CapacityThreshold {
    <#
    .SYNOPSIS
        Creates a new capacity threshold.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ScopeType,

        [Parameter(Mandatory)]
        [string]$ScopeID,

        [Parameter(Mandatory)]
        [string]$MetricName,

        [Parameter(Mandatory)]
        [int]$WarningLevel,

        [Parameter(Mandatory)]
        [int]$CriticalLevel,

        [Parameter()]
        [switch]$IsEnabled,

        [Parameter()]
        [switch]$NotifyOnBreach
    )

    $thresholdId = [Guid]::NewGuid().ToString()

    $threshold = [PSCustomObject]@{
        ThresholdID = $thresholdId
        ScopeType = $ScopeType
        ScopeID = $ScopeID
        MetricName = $MetricName
        WarningLevel = $WarningLevel
        CriticalLevel = $CriticalLevel
        IsEnabled = $IsEnabled.IsPresent
        NotifyOnBreach = $NotifyOnBreach.IsPresent
        CreatedDate = Get-Date
    }

    [void]$script:CapacityThresholds.Add($threshold)

    return $threshold
}

function Add-CapacityThreshold {
    <#
    .SYNOPSIS
        Adds a capacity threshold entry.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Scope,

        [Parameter(Mandatory)]
        [string]$MetricType,

        [Parameter(Mandatory)]
        [int]$WarningLevel,

        [Parameter(Mandatory)]
        [int]$CriticalLevel,

        [Parameter()]
        [string]$ScopeType = 'Site',

        [Parameter()]
        [switch]$IsEnabled,

        [Parameter()]
        [switch]$NotifyOnBreach
    )

    $resolvedScopeType = $ScopeType
    $resolvedScopeId = $Scope
    if ($Scope -match '^\s*(?<type>[^:]+)\s*:\s*(?<id>.+)$') {
        $resolvedScopeType = $matches['type'].Trim()
        $resolvedScopeId = $matches['id'].Trim()
    }

    $metricName = $MetricType
    if ($MetricType -match '^(?i)port$') { $metricName = 'PortUtilization' }
    elseif ($MetricType -match '^(?i)poe$') { $metricName = 'PoEUtilization' }

    return New-CapacityThreshold -ScopeType $resolvedScopeType -ScopeID $resolvedScopeId -MetricName $metricName `
        -WarningLevel $WarningLevel -CriticalLevel $CriticalLevel -IsEnabled:$IsEnabled.IsPresent -NotifyOnBreach:$NotifyOnBreach.IsPresent
}

function Set-CapacityThreshold {
    <#
    .SYNOPSIS
        Updates a capacity threshold entry.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ThresholdID,

        [Parameter()]
        [Nullable[bool]]$IsEnabled,

        [Parameter()]
        [Nullable[bool]]$NotifyOnBreach,

        [Parameter()]
        [int]$WarningLevel,

        [Parameter()]
        [int]$CriticalLevel,

        [Parameter()]
        [string]$Scope,

        [Parameter()]
        [string]$ScopeType,

        [Parameter()]
        [string]$MetricType
    )

    $threshold = $script:CapacityThresholds | Where-Object { $_.ThresholdID -eq $ThresholdID } | Select-Object -First 1
    if (-not $threshold) {
        throw "Threshold not found: $ThresholdID"
    }

    if ($PSBoundParameters.ContainsKey('WarningLevel')) { $threshold.WarningLevel = $WarningLevel }
    if ($PSBoundParameters.ContainsKey('CriticalLevel')) { $threshold.CriticalLevel = $CriticalLevel }
    if ($PSBoundParameters.ContainsKey('IsEnabled')) { $threshold.IsEnabled = [bool]$IsEnabled }
    if ($PSBoundParameters.ContainsKey('NotifyOnBreach')) { $threshold.NotifyOnBreach = [bool]$NotifyOnBreach }

    if ($PSBoundParameters.ContainsKey('Scope')) {
        $resolvedScopeType = if ($ScopeType) { $ScopeType } else { $threshold.ScopeType }
        $resolvedScopeId = $Scope
        if ($Scope -match '^\s*(?<type>[^:]+)\s*:\s*(?<id>.+)$') {
            $resolvedScopeType = $matches['type'].Trim()
            $resolvedScopeId = $matches['id'].Trim()
        }
        $threshold.ScopeType = $resolvedScopeType
        $threshold.ScopeID = $resolvedScopeId
    } elseif ($PSBoundParameters.ContainsKey('ScopeType')) {
        $threshold.ScopeType = $ScopeType
    }

    if ($PSBoundParameters.ContainsKey('MetricType')) {
        $metricName = $MetricType
        if ($MetricType -match '^(?i)port$') { $metricName = 'PortUtilization' }
        elseif ($MetricType -match '^(?i)poe$') { $metricName = 'PoEUtilization' }
        $threshold.MetricName = $metricName
    }

    return $threshold
}

function Remove-CapacityThreshold {
    <#
    .SYNOPSIS
        Removes a capacity threshold entry.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ThresholdID
    )

    $threshold = $script:CapacityThresholds | Where-Object { $_.ThresholdID -eq $ThresholdID } | Select-Object -First 1
    if (-not $threshold) {
        Write-Warning ("Threshold not found: {0}" -f $ThresholdID)
        return $false
    }

    if ($threshold.ThresholdID -like 'DEFAULT-*') {
        Write-Warning ("Default threshold '{0}' cannot be removed." -f $ThresholdID)
        return $false
    }

    [void]$script:CapacityThresholds.Remove($threshold)
    return $true
}

function Get-CapacityWarnings {
    <#
    .SYNOPSIS
        Identifies devices above warning threshold.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$Devices,

        [Parameter()]
        [double]$WarningThreshold = 0.70,

        [Parameter()]
        [double]$CriticalThreshold = 0.85
    )

    $warnings = @()

    foreach ($device in $Devices) {
        $hostname = if ($device -is [hashtable]) { $device['Hostname'] } else { $device.Hostname }
        $totalPorts = if ($device -is [hashtable]) { [int]$device['TotalPorts'] } else { [int]$device.TotalPorts }
        $usedPorts = if ($device -is [hashtable]) { [int]$device['UsedPorts'] } else { [int]$device.UsedPorts }

        if ($totalPorts -eq 0) { continue }

        $utilization = $usedPorts / $totalPorts

        if ($utilization -ge $WarningThreshold) {
            $severity = if ($utilization -ge $CriticalThreshold) { 'Critical' } else { 'Warning' }

            $warnings += [PSCustomObject]@{
                Hostname = $hostname
                TotalPorts = $totalPorts
                UsedPorts = $usedPorts
                AvailablePorts = $totalPorts - $usedPorts
                Utilization = [Math]::Round($utilization * 100, 1)
                Severity = $severity
            }
        }
    }

    return $warnings | Sort-Object Utilization -Descending
}

function Get-CapacityStatus {
    <#
    .SYNOPSIS
        Gets capacity status with severity level.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Device,

        [Parameter()]
        [double]$WarningThreshold = 0.70,

        [Parameter()]
        [double]$CriticalThreshold = 0.85
    )

    $totalPorts = if ($Device -is [hashtable]) { [int]$Device['TotalPorts'] } else { [int]$Device.TotalPorts }
    $usedPorts = if ($Device -is [hashtable]) { [int]$Device['UsedPorts'] } else { [int]$Device.UsedPorts }

    if ($totalPorts -eq 0) {
        return [PSCustomObject]@{
            Utilization = 0
            Severity = 'Unknown'
            Message = 'No ports configured'
        }
    }

    $utilization = $usedPorts / $totalPorts

    $severity = 'Normal'
    if ($utilization -ge $CriticalThreshold) {
        $severity = 'Critical'
    } elseif ($utilization -ge $WarningThreshold) {
        $severity = 'Warning'
    }

    return [PSCustomObject]@{
        Utilization = [Math]::Round($utilization * 100, 1)
        Severity = $severity
        TotalPorts = $totalPorts
        UsedPorts = $usedPorts
        AvailablePorts = $totalPorts - $usedPorts
    }
}

function Get-ForecastAlert {
    <#
    .SYNOPSIS
        Generates alerts based on forecast predictions.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Forecast,

        [Parameter()]
        [int]$AlertDays = 90
    )

    $projectedDate = if ($Forecast -is [hashtable]) { $Forecast['ProjectedExhaustionDate'] } else { $Forecast.ProjectedExhaustionDate }

    if (-not $projectedDate) {
        return [PSCustomObject]@{
            ShouldAlert = $false
            Message = 'No projected exhaustion date'
        }
    }

    $daysUntil = ($projectedDate - (Get-Date)).Days

    $shouldAlert = $daysUntil -le $AlertDays -and $daysUntil -gt 0

    return [PSCustomObject]@{
        ShouldAlert = $shouldAlert
        DaysUntilExhaustion = $daysUntil
        ProjectedDate = $projectedDate
        Message = if ($shouldAlert) { "Capacity exhaustion projected in $daysUntil days" } else { "No immediate capacity concerns" }
    }
}

#endregion

#region What-If Scenarios

function Get-ScenarioImpact {
    <#
    .SYNOPSIS
        Calculates the impact of adding users.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$CurrentState,

        [Parameter(Mandatory)]
        [int]$AddUsers
    )

    $totalPorts = if ($CurrentState -is [hashtable]) { [int]$CurrentState['TotalPorts'] } else { [int]$CurrentState.TotalPorts }
    $usedPorts = if ($CurrentState -is [hashtable]) { [int]$CurrentState['UsedPorts'] } else { [int]$CurrentState.UsedPorts }
    $portsPerUser = if ($CurrentState -is [hashtable]) { [double]$CurrentState['PortsPerUser'] } else { [double]$CurrentState.PortsPerUser }

    if ($portsPerUser -le 0) { $portsPerUser = 1.0 }

    $additionalPorts = [Math]::Ceiling($AddUsers * $portsPerUser)
    $newUsedPorts = $usedPorts + $additionalPorts
    $newUtilization = if ($totalPorts -gt 0) { [Math]::Round(($newUsedPorts / $totalPorts) * 100, 1) } else { 0 }

    return [PSCustomObject]@{
        CurrentUsedPorts = $usedPorts
        AdditionalPorts = $additionalPorts
        NewUsedPorts = $newUsedPorts
        TotalPorts = $totalPorts
        CurrentUtilization = if ($totalPorts -gt 0) { [Math]::Round(($usedPorts / $totalPorts) * 100, 1) } else { 0 }
        NewUtilization = $newUtilization
        AvailableAfter = $totalPorts - $newUsedPorts
        CanAccommodate = $newUsedPorts -le $totalPorts
    }
}

function New-VLANDeploymentScenario {
    <#
    .SYNOPSIS
        Models deploying a new VLAN.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$CurrentState,

        [Parameter(Mandatory)]
        [int]$NewVLAN,

        [Parameter(Mandatory)]
        [int]$EstimatedPorts
    )

    $devices = if ($CurrentState -is [hashtable]) { $CurrentState['Devices'] } else { $CurrentState.Devices }

    # Find device with most available ports
    $bestDevice = $null
    $maxAvailable = 0

    foreach ($device in $devices) {
        $hostname = if ($device -is [hashtable]) { $device['Hostname'] } else { $device.Hostname }
        $totalPorts = if ($device -is [hashtable]) { [int]$device['TotalPorts'] } else { [int]$device.TotalPorts }
        $usedPorts = if ($device -is [hashtable]) { [int]$device['UsedPorts'] } else { [int]$device.UsedPorts }
        $available = $totalPorts - $usedPorts

        if ($available -gt $maxAvailable) {
            $maxAvailable = $available
            $bestDevice = $hostname
        }
    }

    $canAccommodate = $maxAvailable -ge $EstimatedPorts

    return [PSCustomObject]@{
        NewVLAN = $NewVLAN
        EstimatedPorts = $EstimatedPorts
        RecommendedDevice = $bestDevice
        AvailableOnDevice = $maxAvailable
        CanAccommodate = $canAccommodate
        Message = if ($canAccommodate) { "Can deploy VLAN $NewVLAN on $bestDevice with $maxAvailable available ports" } else { "Insufficient capacity - need $EstimatedPorts ports, best device has $maxAvailable" }
    }
}

function New-PlanningScenario {
    <#
    .SYNOPSIS
        Creates a new planning scenario.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter()]
        [string]$Description,

        [Parameter()]
        [hashtable]$Assumptions,

        [Parameter()]
        [hashtable]$ProjectedChanges,

        [Parameter()]
        [decimal]$CostEstimate
    )

    $scenarioId = [Guid]::NewGuid().ToString()

    $scenario = [PSCustomObject]@{
        ScenarioID = $scenarioId
        Name = $Name
        Description = $Description
        BaselineDate = Get-Date
        Assumptions = $Assumptions
        ProjectedChanges = $ProjectedChanges
        CostEstimate = $CostEstimate
        CreatedBy = $env:USERNAME
        CreatedDate = Get-Date
    }

    [void]$script:PlanningScenarios.Add($scenario)

    return $scenario
}

function Get-PlanningScenario {
    <#
    .SYNOPSIS
        Retrieves planning scenarios.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$ScenarioID,

        [Parameter()]
        [string]$Name
    )

    $scenarios = $script:PlanningScenarios

    if ($ScenarioID) {
        $scenarios = $scenarios | Where-Object { $_.ScenarioID -eq $ScenarioID }
    }

    if ($Name) {
        $scenarios = $scenarios | Where-Object { $_.Name -like "*$Name*" }
    }

    return $scenarios | Sort-Object CreatedDate -Descending
}

function Compare-Scenarios {
    <#
    .SYNOPSIS
        Compares multiple planning scenarios.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$Scenarios
    )

    $results = @()

    foreach ($scenario in $Scenarios) {
        $name = if ($scenario -is [hashtable]) { $scenario['Name'] } else { $scenario.Name }
        $cost = if ($scenario -is [hashtable]) { [decimal]$scenario['Cost'] } else { [decimal]$scenario.Cost }
        $capacityGain = if ($scenario -is [hashtable]) { [int]$scenario['CapacityGain'] } else { [int]$scenario.CapacityGain }

        $costPerPort = if ($capacityGain -gt 0) { [Math]::Round($cost / $capacityGain, 2) } else { [decimal]::MaxValue }

        $results += [PSCustomObject]@{
            Name = $name
            Cost = $cost
            CapacityGain = $capacityGain
            CostPerPort = $costPerPort
        }
    }

    return $results | Sort-Object CostPerPort
}

function New-EquipmentScenario {
    <#
    .SYNOPSIS
        Models adding new equipment to increase capacity.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter()]
        [string]$Description,

        [Parameter(Mandatory)]
        [ValidateSet('Switch', 'Router', 'AccessPoint', 'Module')]
        [string]$EquipmentType,

        [Parameter(Mandatory)]
        [string]$Model,

        [Parameter(Mandatory)]
        [int]$Quantity,

        [Parameter(Mandatory)]
        [int]$PortsPerUnit,

        [Parameter(Mandatory)]
        [decimal]$UnitCost,

        [Parameter()]
        [decimal]$InstallationCostPerUnit = 500,

        [Parameter()]
        [int]$PoEBudgetPerUnit = 0,

        [Parameter()]
        [string]$TargetSite
    )

    $scenarioId = [Guid]::NewGuid().ToString()
    $totalPorts = $Quantity * $PortsPerUnit
    $totalPoE = $Quantity * $PoEBudgetPerUnit
    $hardwareCost = $Quantity * $UnitCost
    $installCost = $Quantity * $InstallationCostPerUnit
    $totalCost = $hardwareCost + $installCost
    $costPerPort = if ($totalPorts -gt 0) { [Math]::Round($totalCost / $totalPorts, 2) } else { 0 }

    $scenario = [PSCustomObject]@{
        ScenarioID = $scenarioId
        ScenarioType = 'AddEquipment'
        Name = $Name
        Description = if ($Description) { $Description } else { "Add $Quantity x $Model to increase capacity" }
        EquipmentType = $EquipmentType
        Model = $Model
        Quantity = $Quantity
        PortsPerUnit = $PortsPerUnit
        TotalPortsAdded = $totalPorts
        PoEBudgetAdded = $totalPoE
        UnitCost = $UnitCost
        HardwareCost = $hardwareCost
        InstallationCost = $installCost
        TotalCost = $totalCost
        CostPerPort = $costPerPort
        TargetSite = $TargetSite
        CreatedDate = Get-Date
        CreatedBy = $env:USERNAME
    }

    [void]$script:PlanningScenarios.Add($scenario)

    return $scenario
}

function New-TechnologyRefreshScenario {
    <#
    .SYNOPSIS
        Models a technology refresh (e.g., 1G to 10G migration).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter()]
        [string]$Description,

        [Parameter(Mandatory)]
        [ValidateSet('1Gto10G', '10Gto25G', '10Gto40G', '40Gto100G', 'AccessToPoEPlus', 'Custom')]
        [string]$RefreshType,

        [Parameter(Mandatory)]
        [int]$DevicesToReplace,

        [Parameter(Mandatory)]
        [decimal]$OldDeviceValue,

        [Parameter(Mandatory)]
        [decimal]$NewDeviceCost,

        [Parameter()]
        [int]$CapacityGainPerDevice = 0,

        [Parameter()]
        [decimal]$InstallationCostPerDevice = 500,

        [Parameter()]
        [decimal]$DisposalCostPerDevice = 50,

        [Parameter()]
        [string]$TargetSite
    )

    $scenarioId = [Guid]::NewGuid().ToString()

    # Calculate costs
    $newHardwareCost = $DevicesToReplace * $NewDeviceCost
    $installCost = $DevicesToReplace * $InstallationCostPerDevice
    $disposalCost = $DevicesToReplace * $DisposalCostPerDevice
    $tradeInValue = $DevicesToReplace * $OldDeviceValue * 0.1  # Assume 10% trade-in value

    $netCost = $newHardwareCost + $installCost + $disposalCost - $tradeInValue
    $totalCapacityGain = $DevicesToReplace * $CapacityGainPerDevice

    $costPerPortGain = if ($totalCapacityGain -gt 0) { [Math]::Round($netCost / $totalCapacityGain, 2) } else { 0 }

    $refreshDescription = switch ($RefreshType) {
        '1Gto10G' { '1 Gbps to 10 Gbps uplink migration' }
        '10Gto25G' { '10 Gbps to 25 Gbps migration' }
        '10Gto40G' { '10 Gbps to 40 Gbps migration' }
        '40Gto100G' { '40 Gbps to 100 Gbps migration' }
        'AccessToPoEPlus' { 'Standard PoE to PoE+ upgrade' }
        default { 'Custom technology refresh' }
    }

    $scenario = [PSCustomObject]@{
        ScenarioID = $scenarioId
        ScenarioType = 'TechnologyRefresh'
        Name = $Name
        Description = if ($Description) { $Description } else { $refreshDescription }
        RefreshType = $RefreshType
        DevicesToReplace = $DevicesToReplace
        OldDeviceValue = $OldDeviceValue
        NewDeviceCost = $NewDeviceCost
        NewHardwareCost = $newHardwareCost
        InstallationCost = $installCost
        DisposalCost = $disposalCost
        TradeInValue = [Math]::Round($tradeInValue, 2)
        NetCost = [Math]::Round($netCost, 2)
        CapacityGainPerDevice = $CapacityGainPerDevice
        TotalCapacityGain = $totalCapacityGain
        CostPerPortGain = $costPerPortGain
        TargetSite = $TargetSite
        CreatedDate = Get-Date
        CreatedBy = $env:USERNAME
    }

    [void]$script:PlanningScenarios.Add($scenario)

    return $scenario
}

function Get-ScenarioComparison {
    <#
    .SYNOPSIS
        Provides detailed comparison of planning scenarios.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [array]$ScenarioIDs,

        [Parameter()]
        [switch]$IncludeROI,

        [Parameter()]
        [int]$ROIYears = 5,

        [Parameter()]
        [decimal]$AnnualSavingsPerPort = 50
    )

    # Get scenarios to compare
    $scenarios = if ($ScenarioIDs) {
        $script:PlanningScenarios | Where-Object { $_.ScenarioID -in $ScenarioIDs }
    } else {
        $script:PlanningScenarios
    }

    if (@($scenarios).Count -eq 0) {
        return [PSCustomObject]@{
            ComparisonDate = Get-Date
            ScenariosCompared = 0
            Results = @()
            Recommendation = 'No scenarios available for comparison'
        }
    }

    $comparisonResults = @()

    foreach ($scenario in $scenarios) {
        # Calculate metrics based on scenario type
        $totalCost = 0
        $capacityGain = 0
        $costPerPort = 0

        switch ($scenario.ScenarioType) {
            'AddEquipment' {
                $totalCost = $scenario.TotalCost
                $capacityGain = $scenario.TotalPortsAdded
                $costPerPort = $scenario.CostPerPort
            }
            'TechnologyRefresh' {
                $totalCost = $scenario.NetCost
                $capacityGain = $scenario.TotalCapacityGain
                $costPerPort = $scenario.CostPerPortGain
            }
            default {
                $totalCost = if ($scenario.CostEstimate) { $scenario.CostEstimate } else { 0 }
                $capacityGain = if ($scenario.ProjectedChanges -and $scenario.ProjectedChanges['CapacityGain']) {
                    $scenario.ProjectedChanges['CapacityGain']
                } else { 0 }
                $costPerPort = if ($capacityGain -gt 0) { [Math]::Round($totalCost / $capacityGain, 2) } else { 0 }
            }
        }

        # Calculate ROI if requested
        $roi = $null
        $paybackMonths = $null
        if ($IncludeROI -and $capacityGain -gt 0) {
            $annualBenefit = $capacityGain * $AnnualSavingsPerPort
            $totalBenefit = $annualBenefit * $ROIYears
            $roi = if ($totalCost -gt 0) { [Math]::Round((($totalBenefit - $totalCost) / $totalCost) * 100, 1) } else { 0 }
            $paybackMonths = if ($annualBenefit -gt 0) { [Math]::Round(($totalCost / $annualBenefit) * 12, 0) } else { -1 }
        }

        $result = [PSCustomObject]@{
            ScenarioID = $scenario.ScenarioID
            Name = $scenario.Name
            ScenarioType = $scenario.ScenarioType
            TotalCost = $totalCost
            CapacityGain = $capacityGain
            CostPerPort = $costPerPort
            ROIPercent = $roi
            PaybackMonths = $paybackMonths
            CreatedDate = $scenario.CreatedDate
        }

        $comparisonResults += $result
    }

    # Sort by cost per port (best value first)
    $sorted = @($comparisonResults | Sort-Object CostPerPort)

    # Determine recommendation
    $recommendation = if ($sorted.Count -gt 0) {
        $best = $sorted[0]
        if ($best.CostPerPort -eq 0 -and $best.CapacityGain -eq 0) {
            'No capacity-adding scenarios available'
        } else {
            "Recommended: '$($best.Name)' - Best cost efficiency at $($best.CostPerPort) per port"
        }
    } else {
        'No scenarios to compare'
    }

    return [PSCustomObject]@{
        ComparisonDate = Get-Date
        ScenariosCompared = @($comparisonResults).Count
        Results = $sorted
        BestValue = if ($sorted.Count -gt 0) { $sorted[0] } else { $null }
        LowestCost = if ($sorted.Count -gt 0) { $sorted | Sort-Object TotalCost | Select-Object -First 1 } else { $null }
        HighestCapacity = if ($sorted.Count -gt 0) { $sorted | Sort-Object CapacityGain -Descending | Select-Object -First 1 } else { $null }
        Recommendation = $recommendation
    }
}

#endregion

#region Budget Planning

function Get-HardwareProjection {
    <#
    .SYNOPSIS
        Projects hardware needs based on growth.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [double]$CurrentUtilization,

        [Parameter(Mandatory)]
        [double]$GrowthRateMonthly,

        [Parameter()]
        [int]$PlanningHorizonMonths = 24,

        [Parameter()]
        [int]$DeviceCapacity = 48,

        [Parameter()]
        [int]$CurrentTotalPorts = 1000,

        [Parameter()]
        [double]$TargetUtilization = 0.75
    )

    # Calculate current used ports
    $currentUsedPorts = [Math]::Floor($CurrentTotalPorts * $CurrentUtilization)

    # Project ports needed at end of horizon
    $growthFactor = [Math]::Pow(1 + $GrowthRateMonthly, $PlanningHorizonMonths)
    $projectedUsedPorts = [Math]::Ceiling($currentUsedPorts * $growthFactor)

    # Calculate total ports needed to maintain target utilization
    $targetTotalPorts = [Math]::Ceiling($projectedUsedPorts / $TargetUtilization)

    # Calculate additional ports needed
    $additionalPortsNeeded = [Math]::Max(0, $targetTotalPorts - $CurrentTotalPorts)

    # Calculate devices needed
    $additionalDevicesNeeded = [Math]::Ceiling($additionalPortsNeeded / $DeviceCapacity)

    return [PSCustomObject]@{
        CurrentTotalPorts = $CurrentTotalPorts
        CurrentUsedPorts = $currentUsedPorts
        ProjectedUsedPorts = $projectedUsedPorts
        TargetTotalPorts = $targetTotalPorts
        AdditionalPortsNeeded = $additionalPortsNeeded
        AdditionalDevicesNeeded = $additionalDevicesNeeded
        PlanningHorizonMonths = $PlanningHorizonMonths
        GrowthRateMonthly = [Math]::Round($GrowthRateMonthly * 100, 2)
    }
}

function Get-TotalCostEstimate {
    <#
    .SYNOPSIS
        Calculates total cost of ownership.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$Equipment,

        [Parameter()]
        [decimal]$InstallationCostPerDevice = 500,

        [Parameter()]
        [double]$YearlyMaintenancePercent = 0.15,

        [Parameter()]
        [int]$Years = 5
    )

    $hardwareCost = 0
    $deviceCount = 0

    foreach ($item in $Equipment) {
        $count = if ($item -is [hashtable]) { [int]$item['Count'] } else { [int]$item.Count }
        $unitCost = if ($item -is [hashtable]) { [decimal]$item['UnitCost'] } else { [decimal]$item.UnitCost }

        $hardwareCost += $count * $unitCost
        $deviceCount += $count
    }

    $installationCost = $deviceCount * $InstallationCostPerDevice
    $yearlyMaintenance = $hardwareCost * $YearlyMaintenancePercent
    $totalMaintenance = $yearlyMaintenance * $Years

    $fiveYearTCO = $hardwareCost + $installationCost + $totalMaintenance

    return [PSCustomObject]@{
        HardwareCost = $hardwareCost
        InstallationCost = $installationCost
        YearlyMaintenanceCost = [Math]::Round($yearlyMaintenance, 2)
        TotalMaintenanceCost = [Math]::Round($totalMaintenance, 2)
        FiveYearTCO = [Math]::Round($fiveYearTCO, 2)
        DeviceCount = $deviceCount
        Years = $Years
    }
}

function Get-RedeploymentCandidates {
    <#
    .SYNOPSIS
        Identifies underutilized devices for redeployment.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$Devices,

        [Parameter()]
        [double]$MaxUtilization = 0.30
    )

    $candidates = @()

    foreach ($device in $Devices) {
        $hostname = if ($device -is [hashtable]) { $device['Hostname'] } else { $device.Hostname }
        $totalPorts = if ($device -is [hashtable]) { [int]$device['TotalPorts'] } else { [int]$device.TotalPorts }
        $usedPorts = if ($device -is [hashtable]) { [int]$device['UsedPorts'] } else { [int]$device.UsedPorts }
        $age = if ($device -is [hashtable]) { $device['Age'] } else { $device.Age }

        if ($totalPorts -eq 0) { continue }

        $utilization = $usedPorts / $totalPorts

        if ($utilization -le $MaxUtilization) {
            $candidates += [PSCustomObject]@{
                Hostname = $hostname
                TotalPorts = $totalPorts
                UsedPorts = $usedPorts
                AvailablePorts = $totalPorts - $usedPorts
                Utilization = [Math]::Round($utilization * 100, 1)
                Age = $age
                Recommendation = "Consider redeployment - only $([Math]::Round($utilization * 100, 1))% utilized"
            }
        }
    }

    return $candidates | Sort-Object Utilization
}

function Get-BudgetPlanningReport {
    <#
    .SYNOPSIS
        Generates a comprehensive budget planning report.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateSet('Quarterly', 'Annual', 'MultiYear')]
        [string]$PlanningPeriod = 'Annual',

        [Parameter()]
        [int]$Years = 3,

        [Parameter()]
        [double]$GrowthRateMonthly = 0.02,

        [Parameter()]
        [int]$CurrentTotalPorts = 1000,

        [Parameter()]
        [double]$CurrentUtilization = 0.70,

        [Parameter()]
        [decimal]$AverageDeviceCost = 5000,

        [Parameter()]
        [int]$PortsPerDevice = 48,

        [Parameter()]
        [double]$AnnualPriceIncrease = 0.03
    )

    $yearlyProjections = @()
    $cumulativeCost = 0
    $currentPorts = $CurrentTotalPorts
    $currentUsed = [Math]::Floor($CurrentTotalPorts * $CurrentUtilization)

    for ($year = 1; $year -le $Years; $year++) {
        # Project growth for this year
        $growthFactor = [Math]::Pow(1 + $GrowthRateMonthly, 12)
        $projectedUsed = [Math]::Ceiling($currentUsed * $growthFactor)

        # Calculate capacity needed to stay at 75% utilization
        $targetTotalPorts = [Math]::Ceiling($projectedUsed / 0.75)
        $portsNeeded = [Math]::Max(0, $targetTotalPorts - $currentPorts)
        $devicesNeeded = [Math]::Ceiling($portsNeeded / $PortsPerDevice)

        # Calculate costs with inflation
        $adjustedCost = $AverageDeviceCost * [Math]::Pow(1 + $AnnualPriceIncrease, $year - 1)
        $hardwareCost = $devicesNeeded * $adjustedCost
        $installationCost = $devicesNeeded * 500
        $yearCost = $hardwareCost + $installationCost

        $cumulativeCost += $yearCost

        $yearlyProjections += [PSCustomObject]@{
            Year = $year
            FiscalYear = "FY$(((Get-Date).Year + $year).ToString())"
            StartingPorts = $currentPorts
            ProjectedUsedPorts = $projectedUsed
            ProjectedUtilization = if ($currentPorts -gt 0) { [Math]::Round(($projectedUsed / $currentPorts) * 100, 1) } else { 0 }
            TargetTotalPorts = $targetTotalPorts
            AdditionalPortsNeeded = $portsNeeded
            DevicesNeeded = $devicesNeeded
            HardwareCost = [Math]::Round($hardwareCost, 2)
            InstallationCost = [Math]::Round($installationCost, 2)
            YearTotalCost = [Math]::Round($yearCost, 2)
            CumulativeCost = [Math]::Round($cumulativeCost, 2)
        }

        # Update for next year
        $currentPorts = $targetTotalPorts
        $currentUsed = $projectedUsed
    }

    # Generate recommendations
    $recommendations = @()
    $totalDevicesNeeded = ($yearlyProjections | Measure-Object -Property DevicesNeeded -Sum).Sum

    if ($totalDevicesNeeded -gt 0) {
        $recommendations += "Plan for $totalDevicesNeeded additional devices over $Years years"
    }

    $highGrowthYears = @($yearlyProjections | Where-Object { $_.DevicesNeeded -gt 2 })
    if ($highGrowthYears.Count -gt 0) {
        $recommendations += "High growth expected in years: $($highGrowthYears.Year -join ', ')"
    }

    # Check for redeployment opportunities
    if ($CurrentUtilization -lt 0.5) {
        $recommendations += "Consider consolidation before purchasing - current utilization is low"
    }

    return [PSCustomObject]@{
        ReportType = 'BudgetPlanning'
        PlanningPeriod = $PlanningPeriod
        YearsPlanned = $Years
        GeneratedDate = Get-Date
        GeneratedBy = $env:USERNAME

        # Current State
        CurrentTotalPorts = $CurrentTotalPorts
        CurrentUsedPorts = [Math]::Floor($CurrentTotalPorts * $CurrentUtilization)
        CurrentUtilization = [Math]::Round($CurrentUtilization * 100, 1)

        # Assumptions
        MonthlyGrowthRate = [Math]::Round($GrowthRateMonthly * 100, 2)
        AnnualGrowthRate = [Math]::Round(([Math]::Pow(1 + $GrowthRateMonthly, 12) - 1) * 100, 1)
        AverageDeviceCost = $AverageDeviceCost
        PortsPerDevice = $PortsPerDevice
        AnnualPriceIncrease = [Math]::Round($AnnualPriceIncrease * 100, 1)

        # Projections
        YearlyProjections = $yearlyProjections
        TotalDevicesNeeded = $totalDevicesNeeded
        TotalBudgetRequired = [Math]::Round($cumulativeCost, 2)

        # Summary
        Recommendations = $recommendations
    }
}

#endregion

#region Reports

function New-CapacityReport {
    <#
    .SYNOPSIS
        Generates a capacity planning report.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateSet('Executive', 'Detailed', 'Summary')]
        [string]$Type = 'Summary',

        [Parameter()]
        [string]$Scope = 'Enterprise'
    )

    $reportId = [Guid]::NewGuid().ToString()

    $sections = switch ($Type) {
        'Executive' { @('Summary', 'RiskAreas', 'Recommendations', 'Budget') }
        'Detailed' { @('Summary', 'DeviceDetails', 'SiteAnalysis', 'Forecasts', 'Scenarios', 'Recommendations') }
        'Summary' { @('Summary', 'Utilization', 'Alerts') }
    }

    # Gather statistics
    $snapshots = Get-UtilizationSnapshot -Scope $Scope | Select-Object -First 1
    $forecasts = @($script:GrowthForecasts)
    $scenarios = @($script:PlanningScenarios)

    $report = [PSCustomObject]@{
        ReportID = $reportId
        Type = $Type
        Scope = $Scope
        GeneratedDate = Get-Date
        GeneratedBy = $env:USERNAME
        Sections = $sections
        SnapshotCount = @($snapshots).Count
        ForecastCount = $forecasts.Count
        ScenarioCount = $scenarios.Count
        DeviceDetails = if ($Type -eq 'Detailed') { $snapshots } else { $null }
        Forecasts = if ($Type -eq 'Detailed') { $forecasts } else { $null }
    }

    return $report
}

function Get-CapacityStatistics {
    <#
    .SYNOPSIS
        Gets overall capacity statistics.
    #>
    [CmdletBinding()]
    param()

    $snapshots = @($script:UtilizationSnapshots)
    $thresholds = @($script:CapacityThresholds)
    $forecasts = @($script:GrowthForecasts)
    $scenarios = @($script:PlanningScenarios)

    return [PSCustomObject]@{
        TotalSnapshots = $snapshots.Count
        TotalThresholds = $thresholds.Count
        EnabledThresholds = @($thresholds | Where-Object { $_.IsEnabled }).Count
        TotalForecasts = $forecasts.Count
        TotalScenarios = $scenarios.Count
        LastSnapshotDate = if ($snapshots.Count -gt 0) { ($snapshots | Sort-Object SnapshotDate -Descending | Select-Object -First 1).SnapshotDate } else { $null }
    }
}

function Export-CapacityReport {
    <#
    .SYNOPSIS
        Exports a capacity report to various formats.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Report,

        [Parameter()]
        [ValidateSet('Text', 'HTML', 'JSON', 'CSV')]
        [string]$Format = 'Text',

        [Parameter(Mandatory)]
        [string]$OutputPath
    )

    # Generate report if not provided
    if (-not $Report) {
        $Report = New-CapacityReport -Type 'Summary'
    }

    $extension = switch ($Format) {
        'Text' { 'txt' }
        'HTML' { 'html' }
        'JSON' { 'json' }
        'CSV' { 'csv' }
    }

    $filename = "CapacityReport_$(Get-Date -Format 'yyyyMMdd-HHmmss').$extension"
    $fullPath = Join-Path $OutputPath $filename

    switch ($Format) {
        'Text' {
            $text = @"
CAPACITY PLANNING REPORT
========================
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Report Type: $($Report.Type)
Scope: $($Report.Scope)

SUMMARY
-------
Snapshots: $($Report.SnapshotCount)
Forecasts: $($Report.ForecastCount)
Scenarios: $($Report.ScenarioCount)

SECTIONS INCLUDED
-----------------
$($Report.Sections -join "`n")

---
Generated by StateTrace Capacity Planning Module
"@
            $text | Set-Content -Path $fullPath
        }

        'HTML' {
            $sectionsHtml = ($Report.Sections | ForEach-Object { "<li>$_</li>" }) -join "`n"

            $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Capacity Planning Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #333; border-bottom: 2px solid #0066cc; padding-bottom: 10px; }
        h2 { color: #0066cc; margin-top: 20px; }
        .meta { color: #666; font-size: 0.9em; }
        .summary { background: #f5f5f5; padding: 15px; border-radius: 5px; margin: 15px 0; }
        .summary-item { margin: 10px 0; }
        .label { font-weight: bold; }
        ul { list-style-type: square; }
        .footer { margin-top: 30px; padding-top: 15px; border-top: 1px solid #ddd; color: #666; font-size: 0.8em; }
    </style>
</head>
<body>
    <h1>Capacity Planning Report</h1>
    <p class="meta">Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | Type: $($Report.Type) | Scope: $($Report.Scope)</p>

    <div class="summary">
        <h2>Summary</h2>
        <div class="summary-item"><span class="label">Snapshots:</span> $($Report.SnapshotCount)</div>
        <div class="summary-item"><span class="label">Forecasts:</span> $($Report.ForecastCount)</div>
        <div class="summary-item"><span class="label">Scenarios:</span> $($Report.ScenarioCount)</div>
    </div>

    <h2>Sections Included</h2>
    <ul>
        $sectionsHtml
    </ul>

    <div class="footer">
        Generated by StateTrace Capacity Planning Module
    </div>
</body>
</html>
"@
            $html | Set-Content -Path $fullPath
        }

        'JSON' {
            $Report | ConvertTo-Json -Depth 10 | Set-Content -Path $fullPath
        }

        'CSV' {
            # For CSV, export a summary row
            $csvData = [PSCustomObject]@{
                ReportID = $Report.ReportID
                Type = $Report.Type
                Scope = $Report.Scope
                GeneratedDate = $Report.GeneratedDate
                SnapshotCount = $Report.SnapshotCount
                ForecastCount = $Report.ForecastCount
                ScenarioCount = $Report.ScenarioCount
                Sections = ($Report.Sections -join '; ')
            }
            $csvData | Export-Csv -Path $fullPath -NoTypeInformation
        }
    }

    return [PSCustomObject]@{
        Path = $fullPath
        Format = $Format
        ReportType = $Report.Type
        ExportedAt = Get-Date
    }
}

function Export-BudgetPlanningReport {
    <#
    .SYNOPSIS
        Exports a budget planning report to various formats.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Report,

        [Parameter()]
        [ValidateSet('Text', 'HTML', 'JSON', 'CSV')]
        [string]$Format = 'Text',

        [Parameter(Mandatory)]
        [string]$OutputPath
    )

    $extension = switch ($Format) {
        'Text' { 'txt' }
        'HTML' { 'html' }
        'JSON' { 'json' }
        'CSV' { 'csv' }
    }

    $filename = "BudgetPlanningReport_$(Get-Date -Format 'yyyyMMdd-HHmmss').$extension"
    $fullPath = Join-Path $OutputPath $filename

    switch ($Format) {
        'Text' {
            $yearlyText = ($Report.YearlyProjections | ForEach-Object {
                "$($_.FiscalYear): Need $($_.DevicesNeeded) devices (+$($_.AdditionalPortsNeeded) ports) - Cost: `$$($_.YearTotalCost)"
            }) -join "`n"

            $recsText = ($Report.Recommendations | ForEach-Object { "- $_" }) -join "`n"

            $text = @"
BUDGET PLANNING REPORT
======================
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Planning Period: $($Report.PlanningPeriod)
Years Planned: $($Report.YearsPlanned)

CURRENT STATE
-------------
Total Ports: $($Report.CurrentTotalPorts)
Used Ports: $($Report.CurrentUsedPorts)
Utilization: $($Report.CurrentUtilization)%

ASSUMPTIONS
-----------
Monthly Growth Rate: $($Report.MonthlyGrowthRate)%
Annual Growth Rate: $($Report.AnnualGrowthRate)%
Average Device Cost: `$$($Report.AverageDeviceCost)
Ports Per Device: $($Report.PortsPerDevice)
Annual Price Increase: $($Report.AnnualPriceIncrease)%

YEARLY PROJECTIONS
------------------
$yearlyText

SUMMARY
-------
Total Devices Needed: $($Report.TotalDevicesNeeded)
Total Budget Required: `$$($Report.TotalBudgetRequired)

RECOMMENDATIONS
---------------
$recsText

---
Generated by StateTrace Capacity Planning Module
"@
            $text | Set-Content -Path $fullPath
        }

        'HTML' {
            $yearlyRows = ($Report.YearlyProjections | ForEach-Object {
                "<tr><td>$($_.FiscalYear)</td><td>$($_.DevicesNeeded)</td><td>$($_.AdditionalPortsNeeded)</td><td>$($_.ProjectedUtilization)%</td><td>`$$($_.YearTotalCost)</td><td>`$$($_.CumulativeCost)</td></tr>"
            }) -join "`n"

            $recsHtml = ($Report.Recommendations | ForEach-Object { "<li>$_</li>" }) -join "`n"

            $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Budget Planning Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #333; border-bottom: 2px solid #28a745; padding-bottom: 10px; }
        h2 { color: #28a745; margin-top: 20px; }
        .meta { color: #666; font-size: 0.9em; }
        .summary-box { background: #f8f9fa; padding: 15px; border-radius: 5px; margin: 15px 0; border-left: 4px solid #28a745; }
        .total { font-size: 1.5em; color: #28a745; font-weight: bold; }
        table { border-collapse: collapse; width: 100%; margin: 15px 0; }
        th, td { border: 1px solid #ddd; padding: 10px; text-align: left; }
        th { background: #28a745; color: white; }
        tr:nth-child(even) { background: #f9f9f9; }
        ul { list-style-type: square; }
        .footer { margin-top: 30px; padding-top: 15px; border-top: 1px solid #ddd; color: #666; font-size: 0.8em; }
    </style>
</head>
<body>
    <h1>Budget Planning Report</h1>
    <p class="meta">Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | Period: $($Report.PlanningPeriod) | Years: $($Report.YearsPlanned)</p>

    <div class="summary-box">
        <h2>Budget Summary</h2>
        <p class="total">Total Budget Required: `$$($Report.TotalBudgetRequired)</p>
        <p>Total Devices Needed: $($Report.TotalDevicesNeeded)</p>
    </div>

    <h2>Current State</h2>
    <p>Total Ports: $($Report.CurrentTotalPorts) | Used: $($Report.CurrentUsedPorts) | Utilization: $($Report.CurrentUtilization)%</p>

    <h2>Yearly Projections</h2>
    <table>
        <tr><th>Fiscal Year</th><th>Devices Needed</th><th>Ports Added</th><th>Projected Util</th><th>Year Cost</th><th>Cumulative</th></tr>
        $yearlyRows
    </table>

    <h2>Recommendations</h2>
    <ul>
        $recsHtml
    </ul>

    <div class="footer">
        Generated by StateTrace Capacity Planning Module
    </div>
</body>
</html>
"@
            $html | Set-Content -Path $fullPath
        }

        'JSON' {
            $Report | ConvertTo-Json -Depth 10 | Set-Content -Path $fullPath
        }

        'CSV' {
            # Export yearly projections as CSV
            $Report.YearlyProjections | Export-Csv -Path $fullPath -NoTypeInformation
        }
    }

    return [PSCustomObject]@{
        Path = $fullPath
        Format = $Format
        ReportType = 'BudgetPlanning'
        ExportedAt = Get-Date
    }
}

#endregion

#region Import/Export Database

function Import-CapacityPlanningDatabase {
    <#
    .SYNOPSIS
        Imports capacity planning data from a JSON file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        return
    }

    try {
        $data = Get-Content -Path $Path -Raw | ConvertFrom-Json

        if ($data.Snapshots) {
            foreach ($item in $data.Snapshots) {
                [void]$script:UtilizationSnapshots.Add($item)
            }
        }

        if ($data.Thresholds) {
            foreach ($item in $data.Thresholds) {
                $existing = $script:CapacityThresholds | Where-Object { $_.ThresholdID -eq $item.ThresholdID }
                if (-not $existing) {
                    [void]$script:CapacityThresholds.Add($item)
                }
            }
        }

        if ($data.Forecasts) {
            foreach ($item in $data.Forecasts) {
                [void]$script:GrowthForecasts.Add($item)
            }
        }

        if ($data.Scenarios) {
            foreach ($item in $data.Scenarios) {
                [void]$script:PlanningScenarios.Add($item)
            }
        }
    }
    catch {
        Write-Warning "Failed to import capacity planning database: $_"
    }
}

function Export-CapacityPlanningDatabase {
    <#
    .SYNOPSIS
        Exports the capacity planning database to a JSON file.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Path
    )

    if (-not $Path) {
        $Path = $script:DatabasePath
    }

    if (-not $Path) {
        throw "No database path specified"
    }

    $data = @{
        Snapshots = @($script:UtilizationSnapshots)
        Thresholds = @($script:CapacityThresholds | Where-Object { $_.ThresholdID -notlike 'DEFAULT-*' })
        Forecasts = @($script:GrowthForecasts)
        Scenarios = @($script:PlanningScenarios)
        ExportDate = Get-Date
    }

    $data | ConvertTo-Json -Depth 10 | Set-Content -Path $Path

    return [PSCustomObject]@{
        Path = $Path
        SnapshotCount = $data.Snapshots.Count
        ThresholdCount = $data.Thresholds.Count
        ForecastCount = $data.Forecasts.Count
        ScenarioCount = $data.Scenarios.Count
    }
}

#endregion

#region Test Helpers

function Clear-CapacityPlanningData {
    <#
    .SYNOPSIS
        Clears all capacity planning data (for testing).
    #>
    [CmdletBinding()]
    param()

    $script:UtilizationSnapshots.Clear()
    $script:CapacityThresholds.Clear()
    $script:GrowthForecasts.Clear()
    $script:PlanningScenarios.Clear()

    # Reload default thresholds
    Initialize-DefaultThresholds
}

#endregion

# Initialize on module load
Initialize-CapacityPlanningDatabase

# Export functions
Export-ModuleMember -Function @(
    # Initialization
    'Initialize-CapacityPlanningDatabase'

    # Utilization Calculations
    'Get-PortUtilization'
    'Get-PoEUtilization'
    'Get-SiteUtilization'
    'Get-VLANUtilization'

    # Snapshot Management
    'New-UtilizationSnapshot'
    'Get-UtilizationSnapshot'
    'Get-UtilizationHistory'

    # Trend Analysis & Forecasting
    'Get-GrowthRate'
    'Get-LinearForecast'
    'Get-ThresholdBreachDate'
    'Get-SeasonalForecast'

    # Threshold Management
    'Get-CapacityThreshold'
    'New-CapacityThreshold'
    'Add-CapacityThreshold'
    'Set-CapacityThreshold'
    'Remove-CapacityThreshold'
    'Get-CapacityWarnings'
    'Get-CapacityStatus'
    'Get-ForecastAlert'

    # What-If Scenarios
    'Get-ScenarioImpact'
    'New-VLANDeploymentScenario'
    'New-PlanningScenario'
    'Get-PlanningScenario'
    'Compare-Scenarios'
    'New-EquipmentScenario'
    'New-TechnologyRefreshScenario'
    'Get-ScenarioComparison'

    # Budget Planning
    'Get-HardwareProjection'
    'Get-TotalCostEstimate'
    'Get-RedeploymentCandidates'
    'Get-BudgetPlanningReport'

    # Reports
    'New-CapacityReport'
    'Get-CapacityStatistics'
    'Export-CapacityReport'
    'Export-BudgetPlanningReport'

    # Import/Export
    'Import-CapacityPlanningDatabase'
    'Export-CapacityPlanningDatabase'

    # Test Helpers
    'Clear-CapacityPlanningData'
)
