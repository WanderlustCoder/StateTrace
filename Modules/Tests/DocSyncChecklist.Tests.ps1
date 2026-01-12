Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$scriptPath = Join-Path -Path $repoRoot -ChildPath 'Tools\Test-DocSyncChecklist.ps1'

Describe 'Test-DocSyncChecklist' {
    BeforeAll {
        if (-not (Test-Path -LiteralPath $scriptPath)) {
            throw "Doc sync checklist script not found at $scriptPath"
        }
    }

    It 'passes when required doc files and session log references exist' {
        $taskId = 'ST-G-006'
        $fakeRoot = Join-Path -Path $TestDrive -ChildPath 'Repo'
        $docsRoot = Join-Path -Path $fakeRoot -ChildPath 'docs'
        $taskBoardPath = Join-Path -Path $docsRoot -ChildPath 'StateTrace_TaskBoard.md'
        $taskBoardCsvPath = Join-Path -Path $docsRoot -ChildPath 'taskboard\TaskBoard.csv'
        $planPath = Join-Path -Path $docsRoot -ChildPath 'plans\PlanG_ReleaseGovernance.md'
        $fakeToolsPath = Join-Path -Path $fakeRoot -ChildPath 'Tools'
        $integrityScriptPath = Join-Path -Path $repoRoot -ChildPath 'Tools\Test-TaskBoardIntegrity.ps1'
        $backlogPath = Join-Path -Path $docsRoot -ChildPath 'CODEX_BACKLOG.md'
        $sessionLogPath = Join-Path -Path $docsRoot -ChildPath 'agents\sessions\2025-12-22_session-0007.md'
        $fakeToolsPath = Join-Path -Path $fakeRoot -ChildPath 'Tools'
        $integrityScriptPath = Join-Path -Path $repoRoot -ChildPath 'Tools\Test-TaskBoardIntegrity.ps1'

        New-Item -ItemType Directory -Path (Split-Path -Path $taskBoardPath -Parent) -Force | Out-Null
        New-Item -ItemType Directory -Path (Split-Path -Path $taskBoardCsvPath -Parent) -Force | Out-Null
        New-Item -ItemType Directory -Path (Split-Path -Path $planPath -Parent) -Force | Out-Null
        New-Item -ItemType Directory -Path $fakeToolsPath -Force | Out-Null
        Copy-Item -LiteralPath $integrityScriptPath -Destination (Join-Path -Path $fakeToolsPath -ChildPath 'Test-TaskBoardIntegrity.ps1') -Force
        New-Item -ItemType Directory -Path (Split-Path -Path $sessionLogPath -Parent) -Force | Out-Null
        New-Item -ItemType Directory -Path $fakeToolsPath -Force | Out-Null
        Copy-Item -LiteralPath $integrityScriptPath -Destination (Join-Path -Path $fakeToolsPath -ChildPath 'Test-TaskBoardIntegrity.ps1') -Force

        Set-Content -LiteralPath $taskBoardPath -Value "| $taskId | Doc sync enforcement | Backlog | Docs | Deliverable | docs/plans/PlanG_ReleaseGovernance.md |" -Encoding utf8

        $csvContent = @'
"ID","Title","Column","OwnerRole","Deliverable","PlanLink","Notes"
"ST-G-006","Doc sync enforcement","Backlog","Docs","Checklist script","docs/plans/PlanG_ReleaseGovernance.md",""
'@
        Set-Content -LiteralPath $taskBoardCsvPath -Value $csvContent -Encoding utf8

        Set-Content -LiteralPath $planPath -Value "ST-G-006 Doc sync enforcement" -Encoding utf8
        Set-Content -LiteralPath $backlogPath -Value "ST-G-006 Doc sync enforcement" -Encoding utf8

        $sessionContent = @'
- ST-G-006
- docs/StateTrace_TaskBoard.md
- docs/taskboard/TaskBoard.csv
- docs/CODEX_BACKLOG.md
- docs/plans/PlanG_ReleaseGovernance.md
'@
        Set-Content -LiteralPath $sessionLogPath -Value $sessionContent -Encoding utf8

        $result = & $scriptPath -TaskId $taskId -RepositoryRoot $fakeRoot -SessionLogPath $sessionLogPath -RequireSessionLog -RequireBacklogEntry -TaskBoardMinimumRowCount 1 -PassThru
        $result.Passed | Should Be $true
        $result.Plan.Source | Should Be 'TaskBoardCsv'
        $result.SessionLog.References.Count | Should BeGreaterThan 0
    }

    It 'throws when the task board row is missing' {
        $taskId = 'ST-G-006'
        $fakeRoot = Join-Path -Path $TestDrive -ChildPath 'Repo2'
        $docsRoot = Join-Path -Path $fakeRoot -ChildPath 'docs'
        $taskBoardPath = Join-Path -Path $docsRoot -ChildPath 'StateTrace_TaskBoard.md'
        $taskBoardCsvPath = Join-Path -Path $docsRoot -ChildPath 'taskboard\TaskBoard.csv'
        $planPath = Join-Path -Path $docsRoot -ChildPath 'plans\PlanG_ReleaseGovernance.md'

        New-Item -ItemType Directory -Path (Split-Path -Path $taskBoardPath -Parent) -Force | Out-Null
        New-Item -ItemType Directory -Path (Split-Path -Path $taskBoardCsvPath -Parent) -Force | Out-Null
        New-Item -ItemType Directory -Path (Split-Path -Path $planPath -Parent) -Force | Out-Null

        Set-Content -LiteralPath $taskBoardPath -Value "| ST-G-000 | Doc sync enforcement | Backlog | Docs | Deliverable | docs/plans/PlanG_ReleaseGovernance.md |" -Encoding utf8

        $csvContent = @'
"ID","Title","Column","OwnerRole","Deliverable","PlanLink","Notes"
"ST-G-006","Doc sync enforcement","Backlog","Docs","Checklist script","docs/plans/PlanG_ReleaseGovernance.md",""
'@
        Set-Content -LiteralPath $taskBoardCsvPath -Value $csvContent -Encoding utf8

        Set-Content -LiteralPath $planPath -Value "ST-G-006 Doc sync enforcement" -Encoding utf8

        $threw = $false
        try {
            & $scriptPath -TaskId $taskId -RepositoryRoot $fakeRoot -TaskBoardPath $taskBoardPath -TaskBoardCsvPath $taskBoardCsvPath -PlanPath $planPath -TaskBoardMinimumRowCount 1
        } catch {
            $threw = $true
        }
        $threw | Should Be $true
    }
}
