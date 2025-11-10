Set-StrictMode -Version Latest

# ADODB helper constants and utilities for parameterized operations
if (-not (Get-Variable -Name AdCmdText -Scope Script -ErrorAction SilentlyContinue)) {
    $script:AdCmdText = 1
    $script:AdParamInput = 1
    $script:AdTypeVarWChar = 202
    $script:AdTypeLongVarWChar = 203
    $script:AdTypeInteger = 3
    $script:AdTypeDate = 7
    $script:AdLongTextDefaultSize = 262144
    $script:AdExecuteNoRecords = 128
    $script:AdUseClient = 3
    $script:AdOpenStatic = 3
    $script:AdLockBatchOptimistic = 4
}

if (-not (Get-Variable -Name AdodbParameterWrapperType -Scope Script -ErrorAction SilentlyContinue)) {
    $script:AdodbParameterWrapperType = $null
}

if (-not (Get-Variable -Name AdodbParameterWrapperTypeResolved -Scope Script -ErrorAction SilentlyContinue)) {
    $script:AdodbParameterWrapperTypeResolved = $false
}

if (-not (Get-Variable -Name InterfaceIndexesEnsured -Scope Script -ErrorAction SilentlyContinue)) {
    $script:InterfaceIndexesEnsured = $false
}

if (-not (Get-Variable -Name InterfaceIndexesEnsureAttempted -Scope Script -ErrorAction SilentlyContinue)) {
    $script:InterfaceIndexesEnsureAttempted = $false
}

if (-not (Get-Variable -Name InterfaceComparisonProperties -Scope Script -ErrorAction SilentlyContinue)) {
    $script:InterfaceComparisonProperties = @(
        'Name',
        'Status',
        'VLAN',
        'Duplex',
        'Speed',
        'Type',
        'Learned',
        'AuthState',
        'AuthMode',
        'AuthClient',
        'Template',
        'Config',
        'PortColor',
        'StatusTag',
        'ToolTip'
    )
}

if (-not (Get-Variable -Name LastInterfaceSyncTelemetry -Scope Script -ErrorAction SilentlyContinue)) {
    $script:LastInterfaceSyncTelemetry = $null
}

if (-not (Get-Variable -Name SkipSiteCacheUpdate -Scope Script -ErrorAction SilentlyContinue)) {
    $script:SkipSiteCacheUpdate = $false
}

if (-not (Get-Variable -Name SiteExistingRowCache -Scope Script -ErrorAction SilentlyContinue)) {
    $script:SiteExistingRowCache = @{}
}

if (-not (Get-Variable -Name SpanTablesEnsured -Scope Script -ErrorAction SilentlyContinue)) {
    $script:SpanTablesEnsured = $false
}

function Clear-SiteExistingRowCache {
    [CmdletBinding()]
    param()

    $script:SiteExistingRowCache = @{}
}

function Set-ParserSkipSiteCacheUpdate {
    [CmdletBinding()]
    param(
        [switch]$Reset,
        [bool]$Skip = $true
    )

    if ($Reset) {
        $script:SkipSiteCacheUpdate = $false
        Clear-SiteExistingRowCache
    } else {
        $script:SkipSiteCacheUpdate = [bool]$Skip
    }

    return $script:SkipSiteCacheUpdate
}

function Get-InterfaceSignatureFromValues {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][System.Collections.IEnumerable]$Values
    )

    $builder = New-Object System.Text.StringBuilder
    $first = $true

    foreach ($rawValue in $Values) {
        if (-not $first) {
            [void]$builder.Append('|')
        } else {
            $first = $false
        }

        $text = ''
        if ($null -ne $rawValue -and $rawValue -ne [System.DBNull]::Value) {
            $text = '' + $rawValue
        }

        [void]$builder.Append($text)
    }

    return $builder.ToString()
}

function Get-InterfaceRowSignature {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][psobject]$Row
    )

    $propertyBag = $Row.PSObject.Properties
    $values = New-Object 'System.Collections.Generic.List[object]' $script:InterfaceComparisonProperties.Count

    foreach ($prop in $script:InterfaceComparisonProperties) {
        $member = $propertyBag[$prop]
        if ($null -ne $member) {
            $values.Add($member.Value) | Out-Null
        } else {
            $values.Add($null) | Out-Null
        }
    }

    return Get-InterfaceSignatureFromValues -Values $values
}

function Test-IsAdodbConnection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Connection
    )

    if ($null -eq $Connection) { return $false }
    if ($Connection -is [System.__ComObject]) { return $true }
    try {
        foreach ($name in $Connection.PSObject.TypeNames) {
            if ($name -eq 'ADODB.Connection') { return $true }
        }
    } catch { }
    return $false
}

function Release-ComObjectSafe {
    [CmdletBinding()]
    param(
        [Parameter()][object]$ComObject
    )

    if ($null -eq $ComObject) { return }
    if ($ComObject -is [System.__ComObject]) {
        try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($ComObject) } catch { }
    }
}

function New-AdodbTextCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Connection,
        [Parameter(Mandatory=$true)][string]$CommandText
    )

    try {
        $command = New-Object -ComObject 'ADODB.Command'
    } catch {
        return $null
    }

    try {
        $command.ActiveConnection = $Connection
        $command.CommandType = $script:AdCmdText
        $command.CommandText = $CommandText
        return $command
    } catch {
        Release-ComObjectSafe -ComObject $command
        return $null
    }
}

function New-AdodbInterfaceSeedRecordset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Connection
    )

    if (-not (Test-IsAdodbConnection -Connection $Connection)) { return $null }

    try {
        $recordset = New-Object -ComObject 'ADODB.Recordset'
    } catch {
        return $null
    }

    $opened = $false
    try {
        try { $recordset.CursorLocation = $script:AdUseClient } catch { }
        try { $recordset.CursorType = $script:AdOpenStatic } catch { }
        try { $recordset.LockType = $script:AdLockBatchOptimistic } catch { }

        $recordset.ActiveConnection = $Connection
        $recordset.Source = 'SELECT BatchId, Hostname, RunDateText, Port, Name, Status, VLAN, Duplex, Speed, Type, LearnedMACs, AuthState, AuthMode, AuthClientMAC, AuthTemplate, Config, PortColor, ConfigStatus, ToolTip FROM InterfaceBulkSeed WHERE 1=0'
        $recordset.Open()
        $opened = $true
        return $recordset
    } catch {
        if ($opened -and $recordset -and $recordset.State -ne 0) {
            try { $recordset.Close() } catch { }
        }
        Release-ComObjectSafe -ComObject $recordset
        return $null
    }
}

function Add-AdodbParameter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Command,
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][int]$Type,
        [Parameter()][object]$Size
    )

    if (-not $Command) { return $null }

    try {
        $sizeValue = $null
        if ($PSBoundParameters.ContainsKey('Size')) {
            $sizeValue = $Size
            if ($sizeValue -is [System.Array]) {
                if ($sizeValue.Length -gt 0) {
                    $sizeValue = $sizeValue[0]
                } else {
                    $sizeValue = $null
                }
            }
            if ($sizeValue -ne $null -and -not ($sizeValue -is [int])) {
                try { $sizeValue = [int]$sizeValue } catch { $sizeValue = 0 }
            }
        }

        if ($sizeValue -is [int] -and $sizeValue -gt 0) {
            $parameter = $Command.CreateParameter($Name, $Type, $script:AdParamInput, $sizeValue)
        } else {
            $parameter = $Command.CreateParameter($Name, $Type, $script:AdParamInput)
        }
        [void]$Command.Parameters.Append($parameter)
        return $parameter
    } catch {
        return $null
    }
}

function Set-AdodbParameterValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Parameter,
        [Parameter()][object]$Value
    )

    if (-not $Parameter) { return }

    $valueToAssign = $Value
    if ($null -eq $Value) {
        $valueToAssign = [System.DBNull]::Value
    }

    if ($Parameter -is [System.__ComObject]) {
        if (-not $script:AdodbParameterWrapperTypeResolved) {
            $script:AdodbParameterWrapperTypeResolved = $true
            try {
                $script:AdodbParameterWrapperType = [type]::GetTypeFromProgID('ADODB.Parameter', $true)
            } catch {
                $script:AdodbParameterWrapperType = $null
            }
        }

        if ($script:AdodbParameterWrapperType) {
            $wrapperProperty = $Parameter.PSObject.Properties['__AdodbParameterWrapper']
            $wrapper = if ($wrapperProperty) { $wrapperProperty.Value } else { $null }

            if (-not $wrapper) {
                try {
                    $wrapper = [System.Runtime.InteropServices.Marshal]::CreateWrapperOfType($Parameter, $script:AdodbParameterWrapperType)
                    if ($wrapperProperty) {
                        $wrapperProperty.Value = $wrapper
                    } else {
                        $Parameter.PSObject.Properties.Add((New-Object PSNoteProperty -ArgumentList '__AdodbParameterWrapper', $wrapper))
                    }
                } catch {
                    $wrapper = $null
                }
            }

            if ($wrapper) {
                try {
                    $wrapper.Value = $valueToAssign
                    return
                } catch {
                    # fall back to late binding attempt
                }
            }
        }

        try {
            $bindingFlags = [System.Reflection.BindingFlags]::SetProperty
            $culture = [System.Globalization.CultureInfo]::InvariantCulture
            $Parameter.GetType().InvokeMember('Value', $bindingFlags, $null, $Parameter, @($valueToAssign), $culture) | Out-Null
            return
        } catch {
            # fall through to default assignment
        }
    }

    $Parameter.Value = $valueToAssign
}

function Invoke-AdodbNonQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Connection,
        [Parameter(Mandatory=$true)][string]$CommandText,
        [switch]$ExpectRecords
    )

    if ($ExpectRecords) {
        try {
            return $Connection.Execute($CommandText)
        } catch {
            throw
        }
    }

    $recordsAffected = 0
    $useOptions = Test-IsAdodbConnection -Connection $Connection
    $options = if ($useOptions) { $script:AdExecuteNoRecords } else { $null }

    try {
        $refRecords = [ref]$recordsAffected
        if ($useOptions) {
            $executeSucceeded = $false
            try {
                $Connection.Execute($CommandText, $refRecords, $options) | Out-Null
                $executeSucceeded = $true
            } catch {
                # fall through to retry without optional arguments (useful for mocks)
            }

            if (-not $executeSucceeded) {
                $Connection.Execute($CommandText) | Out-Null
                $recordsAffected = 0
            }
        } else {
            $Connection.Execute($CommandText) | Out-Null
        }

        return $recordsAffected
    } catch {
        throw
    }
}

function Ensure-SpanInfoTableExists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Connection
    )

    if ($script:SpanTablesEnsured) {
        return
    }
    if (-not (Test-IsAdodbConnection -Connection $Connection)) {
        return
    }

    $createSpanInfoTable = @'
CREATE TABLE SpanInfo (
    Hostname    TEXT(64),
    Vlan        TEXT(32),
    RootSwitch  TEXT(64),
    RootPort    TEXT(32),
    Role        TEXT(32),
    Upstream    TEXT(64),
    LastUpdated DATETIME
);
'@
    $createSpanHistoryTable = @'
CREATE TABLE SpanHistory (
    ID          COUNTER     PRIMARY KEY,
    Hostname    TEXT(64),
    RunDate     DATETIME,
    Vlan        TEXT(32),
    RootSwitch  TEXT(64),
    RootPort    TEXT(32),
    Role        TEXT(32),
    Upstream    TEXT(64)
);
'@
    $createSpanInfoIndex     = "CREATE INDEX idx_spaninfo_host_vlan ON SpanInfo (Hostname, Vlan)"
    $createSpanHistoryIndex  = "CREATE INDEX idx_spanhistory_host ON SpanHistory (Hostname)"

    try { Invoke-AdodbNonQuery -Connection $Connection -CommandText $createSpanInfoTable | Out-Null } catch { }
    try { Invoke-AdodbNonQuery -Connection $Connection -CommandText $createSpanHistoryTable | Out-Null } catch { }
    try { Invoke-AdodbNonQuery -Connection $Connection -CommandText $createSpanInfoIndex | Out-Null } catch { }
    try { Invoke-AdodbNonQuery -Connection $Connection -CommandText $createSpanHistoryIndex | Out-Null } catch { }

    $script:SpanTablesEnsured = $true
}

function Ensure-InterfaceTableIndexes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Connection
    )

    if ($script:InterfaceIndexesEnsured -or $script:InterfaceIndexesEnsureAttempted) { return }
    if (-not (Test-IsAdodbConnection -Connection $Connection)) { return }

    $script:InterfaceIndexesEnsureAttempted = $true

    $indexStatements = @(
        "CREATE INDEX IX_Interfaces_Hostname ON Interfaces (Hostname)",
        "CREATE INDEX IX_Interfaces_HostnamePort ON Interfaces (Hostname, Port)",
        "CREATE INDEX IX_InterfaceHistory_HostnameRunDate ON InterfaceHistory (Hostname, RunDate)"
    )

    foreach ($sql in $indexStatements) {
        try {
            Invoke-AdodbNonQuery -Connection $Connection -CommandText $sql | Out-Null
        } catch {
            $message = $_.Exception.Message
            if ($null -ne $message -and $message -match 'already exists') {
                continue
            }

            Write-Verbose ("Failed to apply Access index '{0}': {1}" -f $sql, $message)
        }
    }

    $script:InterfaceIndexesEnsured = $true
}

function ConvertTo-DbDateTime {
    [CmdletBinding()]
    param(
        [Parameter()][string]$RunDateString
    )

    if ([string]::IsNullOrWhiteSpace($RunDateString)) { return $null }

    $formats = @('yyyy-MM-dd HH:mm:ss', 'yyyy-MM-ddTHH:mm:ss', 'o')
    foreach ($fmt in $formats) {
        try {
            return [DateTime]::ParseExact($RunDateString, $fmt, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeLocal)
        } catch { }
    }

    try { return [DateTime]::Parse($RunDateString, [System.Globalization.CultureInfo]::InvariantCulture) } catch { }
    try { return [DateTime]::Parse($RunDateString) } catch { }

    return $null
}



function Update-DeviceSummaryInDb {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Connection,
        [Parameter(Mandatory=$true)][object]$Facts,
        [Parameter(Mandatory=$true)][string]$Hostname,
        [Parameter(Mandatory=$true)][string]$SiteCode,
        [Parameter(Mandatory=$true)][hashtable]$LocationDetails,
        [Parameter(Mandatory=$true)][string]$RunDateString
    )
    # Escape single quotes for SQL literals.  PowerShell 5.1 does not support the
    $escHostname = $Hostname -replace "'", "''"
    # Make
    $rawMake = ''
    if ($Facts.PSObject.Properties.Name -contains 'Make' -and $Facts.Make) {
        $rawMake = $Facts.Make
    }
    $escMake = $rawMake -replace "'", "''"
    # Model
    $rawModel = ''
    if ($Facts.PSObject.Properties.Name -contains 'Model' -and $Facts.Model) {
        $rawModel = $Facts.Model
    }
    $escModel = $rawModel -replace "'", "''"
    # Uptime
    $rawUptime = ''
    if ($Facts.PSObject.Properties.Name -contains 'Uptime' -and $Facts.Uptime) {
        $rawUptime = $Facts.Uptime
    }
    $escUptime = $rawUptime -replace "'", "''"
    # Site code (always provided)
    $escSite = $SiteCode -replace "'", "''"
    # Building
    $rawBuilding = ''
    if ($LocationDetails.ContainsKey('Building') -and $LocationDetails.Building) {
        $rawBuilding = $LocationDetails.Building
    }
    $escBuilding = $rawBuilding -replace "'", "''"
    # Room
    $rawRoom = ''
    if ($LocationDetails.ContainsKey('Room') -and $LocationDetails.Room) {
        $rawRoom = $LocationDetails.Room
    }
    $escRoom = $rawRoom -replace "'", "''"
    # Determine number of interfaces if provided
    $portCount = 0
    if ($Facts.PSObject.Properties.Name -contains 'InterfaceCount') {
        $portCount = $Facts.InterfaceCount
    }
    # Extract the default authentication VLAN
    $rawAuthVlan = ''
    if ($Facts.PSObject.Properties.Name -contains 'AuthDefaultVLAN' -and $null -ne $Facts.AuthDefaultVLAN -and $Facts.AuthDefaultVLAN -ne '') {
        try { $rawAuthVlan = [string]$Facts.AuthDefaultVLAN } catch { $rawAuthVlan = '' + $Facts.AuthDefaultVLAN }
    }
    $escAuthVlan = $rawAuthVlan -replace "'", "''"
    # Compose the authentication block text
    $authBlockText = ''
    if ($Facts.PSObject.Properties.Name -contains 'AuthenticationBlock' -and $Facts.AuthenticationBlock) {
        $authBlockText = ($Facts.AuthenticationBlock -join "`r`n")
    }
    $escAuthBlock = $authBlockText -replace "'", "''"

    $paramValues = @{
        Make            = $rawMake
        Model           = $rawModel
        Uptime          = $rawUptime
        Site            = $SiteCode
        Building        = $rawBuilding
        Room            = $rawRoom
        Ports           = $portCount
        AuthDefaultVlan = $rawAuthVlan
        AuthBlock       = $authBlockText
    }

    $runDateValue = ConvertTo-DbDateTime -RunDateString $RunDateString
    if ($runDateValue -and (Test-IsAdodbConnection -Connection $Connection)) {
        if (Invoke-DeviceSummaryParameterized -Connection $Connection -Hostname $Hostname -Values $paramValues -RunDate $runDateValue) {
            return
        }
    }

    # Build update and insert statements.  The update will modify an existing
    $updateSql = "UPDATE DeviceSummary SET Make='$escMake', Model='$escModel', Uptime='$escUptime', Site='$escSite', Building='$escBuilding', Room='$escRoom', Ports=$portCount, AuthDefaultVLAN='$escAuthVlan', AuthBlock='$escAuthBlock' WHERE Hostname='$escHostname'"
    $insertSql = "INSERT INTO DeviceSummary (Hostname, Make, Model, Uptime, Site, Building, Room, Ports, AuthDefaultVLAN, AuthBlock) VALUES ('$escHostname', '$escMake', '$escModel', '$escUptime', '$escSite', '$escBuilding', '$escRoom', $portCount, '$escAuthVlan', '$escAuthBlock')"
    # Execute update and insert sequentially
    try {
        Invoke-AdodbNonQuery -Connection $Connection -CommandText $updateSql | Out-Null
    } catch {
        # ignore update errors
    }
    try {
        Invoke-AdodbNonQuery -Connection $Connection -CommandText $insertSql | Out-Null
    } catch {
        # duplicate key is expected on upsert; ignore
    }
    # Insert a row into DeviceHistory.  Use the run date literal enclosed
    $runDateLiteral = "#$RunDateString#"
    $histSql = "INSERT INTO DeviceHistory (Hostname, RunDate, Make, Model, Uptime, Site, Building, Room, Ports, AuthDefaultVLAN, AuthBlock) VALUES ('$escHostname', $runDateLiteral, '$escMake', '$escModel', '$escUptime', '$escSite', '$escBuilding', '$escRoom', $portCount, '$escAuthVlan', '$escAuthBlock')"
    try {
        Invoke-AdodbNonQuery -Connection $Connection -CommandText $histSql | Out-Null
    } catch {
        Write-Warning "Failed to insert device history for host ${Hostname}: $($_.Exception.Message)"
    }
}




