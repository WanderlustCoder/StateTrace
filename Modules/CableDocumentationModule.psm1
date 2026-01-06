Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Cable documentation and patch panel management module.

.DESCRIPTION
    Provides functionality for tracking cable runs, managing patch panels,
    generating cable labels, and maintaining physical network documentation.
    Part of Plan T - Cable & Port Documentation.
#>

#region Data Structures

<#
.SYNOPSIS
    Creates a new cable run object.

.PARAMETER CableID
    Unique identifier for the cable. Auto-generated if not provided.

.PARAMETER SourceType
    Type of source endpoint: Device, PatchPanel, WallJack, Other.

.PARAMETER SourceDevice
    Name of source device or panel.

.PARAMETER SourcePort
    Port identifier at source.

.PARAMETER DestType
    Type of destination endpoint: Device, PatchPanel, WallJack, Other.

.PARAMETER DestDevice
    Name of destination device or panel.

.PARAMETER DestPort
    Port identifier at destination.

.PARAMETER CableType
    Type of cable: Cat5e, Cat6, Cat6a, FiberOM3, FiberOM4, FiberOS2, Coax, Other.

.PARAMETER Length
    Cable length with unit (e.g., "10ft", "3m").

.PARAMETER Color
    Cable jacket color.

.PARAMETER Status
    Cable status: Active, Reserved, Abandoned, Faulty, Planned.

.PARAMETER Notes
    Additional notes about the cable run.
#>
function New-CableRun {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$CableID,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Device', 'PatchPanel', 'WallJack', 'Other')]
        [string]$SourceType,

        [Parameter(Mandatory = $true)]
        [string]$SourceDevice,

        [Parameter(Mandatory = $true)]
        [string]$SourcePort,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Device', 'PatchPanel', 'WallJack', 'Other')]
        [string]$DestType,

        [Parameter(Mandatory = $true)]
        [string]$DestDevice,

        [Parameter(Mandatory = $true)]
        [string]$DestPort,

        [Parameter()]
        [ValidateSet('Cat5e', 'Cat6', 'Cat6a', 'FiberOM3', 'FiberOM4', 'FiberOS2', 'Coax', 'Other')]
        [string]$CableType = 'Cat6',

        [Parameter()]
        [string]$Length,

        [Parameter()]
        [string]$Color,

        [Parameter()]
        [ValidateSet('Active', 'Reserved', 'Abandoned', 'Faulty', 'Planned')]
        [string]$Status = 'Active',

        [Parameter()]
        [string]$Notes,

        [Parameter()]
        [string]$CreatedBy,

        [Parameter()]
        [datetime]$InstallDate,

        [Parameter()]
        [datetime]$VerifyDate
    )

    # Auto-generate CableID if not provided
    if (-not $CableID) {
        $CableID = 'CBL-' + [guid]::NewGuid().ToString().Substring(0, 8).ToUpper()
    }

    $now = Get-Date

    [PSCustomObject]@{
        CableID      = $CableID
        SourceType   = $SourceType
        SourceDevice = $SourceDevice
        SourcePort   = $SourcePort
        DestType     = $DestType
        DestDevice   = $DestDevice
        DestPort     = $DestPort
        CableType    = $CableType
        Length       = $Length
        Color        = $Color
        Status       = $Status
        Notes        = $Notes
        CreatedBy    = if ($CreatedBy) { $CreatedBy } else { $env:USERNAME }
        InstallDate  = $InstallDate
        VerifyDate   = $VerifyDate
        CreatedDate  = $now
        ModifiedDate = $now
    }
}

<#
.SYNOPSIS
    Creates a new patch panel object.

.PARAMETER PanelID
    Unique identifier for the panel. Auto-generated if not provided.

.PARAMETER PanelName
    Display name for the patch panel.

.PARAMETER Location
    Physical location (room, closet, etc.).

.PARAMETER RackID
    Rack identifier if panel is rack-mounted.

.PARAMETER RackU
    Rack unit position.

.PARAMETER PortCount
    Number of ports on the panel.

.PARAMETER PanelType
    Type of panel: Copper, Fiber, Mixed.

.PARAMETER Notes
    Additional notes.
