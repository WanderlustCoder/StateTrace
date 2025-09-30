Set-StrictMode -Version Latest

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
    Add-Content -LiteralPath $path -Value $json
}

Export-ModuleMember -Function Get-TelemetryLogDirectory, Get-TelemetryLogPath, Write-StTelemetryEvent
