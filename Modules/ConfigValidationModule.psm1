Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Configuration Validation and Compliance module.

.DESCRIPTION
    Provides configuration validation against defined standards and rules.
    Includes built-in security baselines, compliance checking, and reporting.
    Part of Plan U - Configuration Templates & Validation.
#>

#region Data Structures

<#
.SYNOPSIS
    Creates a new validation rule.
#>
function New-ValidationRule {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RuleID,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter()]
        [string]$Description,

        [Parameter()]
        [ValidateSet('Critical', 'High', 'Medium', 'Low', 'Info')]
        [string]$Severity = 'Medium',

        [Parameter()]
        [ValidateSet('Security', 'Performance', 'Standard', 'BestPractice', 'Custom')]
        [string]$Category = 'Standard',

        [Parameter()]
        [string]$Match,

        [Parameter()]
        [string]$Pattern,

        [Parameter()]
        [switch]$Required,

        [Parameter()]
        [switch]$Prohibited,

        [Parameter()]
        [string]$Remediation,

        [Parameter()]
        [string]$Vendor,

        [Parameter()]
        [string[]]$Tags
    )

    [PSCustomObject]@{
        RuleID       = $RuleID
        Name         = $Name
        Description  = $Description
        Severity     = $Severity
        Category     = $Category
        Match        = $Match
        Pattern      = $Pattern
        Required     = $Required.IsPresent
        Prohibited   = $Prohibited.IsPresent
        Remediation  = $Remediation
        Vendor       = $Vendor
        Tags         = if ($Tags) { $Tags } else { @() }
    }
}

<#
.SYNOPSIS
    Creates a new validation standard (collection of rules).
#>
function New-ValidationStandard {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter()]
        [string]$Description,

        [Parameter()]
        [string]$Version = '1.0',

        [Parameter()]
        [string]$Vendor,

        [Parameter()]
        [PSCustomObject[]]$Rules,

        [Parameter()]
        [string]$Author,

        [Parameter()]
        [string]$Notes
    )

    $now = Get-Date

    [PSCustomObject]@{
        StandardID   = [guid]::NewGuid().ToString()
        Name         = $Name
        Description  = $Description
        Version      = $Version
        Vendor       = $Vendor
        Rules        = if ($Rules) { @($Rules) } else { @() }
        Author       = $Author
        Notes        = $Notes
        CreatedDate  = $now
        ModifiedDate = $now
    }
}

<#
.SYNOPSIS
    Creates a validation result object.
#>
function New-ValidationResult {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RuleID,

        [Parameter(Mandatory = $true)]
        [string]$RuleName,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Pass', 'Fail', 'Skip', 'Error')]
        [string]$Status,

        [Parameter()]
        [string]$Severity,

        [Parameter()]
        [string]$Message,

        [Parameter()]
        [int]$LineNumber,

        [Parameter()]
        [string]$MatchedText,

        [Parameter()]
        [string]$Remediation
    )

    [PSCustomObject]@{
        RuleID      = $RuleID
        RuleName    = $RuleName
        Status      = $Status
        Severity    = $Severity
        Message     = $Message
        LineNumber  = $LineNumber
        MatchedText = $MatchedText
        Remediation = $Remediation
    }
}

#endregion

#region Validation Engine

<#
.SYNOPSIS
    Tests a configuration against a validation standard.
#>
function Test-ConfigCompliance {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Config,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Standard,

        [Parameter()]
        [string]$DeviceName = 'Unknown'
    )

    $results = @()
    $passed = 0
    $failed = 0
    $skipped = 0

    $lines = $Config -split "`n"

    foreach ($rule in $Standard.Rules) {
        $result = Test-SingleRule -Config $Config -Lines $lines -Rule $rule

        $results += $result

        switch ($result.Status) {
            'Pass' { $passed++ }
            'Fail' { $failed++ }
            'Skip' { $skipped++ }
        }
    }

    $total = $Standard.Rules.Count
    $score = if ($total -gt 0) { [Math]::Round(($passed / $total) * 100, 1) } else { 100 }

    [PSCustomObject]@{
        DeviceName     = $DeviceName
        StandardName   = $Standard.Name
        StandardVersion = $Standard.Version
        TotalRules     = $total
        Passed         = $passed
        Failed         = $failed
        Skipped        = $skipped
        Score          = $score
        Results        = $results
        Critical       = @($results | Where-Object { $_.Status -eq 'Fail' -and $_.Severity -eq 'Critical' }).Count
        High           = @($results | Where-Object { $_.Status -eq 'Fail' -and $_.Severity -eq 'High' }).Count
        Medium         = @($results | Where-Object { $_.Status -eq 'Fail' -and $_.Severity -eq 'Medium' }).Count
        Low            = @($results | Where-Object { $_.Status -eq 'Fail' -and $_.Severity -eq 'Low' }).Count
        CheckedAt      = Get-Date
    }
}

