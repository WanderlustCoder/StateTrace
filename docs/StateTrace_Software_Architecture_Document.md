# StateTrace Software Architecture Document

## 1. Purpose
This document describes the architecture of **StateTrace**, with an emphasis on:
- How data flows from raw device outputs/logs to operator UI surfaces.
- How the offline-first contract is maintained (Access-backed persistence, local-only telemetry).
- How automation harnesses produce auditable evidence (telemetry gates, bundles, governance).

This SAD is intended for maintainers and automation agents (including Codex) to make safe, testable changes.

## 2. Architectural drivers

### 2.1 Functional drivers
- Ingest network device outputs/logs and normalize interface/routing/state data.
- Persist results locally (offline-first) so operators can query without re-parsing.
- Provide operator workflows: Interfaces, Compare/Diff, SPAN snapshot, Search/Alerts, Port Reorg script generation, guided troubleshooting.
- Produce telemetry and "evidence bundles" that support performance/regression work and release governance.

### 2.2 Quality attributes
- **Offline-first:** Default operation requires no network access.
- **Auditability:** Every automation run should be reproducible; paths/hashes are recorded in plans/task board/session logs.
- **Performance:** Cold/warm latency gates exist (see `docs/telemetry/Automation_Gates.md`).
- **Reliability:** Dispatcher/scheduler health and queue delays are gated (Plan A / Plan I).
- **Security and privacy:** Sanitization tooling and NetOps logging are required for sensitive inputs (Plan F / Plan R).

## 3. System context

### 3.1 High-level context
StateTrace is a Windows-first toolchain built primarily around PowerShell modules and a WPF shell.

- **Input:** raw device outputs/logs (offline, local file system).
- **Processing:** PowerShell modules parse and normalize records; pipeline harness orchestrates concurrency.
- **Storage:** local Access `.accdb` plus auxiliary history and cache snapshots.
- **Presentation:** WPF UI reads from local stores and displays operator views.
- **Evidence:** telemetry files, analyzer reports, and bundles stored locally for release/governance.

### 3.2 Component overview (logical)

```mermaid
flowchart LR
  A[Raw logs / device outputs] --> B[Parser modules]
  B --> C[Persistence modules]
  C --> D[(Access .accdb)]
  B --> E[(Shared cache store)]
  E --> F[Shared cache snapshot (.clixml)]
  D --> G[WPF UI shell]
  B --> H[Telemetry writer]
  C --> H
  G --> H
  H --> I[Logs/IngestionMetrics/*.json]
  I --> J[Rollups / analyzers]
  J --> K[Logs/Reports/*]
  I --> L[Telemetry bundles]
  K --> L
  L --> M[Release evidence / governance]
```

**Notes**
- Shared cache snapshots are used to stabilize warm runs and reduce per-host access refresh work (Plan B / Plan Q).
- UI harnesses can run in headless mode to validate bindings and produce onboarding/adoption telemetry (Plan H / Plan O).

## 4. Runtime view

### 4.1 Cold pipeline run
A cold run parses inputs and writes normalized results into Access. Telemetry is emitted throughout.

Typical entrypoints:
- `Tools\Invoke-StateTracePipeline.ps1`
- `Tools\Invoke-StateTraceVerification.ps1` (wraps pipeline + assertions)

Outputs:
- Telemetry: `Logs/IngestionMetrics/<date>.json`
- Reports: `Logs/Reports/*` (e.g., site diversity, scheduler launch, queue delay summaries)
- Optionally: shared cache snapshots under `Logs/SharedCacheSnapshot/`

### 4.2 Warm run regression
A warm run replays the corpus after caches are seeded/imported to validate improvement and cache-hit behavior.

Typical entrypoints:
- `Tools\Invoke-WarmRunTelemetry.ps1` / `Tools\Invoke-WarmRunRegression.ps1`
- `Tools\Invoke-SharedCacheWarmup.ps1`

Outputs:
- Warm-run telemetry JSON: `Logs/IngestionMetrics/WarmRunTelemetry-*.json`
- Diff hotspot CSVs or reports (when enabled)
- Shared cache analyzers and provider reason summaries

### 4.3 Operator interactive session
Operators use the WPF shell to browse Interfaces, run comparisons, capture SPAN snapshots, and generate Port Reorg scripts.

UI entrypoints are typically anchored in:
- `Main/MainWindow.ps1`
- View modules such as `Modules/PortReorgViewModule.psm1`

Headless validation entrypoints exist for reliability:
- `Tools\Invoke-InterfacesViewChecklist.ps1`
- `Tools\Invoke-SearchAlertsSmokeTest.ps1`
- `Tools\Invoke-SpanViewSmokeTest.ps1`

## 5. Data view

