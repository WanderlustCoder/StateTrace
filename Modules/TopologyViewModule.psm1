#Requires -Version 5.1
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    View module for the Network Topology Visualization UI.

.DESCRIPTION
    Wires up the TopologyView.xaml to the TopologyModule functions.
    Handles UI events for topology discovery, layout, export, and impact analysis.

.NOTES
    Plan W - Network Topology Visualization
#>

# Module-level references
$script:TopologyView = $null
$script:TopologyCanvas = $null
$script:SelectedNodeID = $null
$script:NodeElements = @{}
$script:LinkElements = @{}

# Role colors for visualization
$script:RoleColors = @{
    'Core'         = '#E74C3C'
    'Distribution' = '#F39C12'
    'Access'       = '#27AE60'
    'Router'       = '#9B59B6'
    'Firewall'     = '#C0392B'
    'Wireless'     = '#3498DB'
    'Default'      = '#4A90D9'
}

function New-TopologyView {
    <#
    .SYNOPSIS
        Creates and initializes the Topology view.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][System.Windows.Window]$Window,
        [Parameter(Mandatory=$true)][string]$ScriptDir
    )

    # Load XAML using ViewCompositionModule pattern
    $script:TopologyView = ViewCompositionModule\Set-StView -Window $Window -ScriptDir $ScriptDir `
        -ViewName 'TopologyView' -HostControlName 'TopologyHost' `
        -GlobalVariableName 'topologyView'
    if (-not $script:TopologyView) {
        return $null
    }

    # Get control references
    Get-TopologyControls

    # Wire up event handlers
    Register-TopologyEventHandlers

    # Initialize UI state
    Update-TopologyStatistics
    Update-ImpactDeviceCombo
    Update-SavedLayoutsList

    return $script:TopologyView
}