<#
.SYNOPSIS
    Tests a single validation rule against config.
#>
function Test-SingleRule {
    [CmdletBinding()]
    param(
        [string]$Config,
        [string[]]$Lines,
        [PSCustomObject]$Rule
    )

    $searchText = if ($Rule.Match) { $Rule.Match } elseif ($Rule.Pattern) { $Rule.Pattern } else { $null }

    if (-not $searchText) {
        return New-ValidationResult -RuleID $Rule.RuleID -RuleName $Rule.Name `
            -Status 'Skip' -Severity $Rule.Severity `
            -Message 'No match criteria defined'
    }

    $isRegex = [bool]$Rule.Pattern
    $found = $false
    $lineNumber = 0
    $matchedText = ''

    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i]

        if ($isRegex) {
            if ($line -match $searchText) {
                $found = $true
                $lineNumber = $i + 1
                $matchedText = $line.Trim()
                break
            }
        }
        else {
            if ($line -like "*$searchText*") {
                $found = $true
                $lineNumber = $i + 1
                $matchedText = $line.Trim()
                break
            }
        }
    }

    # Evaluate result based on Required/Prohibited
    if ($Rule.Required) {
        if ($found) {
            return New-ValidationResult -RuleID $Rule.RuleID -RuleName $Rule.Name `
                -Status 'Pass' -Severity $Rule.Severity `
                -Message 'Required setting found' -LineNumber $lineNumber `
                -MatchedText $matchedText
        }
        else {
            return New-ValidationResult -RuleID $Rule.RuleID -RuleName $Rule.Name `
                -Status 'Fail' -Severity $Rule.Severity `
                -Message 'Required setting not found' `
                -Remediation $Rule.Remediation
        }
    }
    elseif ($Rule.Prohibited) {
        if ($found) {
            return New-ValidationResult -RuleID $Rule.RuleID -RuleName $Rule.Name `
                -Status 'Fail' -Severity $Rule.Severity `
                -Message 'Prohibited setting found' -LineNumber $lineNumber `
                -MatchedText $matchedText `
                -Remediation $Rule.Remediation
        }
        else {
            return New-ValidationResult -RuleID $Rule.RuleID -RuleName $Rule.Name `
                -Status 'Pass' -Severity $Rule.Severity `
                -Message 'Prohibited setting not present'
        }
    }
    else {
        # Just checking existence
        $status = if ($found) { 'Pass' } else { 'Fail' }
        return New-ValidationResult -RuleID $Rule.RuleID -RuleName $Rule.Name `
            -Status $status -Severity $Rule.Severity `
            -Message $(if ($found) { 'Setting found' } else { 'Setting not found' }) `
            -LineNumber $lineNumber -MatchedText $matchedText `
            -Remediation $(if (-not $found) { $Rule.Remediation } else { $null })
    }
}

<#
.SYNOPSIS
    Tests multiple configurations against a standard.
#>
function Test-BulkCompliance {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Configs,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Standard
    )

    $results = @()

    foreach ($deviceName in $Configs.Keys) {
        $config = $Configs[$deviceName]
        $result = Test-ConfigCompliance -Config $config -Standard $Standard -DeviceName $deviceName
        $results += $result
    }

    $results
}

#endregion

#region Built-in Standards

<#
.SYNOPSIS
    Gets built-in security baseline standard.
