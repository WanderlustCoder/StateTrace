# Test Strategy

This document is the canonical description of:
- what tests exist,
- how to run them,
- what "pass" means,
- and what artifacts must be produced to claim completion.

It is written so a Codex-style agent can determine completion without subjective interpretation.

## LANDMARK: Test layers

### 1) Fast checks / lint
**Goal:** Catch obvious contract violations and harness regressions quickly.

**Entry point (preferred):**
- `Tools\Invoke-AllChecks.ps1` (unused export lint, Pester, Span harness, Search/Alerts harness, NetOps lint, doc-sync checks, telemetry bundle readiness, telemetry integrity).

**Requirements:**
- Must run in <= 20 minutes on a clean dev seat (Plan K baseline).
- Must fail with a non-zero exit code on violations.
- If a desktop session is unavailable, use `-SkipSpanHarness` or provide a known `-SpanHostname` and pass `-SkipSearchAlertsHarness` when the WPF host cannot be created.

### 2) Unit tests (Pester)
**Goal:** Validate modules with deterministic, small fixtures.

**Convention:**
- Place tests under `Modules\Tests\*.Tests.ps1`.
- Tests must not depend on gitignored logs; embed minimal fixtures inline or use committed seeds.

**Command (example):**
```powershell
# LANDMARK: Pester unit tests
Invoke-Pester -Path .\Modules\Tests -CI -Output Detailed
```

### 3) Integration / harness smoke (minimal fixtures)
**Goal:** Validate that primary harness entrypoints run end-to-end on a minimal corpus.

**Command (example):**
```powershell
# LANDMARK: Pipeline smoke
Tools\Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -ResetExtractedLogs -RunSharedCacheDiagnostics -RunQueueDelayHarness
```

### 4) Verification harness
**Goal:** Validate gating and correctness checks on the artifacts produced by the pipeline.

**Command (example):**
```powershell
# LANDMARK: Verification harness
Tools\Invoke-StateTraceVerification.ps1 -SkipTests -VerboseParsing -ResetExtractedLogs -GenerateSharedCacheDiagnostics -GenerateDiffHotspotReport
```

### 5) Warm-run telemetry / regression
**Goal:** Confirm warm cache behavior and performance telemetry gates.

**Command (example):**
```powershell
# LANDMARK: Warm-run telemetry
Tools\Invoke-WarmRunTelemetry.ps1 -VerboseParsing -ResetExtractedLogs -GenerateDiffHotspotReport
```

Optional (preserved-session warm regression):
- `Tools\Invoke-WarmRunRegression.ps1 -VerboseParsing`

### 6) UI smoke
**Goal:** Validate that critical UI surfaces render and that accessibility/responsiveness expectations are met.

**Sources:**
- `docs/UI_Smoke_Checklist.md` (manual checklist)
- Headless harnesses: `Tools\Invoke-SearchAlertsSmokeTest.ps1`, `Tools\Invoke-SpanViewSmokeTest.ps1`, `Tools\Invoke-InterfacesViewSmokeTest.ps1` or `Tools\Invoke-InterfacesViewChecklist.ps1`
- Desktop harness runner: `Tools\Invoke-DesktopUIHarness.ps1` (Span/Search/Alerts evidence under `Logs/UIHarness/`)

## LANDMARK: Pass/fail definition

A change is "test complete" when all applicable checks pass:

| Change type | Required checks |
|-------------|-----------------|
| PowerShell module change | Fast checks + Pester tests + pipeline smoke |
| Harness change (`Tools\*.ps1`) | Fast checks + pipeline smoke + verification harness |
| Telemetry schema/rollup change | Pipeline smoke + verification + rollup validation + bundle publish |
| Performance / cache change | Warm-run telemetry + required gates + shared cache diagnostics |
| UI change | UI smoke checklist + headless UI smoke (where available) |

## LANDMARK: Required gates (defaults; update if plans change)

These gates are referenced in `docs/telemetry/Automation_Gates.md` and should be treated as release-blocking unless explicitly waived with a documented reason.

### Queue delay summary
- `p95 <= 120 ms`
- `p99 <= 200 ms`
- `SampleCount >= 10` (default `QueueDelayMinimumSampleCount`). `InsufficientData` fails unless `-SkipQueueDelayEvaluation` is documented.

### Port batch diversity (streak guard)
- `max streak <= 8`
- Failure blocks warm pass unless explicitly waived in:
  - the relevant plan page
  - and the Task Board row

### Warm cache health
- Verification harness defaults: `WarmRunComparison.ImprovementPercent >= 25` and `WarmCacheHitRatioPercentRaw >= 99`.
- Plan B/G release gates: `WarmRunComparison.ImprovementPercent >= 60` and cache hit ratio >= 99 (see `docs/telemetry/Automation_Gates.md`).
- Provider reason distribution should not be dominated by `SharedCacheUnavailable` for key fixture sites (BOYO, WLLS).

### Shared cache diagnostics
- `SnapshotImported > 0`
- `GetHit > GetMiss` for key fixture sites (BOYO, WLLS)

## LANDMARK: Required artifacts for evidence

Each run must emit artifacts under `Logs\` that allow a reviewer (or agent) to verify results without re-running immediately.

Minimum expected:
- `Logs/IngestionMetrics/<date>.json`
- `Logs/IngestionMetrics/QueueDelaySummary-<timestamp>.json`
- `Logs/Reports/PortBatchSiteDiversity-<timestamp>.json` (for warm-run workstreams)
- `Logs/SharedCacheDiagnostics/SharedCacheStoreState-<timestamp>.json` (when cache work is involved)
- `Logs/SharedCacheDiagnostics/SiteCacheProviderReasons-<timestamp>.json` (when cache work is involved)
- `Logs/IngestionMetrics/DiffHotspots-<timestamp>.csv` (when enabled)
- `Logs/TelemetryBundles/<bundle>/<Area>/TelemetryBundle.json` (for bundle-ready work)

## LANDMARK: Adding/adjusting tests

When adding a new test:
- Prefer Pester for deterministic module behavior.
- If you need fixture material:
  - commit seeds/templates, not large generated logs
  - document generation in `docs/fixtures/README.md`
- Ensure tests fail fast and produce actionable error messages.

When changing a gate:
- Update this file.
- Update `docs/telemetry/Automation_Gates.md` and/or the plan(s) that reference it.
- Update any verification scripts that enforce the gate.
