# BulkOperationsModule.psm1
# Bulk operations for device configuration, deployment, and runbook execution

Set-StrictMode -Version Latest

#region Operation State
$script:ActiveOperations = @{}
$script:OperationHistory = [System.Collections.Generic.List[object]]::new()
$script:Runbooks = @{}

function Get-NewOperationId {
    return "OP-$(Get-Date -Format 'yyyyMMdd-HHmmss')-$([guid]::NewGuid().ToString().Substring(0, 8))"
}
#endregion

#region Device Selection
function Select-DevicesByFilter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Devices,

        [string]$Site,

        [string]$Status,

        [string]$Type,

        [string]$NamePattern,

        [string[]]$Tags,

        [scriptblock]$CustomFilter,

        [int]$Limit
    )

    $selected = $Devices

    if ($Site) {
        $selected = $selected | Where-Object { [string]::Equals($_.Site, $Site, [System.StringComparison]::OrdinalIgnoreCase) }
    }

    if ($Status) {
        $selected = $selected | Where-Object { $_.Status -eq $Status }
    }

    if ($Type) {
        $selected = $selected | Where-Object { $_.Type -eq $Type -or $_.DeviceType -eq $Type }
    }

    if ($NamePattern) {
        $selected = $selected | Where-Object { $_.Name -match $NamePattern -or $_.Hostname -match $NamePattern }
    }

    if ($Tags -and $Tags.Count -gt 0) {
        $selected = $selected | Where-Object {
            $deviceTags = $_.Tags
            if ($deviceTags) {
                $Tags | Where-Object { $deviceTags -contains $_ } | Measure-Object | Select-Object -ExpandProperty Count
            } else {
                0
            }
        } | Where-Object { $_ -gt 0 }
    }

    if ($CustomFilter) {
        $selected = $selected | Where-Object $CustomFilter
    }

    if ($Limit -and $Limit -gt 0) {
        $selected = $selected | Select-Object -First $Limit
    }

    return @($selected)
}

function Get-DeviceSelectionSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Devices
    )

    $summary = @{
        TotalDevices = @($Devices).Count
        BySite = @{}
        ByStatus = @{}
        ByType = @{}
    }

    foreach ($device in $Devices) {
        $site = if ($device.Site) { $device.Site } else { 'Unknown' }
        $status = if ($device.Status) { $device.Status } else { 'Unknown' }
        $type = if ($device.Type) { $device.Type } elseif ($device.DeviceType) { $device.DeviceType } else { 'Unknown' }

        if (-not $summary.BySite.ContainsKey($site)) { $summary.BySite[$site] = 0 }
        $summary.BySite[$site]++

        if (-not $summary.ByStatus.ContainsKey($status)) { $summary.ByStatus[$status] = 0 }
        $summary.ByStatus[$status]++

        if (-not $summary.ByType.ContainsKey($type)) { $summary.ByType[$type] = 0 }
        $summary.ByType[$type]++
    }

    return [PSCustomObject]$summary
}
#endregion