#>
function Get-SecurityBaseline {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [ValidateSet('Cisco_IOS', 'Arista_EOS', 'Generic')]
        [string]$Vendor = 'Cisco_IOS'
    )

    $rules = @()

    if ($Vendor -eq 'Cisco_IOS' -or $Vendor -eq 'Generic') {
        $rules += New-ValidationRule -RuleID 'SEC-001' -Name 'SSH Version 2' `
            -Description 'SSH version 2 must be enabled' `
            -Severity 'Critical' -Category 'Security' `
            -Match 'ip ssh version 2' -Required `
            -Remediation 'ip ssh version 2'

        $rules += New-ValidationRule -RuleID 'SEC-002' -Name 'Telnet Disabled on VTY' `
            -Description 'Telnet must not be allowed on VTY lines' `
            -Severity 'Critical' -Category 'Security' `
            -Match 'transport input telnet' -Prohibited `
            -Remediation 'line vty 0 15`n transport input ssh'

        $rules += New-ValidationRule -RuleID 'SEC-003' -Name 'Password Encryption' `
            -Description 'Password encryption service must be enabled' `
            -Severity 'High' -Category 'Security' `
            -Match 'service password-encryption' -Required `
            -Remediation 'service password-encryption'

        $rules += New-ValidationRule -RuleID 'SEC-004' -Name 'Enable Secret Set' `
            -Description 'Enable secret must be configured' `
            -Severity 'Critical' -Category 'Security' `
            -Pattern '^enable secret' -Required `
            -Remediation 'enable secret <password>'

        $rules += New-ValidationRule -RuleID 'SEC-005' -Name 'No HTTP Server' `
            -Description 'HTTP server must be disabled' `
            -Severity 'High' -Category 'Security' `
            -Pattern '^ip http server$' -Prohibited `
            -Remediation 'no ip http server'

        $rules += New-ValidationRule -RuleID 'SEC-006' -Name 'HTTPS Server Only' `
            -Description 'Only HTTPS server should be enabled if web access needed' `
            -Severity 'Medium' -Category 'Security' `
            -Match 'ip http secure-server' -Required `
            -Remediation 'ip http secure-server'

        $rules += New-ValidationRule -RuleID 'SEC-007' -Name 'Logging Enabled' `
            -Description 'Logging to buffer must be enabled' `
            -Severity 'Medium' -Category 'Security' `
            -Pattern '^logging buffered' -Required `
            -Remediation 'logging buffered 16384'

        $rules += New-ValidationRule -RuleID 'SEC-008' -Name 'Console Timeout' `
            -Description 'Console timeout should be configured' `
            -Severity 'Low' -Category 'Security' `
            -Pattern 'exec-timeout \d+ \d+' -Required `
            -Remediation 'line con 0`n exec-timeout 10 0'

        $rules += New-ValidationRule -RuleID 'SEC-009' -Name 'VTY Access List' `
            -Description 'VTY lines should have access-class configured' `
            -Severity 'High' -Category 'Security' `
            -Pattern 'access-class \d+ in' -Required `
            -Remediation 'line vty 0 15`n access-class <acl> in'

        $rules += New-ValidationRule -RuleID 'SEC-010' -Name 'NTP Authentication' `
            -Description 'NTP authentication should be configured' `
            -Severity 'Medium' -Category 'Security' `
            -Match 'ntp authenticate' -Required `
            -Remediation 'ntp authenticate`nntp authentication-key 1 md5 <key>'
    }

    if ($Vendor -eq 'Arista_EOS') {
        $rules += New-ValidationRule -RuleID 'SEC-001' -Name 'SSH Enabled' `
            -Description 'SSH management must be enabled' `
            -Severity 'Critical' -Category 'Security' `
            -Match 'management ssh' -Required `
            -Remediation 'management ssh'

        $rules += New-ValidationRule -RuleID 'SEC-002' -Name 'Telnet Disabled' `
            -Description 'Telnet management must be disabled' `
            -Severity 'Critical' -Category 'Security' `
            -Match 'management telnet' -Prohibited `
            -Remediation 'no management telnet'

        $rules += New-ValidationRule -RuleID 'SEC-003' -Name 'Enable Secret' `
            -Description 'Enable secret must be configured' `
            -Severity 'Critical' -Category 'Security' `
            -Pattern '^enable secret' -Required `
            -Remediation 'enable secret sha512 <hash>'

        $rules += New-ValidationRule -RuleID 'SEC-004' -Name 'AAA Enabled' `
            -Description 'AAA must be enabled' `
            -Severity 'High' -Category 'Security' `
            -Match 'aaa authorization exec' -Required `
            -Remediation 'aaa authorization exec default local'

        $rules += New-ValidationRule -RuleID 'SEC-005' -Name 'Logging Configured' `
            -Description 'Logging must be configured' `
            -Severity 'Medium' -Category 'Security' `
            -Pattern '^logging host' -Required `
            -Remediation 'logging host <ip>'
    }

    New-ValidationStandard -Name "Security Baseline - $Vendor" `
        -Description 'Security configuration baseline' `
        -Version '2.0' -Vendor $Vendor -Rules $rules
}

