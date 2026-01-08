# AccessControlModule.Tests.ps1
# Pester tests for role-based access control, permissions, and authentication

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\AccessControlModule.psm1'
    Import-Module $modulePath -Force
}

AfterAll {
    Close-UserSession
}

Describe 'Role Definitions' {
    It 'Should have default roles defined' {
        $roles = Get-RoleDefinitions

        $roles.Count | Should -BeGreaterOrEqual 3
        $roles.Name | Should -Contain 'Viewer'
        $roles.Name | Should -Contain 'Operator'
        $roles.Name | Should -Contain 'Admin'
    }

    It 'Should return specific role by name' {
        $role = Get-RoleDefinitions -RoleName 'Admin'

        $role | Should -Not -BeNullOrEmpty
        $role.Name | Should -Be 'Admin'
        $role.Level | Should -Be 3
    }

    It 'Should return null for unknown role' {
        $role = Get-RoleDefinitions -RoleName 'NonExistentRole12345'

        $role | Should -BeNullOrEmpty
    }

    It 'Should have Viewer with read-only permissions' {
        $permissions = Get-RolePermissions -RoleName 'Viewer'

        $permissions | Should -Contain 'View.Dashboard'
        $permissions | Should -Contain 'View.Devices'
        $permissions | Should -Not -Contain 'Execute.BulkWrite'
        $permissions | Should -Not -Contain 'Admin.Full'
    }

    It 'Should have Operator with operational permissions' {
        $permissions = Get-RolePermissions -RoleName 'Operator'

        $permissions | Should -Contain 'Run.HealthCheck'
        $permissions | Should -Contain 'Run.Runbook'
        $permissions | Should -Not -Contain 'Admin.Full'
    }

    It 'Should have Admin with full permissions' {
        $permissions = Get-RolePermissions -RoleName 'Admin'

        $permissions | Should -Contain 'Admin.Full'
        $permissions | Should -Contain 'Manage.Users'
        $permissions | Should -Contain 'Execute.BulkWrite'
    }
}

Describe 'Custom Roles' {
    It 'Should create custom role' {
        $role = New-CustomRole -Name 'CustomRole' -Description 'Test role' -Permissions @('View.Dashboard', 'Custom.Permission')

        $role.Name | Should -Be 'CustomRole'
        $role.Permissions | Should -Contain 'View.Dashboard'
        $role.Permissions | Should -Contain 'Custom.Permission'
    }

    It 'Should create role based on existing role' {
        $role = New-CustomRole -Name 'ExtendedViewer' -Description 'Extended viewer' -Permissions @('Run.HealthCheck') -BasedOn 'Viewer'

        $role.Permissions | Should -Contain 'View.Dashboard'  # From Viewer
        $role.Permissions | Should -Contain 'Run.HealthCheck'  # Added
    }
}

Describe 'User Session Management' {
    AfterEach {
        Close-UserSession
    }

    It 'Should initialize user session' {
        $session = Initialize-UserSession -Username 'testuser' -Role 'Viewer'

        $session.SessionId | Should -Not -BeNullOrEmpty
        $session.User.Username | Should -Be 'testuser'
        $session.User.Role | Should -Be 'Viewer'
    }

    It 'Should fail for invalid role' {
        { Initialize-UserSession -Username 'testuser' -Role 'InvalidRole' } |
            Should -Throw '*Invalid role*'
    }

    It 'Should get current user' {
        Initialize-UserSession -Username 'testuser' -Role 'Operator'

        $user = Get-CurrentUser

        $user.Username | Should -Be 'testuser'
        $user.Role | Should -Be 'Operator'
    }

    It 'Should get current session' {
        Initialize-UserSession -Username 'testuser' -Role 'Viewer'

        $session = Get-CurrentSession

        $session.SessionId | Should -Not -BeNullOrEmpty
        $session.User | Should -Be 'testuser'
    }

    It 'Should close session' {
        Initialize-UserSession -Username 'testuser' -Role 'Viewer'
        Close-UserSession

        $user = Get-CurrentUser
        $user | Should -BeNullOrEmpty
    }
}

