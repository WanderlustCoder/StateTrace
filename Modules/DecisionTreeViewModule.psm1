Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Creates and initializes the Decision Tree troubleshooting view.

.DESCRIPTION
    Loads DecisionTreeView.xaml using ViewCompositionModule, wires up event handlers,
    and provides guided troubleshooting functionality using decision trees.

.PARAMETER Window
    The parent MainWindow instance.

.PARAMETER ScriptDir
    The root script directory for locating XAML files.

.OUTPUTS
    System.Windows.Controls.UserControl - The initialized view.
#>
function New-DecisionTreeView {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [System.Windows.Window]$Window,

        [Parameter(Mandatory=$true)]
        [string]$ScriptDir
    )

    try {
        $view = ViewCompositionModule\Set-StView -Window $Window -ScriptDir $ScriptDir `
            -ViewName 'DecisionTreeView' -HostControlName 'DecisionTreeHost' `
            -GlobalVariableName 'decisionTreeView'
        if (-not $view) { return }

        # Get controls from the view
        $categoryDropdown = $view.FindName('CategoryDropdown')
        $treeListBox = $view.FindName('TreeListBox')
        $startTreeButton = $view.FindName('StartTreeButton')
        $deviceContextBox = $view.FindName('DeviceContextBox')
        $interfaceContextBox = $view.FindName('InterfaceContextBox')
        $restartButton = $view.FindName('RestartButton')
        $backButton = $view.FindName('BackButton')
        $progressPanel = $view.FindName('ProgressPanel')
        $executionProgress = $view.FindName('ExecutionProgress')
        $progressText = $view.FindName('ProgressText')
        $pathBreadcrumb = $view.FindName('PathBreadcrumb')
        $stepPanel = $view.FindName('StepPanel')
        $stepTitle = $view.FindName('StepTitle')
        $stepContent = $view.FindName('StepContent')
        $answerPanel = $view.FindName('AnswerPanel')
        $inputPanel = $view.FindName('InputPanel')
        $inputValueBox = $view.FindName('InputValueBox')
        $submitInputButton = $view.FindName('SubmitInputButton')
        $continueButton = $view.FindName('ContinueButton')
        $resultPanel = $view.FindName('ResultPanel')
        $resultTitle = $view.FindName('ResultTitle')
        $resultContent = $view.FindName('ResultContent')
        $copyResultButton = $view.FindName('CopyResultButton')
        $startNewButton = $view.FindName('StartNewButton')
        $welcomePanel = $view.FindName('WelcomePanel')
        $notesGroup = $view.FindName('NotesGroup')
        $notesBox = $view.FindName('NotesBox')

        # Store current state in view's Tag
        $view.Tag = @{
            SelectedTree = $null
            CurrentExecution = $null
            AllTrees = @()
        }

        # Load built-in trees
        function Update-TreeList {
            param([string]$Category = 'All Categories')

            $trees = @(DecisionTreeModule\Get-BuiltInTree -List)
            $view.Tag.AllTrees = $trees

            if ($Category -ne 'All Categories') {
                $trees = @($trees | Where-Object { $_.Category -eq $Category })
            }

            $treeListBox.ItemsSource = $trees
            if ($trees.Count -gt 0) {
                $treeListBox.SelectedIndex = 0
            }
        }

        # Initialize tree list
        Update-TreeList -Category 'All Categories'

        # Category dropdown change
        $categoryDropdown.Add_SelectionChanged({
            param($sender, $e)
            $selected = $sender.SelectedItem
            if ($selected) {
                $category = $selected.Content
                Update-TreeList -Category $category
            }
        }.GetNewClosure())

        # Tree selection change
        $treeListBox.Add_SelectionChanged({
            param($sender, $e)
            $selected = $sender.SelectedItem
            if ($selected) {
                $view.Tag.SelectedTree = $selected.Name
            }
        }.GetNewClosure())

        # Helper to show specific panel
        function Show-Panel {
            param([string]$PanelName)
            $welcomePanel.Visibility = 'Collapsed'
            $stepPanel.Visibility = 'Collapsed'
            $resultPanel.Visibility = 'Collapsed'
            $progressPanel.Visibility = 'Collapsed'
            $notesGroup.Visibility = 'Collapsed'

            switch ($PanelName) {
                'Welcome' { $welcomePanel.Visibility = 'Visible' }
                'Step' {
                    $stepPanel.Visibility = 'Visible'
                    $progressPanel.Visibility = 'Visible'
                    $notesGroup.Visibility = 'Visible'
                    $restartButton.Visibility = 'Visible'
                    $backButton.Visibility = 'Visible'
                }
                'Result' {
                    $resultPanel.Visibility = 'Visible'
                    $progressPanel.Visibility = 'Visible'
                    $restartButton.Visibility = 'Visible'
                    $backButton.Visibility = 'Collapsed'
                }
            }
        }

        # Helper to update the current step display
        function Update-StepDisplay {
            $exec = $view.Tag.CurrentExecution
            if (-not $exec) { return }

            $node = $exec.CurrentNode
            $stepTitle.Text = $node.Title
            $stepContent.Text = if ($node.Content) { $node.Content } else { '' }

            # Update progress
            $totalNodes = $exec.Tree.Nodes.Count
            $stepsCompleted = $exec.Steps.Count - 1  # Current step not yet completed
            $progress = [math]::Min(100, [math]::Round(($stepsCompleted / [math]::Max(1, $totalNodes)) * 100))
            $executionProgress.Value = $progress
            $progressText.Text = "Step $($exec.Steps.Count) of ~$totalNodes"

            # Update breadcrumb
            $pathParts = @()
            foreach ($step in $exec.Steps) {
                $stepNode = $exec.Tree.Nodes | Where-Object { $_.Id -eq $step.NodeId }
                if ($stepNode) {
                    $pathParts += $stepNode.Title
                }
            }
            $pathBreadcrumb.Text = $pathParts -join ' > '

            # Clear dynamic panels
            $answerPanel.Children.Clear()
            $inputPanel.Visibility = 'Collapsed'
            $continueButton.Visibility = 'Collapsed'

            # Show appropriate controls based on node type
            switch ($node.Type) {
                'decision' {
                    foreach ($branch in $node.Branches) {
                        $btn = New-Object System.Windows.Controls.Button
                        $btn.Content = $branch.Answer
                        $btn.Style = $view.FindResource('SecondaryButtonStyle')
                        $btn.Margin = [System.Windows.Thickness]::new(0, 5, 0, 5)
                        $btn.Padding = [System.Windows.Thickness]::new(15, 10, 15, 10)
                        $btn.HorizontalAlignment = 'Left'
                        $btn.MinWidth = 200

                        $answerValue = $branch.Answer
                        $btn.Add_Click({
                            param($s, $e)
                            try {
                                $exec = $view.Tag.CurrentExecution
                                $exec = DecisionTreeModule\Submit-TreeAnswer -Execution $exec -Answer $answerValue
                                $view.Tag.CurrentExecution = $exec

                                if ($exec.IsComplete) {
                                    Show-ResultPanel
                                } else {
                                    Update-StepDisplay
                                }
                            } catch {
                                Write-Warning "Error submitting answer: $($_.Exception.Message)"
                            }
                        }.GetNewClosure())

                        $answerPanel.Children.Add($btn) | Out-Null
                    }
                }
                'input' {
                    $inputPanel.Visibility = 'Visible'
                    $inputValueBox.Text = ''
                    $inputValueBox.Focus() | Out-Null
                }
                'action' {
                    $continueButton.Visibility = 'Visible'
                }
                'check' {
                    $continueButton.Visibility = 'Visible'
                }
                'result' {
                    Show-ResultPanel
                }
            }
        }

        # Helper to show result panel
        function Show-ResultPanel {
            $exec = $view.Tag.CurrentExecution
            if (-not $exec) { return }

            Show-Panel -PanelName 'Result'

            $node = $exec.CurrentNode
            $resultTitle.Text = $node.Title

            # Build result summary
            $summary = [System.Text.StringBuilder]::new()
            if ($node.Content) {
                [void]$summary.AppendLine($node.Content)
                [void]$summary.AppendLine()
            }

            [void]$summary.AppendLine("--- Troubleshooting Path ---")
            $stepNum = 1
            foreach ($step in $exec.Steps) {
                $stepNode = $exec.Tree.Nodes | Where-Object { $_.Id -eq $step.NodeId }
                if ($stepNode) {
                    $line = "$stepNum. $($stepNode.Title)"
                    if ($step.Answer) {
                        $line += " -> $($step.Answer)"
                    }
                    [void]$summary.AppendLine($line)
                    $stepNum++
                }
            }

            [void]$summary.AppendLine()
            [void]$summary.AppendLine("Duration: $([math]::Round($exec.Duration.TotalSeconds, 1)) seconds")
            [void]$summary.AppendLine("Outcome: $($exec.Outcome)")

            if ($exec.DeviceID) {
                [void]$summary.AppendLine("Device: $($exec.DeviceID)")
            }
            if ($exec.InterfaceName) {
                [void]$summary.AppendLine("Interface: $($exec.InterfaceName)")
            }

            $notes = $notesBox.Text
            if (-not [string]::IsNullOrWhiteSpace($notes)) {
                [void]$summary.AppendLine()
                [void]$summary.AppendLine("--- Notes ---")
                [void]$summary.AppendLine($notes)
            }

            $resultContent.Text = $summary.ToString()

            # Update progress to 100%
            $executionProgress.Value = 100
            $progressText.Text = "Complete"
        }

        # Start Troubleshooting button click
        $startTreeButton.Add_Click({
            param($sender, $e)
            $treeName = $view.Tag.SelectedTree
            if (-not $treeName) {
                return
            }

            try {
                $tree = DecisionTreeModule\Get-BuiltInTree -Name $treeName
                if (-not $tree) {
                    Write-Warning "Tree not found: $treeName"
                    return
                }

                $deviceId = $deviceContextBox.Text
                $interfaceName = $interfaceContextBox.Text

                $exec = DecisionTreeModule\Start-TreeExecution -Tree $tree -DeviceID $deviceId -InterfaceName $interfaceName
                $view.Tag.CurrentExecution = $exec

                # Clear notes
                $notesBox.Text = ''

                Show-Panel -PanelName 'Step'
                Update-StepDisplay
            } catch {
                Write-Warning "Error starting tree: $($_.Exception.Message)"
            }
        }.GetNewClosure())

        # Submit Input button click
        $submitInputButton.Add_Click({
            param($sender, $e)
            $value = $inputValueBox.Text
            if ([string]::IsNullOrWhiteSpace($value)) {
                return
            }

            try {
                $exec = $view.Tag.CurrentExecution
                $exec = DecisionTreeModule\Submit-TreeInput -Execution $exec -Value $value
                $view.Tag.CurrentExecution = $exec

                if ($exec.IsComplete) {
                    Show-ResultPanel
                } else {
                    Update-StepDisplay
                }
            } catch {
                Write-Warning "Error submitting input: $($_.Exception.Message)"
            }
        }.GetNewClosure())

        # Input box Enter key
        $inputValueBox.Add_KeyDown({
            param($sender, $e)
            if ($e.Key -eq 'Return') {
                $submitInputButton.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
            }
        }.GetNewClosure())

        # Continue button click
        $continueButton.Add_Click({
            param($sender, $e)
            try {
                $exec = $view.Tag.CurrentExecution
                $notes = $notesBox.Text
                $exec = DecisionTreeModule\Continue-TreeExecution -Execution $exec -Notes $notes
                $view.Tag.CurrentExecution = $exec

                if ($exec.IsComplete) {
                    Show-ResultPanel
                } else {
                    Update-StepDisplay
                }
            } catch {
                Write-Warning "Error continuing: $($_.Exception.Message)"
            }
        }.GetNewClosure())

        # Back button click
        $backButton.Add_Click({
            param($sender, $e)
            try {
                $exec = $view.Tag.CurrentExecution
                if ($exec -and $exec.Steps.Count -gt 1) {
                    $exec = DecisionTreeModule\Undo-TreeStep -Execution $exec
                    $view.Tag.CurrentExecution = $exec
                    Update-StepDisplay
                }
            } catch {
                Write-Warning "Error going back: $($_.Exception.Message)"
            }
        }.GetNewClosure())

        # Restart button click
        $restartButton.Add_Click({
            param($sender, $e)
            $treeName = $view.Tag.SelectedTree
            if (-not $treeName) {
                Show-Panel -PanelName 'Welcome'
                $view.Tag.CurrentExecution = $null
                $restartButton.Visibility = 'Collapsed'
                $backButton.Visibility = 'Collapsed'
                return
            }

            try {
                $tree = DecisionTreeModule\Get-BuiltInTree -Name $treeName
                if (-not $tree) {
                    Show-Panel -PanelName 'Welcome'
                    return
                }

                $deviceId = $deviceContextBox.Text
                $interfaceName = $interfaceContextBox.Text

                $exec = DecisionTreeModule\Start-TreeExecution -Tree $tree -DeviceID $deviceId -InterfaceName $interfaceName
                $view.Tag.CurrentExecution = $exec

                $notesBox.Text = ''

                Show-Panel -PanelName 'Step'
                Update-StepDisplay
            } catch {
                Write-Warning "Error restarting tree: $($_.Exception.Message)"
            }
        }.GetNewClosure())

        # Copy Result button click
        $copyResultButton.Add_Click({
            param($sender, $e)
            $text = $resultContent.Text
            if (-not [string]::IsNullOrWhiteSpace($text)) {
                [System.Windows.Clipboard]::SetText($text)
            }
        }.GetNewClosure())

        # Start New button click
        $startNewButton.Add_Click({
            param($sender, $e)
            Show-Panel -PanelName 'Welcome'
            $view.Tag.CurrentExecution = $null
            $restartButton.Visibility = 'Collapsed'
            $backButton.Visibility = 'Collapsed'
            $notesBox.Text = ''
        }.GetNewClosure())

        # Initialize with welcome panel
        Show-Panel -PanelName 'Welcome'
        $restartButton.Visibility = 'Collapsed'
        $backButton.Visibility = 'Collapsed'

        return $view

    } catch {
        Write-Warning "Failed to initialize DecisionTree view: $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function New-DecisionTreeView
