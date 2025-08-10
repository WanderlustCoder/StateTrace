function New-TemplatesView {
    <#
        .SYNOPSIS
            Load and initialise the Templates view.

        .DESCRIPTION
            This function loads the TemplatesView.xaml file, inserts it into
            the main window and provides handlers for selecting, reloading,
            saving and creating configuration templates.  It maintains a
            script-scoped TemplatesDir variable pointing to the ../Templates
            directory and exposes the view globally via $templatesView.

        .PARAMETER Window
            The main WPF window created by MainWindow.ps1.

        .PARAMETER ScriptDir
            The directory containing the Main scripts.  TemplatesView.xaml
            resides in a ../Views folder relative to this path and templates
            themselves reside in ../Templates.
    #>
    param(
        [Parameter(Mandatory=$true)][Windows.Window]$Window,
        [Parameter(Mandatory=$true)][string]$ScriptDir
    )
    $templatesViewPath = Join-Path $ScriptDir '..\Views\TemplatesView.xaml'
    if (-not (Test-Path $templatesViewPath)) {
        Write-Warning "TemplatesView.xaml not found at $templatesViewPath"
        return
    }
    $tplXaml  = Get-Content $templatesViewPath -Raw
    $reader   = New-Object System.Xml.XmlTextReader (New-Object System.IO.StringReader($tplXaml))
    try {
        $templatesView = [Windows.Markup.XamlReader]::Load($reader)
        $templatesHost = $Window.FindName('TemplatesHost')
        if ($templatesHost -is [System.Windows.Controls.ContentControl]) {
            $templatesHost.Content = $templatesView
        } else {
            Write-Warning "Could not find ContentControl 'TemplatesHost'"
        }
        # Expose globally for access by helper functions
        $global:templatesView = $templatesView
        # Directory containing JSON template files
        $script:TemplatesDir = Join-Path $ScriptDir '..\Templates'
        # Acquire key controls
        $templatesList = $templatesView.FindName('TemplatesList')
        $templateEditor = $templatesView.FindName('TemplateEditor')
        $reloadBtn = $templatesView.FindName('ReloadTemplateButton')
        $saveBtn   = $templatesView.FindName('SaveTemplateButton')
        # Helper to refresh the list of templates
        function Update-TemplatesList {
            if (-not $templatesList) { return }
            if (-not (Test-Path $script:TemplatesDir)) { return }
            $files = Get-ChildItem -Path $script:TemplatesDir -Filter '*.json' -File
            $items = $files | ForEach-Object { $_.Name }
            $templatesList.ItemsSource = $items
        }
        # Load list on startup
        Update-TemplatesList
        # Handle selection change to load file contents
        if ($templatesList) {
            $templatesList.Add_SelectionChanged({
                $sel = $templatesList.SelectedItem
                if ($sel) {
                    $path = Join-Path $script:TemplatesDir $sel
                    try {
                        $templateEditor.Text = Get-Content -Path $path -Raw
                    } catch {
                        $templateEditor.Text = ''
                    }
                } else {
                    $templateEditor.Text = ''
                }
            })
        }
        # Reload button reloads selected template
        if ($reloadBtn) {
            $reloadBtn.Add_Click({
                $sel = $templatesList.SelectedItem
                if (-not $sel) { return }
                $path = Join-Path $script:TemplatesDir $sel
                try {
                    $templateEditor.Text = Get-Content -Path $path -Raw
                } catch {
                    [System.Windows.MessageBox]::Show("Failed to load template: $($_.Exception.Message)")
                }
            })
        }
        # Save button writes edits back to disk
        if ($saveBtn) {
            $saveBtn.Add_Click({
                $sel = $templatesList.SelectedItem
                if (-not $sel) {
                    [System.Windows.MessageBox]::Show('No template selected.')
                    return
                }
                $path = Join-Path $script:TemplatesDir $sel
                try {
                    Set-Content -Path $path -Value $templateEditor.Text -Force
                    [System.Windows.MessageBox]::Show("Saved template $sel.")
                    Update-TemplatesList
                } catch {
                    [System.Windows.MessageBox]::Show("Failed to save template: $($_.Exception.Message)")
                }
            })
        }
        # Add new template
        $addBtn      = $templatesView.FindName('AddTemplateButton')
        $newNameBox  = $templatesView.FindName('NewTemplateNameBox')
        $newOsCombo  = $templatesView.FindName('NewTemplateOSType')
        if ($addBtn) {
            $addBtn.Add_Click({
                $name = $newNameBox.Text
                if (-not $name -or $name.Trim() -eq '') {
                    [System.Windows.MessageBox]::Show('Please enter a template name.')
                    return
                }
                # Ensure extension
                $fileName = if ($name.EndsWith('.json')) { $name } else { "$name.json" }
                $path = Join-Path $script:TemplatesDir $fileName
                if (Test-Path $path) {
                    [System.Windows.MessageBox]::Show('Template already exists.')
                    return
                }
                $osType = 'Cisco'
                try {
                    if ($newOsCombo -and $newOsCombo.SelectedItem) {
                        $osType = $newOsCombo.SelectedItem.Content
                    }
                } catch {}
                # Create a default template structure based on OS
                $templateObj = $null
                switch ($osType) {
                    'Cisco' {
                        $templateObj = @{ PortType = 'Cisco'; Commands = @(
                            'interface {Port}',
                            'description {Name}',
                            'switchport access vlan {VLAN}',
                            'switchport mode access'
                        ) }
                    }
                    'Brocade' {
                        $templateObj = @{ PortType = 'Brocade'; Commands = @(
                            'interface ethernet {Port}',
                            'description {Name}',
                            'untagged {VLAN}',
                            'enable'
                        ) }
                    }
                    'Arista' {
                        $templateObj = @{ PortType = 'Arista'; Commands = @(
                            'interface Ethernet{Port}',
                            'description {Name}',
                            'switchport access vlan {VLAN}',
                            'switchport mode access'
                        ) }
                    }
                    default {
                        $templateObj = @{ PortType = $osType; Commands = @() }
                    }
                }
                try {
                    $json = $templateObj | ConvertTo-Json -Depth 4
                    Set-Content -Path $path -Value $json -Force
                    Update-TemplatesList
                    # Select the newly created file in the list using SelectedIndex rather than SelectedItem.
                    try {
                        $templatesList.SelectedIndex = [Array]::IndexOf($templatesList.ItemsSource, $fileName)
                    } catch {
                        # If selection fails for any reason, leave as-is
                    }
                    $templateEditor.Text = $json
                    [System.Windows.MessageBox]::Show("Created new template $fileName.")
                } catch {
                    [System.Windows.MessageBox]::Show("Failed to create template: $($_.Exception.Message)")
                }
            })
        }
    } catch {
        Write-Warning "Failed to load TemplatesView: $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function New-TemplatesView