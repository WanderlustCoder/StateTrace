# ExternalIntegrationModule.psm1
# External service integrations for ServiceNow, Jira, and webhook publishing

Set-StrictMode -Version Latest

#region Configuration

$script:IntegrationConfig = @{
    ServiceNow = @{
        Enabled = $false
        InstanceUrl = ''
        Username = ''
        Password = $null  # SecureString
        TableName = 'cmdb_ci_netgear'
        ApiVersion = 'v2'
    }
    Jira = @{
        Enabled = $false
        BaseUrl = ''
        Username = ''
        ApiToken = $null  # SecureString
        ProjectKey = ''
        IssueType = 'Task'
    }
    Webhooks = @{
        Enabled = $false
        Endpoints = [System.Collections.Generic.List[object]]::new()
        RetryCount = 3
        RetryDelayMs = 1000
    }
}

$script:WebhookHistory = [System.Collections.Generic.List[object]]::new()
$script:MaxHistorySize = 200

function Set-ServiceNowConfig {
    <#
    .SYNOPSIS
    Configures ServiceNow CMDB integration.
    .PARAMETER InstanceUrl
    ServiceNow instance URL (e.g., https://dev12345.service-now.com).
    .PARAMETER Username
    ServiceNow username.
    .PARAMETER Password
    ServiceNow password as SecureString.
    .PARAMETER TableName
    CMDB table name. Default 'cmdb_ci_netgear'.
    .EXAMPLE
    Set-ServiceNowConfig -InstanceUrl 'https://dev12345.service-now.com' -Username 'admin' -Password $securePassword
    #>
    [CmdletBinding()]
    param(
        [string]$InstanceUrl,
        [string]$Username,
        [System.Security.SecureString]$Password,
        [string]$TableName
    )

    if ($InstanceUrl) { $script:IntegrationConfig.ServiceNow.InstanceUrl = $InstanceUrl.TrimEnd('/') }
    if ($Username) { $script:IntegrationConfig.ServiceNow.Username = $Username }
    if ($Password) { $script:IntegrationConfig.ServiceNow.Password = $Password }
    if ($TableName) { $script:IntegrationConfig.ServiceNow.TableName = $TableName }

    if ($InstanceUrl -and $Username -and $Password) {
        $script:IntegrationConfig.ServiceNow.Enabled = $true
    }
}

function Set-JiraConfig {
    <#
    .SYNOPSIS
    Configures Jira integration for alert escalation.
    .PARAMETER BaseUrl
    Jira instance URL (e.g., https://company.atlassian.net).
    .PARAMETER Username
    Jira username/email.
    .PARAMETER ApiToken
    Jira API token as SecureString.
    .PARAMETER ProjectKey
    Jira project key (e.g., NET, OPS).
    .PARAMETER IssueType
    Default issue type. Default 'Task'.
    .EXAMPLE
    Set-JiraConfig -BaseUrl 'https://company.atlassian.net' -Username 'user@company.com' -ApiToken $token -ProjectKey 'NET'
    #>
    [CmdletBinding()]
    param(
        [string]$BaseUrl,
        [string]$Username,
        [System.Security.SecureString]$ApiToken,
        [string]$ProjectKey,
        [string]$IssueType
    )

    if ($BaseUrl) { $script:IntegrationConfig.Jira.BaseUrl = $BaseUrl.TrimEnd('/') }
    if ($Username) { $script:IntegrationConfig.Jira.Username = $Username }
    if ($ApiToken) { $script:IntegrationConfig.Jira.ApiToken = $ApiToken }
    if ($ProjectKey) { $script:IntegrationConfig.Jira.ProjectKey = $ProjectKey }
    if ($IssueType) { $script:IntegrationConfig.Jira.IssueType = $IssueType }

    if ($BaseUrl -and $Username -and $ApiToken -and $ProjectKey) {
        $script:IntegrationConfig.Jira.Enabled = $true
    }
}

function Add-WebhookEndpoint {
    <#
    .SYNOPSIS
    Adds a webhook endpoint for event publishing.
    .PARAMETER Url
    Webhook URL.
    .PARAMETER Name
    Friendly name for the endpoint.
    .PARAMETER Events
    Array of event types to subscribe to. Default all events.
    .PARAMETER Headers
    Optional hashtable of custom headers.
    .PARAMETER Secret
    Optional signing secret for HMAC signature.
    .EXAMPLE
    Add-WebhookEndpoint -Url 'https://example.com/webhook' -Name 'My Webhook' -Events @('AlertFired', 'DeviceDown')
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Url,
        [string]$Name = 'Webhook',
        [string[]]$Events = @('*'),
        [hashtable]$Headers = @{},
        [string]$Secret
    )

    $endpoint = [PSCustomObject]@{
        Id = [guid]::NewGuid().ToString('N').Substring(0, 8)
        Url = $Url
        Name = $Name
        Events = $Events
        Headers = $Headers
        Secret = $Secret
        Enabled = $true
        CreatedAt = [datetime]::UtcNow
        SuccessCount = 0
        FailureCount = 0
    }

    [void]$script:IntegrationConfig.Webhooks.Endpoints.Add($endpoint)
    $script:IntegrationConfig.Webhooks.Enabled = $true

    return $endpoint
}

function Remove-WebhookEndpoint {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Id)

    $endpoint = $script:IntegrationConfig.Webhooks.Endpoints | Where-Object { $_.Id -eq $Id }
    if ($endpoint) {
        $script:IntegrationConfig.Webhooks.Endpoints.Remove($endpoint) | Out-Null
        return $true
    }
    return $false
}

