[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SessionPath,
    [ValidateSet('Offline','Online')]
    [string]$Mode = 'Offline',
    [switch]$AllowNetworkCapture,
    [string]$OutputRoot,
    [string]$Timestamp = (Get-Date -Format 'yyyyMMdd-HHmmss'),
    [switch]$UpdateLatest,
    [string]$SshUser,
    [int]$SshPort = 22,
    [string]$SshIdentityFile,
    [string]$SshExePath = 'ssh',
    [string[]]$SshOptions,
    [scriptblock]$TranscriptCaptureScriptBlock,
    [int]$MaxHosts,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$preflightPath = Join-Path -Path $repoRoot -ChildPath 'Tools/Test-RoutingOnlineCaptureReadiness.ps1'
$sessionRunnerPath = Join-Path -Path $repoRoot -ChildPath 'Tools/Invoke-RoutingCliCaptureSession.ps1'
$ingestPath = Join-Path -Path $repoRoot -ChildPath 'Tools/Convert-RoutingCliCaptureToDiscoveryCapture.ps1'
$pipelinePath = Join-Path -Path $repoRoot -ChildPath 'Tools/Invoke-RoutingDiscoveryPipeline.ps1'

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path -Path $repoRoot -ChildPath 'Logs/Reports/RoutingValidationRun'
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

function Resolve-HostList {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Hosts,
        [int]$MaxHosts
    )

    if ($MaxHosts -le 0 -or $Hosts.Count -le $MaxHosts) {
        return $Hosts
    }
    return $Hosts | Select-Object -First $MaxHosts
}

$errors = New-Object System.Collections.Generic.List[string]
$onlineMode = ($Mode -eq 'Online')
$envAllowsNetwork = ($env:STATETRACE_ALLOW_NETWORK_CAPTURE -eq '1')

if (-not (Test-Path -LiteralPath $SessionPath)) {
    Add-Error -Errors $errors -Message "MissingSessionPath:$SessionPath"
}

$sessionMetadata = $null
if ($errors.Count -eq 0) {
    try {
        $sessionMetadata = Get-Content -LiteralPath $SessionPath -Raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Add-Error -Errors $errors -Message "SessionParseFailed:$($_.Exception.Message)"
    }
}

# LANDMARK: Routing validation orchestrator - preflight capture ingest pipeline with traceable artifacts
if ($onlineMode -and (-not $AllowNetworkCapture.IsPresent -or -not $envAllowsNetwork)) {
    Add-Error -Errors $errors -Message 'Online capture is disabled by default. Set STATETRACE_ALLOW_NETWORK_CAPTURE=1 and pass -AllowNetworkCapture.'
}

$runRoot = Join-Path -Path $OutputRoot -ChildPath ("Run-{0}" -f $Timestamp)
$preflightSummaryPath = Join-Path -Path $runRoot -ChildPath 'PreflightSummary.json'
$captureOutputRoot = Join-Path -Path $runRoot -ChildPath 'CaptureSession'
$ingestionRoot = Join-Path -Path $runRoot -ChildPath 'Ingestion'
$pipelineRoot = Join-Path -Path $runRoot -ChildPath 'Pipeline'
$runSummaryPath = Join-Path -Path $runRoot -ChildPath ("RoutingValidationRunSummary-{0}.json" -f $Timestamp)
$runSummaryLatestPath = Join-Path -Path $OutputRoot -ChildPath 'RoutingValidationRunSummary-latest.json'

$preflightSummary = $null
$captureSummary = $null
$hostSummaries = [System.Collections.Generic.List[pscustomobject]]::new()
$hostsProcessed = 0
$hostsSucceeded = 0
$hostsFailed = 0
$maxHostsApplied = $null

