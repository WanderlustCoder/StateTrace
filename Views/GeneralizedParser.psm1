function Get-ShowCommandBlocks {
    param([string[]]$Lines)
    $blocks = @{}
    $current = ''
    $buffer  = @()
    foreach ($line in $Lines) {
        if ($line -match '^[\s\S]*?(show\s+.+)$' -and $line -match '^\s*(?:\S+[>#])?\s*show') {
            if ($current) { $blocks[$current] = $buffer }
            $current = ($Matches[1]).Trim().ToLower() -replace '[^a-z0-9]','_'
            $buffer = @()
        } else {
            $buffer += $line
        }
    }
    if ($current) { $blocks[$current] = $buffer }
    return $blocks
}

function Get-GeneralDeviceFacts {
    param(
        [string[]]$Lines,
        [string]$DefinitionsPath = (Join-Path $PSScriptRoot '..\Compainion\Definitions')
    )
    $vendor = if ($Lines -match 'Cisco') { 'cisco' } elseif ($Lines -match 'Brocade') { 'brocade' } elseif ($Lines -match 'Arista') { 'arista' } else { 'unknown' }
    if ($vendor -eq 'unknown') { return $null }
    $defFile = Get-ChildItem $DefinitionsPath -Filter "$vendor*.json" | Select-Object -First 1
    if (-not $defFile) { return $null }
    $def  = Get-Content $defFile.FullName -Raw | ConvertFrom-Json -Depth 20
    $blks = Get-ShowCommandBlocks -Lines $Lines
    $props = @{}
    foreach ($fld in $def.Fields) {
        if (-not $blks.ContainsKey($fld.Source)) { continue }
        foreach ($l in $blks[$fld.Source]) {
            if ($l -match $fld.Regex) { $props[$fld.Name] = $Matches[$fld.Group]; break }
        }
    }
    $obj = [PSCustomObject]$props
    $obj | Add-Member -NotePropertyName Make    -NotePropertyValue $def.Vendor -Force
    $obj | Add-Member -NotePropertyName Model   -NotePropertyValue $def.Model  -Force
    $obj | Add-Member -NotePropertyName Version -NotePropertyValue $def.Version-Force
    return $obj
}

Export-ModuleMember -Function Get-GeneralDeviceFacts