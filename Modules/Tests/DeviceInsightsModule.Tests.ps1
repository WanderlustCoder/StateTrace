Set-StrictMode -Version Latest

function New-SearchWindowStub {
    param(
        [string]$StatusSelection = 'All',
        [string]$AuthSelection   = 'All',
        [string]$SearchText      = ''
    )

    $statusItem = [pscustomobject]@{ Content = $StatusSelection }
    $authItem   = [pscustomobject]@{ Content = $AuthSelection }

    $statusCombo = [pscustomobject]@{ SelectedItem = $statusItem }
    $authCombo   = [pscustomobject]@{ SelectedItem   = $authItem }
    $grid        = [pscustomobject]@{ ItemsSource    = $null }
    $box         = [pscustomobject]@{ Text          = $SearchText }

    $view = [pscustomobject]@{}
    $view | Add-Member -MemberType ScriptMethod -Name FindName -Value ({
        param($name)
        switch ($name) {
            'StatusFilter'         { return $statusCombo }
            'AuthFilter'           { return $authCombo }
            'SearchInterfacesGrid' { return $grid }
            'SearchBox'            { return $box }
            default                { return $null }
        }
    }).GetNewClosure()

    $hostControl = [pscustomobject]@{ Content = $view }
    $window = [pscustomobject]@{}
    $window | Add-Member -MemberType ScriptMethod -Name FindName -Value ({
        param($name)
        if ($name -eq 'SearchInterfacesHost') { return $hostControl }
        return $null
    }).GetNewClosure()

    [pscustomobject]@{
        Window = $window
        Grid   = $grid
        Box    = $box
    }
}

function New-SummaryViewStub {
    $blocks = @{}
    foreach ($name in 'SummaryDevicesCount','SummaryInterfacesCount','SummaryUpCount','SummaryDownCount','SummaryAuthorizedCount','SummaryUnauthorizedCount','SummaryUniqueVlansCount','SummaryExtra') {
        $blocks[$name] = [pscustomobject]@{ Text = '' }
    }
    $view = [pscustomobject]@{}
    $view | Add-Member -MemberType ScriptMethod -Name FindName -Value ({
        param($name)
        return $blocks[$name]
    }).GetNewClosure()
    [pscustomobject]@{
        View   = $view
        Blocks = $blocks
    }
}

function New-AlertsViewStub {
    $grid = [pscustomobject]@{ ItemsSource = $null }
    $view = [pscustomobject]@{}
    $view | Add-Member -MemberType ScriptMethod -Name FindName -Value ({
        param($name)
        if ($name -eq 'AlertsGrid') { return $grid }
        return $null
    }).GetNewClosure()
    [pscustomobject]@{
        View = $view
        Grid = $grid
    }
}

