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

.EXAMPLE
PS> .\Tools\Invoke-InterfaceDispatchHarness.ps1 -Hostname 'BOYO-A05-AS-05'
Stages rows for BOYO-A05-AS-05 and emits InterfacePortDispatchMetrics payloads.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Hostname,
    [datetime]$RunDate = (Get-Date),
    [int]$ChunkSize = 0
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

try { Add-Type -AssemblyName PresentationFramework -ErrorAction Stop } catch {}

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

while ($true) {
    $batch = DeviceRepositoryModule\Get-InterfacePortBatch -Hostname $cleanHost
    if (-not $batch) {
        $status = $null
        try { $status = DeviceRepositoryModule\Get-InterfacePortStreamStatus -Hostname $cleanHost } catch { $status = $null }
        if ($status -and $status.Completed) { break }
        Start-Sleep -Milliseconds 100
        continue
    }

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

DeviceRepositoryModule\Clear-InterfacePortStream -Hostname $cleanHost

Write-HarnessVerbose ("[Harness] Completed dispatcher simulation for '{0}'." -f $cleanHost)
