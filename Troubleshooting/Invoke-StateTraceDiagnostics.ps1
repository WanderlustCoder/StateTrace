
[CmdletBinding()]
param(
    [string[]]$Phases,
    [string]$OutputDirectory,
    [switch]$SkipPester
)
Set-StrictMode -Version Latest


function New-DiagnosticResult {
    param(
        [string]$Phase,
        [string]$Check,
        [string]$Status,
        [string]$Evidence,
        [string]$Remediation,
        [string]$NextSteps
    )
    return [pscustomobject]@{
        Phase = $Phase
        Check = $Check
        Status = $Status
        Evidence = $Evidence
        Remediation = $Remediation
        NextSteps = $NextSteps
    }
}

function New-PhaseLogger {
    param(
        [string]$Phase,
        [string]$OutputDirectory
    )
    $logName = '{0}_{1}.log' -f $Phase, (Get-Date -Format 'yyyyMMdd_HHmmss')
    $logPath = Join-Path $OutputDirectory $logName
    if (-not (Test-Path -LiteralPath $logPath)) {
        New-Item -ItemType File -Path $logPath -Force | Out-Null
    }
    return [pscustomobject]@{
        Phase = $Phase
        LogPath = $logPath
    }
}

function Write-PhaseLog {
    param(
        $Logger,
        [string]$Message
    )
    $line = '[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $Message
    Add-Content -LiteralPath $Logger.LogPath -Value $line
    Write-Host ('[{0}] {1}' -f $Logger.Phase, $Message)
}

function Test-OleDbProvider {
    param(
        [string]$Provider,
        [string]$DatabasePath
    )
    $result = [pscustomobject]@{
        Provider = $Provider
        Success = $false
        Message = ''
    }
    $conn = $null
    try {
        $conn = New-Object System.Data.OleDb.OleDbConnection
        $conn.ConnectionString = 'Provider={0};Data Source={1}' -f $Provider, $DatabasePath
        $conn.Open()
        $result.Success = $true
        $result.Message = 'Opened connection successfully.'
    } catch {
        $result.Message = $_.Exception.Message
    } finally {
        if ($conn) {
            try { $conn.Close() } catch {}
            try { $conn.Dispose() } catch {}
        }
    }
    return $result
}

function Write-DiagnosticsReports {
    param(
        [System.Collections.IEnumerable]$Results,
        [string]$OutputDirectory,
        [string]$Timestamp
    )
    $jsonPath = Join-Path $OutputDirectory 'diagnostics.json'
    $Results | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $jsonPath -Encoding utf8

    $summaryLines = @()
    $summaryLines += '# StateTrace Diagnostics (' + $Timestamp + ')'
    $summaryLines += ''
    $summaryLines += '## Summary'

    $statusGroups = $Results | Group-Object -Property Status
    foreach ($group in $statusGroups) {
        $summaryLines += ('- {0}: {1}' -f $group.Name, $group.Count)
    }
    if (-not $statusGroups) {
        $summaryLines += '- No diagnostics recorded.'
    }

    $summaryLines += ''

    $phaseGroups = $Results | Group-Object -Property Phase
    foreach ($phase in $phaseGroups | Sort-Object -Property Name) {
        $summaryLines += ('## Phase: {0}' -f $phase.Name)
        foreach ($entry in $phase.Group) {
            $summaryLines += ('- **{0}** [{1}] {2}' -f $entry.Check, $entry.Status, $entry.Evidence)
            if ($entry.Remediation) {
                $summaryLines += ('  - Remediation: {0}' -f $entry.Remediation)
            }
            if ($entry.NextSteps) {
                $summaryLines += ('  - Next: {0}' -f $entry.NextSteps)
            }
        }
        $summaryLines += ''
    }

    $mdPath = Join-Path $OutputDirectory 'diagnostics.md'
    Set-Content -LiteralPath $mdPath -Value $summaryLines -Encoding utf8
}

