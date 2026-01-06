#Requires -Version 5.1
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Change management and maintenance window planning module for StateTrace.

.DESCRIPTION
    Provides comprehensive change request management, maintenance window scheduling,
    pre/post change verification, execution tracking, and rollback management
    for network infrastructure changes.

.NOTES
    Plan Z - Change Management & Maintenance Windows
#>

# Module-level databases
$script:ChangeRequests = $null
$script:ChangeSteps = $null
$script:ChangeDevices = $null
$script:MaintenanceWindows = $null
$script:ChangeHistory = $null
$script:ChangeTemplates = $null
$script:DatabasePath = $null

#region Initialization

function Initialize-ChangeManagementDatabase {
    <#
    .SYNOPSIS
        Initializes the change management database structures.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Path,

        [Parameter()]
        [switch]$TestMode
    )

    if ($TestMode) {
        $script:DatabasePath = $null
    } elseif ($Path) {
        $script:DatabasePath = $Path
    } else {
        $dataDir = Join-Path $PSScriptRoot '..\Data'
        if (-not (Test-Path $dataDir)) {
            New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
        }
        $script:DatabasePath = Join-Path $dataDir 'ChangeManagementDatabase.json'
    }

    # Initialize empty databases
    $script:ChangeRequests = New-Object System.Collections.ArrayList
    $script:ChangeSteps = New-Object System.Collections.ArrayList
    $script:ChangeDevices = New-Object System.Collections.ArrayList
    $script:MaintenanceWindows = New-Object System.Collections.ArrayList
    $script:ChangeHistory = New-Object System.Collections.ArrayList
    $script:ChangeTemplates = New-Object System.Collections.ArrayList

    # Load existing data if available
    if ($script:DatabasePath -and (Test-Path $script:DatabasePath)) {
        Import-ChangeManagementDatabase -Path $script:DatabasePath
    }

    # Load built-in templates
    Initialize-BuiltInTemplates
}

function Initialize-BuiltInTemplates {
    <#
    .SYNOPSIS
        Loads built-in change request templates.
    #>
    $builtInTemplates = @(
        @{
            TemplateID = 'VLAN-Addition'
            Name = 'VLAN Addition'
            Description = 'Add a new VLAN to network devices'
            ChangeType = 'Standard'
            DefaultRiskLevel = 'Low'
            EstimatedDuration = 30
            Steps = @(
                @{ StepNumber = 1; Description = 'Capture pre-change configuration'; EstimatedMinutes = 5 }
                @{ StepNumber = 2; Description = 'Create VLAN on distribution switches'; EstimatedMinutes = 5 }
                @{ StepNumber = 3; Description = 'Configure trunk ports to allow VLAN'; EstimatedMinutes = 10 }
                @{ StepNumber = 4; Description = 'Verify VLAN propagation'; EstimatedMinutes = 5 }
                @{ StepNumber = 5; Description = 'Capture post-change configuration'; EstimatedMinutes = 5 }
            )
            RollbackSteps = @(
                'Remove VLAN from trunk ports'
                'Delete VLAN from distribution switches'
                'Verify VLAN removed'
            )
        }
        @{
            TemplateID = 'Port-Configuration'
            Name = 'Port Configuration Change'
            Description = 'Modify access port settings (VLAN, description, etc.)'
            ChangeType = 'Standard'
            DefaultRiskLevel = 'Low'
            EstimatedDuration = 15
            Steps = @(
                @{ StepNumber = 1; Description = 'Document current port configuration'; EstimatedMinutes = 2 }
                @{ StepNumber = 2; Description = 'Apply new port configuration'; EstimatedMinutes = 5 }
                @{ StepNumber = 3; Description = 'Verify port status and connectivity'; EstimatedMinutes = 5 }
                @{ StepNumber = 4; Description = 'Update documentation'; EstimatedMinutes = 3 }
            )
            RollbackSteps = @(
                'Restore original port configuration'
                'Verify connectivity restored'
            )
        }
        @{
            TemplateID = 'Firmware-Upgrade'
            Name = 'Firmware Upgrade'
            Description = 'Upgrade device firmware/software'
            ChangeType = 'Normal'
            DefaultRiskLevel = 'High'
            EstimatedDuration = 120
            Steps = @(
                @{ StepNumber = 1; Description = 'Backup current configuration'; EstimatedMinutes = 10 }
                @{ StepNumber = 2; Description = 'Verify firmware file integrity'; EstimatedMinutes = 5 }
                @{ StepNumber = 3; Description = 'Upload firmware to device'; EstimatedMinutes = 20 }
                @{ StepNumber = 4; Description = 'Schedule/execute reload'; EstimatedMinutes = 30 }
                @{ StepNumber = 5; Description = 'Verify device boots with new firmware'; EstimatedMinutes = 15 }
                @{ StepNumber = 6; Description = 'Run post-upgrade verification tests'; EstimatedMinutes = 20 }
                @{ StepNumber = 7; Description = 'Document completion'; EstimatedMinutes = 10 }
            )
            RollbackSteps = @(
                'Boot from backup firmware image'
                'Restore configuration if needed'
                'Verify services restored'
            )
        }
        @{
            TemplateID = 'ACL-Modification'
            Name = 'Access Control List Modification'
            Description = 'Add, modify, or remove ACL entries'
            ChangeType = 'Normal'
            DefaultRiskLevel = 'Medium'
            EstimatedDuration = 45
            Steps = @(
                @{ StepNumber = 1; Description = 'Document current ACL configuration'; EstimatedMinutes = 5 }
                @{ StepNumber = 2; Description = 'Review proposed changes with security team'; EstimatedMinutes = 10 }
                @{ StepNumber = 3; Description = 'Apply ACL changes'; EstimatedMinutes = 10 }
                @{ StepNumber = 4; Description = 'Test affected traffic flows'; EstimatedMinutes = 15 }
                @{ StepNumber = 5; Description = 'Document changes and update diagrams'; EstimatedMinutes = 5 }
            )
            RollbackSteps = @(
                'Remove new ACL entries'
                'Restore original ACL configuration'
                'Verify traffic flows restored'
            )
        }
        @{
            TemplateID = 'Routing-Change'
            Name = 'Routing Configuration Change'
            Description = 'Modify static routes, OSPF, BGP, or other routing protocols'
            ChangeType = 'Normal'
            DefaultRiskLevel = 'High'
            EstimatedDuration = 60
            Steps = @(
                @{ StepNumber = 1; Description = 'Capture current routing tables'; EstimatedMinutes = 5 }
                @{ StepNumber = 2; Description = 'Document expected routing changes'; EstimatedMinutes = 5 }
                @{ StepNumber = 3; Description = 'Apply routing configuration changes'; EstimatedMinutes = 15 }
                @{ StepNumber = 4; Description = 'Verify route propagation'; EstimatedMinutes = 10 }
                @{ StepNumber = 5; Description = 'Test connectivity to affected destinations'; EstimatedMinutes = 15 }
                @{ StepNumber = 6; Description = 'Capture post-change routing tables'; EstimatedMinutes = 5 }
                @{ StepNumber = 7; Description = 'Update network documentation'; EstimatedMinutes = 5 }
            )
            RollbackSteps = @(
                'Remove new routing entries'
                'Restore original routing configuration'
                'Verify route convergence'
                'Test connectivity restored'
            )
        }
        @{
            TemplateID = 'Emergency-Fix'
            Name = 'Emergency Fix'
            Description = 'Urgent fix for service-impacting issue'
            ChangeType = 'Emergency'
            DefaultRiskLevel = 'High'
            EstimatedDuration = 30
            Steps = @(
                @{ StepNumber = 1; Description = 'Document current state and issue'; EstimatedMinutes = 5 }
                @{ StepNumber = 2; Description = 'Apply emergency fix'; EstimatedMinutes = 10 }
                @{ StepNumber = 3; Description = 'Verify service restoration'; EstimatedMinutes = 10 }
                @{ StepNumber = 4; Description = 'Document actions taken'; EstimatedMinutes = 5 }
            )
            RollbackSteps = @(
                'Revert emergency changes'
                'Escalate if rollback fails'
            )
        }
    )

    foreach ($template in $builtInTemplates) {
        $existing = $script:ChangeTemplates | Where-Object { $_.TemplateID -eq $template.TemplateID }
        if (-not $existing) {
            $templateObj = [PSCustomObject]$template
            [void]$script:ChangeTemplates.Add($templateObj)
        }
    }
}

