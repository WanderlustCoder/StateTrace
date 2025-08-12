<#
    .SYNOPSIS
        Combined module providing both the back‑end data functions and
        the user‑interface wiring for the Interfaces tab in the Network
        Reader GUI.

    .DESCRIPTION
        This module merges the functionality previously split between
        InterfaceModule.psm1 and InterfacesViewModule.psm1.  It exposes
        helper functions to query interface summaries, interface details,
        compare interface configurations and build new interface
        configurations, as well as the view initialisation logic used
        by the main window.  Where possible the implementation has been
        simplified to rely solely on the Access database for data rather
        than falling back to legacy CSV files.  Stale code paths and
        duplicate logic have been removed entirely.

        To initialise the Interfaces view, import this module and call
        `Initialize-InterfacesView` from your main script.  The other
        exported functions may be used by other view modules or helper
        scripts as required.

    .EXAMPLE
        Import-Module (Join-Path $scriptDir '..\Modules\InterfaceModule.psm1') -Force
        Initialize-InterfacesView -Window $window -ScriptDir $scriptDir
#>

Set-StrictMode -Version Latest

function Get-DeviceSummaries {
    <#
        .SYNOPSIS
            Return a list of all device hostnames known to the database.

        .DESCRIPTION
            Queries the DeviceSummary table in the StateTrace database and
            returns the Hostname column as a simple string array.  If the
            global database path (`$global:StateTraceDb`) has not been
            initialised, an empty array is returned.  Legacy CSV fallbacks
            have been removed – parsed CSV files are no longer consulted.

        .PARAMETER ParsedDataPath
            Ignored in this implementation.  Retained only for backwards
            compatibility with existing scripts that might still pass it.

        .OUTPUTS
            System.String[]

        .EXAMPLE
            $hosts = Get-DeviceSummaries
    #>
    [CmdletBinding()]
    param([string]$ParsedDataPath)

    if (-not $global:StateTraceDb) {
        # Without a database there is nothing to query; return empty list
        return @()
    }
    try {
        $dbModule = Join-Path $PSScriptRoot 'DatabaseModule.psm1'
        if (Test-Path $dbModule) {
            Import-Module $dbModule -Force -Global -ErrorAction SilentlyContinue | Out-Null
        }
        $dtHosts = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql 'SELECT Hostname FROM DeviceSummary ORDER BY Hostname'
        return ($dtHosts | ForEach-Object { $_.Hostname })
    } catch {
        Write-Warning "Failed to query hostnames from database: $($_.Exception.Message)"
        return @()
    }
}

