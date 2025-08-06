param(
    [string]$Switch1,
    [string]$Interface1,
    [string]$Switch2,
    [string]$Interface2
)

Add-Type -AssemblyName PresentationFramework


# Determine project root and parsed‑data path.  `$PSScriptRoot` points to
# `StateTrace/Main`, so its parent holds `ParsedData` and `Templates`.  We
# compute these paths once and reuse them throughout this script instead of
# relying on relative paths that assume ParsedData lives in the Main folder.
$projectRoot    = Split-Path -Parent $PSScriptRoot
$parsedDataPath = Join-Path $projectRoot 'ParsedData'

# In earlier versions of this tool the parsed interface and summary data were
# stored as CSV files in the ParsedData folder.  As of the database
# transition, configuration and summary information is persisted in the
# Access database.  Import the DatabaseModule here so that the script can
# execute queries when `$global:StateTraceDb` is defined.  If the module
# cannot be found we silently continue and fall back to any CSV files on disk.
#
# Join-Path accepts only two segments (Path and ChildPath) per invocation.  To
# build a path with more than two segments, we nest calls rather than pass
# three positional arguments.  See: https://learn.microsoft.com/powershell/
# module/microsoft.powershell.management/join-path?view=powershell-7.3
$dbModulePath = Join-Path -Path (Join-Path -Path $projectRoot -ChildPath 'Modules') -ChildPath 'DatabaseModule.psm1'
if (Test-Path $dbModulePath) {
    try {
        # Import the DatabaseModule globally so Invoke-DbQuery is available throughout the session
        Import-Module $dbModulePath -Force -Global -ErrorAction Stop
    } catch {
        # Use a subexpression to terminate the variable expansion before the colon.
        Write-Warning "Failed to import database module from $($dbModulePath): $($_.Exception.Message)"
    }
}

# ---------------------------------------------------------------------------
# Automatically locate the StateTrace database if it exists.  In earlier
# versions of this script, the caller (e.g. MainWindow.ps1) set
# `$global:StateTraceDb` before loading CompareConfigs.ps1.  When run
# standalone there is no such variable, causing the script to fall back to
# legacy CSV files.  To support direct execution, detect an existing
# database in the project's Data folder and assign its path to
# `$global:StateTraceDb` if it is currently unset.  Prefer the modern
# `.accdb` format over `.mdb` if both are present.  If neither file
# exists and the DatabaseModule is available, attempt to create a new
# database at the default `.accdb` location.  Otherwise do nothing and
# allow the CSV fallback logic to engage.
if (-not $global:StateTraceDb -or [string]::IsNullOrWhiteSpace($global:StateTraceDb)) {
    $dataDir  = Join-Path $projectRoot 'Data'
    $accdbPath = Join-Path $dataDir 'StateTrace.accdb'
    $mdbPath   = Join-Path $dataDir 'StateTrace.mdb'
    if (Test-Path $accdbPath) {
        $global:StateTraceDb = $accdbPath
    } elseif (Test-Path $mdbPath) {
        $global:StateTraceDb = $mdbPath
    } else {
        # If the DatabaseModule is loaded and New-AccessDatabase is available,
        # attempt to create a new `.accdb` database.  Catch any errors and
        # continue silently so that the script can still operate in CSV mode.
        if (Get-Command -Name New-AccessDatabase -ErrorAction SilentlyContinue) {
            try {
                $global:StateTraceDb = New-AccessDatabase -Path $accdbPath
            } catch {
                # Wrap $accdbPath in a subexpression to avoid treating the colon after the drive letter as part of the variable name.
                Write-Warning "Could not create a new StateTrace database at $($accdbPath): $($_.Exception.Message). Falling back to CSV files."
            }
        }
    }
}

