# ScheduledReportModule.psm1
# Scheduled report generation and delivery

Set-StrictMode -Version Latest

$script:ScheduledJobs = @{}
$script:ReportTemplates = @{}
$script:ConfigPath = $null

function Initialize-ScheduledReports {
    <#
    .SYNOPSIS
    Initializes the scheduled reports system.
    .PARAMETER ConfigPath
    Path to scheduled reports configuration file.
    #>
    [CmdletBinding()]
    param(
        [string]$ConfigPath
    )

    $projectRoot = Split-Path -Parent $PSScriptRoot

    if (-not $ConfigPath) {
        $ConfigPath = Join-Path $projectRoot 'Data\ScheduledReports.json'
    }

    $script:ConfigPath = $ConfigPath

    # Create default config if not exists
    if (-not (Test-Path $ConfigPath)) {
        $defaultConfig = @{
            Version = '1.0'
            Reports = @()
            NotificationSettings = @{
                SmtpServer = ''
                SmtpPort = 587
                FromAddress = 'statetrace@company.com'
                UseSsl = $true
            }
        }
        $defaultConfig | ConvertTo-Json -Depth 5 | Set-Content -Path $ConfigPath -Encoding UTF8
    }

    # Load report templates
    Initialize-ReportTemplates

    Write-Verbose "[ScheduledReports] Initialized with config: $ConfigPath"
}

function Initialize-ReportTemplates {
    <#
    .SYNOPSIS
    Loads built-in report templates.
    #>
    $script:ReportTemplates = @{
        'DailyCompliance' = @{
            Name = 'Daily Compliance Summary'
            Description = 'Daily compliance validation across all frameworks'
            Type = 'Compliance'
            Frameworks = @('All')
            Format = 'HTML'
            IncludeRemediation = $true
        }
        'WeeklyAudit' = @{
            Name = 'Weekly Audit Trail'
            Description = 'Weekly summary of audit events'
            Type = 'Audit'
            Days = 7
            Format = 'HTML'
        }
        'MonthlyExecutive' = @{
            Name = 'Monthly Executive Summary'
            Description = 'Executive-level compliance overview'
            Type = 'Executive'
            Frameworks = @('SOX', 'PCI-DSS', 'HIPAA')
            Format = 'HTML'
        }
        'PCIDSSReport' = @{
            Name = 'PCI-DSS Compliance Report'
            Description = 'Detailed PCI-DSS compliance assessment'
            Type = 'Compliance'
            Frameworks = @('PCI-DSS')
            Format = 'HTML'
            IncludeRemediation = $true
        }
        'HIPAAReport' = @{
            Name = 'HIPAA Compliance Report'
            Description = 'Detailed HIPAA compliance assessment'
            Type = 'Compliance'
            Frameworks = @('HIPAA')
            Format = 'HTML'
            IncludeRemediation = $true
        }
        'DeviceInventory' = @{
            Name = 'Device Inventory Report'
            Description = 'Complete device and interface inventory'
            Type = 'Inventory'
            Format = 'CSV'
        }
    }
}

function Get-ReportTemplates {
    <#
    .SYNOPSIS
    Returns available report templates.
    #>
    return $script:ReportTemplates.GetEnumerator() | ForEach-Object {
        [PSCustomObject]@{
            Id = $_.Key
            Name = $_.Value.Name
            Description = $_.Value.Description
            Type = $_.Value.Type
            Format = $_.Value.Format
        }
    }
}

