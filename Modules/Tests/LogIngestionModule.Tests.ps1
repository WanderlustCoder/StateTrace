Set-StrictMode -Version Latest

Describe "LogIngestionModule" {
    BeforeAll {
        $modulePath = Join-Path (Split-Path $PSCommandPath) "..\\LogIngestionModule.psm1"
        Import-Module (Resolve-Path $modulePath) -Force
        $script:TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
        $script:RawDir = Join-Path $script:TempRoot 'Logs'
        $script:ExtractedDir = Join-Path $script:RawDir 'Extracted'
        New-Item -ItemType Directory -Path $script:ExtractedDir -Force | Out-Null
        $script:Combined = Join-Path $script:RawDir 'combined.log'
        $sampleLines = @(
            'hostname switch1',
            'switch1# show version',
            'Line from switch1',
            'switch1# show interfaces',
            'hostname switch-two',
            'switch-two>show version',
            'Details from switch two'
        )
        $sampleLines | Set-Content -Path $script:Combined -Encoding UTF8
    }

    AfterAll {
        Remove-Module LogIngestionModule -Force
        if (Test-Path $script:TempRoot) {
            Remove-Item -Path $script:TempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "splits combined logs into per-host files" {
        LogIngestionModule\Split-RawLogs -LogPath $script:RawDir -ExtractedPath $script:ExtractedDir
        $files = Get-ChildItem -Path $script:ExtractedDir -File | Select-Object -ExpandProperty Name
        ($files -contains 'switch1.log') | Should Be True
        ($files -contains 'switch-two.log') | Should Be True
        (@($files | Where-Object { $_ -eq '_unknown.log' })).Count | Should Be 0
    }

    It "clears extracted log files" {
        LogIngestionModule\Split-RawLogs -LogPath $script:RawDir -ExtractedPath $script:ExtractedDir
        LogIngestionModule\Clear-ExtractedLogs -ExtractedPath $script:ExtractedDir
        (@(Get-ChildItem -Path $script:ExtractedDir -File)).Count | Should Be 0
    }
}

