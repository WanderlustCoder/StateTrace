# ThemeModule.psm1
# Provides dynamic theming support for StateTrace.

using namespace System.Windows
using namespace System.Windows.Media
using namespace System.Windows.Markup

Set-StrictMode -Version Latest

$script:ThemeDirectory           = Join-Path $PSScriptRoot '..\Themes'
$script:ThemeCache               = @{}
$script:ResolvedThemeCache       = @{}
$script:CurrentThemeName         = $null
$script:CurrentThemeTokens       = @{}
$script:CurrentThemeMetadata     = $null
$script:ThemeBrushCache          = @{}
$script:ThemeResourceDictionary  = $null
$script:SharedStylesPath         = Join-Path $PSScriptRoot '..\Resources\SharedStyles.xaml'
$script:SharedStylesDictionary   = $null
$script:ThemeChangedHandlers     = [System.Collections.Generic.List[System.Action[string]]]::new()
$script:PresentationFrameworkLoaded = $false
$script:ConvertersRegistered     = $false

function Ensure-PresentationFrameworkLoaded {
    if ($script:PresentationFrameworkLoaded) { return $true }
    try { $null = [Application] } catch {
        try { Add-Type -AssemblyName PresentationFramework } catch { return $false }
    }
    $script:PresentationFrameworkLoaded = $true
    return $true
}

function Register-ValueConverters {
    <#
    .SYNOPSIS
    Registers custom IValueConverter implementations for XAML binding.
    #>
    if ($script:ConvertersRegistered) { return }

    $app = Get-WpfApplication
    if (-not $app) { return }

    # Define converters - converts status/state strings to theme brushes
    try {
        Add-Type -TypeDefinition @"
using System;
using System.Globalization;
using System.Windows;
using System.Windows.Data;
using System.Windows.Media;

namespace StateTrace.Converters
{
    // Converts interface status (up/down/connected/etc) to theme brushes
    public class StatusToBrushConverter : IValueConverter
    {
        public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
        {
            string status = value as string;
            if (string.IsNullOrEmpty(status))
                return DependencyProperty.UnsetValue;

            string resourceKey;
            switch (status.ToLowerInvariant())
            {
                case "up":
                case "connected":
                    resourceKey = "Theme.Status.Success";
                    break;
                case "down":
                case "err-disabled":
                    resourceKey = "Theme.Status.Danger";
                    break;
                case "notconnect":
                    resourceKey = "Theme.Status.Warning";
                    break;
                case "disabled":
                default:
                    resourceKey = "Theme.Status.Neutral";
                    break;
            }

            var app = Application.Current;
            if (app != null && app.Resources.Contains(resourceKey))
                return app.Resources[resourceKey];

            return DependencyProperty.UnsetValue;
        }

        public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        {
            throw new NotImplementedException();
        }
    }

    // Converts cable status (Active/Reserved/Faulty/etc) to theme brushes
    public class CableStatusToBrushConverter : IValueConverter
    {
        public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
        {
            string status = value as string;
            if (string.IsNullOrEmpty(status))
                return DependencyProperty.UnsetValue;

            string resourceKey;
            switch (status)
            {
                case "Active":
                case "Connected":
                    resourceKey = "Theme.Status.Success";
                    break;
                case "Reserved":
                    resourceKey = "Theme.Status.Info";
                    break;
                case "Faulty":
                    resourceKey = "Theme.Status.Danger";
                    break;
                case "Planned":
                    resourceKey = "Theme.Status.Warning";
                    break;
                case "Abandoned":
                default:
                    resourceKey = "Theme.Status.Neutral";
                    break;
            }

            var app = Application.Current;
            if (app != null && app.Resources.Contains(resourceKey))
                return app.Resources[resourceKey];

            return DependencyProperty.UnsetValue;
        }

        public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        {
            throw new NotImplementedException();
        }
    }

    // Converts port reorg label state (Parked/Changed) to theme brushes
    public class LabelStateToBrushConverter : IValueConverter
    {
        public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
        {
            string state = value as string;
            if (string.IsNullOrEmpty(state))
                return DependencyProperty.UnsetValue;

            string resourceKey;
            switch (state)
            {
                case "Parked":
                    resourceKey = "Theme.Template.Red";
                    break;
                case "Changed":
                    resourceKey = "Theme.Template.Green";
                    break;
                default:
                    resourceKey = "Theme.Surface.Primary";
                    break;
            }

            var app = Application.Current;
            if (app != null && app.Resources.Contains(resourceKey))
                return app.Resources[resourceKey];

            return DependencyProperty.UnsetValue;
        }

        public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        {
            throw new NotImplementedException();
        }
    }
}
"@ -ReferencedAssemblies @('PresentationFramework', 'PresentationCore', 'WindowsBase', 'System.Xaml') -ErrorAction Stop
    } catch {
        # Type may already be defined from a previous load
        if ($_.Exception.Message -notmatch 'already exists') {
            Write-Warning "Failed to define converters: $($_.Exception.Message)"
            return
        }
    }

    # Register converters as application resources
    try {
        $converters = @(
            @{ Name = 'StatusToBrushConverter'; Type = 'StateTrace.Converters.StatusToBrushConverter' }
            @{ Name = 'CableStatusToBrushConverter'; Type = 'StateTrace.Converters.CableStatusToBrushConverter' }
            @{ Name = 'LabelStateToBrushConverter'; Type = 'StateTrace.Converters.LabelStateToBrushConverter' }
        )
        foreach ($conv in $converters) {
            if (-not $app.Resources.Contains($conv.Name)) {
                $instance = New-Object $conv.Type
                $app.Resources.Add($conv.Name, $instance)
            }
        }
        $script:ConvertersRegistered = $true
    } catch {
        Write-Warning "Failed to register converters: $($_.Exception.Message)"
    }
}

