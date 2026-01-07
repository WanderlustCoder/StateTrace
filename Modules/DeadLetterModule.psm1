# DeadLetterModule.psm1
# Provides dead-letter queue functionality for failed parse operations.
# Failed records are stored in Data/<site>/DeadLetter/ with retry mechanism.

Set-StrictMode -Version Latest

# Configuration
$script:DeadLetterMaxRetries = 3
$script:DeadLetterRetryDelayMs = 1000
$script:DeadLetterRetentionDays = 30

if (-not (Get-Variable -Scope Script -Name DeadLetterStats -ErrorAction SilentlyContinue)) {
    $script:DeadLetterStats = @{
        TotalQueued = 0
        TotalRetried = 0
        TotalRecovered = 0
        TotalExpired = 0
    }
}

function Get-DeadLetterPath {
    <#
    .SYNOPSIS
    Gets the dead-letter directory path for a site.
    .PARAMETER Site
    The site code.
    .PARAMETER DataDirectoryPath
    Optional base data directory. Defaults to Data/.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Site,
        [string]$DataDirectoryPath
    )

    $dataDir = $DataDirectoryPath
    if ([string]::IsNullOrWhiteSpace($dataDir)) {
        try {
            $dataDir = DeviceRepository.Access\Get-DataDirectoryPath
        } catch {
            $dataDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'Data'
        }
    }

    $siteCode = ('' + $Site).Trim()
    if ([string]::IsNullOrWhiteSpace($siteCode)) { $siteCode = 'Unknown' }

    # Extract prefix for site directory
    $prefix = $siteCode
    $dashIndex = $prefix.IndexOf('-')
    if ($dashIndex -gt 0) { $prefix = $prefix.Substring(0, $dashIndex) }

    $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
    foreach ($ch in $invalidChars) {
        $prefix = $prefix.Replace([string]$ch, '_')
    }
    if ([string]::IsNullOrWhiteSpace($prefix)) { $prefix = 'Unknown' }

    $siteDir = Join-Path $dataDir $prefix
    $deadLetterDir = Join-Path $siteDir 'DeadLetter'

    return $deadLetterDir
}

function New-DeadLetterRecord {
    <#
    .SYNOPSIS
    Creates a dead-letter record structure.
    .PARAMETER Site
    The site code where the failure occurred.
    .PARAMETER SourceFile
    The source file that failed to parse.
    .PARAMETER RecordType
    The type of record (Interface, Span, Host, etc.).
    .PARAMETER RawData
    The raw data that failed to parse.
    .PARAMETER ErrorMessage
    The error message from the failed operation.
    .PARAMETER ErrorDetails
    Additional error details or stack trace.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Site,
        [string]$SourceFile,
        [Parameter(Mandatory)][string]$RecordType,
        [object]$RawData,
        [Parameter(Mandatory)][string]$ErrorMessage,
        [string]$ErrorDetails
    )

    $record = [ordered]@{
        Id = [guid]::NewGuid().ToString('N')
        Site = $Site
        SourceFile = $SourceFile
        RecordType = $RecordType
        RawData = $RawData
        ErrorMessage = $ErrorMessage
        ErrorDetails = $ErrorDetails
        CreatedAt = [datetime]::UtcNow.ToString('o')
        RetryCount = 0
        LastRetryAt = $null
        Status = 'Pending'
        RecoveredAt = $null
    }

    return [pscustomobject]$record
}

