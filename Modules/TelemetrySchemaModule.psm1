# TelemetrySchemaModule.psm1
# Schema validation, required field enforcement, and event catalog management

Set-StrictMode -Version Latest

#region Schema Version
$script:SchemaVersion = '1.0.0'
$script:MinCompatibleVersion = '1.0.0'
#endregion

#region Schema Registry
$script:SchemaRegistry = @{}
$script:SchemaPath = $null
$script:EventCatalog = @{}

function Initialize-TelemetrySchemaRegistry {
    [CmdletBinding()]
    param(
        [string]$SchemaDirectory
    )

    if ([string]::IsNullOrWhiteSpace($SchemaDirectory)) {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $SchemaDirectory = Join-Path $projectRoot 'docs\schemas\telemetry\events'
    }

    $script:SchemaPath = $SchemaDirectory
    $script:SchemaRegistry = @{}
    $script:EventCatalog = @{}

    if (-not (Test-Path -LiteralPath $SchemaDirectory)) {
        Write-Warning "Schema directory not found: $SchemaDirectory"
        return @{
            Loaded = 0
            Errors = @("Schema directory not found: $SchemaDirectory")
        }
    }

    $schemaFiles = Get-ChildItem -Path $SchemaDirectory -Filter '*.schema.json' -ErrorAction SilentlyContinue
    $loaded = 0
    $errors = @()

    foreach ($file in $schemaFiles) {
        try {
            $content = Get-Content -Path $file.FullName -Raw -Encoding UTF8
            $schema = $content | ConvertFrom-Json

            $eventName = $null
            if ($schema.properties -and $schema.properties.EventName -and $schema.properties.EventName.const) {
                $eventName = $schema.properties.EventName.const
            } else {
                $eventName = $file.BaseName -replace '\.schema$', '' -replace '_', ''
                $eventName = (Get-Culture).TextInfo.ToTitleCase($eventName.ToLower()) -replace ' ', ''
            }

            $script:SchemaRegistry[$eventName] = @{
                Schema = $schema
                FilePath = $file.FullName
                RequiredFields = @($schema.required)
                Title = $schema.title
                Description = $schema.description
            }

            $script:EventCatalog[$eventName] = @{
                Name = $eventName
                Title = $schema.title
                Description = $schema.description
                RequiredFields = @($schema.required)
                Properties = $schema.properties
                SchemaFile = $file.Name
            }

            $loaded++
        } catch {
            $errors += "Failed to load schema $($file.Name): $($_.Exception.Message)"
        }
    }

    return @{
        Loaded = $loaded
        Errors = $errors
        SchemaDirectory = $SchemaDirectory
    }
}

function Get-TelemetrySchemaRegistry {
    [CmdletBinding()]
    param()

    if ($script:SchemaRegistry.Count -eq 0) {
        Initialize-TelemetrySchemaRegistry | Out-Null
    }

    return $script:SchemaRegistry.Clone()
}

function Get-TelemetrySchema {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$EventName
    )

    if ($script:SchemaRegistry.Count -eq 0) {
        Initialize-TelemetrySchemaRegistry | Out-Null
    }

    if ($script:SchemaRegistry.ContainsKey($EventName)) {
        return $script:SchemaRegistry[$EventName]
    }

    return $null
}
#endregion

