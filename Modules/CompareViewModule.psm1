# CompareViewModule.psm1
# Loads the Compare sidebar, populates switch/port lists, and renders side-by-side config + diffs.

# Script-scoped references to live view controls (re-initialized each view load)
$script:windowRef         = $null
$script:compareView       = $null
$script:switch1Dropdown   = $null
$script:port1Dropdown     = $null
$script:switch2Dropdown   = $null
$script:port2Dropdown     = $null
$script:config1Box        = $null
$script:config2Box        = $null
$script:diff1Box          = $null
$script:diff2Box          = $null
$script:auth1Text         = $null
$script:auth2Text         = $null
$script:lastWiredViewId   = 0
$script:closeWiredViewId  = 0
$script:compareHostCtl    = $null
$script:LastCompareHostList = $null

$script:lastCompareColors       = @{}
$script:CompareThemeHandlerRegistered = $false
if ($null -eq $Global:StateTraceDebug) { $Global:StateTraceDebug = $false }
if ($Global:StateTraceDebug) { $VerbosePreference = 'Continue' }

function Resolve-CompareControls {
    if (-not $script:compareView) { return $false }
    # Find and bind all the named controls from the loaded XAML view
    $script:switch1Dropdown = $script:compareView.FindName('Switch1Dropdown')
    $script:port1Dropdown   = $script:compareView.FindName('Port1Dropdown')
    $script:switch2Dropdown = $script:compareView.FindName('Switch2Dropdown')
    $script:port2Dropdown   = $script:compareView.FindName('Port2Dropdown')
    $script:config1Box      = $script:compareView.FindName('Config1Box')
    $script:config2Box      = $script:compareView.FindName('Config2Box')
    $script:diff1Box        = $script:compareView.FindName('Diff1Box')
    $script:diff2Box        = $script:compareView.FindName('Diff2Box')
    $script:auth1Text       = $script:compareView.FindName('AuthTemplate1Text')
    $script:auth2Text       = $script:compareView.FindName('AuthTemplate2Text')

    return ($script:switch1Dropdown -and $script:port1Dropdown -and 
            $script:switch2Dropdown -and $script:port2Dropdown)
}

function Get-HostString {
    param($Item)
    # Returns a string hostname given an item which might be a complex object
    if ($null -eq $Item) { return '' }
    if ($Item -is [string])                        { return $Item }
    if ($Item.PSObject -and $Item.PSObject.Properties['Hostname']) { return [string]$Item.Hostname }
    if ($Item.PSObject -and $Item.PSObject.Properties['HostName']) { return [string]$Item.HostName }
    if ($Item.PSObject -and $Item.PSObject.Properties['Name'])     { return [string]$Item.Name }
    return ('' + $Item)
}

