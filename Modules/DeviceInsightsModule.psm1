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
    if ($termEmpty -and
        [System.StringComparer]::OrdinalIgnoreCase.Equals(('' + $statusFilterVal), 'All') -and
        [System.StringComparer]::OrdinalIgnoreCase.Equals(('' + $authFilterVal), 'All'))
    {
        return @()
    }

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

    return ,$results
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

    $global:AlertsList = $alerts
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

    $gridCtrl.ItemsSource = $resultList
}

function script:Ensure-PowerShellThreadStartFactory {
    [CmdletBinding()]
    param()

    if ('StateTrace.Threading.PowerShellThreadStartFactory' -as [type]) { return $true }

    try {
        Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Threading;

namespace StateTrace.Threading
{
    public static class PowerShellThreadStartFactory
    {
        public static ThreadStart Create(ScriptBlock action, PowerShell ps, string host)
        {
            if (action == null)
            {
                throw new ArgumentNullException("action");
            }

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
                        Runspace.DefaultRunspace = runspace;
                    }

                    action.Invoke(ps, host);
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
            if ($script:InsightsWorkerRunspace.RunspaceStateInfo.State -eq [System.Management.Automation.Runspaces.RunspaceState]::Opened) {
                return $script:InsightsWorkerRunspace
            }
        } catch { }
        try { $script:InsightsWorkerRunspace.Dispose() } catch { }
        $script:InsightsWorkerRunspace = $null
    }

    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($iss)
    $rs.ThreadOptions  = [System.Management.Automation.Runspaces.PSThreadOptions]::ReuseThread
    $rs.ApartmentState = [System.Threading.ApartmentState]::STA

    try {
        $rs.Open()
    } catch {
        try { $rs.Dispose() } catch { }
        return $null
    }

    try { $rs.SessionStateProxy.LanguageMode = [System.Management.Automation.PSLanguageMode]::FullLanguage } catch { }
    $script:InsightsWorkerRunspace = $rs
    return $script:InsightsWorkerRunspace
}

function script:Ensure-InsightsWorker {
    [CmdletBinding()]
    param()

    if ($script:InsightsWorkerInitialized -and $script:InsightsWorkerThread) {
        return $true
    }

    $rs = script:Get-InsightsWorkerRunspace
    if (-not $rs) { return $false }

    if (-not (script:Ensure-PowerShellThreadStartFactory)) { return $false }

    if (-not $script:InsightsWorkerQueue) {
        $script:InsightsWorkerQueue = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
    }
    if (-not $script:InsightsWorkerSignal) {
        $script:InsightsWorkerSignal = New-Object System.Threading.AutoResetEvent $false
    }

    $queueRef = $script:InsightsWorkerQueue
    $signalRef = $script:InsightsWorkerSignal

    $threadScript = {
        param([System.Management.Automation.PowerShell]$psCmd, [string]$token)

        $queueLocal = $queueRef
        $signalLocal = $signalRef

        $equalsIgnoreCase = [System.StringComparer]::OrdinalIgnoreCase

        while ($true) {
            $item = $null
            $request = $null
            try { while ($queueLocal.TryDequeue([ref]$item)) { $request = $item } } catch { $request = $null }
            if (-not $request) {
                try { $null = $signalLocal.WaitOne() } catch { }
                continue
            }

            if (-not $request) { continue }

            $interfaces = $request.Interfaces
            if (-not $interfaces) { $interfaces = @() }

            $requestId = 0
            try { $requestId = [int]$request.RequestId } catch { $requestId = 0 }

            $includeSearch = [bool]$request.IncludeSearch
            $includeSummary = [bool]$request.IncludeSummary
            $includeAlerts = [bool]$request.IncludeAlerts

            $term = '' + $request.SearchTerm
            $regexEnabled = [bool]$request.RegexEnabled
            $statusFilterVal = '' + $request.StatusFilter
            $authFilterVal = '' + $request.AuthFilter

            $termEmpty = [string]::IsNullOrWhiteSpace($term)
            $searchNeeded = $includeSearch -and (-not ($termEmpty -and $equalsIgnoreCase.Equals($statusFilterVal, 'All') -and $equalsIgnoreCase.Equals($authFilterVal, 'All')))

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

                if ($searchNeeded) {
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

            # Suppress stale results when a newer request is already pending.
            try {
                if (-not $queueLocal.IsEmpty) { continue }
            } catch { }

            $payload = [PSCustomObject]@{
                RequestId     = $requestId
                IncludeSearch = $includeSearch
                IncludeSummary = $includeSummary
                IncludeAlerts = $includeAlerts
                SearchResults = $searchResults
                Summary       = $summary
                Alerts        = $alerts
            }

            $dispatcher = $null
            try { $dispatcher = $request.Dispatcher } catch { $dispatcher = $null }
            if (-not $dispatcher) {
                try { $dispatcher = [System.Windows.Application]::Current.Dispatcher } catch { $dispatcher = $null }
            }
            if (-not $dispatcher) { continue }

            $applyDelegate = $null
            try { $applyDelegate = $request.ApplyDelegate } catch { $applyDelegate = $null }
            if (-not $applyDelegate) { continue }

            try {
                $null = $dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, $applyDelegate, $payload)
            } catch { }
        }
    }.GetNewClosure()

    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.Runspace = $rs

    $threadStart = [StateTrace.Threading.PowerShellThreadStartFactory]::Create($threadScript, $ps, 'InsightsWorker')
    $workerThread = [System.Threading.Thread]::new($threadStart)
    $workerThread.IsBackground = $true
    $workerThread.ApartmentState = [System.Threading.ApartmentState]::STA
    $workerThread.Start()

    $script:InsightsWorkerThread = $workerThread
    $script:InsightsWorkerInitialized = $true
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
        Write-Verbose '[DeviceInsights] Interfaces not allowed yet; skipping async insights refresh.'
        return
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
    if ($ifaceCount -le 0) {
        $context = script:Get-DeviceInsightsFilterContext

        $siteValue = ''
        try { $siteValue = if ($context -and $context.Site) { ('' + $context.Site).Trim() } else { '' } } catch { $siteValue = '' }

        $hasInterfaceCache = $false
        try {
            $cacheProbe = $global:DeviceInterfaceCache
            if ($cacheProbe -is [System.Collections.IDictionary] -and $cacheProbe.Count -gt 0) { $hasInterfaceCache = $true }
        } catch { $hasInterfaceCache = $false }

        if (([string]::IsNullOrWhiteSpace($siteValue) -or [System.StringComparer]::OrdinalIgnoreCase.Equals($siteValue, 'All Sites')) -and -not $hasInterfaceCache) {
            # Avoid implicit "load every site database" behavior during Load-from-DB when no interface cache exists.
            return
        }

        script:Update-DeviceInsightsSiteZoneCache -Site $context.Site -ZoneToLoad $context.ZoneToLoad
        $interfacesToUse = ViewStateService\Get-InterfacesForContext -Site $context.Site -ZoneSelection $context.Zone -ZoneToLoad $context.ZoneToLoad -Building $context.Building -Room $context.Room
        try { $global:AllInterfaces = $interfacesToUse } catch { }
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

    if (-not (script:Ensure-InsightsWorker)) { return }

    $requestId = 0
    try {
        $script:InsightsRequestCounter++
        $requestId = $script:InsightsRequestCounter
        $script:InsightsLatestRequestId = $requestId
    } catch {
        $requestId = 0
    }

    $applyUiUpdates = {
        param($state)

        $stateId = 0
        try { $stateId = [int]$state.RequestId } catch { $stateId = 0 }
        if ($stateId -gt 0) {
            try {
                if ($stateId -ne $script:InsightsLatestRequestId) { return }
            } catch { }
        }

        if ($state.IncludeSummary -and $state.Summary) {
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

        if ($state.IncludeAlerts) {
            try { $global:AlertsList = $state.Alerts } catch { }
            if ($global:alertsView) {
                try {
                    $grid = $global:alertsView.FindName('AlertsGrid')
                    if ($grid) { $grid.ItemsSource = $global:AlertsList }
                } catch { }
            }
        }

        if ($state.IncludeSearch) {
            try {
                $searchHostCtrl = $global:window.FindName('SearchInterfacesHost')
                if ($searchHostCtrl) {
                    $view = $searchHostCtrl.Content
                    if ($view) {
                        $gridCtrl = $view.FindName('SearchInterfacesGrid')
                        if ($gridCtrl) { $gridCtrl.ItemsSource = $state.SearchResults }
                    }
                }
            } catch { }
        }
    }.GetNewClosure()
    $applyUiDelegate = [System.Action[object]]$applyUiUpdates

    $request = [PSCustomObject]@{
        RequestId      = $requestId
        Dispatcher     = $dispatcher
        ApplyDelegate  = $applyUiDelegate
        Interfaces     = $interfacesToUse
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
