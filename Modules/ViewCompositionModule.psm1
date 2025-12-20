Set-StrictMode -Version Latest

function Set-StView {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Windows.Window]$Window,
        [Parameter(Mandatory)][string]$ScriptDir,
        [string]$ViewName,
        [Parameter(Mandatory)][string]$HostControlName,
        [string]$GlobalVariableName
    )

    if ([string]::IsNullOrWhiteSpace($ViewName)) {
        if ($HostControlName) {
            $ViewName = ($HostControlName -replace 'Host$', '')
        }
        if ([string]::IsNullOrWhiteSpace($ViewName)) {
            throw "Set-StView requires a ViewName or a HostControlName that ends with 'Host'."
        }
    }

    $viewPath = Join-Path $ScriptDir (Join-Path '..\Views' ("{0}.xaml" -f $ViewName))
    if (-not (Test-Path -LiteralPath $viewPath)) {
        Write-Warning ("{0}.xaml not found at {1}" -f $ViewName, $viewPath)
        return $null
    }

    try {
        $xaml   = Get-Content -LiteralPath $viewPath -Raw
        $reader = New-Object System.Xml.XmlTextReader (New-Object System.IO.StringReader($xaml))
        try {
            $view = [Windows.Markup.XamlReader]::Load($reader)
        } finally {
            if ($reader) { $reader.Close(); $reader.Dispose() }
        }
    } catch {
        Write-Warning ("Failed to load {0}.xaml: {1}" -f $ViewName, $_.Exception.Message)
        return $null
    }

    $host = $Window.FindName($HostControlName)
    if ($host -is [System.Windows.Controls.ContentControl]) {
        $host.Content = $view
    } else {
        Write-Warning ("Could not find ContentControl '{0}'" -f $HostControlName)
        return $null
    }

    if ($GlobalVariableName) {
        Set-Variable -Scope Global -Name $GlobalVariableName -Value $view -Force
    }

    return $view
}

function New-StDebounceTimer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$DelayMs,
        [Parameter(Mandatory)][scriptblock]$Action
    )

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds([Math]::Max(0, $DelayMs))
    $timer.add_Tick({
        param($sender, $args)
        try { $sender.Stop() } catch { }
        try { & $Action } catch { }
    }.GetNewClosure())

    return $timer
}

function Export-StRowsToCsv {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Rows,
        [string]$DefaultFileName = 'Export.csv',
        [string]$DialogFilter = 'CSV files (*.csv)|*.csv|All files (*.*)|*.*',
        [string]$EmptyMessage = 'No rows to export.',
        [string]$SuccessNoun = 'rows',
        [string]$SuccessTitle = 'Export Complete',
        [string]$FailureMessagePrefix = 'Failed to export'
    )

    $rowArray = @()
    try {
        $rowArray = @($Rows)
    } catch {
        $rowArray = @()
    }

    if (-not $rowArray -or $rowArray.Count -eq 0) {
        try { [System.Windows.MessageBox]::Show($EmptyMessage) | Out-Null } catch { }
        return
    }

    $dlg = $null
    try {
        $dlg = New-Object Microsoft.Win32.SaveFileDialog
        $dlg.Filter = $DialogFilter
        $dlg.FileName = $DefaultFileName
        $dlg.DefaultExt = '.csv'
        $dlg.AddExtension = $true
    } catch {
        try { [System.Windows.MessageBox]::Show(("Failed to open save dialog: {0}" -f $_.Exception.Message)) | Out-Null } catch { }
        return
    }

    $confirmed = $false
    try { $confirmed = ($dlg.ShowDialog() -eq $true) } catch { $confirmed = $false }
    if (-not $confirmed) { return }

    $path = $dlg.FileName
    if ([string]::IsNullOrWhiteSpace($path)) { return }

    try {
        $rowArray | Export-Csv -Path $path -NoTypeInformation
        $msg = "Exported {0} {1} to {2}" -f $rowArray.Count, $SuccessNoun, $path
        [System.Windows.MessageBox]::Show($msg, $SuccessTitle) | Out-Null
    } catch {
        $prefix = $FailureMessagePrefix
        if ([string]::IsNullOrWhiteSpace($prefix)) { $prefix = 'Failed to export' }
        try { [System.Windows.MessageBox]::Show(("{0}: {1}" -f $prefix, $_.Exception.Message)) | Out-Null } catch { }
    }
}

function Export-StTextToFile {
    [CmdletBinding()]
    param(
        [Parameter()][AllowEmptyString()][string]$Text,
        [string]$DefaultFileName = 'Export.txt',
        [string]$DialogFilter = 'Text files (*.txt)|*.txt|All files (*.*)|*.*',
        [string]$EmptyMessage = 'Nothing to save.',
        [string]$SuccessTitle = 'Save Complete',
        [string]$FailureMessagePrefix = 'Failed to save'
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        try { [System.Windows.MessageBox]::Show($EmptyMessage) | Out-Null } catch { }
        return
    }

    $dlg = $null
    try {
        $dlg = New-Object Microsoft.Win32.SaveFileDialog
        $dlg.Filter = $DialogFilter
        $dlg.FileName = $DefaultFileName
        $dlg.DefaultExt = '.txt'
        $dlg.AddExtension = $true
    } catch {
        try { [System.Windows.MessageBox]::Show(("Failed to open save dialog: {0}" -f $_.Exception.Message)) | Out-Null } catch { }
        return
    }

    $confirmed = $false
    try { $confirmed = ($dlg.ShowDialog() -eq $true) } catch { $confirmed = $false }
    if (-not $confirmed) { return }

    $path = $dlg.FileName
    if ([string]::IsNullOrWhiteSpace($path)) { return }

    try {
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($path, ('' + $Text), $utf8NoBom)
        $msg = "Saved to {0}" -f $path
        [System.Windows.MessageBox]::Show($msg, $SuccessTitle) | Out-Null
    } catch {
        $prefix = $FailureMessagePrefix
        if ([string]::IsNullOrWhiteSpace($prefix)) { $prefix = 'Failed to save' }
        try { [System.Windows.MessageBox]::Show(("{0}: {1}" -f $prefix, $_.Exception.Message)) | Out-Null } catch { }
    }
}

Export-ModuleMember -Function Set-StView, New-StDebounceTimer, Export-StRowsToCsv, Export-StTextToFile
