Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Decision tree engine for guided troubleshooting workflows.

.DESCRIPTION
    Provides functions to create, load, validate, and execute decision trees
    for systematic troubleshooting. Supports built-in trees for common network
    issues and custom tree creation.
#>

# Built-in tree definitions storage
$script:BuiltInTrees = @{}

<#
.SYNOPSIS
    Creates a new empty decision tree.
#>
function New-DecisionTree {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name,

        [string]$Description = '',

        [string]$Category = 'Custom',

        [string]$Version = '1.0'
    )

    return [pscustomobject]@{
        Name = $Name
        Description = $Description
        Category = $Category
        Version = $Version
        Nodes = [System.Collections.ArrayList]::new()
        StartNodeId = $null
        Author = $env:USERNAME
        CreatedDate = (Get-Date).ToString('yyyy-MM-dd')
        ModifiedDate = (Get-Date).ToString('yyyy-MM-dd')
        IsBuiltIn = $false
        IsEnabled = $true
    }
}

<#
.SYNOPSIS
    Imports a decision tree from JSON.
#>
function Import-DecisionTree {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ParameterSetName='Json')]
        [string]$Json,

        [Parameter(Mandatory=$true, ParameterSetName='Path')]
        [string]$Path
    )

    if ($PSCmdlet.ParameterSetName -eq 'Path') {
        if (-not (Test-Path -LiteralPath $Path)) {
            throw "Tree file not found: $Path"
        }
        $Json = Get-Content -LiteralPath $Path -Raw
    }

    $data = $Json | ConvertFrom-Json

    # Helper to safely get property value
    function Get-SafeProperty {
        param($obj, $propName, $default = $null)
        if ($obj.PSObject.Properties[$propName]) {
            return $obj.$propName
        }
        return $default
    }

    $tree = [pscustomobject]@{
        Name = if (Get-SafeProperty $data 'name') { $data.name } else { 'Unnamed' }
        Description = if (Get-SafeProperty $data 'description') { $data.description } else { '' }
        Category = if (Get-SafeProperty $data 'category') { $data.category } else { 'Custom' }
        Version = if (Get-SafeProperty $data 'version') { $data.version } else { '1.0' }
        Nodes = [System.Collections.ArrayList]::new()
        StartNodeId = $null
        Author = if (Get-SafeProperty $data 'author') { $data.author } else { '' }
        CreatedDate = if (Get-SafeProperty $data 'createdDate') { $data.createdDate } else { '' }
        ModifiedDate = (Get-Date).ToString('yyyy-MM-dd')
        IsBuiltIn = if (Get-SafeProperty $data 'isBuiltIn') { [bool]$data.isBuiltIn } else { $false }
        IsEnabled = $true
    }

    if (Get-SafeProperty $data 'nodes') {
        foreach ($node in $data.nodes) {
            $nodeObj = [pscustomobject]@{
                Id = $node.id
                Type = $node.type
                Title = if (Get-SafeProperty $node 'title') { $node.title } else { '' }
                Content = if (Get-SafeProperty $node 'content') { $node.content } else { '' }
                VariableName = if (Get-SafeProperty $node 'variableName') { $node.variableName } else { $null }
                ValidationPattern = if (Get-SafeProperty $node 'validationPattern') { $node.validationPattern } else { $null }
                Next = if (Get-SafeProperty $node 'next') { $node.next } else { $null }
                Branches = [System.Collections.ArrayList]::new()
                Outcome = if (Get-SafeProperty $node 'outcome') { $node.outcome } else { $null }
            }

            if (Get-SafeProperty $node 'branches') {
                foreach ($branch in $node.branches) {
                    $branchObj = [pscustomobject]@{
                        Answer = if (Get-SafeProperty $branch 'answer') { $branch.answer } else { $null }
                        Condition = if (Get-SafeProperty $branch 'condition') { $branch.condition } else { $null }
                        Next = $branch.next
                        Label = if (Get-SafeProperty $branch 'label') { $branch.label } else { $null }
                    }
                    [void]$nodeObj.Branches.Add($branchObj)
                }
            }

            [void]$tree.Nodes.Add($nodeObj)
        }
    }

    # Set start node (first node or explicitly marked)
    if (Get-SafeProperty $data 'startNode') {
        $tree.StartNodeId = $data.startNode
    } elseif ($tree.Nodes.Count -gt 0) {
        $tree.StartNodeId = $tree.Nodes[0].Id
    }

    return $tree
}

<#
.SYNOPSIS
    Validates a decision tree structure.
