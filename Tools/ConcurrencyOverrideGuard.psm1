Set-StrictMode -Version Latest

function Reset-ConcurrencyOverrideSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SettingsPath,
        [string]$Label
    )

    $result = [pscustomobject]@{
        SettingsPath = $SettingsPath
        Changed      = $false
        Overrides    = @{}
        Baselines    = @{}
        Label        = $Label
    }

    if (-not (Test-Path -LiteralPath $SettingsPath)) {
        Write-Warning ("Unable to locate StateTraceSettings.json at '{0}'." -f $SettingsPath)
        return $result
    }

    $originalText = Get-Content -LiteralPath $SettingsPath -Raw
    if ([string]::IsNullOrWhiteSpace($originalText)) {
        return $result
    }

    $baselineValues = [ordered]@{
        MaxRunspaceCeiling = 0
        MaxWorkersPerSite  = 0
        MaxActiveSites     = 0
        JobsPerThread      = 0
        MinRunspaceCount   = 1
    }

    $updatedText = $originalText
    $overrides = [ordered]@{}

    foreach ($entry in $baselineValues.GetEnumerator()) {
        $name = $entry.Key
        $baseline = $entry.Value
        $pattern = '"{0}"\s*:\s*(-?\d+)' -f [System.Text.RegularExpressions.Regex]::Escape($name)
        $match = [System.Text.RegularExpressions.Regex]::Match($updatedText, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if (-not $match.Success) {
            continue
        }

        $currentValue = $baseline
        try { $currentValue = [int]$match.Groups[1].Value } catch { $currentValue = $baseline }
        if ($currentValue -ne $baseline) {
            $overrides[$name] = $currentValue
            $updatedText = [System.Text.RegularExpressions.Regex]::Replace(
                $updatedText,
                $pattern,
                ('"{0}": {1}' -f $name, $baseline),
                [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
            )
        }
    }

    $result.Overrides = $overrides
    $result.Baselines = $baselineValues

    if ($overrides.Count -eq 0 -or $updatedText -eq $originalText) {
        return $result
    }

    try {
        Set-Content -LiteralPath $SettingsPath -Value $updatedText -Encoding utf8
        $result.Changed = $true
        $context = if (-not [string]::IsNullOrWhiteSpace($Label)) { "[{0}]" -f $Label } else { '[ConcurrencyOverride]' }
        $overrideSummary = ($overrides.GetEnumerator() | Sort-Object Name | ForEach-Object {
                '{0}={1}' -f $_.Key, $_.Value
            }) -join ', '
        Write-Host ("{0} Reset concurrency overrides to baseline ({1})." -f $context, $overrideSummary) -ForegroundColor Yellow
    } catch {
        $context = if (-not [string]::IsNullOrWhiteSpace($Label)) { " for {0}" -f $Label } else { '' }
        Write-Warning ("Failed to reset concurrency overrides{0}: {1}" -f $context, $_.Exception.Message)
    }

    return $result
}

Export-ModuleMember -Function Reset-ConcurrencyOverrideSettings