function Add-DeadLetterRecord {
    <#
    .SYNOPSIS
    Adds a failed record to the dead-letter queue.
    .PARAMETER Record
    The dead-letter record to add.
    .PARAMETER DataDirectoryPath
    Optional base data directory.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject]$Record,
        [string]$DataDirectoryPath
    )

    $site = $Record.Site
    if ([string]::IsNullOrWhiteSpace($site)) { $site = 'Unknown' }

    $deadLetterDir = Get-DeadLetterPath -Site $site -DataDirectoryPath $DataDirectoryPath

    # Ensure directory exists
    if (-not (Test-Path -LiteralPath $deadLetterDir)) {
        try {
            New-Item -ItemType Directory -Path $deadLetterDir -Force | Out-Null
        } catch {
            Write-Warning "[DeadLetter] Failed to create directory '$deadLetterDir': $($_.Exception.Message)"
            return $null
        }
    }

    # Generate filename with timestamp and ID
    $timestamp = [datetime]::UtcNow.ToString('yyyyMMdd-HHmmss')
    $fileName = "{0}_{1}_{2}.json" -f $timestamp, $Record.RecordType, $Record.Id.Substring(0, 8)
    $filePath = Join-Path $deadLetterDir $fileName

    try {
        $json = $Record | ConvertTo-Json -Depth 10 -Compress
        [System.IO.File]::WriteAllText($filePath, $json, [System.Text.Encoding]::UTF8)
        $script:DeadLetterStats.TotalQueued++
        return $filePath
    } catch {
        Write-Warning "[DeadLetter] Failed to write record to '$filePath': $($_.Exception.Message)"
        return $null
    }
}

function Write-ToDeadLetter {
    <#
    .SYNOPSIS
    Convenience function to write a failed parse to the dead-letter queue.
    .PARAMETER Site
    The site code.
    .PARAMETER SourceFile
    The source file path.
    .PARAMETER RecordType
    The type of record that failed.
    .PARAMETER RawData
    The raw data that failed to parse.
    .PARAMETER ErrorRecord
    The PowerShell ErrorRecord from the catch block.
    .PARAMETER DataDirectoryPath
    Optional base data directory.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Site,
        [string]$SourceFile,
        [Parameter(Mandatory)][string]$RecordType,
        [object]$RawData,
        [System.Management.Automation.ErrorRecord]$ErrorRecord,
        [string]$DataDirectoryPath
    )

    $errorMsg = 'Unknown error'
    $errorDetails = $null

    if ($ErrorRecord) {
        $errorMsg = $ErrorRecord.Exception.Message
        $errorDetails = $ErrorRecord.ScriptStackTrace
    }

    $record = New-DeadLetterRecord `
        -Site $Site `
        -SourceFile $SourceFile `
        -RecordType $RecordType `
        -RawData $RawData `
        -ErrorMessage $errorMsg `
        -ErrorDetails $errorDetails

    return Add-DeadLetterRecord -Record $record -DataDirectoryPath $DataDirectoryPath
}

function Get-DeadLetterRecords {
    <#
    .SYNOPSIS
    Retrieves dead-letter records for a site.
    .PARAMETER Site
    The site code.
    .PARAMETER Status
    Filter by status (Pending, Retrying, Failed, Recovered).
    .PARAMETER RecordType
    Filter by record type.
    .PARAMETER DataDirectoryPath
    Optional base data directory.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Site,
        [string]$Status,
        [string]$RecordType,
        [string]$DataDirectoryPath
    )

    $deadLetterDir = Get-DeadLetterPath -Site $Site -DataDirectoryPath $DataDirectoryPath

    if (-not (Test-Path -LiteralPath $deadLetterDir)) {
        return @()
    }

    $results = [System.Collections.Generic.List[object]]::new()

    try {
        $files = Get-ChildItem -LiteralPath $deadLetterDir -Filter '*.json' -File -ErrorAction SilentlyContinue
        foreach ($file in $files) {
            try {
                $json = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
                $record = $json | ConvertFrom-Json
                $record | Add-Member -NotePropertyName '_FilePath' -NotePropertyValue $file.FullName -Force

                # Apply filters
                if (-not [string]::IsNullOrWhiteSpace($Status) -and $record.Status -ne $Status) {
                    continue
                }
                if (-not [string]::IsNullOrWhiteSpace($RecordType) -and $record.RecordType -ne $RecordType) {
                    continue
                }

                [void]$results.Add($record)
            } catch {
                Write-Verbose "[DeadLetter] Failed to read '$($file.FullName)': $($_.Exception.Message)"
            }
        }
    } catch {
        Write-Warning "[DeadLetter] Failed to enumerate dead-letter directory: $($_.Exception.Message)"
    }

    return $results.ToArray()
}

