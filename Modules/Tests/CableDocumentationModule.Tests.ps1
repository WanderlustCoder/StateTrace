Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Pester tests for CableDocumentationModule.
#>

$modulePath = Join-Path $PSScriptRoot '..\CableDocumentationModule.psm1'
Import-Module $modulePath -Force

Describe 'CableDocumentationModule' {

    BeforeEach {
        # Create a fresh database for each test
        $script:testDb = CableDocumentationModule\New-CableDatabase
    }

    #region New-CableRun Tests

    Context 'New-CableRun' {

        It 'Creates a cable run with required parameters' {
            $cable = CableDocumentationModule\New-CableRun `
                -SourceType 'Device' `
                -SourceDevice 'SW-01' `
                -SourcePort 'Gi1/0/1' `
                -DestType 'PatchPanel' `
                -DestDevice 'PP-MDF-01' `
                -DestPort '1'

            $cable | Should Not BeNullOrEmpty
            $cable.SourceDevice | Should Be 'SW-01'
            $cable.SourcePort | Should Be 'Gi1/0/1'
            $cable.DestDevice | Should Be 'PP-MDF-01'
            $cable.DestPort | Should Be '1'
            $cable.Status | Should Be 'Active'
            $cable.CableType | Should Be 'Cat6'
        }

        It 'Auto-generates CableID when not provided' {
            $cable = CableDocumentationModule\New-CableRun `
                -SourceType 'Device' `
                -SourceDevice 'SW-01' `
                -SourcePort 'Gi1/0/1' `
                -DestType 'Device' `
                -DestDevice 'SW-02' `
                -DestPort 'Gi1/0/1'

            $cable.CableID | Should Match '^CBL-[A-Z0-9]{8}$'
        }

        It 'Uses provided CableID' {
            $cable = CableDocumentationModule\New-CableRun `
                -CableID 'MDF-001' `
                -SourceType 'Device' `
                -SourceDevice 'SW-01' `
                -SourcePort 'Gi1/0/1' `
                -DestType 'Device' `
                -DestDevice 'SW-02' `
                -DestPort 'Gi1/0/1'

            $cable.CableID | Should Be 'MDF-001'
        }

        It 'Accepts optional parameters' {
            $cable = CableDocumentationModule\New-CableRun `
                -SourceType 'Device' `
                -SourceDevice 'SW-01' `
                -SourcePort 'Gi1/0/1' `
                -DestType 'Device' `
                -DestDevice 'SW-02' `
                -DestPort 'Gi1/0/1' `
                -CableType 'Cat6a' `
                -Length '10ft' `
                -Color 'Blue' `
                -Status 'Reserved' `
                -Notes 'Test cable'

            $cable.CableType | Should Be 'Cat6a'
            $cable.Length | Should Be '10ft'
            $cable.Color | Should Be 'Blue'
            $cable.Status | Should Be 'Reserved'
            $cable.Notes | Should Be 'Test cable'
        }

        It 'Sets CreatedDate and ModifiedDate' {
            $before = Get-Date
            $cable = CableDocumentationModule\New-CableRun `
                -SourceType 'Device' `
                -SourceDevice 'SW-01' `
                -SourcePort 'Gi1/0/1' `
                -DestType 'Device' `
                -DestDevice 'SW-02' `
                -DestPort 'Gi1/0/1'
            $after = Get-Date

            $cable.CreatedDate | Should Not BeNullOrEmpty
            ($cable.CreatedDate -ge $before) | Should Be $true
            ($cable.CreatedDate -le $after) | Should Be $true
        }
    }

    #endregion

    #region New-PatchPanel Tests

    Context 'New-PatchPanel' {

        It 'Creates a patch panel with required parameters' {
            $panel = CableDocumentationModule\New-PatchPanel -PanelName 'MDF-PP-01'

            $panel | Should Not BeNullOrEmpty
            $panel.PanelName | Should Be 'MDF-PP-01'
            $panel.PortCount | Should Be 24
            $panel.PanelType | Should Be 'Copper'
        }

        It 'Auto-generates PanelID when not provided' {
            $panel = CableDocumentationModule\New-PatchPanel -PanelName 'MDF-PP-01'
            $panel.PanelID | Should Match '^PP-[A-Z0-9]{8}$'
        }

        It 'Creates port array matching port count' {
            $panel = CableDocumentationModule\New-PatchPanel -PanelName 'MDF-PP-01' -PortCount 48

            $panel.Ports.Count | Should Be 48
            $panel.Ports[0].PortNumber | Should Be 1
            $panel.Ports[47].PortNumber | Should Be 48
        }

        It 'Initializes ports with Empty status' {
            $panel = CableDocumentationModule\New-PatchPanel -PanelName 'MDF-PP-01'

            $panel.Ports[0].Status | Should Be 'Empty'
            $panel.Ports[0].CableID | Should BeNullOrEmpty
        }

        It 'Accepts optional location parameters' {
            $panel = CableDocumentationModule\New-PatchPanel `
                -PanelName 'MDF-PP-01' `
                -Location 'MDF Room' `
                -RackID 'Rack-A' `
                -RackU '42'

            $panel.Location | Should Be 'MDF Room'
            $panel.RackID | Should Be 'Rack-A'
            $panel.RackU | Should Be '42'
        }
    }

    #endregion

    #region Cable Database Operations Tests

    Context 'Add-CableRun' {

        It 'Adds a cable to the database' {
            $cable = CableDocumentationModule\New-CableRun `
                -CableID 'TEST-001' `
                -SourceType 'Device' `
                -SourceDevice 'SW-01' `
                -SourcePort 'Gi1/0/1' `
                -DestType 'Device' `
                -DestDevice 'SW-02' `
                -DestPort 'Gi1/0/1'

            $result = CableDocumentationModule\Add-CableRun -Cable $cable -Database $script:testDb

            $result | Should Not BeNullOrEmpty
            $script:testDb.Cables.Count | Should Be 1
        }

        It 'Rejects duplicate CableID' {
            $cable1 = CableDocumentationModule\New-CableRun `
                -CableID 'TEST-001' `
                -SourceType 'Device' `
                -SourceDevice 'SW-01' `
                -SourcePort 'Gi1/0/1' `
                -DestType 'Device' `
                -DestDevice 'SW-02' `
                -DestPort 'Gi1/0/1'

            $cable2 = CableDocumentationModule\New-CableRun `
                -CableID 'TEST-001' `
                -SourceType 'Device' `
                -SourceDevice 'SW-03' `
                -SourcePort 'Gi1/0/1' `
                -DestType 'Device' `
                -DestDevice 'SW-04' `
                -DestPort 'Gi1/0/1'

            CableDocumentationModule\Add-CableRun -Cable $cable1 -Database $script:testDb
            $result = CableDocumentationModule\Add-CableRun -Cable $cable2 -Database $script:testDb -WarningAction SilentlyContinue

            $result | Should BeNullOrEmpty
            $script:testDb.Cables.Count | Should Be 1
        }
    }

    Context 'Get-CableRun' {

        It 'Returns all cables when no filter' {
            $cable1 = CableDocumentationModule\New-CableRun `
                -CableID 'TEST-001' `
                -SourceType 'Device' `
                -SourceDevice 'SW-01' `
                -SourcePort 'Gi1/0/1' `
                -DestType 'Device' `
                -DestDevice 'SW-02' `
                -DestPort 'Gi1/0/1' `
                -CableType 'Cat6' `
                -Status 'Active'

            $cable2 = CableDocumentationModule\New-CableRun `
                -CableID 'TEST-002' `
                -SourceType 'Device' `
                -SourceDevice 'SW-01' `
                -SourcePort 'Gi1/0/2' `
                -DestType 'PatchPanel' `
                -DestDevice 'PP-01' `
                -DestPort '1' `
                -CableType 'Cat6a' `
                -Status 'Reserved'

            CableDocumentationModule\Add-CableRun -Cable $cable1 -Database $script:testDb
            CableDocumentationModule\Add-CableRun -Cable $cable2 -Database $script:testDb

            $results = @(CableDocumentationModule\Get-CableRun -Database $script:testDb)
            $results.Count | Should Be 2
        }

        It 'Filters by CableID' {
            $cable1 = CableDocumentationModule\New-CableRun `
                -CableID 'TEST-001' `
                -SourceType 'Device' `
                -SourceDevice 'SW-01' `
                -SourcePort 'Gi1/0/1' `
                -DestType 'Device' `
                -DestDevice 'SW-02' `
                -DestPort 'Gi1/0/1'

            $cable2 = CableDocumentationModule\New-CableRun `
                -CableID 'TEST-002' `
                -SourceType 'Device' `
                -SourceDevice 'SW-01' `
                -SourcePort 'Gi1/0/2' `
                -DestType 'Device' `
                -DestDevice 'SW-03' `
                -DestPort 'Gi1/0/1'

            CableDocumentationModule\Add-CableRun -Cable $cable1 -Database $script:testDb
            CableDocumentationModule\Add-CableRun -Cable $cable2 -Database $script:testDb

            $results = @(CableDocumentationModule\Get-CableRun -CableID 'TEST-001' -Database $script:testDb)
            $results.Count | Should Be 1
            $results[0].CableID | Should Be 'TEST-001'
        }

        It 'Filters by Device' {
            $cable1 = CableDocumentationModule\New-CableRun `
                -CableID 'TEST-001' `
                -SourceType 'Device' `
                -SourceDevice 'SW-01' `
                -SourcePort 'Gi1/0/1' `
                -DestType 'Device' `
                -DestDevice 'SW-02' `
                -DestPort 'Gi1/0/1'

            $cable2 = CableDocumentationModule\New-CableRun `
                -CableID 'TEST-002' `
                -SourceType 'Device' `
                -SourceDevice 'SW-01' `
                -SourcePort 'Gi1/0/2' `
                -DestType 'Device' `
                -DestDevice 'SW-03' `
                -DestPort 'Gi1/0/1'

            CableDocumentationModule\Add-CableRun -Cable $cable1 -Database $script:testDb
            CableDocumentationModule\Add-CableRun -Cable $cable2 -Database $script:testDb

            $results = @(CableDocumentationModule\Get-CableRun -Device 'SW-01' -Database $script:testDb)
            $results.Count | Should Be 2
        }

        It 'Filters by Status' {
            $cable1 = CableDocumentationModule\New-CableRun `
                -CableID 'TEST-001' `
                -SourceType 'Device' `
                -SourceDevice 'SW-01' `
                -SourcePort 'Gi1/0/1' `
                -DestType 'Device' `
                -DestDevice 'SW-02' `
                -DestPort 'Gi1/0/1' `
                -Status 'Active'

            $cable2 = CableDocumentationModule\New-CableRun `
                -CableID 'TEST-002' `
                -SourceType 'Device' `
                -SourceDevice 'SW-01' `
                -SourcePort 'Gi1/0/2' `
                -DestType 'Device' `
                -DestDevice 'SW-03' `
                -DestPort 'Gi1/0/1' `
                -Status 'Reserved'

            CableDocumentationModule\Add-CableRun -Cable $cable1 -Database $script:testDb
            CableDocumentationModule\Add-CableRun -Cable $cable2 -Database $script:testDb

            $results = @(CableDocumentationModule\Get-CableRun -Status 'Reserved' -Database $script:testDb)
            $results.Count | Should Be 1
            $results[0].CableID | Should Be 'TEST-002'
        }
    }

    Context 'Update-CableRun' {

        It 'Updates cable properties' {
            $cable = CableDocumentationModule\New-CableRun `
                -CableID 'TEST-001' `
                -SourceType 'Device' `
                -SourceDevice 'SW-01' `
                -SourcePort 'Gi1/0/1' `
                -DestType 'Device' `
                -DestDevice 'SW-02' `
                -DestPort 'Gi1/0/1'
            CableDocumentationModule\Add-CableRun -Cable $cable -Database $script:testDb

            $result = CableDocumentationModule\Update-CableRun `
                -CableID 'TEST-001' `
                -Properties @{ Status = 'Faulty'; Notes = 'Needs replacement' } `
                -Database $script:testDb

            $result.Status | Should Be 'Faulty'
            $result.Notes | Should Be 'Needs replacement'
        }

        It 'Returns null for non-existent cable' {
            $result = CableDocumentationModule\Update-CableRun `
                -CableID 'NONEXISTENT' `
                -Properties @{ Status = 'Faulty' } `
                -Database $script:testDb -WarningAction SilentlyContinue

            $result | Should BeNullOrEmpty
        }
    }

    Context 'Remove-CableRun' {

        It 'Removes cable from database' {
            $cable = CableDocumentationModule\New-CableRun `
                -CableID 'TEST-001' `
                -SourceType 'Device' `
                -SourceDevice 'SW-01' `
                -SourcePort 'Gi1/0/1' `
                -DestType 'Device' `
                -DestDevice 'SW-02' `
                -DestPort 'Gi1/0/1'
            CableDocumentationModule\Add-CableRun -Cable $cable -Database $script:testDb

            $result = CableDocumentationModule\Remove-CableRun -CableID 'TEST-001' -Database $script:testDb

            $result | Should Be $true
            $script:testDb.Cables.Count | Should Be 0
        }

        It 'Returns false for non-existent cable' {
            $result = CableDocumentationModule\Remove-CableRun -CableID 'NONEXISTENT' -Database $script:testDb -WarningAction SilentlyContinue

            $result | Should Be $false
        }
    }

    #endregion

    #region Patch Panel Operations Tests

    Context 'Add-PatchPanel' {

        It 'Adds a patch panel to the database' {
            $panel = CableDocumentationModule\New-PatchPanel -PanelID 'PP-TEST-01' -PanelName 'MDF-PP-01'
            $result = CableDocumentationModule\Add-PatchPanel -Panel $panel -Database $script:testDb

            $result | Should Not BeNullOrEmpty
            $script:testDb.PatchPanels.Count | Should Be 1
        }

        It 'Rejects duplicate PanelID' {
            $panel1 = CableDocumentationModule\New-PatchPanel -PanelID 'PP-TEST-01' -PanelName 'MDF-PP-01'
            $panel2 = CableDocumentationModule\New-PatchPanel -PanelID 'PP-TEST-01' -PanelName 'MDF-PP-02'

            CableDocumentationModule\Add-PatchPanel -Panel $panel1 -Database $script:testDb
            $result = CableDocumentationModule\Add-PatchPanel -Panel $panel2 -Database $script:testDb -WarningAction SilentlyContinue

            $result | Should BeNullOrEmpty
            $script:testDb.PatchPanels.Count | Should Be 1
        }
    }

    Context 'Get-PatchPanel' {

        It 'Returns all panels when no filter' {
            $panel1 = CableDocumentationModule\New-PatchPanel -PanelID 'PP-01' -PanelName 'MDF-PP-01' -Location 'MDF Room'
            $panel2 = CableDocumentationModule\New-PatchPanel -PanelID 'PP-02' -PanelName 'IDF-PP-01' -Location 'IDF Closet'
            CableDocumentationModule\Add-PatchPanel -Panel $panel1 -Database $script:testDb
            CableDocumentationModule\Add-PatchPanel -Panel $panel2 -Database $script:testDb

            $results = @(CableDocumentationModule\Get-PatchPanel -Database $script:testDb)
            $results.Count | Should Be 2
        }

        It 'Filters by PanelID' {
            $panel1 = CableDocumentationModule\New-PatchPanel -PanelID 'PP-01' -PanelName 'MDF-PP-01'
            $panel2 = CableDocumentationModule\New-PatchPanel -PanelID 'PP-02' -PanelName 'IDF-PP-01'
            CableDocumentationModule\Add-PatchPanel -Panel $panel1 -Database $script:testDb
            CableDocumentationModule\Add-PatchPanel -Panel $panel2 -Database $script:testDb

            $results = @(CableDocumentationModule\Get-PatchPanel -PanelID 'PP-01' -Database $script:testDb)
            $results.Count | Should Be 1
            $results[0].PanelName | Should Be 'MDF-PP-01'
        }

        It 'Filters by Location' {
            $panel1 = CableDocumentationModule\New-PatchPanel -PanelID 'PP-01' -PanelName 'MDF-PP-01' -Location 'MDF Room'
            $panel2 = CableDocumentationModule\New-PatchPanel -PanelID 'PP-02' -PanelName 'IDF-PP-01' -Location 'IDF Closet'
            CableDocumentationModule\Add-PatchPanel -Panel $panel1 -Database $script:testDb
            CableDocumentationModule\Add-PatchPanel -Panel $panel2 -Database $script:testDb

            $results = @(CableDocumentationModule\Get-PatchPanel -Location 'IDF' -Database $script:testDb)
            $results.Count | Should Be 1
            $results[0].PanelID | Should Be 'PP-02'
        }
    }

    Context 'Set-PatchPanelPort' {

        It 'Updates port CableID' {
            $panel = CableDocumentationModule\New-PatchPanel -PanelID 'PP-01' -PanelName 'MDF-PP-01' -PortCount 24
            CableDocumentationModule\Add-PatchPanel -Panel $panel -Database $script:testDb

            $result = CableDocumentationModule\Set-PatchPanelPort `
                -PanelID 'PP-01' `
                -PortNumber 1 `
                -CableID 'CBL-001' `
                -Database $script:testDb

            $result.CableID | Should Be 'CBL-001'
        }

        It 'Updates port Label' {
            $panel = CableDocumentationModule\New-PatchPanel -PanelID 'PP-01' -PanelName 'MDF-PP-01' -PortCount 24
            CableDocumentationModule\Add-PatchPanel -Panel $panel -Database $script:testDb

            $result = CableDocumentationModule\Set-PatchPanelPort `
                -PanelID 'PP-01' `
                -PortNumber 1 `
                -Label 'Desk 101' `
                -Database $script:testDb

            $result.Label | Should Be 'Desk 101'
        }

        It 'Updates port Status' {
            $panel = CableDocumentationModule\New-PatchPanel -PanelID 'PP-01' -PanelName 'MDF-PP-01' -PortCount 24
            CableDocumentationModule\Add-PatchPanel -Panel $panel -Database $script:testDb

            $result = CableDocumentationModule\Set-PatchPanelPort `
                -PanelID 'PP-01' `
                -PortNumber 1 `
                -Status 'Connected' `
                -Database $script:testDb

            $result.Status | Should Be 'Connected'
        }

        It 'Returns null for invalid port number' {
            $panel = CableDocumentationModule\New-PatchPanel -PanelID 'PP-01' -PanelName 'MDF-PP-01' -PortCount 24
            CableDocumentationModule\Add-PatchPanel -Panel $panel -Database $script:testDb

            $result = CableDocumentationModule\Set-PatchPanelPort `
                -PanelID 'PP-01' `
                -PortNumber 99 `
                -Label 'Test' `
                -Database $script:testDb -WarningAction SilentlyContinue

            $result | Should BeNullOrEmpty
        }
    }

    #endregion

    #region Label Generation Tests

    Context 'New-CableLabel' {

        It 'Creates full label with all fields' {
            $cable = CableDocumentationModule\New-CableRun `
                -CableID 'MDF-001' `
                -SourceType 'Device' `
                -SourceDevice 'SW-01' `
                -SourcePort 'Gi1/0/1' `
                -DestType 'PatchPanel' `
                -DestDevice 'PP-MDF-01' `
                -DestPort '1' `
                -CableType 'Cat6a' `
                -Length '10ft'

            $label = CableDocumentationModule\New-CableLabel -Cable $cable -LabelType 'Full'

            $label | Should Not BeNullOrEmpty
            $label.LabelType | Should Be 'Full'
            ($label.Lines -join ' ') | Should Match 'MDF-001'
            ($label.Lines -join ' ') | Should Match 'SW-01'
            ($label.Lines -join ' ') | Should Match 'PP-MDF-01'
        }

        It 'Creates source end label' {
            $cable = CableDocumentationModule\New-CableRun `
                -CableID 'MDF-001' `
                -SourceType 'Device' `
                -SourceDevice 'SW-01' `
                -SourcePort 'Gi1/0/1' `
                -DestType 'PatchPanel' `
                -DestDevice 'PP-MDF-01' `
                -DestPort '1'

            $label = CableDocumentationModule\New-CableLabel -Cable $cable -LabelType 'SourceEnd'

            $label.LabelType | Should Be 'SourceEnd'
            ($label.Lines -join ' ') | Should Match 'TO:'
            ($label.Lines -join ' ') | Should Match 'PP-MDF-01'
        }

        It 'Creates destination end label' {
            $cable = CableDocumentationModule\New-CableRun `
                -CableID 'MDF-001' `
                -SourceType 'Device' `
                -SourceDevice 'SW-01' `
                -SourcePort 'Gi1/0/1' `
                -DestType 'PatchPanel' `
                -DestDevice 'PP-MDF-01' `
                -DestPort '1'

            $label = CableDocumentationModule\New-CableLabel -Cable $cable -LabelType 'DestEnd'

            $label.LabelType | Should Be 'DestEnd'
            ($label.Lines -join ' ') | Should Match 'FROM:'
            ($label.Lines -join ' ') | Should Match 'SW-01'
        }

        It 'Creates compact label' {
            $cable = CableDocumentationModule\New-CableRun `
                -CableID 'MDF-001' `
                -SourceType 'Device' `
                -SourceDevice 'SW-01' `
                -SourcePort 'Gi1/0/1' `
                -DestType 'PatchPanel' `
                -DestDevice 'PP-MDF-01' `
                -DestPort '1'

            $label = CableDocumentationModule\New-CableLabel -Cable $cable -LabelType 'Compact'

            $label.LabelType | Should Be 'Compact'
            $label.Lines.Count | Should Be 2
        }

        It 'Includes QR data when requested' {
            $cable = CableDocumentationModule\New-CableRun `
                -CableID 'MDF-001' `
                -SourceType 'Device' `
                -SourceDevice 'SW-01' `
                -SourcePort 'Gi1/0/1' `
                -DestType 'PatchPanel' `
                -DestDevice 'PP-MDF-01' `
                -DestPort '1'

            $label = CableDocumentationModule\New-CableLabel -Cable $cable -IncludeQR

            $label.QRData | Should Not BeNullOrEmpty
            $label.QRData | Should Match 'MDF-001'
        }
    }

    Context 'Export-CableLabels' {

        It 'Exports to Text format' {
            $cable1 = CableDocumentationModule\New-CableRun `
                -CableID 'CBL-001' `
                -SourceType 'Device' `
                -SourceDevice 'SW-01' `
                -SourcePort 'Gi1/0/1' `
                -DestType 'Device' `
                -DestDevice 'SW-02' `
                -DestPort 'Gi1/0/1'

            $cable2 = CableDocumentationModule\New-CableRun `
                -CableID 'CBL-002' `
                -SourceType 'Device' `
                -SourceDevice 'SW-01' `
                -SourcePort 'Gi1/0/2' `
                -DestType 'Device' `
                -DestDevice 'SW-03' `
                -DestPort 'Gi1/0/1'

            $labels = @(
                CableDocumentationModule\New-CableLabel -Cable $cable1 -LabelType 'Compact'
                CableDocumentationModule\New-CableLabel -Cable $cable2 -LabelType 'Compact'
            )

            $output = $labels | CableDocumentationModule\Export-CableLabels -Format 'Text'

            $output | Should Not BeNullOrEmpty
            $output | Should Match 'CBL-001'
            $output | Should Match 'CBL-002'
        }

        It 'Exports to CSV format' {
            $cable = CableDocumentationModule\New-CableRun `
                -CableID 'CBL-001' `
                -SourceType 'Device' `
                -SourceDevice 'SW-01' `
                -SourcePort 'Gi1/0/1' `
                -DestType 'Device' `
                -DestDevice 'SW-02' `
                -DestPort 'Gi1/0/1'

            $labels = @(CableDocumentationModule\New-CableLabel -Cable $cable -LabelType 'Compact')
            $output = $labels | CableDocumentationModule\Export-CableLabels -Format 'CSV'

            $output | Should Not BeNullOrEmpty
            # CSV headers are "ID","Line1",... - check for ID column and cable ID
            ($output -join "`n") | Should Match 'ID'
            ($output -join "`n") | Should Match 'CBL-001'
        }

        It 'Exports to HTML format' {
            $cable = CableDocumentationModule\New-CableRun `
                -CableID 'CBL-001' `
                -SourceType 'Device' `
                -SourceDevice 'SW-01' `
                -SourcePort 'Gi1/0/1' `
                -DestType 'Device' `
                -DestDevice 'SW-02' `
                -DestPort 'Gi1/0/1'

            $labels = @(CableDocumentationModule\New-CableLabel -Cable $cable -LabelType 'Compact')
            $output = $labels | CableDocumentationModule\Export-CableLabels -Format 'HTML'

            $output | Should Not BeNullOrEmpty
            $output | Should Match '<html>'
            $output | Should Match 'label-line'
        }
    }

    #endregion

    #region Search and Analysis Tests

    Context 'Find-CableConnection' {

        It 'Finds connections by device name' {
            $cable1 = CableDocumentationModule\New-CableRun `
                -CableID 'CBL-001' `
                -SourceType 'Device' `
                -SourceDevice 'SW-01' `
                -SourcePort 'Gi1/0/1' `
                -DestType 'PatchPanel' `
                -DestDevice 'PP-01' `
                -DestPort '1'

            $cable2 = CableDocumentationModule\New-CableRun `
                -CableID 'CBL-002' `
                -SourceType 'PatchPanel' `
                -SourceDevice 'PP-01' `
                -SourcePort '1' `
                -DestType 'WallJack' `
                -DestDevice 'WJ-101' `
                -DestPort 'A'

            CableDocumentationModule\Add-CableRun -Cable $cable1 -Database $script:testDb
            CableDocumentationModule\Add-CableRun -Cable $cable2 -Database $script:testDb

            $results = @(CableDocumentationModule\Find-CableConnection -Device 'SW-01' -Database $script:testDb)

            $results.Count | Should Be 1
            $results[0].CableID | Should Be 'CBL-001'
        }

        It 'Finds connections by device and port' {
            $cable1 = CableDocumentationModule\New-CableRun `
                -CableID 'CBL-001' `
                -SourceType 'Device' `
                -SourceDevice 'SW-01' `
                -SourcePort 'Gi1/0/1' `
                -DestType 'PatchPanel' `
                -DestDevice 'PP-01' `
                -DestPort '1'

            $cable2 = CableDocumentationModule\New-CableRun `
                -CableID 'CBL-002' `
                -SourceType 'PatchPanel' `
                -SourceDevice 'PP-01' `
                -SourcePort '1' `
                -DestType 'WallJack' `
                -DestDevice 'WJ-101' `
                -DestPort 'A'

            CableDocumentationModule\Add-CableRun -Cable $cable1 -Database $script:testDb
            CableDocumentationModule\Add-CableRun -Cable $cable2 -Database $script:testDb

            $results = @(CableDocumentationModule\Find-CableConnection -Device 'PP-01' -Port '1' -Database $script:testDb)

            $results.Count | Should Be 2
        }

        It 'Returns connection direction' {
            $cable = CableDocumentationModule\New-CableRun `
                -CableID 'CBL-001' `
                -SourceType 'Device' `
                -SourceDevice 'SW-01' `
                -SourcePort 'Gi1/0/1' `
                -DestType 'PatchPanel' `
                -DestDevice 'PP-01' `
                -DestPort '1'

            CableDocumentationModule\Add-CableRun -Cable $cable -Database $script:testDb

            $results = @(CableDocumentationModule\Find-CableConnection -Device 'SW-01' -Database $script:testDb)

            $results[0].Direction | Should Be 'Outbound'
        }

        It 'Returns remote endpoint info' {
            $cable = CableDocumentationModule\New-CableRun `
                -CableID 'CBL-001' `
                -SourceType 'Device' `
                -SourceDevice 'SW-01' `
                -SourcePort 'Gi1/0/1' `
                -DestType 'PatchPanel' `
                -DestDevice 'PP-01' `
                -DestPort '1'

            CableDocumentationModule\Add-CableRun -Cable $cable -Database $script:testDb

            $results = @(CableDocumentationModule\Find-CableConnection -Device 'SW-01' -Database $script:testDb)

            $results[0].RemoteDevice | Should Be 'PP-01'
            $results[0].RemotePort | Should Be '1'
        }
    }

    Context 'Get-CableDatabaseStats' {

        It 'Returns correct cable count' {
            $cable1 = CableDocumentationModule\New-CableRun `
                -CableID 'CBL-001' `
                -SourceType 'Device' `
                -SourceDevice 'SW-01' `
                -SourcePort 'Gi1/0/1' `
                -DestType 'Device' `
                -DestDevice 'SW-02' `
                -DestPort 'Gi1/0/1' `
                -CableType 'Cat6' `
                -Status 'Active'

            $cable2 = CableDocumentationModule\New-CableRun `
                -CableID 'CBL-002' `
                -SourceType 'Device' `
                -SourceDevice 'SW-01' `
                -SourcePort 'Gi1/0/2' `
                -DestType 'Device' `
                -DestDevice 'SW-03' `
                -DestPort 'Gi1/0/1' `
                -CableType 'Cat6a' `
                -Status 'Reserved'

            CableDocumentationModule\Add-CableRun -Cable $cable1 -Database $script:testDb
            CableDocumentationModule\Add-CableRun -Cable $cable2 -Database $script:testDb

            $stats = CableDocumentationModule\Get-CableDatabaseStats -Database $script:testDb

            $stats.TotalCables | Should Be 2
        }

        It 'Returns correct panel count' {
            $panel = CableDocumentationModule\New-PatchPanel -PanelID 'PP-01' -PanelName 'PP-01' -PortCount 24
            CableDocumentationModule\Add-PatchPanel -Panel $panel -Database $script:testDb

            $stats = CableDocumentationModule\Get-CableDatabaseStats -Database $script:testDb

            $stats.TotalPatchPanels | Should Be 1
        }

        It 'Returns cables by status' {
            $cable1 = CableDocumentationModule\New-CableRun `
                -CableID 'CBL-001' `
                -SourceType 'Device' `
                -SourceDevice 'SW-01' `
                -SourcePort 'Gi1/0/1' `
                -DestType 'Device' `
                -DestDevice 'SW-02' `
                -DestPort 'Gi1/0/1' `
                -Status 'Active'

            $cable2 = CableDocumentationModule\New-CableRun `
                -CableID 'CBL-002' `
                -SourceType 'Device' `
                -SourceDevice 'SW-01' `
                -SourcePort 'Gi1/0/2' `
                -DestType 'Device' `
                -DestDevice 'SW-03' `
                -DestPort 'Gi1/0/1' `
                -Status 'Reserved'

            CableDocumentationModule\Add-CableRun -Cable $cable1 -Database $script:testDb
            CableDocumentationModule\Add-CableRun -Cable $cable2 -Database $script:testDb

            $stats = CableDocumentationModule\Get-CableDatabaseStats -Database $script:testDb

            $stats.CablesByStatus['Active'] | Should Be 1
            $stats.CablesByStatus['Reserved'] | Should Be 1
        }

        It 'Returns port utilization' {
            $panel = CableDocumentationModule\New-PatchPanel -PanelID 'PP-01' -PanelName 'PP-01' -PortCount 24
            CableDocumentationModule\Add-PatchPanel -Panel $panel -Database $script:testDb
            CableDocumentationModule\Set-PatchPanelPort -PanelID 'PP-01' -PortNumber 1 -Status 'Connected' -Database $script:testDb

            $stats = CableDocumentationModule\Get-CableDatabaseStats -Database $script:testDb

            $stats.TotalPanelPorts | Should Be 24
            $stats.UsedPanelPorts | Should Be 1
            $stats.AvailablePorts | Should Be 23
        }
    }

    #endregion

    #region Import/Export Tests

    Context 'Export and Import CableDatabase' {

        It 'Exports database to JSON file' {
            $cable = CableDocumentationModule\New-CableRun `
                -CableID 'CBL-001' `
                -SourceType 'Device' `
                -SourceDevice 'SW-01' `
                -SourcePort 'Gi1/0/1' `
                -DestType 'Device' `
                -DestDevice 'SW-02' `
                -DestPort 'Gi1/0/1'

            $panel = CableDocumentationModule\New-PatchPanel -PanelID 'PP-01' -PanelName 'PP-01'

            CableDocumentationModule\Add-CableRun -Cable $cable -Database $script:testDb
            CableDocumentationModule\Add-PatchPanel -Panel $panel -Database $script:testDb

            $exportPath = Join-Path $env:TEMP 'CableDocTest.json'

            try {
                CableDocumentationModule\Export-CableDatabase -Path $exportPath -Database $script:testDb
                Test-Path $exportPath | Should Be $true
            }
            finally {
                if (Test-Path $exportPath) {
                    Remove-Item $exportPath -Force
                }
            }
        }

        It 'Imports database from JSON file' {
            $cable = CableDocumentationModule\New-CableRun `
                -CableID 'CBL-001' `
                -SourceType 'Device' `
                -SourceDevice 'SW-01' `
                -SourcePort 'Gi1/0/1' `
                -DestType 'Device' `
                -DestDevice 'SW-02' `
                -DestPort 'Gi1/0/1'

            $panel = CableDocumentationModule\New-PatchPanel -PanelID 'PP-01' -PanelName 'PP-01'

            CableDocumentationModule\Add-CableRun -Cable $cable -Database $script:testDb
            CableDocumentationModule\Add-PatchPanel -Panel $panel -Database $script:testDb

            $exportPath = Join-Path $env:TEMP 'CableDocTest.json'

            try {
                CableDocumentationModule\Export-CableDatabase -Path $exportPath -Database $script:testDb

                $importDb = CableDocumentationModule\New-CableDatabase
                $result = CableDocumentationModule\Import-CableDatabase -Path $exportPath -Database $importDb

                $result.CablesImported | Should Be 1
                $result.PanelsImported | Should Be 1
            }
            finally {
                if (Test-Path $exportPath) {
                    Remove-Item $exportPath -Force
                }
            }
        }

        It 'Merges when Merge flag is set' {
            $cable = CableDocumentationModule\New-CableRun `
                -CableID 'CBL-001' `
                -SourceType 'Device' `
                -SourceDevice 'SW-01' `
                -SourcePort 'Gi1/0/1' `
                -DestType 'Device' `
                -DestDevice 'SW-02' `
                -DestPort 'Gi1/0/1'

            CableDocumentationModule\Add-CableRun -Cable $cable -Database $script:testDb

            $exportPath = Join-Path $env:TEMP 'CableDocTest.json'

            try {
                CableDocumentationModule\Export-CableDatabase -Path $exportPath -Database $script:testDb

                # Create new db with additional cable
                $importDb = CableDocumentationModule\New-CableDatabase
                $cable2 = CableDocumentationModule\New-CableRun `
                    -CableID 'CBL-002' `
                    -SourceType 'Device' `
                    -SourceDevice 'SW-03' `
                    -SourcePort 'Gi1/0/1' `
                    -DestType 'Device' `
                    -DestDevice 'SW-04' `
                    -DestPort 'Gi1/0/1'
                CableDocumentationModule\Add-CableRun -Cable $cable2 -Database $importDb

                $result = CableDocumentationModule\Import-CableDatabase -Path $exportPath -Database $importDb -Merge

                $result.TotalCables | Should Be 2
            }
            finally {
                if (Test-Path $exportPath) {
                    Remove-Item $exportPath -Force
                }
            }
        }
    }

    #endregion

    #region ST-T-005: Port Reorg Integration Functions

    Context 'Get-CableForPort returns cable info for device port' {
        BeforeEach {
            $script:testDb = CableDocumentationModule\New-CableDatabase

            $cable = CableDocumentationModule\New-CableRun `
                -CableID 'CBL-TEST-001' `
                -SourceType 'Device' `
                -SourceDevice 'SW-CORE-01' `
                -SourcePort 'Gi1/0/24' `
                -DestType 'Device' `
                -DestDevice 'SW-ACCESS-01' `
                -DestPort 'Gi1/0/1' `
                -CableType 'Cat6a' `
                -Status 'Active'
            CableDocumentationModule\Add-CableRun -Cable $cable -Database $script:testDb
        }

        It 'Returns cable info when port is source' {
            $result = CableDocumentationModule\Get-CableForPort -DeviceName 'SW-CORE-01' -PortName 'Gi1/0/24' -Database $script:testDb
            $result | Should Not BeNullOrEmpty
            $result.CableID | Should Be 'CBL-TEST-001'
            $result.RemoteDevice | Should Be 'SW-ACCESS-01'
            $result.RemotePort | Should Be 'Gi1/0/1'
        }

        It 'Returns cable info when port is destination' {
            $result = CableDocumentationModule\Get-CableForPort -DeviceName 'SW-ACCESS-01' -PortName 'Gi1/0/1' -Database $script:testDb
            $result | Should Not BeNullOrEmpty
            $result.CableID | Should Be 'CBL-TEST-001'
            $result.RemoteDevice | Should Be 'SW-CORE-01'
            $result.RemotePort | Should Be 'Gi1/0/24'
        }

        It 'Returns null when no cable found' {
            $result = CableDocumentationModule\Get-CableForPort -DeviceName 'SW-UNKNOWN' -PortName 'Gi1/0/1' -Database $script:testDb
            $result | Should BeNullOrEmpty
        }

        It 'Is case-insensitive for device name' {
            $result = CableDocumentationModule\Get-CableForPort -DeviceName 'sw-core-01' -PortName 'Gi1/0/24' -Database $script:testDb
            $result | Should Not BeNullOrEmpty
            $result.CableID | Should Be 'CBL-TEST-001'
        }
    }

    Context 'Get-CableSummaryForPort returns formatted summary string' {
        BeforeEach {
            $script:testDb = CableDocumentationModule\New-CableDatabase

            $cable = CableDocumentationModule\New-CableRun `
                -CableID 'CBL-MDF-001' `
                -SourceType 'Device' `
                -SourceDevice 'ROUTER-01' `
                -SourcePort 'Gi0/0/1' `
                -DestType 'Device' `
                -DestDevice 'FIREWALL-01' `
                -DestPort 'Eth1' `
                -CableType 'Cat6a'
            CableDocumentationModule\Add-CableRun -Cable $cable -Database $script:testDb
        }

        It 'Returns formatted summary for source port' {
            $result = CableDocumentationModule\Get-CableSummaryForPort -DeviceName 'ROUTER-01' -PortName 'Gi0/0/1' -Database $script:testDb
            $result | Should Be 'CBL-MDF-001 -> FIREWALL-01:Eth1'
        }

        It 'Returns formatted summary for destination port' {
            $result = CableDocumentationModule\Get-CableSummaryForPort -DeviceName 'FIREWALL-01' -PortName 'Eth1' -Database $script:testDb
            $result | Should Be 'CBL-MDF-001 -> ROUTER-01:Gi0/0/1'
        }

        It 'Returns empty string when no cable found' {
            $result = CableDocumentationModule\Get-CableSummaryForPort -DeviceName 'UNKNOWN' -PortName 'Gi0/0/1' -Database $script:testDb
            $result | Should Be ''
        }
    }

    Context 'Set-CableForPort creates or updates cable link' {
        BeforeEach {
            $script:testDb = CableDocumentationModule\New-CableDatabase
        }

        It 'Creates new cable when none exists' {
            $result = CableDocumentationModule\Set-CableForPort `
                -DeviceName 'SW-01' `
                -PortName 'Gi1/0/1' `
                -RemoteDevice 'SW-02' `
                -RemotePort 'Gi1/0/1' `
                -CableID 'NEW-CBL-001' `
                -CableType 'Cat6' `
                -Database $script:testDb

            $result | Should Not BeNullOrEmpty
            $result.CableID | Should Be 'NEW-CBL-001'

            # Verify cable was added to database
            $cables = @(CableDocumentationModule\Get-CableRun -Database $script:testDb)
            $cables.Count | Should Be 1
            $cables[0].SourceDevice | Should Be 'SW-01'
        }

        It 'Auto-generates CableID when not provided' {
            $result = CableDocumentationModule\Set-CableForPort `
                -DeviceName 'SW-01' `
                -PortName 'Gi1/0/2' `
                -RemoteDevice 'SW-03' `
                -RemotePort 'Gi1/0/2' `
                -Database $script:testDb

            $result | Should Not BeNullOrEmpty
            $result.CableID | Should Match '^CBL-'
        }

        It 'Updates existing cable when found' {
            # Create initial cable
            $cable = CableDocumentationModule\New-CableRun `
                -CableID 'EXISTING-001' `
                -SourceType 'Device' `
                -SourceDevice 'SW-01' `
                -SourcePort 'Gi1/0/5' `
                -DestType 'Device' `
                -DestDevice 'SW-02' `
                -DestPort 'Gi1/0/5'
            CableDocumentationModule\Add-CableRun -Cable $cable -Database $script:testDb

            # Update it
            $result = CableDocumentationModule\Set-CableForPort `
                -DeviceName 'SW-01' `
                -PortName 'Gi1/0/5' `
                -RemoteDevice 'SW-99' `
                -RemotePort 'Gi1/0/99' `
                -Database $script:testDb

            $result.CableID | Should Be 'EXISTING-001'
            $result.RemoteDevice | Should Be 'SW-99'
        }
    }

    Context 'Remove-CableForPort removes cable link' {
        BeforeEach {
            $script:testDb = CableDocumentationModule\New-CableDatabase

            $cable = CableDocumentationModule\New-CableRun `
                -CableID 'CBL-REMOVE-001' `
                -SourceType 'Device' `
                -SourceDevice 'SW-DEL-01' `
                -SourcePort 'Gi1/0/10' `
                -DestType 'Device' `
                -DestDevice 'SW-DEL-02' `
                -DestPort 'Gi1/0/10'
            CableDocumentationModule\Add-CableRun -Cable $cable -Database $script:testDb
        }

        It 'Removes cable when found by source port' {
            $result = CableDocumentationModule\Remove-CableForPort -DeviceName 'SW-DEL-01' -PortName 'Gi1/0/10' -Database $script:testDb
            $result | Should Be $true

            $cables = @(CableDocumentationModule\Get-CableRun -Database $script:testDb)
            @($cables | Where-Object { $_ }).Count | Should Be 0
        }

        It 'Removes cable when found by destination port' {
            # Re-add the cable since previous test removed it
            $cable = CableDocumentationModule\New-CableRun `
                -CableID 'CBL-REMOVE-001' `
                -SourceType 'Device' `
                -SourceDevice 'SW-DEL-01' `
                -SourcePort 'Gi1/0/10' `
                -DestType 'Device' `
                -DestDevice 'SW-DEL-02' `
                -DestPort 'Gi1/0/10'
            CableDocumentationModule\Add-CableRun -Cable $cable -Database $script:testDb

            $result = CableDocumentationModule\Remove-CableForPort -DeviceName 'SW-DEL-02' -PortName 'Gi1/0/10' -Database $script:testDb
            $result | Should Be $true

            $cables = @(CableDocumentationModule\Get-CableRun -Database $script:testDb)
            @($cables | Where-Object { $_ }).Count | Should Be 0
        }

        It 'Returns false when no cable found' {
            # BeforeEach runs before each test so we have a fresh db with the CBL-REMOVE-001 cable
            # Test with a device/port that doesn't have any cable
            $result = CableDocumentationModule\Remove-CableForPort -DeviceName 'SW-NOPE' -PortName 'Gi1/0/99' -Database $script:testDb
            $result | Should Be $false
        }
    }

    #endregion
}