function Update-InterfacesInDb {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Connection,
        [Parameter(Mandatory=$true)][object]$Facts,
        [Parameter(Mandatory=$true)][string]$Hostname,
        [Parameter(Mandatory=$true)][string]$RunDateString,
        [Parameter(Mandatory=$false)][object[]]$Templates,
        [string]$SiteCode,
        [bool]$SkipSiteCacheUpdate = $false
    )

    $script:LastInterfaceSyncTelemetry = $null

    $loadExistingDurationMs = 0.0
    $loadExistingRowSetCount = 0
    $diffDurationMs = 0.0
    $diffComparisonDurationMs = 0.0
    $deleteDurationMs = 0.0
    $fallbackDurationMs = 0.0
    $loadSignatureDurationMs = 0.0
    $diffSignatureDurationMs = 0.0
    $totalFactsCount = 0
    $fallbackUsed = $false
    $diffRowsCompared = 0
    $diffRowsUnchanged = 0
    $diffRowsChanged = 0
    $diffRowsInserted = 0

    $escHostname = $Hostname -replace "'", "''"

    $ifaceRecords = $null
    if ($Facts.PSObject.Properties.Name -contains 'InterfacesCombined') {
        $ifaceRecords = $Facts.InterfacesCombined
    } elseif ($Facts.PSObject.Properties.Name -contains 'Interfaces') {
        $ifaceRecords = $Facts.Interfaces
    }
    if (-not $ifaceRecords) { $ifaceRecords = @() }

    Ensure-InterfaceTableIndexes -Connection $Connection

    $skipSiteCacheUpdateSetting = (($SkipSiteCacheUpdate -eq $true) -or ($script:SkipSiteCacheUpdate -eq $true))

    $existingRows = $null
    $normalizedHostname = ('' + $Hostname).Trim()
    $siteCodeValue = $SiteCode
    if (-not $siteCodeValue -and $Facts) {
        if ($Facts.PSObject.Properties.Name -contains 'SiteCode' -and $Facts.SiteCode) {
            $candidateSiteCode = '' + $Facts.SiteCode
            if (-not [string]::IsNullOrWhiteSpace($candidateSiteCode)) {
                $siteCodeValue = $candidateSiteCode.Trim()
            }
        } elseif ($Facts.PSObject.Properties.Name -contains 'Site' -and $Facts.Site) {
            $candidateSite = '' + $Facts.Site
            if (-not [string]::IsNullOrWhiteSpace($candidateSite)) {
                $siteCodeValue = $candidateSite.Trim()
            }
        }
    }
    if (-not $siteCodeValue) {
        try {
            $siteCandidate = DeviceRepositoryModule\Get-SiteFromHostname -Hostname $Hostname
            if ($siteCandidate) {
                $siteCodeValue = ('' + $siteCandidate).Trim()
            }
        } catch { }
    }

    $siteExistingCache = $null
    $siteExistingCacheEnabled = $false
    $siteExistingCacheHit = $false
    if (-not [string]::IsNullOrWhiteSpace($siteCodeValue) -and ($skipSiteCacheUpdateSetting -or $script:SkipSiteCacheUpdate)) {
        $siteExistingCacheEnabled = $true
        if (-not $script:SiteExistingRowCache.ContainsKey($siteCodeValue)) {
            $script:SiteExistingRowCache[$siteCodeValue] = @{}
        }
        $siteExistingCache = $script:SiteExistingRowCache[$siteCodeValue]
    }

    if ($siteExistingCache -and $siteExistingCache.ContainsKey($normalizedHostname)) {
        $existingRows = $siteExistingCache[$normalizedHostname]
        if ($existingRows) {
            $siteExistingCacheHit = $true
            $loadCacheHit = $true
            $siteCacheExistingRowSource = 'SiteExistingCache'
        }
    }

    $loadCacheHit = $false
    $loadCacheMiss = $false
    $loadCacheRefreshed = $false
    $siteCacheResolveContext = @{
        Initial = @{
            Status = 'NotAttempted'
            HostMapType = ''
            HostCount = 0
            MatchedKey = ''
            KeysSample = ''
            CachedAt = $null
            CachedAtText = ''
            EntryType = ''
            PortCount = 0
            PortKeysSample = ''
            PortSignatureSample = ''
            PortSignatureMissingCount = 0
            PortSignatureEmptyCount = 0
        }
        Refresh = @{
            Status = 'NotAttempted'
            HostMapType = ''
            HostCount = 0
            MatchedKey = ''
            KeysSample = ''
            CachedAt = $null
            CachedAtText = ''
            EntryType = ''
            PortCount = 0
            PortKeysSample = ''
            PortSignatureSample = ''
            PortSignatureMissingCount = 0
            PortSignatureEmptyCount = 0
        }
    }
    $cachedRowCount = 0
    $cachePrimedRowCount = 0
    $siteCacheUpdateDurationMs = 0.0
    $siteCacheFetchDurationMs = 0.0
    $siteCacheRefreshDurationMs = 0.0
    $siteCacheFetchStatus = $null
    $siteCacheSnapshotDurationMs = 0.0
    $siteCacheRecordsetDurationMs = 0.0
    $siteCacheRecordsetProjectDurationMs = 0.0
    $siteCacheBuildDurationMs = 0.0
    $siteCacheHostMapDurationMs = 0.0
    $siteCacheHostMapSignatureMatchCount = 0L
    $siteCacheHostMapSignatureRewriteCount = 0L
    $siteCacheHostMapEntryAllocationCount = 0L
    $siteCacheHostMapEntryPoolReuseCount = 0L
    $siteCacheHostMapLookupCount = 0L
    $siteCacheHostMapLookupMissCount = 0L
    $siteCacheHostMapCandidateMissingCount = 0L
    $siteCacheHostMapCandidateSignatureMissingCount = 0L
    $siteCacheHostMapCandidateSignatureMismatchCount = 0L
    $siteCacheHostMapCandidateFromPreviousCount = 0L
    $siteCacheHostMapCandidateFromPoolCount = 0L
    $siteCacheHostMapCandidateInvalidCount = 0L
    $siteCacheHostMapCandidateMissingSamples = @()
    $siteCacheHostMapSignatureMismatchSamples = @()
    $siteCachePreviousHostCount = 0
    $siteCachePreviousPortCount = 0
    $siteCachePreviousHostSample = ''
    $siteCachePreviousSnapshotStatus = 'CacheEntryMissing'
    $siteCachePreviousSnapshotHostMapType = ''
    $siteCachePreviousSnapshotHostCount = 0
    $siteCachePreviousSnapshotPortCount = 0
    $siteCachePreviousSnapshotException = ''
    $siteCacheSortDurationMs = 0.0
    $siteCacheHostCount = 0
    $siteCacheQueryDurationMs = 0.0
    $siteCacheExecuteDurationMs = 0.0