$defaultPhases = @('Environment','SourceIntegrity','DataLayer','ParserPipeline','UiGlobals','TemplatesThemes')
if (-not $Phases -or $Phases.Count -eq 0) {
    $Phases = $defaultPhases
}
$Phases = $Phases | Select-Object -Unique

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'

if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $repoRoot ('Logs\\Troubleshooting\\' + $timestamp)
}

if (-not (Test-Path -LiteralPath $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}

$context = [pscustomobject]@{
    RepositoryRoot = $repoRoot
    OutputDirectory = $OutputDirectory
    Timestamp = $timestamp
    ProviderChecks = @{}
    Manifest = $null
    ManifestModules = @()
    ModulesImported = New-Object System.Collections.Generic.List[string]
}

$results = New-Object System.Collections.Generic.List[object]

function Invoke-EnvironmentPhase {
    param($Context)
    $phaseName = 'Environment'
    $logger = New-PhaseLogger -Phase $phaseName -OutputDirectory $Context.OutputDirectory
    $phaseResults = New-Object System.Collections.Generic.List[object]

    Write-PhaseLog -Logger $logger -Message 'Collecting PowerShell runtime information.'
    $psVersion = $PSVersionTable.PSVersion
    $status = if ($psVersion.Major -ge 5) { 'Pass' } else { 'Fail' }
    $phaseResults.Add((New-DiagnosticResult -Phase $phaseName -Check 'PowerShellVersion' -Status $status -Evidence ('Detected {0}' -f $psVersion) -Remediation 'Install PowerShell 5.1 or later.' -NextSteps $null))

    Write-PhaseLog -Logger $logger -Message 'Loading PresentationFramework assembly.'
    try {
        Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
        $phaseResults.Add((New-DiagnosticResult -Phase $phaseName -Check 'PresentationFramework' -Status 'Pass' -Evidence 'PresentationFramework loaded successfully.' -Remediation $null -NextSteps $null))
    } catch {
        $phaseResults.Add((New-DiagnosticResult -Phase $phaseName -Check 'PresentationFramework' -Status 'Fail' -Evidence $_.Exception.Message -Remediation 'Ensure .NET desktop components are installed.' -NextSteps 'Repair .NET install and retry.'))
    }

    $dataDir = Join-Path $Context.RepositoryRoot 'Data'
    $accdb = Get-ChildItem -Path $dataDir -Filter '*.accdb' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $accdb) {
        $phaseResults.Add((New-DiagnosticResult -Phase $phaseName -Check 'AccessProvider' -Status 'Warn' -Evidence 'No .accdb files found under Data.' -Remediation 'Populate sample databases before running provider checks.' -NextSteps $null))
    } else {
        Write-PhaseLog -Logger $logger -Message ('Testing OLE DB providers against {0}.' -f $accdb.FullName)
        foreach ($prov in @('Microsoft.ACE.OLEDB.12.0','Microsoft.Jet.OLEDB.4.0')) {
            $probe = Test-OleDbProvider -Provider $prov -DatabasePath $accdb.FullName
            $Context.ProviderChecks[$prov] = $probe
            if ($probe.Success) {
                $phaseResults.Add((New-DiagnosticResult -Phase $phaseName -Check ('Provider:' + $prov) -Status 'Pass' -Evidence $probe.Message -Remediation $null -NextSteps $null))
            } else {
                $phaseResults.Add((New-DiagnosticResult -Phase $phaseName -Check ('Provider:' + $prov) -Status 'Fail' -Evidence $probe.Message -Remediation 'Install the matching Access Database Engine redistributable.' -NextSteps 'Download: https://www.microsoft.com/en-us/download/details.aspx?id=13255'))
            }
        }
    }

    return $phaseResults
}