#>
function Test-DecisionTree {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [pscustomobject]$Tree
    )

    $errors = [System.Collections.ArrayList]::new()
    $warnings = [System.Collections.ArrayList]::new()
    $nodeIds = @{}

    # Build node ID lookup
    foreach ($node in $Tree.Nodes) {
        if ($nodeIds.ContainsKey($node.Id)) {
            [void]$errors.Add("Duplicate node ID: $($node.Id)")
        } else {
            $nodeIds[$node.Id] = $node
        }
    }

    # Check for orphan nodes and invalid references
    $reachable = @{}
    if ($Tree.StartNodeId) {
        $reachable[$Tree.StartNodeId] = $true
    }

    foreach ($node in $Tree.Nodes) {
        # Check Next reference
        if ($node.Next -and -not $nodeIds.ContainsKey($node.Next)) {
            [void]$errors.Add("Invalid target node: $($node.Next) (from $($node.Id))")
        } elseif ($node.Next) {
            $reachable[$node.Next] = $true
        }

        # Check Branch references
        foreach ($branch in $node.Branches) {
            if ($branch.Next -and -not $nodeIds.ContainsKey($branch.Next)) {
                [void]$errors.Add("Invalid target node: $($branch.Next) (from $($node.Id))")
            } elseif ($branch.Next) {
                $reachable[$branch.Next] = $true
            }
        }
    }

    # Check for orphan nodes (not reachable from start)
    foreach ($node in $Tree.Nodes) {
        if (-not $reachable.ContainsKey($node.Id) -and $node.Id -ne $Tree.StartNodeId) {
            [void]$errors.Add("Orphan node: $($node.Id)")
        }
    }

    # Check for potential loops (simple detection)
    $visited = @{}
    $stack = [System.Collections.ArrayList]::new()

    function Test-LoopFrom {
        param($nodeId, $path)
        if (-not $nodeId -or -not $nodeIds.ContainsKey($nodeId)) { return }
        if ($path -contains $nodeId) {
            [void]$warnings.Add("Potential loop detected: $($path -join ' -> ') -> $nodeId")
            return
        }
        $newPath = @($path) + $nodeId
        $node = $nodeIds[$nodeId]
        if ($node.Next) {
            Test-LoopFrom -nodeId $node.Next -path $newPath
        }
        foreach ($branch in $node.Branches) {
            if ($branch.Next) {
                Test-LoopFrom -nodeId $branch.Next -path $newPath
            }
        }
    }

    if ($Tree.StartNodeId) {
        Test-LoopFrom -nodeId $Tree.StartNodeId -path @()
    }

    # Check for result nodes
    $hasResult = $Tree.Nodes | Where-Object { $_.Type -eq 'result' }
    if (-not $hasResult) {
        [void]$warnings.Add("Tree has no result nodes")
    }

    return [pscustomobject]@{
        IsValid = ($errors.Count -eq 0)
        Errors = @($errors)
        Warnings = @($warnings)
    }
}

<#
.SYNOPSIS
    Adds a node to a decision tree.
#>
function Add-TreeNode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [pscustomobject]$Tree,

        [Parameter(Mandatory=$true)]
        [string]$Id,

        [Parameter(Mandatory=$true)]
        [ValidateSet('decision', 'action', 'input', 'branch', 'result', 'check')]
        [string]$Type,

        [string]$Title = '',

        [string]$Content = '',

        [string]$VariableName,

        [string]$ValidationPattern,

        [string]$Next,

        [array]$Branches,

        [string]$Outcome
    )

    $node = [pscustomobject]@{
        Id = $Id
        Type = $Type
        Title = $Title
        Content = $Content
        VariableName = $VariableName
        ValidationPattern = $ValidationPattern
        Next = $Next
        Branches = [System.Collections.ArrayList]::new()
        Outcome = $Outcome
    }

    if ($Branches) {
        foreach ($branch in $Branches) {
            # Handle both hashtable and psobject inputs
            $answer = $null
            $condition = $null
            $next = $null
            $label = $null

            if ($branch -is [hashtable]) {
                if ($branch.ContainsKey('Answer')) { $answer = $branch['Answer'] }
                if ($branch.ContainsKey('Condition')) { $condition = $branch['Condition'] }
                if ($branch.ContainsKey('Next')) { $next = $branch['Next'] }
                if ($branch.ContainsKey('Label')) { $label = $branch['Label'] }
            } else {
                if ($branch.PSObject.Properties['Answer']) { $answer = $branch.Answer }
                if ($branch.PSObject.Properties['Condition']) { $condition = $branch.Condition }
                if ($branch.PSObject.Properties['Next']) { $next = $branch.Next }
                if ($branch.PSObject.Properties['Label']) { $label = $branch.Label }
            }

            $branchObj = [pscustomobject]@{
                Answer = $answer
                Condition = $condition
                Next = $next
                Label = $label
            }
            [void]$node.Branches.Add($branchObj)
        }
    }

    [void]$Tree.Nodes.Add($node)

    # Set as start node if first
    if ($Tree.Nodes.Count -eq 1) {
        $Tree.StartNodeId = $Id
    }

    $Tree.ModifiedDate = (Get-Date).ToString('yyyy-MM-dd')

    return $node
}

<#
.SYNOPSIS
    Removes a node from a decision tree.
#>
function Remove-TreeNode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [pscustomobject]$Tree,

        [Parameter(Mandatory=$true)]
        [string]$Id
    )

    # Remove the node
    $nodeToRemove = $Tree.Nodes | Where-Object { $_.Id -eq $Id }
    if ($nodeToRemove) {
        [void]$Tree.Nodes.Remove($nodeToRemove)
    }

    # Clear references to removed node
    foreach ($node in $Tree.Nodes) {
        if ($node.Next -eq $Id) {
            $node.Next = $null
        }
        foreach ($branch in $node.Branches) {
            if ($branch.Next -eq $Id) {
                $branch.Next = $null
            }
        }
    }

    # Update start node if needed
    if ($Tree.StartNodeId -eq $Id) {
        $Tree.StartNodeId = if ($Tree.Nodes.Count -gt 0) { $Tree.Nodes[0].Id } else { $null }
    }

    $Tree.ModifiedDate = (Get-Date).ToString('yyyy-MM-dd')
}

<#
.SYNOPSIS
    Starts execution of a decision tree.
#>
function Start-TreeExecution {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [pscustomobject]$Tree,

        [string]$DeviceID,

        [string]$InterfaceName
    )

    $startNode = $Tree.Nodes | Where-Object { $_.Id -eq $Tree.StartNodeId }

    $execution = [pscustomobject]@{
        Tree = $Tree
        CurrentNode = $startNode
        Steps = [System.Collections.ArrayList]::new()
        Variables = @{}
        DeviceID = $DeviceID
        InterfaceName = $InterfaceName
        StartTime = Get-Date
        EndTime = $null
        IsComplete = $false
        Outcome = $null
        Duration = $null
    }

    # Record first step
    $step = [pscustomobject]@{
        NodeId = $startNode.Id
        Timestamp = Get-Date
        Answer = $null
        InputValue = $null
        Duration = $null
    }
    [void]$execution.Steps.Add($step)

    return $execution
}

