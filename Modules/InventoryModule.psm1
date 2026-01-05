#Requires -Version 5.1
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Network inventory and asset tracking module for StateTrace.

.DESCRIPTION
    Provides comprehensive asset registry, warranty tracking, firmware version
    management, and lifecycle planning capabilities for network infrastructure.

.NOTES
    Plan X - Inventory & Asset Tracking
#>

# Module-level asset database
$script:AssetDatabase = $null
$script:ModuleDatabase = $null
$script:FirmwareDatabase = $null
$script:LifecycleDatabase = $null
$script:AssetHistory = $null
$script:MinimumFirmwareRequirements = $null
$script:DatabasePath = $null

#region Initialization

function Initialize-InventoryDatabase {
    <#
    .SYNOPSIS
        Initializes the inventory database structures.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Path,

        [Parameter()]
        [switch]$TestMode
    )

    if ($TestMode) {
        $script:DatabasePath = $null
    } elseif ($Path) {
        $script:DatabasePath = $Path
    } else {
        $dataDir = Join-Path $PSScriptRoot '..\Data'
        if (-not (Test-Path $dataDir)) {
            New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
        }
        $script:DatabasePath = Join-Path $dataDir 'InventoryDatabase.json'
    }

    # Initialize empty databases
    $script:AssetDatabase = New-Object System.Collections.ArrayList
    $script:ModuleDatabase = New-Object System.Collections.ArrayList
    $script:FirmwareDatabase = New-Object System.Collections.ArrayList
    $script:LifecycleDatabase = New-Object System.Collections.ArrayList
    $script:AssetHistory = New-Object System.Collections.ArrayList
    $script:MinimumFirmwareRequirements = New-Object System.Collections.ArrayList

    # Load existing data if available
    if ($script:DatabasePath -and (Test-Path $script:DatabasePath)) {
        Import-InventoryDatabase -Path $script:DatabasePath
    }

    # Load built-in lifecycle data
    Initialize-BuiltInLifecycleData
}

function Initialize-BuiltInLifecycleData {
    <#
    .SYNOPSIS
        Loads built-in vendor lifecycle information.
    #>
    $builtInLifecycle = @(
        # Cisco Catalyst 9000 Series
        @{
            ProductID = 'C9300-24P'
            Vendor = 'Cisco'
            Model = 'Catalyst 9300-24P'
            EndOfSaleDate = [DateTime]'2028-01-01'
            EndOfSupportDate = [DateTime]'2033-01-01'
            LastDateOfSupport = [DateTime]'2033-01-01'
            ReplacementModel = 'C9300X-24P'
            Notes = 'Standard 5-year support lifecycle'
        }
        @{
            ProductID = 'C9300-48P'
            Vendor = 'Cisco'
            Model = 'Catalyst 9300-48P'
            EndOfSaleDate = [DateTime]'2028-01-01'
            EndOfSupportDate = [DateTime]'2033-01-01'
            LastDateOfSupport = [DateTime]'2033-01-01'
            ReplacementModel = 'C9300X-48P'
            Notes = 'Standard 5-year support lifecycle'
        }
        @{
            ProductID = 'C9200-24P'
            Vendor = 'Cisco'
            Model = 'Catalyst 9200-24P'
            EndOfSaleDate = [DateTime]'2027-06-01'
            EndOfSupportDate = [DateTime]'2032-06-01'
            LastDateOfSupport = [DateTime]'2032-06-01'
            ReplacementModel = 'C9200CX-24P'
            Notes = 'Entry-level access switch'
        }
        # Legacy Catalyst
        @{
            ProductID = 'WS-C3850-24P'
            Vendor = 'Cisco'
            Model = 'Catalyst 3850-24P'
            EndOfSaleDate = [DateTime]'2022-10-31'
            EndOfSupportDate = [DateTime]'2027-10-31'
            LastDateOfSupport = [DateTime]'2027-10-31'
            ReplacementModel = 'C9300-24P'
            Notes = 'End of sale announced'
        }
        @{
            ProductID = 'WS-C3850-48P'
            Vendor = 'Cisco'
            Model = 'Catalyst 3850-48P'
            EndOfSaleDate = [DateTime]'2022-10-31'
            EndOfSupportDate = [DateTime]'2027-10-31'
            LastDateOfSupport = [DateTime]'2027-10-31'
            ReplacementModel = 'C9300-48P'
            Notes = 'End of sale announced'
        }
        # Arista
        @{
            ProductID = 'DCS-7050SX-64'
            Vendor = 'Arista'
            Model = '7050SX-64'
            EndOfSaleDate = [DateTime]'2025-12-31'
            EndOfSupportDate = [DateTime]'2030-12-31'
            LastDateOfSupport = [DateTime]'2030-12-31'
            ReplacementModel = '7050X3-48YC8'
            Notes = 'Data center leaf switch'
        }
        @{
            ProductID = 'DCS-7280SR-48C6'
            Vendor = 'Arista'
            Model = '7280SR-48C6'
            EndOfSaleDate = [DateTime]'2027-06-30'
            EndOfSupportDate = [DateTime]'2032-06-30'
            LastDateOfSupport = [DateTime]'2032-06-30'
            ReplacementModel = '7280R3-48YC6'
            Notes = 'Spine/leaf switch'
        }
        # Brocade/Ruckus
        @{
            ProductID = 'ICX7150-24P'
            Vendor = 'Ruckus'
            Model = 'ICX 7150-24P'
            EndOfSaleDate = [DateTime]'2026-03-31'
            EndOfSupportDate = [DateTime]'2031-03-31'
            LastDateOfSupport = [DateTime]'2031-03-31'
            ReplacementModel = 'ICX7550-24P'
            Notes = 'Campus access switch'
        }
        @{
            ProductID = 'ICX7450-48P'
            Vendor = 'Ruckus'
            Model = 'ICX 7450-48P'
            EndOfSaleDate = [DateTime]'2025-09-30'
            EndOfSupportDate = [DateTime]'2030-09-30'
            LastDateOfSupport = [DateTime]'2030-09-30'
            ReplacementModel = 'ICX7650-48P'
            Notes = 'Campus distribution switch'
        }
    )

    foreach ($item in $builtInLifecycle) {
        $existing = $script:LifecycleDatabase | Where-Object { $_.ProductID -eq $item.ProductID }
        if (-not $existing) {
            $lifecycle = [PSCustomObject]$item
            [void]$script:LifecycleDatabase.Add($lifecycle)
        }
    }
}

#endregion

#region Asset Management