<#
.SYNOPSIS
    Gets operational best practices standard.
#>
function Get-OperationalBaseline {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $rules = @(
        New-ValidationRule -RuleID 'OPS-001' -Name 'NTP Configured' `
            -Description 'NTP server must be configured' `
            -Severity 'High' -Category 'Standard' `
            -Pattern '^ntp server' -Required `
            -Remediation 'ntp server <ip>'

        New-ValidationRule -RuleID 'OPS-002' -Name 'Syslog Server' `
            -Description 'Syslog server must be configured' `
            -Severity 'High' -Category 'Standard' `
            -Pattern '^logging (host )?[\d\.]+' -Required `
            -Remediation 'logging host <ip>'

        New-ValidationRule -RuleID 'OPS-003' -Name 'SNMP Configured' `
            -Description 'SNMP must be configured for monitoring' `
            -Severity 'Medium' -Category 'Standard' `
            -Pattern '^snmp-server' -Required `
            -Remediation 'snmp-server community <string> RO'

        New-ValidationRule -RuleID 'OPS-004' -Name 'Banner Configured' `
            -Description 'Login banner must be configured' `
            -Severity 'Low' -Category 'Standard' `
            -Match 'banner login' -Required `
            -Remediation 'banner login ^Warning^'

        New-ValidationRule -RuleID 'OPS-005' -Name 'Domain Name' `
            -Description 'Domain name should be configured' `
            -Severity 'Low' -Category 'Standard' `
            -Pattern '^ip domain.name' -Required `
            -Remediation 'ip domain-name <domain>'

        New-ValidationRule -RuleID 'OPS-006' -Name 'Timestamps Enabled' `
            -Description 'Timestamp logging should be enabled' `
            -Severity 'Low' -Category 'BestPractice' `
            -Match 'service timestamps log datetime' -Required `
            -Remediation 'service timestamps log datetime msec localtime show-timezone'

        New-ValidationRule -RuleID 'OPS-007' -Name 'Archive Config' `
            -Description 'Archive configuration should be enabled' `
            -Severity 'Info' -Category 'BestPractice' `
            -Match 'archive' -Required `
            -Remediation 'archive`n path flash:archive`n write-memory'
    )

    New-ValidationStandard -Name 'Operational Baseline' `
        -Description 'Operational best practices' `
        -Version '1.0' -Rules $rules
}

<#
.SYNOPSIS
    Gets switching best practices standard.
#>
function Get-SwitchingBaseline {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $rules = @(
        New-ValidationRule -RuleID 'SW-001' -Name 'STP Mode' `
            -Description 'Rapid PVST+ or MST should be configured' `
            -Severity 'Medium' -Category 'BestPractice' `
            -Pattern 'spanning-tree mode (rapid-pvst|mst)' -Required `
            -Remediation 'spanning-tree mode rapid-pvst'

        New-ValidationRule -RuleID 'SW-002' -Name 'BPDU Guard' `
            -Description 'BPDU Guard should be enabled globally' `
            -Severity 'Medium' -Category 'Security' `
            -Match 'spanning-tree portfast bpduguard default' -Required `
            -Remediation 'spanning-tree portfast bpduguard default'

        New-ValidationRule -RuleID 'SW-003' -Name 'Root Guard' `
            -Description 'Root guard should be on uplinks' `
            -Severity 'Low' -Category 'BestPractice' `
            -Match 'spanning-tree guard root' -Required `
            -Remediation 'interface <uplink>`n spanning-tree guard root'

        New-ValidationRule -RuleID 'SW-004' -Name 'Storm Control' `
            -Description 'Storm control should be configured' `
            -Severity 'Medium' -Category 'Performance' `
            -Match 'storm-control' -Required `
            -Remediation 'storm-control broadcast level 10'

        New-ValidationRule -RuleID 'SW-005' -Name 'Unused Ports Shutdown' `
            -Description 'Unused ports should be administratively down' `
            -Severity 'Low' -Category 'Security' `
            -Match 'shutdown' -Required `
            -Remediation 'interface range <unused>`n shutdown'

        New-ValidationRule -RuleID 'SW-006' -Name 'Native VLAN' `
            -Description 'Native VLAN should not be VLAN 1' `
            -Severity 'Medium' -Category 'Security' `
            -Pattern 'switchport trunk native vlan [2-9]|[1-9]\d' -Required `
            -Remediation 'switchport trunk native vlan 999'
    )

    New-ValidationStandard -Name 'Switching Baseline' `
        -Description 'Layer 2 switching best practices' `
        -Version '1.0' -Rules $rules
}