<#
.SYNOPSIS
    Submits an answer to advance the decision tree.
#>
function Submit-TreeAnswer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [pscustomobject]$Execution,

        [Parameter(Mandatory=$true)]
        [string]$Answer
    )

    $currentNode = $Execution.CurrentNode

    if ($currentNode.Type -ne 'decision') {
        throw "Current node is not a decision node"
    }

    # Find matching branch
    $nextNodeId = $null
    foreach ($branch in $currentNode.Branches) {
        if ($branch.Answer -eq $Answer) {
            $nextNodeId = $branch.Next
            break
        }
    }

    if (-not $nextNodeId) {
        throw "No branch found for answer: $Answer"
    }

    # Record answer in current step
    $currentStep = $Execution.Steps[$Execution.Steps.Count - 1]
    $currentStep.Answer = $Answer
    $currentStep.Duration = ((Get-Date) - $currentStep.Timestamp)

    # Find next node
    $nextNode = $Execution.Tree.Nodes | Where-Object { $_.Id -eq $nextNodeId }
    if (-not $nextNode) {
        throw "Next node not found: $nextNodeId"
    }

    $Execution.CurrentNode = $nextNode

    # Record new step
    $step = [pscustomobject]@{
        NodeId = $nextNode.Id
        Timestamp = Get-Date
        Answer = $null
        InputValue = $null
        Duration = $null
    }
    [void]$Execution.Steps.Add($step)

    # Check if complete
    if ($nextNode.Type -eq 'result') {
        $Execution.IsComplete = $true
        $Execution.EndTime = Get-Date
        $Execution.Outcome = $nextNode.Outcome
        $Execution.Duration = ($Execution.EndTime - $Execution.StartTime)
    }

    return $Execution
}

<#
.SYNOPSIS
    Submits an input value and advances based on branch conditions.
#>
function Submit-TreeInput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [pscustomobject]$Execution,

        [Parameter(Mandatory=$true)]
        $Value
    )

    $currentNode = $Execution.CurrentNode

    if ($currentNode.Type -ne 'input' -and $currentNode.Type -ne 'branch') {
        throw "Current node is not an input or branch node"
    }

    # Store variable if named
    if ($currentNode.VariableName) {
        $Execution.Variables[$currentNode.VariableName] = $Value
    }

    # Record input in current step
    $currentStep = $Execution.Steps[$Execution.Steps.Count - 1]
    $currentStep.InputValue = $Value
    $currentStep.Duration = ((Get-Date) - $currentStep.Timestamp)

    # Determine next node
    $nextNodeId = $null

    if ($currentNode.Type -eq 'input' -and $currentNode.Next) {
        $nextNodeId = $currentNode.Next
    } elseif ($currentNode.Branches.Count -gt 0) {
        # Evaluate branch conditions
        foreach ($branch in $currentNode.Branches) {
            if ($branch.Condition) {
                # Create a safe evaluation context
                $evalResult = $false
                try {
                    $vars = $Execution.Variables
                    foreach ($key in $vars.Keys) {
                        Set-Variable -Name $key -Value $vars[$key] -Scope Local
                    }
                    $evalResult = Invoke-Expression $branch.Condition
                } catch {
                    $evalResult = $false
                }
                if ($evalResult) {
                    $nextNodeId = $branch.Next
                    break
                }
            }
        }
    }

    if (-not $nextNodeId) {
        throw "No valid next node determined"
    }

    # Find next node
    $nextNode = $Execution.Tree.Nodes | Where-Object { $_.Id -eq $nextNodeId }
    if (-not $nextNode) {
        throw "Next node not found: $nextNodeId"
    }

    $Execution.CurrentNode = $nextNode

    # Record new step
    $step = [pscustomobject]@{
        NodeId = $nextNode.Id
        Timestamp = Get-Date
        Answer = $null
        InputValue = $null
        Duration = $null
    }
    [void]$Execution.Steps.Add($step)

    # Check if complete
    if ($nextNode.Type -eq 'result') {
        $Execution.IsComplete = $true
        $Execution.EndTime = Get-Date
        $Execution.Outcome = $nextNode.Outcome
        $Execution.Duration = ($Execution.EndTime - $Execution.StartTime)
    }

    return $Execution
}

<#
.SYNOPSIS
    Continues execution for action/check nodes.
#>
function Continue-TreeExecution {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [pscustomobject]$Execution,

        [string]$Notes
    )

    $currentNode = $Execution.CurrentNode

    if ($currentNode.Type -ne 'action' -and $currentNode.Type -ne 'check') {
        throw "Current node is not an action or check node"
    }

    if (-not $currentNode.Next) {
        throw "No next node defined for this action"
    }

    # Record in current step
    $currentStep = $Execution.Steps[$Execution.Steps.Count - 1]
    $currentStep.Duration = ((Get-Date) - $currentStep.Timestamp)
    if ($Notes) {
        $currentStep | Add-Member -NotePropertyName 'Notes' -NotePropertyValue $Notes -Force
    }

    # Find next node
    $nextNode = $Execution.Tree.Nodes | Where-Object { $_.Id -eq $currentNode.Next }
    if (-not $nextNode) {
        throw "Next node not found: $($currentNode.Next)"
    }

    $Execution.CurrentNode = $nextNode

    # Record new step
    $step = [pscustomobject]@{
        NodeId = $nextNode.Id
        Timestamp = Get-Date
        Answer = $null
        InputValue = $null
        Duration = $null
    }
    [void]$Execution.Steps.Add($step)

    # Check if complete
    if ($nextNode.Type -eq 'result') {
        $Execution.IsComplete = $true
        $Execution.EndTime = Get-Date
        $Execution.Outcome = $nextNode.Outcome
        $Execution.Duration = ($Execution.EndTime - $Execution.StartTime)
    }

    return $Execution
}

