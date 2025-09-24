Set-StrictMode -Version Latest

Describe "DeviceCatalogModule catalog operations" {
    BeforeAll {
        $moduleRoot = Split-Path $PSCommandPath
        Import-Module (Resolve-Path (Join-Path $moduleRoot "..\DeviceCatalogModule.psm1")) -Force
        Import-Module (Resolve-Path (Join-Path $moduleRoot "..\DeviceRepositoryModule.psm1")) -Force
        Import-Module (Resolve-Path (Join-Path $moduleRoot "..\DatabaseModule.psm1")) -Force

        if (Get-Variable -Name DeviceMetadata -Scope Global -ErrorAction SilentlyContinue) {
            $script:PrevDeviceMetadata = $global:DeviceMetadata
        } else {
            $script:PrevDeviceMetadata = $null
        }
    }

    AfterAll {
        if ($script:PrevDeviceMetadata -ne $null) {
            $global:DeviceMetadata = $script:PrevDeviceMetadata
        } else {
            Remove-Variable -Name DeviceMetadata -Scope Global -ErrorAction SilentlyContinue
        }
        Remove-Module DeviceCatalogModule -Force
        Remove-Module DeviceRepositoryModule -Force
        Remove-Module DatabaseModule -Force
    }

    BeforeEach {
        $global:DeviceMetadata = @{}
    }

    It "aggregates device summaries from all site databases" {
        Mock -ModuleName DeviceCatalogModule -CommandName 'DeviceRepositoryModule\Get-AllSiteDbPaths' { @('C:\data\site1.accdb', 'C:\data\site2.accdb') }
        Mock -ModuleName DeviceCatalogModule -CommandName Test-Path { param($Path, $LiteralPath) $true }
        Mock -ModuleName DeviceCatalogModule -CommandName 'DeviceRepositoryModule\Import-DatabaseModule' {}
        Mock -ModuleName DeviceCatalogModule -CommandName 'DatabaseModule\Invoke-DbQuery' {
            param($DatabasePath, $Sql)
            if ($DatabasePath -like '*site1.accdb') {
                return @(
                    [pscustomobject]@{ Hostname = 'SITE1-Z1-SW1'; Site = 'SITE1'; Building = 'B1'; Room = '101' },
                    [pscustomobject]@{ Hostname = 'SITE1-Z1-SW2'; Site = 'SITE1'; Building = 'B1'; Room = '102' }
                )
            }
            if ($DatabasePath -like '*site2.accdb') {
                return @(
                    [pscustomobject]@{ Hostname = 'SITE2-Z3-EDGE'; Site = 'SITE2'; Building = 'B2'; Room = '201' },
                    [pscustomobject]@{ Hostname = 'SITE1-Z1-SW1'; Site = 'SITE1'; Building = 'B1'; Room = '101' }
                )
            }
            return @()
        }

        $result = DeviceCatalogModule\Get-DeviceSummaries

        @($result.Hostnames).Count | Should Be 3
        ($result.Hostnames -contains 'SITE1-Z1-SW1') | Should Be $true
        ($result.Hostnames -contains 'SITE2-Z3-EDGE') | Should Be $true
        $global:DeviceMetadata.ContainsKey('SITE1-Z1-SW1') | Should Be $true
        $global:DeviceMetadata['SITE2-Z3-EDGE'].Building | Should Be 'B2'
        $global:DeviceMetadata['SITE1-Z1-SW2'].Zone | Should Be 'Z1'
    }

    It "returns hostnames filtered by the requested location" {
        $global:DeviceMetadata = @{
            'SITE1-Z1-SW1' = [pscustomobject]@{ Site = 'SITE1'; Zone = 'Z1'; Building = 'B1'; Room = '101' }
            'SITE1-Z2-SW2' = [pscustomobject]@{ Site = 'SITE1'; Zone = 'Z2'; Building = 'B1'; Room = '201' }
            'SITE2-Z1-SW3' = [pscustomobject]@{ Site = 'SITE2'; Zone = 'Z1'; Building = 'B2'; Room = '301' }
        }

        $allSite = @(DeviceCatalogModule\Get-InterfaceHostnames -Site 'SITE1' -Zone 'All Zones' -Building 'All Buildings' -Room 'All Rooms')
        $allSite.Count | Should Be 2
        ($allSite -contains 'SITE1-Z1-SW1') | Should Be $true
        ($allSite -contains 'SITE1-Z2-SW2') | Should Be $true

        $zoneFiltered = @(DeviceCatalogModule\Get-InterfaceHostnames -Site 'SITE1' -Zone 'Z1')
        $zoneFiltered.Count | Should Be 1
        $zoneFiltered[0] | Should Be 'SITE1-Z1-SW1'

        $global:DeviceMetadata = @{}
        Mock -ModuleName DeviceCatalogModule -CommandName Get-DeviceSummaries {
            $global:DeviceMetadata = @{
                'SITE3-Z5-SW9' = [pscustomobject]@{ Site = 'SITE3'; Zone = 'Z5'; Building = 'B9'; Room = '909' }
            }
            [pscustomobject]@{ Hostnames = @('SITE3-Z5-SW9'); Metadata = $global:DeviceMetadata }
        }

        $auto = @(DeviceCatalogModule\Get-InterfaceHostnames -Site 'SITE3')
        $auto.Count | Should Be 1
        $auto[0] | Should Be 'SITE3-Z5-SW9'
    }
}
