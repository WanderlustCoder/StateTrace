# AlertRuleModule.psm1
# Alert rule engine for StateTrace monitoring
# Supports threshold-based rules, pattern matching, and state transitions

Set-StrictMode -Version Latest

# Module state
$script:AlertRules = [System.Collections.Generic.List[object]]::new()
$script:ActiveAlerts = [System.Collections.Concurrent.ConcurrentDictionary[string,object]]::new()
$script:AlertHistory = [System.Collections.Generic.List[object]]::new()
$script:AlertCallbacks = [System.Collections.Generic.List[scriptblock]]::new()
$script:MaxHistorySize = 1000

# Severity levels
$script:Severities = @{
    Critical = 1
    High = 2
    Medium = 3
    Low = 4
    Info = 5
}

function New-AlertRule {
    <#
    .SYNOPSIS
    Creates a new alert rule for monitoring.
    .PARAMETER Name
    Unique name for the rule.
    .PARAMETER Description
    Human-readable description of what this rule monitors.
    .PARAMETER Condition
    ScriptBlock that evaluates to $true when alert should fire. Receives $Context hashtable.
    .PARAMETER Severity
    Alert severity: Critical, High, Medium, Low, Info.
    .PARAMETER Category
    Category for grouping: Connectivity, Performance, Security, Capacity.
    .PARAMETER Cooldown
    Minimum seconds between repeated alerts for same rule. Default 300 (5 min).
    .PARAMETER AutoResolve
    Automatically resolve alert when condition becomes false.
    .PARAMETER Enabled
    Whether rule is active. Default $true.
    .EXAMPLE
    New-AlertRule -Name 'PortDown' -Condition { $Context.Status -eq 'notconnect' } -Severity High
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$Description = '',
        [Parameter(Mandatory)][scriptblock]$Condition,
        [ValidateSet('Critical', 'High', 'Medium', 'Low', 'Info')]
        [string]$Severity = 'Medium',
        [ValidateSet('Connectivity', 'Performance', 'Security', 'Capacity', 'Configuration', 'General')]
        [string]$Category = 'General',
        [int]$Cooldown = 300,
        [switch]$AutoResolve,
        [switch]$Enabled = $true
    )

    $rule = [PSCustomObject]@{
        Id = [guid]::NewGuid().ToString('N').Substring(0, 8)
        Name = $Name
        Description = $Description
        Condition = $Condition
        Severity = $Severity
        SeverityLevel = $script:Severities[$Severity]
        Category = $Category
        Cooldown = $Cooldown
        AutoResolve = $AutoResolve.IsPresent
        Enabled = $Enabled.IsPresent
        LastFired = $null
        FireCount = 0
        CreatedAt = [datetime]::UtcNow
    }

    # Remove existing rule with same name
    $existing = $script:AlertRules | Where-Object { $_.Name -eq $Name }
    if ($existing) {
        $script:AlertRules.Remove($existing) | Out-Null
    }

    [void]$script:AlertRules.Add($rule)
    Write-Verbose "[AlertRule] Created rule: $Name ($Severity)"

    return $rule
}

function Get-AlertRule {
    <#
    .SYNOPSIS
    Gets alert rules by name or returns all rules.
    #>
    [CmdletBinding()]
    param(
        [string]$Name,
        [string]$Category,
        [switch]$EnabledOnly
    )

    $rules = $script:AlertRules

    if ($Name) {
        $rules = $rules | Where-Object { $_.Name -like $Name }
    }
    if ($Category) {
        $rules = $rules | Where-Object { $_.Category -eq $Category }
    }
    if ($EnabledOnly.IsPresent) {
        $rules = $rules | Where-Object { $_.Enabled }
    }

    return $rules
}

function Remove-AlertRule {
    <#
    .SYNOPSIS
    Removes an alert rule by name or ID.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name
    )

    $rule = $script:AlertRules | Where-Object { $_.Name -eq $Name -or $_.Id -eq $Name }
    if ($rule) {
        $script:AlertRules.Remove($rule) | Out-Null
        Write-Verbose "[AlertRule] Removed rule: $Name"
        return $true
    }
    return $false
}

function Test-AlertCondition {
    <#
    .SYNOPSIS
    Evaluates a rule's condition against a context.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Rule,
        [Parameter(Mandatory)][hashtable]$Context
    )

    try {
        $result = & $Rule.Condition
        return [bool]$result
    } catch {
        Write-Verbose "[AlertRule] Condition evaluation failed for $($Rule.Name): $_"
        return $false
    }
}