#>
function New-PatchPanel {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$PanelID,

        [Parameter(Mandatory = $true)]
        [string]$PanelName,

        [Parameter()]
        [string]$Location,

        [Parameter()]
        [string]$RackID,

        [Parameter()]
        [string]$RackU,

        [Parameter()]
        [ValidateRange(1, 96)]
        [int]$PortCount = 24,

        [Parameter()]
        [ValidateSet('Copper', 'Fiber', 'Mixed')]
        [string]$PanelType = 'Copper',

        [Parameter()]
        [string]$Notes
    )

    if (-not $PanelID) {
        $PanelID = 'PP-' + [guid]::NewGuid().ToString().Substring(0, 8).ToUpper()
    }

    $now = Get-Date

    # Initialize ports array
    $ports = @()
    for ($i = 1; $i -le $PortCount; $i++) {
        $ports += [PSCustomObject]@{
            PortNumber = $i
            CableID    = $null
            Label      = ''
            Status     = 'Empty'
            Notes      = ''
        }
    }

    [PSCustomObject]@{
        PanelID      = $PanelID
        PanelName    = $PanelName
        Location     = $Location
        RackID       = $RackID
        RackU        = $RackU
        PortCount    = $PortCount
        PanelType    = $PanelType
        Notes        = $Notes
        Ports        = $ports
        CreatedDate  = $now
        ModifiedDate = $now
    }
}

#endregion

#region Cable Database Operations

# Module-level storage
$script:CableDatabase = @{
    Cables      = New-Object System.Collections.ArrayList
    PatchPanels = New-Object System.Collections.ArrayList
}

<#
.SYNOPSIS
    Adds a cable run to the database.

.PARAMETER Cable
    The cable run object to add.

.PARAMETER Database
    Optional external database hashtable.
#>
function Add-CableRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSCustomObject]$Cable,

        [Parameter()]
        [hashtable]$Database
    )

    process {
        $db = if ($Database) { $Database } else { $script:CableDatabase }

        # Check for duplicate CableID
        $existing = $db.Cables | Where-Object { $_.CableID -eq $Cable.CableID }
        if ($existing) {
            Write-Warning "Cable with ID '$($Cable.CableID)' already exists."
            return $null
        }

        $db.Cables.Add($Cable) | Out-Null
        $Cable
    }
}

<#
.SYNOPSIS
    Gets cable runs from the database.

.PARAMETER CableID
    Filter by specific cable ID.

.PARAMETER Device
    Filter by device name (source or destination).

.PARAMETER Status
    Filter by cable status.

.PARAMETER CableType
    Filter by cable type.

.PARAMETER Database
    Optional external database hashtable.
#>
function Get-CableRun {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$CableID,

        [Parameter()]
        [string]$Device,

        [Parameter()]
        [string]$Status,

        [Parameter()]
        [string]$CableType,

        [Parameter()]
        [hashtable]$Database
    )

    $db = if ($Database) { $Database } else { $script:CableDatabase }
    $results = @($db.Cables)

    if ($CableID) {
        $results = @($results | Where-Object { $_.CableID -eq $CableID })
    }

    if ($Device) {
        $results = @($results | Where-Object {
            $_.SourceDevice -like "*$Device*" -or $_.DestDevice -like "*$Device*"
        })
    }

    if ($Status) {
        $results = @($results | Where-Object { $_.Status -eq $Status })
    }

    if ($CableType) {
        $results = @($results | Where-Object { $_.CableType -eq $CableType })
    }

    $results
}

<#
.SYNOPSIS
    Updates an existing cable run.

.PARAMETER CableID
    ID of the cable to update.

.PARAMETER Properties
    Hashtable of properties to update.

.PARAMETER Database
    Optional external database hashtable.
#>
function Update-CableRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CableID,

        [Parameter(Mandatory = $true)]
        [hashtable]$Properties,

        [Parameter()]
        [hashtable]$Database
    )

    $db = if ($Database) { $Database } else { $script:CableDatabase }
    $cable = $db.Cables | Where-Object { $_.CableID -eq $CableID } | Select-Object -First 1

    if (-not $cable) {
        Write-Warning "Cable with ID '$CableID' not found."
        return $null
    }

    foreach ($key in $Properties.Keys) {
        if ($cable.PSObject.Properties[$key]) {
            $cable.$key = $Properties[$key]
        }
    }
    $cable.ModifiedDate = Get-Date

    $cable
}

<#
.SYNOPSIS
    Removes a cable run from the database.

.PARAMETER CableID
    ID of the cable to remove.

.PARAMETER Database
    Optional external database hashtable.
#>
function Remove-CableRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CableID,

        [Parameter()]
        [hashtable]$Database
    )

    $db = if ($Database) { $Database } else { $script:CableDatabase }
    $cable = $db.Cables | Where-Object { $_.CableID -eq $CableID } | Select-Object -First 1

    if (-not $cable) {
        Write-Warning "Cable with ID '$CableID' not found."
        return $false
    }

    $db.Cables.Remove($cable)
    $true
}

#endregion

#region Patch Panel Operations

<#
.SYNOPSIS
    Adds a patch panel to the database.

.PARAMETER Panel
    The patch panel object to add.

.PARAMETER Database
    Optional external database hashtable.