function New-ScheduledReport {
    <#
    .SYNOPSIS
    Creates a new scheduled report.
    .PARAMETER Name
    Report name.
    .PARAMETER TemplateId
    Template to use.
    .PARAMETER Schedule
    Schedule type: Daily, Weekly, Monthly
    .PARAMETER Time
    Time to run (HH:mm format)
    .PARAMETER DayOfWeek
    Day of week for weekly reports (Sunday-Saturday)
    .PARAMETER DayOfMonth
    Day of month for monthly reports (1-28)
    .PARAMETER Recipients
    Email recipients
    .PARAMETER OutputPath
    Output folder path (optional)
    .PARAMETER Enabled
    Whether the schedule is enabled
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$TemplateId,

        [Parameter(Mandatory)]
        [ValidateSet('Daily', 'Weekly', 'Monthly')]
        [string]$Schedule,

        [string]$Time = '06:00',

        [ValidateSet('Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday')]
        [string]$DayOfWeek = 'Monday',

        [ValidateRange(1, 28)]
        [int]$DayOfMonth = 1,

        [string[]]$Recipients,

        [string]$OutputPath,

        [switch]$Enabled
    )

    if (-not $script:ConfigPath) {
        Initialize-ScheduledReports
    }

    if (-not $script:ReportTemplates.ContainsKey($TemplateId)) {
        throw "Unknown template: $TemplateId. Use Get-ReportTemplates to see available templates."
    }

    $config = Get-Content -Path $script:ConfigPath -Raw | ConvertFrom-Json

    $reportId = [guid]::NewGuid().ToString('N').Substring(0, 8)

    $newReport = @{
        Id = $reportId
        Name = $Name
        TemplateId = $TemplateId
        Schedule = $Schedule
        Time = $Time
        DayOfWeek = $DayOfWeek
        DayOfMonth = $DayOfMonth
        Recipients = $Recipients
        OutputPath = $OutputPath
        Enabled = $Enabled.IsPresent
        CreatedAt = [datetime]::UtcNow.ToString('o')
        LastRun = $null
        NextRun = (Get-NextRunTime -Schedule $Schedule -Time $Time -DayOfWeek $DayOfWeek -DayOfMonth $DayOfMonth).ToString('o')
    }

    $config.Reports += $newReport
    $config | ConvertTo-Json -Depth 5 | Set-Content -Path $script:ConfigPath -Encoding UTF8

    Write-Verbose "[ScheduledReports] Created report: $Name ($reportId)"

    return [PSCustomObject]$newReport
}

function Get-ScheduledReport {
    <#
    .SYNOPSIS
    Gets scheduled reports.
    .PARAMETER Id
    Optional report ID to filter.
    .PARAMETER Enabled
    Filter by enabled status.
    #>
    [CmdletBinding()]
    param(
        [string]$Id,
        [bool]$Enabled
    )

    if (-not $script:ConfigPath) {
        Initialize-ScheduledReports
    }

    $config = Get-Content -Path $script:ConfigPath -Raw | ConvertFrom-Json

    $reports = $config.Reports

    if ($Id) {
        $reports = $reports | Where-Object { $_.Id -eq $Id }
    }

    if ($PSBoundParameters.ContainsKey('Enabled')) {
        $reports = $reports | Where-Object { $_.Enabled -eq $Enabled }
    }

    return $reports
}

function Set-ScheduledReport {
    <#
    .SYNOPSIS
    Updates a scheduled report.
    .PARAMETER Id
    Report ID to update.
    .PARAMETER Enabled
    Enable or disable the report.
    .PARAMETER Recipients
    Update email recipients.
    .PARAMETER Time
    Update run time.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Id,

        [bool]$Enabled,

        [string[]]$Recipients,

        [string]$Time
    )

    if (-not $script:ConfigPath) {
        Initialize-ScheduledReports
    }

    $config = Get-Content -Path $script:ConfigPath -Raw | ConvertFrom-Json

    $report = $config.Reports | Where-Object { $_.Id -eq $Id }

    if (-not $report) {
        throw "Report not found: $Id"
    }

    if ($PSBoundParameters.ContainsKey('Enabled')) {
        $report.Enabled = $Enabled
    }
    if ($Recipients) {
        $report.Recipients = $Recipients
    }
    if ($Time) {
        $report.Time = $Time
        $report.NextRun = (Get-NextRunTime -Schedule $report.Schedule -Time $Time -DayOfWeek $report.DayOfWeek -DayOfMonth $report.DayOfMonth).ToString('o')
    }

    $config | ConvertTo-Json -Depth 5 | Set-Content -Path $script:ConfigPath -Encoding UTF8

    return $report
}

function Remove-ScheduledReport {
    <#
    .SYNOPSIS
    Removes a scheduled report.
    .PARAMETER Id
    Report ID to remove.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Id
    )

    if (-not $script:ConfigPath) {
        Initialize-ScheduledReports
    }

    $config = Get-Content -Path $script:ConfigPath -Raw | ConvertFrom-Json

    $config.Reports = @($config.Reports | Where-Object { $_.Id -ne $Id })

    $config | ConvertTo-Json -Depth 5 | Set-Content -Path $script:ConfigPath -Encoding UTF8

    Write-Verbose "[ScheduledReports] Removed report: $Id"
}

