<#
    DebugDeviceSummary.ps1

    This script provides diagnostic output for the contents of the
    `DeviceSummary` table in the StateTrace Access database.
    See usage and description above.
#>

$projectRoot = Split-Path $MyInvocation.MyCommand.Path -Parent
$databasePath = Join-Path $projectRoot "Data\StateTrace.accdb"
$dbModulePath = Join-Path $projectRoot "Modules\DatabaseModule.psm1"

try {
    # Import the DatabaseModule if available
    if (Test-Path $dbModulePath) {
        Import-Module $dbModulePath -Global -ErrorAction Stop
    } else {
        Write-Warning "Database module not found at $dbModulePath"
        return
    }

$sql = @"
SELECT Hostname, Make, Model, Uptime, Ports, AuthDefaultVLAN, Building, Room
FROM DeviceSummary;
"@

    #
    # Invoke the database query using the correct parameter names.  The
    # DatabaseModule exposes `Invoke-DbQuery` with `-DatabasePath` and
    # `-Sql` parameters (see Modules/DatabaseModule.psm1).  Using the wrong
    # parameter names (`-DbPath` and `-Query`) will cause PowerShell to
    # throw an error because they don't exist on the function.  Pass the
    # database path and SQL query by name to avoid positional mistakes.
    $rows = Invoke-DbQuery -DatabasePath $databasePath -Sql $sql

    if (-not $rows -or $rows.Count -eq 0) {
        Write-Warning "No rows returned from DeviceSummary. Ensure the database path is correct and the parser has populated the summary table."
        return
    }

    Write-Host "DeviceSummary rows ($($rows.Count)):" -ForegroundColor Cyan

    foreach ($row in $rows) {
        # Use safe property access and trim.  Note: `$Host` is a built‑in
        # read‑only variable in PowerShell 5; avoid clashing with it by
        # using a different variable name.  `$hostnameStr` holds the
        # original hostname (or empty string), `$trimmedHost` its trimmed
        # form, and `$hostDisplay` the display version (with <BLANK> when empty).
        $hostnameStr  = if ($null -ne $row.Hostname) { [string]$row.Hostname } else { "" }
        $trimmedHost  = $hostnameStr.Trim()
        $hostDisplay  = if ([string]::IsNullOrWhiteSpace($hostnameStr)) { "<BLANK>" } else { $hostnameStr }

        Write-Host ("Hostname:'{0}', Trimmed:'{1}', Make:'{2}', Model:'{3}', Uptime:'{4}', Ports:'{5}', AuthDefaultVLAN:'{6}', Building:'{7}', Room:'{8}'" -f `
            $hostDisplay,
            $trimmedHost,
            $row.Make,
            $row.Model,
            $row.Uptime,
            $row.Ports,
            $row.AuthDefaultVLAN,
            $row.Building,
            $row.Room
        )
    }
}
catch {
    Write-Warning "Failed to query DeviceSummary: $($_.Exception.Message)"
}