function Get-InterfaceInfo {
    <#
        .SYNOPSIS
            Retrieves per‑interface details for a given device.

        .DESCRIPTION
            Queries the Interfaces table for all ports belonging to the
            specified hostname.  It then enriches the result with colour
            and compliance information based on the configured vendor
            templates (Cisco or Brocade), which are loaded from JSON files
            in the Templates folder.  If the database is not available or
            the query fails, an empty array is returned.  Legacy CSV
            fallbacks have been removed.

        .PARAMETER Hostname
            The device hostname whose interfaces should be returned.

        .PARAMETER TemplatesPath
            Optional path to the Templates directory.  If omitted, a
            relative path of `..\Templates` from the module location is
            used.

        .OUTPUTS
            PSCustomObject[]
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Hostname,
        [string]$TemplatesPath = (Join-Path $PSScriptRoot '..\Templates')
    )
    if (-not $global:StateTraceDb) { return @() }
    # Debug flag: set $Global:StateTraceDebug = $true in your session to enable verbose debugging
    $debug = ($Global:StateTraceDebug -eq $true)
    try {
        $dbModule = Join-Path $PSScriptRoot 'DatabaseModule.psm1'
        if (Test-Path $dbModule) {
            Import-Module $dbModule -Force -Global -ErrorAction SilentlyContinue | Out-Null
        }
        $escHost = $Hostname -replace "'", "''"
        # Load interface rows
        $sql = "SELECT Port, Name, Status, VLAN, Duplex, Speed, Type, LearnedMACs, AuthState, AuthMode, AuthClientMAC, AuthTemplate, Config, PortColor, ConfigStatus, ToolTip FROM Interfaces WHERE Hostname = '$escHost' ORDER BY Port"
        $dt = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql $sql
        # Determine vendor from device summary
        $vendor = 'Cisco'
        try {
            $mkDt = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql "SELECT Make FROM DeviceSummary WHERE Hostname = '$escHost'"
            if ($mkDt) {
                if ($mkDt -is [System.Data.DataTable]) {
                    if ($mkDt.Rows.Count -gt 0) {
                        $mk = $mkDt.Rows[0].Make
                        if ($mk -match '(?i)brocade') { $vendor = 'Brocade' }
                    }
                } else {
                    $mkRow = $mkDt | Select-Object -First 1
                    if ($mkRow -and $mkRow.PSObject.Properties['Make']) {
                        $mk = $mkRow.Make
                        if ($mk -match '(?i)brocade') { $vendor = 'Brocade' }
                    }
                }
            }
        } catch {}
        # Load device-level AuthBlock from database for Brocade devices.  Append to tooltips later.
        $authBlockLines = @()
        if ($vendor -eq 'Brocade') {
            try {
                $abDt = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql "SELECT AuthBlock FROM DeviceSummary WHERE Hostname = '$escHost'"
                if ($abDt) {
                    $abText = $null
                    if ($abDt -is [System.Data.DataTable]) {
                        if ($abDt.Rows.Count -gt 0) { $abText = '' + $abDt.Rows[0].AuthBlock }
                    } else {
                        $abRow = $abDt | Select-Object -First 1
                        if ($abRow -and $abRow.PSObject.Properties['AuthBlock']) { $abText = '' + $abRow.AuthBlock }
                    }
                    if ($abText -and $abText.Trim() -ne '') {
                        $authBlockLines = $abText -split "`r?`n"
                    }
                }
            } catch {
                if ($debug) { Write-Host "[Get-InterfaceInfo] Failed to load AuthBlock for ${Hostname}: $($_.Exception.Message)" -ForegroundColor Yellow }
            }
        }
        if ($debug) {
            $cnt = 0
            try {
                if ($dt -is [System.Data.DataTable]) { $cnt = $dt.Rows.Count } else { $cnt = @($dt).Count }
            } catch {}
            Write-Host "[Get-InterfaceInfo] Host=$Hostname Vendor=$vendor Rows=$cnt AuthBlockLines=$($authBlockLines.Count)" -ForegroundColor Cyan
            if ($authBlockLines.Count -gt 0) { Write-Host "[Get-InterfaceInfo] AuthBlock first line: $($authBlockLines[0])" -ForegroundColor DarkCyan }
        }

        $vendorFile = if ($vendor -eq 'Cisco') { 'Cisco.json' } else { 'Brocade.json' }
        $jsonFile   = Join-Path $TemplatesPath $vendorFile
        $templates  = $null
        if (Test-Path $jsonFile) {
            $tmplJson = Get-Content $jsonFile -Raw | ConvertFrom-Json
            $templates = $tmplJson.templates
        }
        $results = @()
        foreach ($row in ($dt | Select-Object Port, Name, Status, VLAN, Duplex, Speed, Type, LearnedMACs, AuthState, AuthMode, AuthClientMAC, AuthTemplate, Config, PortColor, ConfigStatus, ToolTip)) {
            $authTemplate = $row.AuthTemplate
            $match = $null
            if ($templates) {
                $match = $templates | Where-Object {
                    $_.name -ieq $authTemplate -or
                    ($_.aliases -and ($_.aliases -contains $authTemplate))
                } | Select-Object -First 1
            }
            $portColor    = if ($row.PortColor) { $row.PortColor } elseif ($match) { $match.color } else { 'Gray' }
            $configStatus = if ($row.ConfigStatus) { $row.ConfigStatus } elseif ($match) { 'Match' } else { 'Mismatch' }
            # Build tooltip and append device-level AuthBlock when appropriate
            $toolTipCore = if ($row.ToolTip) {
                ('' + $row.ToolTip).TrimEnd()
            } else {
                $cfg = '' + $row.Config
                if ($cfg -and $cfg.Trim() -ne '') {
                    "AuthTemplate: $authTemplate`r`n`r`n$cfg"
                } else {
                    "AuthTemplate: $authTemplate"
                }
            }
            $toolTip = $toolTipCore
            if ($vendor -eq 'Brocade' -and $authBlockLines.Count -gt 0 -and ($toolTipCore -notmatch '(?i)GLOBAL AUTH BLOCK')) {
                # Append global auth block without the DB annotation
                $toolTip = $toolTipCore + "`r`n`r`n! GLOBAL AUTH BLOCK`r`n" + ($authBlockLines -join "`r`n")
            }
            if ($debug) {
                $hasCfg = $false
                try { $hasCfg = ($row.Config) -and ((('' + $row.Config).Trim()) -ne '') } catch {}
                $added = ($toolTip -match 'GLOBAL AUTH BLOCK')
                Write-Host ([string]::Format("[Get-InterfaceInfo] Port={0} HasPerPort={1} AddedGlobal={2}", $row.Port, $hasCfg, $added)) -ForegroundColor Gray
            }
            $results += [PSCustomObject]@{
                Hostname      = $Hostname
                Port          = $row.Port
                Name          = $row.Name
                Status        = $row.Status
                VLAN          = $row.VLAN
                Duplex        = $row.Duplex
                Speed         = $row.Speed
                Type          = $row.Type
                LearnedMACs   = $row.LearnedMACs
                AuthState     = $row.AuthState
                AuthMode      = $row.AuthMode
                AuthClientMAC = $row.AuthClientMAC
                ToolTip       = $toolTip
                IsSelected    = $false
                ConfigStatus  = $configStatus
                PortColor     = $portColor
            }
        }
        return $results
    } catch {
        Write-Warning (
            "Failed to load interface information from database for {0}: {1}" -f $Hostname, $_.Exception.Message
        )
        return @()
    }
}

