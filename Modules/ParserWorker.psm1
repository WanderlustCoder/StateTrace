function Initialize-Directories {
    param ([string[]]$Paths)
    foreach ($path in $Paths) {
        if (-not (Test-Path $path)) {
            New-Item -ItemType Directory -Path $path | Out-Null
        }
    }
}

function Remove-OldArchiveFolder {
    param (
        [string]$DeviceArchivePath,
        [int]$RetentionDays = 30
    )
    if (-not (Test-Path $DeviceArchivePath)) { return }

    Get-ChildItem $DeviceArchivePath -Directory | Where-Object {
        $folderDate = $null
        try {
            $folderDate = [datetime]::ParseExact($_.Name, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
        } catch { return $false }
        return $folderDate -lt (Get-Date).AddDays(-$RetentionDays)
    } | ForEach-Object {
        try { Remove-Item $_.FullName -Recurse -Force }
        catch { Write-Warning "Failed to delete archive '$_': $($_.Exception.Message)" }
    }
}

function Invoke-DeviceLogParsing {
    param (
        [string]$FilePath,
        [string]$OutputPath,
        [string]$ArchiveRoot
    )

    $lines = Get-Content $FilePath

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
    $prefix       = Join-Path $OutputPath $hostname
    $today        = Get-Date -Format "yyyy-MM-dd"
    $devicePath   = Join-Path $ArchiveRoot $hostname
    $archivePath  = Join-Path $devicePath $today
    $timestamp    = (Get-Date).ToUniversalTime().ToString("HHmm") + "Z"

    Initialize-Directories @($devicePath, $archivePath)

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
    $summaryObj | Export-Csv (Join-Path $archivePath "Summary_$timestamp.csv") -NoTypeInformation

    Remove-OldArchiveFolder -DeviceArchivePath $devicePath -RetentionDays 30
}
