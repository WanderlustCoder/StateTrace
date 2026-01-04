# Identity & RBAC Rollout Playbook

<!-- LANDMARK: ST-F-004 RBAC playbook -->

This playbook translates the recommendations from `docs/StateTrace_Acknowledgement_Identity_Options.md` into runnable steps for dev seat bootstrap and RBAC verification.

## Overview

StateTrace uses a phased identity approach:
- **Phase 1 (Current):** AD-integrated accounts for domain-joined environments; local operator fallback for air-gapped sites
- **Phase 2 (Future):** Azure AD device-code auth when online mode is approved

## Prerequisites

- PowerShell 5.1+ with execution policy allowing local scripts
- Domain-joined workstation (for AD path) or local admin access (for fallback)
- Access to StateTrace repository and `Data/StateTraceSettings.json`

## Dev Seat Bootstrap

### Step 1: Validate Environment

```powershell
# Run the bootstrap validation
pwsh Tools/Bootstrap-DevSeat.ps1 -ValidateOnly

# Expected output includes:
# - Execution policy check (RemoteSigned/Unrestricted/Bypass required)
# - Pester module check (>= 3.4.0)
# - CISmoke fixtures check
```

### Step 2: Configure Identity Mode

Edit `Data/StateTraceSettings.json` to set the identity provider:

```json
{
    "IdentityProvider": "AD",
    "IdentityFallbackAllowed": false,
    "AuditRetentionDays": 90
}
```

| Setting | Values | Description |
|---------|--------|-------------|
| `IdentityProvider` | `AD`, `Local`, `None` | Primary identity source |
| `IdentityFallbackAllowed` | `true`, `false` | Allow local fallback when AD unavailable |
| `AuditRetentionDays` | Integer | Audit log retention period |

### Step 3: Verify AD Integration (Domain-Joined)

```powershell
# Check domain membership
(Get-WmiObject Win32_ComputerSystem).PartOfDomain

# Verify current user context
[System.Security.Principal.WindowsIdentity]::GetCurrent().Name

# Test directory services access
$searcher = [System.DirectoryServices.DirectorySearcher]::new()
$searcher.Filter = "(sAMAccountName=$env:USERNAME)"
$result = $searcher.FindOne()
if ($result) { Write-Host "AD lookup successful: $($result.Properties['distinguishedname'])" }
```

### Step 4: Configure Local Fallback (Air-Gapped Only)

For non-domain installations:

```powershell
# Generate local operator credentials (run once per operator)
# Note: This is a placeholder for future implementation
# Actual implementation requires PBKDF2 hashing module

$localOperator = @{
    Username = "operator01"
    PasswordPolicy = @{
        MinLength = 12
        RequireComplexity = $true
        MaxAgeDays = 90
    }
}

# Store in StateTraceSettings.json under LocalOperators key
# Ensure proper hashing before production use
```

## RBAC Switch Verification

### Step 1: Check Current RBAC Settings

```powershell
# Read current settings
$settings = Get-Content -Raw 'Data/StateTraceSettings.json' | ConvertFrom-Json

Write-Host "Identity Provider: $($settings.IdentityProvider)"
Write-Host "Fallback Allowed: $($settings.IdentityFallbackAllowed)"
Write-Host "Audit Retention: $($settings.AuditRetentionDays) days"
```

### Step 2: Validate RBAC Configuration

```powershell
# Verify identity provider is set
if (-not $settings.IdentityProvider -or $settings.IdentityProvider -eq 'None') {
    Write-Warning "No identity provider configured - acknowledgements will not be audited"
}

# Check for fallback in domain environment
if ((Get-WmiObject Win32_ComputerSystem).PartOfDomain -and $settings.IdentityFallbackAllowed) {
    Write-Warning "Fallback is enabled on a domain-joined machine - review security policy"
}

# Verify audit retention meets compliance (minimum 30 days recommended)
if ($settings.AuditRetentionDays -lt 30) {
    Write-Warning "Audit retention below 30 days may not meet compliance requirements"
}
```

### Step 3: Test Acknowledgement Flow (Dry Run)

```powershell
# Simulate acknowledgement capture (no actual write)
$acknowledgement = @{
    Timestamp = Get-Date -Format 'o'
    Operator = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    IdentityProvider = $settings.IdentityProvider
    Action = 'TestAcknowledgement'
    TargetHost = 'TEST-HOST-01'
}

# Validate structure
$acknowledgement | ConvertTo-Json -Depth 2

# Expected: JSON with operator identity captured from current Windows context
```

## Verification Checklist

| Check | Command | Expected |
|-------|---------|----------|
| Domain membership | `(Get-WmiObject Win32_ComputerSystem).PartOfDomain` | `True` for AD path |
| Identity provider set | `$settings.IdentityProvider` | `AD` or `Local` |
| Audit retention | `$settings.AuditRetentionDays` | >= 30 days |
| Fallback policy | `$settings.IdentityFallbackAllowed` | `False` for domain |
| Current user resolvable | `[System.Security.Principal.WindowsIdentity]::GetCurrent().Name` | `DOMAIN\username` |

## Security Considerations

1. **Local Fallback Risks:**
   - Only enable for genuinely air-gapped environments
   - Require strong passwords (12+ chars, complexity)
   - Rotate credentials every 90 days maximum
   - Log all fallback authentications for review

2. **Audit Trail Requirements:**
   - All acknowledgements must capture operator identity
   - Timestamps should be UTC with timezone offset
   - Retain logs per `AuditRetentionDays` policy
   - Export audit extracts before cleanup

3. **Session Verification:**
   - Record identity mode in session logs
   - Note any fallback usage in task board entries
   - Reference this playbook when identity changes land

## Telemetry Integration

When identity changes ship, verify telemetry captures:

```powershell
# Check for IdentityResolution events in telemetry
$telemetry = Get-Content Logs/IngestionMetrics/*.json | ForEach-Object {
    try { $_ | ConvertFrom-Json } catch { }
} | Where-Object { $_.EventType -eq 'IdentityResolution' }

$telemetry | Group-Object -Property IdentityProvider | Format-Table Name, Count
```

## References

- Identity options analysis: `docs/StateTrace_Acknowledgement_Identity_Options.md`
- Security policy: `docs/Security.md`
- Plan F (owner): `docs/plans/PlanF_SecurityIdentity.md`
- Dev seat bootstrap: `Tools/Bootstrap-DevSeat.ps1`
- Session checklist: `docs/CODEX_SESSION_CHECKLIST.md`
