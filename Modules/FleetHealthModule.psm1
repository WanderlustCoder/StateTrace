# FleetHealthModule.psm1
# Fleet health monitoring, anomaly detection, trend analysis, and capacity forecasting

Set-StrictMode -Version Latest

#region Configuration
$script:HealthConfig = @{
    AnomalyThresholdStdDev = 2.0
    TrendWindowDays = 30
    ForecastHorizonDays = 90
    BaselineWindowDays = 14
    HealthCheckThresholds = @{
        PortUtilizationWarning = 70
        PortUtilizationCritical = 90
        ErrorRateWarning = 5
        ErrorRateCritical = 10
        UptimeWarning = 99.0
        UptimeCritical = 95.0
    }
}

function Set-FleetHealthConfig {
    [CmdletBinding()]
    param(
        [double]$AnomalyThresholdStdDev,
        [int]$TrendWindowDays,
        [int]$ForecastHorizonDays,
        [int]$BaselineWindowDays,
        [hashtable]$HealthCheckThresholds
    )

    if ($PSBoundParameters.ContainsKey('AnomalyThresholdStdDev')) {
        $script:HealthConfig.AnomalyThresholdStdDev = $AnomalyThresholdStdDev
    }
    if ($PSBoundParameters.ContainsKey('TrendWindowDays')) {
        $script:HealthConfig.TrendWindowDays = $TrendWindowDays
    }
    if ($PSBoundParameters.ContainsKey('ForecastHorizonDays')) {
        $script:HealthConfig.ForecastHorizonDays = $ForecastHorizonDays
    }
    if ($PSBoundParameters.ContainsKey('BaselineWindowDays')) {
        $script:HealthConfig.BaselineWindowDays = $BaselineWindowDays
    }
    if ($HealthCheckThresholds) {
        foreach ($key in $HealthCheckThresholds.Keys) {
            $script:HealthConfig.HealthCheckThresholds[$key] = $HealthCheckThresholds[$key]
        }
    }

    return $script:HealthConfig.Clone()
}

function Get-FleetHealthConfig {
    [CmdletBinding()]
    param()
    return $script:HealthConfig.Clone()
}
#endregion

#region Fleet Health Dashboard
function Get-FleetHealthSummary {
    [CmdletBinding()]
    param(
        [string]$DataPath,
        [string[]]$Sites,
        [datetime]$AsOf
    )

    if (-not $AsOf) { $AsOf = [datetime]::UtcNow }

    $summary = @{
        Timestamp = $AsOf.ToString('o')
        TotalDevices = 0
        TotalInterfaces = 0
        DevicesByStatus = @{}
        InterfacesByStatus = @{}
        SiteBreakdown = @{}
        HealthScore = 100
        Alerts = @()
    }

    # Try to get data from repository modules if available
    $repoModule = Get-Module -Name 'DeviceRepositoryModule' -ErrorAction SilentlyContinue
    if ($repoModule) {
        try {
            $devices = Get-AllDevices -ErrorAction SilentlyContinue
            if ($devices) {
                $summary.TotalDevices = @($devices).Count

                foreach ($device in $devices) {
                    $status = if ($device.Status) { $device.Status } else { 'Unknown' }
                    if (-not $summary.DevicesByStatus.ContainsKey($status)) {
                        $summary.DevicesByStatus[$status] = 0
                    }
                    $summary.DevicesByStatus[$status]++

                    $site = if ($device.Site) { $device.Site } else { 'Unknown' }
                    if (-not $summary.SiteBreakdown.ContainsKey($site)) {
                        $summary.SiteBreakdown[$site] = @{ Devices = 0; Interfaces = 0 }
                    }
                    $summary.SiteBreakdown[$site].Devices++
                }
            }
        } catch {
            $summary.Alerts += "Failed to retrieve device data: $($_.Exception.Message)"
        }
    }

    # Calculate health score
    $downDevices = if ($summary.DevicesByStatus['Down']) { $summary.DevicesByStatus['Down'] } else { 0 }
    $warningDevices = if ($summary.DevicesByStatus['Warning']) { $summary.DevicesByStatus['Warning'] } else { 0 }

    if ($summary.TotalDevices -gt 0) {
        $healthyPercent = (($summary.TotalDevices - $downDevices - $warningDevices) / $summary.TotalDevices) * 100
        $summary.HealthScore = [math]::Round($healthyPercent, 1)
    }

    return [PSCustomObject]$summary
}