function New-Asset {
    <#
    .SYNOPSIS
        Creates a new asset record.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Hostname,

        [Parameter()]
        [string]$Vendor,

        [Parameter()]
        [string]$Model,

        [Parameter()]
        [string]$Platform,

        [Parameter()]
        [string]$SerialNumber,

        [Parameter()]
        [string]$AssetTag,

        [Parameter()]
        [string]$ManagementIP,

        [Parameter()]
        [DateTime]$PurchaseDate,

        [Parameter()]
        [string]$PurchaseVendor,

        [Parameter()]
        [decimal]$PurchasePrice,

        [Parameter()]
        [DateTime]$WarrantyExpiration,

        [Parameter()]
        [string]$SupportContract,

        [Parameter()]
        [ValidateSet('NBD', '4-Hour', '24x7x4', '24x7x2', 'None')]
        [string]$SupportLevel = 'None',

        [Parameter()]
        [string]$Site,

        [Parameter()]
        [string]$Building,

        [Parameter()]
        [string]$Rack,

        [Parameter()]
        [int]$RackU,

        [Parameter()]
        [ValidateSet('Active', 'Spare', 'RMA', 'Decommissioned', 'Staging', 'Unknown')]
        [string]$Status = 'Active',

        [Parameter()]
        [string]$FirmwareVersion,

        [Parameter()]
        [string]$Notes
    )

    # Validate serial number is not empty if provided
    if ($PSBoundParameters.ContainsKey('SerialNumber') -and [string]::IsNullOrWhiteSpace($SerialNumber)) {
        throw "Serial number cannot be empty"
    }

    # Check for duplicate serial number
    if ($SerialNumber) {
        $existing = $script:AssetDatabase | Where-Object { $_.SerialNumber -eq $SerialNumber }
        if ($existing) {
            throw "Asset with serial number '$SerialNumber' already exists"
        }
    }

    $assetId = [Guid]::NewGuid().ToString()
    $now = Get-Date

    $asset = [PSCustomObject]@{
        AssetID = $assetId
        Hostname = $Hostname
        Vendor = $Vendor
        Model = $Model
        Platform = $Platform
        SerialNumber = $SerialNumber
        AssetTag = $AssetTag
        ManagementIP = $ManagementIP
        PurchaseDate = $PurchaseDate
        PurchaseVendor = $PurchaseVendor
        PurchasePrice = $PurchasePrice
        WarrantyExpiration = $WarrantyExpiration
        SupportContract = $SupportContract
        SupportLevel = $SupportLevel
        Site = $Site
        Building = $Building
        Rack = $Rack
        RackU = $RackU
        Status = $Status
        FirmwareVersion = $FirmwareVersion
        Notes = $Notes
        CreatedDate = $now
        ModifiedDate = $now
    }

    [void]$script:AssetDatabase.Add($asset)

    # Log history
    Add-AssetHistoryEntry -AssetID $assetId -ChangeType 'Created' -Details "Asset created: $Hostname"

    return $asset
}

function Get-Asset {
    <#
    .SYNOPSIS
        Retrieves assets from the database.
    #>
    [CmdletBinding(DefaultParameterSetName = 'All')]
    param(
        [Parameter(ParameterSetName = 'ByID')]
        [string]$AssetID,

        [Parameter(ParameterSetName = 'ByHostname')]
        [string]$Hostname,

        [Parameter(ParameterSetName = 'BySerial')]
        [string]$SerialNumber,

        [Parameter(ParameterSetName = 'ByVendor')]
        [string]$Vendor,

        [Parameter(ParameterSetName = 'BySite')]
        [string]$Site,

        [Parameter(ParameterSetName = 'ByStatus')]
        [ValidateSet('Active', 'Spare', 'RMA', 'Decommissioned', 'Staging', 'Unknown')]
        [string]$Status
    )

    $results = $script:AssetDatabase

    switch ($PSCmdlet.ParameterSetName) {
        'ByID' { $results = $results | Where-Object { $_.AssetID -eq $AssetID } }
        'ByHostname' { $results = $results | Where-Object { $_.Hostname -like "*$Hostname*" } }
        'BySerial' { $results = $results | Where-Object { $_.SerialNumber -eq $SerialNumber } }
        'ByVendor' { $results = $results | Where-Object { $_.Vendor -eq $Vendor } }
        'BySite' { $results = $results | Where-Object { $_.Site -eq $Site } }
        'ByStatus' { $results = $results | Where-Object { $_.Status -eq $Status } }
    }

    # Add calculated properties
    $today = Get-Date
    foreach ($asset in $results) {
        $daysUntilExpiration = $null
        if ($asset.WarrantyExpiration) {
            $daysUntilExpiration = [Math]::Floor(($asset.WarrantyExpiration - $today).TotalDays)
        }
        Add-Member -InputObject $asset -NotePropertyName 'DaysUntilExpiration' -NotePropertyValue $daysUntilExpiration -Force
    }

    return $results
}

function Update-Asset {
    <#
    .SYNOPSIS
        Updates an existing asset record.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AssetID,

        [Parameter()]
        [string]$Hostname,

        [Parameter()]
        [string]$Vendor,

        [Parameter()]
        [string]$Model,

        [Parameter()]
        [string]$ManagementIP,

        [Parameter()]
        [DateTime]$WarrantyExpiration,

        [Parameter()]
        [string]$SupportContract,

        [Parameter()]
        [string]$SupportLevel,

        [Parameter()]
        [string]$Site,

        [Parameter()]
        [string]$Building,

        [Parameter()]
        [string]$Rack,

        [Parameter()]
        [int]$RackU,

        [Parameter()]
        [string]$FirmwareVersion,

        [Parameter()]
        [string]$Notes
    )

    $asset = $script:AssetDatabase | Where-Object { $_.AssetID -eq $AssetID }
    if (-not $asset) {
        throw "Asset with ID '$AssetID' not found"
    }

    $changes = @()

    foreach ($param in $PSBoundParameters.Keys) {
        if ($param -eq 'AssetID') { continue }

        $oldValue = $asset.$param
        $newValue = $PSBoundParameters[$param]

        if ($oldValue -ne $newValue) {
            $asset.$param = $newValue
            $changes += "$param`: '$oldValue' -> '$newValue'"
        }
    }

    if ($changes.Count -gt 0) {
        $asset.ModifiedDate = Get-Date
        Add-AssetHistoryEntry -AssetID $AssetID -ChangeType 'Updated' -Details ($changes -join '; ')
    }

    return $asset
}

