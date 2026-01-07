# ComplianceModule.psm1
# Compliance validation for SOX, PCI-DSS, HIPAA frameworks

Set-StrictMode -Version Latest

$script:ComplianceResults = @{}
$script:LastValidation = $null

#region Core Functions

function Get-ComplianceFrameworks {
    <#
    .SYNOPSIS
    Returns list of supported compliance frameworks.
    #>
    return @(
        @{ Id = 'SOX'; Name = 'Sarbanes-Oxley Act'; Description = 'Financial reporting controls' }
        @{ Id = 'PCI-DSS'; Name = 'PCI Data Security Standard'; Description = 'Payment card data protection' }
        @{ Id = 'HIPAA'; Name = 'Health Insurance Portability and Accountability Act'; Description = 'Healthcare data protection' }
        @{ Id = 'NIST'; Name = 'NIST Cybersecurity Framework'; Description = 'General security controls' }
        @{ Id = 'CIS'; Name = 'CIS Controls'; Description = 'Center for Internet Security benchmarks' }
    )
}

function Invoke-ComplianceValidation {
    <#
    .SYNOPSIS
    Runs compliance validation for specified framework(s).
    .PARAMETER Framework
    Framework to validate: SOX, PCI-DSS, HIPAA, NIST, CIS, All
    .PARAMETER Devices
    Device objects to validate. If not provided, uses all loaded devices.
    .PARAMETER IncludeRemediation
    Include remediation recommendations in results.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('SOX', 'PCI-DSS', 'HIPAA', 'NIST', 'CIS', 'All')]
        [string]$Framework,

        [object[]]$Devices,

        [switch]$IncludeRemediation
    )

    # Import device repository if needed
    $projectRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $projectRoot 'Modules\DeviceRepositoryModule.psm1') -Force -DisableNameChecking -ErrorAction SilentlyContinue
    Import-Module (Join-Path $projectRoot 'Modules\AuditTrailModule.psm1') -Force -DisableNameChecking -ErrorAction SilentlyContinue

    if (-not $Devices) {
        try {
            $Devices = Get-AllDevices -ErrorAction SilentlyContinue
        } catch {
            $Devices = @()
        }
    }

    $frameworks = if ($Framework -eq 'All') {
        @('SOX', 'PCI-DSS', 'HIPAA', 'NIST', 'CIS')
    } else {
        @($Framework)
    }

    $results = @{
        ValidationId = [guid]::NewGuid().ToString('N').Substring(0, 12)
        Timestamp = [datetime]::UtcNow.ToString('o')
        DeviceCount = @($Devices).Count
        Frameworks = @{}
        OverallScore = 0
        OverallStatus = 'Unknown'
    }

    foreach ($fw in $frameworks) {
        $fwResult = switch ($fw) {
            'SOX' { Test-SOXCompliance -Devices $Devices -IncludeRemediation:$IncludeRemediation }
            'PCI-DSS' { Test-PCIDSSCompliance -Devices $Devices -IncludeRemediation:$IncludeRemediation }
            'HIPAA' { Test-HIPAACompliance -Devices $Devices -IncludeRemediation:$IncludeRemediation }
            'NIST' { Test-NISTCompliance -Devices $Devices -IncludeRemediation:$IncludeRemediation }
            'CIS' { Test-CISCompliance -Devices $Devices -IncludeRemediation:$IncludeRemediation }
        }
        $results.Frameworks[$fw] = $fwResult
    }

    # Calculate overall score
    $scores = $results.Frameworks.Values | ForEach-Object { $_.Score }
    if ($scores.Count -gt 0) {
        $results.OverallScore = [math]::Round(($scores | Measure-Object -Average).Average, 1)
        $results.OverallStatus = Get-ComplianceStatus -Score $results.OverallScore
    }

    # Log audit event
    try {
        Write-AuditEvent -EventType 'ComplianceCheck' -Category 'Compliance' -Action 'Validate' `
            -Target $Framework -Details "Score: $($results.OverallScore)%" -Result 'Success'
    } catch { }

    $script:ComplianceResults = $results
    $script:LastValidation = [datetime]::UtcNow

    return $results
}

function Get-ComplianceStatus {
    param([double]$Score)

    if ($Score -ge 90) { return 'Compliant' }
    if ($Score -ge 70) { return 'Partially Compliant' }
    if ($Score -ge 50) { return 'Non-Compliant' }
    return 'Critical'
}

#endregion

#region SOX Compliance

function Test-SOXCompliance {
    <#
    .SYNOPSIS
    Validates SOX compliance controls for network access and change management.
    #>
    [CmdletBinding()]
    param(
        [object[]]$Devices,
        [switch]$IncludeRemediation
    )

    $controls = @()
    $passedCount = 0
    $totalWeight = 0

    # SOX-001: Access Control Lists
    $control = @{
        Id = 'SOX-001'
        Name = 'Network Access Control'
        Description = 'Verify ACLs are configured on network devices'
        Category = 'Access Control'
        Weight = 15
        Status = 'Unknown'
        Findings = @()
    }

    $devicesWithACL = 0
    foreach ($device in $Devices) {
        $hasACL = $false
        if ($device.Configuration -match 'access-list|ip access-group|acl|firewall filter') {
            $hasACL = $true
        }
        if ($device.InterfacesCombined | Where-Object { $_.ACL -or $_.AccessGroup }) {
            $hasACL = $true
        }
        if ($hasACL) { $devicesWithACL++ }
        else { $control.Findings += "Device $($device.Hostname) has no ACL configuration" }
    }

    $aclPercent = if (@($Devices).Count -gt 0) { [math]::Round($devicesWithACL / @($Devices).Count * 100, 1) } else { 0 }
    $control.Status = if ($aclPercent -ge 90) { 'Pass' } elseif ($aclPercent -ge 70) { 'Warning' } else { 'Fail' }
    $control.Score = $aclPercent
    if ($control.Status -eq 'Pass') { $passedCount += $control.Weight }
    $totalWeight += $control.Weight

    if ($IncludeRemediation -and $control.Status -ne 'Pass') {
        $control.Remediation = 'Configure access control lists on all network devices to restrict unauthorized access.'
    }
    $controls += $control

    # SOX-002: Change Management
    $control = @{
        Id = 'SOX-002'
        Name = 'Configuration Change Tracking'
        Description = 'Verify configuration changes are logged and tracked'
        Category = 'Change Management'
        Weight = 20
        Status = 'Unknown'
        Findings = @()
    }

    # Check for audit trail existence
    $projectRoot = Split-Path -Parent $PSScriptRoot
    $auditPath = Join-Path $projectRoot 'Logs\Audit'
    $hasAuditTrail = Test-Path $auditPath

    if ($hasAuditTrail) {
        $auditFiles = Get-ChildItem -Path $auditPath -Filter '*.jsonl' -ErrorAction SilentlyContinue
        $recentAudits = $auditFiles | Where-Object { $_.LastWriteTime -gt (Get-Date).AddDays(-30) }

        if ($recentAudits.Count -gt 0) {
            $control.Status = 'Pass'
            $control.Score = 100
        } else {
            $control.Status = 'Warning'
            $control.Score = 50
            $control.Findings += 'No audit events in last 30 days'
        }
    } else {
        $control.Status = 'Fail'
        $control.Score = 0
        $control.Findings += 'Audit trail not configured'
    }

    if ($control.Status -eq 'Pass') { $passedCount += $control.Weight }
    $totalWeight += $control.Weight

    if ($IncludeRemediation -and $control.Status -ne 'Pass') {
        $control.Remediation = 'Enable audit trail logging using Initialize-AuditTrail and ensure Write-AuditEvent is called for all configuration changes.'
    }
    $controls += $control

    # SOX-003: Segregation of Duties
    $control = @{
        Id = 'SOX-003'
        Name = 'Segregation of Duties'
        Description = 'Verify role-based access controls are in place'
        Category = 'Access Control'
        Weight = 15
        Status = 'Unknown'
        Findings = @()
    }

    # Check for privilege levels on devices
    $devicesWithRBAC = 0
    foreach ($device in $Devices) {
        if ($device.Configuration -match 'privilege level|role|aaa authorization|user-role') {
            $devicesWithRBAC++
        }
    }

    $rbacPercent = if (@($Devices).Count -gt 0) { [math]::Round($devicesWithRBAC / @($Devices).Count * 100, 1) } else { 100 }
    $control.Score = $rbacPercent
    $control.Status = if ($rbacPercent -ge 80) { 'Pass' } elseif ($rbacPercent -ge 50) { 'Warning' } else { 'Fail' }

    if ($control.Status -eq 'Pass') { $passedCount += $control.Weight }
    $totalWeight += $control.Weight
    $controls += $control

    # SOX-004: Backup and Recovery
    $control = @{
        Id = 'SOX-004'
        Name = 'Backup and Recovery'
        Description = 'Verify configuration backups exist'
        Category = 'Business Continuity'
        Weight = 15
        Status = 'Unknown'
        Findings = @()
    }

    $backupPath = Join-Path $projectRoot 'Data'
    $hasBackups = (Get-ChildItem -Path $backupPath -Recurse -Filter '*.accdb' -ErrorAction SilentlyContinue).Count -gt 0

    $control.Score = if ($hasBackups) { 100 } else { 0 }
    $control.Status = if ($hasBackups) { 'Pass' } else { 'Fail' }

    if ($control.Status -eq 'Pass') { $passedCount += $control.Weight }
    $totalWeight += $control.Weight
    $controls += $control

    # SOX-005: System Monitoring
    $control = @{
        Id = 'SOX-005'
        Name = 'System Monitoring'
        Description = 'Verify monitoring and alerting is configured'
        Category = 'Monitoring'
        Weight = 10
        Status = 'Unknown'
        Findings = @()
    }

    $alertModule = Join-Path $projectRoot 'Modules\AlertRuleModule.psm1'
    $hasAlerts = Test-Path $alertModule

    $control.Score = if ($hasAlerts) { 100 } else { 0 }
    $control.Status = if ($hasAlerts) { 'Pass' } else { 'Warning' }

    if ($control.Status -eq 'Pass') { $passedCount += $control.Weight }
    $totalWeight += $control.Weight
    $controls += $control

    # Calculate overall SOX score
    $overallScore = 0
    foreach ($c in $controls) {
        $overallScore += ($c.Score / 100) * $c.Weight
    }
    $overallScore = [math]::Round($overallScore / $totalWeight * 100, 1)

    return @{
        Framework = 'SOX'
        Name = 'Sarbanes-Oxley Act'
        Score = $overallScore
        Status = Get-ComplianceStatus -Score $overallScore
        Controls = $controls
        ControlsPassed = ($controls | Where-Object { $_.Status -eq 'Pass' }).Count
        ControlsTotal = $controls.Count
    }
}

#endregion

#region PCI-DSS Compliance

function Test-PCIDSSCompliance {
    <#
    .SYNOPSIS
    Validates PCI-DSS compliance for network segmentation and access controls.
    #>
    [CmdletBinding()]
    param(
        [object[]]$Devices,
        [switch]$IncludeRemediation
    )

    $controls = @()
    $totalWeight = 0

    # PCI-1.1: Firewall Configuration
    $control = @{
        Id = 'PCI-1.1'
        Name = 'Firewall and Router Configuration'
        Description = 'Verify firewall rules restrict traffic to cardholder data environment'
        Category = 'Build and Maintain a Secure Network'
        Weight = 15
        Status = 'Unknown'
        Findings = @()
    }

    $devicesWithFirewall = 0
    foreach ($device in $Devices) {
        if ($device.Make -match 'PaloAlto|Fortinet|Cisco ASA|Firewall' -or
            $device.Configuration -match 'firewall|security-zone|access-list deny') {
            $devicesWithFirewall++
        }
    }

    $fwPercent = if (@($Devices).Count -gt 0) { [math]::Round($devicesWithFirewall / @($Devices).Count * 100, 1) } else { 0 }
    $control.Score = [math]::Min($fwPercent * 1.5, 100)  # Boost score since not all devices need to be firewalls
    $control.Status = if ($control.Score -ge 80) { 'Pass' } elseif ($control.Score -ge 50) { 'Warning' } else { 'Fail' }
    $totalWeight += $control.Weight

    if ($IncludeRemediation -and $control.Status -ne 'Pass') {
        $control.Remediation = 'Deploy firewalls at network perimeter and between CDE and untrusted networks.'
    }
    $controls += $control

    # PCI-1.2: Network Segmentation
    $control = @{
        Id = 'PCI-1.2'
        Name = 'Network Segmentation'
        Description = 'Verify VLAN isolation for cardholder data'
        Category = 'Build and Maintain a Secure Network'
        Weight = 20
        Status = 'Unknown'
        Findings = @()
    }

    $vlansFound = @{}
    foreach ($device in $Devices) {
        foreach ($iface in $device.InterfacesCombined) {
            if ($iface.VLAN -and $iface.VLAN -ne 'trunk' -and $iface.VLAN -ne '0') {
                $vlansFound[$iface.VLAN] = $true
            }
        }
    }

    $vlanCount = $vlansFound.Count
    $control.Score = if ($vlanCount -ge 3) { 100 } elseif ($vlanCount -ge 2) { 70 } elseif ($vlanCount -ge 1) { 40 } else { 0 }
    $control.Status = if ($control.Score -ge 80) { 'Pass' } elseif ($control.Score -ge 50) { 'Warning' } else { 'Fail' }
    $totalWeight += $control.Weight

    if ($IncludeRemediation -and $control.Status -ne 'Pass') {
        $control.Remediation = 'Implement VLAN segmentation to isolate cardholder data environment from other networks.'
    }
    $controls += $control

    # PCI-2.1: Default Passwords
    $control = @{
        Id = 'PCI-2.1'
        Name = 'Vendor Default Passwords'
        Description = 'Verify default passwords are changed'
        Category = 'Do Not Use Vendor-Supplied Defaults'
        Weight = 15
        Status = 'Unknown'
        Findings = @()
    }

    $defaultPasswords = @('cisco', 'admin', 'password', 'default', 'public', 'private')
    $devicesWithDefaults = 0

    foreach ($device in $Devices) {
        if ($device.Configuration) {
            foreach ($pwd in $defaultPasswords) {
                if ($device.Configuration -match "password\s+$pwd|secret\s+$pwd|community\s+$pwd") {
                    $devicesWithDefaults++
                    $control.Findings += "Device $($device.Hostname) may have default credentials"
                    break
                }
            }
        }
    }

    $noDefaultPercent = if (@($Devices).Count -gt 0) { 
        [math]::Round(((@($Devices).Count - $devicesWithDefaults) / @($Devices).Count) * 100, 1) 
    } else { 100 }
    $control.Score = $noDefaultPercent
    $control.Status = if ($control.Score -ge 100) { 'Pass' } elseif ($control.Score -ge 80) { 'Warning' } else { 'Fail' }
    $totalWeight += $control.Weight
    $controls += $control

    # PCI-7.1: Access Control
    $control = @{
        Id = 'PCI-7.1'
        Name = 'Restrict Access to Cardholder Data'
        Description = 'Verify access is limited to need-to-know basis'
        Category = 'Implement Strong Access Control'
        Weight = 15
        Status = 'Unknown'
        Findings = @()
    }

    $devicesWithAAA = 0
    foreach ($device in $Devices) {
        if ($device.Configuration -match 'aaa|radius|tacacs|ldap') {
            $devicesWithAAA++
        }
    }

    $aaaPercent = if (@($Devices).Count -gt 0) { [math]::Round($devicesWithAAA / @($Devices).Count * 100, 1) } else { 0 }
    $control.Score = $aaaPercent
    $control.Status = if ($control.Score -ge 80) { 'Pass' } elseif ($control.Score -ge 50) { 'Warning' } else { 'Fail' }
    $totalWeight += $control.Weight
    $controls += $control

    # PCI-8.1: Unique IDs
    $control = @{
        Id = 'PCI-8.1'
        Name = 'Unique User Identification'
        Description = 'Verify unique user accounts are configured'
        Category = 'Identify and Authenticate Access'
        Weight = 10
        Status = 'Unknown'
        Findings = @()
    }

    $devicesWithUsers = 0
    foreach ($device in $Devices) {
        if ($device.Configuration -match 'username\s+\S+|user\s+\S+') {
            $devicesWithUsers++
        }
    }

    $userPercent = if (@($Devices).Count -gt 0) { [math]::Round($devicesWithUsers / @($Devices).Count * 100, 1) } else { 0 }
    $control.Score = $userPercent
    $control.Status = if ($control.Score -ge 80) { 'Pass' } elseif ($control.Score -ge 50) { 'Warning' } else { 'Fail' }
    $totalWeight += $control.Weight
    $controls += $control

    # PCI-10.1: Audit Trails
    $control = @{
        Id = 'PCI-10.1'
        Name = 'Audit Trails'
        Description = 'Verify logging is enabled for all access to cardholder data'
        Category = 'Track and Monitor All Access'
        Weight = 15
        Status = 'Unknown'
        Findings = @()
    }

    $devicesWithLogging = 0
    foreach ($device in $Devices) {
        if ($device.Configuration -match 'logging|syslog|archive log') {
            $devicesWithLogging++
        }
    }

    $logPercent = if (@($Devices).Count -gt 0) { [math]::Round($devicesWithLogging / @($Devices).Count * 100, 1) } else { 0 }
    $control.Score = $logPercent
    $control.Status = if ($control.Score -ge 90) { 'Pass' } elseif ($control.Score -ge 70) { 'Warning' } else { 'Fail' }
    $totalWeight += $control.Weight
    $controls += $control

    # Calculate overall PCI-DSS score
    $overallScore = 0
    foreach ($c in $controls) {
        $overallScore += ($c.Score / 100) * $c.Weight
    }
    $overallScore = [math]::Round($overallScore / $totalWeight * 100, 1)

    return @{
        Framework = 'PCI-DSS'
        Name = 'PCI Data Security Standard'
        Score = $overallScore
        Status = Get-ComplianceStatus -Score $overallScore
        Controls = $controls
        ControlsPassed = ($controls | Where-Object { $_.Status -eq 'Pass' }).Count
        ControlsTotal = $controls.Count
    }
}

#endregion

#region HIPAA Compliance

function Test-HIPAACompliance {
    <#
    .SYNOPSIS
    Validates HIPAA compliance for healthcare network security.
    #>
    [CmdletBinding()]
    param(
        [object[]]$Devices,
        [switch]$IncludeRemediation
    )

    $controls = @()
    $totalWeight = 0

    # HIPAA-164.312(a)(1): Access Control
    $control = @{
        Id = 'HIPAA-164.312(a)(1)'
        Name = 'Access Control'
        Description = 'Implement technical policies to allow access only to authorized persons'
        Category = 'Technical Safeguards'
        Weight = 20
        Status = 'Unknown'
        Findings = @()
    }

    $devicesWithAccess = 0
    foreach ($device in $Devices) {
        if ($device.Configuration -match 'aaa|access-list|acl|firewall|authentication') {
            $devicesWithAccess++
        }
    }

    $accessPercent = if (@($Devices).Count -gt 0) { [math]::Round($devicesWithAccess / @($Devices).Count * 100, 1) } else { 0 }
    $control.Score = $accessPercent
    $control.Status = if ($control.Score -ge 90) { 'Pass' } elseif ($control.Score -ge 70) { 'Warning' } else { 'Fail' }
    $totalWeight += $control.Weight
    $controls += $control

    # HIPAA-164.312(a)(2)(iv): Encryption
    $control = @{
        Id = 'HIPAA-164.312(a)(2)(iv)'
        Name = 'Encryption and Decryption'
        Description = 'Implement mechanism to encrypt and decrypt ePHI'
        Category = 'Technical Safeguards'
        Weight = 20
        Status = 'Unknown'
        Findings = @()
    }

    $devicesWithEncryption = 0
    foreach ($device in $Devices) {
        if ($device.Configuration -match 'crypto|ipsec|ssl|tls|ssh|encryption|macsec') {
            $devicesWithEncryption++
        }
    }

    $encryptPercent = if (@($Devices).Count -gt 0) { [math]::Round($devicesWithEncryption / @($Devices).Count * 100, 1) } else { 0 }
    $control.Score = $encryptPercent
    $control.Status = if ($control.Score -ge 80) { 'Pass' } elseif ($control.Score -ge 60) { 'Warning' } else { 'Fail' }
    $totalWeight += $control.Weight

    if ($IncludeRemediation -and $control.Status -ne 'Pass') {
        $control.Remediation = 'Enable encryption for data in transit using TLS, SSH, or IPsec on all network devices handling ePHI.'
    }
    $controls += $control

    # HIPAA-164.312(b): Audit Controls
    $control = @{
        Id = 'HIPAA-164.312(b)'
        Name = 'Audit Controls'
        Description = 'Implement mechanisms to record and examine activity in systems containing ePHI'
        Category = 'Technical Safeguards'
        Weight = 15
        Status = 'Unknown'
        Findings = @()
    }

    $devicesWithAudit = 0
    foreach ($device in $Devices) {
        if ($device.Configuration -match 'logging|syslog|audit|archive') {
            $devicesWithAudit++
        }
    }

    $auditPercent = if (@($Devices).Count -gt 0) { [math]::Round($devicesWithAudit / @($Devices).Count * 100, 1) } else { 0 }
    $control.Score = $auditPercent
    $control.Status = if ($control.Score -ge 90) { 'Pass' } elseif ($control.Score -ge 70) { 'Warning' } else { 'Fail' }
    $totalWeight += $control.Weight
    $controls += $control

    # HIPAA-164.312(c)(1): Integrity
    $control = @{
        Id = 'HIPAA-164.312(c)(1)'
        Name = 'Integrity Controls'
        Description = 'Implement policies to protect ePHI from improper alteration or destruction'
        Category = 'Technical Safeguards'
        Weight = 15
        Status = 'Unknown'
        Findings = @()
    }

    # Check for configuration archival/backup
    $projectRoot = Split-Path -Parent $PSScriptRoot
    $hasBackups = (Get-ChildItem -Path (Join-Path $projectRoot 'Data') -Recurse -Filter '*.accdb' -ErrorAction SilentlyContinue).Count -gt 0

    $control.Score = if ($hasBackups) { 100 } else { 30 }
    $control.Status = if ($control.Score -ge 80) { 'Pass' } elseif ($control.Score -ge 50) { 'Warning' } else { 'Fail' }
    $totalWeight += $control.Weight
    $controls += $control

    # HIPAA-164.312(d): Person Authentication
    $control = @{
        Id = 'HIPAA-164.312(d)'
        Name = 'Person or Entity Authentication'
        Description = 'Implement procedures to verify identity of persons seeking access'
        Category = 'Technical Safeguards'
        Weight = 15
        Status = 'Unknown'
        Findings = @()
    }

    $devicesWithAuth = 0
    foreach ($device in $Devices) {
        if ($device.Configuration -match 'aaa authentication|radius|tacacs|ldap|login') {
            $devicesWithAuth++
        }
    }

    $authPercent = if (@($Devices).Count -gt 0) { [math]::Round($devicesWithAuth / @($Devices).Count * 100, 1) } else { 0 }
    $control.Score = $authPercent
    $control.Status = if ($control.Score -ge 80) { 'Pass' } elseif ($control.Score -ge 60) { 'Warning' } else { 'Fail' }
    $totalWeight += $control.Weight
    $controls += $control

    # HIPAA-164.312(e)(1): Transmission Security
    $control = @{
        Id = 'HIPAA-164.312(e)(1)'
        Name = 'Transmission Security'
        Description = 'Implement technical security measures to guard against unauthorized access during transmission'
        Category = 'Technical Safeguards'
        Weight = 15
        Status = 'Unknown'
        Findings = @()
    }

    # Same as encryption check
    $control.Score = $encryptPercent
    $control.Status = if ($control.Score -ge 80) { 'Pass' } elseif ($control.Score -ge 60) { 'Warning' } else { 'Fail' }
    $totalWeight += $control.Weight
    $controls += $control

    # Calculate overall HIPAA score
    $overallScore = 0
    foreach ($c in $controls) {
        $overallScore += ($c.Score / 100) * $c.Weight
    }
    $overallScore = [math]::Round($overallScore / $totalWeight * 100, 1)

    return @{
        Framework = 'HIPAA'
        Name = 'Health Insurance Portability and Accountability Act'
        Score = $overallScore
        Status = Get-ComplianceStatus -Score $overallScore
        Controls = $controls
        ControlsPassed = ($controls | Where-Object { $_.Status -eq 'Pass' }).Count
        ControlsTotal = $controls.Count
    }
}

#endregion

#region NIST Compliance

function Test-NISTCompliance {
    <#
    .SYNOPSIS
    Validates NIST Cybersecurity Framework compliance.
    #>
    [CmdletBinding()]
    param(
        [object[]]$Devices,
        [switch]$IncludeRemediation
    )

    $controls = @()
    $totalWeight = 0

    # NIST-ID.AM: Asset Management
    $control = @{
        Id = 'NIST-ID.AM'
        Name = 'Asset Management'
        Description = 'Physical devices and systems are inventoried'
        Category = 'Identify'
        Weight = 15
        Status = 'Unknown'
        Findings = @()
    }

    $control.Score = if (@($Devices).Count -gt 0) { 100 } else { 0 }
    $control.Status = if ($control.Score -ge 80) { 'Pass' } else { 'Fail' }
    $totalWeight += $control.Weight
    $controls += $control

    # NIST-PR.AC: Access Control
    $control = @{
        Id = 'NIST-PR.AC'
        Name = 'Identity Management and Access Control'
        Description = 'Access to assets and associated facilities is limited'
        Category = 'Protect'
        Weight = 20
        Status = 'Unknown'
        Findings = @()
    }

    $devicesWithAC = 0
    foreach ($device in $Devices) {
        if ($device.Configuration -match 'aaa|access-list|acl|authentication') {
            $devicesWithAC++
        }
    }

    $acPercent = if (@($Devices).Count -gt 0) { [math]::Round($devicesWithAC / @($Devices).Count * 100, 1) } else { 0 }
    $control.Score = $acPercent
    $control.Status = if ($control.Score -ge 80) { 'Pass' } elseif ($control.Score -ge 60) { 'Warning' } else { 'Fail' }
    $totalWeight += $control.Weight
    $controls += $control

    # NIST-PR.DS: Data Security
    $control = @{
        Id = 'NIST-PR.DS'
        Name = 'Data Security'
        Description = 'Information and records are managed consistent with risk strategy'
        Category = 'Protect'
        Weight = 15
        Status = 'Unknown'
        Findings = @()
    }

    $devicesWithDS = 0
    foreach ($device in $Devices) {
        if ($device.Configuration -match 'crypto|encryption|ssh|tls') {
            $devicesWithDS++
        }
    }

    $dsPercent = if (@($Devices).Count -gt 0) { [math]::Round($devicesWithDS / @($Devices).Count * 100, 1) } else { 0 }
    $control.Score = $dsPercent
    $control.Status = if ($control.Score -ge 80) { 'Pass' } elseif ($control.Score -ge 60) { 'Warning' } else { 'Fail' }
    $totalWeight += $control.Weight
    $controls += $control

    # NIST-DE.CM: Continuous Monitoring
    $control = @{
        Id = 'NIST-DE.CM'
        Name = 'Security Continuous Monitoring'
        Description = 'The network is monitored to detect potential cybersecurity events'
        Category = 'Detect'
        Weight = 20
        Status = 'Unknown'
        Findings = @()
    }

    $projectRoot = Split-Path -Parent $PSScriptRoot
    $hasMonitoring = Test-Path (Join-Path $projectRoot 'Modules\AlertRuleModule.psm1')

    $control.Score = if ($hasMonitoring) { 100 } else { 20 }
    $control.Status = if ($control.Score -ge 80) { 'Pass' } elseif ($control.Score -ge 50) { 'Warning' } else { 'Fail' }
    $totalWeight += $control.Weight
    $controls += $control

    # NIST-RS.AN: Analysis
    $control = @{
        Id = 'NIST-RS.AN'
        Name = 'Analysis'
        Description = 'Analysis is conducted to ensure effective response and support recovery'
        Category = 'Respond'
        Weight = 15
        Status = 'Unknown'
        Findings = @()
    }

    $hasAudit = Test-Path (Join-Path $projectRoot 'Logs\Audit')
    $control.Score = if ($hasAudit) { 100 } else { 30 }
    $control.Status = if ($control.Score -ge 80) { 'Pass' } elseif ($control.Score -ge 50) { 'Warning' } else { 'Fail' }
    $totalWeight += $control.Weight
    $controls += $control

    # NIST-RC.RP: Recovery Planning
    $control = @{
        Id = 'NIST-RC.RP'
        Name = 'Recovery Planning'
        Description = 'Recovery processes and procedures are maintained'
        Category = 'Recover'
        Weight = 15
        Status = 'Unknown'
        Findings = @()
    }

    $hasBackups = (Get-ChildItem -Path (Join-Path $projectRoot 'Data') -Recurse -Filter '*.accdb' -ErrorAction SilentlyContinue).Count -gt 0
    $control.Score = if ($hasBackups) { 80 } else { 30 }
    $control.Status = if ($control.Score -ge 80) { 'Pass' } elseif ($control.Score -ge 50) { 'Warning' } else { 'Fail' }
    $totalWeight += $control.Weight
    $controls += $control

    # Calculate overall NIST score
    $overallScore = 0
    foreach ($c in $controls) {
        $overallScore += ($c.Score / 100) * $c.Weight
    }
    $overallScore = [math]::Round($overallScore / $totalWeight * 100, 1)

    return @{
        Framework = 'NIST'
        Name = 'NIST Cybersecurity Framework'
        Score = $overallScore
        Status = Get-ComplianceStatus -Score $overallScore
        Controls = $controls
        ControlsPassed = ($controls | Where-Object { $_.Status -eq 'Pass' }).Count
        ControlsTotal = $controls.Count
    }
}

#endregion

#region CIS Compliance

function Test-CISCompliance {
    <#
    .SYNOPSIS
    Validates CIS Controls compliance.
    #>
    [CmdletBinding()]
    param(
        [object[]]$Devices,
        [switch]$IncludeRemediation
    )

    $controls = @()
    $totalWeight = 0

    # CIS-1: Inventory of Assets
    $control = @{
        Id = 'CIS-1'
        Name = 'Inventory and Control of Enterprise Assets'
        Description = 'Actively manage all enterprise assets'
        Category = 'Basic Controls'
        Weight = 15
        Status = 'Unknown'
        Findings = @()
    }

    $control.Score = if (@($Devices).Count -gt 0) { 100 } else { 0 }
    $control.Status = if ($control.Score -ge 80) { 'Pass' } else { 'Fail' }
    $totalWeight += $control.Weight
    $controls += $control

    # CIS-4: Secure Configuration
    $control = @{
        Id = 'CIS-4'
        Name = 'Secure Configuration of Enterprise Assets'
        Description = 'Establish and maintain secure configuration'
        Category = 'Basic Controls'
        Weight = 20
        Status = 'Unknown'
        Findings = @()
    }

    $secureDevices = 0
    foreach ($device in $Devices) {
        $securityScore = 0
        if ($device.Configuration -match 'no ip http server') { $securityScore++ }
        if ($device.Configuration -match 'service password-encryption') { $securityScore++ }
        if ($device.Configuration -match 'login block-for|login delay') { $securityScore++ }
        if ($device.Configuration -match 'banner') { $securityScore++ }
        if ($securityScore -ge 2) { $secureDevices++ }
    }

    $securePercent = if (@($Devices).Count -gt 0) { [math]::Round($secureDevices / @($Devices).Count * 100, 1) } else { 0 }
    $control.Score = $securePercent
    $control.Status = if ($control.Score -ge 80) { 'Pass' } elseif ($control.Score -ge 50) { 'Warning' } else { 'Fail' }
    $totalWeight += $control.Weight
    $controls += $control

    # CIS-5: Account Management
    $control = @{
        Id = 'CIS-5'
        Name = 'Account Management'
        Description = 'Use processes and tools to assign and manage authorization'
        Category = 'Basic Controls'
        Weight = 15
        Status = 'Unknown'
        Findings = @()
    }

    $devicesWithAccounts = 0
    foreach ($device in $Devices) {
        if ($device.Configuration -match 'username|aaa|tacacs|radius') {
            $devicesWithAccounts++
        }
    }

    $accountPercent = if (@($Devices).Count -gt 0) { [math]::Round($devicesWithAccounts / @($Devices).Count * 100, 1) } else { 0 }
    $control.Score = $accountPercent
    $control.Status = if ($control.Score -ge 80) { 'Pass' } elseif ($control.Score -ge 60) { 'Warning' } else { 'Fail' }
    $totalWeight += $control.Weight
    $controls += $control

    # CIS-8: Audit Log Management
    $control = @{
        Id = 'CIS-8'
        Name = 'Audit Log Management'
        Description = 'Collect, alert, review, and retain audit logs'
        Category = 'Basic Controls'
        Weight = 20
        Status = 'Unknown'
        Findings = @()
    }

    $devicesWithLogs = 0
    foreach ($device in $Devices) {
        if ($device.Configuration -match 'logging|syslog') {
            $devicesWithLogs++
        }
    }

    $logPercent = if (@($Devices).Count -gt 0) { [math]::Round($devicesWithLogs / @($Devices).Count * 100, 1) } else { 0 }
    $control.Score = $logPercent
    $control.Status = if ($control.Score -ge 90) { 'Pass' } elseif ($control.Score -ge 70) { 'Warning' } else { 'Fail' }
    $totalWeight += $control.Weight
    $controls += $control

    # CIS-12: Network Infrastructure Management
    $control = @{
        Id = 'CIS-12'
        Name = 'Network Infrastructure Management'
        Description = 'Establish and maintain network infrastructure securely'
        Category = 'Foundational Controls'
        Weight = 15
        Status = 'Unknown'
        Findings = @()
    }

    # Check for SSH vs Telnet
    $devicesWithSSH = 0
    foreach ($device in $Devices) {
        if ($device.Configuration -match 'transport input ssh|ip ssh|crypto key') {
            $devicesWithSSH++
        }
    }

    $sshPercent = if (@($Devices).Count -gt 0) { [math]::Round($devicesWithSSH / @($Devices).Count * 100, 1) } else { 0 }
    $control.Score = $sshPercent
    $control.Status = if ($control.Score -ge 90) { 'Pass' } elseif ($control.Score -ge 70) { 'Warning' } else { 'Fail' }
    $totalWeight += $control.Weight
    $controls += $control

    # CIS-13: Network Monitoring
    $control = @{
        Id = 'CIS-13'
        Name = 'Network Monitoring and Defense'
        Description = 'Operate processes to detect and prevent network-based threats'
        Category = 'Foundational Controls'
        Weight = 15
        Status = 'Unknown'
        Findings = @()
    }

    $projectRoot = Split-Path -Parent $PSScriptRoot
    $hasMonitoring = Test-Path (Join-Path $projectRoot 'Modules\AlertRuleModule.psm1')
    $control.Score = if ($hasMonitoring) { 100 } else { 30 }
    $control.Status = if ($control.Score -ge 80) { 'Pass' } elseif ($control.Score -ge 50) { 'Warning' } else { 'Fail' }
    $totalWeight += $control.Weight
    $controls += $control

    # Calculate overall CIS score
    $overallScore = 0
    foreach ($c in $controls) {
        $overallScore += ($c.Score / 100) * $c.Weight
    }
    $overallScore = [math]::Round($overallScore / $totalWeight * 100, 1)

    return @{
        Framework = 'CIS'
        Name = 'CIS Controls'
        Score = $overallScore
        Status = Get-ComplianceStatus -Score $overallScore
        Controls = $controls
        ControlsPassed = ($controls | Where-Object { $_.Status -eq 'Pass' }).Count
        ControlsTotal = $controls.Count
    }
}

#endregion

#region Reporting

function Get-ComplianceSummary {
    <#
    .SYNOPSIS
    Returns last compliance validation results.
    #>
    return $script:ComplianceResults
}

function Export-ComplianceReport {
    <#
    .SYNOPSIS
    Exports compliance report to file.
    .PARAMETER Results
    Compliance validation results.
    .PARAMETER Format
    Output format: JSON, HTML, PDF
    .PARAMETER OutputPath
    Output file path.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Results,

        [ValidateSet('JSON', 'HTML')]
        [string]$Format = 'HTML',

        [string]$OutputPath
    )

    $projectRoot = Split-Path -Parent $PSScriptRoot
    $reportsPath = Join-Path $projectRoot 'Logs\Reports\Compliance'

    if (-not (Test-Path $reportsPath)) {
        New-Item -Path $reportsPath -ItemType Directory -Force | Out-Null
    }

    $dateStr = (Get-Date).ToString('yyyyMMdd-HHmmss')

    if (-not $OutputPath) {
        $ext = switch ($Format) { 'JSON' { 'json' } 'HTML' { 'html' } }
        $OutputPath = Join-Path $reportsPath "ComplianceReport-$dateStr.$ext"
    }

    switch ($Format) {
        'JSON' {
            $Results | ConvertTo-Json -Depth 10 | Set-Content -Path $OutputPath -Encoding UTF8
        }

        'HTML' {
            $frameworkRows = $Results.Frameworks.GetEnumerator() | ForEach-Object {
                $fw = $_.Value
                $statusClass = switch ($fw.Status) {
                    'Compliant' { 'success' }
                    'Partially Compliant' { 'warning' }
                    default { 'critical' }
                }
                "<tr class='$statusClass'>
                    <td>$($fw.Name)</td>
                    <td>$($fw.Score)%</td>
                    <td>$($fw.Status)</td>
                    <td>$($fw.ControlsPassed)/$($fw.ControlsTotal)</td>
                </tr>"
            }

            $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>StateTrace Compliance Report</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        h1 { color: #333; border-bottom: 2px solid #0078d4; padding-bottom: 10px; }
        h2 { color: #555; margin-top: 30px; }
        h3 { color: #666; }
        table { border-collapse: collapse; width: 100%; margin: 10px 0; background: white; }
        th, td { border: 1px solid #ddd; padding: 10px; text-align: left; }
        th { background: #0078d4; color: white; }
        tr.success { background: #e8f5e9; }
        tr.warning { background: #fff3e0; }
        tr.critical { background: #ffebee; }
        .score-card { display: inline-block; padding: 20px 40px; margin: 10px; border-radius: 10px; text-align: center; }
        .score-card.compliant { background: #4caf50; color: white; }
        .score-card.partial { background: #ff9800; color: white; }
        .score-card.non-compliant { background: #f44336; color: white; }
        .score-card .score { font-size: 48px; font-weight: bold; }
        .score-card .label { font-size: 14px; opacity: 0.9; }
        .control-pass { color: #4caf50; font-weight: bold; }
        .control-warning { color: #ff9800; font-weight: bold; }
        .control-fail { color: #f44336; font-weight: bold; }
    </style>
</head>
<body>
    <h1>StateTrace Compliance Report</h1>
    <p><strong>Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
    <p><strong>Devices Evaluated:</strong> $($Results.DeviceCount)</p>

    <div class="score-card $(if ($Results.OverallScore -ge 90) { 'compliant' } elseif ($Results.OverallScore -ge 70) { 'partial' } else { 'non-compliant' })">
        <div class="score">$($Results.OverallScore)%</div>
        <div class="label">Overall Compliance Score</div>
    </div>

    <h2>Framework Summary</h2>
    <table>
        <tr>
            <th>Framework</th>
            <th>Score</th>
            <th>Status</th>
            <th>Controls</th>
        </tr>
        $($frameworkRows -join "`n")
    </table>

    $(foreach ($fw in $Results.Frameworks.Values) {
        @"
    <h2>$($fw.Name) ($($fw.Framework))</h2>
    <p><strong>Score:</strong> $($fw.Score)% | <strong>Status:</strong> $($fw.Status)</p>
    <table>
        <tr>
            <th>Control ID</th>
            <th>Name</th>
            <th>Category</th>
            <th>Score</th>
            <th>Status</th>
        </tr>
        $(foreach ($ctrl in $fw.Controls) {
            $statusClass = switch ($ctrl.Status) { 'Pass' { 'control-pass' } 'Warning' { 'control-warning' } default { 'control-fail' } }
            "<tr>
                <td>$($ctrl.Id)</td>
                <td>$($ctrl.Name)</td>
                <td>$($ctrl.Category)</td>
                <td>$($ctrl.Score)%</td>
                <td class='$statusClass'>$($ctrl.Status)</td>
            </tr>"
        })
    </table>
"@
    })
</body>
</html>
"@
            $html | Set-Content -Path $OutputPath -Encoding UTF8
        }
    }

    Write-Verbose "[Compliance] Report exported to $OutputPath"
    return $OutputPath
}

#endregion

Export-ModuleMember -Function @(
    'Get-ComplianceFrameworks',
    'Invoke-ComplianceValidation',
    'Test-SOXCompliance',
    'Test-PCIDSSCompliance',
    'Test-HIPAACompliance',
    'Test-NISTCompliance',
    'Test-CISCompliance',
    'Get-ComplianceSummary',
    'Export-ComplianceReport'
)
