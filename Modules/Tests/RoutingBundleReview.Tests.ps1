Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$toolPath = Join-Path -Path $repoRoot -ChildPath 'Tools/Invoke-RoutingBundleReview.ps1'
$diffFixture = Join-Path -Path $repoRoot -ChildPath 'Tests/Fixtures/Routing/RouteDiff/RoutingDiff.sample.json'

function Get-BytesHash {
    param([byte[]]$Bytes)
    $hasher = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hashBytes = $hasher.ComputeHash($Bytes)
    } finally {
        $hasher.Dispose()
    }
    return ([System.BitConverter]::ToString($hashBytes)).Replace('-', '')
}

function New-ZipFromEntries {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ZipPath,
        [Parameter(Mandatory = $true)]
        [hashtable[]]$Entries
    )
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (Test-Path -LiteralPath $ZipPath) {
        Remove-Item -LiteralPath $ZipPath -Force
    }
    $zip = [System.IO.Compression.ZipFile]::Open($ZipPath, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($entryDef in $Entries) {
            $entry = $zip.CreateEntry($entryDef.Name)
            $stream = $entry.Open()
            try {
                if ($entryDef.Bytes) {
                    $stream.Write($entryDef.Bytes, 0, $entryDef.Bytes.Length)
                }
            } finally {
                $stream.Dispose()
            }
        }
    } finally {
        $zip.Dispose()
    }
}

function New-ReviewBundleZip {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ZipPath,
        [Parameter(Mandatory = $true)]
        [string]$RelativePath,
        [Parameter(Mandatory = $true)]
        [byte[]]$FileBytes,
        [Parameter(Mandatory = $true)]
        [string]$SummaryPath,
        [string]$ShaOverride
    )
    $hash = if ($ShaOverride) { $ShaOverride } else { Get-BytesHash -Bytes $FileBytes }
    $manifest = [ordered]@{
        SchemaVersion = '1.0'
        SummaryPath   = $SummaryPath
        IncludedFiles = @(
            [ordered]@{
                RelativePath = $RelativePath
                SourcePath   = $SummaryPath
                Sha256       = $hash
                Bytes        = $FileBytes.Length
            }
        )
    }
    $manifestBytes = [System.Text.Encoding]::UTF8.GetBytes(($manifest | ConvertTo-Json -Depth 5))
    New-ZipFromEntries -ZipPath $ZipPath -Entries @(
        @{ Name = 'BundleManifest.json'; Bytes = $manifestBytes },
        @{ Name = $RelativePath; Bytes = $FileBytes }
    )
}

