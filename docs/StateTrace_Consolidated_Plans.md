# StateTrace Ã¢â‚¬â€ Consolidated Planning Dossier
> Generated: 2025-09-30 19:45 UTC

This dossier consolidates the planning documents in `docs/` into a small set of **like plans**. Each consolidated plan merges overlapping goals, normalizes terminology, and lists crisp deliverables, scope boundaries, acceptance criteria, metrics, risks, and next actions.

## Source corpus
The following source documents were reviewed and folded into the plan set:
- `AGENT_INSTRUCTIONS.txt`
- `AI_Agent_Terminal_Prompt.txt`
- `README.md`
- `Release.md`
- `RiskRegister.md`
- `Security.md`
- `StateTrace_AI_Agent_Guide.md`
- `StateTrace_Acknowledgement_Identity_Options.md`
- `StateTrace_Deduplication_Plan.md`
- `StateTrace_DiffModel_Prototype.md`
- `StateTrace_FeatureExpansion_WorkshopPlan.md`
- `StateTrace_Feature_Expansion_Plan.md`
- `StateTrace_Functions_Features.md`
- `StateTrace_IncidentPostmortem_Intake.md`
- `StateTrace_LaunchMetrics_DashboardDraft.md`
- `StateTrace_MultiDatabase_Ingestion_Plan.md`
- `StateTrace_Performance_Plan.md`
- `StateTrace_Quarterly_Roadmap.md`
- `StateTrace_Routing_DataArchitecture.md`
- `StateTrace_Routing_Discovery_Workplan.md`
- `StateTrace_Routing_Reliability_Plan.md`
- `StateTrace_Routing_ResourcePlan.md`
- `StateTrace_TaskBoard.md`
- `adr/0004-online-mode-and-tooling.md`
- `agents/Agent_Kickoff_Tasks.md`
- `agents/Agent_PR_Checklist.md`
- `agents/Agent_Session_Template.md`
- `agents/sessions/2025-09-30_session-0001.md`
- `agents/sessions/2025-09-30_session-0002.md`
- `completed/README.md`
- `notes/2025-10-03_feature-expansion.md`
- `notes/2025-10-04_routing-discovery.md`
- `telemetry/Phase1_metrics.md`
- `templates/runbook-template.md`

---

## Executive summary
- **Routing Reliability** becomes a single crossÃ¢â‚¬â€˜cutting program (data model, discovery, health scoring, alerting, and rollout) driven by a _Routing Working Set_ of docs merged below.
- **Performance & Ingestion Scale** unifies perf hotÃ¢â‚¬â€˜spot fixes, multiÃ¢â‚¬â€˜DB concurrency, and code deduplication under one engineering plan with measurable p95 targets.
- **Change Tracking (Diff)** provides AccessÃ¢â‚¬â€˜backed perÃ¢â‚¬â€˜run snapshots and a diff UI, treated as a feature enabler for drift detection and guided troubleshooting.
- **Feature Expansion** sequences UX surface area (anomaly cards, guided runbooks) behind the telemetry and diff groundwork.
- **Telemetry & Launch Metrics** defines a PhaseÃ‚Â 1 dictionary and dashboard to verify adoption and SLA outcomes.
- **Security, Identity & Online Mode** aligns ADRÃ¢â‚¬â€˜0004, security hygiene, and acknowledgement/identity decisions into a practical, offlineÃ¢â‚¬â€˜first implementation plan.
- **Release & Governance** ties the Risk Register, release guide, and quarterly roadmap to an operating cadence.

---

## Mapping: source Ã¢â€ â€™ consolidated plan
**Routing Reliability**
: `StateTrace_Routing_Reliability_Plan.md`
: `StateTrace_Routing_Discovery_Workplan.md`
: `StateTrace_Routing_DataArchitecture.md`
: `StateTrace_Routing_ResourcePlan.md`
: `notes/2025-10-04_routing-discovery.md`

**Performance & Ingestion Scale**
: `StateTrace_Performance_Plan.md`
: `StateTrace_MultiDatabase_Ingestion_Plan.md`
: `StateTrace_Deduplication_Plan.md`

