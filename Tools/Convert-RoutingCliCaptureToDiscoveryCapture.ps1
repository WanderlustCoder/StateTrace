[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CapturePath,
    [Parameter(Mandatory = $true)]
    [string]$OutputPath,
    [Parameter(Mandatory = $true)]
    [string]$SummaryPath,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$schemaPath = Join-Path -Path $repoRoot -ChildPath 'docs/schemas/routing/routing_cli_capture.schema.json'
$discoverySchemaPath = Join-Path -Path $repoRoot -ChildPath 'docs/schemas/routing/routing_discovery_capture.schema.json'

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
    if ([string]::IsNullOrWhiteSpace([string]$Value)) {
        Add-Error -Errors $Errors -Message "EmptyRequiredField:$label"
        return $null
    }
    return [string]$Value
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

function Resolve-ArtifactPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CaptureFilePath,
        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    $baseDirectory = Split-Path -Parent $CaptureFilePath
    return (Join-Path -Path $baseDirectory -ChildPath $RelativePath)
}

function Convert-TimeSpanToSeconds {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $match = [regex]::Match($Value, '^(?<hours>\d+):(?<minutes>\d+):(?<seconds>\d+)$')
    if (-not $match.Success) {
        return $null
    }
    return ([int]$match.Groups['hours'].Value * 3600) +
        ([int]$match.Groups['minutes'].Value * 60) +
        ([int]$match.Groups['seconds'].Value)
}

function Convert-CiscoShowIpRoute {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Lines,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$Errors
    )

    $routes = @()
    $lineIndex = 0
    foreach ($line in $Lines) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) {
            $lineIndex += 1
            continue
        }
        if ($trimmed -match '^(Codes:|Gateway of last resort)') {
            $lineIndex += 1
            continue
        }

        $prefixMatch = [regex]::Match($trimmed, '(?<prefix>\d{1,3}(?:\.\d{1,3}){3})/(?<length>\d{1,2})')
        if (-not $prefixMatch.Success) {
            $lineIndex += 1
            continue
        }

        $codeMatch = [regex]::Match($trimmed, '^(?<code>[A-Z]+)')
        $code = if ($codeMatch.Success) { $codeMatch.Groups['code'].Value } else { '' }
        $code = if ([string]::IsNullOrWhiteSpace($code)) { 'U' } else { $code.Substring(0, 1) }

        $protocol = switch ($code) {
            'C' { 'Connected' }
            'L' { 'Local' }
            'S' { 'Static' }
            'O' { 'OSPF' }
            'B' { 'BGP' }
            'R' { 'RIP' }
            'D' { 'EIGRP' }
            default { $code }
        }

        $prefix = $prefixMatch.Groups['prefix'].Value
        $prefixLength = [int]$prefixMatch.Groups['length'].Value

        $nextHopMatch = [regex]::Match($trimmed, '\bvia\s+(?<nextHop>\d{1,3}(?:\.\d{1,3}){3})')
        $nextHop = if ($nextHopMatch.Success) { $nextHopMatch.Groups['nextHop'].Value } else { 'DIRECT' }

        $interfaceName = $null
        if ($trimmed -match ',') {
            $segments = $trimmed.Split(',')
            $interfaceName = $segments[$segments.Length - 1].Trim()
        }

        $adminDistance = $null
        $metric = $null
        $metricMatch = [regex]::Match($trimmed, '\[(?<ad>\d+)/(?<metric>\d+)\]')
        if ($metricMatch.Success) {
            $adminDistance = [int]$metricMatch.Groups['ad'].Value
            $metric = [int]$metricMatch.Groups['metric'].Value
        }

        $ageSeconds = $null
        $ageMatch = [regex]::Match($trimmed, '(?<age>\d+:\d+:\d+)')
        if ($ageMatch.Success) {
            $ageSeconds = Convert-TimeSpanToSeconds -Value $ageMatch.Groups['age'].Value
        }

        if ([string]::IsNullOrWhiteSpace($interfaceName)) {
            $interfaceName = 'UNKNOWN'
        }
        if ($null -eq $adminDistance) {
            $adminDistance = 0
        }
        if ($null -eq $metric) {
            $metric = 0
        }
        if ($null -eq $ageSeconds) {
            $ageSeconds = 0
        }

        $route = [pscustomobject]@{
            Prefix        = $prefix
            PrefixLength  = $prefixLength
            NextHop       = $nextHop
            Protocol      = $protocol
            RouteRole     = 'Primary'
            RouteState    = 'Active'
            InterfaceName = $interfaceName
            AdminDistance = $adminDistance
            Metric        = $metric
            Tag           = 'CLI'
            AgeSeconds    = $ageSeconds
        }
        $routes += $route
        $lineIndex += 1
    }

    return $routes
}

