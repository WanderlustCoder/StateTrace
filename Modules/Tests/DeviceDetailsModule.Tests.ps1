Set-StrictMode -Version Latest

Describe "DeviceDetailsModule detail retrieval" {
    BeforeAll {
        $moduleRoot = Split-Path $PSCommandPath
        Import-Module (Resolve-Path (Join-Path $moduleRoot "..\DeviceDetailsModule.psm1")) -Force
        Import-Module (Resolve-Path (Join-Path $moduleRoot "..\DeviceRepositoryModule.psm1")) -Force
        Import-Module (Resolve-Path (Join-Path $moduleRoot "..\TemplatesModule.psm1")) -Force
    }

    AfterAll {
        Remove-Module DeviceDetailsModule -Force
        Remove-Module DeviceRepositoryModule -Force
        Remove-Module TemplatesModule -Force
    }

    It "returns null when no hostname is provided" {
        DeviceDetailsModule\Get-DeviceDetails -Hostname '' | Should Be $null
        DeviceDetailsModule\Get-DeviceDetails -Hostname '   ' | Should Be $null
    }

    It "uses CSV fallbacks when the database file is missing" {
        Mock -ModuleName DeviceDetailsModule -CommandName 'DeviceRepositoryModule\Get-DbPathForHost' { 'C:\data\missing.accdb' }
        Mock -ModuleName DeviceDetailsModule -CommandName Test-Path { param($Path, $LiteralPath) $false }
        Mock -ModuleName DeviceDetailsModule -CommandName Get-CsvDeviceSummary { [pscustomobject]@{ Hostname = 'SW1'; Make = 'CSV' } }
        Mock -ModuleName DeviceDetailsModule -CommandName Get-CsvInterfaces { @([pscustomobject]@{ Port = 'Gi1/0/1' }) }
        Mock -ModuleName DeviceDetailsModule -CommandName 'DeviceRepositoryModule\Get-InterfaceInfo' { throw 'Should not query repository when CSV paths are used.' }

        $dto = DeviceDetailsModule\Get-DeviceDetailsData -Hostname 'sw1'

        $dto.Summary.Make | Should Be 'CSV'
        @($dto.Interfaces).Count | Should Be 1
        $dto.Interfaces[0].Port | Should Be 'Gi1/0/1'
        (@($dto.Templates).Count) | Should Be 0
    }

    It "loads database-backed details when the site database exists" {
        Mock -ModuleName DeviceDetailsModule -CommandName 'DeviceRepositoryModule\Get-DbPathForHost' { 'C:\data\site.accdb' }
        Mock -ModuleName DeviceDetailsModule -CommandName Test-Path { param($Path, $LiteralPath) if ($Path -or $LiteralPath) { $true } else { $false } }
        Mock -ModuleName DeviceDetailsModule -CommandName Get-DatabaseDeviceSummary { [pscustomobject]@{ Hostname = 'SW2'; Make = 'Cisco' } }
        Mock -ModuleName DeviceDetailsModule -CommandName 'DeviceRepositoryModule\Get-InterfaceInfo' {
            param([string]$Hostname, [string]$TemplatesPath)
            @([pscustomobject]@{ Hostname = $Hostname; Port = 'Gi1/0/2' })
        }
        Mock -ModuleName DeviceDetailsModule -CommandName 'TemplatesModule\Get-ConfigurationTemplates' {
            param([string]$Hostname, [string]$DatabasePath, [string]$TemplatesPath)
            @([pscustomobject]@{ Name = 'Default' })
        }

        $dto = DeviceDetailsModule\Get-DeviceDetailsData -Hostname 'sw2'

        $dto.Summary.Hostname | Should Be 'SW2'
        @($dto.Interfaces).Count | Should Be 1
        $dto.Interfaces[0].Port | Should Be 'Gi1/0/2'
        @($dto.Templates).Count | Should Be 1
        $dto.Templates[0].Name | Should Be 'Default'
        Assert-MockCalled 'DeviceRepositoryModule\Get-InterfaceInfo' -ModuleName DeviceDetailsModule -Times 1 -ParameterFilter { $Hostname -eq 'sw2' }
        Assert-MockCalled 'TemplatesModule\Get-ConfigurationTemplates' -ModuleName DeviceDetailsModule -Times 1
    }
}