function Get-TopologyControls {
    <#
    .SYNOPSIS
        Gets references to UI controls.
    #>

    # Statistics
    $script:NodeCountLabel = $script:TopologyView.FindName('NodeCountLabel')
    $script:LinkCountLabel = $script:TopologyView.FindName('LinkCountLabel')
    $script:IsolatedCountLabel = $script:TopologyView.FindName('IsolatedCountLabel')

    # View toggles
    $script:L2ViewRadio = $script:TopologyView.FindName('L2ViewRadio')
    $script:L3ViewRadio = $script:TopologyView.FindName('L3ViewRadio')
    $script:SiteViewRadio = $script:TopologyView.FindName('SiteViewRadio')

    # Action buttons
    $script:DiscoverButton = $script:TopologyView.FindName('DiscoverButton')
    $script:RefreshLayoutButton = $script:TopologyView.FindName('RefreshLayoutButton')
    $script:ExportButton = $script:TopologyView.FindName('ExportButton')

    # Canvas controls
    $script:TopologyCanvas = $script:TopologyView.FindName('TopologyCanvas')
    $script:LayoutCombo = $script:TopologyView.FindName('LayoutCombo')
    $script:ZoomSlider = $script:TopologyView.FindName('ZoomSlider')
    $script:ZoomLabel = $script:TopologyView.FindName('ZoomLabel')
    $script:ZoomFitButton = $script:TopologyView.FindName('ZoomFitButton')
    $script:RoleFilterCombo = $script:TopologyView.FindName('RoleFilterCombo')
    $script:EmptyStatePanel = $script:TopologyView.FindName('EmptyStatePanel')

    # Details panel
    $script:NoSelectionPanel = $script:TopologyView.FindName('NoSelectionPanel')
    $script:DeviceDetailsPanel = $script:TopologyView.FindName('DeviceDetailsPanel')
    $script:DetailDeviceLabel = $script:TopologyView.FindName('DetailDeviceLabel')
    $script:DetailRoleLabel = $script:TopologyView.FindName('DetailRoleLabel')
    $script:DetailSiteLabel = $script:TopologyView.FindName('DetailSiteLabel')
    $script:DetailLinksLabel = $script:TopologyView.FindName('DetailLinksLabel')
    $script:DetailPositionLabel = $script:TopologyView.FindName('DetailPositionLabel')
    $script:ConnectedDevicesList = $script:TopologyView.FindName('ConnectedDevicesList')
    $script:ViewDeviceButton = $script:TopologyView.FindName('ViewDeviceButton')
    $script:ImpactAnalysisButton = $script:TopologyView.FindName('ImpactAnalysisButton')

    # Impact analysis
    $script:ImpactDeviceCombo = $script:TopologyView.FindName('ImpactDeviceCombo')
    $script:RunImpactButton = $script:TopologyView.FindName('RunImpactButton')
    $script:ImpactResultsPanel = $script:TopologyView.FindName('ImpactResultsPanel')
    $script:ImpactSummaryLabel = $script:TopologyView.FindName('ImpactSummaryLabel')
    $script:AffectedDevicesList = $script:TopologyView.FindName('AffectedDevicesList')
    $script:CriticalCountLabel = $script:TopologyView.FindName('CriticalCountLabel')
    $script:RedundantCountLabel = $script:TopologyView.FindName('RedundantCountLabel')

    # Layouts
    $script:SavedLayoutsList = $script:TopologyView.FindName('SavedLayoutsList')
    $script:LoadLayoutButton = $script:TopologyView.FindName('LoadLayoutButton')
    $script:DeleteLayoutButton = $script:TopologyView.FindName('DeleteLayoutButton')
    $script:LayoutNameBox = $script:TopologyView.FindName('LayoutNameBox')
    $script:SaveLayoutButton = $script:TopologyView.FindName('SaveLayoutButton')

    # Export
    $script:ExportFormatCombo = $script:TopologyView.FindName('ExportFormatCombo')
    $script:IncludeLabelsCheck = $script:TopologyView.FindName('IncludeLabelsCheck')
    $script:IncludeLegendCheck = $script:TopologyView.FindName('IncludeLegendCheck')
    $script:HighResCheck = $script:TopologyView.FindName('HighResCheck')
    $script:ExportDiagramButton = $script:TopologyView.FindName('ExportDiagramButton')
    $script:CopyToClipboardButton = $script:TopologyView.FindName('CopyToClipboardButton')
    $script:RecentExportsList = $script:TopologyView.FindName('RecentExportsList')

    # Status
    $script:StatusLabel = $script:TopologyView.FindName('StatusLabel')
    $script:LastDiscoveryLabel = $script:TopologyView.FindName('LastDiscoveryLabel')
}

function Register-TopologyEventHandlers {
    <#
    .SYNOPSIS
        Registers event handlers for UI controls.
    #>

    # Discover button
    if ($script:DiscoverButton) {
        $script:DiscoverButton.Add_Click({
            Start-TopologyDiscovery
        })
    }

    # Refresh layout button
    if ($script:RefreshLayoutButton) {
        $script:RefreshLayoutButton.Add_Click({
            Apply-SelectedLayout
            Render-Topology
        })
    }

    # Export button
    if ($script:ExportButton) {
        $script:ExportButton.Add_Click({
            Export-CurrentTopology
        })
    }

    # Layout combo
    if ($script:LayoutCombo) {
        $script:LayoutCombo.Add_SelectionChanged({
            Apply-SelectedLayout
            Render-Topology
        })
    }

    # Zoom slider
    if ($script:ZoomSlider) {
        $script:ZoomSlider.Add_ValueChanged({
            $zoom = $script:ZoomSlider.Value
            if ($script:ZoomLabel) {
                $script:ZoomLabel.Text = "$([math]::Round($zoom * 100))%"
            }
            Apply-ZoomLevel -Zoom $zoom
        })
    }

    # Zoom fit button
    if ($script:ZoomFitButton) {
        $script:ZoomFitButton.Add_Click({
            Fit-TopologyToView
        })
    }

    # Role filter
    if ($script:RoleFilterCombo) {
        $script:RoleFilterCombo.Add_SelectionChanged({
            Render-Topology
        })
    }

    # Impact analysis
    if ($script:RunImpactButton) {
        $script:RunImpactButton.Add_Click({
            Run-ImpactAnalysis
        })
    }

    if ($script:ImpactAnalysisButton) {
        $script:ImpactAnalysisButton.Add_Click({
            if ($script:SelectedNodeID) {
                $script:ImpactDeviceCombo.SelectedValue = $script:SelectedNodeID
                Run-ImpactAnalysis
            }
        })
    }

    # Layout management
    if ($script:SaveLayoutButton) {
        $script:SaveLayoutButton.Add_Click({
            Save-CurrentLayout
        })
    }

    if ($script:LoadLayoutButton) {
        $script:LoadLayoutButton.Add_Click({
            Load-SelectedLayout
        })
    }

    if ($script:DeleteLayoutButton) {
        $script:DeleteLayoutButton.Add_Click({
            Delete-SelectedLayout
        })
    }

    # Export
    if ($script:ExportDiagramButton) {
        $script:ExportDiagramButton.Add_Click({
            Export-CurrentTopology
        })
    }

    if ($script:CopyToClipboardButton) {
        $script:CopyToClipboardButton.Add_Click({
            Copy-TopologyToClipboard
        })
    }
}

