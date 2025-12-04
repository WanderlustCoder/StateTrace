# Default path: ..\Templates\ShowCommands.json (relative to this module)
$script:ShowCfgPath  = Join-Path $PSScriptRoot '..\Templates\ShowCommands.json'
$script:ShowCfg      = $null
$script:ShowCfgMtime = [datetime]::MinValue

function Get-ShowConfig {
    if (-not (Test-Path -LiteralPath $script:ShowCfgPath)) { return $null }
    $mtime = (Get-Item -LiteralPath $script:ShowCfgPath).LastWriteTimeUtc
    if ($script:ShowCfg -and $script:ShowCfgMtime -eq $mtime) { return $script:ShowCfg }

    try {
#if PS 7+: ConvertFrom-Json -AsHashtable (faster, easier); fallback to PSCustomObject on 5.1
        $json   = [IO.File]::ReadAllText($script:ShowCfgPath)
        $params = @{ InputObject = $json }
        if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('AsHashtable')) { $params.AsHashtable = $true }
        $cfg = ConvertFrom-Json @params

        $script:ShowCfg, $script:ShowCfgMtime = $cfg, $mtime
        return $cfg
    } catch {
        throw ("ShowCommands: failed to read {0}: {1}" -f $script:ShowCfgPath, $_.Exception.Message)
    }
}

function Get-ShowCommandsVersions {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Vendor)

    $cfg = Get-ShowConfig
    if (-not $cfg) { return @() }

    $vendorNode = if ($cfg -is [hashtable]) { $cfg[$Vendor] } else { $cfg.$Vendor }
    if (-not $vendorNode) { return @() }

    $versions = if ($vendorNode -is [hashtable]) { $vendorNode['versions'] } else { $vendorNode.versions }
    if (-not $versions) { return @() }

    $names = if ($versions -is [hashtable]) { $versions.Keys } else { $versions.PSObject.Properties.Name }

    # Dedupe, preserve order (case-insensitive)
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $out  = [System.Collections.Generic.List[string]]::new()
    foreach ($n in $names) { $s = [string]$n; if ($s -and $seen.Add($s)) { [void]$out.Add($s) } }
    return ,$out.ToArray()
}

function Get-ShowCommands {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Vendor,
        [string]$OSVersion
    )

    $cfg = Get-ShowConfig
    if (-not $cfg) { throw ("ShowCommands.json missing at {0}" -f $script:ShowCfgPath) }

    $vendorNode = if ($cfg -is [hashtable]) { $cfg[$Vendor] } else { $cfg.$Vendor }
    if (-not $vendorNode) { throw ("Vendor '{0}' not found in ShowCommands.json." -f $Vendor) }

    $common   = if ($vendorNode -is [hashtable]) { $vendorNode['common'] }   else { $vendorNode.common }
    $versions = if ($vendorNode -is [hashtable]) { $vendorNode['versions'] } else { $vendorNode.versions }

    # Build the list of commands using a typed list.  Avoid array += and pipeline normalization.
    $list = [System.Collections.Generic.List[string]]::new()
    if ($common) {
        if ($common -is [System.Collections.IEnumerable]) {
            foreach ($c in $common) {
                if ($null -ne $c) { [void]$list.Add(('' + $c).TrimEnd()) }
            }
        } else {
            [void]$list.Add(('' + $common).TrimEnd())
        }
    }
    if ($OSVersion -and $versions) {
        $osList = if ($versions -is [hashtable]) { $versions[$OSVersion] } else { $versions.$OSVersion }
        if ($osList) {
            if ($osList -is [System.Collections.IEnumerable]) {
                foreach ($c in $osList) {
                    if ($null -ne $c) { [void]$list.Add(('' + $c).TrimEnd()) }
                }
            } else {
                [void]$list.Add(('' + $osList).TrimEnd())
            }
        }
    }
    # Dedupe and preserve order (case-insensitive)
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $out  = [System.Collections.Generic.List[string]]::new()
    foreach ($cmd in $list) {
        if ($seen.Add($cmd)) { [void]$out.Add($cmd) }
    }
    return ,$out.ToArray()
}

