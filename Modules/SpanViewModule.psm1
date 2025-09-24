function New-SpanView {
    # .SYNOPSIS

    param(
        [Parameter(Mandatory=$true)][System.Windows.Window]$Window,
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
    # Helper to get spanning tree information for a device
    #
    # NOTE: The original implementation used the verb 'Load'.  According to
    # PowerShell best practices, cmdlet names should use approved verbs.
    # 'Load' isn't an approved verb (the recommended verb for obtaining
    # information is 'Get'), so we've renamed this helper to
    # 'Get-SpanInfo'.  All references to the old Load-SpanInfo name have
    # been updated accordingly.  This change eliminates import warnings
    # about unapproved verbs and makes the command more discoverable.
    function Global:Get-SpanInfo {
        param([string]$Hostname)
        if (-not $spanGrid) { return }
        # Clear when no hostname provided
        if (-not $Hostname) {
        # Clear the spanning tree grid and initialise the VLAN dropdown
        $spanGrid.ItemsSource = @()
        if ($vlanDropdown) {
            # Use the shared dropdown helper from FilterStateModule to populate
            FilterStateModule\Set-DropdownItems -Control $vlanDropdown -Items @('')
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
            FilterStateModule\Set-DropdownItems -Control $vlanDropdown -Items (@('') + $instances)
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
            # Per-site databases are computed within the parser; do not set a global database path

            # Call the exported parser function
            if (Get-Command Invoke-StateTraceParsing -ErrorAction SilentlyContinue) {
                Invoke-StateTraceParsing
            } else {
                Write-Error "Invoke-StateTraceParsing not found (module load failed)"
            }

            # Refresh summaries and filters
            $catalog = $null
            if (Get-Command Get-DeviceSummaries -ErrorAction SilentlyContinue) {
                try { $catalog = Get-DeviceSummaries } catch { $catalog = $null }
            }
            if (Get-Command Initialize-DeviceFilters -ErrorAction SilentlyContinue) {
                try {
                    $hostList = if ($catalog -and $catalog.PSObject.Properties['Hostnames']) { $catalog.Hostnames } else { $null }
                    if ($hostList) {
                        Initialize-DeviceFilters -Hostnames $hostList -Window $Window
                    } else {
                        Initialize-DeviceFilters -Window $Window
                    }
                } catch {}
            }
            if (Get-Command Update-DeviceFilter -ErrorAction SilentlyContinue) { Update-DeviceFilter }
            # Reload spanning tree info for current host
            $currentHost = $Window.FindName('HostnameDropdown').SelectedItem
            if ($currentHost) { Get-SpanInfo $currentHost }
        })
    }
}

Export-ModuleMember -Function New-SpanView, Get-SpanInfo

