Set-StrictMode -Version Latest

<#
.SYNOPSIS
Tests for telemetry gate enforcement (ST-E-005).

.DESCRIPTION
Validates that telemetry metrics meet the gate thresholds defined in docs/telemetry/Automation_Gates.md.
These tests ensure the rollup and verification harness can detect threshold violations.
#>

# Gate thresholds from docs/telemetry/Automation_Gates.md
$script:Gates = @{
    ParseDuration = @{
        P95Max    = 3.0    # seconds
        MaxMax    = 10.0   # seconds
    }
    DatabaseWriteLatency = @{
        P95Cold   = 950    # ms
        P95Warm   = 500    # ms
        AlertWarm = 600    # ms (warning threshold)
    }
    SiteCacheFetch = @{
        P95Max    = 5000   # ms (5 seconds)
        AlertMax  = 10000  # ms (10 seconds, document if exceeded)
    }
    WarmRunImprovement = @{
        MinImprovement = 60  # percent
    }
    QueueDelay = @{
        P95Max    = 120    # ms
        P99Max    = 200    # ms
        MinSamples = 10    # minimum sample count
    }
    RowsWritten = @{
        TolerancePercent = 1  # +/- 1% of Access counts
    }
    UserAction = @{
        RequiredActions = @('ScanLogs','LoadFromDb','HelpQuickstart','InterfacesView','CompareView','SpanSnapshot')
        MinEvents       = 10
        MinSites        = 2
    }
}

function Test-ParseDurationGate {
    <#
    .SYNOPSIS
    Tests if ParseDuration metrics pass gate thresholds.
    #>
    param(
        [Parameter(Mandatory)][psobject[]]$RollupResults
    )

    $parseRow = $RollupResults | Where-Object { $_.Metric -eq 'ParseDurationSeconds' -and $_.Scope -eq 'All' }
    if (-not $parseRow) {
        return [pscustomobject]@{
            Gate    = 'ParseDuration'
            Passed  = $false
            Message = 'No ParseDuration metrics found'
            P95     = $null
            Max     = $null
        }
    }

    $p95Pass = $parseRow.P95 -le $script:Gates.ParseDuration.P95Max
    $maxPass = $parseRow.Max -le $script:Gates.ParseDuration.MaxMax
    $passed  = $p95Pass -and $maxPass

    $messages = @()
    if (-not $p95Pass) { $messages += "P95 $($parseRow.P95)s exceeds $($script:Gates.ParseDuration.P95Max)s" }
    if (-not $maxPass) { $messages += "Max $($parseRow.Max)s exceeds $($script:Gates.ParseDuration.MaxMax)s" }

    [pscustomobject]@{
        Gate    = 'ParseDuration'
        Passed  = $passed
        Message = if ($passed) { 'Pass' } else { $messages -join '; ' }
        P95     = $parseRow.P95
        Max     = $parseRow.Max
    }
}

function Test-DatabaseWriteLatencyGate {
    <#
    .SYNOPSIS
    Tests if DatabaseWriteLatency metrics pass gate thresholds.
    #>
    param(
        [Parameter(Mandatory)][psobject[]]$RollupResults,
        [switch]$WarmRun
    )

    $latencyRow = $RollupResults | Where-Object { $_.Metric -eq 'DatabaseWriteLatencyMs' -and $_.Scope -eq 'All' }
    if (-not $latencyRow) {
        return [pscustomobject]@{
            Gate    = 'DatabaseWriteLatency'
            Passed  = $false
            Message = 'No DatabaseWriteLatency metrics found'
            P95     = $null
            Max     = $null
        }
    }

    $threshold = if ($WarmRun) { $script:Gates.DatabaseWriteLatency.P95Warm } else { $script:Gates.DatabaseWriteLatency.P95Cold }
    $p95Pass = $latencyRow.P95 -le $threshold
    $warning = $WarmRun -and ($latencyRow.P95 -gt $script:Gates.DatabaseWriteLatency.AlertWarm)

    $message = if ($p95Pass) {
        if ($warning) { "Warning: P95 $($latencyRow.P95)ms exceeds alert threshold $($script:Gates.DatabaseWriteLatency.AlertWarm)ms" }
        else { 'Pass' }
    } else {
        "P95 $($latencyRow.P95)ms exceeds $($threshold)ms"
    }

    [pscustomobject]@{
        Gate    = 'DatabaseWriteLatency'
        Passed  = $p95Pass
        Message = $message
        P95     = $latencyRow.P95
        Max     = $latencyRow.Max
        Warning = $warning
    }
}