<#
.SYNOPSIS
    Goes back to the previous step in execution.
#>
function Undo-TreeStep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [pscustomobject]$Execution
    )

    if ($Execution.Steps.Count -le 1) {
        # Already at start
        return $Execution
    }

    # Remove current step
    [void]$Execution.Steps.RemoveAt($Execution.Steps.Count - 1)

    # Get previous step's node
    $prevStep = $Execution.Steps[$Execution.Steps.Count - 1]
    $prevNode = $Execution.Tree.Nodes | Where-Object { $_.Id -eq $prevStep.NodeId }

    $Execution.CurrentNode = $prevNode
    $Execution.IsComplete = $false
    $Execution.Outcome = $null
    $Execution.EndTime = $null
    $Execution.Duration = $null

    # Clear the answer/input from previous step so it can be re-answered
    $prevStep.Answer = $null
    $prevStep.InputValue = $null
    $prevStep.Duration = $null

    return $Execution
}

<#
.SYNOPSIS
    Exports a decision tree to JSON or Markdown.
#>
function Export-DecisionTree {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [pscustomobject]$Tree,

        [ValidateSet('JSON', 'Markdown')]
        [string]$Format = 'JSON'
    )

    if ($Format -eq 'JSON') {
        $export = @{
            name = $Tree.Name
            description = $Tree.Description
            category = $Tree.Category
            version = $Tree.Version
            author = $Tree.Author
            createdDate = $Tree.CreatedDate
            startNode = $Tree.StartNodeId
            nodes = @()
        }

        foreach ($node in $Tree.Nodes) {
            $nodeExport = @{
                id = $node.Id
                type = $node.Type
                title = $node.Title
            }

            if ($node.Content) { $nodeExport.content = $node.Content }
            if ($node.VariableName) { $nodeExport.variableName = $node.VariableName }
            if ($node.ValidationPattern) { $nodeExport.validationPattern = $node.ValidationPattern }
            if ($node.Next) { $nodeExport.next = $node.Next }
            if ($node.Outcome) { $nodeExport.outcome = $node.Outcome }

            if ($node.Branches.Count -gt 0) {
                $nodeExport.branches = @()
                foreach ($branch in $node.Branches) {
                    $branchExport = @{ next = $branch.Next }
                    if ($branch.Answer) { $branchExport.answer = $branch.Answer }
                    if ($branch.Condition) { $branchExport.condition = $branch.Condition }
                    if ($branch.Label) { $branchExport.label = $branch.Label }
                    $nodeExport.branches += $branchExport
                }
            }

            $export.nodes += $nodeExport
        }

        return ($export | ConvertTo-Json -Depth 10)
    }
    elseif ($Format -eq 'Markdown') {
        $sb = [System.Text.StringBuilder]::new()
        [void]$sb.AppendLine("# $($Tree.Name)")
        [void]$sb.AppendLine()
        if ($Tree.Description) {
            [void]$sb.AppendLine($Tree.Description)
            [void]$sb.AppendLine()
        }
        [void]$sb.AppendLine("**Category:** $($Tree.Category)")
        [void]$sb.AppendLine("**Version:** $($Tree.Version)")
        [void]$sb.AppendLine()
        [void]$sb.AppendLine("## Flowchart")
        [void]$sb.AppendLine()
        [void]$sb.AppendLine('```')

        foreach ($node in $Tree.Nodes) {
            $nodeLabel = "[$($node.Id): $($node.Title)]"
            if ($node.Next) {
                [void]$sb.AppendLine("$nodeLabel --> [$($node.Next)]")
            }
            foreach ($branch in $node.Branches) {
                $branchLabel = if ($branch.Answer) { $branch.Answer } else { $branch.Condition }
                [void]$sb.AppendLine("$nodeLabel --$branchLabel--> [$($branch.Next)]")
            }
        }

        [void]$sb.AppendLine('```')
        [void]$sb.AppendLine()
        [void]$sb.AppendLine("## Nodes")
        [void]$sb.AppendLine()

        foreach ($node in $Tree.Nodes) {
            [void]$sb.AppendLine("### $($node.Id) ($($node.Type))")
            [void]$sb.AppendLine()
            [void]$sb.AppendLine("**$($node.Title)**")
            if ($node.Content) {
                [void]$sb.AppendLine()
                [void]$sb.AppendLine($node.Content)
            }
            if ($node.Branches.Count -gt 0) {
                [void]$sb.AppendLine()
                [void]$sb.AppendLine("Options:")
                foreach ($branch in $node.Branches) {
                    $label = if ($branch.Answer) { $branch.Answer } else { $branch.Condition }
                    [void]$sb.AppendLine("- $label -> $($branch.Next)")
                }
            }
            [void]$sb.AppendLine()
        }

        return $sb.ToString()
    }
}

<#
.SYNOPSIS
    Gets a built-in troubleshooting tree.