#region Pre-Deploy Validation
function Test-DeploymentPrerequisites {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$TargetDevices,

        [Parameter(Mandatory)]
        [object]$Configuration,

        [switch]$ValidateConnectivity,

        [switch]$ValidatePermissions,

        [switch]$DryRun
    )

    $result = @{
        Valid = $true
        Timestamp = [datetime]::UtcNow.ToString('o')
        TargetCount = @($TargetDevices).Count
        Checks = [System.Collections.Generic.List[object]]::new()
        Errors = [System.Collections.Generic.List[string]]::new()
        Warnings = [System.Collections.Generic.List[string]]::new()
    }

    # Check: Configuration structure
    $configCheck = @{
        Name = 'ConfigurationStructure'
        Status = 'Pass'
        Message = ''
    }

    if (-not $Configuration) {
        $configCheck.Status = 'Fail'
        $configCheck.Message = 'Configuration is null or empty'
        $result.Valid = $false
        $result.Errors.Add('Configuration is null or empty')
    } elseif ($Configuration -is [hashtable] -or $Configuration -is [PSCustomObject]) {
        $configCheck.Message = 'Configuration structure is valid'
    } else {
        $configCheck.Status = 'Warning'
        $configCheck.Message = "Unexpected configuration type: $($Configuration.GetType().Name)"
        $result.Warnings.Add($configCheck.Message)
    }

    $result.Checks.Add($configCheck)

    # Check: Target devices
    $targetCheck = @{
        Name = 'TargetDevices'
        Status = 'Pass'
        Message = ''
    }

    if (@($TargetDevices).Count -eq 0) {
        $targetCheck.Status = 'Fail'
        $targetCheck.Message = 'No target devices specified'
        $result.Valid = $false
        $result.Errors.Add('No target devices specified')
    } else {
        $targetCheck.Message = "$(@($TargetDevices).Count) devices targeted"
    }

    $result.Checks.Add($targetCheck)

    # Check: Device connectivity (if requested)
    if ($ValidateConnectivity) {
        $connectivityCheck = @{
            Name = 'DeviceConnectivity'
            Status = 'Pass'
            Message = ''
            Details = @()
        }

        $unreachable = 0
        foreach ($device in $TargetDevices) {
            $hostname = if ($device.Hostname) { $device.Hostname } elseif ($device.Name) { $device.Name } else { $null }
            if ($hostname) {
                $reachable = Test-Connection -ComputerName $hostname -Count 1 -Quiet -ErrorAction SilentlyContinue
                if (-not $reachable) {
                    $unreachable++
                    $connectivityCheck.Details += "$hostname unreachable"
                }
            }
        }

        if ($unreachable -gt 0) {
            $connectivityCheck.Status = 'Warning'
            $connectivityCheck.Message = "$unreachable devices unreachable"
            $result.Warnings.Add($connectivityCheck.Message)
        } else {
            $connectivityCheck.Message = 'All devices reachable'
        }

        $result.Checks.Add($connectivityCheck)
    }

    # Check: Template validation
    if ($Configuration.Template -or $Configuration.ConfigTemplate) {
        $templateCheck = @{
            Name = 'TemplateValidation'
            Status = 'Pass'
            Message = ''
        }

        $template = if ($Configuration.Template) { $Configuration.Template } else { $Configuration.ConfigTemplate }

        # Check for required placeholders
        $placeholders = [regex]::Matches($template, '\{\{(\w+)\}\}') | ForEach-Object { $_.Groups[1].Value }
        if ($placeholders.Count -gt 0) {
            $templateCheck.Message = "Template has $($placeholders.Count) placeholders: $($placeholders -join ', ')"

            # Verify placeholders can be resolved
            $unresolvedCount = 0
            foreach ($placeholder in $placeholders) {
                $canResolve = $false
                foreach ($device in $TargetDevices | Select-Object -First 1) {
                    if ($device.PSObject.Properties[$placeholder] -or
                        $Configuration.Variables.PSObject.Properties[$placeholder] -or
                        $Configuration.Variables[$placeholder]) {
                        $canResolve = $true
                        break
                    }
                }
                if (-not $canResolve) {
                    $unresolvedCount++
                }
            }

            if ($unresolvedCount -gt 0) {
                $templateCheck.Status = 'Warning'
                $templateCheck.Message += " ($unresolvedCount may be unresolved)"
                $result.Warnings.Add("$unresolvedCount template placeholders may be unresolved")
            }
        } else {
            $templateCheck.Message = 'Template has no placeholders'
        }

        $result.Checks.Add($templateCheck)
    }

    return [PSCustomObject]$result
}

function Test-ConfigurationTemplate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Template,

        [hashtable]$Variables,

        [object]$SampleDevice
    )

    $result = @{
        Valid = $true
        RenderedSample = $null
        Placeholders = @()
        UnresolvedPlaceholders = @()
        Errors = @()
    }

    # Find all placeholders
    $placeholders = [regex]::Matches($Template, '\{\{(\w+)\}\}') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
    $result.Placeholders = $placeholders

    # Try to render with sample device
    $rendered = $Template
    $unresolved = @()

    foreach ($placeholder in $placeholders) {
        $value = $null

        # Check variables first
        if ($Variables -and $Variables.ContainsKey($placeholder)) {
            $value = $Variables[$placeholder]
        }
        # Then check sample device
        elseif ($SampleDevice -and $SampleDevice.PSObject.Properties[$placeholder]) {
            $value = $SampleDevice.$placeholder
        }

        if ($null -ne $value) {
            $rendered = $rendered -replace "\{\{$placeholder\}\}", $value
        } else {
            $unresolved += $placeholder
        }
    }

    $result.UnresolvedPlaceholders = $unresolved
    $result.RenderedSample = $rendered

    if ($unresolved.Count -gt 0) {
        $result.Valid = $false
        $result.Errors += "Unresolved placeholders: $($unresolved -join ', ')"
    }

    return [PSCustomObject]$result
}
#endregion

