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

    $files = Get-ChildItem -Path $dataDir -Filter '*.accdb' -File -Recurse
    $list = [System.Collections.Generic.List[string]]::new()
    foreach ($f in $files) { [void]$list.Add($f.FullName) }
    return $list.ToArray()
}

function Import-DatabaseModule {
    [CmdletBinding()]
    param()

    try {
        # Check by module name rather than path; avoids multiple loads when
        # different relative paths point at the same module.  If DatabaseModule
        # isn't loaded yet, attempt to import it from this folder.  The
        # Force/Global flags mirror the original behaviour but only run once.
        if (-not (Get-Module -Name DatabaseModule)) {
            $dbModulePath = Join-Path $PSScriptRoot 'DatabaseModule.psm1'
            if (Test-Path $dbModulePath) {
                Import-Module $dbModulePath -Force -Global -ErrorAction SilentlyContinue | Out-Null
            }
        }
    } catch {
        # Swallow any import errors; downstream functions will handle missing cmdlets.
    }
}

function Invoke-ParallelDbQuery {
    [CmdletBinding()]
    param(
        [string[]]$DbPaths,
        [string]$Sql
    )

    if (-not $DbPaths -or $DbPaths.Count -eq 0) {
        return @()
    }

    try { Import-DatabaseModule } catch { }
    $modulePath = Join-Path $PSScriptRoot 'DatabaseModule.psm1'

    $maxThreads = [Math]::Max(1, [Environment]::ProcessorCount)
    $pool = [runspacefactory]::CreateRunspacePool(1, $maxThreads)
    $pool.Open()

    $jobs = @()
    foreach ($dbPath in $DbPaths) {
        $ps = [powershell]::Create()
        $ps.RunspacePool = $pool
        $null = $ps.AddScript({
                param($dbPathArg, $sqlArg, $modPath)
                try { Import-Module -Name $modPath -DisableNameChecking -Force } catch { }
                try {
                    return DatabaseModule\Invoke-DbQuery -DatabasePath $dbPathArg -Sql $sqlArg
                } catch {
                    return $null
                }
            }).AddArgument($dbPath).AddArgument($Sql).AddArgument($modulePath)
        $job = [pscustomobject]@{ PS = $ps; AsyncResult = $ps.BeginInvoke() }
        $jobs += $job
    }

    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($job in $jobs) {
        try {
            $dt = $job.PS.EndInvoke($job.AsyncResult)
            if ($dt) { [void]$results.Add($dt) }
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
