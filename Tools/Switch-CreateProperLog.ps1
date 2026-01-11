# Switch-CreateProperLog.ps1 - Create StateTrace-compatible log with proper prompt format
param(
    [string]$SerialPort = $env:STATETRACE_SERIAL_PORT,
    [string]$OutputFile
)

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($OutputFile)) {
    $OutputFile = Join-Path $repoRoot 'Tests\Fixtures\LiveSwitch\LAB-C9200L-AS-01.log'
}
if ([string]::IsNullOrWhiteSpace($SerialPort)) {
    throw 'SerialPort is required. Provide -SerialPort or set STATETRACE_SERIAL_PORT.'
}

$outputDir = Split-Path -Parent $OutputFile
if ($outputDir -and -not (Test-Path -LiteralPath $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$port = New-Object System.IO.Ports.SerialPort $SerialPort, 9600, 'None', 8, 'One'
$port.DtrEnable = $true
$port.RtsEnable = $true
$port.ReadTimeout = 15000
$port.Open()

$CR = [char]13
$log = [System.Text.StringBuilder]::new()

function Send-Command {
    param([string]$cmd, [int]$wait = 5000)
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
            if ($chunk -match '--More--') {
                $port.Write(" ")
                Start-Sleep -Milliseconds 300
            }
        }
        Start-Sleep -Milliseconds 100
    } while (((Get-Date) - $lastRead).TotalMilliseconds -lt 2000)

    return $output
}

try {
    $null = $port.ReadExisting()
    Send-Command "terminal length 0" 1000

    # Commands to capture for StateTrace
    $commands = @(
        "show version",
        "show running-config",
        "show interfaces status",
        "show mac address-table",
        "show spanning-tree",
        "show vlan brief",
        "show cdp neighbors detail",
        "show power inline",
        "show ip interface brief"
    )

    # First, get the hostname from the prompt
    $port.Write("$CR")
    Start-Sleep -Milliseconds 1000
    $promptOutput = $port.ReadExisting()
    $hostname = "Switch"
    if ($promptOutput -match '([^\r\n\s]+)#') {
        $hostname = $matches[1]
    }
    Write-Host "Detected hostname: $hostname" -ForegroundColor Green

    foreach ($cmd in $commands) {
        Write-Host "Capturing: $cmd" -ForegroundColor Cyan
        $rawOutput = Send-Command $cmd 6000

        # The serial output already includes the echoed command with prompt
        # Format: command<CR><output>prompt#
        # We need: prompt#command<CR><output>

        # Parse the output - find where the actual command output starts
        $lines = $rawOutput -split "`r?`n"

        # Build the properly formatted block
        # First line should be: hostname#command
        [void]$log.AppendLine("$hostname#$cmd")

        # Skip the first line (command echo) and process the rest
        $skipFirst = $true
        foreach ($line in $lines) {
            if ($skipFirst) {
                $skipFirst = $false
                continue
            }
            # Skip the final prompt line (we'll include it implicitly by the next command)
            if ($line -match "^$([regex]::Escape($hostname))#\s*$") {
                continue
            }
            [void]$log.AppendLine($line)
        }
        [void]$log.AppendLine("")
    }

    # Write the combined log file
    $log.ToString() | Out-File -FilePath $OutputFile -Encoding UTF8
    Write-Host "`nLog file created: $OutputFile" -ForegroundColor Green

    # Also create a copy in the Data folder structure for ingestion
    $dataDir = Join-Path $repoRoot 'Data\LAB'
    if (-not (Test-Path $dataDir)) {
        New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
    }
    $dataFile = Join-Path $dataDir "LAB-C9200L-AS-01.log"
    $log.ToString() | Out-File -FilePath $dataFile -Encoding UTF8
    Write-Host "Also copied to: $dataFile" -ForegroundColor Green

    # Show first 15 lines to verify format
    Write-Host "`nFirst 15 lines of log:" -ForegroundColor Yellow
    Get-Content $OutputFile -TotalCount 15
}
finally {
    $port.Close()
}

