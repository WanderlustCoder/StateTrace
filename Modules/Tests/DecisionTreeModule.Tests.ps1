Set-StrictMode -Version Latest

$modulePath = Join-Path $PSScriptRoot '..\DecisionTreeModule.psm1'
Import-Module $modulePath -Force

Describe 'DecisionTreeModule - Tree Creation' {

    Context 'New-DecisionTree' {
        It 'creates empty tree with required fields' {
            $tree = New-DecisionTree -Name 'Test Tree'

            $tree.Name | Should Be 'Test Tree'
            $tree.Nodes.Count | Should Be 0
            $tree.IsBuiltIn | Should Be $false
            $tree.IsEnabled | Should Be $true
        }

        It 'sets optional fields' {
            $tree = New-DecisionTree -Name 'Custom' -Description 'Test desc' -Category 'Layer1' -Version '2.0'

            $tree.Description | Should Be 'Test desc'
            $tree.Category | Should Be 'Layer1'
            $tree.Version | Should Be '2.0'
        }
    }

    Context 'Add-TreeNode' {
        It 'adds decision node to tree' {
            $tree = New-DecisionTree -Name 'Test'
            Add-TreeNode -Tree $tree -Id 'start' -Type 'decision' -Title 'First question'

            $tree.Nodes.Count | Should Be 1
            $tree.Nodes[0].Id | Should Be 'start'
            $tree.Nodes[0].Type | Should Be 'decision'
        }

        It 'sets first node as start node' {
            $tree = New-DecisionTree -Name 'Test'
            Add-TreeNode -Tree $tree -Id 'first' -Type 'decision' -Title 'First'

            $tree.StartNodeId | Should Be 'first'
        }

        It 'adds node with branches' {
            $tree = New-DecisionTree -Name 'Test'
            Add-TreeNode -Tree $tree -Id 'q1' -Type 'decision' -Title 'Question' -Branches @(
                @{ Answer = 'Yes'; Next = 'yes_node' },
                @{ Answer = 'No'; Next = 'no_node' }
            )

            $tree.Nodes[0].Branches.Count | Should Be 2
            $tree.Nodes[0].Branches[0].Answer | Should Be 'Yes'
            $tree.Nodes[0].Branches[0].Next | Should Be 'yes_node'
        }

        It 'adds result node with outcome' {
            $tree = New-DecisionTree -Name 'Test'
            Add-TreeNode -Tree $tree -Id 'end' -Type 'result' -Title 'Done' -Outcome 'Success'

            $tree.Nodes[0].Outcome | Should Be 'Success'
        }
    }

    Context 'Remove-TreeNode' {
        It 'removes node from tree' {
            $tree = New-DecisionTree -Name 'Test'
            Add-TreeNode -Tree $tree -Id 'a' -Type 'decision' -Title 'A'
            Add-TreeNode -Tree $tree -Id 'b' -Type 'result' -Title 'B'

            Remove-TreeNode -Tree $tree -Id 'b'

            $tree.Nodes.Count | Should Be 1
            $tree.Nodes[0].Id | Should Be 'a'
        }

        It 'clears references to removed node' {
            $tree = New-DecisionTree -Name 'Test'
            Add-TreeNode -Tree $tree -Id 'a' -Type 'decision' -Title 'A' -Branches @(
                @{ Answer = 'Go'; Next = 'b' }
            )
            Add-TreeNode -Tree $tree -Id 'b' -Type 'result' -Title 'B'

            Remove-TreeNode -Tree $tree -Id 'b'

            $tree.Nodes[0].Branches[0].Next | Should Be $null
        }
    }
}

