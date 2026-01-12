[CmdletBinding()]
param(
    [string]$OutputPath,
    [switch]$UpdateLatest,
    [switch]$PassThru,
    [switch]$SkipCompare
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'

function Resolve-PathFromRoot {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
    return [System.IO.Path]::GetFullPath((Join-Path -Path $repoRoot -ChildPath $Path))
}

function Ensure-Directory {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

function Set-CompareModuleVar {
    param([string]$Name, $Value)
    $module = Get-Module CompareViewModule -ErrorAction Stop
    $module.SessionState.PSVariable.Set($Name, $Value)
}

function Get-CompareModuleVar {
    param([string]$Name)
    $module = Get-Module CompareViewModule -ErrorAction Stop
    ($module.SessionState.PSVariable.Get($Name)).Value
}

function New-DropdownStub {
    param([string]$SelectedItem)
    $obj = [pscustomobject]@{
        SelectedItem = $SelectedItem
        ItemsSource  = $null
        Text         = $SelectedItem
    }
    foreach ($name in 'Add_SelectionChanged','Add_LostFocus','Add_KeyDown','Add_DropDownOpened') {
        if (-not ($obj.PSObject.Methods.Name -contains $name)) {
            Add-Member -InputObject $obj -MemberType ScriptMethod -Name $name -Value { param($handler) } -Force
        }
    }
    return $obj
}

function New-TextBlockStub {
    [pscustomobject]@{
        Text       = $null
        Foreground = $null
    }
}

function Select-LastEventSubset {
    param(
        [Parameter(Mandatory)][string]$MetricName,
        $Payload
    )
    if (-not $Payload) { return $null }
    # LANDMARK: Compare telemetry smoke - deterministic LastEvent subset normalization
    switch ($MetricName) {
        'DiffUsageRate' {
            return [ordered]@{
                Status           = $Payload.Status
                UsageNumerator   = $Payload.UsageNumerator
                UsageDenominator = $Payload.UsageDenominator
                Site             = $Payload.Site
                Hostname         = $Payload.Hostname
                Hostname2        = $Payload.Hostname2
                Port1            = $Payload.Port1
                Port2            = $Payload.Port2
                Vrf              = $Payload.Vrf
            }
        }
        'DiffCompareDurationMs' {
            return [ordered]@{
                Status    = $Payload.Status
                Site      = $Payload.Site
                Hostname  = $Payload.Hostname
                Hostname2 = $Payload.Hostname2
                Port1     = $Payload.Port1
                Port2     = $Payload.Port2
                Vrf       = $Payload.Vrf
            }
        }
        'DiffCompareResultCounts' {
            return [ordered]@{
                Status         = $Payload.Status
                TotalCount     = $Payload.TotalCount
                AddedCount     = $Payload.AddedCount
                RemovedCount   = $Payload.RemovedCount
                ChangedCount   = $Payload.ChangedCount
                UnchangedCount = $Payload.UnchangedCount
                Site           = $Payload.Site
                Hostname       = $Payload.Hostname
                Hostname2      = $Payload.Hostname2
                Port1          = $Payload.Port1
                Port2          = $Payload.Port2
                Vrf            = $Payload.Vrf
            }
        }
    }
    return $null
}

if (-not $OutputPath) {
    $OutputPath = Join-Path -Path $repoRoot -ChildPath ("Logs\\Reports\\CompareTelemetrySmoke\\CompareTelemetrySmokeSummary-{0}.json" -f $timestamp)
}
$OutputPath = Resolve-PathFromRoot -Path $OutputPath
Ensure-Directory -Path (Split-Path -Parent $OutputPath)

$requiredMetrics = @('DiffUsageRate','DiffCompareDurationMs','DiffCompareResultCounts')
$script:CompareTelemetrySmokeEvents = New-Object System.Collections.Generic.List[object]
$fatalError = $null
$previousTelemetryOverride = $null

try {
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'Modules\\CompareViewModule.psm1'
    $compareModule = Import-Module $modulePath -Force -PassThru

    try {
        $previousTelemetryOverride = Get-CompareModuleVar -Name 'CompareTelemetryCommandOverride'
    } catch { Write-Verbose "Caught exception in Test-CompareTelemetrySmoke.ps1: $($_.Exception.Message)" }

    Set-CompareModuleVar windowRef $null
    Set-CompareModuleVar compareView ([pscustomobject]@{})
    Set-CompareModuleVar switch1Dropdown (New-DropdownStub 'sw1')
    Set-CompareModuleVar port1Dropdown   (New-DropdownStub 'Gi1')
    Set-CompareModuleVar switch2Dropdown (New-DropdownStub 'sw2')
    Set-CompareModuleVar port2Dropdown   (New-DropdownStub 'Gi2')
    Set-CompareModuleVar config1Box (New-TextBlockStub)
    Set-CompareModuleVar config2Box (New-TextBlockStub)
    Set-CompareModuleVar diff1Box   (New-TextBlockStub)
    Set-CompareModuleVar diff2Box   (New-TextBlockStub)
    Set-CompareModuleVar auth1Text  (New-TextBlockStub)
    Set-CompareModuleVar auth2Text  (New-TextBlockStub)
    Set-CompareModuleVar lastCompareColors (@{})

    $row1 = [pscustomobject]@{ ToolTip = "line1`nline2`nline3"; PortColor = 'Green'; Vrf = 'default' }
    $row2 = [pscustomobject]@{ ToolTip = "line2`nline3`nline4"; PortColor = 'Blue' }
    Set-CompareModuleVar testRow1 $row1
    Set-CompareModuleVar testRow2 $row2

    Set-CompareModuleVar CompareTelemetryCommandOverride {
        param($Name, $Payload)
        $script:CompareTelemetrySmokeEvents.Add([pscustomobject]@{
            Name    = $Name
            Payload = $Payload
        }) | Out-Null
    }

    $originalGetGridRow = & $compareModule { (Get-Command Get-GridRowFor -ErrorAction Stop).ScriptBlock }
    $originalSetCompare = & $compareModule { (Get-Command Set-CompareFromRows -ErrorAction Stop).ScriptBlock }
    $originalThemeBrush = & $compareModule { (Get-Command Get-ThemeBrushForPortColor -ErrorAction Stop).ScriptBlock }

    # LANDMARK: Compare telemetry smoke - execute deterministic compare and capture telemetry
    & $compareModule {
        Set-Item -Path Function:\Get-GridRowFor -Value {
            param($Hostname, $Port)
            switch ("$Hostname|$Port") {
                'sw1|Gi1' { return $script:testRow1 }
                'sw2|Gi2' { return $script:testRow2 }
                default   { return $null }
            }
        }
    }
    & $compareModule {
        Set-Item -Path Function:\Set-CompareFromRows -Value { param($Row1, $Row2) }
    }
    & $compareModule {
        Set-Item -Path Function:\Get-ThemeBrushForPortColor -Value { param($ColorName) return $ColorName }
    }

    if (-not $SkipCompare) {
        & $compareModule { Show-CurrentComparison }
    }
} catch {
    $fatalError = $_.Exception.Message
} finally {
    try {
        if ($originalGetGridRow -and $compareModule) {
            & $compareModule { Set-Item -Path Function:\Get-GridRowFor -Value $using:originalGetGridRow }
        }
        if ($originalSetCompare -and $compareModule) {
            & $compareModule { Set-Item -Path Function:\Set-CompareFromRows -Value $using:originalSetCompare }
        }
        if ($originalThemeBrush -and $compareModule) {
            & $compareModule { Set-Item -Path Function:\Get-ThemeBrushForPortColor -Value $using:originalThemeBrush }
        }
    } catch { Write-Verbose "Caught exception in Test-CompareTelemetrySmoke.ps1: $($_.Exception.Message)" }
    try { Set-CompareModuleVar CompareTelemetryCommandOverride $previousTelemetryOverride } catch { Write-Verbose "Caught exception in Test-CompareTelemetrySmoke.ps1: $($_.Exception.Message)" }
}

$observedMetrics = [ordered]@{}
$missingMetrics = New-Object System.Collections.Generic.List[string]
foreach ($metric in $requiredMetrics) {
    $events = @($script:CompareTelemetrySmokeEvents | Where-Object { $_.Name -eq $metric })
    $present = $events.Count -gt 0
    if (-not $present) { $missingMetrics.Add($metric) | Out-Null }
    $lastPayload = $null
    if ($present) { $lastPayload = ($events | Select-Object -Last 1).Payload }
    $observedMetrics[$metric] = [ordered]@{
        Present    = $present
        EventCount = $events.Count
        LastEvent  = (Select-LastEventSubset -MetricName $metric -Payload $lastPayload)
    }
}

$status = if ($missingMetrics.Count -eq 0 -and -not $fatalError) { 'Pass' } else { 'Fail' }
$summary = [ordered]@{
    TimestampUtc   = (Get-Date).ToUniversalTime().ToString('o')
    Status         = $status
    RequiredMetrics = $requiredMetrics
    ObservedMetrics = $observedMetrics
    MissingMetrics  = @($missingMetrics)
}
if ($fatalError) {
    $summary['ActionableError'] = $fatalError
}

# LANDMARK: Compare telemetry smoke - summary emission and latest pointer
$summaryJson = $summary | ConvertTo-Json -Depth 6
$summaryJson | Set-Content -LiteralPath $OutputPath -Encoding utf8
if ($UpdateLatest) {
    $latestPath = Join-Path -Path $repoRoot -ChildPath 'Logs\\Reports\\CompareTelemetrySmoke\\CompareTelemetrySmoke-latest.json'
    Ensure-Directory -Path (Split-Path -Parent $latestPath)
    $summaryJson | Set-Content -LiteralPath $latestPath -Encoding utf8
}

if ($PassThru) {
    return $summary
}
