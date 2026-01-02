[CmdletBinding()]
param(
    [string]$CapturePath,
    [Parameter(Mandatory = $true)]
    [string]$RouteRecordOutputPath,
    [Parameter(Mandatory = $true)]
    [string]$SummaryPath,
    [string]$SchemaPath,
    [string]$RouteRecordSchemaPath,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($CapturePath)) {
    $CapturePath = Join-Path -Path $repoRoot -ChildPath 'Tests/Fixtures/Routing/RoutingDiscoveryCapture.sample.json'
}
if ([string]::IsNullOrWhiteSpace($SchemaPath)) {
    $SchemaPath = Join-Path -Path $repoRoot -ChildPath 'docs/schemas/routing/routing_discovery_capture.schema.json'
}
if ([string]::IsNullOrWhiteSpace($RouteRecordSchemaPath)) {
    $RouteRecordSchemaPath = Join-Path -Path $repoRoot -ChildPath 'docs/schemas/routing/route_record.schema.json'
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

function Add-Error {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$Errors,
        [Parameter(Mandatory = $true)]
        [string]$Message
    )
    $Errors.Add($Message) | Out-Null
}

function Get-RequiredString {
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $Value,
        [Parameter(Mandatory = $true)]
        [string]$FieldName,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$Errors,
        [string]$Prefix
    )

    $label = if ([string]::IsNullOrWhiteSpace($Prefix)) { $FieldName } else { "$Prefix.$FieldName" }
    if ($null -eq $Value) {
        Add-Error -Errors $Errors -Message "MissingRequiredField:$label"
        return $null
    }
    if (-not (Test-ValueType -Value $Value -ExpectedType 'string')) {
        Add-Error -Errors $Errors -Message "InvalidType:$label expected=string actual=$($Value.GetType().Name)"
        return $null
    }
    if ([string]::IsNullOrWhiteSpace([string]$Value)) {
        Add-Error -Errors $Errors -Message "EmptyRequiredField:$label"
        return $null
    }
    return [string]$Value
}

function Get-PropertyValue {
    param(
        [Parameter(Mandatory = $true)]
        $Object,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($null -eq $Object) {
        return $null
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }
    return $property.Value
}

function Get-DeterministicRecordId {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CapturedAt,
        [Parameter(Mandatory = $true)]
        [string]$Site,
        [Parameter(Mandatory = $true)]
        [string]$Hostname,
        [Parameter(Mandatory = $true)]
        [string]$Vrf,
        [Parameter(Mandatory = $true)]
        [string]$Prefix,
        [Parameter(Mandatory = $true)]
        [int]$PrefixLength,
        [Parameter(Mandatory = $true)]
        [string]$NextHop,
        [Parameter(Mandatory = $true)]
        [string]$Protocol,
        [Parameter(Mandatory = $true)]
        [string]$RouteRole,
        [Parameter(Mandatory = $true)]
        [string]$RouteState
    )

    $payload = ($CapturedAt, $Site, $Hostname, $Vrf, $Prefix, $PrefixLength, $NextHop, $Protocol, $RouteRole, $RouteState) -join '|'
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash($bytes)
    } finally {
        $sha.Dispose()
    }
    return ([BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
}

function Ensure-Directory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    $directory = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
}

if (-not (Test-Path -LiteralPath $CapturePath)) {
    throw "Routing discovery capture not found at $CapturePath"
}
if (-not (Test-Path -LiteralPath $SchemaPath)) {
    throw "Routing discovery capture schema not found at $SchemaPath"
}
if (-not (Test-Path -LiteralPath $RouteRecordSchemaPath)) {
    throw "RouteRecord schema not found at $RouteRecordSchemaPath"
}

$errors = New-Object System.Collections.Generic.List[string]
$capture = Get-Content -LiteralPath $CapturePath -Raw | ConvertFrom-Json -ErrorAction Stop
$schema = Get-Content -LiteralPath $SchemaPath -Raw | ConvertFrom-Json -ErrorAction Stop
$routeRecordSchema = Get-Content -LiteralPath $RouteRecordSchemaPath -Raw | ConvertFrom-Json -ErrorAction Stop

# LANDMARK: Routing discovery capture conversion - validate capture and emit RouteRecord array + summary
$schemaVersion = Get-RequiredString -Value (Get-PropertyValue -Object $capture -Name 'SchemaVersion') -FieldName 'SchemaVersion' -Errors $errors
if ($null -ne $schemaVersion -and $schemaVersion -ne $schema.SchemaVersion) {
    Add-Error -Errors $errors -Message "SchemaVersionMismatch: expected=$($schema.SchemaVersion) actual=$schemaVersion"
}

$capturedAt = Get-RequiredString -Value (Get-PropertyValue -Object $capture -Name 'CapturedAt') -FieldName 'CapturedAt' -Errors $errors
$site = Get-RequiredString -Value (Get-PropertyValue -Object $capture -Name 'Site') -FieldName 'Site' -Errors $errors
$hostname = Get-RequiredString -Value (Get-PropertyValue -Object $capture -Name 'Hostname') -FieldName 'Hostname' -Errors $errors
$vrf = Get-RequiredString -Value (Get-PropertyValue -Object $capture -Name 'Vrf') -FieldName 'Vrf' -Errors $errors

