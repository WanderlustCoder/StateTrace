# Switch-Session.ps1 - Interactive session with serial switch
param(
    [string]$SerialPort = $env:STATETRACE_SERIAL_PORT,
    [string]$Command = "",
    [int]$WaitMs = 2000
)

if ([string]::IsNullOrWhiteSpace($SerialPort)) {
    throw 'SerialPort is required. Provide -SerialPort or set STATETRACE_SERIAL_PORT.'
}

$port = New-Object System.IO.Ports.SerialPort $SerialPort, 9600, 'None', 8, 'One'
$port.ReadTimeout = 5000
$port.WriteTimeout = 3000

try {
    $port.Open()

    # Clear buffer
    $null = $port.ReadExisting()

    if ($Command -eq "") {
        # Just read current state
        $port.WriteLine("")
        Start-Sleep -Milliseconds 1000
        $port.WriteLine("")
        Start-Sleep -Milliseconds $WaitMs
        $output = $port.ReadExisting()
        Write-Host $output
    }
    else {
        # Send specific command
        $port.WriteLine($Command)
        Start-Sleep -Milliseconds $WaitMs
        $output = $port.ReadExisting()
        Write-Host $output
    }
}
catch {
    Write-Error "Error: $($_.Exception.Message)"
}
finally {
    if ($port.IsOpen) {
        $port.Close()
    }
}

