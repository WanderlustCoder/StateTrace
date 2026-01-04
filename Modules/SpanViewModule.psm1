Set-StrictMode -Version Latest

$script:SpanViewControl        = $null
$script:SpanGridControl        = $null
$script:SpanVlanDropdown       = $null
$script:SpanRefreshButton      = $null
$script:SpanDiagnosticsButton  = $null
$script:SpanSamplePreview      = $null
$script:SpanDispatcher         = $null
$script:SpanHandlersRegistered = $false
$script:SpanLastHostname       = $null
$script:SpanLastRefresh        = $null
$script:SpanLastRows           = @()
$script:SpanStatusLabel        = $null
$script:WriteSpanDiagAction    = {
    param([string]$Message)
    try {
        TelemetryModule\Write-SpanDebugLog -Message $Message -Prefix 'Diag'
    } catch { }
}

if (-not (Get-Variable -Scope Script -Name SpanRepositoryImportWarned -ErrorAction SilentlyContinue)) {
    $script:SpanRepositoryImportWarned = $false
}

function Get-GlobalSpanView {
    try {
        $value = (Get-Variable -Name spanView -Scope Global -ErrorAction Stop).Value
        return $value
    } catch {
        return $null
    }
}

function Set-SpanViewControls {
    param([Parameter()][object]$View)

    # LANDMARK: Span view control checks - avoid false negatives on empty WPF enumerables
    if ($null -ne $View) {
        $script:SpanViewControl = $View
    } elseif (-not $script:SpanViewControl) {
        $globalView = Get-GlobalSpanView
        if ($null -ne $globalView) {
            $script:SpanViewControl = $globalView
        }
    }

    if (-not $script:SpanViewControl) {
        return $false
    }

    $currentGlobal = Get-GlobalSpanView
    if ($null -eq $currentGlobal -and $script:SpanViewControl) {
        $global:spanView = $script:SpanViewControl
    }

    try {
        $script:SpanGridControl    = $script:SpanViewControl.FindName('SpanGrid')
        $script:SpanVlanDropdown   = $script:SpanViewControl.FindName('VlanDropdown')
        $script:SpanRefreshButton  = $script:SpanViewControl.FindName('RefreshSpanButton')
        $script:SpanStatusLabel    = $script:SpanViewControl.FindName('SpanStatusLabel')
        $script:SpanDiagnosticsButton = $script:SpanViewControl.FindName('SpanDiagnosticsButton')
        $script:SpanSamplePreview     = $script:SpanViewControl.FindName('SpanSamplePreview')
        if ($script:SpanGridControl -and $script:SpanGridControl.Dispatcher) {
            $script:SpanDispatcher = $script:SpanGridControl.Dispatcher
        }
    } catch {
        $script:SpanGridControl   = $null
        $script:SpanVlanDropdown  = $null
        $script:SpanRefreshButton = $null
        $script:SpanStatusLabel   = $null
        $script:SpanDiagnosticsButton = $null
        $script:SpanSamplePreview = $null
        $script:SpanDispatcher    = $null
    }

    return [bool]$script:SpanGridControl
}

function Ensure-SpanViewControls {
    if ($script:SpanGridControl) {
        return $true
    }

    return (Set-SpanViewControls -View $null)
}

function Invoke-SpanDispatcher {
    param(
        [Parameter(Mandatory)][scriptblock]$Action,
        [object[]]$ArgumentList = @()
    )

    $action = $Action.GetNewClosure()
    $dispatcher = $script:SpanDispatcher
    if (-not $dispatcher -and $script:SpanGridControl -and $script:SpanGridControl.Dispatcher) {
        $dispatcher = $script:SpanGridControl.Dispatcher
        $script:SpanDispatcher = $dispatcher
    }
    if (-not $dispatcher) {
        $app = [System.Windows.Application]::Current
        if ($app) {
            $dispatcher = $app.Dispatcher
            $script:SpanDispatcher = $dispatcher
        }
    }

    if ($dispatcher -and -not $dispatcher.CheckAccess()) {
        return $dispatcher.Invoke($action, $ArgumentList)
    }

    return & $action @ArgumentList
}

