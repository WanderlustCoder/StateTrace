[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SessionPath,
    [Parameter(Mandatory = $true)]
    [string]$OutputPath,
    [string]$SshExePath = 'ssh',
    [switch]$RequireSsh,
    [string]$SshUser,
    [string]$SshIdentityFile,
    [int]$SshPort = 22,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Add-Check {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Checks,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [ValidateSet('Pass','Warning','Fail')]
        [string]$Status,
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $Checks.Add([pscustomobject]@{
        Name    = $Name
        Status  = $Status
        Message = $Message
    }) | Out-Null
}

function Test-ValueType {
    param(
        [Parameter(Mandatory = $true)]
        $Value,
        [Parameter(Mandatory = $true)]
        [string]$ExpectedType
    )

    switch ($ExpectedType) {
        'string' { return ($Value -is [string]) }
        'array' { return ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) }
        default { return $false }
    }
}

function Get-PropertyValue {
    param(
        [Parameter(Mandatory = $true)]
        $Object,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Test-TranscriptPathSafety {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return @{ Ok = $false; Message = 'TranscriptPath is empty.' }
    }
    if ([System.IO.Path]::IsPathRooted($Path)) {
        return @{ Ok = $false; Message = "TranscriptPath is rooted: $Path" }
    }
    if ($Path -match '(^|[\\/])\.\.([\\/]|$)') {
        return @{ Ok = $false; Message = "TranscriptPath contains path traversal: $Path" }
    }
    $invalidChars = [System.IO.Path]::GetInvalidPathChars()
    if ($Path.IndexOfAny($invalidChars) -ge 0) {
        return @{ Ok = $false; Message = "TranscriptPath contains invalid characters: $Path" }
    }
    return @{ Ok = $true; Message = 'TranscriptPath is safe.' }
}

function Resolve-SshExecutable {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    if (Test-Path -LiteralPath $Path) {
        return (Resolve-Path -LiteralPath $Path).Path
    }
    $cmd = Get-Command -Name $Path -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Path }
    return $null
}

$checks = New-Object System.Collections.Generic.List[object]
$supportedVendors = @('CiscoIOSXE', 'AristaEOS')
$session = $null

# LANDMARK: Online capture readiness - validate session manifest, vendor support, and gating prerequisites
if (-not (Test-Path -LiteralPath $SessionPath)) {
    Add-Check -Checks $checks -Name 'SessionPath' -Status 'Fail' -Message "Session manifest not found: $SessionPath"
} else {
    try {
        $session = Get-Content -LiteralPath $SessionPath -Raw | ConvertFrom-Json -ErrorAction Stop
        Add-Check -Checks $checks -Name 'SessionPath' -Status 'Pass' -Message "Session manifest loaded: $SessionPath"
    } catch {
        Add-Check -Checks $checks -Name 'SessionPath' -Status 'Fail' -Message "Session manifest invalid JSON: $SessionPath"
    }
}

$requiredFields = @('SchemaVersion','CapturedAt','Site','Vendor','Vrf','Hosts')
$missingFields = [System.Collections.Generic.List[string]]::new()
if ($session) {
    foreach ($field in $requiredFields) {
        if ($null -eq (Get-PropertyValue -Object $session -Name $field)) {
            [void]$missingFields.Add($field)
        }
    }
}

if ($missingFields.Count -gt 0) {
    Add-Check -Checks $checks -Name 'RequiredFields' -Status 'Fail' -Message ("Missing required fields: {0}" -f ($missingFields -join ', '))
} elseif ($session) {
    Add-Check -Checks $checks -Name 'RequiredFields' -Status 'Pass' -Message 'Required fields present.'
}

$vendor = $null
if ($session) { $vendor = [string](Get-PropertyValue -Object $session -Name 'Vendor') }
if ($session -and -not [string]::IsNullOrWhiteSpace($vendor)) {
    if ($supportedVendors -contains $vendor) {
        Add-Check -Checks $checks -Name 'VendorSupport' -Status 'Pass' -Message "Vendor supported: $vendor"
    } else {
        Add-Check -Checks $checks -Name 'VendorSupport' -Status 'Fail' -Message ("Unsupported vendor: {0}. Supported: {1}" -f $vendor, ($supportedVendors -join ', '))
    }
}

