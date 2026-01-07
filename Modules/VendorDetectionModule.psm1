# VendorDetectionModule.psm1
# Auto-detects network device vendor from prompt patterns, banners, and output content
# Supports: Cisco, Arista, Juniper, Aruba, Palo Alto, Brocade

Set-StrictMode -Version Latest

# Vendor detection patterns with confidence scores
$script:VendorPatterns = @{
    Cisco = @{
        PromptPatterns = @(
            @{ Pattern = '^\S+[>#]\s*$'; Score = 80 }
            @{ Pattern = '^\S+\(config[^)]*\)#'; Score = 95 }
        )
        ContentPatterns = @(
            @{ Pattern = '(?i)Cisco IOS'; Score = 100 }
            @{ Pattern = '(?i)Cisco Nexus'; Score = 100 }
            @{ Pattern = '(?i)IOS-XE Software'; Score = 100 }
            @{ Pattern = '(?i)show running-config'; Score = 70 }
            @{ Pattern = '(?i)Switch Ports Model'; Score = 85 }
            @{ Pattern = '(?i)GigabitEthernet|FastEthernet'; Score = 75 }
        )
        BannerPatterns = @(
            @{ Pattern = '(?i)This is a Cisco'; Score = 100 }
            @{ Pattern = '(?i)Cisco Systems'; Score = 95 }
        )
    }
    Arista = @{
        PromptPatterns = @(
            @{ Pattern = '^\S+[>#]\s*$'; Score = 60 }
            @{ Pattern = '^\S+\(config[^)]*\)#'; Score = 70 }
        )
        ContentPatterns = @(
            @{ Pattern = '(?i)Arista EOS'; Score = 100 }
            @{ Pattern = '(?i)Arista Networks'; Score = 100 }
            @{ Pattern = '(?i)Software image version'; Score = 85 }
            @{ Pattern = '(?i)DCS-\d+'; Score = 90 }
            @{ Pattern = '^\s*Et\d+/\d+'; Score = 80 }
        )
        BannerPatterns = @(
            @{ Pattern = '(?i)Arista'; Score = 100 }
        )
    }
    Juniper = @{
        PromptPatterns = @(
            @{ Pattern = '^\S+@\S+[>#]'; Score = 90 }
            @{ Pattern = '^{master:\d+}'; Score = 95 }
        )
        ContentPatterns = @(
            @{ Pattern = '(?i)Junos:'; Score = 100 }
            @{ Pattern = '(?i)JUNOS Software'; Score = 100 }
            @{ Pattern = '(?i)Model:\s*(EX|SRX|MX|QFX|PTX)'; Score = 95 }
            @{ Pattern = '^\s*ge-\d+/\d+/\d+'; Score = 85 }
            @{ Pattern = '^\s*xe-\d+/\d+/\d+'; Score = 85 }
            @{ Pattern = 'set\s+\w+'; Score = 70 }
        )
        BannerPatterns = @(
            @{ Pattern = '(?i)Juniper Networks'; Score = 100 }
        )
    }
    Aruba = @{
        PromptPatterns = @(
            @{ Pattern = '^\S+[#>]\s*$'; Score = 60 }
            @{ Pattern = '^\S+\(config\)#'; Score = 70 }
        )
        ContentPatterns = @(
            @{ Pattern = '(?i)ArubaOS'; Score = 100 }
            @{ Pattern = '(?i)Aruba\s+\d+'; Score = 95 }
            @{ Pattern = '(?i)ProCurve'; Score = 100 }
            @{ Pattern = '(?i)HPE Aruba'; Score = 100 }
            @{ Pattern = '(?i)HP ProCurve'; Score = 100 }
            @{ Pattern = '(?i)[JK]\d{4}[A-Z]'; Score = 85 }
        )
        BannerPatterns = @(
            @{ Pattern = '(?i)Aruba Networks'; Score = 100 }
            @{ Pattern = '(?i)HPE Aruba'; Score = 100 }
        )
    }
    PaloAlto = @{
        PromptPatterns = @(
            @{ Pattern = '^\S+@\S+[>#]\s*$'; Score = 70 }
            @{ Pattern = '^\S+@\S+\(active\)'; Score = 95 }
            @{ Pattern = '^\S+@\S+\(passive\)'; Score = 95 }
        )
        ContentPatterns = @(
            @{ Pattern = '(?i)PAN-OS'; Score = 100 }
            @{ Pattern = '(?i)Palo Alto Networks'; Score = 100 }
            @{ Pattern = '(?i)model:\s*PA-'; Score = 100 }
            @{ Pattern = '(?i)sw-version:'; Score = 90 }
            @{ Pattern = '(?i)ethernet\d+/\d+.*zone'; Score = 80 }
            @{ Pattern = '(?i)vsys\d+'; Score = 85 }
        )
        BannerPatterns = @(
            @{ Pattern = '(?i)Palo Alto'; Score = 100 }
        )
    }
    Brocade = @{
        PromptPatterns = @(
            @{ Pattern = '^\S+[#>]\s*$'; Score = 60 }
        )
        ContentPatterns = @(
            @{ Pattern = '(?i)Brocade'; Score = 100 }
            @{ Pattern = '(?i)ICX\d+'; Score = 100 }
            @{ Pattern = '(?i)FastIron'; Score = 100 }
            @{ Pattern = '(?i)VDX\d+'; Score = 100 }
            @{ Pattern = '(?i)MLXe'; Score = 95 }
        )
        BannerPatterns = @(
            @{ Pattern = '(?i)Brocade Communications'; Score = 100 }
        )
    }
}

