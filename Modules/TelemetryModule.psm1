Set-StrictMode -Version Latest

function Initialize-StateTraceDebug {
    [CmdletBinding()]
    param(
        [switch]$EnableVerbosePreference
    )

    $current = $false
    try {
        if (Get-Variable -Name StateTraceDebug -Scope Global -ErrorAction SilentlyContinue) {
            $current = [bool]$Global:StateTraceDebug
            Set-Variable -Scope Global -Name StateTraceDebug -Value $current -Option None
        } else {
            Set-Variable -Scope Global -Name StateTraceDebug -Value $false -Option None
            $current = $false
        }
    } catch {
        try { Set-Variable -Scope Global -Name StateTraceDebug -Value $false -Option None } catch { }
        $current = $false
    }

    if ($EnableVerbosePreference -and $current) {
        Set-Variable -Name VerbosePreference -Scope 1 -Value 'Continue' -ErrorAction SilentlyContinue
        Set-Variable -Name VerbosePreference -Scope Global -Value 'Continue' -ErrorAction SilentlyContinue
    }
}

function Import-InterfaceCommon {
    [CmdletBinding()]
    param(
        [string]$ModulesRoot
    )

    if (Get-Module -Name 'InterfaceCommon' -ErrorAction SilentlyContinue) { return $true }

    $rootPath = $ModulesRoot
    if ([string]::IsNullOrWhiteSpace($rootPath)) { $rootPath = $PSScriptRoot }
    try { $rootPath = [System.IO.Path]::GetFullPath($rootPath) } catch { }

    $modulePath = Join-Path $rootPath 'InterfaceCommon.psm1'
    if (-not (Test-Path -LiteralPath $modulePath)) { return $false }

    try {
        Import-Module -Name $modulePath -Force -Global -ErrorAction Stop | Out-Null
        return $true
    } catch {
        Write-Verbose ("[Telemetry] Failed to load InterfaceCommon from '{0}': {1}" -f $modulePath, $_.Exception.Message)
        return $false
    }
}

function Get-SpanDebugLogPath {
    [CmdletBinding()]
    param(
        [string]$Path,
        [switch]$UseTemp
    )

    if (-not [string]::IsNullOrWhiteSpace($Path)) { return $Path }

    if ($UseTemp) {
        try { return Join-Path ([System.IO.Path]::GetTempPath()) 'StateTrace_SpanDebug.log' } catch { return $null }
    }

    try {
        $projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    } catch {
        $projectRoot = (Split-Path -Parent $PSScriptRoot)
    }

    $debugDir = Join-Path $projectRoot 'Logs\Debug'
    try {
        if (-not (Test-Path -LiteralPath $debugDir)) {
            New-Item -ItemType Directory -Path $debugDir -Force | Out-Null
        }
    } catch { }

    return (Join-Path $debugDir 'SpanDebug.log')
}

function Write-SpanDebugLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$Path,
        [switch]$UseTemp,
        [string]$Prefix
    )

    $targetPath = Get-SpanDebugLogPath -Path $Path -UseTemp:$UseTemp
    if (-not $targetPath) { return }

    $linePrefix = ''
    if (-not [string]::IsNullOrWhiteSpace($Prefix)) {
        $linePrefix = ($Prefix.Trim() + ' ')
    }

    $line = ('{0} {1}{2}' -f (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss'), $linePrefix, $Message)

    try {
        $parent = Split-Path -Parent $targetPath
        if ($parent -and -not (Test-Path -LiteralPath $parent) -and -not $UseTemp) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        Add-Content -LiteralPath $targetPath -Value $line -Encoding UTF8
    } catch { }
}

function Get-TelemetryLogDirectory {
    # Allow tests to override output directory via env var
    $override = $env:STATETRACE_TELEMETRY_DIR
    if ($override -and (Test-Path -LiteralPath $override)) {
        return (Resolve-Path $override).ProviderPath
    }
    try {
        $projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    } catch {
        $projectRoot = (Split-Path -Parent $PSScriptRoot)
    }
    $dir = Join-Path $projectRoot 'Logs/IngestionMetrics'
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    return $dir
}

function Get-TelemetryLogPath {
    $dir = Get-TelemetryLogDirectory
    $name = (Get-Date).ToString('yyyy-MM-dd') + '.json'
    return (Join-Path $dir $name)
}

function Get-TelemetryWriteMutexName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    $normalized = $Path
    try { $normalized = [System.IO.Path]::GetFullPath($Path) } catch { }

    $bytes = $null
    try { $bytes = [System.Text.Encoding]::UTF8.GetBytes($normalized.ToLowerInvariant()) } catch { $bytes = [byte[]]@() }

    $sha = $null
    try {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $hash = $sha.ComputeHash($bytes)
        $hex = ($hash | ForEach-Object { $_.ToString('x2') }) -join ''
        if ([string]::IsNullOrWhiteSpace($hex)) {
            return 'StateTrace.Telemetry.Write'
        }
        return ('StateTrace.Telemetry.Write.{0}' -f $hex.Substring(0, 24))
    } catch {
        return 'StateTrace.Telemetry.Write'
    } finally {
        if ($sha) { $sha.Dispose() }
    }
}

