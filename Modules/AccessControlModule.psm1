# AccessControlModule.psm1
# Role-based access control, permission enforcement, audit logging, and authentication

Set-StrictMode -Version Latest

#region Role Definitions
$script:Roles = @{
    Viewer = @{
        Name = 'Viewer'
        Description = 'Read-only access to dashboards and reports'
        Level = 1
        Permissions = @(
            'View.Dashboard',
            'View.Devices',
            'View.Interfaces',
            'View.Reports',
            'View.Telemetry',
            'View.Alerts',
            'Export.Reports'
        )
    }
    Operator = @{
        Name = 'Operator'
        Description = 'Can perform operational tasks and run reports'
        Level = 2
        Permissions = @(
            'View.Dashboard',
            'View.Devices',
            'View.Interfaces',
            'View.Reports',
            'View.Telemetry',
            'View.Alerts',
            'Export.Reports',
            'Run.HealthCheck',
            'Run.Runbook',
            'Manage.Alerts',
            'Refresh.Data',
            'Execute.BulkRead'
        )
    }
    Admin = @{
        Name = 'Admin'
        Description = 'Full administrative access'
        Level = 3
        Permissions = @(
            'View.Dashboard',
            'View.Devices',
            'View.Interfaces',
            'View.Reports',
            'View.Telemetry',
            'View.Alerts',
            'View.AuditLog',
            'View.Settings',
            'Export.Reports',
            'Run.HealthCheck',
            'Run.Runbook',
            'Manage.Alerts',
            'Refresh.Data',
            'Execute.BulkRead',
            'Execute.BulkWrite',
            'Manage.Users',
            'Manage.Roles',
            'Manage.Settings',
            'Manage.Database',
            'Execute.Maintenance',
            'Admin.Full'
        )
    }
}

$script:CurrentUser = $null
$script:CurrentSession = $null
$script:AuditLogPath = $null

function Get-RoleDefinitions {
    [CmdletBinding()]
    param(
        [string]$RoleName
    )

    if ($RoleName) {
        # Case-insensitive role lookup
        $matchedKey = $script:Roles.Keys | Where-Object { [string]::Equals($_, $RoleName, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
        if ($matchedKey) {
            return [PSCustomObject]$script:Roles[$matchedKey]
        }
        return $null
    }

    return $script:Roles.Keys | ForEach-Object { [PSCustomObject]$script:Roles[$_] }
}

function Get-RolePermissions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RoleName
    )

    $role = Get-RoleDefinitions -RoleName $RoleName
    if ($role) {
        return $role.Permissions
    }
    return @()
}

function New-CustomRole {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Description,

        [Parameter(Mandatory)]
        [string[]]$Permissions,

        [int]$Level = 1,

        [string]$BasedOn
    )

    $permissions = @($Permissions)

    if ($BasedOn -and $script:Roles.ContainsKey($BasedOn)) {
        $basePermissions = $script:Roles[$BasedOn].Permissions
        $permissions = @($basePermissions) + @($Permissions) | Select-Object -Unique
    }

    $script:Roles[$Name] = @{
        Name = $Name
        Description = $Description
        Level = $Level
        Permissions = $permissions
        Custom = $true
        CreatedAt = [datetime]::UtcNow
    }

    return [PSCustomObject]$script:Roles[$Name]
}
#endregion

#region User Session Management
function Initialize-UserSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Username,

        [string]$Role = 'Viewer',

        [string[]]$Groups,

        [hashtable]$Claims
    )

    $roleDefinition = Get-RoleDefinitions -RoleName $Role
    if (-not $roleDefinition) {
        throw "Invalid role: $Role"
    }

    $script:CurrentUser = @{
        Username = $Username
        Role = $Role
        RoleLevel = $roleDefinition.Level
        Permissions = @($roleDefinition.Permissions)
        Groups = @($Groups)
        Claims = $Claims
        AuthenticatedAt = [datetime]::UtcNow
    }

    $script:CurrentSession = @{
        SessionId = [guid]::NewGuid().ToString()
        StartTime = [datetime]::UtcNow
        LastActivity = [datetime]::UtcNow
        User = $Username
        Role = $Role
    }

    Write-AuditLog -Action 'Session.Start' -Details "User $Username authenticated with role $Role"

    return [PSCustomObject]@{
        SessionId = $script:CurrentSession.SessionId
        User = $script:CurrentUser
    }
}