function Invoke-SourceIntegrityPhase {
    param($Context)
    $phaseName = 'SourceIntegrity'
    $logger = New-PhaseLogger -Phase $phaseName -OutputDirectory $Context.OutputDirectory
    $phaseResults = New-Object System.Collections.Generic.List[object]

    $manifestPath = Join-Path $Context.RepositoryRoot 'Modules\\ModulesManifest.psd1'
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        $phaseResults.Add((New-DiagnosticResult -Phase $phaseName -Check 'ModulesManifest' -Status 'Fail' -Evidence ('Manifest missing at ' + $manifestPath) -Remediation 'Restore Modules/ModulesManifest.psd1.' -NextSteps $null))
        return $phaseResults
    }

    Write-PhaseLog -Logger $logger -Message 'Loading module manifest.'
    try {
        if (Get-Command Import-PowerShellDataFile -ErrorAction SilentlyContinue) {
            $Context.Manifest = Import-PowerShellDataFile -Path $manifestPath
        } else {
            $Context.Manifest = . $manifestPath
        }
        $phaseResults.Add((New-DiagnosticResult -Phase $phaseName -Check 'ModulesManifest' -Status 'Pass' -Evidence 'Manifest parsed successfully.' -Remediation $null -NextSteps $null))
    } catch {
        $phaseResults.Add((New-DiagnosticResult -Phase $phaseName -Check 'ModulesManifest' -Status 'Fail' -Evidence $_.Exception.Message -Remediation 'Fix syntax errors in ModulesManifest.psd1.' -NextSteps $null))
        return $phaseResults
    }

    $modules = @()
    if ($Context.Manifest.ModulesToImport) {
        $modules = @($Context.Manifest.ModulesToImport)
    } elseif ($Context.Manifest.Modules) {
        $modules = @($Context.Manifest.Modules)
    }
    $Context.ManifestModules = $modules

    if (-not $modules -or $modules.Count -eq 0) {
        $phaseResults.Add((New-DiagnosticResult -Phase $phaseName -Check 'ManifestEntries' -Status 'Warn' -Evidence 'No modules listed in manifest.' -Remediation 'Populate Modules array in manifest.' -NextSteps $null))
        return $phaseResults
    }

    $modulesDir = Join-Path $Context.RepositoryRoot 'Modules'
    $missing = @()
    foreach ($moduleName in $modules) {
        $modulePath = Join-Path $modulesDir $moduleName
        if (-not (Test-Path -LiteralPath $modulePath)) {
            $missing += $moduleName
        }
    }
    if ($missing.Count -gt 0) {
        $phaseResults.Add((New-DiagnosticResult -Phase $phaseName -Check 'ModuleFiles' -Status 'Fail' -Evidence ('Missing: ' + ($missing -join ', ')) -Remediation 'Restore module files referenced by the manifest.' -NextSteps $null))
    } else {
        $phaseResults.Add((New-DiagnosticResult -Phase $phaseName -Check 'ModuleFiles' -Status 'Pass' -Evidence ('All manifest modules present (' + $modules.Count + ').') -Remediation $null -NextSteps $null))
    }

    $importFailures = @()
    foreach ($moduleName in $modules) {
        $modulePath = Join-Path $modulesDir $moduleName
        try {
            Import-Module -Name $modulePath -Force -Global -ErrorAction Stop
            if (-not $Context.ModulesImported.Contains($moduleName)) {
                $null = $Context.ModulesImported.Add($moduleName)
            }
        } catch {
            $importFailures += '{0}: {1}' -f $moduleName, $_.Exception.Message
        }
    }
    if ($importFailures.Count -gt 0) {
        $phaseResults.Add((New-DiagnosticResult -Phase $phaseName -Check 'ModuleImports' -Status 'Fail' -Evidence ($importFailures -join '; ') -Remediation 'Resolve import errors before running diagnostics.' -NextSteps 'Run Import-Module manually to reproduce.'))
    } else {
        $phaseResults.Add((New-DiagnosticResult -Phase $phaseName -Check 'ModuleImports' -Status 'Pass' -Evidence 'All manifest modules imported.' -Remediation $null -NextSteps $null))
    }

    $expectedCommands = @(
        @{ Name = 'DeviceRepositoryModule\\Get-SiteFromHostname'; Purpose = 'Device repository site resolver' },
        @{ Name = 'DeviceRepositoryModule\\Update-GlobalInterfaceList'; Purpose = 'Device repository global interface refresh' },
        @{ Name = 'DeviceCatalogModule\\Get-DeviceSummaries'; Purpose = 'Device catalog metadata loader' },
        @{ Name = 'FilterStateModule\\Initialize-DeviceFilters'; Purpose = 'Filter state bootstrap' },
        @{ Name = 'FilterStateModule\\Update-DeviceFilter'; Purpose = 'Filter state updater' },
        @{ Name = 'DeviceDetailsModule\\Get-DeviceDetails'; Purpose = 'Device details retrieval' },
        @{ Name = 'DeviceInsightsModule\\Update-SearchResults'; Purpose = 'Search results service' },
        @{ Name = 'DeviceInsightsModule\\Update-Summary'; Purpose = 'Summary metrics service' },
        @{ Name = 'DeviceInsightsModule\\Update-Alerts'; Purpose = 'Alerts service' },
        @{ Name = 'TemplatesModule\\Get-ConfigurationTemplates'; Purpose = 'Template lookup' },
        @{ Name = 'InterfaceModule\\Set-InterfaceViewData'; Purpose = 'Interface view binding' },
        @{ Name = 'ParserWorker\\Invoke-StateTraceParsing'; Purpose = 'Parser invocation entry point' }
    )

    $missingCommands = @()
    foreach ($expectation in $expectedCommands) {
        if (-not (Get-Command -Name $expectation.Name -ErrorAction SilentlyContinue)) {
            $missingCommands += ('{0} ({1})' -f $expectation.Name, $expectation.Purpose)
        }
    }
    if ($missingCommands.Count -gt 0) {
        .Add((New-DiagnosticResult -Phase  -Check 'CommandExports' -Status 'Fail' -Evidence ( -join '; ') -Remediation 'Restore missing function exports.' -NextSteps 'Inspect ModulesManifest and Export-ModuleMember statements.'))
    } else {
        $phaseResults.Add((New-DiagnosticResult -Phase $phaseName -Check 'CommandExports' -Status 'Pass' -Evidence 'All critical commands exported.' -Remediation $null -NextSteps $null))
    }

    return $phaseResults
}