Describe 'DecisionTreeModule - Import/Export' {

    Context 'Import-DecisionTree' {
        It 'imports tree from JSON' {
            $json = @'
{
    "name": "Test Tree",
    "description": "A test",
    "category": "Test",
    "nodes": [
        { "id": "start", "type": "decision", "title": "Question?", "branches": [
            { "answer": "Yes", "next": "end" }
        ]},
        { "id": "end", "type": "result", "title": "Done", "outcome": "Complete" }
    ]
}
'@
            $tree = Import-DecisionTree -Json $json

            $tree.Name | Should Be 'Test Tree'
            $tree.Description | Should Be 'A test'
            $tree.Nodes.Count | Should Be 2
            $tree.StartNodeId | Should Be 'start'
        }

        It 'sets default values for missing fields' {
            $json = '{ "nodes": [] }'
            $tree = Import-DecisionTree -Json $json

            $tree.Name | Should Be 'Unnamed'
            $tree.Category | Should Be 'Custom'
            $tree.Version | Should Be '1.0'
        }
    }

    Context 'Export-DecisionTree' {
        It 'exports tree to JSON' {
            $tree = New-DecisionTree -Name 'Export Test'
            Add-TreeNode -Tree $tree -Id 'start' -Type 'decision' -Title 'Q1'

            $json = Export-DecisionTree -Tree $tree -Format JSON
            $parsed = $json | ConvertFrom-Json

            $parsed.name | Should Be 'Export Test'
            $parsed.nodes.Count | Should Be 1
        }

        It 'exports tree to Markdown' {
            $tree = New-DecisionTree -Name 'MD Test' -Description 'Test tree'
            Add-TreeNode -Tree $tree -Id 'start' -Type 'decision' -Title 'Question'

            $md = Export-DecisionTree -Tree $tree -Format Markdown

            $md | Should Match '# MD Test'
            $md | Should Match 'Test tree'
        }
    }
}

Describe 'DecisionTreeModule - Validation' {

    Context 'Test-DecisionTree' {
        It 'validates valid tree' {
            $tree = New-DecisionTree -Name 'Valid'
            Add-TreeNode -Tree $tree -Id 'start' -Type 'decision' -Title 'Q' -Branches @(
                @{ Answer = 'Yes'; Next = 'end' }
            )
            Add-TreeNode -Tree $tree -Id 'end' -Type 'result' -Title 'Done'

            $result = Test-DecisionTree -Tree $tree

            $result.IsValid | Should Be $true
            $result.Errors.Count | Should Be 0
        }

        It 'detects orphan nodes' {
            $tree = New-DecisionTree -Name 'Orphan'
            Add-TreeNode -Tree $tree -Id 'start' -Type 'decision' -Title 'Start' -Branches @(
                @{ Answer = 'Yes'; Next = 'end' }
            )
            Add-TreeNode -Tree $tree -Id 'end' -Type 'result' -Title 'End'
            Add-TreeNode -Tree $tree -Id 'orphan' -Type 'action' -Title 'Orphan'

            $result = Test-DecisionTree -Tree $tree

            $result.IsValid | Should Be $false
            $result.Errors | Should Match 'Orphan node: orphan'
        }

        It 'detects invalid node references' {
            $tree = New-DecisionTree -Name 'BadRef'
            Add-TreeNode -Tree $tree -Id 'start' -Type 'decision' -Title 'Q' -Branches @(
                @{ Answer = 'Yes'; Next = 'nonexistent' }
            )

            $result = Test-DecisionTree -Tree $tree

            $result.IsValid | Should Be $false
            $result.Errors | Should Match 'Invalid target node: nonexistent'
        }

        It 'warns about potential loops' {
            $tree = New-DecisionTree -Name 'Loop'
            Add-TreeNode -Tree $tree -Id 'a' -Type 'decision' -Title 'A' -Branches @(
                @{ Answer = 'Go B'; Next = 'b' }
            )
            Add-TreeNode -Tree $tree -Id 'b' -Type 'decision' -Title 'B' -Branches @(
                @{ Answer = 'Go A'; Next = 'a' }
            )

            $result = Test-DecisionTree -Tree $tree
            $loopWarning = $result.Warnings | Where-Object { $_ -match 'loop' }

            $loopWarning | Should Not Be $null
        }

        It 'warns when no result nodes' {
            $tree = New-DecisionTree -Name 'NoResult'
            Add-TreeNode -Tree $tree -Id 'start' -Type 'decision' -Title 'Q'

            $result = Test-DecisionTree -Tree $tree

            $result.Warnings | Should Match 'no result nodes'
        }
    }
}