function Compare-InterfaceConfigs {
    <#
        .SYNOPSIS
            Launches a comparison of two interfaces' configurations.

        .DESCRIPTION
            This helper invokes an external PowerShell script (`CompareConfigs.ps1`)
            to produce a side‑by‑side comparison of interface configuration
            differences.  The script is executed in a hidden PowerShell
            process and waits for completion.  No CSV logic is involved.

        .PARAMETER Switch1
            Hostname of the first switch.

        .PARAMETER Interface1
            Port identifier on the first switch.

        .PARAMETER Switch2
            Hostname of the second switch.

        .PARAMETER Interface2
            Port identifier on the second switch.

        .PARAMETER ScriptPath
            Optional path to the CompareConfigs.ps1 script.  By default
            resolves to a ../Main/CompareConfigs.ps1 relative to this
            module's location.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Switch1,
        [Parameter(Mandatory)][string]$Interface1,
        [Parameter(Mandatory)][string]$Switch2,
        [Parameter(Mandatory)][string]$Interface2,
        [string]$ScriptPath = (Join-Path $PSScriptRoot '..\Main\CompareConfigs.ps1')
    )
    if (-not (Test-Path $ScriptPath)) {
        throw "Compare script not found: $ScriptPath"
    }
    Start-Process -FilePath 'powershell.exe' -ArgumentList @(
        '-NoProfile','-WindowStyle','Hidden',
        '-File', $ScriptPath,
        '-Switch1',$Switch1,'-Interface1',$Interface1,
        '-Switch2',$Switch2,'-Interface2',$Interface2
    ) -Wait -NoNewWindow
}

