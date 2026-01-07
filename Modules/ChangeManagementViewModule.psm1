#Requires -Version 5.1
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    View module for the Change Management interface.

.DESCRIPTION
    Provides the view wiring for ChangeManagementView.xaml, connecting UI controls
    to the ChangeManagementModule functions for change requests, maintenance windows,
    templates, and history tracking.

.NOTES
    Plan Z - Change Management & Maintenance Windows
#>

function New-ChangeManagementView {
    <#
    .SYNOPSIS
        Creates and initializes the Change Management view.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][System.Windows.Window]$Window,
        [Parameter(Mandatory=$true)][string]$ScriptDir
    )

    # Load XAML using ViewCompositionModule pattern
    $view = ViewCompositionModule\Set-StView -Window $Window -ScriptDir $ScriptDir `
        -ViewName 'ChangeManagementView' -HostControlName 'ChangeManagementHost' `
        -GlobalVariableName 'changeManagementView'
    if (-not $view) {
        return $null
    }

    # Initialize controls
    Initialize-ChangeManagementControls -View $view

    # Wire up event handlers
    Register-ChangeManagementEventHandlers -View $view

    # Load initial data
    Update-ChangeManagementView -View $view

    return $view
}

function Initialize-ChangeManagementControls {
    <#
    .SYNOPSIS
        Initializes dropdown controls with default values.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $View
    )

    # Initialize status filter dropdown
    $statusDropdown = $View.FindName('StatusFilterDropdown')
    if ($statusDropdown) {
        $statusDropdown.Items.Clear()
        [void]$statusDropdown.Items.Add('All Status')
        [void]$statusDropdown.Items.Add('Draft')
        [void]$statusDropdown.Items.Add('Submitted')
        [void]$statusDropdown.Items.Add('Approved')
        [void]$statusDropdown.Items.Add('InProgress')
        [void]$statusDropdown.Items.Add('Completed')
        [void]$statusDropdown.Items.Add('Failed')
        [void]$statusDropdown.Items.Add('RolledBack')
        [void]$statusDropdown.Items.Add('Cancelled')
        $statusDropdown.SelectedIndex = 0
    }

    # Initialize type filter dropdown
    $typeDropdown = $View.FindName('TypeFilterDropdown')
    if ($typeDropdown) {
        $typeDropdown.Items.Clear()
        [void]$typeDropdown.Items.Add('All Types')
        [void]$typeDropdown.Items.Add('Standard')
        [void]$typeDropdown.Items.Add('Normal')
        [void]$typeDropdown.Items.Add('Emergency')
        $typeDropdown.SelectedIndex = 0
    }

    # Initialize history period dropdown
    $historyPeriodDropdown = $View.FindName('HistoryPeriodDropdown')
    if ($historyPeriodDropdown) {
        $historyPeriodDropdown.Items.Clear()
        [void]$historyPeriodDropdown.Items.Add('Last 7 Days')
        [void]$historyPeriodDropdown.Items.Add('Last 30 Days')
        [void]$historyPeriodDropdown.Items.Add('Last 90 Days')
        [void]$historyPeriodDropdown.Items.Add('All Time')
        $historyPeriodDropdown.SelectedIndex = 0
    }

    # Initialize stats period dropdown
    $statsPeriodDropdown = $View.FindName('StatsPeriodDropdown')
    if ($statsPeriodDropdown) {
        $statsPeriodDropdown.Items.Clear()
        [void]$statsPeriodDropdown.Items.Add('Last Week')
        [void]$statsPeriodDropdown.Items.Add('Last Month')
        [void]$statsPeriodDropdown.Items.Add('Last Quarter')
        [void]$statsPeriodDropdown.Items.Add('Last Year')
        [void]$statsPeriodDropdown.Items.Add('All Time')
        $statsPeriodDropdown.SelectedIndex = 1
    }
}

