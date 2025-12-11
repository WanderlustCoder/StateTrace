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
            'switch-two(config)# show version',
            'Details from switch two',
            'hostname switch-two',
            'switch-two>show interfaces',
            'More details from switch two'
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

    It "detects host prompts with commands and config context" {
        LogIngestionModule\Split-RawLogs -LogPath $script:RawDir -ExtractedPath $script:ExtractedDir
        $switch1Path = Join-Path $script:ExtractedDir 'switch1.log'
        $switch2Path = Join-Path $script:ExtractedDir 'switch-two.log'
        $switch1Content = Get-Content -LiteralPath $switch1Path -Raw
        $switch2Content = Get-Content -LiteralPath $switch2Path -Raw
        $switch2Content | Should Match 'switch-two\(config\)# show version'
        $switch1Content | Should Not Match 'switch-two\(config\)# show version'
    }

    It "starts with a clean extracted directory" {
        $oldSlice = Join-Path $script:ExtractedDir 'switch1.log'
        Set-Content -LiteralPath $oldSlice -Value 'old content' -Encoding UTF8
        LogIngestionModule\Split-RawLogs -LogPath $script:RawDir -ExtractedPath $script:ExtractedDir
        (Get-Content -LiteralPath $oldSlice -Raw) | Should Not Match 'old content'
    }

    It "clears extracted log files" {
        LogIngestionModule\Split-RawLogs -LogPath $script:RawDir -ExtractedPath $script:ExtractedDir
        LogIngestionModule\Clear-ExtractedLogs -ExtractedPath $script:ExtractedDir
        (@(Get-ChildItem -Path $script:ExtractedDir -File)).Count | Should Be 0
    }
}
