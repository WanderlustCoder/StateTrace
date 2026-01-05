Set-StrictMode -Version Latest

function script:Import-LocalStateTraceModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ModuleName,
        [Parameter(Mandatory)][string]$ModuleFileName,
        [switch]$Optional
    )

    if (Get-Module -Name $ModuleName -ErrorAction SilentlyContinue) {
        return $true
    }

    $modPath = Join-Path -Path $PSScriptRoot -ChildPath $ModuleFileName
    if (-not (Test-Path -LiteralPath $modPath)) {
        if ($Optional) { return $false }
        throw "Module file not found at $modPath"
    }

    Import-Module -Name $modPath -Force -Global -ErrorAction Stop | Out-Null
    return $true
}

#region Port Reorg Settings (ST-D-012)

function script:Get-PortReorgSettings {
    <#
    .SYNOPSIS
    Loads Port Reorg settings from StateTraceSettings.json.
    #>
    [CmdletBinding()]
    param()

    $defaults = @{
        PagingEnabled        = $false
        PageSize             = 12
        LastPageByHost       = @{}
        ShowModuleBoundaries = $true
        AnimationsEnabled    = $true
    }

    try {
        script:Import-LocalStateTraceModule -ModuleName 'MainWindow.Services' -ModuleFileName 'MainWindow.Services.psm1' -Optional | Out-Null
        $allSettings = MainWindow.Services\Get-StateTraceSettings
        if ($allSettings -and $allSettings.ContainsKey('PortReorg')) {
            $portReorg = $allSettings['PortReorg']
            if ($portReorg -is [hashtable]) {
                foreach ($key in $defaults.Keys) {
                    if ($portReorg.ContainsKey($key)) {
                        $defaults[$key] = $portReorg[$key]
                    }
                }
            }
            elseif ($portReorg.PSObject.Properties) {
                foreach ($key in $defaults.Keys) {
                    if ($portReorg.PSObject.Properties[$key]) {
                        $defaults[$key] = $portReorg.$key
                    }
                }
            }
        }
    }
    catch {
        # Return defaults on error
    }

    return [pscustomobject]$defaults
}

function script:Save-PortReorgSettings {
    <#
    .SYNOPSIS
    Saves Port Reorg settings to StateTraceSettings.json.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Settings
    )

    try {
        script:Import-LocalStateTraceModule -ModuleName 'MainWindow.Services' -ModuleFileName 'MainWindow.Services.psm1' -Optional | Out-Null
        $allSettings = MainWindow.Services\Get-StateTraceSettings
        if (-not $allSettings) { $allSettings = @{} }
        $allSettings['PortReorg'] = $Settings
        MainWindow.Services\Set-StateTraceSettings -Settings $allSettings | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

function script:Get-PortModuleGroup {
    <#
    .SYNOPSIS
    Extracts module group from port name for boundary detection.
    .EXAMPLE
    Get-PortModuleGroup -Port 'Gi1/0/12' returns 'Gi1/0'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Port
    )

    $p = ('' + $Port).Trim()
    if ([string]::IsNullOrWhiteSpace($p)) { return '' }

    # Pattern: Gi1/0/x -> "Gi1/0", Te2/0/x -> "Te2/0"
    if ($p -match '^([A-Za-z]+)(\d+)/(\d+)/') {
        return ('{0}{1}/{2}' -f $Matches[1], $Matches[2], $Matches[3])
    }

    # Pattern: Ethernet1/x -> "Ethernet1/"
    if ($p -match '^([A-Za-z]+)(\d+)/') {
        return ('{0}{1}/' -f $Matches[1], $Matches[2])
    }

    return ''
}

#endregion

# LANDMARK: ST-D-011 paging helper
function Get-PortReorgPageSlice {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IList]$OrderedRows,
        [Parameter()][int]$PageSize = 12,
        [Parameter()][int]$PageNumber = 1
    )

    $total = 0
    try { $total = $OrderedRows.Count } catch { $total = 0 }
    if ($PageSize -lt 1) { $PageSize = 12 }

    $pageCount = 1
    if ($total -gt 0) {
        $pageCount = [int][Math]::Ceiling($total / [double]$PageSize)
    }
    if ($pageCount -lt 1) { $pageCount = 1 }

    if ($PageNumber -lt 1) { $PageNumber = 1 }
    if ($PageNumber -gt $pageCount) { $PageNumber = $pageCount }

    $startIndex = ($PageNumber - 1) * $PageSize
    if ($startIndex -lt 0) { $startIndex = 0 }
    if ($startIndex -ge $total) { $startIndex = [Math]::Max(0, $total - 1) }

    $endIndex = -1
    if ($total -gt 0) {
        $endIndex = [Math]::Min($total - 1, $startIndex + $PageSize - 1)
    }

    $visibleRows = @()
    if ($total -gt 0 -and $endIndex -ge $startIndex) {
        for ($i = $startIndex; $i -le $endIndex; $i++) {
            $visibleRows += $OrderedRows[$i]
        }
    }

    return [pscustomobject]@{
        PageNumber = $PageNumber
        PageCount  = $pageCount
        StartIndex = $startIndex
        EndIndex   = $endIndex
        VisibleRows = $visibleRows
    }
}

