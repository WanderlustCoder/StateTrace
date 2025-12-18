Set-StrictMode -Version Latest

function Get-DataDirectoryPath {
    [CmdletBinding()]
    param()

    if (-not (Get-Variable -Scope Script -Name DataDirPath -ErrorAction SilentlyContinue)) {
        if (-not (Get-Variable -Scope Script -Name ModuleRootPath -ErrorAction SilentlyContinue)) {
            try {
                $script:ModuleRootPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
            } catch {
                $script:ModuleRootPath = Split-Path -Parent $PSScriptRoot
            }
        }
        $rootPath = if ($script:ModuleRootPath) { $script:ModuleRootPath } else { Split-Path -Parent $PSScriptRoot }
        $script:DataDirPath = Join-Path $rootPath 'Data'
    }

    return $script:DataDirPath
}

function Get-SiteFromHostname {
    [CmdletBinding()]
    param(
        [string]$Hostname,
        [int]$FallbackLength = 0
    )

    if ([string]::IsNullOrWhiteSpace($Hostname)) { return 'Unknown' }

    $clean = ('' + $Hostname).Trim()
    if ($clean -like 'SSH@*') { $clean = $clean.Substring(4) }
    $clean = $clean.Trim()

    if ($clean -match '^(?<site>[^-]+)-') {
        return $matches['site']
    }

    if ($FallbackLength -gt 0 -and $clean.Length -ge $FallbackLength) {
        return $clean.Substring(0, $FallbackLength)
    }

    return $clean
}

function Get-DbPathForSite {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Site,
        [string]$DataDirectoryPath
    )

    $siteCode = ('' + $Site).Trim()
    if ([string]::IsNullOrWhiteSpace($siteCode)) { $siteCode = 'Unknown' }

    $dataDir = $DataDirectoryPath
    if ([string]::IsNullOrWhiteSpace($dataDir)) {
        $dataDir = Get-DataDirectoryPath
    }
    $prefix = $siteCode
    $dashIndex = $prefix.IndexOf('-')
    if ($dashIndex -gt 0) { $prefix = $prefix.Substring(0, $dashIndex) }

    $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
    foreach ($ch in $invalidChars) {
        $prefix = $prefix.Replace([string]$ch, '_')
    }
    if ([string]::IsNullOrWhiteSpace($prefix)) { $prefix = 'Unknown' }

    $modernDir = Join-Path $dataDir $prefix
    $modernPath = Join-Path $modernDir ("{0}.accdb" -f $siteCode)
    $legacyPath = Join-Path $dataDir ("{0}.accdb" -f $siteCode)

    if (Test-Path -LiteralPath $modernPath) { return $modernPath }
    if (Test-Path -LiteralPath $legacyPath) { return $legacyPath }

    return $modernPath
}

function Get-DbPathForHost {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Hostname,
        [string]$DataDirectoryPath
    )

    $site = Get-SiteFromHostname -Hostname $Hostname
    return Get-DbPathForSite -Site $site -DataDirectoryPath $DataDirectoryPath
}