function Get-WpfApplication {
    if (-not (Ensure-PresentationFrameworkLoaded)) { return $null }
    try { return [Application]::Current } catch { return $null }
}

function Get-ThemeDirectory {
    if (-not (Test-Path -LiteralPath $script:ThemeDirectory)) {
        throw "Theme directory not found at $($script:ThemeDirectory)"
    }
    return $script:ThemeDirectory
}

function Get-ThemeFile {
    param(
        [Parameter(Mandatory=$true)][object]$Name
    )

    $themeName = if ($null -ne $Name) { '' + $Name } else { '' }
    if ([string]::IsNullOrWhiteSpace($themeName)) { return $null }

    $themeDir = Get-ThemeDirectory

    $primary = Join-Path $themeDir ("{0}.json" -f $themeName)
    if (Test-Path -LiteralPath $primary) { return $primary }

    $secondary = Join-Path $themeDir $themeName
    if (Test-Path -LiteralPath $secondary) { return $secondary }

    return $null
}

function Read-ThemeDefinition {
    param(
        [Parameter(Mandatory=$true)][string]$Name
    )

    if ($script:ThemeCache.ContainsKey($Name)) {
        return $script:ThemeCache[$Name]
    }

    $path = Get-ThemeFile -Name $Name
    if (-not $path) { return $null }

    try {
        $raw = Get-Content -Path $path -Raw -ErrorAction Stop
        $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
        $script:ThemeCache[$Name] = $parsed
        return $parsed
    } catch {
        throw "Failed to parse theme '$Name': $($_.Exception.Message)"
    }
}

function Resolve-ThemeTokens {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [System.Collections.Generic.HashSet[string]]$Visited
    )

    if ($script:ResolvedThemeCache.ContainsKey($Name)) {
        return $script:ResolvedThemeCache[$Name]
    }

    if (-not $Visited) {
        $Visited = [System.Collections.Generic.HashSet[string]]::new()
    }
    if (-not $Visited.Add($Name)) {
        throw "Circular theme inheritance detected for '$Name'"
    }

    $definition = Read-ThemeDefinition -Name $Name
    if (-not $definition) {
        throw "Theme '$Name' not found."
    }

    $tokens = @{}
    $parentName = $null
    try {
        $parentProp = $definition.PSObject.Properties['extends']
        if ($parentProp) {
            $parentName = '' + $parentProp.Value
        }
    } catch {
        $parentName = $null
    }

    if (-not [string]::IsNullOrWhiteSpace($parentName)) {
        $parentTokens = Resolve-ThemeTokens -Name $parentName -Visited $Visited
        foreach ($key in $parentTokens.Keys) {
            $tokens[$key] = $parentTokens[$key]
        }
    }

    $tokenNode = $null
    try {
        $tokensProp = $definition.PSObject.Properties['tokens']
        if ($tokensProp) {
            $tokenNode = $tokensProp.Value
        }
    } catch {
        $tokenNode = $null
    }

    if ($tokenNode) {
        if ($tokenNode -is [System.Collections.IDictionary]) {
            foreach ($key in $tokenNode.Keys) {
                $keyText = '' + $key
                if (-not [string]::IsNullOrWhiteSpace($keyText)) {
                    $tokens[$keyText] = '' + $tokenNode[$key]
                }
            }
        } else {
            foreach ($prop in $tokenNode.PSObject.Properties) {
                $tokens[$prop.Name] = '' + $prop.Value
            }
        }
    }

    $script:ResolvedThemeCache[$Name] = $tokens
    return $tokens
}