function Get-VendorFromContent {
    <#
    .SYNOPSIS
    Detects the network device vendor from output content.
    .DESCRIPTION
    Analyzes device output lines to determine the vendor using pattern matching
    on prompts, content, and banners. Returns the vendor with the highest confidence score.
    .PARAMETER Lines
    Array of text lines from device output.
    .PARAMETER MinConfidence
    Minimum confidence score (0-100) required for a positive match. Default 60.
    .OUTPUTS
    PSCustomObject with Vendor, Confidence, and MatchedPatterns properties.
    .EXAMPLE
    $result = Get-VendorFromContent -Lines $deviceOutput
    if ($result.Confidence -gt 80) { Write-Host "Detected: $($result.Vendor)" }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Lines,
        [int]$MinConfidence = 60
    )

    if (-not $Lines -or $Lines.Count -eq 0) {
        return [PSCustomObject]@{
            Vendor = 'Unknown'
            Confidence = 0
            MatchedPatterns = @()
        }
    }

    $vendorScores = @{}
    $matchedByVendor = @{}

    foreach ($vendor in $script:VendorPatterns.Keys) {
        $vendorScores[$vendor] = 0
        $matchedByVendor[$vendor] = [System.Collections.Generic.List[string]]::new()
    }

    # Sample lines for efficiency (first 50, last 20)
    $sampleLines = @()
    if ($Lines.Count -le 70) {
        $sampleLines = $Lines
    } else {
        $sampleLines = $Lines[0..49] + $Lines[($Lines.Count - 20)..($Lines.Count - 1)]
    }

    foreach ($line in $sampleLines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }

        foreach ($vendor in $script:VendorPatterns.Keys) {
            $patterns = $script:VendorPatterns[$vendor]

            # Check prompt patterns
            foreach ($p in $patterns.PromptPatterns) {
                if ($line -match $p.Pattern) {
                    $vendorScores[$vendor] += $p.Score
                    [void]$matchedByVendor[$vendor].Add("Prompt: $($p.Pattern)")
                }
            }

            # Check content patterns
            foreach ($p in $patterns.ContentPatterns) {
                if ($line -match $p.Pattern) {
                    $vendorScores[$vendor] += $p.Score
                    [void]$matchedByVendor[$vendor].Add("Content: $($p.Pattern)")
                }
            }

            # Check banner patterns
            foreach ($p in $patterns.BannerPatterns) {
                if ($line -match $p.Pattern) {
                    $vendorScores[$vendor] += $p.Score
                    [void]$matchedByVendor[$vendor].Add("Banner: $($p.Pattern)")
                }
            }
        }
    }

    # Find highest scoring vendor
    $topVendor = 'Unknown'
    $topScore = 0
    $topMatches = @()

    foreach ($vendor in $vendorScores.Keys) {
        if ($vendorScores[$vendor] -gt $topScore) {
            $topScore = $vendorScores[$vendor]
            $topVendor = $vendor
            $topMatches = $matchedByVendor[$vendor].ToArray()
        }
    }

    # Normalize score to 0-100 range (cap at 100)
    $normalizedScore = [Math]::Min(100, $topScore)

    if ($normalizedScore -lt $MinConfidence) {
        $topVendor = 'Unknown'
    }

    return [PSCustomObject]@{
        Vendor = $topVendor
        Confidence = $normalizedScore
        MatchedPatterns = $topMatches
        AllScores = $vendorScores
    }
}

function Get-VendorParser {
    <#
    .SYNOPSIS
    Returns the appropriate parser function for a detected vendor.
    .PARAMETER Vendor
    The vendor name (Cisco, Arista, Juniper, Aruba, PaloAlto, Brocade).
    .OUTPUTS
    String containing the qualified function name for the parser.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Vendor
    )

    $parserMap = @{
        Cisco = 'CiscoModule\Get-CiscoDeviceFacts'
        Arista = 'AristaModule\Get-AristaDeviceFacts'
        Juniper = 'JuniperModule\Get-JuniperDeviceFacts'
        Aruba = 'ArubaModule\Get-ArubaDeviceFacts'
        PaloAlto = 'PaloAltoModule\Get-PaloAltoDeviceFacts'
        Brocade = 'BrocadeModule\Get-BrocadeDeviceFacts'
    }

    if ($parserMap.ContainsKey($Vendor)) {
        return $parserMap[$Vendor]
    }

    return $null
}

