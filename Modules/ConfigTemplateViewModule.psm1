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

        # Initialize libraries
        $dataPath = Join-Path $ScriptDir 'Data'
        $templatesPath = Join-Path $dataPath 'ConfigTemplates.json'
        $standardsPath = Join-Path $dataPath 'ValidationStandards.json'

        $script:templateLib = ConfigTemplateModule\New-TemplateLibrary
        $script:standardsLib = ConfigValidationModule\New-StandardsLibrary
        $script:currentVariables = @()
        $script:lastComplianceResult = $null

        # Try to load existing data
        if (Test-Path $templatesPath) {
            try {
                ConfigTemplateModule\Import-TemplateLibrary -Path $templatesPath -Library $script:templateLib | Out-Null
            }
            catch { }
        }

        if (Test-Path $standardsPath) {
            try {
                ConfigValidationModule\Import-StandardsLibrary -Path $standardsPath -Library $script:standardsLib | Out-Null
            }
            catch { }
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

        # Helper: Get combo content
        function Get-ComboValue {
            param($Combo)
            if ($Combo.SelectedItem) { return $Combo.SelectedItem.Content }
            return $null
        }

        # Helper: Select combo by content
        function Select-ComboItem {
            param($Combo, $Value)
            foreach ($item in $Combo.Items) {
                if ($item.Content -eq $Value) {
                    $Combo.SelectedItem = $item
                    return
                }
            }
        }

        # Helper: Save libraries
        function Save-Libraries {
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
        }

        # Helper: Refresh template list
        function Refresh-TemplateList {
            $lib = $view.Tag.TemplateLibrary
            $vendor = Get-ComboValue -Combo $vendorFilterCombo
            if ($vendor -eq 'All') { $vendor = $null }

            $templates = @(ConfigTemplateModule\Get-ConfigTemplate -Library $lib -Vendor $vendor)
            $templateListBox.ItemsSource = $templates
        }

        # Helper: Refresh standards list
        function Refresh-StandardsList {
            $lib = $view.Tag.StandardsLibrary
            $standards = @(ConfigValidationModule\Get-ValidationStandard -Library $lib)
            $standardsListBox.ItemsSource = $standards
        }

        # Helper: Refresh statistics
        function Refresh-Stats {
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
        }

        # Helper: Clear template form
        function Clear-TemplateForm {
            $templateNameBox.Text = ''
            $templateVendorCombo.SelectedIndex = 0
            $templateTypeCombo.SelectedIndex = 0
            $templateContentBox.Text = ''
            $script:currentVariables = @()
            $variablesItemsControl.ItemsSource = $null
            $view.Tag.IsNewTemplate = $true
            $view.Tag.SelectedTemplate = $null
        }

        # Helper: Show template
        function Show-Template {
            param($Template)
            if ($Template) {
                $view.Tag.IsNewTemplate = $false
                $view.Tag.SelectedTemplate = $Template
                $templateNameBox.Text = $Template.Name
                Select-ComboItem -Combo $templateVendorCombo -Value $Template.Vendor
                Select-ComboItem -Combo $templateTypeCombo -Value $Template.DeviceType
                $templateContentBox.Text = $Template.Content

                # Extract and show variables
                Extract-Variables
            }
        }

        # Helper: Extract variables from template
        function Extract-Variables {
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
        }

        # Event: New Template
        $newTemplateButton.Add_Click({
            param($sender, $e)
            Clear-TemplateForm
            $templateListBox.SelectedItem = $null
            $statusText.Text = "New template - fill in details and click Save"
        }.GetNewClosure())

        # Event: Save Template
        $saveTemplateButton.Add_Click({
            param($sender, $e)
            $lib = $view.Tag.TemplateLibrary

            if ([string]::IsNullOrWhiteSpace($templateNameBox.Text)) {
                $statusText.Text = "Please enter a template name"
                return
            }

            try {
                $vendor = Get-ComboValue -Combo $templateVendorCombo
                $deviceType = Get-ComboValue -Combo $templateTypeCombo

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

                Save-Libraries
                Refresh-TemplateList
                Refresh-Stats
            }
            catch {
                $statusText.Text = "Error: $($_.Exception.Message)"
            }
        }.GetNewClosure())

        # Event: Template selection
        $templateListBox.Add_SelectionChanged({
            param($sender, $e)
            $selected = $sender.SelectedItem
            if ($selected) {
                Show-Template -Template $selected
            }
        }.GetNewClosure())

        # Event: Extract Variables
        $extractVarsButton.Add_Click({
            param($sender, $e)
            Extract-Variables
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
            Refresh-TemplateList
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
                Save-Libraries
                Refresh-TemplateList
                Refresh-StandardsList
                Refresh-Stats
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
                    Save-Libraries
                    Refresh-TemplateList
                    Refresh-StandardsList
                    Refresh-Stats
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
                Save-Libraries
                Refresh-TemplateList
                Refresh-StandardsList
                Refresh-Stats
                Clear-TemplateForm
                $statusText.Text = "Libraries cleared"
            }
        }.GetNewClosure())

        # Initial load
        Refresh-TemplateList
        Refresh-StandardsList
        Refresh-Stats
        $statusText.Text = 'Ready'

        return $view

    } catch {
        Write-Warning "Failed to initialize ConfigTemplate view: $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function New-ConfigTemplateView
