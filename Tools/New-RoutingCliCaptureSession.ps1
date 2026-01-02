[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$HostsPath,
    [Parameter(Mandatory = $true)]
    [string]$Site,
    [Parameter(Mandatory = $true)]
    [ValidateSet('CiscoIOSXE', 'AristaEOS')]
    [string]$Vendor,
    [string]$Vrf = 'default',
    [Parameter(Mandatory = $true)]
    [string]$OutputPath,
    [string]$CapturedAt,
    [string]$TranscriptPathTemplate = '{Hostname}_show_ip_route.txt',
    [string]$ArtifactName = 'show_ip_route',
    [string]$CommandTemplate,
    [switch]$SortHosts,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$schemaPath = Join-Path -Path $repoRoot -ChildPath 'docs/schemas/routing/routing_cli_capture_session.schema.json'

if (-not (Test-Path -LiteralPath $schemaPath)) {
    throw "Routing session schema not found at $schemaPath"
}

$schema = Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json
$schemaVersion = $schema.SchemaVersion
if ([string]::IsNullOrWhiteSpace($schemaVersion)) {
    throw 'Routing session schema is missing SchemaVersion'
}

if (-not (Test-Path -LiteralPath $HostsPath)) {
    throw "Hosts list not found at $HostsPath"
}

$rawLines = Get-Content -LiteralPath $HostsPath
$hosts = New-Object 'System.Collections.Generic.List[string]'
$duplicates = New-Object 'System.Collections.Generic.List[string]'
$seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

foreach ($line in $rawLines) {
    $trimmed = $line.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        continue
    }
    if ($trimmed.StartsWith('#')) {
        continue
    }
    if (-not $seen.Add($trimmed)) {
        $duplicates.Add($trimmed) | Out-Null
        continue
    }
    $hosts.Add($trimmed) | Out-Null
}

if ($hosts.Count -eq 0) {
    throw 'Hosts list is empty after filtering (blank/comment-only lines).'
}

if ($duplicates.Count -gt 0) {
    $duplicateList = ($duplicates | Sort-Object -Unique) -join ', '
    throw "Duplicate hostnames detected in ${HostsPath}: $duplicateList"
}

$shouldSortHosts = $true
if ($PSBoundParameters.ContainsKey('SortHosts')) {
    $shouldSortHosts = [bool]$SortHosts
}

if ($shouldSortHosts) {
    $hosts.Sort([System.StringComparer]::OrdinalIgnoreCase)
}

if ([string]::IsNullOrWhiteSpace($CapturedAt)) {
    $CapturedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
}

$resolvedCommandTemplate = $CommandTemplate
if ([string]::IsNullOrWhiteSpace($resolvedCommandTemplate)) {
    if ($Vrf -eq 'default') {
        $resolvedCommandTemplate = 'show ip route'
    } else {
        $resolvedCommandTemplate = "show ip route vrf $Vrf"
    }
}

$hostEntries = New-Object 'System.Collections.Generic.List[object]'

foreach ($hostname in $hosts) {
    $artifactCommand = $resolvedCommandTemplate.Replace('{Vrf}', $Vrf).Replace('{Hostname}', $hostname)
    $artifactPath = $TranscriptPathTemplate.Replace('{Hostname}', $hostname)

    $artifact = [ordered]@{
        Name           = $ArtifactName
        Command        = $artifactCommand
        TranscriptPath = $artifactPath
    }

    $hostEntries.Add([pscustomobject]([ordered]@{
        Hostname  = $hostname
        Artifacts = @([pscustomobject]$artifact)
    })) | Out-Null
}

# LANDMARK: Session manifest generator - parse host list, enforce uniqueness, and normalize hostnames
# LANDMARK: Session manifest generator - build deterministic RoutingCliCaptureSession v1 output
$manifest = [pscustomobject]([ordered]@{
    SchemaVersion = $schemaVersion
    CapturedAt    = $CapturedAt
    Site          = $Site
    Vendor        = $Vendor
    Vrf           = $Vrf
    Hosts         = $hostEntries
})

$outputDirectory = Split-Path -Parent $OutputPath
if (-not [string]::IsNullOrWhiteSpace($outputDirectory) -and -not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -Path $outputDirectory -ItemType Directory -Force | Out-Null
}

# LANDMARK: Session manifest generator - stable JSON emission with fixed ordering
$json = $manifest | ConvertTo-Json -Depth 6
Set-Content -LiteralPath $OutputPath -Value $json -Encoding UTF8

if ($PassThru) {
    $manifest
}