function Set-AssetStatus {
    <#
    .SYNOPSIS
        Updates the status of an asset.
    #>
    [CmdletBinding()]
    param(
        [Parameter(ParameterSetName = 'ByID')]
        [string]$AssetID,

        [Parameter(ParameterSetName = 'BySerial')]
        [string]$SerialNumber,

        [Parameter(Mandatory)]
        [ValidateSet('Active', 'Spare', 'RMA', 'Decommissioned', 'Staging', 'Unknown')]
        [string]$Status,

        [Parameter()]
        [string]$Reason
    )

    $asset = $null
    if ($AssetID) {
        $asset = $script:AssetDatabase | Where-Object { $_.AssetID -eq $AssetID }
    } elseif ($SerialNumber) {
        $asset = $script:AssetDatabase | Where-Object { $_.SerialNumber -eq $SerialNumber }
    }

    if (-not $asset) {
        throw "Asset not found"
    }

    $oldStatus = $asset.Status
    $asset.Status = $Status
    $asset.ModifiedDate = Get-Date

    $details = "Status changed: $oldStatus -> $Status"
    if ($Reason) {
        $details += " (Reason: $Reason)"
    }

    Add-AssetHistoryEntry -AssetID $asset.AssetID -ChangeType 'StatusChange' -Details $details

    return $asset
}

function Remove-Asset {
    <#
    .SYNOPSIS
        Removes an asset from the database.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AssetID
    )

    $asset = $script:AssetDatabase | Where-Object { $_.AssetID -eq $AssetID }
    if (-not $asset) {
        throw "Asset with ID '$AssetID' not found"
    }

    Add-AssetHistoryEntry -AssetID $AssetID -ChangeType 'Deleted' -Details "Asset removed: $($asset.Hostname)"

    [void]$script:AssetDatabase.Remove($asset)
}

#endregion

#region Module Management

function New-AssetModule {
    <#
    .SYNOPSIS
        Creates a new module record for an asset.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AssetID,

        [Parameter(Mandatory)]
        [ValidateSet('LineCard', 'PowerSupply', 'Fan', 'SFP', 'Supervisor', 'StackModule', 'Other')]
        [string]$ModuleType,

        [Parameter()]
        [string]$PartNumber,

        [Parameter()]
        [string]$SerialNumber,

        [Parameter()]
        [string]$SlotPosition,

        [Parameter()]
        [ValidateSet('Active', 'Standby', 'Failed', 'Empty')]
        [string]$Status = 'Active',

        [Parameter()]
        [DateTime]$InstallDate,

        [Parameter()]
        [string]$Notes
    )

    # Verify asset exists
    $asset = $script:AssetDatabase | Where-Object { $_.AssetID -eq $AssetID }
    if (-not $asset) {
        throw "Asset with ID '$AssetID' not found"
    }

    $moduleId = [Guid]::NewGuid().ToString()

    $module = [PSCustomObject]@{
        ModuleID = $moduleId
        AssetID = $AssetID
        ModuleType = $ModuleType
        PartNumber = $PartNumber
        SerialNumber = $SerialNumber
        SlotPosition = $SlotPosition
        Status = $Status
        InstallDate = $InstallDate
        Notes = $Notes
        CreatedDate = Get-Date
    }

    [void]$script:ModuleDatabase.Add($module)

    Add-AssetHistoryEntry -AssetID $AssetID -ChangeType 'ModuleAdded' -Details "Module added: $ModuleType in $SlotPosition"

    return $module
}

function Get-AssetModule {
    <#
    .SYNOPSIS
        Retrieves modules for an asset.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$AssetID,

        [Parameter()]
        [string]$ModuleType
    )

    $results = $script:ModuleDatabase

    if ($AssetID) {
        $results = $results | Where-Object { $_.AssetID -eq $AssetID }
    }

    if ($ModuleType) {
        $results = $results | Where-Object { $_.ModuleType -eq $ModuleType }
    }

    return $results
}

#endregion

#region Warranty Tracking

function Get-ExpiringWarranties {
    <#
    .SYNOPSIS
        Returns assets with warranties expiring within the specified period.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [int]$DaysAhead = 90
    )

    $today = Get-Date
    $threshold = $today.AddDays($DaysAhead)

    $expiring = $script:AssetDatabase | Where-Object {
        $_.WarrantyExpiration -and
        $_.WarrantyExpiration -gt $today -and
        $_.WarrantyExpiration -le $threshold
    } | Sort-Object WarrantyExpiration

    foreach ($asset in $expiring) {
        $days = [Math]::Floor(($asset.WarrantyExpiration - $today).TotalDays)
        Add-Member -InputObject $asset -NotePropertyName 'DaysUntilExpiration' -NotePropertyValue $days -Force
    }

    return $expiring
}

function Get-ExpiredWarranties {
    <#
    .SYNOPSIS
        Returns assets with expired warranties.
    #>
    [CmdletBinding()]
    param()

    $today = Get-Date

    $expired = $script:AssetDatabase | Where-Object {
        $_.WarrantyExpiration -and $_.WarrantyExpiration -lt $today
    } | Sort-Object WarrantyExpiration -Descending

    foreach ($asset in $expired) {
        $days = [Math]::Floor(($today - $asset.WarrantyExpiration).TotalDays)
        Add-Member -InputObject $asset -NotePropertyName 'DaysExpired' -NotePropertyValue $days -Force
    }

    return $expired
}

function Get-WarrantySummary {
    <#
    .SYNOPSIS
        Returns a summary of warranty status across all assets.
    #>
    [CmdletBinding()]
    param()

    $today = Get-Date
    $assets = @($script:AssetDatabase | Where-Object { $_.WarrantyExpiration })

    $summary = [PSCustomObject]@{
        TotalWithWarranty = $assets.Count
        Active = @($assets | Where-Object { $_.WarrantyExpiration -gt $today }).Count
        Expired = @($assets | Where-Object { $_.WarrantyExpiration -lt $today }).Count
        Expiring30Days = @($assets | Where-Object { $_.WarrantyExpiration -gt $today -and $_.WarrantyExpiration -le $today.AddDays(30) }).Count
        Expiring60Days = @($assets | Where-Object { $_.WarrantyExpiration -gt $today -and $_.WarrantyExpiration -le $today.AddDays(60) }).Count
        Expiring90Days = @($assets | Where-Object { $_.WarrantyExpiration -gt $today -and $_.WarrantyExpiration -le $today.AddDays(90) }).Count
        BySupportLevel = @{}
    }

    $byLevel = $assets | Group-Object -Property SupportLevel
    foreach ($group in $byLevel) {
        $summary.BySupportLevel[$group.Name] = $group.Count
    }

    return $summary
}

#endregion

#region Firmware Management

