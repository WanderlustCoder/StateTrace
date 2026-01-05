# Plan AB - Troubleshooting Decision Trees

<!-- LANDMARK: ST-E-001 telemetry gates link -->
Telemetry gates: [docs/telemetry/Automation_Gates.md](../telemetry/Automation_Gates.md).

## Objective
Provide interactive troubleshooting decision trees that guide network technicians through systematic diagnosis workflows. Enable consistent troubleshooting approaches, reduce mean time to resolution (MTTR), and capture institutional knowledge in structured, executable formats.

## Problem Statement
Network teams struggle with:
- Inconsistent troubleshooting approaches between team members
- Junior technicians lacking guidance on complex issues
- Institutional knowledge locked in senior engineers' heads
- Repeating the same diagnostic steps for common problems
- Documenting and sharing effective troubleshooting procedures
- Training new team members on troubleshooting methodology

## Current status (2026-01)
- **In Progress (4/6 core tasks done)**
- DecisionTreeModule.psm1 implemented with full tree engine
- Built-in trees: Port-NotWorking, VLAN-Issues, STP-Problems, Simple-Test
- 42 Pester tests passing
- DecisionTreeView.xaml and DecisionTreeViewModule.psm1 integrated into MainWindow
- Pending: Tree editor UI, execution persistence, outcome analytics

## Proposed Features

### AB.1 Decision Tree Engine
- **Tree Structure**: Define troubleshooting flows with:
  - Decision nodes (questions with multiple answers)
  - Action nodes (steps to perform)
  - Check nodes (verify condition/output)
  - Result nodes (diagnosis/resolution)
  - Branch nodes (conditional paths)
- **Variable System**: Track state through workflow:
  - User inputs
  - Captured data
  - Calculated values
  - Previous answers
- **Expression Evaluation**: Conditional branching based on:
  - Answer comparisons
  - Pattern matching
  - Numeric thresholds
  - Boolean logic

### AB.2 Tree Library
- **Built-in Trees** for common scenarios:
  - Port not working (no link, no traffic)
  - VLAN issues (wrong VLAN, trunk problems)
  - Spanning tree problems (blocked ports, loops)
  - Speed/duplex mismatch
  - Power over Ethernet issues
  - Routing problems (missing routes, wrong next-hop)
  - DHCP issues (no address, wrong scope)
  - DNS resolution failures
  - Connectivity between hosts
  - Performance degradation
- **Custom Trees**: User-defined troubleshooting workflows
- **Tree Templates**: Starting points for new trees

### AB.3 Interactive Execution
- **Step-by-Step UI**: Guide user through:
  - Current question/action
  - Available answers/options
  - Progress indicator
  - Breadcrumb navigation
- **Data Capture**: Record during execution:
  - Answers selected
  - Values entered
  - Commands to run
  - Expected vs actual outputs
- **Navigation**: Allow:
  - Go back to previous step
  - Restart from beginning
  - Jump to specific node
  - Save progress and resume

### AB.4 Knowledge Capture
- **Outcome Recording**: When resolution found:
  - Root cause identified
  - Resolution steps taken
  - Time to resolution
  - Difficulty rating
- **Pattern Analysis**: Over time identify:
  - Most common issues
  - Frequently used paths
  - Success rates by branch
  - Average resolution times
- **Improvement Suggestions**: Flag when:
  - Certain paths rarely used
  - High backtrack rates
  - Long resolution times
  - User feedback indicates confusion

### AB.5 Integration Points
- **Device Data**: Pre-fill based on:
  - Selected device's configuration
  - Interface states
  - VLAN assignments
  - Recent changes
- **Runbook Links**: Connect to:
  - Detailed procedure documents
  - Command references
  - Knowledge base articles
- **Ticket Integration**: Export to:
  - Incident notes
  - Resolution documentation
  - Knowledge articles

### AB.6 Tree Editor
- **Visual Designer**: Drag-and-drop tree building:
  - Add/remove nodes
  - Connect nodes with branches
  - Set conditions and actions
  - Preview execution path
- **Validation**: Check tree integrity:
  - No orphan nodes
  - All branches reachable
  - No infinite loops
  - Required fields populated
- **Import/Export**: Share trees via:
  - JSON format
  - Markdown documentation
  - Print-ready flowcharts