#region Bulk Operations
function Start-BulkOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [object[]]$TargetDevices,

        [Parameter(Mandatory)]
        [scriptblock]$Action,

        [hashtable]$ActionParameters,

        [int]$MaxConcurrent = 5,

        [int]$TimeoutSeconds = 300,

        [switch]$StopOnFirstError,

        [switch]$CreateBackup
    )

    $operationId = Get-NewOperationId

    $operation = @{
        Id = $operationId
        Name = $Name
        Status = 'Running'
        StartTime = [datetime]::UtcNow
        EndTime = $null
        TargetCount = @($TargetDevices).Count
        CompletedCount = 0
        SuccessCount = 0
        FailedCount = 0
        SkippedCount = 0
        Results = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()
        Errors = [System.Collections.Generic.List[object]]::new()
        BackupId = $null
        CanRollback = $false
    }

    $script:ActiveOperations[$operationId] = $operation

    # Create backup if requested
    if ($CreateBackup) {
        $operation.BackupId = "BKP-$operationId"
        $operation.CanRollback = $true
        # Store current state for rollback
        $backupData = @{
            Id = $operation.BackupId
            Timestamp = [datetime]::UtcNow
            Devices = @($TargetDevices | ForEach-Object {
                @{
                    Id = if ($_.Id) { $_.Id } else { $_.Hostname }
                    OriginalState = $_ | ConvertTo-Json -Depth 5 -Compress
                }
            })
        }
        $operation.Backup = $backupData
    }

    # Execute on each device
    $deviceIndex = 0
    foreach ($device in $TargetDevices) {
        $deviceIndex++
        $deviceId = if ($device.Id) { $device.Id } elseif ($device.Hostname) { $device.Hostname } else { "Device$deviceIndex" }

        $deviceResult = @{
            DeviceId = $deviceId
            Status = 'Pending'
            StartTime = $null
            EndTime = $null
            Duration = $null
            Output = $null
            Error = $null
        }

        try {
            $deviceResult.StartTime = [datetime]::UtcNow
            $deviceResult.Status = 'Running'

            # Execute the action
            $params = @{ Device = $device }
            if ($ActionParameters) {
                foreach ($key in $ActionParameters.Keys) {
                    $params[$key] = $ActionParameters[$key]
                }
            }

            $output = & $Action @params

            $deviceResult.Status = 'Success'
            $deviceResult.Output = $output
            $operation.SuccessCount++

        } catch {
            $deviceResult.Status = 'Failed'
            $deviceResult.Error = $_.Exception.Message
            $operation.FailedCount++
            $operation.Errors.Add(@{
                DeviceId = $deviceId
                Error = $_.Exception.Message
                Timestamp = [datetime]::UtcNow
            })

            if ($StopOnFirstError) {
                # Mark remaining as skipped
                $operation.SkippedCount = $operation.TargetCount - $deviceIndex
                $operation.Status = 'Stopped'
                break
            }
        } finally {
            $deviceResult.EndTime = [datetime]::UtcNow
            if ($deviceResult.StartTime) {
                $deviceResult.Duration = ($deviceResult.EndTime - $deviceResult.StartTime).TotalMilliseconds
            }
            $operation.Results[$deviceId] = $deviceResult
            $operation.CompletedCount++
        }
    }

    # Finalize operation
    $operation.EndTime = [datetime]::UtcNow
    if ($operation.Status -ne 'Stopped') {
        $operation.Status = if ($operation.FailedCount -eq 0) { 'Completed' } else { 'CompletedWithErrors' }
    }

    $script:OperationHistory.Add($operation)

    return [PSCustomObject]$operation
}

function Get-BulkOperationStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OperationId
    )

    if ($script:ActiveOperations.ContainsKey($OperationId)) {
        return [PSCustomObject]$script:ActiveOperations[$OperationId]
    }

    $historical = $script:OperationHistory | Where-Object { $_.Id -eq $OperationId } | Select-Object -First 1
    if ($historical) {
        return [PSCustomObject]$historical
    }

    return $null
}

