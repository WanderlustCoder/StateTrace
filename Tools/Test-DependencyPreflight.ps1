[CmdletBinding()]
param(
    [string]$OutputPath,

    [switch]$RequireAllPass,

    [switch]$PassThru
)

<#
.SYNOPSIS
Validates runtime dependencies before packaging or deployment (ST-P-004).

.DESCRIPTION
Checks that the environment meets StateTrace requirements:
1. Execution policy allows script execution
2. Required PowerShell version (5.1+)
3. Required PowerShell modules are available
4. Access/Jet OLEDB providers are available

.PARAMETER OutputPath
If specified, writes the preflight report to a JSON file.

.PARAMETER RequireAllPass
If set, exits with code 1 when any check fails.

.PARAMETER PassThru
Returns the preflight result as an object.

.EXAMPLE
pwsh Tools\Test-DependencyPreflight.ps1 -RequireAllPass

.EXAMPLE
pwsh Tools\Test-DependencyPreflight.ps1 -OutputPath Logs\Reports\DependencyPreflight.json -PassThru
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Initialize result
$result = [pscustomobject]@{
    GeneratedAtUtc      = (Get-Date).ToUniversalTime().ToString('o')
    MachineName         = $env:COMPUTERNAME
    UserName            = $env:USERNAME
    OverallStatus       = 'Unknown'
    Checks              = @()
    PassCount           = 0
    FailCount           = 0
    WarningCount        = 0
    Message             = ''
}

Write-Host "`n=== Dependency Preflight (ST-P-004) ===" -ForegroundColor Cyan
Write-Host ("Timestamp: {0}" -f $result.GeneratedAtUtc) -ForegroundColor DarkGray
Write-Host ("Machine: {0}" -f $result.MachineName) -ForegroundColor DarkGray
Write-Host ""

# Helper function to add a check result
function Add-CheckResult {
    param(
        [string]$Name,
        [string]$Status,
        [string]$Message,
        [string]$Details
    )

    $check = [pscustomobject]@{
        Name    = $Name
        Status  = $Status
        Message = $Message
        Details = $Details
    }
    $script:result.Checks += $check

    $color = switch ($Status) {
        'Pass' { 'Green' }
        'Fail' { 'Red' }
        'Warning' { 'Yellow' }
        default { 'DarkGray' }
    }

    Write-Host ("  [{0}] {1}: {2}" -f $Status.ToUpper(), $Name, $Message) -ForegroundColor $color
    if ($Details) {
        Write-Host ("        {0}" -f $Details) -ForegroundColor DarkGray
    }
}

Write-Host "--- Running Checks ---" -ForegroundColor Yellow

# 1. PowerShell Version
$psVersion = $PSVersionTable.PSVersion
$psVersionStr = "{0}.{1}.{2}" -f $psVersion.Major, $psVersion.Minor, $psVersion.Build
if ($psVersion.Major -ge 5 -and $psVersion.Minor -ge 1) {
    Add-CheckResult -Name 'PowerShell Version' -Status 'Pass' -Message "PowerShell $psVersionStr detected" -Details "Minimum required: 5.1"
} elseif ($psVersion.Major -ge 7) {
    Add-CheckResult -Name 'PowerShell Version' -Status 'Pass' -Message "PowerShell $psVersionStr detected" -Details "PowerShell 7+ is supported"
} else {
    Add-CheckResult -Name 'PowerShell Version' -Status 'Fail' -Message "PowerShell $psVersionStr detected" -Details "Minimum required: 5.1. Upgrade PowerShell."
}

# 2. Execution Policy
try {
    $execPolicy = Get-ExecutionPolicy -Scope CurrentUser
    $machinePolicy = Get-ExecutionPolicy -Scope LocalMachine

    $allowedPolicies = @('Unrestricted', 'RemoteSigned', 'Bypass')
    if ($execPolicy -in $allowedPolicies -or $machinePolicy -in $allowedPolicies) {
        Add-CheckResult -Name 'Execution Policy' -Status 'Pass' -Message "CurrentUser=$execPolicy, LocalMachine=$machinePolicy" -Details "Script execution is allowed"
    } else {
        Add-CheckResult -Name 'Execution Policy' -Status 'Fail' -Message "CurrentUser=$execPolicy, LocalMachine=$machinePolicy" -Details "Run: Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned"
    }
} catch {
    Add-CheckResult -Name 'Execution Policy' -Status 'Warning' -Message "Could not determine execution policy" -Details $_.Exception.Message
}

# 3. Required PowerShell Modules
$requiredModules = @(
    @{ Name = 'Pester'; MinVersion = '3.4.0' }
)

foreach ($mod in $requiredModules) {
    try {
        $installed = Get-Module -ListAvailable -Name $mod.Name | Sort-Object Version -Descending | Select-Object -First 1
        if ($installed) {
            $minVer = [version]$mod.MinVersion
            if ($installed.Version -ge $minVer) {
                Add-CheckResult -Name "Module: $($mod.Name)" -Status 'Pass' -Message "Version $($installed.Version) installed" -Details "Minimum required: $($mod.MinVersion)"
            } else {
                Add-CheckResult -Name "Module: $($mod.Name)" -Status 'Warning' -Message "Version $($installed.Version) installed" -Details "Minimum recommended: $($mod.MinVersion). Consider upgrading."
            }
        } else {
            Add-CheckResult -Name "Module: $($mod.Name)" -Status 'Fail' -Message "Not installed" -Details "Install with: Install-Module $($mod.Name) -MinimumVersion $($mod.MinVersion)"
        }
    } catch {
        Add-CheckResult -Name "Module: $($mod.Name)" -Status 'Warning' -Message "Check failed" -Details $_.Exception.Message
    }
}