#>
function Get-BuiltInTree {
    [CmdletBinding()]
    param(
        [Parameter(ParameterSetName='Name')]
        [string]$Name,

        [Parameter(ParameterSetName='List')]
        [switch]$List
    )

    # Initialize built-in trees if not loaded
    if ($script:BuiltInTrees.Count -eq 0) {
        Initialize-BuiltInTrees
    }

    if ($List) {
        return @($script:BuiltInTrees.Values | ForEach-Object {
            [pscustomobject]@{
                Name = $_.Name
                Description = $_.Description
                Category = $_.Category
            }
        })
    }

    if ($Name -and $script:BuiltInTrees.ContainsKey($Name)) {
        return $script:BuiltInTrees[$Name]
    }

    return $null
}

<#
.SYNOPSIS
    Initializes the built-in troubleshooting trees.
#>
function Initialize-BuiltInTrees {
    [CmdletBinding()]
    param()

    # Port Not Working Tree
    $portTree = @'
{
    "name": "Port-NotWorking",
    "description": "Troubleshoot a switch port that is not working",
    "category": "Layer1-Layer2",
    "version": "1.0",
    "isBuiltIn": true,
    "nodes": [
        {
            "id": "start",
            "type": "decision",
            "title": "Is the link light on?",
            "content": "Check the LED indicator on the switch port. Green typically means link is up.",
            "branches": [
                { "answer": "Yes", "next": "check_vlan" },
                { "answer": "No", "next": "check_cable" }
            ]
        },
        {
            "id": "check_cable",
            "type": "action",
            "title": "Check cable connection",
            "content": "Inspect the cable at both ends:\n- Is it properly seated in the switch port?\n- Is it properly seated in the device/patch panel?\n- Are there any visible signs of damage?",
            "next": "cable_seated"
        },
        {
            "id": "cable_seated",
            "type": "decision",
            "title": "Is the cable properly seated at both ends?",
            "branches": [
                { "answer": "Yes, cable looks good", "next": "try_different_port" },
                { "answer": "No, cable was loose", "next": "reseat_result" },
                { "answer": "Cable appears damaged", "next": "replace_cable" }
            ]
        },
        {
            "id": "reseat_result",
            "type": "decision",
            "title": "After reseating the cable, does the link come up?",
            "branches": [
                { "answer": "Yes", "next": "resolved_cable" },
                { "answer": "No", "next": "try_different_port" }
            ]
        },
        {
            "id": "replace_cable",
            "type": "action",
            "title": "Replace the cable",
            "content": "Get a known-good cable and replace the suspected bad cable.",
            "next": "cable_replaced"
        },
        {
            "id": "cable_replaced",
            "type": "decision",
            "title": "Does the link come up with the new cable?",
            "branches": [
                { "answer": "Yes", "next": "resolved_bad_cable" },
                { "answer": "No", "next": "try_different_port" }
            ]
        },
        {
            "id": "try_different_port",
            "type": "action",
            "title": "Test with a different switch port",
            "content": "Move the cable to a known-working port on the switch to rule out a bad switch port.",
            "next": "different_port_result"
        },
        {
            "id": "different_port_result",
            "type": "decision",
            "title": "Does the device link up on a different port?",
            "branches": [
                { "answer": "Yes", "next": "resolved_bad_port" },
                { "answer": "No", "next": "check_device_nic" }
            ]
        },
        {
            "id": "check_device_nic",
            "type": "action",
            "title": "Check the device NIC",
            "content": "The issue may be with the end device:\n- Check if NIC is enabled\n- Check device manager for errors\n- Try a different NIC or USB adapter if available",
            "next": "device_nic_result"
        },
        {
            "id": "device_nic_result",
            "type": "decision",
            "title": "Is the device NIC working correctly?",
            "branches": [
                { "answer": "Yes, NIC seems fine", "next": "escalate" },
                { "answer": "No, NIC has issues", "next": "resolved_bad_nic" }
            ]
        },
        {
            "id": "check_vlan",
            "type": "decision",
            "title": "Is the port configured for the correct VLAN?",
            "content": "Check the switchport configuration to verify VLAN assignment matches what the device needs.",
            "branches": [
                { "answer": "Yes, VLAN is correct", "next": "check_duplex" },
                { "answer": "No, wrong VLAN", "next": "resolved_vlan" },
                { "answer": "Not sure", "next": "check_port_config" }
            ]
        },
        {
            "id": "check_port_config",
            "type": "action",
            "title": "Verify port configuration",
            "content": "Run 'show running-config interface' or equivalent to check:\n- Access/trunk mode\n- VLAN assignment\n- Speed/duplex settings\n- Port security settings",
            "next": "port_config_result"
        },
        {
            "id": "port_config_result",
            "type": "decision",
            "title": "Does the port configuration look correct?",
            "branches": [
                { "answer": "Yes", "next": "check_duplex" },
                { "answer": "No, found misconfiguration", "next": "resolved_config" }
            ]
        },
        {
            "id": "check_duplex",
            "type": "decision",
            "title": "Are speed/duplex settings correct (no mismatch)?",
            "content": "A duplex mismatch can cause intermittent connectivity. Check for:\n- One side auto, other side fixed\n- Mismatched speed settings\n- Late collisions in interface counters",
            "branches": [
                { "answer": "Yes, settings match", "next": "check_stp" },
                { "answer": "No, mismatch detected", "next": "resolved_duplex" }
            ]
        },
        {
            "id": "check_stp",
            "type": "decision",
            "title": "Is the port in STP forwarding state?",
            "content": "Check 'show spanning-tree interface'. Port should be in 'forwarding' state, not 'blocking' or 'listening'.",
            "branches": [
                { "answer": "Yes, forwarding", "next": "check_port_security" },
                { "answer": "No, blocked/other", "next": "resolved_stp" }
            ]
        },
        {
            "id": "check_port_security",
            "type": "decision",
            "title": "Is port security causing issues?",
            "content": "Check 'show port-security interface'. Look for violation actions or MAC address limits.",
            "branches": [
                { "answer": "No issues found", "next": "escalate" },
                { "answer": "Security violation detected", "next": "resolved_port_security" }
            ]
        },
        {
            "id": "resolved_cable",
            "type": "result",
            "title": "Issue resolved: Cable was loose",
            "outcome": "CableLoose"
        },
        {
            "id": "resolved_bad_cable",
            "type": "result",
            "title": "Issue resolved: Bad cable replaced",
            "outcome": "CableBad"
        },
        {
            "id": "resolved_bad_port",
            "type": "result",
            "title": "Issue resolved: Bad switch port identified",
            "content": "The original switch port appears to be faulty. Consider:\n- Disabling the port\n- Opening a hardware case\n- Updating port documentation",
            "outcome": "SwitchPortBad"
        },
        {
            "id": "resolved_bad_nic",
            "type": "result",
            "title": "Issue resolved: Device NIC is faulty",
            "outcome": "DeviceNICBad"
        },
        {
            "id": "resolved_vlan",
            "type": "result",
            "title": "Issue resolved: VLAN misconfiguration",
            "content": "Configure the correct VLAN on the switch port.",
            "outcome": "VLANMisconfigured"
        },
        {
            "id": "resolved_config",
            "type": "result",
            "title": "Issue resolved: Port misconfiguration",
            "outcome": "PortMisconfigured"
        },
        {
            "id": "resolved_duplex",
            "type": "result",
            "title": "Issue resolved: Speed/duplex mismatch",
            "content": "Correct the speed/duplex settings on both ends. Best practice: both sides auto-negotiate or both sides fixed.",
            "outcome": "DuplexMismatch"
        },
        {
            "id": "resolved_stp",
            "type": "result",
            "title": "Issue resolved: Spanning Tree blocking",
            "content": "Investigate the STP topology to understand why this port is blocked.",
            "outcome": "STPBlocking"
        },
        {
            "id": "resolved_port_security",
            "type": "result",
            "title": "Issue resolved: Port security violation",
            "content": "Clear the violation and verify MAC address is allowed.",
            "outcome": "PortSecurityViolation"
        },
        {
            "id": "escalate",
            "type": "result",
            "title": "Escalation required",
            "content": "Basic troubleshooting did not identify the issue. Consider:\n- Packet capture analysis\n- Check for hardware issues\n- Review recent changes\n- Escalate to senior engineer",
            "outcome": "Escalated"
        }
    ]
}
'@
    $script:BuiltInTrees['Port-NotWorking'] = Import-DecisionTree -Json $portTree

    # VLAN Issues Tree
    $vlanTree = @'
{
    "name": "VLAN-Issues",
    "description": "Troubleshoot VLAN-related connectivity problems",
    "category": "Layer2",
    "version": "1.0",
    "isBuiltIn": true,
    "nodes": [
        {
            "id": "start",
            "type": "decision",
            "title": "What is the symptom?",
            "branches": [
                { "answer": "Device cannot reach gateway", "next": "check_access_vlan" },
                { "answer": "Device cannot reach devices in same VLAN", "next": "check_same_vlan" },
                { "answer": "Device cannot reach other VLANs", "next": "check_routing" },
                { "answer": "VLAN not appearing on switch", "next": "check_vlan_exists" }
            ]
        },
        {
            "id": "check_access_vlan",
            "type": "action",
            "title": "Verify access VLAN assignment",
            "content": "Check 'show interfaces switchport' or 'show vlan'. Confirm the port is in the expected VLAN.",
            "next": "access_vlan_correct"
        },
        {
            "id": "access_vlan_correct",
            "type": "decision",
            "title": "Is the access VLAN correct?",
            "branches": [
                { "answer": "Yes", "next": "check_svi" },
                { "answer": "No", "next": "resolved_wrong_vlan" }
            ]
        },
        {
            "id": "check_svi",
            "type": "decision",
            "title": "Is the SVI (VLAN interface) up and configured?",
            "content": "Check 'show ip interface brief' for the VLAN interface status.",
            "branches": [
                { "answer": "Yes, SVI is up", "next": "check_gateway_ip" },
                { "answer": "No, SVI is down/missing", "next": "resolved_svi_down" }
            ]
        },
        {
            "id": "check_gateway_ip",
            "type": "decision",
            "title": "Is the device's default gateway configured correctly?",
            "branches": [
                { "answer": "Yes", "next": "check_ip_conflict" },
                { "answer": "No, wrong gateway", "next": "resolved_wrong_gateway" }
            ]
        },
        {
            "id": "check_ip_conflict",
            "type": "decision",
            "title": "Is there an IP address conflict?",
            "content": "Check ARP tables for duplicate MAC addresses for the same IP.",
            "branches": [
                { "answer": "No conflict", "next": "escalate" },
                { "answer": "Yes, conflict found", "next": "resolved_ip_conflict" }
            ]
        },
        {
            "id": "check_same_vlan",
            "type": "decision",
            "title": "Are both devices on the same switch?",
            "branches": [
                { "answer": "Yes", "next": "check_both_ports" },
                { "answer": "No, different switches", "next": "check_trunk" }
            ]
        },
        {
            "id": "check_both_ports",
            "type": "decision",
            "title": "Are both ports in the same VLAN?",
            "branches": [
                { "answer": "Yes", "next": "check_private_vlan" },
                { "answer": "No", "next": "resolved_vlan_mismatch" }
            ]
        },
        {
            "id": "check_private_vlan",
            "type": "decision",
            "title": "Is private VLAN or port isolation enabled?",
            "branches": [
                { "answer": "No", "next": "escalate" },
                { "answer": "Yes", "next": "resolved_private_vlan" }
            ]
        },
        {
            "id": "check_trunk",
            "type": "decision",
            "title": "Is the VLAN allowed on trunk links between switches?",
            "content": "Check 'show interfaces trunk' to verify VLAN is in the allowed list.",
            "branches": [
                { "answer": "Yes, VLAN is allowed", "next": "check_trunk_native" },
                { "answer": "No, VLAN is pruned/not allowed", "next": "resolved_trunk_pruned" }
            ]
        },
        {
            "id": "check_trunk_native",
            "type": "decision",
            "title": "Is there a native VLAN mismatch on the trunk?",
            "branches": [
                { "answer": "No mismatch", "next": "check_vlan_exists" },
                { "answer": "Yes, mismatch detected", "next": "resolved_native_mismatch" }
            ]
        },
        {
            "id": "check_vlan_exists",
            "type": "decision",
            "title": "Does the VLAN exist in the VLAN database on all switches?",
            "content": "Check 'show vlan' on each switch in the path.",
            "branches": [
                { "answer": "Yes, exists everywhere", "next": "escalate" },
                { "answer": "No, missing on some switches", "next": "resolved_vlan_missing" }
            ]
        },
        {
            "id": "check_routing",
            "type": "decision",
            "title": "Is inter-VLAN routing enabled?",
            "branches": [
                { "answer": "Yes", "next": "check_acl" },
                { "answer": "No", "next": "resolved_no_routing" }
            ]
        },
        {
            "id": "check_acl",
            "type": "decision",
            "title": "Are there any ACLs blocking traffic?",
            "content": "Check for access-lists applied to VLAN interfaces.",
            "branches": [
                { "answer": "No ACLs blocking", "next": "escalate" },
                { "answer": "ACL is blocking", "next": "resolved_acl" }
            ]
        },
        {
            "id": "resolved_wrong_vlan",
            "type": "result",
            "title": "Issue resolved: Port in wrong VLAN",
            "outcome": "WrongVLAN"
        },
        {
            "id": "resolved_svi_down",
            "type": "result",
            "title": "Issue resolved: SVI down or missing",
            "outcome": "SVIDown"
        },
        {
            "id": "resolved_wrong_gateway",
            "type": "result",
            "title": "Issue resolved: Wrong default gateway",
            "outcome": "WrongGateway"
        },
        {
            "id": "resolved_ip_conflict",
            "type": "result",
            "title": "Issue resolved: IP address conflict",
            "outcome": "IPConflict"
        },
        {
            "id": "resolved_vlan_mismatch",
            "type": "result",
            "title": "Issue resolved: VLAN mismatch between ports",
            "outcome": "VLANMismatch"
        },
        {
            "id": "resolved_private_vlan",
            "type": "result",
            "title": "Issue resolved: Private VLAN/port isolation",
            "outcome": "PrivateVLAN"
        },
        {
            "id": "resolved_trunk_pruned",
            "type": "result",
            "title": "Issue resolved: VLAN pruned/not allowed on trunk",
            "outcome": "TrunkPruned"
        },
        {
            "id": "resolved_native_mismatch",
            "type": "result",
            "title": "Issue resolved: Native VLAN mismatch",
            "outcome": "NativeVLANMismatch"
        },
        {
            "id": "resolved_vlan_missing",
            "type": "result",
            "title": "Issue resolved: VLAN missing from switch",
            "outcome": "VLANMissing"
        },
        {
            "id": "resolved_no_routing",
            "type": "result",
            "title": "Issue resolved: Inter-VLAN routing not enabled",
            "outcome": "NoRouting"
        },
        {
            "id": "resolved_acl",
            "type": "result",
            "title": "Issue resolved: ACL blocking traffic",
            "outcome": "ACLBlocking"
        },
        {
            "id": "escalate",
            "type": "result",
            "title": "Escalation required",
            "content": "Basic VLAN troubleshooting did not identify the issue.",
            "outcome": "Escalated"
        }
    ]
}
'@
    $script:BuiltInTrees['VLAN-Issues'] = Import-DecisionTree -Json $vlanTree

    # Simple Test Tree (for testing)
    $simpleTree = @'
{
    "name": "Simple-Test",
    "description": "A simple tree for testing",
    "category": "Test",
    "version": "1.0",
    "isBuiltIn": true,
    "nodes": [
        {
            "id": "q1",
            "type": "decision",
            "title": "Is it working?",
            "branches": [
                { "answer": "Yes", "next": "done_yes" },
                { "answer": "No", "next": "done_no" }
            ]
        },
        {
            "id": "done_yes",
            "type": "result",
            "title": "Great, no action needed",
            "outcome": "Working"
        },
        {
            "id": "done_no",
            "type": "result",
            "title": "Needs investigation",
            "outcome": "NotWorking"
        }
    ]
}
'@
    $script:BuiltInTrees['Simple-Test'] = Import-DecisionTree -Json $simpleTree

    # STP Problems Tree
    $stpTree = @'
{
    "name": "STP-Problems",
    "description": "Troubleshoot Spanning Tree Protocol issues",
    "category": "Layer2",
    "version": "1.0",
    "isBuiltIn": true,
    "nodes": [
        {
            "id": "start",
            "type": "decision",
            "title": "What is the STP symptom?",
            "branches": [
                { "answer": "Port is blocked unexpectedly", "next": "check_blocked" },
                { "answer": "Port keeps flapping", "next": "check_flapping" },
                { "answer": "Suspected loop", "next": "check_loop" },
                { "answer": "Root bridge wrong device", "next": "check_root" }
            ]
        },
        {
            "id": "check_blocked",
            "type": "action",
            "title": "Check STP port state and role",
            "content": "Run 'show spanning-tree interface' to see port state and role.",
            "next": "blocked_role"
        },
        {
            "id": "blocked_role",
            "type": "decision",
            "title": "What is the port role?",
            "branches": [
                { "answer": "Alternate (normal)", "next": "resolved_normal_blocking" },
                { "answer": "Root port blocked", "next": "check_bpdu_filter" },
                { "answer": "Designated but blocking", "next": "check_tcn" }
            ]
        },
        {
            "id": "check_bpdu_filter",
            "type": "decision",
            "title": "Is BPDU filter enabled on upstream port?",
            "branches": [
                { "answer": "Yes", "next": "resolved_bpdu_filter" },
                { "answer": "No", "next": "check_priority" }
            ]
        },
        {
            "id": "check_priority",
            "type": "decision",
            "title": "Are bridge priorities configured correctly?",
            "content": "Lower priority = more likely to be root. Check if a downstream switch has lower priority.",
            "branches": [
                { "answer": "Yes, priorities correct", "next": "escalate" },
                { "answer": "No, priorities wrong", "next": "resolved_priority" }
            ]
        },
        {
            "id": "check_tcn",
            "type": "decision",
            "title": "Are there topology change notifications?",
            "content": "Check 'show spanning-tree detail' for topology change counters.",
            "branches": [
                { "answer": "Many TCNs", "next": "check_flapping" },
                { "answer": "Few/no TCNs", "next": "escalate" }
            ]
        },
        {
            "id": "check_flapping",
            "type": "action",
            "title": "Check for physical issues",
            "content": "Port flapping can be caused by:\n- Bad cable\n- Failing port/NIC\n- Duplex mismatch\n- PoE issues",
            "next": "flapping_physical"
        },
        {
            "id": "flapping_physical",
            "type": "decision",
            "title": "Are there physical layer issues?",
            "branches": [
                { "answer": "Yes", "next": "resolved_physical" },
                { "answer": "No", "next": "check_loop" }
            ]
        },
        {
            "id": "check_loop",
            "type": "action",
            "title": "Look for loop indicators",
            "content": "Check for:\n- High CPU on switches\n- MAC address table thrashing\n- Broadcast storms\n- Rapid interface counter increases",
            "next": "loop_symptoms"
        },
        {
            "id": "loop_symptoms",
            "type": "decision",
            "title": "Are loop symptoms present?",
            "branches": [
                { "answer": "Yes, loop detected", "next": "isolate_loop" },
                { "answer": "No loop symptoms", "next": "escalate" }
            ]
        },
        {
            "id": "isolate_loop",
            "type": "action",
            "title": "Isolate the loop",
            "content": "1. Check for unauthorized connections\n2. Look for hub/unmanaged switches\n3. Check for patch panel cross-connects\n4. Disable suspected ports one at a time",
            "next": "loop_found"
        },
        {
            "id": "loop_found",
            "type": "decision",
            "title": "Was the loop source identified?",
            "branches": [
                { "answer": "Yes", "next": "resolved_loop" },
                { "answer": "No", "next": "escalate" }
            ]
        },
        {
            "id": "check_root",
            "type": "action",
            "title": "Identify current root bridge",
            "content": "Run 'show spanning-tree root' to see which switch is the root for each VLAN.",
            "next": "root_check"
        },
        {
            "id": "root_check",
            "type": "decision",
            "title": "Is the root bridge the intended switch?",
            "branches": [
                { "answer": "No, wrong root", "next": "resolved_wrong_root" },
                { "answer": "Yes, correct root", "next": "escalate" }
            ]
        },
        {
            "id": "resolved_normal_blocking",
            "type": "result",
            "title": "Normal STP blocking behavior",
            "content": "Alternate ports are expected to be blocking. This is STP working correctly to prevent loops.",
            "outcome": "NormalBlocking"
        },
        {
            "id": "resolved_bpdu_filter",
            "type": "result",
            "title": "Issue resolved: BPDU filter misconfiguration",
            "content": "BPDU filter should only be used on edge ports. Remove from trunk/non-edge ports.",
            "outcome": "BPDUFilter"
        },
        {
            "id": "resolved_priority",
            "type": "result",
            "title": "Issue resolved: STP priority misconfiguration",
            "content": "Adjust bridge priorities so the intended root has the lowest priority value.",
            "outcome": "PriorityWrong"
        },
        {
            "id": "resolved_physical",
            "type": "result",
            "title": "Issue resolved: Physical layer problem",
            "outcome": "PhysicalIssue"
        },
        {
            "id": "resolved_loop",
            "type": "result",
            "title": "Issue resolved: Loop identified and removed",
            "outcome": "LoopRemoved"
        },
        {
            "id": "resolved_wrong_root",
            "type": "result",
            "title": "Issue resolved: Wrong root bridge",
            "content": "Configure the correct switch with lowest priority (e.g., 4096) to become root.",
            "outcome": "WrongRoot"
        },
        {
            "id": "escalate",
            "type": "result",
            "title": "Escalation required",
            "content": "STP troubleshooting did not identify the issue.",
            "outcome": "Escalated"
        }
    ]
}
'@
    $script:BuiltInTrees['STP-Problems'] = Import-DecisionTree -Json $stpTree
}

# Export functions
Export-ModuleMember -Function @(
    'New-DecisionTree',
    'Import-DecisionTree',
    'Test-DecisionTree',
    'Add-TreeNode',
    'Remove-TreeNode',
    'Start-TreeExecution',
    'Submit-TreeAnswer',
    'Submit-TreeInput',
    'Continue-TreeExecution',
    'Undo-TreeStep',
    'Export-DecisionTree',
    'Get-BuiltInTree',
    'Initialize-BuiltInTrees'
)
