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
            Write-Verbose ("Skipping helper artifact '{0}'." -f $f.FullName)
            continue
        }
        # Match .log or .txt extensions (case-insensitive)
        if ($f.Extension -imatch '^\.(log|txt)$') {
            [void]$rawFiles.Add($f)
        }
    }
    Write-Verbose "Split-RawLogs (streaming): found $($rawFiles.Count) file(s) in '$LogPath'."

    $reHostname = [regex]::new('(?i)^\s*hostname\s+(\S+)\s*$', 'Compiled')
    # Detect host prompts even when commands follow and when config contexts are present
    $rePrompt   = [regex]::new('(?i)^\s*(?:SSH@)?([^(#>\s]+)(?:\([^)]*\))?\s*[#>]', 'Compiled')

    foreach ($file in $rawFiles) {
        Write-Verbose ("--- Streaming file: {0} ---" -f $file.FullName)

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
                    if (-not $currentHost -or -not [string]::Equals($detected, $currentHost, [System.StringComparison]::OrdinalIgnoreCase)) {
                        if ($null -ne $writer) {
                            try { $writer.Flush() } catch { Write-Verbose "[LogIngestion] Writer flush failed: $_" }
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
                        Write-Verbose ("Writing slice for host '{0}' -> {1}" -f $currentHost, $outPath)

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
                            Write-Verbose ("No host detected yet; spilling overflow to {0}" -f $uPath)
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
                    try { $uw.Flush() } catch { Write-Verbose "[LogIngestion] Unknown host writer flush failed: $_" }
                    $uw.Dispose()
                    Write-Warning ("Completed file without detecting a host; wrote buffered content to {0}" -f $uPath)
                } else {
                    foreach ($b in $buffer) { $writer.WriteLine($b) }
                }
                $buffer.Clear()
            }
        }
        finally {
            if ($writer) {
                try { $writer.Flush() } catch { Write-Verbose "Caught exception in LogIngestionModule.psm1: $($_.Exception.Message)" }
                $writer.Dispose()
            }
            if ($unknownWriter) {
                try { $unknownWriter.Flush() } catch { Write-Verbose "Caught exception in LogIngestionModule.psm1: $($_.Exception.Message)" }
                $unknownWriter.Dispose()
            }
            if ($sr) { $sr.Dispose() }
        }
    }

    Write-Verbose "Split-RawLogs (streaming): complete."
}

function Clear-ExtractedLogs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$ExtractedPath
    )

    if ([string]::IsNullOrWhiteSpace($ExtractedPath)) { return }
    if (-not (Test-Path -LiteralPath $ExtractedPath)) { return }

    $resolvedExtractedPath = $null
    try { $resolvedExtractedPath = [System.IO.Path]::GetFullPath($ExtractedPath) } catch { $resolvedExtractedPath = $null }
    if ($resolvedExtractedPath) {
        $rootPath = $null
        try { $rootPath = [System.IO.Path]::GetPathRoot($resolvedExtractedPath) } catch { $rootPath = $null }
        if ($rootPath -and [System.StringComparer]::OrdinalIgnoreCase.Equals($resolvedExtractedPath.TrimEnd('\'), $rootPath.TrimEnd('\'))) {
            Write-Warning ("Extracted log cleanup skipped for root path '{0}'." -f $resolvedExtractedPath)
            return
        }

        $leafName = [System.IO.Path]::GetFileName($resolvedExtractedPath.TrimEnd('\'))
        if ([string]::IsNullOrWhiteSpace($leafName) -or -not $leafName.StartsWith('Extracted', [System.StringComparison]::OrdinalIgnoreCase)) {
            Write-Warning ("Extracted log cleanup skipped for unexpected path '{0}'." -f $resolvedExtractedPath)
            return
        }
    }

    try {
        Get-ChildItem -LiteralPath $ExtractedPath -File -ErrorAction SilentlyContinue |
            Remove-Item -Force -ErrorAction SilentlyContinue
    } catch { Write-Verbose "[LogIngestion] Clear extracted logs failed: $_" }
}

Export-ModuleMember -Function Split-RawLogs, Clear-ExtractedLogs