function Import-SpanRepositoryModule {
    if (Get-Module -Name DeviceRepositoryModule -ErrorAction SilentlyContinue) {
        return
    }

    $lastError = $null
    $candidatePaths = [System.Collections.Generic.List[string]]::new()
    try { [void]$candidatePaths.Add((Join-Path -Path $PSScriptRoot -ChildPath 'DeviceRepositoryModule.psm1')) } catch { }
    try { [void]$candidatePaths.Add((Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'Modules\DeviceRepositoryModule.psm1')) } catch { }

    foreach ($candidate in $candidatePaths) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        if (-not (Test-Path -LiteralPath $candidate)) { continue }
        try {
            Import-Module -Name $candidate -Force -Global -ErrorAction Stop | Out-Null
            return
        } catch {
            $lastError = $_.Exception.Message
        }
    }

    try {
        Import-Module -Name DeviceRepositoryModule -Force -Global -ErrorAction Stop | Out-Null
        return
    } catch {
        $lastError = $_.Exception.Message
    }

    if (-not $script:SpanRepositoryImportWarned) {
        $script:SpanRepositoryImportWarned = $true
        $detail = if ($lastError) { $lastError } else { 'Unknown import failure.' }
        Write-Warning ("[SpanView] Failed to import DeviceRepositoryModule: {0}" -f $detail)
    }
}

function Reset-SpanViewState {
    $gridRef = $script:SpanGridControl
    $dropdownRef = $script:SpanVlanDropdown
    $statusLabelRef = $script:SpanStatusLabel
    $samplePreviewRef = $script:SpanSamplePreview
    Invoke-SpanDispatcher -Action {
        param($gridRef,$dropdownRef,$statusLabelRef,$samplePreviewRef,$diagAction)
        if ($gridRef) {
            $gridRef.ItemsSource = @()
            $gridRef.Tag = $null
        }
        if ($dropdownRef) {
            try { FilterStateModule\Set-DropdownItems -Control $dropdownRef -Items @('') } catch { }
            try { $dropdownRef.SelectedIndex = 0 } catch { }
        }
        if ($statusLabelRef) {
            $statusLabelRef.Text = 'No spanning-tree data loaded.'
        }
        if ($samplePreviewRef) {
            $samplePreviewRef.Text = 'Sample preview not loaded.'
        }
        & $diagAction "Reset-SpanViewState invoked."
    } -ArgumentList $gridRef,$dropdownRef,$statusLabelRef,$samplePreviewRef,$script:WriteSpanDiagAction | Out-Null

    $script:SpanLastHostname = $null
    $script:SpanLastRefresh = Get-Date
    $script:SpanLastRows = @()
}

function New-SpanView {
    param(
        [Parameter(Mandatory=$true)][System.Windows.Window]$Window,
        [Parameter(Mandatory=$true)][string]$ScriptDir
    )

    $spanView = Set-StView -Window $Window -ScriptDir $ScriptDir -ViewName 'SpanView' -HostControlName 'SpanHost' -GlobalVariableName 'spanView'
    if (-not $spanView) { return }

    Set-SpanViewControls -View $spanView | Out-Null
    # LANDMARK: Span view global cache - keep spanView synced for harnesses
    if ($null -ne $spanView) {
        $global:spanView = $spanView
    }

    Import-SpanRepositoryModule

    if (-not $script:SpanHandlersRegistered) {
        if ($script:SpanVlanDropdown) {
            $script:SpanVlanDropdown.Add_SelectionChanged({
                $grid = $script:SpanGridControl
                if (-not $grid) { return }
                $cached = $grid.Tag
                if (-not $cached) {
                    $grid.ItemsSource = @()
                    return
                }
                $sel = $script:SpanVlanDropdown.SelectedItem
                if (-not $sel -or $sel -eq '') {
                    $grid.ItemsSource = $cached
                } else {
                    $grid.ItemsSource = $cached | Where-Object { $_.VLAN -eq $sel }
                }
            }.GetNewClosure())
        }

        if ($script:SpanRefreshButton) {
            $script:SpanRefreshButton.Add_Click({
                try {
                    Invoke-StateTraceParsing
                } catch [System.Management.Automation.CommandNotFoundException] {
                    Write-Error "Invoke-StateTraceParsing not found (module load failed)"
                }

                $catalog = $null
                try { $catalog = Get-DeviceSummaries } catch [System.Management.Automation.CommandNotFoundException] { $catalog = $null } catch { $catalog = $null }
                try {
                    $hostList = if ($catalog -and $catalog.PSObject.Properties['Hostnames']) { $catalog.Hostnames } else { $null }
                    if ($hostList) {
                        Initialize-DeviceFilters -Hostnames $hostList -Window $Window
                    } else {
                        Initialize-DeviceFilters -Window $Window
                    }
                } catch [System.Management.Automation.CommandNotFoundException] {
                } catch {}
                try { Update-DeviceFilter } catch [System.Management.Automation.CommandNotFoundException] { }
                $currentHost = $Window.FindName('HostnameDropdown').SelectedItem
                if ($currentHost) { Get-SpanInfo $currentHost }
            }.GetNewClosure())
        }

        if ($script:SpanDiagnosticsButton) {
            $script:SpanDiagnosticsButton.Add_Click({
                try {
                    Show-SpanDiagnostics
                } catch {
                    Write-Warning ("Span diagnostics failed: {0}" -f $_.Exception.Message)
                }
            }.GetNewClosure())
        }

        $script:SpanHandlersRegistered = $true
    }
}

