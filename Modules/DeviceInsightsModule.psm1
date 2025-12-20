Set-StrictMode -Version Latest

try { ViewStateService\Import-ViewStateServiceModule | Out-Null } catch { }
if (-not (Get-Variable -Scope Script -Name SearchRegexEnabled -ErrorAction SilentlyContinue)) {
    $script:SearchRegexEnabled = $false
}
if (-not (Get-Variable -Scope Global -Name InterfacesLoadAllowed -ErrorAction SilentlyContinue)) {
    $global:InterfacesLoadAllowed = $false
}

$script:InterfaceStringPropertyValueCmd = $null
$script:InterfaceSetPortRowDefaultsCmd = $null
$script:InsightsPortSortKeyCmd = $null

if (-not (Get-Variable -Scope Script -Name InsightsPortSortFallbackKey -ErrorAction SilentlyContinue)) {
    try { $script:InsightsPortSortFallbackKey = InterfaceCommon\Get-PortSortFallbackKey } catch { $script:InsightsPortSortFallbackKey = '99-UNK-99999-99999-99999-99999-99999' }
}

if (-not (Get-Variable -Scope Script -Name InsightsWorkerInitialized -ErrorAction SilentlyContinue)) {
    $script:InsightsWorkerInitialized = $false
}
if (-not (Get-Variable -Scope Script -Name InsightsWorkerRunspace -ErrorAction SilentlyContinue)) {
    $script:InsightsWorkerRunspace = $null
}
if (-not (Get-Variable -Scope Script -Name InsightsWorkerThread -ErrorAction SilentlyContinue)) {
    $script:InsightsWorkerThread = $null
}
if (-not (Get-Variable -Scope Script -Name InsightsWorkerQueue -ErrorAction SilentlyContinue)) {
    $script:InsightsWorkerQueue = $null
}
if (-not (Get-Variable -Scope Script -Name InsightsWorkerSignal -ErrorAction SilentlyContinue)) {
    $script:InsightsWorkerSignal = $null
}
if (-not (Get-Variable -Scope Script -Name InsightsRequestCounter -ErrorAction SilentlyContinue)) {
    $script:InsightsRequestCounter = 0
}
if (-not (Get-Variable -Scope Script -Name InsightsLatestRequestId -ErrorAction SilentlyContinue)) {
    $script:InsightsLatestRequestId = 0
}
if (-not (Get-Variable -Scope Script -Name InsightsApplyCounter -ErrorAction SilentlyContinue)) {
    $script:InsightsApplyCounter = 0
}

function script:Get-InterfaceStringPropertyValueCommand {
    [CmdletBinding()]
    param()

    $cmd = $script:InterfaceStringPropertyValueCmd
    if ($cmd) { return $cmd }

    try { $cmd = Get-Command -Name 'InterfaceCommon\Get-StringPropertyValue' -ErrorAction SilentlyContinue } catch { $cmd = $null }
    if ($cmd) { $script:InterfaceStringPropertyValueCmd = $cmd }
    return $cmd
}

function script:Get-InterfaceSetPortRowDefaultsCommand {
    [CmdletBinding()]
    param()

    $cmd = $script:InterfaceSetPortRowDefaultsCmd
    if ($cmd) { return $cmd }

    try { $cmd = Get-Command -Name 'InterfaceCommon\Set-PortRowDefaults' -ErrorAction SilentlyContinue } catch { $cmd = $null }
    if ($cmd) { $script:InterfaceSetPortRowDefaultsCmd = $cmd }
    return $cmd
}

function Write-InsightsDebug {
    [CmdletBinding()]
    param([string]$Message)

    $emit = $false
    try { $emit = [bool]$global:StateTraceDebug } catch { $emit = $false }
    if (-not $emit) { return }

    try { Write-Diag $Message } catch [System.Management.Automation.CommandNotFoundException] {
        try { Write-Verbose $Message } catch { }
    } catch {
        try { Write-Verbose $Message } catch { }
    }
}

function script:Get-InsightsPortSortKeyCommand {
    [CmdletBinding()]
    param()

    $cmd = $script:InsightsPortSortKeyCmd
    if ($cmd) { return $cmd }

    try { $cmd = Get-Command -Name 'InterfaceModule\Get-PortSortKey' -ErrorAction SilentlyContinue } catch { $cmd = $null }
    if (-not $cmd) {
        $portNormPath = Join-Path $PSScriptRoot 'PortNormalization.psm1'
        if (Test-Path -LiteralPath $portNormPath) {
            try { Import-Module -Name $portNormPath -Prefix 'PortNorm' -Force -Global -ErrorAction Stop | Out-Null } catch { }
        }
        try { $cmd = Get-Command -Name 'Get-PortNormPortSortKey' -ErrorAction SilentlyContinue } catch { $cmd = $null }
    }

    if ($cmd) { $script:InsightsPortSortKeyCmd = $cmd }
    return $cmd
}

function script:Get-InsightsHostnameValue {
    [CmdletBinding()]
    param([object]$Row)

    if ($null -eq $Row) { return '' }

    $hostname = ''
    try { if ($Row.PSObject.Properties['Hostname']) { $hostname = '' + $Row.Hostname } } catch { $hostname = '' }
    if (-not $hostname) {
        try { if ($Row.PSObject.Properties['HostName']) { $hostname = '' + $Row.HostName } } catch { $hostname = '' }
    }
    return $hostname
}

function script:Get-InsightsPortSortKey {
    [CmdletBinding()]
    param([object]$Row)

    if ($null -eq $Row) { return $script:InsightsPortSortFallbackKey }

    $portSort = ''
    try { if ($Row.PSObject.Properties['PortSort']) { $portSort = '' + $Row.PortSort } } catch { $portSort = '' }
    if (-not [string]::IsNullOrWhiteSpace($portSort)) { return $portSort }

    $portValue = ''
    try { if ($Row.PSObject.Properties['Port']) { $portValue = '' + $Row.Port } } catch { $portValue = '' }
    if ([string]::IsNullOrWhiteSpace($portValue)) { return $script:InsightsPortSortFallbackKey }

    $cmd = script:Get-InsightsPortSortKeyCommand
    if ($cmd) {
        try { return (& $cmd -Port $portValue) } catch { }
    }

    return $script:InsightsPortSortFallbackKey
}

function script:Sort-InsightsRowsByPort {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.Generic.List[object]]$Rows
    )

    if (-not $Rows -or $Rows.Count -le 1) { return $Rows }

    $hostOrder = New-Object 'System.Collections.Generic.Dictionary[string,int]' ([System.StringComparer]::OrdinalIgnoreCase)
    $index = 0
    foreach ($row in $Rows) {
        if (-not $row) { continue }
        $hostValue = script:Get-InsightsHostnameValue -Row $row
        if ([string]::IsNullOrWhiteSpace($hostValue)) { continue }
        if (-not $hostOrder.ContainsKey($hostValue)) {
            $hostOrder[$hostValue] = $index
            $index++
        }
    }

    $comparison = [System.Comparison[object]]{
        param($a, $b)

        $hostA = script:Get-InsightsHostnameValue -Row $a
        $hostB = script:Get-InsightsHostnameValue -Row $b

        $indexA = [int]::MaxValue
        $indexB = [int]::MaxValue
        if (-not [string]::IsNullOrWhiteSpace($hostA)) {
            $tmpA = 0
            if ($hostOrder.TryGetValue($hostA, [ref]$tmpA)) { $indexA = $tmpA }
        }
        if (-not [string]::IsNullOrWhiteSpace($hostB)) {
            $tmpB = 0
            if ($hostOrder.TryGetValue($hostB, [ref]$tmpB)) { $indexB = $tmpB }
        }

        if ($indexA -ne $indexB) { return ($indexA - $indexB) }

        $portKeyA = script:Get-InsightsPortSortKey -Row $a
        $portKeyB = script:Get-InsightsPortSortKey -Row $b
        $portCompare = [System.StringComparer]::OrdinalIgnoreCase.Compare($portKeyA, $portKeyB)
        if ($portCompare -ne 0) { return $portCompare }

        $portA = ''
        $portB = ''
        try { if ($a -and $a.PSObject.Properties['Port']) { $portA = '' + $a.Port } } catch { $portA = '' }
        try { if ($b -and $b.PSObject.Properties['Port']) { $portB = '' + $b.Port } } catch { $portB = '' }

        return [System.StringComparer]::OrdinalIgnoreCase.Compare($portA, $portB)
    }

    try { $Rows.Sort($comparison) } catch { }

    return $Rows
}

function script:New-InsightsSortedList {
    [CmdletBinding()]
    param([object]$Rows)

    $list = [System.Collections.Generic.List[object]]::new()
    $copied = $false
    if ($Rows) {
        try {
            foreach ($row in $Rows) {
                if ($row) { [void]$list.Add($row) }
            }
            $copied = $true
        } catch {
            $copied = $false
        }
    }

    if (-not $copied) {
        return $Rows
    }

    if ($list.Count -gt 1) {
        script:Sort-InsightsRowsByPort -Rows $list | Out-Null
    }

    return $list
}