function Get-InterfaceConfiguration {
    <#
        .SYNOPSIS
            Builds port configuration snippets based on a selected template.

        .DESCRIPTION
            Given a hostname, a list of port identifiers and a template name,
            this function constructs a set of configuration commands to
            apply the template to each port.  It queries existing
            configurations from the database in order to remove obsolete
            authentication commands.  Name and VLAN overrides can be
            supplied via hashtables.  Legacy CSV fallbacks have been
            removed; when the database is unavailable, an empty array is
            returned.

        .PARAMETER Hostname
            The device hostname.

        .PARAMETER Interfaces
            An array of port identifiers to which the template should be applied.

        .PARAMETER TemplateName
            The name of the template to apply.

        .PARAMETER NewNames
            A hashtable mapping ports to new descriptive names.  Optional.

        .PARAMETER NewVlans
            A hashtable mapping ports to new VLAN identifiers.  Optional.

        .PARAMETER TemplatesPath
            Optional path to the Templates directory.  Defaults to ../Templates
            relative to this module.  Used to load Cisco/Brocade template
            JSON files.

        .OUTPUTS
            System.String[]  – an array of configuration lines.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]  $Hostname,
        [Parameter(Mandatory)][string[]]$Interfaces,
        [Parameter(Mandatory)][string]  $TemplateName,
        [hashtable]$NewNames,
        [hashtable]$NewVlans,
        [string]$TemplatesPath = (Join-Path $PSScriptRoot '..\Templates')
    )
    if (-not $global:StateTraceDb) { return @() }
    # Debug flag: set $Global:StateTraceDebug = $true in your session to enable verbose debugging
    $debug = ($Global:StateTraceDebug -eq $true)
    try {
        $dbModule = Join-Path $PSScriptRoot 'DatabaseModule.psm1'
        if (Test-Path $dbModule) {
            Import-Module $dbModule -Force -Global -ErrorAction SilentlyContinue | Out-Null
        }
        $escHost = $Hostname -replace "'", "''"
        # Determine vendor
        $vendor = 'Cisco'
        try {
            $mkDt = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql "SELECT Make FROM DeviceSummary WHERE Hostname = '$escHost'"
            if ($mkDt) {
                if ($mkDt -is [System.Data.DataTable]) {
                    if ($mkDt.Rows.Count -gt 0) {
                        $mk = $mkDt.Rows[0].Make
                        if ($mk -match '(?i)brocade') { $vendor = 'Brocade' }
                    }
                } else {
                    $mkRow = $mkDt | Select-Object -First 1
                    if ($mkRow -and $mkRow.PSObject.Properties['Make']) {
                        $mk = $mkRow.Make
                        if ($mk -match '(?i)brocade') { $vendor = 'Brocade' }
                    }
                }
            }
        } catch {}
        $jsonFile = Join-Path $TemplatesPath "${vendor}.json"
        if (-not (Test-Path $jsonFile)) { throw "Template file missing: $jsonFile" }
        $templates = (Get-Content $jsonFile -Raw | ConvertFrom-Json).templates
        $tmpl = $templates | Where-Object { $_.name -eq $TemplateName } | Select-Object -First 1
        if (-not $tmpl) { throw "Template '$TemplateName' not found in ${vendor}.json" }
        # Load existing config per port
        $oldConfigs = @{}
        foreach ($p in $Interfaces) {
            $pEsc = $p -replace "'", "''"
            $sqlCfg = "SELECT Config FROM Interfaces WHERE Hostname = '$escHost' AND Port = '$pEsc'"
            $dtCfg  = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql $sqlCfg
            if ($dtCfg) {
                if ($dtCfg -is [System.Data.DataTable]) {
                    if ($dtCfg.Rows.Count -gt 0) {
                        $cfgText = $dtCfg.Rows[0].Config
                        $oldConfigs[$p] = if ($cfgText) { $cfgText -split "`n" } else { @() }
                    }
                } else {
                    $rowCfg = $dtCfg | Select-Object -First 1
                    if ($rowCfg -and $rowCfg.PSObject.Properties['Config']) {
                        $cfgText = $rowCfg.Config
                        $oldConfigs[$p] = if ($cfgText) { $cfgText -split "`n" } else { @() }
                    }
                }
            }
        }
        $outLines = foreach ($port in $Interfaces) {
            "interface $port"
            $pending = @()
            $nameOverride = if ($NewNames.ContainsKey($port)) { $NewNames[$port] } else { $null }
            $vlanOverride = if ($NewVlans.ContainsKey($port)) { $NewVlans[$port] } else { $null }
            if ($nameOverride) {
                $pending += $(if ($vendor -eq 'Cisco') { "description $nameOverride" } else { "port-name $nameOverride" })
            }
            if ($vlanOverride) {
                $pending += $(if ($vendor -eq 'Cisco') { "switchport access vlan $vlanOverride" } else { "auth-default-vlan $vlanOverride" })
            }
            foreach ($cmd in $tmpl.required_commands) { $pending += $cmd.Trim() }
            if ($oldConfigs.ContainsKey($port)) {
                foreach ($oldLine in $oldConfigs[$port]) {
                    $trimOld  = $oldLine.Trim()
                    if (-not $trimOld) { continue }
                    $lowerOld = $trimOld.ToLower()
                    if ($lowerOld.StartsWith('interface') -or $lowerOld -eq 'exit') { continue }
                    $existsInNew = $false
                    foreach ($newCmd in $pending) {
                        if ($lowerOld -like ("$($newCmd.ToLower())*")) { $existsInNew = $true; break }
                    }
                    if ($existsInNew) { continue }
                    # Remove stale auth commands
                    if ($vendor -eq 'Cisco') {
                        if ($lowerOld.StartsWith('authentication') -or $lowerOld.StartsWith('dot1x') -or $lowerOld -eq 'mab') {
                            " no $trimOld"
                        }
                    } else {
                        if ($lowerOld -match 'dot1x\s+port-control\s+auto' -or $lowerOld -match 'mac-authentication\s+enable') {
                            " no $trimOld"
                        }
                    }
                }
            }
            # Append overrides and template commands again for readability
            if ($nameOverride) {
                $(if ($vendor -eq 'Cisco') { " description $nameOverride" } else { " port-name $nameOverride" })
            }
            if ($vlanOverride) {
                $(if ($vendor -eq 'Cisco') { " switchport access vlan $vlanOverride" } else { " auth-default-vlan $vlanOverride" })
            }
            foreach ($cmd in $tmpl.required_commands) { $cmd }
            'exit'
            ''
        }
        return $outLines
    } catch {
        Write-Warning (
            "Failed to build interface configuration from database for {0}: {1}" -f $Hostname, $_.Exception.Message
        )
        return @()
    }
}

