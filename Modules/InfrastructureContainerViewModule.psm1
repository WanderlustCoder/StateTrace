#Requires -Version 5.1
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Container view module for the Infrastructure tab group.

.DESCRIPTION
    Loads the InfrastructureContainerView which contains nested tabs for:
    - Topology
    - Cables
    - IPAM
    - Inventory

.NOTES
    Plan AF - Tab Consolidation & Navigation Redesign
#>

$script:ContainerView = $null

function New-InfrastructureContainerView {
    <#
    .SYNOPSIS
        Initializes the Infrastructure container view with nested sub-views.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Window]$Window,

        [Parameter(Mandatory)]
        [string]$ScriptDir
    )

    try {
        # Load container XAML via ViewCompositionModule
        $script:ContainerView = ViewCompositionModule\Set-StView `
            -Window $Window `
            -ScriptDir $ScriptDir `
            -ViewName 'InfrastructureContainerView' `
            -HostControlName 'InfrastructureContainerHost' `
            -GlobalVariableName 'infrastructureContainerView'

        if (-not $script:ContainerView) {
            Write-Warning "Failed to load InfrastructureContainerView"
            return
        }

        # Get sub-host controls
        $topologySubHost = $script:ContainerView.FindName('TopologySubHost')
        $cablesSubHost = $script:ContainerView.FindName('CablesSubHost')
        $ipamSubHost = $script:ContainerView.FindName('IPAMSubHost')
        $inventorySubHost = $script:ContainerView.FindName('InventorySubHost')

        # Get the nested TabControl for visibility handling
        $tabControl = $script:ContainerView.FindName('InfrastructureTabControl')

        # Track which sub-views have been initialized (lazy loading)
        $script:InitializedSubViews = @{}

        # Initialize first tab immediately (Topology)
        if ($topologySubHost) {
            Initialize-TopologySubView -Host $topologySubHost -ScriptDir $ScriptDir
            $script:InitializedSubViews['Topology'] = $true
        }

        # Wire up lazy loading for other tabs
        if ($tabControl) {
            $tabControl.Add_SelectionChanged({
                param($sender, $e)
                if ($e.Source -ne $sender) { return }

                $selectedTab = $sender.SelectedItem
                if (-not $selectedTab) { return }

                $header = $selectedTab.Header
                switch ($header) {
                    'Topology' {
                        if (-not $script:InitializedSubViews['Topology']) {
                            Initialize-TopologySubView -Host $topologySubHost -ScriptDir $ScriptDir
                            $script:InitializedSubViews['Topology'] = $true
                        }
                    }
                    'Cables' {
                        if (-not $script:InitializedSubViews['Cables']) {
                            Initialize-CablesSubView -Host $cablesSubHost -ScriptDir $ScriptDir
                            $script:InitializedSubViews['Cables'] = $true
                        }
                    }
                    'IPAM' {
                        if (-not $script:InitializedSubViews['IPAM']) {
                            Initialize-IPAMSubView -Host $ipamSubHost -ScriptDir $ScriptDir
                            $script:InitializedSubViews['IPAM'] = $true
                        }
                    }
                    'Inventory' {
                        if (-not $script:InitializedSubViews['Inventory']) {
                            Initialize-InventorySubView -Host $inventorySubHost -ScriptDir $ScriptDir
                            $script:InitializedSubViews['Inventory'] = $true
                        }
                    }
                }
            })
        }

        return $script:ContainerView
    }
    catch {
        Write-Warning "Failed to initialize Infrastructure container view: $($_.Exception.Message)"
    }
}

function Initialize-TopologySubView {
    param(
        [System.Windows.Controls.ContentControl]$Host,
        [string]$ScriptDir
    )

    try {
        if (Get-Command -Name 'Initialize-TopologyView' -ErrorAction SilentlyContinue) {
            TopologyViewModule\Initialize-TopologyView -Host $Host
        }
    }
    catch {
        Write-Warning "Failed to initialize Topology sub-view: $_"
    }
}

function Initialize-CablesSubView {
    param(
        [System.Windows.Controls.ContentControl]$Host,
        [string]$ScriptDir
    )

    try {
        if (Get-Command -Name 'Initialize-CableDocumentationView' -ErrorAction SilentlyContinue) {
            CableDocumentationViewModule\Initialize-CableDocumentationView -Host $Host
        }
    }
    catch {
        Write-Warning "Failed to initialize Cables sub-view: $_"
    }
}

function Initialize-IPAMSubView {
    param(
        [System.Windows.Controls.ContentControl]$Host,
        [string]$ScriptDir
    )

    try {
        if (Get-Command -Name 'Initialize-IPAMView' -ErrorAction SilentlyContinue) {
            IPAMViewModule\Initialize-IPAMView -Host $Host
        }
    }
    catch {
        Write-Warning "Failed to initialize IPAM sub-view: $_"
    }
}

function Initialize-InventorySubView {
    param(
        [System.Windows.Controls.ContentControl]$Host,
        [string]$ScriptDir
    )

    try {
        if (Get-Command -Name 'Initialize-InventoryView' -ErrorAction SilentlyContinue) {
            InventoryViewModule\Initialize-InventoryView -Host $Host
        }
    }
    catch {
        Write-Warning "Failed to initialize Inventory sub-view: $_"
    }
}

Export-ModuleMember -Function @(
    'New-InfrastructureContainerView'
)