Describe 'DecisionTreeModule - Execution' {

    BeforeAll {
        $script:simpleTree = @'
{
    "name": "Simple",
    "nodes": [
        { "id": "q1", "type": "decision", "title": "Is it working?", "branches": [
            { "answer": "Yes", "next": "done_yes" },
            { "answer": "No", "next": "done_no" }
        ]},
        { "id": "done_yes", "type": "result", "title": "Great!", "outcome": "Working" },
        { "id": "done_no", "type": "result", "title": "Fix it", "outcome": "NotWorking" }
    ]
}
'@ | ConvertFrom-Json
    }

    Context 'Start-TreeExecution' {
        It 'starts at first node' {
            $tree = Import-DecisionTree -Json ($script:simpleTree | ConvertTo-Json -Depth 10)
            $execution = Start-TreeExecution -Tree $tree

            $execution.CurrentNode.Id | Should Be 'q1'
            $execution.IsComplete | Should Be $false
            $execution.Steps.Count | Should Be 1
        }

        It 'sets device context' {
            $tree = Import-DecisionTree -Json ($script:simpleTree | ConvertTo-Json -Depth 10)
            $execution = Start-TreeExecution -Tree $tree -DeviceID 'SW-01' -InterfaceName 'Gi1/0/1'

            $execution.DeviceID | Should Be 'SW-01'
            $execution.InterfaceName | Should Be 'Gi1/0/1'
        }
    }

    Context 'Submit-TreeAnswer' {
        It 'advances to next node on answer' {
            $tree = Import-DecisionTree -Json ($script:simpleTree | ConvertTo-Json -Depth 10)
            $execution = Start-TreeExecution -Tree $tree
            $execution = Submit-TreeAnswer -Execution $execution -Answer 'Yes'

            $execution.CurrentNode.Id | Should Be 'done_yes'
        }

        It 'records answer in step history' {
            $tree = Import-DecisionTree -Json ($script:simpleTree | ConvertTo-Json -Depth 10)
            $execution = Start-TreeExecution -Tree $tree
            $execution = Submit-TreeAnswer -Execution $execution -Answer 'No'

            $execution.Steps[0].Answer | Should Be 'No'
        }

        It 'marks complete at result node' {
            $tree = Import-DecisionTree -Json ($script:simpleTree | ConvertTo-Json -Depth 10)
            $execution = Start-TreeExecution -Tree $tree
            $execution = Submit-TreeAnswer -Execution $execution -Answer 'Yes'

            $execution.IsComplete | Should Be $true
            $execution.Outcome | Should Be 'Working'
        }

        It 'throws on invalid answer' {
            $tree = Import-DecisionTree -Json ($script:simpleTree | ConvertTo-Json -Depth 10)
            $execution = Start-TreeExecution -Tree $tree

            { Submit-TreeAnswer -Execution $execution -Answer 'Maybe' } | Should Throw
        }
    }

    Context 'Undo-TreeStep' {
        It 'goes back to previous node' {
            $tree = Import-DecisionTree -Json ($script:simpleTree | ConvertTo-Json -Depth 10)
            $execution = Start-TreeExecution -Tree $tree
            $execution = Submit-TreeAnswer -Execution $execution -Answer 'Yes'
            $execution = Undo-TreeStep -Execution $execution

            $execution.CurrentNode.Id | Should Be 'q1'
            $execution.IsComplete | Should Be $false
        }

        It 'clears completion status on undo' {
            $tree = Import-DecisionTree -Json ($script:simpleTree | ConvertTo-Json -Depth 10)
            $execution = Start-TreeExecution -Tree $tree
            $execution = Submit-TreeAnswer -Execution $execution -Answer 'No'
            $execution = Undo-TreeStep -Execution $execution

            $execution.IsComplete | Should Be $false
            $execution.Outcome | Should Be $null
        }

        It 'does nothing at start node' {
            $tree = Import-DecisionTree -Json ($script:simpleTree | ConvertTo-Json -Depth 10)
            $execution = Start-TreeExecution -Tree $tree
            $execution = Undo-TreeStep -Execution $execution

            $execution.CurrentNode.Id | Should Be 'q1'
            $execution.Steps.Count | Should Be 1
        }
    }

    Context 'Continue-TreeExecution' {
        It 'advances from action node' {
            $json = @'
{
    "name": "ActionTest",
    "nodes": [
        { "id": "action1", "type": "action", "title": "Do something", "next": "result1" },
        { "id": "result1", "type": "result", "title": "Done", "outcome": "Complete" }
    ]
}
'@
            $tree = Import-DecisionTree -Json $json
            $execution = Start-TreeExecution -Tree $tree
            $execution = Continue-TreeExecution -Execution $execution

            $execution.CurrentNode.Id | Should Be 'result1'
            $execution.IsComplete | Should Be $true
        }
    }

    Context 'Execution Duration' {
        It 'calculates duration on completion' {
            $tree = Import-DecisionTree -Json ($script:simpleTree | ConvertTo-Json -Depth 10)
            $execution = Start-TreeExecution -Tree $tree
            Start-Sleep -Milliseconds 50
            $execution = Submit-TreeAnswer -Execution $execution -Answer 'Yes'

            $execution.Duration | Should Not Be $null
            $execution.Duration.TotalMilliseconds | Should BeGreaterThan 40
        }
    }
}

