
# NetworkReader.ps1
# ===============================

# Paths
$scriptRoot    = $PSScriptRoot
$logPath       = Join-Path $scriptRoot "Logs"
$outputPath    = Join-Path $scriptRoot "ParsedData"
$modulesPath   = Join-Path $scriptRoot "Modules"
$extractedPath = Join-Path $logPath "Extracted"
$archiveRoot   = Join-Path ([Environment]::GetFolderPath("MyDocuments")) "SwitchArchives"

# Ensure necessary directories
function Ensure-Directories {
    param ([string[]]$Paths)
    foreach ($path in $Paths) {
        if (-not (Test-Path $path)) {
            New-Item -ItemType Directory -Path $path | Out-Null
        }
    }
}

# Split logs into device-specific files
function Split-RawLogs {
    Get-ChildItem $logPath -File | Where-Object {
        $_.Extension -in '.log', '.txt' -and $_.Name -notlike '*Extracted*'
    } | ForEach-Object {
        $lines = Get-Content $_.FullName
        $currentHost = $null
        $currentLog = @()

        foreach ($line in $lines) {
            if ($line -match '^([^\s]+)#\s?') {
                $prompt = $Matches[1]
                $newHost = $prompt -replace '^.*@', ''

                if ($currentHost -and $newHost -ne $currentHost) {
                    $safeHost = $currentHost -replace '[\\\/:\*\?"<>\|]', '_'
                    $outFile = Join-Path $extractedPath "$safeHost.log"
                    $currentLog | Set-Content $outFile
                    $currentLog = @()
                }
                $currentHost = $newHost
            }

            if ($currentHost) {
                $currentLog += $line
            }
        }

        if ($currentHost -and $currentLog.Count -gt 0) {
            $safeHost = $currentHost -replace '[\\\/:\*\?"<>\|]', '_'
            $outFile = Join-Path $extractedPath "$safeHost.log"
            $currentLog | Set-Content $outFile
        }
    }
}

# Import parsing modules
function Import-ParserModules {
    Import-Module "$modulesPath\AristaModule.psm1" -Force
    Import-Module "$modulesPath\CiscoModule.psm1" -Force
    Import-Module "$modulesPath\BrocadeModule.psm1" -Force
}

# Prune old archive folders
function Remove-OldDeviceArchives {
    param (
        [string]$DeviceArchivePath,
        [int]$RetentionDays = 30
    )
    if (-not (Test-Path $DeviceArchivePath)) { return }

    Get-ChildItem $DeviceArchivePath -Directory | Where-Object {
        $folderDate = $null
        try {
            $folderDate = [datetime]::ParseExact(
                $_.Name,
                'yyyy-MM-dd',
                [System.Globalization.CultureInfo]::InvariantCulture
            )
        } catch {
            return $false
        }
        return $folderDate -lt (Get-Date).AddDays(-$RetentionDays)
    } | ForEach-Object {
        $oldFolder = $_
        try {
            Remove-Item $oldFolder.FullName -Recurse -Force
        } catch {
            Write-Warning "Failed to delete old archive '$($oldFolder.FullName)': $($_.Exception.Message)"
        }
    }
}

# Parse and export facts for a single log
function Process-DeviceLog {
    param ([string]$FilePath)

    $lines = Get-Content $FilePath

    # Vendor detection
    $make = if ($lines -match "Cisco IOS Software") {
        "Cisco"
    } elseif ($lines -match "Brocade") {
        "Brocade"
    } elseif ($lines -match "Arista") {
        "Arista"
    } else {
        Write-Warning "Unknown vendor for file $FilePath"
        return
    }

    try {
        switch ($make) {
            "Cisco"   { $facts = Get-CiscoDeviceFacts   -Lines $lines }
            "Brocade" { $facts = Get-BrocadeDeviceFacts -Lines $lines }
            "Arista"  { $facts = Get-AristaDeviceFacts  -Lines $lines }
        }
    } catch {
        Write-Warning "Failed to parse $make log '${FilePath}': $($_.Exception.Message)"
        return
    }

    if (-not $facts -or -not $facts.Hostname) {
        Write-Warning "No valid facts returned for $FilePath"
        return
    }

    $hostname     = $facts.Hostname -replace '[\\\/:\*\?"<>\|]', '_'
    $prefix       = Join-Path $outputPath $hostname
    $today        = Get-Date -Format "yyyy-MM-dd"
    $devicePath   = Join-Path $archiveRoot $hostname
    $archivePath  = Join-Path $devicePath $today
    $timestamp    = (Get-Date).ToUniversalTime().ToString("HHmm") + "Z"

    Ensure-Directories @($devicePath, $archivePath)

    # Export interface data
    if ($facts.PSObject.Properties.Name -contains "InterfacesCombined") {
        $facts.InterfacesCombined | Export-Csv "$prefix`_Interfaces_Combined.csv" -NoTypeInformation
        $facts.InterfacesCombined | Export-Csv (Join-Path $archivePath "Interfaces_Combined_${timestamp}.csv") -NoTypeInformation
    } else {
        $facts.Interfaces      | Export-Csv "$prefix`_Interfaces.csv" -NoTypeInformation
        $facts.MacTable        | Export-Csv "$prefix`_MacTable.csv"   -NoTypeInformation
        $facts.Dot1xStatus     | Export-Csv "$prefix`_Auth.csv"       -NoTypeInformation

        $facts.Interfaces      | Export-Csv (Join-Path $archivePath "Interfaces.csv") -NoTypeInformation
        $facts.MacTable        | Export-Csv (Join-Path $archivePath "MacTable.csv")   -NoTypeInformation
        $facts.Dot1xStatus     | Export-Csv (Join-Path $archivePath "Auth.csv")       -NoTypeInformation
    }

    # Export summary
    $summaryObj = [PSCustomObject]@{
        Hostname         = $facts.Hostname
        Make             = $facts.Make
        Model            = $facts.Model
        Version          = $facts.Version
        Uptime           = $facts.Uptime
        Location         = $facts.Location
        InterfaceCount   = $facts.InterfaceCount
        AuthDefaultVLAN  = $facts.AuthDefaultVLAN
        AuthBlock        = if ($facts.AuthenticationBlock) { $facts.AuthenticationBlock -join "`n" } else { "" }
    }

    $summaryObj | Export-Csv "$prefix`_Summary.csv" -NoTypeInformation
    $summaryArchivePath = Join-Path $archivePath "Summary_$timestamp.csv"
    $summaryObj | Export-Csv $summaryArchivePath -NoTypeInformation
    
    # Cleanup old archives
    Remove-OldDeviceArchives -DeviceArchivePath $devicePath -RetentionDays 30
}

# Cleanup extracted logs after processing
function Cleanup-ExtractedLogs {
    Get-ChildItem $extractedPath -File | Remove-Item -Force
}

# ===========================
# Main Entry Point
# ===========================

Ensure-Directories @($logPath, $outputPath, $extractedPath, $archiveRoot)
Import-ParserModules
Split-RawLogs

Get-ChildItem $extractedPath -File | ForEach-Object {
    Process-DeviceLog -FilePath $_.FullName
}

Cleanup-ExtractedLogs