function Get-SpanningTreeInfo {
    <#
        .SYNOPSIS
            Retrieves spanning tree information for a device.

        .DESCRIPTION
            This function reads a CSV file named `<Hostname>_Span.csv` from
            the ParsedData directory and returns its contents as an array of
            objects.  At present the database does not store spanning tree
            data, so the CSV remains the sole source of information.  If the
            file does not exist or cannot be parsed, an empty array is
            returned.

        .PARAMETER Hostname
            The device hostname whose spanning tree data should be loaded.

        .PARAMETER ParsedDataPath
            Optional path to the ParsedData directory.  Defaults to
            `..\ParsedData` relative to this module.

        .OUTPUTS
            PSCustomObject[]
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Hostname,
        [string]$ParsedDataPath = (Join-Path $PSScriptRoot '..\ParsedData')
    )
    $spanFile = Join-Path $ParsedDataPath "${Hostname}_Span.csv"
    if (Test-Path $spanFile) {
        try {
            return Import-Csv $spanFile
        } catch {
            # Use formatted string expansion to avoid variable parsing issues with colon
            Write-Warning (
                "Failed to parse spanning tree CSV for {0}: {1}" -f $Hostname, $_.Exception.Message
            )
            return @()
        }
    }
    return @()
}

function Get-ConfigurationTemplates {
    <#
        .SYNOPSIS
            Returns a list of available configuration template names for a device.

        .DESCRIPTION
            Determines the vendor of the specified device by querying the
            DeviceSummary table, then loads the corresponding template JSON
            (Cisco.json or Brocade.json) from the Templates directory and
            returns the names of all templates.  Legacy CSV fallbacks have
            been removed.  If the database is unavailable or the JSON file
            cannot be loaded, an empty array is returned.

        .PARAMETER Hostname
            The device hostname.

        .PARAMETER TemplatesPath
            Optional path to the Templates directory.  Defaults to
            `..\Templates` relative to this module.

        .OUTPUTS
            System.String[]
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Hostname,
        [string]$TemplatesPath = (Join-Path $PSScriptRoot '..\Templates')
    )
    if (-not $global:StateTraceDb) { return @() }
    try {
        $dbModulePath = Join-Path $PSScriptRoot 'DatabaseModule.psm1'
        if (Test-Path $dbModulePath) {
            Import-Module $dbModulePath -Force -Global -ErrorAction SilentlyContinue | Out-Null
        }
        $escHost = $Hostname -replace "'", "''"
        $dt = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql "SELECT Make FROM DeviceSummary WHERE Hostname = '$escHost'"
        # Determine the device make.  Invoke-DbQuery may return a DataTable or an array of objects.
        $make = ''
        if ($dt) {
            # If a DataTable is returned, use its Rows collection
            if ($dt -is [System.Data.DataTable]) {
                if ($dt.Rows.Count -gt 0) { $make = $dt.Rows[0].Make }
            } else {
                # Otherwise, treat it as an enumerable and grab the first object
                $firstRow = $dt | Select-Object -First 1
                if ($firstRow -and $firstRow.PSObject.Properties['Make']) {
                    $make = $firstRow.Make
                }
            }
        }
        $vendorFile = if ($make -match '(?i)brocade') { 'Brocade.json' } else { 'Cisco.json' }
        $jsonFile = Join-Path $TemplatesPath $vendorFile
        if (-not (Test-Path $jsonFile)) { throw "Template file missing: $jsonFile" }
        $templates = (Get-Content $jsonFile -Raw | ConvertFrom-Json).templates
        return $templates | Select-Object -ExpandProperty name
    } catch {
        Write-Warning (
            "Failed to determine configuration templates from database for {0}: {1}" -f $Hostname, $_.Exception.Message
        )
        return @()
    }
}

