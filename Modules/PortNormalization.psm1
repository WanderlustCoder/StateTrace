Set-StrictMode -Version Latest

# Thin wrapper to surface port normalization helpers from InterfaceModule for reuse.
# Keeps InterfaceModule as the source of truth to avoid drift.

function Get-PortSortKey {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Port)
    return InterfaceModule\Get-PortSortKey -Port $Port
}

function Get-PortSortCacheStatistics {
    [CmdletBinding()]
    param()
    return InterfaceModule\Get-PortSortCacheStatistics
}

Export-ModuleMember -Function Get-PortSortKey, Get-PortSortCacheStatistics
