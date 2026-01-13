#Requires -Version 5.1
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    View module for the Documentation Generator UI.

.DESCRIPTION
    Wires up the DocumentationGeneratorView.xaml to the DocumentationGeneratorModule functions.
    Handles UI events and data binding for document generation, templates, and scheduling.

.NOTES
    Plan AA - Network Documentation Generator
#>

# Module-level references to UI controls
$script:DocGenView = $null
$script:TemplatesGrid = $null
$script:DocumentsGrid = $null
$script:SchedulesGrid = $null
$script:HistoryGrid = $null
$script:PreviewTextBox = $null

function Initialize-DocumentationGeneratorView {
    <#
    .SYNOPSIS
        Initializes the Documentation Generator view and wires up event handlers.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.ContentControl]$Host
    )

    # Load the XAML
    $viewPath = Join-Path $PSScriptRoot '..\Views\DocumentationGeneratorView.xaml'
    if (-not (Test-Path $viewPath)) {
        Write-Warning "Documentation Generator view not found at $viewPath"
        return
    }

    $xamlContent = Get-Content -Path $viewPath -Raw
    $xamlContent = $xamlContent -replace 'x:Class="[^"]*"', ''
    $xamlContent = $xamlContent -replace 'mc:Ignorable="d"', ''

    try {
        $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xamlContent))
        $script:DocGenView = [System.Windows.Markup.XamlReader]::Load($reader)
    }
    catch {
        Write-Warning "Failed to load Documentation Generator view: $_"
        return
    }

    # Set the view content
    $Host.Content = $script:DocGenView

    # Get control references
    Get-DocumentationGeneratorControls

    # Wire up event handlers
    Register-DocumentationGeneratorEvents

    # Initialize data
    Update-DocumentationGeneratorStatistics
    Update-TemplatesGrid
    Update-DocumentsGrid
    Update-SchedulesGrid
    Update-HistoryGrid
    Update-GenerateTemplateCombo
    Update-ExportDocumentCombo

}

function Get-DocumentationGeneratorControls {
    <#
    .SYNOPSIS
        Gets references to UI controls.
    #>

    # Statistics labels
    $script:TemplatesCountLabel = $script:DocGenView.FindName('TemplatesCountLabel')
    $script:DocumentsCountLabel = $script:DocGenView.FindName('DocumentsCountLabel')
    $script:SchedulesCountLabel = $script:DocGenView.FindName('SchedulesCountLabel')
    $script:BuiltInCountLabel = $script:DocGenView.FindName('BuiltInCountLabel')
    $script:RefreshStatsButton = $script:DocGenView.FindName('RefreshStatsButton')

    # Templates tab
    $script:TemplatesGrid = $script:DocGenView.FindName('TemplatesGrid')
    $script:TemplateCategoryFilter = $script:DocGenView.FindName('TemplateCategoryFilter')
    $script:TemplateSearchBox = $script:DocGenView.FindName('TemplateSearchBox')
    $script:NewTemplateButton = $script:DocGenView.FindName('NewTemplateButton')
    $script:ViewTemplateButton = $script:DocGenView.FindName('ViewTemplateButton')
    $script:EditTemplateButton = $script:DocGenView.FindName('EditTemplateButton')
    $script:CopyTemplateButton = $script:DocGenView.FindName('CopyTemplateButton')
    $script:DeleteTemplateButton = $script:DocGenView.FindName('DeleteTemplateButton')
    $script:ValidateTemplateButton = $script:DocGenView.FindName('ValidateTemplateButton')

    # Generate tab
    $script:GenerateTemplateCombo = $script:DocGenView.FindName('GenerateTemplateCombo')
    $script:GenerateTitleBox = $script:DocGenView.FindName('GenerateTitleBox')
    $script:GenerateScopeBox = $script:DocGenView.FindName('GenerateScopeBox')
    $script:PreviewTextBox = $script:DocGenView.FindName('PreviewTextBox')
    $script:GenerateDocumentButton = $script:DocGenView.FindName('GenerateDocumentButton')
    $script:CopyPreviewButton = $script:DocGenView.FindName('CopyPreviewButton')
    $script:QuickSiteAsBuiltButton = $script:DocGenView.FindName('QuickSiteAsBuiltButton')
    $script:QuickDeviceSummaryButton = $script:DocGenView.FindName('QuickDeviceSummaryButton')
    $script:QuickVLANReportButton = $script:DocGenView.FindName('QuickVLANReportButton')
    $script:QuickExecutiveButton = $script:DocGenView.FindName('QuickExecutiveButton')

    # Documents tab
    $script:DocumentsGrid = $script:DocGenView.FindName('DocumentsGrid')
    $script:DocumentScopeFilter = $script:DocGenView.FindName('DocumentScopeFilter')
    $script:DocumentTemplateFilter = $script:DocGenView.FindName('DocumentTemplateFilter')
    $script:DocumentSearchBox = $script:DocGenView.FindName('DocumentSearchBox')
    $script:ViewDocumentButton = $script:DocGenView.FindName('ViewDocumentButton')
    $script:ExportDocumentButton = $script:DocGenView.FindName('ExportDocumentButton')
    $script:RegenerateDocumentButton = $script:DocGenView.FindName('RegenerateDocumentButton')
    $script:DeleteDocumentButton = $script:DocGenView.FindName('DeleteDocumentButton')

    # Schedules tab
    $script:SchedulesGrid = $script:DocGenView.FindName('SchedulesGrid')
    $script:NewScheduleButton = $script:DocGenView.FindName('NewScheduleButton')
    $script:ShowEnabledOnlyCheckbox = $script:DocGenView.FindName('ShowEnabledOnlyCheckbox')
    $script:EnableScheduleButton = $script:DocGenView.FindName('EnableScheduleButton')
    $script:DisableScheduleButton = $script:DocGenView.FindName('DisableScheduleButton')
    $script:RunNowButton = $script:DocGenView.FindName('RunNowButton')
    $script:DeleteScheduleButton = $script:DocGenView.FindName('DeleteScheduleButton')

    # Export tab
    $script:ExportDocumentCombo = $script:DocGenView.FindName('ExportDocumentCombo')
    $script:ExportFormatCombo = $script:DocGenView.FindName('ExportFormatCombo')
    $script:ExportPathBox = $script:DocGenView.FindName('ExportPathBox')
    $script:BrowseExportPathButton = $script:DocGenView.FindName('BrowseExportPathButton')
    $script:ExportButton = $script:DocGenView.FindName('ExportButton')
    $script:ExportAllScopeButton = $script:DocGenView.FindName('ExportAllScopeButton')
    $script:ExportAllTemplateButton = $script:DocGenView.FindName('ExportAllTemplateButton')
    $script:ExportHistoryGrid = $script:DocGenView.FindName('ExportHistoryGrid')

    # History tab
    $script:HistoryGrid = $script:DocGenView.FindName('HistoryGrid')
    $script:HistoryDocumentFilter = $script:DocGenView.FindName('HistoryDocumentFilter')
    $script:RefreshHistoryButton = $script:DocGenView.FindName('RefreshHistoryButton')
}

