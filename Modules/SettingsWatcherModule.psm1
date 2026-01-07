# SettingsWatcherModule.psm1
# Provides hot-reload functionality for StateTrace settings using FileSystemWatcher.
# Changes to StateTraceSettings.json are detected and applied without restart.

Set-StrictMode -Version Latest

# Module state
if (-not (Get-Variable -Scope Script -Name SettingsWatcher -ErrorAction SilentlyContinue)) {
    $script:SettingsWatcher = $null
}

if (-not (Get-Variable -Scope Script -Name SettingsPath -ErrorAction SilentlyContinue)) {
    $script:SettingsPath = $null
}

if (-not (Get-Variable -Scope Script -Name LastSettingsHash -ErrorAction SilentlyContinue)) {
    $script:LastSettingsHash = $null
}

if (-not (Get-Variable -Scope Script -Name SettingsChangeCallbacks -ErrorAction SilentlyContinue)) {
    $script:SettingsChangeCallbacks = [System.Collections.Generic.List[scriptblock]]::new()
}

if (-not (Get-Variable -Scope Script -Name SettingsWatcherEnabled -ErrorAction SilentlyContinue)) {
    $script:SettingsWatcherEnabled = $false
}

if (-not (Get-Variable -Scope Script -Name DebounceTimer -ErrorAction SilentlyContinue)) {
    $script:DebounceTimer = $null
}

if (-not (Get-Variable -Scope Script -Name DebounceMs -ErrorAction SilentlyContinue)) {
    $script:DebounceMs = 500
}

function Get-SettingsFileHash {
    <#
    .SYNOPSIS
    Computes a hash of the settings file content.
    #>
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    try {
        $content = [System.IO.File]::ReadAllBytes($Path)
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $hashBytes = $sha.ComputeHash($content)
        $sha.Dispose()
        return [BitConverter]::ToString($hashBytes).Replace('-', '')
    } catch {
        return $null
    }
}

function Initialize-SettingsWatcher {
    <#
    .SYNOPSIS
    Initializes the settings file watcher for hot-reload functionality.
    .PARAMETER SettingsPath
    Path to the StateTraceSettings.json file.
    .PARAMETER DebounceMs
    Debounce interval in milliseconds to avoid rapid reloads. Default 500ms.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SettingsPath,
        [int]$DebounceMs = 500
    )

    # Stop existing watcher if any
    Stop-SettingsWatcher

    if (-not (Test-Path -LiteralPath $SettingsPath)) {
        Write-Warning "[SettingsWatcher] Settings file not found: $SettingsPath"
        return $false
    }

    $script:SettingsPath = $SettingsPath
    $script:DebounceMs = $DebounceMs
    $script:LastSettingsHash = Get-SettingsFileHash -Path $SettingsPath

    $directory = Split-Path -Parent $SettingsPath
    $fileName = Split-Path -Leaf $SettingsPath

    try {
        $script:SettingsWatcher = [System.IO.FileSystemWatcher]::new()
        $script:SettingsWatcher.Path = $directory
        $script:SettingsWatcher.Filter = $fileName
        $script:SettingsWatcher.NotifyFilter = [System.IO.NotifyFilters]::LastWrite -bor [System.IO.NotifyFilters]::Size
        $script:SettingsWatcher.EnableRaisingEvents = $false

        # Register event handler
        $action = {
            # Use synchronized hashtable to pass module state
            $state = $Event.MessageData
            if ($state -and $state.Module) {
                & $state.Module {
                    param($SettingsPath, $DebounceMs)
                    Invoke-SettingsChangeDebounced -SettingsPath $SettingsPath -DebounceMs $DebounceMs
                } $state.SettingsPath $state.DebounceMs
            }
        }

        $messageData = @{
            Module = $MyInvocation.MyCommand.Module
            SettingsPath = $script:SettingsPath
            DebounceMs = $script:DebounceMs
        }

        Register-ObjectEvent -InputObject $script:SettingsWatcher -EventName 'Changed' -Action $action -MessageData $messageData -SourceIdentifier 'StateTraceSettingsChanged' | Out-Null

        $script:SettingsWatcher.EnableRaisingEvents = $true
        $script:SettingsWatcherEnabled = $true

        Write-Verbose "[SettingsWatcher] Initialized watching: $SettingsPath"
        return $true

    } catch {
        Write-Warning "[SettingsWatcher] Failed to initialize: $($_.Exception.Message)"
        Stop-SettingsWatcher
        return $false
    }
}

function Invoke-SettingsChangeDebounced {
    <#
    .SYNOPSIS
    Handles settings file change with debouncing.
    #>
    param(
        [string]$SettingsPath,
        [int]$DebounceMs
    )

    # Simple debounce using a timestamp check
    $now = [datetime]::UtcNow

    if ($script:DebounceTimer -and ($now - $script:DebounceTimer).TotalMilliseconds -lt $DebounceMs) {
        return
    }

    $script:DebounceTimer = $now

    # Schedule the actual reload after debounce period
    $null = [System.Threading.Tasks.Task]::Run({
        Start-Sleep -Milliseconds $using:DebounceMs
        Invoke-SettingsReload -SettingsPath $using:SettingsPath
    })
}