#endregion

#region Change Request Management

function New-ChangeRequest {
    <#
    .SYNOPSIS
        Creates a new change request.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter()]
        [string]$Description,

        [Parameter()]
        [ValidateSet('Standard', 'Normal', 'Emergency')]
        [string]$ChangeType = 'Normal',

        [Parameter()]
        [ValidateSet('Low', 'Medium', 'High', 'Critical')]
        [string]$RiskLevel = 'Medium',

        [Parameter()]
        [DateTime]$PlannedStart,

        [Parameter()]
        [DateTime]$PlannedEnd,

        [Parameter()]
        [string[]]$AffectedDevices,

        [Parameter()]
        [string[]]$AffectedSites,

        [Parameter()]
        [string]$Template,

        [Parameter()]
        [string]$RequestedBy,

        [Parameter()]
        [string[]]$ChangeCommands,

        [Parameter()]
        [string[]]$RollbackCommands,

        [Parameter()]
        [string]$SuccessCriteria,

        [Parameter()]
        [switch]$AutoAssessRisk,

        [Parameter()]
        [string]$Notes
    )

    # Validate dates
    if ($PlannedStart -and $PlannedEnd -and $PlannedEnd -lt $PlannedStart) {
        throw "Planned end time must be after planned start time"
    }

    # Generate Change ID
    $dateStr = (Get-Date).ToString('yyyyMMdd')
    $existingToday = @($script:ChangeRequests | Where-Object { $_.ChangeID -like "CHG-$dateStr-*" })
    $sequence = ($existingToday.Count + 1).ToString('0000')
    $changeId = "CHG-$dateStr-$sequence"

    # Auto-assess risk if requested
    if ($AutoAssessRisk -and $AffectedDevices) {
        $deviceCount = $AffectedDevices.Count
        $hasCore = $AffectedDevices | Where-Object { $_ -match '(CORE|DIST|DS-|CR-)' }

        if ($hasCore -or $deviceCount -gt 10) {
            $RiskLevel = 'Critical'
        } elseif ($deviceCount -gt 5) {
            $RiskLevel = 'High'
        } elseif ($deviceCount -gt 2) {
            $RiskLevel = 'Medium'
        }
    }

    # Apply template if specified
    $templateObj = $null
    if ($Template) {
        $templateObj = $script:ChangeTemplates | Where-Object { $_.TemplateID -eq $Template }
        if ($templateObj) {
            # Use template values if not explicitly provided by caller
            if (-not $PSBoundParameters.ContainsKey('ChangeType') -and $templateObj.ChangeType) {
                $ChangeType = $templateObj.ChangeType
            }
            if (-not $PSBoundParameters.ContainsKey('RiskLevel') -and -not $AutoAssessRisk -and $templateObj.DefaultRiskLevel) {
                $RiskLevel = $templateObj.DefaultRiskLevel
            }
        }
    }

    $now = Get-Date

    $change = [PSCustomObject]@{
        ChangeID = $changeId
        Title = $Title
        Description = $Description
        ChangeType = $ChangeType
        RiskLevel = $RiskLevel
        Status = 'Draft'
        PlannedStart = $PlannedStart
        PlannedEnd = $PlannedEnd
        ActualStart = $null
        ActualEnd = $null
        AffectedDevices = $AffectedDevices
        AffectedSites = $AffectedSites
        Template = $Template
        RequestedBy = if ($RequestedBy) { $RequestedBy } else { $env:USERNAME }
        ApprovedBy = $null
        ImplementedBy = $null
        ChangeCommands = $ChangeCommands
        RollbackCommands = $RollbackCommands
        SuccessCriteria = $SuccessCriteria
        Notes = $Notes
        CreatedDate = $now
        ModifiedDate = $now
        VerificationRules = New-Object System.Collections.ArrayList
    }

    [void]$script:ChangeRequests.Add($change)

    # Add template steps if template specified
    if ($templateObj -and $templateObj.Steps) {
        foreach ($step in $templateObj.Steps) {
            $null = Add-ChangeStep -ChangeID $changeId `
                -StepNumber $step.StepNumber `
                -Description $step.Description `
                -EstimatedMinutes $step.EstimatedMinutes
        }
    }

    # Log history
    $null = Add-ChangeHistoryEntry -ChangeID $changeId -Action 'Created' -Details "Change request created: $Title"

    return $change
}

function Get-ChangeRequest {
    <#
    .SYNOPSIS
        Retrieves change requests.
    #>
    [CmdletBinding(DefaultParameterSetName = 'All')]
    param(
        [Parameter(ParameterSetName = 'ByID')]
        [string]$ChangeID,

        [Parameter(ParameterSetName = 'ByStatus')]
        [ValidateSet('Draft', 'Submitted', 'Approved', 'InProgress', 'Completed', 'Failed', 'RolledBack', 'Cancelled')]
        [string]$Status,

        [Parameter(ParameterSetName = 'ByDateRange')]
        [DateTime]$StartDate,

        [Parameter(ParameterSetName = 'ByDateRange')]
        [DateTime]$EndDate,

        [Parameter(ParameterSetName = 'ByDevice')]
        [string]$Device
    )

    $results = $script:ChangeRequests

    switch ($PSCmdlet.ParameterSetName) {
        'ByID' {
            $results = $results | Where-Object { $_.ChangeID -eq $ChangeID }
        }
        'ByStatus' {
            $results = $results | Where-Object { $_.Status -eq $Status }
        }
        'ByDateRange' {
            if ($StartDate) {
                $results = $results | Where-Object { $_.PlannedStart -ge $StartDate }
            }
            if ($EndDate) {
                $results = $results | Where-Object { $_.PlannedStart -le $EndDate }
            }
        }
        'ByDevice' {
            $results = $results | Where-Object { $_.AffectedDevices -contains $Device }
        }
    }

    return $results
}

function Update-ChangeRequest {
    <#
    .SYNOPSIS
        Updates a change request.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ChangeID,

        [Parameter()]
        [string]$Title,

        [Parameter()]
        [string]$Description,

        [Parameter()]
        [ValidateSet('Draft', 'Submitted', 'Approved', 'InProgress', 'Completed', 'Failed', 'RolledBack', 'Cancelled')]
        [string]$Status,

        [Parameter()]
        [DateTime]$PlannedStart,

        [Parameter()]
        [DateTime]$PlannedEnd,

        [Parameter()]
        [string]$ApprovedBy,

        [Parameter()]
        [string]$Notes
    )

    $change = $script:ChangeRequests | Where-Object { $_.ChangeID -eq $ChangeID }
    if (-not $change) {
        throw "Change request '$ChangeID' not found"
    }

    $changes = @()

    if ($Title) { $change.Title = $Title; $changes += "Title updated" }
    if ($Description) { $change.Description = $Description; $changes += "Description updated" }
    if ($Status) {
        $oldStatus = $change.Status
        $change.Status = $Status
        $changes += "Status: $oldStatus -> $Status"
    }
    if ($PlannedStart) { $change.PlannedStart = $PlannedStart; $changes += "PlannedStart updated" }
    if ($PlannedEnd) { $change.PlannedEnd = $PlannedEnd; $changes += "PlannedEnd updated" }
    if ($ApprovedBy) { $change.ApprovedBy = $ApprovedBy; $changes += "Approved by $ApprovedBy" }
    if ($Notes) { $change.Notes = $Notes }

    $change.ModifiedDate = Get-Date

    if ($changes.Count -gt 0) {
        $null = Add-ChangeHistoryEntry -ChangeID $ChangeID -Action 'Updated' -Details ($changes -join '; ')
    }

    return $change
}

function Remove-ChangeRequest {
    <#
    .SYNOPSIS
        Removes a change request (only if in Draft status).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ChangeID
    )

    $change = $script:ChangeRequests | Where-Object { $_.ChangeID -eq $ChangeID }
    if (-not $change) {
        throw "Change request '$ChangeID' not found"
    }

    if ($change.Status -ne 'Draft') {
        throw "Can only delete change requests in Draft status"
    }

    # Remove associated steps and devices
    $stepsToRemove = @($script:ChangeSteps | Where-Object { $_.ChangeID -eq $ChangeID })
    foreach ($step in $stepsToRemove) {
        [void]$script:ChangeSteps.Remove($step)
    }

    $devicesToRemove = @($script:ChangeDevices | Where-Object { $_.ChangeID -eq $ChangeID })
    foreach ($device in $devicesToRemove) {
        [void]$script:ChangeDevices.Remove($device)
    }

    [void]$script:ChangeRequests.Remove($change)

    $null = Add-ChangeHistoryEntry -ChangeID $ChangeID -Action 'Deleted' -Details "Change request deleted"
}

#endregion

#region Change Steps

function Add-ChangeStep {
    <#
    .SYNOPSIS
        Adds a step to a change request.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ChangeID,

        [Parameter(Mandatory)]
        [int]$StepNumber,

        [Parameter(Mandatory)]
        [string]$Description,

        [Parameter()]
        [int]$EstimatedMinutes = 5,

        [Parameter()]
        [string]$Commands,

        [Parameter()]
        [string]$ExpectedOutput,

        [Parameter()]
        [string]$Notes
    )

    $change = $script:ChangeRequests | Where-Object { $_.ChangeID -eq $ChangeID }
    if (-not $change) {
        throw "Change request '$ChangeID' not found"
    }

    $stepId = [Guid]::NewGuid().ToString()

    $step = [PSCustomObject]@{
        StepID = $stepId
        ChangeID = $ChangeID
        StepNumber = $StepNumber
        Description = $Description
        EstimatedMinutes = $EstimatedMinutes
        Commands = $Commands
        ExpectedOutput = $ExpectedOutput
        ActualStart = $null
        ActualEnd = $null
        Status = 'Pending'
        ActualOutput = $null
        Notes = $Notes
    }

    [void]$script:ChangeSteps.Add($step)

    return $step
}

function Get-ChangeStep {
    <#
    .SYNOPSIS
        Retrieves steps for a change request.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ChangeID,

        [Parameter()]
        [int]$StepNumber
    )

    $steps = $script:ChangeSteps | Where-Object { $_.ChangeID -eq $ChangeID }

    if ($PSBoundParameters.ContainsKey('StepNumber')) {
        $steps = $steps | Where-Object { $_.StepNumber -eq $StepNumber }
    }

    return $steps | Sort-Object StepNumber
}

function Set-ChangeStepStatus {
    <#
    .SYNOPSIS
        Updates the status of a change step.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ChangeID,

        [Parameter(Mandatory)]
        [int]$StepNumber,

        [Parameter(Mandatory)]
        [ValidateSet('Pending', 'InProgress', 'Completed', 'Skipped', 'Failed')]
        [string]$Status,

        [Parameter()]
        [string]$ActualOutput,

        [Parameter()]
        [string]$Notes
    )

    $step = $script:ChangeSteps | Where-Object {
        $_.ChangeID -eq $ChangeID -and $_.StepNumber -eq $StepNumber
    }

    if (-not $step) {
        throw "Step $StepNumber not found for change '$ChangeID'"
    }

    $now = Get-Date

    if ($Status -eq 'InProgress' -and -not $step.ActualStart) {
        $step.ActualStart = $now
    }

    if ($Status -in @('Completed', 'Skipped', 'Failed')) {
        $step.ActualEnd = $now
    }

    $step.Status = $Status

    if ($ActualOutput) {
        $step.ActualOutput = $ActualOutput
    }

    if ($Notes) {
        $step.Notes = $Notes
    }

    $null = Add-ChangeHistoryEntry -ChangeID $ChangeID -Action 'StepUpdated' `
        -Details "Step $StepNumber status changed to $Status"

    return $step
}

#endregion

#region Change Execution

function Start-Change {
    <#
    .SYNOPSIS
        Starts execution of a change request.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ChangeID,

        [Parameter()]
        [string]$ImplementedBy
    )

    $change = $script:ChangeRequests | Where-Object { $_.ChangeID -eq $ChangeID }
    if (-not $change) {
        throw "Change request '$ChangeID' not found"
    }

    if ($change.Status -notin @('Approved', 'Draft')) {
        throw "Change must be in Approved or Draft status to start"
    }

    $change.Status = 'InProgress'
    $change.ActualStart = Get-Date
    $change.ImplementedBy = if ($ImplementedBy) { $ImplementedBy } else { $env:USERNAME }
    $change.ModifiedDate = Get-Date

    $null = Add-ChangeHistoryEntry -ChangeID $ChangeID -Action 'Started' `
        -Details "Change execution started by $($change.ImplementedBy)"

    return $change
}

function Complete-Change {
    <#
    .SYNOPSIS
        Marks a change request as completed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ChangeID,

        [Parameter()]
        [string]$CompletionNotes
    )

    $change = $script:ChangeRequests | Where-Object { $_.ChangeID -eq $ChangeID }
    if (-not $change) {
        throw "Change request '$ChangeID' not found"
    }

    $change.Status = 'Completed'
    $change.ActualEnd = Get-Date
    $change.ModifiedDate = Get-Date

    if ($CompletionNotes) {
        $change.Notes = if ($change.Notes) { "$($change.Notes)`n$CompletionNotes" } else { $CompletionNotes }
    }

    $null = Add-ChangeHistoryEntry -ChangeID $ChangeID -Action 'Completed' `
        -Details "Change completed successfully"

    return $change
}

function Fail-Change {
    <#
    .SYNOPSIS
        Marks a change request as failed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ChangeID,

        [Parameter()]
        [string]$FailureReason
    )

    $change = $script:ChangeRequests | Where-Object { $_.ChangeID -eq $ChangeID }
    if (-not $change) {
        throw "Change request '$ChangeID' not found"
    }

    $change.Status = 'Failed'
    $change.ActualEnd = Get-Date
    $change.ModifiedDate = Get-Date

    if ($FailureReason) {
        $change.Notes = if ($change.Notes) { "$($change.Notes)`nFailure: $FailureReason" } else { "Failure: $FailureReason" }
    }

    $null = Add-ChangeHistoryEntry -ChangeID $ChangeID -Action 'Failed' `
        -Details "Change failed: $FailureReason"

    return $change
}

function Get-ChangeDuration {
    <#
    .SYNOPSIS
        Gets the duration of a change execution.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ChangeID
    )

    $change = $script:ChangeRequests | Where-Object { $_.ChangeID -eq $ChangeID }
    if (-not $change) {
        throw "Change request '$ChangeID' not found"
    }

    if (-not $change.ActualStart) {
        return $null
    }

    $endTime = if ($change.ActualEnd) { $change.ActualEnd } else { Get-Date }

    return $endTime - $change.ActualStart
}

function Get-ChangeProgress {
    <#
    .SYNOPSIS
        Gets the progress of a change execution.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ChangeID
    )

    $steps = @(Get-ChangeStep -ChangeID $ChangeID)

    if ($steps.Count -eq 0) {
        return [PSCustomObject]@{
            TotalSteps = 0
            CompletedSteps = 0
            ProgressPercent = 0
            CurrentStep = $null
        }
    }

    $completed = @($steps | Where-Object { $_.Status -in @('Completed', 'Skipped') }).Count
    $current = $steps | Where-Object { $_.Status -eq 'InProgress' } | Select-Object -First 1
    $percent = [Math]::Round(($completed / $steps.Count) * 100, 0)

    return [PSCustomObject]@{
        TotalSteps = $steps.Count
        CompletedSteps = $completed
        ProgressPercent = $percent
        CurrentStep = $current
        PendingSteps = @($steps | Where-Object { $_.Status -eq 'Pending' }).Count
    }
}

#endregion

#region Rollback Management

function Invoke-ChangeRollback {
    <#
    .SYNOPSIS
        Initiates rollback of a change.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ChangeID,

        [Parameter()]
        [string]$RollbackReason
    )

    $change = $script:ChangeRequests | Where-Object { $_.ChangeID -eq $ChangeID }
    if (-not $change) {
        throw "Change request '$ChangeID' not found"
    }

    $change.Status = 'RolledBack'
    $change.ActualEnd = Get-Date
    $change.ModifiedDate = Get-Date

    $rollbackNote = "Rollback initiated"
    if ($RollbackReason) {
        $rollbackNote += ": $RollbackReason"
    }

    $change.Notes = if ($change.Notes) { "$($change.Notes)`n$rollbackNote" } else { $rollbackNote }

    $null = Add-ChangeHistoryEntry -ChangeID $ChangeID -Action 'RolledBack' `
        -Details $rollbackNote

    return $change
}

function Get-RollbackCommands {
    <#
    .SYNOPSIS
        Gets the rollback commands for a change.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ChangeID
    )

    $change = $script:ChangeRequests | Where-Object { $_.ChangeID -eq $ChangeID }
    if (-not $change) {
        throw "Change request '$ChangeID' not found"
    }

    # Return explicit rollback commands if defined
    if ($change.RollbackCommands) {
        return $change.RollbackCommands
    }

    # Try to get from template
    if ($change.Template) {
        $template = $script:ChangeTemplates | Where-Object { $_.TemplateID -eq $change.Template }
        if ($template -and $template.RollbackSteps) {
            return $template.RollbackSteps
        }
    }

    return @()
}

#endregion

#region Maintenance Windows

function New-MaintenanceWindow {
    <#
    .SYNOPSIS
        Creates a new maintenance window.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory)]
        [DateTime]$StartTime,

        [Parameter(Mandatory)]
        [DateTime]$EndTime,

        [Parameter()]
        [string]$Scope,

        [Parameter()]
        [string[]]$AffectedSites,

        [Parameter()]
        [switch]$IsRecurring,

        [Parameter()]
        [ValidateSet('Weekly', 'BiWeekly', 'Monthly')]
        [string]$RecurrencePattern,

        [Parameter()]
        [switch]$IsBlackout,

        [Parameter()]
        [string]$CreatedBy,

        [Parameter()]
        [string]$Notes
    )

    if ($EndTime -le $StartTime) {
        throw "End time must be after start time"
    }

    $windowId = [Guid]::NewGuid().ToString()

    $window = [PSCustomObject]@{
        WindowID = $windowId
        Title = $Title
        StartTime = $StartTime
        EndTime = $EndTime
        Scope = $Scope
        AffectedSites = $AffectedSites
        IsRecurring = $IsRecurring.IsPresent
        RecurrencePattern = $RecurrencePattern
        IsBlackout = $IsBlackout.IsPresent
        CreatedBy = if ($CreatedBy) { $CreatedBy } else { $env:USERNAME }
        Notes = $Notes
        CreatedDate = Get-Date
        LinkedChanges = @()
    }

    [void]$script:MaintenanceWindows.Add($window)

    return $window
}

function Get-MaintenanceWindow {
    <#
    .SYNOPSIS
        Retrieves maintenance windows.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$WindowID,

        [Parameter()]
        [DateTime]$StartDate,

        [Parameter()]
        [DateTime]$EndDate,

        [Parameter()]
        [switch]$BlackoutsOnly,

        [Parameter()]
        [switch]$IncludePast
    )

    $windows = $script:MaintenanceWindows

    if ($WindowID) {
        $windows = $windows | Where-Object { $_.WindowID -eq $WindowID }
    }

    if ($StartDate) {
        $windows = $windows | Where-Object { $_.EndTime -ge $StartDate }
    }

    if ($EndDate) {
        $windows = $windows | Where-Object { $_.StartTime -le $EndDate }
    }

    if ($BlackoutsOnly) {
        $windows = $windows | Where-Object { $_.IsBlackout }
    }

    if (-not $IncludePast) {
        $now = Get-Date
        $windows = $windows | Where-Object { $_.EndTime -ge $now }
    }

    return $windows | Sort-Object StartTime
}

function Test-MaintenanceWindowConflict {
    <#
    .SYNOPSIS
        Checks for conflicts with existing maintenance windows.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [DateTime]$StartTime,

        [Parameter(Mandatory)]
        [DateTime]$EndTime,

        [Parameter()]
        [string]$ExcludeWindowID
    )

    $conflicts = @($script:MaintenanceWindows | Where-Object {
        $_.WindowID -ne $ExcludeWindowID -and
        -not $_.IsBlackout -and
        (($StartTime -ge $_.StartTime -and $StartTime -lt $_.EndTime) -or
         ($EndTime -gt $_.StartTime -and $EndTime -le $_.EndTime) -or
         ($StartTime -le $_.StartTime -and $EndTime -ge $_.EndTime))
    })

    return $conflicts
}

function Test-BlackoutViolation {
    <#
    .SYNOPSIS
        Checks if a planned change falls within a blackout period.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [DateTime]$PlannedStart,

        [Parameter()]
        [DateTime]$PlannedEnd
    )

    if (-not $PlannedEnd) {
        $PlannedEnd = $PlannedStart.AddHours(1)
    }

    $blackouts = @($script:MaintenanceWindows | Where-Object {
        $_.IsBlackout -and
        (($PlannedStart -ge $_.StartTime -and $PlannedStart -lt $_.EndTime) -or
         ($PlannedEnd -gt $_.StartTime -and $PlannedEnd -le $_.EndTime) -or
         ($PlannedStart -le $_.StartTime -and $PlannedEnd -ge $_.EndTime))
    })

    if ($blackouts.Count -gt 0) {
        return [PSCustomObject]@{
            IsViolation = $true
            BlackoutPeriods = $blackouts
            Message = "Change falls within blackout period: $($blackouts[0].Title)"
        }
    }

    return [PSCustomObject]@{
        IsViolation = $false
        BlackoutPeriods = @()
        Message = "No blackout violations"
    }
}

function Remove-MaintenanceWindow {
    <#
    .SYNOPSIS
        Removes a maintenance window.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$WindowID
    )

    $window = $script:MaintenanceWindows | Where-Object { $_.WindowID -eq $WindowID }
    if (-not $window) {
        throw "Maintenance window '$WindowID' not found"
    }

    [void]$script:MaintenanceWindows.Remove($window)
}

#endregion

#region Pre/Post Change Capture

function Add-ChangeDevice {
    <#
    .SYNOPSIS
        Associates a device with a change and captures baseline.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ChangeID,

        [Parameter(Mandatory)]
        [string]$DeviceID,

        [Parameter()]
        [string]$ChangeRole = 'Target',

        [Parameter()]
        [string]$PreConfigSnapshot,

        [Parameter()]
        [string]$PreStateSnapshot,

        [Parameter()]
        [string]$Notes
    )

    $change = $script:ChangeRequests | Where-Object { $_.ChangeID -eq $ChangeID }
    if (-not $change) {
        throw "Change request '$ChangeID' not found"
    }

    $deviceEntry = [PSCustomObject]@{
        ChangeID = $ChangeID
        DeviceID = $DeviceID
        ChangeRole = $ChangeRole
        PreConfigSnapshot = $PreConfigSnapshot
        PostConfigSnapshot = $null
        PreStateSnapshot = $PreStateSnapshot
        PostStateSnapshot = $null
        Status = 'Pending'
        CaptureTime = Get-Date
        Notes = $Notes
    }

    [void]$script:ChangeDevices.Add($deviceEntry)

    return $deviceEntry
}

function Set-ChangeDevicePostState {
    <#
    .SYNOPSIS
        Captures post-change state for a device.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ChangeID,

        [Parameter(Mandatory)]
        [string]$DeviceID,

        [Parameter()]
        [string]$PostConfigSnapshot,

        [Parameter()]
        [string]$PostStateSnapshot,

        [Parameter()]
        [ValidateSet('Pending', 'Changed', 'Unchanged', 'Failed')]
        [string]$Status = 'Changed'
    )

    $device = $script:ChangeDevices | Where-Object {
        $_.ChangeID -eq $ChangeID -and $_.DeviceID -eq $DeviceID
    }

    if (-not $device) {
        throw "Device '$DeviceID' not found for change '$ChangeID'"
    }

    $device.PostConfigSnapshot = $PostConfigSnapshot
    $device.PostStateSnapshot = $PostStateSnapshot
    $device.Status = $Status

    return $device
}

function Get-ChangeDevice {
    <#
    .SYNOPSIS
        Gets devices associated with a change.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ChangeID
    )

    return $script:ChangeDevices | Where-Object { $_.ChangeID -eq $ChangeID }
}

function Compare-ChangeConfigurations {
    <#
    .SYNOPSIS
        Compares pre and post change configurations.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ChangeID
    )

    $devices = Get-ChangeDevice -ChangeID $ChangeID

    $results = @()

    foreach ($device in $devices) {
        if (-not $device.PreConfigSnapshot -or -not $device.PostConfigSnapshot) {
            continue
        }

        $preLines = $device.PreConfigSnapshot -split "`n"
        $postLines = $device.PostConfigSnapshot -split "`n"

        $added = @($postLines | Where-Object { $_ -notin $preLines })
        $removed = @($preLines | Where-Object { $_ -notin $postLines })

        $results += [PSCustomObject]@{
            DeviceID = $device.DeviceID
            HasChanges = ($added.Count -gt 0 -or $removed.Count -gt 0)
            AddedLines = $added
            RemovedLines = $removed
            AddedCount = $added.Count
            RemovedCount = $removed.Count
        }
    }

    return $results
}