function New-FrozenBrush {
    param(
        [Parameter(Mandatory=$true)][string]$Value
    )

    $trimmed = $Value.Trim()
    try {
        $converter = [BrushConverter]::new()
        $brush = $converter.ConvertFromString($trimmed)
        if ($brush -is [Freezable] -and $brush.CanFreeze) {
            $brush.Freeze()
        }
        return [Brush]$brush
    } catch {
        throw "Unsupported color value '$Value'"
    }
}

function Ensure-SharedStylesDictionary {
    $app = Get-WpfApplication
    if (-not $app) { return }

    if (-not $script:SharedStylesDictionary) {
        if (Test-Path -LiteralPath $script:SharedStylesPath) {
            $stream = $null
            try {
                $stream = [System.IO.File]::Open($script:SharedStylesPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
                $script:SharedStylesDictionary = [XamlReader]::Load($stream)
            } catch {
                Write-Warning ("Failed to load shared styles: {0}" -f $_.Exception.Message)
            } finally {
                if ($stream) { $stream.Dispose() }
            }
        }
    }

    if ($script:SharedStylesDictionary -and -not $app.Resources.MergedDictionaries.Contains($script:SharedStylesDictionary)) {
        [void]$app.Resources.MergedDictionaries.Add($script:SharedStylesDictionary)
    }

    # Register value converters for XAML bindings
    Register-ValueConverters
}

function Update-ThemeResources {
    if (-not $script:CurrentThemeTokens) { return }
    $app = Get-WpfApplication
    if (-not $app) {
        # No WPF application yet; resources will be applied later
        return
    }

    if ($script:ThemeResourceDictionary -and $app.Resources.MergedDictionaries.Contains($script:ThemeResourceDictionary)) {
        [void]$app.Resources.MergedDictionaries.Remove($script:ThemeResourceDictionary)
    }

    $dict = [ResourceDictionary]::new()
    foreach ($entry in $script:CurrentThemeTokens.GetEnumerator()) {
        try {
            $dict[$entry.Key] = New-FrozenBrush -Value $entry.Value
        } catch {
            # Skip invalid entries but continue applying others
        }
    }

    $app.Resources.MergedDictionaries.Insert(0, $dict)
    $inputBackgroundBrush = Get-ThemeBrush -Key 'Theme.Input.Background'
    $inputTextBrush = Get-ThemeBrush -Key 'Theme.Input.Text'
    $highlightBrush = Get-ThemeBrush -Key 'Theme.DataGrid.SelectionBackground'
    if (-not $highlightBrush) { $highlightBrush = Get-ThemeBrush -Key 'Theme.Surface.Secondary' }

    $highlightTextBrush = Get-ThemeBrush -Key 'Theme.Text.Primary'

    if ($inputBackgroundBrush) {
        $app.Resources[[System.Windows.SystemColors]::WindowBrushKey] = $inputBackgroundBrush
        $app.Resources[[System.Windows.SystemColors]::ControlBrushKey] = $inputBackgroundBrush
    }
    if ($inputTextBrush) {
        $app.Resources[[System.Windows.SystemColors]::ControlTextBrushKey] = $inputTextBrush
        $app.Resources[[System.Windows.SystemColors]::WindowTextBrushKey] = $inputTextBrush
    }
    if ($highlightBrush) {
        $app.Resources[[System.Windows.SystemColors]::HighlightBrushKey] = $highlightBrush
    }
    if ($highlightTextBrush) {
        $app.Resources[[System.Windows.SystemColors]::HighlightTextBrushKey] = $highlightTextBrush
    }

    $highlightColor = Get-ThemeColor -Key 'Theme.DataGrid.SelectionBackground'
    if (-not $highlightColor) { $highlightColor = Get-ThemeColor -Key 'Theme.Surface.Secondary' }
    $highlightTextColor = Get-ThemeColor -Key 'Theme.Text.Primary'

    if ($highlightColor) {
        $app.Resources[[System.Windows.SystemColors]::HighlightColorKey] = $highlightColor
    }
    if ($highlightTextColor) {
        $app.Resources[[System.Windows.SystemColors]::HighlightTextColorKey] = $highlightTextColor
    }

    $inputBackgroundColor = Get-ThemeColor -Key 'Theme.Input.Background'
    if ($inputBackgroundColor) {
        $app.Resources[[System.Windows.SystemColors]::WindowColorKey] = $inputBackgroundColor
        $app.Resources[[System.Windows.SystemColors]::ControlColorKey] = $inputBackgroundColor
    }
    $inputTextColor = Get-ThemeColor -Key 'Theme.Input.Text'
    if ($inputTextColor) {
        $app.Resources[[System.Windows.SystemColors]::WindowTextColorKey] = $inputTextColor
        $app.Resources[[System.Windows.SystemColors]::ControlTextColorKey] = $inputTextColor
    }
    $script:ThemeResourceDictionary = $dict
    $script:ThemeBrushCache = @{}

    Ensure-SharedStylesDictionary
}

function Invoke-ThemeChanged {
    param([string]$Name)
    foreach ($handler in $script:ThemeChangedHandlers) {
        try { $handler.Invoke($Name) } catch { }
    }
}

function Set-StateTraceTheme {
    param(
        [Parameter(Mandatory=$true)][object]$Name,
        [switch]$Silent
    )

    $resolvedName = $null
    if ($Name -is [string] -and -not [string]::IsNullOrWhiteSpace($Name)) {
        $resolvedName = $Name
    } elseif ($Name -is [System.Management.Automation.PSObject]) {
        if ($Name.PSObject.Properties['Name']) {
            $resolvedName = '' + $Name.PSObject.Properties['Name'].Value
        }
    } elseif ($Name -is [System.Collections.IDictionary]) {
        if ($Name.Contains('Name')) { $resolvedName = '' + $Name['Name'] }
    } elseif ($Name -is [System.Collections.IEnumerable] -and -not ($Name -is [string])) {
        foreach ($item in $Name) {
            if ($null -ne $item) {
                $resolvedName = '' + $item
                break
            }
        }
    } else {
        if ($null -ne $Name) { $resolvedName = '' + $Name }
    }

    if ([string]::IsNullOrWhiteSpace($resolvedName)) {
        throw 'Theme name cannot be empty.'
    }

    $Name = $resolvedName
    $tokens = Resolve-ThemeTokens -Name $Name

    $definition = Read-ThemeDefinition -Name $Name
    $themePath = Get-ThemeFile -Name $Name
    $displayName = if ($definition -and $definition.PSObject.Properties['name']) { '' + $definition.name } else { $Name }
    $extends = if ($definition -and $definition.PSObject.Properties['extends']) { '' + $definition.extends } else { $null }
    $inspiration = if ($definition -and $definition.PSObject.Properties['inspiration']) { $definition.inspiration } else { $null }
    $contrastTargets = if ($definition -and $definition.PSObject.Properties['contrastTargets']) { $definition.contrastTargets } else { $null }

    $script:CurrentThemeTokens = $tokens
    $script:CurrentThemeName = $Name
    $script:CurrentThemeMetadata = [PSCustomObject]@{
        Name            = $Name
        DisplayName     = $displayName
        Extends         = $extends
        Inspiration     = $inspiration
        ContrastTargets = $contrastTargets
        Path            = $themePath
    }
    $script:ThemeBrushCache = @{}

    Update-ThemeResources
    if (-not $Silent) {
        Invoke-ThemeChanged -Name $Name
    }
    return $tokens
}

function Ensure-ThemeResources {
    if (-not $script:CurrentThemeTokens -or -not $script:CurrentThemeName) {
        return
    }
    $app = Get-WpfApplication
    if (-not $app) { return }
    if (-not $script:ThemeResourceDictionary -or -not $app.Resources.MergedDictionaries.Contains($script:ThemeResourceDictionary)) {
        Update-ThemeResources
    }
}

function Initialize-StateTraceTheme {
    param(
        [string]$PreferredTheme = 'blue-angels'
    )

    $candidates = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($PreferredTheme)) { $null = $candidates.Add($PreferredTheme) }
    if (-not $candidates.Contains('helldivers-spill-oil')) { $null = $candidates.Add('helldivers-spill-oil') }
    if (-not $candidates.Contains('blue-angels')) { $null = $candidates.Add('blue-angels') }
    if (-not $candidates.Contains('base')) { $null = $candidates.Add('base') }

    $initialized = $false
    foreach ($candidate in $candidates) {
        try {
            Set-StateTraceTheme -Name $candidate -Silent | Out-Null
            $initialized = $true
            break
        } catch { }
    }

    if (-not $initialized) {
        throw 'Failed to initialize theme resources.'
    }

    Ensure-ThemeResources
}

