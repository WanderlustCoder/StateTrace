[CmdletBinding()]
param(
    [string]$RouteRecordPath,
    [string]$RouteHealthSnapshotPath,
    [string]$FixtureRoot,
    [string]$SchemaRoot,
    [Parameter(Mandatory = $true)]
    [string]$OutputPath,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($FixtureRoot)) {
    $FixtureRoot = Join-Path -Path $repoRoot -ChildPath 'Tests/Fixtures/Routing'
}
if ([string]::IsNullOrWhiteSpace($SchemaRoot)) {
    $SchemaRoot = Join-Path -Path $repoRoot -ChildPath 'docs/schemas/routing'
}

if ([string]::IsNullOrWhiteSpace($RouteRecordPath)) {
    $RouteRecordPath = Join-Path -Path $FixtureRoot -ChildPath 'RouteRecord.sample.json'
}
if ([string]::IsNullOrWhiteSpace($RouteHealthSnapshotPath)) {
    $RouteHealthSnapshotPath = Join-Path -Path $FixtureRoot -ChildPath 'RouteHealthSnapshot.sample.json'
}

function Test-ValueType {
    param(
        [Parameter(Mandatory = $true)]
        $Value,
        [Parameter(Mandatory = $true)]
        [string]$ExpectedType
    )

    switch ($ExpectedType) {
        'string' { return ($Value -is [string] -or $Value -is [datetime] -or $Value -is [DateTimeOffset]) }
        'integer' {
            if ($Value -is [int] -or $Value -is [long] -or $Value -is [int64]) { return $true }
            if ($Value -is [double]) { return ([math]::Floor($Value) -eq $Value) }
            return $false
        }
        'number' { return ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal]) }
        'boolean' { return ($Value -is [bool]) }
        'array' { return ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) }
        'object' { return ($Value -is [pscustomobject] -or $Value -is [hashtable]) }
        default { return $false }
    }
}

function Read-JsonFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$Errors
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        $Errors.Add("MissingFile:$Path") | Out-Null
        return $null
    }

    try {
        return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -ErrorAction Stop)
    } catch {
        $Errors.Add("InvalidJson:$Path") | Out-Null
        return $null
    }
}

function Test-ObjectAgainstSchema {
    param(
        [Parameter(Mandatory = $true)]
        $Object,
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Schema,
        [Parameter(Mandatory = $true)]
        [string]$Label,
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$Errors
    )

    # LANDMARK: Routing schemas validator - validate RouteRecord/RouteHealthSnapshot v1 and emit summary
    if ($null -eq $Object) {
        $Errors.Add("NullObject:$Label") | Out-Null
    } else {
        $objectsToValidate = @($Object)
        $objectCount = ($objectsToValidate | Measure-Object).Count
        $objectIndex = 0
        foreach ($item in $objectsToValidate) {
            $prefix = if ($objectCount -gt 1) { "Item[$objectIndex]." } else { "" }
            foreach ($fieldName in $Schema.Required.PSObject.Properties.Name) {
                $expectedType = $Schema.Required.$fieldName
                $property = $item.PSObject.Properties[$fieldName]
                if ($null -eq $property) {
                    $Errors.Add("MissingRequiredField:$prefix$fieldName") | Out-Null
                    continue
                }
                $value = $property.Value
                if (-not (Test-ValueType -Value $value -ExpectedType $expectedType)) {
                    $Errors.Add("InvalidType:$prefix$fieldName expected=$expectedType actual=$($value.GetType().Name)") | Out-Null
                    continue
                }
                if ($fieldName -eq 'SchemaVersion' -and $value -ne $Schema.SchemaVersion) {
                    $Errors.Add("SchemaVersionMismatch:$prefix expected=$($Schema.SchemaVersion) actual=$value") | Out-Null
                }
            }

            foreach ($fieldName in $Schema.Optional.PSObject.Properties.Name) {
                $property = $item.PSObject.Properties[$fieldName]
                if ($null -eq $property) {
                    continue
                }
                $expectedType = $Schema.Optional.$fieldName
                $value = $property.Value
                if (-not (Test-ValueType -Value $value -ExpectedType $expectedType)) {
                    $Errors.Add("InvalidType:$prefix$fieldName expected=$expectedType actual=$($value.GetType().Name)") | Out-Null
                }
            }
            $objectIndex += 1
        }
    }

    $status = if ($Errors.Count -gt 0) { 'Fail' } else { 'Pass' }
    return [pscustomobject]@{
        Label                 = $Label
        Path                  = $SourcePath
        Status                = $status
        Errors                = $Errors.ToArray()
        SchemaVersionExpected = $Schema.SchemaVersion
        SchemaVersionFound    = if ($null -ne $Object) { $Object.SchemaVersion } else { $null }
    }
}

$routeRecordSchemaPath = Join-Path -Path $SchemaRoot -ChildPath 'route_record.schema.json'
$routeHealthSchemaPath = Join-Path -Path $SchemaRoot -ChildPath 'route_health_snapshot.schema.json'

if (-not (Test-Path -LiteralPath $routeRecordSchemaPath)) {
    throw "RouteRecord schema not found at $routeRecordSchemaPath"
}
if (-not (Test-Path -LiteralPath $routeHealthSchemaPath)) {
    throw "RouteHealthSnapshot schema not found at $routeHealthSchemaPath"
}

$routeRecordSchema = Get-Content -LiteralPath $routeRecordSchemaPath -Raw | ConvertFrom-Json -ErrorAction Stop
$routeHealthSchema = Get-Content -LiteralPath $routeHealthSchemaPath -Raw | ConvertFrom-Json -ErrorAction Stop

$routeRecordErrors = New-Object System.Collections.Generic.List[string]
$routeRecordObject = Read-JsonFile -Path $RouteRecordPath -Errors $routeRecordErrors
$routeRecordResult = Test-ObjectAgainstSchema -Object $routeRecordObject -Schema $routeRecordSchema -Label 'RouteRecord' -SourcePath $RouteRecordPath -Errors $routeRecordErrors

$routeHealthErrors = New-Object System.Collections.Generic.List[string]
$routeHealthObject = Read-JsonFile -Path $RouteHealthSnapshotPath -Errors $routeHealthErrors
$routeHealthResult = Test-ObjectAgainstSchema -Object $routeHealthObject -Schema $routeHealthSchema -Label 'RouteHealthSnapshot' -SourcePath $RouteHealthSnapshotPath -Errors $routeHealthErrors

$summary = [pscustomobject]@{
    Timestamp            = (Get-Date -Format o)
    SchemaRoot           = (Resolve-Path -LiteralPath $SchemaRoot).Path
    RouteRecord          = $routeRecordResult
    RouteHealthSnapshot  = $routeHealthResult
    Status               = if ($routeRecordResult.Status -eq 'Pass' -and $routeHealthResult.Status -eq 'Pass') { 'Pass' } else { 'Fail' }
}

$outputDirectory = Split-Path -Parent $OutputPath
if (-not [string]::IsNullOrWhiteSpace($outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}

$summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutputPath -Encoding utf8

if ($summary.Status -ne 'Pass') {
    throw "Routing schema validation failed. See $OutputPath"
}

if ($PassThru.IsPresent) {
    return $summary
}
