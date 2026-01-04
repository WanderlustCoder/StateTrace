[CmdletBinding()]
param(
    [string]$SourceMetricsPath = 'Logs\IngestionMetrics\2025-10-24.json',
    [string]$OutputDirectory = 'Logs',
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ST-J-004: Early warning for missing templates
$knownTemplates = @(
    'Logs\mock_cisco_authentic.log',
    'Logs\mock_brocade_BOYO_73.log'
)
$missingTemplates = @($knownTemplates | Where-Object { -not (Test-Path -LiteralPath $_) })
if ($missingTemplates.Count -gt 0) {
    Write-Warning "Some template logs are missing and will cause errors when expanding their sites:"
    foreach ($missing in $missingTemplates) {
        Write-Warning "  - $missing"
    }
    Write-Warning "See Data\README.md for how to create template logs, or use -Force to attempt anyway."
    Write-Warning ""
}

function Get-UniqueHostNames {
    param([string]$MetricsPath)

    if (-not (Test-Path -LiteralPath $MetricsPath)) {
        throw "Metrics file not found at '$MetricsPath'."
    }

    $hostSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($line in [System.IO.File]::ReadLines((Resolve-Path -LiteralPath $MetricsPath))) {
        if (-not $line.StartsWith('{')) { continue }
        try {
            $json = $line | ConvertFrom-Json -ErrorAction Stop
        } catch {
            continue
        }
        $records = @()
        if ($json -is [System.Collections.IEnumerable] -and -not ($json -is [string])) {
            $records = @($json)
        } else {
            $records = @($json)
        }
        foreach ($record in $records) {
            $hostnameProp = $record.PSObject.Properties['Hostname']
            if ($hostnameProp -and -not [string]::IsNullOrWhiteSpace($hostnameProp.Value)) {
                [void]$hostSet.Add(($hostnameProp.Value).Trim())
            }
        }
    }
    return @($hostSet.GetEnumerator() | ForEach-Object { $_ })
}

function Get-TemplateForSite {
    param(
        [Parameter(Mandatory)][string]$SitePrefix
    )

    switch -Regex ($SitePrefix.ToUpperInvariant()) {
        '^WLLS$' { return @{ TemplatePath = 'Logs\mock_cisco_authentic.log'; TemplateHost = 'WLLS-A01-AS-01' } }
        '^BOYO$' { return @{ TemplatePath = 'Logs\mock_brocade_BOYO_73.log'; TemplateHost = 'BOYO-A05-AS-02' } }
        default  { return @{ TemplatePath = 'Logs\mock_cisco_authentic.log'; TemplateHost = 'WLLS-A01-AS-01' } }
    }
}

function Ensure-TemplateAvailable {
    param([string]$TemplatePath)
    if (-not (Test-Path -LiteralPath $TemplatePath)) {
        $hint = @"

Required template log '$TemplatePath' is missing.

Template logs are gitignored and must be created locally:
  1. Obtain authentic device logs from a test environment
  2. Sanitize using: Tools\Sanitize-PostmortemLogs.ps1
  3. Save as: $TemplatePath
  4. Re-run: Tools\Expand-MockLogCorpus.ps1 -Force

For CI testing without templates, use tracked fixtures:
  - Tests\Fixtures\CISmoke\IngestionMetrics.json
  - Invoke-Pester -Tag Decomposition

See Data\README.md for details.
"@
        throw $hint
    }
}

function Write-HostLog {
    param(
        [Parameter(Mandatory)][string]$HostName,
        [Parameter(Mandatory)][string]$TemplatePath,
        [Parameter(Mandatory)][string]$TemplateHost,
        [Parameter(Mandatory)][string]$DestinationPath,
        [switch]$Force
    )

    if ((Test-Path -LiteralPath $DestinationPath) -and -not $Force.IsPresent) {
        return
    }

    $content = Get-Content -LiteralPath $TemplatePath -Raw
    $escaped = [Regex]::Escape($TemplateHost)
    $updated = [Regex]::Replace($content, $escaped, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $HostName }, 'IgnoreCase')
    Set-Content -LiteralPath $DestinationPath -Value $updated -Encoding UTF8 -Force
}

$hosts = Get-UniqueHostNames -MetricsPath $SourceMetricsPath
if (-not $hosts -or $hosts.Count -eq 0) {
    throw "No hostnames discovered in '$SourceMetricsPath'."
}

$outputRoot = Resolve-Path -LiteralPath $OutputDirectory

Write-Host "Generating mock logs for $($hosts.Count) host(s) into '$outputRoot'..." -ForegroundColor Cyan

$generated = 0
foreach ($hostName in $hosts) {
    if ([string]::IsNullOrWhiteSpace($hostName)) { continue }
    $parts = $hostName.Split('-')
    if ($parts.Count -eq 0) { continue }
    $sitePrefix = $parts[0]
    $templateInfo = Get-TemplateForSite -SitePrefix $sitePrefix
    Ensure-TemplateAvailable -TemplatePath $templateInfo.TemplatePath

    $safeFileName = ('synthetic_{0}.log' -f ($hostName -replace '[\\/:*?"<>|]', '_'))
    $destination = Join-Path -Path $outputRoot -ChildPath $safeFileName
    Write-Host ("  -> {0}" -f $hostName) -ForegroundColor DarkGray
    Write-HostLog -HostName $hostName -TemplatePath $templateInfo.TemplatePath -TemplateHost $templateInfo.TemplateHost -DestinationPath $destination -Force:$Force
    $generated++
}

Write-Host ("Completed corpus expansion. Generated or refreshed {0} log file(s)." -f $generated) -ForegroundColor Green
