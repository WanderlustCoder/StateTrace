<#
.SYNOPSIS
MainWindow service layer for non-UI logic.

.DESCRIPTION
ST-L-004/ST-O-004: Extracted service logic from Main/MainWindow.ps1 to enable
unit testing and reduce code-behind complexity. Contains:
- Settings management
- Ingestion freshness queries
- User-action telemetry publishing
- Parser job status helpers

UI binding remains in MainWindow.ps1; this module provides the data layer.
#>

Set-StrictMode -Version Latest

#region Module State

if (-not (Get-Variable -Scope Script -Name ServiceSettingsPath -ErrorAction SilentlyContinue)) {
    $script:ServiceSettingsPath = $null
}

if (-not (Get-Variable -Scope Script -Name FreshnessCache -ErrorAction SilentlyContinue)) {
    $script:FreshnessCache = @{
        Site      = $null
        Info      = $null
        MetricsAt = $null
    }
}

if (-not (Get-Variable -Scope Script -Name RepositoryRoot -ErrorAction SilentlyContinue)) {
    $script:RepositoryRoot = $null
}

#endregion

#region Initialization

function Initialize-MainWindowServices {
    <#
    .SYNOPSIS
    Initializes the service layer with repository paths.
    #>
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [string]$SettingsPath
    )

    $script:RepositoryRoot = $RepositoryRoot

    if ($SettingsPath) {
        $script:ServiceSettingsPath = $SettingsPath
    }
    else {
        $script:ServiceSettingsPath = Join-Path $RepositoryRoot 'Data\StateTraceSettings.json'
    }

    return [pscustomobject]@{
        RepositoryRoot = $script:RepositoryRoot
        SettingsPath   = $script:ServiceSettingsPath
        Initialized    = $true
    }
}

#endregion

#region Settings Management

function Get-StateTraceSettings {
    <#
    .SYNOPSIS
    Loads StateTrace settings from JSON file.
    #>
    param(
        [string]$Path
    )

    $settingsPath = if ($Path) { $Path } else { $script:ServiceSettingsPath }
    if (-not $settingsPath) {
        Write-Warning "Settings path not configured. Call Initialize-MainWindowServices first."
        return @{}
    }

    $settings = @{}
    if (Test-Path -LiteralPath $settingsPath) {
        try {
            $json = Get-Content -LiteralPath $settingsPath -Raw
            if (-not [string]::IsNullOrWhiteSpace($json)) {
                $parsed = $json | ConvertFrom-Json
                if ($parsed) {
                    foreach ($prop in $parsed.PSObject.Properties) {
                        $settings[$prop.Name] = $prop.Value
                    }
                }
            }
        }
        catch {
            Write-Warning ("Failed to load settings from {0}: {1}" -f $settingsPath, $_.Exception.Message)
            $settings = @{}
        }
    }

    return $settings
}

function Set-StateTraceSettings {
    <#
    .SYNOPSIS
    Saves StateTrace settings to JSON file.
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Settings,
        [string]$Path
    )

    $settingsPath = if ($Path) { $Path } else { $script:ServiceSettingsPath }
    if (-not $settingsPath) {
        Write-Warning "Settings path not configured. Call Initialize-MainWindowServices first."
        return $false
    }

    try {
        $json = $Settings | ConvertTo-Json -Depth 5
        $settingsDir = Split-Path -Parent $settingsPath
        if (-not (Test-Path -LiteralPath $settingsDir)) {
            New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
        }
        $json | Out-File -LiteralPath $settingsPath -Encoding utf8
        return $true
    }
    catch {
        Write-Warning ("Failed to save settings to {0}: {1}" -f $settingsPath, $_.Exception.Message)
        return $false
    }
}

#endregion

#region User Action Telemetry

function Publish-UserActionTelemetry {
    <#
    .SYNOPSIS
    Publishes a user action telemetry event.
    #>
    param(
        [string]$Action,
        [string]$Site,
        [string]$Hostname,
        [string]$Context
    )

    $payload = @{
        Timestamp = (Get-Date).ToString('o')
    }
    if ($Action) { $payload['Action'] = $Action }
    if ($Site) { $payload['Site'] = $Site }
    if ($Hostname) { $payload['Hostname'] = $Hostname }
    if ($Context) { $payload['Context'] = $Context }

    # Try to publish via TelemetryModule if available
    $telemetryCmd = Get-Command -Name 'TelemetryModule\Write-StTelemetryEvent' -ErrorAction SilentlyContinue
    if ($telemetryCmd) {
        try {
            & $telemetryCmd -Name 'UserAction' -Payload $payload
        }
        catch {
            # Silently ignore telemetry failures
        }
    }

    return $payload
}

#endregion

#region Ingestion Freshness