function Get-CurrentUser {
    [CmdletBinding()]
    param()

    if ($script:CurrentUser) {
        return [PSCustomObject]$script:CurrentUser
    }
    return $null
}

function Get-CurrentSession {
    [CmdletBinding()]
    param()

    if ($script:CurrentSession) {
        $script:CurrentSession.LastActivity = [datetime]::UtcNow
        return [PSCustomObject]$script:CurrentSession
    }
    return $null
}

function Close-UserSession {
    [CmdletBinding()]
    param()

    if ($script:CurrentSession) {
        Write-AuditLog -Action 'Session.End' -Details "Session ended for $($script:CurrentUser.Username)"
    }

    $script:CurrentUser = $null
    $script:CurrentSession = $null
}
#endregion

#region Permission Enforcement
function Test-Permission {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Permission,

        [switch]$Silent
    )

    if (-not $script:CurrentUser) {
        if (-not $Silent) {
            Write-Warning "No user session active. Permission denied."
        }
        return $false
    }

    # Admin.Full grants all permissions
    if ($script:CurrentUser.Permissions -contains 'Admin.Full') {
        return $true
    }

    $hasPermission = $script:CurrentUser.Permissions -contains $Permission

    if (-not $hasPermission -and -not $Silent) {
        Write-Warning "Permission denied: $Permission (User: $($script:CurrentUser.Username), Role: $($script:CurrentUser.Role))"
    }

    return $hasPermission
}

function Assert-Permission {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Permission,

        [string]$Operation
    )

    if (-not (Test-Permission -Permission $Permission -Silent)) {
        $opName = if ($Operation) { $Operation } else { $Permission }
        Write-AuditLog -Action 'Permission.Denied' -Details "Access denied for $opName" -Severity 'Warning'
        throw "Access denied: You do not have permission to perform this operation ($Permission)"
    }

    return $true
}

function Test-RoleLevel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$RequiredLevel
    )

    if (-not $script:CurrentUser) {
        return $false
    }

    return $script:CurrentUser.RoleLevel -ge $RequiredLevel
}

function Get-EffectivePermissions {
    [CmdletBinding()]
    param(
        [string]$Username
    )

    $user = if ($Username) {
        # Would look up user from store
        $null
    } else {
        $script:CurrentUser
    }

    if (-not $user) {
        return @()
    }

    return $user.Permissions
}

function Test-CanAccessFeature {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FeatureName
    )

    $featurePermissionMap = @{
        'Dashboard' = 'View.Dashboard'
        'Devices' = 'View.Devices'
        'Interfaces' = 'View.Interfaces'
        'Reports' = 'View.Reports'
        'Telemetry' = 'View.Telemetry'
        'Alerts' = 'View.Alerts'
        'AlertManagement' = 'Manage.Alerts'
        'Settings' = 'View.Settings'
        'UserManagement' = 'Manage.Users'
        'BulkOperations' = 'Execute.BulkWrite'
        'Runbooks' = 'Run.Runbook'
        'Maintenance' = 'Execute.Maintenance'
        'AuditLog' = 'View.AuditLog'
    }

    $requiredPermission = $featurePermissionMap[$FeatureName]
    if (-not $requiredPermission) {
        return $true  # Unknown features are accessible by default
    }

    return Test-Permission -Permission $requiredPermission -Silent
}
#endregion

#region Audit Logging
function Initialize-AuditLog {
    [CmdletBinding()]
    param(
        [string]$LogPath
    )

    if (-not $LogPath) {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $LogPath = Join-Path $projectRoot 'Logs\Audit'
    }

    if (-not (Test-Path $LogPath)) {
        New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
    }

    $script:AuditLogPath = $LogPath
    return $LogPath
}