function Invoke-ScheduledReport {
    <#
    .SYNOPSIS
    Runs a scheduled report immediately.
    .PARAMETER Id
    Report ID to run.
    .PARAMETER SendEmail
    Send email to configured recipients.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Id,

        [switch]$SendEmail
    )

    if (-not $script:ConfigPath) {
        Initialize-ScheduledReports
    }

    $projectRoot = Split-Path -Parent $PSScriptRoot

    # Load required modules
    Import-Module (Join-Path $projectRoot 'Modules\ComplianceModule.psm1') -Force -DisableNameChecking -ErrorAction SilentlyContinue
    Import-Module (Join-Path $projectRoot 'Modules\AuditTrailModule.psm1') -Force -DisableNameChecking -ErrorAction SilentlyContinue
    Import-Module (Join-Path $projectRoot 'Modules\DeviceRepositoryModule.psm1') -Force -DisableNameChecking -ErrorAction SilentlyContinue

    $report = Get-ScheduledReport -Id $Id

    if (-not $report) {
        throw "Report not found: $Id"
    }

    $template = $script:ReportTemplates[$report.TemplateId]

    if (-not $template) {
        throw "Template not found: $($report.TemplateId)"
    }

    $outputPath = $report.OutputPath
    if (-not $outputPath) {
        $outputPath = Join-Path $projectRoot 'Logs\Reports\Scheduled'
    }

    if (-not (Test-Path $outputPath)) {
        New-Item -Path $outputPath -ItemType Directory -Force | Out-Null
    }

    $dateStr = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $ext = if ($template.Format -eq 'CSV') { 'csv' } else { 'html' }
    $fileName = "$($report.Name -replace '\s+', '_')-$dateStr.$ext"
    $filePath = Join-Path $outputPath $fileName

    try {
        $reportContent = switch ($template.Type) {
            'Compliance' {
                $frameworks = if ($template.Frameworks -contains 'All') { 'All' } else { $template.Frameworks[0] }
                $results = Invoke-ComplianceValidation -Framework $frameworks -IncludeRemediation:($template.IncludeRemediation -eq $true)
                Export-ComplianceReport -Results $results -Format $template.Format -OutputPath $filePath
                $filePath
            }
            'Audit' {
                $startDate = (Get-Date).AddDays(-$template.Days)
                Export-AuditReport -StartDate $startDate -Format $template.Format -OutputPath $filePath
                $filePath
            }
            'Executive' {
                # Generate executive summary
                $results = Invoke-ComplianceValidation -Framework 'All'
                New-ExecutiveSummaryReport -Results $results -OutputPath $filePath
                $filePath
            }
            'Inventory' {
                $devices = Get-AllDevices -ErrorAction SilentlyContinue
                New-InventoryReport -Devices $devices -OutputPath $filePath
                $filePath
            }
            default {
                throw "Unknown report type: $($template.Type)"
            }
        }

        # Update last run time
        $config = Get-Content -Path $script:ConfigPath -Raw | ConvertFrom-Json
        $configReport = $config.Reports | Where-Object { $_.Id -eq $Id }
        if ($configReport) {
            $configReport.LastRun = [datetime]::UtcNow.ToString('o')
            $configReport.NextRun = (Get-NextRunTime -Schedule $report.Schedule -Time $report.Time -DayOfWeek $report.DayOfWeek -DayOfMonth $report.DayOfMonth).ToString('o')
            $config | ConvertTo-Json -Depth 5 | Set-Content -Path $script:ConfigPath -Encoding UTF8
        }

        # Log audit event
        try {
            Write-AuditEvent -EventType 'DataExport' -Category 'Compliance' -Action 'Export' `
                -Target $report.Name -Details "Generated: $filePath" -Result 'Success'
        } catch { }

        # Send email if requested
        if ($SendEmail -and $report.Recipients) {
            Send-ReportEmail -ReportPath $filePath -Recipients $report.Recipients -ReportName $report.Name
        }

        Write-Verbose "[ScheduledReports] Generated: $filePath"

        return [PSCustomObject]@{
            ReportId = $Id
            ReportName = $report.Name
            FilePath = $filePath
            GeneratedAt = Get-Date
            Success = $true
        }

    } catch {
        Write-Warning "[ScheduledReports] Report generation failed: $_"

        try {
            Write-AuditEvent -EventType 'DataExport' -Category 'Compliance' -Action 'Export' `
                -Target $report.Name -Details $_.Exception.Message -Result 'Failure' -Severity 'Warning'
        } catch { }

        return [PSCustomObject]@{
            ReportId = $Id
            ReportName = $report.Name
            FilePath = $null
            GeneratedAt = Get-Date
            Success = $false
            Error = $_.Exception.Message
        }
    }
}