# Configuration templates caching
if (-not (Get-Variable -Scope Script -Name ConfigurationTemplateCache -ErrorAction SilentlyContinue)) {
    $script:ConfigurationTemplateCache = @{}
}
if (-not (Get-Variable -Scope Script -Name ConfigurationTemplateModuleRoot -ErrorAction SilentlyContinue)) {
    try {
        $script:ConfigurationTemplateModuleRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    } catch {
        $script:ConfigurationTemplateModuleRoot = Split-Path -Parent $PSScriptRoot
    }
}
if (-not (Get-Variable -Scope Script -Name ConfigurationTemplateDataDir -ErrorAction SilentlyContinue)) {
    $script:ConfigurationTemplateDataDir = Join-Path $script:ConfigurationTemplateModuleRoot 'Data'
}

function script:Get-ConfigurationTemplateCacheEntry {
    param(
        [Parameter(Mandatory)][string]$Vendor,
        [string]$TemplatesPath = (Join-Path $PSScriptRoot '..\Templates')
    )

    $vendorKey = ('' + $Vendor).Trim()
    if ([string]::IsNullOrWhiteSpace($vendorKey)) { $vendorKey = 'Cisco' }

    $jsonFile = Join-Path $TemplatesPath ("{0}.json" -f $vendorKey)
    $exists = Test-Path -LiteralPath $jsonFile
    if (-not $exists) {
        $entry = [PSCustomObject]@{
            Vendor        = $vendorKey
            Templates     = @()
            Names         = @()
            Lookup        = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)
            Exists        = $false
            Path          = $jsonFile
            LastWriteTime = [datetime]::MinValue
        }
        $script:ConfigurationTemplateCache[$vendorKey] = $entry
        return $entry
    }

    $mtime = (Get-Item -LiteralPath $jsonFile).LastWriteTimeUtc
    if ($script:ConfigurationTemplateCache.ContainsKey($vendorKey)) {
        $cached = $script:ConfigurationTemplateCache[$vendorKey]
        if ($cached -and $cached.Exists -and $cached.LastWriteTime -eq $mtime) {
            return $cached
        }
    }

    $templates = @()
    try {
        $json = [System.IO.File]::ReadAllText($jsonFile)
        $parsed = ConvertFrom-Json $json
        if ($parsed) {
            if ($parsed -is [hashtable]) {
                if ($parsed.ContainsKey('templates')) { $templates = $parsed['templates'] }
            } elseif ($parsed.PSObject.Properties['templates']) {
                $templates = $parsed.templates
            }
        }
    } catch {
        $templates = @()
    }

    if (-not ($templates -is [System.Collections.IEnumerable])) {
        $templates = @()
    }

    $namesList = New-Object 'System.Collections.Generic.List[string]'
    $lookup = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($tmpl in $templates) {
        if ($null -eq $tmpl) { continue }
        $nameVal = $null
        if ($tmpl -is [hashtable]) {
            if ($tmpl.ContainsKey('name')) { $nameVal = '' + $tmpl['name'] }
        } elseif ($tmpl.PSObject.Properties['name']) {
            $nameVal = '' + $tmpl.name
        }
        if (-not [string]::IsNullOrWhiteSpace($nameVal)) {
            [void]$namesList.Add($nameVal)
            if (-not $lookup.ContainsKey($nameVal)) { $lookup[$nameVal] = $tmpl }
        }

        $aliases = $null
        if ($tmpl -is [hashtable]) {
            if ($tmpl.ContainsKey('aliases')) { $aliases = $tmpl['aliases'] }
        } elseif ($tmpl.PSObject.Properties['aliases']) {
            $aliases = $tmpl.aliases
        }
        if ($aliases -is [System.Collections.IEnumerable]) {
            foreach ($alias in $aliases) {
                $aliasText = '' + $alias
                if ([string]::IsNullOrWhiteSpace($aliasText)) { continue }
                if (-not $lookup.ContainsKey($aliasText)) { $lookup[$aliasText] = $tmpl }
            }
        }
    }

    $entry = [PSCustomObject]@{
        Vendor        = $vendorKey
        Templates     = $templates
        Names         = $namesList.ToArray()
        Lookup        = $lookup
        Exists        = $true
        Path          = $jsonFile
        LastWriteTime = $mtime
    }
    $script:ConfigurationTemplateCache[$vendorKey] = $entry
    return $entry
}