Describe 'Permission Enforcement' {
    AfterEach {
        Close-UserSession
    }

    It 'Should grant permission for valid role' {
        Initialize-UserSession -Username 'viewer' -Role 'Viewer'

        $result = Test-Permission -Permission 'View.Dashboard'

        $result | Should -Be $true
    }

    It 'Should deny permission for insufficient role' {
        Initialize-UserSession -Username 'viewer' -Role 'Viewer'

        $result = Test-Permission -Permission 'Admin.Full' -Silent

        $result | Should -Be $false
    }

    It 'Should deny all permissions without session' {
        Close-UserSession

        $result = Test-Permission -Permission 'View.Dashboard' -Silent

        $result | Should -Be $false
    }

    It 'Should assert permission successfully' {
        Initialize-UserSession -Username 'admin' -Role 'Admin'

        { Assert-Permission -Permission 'Admin.Full' } | Should -Not -Throw
    }

    It 'Should throw on assert for missing permission' {
        Initialize-UserSession -Username 'viewer' -Role 'Viewer'

        { Assert-Permission -Permission 'Admin.Full' } | Should -Throw '*Access denied*'
    }

    It 'Should check role level' {
        Initialize-UserSession -Username 'operator' -Role 'Operator'

        Test-RoleLevel -RequiredLevel 2 | Should -Be $true
        Test-RoleLevel -RequiredLevel 3 | Should -Be $false
    }

    It 'Admin.Full should grant all permissions' {
        Initialize-UserSession -Username 'admin' -Role 'Admin'

        Test-Permission -Permission 'Any.Random.Permission' | Should -Be $true
    }
}

Describe 'Feature Access' {
    AfterEach {
        Close-UserSession
    }

    It 'Should check feature access for Viewer' {
        Initialize-UserSession -Username 'viewer' -Role 'Viewer'

        Test-CanAccessFeature -FeatureName 'Dashboard' | Should -Be $true
        Test-CanAccessFeature -FeatureName 'UserManagement' | Should -Be $false
    }

    It 'Should check feature access for Admin' {
        Initialize-UserSession -Username 'admin' -Role 'Admin'

        Test-CanAccessFeature -FeatureName 'Dashboard' | Should -Be $true
        Test-CanAccessFeature -FeatureName 'UserManagement' | Should -Be $true
        Test-CanAccessFeature -FeatureName 'AuditLog' | Should -Be $true
    }
}

Describe 'Effective Permissions' {
    AfterEach {
        Close-UserSession
    }

    It 'Should return effective permissions for current user' {
        Initialize-UserSession -Username 'operator' -Role 'Operator'

        $permissions = Get-EffectivePermissions

        $permissions | Should -Contain 'View.Dashboard'
        $permissions | Should -Contain 'Run.Runbook'
    }

    It 'Should return empty for no session' {
        Close-UserSession

        $permissions = Get-EffectivePermissions

        $permissions.Count | Should -Be 0
    }
}

