[CmdletBinding()]
param(
    [string]$WorkingDirectory = (Split-Path -Parent $PSScriptRoot),
    [string]$ScreenshotDir = 'docs\performance\screenshots',
    [string]$Timestamp = (Get-Date).ToString('yyyyMMdd-HHmmss'),
    [int]$WaitSeconds = 8
)

<#
.SYNOPSIS
Automates the WPF UI to collect Plan H evidence (scan/load, Interfaces, help) and screenshots.

.DESCRIPTION
Launches Main/MainWindow.ps1 in a new STA PowerShell, drives core UI actions via UI Automation
(Scan Logs, Load from DB, Interfaces tab, Help), and captures window/help screenshots to the
specified directory. Use on an interactive desktop; not suitable for headless CI.

.EXAMPLE
pwsh -NoLogo -File Tools\AutoCapture-PlanHUI.ps1 -ScreenshotDir docs\performance\screenshots -Timestamp 20251126-220000
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName UIAutomationClient

function Start-MainWindowProcess {
    param([string]$WorkingDirectory)
    $main = Join-Path $WorkingDirectory 'Main\MainWindow.ps1'
    if (-not (Test-Path -LiteralPath $main)) { throw "Main window script not found at $main" }
    $argsList = @('-NoLogo','-NoProfile','-Sta','-File',"`"$main`"")
    $proc = Start-Process -FilePath 'powershell.exe' -ArgumentList $argsList -WorkingDirectory $WorkingDirectory -PassThru
    return $proc
}

function Get-MainWindow {
    param([int]$ProcessId, [int]$TimeoutSeconds = 20)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $root = [System.Windows.Automation.AutomationElement]::RootElement
        $cond = [System.Windows.Automation.Condition]::TrueCondition
        $windows = $root.FindAll([System.Windows.Automation.TreeScope]::Children, $cond)
        foreach ($w in $windows) {
            try {
                $pid = $w.GetCurrentPropertyValue([System.Windows.Automation.AutomationElement]::ProcessIdProperty)
                if ($pid -eq $ProcessId) { return $w }
            } catch {}
        }
        Start-Sleep -Milliseconds 500
    }
    throw "Main window for process $ProcessId not found."
}

function Invoke-ButtonByName {
    param([System.Windows.Automation.AutomationElement]$Window, [string]$Name)
    $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, $Name)
    $btn = $Window.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
    if ($btn) {
        $invoke = $btn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
        $invoke.Invoke()
        Start-Sleep -Milliseconds 500
    } else {
        Write-Warning "Button '$Name' not found."
    }
}

function Select-TabByName {
    param([System.Windows.Automation.AutomationElement]$Window, [string]$Name)
    $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, $Name)
    $tabItem = $Window.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
    if ($tabItem) {
        $sel = $tabItem.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
        $sel.Select()
        Start-Sleep -Milliseconds 500
    } else {
        Write-Warning "Tab '$Name' not found."
    }
}

function Capture-WindowScreenshot {
    param([System.Windows.Automation.AutomationElement]$Window, [string]$Path)
    $rect = $Window.Current.BoundingRectangle
    $bmp = New-Object System.Drawing.Bitmap ([int]$rect.Width), ([int]$rect.Height)
    $gfx = [System.Drawing.Graphics]::FromImage($bmp)
    $gfx.CopyFromScreen([int]$rect.Left, [int]$rect.Top, 0, 0, $bmp.Size)
    $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $gfx.Dispose(); $bmp.Dispose()
}

if (-not (Test-Path -LiteralPath $ScreenshotDir)) {
    New-Item -ItemType Directory -Path $ScreenshotDir -Force | Out-Null
}

$proc = Start-MainWindowProcess -WorkingDirectory $WorkingDirectory
Start-Sleep -Seconds $WaitSeconds
$window = Get-MainWindow -ProcessId $proc.Id

# Interact: Scan Logs, Load from DB, Interfaces tab, Help
Invoke-ButtonByName -Window $window -Name 'Scan Logs'
Invoke-ButtonByName -Window $window -Name 'Load from DB'
Select-TabByName -Window $window -Name 'Interfaces'

$mainShot = Join-Path $ScreenshotDir ("onboarding-{0}-interfaces.png" -f $Timestamp)
Capture-WindowScreenshot -Window $window -Path $mainShot

# Help window
Invoke-ButtonByName -Window $window -Name 'Help'
Start-Sleep -Seconds 2
$helpWindow = $null
try {
    $root = [System.Windows.Automation.AutomationElement]::RootElement
    $helpCond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, 'Help')
    $helpWindow = $root.FindFirst([System.Windows.Automation.TreeScope]::Children, $helpCond)
} catch {}
if ($helpWindow) {
    $helpShot = Join-Path $ScreenshotDir ("onboarding-{0}-help.png" -f $Timestamp)
    Capture-WindowScreenshot -Window $helpWindow -Path $helpShot
} else {
    Write-Warning "Help window not found; screenshot skipped."
}

# Freshness tooltip requires hover; instead capture main window again as toolbar evidence
$toolbarShot = Join-Path $ScreenshotDir ("onboarding-{0}-toolbar.png" -f $Timestamp)
Capture-WindowScreenshot -Window $window -Path $toolbarShot

Write-Host "[PlanH] UI automation run complete. Screenshots under $ScreenshotDir." -ForegroundColor Green
