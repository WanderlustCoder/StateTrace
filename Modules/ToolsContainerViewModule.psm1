#Requires -Version 5.1
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Container view module for the Tools tab group.

.DESCRIPTION
    Loads the ToolsContainerView which contains nested tabs for:
    - Troubleshoot (Decision Trees)
    - Calculator (Network Calculator)

.NOTES
    Plan AF - Tab Consolidation & Navigation Redesign
#>

$script:ContainerView = $null
$script:ToolsSubHosts = $null
$script:ToolsInitializedViews = $null
$script:ToolsScriptDir = $null

function New-ToolsContainerView {
    <#
    .SYNOPSIS
        Initializes the Tools container view with nested sub-views.
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
            -ViewName 'ToolsContainerView' `
            -HostControlName 'ToolsContainerHost' `
            -GlobalVariableName 'toolsContainerView'

        if (-not $script:ContainerView) {
            Write-Warning "Failed to load ToolsContainerView"
            return
        }

        # Store state in script scope for event handler access
        $script:ToolsScriptDir = $ScriptDir
        $script:ToolsInitializedViews = @{}
        $script:ToolsSubHosts = @{
            Troubleshoot = $script:ContainerView.FindName('TroubleshootSubHost')
            Calculator   = $script:ContainerView.FindName('CalculatorSubHost')
        }

        # Get the nested TabControl for visibility handling
        $tabControl = $script:ContainerView.FindName('ToolsTabControl')

        # Initialize first tab immediately (Troubleshoot)
        if ($script:ToolsSubHosts.Troubleshoot) {
            Initialize-TroubleshootSubView -Host $script:ToolsSubHosts.Troubleshoot -ScriptDir $ScriptDir
            $script:ToolsInitializedViews['Troubleshoot'] = $true
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
                    'Troubleshoot' {
                        if (-not $script:ToolsInitializedViews['Troubleshoot']) {
                            Initialize-TroubleshootSubView -Host $script:ToolsSubHosts.Troubleshoot -ScriptDir $script:ToolsScriptDir
                            $script:ToolsInitializedViews['Troubleshoot'] = $true
                        }
                    }
                    'Calculator' {
                        if (-not $script:ToolsInitializedViews['Calculator']) {
                            Initialize-CalculatorSubView -Host $script:ToolsSubHosts.Calculator -ScriptDir $script:ToolsScriptDir
                            $script:ToolsInitializedViews['Calculator'] = $true
                        }
                    }
                }
            })
        }

        return $script:ContainerView
    }
    catch {
        Write-Warning "Failed to initialize Tools container view: $($_.Exception.Message)"
    }
}

function Initialize-TroubleshootSubView {
    param(
        [System.Windows.Controls.ContentControl]$Host,
        [string]$ScriptDir
    )

    try {
        if (Get-Command -Name 'Initialize-DecisionTreeView' -ErrorAction SilentlyContinue) {
            DecisionTreeViewModule\Initialize-DecisionTreeView -Host $Host
        } else {
            $viewPath = Join-Path $ScriptDir '..\Views\DecisionTreeView.xaml'
            if (Test-Path $viewPath) {
                $xamlContent = Get-Content -Path $viewPath -Raw
                $xamlContent = $xamlContent -replace 'x:Class="[^"]*"', ''
                $xamlContent = $xamlContent -replace 'mc:Ignorable="d"', ''

                $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xamlContent))
                $view = [System.Windows.Markup.XamlReader]::Load($reader)
                $Host.Content = $view
            }
        }
    }
    catch {
        Write-Warning "Failed to initialize Troubleshoot sub-view: $_"
    }
}

function Initialize-CalculatorSubView {
    param(
        [System.Windows.Controls.ContentControl]$Host,
        [string]$ScriptDir
    )

    try {
        if (Get-Command -Name 'Initialize-NetworkCalculatorView' -ErrorAction SilentlyContinue) {
            NetworkCalculatorViewModule\Initialize-NetworkCalculatorView -Host $Host
        } else {
            $viewPath = Join-Path $ScriptDir '..\Views\NetworkCalculatorView.xaml'
            if (Test-Path $viewPath) {
                $xamlContent = Get-Content -Path $viewPath -Raw
                $xamlContent = $xamlContent -replace 'x:Class="[^"]*"', ''
                $xamlContent = $xamlContent -replace 'mc:Ignorable="d"', ''

                $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xamlContent))
                $view = [System.Windows.Markup.XamlReader]::Load($reader)
                $Host.Content = $view
            }
        }
    }
    catch {
        Write-Warning "Failed to initialize Calculator sub-view: $_"
    }
}

Export-ModuleMember -Function @(
    'New-ToolsContainerView'
)
