Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Creates and initializes the Cable Documentation view with visual hardware templates.

.DESCRIPTION
    Renders patch panels and switches as visual hardware templates with clickable ports.
    Supports Detail mode (view/edit port info) and Quick Connect mode (create cables).
    Part of Plan T - Cable & Port Documentation.
#>

# Import required dependency module globally so closures can access it
$cableDocModulePath = Join-Path $PSScriptRoot 'CableDocumentationModule.psm1'
if (Test-Path $cableDocModulePath) {
    Import-Module $cableDocModulePath -Force -Global -ErrorAction Stop
}

# Note: ThemeModule should already be loaded by the main application
# Don't reimport with -Force as it resets module state including current theme

# Script-level brush cache for performance
$script:PortStatusBrushes = $null
$script:CableTypeBrushes = $null

function Initialize-BrushCache {
    <#
    .SYNOPSIS
        Creates and freezes brushes using theme tokens with fallbacks.
    #>
    # Always reinitialize to pick up theme changes
    $converter = New-Object System.Windows.Media.BrushConverter

    # Port status brushes - use semantic colors
    $script:PortStatusBrushes = @{
        'Empty'     = ThemeModule\Get-ThemeBrushWithFallback -Key 'Theme.Status.Neutral' -Fallback '#555555'
        'Connected' = ThemeModule\Get-ThemeBrushWithFallback -Key 'Theme.Status.Success' -Fallback '#27AE60'
        'Reserved'  = ThemeModule\Get-ThemeBrushWithFallback -Key 'Theme.Status.Info' -Fallback '#3498DB'
        'Faulty'    = ThemeModule\Get-ThemeBrushWithFallback -Key 'Theme.Status.Danger' -Fallback '#E74C3C'
    }

    # Cable type brushes - these are more semantic, keep distinct colors
    $script:CableTypeBrushes = @{
        'Cat5e'    = $converter.ConvertFromString('#888888')
        'Cat6'     = $converter.ConvertFromString('#3498DB')
        'Cat6a'    = $converter.ConvertFromString('#2980B9')
        'FiberOM3' = $converter.ConvertFromString('#F39C12')
        'FiberOM4' = $converter.ConvertFromString('#E67E22')
        'FiberOS2' = $converter.ConvertFromString('#27AE60')
        'Coax'     = $converter.ConvertFromString('#9B59B6')
        'Other'    = $converter.ConvertFromString('#95A5A6')
    }

    # UI brushes - use theme tokens for proper light/dark theme support
    $script:SelectionBrush = ThemeModule\Get-ThemeBrushWithFallback -Key 'Theme.Button.Primary.Background' -Fallback '#F39C12'
    $script:PanelBackgroundBrush = ThemeModule\Get-ThemeBrushWithFallback -Key 'Theme.Surface.Secondary' -Fallback '#2D2D30'
    $script:PanelHeaderBrush = ThemeModule\Get-ThemeBrushWithFallback -Key 'Theme.Toolbar.Background' -Fallback '#3E3E42'
    # Use Toolbar.Text for text on colored surfaces (panel headers, port numbers)
    $script:TextBrush = ThemeModule\Get-ThemeBrushWithFallback -Key 'Theme.Toolbar.Text' -Fallback '#FFFFFF'
    $script:TextSecondaryBrush = ThemeModule\Get-ThemeBrushWithFallback -Key 'Theme.Text.Inverse' -Fallback '#AAAAAA'
    $script:BorderBrush = ThemeModule\Get-ThemeBrushWithFallback -Key 'Theme.Border.Primary' -Fallback '#555555'

    # Freeze cable type brushes
    foreach ($brush in $script:CableTypeBrushes.Values) {
        if ($brush -and $brush.CanFreeze) { $brush.Freeze() }
    }
}

function Get-CurrentBrushes {
    <#
    .SYNOPSIS
        Returns current brush cache for use in closures/theme change handlers.
    #>
    return @{
        PortStatus = $script:PortStatusBrushes
        CableType = $script:CableTypeBrushes
        Selection = $script:SelectionBrush
        PanelBackground = $script:PanelBackgroundBrush
        PanelHeader = $script:PanelHeaderBrush
        Text = $script:TextBrush
        TextSecondary = $script:TextSecondaryBrush
        Border = $script:BorderBrush
    }
}

function New-CableDocumentationView {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [System.Windows.Window]$Window,

        [Parameter(Mandatory=$true)]
        [string]$ScriptDir
    )

    try {
        $view = ViewCompositionModule\Set-StView -Window $Window -ScriptDir $ScriptDir `
            -ViewName 'CableDocumentationView' -HostControlName 'CableDocumentationHost' `
            -GlobalVariableName 'cableDocumentationView'
        if (-not $view) { return }

        Initialize-CableDocumentationControls -View $view
        return $view
    }
    catch {
        Write-Warning "Failed to initialize CableDocumentation view: $($_.Exception.Message)"
    }
}

function Initialize-CableDocumentationView {
    <#
    .SYNOPSIS
        Initializes the Cable Documentation view for nested tab container use.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.ContentControl]$Host
    )

    try {
        $viewPath = Join-Path $PSScriptRoot '..\Views\CableDocumentationView.xaml'
        if (-not (Test-Path $viewPath)) {
            Write-Warning "CableDocumentationView.xaml not found at: $viewPath"
            return
        }

        $xamlContent = Get-Content -Path $viewPath -Raw
        $xamlContent = $xamlContent -replace 'x:Class="[^"]*"', ''
        $xamlContent = $xamlContent -replace 'mc:Ignorable="d"', ''

        $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xamlContent))
        $view = [System.Windows.Markup.XamlReader]::Load($reader)

        # Note: DynamicResource bindings resolve from Application.Resources when view is in visual tree
        $Host.Content = $view

        Initialize-CableDocumentationControls -View $view
        return $view
    }
    catch {
        Write-Warning "Failed to initialize CableDocumentation view: $($_.Exception.Message)"
    }
}

