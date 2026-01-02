Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$toolPath = Join-Path -Path $repoRoot -ChildPath 'Tools/Expand-RoutingOfflineBundle.ps1'

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

Describe 'Routing offline bundle expand' {
    BeforeAll {
        if (-not (Test-Path -LiteralPath $toolPath)) {
            throw "Routing bundle expand tool not found at $toolPath"
        }
    }

    It 'expands a bundle after validation' {
        # LANDMARK: Routing bundle expand tests - validation gate, overwrite semantics, and skip-validation behavior
        $bundlePath = Join-Path -Path $TestDrive -ChildPath 'bundle.zip'
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'out'
        $summaryPath = Join-Path -Path $TestDrive -ChildPath 'summary.json'
        $validationPath = Join-Path -Path $TestDrive -ChildPath 'validation.json'
        $relativePath = 'Logs/Reports/sample.json'
        $fileBytes = [System.Text.Encoding]::UTF8.GetBytes('sample')
        $manifest = [ordered]@{
            SchemaVersion = '1.0'
            IncludedFiles = @(
                [ordered]@{
                    RelativePath = $relativePath
                    Sha256       = (Get-BytesHash -Bytes $fileBytes)
                    Bytes        = $fileBytes.Length
                }
            )
        }
        $manifestBytes = [System.Text.Encoding]::UTF8.GetBytes(($manifest | ConvertTo-Json -Depth 5))

        New-ZipFromEntries -ZipPath $bundlePath -Entries @(
            @{ Name = 'BundleManifest.json'; Bytes = $manifestBytes },
            @{ Name = $relativePath; Bytes = $fileBytes }
        )

        $result = & $toolPath -BundleZipPath $bundlePath -OutputRoot $outputRoot -ValidationOutputPath $validationPath -SummaryPath $summaryPath -PassThru
        $result.Status | Should Be 'Pass'
        (Test-Path -LiteralPath (Join-Path -Path $outputRoot -ChildPath 'BundleManifest.json')) | Should Be $true
        (Test-Path -LiteralPath (Join-Path -Path $outputRoot -ChildPath $relativePath)) | Should Be $true
        (Test-Path -LiteralPath $summaryPath) | Should Be $true
    }

    It 'blocks extraction when validation fails' {
        $bundlePath = Join-Path -Path $TestDrive -ChildPath 'bundle-invalid.zip'
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'out-invalid'
        $summaryPath = Join-Path -Path $TestDrive -ChildPath 'summary-invalid.json'
        $validationPath = Join-Path -Path $TestDrive -ChildPath 'validation-invalid.json'
        $relativePath = 'Logs/Reports/sample.json'
        $fileBytes = [System.Text.Encoding]::UTF8.GetBytes('sample')
        $manifest = [ordered]@{
            SchemaVersion = '1.0'
            IncludedFiles = @(
                [ordered]@{
                    RelativePath = $relativePath
                    Sha256       = 'BADSIGNATURE'
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
            & $toolPath -BundleZipPath $bundlePath -OutputRoot $outputRoot -ValidationOutputPath $validationPath -SummaryPath $summaryPath | Out-Null
        } catch {
            $threw = $true
            $_.Exception.Message | Should Match 'validation failed'
        }
        $threw | Should Be $true
        (Test-Path -LiteralPath (Join-Path -Path $outputRoot -ChildPath $relativePath)) | Should Be $false
    }

    It 'requires Overwrite to clear a non-empty output root' {
        $bundlePath = Join-Path -Path $TestDrive -ChildPath 'bundle-overwrite.zip'
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'out-overwrite'
        $summaryPath = Join-Path -Path $TestDrive -ChildPath 'summary-overwrite.json'
        $validationPath = Join-Path -Path $TestDrive -ChildPath 'validation-overwrite.json'
        $relativePath = 'Logs/Reports/sample.json'
        $fileBytes = [System.Text.Encoding]::UTF8.GetBytes('sample')
        $manifest = [ordered]@{
            SchemaVersion = '1.0'
            IncludedFiles = @(
                [ordered]@{
                    RelativePath = $relativePath
                    Sha256       = (Get-BytesHash -Bytes $fileBytes)
                    Bytes        = $fileBytes.Length
                }
            )
        }
        $manifestBytes = [System.Text.Encoding]::UTF8.GetBytes(($manifest | ConvertTo-Json -Depth 5))

        New-ZipFromEntries -ZipPath $bundlePath -Entries @(
            @{ Name = 'BundleManifest.json'; Bytes = $manifestBytes },
            @{ Name = $relativePath; Bytes = $fileBytes }
        )

        $null = New-Item -ItemType Directory -Path $outputRoot -Force
        $sentinelPath = Join-Path -Path $outputRoot -ChildPath 'sentinel.txt'
        Set-Content -LiteralPath $sentinelPath -Value 'sentinel' -Encoding UTF8

        $threw = $false
        try {
            & $toolPath -BundleZipPath $bundlePath -OutputRoot $outputRoot | Out-Null
        } catch {
            $threw = $true
            $_.Exception.Message | Should Match 'not empty'
        }
        $threw | Should Be $true

        & $toolPath -BundleZipPath $bundlePath -OutputRoot $outputRoot -Overwrite -ValidationOutputPath $validationPath -SummaryPath $summaryPath | Out-Null
        (Test-Path -LiteralPath $sentinelPath) | Should Be $false
        (Test-Path -LiteralPath (Join-Path -Path $outputRoot -ChildPath $relativePath)) | Should Be $true
    }

    It 'skips validation when requested' {
        $bundlePath = Join-Path -Path $TestDrive -ChildPath 'bundle-skip.zip'
        $outputRoot = Join-Path -Path $TestDrive -ChildPath 'out-skip'
        $summaryPath = Join-Path -Path $TestDrive -ChildPath 'summary-skip.json'
        $relativePath = 'Logs/Reports/sample.json'
        $fileBytes = [System.Text.Encoding]::UTF8.GetBytes('sample')
        $manifest = [ordered]@{
            SchemaVersion = '1.0'
            IncludedFiles = @(
                [ordered]@{
                    RelativePath = $relativePath
                    Sha256       = 'BADSIGNATURE'
                    Bytes        = $fileBytes.Length
                }
            )
        }
        $manifestBytes = [System.Text.Encoding]::UTF8.GetBytes(($manifest | ConvertTo-Json -Depth 5))

        New-ZipFromEntries -ZipPath $bundlePath -Entries @(
            @{ Name = 'BundleManifest.json'; Bytes = $manifestBytes },
            @{ Name = $relativePath; Bytes = $fileBytes }
        )

        $result = & $toolPath -BundleZipPath $bundlePath -OutputRoot $outputRoot -SkipValidation -SummaryPath $summaryPath -PassThru
        $result.Status | Should Be 'Pass'
        $result.Validated | Should Be $false
        (Test-Path -LiteralPath (Join-Path -Path $outputRoot -ChildPath $relativePath)) | Should Be $true
    }
}
