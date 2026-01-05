#Requires -Modules Pester
<#
.SYNOPSIS
Pester tests for MainWindow.Services.psm1

.DESCRIPTION
ST-L-004/ST-O-004: Tests for the extracted MainWindow service layer.
#>

$modulePath = Join-Path $PSScriptRoot '..\MainWindow.Services.psm1'
Import-Module $modulePath -Force

Describe 'MainWindow.Services Module' -Tag 'Decomposition', 'Services' {

    Context 'Initialize-MainWindowServices' {

        It 'Returns initialized state with repository root' {
            $tempRoot = Join-Path $TestDrive 'TestRepo'
            New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

            $result = Initialize-MainWindowServices -RepositoryRoot $tempRoot

            $result.Initialized | Should Be $true
            $result.RepositoryRoot | Should Be $tempRoot
            $result.SettingsPath | Should Match 'StateTraceSettings\.json$'
        }

        It 'Uses custom settings path when provided' {
            $tempRoot = Join-Path $TestDrive 'TestRepo2'
            $customPath = Join-Path $TestDrive 'custom-settings.json'
            New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

            $result = Initialize-MainWindowServices -RepositoryRoot $tempRoot -SettingsPath $customPath

            $result.SettingsPath | Should Be $customPath
        }
    }

    Context 'Get-StateTraceSettings' {

        BeforeEach {
            $script:tempRoot = Join-Path $TestDrive 'SettingsRepo'
            $dataDir = Join-Path $script:tempRoot 'Data'
            New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
            Initialize-MainWindowServices -RepositoryRoot $script:tempRoot | Out-Null
        }

        It 'Returns empty hashtable when settings file does not exist' {
            $result = Get-StateTraceSettings

            $result | Should BeOfType [hashtable]
            $result.Count | Should Be 0
        }

        It 'Loads settings from JSON file' {
            $settingsPath = Join-Path $script:tempRoot 'Data\StateTraceSettings.json'
            $testSettings = @{ Theme = 'dark'; LastSite = 'WLLS' }
            $testSettings | ConvertTo-Json | Out-File -LiteralPath $settingsPath -Encoding utf8

            $result = Get-StateTraceSettings

            $result['Theme'] | Should Be 'dark'
            $result['LastSite'] | Should Be 'WLLS'
        }

        It 'Returns empty hashtable on invalid JSON' {
            $settingsPath = Join-Path $script:tempRoot 'Data\StateTraceSettings.json'
            'not valid json {{{' | Out-File -LiteralPath $settingsPath -Encoding utf8

            $result = Get-StateTraceSettings

            $result | Should BeOfType [hashtable]
            $result.Count | Should Be 0
        }
    }

    Context 'Set-StateTraceSettings' {

        BeforeEach {
            $script:tempRoot2 = Join-Path $TestDrive 'SettingsRepo2'
            New-Item -ItemType Directory -Path $script:tempRoot2 -Force | Out-Null
            Initialize-MainWindowServices -RepositoryRoot $script:tempRoot2 | Out-Null
        }

        It 'Saves settings to JSON file' {
            $testSettings = @{ Theme = 'blue'; WindowWidth = 1200 }

            $result = Set-StateTraceSettings -Settings $testSettings

            $result | Should Be $true

            $settingsPath = Join-Path $script:tempRoot2 'Data\StateTraceSettings.json'
            $settingsPath | Should Exist
            $loaded = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
            $loaded.Theme | Should Be 'blue'
            $loaded.WindowWidth | Should Be 1200
        }

        It 'Creates Data directory if it does not exist' {
            $newRoot = Join-Path $TestDrive 'NewRepo'
            New-Item -ItemType Directory -Path $newRoot -Force | Out-Null
            Initialize-MainWindowServices -RepositoryRoot $newRoot | Out-Null

            $result = Set-StateTraceSettings -Settings @{ Test = 'value' }

            $result | Should Be $true
            (Join-Path $newRoot 'Data') | Should Exist
        }
    }

    Context 'Publish-UserActionTelemetry' {

        It 'Returns payload with timestamp' {
            $result = Publish-UserActionTelemetry -Action 'TabSwitch' -Site 'WLLS'

            $result | Should Not BeNullOrEmpty
            $result.Timestamp | Should Not BeNullOrEmpty
            $result.Action | Should Be 'TabSwitch'
            $result.Site | Should Be 'WLLS'
        }

        It 'Includes all provided parameters' {
            $result = Publish-UserActionTelemetry -Action 'Search' -Site 'BOYO' -Hostname 'BOYO-SW-01' -Context 'InterfacesView'

            $result.Action | Should Be 'Search'
            $result.Site | Should Be 'BOYO'
            $result.Hostname | Should Be 'BOYO-SW-01'
            $result.Context | Should Be 'InterfacesView'
        }

        It 'Omits empty parameters from payload' {
            $result = Publish-UserActionTelemetry -Action 'Export'

            ($result.Keys -contains 'Action') | Should Be $true
            ($result.Keys -contains 'Timestamp') | Should Be $true
            ($result.Keys -contains 'Site') | Should Be $false
            ($result.Keys -contains 'Hostname') | Should Be $false
        }
    }

    Context 'Get-SiteIngestionInfo' {

        BeforeEach {
            $script:ingestionRoot = Join-Path $TestDrive 'IngestionRepo'
            $historyDir = Join-Path $script:ingestionRoot 'Data\IngestionHistory'
            New-Item -ItemType Directory -Path $historyDir -Force | Out-Null
            Initialize-MainWindowServices -RepositoryRoot $script:ingestionRoot | Out-Null
        }

        It 'Returns null when site is whitespace' {
            $result = Get-SiteIngestionInfo -Site '   '

            $result | Should BeNullOrEmpty
        }

        It 'Returns null when history file does not exist' {
            $result = Get-SiteIngestionInfo -Site 'NONEXISTENT'

            $result | Should BeNullOrEmpty
        }

        It 'Returns ingestion info from history file' {
            $historyPath = Join-Path $script:ingestionRoot 'Data\IngestionHistory\WLLS.json'
            $entries = @(
                @{ LastIngestedUtc = '2025-01-01T10:00:00Z'; SiteCacheProvider = 'SharedCache' }
                @{ LastIngestedUtc = '2025-01-02T12:00:00Z'; SiteCacheProvider = 'Database' }
            )
            $entries | ConvertTo-Json | Out-File -LiteralPath $historyPath -Encoding utf8

            $result = Get-SiteIngestionInfo -Site 'WLLS'

            $result | Should Not BeNullOrEmpty
            $result.Site | Should Be 'WLLS'
            $result.Source | Should Be 'Database'
            $result.LastIngestedUtc | Should BeOfType [datetime]
        }
    }

    Context 'Get-FreshnessStatus' {

        It 'Returns Green for fresh data (< 24 hours)' {
            $recent = [datetime]::UtcNow.AddHours(-2)

            $result = Get-FreshnessStatus -LastIngestedUtc $recent

            $result.Color | Should Be 'Green'
            $result.StatusText | Should Match 'Fresh'
        }

        It 'Returns Yellow for warning data (24-48 hours)' {
            $warning = [datetime]::UtcNow.AddHours(-30)

            $result = Get-FreshnessStatus -LastIngestedUtc $warning

            $result.Color | Should Be 'Yellow'
            $result.StatusText | Should Match 'Warning'
        }

        It 'Returns Orange for stale data (2-7 days)' {
            $stale = [datetime]::UtcNow.AddDays(-4)

            $result = Get-FreshnessStatus -LastIngestedUtc $stale

            $result.Color | Should Be 'Orange'
            $result.StatusText | Should Match 'Stale'
        }

        It 'Returns Red for very stale data (> 7 days)' {
            $veryStale = [datetime]::UtcNow.AddDays(-10)

            $result = Get-FreshnessStatus -LastIngestedUtc $veryStale

            $result.Color | Should Be 'Red'
            $result.StatusText | Should Match 'Very stale'
        }

        It 'Formats age text correctly for minutes' {
            $recent = [datetime]::UtcNow.AddMinutes(-30)

            $result = Get-FreshnessStatus -LastIngestedUtc $recent

            $result.AgeText | Should Match 'min ago'
        }

        It 'Formats age text correctly for hours' {
            $hours = [datetime]::UtcNow.AddHours(-5)

            $result = Get-FreshnessStatus -LastIngestedUtc $hours

            $result.AgeText | Should Match 'h ago'
        }

        It 'Formats age text correctly for days' {
            $days = [datetime]::UtcNow.AddDays(-3)

            $result = Get-FreshnessStatus -LastIngestedUtc $days

            $result.AgeText | Should Match 'd ago'
        }
    }

    Context 'Get-ParserLogTail' {

        It 'Returns null when log file does not exist' {
            $result = Get-ParserLogTail -LogPath (Join-Path $TestDrive 'nonexistent.log')

            $result | Should BeNullOrEmpty
        }

        It 'Returns last N lines from log file' {
            $logPath = Join-Path $TestDrive 'test.log'
            1..50 | ForEach-Object { "Line $_" } | Out-File -LiteralPath $logPath -Encoding utf8

            $result = Get-ParserLogTail -LogPath $logPath -Lines 5

            $result | Should Not BeNullOrEmpty
            (($result -split "`n").Count -le 5) | Should Be $true
            $result | Should Match 'Line 50'
        }
    }

    Context 'Get-ParserJobStatus' {

        It 'Returns None state when job is null' {
            $result = Get-ParserJobStatus -Job $null

            $result.State | Should Be 'None'
            $result.HasOutput | Should Be $false
            $result.HasError | Should Be $false
        }
    }

    Context 'Get-LatestPipelineLogPath' {

        BeforeEach {
            $script:logRoot = Join-Path $TestDrive 'LogRepo'
            New-Item -ItemType Directory -Path $script:logRoot -Force | Out-Null
            Initialize-MainWindowServices -RepositoryRoot $script:logRoot | Out-Null
        }

        It 'Returns null when logs directory does not exist' {
            $result = Get-LatestPipelineLogPath

            $result | Should BeNullOrEmpty
        }

        It 'Returns latest log file path' {
            $logsDir = Join-Path $script:logRoot 'Logs\Verification'
            New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
            'log1' | Out-File (Join-Path $logsDir 'old.log') -Encoding utf8
            Start-Sleep -Milliseconds 100
            'log2' | Out-File (Join-Path $logsDir 'new.log') -Encoding utf8

            $result = Get-LatestPipelineLogPath

            $result | Should Not BeNullOrEmpty
            $result | Should Match 'new\.log$'
        }
    }
}
