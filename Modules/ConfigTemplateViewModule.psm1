Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Creates and initializes the Configuration Template view.

.DESCRIPTION
    Loads ConfigTemplateView.xaml using ViewCompositionModule, wires up event handlers,
    and provides template management, generation, and validation functionality.
    Part of Plan U - Configuration Templates & Validation.

.PARAMETER Window
    The parent MainWindow instance.

.PARAMETER ScriptDir
    The root script directory for locating XAML files.

.OUTPUTS
    System.Windows.Controls.UserControl - The initialized view.
#>
function New-ConfigTemplateView {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [System.Windows.Window]$Window,

        [Parameter(Mandatory=$true)]
        [string]$ScriptDir
    )

    try {
        $view = ViewCompositionModule\Set-StView -Window $Window -ScriptDir $ScriptDir `
            -ViewName 'ConfigTemplateView' -HostControlName 'ConfigTemplateHost' `
            -GlobalVariableName 'configTemplateView'
        if (-not $view) { return }

        # Get toolbar controls
        $newTemplateButton = $view.FindName('NewTemplateButton')
        $saveTemplateButton = $view.FindName('SaveTemplateButton')
        $importButton = $view.FindName('ImportButton')
        $exportButton = $view.FindName('ExportButton')
        $loadBuiltInButton = $view.FindName('LoadBuiltInButton')
        $vendorFilterCombo = $view.FindName('VendorFilterCombo')

        # Templates tab controls
        $templateListBox = $view.FindName('TemplateListBox')
        $templateNameBox = $view.FindName('TemplateNameBox')
        $templateVendorCombo = $view.FindName('TemplateVendorCombo')
        $templateTypeCombo = $view.FindName('TemplateTypeCombo')
        $templateContentBox = $view.FindName('TemplateContentBox')
        $variablesItemsControl = $view.FindName('VariablesItemsControl')
        $extractVarsButton = $view.FindName('ExtractVarsButton')
        $generateButton = $view.FindName('GenerateButton')

        # Validation tab controls
        $standardsListBox = $view.FindName('StandardsListBox')
        $standardInfoText = $view.FindName('StandardInfoText')
        $configInputBox = $view.FindName('ConfigInputBox')
        $loadConfigButton = $view.FindName('LoadConfigButton')
        $pasteConfigButton = $view.FindName('PasteConfigButton')
        $validateButton = $view.FindName('ValidateButton')
        $scoreText = $view.FindName('ScoreText')
        $resultsGrid = $view.FindName('ResultsGrid')
        $remediationBox = $view.FindName('RemediationBox')
        $copyRemediationButton = $view.FindName('CopyRemediationButton')
        $exportReportButton = $view.FindName('ExportReportButton')

        # Output tab controls
        $outputBox = $view.FindName('OutputBox')
        $generatedInfoText = $view.FindName('GeneratedInfoText')
        $copyOutputButton = $view.FindName('CopyOutputButton')
        $saveOutputButton = $view.FindName('SaveOutputButton')
        $validateOutputButton = $view.FindName('ValidateOutputButton')

        # Statistics controls
        $totalTemplatesText = $view.FindName('TotalTemplatesText')
        $templatesByVendorList = $view.FindName('TemplatesByVendorList')
        $templatesByTypeList = $view.FindName('TemplatesByTypeList')
        $totalStandardsText = $view.FindName('TotalStandardsText')
        $totalRulesText = $view.FindName('TotalRulesText')
        $standardsListStats = $view.FindName('StandardsListStats')
        $quickLoadBuiltInButton = $view.FindName('QuickLoadBuiltInButton')
        $quickExportAllButton = $view.FindName('QuickExportAllButton')
        $quickClearButton = $view.FindName('QuickClearButton')

        $mainTabControl = $view.FindName('MainTabControl')
        $statusText = $view.FindName('StatusText')
        $dirtyIndicator = $view.FindName('DirtyIndicator')

        # Initialize libraries
        $dataPath = Join-Path $ScriptDir 'Data'
        $templatesPath = Join-Path $dataPath 'ConfigTemplates.json'
        $standardsPath = Join-Path $dataPath 'ValidationStandards.json'

        $script:templateLib = ConfigTemplateModule\New-TemplateLibrary
        $script:standardsLib = ConfigValidationModule\New-StandardsLibrary
        $script:currentVariables = @()
        $script:lastComplianceResult = $null
        $script:isDirty = $false
        $script:isLoadingTemplate = $false  # Suppress dirty tracking during template load

        # Try to load existing data
        if (Test-Path $templatesPath) {
            try {
                ConfigTemplateModule\Import-TemplateLibrary -Path $templatesPath -Library $script:templateLib | Out-Null
            }
            catch { Write-Verbose "Caught exception in ConfigTemplateViewModule.psm1: $($_.Exception.Message)" }
        }

        if (Test-Path $standardsPath) {
            try {
                ConfigValidationModule\Import-StandardsLibrary -Path $standardsPath -Library $script:standardsLib | Out-Null
            }
            catch { Write-Verbose "Caught exception in ConfigTemplateViewModule.psm1: $($_.Exception.Message)" }
        }

        # Store state in view's Tag
        $view.Tag = @{
            TemplateLibrary = $script:templateLib
            StandardsLibrary = $script:standardsLib
            DataPath = $dataPath
            TemplatesPath = $templatesPath
            StandardsPath = $standardsPath
            IsNewTemplate = $true
            SelectedTemplate = $null
            SelectedStandard = $null
        }

        # Helper scriptblocks (each must call .GetNewClosure() to capture referenced variables)
        # Using scriptblocks with closures ensures they are accessible in WPF event handlers

        $GetComboValue = {
            param($Combo)
            if ($Combo.SelectedItem) { return $Combo.SelectedItem.Content }
            return $null
        }.GetNewClosure()

        $SelectComboItem = {
            param($Combo, $Value)
            foreach ($item in $Combo.Items) {
                if ($item.Content -eq $Value) {
                    $Combo.SelectedItem = $item
                    return
                }
            }
        }.GetNewClosure()

        $SetDirty = {
            param([bool]$IsDirty)
            $script:isDirty = $IsDirty
            if ($dirtyIndicator) {
                $dirtyIndicator.Visibility = if ($IsDirty) { 'Visible' } else { 'Collapsed' }
            }
        }.GetNewClosure()

        $MarkDirty = {
            if (-not $script:isLoadingTemplate) {
                & $SetDirty -IsDirty $true
            }
        }.GetNewClosure()

        $CheckDirtyBeforeAction = {
            param([string]$ActionDescription)
            if ($script:isDirty) {
                $result = [System.Windows.MessageBox]::Show(
                    "You have unsaved changes. $ActionDescription anyway?",
                    "Unsaved Changes",
                    [System.Windows.MessageBoxButton]::YesNo,
                    [System.Windows.MessageBoxImage]::Warning)
                return ($result -eq [System.Windows.MessageBoxResult]::Yes)
            }
            return $true
        }.GetNewClosure()

        $SaveLibraries = {
            try {
                $dataPath = $view.Tag.DataPath
                if (-not (Test-Path $dataPath)) {
                    New-Item -ItemType Directory -Path $dataPath -Force | Out-Null
                }
                ConfigTemplateModule\Export-TemplateLibrary -Path $view.Tag.TemplatesPath -Library $view.Tag.TemplateLibrary
                ConfigValidationModule\Export-StandardsLibrary -Path $view.Tag.StandardsPath -Library $view.Tag.StandardsLibrary
            }
            catch {
                $statusText.Text = "Error saving: $($_.Exception.Message)"
            }
        }.GetNewClosure()

        $RefreshTemplateList = {
            $lib = $view.Tag.TemplateLibrary
            $vendor = & $GetComboValue -Combo $vendorFilterCombo
            if ($vendor -eq 'All') { $vendor = $null }

            $templates = @(ConfigTemplateModule\Get-ConfigTemplate -Library $lib -Vendor $vendor)
            $templateListBox.ItemsSource = $templates
        }.GetNewClosure()

        $RefreshStandardsList = {
            $lib = $view.Tag.StandardsLibrary
            $standards = @(ConfigValidationModule\Get-ValidationStandard -Library $lib)
            $standardsListBox.ItemsSource = $standards
        }.GetNewClosure()

        $RefreshStats = {
            $tLib = $view.Tag.TemplateLibrary
            $sLib = $view.Tag.StandardsLibrary

            $tStats = ConfigTemplateModule\Get-TemplateLibraryStats -Library $tLib
            $totalTemplatesText.Text = "Total Templates: $($tStats.TotalTemplates)"

            $vendorList = @()
            foreach ($key in $tStats.ByVendor.Keys) {
                $vendorList += [PSCustomObject]@{ Key = $key; Value = $tStats.ByVendor[$key] }
            }
            $templatesByVendorList.ItemsSource = $vendorList

            $typeList = @()
            foreach ($key in $tStats.ByDeviceType.Keys) {
                $typeList += [PSCustomObject]@{ Key = $key; Value = $tStats.ByDeviceType[$key] }
            }
            $templatesByTypeList.ItemsSource = $typeList

            $standards = @(ConfigValidationModule\Get-ValidationStandard -Library $sLib)
            $totalStandardsText.Text = "Total Standards: $($standards.Count)"
            $totalRules = ($standards | ForEach-Object { $_.Rules.Count } | Measure-Object -Sum).Sum
            $totalRulesText.Text = "Total Rules: $totalRules"

            $statsList = @()
            foreach ($s in $standards) {
                $statsList += [PSCustomObject]@{ Name = $s.Name; RuleCount = $s.Rules.Count }
            }
            $standardsListStats.ItemsSource = $statsList
        }.GetNewClosure()

        $ClearTemplateForm = {
            $script:isLoadingTemplate = $true
            $templateNameBox.Text = ''
            $templateVendorCombo.SelectedIndex = 0
            $templateTypeCombo.SelectedIndex = 0
            $templateContentBox.Text = ''
            $script:currentVariables = @()
            $variablesItemsControl.ItemsSource = $null
            $view.Tag.IsNewTemplate = $true
            $view.Tag.SelectedTemplate = $null
            $script:isLoadingTemplate = $false
            & $SetDirty -IsDirty $false
        }.GetNewClosure()

        $ExtractVariables = {
            $content = $templateContentBox.Text
            if ([string]::IsNullOrWhiteSpace($content)) {
                $script:currentVariables = @()
                $variablesItemsControl.ItemsSource = $null
                return
            }

            $varNames = ConfigTemplateModule\Get-TemplateVariables -Template $content

            # Preserve existing values
            $oldVars = @{}
            foreach ($v in $script:currentVariables) {
                $oldVars[$v.Name] = $v.Value
            }

            $script:currentVariables = @()
            foreach ($name in $varNames) {
                $value = if ($oldVars[$name]) { $oldVars[$name] } else { '' }
                $script:currentVariables += [PSCustomObject]@{ Name = $name; Value = $value }
            }

            $variablesItemsControl.ItemsSource = $script:currentVariables
        }.GetNewClosure()

        $ShowTemplate = {
            param($Template)
            if ($Template) {
                $script:isLoadingTemplate = $true
                $view.Tag.IsNewTemplate = $false
                $view.Tag.SelectedTemplate = $Template
                $templateNameBox.Text = $Template.Name
                & $SelectComboItem -Combo $templateVendorCombo -Value $Template.Vendor
                & $SelectComboItem -Combo $templateTypeCombo -Value $Template.DeviceType
                $templateContentBox.Text = $Template.Content

                # Extract and show variables
                & $ExtractVariables
                $script:isLoadingTemplate = $false
                & $SetDirty -IsDirty $false
            }
        }.GetNewClosure()

        # Event: New Template
        $newTemplateButton.Add_Click({
            param($sender, $e)
            if (-not (& $CheckDirtyBeforeAction -ActionDescription "Create new template")) {
                return
            }
            & $ClearTemplateForm
            $templateListBox.SelectedItem = $null
            $statusText.Text = "New template - fill in details and click Save"
        }.GetNewClosure())

        # Event: Save Template
        if ($saveTemplateButton) {
            $saveTemplateButton.Add_Click({
                param($sender, $e)
                $lib = $view.Tag.TemplateLibrary

                if ([string]::IsNullOrWhiteSpace($templateNameBox.Text)) {
                    $statusText.Text = "Please enter a template name"
                    return
                }

                try {
                    $vendor = & $GetComboValue -Combo $templateVendorCombo
                    $deviceType = & $GetComboValue -Combo $templateTypeCombo

                    if ($view.Tag.IsNewTemplate) {
                        $template = ConfigTemplateModule\New-ConfigTemplate -Name $templateNameBox.Text `
                            -Content $templateContentBox.Text -Vendor $vendor -DeviceType $deviceType
                        $result = ConfigTemplateModule\Add-ConfigTemplate -Template $template -Library $lib
                        if ($result) {
                            $statusText.Text = "Created template: $($templateNameBox.Text)"
                        } else {
                            $statusText.Text = "Template name already exists"
                            return
                        }
                    }
                    else {
                        $props = @{
                            Content = $templateContentBox.Text
                            Vendor = $vendor
                            DeviceType = $deviceType
                        }
                        ConfigTemplateModule\Update-ConfigTemplate -Name $view.Tag.SelectedTemplate.Name `
                            -Properties $props -Library $lib | Out-Null
                        $statusText.Text = "Updated template: $($templateNameBox.Text)"
                    }

                    & $SaveLibraries
                    & $RefreshTemplateList
                    & $RefreshStats
                    & $SetDirty -IsDirty $false
                }
                catch {
                    $statusText.Text = "Error: $($_.Exception.Message)"
                }
            }.GetNewClosure())
        }

        # Event: Template selection
        $templateListBox.Add_SelectionChanged({
            param($sender, $e)
            $selected = $sender.SelectedItem
            if ($selected -and ($selected -ne $view.Tag.SelectedTemplate)) {
                if (-not (& $CheckDirtyBeforeAction -ActionDescription "Switch to another template")) {
                    # Restore previous selection
                    $script:isLoadingTemplate = $true
                    if ($view.Tag.SelectedTemplate) {
                        $sender.SelectedItem = $view.Tag.SelectedTemplate
                    }
                    $script:isLoadingTemplate = $false
                    return
                }
                & $ShowTemplate -Template $selected
            }
        }.GetNewClosure())

        # Event: Extract Variables
        $extractVarsButton.Add_Click({
            param($sender, $e)
            & $ExtractVariables
            $statusText.Text = "Extracted $($script:currentVariables.Count) variables"
        }.GetNewClosure())

        # Event: Generate Config
        $generateButton.Add_Click({
            param($sender, $e)
            $content = $templateContentBox.Text
            if ([string]::IsNullOrWhiteSpace($content)) {
                $statusText.Text = "No template content"
                return
            }

            try {
                # Build variables hashtable
                $vars = @{}
                foreach ($v in $script:currentVariables) {
                    if ($v.Value) {
                        # Try to parse as array if it contains commas
                        if ($v.Value -match ',') {
                            $vars[$v.Name] = @($v.Value -split ',' | ForEach-Object { $_.Trim() })
                        }
                        else {
                            $vars[$v.Name] = $v.Value
                        }
                    }
                }

                $output = ConfigTemplateModule\Expand-ConfigTemplate -Template $content -Variables $vars
                $outputBox.Text = $output
                $generatedInfoText.Text = "Generated at $(Get-Date -Format 'HH:mm:ss') from template: $($templateNameBox.Text)"
                $mainTabControl.SelectedIndex = 2  # Switch to Output tab
                $statusText.Text = "Configuration generated"
            }
            catch {
                $statusText.Text = "Generation error: $($_.Exception.Message)"
            }
        }.GetNewClosure())

        # Event: Vendor filter changed
        $vendorFilterCombo.Add_SelectionChanged({
            param($sender, $e)
            & $RefreshTemplateList
        }.GetNewClosure())

        # Event: Standards selection
        $standardsListBox.Add_SelectionChanged({
            param($sender, $e)
            $selected = $sender.SelectedItem
            if ($selected) {
                $view.Tag.SelectedStandard = $selected
                $standardInfoText.Text = "$($selected.Description)`nVersion: $($selected.Version)`nRules: $($selected.Rules.Count)"
            }
        }.GetNewClosure())

        # Event: Load Config File
        $loadConfigButton.Add_Click({
            param($sender, $e)
            try {
                $dialog = New-Object Microsoft.Win32.OpenFileDialog
                $dialog.Title = 'Load Configuration File'
                $dialog.Filter = 'Text files (*.txt)|*.txt|Config files (*.cfg)|*.cfg|All files (*.*)|*.*'

                if ($dialog.ShowDialog() -eq $true) {
                    $content = Get-Content -Path $dialog.FileName -Raw
                    $configInputBox.Text = $content
                    $statusText.Text = "Loaded: $($dialog.FileName)"
                }
            }
            catch {
                $statusText.Text = "Error loading: $($_.Exception.Message)"
            }
        }.GetNewClosure())

        # Event: Paste Config
        $pasteConfigButton.Add_Click({
            param($sender, $e)
            try {
                $text = [System.Windows.Clipboard]::GetText()
                if ($text) {
                    $configInputBox.Text = $text
                    $statusText.Text = "Pasted from clipboard"
                }
            }
            catch {
                $statusText.Text = "Error pasting: $($_.Exception.Message)"
            }
        }.GetNewClosure())

        # Event: Validate
        $validateButton.Add_Click({
            param($sender, $e)
            $standard = $view.Tag.SelectedStandard
            if (-not $standard) {
                $statusText.Text = "Please select a validation standard"
                return
            }

            $config = $configInputBox.Text
            if ([string]::IsNullOrWhiteSpace($config)) {
                $statusText.Text = "Please enter or load a configuration"
                return
            }

            try {
                $result = ConfigValidationModule\Test-ConfigCompliance -Config $config -Standard $standard -DeviceName 'Input Config'
                $script:lastComplianceResult = $result

                $resultsGrid.ItemsSource = $result.Results
                $scoreText.Text = "Score: $($result.Score)% ($($result.Passed)/$($result.TotalRules) passed)"

                # Generate remediation
                $remediation = ConfigValidationModule\Get-RemediationCommands -ComplianceResult $result
                $remediationBox.Text = $remediation -join "`r`n"

                $statusText.Text = "Validation complete: $($result.Score)% compliance"
            }
            catch {
                $statusText.Text = "Validation error: $($_.Exception.Message)"
            }
        }.GetNewClosure())

        # Event: Copy Remediation
        $copyRemediationButton.Add_Click({
            param($sender, $e)
            if ($remediationBox.Text) {
                [System.Windows.Clipboard]::SetText($remediationBox.Text)
                $statusText.Text = "Remediation commands copied to clipboard"
            }
        }.GetNewClosure())

        # Event: Export Report
        $exportReportButton.Add_Click({
            param($sender, $e)
            if (-not $script:lastComplianceResult) {
                $statusText.Text = "No validation results to export"
                return
            }

            try {
                $dialog = New-Object Microsoft.Win32.SaveFileDialog
                $dialog.Title = 'Export Compliance Report'
                $dialog.Filter = 'HTML files (*.html)|*.html|Text files (*.txt)|*.txt|CSV files (*.csv)|*.csv'
                $dialog.DefaultExt = '.html'

                if ($dialog.ShowDialog() -eq $true) {
                    $format = switch -Regex ($dialog.FileName) {
                        '\.html$' { 'HTML' }
                        '\.csv$' { 'CSV' }
                        default { 'Text' }
                    }
                    $report = ConfigValidationModule\New-ComplianceReport -ComplianceResult $script:lastComplianceResult -Format $format
                    $report | Out-File -FilePath $dialog.FileName -Encoding UTF8
                    $statusText.Text = "Report exported to: $($dialog.FileName)"
                }
            }
            catch {
                $statusText.Text = "Export error: $($_.Exception.Message)"
            }
        }.GetNewClosure())

        # Event: Copy Output
        $copyOutputButton.Add_Click({
            param($sender, $e)
            if ($outputBox.Text) {
                [System.Windows.Clipboard]::SetText($outputBox.Text)
                $statusText.Text = "Configuration copied to clipboard"
            }
        }.GetNewClosure())

        # Event: Save Output
        $saveOutputButton.Add_Click({
            param($sender, $e)
            if ([string]::IsNullOrWhiteSpace($outputBox.Text)) {
                $statusText.Text = "No output to save"
                return
            }

            try {
                $dialog = New-Object Microsoft.Win32.SaveFileDialog
                $dialog.Title = 'Save Generated Configuration'
                $dialog.Filter = 'Text files (*.txt)|*.txt|Config files (*.cfg)|*.cfg'
                $dialog.DefaultExt = '.txt'

                if ($dialog.ShowDialog() -eq $true) {
                    $outputBox.Text | Out-File -FilePath $dialog.FileName -Encoding UTF8
                    $statusText.Text = "Saved to: $($dialog.FileName)"
                }
            }
            catch {
                $statusText.Text = "Save error: $($_.Exception.Message)"
            }
        }.GetNewClosure())

        # Event: Validate Output
        $validateOutputButton.Add_Click({
            param($sender, $e)
            $config = $outputBox.Text
            if ([string]::IsNullOrWhiteSpace($config)) {
                $statusText.Text = "No output to validate"
                return
            }

            $configInputBox.Text = $config
            $mainTabControl.SelectedIndex = 1  # Switch to Validation tab
            $statusText.Text = "Copied output to validation - select a standard and click Validate"
        }.GetNewClosure())

        # Event: Load Built-in
        $loadBuiltInButton.Add_Click({
            param($sender, $e)
            try {
                $tResult = ConfigTemplateModule\Import-BuiltInTemplates -Library $view.Tag.TemplateLibrary
                $sResult = ConfigValidationModule\Import-BuiltInStandards -Library $view.Tag.StandardsLibrary
                & $SaveLibraries
                & $RefreshTemplateList
                & $RefreshStandardsList
                & $RefreshStats
                $statusText.Text = "Loaded $($tResult.Imported) templates, $($sResult.Imported) standards"
            }
            catch {
                $statusText.Text = "Error: $($_.Exception.Message)"
            }
        }.GetNewClosure())

        # Event: Quick Load Built-in
        $quickLoadBuiltInButton.Add_Click({
            param($sender, $e)
            $loadBuiltInButton.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
        }.GetNewClosure())

        # Event: Import
        $importButton.Add_Click({
            param($sender, $e)
            try {
                $dialog = New-Object Microsoft.Win32.OpenFileDialog
                $dialog.Title = 'Import Templates/Standards'
                $dialog.Filter = 'JSON files (*.json)|*.json'

                if ($dialog.ShowDialog() -eq $true) {
                    $content = Get-Content -Path $dialog.FileName -Raw | ConvertFrom-Json
                    if ($content.Templates) {
                        ConfigTemplateModule\Import-TemplateLibrary -Path $dialog.FileName -Library $view.Tag.TemplateLibrary -Merge | Out-Null
                    }
                    if ($content.Standards) {
                        ConfigValidationModule\Import-StandardsLibrary -Path $dialog.FileName -Library $view.Tag.StandardsLibrary -Merge | Out-Null
                    }
                    & $SaveLibraries
                    & $RefreshTemplateList
                    & $RefreshStandardsList
                    & $RefreshStats
                    $statusText.Text = "Imported from: $($dialog.FileName)"
                }
            }
            catch {
                $statusText.Text = "Import error: $($_.Exception.Message)"
            }
        }.GetNewClosure())

        # Event: Export
        $exportButton.Add_Click({
            param($sender, $e)
            try {
                $dialog = New-Object Microsoft.Win32.SaveFileDialog
                $dialog.Title = 'Export Templates'
                $dialog.Filter = 'JSON files (*.json)|*.json'
                $dialog.DefaultExt = '.json'

                if ($dialog.ShowDialog() -eq $true) {
                    ConfigTemplateModule\Export-TemplateLibrary -Path $dialog.FileName -Library $view.Tag.TemplateLibrary
                    $statusText.Text = "Exported to: $($dialog.FileName)"
                }
            }
            catch {
                $statusText.Text = "Export error: $($_.Exception.Message)"
            }
        }.GetNewClosure())

        # Event: Quick Export All
        $quickExportAllButton.Add_Click({
            param($sender, $e)
            $exportButton.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
        }.GetNewClosure())

        # Event: Quick Clear
        $quickClearButton.Add_Click({
            param($sender, $e)
            $result = [System.Windows.MessageBox]::Show(
                "Clear all templates and standards?",
                "Confirm Clear",
                [System.Windows.MessageBoxButton]::YesNo,
                [System.Windows.MessageBoxImage]::Warning)

            if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
                ConfigTemplateModule\Clear-TemplateLibrary -Library $view.Tag.TemplateLibrary
                ConfigValidationModule\Clear-StandardsLibrary -Library $view.Tag.StandardsLibrary
                & $SaveLibraries
                & $RefreshTemplateList
                & $RefreshStandardsList
                & $RefreshStats
                & $ClearTemplateForm
                $statusText.Text = "Libraries cleared"
            }
        }.GetNewClosure())

        # Track edits for dirty state
        $templateNameBox.Add_TextChanged({
            param($sender, $e)
            & $MarkDirty
        }.GetNewClosure())

        $templateContentBox.Add_TextChanged({
            param($sender, $e)
            & $MarkDirty
        }.GetNewClosure())

        $templateVendorCombo.Add_SelectionChanged({
            param($sender, $e)
            & $MarkDirty
        }.GetNewClosure())

        $templateTypeCombo.Add_SelectionChanged({
            param($sender, $e)
            & $MarkDirty
        }.GetNewClosure())

        # Keyboard shortcuts
        $view.Add_PreviewKeyDown({
            param($sender, $e)
            $ctrl = [System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control

            if ($ctrl -and $e.Key -eq 'S') {
                # Ctrl+S - Save template
                if ($saveTemplateButton) {
                    $saveTemplateButton.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
                }
                $e.Handled = $true
            }
            elseif ($ctrl -and $e.Key -eq 'N') {
                # Ctrl+N - New template
                if ($newTemplateButton) {
                    $newTemplateButton.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
                }
                $e.Handled = $true
            }
            elseif ($e.Key -eq 'F5') {
                # F5 - Refresh lists
                & $RefreshTemplateList
                & $RefreshStandardsList
                & $RefreshStats
                $statusText.Text = 'Refreshed'
                $e.Handled = $true
            }
        }.GetNewClosure())

        # Initial load
        & $RefreshTemplateList
        & $RefreshStandardsList
        & $RefreshStats
        $statusText.Text = 'Ready'

        return $view

    } catch {
        Write-Warning "Failed to initialize ConfigTemplate view: $($_.Exception.Message)"
    }
}