function Register-ChangeManagementEventHandlers {
    <#
    .SYNOPSIS
        Registers event handlers for view controls.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $View
    )

    # New Change button
    $newChangeButton = $View.FindName('NewChangeButton')
    if ($newChangeButton) {
        $newChangeButton.Add_Click({
            Show-NewChangeDialog -View $View
        }.GetNewClosure())
    }

    # Edit Change button
    $editButton = $View.FindName('EditChangeButton')
    if ($editButton) {
        $editButton.Add_Click({
            $grid = $View.FindName('ChangesGrid')
            if ($grid -and $grid.SelectedItem) {
                Show-EditChangeDialog -View $View -Change $grid.SelectedItem
            }
        }.GetNewClosure())
    }

    # Double-click on grid row to edit
    $changesGrid = $View.FindName('ChangesGrid')
    if ($changesGrid) {
        $changesGrid.Add_MouseDoubleClick({
            param($sender, $e)
            if ($sender.SelectedItem) {
                Show-EditChangeDialog -View $View -Change $sender.SelectedItem
            }
        }.GetNewClosure())
    }

    # Submit Change button
    $submitButton = $View.FindName('SubmitChangeButton')
    if ($submitButton) {
        $submitButton.Add_Click({
            $grid = $View.FindName('ChangesGrid')
            if ($grid -and $grid.SelectedItem) {
                $change = $grid.SelectedItem
                if ($change.Status -eq 'Draft') {
                    $null = Update-ChangeRequest -ChangeID $change.ChangeID -Status 'Submitted'
                    Update-ChangeManagementView -View $View
                    Set-StatusText -View $View -Text "Change $($change.ChangeID) submitted for approval"
                }
            }
        }.GetNewClosure())
    }

    # Approve Change button
    $approveButton = $View.FindName('ApproveChangeButton')
    if ($approveButton) {
        $approveButton.Add_Click({
            $grid = $View.FindName('ChangesGrid')
            if ($grid -and $grid.SelectedItem) {
                $change = $grid.SelectedItem
                if ($change.Status -eq 'Submitted') {
                    $null = Update-ChangeRequest -ChangeID $change.ChangeID -Status 'Approved' -ApprovedBy $env:USERNAME
                    Update-ChangeManagementView -View $View
                    Set-StatusText -View $View -Text "Change $($change.ChangeID) approved"
                }
            }
        }.GetNewClosure())
    }

    # Start Change button
    $startButton = $View.FindName('StartChangeButton')
    if ($startButton) {
        $startButton.Add_Click({
            $grid = $View.FindName('ChangesGrid')
            if ($grid -and $grid.SelectedItem) {
                $change = $grid.SelectedItem
                if ($change.Status -in @('Draft', 'Approved')) {
                    $null = Start-Change -ChangeID $change.ChangeID -ImplementedBy $env:USERNAME
                    Update-ChangeManagementView -View $View
                    Set-StatusText -View $View -Text "Change $($change.ChangeID) execution started"
                }
            }
        }.GetNewClosure())
    }

    # Complete Change button
    $completeButton = $View.FindName('CompleteChangeButton')
    if ($completeButton) {
        $completeButton.Add_Click({
            $grid = $View.FindName('ChangesGrid')
            if ($grid -and $grid.SelectedItem) {
                $change = $grid.SelectedItem
                if ($change.Status -eq 'InProgress') {
                    $null = Complete-Change -ChangeID $change.ChangeID
                    Update-ChangeManagementView -View $View
                    Set-StatusText -View $View -Text "Change $($change.ChangeID) completed successfully"
                }
            }
        }.GetNewClosure())
    }

    # Rollback Change button
    $rollbackButton = $View.FindName('RollbackChangeButton')
    if ($rollbackButton) {
        $rollbackButton.Add_Click({
            $grid = $View.FindName('ChangesGrid')
            if ($grid -and $grid.SelectedItem) {
                $change = $grid.SelectedItem
                if ($change.Status -eq 'InProgress') {
                    $null = Invoke-ChangeRollback -ChangeID $change.ChangeID -RollbackReason 'Manual rollback initiated'
                    Update-ChangeManagementView -View $View
                    Set-StatusText -View $View -Text "Change $($change.ChangeID) rolled back"
                }
            }
        }.GetNewClosure())
    }

    # Filter dropdowns
    $statusDropdown = $View.FindName('StatusFilterDropdown')
    if ($statusDropdown) {
        $statusDropdown.Add_SelectionChanged({
            Update-ChangesGrid -View $View
        }.GetNewClosure())
    }

    $typeDropdown = $View.FindName('TypeFilterDropdown')
    if ($typeDropdown) {
        $typeDropdown.Add_SelectionChanged({
            Update-ChangesGrid -View $View
        }.GetNewClosure())
    }

    # Search box
    $searchBox = $View.FindName('SearchBox')
    if ($searchBox) {
        $searchBox.Add_TextChanged({
            Update-ChangesGrid -View $View
        }.GetNewClosure())
    }

    # Clear Filter button
    $clearFilterButton = $View.FindName('ClearFilterButton')
    if ($clearFilterButton) {
        $clearFilterButton.Add_Click({
            $statusDropdown = $View.FindName('StatusFilterDropdown')
            $typeDropdown = $View.FindName('TypeFilterDropdown')
            $searchBox = $View.FindName('SearchBox')
            if ($statusDropdown) { $statusDropdown.SelectedIndex = 0 }
            if ($typeDropdown) { $typeDropdown.SelectedIndex = 0 }
            if ($searchBox) { $searchBox.Text = '' }
            Update-ChangesGrid -View $View
        }.GetNewClosure())
    }

    # Refresh button
    $refreshButton = $View.FindName('RefreshButton')
    if ($refreshButton) {
        $refreshButton.Add_Click({
            Update-ChangeManagementView -View $View
            Set-StatusText -View $View -Text "Data refreshed"
        }.GetNewClosure())
    }

    # Changes grid selection
    $changesGrid = $View.FindName('ChangesGrid')
    if ($changesGrid) {
        $changesGrid.Add_SelectionChanged({
            param($sender, $e)
            Update-ChangeDetails -View $View
        }.GetNewClosure())
    }

    # Maintenance window buttons
    $newWindowButton = $View.FindName('NewMaintenanceWindowButton')
    if ($newWindowButton) {
        $newWindowButton.Add_Click({
            Show-NewMaintenanceWindowDialog -View $View
        }.GetNewClosure())
    }

    $deleteWindowButton = $View.FindName('DeleteMaintenanceWindowButton')
    if ($deleteWindowButton) {
        $deleteWindowButton.Add_Click({
            $grid = $View.FindName('MaintenanceWindowsGrid')
            if ($grid -and $grid.SelectedItem) {
                $window = $grid.SelectedItem
                $result = [System.Windows.MessageBox]::Show(
                    "Delete maintenance window '$($window.WindowName)'?",
                    'Confirm Delete',
                    [System.Windows.MessageBoxButton]::YesNo,
                    [System.Windows.MessageBoxImage]::Question
                )
                if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
                    Remove-MaintenanceWindow -WindowID $window.WindowID
                    Update-MaintenanceWindowsGrid -View $View
                    Set-StatusText -View $View -Text "Maintenance window deleted"
                }
            }
        }.GetNewClosure())
    }

    # Maintenance window checkboxes
    $showPastCheckbox = $View.FindName('ShowPastWindowsCheckbox')
    if ($showPastCheckbox) {
        $showPastCheckbox.Add_Checked({ Update-MaintenanceWindowsGrid -View $View }.GetNewClosure())
        $showPastCheckbox.Add_Unchecked({ Update-MaintenanceWindowsGrid -View $View }.GetNewClosure())
    }

    $blackoutOnlyCheckbox = $View.FindName('BlackoutOnlyCheckbox')
    if ($blackoutOnlyCheckbox) {
        $blackoutOnlyCheckbox.Add_Checked({ Update-MaintenanceWindowsGrid -View $View }.GetNewClosure())
        $blackoutOnlyCheckbox.Add_Unchecked({ Update-MaintenanceWindowsGrid -View $View }.GetNewClosure())
    }

    # Templates list selection
    $templatesList = $View.FindName('TemplatesList')
    if ($templatesList) {
        $templatesList.Add_SelectionChanged({
            param($sender, $e)
            Update-TemplateDetails -View $View
        }.GetNewClosure())
    }

    # Use Template button
    $useTemplateButton = $View.FindName('UseTemplateButton')
    if ($useTemplateButton) {
        $useTemplateButton.Add_Click({
            $templatesList = $View.FindName('TemplatesList')
            if ($templatesList -and $templatesList.SelectedItem) {
                Show-NewChangeDialog -View $View -TemplateID $templatesList.SelectedItem
            }
        }.GetNewClosure())
    }

    # History filter
    $filterHistoryButton = $View.FindName('FilterHistoryButton')
    if ($filterHistoryButton) {
        $filterHistoryButton.Add_Click({
            Update-HistoryGrid -View $View
        }.GetNewClosure())
    }

    $clearHistoryFilterButton = $View.FindName('ClearHistoryFilterButton')
    if ($clearHistoryFilterButton) {
        $clearHistoryFilterButton.Add_Click({
            $filterBox = $View.FindName('HistoryChangeIdFilter')
            if ($filterBox) { $filterBox.Text = '' }
            Update-HistoryGrid -View $View
        }.GetNewClosure())
    }

    # Stats refresh
    $refreshStatsButton = $View.FindName('RefreshStatsButton')
    if ($refreshStatsButton) {
        $refreshStatsButton.Add_Click({
            Update-StatisticsView -View $View
        }.GetNewClosure())
    }

    $statsPeriodDropdown = $View.FindName('StatsPeriodDropdown')
    if ($statsPeriodDropdown) {
        $statsPeriodDropdown.Add_SelectionChanged({
            Update-StatisticsView -View $View
        }.GetNewClosure())
    }
}

