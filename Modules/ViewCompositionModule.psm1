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
            if ($reader) { $reader.Dispose() }
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

function Export-StRowsToJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Rows,
        [string]$DefaultFileName = 'Export.json',
        [string]$DialogFilter = 'JSON files (*.json)|*.json|All files (*.*)|*.*',
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
            $dlg.DefaultExt = '.json'
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
        $json = $rowArray | ConvertTo-Json -Depth 10
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($path, $json, $utf8NoBom)
        $msg = "Exported {0} {1} to {2}" -f $rowArray.Count, $SuccessNoun, $path
        Show-ViewCompositionMessage -Message $msg -Title $SuccessTitle -SuppressDialogs:$SuppressDialogs
    } catch {
        $prefix = $FailureMessagePrefix
        if ([string]::IsNullOrWhiteSpace($prefix)) { $prefix = 'Failed to export' }
        try { Show-ViewCompositionMessage -Message ("{0}: {1}" -f $prefix, $_.Exception.Message) -Severity Warning -SuppressDialogs:$SuppressDialogs } catch { }
    }
}

function Export-StRowsWithFormatChoice {
    <#
    .SYNOPSIS
        Exports rows to a file with user choice of format (CSV or JSON).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Rows,
        [string]$DefaultBaseName = 'Export',
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
            $dlg.Filter = 'CSV files (*.csv)|*.csv|JSON files (*.json)|*.json|All files (*.*)|*.*'

            # Load last export format preference
            $lastFormat = 'csv'
            try {
                $settingsPath = Join-Path $PSScriptRoot '..\Data\StateTraceSettings.json'
                if (Test-Path $settingsPath) {
                    $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
                    if ($settings.LastExportFormat) { $lastFormat = $settings.LastExportFormat }
                }
            } catch { }

            # Set dialog defaults based on last format
            if ($lastFormat -eq 'json') {
                $dlg.FilterIndex = 2
                $dlg.FileName = "$DefaultBaseName.json"
                $dlg.DefaultExt = '.json'
            } else {
                $dlg.FilterIndex = 1
                $dlg.FileName = "$DefaultBaseName.csv"
                $dlg.DefaultExt = '.csv'
            }
            $dlg.AddExtension = $true
        }
    } catch {
        try { Show-ViewCompositionMessage -Message ("Failed to open save dialog: {0}" -f $_.Exception.Message) -Severity Warning -SuppressDialogs:$SuppressDialogs } catch { }
        return
    }

    if ($suppressDialogsResolved) {
        # For suppressed dialogs, default to CSV
        $path = "$DefaultBaseName.csv"
        if (-not ([System.IO.Path]::IsPathRooted($path))) {
            Show-ViewCompositionMessage -Message 'Export dialog suppressed; provide an absolute path.' -Severity Warning -SuppressDialogs:$SuppressDialogs
            return
        }
    } else {
        $confirmed = $false
        try { $confirmed = ($dlg.ShowDialog() -eq $true) } catch { $confirmed = $false }
        if (-not $confirmed) { return }
        $path = $dlg.FileName
    }
    if ([string]::IsNullOrWhiteSpace($path)) { return }

    try {
        $ext = [System.IO.Path]::GetExtension($path).ToLower()
        if ($ext -eq '.json') {
            $json = $rowArray | ConvertTo-Json -Depth 10
            $utf8NoBom = New-Object System.Text.UTF8Encoding $false
            [System.IO.File]::WriteAllText($path, $json, $utf8NoBom)
        } else {
            $rowArray | Export-Csv -Path $path -NoTypeInformation
        }

        # Save export format preference
        try {
            $chosenFormat = if ($ext -eq '.json') { 'json' } else { 'csv' }
            $settingsPath = Join-Path $PSScriptRoot '..\Data\StateTraceSettings.json'
            $settings = @{}
            if (Test-Path $settingsPath) {
                $raw = Get-Content $settingsPath -Raw
                if ($raw) {
                    $parsed = $raw | ConvertFrom-Json
                    $parsed.PSObject.Properties | ForEach-Object { $settings[$_.Name] = $_.Value }
                }
            }
            $settings['LastExportFormat'] = $chosenFormat
            $settings | ConvertTo-Json -Depth 5 | Set-Content $settingsPath -Encoding UTF8
        } catch { }

        $msg = "Exported {0} {1} to {2}" -f $rowArray.Count, $SuccessNoun, $path
        Show-ViewCompositionMessage -Message $msg -Title $SuccessTitle -SuppressDialogs:$SuppressDialogs
    } catch {
        $prefix = $FailureMessagePrefix
        if ([string]::IsNullOrWhiteSpace($prefix)) { $prefix = 'Failed to export' }
        try { Show-ViewCompositionMessage -Message ("{0}: {1}" -f $prefix, $_.Exception.Message) -Severity Warning -SuppressDialogs:$SuppressDialogs } catch { }
    }
}

function Show-CopyFeedback {
    <#
    .SYNOPSIS
        Shows brief visual feedback when content is copied to clipboard.
    .DESCRIPTION
        Temporarily changes the button content to "Copied!" then restores it after a delay.
    #>
    [CmdletBinding()]
    param(
        [Parameter()][System.Windows.Controls.Button]$Button,
        [string]$Message = 'Copied!',
        [int]$DelayMs = 1500
    )

    if (-not $Button) { return }

    $originalContent = $Button.Content
    $Button.Content = $Message

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds($DelayMs)
    $timer.Add_Tick({
        $timer.Stop()
        $Button.Content = $originalContent
    }.GetNewClosure())
    $timer.Start()
}

function Import-StXamlView {
    <#
    .SYNOPSIS
        Loads a XAML view file and returns the parsed WPF element.
    .DESCRIPTION
        Reads XAML from file, strips designer attributes, and parses via XamlReader.
        DynamicResource bindings resolve from Application.Resources when view is in visual tree.
    .PARAMETER ViewPath
        Absolute path to the XAML file.
    .OUTPUTS
        The loaded WPF element, or $null if loading fails.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ViewPath
    )

    if (-not (Test-Path $ViewPath)) { return $null }

    $xamlContent = Get-Content -Path $ViewPath -Raw
    $xamlContent = $xamlContent -replace 'x:Class="[^"]*"', ''
    $xamlContent = $xamlContent -replace 'mc:Ignorable="d"', ''

    $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xamlContent))
    $view = [System.Windows.Markup.XamlReader]::Load($reader)

    return $view
}

Export-ModuleMember -Function Set-StView, New-StDebounceTimer, Export-StRowsToCsv, Export-StRowsToJson, Export-StRowsWithFormatChoice, Export-StTextToFile, Show-CopyFeedback, Import-StXamlView