function Get-FleetStatusDistribution {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Items,

        [string]$StatusProperty = 'Status'
    )

    $distribution = @{}
    $total = 0

    foreach ($item in $Items) {
        $status = $item.$StatusProperty
        if (-not $status) { $status = 'Unknown' }

        if (-not $distribution.ContainsKey($status)) {
            $distribution[$status] = @{
                Count = 0
                Percent = 0
                Items = [System.Collections.Generic.List[object]]::new()
            }
        }

        $distribution[$status].Count++
        $distribution[$status].Items.Add($item)
        $total++
    }

    # Calculate percentages
    foreach ($status in $distribution.Keys) {
        if ($total -gt 0) {
            $distribution[$status].Percent = [math]::Round(($distribution[$status].Count / $total) * 100, 2)
        }
    }

    return @{
        Distribution = $distribution
        Total = $total
    }
}
#endregion

#region Scheduled Reports
$script:ReportTemplates = @{}

function Register-FleetReportTemplate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory)]
        [scriptblock]$Generator,

        [string]$Description,

        [ValidateSet('Daily', 'Weekly', 'Monthly')]
        [string]$DefaultSchedule = 'Daily',

        [string[]]$RequiredModules
    )

    $script:ReportTemplates[$Name] = @{
        Name = $Name
        Title = $Title
        Description = $Description
        Generator = $Generator
        DefaultSchedule = $DefaultSchedule
        RequiredModules = $RequiredModules
        RegisteredAt = [datetime]::UtcNow
    }

    return $script:ReportTemplates[$Name]
}

function Get-FleetReportTemplates {
    [CmdletBinding()]
    param(
        [string]$Name
    )

    if ($Name) {
        if ($script:ReportTemplates.ContainsKey($Name)) {
            return $script:ReportTemplates[$Name]
        }
        return $null
    }

    return $script:ReportTemplates.Clone()
}

function New-FleetReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TemplateName,

        [string]$OutputPath,

        [ValidateSet('Markdown', 'Html', 'Json', 'Csv')]
        [string]$Format = 'Markdown',

        [hashtable]$Parameters
    )

    $template = Get-FleetReportTemplates -Name $TemplateName
    if (-not $template) {
        throw "Report template not found: $TemplateName"
    }

    # Load required modules
    if ($template.RequiredModules) {
        foreach ($mod in $template.RequiredModules) {
            if (-not (Get-Module -Name $mod -ErrorAction SilentlyContinue)) {
                $modPath = Join-Path $PSScriptRoot "$mod.psm1"
                if (Test-Path $modPath) {
                    Import-Module $modPath -Force
                }
            }
        }
    }

    # Generate report data
    $reportData = & $template.Generator -Parameters $Parameters

    $report = @{
        Title = $template.Title
        GeneratedAt = [datetime]::UtcNow.ToString('o')
        Template = $TemplateName
        Data = $reportData
    }

    # Format output
    $output = switch ($Format) {
        'Json' {
            $report | ConvertTo-Json -Depth 10
        }
        'Csv' {
            if ($reportData -is [array]) {
                $reportData | ConvertTo-Csv -NoTypeInformation
            } else {
                $reportData | ConvertTo-Csv -NoTypeInformation
            }
        }
        'Html' {
            New-FleetReportHtml -Report $report
        }
        'Markdown' {
            New-FleetReportMarkdown -Report $report
        }
    }

    if ($OutputPath) {
        $parent = Split-Path -Parent $OutputPath
        if ($parent -and -not (Test-Path $parent)) {
            New-Item -Path $parent -ItemType Directory -Force | Out-Null
        }
        $output | Set-Content -Path $OutputPath -Encoding UTF8

        return @{
            Path = $OutputPath
            Format = $Format
            GeneratedAt = $report.GeneratedAt
        }
    }

    return $output
}

