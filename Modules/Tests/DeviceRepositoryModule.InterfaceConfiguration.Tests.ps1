Set-StrictMode -Version Latest

Describe "DeviceRepositoryModule Get-InterfaceConfiguration" {
    BeforeAll {
        $modulesDir = Join-Path (Split-Path $PSCommandPath) '..'

        $databaseModulePath = Join-Path $modulesDir 'DatabaseModule.psm1'
        $templatesModulePath = Join-Path $modulesDir 'TemplatesModule.psm1'
        $repositoryModulePath = Join-Path $modulesDir 'DeviceRepositoryModule.psm1'

        Import-Module (Resolve-Path $databaseModulePath) -Force
        Import-Module (Resolve-Path $templatesModulePath) -Force
        Import-Module (Resolve-Path $repositoryModulePath) -Force
    }

    AfterAll {
        Remove-Module DeviceRepositoryModule -Force -ErrorAction SilentlyContinue
        Remove-Module TemplatesModule -Force -ErrorAction SilentlyContinue
        Remove-Module DatabaseModule -Force -ErrorAction SilentlyContinue
    }

    It "removes Brocade spanning-tree edge-port when switching profiles" {
        $hostname = 'TEST-AS1'
        $ports = @('Et1/1/1')
        $dbPath = Join-Path $TestDrive 'site.accdb'
        New-Item -ItemType File -Path $dbPath -Force | Out-Null

        $hostnameForMocks = $hostname
        $dbPathForMocks = $dbPath

        $mockDbPath = {
            param([string]$Hostname)
            return $dbPathForMocks
        }.GetNewClosure()
        Mock -ModuleName DeviceRepositoryModule -CommandName Get-DbPathForHost -MockWith $mockDbPath

        Mock -ModuleName DeviceRepositoryModule -CommandName Open-DbReadSession -MockWith { $null }
        Mock -ModuleName DeviceRepositoryModule -CommandName 'DatabaseModule\Open-DbReadSession' -MockWith { $null }
        Mock -ModuleName DeviceRepositoryModule -CommandName Close-DbReadSession -MockWith { param($Session) }
        Mock -ModuleName DeviceRepositoryModule -CommandName 'DatabaseModule\Close-DbReadSession' -MockWith { param($Session) }

        $mockInvokeDbQuery = {
            param(
                [Parameter(Mandatory)][string]$DatabasePath,
                [Parameter(Mandatory)][string]$Sql,
                [Parameter()][object]$Session
            )

            $dt = New-Object System.Data.DataTable
            $null = $dt.Columns.Add('Make', [string])
            $null = $dt.Columns.Add('Hostname', [string])
            $null = $dt.Columns.Add('Port', [string])
            $null = $dt.Columns.Add('Config', [string])

            $row = $dt.NewRow()
            $row.Make = 'Brocade'
            $row.Hostname = $hostnameForMocks
            $row.Port = 'Et1/1/1'
            $row.Config = @(
                'spanning-tree edge-port',
                'port-name OLD',
                ''
            ) -join "`n"
            $null = $dt.Rows.Add($row)
            return ,$dt
        }.GetNewClosure()
        Mock -ModuleName DeviceRepositoryModule -CommandName Invoke-DbQuery -MockWith $mockInvokeDbQuery
        Mock -ModuleName DeviceRepositoryModule -CommandName 'DatabaseModule\Invoke-DbQuery' -MockWith $mockInvokeDbQuery

        $lines = DeviceRepositoryModule\Get-InterfaceConfiguration `
            -Hostname $hostname `
            -Interfaces $ports `
            -TemplateName 'Dual Authentication Port' `
            -NewNames @{} `
            -NewVlans @{}

        Assert-MockCalled Invoke-DbQuery -ModuleName DeviceRepositoryModule -Times 2

        ($lines -join "`n") | Should Match '\s+no\s+spanning-tree\s+edge-port'
        ($lines -join "`n") | Should Match '\s+dot1x\s+port-control\s+auto'
    }
}
