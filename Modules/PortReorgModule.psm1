Set-StrictMode -Version Latest

function script:Ensure-LocalStateTraceModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ModuleName,
        [Parameter(Mandatory)][string]$ModuleFileName
    )

    try {
        if (Get-Module -Name $ModuleName -ErrorAction SilentlyContinue) {
            return
        }

        $path = Join-Path -Path $PSScriptRoot -ChildPath $ModuleFileName
        if (Test-Path -LiteralPath $path) {
            Import-Module -Name $path -Force -Global -ErrorAction Stop | Out-Null
        }
    } catch {
        throw
    }
}

function script:Ensure-DeviceRepositoryModule {
    script:Ensure-LocalStateTraceModule -ModuleName 'DeviceRepositoryModule' -ModuleFileName 'DeviceRepositoryModule.psm1'
}

function script:Ensure-DatabaseModule {
    script:Ensure-LocalStateTraceModule -ModuleName 'DatabaseModule' -ModuleFileName 'DatabaseModule.psm1'
}

function script:Ensure-TemplatesModule {
    script:Ensure-LocalStateTraceModule -ModuleName 'TemplatesModule' -ModuleFileName 'TemplatesModule.psm1'
}

function script:Get-PortReorgVendorFromDb {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Hostname
    )

    script:Ensure-DeviceRepositoryModule
    script:Ensure-DatabaseModule
    script:Ensure-TemplatesModule

    $dbPath = $null
    try {
        $dbPath = DeviceRepositoryModule\Get-DbPathForHost -Hostname $Hostname
    } catch {
        $dbPath = $null
    }
    if (-not $dbPath -or -not (Test-Path -LiteralPath $dbPath)) {
        return 'Cisco'
    }

    $escHost = $Hostname -replace "'", "''"
    try {
        $escHost = DatabaseModule\Get-SqlLiteral -Value $Hostname
    } catch {
        $escHost = $Hostname -replace "'", "''"
    }

    try {
        $dt = DatabaseModule\Invoke-DbQuery -DatabasePath $dbPath -Sql "SELECT Make FROM DeviceSummary WHERE Hostname = '$escHost'"
        if ($dt) {
            $rows = DatabaseModule\ConvertTo-DbRowList -Data $dt
            if ($rows.Count -gt 0) {
                $mk = $null
                try { $mk = '' + $rows[0].Make } catch { $mk = $null }
                if (-not [string]::IsNullOrWhiteSpace($mk)) {
                    return TemplatesModule\Get-TemplateVendorKeyFromMake -Make $mk
                }
            }
        }
    } catch {
    }

    return 'Cisco'
}

function script:Split-ConfigLines {
    [CmdletBinding()]
    param(
        [Parameter()][AllowEmptyString()][string]$ConfigText
    )

    if ([string]::IsNullOrWhiteSpace($ConfigText)) { return @() }

    $parts = $ConfigText -split "`r?`n"
    $list = [System.Collections.Generic.List[string]]::new()
    foreach ($p in $parts) {
        $t = ('' + $p).Trim()
        if (-not $t) { continue }
        $list.Add($t) | Out-Null
    }
    return $list.ToArray()
}

function script:Get-CiscoAdminEnabled {
    param([string[]]$ConfigLines)

    if (-not $ConfigLines) { return $true }
    $hasShutdown = $false
    $hasNoShutdown = $false
    foreach ($line in $ConfigLines) {
        $t = ('' + $line).Trim()
        if (-not $t) { continue }
        if ($t.Equals('shutdown', [System.StringComparison]::OrdinalIgnoreCase)) { $hasShutdown = $true }
        elseif ($t.Equals('no shutdown', [System.StringComparison]::OrdinalIgnoreCase)) { $hasNoShutdown = $true }
    }

    if ($hasShutdown -and -not $hasNoShutdown) { return $false }
    if ($hasNoShutdown) { return $true }
    return $true
}

function script:Get-BrocadeAdminEnabled {
    param([string]$Status)

    $text = ('' + $Status).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return $true }
    if ($text.Equals('Disable', [System.StringComparison]::OrdinalIgnoreCase) -or
        $text.Equals('Disabled', [System.StringComparison]::OrdinalIgnoreCase)) {
        return $false
    }
    return $true
}