$hosts = $null
if ($session) { $hosts = Get-PropertyValue -Object $session -Name 'Hosts' }
if ($session -and $null -eq $hosts) {
    Add-Check -Checks $checks -Name 'Hosts' -Status 'Fail' -Message 'Missing required Hosts array.'
} elseif ($session -and -not (Test-ValueType -Value $hosts -ExpectedType 'array')) {
    if ($hosts -is [pscustomobject]) {
        $hosts = @($hosts)
    } else {
        Add-Check -Checks $checks -Name 'Hosts' -Status 'Fail' -Message ("Hosts is not an array. Actual type: {0}" -f $hosts.GetType().Name)
    }
}

if ($session -and $hosts -and $hosts.Count -gt 0) {
    Add-Check -Checks $checks -Name 'Hosts' -Status 'Pass' -Message ("Hosts present: {0}" -f $hosts.Count)
} elseif ($session -and $hosts -and $hosts.Count -eq 0) {
    Add-Check -Checks $checks -Name 'Hosts' -Status 'Fail' -Message 'Hosts array is empty.'
}

# LANDMARK: Online capture readiness - transcript path safety checks
if ($session -and $hosts -and $hosts.Count -gt 0) {
    foreach ($hostEntry in $hosts) {
        $hostname = [string](Get-PropertyValue -Object $hostEntry -Name 'Hostname')
        if ([string]::IsNullOrWhiteSpace($hostname)) {
            Add-Check -Checks $checks -Name 'HostName' -Status 'Fail' -Message 'Host entry missing Hostname.'
            continue
        }
        $artifacts = Get-PropertyValue -Object $hostEntry -Name 'Artifacts'
        if ($null -eq $artifacts) {
            Add-Check -Checks $checks -Name "HostArtifacts:$hostname" -Status 'Fail' -Message "Host $hostname missing Artifacts."
            continue
        }
        if (-not (Test-ValueType -Value $artifacts -ExpectedType 'array')) {
            if ($artifacts -is [pscustomobject]) {
                $artifacts = @($artifacts)
            } else {
                Add-Check -Checks $checks -Name "HostArtifacts:$hostname" -Status 'Fail' -Message "Host $hostname artifacts not an array."
                continue
            }
        }

        $hasShow = $false
        foreach ($artifact in $artifacts) {
            $name = [string](Get-PropertyValue -Object $artifact -Name 'Name')
            $command = [string](Get-PropertyValue -Object $artifact -Name 'Command')
            $path = [string](Get-PropertyValue -Object $artifact -Name 'TranscriptPath')
            if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($command) -or [string]::IsNullOrWhiteSpace($path)) {
                Add-Check -Checks $checks -Name "HostArtifacts:$hostname" -Status 'Fail' -Message "Host $hostname has artifact with missing Name/Command/TranscriptPath."
                continue
            }
            if ($name -eq 'show_ip_route') { $hasShow = $true }
            $pathCheck = Test-TranscriptPathSafety -Path $path
            if (-not $pathCheck.Ok) {
                Add-Check -Checks $checks -Name "TranscriptPath:$hostname" -Status 'Fail' -Message $pathCheck.Message
            }
        }

        if (-not $hasShow) {
            Add-Check -Checks $checks -Name "HostArtifacts:$hostname" -Status 'Fail' -Message "Host $hostname missing required show_ip_route artifact."
        } else {
            Add-Check -Checks $checks -Name "HostArtifacts:$hostname" -Status 'Pass' -Message "Host $hostname artifact list includes show_ip_route."
        }
    }
}

# LANDMARK: Online capture readiness - ssh/identity file checks and recommended commands output
$sshResolved = Resolve-SshExecutable -Path $SshExePath
if ($null -eq $sshResolved) {
    $status = if ($RequireSsh.IsPresent) { 'Fail' } else { 'Warning' }
    Add-Check -Checks $checks -Name 'SshExecutable' -Status $status -Message "SSH executable not found: $SshExePath"
} else {
    Add-Check -Checks $checks -Name 'SshExecutable' -Status 'Pass' -Message "SSH executable resolved: $sshResolved"
}