if ($errors.Count -eq 0) {
    try {
        $requireSsh = ($onlineMode -and ($null -eq $TranscriptCaptureScriptBlock))
        $preflightArgs = @{
            SessionPath = $SessionPath
            OutputPath  = $preflightSummaryPath
            SshExePath  = $SshExePath
            SshPort     = $SshPort
            SshUser     = $SshUser
        }
        if ($requireSsh) {
            $preflightArgs.RequireSsh = $true
        }
        if (-not [string]::IsNullOrWhiteSpace($SshIdentityFile)) {
            $preflightArgs.SshIdentityFile = $SshIdentityFile
        }
        $preflightSummary = & $preflightPath @preflightArgs -PassThru
        if ($preflightSummary.Status -eq 'Fail') {
            Add-Error -Errors $errors -Message "PreflightFailed:see=$preflightSummaryPath"
        }
    } catch {
        if (Test-Path -LiteralPath $preflightSummaryPath) {
            $preflightSummary = Get-Content -LiteralPath $preflightSummaryPath -Raw | ConvertFrom-Json
        }
        Add-Error -Errors $errors -Message "PreflightException:$($_.Exception.Message)"
    }
}

if ($errors.Count -eq 0) {
    try {
        $captureArgs = @{
            SessionPath = $SessionPath
            Mode        = $Mode
            OutputRoot  = $captureOutputRoot
            Timestamp   = $Timestamp
            PassThru    = $true
        }
        if ($onlineMode) {
            $captureArgs.AllowNetworkCapture = $true
            $captureArgs.SshUser = $SshUser
            $captureArgs.SshPort = $SshPort
            $captureArgs.SshExePath = $SshExePath
            if ($null -ne $SshOptions) {
                $captureArgs.SshOptions = $SshOptions
            }
            if (-not [string]::IsNullOrWhiteSpace($SshIdentityFile)) {
                $captureArgs.SshIdentityFile = $SshIdentityFile
            }
            if ($null -ne $TranscriptCaptureScriptBlock) {
                $captureArgs.TranscriptCaptureScriptBlock = $TranscriptCaptureScriptBlock
            }
        }
        $captureSummary = & $sessionRunnerPath @captureArgs
        if ($captureSummary.Status -ne 'Pass') {
            Add-Error -Errors $errors -Message "CaptureFailed:see=$($captureSummary.OutputRoot)"
        }
    } catch {
        $captureSummaryPath = Join-Path -Path $captureOutputRoot -ChildPath ("RoutingCliCaptureSessionSummary-{0}.json" -f $Timestamp)
        if (Test-Path -LiteralPath $captureSummaryPath) {
            $captureSummary = Get-Content -LiteralPath $captureSummaryPath -Raw | ConvertFrom-Json
        }
        Add-Error -Errors $errors -Message "CaptureException:$($_.Exception.Message)"
    }
}

if ($errors.Count -eq 0 -and $null -ne $captureSummary) {
    $selectedHosts = @()
    if ($null -ne $captureSummary.HostSummaries) {
        $selectedHosts = Resolve-HostList -Hosts $captureSummary.HostSummaries -MaxHosts $MaxHosts
    }
    if ($selectedHosts.Count -eq 0) {
        Add-Error -Errors $errors -Message 'NoHostsSelected: capture summary contained no host entries.'
    } elseif ($MaxHosts -gt 0 -and $selectedHosts.Count -lt $captureSummary.HostSummaries.Count) {
        $maxHostsApplied = $selectedHosts.Count
    }

    foreach ($hostEntry in $selectedHosts) {
        $hostsProcessed += 1
        $hostErrors = New-Object System.Collections.Generic.List[string]
        $hostname = [string]$hostEntry.Hostname
        $capturePath = [string]$hostEntry.CaptureJsonPath
        $ingestHostRoot = Join-Path -Path $ingestionRoot -ChildPath $hostname
        $pipelineHostRoot = Join-Path -Path $pipelineRoot -ChildPath $hostname
        $discoveryOutput = Join-Path -Path $ingestHostRoot -ChildPath ("RoutingDiscoveryCapture-{0}.json" -f $Timestamp)
        $ingestSummaryPath = Join-Path -Path $ingestHostRoot -ChildPath ("RoutingCliIngestionSummary-{0}.json" -f $Timestamp)
        $pipelineSummaryPath = Join-Path -Path $pipelineHostRoot -ChildPath ("RoutingDiscoveryPipelineSummary-{0}.json" -f $Timestamp)
        $hostStatus = 'Pass'

        if (-not (Test-Path -LiteralPath $capturePath)) {
            Add-Error -Errors $hostErrors -Message "MissingCaptureJson:$capturePath"
            $hostStatus = 'Fail'
        } else {
            try {
                & $ingestPath -CapturePath $capturePath -OutputPath $discoveryOutput -SummaryPath $ingestSummaryPath -PassThru | Out-Null
            } catch {
                Add-Error -Errors $hostErrors -Message "IngestionFailed:$($_.Exception.Message)"
                $hostStatus = 'Fail'
            }
        }

        if ($hostStatus -eq 'Pass') {
            try {
                & $pipelinePath -CapturePath $discoveryOutput -OutputRoot $pipelineHostRoot -Timestamp $Timestamp -PassThru | Out-Null
            } catch {
                Add-Error -Errors $hostErrors -Message "PipelineFailed:$($_.Exception.Message)"
                $hostStatus = 'Fail'
            }
        }

        if ($hostStatus -eq 'Pass') {
            $hostsSucceeded += 1
        } else {
            $hostsFailed += 1
            Add-Error -Errors $errors -Message "HostFailed:$hostname"
        }

        $hostSummaries.Add([pscustomobject]@{
            Hostname             = $hostname
            CaptureJsonPath      = $capturePath
            IngestionSummaryPath = $ingestSummaryPath
            PipelineSummaryPath  = $pipelineSummaryPath
            Status               = $hostStatus
            Errors               = $hostErrors.ToArray()
        })
    }
}