#endregion

#region Post-Change Verification

function New-VerificationRule {
    <#
    .SYNOPSIS
        Creates a new verification rule for change validation.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ChangeID,

        [Parameter(Mandatory)]
        [string]$RuleName,

        [Parameter()]
        [string]$Description,

        [Parameter(Mandatory)]
        [ValidateSet('ConfigContains', 'ConfigNotContains', 'StateMatch', 'OutputContains', 'Custom')]
        [string]$RuleType,

        [Parameter()]
        [string]$ExpectedValue,

        [Parameter()]
        [string]$DeviceID,

        [Parameter()]
        [ValidateSet('Critical', 'Warning', 'Info')]
        [string]$Severity = 'Critical'
    )

    $change = $script:ChangeRequests | Where-Object { $_.ChangeID -eq $ChangeID }
    if (-not $change) {
        throw "Change request '$ChangeID' not found"
    }

    # Store verification rules in change object
    if (-not $change.VerificationRules) {
        $change | Add-Member -NotePropertyName 'VerificationRules' -NotePropertyValue (New-Object System.Collections.ArrayList) -Force
    }

    $rule = [PSCustomObject]@{
        RuleID = [Guid]::NewGuid().ToString()
        RuleName = $RuleName
        Description = $Description
        RuleType = $RuleType
        ExpectedValue = $ExpectedValue
        DeviceID = $DeviceID
        Severity = $Severity
        Status = 'Pending'
        Result = $null
        CheckedAt = $null
    }

    [void]$change.VerificationRules.Add($rule)

    return $rule
}

