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
    $mutex = $null
    $lockAcquired = $false
    try {
        $mutexName = Get-TelemetryWriteMutexName -Path $path
        $mutex = New-Object 'System.Threading.Mutex' $false, $mutexName
        try {
            $lockAcquired = $mutex.WaitOne()
        } catch [System.Threading.AbandonedMutexException] {
            $lockAcquired = $true
        }
        Add-Content -LiteralPath $path -Value $json
    } finally {
        if ($mutex) {
            if ($lockAcquired) {
                try { $mutex.ReleaseMutex() } catch { }
            }
            $mutex.Dispose()
        }
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