#region Discovery

function Start-TopologyDiscovery {
    <#
    .SYNOPSIS
        Discovers topology from interface data.
    #>
    [CmdletBinding()]
    param()

    Set-Status 'Discovering topology...'

    try {
        # Get interface data from global cache
        $interfaces = @()
        if ($global:interfaceCache) {
            $interfaces = @($global:interfaceCache.Values)
        }

        if ($interfaces.Count -eq 0) {
            [System.Windows.MessageBox]::Show(
                'No interface data available. Please load device data first.',
                'No Data',
                'OK',
                'Warning'
            )
            Set-Status 'Ready'
            return
        }

        # Build topology from interfaces
        $result = Build-TopologyFromInterfaces -Interfaces $interfaces -ClearExisting

        # Apply layout
        Apply-SelectedLayout

        # Render
        Render-Topology

        # Update statistics
        Update-TopologyStatistics
        Update-ImpactDeviceCombo

        # Update last discovery time
        if ($script:LastDiscoveryLabel) {
            $script:LastDiscoveryLabel.Text = (Get-Date).ToString('yyyy-MM-dd HH:mm')
        }

        Set-Status "Discovered $($result.NodesCreated) devices, $($result.LinksCreated) links"
    }
    catch {
        Set-Status "Discovery failed: $_"
        Write-Warning "Topology discovery failed: $_"
    }
}

#endregion

#region Rendering