function Get-VerificationRule {
    <#
    .SYNOPSIS
        Gets verification rules for a change.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ChangeID,

        [Parameter()]
        [string]$RuleName
    )

    $change = $script:ChangeRequests | Where-Object { $_.ChangeID -eq $ChangeID }
    if (-not $change) {
        throw "Change request '$ChangeID' not found"
    }

    if ($change.VerificationRules) {
        if ($RuleName) {
            return $change.VerificationRules | Where-Object { $_.RuleName -eq $RuleName }
        }
        return $change.VerificationRules
    }

    return @()
}

function Invoke-ChangeVerification {
    <#
    .SYNOPSIS
        Runs all verification checks for a change.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ChangeID,

        [Parameter()]
        [switch]$IncludeConfigDiff,

        [Parameter()]
        [switch]$IncludeStateDiff
    )

    $change = $script:ChangeRequests | Where-Object { $_.ChangeID -eq $ChangeID }
    if (-not $change) {
        throw "Change request '$ChangeID' not found"
    }

    $now = Get-Date
    $results = New-Object System.Collections.ArrayList

    # Run custom verification rules
    $rules = Get-VerificationRule -ChangeID $ChangeID
    foreach ($rule in $rules) {
        $passed = $false
        $actualValue = $null
        $message = ''

        switch ($rule.RuleType) {
            'ConfigContains' {
                if ($rule.DeviceID) {
                    $device = $script:ChangeDevices | Where-Object {
                        $_.ChangeID -eq $ChangeID -and $_.DeviceID -eq $rule.DeviceID
                    }
                    if ($device -and $device.PostConfigSnapshot) {
                        $passed = $device.PostConfigSnapshot -match [regex]::Escape($rule.ExpectedValue)
                        $actualValue = if ($passed) { 'Found' } else { 'Not found' }
                    }
                }
            }
            'ConfigNotContains' {
                if ($rule.DeviceID) {
                    $device = $script:ChangeDevices | Where-Object {
                        $_.ChangeID -eq $ChangeID -and $_.DeviceID -eq $rule.DeviceID
                    }
                    if ($device -and $device.PostConfigSnapshot) {
                        $passed = $device.PostConfigSnapshot -notmatch [regex]::Escape($rule.ExpectedValue)
                        $actualValue = if ($passed) { 'Not found (correct)' } else { 'Found (incorrect)' }
                    }
                }
            }
            'StateMatch' {
                if ($rule.DeviceID) {
                    $device = $script:ChangeDevices | Where-Object {
                        $_.ChangeID -eq $ChangeID -and $_.DeviceID -eq $rule.DeviceID
                    }
                    if ($device -and $device.PostStateSnapshot) {
                        $passed = $device.PostStateSnapshot -match [regex]::Escape($rule.ExpectedValue)
                        $actualValue = if ($passed) { 'Match' } else { 'No match' }
                    }
                }
            }
            'OutputContains' {
                # Check step outputs
                $steps = Get-ChangeStep -ChangeID $ChangeID
                foreach ($step in $steps) {
                    if ($step.ActualOutput -and $step.ActualOutput -match [regex]::Escape($rule.ExpectedValue)) {
                        $passed = $true
                        $actualValue = "Found in step $($step.StepNumber)"
                        break
                    }
                }
                if (-not $passed) {
                    $actualValue = 'Not found in any step output'
                }
            }
            'Custom' {
                # Custom rules need manual verification
                $passed = $null
                $actualValue = 'Requires manual verification'
                $message = 'Manual check required'
            }
        }

        $rule.Status = if ($null -eq $passed) { 'Manual' } elseif ($passed) { 'Passed' } else { 'Failed' }
        $rule.Result = $actualValue
        $rule.CheckedAt = $now

        [void]$results.Add([PSCustomObject]@{
            RuleName = $rule.RuleName
            RuleType = $rule.RuleType
            Severity = $rule.Severity
            Status = $rule.Status
            ExpectedValue = $rule.ExpectedValue
            ActualValue = $actualValue
            DeviceID = $rule.DeviceID
            Message = $message
        })
    }

    # Add config diff results if requested
    if ($IncludeConfigDiff) {
        $configDiffs = Compare-ChangeConfigurations -ChangeID $ChangeID
        foreach ($diff in $configDiffs) {
            [void]$results.Add([PSCustomObject]@{
                RuleName = "Config Changes - $($diff.DeviceID)"
                RuleType = 'ConfigDiff'
                Severity = 'Info'
                Status = if ($diff.HasChanges) { 'Changed' } else { 'Unchanged' }
                ExpectedValue = 'Configuration modified'
                ActualValue = "Added: $($diff.AddedCount), Removed: $($diff.RemovedCount)"
                DeviceID = $diff.DeviceID
                Message = ''
            })
        }
    }

    # Return summary object with results
    $passed = @($results | Where-Object { $_.Status -eq 'Passed' }).Count
    $failed = @($results | Where-Object { $_.Status -eq 'Failed' }).Count
    $manual = @($results | Where-Object { $_.Status -eq 'Manual' }).Count

    return [PSCustomObject]@{
        ChangeID = $ChangeID
        RulesChecked = $results.Count
        Passed = $passed
        Failed = $failed
        Manual = $manual
        Results = $results
        VerifiedAt = $now
    }
}

