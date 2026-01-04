[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SessionPath,
    [ValidateSet('Offline', 'Online')]
    [string]$Mode = 'Offline',
    [switch]$AllowNetworkCapture,
    [string]$OutputRoot,
    [string]$Timestamp = (Get-Date -Format 'yyyyMMdd-HHmmss'),
    [switch]$UpdateLatest,
    [switch]$PassThru,
    [string]$SshUser,
    [int]$SshPort = 22,
    [string]$SshIdentityFile,
    [string]$SshExePath = 'ssh',
    [string[]]$SshOptions,
    [int]$SshConnectTimeoutSeconds = 10,
    [int]$SshSessionTimeoutSeconds = 60,
    [scriptblock]$TranscriptCaptureScriptBlock
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$sessionSchemaPath = Join-Path -Path $repoRoot -ChildPath 'docs/schemas/routing/routing_cli_capture_session.schema.json'
$captureSchemaPath = Join-Path -Path $repoRoot -ChildPath 'docs/schemas/routing/routing_cli_capture.schema.json'

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path -Path $repoRoot -ChildPath 'Logs/Reports/RoutingCliCaptureSession'
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

function Resolve-TranscriptPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SessionFilePath,
        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )
    $baseDirectory = Split-Path -Parent $SessionFilePath
    return (Join-Path -Path $baseDirectory -ChildPath $RelativePath)
}

function Resolve-OutputTranscriptPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutputDirectory,
        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    if ([System.IO.Path]::IsPathRooted($RelativePath)) {
        throw "TranscriptPathTraversal: rooted path $RelativePath is not allowed"
    }

    $fullOutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
    $candidatePath = Join-Path -Path $OutputDirectory -ChildPath $RelativePath
    $fullCandidatePath = [System.IO.Path]::GetFullPath($candidatePath)

    if (-not $fullCandidatePath.StartsWith($fullOutputDirectory, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "TranscriptPathTraversal: $RelativePath resolves outside $OutputDirectory"
    }

    return $fullCandidatePath
}

