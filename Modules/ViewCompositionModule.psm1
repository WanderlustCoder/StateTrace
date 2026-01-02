Set-StrictMode -Version Latest

$script:LastSetStViewFailure = $null

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

    # LANDMARK: View composition diagnostics - track last failure details for harnesses
    $script:LastSetStViewFailure = $null

    $viewPath = Join-Path $ScriptDir (Join-Path '..\Views' ("{0}.xaml" -f $ViewName))
    if (-not (Test-Path -LiteralPath $viewPath)) {
        $script:LastSetStViewFailure = [pscustomobject]@{
            ViewName = $ViewName
            ViewPath = $viewPath
            Reason   = 'ViewNotFound'
            Message  = ("{0}.xaml not found at {1}" -f $ViewName, $viewPath)
        }
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
        $failure = [ordered]@{
            ViewName      = $ViewName
            ViewPath      = $viewPath
            Reason        = 'XamlLoadFailed'
            ExceptionType = $_.Exception.GetType().FullName
            Message       = $_.Exception.Message
            StackTrace    = $_.Exception.StackTrace
        }
        if ($_.Exception.GetType().FullName -eq 'System.Windows.Markup.XamlParseException') {
            try { $failure.LineNumber = $_.Exception.LineNumber } catch { }
            try { $failure.LinePosition = $_.Exception.LinePosition } catch { }
            try { $failure.BaseUri = if ($_.Exception.BaseUri) { $_.Exception.BaseUri.ToString() } else { '' } } catch { }
        }
        $script:LastSetStViewFailure = [pscustomobject]$failure
        Write-Warning ("Failed to load {0}.xaml: {1}" -f $ViewName, $_.Exception.Message)
        return $null
    }

    $host = $Window.FindName($HostControlName)
    if ($host -is [System.Windows.Controls.ContentControl]) {
        $host.Content = $view
    } else {
        $script:LastSetStViewFailure = [pscustomobject]@{
            ViewName        = $ViewName
            ViewPath        = $viewPath
            Reason          = 'HostControlMissing'
            HostControlName = $HostControlName
            Message         = ("Could not find ContentControl '{0}'" -f $HostControlName)
        }
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

# LANDMARK: View composition lint - keep helper names unscoped for usage discovery
function Test-ViewCompositionDialogSuppression {
    [CmdletBinding()]
    param([switch]$SuppressDialogs)

    if ($SuppressDialogs.IsPresent) { return $true }

    $globalSetting = $null
    try { $globalSetting = Get-Variable -Name StateTraceSuppressDialogs -Scope Global -ErrorAction SilentlyContinue } catch { $globalSetting = $null }
    if ($globalSetting -and $null -ne $globalSetting.Value) {
        try { if ([bool]$globalSetting.Value) { return $true } } catch { }
    }

    $envValue = $env:STATETRACE_SUPPRESS_DIALOGS
    if (-not [string]::IsNullOrWhiteSpace($envValue)) {
        if ($envValue -match '^(1|true|yes)$') { return $true }
    }

    try { if (-not [System.Environment]::UserInteractive) { return $true } } catch { }

    return $false
}

function Show-ViewCompositionMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$Title,
        [ValidateSet('Info','Warning','Error')][string]$Severity = 'Info',
        [switch]$SuppressDialogs
    )

    $suppress = Test-ViewCompositionDialogSuppression -SuppressDialogs:$SuppressDialogs
    if ($suppress) {
        $prefix = if ([string]::IsNullOrWhiteSpace($Title)) { '' } else { "${Title}: " }
        $text = "$prefix$Message"
        switch ($Severity) {
            'Warning' { Write-Warning $text }
            'Error' { Write-Error $text }
            default { Write-Verbose $text }
        }
        return
    }

    if ([string]::IsNullOrWhiteSpace($Title)) {
        [System.Windows.MessageBox]::Show($Message) | Out-Null
    } else {
        [System.Windows.MessageBox]::Show($Message, $Title) | Out-Null
    }
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
        [string]$FailureMessagePrefix = 'Failed to export',
        [switch]$SuppressDialogs
    )

    $rowArray = @()
    try {
        $rowArray = @($Rows)
    } catch {
        $rowArray = @()
    }

    if (-not $rowArray -or $rowArray.Count -eq 0) {
        try { Show-ViewCompositionMessage -Message $EmptyMessage -SuppressDialogs:$SuppressDialogs } catch { }
        return
    }

    $suppressDialogsResolved = Test-ViewCompositionDialogSuppression -SuppressDialogs:$SuppressDialogs

    $dlg = $null
    try {
        if (-not $suppressDialogsResolved) {
            $dlg = New-Object Microsoft.Win32.SaveFileDialog
            $dlg.Filter = $DialogFilter
            $dlg.FileName = $DefaultFileName
            $dlg.DefaultExt = '.csv'
            $dlg.AddExtension = $true
        }
    } catch {
        try { Show-ViewCompositionMessage -Message ("Failed to open save dialog: {0}" -f $_.Exception.Message) -Severity Warning -SuppressDialogs:$SuppressDialogs } catch { }
        return
    }

    if ($suppressDialogsResolved) {
        if ([string]::IsNullOrWhiteSpace($DefaultFileName) -or -not ([System.IO.Path]::IsPathRooted($DefaultFileName))) {
            Show-ViewCompositionMessage -Message 'Export dialog suppressed; provide an absolute -DefaultFileName to export.' -Severity Warning -SuppressDialogs:$SuppressDialogs
            return
        }
        $path = $DefaultFileName
    } else {
    $confirmed = $false
    try { $confirmed = ($dlg.ShowDialog() -eq $true) } catch { $confirmed = $false }
    if (-not $confirmed) { return }

        $path = $dlg.FileName
    }
    if ([string]::IsNullOrWhiteSpace($path)) { return }

    try {
        $rowArray | Export-Csv -Path $path -NoTypeInformation
        $msg = "Exported {0} {1} to {2}" -f $rowArray.Count, $SuccessNoun, $path
        Show-ViewCompositionMessage -Message $msg -Title $SuccessTitle -SuppressDialogs:$SuppressDialogs
    } catch {
        $prefix = $FailureMessagePrefix
        if ([string]::IsNullOrWhiteSpace($prefix)) { $prefix = 'Failed to export' }
        try { Show-ViewCompositionMessage -Message ("{0}: {1}" -f $prefix, $_.Exception.Message) -Severity Warning -SuppressDialogs:$SuppressDialogs } catch { }
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
        [string]$FailureMessagePrefix = 'Failed to save',
        [switch]$SuppressDialogs
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        try { Show-ViewCompositionMessage -Message $EmptyMessage -SuppressDialogs:$SuppressDialogs } catch { }
        return
    }

    $suppressDialogsResolved = Test-ViewCompositionDialogSuppression -SuppressDialogs:$SuppressDialogs

    $dlg = $null
    try {
        if (-not $suppressDialogsResolved) {
            $dlg = New-Object Microsoft.Win32.SaveFileDialog
            $dlg.Filter = $DialogFilter
            $dlg.FileName = $DefaultFileName
            $dlg.DefaultExt = '.txt'
            $dlg.AddExtension = $true
        }
    } catch {
        try { Show-ViewCompositionMessage -Message ("Failed to open save dialog: {0}" -f $_.Exception.Message) -Severity Warning -SuppressDialogs:$SuppressDialogs } catch { }
        return
    }

    if ($suppressDialogsResolved) {
        if ([string]::IsNullOrWhiteSpace($DefaultFileName) -or -not ([System.IO.Path]::IsPathRooted($DefaultFileName))) {
            Show-ViewCompositionMessage -Message 'Save dialog suppressed; provide an absolute -DefaultFileName to write.' -Severity Warning -SuppressDialogs:$SuppressDialogs
            return
        }
        $path = $DefaultFileName
    } else {
    $confirmed = $false
    try { $confirmed = ($dlg.ShowDialog() -eq $true) } catch { $confirmed = $false }
    if (-not $confirmed) { return }

        $path = $dlg.FileName
    }
    if ([string]::IsNullOrWhiteSpace($path)) { return }

    try {
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($path, ('' + $Text), $utf8NoBom)
        $msg = "Saved to {0}" -f $path
        Show-ViewCompositionMessage -Message $msg -Title $SuccessTitle -SuppressDialogs:$SuppressDialogs
    } catch {
        $prefix = $FailureMessagePrefix
        if ([string]::IsNullOrWhiteSpace($prefix)) { $prefix = 'Failed to save' }
        try { Show-ViewCompositionMessage -Message ("{0}: {1}" -f $prefix, $_.Exception.Message) -Severity Warning -SuppressDialogs:$SuppressDialogs } catch { }
    }
}

Export-ModuleMember -Function Set-StView, New-StDebounceTimer, Export-StRowsToCsv, Export-StTextToFile
