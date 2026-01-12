Set-StrictMode -Version Latest

function ConvertFrom-HexColor {
    param(
        [Parameter(Mandatory=$true)][string]$Value
    )

    $trimmed = $Value.Trim()
    if ($trimmed.StartsWith('#')) {
        $trimmed = $trimmed.Substring(1)
    }

    if ($trimmed.Length -ne 6 -or ($trimmed -notmatch '^[0-9a-fA-F]{6}$')) {
        throw "Unsupported color value '$Value' (expected #RRGGBB)."
    }

    return [pscustomobject]@{
        R = [Convert]::ToInt32($trimmed.Substring(0, 2), 16)
        G = [Convert]::ToInt32($trimmed.Substring(2, 2), 16)
        B = [Convert]::ToInt32($trimmed.Substring(4, 2), 16)
    }
}

function ConvertTo-LinearChannel {
    param(
        [Parameter(Mandatory=$true)][double]$Channel
    )

    if ($Channel -le 0.03928) {
        return $Channel / 12.92
    }

    return [Math]::Pow((($Channel + 0.055) / 1.055), 2.4)
}

function Get-RelativeLuminance {
    param(
        [Parameter(Mandatory=$true)][string]$Color
    )

    $rgb = ConvertFrom-HexColor -Value $Color
    $r = ConvertTo-LinearChannel -Channel ($rgb.R / 255.0)
    $g = ConvertTo-LinearChannel -Channel ($rgb.G / 255.0)
    $b = ConvertTo-LinearChannel -Channel ($rgb.B / 255.0)
    return (0.2126 * $r) + (0.7152 * $g) + (0.0722 * $b)
}

function Get-ContrastRatio {
    param(
        [Parameter(Mandatory=$true)][string]$Foreground,
        [Parameter(Mandatory=$true)][string]$Background
    )

    $lum1 = Get-RelativeLuminance -Color $Foreground
    $lum2 = Get-RelativeLuminance -Color $Background
    $lighter = [Math]::Max($lum1, $lum2)
    $darker = [Math]::Min($lum1, $lum2)
    return ($lighter + 0.05) / ($darker + 0.05)
}

