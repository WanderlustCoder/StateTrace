# NotificationModule.psm1
# Unified notification system for email, Teams, and Slack alerts

Set-StrictMode -Version Latest

# Configuration storage
$script:NotificationConfig = @{
    Email = @{
        Enabled = $false
        SmtpServer = ''
        SmtpPort = 587
        UseSsl = $true
        From = ''
        To = @()
        Cc = @()
        Credential = $null
    }
    Teams = @{
        Enabled = $false
        WebhookUrl = ''
    }
    Slack = @{
        Enabled = $false
        WebhookUrl = ''
        Channel = ''
        Username = 'StateTrace'
        IconEmoji = ':satellite:'
    }
}

$script:NotificationHistory = [System.Collections.Generic.List[object]]::new()
$script:MaxHistorySize = 500

#region Configuration

function Set-NotificationConfig {
    <#
    .SYNOPSIS
    Configures notification settings for a specific channel.
    .PARAMETER Channel
    Notification channel: Email, Teams, or Slack.
    .PARAMETER Settings
    Hashtable of settings for the channel.
    .EXAMPLE
    Set-NotificationConfig -Channel Email -Settings @{ SmtpServer = 'smtp.example.com'; From = 'alerts@example.com'; To = @('admin@example.com') }
    .EXAMPLE
    Set-NotificationConfig -Channel Teams -Settings @{ WebhookUrl = 'https://outlook.office.com/webhook/...' }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Email', 'Teams', 'Slack')]
        [string]$Channel,
        [Parameter(Mandatory)][hashtable]$Settings
    )

    foreach ($key in $Settings.Keys) {
        if ($script:NotificationConfig[$Channel].ContainsKey($key)) {
            $script:NotificationConfig[$Channel][$key] = $Settings[$key]
        }
    }

    Write-Verbose "[Notification] Updated $Channel configuration"
}

function Get-NotificationConfig {
    <#
    .SYNOPSIS
    Gets current notification configuration.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Email', 'Teams', 'Slack')]
        [string]$Channel
    )

    if ($Channel) {
        return $script:NotificationConfig[$Channel]
    }
    return $script:NotificationConfig
}

function Enable-NotificationChannel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Email', 'Teams', 'Slack')]
        [string]$Channel
    )
    $script:NotificationConfig[$Channel].Enabled = $true
}

function Disable-NotificationChannel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Email', 'Teams', 'Slack')]
        [string]$Channel
    )
    $script:NotificationConfig[$Channel].Enabled = $false
}

#endregion

#region Email

function Send-EmailNotification {
    <#
    .SYNOPSIS
    Sends an email notification.
    .PARAMETER Subject
    Email subject line.
    .PARAMETER Body
    Email body (HTML supported).
    .PARAMETER Priority
    Email priority: Low, Normal, High.
    .PARAMETER Attachments
    Array of file paths to attach.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Subject,
        [Parameter(Mandatory)][string]$Body,
        [ValidateSet('Low', 'Normal', 'High')]
        [string]$Priority = 'Normal',
        [string[]]$Attachments
    )

    $config = $script:NotificationConfig.Email

    if (-not $config.Enabled) {
        Write-Verbose "[Notification] Email notifications disabled"
        return $false
    }

    if (-not $config.SmtpServer -or -not $config.From -or $config.To.Count -eq 0) {
        Write-Warning "[Notification] Email not configured properly"
        return $false
    }

    try {
        $mailParams = @{
            From = $config.From
            To = $config.To
            Subject = $Subject
            Body = $Body
            BodyAsHtml = $true
            SmtpServer = $config.SmtpServer
            Port = $config.SmtpPort
            Priority = $Priority
        }

        if ($config.UseSsl) {
            $mailParams.UseSsl = $true
        }

        if ($config.Cc -and $config.Cc.Count -gt 0) {
            $mailParams.Cc = $config.Cc
        }

        if ($config.Credential) {
            $mailParams.Credential = $config.Credential
        }

        if ($Attachments -and $Attachments.Count -gt 0) {
            $mailParams.Attachments = $Attachments | Where-Object { Test-Path $_ }
        }

        Send-MailMessage @mailParams -ErrorAction Stop

        Add-NotificationToHistory -Channel 'Email' -Subject $Subject -Success $true

        Write-Verbose "[Notification] Email sent: $Subject"
        return $true

    } catch {
        Write-Warning "[Notification] Email failed: $($_.Exception.Message)"
        Add-NotificationToHistory -Channel 'Email' -Subject $Subject -Success $false -Error $_.Exception.Message
        return $false
    }
}

#endregion

#region Microsoft Teams

