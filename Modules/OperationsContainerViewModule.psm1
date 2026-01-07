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
$script:OpsSubHosts = $null
$script:OpsInitializedViews = $null
$script:OpsScriptDir = $null

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

        # Store state in script scope for event handler access
        $script:OpsScriptDir = $ScriptDir
        $script:OpsInitializedViews = @{}
        $script:OpsSubHosts = @{
            Changes     = $script:ContainerView.FindName('ChangesSubHost')
            Capacity    = $script:ContainerView.FindName('CapacitySubHost')
            LogAnalysis = $script:ContainerView.FindName('LogAnalysisSubHost')
        }

        # Get the nested TabControl for visibility handling
        $tabControl = $script:ContainerView.FindName('OperationsTabControl')

        # Initialize first tab immediately (Changes)
        if ($script:OpsSubHosts.Changes) {
            Initialize-ChangesSubView -Host $script:OpsSubHosts.Changes -ScriptDir $ScriptDir
            $script:OpsInitializedViews['Changes'] = $true
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
                        if (-not $script:OpsInitializedViews['Changes']) {
                            Initialize-ChangesSubView -Host $script:OpsSubHosts.Changes -ScriptDir $script:OpsScriptDir
                            $script:OpsInitializedViews['Changes'] = $true
                        }
                    }
                    'Capacity' {
                        if (-not $script:OpsInitializedViews['Capacity']) {
                            Initialize-CapacitySubView -Host $script:OpsSubHosts.Capacity -ScriptDir $script:OpsScriptDir
                            $script:OpsInitializedViews['Capacity'] = $true
                        }
                    }
                    'Log Analysis' {
                        if (-not $script:OpsInitializedViews['LogAnalysis']) {
                            Initialize-LogAnalysisSubView -Host $script:OpsSubHosts.LogAnalysis -ScriptDir $script:OpsScriptDir
                            $script:OpsInitializedViews['LogAnalysis'] = $true
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
        } else {
            $viewPath = Join-Path $ScriptDir '..\Views\ChangeManagementView.xaml'
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
        } else {
            $viewPath = Join-Path $ScriptDir '..\Views\CapacityPlanningView.xaml'
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
        } else {
            $viewPath = Join-Path $ScriptDir '..\Views\LogAnalysisView.xaml'
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
        Write-Warning "Failed to initialize Log Analysis sub-view: $_"
    }
}

Export-ModuleMember -Function @(
    'New-OperationsContainerView'
)
