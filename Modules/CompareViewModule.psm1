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

# Ensure debug verbose output is configured
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
    <#
        Retrieves the list of device hostnames.  Historically this function
        attempted to read the HostnameDropdown from the main window and then
        fell back to the database via Get-DeviceSummaries.  To decouple the
        compare view from the main UI and ensure a single source of truth,
        this implementation now always queries the database through
        DeviceDataModule.  Any passed Window parameter is ignored.

        Returns an array of unique, trimmed hostname strings.
    #>
    [CmdletBinding()]
    param([Windows.Window]$Window)

    $hosts = @()
    try {
        # Prefer using DeviceDataModule\Get-InterfaceHostnames which reads
        # directly from the database without manipulating any UI elements.
        if (Get-Command -Name 'Get-InterfaceHostnames' -ErrorAction SilentlyContinue) {
            $raw = @(DeviceDataModule\Get-InterfaceHostnames)
            $hosts = @($raw | ForEach-Object { Get-HostString $_ })
            Write-Verbose "[CompareView] Retrieved $($hosts.Count) host(s) from Get-InterfaceHostnames (database)."
        }
    } catch {
        $hosts = @()
        Write-Warning "[CompareView] Failed to retrieve host list from database: $($_.Exception.Message)"
    }
    # Clean up host list: trim whitespace, remove blanks and deduplicate.
    # Use a typed list and a case‑insensitive HashSet to avoid repeated
    # pipeline passes and array copying.  Typed lists grow amortised O(1).
    # After deduplication, sort the list alphabetically (case-insensitive) to
    # provide a consistent ordering in the compare dropdowns.
    $hostSet  = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $hostList = New-Object 'System.Collections.Generic.List[string]'
    foreach ($h in $hosts) {
        $t = ('' + $h).Trim()
        if ($t -and $t -ne '' -and $hostSet.Add($t)) {
            [void]$hostList.Add($t)
        }
    }
    # Sort hostnames alphabetically once all unique names have been collected.  Sorting here
    # ensures both switch dropdowns in the Compare view are ordered consistently regardless of
    # the order returned from the database or prior selections.
    if ($hostList -and $hostList.Count -gt 1) {
        $hostList.Sort([System.StringComparer]::OrdinalIgnoreCase)
    }
    return ,$hostList.ToArray()
}

function Get-PortSortKey {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Port)
    # Delegate sorting to the central Get-PortSortKey implementation defined in
    # DeviceDataModule.  Passing through the bound parameters preserves
    # compatibility while eliminating duplicated logic.
    return DeviceDataModule\Get-PortSortKey @PSBoundParameters
}

