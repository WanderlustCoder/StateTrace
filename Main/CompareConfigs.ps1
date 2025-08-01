param(
    [string]$Switch1,
    [string]$Interface1,
    [string]$Switch2,
    [string]$Interface2
)

Add-Type -AssemblyName PresentationFramework

# Determine project root and parsed-data path.  `$PSScriptRoot` points to
# `StateTrace/Main`, so its parent holds `ParsedData` and `Templates`.  We compute
# these paths once and reuse them throughout this script instead of relying on
# relative paths that assume ParsedData lives in the Main folder.
$projectRoot    = Split-Path -Parent $PSScriptRoot
$parsedDataPath = Join-Path $projectRoot 'ParsedData'

# -- Helpers --

function Get-GlobalAuthLines {
    param([string]$switch)
    # Look up the summary CSV in the project-level ParsedData folder
    $summaryCsv = Join-Path $parsedDataPath "${switch}_Summary.csv"
    if (Test-Path $summaryCsv) {
        $block = (Import-Csv $summaryCsv | Select-Object -First 1).AuthBlock
        if ($block) { return $block -split "`n" }
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
    # Use the project-level ParsedData folder when locating interface CSVs
    $ifaceCsv = Join-Path $parsedDataPath "${switch}_Interfaces_Combined.csv"
    if (-not (Test-Path $ifaceCsv)) {
        $cmpWin.FindName($configBox).Text       = "Interface $intf not found."
        $cmpWin.FindName($labelBox).Text        = "Template: N/A"
        $cmpWin.FindName($labelBox).Foreground = 'Red'
        $configLines.Value = @()
        return
    }

    $row = Import-Csv $ifaceCsv | Where-Object Port -eq $intf

    if ($row) {
        $ifaceLines  = if ($row.Config) { $row.Config -split "`n" } else { @() }
        $globalLines = Get-GlobalAuthLines -switch $switch
        $merged      = $ifaceLines + $globalLines

        $cmpWin.FindName($configBox).Text = $merged -join "`n"
        $configLines.Value = $merged

        # detect vendor
        $Vendor = if ($globalLines.Count -gt 0) { 'Brocade' } else { 'Cisco' }

        $tpl = Get-PortTemplate -ConfigLines $merged -Templates $allTemplates -Port $intf -Vendor $Vendor
        Set-TemplateLabel -Label ($cmpWin.FindName($labelBox)) -Template $tpl
        return
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
    Get-ChildItem $parsedDataPath -Filter '*_Summary.csv' |
      ForEach-Object { $_.BaseName -replace '_Summary$','' }
}
function Load-PortList {
    param([string]$switch)
    $path = Join-Path $parsedDataPath "${switch}_Interfaces_Combined.csv"
    if (Test-Path $path) {
        return (Import-Csv $path).Port
    } else {
        return @()
    }
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
    $cmpWin.FindName('Port1Dropdown').SelectedIndex = 0
})
$cmpWin.FindName('Switch2Dropdown').Add_SelectionChanged({
    $sw = $_.Source.SelectedItem
    $cmpWin.FindName('Port2Dropdown').ItemsSource  = Load-PortList $sw
    $cmpWin.FindName('Port2Dropdown').SelectedIndex = 0
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
