Add-Type -AssemblyName PresentationFramework

# 1) Paths
$scriptDir           = Split-Path -Parent $MyInvocation.MyCommand.Path
$parserScript        = Join-Path $scriptDir '.\NetworkReader.ps1'
$interfaceModulePath = Join-Path $scriptDir '..\Modules\InterfaceModule.psm1'
$interfacesViewXaml  = Join-Path $scriptDir '..\Views\InterfacesView.xaml'


# 2) Import Interfaces module
if (-not (Test-Path $interfaceModulePath)) {
    Write-Error "Cannot find InterfaceModule at $interfaceModulePath"
    exit 1
}
Import-Module $interfaceModulePath -Force

# 2a) Import Database module and ensure the database exists
$dbModulePath = Join-Path $scriptDir '..\Modules\DatabaseModule.psm1'
if (Test-Path $dbModulePath) {
    # Import the DatabaseModule globally so that its functions (e.g. Invoke-DbQuery) are available to all modules
    Import-Module $dbModulePath -Force -Global
        try {
            # Attempt to create a modern .accdb database first.  This will use the
            # ACE OLEDB provider if installed.  If the provider is unavailable
            # or creation fails, fall back to creating a .mdb using the Jet
            # provider.  Store the resulting path globally for later use.
            $dataDir = Join-Path $scriptDir '..\Data'
            if (-not (Test-Path $dataDir)) { New-Item -ItemType Directory -Path $dataDir -Force | Out-Null }
            $accdbPath = Join-Path $dataDir 'StateTrace.accdb'
            try {
                $global:StateTraceDb = New-AccessDatabase -Path $accdbPath
            } catch {
                Write-Warning "Failed to create .accdb database: $($_.Exception.Message). Falling back to .mdb."
                $mdbPath = Join-Path $dataDir 'StateTrace.mdb'
                $global:StateTraceDb = New-AccessDatabase -Path $mdbPath
            }
        } catch {
            Write-Warning "Database initialization failed: $_"
        }
} else {
    Write-Warning "Database module not found at $dbModulePath. Parsed results will continue to use CSV files."
}

# 2b) Import Gui module to provide helper functions used by the view modules
$guiModulePath = Join-Path $scriptDir '..\Modules\GuiModule.psm1'
if (Test-Path $guiModulePath) {
    try {
        # Import globally so that helpers like Update-Summary, Update-Alerts, Update-SearchResults, etc. are available
        Import-Module $guiModulePath -Force -Global -DisableNameChecking
    } catch {
        Write-Warning "Failed to import GuiModule from ${guiModulePath}: $($_.Exception.Message)"
    }
} else {
    Write-Warning "GuiModule not found at $guiModulePath. Some features may not function correctly."
}

# 2c) Import Device functions module to provide Get‑DeviceSummaries,
# Update‑DeviceFilter and Get‑DeviceDetails helpers.  These helpers were
# moved out of this file into DeviceFunctionsModule.psm1 for better
# modularity.
$deviceFunctionsPath = Join-Path $scriptDir '..\Modules\DeviceFunctionsModule.psm1'
if (Test-Path $deviceFunctionsPath) {
    try {
        Import-Module $deviceFunctionsPath -Force -Global -DisableNameChecking
    } catch {
        Write-Warning "Failed to import DeviceFunctionsModule from ${deviceFunctionsPath}: $($_.Exception.Message)"
    }
} else {
    Write-Warning "DeviceFunctionsModule not found at $deviceFunctionsPath"
}

# 3) Load MainWindow.xaml
$xamlPath = Join-Path $scriptDir 'MainWindow.xaml'
if (-not (Test-Path $xamlPath)) {
    Write-Error "Cannot find MainWindow.xaml at $xamlPath"
    exit 1
}
$xamlContent = Get-Content $xamlPath -Raw
$reader      = New-Object System.Xml.XmlTextReader (New-Object System.IO.StringReader($xamlContent))
$window      = [Windows.Markup.XamlReader]::Load($reader)

Set-Variable -Name window -Value $window -Scope Global

# 4) Helpers