<#
.SYNOPSIS
    Gets all built-in standards.
#>
function Get-BuiltInStandards {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param()

    @(
        Get-SecurityBaseline -Vendor 'Cisco_IOS'
        Get-SecurityBaseline -Vendor 'Arista_EOS'
        Get-OperationalBaseline
        Get-SwitchingBaseline
    )
}

#endregion

#region Standards Library

# Module-level storage
$script:StandardsLibrary = @{
    Standards = New-Object System.Collections.ArrayList
}

<#
.SYNOPSIS
    Initializes a new standards library.
#>
function New-StandardsLibrary {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    @{
        Standards = New-Object System.Collections.ArrayList
    }
}

<#
.SYNOPSIS
    Adds a standard to the library.
#>
function Add-ValidationStandard {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSCustomObject]$Standard,

        [Parameter()]
        [hashtable]$Library
    )

    process {
        $lib = if ($Library) { $Library } else { $script:StandardsLibrary }

        $existing = $lib.Standards | Where-Object { $_.Name -eq $Standard.Name }
        if ($existing) {
            Write-Warning "Standard '$($Standard.Name)' already exists"
            return $null
        }

        $lib.Standards.Add($Standard) | Out-Null
        $Standard
    }
}

<#
.SYNOPSIS
    Gets standards from the library.
#>
function Get-ValidationStandard {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Name,

        [Parameter()]
        [string]$Vendor,

        [Parameter()]
        [hashtable]$Library
    )

    $lib = if ($Library) { $Library } else { $script:StandardsLibrary }
    $results = @($lib.Standards)

    if ($Name) {
        $results = @($results | Where-Object { $_.Name -eq $Name -or $_.Name -like "*$Name*" })
    }
    if ($Vendor) {
        $results = @($results | Where-Object { $_.Vendor -eq $Vendor })
    }

    $results
}

<#
.SYNOPSIS
    Removes a standard from the library.
#>
function Remove-ValidationStandard {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter()]
        [hashtable]$Library
    )

    $lib = if ($Library) { $Library } else { $script:StandardsLibrary }
    $standard = $lib.Standards | Where-Object { $_.Name -eq $Name } | Select-Object -First 1

    if (-not $standard) {
        Write-Warning "Standard '$Name' not found"
        return $false
    }

    $lib.Standards.Remove($standard)
    $true
}

<#
.SYNOPSIS
    Clears all standards from the library.
#>
function Clear-StandardsLibrary {
    [CmdletBinding()]
    param(
        [Parameter()]
        [hashtable]$Library
    )

    $lib = if ($Library) { $Library } else { $script:StandardsLibrary }
    $lib.Standards.Clear()
}

<#
.SYNOPSIS
    Loads built-in standards into the library.
#>
function Import-BuiltInStandards {
    [CmdletBinding()]
    param(
        [Parameter()]
        [hashtable]$Library
    )

    $lib = if ($Library) { $Library } else { $script:StandardsLibrary }
    $builtIn = Get-BuiltInStandards

    $imported = 0
    foreach ($standard in $builtIn) {
        $existing = $lib.Standards | Where-Object { $_.Name -eq $standard.Name }
        if (-not $existing) {
            $lib.Standards.Add($standard) | Out-Null
            $imported++
        }
    }

    [PSCustomObject]@{
        Imported = $imported
        Total    = $builtIn.Count
    }
}

#endregion

#region Reporting

<#
.SYNOPSIS
    Generates a compliance report.
#>
function New-ComplianceReport {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$ComplianceResult,

        [Parameter()]
        [ValidateSet('Text', 'HTML', 'CSV')]
        [string]$Format = 'Text'
    )

    switch ($Format) {
        'Text' { Format-TextReport -Result $ComplianceResult }
        'HTML' { Format-HtmlReport -Result $ComplianceResult }
        'CSV'  { Format-CsvReport -Result $ComplianceResult }
    }
}

