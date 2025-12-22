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
            if ($reader) { $reader.Close(); $reader.Dispose() }
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
            TargetPort   = $port
            TargetPortSort = $portSort
            SourcePort   = $port
            CurrentLabel = $label
            NewLabel     = $label
            LabelState   = 'Unchanged'
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

    $orderedRows = @()
    try {
        $orderedRows = @($rows.ToArray() | Sort-Object TargetPortSort, TargetPort)
    } catch {
        try { $orderedRows = @($rows.ToArray()) } catch { $orderedRows = @() }
    }

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
            try {
                if ($total -gt 0 -and $startIndex -ge 0 -and $startIndex -lt $total) {
                    $startPort = ('' + $orderedRows[$startIndex].TargetPort).Trim()
                }
                if ($total -gt 0 -and $endIndex -ge 0 -and $endIndex -lt $total) {
                    $endPort = ('' + $orderedRows[$endIndex].TargetPort).Trim()
                }
            } catch { }

            $label = if (-not [string]::IsNullOrWhiteSpace($startPort) -and -not [string]::IsNullOrWhiteSpace($endPort)) {
                ("{0}: {1} - {2}" -f $page, $startPort, $endPort)
            } else {
                ("Page {0}" -f $page)
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
        if (-not ($pagingState.Enabled -eq $true)) { return }

        $total = $orderedRows.Count
        $pageSize = [int]$pagingState.PageSize
        $pageCount = [int]$pagingState.PageCount
        $pageNumber = [int]$pagingState.PageNumber

        if ($pageCount -lt 1) { $pageCount = 1; $pagingState.PageCount = 1 }
        if ($pageNumber -lt 1) { $pageNumber = 1 }
        if ($pageNumber -gt $pageCount) { $pageNumber = $pageCount }
        $pagingState.PageNumber = $pageNumber

        try { $visibleRows.Clear() } catch { }
        if ($total -le 0) { return }

        $startIndex = ($pageNumber - 1) * $pageSize
        if ($startIndex -lt 0) { $startIndex = 0 }
        if ($startIndex -ge $total) { $startIndex = [Math]::Max(0, $total - 1) }
        $endIndex = [Math]::Min($total - 1, $startIndex + $pageSize - 1)

        for ($i = $startIndex; $i -le $endIndex; $i++) {
            try { $visibleRows.Add($orderedRows[$i]) | Out-Null } catch { }
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

    if ($pagingIsAvailable) {
        if (-not (Get-Variable -Name StateTracePortReorgPagingEnabled -Scope Global -ErrorAction SilentlyContinue)) {
            $global:StateTracePortReorgPagingEnabled = $false
        }

        $initialPagingEnabled = $false
        try { $initialPagingEnabled = [bool]$global:StateTracePortReorgPagingEnabled } catch { $initialPagingEnabled = $false }
        if ($pagedViewCheckBox) {
            try { $pagedViewCheckBox.IsChecked = $initialPagingEnabled } catch { }
        }

        $pagingState.Enabled = ($initialPagingEnabled -eq $true)

        try { & $rebuildPageChoices } catch { }
        try { & $setPagingControlsVisible -Enabled ($pagingState.Enabled -eq $true) } catch { }
        if ($pagingState.Enabled -eq $true) {
            try { & $updateVisibleRowsForCurrentPage } catch { }
            try { & $updatePagingControls } catch { }
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
                try { & $updateVisibleRowsForCurrentPage } catch { }
                $itemsSource = $visibleRows
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

    $setPagingEnabled = {
        param([bool]$Enabled)

        if (-not $pagingIsAvailable) { return }

        $selectedRow = $null
        try { if ($grid) { $selectedRow = $grid.SelectedItem } } catch { $selectedRow = $null }

        $pagingState.Enabled = ($Enabled -eq $true)
        try { $global:StateTracePortReorgPagingEnabled = ($pagingState.Enabled -eq $true) } catch { }

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
    }.GetNewClosure()

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
            if ($chunkBy12) { $chunkEnabled = ($chunkBy12.IsChecked -eq $true) }
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
            & $setStatus 'Scripts generated.' ''
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
                $enabled = ($pagedViewCheckBox.IsChecked -eq $true)
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

    try { & $refreshGrid } catch { }
    $win.Show() | Out-Null
}

Export-ModuleMember -Function Show-PortReorgWindow