function script:Get-ConfigLinesForApply {
    param(
        [Parameter()][AllowEmptyCollection()][string[]]$ConfigLines,
        [Parameter(Mandatory)][ValidateSet('Cisco','Brocade')][string]$Vendor
    )

    if (-not $ConfigLines) { return @() }

    $out = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $ConfigLines) {
        $t = ('' + $line).Trim()
        if (-not $t) { continue }
        if ($t.StartsWith('!', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($t.StartsWith('#', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($t.Equals('exit', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($t.StartsWith('interface ', [System.StringComparison]::OrdinalIgnoreCase)) { continue }

        if ($Vendor -eq 'Cisco') {
            if ($t.StartsWith('description', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
            if ($t.StartsWith('no description', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
            if ($t.Equals('shutdown', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
            if ($t.Equals('no shutdown', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        } else {
            if ($t.StartsWith('port-name', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
            if ($t.StartsWith('no port-name', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
            if ($t.Equals('disable', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
            if ($t.Equals('enable',  [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        }

        $out.Add($t) | Out-Null
    }

    return $out.ToArray()
}

function script:Get-BrocadeResetNoLines {
    param(
        [Parameter()][AllowEmptyCollection()][string[]]$TargetConfigLines,
        [Parameter()][AllowEmptyCollection()][string[]]$DesiredConfigLines
    )

    if (-not $TargetConfigLines) { return @() }

    $desired = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($line in @($DesiredConfigLines)) {
        $t = ('' + $line).Trim()
        if (-not $t) { continue }
        if ($t.StartsWith('!', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($t.StartsWith('#', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($t.Equals('exit', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($t.StartsWith('interface ', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($t.Equals('disable', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($t.Equals('enable',  [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($t.StartsWith('port-name', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($t.StartsWith('no port-name', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        $desired.Add($t) | Out-Null
    }

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $out  = [System.Collections.Generic.List[string]]::new()

    foreach ($line in $TargetConfigLines) {
        $t = ('' + $line).Trim()
        if (-not $t) { continue }
        if ($t.StartsWith('!', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($t.StartsWith('#', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($t.Equals('exit', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($t.StartsWith('interface ', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($t.Equals('disable', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($t.Equals('enable',  [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($t.StartsWith('port-name', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($t.StartsWith('no port-name', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($t.StartsWith('no ', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($desired.Contains($t)) { continue }

        $no = 'no ' + $t
        if ($seen.Add($no)) { $out.Add($no) | Out-Null }
    }

    return $out.ToArray()
}

function script:Get-CiscoDescriptionCommand {
    param([string]$Label)

    $text = ('' + $Label)
    $text = $text -replace '\r|\n', ' '
    $text = $text.Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return 'no description' }
    return ('description {0}' -f $text)
}

function script:Get-BrocadePortNameCommand {
    param([string]$Label)

    $text = ('' + $Label)
    $text = $text -replace '\r|\n', ' '
    $text = $text.Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return 'no port-name' }

    $safe = $text -replace '"', "'"
    return ('port-name "{0}"' -f $safe)
}

function script:Get-BrocadeInterfaceSpec {
    param([string]$Port)

    $p = ('' + $Port).Trim()
    if ([string]::IsNullOrWhiteSpace($p)) { return $p }

    if ($p -match '^(?i)et(\d+/\d+/\d+)$') { return ('ethernet {0}' -f $matches[1]) }
    if ($p -match '^(?i)ethernet(\d+/\d+/\d+)$') { return ('ethernet {0}' -f $matches[1]) }
    if ($p -match '^(\d+/\d+/\d+)$') { return ('ethernet {0}' -f $matches[1]) }

    return $p
}

function Get-PortReorgSuggestedPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$PlanRows,
        [Parameter(Mandatory)][string[]]$AvailablePorts
    )

    $rows = @($PlanRows)
    $ports = @($AvailablePorts)
    if ($rows.Count -eq 0 -or $ports.Count -eq 0) { return $rows }

    $rowList = [System.Collections.Generic.List[object]]::new()
    foreach ($r in $rows) { if ($r) { $rowList.Add($r) | Out-Null } }

    $portList = [System.Collections.Generic.List[string]]::new()
    foreach ($p in $ports) {
        $t = ('' + $p).Trim()
        if (-not [string]::IsNullOrWhiteSpace($t)) { $portList.Add($t) | Out-Null }
    }

    $extractGroupKey = {
        param([string]$Label)
        $t = ('' + $Label).Trim()
        if (-not $t) { return '' }
        if ($t -match '^([A-Za-z]+)') { return $matches[1] }
        if ($t -match '^([^\\s-]+)') { return $matches[1] }
        return $t
    }

    $sorted = $rowList | Sort-Object `
        @{ Expression = { & $extractGroupKey ('' + $_.NewLabel) } } `
        @{ Expression = { ('' + $_.NewLabel).Trim() } } `
        @{ Expression = { ('' + $_.SourcePort).Trim() } }

    $i = 0
    foreach ($row in $sorted) {
        if ($i -ge $portList.Count) { break }
        try { $row.TargetPort = $portList[$i] } catch { }
        $i++
    }

    return $rows
}

function New-PortReorgScripts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Hostname,
        [Parameter(Mandatory)][object[]]$PlanRows,
        [ValidateSet('Cisco','Brocade')][string]$Vendor,
        [object[]]$BaselineInterfaces,
        [int]$ChunkSize = 12
    )

    $rows = @($PlanRows)
    if (-not $rows -or $rows.Count -eq 0) {
        throw 'Port reorg plan is empty.'
    }

    $vendorKey = $Vendor
    if ([string]::IsNullOrWhiteSpace($vendorKey)) {
        $vendorKey = script:Get-PortReorgVendorFromDb -Hostname $Hostname
    }
    if ($vendorKey -ne 'Cisco' -and $vendorKey -ne 'Brocade') { $vendorKey = 'Cisco' }

    $interfaces = @()
    if ($BaselineInterfaces) {
        $interfaces = @($BaselineInterfaces)
    } else {
        script:Ensure-DeviceRepositoryModule
        $interfaces = @(DeviceRepositoryModule\Get-InterfaceInfo -Hostname $Hostname)
    }

    $baselineByPort = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($iface in $interfaces) {
        if (-not $iface) { continue }
        $p = ''
        try { $p = ('' + $iface.Port).Trim() } catch { $p = '' }
        if (-not [string]::IsNullOrWhiteSpace($p) -and -not $baselineByPort.ContainsKey($p)) {
            $baselineByPort[$p] = $iface
        }
    }

    if ($baselineByPort.Count -eq 0) {
        throw ("No baseline interface rows found for {0}." -f $Hostname)
    }

    $seenTargets = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $changedRows = [System.Collections.Generic.List[object]]::new()

    foreach ($row in $rows) {
        if (-not $row) { continue }
        $src = ('' + $row.SourcePort).Trim()
        $dst = ('' + $row.TargetPort).Trim()
        $newLabel = ''
        try { $newLabel = '' + $row.NewLabel } catch { $newLabel = '' }

        if ([string]::IsNullOrWhiteSpace($dst)) {
            throw 'Every plan row must include TargetPort.'
        }
        if (-not $baselineByPort.ContainsKey($dst)) { throw ("Unknown TargetPort '{0}'." -f $dst) }
        if (-not $seenTargets.Add($dst)) { throw ("TargetPort '{0}' is assigned more than once." -f $dst) }

        $hasSource = -not [string]::IsNullOrWhiteSpace($src)
        $isClear = -not $hasSource
        if ($isClear -and -not [string]::IsNullOrWhiteSpace($newLabel)) {
            throw ("TargetPort '{0}' cannot set NewLabel without SourcePort." -f $dst)
        }

        $baselineLabel = ''
        if ($hasSource) {
            if (-not $baselineByPort.ContainsKey($src)) { throw ("Unknown SourcePort '{0}'." -f $src) }
            try { $baselineLabel = '' + $baselineByPort[$src].Name } catch { $baselineLabel = '' }
        } else {
            try { $baselineLabel = '' + $baselineByPort[$dst].Name } catch { $baselineLabel = '' }
        }

        $isMove = $hasSource -and -not $src.Equals($dst, [System.StringComparison]::OrdinalIgnoreCase)
        $isRename = -not ($baselineLabel.Trim()).Equals($newLabel.Trim(), [System.StringComparison]::OrdinalIgnoreCase)

        if ($isClear -or $isMove -or $isRename) {
            $changedRows.Add($row) | Out-Null
        }
    }

    if ($changedRows.Count -eq 0) {
        return [PSCustomObject]@{
            Vendor        = $vendorKey
            ChangeScript  = @()
            RollbackScript = @()
            AffectedPorts = @()
        }
    }

    $affectedTargets = [System.Collections.Generic.List[string]]::new()
    foreach ($row in $changedRows) {
        $dst = ('' + $row.TargetPort).Trim()
        if (-not $affectedTargets.Contains($dst)) {
            $affectedTargets.Add($dst) | Out-Null
        }
    }

    $targetOrder = $affectedTargets.ToArray() | Sort-Object -Property @{
        Expression = {
            $p = $_
            if ($baselineByPort.ContainsKey($p) -and $baselineByPort[$p].PSObject.Properties['PortSort']) {
                return '' + $baselineByPort[$p].PortSort
            }
            return '' + $p
        }
    }

    $chunkSizeResolved = [int]$ChunkSize
    if ($chunkSizeResolved -lt 1) { $chunkSizeResolved = 0 }

    $chunks = [System.Collections.Generic.List[object]]::new()
    if ($chunkSizeResolved -eq 0) {
        $chunks.Add([PSCustomObject]@{ Index = 1; Ports = $targetOrder }) | Out-Null
    } else {
        $idx = 0
        $chunkIdx = 1
        while ($idx -lt $targetOrder.Count) {
            $take = [Math]::Min($chunkSizeResolved, $targetOrder.Count - $idx)
            $subset = $targetOrder[$idx..($idx + $take - 1)]
            $chunks.Add([PSCustomObject]@{ Index = $chunkIdx; Ports = $subset }) | Out-Null
            $idx += $take
            $chunkIdx++
        }
    }

    $changeLines = [System.Collections.Generic.List[string]]::new()
    $rollbackLines = [System.Collections.Generic.List[string]]::new()

    $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $header = @(
        '! StateTrace Port Reorg',
        ("! Host: {0}" -f $Hostname),
        ("! Vendor: {0}" -f $vendorKey),
        ("! Generated: {0}" -f $stamp),
        '! Review before applying.',
        ''
    )

    foreach ($h in $header) { $changeLines.Add($h) | Out-Null }
    foreach ($h in $header) { $rollbackLines.Add($h) | Out-Null }
    $changeLines.Add('configure terminal') | Out-Null
    $rollbackLines.Add('configure terminal') | Out-Null

    foreach ($chunk in $chunks) {
        $chunkPorts = @($chunk.Ports)
        if ($chunkPorts.Count -eq 0) { continue }

        $changeLines.Add(("! ---- Block {0} ----" -f $chunk.Index)) | Out-Null
        $rollbackLines.Add(("! ---- Block {0} ----" -f $chunk.Index)) | Out-Null

        foreach ($targetPort in $chunkPorts) {
            $row = $null
            foreach ($r in $changedRows) {
                if ((('' + $r.TargetPort).Trim()).Equals($targetPort, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $row = $r
                    break
                }
            }
            if (-not $row) { continue }

            $src = ('' + $row.SourcePort).Trim()
            $dst = ('' + $row.TargetPort).Trim()
            $newLabel = ''
            try { $newLabel = '' + $row.NewLabel } catch { $newLabel = '' }

            $dstBaseline = $baselineByPort[$dst]

            $rollbackLabel = ''
            try { $rollbackLabel = '' + $dstBaseline.Name } catch { $rollbackLabel = '' }

            $hasSource = -not [string]::IsNullOrWhiteSpace($src)
            $isClear = -not $hasSource
            if ($isClear) {
                $dstCfgLinesRaw = @()
                try { $dstCfgLinesRaw = script:Split-ConfigLines -ConfigText ('' + $dstBaseline.Config) } catch { $dstCfgLinesRaw = @() }

                if ($vendorKey -eq 'Cisco') {
                    $changeLines.Add(("! Clear {0}" -f $dst)) | Out-Null
                    $changeLines.Add(("default interface {0}" -f $dst)) | Out-Null
                    $changeLines.Add(("interface {0}" -f $dst)) | Out-Null
                    $changeLines.Add(' shutdown') | Out-Null
                    $changeLines.Add((' ' + (script:Get-CiscoDescriptionCommand -Label $newLabel))) | Out-Null
                    $changeLines.Add('exit') | Out-Null
                    $changeLines.Add('') | Out-Null
                } else {
                    $ifaceSpec = script:Get-BrocadeInterfaceSpec -Port $dst
                    $changeLines.Add(("! Clear {0}" -f $dst)) | Out-Null
                    $changeLines.Add(("interface {0}" -f $ifaceSpec)) | Out-Null
                    $changeLines.Add(' disable') | Out-Null
                    $changeLines.Add(' no port-name') | Out-Null
                    $resetNo = script:Get-BrocadeResetNoLines -TargetConfigLines $dstCfgLinesRaw
                    foreach ($cmd in $resetNo) { $changeLines.Add((' ' + $cmd)) | Out-Null }
                    $changeLines.Add((' ' + (script:Get-BrocadePortNameCommand -Label $newLabel))) | Out-Null
                    $changeLines.Add(' exit') | Out-Null
                    $changeLines.Add('') | Out-Null
                }

                $dstApplyLines = script:Get-ConfigLinesForApply -ConfigLines $dstCfgLinesRaw -Vendor $vendorKey

                $dstEnableAtEnd = $true
                if ($vendorKey -eq 'Cisco') {
                    $dstEnableAtEnd = script:Get-CiscoAdminEnabled -ConfigLines $dstCfgLinesRaw
                } else {
                    $dstStatusText = ''
                    try { $dstStatusText = '' + $dstBaseline.Status } catch { $dstStatusText = '' }
                    $dstEnableAtEnd = script:Get-BrocadeAdminEnabled -Status $dstStatusText
                }

                if ($vendorKey -eq 'Cisco') {
                    $rollbackLines.Add(("! Restore {0}" -f $dst)) | Out-Null
                    $rollbackLines.Add(("default interface {0}" -f $dst)) | Out-Null
                    $rollbackLines.Add(("interface {0}" -f $dst)) | Out-Null
                    $rollbackLines.Add(' shutdown') | Out-Null
                    foreach ($cmd in $dstApplyLines) { $rollbackLines.Add((' ' + $cmd)) | Out-Null }
                    $rollbackLines.Add((' ' + (script:Get-CiscoDescriptionCommand -Label $rollbackLabel))) | Out-Null
                    if ($dstEnableAtEnd) { $rollbackLines.Add(' no shutdown') | Out-Null }
                    $rollbackLines.Add('exit') | Out-Null
                    $rollbackLines.Add('') | Out-Null
                } else {
                    $ifaceSpec = script:Get-BrocadeInterfaceSpec -Port $dst
                    $rollbackLines.Add(("! Restore {0}" -f $dst)) | Out-Null
                    $rollbackLines.Add(("interface {0}" -f $ifaceSpec)) | Out-Null
                    $rollbackLines.Add(' disable') | Out-Null
                    $rollbackLines.Add(' no port-name') | Out-Null
                    $resetNo = script:Get-BrocadeResetNoLines -TargetConfigLines $dstCfgLinesRaw
                    foreach ($cmd in $resetNo) { $rollbackLines.Add((' ' + $cmd)) | Out-Null }
                    foreach ($cmd in $dstApplyLines) { $rollbackLines.Add((' ' + $cmd)) | Out-Null }
                    $rollbackLines.Add((' ' + (script:Get-BrocadePortNameCommand -Label $rollbackLabel))) | Out-Null
                    if ($dstEnableAtEnd) { $rollbackLines.Add(' enable') | Out-Null }
                    $rollbackLines.Add(' exit') | Out-Null
                    $rollbackLines.Add('') | Out-Null
                }

                continue
            }

            $srcBaseline = $baselineByPort[$src]
            $isMove = -not $src.Equals($dst, [System.StringComparison]::OrdinalIgnoreCase)
            if (-not $isMove) {
                if ($vendorKey -eq 'Cisco') {
                    $changeLines.Add(("! Rename {0}" -f $dst)) | Out-Null
                    $changeLines.Add(("interface {0}" -f $dst)) | Out-Null
                    $changeLines.Add((' ' + (script:Get-CiscoDescriptionCommand -Label $newLabel))) | Out-Null
                    $changeLines.Add('exit') | Out-Null
                    $changeLines.Add('') | Out-Null

                    $rollbackLines.Add(("! Restore label on {0}" -f $dst)) | Out-Null
                    $rollbackLines.Add(("interface {0}" -f $dst)) | Out-Null
                    $rollbackLines.Add((' ' + (script:Get-CiscoDescriptionCommand -Label $rollbackLabel))) | Out-Null
                    $rollbackLines.Add('exit') | Out-Null
                    $rollbackLines.Add('') | Out-Null
                } else {
                    $ifaceSpec = script:Get-BrocadeInterfaceSpec -Port $dst
                    $changeLines.Add(("! Rename {0}" -f $dst)) | Out-Null
                    $changeLines.Add(("interface {0}" -f $ifaceSpec)) | Out-Null
                    $changeLines.Add((' ' + (script:Get-BrocadePortNameCommand -Label $newLabel))) | Out-Null
                    $changeLines.Add(' exit') | Out-Null
                    $changeLines.Add('') | Out-Null

                    $rollbackLines.Add(("! Restore label on {0}" -f $dst)) | Out-Null
                    $rollbackLines.Add(("interface {0}" -f $ifaceSpec)) | Out-Null
                    $rollbackLines.Add((' ' + (script:Get-BrocadePortNameCommand -Label $rollbackLabel))) | Out-Null
                    $rollbackLines.Add(' exit') | Out-Null
                    $rollbackLines.Add('') | Out-Null
                }

                continue
            }

            $srcCfgLinesRaw = @()
            try { $srcCfgLinesRaw = script:Split-ConfigLines -ConfigText ('' + $srcBaseline.Config) } catch { $srcCfgLinesRaw = @() }
            $dstCfgLinesRaw = @()
            try { $dstCfgLinesRaw = script:Split-ConfigLines -ConfigText ('' + $dstBaseline.Config) } catch { $dstCfgLinesRaw = @() }

            $applyLines = script:Get-ConfigLinesForApply -ConfigLines $srcCfgLinesRaw -Vendor $vendorKey

            $enableAtEnd = $true
            if ($vendorKey -eq 'Cisco') {
                $enableAtEnd = script:Get-CiscoAdminEnabled -ConfigLines $srcCfgLinesRaw
            } else {
                $statusText = ''
                try { $statusText = '' + $srcBaseline.Status } catch { $statusText = '' }
                $enableAtEnd = script:Get-BrocadeAdminEnabled -Status $statusText
            }

            if ($vendorKey -eq 'Cisco') {
                $changeLines.Add(("! Move {0} -> {1}" -f $src, $dst)) | Out-Null
                $changeLines.Add(("default interface {0}" -f $dst)) | Out-Null
                $changeLines.Add(("interface {0}" -f $dst)) | Out-Null
                $changeLines.Add(' shutdown') | Out-Null
                foreach ($cmd in $applyLines) { $changeLines.Add((' ' + $cmd)) | Out-Null }
                $changeLines.Add((' ' + (script:Get-CiscoDescriptionCommand -Label $newLabel))) | Out-Null
                if ($enableAtEnd) { $changeLines.Add(' no shutdown') | Out-Null }
                $changeLines.Add('exit') | Out-Null
                $changeLines.Add('') | Out-Null
            } else {
                $ifaceSpec = script:Get-BrocadeInterfaceSpec -Port $dst
                $changeLines.Add(("! Move {0} -> {1}" -f $src, $dst)) | Out-Null
                $changeLines.Add(("interface {0}" -f $ifaceSpec)) | Out-Null
                $changeLines.Add(' disable') | Out-Null
                $changeLines.Add(' no port-name') | Out-Null
                $resetNo = script:Get-BrocadeResetNoLines -TargetConfigLines $dstCfgLinesRaw -DesiredConfigLines $applyLines
                foreach ($cmd in $resetNo) { $changeLines.Add((' ' + $cmd)) | Out-Null }
                foreach ($cmd in $applyLines) { $changeLines.Add((' ' + $cmd)) | Out-Null }
                $changeLines.Add((' ' + (script:Get-BrocadePortNameCommand -Label $newLabel))) | Out-Null
                if ($enableAtEnd) { $changeLines.Add(' enable') | Out-Null }
                $changeLines.Add(' exit') | Out-Null
                $changeLines.Add('') | Out-Null
            }

            # Rollback: restore the destination port's original configuration and label.
            $dstApplyLines = script:Get-ConfigLinesForApply -ConfigLines $dstCfgLinesRaw -Vendor $vendorKey

            $dstEnableAtEnd = $true
            if ($vendorKey -eq 'Cisco') {
                $dstEnableAtEnd = script:Get-CiscoAdminEnabled -ConfigLines $dstCfgLinesRaw
            } else {
                $dstStatusText = ''
                try { $dstStatusText = '' + $dstBaseline.Status } catch { $dstStatusText = '' }
                $dstEnableAtEnd = script:Get-BrocadeAdminEnabled -Status $dstStatusText
            }

            if ($vendorKey -eq 'Cisco') {
                $rollbackLines.Add(("! Restore {0}" -f $dst)) | Out-Null
                $rollbackLines.Add(("default interface {0}" -f $dst)) | Out-Null
                $rollbackLines.Add(("interface {0}" -f $dst)) | Out-Null
                $rollbackLines.Add(' shutdown') | Out-Null
                foreach ($cmd in $dstApplyLines) { $rollbackLines.Add((' ' + $cmd)) | Out-Null }
                $rollbackLines.Add((' ' + (script:Get-CiscoDescriptionCommand -Label $rollbackLabel))) | Out-Null
                if ($dstEnableAtEnd) { $rollbackLines.Add(' no shutdown') | Out-Null }
                $rollbackLines.Add('exit') | Out-Null
                $rollbackLines.Add('') | Out-Null
            } else {
                $ifaceSpec = script:Get-BrocadeInterfaceSpec -Port $dst
                $rollbackLines.Add(("! Restore {0}" -f $dst)) | Out-Null
                $rollbackLines.Add(("interface {0}" -f $ifaceSpec)) | Out-Null
                $rollbackLines.Add(' disable') | Out-Null
                $rollbackLines.Add(' no port-name') | Out-Null
                $resetNo = script:Get-BrocadeResetNoLines -TargetConfigLines $applyLines -DesiredConfigLines $dstApplyLines
                foreach ($cmd in $resetNo) { $rollbackLines.Add((' ' + $cmd)) | Out-Null }
                foreach ($cmd in $dstApplyLines) { $rollbackLines.Add((' ' + $cmd)) | Out-Null }
                $rollbackLines.Add((' ' + (script:Get-BrocadePortNameCommand -Label $rollbackLabel))) | Out-Null
                if ($dstEnableAtEnd) { $rollbackLines.Add(' enable') | Out-Null }
                $rollbackLines.Add(' exit') | Out-Null
                $rollbackLines.Add('') | Out-Null
            }
        }
    }

    $changeLines.Add('end') | Out-Null
    $rollbackLines.Add('end') | Out-Null

    return [PSCustomObject]@{
        Vendor         = $vendorKey
        ChangeScript   = $changeLines.ToArray()
        RollbackScript = $rollbackLines.ToArray()
        AffectedPorts  = $targetOrder
    }
}

Export-ModuleMember -Function Get-PortReorgSuggestedPlan, New-PortReorgScripts