function Invoke-DeadLetterRetry {
    <#
    .SYNOPSIS
    Attempts to retry processing dead-letter records.
    .PARAMETER Site
    The site code.
    .PARAMETER RetryHandler
    A scriptblock that accepts a dead-letter record and returns $true on success.
    .PARAMETER MaxRecords
    Maximum number of records to retry per invocation.
    .PARAMETER DataDirectoryPath
    Optional base data directory.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Site,
        [Parameter(Mandatory)][scriptblock]$RetryHandler,
        [int]$MaxRecords = 100,
        [string]$DataDirectoryPath
    )

    $records = Get-DeadLetterRecords -Site $Site -Status 'Pending' -DataDirectoryPath $DataDirectoryPath
    $processed = 0
    $recovered = 0

    foreach ($record in $records) {
        if ($processed -ge $MaxRecords) { break }

        if ($record.RetryCount -ge $script:DeadLetterMaxRetries) {
            # Mark as permanently failed
            $record.Status = 'Failed'
            Update-DeadLetterRecord -Record $record
            $processed++
            continue
        }

        $record.RetryCount++
        $record.LastRetryAt = [datetime]::UtcNow.ToString('o')
        $record.Status = 'Retrying'

        try {
            $success = & $RetryHandler $record
            if ($success) {
                $record.Status = 'Recovered'
                $record.RecoveredAt = [datetime]::UtcNow.ToString('o')
                $script:DeadLetterStats.TotalRecovered++
                $recovered++

                # Move to recovered subfolder
                Move-DeadLetterToRecovered -Record $record -DataDirectoryPath $DataDirectoryPath
            } else {
                $record.Status = 'Pending'
                Update-DeadLetterRecord -Record $record
            }
        } catch {
            $record.Status = 'Pending'
            $record.ErrorMessage = $_.Exception.Message
            Update-DeadLetterRecord -Record $record
        }

        $script:DeadLetterStats.TotalRetried++
        $processed++

        # Small delay between retries
        if ($processed -lt $records.Count) {
            Start-Sleep -Milliseconds $script:DeadLetterRetryDelayMs
        }
    }

    return [pscustomobject]@{
        Processed = $processed
        Recovered = $recovered
        Remaining = ($records.Count - $processed)
    }
}

function Update-DeadLetterRecord {
    <#
    .SYNOPSIS
    Updates a dead-letter record file.
    .PARAMETER Record
    The record to update (must have _FilePath property).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject]$Record
    )

    $filePath = $Record._FilePath
    if ([string]::IsNullOrWhiteSpace($filePath) -or -not (Test-Path -LiteralPath $filePath)) {
        return $false
    }

    try {
        # Remove internal property before saving
        $recordCopy = $Record | Select-Object -Property * -ExcludeProperty '_FilePath'
        $json = $recordCopy | ConvertTo-Json -Depth 10 -Compress
        [System.IO.File]::WriteAllText($filePath, $json, [System.Text.Encoding]::UTF8)
        return $true
    } catch {
        Write-Warning "[DeadLetter] Failed to update record: $($_.Exception.Message)"
        return $false
    }
}

function Move-DeadLetterToRecovered {
    <#
    .SYNOPSIS
    Moves a recovered record to the Recovered subfolder.
    .PARAMETER Record
    The recovered record.
    .PARAMETER DataDirectoryPath
    Optional base data directory.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject]$Record,
        [string]$DataDirectoryPath
    )

    $filePath = $Record._FilePath
    if ([string]::IsNullOrWhiteSpace($filePath) -or -not (Test-Path -LiteralPath $filePath)) {
        return $false
    }

    $deadLetterDir = Split-Path -Parent $filePath
    $recoveredDir = Join-Path $deadLetterDir 'Recovered'

    if (-not (Test-Path -LiteralPath $recoveredDir)) {
        try {
            New-Item -ItemType Directory -Path $recoveredDir -Force | Out-Null
        } catch {
            return $false
        }
    }

    try {
        $recordCopy = $Record | Select-Object -Property * -ExcludeProperty '_FilePath'
        $json = $recordCopy | ConvertTo-Json -Depth 10 -Compress
        $newPath = Join-Path $recoveredDir (Split-Path -Leaf $filePath)
        [System.IO.File]::WriteAllText($newPath, $json, [System.Text.Encoding]::UTF8)
        Remove-Item -LiteralPath $filePath -Force -ErrorAction SilentlyContinue
        return $true
    } catch {
        return $false
    }
}