#>
function Add-PatchPanel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSCustomObject]$Panel,

        [Parameter()]
        [hashtable]$Database
    )

    process {
        $db = if ($Database) { $Database } else { $script:CableDatabase }

        $existing = $db.PatchPanels | Where-Object { $_.PanelID -eq $Panel.PanelID }
        if ($existing) {
            Write-Warning "Patch panel with ID '$($Panel.PanelID)' already exists."
            return $null
        }

        $db.PatchPanels.Add($Panel) | Out-Null
        $Panel
    }
}

<#
.SYNOPSIS
    Gets patch panels from the database.

.PARAMETER PanelID
    Filter by specific panel ID.

.PARAMETER PanelName
    Filter by panel name (supports wildcards).

.PARAMETER Location
    Filter by location (supports wildcards).

.PARAMETER Database
    Optional external database hashtable.
#>
function Get-PatchPanel {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$PanelID,

        [Parameter()]
        [string]$PanelName,

        [Parameter()]
        [string]$Location,

        [Parameter()]
        [hashtable]$Database
    )

    $db = if ($Database) { $Database } else { $script:CableDatabase }
    $results = @($db.PatchPanels)

    if ($PanelID) {
        $results = @($results | Where-Object { $_.PanelID -eq $PanelID })
    }

    if ($PanelName) {
        $results = @($results | Where-Object { $_.PanelName -like "*$PanelName*" })
    }

    if ($Location) {
        $results = @($results | Where-Object { $_.Location -like "*$Location*" })
    }

    $results
}

<#
.SYNOPSIS
    Updates a patch panel port assignment.

.PARAMETER PanelID
    ID of the patch panel.

.PARAMETER PortNumber
    Port number to update (1-based).

.PARAMETER CableID
    Cable ID to assign to the port.

.PARAMETER Label
    Label for the port.

.PARAMETER Status
    Port status: Empty, Connected, Reserved, Faulty.

.PARAMETER Notes
    Notes for the port.

.PARAMETER Database
    Optional external database hashtable.
#>
function Set-PatchPanelPort {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PanelID,

        [Parameter(Mandatory = $true)]
        [int]$PortNumber,

        [Parameter()]
        [string]$CableID,

        [Parameter()]
        [string]$Label,

        [Parameter()]
        [ValidateSet('Empty', 'Connected', 'Reserved', 'Faulty')]
        [string]$Status,

        [Parameter()]
        [string]$Notes,

        [Parameter()]
        [hashtable]$Database
    )

    $db = if ($Database) { $Database } else { $script:CableDatabase }
    $panel = $db.PatchPanels | Where-Object { $_.PanelID -eq $PanelID } | Select-Object -First 1

    if (-not $panel) {
        Write-Warning "Patch panel with ID '$PanelID' not found."
        return $null
    }

    if ($PortNumber -lt 1 -or $PortNumber -gt $panel.PortCount) {
        Write-Warning "Port number $PortNumber is out of range (1-$($panel.PortCount))."
        return $null
    }

    $port = $panel.Ports | Where-Object { $_.PortNumber -eq $PortNumber } | Select-Object -First 1
    if (-not $port) {
        Write-Warning "Port $PortNumber not found in panel."
        return $null
    }

    if ($PSBoundParameters.ContainsKey('CableID')) { $port.CableID = $CableID }
    if ($PSBoundParameters.ContainsKey('Label')) { $port.Label = $Label }
    if ($PSBoundParameters.ContainsKey('Status')) { $port.Status = $Status }
    if ($PSBoundParameters.ContainsKey('Notes')) { $port.Notes = $Notes }

    $panel.ModifiedDate = Get-Date
    $port
}

<#
.SYNOPSIS
    Removes a patch panel from the database.

.PARAMETER PanelID
    ID of the panel to remove.

.PARAMETER Database
    Optional external database hashtable.
#>
function Remove-PatchPanel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PanelID,

        [Parameter()]
        [hashtable]$Database
    )

    $db = if ($Database) { $Database } else { $script:CableDatabase }
    $panel = $db.PatchPanels | Where-Object { $_.PanelID -eq $PanelID } | Select-Object -First 1

    if (-not $panel) {
        Write-Warning "Patch panel with ID '$PanelID' not found."
        return $false
    }

    $db.PatchPanels.Remove($panel)
    $true
}

#endregion

#region Label Generation

<#
.SYNOPSIS
    Generates a cable label object.

.PARAMETER Cable
    The cable run to generate a label for.

.PARAMETER LabelType
    Type of label: Full, SourceEnd, DestEnd, Compact.

.PARAMETER IncludeQR
    Include QR code data in the label.