function Get-HostsFromMain {
    [CmdletBinding()]
    param(
        [System.Windows.Window]$Window
    )
    $siteSel = $null
    $zoneSel = $null
    $bldSel  = $null
    $roomSel = $null
    try {
        $lastLoc = $null
        try { $lastLoc = FilterStateModule\Get-LastLocation } catch { }
        if ($lastLoc) {
            $siteSel = $lastLoc.Site
            $zoneSel = $lastLoc.Zone
            $bldSel  = $lastLoc.Building
            $roomSel = $lastLoc.Room
        }
        if ([string]::IsNullOrWhiteSpace($siteSel)) {
            try {
                $locSel = FilterStateModule\Get-SelectedLocation -Window $Window
                if ($locSel) {
                    if ($locSel.Site)     { $siteSel = $locSel.Site }
                    if ($locSel.Zone)     { $zoneSel = $locSel.Zone }
                    if ($locSel.Building) { $bldSel  = $locSel.Building }
                    if ($locSel.Room)     { $roomSel = $locSel.Room }
                }
            } catch { }
        }
    } catch { }
    $metadata = $null
    try { $metadata = $global:DeviceMetadata } catch { }
    $hostSet  = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $hostList = New-Object 'System.Collections.Generic.List[string]'
    $snapshot = $null
    try {
        $snapshot = ViewStateService\Get-FilterSnapshot -DeviceMetadata $metadata -Site $siteSel -ZoneSelection $zoneSel -Building $bldSel -Room $roomSel
    } catch {
        Write-Verbose "[CompareView] ViewStateService snapshot failed: $($_.Exception.Message)"
    }
    if ($snapshot -and $snapshot.Hostnames) {
        foreach ($candidate in $snapshot.Hostnames) {
            $name = ('' + $candidate).Trim()
            if ($name -and $hostSet.Add($name)) { [void]$hostList.Add($name) }
        }
    }
    $zoneToLoad = ''
    if ($zoneSel -and -not [string]::IsNullOrWhiteSpace($zoneSel) -and -not [System.StringComparer]::OrdinalIgnoreCase.Equals($zoneSel, 'All Zones')) {
        $zoneToLoad = $zoneSel
    } elseif ($snapshot -and $snapshot.ZoneToLoad) {
        $zoneToLoad = '' + $snapshot.ZoneToLoad
    }
    try {
        $interfaces = ViewStateService\Get-InterfacesForContext -Site $siteSel -ZoneSelection $zoneSel -ZoneToLoad $zoneToLoad -Building $bldSel -Room $roomSel
        if ($interfaces) {
            foreach ($row in $interfaces) {
                if (-not $row) { continue }
                $hostname = ''
                try {
                    if ($row.PSObject.Properties['Hostname']) { $hostname = '' + $row.Hostname }
                    elseif ($row.PSObject.Properties['HostName']) { $hostname = '' + $row.HostName }
                } catch { $hostname = '' }
                if ([string]::IsNullOrWhiteSpace($hostname)) { $hostname = '' + $row }
                $hostname = $hostname.Trim()
                if ($hostname -and $hostSet.Add($hostname)) { [void]$hostList.Add($hostname) }
            }
        }
    } catch {
        Write-Verbose "[CompareView] ViewStateService interfaces retrieval failed: $($_.Exception.Message)"
    }
    if ($hostList.Count -eq 0 -and $metadata) {
        foreach ($entry in $metadata.GetEnumerator()) {
            $hostname = ('' + $entry.Key).Trim()
            if ([string]::IsNullOrWhiteSpace($hostname)) { continue }
            $meta = $entry.Value
            if ($siteSel -and -not [string]::IsNullOrWhiteSpace($siteSel) -and -not [System.StringComparer]::OrdinalIgnoreCase.Equals($siteSel, 'All Sites')) {
                $siteVal = ''
                if ($meta -and $meta.PSObject.Properties['Site']) { $siteVal = '' + $meta.Site }
                if (-not [System.StringComparer]::OrdinalIgnoreCase.Equals($siteVal, $siteSel)) { continue }
            }
            if ($zoneSel -and -not [string]::IsNullOrWhiteSpace($zoneSel) -and -not [System.StringComparer]::OrdinalIgnoreCase.Equals($zoneSel, 'All Zones')) {
                $zoneVal = ''
                if ($meta -and $meta.PSObject.Properties['Zone']) { $zoneVal = '' + $meta.Zone }
                if (-not [System.StringComparer]::OrdinalIgnoreCase.Equals($zoneVal, $zoneSel)) { continue }
            }
            if ($bldSel -and -not [string]::IsNullOrWhiteSpace($bldSel) -and $meta -and $meta.PSObject.Properties['Building']) {
                if (-not [System.StringComparer]::OrdinalIgnoreCase.Equals(('' + $meta.Building), $bldSel)) { continue }
            }
            if ($roomSel -and -not [string]::IsNullOrWhiteSpace($roomSel) -and $meta -and $meta.PSObject.Properties['Room']) {
                if (-not [System.StringComparer]::OrdinalIgnoreCase.Equals(('' + $meta.Room), $roomSel)) { continue }
            }
            if ($hostSet.Add($hostname)) { [void]$hostList.Add($hostname) }
        }
    }
    if ($hostList.Count -gt 1) {
        $hostList.Sort([System.StringComparer]::OrdinalIgnoreCase)
    }
    try {
        $siteDbg = '' + $siteSel
        $zoneDbg = '' + $zoneSel
        $bldDbg  = '' + $bldSel
        $roomDbg = '' + $roomSel
        $hCount  = $hostList.Count
        $hSample = ''
        if ($hCount -gt 0) {
            $sampleItems = $hostList.ToArray() | Select-Object -First ([System.Math]::Min(5, $hCount))
            $hSample = ($sampleItems -join ', ')
        }
        $msg = "CompareHostFilter | site='{0}', zone='{1}', building='{2}', room='{3}', count={4}, sample=[{5}]" -f $siteDbg, $zoneDbg, $bldDbg, $roomDbg, $hCount, $hSample
        if (Get-Command -Name Write-Diag -ErrorAction SilentlyContinue) {
            Write-Diag $msg
        } else {
            Write-Verbose $msg
        }
    } catch { }
    return ,$hostList.ToArray()
}

function Get-PortSortKey {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Port)
    # Delegate to InterfaceModule::Get-PortSortKey to keep the ordering logic centralised.
    return InterfaceModule\Get-PortSortKey @PSBoundParameters
}

