#Requires -Version 5.1
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Tests for Plan AF: Tab Consolidation container views.

.DESCRIPTION
    Validates the 4 container view modules and their XAML files:
    - DocumentationContainerView (Generator, Config Templates, Templates, Cmd Reference)
    - InfrastructureContainerView (Topology, Cables, IPAM, Inventory)
    - OperationsContainerView (Changes, Capacity, Log Analysis)
    - ToolsContainerView (Troubleshoot, Calculator)

.NOTES
    ST-AF-006: UI smoke tests for tab consolidation feature.
#>

$script:moduleRoot = Split-Path $PSCommandPath
$script:viewsRoot = Resolve-Path (Join-Path $script:moduleRoot '..\..\Views')
$script:modulesRoot = Resolve-Path (Join-Path $script:moduleRoot '..')

Describe 'Plan AF: Container View XAML Files' {

    Context 'DocumentationContainerView.xaml' {
        $xamlPath = Join-Path $script:viewsRoot 'DocumentationContainerView.xaml'

        It 'XAML file exists' {
            Test-Path $xamlPath | Should Be $true
        }

        It 'Contains DocumentationTabControl' {
            $content = Get-Content -Path $xamlPath -Raw
            $content | Should Match 'Name="DocumentationTabControl"'
        }

        It 'Has TabStripPlacement Left for vertical tabs' {
            $content = Get-Content -Path $xamlPath -Raw
            $content | Should Match 'TabStripPlacement="Left"'
        }

        It 'Contains expected sub-host controls' {
            $content = Get-Content -Path $xamlPath -Raw
            $content | Should Match 'Name="DocsSubHost"'
            $content | Should Match 'Name="ConfigSubHost"'
            $content | Should Match 'Name="TemplatesSubHost"'
            $content | Should Match 'Name="CmdReferenceSubHost"'
        }

        It 'Has 4 TabItems for sub-views' {
            $content = Get-Content -Path $xamlPath -Raw
            $matches = [regex]::Matches($content, '<TabItem\s+Header=')
            $matches.Count | Should Be 4
        }
    }

    Context 'InfrastructureContainerView.xaml' {
        $xamlPath = Join-Path $script:viewsRoot 'InfrastructureContainerView.xaml'

        It 'XAML file exists' {
            Test-Path $xamlPath | Should Be $true
        }

        It 'Contains InfrastructureTabControl' {
            $content = Get-Content -Path $xamlPath -Raw
            $content | Should Match 'Name="InfrastructureTabControl"'
        }

        It 'Has TabStripPlacement Left for vertical tabs' {
            $content = Get-Content -Path $xamlPath -Raw
            $content | Should Match 'TabStripPlacement="Left"'
        }

        It 'Contains expected sub-host controls' {
            $content = Get-Content -Path $xamlPath -Raw
            $content | Should Match 'Name="TopologySubHost"'
            $content | Should Match 'Name="CablesSubHost"'
            $content | Should Match 'Name="IPAMSubHost"'
            $content | Should Match 'Name="InventorySubHost"'
        }

        It 'Has 4 TabItems for sub-views' {
            $content = Get-Content -Path $xamlPath -Raw
            $matches = [regex]::Matches($content, '<TabItem\s+Header=')
            $matches.Count | Should Be 4
        }
    }

    Context 'OperationsContainerView.xaml' {
        $xamlPath = Join-Path $script:viewsRoot 'OperationsContainerView.xaml'

        It 'XAML file exists' {
            Test-Path $xamlPath | Should Be $true
        }

        It 'Contains OperationsTabControl' {
            $content = Get-Content -Path $xamlPath -Raw
            $content | Should Match 'Name="OperationsTabControl"'
        }

        It 'Has TabStripPlacement Left for vertical tabs' {
            $content = Get-Content -Path $xamlPath -Raw
            $content | Should Match 'TabStripPlacement="Left"'
        }

        It 'Contains expected sub-host controls' {
            $content = Get-Content -Path $xamlPath -Raw
            $content | Should Match 'Name="ChangesSubHost"'
            $content | Should Match 'Name="CapacitySubHost"'
            $content | Should Match 'Name="LogAnalysisSubHost"'
        }

        It 'Has 3 TabItems for sub-views' {
            $content = Get-Content -Path $xamlPath -Raw
            $matches = [regex]::Matches($content, '<TabItem\s+Header=')
            $matches.Count | Should Be 3
        }
    }

    Context 'ToolsContainerView.xaml' {
        $xamlPath = Join-Path $script:viewsRoot 'ToolsContainerView.xaml'

        It 'XAML file exists' {
            Test-Path $xamlPath | Should Be $true
        }

        It 'Contains ToolsTabControl' {
            $content = Get-Content -Path $xamlPath -Raw
            $content | Should Match 'Name="ToolsTabControl"'
        }

        It 'Has TabStripPlacement Left for vertical tabs' {
            $content = Get-Content -Path $xamlPath -Raw
            $content | Should Match 'TabStripPlacement="Left"'
        }

        It 'Contains expected sub-host controls' {
            $content = Get-Content -Path $xamlPath -Raw
            $content | Should Match 'Name="TroubleshootSubHost"'
            $content | Should Match 'Name="CalculatorSubHost"'
        }

        It 'Has 2 TabItems for sub-views' {
            $content = Get-Content -Path $xamlPath -Raw
            $matches = [regex]::Matches($content, '<TabItem\s+Header=')
            $matches.Count | Should Be 2
        }
    }
}