# Initialize the views via modular imports
try {
    # Initialise the Interfaces view using the combined InterfaceModule.
    # The view initialisation function is now exported from InterfaceModule.psm1,
    # which was imported above.  Simply invoke it here.  Wrap in a try/catch
    # to ensure other views still load if it fails.
    try {
        New-InterfacesView -Window $window -ScriptDir $scriptDir
    } catch {
        Write-Warning "Failed to initialise Interfaces view: $($_.Exception.Message)"
    }

    $spanModulePath = Join-Path $scriptDir '..\Modules\SpanViewModule.psm1'
    if (Test-Path $spanModulePath) {
        Import-Module $spanModulePath -Force -Global
        New-SpanView -Window $window -ScriptDir $scriptDir -ParserScript $parserScript
    } else {
        Write-Warning "SpanViewModule not found at $spanModulePath"
    }

    $searchModulePath = Join-Path $scriptDir '..\Modules\SearchInterfacesViewModule.psm1'
    if (Test-Path $searchModulePath) {
        Import-Module $searchModulePath -Force -Global
        New-SearchInterfacesView -Window $window -ScriptDir $scriptDir
    } else {
        Write-Warning "SearchInterfacesViewModule not found at $searchModulePath"
    }

    $summaryModulePath = Join-Path $scriptDir '..\Modules\SummaryViewModule.psm1'
    if (Test-Path $summaryModulePath) {
        Import-Module $summaryModulePath -Force -Global
        New-SummaryView -Window $window -ScriptDir $scriptDir
    } else {
        Write-Warning "SummaryViewModule not found at $summaryModulePath"
    }

    $templatesModulePath = Join-Path $scriptDir '..\Modules\TemplatesViewModule.psm1'
    if (Test-Path $templatesModulePath) {
        Import-Module $templatesModulePath -Force -Global
        New-TemplatesView -Window $window -ScriptDir $scriptDir
    } else {
        Write-Warning "TemplatesViewModule not found at $templatesModulePath"
    }

    $alertsModulePath = Join-Path $scriptDir '..\Modules\AlertsViewModule.psm1'
    if (Test-Path $alertsModulePath) {
        Import-Module $alertsModulePath -Force -Global
        New-AlertsView -Window $window -ScriptDir $scriptDir
    } else {
        Write-Warning "AlertsViewModule not found at $alertsModulePath"
    }
} catch {
    Write-Warning "Failed to initialize view modules: $($_.Exception.Message)"
}

# 6) Hook up main window controls
$refreshBtn = $window.FindName('RefreshButton')
if ($refreshBtn) {
    $refreshBtn.Add_Click({
        # Capture archive inclusion settings from the checkboxes.  Blank/unset
        # values indicate that archives should not be processed.  Use strings
        # instead of booleans so the downstream script can detect them via
        # $env variables.
        $includeArchiveCB = $window.FindName('IncludeArchiveCheckbox')
        $includeHistoricalCB = $window.FindName('IncludeHistoricalCheckbox')
        if ($includeArchiveCB) {
            if ($includeArchiveCB.IsChecked) { $env:IncludeArchive = 'true' } else { $env:IncludeArchive = '' }
        }
        if ($includeHistoricalCB) {
            if ($includeHistoricalCB.IsChecked) { $env:IncludeHistorical = 'true' } else { $env:IncludeHistorical = '' }
        }
        # Set the database path environment variable if defined
        if ($global:StateTraceDb) { $env:StateTraceDbPath = $global:StateTraceDb }
        # Run the parser script.  It will inspect the environment variables
        # defined above to determine whether to include archive data.  After
        # completion, reload the device summaries and refresh the filters.
        & "$parserScript"
        Get-DeviceSummaries
        Update-DeviceFilter
    })
}

$hostnameDropdown = $window.FindName('HostnameDropdown')
if ($hostnameDropdown) {
    $hostnameDropdown.Add_SelectionChanged({
        $sel = $hostnameDropdown.SelectedItem
        if ($sel) {
            Get-DeviceDetails $sel
            # If the Span tab is loaded and helper exists, load span info
            if (Get-Command Load-SpanInfo -ErrorAction SilentlyContinue) {
                Load-SpanInfo $sel
            }
        } else {
            # Clear span grid when nothing selected
            if (Get-Command Load-SpanInfo -ErrorAction SilentlyContinue) {
                Load-SpanInfo ''
            }
        }
    })
}

# Hook site/building/room dropdowns to update filtering
$siteDropdown = $window.FindName('SiteDropdown')
if ($siteDropdown) {
    $siteDropdown.Add_SelectionChanged({
        Update-DeviceFilter
    })
}

$buildingDropdown = $window.FindName('BuildingDropdown')
if ($buildingDropdown) {
    $buildingDropdown.Add_SelectionChanged({
        Update-DeviceFilter
    })
}

$roomDropdown = $window.FindName('RoomDropdown')
if ($roomDropdown) {
    $roomDropdown.Add_SelectionChanged({
        Update-DeviceFilter
    })
}

# -------------------------------------------------------------------------
# Compare sidebar initialization
#
# Load the compare view module and initialize the compare pane.  The sidebar is
# controlled by the Interfaces tab when a comparison is initiated, so there
# is no toggle button in the main window.  The CompareViewModule is imported
# globally to make its Update-CompareView function available.
$compareModulePath = Join-Path $scriptDir '..\Modules\CompareViewModule.psm1'
if (Test-Path $compareModulePath) {
    try {
        Import-Module $compareModulePath -Force -Global
        # Initialize the compare view.  The module computes its own view path
        # relative to its location, so only the window needs to be provided.
        New-CompareView -Window $window
    } catch {
        Write-Warning "Failed to load compare module: $($_.Exception.Message)"
    }
} else {
    Write-Warning "CompareViewModule not found at $compareModulePath"
}