function Get-PortsForHost {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Hostname)

    # Fetch all interface names for the given host from the database.  This revised
    Write-Verbose "[CompareView] Fetching ports for host '$Hostname'..."
    # Use typed lists to accumulate and normalise port names.  Avoid
    $portsList = New-Object 'System.Collections.Generic.List[string]'
    try {
        if (Get-Command -Name 'Get-InterfaceList' -ErrorAction SilentlyContinue) {
            $list = @(InterfaceModule\Get-InterfaceList -Hostname $Hostname)
            if ($list -and $list.Count -gt 0) {
                foreach ($it in $list) {
                    [void]$portsList.Add(('' + $it))
                }
                Write-Verbose "[CompareView] Get-InterfaceList returned $($portsList.Count) port(s) for '$Hostname'."
            }
        }
    } catch {
        Write-Warning "[CompareView] Error calling Get-InterfaceList for '$Hostname': $($_.Exception.Message)"
    }
    if ($portsList.Count -eq 0) {
        try {
            if (Get-Command -Name 'Get-InterfaceInfo' -ErrorAction SilentlyContinue) {
                $info = @(InterfaceModule\Get-InterfaceInfo -Hostname $Hostname)
                if ($info -and $info.Count -gt 0) {
                    foreach ($r in $info) {
                        $val = $null
                        if     ($r -is [string])                                { $val = '' + $r }
                        elseif ($r.PSObject.Properties['Port'])                 { $val = '' + $r.Port }
                        elseif ($r.PSObject.Properties['Interface'])            { $val = '' + $r.Interface }
                        elseif ($r.PSObject.Properties['IfName'])               { $val = '' + $r.IfName }
                        elseif ($r.PSObject.Properties['Name'])                 { $val = '' + $r.Name }
                        else                                                    { $val = '' + $r }
                        if ($val) { [void]$portsList.Add($val) }
                    }
                    Write-Verbose "[CompareView] Get-InterfaceInfo returned $($portsList.Count) port(s) for '$Hostname'."
                }
            }
        } catch {
            Write-Warning "[CompareView] Error calling Get-InterfaceInfo for '$Hostname': $($_.Exception.Message)"
        }
    }
    # Normalise, deduplicate and sort using a HashSet and typed list.  Use a
    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $finalList = New-Object 'System.Collections.Generic.List[string]'
    foreach ($p in $portsList) {
        $t = ('' + $p).Trim()
        if ($t -and $t -ne '' -and $set.Add($t)) {
            [void]$finalList.Add($t)
        }
    }
    # Define a comparison delegate that uses the port sort key for ordering
    $comp = [System.Comparison[string]]{
        param($a,$b)
        $k1 = InterfaceModule\Get-PortSortKey -Port $a
        $k2 = InterfaceModule\Get-PortSortKey -Port $b
        return [System.StringComparer]::OrdinalIgnoreCase.Compare($k1, $k2)
    }
    $finalList.Sort($comp)
    Write-Verbose "[CompareView] Final port list for '$Hostname': $($finalList.Count) port(s)."
    return ,$finalList.ToArray()
}

function Set-PortsForCombo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Windows.Controls.ComboBox]$Combo,
        [Parameter(Mandatory)][string]$Hostname
    )
    # Populates the given ComboBox with the list of ports for the specified Hostname.
    if ([string]::IsNullOrWhiteSpace($Hostname)) {
        # No host specified - clear the combo box
        $Combo.ItemsSource = @()
        try { $Combo.Items.Refresh() } catch { }
        $Combo.SelectedIndex = -1
        Write-Verbose "[CompareView] Cleared ports list because hostname was empty or null."
        return
    }

    # Retrieve ports for the host
    $ports = Get-PortsForHost -Hostname $Hostname

    # Update the ComboBox with the retrieved ports list
    [System.Windows.Controls.TextSearch]::SetTextPath($Combo, $null)    # ensure we treat items as plain strings
    try { $Combo.ItemTemplate = $null } catch { }
    try { $Combo.DisplayMemberPath = $null } catch { }
    $Combo.ItemsSource = $null
    $Combo.Items.Clear()
    $Combo.ItemsSource = $ports
    try { $Combo.Items.Refresh() } catch { }

    # Select the first port by default (or clear selection if none)
    if ($ports.Count -gt 0) {
        $Combo.SelectedIndex = 0
        Write-Verbose "[CompareView] Populated ports for '$Hostname' (Count=$($ports.Count)). Auto-selected first port: '$($Combo.SelectedItem)'."
    }
    else {
        $Combo.SelectedIndex = -1
        Write-Warning "[CompareView] No ports found for '$Hostname'. Port list is empty."
    }
}

function Get-GridRowFor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Hostname, 
        [Parameter(Mandatory)][string]$Port
    )
    # Find the data object (row) for the given Hostname and Port by querying the
    try {
        if (Get-Command -Name 'Get-InterfaceInfo' -ErrorAction SilentlyContinue) {
            # Retrieve all interface objects for the specified host
            $ifaceList = InterfaceModule\Get-InterfaceInfo -Hostname $Hostname
            if ($ifaceList) {
                # Normalize the requested port by trimming and uppercasing for comparison
                $tgt = ('' + $Port).Trim().ToUpperInvariant()
                foreach ($iface in $ifaceList) {
                    # Determine the interface's port identifier.  Different data sources
                    # may expose the port name under different property names (Port,
                    # Interface, IfName, Name).  Fall back to the object's string
                    # representation when no explicit property is available.  This
                    # improves robustness when comparing ports from heterogeneous sources.
                    $pVal = $null
                    try {
                        if ($iface.PSObject.Properties['Port'])          { $pVal = '' + $iface.Port }
                        elseif ($iface.PSObject.Properties['Interface']) { $pVal = '' + $iface.Interface }
                        elseif ($iface.PSObject.Properties['IfName'])    { $pVal = '' + $iface.IfName }
                        elseif ($iface.PSObject.Properties['Name'])      { $pVal = '' + $iface.Name }
                    } catch {}
                    if (-not $pVal) { $pVal = '' + $iface }
                    $p = ('' + $pVal).Trim().ToUpperInvariant()
                    if ($p -eq $tgt) {
                        return $iface
                    }
                }
            }
        }
    } catch {
        Write-Verbose "[CompareView] Exception in Get-GridRowFor DB lookup: $($_.Exception.Message)"
    }
    return $null
}

function Get-AuthTemplateFromTooltip {
    param([string]$Text)
    if (-not $Text) { return '' }
    # Match a variety of prefixes including "AuthTemplate", "auth template",
    $pattern = '(?im)^\s*(?:auth(?:entication)?\s*template|authtemplate|template)\s*:?' +
               '\s*"?(?<name>[^"\r\n]+)"?'
    $m = [regex]::Match($Text, $pattern)
    if ($m.Success) {
        return ($m.Groups['name'].Value.Trim())
    }
    return ''
}

