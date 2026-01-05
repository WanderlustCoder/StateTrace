# StateTrace Plan Index

<!-- LANDMARK: ST-E-001 telemetry gates link -->
Telemetry gates: [docs/telemetry/Automation_Gates.md](../telemetry/Automation_Gates.md).

The active StateTrace plans live in discrete files so automation agents can reference a small, structured surface instead of parsing the historical log inside `docs/StateTrace_Consolidated_Plans.md`. Treat the per-plan pages as the **source of truth for objectives, owners, active work, and telemetry gates**; append narrative updates or long-form investigation notes to the historical log only after you have updated the plan page.

| Plan | Focus | Primary owner(s) | Key telemetry / automation hooks | Plan file |
|------|-------|------------------|-------------------------------|-----------|
| A | Routing reliability & dispatcher health | Ingestion / Routing | `InterfacePortQueueMetrics`, `InterfaceSyncTiming`, telemetry bundles (`Tools\Test-TelemetryBundleReadiness.ps1`) | `docs/plans/PlanA_RoutingReliability.md` |
| B | Performance & ingestion scale | Ingestion / Parser Worker | `ParseDuration`, `DatabaseWriteLatency`, `InterfaceSiteCacheMetrics`, diff hotspot CSVs, shared-cache diagnostics | `docs/plans/PlanB_Performance.md` |
| C | Change tracking & diff model | UI / Data | `DiffUsageRate`, diff snapshot health | `docs/plans/PlanC_ChangeTracking.md` |
| D | Feature expansion & guided troubleshooting | UI / Guided Ops | Feature telemetry, SPAN helpers | `docs/plans/PlanD_FeatureExpansion.md` |
| E | Telemetry, launch metrics, and rollups | Telemetry / Ops | `Phase1` metrics dictionary, rollup CSVs, scheduled daily rollup task (`Tools\Schedule-DailyRollupTask.ps1`, telemetry bundles / readiness) | `docs/plans/PlanE_Telemetry.md` |
| F | Security, identity, & online mode | Security / Platform | Redaction tooling, RBAC switches, NetOps logs (`Tools\Test-NetOpsEvidence.ps1 -RequireEvidence -RequireReason`, `Tools\Reset-OnlineModeFlags.ps1 -Reason "<task>"`) | `docs/plans/PlanF_SecurityIdentity.md` |
| G | Release & governance | Release / PMO | Release checklist completion, warm-run verification, telemetry bundle readiness (`Tools\Invoke-StateTraceVerification.ps1 -VerifyTelemetryBundleReadiness`, `Tools\Test-TelemetryBundleReadiness.ps1`) | `docs/plans/PlanG_ReleaseGovernance.md` |
| H | User experience & adoption | UI / Docs | Onboarding checklist, UI freshness banner, `UserAction` telemetry surfaced in rollups | `docs/plans/PlanH_UserExperience.md` |
| I | Harness & gating stability | Ingestion / Automation | Queue/diversity guard health, shared-cache diagnostics, bundle readiness on PowerShell 5.1 | `docs/plans/PlanI_HarnessStability.md` |
| J | Test & fixture reliability | QA / Automation | Repository-tracked fixtures, clean telemetry inputs, CI harness smoke | `docs/plans/PlanJ_TestFixtureReliability.md` |
| K | Developer experience & CI readiness | Platform / Automation | Offline-friendly bootstrap, smoke harness on PS 5.1/7, CI artifacts bundled for Plans E/G | `docs/plans/PlanK_DeveloperExperience.md` |
| L | Module decomposition & maintainability | Architecture / UI / Ingestion | Split monolithic modules into testable layers without regressing performance | `docs/plans/PlanL_ModuleDecomposition.md` |
| M | Data quality & telemetry hygiene | Telemetry / Security | Telemetry linting, bundle integrity, redaction enforcement | `docs/plans/PlanM_DataQuality.md` |
| N | Documentation & runbook automation | PMO / Automation | Plan/task board sync, session log stubs, ADR/runbook linkage | `docs/plans/PlanN_DocumentationAutomation.md` |
| O | Accessibility & UI responsiveness | UI | Accessibility checks, layout adaptability, UI latency telemetry | `docs/plans/PlanO_AccessibilityResponsiveness.md` |
| P | Packaging & deployment reliability | PMO / Platform | Package integrity, install/uninstall smokes, version stamping | `docs/plans/PlanP_PackagingDeployment.md` |
| Q | Shared cache strategy & snapshot governance | Ingestion | Snapshot rotation/coverage policy, import compatibility guards | `docs/plans/PlanQ_SharedCacheStrategy.md` |
| R | Incident response & rollback readiness | PMO / Security | Drills, rollback bundles, NetOps evidence enforcement | `docs/plans/PlanR_IncidentResponse.md` |
| S | Deprecation & unused code cleanup | Architecture / PMO | Unused export inventory, feature flag audit, script/runbook pruning | `docs/plans/PlanS_DeprecationCleanup.md` |
| T | Cable & port documentation | UI / Ops | Cable tracking, patch panel mapping, label generation | `docs/plans/PlanT_CablePortDocumentation.md` |
| U | Configuration templates & validation | Tools / UI | Template engine, config validation, compliance checking | `docs/plans/PlanU_ConfigurationTemplates.md` |
| V | IP address & VLAN planning | Data / UI | VLAN registry, subnet planning, conflict detection | `docs/plans/PlanV_IPAddressVLANPlanning.md` |
| W | Network topology visualization | UI | Auto-discovery, L2/L3 views, diagram export | `docs/plans/PlanW_NetworkTopologyVisualization.md` |
| X | Inventory & asset tracking | Data / UI | Asset registry, warranty tracking, firmware management | `docs/plans/PlanX_InventoryAssetTracking.md` |
| Y | Network calculator tools | Tools / UI | Subnet calculator, bandwidth calculator, protocol timers | `docs/plans/PlanY_NetworkCalculatorTools.md` |
| Z | Change management & maintenance windows | Tools / UI | Change requests, maintenance calendar, pre/post verification | `docs/plans/PlanZ_ChangeManagement.md` |
| AA | Network documentation generator | Tools / UI | As-built docs, templates, multi-format export | `docs/plans/PlanAA_DocumentationGenerator.md` |
| AB | Troubleshooting decision trees | Tools / UI | Guided troubleshooting, pattern library, outcome tracking | `docs/plans/PlanAB_TroubleshootingDecisionTrees.md` |
| AC | Capacity planning & forecasting | Tools / UI | Utilization tracking, growth forecasting, budget planning | `docs/plans/PlanAC_CapacityPlanningForecasting.md` |
| AD | Cross-vendor command reference | Tools / UI | Command translation, quick reference, config snippets | `docs/plans/PlanAD_CrossVendorCommandReference.md` |
| AE | Log analysis & pattern detection | Tools / UI | Log parsing, pattern detection, event correlation | `docs/plans/PlanAE_LogAnalysisPatternDetection.md` |

