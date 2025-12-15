Set-StrictMode -Version Latest

$modulePath = Join-Path -Path $PSScriptRoot -ChildPath 'ParserPersistenceModule.psm1'
if (-not (Test-Path -LiteralPath $modulePath)) {
    throw "ParserPersistenceModule.psm1 not found at $modulePath"
}

try {
    # Import into module scope so we can re-export even when the monolith is already
    # loaded globally by ModulesManifest.
    Import-Module -Name $modulePath -ErrorAction Stop | Out-Null
} catch {
    throw ("Failed to import ParserPersistenceModule.psm1 from '{0}': {1}" -f $modulePath, $_.Exception.Message)
}

# Re-export diff/cache helpers (keyed existing-row cache + related switches)
Export-ModuleMember -Function `
    Set-ParserSkipSiteCacheUpdate, `
    Get-SiteExistingRowCacheSnapshot, `
    Set-SiteExistingRowCacheSnapshot, `
    Clear-SiteExistingRowCache, `
    Import-SiteExistingRowCacheSnapshotFromEnv