function Get-BulkOperationHistory {
    [CmdletBinding()]
    param(
        [int]$Last = 10,

        [string]$Name,

        [ValidateSet('Completed', 'CompletedWithErrors', 'Stopped', 'Running', 'All')]
        [string]$Status = 'All'
    )

    $history = $script:OperationHistory.ToArray()

    if ($Name) {
        $history = $history | Where-Object { $_.Name -eq $Name }
    }

    if ($Status -ne 'All') {
        $history = $history | Where-Object { $_.Status -eq $Status }
    }

    return $history | Select-Object -Last $Last
}

function Stop-BulkOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OperationId
    )

    if ($script:ActiveOperations.ContainsKey($OperationId)) {
        $operation = $script:ActiveOperations[$OperationId]
        $operation.Status = 'Stopped'
        $operation.EndTime = [datetime]::UtcNow
        return [PSCustomObject]$operation
    }

    throw "Operation not found or already completed: $OperationId"
}
#endregion

#region Progress Tracking
function Get-OperationProgress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OperationId
    )

    $operation = Get-BulkOperationStatus -OperationId $OperationId
    if (-not $operation) {
        return $null
    }

    $progress = @{
        OperationId = $operation.Id
        Name = $operation.Name
        Status = $operation.Status
        PercentComplete = 0
        Completed = $operation.CompletedCount
        Total = $operation.TargetCount
        Succeeded = $operation.SuccessCount
        Failed = $operation.FailedCount
        Skipped = $operation.SkippedCount
        ElapsedTime = $null
        EstimatedTimeRemaining = $null
        CurrentRate = $null
    }

    if ($operation.TargetCount -gt 0) {
        $progress.PercentComplete = [math]::Round(($operation.CompletedCount / $operation.TargetCount) * 100, 1)
    }

    if ($operation.StartTime) {
        $elapsed = if ($operation.EndTime) {
            $operation.EndTime - $operation.StartTime
        } else {
            [datetime]::UtcNow - $operation.StartTime
        }
        $progress.ElapsedTime = $elapsed.ToString('hh\:mm\:ss')

        if ($operation.CompletedCount -gt 0 -and $operation.Status -eq 'Running') {
            $ratePerSecond = $operation.CompletedCount / $elapsed.TotalSeconds
            $progress.CurrentRate = [math]::Round($ratePerSecond, 2)

            $remaining = $operation.TargetCount - $operation.CompletedCount
            if ($ratePerSecond -gt 0) {
                $secondsRemaining = $remaining / $ratePerSecond
                $progress.EstimatedTimeRemaining = [timespan]::FromSeconds($secondsRemaining).ToString('hh\:mm\:ss')
            }
        }
    }

    return [PSCustomObject]$progress
}

function Write-OperationProgress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OperationId,

        [switch]$NoNewLine
    )

    $progress = Get-OperationProgress -OperationId $OperationId
    if (-not $progress) {
        Write-Host "Operation not found: $OperationId" -ForegroundColor Red
        return
    }

    $statusColor = switch ($progress.Status) {
        'Running' { 'Yellow' }
        'Completed' { 'Green' }
        'CompletedWithErrors' { 'DarkYellow' }
        'Stopped' { 'Red' }
        default { 'Gray' }
    }

    $bar = ''
    $barWidth = 30
    $filled = [math]::Floor(($progress.PercentComplete / 100) * $barWidth)
    $bar = ('#' * $filled) + ('-' * ($barWidth - $filled))

    $line = "[{0}] {1}% | {2}/{3} | Success: {4} Failed: {5}" -f `
        $bar,
        $progress.PercentComplete,
        $progress.Completed,
        $progress.Total,
        $progress.Succeeded,
        $progress.Failed

    if ($progress.EstimatedTimeRemaining) {
        $line += " | ETA: $($progress.EstimatedTimeRemaining)"
    }

    if ($NoNewLine) {
        Write-Host "`r$line" -NoNewline -ForegroundColor $statusColor
    } else {
        Write-Host $line -ForegroundColor $statusColor
    }
}
#endregion