# Hook up ShowCisco and ShowBrocade buttons to copy show command sequences
$showCiscoBtn   = $window.FindName('ShowCiscoButton')
$showBrocadeBtn = $window.FindName('ShowBrocadeButton')
$brocadeOSDD    = $window.FindName('BrocadeOSDropdown')

if ($showCiscoBtn) {
    $showCiscoBtn.Add_Click({
        # Build a list of Cisco show commands.  Prepend a command to
        # disable pagination so the output is not interrupted.  Adjust
        # commands as needed to collect all relevant information.
        $cmds = @(
            'terminal length 0',
            'show version',
            'show running-config',
            'show interfaces status',
            'show mac address-table',
            'show spanning-tree',
            'show lldp neighbors',
            'show cdp neighbors',
            'show dot1x all',
            'show access-lists'
        )
        $text = $cmds -join "`r`n"
        Set-Clipboard -Value $text
        [System.Windows.MessageBox]::Show("Cisco show commands copied to clipboard.")
    })
}

if ($showBrocadeBtn) {
    $showBrocadeBtn.Add_Click({
        # Determine the selected OS version from dropdown; default to first item
        $osVersion = 'v8.0.30'
        if ($brocadeOSDD -and $brocadeOSDD.SelectedItem) {
            $osVersion = $brocadeOSDD.SelectedItem.Content
        }
        # Build common Brocade commands.  Use skip-page to disable paging.
        $cmds = @(
            'skip-page',
            'show version',
            'show config',
            'show interfaces brief',
            'show mac-address',
            'show spanning-tree',
            'show lldp neighbors',
            'show cdp neighbors',
            'show dot1x sessions all',
            'show mac-authentication sessions all',
            'show access-lists'
        )
        # Some OS versions might require variant commands.  For example, version
        # 8.0.95 (jufi) may include stack information.  Add extra commands
        # when that version is selected.
        if ($osVersion -eq 'v8.0.95') {
            $cmds += 'show stacking',
                     'show vlan'
        }
        $text = $cmds -join "`r`n"
        Set-Clipboard -Value $text
        [System.Windows.MessageBox]::Show("Brocade show commands for $osVersion copied to clipboard.")
    })
}

# Help button: open the help window when clicked.
$helpBtn = $window.FindName('HelpButton')
if ($helpBtn) {
    $helpBtn.Add_Click({
        $helpXamlPath = Join-Path $scriptDir '..\Views\HelpWindow.xaml'
        if (-not (Test-Path $helpXamlPath)) {
            [System.Windows.MessageBox]::Show('Help file not found.')
            return
        }
        try {
            $helpXaml   = Get-Content $helpXamlPath -Raw
            $helpReader = New-Object System.Xml.XmlTextReader (New-Object System.IO.StringReader($helpXaml))
            $helpWin    = [Windows.Markup.XamlReader]::Load($helpReader)
            # Set owner so the help window centres relative to main window
            $helpWin.Owner = $window
            $helpWin.ShowDialog() | Out-Null
        } catch {
            [System.Windows.MessageBox]::Show("Failed to load help: $($_.Exception.Message)")
        }
    })
}

# 7) Load initial state after window shows
$window.Add_Loaded({
    try {
        # Set the database path environment variable before running the parser
        if ($global:StateTraceDb) { $env:StateTraceDbPath = $global:StateTraceDb }
        & "$parserScript"
        Get-DeviceSummaries
        if ($window.FindName('HostnameDropdown').Items.Count -gt 0) {
            $first = $window.FindName('HostnameDropdown').Items[0]
            Get-DeviceDetails $first
            if (Get-Command Load-SpanInfo -ErrorAction SilentlyContinue) {
                Load-SpanInfo $first
            }
        }
    } catch {
        [System.Windows.MessageBox]::Show("Log parsing failed:`n$($_.Exception.Message)", "Error")
    }
})


if ($window.FindName('HostnameDropdown').Items.Count -gt 0) {
    $first = $window.FindName('HostnameDropdown').Items[0]
    Get-DeviceDetails $first
    if (Get-Command Load-SpanInfo -ErrorAction SilentlyContinue) {
        Load-SpanInfo $first
    }
}

# 8) Show window
$window.ShowDialog() | Out-Null

# 9) Cleanup
$parsedDir = Join-Path $scriptDir '..\ParsedData'
if (Test-Path $parsedDir) {
    try { Get-ChildItem $parsedDir -Recurse | Remove-Item -Force -Recurse }
    catch { Write-Warning "Failed to clear ParsedData: $_" }
}