#>
function New-CableLabel {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Cable,

        [Parameter()]
        [ValidateSet('Full', 'SourceEnd', 'DestEnd', 'Compact')]
        [string]$LabelType = 'Full',

        [Parameter()]
        [switch]$IncludeQR
    )

    $sourceLabel = "$($Cable.SourceDevice):$($Cable.SourcePort)"
    $destLabel = "$($Cable.DestDevice):$($Cable.DestPort)"

    $labelLines = switch ($LabelType) {
        'Full' {
            @(
                "CABLE: $($Cable.CableID)"
                "FROM: $sourceLabel"
                "TO: $destLabel"
                "TYPE: $($Cable.CableType)"
                if ($Cable.Length) { "LEN: $($Cable.Length)" }
            )
        }
        'SourceEnd' {
            @(
                $Cable.CableID
                "TO: $destLabel"
                $Cable.CableType
            )
        }
        'DestEnd' {
            @(
                $Cable.CableID
                "FROM: $sourceLabel"
                $Cable.CableType
            )
        }
        'Compact' {
            @(
                $Cable.CableID
                "$sourceLabel -> $destLabel"
            )
        }
    }

    $qrData = $null
    if ($IncludeQR) {
        $qrData = @{
            CableID = $Cable.CableID
            Source  = $sourceLabel
            Dest    = $destLabel
            Type    = $Cable.CableType
        } | ConvertTo-Json -Compress
    }

    [PSCustomObject]@{
        CableID   = $Cable.CableID
        LabelType = $LabelType
        Lines     = $labelLines
        QRData    = $qrData
        Width     = 2  # inches
        Height    = 0.5
    }
}

<#
.SYNOPSIS
    Generates a patch panel port label.

.PARAMETER Panel
    The patch panel object.

.PARAMETER PortNumber
    The port number to label.

.PARAMETER IncludeDestination
    Include cable destination in label.
#>
function New-PatchPanelLabel {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Panel,

        [Parameter(Mandatory = $true)]
        [int]$PortNumber,

        [Parameter()]
        [switch]$IncludeDestination,

        [Parameter()]
        [hashtable]$Database
    )

    $db = if ($Database) { $Database } else { $script:CableDatabase }
    $port = $Panel.Ports | Where-Object { $_.PortNumber -eq $PortNumber } | Select-Object -First 1

    if (-not $port) {
        Write-Warning "Port $PortNumber not found."
        return $null
    }

    $lines = @(
        "$($Panel.PanelName)-$PortNumber"
    )

    if ($port.Label) {
        $lines += $port.Label
    }

    if ($IncludeDestination -and $port.CableID) {
        $cable = Get-CableRun -CableID $port.CableID -Database $db
        if ($cable) {
            # Determine which end connects to this panel
            if ($cable.SourceDevice -eq $Panel.PanelName -or $cable.SourceDevice -eq $Panel.PanelID) {
                $lines += "-> $($cable.DestDevice):$($cable.DestPort)"
            } else {
                $lines += "-> $($cable.SourceDevice):$($cable.SourcePort)"
            }
        }
    }

    [PSCustomObject]@{
        PanelID    = $Panel.PanelID
        PortNumber = $PortNumber
        Lines      = $lines
        Width      = 0.75
        Height     = 0.375
    }
}

<#
.SYNOPSIS
    Exports labels to a printable format.

.PARAMETER Labels
    Array of label objects.

.PARAMETER Format
    Output format: Text, CSV, HTML.

.PARAMETER LabelWidth
    Label width in inches.

.PARAMETER LabelHeight
    Label height in inches.
