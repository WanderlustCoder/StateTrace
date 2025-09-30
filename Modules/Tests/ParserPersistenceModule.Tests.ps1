Set-StrictMode -Version Latest

Describe "ParserPersistenceModule" {
    BeforeAll {
        $modulePath = Join-Path (Split-Path $PSCommandPath) "..\ParserPersistenceModule.psm1"
        Import-Module (Resolve-Path $modulePath) -Force
    }

    AfterAll {
        Remove-Module ParserPersistenceModule -Force
    }

    function New-TestRecordset {
        param([object[]]$Rows)

        $rowList = New-Object "System.Collections.Generic.List[hashtable]"
        if ($Rows) {
            foreach ($row in $Rows) { $rowList.Add([hashtable]$row) | Out-Null }
        }

        $rs = New-Object PSObject
        Add-Member -InputObject $rs -MemberType NoteProperty -Name Rows -Value $rowList
        Add-Member -InputObject $rs -MemberType NoteProperty -Name Index -Value 0
        $stateValue = 0
        if ($rowList.Count -gt 0) { $stateValue = 1 }
        Add-Member -InputObject $rs -MemberType NoteProperty -Name State -Value $stateValue
        Add-Member -InputObject $rs -MemberType ScriptProperty -Name EOF -Value { $this.Index -ge $this.Rows.Count }
        Add-Member -InputObject $rs -MemberType ScriptMethod -Name MoveNext -Value { if ($this.Index -lt $this.Rows.Count) { $this.Index++ } }
        Add-Member -InputObject $rs -MemberType ScriptMethod -Name Close -Value { $this.State = 0 }

        $fields = New-Object PSObject
        Add-Member -InputObject $fields -MemberType NoteProperty -Name Parent -Value $rs
        Add-Member -InputObject $fields -MemberType ScriptMethod -Name Item -Value {
            param($name)
            $parent = $this.Parent
            if ($parent.Index -ge $parent.Rows.Count) { return [pscustomobject]@{ Value = $null } }
            $row = $parent.Rows[$parent.Index]
            $value = $null
            if ($row.ContainsKey($name)) { $value = $row[$name] }
            return [pscustomobject]@{ Value = $value }
        }
        Add-Member -InputObject $rs -MemberType NoteProperty -Name Fields -Value $fields
        return $rs
    }

    It "exports persistence helpers" {
        Get-Command -Module ParserPersistenceModule -Name Update-DeviceSummaryInDb | Should Not BeNullOrEmpty
        Get-Command -Module ParserPersistenceModule -Name Update-InterfacesInDb | Should Not BeNullOrEmpty
        Get-Command -Module ParserPersistenceModule -Name Update-SpanInfoInDb | Should Not BeNullOrEmpty
    }

    It "persists span info records" {
        $commands = New-Object "System.Collections.Generic.List[string]"
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
        $commands = New-Object "System.Collections.Generic.List[string]"
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

    It "inserts interfaces when none exist" {
        $commands = New-Object "System.Collections.Generic.List[string]"
        Set-Variable -Name commands -Scope Script -Value $commands
        $recordsets = New-Object "System.Collections.Generic.Queue[object]"
        $recordsets.Enqueue((New-TestRecordset @()))
        Set-Variable -Name recordsets -Scope Script -Value $recordsets

        $connection = New-Object PSObject
        Add-Member -InputObject $connection -MemberType ScriptMethod -Name Execute -Value {
            param($Sql)
            if ($Sql -like "SELECT Port,*FROM Interfaces*") {
                if ($script:recordsets.Count -gt 0) { return $script:recordsets.Dequeue() }
                return $null
            }
            [void]$script:commands.Add($Sql)
            return $null
        }

        $facts = [pscustomobject]@{
            Interfaces = @(
                [pscustomobject]@{
                    Port = '1/1'
                    Name = 'Gi1/1'
                    Status = 'up'
                    VLAN = '10'
                    Duplex = 'full'
                    Speed = '1G'
                    Type = 'access'
                    LearnedMACs = @('AA-BB-CC-00-11-22')
                    AuthState = 'authorized'
                    AuthMode = 'dot1x'
                    AuthClientMAC = 'AA-BB-CC-00-11-22'
                    AuthTemplate = 'Default'
                    Config = 'interface config'
                }
            )
            Make = 'Cisco'
        }

        ParserPersistenceModule\Update-InterfacesInDb -Connection $connection -Facts $facts -Hostname 'SW1' -RunDateString '2025-09-28 12:00:00'

        $commands.Count | Should Be 2
        $commands[0] | Should Match "INSERT INTO Interfaces"
        $commands[1] | Should Match "INSERT INTO InterfaceHistory"

        Remove-Variable -Name commands -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name recordsets -Scope Script -ErrorAction SilentlyContinue
    }

    It "updates existing interfaces when values change" {
        $commands = New-Object "System.Collections.Generic.List[string]"
        Set-Variable -Name commands -Scope Script -Value $commands
        $recordsets = New-Object "System.Collections.Generic.Queue[object]"
        $recordsets.Enqueue((New-TestRecordset @([ordered]@{
            Port = '1/1'
            Name = 'Gi1/1'
            Status = 'down'
            VLAN = '10'
            Duplex = 'half'
            Speed = '1G'
            Type = 'access'
            LearnedMACs = 'AA-BB-CC-00-11-22'
            AuthState = 'unauthorized'
            AuthMode = 'mab'
            AuthClientMAC = 'AA-BB-CC-00-11-22'
            AuthTemplate = 'Default'
            Config = 'old config'
            PortColor = 'Gray'
            ConfigStatus = 'Mismatch'
            ToolTip = 'Old'
        })))
        Set-Variable -Name recordsets -Scope Script -Value $recordsets

        $connection = New-Object PSObject
        Add-Member -InputObject $connection -MemberType ScriptMethod -Name Execute -Value {
            param($Sql)
            if ($Sql -like "SELECT Port,*FROM Interfaces*") {
                if ($script:recordsets.Count -gt 0) { return $script:recordsets.Dequeue() }
                return $null
            }
            [void]$script:commands.Add($Sql)
            return $null
        }

        $facts = [pscustomobject]@{
            Interfaces = @(
                [pscustomobject]@{
                    Port = '1/1'
                    Name = 'Gi1/1'
                    Status = 'up'
                    VLAN = '10'
                    Duplex = 'full'
                    Speed = '1G'
                    Type = 'access'
                    LearnedMACs = 'AA-BB-CC-00-11-22'
                    AuthState = 'authorized'
                    AuthMode = 'dot1x'
                    AuthClientMAC = 'AA-BB-CC-00-11-22'
                    AuthTemplate = 'Default'
                    Config = 'new config'
                }
            )
            Make = 'Cisco'
        }

        ParserPersistenceModule\Update-InterfacesInDb -Connection $connection -Facts $facts -Hostname 'SW1' -RunDateString '2025-09-28 12:05:00'

        $commands.Count | Should Be 3
        $commands[0] | Should Match "DELETE FROM Interfaces"
        $commands[1] | Should Match "INSERT INTO Interfaces"
        $commands[2] | Should Match "INSERT INTO InterfaceHistory"

        Remove-Variable -Name commands -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name recordsets -Scope Script -ErrorAction SilentlyContinue
    }

    It "deletes interfaces missing from the latest facts" {
        $commands = New-Object "System.Collections.Generic.List[string]"
        Set-Variable -Name commands -Scope Script -Value $commands
        $recordsets = New-Object "System.Collections.Generic.Queue[object]"
        $recordsets.Enqueue((New-TestRecordset @([ordered]@{
            Port = '1/1'
            Name = 'Gi1/1'
            Status = 'up'
            VLAN = '10'
            Duplex = 'full'
            Speed = '1G'
            Type = 'access'
            LearnedMACs = 'AA-BB-CC-00-11-22'
            AuthState = 'authorized'
            AuthMode = 'dot1x'
            AuthClientMAC = 'AA-BB-CC-00-11-22'
            AuthTemplate = 'Default'
            Config = 'config'
            PortColor = 'Green'
            ConfigStatus = 'Match'
            ToolTip = 'tip'
        })))
        Set-Variable -Name recordsets -Scope Script -Value $recordsets

        $connection = New-Object PSObject
        Add-Member -InputObject $connection -MemberType ScriptMethod -Name Execute -Value {
            param($Sql)
            if ($Sql -like "SELECT Port,*FROM Interfaces*") {
                if ($script:recordsets.Count -gt 0) { return $script:recordsets.Dequeue() }
                return $null
            }
            [void]$script:commands.Add($Sql)
            return $null
        }

        $facts = [pscustomobject]@{
            Interfaces = @()
            Make = 'Cisco'
        }

        ParserPersistenceModule\Update-InterfacesInDb -Connection $connection -Facts $facts -Hostname 'SW1' -RunDateString '2025-09-28 12:10:00'

        $commands.Count | Should Be 1
        $commands[0] | Should Match "DELETE FROM Interfaces"

        Remove-Variable -Name commands -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name recordsets -Scope Script -ErrorAction SilentlyContinue
    }

    It "detects ADODB connections via type name" {
        InModuleScope -ModuleName ParserPersistenceModule {
            $conn = New-Object PSObject
            $conn.PSObject.TypeNames.Insert(0, 'ADODB.Connection')
            (Test-IsAdodbConnection -Connection $conn) | Should Be $true
            (Test-IsAdodbConnection -Connection ([pscustomobject]@{})) | Should Be $false
        }
    }

    It "converts run date strings to DateTime when possible" {
        InModuleScope -ModuleName ParserPersistenceModule {
            $result = ConvertTo-DbDateTime -RunDateString '2025-09-30 12:34:56'
            $result.GetType().FullName | Should Be "System.DateTime"
            (ConvertTo-DbDateTime -RunDateString '') | Should Be $null
        }
    }


}