function Get-StateTraceTheme {
    return $script:CurrentThemeName
}

function Get-StateTraceThemeMetadata {
    return $script:CurrentThemeMetadata
}

function Get-ThemeToken {
    param(
        [Parameter(Mandatory=$true)][string]$Key
    )
    if (-not $script:CurrentThemeTokens.ContainsKey($Key)) {
        return $null
    }
    return $script:CurrentThemeTokens[$Key]
}

function Get-ThemeColor {
    param(
        [Parameter(Mandatory=$true)][string]$Key
    )

    $token = Get-ThemeToken -Key $Key
    if (-not $token) { return $null }

    try {
        return [ColorConverter]::ConvertFromString($token)
    } catch {
        return $null
    }
}
function Get-ThemeBrush {
    param(
        [Parameter(Mandatory=$true)][string]$Key
    )
    if ($script:ThemeBrushCache.ContainsKey($Key)) {
        return $script:ThemeBrushCache[$Key]
    }
    $token = Get-ThemeToken -Key $Key
    if (-not $token) { return $null }
    $brush = New-FrozenBrush -Value $token
    $script:ThemeBrushCache[$Key] = $brush
    return $brush
}

function Get-AvailableStateTraceThemes {
    $themeDir = Get-ThemeDirectory
    $files = Get-ChildItem -Path $themeDir -Filter '*.json' -File | Sort-Object Name
    $themes = @()
    foreach ($file in $files) {
        if ($file.BaseName -eq 'base') { continue }
        try {
            $def = Read-ThemeDefinition -Name ($file.BaseName)
            $display = $file.BaseName
            try {
                $nameProp = $def.PSObject.Properties['name']
                if ($nameProp -and -not [string]::IsNullOrWhiteSpace(('' + $nameProp.Value))) {
                    $display = '' + $nameProp.Value
                }
            } catch { }
            $inspiration = if ($def.PSObject.Properties['inspiration']) { $def.inspiration } else { $null }
            $contrastTargets = if ($def.PSObject.Properties['contrastTargets']) { $def.contrastTargets } else { $null }
            $extends = $null
            try {
                $extendsProp = $def.PSObject.Properties['extends']
                if ($extendsProp) {
                    $extends = '' + $extendsProp.Value
                }
            } catch { }
            $themes += [PSCustomObject]@{
                Name            = $file.BaseName
                Display         = $display
                Extends         = $extends
                Inspiration     = $inspiration
                ContrastTargets = $contrastTargets
                Path            = $file.FullName
            }
        } catch {
            # Skip malformed theme files
        }
    }
    return $themes
}