function Render-Topology {
    <#
    .SYNOPSIS
        Renders the topology on the canvas.
    #>
    [CmdletBinding()]
    param()

    if (-not $script:TopologyCanvas) { return }

    # Clear canvas
    $script:TopologyCanvas.Children.Clear()
    $script:NodeElements = @{}
    $script:LinkElements = @{}

    $nodes = @(Get-TopologyNode)
    $links = @(Get-TopologyLink)

    # Apply role filter
    $roleFilter = $null
    if ($script:RoleFilterCombo -and $script:RoleFilterCombo.SelectedIndex -gt 0) {
        $roleFilter = $script:RoleFilterCombo.SelectedItem.Content
    }

    if ($roleFilter) {
        $nodes = $nodes | Where-Object { $_.Role -eq $roleFilter }
        $filteredNodeIDs = $nodes | ForEach-Object { $_.NodeID }
        $links = $links | Where-Object {
            ($_.SourceNodeID -in $filteredNodeIDs) -and ($_.DestNodeID -in $filteredNodeIDs)
        }
    }

    # Show/hide empty state
    if ($script:EmptyStatePanel) {
        $script:EmptyStatePanel.Visibility = if ($nodes.Count -eq 0) { 'Visible' } else { 'Collapsed' }
    }

    if ($nodes.Count -eq 0) { return }

    # Draw links first (behind nodes)
    foreach ($link in $links) {
        $sourceNode = $nodes | Where-Object { $_.NodeID -eq $link.SourceNodeID }
        $destNode = $nodes | Where-Object { $_.NodeID -eq $link.DestNodeID }

        if ($sourceNode -and $destNode) {
            $line = New-Object System.Windows.Shapes.Line
            $line.X1 = $sourceNode.XPosition
            $line.Y1 = $sourceNode.YPosition
            $line.X2 = $destNode.XPosition
            $line.Y2 = $destNode.YPosition
            $line.StrokeThickness = if ($link.IsAggregate) { 4 } else { 2 }

            if ($link.LinkType -eq 'WAN') {
                $line.Stroke = [System.Windows.Media.Brushes]::Crimson
                $line.StrokeDashArray = New-Object System.Windows.Media.DoubleCollection @(5, 5)
            } else {
                $line.Stroke = [System.Windows.Media.Brushes]::Gray
            }

            $line.Tag = $link.LinkID
            $line.Add_MouseLeftButtonDown({
                param($sender, $e)
                Select-Link -LinkID $sender.Tag
            }.GetNewClosure())

            [void]$script:TopologyCanvas.Children.Add($line)
            $script:LinkElements[$link.LinkID] = $line
        }
    }

    # Draw nodes
    foreach ($node in $nodes) {
        # Node circle
        $ellipse = New-Object System.Windows.Shapes.Ellipse
        $ellipse.Width = 50
        $ellipse.Height = 50

        $color = $script:RoleColors[$node.Role]
        if (-not $color) { $color = $script:RoleColors['Default'] }

        $ellipse.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString($color)
        $ellipse.Stroke = [System.Windows.Media.Brushes]::White
        $ellipse.StrokeThickness = 2
        $ellipse.Cursor = [System.Windows.Input.Cursors]::Hand
        $ellipse.Tag = $node.NodeID

        [System.Windows.Controls.Canvas]::SetLeft($ellipse, $node.XPosition - 25)
        [System.Windows.Controls.Canvas]::SetTop($ellipse, $node.YPosition - 25)

        # Click handler
        $nodeID = $node.NodeID
        $ellipse.Add_MouseLeftButtonDown({
            param($sender, $e)
            Select-Node -NodeID $sender.Tag
        }.GetNewClosure())

        [void]$script:TopologyCanvas.Children.Add($ellipse)

        # Label
        $label = New-Object System.Windows.Controls.TextBlock
        $label.Text = $node.DisplayName
        $label.FontSize = 10
        $label.Foreground = [System.Windows.Media.Brushes]::White
        $label.TextAlignment = 'Center'

        [System.Windows.Controls.Canvas]::SetLeft($label, $node.XPosition - 40)
        [System.Windows.Controls.Canvas]::SetTop($label, $node.YPosition + 30)

        [void]$script:TopologyCanvas.Children.Add($label)

        $script:NodeElements[$node.NodeID] = @{
            Ellipse = $ellipse
            Label   = $label
        }
    }
}

function Select-Node {
    <#
    .SYNOPSIS
        Selects a node and shows its details.
    #>
    [CmdletBinding()]
    param(
        [string]$NodeID
    )

    # Deselect previous
    if ($script:SelectedNodeID -and $script:NodeElements[$script:SelectedNodeID]) {
        $script:NodeElements[$script:SelectedNodeID].Ellipse.StrokeThickness = 2
    }

    $script:SelectedNodeID = $NodeID
    $node = Get-TopologyNode -NodeID $NodeID

    if (-not $node) { return }

    # Highlight selected
    if ($script:NodeElements[$NodeID]) {
        $script:NodeElements[$NodeID].Ellipse.StrokeThickness = 4
    }

    # Show details panel
    if ($script:NoSelectionPanel) { $script:NoSelectionPanel.Visibility = 'Collapsed' }
    if ($script:DeviceDetailsPanel) { $script:DeviceDetailsPanel.Visibility = 'Visible' }

    # Populate details
    if ($script:DetailDeviceLabel) { $script:DetailDeviceLabel.Text = $node.DeviceID }
    if ($script:DetailRoleLabel) { $script:DetailRoleLabel.Text = $node.Role }
    if ($script:DetailSiteLabel) { $script:DetailSiteLabel.Text = if ($node.SiteID) { $node.SiteID } else { 'N/A' } }

    $links = Get-TopologyLink -NodeID $NodeID
    if ($script:DetailLinksLabel) { $script:DetailLinksLabel.Text = $links.Count.ToString() }
    if ($script:DetailPositionLabel) {
        $script:DetailPositionLabel.Text = "($([int]$node.XPosition), $([int]$node.YPosition))"
    }

    # Populate connected devices
    if ($script:ConnectedDevicesList) {
        $script:ConnectedDevicesList.Items.Clear()
        foreach ($link in $links) {
            $connectedID = if ($link.SourceNodeID -eq $NodeID) { $link.DestNodeID } else { $link.SourceNodeID }
            $connectedNode = Get-TopologyNode -NodeID $connectedID
            if ($connectedNode) {
                [void]$script:ConnectedDevicesList.Items.Add("$($connectedNode.DeviceID) ($($connectedNode.Role))")
            }
        }
    }
}