## Active work
| ID | Title | Owner | Status | Notes |
|----|-------|-------|--------|-------|
| ST-AB-001 | Decision tree schema | Data | Done | Node types: decision, action, input, branch, check, result |
| ST-AB-002 | Tree execution engine | Tools | Done | DecisionTreeModule.psm1 with 42 tests |
| ST-AB-003 | Built-in tree library | Tools | Done | Port-NotWorking, VLAN-Issues, STP-Problems |
| ST-AB-004 | Interactive execution UI | UI | Done | DecisionTreeView.xaml + ViewModule, "Troubleshoot" tab |
| ST-AB-005 | Tree editor | UI | Pending | Visual tree designer |
| ST-AB-006 | Outcome analytics | Tools | Pending | Pattern and success tracking |

## Data Model (Proposed)

### DecisionTree Table
```
TreeID (PK), Name, Description, Category, Version,
Author, CreatedDate, ModifiedDate, IsBuiltIn, IsEnabled
```

### TreeNode Table
```
NodeID (PK), TreeID (FK), NodeType, Title, Content,
VariableName, ValidationPattern, NextNodeDefault, Position, Notes
```

### TreeBranch Table
```
BranchID (PK), FromNodeID (FK), ToNodeID (FK),
Condition, Label, DisplayOrder
```

### TreeExecution Table
```
ExecutionID (PK), TreeID (FK), StartTime, EndTime,
DeviceID, UserID, Outcome, RootCause, Resolution, Notes
```

### ExecutionStep Table
```
StepID (PK), ExecutionID (FK), NodeID (FK), Timestamp,
Answer, InputValue, Duration, Notes
```

## Testing Requirements

### Unit Tests (`Modules/Tests/DecisionTreeModule.Tests.ps1`)