Describe "DeviceInsightsModule view aggregation" {
    BeforeAll {
        $moduleRoot = Split-Path $PSCommandPath
        Import-Module (Resolve-Path (Join-Path $moduleRoot "..\DeviceInsightsModule.psm1")) -Force
        Import-Module (Resolve-Path (Join-Path $moduleRoot "..\DeviceRepositoryModule.psm1")) -Force
        Import-Module (Resolve-Path (Join-Path $moduleRoot "..\FilterStateModule.psm1")) -Force
        $viewStatePath = Resolve-Path (Join-Path $moduleRoot "..\ViewStateService.psm1")
        if (-not (Get-Module -Name ViewStateService -ErrorAction SilentlyContinue)) {
            Import-Module $viewStatePath -Force
        }

        foreach ($var in 'AllInterfaces','summaryView','alertsView','window','AlertsList','DeviceMetadata','DeviceInterfaceCache','InterfacesLoadAllowed') {
            if (Get-Variable -Scope Global -Name $var -ErrorAction SilentlyContinue) {
                Set-Variable -Name "Prev_$var" -Scope Script -Value (Get-Variable -Name $var -Scope Global).Value
            } else {
                Set-Variable -Name "Prev_$var" -Scope Script -Value $null
            }
        }
    }

    AfterAll {
        foreach ($var in 'AllInterfaces','summaryView','alertsView','window','AlertsList','DeviceMetadata','DeviceInterfaceCache','InterfacesLoadAllowed') {
            $prev = Get-Variable -Name "Prev_$var" -Scope Script -ValueOnly
            if ($prev -ne $null) {
                Set-Variable -Name $var -Scope Global -Value $prev
            } else {
                Remove-Variable -Name $var -Scope Global -ErrorAction SilentlyContinue
            }
        }
        Remove-Module DeviceInsightsModule -Force
        Remove-Module DeviceRepositoryModule -Force
        Remove-Module FilterStateModule -Force
    }

    BeforeEach {
        $global:AllInterfaces = [System.Collections.Generic.List[object]]::new()
        $global:summaryView   = $null
        $global:alertsView    = $null
        $global:window        = $null
        $global:AlertsList    = @()
        $global:DeviceMetadata = @{}
        $global:DeviceInterfaceCache = @{}
        $global:InterfacesLoadAllowed = $true
        DeviceInsightsModule\Set-SearchRegexEnabled -Enabled $false
    }

    It "tracks the regex search toggle" {
        DeviceInsightsModule\Get-SearchRegexEnabled | Should Be $false
        DeviceInsightsModule\Set-SearchRegexEnabled -Enabled $true
        DeviceInsightsModule\Get-SearchRegexEnabled | Should Be $true
    }

    It "filters search results by term with location defaults" {
        Mock -ModuleName DeviceInsightsModule -CommandName 'FilterStateModule\Get-SelectedLocation' {
            [pscustomobject]@{ Site = 'All Sites'; Zone = 'All Zones'; Building = $null; Room = $null }
        }
        $global:AllInterfaces.Add([pscustomobject]@{ Hostname = 'SITE1-Z1-SW1'; Site = 'SITE1'; Zone = 'Z1'; Building = 'B1'; Room = 'R1'; Status = 'up'; AuthState = 'authorized'; Port = 'Gi1'; Name = 'Phone'; LearnedMACs = 'AA'; AuthClientMAC = 'AA' }) | Out-Null
        $global:AllInterfaces.Add([pscustomobject]@{ Hostname = 'SITE2-Z9-EDGE'; Site = 'SITE2'; Zone = 'Z9'; Building = 'B9'; Room = 'R9'; Status = 'down'; AuthState = 'unauthorized'; Port = 'Gi9'; Name = 'Printer'; LearnedMACs = 'BB'; AuthClientMAC = 'BB' }) | Out-Null

        $results = DeviceInsightsModule\Update-SearchResults -Term 'phone'

        @($results).Count | Should Be 1
        $results[0].Hostname | Should Be 'SITE1-Z1-SW1'
    }

    It "honours status and auth filters from the search view" {
        Mock -ModuleName DeviceInsightsModule -CommandName 'FilterStateModule\Get-SelectedLocation' {
            [pscustomobject]@{ Site = 'All Sites'; Zone = 'All Zones'; Building = $null; Room = $null }
        }
        $global:AllInterfaces.Add([pscustomobject]@{ Hostname = 'SITE1-Z1-SW1'; Site = 'SITE1'; Zone = 'Z1'; Building = 'B1'; Room = 'R1'; Status = 'up';   AuthState = 'authorized';   Port = 'Gi1'; Name = 'Phone' }) | Out-Null
        $global:AllInterfaces.Add([pscustomobject]@{ Hostname = 'SITE1-Z1-SW2'; Site = 'SITE1'; Zone = 'Z1'; Building = 'B1'; Room = 'R2'; Status = 'down'; AuthState = 'unauthorized'; Port = 'Gi2'; Name = 'AP' }) | Out-Null

        $stub = New-SearchWindowStub -StatusSelection 'Down' -AuthSelection 'Unauthorized'
        $global:window = $stub.Window

        $results = DeviceInsightsModule\Update-SearchResults -Term ''

        @($results).Count | Should Be 1
        $results[0].Hostname | Should Be 'SITE1-Z1-SW2'
    }

    It "supports regex searching when enabled" {
        Mock -ModuleName DeviceInsightsModule -CommandName 'FilterStateModule\Get-SelectedLocation' {
            [pscustomobject]@{ Site = 'All Sites'; Zone = 'All Zones'; Building = $null; Room = $null }
        }
        $global:AllInterfaces.Add([pscustomobject]@{ Hostname = 'SITE3-Z5-SW3'; Site = 'SITE3'; Zone = 'Z5'; Building = 'B5'; Room = 'R5'; Status = 'up'; AuthState = 'authorized'; Port = 'Eth1'; Name = 'Sensor'; LearnedMACs = 'CC-11'; AuthClientMAC = 'CC-22' }) | Out-Null

        DeviceInsightsModule\Set-SearchRegexEnabled -Enabled $true
        $results = DeviceInsightsModule\Update-SearchResults -Term 'CC-\d{2}$'

        @($results).Count | Should Be 1
        $results[0].Name | Should Be 'Sensor'
    }

    It "sorts search results by port order within a host" {
        Mock -ModuleName DeviceInsightsModule -CommandName 'FilterStateModule\Get-SelectedLocation' {
            [pscustomobject]@{ Site = 'All Sites'; Zone = 'All Zones'; Building = $null; Room = $null }
        }
        $global:AllInterfaces = [System.Collections.Generic.List[object]]::new()
        $global:AllInterfaces.Add([pscustomobject]@{ Hostname = 'SITE1-Z1-SW1'; Status = 'up'; AuthState = 'authorized'; Port = 'E 1/1/10'; Name = 'Port10' }) | Out-Null
        $global:AllInterfaces.Add([pscustomobject]@{ Hostname = 'SITE1-Z1-SW1'; Status = 'up'; AuthState = 'authorized'; Port = 'E1/1/2'; Name = 'Port2' }) | Out-Null
        $global:AllInterfaces.Add([pscustomobject]@{ Hostname = 'SITE1-Z1-SW1'; Status = 'up'; AuthState = 'authorized'; Port = 'E 1/1/1'; Name = 'Port1' }) | Out-Null

        $results = DeviceInsightsModule\Update-SearchResults -Term ''

        $results.Count | Should Be 3
        $results[0].Port | Should Be 'E 1/1/1'
        $results[1].Port | Should Be 'E1/1/2'
        $results[2].Port | Should Be 'E 1/1/10'
    }

    It "updates summary counters from the global interface list" {
        Mock -ModuleName DeviceInsightsModule -CommandName 'FilterStateModule\Get-SelectedLocation' {
            [pscustomobject]@{ Site = 'All Sites'; Zone = 'All Zones'; Building = $null; Room = $null }
        }
        $global:DeviceMetadata = @{
            'SITE1-Z1-SW1' = [pscustomobject]@{ Site = 'SITE1'; Zone = 'Z1'; Building = 'B1'; Room = 'R1' }
            'SITE1-Z2-SW2' = [pscustomobject]@{ Site = 'SITE1'; Zone = 'Z2'; Building = 'B2'; Room = 'R2' }
        }
        $global:DeviceInterfaceCache = @{
            'SITE1-Z1-SW1' = @(
                [pscustomobject]@{ Hostname = 'SITE1-Z1-SW1'; Site = 'SITE1'; Building = 'B1'; Room = 'R1'; Status = 'up';   AuthState = 'authorized'; VLAN = '10' }
                [pscustomobject]@{ Hostname = 'SITE1-Z1-SW1'; Site = 'SITE1'; Building = 'B1'; Room = 'R1'; Status = 'down'; AuthState = 'unauthorized'; VLAN = '20' }
            )
            'SITE1-Z2-SW2' = @(
                [pscustomobject]@{ Hostname = 'SITE1-Z2-SW2'; Site = 'SITE1'; Building = 'B2'; Room = 'R2'; Status = 'up'; AuthState = 'authorized'; VLAN = '10' }
            )
        }
        Mock -ModuleName DeviceInsightsModule -CommandName 'DeviceRepositoryModule\Get-InterfaceInfo' { @() }

        $summary = New-SummaryViewStub
        $global:summaryView = $summary.View

        DeviceInsightsModule\Update-Summary

        $summary.Blocks['SummaryDevicesCount'].Text      | Should Be '2'
        $summary.Blocks['SummaryInterfacesCount'].Text   | Should Be '3'
        $summary.Blocks['SummaryDownCount'].Text         | Should Be '1'
        $summary.Blocks['SummaryUnauthorizedCount'].Text | Should Be '1'
        $summary.Blocks['SummaryUniqueVlansCount'].Text  | Should Be '2'
        $summary.Blocks['SummaryExtra'].Text             | Should Match 'Up %: 66\.7%'
    }

    It "generates alert rows highlighting problem ports" {
        Mock -ModuleName DeviceInsightsModule -CommandName 'FilterStateModule\Get-SelectedLocation' {
            [pscustomobject]@{ Site = 'All Sites'; Zone = 'All Zones'; Building = $null; Room = $null }
        }
        $global:AllInterfaces = [System.Collections.Generic.List[object]]::new()
        $global:AllInterfaces.Add([pscustomobject]@{ Hostname = 'SITE4-Z1-SW4'; Site = 'SITE4'; Building = 'B4'; Room = 'R4'; Status = 'down'; Duplex = 'half'; AuthState = 'unauthorized'; Port = 'Gi4'; Name = 'Camera'; VLAN = '30' }) | Out-Null

        $alerts = New-AlertsViewStub
        $global:alertsView = $alerts.View

        DeviceInsightsModule\Update-Alerts

        @($global:AlertsList).Count | Should Be 1
        $global:AlertsList[0].Reason | Should Match 'Port down'
        $global:AlertsList[0].Reason | Should Match 'Half duplex'
        $global:AlertsList[0].Reason | Should Match 'Unauthorized'
        $alerts.Grid.ItemsSource | Should Be $global:AlertsList
    }

    It "sorts alert rows by port order within a host" {
        Mock -ModuleName DeviceInsightsModule -CommandName 'FilterStateModule\Get-SelectedLocation' {
            [pscustomobject]@{ Site = 'All Sites'; Zone = 'All Zones'; Building = $null; Room = $null }
        }
        $global:AllInterfaces = [System.Collections.Generic.List[object]]::new()
        $global:AllInterfaces.Add([pscustomobject]@{ Hostname = 'SITE4-Z1-SW4'; Status = 'down'; Duplex = 'half'; AuthState = 'unauthorized'; Port = 'E 1/1/10'; Name = 'Port10'; VLAN = '30' }) | Out-Null
        $global:AllInterfaces.Add([pscustomobject]@{ Hostname = 'SITE4-Z1-SW4'; Status = 'down'; Duplex = 'half'; AuthState = 'unauthorized'; Port = 'E1/1/2'; Name = 'Port2'; VLAN = '30' }) | Out-Null
        $global:AllInterfaces.Add([pscustomobject]@{ Hostname = 'SITE4-Z1-SW4'; Status = 'down'; Duplex = 'half'; AuthState = 'unauthorized'; Port = 'E 1/1/1'; Name = 'Port1'; VLAN = '30' }) | Out-Null

        DeviceInsightsModule\Update-Alerts

        @($global:AlertsList).Count | Should Be 3
        $global:AlertsList[0].Port | Should Be 'E 1/1/1'
        $global:AlertsList[1].Port | Should Be 'E1/1/2'
        $global:AlertsList[2].Port | Should Be 'E 1/1/10'
    }

    It "refreshes the search grid and primes interface data when empty" {
        Mock -ModuleName DeviceInsightsModule -CommandName 'FilterStateModule\Get-SelectedLocation' {
            [pscustomobject]@{ Site = 'All Sites'; Zone = 'All Zones'; Building = $null; Room = $null }
        }
        $global:SearchGridMockInterface = [pscustomobject]@{ Hostname = 'SITE5-Z1-SW5'; Site = 'SITE5'; Zone = 'Z1'; Building = 'B5'; Room = 'R5'; Status = 'up'; AuthState = 'authorized'; Port = 'Gi5'; Name = 'Sensor' }
        Mock -ModuleName DeviceInsightsModule -CommandName 'ViewStateService\Get-InterfacesForContext' {
            param($Site, $ZoneSelection, $ZoneToLoad, $Building, $Room)
            $list = [System.Collections.Generic.List[object]]::new()
            $list.Add($global:SearchGridMockInterface) | Out-Null
            $global:AllInterfaces = $list
            return $list
        }

        $stub = New-SearchWindowStub -StatusSelection 'All' -AuthSelection 'All' -SearchText 'Gi5'
        $global:window = $stub.Window

        DeviceInsightsModule\Update-SearchGrid

        Assert-MockCalled 'ViewStateService\Get-InterfacesForContext' -ModuleName DeviceInsightsModule -Times 1
        (ViewStateService\Get-SequenceCount -Value $stub.Grid.ItemsSource) | Should Be 1
        $stub.Grid.ItemsSource[0].Hostname | Should Be 'SITE5-Z1-SW5'
        Remove-Variable -Name SearchGridMockInterface -Scope Global -ErrorAction SilentlyContinue
    }
}
