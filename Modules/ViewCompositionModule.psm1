Set-StrictMode -Version Latest

function Set-StView {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Windows.Window]$Window,
        [Parameter(Mandatory)][string]$ScriptDir,
        [string]$ViewName,
        [Parameter(Mandatory)][string]$HostControlName,
        [string]$GlobalVariableName,
        [switch]$PassThruHost
    )

    if ([string]::IsNullOrWhiteSpace($ViewName)) {
        if ($HostControlName) {
            $ViewName = ($HostControlName -replace 'Host$', '')
        }
        if ([string]::IsNullOrWhiteSpace($ViewName)) {
            throw "Set-StView requires a ViewName or a HostControlName that ends with 'Host'."
        }
    }

    $viewPath = Join-Path $ScriptDir (Join-Path '..\Views' ("{0}.xaml" -f $ViewName))
    if (-not (Test-Path -LiteralPath $viewPath)) {
        Write-Warning ("{0}.xaml not found at {1}" -f $ViewName, $viewPath)
        return $null
    }

    try {
        $xaml   = Get-Content -LiteralPath $viewPath -Raw
        $reader = New-Object System.Xml.XmlTextReader (New-Object System.IO.StringReader($xaml))
        try {
            $view = [Windows.Markup.XamlReader]::Load($reader)
        } finally {
            if ($reader) { $reader.Close(); $reader.Dispose() }
        }
    } catch {
        Write-Warning ("Failed to load {0}.xaml: {1}" -f $ViewName, $_.Exception.Message)
        return $null
    }

    $host = $Window.FindName($HostControlName)
    if ($host -is [System.Windows.Controls.ContentControl]) {
        $host.Content = $view
    } else {
        Write-Warning ("Could not find ContentControl '{0}'" -f $HostControlName)
        return $null
    }

    if ($GlobalVariableName) {
        Set-Variable -Scope Global -Name $GlobalVariableName -Value $view -Force
    }

    if ($PassThruHost) {
        return [PSCustomObject]@{ View = $view; Host = $host }
    }

    return $view
}

function New-StView {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Windows.Window]$Window,
        [Parameter(Mandatory)][string]$ScriptDir,
        [string]$ViewName,
        [Parameter(Mandatory)][string]$HostControlName,
        [string]$GlobalVariableName,
        [switch]$PassThruHost
    )

    return Set-StView @PSBoundParameters
}

Export-ModuleMember -Function Set-StView, New-StView