#region Rollback
function Invoke-OperationRollback {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OperationId,

        [scriptblock]$RollbackAction,

        [switch]$Force
    )

    $operation = Get-BulkOperationStatus -OperationId $OperationId
    if (-not $operation) {
        throw "Operation not found: $OperationId"
    }

    if (-not $operation.CanRollback -and -not $Force) {
        throw "Operation does not support rollback. Use -Force to attempt anyway."
    }

    $rollbackResult = @{
        OperationId = $OperationId
        RollbackId = "RB-$OperationId"
        Status = 'Running'
        StartTime = [datetime]::UtcNow
        EndTime = $null
        RestoredCount = 0
        FailedCount = 0
        Errors = [System.Collections.Generic.List[object]]::new()
    }

    if ($operation.Backup -and $RollbackAction) {
        foreach ($deviceBackup in $operation.Backup.Devices) {
            try {
                $originalState = $deviceBackup.OriginalState | ConvertFrom-Json
                & $RollbackAction -DeviceId $deviceBackup.Id -OriginalState $originalState
                $rollbackResult.RestoredCount++
            } catch {
                $rollbackResult.FailedCount++
                $rollbackResult.Errors.Add(@{
                    DeviceId = $deviceBackup.Id
                    Error = $_.Exception.Message
                })
            }
        }
    }

    $rollbackResult.EndTime = [datetime]::UtcNow
    $rollbackResult.Status = if ($rollbackResult.FailedCount -eq 0) { 'Completed' } else { 'CompletedWithErrors' }

    return [PSCustomObject]$rollbackResult
}

function Get-RollbackCapability {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OperationId
    )

    $operation = Get-BulkOperationStatus -OperationId $OperationId
    if (-not $operation) {
        return @{
            OperationId = $OperationId
            CanRollback = $false
            Reason = 'Operation not found'
        }
    }

    return @{
        OperationId = $OperationId
        CanRollback = $operation.CanRollback
        BackupId = $operation.BackupId
        BackupDeviceCount = if ($operation.Backup) { $operation.Backup.Devices.Count } else { 0 }
        Reason = if ($operation.CanRollback) { 'Backup available' } else { 'No backup created' }
    }
}
#endregion

#region Runbook Execution
function Register-Runbook {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Description,

        [Parameter(Mandatory)]
        [object[]]$Steps,

        [string[]]$RequiredParameters,

        [hashtable]$DefaultParameters,

        [string]$Category = 'General'
    )

    $runbook = @{
        Name = $Name
        Description = $Description
        Steps = $Steps
        RequiredParameters = $RequiredParameters
        DefaultParameters = $DefaultParameters
        Category = $Category
        RegisteredAt = [datetime]::UtcNow
        Version = '1.0'
    }

    $script:Runbooks[$Name] = $runbook

    return [PSCustomObject]$runbook
}

function Get-Runbook {
    [CmdletBinding()]
    param(
        [string]$Name,

        [string]$Category
    )

    if ($Name) {
        if ($script:Runbooks.ContainsKey($Name)) {
            return [PSCustomObject]$script:Runbooks[$Name]
        }
        return $null
    }

    $runbooks = $script:Runbooks.Values

    if ($Category) {
        $runbooks = $runbooks | Where-Object { $_.Category -eq $Category }
    }

    return $runbooks | ForEach-Object { [PSCustomObject]$_ }
}

