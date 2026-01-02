Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$toolPath = Join-Path -Path $repoRoot -ChildPath 'Tools/Export-RoutingOfflineBundle.ps1'

function New-SampleSummary {
    param(
        [string]$Root,
        [string]$FileName,
        [string]$PathOne,
        [string]$PathTwo
    )
    $summaryPath = Join-Path -Path $Root -ChildPath $FileName
    $payload = [ordered]@{
        SchemaVersion = '1.0'
        Diff          = [ordered]@{
            SnapshotPath = $PathOne
            LogPath      = $PathTwo
        }
    }
    $payload | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
    return $summaryPath
}

Describe 'Routing offline bundle export' {
    BeforeAll {
        if (-not (Test-Path -LiteralPath $toolPath)) {
            throw "Routing bundle export tool not found at $toolPath"
        }
    }

    It 'exports a bundle with included artifacts' {
        # LANDMARK: Routing bundle export tests - happy path, root safety, and missing artifact handling
        $root = Join-Path -Path $TestDrive -ChildPath 'root'
        $artifactDir = Join-Path -Path $root -ChildPath 'Artifacts'
        $null = New-Item -ItemType Directory -Path $artifactDir -Force

        $artifactOne = Join-Path -Path $artifactDir -ChildPath 'one.txt'
        $artifactTwo = Join-Path -Path $artifactDir -ChildPath 'two.txt'
        Set-Content -LiteralPath $artifactOne -Value 'one' -Encoding UTF8
        Set-Content -LiteralPath $artifactTwo -Value 'two' -Encoding UTF8

        $summaryPath = New-SampleSummary -Root $root -FileName 'RoutingDiff-Sample.json' -PathOne 'Artifacts\one.txt' -PathTwo 'Artifacts\two.txt'
        $outputZip = Join-Path -Path $TestDrive -ChildPath 'bundle.zip'

        & $toolPath -SummaryPath $summaryPath -OutputZipPath $outputZip -RootPath $root -PassThru | Out-Null

        (Test-Path -LiteralPath $outputZip) | Should Be $true
        $extractRoot = Join-Path -Path $TestDrive -ChildPath 'extract'
        Expand-Archive -Path $outputZip -DestinationPath $extractRoot -Force
        $manifestPath = Join-Path -Path $extractRoot -ChildPath 'BundleManifest.json'
        (Test-Path -LiteralPath $manifestPath) | Should Be $true
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        @($manifest.IncludedFiles).Count | Should Be 3
    }

    It 'blocks paths outside the root' {
        $root = Join-Path -Path $TestDrive -ChildPath 'root'
        $null = New-Item -ItemType Directory -Path $root -Force

        $summaryPath = New-SampleSummary -Root $root -FileName 'RoutingDiff-Sample.json' -PathOne '..\..\Windows\system.ini' -PathTwo 'Artifacts\missing.txt'
        $outputZip = Join-Path -Path $TestDrive -ChildPath 'bundle-outside.zip'

        $threw = $false
        try {
            & $toolPath -SummaryPath $summaryPath -OutputZipPath $outputZip -RootPath $root | Out-Null
        } catch {
            $threw = $true
            $_.Exception.Message | Should Match 'outside root'
        }
        $threw | Should Be $true
    }

    It 'fails on missing artifacts by default' {
        $root = Join-Path -Path $TestDrive -ChildPath 'root'
        $null = New-Item -ItemType Directory -Path $root -Force

        $summaryPath = New-SampleSummary -Root $root -FileName 'RoutingDiff-Sample.json' -PathOne 'Artifacts\missing.txt' -PathTwo 'Artifacts\missing-two.txt'
        $outputZip = Join-Path -Path $TestDrive -ChildPath 'bundle-missing.zip'

        $threw = $false
        try {
            & $toolPath -SummaryPath $summaryPath -OutputZipPath $outputZip -RootPath $root | Out-Null
        } catch {
            $threw = $true
            $_.Exception.Message | Should Match 'not found'
            $_.Exception.Message | Should Match 'AllowMissingArtifacts'
        }
        $threw | Should Be $true
    }

    It 'allows missing artifacts when requested' {
        $root = Join-Path -Path $TestDrive -ChildPath 'root'
        $null = New-Item -ItemType Directory -Path $root -Force

        $summaryPath = New-SampleSummary -Root $root -FileName 'RoutingDiff-Sample.json' -PathOne 'Artifacts\missing.txt' -PathTwo 'Artifacts\missing-two.txt'
        $outputZip = Join-Path -Path $TestDrive -ChildPath 'bundle-allowed.zip'

        & $toolPath -SummaryPath $summaryPath -OutputZipPath $outputZip -RootPath $root -AllowMissingArtifacts | Out-Null

        (Test-Path -LiteralPath $outputZip) | Should Be $true
        $extractRoot = Join-Path -Path $TestDrive -ChildPath 'extract-allowed'
        Expand-Archive -Path $outputZip -DestinationPath $extractRoot -Force
        $manifestPath = Join-Path -Path $extractRoot -ChildPath 'BundleManifest.json'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        @($manifest.MissingFiles).Count | Should Be 2
    }
}