function Update-ChangeManagementView {
    <#
    .SYNOPSIS
        Updates all view components with current data.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $View
    )

    Update-SummaryCards -View $View
    Update-ChangesGrid -View $View
    Update-MaintenanceWindowsGrid -View $View
    Update-TemplatesList -View $View
    Update-HistoryGrid -View $View
    Update-StatisticsView -View $View

    $lastRefreshText = $View.FindName('LastRefreshText')
    if ($lastRefreshText) {
        $lastRefreshText.Text = "Last refresh: $(Get-Date -Format 'HH:mm:ss')"
    }
}

function Update-SummaryCards {
    <#
    .SYNOPSIS
        Updates the summary cards with current statistics.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $View
    )

    $changes = @(Get-ChangeRequest)
    $windows = @(Get-MaintenanceWindow)

    # Total Changes
    $totalChangesText = $View.FindName('TotalChangesCount')
    if ($totalChangesText) {
        $totalChangesText.Text = $changes.Count.ToString()
    }

    # In Progress
    $inProgressText = $View.FindName('InProgressCount')
    if ($inProgressText) {
        $inProgress = @($changes | Where-Object { $_.Status -eq 'InProgress' }).Count
        $inProgressText.Text = $inProgress.ToString()
    }

    # Pending Approval
    $pendingText = $View.FindName('PendingApprovalCount')
    if ($pendingText) {
        $pending = @($changes | Where-Object { $_.Status -eq 'Submitted' }).Count
        $pendingText.Text = $pending.ToString()
    }

    # Maintenance Windows
    $windowsText = $View.FindName('MaintenanceWindowsCount')
    if ($windowsText) {
        $windowsText.Text = $windows.Count.ToString()
    }

    # Success Rate
    $successRateText = $View.FindName('SuccessRateText')
    if ($successRateText) {
        $stats = Get-ChangeStatistics -Period 'LastMonth'
        if ($stats) {
            $successRateText.Text = "$($stats.SuccessRate)%"
        }
    }
}