function Invoke-DataLayerPhase {
    param($Context)
    $phaseName = 'DataLayer'
    $logger = New-PhaseLogger -Phase $phaseName -OutputDirectory $Context.OutputDirectory
    $phaseResults = New-Object System.Collections.Generic.List[object]

    if (-not (Get-Command -Name 'DatabaseModule\\Open-DbReadSession' -ErrorAction SilentlyContinue)) {
        $phaseResults.Add((New-DiagnosticResult -Phase $phaseName -Check 'DatabaseModule' -Status 'Fail' -Evidence 'DatabaseModule not imported.' -Remediation 'Run SourceIntegrity phase to load modules.' -NextSteps $null))
        return $phaseResults
    }

    $dataDir = Join-Path $Context.RepositoryRoot 'Data'
    $databases = Get-ChildItem -Path $dataDir -Filter '*.accdb' -ErrorAction SilentlyContinue
    if (-not $databases -or $databases.Count -eq 0) {
        $phaseResults.Add((New-DiagnosticResult -Phase $phaseName -Check 'DatabaseInventory' -Status 'Warn' -Evidence 'No Access databases discovered.' -Remediation 'Place site databases in the Data directory.' -NextSteps $null))
        return $phaseResults
    }

    foreach ($db in $databases) {
        Write-PhaseLog -Logger $logger -Message ('Opening database {0}.' -f $db.FullName)
        $session = $null
        try {
            $session = DatabaseModule\\Open-DbReadSession -DatabasePath $db.FullName
            if (-not $session) {
                $phaseResults.Add((New-DiagnosticResult -Phase $phaseName -Check $db.Name -Status 'Fail' -Evidence 'Open-DbReadSession returned null.' -Remediation 'Inspect DatabaseModule for runtime errors.' -NextSteps $null))
                continue
            }
            $summaryTable = DatabaseModule\\Invoke-DbQuery -DatabasePath $db.FullName -Sql 'SELECT TOP 1 Hostname FROM DeviceSummary' -Session $session
            $interfacesTable = DatabaseModule\\Invoke-DbQuery -DatabasePath $db.FullName -Sql 'SELECT TOP 1 Port FROM Interfaces' -Session $session
            $phaseResults.Add((New-DiagnosticResult -Phase $phaseName -Check $db.Name -Status 'Pass' -Evidence ('DeviceSummary rows={0}, Interfaces rows={1}' -f $summaryTable.Rows.Count, $interfacesTable.Rows.Count) -Remediation $null -NextSteps $null))
        } catch {
            $phaseResults.Add((New-DiagnosticResult -Phase $phaseName -Check $db.Name -Status 'Fail' -Evidence $_.Exception.Message -Remediation 'Run Access repair on the database and ensure schema matches DatabaseModule expectations.' -NextSteps $null))
        } finally {
            if ($session) {
                try { DatabaseModule\\Close-DbReadSession -Session $session } catch {}
            }
        }
    }

    return $phaseResults
}