#region Schema Validation
function Test-TelemetryEventSchema {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$Event,

        [switch]$Strict
    )

    process {
        $result = @{
            Valid = $true
            EventName = $null
            Errors = @()
            Warnings = @()
        }

        # Check basic envelope
        if (-not $Event.EventName) {
            $result.Valid = $false
            $result.Errors += 'Missing required field: EventName'
            return [PSCustomObject]$result
        }

        $result.EventName = $Event.EventName

        if (-not $Event.Timestamp) {
            $result.Valid = $false
            $result.Errors += 'Missing required field: Timestamp'
        } else {
            # Validate timestamp format
            try {
                [datetime]::Parse($Event.Timestamp) | Out-Null
            } catch {
                $result.Valid = $false
                $result.Errors += "Invalid Timestamp format: $($Event.Timestamp)"
            }
        }

        # Get schema for this event type
        $schema = Get-TelemetrySchema -EventName $Event.EventName

        if (-not $schema) {
            if ($Strict) {
                $result.Valid = $false
                $result.Errors += "No schema found for event type: $($Event.EventName)"
            } else {
                $result.Warnings += "No schema found for event type: $($Event.EventName)"
            }
            return [PSCustomObject]$result
        }

        # Validate required fields
        foreach ($required in $schema.RequiredFields) {
            $propValue = $Event.PSObject.Properties[$required]
            if (-not $propValue -or $null -eq $propValue.Value) {
                $result.Valid = $false
                $result.Errors += "Missing required field: $required"
            }
        }

        # Validate field types if schema has property definitions
        if ($schema.Schema.properties) {
            $eventProps = @{}
            if ($Event -is [hashtable]) {
                $eventProps = $Event
            } else {
                foreach ($prop in $Event.PSObject.Properties) {
                    $eventProps[$prop.Name] = $prop.Value
                }
            }

            foreach ($propName in $eventProps.Keys) {
                $propDef = $schema.Schema.properties.$propName
                if (-not $propDef) { continue }

                $value = $eventProps[$propName]
                if ($null -eq $value) { continue }

                # Type validation
                $expectedType = $propDef.type
                $actualType = $value.GetType().Name

                $typeValid = $true
                switch ($expectedType) {
                    'string' {
                        if ($value -isnot [string]) {
                            $typeValid = $false
                        }
                    }
                    'integer' {
                        if ($value -isnot [int] -and $value -isnot [long] -and $value -isnot [int32] -and $value -isnot [int64]) {
                            $typeValid = $false
                        }
                    }
                    'number' {
                        if ($value -isnot [int] -and $value -isnot [long] -and $value -isnot [double] -and $value -isnot [decimal] -and $value -isnot [float]) {
                            $typeValid = $false
                        }
                    }
                    'boolean' {
                        if ($value -isnot [bool]) {
                            $typeValid = $false
                        }
                    }
                    'object' {
                        if ($value -isnot [hashtable] -and $value -isnot [PSCustomObject]) {
                            $typeValid = $false
                        }
                    }
                    'array' {
                        if ($value -isnot [array] -and $value -isnot [System.Collections.IEnumerable]) {
                            $typeValid = $false
                        }
                    }
                }

                if (-not $typeValid) {
                    $result.Warnings += "Field '$propName' has type '$actualType', expected '$expectedType'"
                }

                # Enum validation
                if ($propDef.enum -and $value -notin $propDef.enum) {
                    $result.Valid = $false
                    $result.Errors += "Field '$propName' value '$value' not in allowed values: $($propDef.enum -join ', ')"
                }

                # Minimum validation for numbers
                if ($null -ne $propDef.minimum -and $value -lt $propDef.minimum) {
                    $result.Valid = $false
                    $result.Errors += "Field '$propName' value $value is below minimum $($propDef.minimum)"
                }

                # MinLength for strings
                if ($null -ne $propDef.minLength -and $value -is [string] -and $value.Length -lt $propDef.minLength) {
                    $result.Valid = $false
                    $result.Errors += "Field '$propName' length $($value.Length) is below minimum $($propDef.minLength)"
                }
            }
        }

        return [PSCustomObject]$result
    }
}

function Test-TelemetryFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [switch]$Strict,

        [int]$MaxErrors = 100
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return @{
            Path = $Path
            TotalEvents = 0
            ValidEvents = 0
            InvalidEvents = 0
            Errors = @("File not found: $Path")
            ValidationRate = 0
        }
    }

    $results = @{
        Path = $Path
        TotalEvents = 0
        ValidEvents = 0
        InvalidEvents = 0
        Errors = [System.Collections.Generic.List[object]]::new()
        EventTypes = @{}
        ValidationRate = 0
    }

    $lineNumber = 0
    foreach ($line in [System.IO.File]::ReadLines($Path)) {
        $lineNumber++
        if ([string]::IsNullOrWhiteSpace($line)) { continue }

        try {
            $event = $line | ConvertFrom-Json
            $results.TotalEvents++

            $validation = Test-TelemetryEventSchema -Event $event -Strict:$Strict

            if ($validation.Valid) {
                $results.ValidEvents++
            } else {
                $results.InvalidEvents++
                if ($results.Errors.Count -lt $MaxErrors) {
                    $results.Errors.Add(@{
                        Line = $lineNumber
                        EventName = $validation.EventName
                        Errors = $validation.Errors
                    })
                }
            }

            # Track event types
            $eventName = $event.EventName
            if ($eventName) {
                if (-not $results.EventTypes.ContainsKey($eventName)) {
                    $results.EventTypes[$eventName] = 0
                }
                $results.EventTypes[$eventName]++
            }
        } catch {
            $results.InvalidEvents++
            if ($results.Errors.Count -lt $MaxErrors) {
                $results.Errors.Add(@{
                    Line = $lineNumber
                    EventName = $null
                    Errors = @("JSON parse error: $($_.Exception.Message)")
                })
            }
        }
    }

    if ($results.TotalEvents -gt 0) {
        $results.ValidationRate = [math]::Round(($results.ValidEvents / $results.TotalEvents) * 100, 2)
    }

    return [PSCustomObject]$results
}
#endregion

