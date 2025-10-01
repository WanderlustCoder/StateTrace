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


function Get-DeviceLogSetStatistics {

    param([string[]]$DeviceFiles)

    $deviceCount = if ($DeviceFiles) { $DeviceFiles.Count } else { 0 }
    $siteCount = 0
    if ($deviceCount -gt 0) {
        $siteSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($pathValue in $DeviceFiles) {
            if ([string]::IsNullOrWhiteSpace($pathValue)) { continue }
            $name = [System.IO.Path]::GetFileNameWithoutExtension($pathValue)
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            $siteToken = $name
            $dashIndex = $name.IndexOf('-')
            if ($dashIndex -gt 0) { $siteToken = $name.Substring(0, $dashIndex) }
            if (-not [string]::IsNullOrWhiteSpace($siteToken)) {
                [void]$siteSet.Add($siteToken)
            }
        }
        $siteCount = $siteSet.Count
    }

    return [PSCustomObject]@{
        DeviceCount = [int][Math]::Max(0, $deviceCount)
        SiteCount   = [int][Math]::Max(0, $siteCount)
    }
}

function Get-AutoScaleConcurrencyProfile {

    [CmdletBinding()]

    param(

        [Parameter(Mandatory)][string[]]$DeviceFiles,

        [int]$CpuCount = 1,

        [int]$ThreadCeiling = 0,

        [int]$MaxWorkersPerSite = 0,

        [int]$MaxActiveSites = -1,

        [int]$JobsPerThread = 0,

        [int]$MinRunspaces = 1

    )



    $cpuCount = [Math]::Max(1, $CpuCount)

    $stats = Get-DeviceLogSetStatistics -DeviceFiles $DeviceFiles

    $deviceCount = $stats.DeviceCount

    $rawSiteCount = $stats.SiteCount

    $siteCount = if ($rawSiteCount -gt 0) { $rawSiteCount } else { 1 }



    $maxThreadBound = [Math]::Max(1, [Math]::Min($cpuCount * 2, [Math]::Max(1, $deviceCount)))

    $targetThreads = $ThreadCeiling

    if ($targetThreads -le 0) {

        $baseline = [Math]::Ceiling($cpuCount * 0.75)

        if ($deviceCount -gt 0) {

            $targetThreads = [Math]::Min($baseline, $deviceCount)

        } else {

            $targetThreads = $baseline

        }

    }

    $targetThreads = [Math]::Max(1, [Math]::Min($targetThreads, $maxThreadBound))



    $workersPerSite = $MaxWorkersPerSite

    if ($workersPerSite -le 0) {

        $workersPerSite = [Math]::Ceiling($targetThreads / [Math]::Max(1, $siteCount))

        if ($workersPerSite -lt 1) { $workersPerSite = 1 }

        if ($siteCount -le 1 -and $workersPerSite -gt 4) {

            $workersPerSite = 4

        } elseif ($siteCount -gt 1 -and $workersPerSite -gt 12) {

            $workersPerSite = 12

        }

    } else {

        $workersPerSite = [Math]::Max(1, $workersPerSite)

    }



    if ($MaxActiveSites -eq 0) {

        $activeSiteLimit = 0

    } elseif ($MaxActiveSites -gt 0) {

        $activeSiteLimit = [Math]::Min($siteCount, $MaxActiveSites)

    } else {

        $activeSiteLimit = [Math]::Ceiling($targetThreads / [Math]::Max(1, $workersPerSite))

        if ($activeSiteLimit -lt 1) { $activeSiteLimit = 1 }

        if ($activeSiteLimit -gt $siteCount) { $activeSiteLimit = $siteCount }

    }



    $jobsPerThreadValue = $JobsPerThread

    if ($jobsPerThreadValue -le 0) {

        if ($targetThreads -gt 0) {

            $jobsPerThreadValue = [Math]::Ceiling([Math]::Max(1, $deviceCount) / [Math]::Max(1, $targetThreads))

        }

        if ($jobsPerThreadValue -lt 1) { $jobsPerThreadValue = 1 }

        if ($jobsPerThreadValue -gt 4) { $jobsPerThreadValue = 4 }

    } else {

        $jobsPerThreadValue = [Math]::Max(1, $jobsPerThreadValue)

    }



    $minThreadBaseline = $MinRunspaces

    if ($minThreadBaseline -le 0 -or $minThreadBaseline -gt $targetThreads) {

        $minThreadBaseline = [Math]::Max(1, [Math]::Min($targetThreads, [Math]::Ceiling([Math]::Max(1.0, [double]$siteCount) / 2.0)))

    }



    return [PSCustomObject]@{

        ThreadCeiling     = [int][Math]::Max(1, $targetThreads)

        MaxWorkersPerSite = [int][Math]::Max(1, $workersPerSite)

        MaxActiveSites    = [int][Math]::Max(0, $activeSiteLimit)

        JobsPerThread     = [int][Math]::Max(1, $jobsPerThreadValue)

        MinRunspaces      = [int][Math]::Max(1, $minThreadBaseline)

        DeviceCount       = [int][Math]::Max(0, $deviceCount)

        SiteCount         = [int][Math]::Max(0, $rawSiteCount)

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



    $allExtractedFiles = @(Get-ChildItem -Path $extractedPath -File)

    if ($allExtractedFiles.Count -gt 0) {
        $unknownSlices = @($allExtractedFiles | Where-Object { $_.BaseName -eq '_unknown' })
        if ($unknownSlices.Count -gt 0) {
            $unknownNames = $unknownSlices | Select-Object -ExpandProperty FullName
            Write-Verbose ("Skipping {0} unknown slice(s): {1}" -f $unknownSlices.Count, ($unknownNames -join ', '))
        }
    }

    $deviceFiles = @($allExtractedFiles | Where-Object { $_.BaseName -ne '_unknown' } | Select-Object -ExpandProperty FullName)

    $logSetStats = Get-DeviceLogSetStatistics -DeviceFiles $deviceFiles

    $rawSiteCountForTelemetry = $logSetStats.SiteCount

    $deviceCountForTelemetry = $logSetStats.DeviceCount

    if ($deviceFiles.Count -gt 0) {

        Write-Host "Extracted $($deviceFiles.Count) device log file(s) to process:" -ForegroundColor Yellow

        foreach ($dev in $deviceFiles) {

            Write-Host "  - $dev" -ForegroundColor Yellow

        }

    } else {

        Write-Warning "No device logs were extracted; the parser will not run."

    }



    $parserSettings = $null

    $maxWorkersPerSite = 1

    $maxActiveSites = 1

    $threadCeiling = [Math]::Min(8, [Environment]::ProcessorCount)

    $minRunspaces = 1

    $jobsPerThread = 2

    $enableAdaptiveThreads = $true

    try {

        $settingsPath = Join-Path $projectRoot '..\Data\StateTraceSettings.json'

        if (Test-Path -LiteralPath $settingsPath) {

            $raw = Get-Content -LiteralPath $settingsPath -Raw

            if (-not [string]::IsNullOrWhiteSpace($raw)) {

                try { $settings = $raw | ConvertFrom-Json } catch { $settings = $null }

                if ($settings) {

                    if ($settings.PSObject.Properties.Name -contains 'ParserSettings') {

                        $parserSettings = $settings.ParserSettings

                    } elseif ($settings.PSObject.Properties.Name -contains 'Parser') {

                        $parserSettings = $settings.Parser

                    }

                }

            }

        }

    } catch { }



    $autoScaleConcurrency = $false

    $hasThreadCeilingSetting = $false

    $hasMaxWorkersSetting = $false

    $hasMaxActiveSitesSetting = $false

    $hasJobsPerThreadSetting = $false

    $hasMinRunspacesSetting = $false



    if ($parserSettings) {

        if ($parserSettings.PSObject.Properties.Name -contains 'MaxWorkersPerSite') {

            try {

                $val = [int]$parserSettings.MaxWorkersPerSite

                if ($val -gt 0) { $maxWorkersPerSite = $val }

                elseif ($val -eq 0) { $maxWorkersPerSite = 0 }

                $hasMaxWorkersSetting = $true

            } catch { }

        }

        if ($parserSettings.PSObject.Properties.Name -contains 'MaxActiveSites') {

            try {

                $val = [int]$parserSettings.MaxActiveSites

                if ($val -gt 0) { $maxActiveSites = $val }

                elseif ($val -eq 0) { $maxActiveSites = 0 }

                $hasMaxActiveSitesSetting = $true

            } catch { }

        }

        if ($parserSettings.PSObject.Properties.Name -contains 'MaxRunspaceCeiling') {

            try {

                $val = [int]$parserSettings.MaxRunspaceCeiling

                if ($val -gt 0) { $threadCeiling = $val }

                $hasThreadCeilingSetting = $true

            } catch { }

        }

        if ($parserSettings.PSObject.Properties.Name -contains 'MinRunspaceCount') {

            try {

                $val = [int]$parserSettings.MinRunspaceCount

                if ($val -gt 0) { $minRunspaces = $val }

                $hasMinRunspacesSetting = $true

            } catch { }

        }

        if ($parserSettings.PSObject.Properties.Name -contains 'JobsPerThread') {

            try {

                $val = [int]$parserSettings.JobsPerThread

                if ($val -gt 0) { $jobsPerThread = $val }

                $hasJobsPerThreadSetting = $true

            } catch { }

        }

        if ($parserSettings.PSObject.Properties.Name -contains 'EnableAdaptiveThreads') {

            try {

                $flag = [bool]$parserSettings.EnableAdaptiveThreads

                $enableAdaptiveThreads = $flag

            } catch { }

        }

        if ($parserSettings.PSObject.Properties.Name -contains 'AutoScaleConcurrency') {

            try {

                $autoScaleConcurrency = [bool]$parserSettings.AutoScaleConcurrency

            } catch { $autoScaleConcurrency = $false }

        }

    }



    $autoScaleThreadHint = if ($hasThreadCeilingSetting) { $threadCeiling } else { 0 }

    $autoScaleWorkerHint = if ($hasMaxWorkersSetting) { $maxWorkersPerSite } else { 0 }

    $autoScaleSiteHint   = if ($hasMaxActiveSitesSetting) { $maxActiveSites } else { -1 }

    $autoScaleJobsHint   = if ($hasJobsPerThreadSetting) { $jobsPerThread } else { 0 }

    $autoScaleMinHint    = if ($hasMinRunspacesSetting) { $minRunspaces } else { 0 }



    $resolvedProfile = $null

    if ($autoScaleConcurrency) {

        $profile = Get-AutoScaleConcurrencyProfile -DeviceFiles $deviceFiles -CpuCount ([Environment]::ProcessorCount) -ThreadCeiling $autoScaleThreadHint -MaxWorkersPerSite $autoScaleWorkerHint -MaxActiveSites $autoScaleSiteHint -JobsPerThread $autoScaleJobsHint -MinRunspaces $autoScaleMinHint
        $resolvedProfile = $profile

        $threadCeiling = $profile.ThreadCeiling

        $maxWorkersPerSite = $profile.MaxWorkersPerSite

        $maxActiveSites = $profile.MaxActiveSites

        $jobsPerThread = $profile.JobsPerThread

        if ($profile.MinRunspaces -gt 0) { $minRunspaces = $profile.MinRunspaces }

    }



    $threadCeiling = [Math]::Max($minRunspaces, $threadCeiling)

    $jobsPerThread = [Math]::Max(1, $jobsPerThread)

    $cpuLimit = [Math]::Max($minRunspaces, [Environment]::ProcessorCount * 2)

    $threadCeiling = [Math]::Min($threadCeiling, $cpuLimit)

    if ($maxActiveSites -gt 0) {

        $threadCeiling = [Math]::Min($threadCeiling, [Math]::Max($minRunspaces, $maxActiveSites * [Math]::Max(1, $maxWorkersPerSite)))

    } elseif ($maxWorkersPerSite -gt 0) {

        $threadCeiling = [Math]::Min($threadCeiling, [Math]::Max($minRunspaces, $maxWorkersPerSite))

    }

    if ($threadCeiling -lt $minRunspaces) { $threadCeiling = $minRunspaces }



    $telemetryPayload = @{

        AutoScaleEnabled = [bool]$autoScaleConcurrency

        DeviceCount      = [int]$deviceCountForTelemetry

        SiteCount        = [int]$rawSiteCountForTelemetry

        ThreadCeiling    = [int]$threadCeiling

        MaxWorkersPerSite = [int]$maxWorkersPerSite

        MaxActiveSites   = [int]$maxActiveSites

        JobsPerThread    = [int]$jobsPerThread

        MinRunspaces     = [int]$minRunspaces

        AdaptiveThreads  = [bool]$enableAdaptiveThreads

        HintThreadCeiling     = [int]$autoScaleThreadHint

        HintMaxWorkersPerSite = [int]$autoScaleWorkerHint

        HintMaxActiveSites    = [int]$autoScaleSiteHint

        HintJobsPerThread     = [int]$autoScaleJobsHint

        HintMinRunspaces      = [int]$autoScaleMinHint

    }

    if ($resolvedProfile) {

        $telemetryPayload.DecisionSource = 'AutoScale'

        $telemetryPayload.ResolvedThreadCeiling = [int]$resolvedProfile.ThreadCeiling

        $telemetryPayload.ResolvedMaxWorkersPerSite = [int]$resolvedProfile.MaxWorkersPerSite

        $telemetryPayload.ResolvedMaxActiveSites = [int]$resolvedProfile.MaxActiveSites

        $telemetryPayload.ResolvedJobsPerThread = [int]$resolvedProfile.JobsPerThread

        $telemetryPayload.ResolvedMinRunspaces = [int]$resolvedProfile.MinRunspaces

        if ($resolvedProfile.PSObject.Properties.Name -contains 'DeviceCount') {

            $telemetryPayload.ProfileDeviceCount = [int]$resolvedProfile.DeviceCount

        }

        if ($resolvedProfile.PSObject.Properties.Name -contains 'SiteCount') {

            $telemetryPayload.ProfileSiteCount = [int]$resolvedProfile.SiteCount

        }

    } else {

        $telemetryPayload.DecisionSource = 'Settings'

    }

    try {

        TelemetryModule\Write-StTelemetryEvent -Name 'ConcurrencyProfileResolved' -Payload $telemetryPayload

    } catch { }



    $dbPath = $null

    if ($PSBoundParameters.ContainsKey('DatabasePath') -and $DatabasePath) {

        $dbPath = $DatabasePath

    }



    $jobsParams = @{

        DeviceFiles = $deviceFiles

        MaxThreads  = [Math]::Max($minRunspaces, $threadCeiling)

        MinThreads  = $minRunspaces

        JobsPerThread = $jobsPerThread

        DatabasePath = $dbPath

        ModulesPath = $modulesPath

        ArchiveRoot = $archiveRoot

        MaxWorkersPerSite = $maxWorkersPerSite

        MaxActiveSites    = $maxActiveSites

    }

    if ($enableAdaptiveThreads) { $jobsParams.AdaptiveThreads = $true }

    if ($Synchronous) { $jobsParams.Synchronous = $true }



    if ($deviceFiles.Count -gt 0) {

        $mode = if ($Synchronous) { "synchronously" } else { "in parallel" }

        Write-Host "Processing $($deviceFiles.Count) logs $mode..." -ForegroundColor Yellow

        ParserRunspaceModule\Invoke-DeviceParsingJobs @jobsParams

    }



    LogIngestionModule\Clear-ExtractedLogs -ExtractedPath $extractedPath

    Write-Host "Processing complete." -ForegroundColor Yellow

}

Export-ModuleMember -Function Invoke-StateTraceParsing