function Get-ThemeBrushForPortColor {
    param([string]$ColorName)
    $key = 'Theme.Text.Primary'
    if ([string]::IsNullOrWhiteSpace($ColorName)) {
        $ColorName = 'Gray'
    }
    switch ($ColorName.ToLowerInvariant()) {
        'green'  { $key = 'Theme.Template.Green' }
        'blue'   { $key = 'Theme.Template.Blue' }
        'purple' { $key = 'Theme.Template.Purple' }
        'red'    { $key = 'Theme.Template.Red' }
        'gray'   { $key = 'Theme.Status.Neutral' }
        'black'  { $key = 'Theme.Text.Primary' }
        default  { $key = 'Theme.Text.Primary' }
    }
    try {
        $brush = Get-ThemeBrush -Key $key
        if ($brush) { return $brush }
    } catch {
        Write-Verbose "[CompareView] Get-ThemeBrush failed for key '$key': $($_.Exception.Message)"
    }
    return [System.Windows.Media.Brushes]::Black
}

function Update-CompareThemeBrushes {
    try {
        $color1 = if ($script:lastCompareColors.ContainsKey('Color1')) { $script:lastCompareColors['Color1'] } else { 'Gray' }
        $color2 = if ($script:lastCompareColors.ContainsKey('Color2')) { $script:lastCompareColors['Color2'] } else { 'Gray' }
        $brush1 = Get-ThemeBrushForPortColor -ColorName $color1
        $brush2 = Get-ThemeBrushForPortColor -ColorName $color2
        if ($script:auth1Text)   { $script:auth1Text.Foreground   = $brush1 }
        if ($script:auth2Text)   { $script:auth2Text.Foreground   = $brush2 }
        if ($script:config1Box)  { $script:config1Box.Foreground  = $brush1 }
        if ($script:config2Box)  { $script:config2Box.Foreground  = $brush2 }
    } catch {
        Write-Verbose "[CompareView] Failed to refresh theme brushes: $($_.Exception.Message)"
    }
}
if (-not $script:CompareThemeHandlerRegistered) {
    try {
        Register-StateTraceThemeChanged -Handler ([System.Action[string]]{ param($themeName) Update-CompareThemeBrushes })
        $script:CompareThemeHandlerRegistered = $true
    } catch {
        Write-Verbose "[CompareView] Theme change handler registration failed: $($_.Exception.Message)"
    }
}

function Set-CompareFromRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Row1,
        [Parameter(Mandatory)][psobject]$Row2
    )
    # Given two data rows (interfaces), update the compare view text boxes and diff boxes.
    $tooltip1 = '' + ($Row1.ToolTip)
    $tooltip2 = '' + ($Row2.ToolTip)

    $color1 = if ($Row1.PSObject.Properties['PortColor'] -and $Row1.PortColor) { '' + $Row1.PortColor } else { 'Gray' }
    $color2 = if ($Row2.PSObject.Properties['PortColor'] -and $Row2.PortColor) { '' + $Row2.PortColor } else { 'Gray' }
    $script:lastCompareColors['Color1'] = $color1
    $script:lastCompareColors['Color2'] = $color2
    $brush1 = Get-ThemeBrushForPortColor -ColorName $color1
    $brush2 = Get-ThemeBrushForPortColor -ColorName $color2

    # Display Auth Template name if present
    $auth1 = ''
    try {
        if ($Row1.PSObject.Properties['AuthTemplate'] -and $Row1.AuthTemplate) {
            $auth1 = '' + $Row1.AuthTemplate
        }
    } catch {}
    if (-not $auth1) { $auth1 = Get-AuthTemplateFromTooltip -Text $tooltip1 }

    $auth2 = ''
    try {
        if ($Row2.PSObject.Properties['AuthTemplate'] -and $Row2.AuthTemplate) {
            $auth2 = '' + $Row2.AuthTemplate
        }
    } catch {}
    if (-not $auth2) { $auth2 = Get-AuthTemplateFromTooltip -Text $tooltip2 }

    if ($script:auth1Text) {
        $script:auth1Text.Text = $auth1
        $script:auth1Text.Foreground = $brush1
    }
    if ($script:auth2Text) {
        $script:auth2Text.Text = $auth2
        $script:auth2Text.Foreground = $brush2
    }

    # Prepare cleaned config texts before assigning to text boxes.  Initialise with the full tooltip text.
    $clean1 = $tooltip1
    $clean2 = $tooltip2
    try {
        $parts1 = $tooltip1 -split "`r?`n"
        if ($auth1 -and $parts1.Count -gt 0) {
            $firstLine = ($parts1[0]).Trim()
            if ($firstLine -match '(?im)^(?:auth(?:entication)?\s*template|authtemplate|template)\s*:?' ) {
                $cfgLines = $parts1[1..($parts1.Length-1)]
                while ($cfgLines.Count -gt 0 -and ($cfgLines[0]).Trim() -eq '') { $cfgLines = $cfgLines[1..($cfgLines.Length-1)] }
                $clean1 = $cfgLines -join "`r`n"
            }
        }
    } catch {
        $clean1 = $tooltip1
    }
    try {
        $parts2 = $tooltip2 -split "`r?`n"
        if ($auth2 -and $parts2.Count -gt 0) {
            $firstLine2 = ($parts2[0]).Trim()
            if ($firstLine2 -match '(?im)^(?:auth(?:entication)?\s*template|authtemplate|template)\s*:?' ) {
                $cfg2Lines = $parts2[1..($parts2.Length-1)]
                while ($cfg2Lines.Count -gt 0 -and ($cfg2Lines[0]).Trim() -eq '') { $cfg2Lines = $cfg2Lines[1..($cfg2Lines.Length-1)] }
                $clean2 = $cfg2Lines -join "`r`n"
            }
        }
    } catch {
        $clean2 = $tooltip2
    }

    if ($script:config1Box) {
        $script:config1Box.Text = $clean1
        $script:config1Box.Foreground = $brush1
    }
    if ($script:config2Box) {
        $script:config2Box.Text = $clean2
        $script:config2Box.Foreground = $brush2
    }

    # Compute differences between the two config texts line by line using Compare-Object.
    $lines1 = New-Object 'System.Collections.Generic.List[string]'
    if ($clean1) {
        foreach ($ln in ($clean1 -split "`r?`n")) {
            $t = $ln.Trim()
            if ($t -ne '') { [void]$lines1.Add($t) }
        }
    }
    $lines2 = New-Object 'System.Collections.Generic.List[string]'
    if ($clean2) {
        foreach ($ln in ($clean2 -split "`r?`n")) {
            $t = $ln.Trim()
            if ($t -ne '') { [void]$lines2.Add($t) }
        }
    }
    $diff1 = New-Object 'System.Collections.Generic.List[string]'
    $diff2 = New-Object 'System.Collections.Generic.List[string]'
    try {
        $comp = Compare-Object -ReferenceObject $lines1 -DifferenceObject $lines2
        if ($comp) {
            foreach ($entry in $comp) {
                if ($entry.SideIndicator -eq '<=') { [void]$diff1.Add([string]$entry.InputObject) }
                elseif ($entry.SideIndicator -eq '=>') { [void]$diff2.Add([string]$entry.InputObject) }
            }
        }
    } catch {
        Write-Verbose "[CompareView] Exception during diff computation: $($_.Exception.Message)"
    }

    if ($script:diff1Box) { $script:diff1Box.Text = ([string]::Join("`r`n", $diff1)) }
    if ($script:diff2Box) { $script:diff2Box.Text = ([string]::Join("`r`n", $diff2)) }
}