function Invoke-RoutingCliSshTranscriptCapture {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Hostname,
        [Parameter(Mandatory = $true)]
        [string]$SshUser,
        [Parameter(Mandatory = $true)]
        [string]$Command,
        [Parameter(Mandatory = $true)]
        [string]$OutputPath,
        [int]$SshPort = 22,
        [string]$SshIdentityFile,
        [string]$SshExePath = 'ssh',
        [string[]]$SshOptions,
        [int]$SshConnectTimeoutSeconds = 10,
        [int]$SshSessionTimeoutSeconds = 60
    )

    $sshArgs = @()
    if (-not [string]::IsNullOrWhiteSpace($SshIdentityFile)) {
        $sshArgs += @('-i', $SshIdentityFile)
    }
    $sshArgs += @('-p', $SshPort)
    $sshArgs += @('-o', "ConnectTimeout=$SshConnectTimeoutSeconds")
    $sshArgs += @('-o', 'BatchMode=yes')
    if ($null -ne $SshOptions) {
        $sshArgs += $SshOptions
    }

    $target = "$SshUser@$Hostname"
    $remoteCommand = "terminal length 0; $Command"
    $sshArgs += @($target, $remoteCommand)

    $argumentString = ($sshArgs | ForEach-Object {
        if ($_ -match '[\\s\"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
    }) -join ' '

    $tempOutput = [System.IO.Path]::GetTempFileName()
    $tempError = [System.IO.Path]::GetTempFileName()
    $process = Start-Process -FilePath $SshExePath -ArgumentList $argumentString -NoNewWindow -PassThru `
        -RedirectStandardOutput $tempOutput -RedirectStandardError $tempError

    $completed = $process | Wait-Process -Timeout $SshSessionTimeoutSeconds -ErrorAction SilentlyContinue
    if (-not $process.HasExited) {
        $process | Stop-Process -Force
        Remove-Item -LiteralPath @($tempOutput, $tempError) -Force -ErrorAction SilentlyContinue
        throw "SshSessionTimeout: exceeded ${SshSessionTimeoutSeconds}s for $Hostname"
    }

    $output = @()
    if (Test-Path -LiteralPath $tempOutput) {
        $output += (Get-Content -LiteralPath $tempOutput -Raw)
    }
    if (Test-Path -LiteralPath $tempError) {
        $output += (Get-Content -LiteralPath $tempError -Raw)
    }
    $output -join [Environment]::NewLine | Set-Content -LiteralPath $OutputPath -Encoding utf8
    Remove-Item -LiteralPath @($tempOutput, $tempError) -Force -ErrorAction SilentlyContinue
}

if (-not (Test-Path -LiteralPath $SessionPath)) {
    throw "Routing CLI capture session not found at $SessionPath"
}
if (-not (Test-Path -LiteralPath $sessionSchemaPath)) {
    throw "Routing CLI capture session schema not found at $sessionSchemaPath"
}
if (-not (Test-Path -LiteralPath $captureSchemaPath)) {
    throw "Routing CLI capture schema not found at $captureSchemaPath"
}

$errors = New-Object System.Collections.Generic.List[string]
$session = Get-Content -LiteralPath $SessionPath -Raw | ConvertFrom-Json -ErrorAction Stop
$schema = Get-Content -LiteralPath $sessionSchemaPath -Raw | ConvertFrom-Json -ErrorAction Stop
$captureSchema = Get-Content -LiteralPath $captureSchemaPath -Raw | ConvertFrom-Json -ErrorAction Stop

$onlineMode = ($Mode -eq 'Online')
$environmentAllowsNetwork = ($env:STATETRACE_ALLOW_NETWORK_CAPTURE -eq '1')

# LANDMARK: Online capture gating - require explicit env var + switch for network operations
if ($onlineMode) {
    if (-not $AllowNetworkCapture.IsPresent -or -not $environmentAllowsNetwork) {
        throw 'Online capture is disabled by default. Set STATETRACE_ALLOW_NETWORK_CAPTURE=1 and pass -AllowNetworkCapture.'
    }
    if ([string]::IsNullOrWhiteSpace($SshUser)) {
        throw 'Online capture requires -SshUser for key-based SSH.'
    }
    if ($null -eq $TranscriptCaptureScriptBlock) {
        $sshCommand = Get-Command -Name $SshExePath -ErrorAction Stop
        if ($null -eq $sshCommand) {
            throw "SSH executable not found at $SshExePath"
        }
    }
}

# LANDMARK: Routing CLI capture session - validate session manifest and resolve transcripts
$schemaVersion = Get-RequiredString -Value (Get-PropertyValue -Object $session -Name 'SchemaVersion') -FieldName 'SchemaVersion' -Errors $errors
if ($null -ne $schemaVersion -and $schemaVersion -ne $schema.SchemaVersion) {
    Add-Error -Errors $errors -Message "SchemaVersionMismatch: expected=$($schema.SchemaVersion) actual=$schemaVersion"
}

$capturedAt = Get-RequiredString -Value (Get-PropertyValue -Object $session -Name 'CapturedAt') -FieldName 'CapturedAt' -Errors $errors
$site = Get-RequiredString -Value (Get-PropertyValue -Object $session -Name 'Site') -FieldName 'Site' -Errors $errors
$vendor = Get-RequiredString -Value (Get-PropertyValue -Object $session -Name 'Vendor') -FieldName 'Vendor' -Errors $errors
$vrf = Get-RequiredString -Value (Get-PropertyValue -Object $session -Name 'Vrf') -FieldName 'Vrf' -Errors $errors
$hosts = Get-PropertyValue -Object $session -Name 'Hosts'
if ($null -eq $hosts) {
    Add-Error -Errors $errors -Message 'MissingRequiredField:Hosts'
} elseif (-not (Test-ValueType -Value $hosts -ExpectedType 'array')) {
    if ($hosts -is [pscustomobject]) {
        $hosts = @($hosts)
    } else {
        Add-Error -Errors $errors -Message "InvalidType:Hosts expected=array actual=$($hosts.GetType().Name)"
    }
}

$supportedVendors = @('CiscoIOSXE')
if (-not [string]::IsNullOrWhiteSpace($vendor) -and ($supportedVendors -notcontains $vendor)) {
    Add-Error -Errors $errors -Message "UnsupportedVendor:$vendor supported=$($supportedVendors -join ',')"
}

$preparedHosts = [System.Collections.Generic.List[pscustomobject]]::new()
$hostIndex = 0
if ($null -ne $hosts) {
    foreach ($hostEntry in $hosts) {
        $hostPrefix = "Hosts[$hostIndex]"
        $hostname = Get-RequiredString -Value (Get-PropertyValue -Object $hostEntry -Name 'Hostname') -FieldName 'Hostname' -Errors $errors -Prefix $hostPrefix
        $artifacts = Get-PropertyValue -Object $hostEntry -Name 'Artifacts'
        if ($null -eq $artifacts) {
            Add-Error -Errors $errors -Message "MissingRequiredField:$hostPrefix.Artifacts"
        } elseif (-not (Test-ValueType -Value $artifacts -ExpectedType 'array')) {
            if ($artifacts -is [pscustomobject]) {
                $artifacts = @($artifacts)
            } else {
                Add-Error -Errors $errors -Message "InvalidType:$hostPrefix.Artifacts expected=array actual=$($artifacts.GetType().Name)"
            }
        }

        $artifactIndex = 0
        $resolvedArtifacts = [System.Collections.Generic.List[pscustomobject]]::new()
        $hasShowIpRoute = $false
        if ($null -ne $artifacts) {
            foreach ($artifact in $artifacts) {
                $artifactPrefix = "$hostPrefix.Artifacts[$artifactIndex]"
                $name = Get-RequiredString -Value (Get-PropertyValue -Object $artifact -Name 'Name') -FieldName 'Name' -Errors $errors -Prefix $artifactPrefix
                $command = Get-RequiredString -Value (Get-PropertyValue -Object $artifact -Name 'Command') -FieldName 'Command' -Errors $errors -Prefix $artifactPrefix
                $transcriptPath = Get-RequiredString -Value (Get-PropertyValue -Object $artifact -Name 'TranscriptPath') -FieldName 'TranscriptPath' -Errors $errors -Prefix $artifactPrefix

                if ($name -eq 'show_ip_route') {
                    $hasShowIpRoute = $true
                }
                if (-not [string]::IsNullOrWhiteSpace($transcriptPath)) {
                    if ($onlineMode) {
                        $resolvedArtifacts.Add([pscustomobject]@{
                            Name             = $name
                            Command          = $command
                            TranscriptPath   = $transcriptPath
                            TranscriptOrigin = 'Online'
                        })
                    } else {
                        $resolvedPath = Resolve-TranscriptPath -SessionFilePath $SessionPath -RelativePath $transcriptPath
                        if (-not (Test-Path -LiteralPath $resolvedPath)) {
                            Add-Error -Errors $errors -Message "MissingTranscript:$resolvedPath"
                        } else {
                            $resolvedArtifacts.Add([pscustomobject]@{
                                Name             = $name
                                Command          = $command
                                SourcePath       = $resolvedPath
                                TranscriptPath   = $transcriptPath
                                TranscriptOrigin = 'Offline'
                            })
                        }
                    }
                }

                $artifactIndex += 1
            }
        }

        if (-not $hasShowIpRoute) {
            Add-Error -Errors $errors -Message "MissingArtifact:show_ip_route host=$hostname"
        }

        $preparedHosts.Add([pscustomobject]@{
            HostnameOriginal  = $hostname
            HostnameNormalized = if ($null -ne $hostname) { $hostname.ToUpperInvariant() } else { $hostname }
            Artifacts         = $resolvedArtifacts.ToArray()
        })
        $hostIndex += 1
    }
}

$summaryPath = Join-Path -Path $OutputRoot -ChildPath ("RoutingCliCaptureSessionSummary-{0}.json" -f $Timestamp)
$latestPath = Join-Path -Path $OutputRoot -ChildPath 'RoutingCliCaptureSessionSummary-latest.json'

$hostSummaries = [System.Collections.Generic.List[pscustomobject]]::new()
if ($errors.Count -eq 0) {
    $siteNormalized = $site.ToUpperInvariant()
    $vrfNormalized = if ([string]::IsNullOrWhiteSpace($vrf)) { 'default' } else { $vrf }

    foreach ($hostEntry in $preparedHosts) {
        $hostnameNormalized = $hostEntry.HostnameNormalized
        $hostnameOriginal = $hostEntry.HostnameOriginal
        $outputDir = Join-Path -Path $OutputRoot -ChildPath (Join-Path -Path $siteNormalized -ChildPath (Join-Path -Path $hostnameNormalized -ChildPath $Timestamp))
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null

        # LANDMARK: Routing CLI capture session output - emit per-host RoutingCliCapture bundles
        $artifactOutputs = [System.Collections.Generic.List[string]]::new()
        $captureArtifacts = [System.Collections.Generic.List[pscustomobject]]::new()
        $hostErrors = New-Object System.Collections.Generic.List[string]
        foreach ($artifact in $hostEntry.Artifacts) {
            if (-not $onlineMode) {
                $destinationPath = Join-Path -Path $outputDir -ChildPath (Split-Path -Leaf $artifact.SourcePath)
                Copy-Item -LiteralPath $artifact.SourcePath -Destination $destinationPath -Force
                $artifactOutputs.Add($destinationPath)
                $captureArtifacts.Add([pscustomobject]@{
                    Name    = $artifact.Name
                    Command = $artifact.Command
                    Path    = (Split-Path -Leaf $destinationPath)
                })
                continue
            }

            $destinationPath = $null
            try {
                # LANDMARK: Online transcript path safety - prevent output path traversal outside host output root
                $destinationPath = Resolve-OutputTranscriptPath -OutputDirectory $outputDir -RelativePath $artifact.TranscriptPath
                Ensure-Directory -Path $destinationPath
            } catch {
                $message = "TranscriptPathInvalid: $($artifact.TranscriptPath) host=$hostnameNormalized error=$($_.Exception.Message)"
                Add-Error -Errors $errors -Message $message
                $hostErrors.Add($message) | Out-Null
                continue
            }

            try {
                # LANDMARK: Online transcript capture - abstraction hook for tests and ssh transport for real use
                if ($null -ne $TranscriptCaptureScriptBlock) {
                    & $TranscriptCaptureScriptBlock -Hostname $hostnameOriginal -Vendor $vendor -Command $artifact.Command -OutputPath $destinationPath
                } else {
                    Invoke-RoutingCliSshTranscriptCapture -Hostname $hostnameOriginal -SshUser $SshUser -Command $artifact.Command -OutputPath $destinationPath `
                        -SshPort $SshPort -SshIdentityFile $SshIdentityFile -SshExePath $SshExePath -SshOptions $SshOptions `
                        -SshConnectTimeoutSeconds $SshConnectTimeoutSeconds -SshSessionTimeoutSeconds $SshSessionTimeoutSeconds
                }
            } catch {
                $message = "TranscriptCaptureFailed: host=$hostnameNormalized artifact=$($artifact.Name) error=$($_.Exception.Message)"
                Add-Error -Errors $errors -Message $message
                $hostErrors.Add($message) | Out-Null
                continue
            }

            if (-not (Test-Path -LiteralPath $destinationPath)) {
                $message = "TranscriptCaptureMissing: host=$hostnameNormalized output=$destinationPath"
                Add-Error -Errors $errors -Message $message
                $hostErrors.Add($message) | Out-Null
                continue
            }

            $artifactOutputs.Add($destinationPath)
            $captureArtifacts.Add([pscustomobject]@{
                Name    = $artifact.Name
                Command = $artifact.Command
                Path    = $artifact.TranscriptPath
            })
        }

        $capture = [pscustomobject]@{
            SchemaVersion = $captureSchema.SchemaVersion
            CapturedAt    = $capturedAt
            Site          = $siteNormalized
            Hostname      = $hostnameNormalized
            Vendor        = $vendor
            Vrf           = $vrfNormalized
            Artifacts     = $captureArtifacts.ToArray()
        }

        $capturePath = Join-Path -Path $outputDir -ChildPath 'Capture.json'
        $capture | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $capturePath -Encoding utf8

        $hostSummaries.Add([pscustomobject]@{
            Hostname        = $hostnameNormalized
            OutputDirectory = $outputDir
            CaptureJsonPath = $capturePath
            ArtifactPaths   = $artifactOutputs.ToArray()
            Status          = if ($hostErrors.Count -gt 0) { 'Fail' } else { 'Pass' }
            Errors          = $hostErrors.ToArray()
        })
    }
}

# LANDMARK: Routing CLI capture session latest pointer - deterministic surfacing summary
$summary = [pscustomobject]@{
    Timestamp           = (Get-Date -Format o)
    Status              = if ($errors.Count -eq 0) { 'Pass' } else { 'Fail' }
    SessionPath         = (Resolve-Path -LiteralPath $SessionPath).Path
    OutputRoot          = $OutputRoot
    Mode                = $Mode
    AllowNetworkCaptureSwitch    = $AllowNetworkCapture.IsPresent
    EnvironmentAllowNetworkCapture = $environmentAllowsNetwork
    NetworkCaptureAllowed        = ($onlineMode -and $AllowNetworkCapture.IsPresent -and $environmentAllowsNetwork)
    SshUserProvided     = -not [string]::IsNullOrWhiteSpace($SshUser)
    Site                = if ($null -ne $site) { $site.ToUpperInvariant() } else { $null }
    Vendor              = $vendor
    Vrf                 = if ([string]::IsNullOrWhiteSpace($vrf)) { 'default' } else { $vrf }
    HostsProcessedCount = $hostSummaries.Count
    HostSummaries       = $hostSummaries
    Errors              = $errors.ToArray()
    SchemaVersion       = $schema.SchemaVersion
    CaptureSchema       = $captureSchema.SchemaVersion
}

Ensure-Directory -Path $summaryPath
$summary | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $summaryPath -Encoding utf8

if ($UpdateLatest.IsPresent -and $errors.Count -eq 0) {
    Copy-Item -LiteralPath $summaryPath -Destination $latestPath -Force
}

if ($errors.Count -gt 0) {
    throw "Routing CLI capture session failed. See $summaryPath"
}

if ($PassThru.IsPresent) {
    return $summary
}
