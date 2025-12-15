Set-StrictMode -Version Latest

function Split-RawLogs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$LogPath,
        [Parameter(Mandatory=$true)][string]$ExtractedPath
    )

    New-Item -ItemType Directory -Force -Path $ExtractedPath | Out-Null

    # Start with a clean extracted directory so leftover slices from a prior run
    # cannot be appended into the current parsing session.
    Clear-ExtractedLogs -ExtractedPath $ExtractedPath

    # Build a strongly typed list of raw log files.  Avoid the Where-Object
    # pipeline when filtering by extension to reduce overhead when many files
    # are present.  Filter in a foreach loop instead of piping into a
    # Where-Object script block.  This approach also maintains the original
    # order of files returned by Get-ChildItem.
    $rawFiles = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    foreach ($f in Get-ChildItem -Path $LogPath -File) {
        # Skip warm-run telemetry helper transcripts/logs; they are for regression output and can remain locked.
        if ($f.Name -like 'WarmRunTelemetry-*') {
            Write-Host ("Skipping helper artifact '{0}'." -f $f.FullName)
            continue
        }
        # Match .log or .txt extensions (case-insensitive) using a compiled regex
        if ($f.Extension -match '^(?i)\.(log|txt)$') {
            [void]$rawFiles.Add($f)
        }
    }
    Write-Host "Split-RawLogs (streaming): found $($rawFiles.Count) file(s) in '$LogPath'."

    $reHostname = [regex]::new('(?i)^\s*hostname\s+(\S+)\s*$', 'Compiled')
    # Detect host prompts even when commands follow and when config contexts are present
    $rePrompt   = [regex]::new('(?i)^\s*(?:SSH@)?([^(#>\s]+)(?:\([^)]*\))?\s*[#>]', 'Compiled')

    foreach ($file in $rawFiles) {
        Write-Host "`n--- Streaming file: $($file.FullName) ---"

        $sr = $null
        $writer = $null
        $unknownWriter = $null
        $currentHost = $null

        $buffer = [System.Collections.Generic.List[string]]::new()
        $bufferLimit = 4000

        try {
            $sr = [System.IO.StreamReader]::new($file.FullName)

            while (-not $sr.EndOfStream) {
                $line = $sr.ReadLine()

                $mPrompt = $rePrompt.Match($line)
                $mHost   = $reHostname.Match($line)

                $detected = $null
                if ($mPrompt.Success) {
                    $detected = $mPrompt.Groups[1].Value
                } elseif ($mHost.Success) {
                    $detected = $mHost.Groups[1].Value
                }

                if ($detected) {
                    if (-not $currentHost -or $detected -ne $currentHost) {
                        if ($null -ne $writer) {
                            try { $writer.Flush() } catch { }
                            $writer.Dispose()
                        }

                        $safe = ($detected -replace '[\\/:*?"<>|]', '_')
                        $outPath = Join-Path $ExtractedPath "$safe.log"
                        $fs = [System.IO.File]::Open($outPath,
                            [System.IO.FileMode]::Append,
                            [System.IO.FileAccess]::Write,
                            [System.IO.FileShare]::Read)
                        $writer = New-Object System.IO.StreamWriter($fs)
                        $writer.AutoFlush = $false
                        $currentHost = $detected
                        Write-Host "Writing slice for host '$currentHost' -> $outPath"

                        if ($buffer.Count -gt 0) {
                            foreach ($b in $buffer) { $writer.WriteLine($b) }
                            $buffer.Clear()
                        }
                    }
                }

                if ($writer -ne $null) {
                    $writer.WriteLine($line)
                } else {
                    if ($buffer.Count -lt $bufferLimit) {
                        $buffer.Add($line) | Out-Null
                    } else {
                        if ($null -eq $unknownWriter) {
                            $uPath = Join-Path $ExtractedPath "_unknown.log"
                            $ufs = [System.IO.File]::Open($uPath,
                                [System.IO.FileMode]::Append,
                                [System.IO.FileAccess]::Write,
                                [System.IO.FileShare]::Read)
                            $unknownWriter = New-Object System.IO.StreamWriter($ufs)
                            $unknownWriter.AutoFlush = $false
                            Write-Host "No host detected yet; spilling overflow to $uPath"
                        }
                        $unknownWriter.WriteLine($line)
                    }
                }
            }

            if ($buffer.Count -gt 0) {
                if ($null -eq $writer) {
                    $uPath = Join-Path $ExtractedPath "_unknown.log"
                    $ufs = [System.IO.File]::Open($uPath,
                        [System.IO.FileMode]::Append,
                        [System.IO.FileAccess]::Write,
                        [System.IO.FileShare]::Read)
                    $uw = New-Object System.IO.StreamWriter($ufs)
                    $uw.AutoFlush = $false
                    foreach ($b in $buffer) { $uw.WriteLine($b) }
                    try { $uw.Flush() } catch { }
                    $uw.Dispose()
                    Write-Host "Completed file without detecting a host; wrote buffered content to $uPath"
                } else {
                    foreach ($b in $buffer) { $writer.WriteLine($b) }
                }
                $buffer.Clear()
            }
        }
        finally {
            if ($writer) {
                try { $writer.Flush() } catch { }
                $writer.Dispose()
            }
            if ($unknownWriter) {
                try { $unknownWriter.Flush() } catch { }
                $unknownWriter.Dispose()
            }
            if ($sr) { $sr.Dispose() }
        }
    }

    Write-Host "Split-RawLogs (streaming): complete."
}

function Clear-ExtractedLogs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$ExtractedPath
    )

    if ([string]::IsNullOrWhiteSpace($ExtractedPath)) { return }
    if (-not (Test-Path -LiteralPath $ExtractedPath)) { return }

    try {
        Get-ChildItem -LiteralPath $ExtractedPath -File -ErrorAction SilentlyContinue |
            Remove-Item -Force -ErrorAction SilentlyContinue
    } catch { }
}

Export-ModuleMember -Function Split-RawLogs, Clear-ExtractedLogs