function New-FleetReportMarkdown {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Report
    )

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("# $($Report.Title)")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("**Generated:** $($Report.GeneratedAt)")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('---')
    [void]$sb.AppendLine('')

    $data = $Report.Data
    if ($data -is [hashtable] -or $data -is [PSCustomObject]) {
        foreach ($key in $data.PSObject.Properties.Name) {
            $value = $data.$key
            if ($value -is [array]) {
                [void]$sb.AppendLine("## $key")
                [void]$sb.AppendLine('')
                if ($value.Count -gt 0 -and $value[0] -is [PSCustomObject]) {
                    $props = $value[0].PSObject.Properties.Name
                    [void]$sb.AppendLine("| $($props -join ' | ') |")
                    [void]$sb.AppendLine("| $(($props | ForEach-Object { '---' }) -join ' | ') |")
                    foreach ($row in $value) {
                        $vals = $props | ForEach-Object { $row.$_ }
                        [void]$sb.AppendLine("| $($vals -join ' | ') |")
                    }
                } else {
                    foreach ($item in $value) {
                        [void]$sb.AppendLine("- $item")
                    }
                }
                [void]$sb.AppendLine('')
            } elseif ($value -is [hashtable]) {
                [void]$sb.AppendLine("## $key")
                [void]$sb.AppendLine('')
                foreach ($subKey in $value.Keys) {
                    [void]$sb.AppendLine("- **$subKey**: $($value[$subKey])")
                }
                [void]$sb.AppendLine('')
            } else {
                [void]$sb.AppendLine("**$key**: $value")
                [void]$sb.AppendLine('')
            }
        }
    }

    return $sb.ToString()
}

function New-FleetReportHtml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Report
    )

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('<!DOCTYPE html>')
    [void]$sb.AppendLine('<html><head>')
    [void]$sb.AppendLine("<title>$($Report.Title)</title>")
    [void]$sb.AppendLine('<style>body{font-family:Arial,sans-serif;margin:20px}table{border-collapse:collapse;width:100%}th,td{border:1px solid #ddd;padding:8px;text-align:left}th{background:#4CAF50;color:white}.metric{font-size:24px;font-weight:bold}</style>')
    [void]$sb.AppendLine('</head><body>')
    [void]$sb.AppendLine("<h1>$($Report.Title)</h1>")
    [void]$sb.AppendLine("<p><em>Generated: $($Report.GeneratedAt)</em></p>")
    [void]$sb.AppendLine('<hr/>')

    $data = $Report.Data
    if ($data) {
        [void]$sb.AppendLine('<pre>')
        [void]$sb.AppendLine(($data | ConvertTo-Json -Depth 5))
        [void]$sb.AppendLine('</pre>')
    }

    [void]$sb.AppendLine('</body></html>')
    return $sb.ToString()
}
#endregion

#region Anomaly Detection
function Get-RollingBaseline {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [double[]]$Values,

        [int]$WindowSize = 14
    )

    if ($Values.Count -eq 0) {
        return @{
            Mean = 0
            StdDev = 0
            Min = 0
            Max = 0
            Count = 0
        }
    }

    $window = if ($Values.Count -le $WindowSize) {
        $Values
    } else {
        $Values[($Values.Count - $WindowSize)..($Values.Count - 1)]
    }

    $mean = ($window | Measure-Object -Average).Average
    $sumSquares = ($window | ForEach-Object { [math]::Pow($_ - $mean, 2) } | Measure-Object -Sum).Sum
    $variance = if ($window.Count -gt 1) { $sumSquares / ($window.Count - 1) } else { 0 }
    $stdDev = [math]::Sqrt($variance)

    return @{
        Mean = [math]::Round($mean, 4)
        StdDev = [math]::Round($stdDev, 4)
        Min = ($window | Measure-Object -Minimum).Minimum
        Max = ($window | Measure-Object -Maximum).Maximum
        Count = $window.Count
    }
}

