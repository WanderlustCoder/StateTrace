Set-StrictMode -Version Latest

function Get-StateTraceModulesFromManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ManifestPath
    )

    $resolvedManifestPath = $ManifestPath
    try { $resolvedManifestPath = [System.IO.Path]::GetFullPath($ManifestPath) } catch { $resolvedManifestPath = $ManifestPath }

    if (-not (Test-Path -LiteralPath $resolvedManifestPath)) {
        throw "Modules manifest not found at '$resolvedManifestPath'."
    }

    $manifest = $null
    try {
        if (Get-Command -Name Import-PowerShellDataFile -ErrorAction SilentlyContinue) {
            $manifest = Import-PowerShellDataFile -Path $resolvedManifestPath -ErrorAction Stop
        } else {
            $manifest = . $resolvedManifestPath
        }
    } catch {
        try {
            $manifest = . $resolvedManifestPath
        } catch {
            throw ("Failed to parse modules manifest at '{0}': {1}" -f $resolvedManifestPath, $_.Exception.Message)
        }
    }

    $modulesToImport = @()
    if ($manifest -is [System.Collections.IDictionary]) {
        if ($manifest.Contains('ModulesToImport') -and $manifest['ModulesToImport']) {
            $modulesToImport = @($manifest['ModulesToImport'])
        } elseif ($manifest.Contains('Modules') -and $manifest['Modules']) {
            $modulesToImport = @($manifest['Modules'])
        }
    } elseif ($manifest) {
        if ($manifest.PSObject.Properties.Name -contains 'ModulesToImport' -and $manifest.ModulesToImport) {
            $modulesToImport = @($manifest.ModulesToImport)
        } elseif ($manifest.PSObject.Properties.Name -contains 'Modules' -and $manifest.Modules) {
            $modulesToImport = @($manifest.Modules)
        }
    }

    $filtered = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in $modulesToImport) {
        $text = ''
        try { $text = ('' + $entry).Trim() } catch { $text = '' }
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        $filtered.Add($text) | Out-Null
    }

    if ($filtered.Count -eq 0) {
        throw "Modules manifest '$resolvedManifestPath' does not define ModulesToImport/Modules entries."
    }

    return $filtered.ToArray()
}

function Import-StateTraceModulesFromManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [string[]]$Exclude,
        [switch]$Force
    )

    $resolvedRepoRoot = $RepositoryRoot
    try { $resolvedRepoRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path } catch { $resolvedRepoRoot = $RepositoryRoot }

    $modulesRoot = Join-Path $resolvedRepoRoot 'Modules'
    try { $modulesRoot = [System.IO.Path]::GetFullPath($modulesRoot) } catch { }

    $manifestPath = Join-Path $modulesRoot 'ModulesManifest.psd1'
    $modulesToImport = Get-StateTraceModulesFromManifest -ManifestPath $manifestPath

    $excludeSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($excludeEntry in @($Exclude)) {
        if ([string]::IsNullOrWhiteSpace($excludeEntry)) { continue }
        $excludeSet.Add(($excludeEntry.Trim())) | Out-Null
        try { $excludeSet.Add(([System.IO.Path]::GetFileName($excludeEntry.Trim()))) | Out-Null } catch { }
    }

    $imported = [System.Collections.Generic.List[string]]::new()
    foreach ($moduleEntry in $modulesToImport) {
        if ([string]::IsNullOrWhiteSpace($moduleEntry)) { continue }

        $trimmedEntry = $moduleEntry.Trim()
        $fileName = $trimmedEntry
        try { $fileName = [System.IO.Path]::GetFileName($trimmedEntry) } catch { $fileName = $trimmedEntry }
        if ($excludeSet.Contains($trimmedEntry) -or $excludeSet.Contains($fileName)) {
            continue
        }

        $candidatePath = if ([System.IO.Path]::IsPathRooted($trimmedEntry)) {
            $trimmedEntry
        } else {
            Join-Path -Path $modulesRoot -ChildPath $trimmedEntry
        }

        if (-not (Test-Path -LiteralPath $candidatePath)) {
            throw "Module '$trimmedEntry' missing at '$candidatePath'."
        }

        $importArgs = @{
            Name        = $candidatePath
            Global      = $true
            ErrorAction = 'Stop'
        }
        if ($Force.IsPresent) {
            $importArgs['Force'] = $true
        }

        Import-Module @importArgs | Out-Null
        $imported.Add($trimmedEntry) | Out-Null
    }

    return $imported.ToArray()
}

Export-ModuleMember -Function Get-StateTraceModulesFromManifest, Import-StateTraceModulesFromManifest

