if (-not (Get-Variable -Name StateTraceDebug -Scope Global -ErrorAction SilentlyContinue)) {
    Set-Variable -Scope Global -Name StateTraceDebug -Value $false -Option None
}

function New-Directories {
    param ([string[]]$Paths)
    foreach ($path in $Paths) {
        if (-not (Test-Path $path)) {
            New-Item -ItemType Directory -Path $path | Out-Null
        }
    }
}

function Invoke-StateTraceParsing {
    [CmdletBinding()]
    param(
        [string]$DatabasePath,
        [switch]$Synchronous
    )
    # Determine project root based on the module's location.  $PSScriptRoot is
    # Resolve the project root once using .NET methods.  Using Resolve-Path in a
    # pipeline can be expensive; GetFullPath computes the absolute path to the
    # parent directory without invoking the pipeline.
    try {
        $projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    } catch {
        $projectRoot = (Split-Path -Parent $PSScriptRoot)
    }
    $logPath       = Join-Path $projectRoot 'Logs'
    $extractedPath = Join-Path $logPath 'Extracted'
    $modulesPath   = Join-Path $projectRoot 'Modules'
    $archiveRoot   = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'SwitchArchives'

    New-Directories @($logPath, $extractedPath, $archiveRoot)
    LogIngestionModule\Split-RawLogs -LogPath $logPath -ExtractedPath $extractedPath

    $deviceFiles = @(Get-ChildItem -Path $extractedPath -File | Select-Object -ExpandProperty FullName)
    if ($deviceFiles.Count -gt 0) {
        Write-Host "Extracted $($deviceFiles.Count) device log file(s) to process:" -ForegroundColor Yellow
        foreach ($dev in $deviceFiles) {
            Write-Host "  - $dev" -ForegroundColor Yellow
        }
    } else {
        Write-Warning "No device logs were extracted; the parser will not run."
    }

    $threadCount = [Math]::Min(8, [Environment]::ProcessorCount)

    $dbPath = $null
    if ($PSBoundParameters.ContainsKey('DatabasePath') -and $DatabasePath) {
        $dbPath = $DatabasePath
    }

    $jobsParams = @{
        DeviceFiles = $deviceFiles
        MaxThreads  = $threadCount
        DatabasePath = $dbPath
        ModulesPath = $modulesPath
        ArchiveRoot = $archiveRoot
    }
    if ($Synchronous) { $jobsParams.Synchronous = $true }

    if ($deviceFiles.Count -gt 0) {
        $mode = if ($Synchronous) { "synchronously" } else { "in parallel" }
        Write-Host "Processing $($deviceFiles.Count) logs $mode..." -ForegroundColor Yellow
        ParserRunspaceModule\Invoke-DeviceParsingJobs @jobsParams
    }

    LogIngestionModule\Clear-ExtractedLogs -ExtractedPath $extractedPath
    Write-Host "Processing complete." -ForegroundColor Yellow
}