function Update-ChangesGrid {
    <#
    .SYNOPSIS
        Updates the changes grid with filtered data.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $View
    )

    $changesGrid = $View.FindName('ChangesGrid')
    if (-not $changesGrid) { return }

    $changes = @(Get-ChangeRequest)

    # Apply status filter
    $statusDropdown = $View.FindName('StatusFilterDropdown')
    if ($statusDropdown -and $statusDropdown.SelectedIndex -gt 0) {
        $selectedStatus = $statusDropdown.SelectedItem.ToString()
        $changes = @($changes | Where-Object { $_.Status -eq $selectedStatus })
    }

    # Apply type filter
    $typeDropdown = $View.FindName('TypeFilterDropdown')
    if ($typeDropdown -and $typeDropdown.SelectedIndex -gt 0) {
        $selectedType = $typeDropdown.SelectedItem.ToString()
        $changes = @($changes | Where-Object { $_.ChangeType -eq $selectedType })
    }

    # Apply search filter
    $searchBox = $View.FindName('SearchBox')
    if ($searchBox -and $searchBox.Text) {
        $searchText = $searchBox.Text.ToLower()
        $changes = @($changes | Where-Object {
            $_.Title.ToLower().Contains($searchText) -or
            $_.ChangeID.ToLower().Contains($searchText)
        })
    }

    # Sort by created date descending
    $changes = @($changes | Sort-Object CreatedDate -Descending)

    $changesGrid.ItemsSource = $changes

    Set-StatusText -View $View -Text "$($changes.Count) change request(s) displayed"
}