$routes = Get-PropertyValue -Object $capture -Name 'Routes'
if ($null -eq $routes) {
    Add-Error -Errors $errors -Message 'MissingRequiredField:Routes'
} elseif (-not (Test-ValueType -Value $routes -ExpectedType 'array')) {
    Add-Error -Errors $errors -Message "InvalidType:Routes expected=array actual=$($routes.GetType().Name)"
}

$routeRecords = @()
if ($errors.Count -eq 0) {
    if ([string]::IsNullOrWhiteSpace($vrf)) {
        $vrf = 'default'
    }
    $siteNormalized = $site.ToUpperInvariant()
    $hostnameNormalized = $hostname.ToUpperInvariant()

    $routeIndex = 0
    foreach ($route in $routes) {
        $prefix = Get-RequiredString -Value (Get-PropertyValue -Object $route -Name 'Prefix') -FieldName 'Prefix' -Errors $errors -Prefix "Route[$routeIndex]"
        $prefixLength = Get-PropertyValue -Object $route -Name 'PrefixLength'
        if ($null -eq $prefixLength) {
            Add-Error -Errors $errors -Message "MissingRequiredField:Route[$routeIndex].PrefixLength"
        } elseif (-not (Test-ValueType -Value $prefixLength -ExpectedType 'integer')) {
            Add-Error -Errors $errors -Message "InvalidType:Route[$routeIndex].PrefixLength expected=integer actual=$($prefixLength.GetType().Name)"
        }
        $nextHop = Get-RequiredString -Value (Get-PropertyValue -Object $route -Name 'NextHop') -FieldName 'NextHop' -Errors $errors -Prefix "Route[$routeIndex]"
        $protocol = Get-RequiredString -Value (Get-PropertyValue -Object $route -Name 'Protocol') -FieldName 'Protocol' -Errors $errors -Prefix "Route[$routeIndex]"
        $routeRole = Get-RequiredString -Value (Get-PropertyValue -Object $route -Name 'RouteRole') -FieldName 'RouteRole' -Errors $errors -Prefix "Route[$routeIndex]"
        $routeState = Get-RequiredString -Value (Get-PropertyValue -Object $route -Name 'RouteState') -FieldName 'RouteState' -Errors $errors -Prefix "Route[$routeIndex]"

        if ($errors.Count -eq 0) {
            $recordId = Get-DeterministicRecordId -CapturedAt $capturedAt -Site $siteNormalized -Hostname $hostnameNormalized -Vrf $vrf -Prefix $prefix -PrefixLength $prefixLength -NextHop $nextHop -Protocol $protocol -RouteRole $routeRole -RouteState $routeState
            $routeRecord = [pscustomobject]@{
                SchemaVersion  = $routeRecordSchema.SchemaVersion
                RecordId       = $recordId
                CapturedAt     = $capturedAt
                Site           = $siteNormalized
                Hostname       = $hostnameNormalized
                Vrf            = $vrf
                Prefix         = $prefix
                PrefixLength   = [int]$prefixLength
                NextHop        = $nextHop
                Protocol       = $protocol
                RouteRole      = $routeRole
                RouteState     = $routeState
                InterfaceName  = Get-PropertyValue -Object $route -Name 'InterfaceName'
                AdminDistance  = Get-PropertyValue -Object $route -Name 'AdminDistance'
                Metric         = Get-PropertyValue -Object $route -Name 'Metric'
                Tag            = Get-PropertyValue -Object $route -Name 'Tag'
                AgeSeconds     = Get-PropertyValue -Object $route -Name 'AgeSeconds'
                SourceSystem   = 'RoutingDiscoveryCapture'
            }
            $routeRecords += $routeRecord
        }
        $routeIndex += 1
    }
}

$summary = [pscustomobject]@{
    Timestamp             = (Get-Date -Format o)
    Status                = if ($errors.Count -eq 0) { 'Pass' } else { 'Fail' }
    CapturePath           = (Resolve-Path -LiteralPath $CapturePath).Path
    RouteRecordOutputPath = $RouteRecordOutputPath
    RouteCount            = $routeRecords.Count
    Errors                = $errors.ToArray()
    SchemaVersion         = $schema.SchemaVersion
    RouteRecordSchema     = $routeRecordSchema.SchemaVersion
}

Ensure-Directory -Path $SummaryPath
$summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $SummaryPath -Encoding utf8

if ($errors.Count -eq 0) {
    Ensure-Directory -Path $RouteRecordOutputPath
    $routeRecords | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $RouteRecordOutputPath -Encoding utf8
} else {
    throw "Routing discovery capture conversion failed. See $SummaryPath"
}

if ($PassThru.IsPresent) {
    return $summary
}
