Set-StrictMode -Version Latest

if (-not (Get-Module -Name DeviceRepositoryModule)) {
    $repoModulePath = Join-Path -Path $PSScriptRoot -ChildPath 'DeviceRepositoryModule.psm1'
    if (-not (Test-Path -LiteralPath $repoModulePath)) {
        throw "DeviceRepositoryModule.psm1 not found at $repoModulePath"
    }
    Import-Module -Name $repoModulePath -Force
}

# Re-export cache-related helpers from DeviceRepositoryModule
Export-ModuleMember -Function `
    Get-SharedSiteInterfaceCacheStore, `
    Get-SharedSiteInterfaceCacheEntry, `
    Get-SharedSiteInterfaceCacheSnapshotEntries, `
    Restore-SharedCacheEntries, `
    Restore-SharedCacheEntriesFromFile, `
    Export-SharedCacheSnapshot, `
    Get-SharedSiteInterfaceCache