function Update-ChangeDetails {
    <#
    .SYNOPSIS
        Updates the change details panel for the selected change.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $View
    )

    $changesGrid = $View.FindName('ChangesGrid')
    if (-not $changesGrid -or -not $changesGrid.SelectedItem) {
        Clear-ChangeDetails -View $View
        return
    }

    $change = $changesGrid.SelectedItem

    # Update detail fields
    $detailChangeID = $View.FindName('DetailChangeID')
    if ($detailChangeID) { $detailChangeID.Text = $change.ChangeID }

    $detailTitle = $View.FindName('DetailTitle')
    if ($detailTitle) { $detailTitle.Text = $change.Title }

    $detailDescription = $View.FindName('DetailDescription')
    if ($detailDescription) { $detailDescription.Text = if ($change.Description) { $change.Description } else { '--' } }

    $detailStatus = $View.FindName('DetailStatus')
    if ($detailStatus) { $detailStatus.Text = $change.Status }

    $detailTypeRisk = $View.FindName('DetailTypeRisk')
    if ($detailTypeRisk) { $detailTypeRisk.Text = "$($change.ChangeType) / $($change.RiskLevel)" }

    $detailRequestedBy = $View.FindName('DetailRequestedBy')
    if ($detailRequestedBy) { $detailRequestedBy.Text = if ($change.RequestedBy) { $change.RequestedBy } else { '--' } }

    $detailApprovedBy = $View.FindName('DetailApprovedBy')
    if ($detailApprovedBy) { $detailApprovedBy.Text = if ($change.ApprovedBy) { $change.ApprovedBy } else { '--' } }

    $detailPlannedWindow = $View.FindName('DetailPlannedWindow')
    if ($detailPlannedWindow) {
        if ($change.PlannedStart -and $change.PlannedEnd) {
            $detailPlannedWindow.Text = "$($change.PlannedStart.ToString('yyyy-MM-dd HH:mm')) - $($change.PlannedEnd.ToString('HH:mm'))"
        } else {
            $detailPlannedWindow.Text = '--'
        }
    }

    $detailAffectedDevices = $View.FindName('DetailAffectedDevices')
    if ($detailAffectedDevices) {
        if ($change.AffectedDevices -and $change.AffectedDevices.Count -gt 0) {
            $detailAffectedDevices.Text = ($change.AffectedDevices -join ', ')
        } else {
            $detailAffectedDevices.Text = '--'
        }
    }

    # Load steps
    $stepsList = $View.FindName('StepsList')
    if ($stepsList) {
        $stepsList.Items.Clear()
        $steps = @(Get-ChangeStep -ChangeID $change.ChangeID)
        foreach ($step in $steps) {
            $statusIcon = switch ($step.Status) {
                'Completed' { '[OK]' }
                'InProgress' { '[>>]' }
                'Failed' { '[X]' }
                'Skipped' { '[--]' }
                default { '[ ]' }
            }
            [void]$stepsList.Items.Add("$statusIcon $($step.StepNumber). $($step.Description)")
        }
    }

    $detailNotes = $View.FindName('DetailNotes')
    if ($detailNotes) { $detailNotes.Text = if ($change.Notes) { $change.Notes } else { '--' } }
}