function Get-SpanInfo {
    [CmdletBinding()]
    param([string]$Hostname)

    if (-not (Ensure-SpanViewControls)) {
        return
    }

    Import-SpanRepositoryModule

    if ([string]::IsNullOrWhiteSpace(($Hostname))) {
        Reset-SpanViewState
        return
    }

    $targetHost = ('' + $Hostname).Trim()
    $siteCode = $null
    if (-not [string]::IsNullOrWhiteSpace($targetHost)) {
        $parts = $targetHost -split '-', 2
        if ($parts.Count -gt 0) { $siteCode = $parts[0] }
    }
    try {
        $data = Get-SpanningTreeInfo -Hostname $targetHost
    } catch {
        $data = @()
    }

    if (-not $data) { $data = @() }

    try {
        $entryCount = @($data).Count
        TelemetryModule\Write-SpanDebugLog -Message ("Host={0} Rows={1}" -f $targetHost, $entryCount) -UseTemp -Prefix 'Fetch'
    } catch { }

    $rowsCopy = @($data)
    $script:SpanLastRows = $rowsCopy
    # LANDMARK: ST-D-007 span usage vlan count
    $vlanCount = 0
    try {
        $vlanCount = @(
            $rowsCopy |
                Where-Object { $_ -and $_.PSObject.Properties['VLAN'] -and ('' + $_.VLAN).Trim() -ne '' } |
                ForEach-Object { '' + $_.VLAN } |
                Select-Object -Unique
        ).Count
    } catch { $vlanCount = 0 }

    # LANDMARK: ST-D-004 span telemetry
    try {
        TelemetryModule\Write-StTelemetryEvent -Name 'UserAction' -Payload @{
            Action    = 'SpanInfo'
            Hostname  = $targetHost
            Site      = $siteCode
            RowsBound = $rowsCopy.Count
            Timestamp = (Get-Date).ToString('o')
        }
    } catch [System.Management.Automation.CommandNotFoundException] {
    } catch { }

    # LANDMARK: ST-D-007 span usage telemetry
    try {
        TelemetryModule\Write-StTelemetryEvent -Name 'UserAction' -Payload @{
            Action    = 'SpanViewUsage'
            Hostname  = $targetHost
            Site      = $siteCode
            VlanCount = $vlanCount
            RowsBound = $rowsCopy.Count
            Timestamp = (Get-Date).ToString('o')
        }
    } catch [System.Management.Automation.CommandNotFoundException] {
    } catch { }

    $gridRef = $script:SpanGridControl
    $dropdownRef = $script:SpanVlanDropdown
    $statusLabelRef = $script:SpanStatusLabel
    $samplePreviewRef = $script:SpanSamplePreview

    Invoke-SpanDispatcher -Action {
        param($gridRef,$dropdownRef,$statusLabelRef,$samplePreviewRef,$rowsCopy,$targetHost,$diagAction)
        if (-not $gridRef) { return }
        $gridRef.ItemsSource = $rowsCopy
        $gridRef.Tag = $rowsCopy

        if ($dropdownRef) {
            $vset = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            foreach ($row in $rowsCopy) {
                if (-not $row) { continue }
                $v = $row.VLAN
                if ($null -ne $v -and ('' + $v).Trim() -ne '') {
                    [void]$vset.Add(('' + $v))
                }
            }
            $instances = [System.Collections.Generic.List[string]]::new($vset)
            $instances.Sort([System.StringComparer]::OrdinalIgnoreCase)
            try {
                FilterStateModule\Set-DropdownItems -Control $dropdownRef -Items (@('') + $instances)
            } catch { }
        }
        if ($statusLabelRef) {
            $timestamp = (Get-Date).ToString('HH:mm:ss')
            $statusLabelRef.Text = ("Rows: {0} (Updated {1})" -f $rowsCopy.Count, $timestamp)
            & $diagAction ("Status label updated: Host={0} Text='{1}'" -f $targetHost, $statusLabelRef.Text)
        } else {
            & $diagAction "SpanStatusLabel missing when updating host $targetHost"
        }

        $preview = $rowsCopy | Select-Object -First 3
        $previewText = ($preview | ForEach-Object {
            "VLAN=$($_.VLAN);RootSwitch=$($_.RootSwitch);Role=$($_.Role);Upstream=$($_.Upstream)"
        }) -join ' | '
        & $diagAction ("Grid bound rows: Host={0} Count={1} Preview={2}" -f $targetHost, $rowsCopy.Count, $previewText)
        if ($samplePreviewRef) {
            if ($preview) {
                $sampleText = ($preview | ForEach-Object {
                    "VLAN {0} via {1} ({2})" -f $_.VLAN, $_.Upstream, $_.Role
                }) -join "  |  "
                $samplePreviewRef.Text = $sampleText
            } else {
                $samplePreviewRef.Text = 'No sample rows available.'
            }
        }
    } -ArgumentList $gridRef,$dropdownRef,$statusLabelRef,$samplePreviewRef,$rowsCopy,$targetHost,$script:WriteSpanDiagAction | Out-Null

    try {
        $count = $rowsCopy.Count
        TelemetryModule\Write-SpanDebugLog -Message ("Host={0} Rows={1}" -f $targetHost, $count) -Prefix 'UI'
    } catch { }

    $script:SpanLastHostname = $targetHost
    $script:SpanLastRefresh = Get-Date
}

