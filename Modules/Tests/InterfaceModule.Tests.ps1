Set-StrictMode -Version Latest

Describe "InterfaceModule Get-InterfaceList" {
    BeforeAll {
        $modulePath = Join-Path (Split-Path $PSCommandPath) "..\InterfaceModule.psm1"
        $resolved = (Resolve-Path $modulePath).Path
        Import-Module $resolved -Force

        $dbModulePath = Join-Path (Split-Path $PSCommandPath) "..\DatabaseModule.psm1"
        $dbResolved = (Resolve-Path $dbModulePath).Path
        Import-Module $dbResolved -Force

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
        Remove-Module InterfaceModule -Force
        Remove-Module DatabaseModule -Force
    }

    BeforeEach {
        $global:DeviceInterfaceCache = @{}
        $global:StateTraceDb = 'C:\\Temp\\StateTrace.accdb'
    }

    It "returns cached ports without querying the database" {
        $list = [System.Collections.Generic.List[object]]::new()
        [void]$list.Add([PSCustomObject]@{ Port = 'Gi1/0/1' })
        $global:DeviceInterfaceCache['sw1'] = $list

        Mock -ModuleName InterfaceModule -CommandName Ensure-DatabaseModule {}
        Mock -ModuleName InterfaceModule -CommandName Invoke-DbQuery { throw 'Invoke-DbQuery should not be called for cached hosts.' }

        $result = InterfaceModule\Get-InterfaceList -Hostname 'sw1'

        $result | Should BeExactly @('Gi1/0/1')
        Assert-MockCalled Invoke-DbQuery -ModuleName InterfaceModule -Times 0
    }

    It "queries the aggregated database when no cached data exists" {
        $global:DeviceInterfaceCache.Clear()

        Mock -ModuleName InterfaceModule -CommandName Ensure-DatabaseModule {}
        Mock -ModuleName InterfaceModule -CommandName Invoke-DbQuery {
            param([string]$DatabasePath, [string]$Sql)
            @(
                [PSCustomObject]@{ Port = 'Fa0/1' },
                [PSCustomObject]@{ Port = 'Fa0/2' }
            )
        }

        $result = InterfaceModule\Get-InterfaceList -Hostname "sw2"

        $result | Should BeExactly @('Fa0/1', 'Fa0/2')
        Assert-MockCalled Ensure-DatabaseModule -ModuleName InterfaceModule -Times 1
        Assert-MockCalled Invoke-DbQuery -ModuleName InterfaceModule -Times 1 -ParameterFilter { $Sql -like "*Hostname = 'sw2'*" }
    }
}