#>
function Export-CableLabels {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSCustomObject[]]$Labels,

        [Parameter()]
        [ValidateSet('Text', 'CSV', 'HTML')]
        [string]$Format = 'Text',

        [Parameter()]
        [double]$LabelWidth = 2.0,

        [Parameter()]
        [double]$LabelHeight = 0.5
    )

    begin {
        $allLabels = New-Object System.Collections.ArrayList
    }

    process {
        foreach ($label in $Labels) {
            $allLabels.Add($label) | Out-Null
        }
    }

    end {
        switch ($Format) {
            'Text' {
                $output = New-Object System.Collections.ArrayList
                foreach ($label in $allLabels) {
                    $border = '+' + ('-' * 30) + '+'
                    $output.Add($border) | Out-Null
                    foreach ($line in $label.Lines) {
                        $padded = '| ' + $line.PadRight(28) + ' |'
                        $output.Add($padded) | Out-Null
                    }
                    $output.Add($border) | Out-Null
                    $output.Add('') | Out-Null
                }
                $output -join "`n"
            }
            'CSV' {
                $rows = foreach ($label in $allLabels) {
                    [PSCustomObject]@{
                        ID     = if ($label.CableID) { $label.CableID } else { "$($label.PanelID)-$($label.PortNumber)" }
                        Line1  = if ($label.Lines.Count -gt 0) { $label.Lines[0] } else { '' }
                        Line2  = if ($label.Lines.Count -gt 1) { $label.Lines[1] } else { '' }
                        Line3  = if ($label.Lines.Count -gt 2) { $label.Lines[2] } else { '' }
                        Line4  = if ($label.Lines.Count -gt 3) { $label.Lines[3] } else { '' }
                        Width  = $LabelWidth
                        Height = $LabelHeight
                    }
                }
                $rows | ConvertTo-Csv -NoTypeInformation
            }
            'HTML' {
                $html = @"
<!DOCTYPE html>
<html>
<head>
<style>
.label {
    border: 1px solid black;
    padding: 5px;
    margin: 5px;
    display: inline-block;
    width: $($LabelWidth)in;
    min-height: $($LabelHeight)in;
    font-family: monospace;
    font-size: 10pt;
    page-break-inside: avoid;
}
.label-line { margin: 2px 0; }
@media print {
    .label { margin: 2mm; }
}
</style>
</head>
<body>
"@
                foreach ($label in $allLabels) {
                    $html += "<div class='label'>`n"
                    foreach ($line in $label.Lines) {
                        $html += "  <div class='label-line'>$([System.Web.HttpUtility]::HtmlEncode($line))</div>`n"
                    }
                    $html += "</div>`n"
                }
                $html += "</body></html>"
                $html
            }
        }
    }
}

#endregion

#region Import/Export

<#
.SYNOPSIS
    Exports the cable database to JSON.

.PARAMETER Path
    Output file path.

.PARAMETER Database
    Optional external database hashtable.
#>
function Export-CableDatabase {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter()]
        [hashtable]$Database
    )

    $db = if ($Database) { $Database } else { $script:CableDatabase }

    $export = @{
        ExportDate  = (Get-Date).ToString('o')
        Version     = '1.0'
        Cables      = @($db.Cables)
        PatchPanels = @($db.PatchPanels)
    }

    $export | ConvertTo-Json -Depth 10 | Set-Content -Path $Path -Encoding UTF8
    Write-Verbose "Exported $($db.Cables.Count) cables and $($db.PatchPanels.Count) patch panels to $Path"
}

<#
.SYNOPSIS
    Imports a cable database from JSON.

.PARAMETER Path
    Input file path.

.PARAMETER Merge
    Merge with existing data instead of replacing.

.PARAMETER Database
    Optional external database hashtable.
#>
function Import-CableDatabase {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter()]
        [switch]$Merge,

        [Parameter()]
        [hashtable]$Database
    )

    if (-not (Test-Path $Path)) {
        Write-Warning "File not found: $Path"
        return $null
    }

    $db = if ($Database) { $Database } else { $script:CableDatabase }
    $content = Get-Content -Path $Path -Raw | ConvertFrom-Json

    if (-not $Merge) {
        $db.Cables.Clear()
        $db.PatchPanels.Clear()
    }

    $cablesAdded = 0
    $panelsAdded = 0

    foreach ($cable in $content.Cables) {
        $existing = $db.Cables | Where-Object { $_.CableID -eq $cable.CableID }
        if (-not $existing) {
            $db.Cables.Add($cable) | Out-Null
            $cablesAdded++
        }
    }

    foreach ($panel in $content.PatchPanels) {
        $existing = $db.PatchPanels | Where-Object { $_.PanelID -eq $panel.PanelID }
        if (-not $existing) {
            $db.PatchPanels.Add($panel) | Out-Null
            $panelsAdded++
        }
    }

    [PSCustomObject]@{
        CablesImported = $cablesAdded
        PanelsImported = $panelsAdded
        TotalCables    = $db.Cables.Count
        TotalPanels    = $db.PatchPanels.Count
    }
}

<#
.SYNOPSIS
    Imports cable runs from CSV.

.PARAMETER Path
    CSV file path.

.PARAMETER Database
    Optional external database hashtable.
