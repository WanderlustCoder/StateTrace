# StateTrace â€” Consolidated Planning Dossier
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
- **Routing Reliability** becomes a single crossâ€‘cutting program (data model, discovery, health scoring, alerting, and rollout) driven by a _Routing Working Set_ of docs merged below.
- **Performance & Ingestion Scale** unifies perf hotâ€‘spot fixes, multiâ€‘DB concurrency, and code deduplication under one engineering plan with measurable p95 targets.
- **Change Tracking (Diff)** provides Accessâ€‘backed perâ€‘run snapshots and a diff UI, treated as a feature enabler for drift detection and guided troubleshooting.
- **Feature Expansion** sequences UX surface area (anomaly cards, guided runbooks) behind the telemetry and diff groundwork.
- **Telemetry & Launch Metrics** defines a PhaseÂ 1 dictionary and dashboard to verify adoption and SLA outcomes.
- **Security, Identity & Online Mode** aligns ADRâ€‘0004, security hygiene, and acknowledgement/identity decisions into a practical, offlineâ€‘first implementation plan.
- **Release & Governance** ties the Risk Register, release guide, and quarterly roadmap to an operating cadence.

---

## Mapping: source â†’ consolidated plan
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
## Plan A â€” Routing Reliability
**Objective:** Detect and explain primary route outages within 60Â seconds with actionable remediation and historical trendability, while keeping Access as the PhaseÂ 1 store.

**Scope (PhaseÂ 1):**
- Canonical schemas: `RouteRecord`, `RouteHealthSnapshot`, `OutageEvent`, `RemediationTask`, `NotificationPreference`.
- Ingestion pipelines for SNMP/probes/logs; correlation by `RouteRecord.Id`.
- Health scoring w/ debouncing; state transitions (healthy â†’ degraded â†’ down â†’ recovered).
- Operator UI: route list, detail, history, owner metadata, links to runbooks; alerting hooks.
- Retention: 30â€‘day snapshots (highâ€‘res), 12â€‘month aggregates (trend).

**Out of scope (PhaseÂ 1):** new external services, replacing Access, multiâ€‘tenant auth flows.

**Deliverables:**
- ERD + sequence notes (stored under `Resources/architecture/routing/`).
- Access DDL for the five tables + indices (Hostname/RouteId/Status/Timestamp).
- PowerShell health evaluator service (script) + unit tests; telemetry for state transitions.
- Dashboards: missing/stale/conflicting signal monitors.

**Acceptance criteria:**
- p95 detection latency â‰¤Â 60Â s for primary route failures in testbed.
- Conflicting signal rate <Â 2% daily; all alerts link to runbooks.
- Route ownership visible in UI and via API; audit trail for acknowledgements.

**Risks & mitigations:**
- Signal sparsity â‡’ add synthetic probes; flag data gaps in telemetry.
- Alert fatigue â‡’ tune thresholds; staged rollout; feature flags.
- Soloâ€‘operator bandwidth â‡’ timeâ€‘box discovery (see resource plan) and sequence work via roadmap.

**Roadmap alignment:** See `StateTrace_Quarterly_Roadmap.md` milestone **M2 â€“ Routing discovery baseline** (target 2025â€‘11â€‘15) and subsequent backend/UI work. 

<a id="plan-b-performance-ingestion-scale"></a>
## Plan B â€” Performance & Ingestion Scale
**Objective:** Improve endâ€‘toâ€‘end ingestion throughput without functional changes, supporting growth in perâ€‘site Access databases and concurrent parsing.

**Workstreams:**
1. **Warmâ€‘up & streaming parser** â€” module preloading caches; streaming line pipeline; memory bound below a fixed ceiling.
2. **Multiâ€‘DB concurrency** â€” siteâ€‘scoped mutexes; connection reuse; staging tables; adaptive runspace pool surfaced in `StateTraceSettings.json`.
3. **Persistence tuning** â€” parameterized `ADODB.Command`, batched writes, reduced autoâ€‘flush, writeâ€‘latency telemetry.
4. **Deduplication** â€” shared vendorâ€‘agnostic parsers; common UI composition helpers; central filter service; simpler `ParserWorker` orchestration.


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