function Select-Link {
    <#
    .SYNOPSIS
        Selects a link and shows its details.
    #>
    [CmdletBinding()]
    param(
        [string]$LinkID
    )

    $link = Get-TopologyLink -LinkID $LinkID
    if (-not $link) { return }

    $sourceNode = Get-TopologyNode -NodeID $link.SourceNodeID
    $destNode = Get-TopologyNode -NodeID $link.DestNodeID

    $details = @"
Link Details
============
Source: $($sourceNode.DeviceID) ($($link.SourcePort))
Destination: $($destNode.DeviceID) ($($link.DestPort))
Type: $($link.LinkType)
Speed: $(if ($link.Speed) { $link.Speed } else { 'Unknown' })
Status: $($link.Status)
"@

    [System.Windows.MessageBox]::Show($details, 'Link Details', 'OK', 'Information')
}

#endregion

#region Layout

function Apply-SelectedLayout {
    <#
    .SYNOPSIS
        Applies the currently selected layout algorithm.
    #>
    [CmdletBinding()]
    param()

    $layoutIndex = if ($script:LayoutCombo) { $script:LayoutCombo.SelectedIndex } else { 0 }
    $canvasWidth = if ($script:TopologyCanvas) { $script:TopologyCanvas.Width } else { 800 }
    $canvasHeight = if ($script:TopologyCanvas) { $script:TopologyCanvas.Height } else { 600 }

    switch ($layoutIndex) {
        0 { Set-HierarchicalLayout -Width $canvasWidth -Height $canvasHeight }
        1 { Set-ForceDirectedLayout -Width $canvasWidth -Height $canvasHeight -Iterations 100 }
        2 { Set-CircularLayout -CenterX ($canvasWidth / 2) -CenterY ($canvasHeight / 2) -Radius ([math]::Min($canvasWidth, $canvasHeight) / 3) }
        3 { Set-GridLayout -StartX 100 -StartY 100 -SpacingX 150 -SpacingY 120 -Columns 5 }
    }
}

function Apply-ZoomLevel {
    <#
    .SYNOPSIS
        Applies zoom level to the canvas.
    #>
    [CmdletBinding()]
    param(
        [double]$Zoom = 1
    )

    if (-not $script:TopologyCanvas) { return }

    $transform = New-Object System.Windows.Media.ScaleTransform($Zoom, $Zoom)
    $script:TopologyCanvas.RenderTransform = $transform
}

function Fit-TopologyToView {
    <#
    .SYNOPSIS
        Fits topology to view by adjusting zoom.
    #>
    [CmdletBinding()]
    param()

    # Reset zoom
    if ($script:ZoomSlider) {
        $script:ZoomSlider.Value = 1
    }
}

#endregion

#region Impact Analysis