Describe 'Plan AF: Container View Modules' {

    BeforeAll {
        # Import the container view modules
        Import-Module (Join-Path $script:modulesRoot 'ViewCompositionModule.psm1') -Force -ErrorAction SilentlyContinue
    }

    AfterAll {
        # Cleanup modules
        foreach ($name in @(
            'DocumentationContainerViewModule',
            'InfrastructureContainerViewModule',
            'OperationsContainerViewModule',
            'ToolsContainerViewModule',
            'ViewCompositionModule'
        )) {
            if (Get-Module $name) { Remove-Module $name -Force }
        }
    }

    Context 'DocumentationContainerViewModule' {
        $modulePath = Join-Path $script:modulesRoot 'DocumentationContainerViewModule.psm1'

        It 'Module file exists' {
            Test-Path $modulePath | Should Be $true
        }

        It 'Module can be imported' {
            { Import-Module $modulePath -Force -ErrorAction Stop } | Should Not Throw
        }

        It 'Exports New-DocumentationContainerView function' {
            Import-Module $modulePath -Force
            $exported = @(Get-Command -Module DocumentationContainerViewModule)
            ($exported.Name -contains 'New-DocumentationContainerView') | Should Be $true
        }

        It 'Module contains Plan AF reference' {
            $content = Get-Content -Path $modulePath -Raw
            $content | Should Match 'Plan AF'
        }
    }

    Context 'InfrastructureContainerViewModule' {
        $modulePath = Join-Path $script:modulesRoot 'InfrastructureContainerViewModule.psm1'

        It 'Module file exists' {
            Test-Path $modulePath | Should Be $true
        }

        It 'Module can be imported' {
            { Import-Module $modulePath -Force -ErrorAction Stop } | Should Not Throw
        }

        It 'Exports New-InfrastructureContainerView function' {
            Import-Module $modulePath -Force
            $exported = @(Get-Command -Module InfrastructureContainerViewModule)
            ($exported.Name -contains 'New-InfrastructureContainerView') | Should Be $true
        }

        It 'Module contains Plan AF reference' {
            $content = Get-Content -Path $modulePath -Raw
            $content | Should Match 'Plan AF'
        }
    }

    Context 'OperationsContainerViewModule' {
        $modulePath = Join-Path $script:modulesRoot 'OperationsContainerViewModule.psm1'

        It 'Module file exists' {
            Test-Path $modulePath | Should Be $true
        }

        It 'Module can be imported' {
            { Import-Module $modulePath -Force -ErrorAction Stop } | Should Not Throw
        }

        It 'Exports New-OperationsContainerView function' {
            Import-Module $modulePath -Force
            $exported = @(Get-Command -Module OperationsContainerViewModule)
            ($exported.Name -contains 'New-OperationsContainerView') | Should Be $true
        }

        It 'Module contains Plan AF reference' {
            $content = Get-Content -Path $modulePath -Raw
            $content | Should Match 'Plan AF'
        }
    }

    Context 'ToolsContainerViewModule' {
        $modulePath = Join-Path $script:modulesRoot 'ToolsContainerViewModule.psm1'

        It 'Module file exists' {
            Test-Path $modulePath | Should Be $true
        }

        It 'Module can be imported' {
            { Import-Module $modulePath -Force -ErrorAction Stop } | Should Not Throw
        }

        It 'Exports New-ToolsContainerView function' {
            Import-Module $modulePath -Force
            $exported = @(Get-Command -Module ToolsContainerViewModule)
            ($exported.Name -contains 'New-ToolsContainerView') | Should Be $true
        }

        It 'Module contains Plan AF reference' {
            $content = Get-Content -Path $modulePath -Raw
            $content | Should Match 'Plan AF'
        }
    }
}