$siteCacheMaterializeDurationMs = 0.0
$siteCacheMaterializeProjectionDurationMs = 0.0
$siteCacheMaterializePortSortDurationMs = 0.0
$siteCacheMaterializePortSortCacheHitCount = 0
$siteCacheMaterializePortSortCacheMissCount = 0
$siteCacheMaterializePortSortCacheSize = 0
$siteCacheMaterializePortSortCacheHitRatio = 0.0
$siteCacheMaterializePortSortUniquePortCount = 0
$siteCacheMaterializePortSortMissSamples = @()
$siteCacheMaterializeTemplateDurationMs = 0.0
$siteCacheMaterializeTemplateLookupDurationMs = 0.0
$siteCacheMaterializeTemplateApplyDurationMs = 0.0
$siteCacheMaterializeObjectDurationMs = 0.0
$siteCacheMaterializeTemplateCacheHitCount = 0
$siteCacheMaterializeTemplateCacheMissCount = 0
$siteCacheMaterializeTemplateReuseCount = 0
$siteCacheMaterializeTemplateCacheHitRatio = 0.0
$siteCacheMaterializeTemplateApplyCount = 0
$siteCacheMaterializeTemplateDefaultedCount = 0
$siteCacheMaterializeTemplateAuthTemplateMissingCount = 0
$siteCacheMaterializeTemplateNoTemplateMatchCount = 0
$siteCacheMaterializeTemplateHintAppliedCount = 0
$siteCacheMaterializeTemplateSetPortColorCount = 0
$siteCacheMaterializeTemplateSetConfigStatusCount = 0
$siteCacheMaterializeTemplateApplySamples = @()
$siteCacheTemplateDurationMs = 0.0
    $siteCacheQueryAttempts = 0
    $siteCacheExclusiveRetryCount = 0
    $siteCacheExclusiveWaitDurationMs = 0.0
    $siteCacheProvider = $null
    $siteCacheProviderReason = 'NotEvaluated'
    $siteCacheResultRowCount = 0
    $cacheComparisonCandidateCount = 0
    $cacheComparisonSignatureMatchCount = 0
    $cacheComparisonSignatureMismatchCount = 0
    $cacheComparisonSignatureMissingCount = 0
    $cacheComparisonMissingPortCount = 0
    $cacheComparisonObsoletePortCount = 0
    $siteCacheExistingRowCount = 0
    $siteCacheExistingRowKeysSample = ''
    $siteCacheExistingRowValueType = ''
    $siteCacheExistingRowSource = 'Unknown'

    $siteCacheEntry = $null
    $cachedHostEntry = $null
    $resolveCachedHost = {
        param(
            $entry,
            [string]$stage = 'Initial'
        )

        $context = $null
        if ($siteCacheResolveContext.ContainsKey($stage)) {
            $context = $siteCacheResolveContext[$stage]
        } else {
            $context = @{
                Status = 'NotAttempted'
                HostMapType = ''
                HostCount = 0
                MatchedKey = ''
                KeysSample = ''
                CachedAt = $null
                CachedAtText = ''
            }
            $siteCacheResolveContext[$stage] = $context
        }

        $context.Status = 'Ready'
        $context.HostMapType = ''
        $context.HostCount = 0
        $context.MatchedKey = ''
        $context.KeysSample = ''
        $context.CachedAt = $null
        $context.CachedAtText = ''
        $context.EntryType = ''
        $context.PortCount = 0
        $context.PortKeysSample = ''
        $context.PortSignatureSample = ''
        $context.PortSignatureMissingCount = 0
        $context.PortSignatureEmptyCount = 0

        $recordHostEntryDetails = {
            param($candidateEntry)

            $context.EntryType = ''
            $context.PortCount = 0
            $context.PortKeysSample = ''
            $context.PortSignatureSample = ''
            $context.PortSignatureMissingCount = 0
            $context.PortSignatureEmptyCount = 0

            if (-not $candidateEntry) { return }

            try { $context.EntryType = $candidateEntry.GetType().FullName } catch { $context.EntryType = '' }

            $portKeys = New-Object 'System.Collections.Generic.List[string]'
            $signatureSamples = New-Object 'System.Collections.Generic.List[string]'
            $signatureMissing = 0
            $signatureEmpty = 0

            $collectPortInfo = {
                param($portKeyValue, $portEntryValue)

                $normalizedKey = ''
                if ($null -ne $portKeyValue) {
                    try { $normalizedKey = ('' + $portKeyValue).Trim() } catch { $normalizedKey = '' }
                }
                if (-not [string]::IsNullOrWhiteSpace($normalizedKey) -and $portKeys.Count -lt 5) {
                    $portKeys.Add($normalizedKey) | Out-Null
                }

                $signatureValue = $null
                if ($null -ne $portEntryValue) {
                    try {
                        if ($portEntryValue -is [StateTrace.Models.InterfaceCacheEntry]) {
                            $signatureValue = $portEntryValue.Signature
                        } elseif ($portEntryValue -is [System.Collections.IDictionary]) {
                            if ($portEntryValue.Contains('Signature')) {
                                $signatureValue = $portEntryValue['Signature']
                            }
                        } else {
                            $entryPsObject = $null
                            try { $entryPsObject = $portEntryValue.PSObject } catch { $entryPsObject = $null }
                            if ($entryPsObject) {
                                $signatureProp = $entryPsObject.Properties['Signature']
                                if ($signatureProp) { $signatureValue = $signatureProp.Value }
                            }
                        }
                    } catch {
                        $signatureValue = $null
                    }
                }

                if ($null -eq $signatureValue -or $signatureValue -eq [System.DBNull]::Value) {
                    $signatureMissing++
                } else {
                    $signatureText = '' + $signatureValue
                    if ([string]::IsNullOrWhiteSpace($signatureText)) {
                        $signatureEmpty++
                    } elseif ($signatureSamples.Count -lt 5) {
                        $signatureSamples.Add($signatureText) | Out-Null
                    }
                }
            }

            if ($candidateEntry -is [System.Collections.IDictionary]) {
                try { $context.PortCount = [int]$candidateEntry.Count } catch { $context.PortCount = 0 }
                foreach ($portEntry in @($candidateEntry.GetEnumerator())) {
                    $portKey = $null
                    $portValue = $null
                    try { $portKey = $portEntry.Key } catch { $portKey = $null }
                    try { $portValue = $portEntry.Value } catch { $portValue = $null }
                    & $collectPortInfo $portKey $portValue
                }
            } elseif ($candidateEntry -is [System.Collections.IEnumerable] -and -not ($candidateEntry -is [string])) {
                $portCounter = 0
                foreach ($item in $candidateEntry) {
                    $portCounter++
                    $candidatePortKey = $null
                    if ($item -is [System.Collections.IDictionary]) {
                        try {
                            if ($item.Contains('Port')) { $candidatePortKey = $item['Port'] }
                        } catch { $candidatePortKey = $null }
                    } else {
                        $itemPsObject = $null
                        try { $itemPsObject = $item.PSObject } catch { $itemPsObject = $null }
                        if ($itemPsObject) {
                            $portProp = $itemPsObject.Properties['Port']
                            if ($portProp) { $candidatePortKey = $portProp.Value }
                        }
                    }
                    & $collectPortInfo $candidatePortKey $item
                }
                $context.PortCount = $portCounter
            }

            if ($portKeys.Count -gt 0) {
                $context.PortKeysSample = [string]::Join('|', $portKeys.ToArray())
            }
            if ($signatureSamples.Count -gt 0) {
                $context.PortSignatureSample = [string]::Join('|', $signatureSamples.ToArray())
            }
            $context.PortSignatureMissingCount = [int]$signatureMissing
            $context.PortSignatureEmptyCount = [int]$signatureEmpty
        }

        if (-not $entry) {
            $context.Status = 'EntryNull'
            return $null
        }

        if (-not $normalizedHostname) {
            $context.Status = 'HostnameMissing'
            return $null
        }

        if ($entry.PSObject.Properties.Name -contains 'CachedAt') {
            $rawCachedAt = $entry.CachedAt
            if ($rawCachedAt -is [datetime]) {
                $context.CachedAt = $rawCachedAt
                $context.CachedAtText = $rawCachedAt.ToString('o')
            } elseif ($null -ne $rawCachedAt) {
                $context.CachedAtText = '' + $rawCachedAt
                try {
                    $context.CachedAt = [datetime]$rawCachedAt
                } catch { }
            }
        }

        $hostMap = $null
        if ($entry.PSObject.Properties.Name -contains 'HostMap') {
            $hostMap = $entry.HostMap
        }

        if (-not $hostMap) {
            $context.Status = 'HostMapMissing'
            return $null
        }

        try {
            $context.HostMapType = $hostMap.GetType().FullName
        } catch {
            $context.HostMapType = ''
        }

        try {
            if ($hostMap.PSObject.Properties.Name -contains 'Count') {
                $context.HostCount = [int]$hostMap.Count
            } elseif ($hostMap -is [System.Collections.ICollection]) {
                $context.HostCount = [int]$hostMap.Count
            } elseif ($hostMap -is [System.Collections.IDictionary]) {
                $context.HostCount = [int]$hostMap.Count
            }
        } catch {
            $context.HostCount = 0
        }

        $context.Status = 'HostMapScanned'
        try {
            $sampleKeys = @()
            foreach ($cacheKey in $hostMap.Keys) {
                if ($sampleKeys.Count -ge 5) { break }
                if ($null -eq $cacheKey) { continue }
                $sampleKeys += ('' + $cacheKey)
            }
            if ($sampleKeys.Count -gt 0) {
                $context.KeysSample = [string]::Join('|', $sampleKeys)
            }
        } catch {
            $context.Status = 'EnumerationFailed'
        }

        $containsKeyMethod = $null
        try {
            $containsKeyMethod = $hostMap.PSObject.Methods['ContainsKey']
        } catch { }

        if ($containsKeyMethod) {
            try {
                if ($containsKeyMethod.Invoke($normalizedHostname)) {
                    $context.Status = 'ExactMatch'
                    $context.MatchedKey = $normalizedHostname
                    $matchedEntry = $hostMap[$normalizedHostname]
                    & $recordHostEntryDetails $matchedEntry
                    return $matchedEntry
                }
            } catch {
                $context.Status = 'ContainsKeyInvokeFailed'
            }
        } else {
            try {
                if ($hostMap.ContainsKey($normalizedHostname)) {
                    $context.Status = 'ExactMatch'
                    $context.MatchedKey = $normalizedHostname
                    $matchedEntry = $hostMap[$normalizedHostname]
                    & $recordHostEntryDetails $matchedEntry
                    return $matchedEntry
                }
            } catch {
                if ($context.Status -eq 'HostMapScanned') {
                    $context.Status = 'ContainsKeyMissing'
                }
            }
        }

        if ($context.Status -ne 'EnumerationFailed') {
            try {
                foreach ($cacheKey in $hostMap.Keys) {
                    if ([System.StringComparer]::OrdinalIgnoreCase.Equals($cacheKey, $normalizedHostname)) {
                        $context.Status = 'CaseInsensitiveMatch'
                        $context.MatchedKey = '' + $cacheKey
                        $matchedEntry = $hostMap[$cacheKey]
                        & $recordHostEntryDetails $matchedEntry
                        return $matchedEntry
                    }
                }
            } catch {
                $context.Status = 'EnumerationFailed'
            }
        }

        if ($context.Status -eq 'HostMapScanned' -or
            $context.Status -eq 'ContainsKeyMissing' -or
            $context.Status -eq 'ContainsKeyInvokeFailed') {
            $context.Status = 'NotFound'
        }

        return $null
    }
    $skipSiteCacheHydration = $false
    $sharedSiteCacheEntry = $null
    $sharedSiteCacheEntryAttempted = $false
    $sharedCacheHitStatus = 'SharedOnly'
    $skipAccessHydration = $false
    $siteCacheHitSource = 'None'
    if ($skipSiteCacheUpdateSetting) {
        $skipAccessHydration = $true
        if (-not $siteCacheFetchStatus) {
            $siteCacheFetchStatus = 'Disabled'
        }
        try {
            if ($siteCacheResolveContext.ContainsKey('Initial')) {
                $siteCacheResolveContext['Initial']['Status'] = 'Disabled'
            }
            if ($siteCacheResolveContext.ContainsKey('Refresh')) {
                $siteCacheResolveContext['Refresh']['Status'] = 'Disabled'
            }
        } catch { }
    }

    if ($siteCodeValue) {
        try {
            $siteCacheSummary = DeviceRepositoryModule\Get-InterfaceSiteCacheSummary -Site $siteCodeValue
            if ($siteCacheSummary -and ((-not $siteCacheSummary.CacheExists) -or ([int]$siteCacheSummary.TotalRows -le 0))) {
                $sharedSummaryEntry = $null
                try { $sharedSummaryEntry = DeviceRepositoryModule\Get-SharedSiteInterfaceCacheEntry -SiteKey $siteCodeValue } catch { $sharedSummaryEntry = $null }
                $sharedHostCount = 0
                $sharedTotalRows = 0
                if ($sharedSummaryEntry) {
                    if ($sharedSummaryEntry.PSObject.Properties.Name -contains 'HostMap') {
                        $sharedHostMap = $sharedSummaryEntry.HostMap
                        if ($sharedHostMap -is [System.Collections.IDictionary]) {
                            try { $sharedHostCount = [int]$sharedHostMap.Count } catch { $sharedHostCount = 0 }
                            foreach ($sharedHostEntry in @($sharedHostMap.GetEnumerator())) {
                                $sharedPorts = $sharedHostEntry.Value
                                if ($sharedPorts -is [System.Collections.IDictionary] -or $sharedPorts -is [System.Collections.ICollection]) {
                                    try { $sharedTotalRows += [int]$sharedPorts.Count } catch { }
                                }
                            }
                        }
                    }
                    if ($sharedSummaryEntry.PSObject.Properties.Name -contains 'HostCount' -and $sharedHostCount -le 0) {
                        try { $sharedHostCount = [int]$sharedSummaryEntry.HostCount } catch { }
                    }
                    if ($sharedSummaryEntry.PSObject.Properties.Name -contains 'TotalRows' -and $sharedTotalRows -le 0) {
                        try { $sharedTotalRows = [int]$sharedSummaryEntry.TotalRows } catch { }
                    }
                }

                if ($sharedHostCount -gt 0 -and $sharedTotalRows -gt 0) {
                    $skipSiteCacheHydration = $false
                    $siteCacheFetchStatus = $sharedCacheHitStatus
                    $cachePrimedRowCount = [int][Math]::Max($cachePrimedRowCount, $sharedTotalRows)
                    try {
                        if ($siteCacheResolveContext.ContainsKey('Initial')) {
                            $siteCacheResolveContext['Initial']['Status'] = 'SharedStoreSeed'
                            $siteCacheResolveContext['Initial']['HostCount'] = $sharedHostCount
                        }
                        if ($siteCacheResolveContext.ContainsKey('Refresh')) {
                            $siteCacheResolveContext['Refresh']['Status'] = 'SharedStoreSeed'
                            $siteCacheResolveContext['Refresh']['HostCount'] = $sharedHostCount
                        }
                    } catch { }
                } else {
                    $skipSiteCacheHydration = $true
                    $siteCacheFetchStatus = 'SkippedEmpty'
                    try {
                        if ($siteCacheResolveContext.ContainsKey('Initial')) {
                            $siteCacheResolveContext['Initial']['Status'] = 'SkippedEmpty'
                        }
                        if ($siteCacheResolveContext.ContainsKey('Refresh')) {
                            $siteCacheResolveContext['Refresh']['Status'] = 'SkippedEmpty'
                        }
                    } catch { }
                }
            }
        } catch { }
    }

    $resolveSharedHostEntry = {
        param(
            [string]$stage = 'Initial'
        )

        if (-not $siteCodeValue) { return $null }

        if (-not $sharedSiteCacheEntryAttempted) {
            $sharedSiteCacheEntryAttempted = $true
            try { $sharedSiteCacheEntry = DeviceRepositoryModule\Get-SharedSiteInterfaceCacheEntry -SiteKey $siteCodeValue } catch { $sharedSiteCacheEntry = $null }
        }
        if (-not $sharedSiteCacheEntry) { return $null }

        $sharedHostEntry = & $resolveCachedHost $sharedSiteCacheEntry $stage
        if (-not $sharedHostEntry) { return $null }

        $siteCacheEntry = $sharedSiteCacheEntry
        $siteCacheHitSource = 'Shared'
        $skipAccessHydration = $true
        if (-not $siteCacheFetchStatus -or $siteCacheFetchStatus -eq 'Refreshed' -or $siteCacheFetchStatus -eq 'Disabled' -or $siteCacheFetchStatus -eq 'SkippedEmpty') {
            $siteCacheFetchStatus = $sharedCacheHitStatus
        } elseif ($skipSiteCacheUpdateSetting -and $siteCacheFetchStatus -eq 'Hit') {
            $siteCacheFetchStatus = $sharedCacheHitStatus
        }
        if ($siteCacheEntry -and $siteCacheEntry.PSObject.Properties.Name -contains 'TotalRows') {
            $cachePrimedRowCount = [int][Math]::Max($cachePrimedRowCount, $siteCacheEntry.TotalRows)
        }
        try {
            if ($siteCacheResolveContext.ContainsKey($stage)) {
                $contextEntry = $siteCacheResolveContext[$stage]
                if ($contextEntry) {
                    $contextEntry['Status'] = 'SharedStoreMatch'
                    $contextEntry['MatchedKey'] = $normalizedHostname
                    if ($siteCacheEntry.PSObject.Properties.Name -contains 'HostCount') {
                        $contextEntry['HostCount'] = [int]$siteCacheEntry.HostCount
                    }
                    if ($siteCacheEntry.PSObject.Properties.Name -contains 'CachedAt') {
                        $cacheTimestamp = $siteCacheEntry.CachedAt
                        $contextEntry['CachedAt'] = $cacheTimestamp
                        $contextEntry['CachedAtText'] = if ($cacheTimestamp -is [datetime]) { $cacheTimestamp.ToString('o') } else { '' + $cacheTimestamp }
                    }
                }
            }
        } catch { }

        return $sharedHostEntry
    }

    if ($siteCodeValue) {
        if (-not $cachedHostEntry) {
            $cachedHostEntry = & $resolveSharedHostEntry 'Initial'
        }

        if (-not $cachedHostEntry -and -not $skipSiteCacheHydration -and -not $skipAccessHydration) {
            $siteCacheFetchStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            try {
                try { $siteCacheEntry = DeviceRepositoryModule\Get-InterfaceSiteCache -Site $siteCodeValue -Connection $Connection } catch { $siteCacheEntry = $null }
            } finally {
                if ($siteCacheFetchStopwatch) {
                    $siteCacheFetchStopwatch.Stop()
                    $siteCacheFetchDurationMs = [Math]::Round($siteCacheFetchStopwatch.Elapsed.TotalMilliseconds, 3)
                }
            }
            if ($siteCacheEntry -and $siteCacheEntry.PSObject.Properties.Name -contains 'TotalRows') {
                $cachePrimedRowCount = [int]$siteCacheEntry.TotalRows
            }
            $cachedHostEntry = & $resolveCachedHost $siteCacheEntry 'Initial'
            if ($cachedHostEntry) {
                $siteCacheHitSource = 'Access'
            }
        }

        if (-not $cachedHostEntry) {
            $cachedHostEntry = & $resolveSharedHostEntry 'Refresh'
        }

        if (-not $cachedHostEntry -and -not $skipSiteCacheHydration -and -not $skipAccessHydration) {
            $loadCacheRefreshed = $true
            $siteCacheRefreshStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            try {
                try { $siteCacheEntry = DeviceRepositoryModule\Get-InterfaceSiteCache -Site $siteCodeValue -Connection $Connection -Refresh } catch { $siteCacheEntry = $siteCacheEntry }
            } finally {
                if ($siteCacheRefreshStopwatch) {
                    $siteCacheRefreshStopwatch.Stop()
                    $siteCacheRefreshDurationMs = [Math]::Round($siteCacheRefreshStopwatch.Elapsed.TotalMilliseconds, 3)
                }
            }
            if ($siteCacheEntry -and $siteCacheEntry.PSObject.Properties.Name -contains 'TotalRows') {
                $cachePrimedRowCount = [int]$siteCacheEntry.TotalRows
            }
            $cachedHostEntry = & $resolveCachedHost $siteCacheEntry 'Refresh'
            if ($cachedHostEntry -and $siteCacheHitSource -eq 'None') {
                $siteCacheHitSource = 'Access'
            }
        }

        if (-not $cachedHostEntry) {
            $cachedHostEntry = & $resolveSharedHostEntry 'Refresh'
        }
    }

    if ($siteCodeValue -and -not $skipSiteCacheHydration) {
        try {
            $lastSiteCacheMetrics = DeviceRepositoryModule\Get-LastInterfaceSiteCacheMetrics
            if ($lastSiteCacheMetrics -and $lastSiteCacheMetrics.Site -and [System.StringComparer]::OrdinalIgnoreCase.Equals($lastSiteCacheMetrics.Site, $siteCodeValue)) {
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'CacheStatus') {
                    $statusText = '' + $lastSiteCacheMetrics.CacheStatus
                    if (-not [string]::IsNullOrWhiteSpace($statusText)) {
                        $siteCacheFetchStatus = $statusText
                    }
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationSnapshotMs') {
                    $siteCacheSnapshotDurationMs = [Math]::Round([double]$lastSiteCacheMetrics.HydrationSnapshotMs, 3)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationSnapshotRecordsetDurationMs') {
                    $siteCacheRecordsetDurationMs = [Math]::Round([double]$lastSiteCacheMetrics.HydrationSnapshotRecordsetDurationMs, 3)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationSnapshotProjectDurationMs') {
                    $siteCacheRecordsetProjectDurationMs = [Math]::Round([double]$lastSiteCacheMetrics.HydrationSnapshotProjectDurationMs, 3)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationBuildMs') {
                    $siteCacheBuildDurationMs = [Math]::Round([double]$lastSiteCacheMetrics.HydrationBuildMs, 3)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationHostMapDurationMs') {
                    $siteCacheHostMapDurationMs = [Math]::Round([double]$lastSiteCacheMetrics.HydrationHostMapDurationMs, 3)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationHostMapSignatureMatchCount') {
                    $siteCacheHostMapSignatureMatchCount = [long]$lastSiteCacheMetrics.HydrationHostMapSignatureMatchCount
                } elseif ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HostMapSignatureMatchCount') {
                    $siteCacheHostMapSignatureMatchCount = [long]$lastSiteCacheMetrics.HostMapSignatureMatchCount
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationHostMapSignatureRewriteCount') {
                    $siteCacheHostMapSignatureRewriteCount = [long]$lastSiteCacheMetrics.HydrationHostMapSignatureRewriteCount
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationHostMapEntryAllocationCount') {
                    $siteCacheHostMapEntryAllocationCount = [long]$lastSiteCacheMetrics.HydrationHostMapEntryAllocationCount
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationHostMapEntryPoolReuseCount') {
                    $siteCacheHostMapEntryPoolReuseCount = [long]$lastSiteCacheMetrics.HydrationHostMapEntryPoolReuseCount
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationHostMapLookupCount') {
                    $siteCacheHostMapLookupCount = [long]$lastSiteCacheMetrics.HydrationHostMapLookupCount
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationHostMapLookupMissCount') {
                    $siteCacheHostMapLookupMissCount = [long]$lastSiteCacheMetrics.HydrationHostMapLookupMissCount
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationHostMapCandidateMissingCount') {
                    $siteCacheHostMapCandidateMissingCount = [long]$lastSiteCacheMetrics.HydrationHostMapCandidateMissingCount
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationHostMapCandidateSignatureMissingCount') {
                    $siteCacheHostMapCandidateSignatureMissingCount = [long]$lastSiteCacheMetrics.HydrationHostMapCandidateSignatureMissingCount
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationHostMapCandidateSignatureMismatchCount') {
                    $siteCacheHostMapCandidateSignatureMismatchCount = [long]$lastSiteCacheMetrics.HydrationHostMapCandidateSignatureMismatchCount
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationHostMapCandidateFromPreviousCount') {
                    $siteCacheHostMapCandidateFromPreviousCount = [long]$lastSiteCacheMetrics.HydrationHostMapCandidateFromPreviousCount
                } elseif ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HostMapCandidateFromPreviousCount') {
                    $siteCacheHostMapCandidateFromPreviousCount = [long]$lastSiteCacheMetrics.HostMapCandidateFromPreviousCount
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationHostMapCandidateFromPoolCount') {
                    $siteCacheHostMapCandidateFromPoolCount = [long]$lastSiteCacheMetrics.HydrationHostMapCandidateFromPoolCount
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationHostMapCandidateInvalidCount') {
                    $siteCacheHostMapCandidateInvalidCount = [long]$lastSiteCacheMetrics.HydrationHostMapCandidateInvalidCount
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationHostMapCandidateMissingSamples') {
                    $rawMissingSamples = $lastSiteCacheMetrics.HydrationHostMapCandidateMissingSamples
                    if ($null -ne $rawMissingSamples) {
                        if ($rawMissingSamples -is [System.Collections.IEnumerable] -and -not ($rawMissingSamples -is [string])) {
                            $sampleList = New-Object 'System.Collections.Generic.List[object]'
                            foreach ($sample in $rawMissingSamples) {
                                $sampleList.Add($sample) | Out-Null
                            }
                            $siteCacheHostMapCandidateMissingSamples = $sampleList.ToArray()
                        } else {
                            $siteCacheHostMapCandidateMissingSamples = @($rawMissingSamples)
                        }
                    } else {
                        $siteCacheHostMapCandidateMissingSamples = @()
                    }
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationPreviousHostCount') {
                    $siteCachePreviousHostCount = [int]$lastSiteCacheMetrics.HydrationPreviousHostCount
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationPreviousPortCount') {
                    $siteCachePreviousPortCount = [int]$lastSiteCacheMetrics.HydrationPreviousPortCount
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationPreviousHostSample') {
                    $siteCachePreviousHostSample = '' + $lastSiteCacheMetrics.HydrationPreviousHostSample
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationPreviousSnapshotStatus') {
                    $siteCachePreviousSnapshotStatus = '' + $lastSiteCacheMetrics.HydrationPreviousSnapshotStatus
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationPreviousSnapshotHostMapType') {
                    $siteCachePreviousSnapshotHostMapType = '' + $lastSiteCacheMetrics.HydrationPreviousSnapshotHostMapType
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationPreviousSnapshotHostCount') {
                    $siteCachePreviousSnapshotHostCount = [int]$lastSiteCacheMetrics.HydrationPreviousSnapshotHostCount
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationPreviousSnapshotPortCount') {
                    $siteCachePreviousSnapshotPortCount = [int]$lastSiteCacheMetrics.HydrationPreviousSnapshotPortCount
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationPreviousSnapshotException') {
                    $siteCachePreviousSnapshotException = '' + $lastSiteCacheMetrics.HydrationPreviousSnapshotException
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationHostMapSignatureMismatchSamples') {
                    $rawMismatchSamples = $lastSiteCacheMetrics.HydrationHostMapSignatureMismatchSamples
                    if ($null -ne $rawMismatchSamples) {
                        if ($rawMismatchSamples -is [System.Collections.IEnumerable] -and -not ($rawMismatchSamples -is [string])) {
                            $sampleList = New-Object 'System.Collections.Generic.List[object]'
                            foreach ($sample in $rawMismatchSamples) {
                                $sampleList.Add($sample) | Out-Null
                            }
                            $siteCacheHostMapSignatureMismatchSamples = $sampleList.ToArray()
                        } else {
                            $siteCacheHostMapSignatureMismatchSamples = @($rawMismatchSamples)
                        }
                    } else {
                        $siteCacheHostMapSignatureMismatchSamples = @()
                    }
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationSortDurationMs') {
                    $siteCacheSortDurationMs = [Math]::Round([double]$lastSiteCacheMetrics.HydrationSortDurationMs, 3)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HostCount') {
                    $siteCacheHostCount = [int]$lastSiteCacheMetrics.HostCount
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationQueryDurationMs') {
                    $siteCacheQueryDurationMs = [Math]::Round([double]$lastSiteCacheMetrics.HydrationQueryDurationMs, 3)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationExecuteDurationMs') {
                    $siteCacheExecuteDurationMs = [Math]::Round([double]$lastSiteCacheMetrics.HydrationExecuteDurationMs, 3)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationMaterializeDurationMs') {
                    $siteCacheMaterializeDurationMs = [Math]::Round([double]$lastSiteCacheMetrics.HydrationMaterializeDurationMs, 3)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationMaterializeProjectionDurationMs') {
                    $siteCacheMaterializeProjectionDurationMs = [Math]::Round([double]$lastSiteCacheMetrics.HydrationMaterializeProjectionDurationMs, 3)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationMaterializePortSortDurationMs') {
                    $siteCacheMaterializePortSortDurationMs = [Math]::Round([double]$lastSiteCacheMetrics.HydrationMaterializePortSortDurationMs, 3)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationMaterializePortSortCacheHits') {
                    $siteCacheMaterializePortSortCacheHitCount = [long][Math]::Max(0, $lastSiteCacheMetrics.HydrationMaterializePortSortCacheHits)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationMaterializePortSortCacheMisses') {
                    $siteCacheMaterializePortSortCacheMissCount = [long][Math]::Max(0, $lastSiteCacheMetrics.HydrationMaterializePortSortCacheMisses)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationMaterializePortSortCacheSize') {
                    $siteCacheMaterializePortSortCacheSize = [long][Math]::Max(0, $lastSiteCacheMetrics.HydrationMaterializePortSortCacheSize)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationMaterializePortSortCacheHitRatio') {
                    $siteCacheMaterializePortSortCacheHitRatio = [Math]::Round([double]$lastSiteCacheMetrics.HydrationMaterializePortSortCacheHitRatio, 6)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationMaterializePortSortUniquePortCount') {
                    $siteCacheMaterializePortSortUniquePortCount = [long][Math]::Max(0, $lastSiteCacheMetrics.HydrationMaterializePortSortUniquePortCount)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationMaterializePortSortMissSamples') {
                    $siteCacheMaterializePortSortMissSamples = @($lastSiteCacheMetrics.HydrationMaterializePortSortMissSamples)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationMaterializeTemplateDurationMs') {
                    $siteCacheMaterializeTemplateDurationMs = [Math]::Round([double]$lastSiteCacheMetrics.HydrationMaterializeTemplateDurationMs, 3)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationMaterializeTemplateLookupDurationMs') {
                    $siteCacheMaterializeTemplateLookupDurationMs = [Math]::Round([double]$lastSiteCacheMetrics.HydrationMaterializeTemplateLookupDurationMs, 3)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationMaterializeTemplateApplyDurationMs') {
                    $siteCacheMaterializeTemplateApplyDurationMs = [Math]::Round([double]$lastSiteCacheMetrics.HydrationMaterializeTemplateApplyDurationMs, 3)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationMaterializeObjectDurationMs') {
                    $siteCacheMaterializeObjectDurationMs = [Math]::Round([double]$lastSiteCacheMetrics.HydrationMaterializeObjectDurationMs, 3)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationMaterializeTemplateCacheHitCount') {
                    $siteCacheMaterializeTemplateCacheHitCount = [long][Math]::Max(0, $lastSiteCacheMetrics.HydrationMaterializeTemplateCacheHitCount)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationMaterializeTemplateCacheMissCount') {
                    $siteCacheMaterializeTemplateCacheMissCount = [long][Math]::Max(0, $lastSiteCacheMetrics.HydrationMaterializeTemplateCacheMissCount)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationMaterializeTemplateReuseCount') {
                    $siteCacheMaterializeTemplateReuseCount = [long][Math]::Max(0, $lastSiteCacheMetrics.HydrationMaterializeTemplateReuseCount)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationMaterializeTemplateCacheHitRatio') {
                    $siteCacheMaterializeTemplateCacheHitRatio = [Math]::Round([double]$lastSiteCacheMetrics.HydrationMaterializeTemplateCacheHitRatio, 6)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationMaterializeTemplateApplyCount') {
                    $siteCacheMaterializeTemplateApplyCount = [long][Math]::Max(0, $lastSiteCacheMetrics.HydrationMaterializeTemplateApplyCount)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationMaterializeTemplateDefaultedCount') {
                    $siteCacheMaterializeTemplateDefaultedCount = [long][Math]::Max(0, $lastSiteCacheMetrics.HydrationMaterializeTemplateDefaultedCount)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationMaterializeTemplateAuthTemplateMissingCount') {
                    $siteCacheMaterializeTemplateAuthTemplateMissingCount = [long][Math]::Max(0, $lastSiteCacheMetrics.HydrationMaterializeTemplateAuthTemplateMissingCount)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationMaterializeTemplateNoTemplateMatchCount') {
                    $siteCacheMaterializeTemplateNoTemplateMatchCount = [long][Math]::Max(0, $lastSiteCacheMetrics.HydrationMaterializeTemplateNoTemplateMatchCount)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationMaterializeTemplateHintAppliedCount') {
                    $siteCacheMaterializeTemplateHintAppliedCount = [long][Math]::Max(0, $lastSiteCacheMetrics.HydrationMaterializeTemplateHintAppliedCount)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationMaterializeTemplateSetPortColorCount') {
                    $siteCacheMaterializeTemplateSetPortColorCount = [long][Math]::Max(0, $lastSiteCacheMetrics.HydrationMaterializeTemplateSetPortColorCount)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationMaterializeTemplateSetConfigStatusCount') {
                    $siteCacheMaterializeTemplateSetConfigStatusCount = [long][Math]::Max(0, $lastSiteCacheMetrics.HydrationMaterializeTemplateSetConfigStatusCount)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationMaterializeTemplateApplySamples') {
                    $siteCacheMaterializeTemplateApplySamples = @($lastSiteCacheMetrics.HydrationMaterializeTemplateApplySamples)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationTemplateDurationMs') {
                    $siteCacheTemplateDurationMs = [Math]::Round([double]$lastSiteCacheMetrics.HydrationTemplateDurationMs, 3)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationQueryAttempts') {
                    $siteCacheQueryAttempts = [int]$lastSiteCacheMetrics.HydrationQueryAttempts
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationExclusiveRetryCount') {
                    $siteCacheExclusiveRetryCount = [int]$lastSiteCacheMetrics.HydrationExclusiveRetryCount
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationExclusiveWaitDurationMs') {
                    $siteCacheExclusiveWaitDurationMs = [Math]::Round([double]$lastSiteCacheMetrics.HydrationExclusiveWaitDurationMs, 3)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationProvider') {
                    $providerValue = '' + $lastSiteCacheMetrics.HydrationProvider
                    if (-not [string]::IsNullOrWhiteSpace($providerValue)) {
                        $siteCacheProvider = $providerValue
                    }
                } elseif ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'Provider') {
                    $providerValue = '' + $lastSiteCacheMetrics.Provider
                    if (-not [string]::IsNullOrWhiteSpace($providerValue)) {
                        $siteCacheProvider = $providerValue
                    }
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationResultRowCount') {
                    $siteCacheResultRowCount = [int]$lastSiteCacheMetrics.HydrationResultRowCount
                } elseif ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'ResultRowCount') {
                    $siteCacheResultRowCount = [int]$lastSiteCacheMetrics.ResultRowCount
                }
            }
        } catch { }
    }

    if ($siteCacheHitSource -eq 'Shared') {
        $siteCacheFetchStatus = $sharedCacheHitStatus
        $siteCacheProvider = 'SharedCache'
        $siteCacheProviderReason = 'SharedCacheMatch'
    }
    $queryExistingRows = {
        $result = @{
            Rows = @{}
            LoadSignatureDurationMs = 0.0
        }

        $selectSqlLocal = "SELECT Port, Name, Status, VLAN, Duplex, Speed, Type, LearnedMACs, AuthState, AuthMode, AuthClientMAC, AuthTemplate, Config, PortColor, ConfigStatus, ToolTip FROM Interfaces WHERE Hostname = '$escHostname'"
        $recordsetLocal = $null
        try {
            $recordsetLocal = $Connection.Execute($selectSqlLocal)
            if ($recordsetLocal -and $recordsetLocal.State -eq 1) {
                while (-not $recordsetLocal.EOF) {
                    $portValue = '' + ($recordsetLocal.Fields.Item('Port').Value)
                    if (-not [string]::IsNullOrWhiteSpace($portValue)) {
                        $normalizedPort = $portValue.Trim()
                        $nameValue       = '' + ($recordsetLocal.Fields.Item('Name').Value)
                        $statusValue     = '' + ($recordsetLocal.Fields.Item('Status').Value)
                        $vlanValue       = '' + ($recordsetLocal.Fields.Item('VLAN').Value)
                        $duplexValue     = '' + ($recordsetLocal.Fields.Item('Duplex').Value)
                        $speedValue      = '' + ($recordsetLocal.Fields.Item('Speed').Value)
                        $typeValue       = '' + ($recordsetLocal.Fields.Item('Type').Value)
                        $learnedValue    = '' + ($recordsetLocal.Fields.Item('LearnedMACs').Value)
                        $authStateValue  = '' + ($recordsetLocal.Fields.Item('AuthState').Value)
                        $authModeValue   = '' + ($recordsetLocal.Fields.Item('AuthMode').Value)
                        $authClientValue = '' + ($recordsetLocal.Fields.Item('AuthClientMAC').Value)
                        $templateValue   = '' + ($recordsetLocal.Fields.Item('AuthTemplate').Value)
                        $configValue     = '' + ($recordsetLocal.Fields.Item('Config').Value)
                        $portColorValue  = '' + ($recordsetLocal.Fields.Item('PortColor').Value)
                        $statusTagValue  = '' + ($recordsetLocal.Fields.Item('ConfigStatus').Value)
                        $toolTipValue    = '' + ($recordsetLocal.Fields.Item('ToolTip').Value)

                        $existingRow = [PSCustomObject]@{
                            Name      = $nameValue
                            Status    = $statusValue
                            VLAN      = $vlanValue
                            Duplex    = $duplexValue
                            Speed     = $speedValue
                            Type      = $typeValue
                            Learned   = $learnedValue
                            AuthState = $authStateValue
                            AuthMode  = $authModeValue
                            AuthClient= $authClientValue
                            Template  = $templateValue
                            Config    = $configValue
                            PortColor = $portColorValue
                            StatusTag = $statusTagValue
                            ToolTip   = $toolTipValue
                        }

                        $signatureStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                        $rowSignature = Get-InterfaceSignatureFromValues -Values @(
                            $nameValue,
                            $statusValue,
                            $vlanValue,
                            $duplexValue,
                            $speedValue,
                            $typeValue,
                            $learnedValue,
                            $authStateValue,
                            $authModeValue,
                            $authClientValue,
                            $templateValue,
                            $configValue,
                            $portColorValue,
                            $statusTagValue,
                            $toolTipValue
                        )
                        $signatureStopwatch.Stop()
                        $result.LoadSignatureDurationMs += $signatureStopwatch.Elapsed.TotalMilliseconds
                        Add-Member -InputObject $existingRow -MemberType NoteProperty -Name Signature -Value $rowSignature -Force

                        $result.Rows[$normalizedPort] = $existingRow
                    }
                    $recordsetLocal.MoveNext() | Out-Null
                }
            }
        } catch {
            $result.Rows = @{}
        } finally {
            if ($recordsetLocal) {
                try { $recordsetLocal.Close() } catch { }
            }
        }

        return $result
    }

    $loadExistingStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    if ($existingRows -is [System.Collections.IDictionary] -and $existingRows.Count -gt 0) {
        $cachedRowCount = $existingRows.Count
    } elseif ($cachedHostEntry -is [System.Collections.IDictionary]) {
        $existingRows = @{}
        foreach ($key in $cachedHostEntry.Keys) {
            $existingRows[$key] = $cachedHostEntry[$key]
        }
        $loadCacheHit = $true
        $cachedRowCount = $cachedHostEntry.Count
    } elseif ($null -ne $cachedHostEntry) {
        $loadCacheHit = $true
        if ($cachedHostEntry -is [System.Collections.ICollection]) {
            $cachedRowCount = $cachedHostEntry.Count
        } else {
            $cachedRowCount = 0
        }
    } else {
        $loadCacheMiss = $true
        $queryResult = & $queryExistingRows
        $existingRows = $queryResult.Rows
        $loadSignatureDurationMs += $queryResult.LoadSignatureDurationMs
        $cachedRowCount = if ($existingRows) { [int]$existingRows.Count } else { 0 }
        if ($siteExistingCacheEnabled -and $existingRows -and -not $siteExistingCache.ContainsKey($normalizedHostname)) {
            $siteExistingCache[$normalizedHostname] = $existingRows
        }
        if ($siteCodeValue -and -not $skipSiteCacheUpdateSetting) {
            try { DeviceRepositoryModule\Set-InterfaceSiteCacheHost -Site $siteCodeValue -Hostname $normalizedHostname -RowsByPort $existingRows } catch { }
        }
    }
    $loadExistingStopwatch.Stop()
    $loadExistingDurationMs = [Math]::Round($loadExistingStopwatch.Elapsed.TotalMilliseconds, 3)

    $siteCacheExistingRowCount = if ($existingRows) { [int]$existingRows.Count } else { 0 }
    $loadExistingRowSetCount = $siteCacheExistingRowCount
    $siteCacheExistingRowKeysSample = ''
    if ($existingRows -is [System.Collections.IDictionary]) {
        try {
            $existingKeySamples = New-Object 'System.Collections.Generic.List[string]'
            foreach ($existingKeyCandidate in $existingRows.Keys) {
                if ($existingKeySamples.Count -ge 5) { break }
                if ($null -eq $existingKeyCandidate) { continue }
                try { $existingKeySamples.Add(('' + $existingKeyCandidate)) | Out-Null } catch { }
            }
            if ($existingKeySamples.Count -gt 0) {
                $siteCacheExistingRowKeysSample = [string]::Join('|', $existingKeySamples.ToArray())
            }
        } catch {
            $siteCacheExistingRowKeysSample = ''
        }
    }
    $siteCacheExistingRowValueType = ''
    if ($existingRows -is [System.Collections.IDictionary]) {
        try {
            foreach ($existingEntry in $existingRows.GetEnumerator()) {
                $valueCandidate = $null
                try { $valueCandidate = $existingEntry.Value } catch { $valueCandidate = $null }
                if ($null -eq $valueCandidate) { continue }
                try {
                    $siteCacheExistingRowValueType = $valueCandidate.GetType().FullName
                } catch {
                    $siteCacheExistingRowValueType = ''
                }
                if (-not [string]::IsNullOrEmpty($siteCacheExistingRowValueType)) { break }
            }
        } catch {
            $siteCacheExistingRowValueType = ''
        }
    } elseif ($existingRows -and ($existingRows -is [System.Collections.IEnumerable]) -and -not ($existingRows -is [string])) {
        foreach ($valueCandidate in $existingRows) {
            if ($null -eq $valueCandidate) { continue }
            try {
                $siteCacheExistingRowValueType = $valueCandidate.GetType().FullName
            } catch {
                $siteCacheExistingRowValueType = ''
            }
            if (-not [string]::IsNullOrEmpty($siteCacheExistingRowValueType)) { break }
        }
    }
    if ($siteExistingCacheHit) {
        $siteCacheExistingRowSource = 'SiteExistingCache'
    } elseif ($loadCacheHit -and $loadCacheRefreshed) {
        $siteCacheExistingRowSource = 'CacheRefresh'
    } elseif ($loadCacheHit) {
        $siteCacheExistingRowSource = 'CacheInitial'
    } elseif ($loadCacheMiss) {
        $siteCacheExistingRowSource = 'DatabaseQuery'
    } else {
        $siteCacheExistingRowSource = 'Unknown'
    }

    $toInsert = New-Object 'System.Collections.Generic.List[object]'
    $toUpdate = New-Object 'System.Collections.Generic.List[object]'
    $seenPorts = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    $runDateLiteral = "#$RunDateString#"
    $runDateValue = ConvertTo-DbDateTime -RunDateString $RunDateString
    $useAdodbParameters = $runDateValue -and (Test-IsAdodbConnection -Connection $Connection)

    $toDelete = New-Object 'System.Collections.Generic.List[string]'

    $createInterfaceRow = {
        param(
            [string]$Port,
            [string]$Name,
            [string]$Status,
            [string]$VlanText,
            [int]$VlanNumeric,
            [string]$Duplex,
            [string]$Speed,
            [string]$Type,
            [string]$Learned,
            [string]$AuthState,
            [string]$AuthMode,
            [string]$AuthClient,
            [string]$Template,
            [string]$Config,
            [string]$PortColor,
            [string]$StatusTag,
            [string]$ToolTip,
            [string]$Signature
        )

        return [PSCustomObject]@{
            Port        = $Port
            Name        = $Name
            Status      = $Status
            VLAN        = $VlanText
            VlanNumeric = $VlanNumeric
            Duplex      = $Duplex
            Speed       = $Speed
            Type        = $Type
            Learned     = $Learned
            AuthState   = $AuthState
            AuthMode    = $AuthMode
            AuthClient  = $AuthClient
            Template    = $Template
            Config      = $Config
            PortColor   = $PortColor
            StatusTag   = $StatusTag
            ToolTip     = $ToolTip
            Signature   = $Signature
        }
    }

    $diffStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
    foreach ($iface in $ifaceRecords) {
        if (-not $iface) { continue }
        $comparisonStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            $port = '' + $iface.Port
            if ([string]::IsNullOrWhiteSpace($port)) { continue }
            $normalizedPort = $port.Trim()
            $seenPorts.Add($normalizedPort) | Out-Null
            $totalFactsCount++

            $name   = '' + $iface.Name
            $status = '' + $iface.Status
            $vlan   = '' + $iface.VLAN
            $duplex = '' + $iface.Duplex
            $speed  = '' + $iface.Speed
            $type   = '' + $iface.Type

            $vlanNumeric = 0
            if (-not [int]::TryParse($vlan, [ref]$vlanNumeric)) { $vlanNumeric = 0 }

            $learned = ''
            if ($iface.PSObject.Properties.Name -contains 'LearnedMACsFull' -and ($iface.LearnedMACsFull)) {
                $learned = '' + $iface.LearnedMACsFull
            } elseif ($iface.PSObject.Properties.Name -contains 'LearnedMACs') {
                $lm = $iface.LearnedMACs
                if ($lm -is [string]) {
                    $learned = $lm
                } elseif ($lm) {
                    $macList = New-Object 'System.Collections.Generic.List[string]'
                    foreach ($mac in $lm) {
                        if ($mac -and $mac -ne '') { [void]$macList.Add($mac) }
                    }
                    $learned = [string]::Join(',', $macList.ToArray())
                }
            }

            $authState = ''
            if ($iface.PSObject.Properties.Name -contains 'AuthState') { $authState = '' + $iface.AuthState }
            $authMode = ''
            if ($iface.PSObject.Properties.Name -contains 'AuthMode') { $authMode = '' + $iface.AuthMode }
            $authClient = ''
            if ($iface.PSObject.Properties.Name -contains 'AuthClientMAC') { $authClient = '' + $iface.AuthClientMAC }
            $authTemplate = ''
            if ($iface.PSObject.Properties.Name -contains 'AuthTemplate') { $authTemplate = '' + $iface.AuthTemplate }

            $configText = ''
            if ($iface.PSObject.Properties.Name -contains 'Config') { $configText = '' + $iface.Config }
            if (-not $configText -or ($configText -is [string] -and $configText.Trim() -eq '')) {
                if ($Facts -and $Facts.Make -eq 'Brocade') {
                    if ($Facts.PSObject.Properties.Name -contains 'AuthenticationBlock' -and $Facts.AuthenticationBlock) {
                        $configText = "AUTH BLOCK (GLOBAL)`r`n" + ($Facts.AuthenticationBlock -join "`r`n")
            }

        $comparisonStopwatch.Stop()
        $diffComparisonDurationMs += $comparisonStopwatch.Elapsed.TotalMilliseconds
    }
            }

            $portColor = ''
            if ($iface.PSObject.Properties.Name -contains 'PortColor') { $portColor = '' + $iface.PortColor }
            $configStatus = ''
            if ($iface.PSObject.Properties.Name -contains 'ConfigStatus') { $configStatus = '' + $iface.ConfigStatus }
            $toolTip = ''
            if ($iface.PSObject.Properties.Name -contains 'ToolTip') { $toolTip = '' + $iface.ToolTip }

            if (-not $portColor -and $Templates) {
                foreach ($tpl in $Templates) {
                    if (-not $tpl) { continue }

                    $tplName = $null
                    $tplColor = $null

                    if ($tpl -is [hashtable]) {
                        if ($tpl.ContainsKey('TemplateName')) { $tplName = $tpl['TemplateName'] }
                        if ($tpl.ContainsKey('PortColor')) { $tplColor = $tpl['PortColor'] }
                    } else {
                        $props = $tpl.PSObject.Properties
                        if ($props.Name -contains 'TemplateName') { $tplName = $tpl.TemplateName }
                        if ($props.Name -contains 'PortColor') { $tplColor = $tpl.PortColor }
                    }

                    if ($tplName -and $tplColor -and $tplName -eq $authTemplate) {
                        $portColor = '' + $tplColor
                        break
                    }
                }
            }

            $signatureStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $newSignature = Get-InterfaceSignatureFromValues -Values @(
                $name,
                $status,
                $vlan,
                $duplex,
                $speed,
                $type,
                $learned,
                $authState,
                $authMode,
                $authClient,
                $authTemplate,
                $configText,
                $portColor,
                $configStatus,
                $toolTip
            )
            $signatureStopwatch.Stop()
            $diffSignatureDurationMs += $signatureStopwatch.Elapsed.TotalMilliseconds

            $diffRowsCompared++

            if ($existingRows.ContainsKey($normalizedPort)) {
                $existing = $existingRows[$normalizedPort]
                $existingSignature = $null
                $cacheComparisonCandidateCount++

                $existingSignaturePresent = $false
                if ($existing.PSObject.Properties.Name -contains 'Signature') {
                    $rawExistingSignature = $existing.Signature
                    if (-not [string]::IsNullOrWhiteSpace(('' + $rawExistingSignature))) {
                        $existingSignaturePresent = $true
                    }
                }
                if (-not $existingSignaturePresent) {
                    $cacheComparisonSignatureMissingCount++
                }

                if ($existing.PSObject.Properties.Name -contains 'Signature' -and $existing.Signature) {
                    $existingSignature = '' + $existing.Signature
                } else {
                    $signatureStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                    $existingSignature = Get-InterfaceRowSignature -Row $existing
                    $signatureStopwatch.Stop()
                    $loadSignatureDurationMs += $signatureStopwatch.Elapsed.TotalMilliseconds
                    Add-Member -InputObject $existing -MemberType NoteProperty -Name Signature -Value $existingSignature -Force
                }

                if (-not [System.StringComparer]::Ordinal.Equals($newSignature, $existingSignature)) {
                    $cacheComparisonSignatureMismatchCount++
                    $diffRowsChanged++
                    $toUpdate.Add((& $createInterfaceRow `
                        $normalizedPort `
                        $name `
                        $status `
                        $vlan `
                        $vlanNumeric `
                        $duplex `
                        $speed `
                        $type `
                        $learned `
                        $authState `
                        $authMode `
                        $authClient `
                        $authTemplate `
                        $configText `
                        $portColor `
                        $configStatus `
                        $toolTip `
                        $newSignature)) | Out-Null
                } else {
                    $cacheComparisonSignatureMatchCount++
                    $diffRowsUnchanged++
                }
            } else {
                $cacheComparisonMissingPortCount++
                $diffRowsInserted++
                $toInsert.Add((& $createInterfaceRow `
                    $normalizedPort `
                    $name `
                    $status `
                    $vlan `
                    $vlanNumeric `
                    $duplex `
                    $speed `
                    $type `
                    $learned `
                    $authState `
                    $authMode `
                    $authClient `
                    $authTemplate `
                    $configText `
                    $portColor `
                    $configStatus `
                    $toolTip `
                    $newSignature)) | Out-Null
            }
        }
        foreach ($existingPort in $existingRows.Keys) {

            if (-not $seenPorts.Contains($existingPort)) {

                $cacheComparisonObsoletePortCount++
                $toDelete.Add($existingPort) | Out-Null

            }

        }
    } finally {
        $diffStopwatch.Stop()
        $diffDurationMs = [Math]::Round($diffStopwatch.Elapsed.TotalMilliseconds, 3)
    }



    $deleteBatchSize = 50

    $invokeDeleteBatch = {
        param(
            [string[]]$PortBatch,
            [string]$ContextLabel
        )

        if (-not $PortBatch -or $PortBatch.Count -eq 0) { return }

        $escapedPorts = New-Object 'System.Collections.Generic.List[string]'
        foreach ($portName in $PortBatch) {
            $candidate = $portName
            if ($null -eq $candidate) { $candidate = '' }
            $escapedPorts.Add("'" + ($candidate -replace "'", "''") + "'") | Out-Null
        }

        $deleteSql = "DELETE FROM Interfaces WHERE Hostname = '$escHostname' AND Port IN (" + ([string]::Join(',', $escapedPorts)) + ")"

        try {
            Invoke-AdodbNonQuery -Connection $Connection -CommandText $deleteSql | Out-Null
        } catch {
            if ($PortBatch.Count -le 1) {
                $portDetail = if ($PortBatch.Count -eq 1) { $PortBatch[0] } else { '<unknown>' }
                $label = if ([string]::IsNullOrWhiteSpace($ContextLabel)) { 'interface port' } else { $ContextLabel }
                Write-Warning ("Failed to delete {0} {1}/{2}: {3}" -f $label, $Hostname, $portDetail, $_.Exception.Message)
            } else {
                foreach ($singlePort in $PortBatch) {
                    & $invokeDeleteBatch @($singlePort) $ContextLabel
                }
            }
        }
    }

    $removeInterfacePorts = {
        param(
            [System.Collections.Generic.IEnumerable[string]]$PortSequence,
            [string]$ContextLabel,
            [System.Collections.Generic.HashSet[string]]$SeenPorts
        )

        if (-not $PortSequence) { return }
        if (-not $SeenPorts) {
            $SeenPorts = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        }

        $batch = New-Object 'System.Collections.Generic.List[string]'

        foreach ($portName in $PortSequence) {
            if ([string]::IsNullOrWhiteSpace($portName)) { continue }
            if (-not $SeenPorts.Add($portName)) { continue }

            $batch.Add($portName) | Out-Null

            if ($batch.Count -ge $deleteBatchSize) {
                & $invokeDeleteBatch $batch.ToArray() $ContextLabel
                $batch.Clear()
            }
        }

        if ($batch.Count -gt 0) {
            & $invokeDeleteBatch $batch.ToArray() $ContextLabel
        }
    }

    if ($toDelete.Count -gt 0) {
        $deleteStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            & $removeInterfacePorts $toDelete 'stale interface port'
        } finally {
            $deleteStopwatch.Stop()
            $deleteDurationMs += $deleteStopwatch.Elapsed.TotalMilliseconds
        }
    }



    function Add-InterfaceRow {

        param(

            [object]$Row

        )



        $escPort      = $Row.Port       -replace "'", "''"

        $escName      = $Row.Name       -replace "'", "''"

        $escStatus    = $Row.Status     -replace "'", "''"

        $escDuplex    = $Row.Duplex     -replace "'", "''"

        $escSpeed     = $Row.Speed      -replace "'", "''"

        $escType      = $Row.Type       -replace "'", "''"

        $escLearned   = $Row.Learned    -replace "'", "''"

        $escState     = $Row.AuthState  -replace "'", "''"

        $escModeFld   = $Row.AuthMode   -replace "'", "''"

        $escClient    = $Row.AuthClient -replace "'", "''"

        $escTemplate  = $Row.Template   -replace "'", "''"

        $escConfig    = $Row.Config     -replace "'", "''"

        $escColor     = $Row.PortColor  -replace "'", "''"

        $escCfgStat   = $Row.StatusTag  -replace "'", "''"

        $escToolTip   = $Row.ToolTip    -replace "'", "''"



        $vlanNumeric = 0

        if ($Row.PSObject.Properties.Name -contains 'VlanNumeric' -and $null -ne $Row.VlanNumeric) {

            try { $vlanNumeric = [int]$Row.VlanNumeric } catch { $vlanNumeric = 0 }

        } else {

            [void][int]::TryParse($Row.VLAN, [ref]$vlanNumeric)

        }



        $ifaceSql = "INSERT INTO Interfaces (Hostname, Port, Name, Status, VLAN, Duplex, Speed, Type, LearnedMACs, AuthState, AuthMode, AuthClientMAC, AuthTemplate, Config, PortColor, ConfigStatus, ToolTip) VALUES ('$escHostname', '$escPort', '$escName', '$escStatus', $vlanNumeric, '$escDuplex', '$escSpeed', '$escType', '$escLearned', '$escState', '$escModeFld', '$escClient', '$escTemplate', '$escConfig', '$escColor', '$escCfgStat', '$escToolTip')"

        try { Invoke-AdodbNonQuery -Connection $Connection -CommandText $ifaceSql | Out-Null } catch { Write-Warning "Failed to insert interface record for host ${Hostname} port ${Row.Port}: $($_.Exception.Message)" }



        $histIfaceSql = "INSERT INTO InterfaceHistory (Hostname, RunDate, Port, Name, Status, VLAN, Duplex, Speed, Type, LearnedMACs, AuthState, AuthMode, AuthClientMAC, AuthTemplate, Config, PortColor, ConfigStatus, ToolTip) VALUES ('$escHostname', $runDateLiteral, '$escPort', '$escName', '$escStatus', $vlanNumeric, '$escDuplex', '$escSpeed', '$escType', '$escLearned', '$escState', '$escModeFld', '$escClient', '$escTemplate', '$escConfig', '$escColor', '$escCfgStat', '$escToolTip')"

        try { Invoke-AdodbNonQuery -Connection $Connection -CommandText $histIfaceSql | Out-Null } catch { Write-Warning "Failed to insert interface history for host ${Hostname} port ${Row.Port}: $($_.Exception.Message)" }

    }



    $rowsToWrite = New-Object 'System.Collections.Generic.List[object]'

    foreach ($row in $toInsert) { $rowsToWrite.Add($row) | Out-Null }

    foreach ($row in $toUpdate) { $rowsToWrite.Add($row) | Out-Null }



    $insertRowCount = if ($toInsert) { [int]$toInsert.Count } else { 0 }
    $updateRowCount = if ($toUpdate) { [int]$toUpdate.Count } else { 0 }

    $bulkSucceeded = $false
    $bulkAttempted = $false
    $bulkMetrics = $null

    $script:LastInterfaceBulkInsertMetrics = $null

    if ($useAdodbParameters -and $rowsToWrite.Count -gt 0) {

        $bulkAttempted = $true

        try {

            $bulkMetrics = $null
            $bulkResult = Invoke-InterfaceBulkInsertInternal -Connection $Connection -Hostname $Hostname -RunDate $runDateValue -Rows $rowsToWrite -InsertRowCount $insertRowCount -UpdateRowCount $updateRowCount

            $bulkSucceeded = [bool]$bulkResult
            if ($script:LastInterfaceBulkInsertMetrics) {
                $bulkMetrics = $script:LastInterfaceBulkInsertMetrics
            }

        } catch {

            Write-Verbose ("Bulk interface insert failed for {0}: {1}" -f $Hostname, $_.Exception.Message)

            $bulkSucceeded = $false
            if ($script:LastInterfaceBulkInsertMetrics) {
                $bulkMetrics = $script:LastInterfaceBulkInsertMetrics
            } else {
                $bulkMetrics = $null
            }

        }

    }



    if (-not $bulkSucceeded) {

        $fallbackShouldRun = ($toInsert.Count -gt 0 -or $toUpdate.Count -gt 0)
        $fallbackStopwatch = $null

        if ($fallbackShouldRun) {
            $fallbackUsed = $true
            $fallbackStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        }

        try {
            if ($toUpdate.Count -gt 0) {
                $fallbackDeleteStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                try {
                    $updatePorts = New-Object 'System.Collections.Generic.List[string]'
                    foreach ($row in $toUpdate) {
                        if ($row -and $row.PSObject.Properties.Name -contains 'Port') {
                            $updatePorts.Add([string]$row.Port) | Out-Null
                        }
                    }

                    if ($updatePorts.Count -gt 0) {
                        & $removeInterfacePorts $updatePorts 'existing interface port'
                    }
                } finally {
                    $fallbackDeleteStopwatch.Stop()
                    $deleteDurationMs += $fallbackDeleteStopwatch.Elapsed.TotalMilliseconds
                }
            }

            if ($useAdodbParameters) {

                foreach ($row in $toInsert) {

                    $handled = Invoke-InterfaceRowParameterized -Connection $Connection -Hostname $Hostname -Row $row -RunDate $runDateValue

                    if (-not $handled) { Add-InterfaceRow -Row $row }

                }



                foreach ($row in $toUpdate) {

                    $handled = Invoke-InterfaceRowParameterized -Connection $Connection -Hostname $Hostname -Row $row -RunDate $runDateValue

                    if (-not $handled) { Add-InterfaceRow -Row $row }

                }

            } else {

                foreach ($row in $toInsert) {

                    Add-InterfaceRow -Row $row

                }



                foreach ($row in $toUpdate) {

                    Add-InterfaceRow -Row $row

                }

            }
        } finally {
            if ($fallbackStopwatch) {
                $fallbackStopwatch.Stop()
                $fallbackDurationMs = [Math]::Round($fallbackStopwatch.Elapsed.TotalMilliseconds, 3)
            }
        }

    }

    try {
        $rowsInserted = if ($toInsert) { [int]$toInsert.Count } else { 0 }
        $rowsUpdated  = if ($toUpdate) { [int]$toUpdate.Count } else { 0 }
        $rowsDeleted  = if ($toDelete) { [int]$toDelete.Count } else { 0 }
        if (-not $siteCodeValue) {
            try {
                $siteCandidate = DeviceRepositoryModule\Get-SiteFromHostname -Hostname $Hostname
                if ($siteCandidate) { $siteCodeValue = ('' + $siteCandidate).Trim() }
            } catch { }
        }
        TelemetryModule\Write-StTelemetryEvent -Name 'RowsWritten' -Payload @{
            Hostname   = $Hostname
            Site       = $siteCodeValue
            RunDate    = $RunDateString
            Rows       = ($rowsInserted + $rowsUpdated)
            DeletedRows= $rowsDeleted
        }

        $finalHostRows = @{}
        foreach ($key in $existingRows.Keys) {
            $finalHostRows[$key] = $existingRows[$key]
        }
        foreach ($row in $toUpdate) {
            if ($row -and $row.PSObject.Properties.Name -contains 'Port') {
                $portKey = ('' + $row.Port).Trim()
                if ($portKey) { $finalHostRows[$portKey] = $row }
            }
        }
        foreach ($row in $toInsert) {
            if ($row -and $row.PSObject.Properties.Name -contains 'Port') {
                $portKey = ('' + $row.Port).Trim()
                if ($portKey) { $finalHostRows[$portKey] = $row }
            }
        }
        foreach ($port in $toDelete) {
            if ($port) {
                $trimmedPort = ('' + $port).Trim()
                if ($trimmedPort) { [void]$finalHostRows.Remove($trimmedPort) }
            }
        }
        if ($siteCodeValue -and -not $skipSiteCacheUpdateSetting) {
            $siteCacheStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            try { DeviceRepositoryModule\Set-InterfaceSiteCacheHost -Site $siteCodeValue -Hostname $normalizedHostname -RowsByPort $finalHostRows } catch { }
            $siteCacheStopwatch.Stop()
            $siteCacheUpdateDurationMs = [Math]::Round($siteCacheStopwatch.Elapsed.TotalMilliseconds, 3)
        }

        $bulkStageDurationMs = if ($bulkMetrics) { [double]$bulkMetrics.StageDurationMs } else { 0.0 }
        $bulkParameterBindDurationMs = if ($bulkMetrics) { [double]$bulkMetrics.ParameterBindDurationMs } else { 0.0 }
        $bulkCommandExecuteDurationMs = if ($bulkMetrics) { [double]$bulkMetrics.CommandExecuteDurationMs } else { 0.0 }
        $bulkInterfaceUpdateDurationMs = if ($bulkMetrics) { [double]$bulkMetrics.InterfaceUpdateDurationMs } else { 0.0 }
        $bulkInterfaceInsertDurationMs = if ($bulkMetrics) { [double]$bulkMetrics.InterfaceInsertDurationMs } else { 0.0 }
        $bulkHistoryInsertDurationMs = if ($bulkMetrics) { [double]$bulkMetrics.HistoryInsertDurationMs } else { 0.0 }
        $bulkCleanupDurationMs = if ($bulkMetrics) { [double]$bulkMetrics.CleanupDurationMs } else { 0.0 }
        $bulkTransactionCommitDurationMs = if ($bulkMetrics) { [double]$bulkMetrics.TransactionCommitDurationMs } else { 0.0 }
        $bulkRecordsetAttempted = if ($bulkMetrics) { [bool]$bulkMetrics.RecordsetAttempted } else { $false }
        $bulkRecordsetUsed = if ($bulkMetrics) { [bool]$bulkMetrics.RecordsetUsed } else { $false }
        $bulkRowsPrepared = if ($bulkMetrics) { [int]$bulkMetrics.Rows } else { 0 }
        $bulkRowsStaged = if ($bulkMetrics -and $bulkMetrics.PSObject.Properties.Name -contains 'RowsStaged') { [int]$bulkMetrics.RowsStaged } else { 0 }
        $bulkBatchId = if ($bulkMetrics -and $bulkMetrics.PSObject.Properties.Name -contains 'BatchId') { [string]$bulkMetrics.BatchId } else { $null }
        $bulkStreamDispatchDurationMs = if ($bulkMetrics -and $bulkMetrics.PSObject.Properties.Name -contains 'StreamDispatchDurationMs') { [double]$bulkMetrics.StreamDispatchDurationMs } else { 0.0 }
        $uiCloneDurationMsValue = if ($bulkMetrics -and $bulkMetrics.PSObject.Properties.Name -contains 'UiCloneDurationMs') { [double]$bulkMetrics.UiCloneDurationMs } else { 0.0 }
        $streamCloneDurationMs = if ($bulkMetrics -and $bulkMetrics.PSObject.Properties.Name -contains 'StreamCloneDurationMs') { [double]$bulkMetrics.StreamCloneDurationMs } else { 0.0 }
        $streamStateUpdateDurationMs = if ($bulkMetrics -and $bulkMetrics.PSObject.Properties.Name -contains 'StreamStateUpdateDurationMs') { [double]$bulkMetrics.StreamStateUpdateDurationMs } else { 0.0 }
        $streamRowsReceived = if ($bulkMetrics -and $bulkMetrics.PSObject.Properties.Name -contains 'StreamRowsReceived') { [int]$bulkMetrics.StreamRowsReceived } else { 0 }
        $streamRowsReused = if ($bulkMetrics -and $bulkMetrics.PSObject.Properties.Name -contains 'StreamRowsReused') { [int]$bulkMetrics.StreamRowsReused } else { 0 }
        $streamRowsCloned = if ($bulkMetrics -and $bulkMetrics.PSObject.Properties.Name -contains 'StreamRowsCloned') { [int]$bulkMetrics.StreamRowsCloned } else { 0 }

        if (-not $siteCacheFetchStatus) {
            if ($loadCacheRefreshed) {
                $siteCacheFetchStatus = 'Refreshed'
            } elseif ($loadCacheHit) {
                $siteCacheFetchStatus = if ($siteCacheHitSource -eq 'Shared') { $sharedCacheHitStatus } else { 'Hit' }
            } elseif ($loadCacheMiss) {
                $siteCacheFetchStatus = 'Miss'
            } else {
                $siteCacheFetchStatus = 'Unknown'
            }
        }
        if ($siteCacheHitSource -eq 'Shared') {
            $siteCacheFetchStatus = $sharedCacheHitStatus
        }

    if (-not $siteCacheProvider) {
        if ($loadCacheRefreshed) {
            $siteCacheProvider = 'Refreshed'
            $siteCacheProviderReason = 'AccessRefresh'
        } elseif ($loadCacheHit) {
            if ($siteCacheHitSource -eq 'Shared') {
                $siteCacheProvider = 'SharedCache'
                if ([string]::IsNullOrWhiteSpace($siteCacheProviderReason) -or $siteCacheProviderReason -eq 'NotEvaluated') {
                    $siteCacheProviderReason = 'SharedCacheMatch'
                }
            } else {
                $siteCacheProvider = 'Cache'
                $siteCacheProviderReason = 'AccessCacheHit'
            }
        } else {
            $siteCacheProvider = 'Unknown'
            if ($skipSiteCacheUpdateSetting -or $skipAccessHydration) {
                $siteCacheProviderReason = 'SkipSiteCacheUpdate'
            } elseif ($skipSiteCacheHydration) {
                $siteCacheProviderReason = 'SharedCacheUnavailable'
            } else {
                $siteCacheProviderReason = 'DatabaseQueryFallback'
            }
        }
    }
    if ([string]::IsNullOrWhiteSpace($siteCacheProviderReason)) {
        if ($siteCacheProvider -eq 'SharedCache') {
            $siteCacheProviderReason = 'SharedCacheMatch'
        } elseif ($siteCacheProvider -eq 'Refreshed') {
            $siteCacheProviderReason = 'AccessRefresh'
        } elseif ($siteCacheProvider -eq 'Cache') {
            $siteCacheProviderReason = 'AccessCacheHit'
        } elseif ($siteCacheProvider -eq 'Unknown') {
            $siteCacheProviderReason = 'Undetermined'
        }
    }
    if ($siteCacheResultRowCount -le 0) {
        if ($cachePrimedRowCount -gt 0) {
            $siteCacheResultRowCount = $cachePrimedRowCount
        } elseif ($cachedRowCount -gt 0) {
            $siteCacheResultRowCount = $cachedRowCount
        }
    }

    $siteCacheResolveInitialStatus = 'NotCaptured'
    $siteCacheResolveInitialHostCount = 0
    $siteCacheResolveInitialMatchedKey = ''
    $siteCacheResolveInitialKeysSample = ''
    $siteCacheResolveInitialCacheAgeMs = $null
    $siteCacheResolveInitialCachedAtText = ''
    $siteCacheResolveInitialEntryType = ''
    $siteCacheResolveInitialPortCount = 0
    $siteCacheResolveInitialPortKeysSample = ''
    $siteCacheResolveInitialPortSignatureSample = ''
    $siteCacheResolveInitialPortSignatureMissingCount = 0
    $siteCacheResolveInitialPortSignatureEmptyCount = 0
    if ($siteCacheResolveContext.ContainsKey('Initial')) {
        $initialContext = $siteCacheResolveContext['Initial']
        if ($initialContext) {
            if ($initialContext.Status) { $siteCacheResolveInitialStatus = '' + $initialContext.Status }
            if ($initialContext.HostCount -or $initialContext.HostCount -eq 0) { $siteCacheResolveInitialHostCount = [int]$initialContext.HostCount }
            if ($initialContext.MatchedKey) { $siteCacheResolveInitialMatchedKey = '' + $initialContext.MatchedKey }
            if ($initialContext.KeysSample) { $siteCacheResolveInitialKeysSample = '' + $initialContext.KeysSample }
            if ($initialContext.CachedAtText) { $siteCacheResolveInitialCachedAtText = '' + $initialContext.CachedAtText }
            if ($initialContext.EntryType) { $siteCacheResolveInitialEntryType = '' + $initialContext.EntryType }
            if ($initialContext.PortCount -or $initialContext.PortCount -eq 0) { $siteCacheResolveInitialPortCount = [int]$initialContext.PortCount }
            if ($initialContext.PortKeysSample) { $siteCacheResolveInitialPortKeysSample = '' + $initialContext.PortKeysSample }
            if ($initialContext.PortSignatureSample) { $siteCacheResolveInitialPortSignatureSample = '' + $initialContext.PortSignatureSample }
            if ($initialContext.PortSignatureMissingCount -or $initialContext.PortSignatureMissingCount -eq 0) { $siteCacheResolveInitialPortSignatureMissingCount = [int]$initialContext.PortSignatureMissingCount }
            if ($initialContext.PortSignatureEmptyCount -or $initialContext.PortSignatureEmptyCount -eq 0) { $siteCacheResolveInitialPortSignatureEmptyCount = [int]$initialContext.PortSignatureEmptyCount }
            if ($initialContext.CachedAt -is [datetime]) {
                try {
                    $initialAge = (Get-Date) - $initialContext.CachedAt
                    $siteCacheResolveInitialCacheAgeMs = [Math]::Round($initialAge.TotalMilliseconds, 3)
                } catch { }
            }
        }
    }

    $siteCacheResolveRefreshStatus = 'NotCaptured'
    $siteCacheResolveRefreshHostCount = 0
    $siteCacheResolveRefreshMatchedKey = ''
    $siteCacheResolveRefreshKeysSample = ''
    $siteCacheResolveRefreshCacheAgeMs = $null
    $siteCacheResolveRefreshCachedAtText = ''
    $siteCacheResolveRefreshEntryType = ''
    $siteCacheResolveRefreshPortCount = 0
    $siteCacheResolveRefreshPortKeysSample = ''
    $siteCacheResolveRefreshPortSignatureSample = ''
    $siteCacheResolveRefreshPortSignatureMissingCount = 0
    $siteCacheResolveRefreshPortSignatureEmptyCount = 0
    if ($siteCacheResolveContext.ContainsKey('Refresh')) {
        $refreshContext = $siteCacheResolveContext['Refresh']
        if ($refreshContext) {
            if ($refreshContext.Status) { $siteCacheResolveRefreshStatus = '' + $refreshContext.Status }
            if ($refreshContext.HostCount -or $refreshContext.HostCount -eq 0) { $siteCacheResolveRefreshHostCount = [int]$refreshContext.HostCount }
            if ($refreshContext.MatchedKey) { $siteCacheResolveRefreshMatchedKey = '' + $refreshContext.MatchedKey }
            if ($refreshContext.KeysSample) { $siteCacheResolveRefreshKeysSample = '' + $refreshContext.KeysSample }
            if ($refreshContext.CachedAtText) { $siteCacheResolveRefreshCachedAtText = '' + $refreshContext.CachedAtText }
            if ($refreshContext.EntryType) { $siteCacheResolveRefreshEntryType = '' + $refreshContext.EntryType }
            if ($refreshContext.PortCount -or $refreshContext.PortCount -eq 0) { $siteCacheResolveRefreshPortCount = [int]$refreshContext.PortCount }
            if ($refreshContext.PortKeysSample) { $siteCacheResolveRefreshPortKeysSample = '' + $refreshContext.PortKeysSample }
            if ($refreshContext.PortSignatureSample) { $siteCacheResolveRefreshPortSignatureSample = '' + $refreshContext.PortSignatureSample }
            if ($refreshContext.PortSignatureMissingCount -or $refreshContext.PortSignatureMissingCount -eq 0) { $siteCacheResolveRefreshPortSignatureMissingCount = [int]$refreshContext.PortSignatureMissingCount }
            if ($refreshContext.PortSignatureEmptyCount -or $refreshContext.PortSignatureEmptyCount -eq 0) { $siteCacheResolveRefreshPortSignatureEmptyCount = [int]$refreshContext.PortSignatureEmptyCount }
            if ($refreshContext.CachedAt -is [datetime]) {
                try {
                    $refreshAge = (Get-Date) - $refreshContext.CachedAt
                    $siteCacheResolveRefreshCacheAgeMs = [Math]::Round($refreshAge.TotalMilliseconds, 3)
                } catch { }
            }
        }
    }

    if ($siteCacheHostMapCandidateMissingSamples) {
        $appendCandidateSampleDetail = {
            param($targetSample, [string]$propertyName, $propertyValue)

            if ($null -eq $targetSample -or [string]::IsNullOrWhiteSpace($propertyName)) { return }

            if ($targetSample -is [System.Collections.IDictionary]) {
                $targetSample[$propertyName] = $propertyValue
                return
            }

            $targetPsObject = $null
            try { $targetPsObject = $targetSample.PSObject } catch { $targetPsObject = $null }
            if ($targetPsObject) {
                try { Add-Member -InputObject $targetSample -MemberType NoteProperty -Name $propertyName -Value $propertyValue -Force } catch { }
            }
        }

        foreach ($sample in $siteCacheHostMapCandidateMissingSamples) {
            if (-not $sample) { continue }

            & $appendCandidateSampleDetail $sample 'ParserResolveInitialStatus' $siteCacheResolveInitialStatus
            & $appendCandidateSampleDetail $sample 'ParserExistingRowCount' $siteCacheExistingRowCount
            if (-not [string]::IsNullOrWhiteSpace($siteCacheExistingRowKeysSample)) {
                & $appendCandidateSampleDetail $sample 'ParserExistingRowKeysSample' $siteCacheExistingRowKeysSample
            }
            if (-not [string]::IsNullOrWhiteSpace($siteCacheExistingRowValueType)) {
                & $appendCandidateSampleDetail $sample 'ParserExistingRowValueType' $siteCacheExistingRowValueType
            }
            & $appendCandidateSampleDetail $sample 'ParserExistingRowSource' $siteCacheExistingRowSource
            & $appendCandidateSampleDetail $sample 'ParserLoadCacheHit' $loadCacheHit
            & $appendCandidateSampleDetail $sample 'ParserLoadCacheMiss' $loadCacheMiss
            & $appendCandidateSampleDetail $sample 'ParserLoadCacheRefreshed' $loadCacheRefreshed
        }
    }

    TelemetryModule\Write-StTelemetryEvent -Name 'InterfaceSyncTiming' -Payload @{
        Hostname = $Hostname
        Site = $siteCodeValue
        UiCloneDurationMs = $uiCloneDurationMsValue
        LoadExistingDurationMs = $loadExistingDurationMs
            LoadExistingRowSetCount = $loadExistingRowSetCount
            LoadSignatureDurationMs = [Math]::Round($loadSignatureDurationMs, 3)
            LoadCacheHit = $loadCacheHit
            LoadCacheMiss = $loadCacheMiss
            LoadCacheRefreshed = $loadCacheRefreshed
            CachedRowCount = $cachedRowCount
            CachePrimedRowCount = $cachePrimedRowCount
        SiteCacheResolveInitialStatus = $siteCacheResolveInitialStatus
        SiteCacheResolveInitialHostCount = $siteCacheResolveInitialHostCount
        SiteCacheResolveInitialMatchedKey = $siteCacheResolveInitialMatchedKey
        SiteCacheResolveInitialKeysSample = $siteCacheResolveInitialKeysSample
        SiteCacheResolveInitialCacheAgeMs = $siteCacheResolveInitialCacheAgeMs
        SiteCacheResolveInitialCachedAt = $siteCacheResolveInitialCachedAtText
        SiteCacheResolveInitialEntryType = $siteCacheResolveInitialEntryType
        SiteCacheResolveInitialPortCount = $siteCacheResolveInitialPortCount
        SiteCacheResolveInitialPortKeysSample = $siteCacheResolveInitialPortKeysSample
        SiteCacheResolveInitialPortSignatureSample = $siteCacheResolveInitialPortSignatureSample
        SiteCacheResolveInitialPortSignatureMissingCount = $siteCacheResolveInitialPortSignatureMissingCount
        SiteCacheResolveInitialPortSignatureEmptyCount = $siteCacheResolveInitialPortSignatureEmptyCount
        SiteCacheResolveRefreshStatus = $siteCacheResolveRefreshStatus
        SiteCacheResolveRefreshHostCount = $siteCacheResolveRefreshHostCount
        SiteCacheResolveRefreshMatchedKey = $siteCacheResolveRefreshMatchedKey
        SiteCacheResolveRefreshKeysSample = $siteCacheResolveRefreshKeysSample
        SiteCacheResolveRefreshCacheAgeMs = $siteCacheResolveRefreshCacheAgeMs
        SiteCacheResolveRefreshCachedAt = $siteCacheResolveRefreshCachedAtText
        SiteCacheResolveRefreshEntryType = $siteCacheResolveRefreshEntryType
        SiteCacheResolveRefreshPortCount = $siteCacheResolveRefreshPortCount
        SiteCacheResolveRefreshPortKeysSample = $siteCacheResolveRefreshPortKeysSample
        SiteCacheResolveRefreshPortSignatureSample = $siteCacheResolveRefreshPortSignatureSample
        SiteCacheResolveRefreshPortSignatureMissingCount = $siteCacheResolveRefreshPortSignatureMissingCount
        SiteCacheResolveRefreshPortSignatureEmptyCount = $siteCacheResolveRefreshPortSignatureEmptyCount
        SiteCacheFetchDurationMs = $siteCacheFetchDurationMs
        SiteCacheRefreshDurationMs = $siteCacheRefreshDurationMs
        SiteCacheFetchStatus = $siteCacheFetchStatus
        SiteCacheSnapshotDurationMs = $siteCacheSnapshotDurationMs
        SiteCacheRecordsetDurationMs = $siteCacheRecordsetDurationMs
        SiteCacheRecordsetProjectDurationMs = $siteCacheRecordsetProjectDurationMs
        SiteCacheBuildDurationMs = $siteCacheBuildDurationMs
        SiteCacheHostMapDurationMs = $siteCacheHostMapDurationMs
        SiteCacheHostMapSignatureMatchCount   = $siteCacheHostMapSignatureMatchCount
        SiteCacheHostMapSignatureRewriteCount = $siteCacheHostMapSignatureRewriteCount
        SiteCacheHostMapEntryAllocationCount  = $siteCacheHostMapEntryAllocationCount
        SiteCacheHostMapEntryPoolReuseCount   = $siteCacheHostMapEntryPoolReuseCount
        SiteCacheHostMapLookupCount           = $siteCacheHostMapLookupCount
        SiteCacheHostMapLookupMissCount       = $siteCacheHostMapLookupMissCount
        SiteCacheHostMapCandidateMissingCount = $siteCacheHostMapCandidateMissingCount
        SiteCacheHostMapCandidateSignatureMissingCount = $siteCacheHostMapCandidateSignatureMissingCount
        SiteCacheHostMapCandidateSignatureMismatchCount = $siteCacheHostMapCandidateSignatureMismatchCount
        SiteCacheHostMapCandidateFromPreviousCount = $siteCacheHostMapCandidateFromPreviousCount
        SiteCacheHostMapCandidateFromPoolCount     = $siteCacheHostMapCandidateFromPoolCount
        SiteCacheHostMapCandidateInvalidCount      = $siteCacheHostMapCandidateInvalidCount
        SiteCacheHostMapCandidateMissingSamples    = $siteCacheHostMapCandidateMissingSamples
        SiteCacheHostMapSignatureMismatchSamples   = $siteCacheHostMapSignatureMismatchSamples
        SiteCachePreviousHostCount = $siteCachePreviousHostCount
        SiteCachePreviousPortCount = $siteCachePreviousPortCount
        SiteCachePreviousHostSample = $siteCachePreviousHostSample
        SiteCachePreviousSnapshotStatus = $siteCachePreviousSnapshotStatus
        SiteCachePreviousSnapshotHostMapType = $siteCachePreviousSnapshotHostMapType
        SiteCachePreviousSnapshotHostCount = $siteCachePreviousSnapshotHostCount
        SiteCachePreviousSnapshotPortCount = $siteCachePreviousSnapshotPortCount
        SiteCachePreviousSnapshotException = $siteCachePreviousSnapshotException
        SiteCacheSortDurationMs = $siteCacheSortDurationMs
        SiteCacheHostCount = $siteCacheHostCount
        SiteCacheQueryDurationMs = $siteCacheQueryDurationMs
        SiteCacheExecuteDurationMs = $siteCacheExecuteDurationMs
        SiteCacheMaterializeDurationMs = $siteCacheMaterializeDurationMs
        SiteCacheMaterializeProjectionDurationMs = $siteCacheMaterializeProjectionDurationMs
        SiteCacheMaterializePortSortDurationMs   = $siteCacheMaterializePortSortDurationMs
        SiteCacheMaterializePortSortCacheHitCount   = $siteCacheMaterializePortSortCacheHitCount
        SiteCacheMaterializePortSortCacheMissCount = $siteCacheMaterializePortSortCacheMissCount
        SiteCacheMaterializePortSortCacheSize      = $siteCacheMaterializePortSortCacheSize
        SiteCacheMaterializePortSortCacheHitRatio  = $siteCacheMaterializePortSortCacheHitRatio
        SiteCacheMaterializePortSortUniquePortCount = $siteCacheMaterializePortSortUniquePortCount
        SiteCacheMaterializePortSortMissSamples      = $siteCacheMaterializePortSortMissSamples
        SiteCacheMaterializeTemplateDurationMs   = $siteCacheMaterializeTemplateDurationMs
        SiteCacheMaterializeTemplateLookupDurationMs = $siteCacheMaterializeTemplateLookupDurationMs
        SiteCacheMaterializeTemplateApplyDurationMs  = $siteCacheMaterializeTemplateApplyDurationMs
        SiteCacheMaterializeTemplateCacheHitCount    = $siteCacheMaterializeTemplateCacheHitCount
        SiteCacheMaterializeTemplateCacheMissCount   = $siteCacheMaterializeTemplateCacheMissCount
        SiteCacheMaterializeTemplateReuseCount       = $siteCacheMaterializeTemplateReuseCount
        SiteCacheMaterializeTemplateCacheHitRatio    = $siteCacheMaterializeTemplateCacheHitRatio
        SiteCacheMaterializeTemplateApplyCount        = $siteCacheMaterializeTemplateApplyCount
        SiteCacheMaterializeTemplateDefaultedCount    = $siteCacheMaterializeTemplateDefaultedCount
        SiteCacheMaterializeTemplateAuthTemplateMissingCount = $siteCacheMaterializeTemplateAuthTemplateMissingCount
        SiteCacheMaterializeTemplateNoTemplateMatchCount     = $siteCacheMaterializeTemplateNoTemplateMatchCount
        SiteCacheMaterializeTemplateHintAppliedCount   = $siteCacheMaterializeTemplateHintAppliedCount
        SiteCacheMaterializeTemplateSetPortColorCount  = $siteCacheMaterializeTemplateSetPortColorCount
        SiteCacheMaterializeTemplateSetConfigStatusCount = $siteCacheMaterializeTemplateSetConfigStatusCount
        SiteCacheMaterializeTemplateApplySamples       = $siteCacheMaterializeTemplateApplySamples
        SiteCacheMaterializeObjectDurationMs     = $siteCacheMaterializeObjectDurationMs
        SiteCacheTemplateDurationMs = $siteCacheTemplateDurationMs
        SiteCacheQueryAttempts = $siteCacheQueryAttempts
        SiteCacheExclusiveRetryCount = $siteCacheExclusiveRetryCount
        SiteCacheExclusiveWaitDurationMs = $siteCacheExclusiveWaitDurationMs
        SiteCacheProvider = $siteCacheProvider
        SiteCacheProviderReason = $siteCacheProviderReason
        SiteCacheResultRowCount = $siteCacheResultRowCount
        SiteCacheExistingRowCount = $siteCacheExistingRowCount
        SiteCacheExistingRowKeysSample = $siteCacheExistingRowKeysSample
        SiteCacheExistingRowValueType = $siteCacheExistingRowValueType
        SiteCacheExistingRowSource = $siteCacheExistingRowSource
        SiteCacheComparisonCandidateCount = $cacheComparisonCandidateCount
        SiteCacheComparisonSignatureMatchCount = $cacheComparisonSignatureMatchCount
        SiteCacheComparisonSignatureMismatchCount = $cacheComparisonSignatureMismatchCount
        SiteCacheComparisonSignatureMissingCount = $cacheComparisonSignatureMissingCount
        SiteCacheComparisonMissingPortCount = $cacheComparisonMissingPortCount
        SiteCacheComparisonObsoletePortCount = $cacheComparisonObsoletePortCount
        DiffDurationMs = $diffDurationMs
            DiffComparisonDurationMs = [Math]::Round($diffComparisonDurationMs, 3)
            DiffSignatureDurationMs = [Math]::Round($diffSignatureDurationMs, 3)
            DeleteDurationMs = [Math]::Round($deleteDurationMs, 3)
            FallbackDurationMs = $fallbackDurationMs
            FactsConsidered = $totalFactsCount
            ExistingCount = [int]$existingRows.Count
            InsertCandidates = $rowsInserted
            UpdateCandidates = $rowsUpdated
            DeleteCandidates = $rowsDeleted
            DiffRowsCompared = $diffRowsCompared
            DiffRowsUnchanged = $diffRowsUnchanged
            DiffRowsChanged = $diffRowsChanged
            DiffRowsInserted = $diffRowsInserted
            DiffSeenPorts = [int]$seenPorts.Count
            DiffDuplicatePorts = [int][Math]::Max(0, $totalFactsCount - $seenPorts.Count)
            RowsStaged = [int]$rowsToWrite.Count
            BulkAttempted = $bulkAttempted
            BulkSucceeded = $bulkSucceeded
            FallbackUsed = $fallbackUsed
            BulkStageDurationMs = $bulkStageDurationMs
            BulkParameterBindDurationMs = $bulkParameterBindDurationMs
            BulkCommandExecuteDurationMs = $bulkCommandExecuteDurationMs
            BulkInterfaceUpdateDurationMs = $bulkInterfaceUpdateDurationMs
            BulkInterfaceInsertDurationMs = $bulkInterfaceInsertDurationMs
            BulkHistoryInsertDurationMs = $bulkHistoryInsertDurationMs
            BulkCleanupDurationMs = $bulkCleanupDurationMs
            BulkTransactionCommitDurationMs = $bulkTransactionCommitDurationMs
            BulkRecordsetAttempted = $bulkRecordsetAttempted
            BulkRecordsetUsed = $bulkRecordsetUsed
            BulkRowsPrepared = $bulkRowsPrepared
            BulkRowsCommitted = $bulkRowsStaged
            BulkBatchId = $bulkBatchId
            StreamDispatchDurationMs = $bulkStreamDispatchDurationMs
            StreamCloneDurationMs = $streamCloneDurationMs
            StreamStateUpdateDurationMs = $streamStateUpdateDurationMs
            StreamRowsReceived = $streamRowsReceived
            StreamRowsReused = $streamRowsReused
            StreamRowsCloned = $streamRowsCloned
            SiteCacheUpdateDurationMs = $siteCacheUpdateDurationMs
        }
        $script:LastInterfaceSyncTelemetry = [pscustomobject]@{
            Hostname = $Hostname
            Site = $siteCodeValue
            FactsConsidered = $totalFactsCount
            LoadCacheHit = $loadCacheHit
        LoadCacheMiss = $loadCacheMiss
        LoadCacheRefreshed = $loadCacheRefreshed
        CachedRowCount = $cachedRowCount
        CachePrimedRowCount = $cachePrimedRowCount
        SiteCacheResolveInitialStatus = $siteCacheResolveInitialStatus
        SiteCacheResolveInitialHostCount = $siteCacheResolveInitialHostCount
        SiteCacheResolveInitialMatchedKey = $siteCacheResolveInitialMatchedKey
        SiteCacheResolveInitialKeysSample = $siteCacheResolveInitialKeysSample
        SiteCacheResolveInitialCacheAgeMs = $siteCacheResolveInitialCacheAgeMs
        SiteCacheResolveInitialCachedAt = $siteCacheResolveInitialCachedAtText
        SiteCacheResolveInitialEntryType = $siteCacheResolveInitialEntryType
        SiteCacheResolveInitialPortCount = $siteCacheResolveInitialPortCount
        SiteCacheResolveInitialPortKeysSample = $siteCacheResolveInitialPortKeysSample
        SiteCacheResolveInitialPortSignatureSample = $siteCacheResolveInitialPortSignatureSample
        SiteCacheResolveInitialPortSignatureMissingCount = $siteCacheResolveInitialPortSignatureMissingCount
        SiteCacheResolveInitialPortSignatureEmptyCount = $siteCacheResolveInitialPortSignatureEmptyCount
        SiteCacheResolveRefreshStatus = $siteCacheResolveRefreshStatus
        SiteCacheResolveRefreshHostCount = $siteCacheResolveRefreshHostCount
        SiteCacheResolveRefreshMatchedKey = $siteCacheResolveRefreshMatchedKey
        SiteCacheResolveRefreshKeysSample = $siteCacheResolveRefreshKeysSample
        SiteCacheResolveRefreshCacheAgeMs = $siteCacheResolveRefreshCacheAgeMs
        SiteCacheResolveRefreshCachedAt = $siteCacheResolveRefreshCachedAtText
        SiteCacheResolveRefreshEntryType = $siteCacheResolveRefreshEntryType
        SiteCacheResolveRefreshPortCount = $siteCacheResolveRefreshPortCount
        SiteCacheResolveRefreshPortKeysSample = $siteCacheResolveRefreshPortKeysSample
        SiteCacheResolveRefreshPortSignatureSample = $siteCacheResolveRefreshPortSignatureSample
        SiteCacheResolveRefreshPortSignatureMissingCount = $siteCacheResolveRefreshPortSignatureMissingCount
        SiteCacheResolveRefreshPortSignatureEmptyCount = $siteCacheResolveRefreshPortSignatureEmptyCount
        SiteCacheFetchDurationMs = $siteCacheFetchDurationMs
        SiteCacheRefreshDurationMs = $siteCacheRefreshDurationMs
        SiteCacheFetchStatus = $siteCacheFetchStatus
        SiteCacheSnapshotDurationMs = $siteCacheSnapshotDurationMs
        SiteCacheRecordsetDurationMs = $siteCacheRecordsetDurationMs
        SiteCacheRecordsetProjectDurationMs = $siteCacheRecordsetProjectDurationMs
        SiteCacheBuildDurationMs = $siteCacheBuildDurationMs
        SiteCacheHostMapDurationMs = $siteCacheHostMapDurationMs
        SiteCacheHostMapSignatureMatchCount   = $siteCacheHostMapSignatureMatchCount
        SiteCacheHostMapSignatureRewriteCount = $siteCacheHostMapSignatureRewriteCount
        SiteCacheHostMapEntryAllocationCount  = $siteCacheHostMapEntryAllocationCount
        SiteCacheHostMapEntryPoolReuseCount   = $siteCacheHostMapEntryPoolReuseCount
        SiteCacheHostMapLookupCount           = $siteCacheHostMapLookupCount
        SiteCacheHostMapLookupMissCount       = $siteCacheHostMapLookupMissCount
        SiteCacheHostMapCandidateMissingCount = $siteCacheHostMapCandidateMissingCount
        SiteCacheHostMapCandidateSignatureMissingCount = $siteCacheHostMapCandidateSignatureMissingCount
        SiteCacheHostMapCandidateSignatureMismatchCount = $siteCacheHostMapCandidateSignatureMismatchCount
        SiteCacheHostMapCandidateFromPreviousCount = $siteCacheHostMapCandidateFromPreviousCount
        SiteCacheHostMapCandidateFromPoolCount     = $siteCacheHostMapCandidateFromPoolCount
        SiteCacheHostMapCandidateInvalidCount      = $siteCacheHostMapCandidateInvalidCount
        SiteCacheHostMapCandidateMissingSamples    = $siteCacheHostMapCandidateMissingSamples
        SiteCacheHostMapSignatureMismatchSamples   = $siteCacheHostMapSignatureMismatchSamples
        SiteCachePreviousHostCount = $siteCachePreviousHostCount
        SiteCachePreviousPortCount = $siteCachePreviousPortCount
        SiteCachePreviousHostSample = $siteCachePreviousHostSample
        SiteCachePreviousSnapshotStatus = $siteCachePreviousSnapshotStatus
        SiteCachePreviousSnapshotHostMapType = $siteCachePreviousSnapshotHostMapType
        SiteCachePreviousSnapshotHostCount = $siteCachePreviousSnapshotHostCount
        SiteCachePreviousSnapshotPortCount = $siteCachePreviousSnapshotPortCount
        SiteCachePreviousSnapshotException = $siteCachePreviousSnapshotException
        SiteCacheSortDurationMs = $siteCacheSortDurationMs
        SiteCacheHostCount = $siteCacheHostCount
        SiteCacheQueryDurationMs = $siteCacheQueryDurationMs
        SiteCacheExecuteDurationMs = $siteCacheExecuteDurationMs
        SiteCacheMaterializeDurationMs = $siteCacheMaterializeDurationMs
        SiteCacheMaterializeProjectionDurationMs = $siteCacheMaterializeProjectionDurationMs
        SiteCacheMaterializePortSortDurationMs   = $siteCacheMaterializePortSortDurationMs
        SiteCacheMaterializePortSortCacheHitCount   = $siteCacheMaterializePortSortCacheHitCount
        SiteCacheMaterializePortSortCacheMissCount = $siteCacheMaterializePortSortCacheMissCount
        SiteCacheMaterializePortSortCacheSize      = $siteCacheMaterializePortSortCacheSize
        SiteCacheMaterializePortSortCacheHitRatio  = $siteCacheMaterializePortSortCacheHitRatio
        SiteCacheMaterializePortSortUniquePortCount = $siteCacheMaterializePortSortUniquePortCount
        SiteCacheMaterializePortSortMissSamples      = $siteCacheMaterializePortSortMissSamples
        SiteCacheMaterializeTemplateDurationMs   = $siteCacheMaterializeTemplateDurationMs
        SiteCacheMaterializeTemplateLookupDurationMs = $siteCacheMaterializeTemplateLookupDurationMs
        SiteCacheMaterializeTemplateApplyDurationMs  = $siteCacheMaterializeTemplateApplyDurationMs
        SiteCacheMaterializeTemplateCacheHitCount    = $siteCacheMaterializeTemplateCacheHitCount
        SiteCacheMaterializeTemplateCacheMissCount   = $siteCacheMaterializeTemplateCacheMissCount
        SiteCacheMaterializeTemplateReuseCount       = $siteCacheMaterializeTemplateReuseCount
        SiteCacheMaterializeTemplateCacheHitRatio    = $siteCacheMaterializeTemplateCacheHitRatio
        SiteCacheMaterializeTemplateApplyCount        = $siteCacheMaterializeTemplateApplyCount
        SiteCacheMaterializeTemplateDefaultedCount    = $siteCacheMaterializeTemplateDefaultedCount
        SiteCacheMaterializeTemplateAuthTemplateMissingCount = $siteCacheMaterializeTemplateAuthTemplateMissingCount
        SiteCacheMaterializeTemplateNoTemplateMatchCount     = $siteCacheMaterializeTemplateNoTemplateMatchCount
        SiteCacheMaterializeTemplateHintAppliedCount   = $siteCacheMaterializeTemplateHintAppliedCount
        SiteCacheMaterializeTemplateSetPortColorCount  = $siteCacheMaterializeTemplateSetPortColorCount
        SiteCacheMaterializeTemplateSetConfigStatusCount = $siteCacheMaterializeTemplateSetConfigStatusCount
        SiteCacheMaterializeTemplateApplySamples       = $siteCacheMaterializeTemplateApplySamples
        SiteCacheMaterializeObjectDurationMs     = $siteCacheMaterializeObjectDurationMs
        SiteCacheTemplateDurationMs = $siteCacheTemplateDurationMs
        SiteCacheQueryAttempts = $siteCacheQueryAttempts
        SiteCacheExclusiveRetryCount = $siteCacheExclusiveRetryCount
        SiteCacheExclusiveWaitDurationMs = $siteCacheExclusiveWaitDurationMs
        SiteCacheProvider = $siteCacheProvider
        SiteCacheProviderReason = $siteCacheProviderReason
        SiteCacheResultRowCount = $siteCacheResultRowCount
        SiteCacheExistingRowCount = $siteCacheExistingRowCount
        SiteCacheExistingRowKeysSample = $siteCacheExistingRowKeysSample
        SiteCacheExistingRowValueType = $siteCacheExistingRowValueType
        SiteCacheExistingRowSource = $siteCacheExistingRowSource
        SiteCacheComparisonCandidateCount = $cacheComparisonCandidateCount
        SiteCacheComparisonSignatureMatchCount = $cacheComparisonSignatureMatchCount
        SiteCacheComparisonSignatureMismatchCount = $cacheComparisonSignatureMismatchCount
        SiteCacheComparisonSignatureMissingCount = $cacheComparisonSignatureMissingCount
        SiteCacheComparisonMissingPortCount = $cacheComparisonMissingPortCount
        SiteCacheComparisonObsoletePortCount = $cacheComparisonObsoletePortCount
        DiffDurationMs = $diffDurationMs
            DiffComparisonDurationMs = [Math]::Round($diffComparisonDurationMs, 3)
            DiffRowsCompared = $diffRowsCompared
            DiffRowsChanged = $diffRowsChanged
            DiffRowsUnchanged = $diffRowsUnchanged
            DiffRowsInserted = $diffRowsInserted
            DiffDuplicatePorts = [int][Math]::Max(0, $totalFactsCount - $seenPorts.Count)
            BulkCommandExecuteDurationMs = $bulkCommandExecuteDurationMs
            StreamDispatchDurationMs = $bulkStreamDispatchDurationMs
            StreamCloneDurationMs = $streamCloneDurationMs
            StreamStateUpdateDurationMs = $streamStateUpdateDurationMs
            UiCloneDurationMs = $uiCloneDurationMsValue
            StreamRowsReceived = $streamRowsReceived
            StreamRowsReused = $streamRowsReused
            StreamRowsCloned = $streamRowsCloned
            SiteCacheUpdateDurationMs = $siteCacheUpdateDurationMs
            RowsStaged = [int]$rowsToWrite.Count
            InsertCandidates = $rowsInserted
            UpdateCandidates = $rowsUpdated
            DeleteCandidates = $rowsDeleted
        }
    } catch { }
}