function Get-PortsForHost {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Hostname)

    # Fetch all interface names for the given host from the database.  This revised
    # implementation eliminates any fallback to the main Interfaces grid and
    # relies solely on the centralised DeviceDataModule functions.  It first
    # attempts to call Get-InterfaceList, which returns an array of port strings;
    # if no ports are returned, it falls back to Get-InterfaceInfo to extract
    # port names from full interface objects.
    Write-Verbose "[CompareView] Fetching ports for host '$Hostname'..."
    # Use typed lists to accumulate and normalise port names.  Avoid
    # pipeline-based trimming, sorting and deduplication to reduce overhead
    # when many ports are present.
    $portsList = New-Object 'System.Collections.Generic.List[string]'
    try {
        if (Get-Command -Name 'Get-InterfaceList' -ErrorAction SilentlyContinue) {
            $list = @(DeviceDataModule\Get-InterfaceList -Hostname $Hostname)
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
                $info = @(DeviceDataModule\Get-InterfaceInfo -Hostname $Hostname)
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
    # case‑insensitive set for uniqueness and stable insertion order.  Sort
    # using the port sort key for natural ordering.
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
        $k1 = DeviceDataModule\Get-PortSortKey -Port $a
        $k2 = DeviceDataModule\Get-PortSortKey -Port $b
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
    # If Hostname is empty, clears the combo. Ensures first port is selected on new list.
    if ([string]::IsNullOrWhiteSpace($Hostname)) {
        # No host specified – clear the combo box
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
    # database via DeviceDataModule.  Any reliance on the global Interfaces
    # grid has been removed to decouple the compare view from other views.
    try {
        if (Get-Command -Name 'Get-InterfaceInfo' -ErrorAction SilentlyContinue) {
            # Retrieve all interface objects for the specified host
            $ifaceList = DeviceDataModule\Get-InterfaceInfo -Hostname $Hostname
            if ($ifaceList) {
                # Normalize the requested port by trimming and uppercasing for comparison
                $tgt = ('' + $Port).Trim().ToUpperInvariant()
                foreach ($iface in $ifaceList) {
                    $p = ('' + $iface.Port).Trim().ToUpperInvariant()
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
    # "authentication template" and the more generic "template".  Accept
    # optional colon and quotes around the name.  This allows both
    # "AuthTemplate: XYZ", "auth template XYZ" and "Template: XYZ" to be parsed.
    $pattern = '(?im)^\s*(?:auth(?:entication)?\s*template|authtemplate|template)\s*:?' +
               '\s*"?(?<name>[^"\r\n]+)"?'
    $m = [regex]::Match($Text, $pattern)
    if ($m.Success) {
        return ($m.Groups['name'].Value.Trim())
    }
    return ''
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
    # Determine the colour for each side.  When the PortColor property is not
    # available or empty, fall back to a neutral 'Gray' instead of Black.  Gray
    # communicates an undefined or unknown compliance state and avoids
    # implying compliance (Black can be interpreted as an OK state).  The
    # returned colour names must correspond to valid WPF brush names.
    $color1   = if ($Row1.PSObject.Properties['PortColor'] -and $Row1.PortColor) { '' + $Row1.PortColor } else { 'Gray' }
    $color2   = if ($Row2.PSObject.Properties['PortColor'] -and $Row2.PortColor) { '' + $Row2.PortColor } else { 'Gray' }

    # Display Auth Template name if present
    # Prefer the AuthTemplate property on the row if available; fall back to parsing the tooltip.
    $auth1 = ''
    try {
        if ($Row1.PSObject.Properties['AuthTemplate'] -and $Row1.AuthTemplate) {
            $auth1 = '' + $Row1.AuthTemplate
        }
    } catch {}
    if (-not $auth1) {
        $auth1 = Get-AuthTemplateFromTooltip -Text $tooltip1
    }
    $auth2 = ''
    try {
        if ($Row2.PSObject.Properties['AuthTemplate'] -and $Row2.AuthTemplate) {
            $auth2 = '' + $Row2.AuthTemplate
        }
    } catch {}
    if (-not $auth2) {
        $auth2 = Get-AuthTemplateFromTooltip -Text $tooltip2
    }
    # Update the auth template text and colour it using the same port colour.  If the colour
    # name is invalid, fallback to Black.  Colour-coding the template label helps
    # indicate compliance (e.g., red for mismatch, green/black for match).
    # Display only the template name (e.g., "flexible", "dot1x", "open") without
    # prefixing it with "AuthTemplate:".  The surrounding UI already conveys the
    # meaning of this field, so adding the prefix is redundant.  Set the
    # Foreground brush based on the computed colour; if an invalid colour is
    # supplied, fall back to Black as a safe default.
    if ($script:auth1Text) {
        $script:auth1Text.Text = $auth1
        try {
            $script:auth1Text.Foreground = [System.Windows.Media.Brushes]::$color1
        } catch {
            $script:auth1Text.Foreground = [System.Windows.Media.Brushes]::Black
        }
    }
    if ($script:auth2Text) {
        $script:auth2Text.Text = $auth2
        try {
            $script:auth2Text.Foreground = [System.Windows.Media.Brushes]::$color2
        } catch {
            $script:auth2Text.Foreground = [System.Windows.Media.Brushes]::Black
        }
    }

    # Prepare cleaned config texts before assigning to text boxes.  Initialise with the full
    # tooltip and then strip any leading template line if an auth template is present.
    $clean1 = $tooltip1
    $clean2 = $tooltip2
    try {
        $parts1 = $tooltip1 -split "`r?`n"
        if ($auth1 -and $parts1.Count -gt 0) {
            $firstLine = ($parts1[0]).Trim()
            if ($firstLine -match '(?im)^(?:auth(?:entication)?\s*template|authtemplate|template)\s*:?' ) {
                $cfgLines = $parts1[1..($parts1.Length-1)]
                # Remove any leading blank lines
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
    # Set config text and colour on the UI controls using the cleaned text.
    if ($script:config1Box) {
        $script:config1Box.Text = $clean1
        try {
            $script:config1Box.Foreground = [System.Windows.Media.Brushes]::$color1
        } catch {
            $script:config1Box.Foreground = [System.Windows.Media.Brushes]::Black
        }
    }
    if ($script:config2Box) {
        $script:config2Box.Text = $clean2
        try {
            $script:config2Box.Foreground = [System.Windows.Media.Brushes]::$color2
        } catch {
            $script:config2Box.Foreground = [System.Windows.Media.Brushes]::Black
        }
    }

    # Compute differences between the two config texts line by line using
    # typed lists instead of ForEach-Object/Where-Object pipelines.  This
    # avoids per-line script block invocation overhead when trimming and
    # filtering empty lines, and reduces array reallocation when building
    # the diff lists.
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
            # One of the sides is not fully selected – cannot compare yet
            Write-Verbose "[CompareView] Show-CurrentComparison skipped (one or more selections empty: Switch1='$s1', Port1='$p1', Switch2='$s2', Port2='$p2')."
            return
        }

        # If both sides have selections, retrieve the corresponding data rows (if possible) and show comparison
        $row1 = Get-GridRowFor -Hostname $s1 -Port $p1
        $row2 = Get-GridRowFor -Hostname $s2 -Port $p2
        if ($row1 -and $row2) {
            Set-CompareFromRows -Row1 $row1 -Row2 $row2
            Write-Verbose "[CompareView] Comparison updated for $s1/$p1 vs $s2/$p2."
        }
        else {
            # If either row is not found (e.g., not present in global grid), just clear or show what we have
            Set-CompareFromRows -Row1 (if ($row1) { $row1 } else { [pscustomobject]@{ToolTip = ''; PortColor = $null} }) `
                                 -Row2 (if ($row2) { $row2 } else { [pscustomobject]@{ToolTip = ''; PortColor = $null} })
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

    Write-Verbose "[CompareView] Initializing new Compare view..."
    $script:windowRef = $Window

    # Load the XAML UI for the compare view
    $xamlPath = Join-Path $PSScriptRoot '..\Views\CompareView.xaml'
    if (-not (Test-Path -LiteralPath $xamlPath)) {
        Write-Warning "[CompareView] Compare view XAML not found at $xamlPath"
        return
    }
    try {
        $xaml   = [System.IO.File]::ReadAllText($xamlPath)
        $reader = [System.Xml.XmlTextReader]::new([System.IO.StringReader]::new($xaml))
        $viewCtrl = [System.Windows.Markup.XamlReader]::Load($reader)
    }
    catch {
        Write-Warning "[CompareView] Failed to load compare view XAML from ${xamlPath}: $($_.Exception.Message)"
        return
    }
    if (-not $viewCtrl) {
        Write-Warning "[CompareView] XAML loaded but viewCtrl is null. Aborting."
        return
    }

    # Inject the loaded Compare view control into the main window's CompareHost container
    $compareHost = $Window.FindName('CompareHost')
    if ($compareHost -is [System.Windows.Controls.ContentControl]) {
        $compareHost.Content = $viewCtrl
        Write-Verbose "[CompareView] Compare view injected into main window."
        ### FIX: Wire up Close button to remove Compare view (sidebar) [LANDMARK]
        $script:compareHostCtl = $compareHost
        $closeBtn = $viewCtrl.FindName('CloseCompareButton')
        if ($closeBtn -and ($script:closeWiredViewId -ne $viewCtrl.GetHashCode())) {
            # Attach a single click handler to collapse the Compare sidebar instead of removing its content.
            # When the user clicks the 'X' button the Compare column width is set to zero, effectively hiding
            # the sidebar while keeping the view loaded.  This allows the sidebar to be reopened later
            # without reloading the XAML or losing event handlers.  The handler is only wired once per view
            # instance based on the viewCtrl hash code.
            $closeBtn.Add_Click({
                if ($script:compareHostCtl -is [System.Windows.Controls.ContentControl]) {
                    # Attempt to collapse the Compare column on the main window
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
        ### END FIX
    }
    else {
        Write-Warning "[CompareView] Could not find ContentControl 'CompareHost' in the main window."
        return
    }

    # Store reference and bind controls
    $script:compareView = $viewCtrl
    Resolve-CompareControls | Out-Null

    # Populate the switches list for both dropdowns
    $hosts = Get-HostsFromMain -Window $Window
    if ($script:switch1Dropdown) {
        $script:switch1Dropdown.ItemsSource = $hosts 
        Write-Verbose "[CompareView] Switch1Dropdown populated with $($hosts.Count) host(s)."
    }
    if ($script:switch2Dropdown) {
        $script:switch2Dropdown.ItemsSource = $hosts 
        Write-Verbose "[CompareView] Switch2Dropdown populated with $($hosts.Count) host(s)."
    }

    # Default selection: select the first host in each dropdown (if not already selected)
    if ($script:switch1Dropdown -and -not $script:switch1Dropdown.SelectedItem -and $script:switch1Dropdown.Items.Count -gt 0) {
        $script:switch1Dropdown.SelectedIndex = 0
        Write-Verbose "[CompareView] Switch1 defaulted to '$($script:switch1Dropdown.SelectedItem)'."
    }
    if ($script:switch2Dropdown -and -not $script:switch2Dropdown.SelectedItem -and $script:switch2Dropdown.Items.Count -gt 0) {
        $script:switch2Dropdown.SelectedIndex = 0
        Write-Verbose "[CompareView] Switch2 defaulted to '$($script:switch2Dropdown.SelectedItem)'."
    }

    # Populate Port lists for any pre-selected switches
    if ($script:switch1Dropdown -and $script:port1Dropdown -and $script:switch1Dropdown.SelectedItem) {
        $host1 = Get-HostString $script:switch1Dropdown.SelectedItem
        Set-PortsForCombo -Combo $script:port1Dropdown -Hostname $host1
    }
    if ($script:switch2Dropdown -and $script:port2Dropdown -and $script:switch2Dropdown.SelectedItem) {
        $host2 = Get-HostString $script:switch2Dropdown.SelectedItem
        Set-PortsForCombo -Combo $script:port2Dropdown -Hostname $host2
    }

    # Wire up event handlers and show the initial comparison (if both sides have selection)
    Get-CompareHandlers
    Show-CurrentComparison

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
        Write-Verbose "[CompareView] Update-CompareView called but compareView is not initialized."
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