function New-FirmwareVersion {
    <#
    .SYNOPSIS
        Registers a known firmware version in the database.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Vendor,

        [Parameter(Mandatory)]
        [string]$Platform,

        [Parameter(Mandatory)]
        [string]$VersionString,

        [Parameter()]
        [DateTime]$ReleaseDate,

        [Parameter()]
        [DateTime]$EndOfSupportDate,

        [Parameter()]
        [switch]$IsRecommended,

        [Parameter()]
        [switch]$IsCritical,

        [Parameter()]
        [string[]]$CVEList,

        [Parameter()]
        [string]$Notes
    )

    $versionId = [Guid]::NewGuid().ToString()

    $firmware = [PSCustomObject]@{
        VersionID = $versionId
        Vendor = $Vendor
        Platform = $Platform
        VersionString = $VersionString
        ReleaseDate = $ReleaseDate
        EndOfSupportDate = $EndOfSupportDate
        IsRecommended = $IsRecommended.IsPresent
        IsCritical = $IsCritical.IsPresent
        CVEList = $CVEList
        Notes = $Notes
        CreatedDate = Get-Date
    }

    [void]$script:FirmwareDatabase.Add($firmware)

    return $firmware
}

function Get-FirmwareVersion {
    <#
    .SYNOPSIS
        Retrieves firmware versions from the database.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Vendor,

        [Parameter()]
        [string]$Platform,

        [Parameter()]
        [switch]$RecommendedOnly,

        [Parameter()]
        [switch]$WithCVEs
    )

    $results = $script:FirmwareDatabase

    if ($Vendor) {
        $results = $results | Where-Object { $_.Vendor -eq $Vendor }
    }

    if ($Platform) {
        $results = $results | Where-Object { $_.Platform -like "*$Platform*" }
    }

    if ($RecommendedOnly) {
        $results = $results | Where-Object { $_.IsRecommended }
    }

    if ($WithCVEs) {
        $results = $results | Where-Object { $_.CVEList -and $_.CVEList.Count -gt 0 }
    }

    return $results
}

function Parse-FirmwareVersion {
    <#
    .SYNOPSIS
        Parses a firmware version string into components.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$VersionString,

        [Parameter(Mandatory)]
        [ValidateSet('Cisco', 'Arista', 'Ruckus', 'Brocade', 'Juniper')]
        [string]$Vendor
    )

    $version = [PSCustomObject]@{
        VersionString = $VersionString
        Vendor = $Vendor
        Major = 0
        Minor = 0
        Patch = 0
        Build = $null
        TrainCode = $null
    }

    switch ($Vendor) {
        'Cisco' {
            # Cisco IOS-XE: 17.06.05, 17.03.05a, 16.12.04
            if ($VersionString -match '^(\d+)\.(\d+)\.(\d+)([a-z])?') {
                $version.Major = [int]$Matches[1]
                $version.Minor = [int]$Matches[2]
                $version.Patch = [int]$Matches[3]
                if ($Matches[4]) {
                    $version.TrainCode = $Matches[4]
                }
            }
            # Older IOS: 15.2(7)E4
            elseif ($VersionString -match '^(\d+)\.(\d+)\((\d+)\)([A-Z]+)(\d+)?') {
                $version.Major = [int]$Matches[1]
                $version.Minor = [int]$Matches[2]
                $version.Patch = [int]$Matches[3]
                $version.TrainCode = $Matches[4]
                if ($Matches[5]) {
                    $version.Build = [int]$Matches[5]
                }
            }
        }
        'Arista' {
            # Arista EOS: 4.28.3M, 4.27.5.1M
            if ($VersionString -match '^(\d+)\.(\d+)\.(\d+)(?:\.(\d+))?([A-Z]+)?') {
                $version.Major = [int]$Matches[1]
                $version.Minor = [int]$Matches[2]
                $version.Patch = [int]$Matches[3]
                if ($Matches[4]) {
                    $version.Build = [int]$Matches[4]
                }
                if ($Matches[5]) {
                    $version.TrainCode = $Matches[5]
                }
            }
        }
        { $_ -in 'Ruckus', 'Brocade' } {
            # Ruckus/Brocade ICX: 08.0.95, 09.0.10
            if ($VersionString -match '^(\d+)\.(\d+)\.(\d+)([a-z])?') {
                $version.Major = [int]$Matches[1]
                $version.Minor = [int]$Matches[2]
                $version.Patch = [int]$Matches[3]
            }
        }
        'Juniper' {
            # Junos: 21.4R3-S2, 22.2R1
            if ($VersionString -match '^(\d+)\.(\d+)R(\d+)(?:-S(\d+))?') {
                $version.Major = [int]$Matches[1]
                $version.Minor = [int]$Matches[2]
                $version.Patch = [int]$Matches[3]
                if ($Matches[4]) {
                    $version.Build = [int]$Matches[4]
                }
            }
        }
    }

    return $version
}

function Set-MinimumFirmware {
    <#
    .SYNOPSIS
        Sets the minimum required firmware version for a platform.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Vendor,

        [Parameter(Mandatory)]
        [string]$Platform,

        [Parameter(Mandatory)]
        [string]$MinVersion,

        [Parameter()]
        [string]$Reason
    )

    # Remove existing requirement for this platform
    $existing = $script:MinimumFirmwareRequirements | Where-Object {
        $_.Vendor -eq $Vendor -and $_.Platform -eq $Platform
    }
    if ($existing) {
        [void]$script:MinimumFirmwareRequirements.Remove($existing)
    }

    $requirement = [PSCustomObject]@{
        Vendor = $Vendor
        Platform = $Platform
        MinVersion = $MinVersion
        Reason = $Reason
        SetDate = Get-Date
    }

    [void]$script:MinimumFirmwareRequirements.Add($requirement)

    return $requirement
}

