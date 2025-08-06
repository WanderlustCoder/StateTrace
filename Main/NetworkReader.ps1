# NetworkReader.ps1

# Set script-relative root path
$scriptRoot     = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot    = Join-Path $scriptRoot ".." | Resolve-Path

# Paths
$logPath        = Join-Path $projectRoot "Logs"
$extractedPath  = Join-Path $logPath "Extracted"
$outputPath     = Join-Path $projectRoot "ParsedData"
$modulesPath    = Join-Path $projectRoot "Modules"
$archiveRoot    = Join-Path ([Environment]::GetFolderPath("MyDocuments")) "SwitchArchives"

# -----------------------------------------------------------------------------
# Import archive data from previously parsed logs.
# When requested via environment variables, this helper copies data from
# $ArchiveRoot into the current $outputPath.  By default only the most
# recent archive per device is imported; when IncludeHistorical is true,
# multiple dated archives are copied, each with the date appended to the
# filename so they can be distinguished.  Existing files in $outputPath
# will be overwritten.
function Import-ArchiveData {
    <#
        This helper previously copied CSV archives from past parsed runs into the
        ParsedData folder.  With the migration away from CSV files toward a
        database back‑end, importing CSV archives is no longer necessary.  The
        function is retained for backward compatibility but now performs no
        actions beyond logging a debug message.  The parameters are still
        accepted to avoid breaking callers, but they are ignored.

        .PARAMETER ArchiveRoot
            Ignored.  Previously the root directory containing per‑device
            subfolders of archived CSVs.

        .PARAMETER OutputPath
            Ignored.  Previously the destination folder for imported CSVs.

        .PARAMETER IncludeHistorical
            Ignored.  Whether to import all dated archives or only the most
            recent one.  Has no effect now that CSV imports are disabled.
    #>
    param(
        [string]$ArchiveRoot,
        [string]$OutputPath,
        [bool]$IncludeHistorical
    )
    Write-Host "[DEBUG] Import-ArchiveData called – CSV archive import has been disabled. Using database storage instead." -ForegroundColor DarkYellow
    return
}

function New-Directories {
    param ([string[]]$Paths)
    foreach ($path in $Paths) {
        if (-not (Test-Path $path)) {
            Write-Host "Creating directory '$path'"
            New-Item -ItemType Directory -Path $path | Out-Null
        }
    }
}