function Get-SpanViewSnapshot {
    [CmdletBinding()]
    param(
        [switch]$IncludeRows,
        [int]$SampleCount = 5
    )

    if ($SampleCount -le 0) { $SampleCount = 5 }

    $snapshot = [ordered]@{
        ViewLoaded     = $false
        Site           = $null
        Hostname       = $script:SpanLastHostname
        LastRefreshed  = $script:SpanLastRefresh
        RowCount       = 0
        CachedRowCount = 0
        SelectedVlan   = $null
        SampleRows     = @()
        UsedLastRows   = $false
        StatusText     = $null
    }

    try {
        $location = FilterStateModule\Get-SelectedLocation -Window $global:window
        if ($location -and $location.Site) {
            $siteText = '' + $location.Site
            if (-not [string]::IsNullOrWhiteSpace($siteText)) {
                $snapshot.Site = $siteText
            }
        }
    } catch { }

    if (-not (Ensure-SpanViewControls)) {
        Write-SpanDiag "Get-SpanViewSnapshot: controls unavailable."
        return [pscustomobject]$snapshot
    }

    $gridRefSnapshot = $script:SpanGridControl
    $dropdownRefSnapshot = $script:SpanVlanDropdown
    $result = Invoke-SpanDispatcher -Action {
        param($gridRefSnapshot,$dropdownRefSnapshot)
        $rows = @()
        $cachedRows = @()
        if ($gridRefSnapshot -and $gridRefSnapshot.ItemsSource) { $rows = @($gridRefSnapshot.ItemsSource) }
        if ($gridRefSnapshot -and $gridRefSnapshot.Tag) { $cachedRows = @($gridRefSnapshot.Tag) }
        $selected = $null
        if ($dropdownRefSnapshot) {
            try { $selected = $dropdownRefSnapshot.SelectedItem } catch { $selected = $null }
        }
        [pscustomobject]@{
            Rows       = $rows
            CachedRows = $cachedRows
            Selected   = $selected
        }
    } -ArgumentList $gridRefSnapshot,$dropdownRefSnapshot

    if ($result) {
        $snapshot.ViewLoaded = $true
        $snapshot.RowCount = @($result.Rows).Count
        $snapshot.CachedRowCount = @($result.CachedRows).Count
        $snapshot.SelectedVlan = $result.Selected
        if ($IncludeRows) {
            $snapshot.SampleRows = @($result.Rows | Select-Object -First $SampleCount)
        }
        $label = $null
        try { $label = $script:SpanStatusLabel } catch { $label = $null }
        if ($label -and $label.Text) {
            $snapshot.StatusText = $label.Text
        } else {
            Write-SpanDiag "Get-SpanViewSnapshot: status label unavailable or empty."
        }
    }

    if (($snapshot.RowCount -le 0) -and $script:SpanLastRows -and @($script:SpanLastRows).Count -gt 0) {
        $snapshot.RowCount = @($script:SpanLastRows).Count
        $snapshot.CachedRowCount = $snapshot.RowCount
        if ($IncludeRows) {
            $snapshot.SampleRows = @($script:SpanLastRows | Select-Object -First $SampleCount)
        }
        $snapshot.UsedLastRows = $true
        if (-not $snapshot.StatusText) {
            $snapshot.StatusText = ("Rows: {0} (cached)" -f $snapshot.RowCount)
        }
        Write-SpanDiag ("Get-SpanViewSnapshot used cached rows ({0})." -f $snapshot.RowCount)
    }

    try {
        TelemetryModule\Write-StTelemetryEvent -Name 'UserAction' -Payload @{
            Action    = 'SpanSnapshot'
            Hostname  = $snapshot.Hostname
            Site      = $snapshot.Site
            RowsBound = $snapshot.RowCount
            Timestamp = (Get-Date).ToString('o')
        }
    } catch [System.Management.Automation.CommandNotFoundException] {
    } catch { }

    return [pscustomobject]$snapshot
}

