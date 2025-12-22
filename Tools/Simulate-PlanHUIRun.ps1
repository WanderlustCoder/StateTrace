[CmdletBinding()]
param(
    [string[]]$Sites = @('WLLS','BOYO'),
    [string]$TelemetryPath = (Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'Logs\IngestionMetrics') ((Get-Date).ToString('yyyy-MM-dd') + '.json')),
    [string]$ScreenshotTimestamp = (Get-Date).ToString('yyyyMMdd-HHmmss'),
    [string]$BundleName = ("UI-{0}-planh-sim" -f (Get-Date -Format 'yyyyMMdd')),
    [int]$TimestampStepMilliseconds = 25
)

<#
.SYNOPSIS
Simulates a Plan H UI run in headless mode (telemetry + screenshots + bundle).

.DESCRIPTION
Emits UserAction and freshness/cache provider telemetry for the given sites,
generates headless screenshots from existing summaries, runs analyzers, and
publishes a readiness-enforced bundle. Produces a Plan H report at the end.

.NOTE
Use this when an interactive WPF session is unavailable.

.EXAMPLE
pwsh -NoLogo -File Tools\Simulate-PlanHUIRun.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '..\Modules\TelemetryModule.psm1') -Force

$script:PlanHTimestampBase = Get-Date
$script:PlanHTimestampStepMs = [Math]::Max(1, $TimestampStepMilliseconds)
$script:PlanHTimestampOffsetMs = 0
function Get-PlanHTimestamp {
    $timestamp = $script:PlanHTimestampBase.AddMilliseconds($script:PlanHTimestampOffsetMs)
    $script:PlanHTimestampOffsetMs += $script:PlanHTimestampStepMs
    return $timestamp.ToString('o')
}

function Emit-UserActions {
    param([string]$Path, [string[]]$SiteList)
    $actions = @(
        @{ Action='ScanLogs';      Site=$SiteList[0]; Hostname="$($SiteList[0])-SW01"; Context='Sim' },
        @{ Action='LoadFromDb';    Site=$SiteList[0]; Hostname="$($SiteList[0])-SW01"; Context='Sim' },
        @{ Action='HelpQuickstart';Site=$SiteList[0]; Hostname="$($SiteList[0])-SW01"; Context='Sim' },
        @{ Action='InterfacesView';Site=$SiteList[0]; Hostname="$($SiteList[0])-SW02" },
        @{ Action='CompareView';   Site=$SiteList[0]; Hostname="$($SiteList[0])-SW01"; Hostname2="$($SiteList[0])-SW02"; Port1='Gi1/0/1'; Port2='Gi1/0/2' },
        @{ Action='SpanSnapshot';  Site=$SiteList[0]; Hostname="$($SiteList[0])-SW01"; RowsBound=128 },
        @{ Action='ScanLogs';      Site=$SiteList[1]; Hostname="$($SiteList[1])-SW01"; Context='Sim' },
        @{ Action='LoadFromDb';    Site=$SiteList[1]; Hostname="$($SiteList[1])-SW01"; Context='Sim' },
        @{ Action='HelpQuickstart';Site=$SiteList[1]; Hostname="$($SiteList[1])-SW01"; Context='Sim' },
        @{ Action='InterfacesView';Site=$SiteList[1]; Hostname="$($SiteList[1])-SW02" },
        @{ Action='CompareView';   Site=$SiteList[1]; Hostname="$($SiteList[1])-SW01"; Hostname2="$($SiteList[1])-SW02"; Port1='Te0/1'; Port2='Te0/2' },
        @{ Action='SpanSnapshot';  Site=$SiteList[1]; Hostname="$($SiteList[1])-SW02"; RowsBound=96 }
    )
    foreach ($payload in $actions) {
        $payload['Timestamp'] = Get-PlanHTimestamp
        TelemetryModule\Write-StTelemetryEvent -Name 'UserAction' -Payload $payload
    }
}

function Emit-FreshnessTelemetry {
    param([string[]]$SiteList)
    $events = @(
        @{ EventName='InterfaceSiteCacheMetrics'; Site=$SiteList[0]; SiteCacheProvider='Cache'; CacheStatus='Hit'; SiteCacheProviderReason='SharedOnly'; HostCount=42 },
        @{ EventName='InterfaceSiteCacheMetrics'; Site=$SiteList[1]; SiteCacheProvider='AccessRefresh'; CacheStatus='Miss'; SiteCacheProviderReason='AccessRefresh'; HostCount=18 },
        @{ EventName='InterfaceSiteCacheRunspaceState'; Site=$SiteList[0]; SiteCacheProvider='Cache'; CacheStatus='Hydrated'; SiteCacheProviderReason='SharedOnly' },
        @{ EventName='InterfaceSiteCacheRunspaceState'; Site=$SiteList[1]; SiteCacheProvider='AccessRefresh'; CacheStatus='Hydrated'; SiteCacheProviderReason='AccessRefresh' },
        @{ EventName='InterfaceSyncTiming'; Site=$SiteList[0]; CacheStatus='Cache'; DurationMs=512 },
        @{ EventName='InterfaceSyncTiming'; Site=$SiteList[1]; CacheStatus='AccessRefresh'; DurationMs=845 }
    )
    foreach ($evt in $events) {
        $payload = @{}
        foreach ($k in $evt.Keys) { if ($k -ne 'EventName') { $payload[$k] = $evt[$k] } }
        $payload['Timestamp'] = Get-PlanHTimestamp
        TelemetryModule\Write-StTelemetryEvent -Name $evt.EventName -Payload $payload
    }
}

# Emit telemetry
Emit-UserActions -Path $TelemetryPath -SiteList $Sites
Emit-FreshnessTelemetry -SiteList $Sites

# Generate screenshots (headless) from summaries
& (Join-Path $PSScriptRoot 'Capture-PlanHScreenshots.ps1') -QuickstartSummaryPath 'Logs\Reports\InterfacesViewQuickstart-20251126-143359.json' -FreshnessSummaryPath 'Logs\Reports\FreshnessTelemetrySummary-20251126-run2.json' -OutputDirectory 'docs\performance\screenshots' -Prefix 'onboarding' -Timestamp $ScreenshotTimestamp | Out-Null

# Analyze telemetry
& (Join-Path $PSScriptRoot 'Analyze-UserActionTelemetry.ps1') -Path $TelemetryPath -OutputPath (Join-Path (Split-Path $TelemetryPath -Parent) "..\Reports\UserActionSummary-$($ScreenshotTimestamp).json") | Out-Null
& (Join-Path $PSScriptRoot 'Analyze-FreshnessTelemetry.ps1') -Path $TelemetryPath -OutputPath (Join-Path (Split-Path $TelemetryPath -Parent) "..\Reports\FreshnessTelemetrySummary-$($ScreenshotTimestamp).json") | Out-Null

# Publish bundle (readiness enforced)
$bundleDir = Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'Logs\TelemetryBundles') $BundleName
& (Join-Path $PSScriptRoot 'Invoke-PlanHBundle.ps1') -TelemetryPath $TelemetryPath -BundleName $BundleName -Force | Out-Null

# Run checks/report
& (Join-Path $PSScriptRoot 'Invoke-PlanHChecks.ps1') -BundlePath $bundleDir -ReportPath (Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'docs\performance') ("PlanHReport-$ScreenshotTimestamp.md")) | Out-Null

Write-Host "[PlanH] Simulation complete. Bundle: $bundleDir" -ForegroundColor Green
