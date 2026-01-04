Set-StrictMode -Version Latest

function Set-CompareModuleVar {
    param([string]$Name, $Value)
    $module = Get-Module CompareViewModule -ErrorAction Stop
    $module.SessionState.PSVariable.Set($Name, $Value)
}

function Get-CompareModuleVar {
    param([string]$Name)
    $module = Get-Module CompareViewModule -ErrorAction Stop
    ($module.SessionState.PSVariable.Get($Name)).Value
}

function New-DropdownStub {
    param([string]$SelectedItem)
    $obj = [pscustomobject]@{
        SelectedItem = $SelectedItem
        ItemsSource  = $null
    }
    foreach ($name in 'Add_SelectionChanged','Add_LostFocus','Add_KeyDown','Add_DropDownOpened') {
        if (-not ($obj.PSObject.Methods.Name -contains $name)) {
            Add-Member -InputObject $obj -MemberType ScriptMethod -Name $name -Value { param($handler) } -Force
        }
    }
    return $obj
}

function New-TextBlockStub {
    [pscustomobject]@{
        Text       = $null
        Foreground = $null
    }
}

Describe "CompareViewModule compare workflow" {
    BeforeAll {
        [void][System.Reflection.Assembly]::LoadWithPartialName('PresentationFramework')
        $moduleRoot = Split-Path $PSCommandPath
        Import-Module (Resolve-Path (Join-Path $moduleRoot "..\TelemetryModule.psm1")) -Force
        Import-Module (Resolve-Path (Join-Path $moduleRoot "..\FilterStateModule.psm1")) -Force
        Import-Module (Resolve-Path (Join-Path $moduleRoot "..\ViewStateService.psm1")) -Force
        Import-Module (Resolve-Path (Join-Path $moduleRoot '..\InterfaceModule.psm1')) -Force
        Import-Module (Resolve-Path (Join-Path $moduleRoot "..\CompareViewModule.psm1")) -Force
    }

    AfterAll {
        foreach ($name in 'CompareViewModule','ViewStateService','FilterStateModule','InterfaceModule','TelemetryModule','InterfaceCommon') {
            if (Get-Module $name) { Remove-Module $name -Force }
        }
    }

    BeforeEach {
        Set-CompareModuleVar windowRef $null
        Set-CompareModuleVar compareView ([pscustomobject]@{})
        Set-CompareModuleVar switch1Dropdown (New-DropdownStub 'sw1')
        Set-CompareModuleVar port1Dropdown   (New-DropdownStub 'Gi1')
        Set-CompareModuleVar switch2Dropdown (New-DropdownStub 'sw2')
        Set-CompareModuleVar port2Dropdown   (New-DropdownStub 'Gi2')
        Set-CompareModuleVar config1Box (New-TextBlockStub)
        Set-CompareModuleVar config2Box (New-TextBlockStub)
        Set-CompareModuleVar diff1Box   (New-TextBlockStub)
        Set-CompareModuleVar diff2Box   (New-TextBlockStub)
        Set-CompareModuleVar auth1Text  (New-TextBlockStub)
        Set-CompareModuleVar auth2Text  (New-TextBlockStub)
        Set-CompareModuleVar lastCompareColors (@{})
        Set-CompareModuleVar CompareThemeHandlerRegistered $false
        Set-CompareModuleVar lastWiredViewId 0
        Set-CompareModuleVar closeWiredViewId 0
        Set-CompareModuleVar LastCompareHostList $null
        Set-CompareModuleVar testRow1 $null
        Set-CompareModuleVar testRow2 $null
    }

    It "Show-CurrentComparison populates compare view when rows are available" {
        $row1 = [pscustomobject]@{ ToolTip = 'A'; PortColor = 'Green' }
        $row2 = [pscustomobject]@{ ToolTip = 'B'; PortColor = 'Blue' }
        Set-CompareModuleVar testRow1 $row1
        Set-CompareModuleVar testRow2 $row2

        Mock -ModuleName CompareViewModule -CommandName Get-GridRowFor {
            param($Hostname, $Port)
            switch ("$Hostname|$Port") {
                'sw1|Gi1' { return $script:testRow1 }
                'sw2|Gi2' { return $script:testRow2 }
                default   { return $null }
            }
        }
        Mock -ModuleName CompareViewModule -CommandName Get-ThemeBrushForPortColor { param($ColorName) return $ColorName }
        Mock -ModuleName CompareViewModule -CommandName Set-CompareFromRows {}

        CompareViewModule\Show-CurrentComparison

        Assert-MockCalled Get-GridRowFor -ModuleName CompareViewModule -Times 2
        Assert-MockCalled Set-CompareFromRows -ModuleName CompareViewModule -Times 1 -ParameterFilter { $Row1 -eq $row1 -and $Row2 -eq $row2 }
    }

    It "Show-CurrentComparison handles missing rows by supplying placeholders" {
        $row1 = [pscustomobject]@{ ToolTip = 'A'; PortColor = $null }
        Set-CompareModuleVar testRow1 $row1

        Mock -ModuleName CompareViewModule -CommandName Get-GridRowFor {
            param($Hostname, $Port)
            if ($Hostname -eq 'sw1') { return $script:testRow1 }
            return $null
        }
        Mock -ModuleName CompareViewModule -CommandName Get-ThemeBrushForPortColor { param($ColorName) return $ColorName }

        CompareViewModule\Show-CurrentComparison

        $config2 = (Get-CompareModuleVar config2Box).Text
        $auth2   = (Get-CompareModuleVar auth2Text).Text
        $diff1   = (Get-CompareModuleVar diff1Box).Text
        $diff2   = (Get-CompareModuleVar diff2Box).Text

        $config2 | Should BeNullOrEmpty
        $auth2   | Should BeNullOrEmpty
        $diff1   | Should BeNullOrEmpty
        $diff2   | Should BeNullOrEmpty
    }

    # LANDMARK: Compare view telemetry tests - DiffUsageRate emission
    Context "DiffUsageRate telemetry" {
        It "emits DiffUsageRate telemetry when comparison executes" {
            $row1 = [pscustomobject]@{ ToolTip = 'A'; PortColor = 'Green'; Vrf = 'default' }
            $row2 = [pscustomobject]@{ ToolTip = 'B'; PortColor = 'Blue' }
            Set-CompareModuleVar testRow1 $row1
            Set-CompareModuleVar testRow2 $row2

            Mock -ModuleName CompareViewModule -CommandName Get-GridRowFor {
                param($Hostname, $Port)
                switch ("$Hostname|$Port") {
                    'sw1|Gi1' { return $script:testRow1 }
                    'sw2|Gi2' { return $script:testRow2 }
                    default   { return $null }
                }
            }
            Mock -ModuleName CompareViewModule -CommandName Set-CompareFromRows {}
            $global:CompareViewTelemetryEvents = @()
            Set-CompareModuleVar CompareTelemetryCommandOverride {
                param($Name, $Payload)
                $global:CompareViewTelemetryEvents += [pscustomobject]@{ Name = $Name; Payload = $Payload }
            }

            CompareViewModule\Show-CurrentComparison

            $event = $global:CompareViewTelemetryEvents | Where-Object { $_.Name -eq 'DiffUsageRate' } | Select-Object -Last 1
            $event | Should Not BeNullOrEmpty
            $event.Payload.Source | Should Be 'CompareView'
            $event.Payload.Status | Should Be 'Executed'
            $event.Payload.UsageNumerator | Should Be 1
            $event.Payload.UsageDenominator | Should Be 1
            $event.Payload.Hostname | Should Be 'sw1'
            $event.Payload.Hostname2 | Should Be 'sw2'
            $event.Payload.Port1 | Should Be 'Gi1'
            $event.Payload.Port2 | Should Be 'Gi2'
            $event.Payload.Site | Should Be 'sw1'
            $event.Payload.Vrf | Should Be 'default'
            $event.Payload.Timestamp | Should Not BeNullOrEmpty
            Remove-Variable -Scope Global -Name CompareViewTelemetryEvents -ErrorAction SilentlyContinue
            Set-CompareModuleVar CompareTelemetryCommandOverride $null
        }

        It "does not emit DiffUsageRate telemetry when comparison cannot run" {
            Set-CompareModuleVar port1Dropdown (New-DropdownStub '')

            $global:CompareViewTelemetryEvents = @()
            Set-CompareModuleVar CompareTelemetryCommandOverride {
                param($Name, $Payload)
                $global:CompareViewTelemetryEvents += [pscustomobject]@{ Name = $Name; Payload = $Payload }
            }
            CompareViewModule\Show-CurrentComparison

            @($global:CompareViewTelemetryEvents | Where-Object { $_.Name -eq 'DiffUsageRate' }).Count | Should Be 0
            Remove-Variable -Scope Global -Name CompareViewTelemetryEvents -ErrorAction SilentlyContinue
            Set-CompareModuleVar CompareTelemetryCommandOverride $null
        }
    }

    # LANDMARK: Compare view telemetry tests - DiffCompareDurationMs emission
    Context "DiffCompareDurationMs telemetry" {
        It "emits DiffCompareDurationMs telemetry when comparison executes" {
            $row1 = [pscustomobject]@{ ToolTip = 'A'; PortColor = 'Green'; Vrf = 'default' }
            $row2 = [pscustomobject]@{ ToolTip = 'B'; PortColor = 'Blue' }
            Set-CompareModuleVar testRow1 $row1
            Set-CompareModuleVar testRow2 $row2

            Mock -ModuleName CompareViewModule -CommandName Get-GridRowFor {
                param($Hostname, $Port)
                switch ("$Hostname|$Port") {
                    'sw1|Gi1' { return $script:testRow1 }
                    'sw2|Gi2' { return $script:testRow2 }
                    default   { return $null }
                }
            }
            Mock -ModuleName CompareViewModule -CommandName Set-CompareFromRows {}
            $global:CompareViewTelemetryEvents = @()
            Set-CompareModuleVar CompareTelemetryCommandOverride {
                param($Name, $Payload)
                $global:CompareViewTelemetryEvents += [pscustomobject]@{ Name = $Name; Payload = $Payload }
            }

            CompareViewModule\Show-CurrentComparison

            $event = $global:CompareViewTelemetryEvents | Where-Object { $_.Name -eq 'DiffCompareDurationMs' } | Select-Object -Last 1
            $event | Should Not BeNullOrEmpty
            $event.Payload.Source | Should Be 'CompareView'
            $event.Payload.Status | Should Be 'Executed'
            $event.Payload.Hostname | Should Be 'sw1'
            $event.Payload.Hostname2 | Should Be 'sw2'
            $event.Payload.Port1 | Should Be 'Gi1'
            $event.Payload.Port2 | Should Be 'Gi2'
            $event.Payload.Site | Should Be 'sw1'
            $event.Payload.Vrf | Should Be 'default'
            $event.Payload.TimestampUtc | Should Not BeNullOrEmpty
            ($event.Payload.DurationMs -ge 0) | Should Be $true
            ($event.Payload.DurationMs -is [int]) | Should Be $true
            Remove-Variable -Scope Global -Name CompareViewTelemetryEvents -ErrorAction SilentlyContinue
            Set-CompareModuleVar CompareTelemetryCommandOverride $null
        }

        It "emits DiffCompareDurationMs telemetry with Failed status when comparison throws" {
            $row1 = [pscustomobject]@{ ToolTip = 'A'; PortColor = 'Green' }
            $row2 = [pscustomobject]@{ ToolTip = 'B'; PortColor = 'Blue' }
            Set-CompareModuleVar testRow1 $row1
            Set-CompareModuleVar testRow2 $row2

            Mock -ModuleName CompareViewModule -CommandName Get-GridRowFor {
                param($Hostname, $Port)
                switch ("$Hostname|$Port") {
                    'sw1|Gi1' { return $script:testRow1 }
                    'sw2|Gi2' { return $script:testRow2 }
                    default   { return $null }
                }
            }
            Mock -ModuleName CompareViewModule -CommandName Set-CompareFromRows { throw 'Compare failed' }
            $global:CompareViewTelemetryEvents = @()
            Set-CompareModuleVar CompareTelemetryCommandOverride {
                param($Name, $Payload)
                $global:CompareViewTelemetryEvents += [pscustomobject]@{ Name = $Name; Payload = $Payload }
            }

            CompareViewModule\Show-CurrentComparison

            $event = $global:CompareViewTelemetryEvents | Where-Object { $_.Name -eq 'DiffCompareDurationMs' } | Select-Object -Last 1
            $event | Should Not BeNullOrEmpty
            $event.Payload.Source | Should Be 'CompareView'
            $event.Payload.Status | Should Be 'Failed'
            $event.Payload.TimestampUtc | Should Not BeNullOrEmpty
            ($event.Payload.DurationMs -ge 0) | Should Be $true
            Remove-Variable -Scope Global -Name CompareViewTelemetryEvents -ErrorAction SilentlyContinue
            Set-CompareModuleVar CompareTelemetryCommandOverride $null
        }
    }

    # LANDMARK: Compare view telemetry tests - DiffCompareResultCounts emission
    Context "DiffCompareResultCounts telemetry" {
        It "emits DiffCompareResultCounts telemetry with deterministic counts when comparison executes" {
            $row1 = [pscustomobject]@{ ToolTip = "line1`nline2`nline3"; PortColor = 'Green'; Vrf = 'default' }
            $row2 = [pscustomobject]@{ ToolTip = "line2`nline3`nline4"; PortColor = 'Blue' }
            Set-CompareModuleVar testRow1 $row1
            Set-CompareModuleVar testRow2 $row2

            Mock -ModuleName CompareViewModule -CommandName Get-GridRowFor {
                param($Hostname, $Port)
                switch ("$Hostname|$Port") {
                    'sw1|Gi1' { return $script:testRow1 }
                    'sw2|Gi2' { return $script:testRow2 }
                    default   { return $null }
                }
            }
            Mock -ModuleName CompareViewModule -CommandName Set-CompareFromRows {}
            $global:CompareViewTelemetryEvents = @()
            Set-CompareModuleVar CompareTelemetryCommandOverride {
                param($Name, $Payload)
                $global:CompareViewTelemetryEvents += [pscustomobject]@{ Name = $Name; Payload = $Payload }
            }

            CompareViewModule\Show-CurrentComparison

            $event = $global:CompareViewTelemetryEvents | Where-Object { $_.Name -eq 'DiffCompareResultCounts' } | Select-Object -Last 1
            $event | Should Not BeNullOrEmpty
            $event.Payload.Source | Should Be 'CompareView'
            $event.Payload.Status | Should Be 'Executed'
            $event.Payload.TotalCount | Should Be 4
            $event.Payload.AddedCount | Should Be 1
            $event.Payload.RemovedCount | Should Be 1
            $event.Payload.ChangedCount | Should Be 0
            $event.Payload.UnchangedCount | Should Be 2
            $event.Payload.Hostname | Should Be 'sw1'
            $event.Payload.Hostname2 | Should Be 'sw2'
            $event.Payload.Port1 | Should Be 'Gi1'
            $event.Payload.Port2 | Should Be 'Gi2'
            $event.Payload.Site | Should Be 'sw1'
            $event.Payload.Vrf | Should Be 'default'
            $event.Payload.TimestampUtc | Should Not BeNullOrEmpty
            ($event.Payload.TotalCount -is [int]) | Should Be $true
            Remove-Variable -Scope Global -Name CompareViewTelemetryEvents -ErrorAction SilentlyContinue
            Set-CompareModuleVar CompareTelemetryCommandOverride $null
        }

        It "emits DiffCompareResultCounts telemetry with Failed status when comparison throws" {
            $row1 = [pscustomobject]@{ ToolTip = "line1`nline2"; PortColor = 'Green' }
            $row2 = [pscustomobject]@{ ToolTip = "line2`nline3"; PortColor = 'Blue' }
            Set-CompareModuleVar testRow1 $row1
            Set-CompareModuleVar testRow2 $row2

            Mock -ModuleName CompareViewModule -CommandName Get-GridRowFor {
                param($Hostname, $Port)
                switch ("$Hostname|$Port") {
                    'sw1|Gi1' { return $script:testRow1 }
                    'sw2|Gi2' { return $script:testRow2 }
                    default   { return $null }
                }
            }
            Mock -ModuleName CompareViewModule -CommandName Set-CompareFromRows { throw 'Compare failed' }
            $global:CompareViewTelemetryEvents = @()
            Set-CompareModuleVar CompareTelemetryCommandOverride {
                param($Name, $Payload)
                $global:CompareViewTelemetryEvents += [pscustomobject]@{ Name = $Name; Payload = $Payload }
            }

            CompareViewModule\Show-CurrentComparison

            $event = $global:CompareViewTelemetryEvents | Where-Object { $_.Name -eq 'DiffCompareResultCounts' } | Select-Object -Last 1
            $event | Should Not BeNullOrEmpty
            $event.Payload.Source | Should Be 'CompareView'
            $event.Payload.Status | Should Be 'Failed'
            $event.Payload.TotalCount | Should Be 0
            $event.Payload.AddedCount | Should Be 0
            $event.Payload.RemovedCount | Should Be 0
            $event.Payload.ChangedCount | Should Be 0
            $event.Payload.UnchangedCount | Should Be 0
            $event.Payload.TimestampUtc | Should Not BeNullOrEmpty
            ($event.Payload.DurationMs -ge 0) | Should Be $true
            ($event.Payload.DurationMs -is [int]) | Should Be $true
            Remove-Variable -Scope Global -Name CompareViewTelemetryEvents -ErrorAction SilentlyContinue
            Set-CompareModuleVar CompareTelemetryCommandOverride $null
        }

        It "does not emit DiffCompareResultCounts telemetry when comparison cannot run" {
            Set-CompareModuleVar port1Dropdown (New-DropdownStub '')

            $global:CompareViewTelemetryEvents = @()
            Set-CompareModuleVar CompareTelemetryCommandOverride {
                param($Name, $Payload)
                $global:CompareViewTelemetryEvents += [pscustomobject]@{ Name = $Name; Payload = $Payload }
            }
            CompareViewModule\Show-CurrentComparison

            @($global:CompareViewTelemetryEvents | Where-Object { $_.Name -eq 'DiffCompareResultCounts' }).Count | Should Be 0
            Remove-Variable -Scope Global -Name CompareViewTelemetryEvents -ErrorAction SilentlyContinue
            Set-CompareModuleVar CompareTelemetryCommandOverride $null
        }
    }

    It "Set-CompareSelection refreshes host lists and ports" {
        Set-CompareModuleVar windowRef ([System.Windows.Window]::new())

        Mock -ModuleName CompareViewModule -CommandName Resolve-CompareControls { $true }
        Mock -ModuleName CompareViewModule -CommandName Get-CompareHandlers {}
        Mock -ModuleName CompareViewModule -CommandName Get-HostsFromMain { @('sw1','sw2') }
        Mock -ModuleName CompareViewModule -CommandName Set-PortsForCombo {}
        Mock -ModuleName CompareViewModule -CommandName Set-CompareFromRows {}

        $row1 = [pscustomobject]@{ ToolTip = 'A'; PortColor = $null }
        $row2 = [pscustomobject]@{ ToolTip = 'B'; PortColor = $null }

        CompareViewModule\Set-CompareSelection -Switch1 'sw1' -Interface1 'Gi1' -Switch2 'sw2' -Interface2 'Gi2' -Row1 $row1 -Row2 $row2

        $hosts1 = (Get-CompareModuleVar switch1Dropdown).ItemsSource
        $hosts2 = (Get-CompareModuleVar switch2Dropdown).ItemsSource

        Assert-MockCalled Get-HostsFromMain -ModuleName CompareViewModule -Times 1
        $hosts1 | Should BeExactly @('sw1','sw2')
        $hosts2 | Should BeExactly @('sw1','sw2')

        Assert-MockCalled Set-PortsForCombo -ModuleName CompareViewModule -Times 2
        Assert-MockCalled Set-CompareFromRows -ModuleName CompareViewModule -Times 1 -ParameterFilter { $Row1 -eq $row1 -and $Row2 -eq $row2 }
    }

    Context "Get-HostsFromMain" {
        It "returns hosts from ViewStateService snapshots" {
            $hadMetadata = $false
            $previousMetadata = $null
            if (Get-Variable -Name DeviceMetadata -Scope Global -ErrorAction SilentlyContinue) {
                $hadMetadata = $true
                $previousMetadata = $global:DeviceMetadata
            }

            $global:DeviceMetadata = @{
                'SITE1-Z1-SW1' = [pscustomobject]@{ Site = 'SITE1'; Zone = 'Z1'; Building = 'B1'; Room = 'R101' }
                'SITE1-Z2-SW2' = [pscustomobject]@{ Site = 'SITE1'; Zone = 'Z2'; Building = 'B2'; Room = 'R201' }
            }

            Mock -ModuleName CompareViewModule -CommandName 'FilterStateModule\Get-LastLocation' { @{ Site = 'SITE1'; Zone = 'All Zones'; Building = ''; Room = '' } }
            Mock -ModuleName CompareViewModule -CommandName 'FilterStateModule\Get-SelectedLocation' { @{ Site = 'SITE1'; Zone = 'All Zones'; Building = ''; Room = '' } }
            Mock -ModuleName CompareViewModule -CommandName 'ViewStateService\Get-FilterSnapshot' {
                [pscustomobject]@{ Hostnames = @('SITE1-Z1-SW1','SITE1-Z2-SW2'); ZoneToLoad = 'Z1' }
            }
            Mock -ModuleName CompareViewModule -CommandName 'ViewStateService\Get-InterfacesForContext' {
                @([pscustomobject]@{ Hostname = 'SITE1-Z1-SW1' }, [pscustomobject]@{ Hostname = 'SITE1-Z2-SW2' })
            }

            try {
                $hosts = CompareViewModule\Get-HostsFromMain -Window ([System.Windows.Window]::new())

                $hosts | Should BeExactly @('SITE1-Z1-SW1','SITE1-Z2-SW2')

                Assert-MockCalled -ModuleName CompareViewModule -CommandName 'ViewStateService\Get-FilterSnapshot' -Times 1
                Assert-MockCalled -ModuleName CompareViewModule -CommandName 'ViewStateService\Get-InterfacesForContext' -Times 1
            } finally {
                if ($hadMetadata) {
                    $global:DeviceMetadata = $previousMetadata
                } else {
                    Remove-Variable -Scope Global -Name DeviceMetadata -ErrorAction SilentlyContinue
                }
            }
        }
    }

    Context "Get-PortsForHost" {
        It "returns ports using ViewStateService data" {
            Set-CompareModuleVar windowRef ([System.Windows.Window]::new())

            $hadMetadata = $false
            $previousMetadata = $null
            if (Get-Variable -Name DeviceMetadata -Scope Global -ErrorAction SilentlyContinue) {
                $hadMetadata = $true
                $previousMetadata = $global:DeviceMetadata
            }

            $global:DeviceMetadata = @{ 'SITE1-Z1-SW1' = [pscustomobject]@{ Site = 'SITE1'; Zone = 'Z1'; Building = ''; Room = '' } }

            Mock -ModuleName CompareViewModule -CommandName 'FilterStateModule\Get-LastLocation' { @{ Site = 'SITE1'; Zone = 'Z1'; Building = ''; Room = '' } }
            Mock -ModuleName CompareViewModule -CommandName 'FilterStateModule\Get-SelectedLocation' { @{ Site = 'SITE1'; Zone = 'Z1'; Building = ''; Room = '' } }
            Mock -ModuleName CompareViewModule -CommandName 'ViewStateService\Get-FilterSnapshot' {
                [pscustomobject]@{ Hostnames = @('SITE1-Z1-SW1'); ZoneToLoad = 'Z1' }
            }
            Mock -ModuleName CompareViewModule -CommandName 'ViewStateService\Get-InterfacesForContext' {
                @(
                    [pscustomobject]@{ Hostname = 'SITE1-Z1-SW1'; Port = 'Gi2' },
                    [pscustomobject]@{ Hostname = 'SITE1-Z1-SW1'; Port = 'Gi1' },
                    [pscustomobject]@{ Hostname = 'SITE1-Z2-SW2'; Port = 'Gi3' }
                )
            }
            Mock -ModuleName CompareViewModule -CommandName 'InterfaceModule\Get-InterfaceList' { throw 'Should not be called' }
            Mock -ModuleName CompareViewModule -CommandName 'InterfaceModule\Get-InterfaceInfo' { @() }

            try {
                $ports = CompareViewModule\Get-PortsForHost -Hostname 'SITE1-Z1-SW1'
            } finally {
                if ($hadMetadata) {
                    $global:DeviceMetadata = $previousMetadata
                } else {
                    Remove-Variable -Scope Global -Name DeviceMetadata -ErrorAction SilentlyContinue
                }
            }

            $ports | Should BeExactly @('Gi1','Gi2')

            Assert-MockCalled -ModuleName CompareViewModule -CommandName 'ViewStateService\Get-InterfacesForContext' -Times 1
            Assert-MockCalled -ModuleName CompareViewModule -CommandName 'InterfaceModule\Get-InterfaceList' -Times 0
        }

        It "falls back to InterfaceModule when service returns nothing" {
            Set-CompareModuleVar windowRef ([System.Windows.Window]::new())

            $hadMetadata = $false
            $previousMetadata = $null
            if (Get-Variable -Name DeviceMetadata -Scope Global -ErrorAction SilentlyContinue) {
                $hadMetadata = $true
                $previousMetadata = $global:DeviceMetadata
            }

            $global:DeviceMetadata = @{ 'SITE1-Z1-SW1' = [pscustomobject]@{ Site = 'SITE1'; Zone = 'Z1'; Building = ''; Room = '' } }

            Mock -ModuleName CompareViewModule -CommandName 'FilterStateModule\Get-LastLocation' { @{ Site = 'SITE1'; Zone = 'Z1'; Building = ''; Room = '' } }
            Mock -ModuleName CompareViewModule -CommandName 'FilterStateModule\Get-SelectedLocation' { @{ Site = 'SITE1'; Zone = 'Z1'; Building = ''; Room = '' } }
            Mock -ModuleName CompareViewModule -CommandName 'ViewStateService\Get-FilterSnapshot' {
                [pscustomobject]@{ Hostnames = @('SITE1-Z1-SW1'); ZoneToLoad = 'Z1' }
            }
            Mock -ModuleName CompareViewModule -CommandName 'ViewStateService\Get-InterfacesForContext' { @() }
            Mock -ModuleName CompareViewModule -CommandName 'InterfaceModule\Get-InterfaceList' { @('Gi0/2','Gi0/1') }
            Mock -ModuleName CompareViewModule -CommandName 'InterfaceModule\Get-InterfaceInfo' { @() }

            try {
                $ports = CompareViewModule\Get-PortsForHost -Hostname 'SITE1-Z1-SW1'
            } finally {
                if ($hadMetadata) {
                    $global:DeviceMetadata = $previousMetadata
                } else {
                    Remove-Variable -Scope Global -Name DeviceMetadata -ErrorAction SilentlyContinue
                }
            }

            $ports | Should BeExactly @('Gi0/1','Gi0/2')

            Assert-MockCalled -ModuleName CompareViewModule -CommandName 'InterfaceModule\Get-InterfaceList' -Times 1
        }
    }

}