function Show-PortReorgWindow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Windows.Window]$OwnerWindow,
        [Parameter(Mandatory)][string]$Hostname,
        [switch]$SuppressDialogs
    )

    $hostTrim = ('' + $Hostname).Trim()
    $suppressDialogsResolved = $false
    if ($SuppressDialogs.IsPresent) {
        $suppressDialogsResolved = $true
    } else {
        $globalSetting = $null
        try { $globalSetting = Get-Variable -Name StateTraceSuppressDialogs -Scope Global -ErrorAction SilentlyContinue } catch { $globalSetting = $null }
        if ($globalSetting -and $null -ne $globalSetting.Value) {
            try { if ([bool]$globalSetting.Value) { $suppressDialogsResolved = $true } } catch { }
        }
        if (-not $suppressDialogsResolved) {
            $envValue = $env:STATETRACE_SUPPRESS_DIALOGS
            if (-not [string]::IsNullOrWhiteSpace($envValue) -and $envValue -match '^(1|true|yes)$') {
                $suppressDialogsResolved = $true
            }
        }
        if (-not $suppressDialogsResolved) {
            try { if (-not [System.Environment]::UserInteractive) { $suppressDialogsResolved = $true } } catch { }
        }
    }
    if ([string]::IsNullOrWhiteSpace($hostTrim)) {
        [System.Windows.MessageBox]::Show('No hostname selected.') | Out-Null   
        return
    }

    $xamlPath = Join-Path -Path $PSScriptRoot -ChildPath '..\Views\PortReorgWindow.xaml'
    $xamlPath = [System.IO.Path]::GetFullPath($xamlPath)
    if (-not (Test-Path -LiteralPath $xamlPath)) {
        [System.Windows.MessageBox]::Show(("Port reorg window XAML not found at {0}" -f $xamlPath)) | Out-Null
        return
    }

    try {
        script:Import-LocalStateTraceModule -ModuleName 'PortReorgModule' -ModuleFileName 'PortReorgModule.psm1' | Out-Null
    } catch {
        [System.Windows.MessageBox]::Show(("Failed to load PortReorgModule: {0}" -f $_.Exception.Message)) | Out-Null
        return
    }

    try {
        script:Import-LocalStateTraceModule -ModuleName 'DeviceRepositoryModule' -ModuleFileName 'DeviceRepositoryModule.psm1' | Out-Null
    } catch {
        [System.Windows.MessageBox]::Show(("Failed to load DeviceRepositoryModule: {0}" -f $_.Exception.Message)) | Out-Null
        return
    }

    try {
        script:Import-LocalStateTraceModule -ModuleName 'PortNormalization' -ModuleFileName 'PortNormalization.psm1' -Optional | Out-Null
    } catch {
        # Optional: used only to compute stable port ordering keys when PortSort is missing.
    }

    $win = $null
    try {
        $xaml = Get-Content -LiteralPath $xamlPath -Raw
        $reader = New-Object System.Xml.XmlTextReader (New-Object System.IO.StringReader($xaml))
        try {
            $win = [Windows.Markup.XamlReader]::Load($reader)
        } finally {
            if ($reader) { $reader.Dispose() }
        }
    } catch {
        [System.Windows.MessageBox]::Show(("Failed to load PortReorgWindow: {0}" -f $_.Exception.Message)) | Out-Null
        return
    }

    $win.Owner = $OwnerWindow

    $hostnameText = $win.FindName('ReorgHostnameText')
    $vendorText = $win.FindName('ReorgVendorText')
    $statusText = $win.FindName('ReorgStatusText')
    $chunkBy12 = $win.FindName('ReorgChunkBy12CheckBox')
    $chunkSizeBox = $win.FindName('ReorgChunkSizeBox')
    $pagedViewCheckBox = $win.FindName('ReorgPagedViewCheckBox')
    $pagePrevButton = $win.FindName('ReorgPagePrevButton')
    $pageComboBox = $win.FindName('ReorgPageComboBox')
    $pageNextButton = $win.FindName('ReorgPageNextButton')
    $pageInfoText = $win.FindName('ReorgPageInfoText')

    $parkingList = $win.FindName('ReorgParkingList')
    $grid = $win.FindName('ReorgGrid')
    $suggestBtn = $win.FindName('ReorgSuggestButton')
    $resetBtn = $win.FindName('ReorgResetButton')
    $generateBtn = $win.FindName('ReorgGenerateButton')
    $copyChangeBtn = $win.FindName('ReorgCopyChangeButton')
    $copyRollbackBtn = $win.FindName('ReorgCopyRollbackButton')
    $saveChangeBtn = $win.FindName('ReorgSaveChangeButton')
    $saveRollbackBtn = $win.FindName('ReorgSaveRollbackButton')
    $closeBtn = $win.FindName('ReorgCloseButton')
    $changeBox = $win.FindName('ReorgChangeScriptBox')
    $rollbackBox = $win.FindName('ReorgRollbackScriptBox')

    # ST-D-012: New controls for enhanced paging
    $pageSizeBox = $win.FindName('ReorgPageSizeBox')
    $quickJumpBox = $win.FindName('ReorgQuickJumpBox')
    $searchBox = $win.FindName('ReorgSearchBox')
    $searchClearBtn = $win.FindName('ReorgSearchClearButton')
    $undoBtn = $win.FindName('ReorgUndoButton')
    $redoBtn = $win.FindName('ReorgRedoButton')
    $selectPageBtn = $win.FindName('ReorgSelectPageButton')
    $clearPageBtn = $win.FindName('ReorgClearPageButton')
    $moveToMenuItem = $win.FindName('ReorgMoveToMenuItem')
    $clearLabelMenuItem = $win.FindName('ReorgClearLabelMenuItem')
    $swapLabelsMenuItem = $win.FindName('ReorgSwapLabelsMenuItem')

    if ($hostnameText) { $hostnameText.Text = $hostTrim }

    $parkingLabels = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    if ($parkingList) {
        try { $parkingList.ItemsSource = $parkingLabels } catch { }
    }

    $newParkingItem = {
        param(
            [Parameter(Mandatory)][string]$SourcePort,
            [Parameter()][AllowEmptyString()][string]$Label
        )

        $src = ('' + $SourcePort).Trim()
        $lbl = '' + $Label
        return [PSCustomObject]@{
            SourcePort = $src
            Label      = $lbl
        }
    }.GetNewClosure()

    $interfaces = @()
    try {
        $interfaces = @(DeviceRepositoryModule\Get-InterfaceInfo -Hostname $hostTrim)
    } catch {
        $interfaces = @()
    }
    if (-not $interfaces -or $interfaces.Count -eq 0) {
        [System.Windows.MessageBox]::Show(("No interface rows found for {0}. Parse logs or Load from DB first." -f $hostTrim)) | Out-Null
        return
    }

    $vendor = 'Cisco'
    try {
        $scripts = PortReorgModule\New-PortReorgScripts -Hostname $hostTrim -PlanRows @([pscustomobject]@{ SourcePort = $interfaces[0].Port; TargetPort = $interfaces[0].Port; NewLabel = $interfaces[0].Name }) -BaselineInterfaces $interfaces -ChunkSize 0
        if ($scripts -and $scripts.Vendor) { $vendor = '' + $scripts.Vendor }
    } catch {
        $vendor = 'Cisco'
    }
    if ($vendorText) { $vendorText.Text = $vendor }

    # Build plan rows
    $labelByPort = @{}
    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($iface in $interfaces) {
        if (-not $iface) { continue }
        $port = ('' + $iface.Port).Trim()
        if ([string]::IsNullOrWhiteSpace($port)) { continue }
        $label = ''
        try { $label = '' + $iface.Name } catch { $label = '' }
        $portSort = ''
        try {
            $prop = $iface.PSObject.Properties['PortSort']
            if ($prop -and $prop.Value) { $portSort = '' + $prop.Value }
        } catch { $portSort = '' }
        if ([string]::IsNullOrWhiteSpace($portSort)) {
            try {
                $portSort = PortNormalization\Get-PortSortKey -Port $port
            } catch [System.Management.Automation.CommandNotFoundException] {
                $portSort = ''
            } catch { $portSort = '' }
        }
        if ([string]::IsNullOrWhiteSpace($portSort)) { $portSort = $port }
        if (-not $labelByPort.ContainsKey($port)) {
            $labelByPort[$port] = $label
        }
        $rows.Add([PSCustomObject]@{
            TargetPort       = $port
            TargetPortSort   = $portSort
            SourcePort       = $port
            CurrentLabel     = $label
            NewLabel         = $label
            LabelState       = 'Unchanged'
            IsModuleBoundary = $false   # ST-D-012: visual boundary marker
            IsSearchMatch    = $false   # ST-D-012: search highlight marker
        }) | Out-Null
    }

    $baselineRows = @()
    try { $baselineRows = @($rows.ToArray() | ForEach-Object { [pscustomobject]@{ TargetPort = $_.TargetPort; SourcePort = $_.SourcePort; CurrentLabel = $_.CurrentLabel; NewLabel = $_.NewLabel } }) } catch { $baselineRows = @() }

    $gridView = $null
    if ($grid) {
        $grid.ItemsSource = $rows
        try {
            $gridView = [System.Windows.Data.CollectionViewSource]::GetDefaultView($grid.ItemsSource)
            if ($gridView) {
                $gridView.SortDescriptions.Clear()
                $gridView.SortDescriptions.Add((New-Object System.ComponentModel.SortDescription -ArgumentList 'TargetPortSort', ([System.ComponentModel.ListSortDirection]::Ascending))) | Out-Null
                $gridView.SortDescriptions.Add((New-Object System.ComponentModel.SortDescription -ArgumentList 'TargetPort', ([System.ComponentModel.ListSortDirection]::Ascending))) | Out-Null
                $gridView.Refresh()
            }
        } catch {
            $gridView = $null
        }
    }

    $availablePorts = @($rows | ForEach-Object { $_.TargetPort })

    $pagingIsAvailable = $false
    try {
        $pagingIsAvailable = ($null -ne $pagedViewCheckBox -and $null -ne $pagePrevButton -and $null -ne $pageComboBox -and $null -ne $pageNextButton -and $null -ne $pageInfoText)
    } catch {
        $pagingIsAvailable = $false
    }

    $orderedRowsList = [System.Collections.Generic.List[object]]::new()
    try {
        $sorted = @($rows.ToArray() | Sort-Object TargetPortSort, TargetPort)
        foreach ($r in $sorted) { $orderedRowsList.Add($r) | Out-Null }
    } catch {
        try {
            foreach ($r in $rows) { $orderedRowsList.Add($r) | Out-Null }
        } catch { }
    }
    # Keep $orderedRows as reference for backward compatibility
    $orderedRows = $orderedRowsList

    # ST-D-012: Update module boundary markers based on port grouping
    $updateModuleBoundaries = {
        $prevGroup = ''
        foreach ($row in $orderedRows) {
            $port = ''
            try { $port = '' + $row.TargetPort } catch { $port = '' }
            $group = script:Get-PortModuleGroup -Port $port
            $row.IsModuleBoundary = (-not [string]::IsNullOrWhiteSpace($group) -and $group -ne $prevGroup)
            $prevGroup = $group
        }
    }.GetNewClosure()

    try { & $updateModuleBoundaries } catch { }

    $visibleRows = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    $pageChoices = [System.Collections.ObjectModel.ObservableCollection[object]]::new()

    $pagingState = [pscustomobject]@{
        Enabled           = $false
        PageSize          = 12
        PageNumber        = 1
        PageCount         = 1
        SuppressPageEvent = $false
    }

    if ($pagingIsAvailable) {
        try { $pageComboBox.ItemsSource = $pageChoices } catch { }
        try { $pageComboBox.DisplayMemberPath = 'Label' } catch { }
        try { $pageComboBox.SelectedValuePath = 'Page' } catch { }
    }

    $setPagingControlsVisible = {
        param([bool]$Enabled)
        if (-not $pagingIsAvailable) { return }

        $vis = if ($Enabled) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
        foreach ($ctrl in @($pagePrevButton, $pageComboBox, $pageNextButton, $pageInfoText)) {
            if ($ctrl) {
                try { $ctrl.Visibility = $vis } catch { }
            }
        }
    }.GetNewClosure()

    $rebuildPageChoices = {
        if (-not $pagingIsAvailable) { return }

        $total = $orderedRows.Count
        $pageSize = [int]$pagingState.PageSize
        if ($pageSize -lt 1) {
            $pageSize = 12
            $pagingState.PageSize = 12
        }

        $pageCount = 1
        if ($total -gt 0) {
            $pageCount = [int][Math]::Ceiling($total / [double]$pageSize)
        }
        if ($pageCount -lt 1) { $pageCount = 1 }
        $pagingState.PageCount = $pageCount

        try { $pageChoices.Clear() } catch { }
        for ($page = 1; $page -le $pageCount; $page++) {
            $startIndex = ($page - 1) * $pageSize
            $endIndex = [Math]::Min($total - 1, $startIndex + $pageSize - 1)

            $startPort = ''
            $endPort = ''
            $changeCount = 0
            $parkedCount = 0
            try {
                if ($total -gt 0 -and $startIndex -ge 0 -and $startIndex -lt $total) {
                    $startPort = ('' + $orderedRows[$startIndex].TargetPort).Trim()
                }
                if ($total -gt 0 -and $endIndex -ge 0 -and $endIndex -lt $total) {
                    $endPort = ('' + $orderedRows[$endIndex].TargetPort).Trim()
                }
                # ST-D-012: Count changes and parked on this page
                for ($i = $startIndex; $i -le $endIndex -and $i -lt $total; $i++) {
                    $state = ''
                    try { $state = '' + $orderedRows[$i].LabelState } catch { $state = '' }
                    if ($state -eq 'Changed') { $changeCount++ }
                    elseif ($state -eq 'Parked') { $parkedCount++ }
                }
            } catch { }

            # ST-D-012: Build label with change indicator
            $indicator = ''
            if ($changeCount -gt 0 -and $parkedCount -gt 0) {
                $indicator = " ({0}+ {1}-)" -f $changeCount, $parkedCount
            } elseif ($changeCount -gt 0) {
                $indicator = " ({0}+)" -f $changeCount
            } elseif ($parkedCount -gt 0) {
                $indicator = " ({0}-)" -f $parkedCount
            }

            $label = if (-not [string]::IsNullOrWhiteSpace($startPort) -and -not [string]::IsNullOrWhiteSpace($endPort)) {
                ("{0}: {1} - {2}{3}" -f $page, $startPort, $endPort, $indicator)
            } else {
                ("Page {0}{1}" -f $page, $indicator)
            }

            try {
                $pageChoices.Add([pscustomobject]@{
                    Page       = $page
                    StartIndex = $startIndex
                    EndIndex   = $endIndex
                    Label      = $label
                }) | Out-Null
            } catch { }
        }

        if ($pagingState.PageNumber -lt 1) { $pagingState.PageNumber = 1 }
        if ($pagingState.PageNumber -gt $pageCount) { $pagingState.PageNumber = $pageCount }
    }.GetNewClosure()

    $getPageForRow = {
        param($Row)

        if (-not $Row) { return 1 }
        $target = ''
        try { $target = ('' + $Row.TargetPort).Trim() } catch { $target = '' }
        if ([string]::IsNullOrWhiteSpace($target)) { return 1 }

        $total = $orderedRows.Count
        for ($i = 0; $i -lt $total; $i++) {
            $rowTarget = ''
            try { $rowTarget = ('' + $orderedRows[$i].TargetPort).Trim() } catch { $rowTarget = '' }
            if ($rowTarget.Equals($target, [System.StringComparison]::OrdinalIgnoreCase)) {
                return ([int][Math]::Floor($i / [double]$pagingState.PageSize) + 1)
            }
        }

        return 1
    }.GetNewClosure()

    $updateVisibleRowsForCurrentPage = {
        $isEnabled = $false
        try { $isEnabled = [bool]$pagingState.Enabled } catch { $isEnabled = $false }
        if (-not $isEnabled) { return }

        # LANDMARK: ST-D-011 paging slice usage
        $rowCount = 0
        try { $rowCount = $orderedRows.Count } catch { $rowCount = 0 }

        $slice = Get-PortReorgPageSlice -OrderedRows $orderedRows -PageSize ([int]$pagingState.PageSize) -PageNumber ([int]$pagingState.PageNumber)
        $pagingState.PageNumber = $slice.PageNumber
        $pagingState.PageCount = $slice.PageCount

        try { $visibleRows.Clear() } catch { }
        foreach ($row in $slice.VisibleRows) {
            try { $visibleRows.Add($row) | Out-Null } catch { }
        }
    }.GetNewClosure()

    $updatePagingControls = {
        if (-not $pagingIsAvailable) { return }
        if (-not ($pagingState.Enabled -eq $true)) { return }

        $pageCount = [int]$pagingState.PageCount
        $pageNumber = [int]$pagingState.PageNumber
        $pageSize = [int]$pagingState.PageSize
        $total = $orderedRows.Count

        $startIndex = ($pageNumber - 1) * $pageSize
        $endIndex = [Math]::Min($total - 1, $startIndex + $pageSize - 1)

        $startPort = ''
        $endPort = ''
        try {
            if ($total -gt 0 -and $startIndex -ge 0 -and $startIndex -lt $total) {
                $startPort = ('' + $orderedRows[$startIndex].TargetPort).Trim()
            }
            if ($total -gt 0 -and $endIndex -ge 0 -and $endIndex -lt $total) {
                $endPort = ('' + $orderedRows[$endIndex].TargetPort).Trim()
            }
        } catch { }

        $range = if (-not [string]::IsNullOrWhiteSpace($startPort) -and -not [string]::IsNullOrWhiteSpace($endPort)) {
            ("{0} - {1}" -f $startPort, $endPort)
        } else {
            'No ports'
        }

        try { if ($pageInfoText) { $pageInfoText.Text = ("Page {0}/{1} ({2})" -f $pageNumber, $pageCount, $range) } } catch { }
        try { if ($pagePrevButton) { $pagePrevButton.IsEnabled = ($pageNumber -gt 1) } } catch { }
        try { if ($pageNextButton) { $pageNextButton.IsEnabled = ($pageNumber -lt $pageCount) } } catch { }
        try { if ($pageComboBox) { $pageComboBox.IsEnabled = ($pageCount -gt 1) } } catch { }

        if ($pageComboBox) {
            try {
                $pagingState.SuppressPageEvent = $true
                $pageComboBox.SelectedValue = $pageNumber
            } catch { } finally {
                $pagingState.SuppressPageEvent = $false
            }
        }
    }.GetNewClosure()

    # ST-D-012: Load settings from file
    $portReorgSettings = script:Get-PortReorgSettings

    if ($pagingIsAvailable) {
        # Load paging state from settings (with global variable fallback for backward compatibility)
        $initialPagingEnabled = $false
        try {
            $initialPagingEnabled = [bool]$portReorgSettings.PagingEnabled
        }
        catch {
            # Fallback to global variable
            if (Get-Variable -Name StateTracePortReorgPagingEnabled -Scope Global -ErrorAction SilentlyContinue) {
                try { $initialPagingEnabled = [bool]$global:StateTracePortReorgPagingEnabled } catch { }
            }
        }

        # Load page size from settings
        $initialPageSize = 12
        try {
            $size = [int]$portReorgSettings.PageSize
            if ($size -ge 1 -and $size -le 96) { $initialPageSize = $size }
        }
        catch { }
        $pagingState.PageSize = $initialPageSize

        # Load last page for this host
        try {
            $lastPages = $portReorgSettings.LastPageByHost
            if ($lastPages -and $lastPages[$hostTrim]) {
                $pagingState.PageNumber = [int]$lastPages[$hostTrim]
            }
        }
        catch { }

        if ($pagedViewCheckBox) {
            try { $pagedViewCheckBox.IsChecked = $initialPagingEnabled } catch { }
        }

        $pagingState.Enabled = ($initialPagingEnabled -eq $true)

        try { & $rebuildPageChoices } catch { }
        try { & $setPagingControlsVisible -Enabled ($pagingState.Enabled -eq $true) } catch { }
        if ($pagingState.Enabled -eq $true) {
            try { & $updateVisibleRowsForCurrentPage } catch { }
            try { & $updatePagingControls } catch { }
            # ST-D-012: Update grid to use visibleRows when paging is initially enabled
            try {
                $grid.ItemsSource = $null
                $grid.ItemsSource = $visibleRows
            } catch { }
        }
    }

    $getRowByTargetPort = {
        param([string]$TargetPort)
        $t = ('' + $TargetPort).Trim()
        if ([string]::IsNullOrWhiteSpace($t)) { return $null }
        foreach ($r in $rows) {
            try {
                $rt = ('' + $r.TargetPort).Trim()
                if ($rt.Equals($t, [System.StringComparison]::OrdinalIgnoreCase)) { return $r }
            } catch { }
        }
        return $null
    }.GetNewClosure()

    $getLabelStateForRow = {
        param($Row)

        $srcPort = ''
        try { $srcPort = ('' + $Row.SourcePort).Trim() } catch { $srcPort = '' }
        if ([string]::IsNullOrWhiteSpace($srcPort)) { return 'Parked' }

        $dstPort = ''
        try { $dstPort = ('' + $Row.TargetPort).Trim() } catch { $dstPort = '' }
        if ($dstPort -and -not $srcPort.Equals($dstPort, [System.StringComparison]::OrdinalIgnoreCase)) { return 'Changed' }

        $current = ''
        try { $current = ('' + $Row.CurrentLabel).Trim() } catch { $current = '' }
        $new = ''
        try { $new = ('' + $Row.NewLabel).Trim() } catch { $new = '' }

        if ([string]::IsNullOrWhiteSpace($new) -and -not [string]::IsNullOrWhiteSpace($current)) { return 'Parked' }
        if ($current.Equals($new, [System.StringComparison]::OrdinalIgnoreCase)) { return 'Unchanged' }
        return 'Changed'
    }

    $updateLabelStates = {
        foreach ($r in $rows) {
            try { $r.LabelState = & $getLabelStateForRow $r } catch { }
        }
    }.GetNewClosure()

    $uiState = [PSCustomObject]@{
        ScriptsAreCurrent = $false
    }

    $updateScriptControls = {
        $planComplete = $true
        $sources = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($r in $rows) {
            $src = ('' + $r.SourcePort).Trim()
            if ([string]::IsNullOrWhiteSpace($src)) {
                $lbl = ''
                try { $lbl = ('' + $r.NewLabel).Trim() } catch { $lbl = '' }
                if (-not [string]::IsNullOrWhiteSpace($lbl)) { $planComplete = $false; break }
                continue
            }
            if (-not ($sources.Add($src))) { $planComplete = $false; break }
            if (-not $labelByPort.ContainsKey($src)) { $planComplete = $false; break }
        }

        try {
            if ($generateBtn) {
                $generateBtn.IsEnabled = $planComplete
                $generateBtn.ToolTip = if ($planComplete) {
                    'Generate change + rollback scripts.'
                } else {
                    'Assign profiles to ports (FromPort unique) and leave labels blank when FromPort is empty.'
                }
            }
        } catch { }

        $hasChange = $false
        $hasRollback = $false
        try { $hasChange = ($changeBox -and -not [string]::IsNullOrWhiteSpace($changeBox.Text)) } catch { $hasChange = $false }
        try { $hasRollback = ($rollbackBox -and -not [string]::IsNullOrWhiteSpace($rollbackBox.Text)) } catch { $hasRollback = $false }

        $scriptsCurrent = $false
        try { $scriptsCurrent = ($uiState.ScriptsAreCurrent -eq $true) } catch { $scriptsCurrent = $false }
        try { if ($copyChangeBtn) { $copyChangeBtn.IsEnabled = ($scriptsCurrent -and $hasChange) } } catch { }
        try { if ($saveChangeBtn) { $saveChangeBtn.IsEnabled = ($scriptsCurrent -and $hasChange) } } catch { }
        try { if ($copyRollbackBtn) { $copyRollbackBtn.IsEnabled = ($scriptsCurrent -and $hasRollback) } } catch { }
        try { if ($saveRollbackBtn) { $saveRollbackBtn.IsEnabled = ($scriptsCurrent -and $hasRollback) } } catch { }
    }.GetNewClosure()

    $markScriptsDirty = {
        try { $uiState.ScriptsAreCurrent = $false } catch { }
        try { if ($changeBox) { $changeBox.Text = '' } } catch { }
        try { if ($rollbackBox) { $rollbackBox.Text = '' } } catch { }
        try { & $updateScriptControls } catch { }
    }.GetNewClosure()

    $refreshGrid = {
        if (-not $grid) { return }
        try { & $updateLabelStates } catch { }

        # PSCustomObject rows do not notify property changes; force a rebind so
        # drag/drop updates immediately reflect in the DataGrid visuals.
        try {
            $selectedItem = $null
            try { $selectedItem = $grid.SelectedItem } catch { $selectedItem = $null }

            $itemsSource = $rows
            if ($pagingIsAvailable -and ($pagingState.Enabled -eq $true)) {
                try {
                    & $updateVisibleRowsForCurrentPage
                } catch {
                    & $setStatus ("Paging error: {0}" -f $_.Exception.Message) ''
                }
                $itemsSource = $visibleRows
                & $setStatus ("Page {0}/{1} ({2} of {3} ports)" -f $pagingState.PageNumber, $pagingState.PageCount, $visibleRows.Count, $orderedRows.Count) ''
            }

            $grid.ItemsSource = $null
            $grid.ItemsSource = $itemsSource

            $gridView = $null
            try {
                $gridView = [System.Windows.Data.CollectionViewSource]::GetDefaultView($grid.ItemsSource)
                if ($gridView) {
                    $gridView.SortDescriptions.Clear()
                    $gridView.SortDescriptions.Add((New-Object System.ComponentModel.SortDescription -ArgumentList 'TargetPortSort', ([System.ComponentModel.ListSortDirection]::Ascending))) | Out-Null
                    $gridView.SortDescriptions.Add((New-Object System.ComponentModel.SortDescription -ArgumentList 'TargetPort', ([System.ComponentModel.ListSortDirection]::Ascending))) | Out-Null
                    $gridView.Refresh()
                }
            } catch {
                $gridView = $null
            }

            if ($selectedItem) {
                try { $grid.SelectedItem = $selectedItem } catch { }
                try { $grid.ScrollIntoView($selectedItem) } catch { }
            }
        } catch { }

        try { if ($gridView) { $gridView.Refresh() } } catch { }
        try { $grid.Items.Refresh() } catch { }
        try { $grid.UpdateLayout() } catch { }
        try { & $updateScriptControls } catch { }
        try { & $updatePagingControls } catch { }
    }.GetNewClosure()

    $setStatus = {
        param([string]$Message, [string]$ColorKey)
        if (-not $statusText) { return }
        $statusText.Text = $Message
        # Optional: adjust Foreground based on theme keys when provided
        try {
            if ($ColorKey -and $win.Resources.Contains($ColorKey)) {
                $statusText.Foreground = $win.Resources[$ColorKey]
            }
        } catch { }
    }.GetNewClosure()

    # ST-D-012: Save settings helper
    $saveCurrentSettings = {
        try {
            $settings = @{
                PagingEnabled        = ($pagingState.Enabled -eq $true)
                PageSize             = [int]$pagingState.PageSize
                LastPageByHost       = @{}
                ShowModuleBoundaries = $true
                AnimationsEnabled    = $true
            }
            # Preserve existing LastPageByHost and add/update current host
            $existing = script:Get-PortReorgSettings
            if ($existing.LastPageByHost) {
                foreach ($key in $existing.LastPageByHost.Keys) {
                    $settings.LastPageByHost[$key] = $existing.LastPageByHost[$key]
                }
            }
            $settings.LastPageByHost[$hostTrim] = [int]$pagingState.PageNumber
            script:Save-PortReorgSettings -Settings $settings | Out-Null
        }
        catch { }
        # Keep global variable in sync for backward compatibility
        try { $global:StateTracePortReorgPagingEnabled = ($pagingState.Enabled -eq $true) } catch { }
    }.GetNewClosure()

    $setPagingEnabled = {
        param([bool]$Enabled)

        if (-not $pagingIsAvailable) { return }

        $selectedRow = $null
        try { if ($grid) { $selectedRow = $grid.SelectedItem } } catch { $selectedRow = $null }

        $pagingState.Enabled = ($Enabled -eq $true)

        try { & $rebuildPageChoices } catch { }
        try { & $setPagingControlsVisible -Enabled ($pagingState.Enabled -eq $true) } catch { }

        if ($pagingState.Enabled -eq $true) {
            if ($selectedRow) {
                try { $pagingState.PageNumber = & $getPageForRow $selectedRow } catch { $pagingState.PageNumber = 1 }
            }
            try { & $updateVisibleRowsForCurrentPage } catch { }
        }

        try { & $refreshGrid } catch { }
        try { & $updatePagingControls } catch { }

        # ST-D-012: Save to settings file
        try { & $saveCurrentSettings } catch { }
    }.GetNewClosure()

    #region ST-D-012: Undo/Redo History
    $historyState = [pscustomobject]@{
        UndoStack  = [System.Collections.Generic.Stack[object]]::new()
        RedoStack  = [System.Collections.Generic.Stack[object]]::new()
        MaxHistory = 50
    }

    $captureHistorySnapshot = {
        $snapshot = [System.Collections.Generic.List[object]]::new()
        foreach ($r in $rows) {
            $snapshot.Add([pscustomobject]@{
                TargetPort = '' + $r.TargetPort
                SourcePort = '' + $r.SourcePort
                NewLabel   = '' + $r.NewLabel
            }) | Out-Null
        }
        return $snapshot.ToArray()
    }.GetNewClosure()

    $pushUndo = {
        param([object[]]$Snapshot)
        if ($historyState.UndoStack.Count -ge $historyState.MaxHistory) {
            $arr = $historyState.UndoStack.ToArray()
            $historyState.UndoStack.Clear()
            for ($i = $arr.Count - 2; $i -ge 0; $i--) {
                $historyState.UndoStack.Push($arr[$i])
            }
        }
        $historyState.UndoStack.Push($Snapshot)
        $historyState.RedoStack.Clear()
    }.GetNewClosure()

    $applySnapshot = {
        param([object[]]$Snapshot)
        $byTarget = @{}
        foreach ($s in $Snapshot) {
            $byTarget[('' + $s.TargetPort).Trim()] = $s
        }
        foreach ($r in $rows) {
            $target = ('' + $r.TargetPort).Trim()
            if ($byTarget.ContainsKey($target)) {
                $s = $byTarget[$target]
                $r.SourcePort = $s.SourcePort
                $r.NewLabel = $s.NewLabel
            }
        }
    }.GetNewClosure()

    $undoAction = {
        if ($historyState.UndoStack.Count -eq 0) {
            & $setStatus 'Nothing to undo.' ''
            return
        }
        $currentSnapshot = & $captureHistorySnapshot
        $historyState.RedoStack.Push($currentSnapshot)
        $undoSnapshot = $historyState.UndoStack.Pop()
        & $applySnapshot $undoSnapshot
        & $markScriptsDirty
        & $refreshGrid
        & $setStatus 'Undone.' ''
    }.GetNewClosure()

    $redoAction = {
        if ($historyState.RedoStack.Count -eq 0) {
            & $setStatus 'Nothing to redo.' ''
            return
        }
        $currentSnapshot = & $captureHistorySnapshot
        $historyState.UndoStack.Push($currentSnapshot)
        $redoSnapshot = $historyState.RedoStack.Pop()
        & $applySnapshot $redoSnapshot
        & $markScriptsDirty
        & $refreshGrid
        & $setStatus 'Redone.' ''
    }.GetNewClosure()
    #endregion

    #region ST-D-012: Search State
    $searchState = [pscustomobject]@{
        CurrentFilter = ''
        MatchingPorts = @()
    }

    $applySearchFilter = {
        param([string]$SearchText)
        $filter = ('' + $SearchText).Trim()
        $searchState.CurrentFilter = $filter

        if ([string]::IsNullOrWhiteSpace($filter)) {
            $searchState.MatchingPorts = @()
            # Clear all search match flags
            foreach ($row in $rows) {
                try { $row.IsSearchMatch = $false } catch { }
            }
            & $refreshGrid
            & $setStatus '' ''
            return
        }

        $matches = [System.Collections.Generic.List[string]]::new()
        foreach ($row in $rows) {
            $label = ''
            try { $label = '' + $row.NewLabel } catch { $label = '' }
            $isMatch = ($label.IndexOf($filter, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
            try { $row.IsSearchMatch = $isMatch } catch { }
            if ($isMatch) {
                $matches.Add(('' + $row.TargetPort).Trim()) | Out-Null
            }
        }
        $searchState.MatchingPorts = $matches.ToArray()

        if ($matches.Count -gt 0 -and $pagingState.Enabled) {
            $firstMatchPort = $matches[0]
            foreach ($row in $orderedRows) {
                if (('' + $row.TargetPort).Trim() -eq $firstMatchPort) {
                    $page = & $getPageForRow $row
                    $pagingState.PageNumber = $page
                    break
                }
            }
        }
        & $refreshGrid
        & $setStatus ("{0} port(s) match '{1}'." -f $matches.Count, $filter) ''
    }.GetNewClosure()

    $quickJumpAction = {
        param([string]$PortName)
        if ([string]::IsNullOrWhiteSpace($PortName)) { return }
        $targetPort = $PortName.Trim()
        $total = $orderedRows.Count

        for ($i = 0; $i -lt $total; $i++) {
            $rowPort = ''
            try { $rowPort = ('' + $orderedRows[$i].TargetPort).Trim() } catch { $rowPort = '' }
            if ($rowPort.IndexOf($targetPort, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
                $targetPort.IndexOf($rowPort, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                $page = [int][Math]::Floor($i / [double]$pagingState.PageSize) + 1
                $pagingState.PageNumber = $page
                & $refreshGrid
                try {
                    $matchedRow = $orderedRows[$i]
                    $grid.SelectedItem = $matchedRow
                    $grid.ScrollIntoView($matchedRow)
                } catch { }
                & $setStatus ("Jumped to {0}." -f $rowPort) ''
                return
            }
        }
        & $setStatus ("Port '{0}' not found." -f $targetPort) ''
    }.GetNewClosure()

    $applyPageSize = {
        param([string]$SizeText)
        $size = 12
        [void][int]::TryParse($SizeText, [ref]$size)
        if ($size -lt 1) { $size = 1 }
        if ($size -gt 96) { $size = 96 }

        if ($size -ne $pagingState.PageSize) {
            $pagingState.PageSize = $size
            & $rebuildPageChoices
            if ($pagingState.PageNumber -gt $pagingState.PageCount) {
                $pagingState.PageNumber = $pagingState.PageCount
            }
            & $refreshGrid
            & $updatePagingControls
            try { & $saveCurrentSettings } catch { }
            & $setStatus ("Page size set to {0}." -f $size) ''
        } else {
            & $setStatus ("Page size unchanged ({0})." -f $size) ''
        }
    }.GetNewClosure()
    #endregion

    if ($grid) {
        $grid.Add_CellEditEnding({
            param($sender, $e)
            try {
                $headerText = ''
                try { $headerText = '' + $e.Column.Header } catch { $headerText = '' }
                if (-not $headerText.Equals('Label', [System.StringComparison]::OrdinalIgnoreCase)) { return }

                $row = $null
                try { $row = $e.Row.Item } catch { $row = $null }
                if (-not $row) { return }

                try { $row.LabelState = & $getLabelStateForRow $row } catch { }
                try { & $markScriptsDirty } catch { }
                try { & $refreshGrid } catch { }
            } catch {
            }
        }.GetNewClosure())

        $dragState = [pscustomobject]@{
            StartPoint         = $null
            SourceKind         = ''
            SourceRow          = $null
            SourceParkingIndex = -1
            SourceParkingItem  = $null
            LabelText          = ''
            IsDragging         = $false
            # ST-D-012: Cross-page drag auto-switch
            HoverTarget        = ''     # 'Prev', 'Next', or ''
            HoverTimer         = $null  # DispatcherTimer
        }

        $getVisualAncestor = {
            param(
                [Parameter(Mandatory)][object]$Start,
                [Parameter(Mandatory)][type]$AncestorType
            )

            $current = $Start
            while ($current -and -not ($current -is $AncestorType)) {
                try { $current = [System.Windows.Media.VisualTreeHelper]::GetParent($current) } catch { $current = $null }
            }
            return $current
        }.GetNewClosure()

        $dragPopup = New-Object System.Windows.Controls.Primitives.Popup
        $dragPopup.Placement = [System.Windows.Controls.Primitives.PlacementMode]::Relative
        $dragPopup.PlacementTarget = $win
        $dragPopup.AllowsTransparency = $true
        $dragPopup.IsHitTestVisible = $false
        $dragPopup.StaysOpen = $true

        $dragBorder = New-Object System.Windows.Controls.Border
        $dragBorder.Padding = New-Object System.Windows.Thickness 8,4,8,4
        $dragBorder.CornerRadius = New-Object System.Windows.CornerRadius 6
        $dragBorder.Opacity = 0.95
        $dragBorder.BorderThickness = New-Object System.Windows.Thickness 1
        try {
            $bg = $win.TryFindResource('Theme.Surface.Primary')
            if (-not $bg) { $bg = $win.TryFindResource('Theme.Template.Blue') }
            if ($bg) { $dragBorder.Background = $bg }
        } catch { }
        try {
            $bb = $win.TryFindResource('Theme.Input.Border')
            if ($bb) { $dragBorder.BorderBrush = $bb }
        } catch { }
        try {
            $shadow = New-Object System.Windows.Media.Effects.DropShadowEffect
            $shadow.Color = [System.Windows.Media.Colors]::Black
            $shadow.Opacity = 0.25
            $shadow.BlurRadius = 14
            $shadow.ShadowDepth = 2
            $dragBorder.Effect = $shadow
        } catch { }

        $dragText = New-Object System.Windows.Controls.TextBlock
        $dragText.FontWeight = [System.Windows.FontWeights]::SemiBold
        try {
            $fg = $win.TryFindResource('Theme.DataGrid.HeaderText')
            if ($fg) { $dragText.Foreground = $fg }
        } catch { }
        $dragBorder.Child = $dragText
        $dragPopup.Child = $dragBorder

        $resetDrag = {
            $dragState.IsDragging = $false
            $dragState.StartPoint = $null
            $dragState.SourceKind = ''
            $dragState.SourceRow = $null
            $dragState.SourceParkingIndex = -1
            $dragState.SourceParkingItem = $null
            $dragState.LabelText = ''
            # ST-D-012: Clean up cross-page drag timer
            $dragState.HoverTarget = ''
            if ($dragState.HoverTimer) {
                try { $dragState.HoverTimer.Stop() } catch { }
                $dragState.HoverTimer = $null
            }
        }.GetNewClosure()

        $completeDrag = {
            try { $dragPopup.IsOpen = $false } catch { }
            try { [void][System.Windows.Input.Mouse]::Capture($null) } catch { }
            & $resetDrag
        }.GetNewClosure()

        $getGridRowFromHit = {
            param([object]$Visual)
            $row = $null
            try { $row = & $getVisualAncestor -Start $Visual -AncestorType ([System.Windows.Controls.DataGridRow]) } catch { $row = $null }
            if ($row -and $row.Item) {
                $resolved = $null
                try { $resolved = & $getRowByTargetPort ('' + $row.Item.TargetPort) } catch { $resolved = $null }
                if ($resolved) { return $resolved }
                return $row.Item
            }
            return $null
        }.GetNewClosure()

        $getParkingInsertIndexFromHit = {
            param([object]$Visual)
            if (-not $parkingList) { return -1 }

            $container = $null
            try { $container = & $getVisualAncestor -Start $Visual -AncestorType ([System.Windows.Controls.ListBoxItem]) } catch { $container = $null }
            if ($container) {
                try {
                    $owner = [System.Windows.Controls.ItemsControl]::ItemsControlFromItemContainer($container)
                    if ($owner -ne $parkingList) { $container = $null }
                } catch { $container = $null }
            }
            if ($container) {
                try {
                    $idx = $parkingList.ItemContainerGenerator.IndexFromContainer($container)
                    if ($idx -ge 0) { return [int]$idx }
                } catch { }
            }

            $list = $null
            try { $list = & $getVisualAncestor -Start $Visual -AncestorType ([System.Windows.Controls.ListBox]) } catch { $list = $null }
            if ($list -and ($list -eq $parkingList)) {
                try { return [int]$parkingLabels.Count } catch { return 0 }
            }

            return -1
        }.GetNewClosure()

        $insertParkingItem = {
            param([Parameter(Mandatory)][object]$Item, [int]$Index)
            if (-not $Item) { return }

            $src = ''
            try { $src = ('' + $Item.SourcePort).Trim() } catch { $src = '' }
            if ([string]::IsNullOrWhiteSpace($src)) { return }

            $idx = [int]$Index
            if ($idx -lt 0) { $idx = 0 }
            if ($idx -gt $parkingLabels.Count) { $idx = $parkingLabels.Count }
            try { $parkingLabels.Insert($idx, $Item) } catch { }
        }.GetNewClosure()

        $insertParkingProfile = {
            param(
                [Parameter(Mandatory)][string]$SourcePort,
                [Parameter()][AllowEmptyString()][string]$Label,
                [int]$Index
            )

            $src = ('' + $SourcePort).Trim()
            if ([string]::IsNullOrWhiteSpace($src)) { return }

            $item = $null
            try { $item = & $newParkingItem -SourcePort $src -Label ('' + $Label) } catch { $item = $null }
            if (-not $item) { return }

            & $insertParkingItem -Item $item -Index ([int]$Index)
        }.GetNewClosure()

        $gridMouseDownAction = {
                param($sender, $e)
                try {
                    & $resetDrag

                    $hit = $null
                    $pt = $e.GetPosition($sender)
                    try { $hit = [System.Windows.Media.VisualTreeHelper]::HitTest($sender, $pt) } catch { $hit = $null }
                    if (-not $hit) { return }

                    $cell = & $getVisualAncestor -Start $hit.VisualHit -AncestorType ([System.Windows.Controls.DataGridCell])
                    if (-not $cell) { return }
                    try { if ($cell.IsEditing) { return } } catch { }

                    $headerText = ''
                    try { $headerText = '' + $cell.Column.Header } catch { $headerText = '' }
                    if (-not $headerText.Equals('Label', [System.StringComparison]::OrdinalIgnoreCase)) { return }

                    $row = & $getVisualAncestor -Start $hit.VisualHit -AncestorType ([System.Windows.Controls.DataGridRow])
                    if (-not $row -or -not $row.Item) { return }

                    $dragRow = $row.Item
                    try {
                        $resolvedRow = & $getRowByTargetPort ('' + $dragRow.TargetPort)
                        if ($resolvedRow) { $dragRow = $resolvedRow }
                    } catch { }

                    $clicks = 1
                    try { $clicks = [int]$e.ClickCount } catch { $clicks = 1 }
                    if ($clicks -ge 2) {
                        try { $sender.SelectedItem = $dragRow } catch { }
                        try { $sender.CurrentCell = (New-Object System.Windows.Controls.DataGridCellInfo -ArgumentList $dragRow, $cell.Column) } catch { }
                        try { [void]$sender.BeginEdit() } catch { }
                        try { $e.Handled = $true } catch { }
                        return
                    }

                    $srcPort = ''
                    try { $srcPort = ('' + $dragRow.SourcePort).Trim() } catch { $srcPort = '' }
                    if ([string]::IsNullOrWhiteSpace($srcPort)) { return }

                    $labelRaw = ''
                    try { $labelRaw = '' + $dragRow.NewLabel } catch { $labelRaw = '' }
                    $labelTrim = $labelRaw.Trim()
                    $labelDisplay = if ([string]::IsNullOrWhiteSpace($labelTrim)) { '(blank)' } else { $labelTrim }

                    $dragState.StartPoint = $e.GetPosition($win)
                    $dragState.SourceKind = 'Grid'
                    $dragState.SourceRow = $dragRow
                    $dragState.SourceParkingIndex = -1
                    $dragState.SourceParkingItem = $null
                    $dragState.LabelText = ("{0} ({1})" -f $labelDisplay, $srcPort)

                    try { $sender.SelectedItem = $dragRow } catch { }
                    try { $e.Handled = $true } catch { }
                } catch {
                }
            }.GetNewClosure()
        $gridMouseDown = [System.Windows.Input.MouseButtonEventHandler]$gridMouseDownAction
        $grid.AddHandler([System.Windows.UIElement]::PreviewMouseLeftButtonDownEvent, $gridMouseDown, $true)

        if ($parkingList) {
            $parkingMouseDownAction = {
                    param($sender, $e)
                    try {
                        & $resetDrag

                        $hit = $null
                        $pt = $e.GetPosition($sender)
                        try { $hit = [System.Windows.Media.VisualTreeHelper]::HitTest($sender, $pt) } catch { $hit = $null }
                        if (-not $hit) { return }

                        $item = & $getVisualAncestor -Start $hit.VisualHit -AncestorType ([System.Windows.Controls.ListBoxItem])
                        if (-not $item) { return }
                        try {
                            $owner = [System.Windows.Controls.ItemsControl]::ItemsControlFromItemContainer($item)
                            if ($owner -ne $parkingList) { return }
                        } catch { return }

                        $idx = -1
                        try { $idx = $parkingList.ItemContainerGenerator.IndexFromContainer($item) } catch { $idx = -1 }
                        if ($idx -lt 0) { return }

                        $parkItem = $null
                        try { $parkItem = $parkingLabels[$idx] } catch { $parkItem = $null }
                        if (-not $parkItem) { return }

                        $srcPort = ''
                        try { $srcPort = ('' + $parkItem.SourcePort).Trim() } catch { $srcPort = '' }
                        if ([string]::IsNullOrWhiteSpace($srcPort)) { return }

                        $labelRaw = ''
                        try { $labelRaw = '' + $parkItem.Label } catch { $labelRaw = '' }
                        $labelTrim = $labelRaw.Trim()
                        $labelDisplay = if ([string]::IsNullOrWhiteSpace($labelTrim)) { '(blank)' } else { $labelTrim }

                        $dragState.StartPoint = $e.GetPosition($win)
                        $dragState.SourceKind = 'Parking'
                        $dragState.SourceRow = $null
                        $dragState.SourceParkingIndex = $idx
                        $dragState.SourceParkingItem = $parkItem
                        $dragState.LabelText = ("{0} ({1})" -f $labelDisplay, $srcPort)

                        try { $sender.SelectedIndex = $idx } catch { }
                        try { $e.Handled = $true } catch { }
                    } catch {
                    }
                }.GetNewClosure()
            $parkingMouseDown = [System.Windows.Input.MouseButtonEventHandler]$parkingMouseDownAction
            $parkingList.AddHandler([System.Windows.UIElement]::PreviewMouseLeftButtonDownEvent, $parkingMouseDown, $true)
        }

        # ST-D-012: Helper to check if point is over a button
        $isPointOverControl = {
            param([object]$Control, [System.Windows.Point]$Point)
            if (-not $Control) { return $false }
            try {
                $rect = New-Object System.Windows.Rect (
                    $Control.TransformToAncestor($win).Transform((New-Object System.Windows.Point 0, 0)),
                    (New-Object System.Windows.Size $Control.ActualWidth, $Control.ActualHeight)
                )
                return $rect.Contains($Point)
            } catch { return $false }
        }.GetNewClosure()

        # ST-D-012: Cross-page drag timer handler
        $startCrossPageTimer = {
            param([string]$Direction)
            if ($dragState.HoverTimer) {
                try { $dragState.HoverTimer.Stop() } catch { }
            }
            $dragState.HoverTarget = $Direction
            $timer = New-Object System.Windows.Threading.DispatcherTimer
            $timer.Interval = [TimeSpan]::FromMilliseconds(500)
            $timer.Add_Tick({
                try {
                    $timer.Stop()
                    if (-not $dragState.IsDragging) { return }
                    if (-not ($pagingState.Enabled -eq $true)) { return }

                    if ($dragState.HoverTarget -eq 'Prev' -and $pagingState.PageNumber -gt 1) {
                        $pagingState.PageNumber = [int]$pagingState.PageNumber - 1
                        & $refreshGrid
                    } elseif ($dragState.HoverTarget -eq 'Next' -and $pagingState.PageNumber -lt $pagingState.PageCount) {
                        $pagingState.PageNumber = [int]$pagingState.PageNumber + 1
                        & $refreshGrid
                    }
                } catch { }
            }.GetNewClosure())
            $timer.Start()
            $dragState.HoverTimer = $timer
        }.GetNewClosure()

        $stopCrossPageTimer = {
            $dragState.HoverTarget = ''
            if ($dragState.HoverTimer) {
                try { $dragState.HoverTimer.Stop() } catch { }
                $dragState.HoverTimer = $null
            }
        }.GetNewClosure()

        $winMouseMoveAction = {
                param($sender, $e)
                try {
                    if ($e.LeftButton -ne [System.Windows.Input.MouseButtonState]::Pressed) { return }
                    if (-not $dragState.SourceKind) { return }
                    if ($null -eq $dragState.StartPoint) { return }

                    $pos = $e.GetPosition($win)
                    $dx = [Math]::Abs($pos.X - $dragState.StartPoint.X)
                    $dy = [Math]::Abs($pos.Y - $dragState.StartPoint.Y)

                    if (-not $dragState.IsDragging) {
                        if ($dx -lt [System.Windows.SystemParameters]::MinimumHorizontalDragDistance -and
                            $dy -lt [System.Windows.SystemParameters]::MinimumVerticalDragDistance) {
                            return
                        }

                        $dragState.IsDragging = $true
                        try { [void][System.Windows.Input.Mouse]::Capture($win) } catch { }

                        $dragText.Text = $dragState.LabelText
                        $dragPopup.HorizontalOffset = $pos.X + 12
                        $dragPopup.VerticalOffset = $pos.Y + 12
                        $dragPopup.IsOpen = $true
                        try { $e.Handled = $true } catch { }
                        return
                    }

                    $dragPopup.HorizontalOffset = $pos.X + 12
                    $dragPopup.VerticalOffset = $pos.Y + 12

                    # ST-D-012: Cross-page drag auto-switch detection
                    if ($pagingState.Enabled -eq $true) {
                        $overPrev = & $isPointOverControl $pagePrevButton $pos
                        $overNext = & $isPointOverControl $pageNextButton $pos

                        if ($overPrev -and $dragState.HoverTarget -ne 'Prev') {
                            & $stopCrossPageTimer
                            if ($pagingState.PageNumber -gt 1) {
                                & $startCrossPageTimer 'Prev'
                            }
                        } elseif ($overNext -and $dragState.HoverTarget -ne 'Next') {
                            & $stopCrossPageTimer
                            if ($pagingState.PageNumber -lt $pagingState.PageCount) {
                                & $startCrossPageTimer 'Next'
                            }
                        } elseif (-not $overPrev -and -not $overNext -and $dragState.HoverTarget) {
                            & $stopCrossPageTimer
                        }
                    }

                    try { $e.Handled = $true } catch { }
                } catch {
                }
            }.GetNewClosure()
        $winMouseMove = [System.Windows.Input.MouseEventHandler]$winMouseMoveAction
        $win.AddHandler([System.Windows.UIElement]::PreviewMouseMoveEvent, $winMouseMove, $true)

        $winMouseUpAction = {
                param($sender, $e)
                try {
                    if (-not $dragState.SourceKind) { return }

                    if (-not $dragState.IsDragging) {
                        & $completeDrag
                        return
                    }

                    $point = $e.GetPosition($win)
                    $hit = $null
                    try { $hit = [System.Windows.Media.VisualTreeHelper]::HitTest($win, $point) } catch { $hit = $null }
                    if (-not $hit) {
                        & $completeDrag
                        return
                    }

                    $dropVisual = $hit.VisualHit
                    $dropRow = & $getGridRowFromHit $dropVisual
                    $parkIndex = & $getParkingInsertIndexFromHit $dropVisual

                    if ($dropRow) {
                        $swapAssignments = $false
                        try {
                            $mods = [System.Windows.Input.Keyboard]::Modifiers
                            if (($mods -band [System.Windows.Input.ModifierKeys]::Shift) -ne 0) { $swapAssignments = $true }
                        } catch { $swapAssignments = $false }

                        if ($swapAssignments -and $dragState.SourceKind -eq 'Grid') {
                            $dragged = $dragState.SourceRow
                            $dropped = $dropRow
                            if ($dragged -and $dropped -and -not [object]::ReferenceEquals($dragged, $dropped)) {
                                $tmpSource = ''
                                $tmpLabel = ''
                                try { $tmpSource = '' + $dragged.SourcePort } catch { $tmpSource = '' }
                                try { $tmpLabel = '' + $dragged.NewLabel } catch { $tmpLabel = '' }

                                try { $dragged.SourcePort = '' + $dropped.SourcePort } catch { }
                                try { $dragged.NewLabel = '' + $dropped.NewLabel } catch { }
                                try { $dropped.SourcePort = $tmpSource } catch { }
                                try { $dropped.NewLabel = $tmpLabel } catch { }

                                & $markScriptsDirty
                                & $refreshGrid

                                $dstPort = ''
                                try { $dstPort = ('' + $dropped.TargetPort).Trim() } catch { $dstPort = '' }
                                $srcPort = ''
                                try { $srcPort = ('' + $dragged.TargetPort).Trim() } catch { $srcPort = '' }
                                & $setStatus ("Swapped assignments between {0} and {1}." -f $srcPort, $dstPort) ''
                            }
                            & $completeDrag
                            return
                        }

                        $draggedProfilePort = ''
                        $draggedProfileLabel = ''
                        $draggedFromTargetPort = ''
                        $parkItem = $null

                        if ($dragState.SourceKind -eq 'Grid') {
                            $srcRow = $dragState.SourceRow
                            if (-not $srcRow) {
                                & $completeDrag
                                return
                            }
                            try { $draggedProfilePort = ('' + $srcRow.SourcePort).Trim() } catch { $draggedProfilePort = '' }
                            try { $draggedProfileLabel = '' + $srcRow.NewLabel } catch { $draggedProfileLabel = '' }
                            try { $draggedFromTargetPort = ('' + $srcRow.TargetPort).Trim() } catch { $draggedFromTargetPort = '' }
                        } elseif ($dragState.SourceKind -eq 'Parking') {
                            $parkItem = $dragState.SourceParkingItem
                            if (-not $parkItem) {
                                $srcIdx = [int]$dragState.SourceParkingIndex
                                if ($srcIdx -ge 0 -and $srcIdx -lt $parkingLabels.Count) {
                                    try { $parkItem = $parkingLabels[$srcIdx] } catch { $parkItem = $null }
                                }
                            }
                            if (-not $parkItem) {
                                & $completeDrag
                                return
                            }
                            try { $draggedProfilePort = ('' + $parkItem.SourcePort).Trim() } catch { $draggedProfilePort = '' }
                            try { $draggedProfileLabel = '' + $parkItem.Label } catch { $draggedProfileLabel = '' }
                        }

                        if ([string]::IsNullOrWhiteSpace($draggedProfilePort)) {
                            & $completeDrag
                            return
                        }

                        if ($dragState.SourceKind -eq 'Grid') {
                            if ($dragState.SourceRow -and [object]::ReferenceEquals($dragState.SourceRow, $dropRow)) {
                                & $completeDrag
                                return
                            }
                        }

                        $droppedTargetPort = ''
                        try { $droppedTargetPort = ('' + $dropRow.TargetPort).Trim() } catch { $droppedTargetPort = '' }

                        $destProfilePort = ''
                        $destProfileLabel = ''
                        try { $destProfilePort = ('' + $dropRow.SourcePort).Trim() } catch { $destProfilePort = '' }
                        try { $destProfileLabel = '' + $dropRow.NewLabel } catch { $destProfileLabel = '' }

                        $parkedIndex = -1
                        if (-not [string]::IsNullOrWhiteSpace($destProfilePort)) {
                            if ($dragState.SourceKind -eq 'Parking' -and $dragState.SourceParkingIndex -ge 0) {
                                $parkedIndex = [int]$dragState.SourceParkingIndex
                            } else {
                                $parkedIndex = [int]$parkingLabels.Count
                            }
                        }

                        if ($dragState.SourceKind -eq 'Parking') {
                            $srcIdx = [int]$dragState.SourceParkingIndex
                            $removed = $false
                            if ($srcIdx -ge 0 -and $srcIdx -lt $parkingLabels.Count) {
                                try {
                                    if ($parkingLabels[$srcIdx] -eq $parkItem) {
                                        $parkingLabels.RemoveAt($srcIdx)
                                        $removed = $true
                                    }
                                } catch { }
                            }
                            if (-not $removed -and $parkItem) {
                                try {
                                    for ($i = 0; $i -lt $parkingLabels.Count; $i++) {
                                        if ($parkingLabels[$i] -eq $parkItem) { $parkingLabels.RemoveAt($i); break }
                                    }
                                } catch { }
                            }
                        } elseif ($dragState.SourceKind -eq 'Grid') {
                            $srcRow = $dragState.SourceRow
                            try { $srcRow.SourcePort = '' } catch { }
                            try { $srcRow.NewLabel = '' } catch { }
                        }

                        if ($parkedIndex -ge 0 -and -not [string]::IsNullOrWhiteSpace($destProfilePort)) {
                            & $insertParkingProfile -SourcePort $destProfilePort -Label $destProfileLabel -Index $parkedIndex
                        }

                        try { $dropRow.SourcePort = $draggedProfilePort } catch { }
                        try { $dropRow.NewLabel = '' + $draggedProfileLabel } catch { }
                        & $markScriptsDirty
                        & $refreshGrid

                        $labelMsg = ('' + $draggedProfileLabel).Trim()
                        if ([string]::IsNullOrWhiteSpace($labelMsg)) { $labelMsg = '(blank)' }
                        if ($draggedFromTargetPort) {
                            if ($destProfilePort) {
                                & $setStatus ("Moved {0} from {1} to {2}; parked profile {3}." -f $labelMsg, $draggedFromTargetPort, $droppedTargetPort, $destProfilePort) ''
                            } else {
                                & $setStatus ("Moved {0} from {1} to {2}." -f $labelMsg, $draggedFromTargetPort, $droppedTargetPort) ''
                            }
                        } else {
                            if ($destProfilePort) {
                                & $setStatus ("Assigned {0} to {1}; parked profile {2}." -f $labelMsg, $droppedTargetPort, $destProfilePort) ''
                            } else {
                                & $setStatus ("Assigned {0} to {1}." -f $labelMsg, $droppedTargetPort) ''
                            }
                        }

                        & $completeDrag
                        return
                    }

                    if ($parkIndex -ge 0) {
                        if ($dragState.SourceKind -eq 'Parking') {
                            $srcIdx = [int]$dragState.SourceParkingIndex
                            if ($srcIdx -ge 0 -and $srcIdx -lt $parkingLabels.Count) {
                                $item = $null
                                try { $item = $parkingLabels[$srcIdx] } catch { $item = $null }
                                if ($item) {
                                    try { $parkingLabels.RemoveAt($srcIdx) } catch { }
                                    $insertAt = [int]$parkIndex
                                    if ($insertAt -gt $srcIdx) { $insertAt-- }
                                    & $insertParkingItem -Item $item -Index $insertAt
                                }
                            }
                            & $completeDrag
                            return
                        }

                        if ($dragState.SourceKind -eq 'Grid') {
                            $srcRow = $dragState.SourceRow
                            if ($srcRow) {
                                $srcProfilePort = ''
                                $srcProfileLabel = ''
                                try { $srcProfilePort = ('' + $srcRow.SourcePort).Trim() } catch { $srcProfilePort = '' }
                                try { $srcProfileLabel = '' + $srcRow.NewLabel } catch { $srcProfileLabel = '' }

                                if (-not [string]::IsNullOrWhiteSpace($srcProfilePort)) {
                                    try { $srcRow.SourcePort = '' } catch { }
                                    try { $srcRow.NewLabel = '' } catch { }
                                    & $insertParkingProfile -SourcePort $srcProfilePort -Label $srcProfileLabel -Index ([int]$parkIndex)
                                    & $markScriptsDirty
                                    & $refreshGrid
                                    & $setStatus ("Parked profile {0}." -f $srcProfilePort) ''
                                }
                            }
                            & $completeDrag
                            return
                        }
                    }

                    & $completeDrag
                } catch {
                    & $completeDrag
                }
            }.GetNewClosure()
        $winMouseUp = [System.Windows.Input.MouseButtonEventHandler]$winMouseUpAction
        $win.AddHandler([System.Windows.UIElement]::PreviewMouseLeftButtonUpEvent, $winMouseUp, $true)

        $winLostCaptureAction = {
                param($sender, $e)
                try {
                    if ($dragState.SourceKind) { & $completeDrag }
                } catch { }
            }.GetNewClosure()
        $winLostCapture = [System.Windows.Input.MouseEventHandler]$winLostCaptureAction
        $win.AddHandler([System.Windows.UIElement]::LostMouseCaptureEvent, $winLostCapture, $true)
    }

    $validate = {
        $sources = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($r in $rows) {
            $dst = ('' + $r.TargetPort).Trim()
            $src = ('' + $r.SourcePort).Trim()
            if ([string]::IsNullOrWhiteSpace($dst)) { return "Missing Port value for row." }
            if ([string]::IsNullOrWhiteSpace($src)) {
                $lbl = ''
                try { $lbl = ('' + $r.NewLabel).Trim() } catch { $lbl = '' }
                if (-not [string]::IsNullOrWhiteSpace($lbl)) { return "Port $dst has a label but no FromPort assignment." }
                continue
            }
            if (-not ($sources.Add($src))) { return "Duplicate FromPort assignment: $src" }
            if (-not $labelByPort.ContainsKey($src)) { return "Unknown FromPort: $src" }
        }
        return ''
    }.GetNewClosure()

    $suggestAction = {
        try {
            $planRows = [System.Collections.Generic.List[object]]::new()
            foreach ($r in $rows) {
                $planRows.Add([PSCustomObject]@{
                    SourcePort = ('' + $r.SourcePort).Trim()
                    TargetPort = ('' + $r.TargetPort).Trim()
                    NewLabel   = '' + $r.NewLabel
                }) | Out-Null
            }

            $suggested = PortReorgModule\Get-PortReorgSuggestedPlan -PlanRows $planRows.ToArray() -AvailablePorts $availablePorts
            $byTarget = @{}
            foreach ($p in @($suggested)) {
                $t = ('' + $p.TargetPort).Trim()
                if (-not [string]::IsNullOrWhiteSpace($t)) { $byTarget[$t] = $p }
            }

            foreach ($r in $rows) {
                $t = ('' + $r.TargetPort).Trim()
                if (-not $byTarget.ContainsKey($t)) { continue }
                $p = $byTarget[$t]
                $r.SourcePort = ('' + $p.SourcePort).Trim()
                $r.NewLabel = '' + $p.NewLabel
            }

            try { if ($parkingLabels) { $parkingLabels.Clear() } } catch { }
            & $markScriptsDirty
            & $refreshGrid
            & $setStatus '' ''
        } catch {
            & $setStatus ("Suggest failed: {0}" -f $_.Exception.Message) ''
        }
    }.GetNewClosure()

    $resetAction = {
        try {
            if ($baselineRows.Count -eq 0) { return }
            $map = @{}
            foreach ($b in $baselineRows) { $map[('' + $b.TargetPort).Trim()] = $b }
            foreach ($r in $rows) {
                $dst = ('' + $r.TargetPort).Trim()
                if ($map.ContainsKey($dst)) {
                    $b = $map[$dst]
                    $r.SourcePort = $b.SourcePort
                    $r.NewLabel = $b.NewLabel
                    $r.CurrentLabel = $b.CurrentLabel
                }
            }
            try { if ($parkingLabels) { $parkingLabels.Clear() } } catch { }
            & $markScriptsDirty
            & $refreshGrid
            & $setStatus '' ''
        } catch {
            & $setStatus ("Reset failed: {0}" -f $_.Exception.Message) ''
        }
    }.GetNewClosure()

    $generateAction = {
        try {
            $err = & $validate
            if ($err) {
                & $setStatus $err ''
                return
            }

            $chunkEnabled = $false
            if ($chunkBy12) {
                # Handle nullable boolean from WPF CheckBox
                $checked = $chunkBy12.IsChecked
                $chunkEnabled = ($null -ne $checked -and $checked -eq $true)
            }
            $chunkSize = 0
            if ($chunkEnabled) {
                $raw = if ($chunkSizeBox) { ('' + $chunkSizeBox.Text).Trim() } else { '12' }
                [void][int]::TryParse($raw, [ref]$chunkSize)
                if ($chunkSize -lt 1) { $chunkSize = 12 }
            }
            $chunkArg = if ($chunkEnabled) { $chunkSize } else { 0 }

            $planRows = [System.Collections.Generic.List[object]]::new()
            foreach ($r in $rows) {
                $planRows.Add([PSCustomObject]@{
                    SourcePort = ('' + $r.SourcePort).Trim()
                    TargetPort = ('' + $r.TargetPort).Trim()
                    NewLabel   = '' + $r.NewLabel
                }) | Out-Null
            }

            $scripts = PortReorgModule\New-PortReorgScripts -Hostname $hostTrim -PlanRows $planRows.ToArray() -BaselineInterfaces $interfaces -Vendor $vendor -ChunkSize $chunkArg

            $change = ''
            $rollback = ''
            if ($scripts) {
                if ($scripts.ChangeScript) { $change = ($scripts.ChangeScript -join "`r`n") }
                if ($scripts.RollbackScript) { $rollback = ($scripts.RollbackScript -join "`r`n") }
            }
            if ($changeBox) { $changeBox.Text = $change }
            if ($rollbackBox) { $rollbackBox.Text = $rollback }
            try { $uiState.ScriptsAreCurrent = $true } catch { }
            try { & $updateScriptControls } catch { }
            $chunkMsg = if ($chunkEnabled) { " (chunked by {0})" -f $chunkArg } else { '' }
            & $setStatus ("Scripts generated{0}." -f $chunkMsg) ''
        } catch {
            try { $uiState.ScriptsAreCurrent = $false } catch { }
            try { & $updateScriptControls } catch { }
            & $setStatus ("Generate failed: {0}" -f $_.Exception.Message) ''
        }
    }.GetNewClosure()

    if ($suggestBtn) { $suggestBtn.Add_Click($suggestAction.GetNewClosure()) }
    if ($resetBtn) { $resetBtn.Add_Click($resetAction.GetNewClosure()) }
    if ($generateBtn) { $generateBtn.Add_Click($generateAction.GetNewClosure()) }
    if ($chunkBy12) { $chunkBy12.Add_Click({ try { & $markScriptsDirty } catch { } }.GetNewClosure()) }
    if ($chunkSizeBox) { $chunkSizeBox.Add_TextChanged({ try { & $markScriptsDirty } catch { } }.GetNewClosure()) }

    if ($pagedViewCheckBox) {
        $pagedViewCheckBox.Add_Click({
            try {
                $checked = $pagedViewCheckBox.IsChecked
                $enabled = ($null -ne $checked -and $checked -eq $true)
                & $setPagingEnabled $enabled
            } catch { }
        }.GetNewClosure())
    }

    if ($pagePrevButton) {
        $pagePrevButton.Add_Click({
            try {
                if (-not ($pagingState.Enabled -eq $true)) { return }
                $page = 1
                try { $page = [int]$pagingState.PageNumber } catch { $page = 1 }
                $page--
                if ($page -lt 1) { $page = 1 }
                $pagingState.PageNumber = $page
                & $refreshGrid
            } catch { }
        }.GetNewClosure())
    }

    if ($pageNextButton) {
        $pageNextButton.Add_Click({
            try {
                if (-not ($pagingState.Enabled -eq $true)) { return }
                $page = 1
                $maxPage = 1
                try { $page = [int]$pagingState.PageNumber } catch { $page = 1 }
                try { $maxPage = [int]$pagingState.PageCount } catch { $maxPage = 1 }
                $page++
                if ($page -gt $maxPage) { $page = $maxPage }
                if ($page -lt 1) { $page = 1 }
                $pagingState.PageNumber = $page
                & $refreshGrid
            } catch { }
        }.GetNewClosure())
    }

    if ($pageComboBox) {
        $pageComboBox.Add_SelectionChanged({
            param($sender, $e)
            try {
                if (-not ($pagingState.Enabled -eq $true)) { return }
                if ($pagingState.SuppressPageEvent -eq $true) { return }

                $page = 0
                try { $page = [int]$sender.SelectedValue } catch { $page = 0 }
                if ($page -lt 1) {
                    try { $page = [int]$sender.SelectedIndex + 1 } catch { $page = 1 }
                }
                if ($page -lt 1) { $page = 1 }

                $pagingState.PageNumber = $page
                & $refreshGrid
            } catch { }
        }.GetNewClosure())
    }

    if ($copyChangeBtn) {
        $copyChangeBtn.Add_Click({
            try {
                if ($changeBox -and $changeBox.Text) {
                    Set-Clipboard -Value ('' + $changeBox.Text)
                    & $setStatus 'Change script copied to clipboard.' ''
                }
            } catch {
                & $setStatus ("Copy failed: {0}" -f $_.Exception.Message) ''
            }
        }.GetNewClosure())
    }
    if ($copyRollbackBtn) {
        $copyRollbackBtn.Add_Click({
            try {
                if ($rollbackBox -and $rollbackBox.Text) {
                    Set-Clipboard -Value ('' + $rollbackBox.Text)
                    & $setStatus 'Rollback script copied to clipboard.' ''
                }
            } catch {
                & $setStatus ("Copy failed: {0}" -f $_.Exception.Message) ''
            }
        }.GetNewClosure())
    }

    try { script:Import-LocalStateTraceModule -ModuleName 'ViewCompositionModule' -ModuleFileName 'ViewCompositionModule.psm1' -Optional | Out-Null } catch { }

    if ($saveChangeBtn) {
        $saveChangeBtn.Add_Click({
            try {
                if (-not $changeBox -or [string]::IsNullOrWhiteSpace($changeBox.Text)) { return }
                try {
                    ViewCompositionModule\Export-StTextToFile -Text $changeBox.Text -DefaultFileName ("{0}-PortReorg-Change.txt" -f $hostTrim) -SuppressDialogs:$SuppressDialogs
                } catch [System.Management.Automation.CommandNotFoundException] {
                    Set-Clipboard -Value ('' + $changeBox.Text)
                    if ($suppressDialogsResolved) {
                        Write-Warning 'Export helper missing; script copied to clipboard instead.'
                    } else {
                        [System.Windows.MessageBox]::Show('Export helper missing; script copied to clipboard instead.') | Out-Null
                    }
                }
            } catch {
                & $setStatus ("Save failed: {0}" -f $_.Exception.Message) ''
            }
        }.GetNewClosure())
    }
    if ($saveRollbackBtn) {
        $saveRollbackBtn.Add_Click({
            try {
                if (-not $rollbackBox -or [string]::IsNullOrWhiteSpace($rollbackBox.Text)) { return }
                try {
                    ViewCompositionModule\Export-StTextToFile -Text $rollbackBox.Text -DefaultFileName ("{0}-PortReorg-Rollback.txt" -f $hostTrim) -SuppressDialogs:$SuppressDialogs
                } catch [System.Management.Automation.CommandNotFoundException] {
                    Set-Clipboard -Value ('' + $rollbackBox.Text)
                    if ($suppressDialogsResolved) {
                        Write-Warning 'Export helper missing; script copied to clipboard instead.'
                    } else {
                        [System.Windows.MessageBox]::Show('Export helper missing; script copied to clipboard instead.') | Out-Null
                    }
                }
            } catch {
                & $setStatus ("Save failed: {0}" -f $_.Exception.Message) ''
            }
        }.GetNewClosure())
    }

    if ($closeBtn) { $closeBtn.Add_Click({ try { $win.Close() } catch { } }.GetNewClosure()) }

    #region ST-D-012: Event handlers for new controls

    # Undo/Redo buttons
    if ($undoBtn) {
        $undoBtn.Add_Click({
            try {
                & $undoAction
            } catch { }
        }.GetNewClosure())
    }

    if ($redoBtn) {
        $redoBtn.Add_Click({
            try {
                & $redoAction
            } catch { }
        }.GetNewClosure())
    }

    # Page size text box - press Enter to apply
    if ($pageSizeBox) {
        $pageSizeBox.Text = ('' + $pagingState.PageSize)
        $pageSizeBox.Add_KeyDown({
            param($sender, $e)
            try {
                if ($e.Key -eq [System.Windows.Input.Key]::Enter) {
                    & $applyPageSize $sender.Text
                    $sender.Text = ('' + $pagingState.PageSize)
                    $e.Handled = $true
                }
            } catch { }
        }.GetNewClosure())
    }

    # Quick jump text box - press Enter to jump
    if ($quickJumpBox) {
        $quickJumpBox.Add_KeyDown({
            param($sender, $e)
            try {
                if ($e.Key -eq [System.Windows.Input.Key]::Enter) {
                    & $quickJumpAction $sender.Text
                    $sender.SelectAll()
                    $e.Handled = $true
                }
            } catch { }
        }.GetNewClosure())
    }

    # Search text box - live filter on text change
    if ($searchBox) {
        $searchBox.Add_TextChanged({
            param($sender, $e)
            try {
                & $applySearchFilter $sender.Text
            } catch { }
        }.GetNewClosure())
    }

    # Search clear button
    if ($searchClearBtn) {
        $searchClearBtn.Add_Click({
            try {
                if ($searchBox) { $searchBox.Text = '' }
                & $applySearchFilter ''
            } catch { }
        }.GetNewClosure())
    }

    # Select Page button - select all ports on current page
    if ($selectPageBtn) {
        $selectPageBtn.Add_Click({
            try {
                if (-not $grid) { return }
                if ($pagingState.Enabled -eq $true) {
                    $grid.SelectAll()
                } else {
                    $grid.SelectAll()
                }
            } catch { }
        }.GetNewClosure())
    }

    # Clear Page button - park all labels on current page
    if ($clearPageBtn) {
        $clearPageBtn.Add_Click({
            try {
                $snapshot = & $captureHistorySnapshot
                & $pushUndo $snapshot

                $rowsToClear = @()
                if ($pagingState.Enabled -eq $true) {
                    $rowsToClear = @($visibleRows)
                } else {
                    $rowsToClear = @($rows)
                }

                foreach ($row in $rowsToClear) {
                    $srcPort = ''
                    $label = ''
                    try { $srcPort = ('' + $row.SourcePort).Trim() } catch { $srcPort = '' }
                    try { $label = '' + $row.NewLabel } catch { $label = '' }

                    if (-not [string]::IsNullOrWhiteSpace($srcPort)) {
                        & $insertParkingProfile -SourcePort $srcPort -Label $label -Index ([int]$parkingLabels.Count)
                        try { $row.SourcePort = '' } catch { }
                        try { $row.NewLabel = '' } catch { }
                    }
                }

                & $markScriptsDirty
                & $refreshGrid
                & $setStatus 'Page labels cleared (parked).' ''
            } catch {
                & $setStatus ("Clear page failed: {0}" -f $_.Exception.Message) ''
            }
        }.GetNewClosure())
    }

    # Context menu: Clear Label (Park)
    if ($clearLabelMenuItem) {
        $clearLabelMenuItem.Add_Click({
            try {
                if (-not $grid -or -not $grid.SelectedItem) { return }

                $snapshot = & $captureHistorySnapshot
                & $pushUndo $snapshot

                $selected = @($grid.SelectedItems)
                foreach ($item in $selected) {
                    $row = & $getRowByTargetPort ('' + $item.TargetPort)
                    if (-not $row) { continue }

                    $srcPort = ''
                    $label = ''
                    try { $srcPort = ('' + $row.SourcePort).Trim() } catch { $srcPort = '' }
                    try { $label = '' + $row.NewLabel } catch { $label = '' }

                    if (-not [string]::IsNullOrWhiteSpace($srcPort)) {
                        & $insertParkingProfile -SourcePort $srcPort -Label $label -Index ([int]$parkingLabels.Count)
                        try { $row.SourcePort = '' } catch { }
                        try { $row.NewLabel = '' } catch { }
                    }
                }

                & $markScriptsDirty
                & $refreshGrid
                & $setStatus 'Label(s) cleared.' ''
            } catch { }
        }.GetNewClosure())
    }

    # Context menu: Swap Labels
    if ($swapLabelsMenuItem) {
        $swapLabelsMenuItem.Add_Click({
            try {
                if (-not $grid) { return }
                $selected = @($grid.SelectedItems)
                if ($selected.Count -ne 2) {
                    & $setStatus 'Select exactly 2 rows to swap.' ''
                    return
                }

                $snapshot = & $captureHistorySnapshot
                & $pushUndo $snapshot

                $row1 = & $getRowByTargetPort ('' + $selected[0].TargetPort)
                $row2 = & $getRowByTargetPort ('' + $selected[1].TargetPort)
                if (-not $row1 -or -not $row2) { return }

                $tmpSrc = '' + $row1.SourcePort
                $tmpLbl = '' + $row1.NewLabel
                $row1.SourcePort = '' + $row2.SourcePort
                $row1.NewLabel = '' + $row2.NewLabel
                $row2.SourcePort = $tmpSrc
                $row2.NewLabel = $tmpLbl

                & $markScriptsDirty
                & $refreshGrid
                & $setStatus 'Labels swapped.' ''
            } catch { }
        }.GetNewClosure())
    }

    # Context menu: Move To... (opens dialog to pick target port)
    if ($moveToMenuItem) {
        $moveToMenuItem.Add_Click({
            try {
                if (-not $grid -or -not $grid.SelectedItem) { return }

                $srcRow = & $getRowByTargetPort ('' + $grid.SelectedItem.TargetPort)
                if (-not $srcRow) { return }

                $srcPort = ''
                try { $srcPort = ('' + $srcRow.SourcePort).Trim() } catch { $srcPort = '' }
                if ([string]::IsNullOrWhiteSpace($srcPort)) {
                    & $setStatus 'Selected row has no assigned profile.' ''
                    return
                }

                # Simple input dialog for target port
                $inputWin = New-Object System.Windows.Window
                $inputWin.Title = 'Move To Port'
                $inputWin.Width = 300
                $inputWin.Height = 120
                $inputWin.WindowStartupLocation = 'CenterOwner'
                $inputWin.Owner = $win
                try { $inputWin.Background = $win.TryFindResource('Theme.Window.Background') } catch { }

                $inputPanel = New-Object System.Windows.Controls.StackPanel
                $inputPanel.Margin = '10'

                $inputLabel = New-Object System.Windows.Controls.TextBlock
                $inputLabel.Text = 'Enter target port name:'
                $inputLabel.Margin = '0,0,0,5'
                try { $inputLabel.Foreground = $win.TryFindResource('Theme.Text.Primary') } catch { }

                $inputBox = New-Object System.Windows.Controls.TextBox
                $inputBox.Margin = '0,0,0,10'
                try { $inputBox.Background = $win.TryFindResource('Theme.Input.Background') } catch { }
                try { $inputBox.Foreground = $win.TryFindResource('Theme.Input.Text') } catch { }

                $inputBtnPanel = New-Object System.Windows.Controls.StackPanel
                $inputBtnPanel.Orientation = 'Horizontal'
                $inputBtnPanel.HorizontalAlignment = 'Right'

                $okBtn = New-Object System.Windows.Controls.Button
                $okBtn.Content = 'OK'
                $okBtn.Width = 60
                $okBtn.Margin = '0,0,5,0'
                $okBtn.IsDefault = $true

                $cancelBtn = New-Object System.Windows.Controls.Button
                $cancelBtn.Content = 'Cancel'
                $cancelBtn.Width = 60
                $cancelBtn.IsCancel = $true

                $inputBtnPanel.Children.Add($okBtn) | Out-Null
                $inputBtnPanel.Children.Add($cancelBtn) | Out-Null
                $inputPanel.Children.Add($inputLabel) | Out-Null
                $inputPanel.Children.Add($inputBox) | Out-Null
                $inputPanel.Children.Add($inputBtnPanel) | Out-Null
                $inputWin.Content = $inputPanel

                $result = @{ TargetPort = '' }
                $okBtn.Add_Click({
                    $result.TargetPort = $inputBox.Text.Trim()
                    $inputWin.DialogResult = $true
                    $inputWin.Close()
                }.GetNewClosure())

                $inputBox.Focus() | Out-Null
                $dialogResult = $inputWin.ShowDialog()

                if ($dialogResult -eq $true -and -not [string]::IsNullOrWhiteSpace($result.TargetPort)) {
                    $targetPort = $result.TargetPort
                    $targetRow = & $getRowByTargetPort $targetPort
                    if (-not $targetRow) {
                        & $setStatus ("Port '{0}' not found." -f $targetPort) ''
                        return
                    }

                    $snapshot = & $captureHistorySnapshot
                    & $pushUndo $snapshot

                    # Park existing label on target if any
                    $destSrc = ''
                    $destLbl = ''
                    try { $destSrc = ('' + $targetRow.SourcePort).Trim() } catch { $destSrc = '' }
                    try { $destLbl = '' + $targetRow.NewLabel } catch { $destLbl = '' }
                    if (-not [string]::IsNullOrWhiteSpace($destSrc)) {
                        & $insertParkingProfile -SourcePort $destSrc -Label $destLbl -Index ([int]$parkingLabels.Count)
                    }

                    # Move source profile to target
                    $targetRow.SourcePort = $srcPort
                    $targetRow.NewLabel = '' + $srcRow.NewLabel
                    $srcRow.SourcePort = ''
                    $srcRow.NewLabel = ''

                    # If paged, jump to target page
                    if ($pagingState.Enabled -eq $true) {
                        $page = & $getPageForRow $targetRow
                        $pagingState.PageNumber = $page
                    }

                    & $markScriptsDirty
                    & $refreshGrid
                    & $setStatus ("Moved to {0}." -f $targetPort) ''
                }
            } catch {
                & $setStatus ("Move failed: {0}" -f $_.Exception.Message) ''
            }
        }.GetNewClosure())
    }

    # Keyboard navigation
    $win.Add_PreviewKeyDown({
        param($sender, $e)
        try {
            $mods = [System.Windows.Input.Keyboard]::Modifiers
            $key = $e.Key

            # Ctrl+Z = Undo
            if (($mods -band [System.Windows.Input.ModifierKeys]::Control) -ne 0 -and $key -eq [System.Windows.Input.Key]::Z) {
                & $undoAction
                $e.Handled = $true
                return
            }

            # Ctrl+Y = Redo
            if (($mods -band [System.Windows.Input.ModifierKeys]::Control) -ne 0 -and $key -eq [System.Windows.Input.Key]::Y) {
                & $redoAction
                $e.Handled = $true
                return
            }

            # Skip page navigation if focus is in a text box
            $focused = [System.Windows.Input.Keyboard]::FocusedElement
            if ($focused -is [System.Windows.Controls.TextBox]) { return }

            if (-not ($pagingState.Enabled -eq $true)) { return }

            # PageUp = Previous page
            if ($key -eq [System.Windows.Input.Key]::PageUp) {
                $page = [int]$pagingState.PageNumber - 1
                if ($page -lt 1) { $page = 1 }
                $pagingState.PageNumber = $page
                & $refreshGrid
                $e.Handled = $true
                return
            }

            # PageDown = Next page
            if ($key -eq [System.Windows.Input.Key]::PageDown) {
                $page = [int]$pagingState.PageNumber + 1
                if ($page -gt $pagingState.PageCount) { $page = [int]$pagingState.PageCount }
                $pagingState.PageNumber = $page
                & $refreshGrid
                $e.Handled = $true
                return
            }

            # Ctrl+Home = First page
            if (($mods -band [System.Windows.Input.ModifierKeys]::Control) -ne 0 -and $key -eq [System.Windows.Input.Key]::Home) {
                $pagingState.PageNumber = 1
                & $refreshGrid
                $e.Handled = $true
                return
            }

            # Ctrl+End = Last page
            if (($mods -band [System.Windows.Input.ModifierKeys]::Control) -ne 0 -and $key -eq [System.Windows.Input.Key]::End) {
                $pagingState.PageNumber = [int]$pagingState.PageCount
                & $refreshGrid
                $e.Handled = $true
                return
            }
        } catch { }
    }.GetNewClosure())

    # Set initial visibility for new paging controls based on paging state
    $newPagingControls = @($pageSizeBox, $quickJumpBox, $searchBox, $searchClearBtn)
    foreach ($ctrl in $newPagingControls) {
        if ($ctrl) {
            try {
                # These controls are always visible; paging controls visibility controlled by setPagingControlsVisible
            } catch { }
        }
    }

    #endregion

    try { & $refreshGrid } catch { }
    $win.Show() | Out-Null
}

Export-ModuleMember -Function Show-PortReorgWindow