function Get-SiteIngestionInfo {
    <#
    .SYNOPSIS
    Gets ingestion history info for a site.

    .OUTPUTS
    PSCustomObject with Site, LastIngestedUtc, Source, HistoryPath or $null.
    #>
    param(
        [Parameter(Mandatory)][string]$Site,
        [string]$RepositoryRoot
    )

    if ([string]::IsNullOrWhiteSpace($Site)) { return $null }

    $repoRoot = if ($RepositoryRoot) { $RepositoryRoot } else { $script:RepositoryRoot }
    if (-not $repoRoot) {
        Write-Warning "Repository root not configured. Call Initialize-MainWindowServices first."
        return $null
    }

    $historyPath = Join-Path $repoRoot "Data\IngestionHistory\$Site.json"
    if (-not (Test-Path -LiteralPath $historyPath)) { return $null }

    $entries = $null
    try {
        $entries = Get-Content -LiteralPath $historyPath -Raw | ConvertFrom-Json
    }
    catch {
        return $null
    }

    if (-not $entries) { return $null }

    $latest = $entries | Where-Object { $_.LastIngestedUtc } |
        Sort-Object { $_.LastIngestedUtc } -Descending |
        Select-Object -First 1

    if (-not $latest) { return $null }

    $ingestedUtc = $null
    try {
        $ingestedUtc = [datetime]::Parse($latest.LastIngestedUtc).ToUniversalTime()
    }
    catch {
        return $null
    }

    $source = $latest.SiteCacheProvider
    if (-not $source -and $latest.CacheStatus) { $source = $latest.CacheStatus }
    if (-not $source -and $latest.Source) { $source = $latest.Source }
    if (-not $source) { $source = 'History' }

    return [pscustomobject]@{
        Site            = $Site
        LastIngestedUtc = $ingestedUtc
        Source          = $source
        HistoryPath     = $historyPath
    }
}

function Get-SiteCacheProviderFromMetrics {
    <#
    .SYNOPSIS
    Gets cache provider info from latest ingestion metrics.

    .OUTPUTS
    PSCustomObject with Provider, Reason, EventName, Timestamp, MetricsLog or $null.
    #>
    param(
        [Parameter(Mandatory)][string]$Site,
        [string]$RepositoryRoot,
        [switch]$SkipCache
    )

    if ([string]::IsNullOrWhiteSpace($Site)) { return $null }

    $repoRoot = if ($RepositoryRoot) { $RepositoryRoot } else { $script:RepositoryRoot }
    if (-not $repoRoot) { return $null }

    $logDir = Join-Path $repoRoot 'Logs\IngestionMetrics'
    if (-not (Test-Path -LiteralPath $logDir)) { return $null }

    $latest = Get-ChildItem -LiteralPath $logDir -Filter '*.json' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $latest) { return $null }

    # Check cache
    if (-not $SkipCache -and
        $script:FreshnessCache.Site -eq $Site -and
        $script:FreshnessCache.MetricsAt -eq $latest.LastWriteTime) {
        return $script:FreshnessCache.Info
    }

    # Parse telemetry file
    $telemetry = $null
    try {
        $telemetry = Get-Content -LiteralPath $latest.FullName -Raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        # Fallback to newline-delimited JSON
        $lines = Get-Content -LiteralPath $latest.FullName -ErrorAction SilentlyContinue
        $parsed = [System.Collections.Generic.List[object]]::new()
        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                [void]$parsed.Add(($line | ConvertFrom-Json -ErrorAction Stop))
            }
            catch { Write-Verbose "Caught exception in MainWindow.Services.psm1: $($_.Exception.Message)" }
        }
        if ($parsed.Count -gt 0) { $telemetry = $parsed }
    }

    if (-not $telemetry) { return $null }

    $candidateEvents = @($telemetry | Where-Object {
        $_.EventName -in @('DatabaseWriteBreakdown', 'InterfaceSiteCacheMetrics', 'InterfaceSyncTiming', 'InterfaceSiteCacheRunspaceState') -and
        [string]::Equals($_.Site, $Site, [System.StringComparison]::OrdinalIgnoreCase)
    })

    if ($candidateEvents.Count -eq 0) { return $null }

    $best = $null
    foreach ($entry in $candidateEvents) {
        $provider = $null
        $reason = $null
        $status = $null

        if ($entry.PSObject.Properties.Name -contains 'SiteCacheProvider' -and $entry.SiteCacheProvider) {
            $provider = $entry.SiteCacheProvider
        }
        if ($entry.PSObject.Properties.Name -contains 'SiteCacheProviderReason' -and $entry.SiteCacheProviderReason) {
            $reason = $entry.SiteCacheProviderReason
        }
        if ($entry.PSObject.Properties.Name -contains 'CacheStatus' -and $entry.CacheStatus) {
            $status = $entry.CacheStatus
        }

        if (-not $provider -and $status) { $provider = $status }
        if (-not $provider -and $reason) { $provider = $reason }

        $timestamp = $null
        if ($entry.PSObject.Properties.Name -contains 'Timestamp' -and $entry.Timestamp) {
            try {
                $timestamp = [datetime]::Parse($entry.Timestamp).ToLocalTime()
            }
            catch { Write-Verbose "Caught exception in MainWindow.Services.psm1: $($_.Exception.Message)" }
        }

        $candidate = [pscustomobject]@{
            Provider    = if ($provider) { $provider } else { 'Unknown' }
            Reason      = $reason
            CacheStatus = $status
            EventName   = $entry.EventName
            Timestamp   = $timestamp
        }

        if (-not $best -or ($timestamp -and $best.Timestamp -lt $timestamp)) {
            $best = $candidate
        }
    }

    if (-not $best) { return $null }

    $info = [pscustomobject]@{
        Provider   = $best.Provider
        Reason     = $best.Reason
        EventName  = $best.EventName
        Timestamp  = $best.Timestamp
        MetricsLog = $latest.FullName
    }

    # Update cache
    $script:FreshnessCache = @{
        Site      = $Site
        Info      = $info
        MetricsAt = $latest.LastWriteTime
    }

    return $info
}