function Clear-ChangeDetails {
    <#
    .SYNOPSIS
        Clears the change details panel.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $View
    )

    $fields = @('DetailChangeID', 'DetailTitle', 'DetailDescription', 'DetailStatus',
                'DetailTypeRisk', 'DetailRequestedBy', 'DetailApprovedBy',
                'DetailPlannedWindow', 'DetailAffectedDevices', 'DetailNotes')

    foreach ($field in $fields) {
        $control = $View.FindName($field)
        if ($control) { $control.Text = '--' }
    }

    $stepsList = $View.FindName('StepsList')
    if ($stepsList) { $stepsList.Items.Clear() }
}

function Update-MaintenanceWindowsGrid {
    <#
    .SYNOPSIS
        Updates the maintenance windows grid.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $View
    )

    $windowsGrid = $View.FindName('MaintenanceWindowsGrid')
    if (-not $windowsGrid) { return }

    $showPastCheckbox = $View.FindName('ShowPastWindowsCheckbox')
    $blackoutOnlyCheckbox = $View.FindName('BlackoutOnlyCheckbox')

    $includePast = $showPastCheckbox -and $showPastCheckbox.IsChecked
    $blackoutsOnly = $blackoutOnlyCheckbox -and $blackoutOnlyCheckbox.IsChecked

    $params = @{}
    if ($includePast) { $params['IncludePast'] = $true }
    if ($blackoutsOnly) { $params['BlackoutsOnly'] = $true }

    $windows = @(Get-MaintenanceWindow @params)
    $windowsGrid.ItemsSource = $windows
}

function Update-TemplatesList {
    <#
    .SYNOPSIS
        Updates the templates list.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $View
    )

    $templatesList = $View.FindName('TemplatesList')
    if (-not $templatesList) { return }

    $templatesList.Items.Clear()
    $templates = @(Get-ChangeTemplate)

    foreach ($template in $templates) {
        [void]$templatesList.Items.Add($template.TemplateID)
    }
}

function Update-TemplateDetails {
    <#
    .SYNOPSIS
        Updates the template details panel.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $View
    )

    $templatesList = $View.FindName('TemplatesList')
    if (-not $templatesList -or -not $templatesList.SelectedItem) {
        return
    }

    $templateId = $templatesList.SelectedItem
    $template = Get-ChangeTemplate -TemplateID $templateId

    if (-not $template) { return }

    $templateName = $View.FindName('TemplateName')
    if ($templateName) { $templateName.Text = $template.Name }

    $templateDescription = $View.FindName('TemplateDescription')
    if ($templateDescription) { $templateDescription.Text = $template.Description }

    $templateType = $View.FindName('TemplateType')
    if ($templateType) { $templateType.Text = $template.ChangeType }

    $templateRisk = $View.FindName('TemplateRisk')
    if ($templateRisk) { $templateRisk.Text = $template.DefaultRiskLevel }

    $templateDuration = $View.FindName('TemplateDuration')
    if ($templateDuration) { $templateDuration.Text = "$($template.EstimatedDuration) minutes" }

    $stepsList = $View.FindName('TemplateStepsList')
    if ($stepsList) {
        $stepsList.Items.Clear()
        if ($template.Steps) {
            foreach ($step in $template.Steps) {
                [void]$stepsList.Items.Add("$($step.StepNumber). $($step.Description)")
            }
        }
    }

    $rollbackList = $View.FindName('TemplateRollbackList')
    if ($rollbackList) {
        $rollbackList.Items.Clear()
        if ($template.RollbackSteps) {
            foreach ($step in $template.RollbackSteps) {
                [void]$rollbackList.Items.Add($step)
            }
        }
    }
}