function Write-AuditLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Action,

        [string]$Details,

        [string]$TargetResource,

        [string]$TargetId,

        [ValidateSet('Info', 'Warning', 'Error', 'Critical')]
        [string]$Severity = 'Info',

        [hashtable]$AdditionalData
    )

    $entry = [ordered]@{
        Timestamp = [datetime]::UtcNow.ToString('o')
        Action = $Action
        Severity = $Severity
        User = if ($script:CurrentUser) { $script:CurrentUser.Username } else { 'SYSTEM' }
        Role = if ($script:CurrentUser) { $script:CurrentUser.Role } else { $null }
        SessionId = if ($script:CurrentSession) { $script:CurrentSession.SessionId } else { $null }
        Details = $Details
        TargetResource = $TargetResource
        TargetId = $TargetId
        ComputerName = $env:COMPUTERNAME
        ProcessId = $PID
    }

    if ($AdditionalData) {
        foreach ($key in $AdditionalData.Keys) {
            $entry[$key] = $AdditionalData[$key]
        }
    }

    # Write to file
    if ($script:AuditLogPath) {
        $logFile = Join-Path $script:AuditLogPath "audit-$(Get-Date -Format 'yyyy-MM-dd').json"
        $json = $entry | ConvertTo-Json -Compress
        Add-Content -Path $logFile -Value $json -Encoding UTF8
    }

    # Also write to verbose stream
    Write-Verbose "AUDIT: [$Severity] $Action - $Details"

    return [PSCustomObject]$entry
}

function Get-AuditLog {
    [CmdletBinding()]
    param(
        [datetime]$StartTime,

        [datetime]$EndTime,

        [string]$User,

        [string]$Action,

        [string]$Severity,

        [int]$Last = 100
    )

    Assert-Permission -Permission 'View.AuditLog' -Operation 'View audit logs'

    if (-not $script:AuditLogPath -or -not (Test-Path $script:AuditLogPath)) {
        return @()
    }

    $logFiles = Get-ChildItem -Path $script:AuditLogPath -Filter 'audit-*.json' |
        Sort-Object Name -Descending

    $entries = [System.Collections.Generic.List[object]]::new()

    foreach ($file in $logFiles) {
        if ($entries.Count -ge $Last) { break }

        foreach ($line in [System.IO.File]::ReadLines($file.FullName)) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }

            try {
                $entry = $line | ConvertFrom-Json

                # Apply filters
                if ($StartTime -and [datetime]::Parse($entry.Timestamp) -lt $StartTime) { continue }
                if ($EndTime -and [datetime]::Parse($entry.Timestamp) -gt $EndTime) { continue }
                if ($User -and $entry.User -ne $User) { continue }
                if ($Action -and $entry.Action -notlike "*$Action*") { continue }
                if ($Severity -and $entry.Severity -ne $Severity) { continue }

                $entries.Add($entry)
                if ($entries.Count -ge $Last) { break }
            } catch { }
        }
    }

    return $entries.ToArray()
}

function Clear-AuditLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$OlderThanDays,

        [switch]$Force
    )

    Assert-Permission -Permission 'Admin.Full' -Operation 'Clear audit logs'

    if (-not $Force) {
        throw "Use -Force to confirm audit log deletion"
    }

    $cutoffDate = [datetime]::UtcNow.AddDays(-$OlderThanDays)
    $deleted = 0

    $logFiles = Get-ChildItem -Path $script:AuditLogPath -Filter 'audit-*.json'

    foreach ($file in $logFiles) {
        $dateStr = $file.BaseName -replace 'audit-', ''
        try {
            $fileDate = [datetime]::ParseExact($dateStr, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
            if ($fileDate -lt $cutoffDate) {
                Remove-Item $file.FullName -Force
                $deleted++
            }
        } catch { }
    }

    Write-AuditLog -Action 'AuditLog.Clear' -Details "Deleted $deleted log files older than $OlderThanDays days" -Severity 'Warning'

    return @{
        DeletedFiles = $deleted
        CutoffDate = $cutoffDate
    }
}
#endregion

