Set-StrictMode -Version Latest

Describe "DeviceLogParserModule" {
    BeforeAll {
        $modulePath = Join-Path (Split-Path $PSCommandPath) "..\\DeviceLogParserModule.psm1"
        Import-Module (Resolve-Path $modulePath) -Force
    }

    AfterAll {
        Remove-Module DeviceLogParserModule -Force
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

    It "caches vendor templates within the module" {
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
        $null = New-Item -ItemType Directory -Path $tempDir -Force
        $jsonPath = Join-Path $tempDir 'UnitTest.json'
        try {
            Set-Content -Path $jsonPath -Value '{"templates":["alpha"]}' -Encoding UTF8
            $first = DeviceLogParserModule\Get-VendorTemplates -Vendor 'UnitTest' -TemplatesRoot $tempDir
            $first.Length | Should BeGreaterThan 0
            ($first | Select-Object -First 1) | Should Be 'alpha'

            Set-Content -Path $jsonPath -Value '{"templates":["beta"]}' -Encoding UTF8
            $second = DeviceLogParserModule\Get-VendorTemplates -Vendor 'UnitTest' -TemplatesRoot $tempDir
            ($second | Select-Object -First 1) | Should Be 'alpha'
        } finally {
            $module = Get-Module DeviceLogParserModule
            if ($module) { $module.Invoke({ param($key) if ($script:VendorTemplatesCache.ContainsKey($key)) { $script:VendorTemplatesCache.Remove($key) | Out-Null } }, 'UnitTest') }
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

}

