[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')),
    [string]$OutputDirectory
)

$repoRoot = $null
try {
    $repoRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
} catch {
    throw "Failed to resolve repository root '$RepositoryRoot': $($_.Exception.Message)"
}

if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $repoRoot 'Logs\RefactorValidation'
}

$logEntries = [System.Collections.Generic.List[string]]::new()
$errors = [System.Collections.Generic.List[string]]::new()

function Add-Log {
    param([string]$Message)
    $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $line = "[{0}] {1}" -f $timestamp, $Message
    Write-Host $line
    [void]$logEntries.Add($line)
}

Add-Log ('Repository root: {0}' -f $repoRoot)
Add-Log ('PowerShell version: {0}' -f $PSVersionTable.PSVersion)

if (-not (Test-Path -LiteralPath $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    Add-Log ('Created output directory: {0}' -f $OutputDirectory)
}

$logName = 'MainWindowSmokeTest_{0}.log' -f (Get-Date -Format 'yyyyMMdd_HHmmss')
$logPath = Join-Path $OutputDirectory $logName
Add-Log ('Log file: {0}' -f $logPath)

try {
    Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
    Add-Log 'Loaded PresentationFramework assembly.'
} catch {
    $msg = 'Failed to load PresentationFramework: {0}' -f $_.Exception.Message
    Add-Log $msg
    [void]$errors.Add($msg)
}

$manifestPath = Join-Path $repoRoot 'Modules\ModulesManifest.psd1'
if (-not (Test-Path -LiteralPath $manifestPath)) {
    $msg = 'Module manifest missing at {0}' -f $manifestPath
    Add-Log $msg
    [void]$errors.Add($msg)
    $manifest = $null
} else {
    try {
        if (Get-Command -Name Import-PowerShellDataFile -ErrorAction SilentlyContinue) {
            $manifest = Import-PowerShellDataFile -Path $manifestPath
        } else {
            $manifest = . $manifestPath
        }
        Add-Log 'Loaded module manifest.'
    } catch {
        $msg = 'Failed to load module manifest: {0}' -f $_.Exception.Message
        Add-Log $msg
        [void]$errors.Add($msg)
        $manifest = $null
    }
}

$modulesToImport = @()
if ($manifest) {
    if ($manifest.ModulesToImport) {
        $modulesToImport = @($manifest.ModulesToImport)
    } elseif ($manifest.Modules) {
        $modulesToImport = @($manifest.Modules)
    } else {
        $msg = 'Module manifest does not define ModulesToImport or Modules.'
        Add-Log $msg
        [void]$errors.Add($msg)
    }
}

$modulesDir = Join-Path $repoRoot 'Modules'
$importedModules = [System.Collections.Generic.List[string]]::new()

foreach ($moduleName in $modulesToImport) {
    $modulePath = Join-Path $modulesDir $moduleName
    if (-not (Test-Path -LiteralPath $modulePath)) {
        $msg = 'Module file missing: {0}' -f $modulePath
        Add-Log $msg
        [void]$errors.Add($msg)
        continue
    }
    try {
        Import-Module -Name $modulePath -Force -Global -ErrorAction Stop
        Add-Log ('Imported module: {0}' -f $moduleName)
        [void]$importedModules.Add($moduleName)
    } catch {
        $msg = 'Failed to import {0}: {1}' -f $moduleName, $_.Exception.Message
        Add-Log $msg
        [void]$errors.Add($msg)
    }
}

$expectedCommands = @(
    @{ Name = 'DeviceRepositoryModule\Get-SiteFromHostname'; Purpose = 'Device repository site resolver' },
    @{ Name = 'DeviceRepositoryModule\Update-GlobalInterfaceList'; Purpose = 'Device repository global interface refresh' },
    @{ Name = 'DeviceCatalogModule\Get-DeviceSummaries'; Purpose = 'Device catalog metadata loader' },
    @{ Name = 'FilterStateModule\Initialize-DeviceFilters'; Purpose = 'Filter state bootstrap' },
    @{ Name = 'FilterStateModule\Update-DeviceFilter'; Purpose = 'Filter state updater' },
    @{ Name = 'DeviceDetailsModule\Get-DeviceDetails'; Purpose = 'Device details retrieval' },
    @{ Name = 'DeviceInsightsModule\Update-SearchResults'; Purpose = 'Search results service' },
    @{ Name = 'DeviceInsightsModule\Update-Summary'; Purpose = 'Summary metrics service' },
    @{ Name = 'DeviceInsightsModule\Update-Alerts'; Purpose = 'Alerts service' },
    @{ Name = 'TemplatesModule\Get-ConfigurationTemplates'; Purpose = 'Template lookup' },
    @{ Name = 'InterfaceModule\Set-InterfaceViewData'; Purpose = 'Interface view binding' },
    @{ Name = 'ParserWorker\Invoke-StateTraceParsing'; Purpose = 'Parser invocation entry point' }
)

foreach ($expectation in $expectedCommands) {
    $cmd = Get-Command -Name $expectation.Name -ErrorAction SilentlyContinue
    if ($null -eq $cmd) {
        $msg = 'Missing command {0} ({1}).' -f $expectation.Name, $expectation.Purpose
        Add-Log $msg
        [void]$errors.Add($msg)
    } else {
        Add-Log ('Verified command: {0}' -f $expectation.Name)
    }
}

$mainWindowPs1 = Join-Path $repoRoot 'Main\MainWindow.ps1'
if (-not (Test-Path -LiteralPath $mainWindowPs1)) {
    $msg = 'MainWindow.ps1 not found at {0}' -f $mainWindowPs1
    Add-Log $msg
    [void]$errors.Add($msg)
} else {
    try {
        $mainWindowSource = Get-Content -LiteralPath $mainWindowPs1 -Raw
        [void][scriptblock]::Create($mainWindowSource)
        Add-Log 'Parsed MainWindow.ps1 successfully.'
    } catch {
        $msg = 'MainWindow.ps1 contains syntax errors: {0}' -f $_.Exception.Message
        Add-Log $msg
        [void]$errors.Add($msg)
    }
}

$mainWindowXaml = Join-Path $repoRoot 'Main\MainWindow.xaml'
if (-not (Test-Path -LiteralPath $mainWindowXaml)) {
    $msg = 'MainWindow.xaml not found at {0}' -f $mainWindowXaml
    Add-Log $msg
    [void]$errors.Add($msg)
} else {
    try {
        $xamlContent = Get-Content -LiteralPath $mainWindowXaml -Raw
        [xml]$null = $xamlContent
        Add-Log 'Validated MainWindow.xaml XML structure.'
    } catch {
        $msg = 'MainWindow.xaml is not well-formed XML: {0}' -f $_.Exception.Message
        Add-Log $msg
        [void]$errors.Add($msg)
    }
}

Add-Log ('Smoke test completed with {0} error(s).' -f $errors.Count)

Set-Content -LiteralPath $logPath -Value $logEntries -Encoding ASCII

$summary = [pscustomobject]@{
    Status = if ($errors.Count -eq 0) { 'Passed' } else { 'Failed' }
    ErrorCount = $errors.Count
    Errors = $errors.ToArray()
    LogPath = $logPath
    ImportedModules = $importedModules.ToArray()
}

$summary

if ($errors.Count -gt 0) {
    throw "MainWindow smoke test failed. Review $logPath for details."
}