function script:Get-DeviceInsightsFilterContext {
    [CmdletBinding()]
    param()

    $loc = $null
    try { $loc = FilterStateModule\Get-SelectedLocation } catch { $loc = $null }

    $siteSel = if ($loc) { $loc.Site } else { $null }
    $zoneSel = if ($loc) { $loc.Zone } else { $null }
    $bldSel  = if ($loc) { $loc.Building } else { $null }
    $roomSel = if ($loc) { $loc.Room } else { $null }

    $zoneToLoad = ''
    if ($zoneSel -and -not [string]::IsNullOrWhiteSpace($zoneSel) -and -not [System.StringComparer]::OrdinalIgnoreCase.Equals($zoneSel, 'All Zones')) {
        $zoneToLoad = $zoneSel
    }

    return [pscustomobject]@{
        Site       = $siteSel
        Zone       = $zoneSel
        Building   = $bldSel
        Room       = $roomSel
        ZoneToLoad = $zoneToLoad
    }
}

function script:Update-DeviceInsightsSiteZoneCache {
    [CmdletBinding()]
    param(
        [string]$Site,
        [string]$ZoneToLoad
    )

    if ([string]::IsNullOrWhiteSpace($Site)) { return }
    if ([System.StringComparer]::OrdinalIgnoreCase.Equals($Site, 'All Sites')) { return }

    try { DeviceRepositoryModule\Update-SiteZoneCache -Site $Site -Zone $ZoneToLoad | Out-Null } catch {}
}

function Get-SearchRegexEnabled {
    [CmdletBinding()]
    param()

    return [bool]$script:SearchRegexEnabled
}

function Set-SearchRegexEnabled {
    [CmdletBinding()]
    param([Parameter(Mandatory)][bool]$Enabled)

    $script:SearchRegexEnabled = [bool]$Enabled
}