function Get-AllSiteDbPaths {
    [CmdletBinding()]
    param(
        [string]$DataDirectoryPath
    )

    $dataDir = $DataDirectoryPath
    if ([string]::IsNullOrWhiteSpace($dataDir)) {
        $dataDir = Get-DataDirectoryPath
    }
    if (-not (Test-Path $dataDir)) { return @() }

    $paths = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    # Legacy layout: Data\<Site>.accdb
    try {
        $rootFiles = Get-ChildItem -LiteralPath $dataDir -Filter '*.accdb' -File -ErrorAction SilentlyContinue
        foreach ($f in @($rootFiles)) {
            if ($f -and $f.FullName) { [void]$paths.Add(('' + $f.FullName)) }
        }
    } catch { }

    # Preferred layout: Data\<Site>\<Site>.accdb (site DBs live directly under the site directory).
    try {
        $dirs = Get-ChildItem -LiteralPath $dataDir -Directory -ErrorAction SilentlyContinue
        foreach ($dir in @($dirs)) {
            if (-not $dir -or [string]::IsNullOrWhiteSpace($dir.FullName)) { continue }
            $dirFiles = $null
            try { $dirFiles = Get-ChildItem -LiteralPath $dir.FullName -Filter '*.accdb' -File -ErrorAction SilentlyContinue } catch { $dirFiles = $null }
            foreach ($f in @($dirFiles)) {
                if ($f -and $f.FullName) { [void]$paths.Add(('' + $f.FullName)) }
            }
        }
    } catch { }

    # Rare fallback: deep nested DBs (avoid unless the common layouts yielded nothing).
    if ($paths.Count -eq 0) {
        try {
            $deepFiles = Get-ChildItem -LiteralPath $dataDir -Filter '*.accdb' -File -Recurse -ErrorAction SilentlyContinue
            foreach ($f in @($deepFiles)) {
                if ($f -and $f.FullName) { [void]$paths.Add(('' + $f.FullName)) }
            }
        } catch { }
    }

    return @($paths)
}

function Import-DatabaseModule {
    [CmdletBinding()]
    param()

    try {
        # Check by module name rather than path; avoids multiple loads when
        # different relative paths point at the same module.  If DatabaseModule
        # isn't loaded yet, attempt to import it from this folder.  The
        # Force/Global flags mirror the original behaviour but only run once.
        if (Get-Module -Name DatabaseModule -ErrorAction SilentlyContinue) { return }

        $dbModulePath = Join-Path $PSScriptRoot 'DatabaseModule.psm1'
        if (Test-Path -LiteralPath $dbModulePath) {
            Import-Module $dbModulePath -Force -Global -ErrorAction SilentlyContinue | Out-Null
        }
    } catch {
        # Swallow any import errors; downstream functions will handle missing cmdlets.
    }
}

