# Switch-Capture.ps1 - Capture switch logs for StateTrace
param(
    [string]$SerialPort = $env:STATETRACE_SERIAL_PORT,
    [string]$OutputDir
)

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $repoRoot 'Tests\Fixtures\LiveSwitch'
}
if ([string]::IsNullOrWhiteSpace($SerialPort)) {
    throw 'SerialPort is required. Provide -SerialPort or set STATETRACE_SERIAL_PORT.'
}

$port = New-Object System.IO.Ports.SerialPort $SerialPort, 9600, 'None', 8, 'One'
$port.DtrEnable = $true
$port.RtsEnable = $true
$port.ReadTimeout = 10000
$port.Open()

$CR = [char]13

# Ensure output directory exists
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

function Send-Command {
    param([string]$cmd, [int]$wait = 3000)
    $port.DiscardInBuffer()
    $port.Write("$cmd$CR")
    Start-Sleep -Milliseconds $wait

    $output = ""
    $lastRead = Get-Date
    do {
        $chunk = $port.ReadExisting()
        if ($chunk) {
            $output += $chunk
            $lastRead = Get-Date
            # Handle --More-- prompts
            if ($chunk -match '--More--') {
                $port.Write(" ")
                Start-Sleep -Milliseconds 300
            }
        }
        Start-Sleep -Milliseconds 100
    } while (((Get-Date) - $lastRead).TotalMilliseconds -lt 1000)

    return $output
}

try {
    $null = $port.ReadExisting()
    Send-Command "terminal length 0" 1000

    $commands = @(
        @{ Name = "show_version"; Cmd = "show version" },
        @{ Name = "show_running-config"; Cmd = "show running-config" },
        @{ Name = "show_interfaces_status"; Cmd = "show interfaces status" },
        @{ Name = "show_interfaces"; Cmd = "show interfaces" },
        @{ Name = "show_vlan_brief"; Cmd = "show vlan brief" },
        @{ Name = "show_spanning-tree"; Cmd = "show spanning-tree" },
        @{ Name = "show_mac_address-table"; Cmd = "show mac address-table" },
        @{ Name = "show_cdp_neighbors"; Cmd = "show cdp neighbors" },
        @{ Name = "show_cdp_neighbors_detail"; Cmd = "show cdp neighbors detail" },
        @{ Name = "show_inventory"; Cmd = "show inventory" },
        @{ Name = "show_power_inline"; Cmd = "show power inline" },
        @{ Name = "show_ip_interface_brief"; Cmd = "show ip interface brief" },
        @{ Name = "show_logging"; Cmd = "show logging" }
    )

    foreach ($item in $commands) {
        Write-Host "Capturing: $($item.Cmd)" -ForegroundColor Cyan
        $output = Send-Command $item.Cmd 5000
        $filePath = Join-Path $OutputDir "$($item.Name).txt"
        $output | Out-File -FilePath $filePath -Encoding UTF8
        Write-Host "  Saved to: $filePath" -ForegroundColor Green
    }

    Write-Host "`nAll captures complete!" -ForegroundColor Green
    Write-Host "Output directory: $OutputDir"
}
finally {
    $port.Close()
}