**Change Tracking (Diff model)**
: `StateTrace_DiffModel_Prototype.md`
: `StateTrace_Feature_Expansion_Plan.md`
: `notes/2025-10-03_feature-expansion.md`

**Feature Expansion & Guided Troubleshooting**
: `StateTrace_Feature_Expansion_Plan.md`
: `StateTrace_FeatureExpansion_WorkshopPlan.md`
: `StateTrace_Functions_Features.md`

**Telemetry & Launch Metrics**
: `telemetry/Phase1_metrics.md`
: `StateTrace_LaunchMetrics_DashboardDraft.md`

**Security, Identity & Online Mode**
: `Security.md`
: `adr/0004-online-mode-and-tooling.md`
: `StateTrace_Acknowledgement_Identity_Options.md`

**Release & Governance**
: `Release.md`
: `StateTrace_Quarterly_Roadmap.md`
: `RiskRegister.md`
: `StateTrace_IncidentPostmortem_Intake.md`
: `templates/runbook-template.md`
: `StateTrace_TaskBoard.md`

**AI Agent Program (contributor ops)**
: `StateTrace_AI_Agent_Guide.md`
: `AGENT_INSTRUCTIONS.txt`
: `agents/Agent_Kickoff_Tasks.md`
: `agents/Agent_PR_Checklist.md`
: `agents/Agent_Session_Template.md`
: `agents/sessions/2025-09-30_session-0001.md`
: `agents/sessions/2025-09-30_session-0002.md`

---

## Plan quick links