function Test-AnomalyDetection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [double]$Value,

        [Parameter(Mandatory)]
        [double]$BaselineMean,

        [Parameter(Mandatory)]
        [double]$BaselineStdDev,

        [double]$ThresholdStdDev
    )

    if (-not $ThresholdStdDev) {
        $ThresholdStdDev = $script:HealthConfig.AnomalyThresholdStdDev
    }

    $result = @{
        Value = $Value
        BaselineMean = $BaselineMean
        BaselineStdDev = $BaselineStdDev
        IsAnomaly = $false
        DeviationStdDev = 0
        Direction = 'Normal'
        Severity = 'None'
    }

    if ($BaselineStdDev -eq 0) {
        $result.IsAnomaly = $Value -ne $BaselineMean
        $result.Direction = if ($Value -gt $BaselineMean) { 'High' } elseif ($Value -lt $BaselineMean) { 'Low' } else { 'Normal' }
        return [PSCustomObject]$result
    }

    $deviation = ($Value - $BaselineMean) / $BaselineStdDev
    $result.DeviationStdDev = [math]::Round($deviation, 2)

    if ([math]::Abs($deviation) -gt $ThresholdStdDev) {
        $result.IsAnomaly = $true
        $result.Direction = if ($deviation -gt 0) { 'High' } else { 'Low' }

        $absDeviation = [math]::Abs($deviation)
        $result.Severity = switch ($true) {
            ($absDeviation -gt $ThresholdStdDev * 2) { 'Critical' }
            ($absDeviation -gt $ThresholdStdDev * 1.5) { 'Warning' }
            default { 'Info' }
        }
    }

    return [PSCustomObject]$result
}

function Find-MetricAnomalies {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$DataPoints,

        [Parameter(Mandatory)]
        [string]$ValueProperty,

        [string]$TimestampProperty = 'Timestamp',

        [int]$BaselineWindowSize
    )

    if (-not $BaselineWindowSize) {
        $BaselineWindowSize = $script:HealthConfig.BaselineWindowDays
    }

    $sorted = $DataPoints | Sort-Object $TimestampProperty
    $values = @($sorted | ForEach-Object { $_.$ValueProperty })

    $anomalies = [System.Collections.Generic.List[object]]::new()

    for ($i = $BaselineWindowSize; $i -lt $values.Count; $i++) {
        $baselineValues = $values[($i - $BaselineWindowSize)..($i - 1)]
        $baseline = Get-RollingBaseline -Values $baselineValues -WindowSize $BaselineWindowSize
        $current = $values[$i]

        $detection = Test-AnomalyDetection -Value $current -BaselineMean $baseline.Mean -BaselineStdDev $baseline.StdDev

        if ($detection.IsAnomaly) {
            $anomalies.Add(@{
                Index = $i
                Timestamp = $sorted[$i].$TimestampProperty
                Value = $current
                Baseline = $baseline
                Detection = $detection
                DataPoint = $sorted[$i]
            })
        }
    }

    return @{
        TotalPoints = $values.Count
        AnomaliesFound = $anomalies.Count
        Anomalies = $anomalies.ToArray()
        AnomalyRate = if ($values.Count -gt 0) { [math]::Round(($anomalies.Count / $values.Count) * 100, 2) } else { 0 }
    }
}
#endregion