function Convert-AristaShowIpRoute {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Lines,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$Errors
    )

    $routes = @()
    foreach ($line in $Lines) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) {
            continue
        }
        if ($trimmed -match '^(Codes:|Gateway of last resort)') {
            continue
        }

        $prefixMatch = [regex]::Match($trimmed, '(?<prefix>\d{1,3}(?:\.\d{1,3}){3})/(?<length>\d{1,2})')
        if (-not $prefixMatch.Success) {
            continue
        }

        $codeMatch = [regex]::Match($trimmed, '^(?<code>[A-Z]+)')
        $code = if ($codeMatch.Success) { $codeMatch.Groups['code'].Value } else { '' }
        $code = if ([string]::IsNullOrWhiteSpace($code)) { 'U' } else { $code.Substring(0, 1) }

        $protocol = switch ($code) {
            'C' { 'Connected' }
            'L' { 'Local' }
            'S' { 'Static' }
            'O' { 'OSPF' }
            'B' { 'BGP' }
            'R' { 'RIP' }
            'K' { 'Kernel' }
            'D' { 'EIGRP' }
            default { $code }
        }

        $prefix = $prefixMatch.Groups['prefix'].Value
        $prefixLength = [int]$prefixMatch.Groups['length'].Value

        $nextHopMatch = [regex]::Match($trimmed, '\bvia\s+(?<nextHop>\d{1,3}(?:\.\d{1,3}){3})')
        $nextHop = if ($nextHopMatch.Success) { $nextHopMatch.Groups['nextHop'].Value } else { 'DIRECT' }

        $interfaceName = $null
        if ($trimmed -match ',') {
            $segments = $trimmed.Split(',')
            $interfaceName = $segments[$segments.Length - 1].Trim()
        }

        $adminDistance = $null
        $metric = $null
        $metricMatch = [regex]::Match($trimmed, '\[(?<ad>\d+)/(?<metric>\d+)\]')
        if ($metricMatch.Success) {
            $adminDistance = [int]$metricMatch.Groups['ad'].Value
            $metric = [int]$metricMatch.Groups['metric'].Value
        }

        $ageSeconds = $null
        $ageMatch = [regex]::Match($trimmed, '(?<age>\d+:\d+:\d+)')
        if ($ageMatch.Success) {
            $ageSeconds = Convert-TimeSpanToSeconds -Value $ageMatch.Groups['age'].Value
        }

        if ([string]::IsNullOrWhiteSpace($interfaceName)) {
            $interfaceName = 'UNKNOWN'
        }
        if ($null -eq $adminDistance) {
            $adminDistance = 0
        }
        if ($null -eq $metric) {
            $metric = 0
        }
        if ($null -eq $ageSeconds) {
            $ageSeconds = 0
        }

        $route = [pscustomobject]@{
            Prefix        = $prefix
            PrefixLength  = $prefixLength
            NextHop       = $nextHop
            Protocol      = $protocol
            RouteRole     = 'Primary'
            RouteState    = 'Active'
            InterfaceName = $interfaceName
            AdminDistance = $adminDistance
            Metric        = $metric
            Tag           = 'CLI'
            AgeSeconds    = $ageSeconds
        }
        $routes += $route
    }

    return $routes
}

if (-not (Test-Path -LiteralPath $CapturePath)) {
    throw "Routing CLI capture not found at $CapturePath"
}
if (-not (Test-Path -LiteralPath $schemaPath)) {
    throw "Routing CLI capture schema not found at $schemaPath"
}
if (-not (Test-Path -LiteralPath $discoverySchemaPath)) {
    throw "Routing discovery capture schema not found at $discoverySchemaPath"
}

$errors = New-Object System.Collections.Generic.List[string]
$capture = Get-Content -LiteralPath $CapturePath -Raw | ConvertFrom-Json -ErrorAction Stop
$schema = Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json -ErrorAction Stop
$discoverySchema = Get-Content -LiteralPath $discoverySchemaPath -Raw | ConvertFrom-Json -ErrorAction Stop

# LANDMARK: CLI capture ingestion - validate capture manifest + resolve artifacts
$schemaVersion = Get-RequiredString -Value (Get-PropertyValue -Object $capture -Name 'SchemaVersion') -FieldName 'SchemaVersion' -Errors $errors
if ($null -ne $schemaVersion -and $schemaVersion -ne $schema.SchemaVersion) {
    Add-Error -Errors $errors -Message "SchemaVersionMismatch: expected=$($schema.SchemaVersion) actual=$schemaVersion"
}

$capturedAt = Get-RequiredString -Value (Get-PropertyValue -Object $capture -Name 'CapturedAt') -FieldName 'CapturedAt' -Errors $errors
$site = Get-RequiredString -Value (Get-PropertyValue -Object $capture -Name 'Site') -FieldName 'Site' -Errors $errors
$hostname = Get-RequiredString -Value (Get-PropertyValue -Object $capture -Name 'Hostname') -FieldName 'Hostname' -Errors $errors
$vendor = Get-RequiredString -Value (Get-PropertyValue -Object $capture -Name 'Vendor') -FieldName 'Vendor' -Errors $errors
$vrf = Get-RequiredString -Value (Get-PropertyValue -Object $capture -Name 'Vrf') -FieldName 'Vrf' -Errors $errors
$artifacts = Get-PropertyValue -Object $capture -Name 'Artifacts'
if ($null -eq $artifacts) {
    Add-Error -Errors $errors -Message 'MissingRequiredField:Artifacts'
} elseif (-not (Test-ValueType -Value $artifacts -ExpectedType 'array')) {
    if ($artifacts -is [pscustomobject]) {
        $artifacts = @($artifacts)
    } else {
        Add-Error -Errors $errors -Message "InvalidType:Artifacts expected=array actual=$($artifacts.GetType().Name)"
    }
}

