# CLAUDE.md

Project-specific context for Claude Code.

## Project Overview

StateTrace is a PowerShell-based network device state tracking and parsing application. It ingests logs from various network device vendors (Cisco, Brocade, Arista), stores state in Access databases (.accdb), and provides a WPF UI for visualization and analysis.

## Repository Structure

- `Main/` - WPF application entry point (MainWindow.ps1, MainWindow.xaml)
- `Modules/` - Core PowerShell modules (parser, repository, UI modules)
- `Modules/Tests/` - Pester unit tests
- `Tools/` - Pipeline scripts, analyzers, and automation utilities
- `Data/` - Per-site .accdb stores and StateTraceSettings.json (gitignored except samples)
- `Logs/` - Ingestion metrics and telemetry exports (gitignored)
- `docs/` - Plans, runbooks, and automation references
- `Tests/` - Integration/smoke tests and fixtures
- `Views/`, `Templates/`, `Themes/` - UI assets

## Common Commands

### Run Tests
```powershell
Invoke-Pester Modules/Tests
```

### Run Full Ingestion Pipeline
```powershell
powershell -File Tools/Invoke-StateTracePipeline.ps1 -VerboseParsing
```
Use `-SkipTests` when the Pester suite already ran.

### Ad-hoc Parser Run
```powershell
Import-Module .\Modules\ParserWorker.psm1
Invoke-StateTraceParsing -Synchronous
```

### Warm-Run Regression
```powershell
Tools\Invoke-WarmRunRegression.ps1 -VerboseParsing
```

### Shared Cache Analysis
```powershell
Tools\Analyze-SharedCacheStoreState.ps1 -Path Logs\IngestionMetrics\<file>.json [-IncludeSiteBreakdown]
```

## Code Style

- PowerShell strict mode everywhere
- 4-space indentation
- PascalCase for exported functions
- camelCase for local variables
- Module-qualified calls: `DeviceRepositoryModule\Get-DbPathForSite`
- Use approved PowerShell verbs

## Key Guidelines

- **Run tests before every commit**: `Invoke-Pester Modules/Tests`
- **Never commit .accdb files or generated logs**
- **Keep diffs intentional and small**
- **Offline-first architecture**: Access-backed data stores
- **Parser/UI separation**: Keep parsing logic separate from UI modules
- **Reset overrides after experiments**: Set `-ThreadCeilingOverride`, `-MaxWorkersPerSiteOverride`, etc. back to `0`

## Documentation

- Main guide: `docs/StateTrace_AI_Agent_Guide.md`
- Runbook: `docs/CODEX_RUNBOOK.md`
- Plans index: `docs/plans/PlanIndex.md`
- Telemetry gates: `docs/telemetry/Automation_Gates.md`