function Test-ChangeSuccess {
    <#
    .SYNOPSIS
        Tests if a change meets its success criteria.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ChangeID,

        [Parameter()]
        [switch]$FailOnWarning
    )

    $change = $script:ChangeRequests | Where-Object { $_.ChangeID -eq $ChangeID }
    if (-not $change) {
        throw "Change request '$ChangeID' not found"
    }

    $verification = Invoke-ChangeVerification -ChangeID $ChangeID
    $verificationResults = $verification.Results

    $criticalFailures = @($verificationResults | Where-Object { $_.Severity -eq 'Critical' -and $_.Status -eq 'Failed' })
    $warningFailures = @($verificationResults | Where-Object { $_.Severity -eq 'Warning' -and $_.Status -eq 'Failed' })
    $manualChecks = @($verificationResults | Where-Object { $_.Status -eq 'Manual' })

    $allCriteriaMet = $criticalFailures.Count -eq 0
    if ($FailOnWarning) {
        $allCriteriaMet = $allCriteriaMet -and $warningFailures.Count -eq 0
    }

    # Check basic change completion
    $stepsComplete = $true
    $steps = @(Get-ChangeStep -ChangeID $ChangeID)
    if ($steps.Count -gt 0) {
        $incompleteSteps = @($steps | Where-Object { $_.Status -notin @('Completed', 'Skipped') })
        $stepsComplete = $incompleteSteps.Count -eq 0
    }

    # Check explicit success criteria if defined
    $criteriaMatched = $true
    if ($change.SuccessCriteria) {
        # Success criteria is stored as text - check if it was manually verified
        $criteriaMatched = $change.Status -eq 'Completed'
    }

    return [PSCustomObject]@{
        ChangeID = $ChangeID
        AllCriteriaMet = $allCriteriaMet -and $stepsComplete
        CriticalFailures = $criticalFailures.Count
        WarningFailures = $warningFailures.Count
        ManualChecksRequired = $manualChecks.Count
        StepsComplete = $stepsComplete
        SuccessCriteriaMatched = $criteriaMatched
        VerificationResults = $verificationResults
        VerifiedAt = Get-Date
    }
}