#region Required Field Enforcement
function Get-RequiredFields {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$EventName
    )

    $schema = Get-TelemetrySchema -EventName $EventName
    if ($schema) {
        return $schema.RequiredFields
    }

    # Default required fields for unknown events
    return @('EventName', 'Timestamp')
}

function Assert-RequiredFields {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$EventName,

        [Parameter(Mandatory)]
        [hashtable]$Payload
    )

    $required = Get-RequiredFields -EventName $EventName
    $missing = @()

    foreach ($field in $required) {
        if ($field -eq 'EventName' -or $field -eq 'Timestamp') {
            continue  # These are added by the wrapper
        }

        if (-not $Payload.ContainsKey($field) -or $null -eq $Payload[$field]) {
            $missing += $field
        }
    }

    if ($missing.Count -gt 0) {
        throw "Missing required fields for $EventName event: $($missing -join ', ')"
    }

    return $true
}

function Write-ValidatedTelemetryEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [hashtable]$Payload,

        [switch]$SkipValidation
    )

    if (-not $SkipValidation) {
        Assert-RequiredFields -EventName $Name -Payload $Payload
    }

    # Import TelemetryModule if not loaded
    $telemetryModule = Get-Module -Name 'TelemetryModule' -ErrorAction SilentlyContinue
    if (-not $telemetryModule) {
        $modulePath = Join-Path $PSScriptRoot 'TelemetryModule.psm1'
        if (Test-Path $modulePath) {
            Import-Module $modulePath -Force
        }
    }

    Write-StTelemetryEvent -Name $Name -Payload $Payload
}
#endregion

#region Event Catalog Generation
function Get-TelemetryEventCatalog {
    [CmdletBinding()]
    param()

    if ($script:EventCatalog.Count -eq 0) {
        Initialize-TelemetrySchemaRegistry | Out-Null
    }

    return $script:EventCatalog.Clone()
}

function New-TelemetryEventCatalogMarkdown {
    [CmdletBinding()]
    param(
        [string]$OutputPath
    )

    if ($script:EventCatalog.Count -eq 0) {
        Initialize-TelemetrySchemaRegistry | Out-Null
    }

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('# StateTrace Telemetry Event Catalog')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    [void]$sb.AppendLine("Schema Version: $script:SchemaVersion")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('---')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## Event Types')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('| Event Name | Description | Required Fields |')
    [void]$sb.AppendLine('|------------|-------------|-----------------|')

    foreach ($eventName in ($script:EventCatalog.Keys | Sort-Object)) {
        $event = $script:EventCatalog[$eventName]
        $required = ($event.RequiredFields | Where-Object { $_ -ne 'EventName' -and $_ -ne 'Timestamp' }) -join ', '
        if ([string]::IsNullOrWhiteSpace($required)) { $required = '-' }
        $desc = if ($event.Description) { $event.Description.Substring(0, [Math]::Min(60, $event.Description.Length)) } else { '-' }
        [void]$sb.AppendLine("| $eventName | $desc | $required |")
    }

    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('---')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## Event Details')
    [void]$sb.AppendLine('')

    foreach ($eventName in ($script:EventCatalog.Keys | Sort-Object)) {
        $event = $script:EventCatalog[$eventName]
        [void]$sb.AppendLine("### $eventName")
        [void]$sb.AppendLine('')
        if ($event.Description) {
            [void]$sb.AppendLine($event.Description)
            [void]$sb.AppendLine('')
        }
        [void]$sb.AppendLine("**Schema File:** ``$($event.SchemaFile)``")
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('**Required Fields:**')
        foreach ($field in $event.RequiredFields) {
            [void]$sb.AppendLine("- ``$field``")
        }
        [void]$sb.AppendLine('')

        if ($event.Properties) {
            [void]$sb.AppendLine('**Properties:**')
            [void]$sb.AppendLine('')
            [void]$sb.AppendLine('| Field | Type | Description |')
            [void]$sb.AppendLine('|-------|------|-------------|')

            foreach ($propName in ($event.Properties.PSObject.Properties.Name | Sort-Object)) {
                $prop = $event.Properties.$propName
                $type = if ($prop.type) { $prop.type } else { 'any' }
                $desc = if ($prop.description) { $prop.description } else { '-' }
                [void]$sb.AppendLine("| $propName | $type | $desc |")
            }
            [void]$sb.AppendLine('')
        }

        [void]$sb.AppendLine('---')
        [void]$sb.AppendLine('')
    }

    $content = $sb.ToString()

    if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
        $parent = Split-Path -Parent $OutputPath
        if ($parent -and -not (Test-Path $parent)) {
            New-Item -Path $parent -ItemType Directory -Force | Out-Null
        }
        $content | Set-Content -Path $OutputPath -Encoding UTF8
        return @{
            Path = $OutputPath
            EventCount = $script:EventCatalog.Count
        }
    }

    return $content
}
#endregion

