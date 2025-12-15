Set-StrictMode -Version Latest

$modulePath = Join-Path -Path $PSScriptRoot -ChildPath 'ParserPersistenceModule.psm1'
if (-not (Test-Path -LiteralPath $modulePath)) {
    throw "ParserPersistenceModule.psm1 not found at $modulePath"
}

try {
    # Import into module scope so we can re-export (works even when ParserPersistenceModule
    # is already loaded globally by ModulesManifest).
    Import-Module -Name $modulePath -ErrorAction Stop | Out-Null
} catch {
    throw ("Failed to import ParserPersistenceModule.psm1 from '{0}': {1}" -f $modulePath, $_.Exception.Message)
}

# Re-export core persistence helpers
Export-ModuleMember -Function `
    Set-InterfaceBulkChunkSize, `
    Update-DeviceSummaryInDb, `
    Update-InterfacesInDb, `
    Update-SpanInfoInDb, `
    Write-InterfacePersistenceFailure, `
    Get-LastInterfaceSyncTelemetry