function Get-ChangeVerificationReport {
    <#
    .SYNOPSIS
        Generates a comprehensive verification report for a change.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ChangeID
    )

    $change = $script:ChangeRequests | Where-Object { $_.ChangeID -eq $ChangeID }
    if (-not $change) {
        throw "Change request '$ChangeID' not found"
    }

    $successTest = Test-ChangeSuccess -ChangeID $ChangeID
    $configDiffs = Compare-ChangeConfigurations -ChangeID $ChangeID
    $steps = @(Get-ChangeStep -ChangeID $ChangeID)
    $devices = @(Get-ChangeDevice -ChangeID $ChangeID)
    $duration = Get-ChangeDuration -ChangeID $ChangeID

    # Calculate step metrics
    $completedSteps = @($steps | Where-Object { $_.Status -eq 'Completed' })
    $stepDurations = @($completedSteps | Where-Object { $_.ActualStart -and $_.ActualEnd } | ForEach-Object {
        ($_.ActualEnd - $_.ActualStart).TotalMinutes
    })
    $avgStepDuration = if ($stepDurations.Count -gt 0) { ($stepDurations | Measure-Object -Average).Average } else { 0 }

    return [PSCustomObject]@{
        ChangeID = $ChangeID
        Title = $change.Title
        Status = $change.Status
        OverallSuccess = $successTest.AllCriteriaMet

        # Timing
        PlannedStart = $change.PlannedStart
        PlannedEnd = $change.PlannedEnd
        ActualStart = $change.ActualStart
        ActualEnd = $change.ActualEnd
        PlannedDurationMinutes = if ($change.PlannedStart -and $change.PlannedEnd) {
            ($change.PlannedEnd - $change.PlannedStart).TotalMinutes
        } else { 0 }
        ActualDurationMinutes = if ($duration) { $duration.TotalMinutes } else { 0 }
        OnTime = if ($change.PlannedEnd -and $change.ActualEnd) {
            $change.ActualEnd -le $change.PlannedEnd
        } else { $null }

        # Steps
        TotalSteps = $steps.Count
        CompletedSteps = $completedSteps.Count
        FailedSteps = @($steps | Where-Object { $_.Status -eq 'Failed' }).Count
        SkippedSteps = @($steps | Where-Object { $_.Status -eq 'Skipped' }).Count
        AverageStepDurationMinutes = [Math]::Round($avgStepDuration, 1)

        # Devices
        DevicesAffected = $devices.Count
        DevicesChanged = @($devices | Where-Object { $_.Status -eq 'Changed' }).Count
        DevicesUnchanged = @($devices | Where-Object { $_.Status -eq 'Unchanged' }).Count
        DevicesFailed = @($devices | Where-Object { $_.Status -eq 'Failed' }).Count

        # Configuration Changes
        ConfigurationDiffs = $configDiffs
        TotalLinesAdded = if ($configDiffs) { ($configDiffs | Measure-Object -Property AddedCount -Sum).Sum } else { 0 }
        TotalLinesRemoved = if ($configDiffs) { ($configDiffs | Measure-Object -Property RemovedCount -Sum).Sum } else { 0 }

        # Verification
        CriticalFailures = $successTest.CriticalFailures
        WarningFailures = $successTest.WarningFailures
        ManualChecksRequired = $successTest.ManualChecksRequired
        VerificationDetails = $successTest.VerificationResults
        VerificationResults = $successTest.VerificationResults

        # Metadata
        RequestedBy = $change.RequestedBy
        ApprovedBy = $change.ApprovedBy
        ImplementedBy = $change.ImplementedBy
        GeneratedAt = Get-Date
    }
}

