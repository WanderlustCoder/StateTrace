[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RouteRecordsPath,
    [Parameter(Mandatory = $true)]
    [string]$OutputPath,
    [Parameter(Mandatory = $true)]
    [string]$SummaryPath,
    [string]$Site,
    [string]$Hostname,
    [string]$Vrf,
    [string]$SchemaPath,
    [string]$RouteRecordSchemaPath,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($SchemaPath)) {
    $SchemaPath = Join-Path -Path $repoRoot -ChildPath 'docs/schemas/routing/route_health_snapshot.schema.json'
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
    $stringValue = if ($Value -is [DateTime]) {
        $Value.ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)
    } elseif ($Value -is [DateTimeOffset]) {
        $Value.ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)
    } else {
        [string]$Value
    }
    if ([string]::IsNullOrWhiteSpace($stringValue)) {
        Add-Error -Errors $Errors -Message "EmptyRequiredField:$label"
        return $null
    }
    return $stringValue
}

function Get-DeterministicSnapshotId {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Site,
        [Parameter(Mandatory = $true)]
        [string]$Hostname,
        [Parameter(Mandatory = $true)]
        [string]$Vrf,
        [Parameter(Mandatory = $true)]
        [string]$CapturedAt,
        [Parameter(Mandatory = $true)]
        [string[]]$RecordIds
    )

    $payload = ($Site, $Hostname, $Vrf, $CapturedAt, ($RecordIds -join ',')) -join '|'
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash($bytes)
    } finally {
        $sha.Dispose()
    }
    $hashString = ([BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
    return "RHS-$hashString"
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

if (-not (Test-Path -LiteralPath $RouteRecordsPath)) {
    throw "RouteRecords not found at $RouteRecordsPath"
}
if (-not (Test-Path -LiteralPath $SchemaPath)) {
    throw "RouteHealthSnapshot schema not found at $SchemaPath"
}
if (-not (Test-Path -LiteralPath $RouteRecordSchemaPath)) {
    throw "RouteRecord schema not found at $RouteRecordSchemaPath"
}

$errors = New-Object System.Collections.Generic.List[string]
$routeRecords = Get-Content -LiteralPath $RouteRecordsPath -Raw | ConvertFrom-Json -ErrorAction Stop
if ($routeRecords -isnot [System.Array]) {
    $routeRecords = @($routeRecords)
}
if ($routeRecords.Count -eq 0) {
    Add-Error -Errors $errors -Message 'NoRouteRecords'
}

$healthSchema = Get-Content -LiteralPath $SchemaPath -Raw | ConvertFrom-Json -ErrorAction Stop
$recordSchema = Get-Content -LiteralPath $RouteRecordSchemaPath -Raw | ConvertFrom-Json -ErrorAction Stop

# LANDMARK: Route health snapshot generator - derive health from RouteRecords and emit schema-valid snapshot
$validatedRecords = [System.Collections.Generic.List[pscustomobject]]::new()
$recordIndex = 0
foreach ($record in $routeRecords) {
    $prefix = "Record[$recordIndex]"
    $schemaVersion = Get-RequiredString -Value (Get-PropertyValue -Object $record -Name 'SchemaVersion') -FieldName 'SchemaVersion' -Errors $errors -Prefix $prefix
    if ($null -ne $schemaVersion -and $schemaVersion -ne $recordSchema.SchemaVersion) {
        Add-Error -Errors $errors -Message "SchemaVersionMismatch:$prefix expected=$($recordSchema.SchemaVersion) actual=$schemaVersion"
    }
    $recordId = Get-RequiredString -Value (Get-PropertyValue -Object $record -Name 'RecordId') -FieldName 'RecordId' -Errors $errors -Prefix $prefix
    $capturedAt = Get-RequiredString -Value (Get-PropertyValue -Object $record -Name 'CapturedAt') -FieldName 'CapturedAt' -Errors $errors -Prefix $prefix
    $siteValue = Get-RequiredString -Value (Get-PropertyValue -Object $record -Name 'Site') -FieldName 'Site' -Errors $errors -Prefix $prefix
    $hostnameValue = Get-RequiredString -Value (Get-PropertyValue -Object $record -Name 'Hostname') -FieldName 'Hostname' -Errors $errors -Prefix $prefix
    $vrfValue = Get-RequiredString -Value (Get-PropertyValue -Object $record -Name 'Vrf') -FieldName 'Vrf' -Errors $errors -Prefix $prefix
    $routeRole = Get-RequiredString -Value (Get-PropertyValue -Object $record -Name 'RouteRole') -FieldName 'RouteRole' -Errors $errors -Prefix $prefix
    $routeState = Get-RequiredString -Value (Get-PropertyValue -Object $record -Name 'RouteState') -FieldName 'RouteState' -Errors $errors -Prefix $prefix

    if ($errors.Count -eq 0) {
        $validatedRecords.Add([pscustomobject]@{
            SchemaVersion = $schemaVersion
            RecordId      = $recordId
            CapturedAt    = $capturedAt
            Site          = $siteValue
            Hostname      = $hostnameValue
            Vrf           = $vrfValue
            RouteRole     = $routeRole
            RouteState    = $routeState
        })
    }
    $recordIndex += 1
}

$filteredRecords = $validatedRecords
if (-not [string]::IsNullOrWhiteSpace($Site)) {
    $filteredRecords = $filteredRecords | Where-Object { $_.Site -eq $Site }
}
if (-not [string]::IsNullOrWhiteSpace($Hostname)) {
    $filteredRecords = $filteredRecords | Where-Object { $_.Hostname -eq $Hostname }
}
if (-not [string]::IsNullOrWhiteSpace($Vrf)) {
    $filteredRecords = $filteredRecords | Where-Object { $_.Vrf -eq $Vrf }
}
# LANDMARK: Route health snapshot generator - stabilize empty filter results
$filteredRecords = @($filteredRecords)

if ($errors.Count -eq 0 -and $filteredRecords.Count -eq 0) {
    Add-Error -Errors $errors -Message 'NoRouteRecordsAfterFilter'
}

$groupKey = $null
$snapshot = $null
$primaryStatus = $null
$secondaryStatus = $null
$healthState = $null
$primaryCount = 0
$secondaryCount = 0

if ($errors.Count -eq 0) {
    $groupMap = @{}
    foreach ($record in $filteredRecords) {
        $key = "{0}|{1}|{2}" -f $record.Site, $record.Hostname, $record.Vrf
        if (-not $groupMap.ContainsKey($key)) {
            $groupMap[$key] = [System.Collections.Generic.List[pscustomobject]]::new()
        }
        $groupMap[$key].Add($record)
    }

    if ($groupMap.Keys.Count -ne 1) {
        $keys = ($groupMap.Keys | Sort-Object) -join ','
        Add-Error -Errors $errors -Message "MultipleRouteRecordGroups:$keys"
    } else {
        $groupKey = $groupMap.Keys | Select-Object -First 1
        $records = $groupMap[$groupKey]
        $siteValue = $records[0].Site.ToUpperInvariant()
        $hostnameValue = $records[0].Hostname.ToUpperInvariant()
        $vrfValue = if ([string]::IsNullOrWhiteSpace($records[0].Vrf)) { 'default' } else { $records[0].Vrf }

        $primaryRecords = @($records | Where-Object { $_.RouteRole -eq 'Primary' })
        $secondaryRecords = @($records | Where-Object { $_.RouteRole -eq 'Secondary' })
        $primaryCount = $primaryRecords.Count
        $secondaryCount = $secondaryRecords.Count

        $primaryStatusBase = if ($primaryRecords.Count -eq 0) {
            'Missing'
        } elseif ($primaryRecords | Where-Object { $_.RouteState -eq 'Active' }) {
            'Up'
        } else {
            'Down'
        }

        if ($secondaryRecords.Count -eq 0) {
            $secondaryStatus = 'Missing'
        } elseif ($secondaryRecords | Where-Object { $_.RouteState -eq 'Active' }) {
            $secondaryStatus = 'Up'
        } elseif ($primaryStatusBase -eq 'Up') {
            $secondaryStatus = 'Standby'
        } else {
            $secondaryStatus = 'Down'
        }

        if ($primaryStatusBase -eq 'Down' -and $secondaryStatus -eq 'Up') {
            $primaryStatus = 'Degraded'
        } else {
            $primaryStatus = $primaryStatusBase
        }

        if ($primaryStatus -eq 'Up') {
            $healthState = 'Healthy'
        } elseif ($secondaryStatus -eq 'Up') {
            $healthState = 'Warning'
        } else {
            $healthState = 'Critical'
        }

        $capturedDates = New-Object System.Collections.Generic.List[DateTimeOffset]
        foreach ($record in $records) {
            try {
                $capturedDates.Add([DateTimeOffset]::Parse($record.CapturedAt)) | Out-Null
            } catch {
                Add-Error -Errors $errors -Message "InvalidCapturedAt:$($record.RecordId)"
            }
        }

        if ($errors.Count -eq 0) {
            $minCaptured = ($capturedDates | Measure-Object -Minimum).Minimum
            $maxCaptured = ($capturedDates | Measure-Object -Maximum).Maximum
            $detectionLatencyMs = [math]::Round(($maxCaptured - $minCaptured).TotalMilliseconds, 0)
            $capturedAtSnapshot = $maxCaptured.ToString('o')
            $recordIds = ($records | Select-Object -ExpandProperty RecordId | Sort-Object)
            $snapshotId = Get-DeterministicSnapshotId -Site $siteValue -Hostname $hostnameValue -Vrf $vrfValue -CapturedAt $capturedAtSnapshot -RecordIds $recordIds
            $failoverState = if ($primaryStatus -eq 'Degraded') { 'FailoverComplete' } else { 'None' }
            $healthScore = switch ($healthState) {
                'Healthy' { 1.0 }
                'Warning' { 0.7 }
                'Critical' { 0.0 }
                default { 0.0 }
            }

            $snapshot = [pscustomobject]@{
                SchemaVersion        = $healthSchema.SchemaVersion
                SnapshotId           = $snapshotId
                CapturedAt           = $capturedAtSnapshot
                Site                 = $siteValue
                Hostname             = $hostnameValue
                Vrf                  = $vrfValue
                PrimaryRouteStatus   = $primaryStatus
                SecondaryRouteStatus = $secondaryStatus
                HealthState          = $healthState
                DetectionLatencyMs   = $detectionLatencyMs
                RouteRecordIds       = $recordIds
                FailoverState        = $failoverState
                HealthScore          = $healthScore
                EvidenceSources      = @('RouteRecords')
                Notes                = 'Generated from RouteRecord fixtures'
            }
        }
    }
}

$summary = [pscustomobject]@{
    Timestamp                = (Get-Date -Format o)
    Status                   = if ($errors.Count -eq 0) { 'Pass' } else { 'Fail' }
    RouteRecordsPath         = (Resolve-Path -LiteralPath $RouteRecordsPath).Path
    RouteHealthSnapshotPath  = $OutputPath
    GroupKey                 = $groupKey
    RouteRecordCount         = $filteredRecords.Count
    PrimaryRecordCount       = $primaryCount
    SecondaryRecordCount     = $secondaryCount
    PrimaryRouteStatus       = $primaryStatus
    SecondaryRouteStatus     = $secondaryStatus
    HealthState              = $healthState
    Errors                   = $errors.ToArray()
    SchemaVersion            = $healthSchema.SchemaVersion
    RouteRecordSchemaVersion = $recordSchema.SchemaVersion
}

Ensure-Directory -Path $SummaryPath
$summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $SummaryPath -Encoding utf8

if ($errors.Count -eq 0) {
    Ensure-Directory -Path $OutputPath
    $snapshot | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutputPath -Encoding utf8
} else {
    throw "RouteHealthSnapshot generation failed. See $SummaryPath"
}

if ($PassThru.IsPresent) {
    return $summary
}