function Show-CurrentComparison {
    # Gathers current selections and displays the comparison in the text boxes
    try {
        $s1 = if ($script:switch1Dropdown) { Get-HostString $script:switch1Dropdown.SelectedItem } else { $null }
        $s2 = if ($script:switch2Dropdown) { Get-HostString $script:switch2Dropdown.SelectedItem } else { $null }
        $p1 = if ($script:port1Dropdown)   { [string]$script:port1Dropdown.SelectedItem } else { $null }
        $p2 = if ($script:port2Dropdown)   { [string]$script:port2Dropdown.SelectedItem } else { $null }

        if ([string]::IsNullOrWhiteSpace($s1) -or 
            [string]::IsNullOrWhiteSpace($p1) -or
            [string]::IsNullOrWhiteSpace($s2) -or 
            [string]::IsNullOrWhiteSpace($p2)) {
            # One of the sides is not fully selected - cannot compare yet
            Write-Verbose "[CompareView] Show-CurrentComparison skipped (one or more selections empty: Switch1='$s1', Port1='$p1', Switch2='$s2', Port2='$p2')."
            return
        }

        # If both sides have selections, retrieve the corresponding data rows (if possible) and show comparison
        $row1 = Get-GridRowFor -Hostname $s1 -Port $p1
        $row2 = Get-GridRowFor -Hostname $s2 -Port $p2
        if ($row1 -and $row2) {
            # Both rows are available - pass them directly to the comparison helper
            Set-CompareFromRows -Row1 $row1 -Row2 $row2
            Write-Verbose "[CompareView] Comparison updated for $s1/$p1 vs $s2/$p2."
        }
        else {
            # One or both sides are missing - construct placeholder objects for missing rows
            $resolvedRow1 = if ($row1) { $row1 } else { [pscustomobject]@{ ToolTip = ''; PortColor = $null } }
            $resolvedRow2 = if ($row2) { $row2 } else { [pscustomobject]@{ ToolTip = ''; PortColor = $null } }
            Set-CompareFromRows -Row1 $resolvedRow1 -Row2 $resolvedRow2
            Write-Verbose "[CompareView] Partial data: one or both rows not found in grid for $s1/$p1 vs $s2/$p2."
        }
    }
    catch {
        Write-Warning "[CompareView] Failed to compute comparison: $($_.Exception.Message)"
    }
}

