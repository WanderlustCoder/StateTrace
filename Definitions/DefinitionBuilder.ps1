Add-Type -AssemblyName PresentationFramework

<#
  DefinitionBuilder.ps1
  GUI for building JSON definitions to parse switch logs.
#>

function Get-ShowCommandBlocks {
    param([string[]]$Lines)
    $blocks = @{}; $current = ''; $buffer = @(); $recording = $false
    foreach ($l in $Lines) {
        if ($l -match '^(?:\S+)[#>]+\s*(show .+)$') {
            if ($recording -and $current) { $blocks[$current] = $buffer }
            $current   = $matches[1].ToLower().Trim()
            $buffer    = @(); $recording = $true
        }
        elseif ($recording -and $l -match '^(?:\S+)[#>]+\s*$') {
            $blocks[$current] = $buffer; $buffer = @(); $recording = $false; $current = ''
        }
        elseif ($recording) {
            $buffer += $l
        }
    }
    if ($recording -and $current) { $blocks[$current] = $buffer }
    return $blocks
}

function Convert-ToHash {
    param($o)
    if ($null -eq $o) { return $null }
    if ($o -is [PSCustomObject] -or $o -is [System.Collections.IDictionary]) {
        $ht = [ordered]@{}; foreach ($p in $o.PSObject.Properties) { $ht[$p.Name] = Convert-ToHash $p.Value }
        return $ht
    } elseif ($o -is [System.Collections.IEnumerable] -and -not ($o -is [string])) {
        $arr = @(); foreach ($i in $o) { $arr += Convert-ToHash $i }; return $arr
    } else { return $o }
}

function Get-CategoryFromCommand {
    param($cmd)
    switch -Regex ($cmd) {
        '^(show )?interfaces?\b'            { 'interfaces'; break }
        '\bvlan\b'                         { 'network'; break }
        '\b(version|config)\b'            { 'system'; break }
        '\b(dot1x|authentication|mac)\b'  { 'security'; break }
        default                             { 'other' }
    }
}

function Update-CommandList {
    param($make,$model,$os)
    if ($json.Contains($make) -and $json[$make].Contains($model) -and $json[$make][$model].Contains($os) -and ($json[$make][$model][$os] -is [System.Collections.IDictionary])) {
        $CommandListBox.ItemsSource = $json[$make][$model][$os].Keys | Sort-Object
    } else {
        $CommandListBox.ItemsSource = @()
    }
}

