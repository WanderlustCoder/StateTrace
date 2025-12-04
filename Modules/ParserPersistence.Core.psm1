Set-StrictMode -Version Latest

if (-not (Get-Module -Name ParserPersistenceModule)) {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath 'ParserPersistenceModule.psm1'
    if (-not (Test-Path -LiteralPath $modulePath)) {
        throw "ParserPersistenceModule.psm1 not found at $modulePath"
    }
    Import-Module -Name $modulePath -Force
}

# Re-export core persistence helpers
Export-ModuleMember -Function `
    Initialize-ParserPersistenceState, `
    Write-InterfaceRecords, `
    Write-SpanRecords, `
    Write-TemplateRecords, `
    Get-LastInterfaceSyncTelemetry, `
    Get-LastParseDurationTelemetry