function Register-DocumentationGeneratorEvents {
    <#
    .SYNOPSIS
        Registers event handlers for UI controls.
    #>

    # Statistics refresh
    if ($script:RefreshStatsButton) {
        $script:RefreshStatsButton.Add_Click({
            Update-DocumentationGeneratorStatistics
            Update-TemplatesGrid
            Update-DocumentsGrid
            Update-SchedulesGrid
            Update-HistoryGrid
        })
    }

    # Templates tab events
    if ($script:TemplateCategoryFilter) {
        $script:TemplateCategoryFilter.Add_SelectionChanged({ Update-TemplatesGrid })
    }

    if ($script:TemplateSearchBox) {
        $script:TemplateSearchBox.Add_TextChanged({ Update-TemplatesGrid })
    }

    if ($script:NewTemplateButton) {
        $script:NewTemplateButton.Add_Click({ Show-NewTemplateDialog })
    }

    if ($script:ViewTemplateButton) {
        $script:ViewTemplateButton.Add_Click({ Show-TemplateViewer })
    }

    if ($script:EditTemplateButton) {
        $script:EditTemplateButton.Add_Click({ Show-TemplateEditor })
    }

    if ($script:CopyTemplateButton) {
        $script:CopyTemplateButton.Add_Click({ Copy-SelectedTemplate })
    }

    if ($script:DeleteTemplateButton) {
        $script:DeleteTemplateButton.Add_Click({ Remove-SelectedTemplate })
    }

    if ($script:ValidateTemplateButton) {
        $script:ValidateTemplateButton.Add_Click({ Test-SelectedTemplate })
    }

    # Generate tab events
    if ($script:GenerateTemplateCombo) {
        $script:GenerateTemplateCombo.Add_SelectionChanged({ Update-GeneratePreview })
    }

    if ($script:GenerateDocumentButton) {
        $script:GenerateDocumentButton.Add_Click({ Invoke-GenerateDocument })
    }

    if ($script:CopyPreviewButton) {
        $script:CopyPreviewButton.Add_Click({
            param($sender, $e)
            if ($script:PreviewTextBox.Text) {
                [System.Windows.Clipboard]::SetText($script:PreviewTextBox.Text)
                ViewCompositionModule\Show-CopyFeedback -Button $sender
            }
        })
    }

    if ($script:QuickSiteAsBuiltButton) {
        $script:QuickSiteAsBuiltButton.Add_Click({ Invoke-QuickGenerate -TemplateID 'Site-AsBuilt' })
    }

    if ($script:QuickDeviceSummaryButton) {
        $script:QuickDeviceSummaryButton.Add_Click({ Invoke-QuickGenerate -TemplateID 'Device-Summary' })
    }

    if ($script:QuickVLANReportButton) {
        $script:QuickVLANReportButton.Add_Click({ Invoke-QuickGenerate -TemplateID 'VLAN-Reference' })
    }

    if ($script:QuickExecutiveButton) {
        $script:QuickExecutiveButton.Add_Click({ Invoke-QuickGenerate -TemplateID 'Executive-Summary' })
    }

    # Documents tab events
    if ($script:DocumentScopeFilter) {
        $script:DocumentScopeFilter.Add_SelectionChanged({ Update-DocumentsGrid })
    }

    if ($script:DocumentTemplateFilter) {
        $script:DocumentTemplateFilter.Add_SelectionChanged({ Update-DocumentsGrid })
    }

    if ($script:ViewDocumentButton) {
        $script:ViewDocumentButton.Add_Click({ Show-DocumentViewer })
    }

    if ($script:ExportDocumentButton) {
        $script:ExportDocumentButton.Add_Click({ Export-SelectedDocument })
    }

    if ($script:DeleteDocumentButton) {
        $script:DeleteDocumentButton.Add_Click({ Remove-SelectedDocument })
    }

    # Schedules tab events
    if ($script:NewScheduleButton) {
        $script:NewScheduleButton.Add_Click({ Show-NewScheduleDialog })
    }

    if ($script:ShowEnabledOnlyCheckbox) {
        $script:ShowEnabledOnlyCheckbox.Add_Checked({ Update-SchedulesGrid })
        $script:ShowEnabledOnlyCheckbox.Add_Unchecked({ Update-SchedulesGrid })
    }

    if ($script:EnableScheduleButton) {
        $script:EnableScheduleButton.Add_Click({ Set-SelectedScheduleEnabled -Enabled $true })
    }

    if ($script:DisableScheduleButton) {
        $script:DisableScheduleButton.Add_Click({ Set-SelectedScheduleEnabled -Enabled $false })
    }

    if ($script:DeleteScheduleButton) {
        $script:DeleteScheduleButton.Add_Click({ Remove-SelectedSchedule })
    }

    # Export tab events
    if ($script:ExportDocumentCombo) {
        $script:ExportDocumentCombo.Add_SelectionChanged({ Update-ExportPreview })
    }

    if ($script:BrowseExportPathButton) {
        $script:BrowseExportPathButton.Add_Click({ Browse-ExportPath })
    }

    if ($script:ExportButton) {
        $script:ExportButton.Add_Click({ Invoke-ExportDocument })
    }

    # History tab events
    if ($script:RefreshHistoryButton) {
        $script:RefreshHistoryButton.Add_Click({ Update-HistoryGrid })
    }
}