function Invoke-ParserPipelinePhase {
    param($Context, [switch]$SkipPester)
    $phaseName = 'ParserPipeline'
    $logger = New-PhaseLogger -Phase $phaseName -OutputDirectory $Context.OutputDirectory
    $phaseResults = New-Object System.Collections.Generic.List[object]

    $commands = @(
        'LogIngestionModule\\Split-RawLogs',
        'LogIngestionModule\\Clear-ExtractedLogs',
        'ParserRunspaceModule\\Invoke-DeviceParsingJobs',
        'ParserWorker\\Invoke-StateTraceParsing'
    )

    $missing = @()
    foreach ($cmd in $commands) {
        if (-not (Get-Command -Name $cmd -ErrorAction SilentlyContinue)) {
            $missing += $cmd
        }
    }

    if ($missing.Count -gt 0) {
        $phaseResults.Add((New-DiagnosticResult -Phase $phaseName -Check 'ParserCommands' -Status 'Fail' -Evidence ('Missing commands: ' + ($missing -join ', ')) -Remediation 'Verify parser modules are imported.' -NextSteps 'Run SourceIntegrity phase.'))
    } else {
        $phaseResults.Add((New-DiagnosticResult -Phase $phaseName -Check 'ParserCommands' -Status 'Pass' -Evidence 'Parser entry points exported.' -Remediation $null -NextSteps $null))
    }

    $logsDir = Join-Path $Context.RepositoryRoot 'Logs'
    if (-not (Test-Path -LiteralPath $logsDir)) {
        $phaseResults.Add((New-DiagnosticResult -Phase $phaseName -Check 'LogsDirectory' -Status 'Warn' -Evidence ('Logs directory missing at ' + $logsDir) -Remediation 'Create Logs folder before running parser.' -NextSteps $null))
    } else {
        $phaseResults.Add((New-DiagnosticResult -Phase $phaseName -Check 'LogsDirectory' -Status 'Pass' -Evidence 'Logs directory accessible.' -Remediation $null -NextSteps $null))
    }

    if (-not $SkipPester) {
        $pesterModule = Get-Module -Name Pester -ListAvailable | Sort-Object -Property Version -Descending | Select-Object -First 1
        if ($pesterModule) {
            try {
                Import-Module -Name $pesterModule.Name -ErrorAction Stop | Out-Null
                $testPath = Join-Path $Context.RepositoryRoot 'Modules\\Tests\\ParserRunspaceModule.Tests.ps1'
                if (Test-Path -LiteralPath $testPath) {
                    Write-PhaseLog -Logger $logger -Message 'Running ParserRunspaceModule Pester tests.'
                    $testResult = Invoke-Pester -Path $testPath -Output Summary -PassThru -ErrorAction Stop
                    if ($testResult.FailedCount -gt 0) {
                        $phaseResults.Add((New-DiagnosticResult -Phase $phaseName -Check 'PesterTests' -Status 'Fail' -Evidence ('Failures: ' + $testResult.FailedCount) -Remediation 'Review test output for stack traces.' -NextSteps ('Inspect ' + $testPath)))
                    } else {
                        $phaseResults.Add((New-DiagnosticResult -Phase $phaseName -Check 'PesterTests' -Status 'Pass' -Evidence ('Tests passed in ' + $testResult.TotalTime.TotalSeconds + 's') -Remediation $null -NextSteps $null))
                    }
                } else {
                    $phaseResults.Add((New-DiagnosticResult -Phase $phaseName -Check 'PesterTests' -Status 'Warn' -Evidence 'ParserRunspaceModule.Tests.ps1 not found.' -Remediation 'Restore Modules/Tests files.' -NextSteps $null))
                }
            } catch {
                $phaseResults.Add((New-DiagnosticResult -Phase $phaseName -Check 'PesterTests' -Status 'Fail' -Evidence $_.Exception.Message -Remediation 'Resolve Pester execution issues.' -NextSteps 'Run Invoke-Pester manually.'))
            }
        } else {
            $phaseResults.Add((New-DiagnosticResult -Phase $phaseName -Check 'PesterTests' -Status 'Warn' -Evidence 'Pester module not found on this system.' -Remediation 'Install Pester from PSGallery if automated tests are required.' -NextSteps 'Install-Module Pester'))
        }
    }

    return $phaseResults
}

