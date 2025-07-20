<#
.SYNOPSIS
    Builds and updates JSON definitions from log files for any "show" command, grouping by vendor, model, and OS version.
.DESCRIPTION
    * Accepts user-provided Make (vendor), Model, and OSVersion as inputs.
    * Recursively scans specified log files for "show" command segments (case-insensitive).
    * Parses every segment for header fields (Key: Value or Key is Value) and for table headers.
    * Splits multi-word VLAN Name header into two separate columns: VLAN and Name.
    * Accumulates unique commands, fields, and tables into a JSON file named vendor.model.osVersion.json.
    * Backs up corrupted JSON (keeping only last .bak) before saving.
.PARAMETER LogFiles
    Array of file paths or wildcard patterns pointing to log files to process.
.PARAMETER Make
    Vendor name ("Cisco", "Brocade", or "Arista").
.PARAMETER Model
    Device model identifier (e.g., "ASR1001", "vdx6740").
.PARAMETER OSVersion
    OS version string (e.g., "15.2(3)T1", "v9.0.0").
.PARAMETER DefinitionPath
    Directory path where JSON definition files will be created. Defaults to a "Definitions" folder next to this script.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position=0)][Alias('PSPath')][string[]] $LogFiles,
    [Parameter(Mandatory)][ValidateSet('Cisco','Brocade','Arista',IgnoreCase)][string] $Make,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $Model,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $OSVersion,
    [string] $DefinitionPath
)

# Ensure DefinitionPath exists
if (-not $DefinitionPath) {
    if ($PSScriptRoot) { $root = $PSScriptRoot } else { $root = Split-Path $MyInvocation.MyCommand.Definition -Parent }
    $DefinitionPath = Join-Path $root 'Definitions'
}
if (-not (Test-Path $DefinitionPath)) { New-Item -ItemType Directory -Path $DefinitionPath -Force | Out-Null }

function Initialize-Definition {
    param($FilePath, $Vendor, $Model, $Version)
    if (Test-Path $FilePath) {
        try {
            $def = Get-Content $FilePath -Raw | ConvertFrom-Json -Depth 20
            if ($null -eq $def.Commands) { $def.Commands = @() }
            if ($null -eq $def.Fields)   { $def.Fields   = @() }
            if ($null -eq $def.Tables)   { $def.Tables   = @() }
            return $def
        } catch {
            if (Test-Path "$FilePath.bak") { Remove-Item "$FilePath.bak" -Force }
            Rename-Item -Path $FilePath -NewName "$($FilePath).bak" -Force
        }
    }
    return [PSCustomObject]@{
        Vendor   = $Vendor
        Model    = $Model
        Version  = $Version
        Commands = @()
        Fields   = @()
        Tables   = @()
    }
}

function Save-Definition {
    param($Definition, $FilePath)
    # Coerce to arrays and sort for stable output
    if ($null -eq $Definition.Commands) { $Definition.Commands = @() }
    if ($null -eq $Definition.Fields)   { $Definition.Fields   = @() }
    if ($null -eq $Definition.Tables)   { $Definition.Tables   = @() }
    $Definition.Commands = @($Definition.Commands | Sort-Object Name)
    $Definition.Fields   = @($Definition.Fields   | Sort-Object Name, Regex)
    $Definition.Tables   = @($Definition.Tables   | Sort-Object @{Expression={($_.Columns -join ',')}}, LineRegex, Delimiter)

    $tmp = "$FilePath.tmp"
    $Definition | ConvertTo-Json -Depth 20 | Out-File -FilePath $tmp -Encoding UTF8
    Move-Item -Path $tmp -Destination $FilePath -Force
    Write-Host "Saved: $FilePath (Cmds:$($Definition.Commands.Count), Flds:$($Definition.Fields.Count), Tbls:$($Definition.Tables.Count))"
}

function Get-ShowSegmentsFromFile {
    param($Path)
    $segs = @()
    $r    = [IO.File]::OpenText($Path)
    try {
        $pat = '^[ \t]*(?:\S+[#>]\s*)?(show\b.*)'
        $cur = ''
        while (-not $r.EndOfStream) {
            $l = $r.ReadLine()
            if ($l -match $pat) {
                if ($cur) { $segs += $cur }
                $cur = $Matches[1] + "`n"
            } else { $cur += $l + "`n" }
        }
        if ($cur) { $segs += $cur }
    } finally { $r.Close() }
    return $segs
}