#region Trend Analysis
function Get-MetricTrend {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$DataPoints,

        [Parameter(Mandatory)]
        [string]$ValueProperty,

        [string]$TimestampProperty = 'Timestamp',

        [int]$WindowDays
    )

    if (-not $WindowDays) {
        $WindowDays = $script:HealthConfig.TrendWindowDays
    }

    $sorted = $DataPoints | Sort-Object $TimestampProperty
    $values = @($sorted | ForEach-Object { $_.$ValueProperty })

    if ($values.Count -lt 2) {
        return @{
            Trend = 'Insufficient Data'
            Slope = 0
            Correlation = 0
            StartValue = if ($values.Count -gt 0) { $values[0] } else { 0 }
            EndValue = if ($values.Count -gt 0) { $values[-1] } else { 0 }
            ChangePercent = 0
        }
    }

    # Simple linear regression
    $n = $values.Count
    $xValues = 0..($n - 1)
    $xMean = ($xValues | Measure-Object -Average).Average
    $yMean = ($values | Measure-Object -Average).Average

    $sumXY = 0
    $sumX2 = 0
    $sumY2 = 0

    for ($i = 0; $i -lt $n; $i++) {
        $xDiff = $xValues[$i] - $xMean
        $yDiff = $values[$i] - $yMean
        $sumXY += $xDiff * $yDiff
        $sumX2 += $xDiff * $xDiff
        $sumY2 += $yDiff * $yDiff
    }

    $slope = if ($sumX2 -ne 0) { $sumXY / $sumX2 } else { 0 }
    $correlation = if ($sumX2 -ne 0 -and $sumY2 -ne 0) {
        $sumXY / [math]::Sqrt($sumX2 * $sumY2)
    } else { 0 }

    $startValue = $values[0]
    $endValue = $values[-1]
    $changePercent = if ($startValue -ne 0) {
        [math]::Round((($endValue - $startValue) / $startValue) * 100, 2)
    } else { 0 }

    $trend = switch ($true) {
        ($slope -gt 0.1 -and $correlation -gt 0.5) { 'Increasing' }
        ($slope -lt -0.1 -and $correlation -lt -0.5) { 'Decreasing' }
        ([math]::Abs($slope) -le 0.1) { 'Stable' }
        default { 'Volatile' }
    }

    return @{
        Trend = $trend
        Slope = [math]::Round($slope, 4)
        Correlation = [math]::Round($correlation, 4)
        StartValue = $startValue
        EndValue = $endValue
        ChangePercent = $changePercent
        DataPoints = $n
        Mean = [math]::Round($yMean, 2)
        Min = ($values | Measure-Object -Minimum).Minimum
        Max = ($values | Measure-Object -Maximum).Maximum
    }
}

function Get-TrendAnalysisReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$DataPoints,

        [Parameter(Mandatory)]
        [string[]]$MetricProperties,

        [string]$TimestampProperty = 'Timestamp'
    )

    $report = @{
        GeneratedAt = [datetime]::UtcNow.ToString('o')
        TotalDataPoints = $DataPoints.Count
        Metrics = @{}
    }

    foreach ($metric in $MetricProperties) {
        $trend = Get-MetricTrend -DataPoints $DataPoints -ValueProperty $metric -TimestampProperty $TimestampProperty
        $report.Metrics[$metric] = $trend
    }

    return [PSCustomObject]$report
}
#endregion

#region Capacity Forecasting
function Get-CapacityForecast {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$DataPoints,

        [Parameter(Mandatory)]
        [string]$ValueProperty,

        [string]$TimestampProperty = 'Timestamp',

        [int]$ForecastDays,

        [double]$CapacityLimit
    )

    if (-not $ForecastDays) {
        $ForecastDays = $script:HealthConfig.ForecastHorizonDays
    }

    $trend = Get-MetricTrend -DataPoints $DataPoints -ValueProperty $ValueProperty -TimestampProperty $TimestampProperty

    $forecast = @{
        CurrentValue = $trend.EndValue
        Trend = $trend.Trend
        DailyChange = $trend.Slope
        ForecastDays = $ForecastDays
        Projections = @()
        CapacityLimit = $CapacityLimit
        DaysToCapacity = $null
        CapacityReachedDate = $null
    }

    # Generate projections
    $currentValue = $trend.EndValue
    for ($day = 1; $day -le $ForecastDays; $day++) {
        $projectedValue = $currentValue + ($trend.Slope * $day)
        $forecast.Projections += @{
            Day = $day
            Date = [datetime]::UtcNow.AddDays($day).ToString('yyyy-MM-dd')
            ProjectedValue = [math]::Round($projectedValue, 2)
        }

        # Check capacity threshold
        if ($CapacityLimit -and $projectedValue -ge $CapacityLimit -and -not $forecast.DaysToCapacity) {
            $forecast.DaysToCapacity = $day
            $forecast.CapacityReachedDate = [datetime]::UtcNow.AddDays($day).ToString('yyyy-MM-dd')
        }
    }

    $lastProjection = $forecast.Projections[-1].ProjectedValue
    $forecast.ForecastedValue = $lastProjection
    $forecast.ForecastedChangePercent = if ($currentValue -ne 0) {
        [math]::Round((($lastProjection - $currentValue) / $currentValue) * 100, 2)
    } else { 0 }

    return [PSCustomObject]$forecast
}

