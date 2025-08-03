function New-Directories {
    param ([string[]]$Paths)
    foreach ($path in $Paths) {
        if (-not (Test-Path $path)) {
            New-Item -ItemType Directory -Path $path | Out-Null
        }
    }
}

# Extract structured details from an SNMP location string.  Cisco and Brocade devices
# allow arbitrary strings for the `snmp-server location` configuration; a common
# convention in this environment is to separate fields with underscores.  For
# example: `Bldg_244_Floor_1_Room_33_Row_1_Rack_1`.  This helper splits the
# string on underscores and inspects adjacent key/value pairs.  Keys are
# matched case-insensitively so `bldg`, `building` and `Bldg` are all accepted.
# Returns a hashtable containing the discovered values.  Unmatched keys are
# ignored.
function Get-LocationDetails {
    [CmdletBinding()] param(
        [string]$Location
    )
    # Default return structure with empty strings.  Additional keys can be
    # appended here if more metadata is introduced in the future.
    $details = @{
        Building = ''
        Floor    = ''
        Room     = ''
        Row      = ''
        Rack     = ''
    }
    if (-not [string]::IsNullOrWhiteSpace($Location)) {
        # Split on underscores to capture tokens.  Use `-split` to support any
        # whitespace surrounding underscores and remove empty elements.
        $tokens = $Location -split '_+' | Where-Object { $_ -ne '' }
        for ($i = 0; $i -lt $tokens.Count - 1; $i++) {
            $key = $tokens[$i].Trim()
            $value = $tokens[$i + 1].Trim()
            switch -regex ($key.ToLower()) {
                '^(bldg|building)$' { $details['Building'] = $value; continue }
                '^floor$'          { $details['Floor']    = $value; continue }
                '^room$'           { $details['Room']     = $value; continue }
                '^row$'            { $details['Row']      = $value; continue }
                '^rack$'           { $details['Rack']     = $value; continue }
            }
        }
    }
    return $details
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

    $make = if ($lines -match "Cisco") {
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

    New-Directories @($devicePath, $archivePath)

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

    # Export spanning tree information if available.  The facts may contain
    # a property named SpanInfo which is a collection of records.  Create
    # a *_Span.csv file in both the parsed and archive directories.  Skip
    # export if the property does not exist or is empty.
    if ($facts.PSObject.Properties.Name -contains 'SpanInfo') {
        $spanData = $facts.SpanInfo
        if ($spanData -and $spanData.Count -gt 0) {
            $spanCsvPath = "$prefix`_Span.csv"
            $spanData | Export-Csv $spanCsvPath -NoTypeInformation
            $spanArchivePath = Join-Path $archivePath "Span_${timestamp}.csv"
            $spanData | Export-Csv $spanArchivePath -NoTypeInformation
        }
    }

    # Derive additional metadata about the device.  The site is defined as the
    # first four characters of the hostname (when available).  Location
    # information (building, floor, room, etc.) is encoded in the
    # `snmp-server location` string and parsed via the helper above.  These
    # values will be persisted to the summary so the GUI can filter devices.
    # Clean the hostname to remove any SSH@ prefix that may have been
    # inadvertently captured from prompts.  The raw facts.Hostname comes from
    # the device's configuration and may include such prefixes.
    $cleanHostname = $facts.Hostname
    if ($cleanHostname) {
        $cleanHostname = $cleanHostname -replace '^SSH@',''
    }
    $siteCode = ''
    if ($cleanHostname -and $cleanHostname.Length -ge 4) {
        $siteCode = $cleanHostname.Substring(0,4)
    } elseif ($cleanHostname) {
        # For very short hostnames just use the full name as a site code
        $siteCode = $cleanHostname
    }
    $locDetails = Get-LocationDetails -Location $facts.Location

    $summaryObj = [PSCustomObject]@{
        Hostname         = $cleanHostname
        Make             = $facts.Make
        Model            = $facts.Model
        Version          = $facts.Version
        Uptime           = $facts.Uptime
        Location         = $facts.Location
        Site             = $siteCode
        Building         = $locDetails.Building
        Floor            = $locDetails.Floor
        Room             = $locDetails.Room
        Row              = $locDetails.Row
        Rack             = $locDetails.Rack
        InterfaceCount   = $facts.InterfaceCount
        AuthDefaultVLAN  = $facts.AuthDefaultVLAN
        AuthBlock        = if ($facts.AuthenticationBlock) { $facts.AuthenticationBlock -join "`n" } else { "" }
    }

    $summaryObj | Export-Csv "$prefix`_Summary.csv" -NoTypeInformation
    $summaryObj | Export-Csv (Join-Path $archivePath "Summary_$timestamp.csv") -NoTypeInformation

    Remove-OldArchiveFolder -DeviceArchivePath $devicePath -RetentionDays 30
}