#region UI Permission Helpers
function Get-UIPermissionState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Elements
    )

    $state = @{}

    foreach ($element in $Elements) {
        $state[$element] = @{
            Visible = $true
            Enabled = $true
            Reason = $null
        }

        $permission = switch -Wildcard ($element) {
            'btn_*Settings*' { 'Manage.Settings' }
            'btn_*User*' { 'Manage.Users' }
            'btn_*Delete*' { 'Execute.BulkWrite' }
            'btn_*Edit*' { 'Execute.BulkWrite' }
            'btn_*Bulk*' { 'Execute.BulkWrite' }
            'btn_*Runbook*' { 'Run.Runbook' }
            'btn_*Maintenance*' { 'Execute.Maintenance' }
            'btn_*Refresh*' { 'Refresh.Data' }
            'btn_*Export*' { 'Export.Reports' }
            'menu_Admin*' { 'Admin.Full' }
            'menu_Settings*' { 'View.Settings' }
            'tab_Audit*' { 'View.AuditLog' }
            default { $null }
        }

        if ($permission) {
            $hasPermission = Test-Permission -Permission $permission -Silent

            if (-not $hasPermission) {
                $state[$element].Enabled = $false
                $state[$element].Reason = "Requires permission: $permission"
            }
        }
    }

    return $state
}

function Get-MenuVisibility {
    [CmdletBinding()]
    param()

    return @{
        Dashboard = Test-CanAccessFeature -FeatureName 'Dashboard'
        Devices = Test-CanAccessFeature -FeatureName 'Devices'
        Interfaces = Test-CanAccessFeature -FeatureName 'Interfaces'
        Reports = Test-CanAccessFeature -FeatureName 'Reports'
        Alerts = Test-CanAccessFeature -FeatureName 'Alerts'
        AlertManagement = Test-CanAccessFeature -FeatureName 'AlertManagement'
        BulkOperations = Test-CanAccessFeature -FeatureName 'BulkOperations'
        Runbooks = Test-CanAccessFeature -FeatureName 'Runbooks'
        Settings = Test-CanAccessFeature -FeatureName 'Settings'
        UserManagement = Test-CanAccessFeature -FeatureName 'UserManagement'
        AuditLog = Test-CanAccessFeature -FeatureName 'AuditLog'
        Maintenance = Test-CanAccessFeature -FeatureName 'Maintenance'
    }
}
#endregion

