function New-SpanView {
    # .SYNOPSIS

    param(
        [Parameter(Mandatory=$true)][Windows.Window]$Window,
        [Parameter(Mandatory=$true)][string]$ScriptDir
    )

    $spanViewPath = Join-Path $ScriptDir '..\Views\SpanView.xaml'
    if (-not (Test-Path $spanViewPath)) {
        Write-Warning "SpanView.xaml not found at $spanViewPath"
        return
    }
    $spanXaml = Get-Content $spanViewPath -Raw
    $reader   = New-Object System.Xml.XmlTextReader (New-Object System.IO.StringReader($spanXaml))
    $spanView = [Windows.Markup.XamlReader]::Load($reader)
    $spanHost = $Window.FindName('SpanHost')
    if ($spanHost -is [System.Windows.Controls.ContentControl]) {
        $spanHost.Content = $spanView
    } else {
        Write-Warning "Could not find ContentControl 'SpanHost'"
    }
    # Expose span view globally for other modules
    $global:spanView = $spanView
    # Acquire controls
    $spanGrid     = $spanView.FindName('SpanGrid')
    $vlanDropdown = $spanView.FindName('VlanDropdown')
    $spanRefresh  = $spanView.FindName('RefreshSpanButton')
    # Helper to load spanning tree information for a device
    function Global:Load-SpanInfo {
        param([string]$Hostname)
        if (-not $spanGrid) { return }
        # Clear when no hostname provided
        if (-not $Hostname) {
        # Clear the spanning tree grid and initialise the VLAN dropdown
        $spanGrid.ItemsSource = @()
        if ($vlanDropdown) {
            # Use the shared dropdown helper from DeviceDataModule to populate
            # the VLAN dropdown with a single blank entry.  This helper
            # handles both ItemsSource assignment and index selection.
            DeviceDataModule\Set-DropdownItems -Control $vlanDropdown -Items @('')
        }
            return
        }
        # Retrieve data
        try {
            $data = Get-SpanningTreeInfo -Hostname $Hostname
        } catch {
            $data = @()
        }
        $spanGrid.ItemsSource = $data
        if ($vlanDropdown) {
            # Build a unique sorted list of VLAN instances using a HashSet and typed list.
            $vset = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            foreach ($row in $data) {
                $v = $row.VLAN
                if ($null -ne $v -and ('' + $v).Trim() -ne '') {
                    [void]$vset.Add(('' + $v))
                }
            }
            $instances = [System.Collections.Generic.List[string]]::new($vset)
            $instances.Sort([System.StringComparer]::OrdinalIgnoreCase)
            # Use the shared dropdown helper to populate the VLAN dropdown with
            # a blank entry plus all VLAN instances.
            DeviceDataModule\Set-DropdownItems -Control $vlanDropdown -Items (@('') + $instances)
        }
    }
    # VLAN dropdown filtering
    if ($vlanDropdown) {
        $vlanDropdown.Add_SelectionChanged({
            $sel = $vlanDropdown.SelectedItem
            if (-not $spanGrid) { return }
            $selectedHost = $Window.FindName('HostnameDropdown').SelectedItem
            if (-not $selectedHost) { return }
            $all = Get-SpanningTreeInfo -Hostname $selectedHost
            if (-not $sel -or $sel -eq '') {
                $spanGrid.ItemsSource = $all
            } else {
                $spanGrid.ItemsSource = $all | Where-Object { $_.VLAN -eq $sel }
            }
        })
    }
    # Refresh button re-runs parser and updates summaries
    if ($spanRefresh) {
        $spanRefresh.Add_Click({
            # Update the database path env var if available
            if ($global:StateTraceDb) { $env:StateTraceDbPath = $global:StateTraceDb }

            # Call the exported parser function
            if (Get-Command Invoke-StateTraceParsing -ErrorAction SilentlyContinue) {
                Invoke-StateTraceParsing
            } else {
                Write-Error "Invoke-StateTraceParsing not found (module load failed)"
            }

            # Refresh summaries and filters
            if (Get-Command Get-DeviceSummaries -ErrorAction SilentlyContinue) { Get-DeviceSummaries }
            if (Get-Command Update-DeviceFilter -ErrorAction SilentlyContinue) { Update-DeviceFilter }

            # Reload spanning tree info for current host
            $currentHost = $Window.FindName('HostnameDropdown').SelectedItem
            if ($currentHost) { Load-SpanInfo $currentHost }
        })
    }
}

Export-ModuleMember -Function New-SpanView, Load-SpanInfo