function Send-TeamsNotification {
    <#
    .SYNOPSIS
    Sends a notification to Microsoft Teams via webhook.
    .PARAMETER Title
    Card title.
    .PARAMETER Message
    Main message text.
    .PARAMETER Severity
    Alert severity for color coding.
    .PARAMETER Facts
    Hashtable of additional facts to display.
    .PARAMETER ActionUrl
    Optional URL for action button.
    .PARAMETER ActionText
    Text for action button.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('Critical', 'High', 'Medium', 'Low', 'Info')]
        [string]$Severity = 'Info',
        [hashtable]$Facts,
        [string]$ActionUrl,
        [string]$ActionText = 'View Details'
    )

    $config = $script:NotificationConfig.Teams

    if (-not $config.Enabled) {
        Write-Verbose "[Notification] Teams notifications disabled"
        return $false
    }

    if (-not $config.WebhookUrl) {
        Write-Warning "[Notification] Teams webhook URL not configured"
        return $false
    }

    # Color based on severity
    $colorMap = @{
        Critical = 'FF0000'
        High = 'FF6600'
        Medium = 'FFCC00'
        Low = '00CC00'
        Info = '0078D7'
    }
    $themeColor = $colorMap[$Severity]

    # Build Adaptive Card payload
    $card = @{
        '@type' = 'MessageCard'
        '@context' = 'http://schema.org/extensions'
        themeColor = $themeColor
        summary = $Title
        sections = @(
            @{
                activityTitle = $Title
                activitySubtitle = "StateTrace Alert - $Severity"
                activityImage = 'https://raw.githubusercontent.com/microsoft/fluentui-emoji/main/assets/Satellite/3D/satellite_3d.png'
                facts = @()
                markdown = $true
                text = $Message
            }
        )
    }

    # Add facts
    if ($Facts) {
        foreach ($key in $Facts.Keys) {
            $card.sections[0].facts += @{
                name = $key
                value = [string]$Facts[$key]
            }
        }
    }

    # Add timestamp fact
    $card.sections[0].facts += @{
        name = 'Time'
        value = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    }

    # Add action button
    if ($ActionUrl) {
        $card.potentialAction = @(
            @{
                '@type' = 'OpenUri'
                name = $ActionText
                targets = @(
                    @{ os = 'default'; uri = $ActionUrl }
                )
            }
        )
    }

    try {
        $json = $card | ConvertTo-Json -Depth 10
        $response = Invoke-RestMethod -Uri $config.WebhookUrl -Method Post -Body $json -ContentType 'application/json' -ErrorAction Stop

        Add-NotificationToHistory -Channel 'Teams' -Subject $Title -Success $true

        Write-Verbose "[Notification] Teams message sent: $Title"
        return $true

    } catch {
        Write-Warning "[Notification] Teams failed: $($_.Exception.Message)"
        Add-NotificationToHistory -Channel 'Teams' -Subject $Title -Success $false -Error $_.Exception.Message
        return $false
    }
}

#endregion

#region Slack

function Send-SlackNotification {
    <#
    .SYNOPSIS
    Sends a notification to Slack via webhook.
    .PARAMETER Title
    Message title.
    .PARAMETER Message
    Main message text.
    .PARAMETER Severity
    Alert severity for color coding.
    .PARAMETER Fields
    Array of field hashtables with 'title' and 'value' keys.
    .PARAMETER ActionUrl
    Optional URL for action button.
    .PARAMETER ActionText
    Text for action button.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('Critical', 'High', 'Medium', 'Low', 'Info')]
        [string]$Severity = 'Info',
        [array]$Fields,
        [string]$ActionUrl,
        [string]$ActionText = 'View Details'
    )

    $config = $script:NotificationConfig.Slack

    if (-not $config.Enabled) {
        Write-Verbose "[Notification] Slack notifications disabled"
        return $false
    }

    if (-not $config.WebhookUrl) {
        Write-Warning "[Notification] Slack webhook URL not configured"
        return $false
    }

    # Color based on severity
    $colorMap = @{
        Critical = 'danger'
        High = '#FF6600'
        Medium = 'warning'
        Low = 'good'
        Info = '#0078D7'
    }
    $color = $colorMap[$Severity]

    # Emoji based on severity
    $emojiMap = @{
        Critical = ':rotating_light:'
        High = ':warning:'
        Medium = ':large_orange_diamond:'
        Low = ':information_source:'
        Info = ':speech_balloon:'
    }
    $emoji = $emojiMap[$Severity]

    # Build Block Kit payload
    $attachment = @{
        fallback = "$Title - $Message"
        color = $color
        pretext = "$emoji *$Severity Alert*"
        title = $Title
        text = $Message
        fields = @()
        footer = 'StateTrace'
        footer_icon = 'https://raw.githubusercontent.com/microsoft/fluentui-emoji/main/assets/Satellite/3D/satellite_3d.png'
        ts = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    }

    # Add fields
    if ($Fields) {
        foreach ($field in $Fields) {
            $attachment.fields += @{
                title = $field.title
                value = $field.value
                short = if ($field.short) { $true } else { $false }
            }
        }
    }

    $payload = @{
        username = $config.Username
        icon_emoji = $config.IconEmoji
        attachments = @($attachment)
    }

    if ($config.Channel) {
        $payload.channel = $config.Channel
    }

    # Add action button
    if ($ActionUrl) {
        $attachment.actions = @(
            @{
                type = 'button'
                text = $ActionText
                url = $ActionUrl
            }
        )
    }

    try {
        $json = $payload | ConvertTo-Json -Depth 10
        $response = Invoke-RestMethod -Uri $config.WebhookUrl -Method Post -Body $json -ContentType 'application/json' -ErrorAction Stop

        Add-NotificationToHistory -Channel 'Slack' -Subject $Title -Success $true

        Write-Verbose "[Notification] Slack message sent: $Title"
        return $true

    } catch {
        Write-Warning "[Notification] Slack failed: $($_.Exception.Message)"
        Add-NotificationToHistory -Channel 'Slack' -Subject $Title -Success $false -Error $_.Exception.Message
        return $false
    }
}

