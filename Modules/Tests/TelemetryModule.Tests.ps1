Set-StrictMode -Version Latest

Describe "TelemetryModule" {
    BeforeAll {
        $modulePath = Join-Path (Split-Path $PSCommandPath) "..\TelemetryModule.psm1"
        Import-Module (Resolve-Path $modulePath) -Force
        $testOut = Join-Path (Split-Path $PSCommandPath) "..\..\Logs\TestTelemetry"
        New-Item -ItemType Directory -Force -Path $testOut | Out-Null
        $env:STATETRACE_TELEMETRY_DIR = $testOut
    }

    AfterAll {
        Remove-Module TelemetryModule -Force
        Remove-Item Env:\STATETRACE_TELEMETRY_DIR -ErrorAction SilentlyContinue
    }

    It "builds a daily telemetry path" {
        $path = TelemetryModule\Get-TelemetryLogPath
        ($path -like "*Logs\TestTelemetry\*.json") | Should Be True
    }

    It "initializes the debug flag and can enable verbose preference" {
        $previousVerbose = $VerbosePreference
        Remove-Variable -Name StateTraceDebug -Scope Global -ErrorAction SilentlyContinue
        $VerbosePreference = 'SilentlyContinue'

        TelemetryModule\Initialize-StateTraceDebug
        $Global:StateTraceDebug | Should Be $false

        $Global:StateTraceDebug = $true
        $VerbosePreference = 'SilentlyContinue'
        TelemetryModule\Initialize-StateTraceDebug -EnableVerbosePreference
        $Global:VerbosePreference | Should Be 'Continue'

        $Global:StateTraceDebug = $false
        $VerbosePreference = $previousVerbose
    }

    It "loads InterfaceCommon from a supplied modules root" {
        Remove-Module InterfaceCommon -Force -ErrorAction SilentlyContinue

        $modulesRoot = Join-Path $TestDrive 'ModulesRoot'
        New-Item -ItemType Directory -Path $modulesRoot -Force | Out-Null
        $stubPath = Join-Path $modulesRoot 'InterfaceCommon.psm1'
        @"
function Get-InterfaceCommonStub { 'stub' }
Export-ModuleMember -Function Get-InterfaceCommonStub
"@ | Set-Content -Path $stubPath -Encoding ASCII

        TelemetryModule\Import-InterfaceCommon -ModulesRoot $modulesRoot | Should Be $true
        $cmd = Get-Command -Name 'InterfaceCommon\Get-InterfaceCommonStub' -ErrorAction Stop
        $cmd | Should Not BeNullOrEmpty

        Remove-Module InterfaceCommon -Force -ErrorAction SilentlyContinue
    }

    It "writes a single-line JSON event" {
        $payload = @{ Foo = "Bar"; Number = 42 }
        TelemetryModule\Write-StTelemetryEvent -Name 'UnitTestEvent' -Payload $payload
        $path = TelemetryModule\Get-TelemetryLogPath
        (Test-Path $path) | Should Be True
        $last = Get-Content -LiteralPath $path -Tail 1
        $obj = $last | ConvertFrom-Json
        $obj.EventName | Should Be 'UnitTestEvent'
        $obj.Foo | Should Be 'Bar'
        $obj.Number | Should Be 42
    }

    # LANDMARK: Telemetry buffer rename - approved verb + legacy alias coverage
    It "exposes Save-StTelemetryBuffer and legacy alias" {
        $cmd = Get-Command -Name 'Save-StTelemetryBuffer' -Module TelemetryModule -ErrorAction Stop
        $cmd.CommandType | Should Be 'Function'

        $legacy = Get-Command -Name 'Flush-StTelemetryBuffer' -ErrorAction Stop
        $legacy.CommandType | Should Be 'Alias'
        $legacy.Definition | Should Be 'Save-StTelemetryBuffer'
    }

    It "returns a path for legacy alias invocation" {
        $target = Join-Path $testOut 'telemetry-buffer.json'
        $newPath = TelemetryModule\Save-StTelemetryBuffer -Path $target
        $legacyPath = Flush-StTelemetryBuffer -Path $target

        $newPath | Should Be $target
        $legacyPath | Should Be $target
    }

    It "writes span debug entries to custom and temp paths" {
        $customPath = Join-Path $TestDrive 'span.log'
        if (Test-Path -LiteralPath $customPath) { Remove-Item -LiteralPath $customPath -Force }

        TelemetryModule\Write-SpanDebugLog -Message 'custom message' -Path $customPath -Prefix 'Diag'
        (Test-Path -LiteralPath $customPath) | Should Be True
        (Get-Content -LiteralPath $customPath -Tail 1) | Should Match 'Diag custom message'

        $tempPath = Join-Path ([System.IO.Path]::GetTempPath()) 'StateTrace_SpanDebug.log'
        if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue }

        TelemetryModule\Write-SpanDebugLog -Message 'temp message' -UseTemp
        (Test-Path -LiteralPath $tempPath) | Should Be True
        (Get-Content -LiteralPath $tempPath -Tail 1) | Should Match 'temp message'

        Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
    }
}