if (-not (Get-Variable -Scope Script -Name TelemetryBuffer -ErrorAction SilentlyContinue)) {
    $script:TelemetryBuffer = [System.Collections.Generic.List[string]]::new()
}
if (-not (Get-Variable -Scope Script -Name TelemetryBufferFlushThreshold -ErrorAction SilentlyContinue)) {
    $script:TelemetryBufferFlushThreshold = 50
}
if (-not (Get-Variable -Scope Script -Name TelemetryBufferLastFlushUtc -ErrorAction SilentlyContinue)) {
    $script:TelemetryBufferLastFlushUtc = [DateTime]::UtcNow
}
if (-not (Get-Variable -Scope Script -Name TelemetryWriteMutex -ErrorAction SilentlyContinue)) {
    $script:TelemetryWriteMutex = $null
}
if (-not (Get-Variable -Scope Script -Name TelemetryWriteMutexPath -ErrorAction SilentlyContinue)) {
    $script:TelemetryWriteMutexPath = $null
}

function Flush-TelemetryBuffer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if (-not $script:TelemetryBuffer -or $script:TelemetryBuffer.Count -le 0) { return }

    $lines = $script:TelemetryBuffer.ToArray()
    if (-not $lines -or $lines.Count -le 0) { return }

    $mutex = $null
    $lockAcquired = $false
    try {
        if (-not $script:TelemetryWriteMutex -or -not $script:TelemetryWriteMutexPath -or -not [string]::Equals($script:TelemetryWriteMutexPath, $Path, [System.StringComparison]::OrdinalIgnoreCase)) {
            if ($script:TelemetryWriteMutex) {
                try { $script:TelemetryWriteMutex.Dispose() } catch { }
                $script:TelemetryWriteMutex = $null
            }
            $script:TelemetryWriteMutexPath = $Path
            $mutexName = Get-TelemetryWriteMutexName -Path $Path
            $script:TelemetryWriteMutex = New-Object 'System.Threading.Mutex' $false, $mutexName
        }

        $mutex = $script:TelemetryWriteMutex
        try {
            $lockAcquired = $mutex.WaitOne()
        } catch [System.Threading.AbandonedMutexException] {
            $lockAcquired = $true
        }

        Add-Content -LiteralPath $Path -Value $lines
        $script:TelemetryBuffer.Clear()
        $script:TelemetryBufferLastFlushUtc = [DateTime]::UtcNow
    } finally {
        if ($mutex) {
            if ($lockAcquired) {
                try { $mutex.ReleaseMutex() } catch { }
            }
        }
    }
}

function Write-StTelemetryEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][hashtable]$Payload
    )
    $evt = [ordered]@{
        EventName = $Name
        Timestamp = (Get-Date).ToString('o')
    }
    foreach ($k in $Payload.Keys) {
        $evt[$k] = $Payload[$k]
    }
    $json = ($evt | ConvertTo-Json -Depth 6 -Compress)
    $path = Get-TelemetryLogPath

    if (-not $script:TelemetryBuffer) {
        $script:TelemetryBuffer = [System.Collections.Generic.List[string]]::new()
    }
    $script:TelemetryBuffer.Add($json) | Out-Null

    $flushNow = $false
    $pesterLoaded = $false
    try { $pesterLoaded = ($null -ne (Get-Module -Name 'Pester' -ErrorAction SilentlyContinue)) } catch { $pesterLoaded = $false }

    if ($pesterLoaded) {
        $flushNow = $true
    } elseif ($script:TelemetryBuffer.Count -ge $script:TelemetryBufferFlushThreshold) {
        $flushNow = $true
    } elseif ($Name -eq 'ParseDuration' -or $Name -eq 'SkippedDuplicate') {
        $flushNow = $true
    } else {
        try {
            $elapsedSeconds = ([DateTime]::UtcNow - $script:TelemetryBufferLastFlushUtc).TotalSeconds
            if ($elapsedSeconds -ge 5) {
                $flushNow = $true
            }
        } catch { }
    }

    if ($flushNow) {
        Flush-TelemetryBuffer -Path $path
    }
}

function Remove-ComObjectSafe {
    [CmdletBinding()]
    param(
        [Parameter()][object]$ComObject
    )

    if ($null -eq $ComObject) { return }
    if ($ComObject -is [System.__ComObject]) {
        try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($ComObject) } catch { }
    }
}

Export-ModuleMember -Function Initialize-StateTraceDebug, Import-InterfaceCommon, Get-SpanDebugLogPath, Write-SpanDebugLog, Get-TelemetryLogDirectory, Get-TelemetryLogPath, Write-StTelemetryEvent, Remove-ComObjectSafe