function Split-RawLogs {
    Write-Host "Split-RawLogs: scanning directory '$logPath' for .log and .txt files..."
    Write-Host "NetworkReader debug: starting log extraction with detailed tracing"
    # Gather a list of candidate raw log files first so we can report how many we'll process.
    # Also report which files are included or skipped based on their extension to aid debugging.
    $allFiles = Get-ChildItem $logPath -File
    foreach ($f in $allFiles) {
        # Normalize extension to lowercase for comparison
        $ext = $f.Extension.ToLowerInvariant()
        if ($ext -in '.log', '.txt') {
            Write-Host "Including file for processing: $($f.FullName)"
        } else {
            Write-Host "Skipping file due to unsupported extension '$($f.Extension)': $($f.FullName)"
        }
    }
    $rawFiles = $allFiles | Where-Object {
        # Only consider plain text log types (.log, .txt), case-insensitive
        $ext = $_.Extension.ToLowerInvariant()
        $ext -in '.log', '.txt'
    }
    Write-Host "Found $($rawFiles.Count) raw log file(s) to process."

    foreach ($file in $rawFiles) {
        Write-Host "\n--- Processing file: $($file.FullName) ---"
        Write-Host "Reading file: $($file.FullName)"
        $lines = Get-Content $file.FullName
        Write-Host "Loaded $($lines.Count) lines from '$($file.Name)'"
        $hostMarkers = @()

        # Step 1: Find all hostnames in the file.  Use a case-insensitive match for the
        # "hostname <name>" line and search prompts case-insensitively as well.  If no
        # corresponding prompt is found, fall back to using the beginning of the file.
        Write-Host "Searching for hostnames in '$($file.Name)'..."
        for ($i = 0; $i -lt $lines.Count; $i++) {
            # Use case-insensitive matching to capture 'hostname' regardless of case
            if ($lines[$i] -match '(?i)^\s*hostname\s+(\S+)\s*$') {
                $hostname = $Matches[1]
                Write-Host "Detected hostname '$hostname' at line $i"
                $promptPatterns = @("SSH@${hostname}#", "${hostname}#")

                $foundPromptForHost = $false
                # Search the entire file for the earliest prompt that matches either pattern
                for ($j = 0; $j -lt $lines.Count; $j++) {
                    foreach ($pattern in $promptPatterns) {
                        # Perform case-insensitive match and escape special characters
                        $regex = "(?i)^\s*$([regex]::Escape($pattern))"
                        if ($lines[$j] -match $regex) {
                            Write-Host "    Found prompt '$pattern' at line $j"
                            $hostMarkers += [PSCustomObject]@{
                                Hostname = $hostname
                                Index    = $j
                            }
                            $foundPromptForHost = $true
                            break
                        }
                    }
                    if ($foundPromptForHost) { break }
                }

                if (-not $foundPromptForHost) {
                    Write-Host "  No prompt found for hostname '$hostname', defaulting to start of file"
                    # Default to index 0 if no prompt is found; extract the entire file for this host
                    $hostMarkers += [PSCustomObject]@{
                        Hostname = $hostname
                        Index    = 0
                    }
                }
            }
        }

        if ($hostMarkers.Count -eq 0) {
            # Skip this file but continue processing others if no host markers were found
            Write-Warning "No host markers found in $($file.Name). Skipping this file."
            continue
        }

        # Output diagnostic information about discovered host markers
        $markerStrings = $hostMarkers | ForEach-Object { "$($_.Hostname)@$($_.Index)" }
        $markerSummary = $markerStrings -join ', '
        Write-Host "Host markers for '$($file.Name)': $markerSummary"
        Write-Host "Total host markers found in '$($file.Name)': $($hostMarkers.Count)"

        # Step 2: Sort by index and extract.  If there is only one host marker, write the
        # entire file instead of slicing based on prompt index.  This avoids missing
        # extraction when the prompt appears before the hostname line or whitespace issues.
        # Sort the host markers by the index of the prompt.  Use the unary array
        # operator @() around the pipeline so that when there is only a single
        # element the result is still an array. Without this, PowerShell will
        # unwrap a single PSCustomObject and the `.Count` property will refer
        # to the number of properties on the object (or be `$null`) rather than
        # the number of elements, causing the single-host branch to never
        # trigger. Wrapping in @() ensures `$hostMarkers.Count` reflects the
        # number of markers found.
        $hostMarkers = @($hostMarkers | Sort-Object Index)

        if ($hostMarkers.Count -eq 1) {
            $singleHost = $hostMarkers[0].Hostname
            $safeSingleHost = $singleHost -replace '[\\\/:\*\?"<>\|]', '_'
            $outPathSingle = Join-Path $extractedPath "$safeSingleHost.log"
            Write-Host "Single-host file detected. Writing entire file for host '$safeSingleHost' to '$outPathSingle' (total $($lines.Count) lines)"
            $lines | Set-Content $outPathSingle
            if (Test-Path $outPathSingle) {
                Write-Host "Successfully wrote file: $outPathSingle"
            } else {
                Write-Warning "Failed to write file: $outPathSingle"
            }
            Write-Host "Finished processing single-host file '$($file.Name)'"
            continue
        }

        Write-Host "Multi-host file detected. Writing slices for each host."

        for ($k = 0; $k -lt $hostMarkers.Count; $k++) {
            $start = $hostMarkers[$k].Index
            $end   = if ($k -lt $hostMarkers.Count - 1) {
                $hostMarkers[$k + 1].Index - 1
            } else {
                $lines.Count - 1
            }

            $slice = $lines[$start..$end]
            $safeHost = $hostMarkers[$k].Hostname -replace '[\\\/:\*\?"<>\|]', '_'
            $outPath = Join-Path $extractedPath "$safeHost.log"
            Write-Host "  Preparing slice for host '$safeHost': lines $start..$end (total $($slice.Count))"
            Write-Host "  Writing to: $outPath"
            $slice | Set-Content $outPath
            if (Test-Path $outPath) {
                Write-Host "  Successfully wrote file: $outPath"
            } else {
                Write-Warning "  Failed to write file: $outPath"
            }
        }
        Write-Host "Finished processing multi-host file '$($file.Name)'"
    }
}


function Import-ParserModules {
    Import-Module (Join-Path $modulesPath "AristaModule.psm1") -Force
    Import-Module (Join-Path $modulesPath "CiscoModule.psm1") -Force
    Import-Module (Join-Path $modulesPath "BrocadeModule.psm1") -Force
    Import-Module (Join-Path $modulesPath "ParserWorker.psm1") -Force
}