- [Plan A - Routing Reliability](#plan-a-routing-reliability)
- [Plan B - Performance and Ingestion Scale](#plan-b-performance-ingestion-scale)
- [Plan C - Change Tracking (Diff Snapshots)](#plan-c-change-tracking-diff-snapshots)
- [Plan D - Feature Expansion and Guided Troubleshooting](#plan-d-feature-expansion-guided-troubleshooting)
- [Plan E - Telemetry and Launch Metrics](#plan-e-telemetry-launch-metrics)
- [Plan F - Security, Identity and Online Mode](#plan-f-security-identity-online-mode)
- [Plan G - Release, Risk and Governance](#plan-g-release-risk-governance)

<a id="plan-a-routing-reliability"></a>
## Plan A Ã¢â‚¬â€ Routing Reliability
**Objective:** Detect and explain primary route outages within 60Ã‚Â seconds with actionable remediation and historical trendability, while keeping Access as the PhaseÃ‚Â 1 store.

**Scope (PhaseÃ‚Â 1):**
- Canonical schemas: `RouteRecord`, `RouteHealthSnapshot`, `OutageEvent`, `RemediationTask`, `NotificationPreference`.
- Ingestion pipelines for SNMP/probes/logs; correlation by `RouteRecord.Id`.
- Health scoring w/ debouncing; state transitions (healthy Ã¢â€ â€™ degraded Ã¢â€ â€™ down Ã¢â€ â€™ recovered).
- Operator UI: route list, detail, history, owner metadata, links to runbooks; alerting hooks.
- Retention: 30Ã¢â‚¬â€˜day snapshots (highÃ¢â‚¬â€˜res), 12Ã¢â‚¬â€˜month aggregates (trend).

**Out of scope (PhaseÃ‚Â 1):** new external services, replacing Access, multiÃ¢â‚¬â€˜tenant auth flows.

**Deliverables:**
- ERD + sequence notes (stored under `Resources/architecture/routing/`).
- Access DDL for the five tables + indices (Hostname/RouteId/Status/Timestamp).
- PowerShell health evaluator service (script) + unit tests; telemetry for state transitions.
- Dashboards: missing/stale/conflicting signal monitors.

**Acceptance criteria:**
- p95 detection latency Ã¢â€°Â¤Ã‚Â 60Ã‚Â s for primary route failures in testbed.
- Conflicting signal rate <Ã‚Â 2% daily; all alerts link to runbooks.
- Route ownership visible in UI and via API; audit trail for acknowledgements.

**Risks & mitigations:**
- Signal sparsity Ã¢â€¡â€™ add synthetic probes; flag data gaps in telemetry.
- Alert fatigue Ã¢â€¡â€™ tune thresholds; staged rollout; feature flags.
- SoloÃ¢â‚¬â€˜operator bandwidth Ã¢â€¡â€™ timeÃ¢â‚¬â€˜box discovery (see resource plan) and sequence work via roadmap.

**Roadmap alignment:** See `StateTrace_Quarterly_Roadmap.md` milestone **M2 Ã¢â‚¬â€œ Routing discovery baseline** (target 2025Ã¢â‚¬â€˜11Ã¢â‚¬â€˜15) and subsequent backend/UI work. 

<a id="plan-b-performance-ingestion-scale"></a>
## Plan B Ã¢â‚¬â€ Performance & Ingestion Scale
**Objective:** Improve endÃ¢â‚¬â€˜toÃ¢â‚¬â€˜end ingestion throughput without functional changes, supporting growth in perÃ¢â‚¬â€˜site Access databases and concurrent parsing.

**Workstreams:**
1. **WarmÃ¢â‚¬â€˜up & streaming parser** Ã¢â‚¬â€ module preloading caches; streaming line pipeline; memory bound below a fixed ceiling.
2. **MultiÃ¢â‚¬â€˜DB concurrency** Ã¢â‚¬â€ siteÃ¢â‚¬â€˜scoped mutexes; connection reuse; staging tables; adaptive runspace pool surfaced in `StateTraceSettings.json`.
3. **Persistence tuning** Ã¢â‚¬â€ parameterized `ADODB.Command`, batched writes, reduced autoÃ¢â‚¬â€˜flush, writeÃ¢â‚¬â€˜latency telemetry.
4. **Deduplication** Ã¢â‚¬â€ shared vendorÃ¢â‚¬â€˜agnostic parsers; common UI composition helpers; central filter service; simpler `ParserWorker` orchestration.


**Execution playbook:**
- `Tools/Invoke-StateTracePipeline.ps1` orchestrates module preloading, optional test execution, and a synchronous call to `Invoke-StateTraceParsing`; it returns green when ingestion completes without exceptions.
  - `-SkipTests` bypasses `Invoke-Pester Modules/Tests` (useful during rapid iteration when the suite has already passed).
  - `-SkipParsing` stops after validation so agents can gate code review on test results alone.
  - `-DatabasePath` points the run at an alternate Access root; omit to use the per-site layout under `Data/`.
  - `-VerboseParsing` surfaces per-device progress and autoscaling decisions in the console.
- Recommended invocation: `powershell -File Tools/Invoke-StateTracePipeline.ps1 -VerboseParsing` so verbose logs and metrics (e.g., `ParseDuration`, `DatabaseWriteLatency`) can be captured alongside run output under `Logs/IngestionMetrics/`.

**Autoscaling workflow overview:**
- `Data/StateTraceSettings.json` enables `AutoScaleConcurrency` by default; zero-valued ceilings (`MaxRunspaceCeiling`, `MaxWorkersPerSite`, `MaxActiveSites`, `JobsPerThread`) hand control to `Get-AutoScaleConcurrencyProfile`.
- `Invoke-StateTraceParsing` consumes the generated profile to set thread ceilings, per-site worker limits, active site caps, and job batching while respecting any manual overrides greater than zero.
- Each ingestion run emits telemetry (`ParseDuration`, `DatabaseWriteLatency`, `SkippedDuplicate`) that should be appended to `Logs/IngestionMetrics/` for trend monitoring.

**Troubleshooting checklist:**
- If the pipeline exits before ingestion, confirm `Invoke-Pester` is available or rerun with `-SkipTests`.
- Missing module errors usually mean `Modules/ModulesManifest.psd1` is stale; run `Tools/Bootstrap-DevSeat.ps1` or update the manifest before retrying.
- Unexpected low concurrency indicates manual ceilings remain non-zero; reset the hints to `0` in `StateTraceSettings.json` unless a cap is intentional.



**2025-09-30 stress-test snapshot:**
- Corpus: 37 raw log files produced 38 extracted device slices (BOYO and WLLS); _unknown.log remains vendor-unknown and is skipped after warning.
- Auto-scale profile (CPU=32): ThreadCeiling=24, MaxWorkersPerSite=8, MaxActiveSites=3, JobsPerThread=2, MinRunspaces=1.
- Latest ingestion run (13:06 MT) recorded 37 writes with DatabaseWriteLatency averages of ~281 ms (BOYO) and ~259 ms (WLLS); p95 peaked at 564 ms.
- Metric coverage is limited to RowsWritten/DatabaseWriteLatency; no ParseDuration events were emitted, leaving parser timing unobserved.

**Follow-ups:**
- Trial reduced ceilings (e.g., MaxWorkersPerSite=4 or MaxActiveSites=2) to evaluate latency impact versus throughput.
- Extend telemetry to emit ParseDuration and auto-scale decisions so future runs capture full pipeline timing. (Done: ParseDuration + ConcurrencyProfileResolved events now logged in pipeline telemetry.)
- Investigate _unknown.log classification to remove warning noise or exclude it from stress bundles.

**KPIs (PhaseÃ‚Â 1 targets):**
- `ParseDuration` p95 Ã¢â€°Â¤Ã‚Â 3Ã‚Â s per device; max <Ã‚Â 10Ã‚Â s.
- `DatabaseWriteLatency` p95 Ã¢â€°Â¤Ã‚Â 200Ã‚Â ms.
- `SkippedDuplicate` ratio Ã¢â€°Â¥Ã‚Â 50% on incremental runs.
- Memory bounded during parsing; no provider contention in multiÃ¢â‚¬â€˜site tests.

**Verification:** benchmark corpus, Pester tests, ingestion smoke tests; compare metrics before/after.

**Roadmap alignment:** Milestone **M1 Ã¢â‚¬â€œ MultiÃ¢â‚¬â€˜DB ingestion foundation** (target 2025Ã¢â‚¬â€˜10Ã¢â‚¬â€˜14).

<a id="plan-c-change-tracking-diff-snapshots"></a>
## Plan C Ã¢â‚¬â€ Change Tracking (Diff Snapshots)
**Objective:** Persist perÃ¢â‚¬â€˜run normalized objects and compute diffs to surface configuration drift and feed anomaly rules, stored in Access for PhaseÃ‚Â 1.

**Schema sketch:** `DiffRun`, `DiffObject`, `DiffChange`, `DiffMetadata` (keys: DeviceId + CaptureId + ObjectHash; columns: ChangeType, Before, After, Confidence).
**Implementation track:** parser spike to emit stable hashes; persistence test DB under `Data/Prototypes/`; UI queries for lastÃ‚Â N changes; metrics CSV under `Logs/Research/DiffPrototype/`.

**Success metrics:** Ã¢â€°Â¥Ã‚Â 70% diff usage in pilot sessions; Ã¢Ë†â€™40% timeÃ¢â‚¬â€˜toÃ¢â‚¬â€˜driftÃ¢â‚¬â€˜identification vs. baseline; FP rate <Ã‚Â 10% after tuning.

<a id="plan-d-feature-expansion-guided-troubleshooting"></a>
## Plan D Ã¢â‚¬â€ Feature Expansion & Guided Troubleshooting
**Objective:** Turn parsed facts + diffs into operatorÃ¢â‚¬â€˜ready insights with guided runbooks, while remaining offlineÃ¢â‚¬â€˜first and AccessÃ¢â‚¬â€˜backed.**

**Streams:**
- **Anomaly cards** Ã¢â‚¬â€ ruleÃ¢â‚¬â€˜based engine (JSON config) to surface events/tags (e.g., `AuthFailureCount`, `PortFlapEvents`).
- **Guided troubleshooting** Ã¢â‚¬â€ map patterns to vendorÃ¢â‚¬â€˜aligned runbooks; show next steps and expected outcomes.
- **Diff explorer** Ã¢â‚¬â€ filterable UI for added/removed/changed items; deepÃ¢â‚¬â€˜link to raw log context.
- **Exports & digests** Ã¢â‚¬â€ scheduled daily digests and exportable reports for analysts.

**PreÃ¢â‚¬â€˜reqs:** Plans **B** and **C** (telemetry & diff data).

<a id="plan-e-telemetry-launch-metrics"></a>
## Plan E Ã¢â‚¬â€ Telemetry & Launch Metrics
**Objective:** Instrument usage and reliability metrics to validate adoption and SLO outcomes.**

**PhaseÃ‚Â 1 dictionary:** `ParseDuration`, `RowsWritten`, `SkippedDuplicate`, `DatabaseWriteLatency`, `DiffUsageRate`, `DriftDetectionTime`, plus optional agent metrics (e.g., `AgentTestPassRate`).
**Artifacts:** metrics schema; ingestion to JSONÃ¢â‚¬â€˜lines under `Logs/`; dashboard draft for launch metrics.
**Targets:** as specified in the dictionary (p95 thresholds; ratios).

<a id="plan-f-security-identity-online-mode"></a>
## Plan F Ã¢â‚¬â€ Security, Identity & Online Mode
**Objective:** Apply leastÃ¢â‚¬â€˜privilege handling to logs and databases; choose a pragmatic identity mechanism for acknowledgements that fits offlineÃ¢â‚¬â€˜first constraints.**

**Policies:** redaction before storage; 90Ã¢â‚¬â€˜day retention on sanitized postmortems; Access DB rotation/backups; `.gitignore` hygiene; incident confidentiality.
**Identity options under evaluation:** AD integrated, Azure AD device code, local accounts, external SSO (PhaseÃ‚Â 2+).
**Next actions:** scorecard each option; draft spike for chosen path; tie acknowledgements to Access `Audit` table and telemetry.

<a id="plan-g-release-risk-governance"></a>
## Plan G Ã¢â‚¬â€ Release, Risk & Governance
**Objective:** Ship predictably and manage risk while operating as a small team.**

**Release:** semantic versioning; packaging script; smoke tests (unit, parsing, UI load, version check).
**Risk register:** active risks include telemetry gaps, DB contention, sanitisation lag, overcommitment, alert fatigue, identity uncertainty; review cadence per owner.
**Operating cadence:** Use the quarterly roadmap for milestones (M1Ã¢â‚¬â€œM3), update during weekly planning and Friday retrospectives; convert discovery outcomes into backlog items.

---

## CrossÃ¢â‚¬â€˜cutting dependencies & sequencing
1. **Plan B (Performance/Scale)** underpins Plans C and D; land perf baselines before exposing heavier diff and anomaly features.
2. **Plan E (Telemetry)** must be present before Plan D success metrics are meaningful; instrument as you go.
3. **Plan F (Identity)** is required before acknowledgements are authoritative in Plan A; minimally support internal operator tracking in PhaseÃ‚Â 1.

## Consolidated backlog (PhaseÃ‚Â 1)
- SiteÃ¢â‚¬â€˜scoped DB mutex; connection cache; staging tables; adaptive runspace sizing.
- Streaming parser refactor; remove perÃ¢â‚¬â€˜line AutoFlush; Pester coverage for vendor parsers.
- Diff prototype schema + persistence spike; UI diff queries; metrics CSV logging.
- Telemetry dictionary implementation across parser/UI; draft launch dashboard.
- Routing ERD + health evaluator + UI surfaces; alert pipeline to runbooks.
- Identity option scorecard + spike; wire acknowledgements into Access + telemetry.
- Release packaging script verification; roadmap sync; risk register reviews.

## Appendix Ã¢â‚¬â€ Change log & review
- Last source doc touchpoints were sampled from repository dates embedded in files (e.g., 2025Ã¢â‚¬â€˜09Ã¢â‚¬â€˜30 reviews).
- Keep this dossier versioned alongside `docs/` and update the mapping table when new plan docs are added.
