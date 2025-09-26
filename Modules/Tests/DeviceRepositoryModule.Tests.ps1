Set-StrictMode -Version Latest

function Set-RepositoryVar {
    param([string]$Name, $Value)
    $module = Get-Module DeviceRepositoryModule -ErrorAction Stop
    $module.SessionState.PSVariable.Set($Name, $Value)
}

function Remove-RepositoryVar {
    param([string]$Name)
    $module = Get-Module DeviceRepositoryModule -ErrorAction Stop
    try { $module.SessionState.PSVariable.Remove($Name) } catch {}
}

Describe "DeviceRepositoryModule core helpers" {
    BeforeAll {
        $modulePath = Join-Path (Split-Path $PSCommandPath) "..\DeviceRepositoryModule.psm1"
        Import-Module (Resolve-Path $modulePath) -Force

        $script:OriginalGlobals = @{}
        foreach ($name in 'DeviceInterfaceCache','AllInterfaces','LoadedSiteZones','DeviceMetadata') {
            if (Get-Variable -Name $name -Scope Global -ErrorAction SilentlyContinue) {
                $script:OriginalGlobals[$name] = Get-Variable -Name $name -Scope Global -ValueOnly
            } else {
                $script:OriginalGlobals[$name] = $null
            }
        }
    }

    AfterAll {
        Remove-Module DeviceRepositoryModule -Force
        foreach ($name in $script:OriginalGlobals.Keys) {
            $value = $script:OriginalGlobals[$name]
            if ($value -ne $null) {
                Set-Variable -Name $name -Scope Global -Value $value
            } else {
                Remove-Variable -Name $name -Scope Global -ErrorAction SilentlyContinue
            }
        }
    }

    BeforeEach {
        $global:DeviceInterfaceCache = @{}
        $global:AllInterfaces = [System.Collections.Generic.List[object]]::new()
        $global:LoadedSiteZones = @{}
        $global:DeviceMetadata = @{}
        Set-RepositoryVar -Name 'SiteInterfaceCache' -Value @{}
        Remove-RepositoryVar -Name 'DataDirPath'
    }

    It "derives site codes from hostnames" {
        DeviceRepositoryModule\Get-SiteFromHostname -Hostname 'SITE1-Z1-SW1' | Should Be 'SITE1'
        DeviceRepositoryModule\Get-SiteFromHostname -Hostname 'SSH@SITE2-Z9-EDGE' | Should Be 'SITE2'
        DeviceRepositoryModule\Get-SiteFromHostname -Hostname 'core' -FallbackLength 3 | Should Be 'cor'
    }

    It "returns absolute paths for discovered .accdb files" {
        $paths = DeviceRepositoryModule\Get-AllSiteDbPaths

        $paths | Should Not BeNullOrEmpty
        foreach ($path in $paths) {
            [System.IO.Path]::IsPathRooted($path) | Should Be $true
            [System.IO.Path]::GetExtension($path) | Should Be '.accdb'
        }
    }

    It "clears the per-site interface cache" {
        Set-RepositoryVar -Name 'SiteInterfaceCache' -Value @{ 'SITE1' = 1 }
        DeviceRepositoryModule\Clear-SiteInterfaceCache
        $cache = Get-Module DeviceRepositoryModule | ForEach-Object { $_.SessionState.PSVariable.Get('SiteInterfaceCache').Value }
        $cache.Keys.Count | Should Be 0
    }

    It "loads site data once per zone" {
        $global:DeviceMetadata = @{
            'SITE1-Z1-SW1' = [pscustomobject]@{ Site = 'SITE1'; Zone = 'Z1' }
        }
        Mock -ModuleName DeviceRepositoryModule -CommandName Get-InterfaceInfo {
            param([string]$Hostname)
            @([pscustomobject]@{ Hostname = $Hostname; Site = 'SITE1'; Zone = 'Z1'; Port = 'Gi1' })
        }

        DeviceRepositoryModule\Update-SiteZoneCache -Site 'SITE1' -Zone 'Z1'
        DeviceRepositoryModule\Update-SiteZoneCache -Site 'SITE1' -Zone 'Z1'

        $global:LoadedSiteZones.ContainsKey('SITE1|Z1') | Should Be $true
        $global:AllInterfaces.Count | Should Be 1
        Assert-MockCalled Get-InterfaceInfo -ModuleName DeviceRepositoryModule -Times 1 -ParameterFilter { $Hostname -eq 'SITE1-Z1-SW1' }
    }

    It "returns snapshots without mutating global interface cache" {
        $global:DeviceInterfaceCache = @{
            'SITE1-Z1-SW1' = @([pscustomobject]@{ Hostname = 'SITE1-Z1-SW1'; Site = 'SITE1'; Zone = 'Z1'; Port = 'Gi1'; PortSort = '001'; Status = 'up'; AuthState = 'authorized' })
        }

        $snapshot = DeviceRepositoryModule\Get-GlobalInterfaceSnapshot -Site 'SITE1' -ZoneSelection 'Z1'

        $snapshot | Should Not BeNullOrEmpty
        $snapshot.Length | Should Be 1
        $snapshot[0].Hostname | Should Be 'SITE1-Z1-SW1'
        (Get-Variable -Name AllInterfaces -Scope Global -ValueOnly).Count | Should Be 0
    }
    It "builds the global interface list for a site/zone selection" {
        $global:DeviceInterfaceCache = @{
            'SITE1-Z1-SW1' = @([pscustomobject]@{ Hostname = 'SITE1-Z1-SW1'; Site = 'SITE1'; Zone = 'Z1'; Port = 'Gi1'; PortSort = '001'; Status = 'up'; AuthState = 'authorized' })
            'SITE1-Z2-SW2' = @([pscustomobject]@{ Hostname = 'SITE1-Z2-SW2'; Site = 'SITE1'; Zone = 'Z2'; Port = 'Gi2'; PortSort = '002'; Status = 'down'; AuthState = 'unauthorized' })
        }
        Mock -ModuleName DeviceRepositoryModule -CommandName Update-SiteZoneCache {}

        $result = @(DeviceRepositoryModule\Update-GlobalInterfaceList -Site 'SITE1' -ZoneSelection 'Z1')

        $result.Count | Should Be 1
        $result[0].Hostname | Should Be 'SITE1-Z1-SW1'
        ($result[0].PSObject.Properties.Name -contains 'IsSelected') | Should Be $true
    }
}