function Ensure-InterfaceBulkSeedTable {

    [CmdletBinding()]

    param(

        [Parameter(Mandatory=$true)][object]$Connection

    )

    if (-not (Test-IsAdodbConnection -Connection $Connection)) { return $false }

    try {

        $Connection.Execute('SELECT TOP 1 BatchId FROM InterfaceBulkSeed') | Out-Null

        return $true

    } catch {

        try {

            $createSql = @"

CREATE TABLE InterfaceBulkSeed (

    BatchId TEXT(36) NOT NULL,

    Hostname TEXT(255),

    RunDateText TEXT(32),

    Port TEXT(255),

    Name TEXT(255),

    Status TEXT(255),

    VLAN INTEGER,

    Duplex TEXT(255),

    Speed TEXT(255),

    Type TEXT(255),

    LearnedMACs MEMO,

    AuthState TEXT(255),

    AuthMode TEXT(255),

    AuthClientMAC TEXT(255),

    AuthTemplate TEXT(255),

    Config MEMO,

    PortColor TEXT(255),

    ConfigStatus TEXT(255),

    ToolTip MEMO

)

"@

            Invoke-AdodbNonQuery -Connection $Connection -CommandText $createSql | Out-Null

            try { Invoke-AdodbNonQuery -Connection $Connection -CommandText 'CREATE INDEX IX_InterfaceBulkSeed_BatchId ON InterfaceBulkSeed (BatchId)' | Out-Null } catch { }

            return $true

        } catch {

            Write-Warning ("Failed to ensure InterfaceBulkSeed staging table: {0}" -f $_.Exception.Message)

            return $false

        }

    }

}

