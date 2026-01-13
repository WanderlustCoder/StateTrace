Set-StrictMode -Version Latest

function Get-StateTraceIndexDefinitions {
    <#
    .SYNOPSIS
    Returns the expected Access index definitions used across DeviceSummary, Interfaces, Span tables, InterfaceHistory, and InterfaceBulkSeed.
    #>
    [CmdletBinding()]
    param()

    $definitions = @(
        @{ Table = 'DeviceSummary';     Name = 'idx_devicesummary_host';           Columns = @('Hostname') },
        @{ Table = 'DeviceSummary';     Name = 'idx_devicesummary_site';           Columns = @('Site') },
        @{ Table = 'Interfaces';        Name = 'IX_Interfaces_Hostname';          Columns = @('Hostname') },
        @{ Table = 'Interfaces';        Name = 'IX_Interfaces_HostnamePort';      Columns = @('Hostname','Port') },
        @{ Table = 'Interfaces';        Name = 'IX_Interfaces_Status';            Columns = @('Status') },
        @{ Table = 'Interfaces';        Name = 'IX_Interfaces_VLAN';              Columns = @('VLAN') },
        @{ Table = 'Interfaces';        Name = 'IX_Interfaces_AuthState';         Columns = @('AuthState') },
        @{ Table = 'InterfaceHistory';  Name = 'IX_InterfaceHistory_HostnameRunDate'; Columns = @('Hostname','RunDate') },
        @{ Table = 'SpanInfo';          Name = 'idx_spaninfo_host_vlan';          Columns = @('Hostname','Vlan') },
        @{ Table = 'SpanHistory';       Name = 'idx_spanhistory_host';            Columns = @('Hostname') },
        @{ Table = 'InterfaceBulkSeed'; Name = 'IX_InterfaceBulkSeed_BatchId';    Columns = @('BatchId') }
    )

    return $definitions | ForEach-Object {
        [pscustomobject]@{
            Table   = $_.Table
            Name    = $_.Name
            Columns = $_.Columns
        }
    }
}

Export-ModuleMember -Function Get-StateTraceIndexDefinitions
