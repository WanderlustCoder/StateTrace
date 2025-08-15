# === BEGIN TemplatesModule.psm1 ===
# Purpose: Load ShowCommands.json and expose simple query functions.
# Caching auto-invalidates on file mtime. Works on PS 5.1 and PS 7+.

# Default path: ..\Templates\ShowCommands.json (relative to this module)
$script:ShowCfgPath  = Join-Path $PSScriptRoot '..\Templates\ShowCommands.json'
$script:ShowCfg      = $null
$script:ShowCfgMtime = [datetime]::MinValue

function Set-ShowCommandsConfigPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    # Accept non-existent path (caller might set then create). Cache will fail gracefully.
    $script:ShowCfgPath  = $Path
    $script:ShowCfg      = $null
    $script:ShowCfgMtime = [datetime]::MinValue
}

function Clear-ShowCommandsCache {
    [CmdletBinding()]
    param()
    $script:ShowCfg      = $null
    $script:ShowCfgMtime = [datetime]::MinValue
}

function script:Get-ShowConfig {
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

function Get-ShowVendors {
    [CmdletBinding()]
    param()
    $cfg = Get-ShowConfig
    if (-not $cfg) { return @() }
    if ($cfg -is [hashtable]) { return ,@($cfg.Keys) }
    return ,@($cfg.PSObject.Properties.Name)
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

    $list = @()
    if ($common) { $list += $common }
    if ($OSVersion -and $versions) {
        $osList = if ($versions -is [hashtable]) { $versions[$OSVersion] } else { $versions.$OSVersion }
        if ($osList) { $list += $osList }
    }

    # Normalize + dedupe (order preserved, case-insensitive)
    $list = $list | ForEach-Object { [string]$_ } | Where-Object { $_ } | ForEach-Object { $_.TrimEnd() }
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $out  = [System.Collections.Generic.List[string]]::new()
    foreach ($c in $list) { if ($seen.Add($c)) { [void]$out.Add($c) } }
    return ,$out.ToArray()
}

Export-ModuleMember -Function Get-ShowVendors, Get-ShowCommandsVersions, Get-ShowCommands, Set-ShowCommandsConfigPath, Clear-ShowCommandsCache
# === END TemplatesModule.psm1 ===
