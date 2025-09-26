Set-StrictMode -Version Latest

Describe "ParserPersistenceModule" {
    BeforeAll {
        $modulePath = Join-Path (Split-Path $PSCommandPath) "..\\ParserPersistenceModule.psm1"
        Import-Module (Resolve-Path $modulePath) -Force
    }

    AfterAll {
        Remove-Module ParserPersistenceModule -Force
    }

    It "exports persistence helpers" {
        Get-Command -Module ParserPersistenceModule -Name Update-DeviceSummaryInDb | Should Not BeNullOrEmpty
        Get-Command -Module ParserPersistenceModule -Name Update-InterfacesInDb | Should Not BeNullOrEmpty
    }
}

