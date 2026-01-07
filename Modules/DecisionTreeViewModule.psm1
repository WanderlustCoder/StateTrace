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

        # Editor controls
        $editTreeButton = $view.FindName('EditTreeButton')
        $newTreeButton = $view.FindName('NewTreeButton')
        $editorPanel = $view.FindName('EditorPanel')
        $editorSaveButton = $view.FindName('EditorSaveButton')
        $editorValidateButton = $view.FindName('EditorValidateButton')
        $editorTestButton = $view.FindName('EditorTestButton')
        $editorExportButton = $view.FindName('EditorExportButton')
        $editorCloseButton = $view.FindName('EditorCloseButton')
        $editorTreeName = $view.FindName('EditorTreeName')
        $editorTreeCategory = $view.FindName('EditorTreeCategory')
        $editorTreeDescription = $view.FindName('EditorTreeDescription')
        $editorNodesList = $view.FindName('EditorNodesList')
        $addDecisionNodeButton = $view.FindName('AddDecisionNodeButton')
        $addActionNodeButton = $view.FindName('AddActionNodeButton')
        $addInputNodeButton = $view.FindName('AddInputNodeButton')
        $addResultNodeButton = $view.FindName('AddResultNodeButton')
        $removeNodeButton = $view.FindName('RemoveNodeButton')
        $editorValidationPanel = $view.FindName('EditorValidationPanel')
        $editorValidationHeader = $view.FindName('EditorValidationHeader')
        $editorValidationMessages = $view.FindName('EditorValidationMessages')
        $nodeIdBox = $view.FindName('NodeIdBox')
        $nodeTypeBox = $view.FindName('NodeTypeBox')
        $nodeTitleBox = $view.FindName('NodeTitleBox')
        $nodeContentBox = $view.FindName('NodeContentBox')
        $nextNodeLabel = $view.FindName('NextNodeLabel')
        $nextNodeBox = $view.FindName('NextNodeBox')
        $branchesPanel = $view.FindName('BranchesPanel')
        $branchesListBox = $view.FindName('BranchesListBox')
        $addBranchButton = $view.FindName('AddBranchButton')
        $removeBranchButton = $view.FindName('RemoveBranchButton')
        $variablePanel = $view.FindName('VariablePanel')
        $variableNameBox = $view.FindName('VariableNameBox')
        $outcomePanel = $view.FindName('OutcomePanel')
        $outcomeBox = $view.FindName('OutcomeBox')
        $applyNodeChangesButton = $view.FindName('ApplyNodeChangesButton')

        # Store current state in view's Tag
        $view.Tag = @{
            SelectedTree = $null
            CurrentExecution = $null
            AllTrees = @()
            EditingTree = $null
            EditorMode = $false
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
                ViewCompositionModule\Show-CopyFeedback -Button $sender
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

        # ========================================
        # EDITOR FUNCTIONALITY
        # ========================================

        # Helper to show/hide editor panel
        function Show-EditorPanel {
            param([bool]$Show)
            if ($Show) {
                $editorPanel.Visibility = 'Visible'
                $welcomePanel.Visibility = 'Collapsed'
                $stepPanel.Visibility = 'Collapsed'
                $resultPanel.Visibility = 'Collapsed'
                $view.Tag.EditorMode = $true
            } else {
                $editorPanel.Visibility = 'Collapsed'
                $view.Tag.EditorMode = $false
                $view.Tag.EditingTree = $null
                Show-Panel -PanelName 'Welcome'
            }
        }

        # Helper to create a new empty tree
        function New-EmptyTree {
            return @{
                Name = 'NewTree'
                Category = 'General'
                Description = 'New troubleshooting tree'
                StartNode = 'start'
                Nodes = [System.Collections.ArrayList]@(
                    @{
                        Id = 'start'
                        Type = 'decision'
                        Title = 'Start Here'
                        Content = 'What is the issue?'
                        Branches = [System.Collections.ArrayList]@(
                            @{ Answer = 'Option A'; NextNode = 'result1' }
                            @{ Answer = 'Option B'; NextNode = 'result1' }
                        )
                    },
                    @{
                        Id = 'result1'
                        Type = 'result'
                        Title = 'Resolution'
                        Content = 'Issue resolved.'
                        Outcome = 'resolved'
                    }
                )
            }
        }

        # Helper to update the nodes list in editor
        function Update-EditorNodesList {
            $tree = $view.Tag.EditingTree
            if (-not $tree) { return }

            $nodeItems = [System.Collections.ArrayList]::new()
            foreach ($node in $tree.Nodes) {
                $displayText = "[$($node.Type)] $($node.Id): $($node.Title)"
                [void]$nodeItems.Add(@{
                    Display = $displayText
                    NodeId = $node.Id
                })
            }
            $editorNodesList.ItemsSource = $nodeItems
            $editorNodesList.DisplayMemberPath = 'Display'
        }

        # Helper to load node properties into editor
        function Load-NodeProperties {
            param([string]$NodeId)
            $tree = $view.Tag.EditingTree
            if (-not $tree -or -not $NodeId) { return }

            $node = $tree.Nodes | Where-Object { $_.Id -eq $NodeId }
            if (-not $node) { return }

            $nodeIdBox.Text = $node.Id
            $nodeTypeBox.SelectedValue = $node.Type
            $nodeTitleBox.Text = $node.Title
            $nodeContentBox.Text = if ($node.Content) { $node.Content } else { '' }

            # Show/hide type-specific panels
            $branchesPanel.Visibility = 'Collapsed'
            $variablePanel.Visibility = 'Collapsed'
            $outcomePanel.Visibility = 'Collapsed'
            $nextNodeLabel.Visibility = 'Collapsed'
            $nextNodeBox.Visibility = 'Collapsed'

            switch ($node.Type) {
                'decision' {
                    $branchesPanel.Visibility = 'Visible'
                    $branchItems = [System.Collections.ArrayList]::new()
                    if ($node.Branches) {
                        foreach ($branch in $node.Branches) {
                            [void]$branchItems.Add("$($branch.Answer) -> $($branch.NextNode)")
                        }
                    }
                    $branchesListBox.ItemsSource = $branchItems
                }
                'input' {
                    $variablePanel.Visibility = 'Visible'
                    $nextNodeLabel.Visibility = 'Visible'
                    $nextNodeBox.Visibility = 'Visible'
                    $variableNameBox.Text = if ($node.Variable) { $node.Variable } else { '' }
                    $nextNodeBox.Text = if ($node.NextNode) { $node.NextNode } else { '' }
                }
                'action' {
                    $nextNodeLabel.Visibility = 'Visible'
                    $nextNodeBox.Visibility = 'Visible'
                    $nextNodeBox.Text = if ($node.NextNode) { $node.NextNode } else { '' }
                }
                'check' {
                    $nextNodeLabel.Visibility = 'Visible'
                    $nextNodeBox.Visibility = 'Visible'
                    $nextNodeBox.Text = if ($node.NextNode) { $node.NextNode } else { '' }
                }
                'result' {
                    $outcomePanel.Visibility = 'Visible'
                    $outcomeBox.Text = if ($node.Outcome) { $node.Outcome } else { 'resolved' }
                }
            }
        }

        # Helper to validate tree structure
        function Test-TreeValidity {
            $tree = $view.Tag.EditingTree
            if (-not $tree) { return @() }

            $messages = [System.Collections.ArrayList]::new()

            # Check for required fields
            if ([string]::IsNullOrWhiteSpace($tree.Name)) {
                [void]$messages.Add(@{ Level = 'Error'; Message = 'Tree name is required' })
            }
            if (-not $tree.Nodes -or $tree.Nodes.Count -eq 0) {
                [void]$messages.Add(@{ Level = 'Error'; Message = 'Tree must have at least one node' })
            }

            # Check start node exists
            $startNode = $tree.Nodes | Where-Object { $_.Id -eq $tree.StartNode }
            if (-not $startNode) {
                [void]$messages.Add(@{ Level = 'Error'; Message = "Start node '$($tree.StartNode)' not found" })
            }

            # Check all referenced nodes exist
            $nodeIds = @($tree.Nodes | ForEach-Object { $_.Id })
            foreach ($node in $tree.Nodes) {
                if ($node.NextNode -and $node.NextNode -notin $nodeIds) {
                    [void]$messages.Add(@{ Level = 'Error'; Message = "Node '$($node.Id)' references missing node '$($node.NextNode)'" })
                }
                if ($node.Branches) {
                    foreach ($branch in $node.Branches) {
                        if ($branch.NextNode -and $branch.NextNode -notin $nodeIds) {
                            [void]$messages.Add(@{ Level = 'Error'; Message = "Node '$($node.Id)' branch '$($branch.Answer)' references missing node '$($branch.NextNode)'" })
                        }
                    }
                }
            }

            # Check for at least one result node
            $resultNodes = @($tree.Nodes | Where-Object { $_.Type -eq 'result' })
            if ($resultNodes.Count -eq 0) {
                [void]$messages.Add(@{ Level = 'Warning'; Message = 'Tree has no result nodes - execution will never complete' })
            }

            # Check for orphan nodes (not reachable from start)
            $reachable = [System.Collections.Generic.HashSet[string]]::new()
            $queue = [System.Collections.Queue]::new()
            $queue.Enqueue($tree.StartNode)
            while ($queue.Count -gt 0) {
                $currentId = $queue.Dequeue()
                if ($reachable.Contains($currentId)) { continue }
                [void]$reachable.Add($currentId)
                $current = $tree.Nodes | Where-Object { $_.Id -eq $currentId }
                if ($current) {
                    if ($current.NextNode) { $queue.Enqueue($current.NextNode) }
                    if ($current.Branches) {
                        foreach ($b in $current.Branches) {
                            if ($b.NextNode) { $queue.Enqueue($b.NextNode) }
                        }
                    }
                }
            }
            foreach ($node in $tree.Nodes) {
                if (-not $reachable.Contains($node.Id)) {
                    [void]$messages.Add(@{ Level = 'Warning'; Message = "Node '$($node.Id)' is not reachable from start node" })
                }
            }

            return $messages
        }

        # Helper to show validation messages
        function Show-ValidationMessages {
            param([array]$Messages)
            if ($Messages.Count -eq 0) {
                $editorValidationPanel.Visibility = 'Collapsed'
                return
            }

            $editorValidationPanel.Visibility = 'Visible'
            $errorCount = @($Messages | Where-Object { $_.Level -eq 'Error' }).Count
            $warnCount = @($Messages | Where-Object { $_.Level -eq 'Warning' }).Count
            $editorValidationHeader.Text = "Validation: $errorCount error(s), $warnCount warning(s)"

            $msgText = ($Messages | ForEach-Object { "[$($_.Level)] $($_.Message)" }) -join "`n"
            $editorValidationMessages.Text = $msgText
        }

        # Edit Tree button click
        $editTreeButton.Add_Click({
            param($sender, $e)
            $treeName = $view.Tag.SelectedTree
            if (-not $treeName) { return }

            try {
                $tree = DecisionTreeModule\Get-BuiltInTree -Name $treeName
                if (-not $tree) { return }

                # Deep clone the tree for editing
                $editTree = @{
                    Name = $tree.Name
                    Category = $tree.Category
                    Description = $tree.Description
                    StartNode = $tree.StartNode
                    Nodes = [System.Collections.ArrayList]::new()
                }
                foreach ($node in $tree.Nodes) {
                    $nodeCopy = @{
                        Id = $node.Id
                        Type = $node.Type
                        Title = $node.Title
                        Content = $node.Content
                    }
                    if ($node.NextNode) { $nodeCopy.NextNode = $node.NextNode }
                    if ($node.Variable) { $nodeCopy.Variable = $node.Variable }
                    if ($node.Outcome) { $nodeCopy.Outcome = $node.Outcome }
                    if ($node.Branches) {
                        $nodeCopy.Branches = [System.Collections.ArrayList]::new()
                        foreach ($b in $node.Branches) {
                            [void]$nodeCopy.Branches.Add(@{ Answer = $b.Answer; NextNode = $b.NextNode })
                        }
                    }
                    [void]$editTree.Nodes.Add($nodeCopy)
                }

                $view.Tag.EditingTree = $editTree
                $editorTreeName.Text = $editTree.Name
                $editorTreeCategory.Text = $editTree.Category
                $editorTreeDescription.Text = $editTree.Description

                Update-EditorNodesList
                Show-EditorPanel -Show $true
                $editorValidationPanel.Visibility = 'Collapsed'

                if ($editTree.Nodes.Count -gt 0) {
                    $editorNodesList.SelectedIndex = 0
                }
            } catch {
                Write-Warning "Error loading tree for editing: $($_.Exception.Message)"
            }
        }.GetNewClosure())

        # New Tree button click
        $newTreeButton.Add_Click({
            param($sender, $e)
            $editTree = New-EmptyTree
            $view.Tag.EditingTree = $editTree
            $editorTreeName.Text = $editTree.Name
            $editorTreeCategory.Text = $editTree.Category
            $editorTreeDescription.Text = $editTree.Description

            Update-EditorNodesList
            Show-EditorPanel -Show $true
            $editorValidationPanel.Visibility = 'Collapsed'

            if ($editTree.Nodes.Count -gt 0) {
                $editorNodesList.SelectedIndex = 0
            }
        }.GetNewClosure())

        # Editor node selection change
        $editorNodesList.Add_SelectionChanged({
            param($sender, $e)
            $selected = $sender.SelectedItem
            if ($selected) {
                Load-NodeProperties -NodeId $selected.NodeId
            }
        }.GetNewClosure())

        # Add Decision Node button
        $addDecisionNodeButton.Add_Click({
            param($sender, $e)
            $tree = $view.Tag.EditingTree
            if (-not $tree) { return }

            $newId = "decision_$([guid]::NewGuid().ToString('N').Substring(0,8))"
            $newNode = @{
                Id = $newId
                Type = 'decision'
                Title = 'New Decision'
                Content = 'Choose an option:'
                Branches = [System.Collections.ArrayList]@(
                    @{ Answer = 'Yes'; NextNode = '' }
                    @{ Answer = 'No'; NextNode = '' }
                )
            }
            [void]$tree.Nodes.Add($newNode)
            Update-EditorNodesList
            $editorNodesList.SelectedIndex = $tree.Nodes.Count - 1
        }.GetNewClosure())

        # Add Action Node button
        $addActionNodeButton.Add_Click({
            param($sender, $e)
            $tree = $view.Tag.EditingTree
            if (-not $tree) { return }

            $newId = "action_$([guid]::NewGuid().ToString('N').Substring(0,8))"
            $newNode = @{
                Id = $newId
                Type = 'action'
                Title = 'New Action'
                Content = 'Perform this action...'
                NextNode = ''
            }
            [void]$tree.Nodes.Add($newNode)
            Update-EditorNodesList
            $editorNodesList.SelectedIndex = $tree.Nodes.Count - 1
        }.GetNewClosure())

        # Add Input Node button
        $addInputNodeButton.Add_Click({
            param($sender, $e)
            $tree = $view.Tag.EditingTree
            if (-not $tree) { return }

            $newId = "input_$([guid]::NewGuid().ToString('N').Substring(0,8))"
            $newNode = @{
                Id = $newId
                Type = 'input'
                Title = 'New Input'
                Content = 'Enter a value:'
                Variable = 'userInput'
                NextNode = ''
            }
            [void]$tree.Nodes.Add($newNode)
            Update-EditorNodesList
            $editorNodesList.SelectedIndex = $tree.Nodes.Count - 1
        }.GetNewClosure())

        # Add Result Node button
        $addResultNodeButton.Add_Click({
            param($sender, $e)
            $tree = $view.Tag.EditingTree
            if (-not $tree) { return }

            $newId = "result_$([guid]::NewGuid().ToString('N').Substring(0,8))"
            $newNode = @{
                Id = $newId
                Type = 'result'
                Title = 'New Result'
                Content = 'Issue resolved.'
                Outcome = 'resolved'
            }
            [void]$tree.Nodes.Add($newNode)
            Update-EditorNodesList
            $editorNodesList.SelectedIndex = $tree.Nodes.Count - 1
        }.GetNewClosure())

        # Remove Node button
        $removeNodeButton.Add_Click({
            param($sender, $e)
            $tree = $view.Tag.EditingTree
            $selected = $editorNodesList.SelectedItem
            if (-not $tree -or -not $selected) { return }

            $nodeToRemove = $tree.Nodes | Where-Object { $_.Id -eq $selected.NodeId }
            if ($nodeToRemove) {
                [void]$tree.Nodes.Remove($nodeToRemove)
                Update-EditorNodesList
                if ($tree.Nodes.Count -gt 0) {
                    $editorNodesList.SelectedIndex = 0
                }
            }
        }.GetNewClosure())

        # Apply Node Changes button
        $applyNodeChangesButton.Add_Click({
            param($sender, $e)
            $tree = $view.Tag.EditingTree
            $selected = $editorNodesList.SelectedItem
            if (-not $tree -or -not $selected) { return }

            $node = $tree.Nodes | Where-Object { $_.Id -eq $selected.NodeId }
            if (-not $node) { return }

            # Update basic properties
            $node.Id = $nodeIdBox.Text
            $node.Title = $nodeTitleBox.Text
            $node.Content = $nodeContentBox.Text

            # Update type-specific properties
            switch ($node.Type) {
                'input' {
                    $node.Variable = $variableNameBox.Text
                    $node.NextNode = $nextNodeBox.Text
                }
                'action' {
                    $node.NextNode = $nextNodeBox.Text
                }
                'check' {
                    $node.NextNode = $nextNodeBox.Text
                }
                'result' {
                    $node.Outcome = $outcomeBox.Text
                }
            }

            Update-EditorNodesList
            # Re-select the node (ID may have changed)
            for ($i = 0; $i -lt $tree.Nodes.Count; $i++) {
                if ($tree.Nodes[$i].Id -eq $nodeIdBox.Text) {
                    $editorNodesList.SelectedIndex = $i
                    break
                }
            }
        }.GetNewClosure())

        # Editor Validate button
        $editorValidateButton.Add_Click({
            param($sender, $e)
            # Update tree metadata from UI
            $tree = $view.Tag.EditingTree
            if ($tree) {
                $tree.Name = $editorTreeName.Text
                $tree.Category = $editorTreeCategory.Text
                $tree.Description = $editorTreeDescription.Text
            }

            $messages = Test-TreeValidity
            Show-ValidationMessages -Messages $messages
        }.GetNewClosure())

        # Editor Test Run button
        $editorTestButton.Add_Click({
            param($sender, $e)
            $tree = $view.Tag.EditingTree
            if (-not $tree) { return }

            # Validate first
            $messages = Test-TreeValidity
            $errors = @($messages | Where-Object { $_.Level -eq 'Error' })
            if ($errors.Count -gt 0) {
                Show-ValidationMessages -Messages $messages
                return
            }

            try {
                # Create tree object for execution
                $testTree = [PSCustomObject]@{
                    Name = $tree.Name
                    Category = $tree.Category
                    Description = $tree.Description
                    StartNode = $tree.StartNode
                    Nodes = $tree.Nodes
                }

                $exec = DecisionTreeModule\Start-TreeExecution -Tree $testTree
                $view.Tag.CurrentExecution = $exec
                $view.Tag.EditorMode = $false
                $editorPanel.Visibility = 'Collapsed'

                Show-Panel -PanelName 'Step'
                Update-StepDisplay
            } catch {
                Write-Warning "Error starting test run: $($_.Exception.Message)"
            }
        }.GetNewClosure())

        # Editor Save button
        $editorSaveButton.Add_Click({
            param($sender, $e)
            $tree = $view.Tag.EditingTree
            if (-not $tree) { return }

            # Update metadata from UI
            $tree.Name = $editorTreeName.Text
            $tree.Category = $editorTreeCategory.Text
            $tree.Description = $editorTreeDescription.Text

            # Validate
            $messages = Test-TreeValidity
            $errors = @($messages | Where-Object { $_.Level -eq 'Error' })
            if ($errors.Count -gt 0) {
                Show-ValidationMessages -Messages $messages
                return
            }

            try {
                # Save to custom trees folder
                $customTreesPath = Join-Path $ScriptDir 'Data\CustomTrees'
                if (-not (Test-Path $customTreesPath)) {
                    New-Item -Path $customTreesPath -ItemType Directory -Force | Out-Null
                }

                $treePath = Join-Path $customTreesPath "$($tree.Name).json"
                $tree | ConvertTo-Json -Depth 10 | Set-Content -Path $treePath -Encoding UTF8

                # Refresh tree list
                Update-TreeList -Category 'All Categories'
                Show-EditorPanel -Show $false
            } catch {
                Write-Warning "Error saving tree: $($_.Exception.Message)"
            }
        }.GetNewClosure())

        # Editor Export button
        $editorExportButton.Add_Click({
            param($sender, $e)
            $tree = $view.Tag.EditingTree
            if (-not $tree) { return }

            # Update metadata from UI
            $tree.Name = $editorTreeName.Text
            $tree.Category = $editorTreeCategory.Text
            $tree.Description = $editorTreeDescription.Text

            try {
                $dialog = New-Object Microsoft.Win32.SaveFileDialog
                $dialog.Filter = 'JSON files (*.json)|*.json|All files (*.*)|*.*'
                $dialog.DefaultExt = '.json'
                $dialog.FileName = "$($tree.Name).json"

                if ($dialog.ShowDialog()) {
                    $tree | ConvertTo-Json -Depth 10 | Set-Content -Path $dialog.FileName -Encoding UTF8
                }
            } catch {
                Write-Warning "Error exporting tree: $($_.Exception.Message)"
            }
        }.GetNewClosure())

        # Editor Close button
        $editorCloseButton.Add_Click({
            param($sender, $e)
            Show-EditorPanel -Show $false
        }.GetNewClosure())

        # Add/Remove Branch buttons
        $addBranchButton.Add_Click({
            param($sender, $e)
            $tree = $view.Tag.EditingTree
            $selected = $editorNodesList.SelectedItem
            if (-not $tree -or -not $selected) { return }

            $node = $tree.Nodes | Where-Object { $_.Id -eq $selected.NodeId }
            if (-not $node -or $node.Type -ne 'decision') { return }

            if (-not $node.Branches) {
                $node.Branches = [System.Collections.ArrayList]::new()
            }
            [void]$node.Branches.Add(@{ Answer = 'New Option'; NextNode = '' })
            Load-NodeProperties -NodeId $node.Id
        }.GetNewClosure())

        $removeBranchButton.Add_Click({
            param($sender, $e)
            $tree = $view.Tag.EditingTree
            $selected = $editorNodesList.SelectedItem
            $branchIndex = $branchesListBox.SelectedIndex
            if (-not $tree -or -not $selected -or $branchIndex -lt 0) { return }

            $node = $tree.Nodes | Where-Object { $_.Id -eq $selected.NodeId }
            if (-not $node -or -not $node.Branches -or $branchIndex -ge $node.Branches.Count) { return }

            $node.Branches.RemoveAt($branchIndex)
            Load-NodeProperties -NodeId $node.Id
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
