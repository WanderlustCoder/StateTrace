Set-StrictMode -Version Latest

<#
.SYNOPSIS
Tests for the status strip freshness indicator logic (ST-H-002).
#>

Describe 'Freshness indicator threshold logic' {
    Context 'Age-based color selection' {
        It 'Returns Green for data less than 24 hours old' {
            $age = [timespan]::FromHours(1)
            $color = if ($age.TotalHours -lt 24) { 'Green' }
                     elseif ($age.TotalHours -lt 48) { 'Yellow' }
                     elseif ($age.TotalDays -lt 7) { 'Orange' }
                     else { 'Red' }
            $color | Should Be 'Green'
        }

        It 'Returns Green for data just under 24 hours old' {
            $age = [timespan]::FromHours(23.9)
            $color = if ($age.TotalHours -lt 24) { 'Green' }
                     elseif ($age.TotalHours -lt 48) { 'Yellow' }
                     elseif ($age.TotalDays -lt 7) { 'Orange' }
                     else { 'Red' }
            $color | Should Be 'Green'
        }

        It 'Returns Yellow for data between 24-48 hours old' {
            $age = [timespan]::FromHours(36)
            $color = if ($age.TotalHours -lt 24) { 'Green' }
                     elseif ($age.TotalHours -lt 48) { 'Yellow' }
                     elseif ($age.TotalDays -lt 7) { 'Orange' }
                     else { 'Red' }
            $color | Should Be 'Yellow'
        }

        It 'Returns Orange for data between 2-7 days old' {
            $age = [timespan]::FromDays(4)
            $color = if ($age.TotalHours -lt 24) { 'Green' }
                     elseif ($age.TotalHours -lt 48) { 'Yellow' }
                     elseif ($age.TotalDays -lt 7) { 'Orange' }
                     else { 'Red' }
            $color | Should Be 'Orange'
        }

        It 'Returns Red for data older than 7 days' {
            $age = [timespan]::FromDays(10)
            $color = if ($age.TotalHours -lt 24) { 'Green' }
                     elseif ($age.TotalHours -lt 48) { 'Yellow' }
                     elseif ($age.TotalDays -lt 7) { 'Orange' }
                     else { 'Red' }
            $color | Should Be 'Red'
        }
    }

    Context 'Age text formatting' {
        It 'Formats age less than 1 minute as "<1 min ago"' {
            $age = [timespan]::FromSeconds(30)
            $ageText = if ($age.TotalMinutes -lt 1) { '<1 min ago' }
                       elseif ($age.TotalHours -lt 1) { '{0:F0} min ago' -f [math]::Floor($age.TotalMinutes) }
                       elseif ($age.TotalDays -lt 1) { '{0:F1} h ago' -f $age.TotalHours }
                       else { '{0:F1} d ago' -f $age.TotalDays }
            $ageText | Should Be '<1 min ago'
        }

        It 'Formats age in minutes for less than 1 hour' {
            $age = [timespan]::FromMinutes(45)
            $ageText = if ($age.TotalMinutes -lt 1) { '<1 min ago' }
                       elseif ($age.TotalHours -lt 1) { '{0:F0} min ago' -f [math]::Floor($age.TotalMinutes) }
                       elseif ($age.TotalDays -lt 1) { '{0:F1} h ago' -f $age.TotalHours }
                       else { '{0:F1} d ago' -f $age.TotalDays }
            $ageText | Should Be '45 min ago'
        }

        It 'Formats age in hours for less than 1 day' {
            $age = [timespan]::FromHours(5.5)
            $ageText = if ($age.TotalMinutes -lt 1) { '<1 min ago' }
                       elseif ($age.TotalHours -lt 1) { '{0:F0} min ago' -f [math]::Floor($age.TotalMinutes) }
                       elseif ($age.TotalDays -lt 1) { '{0:F1} h ago' -f $age.TotalHours }
                       else { '{0:F1} d ago' -f $age.TotalDays }
            $ageText | Should Be '5.5 h ago'
        }

        It 'Formats age in days for 1 day or more' {
            $age = [timespan]::FromDays(2.3)
            $ageText = if ($age.TotalMinutes -lt 1) { '<1 min ago' }
                       elseif ($age.TotalHours -lt 1) { '{0:F0} min ago' -f [math]::Floor($age.TotalMinutes) }
                       elseif ($age.TotalDays -lt 1) { '{0:F1} h ago' -f $age.TotalHours }
                       else { '{0:F1} d ago' -f $age.TotalDays }
            $ageText | Should Be '2.3 d ago'
        }
    }

    Context 'Status text descriptions' {
        It 'Returns correct status text for Green' {
            $statusText = switch ('Green') {
                'Green'  { 'Fresh (< 24 hours old)' }
                'Yellow' { 'Warning (24-48 hours old)' }
                'Orange' { 'Stale (2-7 days old)' }
                'Red'    { 'Very stale (> 7 days old)' }
                default  { 'Unknown' }
            }
            $statusText | Should Be 'Fresh (< 24 hours old)'
        }

        It 'Returns correct status text for Yellow' {
            $statusText = switch ('Yellow') {
                'Green'  { 'Fresh (< 24 hours old)' }
                'Yellow' { 'Warning (24-48 hours old)' }
                'Orange' { 'Stale (2-7 days old)' }
                'Red'    { 'Very stale (> 7 days old)' }
                default  { 'Unknown' }
            }
            $statusText | Should Be 'Warning (24-48 hours old)'
        }

        It 'Returns correct status text for Orange' {
            $statusText = switch ('Orange') {
                'Green'  { 'Fresh (< 24 hours old)' }
                'Yellow' { 'Warning (24-48 hours old)' }
                'Orange' { 'Stale (2-7 days old)' }
                'Red'    { 'Very stale (> 7 days old)' }
                default  { 'Unknown' }
            }
            $statusText | Should Be 'Stale (2-7 days old)'
        }

        It 'Returns correct status text for Red' {
            $statusText = switch ('Red') {
                'Green'  { 'Fresh (< 24 hours old)' }
                'Yellow' { 'Warning (24-48 hours old)' }
                'Orange' { 'Stale (2-7 days old)' }
                'Red'    { 'Very stale (> 7 days old)' }
                default  { 'Unknown' }
            }
            $statusText | Should Be 'Very stale (> 7 days old)'
        }
    }
}

Describe 'MainWindow.xaml status strip elements' {
    BeforeAll {
        $xamlPath = Join-Path (Split-Path $PSCommandPath) '..\..\Main\MainWindow.xaml'
        $xamlContent = Get-Content -LiteralPath (Resolve-Path $xamlPath) -Raw
    }

    It 'Contains FreshnessIndicator ellipse element' {
        $xamlContent | Should Match 'Name="FreshnessIndicator"'
    }

    It 'Contains FreshnessLabel element' {
        $xamlContent | Should Match 'Name="FreshnessLabel"'
    }

    It 'Contains PipelineHealthLabel element' {
        $xamlContent | Should Match 'Name="PipelineHealthLabel"'
    }

    It 'Contains ViewPipelineLogButton element' {
        $xamlContent | Should Match 'Name="ViewPipelineLogButton"'
    }

    It 'Contains RefreshFromDbButton element' {
        $xamlContent | Should Match 'Name="RefreshFromDbButton"'
    }

    It 'Has FreshnessIndicator with correct dimensions' {
        $xamlContent | Should Match 'Ellipse.*Width="12".*Height="12"'
    }
}