#>
function Import-CableRunsFromCsv {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter()]
        [hashtable]$Database
    )

    if (-not (Test-Path $Path)) {
        Write-Warning "File not found: $Path"
        return $null
    }

    $db = if ($Database) { $Database } else { $script:CableDatabase }
    $rows = Import-Csv -Path $Path

    $imported = 0
    $errors = 0

    foreach ($row in $rows) {
        try {
            $params = @{
                SourceType   = if ($row.SourceType) { $row.SourceType } else { 'Device' }
                SourceDevice = $row.SourceDevice
                SourcePort   = $row.SourcePort
                DestType     = if ($row.DestType) { $row.DestType } else { 'Device' }
                DestDevice   = $row.DestDevice
                DestPort     = $row.DestPort
            }

            if ($row.CableID) { $params['CableID'] = $row.CableID }
            if ($row.CableType) { $params['CableType'] = $row.CableType }
            if ($row.Length) { $params['Length'] = $row.Length }
            if ($row.Color) { $params['Color'] = $row.Color }
            if ($row.Status) { $params['Status'] = $row.Status }
            if ($row.Notes) { $params['Notes'] = $row.Notes }

            $cable = New-CableRun @params
            $result = Add-CableRun -Cable $cable -Database $db
            if ($result) { $imported++ }
        }
        catch {
            $errors++
            Write-Warning "Error importing row: $($_.Exception.Message)"
        }
    }

    [PSCustomObject]@{
        Imported = $imported
        Errors   = $errors
    }
}

#endregion

#region Port Reorg Integration

<#
.SYNOPSIS
    Gets cable information for a specific device port.

.DESCRIPTION
    Looks up cable documentation for a given device and port combination.
    Returns the cable info in a format suitable for display in Port Reorg.

.PARAMETER DeviceName
    The device hostname or name.

.PARAMETER PortName
    The port identifier (e.g., Gi1/0/1).

.PARAMETER Database
    Optional external database hashtable.
#>
function Get-CableForPort {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DeviceName,

        [Parameter(Mandatory = $true)]
        [string]$PortName,

        [Parameter()]
        [hashtable]$Database
    )

    $db = if ($Database) { $Database } else { $script:CableDatabase }

    # Normalize port name - handle common variations
    $normalizedPort = $PortName -replace '^\s+|\s+$', ''

    # Search for cable where this device/port is source or destination
    $cable = $db.Cables | Where-Object {
        ($_.SourceDevice -eq $DeviceName -and $_.SourcePort -eq $normalizedPort) -or
        ($_.DestDevice -eq $DeviceName -and $_.DestPort -eq $normalizedPort)
    } | Select-Object -First 1

    if (-not $cable) {
        return $null
    }

    # Determine which end this port represents
    $isSource = ($cable.SourceDevice -eq $DeviceName -and $cable.SourcePort -eq $normalizedPort)

    [PSCustomObject]@{
        CableID      = $cable.CableID
        CableType    = $cable.CableType
        Length       = $cable.Length
        Color        = $cable.Color
        Status       = $cable.Status
        RemoteDevice = if ($isSource) { $cable.DestDevice } else { $cable.SourceDevice }
        RemotePort   = if ($isSource) { $cable.DestPort } else { $cable.SourcePort }
        RemoteType   = if ($isSource) { $cable.DestType } else { $cable.SourceType }
        Notes        = $cable.Notes
        InstallDate  = $cable.InstallDate
        VerifyDate   = $cable.VerifyDate
        FullCable    = $cable
    }
}

<#
.SYNOPSIS
    Gets cable info summary string for display.

.DESCRIPTION
    Returns a short summary string suitable for display in a grid column.

.PARAMETER DeviceName
    The device hostname or name.

.PARAMETER PortName
    The port identifier.

.PARAMETER Database
    Optional external database hashtable.
#>
function Get-CableSummaryForPort {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DeviceName,

        [Parameter(Mandatory = $true)]
        [string]$PortName,

        [Parameter()]
        [hashtable]$Database
    )

    $info = Get-CableForPort -DeviceName $DeviceName -PortName $PortName -Database $Database

    if (-not $info) {
        return ''
    }

    # Format: "CableID -> RemoteDevice:RemotePort (Type)"
    $remote = "$($info.RemoteDevice):$($info.RemotePort)"
    if ($info.RemoteType -eq 'PatchPanel') {
        $remote = "PP:$($info.RemoteDevice)/$($info.RemotePort)"
    }

    return "$($info.CableID) -> $remote"
}

<#
.SYNOPSIS
    Links a cable to a port in Port Reorg context.

.DESCRIPTION
    Creates or updates a cable run to link a device port to a destination.

.PARAMETER DeviceName
    The source device hostname.

.PARAMETER PortName
    The source port identifier.

.PARAMETER DestDevice
    The destination device or patch panel name.

.PARAMETER DestPort
    The destination port identifier.

.PARAMETER DestType
    Type of destination: Device, PatchPanel, WallJack, Other.

.PARAMETER CableType
    Type of cable.

.PARAMETER Database
    Optional external database hashtable.