# Emit a debug message indicating whether a database will be used.  When running
# interactively this helps diagnose why the device lists may appear empty in
# the GUI.  Use Write-Host rather than Write-Warning so that informational
# messages are clearly distinguished from errors.
if ($global:StateTraceDb) {
    Write-Host "[DEBUG] Using StateTrace database at: $($global:StateTraceDb)" -ForegroundColor Cyan
} else {
    Write-Host "[DEBUG] No StateTrace database found; using CSV fallback." -ForegroundColor Yellow
}

# -- Helpers --

function Get-GlobalAuthLines {
    [CmdletBinding()]
    param([string]$switch)
    # When using the database back‑end we may still need to provide global
    # authentication lines for Brocade or Arista devices.  The database does not
    # persist the AuthBlock, so attempt to reconstruct it from the extracted
    # log file.  Otherwise, fall back to returning an empty array.
    if ($global:StateTraceDb) {
        try {
            # Determine vendor for this switch via DeviceSummary.Make.  If the
            # Make contains "brocade" or "arista", we treat it as a Brocade‑style
            # device and attempt to extract the authentication block from the
            # raw log.  Use a case‑insensitive match.
            $escSwitch = $switch -replace "'", "''"
            $dtMake = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql "SELECT Make FROM DeviceSummary WHERE Trim(Hostname) = '$escSwitch'"
            $make = if ($dtMake -and $dtMake.Rows.Count -gt 0) { '' + $dtMake[0].Make } else { '' }
            if ($make -match '(?i)brocade|arista') {
                # Use a helper to read the Authentication block from the extracted log file
                $lines = Get-BrocadeGlobalAuthLines -switch $switch
                if ($lines) { return $lines }
            }
        } catch {
            # Ignore errors and fall through to default
        }
        return @()
    }
    # Legacy CSV fallback: if no database is present, attempt to read from the
    # summary CSV.  Historically the AuthBlock was stored in the summary
    # file.  This branch is kept for backward compatibility with CSV data.
    $summaryCsv = Join-Path $parsedDataPath "${switch}_Summary.csv"
    if (Test-Path $summaryCsv) {
        try {
            $block = (Import-Csv $summaryCsv | Select-Object -First 1).AuthBlock
            if ($block) { return $block -split "`n" }
        } catch {}
    }
    return @()
}

function Test-PortInRange {
    param(
        [string]$Port,       # e.g. "Et1/1/12"
        [string]$RangeStr    # e.g. "1/1/9 to 1/1/12, 1/1/14 to 1/1/15"
    )

    # Normalize the port ("Et1/1/12" → "1/1/12") and split into ints
    $p = $Port -replace '^[A-Za-z]+',''
    $pInts = ($p -split '/') | ForEach-Object { [int]$_ }

    # Split on commas to handle multiple ranges
    $ranges = $RangeStr -split ','

    foreach ($r in $ranges) {
        $seg = $r.Trim()

        # If it’s a range “X to Y”
        if ($seg -match '^\s*(.+)\s+to\s+(.+)\s*$') {
            $start = $matches[1]
            $end   = $matches[2]

            $sInts = ($start -split '/') | ForEach-Object { [int]$_ }
            $eInts = ($end   -split '/') | ForEach-Object { [int]$_ }

            if ($pInts[0] -eq $sInts[0] -and
                $pInts[1] -eq $sInts[1] -and
                $pInts[2] -ge $sInts[2] -and
                $pInts[2] -le $eInts[2]) {
                return $true
            }
        }
        else {
            # Single-port case
            if ($seg -eq $p) {
                return $true
            }
        }
    }

    return $false
}

# -- Load all JSON templates --
# The templates folder lives one directory above this script (e.g. StateTrace\Templates),
# not inside the Main folder.  We use `$projectRoot` computed at the top of the
# script to construct this path.
$templatesFolder = Join-Path $projectRoot 'Templates'
if (-not (Test-Path $templatesFolder)) {
    throw "Templates folder not found: $templatesFolder"
}
$allTemplates = @()
Get-ChildItem $templatesFolder -Filter '*.json' | ForEach-Object {
    $json = Get-Content $_.FullName -Raw | ConvertFrom-Json
    if ($json.templates) { $allTemplates += $json.templates }
}