function Parse-Headers {
    param([string[]] $Lines)
    $out = @(); $end = $Lines.Count
    for ($i=0; $i -lt $Lines.Count; $i++) {
        if ([string]::IsNullOrWhiteSpace($Lines[$i])) { $end = $i; break }
    }
    foreach ($l in $Lines[0..($end-1)]) {
        if ($l -match '^(?<K>[^:]+):\s*(?<V>.+)$') {
            $k = $Matches.K.Trim(); $r = [regex]::Escape($k) + ':\s*(.+)'
        } elseif ($l -match '^(?<K>.+?)\s+is\s+"?(?<V>.+?)"?$') {
            $k = $Matches.K.Trim(); $r = [regex]::Escape($k) + '\s+is\s+"?(.+?)"?'
        } else { continue }
        $prop = ($k -replace '\s+','') -replace '[^A-Za-z0-9_]',''
        $out += [PSCustomObject]@{ Name=$prop; Regex=$r; Group=1; Source='' }
    }
    return $out
}

# Main
$sM = $Make.ToLower()
$sMd = ($Model     -replace '[^0-9A-Za-z\.\-]','_').ToLower()
$sV = ($OSVersion -replace '[^0-9A-Za-z\.\-]','_').ToLower()
$defFile = Join-Path $DefinitionPath "$sM.$sMd.$sV.json"
$Def     = Initialize-Definition -FilePath $defFile -Vendor $Make -Model $Model -Version $OSVersion

foreach ($p in $LogFiles) {
    Get-ChildItem -Path $p -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
        $segs = Get-ShowSegmentsFromFile -Path $_.FullName
        foreach ($seg in $segs) {
            $lines = $seg -split '\r?\n'
            $cmd   = $lines[0].Trim()
            if ($cmd -notmatch '^show\b') { continue }
            $key   = $cmd.ToLower() -replace '[^a-z0-9]','_'
            if (-not ($Def.Commands.Name -contains $key)) {
                $Def.Commands += [PSCustomObject]@{ Name=$key; Command=$cmd }
            }
            $body = if ($lines.Count -gt 1) { $lines[1..($lines.Count-1)] } else { @() }

            # Parse all header fields
            foreach ($h in Parse-Headers -Lines $body) {
                if (-not ($Def.Fields | Where-Object { $_.Name -eq $h.Name -and $_.Regex -eq $h.Regex })) {
                    $h.Source = $key
                    $Def.Fields += $h
                }
            }

            # Generic table header extraction
            $hdrIdx = -1
            # look for delimiter row
            for ($i=0; $i -lt $body.Count-1; $i++) {
                if ($body[$i+1] -match '^[\-+|=\s]{3,}$') { $hdrIdx = $i; break }
            }
            # fallback to first multi-column line
            if ($hdrIdx -lt 0) {
                for ($i=0; $i -lt $body.Count; $i++) {
                    if ($body[$i] -match '^\s*\S+(?:\s{2,}\S)+') { $hdrIdx = $i; break }
                }
            }
            if ($hdrIdx -ge 0) {
                $hLine = $body[$hdrIdx]
                $cols  = $hLine -split '\s{2,}' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
                # special: split "VLAN Name" into two columns
                $finalCols = @()
                foreach ($c in $cols) {
                    if ($c -match '^VLAN\s+Name$') {
                        $finalCols += 'VLAN'; $finalCols += 'Name'
                    } else {
                        $finalCols += $c
                    }
                }
                if ($finalCols.Count -gt 0 -and -not ($Def.Tables | Where-Object { ($_.Columns -join ',') -eq ($finalCols -join ',') })) {
                    $Def.Tables += [PSCustomObject]@{
                        Columns   = $finalCols
                        Delimiter = '\s+'
                        LineRegex = '^\s*\S+'
                        Source    = $key
                    }
                }
            }
        }
    }
}

Save-Definition -Definition $Def -FilePath $defFile