function Get-CompareHandlers {
    # Attach event handlers for the compare view controls (ensure we don't attach twice for the same view instance)
    $viewId = if ($script:compareView) { $script:compareView.GetHashCode() } else { 0 }
    if ($script:lastWiredViewId -eq $viewId) { return }
    $script:lastWiredViewId = $viewId

    # When Switch1 changes (selection, losing focus after edit, or Enter key in editable mode), rebuild Port1 list and update compare
    if ($script:switch1Dropdown -and $script:port1Dropdown) {
        $rebuildLeft = {
            ### FIX: inline hostname (avoid Get-HostFromCombo) [switch1Dropdown]
            $si = $script:switch1Dropdown.SelectedItem
            $hostname = if ($si) {
                if ($si -is [string]) { [string]$si }
                elseif ($si.PSObject -and $si.PSObject.Properties['Hostname']) { [string]$si.Hostname }
                elseif ($si.PSObject -and $si.PSObject.Properties['HostName']) { [string]$si.HostName }
                elseif ($si.PSObject -and $si.PSObject.Properties['Name'])     { [string]$si.Name }
                else { ('' + $si) }
            } else { ('' + $script:switch1Dropdown.Text).Trim() }
            ### END FIX
            if ($hostname) {
                Write-Verbose "[CompareView] Switch1 changed to '$hostname'. Rebuilding Port1 list..."
                Set-PortsForCombo -Combo $script:port1Dropdown -Hostname $hostname
            }
            Show-CurrentComparison
        }
        $script:switch1Dropdown.Add_SelectionChanged($rebuildLeft)
        $script:switch1Dropdown.Add_LostFocus($rebuildLeft)
        $script:switch1Dropdown.Add_KeyDown({
            param($s, $e)
            if ($e.Key -eq [System.Windows.Input.Key]::Enter) {
                & $rebuildLeft
                $e.Handled = $true
            }
        })
    }

    # When Switch2 changes, rebuild Port2 list and update compare
    if ($script:switch2Dropdown -and $script:port2Dropdown) {
        $rebuildRight = {
            ### FIX: inline hostname (avoid Get-HostFromCombo) [switch2Dropdown]
            $si = $script:switch2Dropdown.SelectedItem
            $hostname = if ($si) {
                if ($si -is [string]) { [string]$si }
                elseif ($si.PSObject -and $si.PSObject.Properties['Hostname']) { [string]$si.Hostname }
                elseif ($si.PSObject -and $si.PSObject.Properties['HostName']) { [string]$si.HostName }
                elseif ($si.PSObject -and $si.PSObject.Properties['Name'])     { [string]$si.Name }
                else { ('' + $si) }
            } else { ('' + $script:switch2Dropdown.Text).Trim() }
            ### END FIX
            if ($hostname) {
                Write-Verbose "[CompareView] Switch2 changed to '$hostname'. Rebuilding Port2 list..."
                Set-PortsForCombo -Combo $script:port2Dropdown -Hostname $hostname
            }
            Show-CurrentComparison
        }
        $script:switch2Dropdown.Add_SelectionChanged($rebuildRight)
        $script:switch2Dropdown.Add_LostFocus($rebuildRight)
        $script:switch2Dropdown.Add_KeyDown({
            param($s, $e)
            if ($e.Key -eq [System.Windows.Input.Key]::Enter) {
                & $rebuildRight
                $e.Handled = $true
            }
        })
    }

    # When Port1 dropdown is opened, refresh the list for current Switch1 (in case user typed a new switch or data changed), then on selection change update compare
    if ($script:port1Dropdown) {
        $script:port1Dropdown.Add_DropDownOpened({
            ### FIX: inline hostname (avoid Get-HostFromCombo) [opened switch1Dropdown]
            $hostname = if ($script:switch1Dropdown) {
                $si = $script:switch1Dropdown.SelectedItem
                if ($si) {
                    if ($si -is [string]) { [string]$si }
                    elseif ($si.PSObject -and $si.PSObject.Properties['Hostname']) { [string]$si.Hostname }
                    elseif ($si.PSObject -and $si.PSObject.Properties['HostName']) { [string]$si.HostName }
                    elseif ($si.PSObject -and $si.PSObject.Properties['Name'])     { [string]$si.Name }
                    else { ('' + $si) }
                } else { ('' + $script:switch1Dropdown.Text).Trim() }
            } else { $null }
            ### END FIX
            if ($hostname) {
                Write-Verbose "[CompareView] Port1 dropdown opened; refreshing Port1 list for host '$hostname'."
                Set-PortsForCombo -Combo $script:port1Dropdown -Hostname $hostname
            }
        })
        $script:port1Dropdown.Add_SelectionChanged({
            Show-CurrentComparison 
            if ($script:port1Dropdown.SelectedItem) {
                Write-Verbose "[CompareView] Port1 changed to '$($script:port1Dropdown.SelectedItem)' (Switch1=$($script:switch1Dropdown.SelectedItem))."
            }
        })
    }

    # When Port2 dropdown is opened, refresh the list for current Switch2, then update compare on selection
    if ($script:port2Dropdown) {
        $script:port2Dropdown.Add_DropDownOpened({
            ### FIX: inline hostname (avoid Get-HostFromCombo) [opened switch2Dropdown]
            $hostname = if ($script:switch2Dropdown) {
                $si = $script:switch2Dropdown.SelectedItem
                if ($si) {
                    if ($si -is [string]) { [string]$si }
                    elseif ($si.PSObject -and $si.PSObject.Properties['Hostname']) { [string]$si.Hostname }
                    elseif ($si.PSObject -and $si.PSObject.Properties['HostName']) { [string]$si.HostName }
                    elseif ($si.PSObject -and $si.PSObject.Properties['Name'])     { [string]$si.Name }
                    else { ('' + $si) }
                } else { ('' + $script:switch2Dropdown.Text).Trim() }
            } else { $null }
            ### END FIX
            if ($hostname) {
                Write-Verbose "[CompareView] Port2 dropdown opened; refreshing Port2 list for host '$hostname'."
                Set-PortsForCombo -Combo $script:port2Dropdown -Hostname $hostname
            }
        })
        $script:port2Dropdown.Add_SelectionChanged({
            Show-CurrentComparison 
            if ($script:port2Dropdown.SelectedItem) {
                Write-Verbose "[CompareView] Port2 changed to '$($script:port2Dropdown.SelectedItem)' (Switch2=$($script:switch2Dropdown.SelectedItem))."
            }
        })
    }
}