# -- Load XAML GUI --
$xamlPath    = Join-Path $PSScriptRoot 'CompareWindow.xaml'
$cmpWin      = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlTextReader (New-Object System.IO.StringReader((Get-Content $xamlPath -Raw)))))

# -- Helper to read the global authentication block for Brocade/Arista devices --
function Get-BrocadeGlobalAuthLines {
    [CmdletBinding()]
    param([string]$switch)
    # Attempt to locate the extracted log file for this host.  The extracted logs
    # live in the Logs\Extracted folder at the project root and are named
    # <hostname>.log.  Use a case‑insensitive comparison because Windows file
    # systems are typically case‑insensitive.  If the exact file isn't found,
    # fall back to scanning the directory for a matching basename.
    # Build the path to the extracted logs folder.  Use nested Join-Path
    # calls rather than piping into Join-Path to avoid unexpected pipeline
    # behaviour.
    $logDir = Join-Path -Path $projectRoot -ChildPath 'Logs'
    $logDir = Join-Path -Path $logDir    -ChildPath 'Extracted'
    $candidate = Join-Path $logDir "$switch.log"
    if (-not (Test-Path $candidate)) {
        try {
            $matches = Get-ChildItem -Path $logDir -Filter '*.log' -ErrorAction SilentlyContinue | Where-Object { $_.BaseName -ieq $switch }
            if ($matches -and $matches.Count -gt 0) { $candidate = $matches[0].FullName }
        } catch {}
    }
    if (-not (Test-Path $candidate)) {
        return @()
    }
    try {
        # Read the file content.  Use -Raw for efficiency.  Split into lines
        # manually to handle both LF and CRLF line endings.  Trim each line.
        $content = Get-Content -Path $candidate -Raw -ErrorAction Stop
        $lines   = $content -split "`r?`n"
        $buffer  = @()
        $inside  = $false
        foreach ($line in $lines) {
            if (-not $inside) {
                if ($line -match '^Authentication\s*$') {
                    $inside = $true
                    continue
                }
            } else {
                if ($line -match '^!') {
                    break
                }
                $buffer += $line.Trim()
            }
        }
        return $buffer
    } catch {
        # If reading or parsing fails, return an empty array rather than throwing
        return @()
    }
}

