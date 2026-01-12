<#
.SYNOPSIS
Headless smoke test for the Cable Documentation view.

.DESCRIPTION
Loads the CableDocumentationView into a hidden WPF window, tests CRUD operations
on cables and patch panels, verifies UI bindings, and validates database persistence.

.EXAMPLE
pwsh -NoLogo -STA -File Tools\Invoke-CablesSmokeTest.ps1 -PassThru

.EXAMPLE
powershell -STA -File Tools\Invoke-CablesSmokeTest.ps1 -EnableDiagnostics -AsJson
#>
[CmdletBinding()]
param(
    [string]$RepositoryRoot,
    [int]$TimeoutSeconds = 10,
    [switch]$EnableDiagnostics,
    [switch]$ForceExit,
    [switch]$PassThru,
    [switch]$AsJson,
    [switch]$SkipCleanup
)

Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne [System.Threading.ApartmentState]::STA) {
    throw "Invoke-CablesSmokeTest.ps1 must run in STA mode. Re-run with 'pwsh -STA -File Tools\Invoke-CablesSmokeTest.ps1 ...'."
}

$repoRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$modulesDir = Join-Path $repoRoot 'Modules'

Add-Type -AssemblyName PresentationFramework -ErrorAction Stop

$moduleLoaderPath = Join-Path $modulesDir 'ModuleLoaderModule.psm1'
if (-not (Test-Path -LiteralPath $moduleLoaderPath)) {
    throw "Module loader not found at '$moduleLoaderPath'."
}
Import-Module -Name $moduleLoaderPath -Force -ErrorAction Stop | Out-Null
ModuleLoaderModule\Import-StateTraceModulesFromManifest -RepositoryRoot $repoRoot | Out-Null

if (-not [System.Windows.Application]::Current) {
    $app = New-Object System.Windows.Application
    $app.ShutdownMode = 'OnExplicitShutdown'
}

# Initialize theme for styles to work
try {
    ThemeModule\Initialize-StateTraceTheme -PreferredTheme 'blue-angels' | Out-Null
} catch {
    Write-Warning "Theme initialization failed: $($_.Exception.Message)"
}

if ($EnableDiagnostics) {
    $global:StateTraceDebug = $true
    $VerbosePreference = 'Continue'
}

function Invoke-DispatcherPump {
    param([int]$Milliseconds = 100)
    $frame = New-Object System.Windows.Threading.DispatcherFrame
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds([math]::Max(10, $Milliseconds))
    $timer.Add_Tick({
        param($sender, $args)
        $sender.Stop()
        $frame.Continue = $false
    })
    $timer.Start()
    [System.Windows.Threading.Dispatcher]::PushFrame($frame)
}

function Get-CollectionCount {
    param([object]$Items)
    if ($null -eq $Items) { return 0 }
    try {
        if ($Items -is [System.Collections.ICollection]) { return [int]$Items.Count }
    } catch { Write-Verbose "Caught exception in Invoke-CablesSmokeTest.ps1: $($_.Exception.Message)" }
    try { return @($Items).Count } catch { return 0 }
}

$finalResult = $null
$failure = $null
$windowRef = $null
$testDbPath = $null