function Remove-ExpiredDeadLetterRecords {
    <#
    .SYNOPSIS
    Removes dead-letter records older than retention period.
    .PARAMETER Site
    The site code.
    .PARAMETER RetentionDays
    Number of days to retain records. Defaults to 30.
    .PARAMETER DataDirectoryPath
    Optional base data directory.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Site,
        [int]$RetentionDays = 30,
        [string]$DataDirectoryPath
    )

    if ($RetentionDays -le 0) { $RetentionDays = $script:DeadLetterRetentionDays }

    $deadLetterDir = Get-DeadLetterPath -Site $Site -DataDirectoryPath $DataDirectoryPath

    if (-not (Test-Path -LiteralPath $deadLetterDir)) {
        return 0
    }

    $cutoffDate = [datetime]::UtcNow.AddDays(-$RetentionDays)
    $removed = 0

    try {
        # Clean main dead-letter folder
        $files = Get-ChildItem -LiteralPath $deadLetterDir -Filter '*.json' -File -ErrorAction SilentlyContinue
        foreach ($file in $files) {
            if ($file.LastWriteTimeUtc -lt $cutoffDate) {
                try {
                    Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
                    $removed++
                    $script:DeadLetterStats.TotalExpired++
                } catch { }
            }
        }

        # Clean recovered folder
        $recoveredDir = Join-Path $deadLetterDir 'Recovered'
        if (Test-Path -LiteralPath $recoveredDir) {
            $recoveredFiles = Get-ChildItem -LiteralPath $recoveredDir -Filter '*.json' -File -ErrorAction SilentlyContinue
            foreach ($file in $recoveredFiles) {
                if ($file.LastWriteTimeUtc -lt $cutoffDate) {
                    try {
                        Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
                        $removed++
                    } catch { }
                }
            }
        }
    } catch {
        Write-Warning "[DeadLetter] Failed to clean expired records: $($_.Exception.Message)"
    }

    return $removed
}

function Get-DeadLetterStats {
    <#
    .SYNOPSIS
    Returns dead-letter queue statistics.
    .PARAMETER Site
    Optional site code to include file-based stats.
    .PARAMETER DataDirectoryPath
    Optional base data directory.
    #>
    [CmdletBinding()]
    param(
        [string]$Site,
        [string]$DataDirectoryPath
    )

    $stats = [pscustomobject]@{
        TotalQueued = $script:DeadLetterStats.TotalQueued
        TotalRetried = $script:DeadLetterStats.TotalRetried
        TotalRecovered = $script:DeadLetterStats.TotalRecovered
        TotalExpired = $script:DeadLetterStats.TotalExpired
        PendingCount = 0
        FailedCount = 0
    }

    if (-not [string]::IsNullOrWhiteSpace($Site)) {
        $pending = Get-DeadLetterRecords -Site $Site -Status 'Pending' -DataDirectoryPath $DataDirectoryPath
        $failed = Get-DeadLetterRecords -Site $Site -Status 'Failed' -DataDirectoryPath $DataDirectoryPath
        $stats.PendingCount = $pending.Count
        $stats.FailedCount = $failed.Count
    }

    return $stats
}

function Clear-DeadLetterStats {
    <#
    .SYNOPSIS
    Resets the in-memory dead-letter statistics.
    #>
    [CmdletBinding()]
    param()

    $script:DeadLetterStats = @{
        TotalQueued = 0
        TotalRetried = 0
        TotalRecovered = 0
        TotalExpired = 0
    }
}

Export-ModuleMember -Function `
    Get-DeadLetterPath, `
    New-DeadLetterRecord, `
    Add-DeadLetterRecord, `
    Write-ToDeadLetter, `
    Get-DeadLetterRecords, `
    Invoke-DeadLetterRetry, `
    Update-DeadLetterRecord, `
    Move-DeadLetterToRecovered, `
    Remove-ExpiredDeadLetterRecords, `
    Get-DeadLetterStats, `
    Clear-DeadLetterStats