function Update-CompareView {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][System.Windows.Window]$Window)
    # Determine the window reference immediately
    Write-Verbose "[CompareView] Initializing new Compare view..."
    $script:windowRef = $Window
    # Gather the list of hosts based on the current filters before taking further action
    $hosts = Get-HostsFromMain -Window $Window
    # If we already have a compare view and the host list has not changed, refresh
    # the existing host dropdowns and ports and avoid reloading the XAML UI.  This
    # prevents unnecessary re-creation of the view and reduces logging.
    $reuse = $false
    try {
        if ($script:compareView -and $script:LastCompareHostList -and $hosts) {
            if ($script:LastCompareHostList.Count -eq $hosts.Count) {
                $same = $true
                for ($i = 0; $i -lt $hosts.Count; $i++) {
                    if ($script:LastCompareHostList[$i] -ne $hosts[$i]) { $same = $false; break }
                }
                if ($same) { $reuse = $true }
            }
        }
    } catch { $reuse = $false }
    if ($reuse) {
        Write-Verbose "[CompareView] Host list unchanged; refreshing existing compare view hosts."
        # Preserve currently selected switches before replacing the ItemsSource
        $prev1 = ''
        $prev2 = ''
        try { if ($script:switch1Dropdown) { $prev1 = Get-HostString $script:switch1Dropdown.SelectedItem } } catch {}
        try { if ($script:switch2Dropdown) { $prev2 = Get-HostString $script:switch2Dropdown.SelectedItem } } catch {}
        # Update the host dropdowns with the same list
        if ($script:switch1Dropdown) { $script:switch1Dropdown.ItemsSource = $hosts }
        if ($script:switch2Dropdown) { $script:switch2Dropdown.ItemsSource = $hosts }
        # Restore previous selections if still present in the list; otherwise select the first item
        if ($script:switch1Dropdown) {
            if ($prev1 -and $hosts -contains $prev1) { $script:switch1Dropdown.SelectedItem = $prev1 }
            elseif ($hosts.Count -gt 0) { $script:switch1Dropdown.SelectedIndex = 0 }
        }
        if ($script:switch2Dropdown) {
            if ($prev2 -and $hosts -contains $prev2) { $script:switch2Dropdown.SelectedItem = $prev2 }
            elseif ($hosts.Count -gt 0) { $script:switch2Dropdown.SelectedIndex = 0 }
        }
        # Update ports for the selected switches
        if ($script:switch1Dropdown -and $script:port1Dropdown -and $script:switch1Dropdown.SelectedItem) {
            $host1 = Get-HostString $script:switch1Dropdown.SelectedItem
            Set-PortsForCombo -Combo $script:port1Dropdown -Hostname $host1
        }
        if ($script:switch2Dropdown -and $script:port2Dropdown -and $script:switch2Dropdown.SelectedItem) {
            $host2 = Get-HostString $script:switch2Dropdown.SelectedItem
            Set-PortsForCombo -Combo $script:port2Dropdown -Hostname $host2
        }
        # Show comparison for the refreshed selections
        Show-CurrentComparison
        # Update the last host list reference
        $script:LastCompareHostList = $hosts
        Write-Verbose "[CompareView] Existing compare view updated without full reload."
        return
    }

    # At this point we either have no compare view yet or the host list has changed,
    # so we need to build a fresh view and populate it.
    $viewCtrl = Set-StView -Window $Window -ScriptDir $PSScriptRoot -ViewName 'CompareView' -HostControlName 'CompareHost' -GlobalVariableName 'compareView'
    if (-not $viewCtrl) { return }
    Write-Verbose "[CompareView] Compare view injected into main window."
    $script:compareHostCtl = $Window.FindName('CompareHost')
    $closeBtn = $viewCtrl.FindName('CloseCompareButton')
    if ($script:compareHostCtl -is [System.Windows.Controls.ContentControl] -and $closeBtn -and ($script:closeWiredViewId -ne $viewCtrl.GetHashCode())) {
        $closeBtn.Add_Click({
            if ($script:compareHostCtl -is [System.Windows.Controls.ContentControl]) {
                try {
                    if ($script:windowRef) {
                        $col = $script:windowRef.FindName('CompareColumn')
                        if ($col -is [System.Windows.Controls.ColumnDefinition]) {
                            $col.Width = [System.Windows.GridLength]::new(0)
                        }
                    }
                } catch { }
            }
        })
        $script:closeWiredViewId = $viewCtrl.GetHashCode()
    }
    $script:compareView = $viewCtrl
    Resolve-CompareControls | Out-Null
    # Populate the switches list for both dropdowns with the new host list
    if ($script:switch1Dropdown) {
        $script:switch1Dropdown.ItemsSource = $hosts 
        Write-Verbose "[CompareView] Switch1Dropdown populated with $($hosts.Count) host(s)."
    }
    if ($script:switch2Dropdown) {
        $script:switch2Dropdown.ItemsSource = $hosts 
        Write-Verbose "[CompareView] Switch2Dropdown populated with $($hosts.Count) host(s)."
    }
    # Select first host by default if no selection
    if ($script:switch1Dropdown -and -not $script:switch1Dropdown.SelectedItem -and $script:switch1Dropdown.Items.Count -gt 0) {
        $script:switch1Dropdown.SelectedIndex = 0
        Write-Verbose "[CompareView] Switch1 defaulted to '$($script:switch1Dropdown.SelectedItem)'."
    }
    if ($script:switch2Dropdown -and -not $script:switch2Dropdown.SelectedItem -and $script:switch2Dropdown.Items.Count -gt 0) {
        $script:switch2Dropdown.SelectedIndex = 0
        Write-Verbose "[CompareView] Switch2 defaulted to '$($script:switch2Dropdown.SelectedItem)'."
    }
    # Populate ports for pre-selected switches
    if ($script:switch1Dropdown -and $script:port1Dropdown -and $script:switch1Dropdown.SelectedItem) {
        $host1 = Get-HostString $script:switch1Dropdown.SelectedItem
        Set-PortsForCombo -Combo $script:port1Dropdown -Hostname $host1
    }
    if ($script:switch2Dropdown -and $script:port2Dropdown -and $script:switch2Dropdown.SelectedItem) {
        $host2 = Get-HostString $script:switch2Dropdown.SelectedItem
        Set-PortsForCombo -Combo $script:port2Dropdown -Hostname $host2
    }
    # Wire up event handlers and display initial comparison
    Get-CompareHandlers
    Show-CurrentComparison
    # Record host list for next comparison
    $script:LastCompareHostList = $hosts
    Write-Verbose "[CompareView] New Compare view setup complete."
}

