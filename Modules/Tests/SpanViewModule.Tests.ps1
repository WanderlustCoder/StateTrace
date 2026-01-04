Set-StrictMode -Version Latest

Describe "SpanViewModule" {
    BeforeAll {
        Add-Type -AssemblyName PresentationFramework -ErrorAction Stop

        $baseDir = Split-Path $PSCommandPath
        $modulePath = Join-Path $baseDir "..\SpanViewModule.psm1"
        Import-Module (Resolve-Path $modulePath).Path -Force

        $filterPath = Join-Path $baseDir "..\FilterStateModule.psm1"
        Import-Module (Resolve-Path $filterPath).Path -Force

        $repoPath = Join-Path $baseDir "..\DeviceRepositoryModule.psm1"
        Import-Module (Resolve-Path $repoPath).Path -Force

        # LANDMARK: ST-D-004 span telemetry tests
        $telemetryPath = Join-Path $baseDir "..\TelemetryModule.psm1"
        Import-Module (Resolve-Path $telemetryPath).Path -Force
    }

    AfterAll {
        Remove-Module DeviceRepositoryModule -Force
        Remove-Module FilterStateModule -Force
        Remove-Module TelemetryModule -Force
        Remove-Module SpanViewModule -Force
    }

    BeforeEach {
        Mock -ModuleName SpanViewModule -CommandName 'FilterStateModule\Set-DropdownItems' {}

        # LANDMARK: ST-D-004 span telemetry tests
        $global:SpanTelemetryEvents = @()
        Mock -ModuleName SpanViewModule -CommandName 'TelemetryModule\Write-StTelemetryEvent' {
            param($Name, $Payload)
            $global:SpanTelemetryEvents += [pscustomobject]@{ Name = $Name; Payload = $Payload }
        }

        InModuleScope SpanViewModule {
            $dispatcher = New-Object psobject
            $dispatcher | Add-Member -MemberType ScriptMethod -Name CheckAccess -Value { $true } -Force
            $dispatcher | Add-Member -MemberType ScriptMethod -Name Invoke -Value {
                param($callback)
                & $callback
            } -Force

            $grid = [pscustomobject]@{
                ItemsSource = @()
                Tag         = $null
                Dispatcher  = $dispatcher
            }

            $dropdown = [pscustomobject]@{
                SelectedItem = $null
            }

            $refreshButton = [pscustomobject]@{}
            $statusLabel = [pscustomobject]@{ Text = '' }

            $view = New-Object psobject
            $view | Add-Member -MemberType ScriptMethod -Name FindName -Value {
                param($name)
                switch ($name) {
                    'SpanGrid'         { return $grid }
                    'VlanDropdown'     { return $dropdown }
                    'RefreshSpanButton'{ return $refreshButton }
                    'SpanStatusLabel'  { return $statusLabel }
                    default { return $null }
                }
            } -Force

            Set-SpanViewControls -View $view | Out-Null
            $script:SpanDispatcher   = $dispatcher
            $script:SpanLastHostname = $null
            $script:SpanLastRefresh  = $null
        }
    }

    It "binds spanning-tree rows and exposes them via snapshot" {
        InModuleScope SpanViewModule {
            $original = $null
            try {
                $original = (Get-Command Get-SpanningTreeInfo -ErrorAction SilentlyContinue)
                Set-Item Function:Get-SpanningTreeInfo -Value {
                    param([string]$Hostname)
                    $Hostname | Should Be 'LABS-A01-AS-01'
                    @(
                        [pscustomobject]@{ VLAN='100'; RootSwitch='RS1'; RootPort='Gi1/0/1'; Role='Root'; Upstream='UP1'; LastUpdated='2025-11-07 12:00:00' },
                        [pscustomobject]@{ VLAN='200'; RootSwitch='RS2'; RootPort='Gi1/0/2'; Role='Designated'; Upstream='UP2'; LastUpdated='2025-11-07 12:00:00' }
                    )
                }

                { Get-SpanInfo -Hostname 'LABS-A01-AS-01' } | Should Not Throw

                $script:SpanLastHostname | Should Be 'LABS-A01-AS-01'
                $script:SpanLastRefresh | Should Not BeNullOrEmpty

                $snapshot = Get-SpanViewSnapshot -IncludeRows -SampleCount 2
                $snapshot.RowCount | Should BeGreaterThan 0
                @($snapshot.SampleRows).Count | Should BeGreaterThan 0
                $snapshot.StatusText | Should Match 'Rows:'

                # LANDMARK: ST-D-004 span telemetry tests
                $spanInfo = $global:SpanTelemetryEvents | Where-Object { $_.Name -eq 'UserAction' -and $_.Payload.Action -eq 'SpanInfo' } | Select-Object -First 1
                $spanInfo | Should Not BeNullOrEmpty
                $spanInfo.Payload.Hostname | Should Be 'LABS-A01-AS-01'
                $spanInfo.Payload.Site | Should Be 'LABS'
                $spanInfo.Payload.RowsBound | Should BeGreaterThan 0

                $spanSnapshot = $global:SpanTelemetryEvents | Where-Object { $_.Name -eq 'UserAction' -and $_.Payload.Action -eq 'SpanSnapshot' } | Select-Object -First 1
                $spanSnapshot | Should Not BeNullOrEmpty
                $spanSnapshot.Payload.Hostname | Should Be 'LABS-A01-AS-01'
                $spanSnapshot.Payload.RowsBound | Should BeGreaterThan 0

                # LANDMARK: ST-D-007 span usage telemetry tests
                $spanUsage = $global:SpanTelemetryEvents | Where-Object { $_.Name -eq 'UserAction' -and $_.Payload.Action -eq 'SpanViewUsage' } | Select-Object -First 1
                $spanUsage | Should Not BeNullOrEmpty
                $spanUsage.Payload.Hostname | Should Be 'LABS-A01-AS-01'
                $spanUsage.Payload.RowsBound | Should BeGreaterThan 0
                $spanUsage.Payload.VlanCount | Should Be 2
            } finally {
                if ($original) {
                    Set-Item Function:Get-SpanningTreeInfo -Value $original.ScriptBlock
                } else {
                    Remove-Item Function:Get-SpanningTreeInfo -ErrorAction SilentlyContinue
                }
            }
        }
    }

    It "returns cached rows when grid controls cannot be read" {
        $snapshot = InModuleScope SpanViewModule {
            $rows = @(
                [pscustomobject]@{ VLAN='10'; RootSwitch='RS'; RootPort='Gi1/0/1'; Role='Root'; Upstream='UP' }
            )
            $script:SpanLastRows = $rows
            $script:SpanLastHostname = 'LABS-A01-AS-01'
            $script:SpanLastRefresh = Get-Date
            Get-SpanViewSnapshot -IncludeRows -SampleCount 1
        }

        $snapshot.ViewLoaded | Should Be $true
        $snapshot.RowCount | Should Be 1
        $snapshot.CachedRowCount | Should Be 1
        $snapshot.SelectedVlan | Should Be $null
        $snapshot.Hostname | Should Be 'LABS-A01-AS-01'
        $snapshot.UsedLastRows | Should Be $true
        @($snapshot.SampleRows).Count | Should Be 1
        $snapshot.SampleRows[0].VLAN | Should Be '10'
        $snapshot.StatusText | Should Match 'Rows:'
    }

    It "returns snapshot defaults when controls are unavailable" {
        $snapshot = InModuleScope SpanViewModule {
            $script:SpanGridControl = $null
            $script:SpanVlanDropdown = $null
            $script:SpanLastHostname = 'LABS-A01-AS-01'
            $script:SpanLastRefresh = Get-Date
            $script:SpanLastRows = @()
            Get-SpanViewSnapshot
        }

        $snapshot.ViewLoaded | Should Be $false
        $snapshot.RowCount | Should Be 0
        $snapshot.CachedRowCount | Should Be 0
        $snapshot.Hostname | Should Be 'LABS-A01-AS-01'
    }
}