function Update-SearchResults {
    [CmdletBinding()]
    param(
        [string]$Term,
        [object]$Interfaces
    )

    if (-not $global:InterfacesLoadAllowed) {
        Write-Verbose '[DeviceInsights] Interfaces not allowed yet; skipping search.'
        return @()
    }

    $context = script:Get-DeviceInsightsFilterContext
    $siteSel = $context.Site
    $zoneSel = $context.Zone
    $bldSel  = $context.Building
    $roomSel = $context.Room
    $zoneToLoad = $context.ZoneToLoad

    $statusFilterVal = 'All'
    $authFilterVal   = 'All'
    try {
        $searchHostCtrl = $global:window.FindName('SearchInterfacesHost')
        if ($searchHostCtrl) {
            $view = $searchHostCtrl.Content
            if ($view) {
                $statusCtrl = $view.FindName('StatusFilter')
                $authCtrl   = $view.FindName('AuthFilter')
                if ($statusCtrl -and $statusCtrl.SelectedItem) {
                    $statusFilterVal = $statusCtrl.SelectedItem.Content
                }
                if ($authCtrl -and $authCtrl.SelectedItem) {
                    $authFilterVal = $authCtrl.SelectedItem.Content
                }
            }
        }
    } catch {}

    $termEmpty = [string]::IsNullOrWhiteSpace($Term)

    $interfaces = $null
    $interfaceCount = 0

    if ($PSBoundParameters.ContainsKey('Interfaces') -and $Interfaces) {
        $interfaces = $Interfaces
    } else {
        try { $interfaces = $global:AllInterfaces } catch { $interfaces = $null }
    }
    try { $interfaceCount = ViewStateService\Get-SequenceCount -Value $interfaces } catch { $interfaceCount = 0 }
    if ($interfaceCount -le 0) {
        $interfaces = ViewStateService\Get-InterfacesForContext -Site $siteSel -ZoneSelection $zoneSel -ZoneToLoad $zoneToLoad -Building $bldSel -Room $roomSel
    }
    $results   = [System.Collections.Generic.List[object]]::new()

    foreach ($row in $interfaces) {
        if (-not $row) { continue }

        if ($statusFilterVal -ne 'All') {
            $st = '' + $row.Status
            if ($statusFilterVal -eq 'Up') {
                if (-not ([System.StringComparer]::OrdinalIgnoreCase.Equals($st, 'up') -or
                          [System.StringComparer]::OrdinalIgnoreCase.Equals($st, 'connected'))) {
                    continue
                }
            } elseif ($statusFilterVal -eq 'Down') {
                if (-not ([System.StringComparer]::OrdinalIgnoreCase.Equals($st, 'down') -or
                          [System.StringComparer]::OrdinalIgnoreCase.Equals($st, 'notconnect'))) {
                    continue
                }
            }
        }

        if ($authFilterVal -ne 'All') {
            $as = '' + $row.AuthState
            if ($authFilterVal -eq 'Authorized') {
                if (-not [System.StringComparer]::OrdinalIgnoreCase.Equals($as, 'authorized')) { continue }
            } elseif ($authFilterVal -eq 'Unauthorized') {
                if ([System.StringComparer]::OrdinalIgnoreCase.Equals($as, 'authorized')) { continue }
            }
        }

        if (-not $termEmpty) {
            if ($script:SearchRegexEnabled) {
                $matched = $false
                try {
                    if ( ('' + $row.Port) -match $Term -or
                         ('' + $row.Name) -match $Term -or
                         ('' + $row.LearnedMACs) -match $Term -or
                         ('' + $row.AuthClientMAC) -match $Term ) {
                        $matched = $true
                    }
                } catch {}
                if (-not $matched) {
                    $q = $Term
                    if (-not ((('' + $row.Port).IndexOf($q, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) -or
                              (('' + $row.Name).IndexOf($q, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) -or
                              (('' + $row.LearnedMACs).IndexOf($q, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) -or
                              (('' + $row.AuthClientMAC).IndexOf($q, [System.StringComparison]::OrdinalIgnoreCase) -ge 0))) {
                        continue
                    }
                }
            } else {
                $q = $Term
                if (-not ((('' + $row.Port).IndexOf($q, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) -or
                          (('' + $row.Name).IndexOf($q, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) -or
                          (('' + $row.LearnedMACs).IndexOf($q, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) -or
                          (('' + $row.AuthClientMAC).IndexOf($q, [System.StringComparison]::OrdinalIgnoreCase) -ge 0))) {
                    continue
                }
            }
        }

        [void]$results.Add($row)
    }

    return ,(script:New-InsightsSortedList -Rows $results)
}

function Update-Summary {
    [CmdletBinding()]
    param(
        [object]$Interfaces
    )

    if (-not $global:InterfacesLoadAllowed) {
        Write-Verbose '[DeviceInsights] Interfaces not allowed yet; skipping summary.'
        return
    }

    $context = script:Get-DeviceInsightsFilterContext
    $siteSel = $context.Site
    $zoneSel = $context.Zone
    $bldSel  = $context.Building
    $roomSel = $context.Room
    $zoneToLoad = $context.ZoneToLoad

    $interfaces = $null
    $interfaceCount = 0

    if ($PSBoundParameters.ContainsKey('Interfaces') -and $Interfaces) {
        $interfaces = $Interfaces
    } else {
        try { $interfaces = $global:AllInterfaces } catch { $interfaces = $null }
    }
    try { $interfaceCount = ViewStateService\Get-SequenceCount -Value $interfaces } catch { $interfaceCount = 0 }
    if ($interfaceCount -le 0) {
        script:Update-DeviceInsightsSiteZoneCache -Site $siteSel -ZoneToLoad $zoneToLoad
        $interfaces = ViewStateService\Get-InterfacesForContext -Site $siteSel -ZoneSelection $zoneSel -ZoneToLoad $zoneToLoad -Building $bldSel -Room $roomSel
    }
    try {
        $locSite = if ($siteSel) { '' + $siteSel } else { '' }
        $locZone = if ($zoneSel) { '' + $zoneSel } else { '' }
        $locBuilding = if ($bldSel) { '' + $bldSel } else { '' }
        $locRoom = if ($roomSel) { '' + $roomSel } else { '' }
        $locText = ("Site={0};Zone={1};Building={2};Room={3}" -f $locSite, $locZone, $locBuilding, $locRoom)
        $ifaceCount = ViewStateService\Get-SequenceCount -Value $interfaces
        Write-Diag ("Update-Summary context | Location={0} | InterfaceCount={1}" -f $locText, $ifaceCount)
    } catch {}
    if (-not $interfaces) { $interfaces = @() }

    $stringPropertyCmd = script:Get-InterfaceStringPropertyValueCommand
    $setDefaultsCmd = script:Get-InterfaceSetPortRowDefaultsCommand

    foreach ($row in $interfaces) {
        if (-not $row) { continue }
        try {
            $hostnameValue = ''
            if (-not $row.PSObject.Properties['Hostname']) {
                try {
                    if ($stringPropertyCmd) {
                        $hostnameValue = & $stringPropertyCmd -InputObject $row -PropertyNames @('Hostname','HostName')
                    }
                } catch { $hostnameValue = '' }
                if (-not $hostnameValue) {
                    try {
                        if ($row.PSObject.Properties['HostName']) { $hostnameValue = '' + $row.HostName }
                    } catch { $hostnameValue = '' }
                }
            }

            if ($setDefaultsCmd) {
                try { & $setDefaultsCmd -Row $row -Hostname $hostnameValue | Out-Null } catch { }
            } else {
                if (-not $row.PSObject.Properties['Hostname']) {
                    $row | Add-Member -NotePropertyName Hostname -NotePropertyValue $hostnameValue -ErrorAction SilentlyContinue
                }
                if (-not $row.PSObject.Properties['IsSelected']) {
                    $row | Add-Member -NotePropertyName IsSelected -NotePropertyValue $false -ErrorAction SilentlyContinue
                }
            }
        } catch {}
    }

    $global:AllInterfaces = $interfaces

    $deviceSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($row in $interfaces) {
        if ($row -and $row.PSObject.Properties['Hostname']) {
            $hostname = '' + $row.Hostname
            if (-not [string]::IsNullOrWhiteSpace($hostname)) { [void]$deviceSet.Add($hostname) }
        }
    }

    $devCount = $deviceSet.Count
    $intCount = $interfaces.Count
    $upCount = 0; $downCount = 0; $authCount = 0; $unauthCount = 0
    $vlanSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($row in $interfaces) {
        if (-not $row) { continue }
        $status = '' + $row.Status
        if ($status) {
            switch -Regex ($status) {
                '(?i)^(up|connected)$'    { $upCount++; break }
                '(?i)^(down|notconnect)$' { $downCount++; break }
            }
        }
        $authState = '' + $row.AuthState
        if ($authState) {
            if ([System.StringComparer]::OrdinalIgnoreCase.Equals($authState, 'authorized')) { $authCount++ } else { $unauthCount++ }
        } else {
            $unauthCount++
        }
        $vlanValue = ''
        try { $vlanValue = '' + $row.VLAN } catch { $vlanValue = '' }
        if (-not [string]::IsNullOrWhiteSpace($vlanValue)) { [void]$vlanSet.Add($vlanValue) }
    }
    $uniqueCount = $vlanSet.Count

    $summaryVar = $null
    try {
        $summaryVar = Get-Variable -Name summaryView -Scope Global -ErrorAction Stop
    } catch {
        try { Write-Diag ("Update-Summary skipped | Reason=SummaryViewMissing") } catch {}
        return
    }

    $sv = $summaryVar.Value
    if (-not $sv) { return }

    try {
        ($sv.FindName("SummaryDevicesCount")).Text      = $devCount.ToString()
        ($sv.FindName("SummaryInterfacesCount")).Text   = $intCount.ToString()
        ($sv.FindName("SummaryUpCount")).Text           = $upCount.ToString()
        ($sv.FindName("SummaryDownCount")).Text         = $downCount.ToString()
        ($sv.FindName("SummaryAuthorizedCount")).Text   = $authCount.ToString()
        ($sv.FindName("SummaryUnauthorizedCount")).Text = $unauthCount.ToString()
        ($sv.FindName("SummaryUniqueVlansCount")).Text  = $uniqueCount.ToString()
        $ratio = if ($intCount -gt 0) { [math]::Round(($upCount / $intCount) * 100, 1) } else { 0 }
        ($sv.FindName("SummaryExtra")).Text = "Up %: $ratio%"
        try { Write-Diag ("Update-Summary metrics | Devices={0} | Interfaces={1} | Up={2} | Down={3} | Auth={4} | Unauth={5} | UniqueVlans={6} | UpPct={7}" -f $devCount, $intCount, $upCount, $downCount, $authCount, $unauthCount, $uniqueCount, $ratio) } catch {}
    } catch {}
}

function Update-Alerts {
    [CmdletBinding()]
    param(
        [object]$Interfaces
    )

    if (-not $global:InterfacesLoadAllowed) {
        Write-Verbose '[DeviceInsights] Interfaces not allowed yet; skipping alerts.'
        return
    }

    $context = script:Get-DeviceInsightsFilterContext
    $siteSel = $context.Site
    $zoneSel = $context.Zone
    $bldSel  = $context.Building
    $roomSel = $context.Room
    $zoneToLoad = $context.ZoneToLoad

    $interfaces = $null
    $interfaceCount = 0

    if ($PSBoundParameters.ContainsKey('Interfaces') -and $Interfaces) {
        $interfaces = $Interfaces
    } else {
        try { $interfaces = $global:AllInterfaces } catch { $interfaces = $null }
    }
    try { $interfaceCount = ViewStateService\Get-SequenceCount -Value $interfaces } catch { $interfaceCount = 0 }
    if ($interfaceCount -le 0) {
        script:Update-DeviceInsightsSiteZoneCache -Site $siteSel -ZoneToLoad $zoneToLoad
        $interfaces = ViewStateService\Get-InterfacesForContext -Site $siteSel -ZoneSelection $zoneSel -ZoneToLoad $zoneToLoad -Building $bldSel -Room $roomSel
    }
    if (-not $interfaces) { $interfaces = @() }

    $alerts = [System.Collections.Generic.List[object]]::new()
    foreach ($row in $interfaces) {
        if (-not $row) { continue }

        $reasons = [System.Collections.Generic.List[string]]::new()
        $status = '' + $row.Status
        if ($status) {
            if ([System.StringComparer]::OrdinalIgnoreCase.Equals($status, 'down') -or
                [System.StringComparer]::OrdinalIgnoreCase.Equals($status, 'notconnect')) {
                [void]$reasons.Add('Port down')
            }
        }
        $duplex = '' + $row.Duplex
        if ($duplex -and ($duplex -match '(?i)half')) {
            [void]$reasons.Add('Half duplex')
        }
        $authState = '' + $row.AuthState
        if ($authState) {
            if (-not [System.StringComparer]::OrdinalIgnoreCase.Equals($authState, 'authorized')) { [void]$reasons.Add('Unauthorized') }
        } else {
            [void]$reasons.Add('Unauthorized')
        }

        if ($reasons.Count -gt 0) {
            $alert = [PSCustomObject]@{
                Hostname  = $row.Hostname
                Port      = $row.Port
                Name      = $row.Name
                Status    = $row.Status
                VLAN      = $row.VLAN
                Duplex    = $row.Duplex
                AuthState = $row.AuthState
                Reason    = ($reasons -join '; ')
            }
            [void]$alerts.Add($alert)
        }
    }

    $global:AlertsList = script:New-InsightsSortedList -Rows $alerts
    if ($global:alertsView) {
        try {
            $grid = $global:alertsView.FindName('AlertsGrid')
            if ($grid) { $grid.ItemsSource = $global:AlertsList }
        } catch {}
    }

}

function Update-SearchGrid {
    [CmdletBinding()]
    param(
        [object]$Interfaces
    )

    if (-not $global:InterfacesLoadAllowed) {
        Write-Verbose '[DeviceInsights] Interfaces not allowed yet; skipping search grid.'
        return
    }

    $searchHostCtrl = $global:window.FindName('SearchInterfacesHost')
    if (-not $searchHostCtrl) { return }
    $view = $searchHostCtrl.Content
    if (-not $view) { return }
    $gridCtrl = $view.FindName('SearchInterfacesGrid')
    $boxCtrl  = $view.FindName('SearchBox')
    if (-not $gridCtrl -or -not $boxCtrl) { return }

    $term = $boxCtrl.Text
    $results = Update-SearchResults -Term $term -Interfaces $Interfaces
    $resultList = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $results) {
        if ($item) { [void]$resultList.Add($item) }
    }
    if ($resultList.Count -gt 1) {
        script:Sort-InsightsRowsByPort -Rows $resultList | Out-Null
    }

    $gridCtrl.ItemsSource = $resultList
}

function script:Ensure-PowerShellInvokeThreadStartFactory {
    [CmdletBinding()]
    param()

    if ('StateTrace.Threading.PowerShellInvokeThreadStartFactory' -as [type]) { return $true }

    try {
        Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Threading;

namespace StateTrace.Threading
{
    public static class PowerShellInvokeThreadStartFactory
    {
        public static ThreadStart Create(PowerShell ps, string host)
        {
            if (ps == null)
            {
                throw new ArgumentNullException("ps");
            }

            return delegate
            {
                var runspace = ps.Runspace;
                var previous = Runspace.DefaultRunspace;

                try
                {
                    if (runspace != null)
                    {
                        var state = runspace.RunspaceStateInfo.State;
                        if (state == RunspaceState.BeforeOpen)
                        {
                            runspace.Open();
                        }

                        Runspace.DefaultRunspace = runspace;
                    }

                    ps.Invoke();
                }
                catch
                {
                }
                finally
                {
                    Runspace.DefaultRunspace = previous;
                }
            };
        }
    }
}
'@
        return $true
    } catch {
        return $false
    }
}

function script:Get-InsightsWorkerRunspace {
    [CmdletBinding()]
    param()

    if ($script:InsightsWorkerRunspace) {
        try {
            $state = $script:InsightsWorkerRunspace.RunspaceStateInfo.State
            if ($state -eq [System.Management.Automation.Runspaces.RunspaceState]::Opened -or
                $state -eq [System.Management.Automation.Runspaces.RunspaceState]::BeforeOpen -or
                $state -eq [System.Management.Automation.Runspaces.RunspaceState]::Opening -or
                $state -eq [System.Management.Automation.Runspaces.RunspaceState]::Connecting) {
                return $script:InsightsWorkerRunspace
            }
        } catch { }
        try { $script:InsightsWorkerRunspace.Dispose() } catch { }
        $script:InsightsWorkerRunspace = $null
    }

    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    try { $iss.LanguageMode = [System.Management.Automation.PSLanguageMode]::FullLanguage } catch { }
    $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($iss)
    $rs.ThreadOptions  = [System.Management.Automation.Runspaces.PSThreadOptions]::ReuseThread
    $rs.ApartmentState = [System.Threading.ApartmentState]::STA

    try {
        $msg = "[DeviceInsights] Insights worker runspace created (deferred open) | Id={0} | LangMode={1}" -f $rs.Id, $iss.LanguageMode
        try { Write-Diag $msg } catch [System.Management.Automation.CommandNotFoundException] { Write-Verbose $msg } catch { }
    } catch { }

    $script:InsightsWorkerRunspace = $rs
    return $script:InsightsWorkerRunspace
}

function script:Ensure-InsightsWorker {
    [CmdletBinding()]
    param()

    $emitInitVerbose = $false
    try { if ($global:StateTraceDebug) { $emitInitVerbose = $true } } catch { $emitInitVerbose = $false }
    if ($emitInitVerbose) {
        try {
            Write-Verbose ("[DeviceInsights] Ensure-InsightsWorker stage=Enter | ThreadId={0}" -f [System.Threading.Thread]::CurrentThread.ManagedThreadId)
        } catch { }
    }

    if ($script:InsightsWorkerInitialized -and $script:InsightsWorkerThread) {
        try {
            if ($script:InsightsWorkerThread.IsAlive) { return $true }
        } catch { }

        try {
            $msg = "[DeviceInsights] Insights worker thread not alive; resetting initialization."
            try { Write-Diag $msg } catch [System.Management.Automation.CommandNotFoundException] { Write-Verbose $msg } catch { }
        } catch { }

        $script:InsightsWorkerInitialized = $false
        $script:InsightsWorkerThread = $null
    }

    $rs = script:Get-InsightsWorkerRunspace
    if (-not $rs) { return $false }

    if ($emitInitVerbose) {
        try {
            Write-Verbose ("[DeviceInsights] Ensure-InsightsWorker stage=GotRunspace | RunspaceId={0} | State={1}" -f $rs.Id, $rs.RunspaceStateInfo.State)
        } catch { }
    }

    if (-not (script:Ensure-PowerShellInvokeThreadStartFactory)) { return $false }

    if ($emitInitVerbose) {
        try { Write-Verbose "[DeviceInsights] Ensure-InsightsWorker stage=ThreadStartFactoryReady" } catch { }
    }

    if (-not $script:InsightsWorkerQueue) {
        $script:InsightsWorkerQueue = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
    }
    if (-not $script:InsightsWorkerSignal) {
        $script:InsightsWorkerSignal = New-Object System.Threading.AutoResetEvent $false
    }

    if ($emitInitVerbose) {
        try { Write-Verbose "[DeviceInsights] Ensure-InsightsWorker stage=QueueReady" } catch { }
    }

    $modulesRoot = $PSScriptRoot
    $telemetryModulePath = Join-Path $modulesRoot 'TelemetryModule.psm1'
    $databaseModulePath = Join-Path $modulesRoot 'DatabaseModule.psm1'
    $repoModulePath = Join-Path $modulesRoot 'DeviceRepositoryModule.psm1'
    $templatesModulePath = Join-Path $modulesRoot 'TemplatesModule.psm1'
    $interfaceModulePath = Join-Path $modulesRoot 'InterfaceModule.psm1'

    $queueRef = $script:InsightsWorkerQueue
    $signalRef = $script:InsightsWorkerSignal

    if ($emitInitVerbose) {
        try { Write-Verbose "[DeviceInsights] Ensure-InsightsWorker stage=BeforeThreadScript" } catch { }
    }

    $threadScript = {
        param(
            [System.Collections.Concurrent.ConcurrentQueue[object]]$queueRef,
            [System.Threading.AutoResetEvent]$signalRef,
            [string]$telemetryModulePath,
            [string]$databaseModulePath,
            [string]$repoModulePath,
            [string]$templatesModulePath,
            [string]$interfaceModulePath
        )

        $modulesLoaded = $false

        $queueLocal = $queueRef
        $signalLocal = $signalRef

        $equalsIgnoreCase = [System.StringComparer]::OrdinalIgnoreCase

        while ($true) {
            $item = $null
            $request = $null
            $latestRequest = $null
            $searchRequest = $null
            $includeSearch = $false
            $includeSummary = $false
            $includeAlerts = $false
            # Drain to the latest request while merging view flags; preserve the newest search filter context.
            try {
                while ($queueLocal.TryDequeue([ref]$item)) {
                    $candidate = $item
                    if (-not $candidate) { continue }
                    $latestRequest = $candidate

                    $candidateSearch = $false
                    $candidateSummary = $false
                    $candidateAlerts = $false
                    try { $candidateSearch = [bool]$candidate.IncludeSearch } catch { $candidateSearch = $false }
                    try { $candidateSummary = [bool]$candidate.IncludeSummary } catch { $candidateSummary = $false }
                    try { $candidateAlerts = [bool]$candidate.IncludeAlerts } catch { $candidateAlerts = $false }

                    if ($candidateSearch) {
                        $includeSearch = $true
                        $searchRequest = $candidate
                    }
                    if ($candidateSummary) { $includeSummary = $true }
                    if ($candidateAlerts) { $includeAlerts = $true }
                }
            } catch {
                $latestRequest = $null
            }

            $request = $latestRequest
            if (-not $request) {
                try { $null = $signalLocal.WaitOne() } catch { }
                continue
            }

            $interfaces = $request.Interfaces
            if (-not $interfaces) { $interfaces = @() }

            $requestSiteToLoad = ''
            try { $requestSiteToLoad = '' + $request.SiteToLoad } catch { $requestSiteToLoad = '' }

            $loadedInterfacesPayload = $null
            $interfaceLoadMs = $null
            $interfaceLoadSite = $null

            $loadInterfaces = $false
            try { $loadInterfaces = [bool]$request.LoadInterfaces } catch { $loadInterfaces = $false }
            if ($loadInterfaces) {
                $ifaceCount = 0
                try {
                    if ($interfaces -is [System.Collections.ICollection]) {
                        $ifaceCount = [int]$interfaces.Count
                    } else {
                        $ifaceCount = @($interfaces).Count
                    }
                } catch { $ifaceCount = 0 }

                if ($ifaceCount -le 0) {
                    if (-not $modulesLoaded) {
                        try {
                            if (Test-Path -LiteralPath $telemetryModulePath) { Import-Module -Name $telemetryModulePath -Global -Force -ErrorAction Stop | Out-Null }
                        } catch { }
                        try {
                            if (Test-Path -LiteralPath $databaseModulePath) { Import-Module -Name $databaseModulePath -Global -Force -ErrorAction Stop | Out-Null }
                        } catch { }
                        try {
                            if (Test-Path -LiteralPath $repoModulePath) { Import-Module -Name $repoModulePath -Global -Force -ErrorAction Stop | Out-Null }
                        } catch { }
                        try {
                            if (Test-Path -LiteralPath $templatesModulePath) { Import-Module -Name $templatesModulePath -Global -Force -ErrorAction Stop | Out-Null }
                        } catch { }
                        try {
                            if (Test-Path -LiteralPath $interfaceModulePath) { Import-Module -Name $interfaceModulePath -Global -Force -ErrorAction Stop | Out-Null }
                        } catch { }
                        $modulesLoaded = $true
                    }

                    $siteToLoad = ''
                    try { $siteToLoad = '' + $request.SiteToLoad } catch { $siteToLoad = '' }
                    $zoneSelection = ''
                    try { if ($request.PSObject.Properties['ZoneSelection']) { $zoneSelection = ('' + $request.ZoneSelection).Trim() } } catch { $zoneSelection = '' }
                    if ([string]::IsNullOrWhiteSpace($zoneSelection) -or $equalsIgnoreCase.Equals($zoneSelection, 'All Zones')) {
                        $zoneSelection = ''
                    }

                    $hostnamesToLoad = @()
                    try { if ($request.HostnamesToLoad) { $hostnamesToLoad = @($request.HostnamesToLoad) } } catch { $hostnamesToLoad = @() }

                    if ([string]::IsNullOrWhiteSpace($siteToLoad) -or $equalsIgnoreCase.Equals($siteToLoad, 'All Sites')) {
                        $interfaceLoadSite = if ([string]::IsNullOrWhiteSpace($siteToLoad)) { 'All Sites' } else { $siteToLoad }

                        $orderedHosts = [System.Collections.Generic.List[string]]::new()
                        $seenHosts = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
                        $siteBuckets = New-Object 'System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[string]]' ([System.StringComparer]::OrdinalIgnoreCase)

                        foreach ($hn in $hostnamesToLoad) {
                            if ($null -eq $hn) { continue }
                            $hnValue = ('' + $hn).Trim()
                            if ([string]::IsNullOrWhiteSpace($hnValue)) { continue }
                            if (-not $seenHosts.Add($hnValue)) { continue }
                            [void]$orderedHosts.Add($hnValue)

                            $siteKey = ''
                            try { $siteKey = DeviceRepositoryModule\Get-SiteFromHostname -Hostname $hnValue } catch { $siteKey = '' }
                            if ([string]::IsNullOrWhiteSpace($siteKey)) { continue }

                            $bucket = $null
                            if (-not $siteBuckets.TryGetValue($siteKey, [ref]$bucket)) {
                                $bucket = [System.Collections.Generic.List[string]]::new()
                                $siteBuckets[$siteKey] = $bucket
                            }
                            [void]$bucket.Add($hnValue)
                        }

                        # Ensure we only keep rows for the current request scope.
                        $global:DeviceInterfaceCache = @{}

                        $loadStopwatch = $null
                        try { $loadStopwatch = [System.Diagnostics.Stopwatch]::StartNew() } catch { $loadStopwatch = $null }

                        $batchSize = 75
                        foreach ($kv in $siteBuckets.GetEnumerator()) {
                            $siteKey = $kv.Key
                            $bucket = $kv.Value
                            if (-not $bucket -or $bucket.Count -eq 0) { continue }
                            $hostsArray = $bucket.ToArray()

                            for ($idx = 0; $idx -lt $hostsArray.Length; $idx += $batchSize) {
                                $take = [System.Math]::Min($batchSize, ($hostsArray.Length - $idx))
                                if ($take -le 0) { break }
                                $slice = $hostsArray[$idx..($idx + $take - 1)]

                                try {
                                    if ($zoneSelection) {
                                        DeviceRepositoryModule\Update-HostInterfaceCache -Site $siteKey -Zone $zoneSelection -Hostnames $slice
                                    } else {
                                        DeviceRepositoryModule\Update-HostInterfaceCache -Site $siteKey -Hostnames $slice
                                    }
                                } catch { }
                            }
                        }

                        if ($loadStopwatch) {
                            try { $loadStopwatch.Stop() } catch { }
                            try { $interfaceLoadMs = [Math]::Round($loadStopwatch.Elapsed.TotalMilliseconds, 3) } catch { $interfaceLoadMs = $null }
                        }

                        $filtered = [System.Collections.Generic.List[object]]::new()
                        foreach ($hnValue in $orderedHosts) {
                            if ([string]::IsNullOrWhiteSpace($hnValue)) { continue }
                            $rows = $null
                            try { $rows = $global:DeviceInterfaceCache[$hnValue] } catch { $rows = $null }
                            if (-not $rows) { continue }
                            foreach ($row in $rows) {
                                if (-not $row) { continue }
                                [void]$filtered.Add($row)
                            }
                        }

                        $interfaces = $filtered
                        $loadedInterfacesPayload = $filtered
                    } elseif (-not [string]::IsNullOrWhiteSpace($siteToLoad)) {
                        $interfaceLoadSite = $siteToLoad

                        $loadStopwatch = $null
                        try { $loadStopwatch = [System.Diagnostics.Stopwatch]::StartNew() } catch { $loadStopwatch = $null }
                        $siteInterfaces = $null
                        try {
                            $siteInterfaces = DeviceRepositoryModule\Get-InterfacesForSite -Site $siteToLoad
                        } catch {
                            $siteInterfaces = $null
                        }
                        if ($loadStopwatch) {
                            try { $loadStopwatch.Stop() } catch { }
                            try { $interfaceLoadMs = [Math]::Round($loadStopwatch.Elapsed.TotalMilliseconds, 3) } catch { $interfaceLoadMs = $null }
                        }

                        $filtered = [System.Collections.Generic.List[object]]::new()
                        if ($siteInterfaces) {
                            $useFilter = $false
                            $hostSet = $null
                            if ($hostnamesToLoad -and $hostnamesToLoad.Count -gt 0) {
                                $useFilter = $true
                                $hostSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
                                foreach ($hn in $hostnamesToLoad) {
                                    if ($null -eq $hn) { continue }
                                    $hnValue = ('' + $hn).Trim()
                                    if ([string]::IsNullOrWhiteSpace($hnValue)) { continue }
                                    [void]$hostSet.Add($hnValue)
                                }
                                if ($hostSet.Count -eq 0) { $useFilter = $false }
                            }

                            foreach ($row in $siteInterfaces) {
                                if (-not $row) { continue }
                                if ($useFilter) {
                                    $hnValue = ''
                                    try { $hnValue = ('' + $row.Hostname).Trim() } catch { $hnValue = '' }
                                    if ([string]::IsNullOrWhiteSpace($hnValue)) { continue }
                                    if (-not $hostSet.Contains($hnValue)) { continue }
                                }
                                [void]$filtered.Add($row)
                            }
                        }

                        $interfaces = $filtered
                        $loadedInterfacesPayload = $filtered
                    }
                }
            }

            $requestId = 0
            try { $requestId = [int]$request.RequestId } catch { $requestId = 0 }

            $term = ''
            $regexEnabled = $false
            $statusFilterVal = 'All'
            $authFilterVal = 'All'
            if ($includeSearch) {
                $searchSource = $searchRequest
                if (-not $searchSource) { $searchSource = $request }
                try { $term = '' + $searchSource.SearchTerm } catch { $term = '' }
                try { $regexEnabled = [bool]$searchSource.RegexEnabled } catch { $regexEnabled = $false }
                try { $statusFilterVal = '' + $searchSource.StatusFilter } catch { $statusFilterVal = 'All' }
                try { $authFilterVal = '' + $searchSource.AuthFilter } catch { $authFilterVal = 'All' }
            }

            $termEmpty = [string]::IsNullOrWhiteSpace($term)
            $noSearchFilters = ($termEmpty -and $equalsIgnoreCase.Equals($statusFilterVal, 'All') -and $equalsIgnoreCase.Equals($authFilterVal, 'All'))
            $searchNeeded = $includeSearch -and (-not $noSearchFilters)
            $searchCopyAll = $includeSearch -and $noSearchFilters

            $searchResults = $null
            if ($includeSearch) {
                $searchResults = [System.Collections.Generic.List[object]]::new()
            }
            $summary = $null
            $alerts = $null
            if ($includeAlerts) {
                $alerts = [System.Collections.Generic.List[object]]::new()
            }

            $devSet = $null
            $vlanSet = $null
            $intCount = 0
            $upCount = 0
            $downCount = 0
            $authCount = 0
            $unauthCount = 0

            if ($includeSummary) {
                $devSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
                $vlanSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
            }

            $skipLoop = (-not $includeSummary) -and (-not $includeAlerts) -and (-not $searchNeeded) -and (-not $searchCopyAll)
            if (-not $skipLoop) {
                foreach ($row in $interfaces) {
                    if (-not $row) { continue }

                    $hostname = ''
                    try { $hostname = '' + $row.Hostname } catch { $hostname = '' }
                    if (-not $hostname) {
                        try { $hostname = '' + $row.HostName } catch { $hostname = '' }
                    }

                    if ($includeSummary) {
                        $intCount++

                        if (-not [string]::IsNullOrWhiteSpace($hostname)) { [void]$devSet.Add($hostname) }

                        $status = ''
                        try { $status = '' + $row.Status } catch { $status = '' }
                        if ($status) {
                            if ($status -match '(?i)^(up|connected)$') { $upCount++ }
                            elseif ($status -match '(?i)^(down|notconnect)$') { $downCount++ }
                        }

                        $authState = ''
                        try { $authState = '' + $row.AuthState } catch { $authState = '' }
                        if ($authState) {
                            if ($equalsIgnoreCase.Equals($authState, 'authorized')) { $authCount++ } else { $unauthCount++ }
                        } else {
                            $unauthCount++
                        }

                        $vlanValue = ''
                        try { $vlanValue = '' + $row.VLAN } catch { $vlanValue = '' }
                        if (-not [string]::IsNullOrWhiteSpace($vlanValue)) { [void]$vlanSet.Add($vlanValue) }
                    }

                    if ($includeAlerts) {
                        $reasonParts = [System.Collections.Generic.List[string]]::new()

                        $status = ''
                        try { $status = '' + $row.Status } catch { $status = '' }
                        if ($status -and ($equalsIgnoreCase.Equals($status, 'down') -or $equalsIgnoreCase.Equals($status, 'notconnect'))) {
                            [void]$reasonParts.Add('Port down')
                        }

                        $duplex = ''
                        try { $duplex = '' + $row.Duplex } catch { $duplex = '' }
                        if ($duplex -and ($duplex -match '(?i)half')) { [void]$reasonParts.Add('Half duplex') }

                        $authState = ''
                        try { $authState = '' + $row.AuthState } catch { $authState = '' }
                        if ($authState) {
                            if (-not $equalsIgnoreCase.Equals($authState, 'authorized')) { [void]$reasonParts.Add('Unauthorized') }
                        } else {
                            [void]$reasonParts.Add('Unauthorized')
                        }

                        if ($reasonParts.Count -gt 0) {
                            $alert = [PSCustomObject]@{
                                Hostname  = $hostname
                                Port      = $row.Port
                                Name      = $row.Name
                                Status    = $row.Status
                                VLAN      = $row.VLAN
                                Duplex    = $row.Duplex
                                AuthState = $row.AuthState
                                Reason    = ($reasonParts -join '; ')
                            }
                            [void]$alerts.Add($alert)
                        }
                    }

                    if ($searchCopyAll) {
                        [void]$searchResults.Add($row)
                    } elseif ($searchNeeded) {
                        if (-not $equalsIgnoreCase.Equals($statusFilterVal, 'All')) {
                            $st = ''
                            try { $st = '' + $row.Status } catch { $st = '' }

                            if ($equalsIgnoreCase.Equals($statusFilterVal, 'Up')) {
                                if (-not ($equalsIgnoreCase.Equals($st, 'up') -or $equalsIgnoreCase.Equals($st, 'connected'))) {
                                    continue
                                }
                            } elseif ($equalsIgnoreCase.Equals($statusFilterVal, 'Down')) {
                                if (-not ($equalsIgnoreCase.Equals($st, 'down') -or $equalsIgnoreCase.Equals($st, 'notconnect'))) {
                                    continue
                                }
                            }
                        }

                        if (-not $equalsIgnoreCase.Equals($authFilterVal, 'All')) {
                            $as = ''
                            try { $as = '' + $row.AuthState } catch { $as = '' }

                            if ($equalsIgnoreCase.Equals($authFilterVal, 'Authorized')) {
                                if (-not $equalsIgnoreCase.Equals($as, 'authorized')) { continue }
                            } elseif ($equalsIgnoreCase.Equals($authFilterVal, 'Unauthorized')) {
                                if ($equalsIgnoreCase.Equals($as, 'authorized')) { continue }
                            }
                        }

                        if (-not $termEmpty) {
                            if ($regexEnabled) {
                                $matched = $false
                                try {
                                    if ( ('' + $row.Port) -match $term -or
                                         ('' + $row.Name) -match $term -or
                                         ('' + $row.LearnedMACs) -match $term -or
                                         ('' + $row.AuthClientMAC) -match $term ) {
                                        $matched = $true
                                    }
                                } catch { $matched = $false }

                                if (-not $matched) {
                                    $q = $term
                                    if (-not ((('' + $row.Port).IndexOf($q, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) -or
                                              (('' + $row.Name).IndexOf($q, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) -or
                                              (('' + $row.LearnedMACs).IndexOf($q, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) -or
                                              (('' + $row.AuthClientMAC).IndexOf($q, [System.StringComparison]::OrdinalIgnoreCase) -ge 0))) {
                                        continue
                                    }
                                }
                            } else {
                                $q = $term
                                if (-not ((('' + $row.Port).IndexOf($q, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) -or
                                          (('' + $row.Name).IndexOf($q, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) -or
                                          (('' + $row.LearnedMACs).IndexOf($q, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) -or
                                          (('' + $row.AuthClientMAC).IndexOf($q, [System.StringComparison]::OrdinalIgnoreCase) -ge 0))) {
                                    continue
                                }
                            }
                        }

                        [void]$searchResults.Add($row)
                    }
                }
            }

            if ($includeSummary) {
                $ratio = if ($intCount -gt 0) { [math]::Round(($upCount / $intCount) * 100, 1) } else { 0 }
                $summary = [PSCustomObject]@{
                    Devices     = $devSet.Count
                    Interfaces  = $intCount
                    Up          = $upCount
                    Down        = $downCount
                    Authorized  = $authCount
                    Unauthorized= $unauthCount
                    UniqueVlans = $vlanSet.Count
                    UpPct       = $ratio
                }
            }

            $payload = [PSCustomObject]@{
                RequestId     = $requestId
                IncludeSearch = $includeSearch
                IncludeSummary = $includeSummary
                IncludeAlerts = $includeAlerts
                SiteToLoad    = $requestSiteToLoad
                SearchResults = $searchResults
                SearchTerm    = $term
                StatusFilter  = $statusFilterVal
                AuthFilter    = $authFilterVal
                RegexEnabled  = $regexEnabled
                Summary       = $summary
                Alerts        = $alerts
                Interfaces    = $loadedInterfacesPayload
                InterfaceLoadMs = $interfaceLoadMs
                InterfaceLoadSite = $interfaceLoadSite
            }

            $dispatcher = $null
            try { $dispatcher = $request.Dispatcher } catch { $dispatcher = $null }
            if (-not $dispatcher) { continue }

            $applyDelegate = $null
            try { $applyDelegate = $request.ApplyDelegate } catch { $applyDelegate = $null }
            if (-not $applyDelegate) { continue }

            try {
                $null = $dispatcher.BeginInvoke($applyDelegate, $payload)
            } catch { }
        }
    }

    if ($emitInitVerbose) {
        try { Write-Verbose "[DeviceInsights] Ensure-InsightsWorker stage=ThreadScriptReady" } catch { }
    }

    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.Runspace = $rs

    $workerScriptText = $null
    try { $workerScriptText = $threadScript.ToString() } catch { $workerScriptText = $null }
    if ([string]::IsNullOrWhiteSpace($workerScriptText)) { return $false }
    try {
        $null = $ps.AddScript($workerScriptText).AddArgument($queueRef).AddArgument($signalRef).AddArgument($telemetryModulePath).AddArgument($databaseModulePath).AddArgument($repoModulePath).AddArgument($templatesModulePath).AddArgument($interfaceModulePath)
    } catch {
        return $false
    }

    if ($emitInitVerbose) {
        try { Write-Verbose "[DeviceInsights] Ensure-InsightsWorker stage=PowerShellReady" } catch { }
    }

    $threadStart = [StateTrace.Threading.PowerShellInvokeThreadStartFactory]::Create($ps, 'InsightsWorker')
    if ($emitInitVerbose) {
        try { Write-Verbose "[DeviceInsights] Ensure-InsightsWorker stage=ThreadStartCreated" } catch { }
    }

    $workerThread = [System.Threading.Thread]::new($threadStart)
    $workerThread.IsBackground = $true
    $workerThread.ApartmentState = [System.Threading.ApartmentState]::STA

    if ($emitInitVerbose) {
        try { Write-Verbose "[DeviceInsights] Ensure-InsightsWorker stage=ThreadStarting" } catch { }
    }
    $workerThread.Start()
    if ($emitInitVerbose) {
        try { Write-Verbose ("[DeviceInsights] Ensure-InsightsWorker stage=ThreadStarted | ThreadId={0}" -f $workerThread.ManagedThreadId) } catch { }
    }

    $script:InsightsWorkerThread = $workerThread
    $script:InsightsWorkerInitialized = $true

    try {
        $msg = "[DeviceInsights] Insights worker started | ThreadId={0}" -f $workerThread.ManagedThreadId
        try { Write-Diag $msg } catch [System.Management.Automation.CommandNotFoundException] { Write-Verbose $msg } catch { }
    } catch { }

    if ($emitInitVerbose) {
        try { Write-Verbose "[DeviceInsights] Ensure-InsightsWorker stage=ReturnTrue" } catch { }
    }

    return $true
}

function Update-InsightsAsync {
    [CmdletBinding()]
    param(
        [object]$Interfaces,
        [switch]$IncludeSearch,
        [switch]$IncludeSummary,
        [switch]$IncludeAlerts
    )

    if (-not $global:InterfacesLoadAllowed) {
        $interfacesSnapshot = $null
        if ($PSBoundParameters.ContainsKey('Interfaces') -and $Interfaces) {
            $interfacesSnapshot = $Interfaces
        } else {
            try { $interfacesSnapshot = $global:AllInterfaces } catch { $interfacesSnapshot = $null }
        }

        $ifaceCount = 0
        try { $ifaceCount = ViewStateService\Get-SequenceCount -Value $interfacesSnapshot } catch { $ifaceCount = 0 }
        if ($ifaceCount -le 0) {
            Write-Verbose '[DeviceInsights] Interfaces not allowed yet; skipping async insights refresh.'
            return
        }
    }

    $needSearch = $IncludeSearch.IsPresent
    $needSummary = $IncludeSummary.IsPresent
    $needAlerts = $IncludeAlerts.IsPresent
    if (-not ($needSearch -or $needSummary -or $needAlerts)) { return }

    $dispatcher = $null
    try {
        if ($global:window -and $global:window.Dispatcher) {
            $dispatcher = $global:window.Dispatcher
        } else {
            $dispatcher = [System.Windows.Application]::Current.Dispatcher
        }
    } catch {
        $dispatcher = $null
    }
    if (-not $dispatcher) { return }

    $interfacesToUse = $null
    if ($PSBoundParameters.ContainsKey('Interfaces') -and $Interfaces) {
        $interfacesToUse = $Interfaces
    } else {
        try { $interfacesToUse = $global:AllInterfaces } catch { $interfacesToUse = $null }
    }

    $ifaceCount = 0
    try { $ifaceCount = ViewStateService\Get-SequenceCount -Value $interfacesToUse } catch { $ifaceCount = 0 }

    $context = $null
    try { $context = script:Get-DeviceInsightsFilterContext } catch { $context = $null }
    $loadInterfaces = $false
    $siteToLoad = ''
    $zoneSelectionValue = ''
    $hostnamesToLoad = @()
    try { $siteToLoad = if ($context -and $context.Site) { ('' + $context.Site).Trim() } else { '' } } catch { $siteToLoad = '' }
    try { $zoneSelectionValue = if ($context -and $context.Zone) { ('' + $context.Zone).Trim() } else { '' } } catch { $zoneSelectionValue = '' }
    if ($ifaceCount -le 0) {
        $metadata = $null
        $locationEntries = $null
        try { $metadata = $global:DeviceMetadata } catch { $metadata = $null }
        try { $locationEntries = $global:DeviceLocationEntries } catch { $locationEntries = $null }

        $snapshot = $null
        try {
            $snapshotParams = @{ DeviceMetadata = $metadata; LocationEntries = $locationEntries }
            if (-not [string]::IsNullOrWhiteSpace($siteToLoad) -and -not [System.StringComparer]::OrdinalIgnoreCase.Equals($siteToLoad, 'All Sites')) {
                $snapshotParams.Site = $siteToLoad
            }
            if ($zoneSelectionValue -and -not [System.StringComparer]::OrdinalIgnoreCase.Equals($zoneSelectionValue, 'All Zones')) {
                $snapshotParams.ZoneSelection = $zoneSelectionValue
            }
            if ($context.Building -and -not [string]::IsNullOrWhiteSpace($context.Building)) { $snapshotParams.Building = $context.Building }
            if ($context.Room -and -not [string]::IsNullOrWhiteSpace($context.Room)) { $snapshotParams.Room = $context.Room }
            $snapshot = ViewStateService\Get-FilterSnapshot @snapshotParams
        } catch {
            $snapshot = $null
        }

        if ($snapshot -and $snapshot.Hostnames) {
            try { $hostnamesToLoad = @($snapshot.Hostnames) } catch { $hostnamesToLoad = @() }
        }

        if ($hostnamesToLoad -and $hostnamesToLoad.Count -gt 0) {
            $loadInterfaces = $true
        }

        if (-not $loadInterfaces -and -not [string]::IsNullOrWhiteSpace($siteToLoad) -and -not [System.StringComparer]::OrdinalIgnoreCase.Equals($siteToLoad, 'All Sites')) {
            try {
                $zoneValue = ''
                $buildingValue = ''
                $roomValue = ''
                try { $zoneValue = '' + $context.Zone } catch { $zoneValue = '' }
                try { $buildingValue = '' + $context.Building } catch { $buildingValue = '' }
                try { $roomValue = '' + $context.Room } catch { $roomValue = '' }
                $msg = "[DeviceInsights] Interface snapshot not scheduled | Reason=NoHostnames | Site={0} | Zone={1} | Building={2} | Room={3}" -f $siteToLoad, $zoneValue, $buildingValue, $roomValue
                try { Write-Diag $msg } catch [System.Management.Automation.CommandNotFoundException] { Write-Verbose $msg } catch { }
            } catch { }
        }
    }

    $term = ''
    $statusFilterVal = 'All'
    $authFilterVal = 'All'

    if ($needSearch) {
        try {
            $searchHostCtrl = $global:window.FindName('SearchInterfacesHost')
            if ($searchHostCtrl) {
                $view = $searchHostCtrl.Content
                if ($view) {
                    $boxCtrl = $view.FindName('SearchBox')
                    if ($boxCtrl) { $term = '' + $boxCtrl.Text }

                    $statusCtrl = $view.FindName('StatusFilter')
                    $authCtrl   = $view.FindName('AuthFilter')
                    if ($statusCtrl -and $statusCtrl.SelectedItem) {
                        $statusFilterVal = '' + $statusCtrl.SelectedItem.Content
                    }
                    if ($authCtrl -and $authCtrl.SelectedItem) {
                        $authFilterVal = '' + $authCtrl.SelectedItem.Content
                    }
                }
            }
        } catch { }
    }

    $emitStageVerbose = $false
    try { if ($global:StateTraceDebug) { $emitStageVerbose = $true } } catch { $emitStageVerbose = $false }

    $diagWriter = $null
    try { $diagWriter = ${function:Write-InsightsDebug} } catch { $diagWriter = $null }
    $sortedListCmd = $null
    try { $sortedListCmd = ${function:New-InsightsSortedList} } catch { $sortedListCmd = $null }

    $applyUiDelegate = $null
    try {
        $applyUiUpdates = {
            param($state)

            $emitInsightsDiag = $false
            try { $emitInsightsDiag = [bool]$global:StateTraceDebug } catch { $emitInsightsDiag = $false }

            try { $script:InsightsApplyCounter++ } catch { }

            $stateId = 0
            try { $stateId = [int]$state.RequestId } catch { $stateId = 0 }

            $isLatest = $true
            if ($stateId -gt 0) {
                try {
                    if ($stateId -ne $script:InsightsLatestRequestId) { $isLatest = $false }
                } catch { $isLatest = $true }
            }

            $siteMatches = $true
            if (-not $isLatest) {
                $siteMatches = $false
                $currentSite = ''
                try {
                    $locCmd = $null
                    try { $locCmd = Get-Command -Name 'FilterStateModule\Get-SelectedLocation' -ErrorAction SilentlyContinue } catch { $locCmd = $null }
                    if ($locCmd) {
                        $loc = $null
                        try { $loc = FilterStateModule\Get-SelectedLocation } catch { $loc = $null }
                        if ($loc -and $loc.PSObject.Properties['Site']) { $currentSite = '' + $loc.Site }
                    }
                } catch { $currentSite = '' }

                $payloadSite = ''
                try {
                    if ($state.PSObject.Properties['SiteToLoad']) {
                        $payloadSite = '' + $state.SiteToLoad
                    } elseif ($state.PSObject.Properties['InterfaceLoadSite']) {
                        $payloadSite = '' + $state.InterfaceLoadSite
                    }
                } catch { $payloadSite = '' }

                $normalizeSite = {
                    param([string]$value)
                    $v = if ($value) { ('' + $value).Trim() } else { '' }
                    if ([string]::IsNullOrWhiteSpace($v) -or
                        [System.StringComparer]::OrdinalIgnoreCase.Equals($v, 'All Sites') -or
                        [System.StringComparer]::OrdinalIgnoreCase.Equals($v, 'All'))
                    {
                        return 'All Sites'
                    }
                    return $v
                }

                $currentNorm = & $normalizeSite $currentSite
                $payloadNorm = & $normalizeSite $payloadSite
                if ([System.StringComparer]::OrdinalIgnoreCase.Equals($currentNorm, $payloadNorm)) {
                    $siteMatches = $true
                } elseif ([string]::IsNullOrWhiteSpace($currentSite)) {
                    # Fallback: avoid starving the UI if selection probing fails.
                    $siteMatches = $true
                }
            }

            $applyDerived = ($isLatest -or $siteMatches)
            if ($emitInsightsDiag) {
                $diagSearchCount = 0
                $diagAlertCount = 0
                try {
                    if ($state.PSObject.Properties['SearchResults']) {
                        $diagSearchCount = ViewStateService\Get-SequenceCount -Value $state.SearchResults
                    }
                } catch { $diagSearchCount = 0 }
                try {
                    if ($state.PSObject.Properties['Alerts']) {
                        $diagAlertCount = ViewStateService\Get-SequenceCount -Value $state.Alerts
                    }
                } catch { $diagAlertCount = 0 }
                $msg = "[DeviceInsights] ApplyInsights | RequestId={0} Latest={1} ApplyDerived={2} Search={3} Alerts={4} Summary={5} SearchCount={6} AlertsCount={7}" -f `
                    $stateId, $script:InsightsLatestRequestId, $applyDerived, [bool]$state.IncludeSearch, [bool]$state.IncludeAlerts, [bool]$state.IncludeSummary, $diagSearchCount, $diagAlertCount
                if ($diagWriter) { & $diagWriter $msg }
            }

            $loadedInterfaces = $null
            try { if ($state.PSObject.Properties['Interfaces']) { $loadedInterfaces = $state.Interfaces } } catch { $loadedInterfaces = $null }
            if ($loadedInterfaces -and $applyDerived) {
                try { $global:AllInterfaces = $loadedInterfaces } catch { }
                try {
                    $loadMs = $null
                    $loadSite = ''
                    try { $loadMs = $state.InterfaceLoadMs } catch { $loadMs = $null }
                    try { $loadSite = '' + $state.InterfaceLoadSite } catch { $loadSite = '' }
                    if ($null -ne $loadMs) {
                        $msg = "[DeviceInsights] Interface snapshot loaded | Site={0} | Interfaces={1} | LoadMs={2}" -f $loadSite, (ViewStateService\Get-SequenceCount -Value $loadedInterfaces), $loadMs
                        try { Write-Diag $msg } catch [System.Management.Automation.CommandNotFoundException] { Write-Verbose $msg } catch { }
                    }
                } catch { }
            }

            if ($applyDerived -and $state.IncludeSummary -and $state.Summary) {
                $sv = $null
                try { $sv = (Get-Variable -Name summaryView -Scope Global -ErrorAction SilentlyContinue).Value } catch { $sv = $null }
                if ($sv) {
                    try {
                        ($sv.FindName("SummaryDevicesCount")).Text      = ('' + $state.Summary.Devices)
                        ($sv.FindName("SummaryInterfacesCount")).Text   = ('' + $state.Summary.Interfaces)
                        ($sv.FindName("SummaryUpCount")).Text           = ('' + $state.Summary.Up)
                        ($sv.FindName("SummaryDownCount")).Text         = ('' + $state.Summary.Down)
                        ($sv.FindName("SummaryAuthorizedCount")).Text   = ('' + $state.Summary.Authorized)
                        ($sv.FindName("SummaryUnauthorizedCount")).Text = ('' + $state.Summary.Unauthorized)
                        ($sv.FindName("SummaryUniqueVlansCount")).Text  = ('' + $state.Summary.UniqueVlans)
                        ($sv.FindName("SummaryExtra")).Text             = ("Up %: {0}%" -f $state.Summary.UpPct)
                    } catch { }
                }
            }

            if ($applyDerived -and $state.IncludeAlerts) {
                $alertsList = $null
                if ($sortedListCmd) {
                    try { $alertsList = & $sortedListCmd -Rows $state.Alerts } catch { $alertsList = $null }
                } else {
                    try { $alertsList = $state.Alerts } catch { $alertsList = $null }
                }
                if ($null -eq $alertsList) { $alertsList = @() }
                $global:AlertsList = $alertsList
                if ($global:alertsView) {
                    try {
                        $grid = $global:alertsView.FindName('AlertsGrid')
                        if ($grid) { $grid.ItemsSource = $global:AlertsList }
                        if ($emitInsightsDiag) {
                            $alertCount = 0
                            try { $alertCount = ViewStateService\Get-SequenceCount -Value $global:AlertsList } catch { $alertCount = 0 }
                            $gridFound = [bool]$grid
                            if ($diagWriter) { & $diagWriter ("[DeviceInsights] ApplyAlerts | GridFound={0} | Count={1}" -f $gridFound, $alertCount) }
                        }
                    } catch { }
                } elseif ($emitInsightsDiag) {
                    if ($diagWriter) { & $diagWriter "[DeviceInsights] ApplyAlerts | AlertsViewMissing" }
                }
            }

            if ($applyDerived -and $state.IncludeSearch) {
                $payloadTerm = ''
                $payloadStatus = 'All'
                $payloadAuth = 'All'
                $payloadRegexEnabled = $false
                try { if ($state.PSObject.Properties['SearchTerm']) { $payloadTerm = '' + $state.SearchTerm } } catch { $payloadTerm = '' }
                try { if ($state.PSObject.Properties['StatusFilter']) { $payloadStatus = '' + $state.StatusFilter } } catch { $payloadStatus = 'All' }
                try { if ($state.PSObject.Properties['AuthFilter']) { $payloadAuth = '' + $state.AuthFilter } } catch { $payloadAuth = 'All' }
                try { if ($state.PSObject.Properties['RegexEnabled']) { $payloadRegexEnabled = [bool]$state.RegexEnabled } } catch { $payloadRegexEnabled = $false }

                $currentTerm = ''
                $currentStatus = 'All'
                $currentAuth = 'All'
                $currentRegexEnabled = $false
                try { $currentRegexEnabled = [bool]$script:SearchRegexEnabled } catch { $currentRegexEnabled = $false }

                $gridCtrl = $null
                try {
                    $searchHostCtrl = $global:window.FindName('SearchInterfacesHost')
                    if ($searchHostCtrl) {
                        $view = $searchHostCtrl.Content
                        if ($view) {
                            $boxCtrl = $view.FindName('SearchBox')
                            if ($boxCtrl) { $currentTerm = '' + $boxCtrl.Text }

                            $statusCtrl = $view.FindName('StatusFilter')
                            $authCtrl   = $view.FindName('AuthFilter')
                            if ($statusCtrl -and $statusCtrl.SelectedItem) {
                                $currentStatus = '' + $statusCtrl.SelectedItem.Content
                            }
                            if ($authCtrl -and $authCtrl.SelectedItem) {
                                $currentAuth = '' + $authCtrl.SelectedItem.Content
                            }

                            $gridCtrl = $view.FindName('SearchInterfacesGrid')
                        }
                    }
                } catch { }

                if ($gridCtrl) {
                    $termMatches = $false
                    $statusMatches = $false
                    $authMatches = $false
                    try { $termMatches = [System.StringComparer]::Ordinal.Equals(('' + $currentTerm), ('' + $payloadTerm)) } catch { $termMatches = $false }
                    try { $statusMatches = [System.StringComparer]::OrdinalIgnoreCase.Equals(('' + $currentStatus), ('' + $payloadStatus)) } catch { $statusMatches = $false }
                    try { $authMatches = [System.StringComparer]::OrdinalIgnoreCase.Equals(('' + $currentAuth), ('' + $payloadAuth)) } catch { $authMatches = $false }

                    $regexMatches = ($currentRegexEnabled -eq $payloadRegexEnabled)

                    if ($emitInsightsDiag) {
                        $diagMsg = "[DeviceInsights] ApplySearch | GridFound=True | TermMatch={0} StatusMatch={1} AuthMatch={2} RegexMatch={3} | Term='{4}' Status='{5}' Auth='{6}'" -f `
                            $termMatches, $statusMatches, $authMatches, $regexMatches, $currentTerm, $currentStatus, $currentAuth
                        if ($diagWriter) { & $diagWriter $diagMsg }
                    }

                    if ($termMatches -and $statusMatches -and $authMatches -and $regexMatches) {
                        if ($sortedListCmd) {
                            try { $gridCtrl.ItemsSource = & $sortedListCmd -Rows $state.SearchResults } catch { }
                        } else {
                            try { $gridCtrl.ItemsSource = $state.SearchResults } catch { }
                        }
                        if ($emitInsightsDiag) {
                            $searchCount = 0
                            try { $searchCount = ViewStateService\Get-SequenceCount -Value $state.SearchResults } catch { $searchCount = 0 }
                            if ($diagWriter) { & $diagWriter ("[DeviceInsights] ApplySearch bound | Count={0}" -f $searchCount) }
                        }
                    }
                } elseif ($emitInsightsDiag) {
                    if ($diagWriter) { & $diagWriter "[DeviceInsights] ApplySearch | GridFound=False" }
                }
            }
        }.GetNewClosure()
        $applyUiDelegate = [System.Action[object]]$applyUiUpdates
    } catch {
        $applyUiDelegate = $null
    }

    if (-not $applyUiDelegate) { return }
    if ($emitStageVerbose) {
        try { Write-Verbose ("[DeviceInsights] Update-InsightsAsync stage=ApplyDelegateReady | ThreadId={0}" -f [System.Threading.Thread]::CurrentThread.ManagedThreadId) } catch { }
    }

    $workerEnsureOk = $false
    $workerEnsureMs = $null
    $ensureStopwatch = $null
    try { $ensureStopwatch = [System.Diagnostics.Stopwatch]::StartNew() } catch { $ensureStopwatch = $null }
    try { $workerEnsureOk = [bool](script:Ensure-InsightsWorker) } catch { $workerEnsureOk = $false }
    try {
        if ($ensureStopwatch) {
            try { $ensureStopwatch.Stop() } catch { }
            try { $workerEnsureMs = [math]::Round($ensureStopwatch.Elapsed.TotalMilliseconds, 3) } catch { $workerEnsureMs = $null }
        }
    } catch { }

    if (-not $workerEnsureOk) {
        try {
            $msg = "[DeviceInsights] Insights worker unavailable; skipping async refresh."
            try { Write-Diag $msg } catch [System.Management.Automation.CommandNotFoundException] { Write-Verbose $msg } catch { }
        } catch { }
        return
    }

    if ($emitStageVerbose) {
        try { Write-Verbose ("[DeviceInsights] Update-InsightsAsync stage=WorkerReady | ThreadId={0}" -f [System.Threading.Thread]::CurrentThread.ManagedThreadId) } catch { }
    }

    if ($null -ne $workerEnsureMs) {
        $emitEnsureDiag = $false
        try { if ($global:StateTraceDebug) { $emitEnsureDiag = $true } } catch { $emitEnsureDiag = $false }
        if (-not $emitEnsureDiag) {
            try { $emitEnsureDiag = ($workerEnsureMs -ge 250) } catch { $emitEnsureDiag = $false }
        }

        if ($emitEnsureDiag) {
            try {
                $msg = "[DeviceInsights] Ensure-InsightsWorker completed | DurationMs={0}" -f $workerEnsureMs
                try { Write-Diag $msg } catch [System.Management.Automation.CommandNotFoundException] { Write-Verbose $msg } catch { }
            } catch { }
        }
    }

    $requestId = 0
    try {
        $script:InsightsRequestCounter++
        $requestId = $script:InsightsRequestCounter
        $script:InsightsLatestRequestId = $requestId
    } catch {
        $requestId = 0
    }

    try {
        $hostCount = 0
        try { $hostCount = @($hostnamesToLoad).Count } catch { $hostCount = 0 }
        $msg = "[DeviceInsights] Insights request building | RequestId={0} | LoadInterfaces={1} | Hosts={2} | Interfaces={3}" -f $requestId, $loadInterfaces, $hostCount, $ifaceCount
        try { Write-Diag $msg } catch [System.Management.Automation.CommandNotFoundException] { Write-Verbose $msg } catch { }
    } catch { }

    if ($loadInterfaces) {
        try {
            $hostCount = 0
            try { $hostCount = @($hostnamesToLoad).Count } catch { $hostCount = 0 }
            $msg = "[DeviceInsights] Interface snapshot scheduled | RequestId={0} | Site={1} | Hosts={2}" -f $requestId, $siteToLoad, $hostCount
            try { Write-Diag $msg } catch [System.Management.Automation.CommandNotFoundException] { Write-Verbose $msg } catch { }
        } catch { }
    }

    $request = [PSCustomObject]@{
        RequestId      = $requestId
        Dispatcher     = $dispatcher
        ApplyDelegate  = $applyUiDelegate
        Interfaces     = $interfacesToUse
        LoadInterfaces = $loadInterfaces
        SiteToLoad     = $siteToLoad
        ZoneSelection  = $zoneSelectionValue
        HostnamesToLoad = $hostnamesToLoad
        IncludeSearch  = $needSearch
        IncludeSummary = $needSummary
        IncludeAlerts  = $needAlerts
        SearchTerm     = $term
        RegexEnabled   = [bool]$script:SearchRegexEnabled
        StatusFilter   = $statusFilterVal
        AuthFilter     = $authFilterVal
    }

    try { $script:InsightsWorkerQueue.Enqueue($request) } catch { return }
    try { $null = $script:InsightsWorkerSignal.Set() } catch { }

    try {
        $msg = "[DeviceInsights] Insights request enqueued | RequestId={0}" -f $requestId
        try { Write-Diag $msg } catch [System.Management.Automation.CommandNotFoundException] { Write-Verbose $msg } catch { }
    } catch { }

    if ($emitStageVerbose) {
        try { Write-Verbose ("[DeviceInsights] Update-InsightsAsync stage=Enqueued | RequestId={0}" -f $requestId) } catch { }
    }
}

function Update-SearchGridAsync {
    [CmdletBinding()]
    param([object]$Interfaces)

    Update-InsightsAsync -Interfaces $Interfaces -IncludeSearch
}

function Update-SummaryAsync {
    [CmdletBinding()]
    param([object]$Interfaces)

    Update-InsightsAsync -Interfaces $Interfaces -IncludeSummary
}

function Update-AlertsAsync {
    [CmdletBinding()]
    param([object]$Interfaces)

    Update-InsightsAsync -Interfaces $Interfaces -IncludeAlerts
}

Export-ModuleMember -Function Update-SearchResults, Update-Summary, Update-Alerts, Update-SearchGrid, Update-InsightsAsync, Update-SearchGridAsync, Update-SummaryAsync, Update-AlertsAsync, Get-SearchRegexEnabled, Set-SearchRegexEnabled
