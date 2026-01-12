Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$toolPath = Join-Path -Path $repoRoot -ChildPath 'Tools/Test-RoutingOfflineBundle.ps1'

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

Describe 'Routing offline bundle validation' {
    BeforeAll {
        if (-not (Test-Path -LiteralPath $toolPath)) {
            throw "Routing bundle validation tool not found at $toolPath"
        }
    }

    It 'validates a bundle with a manifest and hashes' {
        # LANDMARK: Routing bundle validation tests - pass, hash mismatch, missing manifest, traversal, extras
        $bundlePath = Join-Path -Path $TestDrive -ChildPath 'bundle.zip'
        $outputPath = Join-Path -Path $TestDrive -ChildPath 'validation.json'
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

        $result = & $toolPath -BundleZipPath $bundlePath -OutputPath $outputPath -PassThru
        $result.Status | Should Be 'Pass'
        (Test-Path -LiteralPath $outputPath) | Should Be $true
    }

    It 'fails on hash mismatches' {
        $bundlePath = Join-Path -Path $TestDrive -ChildPath 'bundle-hash.zip'
        $outputPath = Join-Path -Path $TestDrive -ChildPath 'validation-hash.json'
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
            & $toolPath -BundleZipPath $bundlePath -OutputPath $outputPath | Out-Null
        } catch {
            $threw = $true
            $_.Exception.Message | Should Match 'hash mismatch'
        }
        $threw | Should Be $true
        $validation = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json
        $validation.Status | Should Be 'Fail'
        $validation.Counts.HashMismatches | Should Be 1
    }

    It 'fails when BundleManifest.json is missing' {
        $bundlePath = Join-Path -Path $TestDrive -ChildPath 'bundle-missing.zip'
        $outputPath = Join-Path -Path $TestDrive -ChildPath 'validation-missing.json'
        $fileBytes = [System.Text.Encoding]::UTF8.GetBytes('sample')

        New-ZipFromEntries -ZipPath $bundlePath -Entries @(
            @{ Name = 'Logs/Reports/sample.json'; Bytes = $fileBytes }
        )

        $threw = $false
        try {
            & $toolPath -BundleZipPath $bundlePath -OutputPath $outputPath | Out-Null
        } catch {
            $threw = $true
            $_.Exception.Message | Should Match 'BundleManifest.json'
        }
        $threw | Should Be $true
    }

    It 'blocks path traversal in manifest entries' {
        $bundlePath = Join-Path -Path $TestDrive -ChildPath 'bundle-traversal.zip'
        $outputPath = Join-Path -Path $TestDrive -ChildPath 'validation-traversal.json'
        $manifest = [ordered]@{
            SchemaVersion = '1.0'
            IncludedFiles = @(
                [ordered]@{
                    RelativePath = '../evil.txt'
                    Sha256       = 'DEADBEEF'
                    Bytes        = 1
                }
            )
        }
        $manifestBytes = [System.Text.Encoding]::UTF8.GetBytes(($manifest | ConvertTo-Json -Depth 5))

        New-ZipFromEntries -ZipPath $bundlePath -Entries @(
            @{ Name = 'BundleManifest.json'; Bytes = $manifestBytes }
        )

        $threw = $false
        try {
            & $toolPath -BundleZipPath $bundlePath -OutputPath $outputPath | Out-Null
        } catch {
            $threw = $true
            $_.Exception.Message | Should Match 'safe relative path'
        }
        $threw | Should Be $true
    }

    It 'handles extra files based on AllowExtraFiles' {
        $bundlePath = Join-Path -Path $TestDrive -ChildPath 'bundle-extra.zip'
        $outputPath = Join-Path -Path $TestDrive -ChildPath 'validation-extra.json'
        $outputAllowedPath = Join-Path -Path $TestDrive -ChildPath 'validation-extra-allowed.json'
        $relativePath = 'Logs/Reports/sample.json'
        $extraPath = 'Logs/Reports/extra.json'
        $fileBytes = [System.Text.Encoding]::UTF8.GetBytes('sample')
        $extraBytes = [System.Text.Encoding]::UTF8.GetBytes('extra')
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
            @{ Name = $relativePath; Bytes = $fileBytes },
            @{ Name = $extraPath; Bytes = $extraBytes }
        )

        $threw = $false
        try {
            & $toolPath -BundleZipPath $bundlePath -OutputPath $outputPath | Out-Null
        } catch {
            $threw = $true
            $_.Exception.Message | Should Match 'unexpected files'
        }
        $threw | Should Be $true

        $result = & $toolPath -BundleZipPath $bundlePath -OutputPath $outputAllowedPath -AllowExtraFiles -PassThru
        $result.Status | Should Be 'Pass'
        $result.ExtraFiles.Count | Should Be 1
    }
}