**2025-10-03 stress-test snapshot (bulk staging re-run, autoscale defaults):**
- Run: `Tools/Invoke-StateTracePipeline.ps1 -VerboseParsing -ResetExtractedLogs`; Pester suite passed; processed 37-device BOYO/WLLS corpus.
- Auto-scale profile resolved ThreadCeiling=8, MaxWorkersPerSite=4, MaxActiveSites=0, JobsPerThread=2.
- ParseDuration p95 ~4.83 s (target <=3 s); max 7.34 s on WLLS-A05-AS-55; average 2.43 s across 37 hosts.
- DatabaseWriteLatency p95 ~4.08 s (target <=200 ms); max 4.43 s on WLLS-A05-AS-55 after 91-row batch; staging succeeded but Access commit remained slow.
- Second pass emitted Duplicate=true ParseDuration events for 35 devices with zero writes; only WLLS-A05-AS-55 and WLLS-A07-AS-07 retried with real commits; suppression needed to avoid redundant duplicate sweep.

**Follow-ups status (as of 2025-10-03):**
- Open: Trial reduced ceilings (for example, MaxWorkersPerSite=2 or MaxActiveSites=2) to evaluate latency impact versus throughput; WLLS commits still >4 s in latest run.
- Open: Investigate Access commit latency (DatabaseWriteLatency p95 ~4.08 s) despite staging; test smaller batches or per-site serialization for WLLS hosts.
- Done: Extended telemetry now emits ParseDuration and ConcurrencyProfileResolved events in pipeline runs.
- Done: ParserWorker filters _unknown.log slices before scheduling parse jobs.
- Done: Profiled Access bulk insert timing; InterfaceBulkInsertInternal emits InterfaceBulkInsertTiming telemetry for staging and commit phases.
- Done: Added a 32-bit PowerShell fallback when ADOX cannot create new Access databases on 64-bit hosts.
- Open: Suppress duplicate-only reruns triggered immediately after -ResetExtractedLogs (current telemetry marks Duplicate=true but still logs 35 ParseDuration entries with zero writes).

**KPIs (PhaseÂ 1 targets):**
- `ParseDuration` p95 â‰¤Â 3Â s per device; max <Â 10Â s.
- `DatabaseWriteLatency` p95 â‰¤Â 200Â ms.
- `SkippedDuplicate` ratio â‰¥Â 50% on incremental runs.
- Memory bounded during parsing; no provider contention in multiâ€‘site tests.

**Verification:** benchmark corpus, Pester tests, ingestion smoke tests; compare metrics before/after.

**Roadmap alignment:** Milestone **M1 â€“ Multiâ€‘DB ingestion foundation** (target 2025â€‘10â€‘14).

<a id="plan-c-change-tracking-diff-snapshots"></a>
## Plan C â€” Change Tracking (Diff Snapshots)
**Objective:** Persist perâ€‘run normalized objects and compute diffs to surface configuration drift and feed anomaly rules, stored in Access for PhaseÂ 1.

**Schema sketch:** `DiffRun`, `DiffObject`, `DiffChange`, `DiffMetadata` (keys: DeviceId + CaptureId + ObjectHash; columns: ChangeType, Before, After, Confidence).
**Implementation track:** parser spike to emit stable hashes; persistence test DB under `Data/Prototypes/`; UI queries for lastÂ N changes; metrics CSV under `Logs/Research/DiffPrototype/`.

**Success metrics:** â‰¥Â 70% diff usage in pilot sessions; âˆ’40% timeâ€‘toâ€‘driftâ€‘identification vs. baseline; FP rate <Â 10% after tuning.

<a id="plan-d-feature-expansion-guided-troubleshooting"></a>
## Plan D â€” Feature Expansion & Guided Troubleshooting
**Objective:** Turn parsed facts + diffs into operatorâ€‘ready insights with guided runbooks, while remaining offlineâ€‘first and Accessâ€‘backed.**

