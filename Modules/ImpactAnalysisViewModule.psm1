# ImpactAnalysisViewModule.psm1
# View module for the Impact Analysis dashboard

Set-StrictMode -Version Latest

$script:View = $null
$script:CurrentImpact = $null

function Initialize-ImpactAnalysisView {
    <#
    .SYNOPSIS
    Initializes the Impact Analysis view with data binding and event handlers.
    .PARAMETER View
    The loaded XAML UserControl.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Windows.Controls.UserControl]$View
    )

    $script:View = $View

    # Import required modules
    $projectRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $projectRoot 'Modules\ImpactAnalysisModule.psm1') -Force -DisableNameChecking -ErrorAction SilentlyContinue
    Import-Module (Join-Path $projectRoot 'Modules\DeviceRepositoryModule.psm1') -Force -DisableNameChecking -ErrorAction SilentlyContinue

    # Get UI elements
    $refreshGraphBtn = $View.FindName('RefreshGraphButton')
    $newCRBtn = $View.FindName('NewChangeRequestButton')
    $analyzeBtn = $View.FindName('AnalyzeButton')
    $traceRouteBtn = $View.FindName('TraceRouteButton')
    $changeTypeCombo = $View.FindName('ChangeTypeCombo')
    $targetCombo = $View.FindName('TargetCombo')
    $crStatusFilter = $View.FindName('CRStatusFilter')
    $refreshCRBtn = $View.FindName('RefreshCRButton')
    $servicesList = $View.FindName('ServicesList')

    # Wire up event handlers
    if ($refreshGraphBtn) {
        $refreshGraphBtn.Add_Click({ Invoke-RefreshGraph })
    }

    if ($newCRBtn) {
        $newCRBtn.Add_Click({ Show-NewChangeRequestDialog })
    }

    if ($analyzeBtn) {
        $analyzeBtn.Add_Click({ Invoke-ImpactAnalysis })
    }

    if ($traceRouteBtn) {
        $traceRouteBtn.Add_Click({ Invoke-RouteTrace })
    }

    if ($changeTypeCombo) {
        $changeTypeCombo.Add_SelectionChanged({ Update-TargetOptions })
    }

    if ($crStatusFilter) {
        $crStatusFilter.Add_SelectionChanged({ Update-ChangeRequestsGrid })
    }

    if ($refreshCRBtn) {
        $refreshCRBtn.Add_Click({ Update-ChangeRequestsGrid })
    }

    if ($servicesList) {
        $servicesList.Add_SelectionChanged({ Update-ServiceDetails })
    }

    # Context menu handlers
    $approveCR = $View.FindName('ApproveCRMenuItem')
    $completeCR = $View.FindName('CompleteCRMenuItem')

    if ($approveCR) {
        $approveCR.Add_Click({ Invoke-ApproveSelectedCR })
    }

    if ($completeCR) {
        $completeCR.Add_Click({ Invoke-CompleteSelectedCR })
    }

    # Initial data load
    Invoke-RefreshGraph
    Update-TargetOptions
    Update-ServicesList
    Update-ChangeRequestsGrid

    Set-StatusText -Text "Ready - Select a change type and target to analyze impact"

    Write-Verbose "[ImpactAnalysisView] View initialized"
}

function Invoke-RefreshGraph {
    if (-not $script:View) { return }

    Set-StatusText -Text "Building dependency graph..."

    try {
        $graph = Build-DependencyGraph -IncludeL3 -IncludeVLAN

        $nodesCount = $script:View.FindName('GraphNodesCount')
        $edgesCount = $script:View.FindName('GraphEdgesCount')

        if ($nodesCount) { $nodesCount.Text = [string]$graph.Nodes.Count }
        if ($edgesCount) { $edgesCount.Text = [string]$graph.Edges.Count }

        Update-TargetOptions

        Set-StatusText -Text "Graph built: $($graph.Nodes.Count) nodes, $($graph.Edges.Count) edges"

    } catch {
        Set-StatusText -Text "Graph build failed: $($_.Exception.Message)"
    }
}

