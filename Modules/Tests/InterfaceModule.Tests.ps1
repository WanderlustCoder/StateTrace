Set-StrictMode -Version Latest

Describe "InterfaceModule Get-InterfaceList" {
    BeforeAll {
        $modulePath = Join-Path (Split-Path $PSCommandPath) "..\InterfaceModule.psm1"
        Import-Module (Resolve-Path $modulePath).Path -Force

        $dbModulePath = Join-Path (Split-Path $PSCommandPath) "..\DatabaseModule.psm1"
        Import-Module (Resolve-Path $dbModulePath).Path -Force

        $repoPath = Join-Path (Split-Path $PSCommandPath) "..\DeviceRepositoryModule.psm1"
        Import-Module (Resolve-Path $repoPath).Path -Force

        $viewStatePath = Join-Path (Split-Path $PSCommandPath) "..\ViewStateService.psm1"
        Import-Module (Resolve-Path $viewStatePath).Path -Force

        if (Get-Variable -Name DeviceInterfaceCache -Scope Global -ErrorAction SilentlyContinue) {
            $script:PrevInterfaceCache = $global:DeviceInterfaceCache
        } else {
            $script:PrevInterfaceCache = $null
        }

        if (Get-Variable -Name StateTraceDb -Scope Global -ErrorAction SilentlyContinue) {
            $script:PrevDbPath = $global:StateTraceDb
        } else {
            $script:PrevDbPath = $null
        }

        if (Get-Variable -Name DeviceMetadata -Scope Global -ErrorAction SilentlyContinue) {
            $script:PrevDeviceMetadata = $global:DeviceMetadata
        } else {
            $script:PrevDeviceMetadata = $null
        }
    }

    AfterAll {
        if ($script:PrevInterfaceCache -ne $null) {
            $global:DeviceInterfaceCache = $script:PrevInterfaceCache
        } else {
            Remove-Variable -Name DeviceInterfaceCache -Scope Global -ErrorAction SilentlyContinue
        }

        if ($script:PrevDbPath -ne $null) {
            $global:StateTraceDb = $script:PrevDbPath
        } else {
            Remove-Variable -Name StateTraceDb -Scope Global -ErrorAction SilentlyContinue
        }

        if ($script:PrevDeviceMetadata -ne $null) {
            $global:DeviceMetadata = $script:PrevDeviceMetadata
        } else {
            Remove-Variable -Name DeviceMetadata -Scope Global -ErrorAction SilentlyContinue
        }

        Remove-Module InterfaceModule -Force
        Remove-Module DatabaseModule -Force
        Remove-Module ViewStateService -Force
    }

    BeforeEach {
        $global:DeviceInterfaceCache = @{}
        $global:StateTraceDb = 'C:\\Temp\\StateTrace.accdb'
        $global:DeviceMetadata = @{
            'sw1' = [pscustomobject]@{ Site = 'SITE1'; Zone = 'Z1'; Building = 'B1'; Room = 'R101' }
            'sw2' = [pscustomobject]@{ Site = 'SITE2'; Zone = 'Z2'; Building = 'B2'; Room = 'R201' }
        }
    }

    It "returns ports from ViewStateService when data is available" {
        Mock -ModuleName InterfaceModule -CommandName 'ViewStateService\Get-InterfacesForContext' {
            @(
                [pscustomobject]@{ Hostname = 'sw1'; Port = 'Gi0/2' },
                [pscustomobject]@{ Hostname = 'sw1'; Port = 'Gi0/1' },
                [pscustomobject]@{ Hostname = 'sw2'; Port = 'Gi0/3' }
            )
        }

        Mock -ModuleName InterfaceModule -CommandName Ensure-DatabaseModule {}
        Mock -ModuleName InterfaceModule -CommandName Invoke-DbQuery { throw 'Invoke-DbQuery should not be called when ViewStateService returns ports.' }

        $result = InterfaceModule\Get-InterfaceList -Hostname 'sw1'

        $result | Should BeExactly @('Gi0/1', 'Gi0/2')
        Assert-MockCalled 'ViewStateService\Get-InterfacesForContext' -ModuleName InterfaceModule -Times 1
        Assert-MockCalled Invoke-DbQuery -ModuleName InterfaceModule -Times 0
    }

    It "uses cached ports when service returns no interfaces" {
        $list = [System.Collections.Generic.List[object]]::new()
        [void]$list.Add([pscustomobject]@{ Port = 'Gi1/0/1' })
        $global:DeviceInterfaceCache['sw1'] = $list

        Mock -ModuleName InterfaceModule -CommandName 'ViewStateService\Get-InterfacesForContext' { @() }
        Mock -ModuleName InterfaceModule -CommandName Ensure-DatabaseModule {}
        Mock -ModuleName InterfaceModule -CommandName Invoke-DbQuery { throw 'Invoke-DbQuery should not be called when cache provides data.' }

        $result = InterfaceModule\Get-InterfaceList -Hostname 'sw1'

        $result | Should BeExactly @('Gi1/0/1')
        Assert-MockCalled 'ViewStateService\Get-InterfacesForContext' -ModuleName InterfaceModule -Times 1
        Assert-MockCalled Invoke-DbQuery -ModuleName InterfaceModule -Times 0
    }

    It "queries the database when service and cache are empty" {
        $global:DeviceInterfaceCache.Clear()

        Mock -ModuleName InterfaceModule -CommandName 'ViewStateService\Get-InterfacesForContext' { @() }
        Mock -ModuleName InterfaceModule -CommandName Ensure-DatabaseModule {}
        Mock -ModuleName InterfaceModule -CommandName Invoke-DbQuery {
            param([string]$DatabasePath, [string]$Sql)
            @(
                [pscustomobject]@{ Port = 'Fa0/1' },
                [pscustomobject]@{ Port = 'Fa0/2' }
            )
        }

        $result = InterfaceModule\Get-InterfaceList -Hostname 'sw2'

        $result | Should BeExactly @('Fa0/1', 'Fa0/2')
        Assert-MockCalled 'ViewStateService\Get-InterfacesForContext' -ModuleName InterfaceModule -Times 1
        Assert-MockCalled Ensure-DatabaseModule -ModuleName InterfaceModule -Times 1
        Assert-MockCalled Invoke-DbQuery -ModuleName InterfaceModule -Times 1 -ParameterFilter { $Sql -like "*Hostname = 'sw2'*" }
    }

    Context "Get-SpanningTreeInfo" {
        It "returns empty when hostname is blank" {
            Mock -ModuleName InterfaceModule -CommandName 'DeviceRepositoryModule\Get-SpanningTreeInfo' { @() }

            $result = InterfaceModule\Get-SpanningTreeInfo -Hostname ''

            @($result).Count | Should Be 0
            Assert-MockCalled 'DeviceRepositoryModule\Get-SpanningTreeInfo' -ModuleName InterfaceModule -Times 0
        }

        It "delegates to DeviceRepositoryModule" {
            Mock -ModuleName InterfaceModule -CommandName 'DeviceRepositoryModule\Get-SpanningTreeInfo' {
                param([string]$Hostname)
                @([pscustomobject]@{ VLAN = 'VLAN0010'; RootPort = 'Gi1/0/48' })
            }

            $result = InterfaceModule\Get-SpanningTreeInfo -Hostname 'SW1'

            $rows = @($result)
            $rows.Count | Should Be 1
            $rows[0].VLAN | Should Be 'VLAN0010'
            Assert-MockCalled 'DeviceRepositoryModule\Get-SpanningTreeInfo' -ModuleName InterfaceModule -Times 1 -ParameterFilter { $Hostname -eq 'SW1' }
        }
    }

    Context "Get-PortSortKey normalization" {
        It "normalizes prefixes and pads numeric segments" {
            $cases = @(
                @{ Port = 'GigabitEthernet1/0/2'; Expected = '40-GI-00001-00000-00002-00000' },
                @{ Port = 'Hundred GigabitEthernet 1/1'; Expected = '23-HU-00001-00001-00000-00000' },
                @{ Port = 'Loopback10'; Expected = '98-LO-00010-00000-00000-00000' },
                @{ Port = '1/1/1'; Expected = '30-ET-00001-00001-00001-00000' }
            )

            foreach ($case in $cases) {
                InterfaceModule\Get-PortSortKey -Port $case.Port | Should Be $case.Expected
            }
        }
    }

    Context "Get-PortSortKey caching" {
        It "caches normalized port keys and reports stats" {
            $statsBefore = InterfaceModule\Get-PortSortCacheStatistics
            $statsBefore | Should Not BeNullOrEmpty

            $uniquePort = "GiCache-{0}" -f ([guid]::NewGuid().ToString('N'))
            $first = InterfaceModule\Get-PortSortKey -Port ("  {0}  " -f $uniquePort)
            $second = InterfaceModule\Get-PortSortKey -Port $uniquePort.ToLowerInvariant()

            $first | Should Be $second

            $statsAfter = InterfaceModule\Get-PortSortCacheStatistics
            $statsAfter | Should Not BeNullOrEmpty

            $hitDelta = [long]$statsAfter.Hits - [long]$statsBefore.Hits
            $missDelta = [long]$statsAfter.Misses - [long]$statsBefore.Misses
            $entryDelta = [long]$statsAfter.EntryCount - [long]$statsBefore.EntryCount

            $missDelta | Should Be 1
            $hitDelta | Should Be 1
            $entryDelta | Should Be 1
        }
    }
}