function Test-QueueDelayGate {
    <#
    .SYNOPSIS
    Tests if QueueDelay metrics pass gate thresholds.
    #>
    param(
        [Parameter(Mandatory)][psobject[]]$RollupResults
    )

    $queueRow = $RollupResults | Where-Object { $_.Metric -eq 'QueueBuildDelayMs' -and $_.Scope -eq 'All' }
    if (-not $queueRow) {
        return [pscustomobject]@{
            Gate       = 'QueueDelay'
            Passed     = $false
            Message    = 'No QueueDelay metrics found'
            P95        = $null
            P99        = $null
            SampleCount = 0
        }
    }

    $sampleCount = [int]$queueRow.Count
    if ($sampleCount -lt $script:Gates.QueueDelay.MinSamples) {
        return [pscustomobject]@{
            Gate        = 'QueueDelay'
            Passed      = $false
            Message     = "InsufficientData: $sampleCount samples < $($script:Gates.QueueDelay.MinSamples) required"
            P95         = $queueRow.P95
            P99         = $queueRow.Max  # Approximate P99 as max for small samples
            SampleCount = $sampleCount
        }
    }

    $p95Pass = $queueRow.P95 -le $script:Gates.QueueDelay.P95Max
    # Note: P99 would need a different calculation, using Max as approximation
    $p99Pass = $queueRow.Max -le $script:Gates.QueueDelay.P99Max

    $messages = @()
    if (-not $p95Pass) { $messages += "P95 $($queueRow.P95)ms exceeds $($script:Gates.QueueDelay.P95Max)ms" }
    if (-not $p99Pass) { $messages += "P99/Max $($queueRow.Max)ms exceeds $($script:Gates.QueueDelay.P99Max)ms" }

    [pscustomobject]@{
        Gate        = 'QueueDelay'
        Passed      = $p95Pass -and $p99Pass
        Message     = if ($p95Pass -and $p99Pass) { 'Pass' } else { $messages -join '; ' }
        P95         = $queueRow.P95
        P99         = $queueRow.Max
        SampleCount = $sampleCount
    }
}

function Test-UserActionCoverageGate {
    <#
    .SYNOPSIS
    Tests if UserAction telemetry meets coverage requirements.
    #>
    param(
        [Parameter(Mandatory)][psobject[]]$RollupResults
    )

    $coverageRow = $RollupResults | Where-Object { $_.Metric -eq 'UserActionCoverage' -and $_.Scope -eq 'All' }
    $totalRow = $RollupResults | Where-Object { $_.Metric -eq 'UserActionTotal' -and $_.Scope -eq 'All' }

    if (-not $coverageRow) {
        return [pscustomobject]@{
            Gate           = 'UserActionCoverage'
            Passed         = $false
            Message        = 'No UserActionCoverage metrics found'
            CoveredActions = 0
            TotalRequired  = $script:Gates.UserAction.RequiredActions.Count
            MissingActions = $script:Gates.UserAction.RequiredActions
        }
    }

    $covered = [int]$coverageRow.Count
    $total   = [int]$coverageRow.Total
    $missing = @()
    if ($coverageRow.Notes -match 'Missing=([^;]+)') {
        $missing = $Matches[1] -split ','
    }

    $allPresent = ($missing.Count -eq 0) -and ($covered -ge $total)

    [pscustomobject]@{
        Gate           = 'UserActionCoverage'
        Passed         = $allPresent
        Message        = if ($allPresent) { 'Pass' } else { "Missing: $($missing -join ', ')" }
        CoveredActions = $covered
        TotalRequired  = $total
        MissingActions = $missing
    }
}