#endregion

#region Unified Send

function Send-AlertNotification {
    <#
    .SYNOPSIS
    Sends an alert notification to all enabled channels.
    .PARAMETER Alert
    PSCustomObject with alert details.
    .PARAMETER Channels
    Specific channels to notify. If not specified, uses all enabled.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Alert,
        [ValidateSet('Email', 'Teams', 'Slack')]
        [string[]]$Channels
    )

    $targetChannels = if ($Channels) { $Channels } else { @('Email', 'Teams', 'Slack') }
    $results = @{}

    $title = "[$($Alert.Severity)] $($Alert.RuleName)"
    $message = $Alert.Message
    if (-not $message) { $message = "Alert fired from $($Alert.Source)" }

    $facts = @{
        Source = $Alert.Source
        Category = $Alert.Category
        Severity = $Alert.Severity
        'Alert ID' = $Alert.Id
    }

    foreach ($channel in $targetChannels) {
        if (-not $script:NotificationConfig[$channel].Enabled) {
            continue
        }

        switch ($channel) {
            'Email' {
                $htmlBody = @"
<html>
<body style="font-family: Arial, sans-serif;">
<h2 style="color: $(if ($Alert.Severity -eq 'Critical') { '#FF0000' } else { '#FF6600' });">$title</h2>
<p>$message</p>
<table style="border-collapse: collapse;">
<tr><td style="padding: 5px; font-weight: bold;">Source:</td><td style="padding: 5px;">$($Alert.Source)</td></tr>
<tr><td style="padding: 5px; font-weight: bold;">Category:</td><td style="padding: 5px;">$($Alert.Category)</td></tr>
<tr><td style="padding: 5px; font-weight: bold;">Time:</td><td style="padding: 5px;">$($Alert.FiredAt.ToString('yyyy-MM-dd HH:mm:ss')) UTC</td></tr>
<tr><td style="padding: 5px; font-weight: bold;">Alert ID:</td><td style="padding: 5px;">$($Alert.Id)</td></tr>
</table>
<hr/>
<p style="color: #666; font-size: 12px;">This alert was generated by StateTrace.</p>
</body>
</html>
"@
                $results.Email = Send-EmailNotification -Subject $title -Body $htmlBody -Priority $(if ($Alert.Severity -eq 'Critical') { 'High' } else { 'Normal' })
            }
            'Teams' {
                $results.Teams = Send-TeamsNotification -Title $title -Message $message -Severity $Alert.Severity -Facts $facts
            }
            'Slack' {
                $fields = @(
                    @{ title = 'Source'; value = $Alert.Source; short = $true }
                    @{ title = 'Category'; value = $Alert.Category; short = $true }
                )
                $results.Slack = Send-SlackNotification -Title $title -Message $message -Severity $Alert.Severity -Fields $fields
            }
        }
    }

    return $results
}

#endregion

#region History

function Add-NotificationToHistory {
    param(
        [string]$Channel,
        [string]$Subject,
        [bool]$Success,
        [string]$Error
    )

    $entry = [PSCustomObject]@{
        Timestamp = [datetime]::UtcNow
        Channel = $Channel
        Subject = $Subject
        Success = $Success
        Error = $Error
    }

    [void]$script:NotificationHistory.Add($entry)

    while ($script:NotificationHistory.Count -gt $script:MaxHistorySize) {
        $script:NotificationHistory.RemoveAt(0)
    }
}

function Get-NotificationHistory {
    <#
    .SYNOPSIS
    Returns notification history.
    #>
    [CmdletBinding()]
    param(
        [int]$Last = 50,
        [string]$Channel,
        [switch]$FailedOnly
    )

    $history = $script:NotificationHistory

    if ($Channel) {
        $history = $history | Where-Object { $_.Channel -eq $Channel }
    }
    if ($FailedOnly.IsPresent) {
        $history = $history | Where-Object { -not $_.Success }
    }

    return $history | Select-Object -Last $Last
}

#endregion

Export-ModuleMember -Function @(
    'Set-NotificationConfig',
    'Get-NotificationConfig',
    'Enable-NotificationChannel',
    'Disable-NotificationChannel',
    'Send-EmailNotification',
    'Send-TeamsNotification',
    'Send-SlackNotification',
    'Send-AlertNotification',
    'Get-NotificationHistory'
)