function Show-SpanDiagnostics {
    $snapshot = Get-SpanViewSnapshot -IncludeRows -SampleCount 5
    $host = if ($snapshot.Hostname) { $snapshot.Hostname } else { '<none>' }
    $status = if ($snapshot.StatusText) { $snapshot.StatusText } else { 'N/A' }
    $usedCache = if ($snapshot.UsedLastRows) { 'Yes' } else { 'No' }
    $samples = @()
    foreach ($row in $snapshot.SampleRows) {
        $samples += ("VLAN={0} Root={1} Role={2} Upstream={3}" -f $row.VLAN, $row.RootSwitch, $row.Role, $row.Upstream)
    }
    if (-not $samples) { $samples = @('<no sample rows>') }

    $message = @(
        "Host: $host",
        "Rows: $($snapshot.RowCount)",
        "Cached Rows: $($snapshot.CachedRowCount)",
        "Used Cached Rows: $usedCache",
        "Status: $status",
        "Samples:",
        "  " + ($samples -join "`n  ")
    ) -join "`n"

    Write-SpanDiag ("Diagnostics | Host={0} Rows={1} Cache={2} UsedCache={3}" -f $host, $snapshot.RowCount, $snapshot.CachedRowCount, $usedCache)
    try {
        $logDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'Logs\Debug'
        if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
        $diagPath = Join-Path $logDir 'SpanDiag.log'
        Add-Content -Path $diagPath -Value ("{0}`t{1}" -f (Get-Date).ToString('s'), $message)
    } catch { }

    $app = [System.Windows.Application]::Current
    if ($app -and $app.MainWindow) {
        [System.Windows.MessageBox]::Show($app.MainWindow, $message, "Span Diagnostics")
    } else {
        [System.Windows.MessageBox]::Show($message, "Span Diagnostics")
    }
}

Export-ModuleMember -Function New-SpanView, Get-SpanInfo, Get-SpanViewSnapshot, Show-SpanDiagnostics




function Write-SpanDiag {
    param([string]$Message)
    & $script:WriteSpanDiagAction $Message
}