$summary = [pscustomobject]@{
    Timestamp                    = (Get-Date -Format o)
    Status                       = if ($errors.Count -eq 0 -and $hostsFailed -eq 0) { 'Pass' } else { 'Fail' }
    Mode                         = $Mode
    SessionPath                  = if (Test-Path -LiteralPath $SessionPath) { (Resolve-Path -LiteralPath $SessionPath).Path } else { $SessionPath }
    RunFolder                    = $runRoot
    Vendor                       = if ($null -ne $sessionMetadata) { $sessionMetadata.Vendor } else { $null }
    Site                         = if ($null -ne $sessionMetadata) { $sessionMetadata.Site } else { $null }
    Vrf                          = if ($null -ne $sessionMetadata) { $sessionMetadata.Vrf } else { $null }
    AllowNetworkCaptureSwitch    = $AllowNetworkCapture.IsPresent
    EnvironmentAllowNetworkCapture = $envAllowsNetwork
    NetworkCaptureAllowed        = ($onlineMode -and $AllowNetworkCapture.IsPresent -and $envAllowsNetwork)
    PreflightSummaryPath         = $preflightSummaryPath
    CaptureSessionSummaryPath    = if ($null -ne $captureSummary) { (Join-Path -Path $captureOutputRoot -ChildPath ("RoutingCliCaptureSessionSummary-{0}.json" -f $Timestamp)) } else { $null }
    HostsProcessedCount          = $hostsProcessed
    HostsSucceededCount          = $hostsSucceeded
    HostsFailedCount             = $hostsFailed
    MaxHosts                     = if ($MaxHosts -gt 0) { $MaxHosts } else { $null }
    MaxHostsApplied              = $maxHostsApplied
    HostSummaries                = $hostSummaries
    Errors                       = $errors.ToArray()
}

# LANDMARK: Routing validation summary - per-host status and actionable failure reporting
Ensure-Directory -Path $runSummaryPath
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $runSummaryPath -Encoding utf8

if ($summary.Status -eq 'Pass' -and $UpdateLatest.IsPresent) {
    # LANDMARK: Routing validation latest pointer - deterministic surfacing output
    Copy-Item -LiteralPath $runSummaryPath -Destination $runSummaryLatestPath -Force
}

if ($summary.Status -ne 'Pass') {
    $primaryError = $errors | Select-Object -First 1
    if (-not [string]::IsNullOrWhiteSpace($primaryError)) {
        throw "$primaryError See $runSummaryPath"
    }
    throw "Routing validation run failed. See $runSummaryPath"
}

if ($PassThru.IsPresent) {
    return $summary
}