Describe 'Routing bundle review' {
    BeforeAll {
        if (-not (Test-Path -LiteralPath $toolPath)) {
            throw "Routing bundle review tool not found at $toolPath"
        }
        if (-not (Test-Path -LiteralPath $diffFixture)) {
            throw "Routing diff fixture not found at $diffFixture"
        }
    }

    It 'reviews a bundle with validation and expansion' {
        # LANDMARK: Bundle review tests - happy path, overwrite semantics, validation gate, skip-validation, and manifest/summary failure
        $bundlePath = Join-Path -Path $TestDrive -ChildPath 'bundle.zip'
        $workspaceRoot = Join-Path -Path $TestDrive -ChildPath 'review'
        $relativePath = 'Logs/Reports/Foo.json'
        $fileBytes = [System.Text.Encoding]::UTF8.GetBytes('payload')
        $summaryPath = 'C:\Bundle\Logs\Reports\Foo.json'
        New-ReviewBundleZip -ZipPath $bundlePath -RelativePath $relativePath -FileBytes $fileBytes -SummaryPath $summaryPath

        $result = & $toolPath -BundleZipPath $bundlePath -WorkspaceRoot $workspaceRoot -SkipIndex -SkipRender -PassThru
        $result.Status | Should Be 'Pass'
        (Test-Path -LiteralPath $result.PrimarySummaryExtractedPath) | Should Be $true
    }

    It 'requires Overwrite for a non-empty workspace' {
        $bundlePath = Join-Path -Path $TestDrive -ChildPath 'bundle-overwrite.zip'
        $workspaceRoot = Join-Path -Path $TestDrive -ChildPath 'review-overwrite'
        $relativePath = 'Logs/Reports/Foo.json'
        $fileBytes = [System.Text.Encoding]::UTF8.GetBytes('payload')
        $summaryPath = 'C:\Bundle\Logs\Reports\Foo.json'
        New-ReviewBundleZip -ZipPath $bundlePath -RelativePath $relativePath -FileBytes $fileBytes -SummaryPath $summaryPath

        $null = New-Item -ItemType Directory -Path $workspaceRoot -Force
        $sentinelPath = Join-Path -Path $workspaceRoot -ChildPath 'sentinel.txt'
        Set-Content -LiteralPath $sentinelPath -Value 'sentinel' -Encoding UTF8

        $threw = $false
        try {
            & $toolPath -BundleZipPath $bundlePath -WorkspaceRoot $workspaceRoot -SkipIndex -SkipRender | Out-Null
        } catch {
            $threw = $true
            $_.Exception.Message | Should Match 'not empty'
        }
        $threw | Should Be $true

        $result = & $toolPath -BundleZipPath $bundlePath -WorkspaceRoot $workspaceRoot -Overwrite -SkipIndex -SkipRender -PassThru
        $result.Status | Should Be 'Pass'
        (Test-Path -LiteralPath $sentinelPath) | Should Be $false
    }

    It 'fails when validation fails by default' {
        $bundlePath = Join-Path -Path $TestDrive -ChildPath 'bundle-invalid.zip'
        $workspaceRoot = Join-Path -Path $TestDrive -ChildPath 'review-invalid'
        $relativePath = 'Logs/Reports/Foo.json'
        $fileBytes = [System.Text.Encoding]::UTF8.GetBytes('payload')
        $summaryPath = 'C:\Bundle\Logs\Reports\Foo.json'
        New-ReviewBundleZip -ZipPath $bundlePath -RelativePath $relativePath -FileBytes $fileBytes -SummaryPath $summaryPath -ShaOverride 'BADSIGNATURE'

        $threw = $false
        try {
            & $toolPath -BundleZipPath $bundlePath -WorkspaceRoot $workspaceRoot -SkipIndex -SkipRender | Out-Null
        } catch {
            $threw = $true
            $_.Exception.Message | Should Match 'Bundle validation failed'
        }
        $threw | Should Be $true
    }

    It 'allows review when validation is skipped' {
        $bundlePath = Join-Path -Path $TestDrive -ChildPath 'bundle-skip.zip'
        $workspaceRoot = Join-Path -Path $TestDrive -ChildPath 'review-skip'
        $relativePath = 'Logs/Reports/Foo.json'
        $fileBytes = [System.Text.Encoding]::UTF8.GetBytes('payload')
        $summaryPath = 'C:\Bundle\Logs\Reports\Foo.json'
        New-ReviewBundleZip -ZipPath $bundlePath -RelativePath $relativePath -FileBytes $fileBytes -SummaryPath $summaryPath -ShaOverride 'BADSIGNATURE'

        $result = & $toolPath -BundleZipPath $bundlePath -WorkspaceRoot $workspaceRoot -SkipValidation -SkipIndex -SkipRender -PassThru
        $result.Status | Should Be 'Pass'
        $result.Validated | Should Be $false
    }

    It 'fails when the manifest summary cannot be resolved' {
        $bundlePath = Join-Path -Path $TestDrive -ChildPath 'bundle-missing-summary.zip'
        $workspaceRoot = Join-Path -Path $TestDrive -ChildPath 'review-missing-summary'
        $relativePath = 'Logs/Reports/Foo.json'
        $fileBytes = [System.Text.Encoding]::UTF8.GetBytes('payload')
        $summaryPath = 'C:\Bundle\Logs\Reports\Missing.json'
        $hash = Get-BytesHash -Bytes $fileBytes
        $manifest = [ordered]@{
            SchemaVersion = '1.0'
            SummaryPath   = $summaryPath
            IncludedFiles = @(
                [ordered]@{
                    RelativePath = $relativePath
                    SourcePath   = 'C:\Bundle\Logs\Reports\Other.json'
                    Sha256       = $hash
                    Bytes        = $fileBytes.Length
                }
            )
        }
        $manifestBytes = [System.Text.Encoding]::UTF8.GetBytes(($manifest | ConvertTo-Json -Depth 5))
        New-ZipFromEntries -ZipPath $bundlePath -Entries @(
            @{ Name = 'BundleManifest.json'; Bytes = $manifestBytes },
            @{ Name = $relativePath; Bytes = $fileBytes }
        )

        $threw = $false
        try {
            & $toolPath -BundleZipPath $bundlePath -WorkspaceRoot $workspaceRoot -SkipIndex -SkipRender | Out-Null
        } catch {
            $threw = $true
            $_.Exception.Message | Should Match 'Primary summary'
        }
        $threw | Should Be $true
    }

    It 'renders routing diff summaries without warnings' {
        # LANDMARK: RoutingDiff support tests - index + render + bundle review diff render
        $bundlePath = Join-Path -Path $TestDrive -ChildPath 'bundle-diff.zip'
        $workspaceRoot = Join-Path -Path $TestDrive -ChildPath 'review-diff'
        $relativePath = 'Logs/Reports/RoutingDiff/RoutingDiff-20251231-000000.json'
        $fileBytes = [System.Text.Encoding]::UTF8.GetBytes((Get-Content -LiteralPath $diffFixture -Raw))
        $summaryPath = 'C:\Bundle\Logs\Reports\RoutingDiff\RoutingDiff-20251231-000000.json'
        New-ReviewBundleZip -ZipPath $bundlePath -RelativePath $relativePath -FileBytes $fileBytes -SummaryPath $summaryPath

        $result = & $toolPath -BundleZipPath $bundlePath -WorkspaceRoot $workspaceRoot -SkipIndex -PassThru
        $result.Status | Should Be 'Pass'
        $result.Rendered | Should Be $true
        $result.Warnings -join '; ' | Should Not Match 'render failed'
        (Test-Path -LiteralPath $result.RenderOutputPath) | Should Be $true
    }

    It 'writes workspace latest pointers and explorer command when index/render succeed' {
        # LANDMARK: Bundle review ergonomics tests - workspace latest pointers + explorer command emission
        $bundlePath = Join-Path -Path $TestDrive -ChildPath 'bundle-latest.zip'
        $workspaceRoot = Join-Path -Path $TestDrive -ChildPath 'review-latest'
        $relativePath = 'Logs/Reports/RoutingDiff/RoutingDiff-20251231-000000.json'
        $fileBytes = [System.Text.Encoding]::UTF8.GetBytes((Get-Content -LiteralPath $diffFixture -Raw))
        $summaryPath = 'C:\Bundle\Logs\Reports\RoutingDiff\RoutingDiff-20251231-000000.json'
        New-ReviewBundleZip -ZipPath $bundlePath -RelativePath $relativePath -FileBytes $fileBytes -SummaryPath $summaryPath

        $result = & $toolPath -BundleZipPath $bundlePath -WorkspaceRoot $workspaceRoot -PassThru
        $result.Status | Should Be 'Pass'
        $result.IndexBuilt | Should Be $true
        $result.Rendered | Should Be $true

        (Test-Path -LiteralPath $result.IndexLatestPath) | Should Be $true
        (Get-BytesHash -Bytes ([System.IO.File]::ReadAllBytes($result.IndexLatestPath))) | Should Be (Get-BytesHash -Bytes ([System.IO.File]::ReadAllBytes($result.IndexOutputPath)))

        (Test-Path -LiteralPath $result.RenderLatestPath) | Should Be $true
        (Get-BytesHash -Bytes ([System.IO.File]::ReadAllBytes($result.RenderLatestPath))) | Should Be (Get-BytesHash -Bytes ([System.IO.File]::ReadAllBytes($result.RenderOutputPath)))

        $result.ExplorerCommand | Should Match 'Invoke-RoutingLogExplorer\.ps1'
        $result.ExplorerCommand | Should Match ([regex]::Escape($result.IndexLatestPath))
    }

    It 'runs explorer when requested' {
        # LANDMARK: Bundle review one-step tests - explorer run and parameter incompatibility
        $bundlePath = Join-Path -Path $TestDrive -ChildPath 'bundle-explorer.zip'
        $workspaceRoot = Join-Path -Path $TestDrive -ChildPath 'review-explorer'
        $relativePath = 'Logs/Reports/RoutingDiff/RoutingDiff-20251231-000000.json'
        $fileBytes = [System.Text.Encoding]::UTF8.GetBytes((Get-Content -LiteralPath $diffFixture -Raw))
        $summaryPath = 'C:\Bundle\Logs\Reports\RoutingDiff\RoutingDiff-20251231-000000.json'
        New-ReviewBundleZip -ZipPath $bundlePath -RelativePath $relativePath -FileBytes $fileBytes -SummaryPath $summaryPath

        $result = & $toolPath -BundleZipPath $bundlePath -WorkspaceRoot $workspaceRoot -RunExplorer -PassThru
        $result.ExplorerInvoked | Should Be $true
        $result.ExplorerStatus | Should Be 'Pass'
        (Test-Path -LiteralPath $result.ExplorerOutputPath) | Should Be $true
        (Test-Path -LiteralPath $result.ExplorerLogPath) | Should Be $true
    }

    It 'fails fast when RunExplorer is combined with SkipIndex' {
        $bundlePath = Join-Path -Path $TestDrive -ChildPath 'bundle-skipindex.zip'
        $workspaceRoot = Join-Path -Path $TestDrive -ChildPath 'review-skipindex'
        $relativePath = 'Logs/Reports/RoutingDiff/RoutingDiff-20251231-000000.json'
        $fileBytes = [System.Text.Encoding]::UTF8.GetBytes((Get-Content -LiteralPath $diffFixture -Raw))
        $summaryPath = 'C:\Bundle\Logs\Reports\RoutingDiff\RoutingDiff-20251231-000000.json'
        New-ReviewBundleZip -ZipPath $bundlePath -RelativePath $relativePath -FileBytes $fileBytes -SummaryPath $summaryPath

        $threw = $false
        try {
            & $toolPath -BundleZipPath $bundlePath -WorkspaceRoot $workspaceRoot -RunExplorer -SkipIndex | Out-Null
        } catch {
            $threw = $true
            $_.Exception.Message | Should Match 'RunExplorer cannot be used with -SkipIndex'
        }
        $threw | Should Be $true
    }
}