Describe 'DecisionTreeModule - Built-in Trees' {

    Context 'Get-BuiltInTree' {
        It 'lists all built-in trees' {
            $trees = Get-BuiltInTree -List

            $trees.Count | Should BeGreaterThan 2
        }

        It 'returns tree by name' {
            $tree = Get-BuiltInTree -Name 'Port-NotWorking'

            $tree | Should Not Be $null
            $tree.Name | Should Be 'Port-NotWorking'
            $tree.IsBuiltIn | Should Be $true
        }

        It 'returns null for unknown tree' {
            $tree = Get-BuiltInTree -Name 'NonExistent'

            $tree | Should Be $null
        }

        It 'includes Port-NotWorking tree' {
            $trees = @(Get-BuiltInTree -List)
            $found = @($trees | Where-Object { $_.Name -eq 'Port-NotWorking' })

            $found.Count | Should BeGreaterThan 0
        }

        It 'includes VLAN-Issues tree' {
            $trees = @(Get-BuiltInTree -List)
            $found = @($trees | Where-Object { $_.Name -eq 'VLAN-Issues' })

            $found.Count | Should BeGreaterThan 0
        }

        It 'includes STP-Problems tree' {
            $trees = @(Get-BuiltInTree -List)
            $found = @($trees | Where-Object { $_.Name -eq 'STP-Problems' })

            $found.Count | Should BeGreaterThan 0
        }
    }

    Context 'Built-in Tree Validation' {
        It 'Port-NotWorking tree is valid' {
            $tree = Get-BuiltInTree -Name 'Port-NotWorking'
            $validation = Test-DecisionTree -Tree $tree

            $validation.IsValid | Should Be $true
        }

        It 'VLAN-Issues tree is valid' {
            $tree = Get-BuiltInTree -Name 'VLAN-Issues'
            $validation = Test-DecisionTree -Tree $tree

            $validation.IsValid | Should Be $true
        }

        It 'STP-Problems tree is valid' {
            $tree = Get-BuiltInTree -Name 'STP-Problems'
            $validation = Test-DecisionTree -Tree $tree

            $validation.IsValid | Should Be $true
        }
    }

    Context 'Built-in Tree Execution' {
        It 'can execute Port-NotWorking tree' {
            $tree = Get-BuiltInTree -Name 'Port-NotWorking'
            $execution = Start-TreeExecution -Tree $tree

            $execution.CurrentNode.Id | Should Be 'start'
            $execution.CurrentNode.Title | Should Match 'link light'
        }

        It 'can complete Simple-Test tree' {
            $tree = Get-BuiltInTree -Name 'Simple-Test'
            $execution = Start-TreeExecution -Tree $tree
            $execution = Submit-TreeAnswer -Execution $execution -Answer 'Yes'

            $execution.IsComplete | Should Be $true
            $execution.Outcome | Should Be 'Working'
        }
    }
}