function Format-TextReport {
    param([PSCustomObject]$Result)

    $sb = New-Object System.Text.StringBuilder

    $sb.AppendLine("=" * 60) | Out-Null
    $sb.AppendLine("COMPLIANCE REPORT") | Out-Null
    $sb.AppendLine("=" * 60) | Out-Null
    $sb.AppendLine("Device: $($Result.DeviceName)") | Out-Null
    $sb.AppendLine("Standard: $($Result.StandardName) v$($Result.StandardVersion)") | Out-Null
    $sb.AppendLine("Checked: $($Result.CheckedAt)") | Out-Null
    $sb.AppendLine("-" * 60) | Out-Null
    $sb.AppendLine("Score: $($Result.Score)% ($($Result.Passed)/$($Result.TotalRules) rules passed)") | Out-Null
    $sb.AppendLine("") | Out-Null

    # Critical violations
    $critical = @($Result.Results | Where-Object { $_.Status -eq 'Fail' -and $_.Severity -eq 'Critical' })
    if ($critical.Count -gt 0) {
        $sb.AppendLine("CRITICAL VIOLATIONS ($($critical.Count))") | Out-Null
        $sb.AppendLine("-" * 40) | Out-Null
        foreach ($v in $critical) {
            $sb.AppendLine("  [$($v.RuleID)] $($v.RuleName)") | Out-Null
            $sb.AppendLine("    $($v.Message)") | Out-Null
            if ($v.LineNumber) { $sb.AppendLine("    Line: $($v.LineNumber)") | Out-Null }
            if ($v.Remediation) { $sb.AppendLine("    Fix: $($v.Remediation)") | Out-Null }
        }
        $sb.AppendLine("") | Out-Null
    }

    # High violations
    $high = @($Result.Results | Where-Object { $_.Status -eq 'Fail' -and $_.Severity -eq 'High' })
    if ($high.Count -gt 0) {
        $sb.AppendLine("HIGH VIOLATIONS ($($high.Count))") | Out-Null
        $sb.AppendLine("-" * 40) | Out-Null
        foreach ($v in $high) {
            $sb.AppendLine("  [$($v.RuleID)] $($v.RuleName)") | Out-Null
            $sb.AppendLine("    $($v.Message)") | Out-Null
            if ($v.Remediation) { $sb.AppendLine("    Fix: $($v.Remediation)") | Out-Null }
        }
        $sb.AppendLine("") | Out-Null
    }

    # Medium/Low
    $other = @($Result.Results | Where-Object { $_.Status -eq 'Fail' -and $_.Severity -notin @('Critical', 'High') })
    if ($other.Count -gt 0) {
        $sb.AppendLine("OTHER VIOLATIONS ($($other.Count))") | Out-Null
        $sb.AppendLine("-" * 40) | Out-Null
        foreach ($v in $other) {
            $sb.AppendLine("  [$($v.RuleID)] $($v.RuleName) ($($v.Severity))") | Out-Null
        }
    }

    $sb.ToString()
}

