<#
.SYNOPSIS
Executes the incremental-loading dispatcher loop without the full WPF UI so that
InterfacePortDispatchMetrics telemetry is emitted for analysis.

.DESCRIPTION
Loads the required modules, stages interface rows for the specified hostname,
and uses the current dispatcher to mimic the MainWindow batching logic.  This
drives DeviceRepositoryModule\Set-InterfacePortDispatchMetrics so telemetry can
be captured in offline/headless environments.

.PARAMETER Hostname
Target device hostname whose interface rows will be streamed through the
dispatcher harness.

.PARAMETER RunDate
Optional run date applied to staged interface rows. Defaults to the current
time.

.PARAMETER ChunkSize
Optional chunk size override when building port batches.

.PARAMETER QueueDelayWarningMs
Warning threshold (milliseconds) for `QueueBuildDelayMs`. Exceeding this still completes the harness but emits a warning.

.PARAMETER QueueDelayCriticalMs
Critical threshold (milliseconds) for `QueueBuildDelayMs`. Exceeding this throws and fails the harness.

.PARAMETER SkipQueueDelayCheck
Skips the post-run queue delay guard (not recommended).

.EXAMPLE
PS> .\Tools\Invoke-InterfaceDispatchHarness.ps1 -Hostname 'BOYO-A05-AS-05'
Stages rows for BOYO-A05-AS-05 and emits InterfacePortDispatchMetrics payloads.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Hostname,
    [datetime]$RunDate = (Get-Date),
    [int]$ChunkSize = 0,
    [double]$QueueDelayWarningMs = 120,
    [double]$QueueDelayCriticalMs = 200,
    [switch]$SkipQueueDelayCheck,
    [int]$TimeoutSeconds = 30,
    [int]$NoProgressTimeoutSeconds = 5,
    [int]$PollIntervalMilliseconds = 100
)

Set-StrictMode -Version Latest

function Write-HarnessVerbose {
    param([string]$Message)
    if ($PSBoundParameters.ContainsKey('Verbose') -or $VerbosePreference -eq 'Continue') {
        Write-Verbose $Message
    }
}

Write-HarnessVerbose ("[Harness] Loading required modules...")

Import-Module (Join-Path $PSScriptRoot '..\Modules\TelemetryModule.psm1') -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot '..\Modules\DeviceRepositoryModule.psm1') -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot '..\Modules\InterfaceModule.psm1') -ErrorAction Stop

try { Add-Type -AssemblyName PresentationFramework -ErrorAction Stop } catch { Write-Verbose "Caught exception in Invoke-InterfaceDispatchHarness.ps1: $($_.Exception.Message)" }

$cleanHost = ('' + $Hostname).Trim()
if ([string]::IsNullOrWhiteSpace($cleanHost)) {
    throw "Hostname is required."
}

Write-HarnessVerbose ("[Harness] Loading interface inventory for '{0}'." -f $cleanHost)
$interfaceRows = DeviceRepositoryModule\Get-InterfaceInfo -Hostname $cleanHost
if (-not $interfaceRows) {
    throw "No interface rows were returned for hostname '$cleanHost'."
}

$batchId = [guid]::NewGuid().ToString()
$runDateValue = $RunDate

Write-HarnessVerbose ("[Harness] Staging {0} interface rows (BatchId={1})." -f $interfaceRows.Count, $batchId)
DeviceRepositoryModule\Set-InterfacePortStreamData -Hostname $cleanHost -RunDate $runDateValue -InterfaceRows $interfaceRows -BatchId $batchId

if ($ChunkSize -gt 0) {
    DeviceRepositoryModule\Initialize-InterfacePortStream -Hostname $cleanHost -ChunkSize $ChunkSize | Out-Null
} else {
    DeviceRepositoryModule\Initialize-InterfacePortStream -Hostname $cleanHost | Out-Null
}

$dispatcher = [System.Windows.Threading.Dispatcher]::CurrentDispatcher
$collection = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'

Write-HarnessVerbose ("[Harness] Beginning dispatcher loop for '{0}'." -f $cleanHost)

$timeoutMs = [Math]::Max(1000, ($TimeoutSeconds * 1000))
$noProgressMs = if ($NoProgressTimeoutSeconds -gt 0) { [Math]::Max(1000, ($NoProgressTimeoutSeconds * 1000)) } else { 0 }
$pollMs = [Math]::Max(10, $PollIntervalMilliseconds)
$streamWatch = [System.Diagnostics.Stopwatch]::StartNew()
$lastProgressMs = 0