Describe 'Theme contrast compliance' {
    BeforeAll {
        $modulePath = Join-Path (Split-Path $PSCommandPath) '..\ThemeModule.psm1'
        Import-Module (Resolve-Path $modulePath) -Force
    }

    AfterAll {
        Remove-Module ThemeModule -Force -ErrorAction SilentlyContinue
    }

    It 'meets minimum contrast for core UI pairs' {
        $themes = ThemeModule\Get-AvailableStateTraceThemes
        $checks = @(
            [pscustomobject]@{ Name = 'Text.Inverse on Surface.Primary'; ForegroundKey = 'Theme.Text.Inverse'; BackgroundKey = 'Theme.Surface.Primary'; Minimum = 4.5 },
            [pscustomobject]@{ Name = 'Input.Text on Input.Background'; ForegroundKey = 'Theme.Input.Text'; BackgroundKey = 'Theme.Input.Background'; Minimum = 4.5 },
            [pscustomobject]@{ Name = 'Toolbar.Text on Toolbar.Background'; ForegroundKey = 'Theme.Toolbar.Text'; BackgroundKey = 'Theme.Toolbar.Background'; Minimum = 4.5 },
            [pscustomobject]@{ Name = 'Primary button text'; ForegroundKey = 'Theme.Button.Primary.Text'; BackgroundKey = 'Theme.Button.Primary.Background'; Minimum = 4.5 },
            [pscustomobject]@{ Name = 'Secondary button text'; ForegroundKey = 'Theme.Button.Secondary.Text'; BackgroundKey = 'Theme.Button.Secondary.Background'; Minimum = 4.5 },
            [pscustomobject]@{ Name = 'DataGrid header text'; ForegroundKey = 'Theme.DataGrid.HeaderText'; BackgroundKey = 'Theme.DataGrid.HeaderBackground'; Minimum = 4.5 },
            [pscustomobject]@{ Name = 'DataGrid selection text'; ForegroundKey = 'Theme.DataGrid.SelectionText'; BackgroundKey = 'Theme.DataGrid.SelectionBackground'; Minimum = 4.5 },
            [pscustomobject]@{ Name = 'DataGrid foreground'; ForegroundKey = 'Theme.Text.Primary'; BackgroundKey = 'Theme.DataGrid.Background'; Minimum = 4.5 }
        )

        $failures = [System.Collections.Generic.List[string]]::new()

        foreach ($theme in $themes) {
            ThemeModule\Set-StateTraceTheme -Name $theme.Name -Silent | Out-Null

            foreach ($check in $checks) {
                $foreground = ThemeModule\Get-ThemeToken -Key $check.ForegroundKey
                $background = ThemeModule\Get-ThemeToken -Key $check.BackgroundKey

                if ([string]::IsNullOrWhiteSpace($foreground) -or [string]::IsNullOrWhiteSpace($background)) {
                    $failures.Add(("Theme '{0}' missing token(s) for {1}: {2}='{3}' {4}='{5}'" -f $theme.Name, $check.Name, $check.ForegroundKey, $foreground, $check.BackgroundKey, $background)) | Out-Null
                    continue
                }

                try {
                    $ratio = Get-ContrastRatio -Foreground $foreground -Background $background
                    if ($ratio -lt $check.Minimum) {
                        $failures.Add(("Theme '{0}' {1} contrast {2} < {3} ({4} on {5})" -f $theme.Name, $check.Name, ([Math]::Round($ratio, 2)), $check.Minimum, $foreground, $background)) | Out-Null
                    }
                } catch {
                    $failures.Add(("Theme '{0}' {1} failed contrast calc ({2} on {3}): {4}" -f $theme.Name, $check.Name, $foreground, $background, $_.Exception.Message)) | Out-Null
                }
            }
        }

        if ($failures.Count -gt 0) {
            throw ($failures -join [Environment]::NewLine)
        }
    }

    It 'meets declared contrastTargets for each theme' {
        $themes = ThemeModule\Get-AvailableStateTraceThemes
        $failures = [System.Collections.Generic.List[string]]::new()

        foreach ($theme in $themes) {
            if (-not $theme.ContrastTargets) { continue }

            ThemeModule\Set-StateTraceTheme -Name $theme.Name -Silent | Out-Null

            foreach ($entry in $theme.ContrastTargets.PSObject.Properties) {
                $pair = '' + $entry.Name
                $target = [double]$entry.Value
                $parts = $pair.Split('|')

                if ($parts.Count -ne 2) {
                    $failures.Add(("Theme '{0}' has invalid contrastTargets key '{1}' (expected 'ForegroundKey|BackgroundKey')." -f $theme.Name, $pair)) | Out-Null
                    continue
                }

                $foregroundKey = $parts[0]
                $backgroundKey = $parts[1]
                $foreground = ThemeModule\Get-ThemeToken -Key $foregroundKey
                $background = ThemeModule\Get-ThemeToken -Key $backgroundKey

                if ([string]::IsNullOrWhiteSpace($foreground) -or [string]::IsNullOrWhiteSpace($background)) {
                    $failures.Add(("Theme '{0}' missing token(s) for contrast target '{1}': {2}='{3}' {4}='{5}'" -f $theme.Name, $pair, $foregroundKey, $foreground, $backgroundKey, $background)) | Out-Null
                    continue
                }

                try {
                    $ratio = Get-ContrastRatio -Foreground $foreground -Background $background
                    if ($ratio -lt $target) {
                        $failures.Add(("Theme '{0}' contrast target '{1}' {2} < {3} ({4} on {5})" -f $theme.Name, $pair, ([Math]::Round($ratio, 2)), $target, $foreground, $background)) | Out-Null
                    }
                } catch {
                    $failures.Add(("Theme '{0}' contrast target '{1}' failed contrast calc ({2} on {3}): {4}" -f $theme.Name, $pair, $foreground, $background, $_.Exception.Message)) | Out-Null
                }
            }
        }

        if ($failures.Count -gt 0) {
            throw ($failures -join [Environment]::NewLine)
        }
    }
}