function Initialize-ConfigTemplateView {
    <#
    .SYNOPSIS
        Initializes the Config Template view into a Host ContentControl.
        Used for nested tab scenarios where the view is loaded into a container.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.ContentControl]$Host
    )

    try {
        # Load the XAML
        $viewPath = Join-Path $PSScriptRoot '..\Views\ConfigTemplateView.xaml'
        if (-not (Test-Path $viewPath)) {
            Write-Warning "ConfigTemplateView.xaml not found at $viewPath"
            return
        }

        $xamlContent = Get-Content -Path $viewPath -Raw
        $xamlContent = $xamlContent -replace 'x:Class="[^"]*"', ''
        $xamlContent = $xamlContent -replace 'mc:Ignorable="d"', ''

        $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xamlContent))
        $view = [System.Windows.Markup.XamlReader]::Load($reader)
        $Host.Content = $view

        # Get ScriptDir - go up from Modules to project root
        $ScriptDir = Join-Path $PSScriptRoot '..'

        # Now wire up all event handlers (same as New-ConfigTemplateView)
        Initialize-ConfigTemplateEventHandlers -View $view -ScriptDir $ScriptDir

        return $view
    }
    catch {
        Write-Warning "Failed to initialize ConfigTemplate view: $($_.Exception.Message)"
    }
}

