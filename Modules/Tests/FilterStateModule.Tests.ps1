Set-StrictMode -Version Latest

Describe "FilterStateModule Update-DeviceFilter" {
    BeforeAll {
        Add-Type -AssemblyName PresentationFramework
        $testDir = Split-Path $PSCommandPath
        $filterPath = Resolve-Path (Join-Path $testDir "..\FilterStateModule.psm1")
        $viewStatePath = Resolve-Path (Join-Path $testDir "..\ViewStateService.psm1")
        $repoPath = Resolve-Path (Join-Path $testDir "..\DeviceRepositoryModule.psm1")
        $catalogPath = Resolve-Path (Join-Path $testDir "..\DeviceCatalogModule.psm1")
        Import-Module $viewStatePath -Force
        Import-Module $repoPath -Force
        Import-Module $catalogPath -Force
        Import-Module $filterPath -Force
    }

    AfterAll {
        Remove-Module FilterStateModule -Force
        Remove-Module ViewStateService -Force
        Remove-Module DeviceRepositoryModule -Force
        Remove-Module DeviceCatalogModule -Force
    }

    BeforeEach {
        $global:DeviceMetadata = @{
            'SITE1-Z1-SW1' = [pscustomobject]@{ Site = 'SITE1'; Zone = 'Z1'; Building = 'B1'; Room = 'R101' }
            'SITE1-Z2-SW2' = [pscustomobject]@{ Site = 'SITE1'; Zone = 'Z2'; Building = 'B2'; Room = 'R201' }
            'SITE2-Z3-SW3' = [pscustomobject]@{ Site = 'SITE2'; Zone = 'Z3'; Building = 'B3'; Room = 'R301' }
        }

        FilterStateModule\Set-FilterFaulted -Faulted $false
        $global:ProgrammaticFilterUpdate = $false
        $global:AllInterfaces = @()
        $global:InterfacesLoadAllowed = $true

        $siteCombo      = New-Object System.Windows.Controls.ComboBox
        $zoneCombo      = New-Object System.Windows.Controls.ComboBox
        $buildingCombo  = New-Object System.Windows.Controls.ComboBox
        $roomCombo      = New-Object System.Windows.Controls.ComboBox
        $hostnameCombo  = New-Object System.Windows.Controls.ComboBox

        $script:FilterTestControls = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)
        $script:FilterTestControls['SiteDropdown']     = $siteCombo
        $script:FilterTestControls['ZoneDropdown']     = $zoneCombo
        $script:FilterTestControls['BuildingDropdown'] = $buildingCombo
        $script:FilterTestControls['RoomDropdown']     = $roomCombo
        $script:FilterTestControls['HostnameDropdown'] = $hostnameCombo

        $global:window = New-Object psobject
        $global:window | Add-Member -MemberType ScriptMethod -Name FindName -Value {
            param($name)
            if ($script:FilterTestControls.ContainsKey($name)) {
                return $script:FilterTestControls[$name]
            }
            return $null
        }

        $mockInterfaces = {
            param()
            $site = if ($PSBoundParameters.ContainsKey('Site')) { '' + $PSBoundParameters['Site'] } else { '' }
            if ([string]::IsNullOrWhiteSpace($site) -or $site -eq 'All Sites') {
                return ,([pscustomobject]@{ Hostname = 'SITE1-Z1-SW1'; PortSort = '001' })
            }
            if ($site -eq 'SITE2') {
                return ,([pscustomobject]@{ Hostname = 'SITE2-Z3-SW3'; PortSort = '001' })
            }
            return ,([pscustomobject]@{ Hostname = 'SITE1-Z1-SW1'; PortSort = '001' })
        }

        Mock -ModuleName ViewStateService -CommandName 'DeviceRepositoryModule\Get-GlobalInterfaceSnapshot' -MockWith $mockInterfaces
        Mock -ModuleName FilterStateModule -CommandName 'DeviceRepositoryModule\Get-GlobalInterfaceSnapshot' {
            throw 'FilterStateModule should not call DeviceRepositoryModule\Get-GlobalInterfaceSnapshot directly.'
        }

        FilterStateModule\Initialize-DeviceFilters -Window $global:window
    }

    AfterEach {
        Remove-Variable -Name DeviceMetadata -Scope Global -ErrorAction SilentlyContinue
        Remove-Variable -Name window -Scope Global -ErrorAction SilentlyContinue
        Remove-Variable -Name ProgrammaticFilterUpdate -Scope Global -ErrorAction SilentlyContinue
        Remove-Variable -Name AllInterfaces -Scope Global -ErrorAction SilentlyContinue
        Remove-Variable -Name InterfacesLoadAllowed -Scope Global -ErrorAction SilentlyContinue
        Remove-Variable -Name FilterTestControls -Scope Script -ErrorAction SilentlyContinue
    }

    It "populates filter dropdowns using ViewStateService snapshots" {
        FilterStateModule\Update-DeviceFilter

        ($script:FilterTestControls['SiteDropdown'].ItemsSource -contains 'SITE1') | Should Be $true
        ($script:FilterTestControls['ZoneDropdown'].ItemsSource -contains 'Z1') | Should Be $true
        $script:FilterTestControls['ZoneDropdown'].SelectedItem | Should Be 'Z1'
        ($script:FilterTestControls['HostnameDropdown'].ItemsSource -contains 'SITE1-Z1-SW1') | Should Be $true
        ($script:FilterTestControls['BuildingDropdown'].ItemsSource -contains 'B1') | Should Be $true
        ($script:FilterTestControls['RoomDropdown'].ItemsSource -contains 'R101') | Should Be $true
    }

    It "refreshes interface cache when selection changes" {
        FilterStateModule\Update-DeviceFilter

        $script:FilterTestControls['SiteDropdown'].SelectedItem = 'SITE2'
        $script:FilterTestControls['ZoneDropdown'].SelectedItem = 'All Zones'

        FilterStateModule\Update-DeviceFilter

        $script:FilterTestControls['ZoneDropdown'].SelectedItem | Should Be 'Z3'
        ($script:FilterTestControls['HostnameDropdown'].ItemsSource -contains 'SITE2-Z3-SW3') | Should Be $true
        Assert-MockCalled -ModuleName ViewStateService -CommandName 'DeviceRepositoryModule\Get-GlobalInterfaceSnapshot' -ParameterFilter { $Site -eq 'SITE2' } -Times 1
    }
    It "initializes interface cache to empty list when service returns null" {
        Mock -ModuleName FilterStateModule -CommandName 'ViewStateService\Get-InterfacesForContext' {
            return $null
        }

        $global:AllInterfaces = $null

        FilterStateModule\Initialize-DeviceFilters -Window $global:window

        $isNull = [bool]($null -eq $global:AllInterfaces)
        $isNull | Should Be $false
        ($global:AllInterfaces -is [System.Collections.Generic.List[object]]) | Should Be $true
        $global:AllInterfaces.Count | Should Be 0
    }

    It "populates site and zone from location entries without loading interfaces when disabled" {
        $global:DeviceMetadata = $null
        $global:InterfacesLoadAllowed = $false
        Mock -ModuleName ViewStateService -CommandName 'DeviceRepositoryModule\Get-GlobalInterfaceSnapshot' {
            throw 'DeviceRepositoryModule\Get-GlobalInterfaceSnapshot should not be called when interfaces are disabled.'
        }
        $global:DeviceLocationEntries = @(
            [pscustomobject]@{ Site = 'SITE1'; Zone = 'Z1'; Building = 'B1'; Room = 'R101' },
            [pscustomobject]@{ Site = 'SITE2'; Zone = 'Z2'; Building = 'B2'; Room = 'R201' }
        )

        # Do not pass LocationEntries explicitly; exercise fallback to DeviceCatalogModule
        FilterStateModule\Initialize-DeviceFilters -Window $global:window
        FilterStateModule\Update-DeviceFilter

        $siteItems = @($script:FilterTestControls['SiteDropdown'].ItemsSource)
        $zoneItems = @($script:FilterTestControls['ZoneDropdown'].ItemsSource)
        ($siteItems -contains 'SITE1') | Should Be $true
        ($zoneItems -contains 'Z1') | Should Be $true
        $hostItems = $script:FilterTestControls['HostnameDropdown'].ItemsSource
        $hostCount = if ($hostItems) { $hostItems.Count } else { 0 }
        $hostCount | Should Be 0
        $global:AllInterfaces.Count | Should Be 0
    }

    It "loads site list from Get-DeviceLocationEntries when metadata is empty (integration)" {
        $global:DeviceMetadata = $null
        $global:InterfacesLoadAllowed = $false
        $global:DeviceLocationEntries = @()
        Mock -ModuleName ViewStateService -CommandName 'DeviceRepositoryModule\Get-GlobalInterfaceSnapshot' {
            throw 'DeviceRepositoryModule\Get-GlobalInterfaceSnapshot should not be called when interfaces are disabled.'
        }

        $locations = DeviceCatalogModule\Get-DeviceLocationEntries
        if (-not $locations -or $locations.Count -eq 0) {
            Set-ItResult -Skipped -Because "No location entries available from Get-DeviceLocationEntries"
            return
        }

        FilterStateModule\Initialize-DeviceFilters -Window $global:window -LocationEntries $locations
        FilterStateModule\Update-DeviceFilter

        $siteItems = @($script:FilterTestControls['SiteDropdown'].ItemsSource)
        ($siteItems.Count -ge 2) | Should Be $true # All Sites + at least one real site
        foreach ($loc in $locations) {
            if ($loc.Site) {
                ($siteItems -contains $loc.Site) | Should Be $true
            }
        }

        $hostItems = $script:FilterTestControls['HostnameDropdown'].ItemsSource
        $hostCount = if ($hostItems) { $hostItems.Count } else { 0 }
        $hostCount | Should Be 0
        $global:AllInterfaces.Count | Should Be 0
    }


}