function Get-IntegrationConfig {
    [CmdletBinding()]
    param([string]$Integration)

    if ($Integration) {
        return $script:IntegrationConfig[$Integration]
    }
    return $script:IntegrationConfig
}

#endregion

#region ServiceNow

function Sync-DeviceToServiceNow {
    <#
    .SYNOPSIS
    Syncs a device to ServiceNow CMDB.
    .PARAMETER Device
    Device object with Hostname, Make, Model, etc.
    .OUTPUTS
    ServiceNow record sys_id on success.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Device
    )

    $config = $script:IntegrationConfig.ServiceNow

    if (-not $config.Enabled) {
        Write-Verbose "[ServiceNow] Integration not enabled"
        return $null
    }

    # Build CMDB record
    $record = @{
        name = $Device.Hostname
        manufacturer = $Device.Make
        model_id = $Device.Model
        os_version = $Device.Version
        location = $Device.Location
        operational_status = 1  # Operational
        u_site = $Device.Site
        u_interface_count = $Device.InterfaceCount
        u_last_sync = [datetime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss')
    }

    try {
        $cred = [PSCredential]::new($config.Username, $config.Password)
        $uri = "$($config.InstanceUrl)/api/now/$($config.ApiVersion)/table/$($config.TableName)"

        # Check if record exists
        $searchUri = "$uri`?sysparm_query=name=$($Device.Hostname)&sysparm_limit=1"
        $existing = Invoke-RestMethod -Uri $searchUri -Credential $cred -Method Get -ContentType 'application/json'

        if ($existing.result -and $existing.result.Count -gt 0) {
            # Update existing record
            $sysId = $existing.result[0].sys_id
            $updateUri = "$uri/$sysId"
            $result = Invoke-RestMethod -Uri $updateUri -Credential $cred -Method Patch -Body ($record | ConvertTo-Json) -ContentType 'application/json'
            Write-Verbose "[ServiceNow] Updated record: $sysId"
            return $sysId
        } else {
            # Create new record
            $result = Invoke-RestMethod -Uri $uri -Credential $cred -Method Post -Body ($record | ConvertTo-Json) -ContentType 'application/json'
            $sysId = $result.result.sys_id
            Write-Verbose "[ServiceNow] Created record: $sysId"
            return $sysId
        }

    } catch {
        Write-Warning "[ServiceNow] Sync failed: $($_.Exception.Message)"
        return $null
    }
}

function Sync-AllDevicesToServiceNow {
    <#
    .SYNOPSIS
    Syncs all devices to ServiceNow CMDB.
    #>
    [CmdletBinding()]
    param()

    $projectRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $projectRoot 'Modules\DeviceRepositoryModule.psm1') -Force -DisableNameChecking -ErrorAction SilentlyContinue

    try {
        $devices = Get-AllDevices
        $results = @{ success = 0; failed = 0; errors = @() }

        foreach ($device in $devices) {
            $sysId = Sync-DeviceToServiceNow -Device $device
            if ($sysId) {
                $results.success++
            } else {
                $results.failed++
                $results.errors += $device.Hostname
            }
        }

        return $results

    } catch {
        return @{ success = 0; failed = 0; error = $_.Exception.Message }
    }
}

