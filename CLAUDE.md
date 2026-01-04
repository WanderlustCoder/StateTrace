# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

StateTrace is a network device state tracking and analysis application built with PowerShell and WPF. It ingests network device logs (Cisco, Arista, Brocade), parses them into Microsoft Access databases, and provides a WPF UI for searching, comparing, and analyzing device interface states.

**Key characteristics:**
- PowerShell 5.1 (Windows PowerShell) + WPF + Access databases (ACE OLEDB provider)
- Strict parser/UI separation: parse logs → Access DB (offline), then UI loads from database
- Offline-first: no external dependencies, no Node/npm
- Documentation-first: docs are the source of truth, update them before/after code changes

## Build and Run Commands

```powershell
# Run the UI (main entry point) - requires STA mode for WPF
powershell -STA -File Main\MainWindow.ps1

# Run the cold parser pipeline
Tools\Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -ResetExtractedLogs

# Run verification harness
Tools\Invoke-StateTraceVerification.ps1 -SkipTests -VerboseParsing -ResetExtractedLogs

# Run warm-run telemetry capture
Tools\Invoke-WarmRunTelemetry.ps1 -GenerateDiffHotspotReport -OutputPath Logs/IngestionMetrics/WarmRunTelemetry.json
```

## Testing Commands

```powershell
# Run all Pester unit tests
Invoke-Pester Modules\Tests -CI -Output Detailed

# Run fast checks (lint, Pester, UI harnesses)
Tools\Invoke-AllChecks.ps1

# Run UI smoke tests (headless)
Tools\Invoke-SearchAlertsSmokeTest.ps1
Tools\Invoke-SpanViewSmokeTest.ps1 -Hostname <host>
Tools\Invoke-InterfacesViewChecklist.ps1 -SiteFilter WLLS,BOYO -MaxHosts 10

# Run single test file
Invoke-Pester -Path Modules\Tests\<TestFile>.Tests.ps1 -Output Detailed
```

## Architecture

### Directory Structure

- `Main/` - WPF UI entrypoint (MainWindow.ps1/xaml)
- `Modules/` - Core PowerShell modules (parser, repository, UI logic)
- `Modules/Tests/` - Pester unit tests
- `Views/` - XAML user control definitions
- `Tools/` - Automation scripts (pipeline, verification, analysis)
- `Tests/` - Integration tests and fixtures
- `Data/` - Per-site Access databases (gitignored except samples)
- `Logs/` - Generated artifacts (gitignored)
- `docs/` - Plans, runbooks, schemas, architecture docs
- `docs/plans/` - Plans A-S (high-level initiatives)
- `Themes/` - WPF theme JSON files

### Key Module Categories

**Parser Pipeline:**
- `DeviceLogParserModule` - Device log parsing
- `AristaModule`, `CiscoModule`, `BrocadeModule` - Vendor-specific parsing
- `ParserWorker`, `ParserRunspaceModule` - Parallel worker management
- `ParserPersistenceModule` - Writes to Access DBs

**Data Layer:**
- `DeviceRepositoryModule` - Unified data access layer
- `DeviceRepository.Access` - Access DB provider
- `DeviceRepository.Cache` - Shared cache strategy
- `DatabaseModule` - OLEDB operations

**UI Stack:**
- View modules (`InterfaceModule`, `CompareViewModule`, etc.) - Business logic
- `ViewCompositionModule` - Binding and composition
- `ThemeModule` - Theming and styling

### Data Flow

1. Raw device logs → Parser modules (vendor-specific)
2. Parsed data → Access databases per site (`Data/<site>/*.accdb`)
3. UI loads from databases with optional shared cache layer
4. Telemetry emitted to `Logs/IngestionMetrics/`

## Code Conventions

- **Strict Mode:** `Set-StrictMode -Version Latest` everywhere
- **Verbs:** Must use official `Get-Verb` list
- **Indentation:** 4 spaces
- **Casing:** PascalCase for exports, camelCase for locals
- **Module calls:** Qualified (`DeviceRepositoryModule\Get-DbPathForSite`)

## Configuration

Settings stored in `Data/StateTraceSettings.json`:
```json
{
    "DebugOnNextLaunch": true,
    "ParserSettings": {
        "AutoScaleConcurrency": true,
        "MaxRunspaceCeiling": 0,
        "MaxWorkersPerSite": 0,
        "EnableAdaptiveThreads": true
    }
}
```

## Test Gates (Release Blocking)

From `docs/telemetry/Automation_Gates.md`:
- Queue delay: p95 ≤ 120ms, p99 ≤ 200ms
- Port diversity: max streak ≤ 8
- Warm cache improvement: ≥ 60% (release) or ≥ 25% (dev)
- Warm cache hit ratio: ≥ 99%
- Shared cache: SnapshotImported > 0, GetHit > GetMiss

## Prerequisites

- Windows 10/11 with PowerShell 5.1
- .NET Framework 4.8+ (included with Windows)
- Microsoft.ACE.OLEDB.12.0 provider
- Execution policy: `Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned`

## Key Documentation

- `docs/CODEX_RUNBOOK.md` - Command matrix for all automation tasks
- `docs/Test_Strategy.md` - Test layers and gates
- `docs/Core_Ideas.md` - 7 core pillars
- `docs/plans/PlanIndex.md` - Overview of all plans (A-S)
- `AGENTS.md` - Quick reference for AI agents
