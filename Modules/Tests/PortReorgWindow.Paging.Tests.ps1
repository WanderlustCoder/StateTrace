Set-StrictMode -Version Latest

Describe 'Port Reorg paging controls' {
    It 'defines paging view controls in PortReorgWindow.xaml' {
        $xamlPath = Join-Path (Split-Path $PSScriptRoot -Parent) '..\\Views\\PortReorgWindow.xaml'
        $resolved = (Resolve-Path -LiteralPath $xamlPath).Path
        $content = Get-Content -LiteralPath $resolved -Raw

        $requiredNames = @(
            'ReorgPagedViewCheckBox',
            'ReorgPagePrevButton',
            'ReorgPageComboBox',
            'ReorgPageNextButton',
            'ReorgPageInfoText'
        )

        foreach ($name in $requiredNames) {
            $needle = [regex]::Escape(('Name="{0}"' -f $name))
            $content | Should Match $needle
        }
    }
}

# LANDMARK: ST-D-011 paging tests
Describe 'Port Reorg paging slices' {
    BeforeAll {
        $modulePath = Join-Path (Split-Path $PSCommandPath) '..\\PortReorgViewModule.psm1'
        Import-Module $modulePath -Force
        $script:portReorgViewModule = Get-Module PortReorgViewModule
        $script:makeRows = {
            param([int]$Count)
            $rows = [System.Collections.Generic.List[object]]::new()
            for ($i = 1; $i -le $Count; $i++) {
                [void]$rows.Add([pscustomobject]@{
                    TargetPort = ("Gi1/0/{0}" -f $i)
                })
            }
            return $rows
        }
    }

    It 'computes 24-port paging as two 12-port pages' {
        $rows = & $script:makeRows 24
        $result = & $script:portReorgViewModule { param($r,$size,$page) Get-PortReorgPageSlice -OrderedRows $r -PageSize $size -PageNumber $page } $rows 12 1
        $result.PageCount | Should Be 2
        $result.VisibleRows.Count | Should Be 12
        $result.StartIndex | Should Be 0
        $result.EndIndex | Should Be 11
    }

    It 'returns the final page for 48 ports' {
        $rows = & $script:makeRows 48
        $result = & $script:portReorgViewModule { param($r,$size,$page) Get-PortReorgPageSlice -OrderedRows $r -PageSize $size -PageNumber $page } $rows 12 4
        $result.PageCount | Should Be 4
        $result.StartIndex | Should Be 36
        $result.EndIndex | Should Be 47
    }

    It 'clamps page numbers beyond 96-port range' {
        $rows = & $script:makeRows 96
        $result = & $script:portReorgViewModule { param($r,$size,$page) Get-PortReorgPageSlice -OrderedRows $r -PageSize $size -PageNumber $page } $rows 12 9
        $result.PageCount | Should Be 8
        $result.PageNumber | Should Be 8
        $result.VisibleRows.Count | Should Be 12
        $result.VisibleRows[0].TargetPort | Should Be $rows[84].TargetPort
    }

    # ST-D-012: Custom page size tests
    It 'handles custom page size of 24' {
        $rows = & $script:makeRows 48
        $result = & $script:portReorgViewModule { param($r,$size,$page) Get-PortReorgPageSlice -OrderedRows $r -PageSize $size -PageNumber $page } $rows 24 1
        $result.PageCount | Should Be 2
        $result.VisibleRows.Count | Should Be 24
        $result.StartIndex | Should Be 0
        $result.EndIndex | Should Be 23
    }

    It 'handles custom page size of 48' {
        $rows = & $script:makeRows 96
        $result = & $script:portReorgViewModule { param($r,$size,$page) Get-PortReorgPageSlice -OrderedRows $r -PageSize $size -PageNumber $page } $rows 48 2
        $result.PageCount | Should Be 2
        $result.PageNumber | Should Be 2
        $result.VisibleRows.Count | Should Be 48
        $result.StartIndex | Should Be 48
        $result.EndIndex | Should Be 95
    }
}

# ST-D-012: Module boundary detection tests
Describe 'Port module boundary detection' -Tag 'PortReorg' {
    BeforeAll {
        $modulePath = Join-Path (Split-Path $PSCommandPath) '..\\PortReorgViewModule.psm1'
        Import-Module $modulePath -Force
        $script:portReorgViewModule = Get-Module PortReorgViewModule
        $script:getGroup = {
            param([string]$Port)
            & $script:portReorgViewModule { param($p) script:Get-PortModuleGroup -Port $p } $Port
        }
    }

    It 'extracts module group from Gi1/0/x ports' {
        & $script:getGroup 'Gi1/0/1' | Should Be 'Gi1/0'
        & $script:getGroup 'Gi1/0/12' | Should Be 'Gi1/0'
        & $script:getGroup 'Gi1/0/48' | Should Be 'Gi1/0'
    }

    It 'extracts module group from Gi2/0/x ports' {
        & $script:getGroup 'Gi2/0/1' | Should Be 'Gi2/0'
    }

    It 'extracts module group from Te1/0/x ports' {
        & $script:getGroup 'Te1/0/1' | Should Be 'Te1/0'
        & $script:getGroup 'Te1/0/4' | Should Be 'Te1/0'
    }

    It 'extracts module group from Ethernet1/x ports' {
        & $script:getGroup 'Ethernet1/1' | Should Be 'Ethernet1/'
        & $script:getGroup 'Ethernet1/48' | Should Be 'Ethernet1/'
    }

    It 'returns empty for non-matching patterns' {
        & $script:getGroup 'eth0' | Should BeNullOrEmpty
        # Empty string throws validation error, so we test with a whitespace-only string
        & $script:getGroup ' ' | Should BeNullOrEmpty
    }
}

# ST-D-012: Enhanced XAML controls tests
Describe 'Port Reorg enhanced controls' -Tag 'PortReorg' {
    BeforeAll {
        $xamlPath = Join-Path (Split-Path $PSScriptRoot -Parent) '..\\Views\\PortReorgWindow.xaml'
        $script:xamlContent = Get-Content -LiteralPath (Resolve-Path $xamlPath).Path -Raw
    }

    It 'defines undo/redo buttons' {
        $script:xamlContent | Should Match 'Name="ReorgUndoButton"'
        $script:xamlContent | Should Match 'Name="ReorgRedoButton"'
    }

    It 'defines page size box' {
        $script:xamlContent | Should Match 'Name="ReorgPageSizeBox"'
    }

    It 'defines quick jump box' {
        $script:xamlContent | Should Match 'Name="ReorgQuickJumpBox"'
    }

    It 'defines search controls' {
        $script:xamlContent | Should Match 'Name="ReorgSearchBox"'
        $script:xamlContent | Should Match 'Name="ReorgSearchClearButton"'
    }

    It 'defines batch operation buttons' {
        $script:xamlContent | Should Match 'Name="ReorgSelectPageButton"'
        $script:xamlContent | Should Match 'Name="ReorgClearPageButton"'
    }

    It 'defines context menu items' {
        $script:xamlContent | Should Match 'Name="ReorgMoveToMenuItem"'
        $script:xamlContent | Should Match 'Name="ReorgClearLabelMenuItem"'
        $script:xamlContent | Should Match 'Name="ReorgSwapLabelsMenuItem"'
    }

    It 'defines row style with module boundary trigger' {
        $script:xamlContent | Should Match 'IsModuleBoundary'
        $script:xamlContent | Should Match 'DataGrid.RowStyle'
    }

    It 'defines row style with search match trigger' {
        $script:xamlContent | Should Match 'IsSearchMatch'
    }
}