function Invoke-InterfaceBulkInsertInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Connection,
        [Parameter(Mandatory=$true)][string]$Hostname,
        [Parameter(Mandatory=$true)][datetime]$RunDate,
        [Parameter(Mandatory=$true)][System.Collections.IEnumerable]$Rows,
        [Parameter()][int]$InsertRowCount = 0,
        [Parameter()][int]$UpdateRowCount = 0
    )

    $batchId = ([guid]::NewGuid()).ToString()
    $runDateText = $RunDate.ToString('yyyy-MM-dd HH:mm:ss')

    $rowsBuffer = $null
    $rowsBufferCount = 0
    $stagedCount = 0

    $stageDurationMs = 0.0
    $interfaceUpdateDurationMs = 0.0
    $interfaceInsertDurationMs = 0.0
    $historyInsertDurationMs = 0.0
    $cleanupDurationMs = 0.0
    $transactionCommitDurationMs = 0.0
    $transactionUsed = $false
    $transactionLevel = $null
    $transactionCommitted = $false
    $transactionRolledBack = $false
    $parameterBindDurationMs = 0.0
    $commandExecuteDurationMs = 0.0
    $recordsetAttempted = $false
    $recordsetSucceeded = $false

    $streamDispatchDurationMs = 0.0
    $streamCloneDurationMs = 0.0
    $streamStateUpdateDurationMs = 0.0
    $streamRowsReceived = 0
    $streamRowsReused = 0
    $streamRowsCloned = 0
    $setLastBulkMetrics = {
        param([bool]$resultFlag)

        $script:LastInterfaceBulkInsertMetrics = [pscustomobject]@{
            Hostname = $Hostname
            BatchId = $batchId
            RunDate = $runDateText
            Rows = if ($rowsBuffer) { [int]$rowsBuffer.Count } else { 0 }
            RowsStaged = [int]$stagedCount
            InsertRowCount = [int]$InsertRowCount
            UpdateRowCount = [int]$UpdateRowCount
            UiCloneDurationMs = $uiCloneDurationMs
            StageDurationMs = $stageDurationMs
            ParameterBindDurationMs = $parameterBindDurationMs
            CommandExecuteDurationMs = $commandExecuteDurationMs
            InterfaceUpdateDurationMs = $interfaceUpdateDurationMs
            InterfaceInsertDurationMs = $interfaceInsertDurationMs
            HistoryInsertDurationMs = $historyInsertDurationMs
            CleanupDurationMs = $cleanupDurationMs
            TransactionCommitDurationMs = $transactionCommitDurationMs
            TransactionUsed = $transactionUsed
            TransactionLevel = $transactionLevel
            TransactionCommitted = $transactionCommitted
            TransactionRolledBack = $transactionRolledBack
            RecordsetAttempted = $recordsetAttempted
            RecordsetUsed = $recordsetSucceeded
            StreamDispatchDurationMs = $streamDispatchDurationMs
            StreamCloneDurationMs = $streamCloneDurationMs
            StreamStateUpdateDurationMs = $streamStateUpdateDurationMs
            StreamRowsReceived = $streamRowsReceived
            StreamRowsReused = $streamRowsReused
            StreamRowsCloned = $streamRowsCloned
            Success = [bool]$resultFlag
        }

        return [bool]$resultFlag
    }

    if (-not (Test-IsAdodbConnection -Connection $Connection)) { return (& $setLastBulkMetrics $false) }

    $rowsBuffer = New-Object 'System.Collections.Generic.List[object[]]'
    $uiRows = New-Object 'System.Collections.Generic.List[psobject]'
    $uiCloneDurationMs = 0.0
    $uiCloneStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $extractStringValue = {
        param($properties, $propertyName)

        $property = $properties[$propertyName]
        if ($property -and $null -ne $property.Value) {
            return [string]$property.Value
        }
        return ''
    }

    foreach ($row in $Rows) {
        if ($null -eq $row) { continue }

        $properties = $row.PSObject.Properties

        $vlanNumeric = 0
        $vlanNumericProperty = $properties['VlanNumeric']
        if ($vlanNumericProperty) {
            $vlanNumericValue = $vlanNumericProperty.Value
            if ($null -ne $vlanNumericValue) {
                try { $vlanNumeric = [int]$vlanNumericValue } catch { $vlanNumeric = 0 }
            }
        } else {
            $vlanProperty = $properties['VLAN']
            if ($vlanProperty) {
                $vlanValue = $vlanProperty.Value
                if ($null -ne $vlanValue) {
                    $rawVlan = [string]$vlanValue
                    [void][int]::TryParse($rawVlan, [ref]$vlanNumeric)
                }
            }
        }

        $rowValues = New-Object object[] 19
        $rowValues[0] = $batchId
        $rowValues[1] = $Hostname
        $rowValues[2] = $runDateText
        $rowValues[3] = & $extractStringValue $properties 'Port'
        $rowValues[4] = & $extractStringValue $properties 'Name'
        $rowValues[5] = & $extractStringValue $properties 'Status'
        $rowValues[6] = $vlanNumeric
        $rowValues[7] = & $extractStringValue $properties 'Duplex'
        $rowValues[8] = & $extractStringValue $properties 'Speed'
        $rowValues[9] = & $extractStringValue $properties 'Type'
        $rowValues[10] = & $extractStringValue $properties 'Learned'
        $rowValues[11] = & $extractStringValue $properties 'AuthState'
        $rowValues[12] = & $extractStringValue $properties 'AuthMode'
        $rowValues[13] = & $extractStringValue $properties 'AuthClient'
        $rowValues[14] = & $extractStringValue $properties 'Template'
        $rowValues[15] = & $extractStringValue $properties 'Config'
        $rowValues[16] = & $extractStringValue $properties 'PortColor'
        $rowValues[17] = & $extractStringValue $properties 'StatusTag'
        $rowValues[18] = & $extractStringValue $properties 'ToolTip'

        $rowsBuffer.Add($rowValues) | Out-Null

        try {
            $clone = New-Object psobject
            foreach ($prop in $properties) {
                $clone | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value -Force
            }
            if (-not $clone.PSObject.Properties['Hostname']) {
                $clone | Add-Member -NotePropertyName Hostname -NotePropertyValue $Hostname -Force
            }
            if (-not $clone.PSObject.Properties['IsSelected']) {
                $clone | Add-Member -NotePropertyName IsSelected -NotePropertyValue $false -Force
            }
            $uiRows.Add($clone) | Out-Null
        } catch { }
    }
    $uiCloneStopwatch.Stop()
    $uiCloneDurationMs = [Math]::Round($uiCloneStopwatch.Elapsed.TotalMilliseconds, 3)

    if ($rowsBuffer.Count -eq 0) { return (& $setLastBulkMetrics $true) }
    if (-not (Ensure-InterfaceBulkSeedTable -Connection $Connection)) { return (& $setLastBulkMetrics $false) }

    $escBatch = $batchId -replace "'", "''"
    $escHostname = $Hostname -replace "'", "''"

    $cleanupSql = "DELETE FROM InterfaceBulkSeed WHERE BatchId = '$escBatch'"
    $streamDispatchDurationMs = 0.0
    $streamCloneDurationMs = 0.0
    $streamStateUpdateDurationMs = 0.0
    $streamRowsReceived = 0
    $streamRowsReused = 0
    $streamRowsCloned = 0

    $seedRecordset = New-AdodbInterfaceSeedRecordset -Connection $Connection
    if ($seedRecordset) {
        $recordsetAttempted = $true
        $stageStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $parameterBindStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $fieldNames = @('BatchId', 'Hostname', 'RunDateText', 'Port', 'Name', 'Status', 'VLAN', 'Duplex', 'Speed', 'Type', 'LearnedMACs', 'AuthState', 'AuthMode', 'AuthClientMAC', 'AuthTemplate', 'Config', 'PortColor', 'ConfigStatus', 'ToolTip')

            foreach ($rowValues in $rowsBuffer) {
                $seedRecordset.AddNew($fieldNames, $rowValues)
                $stagedCount++
            }

            $parameterBindStopwatch.Stop()
            $parameterBindDurationMs = [Math]::Round($parameterBindStopwatch.Elapsed.TotalMilliseconds, 3)

            if ($stagedCount -gt 0) {
                $executeStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                $seedRecordset.UpdateBatch()
                $executeStopwatch.Stop()
                $commandExecuteDurationMs = [Math]::Round($executeStopwatch.Elapsed.TotalMilliseconds, 3)
            }

            $recordsetSucceeded = $true
        } catch {
            $stagedCount = 0
            $parameterBindDurationMs = 0.0
            $commandExecuteDurationMs = 0.0
            try { $seedRecordset.CancelUpdate() } catch { }
            try { Invoke-AdodbNonQuery -Connection $Connection -CommandText $cleanupSql | Out-Null } catch { }
        } finally {
            $stageStopwatch.Stop()
            if ($recordsetSucceeded) {
                $stageDurationMs = [Math]::Round($stageStopwatch.Elapsed.TotalMilliseconds, 3)
            }
            try {
                if ($seedRecordset.State -ne 0) { $seedRecordset.Close() }
            } catch { }
            Release-ComObjectSafe -ComObject $seedRecordset
        }
    }

    if (-not $recordsetSucceeded) {
        $stagedCount = 0
        $stageDurationMs = 0.0
        $parameterBindDurationMs = 0.0
        $commandExecuteDurationMs = 0.0

        $insertSql = 'INSERT INTO InterfaceBulkSeed (BatchId, Hostname, RunDateText, Port, Name, Status, VLAN, Duplex, Speed, Type, LearnedMACs, AuthState, AuthMode, AuthClientMAC, AuthTemplate, Config, PortColor, ConfigStatus, ToolTip) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
        $insertCmd = New-AdodbTextCommand -Connection $Connection -CommandText $insertSql
        if (-not $insertCmd) { return (& $setLastBulkMetrics $false) }

        try {
            $parameters = @(
                Add-AdodbParameter -Command $insertCmd -Name 'BatchId' -Type $script:AdTypeVarWChar -Size 36
                Add-AdodbParameter -Command $insertCmd -Name 'Hostname' -Type $script:AdTypeVarWChar -Size 255
                Add-AdodbParameter -Command $insertCmd -Name 'RunDateText' -Type $script:AdTypeVarWChar -Size 32
                Add-AdodbParameter -Command $insertCmd -Name 'Port' -Type $script:AdTypeVarWChar -Size 255
                Add-AdodbParameter -Command $insertCmd -Name 'Name' -Type $script:AdTypeVarWChar -Size 255
                Add-AdodbParameter -Command $insertCmd -Name 'Status' -Type $script:AdTypeVarWChar -Size 255
                Add-AdodbParameter -Command $insertCmd -Name 'VLAN' -Type $script:AdTypeInteger
                Add-AdodbParameter -Command $insertCmd -Name 'Duplex' -Type $script:AdTypeVarWChar -Size 255
                Add-AdodbParameter -Command $insertCmd -Name 'Speed' -Type $script:AdTypeVarWChar -Size 255
                Add-AdodbParameter -Command $insertCmd -Name 'Type' -Type $script:AdTypeVarWChar -Size 255
                Add-AdodbParameter -Command $insertCmd -Name 'Learned' -Type $script:AdTypeLongVarWChar
                Add-AdodbParameter -Command $insertCmd -Name 'AuthState' -Type $script:AdTypeVarWChar -Size 255
                Add-AdodbParameter -Command $insertCmd -Name 'AuthMode' -Type $script:AdTypeVarWChar -Size 255
                Add-AdodbParameter -Command $insertCmd -Name 'AuthClient' -Type $script:AdTypeVarWChar -Size 255
                Add-AdodbParameter -Command $insertCmd -Name 'AuthTemplate' -Type $script:AdTypeVarWChar -Size 255
                Add-AdodbParameter -Command $insertCmd -Name 'Config' -Type $script:AdTypeLongVarWChar
                Add-AdodbParameter -Command $insertCmd -Name 'PortColor' -Type $script:AdTypeVarWChar -Size 255
                Add-AdodbParameter -Command $insertCmd -Name 'ConfigStatus' -Type $script:AdTypeVarWChar -Size 255
                Add-AdodbParameter -Command $insertCmd -Name 'ToolTip' -Type $script:AdTypeLongVarWChar
            )

            if ($parameters -contains $null) {
                try { Invoke-AdodbNonQuery -Connection $Connection -CommandText $cleanupSql | Out-Null } catch { }
                return (& $setLastBulkMetrics $false)
            }

            Set-AdodbParameterValue -Parameter $parameters[0] -Value $batchId
            Set-AdodbParameterValue -Parameter $parameters[1] -Value $Hostname
            Set-AdodbParameterValue -Parameter $parameters[2] -Value $runDateText

            $stageStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $bindDurationTotal = 0.0
            $executeDurationTotal = 0.0
            try {
                foreach ($rowValues in $rowsBuffer) {
                    $bindStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

                    Set-AdodbParameterValue -Parameter $parameters[3] -Value $rowValues[3]
                    Set-AdodbParameterValue -Parameter $parameters[4] -Value $rowValues[4]
                    Set-AdodbParameterValue -Parameter $parameters[5] -Value $rowValues[5]
                    Set-AdodbParameterValue -Parameter $parameters[6] -Value $rowValues[6]
                    Set-AdodbParameterValue -Parameter $parameters[7] -Value $rowValues[7]
                    Set-AdodbParameterValue -Parameter $parameters[8] -Value $rowValues[8]
                    Set-AdodbParameterValue -Parameter $parameters[9] -Value $rowValues[9]
                    Set-AdodbParameterValue -Parameter $parameters[10] -Value $rowValues[10]
                    Set-AdodbParameterValue -Parameter $parameters[11] -Value $rowValues[11]
                    Set-AdodbParameterValue -Parameter $parameters[12] -Value $rowValues[12]
                    Set-AdodbParameterValue -Parameter $parameters[13] -Value $rowValues[13]
                    Set-AdodbParameterValue -Parameter $parameters[14] -Value $rowValues[14]
                    Set-AdodbParameterValue -Parameter $parameters[15] -Value $rowValues[15]
                    Set-AdodbParameterValue -Parameter $parameters[16] -Value $rowValues[16]
                    Set-AdodbParameterValue -Parameter $parameters[17] -Value $rowValues[17]
                    Set-AdodbParameterValue -Parameter $parameters[18] -Value $rowValues[18]

                    $bindStopwatch.Stop()
                    $bindDurationTotal += $bindStopwatch.Elapsed.TotalMilliseconds

                    $executeStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                    try {
                        $recordsAffectedRef = [ref]0
                        $insertCmd.Execute($recordsAffectedRef, $null, $script:AdExecuteNoRecords) | Out-Null
                    } catch {
                        try {
                            $insertCmd.Execute() | Out-Null
                        } catch {
                            try { Invoke-AdodbNonQuery -Connection $Connection -CommandText $cleanupSql | Out-Null } catch { }
                            throw
                        }
                    } finally {
                        $executeStopwatch.Stop()
                        $executeDurationTotal += $executeStopwatch.Elapsed.TotalMilliseconds
                    }

                    $stagedCount++
                }
            } finally {
                $stageStopwatch.Stop()
                $stageDurationMs = [Math]::Round($stageStopwatch.Elapsed.TotalMilliseconds, 3)
                $parameterBindDurationMs = [Math]::Round($bindDurationTotal, 3)
                $commandExecuteDurationMs = [Math]::Round($executeDurationTotal, 3)
            }
        } catch {
            Write-Warning ("Failed to stage interfaces for host {0}: {1}" -f $Hostname, $_.Exception.Message)
            return (& $setLastBulkMetrics $false)
        } finally {
            Release-ComObjectSafe -ComObject $insertCmd
        }
    }

    if ($stagedCount -eq 0) {
        $cleanupStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        try { Invoke-AdodbNonQuery -Connection $Connection -CommandText $cleanupSql | Out-Null } catch { }
        $cleanupStopwatch.Stop()
        $cleanupDurationMs = [Math]::Round($cleanupStopwatch.Elapsed.TotalMilliseconds, 3)
        return (& $setLastBulkMetrics $true)
    }

    $success = $false
    $commitStopwatch = $null

    $beginTransMethod = $null
    try { $beginTransMethod = $Connection.PSObject.Methods | Where-Object { $_.Name -eq 'BeginTrans' } } catch { $beginTransMethod = $null }
    if ($beginTransMethod) {
        try {
            $transactionLevel = $Connection.BeginTrans()
            $transactionUsed = $true
        } catch {
            $transactionLevel = $null
            $transactionUsed = $false
        }
    }

    $updateInterfacesSql = "UPDATE Interfaces AS Target