function Update-TargetOptions {
    if (-not $script:View) { return }

    $changeTypeCombo = $script:View.FindName('ChangeTypeCombo')
    $targetCombo = $script:View.FindName('TargetCombo')
    $interfaceCombo = $script:View.FindName('InterfaceCombo')

    if (-not $targetCombo) { return }

    $changeType = if ($changeTypeCombo -and $changeTypeCombo.SelectedItem) {
        $changeTypeCombo.SelectedItem.Content
    } else { 'DeviceDown' }

    $targetCombo.Items.Clear()

    try {
        $graph = Get-DependencyGraph

        switch ($changeType) {
            'VLANChange' {
                foreach ($vlanId in ($graph.VLANs.Keys | Sort-Object)) {
                    $vlanNum = $graph.VLANs[$vlanId].VLANNumber
                    $targetCombo.Items.Add($vlanNum) | Out-Null
                }
            }
            default {
                foreach ($nodeId in ($graph.Nodes.Keys | Sort-Object)) {
                    $node = $graph.Nodes[$nodeId]
                    $targetCombo.Items.Add($node.Hostname) | Out-Null
                }
            }
        }

        if ($targetCombo.Items.Count -gt 0) {
            $targetCombo.SelectedIndex = 0
            Update-InterfaceOptions
        }

    } catch {
        Write-Verbose "[ImpactAnalysisView] Failed to update targets: $_"
    }
}

function Update-InterfaceOptions {
    if (-not $script:View) { return }

    $targetCombo = $script:View.FindName('TargetCombo')
    $interfaceCombo = $script:View.FindName('InterfaceCombo')

    if (-not $interfaceCombo -or -not $targetCombo) { return }

    $interfaceCombo.Items.Clear()
    $interfaceCombo.Items.Add('') | Out-Null

    $target = $targetCombo.Text
    if (-not $target) { return }

    try {
        $graph = Get-DependencyGraph
        $nodeId = "device:$target"

        if ($graph.Nodes.ContainsKey($nodeId)) {
            $node = $graph.Nodes[$nodeId]
            foreach ($ifaceKey in ($node.Interfaces.Keys | Sort-Object)) {
                $interfaceCombo.Items.Add($ifaceKey) | Out-Null
            }
        }

    } catch {
        Write-Verbose "[ImpactAnalysisView] Failed to update interfaces: $_"
    }
}

function Invoke-ImpactAnalysis {
    if (-not $script:View) { return }

    $changeTypeCombo = $script:View.FindName('ChangeTypeCombo')
    $targetCombo = $script:View.FindName('TargetCombo')
    $interfaceCombo = $script:View.FindName('InterfaceCombo')

    $changeType = if ($changeTypeCombo -and $changeTypeCombo.SelectedItem) {
        $changeTypeCombo.SelectedItem.Content
    } else { 'DeviceDown' }

    $target = $targetCombo.Text
    $interface = $interfaceCombo.Text

    if (-not $target) {
        Set-StatusText -Text "Please select a target"
        return
    }

    Set-StatusText -Text "Analyzing impact..."

    try {
        $params = @{
            ChangeType = $changeType
            Target = $target
            IncludeServices = $true
        }

        if ($interface) {
            $params.TargetInterface = $interface
        }

        $script:CurrentImpact = Get-ChangeImpact @params

        Update-ImpactDisplay

        Set-StatusText -Text "Analysis complete - Risk Level: $($script:CurrentImpact.RiskLevel)"

    } catch {
        Set-StatusText -Text "Analysis failed: $($_.Exception.Message)"
    }
}