function Initialize-ConfigTemplateEventHandlers {
    <#
    .SYNOPSIS
        Wires up event handlers for the Config Template view.
        Called by both New-ConfigTemplateView and Initialize-ConfigTemplateView.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $View,
        [Parameter(Mandatory)]
        [string]$ScriptDir
    )

    $view = $View

    # Get toolbar controls
    $newTemplateButton = $view.FindName('NewTemplateButton')
    $saveTemplateButton = $view.FindName('SaveTemplateButton')
    $importButton = $view.FindName('ImportButton')
    $exportButton = $view.FindName('ExportButton')
    $loadBuiltInButton = $view.FindName('LoadBuiltInButton')
    $vendorFilterCombo = $view.FindName('VendorFilterCombo')

    # Templates tab controls
    $templateListBox = $view.FindName('TemplateListBox')
    $templateNameBox = $view.FindName('TemplateNameBox')
    $templateVendorCombo = $view.FindName('TemplateVendorCombo')
    $templateTypeCombo = $view.FindName('TemplateTypeCombo')
    $templateContentBox = $view.FindName('TemplateContentBox')
    $variablesItemsControl = $view.FindName('VariablesItemsControl')
    $extractVarsButton = $view.FindName('ExtractVarsButton')
    $generateButton = $view.FindName('GenerateButton')

    # Validation tab controls
    $standardsListBox = $view.FindName('StandardsListBox')
    $standardInfoText = $view.FindName('StandardInfoText')
    $configInputBox = $view.FindName('ConfigInputBox')
    $loadConfigButton = $view.FindName('LoadConfigButton')
    $pasteConfigButton = $view.FindName('PasteConfigButton')
    $validateButton = $view.FindName('ValidateButton')
    $scoreText = $view.FindName('ScoreText')
    $resultsGrid = $view.FindName('ResultsGrid')
    $remediationBox = $view.FindName('RemediationBox')
    $copyRemediationButton = $view.FindName('CopyRemediationButton')
    $exportReportButton = $view.FindName('ExportReportButton')

    # Output tab controls
    $outputBox = $view.FindName('OutputBox')
    $generatedInfoText = $view.FindName('GeneratedInfoText')
    $copyOutputButton = $view.FindName('CopyOutputButton')
    $saveOutputButton = $view.FindName('SaveOutputButton')
    $validateOutputButton = $view.FindName('ValidateOutputButton')

    # Statistics controls
    $totalTemplatesText = $view.FindName('TotalTemplatesText')
    $templatesByVendorList = $view.FindName('TemplatesByVendorList')
    $templatesByTypeList = $view.FindName('TemplatesByTypeList')
    $totalStandardsText = $view.FindName('TotalStandardsText')
    $totalRulesText = $view.FindName('TotalRulesText')
    $standardsListStats = $view.FindName('StandardsListStats')
    $quickLoadBuiltInButton = $view.FindName('QuickLoadBuiltInButton')
    $quickExportAllButton = $view.FindName('QuickExportAllButton')
    $quickClearButton = $view.FindName('QuickClearButton')

    $mainTabControl = $view.FindName('MainTabControl')
    $statusText = $view.FindName('StatusText')
    $dirtyIndicator = $view.FindName('DirtyIndicator')

    # Initialize libraries
    $dataPath = Join-Path $ScriptDir 'Data'
    $templatesPath = Join-Path $dataPath 'ConfigTemplates.json'
    $standardsPath = Join-Path $dataPath 'ValidationStandards.json'

    $script:templateLib = ConfigTemplateModule\New-TemplateLibrary
    $script:standardsLib = ConfigValidationModule\New-StandardsLibrary
    $script:currentVariables = @()
    $script:lastComplianceResult = $null
    $script:isDirty = $false
    $script:isLoadingTemplate = $false

    # Try to load existing data
    if (Test-Path $templatesPath) {
        try {
            ConfigTemplateModule\Import-TemplateLibrary -Path $templatesPath -Library $script:templateLib | Out-Null
        }
        catch { Write-Verbose "Caught exception in ConfigTemplateViewModule.psm1: $($_.Exception.Message)" }
    }

    if (Test-Path $standardsPath) {
        try {
            ConfigValidationModule\Import-StandardsLibrary -Path $standardsPath -Library $script:standardsLib | Out-Null
        }
        catch { Write-Verbose "Caught exception in ConfigTemplateViewModule.psm1: $($_.Exception.Message)" }
    }

    # Store state in view's Tag
    $view.Tag = @{
        TemplateLibrary = $script:templateLib
        StandardsLibrary = $script:standardsLib
        DataPath = $dataPath
        TemplatesPath = $templatesPath
        StandardsPath = $standardsPath
        IsNewTemplate = $true
        SelectedTemplate = $null
        SelectedStandard = $null
    }

    # Helper scriptblocks (each must call .GetNewClosure() to capture referenced variables)
    $GetComboValue = {
        param($Combo)
        if ($Combo.SelectedItem) { return $Combo.SelectedItem.Content }
        return $null
    }.GetNewClosure()

    $SelectComboItem = {
        param($Combo, $Value)
        foreach ($item in $Combo.Items) {
            if ($item.Content -eq $Value) {
                $Combo.SelectedItem = $item
                return
            }
        }
    }.GetNewClosure()

    $SetDirty = {
        param([bool]$IsDirty)
        $script:isDirty = $IsDirty
        if ($dirtyIndicator) {
            $dirtyIndicator.Visibility = if ($IsDirty) { 'Visible' } else { 'Collapsed' }
        }
    }.GetNewClosure()

    $MarkDirty = {
        if (-not $script:isLoadingTemplate) {
            & $SetDirty -IsDirty $true
        }
    }.GetNewClosure()

    $CheckDirtyBeforeAction = {
        param([string]$ActionDescription)
        if ($script:isDirty) {
            $result = [System.Windows.MessageBox]::Show(
                "You have unsaved changes. $ActionDescription anyway?",
                "Unsaved Changes",
                [System.Windows.MessageBoxButton]::YesNo,
                [System.Windows.MessageBoxImage]::Warning)
            return ($result -eq [System.Windows.MessageBoxResult]::Yes)
        }
        return $true
    }.GetNewClosure()

    $SaveLibraries = {
        try {
            $dataPath = $view.Tag.DataPath
            if (-not (Test-Path $dataPath)) {
                New-Item -ItemType Directory -Path $dataPath -Force | Out-Null
            }
            ConfigTemplateModule\Export-TemplateLibrary -Path $view.Tag.TemplatesPath -Library $view.Tag.TemplateLibrary
            ConfigValidationModule\Export-StandardsLibrary -Path $view.Tag.StandardsPath -Library $view.Tag.StandardsLibrary
        }
        catch {
            $statusText.Text = "Error saving: $($_.Exception.Message)"
        }
    }.GetNewClosure()

    $RefreshTemplateList = {
        $lib = $view.Tag.TemplateLibrary
        $vendor = & $GetComboValue -Combo $vendorFilterCombo
        if ($vendor -eq 'All') { $vendor = $null }
        $templates = @(ConfigTemplateModule\Get-ConfigTemplate -Library $lib -Vendor $vendor)
        $templateListBox.ItemsSource = $templates
    }.GetNewClosure()

    $RefreshStandardsList = {
        $lib = $view.Tag.StandardsLibrary
        $standards = @(ConfigValidationModule\Get-ValidationStandard -Library $lib)
        $standardsListBox.ItemsSource = $standards
    }.GetNewClosure()

    $RefreshStats = {
        $tLib = $view.Tag.TemplateLibrary
        $sLib = $view.Tag.StandardsLibrary
        $tStats = ConfigTemplateModule\Get-TemplateLibraryStats -Library $tLib
        $totalTemplatesText.Text = "Total Templates: $($tStats.TotalTemplates)"
        $vendorList = @()
        foreach ($key in $tStats.ByVendor.Keys) {
            $vendorList += [PSCustomObject]@{ Key = $key; Value = $tStats.ByVendor[$key] }
        }
        $templatesByVendorList.ItemsSource = $vendorList
        $typeList = @()
        foreach ($key in $tStats.ByDeviceType.Keys) {
            $typeList += [PSCustomObject]@{ Key = $key; Value = $tStats.ByDeviceType[$key] }
        }
        $templatesByTypeList.ItemsSource = $typeList
        $standards = @(ConfigValidationModule\Get-ValidationStandard -Library $sLib)
        $totalStandardsText.Text = "Total Standards: $($standards.Count)"
        $totalRules = ($standards | ForEach-Object { $_.Rules.Count } | Measure-Object -Sum).Sum
        $totalRulesText.Text = "Total Rules: $totalRules"
        $statsList = @()
        foreach ($s in $standards) {
            $statsList += [PSCustomObject]@{ Name = $s.Name; RuleCount = $s.Rules.Count }
        }
        $standardsListStats.ItemsSource = $statsList
    }.GetNewClosure()

    $ClearTemplateForm = {
        $script:isLoadingTemplate = $true
        $templateNameBox.Text = ''
        $templateVendorCombo.SelectedIndex = 0
        $templateTypeCombo.SelectedIndex = 0
        $templateContentBox.Text = ''
        $script:currentVariables = @()
        $variablesItemsControl.ItemsSource = $null
        $view.Tag.IsNewTemplate = $true
        $view.Tag.SelectedTemplate = $null
        $script:isLoadingTemplate = $false
        & $SetDirty -IsDirty $false
    }.GetNewClosure()

    $ExtractVariables = {
        $content = $templateContentBox.Text
        if ([string]::IsNullOrWhiteSpace($content)) {
            $script:currentVariables = @()
            $variablesItemsControl.ItemsSource = $null
            return
        }
        $varNames = ConfigTemplateModule\Get-TemplateVariables -Template $content
        $oldVars = @{}
        foreach ($v in $script:currentVariables) {
            $oldVars[$v.Name] = $v.Value
        }
        $script:currentVariables = @()
        foreach ($name in $varNames) {
            $value = if ($oldVars[$name]) { $oldVars[$name] } else { '' }
            $script:currentVariables += [PSCustomObject]@{ Name = $name; Value = $value }
        }
        $variablesItemsControl.ItemsSource = $script:currentVariables
    }.GetNewClosure()

    $ShowTemplate = {
        param($Template)
        if ($Template) {
            $script:isLoadingTemplate = $true
            $view.Tag.IsNewTemplate = $false
            $view.Tag.SelectedTemplate = $Template
            $templateNameBox.Text = $Template.Name
            & $SelectComboItem -Combo $templateVendorCombo -Value $Template.Vendor
            & $SelectComboItem -Combo $templateTypeCombo -Value $Template.DeviceType
            $templateContentBox.Text = $Template.Content
            & $ExtractVariables
            $script:isLoadingTemplate = $false
            & $SetDirty -IsDirty $false
        }
    }.GetNewClosure()

    # Event: New Template
    if ($newTemplateButton) {
        $newTemplateButton.Add_Click({
            param($sender, $e)
            if (-not (& $CheckDirtyBeforeAction -ActionDescription "Create new template")) { return }
            & $ClearTemplateForm
            $templateListBox.SelectedItem = $null
            $statusText.Text = "New template - fill in details and click Save"
        }.GetNewClosure())
    }

    # Event: Save Template
    if ($saveTemplateButton) {
        $saveTemplateButton.Add_Click({
            param($sender, $e)
            $lib = $view.Tag.TemplateLibrary
            if ([string]::IsNullOrWhiteSpace($templateNameBox.Text)) {
                $statusText.Text = "Please enter a template name"
                return
            }
            try {
                $vendor = & $GetComboValue -Combo $templateVendorCombo
                $deviceType = & $GetComboValue -Combo $templateTypeCombo
                if ($view.Tag.IsNewTemplate) {
                    $template = ConfigTemplateModule\New-ConfigTemplate -Name $templateNameBox.Text `
                        -Content $templateContentBox.Text -Vendor $vendor -DeviceType $deviceType
                    $result = ConfigTemplateModule\Add-ConfigTemplate -Template $template -Library $lib
                    if ($result) {
                        $statusText.Text = "Created template: $($templateNameBox.Text)"
                    } else {
                        $statusText.Text = "Template name already exists"
                        return
                    }
                }
                else {
                    $props = @{
                        Content = $templateContentBox.Text
                        Vendor = $vendor
                        DeviceType = $deviceType
                    }
                    ConfigTemplateModule\Update-ConfigTemplate -Name $view.Tag.SelectedTemplate.Name `
                        -Properties $props -Library $lib | Out-Null
                    $statusText.Text = "Updated template: $($templateNameBox.Text)"
                }
                & $SaveLibraries
                & $RefreshTemplateList
                & $RefreshStats
                & $SetDirty -IsDirty $false
            }
            catch {
                $statusText.Text = "Error: $($_.Exception.Message)"
            }
        }.GetNewClosure())
    }

    # Event: Template selection
    if ($templateListBox) {
        $templateListBox.Add_SelectionChanged({
            param($sender, $e)
            $selected = $sender.SelectedItem
            if ($selected -and ($selected -ne $view.Tag.SelectedTemplate)) {
                if (-not (& $CheckDirtyBeforeAction -ActionDescription "Switch to another template")) {
                    $script:isLoadingTemplate = $true
                    if ($view.Tag.SelectedTemplate) {
                        $sender.SelectedItem = $view.Tag.SelectedTemplate
                    }
                    $script:isLoadingTemplate = $false
                    return
                }
                & $ShowTemplate -Template $selected
            }
        }.GetNewClosure())
    }

    # Event: Extract Variables
    if ($extractVarsButton) {
        $extractVarsButton.Add_Click({
            param($sender, $e)
            & $ExtractVariables
            $statusText.Text = "Extracted $($script:currentVariables.Count) variables"
        }.GetNewClosure())
    }

    # Event: Generate Config
    if ($generateButton) {
        $generateButton.Add_Click({
            param($sender, $e)
            $content = $templateContentBox.Text
            if ([string]::IsNullOrWhiteSpace($content)) {
                $statusText.Text = "No template content"
                return
            }
            try {
                $vars = @{}
                foreach ($v in $script:currentVariables) {
                    if ($v.Value) {
                        if ($v.Value -match ',') {
                            $vars[$v.Name] = @($v.Value -split ',' | ForEach-Object { $_.Trim() })
                        } else {
                            $vars[$v.Name] = $v.Value
                        }
                    }
                }
                $output = ConfigTemplateModule\Expand-ConfigTemplate -Template $content -Variables $vars
                $outputBox.Text = $output
                $generatedInfoText.Text = "Generated at $(Get-Date -Format 'HH:mm:ss') from template: $($templateNameBox.Text)"
                $mainTabControl.SelectedIndex = 2
                $statusText.Text = "Configuration generated"
            }
            catch {
                $statusText.Text = "Generation error: $($_.Exception.Message)"
            }
        }.GetNewClosure())
    }

    # Event: Vendor filter changed
    if ($vendorFilterCombo) {
        $vendorFilterCombo.Add_SelectionChanged({
            param($sender, $e)
            & $RefreshTemplateList
        }.GetNewClosure())
    }

    # Event: Standards selection
    if ($standardsListBox) {
        $standardsListBox.Add_SelectionChanged({
            param($sender, $e)
            $selected = $sender.SelectedItem
            if ($selected) {
                $view.Tag.SelectedStandard = $selected
                $standardInfoText.Text = "$($selected.Description)`nVersion: $($selected.Version)`nRules: $($selected.Rules.Count)"
            }
        }.GetNewClosure())
    }

    # Event: Load Built-in
    if ($loadBuiltInButton) {
        $loadBuiltInButton.Add_Click({
            param($sender, $e)
            try {
                $tResult = ConfigTemplateModule\Import-BuiltInTemplates -Library $view.Tag.TemplateLibrary
                $sResult = ConfigValidationModule\Import-BuiltInStandards -Library $view.Tag.StandardsLibrary
                & $SaveLibraries
                & $RefreshTemplateList
                & $RefreshStandardsList
                & $RefreshStats
                $statusText.Text = "Loaded $($tResult.Imported) templates, $($sResult.Imported) standards"
            }
            catch {
                $statusText.Text = "Error: $($_.Exception.Message)"
            }
        }.GetNewClosure())
    }

    # Track edits for dirty state
    if ($templateNameBox) {
        $templateNameBox.Add_TextChanged({
            param($sender, $e)
            & $MarkDirty
        }.GetNewClosure())
    }

    if ($templateContentBox) {
        $templateContentBox.Add_TextChanged({
            param($sender, $e)
            & $MarkDirty
        }.GetNewClosure())
    }

    if ($templateVendorCombo) {
        $templateVendorCombo.Add_SelectionChanged({
            param($sender, $e)
            & $MarkDirty
        }.GetNewClosure())
    }

    if ($templateTypeCombo) {
        $templateTypeCombo.Add_SelectionChanged({
            param($sender, $e)
            & $MarkDirty
        }.GetNewClosure())
    }

    # Initial load
    & $RefreshTemplateList
    & $RefreshStandardsList
    & $RefreshStats
    if ($statusText) { $statusText.Text = 'Ready' }
}

Export-ModuleMember -Function New-ConfigTemplateView, Initialize-ConfigTemplateView
