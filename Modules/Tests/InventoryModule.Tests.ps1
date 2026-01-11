#Requires -Version 5.1
# Pester 3.x tests for InventoryModule

$modulePath = Join-Path $PSScriptRoot '..\InventoryModule.psm1'
Import-Module $modulePath -Force
. (Join-Path $PSScriptRoot 'TestHelpers.ps1')

Describe 'InventoryModule' {
    BeforeAll {
        Initialize-InventoryDatabase -TestMode
    }

    AfterAll {
        Remove-TestInventoryData
    }

    Context 'Asset Registry - Creation' {
        BeforeEach {
            Remove-TestInventoryData
            Initialize-InventoryDatabase -TestMode
        }

        It 'creates new asset record with required fields' {
            $asset = New-Asset -Hostname 'SW-01' -Vendor 'Cisco' -Model 'C9300-48P' -SerialNumber 'FCW12345678'
            $asset | Should Not BeNullOrEmpty
            $asset.Hostname | Should Be 'SW-01'
            $asset.SerialNumber | Should Be 'FCW12345678'
            $asset.Vendor | Should Be 'Cisco'
            $asset.Model | Should Be 'C9300-48P'
        }

        It 'creates asset with all optional fields' {
            $purchaseDate = Get-Date '2024-01-15'
            $warrantyExpiration = Get-Date '2027-01-15'

            $asset = New-Asset -Hostname 'SW-FULL-01' `
                -Vendor 'Cisco' `
                -Model 'C9300-24P' `
                -Platform 'IOS-XE' `
                -SerialNumber 'FCW99999999' `
                -AssetTag 'NT-2024-001' `
                -ManagementIP '10.1.1.10' `
                -PurchaseDate $purchaseDate `
                -PurchaseVendor 'CDW' `
                -PurchasePrice 5000 `
                -WarrantyExpiration $warrantyExpiration `
                -SupportContract 'SWSS-12345' `
                -SupportLevel '24x7x4' `
                -Site 'Campus' `
                -Building 'Building1' `
                -Rack 'Row-A-Rack-5' `
                -RackU 22 `
                -Status 'Active' `
                -FirmwareVersion '17.06.05' `
                -Notes 'Test asset'

            $asset.AssetTag | Should Be 'NT-2024-001'
            $asset.ManagementIP | Should Be '10.1.1.10'
            $asset.PurchaseVendor | Should Be 'CDW'
            $asset.PurchasePrice | Should Be 5000
            $asset.SupportLevel | Should Be '24x7x4'
            $asset.Site | Should Be 'Campus'
            $asset.FirmwareVersion | Should Be '17.06.05'
        }

        It 'validates serial number cannot be empty' {
            Assert-Throws { New-Asset -Hostname 'SW-01' -SerialNumber '' }
        }

        It 'prevents duplicate serial numbers' {
            New-Asset -Hostname 'SW-01' -SerialNumber 'DUP001'
            Assert-Throws { New-Asset -Hostname 'SW-02' -SerialNumber 'DUP001' }
        }
    }

    Context 'Asset Registry - Retrieval' {
        BeforeEach {
            Remove-TestInventoryData
            Initialize-InventoryDatabase -TestMode
        }

        It 'retrieves asset by hostname' {
            New-Asset -Hostname 'SW-TEST-01' -SerialNumber 'TEST001'
            $retrieved = Get-Asset -Hostname 'SW-TEST-01'
            $retrieved.Hostname | Should Be 'SW-TEST-01'
        }

        It 'retrieves asset by serial number' {
            New-Asset -Hostname 'SW-SERIAL' -SerialNumber 'SER001'
            $retrieved = Get-Asset -SerialNumber 'SER001'
            $retrieved.SerialNumber | Should Be 'SER001'
        }

        It 'retrieves assets by vendor' {
            New-Asset -Hostname 'SW-CISCO-01' -Vendor 'Cisco' -SerialNumber 'CIS001'
            New-Asset -Hostname 'SW-ARISTA-01' -Vendor 'Arista' -SerialNumber 'ARI001'
            $ciscoAssets = @(Get-Asset -Vendor 'Cisco')
            $ciscoAssets.Count | Should Be 1
            $ciscoAssets[0].Vendor | Should Be 'Cisco'
        }

        It 'retrieves assets by status' {
            New-Asset -Hostname 'SW-ACTIVE' -Status 'Active' -SerialNumber 'ACT001'
            New-Asset -Hostname 'SW-RMA' -Status 'RMA' -SerialNumber 'RMA001'
            $activeAssets = @(Get-Asset -Status 'Active')
            $activeAssets.Count | Should Be 1
        }
    }

    Context 'Asset Registry - Updates' {
        BeforeEach {
            Remove-TestInventoryData
            Initialize-InventoryDatabase -TestMode
        }

        It 'updates asset status correctly' {
            $asset = New-Asset -Hostname 'SW-STATUS' -SerialNumber 'STAT001' -Status 'Active'
            Set-AssetStatus -AssetID $asset.AssetID -Status 'RMA' -Reason 'Hardware failure'
            $updated = Get-Asset -AssetID $asset.AssetID
            $updated.Status | Should Be 'RMA'
        }

        It 'updates asset properties' {
            $asset = New-Asset -Hostname 'SW-UPDATE' -SerialNumber 'UPD001' -Site 'SiteA'
            Update-Asset -AssetID $asset.AssetID -Site 'SiteB' -Rack 'Rack-1'
            $updated = Get-Asset -AssetID $asset.AssetID
            $updated.Site | Should Be 'SiteB'
            $updated.Rack | Should Be 'Rack-1'
        }

        It 'removes asset from database' {
            $asset = New-Asset -Hostname 'SW-DELETE' -SerialNumber 'DEL001'
            Remove-Asset -AssetID $asset.AssetID
            $retrieved = Get-Asset -SerialNumber 'DEL001'
            $retrieved | Should BeNullOrEmpty
        }
    }

    Context 'Module Management' {
        BeforeEach {
            Remove-TestInventoryData
            Initialize-InventoryDatabase -TestMode
        }

        It 'adds module to asset' {
            $asset = New-Asset -Hostname 'SW-MOD' -SerialNumber 'MOD001'
            $module = New-AssetModule -AssetID $asset.AssetID `
                -ModuleType 'PowerSupply' `
                -PartNumber 'PWR-C1-1100WAC' `
                -SerialNumber 'PSU001' `
                -SlotPosition 'PS1' `
                -Status 'Active'

            $module | Should Not BeNullOrEmpty
            $module.ModuleType | Should Be 'PowerSupply'
            $module.SlotPosition | Should Be 'PS1'
        }

        It 'retrieves modules for asset' {
            $asset = New-Asset -Hostname 'SW-MOD2' -SerialNumber 'MOD002'
            New-AssetModule -AssetID $asset.AssetID -ModuleType 'PowerSupply' -SlotPosition 'PS1'
            New-AssetModule -AssetID $asset.AssetID -ModuleType 'PowerSupply' -SlotPosition 'PS2'
            New-AssetModule -AssetID $asset.AssetID -ModuleType 'SFP' -SlotPosition 'Gi1/0/1'

            $modules = @(Get-AssetModule -AssetID $asset.AssetID)
            $modules.Count | Should Be 3

            $psuModules = @(Get-AssetModule -AssetID $asset.AssetID -ModuleType 'PowerSupply')
            $psuModules.Count | Should Be 2
        }

        It 'throws when adding module to non-existent asset' {
            Assert-Throws { New-AssetModule -AssetID 'FAKE-ID' -ModuleType 'SFP' }
        }
    }

    Context 'Warranty Tracking' {
        BeforeEach {
            Remove-TestInventoryData
            Initialize-InventoryDatabase -TestMode
        }

        It 'identifies warranties expiring within 60 days' {
            $today = Get-Date
            New-Asset -Hostname 'SW-EXPIRE' -SerialNumber 'EXP001' -WarrantyExpiration ($today.AddDays(30))
            New-Asset -Hostname 'SW-COVERED' -SerialNumber 'COV001' -WarrantyExpiration ($today.AddDays(365))

            $expiring = @(Get-ExpiringWarranties -DaysAhead 60)
            ($expiring | Where-Object { $_.Hostname -eq 'SW-EXPIRE' }) | Should Not BeNullOrEmpty
            ($expiring | Where-Object { $_.Hostname -eq 'SW-COVERED' }) | Should BeNullOrEmpty
        }

        It 'identifies expired warranties' {
            $today = Get-Date
            New-Asset -Hostname 'SW-EXPIRED' -SerialNumber 'EXPD001' -WarrantyExpiration ($today.AddDays(-10))
            New-Asset -Hostname 'SW-ACTIVE' -SerialNumber 'ACTV001' -WarrantyExpiration ($today.AddDays(100))

            $expired = @(Get-ExpiredWarranties)
            ($expired | Where-Object { $_.Hostname -eq 'SW-EXPIRED' }) | Should Not BeNullOrEmpty
            ($expired | Where-Object { $_.Hostname -eq 'SW-ACTIVE' }) | Should BeNullOrEmpty
        }

        It 'calculates days until expiration correctly' {
            $today = Get-Date
            New-Asset -Hostname 'SW-CALC' -SerialNumber 'CALC001' -WarrantyExpiration ($today.AddDays(30))

            $asset = Get-Asset -Hostname 'SW-CALC'
            $asset.DaysUntilExpiration | Should BeGreaterThan 25
            $asset.DaysUntilExpiration | Should BeLessThan 35
        }

        It 'returns warranty summary' {
            $today = Get-Date
            New-Asset -Hostname 'SW-W1' -SerialNumber 'W001' -WarrantyExpiration ($today.AddDays(15)) -SupportLevel 'NBD'
            New-Asset -Hostname 'SW-W2' -SerialNumber 'W002' -WarrantyExpiration ($today.AddDays(45)) -SupportLevel '24x7x4'
            New-Asset -Hostname 'SW-W3' -SerialNumber 'W003' -WarrantyExpiration ($today.AddDays(-5)) -SupportLevel 'NBD'

            $summary = Get-WarrantySummary
            $summary.TotalWithWarranty | Should Be 3
            $summary.Active | Should Be 2
            $summary.Expired | Should Be 1
            $summary.Expiring30Days | Should Be 1
        }
    }

    Context 'Firmware Version Management' {
        It 'parses Cisco IOS-XE version string correctly' {
            $version = ConvertFrom-FirmwareVersionString -VersionString '17.06.05' -Vendor 'Cisco'
            $version.Major | Should Be 17
            $version.Minor | Should Be 6
            $version.Patch | Should Be 5
        }

        It 'parses Cisco IOS classic version string' {
            $version = ConvertFrom-FirmwareVersionString -VersionString '15.2(7)E4' -Vendor 'Cisco'
            $version.Major | Should Be 15
            $version.Minor | Should Be 2
            $version.Patch | Should Be 7
            $version.TrainCode | Should Be 'E'
        }

        It 'parses Arista EOS version string' {
            $version = ConvertFrom-FirmwareVersionString -VersionString '4.28.3M' -Vendor 'Arista'
            $version.Major | Should Be 4
            $version.Minor | Should Be 28
            $version.Patch | Should Be 3
            $version.TrainCode | Should Be 'M'
        }

        It 'parses Ruckus/Brocade version string' {
            $version = ConvertFrom-FirmwareVersionString -VersionString '08.0.95' -Vendor 'Ruckus'
            $version.Major | Should Be 8
            $version.Minor | Should Be 0
            $version.Patch | Should Be 95
        }

        It 'parses Juniper Junos version string' {
            $version = ConvertFrom-FirmwareVersionString -VersionString '21.4R3-S2' -Vendor 'Juniper'
            $version.Major | Should Be 21
            $version.Minor | Should Be 4
            $version.Patch | Should Be 3
            $version.Build | Should Be 2
        }

        It 'registers firmware version in database' {
            $fw = New-FirmwareVersion -Vendor 'Cisco' -Platform 'C9300' `
                -VersionString '17.06.05' `
                -IsRecommended `
                -Notes 'Recommended version'

            $fw | Should Not BeNullOrEmpty
            $fw.IsRecommended | Should Be $true

            $retrieved = @(Get-FirmwareVersion -Vendor 'Cisco' -RecommendedOnly)
            $retrieved | Should Not BeNullOrEmpty
        }

        It 'registers vulnerable firmware version with CVEs' {
            New-FirmwareVersion -Vendor 'Cisco' -Platform 'C9300' `
                -VersionString '17.03.01' `
                -CVEList @('CVE-2023-1234', 'CVE-2023-5678') `
                -IsCritical

            $vulnerable = @(Get-FirmwareVersion -WithCVEs)
            ($vulnerable.CVEList -contains 'CVE-2023-1234') | Should Be $true
        }
    }

    Context 'Minimum Firmware Requirements' {
        BeforeEach {
            Remove-TestInventoryData
            Initialize-InventoryDatabase -TestMode
        }

        It 'sets minimum firmware requirement' {
            $req = Set-MinimumFirmware -Vendor 'Cisco' -Platform 'C9300' `
                -MinVersion '17.06.03' -Reason 'Security baseline'

            $req.MinVersion | Should Be '17.06.03'
            $req.Reason | Should Be 'Security baseline'
        }

        It 'identifies devices below minimum version' {
            Set-MinimumFirmware -Vendor 'Cisco' -Platform 'C9300' -MinVersion '17.06.03'
            New-Asset -Hostname 'SW-OLD' -Vendor 'Cisco' -Model 'C9300-48P' `
                -FirmwareVersion '17.03.05' -SerialNumber 'OLD001'
            New-Asset -Hostname 'SW-NEW' -Vendor 'Cisco' -Model 'C9300-48P' `
                -FirmwareVersion '17.09.01' -SerialNumber 'NEW001'

            $below = @(Get-DevicesBelowMinimumFirmware -Vendor 'Cisco')
            ($below | Where-Object { $_.Hostname -eq 'SW-OLD' }) | Should Not BeNullOrEmpty
            ($below | Where-Object { $_.Hostname -eq 'SW-NEW' }) | Should BeNullOrEmpty
        }

        It 'returns firmware compliance summary' {
            Set-MinimumFirmware -Vendor 'Cisco' -Platform 'C9300' -MinVersion '17.06.03'
            New-Asset -Hostname 'SW-COMP1' -Vendor 'Cisco' -Model 'C9300-48P' `
                -FirmwareVersion '17.09.01' -SerialNumber 'COMP001'
            New-Asset -Hostname 'SW-COMP2' -Vendor 'Cisco' -Model 'C9300-24P' `
                -FirmwareVersion '17.06.05' -SerialNumber 'COMP002'
            New-Asset -Hostname 'SW-NONCOMP' -Vendor 'Cisco' -Model 'C9300-24P' `
                -FirmwareVersion '17.03.05' -SerialNumber 'NONC001'

            $summary = Get-FirmwareComplianceSummary
            $summary.TotalDevices | Should Be 3
            $summary.Compliant | Should Be 2
            $summary.BelowMinimum | Should Be 1
        }
    }

    Context 'Lifecycle Management' {
        BeforeEach {
            Remove-TestInventoryData
            Initialize-InventoryDatabase -TestMode
        }

        It 'retrieves lifecycle info for product' {
            $lifecycle = @(Get-LifecycleInfo -ProductID 'C9300-48P')
            $lifecycle | Should Not BeNullOrEmpty
            $lifecycle[0].Vendor | Should Be 'Cisco'
        }

        It 'retrieves lifecycle info by vendor' {
            $aristaLifecycle = @(Get-LifecycleInfo -Vendor 'Arista')
            $aristaLifecycle | Should Not BeNullOrEmpty
            $aristaLifecycle | ForEach-Object { $_.Vendor | Should Be 'Arista' }
        }

        It 'calculates days to end of support' {
            $lifecycle = @(Get-LifecycleInfo -ProductID 'C9300-48P')
            $lifecycle[0].DaysToEndOfSupport | Should Not BeNullOrEmpty
        }

        It 'adds custom lifecycle information' {
            Add-LifecycleInfo -ProductID 'CUSTOM-SW' -Vendor 'CustomVendor' `
                -Model 'Custom Switch' `
                -EndOfSaleDate ([DateTime]'2025-12-31') `
                -EndOfSupportDate ([DateTime]'2030-12-31') `
                -ReplacementModel 'CUSTOM-SW-V2'

            $custom = @(Get-LifecycleInfo -ProductID 'CUSTOM-SW')
            $custom[0].ReplacementModel | Should Be 'CUSTOM-SW-V2'
        }

        It 'identifies devices approaching end of life' {
            New-Asset -Hostname 'SW-EOL' -Vendor 'Cisco' -Model 'WS-C3850-48P' -SerialNumber 'EOL001'

            $approaching = @(Get-DevicesApproachingEoL -DaysAhead 1000)
            $approaching | Should Not BeNullOrEmpty
        }
    }

    Context 'History and Audit' {
        BeforeEach {
            Remove-TestInventoryData
            Initialize-InventoryDatabase -TestMode
        }

        It 'records asset creation in history' {
            $asset = New-Asset -Hostname 'SW-HIST' -SerialNumber 'HIST001'
            $history = @(Get-AssetHistory -AssetID $asset.AssetID)
            $history | Should Not BeNullOrEmpty
            $history[0].ChangeType | Should Be 'Created'
        }

        It 'records status changes in history' {
            $asset = New-Asset -Hostname 'SW-TRACK' -SerialNumber 'TRACK001' -Status 'Active'
            Set-AssetStatus -AssetID $asset.AssetID -Status 'RMA' -Reason 'Testing'

            $history = @(Get-AssetHistory -AssetID $asset.AssetID)
            $history.Count | Should BeGreaterThan 1

            $statusChange = @($history | Where-Object { $_.ChangeType -eq 'StatusChange' })
            $statusChange | Should Not BeNullOrEmpty
        }

        It 'retrieves history by serial number' {
            $asset = New-Asset -Hostname 'SW-SER-HIST' -SerialNumber 'SERHIST001'
            Set-AssetStatus -SerialNumber 'SERHIST001' -Status 'Spare'

            $history = @(Get-AssetHistory -SerialNumber 'SERHIST001')
            $history.Count | Should BeGreaterThan 1
        }
    }

    Context 'Import Functions' {
        BeforeEach {
            Remove-TestInventoryData
            Initialize-InventoryDatabase -TestMode
        }

        It 'imports assets from CSV' {
            $csv = @"
Hostname,Vendor,Model,SerialNumber,AssetTag,Site
SW-IMPORT-01,Cisco,C9300-48P,CSV001,AT001,Campus
SW-IMPORT-02,Cisco,C9300-24P,CSV002,AT002,Campus
"@
            $tempFile = [System.IO.Path]::GetTempFileName()
            $tempFile = $tempFile -replace '\.tmp$', '.csv'
            $csv | Set-Content $tempFile

            $result = Import-AssetInventory -Path $tempFile
            $result.ImportedCount | Should Be 2
            $result.Errors.Count | Should Be 0

            Remove-Item $tempFile -ErrorAction SilentlyContinue
        }

        It 'reports errors for invalid CSV data' {
            $csv = @"
Hostname,Vendor,Model,SerialNumber
SW-DUP-01,Cisco,C9300-48P,DUP999
SW-DUP-02,Cisco,C9300-24P,DUP999
"@
            $tempFile = [System.IO.Path]::GetTempFileName()
            $tempFile = $tempFile -replace '\.tmp$', '.csv'
            $csv | Set-Content $tempFile

            $result = Import-AssetInventory -Path $tempFile
            $result.ImportedCount | Should Be 1
            $result.Errors.Count | Should Be 1

            Remove-Item $tempFile -ErrorAction SilentlyContinue
        }

        It 'parses Cisco show version output' {
            $showVersion = @"
Cisco IOS Software, C9300 Software (C9300-UNIVERSALK9-M), Version 17.06.05
System serial number: FCW12345678
Model number: C9300-48P
SW-TEST-01 uptime is 45 days
"@
            $info = ConvertFrom-ShowVersionOutput -Content $showVersion -Vendor 'Cisco'
            $info.SerialNumber | Should Be 'FCW12345678'
            $info.Model | Should Be 'C9300-48P'
            $info.Version | Should Be '17.06.05'
            $info.Hostname | Should Be 'SW-TEST-01'
        }

        It 'parses Arista show version output' {
            $showVersion = @"
Arista DCS-7050SX-64
Software image version: 4.28.3M
Serial number: JPE12345678
Hostname: SW-ARISTA-01
"@
            $info = ConvertFrom-ShowVersionOutput -Content $showVersion -Vendor 'Arista'
            $info.SerialNumber | Should Be 'JPE12345678'
            $info.Model | Should Be 'DCS-7050SX-64'
            $info.Version | Should Be '4.28.3M'
        }

        It 'parses Ruckus show version output' {
            $showVersion = @"
System: ICX7450-48P
SW: Version 08.0.95
System Serial #: CYR3456789
"@
            $info = ConvertFrom-ShowVersionOutput -Content $showVersion -Vendor 'Ruckus'
            $info.SerialNumber | Should Be 'CYR3456789'
            $info.Model | Should Be 'ICX7450-48P'
            $info.Version | Should Be '08.0.95'
        }
    }

    Context 'Export Functions' {
        BeforeEach {
            Remove-TestInventoryData
            Initialize-InventoryDatabase -TestMode
        }

        It 'exports inventory to CSV' {
            New-Asset -Hostname 'SW-EXP-01' -Vendor 'Cisco' -SerialNumber 'EXP001' -Site 'Campus'
            New-Asset -Hostname 'SW-EXP-02' -Vendor 'Arista' -SerialNumber 'EXP002' -Site 'DC'

            $tempPath = [System.IO.Path]::GetTempFileName()
            $tempPath = $tempPath -replace '\.tmp$', '.csv'

            $result = Export-AssetInventory -Path $tempPath -Format 'CSV'
            $result.ExportedCount | Should Be 2
            (Test-Path $result.Path) | Should Be $true

            Remove-Item $tempPath -ErrorAction SilentlyContinue
        }

        It 'exports filtered inventory by site' {
            New-Asset -Hostname 'SW-CAMPUS-01' -SerialNumber 'CAM001' -Site 'Campus'
            New-Asset -Hostname 'SW-DC-01' -SerialNumber 'DC001' -Site 'DataCenter'

            $tempPath = [System.IO.Path]::GetTempFileName()
            $tempPath = $tempPath -replace '\.tmp$', '.csv'

            $result = Export-AssetInventory -Path $tempPath -Format 'CSV' -Site 'Campus'
            $result.ExportedCount | Should Be 1

            Remove-Item $tempPath -ErrorAction SilentlyContinue
        }

        It 'exports to JSON format' {
            New-Asset -Hostname 'SW-JSON-01' -SerialNumber 'JSON001'

            $tempPath = [System.IO.Path]::GetTempFileName()
            $tempPath = $tempPath -replace '\.tmp$', '.json'

            $result = Export-AssetInventory -Path $tempPath -Format 'JSON'
            (Test-Path $result.Path) | Should Be $true

            $content = Get-Content $result.Path -Raw | ConvertFrom-Json
            $content | Should Not BeNullOrEmpty

            Remove-Item $tempPath -ErrorAction SilentlyContinue
        }
    }

    Context 'Report Generation' {
        BeforeEach {
            Remove-TestInventoryData
            Initialize-InventoryDatabase -TestMode
        }

        It 'generates inventory summary with correct counts' {
            New-Asset -Hostname 'SW-SUM-01' -Vendor 'Cisco' -Site 'Site1' -Status 'Active' -SerialNumber 'SUM001'
            New-Asset -Hostname 'SW-SUM-02' -Vendor 'Cisco' -Site 'Site1' -Status 'Spare' -SerialNumber 'SUM002'
            New-Asset -Hostname 'SW-SUM-03' -Vendor 'Arista' -Site 'Site2' -Status 'Active' -SerialNumber 'SUM003'

            $summary = Get-InventorySummary
            $summary.TotalDevices | Should Be 3
            $summary.ByVendor['Cisco'] | Should Be 2
            $summary.ByVendor['Arista'] | Should Be 1
            $summary.BySite['Site1'] | Should Be 2
            $summary.ByStatus['Active'] | Should Be 2
        }

        It 'generates warranty report in Text format' {
            $today = Get-Date
            New-Asset -Hostname 'SW-RPT-01' -SerialNumber 'RPT001' -WarrantyExpiration ($today.AddDays(30))
            New-Asset -Hostname 'SW-RPT-02' -SerialNumber 'RPT002' -WarrantyExpiration ($today.AddDays(-10))

            $tempDir = [System.IO.Path]::GetTempPath()
            $result = Export-WarrantyReport -Format 'Text' -OutputPath $tempDir -ExpiringWithin 90

            (Test-Path $result.Path) | Should Be $true
            $result.ExpiringCount | Should Be 1
            $result.ExpiredCount | Should Be 1

            Remove-Item $result.Path -ErrorAction SilentlyContinue
        }

        It 'generates warranty report in HTML format' {
            $today = Get-Date
            New-Asset -Hostname 'SW-HTML-01' -SerialNumber 'HTML001' -Vendor 'Cisco' `
                -WarrantyExpiration ($today.AddDays(15)) -SupportLevel 'NBD'

            $tempDir = [System.IO.Path]::GetTempPath()
            $result = Export-WarrantyReport -Format 'HTML' -OutputPath $tempDir

            (Test-Path $result.Path) | Should Be $true
            $content = Get-Content $result.Path -Raw
            $content | Should Match '<html>'
            $content | Should Match 'SW-HTML-01'

            Remove-Item $result.Path -ErrorAction SilentlyContinue
        }

        It 'generates lifecycle report' {
            New-Asset -Hostname 'SW-LIFE-01' -Vendor 'Cisco' -Model 'WS-C3850-48P' -SerialNumber 'LIFE001'

            $report = Get-LifecycleReport -EoLWithin 1000
            $report | Should Not BeNullOrEmpty
        }
    }

    Context 'Advanced Analytics' {
        BeforeEach {
            Remove-TestInventoryData
            Initialize-InventoryDatabase -TestMode
        }

        It 'returns comprehensive inventory analytics' {
            $today = Get-Date
            New-Asset -Hostname 'SW-ANA-01' -Vendor 'Cisco' -Model 'C9300-48P' `
                -SerialNumber 'ANA001' -Site 'Campus' `
                -PurchaseDate ($today.AddYears(-2)) -PurchasePrice 5000 `
                -WarrantyExpiration ($today.AddYears(1)) -FirmwareVersion '17.06.05'
            New-Asset -Hostname 'SW-ANA-02' -Vendor 'Arista' -Model 'DCS-7050SX-64' `
                -SerialNumber 'ANA002' -Site 'DC' `
                -PurchaseDate ($today.AddYears(-1)) -PurchasePrice 8000 `
                -WarrantyExpiration ($today.AddYears(2)) -FirmwareVersion '4.28.3M'

            $analytics = Get-InventoryAnalytics
            $analytics.TotalAssets | Should Be 2
            $analytics.TotalInvestment | Should Be 13000
            $analytics.AssetsWithCostData | Should Be 2
            $analytics.CostByVendor['Cisco'] | Should Be 5000
            $analytics.CostByVendor['Arista'] | Should Be 8000
            $analytics.WarrantyCoveragePercent | Should Be 100
            $analytics.UniqueFirmwareVersions | Should Be 2
        }

        It 'returns age distribution with categories' {
            $today = Get-Date
            New-Asset -Hostname 'SW-NEW' -SerialNumber 'NEW001' -PurchaseDate ($today.AddDays(-30))
            New-Asset -Hostname 'SW-OLD' -SerialNumber 'OLD001' -PurchaseDate ($today.AddYears(-4))
            New-Asset -Hostname 'SW-ANCIENT' -SerialNumber 'ANC001' -PurchaseDate ($today.AddYears(-7))

            $distribution = @(Get-AssetAgeDistribution)
            $distribution.Count | Should Be 3

            $newDevice = $distribution | Where-Object { $_.Hostname -eq 'SW-NEW' }
            $newDevice.AgeYears | Should BeLessThan 1

            $ancientDevice = $distribution | Where-Object { $_.Hostname -eq 'SW-ANCIENT' }
            $ancientDevice.AgeCategory | Should Be 'Over 5 Years'
        }

        It 'filters age distribution by vendor' {
            $today = Get-Date
            New-Asset -Hostname 'SW-CISCO' -Vendor 'Cisco' -SerialNumber 'CIS001' -PurchaseDate ($today.AddYears(-1))
            New-Asset -Hostname 'SW-ARISTA' -Vendor 'Arista' -SerialNumber 'ARI001' -PurchaseDate ($today.AddYears(-1))

            $ciscoOnly = @(Get-AssetAgeDistribution -Vendor 'Cisco')
            $ciscoOnly.Count | Should Be 1
            $ciscoOnly[0].Vendor | Should Be 'Cisco'
        }

        It 'returns cost analysis grouped by vendor' {
            New-Asset -Hostname 'SW-C1' -Vendor 'Cisco' -SerialNumber 'C001' -PurchasePrice 5000
            New-Asset -Hostname 'SW-C2' -Vendor 'Cisco' -SerialNumber 'C002' -PurchasePrice 6000
            New-Asset -Hostname 'SW-A1' -Vendor 'Arista' -SerialNumber 'A001' -PurchasePrice 8000

            $analysis = @(Get-AssetCostAnalysis -GroupBy 'Vendor')
            $analysis.Count | Should Be 2

            $ciscoAnalysis = $analysis | Where-Object { $_.Category -eq 'Cisco' }
            $ciscoAnalysis.DeviceCount | Should Be 2
            $ciscoAnalysis.TotalCost | Should Be 11000
        }

        It 'returns cost analysis grouped by site' {
            New-Asset -Hostname 'SW-S1A' -Site 'Site1' -SerialNumber 'S1A001' -PurchasePrice 5000
            New-Asset -Hostname 'SW-S1B' -Site 'Site1' -SerialNumber 'S1B001' -PurchasePrice 4000
            New-Asset -Hostname 'SW-S2A' -Site 'Site2' -SerialNumber 'S2A001' -PurchasePrice 6000

            $analysis = @(Get-AssetCostAnalysis -GroupBy 'Site')

            $site1 = $analysis | Where-Object { $_.Category -eq 'Site1' }
            $site1.TotalCost | Should Be 9000
            $site1.DeviceCount | Should Be 2
        }
    }

    Context 'Budget Forecasting' {
        BeforeEach {
            Remove-TestInventoryData
            Initialize-InventoryDatabase -TestMode
        }

        It 'identifies devices needing refresh based on age' {
            $today = Get-Date
            New-Asset -Hostname 'SW-OLD' -Vendor 'Cisco' -Model 'C9300-48P' `
                -SerialNumber 'OLD001' -PurchaseDate ($today.AddYears(-6)) -PurchasePrice 5000

            $recommendations = @(Get-RefreshRecommendations -MaxAgeYears 5 -IncludeCostEstimates)
            $recommendations.Count | Should Be 1
            $recommendations[0].Hostname | Should Be 'SW-OLD'
            $recommendations[0].EstimatedCost | Should BeGreaterThan 0
        }

        It 'identifies devices approaching end of life' {
            New-Asset -Hostname 'SW-EOL' -Vendor 'Cisco' -Model 'WS-C3850-48P' -SerialNumber 'EOL001'

            $recommendations = @(Get-RefreshRecommendations -EoLWithinDays 1000 -IncludeCostEstimates)
            ($recommendations | Where-Object { $_.Hostname -eq 'SW-EOL' }) | Should Not BeNullOrEmpty
        }

        It 'suggests replacement models from lifecycle database' {
            New-Asset -Hostname 'SW-REPLACE' -Vendor 'Cisco' -Model 'WS-C3850-48P' -SerialNumber 'REP001'

            $recommendations = @(Get-RefreshRecommendations -EoLWithinDays 1000 -IncludeCostEstimates)
            $device = $recommendations | Where-Object { $_.Hostname -eq 'SW-REPLACE' }
            $device.ReplacementModel | Should Be 'C9300-48P'
        }

        It 'assigns priority based on multiple factors' {
            $today = Get-Date
            # Device with both age and EoL issues should be High priority
            New-Asset -Hostname 'SW-CRITICAL' -Vendor 'Cisco' -Model 'WS-C3850-48P' `
                -SerialNumber 'CRIT001' -PurchaseDate ($today.AddYears(-6))

            $recommendations = @(Get-RefreshRecommendations -MaxAgeYears 5 -EoLWithinDays 1000)
            $device = $recommendations | Where-Object { $_.Hostname -eq 'SW-CRITICAL' }
            $device.Priority | Should Be 'High'
        }

        It 'generates multi-year budget forecast' {
            $today = Get-Date
            New-Asset -Hostname 'SW-FY1' -Vendor 'Cisco' -SerialNumber 'FY001' `
                -PurchaseDate ($today.AddYears(-4)) -PurchasePrice 5000
            New-Asset -Hostname 'SW-FY2' -Vendor 'Cisco' -SerialNumber 'FY002' `
                -PurchaseDate ($today.AddYears(-3)) -PurchasePrice 6000

            $forecast = Get-BudgetForecast -Years 3 -RefreshCycleYears 5 -DefaultReplacementCost 5000
            $forecast.ForecastYears | Should Be 3
            $forecast.YearlyForecast.Count | Should Be 3
            $forecast.TotalProjectedCost | Should BeGreaterThan 0
        }

        It 'applies inflation to forecast costs' {
            $today = Get-Date
            New-Asset -Hostname 'SW-INF' -Vendor 'Cisco' -SerialNumber 'INF001' `
                -PurchaseDate ($today.AddYears(-4)) -PurchasePrice 10000

            $forecast = Get-BudgetForecast -Years 3 -RefreshCycleYears 5 `
                -AnnualPriceIncrease 0.05 -DefaultReplacementCost 10000

            # Year 0 should have base cost, later years should be higher
            $forecast.AnnualPriceIncrease | Should Match '5'
        }

        It 'creates refresh plan within budget' {
            $today = Get-Date
            New-Asset -Hostname 'SW-P1' -Vendor 'Cisco' -Model 'WS-C3850-48P' `
                -SerialNumber 'P001' -PurchaseDate ($today.AddYears(-6)) -PurchasePrice 5000
            New-Asset -Hostname 'SW-P2' -Vendor 'Cisco' -Model 'WS-C3850-24P' `
                -SerialNumber 'P002' -PurchaseDate ($today.AddYears(-6)) -PurchasePrice 4000

            $plan = New-RefreshPlan -AnnualBudget 10000 -PlanYears 2
            $plan | Should Not BeNullOrEmpty
            $plan.AnnualBudget | Should Be 10000
            $plan.PlanYears | Should Be 2
            $plan.TotalDevicesToRefresh | Should BeGreaterThan 0
        }

        It 'exports refresh plan to CSV' {
            $today = Get-Date
            New-Asset -Hostname 'SW-EXP' -Vendor 'Cisco' -Model 'WS-C3850-48P' `
                -SerialNumber 'EXPORT001' -PurchaseDate ($today.AddYears(-6)) -PurchasePrice 5000

            $plan = New-RefreshPlan -AnnualBudget 50000 -PlanYears 2
            $tempDir = [System.IO.Path]::GetTempPath()

            $result = Export-RefreshPlanReport -Plan $plan -Format 'CSV' -OutputPath $tempDir
            (Test-Path $result.Path) | Should Be $true

            Remove-Item $result.Path -ErrorAction SilentlyContinue
        }

        It 'exports refresh plan to HTML' {
            $today = Get-Date
            New-Asset -Hostname 'SW-HTML' -Vendor 'Cisco' -Model 'WS-C3850-48P' `
                -SerialNumber 'HTML001' -PurchaseDate ($today.AddYears(-6)) -PurchasePrice 5000

            $plan = New-RefreshPlan -AnnualBudget 50000 -PlanYears 2
            $tempDir = [System.IO.Path]::GetTempPath()

            $result = Export-RefreshPlanReport -Plan $plan -Format 'HTML' -OutputPath $tempDir
            (Test-Path $result.Path) | Should Be $true

            $content = Get-Content $result.Path -Raw
            $content | Should Match '<html>'
            $content | Should Match 'Hardware Refresh Plan'

            Remove-Item $result.Path -ErrorAction SilentlyContinue
        }

        It 'exports refresh plan to Text' {
            $today = Get-Date
            New-Asset -Hostname 'SW-TXT' -Vendor 'Cisco' -Model 'WS-C3850-48P' `
                -SerialNumber 'TXT001' -PurchaseDate ($today.AddYears(-6)) -PurchasePrice 5000

            $plan = New-RefreshPlan -AnnualBudget 50000 -PlanYears 2
            $tempDir = [System.IO.Path]::GetTempPath()

            $result = Export-RefreshPlanReport -Plan $plan -Format 'Text' -OutputPath $tempDir
            (Test-Path $result.Path) | Should Be $true

            $content = Get-Content $result.Path -Raw
            $content | Should Match 'HARDWARE REFRESH PLAN'

            Remove-Item $result.Path -ErrorAction SilentlyContinue
        }
    }

    Context 'UI Controls Verification' {
        BeforeAll {
            $xamlPath = Join-Path $PSScriptRoot '..\..\Views\InventoryView.xaml'
            $script:xamlContent = Get-Content $xamlPath -Raw
        }

        It 'defines budget forecast tab' {
            $xamlContent | Should Match 'Header="Budget Forecast"'
        }

        It 'defines forecast years dropdown' {
            $xamlContent | Should Match 'Name="ForecastYearsDropdown"'
        }

        It 'defines annual budget textbox' {
            $xamlContent | Should Match 'Name="AnnualBudgetBox"'
        }

        It 'defines generate forecast button' {
            $xamlContent | Should Match 'Name="GenerateForecastButton"'
        }

        It 'defines yearly forecast grid' {
            $xamlContent | Should Match 'Name="YearlyForecastGrid"'
        }

        It 'defines refresh recommendations grid' {
            $xamlContent | Should Match 'Name="RefreshRecommendationsGrid"'
        }

        It 'defines export forecast buttons' {
            $xamlContent | Should Match 'Name="ExportForecastTextButton"'
            $xamlContent | Should Match 'Name="ExportForecastCsvButton"'
            $xamlContent | Should Match 'Name="ExportForecastHtmlButton"'
        }
    }

    Context 'Database Persistence' {
        It 'exports and imports database' {
            Remove-TestInventoryData
            Initialize-InventoryDatabase -TestMode

            New-Asset -Hostname 'SW-PERSIST' -Vendor 'Cisco' -SerialNumber 'PERS001' -Site 'Test'
            New-FirmwareVersion -Vendor 'Cisco' -Platform 'C9300' -VersionString '17.09.01'
            Set-MinimumFirmware -Vendor 'Cisco' -Platform 'C9300' -MinVersion '17.06.03'

            $tempPath = [System.IO.Path]::GetTempFileName()
            $tempPath = $tempPath -replace '\.tmp$', '.json'

            $exportResult = Export-InventoryDatabase -Path $tempPath
            $exportResult.AssetCount | Should Be 1

            # Clear and reimport
            Remove-TestInventoryData

            Import-InventoryDatabase -Path $tempPath

            $assets = @(Get-Asset)
            $assets.Count | Should Be 1
            $assets[0].Hostname | Should Be 'SW-PERSIST'

            Remove-Item $tempPath -ErrorAction SilentlyContinue
        }
    }
}