function Invoke-AlertEvaluation {
    <#
    .SYNOPSIS
    Evaluates all enabled rules against provided context.
    .PARAMETER Context
    Hashtable with monitoring data (device info, metrics, etc).
    .PARAMETER Source
    Identifier for the source (hostname, IP, etc).
    .OUTPUTS
    Array of fired alerts.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [string]$Source = 'Unknown'
    )

    $now = [datetime]::UtcNow
    $firedAlerts = [System.Collections.Generic.List[object]]::new()

    foreach ($rule in ($script:AlertRules | Where-Object { $_.Enabled })) {
        # Check cooldown
        if ($rule.LastFired -and ($now - $rule.LastFired).TotalSeconds -lt $rule.Cooldown) {
            continue
        }

        $conditionMet = Test-AlertCondition -Rule $rule -Context $Context

        $alertKey = "$($rule.Id):$Source"

        if ($conditionMet) {
            # Create or update alert
            $alert = [PSCustomObject]@{
                Id = [guid]::NewGuid().ToString('N').Substring(0, 12)
                RuleId = $rule.Id
                RuleName = $rule.Name
                Source = $Source
                Severity = $rule.Severity
                SeverityLevel = $rule.SeverityLevel
                Category = $rule.Category
                Message = if ($Context.Message) { $Context.Message } else { $rule.Description }
                Context = $Context.Clone()
                FiredAt = $now
                ResolvedAt = $null
                State = 'Active'
                AcknowledgedBy = $null
                AcknowledgedAt = $null
            }

            $script:ActiveAlerts[$alertKey] = $alert
            [void]$firedAlerts.Add($alert)

            # Update rule stats
            $rule.LastFired = $now
            $rule.FireCount++

            # Add to history
            Add-AlertToHistory -Alert $alert

            # Invoke callbacks
            Invoke-AlertCallbacks -Alert $alert -EventType 'Fired'

            Write-Verbose "[AlertRule] Alert fired: $($rule.Name) from $Source"

        } elseif ($rule.AutoResolve) {
            # Check if there's an active alert to resolve
            $existingAlert = $null
            if ($script:ActiveAlerts.TryGetValue($alertKey, [ref]$existingAlert)) {
                $existingAlert.ResolvedAt = $now
                $existingAlert.State = 'Resolved'
                $script:ActiveAlerts.TryRemove($alertKey, [ref]$null) | Out-Null

                Invoke-AlertCallbacks -Alert $existingAlert -EventType 'Resolved'
                Write-Verbose "[AlertRule] Alert auto-resolved: $($rule.Name) from $Source"
            }
        }
    }

    return $firedAlerts
}

function Add-AlertToHistory {
    param([object]$Alert)

    [void]$script:AlertHistory.Add($Alert)

    # Trim history if needed
    while ($script:AlertHistory.Count -gt $script:MaxHistorySize) {
        $script:AlertHistory.RemoveAt(0)
    }
}

function Get-ActiveAlerts {
    <#
    .SYNOPSIS
    Returns all currently active alerts.
    #>
    [CmdletBinding()]
    param(
        [string]$Severity,
        [string]$Category,
        [string]$Source
    )

    $alerts = $script:ActiveAlerts.Values

    if ($Severity) {
        $alerts = $alerts | Where-Object { $_.Severity -eq $Severity }
    }
    if ($Category) {
        $alerts = $alerts | Where-Object { $_.Category -eq $Category }
    }
    if ($Source) {
        $alerts = $alerts | Where-Object { $_.Source -like $Source }
    }

    return $alerts | Sort-Object -Property SeverityLevel, FiredAt
}

function Get-AlertHistory {
    <#
    .SYNOPSIS
    Returns alert history.
    #>
    [CmdletBinding()]
    param(
        [int]$Last = 100,
        [datetime]$Since,
        [string]$Severity
    )

    $history = $script:AlertHistory

    if ($Since) {
        $history = $history | Where-Object { $_.FiredAt -ge $Since }
    }
    if ($Severity) {
        $history = $history | Where-Object { $_.Severity -eq $Severity }
    }

    return $history | Select-Object -Last $Last
}

function Set-AlertAcknowledged {
    <#
    .SYNOPSIS
    Acknowledges an active alert.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$AlertId,
        [string]$AcknowledgedBy = $env:USERNAME
    )

    foreach ($key in $script:ActiveAlerts.Keys) {
        $alert = $script:ActiveAlerts[$key]
        if ($alert.Id -eq $AlertId) {
            $alert.State = 'Acknowledged'
            $alert.AcknowledgedBy = $AcknowledgedBy
            $alert.AcknowledgedAt = [datetime]::UtcNow

            Invoke-AlertCallbacks -Alert $alert -EventType 'Acknowledged'
            return $true
        }
    }
    return $false
}