function Update-HistoryGrid {
    <#
    .SYNOPSIS
        Updates the history grid.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $View
    )

    $historyGrid = $View.FindName('HistoryGrid')
    if (-not $historyGrid) { return }

    $filterBox = $View.FindName('HistoryChangeIdFilter')
    $changeIdFilter = if ($filterBox -and $filterBox.Text) { $filterBox.Text } else { $null }

    if ($changeIdFilter) {
        $history = @(Get-ChangeHistory -ChangeID $changeIdFilter)
    } else {
        $history = @(Get-ChangeHistory)
    }

    # Apply period filter
    $periodDropdown = $View.FindName('HistoryPeriodDropdown')
    if ($periodDropdown -and $periodDropdown.SelectedIndex -ge 0) {
        $now = Get-Date
        $cutoff = switch ($periodDropdown.SelectedIndex) {
            0 { $now.AddDays(-7) }
            1 { $now.AddDays(-30) }
            2 { $now.AddDays(-90) }
            default { [DateTime]::MinValue }
        }
        $history = @($history | Where-Object { $_.Timestamp -ge $cutoff })
    }

    $historyGrid.ItemsSource = $history
}

function Update-StatisticsView {
    <#
    .SYNOPSIS
        Updates the statistics view.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $View
    )

    $periodDropdown = $View.FindName('StatsPeriodDropdown')
    $period = 'LastMonth'
    if ($periodDropdown -and $periodDropdown.SelectedIndex -ge 0) {
        $period = switch ($periodDropdown.SelectedIndex) {
            0 { 'LastWeek' }
            1 { 'LastMonth' }
            2 { 'LastQuarter' }
            3 { 'LastYear' }
            4 { 'All' }
        }
    }

    $stats = Get-ChangeStatistics -Period $period

    # Update summary stats
    $totalChanges = $View.FindName('StatsTotalChanges')
    if ($totalChanges) { $totalChanges.Text = $stats.TotalChanges.ToString() }

    $completed = $View.FindName('StatsCompleted')
    if ($completed) { $completed.Text = $stats.Completed.ToString() }

    $failed = $View.FindName('StatsFailed')
    if ($failed) { $failed.Text = $stats.Failed.ToString() }

    $rolledBack = $View.FindName('StatsRolledBack')
    if ($rolledBack) { $rolledBack.Text = $stats.RolledBack.ToString() }

    $successRate = $View.FindName('StatsSuccessRate')
    if ($successRate) { $successRate.Text = "$($stats.SuccessRate)%" }

    # Update by type list
    $byTypeList = $View.FindName('StatsByTypeList')
    if ($byTypeList) {
        $byTypeList.Items.Clear()
        foreach ($key in $stats.ByType.Keys) {
            [void]$byTypeList.Items.Add("$key`: $($stats.ByType[$key])")
        }
    }

    # Update by risk list
    $byRiskList = $View.FindName('StatsByRiskList')
    if ($byRiskList) {
        $byRiskList.Items.Clear()
        foreach ($key in $stats.ByRisk.Keys) {
            [void]$byRiskList.Items.Add("$key`: $($stats.ByRisk[$key])")
        }
    }

    # Update by status list
    $byStatusList = $View.FindName('StatsByStatusList')
    if ($byStatusList) {
        $byStatusList.Items.Clear()
        foreach ($key in $stats.ByStatus.Keys) {
            [void]$byStatusList.Items.Add("$key`: $($stats.ByStatus[$key])")
        }
    }
}

