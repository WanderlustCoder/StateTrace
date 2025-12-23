Set-StrictMode -Version Latest

function Disable-SkipSiteCacheUpdateSetting {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SettingsPath,
        [string]$Label
    )

    $envVarName = 'STATETRACE_SKIP_SITECACHE_UPDATE'
    $envPath = "Env:{0}" -f $envVarName
    $envOriginalValue = $null
    $envWasSet = $false
    try {
        if (Test-Path -LiteralPath $envPath) {
            $envOriginalValue = (Get-Item -LiteralPath $envPath).Value
            $envWasSet = $true
        }
    } catch {
        $envOriginalValue = $null
        $envWasSet = $false
    }

    $result = [pscustomobject]@{
        SettingsPath         = $SettingsPath
        OriginalText         = $null
        Changed              = $false
        Label                = $Label
        EnvVarName           = $envVarName
        EnvVarOriginalValue  = $envOriginalValue
        EnvVarWasSet         = $envWasSet
        EnvVarChanged        = $false
    }

    if (-not (Test-Path -LiteralPath $SettingsPath)) {
        Write-Warning ("Unable to locate StateTraceSettings.json at '{0}'." -f $SettingsPath)
        return $result
    }

    $originalText = Get-Content -LiteralPath $SettingsPath -Raw
    $result.OriginalText = $originalText
    if ([string]::IsNullOrWhiteSpace($originalText)) {
        return $result
    }
    $shouldDisableSetting = ($originalText -match '"SkipSiteCacheUpdate"\s*:\s*true')
    $shouldUpdateEnv = $false
    if ($envWasSet) {
        $envValue = if ($null -ne $envOriginalValue) { ('' + $envOriginalValue).Trim() } else { '' }
        if (-not [string]::Equals($envValue, '0', [System.StringComparison]::OrdinalIgnoreCase) -and
            -not [string]::Equals($envValue, 'false', [System.StringComparison]::OrdinalIgnoreCase)) {
            $shouldUpdateEnv = $true
        }
    } elseif ($shouldDisableSetting) {
        $shouldUpdateEnv = $true
    }
    if (-not $shouldDisableSetting -and -not $shouldUpdateEnv) {
        return $result
    }

    if ($shouldDisableSetting) {
        $updatedText = [System.Text.RegularExpressions.Regex]::Replace(
            $originalText,
            '"SkipSiteCacheUpdate"\s*:\s*true',
            '"SkipSiteCacheUpdate": false',
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        )
        if ([string]::IsNullOrWhiteSpace($updatedText)) {
            return $result
        }

        try {
            Set-Content -LiteralPath $SettingsPath -Value $updatedText -Encoding utf8
            $result.Changed = $true
            $context = if (-not [string]::IsNullOrWhiteSpace($Label)) { "[{0}]" -f $Label } else { '[SkipSiteCache]' }
            Write-Host ("{0} Temporarily disabled SkipSiteCacheUpdate." -f $context) -ForegroundColor Yellow
        } catch {
            $context = if (-not [string]::IsNullOrWhiteSpace($Label)) { " for {0}" -f $Label } else { '' }
            Write-Warning ("Failed to disable SkipSiteCacheUpdate{0}: {1}" -f $context, $_.Exception.Message)
        }
    }

    if ($shouldUpdateEnv) {
        try {
            Set-Item -LiteralPath $envPath -Value '0'
            $result.EnvVarChanged = $true
        } catch {
            Write-Warning ("Failed to update {0}: {1}" -f $envVarName, $_.Exception.Message)
        }
    }

    return $result
}

function Restore-SkipSiteCacheUpdateSetting {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Guard
    )

    if (-not $Guard) { return }

    $settingsPath = $null
    $originalText = $null
    $label = $null
    $changed = $false
    $envVarName = 'STATETRACE_SKIP_SITECACHE_UPDATE'
    $envVarChanged = $false
    $envVarWasSet = $false
    $envVarOriginalValue = $null

    if ($Guard.PSObject.Properties.Name -contains 'SettingsPath') {
        $settingsPath = $Guard.SettingsPath
    }
    if ($Guard.PSObject.Properties.Name -contains 'OriginalText') {
        $originalText = $Guard.OriginalText
    }
    if ($Guard.PSObject.Properties.Name -contains 'Label') {
        $label = $Guard.Label
    }
    if ($Guard.PSObject.Properties.Name -contains 'Changed') {
        try { $changed = [bool]$Guard.Changed } catch { $changed = $false }
    }
    if ($Guard.PSObject.Properties.Name -contains 'EnvVarName') {
        $envVarName = $Guard.EnvVarName
    }
    if ($Guard.PSObject.Properties.Name -contains 'EnvVarChanged') {
        try { $envVarChanged = [bool]$Guard.EnvVarChanged } catch { $envVarChanged = $false }
    }
    if ($Guard.PSObject.Properties.Name -contains 'EnvVarWasSet') {
        try { $envVarWasSet = [bool]$Guard.EnvVarWasSet } catch { $envVarWasSet = $false }
    }
    if ($Guard.PSObject.Properties.Name -contains 'EnvVarOriginalValue') {
        $envVarOriginalValue = $Guard.EnvVarOriginalValue
    }

    if (-not $changed -and -not $envVarChanged) { return }

    try {
        if ($changed) {
            if (-not [string]::IsNullOrWhiteSpace($settingsPath) -and $null -ne $originalText) {
                Set-Content -LiteralPath $settingsPath -Value $originalText -Encoding utf8
                $context = if (-not [string]::IsNullOrWhiteSpace($label)) { "[{0}]" -f $label } else { '[SkipSiteCache]' }
                Write-Host ("{0} Restored SkipSiteCacheUpdate setting." -f $context) -ForegroundColor Yellow
            } else {
                Write-Warning 'SkipSiteCacheUpdate guard missing settings metadata; settings file was not restored.'
            }
        }
    } catch {
        $context = if (-not [string]::IsNullOrWhiteSpace($label)) { " for {0}" -f $label } else { '' }
        Write-Warning ("Failed to restore SkipSiteCacheUpdate setting{0}: {1}" -f $context, $_.Exception.Message)
    }

    if ($envVarChanged) {
        $envPath = "Env:{0}" -f $envVarName
        try {
            if ($envVarWasSet) {
                Set-Item -LiteralPath $envPath -Value $envVarOriginalValue
            } else {
                Remove-Item -LiteralPath $envPath -ErrorAction SilentlyContinue
            }
        } catch {
            Write-Warning ("Failed to restore {0}: {1}" -f $envVarName, $_.Exception.Message)
        }
    }
}

Export-ModuleMember -Function Disable-SkipSiteCacheUpdateSetting, Restore-SkipSiteCacheUpdateSetting
