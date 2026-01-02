[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CapturePath,
    [string]$OutputRoot,
    [string]$Timestamp,
    [switch]$UpdateLatest,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path -Path $repoRoot -ChildPath 'Logs/Reports/RoutingDiscoveryPipeline'
}
if ([string]::IsNullOrWhiteSpace($Timestamp)) {
    $Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
}

$converterPath = Join-Path -Path $repoRoot -ChildPath 'Tools/Convert-RoutingDiscoveryCapture.ps1'
$schemaValidatorPath = Join-Path -Path $repoRoot -ChildPath 'Tools/Test-RoutingSchemas.ps1'
$healthConverterPath = Join-Path -Path $repoRoot -ChildPath 'Tools/Convert-RouteRecordsToHealthSnapshot.ps1'
$fixtureRoot = Join-Path -Path $repoRoot -ChildPath 'Tests/Fixtures/Routing'
$schemaRoot = Join-Path -Path $repoRoot -ChildPath 'docs/schemas/routing'
$routeHealthFixturePath = Join-Path -Path $fixtureRoot -ChildPath 'RouteHealthSnapshot.sample.json'

$pipelineSummaryPath = Join-Path -Path $OutputRoot -ChildPath ("RoutingDiscoveryPipelineSummary-{0}.json" -f $Timestamp)
$pipelineSummaryLatestPath = Join-Path -Path $OutputRoot -ChildPath 'RoutingDiscoveryPipelineSummary-latest.json'
$routeRecordsPath = Join-Path -Path $OutputRoot -ChildPath ("RouteRecords-{0}.json" -f $Timestamp)
$routeRecordsSummaryPath = Join-Path -Path $OutputRoot -ChildPath ("RoutingDiscoveryConversion-{0}.json" -f $Timestamp)
$snapshotPath = Join-Path -Path $OutputRoot -ChildPath ("RouteHealthSnapshot-{0}.json" -f $Timestamp)
$snapshotSummaryPath = Join-Path -Path $OutputRoot -ChildPath ("RouteHealthSnapshotSummary-{0}.json" -f $Timestamp)
$schemaValidationRecordsPath = Join-Path -Path $OutputRoot -ChildPath ("RoutingSchemas-RouteRecords-{0}.json" -f $Timestamp)
$schemaValidationSnapshotPath = Join-Path -Path $OutputRoot -ChildPath ("RoutingSchemas-RouteHealthSnapshot-{0}.json" -f $Timestamp)

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

function Add-StepError {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$Errors,
        [Parameter(Mandatory = $true)]
        [string]$Step,
        [Parameter(Mandatory = $true)]
        [string]$Message
    )
    $Errors.Add(("{0}:{1}" -f $Step, $Message)) | Out-Null
}

$errors = New-Object System.Collections.Generic.List[string]
$captureMetadata = $null
$conversionSummary = $null
$routeRecordsValidation = $null
$snapshotSummary = $null
$snapshotValidation = $null

# LANDMARK: Routing discovery pipeline runner - orchestrate capture->records->snapshot with schema validation
if (-not (Test-Path -LiteralPath $CapturePath)) {
    Add-StepError -Errors $errors -Step 'Capture' -Message "MissingCapturePath:$CapturePath"
} else {
    try {
        $capture = Get-Content -LiteralPath $CapturePath -Raw | ConvertFrom-Json -ErrorAction Stop
        $captureMetadata = [pscustomobject]@{
            SchemaVersion = $capture.SchemaVersion
            CapturedAt    = $capture.CapturedAt
            Site          = $capture.Site
            Hostname      = $capture.Hostname
            Vrf           = $capture.Vrf
        }
    } catch {
        Add-StepError -Errors $errors -Step 'Capture' -Message $_.Exception.Message
    }
}

if ($errors.Count -eq 0) {
    try {
        $conversionSummary = & $converterPath -CapturePath $CapturePath -RouteRecordOutputPath $routeRecordsPath -SummaryPath $routeRecordsSummaryPath -PassThru
    } catch {
        Add-StepError -Errors $errors -Step 'ConvertCapture' -Message $_.Exception.Message
    }
}

if ($errors.Count -eq 0) {
    try {
        $routeRecordsValidation = & $schemaValidatorPath -RouteRecordPath $routeRecordsPath -RouteHealthSnapshotPath $routeHealthFixturePath -FixtureRoot $fixtureRoot -SchemaRoot $schemaRoot -OutputPath $schemaValidationRecordsPath -PassThru
    } catch {
        Add-StepError -Errors $errors -Step 'ValidateRouteRecords' -Message $_.Exception.Message
    }
}

