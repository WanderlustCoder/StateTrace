Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$scriptPath = Join-Path -Path $repoRoot -ChildPath 'Tools\Test-TaskBoardIntegrity.ps1'

Describe 'Test-TaskBoardIntegrity' {
    BeforeAll {
        if (-not (Test-Path -LiteralPath $scriptPath)) {
            throw "TaskBoard integrity script not found at $scriptPath"
        }
    }

    # LANDMARK: TaskBoard integrity tests - duplicates/empty IDs/large deletion guard
    It 'passes with a valid task board' {
        $fakeRoot = Join-Path -Path $TestDrive -ChildPath 'Repo'
        $taskBoardCsvPath = Join-Path -Path $fakeRoot -ChildPath 'docs\taskboard\TaskBoard.csv'
        New-Item -ItemType Directory -Path (Split-Path -Path $taskBoardCsvPath -Parent) -Force | Out-Null

        $csvContent = @'
"ID","Title","Column","OwnerRole","Deliverable","PlanLink","Notes"
"ST-I-001","Guard","Done","Docs","Test guard","docs/plans/PlanG_ReleaseGovernance.md",""
"ST-I-002","Guard","Done","Docs","Test guard","docs/plans/PlanG_ReleaseGovernance.md",""
'@
        Set-Content -LiteralPath $taskBoardCsvPath -Value $csvContent -Encoding utf8
        $outputPath = Join-Path -Path $TestDrive -ChildPath 'TaskBoardIntegrity.json'

        $result = & $scriptPath -RepositoryRoot $fakeRoot -TaskBoardCsvPath $taskBoardCsvPath -MinimumRowCount 1 -SkipGitDiff -OutputPath $outputPath -PassThru
        $result.Passed | Should Be $true
        $result.RowCount | Should Be 2
    }

    It 'fails when duplicate IDs are present' {
        $fakeRoot = Join-Path -Path $TestDrive -ChildPath 'RepoDup'
        $taskBoardCsvPath = Join-Path -Path $fakeRoot -ChildPath 'docs\taskboard\TaskBoard.csv'
        New-Item -ItemType Directory -Path (Split-Path -Path $taskBoardCsvPath -Parent) -Force | Out-Null

        $csvContent = @'
"ID","Title","Column","OwnerRole","Deliverable","PlanLink","Notes"
"ST-I-001","Guard","Done","Docs","Test guard","docs/plans/PlanG_ReleaseGovernance.md",""
"ST-I-001","Guard","Done","Docs","Test guard","docs/plans/PlanG_ReleaseGovernance.md",""
'@
        Set-Content -LiteralPath $taskBoardCsvPath -Value $csvContent -Encoding utf8
        $outputPath = Join-Path -Path $TestDrive -ChildPath 'TaskBoardIntegrity-dup.json'

        $threw = $false
        try {
            & $scriptPath -RepositoryRoot $fakeRoot -TaskBoardCsvPath $taskBoardCsvPath -MinimumRowCount 1 -SkipGitDiff -OutputPath $outputPath
        } catch {
            $threw = $true
        }
        $threw | Should Be $true
    }

    It 'fails when IDs are empty' {
        $fakeRoot = Join-Path -Path $TestDrive -ChildPath 'RepoEmpty'
        $taskBoardCsvPath = Join-Path -Path $fakeRoot -ChildPath 'docs\taskboard\TaskBoard.csv'
        New-Item -ItemType Directory -Path (Split-Path -Path $taskBoardCsvPath -Parent) -Force | Out-Null

        $csvContent = @'
"ID","Title","Column","OwnerRole","Deliverable","PlanLink","Notes"
"","Guard","Done","Docs","Test guard","docs/plans/PlanG_ReleaseGovernance.md",""
'@
        Set-Content -LiteralPath $taskBoardCsvPath -Value $csvContent -Encoding utf8
        $outputPath = Join-Path -Path $TestDrive -ChildPath 'TaskBoardIntegrity-empty.json'

        $threw = $false
        try {
            & $scriptPath -RepositoryRoot $fakeRoot -TaskBoardCsvPath $taskBoardCsvPath -MinimumRowCount 1 -SkipGitDiff -OutputPath $outputPath
        } catch {
            $threw = $true
        }
        $threw | Should Be $true
    }

    It 'fails when large deletions are detected' {
        $fakeRoot = Join-Path -Path $TestDrive -ChildPath 'RepoDelete'
        $taskBoardCsvPath = Join-Path -Path $fakeRoot -ChildPath 'docs\taskboard\TaskBoard.csv'
        New-Item -ItemType Directory -Path (Split-Path -Path $taskBoardCsvPath -Parent) -Force | Out-Null

        $csvContent = @'
"ID","Title","Column","OwnerRole","Deliverable","PlanLink","Notes"
"ST-I-001","Guard","Done","Docs","Test guard","docs/plans/PlanG_ReleaseGovernance.md",""
'@
        Set-Content -LiteralPath $taskBoardCsvPath -Value $csvContent -Encoding utf8
        $outputPath = Join-Path -Path $TestDrive -ChildPath 'TaskBoardIntegrity-delete.json'

        $threw = $false
        try {
            & $scriptPath -RepositoryRoot $fakeRoot -TaskBoardCsvPath $taskBoardCsvPath -MinimumRowCount 1 -OutputPath $outputPath -GitDiffOverride @{ Added = 0; Deleted = 30; HasDiff = $true; HeadRowCount = 40 }
        } catch {
            $threw = $true
        }
        $threw | Should Be $true
    }
}
