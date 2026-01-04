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
            $rows = @()
            for ($i = 1; $i -le $Count; $i++) {
                $rows += [pscustomobject]@{
                    TargetPort = ("Gi1/0/{0}" -f $i)
                }
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
}