### 5.1 Primary stores
- **Access database (`.accdb`)**  
  Primary offline store for normalized operational data. Exact schema is subject to change; treat it as a contract that must remain backward compatible across releases unless explicitly versioned.

- **Shared cache store and snapshots (`.clixml`)**  
  A serialized cache used to improve warm runs by avoiding repeated Access work and enabling fast hydration across runspaces. Snapshots are rotated and governed (Plan Q).

- **Ingestion history (`Data/IngestionHistory/`)**  
  Local history enabling incremental workflows and freshness indicators (Plan D / Plan H).

- **Postmortems (`Data/Postmortems/`)**  
  Sanitized incident data used for debugging and regression reproduction (Plan F / Plan R). Raw evidence must not be committed.

### 5.2 Evidence and telemetry
- **Telemetry:** `Logs/IngestionMetrics/*.json`
- **Analyzer outputs:** `Logs/Reports/*`
- **Verification summaries:** `Logs/Verification/VerificationSummary-*.json`
- **Bundles:** `Logs/TelemetryBundles/<bundle>/` (includes a README with hashes)

### 5.3 Telemetry schema ownership
Telemetry naming, required fields, and rollup expectations are defined in:
- `docs/telemetry/Phase1_metrics.md`
- `docs/telemetry/Automation_Gates.md`

## 6. Key modules and responsibilities

The following module names are used throughout the plans and harnesses:

- `Modules/DeviceRepositoryModule.psm1`  
  Repository/cache layer, shared cache read/write, snapshot import/export helpers.

- `Modules/ParserPersistenceModule.psm1`  
  Persistence and diff/comparison logic; responsible for staged writes and emitting persistence timing telemetry.

- `Tools/*`  
  Orchestration scripts:
  - Pipeline and verification (`Invoke-StateTracePipeline`, `Invoke-StateTraceVerification`, scheduled verification)
  - Warm-run harness (`Invoke-WarmRunTelemetry`, `Invoke-WarmRunRegression`)
  - Rollups and bundling (`Invoke-DailyMetricRollup`, `Rollup-IngestionMetrics`, `Publish-TelemetryBundle`)
  - UI headless smoke tools
  - Lints and checklists (`Invoke-AllChecks`, doc-sync checklist, telemetry/bundle readiness checks)

- `Main/*`  
  WPF shell entrypoints and UI wiring.

Plan L drives the long-term decomposition strategy to reduce module coupling and clarify contracts.

## 7. Security and compliance

### 7.1 Offline-first and online-mode guardrails
Online actions (downloads, installs) are optional and must be explicitly authorized. Requirements:
- Use allowlisted wrappers (e.g., `Tools/NetworkGuard.psm1::Invoke-AllowedDownload`).
- Produce NetOps logs under `Logs/NetOps/`.
- Reset online-mode flags and record the reset evidence.

See:
- `docs/Security.md`
- `docs/CODEX_AUTONOMY_PLAN.md`
- `docs/plans/PlanF_SecurityIdentity.md`
- `docs/templates/NetOpsLogTemplate.json`

### 7.2 Sanitization
Incident and postmortem data must be sanitized before it can be committed or used as fixtures:
- Sanitized outputs live under `Data/Postmortems/<IncidentId>/Sanitized`.
- Sanitization reports live under `Logs/Sanitization/<IncidentId>.json`.

See `docs/StateTrace_IncidentPostmortem_Intake.md` and `docs/templates/SanitizationEvidenceTemplate.md`.

## 8. Release and governance
Release governance is evidence-driven:
- Run verification harnesses and capture summaries.
- Publish telemetry bundles and verify readiness (hashes, required artifacts).
- Update plans/task board/risk register and attach evidence links.

See:
- `docs/plans/PlanG_ReleaseGovernance.md`
- `docs/Release.md`
- `docs/runbooks/Telemetry_Bundle_Verification.md`

## 9. Testing strategy (high level)
- Pester tests under `Modules/Tests/*` provide unit/regression coverage.
- `Tools\Invoke-AllChecks.ps1` aggregates linting and smoke checks.
- UI-specific headless smokes validate binding and basic interaction without requiring a full operator desktop session.

CI readiness workstreams are tracked in Plan K and Plan J.

## 10. Glossary
- **Cold run:** A parse/persist run where caches are not warmed or are intentionally reset.
- **Warm run:** A subsequent run that should reuse caches/snapshots to reduce latency.
- **Shared cache snapshot:** Serialized cache state used to improve warm runs and make results repeatable.
- **Telemetry bundle:** A curated folder containing telemetry, analyzer outputs, and hashes used for governance and release evidence.
- **NetOps log:** A JSON evidence file recording any allowed network activity during development/automation sessions.