#>
function Set-CableForPort {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DeviceName,

        [Parameter(Mandatory = $true)]
        [string]$PortName,

        [Parameter(Mandatory = $true)]
        [Alias('DestDevice')]
        [string]$RemoteDevice,

        [Parameter(Mandatory = $true)]
        [Alias('DestPort')]
        [string]$RemotePort,

        [Parameter()]
        [string]$CableID,

        [Parameter()]
        [ValidateSet('Device', 'PatchPanel', 'WallJack', 'Other')]
        [string]$DestType = 'Device',

        [Parameter()]
        [ValidateSet('Cat5e', 'Cat6', 'Cat6a', 'FiberOM3', 'FiberOM4', 'FiberOS2', 'Coax', 'Other')]
        [string]$CableType = 'Cat6',

        [Parameter()]
        [hashtable]$Database
    )

    $db = if ($Database) { $Database } else { $script:CableDatabase }

    # Check if cable already exists for this port
    $existing = Get-CableForPort -DeviceName $DeviceName -PortName $PortName -Database $db

    if ($existing) {
        # Update existing cable (suppress output)
        Update-CableRun -CableID $existing.CableID -Properties @{
            DestDevice = $RemoteDevice
            DestPort   = $RemotePort
            DestType   = $DestType
            CableType  = $CableType
        } -Database $db | Out-Null

        # Return updated info
        return Get-CableForPort -DeviceName $DeviceName -PortName $PortName -Database $db
    }
    else {
        # Create new cable
        $newCableParams = @{
            SourceType   = 'Device'
            SourceDevice = $DeviceName
            SourcePort   = $PortName
            DestType     = $DestType
            DestDevice   = $RemoteDevice
            DestPort     = $RemotePort
            CableType    = $CableType
        }

        if ($CableID) {
            $newCableParams['CableID'] = $CableID
        }

        $cable = New-CableRun @newCableParams
        Add-CableRun -Cable $cable -Database $db | Out-Null

        # Return the created cable info
        return Get-CableForPort -DeviceName $DeviceName -PortName $PortName -Database $db
    }
}

<#
.SYNOPSIS
    Removes cable link from a port.

.PARAMETER DeviceName
    The device hostname.

.PARAMETER PortName
    The port identifier.

.PARAMETER Database
    Optional external database hashtable.
#>
function Remove-CableForPort {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DeviceName,

        [Parameter(Mandatory = $true)]
        [string]$PortName,

        [Parameter()]
        [hashtable]$Database
    )

    $db = if ($Database) { $Database } else { $script:CableDatabase }

    $info = Get-CableForPort -DeviceName $DeviceName -PortName $PortName -Database $db

    if ($info) {
        Remove-CableRun -CableID $info.CableID -Database $db
        return $true
    }

    return $false
}

#endregion

#region Search and Analysis

<#
.SYNOPSIS
    Searches for cable connections involving a specific endpoint.

.PARAMETER Device
    Device name to search for.

.PARAMETER Port
    Port identifier to search for.

.PARAMETER Database
    Optional external database hashtable.
#>
function Find-CableConnection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Device,

        [Parameter()]
        [string]$Port,

        [Parameter()]
        [hashtable]$Database
    )

    $db = if ($Database) { $Database } else { $script:CableDatabase }

    $results = @($db.Cables | Where-Object {
        $matchSource = $_.SourceDevice -eq $Device
        $matchDest = $_.DestDevice -eq $Device

        if ($Port) {
            $matchSource = $matchSource -and $_.SourcePort -eq $Port
            $matchDest = $matchDest -and $_.DestPort -eq $Port
        }

        $matchSource -or $matchDest
    })

    foreach ($cable in $results) {
        $isSource = $cable.SourceDevice -eq $Device
        if ($Port) {
            $isSource = $isSource -and $cable.SourcePort -eq $Port
        }

        [PSCustomObject]@{
            CableID         = $cable.CableID
            Direction       = if ($isSource) { 'Outbound' } else { 'Inbound' }
            LocalPort       = if ($isSource) { $cable.SourcePort } else { $cable.DestPort }
            RemoteDevice    = if ($isSource) { $cable.DestDevice } else { $cable.SourceDevice }
            RemotePort      = if ($isSource) { $cable.DestPort } else { $cable.SourcePort }
            CableType       = $cable.CableType
            Status          = $cable.Status
            Cable           = $cable
        }
    }
}

<#
.SYNOPSIS
    Traces a cable path through patch panels.

.PARAMETER StartDevice
    Starting device name.

.PARAMETER StartPort
    Starting port identifier.

.PARAMETER MaxHops
    Maximum number of hops to trace.

.PARAMETER Database
    Optional external database hashtable.