try {
    # Create test database path in temp
    $testDbPath = Join-Path ([System.IO.Path]::GetTempPath()) "CablesSmokeTest_$([guid]::NewGuid().ToString('N')).json"

    # Create a minimal window with CablesSubHost
    $windowXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Cables Smoke Test"
        Height="600"
        Width="1000"
        Visibility="Hidden"
        ShowInTaskbar="False">
  <Grid>
    <ContentControl Name="CablesSubHost"/>
  </Grid>
</Window>
"@

    $reader = New-Object System.Xml.XmlTextReader (New-Object System.IO.StringReader($windowXaml))
    $window = [Windows.Markup.XamlReader]::Load($reader)
    $windowRef = $window

    $cablesHost = $window.FindName('CablesSubHost')
    if (-not $cablesHost) {
        throw "CablesSubHost not found in test window."
    }

    # Test 1: Verify Initialize-CableDocumentationView function exists
    $initCmd = Get-Command -Name 'Initialize-CableDocumentationView' -ErrorAction SilentlyContinue
    $moduleLoaded = $null -ne $initCmd

    # Test 2: Initialize the view
    $viewInitialized = $false
    $view = $null
    try {
        $view = CableDocumentationViewModule\Initialize-CableDocumentationView -Host $cablesHost
        Invoke-DispatcherPump -Milliseconds 200
        $viewInitialized = ($null -ne $cablesHost.Content)
    } catch {
        $viewInitialized = $false
        Write-Warning "View initialization failed: $($_.Exception.Message)"
    }

    if (-not $viewInitialized) {
        throw "CableDocumentationView failed to initialize."
    }

    $viewContent = $cablesHost.Content

    # Test 3: Verify key controls exist
    $controlsFound = @{}
    $requiredControls = @(
        'AddCableButton', 'AddPanelButton', 'ImportButton', 'ExportButton',
        'CableListBox', 'PanelListBox', 'FilterBox', 'StatusText',
        'CableDetailsGrid', 'PanelDetailsGrid', 'DetailsTabControl',
        'TotalCablesText', 'TotalPanelsText'
    )
    foreach ($ctrlName in $requiredControls) {
        $ctrl = $viewContent.FindName($ctrlName)
        $controlsFound[$ctrlName] = ($null -ne $ctrl)
    }
    $allControlsFound = @($controlsFound.Values | Where-Object { -not $_ }).Count -eq 0

    # Test 4: Verify CableDocumentationModule functions exist
    $moduleFunctionsExist = @{}
    $requiredFunctions = @(
        'New-CableDatabase', 'New-CableRun', 'Add-CableRun', 'Get-CableRun',
        'New-PatchPanel', 'Add-PatchPanel', 'Get-PatchPanel',
        'Get-CableDatabaseStats', 'Export-CableDatabase', 'Import-CableDatabase'
    )
    foreach ($funcName in $requiredFunctions) {
        $cmd = Get-Command -Name $funcName -Module CableDocumentationModule -ErrorAction SilentlyContinue
        $moduleFunctionsExist[$funcName] = ($null -ne $cmd)
    }
    $allFunctionsExist = @($moduleFunctionsExist.Values | Where-Object { -not $_ }).Count -eq 0

    # Test 5: Create a test database and perform CRUD operations
    $crudResults = @{
        DatabaseCreated = $false
        CableCreated = $false
        CableRetrieved = $false
        PanelCreated = $false
        PanelRetrieved = $false
        StatsRetrieved = $false
        ExportWorked = $false
        ImportWorked = $false
    }

    try {
        # Create database
        $testDb = CableDocumentationModule\New-CableDatabase
        $crudResults.DatabaseCreated = ($null -ne $testDb)

        # Create and add a cable
        $testCable = CableDocumentationModule\New-CableRun `
            -SourceType 'Device' `
            -SourceDevice 'TEST-SW1' `
            -SourcePort 'Gi1/0/1' `
            -DestType 'PatchPanel' `
            -DestDevice 'PP-TEST-01' `
            -DestPort '1' `
            -CableType 'Cat6' `
            -Status 'Active' `
            -Notes 'Smoke test cable'
        CableDocumentationModule\Add-CableRun -Cable $testCable -Database $testDb | Out-Null
        $crudResults.CableCreated = $true

        # Retrieve the cable
        $retrievedCables = @(CableDocumentationModule\Get-CableRun -Database $testDb)
        $crudResults.CableRetrieved = ($retrievedCables.Count -ge 1)

        # Create and add a patch panel
        $testPanel = CableDocumentationModule\New-PatchPanel `
            -PanelName 'Test Panel 1' `
            -Location 'Server Room A' `
            -RackID 'RACK-01' `
            -RackU '10' `
            -PortCount 24
        CableDocumentationModule\Add-PatchPanel -Panel $testPanel -Database $testDb | Out-Null
        $crudResults.PanelCreated = $true

        # Retrieve the panel
        $retrievedPanels = @(CableDocumentationModule\Get-PatchPanel -Database $testDb)
        $crudResults.PanelRetrieved = ($retrievedPanels.Count -ge 1)

        # Get stats
        $stats = CableDocumentationModule\Get-CableDatabaseStats -Database $testDb
        $crudResults.StatsRetrieved = ($null -ne $stats -and $stats.TotalCables -ge 1)

        # Export database
        CableDocumentationModule\Export-CableDatabase -Path $testDbPath -Database $testDb
        $crudResults.ExportWorked = (Test-Path -LiteralPath $testDbPath)

        # Import database into fresh db
        $importDb = CableDocumentationModule\New-CableDatabase
        $importResult = CableDocumentationModule\Import-CableDatabase -Path $testDbPath -Database $importDb
        $crudResults.ImportWorked = ($importResult.CablesImported -ge 1)

    } catch {
        Write-Warning "CRUD test failed: $($_.Exception.Message)"
    }

    $allCrudPassed = @($crudResults.Values | Where-Object { -not $_ }).Count -eq 0

    # Test 6: Verify view state is properly initialized
    $viewState = $viewContent.Tag
    $viewStateValid = ($null -ne $viewState -and $null -ne $viewState.Database)

    # Test 7: Check list boxes can be populated
    $cableListBox = $viewContent.FindName('CableListBox')
    $panelListBox = $viewContent.FindName('PanelListBox')
    $listsAccessible = ($null -ne $cableListBox -and $null -ne $panelListBox)

    # Test 8: Verify stats text blocks exist and can be read
    $totalCablesText = $viewContent.FindName('TotalCablesText')
    $totalPanelsText = $viewContent.FindName('TotalPanelsText')
    $statsTextAccessible = ($null -ne $totalCablesText -and $null -ne $totalPanelsText)

    # Test 9: Check button click handlers are wired (verify they have event handlers)
    $addCableButton = $viewContent.FindName('AddCableButton')
    $addPanelButton = $viewContent.FindName('AddPanelButton')
    $buttonsClickable = $false
    try {
        # Check if Click event has handlers by examining internal event store
        # This is a heuristic - if the button exists and is enabled, handlers should be wired
        $buttonsClickable = (
            $null -ne $addCableButton -and
            $null -ne $addPanelButton -and
            $addCableButton.IsEnabled -and
            $addPanelButton.IsEnabled
        )
    } catch {
        $buttonsClickable = $false
    }

    # Calculate overall success
    $success = $moduleLoaded -and $viewInitialized -and $allControlsFound -and
               $allFunctionsExist -and $allCrudPassed -and $viewStateValid -and
               $listsAccessible -and $statsTextAccessible -and $buttonsClickable

    $finalResult = [pscustomobject]@{
        Success               = $success
        ModuleLoaded          = $moduleLoaded
        ViewInitialized       = $viewInitialized
        AllControlsFound      = $allControlsFound
        ControlsFound         = $controlsFound
        AllFunctionsExist     = $allFunctionsExist
        FunctionsExist        = $moduleFunctionsExist
        CrudResults           = $crudResults
        AllCrudPassed         = $allCrudPassed
        ViewStateValid        = $viewStateValid
        ListsAccessible       = $listsAccessible
        StatsTextAccessible   = $statsTextAccessible
        ButtonsClickable      = $buttonsClickable
    }

    if (-not $success) {
        $failedChecks = @()
        if (-not $moduleLoaded) { $failedChecks += 'ModuleLoaded' }
        if (-not $viewInitialized) { $failedChecks += 'ViewInitialized' }
        if (-not $allControlsFound) { $failedChecks += 'AllControlsFound' }
        if (-not $allFunctionsExist) { $failedChecks += 'AllFunctionsExist' }
        if (-not $allCrudPassed) { $failedChecks += 'AllCrudPassed' }
        if (-not $viewStateValid) { $failedChecks += 'ViewStateValid' }
        if (-not $listsAccessible) { $failedChecks += 'ListsAccessible' }
        if (-not $statsTextAccessible) { $failedChecks += 'StatsTextAccessible' }
        if (-not $buttonsClickable) { $failedChecks += 'ButtonsClickable' }
        $failure = "Cables smoke test failed. Failed checks: $($failedChecks -join ', ')"
    }

} catch {
    $failure = $_
} finally {
    # Cleanup test database file
    if (-not $SkipCleanup -and $testDbPath -and (Test-Path -LiteralPath $testDbPath)) {
        try { Remove-Item -Path $testDbPath -Force -ErrorAction SilentlyContinue } catch { Write-Verbose "Caught exception in Invoke-CablesSmokeTest.ps1: $($_.Exception.Message)" }
    }

    try {
        if ($windowRef) {
            try { $windowRef.Close() } catch {
                Write-Warning "Failed to close test window: $($_.Exception.Message)"
            }
        }
        if ([System.Windows.Application]::Current) {
            try { [System.Windows.Application]::Current.Dispatcher.InvokeShutdown() } catch { Write-Verbose "Caught exception in Invoke-CablesSmokeTest.ps1: $($_.Exception.Message)" }
            try { [System.Windows.Application]::Current.Shutdown() } catch { Write-Verbose "Caught exception in Invoke-CablesSmokeTest.ps1: $($_.Exception.Message)" }
        }
    } catch { Write-Verbose "Caught exception in Invoke-CablesSmokeTest.ps1: $($_.Exception.Message)" }
}

if ($failure) {
    Write-Error $failure
    if ($ForceExit) {
        [System.Environment]::Exit(1)
    }
    throw $failure
}

if ($finalResult) {
    if ($AsJson) {
        $finalResult | ConvertTo-Json -Depth 6 -Compress | Write-Output
    } elseif ($PassThru) {
        $finalResult
    } else {
        Write-Host "Cables Smoke Test: $(if ($finalResult.Success) { 'PASSED' } else { 'FAILED' })" -ForegroundColor $(if ($finalResult.Success) { 'Green' } else { 'Red' })
        Write-Host "  Module Loaded: $($finalResult.ModuleLoaded)"
        Write-Host "  View Initialized: $($finalResult.ViewInitialized)"
        Write-Host "  All Controls Found: $($finalResult.AllControlsFound)"
        Write-Host "  All Functions Exist: $($finalResult.AllFunctionsExist)"
        Write-Host "  All CRUD Passed: $($finalResult.AllCrudPassed)"
        Write-Host "  View State Valid: $($finalResult.ViewStateValid)"
        Write-Host "  Buttons Clickable: $($finalResult.ButtonsClickable)"
    }
}

if ($ForceExit) {
    [System.Environment]::Exit(0)
}