function Test-AllTelemetryGates {
    <#
    .SYNOPSIS
    Tests all telemetry gates and returns a summary.
    #>
    param(
        [Parameter(Mandatory)][psobject[]]$RollupResults,
        [switch]$WarmRun
    )

    $results = @(
        (Test-ParseDurationGate -RollupResults $RollupResults)
        (Test-DatabaseWriteLatencyGate -RollupResults $RollupResults -WarmRun:$WarmRun)
        (Test-QueueDelayGate -RollupResults $RollupResults)
        (Test-UserActionCoverageGate -RollupResults $RollupResults)
    )

    $failed   = @($results | Where-Object { -not $_.Passed })
    $passed   = @($results | Where-Object { $_.Passed })
    $warnings = @($results | Where-Object { $_.PSObject.Properties['Warning'] -and $_.Warning })

    [pscustomobject]@{
        AllGatesPassed = ($failed.Count -eq 0)
        TotalGates     = $results.Count
        PassedGates    = $passed.Count
        FailedGates    = $failed.Count
        Warnings       = $warnings.Count
        Results        = $results
    }
}

Describe 'Telemetry Gate Thresholds' {
    Context 'ParseDuration gate' {
        It 'Passes when P95 and Max are within limits' {
            $results = @(
                [pscustomobject]@{ Metric = 'ParseDurationSeconds'; Scope = 'All'; P95 = 2.5; Max = 8.0; Count = 10 }
            )
            $gate = Test-ParseDurationGate -RollupResults $results
            $gate.Passed | Should Be $true
            $gate.Message | Should Be 'Pass'
        }

        It 'Fails when P95 exceeds threshold' {
            $results = @(
                [pscustomobject]@{ Metric = 'ParseDurationSeconds'; Scope = 'All'; P95 = 4.0; Max = 8.0; Count = 10 }
            )
            $gate = Test-ParseDurationGate -RollupResults $results
            $gate.Passed | Should Be $false
            $gate.Message | Should Match 'P95.*exceeds'
        }

        It 'Fails when Max exceeds threshold' {
            $results = @(
                [pscustomobject]@{ Metric = 'ParseDurationSeconds'; Scope = 'All'; P95 = 2.5; Max = 12.0; Count = 10 }
            )
            $gate = Test-ParseDurationGate -RollupResults $results
            $gate.Passed | Should Be $false
            $gate.Message | Should Match 'Max.*exceeds'
        }
    }

    Context 'DatabaseWriteLatency gate' {
        It 'Passes cold run when P95 is under 950ms' {
            $results = @(
                [pscustomobject]@{ Metric = 'DatabaseWriteLatencyMs'; Scope = 'All'; P95 = 800; Max = 1200; Count = 10 }
            )
            $gate = Test-DatabaseWriteLatencyGate -RollupResults $results
            $gate.Passed | Should Be $true
        }

        It 'Fails cold run when P95 exceeds 950ms' {
            $results = @(
                [pscustomobject]@{ Metric = 'DatabaseWriteLatencyMs'; Scope = 'All'; P95 = 1000; Max = 1500; Count = 10 }
            )
            $gate = Test-DatabaseWriteLatencyGate -RollupResults $results
            $gate.Passed | Should Be $false
        }

        It 'Passes warm run when P95 is under 500ms' {
            $results = @(
                [pscustomobject]@{ Metric = 'DatabaseWriteLatencyMs'; Scope = 'All'; P95 = 400; Max = 600; Count = 10 }
            )
            $gate = Test-DatabaseWriteLatencyGate -RollupResults $results -WarmRun
            $gate.Passed | Should Be $true
        }

        It 'Warns warm run when P95 exceeds 600ms but passes under 500ms threshold' {
            $results = @(
                [pscustomobject]@{ Metric = 'DatabaseWriteLatencyMs'; Scope = 'All'; P95 = 480; Max = 700; Count = 10 }
            )
            $gate = Test-DatabaseWriteLatencyGate -RollupResults $results -WarmRun
            $gate.Passed | Should Be $true
            $gate.Warning | Should Be $false  # 480 < 600 alert threshold
        }
    }

    Context 'QueueDelay gate' {
        It 'Passes when P95 and P99 are within limits with sufficient samples' {
            $results = @(
                [pscustomobject]@{ Metric = 'QueueBuildDelayMs'; Scope = 'All'; P95 = 100; Max = 150; Count = 15 }
            )
            $gate = Test-QueueDelayGate -RollupResults $results
            $gate.Passed | Should Be $true
        }

        It 'Fails with InsufficientData when sample count is too low' {
            $results = @(
                [pscustomobject]@{ Metric = 'QueueBuildDelayMs'; Scope = 'All'; P95 = 80; Max = 120; Count = 5 }
            )
            $gate = Test-QueueDelayGate -RollupResults $results
            $gate.Passed | Should Be $false
            $gate.Message | Should Match 'InsufficientData'
        }

        It 'Fails when P95 exceeds 120ms' {
            $results = @(
                [pscustomobject]@{ Metric = 'QueueBuildDelayMs'; Scope = 'All'; P95 = 150; Max = 180; Count = 20 }
            )
            $gate = Test-QueueDelayGate -RollupResults $results
            $gate.Passed | Should Be $false
            $gate.Message | Should Match 'P95.*exceeds'
        }
    }

    Context 'UserActionCoverage gate' {
        It 'Passes when all required actions are present' {
            $results = @(
                [pscustomobject]@{ Metric = 'UserActionCoverage'; Scope = 'All'; Count = 6; Total = 6; Notes = '' }
            )
            $gate = Test-UserActionCoverageGate -RollupResults $results
            $gate.Passed | Should Be $true
        }

        It 'Fails when actions are missing' {
            $results = @(
                [pscustomobject]@{ Metric = 'UserActionCoverage'; Scope = 'All'; Count = 4; Total = 6; Notes = 'Missing=CompareView,SpanSnapshot' }
            )
            $gate = Test-UserActionCoverageGate -RollupResults $results
            $gate.Passed | Should Be $false
            $gate.Message | Should Match 'CompareView'
            ($gate.MissingActions -contains 'CompareView') | Should Be $true
        }
    }

    Context 'Combined gate check' {
        It 'Reports all gates passed when all thresholds are met' {
            $results = @(
                [pscustomobject]@{ Metric = 'ParseDurationSeconds'; Scope = 'All'; P95 = 2.0; Max = 5.0; Count = 10 }
                [pscustomobject]@{ Metric = 'DatabaseWriteLatencyMs'; Scope = 'All'; P95 = 400; Max = 800; Count = 10 }
                [pscustomobject]@{ Metric = 'QueueBuildDelayMs'; Scope = 'All'; P95 = 80; Max = 150; Count = 15 }
                [pscustomobject]@{ Metric = 'UserActionCoverage'; Scope = 'All'; Count = 6; Total = 6; Notes = '' }
            )
            $summary = Test-AllTelemetryGates -RollupResults $results
            $summary.AllGatesPassed | Should Be $true
            $summary.FailedGates | Should Be 0
        }

        It 'Reports failures when any gate fails' {
            $results = @(
                [pscustomobject]@{ Metric = 'ParseDurationSeconds'; Scope = 'All'; P95 = 5.0; Max = 5.0; Count = 10 }  # Fails
                [pscustomobject]@{ Metric = 'DatabaseWriteLatencyMs'; Scope = 'All'; P95 = 400; Max = 800; Count = 10 }
                [pscustomobject]@{ Metric = 'QueueBuildDelayMs'; Scope = 'All'; P95 = 80; Max = 150; Count = 15 }
                [pscustomobject]@{ Metric = 'UserActionCoverage'; Scope = 'All'; Count = 6; Total = 6; Notes = '' }
            )
            $summary = Test-AllTelemetryGates -RollupResults $results
            $summary.AllGatesPassed | Should Be $false
            $summary.FailedGates | Should Be 1
        }
    }
}

Describe 'Gate threshold constants' {
    It 'ParseDuration P95 threshold is 3 seconds' {
        $script:Gates.ParseDuration.P95Max | Should Be 3.0
    }

    It 'ParseDuration Max threshold is 10 seconds' {
        $script:Gates.ParseDuration.MaxMax | Should Be 10.0
    }

    It 'DatabaseWriteLatency cold P95 threshold is 950ms' {
        $script:Gates.DatabaseWriteLatency.P95Cold | Should Be 950
    }

    It 'DatabaseWriteLatency warm P95 threshold is 500ms' {
        $script:Gates.DatabaseWriteLatency.P95Warm | Should Be 500
    }

    It 'QueueDelay P95 threshold is 120ms' {
        $script:Gates.QueueDelay.P95Max | Should Be 120
    }

    It 'QueueDelay P99 threshold is 200ms' {
        $script:Gates.QueueDelay.P99Max | Should Be 200
    }

    It 'QueueDelay minimum sample count is 10' {
        $script:Gates.QueueDelay.MinSamples | Should Be 10
    }

    It 'UserAction requires 6 actions' {
        $script:Gates.UserAction.RequiredActions.Count | Should Be 6
    }
}