function Invoke-UiGlobalsPhase {
    param($Context)
    $phaseName = 'UiGlobals'
    $logger = New-PhaseLogger -Phase $phaseName -OutputDirectory $Context.OutputDirectory
    $phaseResults = New-Object System.Collections.Generic.List[object]

    $mainPs1 = Join-Path $Context.RepositoryRoot 'Main\\MainWindow.ps1'
    if (-not (Test-Path -LiteralPath $mainPs1)) {
        $phaseResults.Add((New-DiagnosticResult -Phase $phaseName -Check 'MainWindow.ps1' -Status 'Fail' -Evidence ('Missing ' + $mainPs1) -Remediation 'Restore Main/MainWindow.ps1.' -NextSteps $null))
    } else {
        Write-PhaseLog -Logger $logger -Message 'Parsing MainWindow.ps1.'
        try {
            $source = Get-Content -LiteralPath $mainPs1 -Raw
            [void][scriptblock]::Create($source)
            $phaseResults.Add((New-DiagnosticResult -Phase $phaseName -Check 'MainWindow.ps1' -Status 'Pass' -Evidence 'MainWindow.ps1 parsed successfully.' -Remediation $null -NextSteps $null))
        } catch {
            $phaseResults.Add((New-DiagnosticResult -Phase $phaseName -Check 'MainWindow.ps1' -Status 'Fail' -Evidence $_.Exception.Message -Remediation 'Fix syntax errors in MainWindow.ps1.' -NextSteps $null))
        }
    }

    $mainXaml = Join-Path $Context.RepositoryRoot 'Main\\MainWindow.xaml'
    if (-not (Test-Path -LiteralPath $mainXaml)) {
        $phaseResults.Add((New-DiagnosticResult -Phase $phaseName -Check 'MainWindow.xaml' -Status 'Fail' -Evidence ('Missing ' + $mainXaml) -Remediation 'Restore Main/MainWindow.xaml.' -NextSteps $null))
    } else {
        Write-PhaseLog -Logger $logger -Message 'Validating MainWindow.xaml XML.'
        try {
            $xamlContent = Get-Content -LiteralPath $mainXaml -Raw
            [xml]$null = $xamlContent
            $phaseResults.Add((New-DiagnosticResult -Phase $phaseName -Check 'MainWindow.xaml' -Status 'Pass' -Evidence 'XAML parsed successfully.' -Remediation $null -NextSteps $null))
        } catch {
            $phaseResults.Add((New-DiagnosticResult -Phase $phaseName -Check 'MainWindow.xaml' -Status 'Fail' -Evidence $_.Exception.Message -Remediation 'Repair XML syntax in MainWindow.xaml.' -NextSteps $null))
        }
    }

    $smokeScript = Join-Path $Context.RepositoryRoot 'Tests\\Invoke-MainWindowSmokeTest.ps1'
    if (Test-Path -LiteralPath $smokeScript) {
        $smokeOut = Join-Path $Context.OutputDirectory 'SmokeTest'
        if (-not (Test-Path -LiteralPath $smokeOut)) {
            New-Item -ItemType Directory -Path $smokeOut -Force | Out-Null
        }
        Write-PhaseLog -Logger $logger -Message 'Running Invoke-MainWindowSmokeTest.ps1 in isolated process.'
        $psiArgs = @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$smokeScript,'-RepositoryRoot',$Context.RepositoryRoot,'-OutputDirectory',$smokeOut)
        $procOutput = & powershell.exe @psiArgs 2>&1
        $exitCode = $LASTEXITCODE
        $logFile = Join-Path $smokeOut 'smoke-output.log'
        $procOutput | Out-File -LiteralPath $logFile -Encoding utf8
        if ($exitCode -eq 0) {
            $phaseResults.Add((New-DiagnosticResult -Phase $phaseName -Check 'SmokeTest' -Status 'Pass' -Evidence ('Smoke test succeeded. Log: ' + $logFile) -Remediation $null -NextSteps $null))
        } else {
            $phaseResults.Add((New-DiagnosticResult -Phase $phaseName -Check 'SmokeTest' -Status 'Fail' -Evidence ('ExitCode=' + $exitCode + '; See ' + $logFile) -Remediation 'Review smoke test log for missing commands or syntax errors.' -NextSteps $null))
        }
    } else {
        $phaseResults.Add((New-DiagnosticResult -Phase $phaseName -Check 'SmokeTest' -Status 'Warn' -Evidence 'Invoke-MainWindowSmokeTest.ps1 not found.' -Remediation 'Restore Tests/Invoke-MainWindowSmokeTest.ps1.' -NextSteps $null))
    }

    return $phaseResults
}