function Clear-Alert {
    <#
    .SYNOPSIS
    Manually clears/resolves an active alert.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$AlertId,
        [string]$ResolvedBy = $env:USERNAME
    )

    foreach ($key in $script:ActiveAlerts.Keys) {
        $alert = $script:ActiveAlerts[$key]
        if ($alert.Id -eq $AlertId) {
            $alert.State = 'Resolved'
            $alert.ResolvedAt = [datetime]::UtcNow
            $script:ActiveAlerts.TryRemove($key, [ref]$null) | Out-Null

            Invoke-AlertCallbacks -Alert $alert -EventType 'Resolved'
            return $true
        }
    }
    return $false
}

function Register-AlertCallback {
    <#
    .SYNOPSIS
    Registers a callback to be invoked when alerts fire/resolve.
    .PARAMETER Callback
    ScriptBlock receiving $Alert and $EventType parameters.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][scriptblock]$Callback
    )

    [void]$script:AlertCallbacks.Add($Callback)
}

function Invoke-AlertCallbacks {
    param(
        [object]$Alert,
        [string]$EventType
    )

    foreach ($callback in $script:AlertCallbacks) {
        try {
            & $callback $Alert $EventType
        } catch {
            Write-Verbose "[AlertRule] Callback failed: $_"
        }
    }
}

function Clear-AlertCallbacks {
    [CmdletBinding()]
    param()
    $script:AlertCallbacks.Clear()
}

function Get-AlertSummary {
    <#
    .SYNOPSIS
    Returns a summary of current alert state.
    #>
    [CmdletBinding()]
    param()

    $active = $script:ActiveAlerts.Values

    return [PSCustomObject]@{
        TotalActive = $active.Count
        Critical = ($active | Where-Object { $_.Severity -eq 'Critical' }).Count
        High = ($active | Where-Object { $_.Severity -eq 'High' }).Count
        Medium = ($active | Where-Object { $_.Severity -eq 'Medium' }).Count
        Low = ($active | Where-Object { $_.Severity -eq 'Low' }).Count
        Info = ($active | Where-Object { $_.Severity -eq 'Info' }).Count
        ByCategory = $active | Group-Object -Property Category | ForEach-Object {
            [PSCustomObject]@{ Category = $_.Name; Count = $_.Count }
        }
        RulesEnabled = ($script:AlertRules | Where-Object { $_.Enabled }).Count
        RulesTotal = $script:AlertRules.Count
        HistorySize = $script:AlertHistory.Count
    }
}

# Initialize default rules
function Initialize-DefaultAlertRules {
    <#
    .SYNOPSIS
    Creates a set of default monitoring rules.
    #>
    [CmdletBinding()]
    param()

    # Connectivity rules
    New-AlertRule -Name 'DeviceUnreachable' -Description 'Device is not responding to ICMP' `
        -Condition { $Context.PingStatus -eq 'Failed' } `
        -Severity Critical -Category Connectivity -AutoResolve

    New-AlertRule -Name 'PortDown' -Description 'Interface is in down state' `
        -Condition { $Context.Status -eq 'notconnect' -or $Context.Status -eq 'down' } `
        -Severity High -Category Connectivity -AutoResolve

    New-AlertRule -Name 'PortErrorDisabled' -Description 'Interface is error-disabled' `
        -Condition { $Context.Status -eq 'err-disabled' -or $Context.Status -eq 'errdisabled' } `
        -Severity Critical -Category Connectivity

    # Performance rules
    New-AlertRule -Name 'HighCPU' -Description 'CPU utilization exceeds 90%' `
        -Condition { $Context.CPUPercent -gt 90 } `
        -Severity High -Category Performance -AutoResolve

    New-AlertRule -Name 'HighMemory' -Description 'Memory utilization exceeds 85%' `
        -Condition { $Context.MemoryPercent -gt 85 } `
        -Severity High -Category Performance -AutoResolve

    New-AlertRule -Name 'HighBandwidth' -Description 'Interface bandwidth exceeds 80%' `
        -Condition { $Context.BandwidthPercent -gt 80 } `
        -Severity Medium -Category Performance -AutoResolve

    # Security rules
    New-AlertRule -Name 'AuthenticationFailure' -Description 'Authentication failed for port' `
        -Condition { $Context.AuthState -eq 'Unauthorized' -or $Context.AuthState -eq 'Failed' } `
        -Severity Medium -Category Security

    New-AlertRule -Name 'MACFlapping' -Description 'MAC address flapping detected' `
        -Condition { $Context.MACFlapping -eq $true } `
        -Severity High -Category Security

    Write-Verbose "[AlertRule] Initialized default rules"
}

Export-ModuleMember -Function @(
    'New-AlertRule',
    'Get-AlertRule',
    'Remove-AlertRule',
    'Invoke-AlertEvaluation',
    'Get-ActiveAlerts',
    'Get-AlertHistory',
    'Set-AlertAcknowledged',
    'Clear-Alert',
    'Register-AlertCallback',
    'Clear-AlertCallbacks',
    'Get-AlertSummary',
    'Initialize-DefaultAlertRules'
)