## Status snapshot (2026-01)
- **Plan A** - **Complete (5/6 Done, 1 Deferred)**. Routing instrumentation, dispatcher harness, verification scripts, and evidence capture implemented. ST-A-019 (real-device validation) deferred pending device access.
- **Plan B** - **Complete**. Shared-cache diagnostics, warm-run telemetry, diff hotspot automation, and telemetry bundle packaging delivered.
- **Plan C** - **Complete**. Diff prototype validation, Compare view telemetry instrumentation, and drift analyzer output implemented.
- **Plan D** - **Complete**. Incremental-loading telemetry, SPAN telemetry wiring, guided troubleshooting runbooks, and UI smoke automation delivered.
- **Plan E** - **Complete**. Daily rollup scheduling, Phase 1 dictionary refresh, telemetry gate enforcement, and bundle production implemented.
- **Plan F** - **Complete (5/6 Done, 1 Blocked)**. NetOps logging, sanitizer automation, evidence templates, RBAC rollout playbook delivered. ST-F-006 (sanitized incident intake) blocked pending real incident data.
- **Plan G** - **Complete**. Release checklist, shared-cache snapshot policy, verification summaries, and bundle verification automation implemented.
- **Plan H** - **Complete**. Onboarding checklist, in-app freshness indicators, and UserAction telemetry routing to rollups delivered.
- **Plan I** - **Complete**. Queue/diversity guards, guarded cold+warm runs, and shared-cache diagnostics on PowerShell 5.1 implemented.
- **Plan J** - **Complete**. Tracked fixture seeds, preflight checks, and polluted-input guards delivered.
- **Plan K** - **Complete**. Offline-friendly bootstrap, CI harness on PS 5.1/7, and bundled outputs implemented.
- **Plan L** - **Complete (5/5 Done)**. Module decomposition delivered: DeviceRepository.Cache, DeviceRepository.Access, ParserPersistence.Core, ParserPersistence.Diff, MainWindow.Services. All 56 Decomposition tests pass.
- **Plan M** - **Complete**. Telemetry linting, bundle integrity checks, and redaction preflights implemented.
- **Plan N** - **Complete (4/4 Done)**. Sync-TaskBoard, New-SessionLogStub, New-ArchitectureDecisionRecord, and Test-PlanTaskBoardDrift delivered.
- **Plan O** - **Complete (4/4 Done)**. Accessibility checklist, responsive layout validation, UI responsiveness telemetry, and code-behind reduction delivered.
- **Plan P** - **Complete**. Manifest/hash verification, install/uninstall smokes, and version stamping implemented.
- **Plan Q** - **Complete**. Snapshot rotation/coverage policies, compatibility guards, and fallback seeds delivered.
- **Plan R** - **Complete**. Drill cadence, rollback bundles, evidence enforcement, and post-incident verification implemented.
- **Plan S** - **Complete**. Unused export inventory, feature flag audit, and script/runbook pruning delivered.
- **Plan T** - **Planned**. Cable & port documentation for tracking physical connections, patch panels, and generating cable labels.
- **Plan U** - **Planned**. Configuration template engine with validation, compliance checking, and config generation.
- **Plan V** - **Planned**. Lightweight IPAM with VLAN registry, subnet planning, and conflict detection.
- **Plan W** - **Planned**. Network topology visualization with auto-discovery and diagram export.
- **Plan X** - **Planned**. Inventory and asset tracking with warranty monitoring and firmware management.
- **Plan Y** - **Planned**. Network calculator suite with subnet, VLAN, bandwidth, and protocol timer tools.
- **Plan Z** - **Planned**. Change management with maintenance window scheduling, pre/post verification, and rollback tracking.
- **Plan AA** - **Planned**. Network documentation generator with as-built templates and multi-format export.
- **Plan AB** - **Planned**. Troubleshooting decision trees with guided workflows and outcome tracking.
- **Plan AC** - **Planned**. Capacity planning with utilization tracking, growth forecasting, and budget projections.
- **Plan AD** - **In Progress (5/6 Done)**. Cross-vendor command reference with translation and configuration snippets. Core module, UI, and tests delivered. Learning mode pending.
- **Plan AE** - **Planned**. Log analysis with pattern detection, event correlation, and anomaly detection.

