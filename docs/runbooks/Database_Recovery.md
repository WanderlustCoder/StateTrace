# Database Recovery Runbook

## Overview

This runbook provides step-by-step procedures for recovering StateTrace Access databases from corruption, data loss, or other failures.

## Prerequisites

- PowerShell 5.1+
- Microsoft Access Database Engine (ACE OLEDB 12.0)
- Administrative access to StateTrace data directories
- Familiarity with StateTrace module structure

## Quick Reference

| Scenario | Primary Procedure | Recovery Time |
|----------|-------------------|---------------|
| Minor corruption | Compact/Repair | 5-15 minutes |
| Major corruption | Restore from backup | 10-30 minutes |
| Data integrity issues | Integrity check + selective restore | 30-60 minutes |
| Complete database loss | Full restore from backup | 15-45 minutes |

---

## Procedure 1: Database Health Check

**When to use:** Before any maintenance, after crashes, or when queries are slow.

### Steps

```powershell
# Import the module
Import-Module .\Modules\DatabaseConcurrencyModule.psm1

# Check database health
$health = Test-DatabaseHealth -DatabasePath ".\Data\WLLS\WLLS.accdb"

# Review results
$health | Format-List

# Check specific tables
if ($health.Healthy) {
    Write-Host "Database is healthy" -ForegroundColor Green
} else {
    Write-Host "Database has issues:" -ForegroundColor Red
    $health.Errors | ForEach-Object { Write-Host "  - $_" }
}
```

### Expected Output

```
DatabasePath  : .\Data\WLLS\WLLS.accdb
Exists        : True
Healthy       : True
FileSize      : 52428800
CanConnect    : True
TableCount    : 15
Tables        : {...}
```

### Escalation

- If `CanConnect` is False: Proceed to Procedure 2 (Compact/Repair)
- If tables show query errors: Proceed to Procedure 4 (Integrity Verification)

---

## Procedure 2: Compact and Repair

**When to use:** Database is slow, showing minor corruption, or needs maintenance.

### Steps

```powershell
# Import the module
Import-Module .\Modules\DatabaseConcurrencyModule.psm1

# Repair with automatic backup
$result = Repair-AccessDatabase -DatabasePath ".\Data\WLLS\WLLS.accdb" -BackupFirst

# Check result
if ($result.RepairSuccessful) {
    Write-Host "Repair successful!" -ForegroundColor Green
    Write-Host "Size reduced by $($result.SizeReductionPercent)%"
    Write-Host "Backup saved to: $($result.BackupPath)"
} else {
    Write-Host "Repair failed:" -ForegroundColor Red
    $result.Errors | ForEach-Object { Write-Host "  - $_" }
}
```

### Important Notes

- **ALWAYS** use `-BackupFirst` (default is true)
- Repair requires exclusive access - ensure no other processes are using the database
- If repair fails, the original is automatically restored from backup

### Troubleshooting

| Error | Cause | Solution |
|-------|-------|----------|
| "Database is locked" | Another process has the file open | Close StateTrace UI, stop scheduled tasks |
| "JRO.JetEngine failed" | ACE provider not installed | Install Access Database Engine |
| "Backup failed" | Disk full or permissions | Check disk space, run as admin |

---

## Procedure 3: Restore from Backup

**When to use:** Database is severely corrupted or needs to be rolled back.

### Steps

```powershell
# List available backups
$backups = Get-DatabaseBackups -DatabaseName "WLLS"
$backups | Format-Table Name, SizeMB, Created, Age

# Select a backup to restore
$selectedBackup = $backups | Where-Object { $_.Age -lt 1 } | Select-Object -First 1

# Restore (this will overwrite the current database)
$result = Restore-DatabaseBackup `
    -BackupPath $selectedBackup.Path `
    -TargetPath ".\Data\WLLS\WLLS.accdb" `
    -Force

if ($result.Success) {
    Write-Host "Restore completed successfully" -ForegroundColor Green
} else {
    Write-Host "Restore failed: $($result.Error)" -ForegroundColor Red
}
```

### Backup Selection Guidelines

| Situation | Backup Selection |
|-----------|------------------|
| Corruption detected today | Use yesterday's backup |
| Data looks wrong | Use backup from before issue started |
| Unknown issue | Use most recent backup, verify data |

### Post-Restore Verification

```powershell
# Verify restored database
$health = Test-DatabaseHealth -DatabasePath ".\Data\WLLS\WLLS.accdb"

# Run integrity check
$integrity = Test-DatabaseIntegrity -DatabasePath ".\Data\WLLS\WLLS.accdb" -IncludeRowCounts

Write-Host "Integrity Status: $($integrity.OverallStatus)"
Write-Host "Passed: $($integrity.PassedChecks)/$($integrity.TotalChecks) checks"
```

---

## Procedure 4: Integrity Verification

**When to use:** Suspecting data corruption or after recovery.

### Steps

```powershell
# Full integrity check with row counts
$integrity = Test-DatabaseIntegrity `
    -DatabasePath ".\Data\WLLS\WLLS.accdb" `
    -IncludeRowCounts

# Review results
Write-Host "Overall Status: $($integrity.OverallStatus)"
Write-Host ""

foreach ($check in $integrity.Checks) {
    $color = switch ($check.Status) {
        'Pass' { 'Green' }
        'Warning' { 'Yellow' }
        'Fail' { 'Red' }
        default { 'Gray' }
    }
    Write-Host "[$($check.Status)] $($check.Name): $($check.Details)" -ForegroundColor $color
}
```

### Handling Failed Checks

| Failed Check | Recovery Action |
|--------------|-----------------|
| FileAccess | Check file permissions, disk health |
| Connection | Run Compact/Repair (Procedure 2) |
| Schema | Restore from backup (Procedure 3) |
| Table_* | May need selective data recovery |
| Indexes | Run Compact/Repair to rebuild |

---

## Procedure 5: Manual Backup

**When to use:** Before major changes, migrations, or scheduled maintenance.

### Steps

```powershell
# Create manual backup
$backup = New-DatabaseBackup `
    -DatabasePath ".\Data\WLLS\WLLS.accdb" `
    -RetentionDays 90