function Invoke-TemplatesThemesPhase {
    param($Context)
    $phaseName = 'TemplatesThemes'
    $logger = New-PhaseLogger -Phase $phaseName -OutputDirectory $Context.OutputDirectory
    $phaseResults = New-Object System.Collections.Generic.List[object]

    $templatesDir = Join-Path $Context.RepositoryRoot 'Templates'
    $templateFiles = @()
    if (Test-Path -LiteralPath $templatesDir) {
        $templateFiles = Get-ChildItem -Path $templatesDir -Filter '*.json' -ErrorAction SilentlyContinue
    }
    if ($templateFiles.Count -eq 0) {
        $phaseResults.Add((New-DiagnosticResult -Phase $phaseName -Check 'TemplateJson' -Status 'Warn' -Evidence 'No JSON templates found under Templates.' -Remediation 'Ensure Templates/*.json exist.' -NextSteps $null))
    } else {
        foreach ($file in $templateFiles) {
            try {
                $json = Get-Content -LiteralPath $file.FullName -Raw
                $null = $json | ConvertFrom-Json -ErrorAction Stop
                $phaseResults.Add((New-DiagnosticResult -Phase $phaseName -Check $file.Name -Status 'Pass' -Evidence 'Valid JSON.' -Remediation $null -NextSteps $null))
            } catch {
                $phaseResults.Add((New-DiagnosticResult -Phase $phaseName -Check $file.Name -Status 'Fail' -Evidence $_.Exception.Message -Remediation 'Fix JSON syntax.' -NextSteps $null))
            }
        }
    }

    $themesDir = Join-Path $Context.RepositoryRoot 'Themes'
    $themeFiles = @()
    if (Test-Path -LiteralPath $themesDir) {
        $themeFiles = Get-ChildItem -Path $themesDir -Filter '*.json' -ErrorAction SilentlyContinue
    }
    if ($themeFiles.Count -eq 0) {
        $phaseResults.Add((New-DiagnosticResult -Phase $phaseName -Check 'ThemeJson' -Status 'Warn' -Evidence 'No theme JSON files discovered.' -Remediation 'Restore Themes/*.json resources.' -NextSteps $null))
    } else {
        foreach ($file in $themeFiles) {
            try {
                $json = Get-Content -LiteralPath $file.FullName -Raw
                $null = $json | ConvertFrom-Json -ErrorAction Stop
                $phaseResults.Add((New-DiagnosticResult -Phase $phaseName -Check $file.Name -Status 'Pass' -Evidence 'Valid JSON.' -Remediation $null -NextSteps $null))
            } catch {
                $phaseResults.Add((New-DiagnosticResult -Phase $phaseName -Check $file.Name -Status 'Fail' -Evidence $_.Exception.Message -Remediation 'Fix theme JSON syntax.' -NextSteps $null))
            }
        }
    }

    if (Get-Command -Name 'TemplatesModule\\Get-ShowCommandsVersions' -ErrorAction SilentlyContinue) {
        foreach ($vendor in @('Brocade','Cisco','Arista')) {
            try {
                $versions = TemplatesModule\\Get-ShowCommandsVersions -Vendor $vendor
                if ($versions -and $versions.Count -gt 0) {
                    $phaseResults.Add((New-DiagnosticResult -Phase $phaseName -Check ('ShowCommands:' + $vendor) -Status 'Pass' -Evidence ('Versions: ' + ($versions -join ', ')) -Remediation $null -NextSteps $null))
                } else {
                    $phaseResults.Add((New-DiagnosticResult -Phase $phaseName -Check ('ShowCommands:' + $vendor) -Status 'Warn' -Evidence 'No versions returned.' -Remediation 'Update Templates/ShowCommands.json to include vendor versions.' -NextSteps $null))
                }
            } catch {
                $phaseResults.Add((New-DiagnosticResult -Phase $phaseName -Check ('ShowCommands:' + $vendor) -Status 'Fail' -Evidence $_.Exception.Message -Remediation 'Fix TemplatesModule parsing errors.' -NextSteps $null))
            }
        }
    } else {
        $phaseResults.Add((New-DiagnosticResult -Phase $phaseName -Check 'TemplatesModule' -Status 'Warn' -Evidence 'TemplatesModule not imported; skipping command checks.' -Remediation 'Run SourceIntegrity phase.' -NextSteps $null))
    }

    return $phaseResults
}

