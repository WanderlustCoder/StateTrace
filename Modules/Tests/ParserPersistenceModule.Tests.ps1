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
        Get-Command -Module ParserPersistenceModule -Name Update-SpanInfoInDb | Should Not BeNullOrEmpty
    }

    It "persists span info records" {
        $commands = New-Object 'System.Collections.Generic.List[string]'
        Set-Variable -Name commands -Scope Script -Value $commands
        $connection = New-Object PSObject
        Add-Member -InputObject $connection -MemberType ScriptMethod -Name Execute -Value {
            param($Sql)
            [void]$script:commands.Add($Sql)
        }

        $records = @(
            [pscustomobject]@{ VLAN = 'VLAN0010'; RootSwitch = '5254.001b.1c58'; RootPort = 'Gi1/0/48'; Role = 'Root'; Upstream = 'Gi1/0/48' },
            [pscustomobject]@{ VLAN = 'VLAN0010'; RootSwitch = '5254.001b.1c58'; RootPort = 'Gi1/0/48'; Role = 'Desg'; Upstream = 'Gi1/0/1' }
        )

        ParserPersistenceModule\Update-SpanInfoInDb -Connection $connection -Hostname 'SW1' -RunDateString '2024-09-01 10:00:00' -SpanInfo $records

        $commands.Count | Should Be 5
        $commands[0] | Should Match "DELETE FROM SpanInfo WHERE Hostname = 'SW1'"
        ($commands | Where-Object { $_ -like 'INSERT INTO SpanInfo*' }).Count | Should Be 2
        ($commands | Where-Object { $_ -like 'INSERT INTO SpanHistory*' }).Count | Should Be 2

        Remove-Variable -Name commands -Scope Script -ErrorAction SilentlyContinue
    }

    It "clears span info when no records remain" {
        $commands = New-Object 'System.Collections.Generic.List[string]'
        Set-Variable -Name commands -Scope Script -Value $commands
        $connection = New-Object PSObject
        Add-Member -InputObject $connection -MemberType ScriptMethod -Name Execute -Value {
            param($Sql)
            [void]$script:commands.Add($Sql)
        }

        ParserPersistenceModule\Update-SpanInfoInDb -Connection $connection -Hostname 'SW2' -RunDateString '2024-09-01 10:00:00'

        $commands.Count | Should Be 1
        $commands[0] | Should Match "DELETE FROM SpanInfo"

        Remove-Variable -Name commands -Scope Script -ErrorAction SilentlyContinue
    }
}