function Start-ParallelDeviceProcessing {
    param (
        [string[]]$DeviceFiles,
        [int]$MaxThreads = 20,
        [string]$DatabasePath
    )

    $sessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $runspacePool = [runspacefactory]::CreateRunspacePool(1, $MaxThreads, $sessionState, $Host)
    $runspacePool.Open()
    $runspaces = @()

    foreach ($file in $DeviceFiles) {
        $ps = [powershell]::Create()
        $ps.RunspacePool = $runspacePool

        $ps.AddScript({
            param($filePath, $modulesPath, $outputPath, $archiveRoot, $dbPath)

            Import-Module (Join-Path $modulesPath "AristaModule.psm1") -Force
            Import-Module (Join-Path $modulesPath "CiscoModule.psm1") -Force
            Import-Module (Join-Path $modulesPath "BrocadeModule.psm1") -Force
            Import-Module (Join-Path $modulesPath "ParserWorker.psm1") -Force
            # Import the database module if a path was provided.  Use -Global so
            # that its commands (Invoke-DbQuery/Invoke-DbNonQuery) are visible in this runspace.
            if ($dbPath -and (Test-Path (Join-Path $modulesPath "DatabaseModule.psm1"))) {
                Import-Module (Join-Path $modulesPath "DatabaseModule.psm1") -Force -Global
            }
            Invoke-DeviceLogParsing -FilePath $filePath -OutputPath $outputPath -ArchiveRoot $archiveRoot -DatabasePath $dbPath
        }).AddArgument($file).AddArgument($modulesPath).AddArgument($outputPath).AddArgument($archiveRoot).AddArgument($DatabasePath)

        $runspaces += [PSCustomObject]@{
            Pipe = $ps
            AsyncResult = $ps.BeginInvoke()
        }
    }

    foreach ($r in $runspaces) {
        $r.Pipe.EndInvoke($r.AsyncResult)
        $r.Pipe.Dispose()
    }

    $runspacePool.Close()
    $runspacePool.Dispose()
}

function Clear-ExtractedLogs {
    Get-ChildItem $extractedPath -File | Remove-Item -Force
}

# --- Entry Point ---
New-Directories @($logPath, $outputPath, $extractedPath, $archiveRoot)
Import-ParserModules
Split-RawLogs

$deviceFiles = Get-ChildItem $extractedPath -File | Select-Object -ExpandProperty FullName
if ($deviceFiles.Count -gt 0) {
    Write-Host "Extracted $($deviceFiles.Count) device log file(s) to process:"
    foreach ($dev in $deviceFiles) {
        Write-Host "  - $dev"
    }
} else {
    Write-Warning "No device logs were extracted; the parser will not run."
}
Write-Host "Processing $($deviceFiles.Count) logs in parallel..."

$sw = [System.Diagnostics.Stopwatch]::StartNew()
<#
Throttle the number of runspaces used for parallel parsing.  While the system
could theoretically spawn many runspaces (ProcessorCount*2), doing so can
oversubscribe CPU cores and degrade I/O performance.  Use a conservative
upper bound of 8 runspaces or the number of available cores, whichever is
smaller.  This aligns with the performance plan guidance to limit
concurrency to around 4–8 threads.
#>
$threadCount = [Math]::Min(8, [Environment]::ProcessorCount)
# Pass along the database path if available via environment variable or global variable.  When
# invoked from the GUI, $env:StateTraceDbPath may be set; otherwise fall back to the
# globally defined StateTraceDb variable from MainWindow.
$dbPath = $null
if ($env:StateTraceDbPath -and $env:StateTraceDbPath -ne '') {
    $dbPath = $env:StateTraceDbPath
} elseif ($global:StateTraceDb) {
    $dbPath = $global:StateTraceDb
}
Start-ParallelDeviceProcessing -DeviceFiles $deviceFiles -MaxThreads $threadCount -DatabasePath $dbPath
$sw.Stop()

Write-Host "Processing complete in $($sw.Elapsed.TotalSeconds) seconds."
Clear-ExtractedLogs

# Optionally import archive data.  Use environment variables set by the
# calling process (MainWindow) to determine whether to import the most
# recent archive or include historical archives.  These variables are
# expected to be simple strings (e.g. 'true' or empty).
if ($env:IncludeArchive -and $env:IncludeArchive -ne '') {
    $includeHistFlag = $false
    if ($env:IncludeHistorical -and $env:IncludeHistorical -ne '') { $includeHistFlag = $true }
    try {
        Write-Host "Importing archive data (Historical: $includeHistFlag) from $archiveRoot"
        Import-ArchiveData -ArchiveRoot $archiveRoot -OutputPath $outputPath -IncludeHistorical:$includeHistFlag
    } catch {
        Write-Warning "Failed to import archive data: $($_.Exception.Message)"
    }
}