function Format-HtmlReport {
    param([PSCustomObject]$Result)

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Compliance Report - $($Result.DeviceName)</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #333; }
        .summary { background: #f5f5f5; padding: 15px; border-radius: 5px; margin-bottom: 20px; }
        .score { font-size: 24px; font-weight: bold; }
        .score.good { color: green; }
        .score.warn { color: orange; }
        .score.bad { color: red; }
        table { width: 100%; border-collapse: collapse; margin-top: 10px; }
        th, td { padding: 8px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background: #333; color: white; }
        .critical { background: #ffcccc; }
        .high { background: #ffe0cc; }
        .medium { background: #fff3cc; }
        .pass { background: #ccffcc; }
    </style>
</head>
<body>
    <h1>Compliance Report</h1>
    <div class="summary">
        <p><strong>Device:</strong> $($Result.DeviceName)</p>
        <p><strong>Standard:</strong> $($Result.StandardName) v$($Result.StandardVersion)</p>
        <p><strong>Checked:</strong> $($Result.CheckedAt)</p>
        <p class="score $(if($Result.Score -ge 90){'good'}elseif($Result.Score -ge 70){'warn'}else{'bad'})">
            Score: $($Result.Score)% ($($Result.Passed)/$($Result.TotalRules) passed)
        </p>
    </div>
    <h2>Results</h2>
    <table>
        <tr><th>Rule</th><th>Name</th><th>Status</th><th>Severity</th><th>Message</th></tr>
"@

    foreach ($r in $Result.Results | Sort-Object -Property @{E={switch($_.Severity){'Critical'{0}'High'{1}'Medium'{2}'Low'{3}default{4}}}}, RuleID) {
        $class = switch ($r.Status) {
            'Fail' {
                switch ($r.Severity) {
                    'Critical' { 'critical' }
                    'High' { 'high' }
                    'Medium' { 'medium' }
                    default { '' }
                }
            }
            'Pass' { 'pass' }
            default { '' }
        }
        $html += "        <tr class='$class'><td>$($r.RuleID)</td><td>$($r.RuleName)</td><td>$($r.Status)</td><td>$($r.Severity)</td><td>$($r.Message)</td></tr>`n"
    }

    $html += @"
    </table>
</body>
</html>
"@

    $html
}

function Format-CsvReport {
    param([PSCustomObject]$Result)

    $sb = New-Object System.Text.StringBuilder
    $sb.AppendLine("RuleID,RuleName,Status,Severity,Message,LineNumber,Remediation") | Out-Null

    foreach ($r in $Result.Results) {
        $msg = $r.Message -replace '"', '""'
        $rem = if ($r.Remediation) { $r.Remediation -replace '"', '""' -replace "`n", "; " } else { '' }
        $sb.AppendLine("`"$($r.RuleID)`",`"$($r.RuleName)`",`"$($r.Status)`",`"$($r.Severity)`",`"$msg`",$($r.LineNumber),`"$rem`"") | Out-Null
    }

    $sb.ToString()
}

<#
.SYNOPSIS
    Generates remediation commands from violations.
#>
function Get-RemediationCommands {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$ComplianceResult
    )

    $commands = @()
    $violations = @($ComplianceResult.Results | Where-Object { $_.Status -eq 'Fail' -and $_.Remediation })

    foreach ($v in $violations) {
        $commands += "! $($v.RuleID): $($v.RuleName)"
        $commands += $v.Remediation -split "`n"
        $commands += ""
    }

    $commands
}

#endregion

#region Import/Export

<#
.SYNOPSIS
    Exports standards to a JSON file.
#>
function Export-StandardsLibrary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter()]
        [hashtable]$Library
    )

    $lib = if ($Library) { $Library } else { $script:StandardsLibrary }

    $export = @{
        ExportDate = (Get-Date).ToString('o')
        Version    = '1.0'
        Standards  = @($lib.Standards)
    }

    $export | ConvertTo-Json -Depth 10 | Set-Content -Path $Path -Encoding UTF8
}

<#
.SYNOPSIS
    Imports standards from a JSON file.
#>
function Import-StandardsLibrary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter()]
        [switch]$Merge,

        [Parameter()]
        [hashtable]$Library
    )

    if (-not (Test-Path $Path)) {
        Write-Warning "File not found: $Path"
        return $null
    }

    $lib = if ($Library) { $Library } else { $script:StandardsLibrary }
    $content = Get-Content -Path $Path -Raw | ConvertFrom-Json

    if (-not $Merge) {
        $lib.Standards.Clear()
    }

    $imported = 0
    foreach ($standard in $content.Standards) {
        $existing = $lib.Standards | Where-Object { $_.Name -eq $standard.Name }
        if (-not $existing) {
            $lib.Standards.Add($standard) | Out-Null
            $imported++
        }
    }

    [PSCustomObject]@{
        Imported = $imported
        Total    = $content.Standards.Count
    }
}

#endregion

Export-ModuleMember -Function @(
    'New-ValidationRule'
    'New-ValidationStandard'
    'New-ValidationResult'
    'Test-ConfigCompliance'
    'Test-SingleRule'
    'Test-BulkCompliance'
    'Get-SecurityBaseline'
    'Get-OperationalBaseline'
    'Get-SwitchingBaseline'
    'Get-BuiltInStandards'
    'New-StandardsLibrary'
    'Add-ValidationStandard'
    'Get-ValidationStandard'
    'Remove-ValidationStandard'
    'Clear-StandardsLibrary'
    'Import-BuiltInStandards'
    'New-ComplianceReport'
    'Get-RemediationCommands'
    'Export-StandardsLibrary'
    'Import-StandardsLibrary'
)