$phaseHandlers = @{
    'Environment'     = { Invoke-EnvironmentPhase -Context $context }
    'SourceIntegrity' = { Invoke-SourceIntegrityPhase -Context $context }
    'DataLayer'       = { Invoke-DataLayerPhase -Context $context }
    'ParserPipeline'  = { Invoke-ParserPipelinePhase -Context $context -SkipPester:$SkipPester }
    'UiGlobals'       = { Invoke-UiGlobalsPhase -Context $context }
    'TemplatesThemes' = { Invoke-TemplatesThemesPhase -Context $context }
}

foreach ($phase in $Phases) {
    if (-not $phaseHandlers.ContainsKey($phase)) {
        Write-Host ('[WARN] Unknown phase {0}, skipping.' -f $phase)
        continue
    }
    Write-Host ('=== Running {0} phase ===' -f $phase)
    try {
        $phaseResult = & $phaseHandlers[$phase]
        foreach ($entry in $phaseResult) {
            $null = $results.Add($entry)
        }
    } catch {
        $results.Add((New-DiagnosticResult -Phase $phase -Check 'PhaseExecution' -Status 'Fail' -Evidence $_.Exception.Message -Remediation 'Inspect troubleshooting script for execution errors.' -NextSteps $null))
    }
}

Write-DiagnosticsReports -Results $results -OutputDirectory $context.OutputDirectory -Timestamp $context.Timestamp

Write-Host ('Diagnostics complete. Output: {0}' -f $context.OutputDirectory)


