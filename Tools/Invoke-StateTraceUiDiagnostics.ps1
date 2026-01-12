[CmdletBinding()]
param(
    [switch]$EnableDebug,
    [switch]$LeaveDebugEnabled,
    [switch]$NoTranscript,
    [string]$LogDirectory
)

Set-StrictMode -Version Latest

$projectRoot = $null
try { $projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')) } catch { $projectRoot = (Join-Path $PSScriptRoot '..') }

$mainScriptPath = Join-Path $projectRoot 'Main\MainWindow.ps1'
if (-not (Test-Path -LiteralPath $mainScriptPath)) {
    throw "Main window script not found at '$mainScriptPath'."
}

$settingsPath = Join-Path $projectRoot 'Data\StateTraceSettings.json'

$resolvedLogDir = $LogDirectory
if ([string]::IsNullOrWhiteSpace($resolvedLogDir)) {
    $resolvedLogDir = Join-Path $projectRoot 'Logs\Diagnostics'
}
try { $resolvedLogDir = [System.IO.Path]::GetFullPath($resolvedLogDir) } catch {
    Write-Warning ("Failed to normalize diagnostics log directory '{0}': {1}" -f $resolvedLogDir, $_.Exception.Message)
}
try { [System.IO.Directory]::CreateDirectory($resolvedLogDir) | Out-Null } catch {
    Write-Warning ("Failed to create diagnostics log directory '{0}': {1}" -f $resolvedLogDir, $_.Exception.Message)
}

$timestamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
$transcriptPath = Join-Path $resolvedLogDir ("UiSession-{0}.log" -f $timestamp)

$previousDebug = $null
$settings = $null
if ($EnableDebug) {
    $settings = @{}
    if (Test-Path -LiteralPath $settingsPath) {
        try {
            $json = Get-Content -LiteralPath $settingsPath -Raw
            if (-not [string]::IsNullOrWhiteSpace($json)) {
                $parsed = $json | ConvertFrom-Json
                if ($parsed) {
                    foreach ($prop in $parsed.PSObject.Properties) {
                        $settings[$prop.Name] = $prop.Value
                    }
                }
            }
        } catch {
            $settings = @{}
        }
    }

    if ($settings.ContainsKey('DebugOnNextLaunch')) {
        $previousDebug = [bool]$settings['DebugOnNextLaunch']
    }

    $settings['DebugOnNextLaunch'] = $true
    try {
        $settingsJson = $settings | ConvertTo-Json -Depth 5
        $settingsDir = Split-Path -Parent $settingsPath
        if ($settingsDir) { [System.IO.Directory]::CreateDirectory($settingsDir) | Out-Null }
        $settingsJson | Out-File -LiteralPath $settingsPath -Encoding utf8
    } catch { Write-Verbose "Caught exception in Invoke-StateTraceUiDiagnostics.ps1: $($_.Exception.Message)" }
}

$transcriptStarted = $false
if (-not $NoTranscript) {
    try {
        Start-Transcript -Path $transcriptPath -Force | Out-Null
        $transcriptStarted = $true
    } catch {
        $transcriptStarted = $false
    }
}

try {
    & $mainScriptPath
} finally {
    if ($transcriptStarted) {
        try { Stop-Transcript | Out-Null } catch { Write-Verbose "Caught exception in Invoke-StateTraceUiDiagnostics.ps1: $($_.Exception.Message)" }
    }

    if ($EnableDebug -and -not $LeaveDebugEnabled) {
        try {
            if (-not $settings) { $settings = @{} }
            if ($null -eq $previousDebug) {
                $settings.Remove('DebugOnNextLaunch') | Out-Null
            } else {
                $settings['DebugOnNextLaunch'] = [bool]$previousDebug
            }

            $settingsJson = $settings | ConvertTo-Json -Depth 5
            $settingsJson | Out-File -LiteralPath $settingsPath -Encoding utf8
        } catch { Write-Verbose "Caught exception in Invoke-StateTraceUiDiagnostics.ps1: $($_.Exception.Message)" }
    }
}

if ($transcriptStarted) {
    Write-Output $transcriptPath
}