function Get-FreshnessStatus {
    <#
    .SYNOPSIS
    Calculates freshness status based on age thresholds.

    .OUTPUTS
    PSCustomObject with Color, StatusText, AgeText.
    #>
    param(
        [Parameter(Mandatory)][datetime]$LastIngestedUtc
    )

    $age = [datetime]::UtcNow - $LastIngestedUtc

    $ageText = if ($age.TotalMinutes -lt 1) {
        '<1 min ago'
    }
    elseif ($age.TotalHours -lt 1) {
        ('{0:F0} min ago' -f [math]::Floor($age.TotalMinutes))
    }
    elseif ($age.TotalDays -lt 1) {
        ('{0:F1} h ago' -f $age.TotalHours)
    }
    else {
        ('{0:F1} d ago' -f $age.TotalDays)
    }

    # Green: <24h, Yellow: 24-48h, Orange: 48h-7d, Red: >7d
    $color = if ($age.TotalHours -lt 24) {
        'Green'
    }
    elseif ($age.TotalHours -lt 48) {
        'Yellow'
    }
    elseif ($age.TotalDays -lt 7) {
        'Orange'
    }
    else {
        'Red'
    }

    $statusText = switch ($color) {
        'Green'  { 'Fresh (< 24 hours old)' }
        'Yellow' { 'Warning (24-48 hours old)' }
        'Orange' { 'Stale (2-7 days old)' }
        'Red'    { 'Very stale (> 7 days old)' }
        default  { 'Unknown' }
    }

    return [pscustomobject]@{
        Color      = $color
        StatusText = $statusText
        AgeText    = $ageText
        Age        = $age
    }
}

function Get-LatestPipelineLogPath {
    <#
    .SYNOPSIS
    Returns the path to the latest pipeline log file.
    #>
    param(
        [string]$RepositoryRoot
    )

    $repoRoot = if ($RepositoryRoot) { $RepositoryRoot } else { $script:RepositoryRoot }
    if (-not $repoRoot) { return $null }

    $logsDir = Join-Path $repoRoot 'Logs\Verification'
    if (-not (Test-Path -LiteralPath $logsDir)) {
        $logsDir = Join-Path $repoRoot 'Logs\IngestionMetrics'
    }
    if (-not (Test-Path -LiteralPath $logsDir)) { return $null }

    $latest = Get-ChildItem -LiteralPath $logsDir -Filter '*.log' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $latest) {
        $latest = Get-ChildItem -LiteralPath $logsDir -Filter '*.json' -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
    }

    if ($latest) {
        return $latest.FullName
    }

    return $null
}

#endregion

#region Parser Job Helpers

function Get-ParserLogTail {
    <#
    .SYNOPSIS
    Gets the last N lines from a parser log file.
    #>
    param(
        [Parameter(Mandatory)][string]$LogPath,
        [int]$Lines = 20
    )

    if (-not (Test-Path -LiteralPath $LogPath)) {
        return $null
    }

    try {
        $content = Get-Content -LiteralPath $LogPath -Tail $Lines -ErrorAction Stop
        return ($content -join "`n")
    }
    catch {
        return $null
    }
}

function Get-ParserJobStatus {
    <#
    .SYNOPSIS
    Gets the status of a parser background job.
    #>
    param(
        [System.Management.Automation.Job]$Job
    )

    if (-not $Job) {
        return [pscustomobject]@{
            State     = 'None'
            HasOutput = $false
            HasError  = $false
        }
    }

    $hasOutput = $Job.ChildJobs.Count -gt 0 -and $Job.ChildJobs[0].Output.Count -gt 0
    $hasError = $Job.ChildJobs.Count -gt 0 -and $Job.ChildJobs[0].Error.Count -gt 0

    return [pscustomobject]@{
        State     = $Job.State
        HasOutput = $hasOutput
        HasError  = $hasError
        Id        = $Job.Id
        Name      = $Job.Name
    }
}

#endregion

#region Exports

Export-ModuleMember -Function @(
    'Initialize-MainWindowServices',
    'Get-StateTraceSettings',
    'Set-StateTraceSettings',
    'Publish-UserActionTelemetry',
    'Get-SiteIngestionInfo',
    'Get-SiteCacheProviderFromMetrics',
    'Get-FreshnessStatus',
    'Get-LatestPipelineLogPath',
    'Get-ParserLogTail',
    'Get-ParserJobStatus'
)

#endregion
