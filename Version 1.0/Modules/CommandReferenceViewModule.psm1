Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Creates and initializes the Command Reference view.

.DESCRIPTION
    Loads CommandReferenceView.xaml using ViewCompositionModule, wires up event handlers,
    and populates initial data for cross-vendor command lookup, translation, and config snippets.

.PARAMETER Window
    The parent MainWindow instance.

.PARAMETER ScriptDir
    The root script directory for locating XAML files.

.OUTPUTS
    System.Windows.Controls.UserControl - The initialized view.
#>
function New-CommandReferenceView {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [System.Windows.Window]$Window,

        [Parameter(Mandatory=$true)]
        [string]$ScriptDir
    )

    try {
        $view = ViewCompositionModule\Set-StView -Window $Window -ScriptDir $ScriptDir `
            -ViewName 'CommandReferenceView' -HostControlName 'CommandReferenceHost' `
            -GlobalVariableName 'commandReferenceView'
        if (-not $view) { return }

        # Get control references
        $searchBox = $view.FindName('SearchBox')
        $searchButton = $view.FindName('SearchButton')
        $categoryDropdown = $view.FindName('CategoryDropdown')
        $vendorDropdown = $view.FindName('VendorDropdown')

        $fromVendorDropdown = $view.FindName('FromVendorDropdown')
        $toVendorDropdown = $view.FindName('ToVendorDropdown')
        $sourceCommandBox = $view.FindName('SourceCommandBox')
        $translatedCommandBox = $view.FindName('TranslatedCommandBox')
        $translateButton = $view.FindName('TranslateButton')

        $commandsGrid = $view.FindName('CommandsGrid')
        $copyCommandButton = $view.FindName('CopyCommandButton')
        $commandCountText = $view.FindName('CommandCountText')

        $compareTaskBox = $view.FindName('CompareTaskBox')
        $compareButton = $view.FindName('CompareButton')
        $compareGrid = $view.FindName('CompareGrid')

        $snippetVendorDropdown = $view.FindName('SnippetVendorDropdown')
        $snippetsList = $view.FindName('SnippetsList')
        $snippetTitleText = $view.FindName('SnippetTitleText')
        $variablesPanel = $view.FindName('VariablesPanel')
        $generatedConfigBox = $view.FindName('GeneratedConfigBox')
        $generateConfigButton = $view.FindName('GenerateConfigButton')
        $copyConfigButton = $view.FindName('CopyConfigButton')

        $quickRefTaskBox = $view.FindName('QuickRefTaskBox')
        $quickRefSearchButton = $view.FindName('QuickRefSearchButton')
        $quickRefGrid = $view.FindName('QuickRefGrid')

        # Store state in view's Tag
        $view.Tag = @{
            CurrentSnippet = $null
            VariableInputs = @{}
        }

        # Populate vendor dropdowns
        $vendors = CommandReferenceModule\Get-SupportedVendors
        foreach ($dropdown in @($vendorDropdown, $fromVendorDropdown, $toVendorDropdown, $snippetVendorDropdown)) {
            if ($null -ne $dropdown) {
                foreach ($vendor in $vendors) {
                    $item = New-Object System.Windows.Controls.ComboBoxItem
                    $item.Content = $vendor
                    $dropdown.Items.Add($item) | Out-Null
                }
                if ($dropdown.Items.Count -gt 0) {
                    $dropdown.SelectedIndex = 0
                }
            }
        }

        # Populate category dropdown
        $categories = CommandReferenceModule\Get-CommandCategories
        foreach ($cat in $categories) {
            $item = New-Object System.Windows.Controls.ComboBoxItem
            $item.Content = $cat.Name
            $categoryDropdown.Items.Add($item) | Out-Null
        }

        # Capture function references for use in closures
        $updateGridFunc = ${function:Update-CommandsGrid}
        $updateSnippetsFunc = ${function:Update-SnippetsList}

        # Load initial command list
        Update-CommandsGrid -Grid $commandsGrid -CountText $commandCountText

        # Search button click
        $searchButton.Add_Click({
            param($sender, $e)
            $keyword = $searchBox.Text
            $vendor = $null
            $category = $null

            if ($vendorDropdown.SelectedItem -and $vendorDropdown.SelectedItem.Content -ne 'All') {
                $vendor = $vendorDropdown.SelectedItem.Content
            }
            if ($categoryDropdown.SelectedItem -and $categoryDropdown.SelectedItem.Content -ne 'All') {
                $category = $categoryDropdown.SelectedItem.Content
            }

            & $updateGridFunc -Grid $commandsGrid -CountText $commandCountText `
                -Keyword $keyword -Vendor $vendor -Category $category
        }.GetNewClosure())

        # Search on Enter key in search box
        $searchBox.Add_KeyDown({
            param($sender, $e)
            if ($e.Key -eq 'Return') {
                $searchButton.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
            }
        }.GetNewClosure())

        # Translate button click
        $translateButton.Add_Click({
            param($sender, $e)
            $command = $sourceCommandBox.Text
            $fromVendor = if ($fromVendorDropdown.SelectedItem) { $fromVendorDropdown.SelectedItem.Content } else { $null }
            $toVendor = if ($toVendorDropdown.SelectedItem) { $toVendorDropdown.SelectedItem.Content } else { $null }

            if ([string]::IsNullOrWhiteSpace($command) -or -not $fromVendor -or -not $toVendor) {
                $translatedCommandBox.Text = ''
                return
            }

            $result = CommandReferenceModule\Convert-NetworkCommand -Command $command -FromVendor $fromVendor -ToVendor $toVendor
            if ($result.Success -and $result.HasEquivalent) {
                $translatedCommandBox.Text = $result.TranslatedCommand
                $translatedCommandBox.ToolTip = $result.Notes
            } elseif ($result.Success -and -not $result.HasEquivalent) {
                $translatedCommandBox.Text = '(No equivalent)'
                $translatedCommandBox.ToolTip = 'This command has no direct equivalent in the target vendor'
            } else {
                $translatedCommandBox.Text = '(Unknown command)'
                $translatedCommandBox.ToolTip = $result.Error
            }
        }.GetNewClosure())

        # Translate on Enter key
        $sourceCommandBox.Add_KeyDown({
            param($sender, $e)
            if ($e.Key -eq 'Return') {
                $translateButton.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
            }
        }.GetNewClosure())

        # Copy command button
        $copyCommandButton.Add_Click({
            param($sender, $e)
            if ($commandsGrid.SelectedItem) {
                $cmd = $commandsGrid.SelectedItem.Command
                [System.Windows.Clipboard]::SetText($cmd)
                ViewCompositionModule\Show-CopyFeedback -Button $sender
            }
        }.GetNewClosure())

        # Compare button click
        $compareButton.Add_Click({
            param($sender, $e)
            $task = $compareTaskBox.Text
            if ([string]::IsNullOrWhiteSpace($task)) {
                $compareGrid.ItemsSource = $null
                return
            }

            $comparison = CommandReferenceModule\Get-CommandComparison -Task $task
            $compareGrid.ItemsSource = $comparison
        }.GetNewClosure())

        # Compare on Enter key
        $compareTaskBox.Add_KeyDown({
            param($sender, $e)
            if ($e.Key -eq 'Return') {
                $compareButton.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
            }
        }.GetNewClosure())

        # Snippet vendor dropdown change
        $snippetVendorDropdown.Add_SelectionChanged({
            param($sender, $e)
            $vendor = if ($snippetVendorDropdown.SelectedItem) { $snippetVendorDropdown.SelectedItem.Content } else { $null }
            & $updateSnippetsFunc -ListBox $snippetsList -Vendor $vendor
        }.GetNewClosure())

        # Snippet selection change
        $snippetsList.Add_SelectionChanged({
            param($sender, $e)
            $selectedItem = $snippetsList.SelectedItem
            if ($null -eq $selectedItem) {
                $snippetTitleText.Text = 'Select a snippet'
                $variablesPanel.Children.Clear()
                $generatedConfigBox.Text = ''
                $view.Tag.CurrentSnippet = $null
                return
            }

            $vendor = if ($snippetVendorDropdown.SelectedItem) { $snippetVendorDropdown.SelectedItem.Content } else { 'Cisco' }
            $snippet = CommandReferenceModule\Get-ConfigSnippet -Task $selectedItem -Vendor $vendor

            if ($null -eq $snippet) {
                $snippetTitleText.Text = 'Snippet not found'
                return
            }

            $view.Tag.CurrentSnippet = $snippet
            $snippetTitleText.Text = $snippet.Task
            $view.Tag.VariableInputs = @{}

            # Build variable input controls
            $variablesPanel.Children.Clear()
            foreach ($varName in $snippet.Variables) {
                $sp = New-Object System.Windows.Controls.StackPanel
                $sp.Orientation = 'Horizontal'
                $sp.Margin = '0,2'

                $label = New-Object System.Windows.Controls.Label
                $label.Content = "${varName}:"
                $label.Width = 120
                $label.SetResourceReference([System.Windows.Controls.Control]::StyleProperty, 'ToolbarLabelStyle')

                $textBox = New-Object System.Windows.Controls.TextBox
                $textBox.Width = 200
                $textBox.Tag = $varName
                $textBox.SetResourceReference([System.Windows.Controls.Control]::BackgroundProperty, 'Theme.Input.Background')
                $textBox.SetResourceReference([System.Windows.Controls.Control]::ForegroundProperty, 'Theme.Input.Text')
                $textBox.SetResourceReference([System.Windows.Controls.Control]::BorderBrushProperty, 'Theme.Input.Border')

                $view.Tag.VariableInputs[$varName] = $textBox

                $sp.Children.Add($label) | Out-Null
                $sp.Children.Add($textBox) | Out-Null
                $variablesPanel.Children.Add($sp) | Out-Null
            }

            $generatedConfigBox.Text = $snippet.Template
        }.GetNewClosure())

        # Generate config button
        $generateConfigButton.Add_Click({
            param($sender, $e)
            $snippet = $view.Tag.CurrentSnippet
            if ($null -eq $snippet) {
                return
            }

            $variables = @{}
            foreach ($kvp in $view.Tag.VariableInputs.GetEnumerator()) {
                $variables[$kvp.Key] = $kvp.Value.Text
            }

            $config = CommandReferenceModule\Expand-ConfigSnippet -Snippet $snippet -Variables $variables
            $generatedConfigBox.Text = $config
        }.GetNewClosure())

        # Copy config button
        $copyConfigButton.Add_Click({
            param($sender, $e)
            $config = $generatedConfigBox.Text
            if (-not [string]::IsNullOrWhiteSpace($config)) {
                [System.Windows.Clipboard]::SetText($config)
                ViewCompositionModule\Show-CopyFeedback -Button $sender
            }
        }.GetNewClosure())

        # Quick reference search
        $quickRefSearchButton.Add_Click({
            param($sender, $e)
            $task = $quickRefTaskBox.Text
            if ([string]::IsNullOrWhiteSpace($task)) {
                $quickRefGrid.ItemsSource = $null
                return
            }

            $results = CommandReferenceModule\Find-CommandByTask -Task $task
            $quickRefGrid.ItemsSource = $results
        }.GetNewClosure())

        # Quick ref on Enter key
        $quickRefTaskBox.Add_KeyDown({
            param($sender, $e)
            if ($e.Key -eq 'Return') {
                $quickRefSearchButton.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
            }
        }.GetNewClosure())

        # Load initial snippets list
        if ($snippetVendorDropdown.SelectedItem) {
            Update-SnippetsList -ListBox $snippetsList -Vendor $snippetVendorDropdown.SelectedItem.Content
        }

    } catch {
        Write-Warning "Failed to initialize CommandReference view: $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
    Updates the commands grid with search results.
#>
function Update-CommandsGrid {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        $Grid,

        [Parameter(Mandatory=$true)]
        $CountText,

        [string]$Keyword,
        [string]$Vendor,
        [string]$Category
    )

    $params = @{}
    if (-not [string]::IsNullOrWhiteSpace($Keyword)) {
        $params['Keyword'] = $Keyword
    }
    if (-not [string]::IsNullOrWhiteSpace($Vendor)) {
        $params['Vendor'] = $Vendor
    }
    if (-not [string]::IsNullOrWhiteSpace($Category)) {
        $params['Category'] = $Category
    }

    # Search-NetworkCommands returns all commands when called without Keyword
    $results = CommandReferenceModule\Search-NetworkCommands @params

    $Grid.ItemsSource = $results
    $count = if ($results) { $results.Count } else { 0 }
    $CountText.Text = "$count commands"
}

<#
.SYNOPSIS
    Updates the snippets list for a vendor.
#>
function Update-SnippetsList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        $ListBox,

        [string]$Vendor
    )

    $ListBox.Items.Clear()

    if ([string]::IsNullOrWhiteSpace($Vendor)) {
        return
    }

    $snippets = CommandReferenceModule\Get-ConfigSnippets -Vendor $Vendor
    foreach ($snippet in $snippets) {
        $ListBox.Items.Add($snippet.TaskName) | Out-Null
    }
}

function Initialize-CommandReferenceView {
    <#
    .SYNOPSIS
        Initializes the Command Reference view into a Host ContentControl.
        Used for nested tab scenarios where the view is loaded into a container.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.ContentControl]$Host
    )

    try {
        # Load the XAML
        $viewPath = Join-Path $PSScriptRoot '..\Views\CommandReferenceView.xaml'
        if (-not (Test-Path $viewPath)) {
            Write-Warning "CommandReferenceView.xaml not found at $viewPath"
            return
        }

        $xamlContent = Get-Content -Path $viewPath -Raw
        $xamlContent = $xamlContent -replace 'x:Class="[^"]*"', ''
        $xamlContent = $xamlContent -replace 'mc:Ignorable="d"', ''

        $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xamlContent))
        $view = [System.Windows.Markup.XamlReader]::Load($reader)
        $Host.Content = $view

        # Wire up event handlers
        Initialize-CommandReferenceEventHandlers -View $view

        return $view
    }
    catch {
        Write-Warning "Failed to initialize CommandReference view: $($_.Exception.Message)"
    }
}

function Initialize-CommandReferenceEventHandlers {
    <#
    .SYNOPSIS
        Wires up event handlers for the Command Reference view.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $View
    )

    $view = $View

    # Get control references
    $searchBox = $view.FindName('SearchBox')
    $searchButton = $view.FindName('SearchButton')
    $categoryDropdown = $view.FindName('CategoryDropdown')
    $vendorDropdown = $view.FindName('VendorDropdown')

    $fromVendorDropdown = $view.FindName('FromVendorDropdown')
    $toVendorDropdown = $view.FindName('ToVendorDropdown')
    $sourceCommandBox = $view.FindName('SourceCommandBox')
    $translatedCommandBox = $view.FindName('TranslatedCommandBox')
    $translateButton = $view.FindName('TranslateButton')

    $commandsGrid = $view.FindName('CommandsGrid')
    $copyCommandButton = $view.FindName('CopyCommandButton')
    $commandCountText = $view.FindName('CommandCountText')

    $compareTaskBox = $view.FindName('CompareTaskBox')
    $compareButton = $view.FindName('CompareButton')
    $compareGrid = $view.FindName('CompareGrid')

    $snippetVendorDropdown = $view.FindName('SnippetVendorDropdown')
    $snippetsList = $view.FindName('SnippetsList')
    $snippetTitleText = $view.FindName('SnippetTitleText')
    $variablesPanel = $view.FindName('VariablesPanel')
    $generatedConfigBox = $view.FindName('GeneratedConfigBox')
    $generateConfigButton = $view.FindName('GenerateConfigButton')
    $copyConfigButton = $view.FindName('CopyConfigButton')

    $quickRefTaskBox = $view.FindName('QuickRefTaskBox')
    $quickRefSearchButton = $view.FindName('QuickRefSearchButton')
    $quickRefGrid = $view.FindName('QuickRefGrid')

    # Store state in view's Tag
    $view.Tag = @{
        CurrentSnippet = $null
        VariableInputs = @{}
    }

    # Populate vendor dropdowns
    $vendors = CommandReferenceModule\Get-SupportedVendors
    foreach ($dropdown in @($vendorDropdown, $fromVendorDropdown, $toVendorDropdown, $snippetVendorDropdown)) {
        if ($null -ne $dropdown) {
            foreach ($vendor in $vendors) {
                $item = New-Object System.Windows.Controls.ComboBoxItem
                $item.Content = $vendor
                $dropdown.Items.Add($item) | Out-Null
            }
            if ($dropdown.Items.Count -gt 0) {
                $dropdown.SelectedIndex = 0
            }
        }
    }

    # Populate category dropdown
    if ($categoryDropdown) {
        $categories = CommandReferenceModule\Get-CommandCategories
        foreach ($cat in $categories) {
            $item = New-Object System.Windows.Controls.ComboBoxItem
            $item.Content = $cat.Name
            $categoryDropdown.Items.Add($item) | Out-Null
        }
    }

    # Capture function references for use in closures
    $updateGridFunc = ${function:Update-CommandsGrid}
    $updateSnippetsFunc = ${function:Update-SnippetsList}

    # Load initial command list
    if ($commandsGrid -and $commandCountText) {
        Update-CommandsGrid -Grid $commandsGrid -CountText $commandCountText
    }

    # Search button click
    if ($searchButton) {
        $searchButton.Add_Click({
            param($sender, $e)
            $keyword = $searchBox.Text
            $vendor = $null
            $category = $null

            if ($vendorDropdown.SelectedItem -and $vendorDropdown.SelectedItem.Content -ne 'All') {
                $vendor = $vendorDropdown.SelectedItem.Content
            }
            if ($categoryDropdown.SelectedItem -and $categoryDropdown.SelectedItem.Content -ne 'All') {
                $category = $categoryDropdown.SelectedItem.Content
            }

            & $updateGridFunc -Grid $commandsGrid -CountText $commandCountText `
                -Keyword $keyword -Vendor $vendor -Category $category
        }.GetNewClosure())
    }

    # Search on Enter key in search box
    if ($searchBox) {
        $searchBox.Add_KeyDown({
            param($sender, $e)
            if ($e.Key -eq 'Return') {
                $searchButton.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
            }
        }.GetNewClosure())
    }

    # Translate button click
    if ($translateButton) {
        $translateButton.Add_Click({
            param($sender, $e)
            $command = $sourceCommandBox.Text
            $fromVendor = if ($fromVendorDropdown.SelectedItem) { $fromVendorDropdown.SelectedItem.Content } else { $null }
            $toVendor = if ($toVendorDropdown.SelectedItem) { $toVendorDropdown.SelectedItem.Content } else { $null }

            if ([string]::IsNullOrWhiteSpace($command) -or -not $fromVendor -or -not $toVendor) {
                $translatedCommandBox.Text = ''
                return
            }

            $result = CommandReferenceModule\Convert-NetworkCommand -Command $command -FromVendor $fromVendor -ToVendor $toVendor
            if ($result.Success -and $result.HasEquivalent) {
                $translatedCommandBox.Text = $result.TranslatedCommand
                $translatedCommandBox.ToolTip = $result.Notes
            } elseif ($result.Success -and -not $result.HasEquivalent) {
                $translatedCommandBox.Text = '(No equivalent)'
                $translatedCommandBox.ToolTip = 'This command has no direct equivalent in the target vendor'
            } else {
                $translatedCommandBox.Text = '(Unknown command)'
                $translatedCommandBox.ToolTip = $result.Error
            }
        }.GetNewClosure())
    }

    # Translate on Enter key
    if ($sourceCommandBox) {
        $sourceCommandBox.Add_KeyDown({
            param($sender, $e)
            if ($e.Key -eq 'Return') {
                $translateButton.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
            }
        }.GetNewClosure())
    }

    # Copy command button
    if ($copyCommandButton) {
        $copyCommandButton.Add_Click({
            param($sender, $e)
            if ($commandsGrid.SelectedItem) {
                $cmd = $commandsGrid.SelectedItem.Command
                [System.Windows.Clipboard]::SetText($cmd)
            }
        }.GetNewClosure())
    }

    # Compare button click
    if ($compareButton) {
        $compareButton.Add_Click({
            param($sender, $e)
            $task = $compareTaskBox.Text
            if ([string]::IsNullOrWhiteSpace($task)) {
                $compareGrid.ItemsSource = $null
                return
            }

            $comparison = CommandReferenceModule\Get-CommandComparison -Task $task
            $compareGrid.ItemsSource = $comparison
        }.GetNewClosure())
    }

    # Compare on Enter key
    if ($compareTaskBox) {
        $compareTaskBox.Add_KeyDown({
            param($sender, $e)
            if ($e.Key -eq 'Return') {
                $compareButton.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
            }
        }.GetNewClosure())
    }

    # Snippet vendor dropdown change
    if ($snippetVendorDropdown) {
        $snippetVendorDropdown.Add_SelectionChanged({
            param($sender, $e)
            $vendor = if ($snippetVendorDropdown.SelectedItem) { $snippetVendorDropdown.SelectedItem.Content } else { $null }
            & $updateSnippetsFunc -ListBox $snippetsList -Vendor $vendor
        }.GetNewClosure())
    }

    # Snippet selection change
    if ($snippetsList) {
        $snippetsList.Add_SelectionChanged({
            param($sender, $e)
            $selectedItem = $snippetsList.SelectedItem
            if ($null -eq $selectedItem) {
                if ($snippetTitleText) { $snippetTitleText.Text = 'Select a snippet' }
                if ($variablesPanel) { $variablesPanel.Children.Clear() }
                if ($generatedConfigBox) { $generatedConfigBox.Text = '' }
                $view.Tag.CurrentSnippet = $null
                return
            }

            $vendor = if ($snippetVendorDropdown.SelectedItem) { $snippetVendorDropdown.SelectedItem.Content } else { 'Cisco' }
            $snippet = CommandReferenceModule\Get-ConfigSnippet -Task $selectedItem -Vendor $vendor

            if ($null -eq $snippet) {
                if ($snippetTitleText) { $snippetTitleText.Text = 'Snippet not found' }
                return
            }

            $view.Tag.CurrentSnippet = $snippet
            if ($snippetTitleText) { $snippetTitleText.Text = $snippet.Task }
            $view.Tag.VariableInputs = @{}

            # Build variable input controls
            if ($variablesPanel) {
                $variablesPanel.Children.Clear()
                foreach ($varName in $snippet.Variables) {
                    $sp = New-Object System.Windows.Controls.StackPanel
                    $sp.Orientation = 'Horizontal'
                    $sp.Margin = '0,2'

                    $label = New-Object System.Windows.Controls.Label
                    $label.Content = "${varName}:"
                    $label.Width = 120
                    $label.SetResourceReference([System.Windows.Controls.Control]::StyleProperty, 'ToolbarLabelStyle')

                    $textBox = New-Object System.Windows.Controls.TextBox
                    $textBox.Width = 200
                    $textBox.Tag = $varName
                    $textBox.SetResourceReference([System.Windows.Controls.Control]::BackgroundProperty, 'Theme.Input.Background')
                    $textBox.SetResourceReference([System.Windows.Controls.Control]::ForegroundProperty, 'Theme.Input.Text')
                    $textBox.SetResourceReference([System.Windows.Controls.Control]::BorderBrushProperty, 'Theme.Input.Border')

                    $view.Tag.VariableInputs[$varName] = $textBox

                    $sp.Children.Add($label) | Out-Null
                    $sp.Children.Add($textBox) | Out-Null
                    $variablesPanel.Children.Add($sp) | Out-Null
                }
            }

            if ($generatedConfigBox) { $generatedConfigBox.Text = $snippet.Template }
        }.GetNewClosure())
    }

    # Generate config button
    if ($generateConfigButton) {
        $generateConfigButton.Add_Click({
            param($sender, $e)
            $snippet = $view.Tag.CurrentSnippet
            if ($null -eq $snippet) {
                return
            }

            $variables = @{}
            foreach ($kvp in $view.Tag.VariableInputs.GetEnumerator()) {
                $variables[$kvp.Key] = $kvp.Value.Text
            }

            $config = CommandReferenceModule\Expand-ConfigSnippet -Snippet $snippet -Variables $variables
            $generatedConfigBox.Text = $config
        }.GetNewClosure())
    }

    # Copy config button
    if ($copyConfigButton) {
        $copyConfigButton.Add_Click({
            param($sender, $e)
            $config = $generatedConfigBox.Text
            if (-not [string]::IsNullOrWhiteSpace($config)) {
                [System.Windows.Clipboard]::SetText($config)
            }
        }.GetNewClosure())
    }

    # Quick reference search
    if ($quickRefSearchButton) {
        $quickRefSearchButton.Add_Click({
            param($sender, $e)
            $task = $quickRefTaskBox.Text
            if ([string]::IsNullOrWhiteSpace($task)) {
                $quickRefGrid.ItemsSource = $null
                return
            }

            $results = CommandReferenceModule\Find-CommandByTask -Task $task
            $quickRefGrid.ItemsSource = $results
        }.GetNewClosure())
    }

    # Quick ref on Enter key
    if ($quickRefTaskBox) {
        $quickRefTaskBox.Add_KeyDown({
            param($sender, $e)
            if ($e.Key -eq 'Return') {
                $quickRefSearchButton.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
            }
        }.GetNewClosure())
    }

    # Load initial snippets list
    if ($snippetVendorDropdown -and $snippetVendorDropdown.SelectedItem) {
        Update-SnippetsList -ListBox $snippetsList -Vendor $snippetVendorDropdown.SelectedItem.Content
    }
}

Export-ModuleMember -Function New-CommandReferenceView, Initialize-CommandReferenceView
