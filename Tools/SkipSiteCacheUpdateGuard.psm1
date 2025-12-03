Set-StrictMode -Version Latest

function Disable-SkipSiteCacheUpdateSetting {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SettingsPath,
        [string]$Label
    )

    $result = [pscustomobject]@{
        SettingsPath = $SettingsPath
        OriginalText = $null
        Changed      = $false
        Label        = $Label
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
    if ($originalText -notmatch '"SkipSiteCacheUpdate"\s*:\s*true') {
        return $result
    }

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

    if (-not $changed) { return }
    if ([string]::IsNullOrWhiteSpace($settingsPath)) { return }
    if ($null -eq $originalText) { return }

    try {
        Set-Content -LiteralPath $settingsPath -Value $originalText -Encoding utf8
        $context = if (-not [string]::IsNullOrWhiteSpace($label)) { "[{0}]" -f $label } else { '[SkipSiteCache]' }
        Write-Host ("{0} Restored SkipSiteCacheUpdate setting." -f $context) -ForegroundColor Yellow
    } catch {
        $context = if (-not [string]::IsNullOrWhiteSpace($label)) { " for {0}" -f $label } else { '' }
        Write-Warning ("Failed to restore SkipSiteCacheUpdate setting{0}: {1}" -f $context, $_.Exception.Message)
    }
}

Export-ModuleMember -Function Disable-SkipSiteCacheUpdateSetting, Restore-SkipSiteCacheUpdateSetting