function Get-DevicesBelowMinimumFirmware {
    <#
    .SYNOPSIS
        Returns devices running firmware below the minimum required version.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Vendor,

        [Parameter()]
        [string]$Platform
    )

    $requirements = $script:MinimumFirmwareRequirements

    if ($Vendor) {
        $requirements = $requirements | Where-Object { $_.Vendor -eq $Vendor }
    }

    if ($Platform) {
        $requirements = $requirements | Where-Object { $_.Platform -like "*$Platform*" }
    }

    $belowMinimum = New-Object System.Collections.ArrayList

    foreach ($req in $requirements) {
        $minParsed = Parse-FirmwareVersion -VersionString $req.MinVersion -Vendor $req.Vendor

        $devices = $script:AssetDatabase | Where-Object {
            $_.Vendor -eq $req.Vendor -and
            $_.Model -like "*$($req.Platform)*" -and
            $_.FirmwareVersion
        }

        foreach ($device in $devices) {
            $deviceParsed = Parse-FirmwareVersion -VersionString $device.FirmwareVersion -Vendor $device.Vendor

            $isBelow = $false
            if ($deviceParsed.Major -lt $minParsed.Major) {
                $isBelow = $true
            } elseif ($deviceParsed.Major -eq $minParsed.Major -and $deviceParsed.Minor -lt $minParsed.Minor) {
                $isBelow = $true
            } elseif ($deviceParsed.Major -eq $minParsed.Major -and $deviceParsed.Minor -eq $minParsed.Minor -and $deviceParsed.Patch -lt $minParsed.Patch) {
                $isBelow = $true
            }

            if ($isBelow) {
                $result = $device | Select-Object *
                Add-Member -InputObject $result -NotePropertyName 'MinimumRequired' -NotePropertyValue $req.MinVersion -Force
                Add-Member -InputObject $result -NotePropertyName 'UpdateReason' -NotePropertyValue $req.Reason -Force
                [void]$belowMinimum.Add($result)
            }
        }
    }

    return $belowMinimum
}

function Get-VulnerableDevices {
    <#
    .SYNOPSIS
        Returns devices running firmware with known CVEs.
    #>
    [CmdletBinding()]
    param()

    $vulnerableFirmware = $script:FirmwareDatabase | Where-Object {
        $_.CVEList -and $_.CVEList.Count -gt 0
    }

    $vulnerable = New-Object System.Collections.ArrayList

    foreach ($fw in $vulnerableFirmware) {
        $devices = $script:AssetDatabase | Where-Object {
            $_.Vendor -eq $fw.Vendor -and
            $_.FirmwareVersion -eq $fw.VersionString
        }

        foreach ($device in $devices) {
            $result = $device | Select-Object *
            Add-Member -InputObject $result -NotePropertyName 'CVEList' -NotePropertyValue $fw.CVEList -Force
            [void]$vulnerable.Add($result)
        }
    }

    return $vulnerable
}

function Get-FirmwareComplianceSummary {
    <#
    .SYNOPSIS
        Returns a summary of firmware compliance across all devices.
    #>
    [CmdletBinding()]
    param()

    $total = ($script:AssetDatabase | Where-Object { $_.FirmwareVersion }).Count
    $belowMinimum = (Get-DevicesBelowMinimumFirmware).Count
    $vulnerable = (Get-VulnerableDevices).Count
    $compliant = $total - $belowMinimum

    $compliancePercent = 0
    if ($total -gt 0) {
        $compliancePercent = [Math]::Round(($compliant / $total) * 100, 1)
    }

    return [PSCustomObject]@{
        TotalDevices = $total
        Compliant = $compliant
        BelowMinimum = $belowMinimum
        Vulnerable = $vulnerable
        CompliancePercent = $compliancePercent
    }
}

#endregion

#region Lifecycle Management

function Get-LifecycleInfo {
    <#
    .SYNOPSIS
        Retrieves lifecycle information for a product.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$ProductID,

        [Parameter()]
        [string]$Model,

        [Parameter()]
        [string]$Vendor
    )

    $results = $script:LifecycleDatabase

    if ($ProductID) {
        $results = $results | Where-Object { $_.ProductID -eq $ProductID }
    }

    if ($Model) {
        $results = $results | Where-Object { $_.Model -like "*$Model*" }
    }

    if ($Vendor) {
        $results = $results | Where-Object { $_.Vendor -eq $Vendor }
    }

    $today = Get-Date
    foreach ($item in $results) {
        $daysToEoS = $null
        $daysToEoSu = $null

        if ($item.EndOfSaleDate) {
            $daysToEoS = [Math]::Floor(($item.EndOfSaleDate - $today).TotalDays)
        }
        if ($item.EndOfSupportDate) {
            $daysToEoSu = [Math]::Floor(($item.EndOfSupportDate - $today).TotalDays)
        }

        Add-Member -InputObject $item -NotePropertyName 'DaysToEndOfSale' -NotePropertyValue $daysToEoS -Force
        Add-Member -InputObject $item -NotePropertyName 'DaysToEndOfSupport' -NotePropertyValue $daysToEoSu -Force
    }

    return $results
}

function Get-DevicesApproachingEoL {
    <#
    .SYNOPSIS
        Returns devices approaching end of life within the specified period.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [int]$DaysAhead = 365
    )

    $today = Get-Date
    $threshold = $today.AddDays($DaysAhead)

    $approachingEoL = New-Object System.Collections.ArrayList

    foreach ($asset in $script:AssetDatabase) {
        # Try to find lifecycle info for this device
        $lifecycle = $script:LifecycleDatabase | Where-Object {
            ($_.ProductID -and $asset.Model -like "*$($_.ProductID)*") -or
            ($_.Model -and $asset.Model -like "*$($_.Model)*")
        } | Select-Object -First 1

        if ($lifecycle -and $lifecycle.EndOfSupportDate) {
            if ($lifecycle.EndOfSupportDate -le $threshold) {
                $result = $asset | Select-Object *
                Add-Member -InputObject $result -NotePropertyName 'EndOfSaleDate' -NotePropertyValue $lifecycle.EndOfSaleDate -Force
                Add-Member -InputObject $result -NotePropertyName 'EndOfSupportDate' -NotePropertyValue $lifecycle.EndOfSupportDate -Force
                Add-Member -InputObject $result -NotePropertyName 'ReplacementModel' -NotePropertyValue $lifecycle.ReplacementModel -Force

                $daysToEoSu = [Math]::Floor(($lifecycle.EndOfSupportDate - $today).TotalDays)
                Add-Member -InputObject $result -NotePropertyName 'DaysToEndOfSupport' -NotePropertyValue $daysToEoSu -Force

                [void]$approachingEoL.Add($result)
            }
        }
    }

    return $approachingEoL | Sort-Object DaysToEndOfSupport
}

function Add-LifecycleInfo {
    <#
    .SYNOPSIS
        Adds lifecycle information for a product.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProductID,

        [Parameter(Mandatory)]
        [string]$Vendor,

        [Parameter(Mandatory)]
        [string]$Model,

        [Parameter()]
        [DateTime]$EndOfSaleDate,

        [Parameter()]
        [DateTime]$EndOfSupportDate,

        [Parameter()]
        [DateTime]$LastDateOfSupport,

        [Parameter()]
        [string]$ReplacementModel,

        [Parameter()]
        [string]$Notes
    )

    $lifecycle = [PSCustomObject]@{
        ProductID = $ProductID
        Vendor = $Vendor
        Model = $Model
        EndOfSaleDate = $EndOfSaleDate
        EndOfSupportDate = $EndOfSupportDate
        LastDateOfSupport = $LastDateOfSupport
        ReplacementModel = $ReplacementModel
        Notes = $Notes
    }

    [void]$script:LifecycleDatabase.Add($lifecycle)

    return $lifecycle
}