function Register-StateTraceThemeChanged {
    param(
        [Parameter(Mandatory=$true)][System.Action[string]]$Handler
    )
    $script:ThemeChangedHandlers.Add($Handler) | Out-Null
}

function Update-StateTraceThemeResources {
    Ensure-ThemeResources
}

function Get-WindowsThemePreference {
    <#
    .SYNOPSIS
    Detects whether Windows is set to light or dark mode.
    .OUTPUTS
    Returns 'Light' or 'Dark' based on the Windows theme setting.
    #>
    try {
        $regPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
        $value = Get-ItemProperty -Path $regPath -Name 'AppsUseLightTheme' -ErrorAction SilentlyContinue
        if ($null -ne $value -and $value.AppsUseLightTheme -eq 0) {
            return 'Dark'
        }
        return 'Light'
    } catch {
        return 'Light'
    }
}

function Set-AutoTheme {
    <#
    .SYNOPSIS
    Automatically selects and applies a theme based on Windows settings.
    .DESCRIPTION
    Detects the Windows theme preference (light/dark) and applies an appropriate theme.
    #>
    param(
        [string]$LightTheme = 'blue-angels',
        [string]$DarkTheme = 'helldivers-spill-oil'
    )

    $preference = Get-WindowsThemePreference
    $themeName = if ($preference -eq 'Dark') { $DarkTheme } else { $LightTheme }

    try {
        Set-StateTraceTheme -Name $themeName
        return $themeName
    } catch {
        # Fallback to blue-angels if preferred theme fails
        try {
            Set-StateTraceTheme -Name 'blue-angels'
            return 'blue-angels'
        } catch {
            return $null
        }
    }
}

Export-ModuleMember -Function Get-StateTraceTheme, Get-StateTraceThemeMetadata, Set-StateTraceTheme, Get-ThemeToken, Get-ThemeBrush, Initialize-StateTraceTheme, Get-AvailableStateTraceThemes, Register-StateTraceThemeChanged, Update-StateTraceThemeResources, Get-WindowsThemePreference, Set-AutoTheme
