# Switch-Interact.ps1 - Send commands to switch and capture output
param(
    [string]$SerialPort = $env:STATETRACE_SERIAL_PORT,
    [Parameter(Mandatory=$true)]
    [string[]]$Commands,
    [int]$DelayMs = 2000,
    [switch]$Raw
)

if ([string]::IsNullOrWhiteSpace($SerialPort)) {
    throw 'SerialPort is required. Provide -SerialPort or set STATETRACE_SERIAL_PORT.'
}

$port = New-Object System.IO.Ports.SerialPort $SerialPort, 9600, 'None', 8, 'One'
$port.DtrEnable = $true
$port.RtsEnable = $true
$port.ReadTimeout = 5000
$port.Open()

$CR = [char]13
$allOutput = ""

function Send-Command {
    param([string]$cmd, [int]$wait = 2000)

    $port.Write("$cmd$CR")
    Start-Sleep -Milliseconds $wait

    # Read all available output, handling --More-- prompts
    $output = ""
    do {
        $chunk = $port.ReadExisting()
        $output += $chunk

        if ($chunk -match '--More--') {
            # Send space to continue
            $port.Write(" ")
            Start-Sleep -Milliseconds 500
        }
    } while ($chunk -match '--More--')

    return $output
}

try {
    # Clear buffer
    $null = $port.ReadExisting()

    # Disable paging first
    $null = Send-Command "terminal length 0" 1000

    foreach ($cmd in $Commands) {
        if (-not $Raw) {
            Write-Host "`n=== $cmd ===" -ForegroundColor Cyan
        }
        $output = Send-Command $cmd $DelayMs
        Write-Host $output
        $allOutput += "`n=== $cmd ===`n$output"
    }
}
finally {
    $port.Close()
}

return $allOutput