Describe 'DecisionTreeModule - Input Nodes' {

    Context 'Submit-TreeInput' {
        It 'stores variable value' {
            $json = @'
{
    "name": "InputTest",
    "nodes": [
        { "id": "input1", "type": "input", "title": "Enter value", "variableName": "testVar", "next": "result1" },
        { "id": "result1", "type": "result", "title": "Done", "outcome": "Complete" }
    ]
}
'@
            $tree = Import-DecisionTree -Json $json
            $execution = Start-TreeExecution -Tree $tree
            $execution = Submit-TreeInput -Execution $execution -Value 'test123'

            $execution.Variables['testVar'] | Should Be 'test123'
        }

        It 'records input in step' {
            $json = @'
{
    "name": "InputTest",
    "nodes": [
        { "id": "input1", "type": "input", "title": "Enter value", "variableName": "val", "next": "result1" },
        { "id": "result1", "type": "result", "title": "Done", "outcome": "Complete" }
    ]
}
'@
            $tree = Import-DecisionTree -Json $json
            $execution = Start-TreeExecution -Tree $tree
            $execution = Submit-TreeInput -Execution $execution -Value 42

            $execution.Steps[0].InputValue | Should Be 42
        }
    }

    Context 'Branch Conditions' {
        It 'evaluates numeric condition' {
            $json = @'
{
    "name": "BranchTest",
    "nodes": [
        { "id": "input1", "type": "input", "title": "Enter loss", "variableName": "loss", "next": "branch1" },
        { "id": "branch1", "type": "branch", "title": "Check", "branches": [
            { "condition": "$loss -lt 5", "next": "ok" },
            { "condition": "$true", "next": "bad" }
        ]},
        { "id": "ok", "type": "result", "title": "OK", "outcome": "Acceptable" },
        { "id": "bad", "type": "result", "title": "Bad", "outcome": "TooHigh" }
    ]
}
'@
            $tree = Import-DecisionTree -Json $json
            $execution = Start-TreeExecution -Tree $tree
            $execution = Submit-TreeInput -Execution $execution -Value 2
            # Now at branch1, submit dummy value to trigger condition check
            $execution = Submit-TreeInput -Execution $execution -Value 0

            $execution.CurrentNode.Id | Should Be 'ok'
        }
    }
}

#region ST-AB-006: Execution Persistence and Analytics Tests

Describe 'DecisionTreeModule - Execution Persistence' {

    BeforeAll {
        $script:testSaveDir = Join-Path $env:TEMP 'DecisionTreePersistenceTest'
        New-Item -ItemType Directory -Path $script:testSaveDir -Force | Out-Null
    }

    AfterAll {
        if (Test-Path $script:testSaveDir) {
            Remove-Item -Path $script:testSaveDir -Recurse -Force
        }
    }

    Context 'Save-TreeExecution' {
        It 'saves execution state to file' {
            $tree = Get-BuiltInTree -Name 'Simple-Test'
            $execution = Start-TreeExecution -Tree $tree -DeviceID 'SW-01'

            $savePath = Join-Path $script:testSaveDir 'test_save.json'
            $result = Save-TreeExecution -Execution $execution -Path $savePath

            Test-Path $result | Should Be $true
        }

        It 'saves current node and steps' {
            $tree = Get-BuiltInTree -Name 'Simple-Test'
            $execution = Start-TreeExecution -Tree $tree
            $execution = Submit-TreeAnswer -Execution $execution -Answer 'No'

            $savePath = Join-Path $script:testSaveDir 'test_save2.json'
            Save-TreeExecution -Execution $execution -Path $savePath

            $json = Get-Content -LiteralPath $savePath -Raw | ConvertFrom-Json
            $json.CurrentNodeId | Should Be 'done_no'
            $json.Steps.Count | Should Be 2
        }
    }

    Context 'Resume-TreeExecution' {
        It 'resumes execution from saved file' {
            $tree = Get-BuiltInTree -Name 'Simple-Test'
            $execution = Start-TreeExecution -Tree $tree -DeviceID 'SW-02'

            $savePath = Join-Path $script:testSaveDir 'test_resume.json'
            Save-TreeExecution -Execution $execution -Path $savePath

            $resumed = Resume-TreeExecution -Path $savePath

            $resumed.DeviceID | Should Be 'SW-02'
            $resumed.CurrentNode.Id | Should Be 'q1'
        }

        It 'preserves step history on resume' {
            $tree = Get-BuiltInTree -Name 'Simple-Test'
            $execution = Start-TreeExecution -Tree $tree
            $execution = Submit-TreeAnswer -Execution $execution -Answer 'Yes'

            $savePath = Join-Path $script:testSaveDir 'test_resume2.json'
            Save-TreeExecution -Execution $execution -Path $savePath

            $resumed = Resume-TreeExecution -Path $savePath

            $resumed.Steps.Count | Should Be 2
            $resumed.IsComplete | Should Be $true
        }
    }
}