function Update-ImpactDisplay {
    if (-not $script:View -or -not $script:CurrentImpact) { return }

    $impact = $script:CurrentImpact

    # Update risk score card
    $riskScoreValue = $script:View.FindName('RiskScoreValue')
    $riskLevelText = $script:View.FindName('RiskLevelText')
    $riskScoreCard = $script:View.FindName('RiskScoreCard')

    if ($riskScoreValue) { $riskScoreValue.Text = [string]$impact.RiskScore }
    if ($riskLevelText) { $riskLevelText.Text = $impact.RiskLevel }

    # Update card color based on risk level
    if ($riskScoreCard) {
        $brush = switch ($impact.RiskLevel) {
            'Critical' {
                $gb = [System.Windows.Media.LinearGradientBrush]::new()
                $gb.StartPoint = [System.Windows.Point]::new(0, 0)
                $gb.EndPoint = [System.Windows.Point]::new(1, 1)
                $gb.GradientStops.Add([System.Windows.Media.GradientStop]::new([System.Windows.Media.Color]::FromRgb(244, 67, 54), 0))
                $gb.GradientStops.Add([System.Windows.Media.GradientStop]::new([System.Windows.Media.Color]::FromRgb(183, 28, 28), 1))
                $gb
            }
            'High' {
                $gb = [System.Windows.Media.LinearGradientBrush]::new()
                $gb.StartPoint = [System.Windows.Point]::new(0, 0)
                $gb.EndPoint = [System.Windows.Point]::new(1, 1)
                $gb.GradientStops.Add([System.Windows.Media.GradientStop]::new([System.Windows.Media.Color]::FromRgb(255, 152, 0), 0))
                $gb.GradientStops.Add([System.Windows.Media.GradientStop]::new([System.Windows.Media.Color]::FromRgb(230, 81, 0), 1))
                $gb
            }
            'Medium' {
                $gb = [System.Windows.Media.LinearGradientBrush]::new()
                $gb.StartPoint = [System.Windows.Point]::new(0, 0)
                $gb.EndPoint = [System.Windows.Point]::new(1, 1)
                $gb.GradientStops.Add([System.Windows.Media.GradientStop]::new([System.Windows.Media.Color]::FromRgb(255, 193, 7), 0))
                $gb.GradientStops.Add([System.Windows.Media.GradientStop]::new([System.Windows.Media.Color]::FromRgb(255, 160, 0), 1))
                $gb
            }
            default {
                $gb = [System.Windows.Media.LinearGradientBrush]::new()
                $gb.StartPoint = [System.Windows.Point]::new(0, 0)
                $gb.EndPoint = [System.Windows.Point]::new(1, 1)
                $gb.GradientStops.Add([System.Windows.Media.GradientStop]::new([System.Windows.Media.Color]::FromRgb(76, 175, 80), 0))
                $gb.GradientStops.Add([System.Windows.Media.GradientStop]::new([System.Windows.Media.Color]::FromRgb(46, 125, 50), 1))
                $gb
            }
        }
        $riskScoreCard.Background = $brush
    }

    # Update summary counts
    $directCount = $script:View.FindName('DirectAffectedCount')
    $indirectCount = $script:View.FindName('IndirectAffectedCount')
    $vlanCount = $script:View.FindName('AffectedVLANCount')
    $serviceCount = $script:View.FindName('AffectedServiceCount')

    if ($directCount) { $directCount.Text = [string]$impact.DirectlyAffected.Count }
    if ($indirectCount) { $indirectCount.Text = [string]$impact.IndirectlyAffected.Count }
    if ($vlanCount) { $vlanCount.Text = [string]$impact.AffectedVLANs.Count }
    if ($serviceCount) { $serviceCount.Text = [string]$impact.AffectedServices.Count }

    # Update grids
    $directGrid = $script:View.FindName('DirectAffectedGrid')
    $indirectGrid = $script:View.FindName('IndirectAffectedGrid')

    if ($directGrid) {
        $directGrid.ItemsSource = $impact.DirectlyAffected
    }

    if ($indirectGrid) {
        $indirectGrid.ItemsSource = $impact.IndirectlyAffected
    }

    # Update recommendations
    $recommendationsList = $script:View.FindName('RecommendationsList')
    if ($recommendationsList) {
        $recommendationsList.ItemsSource = $impact.Recommendations
    }
}

function Invoke-RouteTrace {
    if (-not $script:View) { return }

    $sourceInput = $script:View.FindName('TraceSourceInput')
    $destInput = $script:View.FindName('TraceDestInput')
    $statusText = $script:View.FindName('TraceStatusText')
    $hopsGrid = $script:View.FindName('TraceHopsGrid')

    $source = $sourceInput.Text
    $destination = $destInput.Text

    if (-not $source -or -not $destination) {
        if ($statusText) { $statusText.Text = "Please enter both source and destination" }
        return
    }

    if ($statusText) { $statusText.Text = "Tracing path..." }

    try {
        $trace = Trace-RoutePath -SourceIP $source -DestinationIP $destination

        if ($hopsGrid) {
            $hopsGrid.ItemsSource = $trace.Hops
        }

        if ($statusText) {
            $statusText.Text = "Trace $($trace.Status): $($trace.HopCount) hops"
        }

    } catch {
        if ($statusText) { $statusText.Text = "Trace failed: $($_.Exception.Message)" }
    }
}

