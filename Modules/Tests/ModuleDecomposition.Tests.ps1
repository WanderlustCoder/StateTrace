Set-StrictMode -Version Latest

Describe "Module decomposition shims" -Tag 'Decomposition' {
    Context "DeviceRepository.Cache exports" {
        BeforeAll {
            $modulePath = Join-Path (Split-Path $PSCommandPath) "..\DeviceRepository.Cache.psm1"
            Import-Module (Resolve-Path $modulePath) -Force
        }

        It "exports cache helpers" {
            $module = Get-Module -Name 'DeviceRepository.Cache'
            $module | Should Not BeNullOrEmpty
            ($module.ExportedFunctions.Count) -gt 0 | Should Be $true
        }
    }

    Context "ParserPersistence decomposition exports" {
        BeforeAll {
            $corePath = Join-Path (Split-Path $PSCommandPath) "..\ParserPersistence.Core.psm1"
            $diffPath = Join-Path (Split-Path $PSCommandPath) "..\ParserPersistence.Diff.psm1"
            $warmPath = Join-Path (Split-Path $PSCommandPath) "..\WarmRun.Telemetry.psm1"
            Import-Module (Resolve-Path $corePath) -Force
            Import-Module (Resolve-Path $diffPath) -Force
            Import-Module (Resolve-Path $warmPath) -Force
        }

        It "exports core persistence helpers" {
            $module = Get-Module -Name 'ParserPersistence.Core'
            $module | Should Not BeNullOrEmpty
            ($module.ExportedFunctions.Count) -gt 0 | Should Be $true
        }

        It "imports diff module" {
            Get-Module -Name 'ParserPersistence.Diff' | Should Not BeNullOrEmpty
        }

        It "imports warm-run telemetry module" {
            Get-Module -Name 'WarmRun.Telemetry' | Should Not BeNullOrEmpty
        }
    }
}
