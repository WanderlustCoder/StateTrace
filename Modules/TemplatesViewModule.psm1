Set-StrictMode -Version Latest

function New-TemplatesView {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][System.Windows.Window]$Window,
        [Parameter(Mandatory=$true)][string]$ScriptDir
    )
    try {
        $templatesView = ViewCompositionModule\Set-StView -Window $Window -ScriptDir $ScriptDir -ViewName 'TemplatesView' -HostControlName 'TemplatesHost' -GlobalVariableName 'templatesView'
        if (-not $templatesView) { return }

        # Directory containing JSON template files
        $script:TemplatesDir = Join-Path $ScriptDir '..\Templates'
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false

        # Acquire key controls
        $templatesList = $templatesView.FindName('TemplatesList')
        $templateEditor = $templatesView.FindName('TemplateEditor')
        $reloadBtn = $templatesView.FindName('ReloadTemplateButton')
        $saveBtn   = $templatesView.FindName('SaveTemplateButton')

        $refreshTemplatesList = {
            if (-not $templatesList) { return }
            if (-not $script:TemplatesDir -or -not (Test-Path -LiteralPath $script:TemplatesDir)) {
                $templatesList.ItemsSource = @()
                return
            }

            $files = Get-ChildItem -LiteralPath $script:TemplatesDir -Filter '*.json' -File | Sort-Object Name
            $items = [System.Collections.Generic.List[string]]::new()
            foreach ($f in $files) {
                if ($f -and $f.Name) { [void]$items.Add($f.Name) }
            }
            $templatesList.ItemsSource = $items
        }

        $loadTemplateText = {
            param([object]$SelectedItem)

            if (-not $templateEditor) { return }

            $selText = if ($SelectedItem) { '' + $SelectedItem } else { '' }
            if ([string]::IsNullOrWhiteSpace($selText)) {
                $templateEditor.Text = ''
                return
            }
            if (-not $script:TemplatesDir) {
                $templateEditor.Text = ''
                return
            }

            $path = Join-Path -Path $script:TemplatesDir -ChildPath $selText
            try {
                if (-not (Test-Path -LiteralPath $path)) {
                    $templateEditor.Text = ''
                    return
                }

                $templateEditor.Text = [System.IO.File]::ReadAllText($path)
            } catch {
                $templateEditor.Text = ''
            }
        }

        # Load list on startup
        & $refreshTemplatesList
        # Handle selection change to load file contents
        if ($templatesList) {
            $templatesList.Add_SelectionChanged({
                & $loadTemplateText $templatesList.SelectedItem
            })
        }
        # Reload button reloads selected template
        if ($reloadBtn) {
            $reloadBtn.Add_Click({
                try {
                    if (-not $templatesList -or -not $templatesList.SelectedItem) { return }
                    & $loadTemplateText $templatesList.SelectedItem
                } catch {
                    [System.Windows.MessageBox]::Show("Failed to load template: $($_.Exception.Message)")
                }
            })
        }
        # Save button writes edits back to disk
        if ($saveBtn) {
            $saveBtn.Add_Click({
                if (-not $templatesList -or -not $templatesList.SelectedItem) {
                    [System.Windows.MessageBox]::Show('No template selected.')
                    return
                }
                $selText = '' + $templatesList.SelectedItem
                if ([string]::IsNullOrWhiteSpace($selText)) {
                    [System.Windows.MessageBox]::Show('No template selected.')
                    return
                }

                $path = Join-Path -Path $script:TemplatesDir -ChildPath $selText
                try {
                    [System.IO.File]::WriteAllText($path, ('' + $templateEditor.Text), $utf8NoBom)
                    [System.Windows.MessageBox]::Show("Saved template $selText.")
                    & $refreshTemplatesList
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
                $path = Join-Path -Path $script:TemplatesDir -ChildPath $fileName
                if (Test-Path -LiteralPath $path) {
                    [System.Windows.MessageBox]::Show('Template already exists.')
                    return
                }
                $osType = 'Cisco'
                try {
                    if ($newOsCombo -and $newOsCombo.SelectedItem) {
                        $osType = $newOsCombo.SelectedItem.Content
                    }
                } catch {}

                # Create a default vendor template file structure compatible with TemplatesModule.
                # Note: This creates a new JSON file; existing vendor files like Cisco.json/Brocade.json
                # contain multiple templates under the 'templates' array.
                $templateObj = @{
                    templates = @(
                        @{
                            name             = 'New Template'
                            aliases          = @()
                            vendor           = $osType
                            match_type       = 'contains_all'
                            required_commands = @()
                            excluded_commands = @()
                            color            = 'Green'
                            description      = ("New {0} template (edit required/excluded commands)." -f $osType)
                        }
                    )
                }
                try {
                    $json = $templateObj | ConvertTo-Json -Depth 6
                    [System.IO.File]::WriteAllText($path, $json, $utf8NoBom)
                    & $refreshTemplatesList
                    # Select the newly created file in the list using SelectedIndex rather than SelectedItem.
                    try {
                        $idx = -1
                        $source = $templatesList.ItemsSource
                        if ($source -is [System.Collections.Generic.List[string]]) {
                            $idx = $source.IndexOf($fileName)
                        } else {
                            $idx = [Array]::IndexOf(@($source), $fileName)
                        }
                        if ($idx -ge 0) { $templatesList.SelectedIndex = $idx }
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