while ($true) {
    if ($streamWatch.ElapsedMilliseconds -ge $timeoutMs) {
        throw ("[Harness] Timed out after {0} seconds while streaming '{1}'." -f $TimeoutSeconds, $cleanHost)
    }

    $batch = DeviceRepositoryModule\Get-InterfacePortBatch -Hostname $cleanHost
    if (-not $batch) {
        $status = $null
        try { $status = DeviceRepositoryModule\Get-InterfacePortStreamStatus -Hostname $cleanHost } catch { $status = $null }
        if ($status -and $status.Completed) { break }
        if ($noProgressMs -gt 0 -and ($streamWatch.ElapsedMilliseconds - $lastProgressMs) -ge $noProgressMs) {
            throw ("[Harness] Stalled for {0} seconds without batch progress (Hostname: {1})." -f $NoProgressTimeoutSeconds, $cleanHost)
        }
        Start-Sleep -Milliseconds $pollMs
        continue
    }

    $lastProgressMs = $streamWatch.ElapsedMilliseconds
    $portItems = $batch.Ports
    if (-not ($portItems -is [System.Collections.ICollection])) {
        $portItems = @($portItems)
    }
    $batchSize = if ($portItems) { [int]$portItems.Count } else { 0 }

    $appendDurationRef = [ref]0.0
    $indicatorDurationRef = [ref]0.0

    $dispatcherStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $dispatcher.Invoke([System.Action]{
        param()
        $appendSw = [System.Diagnostics.Stopwatch]::StartNew()
        foreach ($row in $portItems) { $collection.Add($row) }
        $appendSw.Stop()
        $appendDurationRef.Value = [Math]::Round($appendSw.Elapsed.TotalMilliseconds, 3)

        $indicatorSw = [System.Diagnostics.Stopwatch]::StartNew()
        $indicatorSw.Stop()
        $indicatorDurationRef.Value = [Math]::Round($indicatorSw.Elapsed.TotalMilliseconds, 3)
    })
    $dispatcherStopwatch.Stop()

    $dispatcherDurationMs = [Math]::Round($dispatcherStopwatch.Elapsed.TotalMilliseconds, 3)
    $appendDurationMs = [double]$appendDurationRef.Value
    $indicatorDurationMs = [double]$indicatorDurationRef.Value

    DeviceRepositoryModule\Set-InterfacePortDispatchMetrics -Hostname $cleanHost -BatchId $batch.BatchId -BatchOrdinal $batch.BatchOrdinal -BatchCount $batch.BatchCount -BatchSize $batchSize -PortsDelivered $batch.PortsDelivered -TotalPorts $batch.TotalPorts -DispatcherDurationMs $dispatcherDurationMs -AppendDurationMs $appendDurationMs -IndicatorDurationMs $indicatorDurationMs

    Write-HarnessVerbose ("[Harness] Batch {0}/{1} processed (Size={2}, Dispatcher={3} ms)." -f $batch.BatchOrdinal, $batch.BatchCount, $batchSize, $dispatcherDurationMs)

    if ($batch.Completed) { break }
}

$queueMetrics = $null
try { $queueMetrics = DeviceRepositoryModule\Get-LastInterfacePortQueueMetrics } catch { $queueMetrics = $null }
DeviceRepositoryModule\Clear-InterfacePortStream -Hostname $cleanHost

if (-not $SkipQueueDelayCheck.IsPresent) {
    if (-not $queueMetrics) {
        Write-Warning ("[Harness] No InterfacePortQueueMetrics were captured for '{0}'; queue delay guard skipped." -f $cleanHost)
    } else {
        $delay = $null
        foreach ($property in @('QueueDelayMs', 'QueueBuildDelayMs')) {
            if ($queueMetrics.PSObject.Properties.Name -contains $property) {
                try { $delay = [double]$queueMetrics.$property } catch { $delay = $null }
            }
            if ($delay -ne $null) { break }
        }

        $duration = $null
        if ($queueMetrics.PSObject.Properties.Name -contains 'QueueBuildDurationMs') {
            try { $duration = [double]$queueMetrics.QueueBuildDurationMs } catch { $duration = $null }
        }

        if ($delay -eq $null) {
            Write-Warning ("[Harness] Queue metrics for '{0}' did not include QueueBuildDelayMs; guard skipped." -f $cleanHost)
        } else {
            $durationDisplay = if ($duration -ne $null) { ('{0:N3} ms' -f $duration) } else { 'n/a' }
            Write-Host ("[Harness] Queue build delay for '{0}': {1:N3} ms (duration {2})" -f `
                $cleanHost,
                $delay,
                $durationDisplay) -ForegroundColor Yellow

            if ($QueueDelayCriticalMs -ge 0 -and $delay -gt $QueueDelayCriticalMs) {
                throw ("[Harness] Queue build delay {0:N3} ms exceeds critical threshold {1:N3} ms." -f $delay, $QueueDelayCriticalMs)
            }

            if ($QueueDelayWarningMs -ge 0 -and $delay -gt $QueueDelayWarningMs) {
                Write-Warning ("[Harness] Queue build delay {0:N3} ms exceeds warning threshold {1:N3} ms (Hostname: {2})." -f $delay, $QueueDelayWarningMs, $cleanHost)
            }
        }
    }
}

# LANDMARK: Telemetry buffer rename - use approved verb export
try { TelemetryModule\Save-StTelemetryBuffer | Out-Null } catch { Write-Verbose "Caught exception in Invoke-InterfaceDispatchHarness.ps1: $($_.Exception.Message)" }
Write-HarnessVerbose ("[Harness] Completed dispatcher simulation for '{0}'." -f $cleanHost)
