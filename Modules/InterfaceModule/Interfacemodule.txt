<#
.SYNOPSIS
  PowerShell module for loading interface summaries, details, compliance,
  comparing two interfaces’ configs (via a WPF dialog), generating port
  configuration snippets, and retrieving available configuration template names.
#>

function Get-DeviceSummaries {
    [CmdletBinding()]
    param(
        [string]$ParsedDataPath = (Join-Path $PSScriptRoot '..\ParsedData')
    )
    if (-not (Test-Path $ParsedDataPath)) { return @() }
    Get-ChildItem -Path $ParsedDataPath -Filter '*_Summary.csv' |
        ForEach-Object { $_.BaseName -replace '_Summary$','' }
}

function Get-ConfigCompliance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$ConfigLines,
        [Parameter(Mandatory)][object[]]$Templates
    )
    $normalized = $ConfigLines | ForEach-Object { $_.Trim().ToLower() }

    foreach ($template in $Templates) {
        $isMatch = $true
        foreach ($cmd in $template.required_commands) {
            if (-not ($normalized -like "$cmd*")) {
                $isMatch = $false
                break
            }
        }
        if ($isMatch) {
            return [PSCustomObject]@{
                Template     = $template.name
                ConfigStatus = 'Match'
                PortColor    = $template.color
            }
        }
    }

    return [PSCustomObject]@{
        Template     = 'Non-compliant'
        ConfigStatus = 'Mismatch'
        PortColor    = 'Red'
    }
}

function Get-InterfaceInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Hostname,
        [string]$ParsedDataPath = (Join-Path $PSScriptRoot '..\ParsedData'),
        [string]$TemplatesPath  = (Join-Path $PSScriptRoot '..\Templates')
    )

    $base    = Join-Path $ParsedDataPath $Hostname
    $sumFile = "${base}_Summary.csv"
    $ifsFile = "${base}_Interfaces_Combined.csv"

    if (-not (Test-Path $ifsFile)) {
        Throw "Interfaces data file not found: $ifsFile"
    }

    $summary = Import-Csv $sumFile | Select-Object -First 1
    $isCisco = $summary.Make -match 'Cisco'

    $vendorFile = if ($isCisco) { 'Cisco.json' } else { 'Brocade.json' }
    $jsonFile   = Join-Path $TemplatesPath $vendorFile

    if (-not (Test-Path $jsonFile)) {
        Throw "Template file missing: $jsonFile"
    }
    $templates = (Get-Content $jsonFile -Raw | ConvertFrom-Json).templates

    Import-Csv $ifsFile | ForEach-Object {
        $obj = [PSCustomObject]@{
            Port           = $_.Port
            Name           = $_.Name
            Status         = $_.Status
            VLAN           = $_.VLAN
            Duplex         = $_.Duplex
            Speed          = $_.Speed
            Type           = $_.Type
            LearnedMACs    = $_.LearnedMACs
            AuthState      = $_.AuthState
            AuthMode       = $_.AuthMode
            AuthClientMAC  = $_.AuthClientMAC
            ToolTip        = $_.ToolTip
            IsSelected     = $false
        }

        if ($isCisco) {
            $lines = ($_.Config -split "`n")
            $comp  = Get-ConfigCompliance -ConfigLines $lines -Templates $templates
            $obj | Add-Member -NotePropertyName ConfigStatus -NotePropertyValue $comp.ConfigStatus
            $obj | Add-Member -NotePropertyName PortColor    -NotePropertyValue $comp.PortColor
        } else {
            switch ($_.AuthTemplate) {
                'open'     { $color = 'Red' }
                'dot1x'    { $color = 'Green' }
                'macauth'  { $color = 'Purple' }
                'flexible' { $color = 'Blue' }
                default    { $color = 'Gray' }
            }
            $obj | Add-Member -NotePropertyName ConfigStatus -NotePropertyValue 'Match'
            $obj | Add-Member -NotePropertyName PortColor     -NotePropertyValue $color
        }

        $obj
    }
}

function Compare-InterfaceConfigs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Switch1,
        [Parameter(Mandatory)][string]$Interface1,
        [Parameter(Mandatory)][string]$Switch2,
        [Parameter(Mandatory)][string]$Interface2,
        [string]$ScriptPath = (Join-Path $PSScriptRoot 'CompareConfigs.ps1')
    )

    if (-not (Test-Path $ScriptPath)) {
        Throw "Compare script not found: $ScriptPath"
    }

    # Run the WPF launcher script in-process so its own window appears
    & $ScriptPath `
        -Switch1    $Switch1 `
        -Interface1 $Interface1 `
        -Switch2    $Switch2 `
        -Interface2 $Interface2
}

function Get-InterfaceConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]  $Hostname,
        [Parameter(Mandatory)][string[]]$Interfaces,
        [Parameter(Mandatory)][string]  $TemplateName,
        [string]$ParsedDataPath = (Join-Path $PSScriptRoot '..\ParsedData'),
        [string]$TemplatesPath  = (Join-Path $PSScriptRoot '..\Templates')
    )

    $sumFile = Join-Path $ParsedDataPath "$($Hostname)_Summary.csv"
    $summary = Import-Csv $sumFile | Select-Object -First 1

    $vendor = if ($summary.Make -match 'Cisco') { 'Cisco' } else { 'Brocade' }
    $jsonFile = Join-Path $TemplatesPath "$vendor.json"

    if (-not (Test-Path $jsonFile)) {
        Throw "Template file missing: $jsonFile"
    }
    $templates = (Get-Content $jsonFile -Raw | ConvertFrom-Json).templates

    $tmpl = $templates | Where-Object { $_.name -eq $TemplateName }
    if (-not $tmpl) {
        Throw "Template '$TemplateName' not found in $vendor.json"
    }

    $lines = foreach ($port in $Interfaces) {
        "interface $port"
        $tmpl.required_commands
        'exit'
        ''
    }
    return $lines
}

function Get-ConfigurationTemplates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Hostname,
        [string]$ParsedDataPath = (Join-Path $PSScriptRoot '..\ParsedData'),
        [string]$TemplatesPath  = (Join-Path $PSScriptRoot '..\Templates')
    )

    $sumFile = Join-Path $ParsedDataPath "$($Hostname)_Summary.csv"
    if (-not (Test-Path $sumFile)) {
        Throw "Summary file not found: $sumFile"
    }
    $summary = Import-Csv $sumFile | Select-Object -First 1

    $vendorFile = if ($summary.Make -match 'Cisco') { 'Cisco.json' } else { 'Brocade.json' }
    $jsonFile   = Join-Path $TemplatesPath $vendorFile

    if (-not (Test-Path $jsonFile)) {
        Throw "Template file missing: $jsonFile"
    }

    $templates = (Get-Content $jsonFile -Raw | ConvertFrom-Json).templates
    $templates | Select-Object -ExpandProperty name
}

Export-ModuleMember -Function `
    Get-DeviceSummaries, `
    Get-InterfaceInfo, `
    Compare-InterfaceConfigs, `
    Get-InterfaceConfiguration, `
    Get-ConfigurationTemplates