**Streams:**
- **Anomaly cards** â€” ruleâ€‘based engine (JSON config) to surface events/tags (e.g., `AuthFailureCount`, `PortFlapEvents`).
- **Guided troubleshooting** â€” map patterns to vendorâ€‘aligned runbooks; show next steps and expected outcomes.
- **Diff explorer** â€” filterable UI for added/removed/changed items; deepâ€‘link to raw log context.
- **Exports & digests** â€” scheduled daily digests and exportable reports for analysts.

**Preâ€‘reqs:** Plans **B** and **C** (telemetry & diff data).

<a id="plan-e-telemetry-launch-metrics"></a>
## Plan E â€” Telemetry & Launch Metrics
**Objective:** Instrument usage and reliability metrics to validate adoption and SLO outcomes.**

**PhaseÂ 1 dictionary:** `ParseDuration`, `RowsWritten`, `SkippedDuplicate`, `DatabaseWriteLatency`, `DiffUsageRate`, `DriftDetectionTime`, plus optional agent metrics (e.g., `AgentTestPassRate`).
**Artifacts:** metrics schema; ingestion to JSONâ€‘lines under `Logs/`; dashboard draft for launch metrics.
**Targets:** as specified in the dictionary (p95 thresholds; ratios).

<a id="plan-f-security-identity-online-mode"></a>
## Plan F â€” Security, Identity & Online Mode
**Objective:** Apply leastâ€‘privilege handling to logs and databases; choose a pragmatic identity mechanism for acknowledgements that fits offlineâ€‘first constraints.**

**Policies:** redaction before storage; 90â€‘day retention on sanitized postmortems; Access DB rotation/backups; `.gitignore` hygiene; incident confidentiality.
**Identity options under evaluation:** AD integrated, Azure AD device code, local accounts, external SSO (PhaseÂ 2+).
**Next actions:** scorecard each option; draft spike for chosen path; tie acknowledgements to Access `Audit` table and telemetry.

<a id="plan-g-release-risk-governance"></a>
## Plan G â€” Release, Risk & Governance
**Objective:** Ship predictably and manage risk while operating as a small team.**

**Release:** semantic versioning; packaging script; smoke tests (unit, parsing, UI load, version check).
**Risk register:** active risks include telemetry gaps, DB contention, sanitisation lag, overcommitment, alert fatigue, identity uncertainty; review cadence per owner.
**Operating cadence:** Use the quarterly roadmap for milestones (M1â€“M3), update during weekly planning and Friday retrospectives; convert discovery outcomes into backlog items.

---

## Crossâ€‘cutting dependencies & sequencing
1. **Plan B (Performance/Scale)** underpins Plans C and D; land perf baselines before exposing heavier diff and anomaly features.
2. **Plan E (Telemetry)** must be present before Plan D success metrics are meaningful; instrument as you go.
3. **Plan F (Identity)** is required before acknowledgements are authoritative in Plan A; minimally support internal operator tracking in PhaseÂ 1.

## Consolidated backlog (PhaseÂ 1)
- Siteâ€‘scoped DB mutex; connection cache; staging tables; adaptive runspace sizing.
- Streaming parser refactor; remove perâ€‘line AutoFlush; Pester coverage for vendor parsers.
- Diff prototype schema + persistence spike; UI diff queries; metrics CSV logging.
- Telemetry dictionary implementation across parser/UI; draft launch dashboard.
- Routing ERD + health evaluator + UI surfaces; alert pipeline to runbooks.
- Identity option scorecard + spike; wire acknowledgements into Access + telemetry.
- Release packaging script verification; roadmap sync; risk register reviews.

## Appendix â€” Change log & review
- Last source doc touchpoints were sampled from repository dates embedded in files (e.g., 2025â€‘09â€‘30 reviews).
- Keep this dossier versioned alongside `docs/` and update the mapping table when new plan docs are added.
