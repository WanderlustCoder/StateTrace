Set-StrictMode -Version Latest

function Assert-OnlineCapability {
    if (-not $env:STATETRACE_AGENT_ALLOW_NET) {
        throw "Online capability is disabled. Set STATETRACE_AGENT_ALLOW_NET=1 to proceed."
    }
}

function Invoke-AllowedDownload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$OutFile,
        [string[]]$AllowedDomains = @('github.com','objects.githubusercontent.com','downloads.python.org','graphviz.org','winget.azureedge.net'),
        [string]$ExpectedSha256 # optional
    )
    Assert-OnlineCapability

    # Domain allowlist
    try {
        $u = [Uri]$Uri
    } catch {
        throw "Invalid URI: $Uri"
    }
    $host = $u.Host.ToLowerInvariant()
    if (-not ($AllowedDomains | ForEach-Object { $host -like "*$_" } | Where-Object { $_ } | Measure-Object).Count) {
        throw "Host '$host' is not in the allowlist."
    }

    # Download
    Invoke-WebRequest -UseBasicParsing -Uri $Uri -OutFile $OutFile

    # Hash verification (optional but recommended)
    if ($ExpectedSha256) {
        $hash = (Get-FileHash -Algorithm SHA256 -Path $OutFile).Hash.ToLowerInvariant()
        if ($hash -ne $ExpectedSha256.ToLowerInvariant()) {
            Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue
            throw "SHA256 mismatch for $OutFile. Expected $ExpectedSha256, got $hash."
        }
    }

    # Log provenance
    $logDir = Join-Path $PSScriptRoot '..\Logs\NetOps'
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    $entry = [pscustomobject]@{
        Timestamp = (Get-Date).ToString('o')
        Uri       = $Uri
        OutFile   = (Resolve-Path $OutFile).ProviderPath
        Sha256    = if ($ExpectedSha256) { $ExpectedSha256 } else { '' }
    }
    $entry | ConvertTo-Json -Compress | Add-Content (Join-Path $logDir ((Get-Date).ToString('yyyy-MM-dd') + '.json'))
}

Export-ModuleMember -Function Invoke-AllowedDownload, Assert-OnlineCapability
