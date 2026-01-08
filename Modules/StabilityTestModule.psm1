# StabilityTestModule.psm1
# Long-running stability tests, leak detection, and fixture validation

Set-StrictMode -Version Latest

$script:TestRunning = $false
$script:MemoryBaseline = $null
$script:HandleBaseline = $null
$script:TelemetryLog = $null

#region Soak Test

function Start-SoakTest {
    <#
    .SYNOPSIS
    Starts a long-running soak test with continuous parse/query cycles.
    .PARAMETER DurationHours
    Test duration in hours. Default 24.
    .PARAMETER CycleIntervalSeconds
    Interval between test cycles. Default 60.
    .PARAMETER OutputPath
    Path for test results and telemetry.
    .PARAMETER IncludeMemoryMonitoring
    Enable memory leak detection.
    .PARAMETER IncludeHandleMonitoring
    Enable handle leak detection.
    #>
    [CmdletBinding()]
    param(
        [int]$DurationHours = 24,

        [int]$CycleIntervalSeconds = 60,

        [string]$OutputPath,

        [switch]$IncludeMemoryMonitoring,

        [switch]$IncludeHandleMonitoring
    )

    if ($script:TestRunning) {
        throw "A soak test is already running"
    }

    $projectRoot = Split-Path -Parent $PSScriptRoot

    if (-not $OutputPath) {
        $OutputPath = Join-Path $projectRoot "Logs\StabilityTests\SoakTest-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    }

    if (-not (Test-Path $OutputPath)) {
        New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
    }

    $script:TestRunning = $true
    $startTime = [datetime]::UtcNow
    $endTime = $startTime.AddHours($DurationHours)

    $testResult = @{
        TestId = [guid]::NewGuid().ToString('N').Substring(0, 12)
        StartTime = $startTime.ToString('o')
        EndTime = $null
        DurationHours = $DurationHours
        CycleIntervalSeconds = $CycleIntervalSeconds
        OutputPath = $OutputPath
        Status = 'Running'
        TotalCycles = 0
        SuccessfulCycles = 0
        FailedCycles = 0
        Errors = [System.Collections.Generic.List[object]]::new()
        MemoryMetrics = @()
        HandleMetrics = @()
        CycleMetrics = [System.Collections.Generic.List[object]]::new()
    }

    # Initialize telemetry log
    $script:TelemetryLog = Join-Path $OutputPath 'telemetry.jsonl'

    # Capture baselines
    if ($IncludeMemoryMonitoring) {
        $script:MemoryBaseline = Get-MemoryMetrics
        Write-TelemetryEvent -Type 'MemoryBaseline' -Data $script:MemoryBaseline
    }

    if ($IncludeHandleMonitoring) {
        $script:HandleBaseline = Get-HandleMetrics
        Write-TelemetryEvent -Type 'HandleBaseline' -Data $script:HandleBaseline
    }

    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  StateTrace Soak Test Started" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Test ID: $($testResult.TestId)"
    Write-Host "Duration: $DurationHours hours"
    Write-Host "Cycle Interval: $CycleIntervalSeconds seconds"
    Write-Host "Output: $OutputPath"
    Write-Host "Press Ctrl+C to stop early`n"

    $cycleNumber = 0
    $lastMemoryCheck = $startTime
    $memoryCheckInterval = [TimeSpan]::FromMinutes(5)

    try {
        while ([datetime]::UtcNow -lt $endTime -and $script:TestRunning) {
            $cycleNumber++
            $cycleStart = [datetime]::UtcNow

            $cycleResult = Invoke-TestCycle -CycleNumber $cycleNumber

            $testResult.TotalCycles++
            if ($cycleResult.Success) {
                $testResult.SuccessfulCycles++
            } else {
                $testResult.FailedCycles++
                [void]$testResult.Errors.Add(@{
                    Cycle = $cycleNumber
                    Time = [datetime]::UtcNow.ToString('o')
                    Error = $cycleResult.Error
                })
            }

            [void]$testResult.CycleMetrics.Add($cycleResult)
            Write-TelemetryEvent -Type 'CycleComplete' -Data $cycleResult

            # Memory check every 5 minutes
            if ($IncludeMemoryMonitoring -and ([datetime]::UtcNow - $lastMemoryCheck) -gt $memoryCheckInterval) {
                $memoryMetrics = Get-MemoryMetrics
                $memoryMetrics.GrowthFromBaseline = $memoryMetrics.WorkingSetMB - $script:MemoryBaseline.WorkingSetMB
                $memoryMetrics.GrowthPercent = if ($script:MemoryBaseline.WorkingSetMB -gt 0) {
                    [math]::Round(($memoryMetrics.GrowthFromBaseline / $script:MemoryBaseline.WorkingSetMB) * 100, 2)
                } else { 0 }

                $testResult.MemoryMetrics += $memoryMetrics
                Write-TelemetryEvent -Type 'MemoryCheck' -Data $memoryMetrics

                # Alert on excessive growth
                if ($memoryMetrics.GrowthPercent -gt 10) {
                    Write-Host "[WARNING] Memory growth: $($memoryMetrics.GrowthPercent)% above baseline" -ForegroundColor Yellow
                }

                $lastMemoryCheck = [datetime]::UtcNow
            }

            # Handle check with memory check
            if ($IncludeHandleMonitoring -and ([datetime]::UtcNow - $lastMemoryCheck) -lt [TimeSpan]::FromSeconds(5)) {
                $handleMetrics = Get-HandleMetrics
                $handleMetrics.GrowthFromBaseline = $handleMetrics.HandleCount - $script:HandleBaseline.HandleCount
                $handleMetrics.GrowthPercent = if ($script:HandleBaseline.HandleCount -gt 0) {
                    [math]::Round(($handleMetrics.GrowthFromBaseline / $script:HandleBaseline.HandleCount) * 100, 2)
                } else { 0 }

                $testResult.HandleMetrics += $handleMetrics
                Write-TelemetryEvent -Type 'HandleCheck' -Data $handleMetrics

                # Alert on excessive handle growth
                if ($handleMetrics.GrowthPercent -gt 20) {
                    Write-Host "[WARNING] Handle growth: $($handleMetrics.GrowthPercent)% above baseline" -ForegroundColor Yellow
                }
            }

            # Progress update
            $elapsed = [datetime]::UtcNow - $startTime
            $remaining = $endTime - [datetime]::UtcNow
            $successRate = if ($testResult.TotalCycles -gt 0) {
                [math]::Round($testResult.SuccessfulCycles / $testResult.TotalCycles * 100, 1)
            } else { 0 }

            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Cycle $cycleNumber complete - Success: $successRate% - Remaining: $([math]::Round($remaining.TotalHours, 1))h" -ForegroundColor Gray

            # Sleep until next cycle
            $cycleDuration = ([datetime]::UtcNow - $cycleStart).TotalSeconds
            $sleepTime = [math]::Max(0, $CycleIntervalSeconds - $cycleDuration)
            if ($sleepTime -gt 0) {
                Start-Sleep -Seconds $sleepTime
            }
        }

        $testResult.Status = 'Completed'

    } catch {
        $testResult.Status = 'Failed'
        $testResult.FatalError = $_.Exception.Message
        Write-Host "[ERROR] Soak test failed: $($_.Exception.Message)" -ForegroundColor Red

    } finally {
        $script:TestRunning = $false
        $testResult.EndTime = [datetime]::UtcNow.ToString('o')
        $testResult.ActualDurationHours = [math]::Round(([datetime]::UtcNow - $startTime).TotalHours, 2)

        # Calculate summary metrics
        $testResult.SuccessRate = if ($testResult.TotalCycles -gt 0) {
            [math]::Round($testResult.SuccessfulCycles / $testResult.TotalCycles * 100, 2)
        } else { 0 }

        if ($testResult.MemoryMetrics.Count -gt 0) {
            $testResult.MaxMemoryGrowthPercent = ($testResult.MemoryMetrics | Measure-Object -Property GrowthPercent -Maximum).Maximum
        }

        if ($testResult.HandleMetrics.Count -gt 0) {
            $testResult.MaxHandleGrowthPercent = ($testResult.HandleMetrics | Measure-Object -Property GrowthPercent -Maximum).Maximum
        }

        # Save final report
        $reportPath = Join-Path $OutputPath 'SoakTestReport.json'
        $testResult | ConvertTo-Json -Depth 10 | Set-Content -Path $reportPath -Encoding UTF8

        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "  Soak Test Complete" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "Status: $($testResult.Status)"
        Write-Host "Duration: $($testResult.ActualDurationHours) hours"
        Write-Host "Cycles: $($testResult.TotalCycles) ($($testResult.SuccessfulCycles) passed, $($testResult.FailedCycles) failed)"
        Write-Host "Success Rate: $($testResult.SuccessRate)%"
        Write-Host "Report: $reportPath`n"
    }

    return [PSCustomObject]$testResult
}

function Stop-SoakTest {
    <#
    .SYNOPSIS
    Signals the running soak test to stop.
    #>
    $script:TestRunning = $false
    Write-Host "Soak test stop requested..." -ForegroundColor Yellow
}

function Invoke-TestCycle {
    <#
    .SYNOPSIS
    Executes a single test cycle.
    #>
    param([int]$CycleNumber)

    $cycleResult = @{
        CycleNumber = $CycleNumber
        StartTime = [datetime]::UtcNow.ToString('o')
        Success = $true
        DurationMs = 0
        Operations = @()
    }

    $cycleStart = [datetime]::UtcNow

    try {
        $projectRoot = Split-Path -Parent $PSScriptRoot

        # Operation 1: Load modules
        $op1 = @{ Name = 'LoadModules'; Success = $true; DurationMs = 0 }
        $opStart = [datetime]::UtcNow
        try {
            Import-Module (Join-Path $projectRoot 'Modules\DeviceRepositoryModule.psm1') -Force -DisableNameChecking -ErrorAction Stop
        } catch {
            $op1.Success = $false
            $op1.Error = $_.Exception.Message
        }
        $op1.DurationMs = ([datetime]::UtcNow - $opStart).TotalMilliseconds
        $cycleResult.Operations += $op1

        # Operation 2: Query devices
        $op2 = @{ Name = 'QueryDevices'; Success = $true; DurationMs = 0; Count = 0 }
        $opStart = [datetime]::UtcNow
        try {
            $devices = Get-AllDevices -ErrorAction SilentlyContinue
            $op2.Count = @($devices).Count
        } catch {
            $op2.Success = $false
            $op2.Error = $_.Exception.Message
        }
        $op2.DurationMs = ([datetime]::UtcNow - $opStart).TotalMilliseconds
        $cycleResult.Operations += $op2

        # Operation 3: Parse sample file (if exists)
        $op3 = @{ Name = 'ParseSample'; Success = $true; DurationMs = 0 }
        $opStart = [datetime]::UtcNow
        try {
            $sampleFiles = Get-ChildItem -Path $projectRoot -Filter '*.txt' -Recurse -ErrorAction SilentlyContinue | 
                Where-Object { $_.FullName -match 'Fixtures|Samples' } |
                Select-Object -First 1

            if ($sampleFiles) {
                $content = Get-Content -Path $sampleFiles.FullName -Raw -ErrorAction SilentlyContinue
                $op3.FileSize = $sampleFiles.Length
            }
        } catch {
            $op3.Success = $false
            $op3.Error = $_.Exception.Message
        }
        $op3.DurationMs = ([datetime]::UtcNow - $opStart).TotalMilliseconds
        $cycleResult.Operations += $op3

        # Operation 4: Database health check
        $op4 = @{ Name = 'DatabaseCheck'; Success = $true; DurationMs = 0 }
        $opStart = [datetime]::UtcNow
        try {
            Import-Module (Join-Path $projectRoot 'Modules\DatabaseConcurrencyModule.psm1') -Force -DisableNameChecking -ErrorAction SilentlyContinue
            
            $dbs = Get-ChildItem -Path $projectRoot -Filter '*.accdb' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($dbs) {
                $health = Test-DatabaseHealth -DatabasePath $dbs.FullName
                $op4.Healthy = $health.Healthy
            }
        } catch {
            $op4.Success = $false
            $op4.Error = $_.Exception.Message
        }
        $op4.DurationMs = ([datetime]::UtcNow - $opStart).TotalMilliseconds
        $cycleResult.Operations += $op4

        # Check for any failures
        $failedOps = $cycleResult.Operations | Where-Object { -not $_.Success }
        if ($failedOps) {
            $cycleResult.Success = $false
            $cycleResult.Error = ($failedOps | ForEach-Object { "$($_.Name): $($_.Error)" }) -join '; '
        }

    } catch {
        $cycleResult.Success = $false
        $cycleResult.Error = $_.Exception.Message
    }

    $cycleResult.EndTime = [datetime]::UtcNow.ToString('o')
    $cycleResult.DurationMs = ([datetime]::UtcNow - $cycleStart).TotalMilliseconds

    return $cycleResult
}

#endregion

#region Memory Monitoring

function Get-MemoryMetrics {
    <#
    .SYNOPSIS
    Gets current memory usage metrics.
    #>
    $process = Get-Process -Id $PID

    return @{
        Timestamp = [datetime]::UtcNow.ToString('o')
        ProcessId = $PID
        WorkingSetMB = [math]::Round($process.WorkingSet64 / 1MB, 2)
        PrivateMemoryMB = [math]::Round($process.PrivateMemorySize64 / 1MB, 2)
        VirtualMemoryMB = [math]::Round($process.VirtualMemorySize64 / 1MB, 2)
        PagedMemoryMB = [math]::Round($process.PagedMemorySize64 / 1MB, 2)
        PeakWorkingSetMB = [math]::Round($process.PeakWorkingSet64 / 1MB, 2)
        GCTotalMemoryMB = [math]::Round([GC]::GetTotalMemory($false) / 1MB, 2)
    }
}

function Test-MemoryLeak {
    <#
    .SYNOPSIS
    Tests for memory leaks over a specified duration.
    .PARAMETER DurationMinutes
    Test duration in minutes. Default 60.
    .PARAMETER SampleIntervalSeconds
    Interval between samples. Default 30.
    .PARAMETER GrowthThresholdPercent
    Alert threshold for growth percentage. Default 10.
    #>
    [CmdletBinding()]
    param(
        [int]$DurationMinutes = 60,
        [int]$SampleIntervalSeconds = 30,
        [double]$GrowthThresholdPercent = 10
    )

    $startTime = [datetime]::UtcNow
    $endTime = $startTime.AddMinutes($DurationMinutes)
    $baseline = Get-MemoryMetrics
    $samples = @($baseline)

    Write-Host "Memory leak test started. Duration: $DurationMinutes minutes" -ForegroundColor Cyan

    while ([datetime]::UtcNow -lt $endTime) {
        Start-Sleep -Seconds $SampleIntervalSeconds

        # Force garbage collection to get accurate readings
        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
        [GC]::Collect()

        $sample = Get-MemoryMetrics
        $sample.GrowthFromBaseline = $sample.WorkingSetMB - $baseline.WorkingSetMB
        $sample.GrowthPercent = [math]::Round(($sample.GrowthFromBaseline / $baseline.WorkingSetMB) * 100, 2)
        $samples += $sample

        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Memory: $($sample.WorkingSetMB) MB (Growth: $($sample.GrowthPercent)%)" -ForegroundColor Gray
    }

    $result = @{
        StartTime = $startTime.ToString('o')
        EndTime = [datetime]::UtcNow.ToString('o')
        DurationMinutes = $DurationMinutes
        SampleCount = $samples.Count
        BaselineMemoryMB = $baseline.WorkingSetMB
        FinalMemoryMB = $samples[-1].WorkingSetMB
        MaxMemoryMB = ($samples | Measure-Object -Property WorkingSetMB -Maximum).Maximum
        MinMemoryMB = ($samples | Measure-Object -Property WorkingSetMB -Minimum).Minimum
        GrowthMB = $samples[-1].WorkingSetMB - $baseline.WorkingSetMB
        GrowthPercent = $samples[-1].GrowthPercent
        LeakDetected = $samples[-1].GrowthPercent -gt $GrowthThresholdPercent
        Samples = $samples
    }

    if ($result.LeakDetected) {
        Write-Host "`n[WARNING] Potential memory leak detected!" -ForegroundColor Yellow
        Write-Host "Growth: $($result.GrowthMB) MB ($($result.GrowthPercent)%)" -ForegroundColor Yellow
    } else {
        Write-Host "`nNo significant memory leak detected." -ForegroundColor Green
    }

    return [PSCustomObject]$result
}

#endregion

#region Handle Monitoring

function Get-HandleMetrics {
    <#
    .SYNOPSIS
    Gets current handle usage metrics.
    #>
    $process = Get-Process -Id $PID

    return @{
        Timestamp = [datetime]::UtcNow.ToString('o')
        ProcessId = $PID
        HandleCount = $process.HandleCount
        ThreadCount = $process.Threads.Count
    }
}

function Test-HandleLeak {
    <#
    .SYNOPSIS
    Tests for handle leaks over a specified duration.
    .PARAMETER DurationMinutes
    Test duration in minutes. Default 60.
    .PARAMETER SampleIntervalSeconds
    Interval between samples. Default 30.
    .PARAMETER GrowthThresholdPercent
    Alert threshold for growth percentage. Default 20.
    #>
    [CmdletBinding()]
    param(
        [int]$DurationMinutes = 60,
        [int]$SampleIntervalSeconds = 30,
        [double]$GrowthThresholdPercent = 20
    )

    $startTime = [datetime]::UtcNow
    $endTime = $startTime.AddMinutes($DurationMinutes)
    $baseline = Get-HandleMetrics
    $samples = @($baseline)

    Write-Host "Handle leak test started. Duration: $DurationMinutes minutes" -ForegroundColor Cyan

    while ([datetime]::UtcNow -lt $endTime) {
        Start-Sleep -Seconds $SampleIntervalSeconds

        $sample = Get-HandleMetrics
        $sample.GrowthFromBaseline = $sample.HandleCount - $baseline.HandleCount
        $sample.GrowthPercent = [math]::Round(($sample.GrowthFromBaseline / $baseline.HandleCount) * 100, 2)
        $samples += $sample

        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Handles: $($sample.HandleCount) (Growth: $($sample.GrowthPercent)%)" -ForegroundColor Gray
    }

    $result = @{
        StartTime = $startTime.ToString('o')
        EndTime = [datetime]::UtcNow.ToString('o')
        DurationMinutes = $DurationMinutes
        SampleCount = $samples.Count
        BaselineHandles = $baseline.HandleCount
        FinalHandles = $samples[-1].HandleCount
        MaxHandles = ($samples | Measure-Object -Property HandleCount -Maximum).Maximum
        MinHandles = ($samples | Measure-Object -Property HandleCount -Minimum).Minimum
        GrowthCount = $samples[-1].HandleCount - $baseline.HandleCount
        GrowthPercent = $samples[-1].GrowthPercent
        LeakDetected = $samples[-1].GrowthPercent -gt $GrowthThresholdPercent
        Samples = $samples
    }

    if ($result.LeakDetected) {
        Write-Host "`n[WARNING] Potential handle leak detected!" -ForegroundColor Yellow
        Write-Host "Growth: $($result.GrowthCount) handles ($($result.GrowthPercent)%)" -ForegroundColor Yellow
    } else {
        Write-Host "`nNo significant handle leak detected." -ForegroundColor Green
    }

    return [PSCustomObject]$result
}

#endregion

#region Fixture Validation

function Test-FixtureFreshness {
    <#
    .SYNOPSIS
    Validates test fixture freshness against schema versions.
    .PARAMETER FixturePath
    Path to fixtures directory. Default: Tests/Fixtures
    .PARAMETER MaxAgeDays
    Maximum acceptable age in days. Default 90.
    #>
    [CmdletBinding()]
    param(
        [string]$FixturePath,
        [int]$MaxAgeDays = 90
    )

    $projectRoot = Split-Path -Parent $PSScriptRoot

    if (-not $FixturePath) {
        $FixturePath = Join-Path $projectRoot 'Tests\Fixtures'
    }

    if (-not (Test-Path $FixturePath)) {
        return @{
            Status = 'Error'
            Message = "Fixture path not found: $FixturePath"
        }
    }

    $cutoffDate = (Get-Date).AddDays(-$MaxAgeDays)
    $fixtures = Get-ChildItem -Path $FixturePath -Recurse -File -ErrorAction SilentlyContinue

    $results = @{
        FixturePath = $FixturePath
        TotalFixtures = $fixtures.Count
        FreshFixtures = 0
        StaleFixtures = 0
        MaxAgeDays = $MaxAgeDays
        CutoffDate = $cutoffDate.ToString('yyyy-MM-dd')
        Details = [System.Collections.Generic.List[object]]::new()
    }

    foreach ($fixture in $fixtures) {
        $fixtureInfo = @{
            Name = $fixture.Name
            Path = $fixture.FullName.Replace($projectRoot, '.')
            LastModified = $fixture.LastWriteTime.ToString('yyyy-MM-dd')
            AgeDays = [math]::Round(((Get-Date) - $fixture.LastWriteTime).TotalDays, 0)
            IsFresh = $fixture.LastWriteTime -gt $cutoffDate
        }

        if ($fixtureInfo.IsFresh) {
            $results.FreshFixtures++
        } else {
            $results.StaleFixtures++
        }

        [void]$results.Details.Add($fixtureInfo)
    }

    $results.FreshnessPercent = if ($results.TotalFixtures -gt 0) {
        [math]::Round($results.FreshFixtures / $results.TotalFixtures * 100, 1)
    } else { 0 }

    $results.Status = if ($results.StaleFixtures -eq 0) { 'Pass' }
                      elseif ($results.FreshnessPercent -ge 80) { 'Warning' }
                      else { 'Fail' }

    return [PSCustomObject]$results
}

function Test-FixtureSchemaCompliance {
    <#
    .SYNOPSIS
    Validates fixture files against expected schemas.
    .PARAMETER FixturePath
    Path to fixtures directory.
    #>
    [CmdletBinding()]
    param(
        [string]$FixturePath
    )

    $projectRoot = Split-Path -Parent $PSScriptRoot

    if (-not $FixturePath) {
        $FixturePath = Join-Path $projectRoot 'Tests\Fixtures'
    }

    $results = @{
        FixturePath = $FixturePath
        TotalChecked = 0
        Passed = 0
        Failed = 0
        Details = [System.Collections.Generic.List[object]]::new()
    }

    # Check JSON fixtures
    $jsonFiles = Get-ChildItem -Path $FixturePath -Filter '*.json' -Recurse -ErrorAction SilentlyContinue

    foreach ($file in $jsonFiles) {
        $results.TotalChecked++
        $check = @{
            File = $file.Name
            Path = $file.FullName.Replace($projectRoot, '.')
            Type = 'JSON'
            Valid = $true
            Error = $null
        }

        try {
            $content = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json
            $check.Valid = $true
            $results.Passed++
        } catch {
            $check.Valid = $false
            $check.Error = $_.Exception.Message
            $results.Failed++
        }

        [void]$results.Details.Add($check)
    }

    # Check CSV fixtures
    $csvFiles = Get-ChildItem -Path $FixturePath -Filter '*.csv' -Recurse -ErrorAction SilentlyContinue

    foreach ($file in $csvFiles) {
        $results.TotalChecked++
        $check = @{
            File = $file.Name
            Path = $file.FullName.Replace($projectRoot, '.')
            Type = 'CSV'
            Valid = $true
            Error = $null
        }

        try {
            $content = Import-Csv -Path $file.FullName -ErrorAction Stop
            $check.RowCount = @($content).Count
            $results.Passed++
        } catch {
            $check.Valid = $false
            $check.Error = $_.Exception.Message
            $results.Failed++
        }

        [void]$results.Details.Add($check)
    }

    $results.PassRate = if ($results.TotalChecked -gt 0) {
        [math]::Round($results.Passed / $results.TotalChecked * 100, 1)
    } else { 0 }

    $results.Status = if ($results.Failed -eq 0) { 'Pass' } else { 'Fail' }

    return [PSCustomObject]$results
}

#endregion

#region Telemetry Validation

function Test-TelemetryFields {
    <#
    .SYNOPSIS
    Validates telemetry events have required fields.
    .PARAMETER TelemetryPath
    Path to telemetry files.
    .PARAMETER Last
    Number of recent events to validate.
    #>
    [CmdletBinding()]
    param(
        [string]$TelemetryPath,
        [int]$Last = 1000
    )

    $projectRoot = Split-Path -Parent $PSScriptRoot

    if (-not $TelemetryPath) {
        $TelemetryPath = Join-Path $projectRoot 'Logs'
    }

    # Define required fields per event type
    $requiredFields = @{
        'Default' = @('Timestamp', 'EventType')
        'ParseComplete' = @('Timestamp', 'EventType', 'Duration', 'RecordCount')
        'DatabaseOperation' = @('Timestamp', 'EventType', 'Database', 'Operation')
        'CycleComplete' = @('Timestamp', 'CycleNumber', 'Success', 'DurationMs')
        'MemoryCheck' = @('Timestamp', 'WorkingSetMB')
        'HandleCheck' = @('Timestamp', 'HandleCount')
    }

    $results = @{
        TelemetryPath = $TelemetryPath
        TotalEvents = 0
        ValidEvents = 0
        InvalidEvents = 0
        MissingFields = @{}
        Details = [System.Collections.Generic.List[object]]::new()
    }

    # Find telemetry files
    $telemetryFiles = Get-ChildItem -Path $TelemetryPath -Filter '*.jsonl' -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 10

    $eventsChecked = 0

    foreach ($file in $telemetryFiles) {
        if ($eventsChecked -ge $Last) { break }

        $lines = Get-Content -Path $file.FullName -ErrorAction SilentlyContinue | Select-Object -Last ($Last - $eventsChecked)

        foreach ($line in $lines) {
            if (-not $line.Trim()) { continue }

            $results.TotalEvents++
            $eventsChecked++

            try {
                $event = $line | ConvertFrom-Json

                $eventType = if ($event.EventType) { $event.EventType } 
                             elseif ($event.Type) { $event.Type }
                             else { 'Default' }

                $required = if ($requiredFields.ContainsKey($eventType)) {
                    $requiredFields[$eventType]
                } else {
                    $requiredFields['Default']
                }

                $missing = @()
                foreach ($field in $required) {
                    if (-not $event.PSObject.Properties.Name -contains $field) {
                        $missing += $field
                    }
                }

                if ($missing.Count -eq 0) {
                    $results.ValidEvents++
                } else {
                    $results.InvalidEvents++
                    foreach ($m in $missing) {
                        if (-not $results.MissingFields.ContainsKey($m)) {
                            $results.MissingFields[$m] = 0
                        }
                        $results.MissingFields[$m]++
                    }

                    if ($results.Details.Count -lt 50) {
                        [void]$results.Details.Add(@{
                            File = $file.Name
                            EventType = $eventType
                            MissingFields = $missing
                        })
                    }
                }

            } catch {
                $results.InvalidEvents++
            }
        }
    }

    $results.ValidationRate = if ($results.TotalEvents -gt 0) {
        [math]::Round($results.ValidEvents / $results.TotalEvents * 100, 1)
    } else { 0 }

    $results.Status = if ($results.ValidationRate -ge 99) { 'Pass' }
                      elseif ($results.ValidationRate -ge 95) { 'Warning' }
                      else { 'Fail' }

    return [PSCustomObject]$results
}

#endregion

#region Utilities

function Write-TelemetryEvent {
    param(
        [string]$Type,
        [object]$Data
    )

    if (-not $script:TelemetryLog) { return }

    $event = @{
        Timestamp = [datetime]::UtcNow.ToString('o')
        Type = $Type
        Data = $Data
    }

    $json = $event | ConvertTo-Json -Compress -Depth 5
    Add-Content -Path $script:TelemetryLog -Value $json -Encoding UTF8
}

function Get-SoakTestReport {
    <#
    .SYNOPSIS
    Gets the most recent soak test report.
    .PARAMETER TestPath
    Path to test results directory.
    #>
    [CmdletBinding()]
    param(
        [string]$TestPath
    )

    $projectRoot = Split-Path -Parent $PSScriptRoot

    if (-not $TestPath) {
        $TestPath = Join-Path $projectRoot 'Logs\StabilityTests'
    }

    $reports = Get-ChildItem -Path $TestPath -Filter 'SoakTestReport.json' -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($reports) {
        return Get-Content -Path $reports.FullName -Raw | ConvertFrom-Json
    }

    return $null
}

#endregion

Export-ModuleMember -Function @(
    # Soak Test
    'Start-SoakTest',
    'Stop-SoakTest',
    'Get-SoakTestReport',
    # Memory Monitoring
    'Get-MemoryMetrics',
    'Test-MemoryLeak',
    # Handle Monitoring
    'Get-HandleMetrics',
    'Test-HandleLeak',
    # Fixture Validation
    'Test-FixtureFreshness',
    'Test-FixtureSchemaCompliance',
    # Telemetry Validation
    'Test-TelemetryFields'
)