Describe 'DecisionTreeModule - Execution History' {

    BeforeAll {
        # Use temp path for test history
        $script:testHistoryPath = Join-Path $env:TEMP 'DecisionTreeTestHistory.json'
        Initialize-ExecutionHistory -Path $script:testHistoryPath
        Clear-TreeExecutionHistory
    }

    AfterAll {
        Clear-TreeExecutionHistory
    }

    Context 'Complete-TreeExecution' {
        It 'records completed execution to history' {
            $tree = Get-BuiltInTree -Name 'Simple-Test'
            $execution = Start-TreeExecution -Tree $tree -DeviceID 'SW-01'
            $execution = Submit-TreeAnswer -Execution $execution -Answer 'Yes'

            $record = Complete-TreeExecution -Execution $execution -RootCause 'Test' -Resolution 'Fixed'

            $record.ExecutionID | Should Match '^EXEC-'
            $record.TreeName | Should Be 'Simple-Test'
            $record.RootCause | Should Be 'Test'
        }

        It 'records path taken through tree' {
            Clear-TreeExecutionHistory
            $tree = Get-BuiltInTree -Name 'Simple-Test'
            $execution = Start-TreeExecution -Tree $tree
            $execution = Submit-TreeAnswer -Execution $execution -Answer 'No'

            $record = Complete-TreeExecution -Execution $execution

            $record.Path | Should Match 'q1 -> done_no'
        }
    }

    Context 'Get-TreeExecutionHistory' {
        BeforeAll {
            Clear-TreeExecutionHistory

            # Create some test executions
            $tree = Get-BuiltInTree -Name 'Simple-Test'

            $exec1 = Start-TreeExecution -Tree $tree -DeviceID 'SW-01'
            $exec1 = Submit-TreeAnswer -Execution $exec1 -Answer 'Yes'
            Complete-TreeExecution -Execution $exec1 -RootCause 'Test1' | Out-Null

            $exec2 = Start-TreeExecution -Tree $tree -DeviceID 'SW-02'
            $exec2 = Submit-TreeAnswer -Execution $exec2 -Answer 'No'
            Complete-TreeExecution -Execution $exec2 -RootCause 'Test2' | Out-Null

            $exec3 = Start-TreeExecution -Tree $tree -DeviceID 'SW-01'
            $exec3 = Submit-TreeAnswer -Execution $exec3 -Answer 'Yes'
            Complete-TreeExecution -Execution $exec3 -RootCause 'Test3' | Out-Null
        }

        It 'retrieves all history' {
            $history = Get-TreeExecutionHistory

            $history.Count | Should BeGreaterThan 2
        }

        It 'filters by tree name' {
            $history = Get-TreeExecutionHistory -TreeName 'Simple-Test'

            @($history).Count | Should BeGreaterThan 0
            $history | ForEach-Object { $_.TreeName | Should Be 'Simple-Test' }
        }

        It 'filters by device ID' {
            $history = Get-TreeExecutionHistory -DeviceID 'SW-01'

            @($history).Count | Should BeGreaterThan 0
            $history | ForEach-Object { $_.DeviceID | Should Be 'SW-01' }
        }

        It 'limits results with -Last' {
            $history = Get-TreeExecutionHistory -Last 1

            @($history).Count | Should Be 1
        }
    }
}

