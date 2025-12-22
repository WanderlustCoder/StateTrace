Set-StrictMode -Version Latest

function Read-ToolingJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$Label = 'JSON',
        [scriptblock]$FilterScript,
        [int]$LineProbeLimit = 10,
        [int]$MaxRawBytes = 52428800
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw ("{0} file '{1}' does not exist." -f $Label, $Path)
    }

    $resolved = Resolve-Path -LiteralPath $Path -ErrorAction Stop | Select-Object -First 1
    $resolvedPath = $resolved.Path

    $parsed = New-Object System.Collections.Generic.List[object]
    $parseErrors = 0
    $parsedLines = 0
    $lineAttempts = 0

    foreach ($line in (Get-Content -LiteralPath $resolvedPath -ReadCount 1 -ErrorAction Stop)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $lineAttempts++
        try {
            $obj = $line | ConvertFrom-Json -ErrorAction Stop
            $isCustom = $false
            try {
                $isCustom = $obj -and $obj.PSObject -and ($obj.PSObject.TypeNames -contains 'System.Management.Automation.PSCustomObject')
            } catch {
                $isCustom = $false
            }
            $isDictionary = $obj -is [System.Collections.IDictionary]
            if ($isCustom -or $isDictionary) {
                $parsedLines++
                if (-not $FilterScript -or (& $FilterScript $obj)) {
                    $null = $parsed.Add($obj)
                }
            }
        } catch {
            $parseErrors++
            if ($parseErrors -le 3) {
                Write-Verbose ("[{0}] Skipping invalid JSON line: {1}" -f $Label, $_.Exception.Message)
            }
        }
        if ($parsedLines -eq 0 -and $lineAttempts -ge $LineProbeLimit) {
            break
        }
    }

    if ($parsedLines -gt 0) {
        if ($parseErrors -gt 0) {
            Write-Warning ("[{0}] Skipped {1} invalid JSON line(s) in {2}" -f $Label, $parseErrors, $resolvedPath)
        }
        return $parsed.ToArray()
    }

    $fileInfo = Get-Item -LiteralPath $resolvedPath -ErrorAction Stop
    if ($MaxRawBytes -gt 0 -and $fileInfo.Length -gt $MaxRawBytes) {
        $sizeMb = [math]::Round(($fileInfo.Length / 1MB), 2)
        $limitMb = [math]::Round(($MaxRawBytes / 1MB), 2)
        Write-Warning ("[{0}] Reading {1} MB JSON into memory (limit {2} MB). Consider trimming or emitting NDJSON for streaming." -f $Label, $sizeMb, $limitMb)
    }

    $rawJson = Get-Content -LiteralPath $resolvedPath -Raw -ErrorAction Stop
    $parsedRaw = $rawJson | ConvertFrom-Json -ErrorAction Stop
    if ($FilterScript) {
        if ($parsedRaw -is [System.Collections.IEnumerable] -and -not ($parsedRaw -is [string])) {
            $filtered = New-Object System.Collections.Generic.List[object]
            foreach ($item in $parsedRaw) {
                if (& $FilterScript $item) {
                    $null = $filtered.Add($item)
                }
            }
            return $filtered.ToArray()
        }

        if (& $FilterScript $parsedRaw) {
            return $parsedRaw
        }
        return @()
    }

    return $parsedRaw
}

Export-ModuleMember -Function Read-ToolingJson