if ($errors.Count -eq 0) {
    try {
        $siteFilter = if ($null -ne $captureMetadata.Site) { [string]$captureMetadata.Site } else { $null }
        $hostnameFilter = if ($null -ne $captureMetadata.Hostname) { [string]$captureMetadata.Hostname } else { $null }
        $vrfFilter = if ($null -ne $captureMetadata.Vrf) { [string]$captureMetadata.Vrf } else { $null }

        if (-not [string]::IsNullOrWhiteSpace($siteFilter)) {
            $siteFilter = $siteFilter.ToUpperInvariant()
        }
        if (-not [string]::IsNullOrWhiteSpace($hostnameFilter)) {
            $hostnameFilter = $hostnameFilter.ToUpperInvariant()
        }
        if ([string]::IsNullOrWhiteSpace($vrfFilter)) {
            $vrfFilter = 'default'
        }

        $snapshotSummary = & $healthConverterPath -RouteRecordsPath $routeRecordsPath -Site $siteFilter -Hostname $hostnameFilter -Vrf $vrfFilter -OutputPath $snapshotPath -SummaryPath $snapshotSummaryPath -PassThru
    } catch {
        Add-StepError -Errors $errors -Step 'ConvertSnapshot' -Message $_.Exception.Message
    }
}

if ($errors.Count -eq 0) {
    try {
        $snapshotValidation = & $schemaValidatorPath -RouteRecordPath $routeRecordsPath -RouteHealthSnapshotPath $snapshotPath -FixtureRoot $fixtureRoot -SchemaRoot $schemaRoot -OutputPath $schemaValidationSnapshotPath -PassThru
    } catch {
        Add-StepError -Errors $errors -Step 'ValidateSnapshot' -Message $_.Exception.Message
    }
}

# LANDMARK: Routing discovery pipeline summary - artifact traceability + actionable failure reporting
$summary = [pscustomobject]@{
    Timestamp        = (Get-Date -Format o)
    Status           = if ($errors.Count -eq 0) { 'Pass' } else { 'Fail' }
    Mode             = 'Offline'
    CapturePath      = if (Test-Path -LiteralPath $CapturePath) { (Resolve-Path -LiteralPath $CapturePath).Path } else { $CapturePath }
    CaptureMetadata  = $captureMetadata
    ArtifactPaths    = [pscustomobject]@{
        PipelineSummaryPath        = $pipelineSummaryPath
        PipelineSummaryLatestPath  = $pipelineSummaryLatestPath
        RouteRecordsPath           = $routeRecordsPath
        RouteRecordsSummaryPath    = $routeRecordsSummaryPath
        RouteHealthSnapshotPath    = $snapshotPath
        RouteHealthSnapshotSummary = $snapshotSummaryPath
        SchemaValidationRouteRecordsPath = $schemaValidationRecordsPath
        SchemaValidationSnapshotPath     = $schemaValidationSnapshotPath
    }
    ValidationResults = [pscustomobject]@{
        RouteRecords = if ($null -ne $routeRecordsValidation) {
            [pscustomobject]@{
                Status                = $routeRecordsValidation.RouteRecord.Status
                SummaryPath           = $schemaValidationRecordsPath
                RouteRecordPath       = $routeRecordsPath
                RouteHealthSnapshotPath = $routeHealthFixturePath
            }
        } else { $null }
        RouteHealthSnapshot = if ($null -ne $snapshotValidation) {
            [pscustomobject]@{
                Status                  = $snapshotValidation.RouteHealthSnapshot.Status
                SummaryPath             = $schemaValidationSnapshotPath
                RouteRecordPath         = $routeRecordsPath
                RouteHealthSnapshotPath = $snapshotPath
            }
        } else { $null }
    }
    Errors           = $errors.ToArray()
}

Ensure-Directory -Path $pipelineSummaryPath
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $pipelineSummaryPath -Encoding utf8

if ($errors.Count -eq 0 -and $UpdateLatest.IsPresent) {
    # LANDMARK: Routing discovery pipeline latest pointer - deterministic surfacing output
    Copy-Item -LiteralPath $pipelineSummaryPath -Destination $pipelineSummaryLatestPath -Force
}

if ($summary.Status -ne 'Pass') {
    throw "Routing discovery pipeline failed. See $pipelineSummaryPath"
}

if ($PassThru.IsPresent) {
    return $summary
}