function Get-PortUtilizationForecast {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$UtilizationData,

        [string]$UtilizationProperty = 'UtilizationPercent',

        [string]$TimestampProperty = 'Timestamp',

        [int]$ForecastDays,

        [double]$WarningThreshold,

        [double]$CriticalThreshold
    )

    if (-not $ForecastDays) { $ForecastDays = $script:HealthConfig.ForecastHorizonDays }
    if (-not $WarningThreshold) { $WarningThreshold = $script:HealthConfig.HealthCheckThresholds.PortUtilizationWarning }
    if (-not $CriticalThreshold) { $CriticalThreshold = $script:HealthConfig.HealthCheckThresholds.PortUtilizationCritical }

    $forecast = Get-CapacityForecast `
        -DataPoints $UtilizationData `
        -ValueProperty $UtilizationProperty `
        -TimestampProperty $TimestampProperty `
        -ForecastDays $ForecastDays `
        -CapacityLimit $CriticalThreshold

    $forecast | Add-Member -NotePropertyName 'WarningThreshold' -NotePropertyValue $WarningThreshold
    $forecast | Add-Member -NotePropertyName 'CriticalThreshold' -NotePropertyValue $CriticalThreshold

    # Find when warning threshold is reached
    $warningDay = $forecast.Projections | Where-Object { $_.ProjectedValue -ge $WarningThreshold } | Select-Object -First 1
    if ($warningDay) {
        $forecast | Add-Member -NotePropertyName 'DaysToWarning' -NotePropertyValue $warningDay.Day
        $forecast | Add-Member -NotePropertyName 'WarningDate' -NotePropertyValue $warningDay.Date
    }

    return $forecast
}
#endregion

#region Health Check Automation
function Invoke-FleetHealthCheck {
    [CmdletBinding()]
    param(
        [string]$DataPath,
        [string[]]$Sites,
        [hashtable]$Thresholds,
        [switch]$IncludeDetails
    )

    if (-not $Thresholds) {
        $Thresholds = $script:HealthConfig.HealthCheckThresholds
    }

    $result = @{
        Timestamp = [datetime]::UtcNow.ToString('o')
        OverallStatus = 'Healthy'
        Checks = [System.Collections.Generic.List[object]]::new()
        Summary = @{
            Total = 0
            Passed = 0
            Warning = 0
            Critical = 0
        }
    }

    # Check: Device Availability
    $deviceCheck = @{
        Name = 'DeviceAvailability'
        Status = 'Pass'
        Message = ''
        Details = $null
    }

    try {
        $summary = Get-FleetHealthSummary -DataPath $DataPath -Sites $Sites
        $downCount = if ($summary.DevicesByStatus['Down']) { $summary.DevicesByStatus['Down'] } else { 0 }
        $totalDevices = $summary.TotalDevices

        if ($totalDevices -gt 0) {
            $downPercent = ($downCount / $totalDevices) * 100

            if ($downPercent -gt 10) {
                $deviceCheck.Status = 'Critical'
                $deviceCheck.Message = "$downCount of $totalDevices devices are down ($([math]::Round($downPercent, 1))%)"
            } elseif ($downPercent -gt 5) {
                $deviceCheck.Status = 'Warning'
                $deviceCheck.Message = "$downCount of $totalDevices devices are down ($([math]::Round($downPercent, 1))%)"
            } else {
                $deviceCheck.Message = "All devices healthy ($totalDevices total, $downCount down)"
            }

            if ($IncludeDetails) {
                $deviceCheck.Details = $summary
            }
        } else {
            $deviceCheck.Status = 'Warning'
            $deviceCheck.Message = 'No device data available'
        }
    } catch {
        $deviceCheck.Status = 'Warning'
        $deviceCheck.Message = "Check failed: $($_.Exception.Message)"
    }

    $result.Checks.Add($deviceCheck)
    $result.Summary.Total++
    $result.Summary[$deviceCheck.Status -eq 'Pass' ? 'Passed' : $deviceCheck.Status]++

    # Check: Database Health
    $dbCheck = @{
        Name = 'DatabaseHealth'
        Status = 'Pass'
        Message = 'Database connectivity check'
        Details = $null
    }

    $dbModule = Get-Module -Name 'DatabaseConcurrencyModule' -ErrorAction SilentlyContinue
    if ($dbModule) {
        try {
            $projectRoot = Split-Path -Parent $PSScriptRoot
            $dataPath = Join-Path $projectRoot 'Data'
            $databases = Get-ChildItem -Path $dataPath -Filter '*.accdb' -Recurse -ErrorAction SilentlyContinue

            $unhealthy = 0
            foreach ($db in $databases) {
                $health = Test-DatabaseHealth -DatabasePath $db.FullName -ErrorAction SilentlyContinue
                if ($health -and -not $health.Healthy) {
                    $unhealthy++
                }
            }

            if ($unhealthy -gt 0) {
                $dbCheck.Status = 'Warning'
                $dbCheck.Message = "$unhealthy database(s) have health issues"
            } else {
                $dbCheck.Message = "All $($databases.Count) databases healthy"
            }
        } catch {
            $dbCheck.Status = 'Warning'
            $dbCheck.Message = "Database check failed: $($_.Exception.Message)"
        }
    } else {
        $dbCheck.Message = 'DatabaseConcurrencyModule not loaded - skipped'
    }

    $result.Checks.Add($dbCheck)
    $result.Summary.Total++
    $result.Summary[$dbCheck.Status -eq 'Pass' ? 'Passed' : $dbCheck.Status]++

    # Check: Telemetry Health
    $telemetryCheck = @{
        Name = 'TelemetryHealth'
        Status = 'Pass'
        Message = 'Telemetry validation'
        Details = $null
    }

    $schemaModule = Get-Module -Name 'TelemetrySchemaModule' -ErrorAction SilentlyContinue
    if ($schemaModule) {
        try {
            $projectRoot = Split-Path -Parent $PSScriptRoot
            $telemetryDir = Join-Path $projectRoot 'Logs\IngestionMetrics'
            $todayFile = Join-Path $telemetryDir "$(Get-Date -Format 'yyyy-MM-dd').json"

            if (Test-Path $todayFile) {
                $validation = Test-TelemetryFile -Path $todayFile
                if ($validation.ValidationRate -lt 95) {
                    $telemetryCheck.Status = 'Warning'
                    $telemetryCheck.Message = "Telemetry validation rate: $($validation.ValidationRate)%"
                } else {
                    $telemetryCheck.Message = "Telemetry validation rate: $($validation.ValidationRate)% ($($validation.TotalEvents) events)"
                }

                if ($IncludeDetails) {
                    $telemetryCheck.Details = $validation
                }
            } else {
                $telemetryCheck.Message = 'No telemetry file for today'
            }
        } catch {
            $telemetryCheck.Status = 'Warning'
            $telemetryCheck.Message = "Telemetry check failed: $($_.Exception.Message)"
        }
    } else {
        $telemetryCheck.Message = 'TelemetrySchemaModule not loaded - skipped'
    }

    $result.Checks.Add($telemetryCheck)
    $result.Summary.Total++
    $result.Summary[$telemetryCheck.Status -eq 'Pass' ? 'Passed' : $telemetryCheck.Status]++

    # Determine overall status
    if ($result.Summary.Critical -gt 0) {
        $result.OverallStatus = 'Critical'
    } elseif ($result.Summary.Warning -gt 0) {
        $result.OverallStatus = 'Warning'
    } else {
        $result.OverallStatus = 'Healthy'
    }

    return [PSCustomObject]$result
}

function New-ScheduledHealthCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [ValidateSet('Daily', 'Hourly', 'Weekly')]
        [string]$Schedule = 'Daily',

        [string]$OutputPath,

        [switch]$EmailOnFailure,

        [string]$EmailTo
    )

    $config = @{
        Name = $Name
        Schedule = $Schedule
        OutputPath = $OutputPath
        EmailOnFailure = $EmailOnFailure.IsPresent
        EmailTo = $EmailTo
        CreatedAt = [datetime]::UtcNow.ToString('o')
        LastRun = $null
        LastStatus = $null
    }

    # Save to config file
    $configPath = Join-Path $PSScriptRoot '..\Data\HealthCheckSchedules'
    if (-not (Test-Path $configPath)) {
        New-Item -Path $configPath -ItemType Directory -Force | Out-Null
    }

    $configFile = Join-Path $configPath "$Name.json"
    $config | ConvertTo-Json -Depth 5 | Set-Content -Path $configFile -Encoding UTF8

    return [PSCustomObject]$config
}

function Get-ScheduledHealthChecks {
    [CmdletBinding()]
    param(
        [string]$Name
    )

    $configPath = Join-Path $PSScriptRoot '..\Data\HealthCheckSchedules'
    if (-not (Test-Path $configPath)) {
        return @()
    }

    $configs = Get-ChildItem -Path $configPath -Filter '*.json' | ForEach-Object {
        try {
            Get-Content $_.FullName -Raw | ConvertFrom-Json
        } catch { }
    }

    if ($Name) {
        return $configs | Where-Object { $_.Name -eq $Name }
    }

    return $configs
}
#endregion

#region Built-in Report Templates
# Register default templates
Register-FleetReportTemplate -Name 'DailyHealthSummary' -Title 'Daily Fleet Health Summary' -Description 'Overview of fleet health metrics for the day' -DefaultSchedule 'Daily' -Generator {
    param($Parameters)

    $summary = Get-FleetHealthSummary
    $healthCheck = Invoke-FleetHealthCheck

    return @{
        Summary = $summary
        HealthChecks = $healthCheck.Checks
        OverallStatus = $healthCheck.OverallStatus
    }
}

Register-FleetReportTemplate -Name 'WeeklyTrendReport' -Title 'Weekly Trend Analysis Report' -Description 'Trend analysis of key metrics over the past week' -DefaultSchedule 'Weekly' -Generator {
    param($Parameters)

    return @{
        ReportPeriod = '7 days'
        GeneratedAt = [datetime]::UtcNow.ToString('o')
        Note = 'Trend data requires metric collection to be configured'
    }
}
#endregion

#region Exports
Export-ModuleMember -Function @(
    'Set-FleetHealthConfig',
    'Get-FleetHealthConfig',
    'Get-FleetHealthSummary',
    'Get-FleetStatusDistribution',
    'Register-FleetReportTemplate',
    'Get-FleetReportTemplates',
    'New-FleetReport',
    'Get-RollingBaseline',
    'Test-AnomalyDetection',
    'Find-MetricAnomalies',
    'Get-MetricTrend',
    'Get-TrendAnalysisReport',
    'Get-CapacityForecast',
    'Get-PortUtilizationForecast',
    'Invoke-FleetHealthCheck',
    'New-ScheduledHealthCheck',
    'Get-ScheduledHealthChecks'
)
#endregion
