Set-StrictMode -Version Latest

if (-not (Get-Module -Name DeviceRepositoryModule)) {
    $repoModulePath = Join-Path -Path $PSScriptRoot -ChildPath 'DeviceRepositoryModule.psm1'
    if (-not (Test-Path -LiteralPath $repoModulePath)) {
        throw "DeviceRepositoryModule.psm1 not found at $repoModulePath"
    }
    Import-Module -Name $repoModulePath -Force
}

# Re-export Access-related helpers from DeviceRepositoryModule
Export-ModuleMember -Function `
    Get-DbPathForSite, `
    Get-DbPathForSiteGrouped, `
    Get-DbConnectionForSite, `
    Get-DbConnectionCacheKey, `
    Remove-DbConnectionForSite, `
    Remove-DbConnectionCache, `
    Get-DbConnectionCacheMetrics