```powershell
Describe 'Decision Tree Engine' -Tag 'DecisionTree' {

    Describe 'Tree Structure' {
        It 'loads tree from JSON definition' {
            $json = @'
{
    "name": "Port Not Working",
    "nodes": [
        { "id": "start", "type": "decision", "title": "Is the link light on?", "branches": [
            { "answer": "Yes", "next": "check_vlan" },
            { "answer": "No", "next": "check_cable" }
        ]},
        { "id": "check_cable", "type": "action", "title": "Check cable connection", "next": "cable_ok" },
        { "id": "cable_ok", "type": "decision", "title": "Is cable properly seated?", "branches": [
            { "answer": "Yes", "next": "try_different_port" },
            { "answer": "No", "next": "reseat_cable" }
        ]},
        { "id": "reseat_cable", "type": "result", "title": "Reseat cable - issue resolved" }
    ]
}
'@
            $tree = Import-DecisionTree -Json $json

            $tree.Name | Should -Be 'Port Not Working'
            $tree.Nodes.Count | Should -Be 4
            $tree.StartNode.Type | Should -Be 'decision'
        }

        It 'validates tree has no orphan nodes' {
            $tree = New-DecisionTree -Name 'Test'
            Add-TreeNode -Tree $tree -Id 'orphan' -Type 'action' -Title 'Orphan node'

            $validation = Test-DecisionTree -Tree $tree

            $validation.IsValid | Should -BeFalse
            $validation.Errors | Should -Contain 'Orphan node: orphan'
        }

        It 'detects circular references' {
            $tree = New-DecisionTree -Name 'Circular'
            Add-TreeNode -Tree $tree -Id 'a' -Type 'decision' -Title 'Node A' -Branches @(
                @{ Answer = 'Go to B'; Next = 'b' }
            )
            Add-TreeNode -Tree $tree -Id 'b' -Type 'decision' -Title 'Node B' -Branches @(
                @{ Answer = 'Go to A'; Next = 'a' }
            )

            $validation = Test-DecisionTree -Tree $tree

            $validation.Warnings | Should -Match 'Potential loop detected'
        }

        It 'ensures all branches lead to valid nodes' {
            $tree = New-DecisionTree -Name 'Test'
            Add-TreeNode -Tree $tree -Id 'start' -Type 'decision' -Branches @(
                @{ Answer = 'Go nowhere'; Next = 'nonexistent' }
            )

            $validation = Test-DecisionTree -Tree $tree

            $validation.Errors | Should -Match 'Invalid target node: nonexistent'
        }
    }

    Describe 'Tree Execution' {
        BeforeAll {
            $script:testTree = @'
{
    "name": "Simple Test",
    "nodes": [
        { "id": "q1", "type": "decision", "title": "Is it working?", "branches": [
            { "answer": "Yes", "next": "done_yes" },
            { "answer": "No", "next": "done_no" }
        ]},
        { "id": "done_yes", "type": "result", "title": "Great, no action needed", "outcome": "Working" },
        { "id": "done_no", "type": "result", "title": "Needs investigation", "outcome": "NotWorking" }
    ]
}
'@ | ConvertFrom-Json
        }

        It 'starts execution at first node' {
            $execution = Start-TreeExecution -Tree $testTree

            $execution.CurrentNode.Id | Should -Be 'q1'
            $execution.CurrentNode.Type | Should -Be 'decision'
        }

        It 'advances to next node on answer' {
            $execution = Start-TreeExecution -Tree $testTree
            $execution = Submit-TreeAnswer -Execution $execution -Answer 'No'

            $execution.CurrentNode.Id | Should -Be 'done_no'
            $execution.IsComplete | Should -BeTrue
            $execution.Outcome | Should -Be 'NotWorking'
        }

        It 'records step history' {
            $execution = Start-TreeExecution -Tree $testTree
            $execution = Submit-TreeAnswer -Execution $execution -Answer 'Yes'

            $execution.Steps.Count | Should -Be 2
            $execution.Steps[0].NodeId | Should -Be 'q1'
            $execution.Steps[0].Answer | Should -Be 'Yes'
        }

        It 'allows going back to previous step' {
            $execution = Start-TreeExecution -Tree $testTree
            $execution = Submit-TreeAnswer -Execution $execution -Answer 'Yes'
            $execution = Undo-TreeStep -Execution $execution

            $execution.CurrentNode.Id | Should -Be 'q1'
            $execution.IsComplete | Should -BeFalse
        }

        It 'calculates execution duration' {
            $execution = Start-TreeExecution -Tree $testTree
            Start-Sleep -Milliseconds 100
            $execution = Submit-TreeAnswer -Execution $execution -Answer 'Yes'

            $execution.Duration.TotalMilliseconds | Should -BeGreaterThan 50
        }
    }

    Describe 'Conditional Branching' {
        It 'evaluates numeric conditions' {
            $tree = New-DecisionTree -Name 'Numeric Test'
            Add-TreeNode -Tree $tree -Id 'input' -Type 'input' -Title 'Enter packet loss %' `
                -VariableName 'packetLoss' -Next 'check'
            Add-TreeNode -Tree $tree -Id 'check' -Type 'branch' -Branches @(
                @{ Condition = '$packetLoss -lt 1'; Next = 'ok' },
                @{ Condition = '$packetLoss -lt 5'; Next = 'warning' },
                @{ Condition = '$true'; Next = 'critical' }
            )

            $execution = Start-TreeExecution -Tree $tree
            $execution = Submit-TreeInput -Execution $execution -Value 3

            $execution.CurrentNode.Id | Should -Be 'warning'
        }

        It 'evaluates pattern matching conditions' {
            $tree = New-DecisionTree -Name 'Pattern Test'
            Add-TreeNode -Tree $tree -Id 'input' -Type 'input' -Title 'Enter error message' `
                -VariableName 'errorMsg' -Next 'check'
            Add-TreeNode -Tree $tree -Id 'check' -Type 'branch' -Branches @(
                @{ Condition = '$errorMsg -match "timeout"'; Next = 'timeout_issue' },
                @{ Condition = '$errorMsg -match "refused"'; Next = 'refused_issue' },
                @{ Condition = '$true'; Next = 'unknown' }
            )

            $execution = Start-TreeExecution -Tree $tree
            $execution = Submit-TreeInput -Execution $execution -Value 'Connection refused by host'

            $execution.CurrentNode.Id | Should -Be 'refused_issue'
        }
    }

    Describe 'Built-in Trees' {
        It 'loads port troubleshooting tree' {
            $tree = Get-BuiltInTree -Name 'Port-NotWorking'

            $tree | Should -Not -BeNullOrEmpty
            $tree.Nodes.Count | Should -BeGreaterThan 5
        }

        It 'loads VLAN troubleshooting tree' {
            $tree = Get-BuiltInTree -Name 'VLAN-Issues'

            $tree | Should -Not -BeNullOrEmpty
            $tree.Category | Should -Be 'Layer2'
        }

        It 'lists all available built-in trees' {
            $trees = Get-BuiltInTree -List

            $trees.Count | Should -BeGreaterThan 5
            $trees.Name | Should -Contain 'Port-NotWorking'
            $trees.Name | Should -Contain 'VLAN-Issues'
            $trees.Name | Should -Contain 'STP-Problems'
        }
    }

    Describe 'Execution Persistence' {
        It 'saves execution state for resume' {
            $tree = Get-BuiltInTree -Name 'Port-NotWorking'
            $execution = Start-TreeExecution -Tree $tree
            $execution = Submit-TreeAnswer -Execution $execution -Answer 'No'

            $savedPath = Save-TreeExecution -Execution $execution
            $loaded = Resume-TreeExecution -Path $savedPath

            $loaded.CurrentNode.Id | Should -Be $execution.CurrentNode.Id
            $loaded.Steps.Count | Should -Be $execution.Steps.Count
        }

        It 'records completed execution to history' {
            $tree = Get-BuiltInTree -Name 'Simple-Test'
            $execution = Start-TreeExecution -Tree $tree -DeviceID 'SW-01'
            $execution = Submit-TreeAnswer -Execution $execution -Answer 'Yes'

            Complete-TreeExecution -Execution $execution -RootCause 'Cable issue' -Resolution 'Replaced cable'

            $history = Get-TreeExecutionHistory -TreeName 'Simple-Test' -Last 1
            $history.RootCause | Should -Be 'Cable issue'
            $history.DeviceID | Should -Be 'SW-01'
        }
    }

    Describe 'Outcome Analytics' {
        It 'calculates resolution statistics' {
            $stats = Get-TreeStatistics -TreeName 'Port-NotWorking'

            $stats.TotalExecutions | Should -BeGreaterOrEqual 0
            $stats.AverageSteps | Should -BeGreaterOrEqual 0
            $stats.MostCommonOutcome | Should -Not -BeNullOrEmpty
        }

        It 'identifies most-used paths' {
            $paths = Get-TreePathAnalysis -TreeName 'Port-NotWorking'

            $paths | Should -Not -BeNullOrEmpty
            $paths[0].UsageCount | Should -BeGreaterOrEqual $paths[1].UsageCount
        }
    }
}

Describe 'Tree Editor Functions' -Tag 'DecisionTree' {
    It 'creates new empty tree' {
        $tree = New-DecisionTree -Name 'New Tree' -Description 'Test tree' -Category 'Custom'

        $tree.Name | Should -Be 'New Tree'
        $tree.Nodes | Should -BeNullOrEmpty
        $tree.IsBuiltIn | Should -BeFalse
    }

    It 'adds node to tree' {
        $tree = New-DecisionTree -Name 'Test'
        Add-TreeNode -Tree $tree -Id 'start' -Type 'decision' -Title 'First question'

        $tree.Nodes.Count | Should -Be 1
        $tree.Nodes[0].Id | Should -Be 'start'
    }

    It 'removes node and updates references' {
        $tree = New-DecisionTree -Name 'Test'
        Add-TreeNode -Tree $tree -Id 'a' -Type 'decision' -Branches @(
            @{ Answer = 'Go to B'; Next = 'b' }
        )
        Add-TreeNode -Tree $tree -Id 'b' -Type 'result' -Title 'End'

        Remove-TreeNode -Tree $tree -Id 'b'

        $tree.Nodes.Count | Should -Be 1
        $tree.Nodes[0].Branches[0].Next | Should -BeNullOrEmpty
    }

    It 'exports tree to JSON' {
        $tree = New-DecisionTree -Name 'Export Test'
        Add-TreeNode -Tree $tree -Id 'start' -Type 'decision' -Title 'Question'

        $json = Export-DecisionTree -Tree $tree -Format JSON
        $parsed = $json | ConvertFrom-Json

        $parsed.name | Should -Be 'Export Test'
    }

    It 'exports tree to Markdown documentation' {
        $tree = Get-BuiltInTree -Name 'Port-NotWorking'

        $md = Export-DecisionTree -Tree $tree -Format Markdown

        $md | Should -Match '# Port-NotWorking'
        $md | Should -Match '\[.*\] -->'  # Flowchart notation
    }
}
```

## UI Mockup Concepts

### Troubleshooting Execution View
```
+------------------------------------------------------------------+
| Troubleshooting: Port Not Working                    [Restart][X]|
+------------------------------------------------------------------+
| Device: SW-BLDG1-01    Interface: Gi1/0/15    Started: 14:30:05 |
+------------------------------------------------------------------+
| Progress: [=====>                    ] Step 3 of ~8             |
| Path: Start > No Link > Check Cable > Cable OK                   |
+------------------------------------------------------------------+
|                                                                  |
|  CURRENT STEP                                                    |
|  +------------------------------------------------------------+  |
|  | Is the cable properly seated at both ends?                 |  |
|  |                                                            |  |
|  | Check the cable connection at:                             |  |
|  | - The switch port (Gi1/0/15)                               |  |
|  | - The patch panel or device                                |  |
|  |                                                            |  |
|  |     [Yes, cable is secure]    [No, cable was loose]       |  |
|  |     [Not sure / Can't check]                               |  |
|  +------------------------------------------------------------+  |
|                                                                  |
+------------------------------------------------------------------+
| NOTES FOR THIS STEP:                                             |
| [                                                              ] |
+------------------------------------------------------------------+
| [<< Back]                                              [Skip >>] |
+------------------------------------------------------------------+
```

### Tree Editor View
```
+------------------------------------------------------------------+
| Decision Tree Editor: Port Not Working              [Save][Test] |
+------------------------------------------------------------------+
| NODE PALETTE              | CANVAS                               |
| +--------+               |  +--------+                          |
| |Decision|               |  | Start  |                          |
| +--------+               |  |  Is    |                          |
| +--------+               |  | link   |                          |
| | Action |               |  |  on?   |                          |
| +--------+               |  +---+----+                          |
| +--------+               |      |                               |
| | Input  |               |  Yes |  No                           |
| +--------+               |   +--+------+                        |
| +--------+               |   |         |                        |
| | Branch |               |   v         v                        |
| +--------+               | +----+   +------+                    |
| +--------+               | |VLAN|   |Cable |                    |
| | Result |               | |chk |   |check |                    |
| +--------+               | +----+   +------+                    |
|                          |                                      |
| PROPERTIES               |                                      |
| Selected: "Start"        |                                      |
| Type: Decision           |                                      |
| Title: [Is link on?   ]  |                                      |
| Branches:                |                                      |
| - Yes -> check_vlan      |                                      |
| - No  -> check_cable     |                                      |
+------------------------------------------------------------------+
```

### Execution History
```
+------------------------------------------------------------------+
| Troubleshooting History                        [Export][Analyze] |
+------------------------------------------------------------------+
| Tree: [All Trees           v]  Period: [Last 30 days v]          |
+------------------------------------------------------------------+
| Date       | Tree              | Device   | Outcome    | Time   |
|------------|-------------------|----------|------------|--------|
| 2026-01-04 | Port Not Working  | SW-01    | Cable Bad  | 3:45   |
| 2026-01-04 | VLAN Issues       | DS-02    | Wrong VLAN | 5:12   |
| 2026-01-03 | STP Problems      | CORE-01  | Unresolved | 15:30  |
+------------------------------------------------------------------+
| ANALYTICS                                                        |
| Most Common Issue: Cable problems (35%)                          |
| Average Resolution Time: 4:32                                    |
| Success Rate: 89%                                                |
+------------------------------------------------------------------+
```

## Automation hooks
- `Tools\Start-TroubleshootingTree.ps1 -Tree "Port-NotWorking" -Device SW-01`
- `Tools\Get-BuiltInTrees.ps1` to list available trees
- `Tools\New-DecisionTree.ps1 -Name "Custom Tree" -Template blank`
- `Tools\Export-DecisionTree.ps1 -Tree "Port-NotWorking" -Format Markdown`
- `Tools\Get-TreeExecutionHistory.ps1 -Last 10` for recent troubleshooting
- `Tools\Get-TreeAnalytics.ps1 -Period LastMonth` for statistics

## Telemetry gates
- Tree execution emits `TreeExecutionStart` with tree name and device
- Step completion emits `TreeStep` with node and duration
- Completion emits `TreeExecutionComplete` with outcome and total time
- Back/restart actions emit `TreeNavigation` for UX analysis

## Dependencies
- Device and interface data for context
- Knowledge base articles (Plan D runbooks)
- Existing troubleshooting documentation

## References
- `docs/plans/PlanD_FeatureExpansion.md` (Guided troubleshooting patterns)
- `docs/Troubleshooting/KnowledgeBase.yml` (Existing knowledge base)
- `docs/plans/PlanAA_DocumentationGenerator.md` (Documentation export)
