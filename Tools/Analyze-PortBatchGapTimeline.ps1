[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$MetricsPath,

    [double]$GapThresholdSeconds = 60,

    [int]$EventsBefore = 4,

    [int]$EventsAfter = 4,

    [datetime]$StartTimeUtc,

    [datetime]$EndTimeUtc,

    [string]$OutputPath,

    [switch]$PassThru
)

<#
.SYNOPSIS
Shows the event timeline around large PortBatchReady gaps.

.DESCRIPTION
Reads newline-delimited ingestion metrics JSON, extracts `PortBatchReady` events, and identifies gaps where the time
between consecutive batches exceeds `GapThresholdSeconds`. For each gap, the script prints the surrounding hosts (the
previous `$EventsBefore` batches and the next `$EventsAfter` batches) so we can see which sites ran before/after the
stall. The output makes scheduler starvation obvious (e.g., every >60s gap being WLLS -> BOYO) without manual log
scraping. Use alongside `Tools\Analyze-PortBatchIntervals.ps1` and `Tools\Analyze-PortBatchGapBreakdown.ps1`.

.EXAMPLE
pwsh Tools\Analyze-PortBatchGapTimeline.ps1 `
    -MetricsPath Logs/IngestionMetrics/2025-11-13.json `
    -GapThresholdSeconds 60 `
    -EventsBefore 5 `
    -EventsAfter 5 `
    -OutputPath docs/performance/WLLS_BOYO_GapTimeline-20251113.md
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

trap {
    Write-Error "[GapTimeline] Line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"
    throw
}

function Resolve-InputFiles {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Metrics path '$Path' does not exist."
    }
    $item = Get-Item -LiteralPath $Path
    if ($item -is [System.IO.DirectoryInfo]) {
        return (Get-ChildItem -LiteralPath $item.FullName -Filter '*.json' -File | Sort-Object FullName).FullName
    }
    return @($item.FullName)
}

function Get-SiteFromHostname {
    param([string]$Hostname)
    if ([string]::IsNullOrWhiteSpace($Hostname)) { return '(unknown)' }
    $parts = $Hostname.Split('-', 2, [System.StringSplitOptions]::RemoveEmptyEntries)
    if ($parts.Count -gt 0) { return $parts[0] }
    return $Hostname
}

$files = Resolve-InputFiles -Path $MetricsPath
$events = New-Object System.Collections.Generic.List[pscustomobject]
$startUtc = $null
$endUtc = $null
if ($StartTimeUtc) { $startUtc = $StartTimeUtc.ToUniversalTime() }
if ($EndTimeUtc) { $endUtc = $EndTimeUtc.ToUniversalTime() }
if ($startUtc -and $endUtc -and $startUtc -gt $endUtc) {
    throw "StartTimeUtc must be earlier than or equal to EndTimeUtc."
}

foreach ($file in $files) {
    Get-Content -LiteralPath $file -ReadCount 500 | ForEach-Object {
        foreach ($line in $_) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $record = $line | ConvertFrom-Json -ErrorAction Stop
            }
            catch {
                Write-Warning ([string]::Format("Skipping malformed JSON line in '{0}': {1}", $file, $_.Exception.Message))
                continue
            }
            if ($record.EventName -ne 'PortBatchReady') { continue }
            $timestamp = [datetime]$record.Timestamp
            $timestampUtc = $timestamp.ToUniversalTime()
            if ($startUtc -and $timestampUtc -lt $startUtc) { continue }
            if ($endUtc -and $timestampUtc -gt $endUtc) { continue }
            $hostname = $record.Hostname
            $events.Add([pscustomobject]@{
                Index     = $events.Count
                Timestamp = $timestampUtc
                Hostname  = $hostname
                Site      = Get-SiteFromHostname -Hostname $hostname
                Ports     = $record.PortsCommitted
                Source    = $file
            }) | Out-Null
        }
    }
}

if ($events.Count -lt 2) {
    throw "Need at least 2 PortBatchReady events (found $($events.Count))."
}

$sorted = $events | Sort-Object Timestamp
for ($i = 0; $i -lt $sorted.Count; $i++) {
    $sorted[$i].Index = $i
    if ($i -eq 0) {
        $sorted[$i] | Add-Member -NotePropertyName 'DeltaSeconds' -NotePropertyValue $null -Force
    }
    else {
        $delta = ($sorted[$i].Timestamp - $sorted[$i-1].Timestamp).TotalSeconds
        $sorted[$i] | Add-Member -NotePropertyName 'DeltaSeconds' -NotePropertyValue ([math]::Round($delta, 3)) -Force
    }
}

$gapEntries = @()
for ($i = 1; $i -lt $sorted.Count; $i++) {
    $delta = $sorted[$i].DeltaSeconds
    if ($delta -ge $GapThresholdSeconds) {
        $gapEntries += [pscustomobject]@{
            GapSeconds   = $delta
            StartEvent   = $sorted[$i-1]
            EndEvent     = $sorted[$i]
            GapIndex     = $i
        }
    }
}

if (-not $gapEntries) {
    Write-Host ([string]::Format("No PortBatch gaps exceeded {0} seconds.", $GapThresholdSeconds)) -ForegroundColor Green
    if ($PassThru) { return @() }
    return
}

function Build-ContextRows {
    param(
        [pscustomobject]$Gap,
        [System.Collections.Generic.List[pscustomobject]]$Events,
        [int]$Before,
        [int]$After
    )

    $startIdx = [math]::Max(0, $Gap.StartEvent.Index - ($Before - 1))
    $endIdx = [math]::Min($Events.Count - 1, $Gap.EndEvent.Index + ($After - 1))
    $rows = New-Object System.Collections.Generic.List[pscustomobject]
    for ($idx = $startIdx; $idx -le $endIdx; $idx++) {
        $evt = $Events[$idx]
        $rows.Add([pscustomobject]@{
            Seq         = $idx
            Timestamp   = $evt.Timestamp.ToUniversalTime()
            Hostname    = $evt.Hostname
            Site        = $evt.Site
            Ports       = $evt.Ports
            DeltaSeconds= $evt.DeltaSeconds
            IsGapStart  = ($idx -eq $Gap.EndEvent.Index)
            IsGapEndPrev= ($idx -eq $Gap.StartEvent.Index)
        }) | Out-Null
    }
    return $rows
}

$builder = New-Object System.Collections.Generic.List[string]
$builder.Add("# PortBatch gap timeline")
$builder.Add("")
$resolvedMetrics = (Resolve-Path -LiteralPath $MetricsPath) | ForEach-Object { $_.Path }
$builder.Add([string]::Format('> Metrics: `{0}`', ($resolvedMetrics -join '; ')))
if ($startUtc -or $endUtc) {
    $builder.Add([string]::Format('> Filter (UTC): {0} -> {1}', ($startUtc ? $startUtc.ToString('o') : 'start'), ($endUtc ? $endUtc.ToString('o') : 'end')))
}
$generatedStamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss K'
$builder.Add("> Generated $generatedStamp")
$builder.Add("> Gap threshold: $GapThresholdSeconds seconds")
$builder.Add("")

$timelineSummaries = @()
for ($gapIdx = 0; $gapIdx -lt $gapEntries.Count; $gapIdx++) {
    $gap = $gapEntries[$gapIdx]
    $contextRows = Build-ContextRows -Gap $gap -Events $sorted -Before $EventsBefore -After $EventsAfter
    $builder.Add([string]::Format("## Gap {0} - {1} -> {2} ({3} s)",
        ($gapIdx + 1),
        $gap.StartEvent.Hostname,
        $gap.EndEvent.Hostname,
        [math]::Round($gap.GapSeconds, 3)))
    $builder.Add("")
    $builder.Add("| Seq | Timestamp (UTC) | Delta seconds | Host | Site | Notes |")
    $builder.Add("|---|---|---|---|---|---|")
    foreach ($row in $contextRows) {
        $note = if ($row.IsGapEndPrev) {
            [string]::Format("Gap starts after this batch (delta={0}s)", [math]::Round($gap.GapSeconds, 3))
        }
        elseif ($row.IsGapStart) {
            "First batch after gap"
        }
        else {
            ""
        }
        $deltaText = if ($row.DeltaSeconds -ne $null) { $row.DeltaSeconds } else { "" }
        $builder.Add([string]::Format("| {0} | {1:u} | {2} | {3} | {4} | {5} |",
            $row.Seq,
            $row.Timestamp,
            $deltaText,
            $row.Hostname,
            $row.Site,
            $note))
        if ($row.IsGapEndPrev) {
            $builder.Add([string]::Format("|  |  | **{0} s idle** |  |  |  |", [math]::Round($gap.GapSeconds, 3)))
        }
    }
    $builder.Add("")
    $timelineSummaries += [pscustomobject]@{
        GapSeconds   = $gap.GapSeconds
        StartHost    = $gap.StartEvent.Hostname
        StartSite    = $gap.StartEvent.Site
        EndHost      = $gap.EndEvent.Hostname
        EndSite      = $gap.EndEvent.Site
        ContextRows  = $contextRows
    }
}

if ($OutputPath) {
    $outputDir = Split-Path -Path $OutputPath -Parent
    if ($outputDir -and -not (Test-Path -LiteralPath $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }
    Set-Content -LiteralPath $OutputPath -Value ($builder -join [Environment]::NewLine) -Encoding utf8
    Write-Host ([string]::Format("Gap timeline written to {0}", (Resolve-Path -LiteralPath $OutputPath))) -ForegroundColor DarkCyan
}
else {
    $builder -join [Environment]::NewLine | Write-Host
}

if ($PassThru) {
    return $timelineSummaries
}