function Export-ChangeVerificationReport {
    <#
    .SYNOPSIS
        Exports a change verification report to various formats.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ChangeID,

        [Parameter(Mandatory)]
        [ValidateSet('Text', 'HTML', 'JSON')]
        [string]$Format,

        [Parameter(Mandatory)]
        [string]$OutputPath
    )

    $report = Get-ChangeVerificationReport -ChangeID $ChangeID
    $extension = switch ($Format) {
        'Text' { 'txt' }
        'HTML' { 'html' }
        'JSON' { 'json' }
    }
    $filename = "ChangeVerification_$($ChangeID)_$(Get-Date -Format 'yyyyMMdd-HHmmss').$extension"
    $fullPath = Join-Path $OutputPath $filename

    switch ($Format) {
        'Text' {
            $status = if ($report.OverallSuccess) { 'SUCCESS' } else { 'FAILED' }
            $text = @"
CHANGE VERIFICATION REPORT
==========================
Change ID: $($report.ChangeID)
Title: $($report.Title)
Status: $($report.Status)
Overall Result: $status

TIMING
------
Planned Start: $($report.PlannedStart)
Planned End: $($report.PlannedEnd)
Actual Start: $($report.ActualStart)
Actual End: $($report.ActualEnd)
Planned Duration: $($report.PlannedDurationMinutes) minutes
Actual Duration: $([Math]::Round($report.ActualDurationMinutes, 1)) minutes
On Time: $(if ($null -eq $report.OnTime) { 'N/A' } elseif ($report.OnTime) { 'Yes' } else { 'No' })

STEPS
-----
Total: $($report.TotalSteps)
Completed: $($report.CompletedSteps)
Failed: $($report.FailedSteps)
Skipped: $($report.SkippedSteps)
Average Step Duration: $($report.AverageStepDurationMinutes) minutes

DEVICES
-------
Affected: $($report.DevicesAffected)
Changed: $($report.DevicesChanged)
Unchanged: $($report.DevicesUnchanged)
Failed: $($report.DevicesFailed)

CONFIGURATION CHANGES
---------------------
Lines Added: $($report.TotalLinesAdded)
Lines Removed: $($report.TotalLinesRemoved)

VERIFICATION
------------
Critical Failures: $($report.CriticalFailures)
Warning Failures: $($report.WarningFailures)
Manual Checks Required: $($report.ManualChecksRequired)

PERSONNEL
---------
Requested By: $($report.RequestedBy)
Approved By: $($report.ApprovedBy)
Implemented By: $($report.ImplementedBy)

Generated: $($report.GeneratedAt)
"@
            $text | Set-Content -Path $fullPath
        }
        'HTML' {
            $statusClass = if ($report.OverallSuccess) { 'success' } else { 'failure' }
            $statusText = if ($report.OverallSuccess) { 'SUCCESS' } else { 'FAILED' }

            $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Change Verification Report - $($report.ChangeID)</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        .container { max-width: 900px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #2c3e50; border-bottom: 3px solid #3498db; padding-bottom: 10px; }
        h2 { color: #34495e; margin-top: 25px; }
        .status { display: inline-block; padding: 8px 16px; border-radius: 4px; font-weight: bold; font-size: 1.1em; }
        .success { background: #27ae60; color: white; }
        .failure { background: #e74c3c; color: white; }
        .grid { display: grid; grid-template-columns: repeat(2, 1fr); gap: 20px; margin: 15px 0; }
        .card { background: #ecf0f1; padding: 15px; border-radius: 5px; }
        .card h3 { margin-top: 0; color: #2c3e50; font-size: 0.9em; text-transform: uppercase; }
        .card .value { font-size: 1.8em; font-weight: bold; color: #3498db; }
        .metric-row { display: flex; justify-content: space-between; padding: 8px 0; border-bottom: 1px solid #ddd; }
        .metric-label { color: #7f8c8d; }
        .metric-value { font-weight: bold; }
        table { width: 100%; border-collapse: collapse; margin: 15px 0; }
        th, td { border: 1px solid #ddd; padding: 10px; text-align: left; }
        th { background: #3498db; color: white; }
        tr:nth-child(even) { background: #f8f9fa; }
        .check-passed { color: #27ae60; }
        .check-failed { color: #e74c3c; }
        .check-manual { color: #f39c12; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Change Verification Report</h1>
        <p><strong>Change ID:</strong> $($report.ChangeID) | <strong>Title:</strong> $($report.Title)</p>
        <p><strong>Status:</strong> $($report.Status) | <span class="status $statusClass">$statusText</span></p>

        <div class="grid">
            <div class="card">
                <h3>Steps Completed</h3>
                <div class="value">$($report.CompletedSteps) / $($report.TotalSteps)</div>
            </div>
            <div class="card">
                <h3>Devices Changed</h3>
                <div class="value">$($report.DevicesChanged) / $($report.DevicesAffected)</div>
            </div>
            <div class="card">
                <h3>Duration</h3>
                <div class="value">$([Math]::Round($report.ActualDurationMinutes, 0)) min</div>
            </div>
            <div class="card">
                <h3>Config Changes</h3>
                <div class="value">+$($report.TotalLinesAdded) / -$($report.TotalLinesRemoved)</div>
            </div>
        </div>

        <h2>Timing</h2>
        <div class="metric-row"><span class="metric-label">Planned</span><span class="metric-value">$($report.PlannedStart) to $($report.PlannedEnd)</span></div>
        <div class="metric-row"><span class="metric-label">Actual</span><span class="metric-value">$($report.ActualStart) to $($report.ActualEnd)</span></div>
        <div class="metric-row"><span class="metric-label">On Time</span><span class="metric-value">$(if ($null -eq $report.OnTime) { 'N/A' } elseif ($report.OnTime) { 'Yes' } else { 'No' })</span></div>

        <h2>Verification Results</h2>
        <table>
            <tr><th>Check</th><th>Type</th><th>Severity</th><th>Status</th><th>Details</th></tr>
"@
            foreach ($check in $report.VerificationDetails) {
                $checkClass = switch ($check.Status) {
                    'Passed' { 'check-passed' }
                    'Failed' { 'check-failed' }
                    default { 'check-manual' }
                }
                $html += "            <tr><td>$($check.RuleName)</td><td>$($check.RuleType)</td><td>$($check.Severity)</td><td class='$checkClass'>$($check.Status)</td><td>$($check.ActualValue)</td></tr>`n"
            }
            $html += @"
        </table>

        <h2>Personnel</h2>
        <div class="metric-row"><span class="metric-label">Requested By</span><span class="metric-value">$($report.RequestedBy)</span></div>
        <div class="metric-row"><span class="metric-label">Approved By</span><span class="metric-value">$($report.ApprovedBy)</span></div>
        <div class="metric-row"><span class="metric-label">Implemented By</span><span class="metric-value">$($report.ImplementedBy)</span></div>

        <p style="margin-top: 30px; color: #7f8c8d; font-size: 0.9em;">Generated: $($report.GeneratedAt)</p>
    </div>
</body>
</html>
"@
            $html | Set-Content -Path $fullPath
        }
        'JSON' {
            $report | ConvertTo-Json -Depth 10 | Set-Content -Path $fullPath
        }
    }

    return [PSCustomObject]@{
        Path = $fullPath
        Format = $Format
        ChangeID = $ChangeID
        OverallSuccess = $report.OverallSuccess
    }
}

#endregion

#region Change Impact Analysis

function Get-ChangeImpact {
    <#
    .SYNOPSIS
        Analyzes the potential impact of a change.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ChangeID
    )

    $change = $script:ChangeRequests | Where-Object { $_.ChangeID -eq $ChangeID }
    if (-not $change) {
        throw "Change request '$ChangeID' not found"
    }

    $deviceCount = if ($change.AffectedDevices) { $change.AffectedDevices.Count } else { 0 }
    $siteCount = if ($change.AffectedSites) { $change.AffectedSites.Count } else { 0 }

    # Estimate impact based on change type and scope
    $impactLevel = 'Low'
    if ($deviceCount -gt 10 -or $change.RiskLevel -eq 'Critical') {
        $impactLevel = 'Critical'
    } elseif ($deviceCount -gt 5 -or $change.RiskLevel -eq 'High') {
        $impactLevel = 'High'
    } elseif ($deviceCount -gt 2 -or $change.RiskLevel -eq 'Medium') {
        $impactLevel = 'Medium'
    }

    return [PSCustomObject]@{
        ChangeID = $ChangeID
        DevicesAffected = $deviceCount
        SitesAffected = $siteCount
        ImpactLevel = $impactLevel
        RiskLevel = $change.RiskLevel
        ChangeType = $change.ChangeType
        EstimatedDuration = Get-ChangeEstimatedDuration -ChangeID $ChangeID
        RequiresApproval = $change.ChangeType -ne 'Standard' -or $change.RiskLevel -in @('High', 'Critical')
    }
}

function Get-ChangeEstimatedDuration {
    <#
    .SYNOPSIS
        Calculates estimated duration based on steps.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ChangeID
    )

    $steps = @(Get-ChangeStep -ChangeID $ChangeID)

    if ($steps.Count -eq 0) {
        return 0
    }

    $totalMinutes = ($steps | Measure-Object -Property EstimatedMinutes -Sum).Sum

    return $totalMinutes
}

#endregion

#region Checklists

function Get-ChangeChecklist {
    <#
    .SYNOPSIS
        Generates a checklist for a change request.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ChangeID
    )

    $change = $script:ChangeRequests | Where-Object { $_.ChangeID -eq $ChangeID }
    if (-not $change) {
        throw "Change request '$ChangeID' not found"
    }

    $steps = @(Get-ChangeStep -ChangeID $ChangeID)

    $preChecks = @(
        [PSCustomObject]@{ Item = 'Change request approved'; Checked = ($change.Status -eq 'Approved') }
        [PSCustomObject]@{ Item = 'Maintenance window scheduled'; Checked = $false }
        [PSCustomObject]@{ Item = 'Stakeholders notified'; Checked = $false }
        [PSCustomObject]@{ Item = 'Rollback procedure documented'; Checked = ($change.RollbackCommands -or $change.Template) }
        [PSCustomObject]@{ Item = 'Pre-change baseline captured'; Checked = $false }
    )

    $postChecks = @(
        [PSCustomObject]@{ Item = 'All implementation steps completed'; Checked = $false }
        [PSCustomObject]@{ Item = 'Post-change verification performed'; Checked = $false }
        [PSCustomObject]@{ Item = 'Services confirmed operational'; Checked = $false }
        [PSCustomObject]@{ Item = 'Documentation updated'; Checked = $false }
        [PSCustomObject]@{ Item = 'Stakeholders notified of completion'; Checked = $false }
    )

    return [PSCustomObject]@{
        ChangeID = $ChangeID
        Title = $change.Title
        PreChecks = $preChecks
        Steps = $steps
        PostChecks = $postChecks
        GeneratedDate = Get-Date
    }
}

#endregion

#region Templates

function Get-ChangeTemplate {
    <#
    .SYNOPSIS
        Retrieves change request templates.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$TemplateID
    )

    if ($TemplateID) {
        return $script:ChangeTemplates | Where-Object { $_.TemplateID -eq $TemplateID }
    }

    return $script:ChangeTemplates
}

#endregion

#region History

function Add-ChangeHistoryEntry {
    <#
    .SYNOPSIS
        Adds an entry to the change history log.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ChangeID,

        [Parameter(Mandatory)]
        [string]$Action,

        [Parameter()]
        [string]$Details
    )

    $entry = [PSCustomObject]@{
        HistoryID = [Guid]::NewGuid().ToString()
        ChangeID = $ChangeID
        Action = $Action
        Details = $Details
        Timestamp = Get-Date
        User = $env:USERNAME
    }

    [void]$script:ChangeHistory.Add($entry)

    return $entry
}

function Get-ChangeHistory {
    <#
    .SYNOPSIS
        Retrieves history for a change request.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$ChangeID
    )

    if ($ChangeID) {
        return $script:ChangeHistory | Where-Object { $_.ChangeID -eq $ChangeID } | Sort-Object Timestamp
    }

    return $script:ChangeHistory | Sort-Object Timestamp -Descending
}

#endregion

#region Statistics

function Get-ChangeStatistics {
    <#
    .SYNOPSIS
        Gets change management statistics.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateSet('LastWeek', 'LastMonth', 'LastQuarter', 'LastYear', 'All')]
        [string]$Period = 'LastMonth'
    )

    $now = Get-Date
    $startDate = switch ($Period) {
        'LastWeek' { $now.AddDays(-7) }
        'LastMonth' { $now.AddMonths(-1) }
        'LastQuarter' { $now.AddMonths(-3) }
        'LastYear' { $now.AddYears(-1) }
        'All' { [DateTime]::MinValue }
    }

    $changes = @($script:ChangeRequests | Where-Object { $_.CreatedDate -ge $startDate })

    $completed = @($changes | Where-Object { $_.Status -eq 'Completed' }).Count
    $failed = @($changes | Where-Object { $_.Status -eq 'Failed' }).Count
    $rolledBack = @($changes | Where-Object { $_.Status -eq 'RolledBack' }).Count

    $totalFinished = $completed + $failed + $rolledBack
    $successRate = if ($totalFinished -gt 0) { [Math]::Round(($completed / $totalFinished) * 100, 1) } else { 0 }

    $byType = $changes | Group-Object -Property ChangeType
    $byRisk = $changes | Group-Object -Property RiskLevel
    $byStatus = $changes | Group-Object -Property Status

    return [PSCustomObject]@{
        Period = $Period
        TotalChanges = $changes.Count
        Completed = $completed
        Failed = $failed
        RolledBack = $rolledBack
        SuccessRate = $successRate
        ByType = @{}
        ByRisk = @{}
        ByStatus = @{}
    } | ForEach-Object {
        foreach ($group in $byType) { $_.ByType[$group.Name] = $group.Count }
        foreach ($group in $byRisk) { $_.ByRisk[$group.Name] = $group.Count }
        foreach ($group in $byStatus) { $_.ByStatus[$group.Name] = $group.Count }
        $_
    }
}

#endregion

#region Import / Export

function Import-ChangeManagementDatabase {
    <#
    .SYNOPSIS
        Imports change management data from a JSON file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        return
    }

    try {
        $data = Get-Content -Path $Path -Raw | ConvertFrom-Json

        if ($data.ChangeRequests) {
            $script:ChangeRequests.Clear()
            foreach ($item in $data.ChangeRequests) {
                # Ensure VerificationRules is initialized for backward compatibility
                if (-not $item.PSObject.Properties['VerificationRules']) {
                    $item | Add-Member -NotePropertyName 'VerificationRules' -NotePropertyValue (New-Object System.Collections.ArrayList) -Force
                } elseif ($item.VerificationRules -isnot [System.Collections.ArrayList]) {
                    $rules = New-Object System.Collections.ArrayList
                    if ($item.VerificationRules) {
                        foreach ($r in $item.VerificationRules) {
                            [void]$rules.Add($r)
                        }
                    }
                    $item.VerificationRules = $rules
                }
                [void]$script:ChangeRequests.Add($item)
            }
        }

        if ($data.ChangeSteps) {
            $script:ChangeSteps.Clear()
            foreach ($item in $data.ChangeSteps) {
                [void]$script:ChangeSteps.Add($item)
            }
        }

        if ($data.ChangeDevices) {
            $script:ChangeDevices.Clear()
            foreach ($item in $data.ChangeDevices) {
                [void]$script:ChangeDevices.Add($item)
            }
        }

        if ($data.MaintenanceWindows) {
            $script:MaintenanceWindows.Clear()
            foreach ($item in $data.MaintenanceWindows) {
                [void]$script:MaintenanceWindows.Add($item)
            }
        }

        if ($data.ChangeHistory) {
            $script:ChangeHistory.Clear()
            foreach ($item in $data.ChangeHistory) {
                [void]$script:ChangeHistory.Add($item)
            }
        }
    }
    catch {
        Write-Warning "Failed to import change management database: $_"
    }
}

function Export-ChangeManagementDatabase {
    <#
    .SYNOPSIS
        Exports the change management database to a JSON file.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Path
    )

    if (-not $Path) {
        $Path = $script:DatabasePath
    }

    if (-not $Path) {
        throw "No database path specified"
    }

    $data = @{
        ChangeRequests = @($script:ChangeRequests)
        ChangeSteps = @($script:ChangeSteps)
        ChangeDevices = @($script:ChangeDevices)
        MaintenanceWindows = @($script:MaintenanceWindows)
        ChangeHistory = @($script:ChangeHistory)
        ExportDate = Get-Date
    }

    $data | ConvertTo-Json -Depth 10 | Set-Content -Path $Path

    return [PSCustomObject]@{
        Path = $Path
        ChangeCount = $script:ChangeRequests.Count
        WindowCount = $script:MaintenanceWindows.Count
    }
}

#endregion

#region Test Helpers

function Remove-TestChangeData {
    <#
    .SYNOPSIS
        Removes all test data from change management.
    #>
    [CmdletBinding()]
    param()

    $script:ChangeRequests.Clear()
    $script:ChangeSteps.Clear()
    $script:ChangeDevices.Clear()
    $script:MaintenanceWindows.Clear()
    $script:ChangeHistory.Clear()
}

#endregion

# Initialize on module load
Initialize-ChangeManagementDatabase

# Export functions
Export-ModuleMember -Function @(
    # Initialization
    'Initialize-ChangeManagementDatabase'

    # Change Request Management
    'New-ChangeRequest'
    'Get-ChangeRequest'
    'Update-ChangeRequest'
    'Remove-ChangeRequest'

    # Change Steps
    'Add-ChangeStep'
    'Get-ChangeStep'
    'Set-ChangeStepStatus'

    # Change Execution
    'Start-Change'
    'Complete-Change'
    'Fail-Change'
    'Get-ChangeDuration'
    'Get-ChangeProgress'

    # Rollback Management
    'Invoke-ChangeRollback'
    'Get-RollbackCommands'

    # Maintenance Windows
    'New-MaintenanceWindow'
    'Get-MaintenanceWindow'
    'Test-MaintenanceWindowConflict'
    'Test-BlackoutViolation'
    'Remove-MaintenanceWindow'

    # Pre/Post Change Capture
    'Add-ChangeDevice'
    'Set-ChangeDevicePostState'
    'Get-ChangeDevice'
    'Compare-ChangeConfigurations'

    # Impact Analysis
    'Get-ChangeImpact'
    'Get-ChangeEstimatedDuration'

    # Checklists
    'Get-ChangeChecklist'

    # Templates
    'Get-ChangeTemplate'

    # History
    'Add-ChangeHistoryEntry'
    'Get-ChangeHistory'

    # Post-Change Verification
    'New-VerificationRule'
    'Get-VerificationRule'
    'Invoke-ChangeVerification'
    'Test-ChangeSuccess'
    'Get-ChangeVerificationReport'
    'Export-ChangeVerificationReport'

    # Statistics
    'Get-ChangeStatistics'

    # Import / Export
    'Import-ChangeManagementDatabase'
    'Export-ChangeManagementDatabase'

    # Test Helpers
    'Remove-TestChangeData'
)