function Invoke-ParallelDbQuery {
    [CmdletBinding()]
    param(
        [string[]]$DbPaths,
        [string]$Sql,
        [switch]$IncludeDbPath,
        [int]$MaxThreads = 0
    )

    if (-not $DbPaths -or $DbPaths.Count -eq 0) {
        return @()
    }

    $existingDbPaths = [System.Collections.Generic.List[string]]::new()
    foreach ($dbPath in $DbPaths) {
        if ([string]::IsNullOrWhiteSpace($dbPath)) { continue }
        if (-not (Test-Path -LiteralPath $dbPath)) { continue }
        [void]$existingDbPaths.Add($dbPath)
    }

    if ($existingDbPaths.Count -eq 0) {
        return @()
    }

    $DbPaths = $existingDbPaths.ToArray()

    $requestedThreads = $MaxThreads
    if ($requestedThreads -le 0) { $requestedThreads = [Environment]::ProcessorCount }
    $requestedThreads = [Math]::Max(1, $requestedThreads)
    $requestedThreads = [Math]::Min($requestedThreads, $DbPaths.Count)

    $sessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $sessionState.ApartmentState = [System.Threading.ApartmentState]::STA
    $sessionState.LanguageMode = [System.Management.Automation.PSLanguageMode]::FullLanguage

    $pool = [runspacefactory]::CreateRunspacePool(1, $requestedThreads, $sessionState, $Host)
    try { $pool.ApartmentState = [System.Threading.ApartmentState]::STA } catch { }
    $pool.Open()

    $jobs = @()
    foreach ($dbPath in $DbPaths) {
        $ps = [powershell]::Create()
        $ps.RunspacePool = $pool
        $null = $ps.AddScript({
                param($dbPathArg, $sqlArg, $includeDbPathArg)
                $ErrorActionPreference = 'Stop'

                $payload = $null
                $connection = $null
                $recordset = $null
                try {
                    $connection = New-Object -ComObject ADODB.Connection
                    $opened = $false
                    foreach ($prov in @('Microsoft.ACE.OLEDB.12.0','Microsoft.Jet.OLEDB.4.0')) {
                        try {
                            $connection.Open(("Provider={0};Data Source={1}" -f $prov, $dbPathArg))
                            $opened = $true
                            break
                        } catch {
                            try { $connection.Close() } catch { }
                        }
                    }

                    if (-not $opened) {
                        $payload = $null
                    } else {
                        $recordset = $connection.Execute($sqlArg)
                        $rowsList = [System.Collections.Generic.List[object]]::new()

                        if ($recordset -and $recordset.State -eq 1) {
                            $fieldCount = 0
                            try { $fieldCount = [int]$recordset.Fields.Count } catch { $fieldCount = 0 }
                            if ($fieldCount -gt 0) {
                                $fieldNames = New-Object string[] $fieldCount
                                for ($fieldIndex = 0; $fieldIndex -lt $fieldCount; $fieldIndex++) {
                                    $fieldName = ''
                                    try { $fieldName = '' + $recordset.Fields.Item($fieldIndex).Name } catch { $fieldName = '' }
                                    $fieldNames[$fieldIndex] = $fieldName
                                }

                                $rawRows = $null
                                try { $rawRows = $recordset.GetRows() } catch { $rawRows = $null }

                                if ($rawRows -and ($rawRows.Rank -ge 2)) {
                                    $rowCount = 0
                                    try { $rowCount = $rawRows.GetUpperBound(1) + 1 } catch { $rowCount = 0 }

                                    for ($rowIndex = 0; $rowIndex -lt $rowCount; $rowIndex++) {
                                        $rowMap = [ordered]@{}
                                        for ($fieldIndex = 0; $fieldIndex -lt $fieldCount; $fieldIndex++) {
                                            $name = $fieldNames[$fieldIndex]
                                            if ([string]::IsNullOrWhiteSpace($name)) { continue }

                                            $value = $null
                                            try { $value = $rawRows[$fieldIndex, $rowIndex] } catch { $value = $null }
                                            if ($value -eq [System.DBNull]::Value) { $value = $null }
                                            $rowMap[$name] = $value
                                        }
                                        [void]$rowsList.Add([pscustomobject]$rowMap)
                                    }
                                }
                            }
                        }

                        $payload = $rowsList.ToArray()
                    }
                } catch {
                    $payload = $null
                } finally {
                    if ($recordset) {
                        try { $recordset.Close() } catch { }
                        if ($recordset -is [System.__ComObject]) {
                            try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($recordset) } catch { }
                        }
                    }
                    if ($connection) {
                        try { $connection.Close() } catch { }
                        if ($connection -is [System.__ComObject]) {
                            try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($connection) } catch { }
                        }
                    }
                }
                if ($includeDbPathArg) {
                    return [pscustomobject]@{
                        DatabasePath = $dbPathArg
                        Data         = $payload
                    }
                }
                return $payload
            }).AddArgument($dbPath).AddArgument($Sql).AddArgument($IncludeDbPath.IsPresent)
        $job = [pscustomobject]@{ PS = $ps; AsyncResult = $ps.BeginInvoke() }
        $jobs += $job
    }

    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($job in $jobs) {
        try {
            $payload = $job.PS.EndInvoke($job.AsyncResult)
            if ($payload) {
                foreach ($item in $payload) {
                    if ($item) { [void]$results.Add($item) }
                }
            }
        } catch { }
        finally {
            $job.PS.Dispose()
        }
    }

    $pool.Close()
    $pool.Dispose()
    return $results.ToArray()
}

Export-ModuleMember -Function `
    Get-DataDirectoryPath, `
    Get-SiteFromHostname, `
    Get-DbPathForSite, `
    Get-DbPathForHost, `
    Get-AllSiteDbPaths, `
    Import-DatabaseModule, `
    Invoke-ParallelDbQuery