function Invoke-Runbook {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [object[]]$TargetDevices,

        [hashtable]$Parameters,

        [switch]$WhatIf,

        [switch]$StopOnError
    )

    $runbook = Get-Runbook -Name $Name
    if (-not $runbook) {
        throw "Runbook not found: $Name"
    }

    # Validate required parameters
    if ($runbook.RequiredParameters) {
        foreach ($required in $runbook.RequiredParameters) {
            if (-not $Parameters -or -not $Parameters.ContainsKey($required)) {
                throw "Missing required parameter: $required"
            }
        }
    }

    # Merge with defaults
    $effectiveParams = @{}
    if ($runbook.DefaultParameters) {
        foreach ($key in $runbook.DefaultParameters.Keys) {
            $effectiveParams[$key] = $runbook.DefaultParameters[$key]
        }
    }
    if ($Parameters) {
        foreach ($key in $Parameters.Keys) {
            $effectiveParams[$key] = $Parameters[$key]
        }
    }

    $executionResult = @{
        RunbookName = $Name
        ExecutionId = "RUN-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Status = 'Running'
        StartTime = [datetime]::UtcNow
        EndTime = $null
        Parameters = $effectiveParams
        TargetCount = @($TargetDevices).Count
        StepResults = [System.Collections.Generic.List[object]]::new()
        WhatIf = $WhatIf.IsPresent
    }

    $stepIndex = 0
    foreach ($step in $runbook.Steps) {
        $stepIndex++
        $stepResult = @{
            StepNumber = $stepIndex
            Name = if ($step.Name) { $step.Name } else { "Step $stepIndex" }
            Status = 'Pending'
            StartTime = $null
            EndTime = $null
            Output = $null
            Error = $null
        }

        try {
            $stepResult.StartTime = [datetime]::UtcNow
            $stepResult.Status = 'Running'

            if ($WhatIf) {
                $stepResult.Output = "WhatIf: Would execute $($stepResult.Name)"
                $stepResult.Status = 'WhatIf'
            } else {
                if ($step.Action -is [scriptblock]) {
                    $output = & $step.Action -Devices $TargetDevices -Parameters $effectiveParams
                    $stepResult.Output = $output
                    $stepResult.Status = 'Success'
                } elseif ($step.Command) {
                    $stepResult.Output = "Command: $($step.Command)"
                    $stepResult.Status = 'Success'
                } else {
                    $stepResult.Status = 'Skipped'
                    $stepResult.Output = 'No action defined'
                }
            }
        } catch {
            $stepResult.Status = 'Failed'
            $stepResult.Error = $_.Exception.Message

            if ($StopOnError) {
                $executionResult.Status = 'Stopped'
                $executionResult.StepResults.Add($stepResult)
                break
            }
        } finally {
            $stepResult.EndTime = [datetime]::UtcNow
            $executionResult.StepResults.Add($stepResult)
        }
    }

    $executionResult.EndTime = [datetime]::UtcNow

    $failedSteps = $executionResult.StepResults | Where-Object { $_.Status -eq 'Failed' }
    if ($executionResult.Status -ne 'Stopped') {
        $executionResult.Status = if ($failedSteps.Count -eq 0) { 'Completed' } else { 'CompletedWithErrors' }
    }

    return [PSCustomObject]$executionResult
}

function New-RunbookStep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [string]$Description,

        [scriptblock]$Action,

        [string]$Command,

        [int]$TimeoutSeconds = 300,

        [switch]$ContinueOnError
    )

    return @{
        Name = $Name
        Description = $Description
        Action = $Action
        Command = $Command
        TimeoutSeconds = $TimeoutSeconds
        ContinueOnError = $ContinueOnError.IsPresent
    }
}
#endregion

#region Built-in Runbooks
# Register sample runbooks
Register-Runbook -Name 'HealthCheck' -Description 'Run health checks on target devices' -Category 'Maintenance' -Steps @(
    (New-RunbookStep -Name 'Validate Connectivity' -Description 'Check device reachability' -Action {
        param($Devices, $Parameters)
        return @{ Checked = $Devices.Count }
    }),
    (New-RunbookStep -Name 'Collect Status' -Description 'Gather device status' -Action {
        param($Devices, $Parameters)
        return @{ Collected = $Devices.Count }
    }),
    (New-RunbookStep -Name 'Generate Report' -Description 'Create health report' -Action {
        param($Devices, $Parameters)
        return @{ Report = 'Generated' }
    })
)

Register-Runbook -Name 'ConfigBackup' -Description 'Backup device configurations' -Category 'Maintenance' -Steps @(
    (New-RunbookStep -Name 'Create Backup Directory' -Action {
        param($Devices, $Parameters)
        return @{ Directory = 'Created' }
    }),
    (New-RunbookStep -Name 'Export Configurations' -Action {
        param($Devices, $Parameters)
        return @{ Exported = $Devices.Count }
    }),
    (New-RunbookStep -Name 'Verify Backups' -Action {
        param($Devices, $Parameters)
        return @{ Verified = $true }
    })
)
#endregion

#region Exports
Export-ModuleMember -Function @(
    'Select-DevicesByFilter',
    'Get-DeviceSelectionSummary',
    'Test-DeploymentPrerequisites',
    'Test-ConfigurationTemplate',
    'Start-BulkOperation',
    'Get-BulkOperationStatus',
    'Get-BulkOperationHistory',
    'Stop-BulkOperation',
    'Get-OperationProgress',
    'Write-OperationProgress',
    'Invoke-OperationRollback',
    'Get-RollbackCapability',
    'Register-Runbook',
    'Get-Runbook',
    'Invoke-Runbook',
    'New-RunbookStep'
)
#endregion
