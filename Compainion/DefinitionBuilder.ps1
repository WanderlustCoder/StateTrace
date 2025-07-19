<#
.SYNOPSIS
    Build or update JSON parsing definitions from individual "show" command outputs.
.DESCRIPTION
    Processes one or more raw CLI output files, auto-detects vendor and OS version,
    and updates (or creates) a JSON definition file for each vendor/OSVersion under
    Definitions\<Vendor>.<OSVersion>.json. The definitions include:
      - VersionRegex for OS detection
      - Commands with logical names and optional CLI strings
      - Single-valued fields (key:value pairs)
      - Table definitions (header-based)
.PARAMETER OutputFiles
    Array of paths to raw CLI output files (each containing one "show" command).
.PARAMETER DefinitionPath
    Directory for JSON definition files (default: "$PSScriptRoot\Definitions").
.PARAMETER CommandString
    Optional actual CLI command string to store in the JSON (e.g., "show version").
.EXAMPLE
    .\DefinitionBuilder.ps1 \
      -OutputFiles .\Logs\Extracted\ShowVersion.log, .\Logs\Extracted\ShowInterfaces.log \
      -CommandString "show version"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position=0)]
    [string[]]$OutputFiles,

    [Parameter()]
    [string]$DefinitionPath = "$PSScriptRoot\Definitions",

    [Parameter()]
    [string]$CommandString
)

# Ensure definitions directory
if (-not (Test-Path $DefinitionPath)) {
    New-Item -ItemType Directory -Path $DefinitionPath | Out-Null
}

foreach ($file in $OutputFiles) {
    Write-Host "Processing file: $file"
    $lines = Get-Content $file
    $text  = $lines -join "`n"

    # Detect vendor and set VersionRegex
    switch -Regex ($text) {
        'Cisco IOS Software'     { $vendor = 'Cisco';  $verRegex = 'Version\s+([\d\.]+),'     }
        'Fabric OS'              { $vendor = 'Brocade'; $verRegex = 'Fabric OS\s+([\d\.]+)'    }
        'Software image version' { $vendor = 'Arista';  $verRegex = 'Software image version\s+(\S+)' }
        Default {
            Write-Warning "Unknown vendor in $file, skipping."
            continue
        }
    }

    # Extract OSVersion
    if ($text -match $verRegex) {
        $osVersion = $Matches[1]
        Write-Host "Detected $vendor OS version: $osVersion"
    } else {
        Write-Warning "Could not detect OSVersion in $file using regex '$verRegex', skipping."
        continue
    }

    # Load or initialize JSON definition
    $defFile = Join-Path $DefinitionPath "$vendor.$osVersion.json"
    if (Test-Path $defFile) {
        $json = Get-Content $defFile -Raw | ConvertFrom-Json -Depth 5
    } else {
        $json = [PSCustomObject]@{
            VersionRegex = $verRegex
            Commands     = @()
            Fields       = @()
            Tables       = @()
        }
        Write-Host "Creating new definition: $defFile"
    }

    # Determine command name from file name
    $commandName = [IO.Path]::GetFileNameWithoutExtension($file)

    # Add Commands entry
    if (-not ($json.Commands | Where-Object { $_.Name -eq $commandName })) {
        $json.Commands += [PSCustomObject]@{
            Name    = $commandName
            Command = if ($CommandString) { $CommandString } else { '' }
        }
        Write-Host "Added command definition: $commandName"
    }

    # Detect key:value fields
    $kvLines = $lines | Where-Object { $_ -match '^[^:]+:\s+.+$' }
    foreach ($line in $kvLines) {
        $pair = $line -split ':', 2
        $key  = $pair[0].Trim()
        $prop = ($key -replace '\s+', '') -replace '[^A-Za-z0-9_]', ''
        $regex = [regex]::Escape($key) + ':\s*(.+)'

        if (-not ($json.Fields | Where-Object { $_.Name -eq $prop -and $_.Source -eq $commandName })) {
            $json.Fields += [PSCustomObject]@{
                Name   = $prop
                Source = $commandName
                Regex  = $regex
                Group  = 1
            }
            Write-Host "Added field definition: $prop"
        }
    }

    # Detect simple tables by header pattern
    for ($i = 0; $i -lt $lines.Count - 1; $i++) {
        if ($lines[$i] -match '\S+\s{2,}\S+' -and $lines[$i+1] -match '^\S') {
            $colNames = ($lines[$i] -split '\s{2,}') | ForEach-Object { $_.Trim() }
            $tableName = $commandName

            if (-not ($json.Tables | Where-Object { $_.Name -eq $tableName -and $_.Source -eq $commandName })) {
                $json.Tables += [PSCustomObject]@{
                    Name      = $tableName
                    Source    = $commandName
                    LineRegex = '^\S+'
                    Delimiter = '\s+'
                    Columns   = $colNames
                }
                Write-Host "Added table definition: $tableName (`$($colNames -join ', '))"
            }
            break
        }
    }

    # Save JSON definitions
    $json | ConvertTo-Json -Depth 5 | Out-File $defFile -Encoding utf8
    Write-Host "Updated definitions saved to: $defFile`n"
}
