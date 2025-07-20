function Start-DefinitionBuilder {
    [CmdletBinding()]
    param(
        [string[]]$LogFiles
    )

    $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
    $xamlPath   = Join-Path $scriptRoot '..\Views\DefinitionBuilder.xaml'

    if (-not (Test-Path $xamlPath)) {
        Write-Error "Cannot find XAML at $xamlPath"; exit 1
    }

    $xaml    = Get-Content $xamlPath -Raw
    $reader  = New-Object System.Xml.XmlTextReader (New-Object System.IO.StringReader($xaml))
    $window  = [Windows.Markup.XamlReader]::Load($reader)

    $makeDD    = $window.FindName('MakeDropdown')
    $modelBox  = $window.FindName('ModelBox')
    $osBox     = $window.FindName('OSBox')
    $logList   = $window.FindName('LogList')
    $addBtn    = $window.FindName('AddLogButton')
    $buildBtn  = $window.FindName('BuildButton')
    $cancelBtn = $window.FindName('CancelButton')

    if ($LogFiles) {
        foreach ($f in $LogFiles) { $logList.Items.Add($f) }
    }

    $addBtn.Add_Click({
        $dlg = New-Object Microsoft.Win32.OpenFileDialog
        $dlg.Multiselect = $true
        if ($dlg.ShowDialog()) {
            foreach ($f in $dlg.FileNames) { $logList.Items.Add($f) }
        }
    })

    $buildBtn.Add_Click({
        $make  = $makeDD.Text
        $model = $modelBox.Text
        $os    = $osBox.Text
        $files = @($logList.Items)
        if (-not $make -or -not $model -or -not $os -or $files.Count -eq 0) {
            [System.Windows.MessageBox]::Show('Please provide make, model, OS and at least one log file.')
            return
        }
        $builder = Join-Path $scriptRoot 'DefinitionBuilder.ps1'
        & $builder -LogFiles $files -Make $make -Model $model -OSVersion $os -DefinitionPath (Join-Path $scriptRoot 'Definitions')
        [System.Windows.MessageBox]::Show('Definition created.')
        $window.Close()
    })

    $cancelBtn.Add_Click({ $window.Close() })

    $window.ShowDialog() | Out-Null
}

# Call the function
Start-DefinitionBuilder -LogFiles $LogFiles
