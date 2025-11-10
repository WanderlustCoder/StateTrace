Set-StrictMode -Version Latest



Describe "ParserPersistenceModule" {

    BeforeAll {

        $moduleDirectory = Split-Path $PSCommandPath
        $modulePath = Join-Path $moduleDirectory "..\ParserPersistenceModule.psm1"
        Import-Module (Resolve-Path $modulePath) -Force

        $deviceRepoPath = Join-Path $moduleDirectory "..\DeviceRepositoryModule.psm1"
        Import-Module (Resolve-Path $deviceRepoPath) -Force

        $telemetryPath = Join-Path $moduleDirectory "..\TelemetryModule.psm1"
        Import-Module (Resolve-Path $telemetryPath) -Force

    }

    BeforeEach {
        try { DeviceRepositoryModule\Clear-SiteInterfaceCache } catch { }
        try { ParserPersistenceModule\Clear-SiteExistingRowCache } catch { }
    }



    AfterAll { }



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



    It "reuses shared cache entry when initial site cache lookup misses" {

        $commands = New-Object "System.Collections.Generic.List[string]"
        Set-Variable -Name commands -Scope Script -Value $commands

        $connection = New-Object PSObject
        Add-Member -InputObject $connection -MemberType ScriptMethod -Name Execute -Value {
            param($Sql)
            if ($Sql -like "SELECT Port,*FROM Interfaces*") {
                return New-TestRecordset @()
            }
            [void]$script:commands.Add($Sql)
            return $null
        }
        Add-Member -InputObject $connection -MemberType ScriptMethod -Name BeginTrans -Value { }
        Add-Member -InputObject $connection -MemberType ScriptMethod -Name CommitTrans -Value { }
        Add-Member -InputObject $connection -MemberType ScriptMethod -Name RollbackTrans -Value { }
        Add-Member -InputObject $connection -MemberType ScriptMethod -Name Close -Value { }

        $sharedPort = [pscustomobject]@{
            Name      = 'Gi1/0/1'
            Status    = 'up'
            VLAN      = '10'
            Duplex    = 'full'
            Speed     = '1G'
            Type      = 'access'
            Learned   = ''
            AuthState = ''
            AuthMode  = ''
            AuthClient= ''
            Template  = ''
            Config    = ''
            PortColor = ''
            StatusTag = ''
            ToolTip   = ''
            Signature = 'sig-1'
        }

        $sharedEntry = [pscustomobject]@{
            HostMap = @{
                'SW1' = @{
                    'Gi1/0/1' = $sharedPort
                }
            }
            TotalRows = 1
            HostCount = 1
            CacheStatus = 'Hit'
            CachedAt = Get-Date
        }

        Mock -ModuleName DeviceRepositoryModule Get-InterfaceSiteCache {
            [pscustomobject]@{
                HostMap   = @{}
                TotalRows = 0
                HostCount = 0
                CacheStatus = 'Hit'
                CachedAt  = Get-Date
            }
        }

        Mock -ModuleName DeviceRepositoryModule Get-SharedSiteInterfaceCacheEntry { $sharedEntry }

        Mock -ModuleName DeviceRepositoryModule Get-InterfaceSiteCacheSummary {
            [pscustomobject]@{
                CacheExists = $true
                TotalRows   = 1
            }
        }

        Mock -ModuleName DeviceRepositoryModule Get-LastInterfaceSiteCacheMetrics { $null }
        Mock -ModuleName DeviceRepositoryModule Set-InterfaceSiteCacheHost { }
        $facts = [pscustomobject]@{
            InterfacesCombined = @(
                [pscustomobject]@{
                    Port      = 'Gi1/0/1'
                    Name      = 'Gi1/0/1'
                    Status    = 'up'
                    VLAN      = '10'
                    Duplex    = 'full'
                    Speed     = '1G'
                    Type      = 'access'
                    Learned   = ''
                    AuthState = ''
                    AuthMode  = ''
                    AuthClient= ''
                    AuthTemplate = ''
                    Config    = ''
                    PortColor = ''
                    StatusTag = ''
                    ToolTip   = ''
                    Signature = 'sig-1'
                }
            )
            Make = 'Cisco'
        }

        ParserPersistenceModule\Update-InterfacesInDb -Connection $connection -Facts $facts -Hostname 'SW1' -RunDateString '2025-11-06 12:00:00'

        $telemetry = InModuleScope -ModuleName ParserPersistenceModule { Get-LastInterfaceSyncTelemetry }
        $telemetry | Should Not BeNullOrEmpty
        Remove-Variable -Name commands -Scope Script -ErrorAction SilentlyContinue
    }


    It "prefers shared cache when site cache updates are disabled" {

        $commands = New-Object "System.Collections.Generic.List[string]"
        Set-Variable -Name commands -Scope Script -Value $commands

        $connection = New-Object PSObject
        Add-Member -InputObject $connection -MemberType ScriptMethod -Name Execute -Value {
            param($Sql)
            [void]$script:commands.Add($Sql)
            return $null
        }
        Add-Member -InputObject $connection -MemberType ScriptMethod -Name BeginTrans -Value { }
        Add-Member -InputObject $connection -MemberType ScriptMethod -Name CommitTrans -Value { }
        Add-Member -InputObject $connection -MemberType ScriptMethod -Name RollbackTrans -Value { }
        Add-Member -InputObject $connection -MemberType ScriptMethod -Name Close -Value { }

        $sharedPort = [pscustomobject]@{
            Name      = 'Gi1/0/1'
            Status    = 'up'
            VLAN      = '10'
            Duplex    = 'full'
            Speed     = '1G'
            Type      = 'access'
            Learned   = ''
            AuthState = ''
            AuthMode  = ''
            AuthClient= ''
            Template  = ''
            Config    = ''
            PortColor = ''
            StatusTag = ''
            ToolTip   = ''
            Signature = 'sig-1'
        }

        $sharedEntry = [pscustomobject]@{
            HostMap = @{
                'SW1' = @{
                    'Gi1/0/1' = $sharedPort
                }
            }
            TotalRows = 1
            HostCount = 1
            CacheStatus = 'Hit'
            CachedAt    = Get-Date
        }

        $script:interfaceSiteCacheFetchCount = 0

        Mock -ModuleName DeviceRepositoryModule Get-InterfaceSiteCache {
            param([string]$Site, [object]$Connection, [switch]$Refresh)
            $script:interfaceSiteCacheFetchCount++
            if ($Refresh) {
                throw "Refresh should not be invoked when shared cache satisfies request."
            }
            return [pscustomobject]@{
                HostMap   = @{}
                TotalRows = 0
                HostCount = 0
                CacheStatus = 'Hit'
                CachedAt  = Get-Date
            }
        }

        Mock -ModuleName DeviceRepositoryModule Get-SharedSiteInterfaceCacheEntry { $sharedEntry }

        Mock -ModuleName DeviceRepositoryModule Get-InterfaceSiteCacheSummary {
            [pscustomobject]@{
                CacheExists = $false
                TotalRows   = 0
            }
        }

        Mock -ModuleName DeviceRepositoryModule Get-LastInterfaceSiteCacheMetrics { $null }
        Mock -ModuleName DeviceRepositoryModule Set-InterfaceSiteCacheHost { }
        $facts = [pscustomobject]@{
            InterfacesCombined = @(
                [pscustomobject]@{
                    Port      = 'Gi1/0/1'
                    Name      = 'Gi1/0/1'
                    Status    = 'up'
                    VLAN      = '10'
                    Duplex    = 'full'
                    Speed     = '1G'
                    Type      = 'access'
                    Learned   = ''
                    AuthState = ''
                    AuthMode  = ''
                    AuthClient= ''
                    AuthTemplate = ''
                    Config    = ''
                    PortColor = ''
                    StatusTag = ''
                    ToolTip   = ''
                    Signature = 'sig-1'
                }
            )
            Make = 'Cisco'
        }

        ParserPersistenceModule\Update-InterfacesInDb -Connection $connection -Facts $facts -Hostname 'SW1' -RunDateString '2025-11-06 12:00:00' -SkipSiteCacheUpdate $true

        $telemetry = InModuleScope -ModuleName ParserPersistenceModule { Get-LastInterfaceSyncTelemetry }
        $telemetry | Should Not BeNullOrEmpty
        $telemetry.LoadCacheRefreshed | Should Be $false
        $script:interfaceSiteCacheFetchCount | Should Be 0

        Remove-Variable -Name commands -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name interfaceSiteCacheFetchCount -Scope Script -ErrorAction SilentlyContinue
    }

    It "reuses site existing row cache when site cache updates are skipped" {
        $rows = @(
            @{
                Port = 'Gi1/0/1'
                Name = 'Gi1/0/1'
                Status = 'up'
                VLAN = '10'
                Duplex = 'full'
                Speed = '1G'
                Type = 'access'
                LearnedMACs = '0011.2233.4455'
                AuthState = 'Authorized'
                AuthMode = 'dot1x'
                AuthClientMAC = '0011.2233.4455'
                AuthTemplate = 'default'
                Config = 'desc foo'
                PortColor = 'green'
                ConfigStatus = 'active'
                ToolTip = ''
            }
        )
        ParserPersistenceModule\Set-ParserSkipSiteCacheUpdate -Skip $true | Out-Null
        try {
            $recordsets = New-Object "System.Collections.Generic.Queue[object]"
            $recordsets.Enqueue((New-TestRecordset $rows))
            Mock -ModuleName ParserPersistenceModule DeviceRepositoryModule\Get-InterfaceSiteCache { $null }
            Mock -ModuleName ParserPersistenceModule DeviceRepositoryModule\Get-SharedSiteInterfaceCacheEntry { $null }

            $connection = New-Object PSObject
            Add-Member -InputObject $connection -MemberType ScriptMethod -Name Execute -Value {
                param($Sql)
                if ($Sql -match '^(?i)\s*select\b' -and $recordsets.Count -gt 0) {
                    return $recordsets.Dequeue()
                }
                return $null
            }

            $facts = [pscustomobject]@{
                Interfaces = @(
                    [pscustomobject]@{
                        Port = 'Gi1/0/1'
                        Name = 'Gi1/0/1'
                        Status = 'up'
                        VLAN = '10'
                        Duplex = 'full'
                        Speed = '1G'
                        Type = 'access'
                        LearnedMACsFull = '0011.2233.4455'
                        AuthState = 'Authorized'
                        AuthMode = 'dot1x'
                        AuthClient = '0011.2233.4455'
                        Template = 'default'
                        Config = 'desc foo'
                        PortColor = 'green'
                        StatusTag = 'active'
                        ToolTip = ''
                    }
                )
                SiteCode = 'WLLS'
            }

            ParserPersistenceModule\Update-InterfacesInDb -Connection $connection -Facts $facts -Hostname 'WLLS-A01-AS-01' -RunDateString '2025-11-08 10:00:00'
            $recordsets.Count | Should Be 0
            $recordsets.Enqueue((New-TestRecordset $rows))
            ParserPersistenceModule\Update-InterfacesInDb -Connection $connection -Facts $facts -Hostname 'WLLS-A01-AS-01' -RunDateString '2025-11-08 10:05:00'
            $recordsets.Count | Should Be 1
        } finally {
            ParserPersistenceModule\Set-ParserSkipSiteCacheUpdate -Reset | Out-Null
        }
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







    It "writes interfaces via bulk staging when Access helpers succeed" {



        InModuleScope -ModuleName ParserPersistenceModule {



            $script:bulkCommands = New-Object 'System.Collections.Generic.List[string]'

            $script:bulkCommandExecutions = 0

            $script:lastTelemetry = $null



            $connection = New-Object PSObject

            $connection.PSObject.TypeNames.Insert(0, 'ADODB.Connection')

            Add-Member -InputObject $connection -MemberType ScriptMethod -Name Execute -Value {



                param($Sql)



                [void]$script:bulkCommands.Add($Sql)



                return $null



            }



            Mock Ensure-InterfaceBulkSeedTable -ModuleName ParserPersistenceModule { return $true }



            function TelemetryModule\Write-StTelemetryEvent {



                param($Name, $Payload)



                $script:lastTelemetry = @{ Name = $Name; Payload = $Payload }



            }



            Mock Release-ComObjectSafe -ModuleName ParserPersistenceModule { }



            Mock New-AdodbTextCommand -ModuleName ParserPersistenceModule {



                param($Connection, $CommandText)



                $command = New-Object PSObject

                Add-Member -InputObject $command -MemberType NoteProperty -Name CommandText -Value $CommandText

                Add-Member -InputObject $command -MemberType NoteProperty -Name ActiveConnection -Value $Connection



                $paramsList = New-Object 'System.Collections.Generic.List[object]'

                $paramsBag = New-Object PSObject

                Add-Member -InputObject $paramsBag -MemberType NoteProperty -Name Items -Value $paramsList

                Add-Member -InputObject $paramsBag -MemberType ScriptMethod -Name Append -Value {



                    param($parameter)



                    [void]$this.Items.Add($parameter)



                }

                Add-Member -InputObject $command -MemberType NoteProperty -Name Parameters -Value $paramsBag



                Add-Member -InputObject $command -MemberType ScriptMethod -Name CreateParameter -Value {



                    param($name, $type, $direction, $size)



                    $param = New-Object PSObject



                    Add-Member -InputObject $param -MemberType NoteProperty -Name Name -Value $name



                    Add-Member -InputObject $param -MemberType NoteProperty -Name Value -Value $null



                    return $param



                }



                Add-Member -InputObject $command -MemberType ScriptMethod -Name Execute -Value {



                    $script:bulkCommandExecutions = [int]$script:bulkCommandExecutions + 1



                }



                return $command



            }



            $rows = @(

                [pscustomobject]@{

                    Port        = 'Gi1/0/1'

                    Name        = 'Gi1/0/1'

                    Status      = 'up'

                    VLAN        = '10'

                    VlanNumeric = 10

                    Duplex      = 'full'

                    Speed       = '1G'

                    Type        = 'access'

                    Learned     = 'AA-BB'

                    AuthState   = 'authorized'

                    AuthMode    = 'dot1x'

                    AuthClient  = 'AA-BB-CC-00-11-22'

                    Template    = 'Default'

                    Config      = 'cfg'

                    PortColor   = 'Green'

                    StatusTag   = 'Match'

                    ToolTip     = 'tip'

                }

            )



            $result = Invoke-InterfaceBulkInsertInternal -Connection $connection -Hostname 'sw1' -RunDate (Get-Date '2025-10-01') -Rows $rows



            $result | Should Be $true



            $script:bulkCommandExecutions | Should Be 1



            ($script:bulkCommands | Where-Object { $_ -like 'DELETE FROM InterfaceBulkSeed*' }) | Should Not BeNullOrEmpty



            $script:lastTelemetry | Should Not BeNullOrEmpty



            (($script:lastTelemetry.Name -eq 'InterfaceBulkInsert') -or ($script:lastTelemetry.Name -eq 'PortBatchReady')) | Should Be $true



            if ($script:lastTelemetry.Payload.PSObject.Properties.Name -contains 'Rows') {
                $script:lastTelemetry.Payload.Rows | Should Be 1
            } else {
                $script:lastTelemetry.Payload.PortsCommitted | Should Be 1
            }



            Remove-Variable -Name bulkCommands -Scope Script -ErrorAction SilentlyContinue



            Remove-Variable -Name bulkCommandExecutions -Scope Script -ErrorAction SilentlyContinue



            Remove-Variable -Name lastTelemetry -Scope Script -ErrorAction SilentlyContinue



            Remove-Item Function:TelemetryModule\Write-StTelemetryEvent -ErrorAction SilentlyContinue



        }



    }



    It "returns false when bulk staging prerequisites are unavailable" {



        InModuleScope -ModuleName ParserPersistenceModule {



            $connection = New-Object PSObject



            $connection.PSObject.TypeNames.Insert(0, 'ADODB.Connection')



            Mock Ensure-InterfaceBulkSeedTable -ModuleName ParserPersistenceModule { return $false }





            $rows = @([pscustomobject]@{ Port = 'Gi1/0/1'; Name = 'Gi1/0/1' })



            $result = Invoke-InterfaceBulkInsertInternal -Connection $connection -Hostname 'sw1' -RunDate (Get-Date '2025-10-01') -Rows $rows



            $result | Should Be $false



        }



    }



    It "emits telemetry for persistence failures" {

        InModuleScope -ModuleName ParserPersistenceModule {

            $env:STATETRACE_TELEMETRY_DIR = $TestDrive

            try {

                $moduleInfo = Get-Module ParserPersistenceModule

                $telemetryPath = Join-Path $moduleInfo.ModuleBase 'TelemetryModule.psm1'

                Import-Module $telemetryPath -Force | Out-Null



                Write-InterfacePersistenceFailure -Stage 'DeviceLogParserUnhandled' -Hostname 'SW1' -Exception ([System.Exception]'boom') -Metadata @{ Provider = 'ACE' }



                $telemetryFile = Get-ChildItem -LiteralPath $TestDrive -Filter '*.json' | Sort-Object LastWriteTime -Descending | Select-Object -First 1

                $telemetryFile | Should Not BeNullOrEmpty



                $events = @(Get-Content -LiteralPath $telemetryFile.FullName | ForEach-Object { $_ | ConvertFrom-Json })

                $event = $events | Where-Object { $_.EventName -eq 'InterfacePersistenceFailure' } | Select-Object -Last 1

                $event | Should Not BeNullOrEmpty

                $event.Stage | Should Be 'DeviceLogParserUnhandled'

                $event.Hostname | Should Be 'SW1'

                $event.Provider | Should Be 'ACE'

                $event.ExceptionMessage | Should Match 'boom'

            } finally {

                Remove-Item Env:STATETRACE_TELEMETRY_DIR -ErrorAction SilentlyContinue

                if (Get-Module TelemetryModule) { Remove-Module TelemetryModule -Force }

                Get-ChildItem -LiteralPath $TestDrive -Filter '*.json' | Remove-Item -ErrorAction SilentlyContinue

            }

        }

    }

    It "emits InterfaceSyncTiming even when stream metrics are absent" {

        InModuleScope -ModuleName ParserPersistenceModule {

            $env:STATETRACE_TELEMETRY_DIR = $TestDrive
            try {
                $moduleInfo = Get-Module ParserPersistenceModule
                $telemetryPath = Join-Path $moduleInfo.ModuleBase 'TelemetryModule.psm1'
                Import-Module $telemetryPath -Force | Out-Null
                $deviceRepositoryPath = Join-Path $moduleInfo.ModuleBase 'DeviceRepositoryModule.psm1'
                Import-Module $deviceRepositoryPath -Force | Out-Null

                Get-ChildItem -LiteralPath $TestDrive -Filter '*.json' | Remove-Item -ErrorAction SilentlyContinue

                Mock -ModuleName ParserPersistenceModule Ensure-InterfaceTableIndexes { }
                Mock -ModuleName ParserPersistenceModule DeviceRepositoryModule\Get-SiteFromHostname { 'BOYO' }
                Mock -ModuleName ParserPersistenceModule Invoke-AdodbNonQuery { }

                $connection = New-Object PSObject
                Add-Member -InputObject $connection -MemberType ScriptMethod -Name Execute -Value {
                    param($Sql)
                    return (New-TestRecordset @())
                }

                $facts = [pscustomobject]@{
                    Interfaces = @(
                        [pscustomobject]@{
                            Port = 'Gi1/0/1'
                            Name = 'Gi1/0/1'
                            Status = 'up'
                            VLAN = '10'
                            Duplex = 'full'
                            Speed = '1G'
                            Type = 'access'
                            LearnedMACsFull = '0011.2233.4455'
                            AuthState = 'Authorized'
                            AuthMode = 'dot1x'
                            AuthClient = '0011.2233.4455'
                            Template = 'default'
                            Config = 'desc foo'
                            PortColor = 'green'
                            StatusTag = 'active'
                            ToolTip = ''
                        }
                    )
                    SiteCode = 'BOYO'
                }

                Update-InterfacesInDb -Connection $connection -Facts $facts -Hostname 'SW1' -RunDateString '2025-10-15 10:00:00'

                $telemetryFile = Get-ChildItem -LiteralPath $TestDrive -Filter '*.json' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                $telemetryFile | Should Not BeNullOrEmpty

                $events = @(Get-Content -LiteralPath $telemetryFile.FullName | ForEach-Object { $_ | ConvertFrom-Json })
                $interfaceSync = $events | Where-Object { $_.EventName -eq 'InterfaceSyncTiming' } | Select-Object -Last 1
                $interfaceSync | Should Not BeNullOrEmpty
                $interfaceSync.StreamCloneDurationMs | Should Be 0.0
                $interfaceSync.StreamRowsReceived | Should Be 0
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheFetchDurationMs') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheRefreshDurationMs') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheFetchStatus') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheSnapshotDurationMs') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheRecordsetDurationMs') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheRecordsetProjectDurationMs') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheBuildDurationMs') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheHostMapDurationMs') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheHostMapSignatureMatchCount') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheHostMapSignatureRewriteCount') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheHostMapEntryAllocationCount') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheHostMapEntryPoolReuseCount') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheHostMapLookupCount') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheHostMapLookupMissCount') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheHostMapCandidateMissingCount') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheHostMapCandidateSignatureMissingCount') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheHostMapCandidateSignatureMismatchCount') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheHostMapCandidateFromPreviousCount') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheHostMapCandidateFromPoolCount') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheHostMapCandidateInvalidCount') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheHostMapCandidateMissingSamples') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheHostMapSignatureMismatchSamples') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCachePreviousHostCount') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCachePreviousPortCount') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCachePreviousHostSample') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCachePreviousSnapshotStatus') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCachePreviousSnapshotHostMapType') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCachePreviousSnapshotHostCount') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCachePreviousSnapshotPortCount') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCachePreviousSnapshotException') | Should Be $true
                @($interfaceSync.SiteCacheHostMapSignatureMismatchSamples).Count | Should Be 0
                (@($interfaceSync.SiteCacheHostMapCandidateMissingSamples).Count -le 5) | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheSortDurationMs') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheHostCount') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheQueryDurationMs') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheExecuteDurationMs') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheMaterializeDurationMs') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'DiffComparisonDurationMs') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'LoadExistingRowSetCount') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheMaterializeProjectionDurationMs') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheMaterializePortSortDurationMs') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheMaterializePortSortCacheHitCount') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheMaterializePortSortCacheMissCount') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheMaterializePortSortCacheSize') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheMaterializePortSortCacheHitRatio') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheMaterializePortSortUniquePortCount') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheMaterializePortSortMissSamples') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheMaterializeTemplateDurationMs') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheMaterializeTemplateLookupDurationMs') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheMaterializeTemplateApplyDurationMs') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheMaterializeTemplateCacheHitCount') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheMaterializeTemplateCacheMissCount') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheMaterializeTemplateReuseCount') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheMaterializeTemplateCacheHitRatio') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheMaterializeTemplateApplyCount') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheMaterializeTemplateDefaultedCount') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheMaterializeTemplateAuthTemplateMissingCount') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheMaterializeTemplateNoTemplateMatchCount') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheMaterializeTemplateHintAppliedCount') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheMaterializeTemplateSetPortColorCount') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheMaterializeTemplateSetConfigStatusCount') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheMaterializeTemplateApplySamples') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheMaterializeObjectDurationMs') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheTemplateDurationMs') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheQueryAttempts') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheExclusiveRetryCount') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheExclusiveWaitDurationMs') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheProvider') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheProviderReason') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheResultRowCount') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheExistingRowCount') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheExistingRowKeysSample') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheExistingRowValueType') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheExistingRowSource') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheComparisonCandidateCount') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheComparisonSignatureMatchCount') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheComparisonSignatureMismatchCount') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheComparisonSignatureMissingCount') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheComparisonMissingPortCount') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheComparisonObsoletePortCount') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheResolveInitialStatus') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheResolveInitialHostCount') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheResolveInitialMatchedKey') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheResolveInitialKeysSample') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheResolveInitialCacheAgeMs') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheResolveInitialCachedAt') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheResolveInitialEntryType') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheResolveInitialPortCount') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheResolveInitialPortKeysSample') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheResolveInitialPortSignatureSample') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheResolveInitialPortSignatureMissingCount') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheResolveInitialPortSignatureEmptyCount') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheResolveRefreshStatus') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheResolveRefreshHostCount') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheResolveRefreshMatchedKey') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheResolveRefreshKeysSample') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheResolveRefreshCacheAgeMs') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheResolveRefreshCachedAt') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheResolveRefreshEntryType') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheResolveRefreshPortCount') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheResolveRefreshPortKeysSample') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheResolveRefreshPortSignatureSample') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheResolveRefreshPortSignatureMissingCount') | Should Be $true
                ($interfaceSync.PSObject.Properties.Name -contains 'SiteCacheResolveRefreshPortSignatureEmptyCount') | Should Be $true
            } finally {
                Remove-Item Env:STATETRACE_TELEMETRY_DIR -ErrorAction SilentlyContinue
                if (Get-Module DeviceRepositoryModule) { Remove-Module DeviceRepositoryModule -Force }
                if (Get-Module TelemetryModule) { Remove-Module TelemetryModule -Force }
                Get-ChildItem -LiteralPath $TestDrive -Filter '*.json' | Remove-Item -ErrorAction SilentlyContinue
            }
        }

    }

    It "exposes stream metrics via Get-LastInterfaceSyncTelemetry" {
        InModuleScope -ModuleName ParserPersistenceModule {
            $script:LastInterfaceSyncTelemetry = [pscustomobject]@{
                Hostname                 = 'SW1'
                StreamDispatchDurationMs = 5.5
                StreamCloneDurationMs    = 1.2
                StreamStateUpdateDurationMs = 0.8
                UiCloneDurationMs        = 2.3
                StreamRowsReceived       = 10
                StreamRowsReused         = 10
                StreamRowsCloned         = 0
                LoadCacheHit             = $true
                CachedRowCount           = 10
                CachePrimedRowCount      = 20
                SiteCacheFetchDurationMs = 5.5
                SiteCacheRefreshDurationMs = 1.1
                SiteCacheFetchStatus     = 'SharedOnly'
                SiteCacheSnapshotDurationMs = 0.4
                SiteCacheRecordsetDurationMs = 0.15
                SiteCacheRecordsetProjectDurationMs = 0.05
                SiteCacheBuildDurationMs = 0.6
                SiteCacheHostMapDurationMs = 0.3
                SiteCacheHostMapSignatureMatchCount   = 5
                SiteCacheHostMapSignatureRewriteCount = 7
                SiteCacheHostMapEntryAllocationCount  = 2
                SiteCacheHostMapEntryPoolReuseCount   = 4
                SiteCacheHostMapLookupCount           = 11
                SiteCacheHostMapLookupMissCount       = 2
                SiteCacheHostMapCandidateMissingCount = 1
                SiteCacheHostMapCandidateSignatureMissingCount = 0
                SiteCacheHostMapCandidateSignatureMismatchCount = 3
                SiteCacheHostMapCandidateFromPreviousCount = 8
                SiteCacheHostMapCandidateFromPoolCount     = 1
                SiteCacheHostMapCandidateInvalidCount      = 0
                SiteCacheHostMapCandidateMissingSamples = @(
                    [pscustomobject]@{
                        Hostname                  = 'SW1'
                        Port                      = 'Gi1/0/2'
                        Reason                    = 'HostSnapshotMissing'
                        PreviousHostEntryPresent  = $false
                        PreviousPortEntryPresent  = $false
                        CachedPortCount           = 0
                        CachedPortSample          = ''
                        CachedSignature           = $null
                        PreviousRemainingPortCount = 0
                        CandidateSource           = ''
                        ParserResolveInitialStatus = 'NotFound'
                        ParserExistingRowCount = 20
                        ParserExistingRowKeysSample = 'Gi1/0/1|Gi1/0/2'
                        ParserExistingRowValueType = 'System.Management.Automation.PSCustomObject'
                        ParserExistingRowSource = 'CacheInitial'
                        ParserLoadCacheHit = $true
                        ParserLoadCacheMiss = $false
                        ParserLoadCacheRefreshed = $false
                    }
                )
                SiteCachePreviousHostCount = 12
                SiteCachePreviousPortCount = 20
                SiteCachePreviousHostSample = 'SW1|SW2'
                SiteCachePreviousSnapshotStatus = 'Converted'
                SiteCachePreviousSnapshotHostMapType = 'System.Collections.Generic.Dictionary`2[System.String,System.Collections.Generic.Dictionary`2[System.String,StateTrace.Models.InterfaceCacheEntry]]'
                SiteCachePreviousSnapshotHostCount = 12
                SiteCachePreviousSnapshotPortCount = 20
                SiteCachePreviousSnapshotException = ''
                SiteCacheHostMapSignatureMismatchSamples = @(
                    [pscustomobject]@{
                        Hostname          = 'SW1'
                        Port              = 'Gi1/0/1'
                        PreviousSignature = 'sig-old'
                        NewSignature      = 'sig-new'
                    }
                )
                SiteCacheSortDurationMs = 0.2
                SiteCacheHostCount       = 12
                SiteCacheQueryDurationMs = 2.0
                SiteCacheExecuteDurationMs = 1.5
                SiteCacheMaterializeDurationMs = 3.3
                SiteCacheMaterializeProjectionDurationMs = 1.1
                SiteCacheMaterializePortSortDurationMs   = 0.2
                SiteCacheMaterializePortSortCacheHitCount   = 12
                SiteCacheMaterializePortSortCacheMissCount = 3
                SiteCacheMaterializePortSortCacheSize      = 45
                SiteCacheMaterializePortSortCacheHitRatio  = 0.8
                SiteCacheMaterializePortSortUniquePortCount = 90
                SiteCacheMaterializePortSortMissSamples      = @(
                    [pscustomobject]@{
                        Port     = 'Gi1/0/1'
                        PortSort = '01-GI-00001-00000-00000-00000'
                    }
                )
                SiteCacheMaterializeTemplateDurationMs   = 0.3
                SiteCacheMaterializeTemplateLookupDurationMs = 0.12
                SiteCacheMaterializeTemplateApplyDurationMs  = 0.08
                SiteCacheMaterializeTemplateCacheHitCount    = 10
                SiteCacheMaterializeTemplateCacheMissCount   = 5
                SiteCacheMaterializeTemplateReuseCount       = 7
                SiteCacheMaterializeTemplateCacheHitRatio    = 0.666667
                SiteCacheMaterializeTemplateApplyCount        = 18
                SiteCacheMaterializeTemplateDefaultedCount    = 4
                SiteCacheMaterializeTemplateAuthTemplateMissingCount = 2
                SiteCacheMaterializeTemplateNoTemplateMatchCount     = 2
                SiteCacheMaterializeTemplateHintAppliedCount   = 14
                SiteCacheMaterializeTemplateSetPortColorCount  = 3
                SiteCacheMaterializeTemplateSetConfigStatusCount = 5
                SiteCacheMaterializeTemplateApplySamples       = @(
                    [pscustomobject]@{
                        Port            = 'Gi1/0/1'
                        AuthTemplate    = 'Default'
                        Reason          = 'TemplateMatched'
                        HintSource      = 'Cache'
                        PortColorSet    = $true
                        ConfigStatusSet = $true
                    }
                )
                SiteCacheMaterializeObjectDurationMs     = 1.7
                SiteCacheTemplateDurationMs = 0.9
                SiteCacheQueryAttempts   = 1
                SiteCacheExclusiveRetryCount = 0
                SiteCacheExclusiveWaitDurationMs = 0.0
                SiteCacheProvider        = 'Hydrate'
                SiteCacheProviderReason  = 'Hydrate'
                SiteCacheResultRowCount  = 20
                SiteCacheExistingRowCount = 20
                SiteCacheExistingRowKeysSample = 'Gi1/0/1|Gi1/0/2'
                SiteCacheExistingRowValueType = 'System.Management.Automation.PSCustomObject'
                SiteCacheExistingRowSource = 'CacheInitial'
                SiteCacheComparisonCandidateCount = 12
                SiteCacheComparisonSignatureMatchCount = 10
                SiteCacheComparisonSignatureMismatchCount = 2
                SiteCacheComparisonSignatureMissingCount = 1
                SiteCacheComparisonMissingPortCount = 3
                SiteCacheComparisonObsoletePortCount = 4
                SiteCacheResolveInitialStatus = 'NotFound'
                SiteCacheResolveInitialHostCount = 3
                SiteCacheResolveInitialMatchedKey = ''
                SiteCacheResolveInitialKeysSample = 'SW1|SW2'
                SiteCacheResolveInitialCacheAgeMs = 125.5
                SiteCacheResolveInitialCachedAt = '2025-10-15T10:00:00.0000000Z'
                SiteCacheResolveInitialEntryType = 'System.Collections.Generic.Dictionary[string,System.Object]'
                SiteCacheResolveInitialPortCount = 0
                SiteCacheResolveInitialPortKeysSample = ''
                SiteCacheResolveInitialPortSignatureSample = ''
                SiteCacheResolveInitialPortSignatureMissingCount = 0
                SiteCacheResolveInitialPortSignatureEmptyCount = 0
                SiteCacheResolveRefreshStatus = 'ExactMatch'
                SiteCacheResolveRefreshHostCount = 3
                SiteCacheResolveRefreshMatchedKey = 'SW1'
                SiteCacheResolveRefreshKeysSample = 'SW1|SW2'
                SiteCacheResolveRefreshCacheAgeMs = 12.4
                SiteCacheResolveRefreshCachedAt = '2025-10-15T10:02:00.0000000Z'
                SiteCacheResolveRefreshEntryType = 'System.Collections.Generic.Dictionary[string,System.Object]'
                SiteCacheResolveRefreshPortCount = 4
                SiteCacheResolveRefreshPortKeysSample = 'Gi1/0/1|Gi1/0/2'
                SiteCacheResolveRefreshPortSignatureSample = 'sig-a|sig-b'
                SiteCacheResolveRefreshPortSignatureMissingCount = 1
                SiteCacheResolveRefreshPortSignatureEmptyCount = 0
            }
        }

        $metrics = ParserPersistenceModule\Get-LastInterfaceSyncTelemetry
        $metrics | Should Not BeNullOrEmpty
        $metrics.StreamDispatchDurationMs | Should Be 5.5
        $metrics.StreamCloneDurationMs | Should Be 1.2
        $metrics.StreamRowsCloned | Should Be 0
        ($metrics.PSObject.Properties.Name -contains 'UiCloneDurationMs') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'LoadCacheHit') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheFetchDurationMs') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheRefreshDurationMs') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheComparisonCandidateCount') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheResolveInitialEntryType') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheResolveRefreshEntryType') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheFetchStatus') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheSnapshotDurationMs') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheRecordsetDurationMs') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheRecordsetProjectDurationMs') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheBuildDurationMs') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheHostMapDurationMs') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheHostMapSignatureMatchCount') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheHostMapSignatureRewriteCount') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheHostMapEntryAllocationCount') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheHostMapEntryPoolReuseCount') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheHostMapLookupCount') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheHostMapLookupMissCount') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheHostMapCandidateMissingCount') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheHostMapCandidateSignatureMissingCount') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheHostMapCandidateSignatureMismatchCount') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheHostMapCandidateFromPreviousCount') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheHostMapCandidateFromPoolCount') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheHostMapCandidateInvalidCount') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheHostMapCandidateMissingSamples') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheHostMapSignatureMismatchSamples') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCachePreviousHostCount') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCachePreviousPortCount') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCachePreviousHostSample') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCachePreviousSnapshotStatus') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCachePreviousSnapshotHostMapType') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCachePreviousSnapshotHostCount') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCachePreviousSnapshotPortCount') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCachePreviousSnapshotException') | Should Be $true
        @($metrics.SiteCacheHostMapSignatureMismatchSamples).Count | Should Be 1
        $metrics.SiteCacheHostMapSignatureMismatchSamples[0].NewSignature | Should Be 'sig-new'
        @($metrics.SiteCacheHostMapCandidateMissingSamples).Count | Should Be 1
        $metrics.SiteCacheHostMapCandidateMissingSamples[0].Reason | Should Be 'HostSnapshotMissing'
        $metrics.SiteCacheHostMapCandidateMissingSamples[0].ParserExistingRowCount | Should Be 20
        $metrics.SiteCacheHostMapCandidateMissingSamples[0].ParserExistingRowSource | Should Be 'CacheInitial'
        $metrics.SiteCacheRecordsetDurationMs | Should Be 0.15
        $metrics.SiteCacheRecordsetProjectDurationMs | Should Be 0.05
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheSortDurationMs') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheHostCount') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheQueryDurationMs') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheExecuteDurationMs') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheMaterializeDurationMs') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheMaterializeProjectionDurationMs') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheMaterializePortSortDurationMs') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheMaterializePortSortCacheHitCount') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheMaterializePortSortCacheMissCount') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheMaterializePortSortCacheSize') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheMaterializePortSortCacheHitRatio') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheMaterializePortSortUniquePortCount') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheMaterializePortSortMissSamples') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheMaterializeTemplateDurationMs') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheMaterializeTemplateLookupDurationMs') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheMaterializeTemplateApplyDurationMs') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheMaterializeTemplateCacheHitCount') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheMaterializeTemplateCacheMissCount') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheMaterializeTemplateReuseCount') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheMaterializeTemplateCacheHitRatio') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheMaterializeTemplateApplyCount') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheMaterializeTemplateDefaultedCount') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheMaterializeTemplateAuthTemplateMissingCount') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheMaterializeTemplateNoTemplateMatchCount') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheMaterializeTemplateHintAppliedCount') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheMaterializeTemplateSetPortColorCount') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheMaterializeTemplateSetConfigStatusCount') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheMaterializeTemplateApplySamples') | Should Be $true
        $metrics.SiteCacheMaterializePortSortUniquePortCount | Should Be 90
        @($metrics.SiteCacheMaterializePortSortMissSamples).Count | Should Be 1
        $metrics.SiteCacheMaterializePortSortMissSamples[0].Port | Should Be 'Gi1/0/1'
        $metrics.SiteCacheMaterializeTemplateApplyCount | Should Be 18
        $metrics.SiteCacheMaterializeTemplateDefaultedCount | Should Be 4
        $metrics.SiteCacheMaterializeTemplateAuthTemplateMissingCount | Should Be 2
        $metrics.SiteCacheMaterializeTemplateNoTemplateMatchCount | Should Be 2
        $metrics.SiteCacheMaterializeTemplateHintAppliedCount | Should Be 14
        $metrics.SiteCacheMaterializeTemplateSetPortColorCount | Should Be 3
        $metrics.SiteCacheMaterializeTemplateSetConfigStatusCount | Should Be 5
        @($metrics.SiteCacheMaterializeTemplateApplySamples).Count | Should Be 1
        $metrics.SiteCacheMaterializeTemplateApplySamples[0].Reason | Should Be 'TemplateMatched'
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheMaterializeObjectDurationMs') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheTemplateDurationMs') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheQueryAttempts') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheExclusiveRetryCount') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheExclusiveWaitDurationMs') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheProvider') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheProviderReason') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheResultRowCount') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheExistingRowCount') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheExistingRowKeysSample') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheExistingRowValueType') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheExistingRowSource') | Should Be $true
        $metrics.SiteCacheExistingRowCount | Should Be 20
        $metrics.SiteCacheExistingRowSource | Should Be 'CacheInitial'
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheResolveInitialStatus') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheResolveInitialHostCount') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheResolveInitialMatchedKey') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheResolveInitialKeysSample') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheResolveInitialCacheAgeMs') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheResolveInitialCachedAt') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheResolveRefreshStatus') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheResolveRefreshHostCount') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheResolveRefreshMatchedKey') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheResolveRefreshKeysSample') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheResolveRefreshCacheAgeMs') | Should Be $true
        ($metrics.PSObject.Properties.Name -contains 'SiteCacheResolveRefreshCachedAt') | Should Be $true
    }

}