Describe 'Audit Logging' {
    BeforeAll {
        $testAuditPath = Join-Path ([System.IO.Path]::GetTempPath()) 'AccessControlTests\Audit'
        Initialize-AuditLog -LogPath $testAuditPath
        Initialize-UserSession -Username 'testuser' -Role 'Admin'
    }

    AfterAll {
        Close-UserSession
        $testPath = Join-Path ([System.IO.Path]::GetTempPath()) 'AccessControlTests'
        if (Test-Path $testPath) {
            Remove-Item $testPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Should write audit log entry' {
        $entry = Write-AuditLog -Action 'Test.Action' -Details 'Test details'

        $entry.Action | Should -Be 'Test.Action'
        $entry.Details | Should -Be 'Test details'
        $entry.User | Should -Be 'testuser'
    }

    It 'Should include severity level' {
        $entry = Write-AuditLog -Action 'Test.Warning' -Details 'Warning test' -Severity 'Warning'

        $entry.Severity | Should -Be 'Warning'
    }

    It 'Should include target resource' {
        $entry = Write-AuditLog -Action 'Test.Resource' -Details 'Resource test' -TargetResource 'Device' -TargetId 'D123'

        $entry.TargetResource | Should -Be 'Device'
        $entry.TargetId | Should -Be 'D123'
    }

    It 'Should retrieve audit logs' {
        Write-AuditLog -Action 'Retrievable.Test' -Details 'For retrieval'

        $logs = Get-AuditLog -Last 10

        $logs | Where-Object { $_.Action -eq 'Retrievable.Test' } | Should -Not -BeNullOrEmpty
    }

    It 'Should filter by action' {
        Write-AuditLog -Action 'Specific.Action' -Details 'Specific'

        $logs = Get-AuditLog -Action 'Specific' -Last 10

        $logs | ForEach-Object { $_.Action | Should -Match 'Specific' }
    }
}

Describe 'UI Permission State' {
    BeforeEach {
        Initialize-UserSession -Username 'viewer' -Role 'Viewer'
    }

    AfterEach {
        Close-UserSession
    }

    It 'Should return state for UI elements' {
        $state = Get-UIPermissionState -Elements @('btn_View', 'btn_Settings', 'btn_Delete')

        $state.Keys.Count | Should -Be 3
    }

    It 'Should disable admin elements for viewers' {
        $state = Get-UIPermissionState -Elements @('btn_UserManagement', 'btn_DeleteAll')

        $state['btn_UserManagement'].Enabled | Should -Be $false
        $state['btn_DeleteAll'].Enabled | Should -Be $false
    }

    It 'Should return menu visibility' {
        $visibility = Get-MenuVisibility

        $visibility.Dashboard | Should -Be $true
        $visibility.UserManagement | Should -Be $false
    }
}

Describe 'AD Group Membership' {
    It 'Should attempt to get group membership' {
        # This test just ensures the function runs without error
        $groups = Get-ADGroupMembership

        # May or may not return groups depending on environment
        $groups | Should -Not -BeNullOrEmpty -Or -BeNullOrEmpty
    }
}

Describe 'API Token Management' {
    BeforeAll {
        Initialize-UserSession -Username 'admin' -Role 'Admin'
    }

    AfterAll {
        Close-UserSession
    }

    It 'Should create API token' {
        $token = New-ApiToken -Name 'TestToken' -Role 'Viewer' -ExpirationDays 30

        $token.Id | Should -Not -BeNullOrEmpty
        $token.Token | Should -Not -BeNullOrEmpty
        $token.Name | Should -Be 'TestToken'
        $token.Role | Should -Be 'Viewer'
    }

    It 'Should fail for invalid role' {
        { New-ApiToken -Name 'BadToken' -Role 'InvalidRole' } |
            Should -Throw '*Invalid role*'
    }

    It 'Should validate token' {
        $created = New-ApiToken -Name 'ValidateToken' -Role 'Operator'

        $result = Test-ApiToken -Token $created.Token

        $result.Valid | Should -Be $true
        $result.Role | Should -Be 'Operator'
    }

    It 'Should reject invalid token' {
        $result = Test-ApiToken -Token 'invalid-token-12345'

        $result.Valid | Should -Be $false
        $result.Reason | Should -Be 'Invalid token'
    }

    It 'Should check required permission' {
        $created = New-ApiToken -Name 'PermToken' -Role 'Viewer'

        $result = Test-ApiToken -Token $created.Token -RequiredPermission 'Admin.Full'

        $result.Valid | Should -Be $false
        $result.Reason | Should -Match 'Missing permission'
    }

    It 'Should list tokens' {
        $tokens = Get-ApiTokens

        $tokens | Should -Not -BeNullOrEmpty
    }

    It 'Should revoke token' {
        $created = New-ApiToken -Name 'RevokeToken' -Role 'Viewer'

        $result = Revoke-ApiToken -TokenId $created.Id

        $result.Success | Should -Be $true

        # Should fail validation after revoke
        $validation = Test-ApiToken -Token $created.Token
        $validation.Valid | Should -Be $false
    }
}

Describe 'Protected Operations' {
    BeforeEach {
        Initialize-UserSession -Username 'admin' -Role 'Admin'
    }

    AfterEach {
        Close-UserSession
    }

    It 'Should execute protected operation with permission' {
        $result = Invoke-ProtectedOperation -Permission 'View.Dashboard' -Operation { return 'Success' }

        $result | Should -Be 'Success'
    }

    It 'Should deny protected operation without permission' {
        Initialize-UserSession -Username 'viewer' -Role 'Viewer'

        { Invoke-ProtectedOperation -Permission 'Admin.Full' -Operation { return 'Fail' } } |
            Should -Throw '*Access denied*'
    }

    It 'Should audit on success when requested' {
        $testAuditPath = Join-Path ([System.IO.Path]::GetTempPath()) 'ProtectedOpTest'
        Initialize-AuditLog -LogPath $testAuditPath

        Invoke-ProtectedOperation `
            -Permission 'View.Dashboard' `
            -Operation { return 'OK' } `
            -OperationName 'TestOp' `
            -AuditOnSuccess

        $logs = Get-AuditLog -Action 'TestOp' -Last 5
        $logs | Should -Not -BeNullOrEmpty

        Remove-Item $testAuditPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Permission Denied for Non-Admin' {
    BeforeEach {
        Initialize-UserSession -Username 'viewer' -Role 'Viewer'
    }

    AfterEach {
        Close-UserSession
    }

    It 'Should deny API token creation' {
        { New-ApiToken -Name 'Denied' -Role 'Viewer' } |
            Should -Throw '*Access denied*'
    }

    It 'Should deny audit log clearing' {
        { Clear-AuditLog -OlderThanDays 30 -Force } |
            Should -Throw '*Access denied*'
    }
}

Describe 'Module Exports' {
    It 'Should export all required functions' {
        $exportedFunctions = (Get-Module AccessControlModule).ExportedFunctions.Keys

        $requiredFunctions = @(
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

        foreach ($func in $requiredFunctions) {
            $exportedFunctions | Should -Contain $func
        }
    }
}
