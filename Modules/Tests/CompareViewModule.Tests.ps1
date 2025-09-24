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
        $modulePath = Join-Path (Split-Path $PSCommandPath) "..\CompareViewModule.psm1"
        Import-Module (Resolve-Path $modulePath) -Force
    }

    AfterAll {
        Remove-Module CompareViewModule -Force
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
    }

    It "Show-CurrentComparison populates compare view when rows are available" {
        $row1 = [pscustomobject]@{ ToolTip = 'A'; PortColor = 'Green' }
        $row2 = [pscustomobject]@{ ToolTip = 'B'; PortColor = 'Blue' }

        Mock -ModuleName CompareViewModule -CommandName Get-GridRowFor {
            param($Hostname, $Port)
            switch ("$Hostname|$Port") {
                'sw1|Gi1' { return $row1 }
                'sw2|Gi2' { return $row2 }
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

        Mock -ModuleName CompareViewModule -CommandName Get-GridRowFor {
            param($Hostname, $Port)
            if ($Hostname -eq 'sw1') { return $row1 }
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
}