#endregion

#region History & Audit

function Add-AssetHistoryEntry {
    <#
    .SYNOPSIS
        Adds an entry to the asset history log.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AssetID,

        [Parameter(Mandatory)]
        [ValidateSet('Created', 'Updated', 'StatusChange', 'ModuleAdded', 'ModuleRemoved', 'Deleted', 'Imported')]
        [string]$ChangeType,

        [Parameter()]
        [string]$Details
    )

    $entry = [PSCustomObject]@{
        HistoryID = [Guid]::NewGuid().ToString()
        AssetID = $AssetID
        ChangeType = $ChangeType
        Details = $Details
        Timestamp = Get-Date
        User = $env:USERNAME
    }

    [void]$script:AssetHistory.Add($entry)

    return $entry
}

function Get-AssetHistory {
    <#
    .SYNOPSIS
        Retrieves history for an asset.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$AssetID,

        [Parameter()]
        [string]$SerialNumber
    )

    if ($SerialNumber) {
        $asset = $script:AssetDatabase | Where-Object { $_.SerialNumber -eq $SerialNumber }
        if ($asset) {
            $AssetID = $asset.AssetID
        }
    }

    if ($AssetID) {
        return $script:AssetHistory | Where-Object { $_.AssetID -eq $AssetID } | Sort-Object Timestamp
    }

    return $script:AssetHistory | Sort-Object Timestamp
}

#endregion

#region Import / Export

function Import-AssetInventory {
    <#
    .SYNOPSIS
        Imports assets from a CSV file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        throw "File not found: $Path"
    }

    $csvData = Import-Csv -Path $Path
    $imported = 0
    $errors = New-Object System.Collections.ArrayList

    foreach ($row in $csvData) {
        try {
            $params = @{
                Hostname = $row.Hostname
            }

            # Map CSV columns to parameters
            if ($row.Vendor) { $params.Vendor = $row.Vendor }
            if ($row.Model) { $params.Model = $row.Model }
            if ($row.SerialNumber) { $params.SerialNumber = $row.SerialNumber }
            if ($row.AssetTag) { $params.AssetTag = $row.AssetTag }
            if ($row.ManagementIP) { $params.ManagementIP = $row.ManagementIP }
            if ($row.Site) { $params.Site = $row.Site }
            if ($row.Building) { $params.Building = $row.Building }
            if ($row.Rack) { $params.Rack = $row.Rack }
            if ($row.Status) { $params.Status = $row.Status }
            if ($row.FirmwareVersion) { $params.FirmwareVersion = $row.FirmwareVersion }
            if ($row.Notes) { $params.Notes = $row.Notes }

            if ($row.PurchaseDate) {
                $params.PurchaseDate = [DateTime]::Parse($row.PurchaseDate)
            }
            if ($row.WarrantyExpiration) {
                $params.WarrantyExpiration = [DateTime]::Parse($row.WarrantyExpiration)
            }

            New-Asset @params
            $imported++
        }
        catch {
            [void]$errors.Add("Row $($row.Hostname): $($_.Exception.Message)")
        }
    }

    return [PSCustomObject]@{
        ImportedCount = $imported
        TotalRows = $csvData.Count
        Errors = $errors
    }
}

function Export-AssetInventory {
    <#
    .SYNOPSIS
        Exports the asset inventory to a file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [ValidateSet('CSV', 'JSON')]
        [string]$Format = 'CSV',

        [Parameter()]
        [string]$Site,

        [Parameter()]
        [string]$Vendor,

        [Parameter()]
        [string]$Status
    )

    $assets = @($script:AssetDatabase)

    if ($Site) {
        $assets = @($assets | Where-Object { $_.Site -eq $Site })
    }
    if ($Vendor) {
        $assets = @($assets | Where-Object { $_.Vendor -eq $Vendor })
    }
    if ($Status) {
        $assets = @($assets | Where-Object { $_.Status -eq $Status })
    }

    switch ($Format) {
        'CSV' {
            $assets | Export-Csv -Path $Path -NoTypeInformation
        }
        'JSON' {
            $assets | ConvertTo-Json -Depth 10 | Set-Content -Path $Path
        }
    }

    return [PSCustomObject]@{
        Path = $Path
        Format = $Format
        ExportedCount = $assets.Count
    }
}

function Parse-ShowVersion {
    <#
    .SYNOPSIS
        Parses 'show version' output to extract hardware information.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Content,

        [Parameter(Mandatory)]
        [ValidateSet('Cisco', 'Arista', 'Ruckus', 'Brocade')]
        [string]$Vendor
    )

    $info = [PSCustomObject]@{
        Vendor = $Vendor
        Model = $null
        SerialNumber = $null
        Version = $null
        Hostname = $null
        Uptime = $null
    }

    switch ($Vendor) {
        'Cisco' {
            if ($Content -match 'System serial number:\s*(\S+)') {
                $info.SerialNumber = $Matches[1]
            } elseif ($Content -match 'Processor board ID\s+(\S+)') {
                $info.SerialNumber = $Matches[1]
            }

            if ($Content -match 'Model number:\s*(\S+)') {
                $info.Model = $Matches[1]
            } elseif ($Content -match 'cisco\s+(\S+)') {
                $info.Model = $Matches[1]
            }

            if ($Content -match 'Version\s+(\d+\.\d+\.\d+[a-zA-Z]?)') {
                $info.Version = $Matches[1]
            } elseif ($Content -match 'Version\s+(\d+\.\d+\(\d+\)[A-Z]+\d*)') {
                $info.Version = $Matches[1]
            }

            if ($Content -match '(\S+)\s+uptime\s+is') {
                $info.Hostname = $Matches[1]
            }
        }
        'Arista' {
            if ($Content -match 'Serial number:\s*(\S+)') {
                $info.SerialNumber = $Matches[1]
            }

            if ($Content -match 'Arista\s+(\S+)') {
                $info.Model = $Matches[1]
            }

            if ($Content -match 'Software image version:\s*(\S+)') {
                $info.Version = $Matches[1]
            }

            if ($Content -match 'Hostname:\s*(\S+)') {
                $info.Hostname = $Matches[1]
            }
        }
        { $_ -in 'Ruckus', 'Brocade' } {
            if ($Content -match 'System Serial #:\s*(\S+)') {
                $info.SerialNumber = $Matches[1]
            }

            if ($Content -match 'System:\s*(\S+)') {
                $info.Model = $Matches[1]
            } elseif ($Content -match 'ICX(\d+)') {
                $info.Model = "ICX$($Matches[1])"
            }

            if ($Content -match 'SW:\s*Version\s+(\S+)') {
                $info.Version = $Matches[1]
            }
        }
    }

    return $info
}