if (-not [string]::IsNullOrWhiteSpace($SshIdentityFile)) {
    if (-not (Test-Path -LiteralPath $SshIdentityFile)) {
        Add-Check -Checks $checks -Name 'SshIdentityFile' -Status 'Fail' -Message "SSH identity file not found: $SshIdentityFile"
    } else {
        Add-Check -Checks $checks -Name 'SshIdentityFile' -Status 'Pass' -Message "SSH identity file found: $SshIdentityFile"
    }
} else {
    Add-Check -Checks $checks -Name 'SshIdentityFile' -Status 'Pass' -Message 'SSH identity file not specified.'
}

$envEnabled = ($env:STATETRACE_ALLOW_NETWORK_CAPTURE -eq '1')
$gatingMessage = if ($envEnabled) {
    'Network capture environment flag is enabled.'
} else {
    'Network capture environment flag is not enabled; set STATETRACE_ALLOW_NETWORK_CAPTURE=1 for online capture.'
}
$gatingStatus = if ($envEnabled) { 'Pass' } else { 'Warning' }
Add-Check -Checks $checks -Name 'NetworkCaptureGating' -Status $gatingStatus -Message $gatingMessage

$overallStatus = 'Pass'
if ($checks | Where-Object { $_.Status -eq 'Fail' }) {
    $overallStatus = 'Fail'
} elseif ($checks | Where-Object { $_.Status -eq 'Warning' }) {
    $overallStatus = 'Warning'
}

$userToken = if ([string]::IsNullOrWhiteSpace($SshUser)) { '<ssh-user>' } else { $SshUser }
$identityToken = if ([string]::IsNullOrWhiteSpace($SshIdentityFile)) { '<path-to-key>' } else { $SshIdentityFile }
$sshExeToken = if ([string]::IsNullOrWhiteSpace($SshExePath) -or $SshExePath -eq 'ssh') { 'ssh' } else { $SshExePath }

$captureCommand = @(
    "pwsh -NoProfile -File Tools/Invoke-RoutingCliCaptureSession.ps1",
    "-SessionPath `"$SessionPath`"",
    "-Mode Online",
    "-AllowNetworkCapture",
    "-SshUser `"$userToken`"",
    "-SshPort $SshPort",
    "-SshExePath `"$sshExeToken`""
) -join ' '
if (-not [string]::IsNullOrWhiteSpace($SshIdentityFile)) {
    $captureCommand += (" -SshIdentityFile `"{0}`"" -f $identityToken)
} else {
    $captureCommand += " -SshIdentityFile `"$identityToken`""
}

$summary = [pscustomobject]@{
    Timestamp                   = (Get-Date -Format o)
    Status                      = $overallStatus
    SessionPath                 = $SessionPath
    Vendor                      = $vendor
    SupportedVendors            = $supportedVendors
    NetworkCaptureEnvEnabled    = $envEnabled
    RequireSsh                  = $RequireSsh.IsPresent
    SshExeResolved              = $sshResolved
    SshUserProvided             = (-not [string]::IsNullOrWhiteSpace($SshUser))
    Checks                      = $checks
    RecommendedCommands         = [pscustomobject]@{
        EnableGating = '$env:STATETRACE_ALLOW_NETWORK_CAPTURE=''1'''
        Preflight    = "pwsh -NoProfile -File Tools/Test-RoutingOnlineCaptureReadiness.ps1 -SessionPath `"$SessionPath`" -OutputPath `"$OutputPath`""
        CaptureOnline = $captureCommand
        Ingest       = 'pwsh -NoProfile -File Tools/Convert-RoutingCliCaptureToDiscoveryCapture.ps1 -CapturePath <Capture.json> -OutputPath Logs/Reports/RoutingDiscoveryCapture-<timestamp>.json -SummaryPath Logs/Reports/RoutingCliIngestionSummary-<timestamp>.json -PassThru'
        Pipeline     = 'pwsh -NoProfile -File Tools/Invoke-RoutingDiscoveryPipeline.ps1 -CapturePath <RoutingDiscoveryCapture.json> -OutputRoot Logs/Reports/RoutingDiscoveryPipeline -UpdateLatest -PassThru'
    }
}

$outputDirectory = Split-Path -Parent $OutputPath
if (-not [string]::IsNullOrWhiteSpace($outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}
$summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutputPath -Encoding utf8

if ($overallStatus -eq 'Fail') {
    throw "Online capture readiness failed. See $OutputPath"
}

if ($PassThru.IsPresent) {
    return $summary
}