Describe 'DecisionTreeModule - Analytics' {

    BeforeAll {
        $script:testHistoryPath = Join-Path $env:TEMP 'DecisionTreeAnalyticsTest.json'
        Initialize-ExecutionHistory -Path $script:testHistoryPath
        Clear-TreeExecutionHistory

        # Create test data
        $tree = Get-BuiltInTree -Name 'Simple-Test'

        # Multiple executions with different outcomes
        for ($i = 1; $i -le 3; $i++) {
            $exec = Start-TreeExecution -Tree $tree -DeviceID "SW-0$i"
            $exec = Submit-TreeAnswer -Execution $exec -Answer 'Yes'
            Complete-TreeExecution -Execution $exec | Out-Null
        }

        for ($i = 1; $i -le 2; $i++) {
            $exec = Start-TreeExecution -Tree $tree -DeviceID "DS-0$i"
            $exec = Submit-TreeAnswer -Execution $exec -Answer 'No'
            Complete-TreeExecution -Execution $exec | Out-Null
        }
    }

    AfterAll {
        Clear-TreeExecutionHistory
    }

    Context 'Get-TreeStatistics' {
        It 'calculates total executions' {
            $stats = Get-TreeStatistics -TreeName 'Simple-Test'

            $stats.TotalExecutions | Should Be 5
        }

        It 'calculates average steps' {
            $stats = Get-TreeStatistics -TreeName 'Simple-Test'

            $stats.AverageSteps | Should BeGreaterThan 0
        }

        It 'identifies most common outcome' {
            $stats = Get-TreeStatistics -TreeName 'Simple-Test'

            $stats.MostCommonOutcome | Should Be 'Working'
        }

        It 'provides outcome breakdown' {
            $stats = Get-TreeStatistics -TreeName 'Simple-Test'

            $stats.OutcomeBreakdown['Working'] | Should Be 3
            $stats.OutcomeBreakdown['NotWorking'] | Should Be 2
        }

        It 'calculates success rate' {
            $stats = Get-TreeStatistics -TreeName 'Simple-Test'

            $stats.SuccessRate | Should Be 100
        }

        It 'returns zero stats for unknown tree' {
            $stats = Get-TreeStatistics -TreeName 'NonExistent'

            $stats.TotalExecutions | Should Be 0
            $stats.MostCommonOutcome | Should Be 'N/A'
        }
    }

    Context 'Get-TreePathAnalysis' {
        It 'identifies unique paths' {
            $paths = Get-TreePathAnalysis -TreeName 'Simple-Test'

            @($paths).Count | Should Be 2
        }

        It 'counts path usage' {
            $paths = Get-TreePathAnalysis -TreeName 'Simple-Test'
            $yesPath = $paths | Where-Object { $_.Path -match 'done_yes' }

            $yesPath.UsageCount | Should Be 3
        }

        It 'calculates path percentage' {
            $paths = Get-TreePathAnalysis -TreeName 'Simple-Test'
            $yesPath = $paths | Where-Object { $_.Path -match 'done_yes' }

            $yesPath.Percentage | Should Be 60
        }

        It 'sorts by usage count descending' {
            $paths = Get-TreePathAnalysis -TreeName 'Simple-Test'

            $paths[0].UsageCount | Should BeGreaterThan $paths[1].UsageCount
        }

        It 'returns empty for unknown tree' {
            $paths = Get-TreePathAnalysis -TreeName 'NonExistent'

            @($paths).Count | Should Be 0
        }
    }
}

#endregion