#region Schema Migration
function Get-TelemetrySchemaVersion {
    [CmdletBinding()]
    param()

    return @{
        Current = $script:SchemaVersion
        MinCompatible = $script:MinCompatibleVersion
    }
}

function Test-SchemaVersionCompatibility {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Version
    )

    try {
        $current = [version]$script:SchemaVersion
        $minCompatible = [version]$script:MinCompatibleVersion
        $test = [version]$Version

        return @{
            Compatible = $test -ge $minCompatible
            CurrentVersion = $script:SchemaVersion
            TestedVersion = $Version
            MinCompatibleVersion = $script:MinCompatibleVersion
        }
    } catch {
        return @{
            Compatible = $false
            CurrentVersion = $script:SchemaVersion
            TestedVersion = $Version
            MinCompatibleVersion = $script:MinCompatibleVersion
            Error = $_.Exception.Message
        }
    }
}

function Update-TelemetryEventSchema {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [hashtable]$FieldMappings,

        [hashtable]$DefaultValues,

        [string]$OutputPath,

        [switch]$WhatIf
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "File not found: $Path"
    }

    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $OutputPath = $Path + '.migrated'
    }

    $results = @{
        SourcePath = $Path
        OutputPath = $OutputPath
        TotalEvents = 0
        MigratedEvents = 0
        SkippedEvents = 0
        Changes = [System.Collections.Generic.List[object]]::new()
    }

    $outputLines = [System.Collections.Generic.List[string]]::new()

    foreach ($line in [System.IO.File]::ReadLines($Path)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }

        try {
            $event = $line | ConvertFrom-Json
            $results.TotalEvents++

            $changed = $false
            $changes = @()

            # Apply field mappings (rename fields)
            if ($FieldMappings) {
                foreach ($oldName in $FieldMappings.Keys) {
                    $newName = $FieldMappings[$oldName]
                    if ($event.PSObject.Properties[$oldName]) {
                        $value = $event.$oldName
                        $event.PSObject.Properties.Remove($oldName)
                        $event | Add-Member -NotePropertyName $newName -NotePropertyValue $value
                        $changed = $true
                        $changes += "Renamed $oldName -> $newName"
                    }
                }
            }

            # Apply default values for missing fields
            if ($DefaultValues) {
                foreach ($fieldName in $DefaultValues.Keys) {
                    if (-not $event.PSObject.Properties[$fieldName]) {
                        $event | Add-Member -NotePropertyName $fieldName -NotePropertyValue $DefaultValues[$fieldName]
                        $changed = $true
                        $changes += "Added default $fieldName"
                    }
                }
            }

            if ($changed) {
                $results.MigratedEvents++
                $results.Changes.Add(@{
                    Line = $results.TotalEvents
                    Changes = $changes
                })
            } else {
                $results.SkippedEvents++
            }

            $outputLines.Add(($event | ConvertTo-Json -Depth 10 -Compress))
        } catch {
            $results.SkippedEvents++
            $outputLines.Add($line)  # Keep original on error
        }
    }

    if (-not $WhatIf) {
        $parent = Split-Path -Parent $OutputPath
        if ($parent -and -not (Test-Path $parent)) {
            New-Item -Path $parent -ItemType Directory -Force | Out-Null
        }
        $outputLines | Set-Content -Path $OutputPath -Encoding UTF8
    }

    return [PSCustomObject]$results
}
#endregion

#region Schema Version Enforcement
function Test-EventSchemaVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Event
    )

    $result = @{
        Valid = $true
        Version = $null
        Reason = $null
    }

    if ($Event.SchemaVersion) {
        $result.Version = $Event.SchemaVersion
        $compatibility = Test-SchemaVersionCompatibility -Version $Event.SchemaVersion

        if (-not $compatibility.Compatible) {
            $result.Valid = $false
            $result.Reason = "Schema version $($Event.SchemaVersion) is below minimum compatible version $($script:MinCompatibleVersion)"
        }
    }

    return [PSCustomObject]$result
}

function Add-SchemaVersionToEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Payload
    )

    $Payload['SchemaVersion'] = $script:SchemaVersion
    return $Payload
}
#endregion

#region Exports
Export-ModuleMember -Function @(
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
#endregion