function Initialize-CableDocumentationControls {
    <#
    .SYNOPSIS
        Wires up controls and event handlers for the Cable Documentation view.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $View
    )

    Initialize-BrushCache

    # Capture brush caches in local variables for closure capture
    # ($script: variables aren't captured by .GetNewClosure())
    $portStatusBrushes = $script:PortStatusBrushes
    $cableTypeBrushes = $script:CableTypeBrushes
    $selectionBrush = $script:SelectionBrush
    $panelBackgroundBrush = $script:PanelBackgroundBrush
    $panelHeaderBrush = $script:PanelHeaderBrush
    $textBrush = $script:TextBrush
    $textSecondaryBrush = $script:TextSecondaryBrush
    $borderBrush = $script:BorderBrush

    # Get controls from the new XAML layout
    $addPanelButton = $View.FindName('AddPanelButton')
    $quickConnectToggle = $View.FindName('QuickConnectToggle')
    $importButton = $View.FindName('ImportButton')
    $exportButton = $View.FindName('ExportButton')
    $filterBox = $View.FindName('FilterBox')
    $clearFilterButton = $View.FindName('ClearFilterButton')

    $panelListBox = $View.FindName('PanelListBox')
    $panelCountLabel = $View.FindName('PanelCountLabel')

    $hardwareCanvas = $View.FindName('HardwareCanvas')
    $canvasHeaderText = $View.FindName('CanvasHeaderText')
    $modeIndicator = $View.FindName('ModeIndicator')

    $detailsTitleLabel = $View.FindName('DetailsTitleLabel')
    $statusText = $View.FindName('StatusText')

    # Detail sections
    $portDetailsSection = $View.FindName('PortDetailsSection')
    $cableDetailsSection = $View.FindName('CableDetailsSection')
    $noCableSection = $View.FindName('NoCableSection')
    $quickConnectSection = $View.FindName('QuickConnectSection')
    $panelEditSection = $View.FindName('PanelEditSection')
    $emptyStateSection = $View.FindName('EmptyStateSection')

    # Port detail controls
    $portNumberText = $View.FindName('PortNumberText')
    $portStatusText = $View.FindName('PortStatusText')
    $portLabelBox = $View.FindName('PortLabelBox')
    $portPanelText = $View.FindName('PortPanelText')
    $savePortLabelButton = $View.FindName('SavePortLabelButton')

    # Cable detail controls
    $cableIdText = $View.FindName('CableIdText')
    $cableSourceText = $View.FindName('CableSourceText')
    $cableDestText = $View.FindName('CableDestText')
    $cableTypeText = $View.FindName('CableTypeText')
    $cableStatusText = $View.FindName('CableStatusText')
    $cableLengthText = $View.FindName('CableLengthText')
    $editCableButton = $View.FindName('EditCableButton')
    $traceCableButton = $View.FindName('TraceCableButton')
    $deleteCableButton = $View.FindName('DeleteCableButton')

    # Quick connect controls
    $quickConnectInstructions = $View.FindName('QuickConnectInstructions')
    $quickConnectSourceText = $View.FindName('QuickConnectSourceText')
    $cancelQuickConnectButton = $View.FindName('CancelQuickConnectButton')
    $createCableButton = $View.FindName('CreateCableButton')

    # Panel edit controls
    $panelNameBox = $View.FindName('PanelNameBox')
    $panelLocationBox = $View.FindName('PanelLocationBox')
    $panelRackIdBox = $View.FindName('PanelRackIdBox')
    $panelRackUBox = $View.FindName('PanelRackUBox')
    $panelPortCountText = $View.FindName('PanelPortCountText')
    $savePanelButton = $View.FindName('SavePanelButton')
    $deletePanelButton = $View.FindName('DeletePanelButton')

    # Initialize database
    $scriptDir = Split-Path $PSScriptRoot -Parent
    $dataPath = Join-Path $scriptDir 'Data\CableDatabase.json'
    $cableDb = CableDocumentationModule\New-CableDatabase

    if (Test-Path $dataPath) {
        try {
            CableDocumentationModule\Import-CableDatabase -Path $dataPath -Database $cableDb | Out-Null
            if ($statusText) { $statusText.Text = "Loaded database from $dataPath" }
        }
        catch {
            if ($statusText) { $statusText.Text = "Error loading database: $($_.Exception.Message)" }
        }
    }

    # Store state in view's Tag
    $View.Tag = @{
        Database = $cableDb
        DataPath = $dataPath
        InteractionMode = 'Detail'
        QuickConnectSource = $null
        SelectedPort = $null
        SelectedPanel = $null
        SelectedCable = $null
        IsNewPanel = $false
        PortElements = @{}  # Maps "PanelID:PortNum" to Border element
        PanelElements = @{} # Maps PanelID to panel Border element
        Callbacks = @{}     # Scriptblock callbacks for nested closures
        Brushes = @{        # Brush references for nested closures
            PortStatus = $portStatusBrushes
            CableType = $cableTypeBrushes
            Selection = $selectionBrush
            PanelBackground = $panelBackgroundBrush
            PanelHeader = $panelHeaderBrush
            Text = $textBrush
            TextSecondary = $textSecondaryBrush
            Border = $borderBrush
        }
    }

    # Helper: Save database
    $saveDatabase = {
        $dataPath = $View.Tag.DataPath
        $db = $View.Tag.Database
        try {
            $dataDir = Split-Path $dataPath -Parent
            if (-not (Test-Path $dataDir)) { New-Item -ItemType Directory -Path $dataDir -Force | Out-Null }
            CableDocumentationModule\Export-CableDatabase -Path $dataPath -Database $db
            if ($statusText) { $statusText.Text = "Saved to $dataPath" }
        }
        catch {
            if ($statusText) { $statusText.Text = "Error saving: $($_.Exception.Message)" }
        }
    }.GetNewClosure()

    # Helper: Hide all detail sections
    $hideAllSections = {
        if ($portDetailsSection) { $portDetailsSection.Visibility = 'Collapsed' }
        if ($cableDetailsSection) { $cableDetailsSection.Visibility = 'Collapsed' }
        if ($noCableSection) { $noCableSection.Visibility = 'Collapsed' }
        if ($quickConnectSection) { $quickConnectSection.Visibility = 'Collapsed' }
        if ($panelEditSection) { $panelEditSection.Visibility = 'Collapsed' }
        if ($emptyStateSection) { $emptyStateSection.Visibility = 'Collapsed' }
    }.GetNewClosure()

    # Helper: Show port details in right panel
    $showPortDetails = {
        param($Panel, $Port)

        & $hideAllSections

        $View.Tag.SelectedPort = @{ Panel = $Panel; Port = $Port }
        $View.Tag.SelectedPanel = $Panel

        if ($detailsTitleLabel) { $detailsTitleLabel.Text = "Port $($Port.PortNumber)" }
        if ($portDetailsSection) { $portDetailsSection.Visibility = 'Visible' }

        if ($portNumberText) { $portNumberText.Text = $Port.PortNumber.ToString() }
        if ($portStatusText) { $portStatusText.Text = $Port.Status }
        if ($portLabelBox) { $portLabelBox.Text = $Port.Label }
        if ($portPanelText) { $portPanelText.Text = $Panel.PanelName }

        # Check if port has a cable
        if ($Port.CableID) {
            $cable = CableDocumentationModule\Get-CableRun -CableID $Port.CableID -Database $View.Tag.Database
            if ($cable) {
                $View.Tag.SelectedCable = $cable
                if ($cableDetailsSection) { $cableDetailsSection.Visibility = 'Visible' }
                if ($cableIdText) { $cableIdText.Text = $cable.CableID }
                if ($cableSourceText) { $cableSourceText.Text = "$($cable.SourceDevice):$($cable.SourcePort)" }
                if ($cableDestText) { $cableDestText.Text = "$($cable.DestDevice):$($cable.DestPort)" }
                if ($cableTypeText) { $cableTypeText.Text = $cable.CableType }
                if ($cableStatusText) { $cableStatusText.Text = $cable.Status }
                if ($cableLengthText) { $cableLengthText.Text = $cable.Length }
            }
        }
        else {
            $View.Tag.SelectedCable = $null
            if ($noCableSection) { $noCableSection.Visibility = 'Visible' }
        }
    }.GetNewClosure()

    # Helper: Show panel edit form
    $showPanelEdit = {
        param($Panel, [bool]$IsNew)

        & $hideAllSections

        $View.Tag.SelectedPanel = $Panel
        $View.Tag.IsNewPanel = $IsNew

        if ($panelEditSection) { $panelEditSection.Visibility = 'Visible' }

        if ($IsNew) {
            if ($detailsTitleLabel) { $detailsTitleLabel.Text = "New Panel" }
            if ($panelNameBox) { $panelNameBox.Text = '' }
            if ($panelLocationBox) { $panelLocationBox.Text = '' }
            if ($panelRackIdBox) { $panelRackIdBox.Text = '' }
            if ($panelRackUBox) { $panelRackUBox.Text = '' }
            if ($panelPortCountText) { $panelPortCountText.Text = '24 ports (default)' }
        }
        else {
            if ($detailsTitleLabel) { $detailsTitleLabel.Text = $Panel.PanelName }
            if ($panelNameBox) { $panelNameBox.Text = $Panel.PanelName }
            if ($panelLocationBox) { $panelLocationBox.Text = $Panel.Location }
            if ($panelRackIdBox) { $panelRackIdBox.Text = $Panel.RackID }
            if ($panelRackUBox) { $panelRackUBox.Text = $Panel.RackU }
            if ($panelPortCountText) { $panelPortCountText.Text = "$($Panel.PortCount) ports" }
        }
    }.GetNewClosure()

    # Helper: Handle port click
    $handlePortClick = {
        param($Panel, $Port, $PortElement)

        if ($View.Tag.InteractionMode -eq 'QuickConnect') {
            if ($View.Tag.QuickConnectSource) {
                # Second click - create cable
                $source = $View.Tag.QuickConnectSource

                # Don't connect to same port
                if ($source.Panel.PanelID -eq $Panel.PanelID -and $source.Port.PortNumber -eq $Port.PortNumber) {
                    if ($statusText) { $statusText.Text = "Cannot connect port to itself" }
                    return
                }

                # Create cable
                try {
                    $cable = CableDocumentationModule\New-CableRun `
                        -SourceType 'PatchPanel' `
                        -SourceDevice $source.Panel.PanelName `
                        -SourcePort $source.Port.PortNumber.ToString() `
                        -DestType 'PatchPanel' `
                        -DestDevice $Panel.PanelName `
                        -DestPort $Port.PortNumber.ToString() `
                        -CableType 'Cat6' `
                        -Status 'Active'

                    CableDocumentationModule\Add-CableRun -Cable $cable -Database $View.Tag.Database | Out-Null

                    # Update port statuses
                    CableDocumentationModule\Set-PatchPanelPort -PanelID $source.Panel.PanelID `
                        -PortNumber $source.Port.PortNumber `
                        -CableID $cable.CableID -Status 'Connected' `
                        -Database $View.Tag.Database | Out-Null

                    CableDocumentationModule\Set-PatchPanelPort -PanelID $Panel.PanelID `
                        -PortNumber $Port.PortNumber `
                        -CableID $cable.CableID -Status 'Connected' `
                        -Database $View.Tag.Database | Out-Null

                    & $saveDatabase

                    if ($statusText) { $statusText.Text = "Created cable $($cable.CableID)" }

                    # Clear quick connect state
                    $View.Tag.QuickConnectSource = $null
                    if ($quickConnectSourceText) { $quickConnectSourceText.Text = '' }
                    if ($quickConnectInstructions) { $quickConnectInstructions.Text = 'Click a port to start' }
                    if ($cancelQuickConnectButton) { $cancelQuickConnectButton.Visibility = 'Collapsed' }

                    # Refresh canvas
                    & $renderHardwareCanvas
                }
                catch {
                    if ($statusText) { $statusText.Text = "Error: $($_.Exception.Message)" }
                }
            }
            else {
                # First click - select source
                $View.Tag.QuickConnectSource = @{ Panel = $Panel; Port = $Port; Element = $PortElement }
                if ($quickConnectSourceText) { $quickConnectSourceText.Text = "Source: $($Panel.PanelName) Port $($Port.PortNumber)" }
                if ($quickConnectInstructions) { $quickConnectInstructions.Text = 'Now click destination port' }
                if ($cancelQuickConnectButton) { $cancelQuickConnectButton.Visibility = 'Visible' }

                # Highlight source port
                $PortElement.BorderBrush = $selectionBrush
                $PortElement.BorderThickness = New-Object System.Windows.Thickness(2)
            }
        }
        else {
            # Detail mode - show port details
            & $showPortDetails $Panel $Port

            # Clear previous selection highlight
            foreach ($elem in $View.Tag.PortElements.Values) {
                $elem.BorderBrush = $borderBrush
                $elem.BorderThickness = New-Object System.Windows.Thickness(1)
            }

            # Highlight selected port
            $PortElement.BorderBrush = $selectionBrush
            $PortElement.BorderThickness = New-Object System.Windows.Thickness(2)
        }
    }.GetNewClosure()

    # Helper: Render a single hardware panel on canvas
    $renderHardwarePanel = {
        param($Panel, [int]$YPosition)

        try {
        $portWidth = 28
        $portHeight = 24
        $portMargin = 2
        $portsPerRow = 24
        $headerHeight = 28
        $padding = 8

        $rowCount = [Math]::Ceiling($Panel.PortCount / $portsPerRow)
        $panelWidth = ($portWidth + $portMargin * 2) * [Math]::Min($Panel.PortCount, $portsPerRow) + $padding * 2
        $panelHeight = $headerHeight + ($portHeight + $portMargin * 2) * $rowCount + $padding * 2

        # Panel container
        $panelBorder = New-Object System.Windows.Controls.Border
        $panelBorder.Width = $panelWidth
        $panelBorder.Height = $panelHeight
        $panelBorder.Background = $panelBackgroundBrush
        $panelBorder.BorderBrush = $borderBrush
        $panelBorder.BorderThickness = New-Object System.Windows.Thickness(1)
        $panelBorder.CornerRadius = New-Object System.Windows.CornerRadius(4)
        $panelBorder.Tag = $Panel

        $panelGrid = New-Object System.Windows.Controls.Grid
        $panelGrid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = [System.Windows.GridLength]::Auto }))
        $panelGrid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = [System.Windows.GridLength]::new(1, 'Star') }))

        # Header
        $headerBorder = New-Object System.Windows.Controls.Border
        $headerBorder.Background = $panelHeaderBrush
        $headerBorder.Padding = New-Object System.Windows.Thickness(8, 4, 8, 4)
        [System.Windows.Controls.Grid]::SetRow($headerBorder, 0)

        $headerStack = New-Object System.Windows.Controls.StackPanel
        $headerStack.Orientation = 'Horizontal'

        $nameText = New-Object System.Windows.Controls.TextBlock
        $nameText.Text = $Panel.PanelName
        $nameText.FontWeight = 'Bold'
        $nameText.Foreground = $textBrush
        $nameText.VerticalAlignment = 'Center'

        $portCountText = New-Object System.Windows.Controls.TextBlock
        $portCountText.Text = "  [$($Panel.PortCount)-Port]"
        $portCountText.Foreground = $textSecondaryBrush
        $portCountText.VerticalAlignment = 'Center'
        $portCountText.FontSize = 11

        $headerStack.Children.Add($nameText) | Out-Null
        $headerStack.Children.Add($portCountText) | Out-Null
        $headerBorder.Child = $headerStack

        # Port container
        $portCanvas = New-Object System.Windows.Controls.Canvas
        $portCanvas.Margin = New-Object System.Windows.Thickness($padding)
        [System.Windows.Controls.Grid]::SetRow($portCanvas, 1)

        # Render ports
        $portIndex = 0
        foreach ($port in $Panel.Ports) {
            $row = [Math]::Floor($portIndex / $portsPerRow)
            $col = $portIndex % $portsPerRow

            $x = $col * ($portWidth + $portMargin * 2) + $portMargin
            $y = $row * ($portHeight + $portMargin * 2) + $portMargin

            $portBorder = New-Object System.Windows.Controls.Border
            $portBorder.Width = $portWidth
            $portBorder.Height = $portHeight
            $portBorder.CornerRadius = New-Object System.Windows.CornerRadius(2)
            $portBorder.BorderBrush = $borderBrush
            $portBorder.BorderThickness = New-Object System.Windows.Thickness(1)
            $portBorder.Cursor = [System.Windows.Input.Cursors]::Hand

            # Status color
            $statusBrush = $portStatusBrushes[$port.Status]
            if (-not $statusBrush) { $statusBrush = $portStatusBrushes['Empty'] }
            $portBorder.Background = $statusBrush

            # Port number text
            $portText = New-Object System.Windows.Controls.TextBlock
            $portText.Text = $port.PortNumber.ToString()
            $portText.FontSize = 9
            $portText.FontWeight = 'Bold'
            $portText.Foreground = $textBrush
            $portText.HorizontalAlignment = 'Center'
            $portText.VerticalAlignment = 'Center'

            $portBorder.Child = $portText

            # Tooltip
            $tooltip = "Port $($port.PortNumber)"
            if ($port.Label) { $tooltip += ": $($port.Label)" }
            if ($port.CableID) { $tooltip += "`nCable: $($port.CableID)" }
            $tooltip += "`nStatus: $($port.Status)"
            $portBorder.ToolTip = $tooltip

            # Store reference for selection
            $portKey = "$($Panel.PanelID):$($port.PortNumber)"
            $View.Tag.PortElements[$portKey] = $portBorder

            # Click handler - need to capture current values
            $clickView = $View
            $clickPanel = $Panel
            $clickPort = $port
            $clickElement = $portBorder
            $portBorder.Add_MouseLeftButtonDown({
                param($sender, $e)
                $handler = $clickView.Tag.Callbacks.HandlePortClick
                if ($handler) { & $handler $clickPanel $clickPort $clickElement }
            }.GetNewClosure())

            [System.Windows.Controls.Canvas]::SetLeft($portBorder, $x)
            [System.Windows.Controls.Canvas]::SetTop($portBorder, $y)
            $portCanvas.Children.Add($portBorder) | Out-Null

            $portIndex++
        }

        $panelGrid.Children.Add($headerBorder) | Out-Null
        $panelGrid.Children.Add($portCanvas) | Out-Null
        $panelBorder.Child = $panelGrid

        # Store panel element reference
        $View.Tag.PanelElements[$Panel.PanelID] = $panelBorder

        # Position on canvas
        [System.Windows.Controls.Canvas]::SetLeft($panelBorder, 20)
        [System.Windows.Controls.Canvas]::SetTop($panelBorder, $YPosition)

        return @{
            Element = $panelBorder
            Height = $panelHeight
        }
        } catch {
            Write-Warning "renderHardwarePanel error: $($_.Exception.Message)"
            return $null
        }
    }.GetNewClosure()

    # Helper: Get port center position on canvas
    $getPortCenter = {
        param($PanelID, $PortNumber)

        $portKey = "$($PanelID):$($PortNumber)"
        $portElement = $View.Tag.PortElements[$portKey]
        $panelElement = $View.Tag.PanelElements[$PanelID]

        if (-not $portElement -or -not $panelElement) { return $null }

        # Get panel position
        $panelLeft = [System.Windows.Controls.Canvas]::GetLeft($panelElement)
        $panelTop = [System.Windows.Controls.Canvas]::GetTop($panelElement)

        # Get port position within panel (need to traverse visual tree)
        $portLeft = [System.Windows.Controls.Canvas]::GetLeft($portElement)
        $portTop = [System.Windows.Controls.Canvas]::GetTop($portElement)

        # Header height + padding
        $headerOffset = 28 + 8

        # Calculate center
        $centerX = $panelLeft + 8 + $portLeft + ($portElement.Width / 2)
        $centerY = $panelTop + $headerOffset + $portTop + ($portElement.Height / 2)

        return [System.Windows.Point]::new($centerX, $centerY)
    }.GetNewClosure()

    # Helper: Render cable lines between connected ports
    $renderCables = {
        $db = $View.Tag.Database
        $cables = @(CableDocumentationModule\Get-CableRun -Database $db)
        $panels = @(CableDocumentationModule\Get-PatchPanel -Database $db)

        # Build panel name to ID lookup
        $panelLookup = @{}
        foreach ($panel in $panels) {
            $panelLookup[$panel.PanelName] = $panel.PanelID
        }

        foreach ($cable in $cables) {
            # Only draw cables between patch panels (that we're displaying)
            if ($cable.SourceType -ne 'PatchPanel' -or $cable.DestType -ne 'PatchPanel') { continue }

            $sourcePanelID = $panelLookup[$cable.SourceDevice]
            $destPanelID = $panelLookup[$cable.DestDevice]

            if (-not $sourcePanelID -or -not $destPanelID) { continue }

            # Get port centers
            $sourcePort = [int]$cable.SourcePort
            $destPort = [int]$cable.DestPort

            $startPoint = & $getPortCenter $sourcePanelID $sourcePort
            $endPoint = & $getPortCenter $destPanelID $destPort

            if (-not $startPoint -or -not $endPoint) { continue }

            # Create bezier curve path
            $pathFigure = New-Object System.Windows.Media.PathFigure
            $pathFigure.StartPoint = $startPoint

            # Calculate control points for smooth curve
            $midY = ($startPoint.Y + $endPoint.Y) / 2
            $controlOffset = [Math]::Max(50, [Math]::Abs($endPoint.Y - $startPoint.Y) * 0.5)

            $bezier = New-Object System.Windows.Media.BezierSegment
            $bezier.Point1 = [System.Windows.Point]::new($startPoint.X + $controlOffset, $startPoint.Y)
            $bezier.Point2 = [System.Windows.Point]::new($endPoint.X - $controlOffset, $endPoint.Y)
            $bezier.Point3 = $endPoint

            $pathFigure.Segments.Add($bezier) | Out-Null

            $pathGeometry = New-Object System.Windows.Media.PathGeometry
            $pathGeometry.Figures.Add($pathFigure) | Out-Null

            $path = New-Object System.Windows.Shapes.Path
            $path.Data = $pathGeometry
            $path.StrokeThickness = 2
            $path.Cursor = [System.Windows.Input.Cursors]::Hand
            $path.Tag = $cable

            # Cable type color
            $cableBrush = $cableTypeBrushes[$cable.CableType]
            if (-not $cableBrush) { $cableBrush = $cableTypeBrushes['Other'] }
            $path.Stroke = $cableBrush

            # Status opacity
            $path.Opacity = switch ($cable.Status) {
                'Active' { 1.0 }
                'Reserved' { 0.7 }
                'Planned' { 0.5 }
                'Abandoned' { 0.3 }
                'Faulty' { 0.8 }
                default { 1.0 }
            }

            # Tooltip
            $path.ToolTip = "Cable: $($cable.CableID)`n$($cable.SourceDevice):$($cable.SourcePort) -> $($cable.DestDevice):$($cable.DestPort)`nType: $($cable.CableType)`nStatus: $($cable.Status)"

            # Click handler to show cable details
            $clickView = $View
            $clickCable = $cable
            $path.Add_MouseLeftButtonDown({
                param($sender, $e)
                # Find a port with this cable and show its details
                $panels = @(CableDocumentationModule\Get-PatchPanel -Database $clickView.Tag.Database)
                foreach ($panel in $panels) {
                    foreach ($port in $panel.Ports) {
                        if ($port.CableID -eq $clickCable.CableID) {
                            $handler = $clickView.Tag.Callbacks.ShowPortDetails
                            if ($handler) { & $handler $panel $port }
                            $e.Handled = $true
                            return
                        }
                    }
                }
            }.GetNewClosure())

            # Add to canvas (cables drawn first, panels on top)
            $hardwareCanvas.Children.Insert(0, $path) | Out-Null
        }
    }.GetNewClosure()

    # Helper: Render all hardware panels
    $renderHardwareCanvas = {
        if (-not $hardwareCanvas) { return }

        $hardwareCanvas.Children.Clear()
        $View.Tag.PortElements = @{}
        $View.Tag.PanelElements = @{}

        $db = $View.Tag.Database
        $panels = @(CableDocumentationModule\Get-PatchPanel -Database $db)

        # Apply filter
        $filter = $filterBox.Text
        if (-not [string]::IsNullOrWhiteSpace($filter)) {
            $panels = @($panels | Where-Object {
                $_.PanelID -like "*$filter*" -or
                $_.PanelName -like "*$filter*" -or
                $_.Location -like "*$filter*"
            })
        }

        $yPos = 20
        $maxWidth = 800

        foreach ($panel in $panels) {
            $result = & $renderHardwarePanel $panel $yPos
            if ($result -and $result.Element) {
                $hardwareCanvas.Children.Add($result.Element) | Out-Null
                $yPos += $result.Height + 20

                # Update canvas size
                $elementRight = 20 + $result.Element.Width + 40
                if ($elementRight -gt $maxWidth) { $maxWidth = $elementRight }
            }
        }

        # Resize canvas to fit content
        $hardwareCanvas.Width = $maxWidth
        $hardwareCanvas.Height = [Math]::Max(600, $yPos + 20)

        # Render cable lines between connected ports
        & $renderCables

        # Update panel list
        if ($panelListBox) { $panelListBox.ItemsSource = $panels }
        if ($panelCountLabel) { $panelCountLabel.Content = "($($panels.Count))" }

        # Show empty state if no panels
        if ($panels.Count -eq 0) {
            & $hideAllSections
            if ($emptyStateSection) { $emptyStateSection.Visibility = 'Visible' }
        }
    }.GetNewClosure()

    # Store callbacks in View.Tag for access by nested closures
    $View.Tag.Callbacks = @{
        HandlePortClick = $handlePortClick
        ShowPortDetails = $showPortDetails
        ShowPanelEdit = $showPanelEdit
        HideAllSections = $hideAllSections
        SaveDatabase = $saveDatabase
        RenderHardwareCanvas = $renderHardwareCanvas
        RenderHardwarePanel = $renderHardwarePanel
        RenderCables = $renderCables
    }

    # Event: Add Panel button
    if ($addPanelButton) {
        $addPanelButton.Add_Click({
            try {
                & $showPanelEdit $null $true
            }
            catch {
                if ($statusText) { $statusText.Text = "Error: $($_.Exception.Message)" }
            }
        }.GetNewClosure())
    }

    # Event: Quick Connect toggle
    if ($quickConnectToggle) {
        $quickConnectToggle.Add_Checked({
            $View.Tag.InteractionMode = 'QuickConnect'
            $View.Tag.QuickConnectSource = $null

            if ($modeIndicator) { $modeIndicator.Text = 'Quick Connect Mode' }

            & $hideAllSections
            if ($quickConnectSection) { $quickConnectSection.Visibility = 'Visible' }
            if ($quickConnectInstructions) { $quickConnectInstructions.Text = 'Click a port to start' }
            if ($quickConnectSourceText) { $quickConnectSourceText.Text = '' }
            if ($cancelQuickConnectButton) { $cancelQuickConnectButton.Visibility = 'Collapsed' }
        }.GetNewClosure())

        $quickConnectToggle.Add_Unchecked({
            $View.Tag.InteractionMode = 'Detail'
            $View.Tag.QuickConnectSource = $null

            if ($modeIndicator) { $modeIndicator.Text = '' }

            & $hideAllSections
            if ($emptyStateSection) { $emptyStateSection.Visibility = 'Visible' }

            # Clear any selection highlights
            foreach ($elem in $View.Tag.PortElements.Values) {
                $elem.BorderBrush = $borderBrush
                $elem.BorderThickness = New-Object System.Windows.Thickness(1)
            }
        }.GetNewClosure())
    }

    # Event: Cancel Quick Connect
    if ($cancelQuickConnectButton) {
        $cancelQuickConnectButton.Add_Click({
            $View.Tag.QuickConnectSource = $null
            if ($quickConnectSourceText) { $quickConnectSourceText.Text = '' }
            if ($quickConnectInstructions) { $quickConnectInstructions.Text = 'Click a port to start' }
            if ($cancelQuickConnectButton) { $cancelQuickConnectButton.Visibility = 'Collapsed' }

            # Clear highlight
            foreach ($elem in $View.Tag.PortElements.Values) {
                $elem.BorderBrush = $borderBrush
                $elem.BorderThickness = New-Object System.Windows.Thickness(1)
            }
        }.GetNewClosure())
    }

    # Event: Create Cable (from empty port)
    if ($createCableButton) {
        $createCableButton.Add_Click({
            # Switch to quick connect mode with current port as source
            $selected = $View.Tag.SelectedPort
            if ($selected -and $quickConnectToggle) {
                $quickConnectToggle.IsChecked = $true
                # Set this port as source
                $View.Tag.QuickConnectSource = @{ Panel = $selected.Panel; Port = $selected.Port }
                if ($quickConnectSourceText) { $quickConnectSourceText.Text = "Source: $($selected.Panel.PanelName) Port $($selected.Port.PortNumber)" }
                if ($quickConnectInstructions) { $quickConnectInstructions.Text = 'Now click destination port' }
                if ($cancelQuickConnectButton) { $cancelQuickConnectButton.Visibility = 'Visible' }
            }
        }.GetNewClosure())
    }

    # Event: Save Port Label
    if ($savePortLabelButton) {
        $savePortLabelButton.Add_Click({
            $selected = $View.Tag.SelectedPort
            if (-not $selected) { return }

            try {
                CableDocumentationModule\Set-PatchPanelPort `
                    -PanelID $selected.Panel.PanelID `
                    -PortNumber $selected.Port.PortNumber `
                    -Label $portLabelBox.Text `
                    -Database $View.Tag.Database | Out-Null

                & $saveDatabase
                & $renderHardwareCanvas

                if ($statusText) { $statusText.Text = "Saved label for Port $($selected.Port.PortNumber)" }
            }
            catch {
                if ($statusText) { $statusText.Text = "Error: $($_.Exception.Message)" }
            }
        }.GetNewClosure())
    }

    # Event: Delete Cable
    if ($deleteCableButton) {
        $deleteCableButton.Add_Click({
            $cable = $View.Tag.SelectedCable
            if (-not $cable) { return }

            $result = [System.Windows.MessageBox]::Show(
                "Delete cable $($cable.CableID)?",
                "Confirm Delete",
                [System.Windows.MessageBoxButton]::YesNo,
                [System.Windows.MessageBoxImage]::Warning)

            if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
                try {
                    # Clear port references
                    $panels = @(CableDocumentationModule\Get-PatchPanel -Database $View.Tag.Database)
                    foreach ($panel in $panels) {
                        foreach ($port in $panel.Ports) {
                            if ($port.CableID -eq $cable.CableID) {
                                CableDocumentationModule\Set-PatchPanelPort `
                                    -PanelID $panel.PanelID `
                                    -PortNumber $port.PortNumber `
                                    -CableID $null -Status 'Empty' `
                                    -Database $View.Tag.Database | Out-Null
                            }
                        }
                    }

                    CableDocumentationModule\Remove-CableRun -CableID $cable.CableID -Database $View.Tag.Database | Out-Null

                    & $saveDatabase
                    & $renderHardwareCanvas

                    & $hideAllSections
                    if ($emptyStateSection) { $emptyStateSection.Visibility = 'Visible' }

                    if ($statusText) { $statusText.Text = "Deleted cable $($cable.CableID)" }
                }
                catch {
                    if ($statusText) { $statusText.Text = "Error: $($_.Exception.Message)" }
                }
            }
        }.GetNewClosure())
    }

    # Event: Edit Cable
    if ($editCableButton) {
        $editCableButton.Add_Click({
            $cable = $View.Tag.SelectedCable
            if (-not $cable) {
                if ($statusText) { $statusText.Text = 'No cable selected' }
                return
            }

            Add-Type -AssemblyName Microsoft.VisualBasic
            $newType = [Microsoft.VisualBasic.Interaction]::InputBox(
                "Enter cable type (e.g., Cat6, Fiber, Coax):",
                "Edit Cable Type",
                $cable.CableType
            )
            if ([string]::IsNullOrWhiteSpace($newType)) { return }

            $newLength = [Microsoft.VisualBasic.Interaction]::InputBox(
                "Enter cable length (e.g., 10ft, 3m):",
                "Edit Cable Length",
                $cable.Length
            )

            try {
                CableDocumentationModule\Update-CableRun `
                    -CableID $cable.CableID `
                    -Properties @{ CableType = $newType; Length = $newLength } `
                    -Database $View.Tag.Database | Out-Null

                & $saveDatabase
                & $renderHardwareCanvas

                # Update displayed info
                if ($cableTypeText) { $cableTypeText.Text = $newType }
                if ($cableLengthText) { $cableLengthText.Text = $newLength }

                if ($statusText) { $statusText.Text = "Updated cable $($cable.CableID)" }
            }
            catch {
                if ($statusText) { $statusText.Text = "Error: $($_.Exception.Message)" }
            }
        }.GetNewClosure())
    }

    # Event: Trace Cable
    if ($traceCableButton) {
        $traceCableButton.Add_Click({
            $cable = $View.Tag.SelectedCable
            if (-not $cable) {
                if ($statusText) { $statusText.Text = 'No cable selected' }
                return
            }

            # Build trace information
            $traceInfo = @(
                "Cable Trace: $($cable.CableID)",
                "=" * 40,
                "",
                "Source: $($cable.SourceDevice) Port $($cable.SourcePort)",
                "Destination: $($cable.DestDevice) Port $($cable.DestPort)",
                "",
                "Type: $($cable.CableType)",
                "Length: $($cable.Length)",
                "Status: $($cable.Status)"
            ) -join "`r`n"

            [System.Windows.MessageBox]::Show(
                $traceInfo,
                "Cable Trace",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Information
            )

            if ($statusText) { $statusText.Text = "Traced cable $($cable.CableID)" }
        }.GetNewClosure())
    }

    # Event: Save Panel
    if ($savePanelButton) {
        $savePanelButton.Add_Click({
            $db = $View.Tag.Database

            if ([string]::IsNullOrWhiteSpace($panelNameBox.Text)) {
                if ($statusText) { $statusText.Text = 'Please enter a panel name' }
                return
            }

            try {
                if ($View.Tag.IsNewPanel) {

                    $params = @{ PanelName = $panelNameBox.Text }
                    if ($panelLocationBox -and $panelLocationBox.Text) { $params['Location'] = $panelLocationBox.Text }
                    if ($panelRackIdBox -and $panelRackIdBox.Text) { $params['RackID'] = $panelRackIdBox.Text }
                    if ($panelRackUBox -and $panelRackUBox.Text) { $params['RackU'] = $panelRackUBox.Text }

                    $panel = CableDocumentationModule\New-PatchPanel @params
                    CableDocumentationModule\Add-PatchPanel -Panel $panel -Database $db | Out-Null

                    if ($statusText) { $statusText.Text = "Created panel $($panel.PanelName)" }
                }
                else {
                    $panel = $View.Tag.SelectedPanel
                    $panel.PanelName = $panelNameBox.Text
                    $panel.Location = $panelLocationBox.Text
                    $panel.RackID = $panelRackIdBox.Text
                    $panel.RackU = $panelRackUBox.Text
                    $panel.ModifiedDate = Get-Date

                    if ($statusText) { $statusText.Text = "Updated panel $($panel.PanelName)" }
                }

                & $saveDatabase
                & $renderHardwareCanvas

                & $hideAllSections
                if ($emptyStateSection) { $emptyStateSection.Visibility = 'Visible' }
            }
            catch {
                if ($statusText) { $statusText.Text = "Error: $($_.Exception.Message)" }
            }
        }.GetNewClosure())
    }

    # Event: Delete Panel
    if ($deletePanelButton) {
        $deletePanelButton.Add_Click({
            $panel = $View.Tag.SelectedPanel
            if (-not $panel -or $View.Tag.IsNewPanel) { return }

            $result = [System.Windows.MessageBox]::Show(
                "Delete panel $($panel.PanelName)?",
                "Confirm Delete",
                [System.Windows.MessageBoxButton]::YesNo,
                [System.Windows.MessageBoxImage]::Warning)

            if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
                try {
                    CableDocumentationModule\Remove-PatchPanel -PanelID $panel.PanelID -Database $View.Tag.Database | Out-Null

                    & $saveDatabase
                    & $renderHardwareCanvas

                    & $hideAllSections
                    if ($emptyStateSection) { $emptyStateSection.Visibility = 'Visible' }

                    if ($statusText) { $statusText.Text = "Deleted panel $($panel.PanelName)" }
                }
                catch {
                    if ($statusText) { $statusText.Text = "Error: $($_.Exception.Message)" }
                }
            }
        }.GetNewClosure())
    }

    # Event: Panel list selection - scroll to panel
    if ($panelListBox) {
        $panelListBox.Add_SelectionChanged({
            param($sender, $e)
            $selected = $sender.SelectedItem
            if ($selected) {
                & $showPanelEdit $selected $false

                # Scroll canvas to panel
                $panelElement = $View.Tag.PanelElements[$selected.PanelID]
                if ($panelElement) {
                    $panelElement.BringIntoView()
                }
            }
        }.GetNewClosure())
    }

    # Event: Filter change
    if ($filterBox) {
        $filterBox.Add_TextChanged({
            & $renderHardwareCanvas
        }.GetNewClosure())
    }

    # Event: Clear filter
    if ($clearFilterButton) {
        $clearFilterButton.Add_Click({
            if ($filterBox) { $filterBox.Text = '' }
        }.GetNewClosure())
    }

    # Event: Import
    if ($importButton) {
        $importButton.Add_Click({
            try {
                $dialog = New-Object Microsoft.Win32.OpenFileDialog
                $dialog.Title = 'Import Cable Database'
                $dialog.Filter = 'JSON files (*.json)|*.json'

                if ($dialog.ShowDialog() -eq $true) {
                    $db = $View.Tag.Database
                    $result = CableDocumentationModule\Import-CableDatabase -Path $dialog.FileName -Database $db -Merge
                    if ($statusText) { $statusText.Text = "Imported $($result.CablesImported) cables, $($result.PanelsImported) panels" }
                    & $saveDatabase
                    & $renderHardwareCanvas
                }
            }
            catch {
                if ($statusText) { $statusText.Text = "Import error: $($_.Exception.Message)" }
            }
        }.GetNewClosure())
    }

    # Event: Export
    if ($exportButton) {
        $exportButton.Add_Click({
            try {
                $dialog = New-Object Microsoft.Win32.SaveFileDialog
                $dialog.Title = 'Export Cable Database'
                $dialog.Filter = 'JSON files (*.json)|*.json'
                $dialog.DefaultExt = '.json'

                if ($dialog.ShowDialog() -eq $true) {
                    $db = $View.Tag.Database
                    CableDocumentationModule\Export-CableDatabase -Path $dialog.FileName -Database $db
                    if ($statusText) { $statusText.Text = "Exported database to $($dialog.FileName)" }
                }
            }
            catch {
                if ($statusText) { $statusText.Text = "Export error: $($_.Exception.Message)" }
            }
        }.GetNewClosure())
    }

    # Initial render
    & $renderHardwareCanvas
    if ($statusText) { $statusText.Text = 'Ready' }
}

Export-ModuleMember -Function New-CableDocumentationView, Initialize-CableDocumentationView, Initialize-BrushCache, Get-CurrentBrushes