# -- Template matching function --
function Get-PortTemplate {
    param (
        [string[]]$ConfigLines,
        [object[]]$Templates,
        [string]$Port,
        [string]$Vendor
    )
    $norm = $ConfigLines | ForEach-Object { $_.Trim().ToLower() }

    foreach ($t in $Templates) {
        # filter by vendor
        if ($t.vendor.ToLower() -ne $Vendor.ToLower()) { continue }

        $req = $t.required_commands
        $ex  = if ($t.PSObject.Properties.Match('excluded_commands')) { $t.excluded_commands } else { @() }
        $have = @()

        foreach ($cmd in $req) {
            switch ($cmd) {
                'dot1x enable' {
                    # Only count if in a range: ignore bare global 'dot1x enable'
                    $lines = $norm | Where-Object { $_ -like 'dot1x enable ethe*' }
                    foreach ($l in $lines) {
                        $range = $l.Substring('dot1x enable ethe'.Length).Trim()
                        if (Test-PortInRange -Port $Port -RangeStr $range) { $have += $cmd; break }
                    }
                }
                'dot1x port-control auto' {
                    # interface-level
                    if ($norm -contains 'dot1x port-control auto') { $have += $cmd; break }
                    # global-range
                    $lines = $norm | Where-Object { $_ -like 'dot1x port-control auto ethe*' }
                    foreach ($l in $lines) {
                        $range = $l.Substring('dot1x port-control auto ethe'.Length).Trim()
                        if (Test-PortInRange -Port $Port -RangeStr $range) { $have += $cmd; break }
                    }
                }
                default {
                    if ($cmd -match '\bethe$') {
                        # range-based command
                        $lines = $norm | Where-Object { $_ -like "$cmd*" }
                        foreach ($l in $lines) {
                            $range = $l.Substring($cmd.Length).Trim()
                            if (Test-PortInRange -Port $Port -RangeStr $range) { $have += $cmd; break }
                        }
                    }
                    else {
                        # simple prefix match
                        if ($norm | Where-Object { $_ -like "$cmd*" }) { $have += $cmd }
                    }
                }
            }
        }

        # excluded commands
        $bad = @()
        foreach ($cmd in $ex) {
            if ($cmd -eq 'dot1x port-control auto') {
                # only exclude if interface‐level or in the port's range
                if ($norm -contains 'dot1x port-control auto') {
                    $bad += $cmd
                    continue
                }
                $lines = $norm | Where-Object { $_ -like 'dot1x port-control auto ethe*' }
                foreach ($l in $lines) {
                    $range = $l.Substring('dot1x port-control auto ethe'.Length).Trim()
                    if (Test-PortInRange -Port $Port -RangeStr $range) {
                        $bad += $cmd
                        break
                    }
                }
            }
            elseif ($cmd -eq 'dot1x enable') {
                # only exclude if truly in range
                $lines = $norm | Where-Object { $_ -like 'dot1x enable ethe*' }
                foreach ($l in $lines) {
                    $range = $l.Substring('dot1x enable ethe'.Length).Trim()
                    if (Test-PortInRange -Port $Port -RangeStr $range) {
                        $bad += $cmd
                        break
                    }
                }
            }
            elseif ($cmd -match '\bethe$') {
                # generic range‐based exclusion
                $lines = $norm | Where-Object { $_ -like "$cmd*" }
                foreach ($l in $lines) {
                    $range = $l.Substring($cmd.Length).Trim()
                    if (Test-PortInRange -Port $Port -RangeStr $range) {
                        $bad += $cmd
                        break
                    }
                }
            }
            else {
                # plain prefix exclusion
                if ($norm | Where-Object { $_ -like "$cmd*" }) {
                    $bad += $cmd
                }
            }
        }

        if ($have.Count -eq $req.Count -and $bad.Count -eq 0) { return $t }
    }
    return $null
}

# -- GUI Label Setter --
function Set-TemplateLabel {
    param($Label, $Template)
    if ($Template) {
        $Label.Text       = "Template: $($Template.name)"
        $Label.Foreground = $Template.color
    } else {
        $Label.Text       = "Template: Non-compliant/Unknown"
        $Label.Foreground = 'Red'
    }
}