function New-ExecutiveSummaryReport {
    <#
    .SYNOPSIS
    Generates an executive summary report.
    #>
    param(
        [object]$Results,
        [string]$OutputPath
    )

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>StateTrace Executive Compliance Summary</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 40px; background: #f5f5f5; }
        .header { text-align: center; padding: 30px; background: linear-gradient(135deg, #1976D2, #0D47A1); color: white; border-radius: 10px; margin-bottom: 30px; }
        .header h1 { margin: 0; font-size: 32px; }
        .header p { margin: 10px 0 0 0; opacity: 0.9; }
        .score-section { text-align: center; padding: 40px; background: white; border-radius: 10px; margin-bottom: 30px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .score { font-size: 72px; font-weight: bold; }
        .score.compliant { color: #4CAF50; }
        .score.partial { color: #FF9800; }
        .score.noncompliant { color: #F44336; }
        .frameworks { display: flex; justify-content: space-around; flex-wrap: wrap; margin-bottom: 30px; }
        .framework-card { background: white; padding: 20px; border-radius: 10px; min-width: 150px; text-align: center; margin: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .framework-score { font-size: 36px; font-weight: bold; }
        .key-findings { background: white; padding: 20px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .finding { padding: 10px; border-left: 4px solid #F44336; margin: 10px 0; background: #FFEBEE; }
        .finding.warning { border-color: #FF9800; background: #FFF3E0; }
        .footer { text-align: center; padding: 20px; color: #666; font-size: 12px; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Executive Compliance Summary</h1>
        <p>Generated: $(Get-Date -Format 'MMMM dd, yyyy HH:mm')</p>
    </div>

    <div class="score-section">
        <div class="score $(if ($Results.OverallScore -ge 90) { 'compliant' } elseif ($Results.OverallScore -ge 70) { 'partial' } else { 'noncompliant' })">
            $($Results.OverallScore)%
        </div>
        <p>Overall Compliance Score</p>
        <p><strong>$($Results.OverallStatus)</strong></p>
    </div>

    <div class="frameworks">
        $(foreach ($fwKey in $Results.Frameworks.Keys) {
            $fw = $Results.Frameworks[$fwKey]
            $color = if ($fw.Score -ge 90) { '#4CAF50' } elseif ($fw.Score -ge 70) { '#FF9800' } else { '#F44336' }
            @"
        <div class="framework-card">
            <div class="framework-score" style="color: $color">$($fw.Score)%</div>
            <p><strong>$fwKey</strong></p>
            <p style="color: #666; font-size: 12px;">$($fw.ControlsPassed)/$($fw.ControlsTotal) controls</p>
        </div>
"@
        })
    </div>

    <div class="key-findings">
        <h2>Key Findings</h2>
        $(
            $findings = @()
            foreach ($fw in $Results.Frameworks.Values) {
                foreach ($ctrl in $fw.Controls) {
                    if ($ctrl.Status -eq 'Fail') {
                        $findings += @{ Framework = $fw.Framework; Control = $ctrl.Name; Severity = 'Critical' }
                    } elseif ($ctrl.Status -eq 'Warning') {
                        $findings += @{ Framework = $fw.Framework; Control = $ctrl.Name; Severity = 'Warning' }
                    }
                }
            }
            if ($findings.Count -eq 0) {
                '<p style="color: #4CAF50;">No critical findings. All major controls are passing.</p>'
            } else {
                $findings | Select-Object -First 10 | ForEach-Object {
                    $class = if ($_.Severity -eq 'Critical') { 'finding' } else { 'finding warning' }
                    "<div class='$class'><strong>$($_.Framework):</strong> $($_.Control)</div>"
                }
            }
        )
    </div>

    <div class="footer">
        <p>This report was automatically generated by StateTrace Compliance Engine</p>
        <p>Devices evaluated: $($Results.DeviceCount)</p>
    </div>
</body>
</html>
"@

    $html | Set-Content -Path $OutputPath -Encoding UTF8
    return $OutputPath
}

function New-InventoryReport {
    <#
    .SYNOPSIS
    Generates a device inventory report.
    #>
    param(
        [object[]]$Devices,
        [string]$OutputPath
    )

    $records = $Devices | ForEach-Object {
        [PSCustomObject]@{
            Hostname = $_.Hostname
            Site = $_.Site
            Make = $_.Make
            Model = $_.Model
            Version = $_.Version
            Uptime = $_.Uptime
            Location = $_.Location
            InterfaceCount = $_.InterfaceCount
            UpPorts = @($_.InterfacesCombined | Where-Object { $_.Status -eq 'up' }).Count
            DownPorts = @($_.InterfacesCombined | Where-Object { $_.Status -eq 'down' }).Count
        }
    }

    $records | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
    return $OutputPath
}

function Get-NextRunTime {
    param(
        [string]$Schedule,
        [string]$Time,
        [string]$DayOfWeek,
        [int]$DayOfMonth
    )

    $timeParts = $Time.Split(':')
    $hour = [int]$timeParts[0]
    $minute = [int]$timeParts[1]

    $now = Get-Date
    $today = $now.Date.AddHours($hour).AddMinutes($minute)

    switch ($Schedule) {
        'Daily' {
            if ($now -lt $today) {
                return $today
            } else {
                return $today.AddDays(1)
            }
        }
        'Weekly' {
            $targetDay = [DayOfWeek]::$DayOfWeek
            $daysUntil = (7 + [int]$targetDay - [int]$now.DayOfWeek) % 7
            if ($daysUntil -eq 0 -and $now -ge $today) {
                $daysUntil = 7
            }
            return $now.Date.AddDays($daysUntil).AddHours($hour).AddMinutes($minute)
        }
        'Monthly' {
            $thisMonth = [datetime]::new($now.Year, $now.Month, [math]::Min($DayOfMonth, [datetime]::DaysInMonth($now.Year, $now.Month)))
            $thisMonth = $thisMonth.AddHours($hour).AddMinutes($minute)
            if ($now -lt $thisMonth) {
                return $thisMonth
            } else {
                $nextMonth = $now.AddMonths(1)
                return [datetime]::new($nextMonth.Year, $nextMonth.Month, [math]::Min($DayOfMonth, [datetime]::DaysInMonth($nextMonth.Year, $nextMonth.Month))).AddHours($hour).AddMinutes($minute)
            }
        }
    }
}

function Send-ReportEmail {
    <#
    .SYNOPSIS
    Sends a report via email.
    #>
    param(
        [string]$ReportPath,
        [string[]]$Recipients,
        [string]$ReportName
    )

    if (-not $script:ConfigPath) {
        Initialize-ScheduledReports
    }

    $config = Get-Content -Path $script:ConfigPath -Raw | ConvertFrom-Json
    $smtp = $config.NotificationSettings

    if (-not $smtp.SmtpServer) {
        Write-Warning "[ScheduledReports] SMTP server not configured"
        return
    }

    try {
        $params = @{
            SmtpServer = $smtp.SmtpServer
            Port = $smtp.SmtpPort
            From = $smtp.FromAddress
            To = $Recipients
            Subject = "StateTrace Report: $ReportName - $(Get-Date -Format 'yyyy-MM-dd')"
            Body = "Please find the attached compliance report.`n`nGenerated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
            Attachments = $ReportPath
            UseSsl = $smtp.UseSsl
        }

        Send-MailMessage @params

        Write-Verbose "[ScheduledReports] Email sent to: $($Recipients -join ', ')"

    } catch {
        Write-Warning "[ScheduledReports] Email send failed: $_"
    }
}

function Start-ReportScheduler {
    <#
    .SYNOPSIS
    Starts the background report scheduler.
    #>
    [CmdletBinding()]
    param()

    if (-not $script:ConfigPath) {
        Initialize-ScheduledReports
    }

    Write-Host "StateTrace Report Scheduler started" -ForegroundColor Green
    Write-Host "Press Ctrl+C to stop`n" -ForegroundColor Gray

    while ($true) {
        $now = [datetime]::UtcNow
        $reports = Get-ScheduledReport -Enabled $true

        foreach ($report in $reports) {
            if ($report.NextRun) {
                $nextRun = [datetime]$report.NextRun
                if ($now -ge $nextRun) {
                    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Running: $($report.Name)" -ForegroundColor Cyan
                    $result = Invoke-ScheduledReport -Id $report.Id -SendEmail
                    if ($result.Success) {
                        Write-Host "  Generated: $($result.FilePath)" -ForegroundColor Green
                    } else {
                        Write-Host "  Failed: $($result.Error)" -ForegroundColor Red
                    }
                }
            }
        }

        Start-Sleep -Seconds 60
    }
}

# Initialize on module load
Initialize-ScheduledReports

Export-ModuleMember -Function @(
    'Initialize-ScheduledReports',
    'Get-ReportTemplates',
    'New-ScheduledReport',
    'Get-ScheduledReport',
    'Set-ScheduledReport',
    'Remove-ScheduledReport',
    'Invoke-ScheduledReport',
    'Start-ReportScheduler'
)
