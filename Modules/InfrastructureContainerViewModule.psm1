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
$script:InfraSubHosts = $null
$script:InfraInitializedViews = $null
$script:InfraScriptDir = $null

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

        # Store state in script scope for event handler access
        $script:InfraScriptDir = $ScriptDir
        $script:InfraInitializedViews = @{}
        $script:InfraSubHosts = @{
            Topology  = $script:ContainerView.FindName('TopologySubHost')
            Cables    = $script:ContainerView.FindName('CablesSubHost')
            IPAM      = $script:ContainerView.FindName('IPAMSubHost')
            Inventory = $script:ContainerView.FindName('InventorySubHost')
        }

        # Get the nested TabControl for visibility handling
        $tabControl = $script:ContainerView.FindName('InfrastructureTabControl')

        # Initialize first tab immediately (Topology)
        if ($script:InfraSubHosts.Topology) {
            Initialize-TopologySubView -Host $script:InfraSubHosts.Topology -ScriptDir $ScriptDir
            $script:InfraInitializedViews['Topology'] = $true
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
                        if (-not $script:InfraInitializedViews['Topology']) {
                            Initialize-TopologySubView -Host $script:InfraSubHosts.Topology -ScriptDir $script:InfraScriptDir
                            $script:InfraInitializedViews['Topology'] = $true
                        }
                    }
                    'Cables' {
                        if (-not $script:InfraInitializedViews['Cables']) {
                            Initialize-CablesSubView -Host $script:InfraSubHosts.Cables -ScriptDir $script:InfraScriptDir
                            $script:InfraInitializedViews['Cables'] = $true
                        }
                    }
                    'IPAM' {
                        if (-not $script:InfraInitializedViews['IPAM']) {
                            Initialize-IPAMSubView -Host $script:InfraSubHosts.IPAM -ScriptDir $script:InfraScriptDir
                            $script:InfraInitializedViews['IPAM'] = $true
                        }
                    }
                    'Inventory' {
                        if (-not $script:InfraInitializedViews['Inventory']) {
                            Initialize-InventorySubView -Host $script:InfraSubHosts.Inventory -ScriptDir $script:InfraScriptDir
                            $script:InfraInitializedViews['Inventory'] = $true
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

# Helper: Load XAML for fallback view loading
# Note: DynamicResource bindings resolve from Application.Resources when view is in visual tree
function Load-ThemedXamlView {
    param(
        [string]$ViewPath,
        [string]$ScriptDir
    )

    if (-not (Test-Path $ViewPath)) { return $null }

    $xamlContent = Get-Content -Path $ViewPath -Raw
    $xamlContent = $xamlContent -replace 'x:Class="[^"]*"', ''
    $xamlContent = $xamlContent -replace 'mc:Ignorable="d"', ''

    $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xamlContent))
    $view = [System.Windows.Markup.XamlReader]::Load($reader)

    return $view
}

function Initialize-TopologySubView {
    param(
        [System.Windows.Controls.ContentControl]$Host,
        [string]$ScriptDir
    )

    try {
        if (Get-Command -Name 'Initialize-TopologyView' -ErrorAction SilentlyContinue) {
            TopologyViewModule\Initialize-TopologyView -Host $Host
        } else {
            $viewPath = Join-Path $ScriptDir '..\Views\TopologyView.xaml'
            $view = Load-ThemedXamlView -ViewPath $viewPath -ScriptDir $ScriptDir
            if ($view) { $Host.Content = $view }
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
        # Import required modules if not already loaded
        $cableModulePath = Join-Path $ScriptDir '..\Modules\CableDocumentationModule.psm1'
        if (Test-Path $cableModulePath) {
            Import-Module $cableModulePath -Force -ErrorAction SilentlyContinue
        }

        $viewModulePath = Join-Path $ScriptDir '..\Modules\CableDocumentationViewModule.psm1'
        if (Test-Path $viewModulePath) {
            Import-Module $viewModulePath -Force -ErrorAction SilentlyContinue
        }

        if (Get-Command -Name 'Initialize-CableDocumentationView' -ErrorAction SilentlyContinue) {
            CableDocumentationViewModule\Initialize-CableDocumentationView -Host $Host
        } else {
            $viewPath = Join-Path $ScriptDir '..\Views\CableDocumentationView.xaml'
            $view = Load-ThemedXamlView -ViewPath $viewPath -ScriptDir $ScriptDir
            if ($view) { $Host.Content = $view }
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
        } else {
            $viewPath = Join-Path $ScriptDir '..\Views\IPAMView.xaml'
            $view = Load-ThemedXamlView -ViewPath $viewPath -ScriptDir $ScriptDir
            if ($view) { $Host.Content = $view }
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
        } else {
            $viewPath = Join-Path $ScriptDir '..\Views\InventoryView.xaml'
            $view = Load-ThemedXamlView -ViewPath $viewPath -ScriptDir $ScriptDir
            if ($view) { $Host.Content = $view }
        }
    }
    catch {
        Write-Warning "Failed to initialize Inventory sub-view: $_"
    }
}

Export-ModuleMember -Function @(
    'New-InfrastructureContainerView'
)