# -- Load, Merge & Apply Template --
function Load-ConfigAndTemplate {
    param (
        [string]$switch,
        [string]$intf,
        [string]$configBox,
        [string]$labelBox,
        [ref]$configLines
    )
    # When a database is present, read the configuration and template directly
    # from the Interfaces table.  Otherwise fall back to reading the legacy
    # CSV file stored in the ParsedData folder.
    if ($global:StateTraceDb) {
        try {
            # Escape any single quotes in the host and port values for SQL safety
            $escSwitch = $switch -replace "'", "''"
            $escPort   = $intf   -replace "'", "''"
            # Convert host to uppercase and remove spaces.  Many logs include spaces within
            # interface or hostnames (e.g. "Gi 1/0/4").  We'll perform port matching in
            # PowerShell after retrieving all rows for the host.  Build a SQL statement
            # that selects all ports/configs for the given host, normalized by trimming
            # whitespace and control characters and upper‑casing.
            $escSwitchUpper  = $escSwitch.ToUpper()
            $escSwitchNoSpace = $escSwitchUpper -replace ' ', ''
            $sqlAll = "SELECT Port, Config, AuthTemplate FROM Interfaces WHERE UCASE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(Trim(Hostname),' ',''), Chr(13),''), Chr(10),''), Chr(9),''), Chr(160),'')) = '$escSwitchNoSpace'"
            Write-Host "[DEBUG] Interface lookup SQL: $sqlAll" -ForegroundColor Gray
            $dt = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql $sqlAll
            # Normalize the selected interface by removing all whitespace characters and upper‑casing
            $targetPort = ($intf -replace '\s','').ToUpper()
            $matchRow = $null
            $rowCount = if ($dt -and $dt.Rows) { $dt.Rows.Count } else { 0 }
            if ($dt) {
                foreach ($row in $dt) {
                    $dbPort = $row.Port
                    if ($dbPort -ne $null) {
                        # Remove all whitespace from the database value (space, tab, CR, LF)
                        $normDbPort = ($dbPort -replace '\s','').ToUpper()
                        if ($normDbPort -eq $targetPort) {
                            $matchRow = $row
                            break
                        }
                    }
                }
            }
            Write-Host "[DEBUG] Load-ConfigAndTemplate: fetched $rowCount rows for host $switch; normalized target port='$targetPort'; match found=$([bool]$matchRow)" -ForegroundColor Gray
            if ($matchRow) {
                $cfgText    = $matchRow.Config
                $ifaceLines = if ($cfgText) { $cfgText -split "`n" } else { @() }
                $globalLines = Get-GlobalAuthLines -switch $switch
                $merged = $ifaceLines + $globalLines
                $cmpWin.FindName($configBox).Text = $merged -join "`n"
                $configLines.Value = $merged
                # Determine the vendor based on the device make stored in the summary table.
                $vendor = 'Cisco'
                try {
                    $dtMake = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql "SELECT Make FROM DeviceSummary WHERE Trim(Hostname) = '$escSwitch'"
                    if ($dtMake -and $dtMake.Rows.Count -gt 0) {
                        $mk = $dtMake[0].Make
                        if ($mk -match '(?i)brocade') { $vendor = 'Brocade' }
                    }
                } catch {}
                $tpl = Get-PortTemplate -ConfigLines $merged -Templates $allTemplates -Port $intf -Vendor $vendor
                Set-TemplateLabel -Label ($cmpWin.FindName($labelBox)) -Template $tpl
                return
            }
        } catch {
            # Wrap switch and interface variables in subexpressions to ensure the trailing colon is not
            # parsed as part of the variable name when constructing the warning message.
            Write-Warning "Error reading interface data from database for $($switch)/$($intf): $($_.Exception.Message)"
        }
        # If no row was returned or an error occurred, indicate the interface is not found
        $cmpWin.FindName($configBox).Text       = "Interface $intf not found."
        $cmpWin.FindName($labelBox).Text        = "Template: N/A"
        $cmpWin.FindName($labelBox).Foreground = 'Red'
        $configLines.Value = @()
        return
    }

    # Legacy fallback: read from CSV
    $ifaceCsv = Join-Path $parsedDataPath "${switch}_Interfaces_Combined.csv"
    if (-not (Test-Path $ifaceCsv)) {
        $cmpWin.FindName($configBox).Text       = "Interface $intf not found."
        $cmpWin.FindName($labelBox).Text        = "Template: N/A"
        $cmpWin.FindName($labelBox).Foreground = 'Red'
        $configLines.Value = @()
        return
    }
    try {
        $row = Import-Csv $ifaceCsv | Where-Object Port -eq $intf
        if ($row) {
            $ifaceLines  = if ($row.Config) { $row.Config -split "`n" } else { @() }
            $globalLines = Get-GlobalAuthLines -switch $switch
            $merged      = $ifaceLines + $globalLines
            $cmpWin.FindName($configBox).Text = $merged -join "`n"
            $configLines.Value = $merged
            # detect vendor based on presence of global auth lines (Brocade stores global auth in AuthBlock)
            $Vendor = if ($globalLines.Count -gt 0) { 'Brocade' } else { 'Cisco' }
            $tpl = Get-PortTemplate -ConfigLines $merged -Templates $allTemplates -Port $intf -Vendor $Vendor
            Set-TemplateLabel -Label ($cmpWin.FindName($labelBox)) -Template $tpl
            return
        }
    } catch {
        # ignore and fall through
    }
    $cmpWin.FindName($configBox).Text       = "Interface $intf not found."
    $cmpWin.FindName($labelBox).Text        = "Template: N/A"
    $cmpWin.FindName($labelBox).Foreground = 'Red'
    $configLines.Value = @()
}

