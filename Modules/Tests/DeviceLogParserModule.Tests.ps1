Set-StrictMode -Version Latest

Describe "DeviceLogParserModule" {
    BeforeAll {
        $telemetryPath = Join-Path (Split-Path $PSCommandPath) "..\\TelemetryModule.psm1"
        Import-Module (Resolve-Path $telemetryPath) -Force

        $modulePath = Join-Path (Split-Path $PSCommandPath) "..\\DeviceLogParserModule.psm1"
        Import-Module (Resolve-Path $modulePath) -Force
    }

    AfterAll {
        Remove-Module DeviceLogParserModule -Force
        if (Get-Module TelemetryModule) { Remove-Module TelemetryModule -Force }
    }

    It "parses location tokens from SNMP strings" {
        $details = DeviceLogParserModule\Get-LocationDetails -Location 'Bldg _ A _ Floor _ 2 _ Room _ 210'
        $details.Building | Should Be 'A'
        $details.Floor | Should Be '2'
        $details.Room | Should Be '210'
    }

    It "identifies vendors from show version output" {
        $blocks = @{ 'show version' = @('Arista vEOS 4.26.4') }
        DeviceLogParserModule\Get-DeviceMakeFromBlocks -Blocks $blocks | Should Be 'Arista'
    }

    It "extracts SNMP location lines from logs" {
        $lines = @('some text', 'snmp-server location HQ-2-115', 'trailing')
        DeviceLogParserModule\Get-SnmpLocationFromLines -Lines $lines | Should Be 'HQ-2-115'
    }

    It "selects show blocks with preferred keys and regex fallbacks" {
        $blocks = @{
            'show interfaces status' = @('status')
            'show mac-address-table' = @('macs')
            'show auth ses' = @('auth')
        }
        (@(DeviceLogParserModule\Get-ShowBlock -Blocks $blocks -PreferredKeys @('show interfaces status') -DefaultValue @('fallback')))[0] | Should Be 'status'
        (@(DeviceLogParserModule\Get-ShowBlock -Blocks $blocks -PreferredKeys @('missing') -RegexPatterns @('^show\s+mac[- ]address[- ]table') -DefaultValue @('fallback')))[0] | Should Be 'macs'
        (@(DeviceLogParserModule\Get-ShowBlock -Blocks $blocks -PreferredKeys @('missing') -RegexPatterns @('^nomatch') -DefaultValue @('fallback')))[0] | Should Be 'fallback'
    }

    It "falls back to raw lines when blocks are absent" {
        $lines = @('# show version','line1','line2','# prompt')
        $result = DeviceLogParserModule\Get-ShowBlock -Blocks @{} -Lines $lines -CommandRegexes @('#\s*show\s+version') -DefaultValue @('miss')
        $result | Should Not BeNullOrEmpty
        $result.Count | Should Be 2
        $result[0] | Should Be 'line1'
        $result[1] | Should Be 'line2'
    }

    It "cleans archive folders older than retention window" {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $old = Join-Path $root ((Get-Date).AddDays(-40).ToString('yyyy-MM-dd'))
        $new = Join-Path $root ((Get-Date).ToString('yyyy-MM-dd'))
        New-Item -ItemType Directory -Path $old -Force | Out-Null
        New-Item -ItemType Directory -Path $new -Force | Out-Null
        DeviceLogParserModule\Remove-OldArchiveFolder -DeviceArchivePath $root -RetentionDays 30
        (Test-Path $old) | Should Be False
        (Test-Path $new) | Should Be True
        Remove-Item -Path $root -Recurse -Force -ErrorAction SilentlyContinue
    }
    It "converts spanning tree output into records" {
        $lines = @(
            'VLAN0010',
            '  Root ID    Priority    32769',
            '             Address     5254.001b.1c58',
            '  Root port Gi1/0/48, cost 4',
            'Interface           Role Sts Cost Prio.Nbr Type',
            '------------------- ---- --- ---- -------- --------',
            'Gi1/0/1             Desg FWD 4    128.1    P2p'
        )

        $rows = @((DeviceLogParserModule\ConvertFrom-SpanningTree -SpanLines $lines))

        $rows.Count | Should Be 1
        $rows[0].VLAN | Should Be 'VLAN0010'
        $rows[0].RootSwitch | Should Be '5254.001b.1c58'
        $rows[0].RootPort | Should Be 'Gi1/0/48'
        $rows[0].Role | Should Be 'Desg'
        $rows[0].Upstream | Should Be 'Gi1/0/1'
    }

    It "returns a stub record when no interface rows exist" {
        $lines = @(
            'VLAN0010',
            '  Root ID    Priority    32769',
            '             Address     5254.001b.1c58'
        )

        $rows = @((DeviceLogParserModule\ConvertFrom-SpanningTree -SpanLines $lines))

        $rows.Count | Should Be 1
        $rows[0].VLAN | Should Be 'VLAN0010'
        $rows[0].RootSwitch | Should Be '5254.001b.1c58'
        $rows[0].RootPort | Should Be ''
        $rows[0].Role | Should Be ''
    }

    It "parses log context with command blocks" {
        $tempPath = Join-Path ([System.IO.Path]::GetTempPath()) (([System.Guid]::NewGuid()).ToString() + '.log')
        try {
            Set-Content -Path $tempPath -Value @('switch# show version','Version output line','switch# show interfaces status','Gi1/0/1 up','switch#') -Encoding ASCII
            $ctx = DeviceLogParserModule\Get-LogParseContext -FilePath $tempPath
            $ctx.Lines.Count | Should Be 5
            $ctx.Blocks.ContainsKey('show version') | Should Be True
            $ctx.Blocks['show version'].Count | Should Be 1
            $ctx.Blocks.ContainsKey('show interfaces status') | Should Be True
            $ctx.Blocks['show interfaces status'].Count | Should Be 1
        } finally {
            Remove-Item -Path $tempPath -ErrorAction SilentlyContinue
        }
    }

    It "returns stable mutex names per database path" {
        $pathA = 'C:\Data\SiteA.accdb'
        $pathB = 'C:\Data\SiteB.accdb'
        $nameA = DeviceLogParserModule\Get-DatabaseMutexName -DatabasePath $pathA
        $nameA2 = DeviceLogParserModule\Get-DatabaseMutexName -DatabasePath 'c:\data\sitea.accdb'
        $nameB = DeviceLogParserModule\Get-DatabaseMutexName -DatabasePath $pathB
        $nameA | Should Not Be $nameB
        $nameA | Should Be $nameA2
    }

    It "forces DatabaseWriteBreakdown payloads to report cache providers for site existing cache rows" {
        $payload = @{}
        $telemetry = [pscustomobject]@{ SiteCacheFetchStatus = '' }
        $module = Get-Module DeviceLogParserModule
        $module | Should Not Be $null
        $module.Invoke({ param($p, $source, $telemetry)
                Resolve-DatabaseWriteBreakdownCacheProvider -Payload $p -ExistingRowSource $source -Telemetry $telemetry
            }, $payload, 'SiteExistingCache', $telemetry) | Out-Null
        $payload['SiteCacheProvider'] | Should Be 'Cache'
        $payload['SiteCacheProviderReason'] | Should Be 'SiteExistingCache'
        $payload['SiteCacheFetchStatus'] | Should Be 'Hit'
        $payload['SiteCacheExistingRowSource'] | Should Be 'SiteExistingCache'
    }

    It "derives cache provider details from telemetry when the existing row source is missing" {
        $payload = @{}
        $telemetry = [pscustomobject]@{
            SiteCacheExistingRowSource = 'SiteExistingCache'
            SiteCacheFetchStatus       = 'SkippedEmpty'
        }
        $module = Get-Module DeviceLogParserModule
        $module | Should Not Be $null
        $module.Invoke({ param($p, $telemetry)
                Resolve-DatabaseWriteBreakdownCacheProvider -Payload $p -ExistingRowSource $null -Telemetry $telemetry
            }, $payload, $telemetry) | Out-Null
        $payload['SiteCacheProvider'] | Should Be 'Cache'
        $payload['SiteCacheProviderReason'] | Should Be 'SiteExistingCache'
        $payload['SiteCacheFetchStatus'] | Should Be 'Hit'
        $payload['SiteCacheExistingRowSource'] | Should Be 'SiteExistingCache'
    }

    It "leaves DatabaseWriteBreakdown payloads untouched when existing rows are not cache-backed" {
        $payload = @{}
        $module = Get-Module DeviceLogParserModule
        $module | Should Not Be $null
        $module.Invoke({ param($p, $source)
                Resolve-DatabaseWriteBreakdownCacheProvider -Payload $p -ExistingRowSource $source -Telemetry $null
            }, $payload, 'SharedCacheOnly') | Out-Null
        $payload.ContainsKey('SiteCacheProvider') | Should Be $false
        $payload.ContainsKey('SiteCacheProviderReason') | Should Be $false
        $payload.ContainsKey('SiteCacheFetchStatus') | Should Be $false
    }

    It "loads vendor templates via TemplatesModule and honors file updates" {
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
        $null = New-Item -ItemType Directory -Path $tempDir -Force
        $jsonPath = Join-Path $tempDir 'UnitTest.json'
        try {
            Set-Content -Path $jsonPath -Value '{"templates":["alpha"]}' -Encoding UTF8
            $first = DeviceLogParserModule\Get-VendorTemplates -Vendor 'UnitTest' -TemplatesRoot $tempDir
            $first.Length | Should BeGreaterThan 0
            ($first | Select-Object -First 1) | Should Be 'alpha'

            Start-Sleep -Milliseconds 1100
            Set-Content -Path $jsonPath -Value '{"templates":["beta"]}' -Encoding UTF8
            $second = DeviceLogParserModule\Get-VendorTemplates -Vendor 'UnitTest' -TemplatesRoot $tempDir
            ($second | Select-Object -First 1) | Should Be 'beta'
        } finally {
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "emits duplicate telemetry when log hash matches prior ingestion" {
        if (-not (Get-Command 'DeviceRepositoryModule\Get-SiteFromHostname' -ErrorAction SilentlyContinue)) {
            function DeviceRepositoryModule\Get-SiteFromHostname {
                param([string]$Hostname, [int]$FallbackLength)
                if ([string]::IsNullOrWhiteSpace($Hostname)) { return '' }
                $length = [Math]::Min([Math]::Max($FallbackLength, 1), $Hostname.Length)
                return $Hostname.Substring(0, $length)
            }
        }

        $deviceRepoModulePath = Join-Path (Split-Path $PSCommandPath) '..\DeviceRepositoryModule.psm1'
        Import-Module (Resolve-Path $deviceRepoModulePath) -Force

        $repoRoot = [System.IO.Path]::GetFullPath((Join-Path (Split-Path $PSCommandPath) '..\..'))
        $logPath = Join-Path $TestDrive 'WLLS-A02-AS-02.log'
        $logContent = @(
            'brocade',
            'WLLS-A02-AS-02# show version',
            'Version output line'
        )
        Set-Content -LiteralPath $logPath -Value $logContent -Encoding UTF8
        $hashValue = (Get-FileHash -LiteralPath $logPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $siteCode = 'WLLS'

        $historyDir = Join-Path $repoRoot 'Data\IngestionHistory'
        $historyFile = Join-Path $historyDir 'WLLS.json'
        $historyExists = Test-Path -LiteralPath $historyFile
        $previousHistory = $null
        if ($historyExists) {
            $previousHistory = Get-Content -LiteralPath $historyFile -Raw
        }

        $historyRecord = @(@{
                Hostname        = 'WLLS-A02-AS-02'
                Site            = $siteCode
                FileHash        = $hashValue
                SourceLength    = (Get-Item -LiteralPath $logPath).Length
                LastIngestedUtc = '2025-10-03T12:00:00Z'
            })
        $historyJson = $historyRecord | ConvertTo-Json -Depth 4
        Set-Content -LiteralPath $historyFile -Value $historyJson -Encoding UTF8

        $dbPath = Join-Path $TestDrive 'WLLS.accdb'
        if (-not (Test-Path -LiteralPath $dbPath)) {
            New-Item -Path $dbPath -ItemType File | Out-Null
        }

        $telemetryModulePath = Join-Path (Split-Path $PSCommandPath) '..\TelemetryModule.psm1'
        Import-Module (Resolve-Path $telemetryModulePath) -Force

        $metricsDir = Join-Path $TestDrive 'metrics'
        if (-not (Test-Path -LiteralPath $metricsDir)) { New-Item -ItemType Directory -Path $metricsDir -Force | Out-Null }
        $previousTelemetryDir = $env:STATETRACE_TELEMETRY_DIR
        $env:STATETRACE_TELEMETRY_DIR = $metricsDir

        try {
            DeviceLogParserModule\Invoke-DeviceLogParsing -FilePath $logPath -ArchiveRoot $TestDrive -DatabasePath $dbPath
        } finally {
            if ($previousTelemetryDir) {
                $env:STATETRACE_TELEMETRY_DIR = $previousTelemetryDir
            } else {
                Remove-Item Env:STATETRACE_TELEMETRY_DIR -ErrorAction SilentlyContinue
            }
            if ($historyExists) {
                Set-Content -LiteralPath $historyFile -Value $previousHistory -Encoding UTF8
            } else {
                Remove-Item -LiteralPath $historyFile -Force -ErrorAction SilentlyContinue
            }
        }

        $metricsPath = Join-Path $metricsDir ((Get-Date).ToString('yyyy-MM-dd') + '.json')
        $telemetryEvents = @()
        if (Test-Path -LiteralPath $metricsPath) {
            $telemetryEvents = Get-Content -LiteralPath $metricsPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_ | ConvertFrom-Json }
        }

        $skipEvent = $telemetryEvents | Where-Object { $_.EventName -eq 'SkippedDuplicate' -and $_.Hostname -eq 'WLLS-A02-AS-02' } | Select-Object -First 1
        $parseEvent = $telemetryEvents | Where-Object { $_.EventName -eq 'ParseDuration' -and $_.Hostname -eq 'WLLS-A02-AS-02' } | Select-Object -First 1

        $skipEvent | Should Not BeNullOrEmpty
        $skipEvent.Site | Should Be $siteCode
        $skipEvent.Reason | Should Be 'HashMatch'
        $skipEvent.FileHash | Should Be $hashValue

        $parseEvent | Should BeNullOrEmpty
        ($telemetryEvents | Where-Object { $_.EventName -eq 'ParseDuration' -and $_.Hostname -eq 'WLLS-A02-AS-02' }) | Should BeNullOrEmpty
    }

    Context "Get-CachedDbConnection" {
        function Invoke-InModule {
            param([Parameter(Mandatory)][ScriptBlock]$ScriptBlock, [object[]]$Arguments = @())
            $module = Get-Module DeviceLogParserModule
            if (-not $module) { throw "DeviceLogParserModule is not loaded." }
            $result = $module.Invoke($ScriptBlock, $Arguments)
            if ($null -eq $result) { return $null }
            if ($result -is [System.Collections.IList]) {
                if ($result.Count -eq 0) { return $null }
                return $result[0]
            }
            return $result
        }

        function Invoke-ConnectionMock {
            param([string]$FailPattern)
            Invoke-InModule { param($value) $script:ConnectionMockFailPattern = $value } @($FailPattern)
            Mock -ModuleName DeviceLogParserModule -CommandName New-Object -ParameterFilter { $PSBoundParameters.ContainsKey('ComObject') -and $ComObject -eq 'ADODB.Connection' } -MockWith {
                $prop = [pscustomobject]@{ Value = 0 }
                $properties = [pscustomobject]@{ ValueHolder = $prop }
                $properties | Add-Member -MemberType ScriptMethod -Name Item -Value {
                    param($name)
                    if ($name -eq 'Jet OLEDB:Transaction Commit Mode') { return $this.ValueHolder }
                    return $null
                }
                $conn = [pscustomobject]@{
                    State = 0
                    Properties = $properties
                    LastConnectionString = $null
                    CloseCalls = 0
                    FailPattern = $script:ConnectionMockFailPattern
                }
                $conn | Add-Member -MemberType ScriptMethod -Name Open -Value {
                    param($connStr)
                    $this.LastConnectionString = $connStr
                    if ($this.FailPattern -and ($connStr -match $this.FailPattern)) { throw [System.Exception]::new('provider failure') }
                    $this.State = 1
                }
                $conn | Add-Member -MemberType ScriptMethod -Name Close -Value {
                    $this.State = 0
                    $this.CloseCalls++
                }
                return $conn
            }
        }

        BeforeEach {
            Invoke-InModule {
                $script:ConnectionCache.Clear()
                $script:DbProviderCache.Clear()
                $script:ConnectionCacheTtlMinutes = 5
                $script:ConnectionMockFailPattern = $null
            }
        }

        AfterEach {
            Invoke-InModule {
                $script:ConnectionCache.Clear()
                $script:DbProviderCache.Clear()
                $script:ConnectionCacheTtlMinutes = 5
                $script:ConnectionMockFailPattern = $null
            }
        }

        # LANDMARK: Provider probe cleanup - validate status and cleanup handling
        It "returns MissingProvider without double-close warnings when open fails" {
            $fakeConn = [pscustomobject]@{ State = 0; CloseCalls = 0 }
            $fakeConn | Add-Member -MemberType ScriptMethod -Name Open -Value {
                param($connStr)
                throw [System.Exception]::new('provider missing')
            }
            $fakeConn | Add-Member -MemberType ScriptMethod -Name Close -Value {
                if ($this.State -ne 1) { throw [System.Exception]::new('Operation is not allowed when the object is closed.') }
                $this.State = 0
                $this.CloseCalls++
            }

            $factory = { $fakeConn }
            $result = Invoke-InModule {
                param($path, $provider, $factoryBlock)
                $WarningPreference = 'Stop'
                Invoke-ProviderProbe -DatabasePath $path -Provider $provider -ConnectionFactory $factoryBlock
            } @('C:\\Temp\\missing.accdb', 'Microsoft.ACE.OLEDB.12.0', $factory)

            $result.Status | Should Be 'MissingProvider'
            $result.Message | Should Match 'provider missing'
            $fakeConn.CloseCalls | Should Be 0
        }

        It "returns Available and closes once when the probe succeeds" {
            $fakeConn = [pscustomobject]@{ State = 0; CloseCalls = 0 }
            $fakeConn | Add-Member -MemberType ScriptMethod -Name Open -Value {
                param($connStr)
                $this.State = 1
            }
            $fakeConn | Add-Member -MemberType ScriptMethod -Name Close -Value {
                if ($this.State -ne 1) { throw [System.Exception]::new('Operation is not allowed when the object is closed.') }
                $this.State = 0
                $this.CloseCalls++
            }

            $factory = { $fakeConn }
            $result = Invoke-InModule {
                param($path, $provider, $factoryBlock)
                $WarningPreference = 'Stop'
                Invoke-ProviderProbe -DatabasePath $path -Provider $provider -ConnectionFactory $factoryBlock
            } @('C:\\Temp\\ok.accdb', 'Microsoft.ACE.OLEDB.12.0', $factory)

            $result.Status | Should Be 'Available'
            $fakeConn.CloseCalls | Should Be 1
        }

        It "returns ProbeFailed when the connection factory returns null" {
            $factory = { $null }
            $result = Invoke-InModule {
                param($path, $provider, $factoryBlock)
                $WarningPreference = 'Stop'
                Invoke-ProviderProbe -DatabasePath $path -Provider $provider -ConnectionFactory $factoryBlock
            } @('C:\\Temp\\null.accdb', 'Microsoft.ACE.OLEDB.12.0', $factory)

            $result.Status | Should Be 'ProbeFailed'
            $result.Message | Should Match 'Connection factory returned null'
        }

        It "expires idle cached connections when TTL is zero" {
            Invoke-InModule {
                $script:ConnectionCache.Clear()
                $script:DbProviderCache.Clear()
                $script:ConnectionCacheTtlMinutes = 0
            }
            Invoke-ConnectionMock -FailPattern 'Provider=__none__'
            $dbPath = Join-Path ([System.IO.Path]::GetTempPath()) (([System.Guid]::NewGuid()).ToString() + '.accdb')
            $lease = Invoke-InModule { param($path) Get-CachedDbConnection -DatabasePath $path } @($dbPath)
            $lease.Connection.State | Should Be 1
            Invoke-InModule { param($lease) Release-CachedDbConnection -Lease $lease } @($lease)
            $lease.Connection.State | Should Be 0
            $lease.Connection.CloseCalls | Should Be 1
            $key = Invoke-InModule { param($path) Get-CanonicalDatabaseKey -DatabasePath $path } @($dbPath)
            $entryExists = Invoke-InModule { param($cacheKey) $script:ConnectionCache.ContainsKey($cacheKey) } @($key)
            $entryExists | Should Be False
        }

        It "removes cached connection when force removal is requested" {
            Invoke-InModule {
                $script:ConnectionCache.Clear()
                $script:DbProviderCache.Clear()
                $script:ConnectionCacheTtlMinutes = 10
            }
            Invoke-ConnectionMock -FailPattern 'Provider=__none__'
            $dbPath = Join-Path ([System.IO.Path]::GetTempPath()) (([System.Guid]::NewGuid()).ToString() + '.accdb')
            $lease1 = Invoke-InModule { param($path) Get-CachedDbConnection -DatabasePath $path } @($dbPath)
            $initialConnection = $lease1.Connection
            Invoke-InModule { param($lease) Release-CachedDbConnection -Lease $lease } @($lease1)
            $lease2 = Invoke-InModule { param($path) Get-CachedDbConnection -DatabasePath $path } @($dbPath)
            [object]::ReferenceEquals($initialConnection, $lease2.Connection) | Should Be True
            Invoke-InModule { param($lease) Release-CachedDbConnection -Lease $lease -ForceRemove } @($lease2)
            $initialConnection.State | Should Be 0
            $initialConnection.CloseCalls | Should Be 1
            $lease3 = Invoke-InModule { param($path) Get-CachedDbConnection -DatabasePath $path } @($dbPath)
            [object]::ReferenceEquals($initialConnection, $lease3.Connection) | Should Be False
            Invoke-InModule { param($lease) Release-CachedDbConnection -Lease $lease -ForceRemove } @($lease3)
        }

        It "falls back to next provider candidate when the first fails" {
            Invoke-InModule {
                $script:ConnectionCache.Clear()
                $script:DbProviderCache.Clear()
                $script:ConnectionCacheTtlMinutes = 5
            }
            Invoke-ConnectionMock -FailPattern 'Provider=Microsoft\.ACE\.OLEDB\.12\.0'
            $dbPath = Join-Path ([System.IO.Path]::GetTempPath()) (([System.Guid]::NewGuid()).ToString() + '.accdb')
            $providers = @('Microsoft.ACE.OLEDB.12.0','Microsoft.Jet.OLEDB.4.0')
            $lease = Invoke-InModule { param($path,$candidates) Get-CachedDbConnection -DatabasePath $path -ProviderCandidates $candidates } @($dbPath, $providers)
            $lease.Provider | Should Be 'Microsoft.Jet.OLEDB.4.0'
            $lease.Connection.LastConnectionString | Should Match 'Provider=Microsoft.Jet.OLEDB.4.0'
            $key = Invoke-InModule { param($path) Get-CanonicalDatabaseKey -DatabasePath $path } @($dbPath)
            $cachedProvider = Invoke-InModule { param($cacheKey) if ($script:DbProviderCache.ContainsKey($cacheKey)) { $script:DbProviderCache[$cacheKey] } else { $null } } @($key)
            $cachedProvider | Should Be 'Microsoft.Jet.OLEDB.4.0'
            Invoke-InModule { param($lease) Release-CachedDbConnection -Lease $lease -ForceRemove } @($lease)
        }
    }
}