#>
function Trace-CablePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$StartDevice,

        [Parameter(Mandatory = $true)]
        [string]$StartPort,

        [Parameter()]
        [int]$MaxHops = 10,

        [Parameter()]
        [hashtable]$Database
    )

    $db = if ($Database) { $Database } else { $script:CableDatabase }
    $path = New-Object System.Collections.ArrayList
    $visited = @{}

    $currentDevice = $StartDevice
    $currentPort = $StartPort
    $hop = 0

    while ($hop -lt $MaxHops) {
        $key = "$currentDevice`:$currentPort"
        if ($visited.ContainsKey($key)) {
            # Loop detected
            break
        }
        $visited[$key] = $true

        $connections = @(Find-CableConnection -Device $currentDevice -Port $currentPort -Database $db)
        if ($connections.Count -eq 0) {
            # End of path
            $path.Add([PSCustomObject]@{
                Hop    = $hop
                Device = $currentDevice
                Port   = $currentPort
                Type   = 'Endpoint'
            }) | Out-Null
            break
        }

        $conn = $connections[0]
        $path.Add([PSCustomObject]@{
            Hop         = $hop
            Device      = $currentDevice
            Port        = $currentPort
            CableID     = $conn.CableID
            CableType   = $conn.CableType
            NextDevice  = $conn.RemoteDevice
            NextPort    = $conn.RemotePort
            Type        = 'Connection'
        }) | Out-Null

        # Check if next device is a patch panel
        $panel = $db.PatchPanels | Where-Object {
            $_.PanelName -eq $conn.RemoteDevice -or $_.PanelID -eq $conn.RemoteDevice
        }

        if ($panel) {
            # Look for another cable from this patch panel port
            $currentDevice = $conn.RemoteDevice
            $currentPort = $conn.RemotePort
        }
        else {
            # Reached a device endpoint
            $path.Add([PSCustomObject]@{
                Hop    = $hop + 1
                Device = $conn.RemoteDevice
                Port   = $conn.RemotePort
                Type   = 'Endpoint'
            }) | Out-Null
            break
        }

        $hop++
    }

    $path
}

<#
.SYNOPSIS
    Gets summary statistics for the cable database.

.PARAMETER Database
    Optional external database hashtable.
#>
function Get-CableDatabaseStats {
    [CmdletBinding()]
    param(
        [Parameter()]
        [hashtable]$Database
    )

    $db = if ($Database) { $Database } else { $script:CableDatabase }

    $cables = @($db.Cables)
    $panels = @($db.PatchPanels)

    $statusCounts = @{}
    $typeCounts = @{}

    foreach ($cable in $cables) {
        if (-not $statusCounts[$cable.Status]) { $statusCounts[$cable.Status] = 0 }
        $statusCounts[$cable.Status]++

        if (-not $typeCounts[$cable.CableType]) { $typeCounts[$cable.CableType] = 0 }
        $typeCounts[$cable.CableType]++
    }

    $totalPorts = 0
    $usedPorts = 0
    foreach ($panel in $panels) {
        $totalPorts += $panel.PortCount
        $usedPorts += @($panel.Ports | Where-Object { $_.Status -eq 'Connected' -or $_.CableID }).Count
    }

    [PSCustomObject]@{
        TotalCables       = $cables.Count
        TotalPatchPanels  = $panels.Count
        TotalPanelPorts   = $totalPorts
        UsedPanelPorts    = $usedPorts
        AvailablePorts    = $totalPorts - $usedPorts
        CablesByStatus    = $statusCounts
        CablesByType      = $typeCounts
    }
}

<#
.SYNOPSIS
    Clears the cable database.

.PARAMETER Database
    Optional external database hashtable.
#>
function Clear-CableDatabase {
    [CmdletBinding()]
    param(
        [Parameter()]
        [hashtable]$Database
    )

    $db = if ($Database) { $Database } else { $script:CableDatabase }
    $db.Cables.Clear()
    $db.PatchPanels.Clear()
}

<#
.SYNOPSIS
    Initializes a new empty cable database hashtable.
#>
function New-CableDatabase {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    @{
        Cables      = New-Object System.Collections.ArrayList
        PatchPanels = New-Object System.Collections.ArrayList
    }
}

#endregion

Export-ModuleMember -Function @(
    'New-CableRun'
    'New-PatchPanel'
    'Add-CableRun'
    'Get-CableRun'
    'Update-CableRun'
    'Remove-CableRun'
    'Add-PatchPanel'
    'Get-PatchPanel'
    'Set-PatchPanelPort'
    'Remove-PatchPanel'
    'New-CableLabel'
    'New-PatchPanelLabel'
    'Export-CableLabels'
    'Export-CableDatabase'
    'Import-CableDatabase'
    'Import-CableRunsFromCsv'
    'Find-CableConnection'
    'Trace-CablePath'
    'Get-CableDatabaseStats'
    'Clear-CableDatabase'
    'New-CableDatabase'
    # Port Reorg Integration
    'Get-CableForPort'
    'Get-CableSummaryForPort'
    'Set-CableForPort'
    'Remove-CableForPort'
)