#region AD/LDAP Integration
function Get-ADGroupMembership {
    [CmdletBinding()]
    param(
        [string]$Username,

        [string]$Domain
    )

    if (-not $Username) {
        $Username = $env:USERNAME
    }

    if (-not $Domain) {
        $Domain = $env:USERDOMAIN
    }

    $groups = @()

    try {
        # Try using .NET DirectoryServices
        $searcher = [System.DirectoryServices.DirectorySearcher]::new()
        $searcher.Filter = "(&(objectClass=user)(sAMAccountName=$Username))"
        $searcher.PropertiesToLoad.Add('memberOf') | Out-Null

        $result = $searcher.FindOne()
        if ($result -and $result.Properties['memberOf']) {
            foreach ($groupDN in $result.Properties['memberOf']) {
                # Extract CN from DN
                if ($groupDN -match 'CN=([^,]+)') {
                    $groups += $matches[1]
                }
            }
        }
    } catch {
        Write-Verbose "AD lookup failed: $($_.Exception.Message)"
        # Fallback: Try whoami /groups
        try {
            $whoamiOutput = whoami /groups /fo csv 2>$null | ConvertFrom-Csv
            $groups = $whoamiOutput | Where-Object { $_.'Type' -eq 'Group' } |
                ForEach-Object { $_.'Group Name'.Split('\')[-1] }
        } catch { }
    }

    return $groups
}

function Initialize-ADAuthentication {
    [CmdletBinding()]
    param(
        [hashtable]$GroupRoleMapping
    )

    $username = $env:USERNAME
    $domain = $env:USERDOMAIN

    $groups = Get-ADGroupMembership -Username $username -Domain $domain

    # Default group-to-role mapping
    $defaultMapping = @{
        'StateTrace-Admins' = 'Admin'
        'StateTrace-Operators' = 'Operator'
        'StateTrace-Viewers' = 'Viewer'
        'Domain Admins' = 'Admin'
    }

    $mapping = if ($GroupRoleMapping) { $GroupRoleMapping } else { $defaultMapping }

    # Find highest role based on group membership
    $role = 'Viewer'  # Default
    $roleLevel = 1

    foreach ($group in $groups) {
        if ($mapping.ContainsKey($group)) {
            $mappedRole = $mapping[$group]
            $mappedRoleInfo = Get-RoleDefinitions -RoleName $mappedRole
            if ($mappedRoleInfo -and $mappedRoleInfo.Level -gt $roleLevel) {
                $role = $mappedRole
                $roleLevel = $mappedRoleInfo.Level
            }
        }
    }

    return Initialize-UserSession -Username "$domain\$username" -Role $role -Groups $groups
}
#endregion

#region API Token Authentication
$script:ApiTokens = @{}

function New-ApiToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Role,

        [int]$ExpirationDays = 365,

        [string[]]$AllowedIPs,

        [string[]]$Scopes
    )

    Assert-Permission -Permission 'Admin.Full' -Operation 'Create API token'

    $roleDefinition = Get-RoleDefinitions -RoleName $Role
    if (-not $roleDefinition) {
        throw "Invalid role: $Role"
    }

    $tokenId = [guid]::NewGuid().ToString()
    $tokenSecret = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes([guid]::NewGuid().ToString() + [guid]::NewGuid().ToString()))

    $token = @{
        Id = $tokenId
        Name = $Name
        TokenHash = [Convert]::ToBase64String([System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($tokenSecret)))
        Role = $Role
        Permissions = @($roleDefinition.Permissions)
        Scopes = @($Scopes)
        AllowedIPs = @($AllowedIPs)
        CreatedAt = [datetime]::UtcNow
        ExpiresAt = [datetime]::UtcNow.AddDays($ExpirationDays)
        CreatedBy = if ($script:CurrentUser) { $script:CurrentUser.Username } else { 'SYSTEM' }
        LastUsed = $null
        UseCount = 0
        Enabled = $true
    }

    $script:ApiTokens[$tokenId] = $token

    Write-AuditLog -Action 'ApiToken.Create' -Details "Created API token: $Name" -TargetResource 'ApiToken' -TargetId $tokenId

    # Return token with secret (only time it's visible)
    return [PSCustomObject]@{
        Id = $tokenId
        Name = $Name
        Token = $tokenSecret
        ExpiresAt = $token.ExpiresAt
        Role = $Role
        Warning = 'Store this token securely. It will not be shown again.'
    }
}

function Test-ApiToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Token,

        [string]$RequiredPermission,

        [string]$ClientIP
    )

    $tokenHash = [Convert]::ToBase64String([System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Token)))

    $matchingToken = $script:ApiTokens.Values | Where-Object { $_.TokenHash -eq $tokenHash } | Select-Object -First 1

    if (-not $matchingToken) {
        return @{
            Valid = $false
            Reason = 'Invalid token'
        }
    }

    if (-not $matchingToken.Enabled) {
        return @{
            Valid = $false
            Reason = 'Token is disabled'
        }
    }

    if ([datetime]::UtcNow -gt $matchingToken.ExpiresAt) {
        return @{
            Valid = $false
            Reason = 'Token has expired'
        }
    }

    if ($matchingToken.AllowedIPs -and $matchingToken.AllowedIPs.Count -gt 0) {
        if ($ClientIP -and $ClientIP -notin $matchingToken.AllowedIPs) {
            return @{
                Valid = $false
                Reason = 'IP address not allowed'
            }
        }
    }

    if ($RequiredPermission) {
        if ($matchingToken.Permissions -notcontains $RequiredPermission -and $matchingToken.Permissions -notcontains 'Admin.Full') {
            return @{
                Valid = $false
                Reason = "Missing permission: $RequiredPermission"
            }
        }
    }

    # Update usage stats
    $matchingToken.LastUsed = [datetime]::UtcNow
    $matchingToken.UseCount++

    return @{
        Valid = $true
        TokenId = $matchingToken.Id
        Name = $matchingToken.Name
        Role = $matchingToken.Role
        Permissions = $matchingToken.Permissions
    }
}