function Import-InventoryDatabase {
    <#
    .SYNOPSIS
        Imports inventory data from a JSON file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        return
    }

    try {
        $data = Get-Content -Path $Path -Raw | ConvertFrom-Json

        if ($data.Assets) {
            $script:AssetDatabase.Clear()
            foreach ($item in $data.Assets) {
                [void]$script:AssetDatabase.Add($item)
            }
        }

        if ($data.Modules) {
            $script:ModuleDatabase.Clear()
            foreach ($item in $data.Modules) {
                [void]$script:ModuleDatabase.Add($item)
            }
        }

        if ($data.Firmware) {
            $script:FirmwareDatabase.Clear()
            foreach ($item in $data.Firmware) {
                [void]$script:FirmwareDatabase.Add($item)
            }
        }

        if ($data.History) {
            $script:AssetHistory.Clear()
            foreach ($item in $data.History) {
                [void]$script:AssetHistory.Add($item)
            }
        }

        if ($data.MinimumFirmware) {
            $script:MinimumFirmwareRequirements.Clear()
            foreach ($item in $data.MinimumFirmware) {
                [void]$script:MinimumFirmwareRequirements.Add($item)
            }
        }
    }
    catch {
        Write-Warning "Failed to import inventory database: $_"
    }
}

function Export-InventoryDatabase {
    <#
    .SYNOPSIS
        Exports the inventory database to a JSON file.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Path
    )

    if (-not $Path) {
        $Path = $script:DatabasePath
    }

    if (-not $Path) {
        throw "No database path specified"
    }

    $data = @{
        Assets = @($script:AssetDatabase)
        Modules = @($script:ModuleDatabase)
        Firmware = @($script:FirmwareDatabase)
        Lifecycle = @($script:LifecycleDatabase)
        History = @($script:AssetHistory)
        MinimumFirmware = @($script:MinimumFirmwareRequirements)
        ExportDate = Get-Date
    }

    $data | ConvertTo-Json -Depth 10 | Set-Content -Path $Path

    return [PSCustomObject]@{
        Path = $Path
        AssetCount = $script:AssetDatabase.Count
        ModuleCount = $script:ModuleDatabase.Count
    }
}

#endregion

#region Reports

function Get-InventorySummary {
    <#
    .SYNOPSIS
        Returns a summary of the inventory.
    #>
    [CmdletBinding()]
    param()

    $assets = $script:AssetDatabase

    $summary = [PSCustomObject]@{
        TotalDevices = $assets.Count
        ByVendor = @{}
        BySite = @{}
        ByStatus = @{}
        ByModel = @{}
    }

    $byVendor = $assets | Group-Object -Property Vendor
    foreach ($group in $byVendor) {
        if ($group.Name) {
            $summary.ByVendor[$group.Name] = $group.Count
        }
    }

    $bySite = $assets | Group-Object -Property Site
    foreach ($group in $bySite) {
        if ($group.Name) {
            $summary.BySite[$group.Name] = $group.Count
        }
    }

    $byStatus = $assets | Group-Object -Property Status
    foreach ($group in $byStatus) {
        if ($group.Name) {
            $summary.ByStatus[$group.Name] = $group.Count
        }
    }

    $byModel = $assets | Group-Object -Property Model | Sort-Object Count -Descending | Select-Object -First 10
    foreach ($group in $byModel) {
        if ($group.Name) {
            $summary.ByModel[$group.Name] = $group.Count
        }
    }

    return $summary
}

