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

    BeforeEach {
        $global:DeviceHostnameOrder = @()
        $global:InterfacesLoadAllowed = $true
        Remove-Variable -Name DeviceInterfaceCache -Scope Global -ErrorAction SilentlyContinue
    }

    AfterAll {
        Remove-Module ViewStateService -Force
        Remove-Variable -Name TestMetadata -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name DeviceHostnameOrder -Scope Global -ErrorAction SilentlyContinue
        Remove-Variable -Name DeviceInterfaceCache -Scope Global -ErrorAction SilentlyContinue
        Remove-Variable -Name DeviceMetadata -Scope Global -ErrorAction SilentlyContinue
        Remove-Variable -Name InterfacesLoadAllowed -Scope Global -ErrorAction SilentlyContinue
    }

    It "returns sorted unique lists when no rotation is defined" {
        $snapshot = ViewStateService\Get-FilterSnapshot -DeviceMetadata $script:TestMetadata

        $snapshot.Sites | Should Be @('SITE1','SITE2','SITE3')
        $snapshot.Zones | Should Be @('XX','Z1','Z2','Z3')
        $snapshot.Buildings | Should Be @('B1','B2','B3','B4')
        $snapshot.Hostnames | Should Be @('SITE1-Z1-SW1','SITE1-Z2-SW2','SITE1-Z2-SW3','SITE2-Z3-SW4','SITE3-XX-SW5')
        $snapshot.ZoneToLoad | Should Be 'XX'
    }

    It "respects the preferred host rotation when provided" {
        $global:DeviceHostnameOrder = @(
            'SITE1-Z2-SW2',
            'SITE2-Z3-SW4',
            'SITE1-Z1-SW1',
            'SITE3-XX-SW5',
            'SITE1-Z2-SW3'
        )

        $snapshot = ViewStateService\Get-FilterSnapshot -DeviceMetadata $script:TestMetadata

        $snapshot.Hostnames | Should Be @('SITE1-Z2-SW2','SITE2-Z3-SW4','SITE1-Z1-SW1','SITE3-XX-SW5','SITE1-Z2-SW3')
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

    It "returns an empty snapshot when metadata is null" {
        $snapshot = ViewStateService\Get-FilterSnapshot -DeviceMetadata $null

        $snapshot.Sites | Should BeNullOrEmpty
        $snapshot.Zones | Should BeNullOrEmpty
        $snapshot.Buildings | Should BeNullOrEmpty
        $snapshot.Rooms | Should BeNullOrEmpty
        $snapshot.Hostnames | Should BeNullOrEmpty
        $snapshot.ZoneToLoad | Should Be ''
    }

    It "emits site and zone data when only location entries are provided" {
        $locations = @(
            [pscustomobject]@{ Site = 'SITE1'; Zone = 'Z1'; Building = 'B1'; Room = 'R101' },
            [pscustomobject]@{ Site = 'SITE1'; Zone = 'Z2'; Building = 'B2'; Room = 'R201' },
            [pscustomobject]@{ Site = 'SITE2'; Zone = 'Z3'; Building = 'B3'; Room = 'R301' }
        )

        $snapshot = ViewStateService\Get-FilterSnapshot -DeviceMetadata $null -LocationEntries $locations

        $snapshot.Sites | Should Be @('SITE1','SITE2')
        $snapshot.Zones | Should Be @('Z1','Z2','Z3')
        $snapshot.Buildings | Should Be @('B1','B2','B3')
        $snapshot.Rooms | Should Be @('R101','R201','R301')
        $snapshot.Hostnames | Should BeNullOrEmpty
    }

    It "falls back to location entries when metadata is an empty dictionary" {
        $locations = @(
            [pscustomobject]@{ Site = 'SITE1'; Zone = 'Z1'; Building = 'B1'; Room = 'R101' },
            [pscustomobject]@{ Site = 'SITE2'; Zone = 'Z2'; Building = 'B2'; Room = 'R201' }
        )

        $snapshot = ViewStateService\Get-FilterSnapshot -DeviceMetadata @{} -LocationEntries $locations

        $snapshot.Sites | Should Be @('SITE1','SITE2')
        $snapshot.Zones | Should Be @('Z1','Z2')
        $snapshot.Hostnames | Should BeNullOrEmpty
    }

    It "uses metadata to satisfy building and room filters when rows omit those fields" {
        $global:DeviceMetadata = $script:TestMetadata
        $row = [pscustomobject]@{
            Hostname = 'SITE1-Z1-SW1'
            Site     = 'SITE1'
            Zone     = 'Z1'
            Port     = 'Et1'
            Status   = 'up'
        }

        $global:AllInterfaces = [System.Collections.Generic.List[object]]::new()
        [void]$global:AllInterfaces.Add($row)
        & (Get-Module ViewStateService) {
            $script:CachedSite = 'SITE1'
            $script:CachedZoneSelection = 'Z1'
            $script:CachedZoneLoad = ''
            $script:CachedInterfaces = $global:AllInterfaces
        }

        $result = ViewStateService\Get-InterfacesForContext -Site 'SITE1' -ZoneSelection 'Z1' -Building 'B1' -Room 'R101'

        $result.Count | Should Be 1
        $result[0].Hostname | Should Be 'SITE1-Z1-SW1'
    }

    It "avoids hydrating full snapshots when host cache is available" {
        $global:DeviceMetadata = $script:TestMetadata
        $global:DeviceInterfaceCache = @{
            'SITE1-Z1-SW1' = @(
                [pscustomobject]@{
                    Hostname = 'SITE1-Z1-SW1'
                    Site     = 'SITE1'
                    Zone     = 'Z1'
                    Port     = 'Et1'
                    Status   = 'up'
                }
            )
        }

        & (Get-Module ViewStateService) {
            $script:CachedSite = $null
            $script:CachedZoneSelection = $null
            $script:CachedZoneLoad = $null
            $script:CachedInterfaces = $null
        }

        $result = ViewStateService\Get-InterfacesForContext -Site 'SITE1' -ZoneSelection 'Z1' -Building 'B1' -Room 'R101'

        $result.Count | Should Be 1
        $result[0].Hostname | Should Be 'SITE1-Z1-SW1'

        $cachedAfter = & (Get-Module ViewStateService) { $script:CachedInterfaces }
        $cachedAfter | Should Be $null
    }
}