function Get-ApiTokens {
    [CmdletBinding()]
    param(
        [switch]$IncludeExpired
    )

    Assert-Permission -Permission 'Admin.Full' -Operation 'List API tokens'

    $tokens = $script:ApiTokens.Values

    if (-not $IncludeExpired) {
        $tokens = $tokens | Where-Object { $_.ExpiresAt -gt [datetime]::UtcNow }
    }

    return $tokens | ForEach-Object {
        [PSCustomObject]@{
            Id = $_.Id
            Name = $_.Name
            Role = $_.Role
            CreatedAt = $_.CreatedAt
            ExpiresAt = $_.ExpiresAt
            LastUsed = $_.LastUsed
            UseCount = $_.UseCount
            Enabled = $_.Enabled
            CreatedBy = $_.CreatedBy
        }
    }
}

function Revoke-ApiToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TokenId
    )

    Assert-Permission -Permission 'Admin.Full' -Operation 'Revoke API token'

    if ($script:ApiTokens.ContainsKey($TokenId)) {
        $tokenName = $script:ApiTokens[$TokenId].Name
        $script:ApiTokens.Remove($TokenId)

        Write-AuditLog -Action 'ApiToken.Revoke' -Details "Revoked API token: $tokenName" -TargetResource 'ApiToken' -TargetId $TokenId -Severity 'Warning'

        return @{ Success = $true; Message = "Token revoked: $tokenName" }
    }

    throw "Token not found: $TokenId"
}
#endregion

#region Protected Operations Wrapper
function Invoke-ProtectedOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Permission,

        [Parameter(Mandatory)]
        [scriptblock]$Operation,

        [string]$OperationName,

        [string]$TargetResource,

        [string]$TargetId,

        [switch]$AuditOnSuccess
    )

    $opName = if ($OperationName) { $OperationName } else { $Permission }

    Assert-Permission -Permission $Permission -Operation $opName

    try {
        $result = & $Operation

        if ($AuditOnSuccess) {
            Write-AuditLog -Action $opName -Details "Operation completed successfully" -TargetResource $TargetResource -TargetId $TargetId
        }

        return $result
    } catch {
        Write-AuditLog -Action $opName -Details "Operation failed: $($_.Exception.Message)" -TargetResource $TargetResource -TargetId $TargetId -Severity 'Error'
        throw
    }
}
#endregion

#region Exports
Export-ModuleMember -Function @(
    'Get-RoleDefinitions',
    'Get-RolePermissions',
    'New-CustomRole',
    'Initialize-UserSession',
    'Get-CurrentUser',
    'Get-CurrentSession',
    'Close-UserSession',
    'Test-Permission',
    'Assert-Permission',
    'Test-RoleLevel',
    'Get-EffectivePermissions',
    'Test-CanAccessFeature',
    'Initialize-AuditLog',
    'Write-AuditLog',
    'Get-AuditLog',
    'Clear-AuditLog',
    'Get-UIPermissionState',
    'Get-MenuVisibility',
    'Get-ADGroupMembership',
    'Initialize-ADAuthentication',
    'New-ApiToken',
    'Test-ApiToken',
    'Get-ApiTokens',
    'Revoke-ApiToken',
    'Invoke-ProtectedOperation'
)
#endregion