#region Statistics Functions

function Update-DocumentationGeneratorStatistics {
    <#
    .SYNOPSIS
        Updates the statistics display.
    #>
    try {
        $stats = Get-DocumentStatistics

        if ($script:TemplatesCountLabel) {
            $script:TemplatesCountLabel.Text = $stats.TotalTemplates.ToString()
        }

        if ($script:DocumentsCountLabel) {
            $script:DocumentsCountLabel.Text = $stats.TotalDocuments.ToString()
        }

        if ($script:SchedulesCountLabel) {
            $script:SchedulesCountLabel.Text = $stats.ActiveSchedules.ToString()
        }

        if ($script:BuiltInCountLabel) {
            $script:BuiltInCountLabel.Text = $stats.BuiltInTemplates.ToString()
        }
    }
    catch {
        Write-Warning "Failed to update statistics: $_"
    }
}

#endregion

#region Templates Functions

function Update-TemplatesGrid {
    <#
    .SYNOPSIS
        Updates the templates grid with filtered data.
    #>
    if (-not $script:TemplatesGrid) { return }

    try {
        $templates = Get-DocumentTemplate

        # Apply category filter
        if ($script:TemplateCategoryFilter -and $script:TemplateCategoryFilter.SelectedIndex -gt 0) {
            $category = ($script:TemplateCategoryFilter.SelectedItem).Content
            $templates = $templates | Where-Object { $_.Category -eq $category }
        }

        # Apply search filter
        if ($script:TemplateSearchBox -and $script:TemplateSearchBox.Text) {
            $search = $script:TemplateSearchBox.Text
            $templates = $templates | Where-Object {
                $_.Name -like "*$search*" -or $_.TemplateID -like "*$search*" -or $_.Description -like "*$search*"
            }
        }

        $script:TemplatesGrid.ItemsSource = @($templates)
    }
    catch {
        Write-Warning "Failed to update templates grid: $_"
    }
}

