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

        # Get sub-host controls
        $troubleshootSubHost = $script:ContainerView.FindName('TroubleshootSubHost')
        $calculatorSubHost = $script:ContainerView.FindName('CalculatorSubHost')

        # Get the nested TabControl for visibility handling
        $tabControl = $script:ContainerView.FindName('ToolsTabControl')

        # Track which sub-views have been initialized (lazy loading)
        $script:InitializedSubViews = @{}

        # Initialize first tab immediately (Troubleshoot)
        if ($troubleshootSubHost) {
            Initialize-TroubleshootSubView -Host $troubleshootSubHost -ScriptDir $ScriptDir
            $script:InitializedSubViews['Troubleshoot'] = $true
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
                        if (-not $script:InitializedSubViews['Troubleshoot']) {
                            Initialize-TroubleshootSubView -Host $troubleshootSubHost -ScriptDir $ScriptDir
                            $script:InitializedSubViews['Troubleshoot'] = $true
                        }
                    }
                    'Calculator' {
                        if (-not $script:InitializedSubViews['Calculator']) {
                            Initialize-CalculatorSubView -Host $calculatorSubHost -ScriptDir $ScriptDir
                            $script:InitializedSubViews['Calculator'] = $true
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
        }
    }
    catch {
        Write-Warning "Failed to initialize Calculator sub-view: $_"
    }
}

Export-ModuleMember -Function @(
    'New-ToolsContainerView'
)
