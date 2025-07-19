# NetworkReader.ps1

# Paths
$scriptRoot    = $PSScriptRoot
$logPath       = Join-Path $scriptRoot "Logs"
$outputPath    = Join-Path $scriptRoot "ParsedData"
$modulesPath   = Join-Path $scriptRoot "Modules"
$extractedPath = Join-Path $logPath "Extracted"
$archiveRoot   = Join-Path ([Environment]::GetFolderPath("MyDocuments")) "SwitchArchives"

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
        $_.Extension -in '.log', '.txt' -and $_.Name -notlike '*Extracted*'
    } | ForEach-Object {
        $lines = Get-Content $_.FullName
        $currentHost = $null
        $currentLog = @()

        foreach ($line in $lines) {
            if ($line -match '\b([A-Z0-9]{4}-[A-Z]\d{2}-[A-Z]{2}-\d{2,3})\b') {
                $newHost = $Matches[1]

                if ($currentHost -and $newHost -ne $currentHost) {
                    $safeHost = $currentHost -replace '[\\\/:\*\?"<>\|]', '_'
                    $outFile = Join-Path $extractedPath "$safeHost.log"
                    $currentLog | Set-Content $outFile
                    $currentLog = @()
                }

                $currentHost = $newHost
            }

            if ($currentHost) {
                $currentLog += $line
            }
        }

        if ($currentHost -and $currentLog.Count -gt 0) {
            $safeHost = $currentHost -replace '[\\\/:\*\?"<>\|]', '_'
            $outFile = Join-Path $extractedPath "$safeHost.log"
            $currentLog | Set-Content $outFile
        }
    }
}

function Import-ParserModules {
    Import-Module "$modulesPath\AristaModule.psm1" -Force
    Import-Module "$modulesPath\CiscoModule.psm1" -Force
    Import-Module "$modulesPath\BrocadeModule.psm1" -Force
    Import-Module "$modulesPath\ParserWorker.psm1" -Force
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

            Import-Module "$modulesPath\AristaModule.psm1" -Force
            Import-Module "$modulesPath\CiscoModule.psm1" -Force
            Import-Module "$modulesPath\BrocadeModule.psm1" -Force
            Import-Module "$modulesPath\ParserWorker.psm1" -Force

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

# Entry point
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