function script:Get-ConfigurationTemplateDbPath {
    param([string]$Hostname)

    $hostTrim = ('' + $Hostname).Trim()
    if ([string]::IsNullOrWhiteSpace($hostTrim)) { return $null }
    $site = $hostTrim
    if ($hostTrim -match '^(?<site>[^-]+)-') { $site = $matches['site'] }

    return Join-Path $script:ConfigurationTemplateDataDir ("{0}.accdb" -f $site)
}

function script:Ensure-DatabaseModule {
    try {
        if (-not (Get-Module -Name DatabaseModule)) {
            $dbModulePath = Join-Path $PSScriptRoot 'DatabaseModule.psm1'
            if (Test-Path -LiteralPath $dbModulePath) {
                Import-Module $dbModulePath -Force -Global -ErrorAction SilentlyContinue | Out-Null
            }
        }
    } catch {
    }
}

function script:Get-DeviceVendorFromSummary {
    param(
        [Parameter(Mandatory)][string]$Hostname,
        [Parameter(Mandatory)][string]$DatabasePath
    )

    $vendor = 'Cisco'
    $escHost = $Hostname -replace "'", "''"
    try {
        script:Ensure-DatabaseModule
        $mkDt = DatabaseModule\Invoke-DbQuery -DatabasePath $DatabasePath -Sql "SELECT Make FROM DeviceSummary WHERE Hostname = '$escHost'"
        $row = $null
        if ($mkDt) {
            if ($mkDt -is [System.Data.DataTable]) {
                if ($mkDt.Rows.Count -gt 0) { $row = $mkDt.Rows[0] }
            } elseif ($mkDt -is [System.Collections.IEnumerable]) {
                try { $row = ($mkDt | Select-Object -First 1) } catch { $row = $null }
            }
        }
        $makeVal = $null
        if ($row) {
            if ($row -is [System.Data.DataRow]) {
                $makeVal = $row.Make
            } elseif ($row.PSObject -and $row.PSObject.Properties['Make']) {
                $makeVal = $row.Make
            }
        }
        if ($makeVal) {
            $makeText = '' + $makeVal
            if ($makeText -match '(?i)brocade') { return 'Brocade' }
            if ($makeText -match '(?i)arista')  { return 'Arista' }
        }
    } catch {
    }
    return $vendor
}

function Get-ConfigurationTemplateData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Vendor,
        [string]$TemplatesPath = (Join-Path $PSScriptRoot '..\Templates')
    )

    return script:Get-ConfigurationTemplateCacheEntry -Vendor $Vendor -TemplatesPath $TemplatesPath
}

function Get-ConfigurationTemplates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Hostname,
        [string]$TemplatesPath = (Join-Path $PSScriptRoot '..\Templates'),
        [string]$DatabasePath,
        [string]$Vendor
    )

    $hostTrim = ('' + $Hostname).Trim()
    if ([string]::IsNullOrWhiteSpace($hostTrim)) { return @() }

    $dbPath = $DatabasePath
    if (-not $dbPath) {
        $dbPath = script:Get-ConfigurationTemplateDbPath -Hostname $hostTrim
    }
    if (-not $dbPath -or -not (Test-Path -LiteralPath $dbPath)) { return @() }

    $vendorName = ('' + $Vendor).Trim()
    if ([string]::IsNullOrWhiteSpace($vendorName)) {
        $vendorName = script:Get-DeviceVendorFromSummary -Hostname $hostTrim -DatabasePath $dbPath
    }

    $entry = script:Get-ConfigurationTemplateCacheEntry -Vendor $vendorName -TemplatesPath $TemplatesPath
    if (-not $entry.Exists) { return @() }
    return $entry.Names
}

Export-ModuleMember -Function Get-ShowCommandsVersions, Get-ShowCommands, Get-ConfigurationTemplates, Get-ConfigurationTemplateData
