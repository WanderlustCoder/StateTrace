# Developer Setup

This document defines the authoritative, offline-friendly developer bootstrap path for StateTrace.

The goal is that an agent (or a new developer) can:
1) prepare a clean workstation without tribal knowledge,
2) run a cold pipeline + warm telemetry + verification,
3) produce bundle-ready artifacts under `Logs/`,
4) do so without downloading dependencies during the run.

## LANDMARK: Supported environment

**Primary supported host**
- OS: Windows 10/11 (x64), 22H2+ recommended.
- PowerShell: Windows PowerShell 5.1 (required for WPF + harness scripts).
- Git: 2.46.0 (pinned by `Tools/Bootstrap-DevSeat.ps1`; newer ok).
- .NET: .NET Framework 4.8+ (ships with Windows 10/11; no separate SDK required).
- Node/npm: not required for current UI (WPF/XAML only).

**Not supported (unless explicitly validated)**
- Non-Windows hosts (unless a documented WSL/CI path exists).
- PowerShell 7 as the only runner for UI/harness workflows.

## LANDMARK: Prerequisites

### Toolchain
Install (or verify) the following tools:

- Git
- Windows PowerShell 5.1
- Optional tooling: Python 3.11 and Graphviz (install helper in `Tools/Bootstrap-DevSeat.ps1`)

### Access DB provider
StateTrace plans reference Access persistence and Access connection caching.

- Provider: `Microsoft.ACE.OLEDB.12.0` (primary); Jet `Microsoft.Jet.OLEDB.4.0` fallback for legacy `.mdb`.
- Architecture: match the process bitness (x64 recommended).
- Offline installer location: internal share or local package repository (record exact path in your session log when used).

Validation hint (PowerShell):
```powershell
# LANDMARK: Verify Access provider availability
Get-ItemProperty "HKLM:\SOFTWARE\Classes\Microsoft.ACE.OLEDB.12.0" -ErrorAction SilentlyContinue
```

### PowerShell execution policy
Recommended (CurrentUser) policy for developer seats:

```powershell
# LANDMARK: Execution policy (CurrentUser only)
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
Get-ExecutionPolicy -List
```

## LANDMARK: Repo acquisition

1. Clone the repository:
   ```powershell
   git clone https://github.com/WanderlustCoder/StateTrace.git
   cd <repo-root>
   ```

2. Confirm you are in the repo root:
   ```powershell
   # LANDMARK: Repo root marker checks
   Test-Path .\Tools
   Test-Path .\Modules
   Test-Path .\docs
   ```

## LANDMARK: Bootstrap (offline-first)

`Tools/Bootstrap-DevSeat.ps1` is an online install helper and requires `STATETRACE_AGENT_ALLOW_INSTALL=1`. Use it only when online mode is explicitly approved.

Offline validation checklist:
- PowerShell 5.1 is available (`$PSVersionTable.PSVersion`).
- `pwsh.exe` is available for harness wrappers.
- Access provider is installed (`Microsoft.ACE.OLEDB.12.0`).
- Repository path is not blocked (no `Zone.Identifier` markers).
- Long path support is enabled if the environment uses deep module paths.

## LANDMARK: Minimum smoke commands

The minimum smoke is designed to be:
- deterministic,
- runnable offline,
- and sufficient to validate core harness paths.

### 1) Cold pipeline run (tracked corpus)
```powershell
# LANDMARK: Cold pipeline (tracked corpus)
Tools\Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -ResetExtractedLogs -RunSharedCacheDiagnostics -RunQueueDelayHarness -VerifyTelemetryCompleteness -FailOnTelemetryMissing
```

Expected outputs (examples):
- `Logs/IngestionMetrics/<date>.json`
- `Logs/IngestionMetrics/QueueDelaySummary-<timestamp>.json`
- `Logs/Reports/PortBatchSiteDiversity-<timestamp>.json`
- `Logs/SharedCacheDiagnostics/SharedCacheStoreState-<timestamp>.json`

### 2) Verification harness
```powershell
# LANDMARK: Verification harness
Tools\Invoke-StateTraceVerification.ps1 -SkipTests -VerboseParsing -ResetExtractedLogs -GenerateSharedCacheDiagnostics -GenerateDiffHotspotReport
```

### 3) Warm-run telemetry (guarded)
```powershell
# LANDMARK: Warm-run telemetry
Tools\Invoke-WarmRunTelemetry.ps1 -VerboseParsing -ResetExtractedLogs -GenerateDiffHotspotReport -OutputPath Logs/IngestionMetrics/WarmRunTelemetry-<timestamp>.json
```

Expected outputs (examples):
- `Logs/IngestionMetrics/WarmRunTelemetry-<timestamp>.json`
- `Logs/IngestionMetrics/DiffHotspots-<timestamp>.csv`

### 4) Publish a telemetry bundle (for governance/traceability)
```powershell
# LANDMARK: Bundle publish
Tools\Publish-TelemetryBundle.ps1 -BundleName DevSeatSmoke-<timestamp> -PlanReferences PlanK,PlanE,PlanG -TaskBoardIds ST-K-006 -Notes "Developer seat smoke validation"
```

Expected outputs:
- `Logs/TelemetryBundles/DevSeatSmoke-<timestamp>/<Area>/TelemetryBundle.json`
- `Logs/TelemetryBundles/DevSeatSmoke-<timestamp>/<Area>/README.md`

## LANDMARK: Offline rules

To keep runs deterministic:
- Do not download dependencies during harness execution.
- Vendor PowerShell modules in-repo (or use an internal offline feed, but document it).
- Ensure fixtures are either committed seeds or generated deterministically from committed templates.
- If online mode is required for a specific task, use the documented online-mode gating process and log the reason (Plan F).

## LANDMARK: Troubleshooting

See `docs/troubleshooting/Common_Failures.md`.
