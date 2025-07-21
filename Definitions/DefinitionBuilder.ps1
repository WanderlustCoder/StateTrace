# DefinitionBuilder.ps1
Add-Type -AssemblyName PresentationFramework

function Start-DefinitionBuilderGui {
    $xamlPath = Join-Path -Path $PSScriptRoot -ChildPath "DefinitionBuilder.xaml"
    [xml]$xaml = Get-Content $xamlPath

    $reader = (New-Object System.Xml.XmlNodeReader $xaml)
    $form = [Windows.Markup.XamlReader]::Load($reader)

    $MakeBox        = $form.FindName("MakeBox")
    $ModelBox       = $form.FindName("ModelBox")
    $OSBox          = $form.FindName("OSBox")
    $CategoryBox    = $form.FindName("CategoryBox")
    $RegexBox       = $form.FindName("RegexBox")
    $CommandBox     = $form.FindName("CommandBox")
    $SaveButton     = $form.FindName("SaveButton")
    $OutputPreview  = $form.FindName("OutputPreview")
    $LogListBox     = $form.FindName("LogList")
    $CommandListBox = $form.FindName("CommandList")
    $BulkButton     = $form.FindName("BulkLoadButton")
    $DetectButton   = $form.FindName("DetectButton")
    $LoadSelectedButton = $form.FindName("LoadSelectedButton")
    $DeleteSelectedButton = $form.FindName("DeleteSelectedButton")
    $ExportSelectedButton = $form.FindName("ExportSelectedButton")

    $jsonFile = Join-Path $PSScriptRoot 'definitions.json'
    if (Test-Path $jsonFile) {
        $json = Get-Content $jsonFile -Raw | ConvertFrom-Json
        $MakeBox.ItemsSource = $json.PSObject.Properties.Name
        $ModelBox.ItemsSource = $json.PSObject.Properties.Value | ForEach-Object { $_.PSObject.Properties.Name } | Select-Object -Unique
        $OSBox.ItemsSource = $json.PSObject.Properties.Value | ForEach-Object { $_.PSObject.Properties.Value | ForEach-Object { $_.PSObject.Properties.Name } } | Select-Object -Unique
    } else {
        $json = [ordered]@{}
    }

    $logDir = Join-Path $PSScriptRoot '..\logs'
    $logFiles = Get-ChildItem -Path $logDir -Filter *.log -ErrorAction SilentlyContinue
    $LogListBox.ItemsSource = $logFiles.Name

    function Update-CommandList($make, $model, $os) {
        if (($json.PSObject.Properties.Name -contains $make) -and
            ($json[$make].PSObject.Properties.Name -contains $model) -and
            ($json[$make][$model].PSObject.Properties.Name -contains $os)) {
            $CommandListBox.ItemsSource = $json[$make][$model][$os].PSObject.Properties.Name
        } else {
            $CommandListBox.ItemsSource = @()
        }
    }

    $MakeBox.Add_SelectionChanged({ Update-CommandList $MakeBox.Text.Trim() $ModelBox.Text.Trim() $OSBox.Text.Trim() })
    $ModelBox.Add_SelectionChanged({ Update-CommandList $MakeBox.Text.Trim() $ModelBox.Text.Trim() $OSBox.Text.Trim() })
    $OSBox.Add_SelectionChanged({ Update-CommandList $MakeBox.Text.Trim() $ModelBox.Text.Trim() $OSBox.Text.Trim() })

    $CommandBox.Add_SelectionChanged({
        $selectedCommand = $CommandBox.Text.Trim()
        $selectedLog = $LogListBox.SelectedItem
        $OutputPreview.Clear()
        if ($selectedCommand -and $selectedLog) {
            $file = Get-ChildItem -Path $logDir -Filter $selectedLog
            if ($file) {
                $content = Get-Content $file.FullName -Raw
                $promptMatch = $content | Select-String -Pattern '^(\S+)#' -AllMatches | Select-Object -First 1
                $prompt = if ($promptMatch) { [regex]::Escape($promptMatch.Matches[0].Groups[1].Value) } else { '\S+' }
                $pattern = "(?ms)^\s*${prompt}#\s*" + [regex]::Escape($selectedCommand) + "\s*(.+?)(?=^\s*${prompt}#|\z)"
                if ($content -match $pattern) {
                    $outputLines = $matches[1].Trim().Split("`n") | ForEach-Object { $_.Trim() }
                    $regex = $RegexBox.Text.Trim()
                    if ($regex) {
                        $outputLines = $outputLines | Where-Object { $_ -match $regex }
                    }
                    $OutputPreview.Text = ($outputLines -join "`r`n")
                }
            }
        }
    })

    $ExportSelectedButton.Add_Click({
        $make = $MakeBox.Text.Trim()
        $model = $ModelBox.Text.Trim()
        $os = $OSBox.Text.Trim()
        if (-not ($make -and $model -and $os)) {
            [System.Windows.MessageBox]::Show("Please select Make, Model, and OS to export.")
            return
        }
        $exportData = $json[$make][$model][$os]
        $exportFile = Join-Path $PSScriptRoot "export_${make}_${model}_${os}.json"
        $exportData | ConvertTo-Json -Depth 10 | Set-Content -Path $exportFile -Encoding UTF8
        [System.Windows.MessageBox]::Show("Exported to $exportFile")
    })

    $SaveButton.Add_Click({
        $make = $MakeBox.Text.Trim()
        $model = $ModelBox.Text.Trim()
        $os = $OSBox.Text.Trim()
        $cmd = $CommandBox.Text.Trim()
        $category = if ($CategoryBox.SelectedItem -ne $null) { $CategoryBox.Text } else { "other" }
        if (-not ($make -and $model -and $os -and $cmd)) {
            [System.Windows.MessageBox]::Show("Please fill in all fields.")
            return
        }
        if (-not $json.PSObject.Properties.Name -contains $make) { $json[$make] = @{} }
        if (-not $json[$make].PSObject.Properties.Name -contains $model) { $json[$make][$model] = @{} }
        if (-not $json[$make][$model].PSObject.Properties.Name -contains $os) { $json[$make][$model][$os] = @{} }
        $sampleOutput = $OutputPreview.Text -split "`r?`n" | ForEach-Object { $_.Trim() }
        $json[$make][$model][$os][$cmd] = @{ sample = $sampleOutput; category = $category }
        $json | ConvertTo-Json -Compress | Set-Content -Path $jsonFile -Encoding UTF8
        [System.Windows.MessageBox]::Show("Definition saved.")
        $CommandBox.Text = ""
        $OutputPreview.Clear()
        Update-CommandList $make $model $os
    })

    $DetectButton.Add_Click({
        $selectedLog = $LogListBox.SelectedItem
        if (-not $selectedLog) {
            [System.Windows.MessageBox]::Show("Please select a log file first.")
            return
        }

        $MakeBox.Text = ""
        $ModelBox.Text = ""
        $OSBox.Text = ""
        $CommandListBox.ItemsSource = @()

        $file = Get-ChildItem -Path $logDir -Filter $selectedLog
        if ($file) {
            $content = Get-Content $file.FullName -Raw

            if ($content -match 'Cisco IOS XE Software, Version ([\d\.]+)') {
                $OSBox.Text = $matches[1]
            } elseif ($content -match 'SW:\s+Version\s+([\w\.\-]+)') {
                $OSBox.Text = $matches[1]
            } elseif ($content -match 'ver\s+([\d\.A-Za-z\-]+)') {
                $OSBox.Text = $matches[1]
            }

            if ($content -match 'Model number\s*:\s*(\S+)') {
                $ModelBox.Text = $matches[1]
            } elseif ($content -match 'HW:\s+(?:Stackable\s+)?([A-Za-z0-9\-]+)') {
                $ModelBox.Text = $matches[1]
            }

            if ($content -match '^(\S+)#') {
                $MakeBox.Text = $matches[1]
            }

            $commandMatches = [regex]::Matches($content, "(?m)^\s*\S+#\s*(show\s+.+)$")
            $uniqueCommands = $commandMatches | ForEach-Object { $_.Groups[1].Value.Trim() } | Sort-Object -Unique
            $CommandBox.ItemsSource = $uniqueCommands

            Update-CommandList $MakeBox.Text.Trim() $ModelBox.Text.Trim() $OSBox.Text.Trim()
        }
    })

    $form.ShowDialog() | Out-Null
}

Start-DefinitionBuilderGui