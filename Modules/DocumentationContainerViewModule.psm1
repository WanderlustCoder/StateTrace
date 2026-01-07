#Requires -Version 5.1
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Container view module for the Documentation tab group.

.DESCRIPTION
    Loads the DocumentationContainerView which contains nested tabs for:
    - Generator (Documentation Generator)
    - Config Templates
    - Command Reference

.NOTES
    Plan AF - Tab Consolidation & Navigation Redesign
#>

$script:ContainerView = $null
$script:DocSubHosts = $null
$script:DocInitializedViews = $null
$script:DocScriptDir = $null
$script:DocWindow = $null

function New-DocumentationContainerView {
    <#
    .SYNOPSIS
        Initializes the Documentation container view with nested sub-views.
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
            -ViewName 'DocumentationContainerView' `
            -HostControlName 'DocumentationContainerHost' `
            -GlobalVariableName 'documentationContainerView'

        if (-not $script:ContainerView) {
            Write-Warning "Failed to load DocumentationContainerView"
            return
        }

        # Store state in script scope for event handler access
        $script:DocScriptDir = $ScriptDir
        $script:DocWindow = $Window
        $script:DocInitializedViews = @{}
        $script:DocSubHosts = @{
            Docs      = $script:ContainerView.FindName('DocsSubHost')
            Config    = $script:ContainerView.FindName('ConfigSubHost')
            CmdRef    = $script:ContainerView.FindName('CmdReferenceSubHost')
        }

        # Get the nested TabControl for visibility handling
        $tabControl = $script:ContainerView.FindName('DocumentationTabControl')

        # Initialize first tab immediately (Generator/Docs)
        if ($script:DocSubHosts.Docs) {
            Initialize-DocsSubView -Host $script:DocSubHosts.Docs -ScriptDir $ScriptDir
            $script:DocInitializedViews['Docs'] = $true
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
                    'Generator' {
                        if (-not $script:DocInitializedViews['Docs']) {
                            Initialize-DocsSubView -Host $script:DocSubHosts.Docs -ScriptDir $script:DocScriptDir
                            $script:DocInitializedViews['Docs'] = $true
                        }
                    }
                    'Config Templates' {
                        if (-not $script:DocInitializedViews['Config']) {
                            Initialize-ConfigSubView -Host $script:DocSubHosts.Config -ScriptDir $script:DocScriptDir
                            $script:DocInitializedViews['Config'] = $true
                        }
                    }
                    'Cmd Reference' {
                        if (-not $script:DocInitializedViews['CmdRef']) {
                            Initialize-CmdRefSubView -Host $script:DocSubHosts.CmdRef -ScriptDir $script:DocScriptDir
                            $script:DocInitializedViews['CmdRef'] = $true
                        }
                    }
                }
            })
        }

        return $script:ContainerView
    }
    catch {
        Write-Warning "Failed to initialize Documentation container view: $($_.Exception.Message)"
    }
}

function Initialize-DocsSubView {
    param(
        [System.Windows.Controls.ContentControl]$Host,
        [string]$ScriptDir
    )

    try {
        if (Get-Command -Name 'Initialize-DocumentationGeneratorView' -ErrorAction SilentlyContinue) {
            DocumentationGeneratorViewModule\Initialize-DocumentationGeneratorView -Host $Host
        }
    }
    catch {
        Write-Warning "Failed to initialize Documentation Generator sub-view: $_"
    }
}

function Initialize-ConfigSubView {
    param(
        [System.Windows.Controls.ContentControl]$Host,
        [string]$ScriptDir
    )

    try {
        # Use the ConfigTemplateViewModule to properly initialize with event handlers
        if (Get-Command -Name 'Initialize-ConfigTemplateView' -ErrorAction SilentlyContinue) {
            ConfigTemplateViewModule\Initialize-ConfigTemplateView -Host $Host
        } else {
            Write-Warning "Initialize-ConfigTemplateView not found - loading XAML only"
            $viewPath = Join-Path $ScriptDir '..\Views\ConfigTemplateView.xaml'
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
        Write-Warning "Failed to initialize Config Templates sub-view: $_"
    }
}

function Initialize-CmdRefSubView {
    param(
        [System.Windows.Controls.ContentControl]$Host,
        [string]$ScriptDir
    )

    try {
        $viewPath = Join-Path $ScriptDir '..\Views\CommandReferenceView.xaml'
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
        Write-Warning "Failed to initialize Command Reference sub-view: $_"
    }
}

Export-ModuleMember -Function @(
    'New-DocumentationContainerView'
)
