Set-StrictMode -Version Latest

Describe "ParserRunspaceModule" {
    BeforeAll {
        $modulePath = Join-Path (Split-Path $PSCommandPath) "..\\ParserRunspaceModule.psm1"
        Import-Module (Resolve-Path $modulePath) -Force
    }

    AfterAll {
        Remove-Module ParserRunspaceModule -Force -ErrorAction SilentlyContinue
    }

    It "invokes the worker once per file when running synchronously" {
        Mock -ModuleName ParserRunspaceModule -CommandName Invoke-DeviceParseWorker -MockWith {}

        $files = @('C:\logs\device1.log', 'C:\logs\device2.log')
        ParserRunspaceModule\Invoke-DeviceParsingJobs -DeviceFiles $files -ModulesPath 'C:\modules' -ArchiveRoot 'C:\archives' -DatabasePath $null -Synchronous

        Assert-MockCalled -ModuleName ParserRunspaceModule -CommandName Invoke-DeviceParseWorker -Times 2
        Assert-MockCalled -ModuleName ParserRunspaceModule -CommandName Invoke-DeviceParseWorker -ParameterFilter { $FilePath -eq 'C:\logs\device1.log' -and -not $EnableVerbose } -Times 1
        Assert-MockCalled -ModuleName ParserRunspaceModule -CommandName Invoke-DeviceParseWorker -ParameterFilter { $FilePath -eq 'C:\logs\device2.log' -and -not $EnableVerbose } -Times 1
    }

    It "falls back to synchronous execution when MaxThreads is 1" {
        Mock -ModuleName ParserRunspaceModule -CommandName Invoke-DeviceParseWorker -MockWith {}

        ParserRunspaceModule\Invoke-DeviceParsingJobs -DeviceFiles @('C:\logs\single.log') -ModulesPath 'C:\modules' -ArchiveRoot 'C:\archives' -DatabasePath 'C:\db.accdb' -MaxThreads 1

        Assert-MockCalled -ModuleName ParserRunspaceModule -CommandName Invoke-DeviceParseWorker -ParameterFilter { $FilePath -eq 'C:\logs\single.log' } -Times 1
    }
}
