<#
.SYNOPSIS
  PowerShell module for loading interface summaries, details, compliance,
  comparing two interfaces’ configs, generating port configuration snippets,
  and retrieving available configuration template names.
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

    # Load templates and alias arrays from JSON
    $templateJson = Get-Content $jsonFile -Raw | ConvertFrom-Json
    if (-not $templateJson.templates) {
        Throw "No templates found in $vendorFile — check JSON structure"
    }
    $templates = $templateJson.templates

    # For debugging, uncomment:
    # Write-Host "`n[DEBUG] Loaded Templates from ${vendorFile}:"
    # $templates | ForEach-Object { Write-Host "  - $($_.name) (aliases: $($_.aliases -join ', '))" }

    Import-Csv $ifsFile | ForEach-Object {
        $authTemplate = $_.AuthTemplate

        $obj = [PSCustomObject]@{
            Hostname       = $Hostname
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
            ToolTip        = "AuthTemplate: $authTemplate`n`n$($_.Config)"
            IsSelected     = $false
        }

        # Match either name or any alias
        $match = $templates | Where-Object {
            $_.name -ieq $authTemplate -or
            ($_.aliases -and ($_.aliases -contains $authTemplate))
        }

        if ($match) {
            $obj | Add-Member -NotePropertyName ConfigStatus -NotePropertyValue 'Match'
            $obj | Add-Member -NotePropertyName PortColor     -NotePropertyValue $match.color
        } else {
            $obj | Add-Member -NotePropertyName ConfigStatus -NotePropertyValue 'Mismatch'
            $obj | Add-Member -NotePropertyName PortColor     -NotePropertyValue 'Gray'
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
        [string]$ScriptPath = (Join-Path $PSScriptRoot '..\Main\CompareConfigs.ps1')
    )
    if (-not (Test-Path $ScriptPath)) {
        Throw "Compare script not found: $ScriptPath"
    }
    Start-Process -FilePath 'powershell.exe' -ArgumentList @(
        '-NoProfile','-WindowStyle','Hidden',
        '-File', $ScriptPath,
        '-Switch1',$Switch1,'-Interface1',$Interface1,
        '-Switch2',$Switch2,'-Interface2',$Interface2
    ) -Wait -NoNewWindow
}

function Get-InterfaceConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]  $Hostname,
        [Parameter(Mandatory)][string[]]$Interfaces,
        [Parameter(Mandatory)][string]  $TemplateName,
        [hashtable]$NewNames,
        [hashtable]$NewVlans,
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

    # Load existing configs to generate removal commands
    $ifsPath    = Join-Path $ParsedDataPath "$($Hostname)_Interfaces_Combined.csv"
    $oldConfigs = @{}
    if (Test-Path $ifsPath) {
        try {
            $csvData = Import-Csv $ifsPath
            foreach ($row in $csvData) {
                if ($Interfaces -contains $row.Port) {
                    $oldConfigs[$row.Port] = $row.Config -split "`n"
                }
            }
        } catch {
            # ignore read errors
        }
    }

    $lines = foreach ($port in $Interfaces) {
        "interface $port"

        # Build pending commands
        $pendingCmds = @()
        $nameOverride = $null
        $vlanOverride = $null
        if ($NewNames.ContainsKey($port)) { $nameOverride = $NewNames[$port] }
        if ($NewVlans.ContainsKey($port)) { $vlanOverride = $NewVlans[$port] }

        if ($nameOverride) {
            $pendingCmds += $(if ($vendor -eq 'Cisco') { "description $nameOverride" } else { "port-name $nameOverride" })
        }
        if ($vlanOverride) {
            $pendingCmds += $(if ($vendor -eq 'Cisco') { "switchport access vlan $vlanOverride" } else { "auth-default-vlan $vlanOverride" })
        }
        foreach ($cmd in $tmpl.required_commands) {
            $pendingCmds += $cmd.Trim()
        }

        # Removal logic
        if ($oldConfigs.ContainsKey($port)) {
            foreach ($oldLine in $oldConfigs[$port]) {
                $trimOld  = $oldLine.Trim()
                if (-not $trimOld) { continue }
                $lowerOld = $trimOld.ToLower()
                if ($lowerOld.StartsWith('interface') -or $lowerOld -eq 'exit') { continue }

                $shouldRemove = $true
                foreach ($newCmd in $pendingCmds) {
                    if ($lowerOld -like ("$($newCmd.ToLower())*")) {
                        $shouldRemove = $false; break
                    }
                }
                if (-not $shouldRemove) { continue }

                if ($vendor -eq 'Cisco') {
                    if ($lowerOld.StartsWith('authentication') -or $lowerOld.StartsWith('dot1x') -or $lowerOld -eq 'mab') {
                        " no $trimOld"
                    }
                } else {
                    if ($lowerOld -match 'dot1x\s+port-control\s+auto' -or $lowerOld -match 'mac-authentication\s+enable') {
                        " no $trimOld"
                    }
                }
            }
        }

        # Apply overrides & template
        if ($nameOverride) {
            $(if ($vendor -eq 'Cisco') { " description $nameOverride" } else { " port-name $nameOverride" })
        }
        if ($vlanOverride) {
            $(if ($vendor -eq 'Cisco') { " switchport access vlan $vlanOverride" } else { " auth-default-vlan $vlanOverride" })
        }
        foreach ($cmd in $tmpl.required_commands) {
            $cmd
        }
        'exit'
        ''
    }

    return $lines
}

function Get-SpanningTreeInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Hostname,
        [string]$ParsedDataPath = (Join-Path $PSScriptRoot '..\ParsedData')
    )
    $spanFile = Join-Path $ParsedDataPath "$Hostname`_Span.csv"
    if (Test-Path $spanFile) {
        try {
            return Import-Csv $spanFile
        } catch {
            return @()
        }
    }
    return @()
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
    Get-ConfigurationTemplates, `
    Get-SpanningTreeInfo