INNER JOIN InterfaceBulkSeed AS Seed
ON (Target.Hostname = Seed.Hostname) AND (Target.Port = Seed.Port)
SET Target.Name = Seed.Name,
    Target.Status = Seed.Status,
    Target.VLAN = Seed.VLAN,
    Target.Duplex = Seed.Duplex,
    Target.Speed = Seed.Speed,
    Target.Type = Seed.Type,
    Target.LearnedMACs = Seed.LearnedMACs,
    Target.AuthState = Seed.AuthState,
    Target.AuthMode = Seed.AuthMode,
    Target.AuthClientMAC = Seed.AuthClientMAC,
    Target.AuthTemplate = Seed.AuthTemplate,
    Target.Config = Seed.Config,
    Target.PortColor = Seed.PortColor,
    Target.ConfigStatus = Seed.ConfigStatus,
    Target.ToolTip = Seed.ToolTip
WHERE Seed.BatchId = '$escBatch' AND Seed.Hostname = '$escHostname'"

    $insertInterfacesSql = "INSERT INTO Interfaces (Hostname, Port, Name, Status, VLAN, Duplex, Speed, Type, LearnedMACs, AuthState, AuthMode, AuthClientMAC, AuthTemplate, Config, PortColor, ConfigStatus, ToolTip)
