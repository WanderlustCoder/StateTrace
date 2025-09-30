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
}