function Invoke-VendorParser {
    <#
    .SYNOPSIS
    Auto-detects vendor and invokes the appropriate parser.
    .PARAMETER Lines
    Array of text lines from device output.
    .PARAMETER Blocks
    Optional hashtable of pre-parsed show command blocks.
    .PARAMETER ForceVendor
    Optional vendor override to skip auto-detection.
    .OUTPUTS
    PSCustomObject with device facts from the vendor-specific parser.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$Lines,
        [hashtable]$Blocks,
        [string]$ForceVendor
    )

    $vendor = $ForceVendor
    $detection = $null

    if (-not $vendor) {
        $detection = Get-VendorFromContent -Lines $Lines
        $vendor = $detection.Vendor
        Write-Verbose "[VendorDetection] Detected: $vendor (confidence: $($detection.Confidence)%)"
    }

    if ($vendor -eq 'Unknown') {
        Write-Warning "[VendorDetection] Unable to detect vendor. Returning raw data."
        return [PSCustomObject]@{
            Hostname = 'Unknown'
            Make = 'Unknown'
            Model = 'Unknown'
            Version = 'Unknown'
            Uptime = 'Unknown'
            Location = ''
            InterfaceCount = 0
            InterfacesCombined = @()
            DetectionResult = $detection
        }
    }

    $parserFunc = Get-VendorParser -Vendor $vendor

    if (-not $parserFunc) {
        Write-Warning "[VendorDetection] No parser available for vendor: $vendor"
        return [PSCustomObject]@{
            Hostname = 'Unknown'
            Make = $vendor
            Model = 'Unknown'
            Version = 'Unknown'
            Uptime = 'Unknown'
            Location = ''
            InterfaceCount = 0
            InterfacesCombined = @()
            DetectionResult = $detection
        }
    }

    # Import the module if needed
    $moduleName = $parserFunc -replace '\\.*', ''
    $modulePath = Join-Path $PSScriptRoot "$moduleName.psm1"
    if (Test-Path $modulePath) {
        Import-Module $modulePath -Force -DisableNameChecking -ErrorAction SilentlyContinue
    }

    # Invoke the parser
    try {
        $params = @{ Lines = $Lines }
        if ($Blocks) { $params.Blocks = $Blocks }

        $result = & $parserFunc @params

        # Add detection metadata
        if ($detection) {
            $result | Add-Member -NotePropertyName 'DetectionConfidence' -NotePropertyValue $detection.Confidence -Force
        }

        return $result
    } catch {
        Write-Warning "[VendorDetection] Parser failed: $($_.Exception.Message)"
        return [PSCustomObject]@{
            Hostname = 'Unknown'
            Make = $vendor
            Model = 'Unknown'
            Version = 'Unknown'
            Error = $_.Exception.Message
            DetectionResult = $detection
        }
    }
}

function Get-SupportedVendors {
    <#
    .SYNOPSIS
    Returns a list of supported network device vendors.
    #>
    [CmdletBinding()]
    param()

    return $script:VendorPatterns.Keys | Sort-Object
}

function Add-VendorPattern {
    <#
    .SYNOPSIS
    Adds a custom pattern for vendor detection.
    .PARAMETER Vendor
    The vendor name.
    .PARAMETER PatternType
    Type of pattern: PromptPatterns, ContentPatterns, or BannerPatterns.
    .PARAMETER Pattern
    The regex pattern to match.
    .PARAMETER Score
    Confidence score (1-100) for this pattern.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Vendor,
        [Parameter(Mandatory)][ValidateSet('PromptPatterns', 'ContentPatterns', 'BannerPatterns')][string]$PatternType,
        [Parameter(Mandatory)][string]$Pattern,
        [Parameter(Mandatory)][ValidateRange(1, 100)][int]$Score
    )

    if (-not $script:VendorPatterns.ContainsKey($Vendor)) {
        $script:VendorPatterns[$Vendor] = @{
            PromptPatterns = @()
            ContentPatterns = @()
            BannerPatterns = @()
        }
    }

    $script:VendorPatterns[$Vendor][$PatternType] += @{ Pattern = $Pattern; Score = $Score }
    Write-Verbose "[VendorDetection] Added pattern for $Vendor : $PatternType"
}

Export-ModuleMember -Function @(
    'Get-VendorFromContent',
    'Get-VendorParser',
    'Invoke-VendorParser',
    'Get-SupportedVendors',
    'Add-VendorPattern'
)