# -- Diff Helper --
function Get-ConfigDiff {
    param($base, $compare)
    $b = $base    | ForEach-Object { $_.Trim() }
    $c = $compare | ForEach-Object { $_.Trim() }
    return $c | Where-Object { $_ -and ($_ -notin $b) }
}

# -- GUI Dropdowns & Events --
function Load-SwitchList {
    [CmdletBinding()]
    param()
    # When a database is available, retrieve the list of hostnames from
    # DeviceSummary.  Fall back to scanning any remaining CSV files if the
    # database is not yet initialized (for example, during development).
    if ($global:StateTraceDb) {
        try {
            $dt = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql "SELECT Hostname FROM DeviceSummary ORDER BY Hostname"
            # Emit debug information about how many devices were returned.  The DataTable
            # type exposes a Rows collection.  Protect against null for robustness.
            $rowCount = if ($dt -and $dt.Rows) { $dt.Rows.Count } else { 0 }
            Write-Host "[DEBUG] Load-SwitchList: retrieved $rowCount hostnames from database." -ForegroundColor Gray
            return ($dt | ForEach-Object { $_.Hostname })
        } catch {
            Write-Warning "Failed to query device list from database: $($_.Exception.Message)"
        }
    }
    # Legacy fallback: list CSV summaries
    if (Test-Path $parsedDataPath) {
        $namesCsv = (Get-ChildItem $parsedDataPath -Filter '*_Summary.csv' | ForEach-Object { $_.BaseName -replace '_Summary$','' })
        Write-Host "[DEBUG] Load-SwitchList: loaded $($namesCsv.Count) hostnames from CSV files." -ForegroundColor Gray
        return $namesCsv
    }
    return @()
}
function Load-PortList {
    [CmdletBinding()]
    param([string]$switch)
    # When using the database, query the Interfaces table for ports
    if ($global:StateTraceDb) {
        try {
            $escaped = $switch -replace "'", "''"
            $escapedUpper = $escaped.ToUpper()
            $dt = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql "SELECT Port FROM Interfaces WHERE UCASE(Trim(Hostname)) = '$escapedUpper' ORDER BY Port"
            # Emit debug information about how many ports were returned for this host
            $rowCount = if ($dt -and $dt.Rows) { $dt.Rows.Count } else { 0 }
            # Show a few example port names to aid debugging of matching issues
            $portsArray = @()
            $samplePorts = @()
            if ($dt) {
                $portsArray  = ($dt | ForEach-Object { $_.Port })
                $samplePorts = ($portsArray | Select-Object -First 5) -join ', '
            }
            Write-Host "[DEBUG] Load-PortList: retrieved $rowCount ports for $switch from database. Sample: $samplePorts" -ForegroundColor Gray
            # List all ports for further debugging
            if ($portsArray) {
                # Use a subexpression around the variable before the colon to avoid PowerShell
                # interpreting the colon as part of a drive-qualified variable name.  This
                # prevents errors like "Variable reference is not valid. ':' was not
                # followed by a valid variable name character".  Compose the message
                # explicitly using a formatted string to ensure safe expansion.
                $allPortsString = $portsArray -join ', '
                Write-Host ("[DEBUG] All ports for {0}: {1}" -f $switch, $allPortsString) -ForegroundColor DarkGray
            }
            return ($dt | ForEach-Object { $_.Port })
        } catch {
            # Use subexpression to properly terminate the variable expansion before the colon.
            Write-Warning "Failed to query ports for switch $($switch): $($_.Exception.Message)"
            return @()
        }
    }
    # Legacy fallback: read remaining CSV if present
    $path = Join-Path $parsedDataPath "${switch}_Interfaces_Combined.csv"
    if (Test-Path $path) {
        try {
            $rows = Import-Csv $path
            Write-Host "[DEBUG] Load-PortList: loaded $($rows.Count) ports for $switch from CSV." -ForegroundColor Gray
            return $rows.Port
        } catch {
            return @()
        }
    }
    return @()
}