function Show-NewTemplateDialog {
    <#
    .SYNOPSIS
        Shows a dialog to create a new template.
    #>
    $name = Show-InputDialog -Title 'New Template' -Prompt 'Enter template name:'
    if (-not $name) { return }

    $content = @"
# {{title}}

**Generated:** {{generated_date}}

## Content

Add your template content here.
Use {{variable}} for variable substitution.
Use {{#each items}}...{{/each}} for loops.
Use {{#if condition}}...{{/if}} for conditionals.

---

*Document generated by StateTrace Documentation Generator*
"@

    try {
        $template = New-DocumentTemplate -Name $name -Content $content -Description "Custom template: $name"
        Update-TemplatesGrid
        Update-DocumentationGeneratorStatistics
        [System.Windows.MessageBox]::Show("Template '$name' created successfully.", 'Success', 'OK', 'Information')
    }
    catch {
        [System.Windows.MessageBox]::Show("Failed to create template: $_", 'Error', 'OK', 'Error')
    }
}

function Show-TemplateViewer {
    <#
    .SYNOPSIS
        Shows the selected template content in a viewer window.
    #>
    $selected = $script:TemplatesGrid.SelectedItem
    if (-not $selected) {
        [System.Windows.MessageBox]::Show('Please select a template to view.', 'No Selection', 'OK', 'Warning')
        return
    }

    $content = "Template: $($selected.Name)`n"
    $content += "ID: $($selected.TemplateID)`n"
    $content += "Category: $($selected.Category)`n"
    $content += "Version: $($selected.Version)`n"
    $content += "Built-in: $($selected.IsBuiltIn)`n"
    $content += "`n--- Content ---`n`n"
    $content += $selected.Content

    Show-TextDialog -Title "Template: $($selected.Name)" -Content $content
}

function Show-TemplateEditor {
    <#
    .SYNOPSIS
        Opens the template editor for the selected template.
    #>
    $selected = $script:TemplatesGrid.SelectedItem
    if (-not $selected) {
        [System.Windows.MessageBox]::Show('Please select a template to edit.', 'No Selection', 'OK', 'Warning')
        return
    }

    if ($selected.IsBuiltIn) {
        [System.Windows.MessageBox]::Show('Built-in templates cannot be edited. Use Copy to create an editable version.', 'Cannot Edit', 'OK', 'Warning')
        return
    }

    $newContent = Show-TextInputDialog -Title "Edit Template: $($selected.Name)" -Content $selected.Content
    if ($newContent -and $newContent -ne $selected.Content) {
        try {
            $null = Update-DocumentTemplate -TemplateID $selected.TemplateID -Content $newContent
            Update-TemplatesGrid
            [System.Windows.MessageBox]::Show('Template updated successfully.', 'Success', 'OK', 'Information')
        }
        catch {
            [System.Windows.MessageBox]::Show("Failed to update template: $_", 'Error', 'OK', 'Error')
        }
    }
}

function Copy-SelectedTemplate {
    <#
    .SYNOPSIS
        Creates a copy of the selected template.
    #>
    $selected = $script:TemplatesGrid.SelectedItem
    if (-not $selected) {
        [System.Windows.MessageBox]::Show('Please select a template to copy.', 'No Selection', 'OK', 'Warning')
        return
    }

    $newName = Show-InputDialog -Title 'Copy Template' -Prompt 'Enter name for the copy:' -Default "$($selected.Name) (Copy)"
    if (-not $newName) { return }

    try {
        $template = New-DocumentTemplate -Name $newName -Content $selected.Content -Description "Copy of $($selected.Name)" -Category $selected.Category
        Update-TemplatesGrid
        Update-DocumentationGeneratorStatistics
        [System.Windows.MessageBox]::Show("Template copied as '$newName'.", 'Success', 'OK', 'Information')
    }
    catch {
        [System.Windows.MessageBox]::Show("Failed to copy template: $_", 'Error', 'OK', 'Error')
    }
}

function Remove-SelectedTemplate {
    <#
    .SYNOPSIS
        Removes the selected template.
    #>
    $selected = $script:TemplatesGrid.SelectedItem
    if (-not $selected) {
        [System.Windows.MessageBox]::Show('Please select a template to delete.', 'No Selection', 'OK', 'Warning')
        return
    }

    if ($selected.IsBuiltIn) {
        [System.Windows.MessageBox]::Show('Built-in templates cannot be deleted.', 'Cannot Delete', 'OK', 'Warning')
        return
    }

    $result = [System.Windows.MessageBox]::Show("Delete template '$($selected.Name)'?", 'Confirm Delete', 'YesNo', 'Question')
    if ($result -eq 'Yes') {
        try {
            Remove-DocumentTemplate -TemplateID $selected.TemplateID
            Update-TemplatesGrid
            Update-DocumentationGeneratorStatistics
        }
        catch {
            [System.Windows.MessageBox]::Show("Failed to delete template: $_", 'Error', 'OK', 'Error')
        }
    }
}

function Test-SelectedTemplate {
    <#
    .SYNOPSIS
        Validates the selected template.
    #>
    $selected = $script:TemplatesGrid.SelectedItem
    if (-not $selected) {
        [System.Windows.MessageBox]::Show('Please select a template to validate.', 'No Selection', 'OK', 'Warning')
        return
    }

    try {
        $result = Test-DocumentTemplate -Content $selected.Content

        if ($result.IsValid) {
            $msg = "Template is valid.`n`nVariables used:`n"
            $msg += ($result.Variables -join ", ")
            [System.Windows.MessageBox]::Show($msg, 'Validation Passed', 'OK', 'Information')
        }
        else {
            $msg = "Template has errors:`n`n"
            $msg += ($result.Errors -join "`n")
            [System.Windows.MessageBox]::Show($msg, 'Validation Failed', 'OK', 'Warning')
        }
    }
    catch {
        [System.Windows.MessageBox]::Show("Validation error: $_", 'Error', 'OK', 'Error')
    }
}

#endregion

#region Generate Functions

function Update-GenerateTemplateCombo {
    <#
    .SYNOPSIS
        Updates the template dropdown in the Generate tab.
    #>
    if (-not $script:GenerateTemplateCombo) { return }

    try {
        $templates = Get-DocumentTemplate | Sort-Object Name
        $script:GenerateTemplateCombo.Items.Clear()

        foreach ($template in $templates) {
            $item = New-Object System.Windows.Controls.ComboBoxItem
            $item.Content = "$($template.Name) ($($template.TemplateID))"
            $item.Tag = $template.TemplateID
            $script:GenerateTemplateCombo.Items.Add($item) | Out-Null
        }

        if ($script:GenerateTemplateCombo.Items.Count -gt 0) {
            $script:GenerateTemplateCombo.SelectedIndex = 0
        }
    }
    catch {
        Write-Warning "Failed to update generate template combo: $_"
    }
}

function Update-GeneratePreview {
    <#
    .SYNOPSIS
        Updates the preview based on selected template.
    #>
    if (-not $script:PreviewTextBox -or -not $script:GenerateTemplateCombo.SelectedItem) { return }

    try {
        $templateId = $script:GenerateTemplateCombo.SelectedItem.Tag
        $template = Get-DocumentTemplate -TemplateID $templateId

        if ($template) {
            $script:PreviewTextBox.Text = $template.Content
        }
    }
    catch {
        Write-Warning "Failed to update preview: $_"
    }
}

function Invoke-GenerateDocument {
    <#
    .SYNOPSIS
        Generates a document based on the current settings.
    #>
    if (-not $script:GenerateTemplateCombo.SelectedItem) {
        [System.Windows.MessageBox]::Show('Please select a template.', 'No Template', 'OK', 'Warning')
        return
    }

    $templateId = $script:GenerateTemplateCombo.SelectedItem.Tag
    $title = $script:GenerateTitleBox.Text
    $scope = $script:GenerateScopeBox.Text

    if (-not $title) {
        $title = "Document - $(Get-Date -Format 'yyyy-MM-dd')"
    }

    try {
        $variables = @{}
        if ($scope) {
            $variables['site_name'] = $scope
            $variables['scope'] = $scope
        }

        $doc = New-Document -TemplateID $templateId -Title $title -Variables $variables -Scope $scope
        $script:PreviewTextBox.Text = $doc.Content

        Update-DocumentsGrid
        Update-DocumentationGeneratorStatistics
        Update-ExportDocumentCombo

        [System.Windows.MessageBox]::Show("Document '$title' generated successfully.", 'Success', 'OK', 'Information')
    }
    catch {
        [System.Windows.MessageBox]::Show("Failed to generate document: $_", 'Error', 'OK', 'Error')
    }
}

function Invoke-QuickGenerate {
    <#
    .SYNOPSIS
        Quickly generates a document with a specific template.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$TemplateID
    )

    $scope = $script:GenerateScopeBox.Text
    if (-not $scope) {
        $scope = Show-InputDialog -Title 'Quick Generate' -Prompt 'Enter scope (e.g., site name):'
        if (-not $scope) { return }
        $script:GenerateScopeBox.Text = $scope
    }

    try {
        $variables = @{
            site_name = $scope
            scope = $scope
        }

        $title = "$scope - $TemplateID - $(Get-Date -Format 'yyyy-MM-dd')"
        $doc = New-Document -TemplateID $TemplateID -Title $title -Variables $variables -Scope $scope
        $script:PreviewTextBox.Text = $doc.Content

        Update-DocumentsGrid
        Update-DocumentationGeneratorStatistics
        Update-ExportDocumentCombo

        [System.Windows.MessageBox]::Show("Document generated successfully.", 'Success', 'OK', 'Information')
    }
    catch {
        [System.Windows.MessageBox]::Show("Failed to generate document: $_", 'Error', 'OK', 'Error')
    }
}

#endregion

#region Documents Functions

function Update-DocumentsGrid {
    <#
    .SYNOPSIS
        Updates the documents grid with filtered data.
    #>
    if (-not $script:DocumentsGrid) { return }

    try {
        $documents = Get-GeneratedDocument

        # Apply scope filter
        if ($script:DocumentScopeFilter -and $script:DocumentScopeFilter.SelectedIndex -gt 0) {
            $scope = ($script:DocumentScopeFilter.SelectedItem).Content
            $documents = $documents | Where-Object { $_.Scope -eq $scope }
        }

        # Apply template filter
        if ($script:DocumentTemplateFilter -and $script:DocumentTemplateFilter.SelectedIndex -gt 0) {
            $templateId = ($script:DocumentTemplateFilter.SelectedItem).Content
            $documents = $documents | Where-Object { $_.TemplateID -eq $templateId }
        }

        $script:DocumentsGrid.ItemsSource = @($documents)
    }
    catch {
        Write-Warning "Failed to update documents grid: $_"
    }
}

function Show-DocumentViewer {
    <#
    .SYNOPSIS
        Shows the selected document in a viewer.
    #>
    $selected = $script:DocumentsGrid.SelectedItem
    if (-not $selected) {
        [System.Windows.MessageBox]::Show('Please select a document to view.', 'No Selection', 'OK', 'Warning')
        return
    }

    Show-TextDialog -Title "Document: $($selected.Title)" -Content $selected.Content
}

function Export-SelectedDocument {
    <#
    .SYNOPSIS
        Exports the selected document.
    #>
    $selected = $script:DocumentsGrid.SelectedItem
    if (-not $selected) {
        [System.Windows.MessageBox]::Show('Please select a document to export.', 'No Selection', 'OK', 'Warning')
        return
    }

    # Update export tab with selection
    if ($script:ExportDocumentCombo) {
        foreach ($item in $script:ExportDocumentCombo.Items) {
            if ($item.Tag -eq $selected.DocumentID) {
                $script:ExportDocumentCombo.SelectedItem = $item
                break
            }
        }
    }

    # Switch to export tab - find parent TabControl and switch
    $tabControl = $script:DocumentsGrid.Parent
    while ($tabControl -and $tabControl -isnot [System.Windows.Controls.TabControl]) {
        $tabControl = $tabControl.Parent
    }
    if ($tabControl) {
        $tabControl.SelectedIndex = 4  # Export tab index
    }
}

function Remove-SelectedDocument {
    <#
    .SYNOPSIS
        Removes the selected document.
    #>
    $selected = $script:DocumentsGrid.SelectedItem
    if (-not $selected) {
        [System.Windows.MessageBox]::Show('Please select a document to delete.', 'No Selection', 'OK', 'Warning')
        return
    }

    $result = [System.Windows.MessageBox]::Show("Delete document '$($selected.Title)'?", 'Confirm Delete', 'YesNo', 'Question')
    if ($result -eq 'Yes') {
        try {
            Remove-GeneratedDocument -DocumentID $selected.DocumentID
            Update-DocumentsGrid
            Update-DocumentationGeneratorStatistics
            Update-ExportDocumentCombo
        }
        catch {
            [System.Windows.MessageBox]::Show("Failed to delete document: $_", 'Error', 'OK', 'Error')
        }
    }
}

#endregion

#region Schedules Functions

function Update-SchedulesGrid {
    <#
    .SYNOPSIS
        Updates the schedules grid.
    #>
    if (-not $script:SchedulesGrid) { return }

    try {
        $enabledOnly = $script:ShowEnabledOnlyCheckbox -and $script:ShowEnabledOnlyCheckbox.IsChecked
        $schedules = Get-DocumentSchedule -EnabledOnly:$enabledOnly

        $script:SchedulesGrid.ItemsSource = @($schedules)
    }
    catch {
        Write-Warning "Failed to update schedules grid: $_"
    }
}

function Show-NewScheduleDialog {
    <#
    .SYNOPSIS
        Shows a dialog to create a new schedule.
    #>
    # Simple implementation - create schedule with defaults
    if (-not $script:GenerateTemplateCombo.SelectedItem) {
        [System.Windows.MessageBox]::Show('Please select a template in the Generate tab first.', 'No Template', 'OK', 'Warning')
        return
    }

    $templateId = $script:GenerateTemplateCombo.SelectedItem.Tag
    $scope = $script:GenerateScopeBox.Text

    try {
        $schedule = New-DocumentSchedule -TemplateID $templateId -Scope $scope -Frequency 'Daily' -StartTime '06:00' -IsEnabled
        Update-SchedulesGrid
        Update-DocumentationGeneratorStatistics
        [System.Windows.MessageBox]::Show("Schedule created. Next run: $($schedule.NextRunTime.ToString('yyyy-MM-dd HH:mm'))", 'Success', 'OK', 'Information')
    }
    catch {
        [System.Windows.MessageBox]::Show("Failed to create schedule: $_", 'Error', 'OK', 'Error')
    }
}

function Set-SelectedScheduleEnabled {
    <#
    .SYNOPSIS
        Enables or disables the selected schedule.
    #>
    param(
        [Parameter(Mandatory)]
        [bool]$Enabled
    )

    $selected = $script:SchedulesGrid.SelectedItem
    if (-not $selected) {
        [System.Windows.MessageBox]::Show('Please select a schedule.', 'No Selection', 'OK', 'Warning')
        return
    }

    try {
        $null = Set-DocumentScheduleEnabled -ScheduleID $selected.ScheduleID -IsEnabled $Enabled
        Update-SchedulesGrid
        Update-DocumentationGeneratorStatistics
    }
    catch {
        [System.Windows.MessageBox]::Show("Failed to update schedule: $_", 'Error', 'OK', 'Error')
    }
}

function Remove-SelectedSchedule {
    <#
    .SYNOPSIS
        Removes the selected schedule.
    #>
    $selected = $script:SchedulesGrid.SelectedItem
    if (-not $selected) {
        [System.Windows.MessageBox]::Show('Please select a schedule to delete.', 'No Selection', 'OK', 'Warning')
        return
    }

    $result = [System.Windows.MessageBox]::Show("Delete this schedule?", 'Confirm Delete', 'YesNo', 'Question')
    if ($result -eq 'Yes') {
        try {
            Remove-DocumentSchedule -ScheduleID $selected.ScheduleID
            Update-SchedulesGrid
            Update-DocumentationGeneratorStatistics
        }
        catch {
            [System.Windows.MessageBox]::Show("Failed to delete schedule: $_", 'Error', 'OK', 'Error')
        }
    }
}

#endregion

#region Export Functions

function Update-ExportDocumentCombo {
    <#
    .SYNOPSIS
        Updates the document dropdown in the Export tab.
    #>
    if (-not $script:ExportDocumentCombo) { return }

    try {
        $documents = Get-GeneratedDocument | Sort-Object GeneratedDate -Descending
        $script:ExportDocumentCombo.Items.Clear()

        foreach ($doc in $documents) {
            $item = New-Object System.Windows.Controls.ComboBoxItem
            $item.Content = "$($doc.Title) ($($doc.DocumentID))"
            $item.Tag = $doc.DocumentID
            $script:ExportDocumentCombo.Items.Add($item) | Out-Null
        }

        if ($script:ExportDocumentCombo.Items.Count -gt 0) {
            $script:ExportDocumentCombo.SelectedIndex = 0
        }
    }
    catch {
        Write-Warning "Failed to update export document combo: $_"
    }
}

function Update-ExportPreview {
    <#
    .SYNOPSIS
        Updates the export path suggestion based on selection.
    #>
    if (-not $script:ExportDocumentCombo.SelectedItem -or -not $script:ExportPathBox) { return }

    try {
        $docId = $script:ExportDocumentCombo.SelectedItem.Tag
        $doc = Get-GeneratedDocument -DocumentID $docId

        if ($doc) {
            $format = 'md'
            if ($script:ExportFormatCombo -and $script:ExportFormatCombo.SelectedItem) {
                $formatText = ($script:ExportFormatCombo.SelectedItem).Content
                if ($formatText -match 'HTML') { $format = 'html' }
                elseif ($formatText -match 'Text') { $format = 'txt' }
                elseif ($formatText -match 'CSV') { $format = 'csv' }
            }

            $fileName = "$($doc.Title -replace '[^\w\-]', '_').$format"
            $script:ExportPathBox.Text = Join-Path $env:TEMP $fileName
        }
    }
    catch {
        Write-Warning "Failed to update export preview: $_"
    }
}

function Browse-ExportPath {
    <#
    .SYNOPSIS
        Opens a file browser for export path selection.
    #>
    $dialog = New-Object Microsoft.Win32.SaveFileDialog
    $dialog.Filter = "Markdown files (*.md)|*.md|HTML files (*.html)|*.html|Text files (*.txt)|*.txt|CSV files (*.csv)|*.csv|All files (*.*)|*.*"
    $dialog.InitialDirectory = $env:TEMP

    if ($dialog.ShowDialog()) {
        $script:ExportPathBox.Text = $dialog.FileName
    }
}

function Invoke-ExportDocument {
    <#
    .SYNOPSIS
        Exports the selected document to the specified path.
    #>
    if (-not $script:ExportDocumentCombo.SelectedItem) {
        [System.Windows.MessageBox]::Show('Please select a document to export.', 'No Selection', 'OK', 'Warning')
        return
    }

    if (-not $script:ExportPathBox.Text) {
        [System.Windows.MessageBox]::Show('Please specify an export path.', 'No Path', 'OK', 'Warning')
        return
    }

    $docId = $script:ExportDocumentCombo.SelectedItem.Tag
    $outputPath = $script:ExportPathBox.Text

    # Determine format
    $format = 'Markdown'
    if ($script:ExportFormatCombo -and $script:ExportFormatCombo.SelectedItem) {
        $formatText = ($script:ExportFormatCombo.SelectedItem).Content
        if ($formatText -match 'HTML') { $format = 'HTML' }
        elseif ($formatText -match 'Text') { $format = 'Text' }
        elseif ($formatText -match 'CSV') { $format = 'CSV' }
    }

    try {
        $doc = Get-GeneratedDocument -DocumentID $docId
        if (-not $doc) {
            throw "Document not found"
        }

        $result = Export-Document -Document $doc -Format $format -OutputPath $outputPath
        Update-HistoryGrid

        $openResult = [System.Windows.MessageBox]::Show("Document exported to:`n$result`n`nOpen file?", 'Export Complete', 'YesNo', 'Information')
        if ($openResult -eq 'Yes') {
            Start-Process $result
        }
    }
    catch {
        [System.Windows.MessageBox]::Show("Export failed: $_", 'Error', 'OK', 'Error')
    }
}

#endregion

#region History Functions

function Update-HistoryGrid {
    <#
    .SYNOPSIS
        Updates the history grid.
    #>
    if (-not $script:HistoryGrid) { return }

    try {
        $history = Get-DocumentHistory | Select-Object -First 100
        $script:HistoryGrid.ItemsSource = @($history)

        # Also update export history grid if present
        if ($script:ExportHistoryGrid) {
            $exportHistory = $history | Where-Object { $_.Action -eq 'Exported' } | Select-Object -First 20
            $script:ExportHistoryGrid.ItemsSource = @($exportHistory)
        }
    }
    catch {
        Write-Warning "Failed to update history grid: $_"
    }
}

#endregion

#region Dialog Helpers

function Show-InputDialog {
    <#
    .SYNOPSIS
        Shows a simple input dialog and returns the user's input.
    #>
    param(
        [string]$Title = 'Input',
        [string]$Prompt = 'Enter value:',
        [string]$Default = ''
    )

    # Simple input using InputBox
    Add-Type -AssemblyName Microsoft.VisualBasic
    return [Microsoft.VisualBasic.Interaction]::InputBox($Prompt, $Title, $Default)
}

function Show-TextDialog {
    <#
    .SYNOPSIS
        Shows a text viewer dialog.
    #>
    param(
        [string]$Title = 'View',
        [string]$Content = ''
    )

    $window = New-Object System.Windows.Window
    $window.Title = $Title
    $window.Width = 800
    $window.Height = 600
    $window.WindowStartupLocation = 'CenterScreen'

    $textBox = New-Object System.Windows.Controls.TextBox
    $textBox.Text = $Content
    $textBox.IsReadOnly = $true
    $textBox.AcceptsReturn = $true
    $textBox.TextWrapping = 'Wrap'
    $textBox.VerticalScrollBarVisibility = 'Auto'
    $textBox.HorizontalScrollBarVisibility = 'Auto'
    $textBox.FontFamily = New-Object System.Windows.Media.FontFamily('Consolas')
    $textBox.FontSize = 12

    $window.Content = $textBox
    $window.ShowDialog() | Out-Null
}

function Show-TextInputDialog {
    <#
    .SYNOPSIS
        Shows a text editor dialog and returns the edited content.
    #>
    param(
        [string]$Title = 'Edit',
        [string]$Content = ''
    )

    $window = New-Object System.Windows.Window
    $window.Title = $Title
    $window.Width = 800
    $window.Height = 600
    $window.WindowStartupLocation = 'CenterScreen'

    $grid = New-Object System.Windows.Controls.Grid
    $grid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition))
    $grid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = 'Auto' }))

    $textBox = New-Object System.Windows.Controls.TextBox
    $textBox.Text = $Content
    $textBox.AcceptsReturn = $true
    $textBox.TextWrapping = 'Wrap'
    $textBox.VerticalScrollBarVisibility = 'Auto'
    $textBox.HorizontalScrollBarVisibility = 'Auto'
    $textBox.FontFamily = New-Object System.Windows.Media.FontFamily('Consolas')
    $textBox.FontSize = 12
    [System.Windows.Controls.Grid]::SetRow($textBox, 0)

    $buttonPanel = New-Object System.Windows.Controls.StackPanel
    $buttonPanel.Orientation = 'Horizontal'
    $buttonPanel.HorizontalAlignment = 'Right'
    $buttonPanel.Margin = '5'
    [System.Windows.Controls.Grid]::SetRow($buttonPanel, 1)

    $okButton = New-Object System.Windows.Controls.Button
    $okButton.Content = 'OK'
    $okButton.Width = 80
    $okButton.Margin = '5'
    $okButton.Add_Click({
        $window.Tag = $textBox.Text
        $window.Close()
    })

    $cancelButton = New-Object System.Windows.Controls.Button
    $cancelButton.Content = 'Cancel'
    $cancelButton.Width = 80
    $cancelButton.Margin = '5'
    $cancelButton.Add_Click({ $window.Close() })

    $buttonPanel.Children.Add($okButton) | Out-Null
    $buttonPanel.Children.Add($cancelButton) | Out-Null

    $grid.Children.Add($textBox) | Out-Null
    $grid.Children.Add($buttonPanel) | Out-Null

    $window.Content = $grid
    $window.ShowDialog() | Out-Null

    return $window.Tag
}

#endregion

# Export functions
Export-ModuleMember -Function @(
    'Initialize-DocumentationGeneratorView'
)
