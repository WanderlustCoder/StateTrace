# TelemetrySchemaModule.Tests.ps1
# Pester tests for telemetry schema validation and enforcement

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\TelemetrySchemaModule.psm1'
    Import-Module $modulePath -Force
}

Describe 'Schema Registry' {
    BeforeAll {
        $initResult = Initialize-TelemetrySchemaRegistry
    }

    It 'Should initialize schema registry' {
        $initResult.Loaded | Should -BeGreaterOrEqual 0
    }

    It 'Should return schema registry' {
        $registry = Get-TelemetrySchemaRegistry
        $registry | Should -Not -BeNullOrEmpty
    }

    It 'Should get schema for known event type' {
        $initResult = Initialize-TelemetrySchemaRegistry
        if ($initResult.Loaded -gt 0) {
            $registry = Get-TelemetrySchemaRegistry
            $firstEvent = $registry.Keys | Select-Object -First 1
            $schema = Get-TelemetrySchema -EventName $firstEvent

            $schema | Should -Not -BeNullOrEmpty
            $schema.RequiredFields | Should -Not -BeNullOrEmpty
        } else {
            Set-ItResult -Skipped -Because 'No schemas loaded'
        }
    }

    It 'Should return null for unknown event type' {
        $schema = Get-TelemetrySchema -EventName 'NonExistentEventType12345'
        $schema | Should -BeNullOrEmpty
    }
}

Describe 'Event Schema Validation' {
    It 'Should validate event with required fields' {
        $event = @{
            EventName = 'TestEvent'
            Timestamp = (Get-Date).ToString('o')
        }

        $result = Test-TelemetryEventSchema -Event $event

        $result.Valid | Should -Be $true
        $result.EventName | Should -Be 'TestEvent'
    }

    It 'Should fail validation for missing EventName' {
        $event = @{
            Timestamp = (Get-Date).ToString('o')
        }

        $result = Test-TelemetryEventSchema -Event $event

        $result.Valid | Should -Be $false
        $result.Errors | Should -Contain 'Missing required field: EventName'
    }

    It 'Should fail validation for missing Timestamp' {
        $event = @{
            EventName = 'TestEvent'
        }

        $result = Test-TelemetryEventSchema -Event $event

        $result.Valid | Should -Be $false
        $result.Errors | Should -Contain 'Missing required field: Timestamp'
    }

    It 'Should fail validation for invalid Timestamp format' {
        $event = @{
            EventName = 'TestEvent'
            Timestamp = 'not-a-timestamp'
        }

        $result = Test-TelemetryEventSchema -Event $event

        $result.Valid | Should -Be $false
        $result.Errors | Where-Object { $_ -match 'Invalid Timestamp' } | Should -Not -BeNullOrEmpty
    }

    It 'Should validate ParseDuration event' {
        Initialize-TelemetrySchemaRegistry | Out-Null
        $schema = Get-TelemetrySchema -EventName 'ParseDuration'

        if ($schema) {
            $event = @{
                EventName = 'ParseDuration'
                Timestamp = (Get-Date).ToString('o')
                DurationMs = 1500.5
            }

            $result = Test-TelemetryEventSchema -Event ([PSCustomObject]$event)
            $result.Valid | Should -Be $true
        } else {
            Set-ItResult -Skipped -Because 'ParseDuration schema not found'
        }
    }

    It 'Should fail validation for ParseDuration missing DurationMs' {
        Initialize-TelemetrySchemaRegistry | Out-Null
        $schema = Get-TelemetrySchema -EventName 'ParseDuration'

        if ($schema) {
            $event = @{
                EventName = 'ParseDuration'
                Timestamp = (Get-Date).ToString('o')
            }

            $result = Test-TelemetryEventSchema -Event ([PSCustomObject]$event)
            $result.Valid | Should -Be $false
            $result.Errors | Should -Contain 'Missing required field: DurationMs'
        } else {
            Set-ItResult -Skipped -Because 'ParseDuration schema not found'
        }
    }
}