$switches = Load-SwitchList
$cmpWin.FindName('Switch1Dropdown').ItemsSource = $switches
$cmpWin.FindName('Switch2Dropdown').ItemsSource = $switches

if ($Switch1 -and $switches -contains $Switch1) {
    $cmpWin.FindName('Switch1Dropdown').SelectedItem = $Switch1
    $cmpWin.FindName('Port1Dropdown').ItemsSource   = Load-PortList $Switch1
    if ($Interface1) { $cmpWin.FindName('Port1Dropdown').SelectedItem = $Interface1 }
}
if ($Switch2 -and $switches -contains $Switch2) {
    $cmpWin.FindName('Switch2Dropdown').SelectedItem = $Switch2
    $cmpWin.FindName('Port2Dropdown').ItemsSource   = Load-PortList $Switch2
    if ($Interface2) { $cmpWin.FindName('Port2Dropdown').SelectedItem = $Interface2 }
}

$cmpWin.FindName('Switch1Dropdown').Add_SelectionChanged({
    $sw = $_.Source.SelectedItem
    $cmpWin.FindName('Port1Dropdown').ItemsSource  = Load-PortList $sw
    # Select the first port safely via SelectedItem rather than SelectedIndex.  This
    # avoids unintentionally assigning to the built‑in $Host variable.
    $portDD = $cmpWin.FindName('Port1Dropdown')
    if ($portDD.ItemsSource -and $portDD.ItemsSource.Count -gt 0) {
        $portDD.SelectedItem = $portDD.ItemsSource[0]
    } else {
        $portDD.SelectedItem = $null
    }
})
$cmpWin.FindName('Switch2Dropdown').Add_SelectionChanged({
    $sw = $_.Source.SelectedItem
    $cmpWin.FindName('Port2Dropdown').ItemsSource  = Load-PortList $sw
    # Select the first port safely via SelectedItem rather than SelectedIndex.
    $portDD2 = $cmpWin.FindName('Port2Dropdown')
    if ($portDD2.ItemsSource -and $portDD2.ItemsSource.Count -gt 0) {
        $portDD2.SelectedItem = $portDD2.ItemsSource[0]
    } else {
        $portDD2.SelectedItem = $null
    }
})
$cmpWin.FindName('Port1Dropdown').Add_SelectionChanged({ Refresh-ConfigState })
$cmpWin.FindName('Port2Dropdown').Add_SelectionChanged({ Refresh-ConfigState })

function Refresh-ConfigState {
    $sw1  = $cmpWin.FindName('Switch1Dropdown').SelectedItem
    $int1 = $cmpWin.FindName('Port1Dropdown').SelectedItem
    $sw2  = $cmpWin.FindName('Switch2Dropdown').SelectedItem
    $int2 = $cmpWin.FindName('Port2Dropdown').SelectedItem

    if ($sw1 -and $int1 -and $sw2 -and $int2) {
        $tmp1 = @(); $tmp2 = @()
        Load-ConfigAndTemplate -switch $sw1 -intf $int1 -configBox 'Config1Box' -labelBox 'Template1Label' -configLines ([ref]$tmp1)
        Load-ConfigAndTemplate -switch $sw2 -intf $int2 -configBox 'Config2Box' -labelBox 'Template2Label' -configLines ([ref]$tmp2)
        $cmpWin.FindName('Config1DeltaBox').Text = (Get-ConfigDiff -base $tmp2 -compare $tmp1) -join "`n"
        $cmpWin.FindName('Config2DeltaBox').Text = (Get-ConfigDiff -base $tmp1 -compare $tmp2) -join "`n"
    }
}

# -- Launch GUI --
Refresh-ConfigState
$cmpWin.ShowDialog() | Out-Null