# LANDMARK: Vendor support expansion - include AristaEOS and update actionable unsupported vendor messaging
$supportedVendors = @('CiscoIOSXE', 'AristaEOS')
if (-not [string]::IsNullOrWhiteSpace($vendor) -and ($supportedVendors -notcontains $vendor)) {
    Add-Error -Errors $errors -Message "UnsupportedVendor:$vendor supported=$($supportedVendors -join ',')"
}

$showIpRoutePath = $null
if ($errors.Count -eq 0) {
    $artifactIndex = 0
    foreach ($artifact in $artifacts) {
        $prefix = "Artifacts[$artifactIndex]"
        $name = Get-RequiredString -Value (Get-PropertyValue -Object $artifact -Name 'Name') -FieldName 'Name' -Errors $errors -Prefix $prefix
        $command = Get-RequiredString -Value (Get-PropertyValue -Object $artifact -Name 'Command') -FieldName 'Command' -Errors $errors -Prefix $prefix
        $path = Get-RequiredString -Value (Get-PropertyValue -Object $artifact -Name 'Path') -FieldName 'Path' -Errors $errors -Prefix $prefix

        if ($errors.Count -eq 0 -and $name -eq 'show_ip_route') {
            $resolvedPath = Resolve-ArtifactPath -CaptureFilePath $CapturePath -RelativePath $path
            $showIpRoutePath = $resolvedPath
        }
        $artifactIndex += 1
    }
}

if ($errors.Count -eq 0 -and [string]::IsNullOrWhiteSpace($showIpRoutePath)) {
    Add-Error -Errors $errors -Message 'MissingArtifact:show_ip_route'
}

if ($errors.Count -eq 0 -and -not (Test-Path -LiteralPath $showIpRoutePath)) {
    Add-Error -Errors $errors -Message "MissingArtifactFile:$showIpRoutePath"
}

$routes = @()
$linesParsedCount = 0
$linesSkippedCount = 0
if ($errors.Count -eq 0) {
    $lines = Get-Content -LiteralPath $showIpRoutePath -ErrorAction Stop
    $linesParsedCount = $lines.Count

    # LANDMARK: CLI route parsing - vendor-specific extraction for show ip route
    switch ($vendor) {
        'CiscoIOSXE' { $routes = Convert-CiscoShowIpRoute -Lines $lines -Errors $errors }
        # LANDMARK: AristaEOS route parsing - extract prefix/nexthop/interface and AD/metric for show ip route
        'AristaEOS' { $routes = Convert-AristaShowIpRoute -Lines $lines -Errors $errors }
        default { Add-Error -Errors $errors -Message "UnsupportedVendor:$vendor supported=$($supportedVendors -join ',')" }
    }
    $linesSkippedCount = [math]::Max(0, ($linesParsedCount - $routes.Count))
}

if ($errors.Count -eq 0 -and $routes.Count -eq 0) {
    Add-Error -Errors $errors -Message 'NoRoutesParsed'
}

# LANDMARK: CLI ingestion output - emit RoutingDiscoveryCapture v1 + actionable summary
$summary = [pscustomobject]@{
    Timestamp           = (Get-Date -Format o)
    Status              = if ($errors.Count -eq 0) { 'Pass' } else { 'Fail' }
    Vendor              = $vendor
    CapturePath         = (Resolve-Path -LiteralPath $CapturePath).Path
    OutputPath          = $OutputPath
    RoutesParsedCount   = $routes.Count
    LinesParsedCount    = $linesParsedCount
    LinesSkippedCount   = $linesSkippedCount
    Errors              = $errors.ToArray()
    SchemaVersion       = $schema.SchemaVersion
    DiscoverySchema     = $discoverySchema.SchemaVersion
}

Ensure-Directory -Path $SummaryPath
$summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $SummaryPath -Encoding utf8

if ($errors.Count -eq 0) {
    $siteNormalized = $site.ToUpperInvariant()
    $hostnameNormalized = $hostname.ToUpperInvariant()
    $vrfNormalized = if ([string]::IsNullOrWhiteSpace($vrf)) { 'default' } else { $vrf }
    $discoveryCapture = [pscustomobject]@{
        SchemaVersion = $discoverySchema.SchemaVersion
        CapturedAt    = $capturedAt
        Site          = $siteNormalized
        Hostname      = $hostnameNormalized
        Vrf           = $vrfNormalized
        Routes        = $routes
    }

    Ensure-Directory -Path $OutputPath
    $discoveryCapture | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutputPath -Encoding utf8
} else {
    throw "Routing CLI capture ingestion failed. See $SummaryPath"
}

if ($PassThru.IsPresent) {
    return $summary
}