SELECT Seed.Hostname, Seed.Port, Seed.Name, Seed.Status, Seed.VLAN, Seed.Duplex, Seed.Speed, Seed.Type, Seed.LearnedMACs, Seed.AuthState, Seed.AuthMode, Seed.AuthClientMAC, Seed.AuthTemplate, Seed.Config, Seed.PortColor, Seed.ConfigStatus, Seed.ToolTip
FROM InterfaceBulkSeed AS Seed
LEFT JOIN Interfaces AS Existing ON (Existing.Hostname = Seed.Hostname) AND (Existing.Port = Seed.Port)
WHERE Seed.BatchId = '$escBatch' AND Seed.Hostname = '$escHostname' AND Existing.Hostname IS NULL"

    $insertHistorySql = "INSERT INTO InterfaceHistory (Hostname, RunDate, Port, Name, Status, VLAN, Duplex, Speed, Type, LearnedMACs, AuthState, AuthMode, AuthClientMAC, AuthTemplate, Config, PortColor, ConfigStatus, ToolTip)
SELECT Seed.Hostname, CDate(Seed.RunDateText), Seed.Port, Seed.Name, Seed.Status, Seed.VLAN, Seed.Duplex, Seed.Speed, Seed.Type, Seed.LearnedMACs, Seed.AuthState, Seed.AuthMode, Seed.AuthClientMAC, Seed.AuthTemplate, Seed.Config, Seed.PortColor, Seed.ConfigStatus, Seed.ToolTip
FROM InterfaceBulkSeed AS Seed
WHERE Seed.BatchId = '$escBatch' AND Seed.Hostname = '$escHostname'"

    try {
        if ($UpdateRowCount -gt 0) {
            $updateStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            Invoke-AdodbNonQuery -Connection $Connection -CommandText $updateInterfacesSql | Out-Null
            $updateStopwatch.Stop()
            $interfaceUpdateDurationMs = [Math]::Round($updateStopwatch.Elapsed.TotalMilliseconds, 3)
        }

        if ($InsertRowCount -gt 0) {
            $interfacesStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            Invoke-AdodbNonQuery -Connection $Connection -CommandText $insertInterfacesSql | Out-Null
            $interfacesStopwatch.Stop()
            $interfaceInsertDurationMs = [Math]::Round($interfacesStopwatch.Elapsed.TotalMilliseconds, 3)
        }

        $historyStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        Invoke-AdodbNonQuery -Connection $Connection -CommandText $insertHistorySql | Out-Null
        $historyStopwatch.Stop()
        $historyInsertDurationMs = [Math]::Round($historyStopwatch.Elapsed.TotalMilliseconds, 3)

        if ($transactionUsed) {
            $commitMethod = $null
            try { $commitMethod = $Connection.PSObject.Methods | Where-Object { $_.Name -eq 'CommitTrans' } } catch { $commitMethod = $null }
            if ($commitMethod) {
                $commitStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                try {
                    $null = $Connection.CommitTrans()
                    $transactionCommitted = $true
                } finally {
                    $commitStopwatch.Stop()
                    $transactionCommitDurationMs = [Math]::Round($commitStopwatch.Elapsed.TotalMilliseconds, 3)
                }
            }
        }

        $success = $true
    } catch {
        if ($transactionUsed -and -not $transactionCommitted) {
            $rollbackMethod = $null
            try { $rollbackMethod = $Connection.PSObject.Methods | Where-Object { $_.Name -eq 'RollbackTrans' } } catch { $rollbackMethod = $null }
            if ($rollbackMethod) {
                try {
                    $Connection.RollbackTrans() | Out-Null
                    $transactionRolledBack = $true
                } catch {
                    $transactionRolledBack = $false
                }
            }
        }

        Write-Warning ("Failed to commit bulk interface rows for host {0}: {1}" -f $Hostname, $_.Exception.Message)
    } finally {
        $cleanupStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        try { Invoke-AdodbNonQuery -Connection $Connection -CommandText $cleanupSql | Out-Null } catch { }
        $cleanupStopwatch.Stop()
        $cleanupDurationMs = [Math]::Round($cleanupStopwatch.Elapsed.TotalMilliseconds, 3)
    }

    try {
        TelemetryModule\Write-StTelemetryEvent -Name 'InterfaceBulkInsertTiming' -Payload @{
            Hostname = $Hostname
            BatchId  = $batchId
            Rows     = [int]$rowsBuffer.Count
            RunDate  = $runDateText
            UiCloneDurationMs = $uiCloneDurationMs
            StageDurationMs = $stageDurationMs
            ParameterBindDurationMs = $parameterBindDurationMs
            CommandExecuteDurationMs = $commandExecuteDurationMs
            InterfaceUpdateDurationMs = $interfaceUpdateDurationMs
            InterfaceInsertDurationMs = $interfaceInsertDurationMs
            HistoryInsertDurationMs = $historyInsertDurationMs
            CleanupDurationMs = $cleanupDurationMs
            TransactionUsed = $transactionUsed
            TransactionLevel = $transactionLevel
            TransactionCommitted = $transactionCommitted
            TransactionRolledBack = $transactionRolledBack
            TransactionCommitDurationMs = $transactionCommitDurationMs
            RecordsetAttempted = $recordsetAttempted
            RecordsetUsed = $recordsetSucceeded
            StreamDispatchDurationMs = $streamDispatchDurationMs
            StreamCloneDurationMs = $streamCloneDurationMs
            StreamStateUpdateDurationMs = $streamStateUpdateDurationMs
            StreamRowsReceived = $streamRowsReceived
            StreamRowsReused = $streamRowsReused
            StreamRowsCloned = $streamRowsCloned
            InsertRowCount = [int]$InsertRowCount
            UpdateRowCount = [int]$UpdateRowCount
            Success = $success
        }
    } catch { }

    try {
        TelemetryModule\Write-StTelemetryEvent -Name 'InterfaceBulkInsert' -Payload @{
            Hostname = $Hostname
            BatchId  = $batchId
            Rows     = [int]$rowsBuffer.Count
            RunDate  = $runDateText
            Success  = $success
        }
    } catch { }

    if ($success) {
        $totalPorts = if ($uiRows) { [int]$uiRows.Count } else { 0 }
        $streamStopwatch = $null
        try {
            $streamStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            DeviceRepositoryModule\Set-InterfacePortStreamData -Hostname $Hostname -RunDate $RunDate -InterfaceRows $uiRows -BatchId $batchId
        } catch { }
        finally {
            if ($streamStopwatch) {
                $streamStopwatch.Stop()
                $streamDispatchDurationMs = [Math]::Round($streamStopwatch.Elapsed.TotalMilliseconds, 3)
            }
        }

        $streamMetrics = $null
        try { $streamMetrics = DeviceRepositoryModule\Get-LastInterfacePortStreamMetrics } catch { $streamMetrics = $null }
        if ($streamMetrics) {
            if ($streamMetrics.PSObject.Properties.Name -contains 'StreamCloneDurationMs') {
                $streamCloneDurationMs = [double]$streamMetrics.StreamCloneDurationMs
            }
            if ($streamMetrics.PSObject.Properties.Name -contains 'StreamStateUpdateDurationMs') {
                $streamStateUpdateDurationMs = [double]$streamMetrics.StreamStateUpdateDurationMs
            }
            if ($streamMetrics.PSObject.Properties.Name -contains 'RowsReceived') {
                $streamRowsReceived = [int]$streamMetrics.RowsReceived
            }
            if ($streamMetrics.PSObject.Properties.Name -contains 'RowsReused') {
                $streamRowsReused = [int]$streamMetrics.RowsReused
            }
            if ($streamMetrics.PSObject.Properties.Name -contains 'RowsCloned') {
                $streamRowsCloned = [int]$streamMetrics.RowsCloned
            }
            if ($script:LastInterfaceSyncTelemetry -and $script:LastInterfaceSyncTelemetry.Hostname -eq $Hostname) {
                $script:LastInterfaceSyncTelemetry.StreamCloneDurationMs = $streamCloneDurationMs
                $script:LastInterfaceSyncTelemetry.StreamStateUpdateDurationMs = $streamStateUpdateDurationMs
                $script:LastInterfaceSyncTelemetry.StreamRowsReceived = $streamRowsReceived
                $script:LastInterfaceSyncTelemetry.StreamRowsReused = $streamRowsReused
                $script:LastInterfaceSyncTelemetry.StreamRowsCloned = $streamRowsCloned
                $script:LastInterfaceSyncTelemetry.StreamDispatchDurationMs = $streamDispatchDurationMs
            }
        }

        $chunkSize = 24
        try { $chunkSize = DeviceRepositoryModule\Get-InterfacePortBatchChunkSize } catch { $chunkSize = 24 }
        if ($chunkSize -le 0) { $chunkSize = 24 }
        $estimatedBatchCount = if ($totalPorts -gt 0) { [int][Math]::Ceiling($totalPorts / [double]$chunkSize) } else { 0 }

        try {
            TelemetryModule\Write-StTelemetryEvent -Name 'PortBatchReady' -Payload @{
                Hostname             = $Hostname
                BatchId              = $batchId
                RunDate              = $runDateText
                PortsCommitted       = $totalPorts
                ChunkSize            = $chunkSize
                EstimatedBatchCount  = $estimatedBatchCount
            }
        } catch { }
    } else {
        try { DeviceRepositoryModule\Clear-InterfacePortStream -Hostname $Hostname } catch { }
    }

    return (& $setLastBulkMetrics $success)
}