Describe 'Telemetry File Validation' {
    BeforeAll {
        $testDir = Join-Path ([System.IO.Path]::GetTempPath()) 'TelemetrySchemaTests'
        if (-not (Test-Path $testDir)) {
            New-Item -Path $testDir -ItemType Directory -Force | Out-Null
        }
    }

    AfterAll {
        $testDir = Join-Path ([System.IO.Path]::GetTempPath()) 'TelemetrySchemaTests'
        if (Test-Path $testDir) {
            Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Should validate telemetry file with valid events' {
        $testFile = Join-Path ([System.IO.Path]::GetTempPath()) 'TelemetrySchemaTests\valid.json'
        $events = @(
            '{"EventName":"TestEvent1","Timestamp":"2025-01-01T12:00:00Z"}',
            '{"EventName":"TestEvent2","Timestamp":"2025-01-01T12:01:00Z"}'
        )
        $events | Set-Content -Path $testFile -Encoding UTF8

        $result = Test-TelemetryFile -Path $testFile

        $result.TotalEvents | Should -Be 2
        $result.ValidEvents | Should -Be 2
        $result.InvalidEvents | Should -Be 0
        $result.ValidationRate | Should -Be 100
    }

    It 'Should detect invalid events in file' {
        $testFile = Join-Path ([System.IO.Path]::GetTempPath()) 'TelemetrySchemaTests\invalid.json'
        $events = @(
            '{"EventName":"TestEvent1","Timestamp":"2025-01-01T12:00:00Z"}',
            '{"Timestamp":"2025-01-01T12:01:00Z"}',  # Missing EventName
            '{"EventName":"TestEvent3","Timestamp":"2025-01-01T12:02:00Z"}'
        )
        $events | Set-Content -Path $testFile -Encoding UTF8

        $result = Test-TelemetryFile -Path $testFile

        $result.TotalEvents | Should -Be 3
        $result.ValidEvents | Should -Be 2
        $result.InvalidEvents | Should -Be 1
    }

    It 'Should handle malformed JSON' {
        $testFile = Join-Path ([System.IO.Path]::GetTempPath()) 'TelemetrySchemaTests\malformed.json'
        $events = @(
            '{"EventName":"TestEvent1","Timestamp":"2025-01-01T12:00:00Z"}',
            'not valid json',
            '{"EventName":"TestEvent3","Timestamp":"2025-01-01T12:02:00Z"}'
        )
        $events | Set-Content -Path $testFile -Encoding UTF8

        $result = Test-TelemetryFile -Path $testFile

        $result.InvalidEvents | Should -BeGreaterThan 0
        $result.Errors.Count | Should -BeGreaterThan 0
    }

    It 'Should return error for non-existent file' {
        $result = Test-TelemetryFile -Path 'C:\NonExistent\fake.json'

        $result.TotalEvents | Should -Be 0
        $result.Errors | Should -Not -BeNullOrEmpty
    }
}

Describe 'Required Field Enforcement' {
    It 'Should return required fields for known event' {
        Initialize-TelemetrySchemaRegistry | Out-Null
        $schema = Get-TelemetrySchema -EventName 'ParseDuration'

        if ($schema) {
            $required = Get-RequiredFields -EventName 'ParseDuration'
            $required | Should -Contain 'EventName'
            $required | Should -Contain 'Timestamp'
            $required | Should -Contain 'DurationMs'
        } else {
            Set-ItResult -Skipped -Because 'ParseDuration schema not found'
        }
    }

    It 'Should return default required fields for unknown event' {
        $required = Get-RequiredFields -EventName 'UnknownEventType12345'
        $required | Should -Contain 'EventName'
        $required | Should -Contain 'Timestamp'
    }

    It 'Should pass assertion for valid payload' {
        # Use an event that might have only basic requirements
        { Assert-RequiredFields -EventName 'TestEvent' -Payload @{ SomeField = 'value' } } |
            Should -Not -Throw
    }

    It 'Should throw for missing required fields' {
        Initialize-TelemetrySchemaRegistry | Out-Null
        $schema = Get-TelemetrySchema -EventName 'DiffUsageRate'

        if ($schema) {
            { Assert-RequiredFields -EventName 'DiffUsageRate' -Payload @{} } |
                Should -Throw '*Missing required fields*'
        } else {
            Set-ItResult -Skipped -Because 'DiffUsageRate schema not found'
        }
    }
}

Describe 'Event Catalog Generation' {
    It 'Should return event catalog' {
        Initialize-TelemetrySchemaRegistry | Out-Null
        $catalog = Get-TelemetryEventCatalog

        $catalog | Should -Not -BeNullOrEmpty
    }

    It 'Should generate markdown catalog' {
        Initialize-TelemetrySchemaRegistry | Out-Null
        $markdown = New-TelemetryEventCatalogMarkdown

        $markdown | Should -Not -BeNullOrEmpty
        $markdown | Should -Match '# StateTrace Telemetry Event Catalog'
        $markdown | Should -Match 'Event Types'
    }

    It 'Should write catalog to file' {
        $outputPath = Join-Path ([System.IO.Path]::GetTempPath()) 'TelemetrySchemaTests\catalog.md'

        $result = New-TelemetryEventCatalogMarkdown -OutputPath $outputPath

        $result.Path | Should -Be $outputPath
        Test-Path $outputPath | Should -Be $true

        Remove-Item $outputPath -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Schema Version Management' {
    It 'Should return schema version' {
        $version = Get-TelemetrySchemaVersion

        $version.Current | Should -Not -BeNullOrEmpty
        $version.MinCompatible | Should -Not -BeNullOrEmpty
    }

    It 'Should test compatible version' {
        $result = Test-SchemaVersionCompatibility -Version '1.0.0'

        $result.Compatible | Should -Be $true
    }

    It 'Should test incompatible version' {
        $result = Test-SchemaVersionCompatibility -Version '0.1.0'

        $result.Compatible | Should -Be $false
    }

    It 'Should handle invalid version format' {
        $result = Test-SchemaVersionCompatibility -Version 'not-a-version'

        $result.Compatible | Should -Be $false
        $result.Error | Should -Not -BeNullOrEmpty
    }

    It 'Should add schema version to payload' {
        $payload = @{ TestField = 'value' }
        $result = Add-SchemaVersionToEvent -Payload $payload

        $result.SchemaVersion | Should -Not -BeNullOrEmpty
    }
}

Describe 'Schema Migration' {
    BeforeAll {
        $testDir = Join-Path ([System.IO.Path]::GetTempPath()) 'TelemetrySchemaTests'
        if (-not (Test-Path $testDir)) {
            New-Item -Path $testDir -ItemType Directory -Force | Out-Null
        }
    }

    AfterAll {
        $testDir = Join-Path ([System.IO.Path]::GetTempPath()) 'TelemetrySchemaTests'
        if (Test-Path $testDir) {
            Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Should migrate field names' {
        $testFile = Join-Path ([System.IO.Path]::GetTempPath()) 'TelemetrySchemaTests\migrate_source.json'
        $outputFile = Join-Path ([System.IO.Path]::GetTempPath()) 'TelemetrySchemaTests\migrate_output.json'

        $events = @(
            '{"EventName":"TestEvent","Timestamp":"2025-01-01T12:00:00Z","OldField":"value1"}',
            '{"EventName":"TestEvent","Timestamp":"2025-01-01T12:01:00Z","OldField":"value2"}'
        )
        $events | Set-Content -Path $testFile -Encoding UTF8

        $result = Update-TelemetryEventSchema `
            -Path $testFile `
            -OutputPath $outputFile `
            -FieldMappings @{ OldField = 'NewField' }

        $result.TotalEvents | Should -Be 2
        $result.MigratedEvents | Should -Be 2

        $content = Get-Content $outputFile -Raw
        $content | Should -Match 'NewField'
        $content | Should -Not -Match '"OldField"'

        Remove-Item $testFile, $outputFile -Force -ErrorAction SilentlyContinue
    }

    It 'Should add default values' {
        $testFile = Join-Path ([System.IO.Path]::GetTempPath()) 'TelemetrySchemaTests\default_source.json'
        $outputFile = Join-Path ([System.IO.Path]::GetTempPath()) 'TelemetrySchemaTests\default_output.json'

        $events = @(
            '{"EventName":"TestEvent","Timestamp":"2025-01-01T12:00:00Z"}'
        )
        $events | Set-Content -Path $testFile -Encoding UTF8

        $result = Update-TelemetryEventSchema `
            -Path $testFile `
            -OutputPath $outputFile `
            -DefaultValues @{ NewRequiredField = 'default_value' }

        $result.MigratedEvents | Should -Be 1

        $content = Get-Content $outputFile -Raw
        $content | Should -Match 'NewRequiredField'
        $content | Should -Match 'default_value'

        Remove-Item $testFile, $outputFile -Force -ErrorAction SilentlyContinue
    }

    It 'Should fail for non-existent file' {
        { Update-TelemetryEventSchema -Path 'C:\NonExistent\fake.json' } |
            Should -Throw '*File not found*'
    }
}

Describe 'Module Exports' {
    It 'Should export all required functions' {
        $exportedFunctions = (Get-Module TelemetrySchemaModule).ExportedFunctions.Keys

        $requiredFunctions = @(
            'Initialize-TelemetrySchemaRegistry',
            'Get-TelemetrySchemaRegistry',
            'Get-TelemetrySchema',
            'Test-TelemetryEventSchema',
            'Test-TelemetryFile',
            'Get-RequiredFields',
            'Assert-RequiredFields',
            'Write-ValidatedTelemetryEvent',
            'Get-TelemetryEventCatalog',
            'New-TelemetryEventCatalogMarkdown',
            'Get-TelemetrySchemaVersion',
            'Test-SchemaVersionCompatibility',
            'Update-TelemetryEventSchema',
            'Test-EventSchemaVersion',
            'Add-SchemaVersionToEvent'
        )

        foreach ($func in $requiredFunctions) {
            $exportedFunctions | Should -Contain $func
        }
    }
}