function Start-DefinitionBuilderGui {
    # Load XAML
    $xaml = [xml](Get-Content (Join-Path $PSScriptRoot 'DefinitionBuilder.xaml'))
    $form = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))

    # Controls
    $MakeBox = $form.FindName('MakeBox'); $ModelBox = $form.FindName('ModelBox'); $OSBox = $form.FindName('OSBox')
    $CategoryBox = $form.FindName('CategoryBox'); $CommandBox = $form.FindName('CommandBox')
    $ColumnsPreview = $form.FindName('ColumnsPreview'); $OutputPreview = $form.FindName('OutputPreview')
    $DescriptionBox = $form.FindName('DescriptionBox'); $LogListBox = $form.FindName('LogList')
    $CommandListBox = $form.FindName('CommandList'); $SaveButton = $form.FindName('SaveButton')
    $SaveAllButton = $form.FindName('SaveAllButton'); $DetectButton = $form.FindName('DetectButton')
    $ExportButton = $form.FindName('ExportSelectedButton')

    # Load definitions JSON
    $jsonFile = Join-Path $PSScriptRoot 'definitions.json'
    if (Test-Path $jsonFile) {
        $json = Convert-ToHash (Get-Content $jsonFile -Raw | ConvertFrom-Json)
    } else {
        $json = [ordered]@{}
    }

    # Populate log list
    $logDir = Join-Path $PSScriptRoot '..\logs'
    $LogListBox.ItemsSource = (Get-ChildItem -Path $logDir -Filter '*.log' -ErrorAction SilentlyContinue).Name

    # Detect logs
    $DetectButton.Add_Click({
        if (-not $LogListBox.SelectedItem) { [Windows.MessageBox]::Show('Select a log file.'); return }
        $MakeBox.Clear(); $ModelBox.Clear(); $OSBox.Clear()
        $CommandBox.ItemsSource = @(); $CommandListBox.ItemsSource = @()
        $ColumnsPreview.Clear(); $OutputPreview.Clear(); $DescriptionBox.Clear()

        $lines = Get-Content (Join-Path $logDir $LogListBox.SelectedItem)
        $blocks = Get-ShowCommandBlocks -Lines $lines
        $CommandBox.ItemsSource = $blocks.Keys | Sort-Object
        $CommandListBox.ItemsSource = $blocks.Keys | Sort-Object
        $form.Tag = @{ blocks = $blocks; cols = @() }

        if ($lines -match '(?i)cisco') { $MakeBox.Text = 'Cisco' }
        elseif ($lines -match '(?i)brocade') { $MakeBox.Text = 'Brocade' }

        if ($MakeBox.Text -eq 'Cisco') {
            $v = $lines | Where-Object { $_ -match '^(?i)version\s+([\d\.]+)' } | Select-Object -First 1
            if ($v -match 'version\s+([\d\.]+)') { $OSBox.Text = $matches[1] }
            $m = $lines | Where-Object { $_ -match '(?i)model number\s*:\s*(\S+)' } | Select-Object -First 1
            if ($m -match 'model number\s*:\s*(\S+)') { $ModelBox.Text = $matches[1] }
        } else {
            $s = $lines | Where-Object { $_ -match 'SW:\s+Version\s+(\S+)' } | Select-Object -First 1
            if ($s -match 'SW:\s+Version\s+(\S+)') { $OSBox.Text = $matches[1] }
            $r = $lines | Where-Object { $_ -match '^(?i)ver\s+([\w\.\-]+)' } | Select-Object -First 1
            if ($r -match 'ver\s+([\w\.\-]+)') { $OSBox.Text = $matches[1] }
            $h = $lines | Where-Object { $_ -match 'HW:\s+(Stackable\s+\S+)' } | Select-Object -First 1
            if ($h -match 'HW:\s+(Stackable\s+\S+)') { $ModelBox.Text = $matches[1] }
        }

        Update-CommandList $MakeBox.Text.Trim() $ModelBox.Text.Trim() $OSBox.Text.Trim()
    })

    # Column detection helper
    function Get-Columns($lines) {
        $total = $lines.Count
        $kvCount = ($lines | Where-Object { $_ -match '^\s*\S+?:\s+.+$' } | Measure-Object).Count
        if ($total -gt 0 -and $kvCount / $total -gt 0.6) {
            return @('Property','Value')
        }
        $hdr = $lines | Where-Object { $_ -match '\S+\s{2,}\S+' } | Select-Object -First 1
        if ($hdr) {
            return ($hdr -split '\s{2,}') | ForEach-Object { $_.Trim() }
        }
        return @()
    }

    # Show-command selection
    $CommandBox.Add_SelectionChanged({
        $ctx = $form.Tag; $cmd = $CommandBox.SelectedItem
        if ($ctx -and $cmd -and $ctx.blocks.ContainsKey($cmd)) {
            $lines = $ctx.blocks[$cmd]; $OutputPreview.Text = $lines -join "`r`n"
            if ($MakeBox.Text -eq 'Brocade' -and $cmd -like 'show vlan*') {
                $cols = @('ConfigLine')
            } else {
                $cols = Get-Columns $lines
            }
            $ColumnsPreview.Text = $cols -join ', '
            $ctx.cols = $cols
            $CategoryBox.Text = Get-CategoryFromCommand $cmd
        }
    })

    # Save single definition
    $SaveButton.Add_Click({
        $m = $MakeBox.Text.Trim(); $md = $ModelBox.Text.Trim(); $os = $OSBox.Text.Trim()
        $cmd = $CommandBox.SelectedItem; $cat = $CategoryBox.Text.Trim(); $desc = $DescriptionBox.Text.Trim()
        $cols = $form.Tag.cols
        if (-not ($m -and $md -and $os -and $cmd)) { [Windows.MessageBox]::Show('Complete all fields.'); return }
        if (-not $json.Contains($m)) { $json[$m] = [ordered]@{} }
        if (-not $json[$m].Contains($md)) { $json[$m][$md] = [ordered]@{} }
        if (-not ($json[$m][$md][$os] -is [System.Collections.IDictionary])) { $json[$m][$md][$os] = [ordered]@{} }
        $json[$m][$md][$os][$cmd] = [ordered]@{ category=$cat; columns=$cols; description=$desc }
        $json | ConvertTo-Json -Compress | Set-Content $jsonFile -Encoding UTF8
        [Windows.MessageBox]::Show('Definition saved.')
        Update-CommandList $m $md $os
    })

    # Bulk-save all definitions
    if ($SaveAllButton) {
        $SaveAllButton.Add_Click({
            $m = $MakeBox.Text.Trim(); $md = $ModelBox.Text.Trim(); $os = $OSBox.Text.Trim()
            if (-not $form.Tag.blocks) { [Windows.MessageBox]::Show('Parse first.'); return }
            if (-not ($m -and $md -and $os)) { [Windows.MessageBox]::Show('Make/Model/OS missing.'); return }
            if (-not $json.Contains($m)) { $json[$m] = [ordered]@{} }
            if (-not $json[$m].Contains($md)) { $json[$m][$md] = [ordered]@{} }
            if (-not ($json[$m][$md][$os] -is [System.Collections.IDictionary])) { $json[$m][$md][$os] = [ordered]@{} }
            foreach ($k in $form.Tag.blocks.Keys) {
                $lines = $form.Tag.blocks[$k]
                if ($MakeBox.Text -eq 'Brocade' -and $k -like 'show vlan*') {
                    $cols = @('ConfigLine')
                } else {
                    $cols = Get-Columns $lines
                }
                $ct = Get-CategoryFromCommand $k
                $json[$m][$md][$os][$k] = [ordered]@{ category=$ct; columns=$cols; description='' }
            }
            $json | ConvertTo-Json -Compress | Set-Content $jsonFile -Encoding UTF8
            [Windows.MessageBox]::Show('All definitions saved.')
            Update-CommandList $m $md $os
        })
    }

    # Export definitions
    $ExportButton.Add_Click({
        $m = $MakeBox.Text.Trim(); $md = $ModelBox.Text.Trim(); $os = $OSBox.Text.Trim()
        if ($json.Contains($m) -and $json[$m].Contains($md) -and $json[$m][$md].Contains($os)) {
            $defs = $json[$m][$md][$os]; $out = [ordered]@{}
            foreach ($c in $defs.Keys) {
                $d = $defs[$c]
                $out[$c] = [ordered]@{ category=$d.category; columns=$d.columns; description=$d.description }
            }
            $file = "export_${m}_${md}_${os}.json"
            $out | ConvertTo-Json -Compress | Set-Content (Join-Path $PSScriptRoot $file) -Encoding UTF8
            [Windows.MessageBox]::Show("Exported to $file")
        } else {
            [Windows.MessageBox]::Show('Nothing to export.')
        }
    })

    # Show GUI
    $form.ShowDialog() | Out-Null
}

Start-DefinitionBuilderGui