function Invoke-SettingsReload {
    <#
    .SYNOPSIS
    Reloads settings and invokes registered callbacks.
    #>
    param([string]$SettingsPath)

    if (-not (Test-Path -LiteralPath $SettingsPath)) {
        return
    }

    # Check if file actually changed
    $newHash = Get-SettingsFileHash -Path $SettingsPath
    if ($newHash -eq $script:LastSettingsHash) {
        return
    }

    $script:LastSettingsHash = $newHash

    Write-Verbose "[SettingsWatcher] Settings file changed, reloading..."

    # Load new settings
    $newSettings = $null
    try {
        $content = [System.IO.File]::ReadAllText($SettingsPath, [System.Text.Encoding]::UTF8)
        $newSettings = $content | ConvertFrom-Json
    } catch {
        Write-Warning "[SettingsWatcher] Failed to parse settings: $($_.Exception.Message)"
        return
    }

    # Invoke callbacks
    foreach ($callback in $script:SettingsChangeCallbacks) {
        try {
            & $callback $newSettings
        } catch {
            Write-Warning "[SettingsWatcher] Callback failed: $($_.Exception.Message)"
        }
    }

    # Publish event for any listeners
    Publish-SettingsChangedEvent -Settings $newSettings
}

function Register-SettingsChangeCallback {
    <#
    .SYNOPSIS
    Registers a callback to be invoked when settings change.
    .PARAMETER Callback
    A scriptblock that receives the new settings object as parameter.
    .EXAMPLE
    Register-SettingsChangeCallback -Callback { param($settings) Write-Host "Theme changed to: $($settings.Theme)" }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][scriptblock]$Callback
    )

    $script:SettingsChangeCallbacks.Add($Callback)
    Write-Verbose "[SettingsWatcher] Registered settings change callback"
}

function Unregister-SettingsChangeCallback {
    <#
    .SYNOPSIS
    Removes a previously registered callback.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][scriptblock]$Callback
    )

    $script:SettingsChangeCallbacks.Remove($Callback) | Out-Null
}

function Clear-SettingsChangeCallbacks {
    <#
    .SYNOPSIS
    Removes all registered callbacks.
    #>
    [CmdletBinding()]
    param()

    $script:SettingsChangeCallbacks.Clear()
}

function Publish-SettingsChangedEvent {
    <#
    .SYNOPSIS
    Publishes a settings changed event for global listeners.
    #>
    param([object]$Settings)

    try {
        $eventArgs = [PSCustomObject]@{
            Settings = $Settings
            Timestamp = [datetime]::UtcNow
            SettingsPath = $script:SettingsPath
        }

        # Use a global variable for cross-module communication
        $global:StateTraceLastSettingsChange = $eventArgs

        # Try to invoke telemetry if available
        try {
            if (Get-Command -Name 'TelemetryModule\Publish-TelemetryEvent' -ErrorAction SilentlyContinue) {
                TelemetryModule\Publish-TelemetryEvent -EventType 'SettingsReloaded' -Data @{
                    Timestamp = $eventArgs.Timestamp.ToString('o')
                }
            }
        } catch { }

    } catch {
        Write-Verbose "[SettingsWatcher] Failed to publish event: $($_.Exception.Message)"
    }
}

function Stop-SettingsWatcher {
    <#
    .SYNOPSIS
    Stops the settings file watcher and cleans up resources.
    #>
    [CmdletBinding()]
    param()

    try {
        # Unregister event
        Get-EventSubscriber -SourceIdentifier 'StateTraceSettingsChanged' -ErrorAction SilentlyContinue |
            Unregister-Event -ErrorAction SilentlyContinue
    } catch { }

    if ($script:SettingsWatcher) {
        try {
            $script:SettingsWatcher.EnableRaisingEvents = $false
            $script:SettingsWatcher.Dispose()
        } catch { }
        $script:SettingsWatcher = $null
    }

    $script:SettingsWatcherEnabled = $false
    Write-Verbose "[SettingsWatcher] Stopped"
}

function Get-SettingsWatcherStatus {
    <#
    .SYNOPSIS
    Returns the current status of the settings watcher.
    #>
    [CmdletBinding()]
    param()

    return [PSCustomObject]@{
        Enabled = $script:SettingsWatcherEnabled
        SettingsPath = $script:SettingsPath
        LastHash = $script:LastSettingsHash
        CallbackCount = $script:SettingsChangeCallbacks.Count
        DebounceMs = $script:DebounceMs
    }
}

function Test-SettingsWatcher {
    <#
    .SYNOPSIS
    Tests the settings watcher by simulating a file change.
    #>
    [CmdletBinding()]
    param()

    if (-not $script:SettingsWatcherEnabled) {
        Write-Warning "[SettingsWatcher] Watcher is not enabled"
        return $false
    }

    Write-Verbose "[SettingsWatcher] Triggering test reload..."
    $script:LastSettingsHash = $null  # Force reload
    Invoke-SettingsReload -SettingsPath $script:SettingsPath
    return $true
}

Export-ModuleMember -Function @(
    'Initialize-SettingsWatcher',
    'Stop-SettingsWatcher',
    'Register-SettingsChangeCallback',
    'Unregister-SettingsChangeCallback',
    'Clear-SettingsChangeCallbacks',
    'Get-SettingsWatcherStatus',
    'Test-SettingsWatcher'
)
