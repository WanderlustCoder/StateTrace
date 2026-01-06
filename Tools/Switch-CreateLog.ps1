# Switch-CreateLog.ps1 - Create StateTrace-compatible log file from switch
param(
    [string]$OutputFile = "C:\Users\Werem\Projects\StateTrace\Tests\Fixtures\LiveSwitch\LAB-C9200L-AS-01.log"
)

$port = New-Object System.IO.Ports.SerialPort 'COM8', 9600, 'None', 8, 'One'
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
        "show interface status",
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

        # Clean up output - remove the echo of the command at the start if duplicated
        $lines = $output -split "`r?`n"
        $cleanLines = @()
        $foundCmd = $false
        foreach ($line in $lines) {
            if (-not $foundCmd -and $line -match [regex]::Escape($cmd)) {
                $foundCmd = $true
                $cleanLines += $line
            } elseif ($foundCmd) {
                $cleanLines += $line
            }
        }
        $cleanOutput = $cleanLines -join "`r`n"

        [void]$log.AppendLine($cleanOutput)
        [void]$log.AppendLine("")
    }

    # Write the combined log file
    $log.ToString() | Out-File -FilePath $OutputFile -Encoding UTF8
    Write-Host "`nLog file created: $OutputFile" -ForegroundColor Green

    # Also create a copy in the Data folder structure for ingestion
    $dataDir = "C:\Users\Werem\Projects\StateTrace\Data\LAB"
    if (-not (Test-Path $dataDir)) {
        New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
    }
    $dataFile = Join-Path $dataDir "LAB-C9200L-AS-01.log"
    $log.ToString() | Out-File -FilePath $dataFile -Encoding UTF8
    Write-Host "Also copied to: $dataFile" -ForegroundColor Green
}
finally {
    $port.Close()
}
