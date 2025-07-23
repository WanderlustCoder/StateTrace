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

function Initialize-Directories {
    param ([string[]]$Paths)
    foreach ($path in $Paths) {
        if (-not (Test-Path $path)) {
            New-Item -ItemType Directory -Path $path | Out-Null
        }
    }
}

function Split-RawLogs {
    Get-ChildItem $logPath -File | Where-Object {
        $_.Extension -in '.log', '.txt'
    } | ForEach-Object {
        $lines = Get-Content $_.FullName
        $hostMarkers = @()

        # Step 1: Find all hostnames in "hostname <name>"
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^\s*hostname\s+(\S+)\s*$') {
                $hostname = $Matches[1]
                $promptPatterns = @("SSH@${hostname}#", "${hostname}#")

                foreach ($pattern in $promptPatterns) {
                    for ($j = 0; $j -lt $lines.Count; $j++) {
                        if ($lines[$j] -match "^\s*$([regex]::Escape($pattern))") {
                            $hostMarkers += [PSCustomObject]@{
                                Hostname = $hostname
                                Index    = $j
                            }
                            break
                        }
                    }

                    if ($hostMarkers.Count -gt 0 -and $hostMarkers[-1].Hostname -eq $hostname) { break }
                }
            }
        }

        if ($hostMarkers.Count -eq 0) {
            Write-Warning "No host markers found in $($_.Name)"
            return
        }

        # Step 2: Sort by index and extract
        $hostMarkers = $hostMarkers | Sort-Object Index

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
            $slice | Set-Content $outPath
        }
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
        [int]$MaxThreads = 20
    )

    $sessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $runspacePool = [runspacefactory]::CreateRunspacePool(1, $MaxThreads, $sessionState, $Host)
    $runspacePool.Open()
    $runspaces = @()

    foreach ($file in $DeviceFiles) {
        $ps = [powershell]::Create()
        $ps.RunspacePool = $runspacePool

        $ps.AddScript({
            param($filePath, $modulesPath, $outputPath, $archiveRoot)

            Import-Module (Join-Path $modulesPath "AristaModule.psm1") -Force
            Import-Module (Join-Path $modulesPath "CiscoModule.psm1") -Force
            Import-Module (Join-Path $modulesPath "BrocadeModule.psm1") -Force
            Import-Module (Join-Path $modulesPath "ParserWorker.psm1") -Force

            Invoke-DeviceLogParsing -FilePath $filePath -OutputPath $outputPath -ArchiveRoot $archiveRoot
        }).AddArgument($file).AddArgument($modulesPath).AddArgument($outputPath).AddArgument($archiveRoot)

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

function Cleanup-ExtractedLogs {
    Get-ChildItem $extractedPath -File | Remove-Item -Force
}

# --- Entry Point ---
Initialize-Directories @($logPath, $outputPath, $extractedPath, $archiveRoot)
Import-ParserModules
Split-RawLogs

$deviceFiles = Get-ChildItem $extractedPath -File | Select-Object -ExpandProperty FullName
Write-Host "Processing $($deviceFiles.Count) logs in parallel..."

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$threadCount = [Math]::Min(20, [Environment]::ProcessorCount * 2)
Start-ParallelDeviceProcessing -DeviceFiles $deviceFiles -MaxThreads $threadCount
$sw.Stop()

Write-Host "Processing complete in $($sw.Elapsed.TotalSeconds) seconds."
Cleanup-ExtractedLogs