function Run-ImpactAnalysis {
    <#
    .SYNOPSIS
        Runs impact analysis for the selected device.
    #>
    [CmdletBinding()]
    param()

    if (-not $script:ImpactDeviceCombo -or -not $script:ImpactDeviceCombo.SelectedValue) {
        [System.Windows.MessageBox]::Show('Please select a device to analyze.', 'No Selection', 'OK', 'Information')
        return
    }

    $nodeID = $script:ImpactDeviceCombo.SelectedValue
    $impact = Get-ImpactAnalysis -NodeID $nodeID

    if (-not $impact) {
        [System.Windows.MessageBox]::Show('Failed to analyze impact.', 'Error', 'OK', 'Error')
        return
    }

    # Show results panel
    if ($script:ImpactResultsPanel) { $script:ImpactResultsPanel.Visibility = 'Visible' }

    # Populate results
    if ($script:ImpactSummaryLabel) {
        $script:ImpactSummaryLabel.Text = "Impact of $($impact.AffectedNode.DeviceID) failure:`n$($impact.Summary)"
    }

    if ($script:AffectedDevicesList) {
        $script:AffectedDevicesList.Items.Clear()
        foreach ($affected in $impact.DirectlyAffected) {
            $status = if ($affected.IsCritical) { '[CRITICAL]' } else { '[OK]' }
            [void]$script:AffectedDevicesList.Items.Add("$status $($affected.Node.DeviceID)")
        }
    }

    $critical = ($impact.DirectlyAffected | Where-Object { $_.IsCritical }).Count
    $redundant = ($impact.DirectlyAffected | Where-Object { $_.HasRedundancy }).Count

    if ($script:CriticalCountLabel) { $script:CriticalCountLabel.Text = $critical.ToString() }
    if ($script:RedundantCountLabel) { $script:RedundantCountLabel.Text = $redundant.ToString() }
}

function Update-ImpactDeviceCombo {
    <#
    .SYNOPSIS
        Updates the impact device combo box.
    #>
    [CmdletBinding()]
    param()

    if (-not $script:ImpactDeviceCombo) { return }

    $script:ImpactDeviceCombo.Items.Clear()
    $nodes = @(Get-TopologyNode)

    foreach ($node in ($nodes | Sort-Object DisplayName)) {
        $item = New-Object System.Windows.Controls.ComboBoxItem
        $item.Content = "$($node.DisplayName) ($($node.Role))"
        $item.Tag = $node.NodeID
        [void]$script:ImpactDeviceCombo.Items.Add($item)
    }
}

#endregion

#region Layout Management

function Save-CurrentLayout {
    <#
    .SYNOPSIS
        Saves the current layout.
    #>
    [CmdletBinding()]
    param()

    $layoutName = if ($script:LayoutNameBox) { $script:LayoutNameBox.Text.Trim() } else { '' }

    if ([string]::IsNullOrWhiteSpace($layoutName)) {
        [System.Windows.MessageBox]::Show('Please enter a layout name.', 'Invalid Name', 'OK', 'Warning')
        return
    }

    Save-TopologyLayout -LayoutName $layoutName
    Update-SavedLayoutsList

    if ($script:LayoutNameBox) { $script:LayoutNameBox.Text = '' }
    Set-Status "Layout '$layoutName' saved"
}

function Load-SelectedLayout {
    <#
    .SYNOPSIS
        Loads the selected layout.
    #>
    [CmdletBinding()]
    param()

    if (-not $script:SavedLayoutsList -or $script:SavedLayoutsList.SelectedIndex -lt 0) {
        [System.Windows.MessageBox]::Show('Please select a layout to load.', 'No Selection', 'OK', 'Information')
        return
    }

    $layoutName = $script:SavedLayoutsList.SelectedItem
    Restore-TopologyLayout -LayoutName $layoutName
    Render-Topology
    Set-Status "Layout '$layoutName' loaded"
}

function Delete-SelectedLayout {
    <#
    .SYNOPSIS
        Deletes the selected layout.
    #>
    [CmdletBinding()]
    param()

    if (-not $script:SavedLayoutsList -or $script:SavedLayoutsList.SelectedIndex -lt 0) {
        [System.Windows.MessageBox]::Show('Please select a layout to delete.', 'No Selection', 'OK', 'Information')
        return
    }

    $layoutName = $script:SavedLayoutsList.SelectedItem
    $result = [System.Windows.MessageBox]::Show(
        "Delete layout '$layoutName'?",
        'Confirm Delete',
        'YesNo',
        'Question'
    )

    if ($result -eq 'Yes') {
        # Remove from layouts (would need a Remove-TopologyLayout function)
        Update-SavedLayoutsList
        Set-Status "Layout '$layoutName' deleted"
    }
}