function Set-StatusText {
    <#
    .SYNOPSIS
        Sets the status bar text.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $View,

        [Parameter(Mandatory)]
        [string]$Text
    )

    $statusText = $View.FindName('StatusText')
    if ($statusText) {
        $statusText.Text = $Text
    }
}

function Show-NewChangeDialog {
    <#
    .SYNOPSIS
        Shows dialog to create a new change request.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $View,

        [Parameter()]
        [string]$TemplateID
    )

    # Simple input dialog - in a real implementation this would be a proper WPF dialog
    $title = Read-Host "Enter change title"
    if (-not $title) { return }

    $description = Read-Host "Enter change description"

    $params = @{
        Title = $title
        Description = $description
        RequestedBy = $env:USERNAME
    }

    if ($TemplateID) {
        $params['Template'] = $TemplateID
    }

    $change = New-ChangeRequest @params
    Update-ChangeManagementView -View $View
    Set-StatusText -View $View -Text "Change $($change.ChangeID) created"
}

function Show-EditChangeDialog {
    <#
    .SYNOPSIS
        Shows dialog to edit an existing change request.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $View,

        [Parameter(Mandatory)]
        $Change
    )

    # Simple edit - in a real implementation this would be a proper WPF dialog
    $newTitle = Read-Host "Edit title (current: $($Change.Title))"
    if ($newTitle) {
        $null = Update-ChangeRequest -ChangeID $Change.ChangeID -Title $newTitle
        Update-ChangeManagementView -View $View
        Set-StatusText -View $View -Text "Change $($Change.ChangeID) updated"
    }
}

function Show-NewMaintenanceWindowDialog {
    <#
    .SYNOPSIS
        Shows dialog to create a new maintenance window.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $View
    )

    # Simple input dialog - in a real implementation this would be a proper WPF dialog
    $title = Read-Host "Enter window title"
    if (-not $title) { return }

    $startStr = Read-Host "Enter start time (yyyy-MM-dd HH:mm)"
    $endStr = Read-Host "Enter end time (yyyy-MM-dd HH:mm)"

    try {
        $startTime = [DateTime]::ParseExact($startStr, 'yyyy-MM-dd HH:mm', $null)
        $endTime = [DateTime]::ParseExact($endStr, 'yyyy-MM-dd HH:mm', $null)

        $window = New-MaintenanceWindow -Title $title -StartTime $startTime -EndTime $endTime -CreatedBy $env:USERNAME
        Update-MaintenanceWindowsGrid -View $View
        Set-StatusText -View $View -Text "Maintenance window created"
    }
    catch {
        Set-StatusText -View $View -Text "Error: Invalid date format"
    }
}

function Initialize-ChangeManagementView {
    <#
    .SYNOPSIS
        Initializes the Change Management view into a Host ContentControl.
        Used for nested tab scenarios where the view is loaded into a container.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.ContentControl]$Host
    )

    try {
        $viewPath = Join-Path $PSScriptRoot '..\Views\ChangeManagementView.xaml'
        if (-not (Test-Path $viewPath)) {
            Write-Warning "ChangeManagementView.xaml not found at $viewPath"
            return
        }

        $xamlContent = Get-Content -Path $viewPath -Raw
        $xamlContent = $xamlContent -replace 'x:Class="[^"]*"', ''
        $xamlContent = $xamlContent -replace 'mc:Ignorable="d"', ''

        $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xamlContent))
        $view = [System.Windows.Markup.XamlReader]::Load($reader)
        $Host.Content = $view

        # Initialize controls and wire up event handlers
        Initialize-ChangeManagementControls -View $view
        Register-ChangeManagementEventHandlers -View $view
        Update-ChangeManagementView -View $view

        return $view
    }
    catch {
        Write-Warning "Failed to initialize ChangeManagement view: $($_.Exception.Message)"
    }
}

# Export functions
Export-ModuleMember -Function @(
    'New-ChangeManagementView'
    'Update-ChangeManagementView'
    'Initialize-ChangeManagementView'
)