## How to use the plans
1. **Before editing code** - open the relevant plan file, confirm the objective still matches your intent, and add your upcoming work to the "Active work" table (include the task-board or Codex backlog ID).
2. **While working** - capture telemetry and command output under the "Automation hooks" section of the same plan file so future agents can reproduce your steps.
3. **After finishing** - move the row to "Recently delivered" (if provided), link the doc/test diffs, and mirror the summary to the task board (`docs/StateTrace_TaskBoard.md` / `docs/taskboard/TaskBoard.csv`).
4. **When adding a new initiative** - clone one of the plan templates in this folder, update the index above, and add a pointer at the top of `docs/StateTrace_Consolidated_Plans.md`.

## Cross-references & telemetry hygiene
- Pair this index with `docs/CODEX_PLAN_AUTOMATION_MATRIX.md` and the per-plan "Automation hooks" tables so every task cites the exact scripts/tests to run.
- Always log telemetry artifacts (e.g., `Logs/IngestionMetrics/<date>.json`, rollup CSVs, shared-cache diagnostics, NetOps JSON) and mention the paths in plan/task-board updates per `docs/CODEX_DOC_SYNC_PLAYBOOK.md`.
- When a plan references sanitized incidents, link the matching entry in `docs/StateTrace_IncidentPostmortem_Intake.md` and the relevant session log under `docs/agents/sessions/`.
- Historical narrative (per-minute notes, rich telemetry dumps) should continue to live in `docs/StateTrace_Consolidated_Plans.md`. Link back from each plan page so readers can dive deeper when necessary.

