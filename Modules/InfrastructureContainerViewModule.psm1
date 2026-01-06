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

function Initialize-TopologySubView {
    param(
        [System.Windows.Controls.ContentControl]$Host,
        [string]$ScriptDir
    )

    try {
        $viewPath = Join-Path $ScriptDir '..\Views\TopologyView.xaml'
        if (Test-Path $viewPath) {
            $xamlContent = Get-Content -Path $viewPath -Raw
            $xamlContent = $xamlContent -replace 'x:Class="[^"]*"', ''
            $xamlContent = $xamlContent -replace 'mc:Ignorable="d"', ''

            $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xamlContent))
            $view = [System.Windows.Markup.XamlReader]::Load($reader)
            $Host.Content = $view
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
        $viewPath = Join-Path $ScriptDir '..\Views\CableDocumentationView.xaml'
        if (Test-Path $viewPath) {
            $xamlContent = Get-Content -Path $viewPath -Raw
            $xamlContent = $xamlContent -replace 'x:Class="[^"]*"', ''
            $xamlContent = $xamlContent -replace 'mc:Ignorable="d"', ''

            $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xamlContent))
            $view = [System.Windows.Markup.XamlReader]::Load($reader)
            $Host.Content = $view
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
        $viewPath = Join-Path $ScriptDir '..\Views\IPAMView.xaml'
        if (Test-Path $viewPath) {
            $xamlContent = Get-Content -Path $viewPath -Raw
            $xamlContent = $xamlContent -replace 'x:Class="[^"]*"', ''
            $xamlContent = $xamlContent -replace 'mc:Ignorable="d"', ''

            $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xamlContent))
            $view = [System.Windows.Markup.XamlReader]::Load($reader)
            $Host.Content = $view
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
        $viewPath = Join-Path $ScriptDir '..\Views\InventoryView.xaml'
        if (Test-Path $viewPath) {
            $xamlContent = Get-Content -Path $viewPath -Raw
            $xamlContent = $xamlContent -replace 'x:Class="[^"]*"', ''
            $xamlContent = $xamlContent -replace 'mc:Ignorable="d"', ''

            $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xamlContent))
            $view = [System.Windows.Markup.XamlReader]::Load($reader)
            $Host.Content = $view
        }
    }
    catch {
        Write-Warning "Failed to initialize Inventory sub-view: $_"
    }
}

Export-ModuleMember -Function @(
    'New-InfrastructureContainerView'
)