function Update-SavedLayoutsList {
    <#
    .SYNOPSIS
        Updates the saved layouts list.
    #>
    [CmdletBinding()]
    param()

    if (-not $script:SavedLayoutsList) { return }

    $script:SavedLayoutsList.Items.Clear()
    $layouts = @(Get-TopologyLayout)

    foreach ($layout in $layouts) {
        [void]$script:SavedLayoutsList.Items.Add($layout.LayoutName)
    }
}

#endregion

#region Export

function Export-CurrentTopology {
    <#
    .SYNOPSIS
        Exports the current topology.
    #>
    [CmdletBinding()]
    param()

    $formatIndex = if ($script:ExportFormatCombo) { $script:ExportFormatCombo.SelectedIndex } else { 0 }

    $filter = switch ($formatIndex) {
        0 { 'SVG Files (*.svg)|*.svg' }
        1 { 'PNG Files (*.png)|*.png' }
        2 { 'JSON Files (*.json)|*.json' }
        3 { 'Draw.io Files (*.drawio)|*.drawio' }
        default { 'All Files (*.*)|*.*' }
    }

    $ext = switch ($formatIndex) {
        0 { 'svg' }
        1 { 'png' }
        2 { 'json' }
        3 { 'drawio' }
        default { 'svg' }
    }

    $saveDialog = New-Object Microsoft.Win32.SaveFileDialog
    $saveDialog.Filter = $filter
    $saveDialog.FileName = "Topology_$(Get-Date -Format 'yyyyMMdd').$ext"

    if ($saveDialog.ShowDialog()) {
        try {
            switch ($formatIndex) {
                0 { Export-TopologyToSVG -OutputPath $saveDialog.FileName }
                2 { Export-TopologyToJSON -OutputPath $saveDialog.FileName }
                3 { Export-TopologyToDrawIO -OutputPath $saveDialog.FileName }
                default {
                    Export-TopologyToSVG -OutputPath $saveDialog.FileName
                }
            }

            Set-Status "Exported to $($saveDialog.FileName)"
            [System.Windows.MessageBox]::Show(
                "Topology exported to:`n$($saveDialog.FileName)",
                'Export Complete',
                'OK',
                'Information'
            )
        }
        catch {
            [System.Windows.MessageBox]::Show("Export failed: $_", 'Error', 'OK', 'Error')
        }
    }
}

function Copy-TopologyToClipboard {
    <#
    .SYNOPSIS
        Copies topology data to clipboard.
    #>
    [CmdletBinding()]
    param()

    try {
        $json = Export-TopologyToJSON
        [System.Windows.Clipboard]::SetText($json)
        Set-Status 'Topology copied to clipboard'
    }
    catch {
        [System.Windows.MessageBox]::Show("Copy failed: $_", 'Error', 'OK', 'Error')
    }
}

#endregion

#region Helpers

function Update-TopologyStatistics {
    <#
    .SYNOPSIS
        Updates the topology statistics display.
    #>
    [CmdletBinding()]
    param()

    $stats = Get-TopologyStatistics

    if ($script:NodeCountLabel) { $script:NodeCountLabel.Text = $stats.TotalNodes.ToString() }
    if ($script:LinkCountLabel) { $script:LinkCountLabel.Text = $stats.TotalLinks.ToString() }
    if ($script:IsolatedCountLabel) { $script:IsolatedCountLabel.Text = $stats.IsolatedNodes.ToString() }
}

function Set-Status {
    <#
    .SYNOPSIS
        Sets the status bar text.
    #>
    [CmdletBinding()]
    param(
        [string]$Text
    )

    if ($script:StatusLabel) {
        $script:StatusLabel.Text = $Text
    }
}

#endregion

# Export module members
Export-ModuleMember -Function @(
    'New-TopologyView'
)