if ($backup.Success) {
    Write-Host "Backup created: $($backup.BackupPath)" -ForegroundColor Green
    Write-Host "Size: $([math]::Round($backup.Size / 1MB, 2)) MB"
    Write-Host "Old backups cleaned: $($backup.CleanedUp)"
} else {
    Write-Host "Backup failed: $($backup.Error)" -ForegroundColor Red
}
```

### Backup Best Practices

1. **Before upgrades:** Always backup before StateTrace updates
2. **Before bulk imports:** Backup before large data ingestion
3. **Weekly verification:** Test restore from backup monthly
4. **Off-site copies:** Copy critical backups to network share

---

## Procedure 6: Concurrent Access Issues

**When to use:** Lock timeouts, database busy errors, or multi-user conflicts.

### Diagnosing Lock Issues

```powershell
# Start lock monitoring
Start-LockMonitoring

# After some operations, check metrics
$metrics = Get-LockMetrics
$metrics | Format-List

# If lock wait rate > 10%, investigate
if ($metrics.LockWaitRate -gt 10) {
    Write-Host "High lock contention detected!" -ForegroundColor Yellow
    
    # Get recent lock events
    $events = Get-LockEvents -Last 20
    $events | Format-Table Timestamp, Database, WaitTimeMs, TimedOut
}
```

### Resolving Lock Contention

1. **Identify conflicting processes:**
   ```powershell
   Get-Process | Where-Object { $_.Modules.ModuleName -match 'ace|jet' }
   ```

2. **Close StateTrace instances:**
   - Close any open StateTrace UI windows
   - Stop scheduled harness tasks
   - Wait 30 seconds for connections to release

3. **Force release (last resort):**
   ```powershell
   # Create .laccdb file backup and delete
   $lockFile = ".\Data\WLLS\WLLS.laccdb"
   if (Test-Path $lockFile) {
       Copy-Item $lockFile "$lockFile.bak"
       Remove-Item $lockFile -Force
   }
   ```

---

## Procedure 7: Stress Testing

**When to use:** After recovery, before production, or capacity planning.

### Running Concurrent Write Test

```powershell
# Run stress test
$test = Test-ConcurrentWrites `
    -DatabasePath ".\Data\WLLS\WLLS.accdb" `
    -ThreadCount 4 `
    -OperationsPerThread 100

# Review results
Write-Host "Test ID: $($test.TestId)"
Write-Host "Duration: $($test.DurationMs) ms"
Write-Host "Success Rate: $($test.SuccessRate)%"
Write-Host "Operations/Second: $($test.OperationsPerSecond)"
Write-Host "Lock Timeouts: $($test.LockTimeouts)"
Write-Host "Corruption Detected: $($test.CorruptionDetected)"
```

### Acceptable Thresholds

| Metric | Acceptable | Warning | Critical |
|--------|------------|---------|----------|
| Success Rate | > 99% | 95-99% | < 95% |
| Lock Timeouts | < 5 | 5-20 | > 20 |
| Corruption | None | - | Any |

---

## Emergency Contacts

| Role | Contact | Escalation Time |
|------|---------|-----------------|
| Primary DBA | [DBA Name] | Immediate |
| Backup Administrator | [Backup Admin] | 15 minutes |
| Network Team | [Network Team] | 30 minutes |

---

## Appendix A: Common Error Messages

| Error Message | Meaning | Solution |
|---------------|---------|----------|
| "Unrecognized database format" | Severe corruption or wrong file | Restore from backup |
| "Could not use '...'; file already in use" | Lock conflict | Close other processes |
| "Disk or network error" | I/O failure | Check disk health |
| "Table 'X' doesn't exist" | Schema corruption | Restore from backup |
| "Record is deleted" | Data corruption | Compact/Repair or restore |

---

## Appendix B: Automation Scripts

### Daily Health Check Script

```powershell
# Save as: Tools/Invoke-DailyHealthCheck.ps1

$databases = @(
    ".\Data\WLLS\WLLS.accdb",
    ".\Data\BOYO\BOYO.accdb"
)

$results = foreach ($db in $databases) {
    if (Test-Path $db) {
        Test-DatabaseHealth -DatabasePath $db
    }
}

$unhealthy = $results | Where-Object { -not $_.Healthy }

if ($unhealthy) {
    Write-Host "ALERT: Unhealthy databases detected!" -ForegroundColor Red
    $unhealthy | Format-Table DatabasePath, Errors
    # Add alerting/notification here
}
```

### Weekly Backup Verification

```powershell
# Save as: Tools/Test-BackupIntegrity.ps1

$backups = Get-DatabaseBackups | Where-Object { $_.Age -lt 7 }

foreach ($backup in $backups) {
    Write-Host "Testing: $($backup.Name)"
    
    $tempPath = [System.IO.Path]::GetTempFileName() + ".accdb"
    Copy-Item $backup.Path $tempPath
    
    $integrity = Test-DatabaseIntegrity -DatabasePath $tempPath
    
    if ($integrity.OverallStatus -eq 'Pass') {
        Write-Host "  PASS" -ForegroundColor Green
    } else {
        Write-Host "  FAIL - Backup may be corrupted!" -ForegroundColor Red
    }
    
    Remove-Item $tempPath -Force
}
```

---

*Last Updated: $(Get-Date -Format 'yyyy-MM-dd')*
*Document Owner: StateTrace Operations Team*