function New-InterfacesView {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [System.Windows.Window]$Window,
        [Parameter(Mandatory=$true)]
        [string]$ScriptDir
    )

    # Load InterfacesView.xaml
    $interfacesViewXamlPath = Join-Path $ScriptDir '..\Views\InterfacesView.xaml'
    if (-not (Test-Path $interfacesViewXamlPath)) {
        Write-Warning "Missing InterfacesView.xaml at $interfacesViewXamlPath"
        return
    }
    $ifaceXaml   = Get-Content $interfacesViewXamlPath -Raw
    $ifaceReader = New-Object System.Xml.XmlTextReader (New-Object System.IO.StringReader($ifaceXaml))
    $interfacesView = [Windows.Markup.XamlReader]::Load($ifaceReader)

    # Mount view
    $interfacesHost = $Window.FindName('InterfacesHost')
    if ($interfacesHost -is [System.Windows.Controls.ContentControl]) {
        $interfacesHost.Content = $interfacesView
    } else {
        Write-Warning "Could not find ContentControl 'InterfacesHost'"
    }

    # Grab controls
    $compareButton     = $interfacesView.FindName('CompareButton')
    $interfacesGrid    = $interfacesView.FindName('InterfacesGrid')
    $configureButton   = $interfacesView.FindName('ConfigureButton')
    $templateDropdown  = $interfacesView.FindName('ConfigOptionsDropdown')
    $filterBox         = $interfacesView.FindName('FilterBox')
    $clearBtn          = $interfacesView.FindName('ClearFilterButton')
    $copyDetailsButton = $interfacesView.FindName('CopyDetailsButton')

    #
    # Promote frequently used controls to the global scope.  When this function
    # completes, its local variables go out of scope and any scriptblocks
    # attached to UI events will no longer be able to access them.  Assigning
    # the controls to global variables ensures they remain available when
    # invoked later (for example, by the Copy Details button or filter box
    # handlers).  See FurtherFixes.docx step 1 for details.
    #
    if ($interfacesGrid)    { $global:interfacesGrid   = $interfacesGrid }
    if ($templateDropdown)  { $global:templateDropdown = $templateDropdown }
    if ($filterBox)         { $global:filterBox        = $filterBox }

    # ------------------------------
    # Compare button
    if ($compareButton) {
        $compareButton.Add_Click({
        # Prefer globally-scoped grid if we promoted it; fall back to find by name
        $grid = $global:interfacesGrid
        if (-not $grid) { $grid = $interfacesView.FindName('InterfacesGrid') }
        if (-not $grid) {
            [System.Windows.MessageBox]::Show("Interfaces grid not found.")
            return
        }

        # Commit any pending edits before we read selections
        [void]$grid.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Cell, $true)
        [void]$grid.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Row,  $true)

        # 1) Rows explicitly highlighted/selected in the grid
        $selectedRows = @($grid.SelectedItems)

        # 2) Rows checked via the checkbox column (robust to items w/o IsSelected)
        $itemsEnum = @()
        if ($grid.ItemsSource -is [System.Collections.IEnumerable]) {
            $itemsEnum = @($grid.ItemsSource)
        }
        $checkedRows = @()
        foreach ($item in $itemsEnum) {
            $prop = $item.PSObject.Properties['IsSelected']  # safe under StrictMode
            if ($prop -and $prop.Value) {
                $checkedRows += $item
            }
        }

        # Prefer checked boxes; fall back to selected rows
        if     ($checkedRows.Count  -eq 2) { $int1,$int2 = $checkedRows }
        elseif ($selectedRows.Count -eq 2) { $int1,$int2 = $selectedRows }
        else {
            [System.Windows.MessageBox]::Show("Select (or check) exactly two interfaces to compare.")
            return
        }

        # Validate we have needed fields
        foreach ($int in @($int1,$int2)) {
            foreach ($req in 'Hostname','Port') {
                if (-not $int.PSObject.Properties[$req]) {
                    [System.Windows.MessageBox]::Show("Selected items are missing '$req'.")
                    return
                }
            }
        }

        try {
            Update-CompareView -Switch1 $int1.Hostname -Interface1 $int1.Port `
                               -Switch2 $int2.Hostname -Interface2 $int2.Port `
                               -Row1 $int1 -Row2 $int2


            # Expand compare sidebar if collapsed
            $col = $Window.FindName('CompareColumn')
            if ($col -is [System.Windows.Controls.ColumnDefinition]) {
                if ($col.Width.Value -eq 0) { $col.Width = [System.Windows.GridLength]::new(400) }
            }
        } catch {
            [System.Windows.MessageBox]::Show("Compare failed:`n$($_.Exception.Message)")
        }
    })

    }

    if ($interfacesGrid) {
        # With SelectionUnit="CellOrRowHeader" and a two-way checkbox binding defined in the XAML, DataGrid checkboxes
        # update the IsSelected property immediately on click without any code-behind.  Therefore we no longer attach
        # preview click handlers or extra Checked/Unchecked handlers here.
    }

    # ------------------------------
    # Configure button (unchanged)
    if ($configureButton -and $interfacesGrid -and $templateDropdown) {
        $configureButton.Add_Click({
            # Use globally scoped grid and dropdown to avoid out-of-scope errors
            $selected = @($global:interfacesGrid.SelectedItems)
            if (-not $selected -or $selected.Count -eq 0) {
                [System.Windows.MessageBox]::Show("No interfaces selected.")
                return
            }
            $template = $global:templateDropdown.SelectedItem
            if (-not $template) {
                [System.Windows.MessageBox]::Show("No template selected.")
                return
            }
            $hostname = $interfacesView.FindName('HostnameBox').Text
            try {
                $namesMap = @{}
                $vlansMap = @{}
                foreach ($int in $selected) {
                    if ($int.Name -and $int.Name -ne '') { $namesMap[$int.Port] = $int.Name }
                    if ($int.VLAN -and $int.VLAN -ne '') { $vlansMap[$int.Port] = $int.VLAN }
                }
                $ports = $selected | ForEach-Object { $_.Port }
                $lines = Get-InterfaceConfiguration -Hostname $hostname -Interfaces $ports -TemplateName $template -NewNames $namesMap -NewVlans $vlansMap
                Set-Clipboard -Value ($lines -join "`r`n")
                [System.Windows.MessageBox]::Show(($lines -join "`n"), "Generated Config")
            } catch {
                [System.Windows.MessageBox]::Show("Failed to build config:`n$($_.Exception.Message)")
            }
        })
    }

    # ------------------------------
    # Filter box
    if ($clearBtn -and $filterBox) {
        $clearBtn.Add_Click({
            # Access filter box via global scope to avoid missing variable errors
            $global:filterBox.Text  = ""
            $global:filterBox.Focus()
        })
    }
    if ($filterBox -and $interfacesGrid) {
        $filterBox.Add_TextChanged({
            # Capture text from globally scoped filter box
            $text = $global:filterBox.Text.ToLower()
            $view = [System.Windows.Data.CollectionViewSource]::GetDefaultView($global:interfacesGrid.ItemsSource)
            if ($null -eq $view) { return }
            $view.Filter = {
                param($item)
                return (
                    ($item.Port      -as [string]).ToLower().Contains($text) -or
                    ($item.Name      -as [string]).ToLower().Contains($text) -or
                    ($item.Status    -as [string]).ToLower().Contains($text) -or
                    ($item.VLAN      -as [string]).ToLower().Contains($text) -or
                    ($item.AuthState -as [string]).ToLower().Contains($text)
                )
            }
            $view.Refresh()
        })
    }

    # ------------------------------
    # Copy Details button
    if ($copyDetailsButton -and $interfacesGrid) {
        $copyDetailsButton.Add_Click({
            # Use global interfaces grid to read selected items
            $selected = @($global:interfacesGrid.SelectedItems)
            if (-not $selected -or $selected.Count -eq 0) {
                [System.Windows.MessageBox]::Show("No interfaces selected.")
                return
            }
            $hostname = $interfacesView.FindName('HostnameBox').Text
            $header = @("Hostname: $hostname", "------------------------------", "")
            $output = foreach ($int in $selected) {
                @(
                    "Port:        $($int.Port)",
                    "Name:        $($int.Name)",
                    "Status:      $($int.Status)",
                    "VLAN:        $($int.VLAN)",
                    "Duplex:      $($int.Duplex)",
                    "Speed:       $($int.Speed)",
                    "Type:        $($int.Type)",
                    "LearnedMACs: $($int.LearnedMACs)",
                    "AuthState:   $($int.AuthState)",
                    "AuthMode:    $($int.AuthMode)",
                    "Client MAC:  $($int.AuthClientMAC)",
                    "Config:",
                    "$($int.ToolTip)",
                    "------------------------------"
                ) -join "`r`n"
            }
            $final = $header + $output
            Set-Clipboard -Value ($final -join "`r`n")
            [System.Windows.MessageBox]::Show("Copied $($selected.Count) interface(s) to clipboard.")
        })
    }

    # ------------------------------
    # Template dropdown color hint
    # Use global scope to ensure the control remains available when this event fires.
    if ($templateDropdown) {
        $templateDropdown.Add_SelectionChanged({
            $sel = $global:templateDropdown.SelectedItem
            $brush = [System.Windows.Media.Brushes]::Black
            if ($sel) {
                $lower = ('' + $sel).ToLower()
                if     ($lower -match 'cisco')   { $brush = [System.Windows.Media.Brushes]::DodgerBlue }
                elseif ($lower -match 'brocade') { $brush = [System.Windows.Media.Brushes]::Goldenrod }
                elseif ($lower -match 'arista')  { $brush = [System.Windows.Media.Brushes]::MediumSeaGreen }
            }
            $global:templateDropdown.Foreground = $brush
        })
    }

    $global:interfacesView = $interfacesView
}

Export-ModuleMember -Function Get-DeviceSummaries,Get-InterfaceInfo,Compare-InterfaceConfigs,Get-InterfaceConfiguration,Get-ConfigurationTemplates,Get-SpanningTreeInfo,New-InterfacesView