function Invoke-DeviceSummaryParameterized {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Connection,
        [Parameter(Mandatory=$true)][string]$Hostname,
        [Parameter(Mandatory=$true)][hashtable]$Values,
        [Parameter(Mandatory=$true)][datetime]$RunDate
    )

    $updateSql = 'UPDATE DeviceSummary SET Make=?, Model=?, Uptime=?, Site=?, Building=?, Room=?, Ports=?, AuthDefaultVLAN=?, AuthBlock=? WHERE Hostname=?'
    $updateCmd = New-AdodbTextCommand -Connection $Connection -CommandText $updateSql
    if (-not $updateCmd) { return $false }

    try {
        $parameters = @(
            Add-AdodbParameter -Command $updateCmd -Name 'Make' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $updateCmd -Name 'Model' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $updateCmd -Name 'Uptime' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $updateCmd -Name 'Site' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $updateCmd -Name 'Building' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $updateCmd -Name 'Room' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $updateCmd -Name 'Ports' -Type $script:AdTypeInteger
            Add-AdodbParameter -Command $updateCmd -Name 'AuthDefaultVLAN' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $updateCmd -Name 'AuthBlock' -Type $script:AdTypeLongVarWChar
            Add-AdodbParameter -Command $updateCmd -Name 'Hostname' -Type $script:AdTypeVarWChar -Size 255
        )

        if ($parameters -contains $null) { return $false }

        Set-AdodbParameterValue -Parameter $parameters[0] -Value ([string]$Values.Make)
        Set-AdodbParameterValue -Parameter $parameters[1] -Value ([string]$Values.Model)
        Set-AdodbParameterValue -Parameter $parameters[2] -Value ([string]$Values.Uptime)
        Set-AdodbParameterValue -Parameter $parameters[3] -Value ([string]$Values.Site)
        Set-AdodbParameterValue -Parameter $parameters[4] -Value ([string]$Values.Building)
        Set-AdodbParameterValue -Parameter $parameters[5] -Value ([string]$Values.Room)
        Set-AdodbParameterValue -Parameter $parameters[6] -Value ([int]$Values.Ports)
        Set-AdodbParameterValue -Parameter $parameters[7] -Value ([string]$Values.AuthDefaultVlan)
        Set-AdodbParameterValue -Parameter $parameters[8] -Value ([string]$Values.AuthBlock)
        Set-AdodbParameterValue -Parameter $parameters[9] -Value $Hostname

        try { $updateCmd.Execute() | Out-Null } catch { }
    } finally {
        Release-ComObjectSafe -ComObject $updateCmd
    }

    $insertSql = 'INSERT INTO DeviceSummary (Hostname, Make, Model, Uptime, Site, Building, Room, Ports, AuthDefaultVLAN, AuthBlock) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
    $insertCmd = New-AdodbTextCommand -Connection $Connection -CommandText $insertSql
    if (-not $insertCmd) { return $false }

    try {
        $parameters = @(
            Add-AdodbParameter -Command $insertCmd -Name 'Hostname' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $insertCmd -Name 'Make' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $insertCmd -Name 'Model' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $insertCmd -Name 'Uptime' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $insertCmd -Name 'Site' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $insertCmd -Name 'Building' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $insertCmd -Name 'Room' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $insertCmd -Name 'Ports' -Type $script:AdTypeInteger
            Add-AdodbParameter -Command $insertCmd -Name 'AuthDefaultVLAN' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $insertCmd -Name 'AuthBlock' -Type $script:AdTypeLongVarWChar
        )

        if ($parameters -contains $null) { return $false }

        Set-AdodbParameterValue -Parameter $parameters[0] -Value $Hostname
        Set-AdodbParameterValue -Parameter $parameters[1] -Value ([string]$Values.Make)
        Set-AdodbParameterValue -Parameter $parameters[2] -Value ([string]$Values.Model)
        Set-AdodbParameterValue -Parameter $parameters[3] -Value ([string]$Values.Uptime)
        Set-AdodbParameterValue -Parameter $parameters[4] -Value ([string]$Values.Site)
        Set-AdodbParameterValue -Parameter $parameters[5] -Value ([string]$Values.Building)
        Set-AdodbParameterValue -Parameter $parameters[6] -Value ([string]$Values.Room)
        Set-AdodbParameterValue -Parameter $parameters[7] -Value ([int]$Values.Ports)
        Set-AdodbParameterValue -Parameter $parameters[8] -Value ([string]$Values.AuthDefaultVlan)
        Set-AdodbParameterValue -Parameter $parameters[9] -Value ([string]$Values.AuthBlock)

        try { $insertCmd.Execute() | Out-Null } catch { }
    } finally {
        Release-ComObjectSafe -ComObject $insertCmd
    }

    $historySql = 'INSERT INTO DeviceHistory (Hostname, RunDate, Make, Model, Uptime, Site, Building, Room, Ports, AuthDefaultVLAN, AuthBlock) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
    $historyCmd = New-AdodbTextCommand -Connection $Connection -CommandText $historySql
    if (-not $historyCmd) { return $false }

    try {
        $parameters = @(
            Add-AdodbParameter -Command $historyCmd -Name 'Hostname' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $historyCmd -Name 'RunDate' -Type $script:AdTypeVarWChar -Size 32
            Add-AdodbParameter -Command $historyCmd -Name 'Make' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $historyCmd -Name 'Model' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $historyCmd -Name 'Uptime' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $historyCmd -Name 'Site' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $historyCmd -Name 'Building' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $historyCmd -Name 'Room' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $historyCmd -Name 'Ports' -Type $script:AdTypeInteger
            Add-AdodbParameter -Command $historyCmd -Name 'AuthDefaultVLAN' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $historyCmd -Name 'AuthBlock' -Type $script:AdTypeLongVarWChar
        )

        if ($parameters -contains $null) { return $false }

        Set-AdodbParameterValue -Parameter $parameters[0] -Value $Hostname
        Set-AdodbParameterValue -Parameter $parameters[1] -Value ($RunDate.ToString('yyyy-MM-dd HH:mm:ss'))
        Set-AdodbParameterValue -Parameter $parameters[2] -Value ([string]$Values.Make)
        Set-AdodbParameterValue -Parameter $parameters[3] -Value ([string]$Values.Model)
        Set-AdodbParameterValue -Parameter $parameters[4] -Value ([string]$Values.Uptime)
        Set-AdodbParameterValue -Parameter $parameters[5] -Value ([string]$Values.Site)
        Set-AdodbParameterValue -Parameter $parameters[6] -Value ([string]$Values.Building)
        Set-AdodbParameterValue -Parameter $parameters[7] -Value ([string]$Values.Room)
        Set-AdodbParameterValue -Parameter $parameters[8] -Value ([int]$Values.Ports)
        Set-AdodbParameterValue -Parameter $parameters[9] -Value ([string]$Values.AuthDefaultVlan)
        Set-AdodbParameterValue -Parameter $parameters[10] -Value ([string]$Values.AuthBlock)

        try { $historyCmd.Execute() | Out-Null } catch {
            Write-Warning "Failed to insert device history for host ${Hostname}: $($_.Exception.Message)"
            Write-Verbose ("Device history exception details: {0}" -f ($_.Exception | Format-List * | Out-String))
        }
    } finally {
        Release-ComObjectSafe -ComObject $historyCmd
    }

    return $true
}

function Invoke-InterfaceRowParameterized {

    [CmdletBinding()]

    param(

        [Parameter(Mandatory=$true)][object]$Connection,

        [Parameter(Mandatory=$true)][string]$Hostname,

        [Parameter(Mandatory=$true)][object]$Row,

        [Parameter(Mandatory=$true)][datetime]$RunDate

    )



    $insertSql = 'INSERT INTO Interfaces (Hostname, Port, Name, Status, VLAN, Duplex, Speed, Type, LearnedMACs, AuthState, AuthMode, AuthClientMAC, AuthTemplate, Config, PortColor, ConfigStatus, ToolTip) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'

    $insertCmd = New-AdodbTextCommand -Connection $Connection -CommandText $insertSql

    if (-not $insertCmd) { return $false }



    $vlanNumeric = 0

    if ($Row.PSObject.Properties.Name -contains 'VlanNumeric' -and $null -ne $Row.VlanNumeric) {

        try { $vlanNumeric = [int]$Row.VlanNumeric } catch { $vlanNumeric = 0 }

    } else {

        [void][int]::TryParse($Row.VLAN, [ref]$vlanNumeric)

    }



    try {

        $parameters = @(

            Add-AdodbParameter -Command $insertCmd -Name 'Hostname' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $insertCmd -Name 'Port' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $insertCmd -Name 'Name' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $insertCmd -Name 'Status' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $insertCmd -Name 'VLAN' -Type $script:AdTypeInteger

            Add-AdodbParameter -Command $insertCmd -Name 'Duplex' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $insertCmd -Name 'Speed' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $insertCmd -Name 'Type' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $insertCmd -Name 'Learned' -Type $script:AdTypeLongVarWChar

            Add-AdodbParameter -Command $insertCmd -Name 'AuthState' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $insertCmd -Name 'AuthMode' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $insertCmd -Name 'AuthClient' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $insertCmd -Name 'AuthTemplate' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $insertCmd -Name 'Config' -Type $script:AdTypeLongVarWChar

            Add-AdodbParameter -Command $insertCmd -Name 'PortColor' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $insertCmd -Name 'ConfigStatus' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $insertCmd -Name 'ToolTip' -Type $script:AdTypeLongVarWChar

        )



        if ($parameters -contains $null) { return $false }



        Set-AdodbParameterValue -Parameter $parameters[0] -Value $Hostname

        Set-AdodbParameterValue -Parameter $parameters[1] -Value ([string]$Row.Port)

        Set-AdodbParameterValue -Parameter $parameters[2] -Value ([string]$Row.Name)

        Set-AdodbParameterValue -Parameter $parameters[3] -Value ([string]$Row.Status)

        Set-AdodbParameterValue -Parameter $parameters[4] -Value $vlanNumeric

        Set-AdodbParameterValue -Parameter $parameters[5] -Value ([string]$Row.Duplex)

        Set-AdodbParameterValue -Parameter $parameters[6] -Value ([string]$Row.Speed)

        Set-AdodbParameterValue -Parameter $parameters[7] -Value ([string]$Row.Type)

        Set-AdodbParameterValue -Parameter $parameters[8] -Value ([string]$Row.Learned)

        Set-AdodbParameterValue -Parameter $parameters[9] -Value ([string]$Row.AuthState)

        Set-AdodbParameterValue -Parameter $parameters[10] -Value ([string]$Row.AuthMode)

        Set-AdodbParameterValue -Parameter $parameters[11] -Value ([string]$Row.AuthClient)

        Set-AdodbParameterValue -Parameter $parameters[12] -Value ([string]$Row.Template)

        Set-AdodbParameterValue -Parameter $parameters[13] -Value ([string]$Row.Config)

        Set-AdodbParameterValue -Parameter $parameters[14] -Value ([string]$Row.PortColor)

        Set-AdodbParameterValue -Parameter $parameters[15] -Value ([string]$Row.StatusTag)

        Set-AdodbParameterValue -Parameter $parameters[16] -Value ([string]$Row.ToolTip)



        try {

            $insertCmd.Execute() | Out-Null

        } catch {

            Write-Warning "Failed to insert interface record for host ${Hostname} port ${Row.Port}: $($_.Exception.Message)"

            Write-Verbose ("Interface insert exception details: {0}" -f ($_.Exception | Format-List * | Out-String))

            return $false

        }

    } finally {

        Release-ComObjectSafe -ComObject $insertCmd

    }



    $historySql = 'INSERT INTO InterfaceHistory (Hostname, RunDate, Port, Name, Status, VLAN, Duplex, Speed, Type, LearnedMACs, AuthState, AuthMode, AuthClientMAC, AuthTemplate, Config, PortColor, ConfigStatus, ToolTip) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'

    $historyCmd = New-AdodbTextCommand -Connection $Connection -CommandText $historySql

    if (-not $historyCmd) { return $true }



    try {

        $parameters = @(

            Add-AdodbParameter -Command $historyCmd -Name 'Hostname' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $historyCmd -Name 'RunDate' -Type $script:AdTypeVarWChar -Size 32

            Add-AdodbParameter -Command $historyCmd -Name 'Port' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $historyCmd -Name 'Name' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $historyCmd -Name 'Status' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $historyCmd -Name 'VLAN' -Type $script:AdTypeInteger

            Add-AdodbParameter -Command $historyCmd -Name 'Duplex' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $historyCmd -Name 'Speed' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $historyCmd -Name 'Type' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $historyCmd -Name 'Learned' -Type $script:AdTypeLongVarWChar

            Add-AdodbParameter -Command $historyCmd -Name 'AuthState' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $historyCmd -Name 'AuthMode' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $historyCmd -Name 'AuthClient' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $historyCmd -Name 'AuthTemplate' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $historyCmd -Name 'Config' -Type $script:AdTypeLongVarWChar

            Add-AdodbParameter -Command $historyCmd -Name 'PortColor' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $historyCmd -Name 'ConfigStatus' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $historyCmd -Name 'ToolTip' -Type $script:AdTypeLongVarWChar

        )



        if ($parameters -contains $null) { return $true }



        Set-AdodbParameterValue -Parameter $parameters[0] -Value $Hostname

        Set-AdodbParameterValue -Parameter $parameters[1] -Value ($RunDate.ToString('yyyy-MM-dd HH:mm:ss'))

        Set-AdodbParameterValue -Parameter $parameters[2] -Value ([string]$Row.Port)

        Set-AdodbParameterValue -Parameter $parameters[3] -Value ([string]$Row.Name)

        Set-AdodbParameterValue -Parameter $parameters[4] -Value ([string]$Row.Status)

        Set-AdodbParameterValue -Parameter $parameters[5] -Value $vlanNumeric

        Set-AdodbParameterValue -Parameter $parameters[6] -Value ([string]$Row.Duplex)

        Set-AdodbParameterValue -Parameter $parameters[7] -Value ([string]$Row.Speed)

        Set-AdodbParameterValue -Parameter $parameters[8] -Value ([string]$Row.Type)

        Set-AdodbParameterValue -Parameter $parameters[9] -Value ([string]$Row.Learned)

        Set-AdodbParameterValue -Parameter $parameters[10] -Value ([string]$Row.AuthState)

        Set-AdodbParameterValue -Parameter $parameters[11] -Value ([string]$Row.AuthMode)

        Set-AdodbParameterValue -Parameter $parameters[12] -Value ([string]$Row.AuthClient)

        Set-AdodbParameterValue -Parameter $parameters[13] -Value ([string]$Row.Template)

        Set-AdodbParameterValue -Parameter $parameters[14] -Value ([string]$Row.Config)

        Set-AdodbParameterValue -Parameter $parameters[15] -Value ([string]$Row.PortColor)

        Set-AdodbParameterValue -Parameter $parameters[16] -Value ([string]$Row.StatusTag)

        Set-AdodbParameterValue -Parameter $parameters[17] -Value ([string]$Row.ToolTip)



        try {

            $historyCmd.Execute() | Out-Null

        } catch {

            Write-Warning "Failed to insert interface history for host ${Hostname} port ${Row.Port}: $($_.Exception.Message)"

        }

    } finally {

        Release-ComObjectSafe -ComObject $historyCmd

    }



    return $true

}





function Write-InterfacePersistenceFailure {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Stage,
        [Parameter(Mandatory=$true)][string]$Hostname,
        [Parameter(Mandatory=$true)][System.Exception]$Exception,
        [Parameter()][hashtable]$Metadata
    )

    $payload = @{
        Stage = $Stage
        Hostname = $Hostname
        ExceptionMessage = $Exception.Message
        ExceptionType = $Exception.GetType().FullName
    }

    if ($Metadata) {
        foreach ($key in $Metadata.Keys) {
            $payload[$key] = $Metadata[$key]
        }
    }

    try {
        TelemetryModule\Write-StTelemetryEvent -Name 'InterfacePersistenceFailure' -Payload $payload
    } catch {
        Write-Warning ("Failed to emit interface persistence telemetry: {0}" -f $_.Exception.Message)
    }
}

function Update-SpanInfoInDb {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Connection,
        [Parameter(Mandatory=$true)][string]$Hostname,
        [Parameter(Mandatory=$true)][string]$RunDateString,
        [Parameter()][object[]]$SpanInfo
    )

    $escHostname = $Hostname -replace "'", "''"
    $runDateLiteral = "#$RunDateString#"

    Ensure-SpanInfoTableExists -Connection $Connection

    try {
        Invoke-AdodbNonQuery -Connection $Connection -CommandText "DELETE FROM SpanInfo WHERE Hostname = '$escHostname'" | Out-Null
    } catch {
        Write-Warning "Failed to clear span data for host ${Hostname}: $($_.Exception.Message)"
    }

    if (-not $SpanInfo) { return }

    foreach ($item in $SpanInfo) {
        if ($null -eq $item) { continue }

        $vlan = ''
        if ($item.PSObject.Properties['VLAN']) { $vlan = '' + $item.VLAN }

        $rootSwitch = ''
        if ($item.PSObject.Properties['RootSwitch']) { $rootSwitch = '' + $item.RootSwitch }

        $rootPort = ''
        if ($item.PSObject.Properties['RootPort']) { $rootPort = '' + $item.RootPort }

        $role = ''
        if ($item.PSObject.Properties['Role']) { $role = '' + $item.Role }

        $upstream = ''
        if ($item.PSObject.Properties['Upstream']) { $upstream = '' + $item.Upstream }

        $escVlan     = $vlan -replace "'", "''"
        $escRoot     = $rootSwitch -replace "'", "''"
        $escPort     = $rootPort -replace "'", "''"
        $escRole     = $role -replace "'", "''"
        $escUpstream = $upstream -replace "'", "''"

        $insertSql = "INSERT INTO SpanInfo (Hostname, Vlan, RootSwitch, RootPort, Role, Upstream, LastUpdated) VALUES ('$escHostname', '$escVlan', '$escRoot', '$escPort', '$escRole', '$escUpstream', $runDateLiteral)"
        try {
            Invoke-AdodbNonQuery -Connection $Connection -CommandText $insertSql | Out-Null
        } catch {
            Write-Warning "Failed to insert span info for host ${Hostname}: $($_.Exception.Message)"
        }

        $histSql = "INSERT INTO SpanHistory (Hostname, RunDate, Vlan, RootSwitch, RootPort, Role, Upstream) VALUES ('$escHostname', $runDateLiteral, '$escVlan', '$escRoot', '$escPort', '$escRole', '$escUpstream')"
        try {
            Invoke-AdodbNonQuery -Connection $Connection -CommandText $histSql | Out-Null
        } catch {
            Write-Warning "Failed to insert span history for host ${Hostname}: $($_.Exception.Message)"
        }
    }
}

function Get-LastInterfaceSyncTelemetry {
    [CmdletBinding()]
    param()

    return $script:LastInterfaceSyncTelemetry
}

Export-ModuleMember -Function Update-DeviceSummaryInDb, Update-InterfacesInDb, Update-SpanInfoInDb, Write-InterfacePersistenceFailure, Get-LastInterfaceSyncTelemetry, Set-ParserSkipSiteCacheUpdate
