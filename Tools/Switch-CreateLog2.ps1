# Switch-CreateLog2.ps1 - Create StateTrace-compatible log with proper prompts
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

    # The output includes the command we typed - just return it as-is
    # This will have the prompt and command at the start
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

    foreach ($cmd in $commands) {
        Write-Host "Capturing: $cmd" -ForegroundColor Cyan
        $output = Send-Command $cmd 6000

        # The output should already have the prompt and command
        # Just clean up double echo if needed
        [void]$log.AppendLine($output)
        [void]$log.AppendLine("")
    }

    # Write the combined log file
    $log.ToString() | Out-File -FilePath $OutputFile -Encoding UTF8
    Write-Host "`nLog file created: $OutputFile" -ForegroundColor Green

    # Show first few lines to verify format
    Write-Host "`nFirst 5 lines of log:" -ForegroundColor Yellow
    Get-Content $OutputFile -TotalCount 5
}
finally {
    $port.Close()
}