#endregion

#region Jira

function New-JiraIssue {
    <#
    .SYNOPSIS
    Creates a Jira issue for alert escalation.
    .PARAMETER Summary
    Issue summary/title.
    .PARAMETER Description
    Issue description.
    .PARAMETER Priority
    Jira priority: Highest, High, Medium, Low, Lowest.
    .PARAMETER Labels
    Array of labels.
    .PARAMETER CustomFields
    Hashtable of custom field IDs and values.
    .OUTPUTS
    Jira issue key (e.g., NET-123).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Summary,
        [string]$Description = '',
        [ValidateSet('Highest', 'High', 'Medium', 'Low', 'Lowest')]
        [string]$Priority = 'Medium',
        [string[]]$Labels = @(),
        [hashtable]$CustomFields = @{}
    )

    $config = $script:IntegrationConfig.Jira

    if (-not $config.Enabled) {
        Write-Verbose "[Jira] Integration not enabled"
        return $null
    }

    # Priority mapping
    $priorityMap = @{
        Highest = '1'
        High = '2'
        Medium = '3'
        Low = '4'
        Lowest = '5'
    }

    # Build issue payload
    $issue = @{
        fields = @{
            project = @{ key = $config.ProjectKey }
            summary = $Summary
            description = $Description
            issuetype = @{ name = $config.IssueType }
            priority = @{ id = $priorityMap[$Priority] }
        }
    }

    if ($Labels.Count -gt 0) {
        $issue.fields.labels = $Labels
    }

    foreach ($key in $CustomFields.Keys) {
        $issue.fields[$key] = $CustomFields[$key]
    }

    try {
        $plainToken = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($config.ApiToken)
        )
        $authBytes = [Text.Encoding]::ASCII.GetBytes("$($config.Username):$plainToken")
        $authHeader = "Basic $([Convert]::ToBase64String($authBytes))"

        $uri = "$($config.BaseUrl)/rest/api/3/issue"
        $headers = @{
            'Authorization' = $authHeader
            'Content-Type' = 'application/json'
        }

        $result = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body ($issue | ConvertTo-Json -Depth 10)
        $issueKey = $result.key

        Write-Verbose "[Jira] Created issue: $issueKey"
        return $issueKey

    } catch {
        Write-Warning "[Jira] Issue creation failed: $($_.Exception.Message)"
        return $null
    }
}

function New-JiraIssueFromAlert {
    <#
    .SYNOPSIS
    Creates a Jira issue from a StateTrace alert.
    .PARAMETER Alert
    Alert object from AlertRuleModule.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Alert
    )

    $priorityMap = @{
        Critical = 'Highest'
        High = 'High'
        Medium = 'Medium'
        Low = 'Low'
        Info = 'Lowest'
    }

    $summary = "[$($Alert.Severity)] $($Alert.RuleName) - $($Alert.Source)"

    $description = @"
h2. Alert Details

|*Field*|*Value*|
|Alert ID|$($Alert.Id)|
|Rule|$($Alert.RuleName)|
|Source|$($Alert.Source)|
|Category|$($Alert.Category)|
|Severity|$($Alert.Severity)|
|Fired At|$($Alert.FiredAt.ToString('yyyy-MM-dd HH:mm:ss')) UTC|

h3. Message
$($Alert.Message)

----
_This issue was automatically created by StateTrace._
"@

    $labels = @('statetrace', 'alert', $Alert.Category.ToLower())

    return New-JiraIssue -Summary $summary -Description $description -Priority $priorityMap[$Alert.Severity] -Labels $labels
}

#endregion

#region Webhooks

function Publish-WebhookEvent {
    <#
    .SYNOPSIS
    Publishes an event to all subscribed webhook endpoints.
    .PARAMETER EventType
    Type of event: AlertFired, AlertResolved, DeviceDown, DeviceUp, ConfigChange, etc.
    .PARAMETER Payload
    Event data as hashtable.
    .OUTPUTS
    Array of delivery results.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$EventType,
        [Parameter(Mandatory)][hashtable]$Payload
    )

    $config = $script:IntegrationConfig.Webhooks

    if (-not $config.Enabled -or $config.Endpoints.Count -eq 0) {
        Write-Verbose "[Webhook] No endpoints configured"
        return @()
    }

    $event = @{
        id = [guid]::NewGuid().ToString()
        type = $EventType
        timestamp = [datetime]::UtcNow.ToString('o')
        source = 'StateTrace'
        data = $Payload
    }

    $json = $event | ConvertTo-Json -Depth 10 -Compress
    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($endpoint in $config.Endpoints) {
        if (-not $endpoint.Enabled) { continue }

        # Check event subscription
        if ($endpoint.Events -notcontains '*' -and $endpoint.Events -notcontains $EventType) {
            continue
        }

        $result = Invoke-WebhookDelivery -Endpoint $endpoint -Json $json -Event $event
        [void]$results.Add($result)
    }

    return $results.ToArray()
}