# 4. Access/Jet OLEDB Providers
$providers = @(
    @{ Name = 'ACE.OLEDB.12.0'; Description = 'Microsoft Access Database Engine 2010+' }
    @{ Name = 'ACE.OLEDB.16.0'; Description = 'Microsoft Access Database Engine 2016+' }
    @{ Name = 'Microsoft.Jet.OLEDB.4.0'; Description = 'Jet 4.0 (32-bit legacy)' }
)

$foundProvider = $false
$providerDetails = @()

foreach ($prov in $providers) {
    try {
        $progId = "Provider={0};Data Source=nul" -f $prov.Name
        $conn = New-Object -ComObject ADODB.Connection -ErrorAction Stop
        try {
            $conn.Open($progId)
            $conn.Close()
        } catch {
            # Provider exists but couldn't open - that's expected with nul path
        }
        [System.Runtime.Interopservices.Marshal]::ReleaseComObject($conn) | Out-Null
        $foundProvider = $true
        $providerDetails += "$($prov.Name) (Available)"
    } catch {
        $providerDetails += "$($prov.Name) (Not found)"
    }
}

if ($foundProvider) {
    Add-CheckResult -Name 'Access OLEDB Provider' -Status 'Pass' -Message "At least one provider available" -Details ($providerDetails -join '; ')
} else {
    Add-CheckResult -Name 'Access OLEDB Provider' -Status 'Fail' -Message "No Access OLEDB providers found" -Details "Install Microsoft Access Database Engine: https://www.microsoft.com/en-us/download/details.aspx?id=54920"
}

# 5. .NET Framework (for WPF)
try {
    $netVersion = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -ErrorAction SilentlyContinue).Release
    if ($netVersion) {
        $netVersionStr = if ($netVersion -ge 528040) { '4.8+' }
                        elseif ($netVersion -ge 461808) { '4.7.2+' }
                        elseif ($netVersion -ge 460798) { '4.7+' }
                        elseif ($netVersion -ge 394802) { '4.6.2+' }
                        else { '4.5+' }
        Add-CheckResult -Name '.NET Framework' -Status 'Pass' -Message ".NET Framework $netVersionStr detected" -Details "Release: $netVersion"
    } else {
        Add-CheckResult -Name '.NET Framework' -Status 'Warning' -Message "Could not detect .NET Framework version" -Details "WPF requires .NET Framework 4.5+"
    }
} catch {
    Add-CheckResult -Name '.NET Framework' -Status 'Warning' -Message "Could not check .NET Framework" -Details $_.Exception.Message
}

# 6. Disk Space (basic check)
try {
    $drive = (Get-Location).Drive
    if ($drive) {
        $freeGB = [math]::Round($drive.Free / 1GB, 2)
        if ($freeGB -ge 1) {
            Add-CheckResult -Name 'Disk Space' -Status 'Pass' -Message "$freeGB GB free on $($drive.Name):" -Details "Minimum recommended: 1 GB"
        } else {
            Add-CheckResult -Name 'Disk Space' -Status 'Warning' -Message "$freeGB GB free on $($drive.Name):" -Details "Low disk space may cause issues"
        }
    }
} catch {
    # Skip disk check if it fails
}

Write-Host ""

# Calculate summary
$result.PassCount = ($result.Checks | Where-Object { $_.Status -eq 'Pass' }).Count
$result.FailCount = ($result.Checks | Where-Object { $_.Status -eq 'Fail' }).Count
$result.WarningCount = ($result.Checks | Where-Object { $_.Status -eq 'Warning' }).Count

if ($result.FailCount -eq 0) {
    if ($result.WarningCount -eq 0) {
        $result.OverallStatus = 'Pass'
        $result.Message = "All $($result.PassCount) checks passed."
    } else {
        $result.OverallStatus = 'Warning'
        $result.Message = "$($result.PassCount) passed, $($result.WarningCount) warning(s)."
    }
    Write-Host ("PREFLIGHT: {0}" -f $result.Message) -ForegroundColor Green
} else {
    $result.OverallStatus = 'Fail'
    $result.Message = "$($result.FailCount) check(s) failed, $($result.PassCount) passed, $($result.WarningCount) warning(s)."
    Write-Host ("PREFLIGHT: {0}" -f $result.Message) -ForegroundColor Red
}

Write-Host ""

# Write output
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    try {
        $outputDir = Split-Path -Path $OutputPath -Parent
        if ($outputDir -and -not (Test-Path -LiteralPath $outputDir)) {
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        }
        $result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputPath -Encoding utf8
        Write-Host "Report saved to: $OutputPath" -ForegroundColor DarkCyan
    } catch {
        Write-Warning "Failed to save report: $($_.Exception.Message)"
    }
}

if ($PassThru.IsPresent) {
    return $result
}

if ($RequireAllPass.IsPresent -and $result.OverallStatus -eq 'Fail') {
    exit 1
}