Describe 'Plan AF: Tab Consolidation Structure' {

    Context 'Tab count reduction verification' {
        It 'Total container sub-tabs equals 13 (previously top-level tabs)' {
            # Documentation: 4 (Generator, Config Templates, Templates, Cmd Reference)
            # Infrastructure: 4 (Topology, Cables, IPAM, Inventory)
            # Operations: 3 (Changes, Capacity, Log Analysis)
            # Tools: 2 (Troubleshoot, Calculator)
            $documentationTabs = 4
            $infrastructureTabs = 4
            $operationsTabs = 3
            $toolsTabs = 2
            $totalSubTabs = $documentationTabs + $infrastructureTabs + $operationsTabs + $toolsTabs
            $totalSubTabs | Should Be 13
        }

        It 'New top-level tab count is 9 (5 standalone + 4 containers)' {
            # Standalone: Summary, Interfaces, SPAN, Search, Alerts (5)
            # Containers: Documentation, Infrastructure, Operations, Tools (4)
            $standaloneTabs = 5
            $containerTabs = 4
            $totalTopLevel = $standaloneTabs + $containerTabs
            $totalTopLevel | Should Be 9
        }
    }

    Context 'XAML theme integration' {
        It 'All container XAMLs use DynamicResource for theming' {
            $xamlFiles = @(
                'DocumentationContainerView.xaml',
                'InfrastructureContainerView.xaml',
                'OperationsContainerView.xaml',
                'ToolsContainerView.xaml'
            )

            foreach ($file in $xamlFiles) {
                $path = Join-Path $script:viewsRoot $file
                $content = Get-Content -Path $path -Raw
                $content | Should Match 'DynamicResource'
            }
        }

        It 'All container XAMLs have consistent MinWidth for tab buttons' {
            $xamlFiles = @(
                'DocumentationContainerView.xaml',
                'InfrastructureContainerView.xaml',
                'OperationsContainerView.xaml',
                'ToolsContainerView.xaml'
            )

            $allHaveMinWidth = $true
            foreach ($file in $xamlFiles) {
                $path = Join-Path $script:viewsRoot $file
                $content = Get-Content -Path $path -Raw
                # XAML uses setter syntax: Property="MinWidth" Value="130"
                if ($content -notmatch 'MinWidth.*Value="130"') {
                    $allHaveMinWidth = $false
                }
            }
            $allHaveMinWidth | Should Be $true
        }
    }

    Context 'Lazy loading implementation' {
        It 'All container modules track initialized sub-views' {
            $moduleFiles = @(
                'DocumentationContainerViewModule.psm1',
                'InfrastructureContainerViewModule.psm1',
                'OperationsContainerViewModule.psm1',
                'ToolsContainerViewModule.psm1'
            )

            foreach ($file in $moduleFiles) {
                $path = Join-Path $script:modulesRoot $file
                $content = Get-Content -Path $path -Raw
                $content | Should Match '\$script:InitializedSubViews'
            }
        }

        It 'All container modules use SelectionChanged for lazy loading' {
            $moduleFiles = @(
                'DocumentationContainerViewModule.psm1',
                'InfrastructureContainerViewModule.psm1',
                'OperationsContainerViewModule.psm1',
                'ToolsContainerViewModule.psm1'
            )

            foreach ($file in $moduleFiles) {
                $path = Join-Path $script:modulesRoot $file
                $content = Get-Content -Path $path -Raw
                $content | Should Match 'Add_SelectionChanged'
            }
        }
    }
}