function Export-WarrantyReport {
    <#
    .SYNOPSIS
        Exports a warranty status report.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Text', 'CSV', 'HTML')]
        [string]$Format,

        [Parameter(Mandatory)]
        [string]$OutputPath,

        [Parameter()]
        [int]$ExpiringWithin = 90
    )

    $today = Get-Date
    $expiring = @(Get-ExpiringWarranties -DaysAhead $ExpiringWithin)
    $expired = @(Get-ExpiredWarranties)
    $summary = Get-WarrantySummary

    $filename = "WarrantyReport_$(Get-Date -Format 'yyyyMMdd').$($Format.ToLower())"
    $fullPath = Join-Path $OutputPath $filename

    switch ($Format) {
        'Text' {
            $report = @"
NETWORK DEVICE WARRANTY REPORT
Generated: $today

SUMMARY
-------
Total Devices with Warranty: $($summary.TotalWithWarranty)
Active Warranties: $($summary.Active)
Expired Warranties: $($summary.Expired)
Expiring in 30 Days: $($summary.Expiring30Days)
Expiring in 60 Days: $($summary.Expiring60Days)
Expiring in 90 Days: $($summary.Expiring90Days)

EXPIRING SOON (within $ExpiringWithin days)
-------------------------------------------
"@
            foreach ($asset in $expiring) {
                $report += "`n$($asset.Hostname) - $($asset.SerialNumber) - Expires: $($asset.WarrantyExpiration.ToString('yyyy-MM-dd')) ($($asset.DaysUntilExpiration) days)"
            }

            $report += @"

EXPIRED WARRANTIES
------------------
"@
            foreach ($asset in $expired) {
                $report += "`n$($asset.Hostname) - $($asset.SerialNumber) - Expired: $($asset.WarrantyExpiration.ToString('yyyy-MM-dd')) ($($asset.DaysExpired) days ago)"
            }

            $report | Set-Content -Path $fullPath
        }
        'CSV' {
            $allWarrantyData = @()

            foreach ($asset in $expiring) {
                $allWarrantyData += [PSCustomObject]@{
                    Hostname = $asset.Hostname
                    SerialNumber = $asset.SerialNumber
                    Vendor = $asset.Vendor
                    Model = $asset.Model
                    WarrantyExpiration = $asset.WarrantyExpiration
                    Status = 'Expiring'
                    DaysRemaining = $asset.DaysUntilExpiration
                    SupportLevel = $asset.SupportLevel
                }
            }

            foreach ($asset in $expired) {
                $allWarrantyData += [PSCustomObject]@{
                    Hostname = $asset.Hostname
                    SerialNumber = $asset.SerialNumber
                    Vendor = $asset.Vendor
                    Model = $asset.Model
                    WarrantyExpiration = $asset.WarrantyExpiration
                    Status = 'Expired'
                    DaysRemaining = -$asset.DaysExpired
                    SupportLevel = $asset.SupportLevel
                }
            }

            $allWarrantyData | Export-Csv -Path $fullPath -NoTypeInformation
        }
        'HTML' {
            $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Warranty Report - $(Get-Date -Format 'yyyy-MM-dd')</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #333; }
        h2 { color: #666; border-bottom: 1px solid #ddd; padding-bottom: 5px; }
        table { border-collapse: collapse; width: 100%; margin-bottom: 20px; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #4CAF50; color: white; }
        tr:nth-child(even) { background-color: #f2f2f2; }
        .critical { background-color: #ffcccc; }
        .warning { background-color: #fff3cd; }
        .summary { display: flex; gap: 20px; margin-bottom: 20px; }
        .summary-card { background: #f8f9fa; padding: 15px; border-radius: 5px; min-width: 150px; }
        .summary-number { font-size: 2em; font-weight: bold; color: #333; }
    </style>
</head>
<body>
    <h1>Network Device Warranty Report</h1>
    <p>Generated: $today</p>

    <div class="summary">
        <div class="summary-card">
            <div class="summary-number">$($summary.TotalWithWarranty)</div>
            <div>Total Devices</div>
        </div>
        <div class="summary-card">
            <div class="summary-number">$($summary.Active)</div>
            <div>Active</div>
        </div>
        <div class="summary-card">
            <div class="summary-number" style="color: red;">$($summary.Expired)</div>
            <div>Expired</div>
        </div>
        <div class="summary-card">
            <div class="summary-number" style="color: orange;">$($summary.Expiring30Days)</div>
            <div>Expiring 30d</div>
        </div>
    </div>

    <h2>Expiring Soon (within $ExpiringWithin days)</h2>
    <table>
        <tr><th>Hostname</th><th>Serial</th><th>Vendor</th><th>Model</th><th>Expires</th><th>Days Left</th><th>Support</th></tr>
"@
            foreach ($asset in $expiring) {
                $rowClass = if ($asset.DaysUntilExpiration -le 30) { 'critical' } elseif ($asset.DaysUntilExpiration -le 60) { 'warning' } else { '' }
                $html += "        <tr class='$rowClass'><td>$($asset.Hostname)</td><td>$($asset.SerialNumber)</td><td>$($asset.Vendor)</td><td>$($asset.Model)</td><td>$($asset.WarrantyExpiration.ToString('yyyy-MM-dd'))</td><td>$($asset.DaysUntilExpiration)</td><td>$($asset.SupportLevel)</td></tr>`n"
            }

            $html += @"
    </table>

    <h2>Expired Warranties</h2>
    <table>
        <tr><th>Hostname</th><th>Serial</th><th>Vendor</th><th>Model</th><th>Expired</th><th>Days Ago</th></tr>
"@
            foreach ($asset in $expired) {
                $html += "        <tr class='critical'><td>$($asset.Hostname)</td><td>$($asset.SerialNumber)</td><td>$($asset.Vendor)</td><td>$($asset.Model)</td><td>$($asset.WarrantyExpiration.ToString('yyyy-MM-dd'))</td><td>$($asset.DaysExpired)</td></tr>`n"
            }

            $html += @"
    </table>
</body>
</html>
"@
            $html | Set-Content -Path $fullPath
        }
    }

    return [PSCustomObject]@{
        Path = $fullPath
        Format = $Format
        ExpiringCount = $expiring.Count
        ExpiredCount = $expired.Count
    }
}

function Get-LifecycleReport {
    <#
    .SYNOPSIS
        Returns a lifecycle and refresh planning report.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [int]$EoLWithin = 365
    )

    $approaching = @(Get-DevicesApproachingEoL -DaysAhead $EoLWithin)

    $byYear = $approaching | Group-Object { $_.EndOfSupportDate.Year } | Sort-Object Name

    return [PSCustomObject]@{
        TotalApproachingEoL = $approaching.Count
        ByYear = @($byYear | ForEach-Object {
            [PSCustomObject]@{
                Year = $_.Name
                Count = $_.Count
                Devices = $_.Group | Select-Object Hostname, Model, EndOfSupportDate, ReplacementModel
            }
        })
        Devices = $approaching
    }
}

#endregion

#region Test Helpers

function Remove-TestInventoryData {
    <#
    .SYNOPSIS
        Removes all test data from the inventory.
    #>
    [CmdletBinding()]
    param()

    $script:AssetDatabase.Clear()
    $script:ModuleDatabase.Clear()
    $script:FirmwareDatabase.Clear()
    $script:AssetHistory.Clear()
    $script:MinimumFirmwareRequirements.Clear()
}

function Get-InventoryDatabasePath {
    <#
    .SYNOPSIS
        Returns the current database path.
    #>
    [CmdletBinding()]
    param()

    return $script:DatabasePath
}

#endregion

# Initialize on module load
Initialize-InventoryDatabase

# Export functions
Export-ModuleMember -Function @(
    # Initialization
    'Initialize-InventoryDatabase'

    # Asset Management
    'New-Asset'
    'Get-Asset'
    'Update-Asset'
    'Set-AssetStatus'
    'Remove-Asset'

    # Module Management
    'New-AssetModule'
    'Get-AssetModule'

    # Warranty Tracking
    'Get-ExpiringWarranties'
    'Get-ExpiredWarranties'
    'Get-WarrantySummary'

    # Firmware Management
    'New-FirmwareVersion'
    'Get-FirmwareVersion'
    'Parse-FirmwareVersion'
    'Set-MinimumFirmware'
    'Get-DevicesBelowMinimumFirmware'
    'Get-VulnerableDevices'
    'Get-FirmwareComplianceSummary'

    # Lifecycle Management
    'Get-LifecycleInfo'
    'Get-DevicesApproachingEoL'
    'Add-LifecycleInfo'

    # History & Audit
    'Add-AssetHistoryEntry'
    'Get-AssetHistory'

    # Import / Export
    'Import-AssetInventory'
    'Export-AssetInventory'
    'Parse-ShowVersion'
    'Import-InventoryDatabase'
    'Export-InventoryDatabase'

    # Reports
    'Get-InventorySummary'
    'Export-WarrantyReport'
    'Get-LifecycleReport'

    # Test Helpers
    'Remove-TestInventoryData'
    'Get-InventoryDatabasePath'
)
