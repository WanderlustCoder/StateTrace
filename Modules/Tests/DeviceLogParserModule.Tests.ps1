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
}

