Set-StrictMode -Version Latest

Describe "ViewStateService Get-FilterSnapshot" {
    BeforeAll {
        $modulePath = Join-Path (Split-Path $PSCommandPath) "..\ViewStateService.psm1"
        Import-Module (Resolve-Path $modulePath) -Force

        $script:TestMetadata = @{
            'SITE1-Z1-SW1' = [pscustomobject]@{ Site = 'SITE1'; Zone = 'Z1'; Building = 'B1'; Room = 'R101' }
            'SITE1-Z2-SW2' = [pscustomobject]@{ Site = 'SITE1'; Zone = 'Z2'; Building = 'B2'; Room = 'R201' }
            'SITE1-Z2-SW3' = [pscustomobject]@{ Site = 'SITE1'; Zone = 'Z2'; Building = 'B2'; Room = 'R202' }
            'SITE2-Z3-SW4' = [pscustomobject]@{ Site = 'SITE2'; Zone = 'Z3'; Building = 'B3'; Room = 'R301' }
            'SITE3-XX-SW5' = [pscustomobject]@{ Site = 'SITE3'; Building = 'B4'; Room = 'R401' }
        }
    }

    AfterAll {
        Remove-Module ViewStateService -Force
        Remove-Variable -Name TestMetadata -Scope Script -ErrorAction SilentlyContinue
    }

    It "returns sorted unique lists when no filters are provided" {
        $snapshot = ViewStateService\Get-FilterSnapshot -DeviceMetadata $script:TestMetadata

        $snapshot.Sites | Should Be @('SITE1','SITE2','SITE3')
        $snapshot.Zones | Should Be @('XX','Z1','Z2','Z3')
        $snapshot.Buildings | Should Be @('B1','B2','B3','B4')
        $snapshot.Hostnames | Should Be @('SITE1-Z1-SW1','SITE1-Z2-SW2','SITE1-Z2-SW3','SITE2-Z3-SW4','SITE3-XX-SW5')
        $snapshot.ZoneToLoad | Should Be 'XX'
    }

    It "scopes zones, buildings, and hosts to the requested site" {
        $snapshot = ViewStateService\Get-FilterSnapshot -DeviceMetadata $script:TestMetadata -Site 'SITE1'

        $snapshot.Zones | Should Be @('Z1','Z2')
        $snapshot.Buildings | Should Be @('B1','B2')
        $snapshot.Hostnames | Should Be @('SITE1-Z1-SW1','SITE1-Z2-SW2','SITE1-Z2-SW3')
    }

    It "filters hostnames by building and room and surfaces zone load hints" {
        $snapshot = ViewStateService\Get-FilterSnapshot -DeviceMetadata $script:TestMetadata -Site 'SITE1' -ZoneSelection 'Z2' -Building 'B2' -Room 'R202'

        $snapshot.Hostnames | Should Be @('SITE1-Z2-SW3')
        $snapshot.ZoneToLoad | Should Be 'Z2'
    }
}
