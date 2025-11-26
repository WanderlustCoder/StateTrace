Set-StrictMode -Version Latest

function Get-PercentileValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [double[]]$Values,
        [Parameter(Mandatory = $true)]
        [double]$Percentile
    )

    if (-not $Values -or $Values.Length -eq 0) {
        return $null
    }

    if ($Percentile -lt 0) { $Percentile = 0 }
    if ($Percentile -gt 100) { $Percentile = 100 }

    $sorted = $Values | Sort-Object
    $count = $sorted.Count
    if ($count -eq 1) {
        return [double]$sorted[0]
    }

    $position = ($Percentile / 100) * ($count - 1)
    $lowerIndex = [math]::Floor($position)
    $upperIndex = [math]::Ceiling($position)
    if ($lowerIndex -eq $upperIndex) {
        return [double]$sorted[$lowerIndex]
    }

    $lowerValue = [double]$sorted[$lowerIndex]
    $upperValue = [double]$sorted[$upperIndex]
    $fraction = $position - $lowerIndex
    return $lowerValue + (($upperValue - $lowerValue) * $fraction)
}

function Test-WarmRunRegressionSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Summary,

        [double]$MinimumImprovementPercent = 25,
        [double]$MinimumCacheHitRatioPercent = 99,
        [int]$MaximumWarmCacheMissCount = 0,
        [int]$MaximumSignatureMissCount = 0,
        [int]$MaximumSignatureRewriteTotal = 0,
        [double]$MaximumWarmAverageDeltaMs = 0
    )

    $messages = New-Object System.Collections.Generic.List[string]
    $pass = $true

    if ($null -eq $Summary) {
        $messages.Add('Warm-run regression summary is null.')
        return [pscustomobject]@{
            Pass      = $false
            Messages  = $messages.ToArray()
            Summary   = $null
            Violations = @('SummaryMissing')
        }
    }

    $violations = New-Object System.Collections.Generic.List[string]

    $improvementPercent = $null
    if ($Summary.PSObject.Properties.Name -contains 'ImprovementPercent') {
        try {
            $improvementPercent = [double]$Summary.ImprovementPercent
        } catch {
            $improvementPercent = $null
        }
    }

    $improvementDisplay = if ($improvementPercent -eq $null) { 'null' } else { ('{0:N3}' -f $improvementPercent) }
    if ($improvementPercent -eq $null -or $improvementPercent -lt $MinimumImprovementPercent) {
        $pass = $false
        $violations.Add('ImprovementPercent')
        $messages.Add(("Warm-run improvement percent {0} is below required {1}." -f $improvementDisplay, $MinimumImprovementPercent))
    }

    $warmAvg = $null
    $coldAvg = $null
    if ($Summary.PSObject.Properties.Name -contains 'WarmInterfaceCallAvgMs') {
        try { $warmAvg = [double]$Summary.WarmInterfaceCallAvgMs } catch { $warmAvg = $null }
    }
    if ($Summary.PSObject.Properties.Name -contains 'ColdInterfaceCallAvgMs') {
        try { $coldAvg = [double]$Summary.ColdInterfaceCallAvgMs } catch { $coldAvg = $null }
    }
    if ($warmAvg -ne $null -and $coldAvg -ne $null -and $MaximumWarmAverageDeltaMs -ge 0) {
        $delta = $warmAvg - $coldAvg
        if ($delta -gt $MaximumWarmAverageDeltaMs) {
            $pass = $false
            $violations.Add('WarmAverageDelta')
            $messages.Add(("Warm-run average {0:N3} ms exceeds cold average {1:N3} ms by {2:N3} ms (allowed {3:N3} ms)." -f `
                    $warmAvg, $coldAvg, $delta, $MaximumWarmAverageDeltaMs))
        }
    }

    $hitCount = 0
    $missCount = 0
    if ($Summary.PSObject.Properties.Name -contains 'WarmCacheProviderHitCount') {
        try { $hitCount = [int]$Summary.WarmCacheProviderHitCount } catch { $hitCount = 0 }
    }
    if ($Summary.PSObject.Properties.Name -contains 'WarmCacheProviderMissCount') {
        try { $missCount = [int]$Summary.WarmCacheProviderMissCount } catch { $missCount = 0 }
    }

    if ($missCount -gt $MaximumWarmCacheMissCount) {
        $pass = $false
        $violations.Add('WarmCacheMissCount')
        $messages.Add(("Warm cache miss count {0} exceeds allowed {1}." -f $missCount, $MaximumWarmCacheMissCount))
    }

    $hitRatio = $null
    if ($Summary.PSObject.Properties.Name -contains 'WarmCacheHitRatioPercent') {
        try { $hitRatio = [double]$Summary.WarmCacheHitRatioPercent } catch { $hitRatio = $null }
    }
    if ($hitRatio -eq $null -and ($hitCount -gt 0 -or $missCount -gt 0)) {
        $total = $hitCount + $missCount
        if ($total -gt 0) {
            $hitRatio = ($hitCount / $total) * 100
        }
    }

    $hitRatioDisplay = if ($hitRatio -eq $null) { 'null' } else { ('{0:N3}' -f $hitRatio) }
    if ($hitRatio -eq $null -or $hitRatio -lt $MinimumCacheHitRatioPercent) {
        $pass = $false
        $violations.Add('HitRatio')
        $messages.Add(("Warm cache hit ratio {0} is below required {1}." -f $hitRatioDisplay, $MinimumCacheHitRatioPercent))
    }

    $signatureMiss = 0
    if ($Summary.PSObject.Properties.Name -contains 'WarmSignatureMatchMissCount') {
        try { $signatureMiss = [int]$Summary.WarmSignatureMatchMissCount } catch { $signatureMiss = 0 }
    }
    if ($signatureMiss -gt $MaximumSignatureMissCount) {
        $pass = $false
        $violations.Add('SignatureMissCount')
        $messages.Add(("Warm signature miss count {0} exceeds allowed {1}." -f $signatureMiss, $MaximumSignatureMissCount))
    }

    $signatureRewrite = 0
    if ($Summary.PSObject.Properties.Name -contains 'WarmSignatureRewriteTotal') {
        try { $signatureRewrite = [int]$Summary.WarmSignatureRewriteTotal } catch { $signatureRewrite = 0 }
    }
    if ($signatureRewrite -gt $MaximumSignatureRewriteTotal) {
        $pass = $false
        $violations.Add('SignatureRewriteTotal')
        $messages.Add(("Warm signature rewrite total {0} exceeds allowed {1}." -f $signatureRewrite, $MaximumSignatureRewriteTotal))
    }

    $thresholds = [pscustomobject]@{
        MinimumImprovementPercent      = $MinimumImprovementPercent
        MinimumCacheHitRatioPercent    = $MinimumCacheHitRatioPercent
        MaximumWarmCacheMissCount      = $MaximumWarmCacheMissCount
        MaximumSignatureMissCount      = $MaximumSignatureMissCount
        MaximumSignatureRewriteTotal   = $MaximumSignatureRewriteTotal
        MaximumWarmAverageDeltaMs      = $MaximumWarmAverageDeltaMs
    }

    return [pscustomobject]@{
        Pass       = $pass
        Messages   = $messages.ToArray()
        Summary    = $Summary
        Violations = $violations.ToArray()
        Thresholds = $thresholds
    }
}

function Test-SharedCacheSummaryCoverage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Summary,
        [int]$MinimumSiteCount = 1,
        [int]$MinimumHostCount = 1,
        [int]$MinimumTotalRowCount = 1,
        [string[]]$RequiredSites = @()
    )

    $messages = New-Object System.Collections.Generic.List[string]
    $violations = New-Object System.Collections.Generic.List[string]
    $entries = @()

    switch ($Summary.GetType().FullName) {
        'System.String' {
            $summaryPath = [string]$Summary
            if (-not (Test-Path -LiteralPath $summaryPath)) {
                $messages.Add(("Shared-cache summary path '{0}' does not exist." -f $summaryPath))
                $violations.Add('SummaryMissing')
                return [pscustomobject]@{
                    Pass         = $false
                    Messages     = $messages.ToArray()
                    Entries      = @()
                    Violations   = $violations.ToArray()
                    Statistics   = [pscustomobject]@{ SiteCount = 0; TotalHostCount = 0; TotalRowCount = 0 }
                    RequiredSitesMissing = @($RequiredSites)
                    Thresholds   = [pscustomobject]@{
                        MinimumSiteCount      = $MinimumSiteCount
                        MinimumHostCount      = $MinimumHostCount
                        MinimumTotalRowCount  = $MinimumTotalRowCount
                        RequiredSites         = $RequiredSites
                    }
                }
            }

            $raw = Get-Content -LiteralPath $summaryPath -Raw
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                try {
                    $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
                    if ($parsed -is [System.Collections.IEnumerable]) {
                        $entries = @($parsed)
                    } else {
                        $entries = @($parsed)
                    }
                } catch {
                    $messages.Add(("Failed to parse shared-cache summary '{0}': {1}" -f $summaryPath, $_.Exception.Message))
                    $violations.Add('SummaryInvalid')
                }
            } else {
                $messages.Add(("Shared-cache summary '{0}' was empty." -f $summaryPath))
                $violations.Add('SummaryEmpty')
            }
        }
        default {
            if ($Summary -is [System.Collections.IEnumerable] -and -not ($Summary -is [string])) {
                $entries = @($Summary)
            } else {
                $entries = @($Summary)
            }
        }
    }

    if (-not $entries -or $entries.Count -eq 0) {
        $messages.Add('Shared-cache summary did not contain any site entries.')
        if (-not ($violations -contains 'SummaryEmpty')) {
            $violations.Add('SummaryEmpty')
        }
        return [pscustomobject]@{
            Pass         = $false
            Messages     = $messages.ToArray()
            Entries      = @()
            Violations   = $violations.ToArray()
            Statistics   = [pscustomobject]@{ SiteCount = 0; TotalHostCount = 0; TotalRowCount = 0 }
            RequiredSitesMissing = @($RequiredSites)
            Thresholds   = [pscustomobject]@{
                MinimumSiteCount      = $MinimumSiteCount
                MinimumHostCount      = $MinimumHostCount
                MinimumTotalRowCount  = $MinimumTotalRowCount
                RequiredSites         = $RequiredSites
            }
        }
    }

    $siteSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $totalHostCount = 0
    $totalRowCount = 0

    foreach ($entry in $entries) {
        if (-not $entry) { continue }

        $site = ''
        if ($entry.PSObject.Properties.Name -contains 'Site') {
            $site = ('' + $entry.Site).Trim()
        }
        if (-not [string]::IsNullOrWhiteSpace($site)) {
            $null = $siteSet.Add($site)
        }

        if ($entry.PSObject.Properties.Name -contains 'Hosts') {
            try { $totalHostCount += [int]$entry.Hosts } catch { }
        }
        if ($entry.PSObject.Properties.Name -contains 'TotalRows') {
            try { $totalRowCount += [int]$entry.TotalRows } catch { }
        }
    }

    $pass = $true

    if ($siteSet.Count -lt $MinimumSiteCount) {
        $pass = $false
        $violations.Add('SiteCount')
        $messages.Add(("Shared-cache summary reports {0} site(s); minimum required is {1}." -f $siteSet.Count, $MinimumSiteCount))
    }

    if ($totalHostCount -lt $MinimumHostCount) {
        $pass = $false
        $violations.Add('HostCount')
        $messages.Add(("Shared-cache summary reports {0} cached host(s); minimum required is {1}." -f $totalHostCount, $MinimumHostCount))
    }

    if ($totalRowCount -lt $MinimumTotalRowCount) {
        $pass = $false
        $violations.Add('RowCount')
        $messages.Add(("Shared-cache summary reports {0} cached row(s); minimum required is {1}." -f $totalRowCount, $MinimumTotalRowCount))
    }

    $requiredMissing = @()
    if ($RequiredSites -and $RequiredSites.Count -gt 0) {
        foreach ($requiredSite in $RequiredSites) {
            if ([string]::IsNullOrWhiteSpace($requiredSite)) { continue }
            if (-not ($siteSet.Contains($requiredSite))) {
                $requiredMissing += $requiredSite
            }
        }
        if ($requiredMissing.Count -gt 0) {
            $pass = $false
            $violations.Add('RequiredSites')
            $messages.Add(("Shared-cache summary missing required sites: {0}." -f ($requiredMissing -join ', ')))
        }
    }

    $statistics = [pscustomobject]@{
        SiteCount      = $siteSet.Count
        TotalHostCount = $totalHostCount
        TotalRowCount  = $totalRowCount
    }

    $thresholds = [pscustomobject]@{
        MinimumSiteCount      = $MinimumSiteCount
        MinimumHostCount      = $MinimumHostCount
        MinimumTotalRowCount  = $MinimumTotalRowCount
        RequiredSites         = $RequiredSites
    }

    return [pscustomobject]@{
        Pass                  = $pass
        Messages              = $messages.ToArray()
        Entries               = $entries
        Violations            = $violations.ToArray()
        Statistics            = $statistics
        RequiredSitesMissing  = $requiredMissing
        Thresholds            = $thresholds
    }
}

function Test-InterfacePortQueueDelay {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Events,
        [double]$MaximumP95Ms = 120,
        [double]$MaximumP99Ms = 200,
        [int]$MinimumEventCount = 1
    )

    $messages = New-Object System.Collections.Generic.List[string]
    $violations = New-Object System.Collections.Generic.List[string]
    $pass = $true

    $totalProvided = if ($Events) { $Events.Count } else { 0 }

    if (-not $Events -or $Events.Count -lt $MinimumEventCount) {
        $messages.Add(("Only {0} InterfacePortQueueMetrics event(s) supplied (minimum required {1})." -f $totalProvided, $MinimumEventCount))
        $violations.Add('EventCount')
        return [pscustomobject]@{
            Pass        = $false
            Messages    = $messages.ToArray()
            Violations  = $violations.ToArray()
            Statistics  = [pscustomobject]@{
                SampleCount = $totalProvided
            }
            Thresholds  = [pscustomobject]@{
                MinimumEventCount      = $MinimumEventCount
                MaximumQueueDelayP95Ms = $MaximumP95Ms
                MaximumQueueDelayP99Ms = $MaximumP99Ms
            }
        }
    }

    $delayValues = New-Object System.Collections.Generic.List[double]
    $durationValues = New-Object System.Collections.Generic.List[double]

    foreach ($evt in $Events) {
        if ($null -eq $evt) { continue }

        $delay = $null
        if ($evt.PSObject.Properties.Name -contains 'QueueDelayMs') {
            try { $delay = [double]$evt.QueueDelayMs } catch { $delay = $null }
        }
        if ($delay -eq $null -and $evt.PSObject.Properties.Name -contains 'QueueBuildDelayMs') {
            try { $delay = [double]$evt.QueueBuildDelayMs } catch { $delay = $null }
        }
        if ($delay -ne $null) {
            $delayValues.Add($delay) | Out-Null
        }

        $duration = $null
        if ($evt.PSObject.Properties.Name -contains 'QueueBuildDurationMs') {
            try { $duration = [double]$evt.QueueBuildDurationMs } catch { $duration = $null }
        }
        if ($duration -eq $null -and $evt.PSObject.Properties.Name -contains 'QueueDurationMs') {
            try { $duration = [double]$evt.QueueDurationMs } catch { $duration = $null }
        }
        if ($duration -ne $null) {
            $durationValues.Add($duration) | Out-Null
        }
    }

    if ($delayValues.Count -lt $MinimumEventCount) {
        $messages.Add(("Found {0} InterfacePortQueueMetrics entries with delay data (minimum required {1})." -f $delayValues.Count, $MinimumEventCount))
        $violations.Add('EventCount')
        $pass = $false
    }

    $delayArray = $delayValues.ToArray()
    $durationArray = $durationValues.ToArray()

    $delayStats = [pscustomobject]@{
        SampleCount = $delayArray.Length
        Average     = if ($delayArray.Length -gt 0) { ($delayArray | Measure-Object -Average).Average } else { $null }
        P95         = Get-PercentileValue -Values $delayArray -Percentile 95
        P99         = Get-PercentileValue -Values $delayArray -Percentile 99
        Min         = if ($delayArray.Length -gt 0) { ($delayArray | Measure-Object -Minimum).Minimum } else { $null }
        Max         = if ($delayArray.Length -gt 0) { ($delayArray | Measure-Object -Maximum).Maximum } else { $null }
    }

    $durationStats = [pscustomobject]@{
        SampleCount = $durationArray.Length
        Average     = if ($durationArray.Length -gt 0) { ($durationArray | Measure-Object -Average).Average } else { $null }
        P95         = Get-PercentileValue -Values $durationArray -Percentile 95
        P99         = Get-PercentileValue -Values $durationArray -Percentile 99
        Min         = if ($durationArray.Length -gt 0) { ($durationArray | Measure-Object -Minimum).Minimum } else { $null }
        Max         = if ($durationArray.Length -gt 0) { ($durationArray | Measure-Object -Maximum).Maximum } else { $null }
    }

    if ($delayStats.P95 -ne $null -and $MaximumP95Ms -ge 0 -and $delayStats.P95 -gt $MaximumP95Ms) {
        $pass = $false
        $violations.Add('QueueDelayP95')
        $messages.Add(("InterfacePortQueueMetrics QueueDelay P95 {0:N3} ms exceeds allowed {1:N3} ms." -f $delayStats.P95, $MaximumP95Ms))
    }

    if ($delayStats.P99 -ne $null -and $MaximumP99Ms -ge 0 -and $delayStats.P99 -gt $MaximumP99Ms) {
        $pass = $false
        $violations.Add('QueueDelayP99')
        $messages.Add(("InterfacePortQueueMetrics QueueDelay P99 {0:N3} ms exceeds allowed {1:N3} ms." -f $delayStats.P99, $MaximumP99Ms))
    }

    return [pscustomobject]@{
        Pass       = $pass
        Messages   = $messages.ToArray()
        Violations = $violations.ToArray()
        Statistics = [pscustomobject]@{
            SampleCount         = $delayStats.SampleCount
            QueueBuildDelayMs   = $delayStats
            QueueBuildDurationMs = $durationStats
        }
        Thresholds = [pscustomobject]@{
            MinimumEventCount      = $MinimumEventCount
            MaximumQueueDelayP95Ms = $MaximumP95Ms
            MaximumQueueDelayP99Ms = $MaximumP99Ms
        }
    }
}

Export-ModuleMember -Function Test-WarmRunRegressionSummary, Test-SharedCacheSummaryCoverage, Test-InterfacePortQueueDelay
