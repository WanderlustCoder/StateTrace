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
    # When a database is available, retrieve hostnames from the DeviceSummary table.
    # Otherwise fall back to enumerating summary CSV files.  Import the DatabaseModule
    # on demand so Invoke-DbQuery is available.  $global:StateTraceDb is set by
    # MainWindow.ps1 when the database is initialized.
    if (-not $global:StateTraceDb) {
        if (-not (Test-Path $ParsedDataPath)) { return @() }
        return (Get-ChildItem -Path $ParsedDataPath -Filter '*_Summary.csv' | ForEach-Object { $_.BaseName -replace '_Summary$','' })
    }
    try {
        $dbModule = Join-Path $PSScriptRoot 'DatabaseModule.psm1'
        if (Test-Path $dbModule) {
            # Import the DatabaseModule into the global session so its functions (e.g. Invoke-DbQuery) are visible everywhere
            Import-Module $dbModule -Force -Global
        }
        $dtHosts = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql 'SELECT Hostname FROM DeviceSummary ORDER BY Hostname'
        return ($dtHosts | ForEach-Object { $_.Hostname })
    } catch {
        Write-Warning "Failed to query hostnames from database: $($_.Exception.Message). Falling back to CSV."
        if (-not (Test-Path $ParsedDataPath)) { return @() }
        return (Get-ChildItem -Path $ParsedDataPath -Filter '*_Summary.csv' | ForEach-Object { $_.BaseName -replace '_Summary$','' })
    }
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
    # If a database is in use, query interface details from the Interfaces table.
    # Otherwise fall back to reading the legacy CSV files.
    if ($global:StateTraceDb) {
        try {
            $dbModule = Join-Path $PSScriptRoot 'DatabaseModule.psm1'
            if (Test-Path $dbModule) {
                # Import DatabaseModule globally so Invoke-DbQuery is available across modules
                Import-Module $dbModule -Force -Global
            }
            $escHost = $Hostname -replace "'", "''"
            $sql = "SELECT Port, Name, Status, VLAN, Duplex, Speed, Type, LearnedMACs, AuthState, AuthMode, AuthClientMAC, AuthTemplate, Config, PortColor, ConfigStatus, ToolTip FROM Interfaces WHERE Hostname = '$escHost' ORDER BY Port"
            $dt = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql $sql
            # Determine vendor for template lookup
            $vendor = 'Cisco'
            try {
                $mkDt = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql "SELECT Make FROM DeviceSummary WHERE Hostname = '$escHost'"
                if ($mkDt -and $mkDt.Rows.Count -gt 0) {
                    $mk = $mkDt[0].Make
                    if ($mk -match '(?i)brocade') { $vendor = 'Brocade' }
                }
            } catch {}
            $vendorFile = if ($vendor -eq 'Cisco') { 'Cisco.json' } else { 'Brocade.json' }
            $jsonFile   = Join-Path $TemplatesPath $vendorFile
            $tmplJson = $null
            if (Test-Path $jsonFile) { $tmplJson = Get-Content $jsonFile -Raw | ConvertFrom-Json }
            $templates = if ($tmplJson) { $tmplJson.templates } else { $null }
            $results = @()
            foreach ($row in ($dt | Select-Object Port, Name, Status, VLAN, Duplex, Speed, Type, LearnedMACs, AuthState, AuthMode, AuthClientMAC, AuthTemplate, Config, PortColor, ConfigStatus, ToolTip)) {
                $authTemplate = $row.AuthTemplate
                $match = $null
                if ($templates) {
                    $match = $templates | Where-Object {
                        $_.name -ieq $authTemplate -or
                        ($_.aliases -and ($_.aliases -contains $authTemplate))
                    } | Select-Object -First 1
                }
                $portColor    = if ($row.PortColor) { $row.PortColor } elseif ($match) { $match.color } else { 'Gray' }
                $configStatus = if ($row.ConfigStatus) { $row.ConfigStatus } elseif ($match) { 'Match' } else { 'Mismatch' }
                $toolTip      = if ($row.ToolTip) { $row.ToolTip } else { "AuthTemplate: $authTemplate`n`n$($row.Config)" }
                $results += [PSCustomObject]@{
                    Hostname      = $Hostname
                    Port          = $row.Port
                    Name          = $row.Name
                    Status        = $row.Status
                    VLAN          = $row.VLAN
                    Duplex        = $row.Duplex
                    Speed         = $row.Speed
                    Type          = $row.Type
                    LearnedMACs   = $row.LearnedMACs
                    AuthState     = $row.AuthState
                    AuthMode      = $row.AuthMode
                    AuthClientMAC = $row.AuthClientMAC
                    ToolTip       = $toolTip
                    IsSelected    = $false
                    ConfigStatus  = $configStatus
                    PortColor     = $portColor
                }
            }
            return $results
        } catch {
            # Avoid parsing errors caused by the colon following a variable name by using formatted string expansion.
            Write-Warning (
                "Failed to load interface information from database for {0}: {1}. Falling back to CSV." -f $Hostname, $_.Exception.Message
            )
        }
    }
    # Legacy fallback to CSV
    $base    = Join-Path $ParsedDataPath $Hostname
    $sumFile = "${base}_Summary.csv"
    $ifsFile = "${base}_Interfaces_Combined.csv"
    if (-not (Test-Path $ifsFile)) { Throw "Interfaces data file not found: $ifsFile" }
    $summary  = Import-Csv $sumFile | Select-Object -First 1
    $isCisco  = $summary.Make -match 'Cisco'
    $vendorFile = if ($isCisco) { 'Cisco.json' } else { 'Brocade.json' }
    $jsonFile   = Join-Path $TemplatesPath $vendorFile
    if (-not (Test-Path $jsonFile)) { Throw "Template file missing: $jsonFile" }
    $templateJson = Get-Content $jsonFile -Raw | ConvertFrom-Json
    if (-not $templateJson.templates) { Throw "No templates found in $vendorFile — check JSON structure" }
    $templates = $templateJson.templates
    return (Import-Csv $ifsFile | ForEach-Object {
        $authTemplate = $_.AuthTemplate
        $obj = [PSCustomObject]@{
            Hostname      = $Hostname
            Port          = $_.Port
            Name          = $_.Name
            Status        = $_.Status
            VLAN          = $_.VLAN
            Duplex        = $_.Duplex
            Speed         = $_.Speed
            Type          = $_.Type
            LearnedMACs   = $_.LearnedMACs
            AuthState     = $_.AuthState
            AuthMode      = $_.AuthMode
            AuthClientMAC = $_.AuthClientMAC
            ToolTip       = "AuthTemplate: $authTemplate`n`n$($_.Config)"
            IsSelected    = $false
        }
        $match = $templates | Where-Object {
            $_.name -ieq $authTemplate -or
            ($_.aliases -and ($_.aliases -contains $authTemplate))
        } | Select-Object -First 1
        if ($match) {
            $obj | Add-Member -NotePropertyName ConfigStatus -NotePropertyValue 'Match'
            $obj | Add-Member -NotePropertyName PortColor     -NotePropertyValue $match.color
        } else {
            $obj | Add-Member -NotePropertyName ConfigStatus -NotePropertyValue 'Mismatch'
            $obj | Add-Member -NotePropertyName PortColor     -NotePropertyValue 'Gray'
        }
        $obj
    })
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
    # When a database is present, build the configuration commands using data
    # stored in the database.  Otherwise fall back to reading legacy CSV files.
    if ($global:StateTraceDb) {
        try {
            $dbModule = Join-Path $PSScriptRoot 'DatabaseModule.psm1'
            if (Test-Path $dbModule) {
                # Import DatabaseModule globally so its database functions are available
                Import-Module $dbModule -Force -Global
            }
            $escHost = $Hostname -replace "'", "''"
            # Determine vendor
            $vendor = 'Cisco'
            try {
                $mkDt = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql "SELECT Make FROM DeviceSummary WHERE Hostname = '$escHost'"
                if ($mkDt -and $mkDt.Rows.Count -gt 0) {
                    $mk = $mkDt[0].Make
                    if ($mk -match '(?i)brocade') { $vendor = 'Brocade' }
                }
            } catch {}
            $jsonFile = Join-Path $TemplatesPath "$vendor.json"
            if (-not (Test-Path $jsonFile)) { Throw "Template file missing: $jsonFile" }
            $templates = (Get-Content $jsonFile -Raw | ConvertFrom-Json).templates
            $tmpl = $templates | Where-Object { $_.name -eq $TemplateName }
            if (-not $tmpl) { Throw "Template '$TemplateName' not found in $vendor.json" }
            # Load existing config per port
            $oldConfigs = @{}
            foreach ($p in $Interfaces) {
                $pEsc = $p -replace "'", "''"
                $sqlCfg = "SELECT Config FROM Interfaces WHERE Hostname = '$escHost' AND Port = '$pEsc'"
                $dtCfg = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql $sqlCfg
                if ($dtCfg -and $dtCfg.Rows.Count -gt 0) {
                    $cfgText = $dtCfg[0].Config
                    $oldConfigs[$p] = if ($cfgText) { $cfgText -split "`n" } else { @() }
                }
            }
            $outLines = foreach ($port in $Interfaces) {
                "interface $port"
                $pending = @()
                $nameOverride = if ($NewNames.ContainsKey($port)) { $NewNames[$port] } else { $null }
                $vlanOverride = if ($NewVlans.ContainsKey($port)) { $NewVlans[$port] } else { $null }
                if ($nameOverride) { $pending += $(if ($vendor -eq 'Cisco') { "description $nameOverride" } else { "port-name $nameOverride" }) }
                if ($vlanOverride) { $pending += $(if ($vendor -eq 'Cisco') { "switchport access vlan $vlanOverride" } else { "auth-default-vlan $vlanOverride" }) }
                foreach ($cmd in $tmpl.required_commands) { $pending += $cmd.Trim() }
                if ($oldConfigs.ContainsKey($port)) {
                    foreach ($oldLine in $oldConfigs[$port]) {
                        $trimOld = $oldLine.Trim()
                        if (-not $trimOld) { continue }
                        $lowerOld = $trimOld.ToLower()
                        if ($lowerOld.StartsWith('interface') -or $lowerOld -eq 'exit') { continue }
                        # Check if the old command exists as a prefix of any new command
                        $existsInNew = $false
                        foreach ($newCmd in $pending) {
                            if ($lowerOld -like ("$($newCmd.ToLower())*")) { $existsInNew = $true; break }
                        }
                        if ($existsInNew) { continue }
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
                # Append overrides and template commands again for readability
                if ($nameOverride) { $(if ($vendor -eq 'Cisco') { " description $nameOverride" } else { " port-name $nameOverride" }) }
                if ($vlanOverride) { $(if ($vendor -eq 'Cisco') { " switchport access vlan $vlanOverride" } else { " auth-default-vlan $vlanOverride" }) }
                foreach ($cmd in $tmpl.required_commands) { $cmd }
                'exit'
                ''
            }
            return $outLines
        } catch {
            # Use formatted string to avoid PowerShell colon variable parsing issues
            Write-Warning (
                "Failed to build interface configuration from database for {0}: {1}. Falling back to CSV." -f $Hostname, $_.Exception.Message
            )
        }
    }
    # CSV fallback path
    $sumFile = Join-Path $ParsedDataPath "$($Hostname)_Summary.csv"
    $summary = Import-Csv $sumFile | Select-Object -First 1
    $vendor = if ($summary.Make -match 'Cisco') { 'Cisco' } else { 'Brocade' }
    $jsonFileCsv = Join-Path $TemplatesPath "$vendor.json"
    if (-not (Test-Path $jsonFileCsv)) { Throw "Template file missing: $jsonFileCsv" }
    $templatesCsv = (Get-Content $jsonFileCsv -Raw | ConvertFrom-Json).templates
    $tmplCsv = $templatesCsv | Where-Object { $_.name -eq $TemplateName }
    if (-not $tmplCsv) { Throw "Template '$TemplateName' not found in $vendor.json" }
    $ifsPath = Join-Path $ParsedDataPath "$($Hostname)_Interfaces_Combined.csv"
    $oldCfgs = @{}
    if (Test-Path $ifsPath) {
        try {
            $csvData = Import-Csv $ifsPath
            foreach ($row in $csvData) {
                if ($Interfaces -contains $row.Port) {
                    $oldCfgs[$row.Port] = $row.Config -split "`n"
                }
            }
        } catch {}
    }
    $finalLines = foreach ($port in $Interfaces) {
        "interface $port"
        $pending = @()
        $nameOverride = if ($NewNames.ContainsKey($port)) { $NewNames[$port] } else { $null }
        $vlanOverride = if ($NewVlans.ContainsKey($port)) { $NewVlans[$port] } else { $null }
        if ($nameOverride) { $pending += $(if ($vendor -eq 'Cisco') { "description $nameOverride" } else { "port-name $nameOverride" }) }
        if ($vlanOverride) { $pending += $(if ($vendor -eq 'Cisco') { "switchport access vlan $vlanOverride" } else { "auth-default-vlan $vlanOverride" }) }
        foreach ($cmd in $tmplCsv.required_commands) { $pending += $cmd.Trim() }
        if ($oldCfgs.ContainsKey($port)) {
            foreach ($oldLine in $oldCfgs[$port]) {
                $trimOld = $oldLine.Trim()
                if (-not $trimOld) { continue }
                $lowerOld = $trimOld.ToLower()
                if ($lowerOld.StartsWith('interface') -or $lowerOld -eq 'exit') { continue }
                $existsInNew = $false
                foreach ($newCmd in $pending) {
                    if ($lowerOld -like ("$($newCmd.ToLower())*")) { $existsInNew = $true; break }
                }
                if ($existsInNew) { continue }
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
        if ($nameOverride) { $(if ($vendor -eq 'Cisco') { " description $nameOverride" } else { " port-name $nameOverride" }) }
        if ($vlanOverride) { $(if ($vendor -eq 'Cisco') { " switchport access vlan $vlanOverride" } else { " auth-default-vlan $vlanOverride" }) }
        foreach ($cmd in $tmplCsv.required_commands) { $cmd }
        'exit'
        ''
    }
    return $finalLines
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

    # When a database is available, determine the vendor from the DeviceSummary
    # table and load the appropriate template JSON.  If the database is not
    # present or the query fails, fall back to reading the summary CSV to
    # determine the vendor.
    if ($global:StateTraceDb) {
        try {
            # Import DatabaseModule if needed
            $dbModulePath = Join-Path $PSScriptRoot 'DatabaseModule.psm1'
            if (Test-Path $dbModulePath) {
                # Import DatabaseModule globally so Invoke-DbQuery is accessible
                Import-Module $dbModulePath -Force -Global -ErrorAction Stop | Out-Null
            }
            $escHost = $Hostname -replace "'", "''"
            $dt = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql "SELECT Make FROM DeviceSummary WHERE Hostname = '$escHost'"
            $make = ''
            if ($dt -and $dt.Rows.Count -gt 0) { $make = $dt[0].Make }
            $vendorFile = if ($make -match '(?i)brocade') { 'Brocade.json' } else { 'Cisco.json' }
            $jsonFile = Join-Path $TemplatesPath $vendorFile
            if (-not (Test-Path $jsonFile)) { Throw "Template file missing: $jsonFile" }
            $templates = (Get-Content $jsonFile -Raw | ConvertFrom-Json).templates
            return $templates | Select-Object -ExpandProperty name
        } catch {
            # Format string to prevent colon after variable from causing parser errors
            Write-Warning (
                "Failed to determine configuration templates from database for {0}: {1}. Falling back to CSV." -f $Hostname, $_.Exception.Message
            )
        }
    }
    # CSV fallback: determine vendor from summary file
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
    return $templates | Select-Object -ExpandProperty name
}

Export-ModuleMember -Function `
    Get-DeviceSummaries, `
    Get-InterfaceInfo, `
    Compare-InterfaceConfigs, `
    Get-InterfaceConfiguration, `
    Get-ConfigurationTemplates, `
    Get-SpanningTreeInfo