function Update-ServicesList {
    if (-not $script:View) { return }

    $servicesList = $script:View.FindName('ServicesList')
    if (-not $servicesList) { return }

    try {
        $services = Get-ServiceDefinition

        $servicesList.Items.Clear()
        foreach ($svc in $services) {
            $item = [System.Windows.Controls.ListBoxItem]::new()
            $item.Content = "$($svc.Name) [$($svc.Criticality)]"
            $item.Tag = $svc.Id
            $servicesList.Items.Add($item) | Out-Null
        }

    } catch {
        Write-Verbose "[ImpactAnalysisView] Failed to load services: $_"
    }
}

function Update-ServiceDetails {
    if (-not $script:View) { return }

    $servicesList = $script:View.FindName('ServicesList')
    $nameText = $script:View.FindName('ServiceNameText')
    $criticalityText = $script:View.FindName('ServiceCriticalityText')
    $ownerText = $script:View.FindName('ServiceOwnerText')
    $depsGrid = $script:View.FindName('ServiceDependenciesGrid')

    if (-not $servicesList -or -not $servicesList.SelectedItem) { return }

    $serviceId = $servicesList.SelectedItem.Tag

    try {
        $service = Get-ServiceDefinition -Name $serviceId

        if ($service) {
            if ($nameText) { $nameText.Text = $service.Name }
            if ($criticalityText) { $criticalityText.Text = $service.Criticality }
            if ($ownerText) { $ownerText.Text = if ($service.Owner) { $service.Owner } else { '-' } }

            if ($depsGrid) {
                $depsGrid.ItemsSource = $service.Dependencies
            }
        }

    } catch {
        Write-Verbose "[ImpactAnalysisView] Failed to load service details: $_"
    }
}

function Update-ChangeRequestsGrid {
    if (-not $script:View) { return }

    $grid = $script:View.FindName('ChangeRequestsGrid')
    $statusFilter = $script:View.FindName('CRStatusFilter')

    if (-not $grid) { return }

    try {
        $status = if ($statusFilter -and $statusFilter.SelectedIndex -gt 0) {
            $statusFilter.SelectedItem.Content
        } else { $null }

        $requests = Get-ChangeRequest -Status $status

        $grid.ItemsSource = $requests

    } catch {
        Write-Verbose "[ImpactAnalysisView] Failed to load change requests: $_"
    }
}

function Invoke-ApproveSelectedCR {
    if (-not $script:View) { return }

    $grid = $script:View.FindName('ChangeRequestsGrid')
    if (-not $grid -or -not $grid.SelectedItem) { return }

    $crId = $grid.SelectedItem.Id

    try {
        $user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        Approve-ChangeRequest -Id $crId -Approver $user

        Update-ChangeRequestsGrid
        Set-StatusText -Text "Change request $crId approved"

    } catch {
        Set-StatusText -Text "Approval failed: $($_.Exception.Message)"
    }
}

function Invoke-CompleteSelectedCR {
    if (-not $script:View) { return }

    $grid = $script:View.FindName('ChangeRequestsGrid')
    if (-not $grid -or -not $grid.SelectedItem) { return }

    $crId = $grid.SelectedItem.Id

    try {
        Complete-ChangeRequest -Id $crId -Outcome 'Success'

        Update-ChangeRequestsGrid
        Set-StatusText -Text "Change request $crId marked complete"

    } catch {
        Set-StatusText -Text "Completion failed: $($_.Exception.Message)"
    }
}

function Show-NewChangeRequestDialog {
    # Placeholder for dialog - would create a WPF dialog in full implementation
    Set-StatusText -Text "Use New-ChangeRequest cmdlet to create change requests"
}

function Set-StatusText {
    param([string]$Text)

    if (-not $script:View) { return }

    $statusText = $script:View.FindName('StatusText')
    if ($statusText) {
        $statusText.Text = $Text
    }
}

function Get-ImpactAnalysisView {
    return $script:View
}

Export-ModuleMember -Function @(
    'Initialize-ImpactAnalysisView',
    'Get-ImpactAnalysisView',
    'Invoke-ImpactAnalysis'
)
