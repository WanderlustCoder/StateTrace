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
