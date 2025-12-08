Set-StrictMode -Version Latest

if (-not (Get-Variable -Scope Script -Name PortSortFallbackKey -ErrorAction SilentlyContinue)) {
    $script:PortSortFallbackKey = '99-UNK-99999-99999-99999-99999-99999'
}

function Get-StringPropertyValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$InputObject,
        [Parameter(Mandatory)][string[]]$PropertyNames
    )

    foreach ($name in $PropertyNames) {
        try {
            $prop = $InputObject.PSObject.Properties[$name]
            if ($prop -and $null -ne $prop.Value) {
                $val = '' + $prop.Value
                if (-not [string]::IsNullOrWhiteSpace($val)) { return $val }
            }
        } catch { continue }
    }
    return ''
}

function Ensure-PortRowDefaults {
    [CmdletBinding()]
    param(
        $Row,
        [string]$Hostname
    )

    if ($null -eq $Row) { return }

    try {
        if (-not $Row.PSObject.Properties['Hostname']) {
            $Row | Add-Member -NotePropertyName Hostname -NotePropertyValue $Hostname -ErrorAction SilentlyContinue
        }
    } catch { }

    try {
        if (-not $Row.PSObject.Properties['IsSelected']) {
            $Row | Add-Member -NotePropertyName IsSelected -NotePropertyValue $false -ErrorAction SilentlyContinue
        }
    } catch { }
}

function Get-PortSortFallbackKey {
    [CmdletBinding()]
    param()
    return $script:PortSortFallbackKey
}

Export-ModuleMember -Function Get-StringPropertyValue, Ensure-PortRowDefaults, Get-PortSortFallbackKey
