#Requires -Version 5.1
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Container view module for the Operations tab group.

.DESCRIPTION
    Loads the OperationsContainerView which contains nested tabs for:
    - Changes (Change Management)
    - Capacity (Capacity Planning)
    - Log Analysis

.NOTES
    Plan AF - Tab Consolidation & Navigation Redesign
#>

$script:ContainerView = $null

function New-OperationsContainerView {
    <#
    .SYNOPSIS
        Initializes the Operations container view with nested sub-views.
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
            -ViewName 'OperationsContainerView' `
            -HostControlName 'OperationsContainerHost' `
            -GlobalVariableName 'operationsContainerView'

        if (-not $script:ContainerView) {
            Write-Warning "Failed to load OperationsContainerView"
            return
        }

        # Get sub-host controls
        $changesSubHost = $script:ContainerView.FindName('ChangesSubHost')
        $capacitySubHost = $script:ContainerView.FindName('CapacitySubHost')
        $logAnalysisSubHost = $script:ContainerView.FindName('LogAnalysisSubHost')

        # Get the nested TabControl for visibility handling
        $tabControl = $script:ContainerView.FindName('OperationsTabControl')

        # Track which sub-views have been initialized (lazy loading)
        $script:InitializedSubViews = @{}

        # Initialize first tab immediately (Changes)
        if ($changesSubHost) {
            Initialize-ChangesSubView -Host $changesSubHost -ScriptDir $ScriptDir
            $script:InitializedSubViews['Changes'] = $true
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
                    'Changes' {
                        if (-not $script:InitializedSubViews['Changes']) {
                            Initialize-ChangesSubView -Host $changesSubHost -ScriptDir $ScriptDir
                            $script:InitializedSubViews['Changes'] = $true
                        }
                    }
                    'Capacity' {
                        if (-not $script:InitializedSubViews['Capacity']) {
                            Initialize-CapacitySubView -Host $capacitySubHost -ScriptDir $ScriptDir
                            $script:InitializedSubViews['Capacity'] = $true
                        }
                    }
                    'Log Analysis' {
                        if (-not $script:InitializedSubViews['LogAnalysis']) {
                            Initialize-LogAnalysisSubView -Host $logAnalysisSubHost -ScriptDir $ScriptDir
                            $script:InitializedSubViews['LogAnalysis'] = $true
                        }
                    }
                }
            })
        }

        return $script:ContainerView
    }
    catch {
        Write-Warning "Failed to initialize Operations container view: $($_.Exception.Message)"
    }
}

function Initialize-ChangesSubView {
    param(
        [System.Windows.Controls.ContentControl]$Host,
        [string]$ScriptDir
    )

    try {
        if (Get-Command -Name 'Initialize-ChangeManagementView' -ErrorAction SilentlyContinue) {
            ChangeManagementViewModule\Initialize-ChangeManagementView -Host $Host
        }
    }
    catch {
        Write-Warning "Failed to initialize Change Management sub-view: $_"
    }
}

function Initialize-CapacitySubView {
    param(
        [System.Windows.Controls.ContentControl]$Host,
        [string]$ScriptDir
    )

    try {
        if (Get-Command -Name 'Initialize-CapacityPlanningView' -ErrorAction SilentlyContinue) {
            CapacityPlanningViewModule\Initialize-CapacityPlanningView -Host $Host
        }
    }
    catch {
        Write-Warning "Failed to initialize Capacity Planning sub-view: $_"
    }
}

function Initialize-LogAnalysisSubView {
    param(
        [System.Windows.Controls.ContentControl]$Host,
        [string]$ScriptDir
    )

    try {
        if (Get-Command -Name 'Initialize-LogAnalysisView' -ErrorAction SilentlyContinue) {
            LogAnalysisViewModule\Initialize-LogAnalysisView -Host $Host
        }
    }
    catch {
        Write-Warning "Failed to initialize Log Analysis sub-view: $_"
    }
}

Export-ModuleMember -Function @(
    'New-OperationsContainerView'
)