function Set-CompareSelection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Switch1,
        [Parameter(Mandatory)][string]$Interface1,
        [Parameter(Mandatory)][string]$Switch2,
        [Parameter(Mandatory)][string]$Interface2,
        [psobject]$Row1,
        [psobject]$Row2
    )
    # Updates an existing Compare view with given switches and interfaces selected.
    if (-not $script:compareView) {
        # Emit a message that accurately reflects the calling function.  Previously
        # this log incorrectly referenced Update-CompareView, which could
        # confuse debugging.  Use the current function name instead.
        Write-Verbose "[CompareView] Set-CompareSelection called but compareView is not initialized."
        return
    }

    Resolve-CompareControls | Out-Null
    # Ensure event handlers are attached (if Update is called first without New)
    Get-CompareHandlers

    # Refresh host lists in case of any changes
    $hosts = if ($script:windowRef) { Get-HostsFromMain -Window $script:windowRef } else { @() }
    if ($script:switch1Dropdown) {
        $script:switch1Dropdown.ItemsSource = $hosts 
        Write-Verbose "[CompareView] Switch1Dropdown updated with $($hosts.Count) hosts (Update-CompareView)."
    }
    if ($script:switch2Dropdown) {
        $script:switch2Dropdown.ItemsSource = $hosts 
        Write-Verbose "[CompareView] Switch2Dropdown updated with $($hosts.Count) hosts (Update-CompareView)."
    }

    # Set the specified selections
    if ($script:switch1Dropdown) { $script:switch1Dropdown.SelectedItem = $Switch1 }
    if ($script:switch2Dropdown) { $script:switch2Dropdown.SelectedItem = $Switch2 }

    # Populate ports for the specified switches and select the given interfaces
    if ($script:port1Dropdown -and $Switch1) {
        Set-PortsForCombo -Combo $script:port1Dropdown -Hostname $Switch1
        if ($Interface1) { $script:port1Dropdown.SelectedItem = $Interface1 }
        Write-Verbose "[CompareView] Switch1 set to '$Switch1', Port1 set to '$Interface1' (Update-CompareView)."
    }
    if ($script:port2Dropdown -and $Switch2) {
        Set-PortsForCombo -Combo $script:port2Dropdown -Hostname $Switch2
        if ($Interface2) { $script:port2Dropdown.SelectedItem = $Interface2 }
        Write-Verbose "[CompareView] Switch2 set to '$Switch2', Port2 set to '$Interface2' (Update-CompareView)."
    }

    # If Row1 and Row2 were provided (pre-fetched data), use them; otherwise attempt to get from grid/DB
    if ($Row1 -and $Row2) {
        Set-CompareFromRows -Row1 $Row1 -Row2 $Row2
        Write-Verbose "[CompareView] Comparison set from provided rows (Update-CompareView)."
    }
    else {
        Show-CurrentComparison
    }
}

Export-ModuleMember -Function Resolve-CompareControls, Get-HostString, Get-HostsFromMain, Get-PortSortKey, Get-PortsForHost, Set-PortsForCombo, Get-GridRowFor, Get-AuthTemplateFromTooltip, Get-ThemeBrushForPortColor, Update-CompareThemeBrushes, Set-CompareFromRows, Show-CurrentComparison, Get-CompareHandlers, Update-CompareView, Set-CompareSelection



