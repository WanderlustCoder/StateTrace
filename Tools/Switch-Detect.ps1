# Switch-Detect.ps1 - Try different baud rates to find the switch
$baudRates = @(9600, 115200, 38400, 19200, 57600)

foreach ($baud in $baudRates) {
    Write-Host "`n=== Trying baud rate: $baud ==="

    try {
        $port = New-Object System.IO.Ports.SerialPort 'COM8', $baud, 'None', 8, 'One'
        $port.ReadTimeout = 2000
        $port.WriteTimeout = 2000
        $port.DtrEnable = $true
        $port.RtsEnable = $true
        $port.Open()

        # Clear buffer
        $null = $port.ReadExisting()

        # Send enters
        $port.WriteLine("")
        $port.WriteLine("")
        $port.WriteLine("")
        Start-Sleep -Milliseconds 1500

        $output = $port.ReadExisting()

        if ($output -and $output.Length -gt 5) {
            Write-Host "Got output at $baud baud:"
            Write-Host $output

            # Check if it looks like valid CLI output
            if ($output -match ">" -or $output -match "#" -or $output -match "Switch" -or $output -match "Router" -or $output -match "%" -or $output -match "cisco" -or $output -match "dialog") {
                Write-Host "`n*** SUCCESS - Found valid output at $baud baud ***"
                $port.Close()
                break
            }
        }
        else {
            Write-Host "No meaningful output"
        }

        $port.Close()
    }
    catch {
        Write-Host "Error at $baud : $($_.Exception.Message)"
    }
}

Write-Host "`nDone testing baud rates"