function Invoke-WebhookDelivery {
    param(
        [object]$Endpoint,
        [string]$Json,
        [object]$Event
    )

    $config = $script:IntegrationConfig.Webhooks
    $success = $false
    $statusCode = 0
    $error = $null

    $headers = @{
        'Content-Type' = 'application/json'
        'User-Agent' = 'StateTrace-Webhook/1.0'
        'X-StateTrace-Event' = $Event.type
        'X-StateTrace-Delivery' = $Event.id
    }

    # Add custom headers
    foreach ($key in $Endpoint.Headers.Keys) {
        $headers[$key] = $Endpoint.Headers[$key]
    }

    # Add HMAC signature if secret is configured
    if ($Endpoint.Secret) {
        $hmac = [System.Security.Cryptography.HMACSHA256]::new([Text.Encoding]::UTF8.GetBytes($Endpoint.Secret))
        $hash = $hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($Json))
        $signature = 'sha256=' + [BitConverter]::ToString($hash).Replace('-', '').ToLower()
        $headers['X-StateTrace-Signature'] = $signature
    }

    for ($attempt = 1; $attempt -le $config.RetryCount; $attempt++) {
        try {
            $response = Invoke-WebRequest -Uri $Endpoint.Url -Method Post -Headers $headers -Body $Json -UseBasicParsing -TimeoutSec 30
            $statusCode = $response.StatusCode
            $success = $statusCode -ge 200 -and $statusCode -lt 300
            break

        } catch {
            $error = $_.Exception.Message
            if ($_.Exception.Response) {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            if ($attempt -lt $config.RetryCount) {
                Start-Sleep -Milliseconds $config.RetryDelayMs
            }
        }
    }

    # Update endpoint stats
    if ($success) {
        $Endpoint.SuccessCount++
    } else {
        $Endpoint.FailureCount++
    }

    $deliveryResult = [PSCustomObject]@{
        EndpointId = $Endpoint.Id
        EndpointName = $Endpoint.Name
        EventId = $Event.id
        EventType = $Event.type
        Success = $success
        StatusCode = $statusCode
        Error = $error
        Timestamp = [datetime]::UtcNow
    }

    # Add to history
    [void]$script:WebhookHistory.Add($deliveryResult)
    while ($script:WebhookHistory.Count -gt $script:MaxHistorySize) {
        $script:WebhookHistory.RemoveAt(0)
    }

    if ($success) {
        Write-Verbose "[Webhook] Delivered to $($Endpoint.Name): $($Event.type)"
    } else {
        Write-Warning "[Webhook] Failed to deliver to $($Endpoint.Name): $error"
    }

    return $deliveryResult
}

function Get-WebhookHistory {
    <#
    .SYNOPSIS
    Returns webhook delivery history.
    #>
    [CmdletBinding()]
    param(
        [int]$Last = 50,
        [switch]$FailedOnly
    )

    $history = $script:WebhookHistory

    if ($FailedOnly.IsPresent) {
        $history = $history | Where-Object { -not $_.Success }
    }

    return $history | Select-Object -Last $Last
}

function Get-WebhookEndpoints {
    return $script:IntegrationConfig.Webhooks.Endpoints
}

#endregion

Export-ModuleMember -Function @(
    # Configuration
    'Set-ServiceNowConfig',
    'Set-JiraConfig',
    'Add-WebhookEndpoint',
    'Remove-WebhookEndpoint',
    'Get-IntegrationConfig',
    # ServiceNow
    'Sync-DeviceToServiceNow',
    'Sync-AllDevicesToServiceNow',
    # Jira
    'New-JiraIssue',
    'New-JiraIssueFromAlert',
    # Webhooks
    'Publish-WebhookEvent',
    'Get-WebhookHistory',
    'Get-WebhookEndpoints'
)
