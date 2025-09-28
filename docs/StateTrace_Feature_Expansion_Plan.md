# StateTrace Feature Expansion Plan

## Context & Goals
StateTrace converts raw infrastructure log bundles into actionable guidance for network operators. The immediate roadmap should:
- Shorten time-to-diagnosis by exposing context already buried in device logs.
- Provide guided remediation that reflects vendor best practices.
- Keep the platform extensible so customers can tailor parsing and reporting to their environments.
- Maintain a focus on log-centric insights; every feature should leverage, augment, or accelerate log-driven understanding.
- Respect the existing ingestion model (.log files only) and operate entirely within PowerShell scripts and Access databases--no compiled components or new data stores.

## Personas & Primary Needs
- **Network Ops On-call:** Rapid anomaly surfacing, diffing between runs, clear remediation orders.
- **Support Engineering:** Shareable incident snapshots for customer communications, auditability back to raw logs.
- **Platform SRE/Parser Owners:** Observability into ingestion health, safe rollout of new parsing logic, tooling for custom rules.
- **Customer Success / Reporting Analysts:** Scheduled digests, trend lines, and exportable insights.

## Feature Themes & Detailed Proposals

### 1. Richer Log Intelligence
**Objectives**
- Highlight meaningful changes and emerging risks directly from successive log uploads.

**Key Capabilities**
- Visual diff explorer with side-by-side configuration/state comparison across the last N captures, including filters (interface, VLAN, auth, STP state).
- Automated insight cards summarising detected anomalies (port flapping > threshold, auth failures, missing templates, unexpected shutdowns).
- Historical timeline charts (per device, per site) of interface status counts, alert types, auth errors derived from parsed logs.
- Correlate log statements into incident clusters (e.g., power failure sequences, STP topology changes) using pattern libraries.

**Technical Requirements**
- Persist per-run snapshots of normalized objects (interfaces, templates, alerts) in Access with diff metadata (added/removed/changed fields).
- Extend parser to emit event counters and tags (e.g., `AuthFailureCount`, `PortFlapEvents`) per device.
- Introduce PowerShell-driven anomaly rules engine (rule-based to start, future ML-ready via scripts) with configuration stored in JSON.
- Add time-series storage in Access tables for key metrics to support charting without reparsing logs and stay within current storage options.

**Success Metrics**
- >=70% of primary incidents show diff/insight usage in telemetry (event tracking).
- Mean time to identify configuration drift reduced by 40% in beta cohorts.
- False positive rate on anomaly cards <10% after first tuning cycle.

### 2. Guided Troubleshooting
**Objectives**
- Provide just-in-time remediation help when patterns are detected in logs.

**Key Capabilities**
- Pattern-to-runbook mapping: when a known `.log` signature appears, show relevant runbook snippet, required checks, and expected outcomes.
- “Next command suggestions” referencing gaps in log coverage (e.g., missing `show interface transceiver` when optics alerts fire).
- Inline remediation checklists with completion tracking (e.g., confirm redundant link up, verify authentication server status).
- Escalation cues (who to call, SLA impact) tied to severity of detected issues.

**Technical Requirements**
- Create knowledge base mapping signature IDs to markdown runbook content stored in `docs/runbooks/*.md`.
- UI component for checklist modal with persistence (per device/incident) in local DB or config store.
- Extend parser metadata to flag missing command outputs and cross-reference the Templates/ShowCommands inventory.
- Provide optional integration hooks for external ticketing (PagerDuty/ServiceNow) when escalation thresholds met.

**Success Metrics**
- Operators complete guided checklists in >=60% of major incident sessions.
- Reduction in duplicate escalations due to missing runbook references (tracked via ops feedback).

### 3. Custom Analytics & Extensibility
**Objectives**
- Empower advanced users to define bespoke parsing logic and computed insights without core code changes.

**Key Capabilities**
- UI-driven custom parser rule builder supporting regex, delimiter, and JSONPath extraction with live preview on sample `.log` files.
- Derived metric definitions (e.g., “count interfaces with err-disabled state grouped by building”) saved as reusable widgets.
- Export/import packs (JSON/PowerShell module) so teams can share rule sets across environments.
- Scriptable automation surfaces (PowerShell cmdlets plus optional PowerShell-hosted HTTP listener) exposing parsed datasets, diff results, and anomalies.

**Technical Requirements**
- Sandbox execution context for custom rules to prevent unsafe code (e.g., hosted runspace with constrained language mode).
- Rule metadata persistence (Access tables or JSON files) with versioning and rollback.
- Validation harness running rules against sample logs during creation to catch performance or parsing issues.
- Authentication/authorisation layer for REST API (reuse existing RBAC plan once defined).

**Success Metrics**
- >=10 active custom rules per pilot team within first month.
- Less than 5% of custom rule executions error due to performance/timeouts.
- External automation accounts for >=20% of insight exports post-launch.

### 4. Collaboration & Reporting
**Objectives**
- Make log-derived insights shareable and auditable for cross-team collaboration.

**Key Capabilities**
- Incident packet generator (PDF/HTML/Markdown) summarising anomaly cards, diff highlights, impacted hosts, runbook steps, and links back to raw logs.
- Acknowledgement/ownership workflow for high-severity alerts with activity log (who acknowledged, when, follow-up notes).
- Scheduled digest emails/slack posts summarising new anomalies, diff summaries, and outstanding acknowledgements.
- Commenting capability on insight cards or devices with mention notifications.

**Technical Requirements**
- Extend storage schema for incident packets, acknowledgements, and comments (including user identity fields).
- Email/webhook integration implemented via PowerShell modules/scripts configurable per deployment.
- Template engine for packet/digest rendering built with PowerShell templating (e.g., here-strings, Markdown helpers).
- Audit log capturing acknowledgement changes for compliance.

**Success Metrics**
- 80% of critical anomalies acknowledged within target SLA after workflow launch.
- Adoption of scheduled digests by =3 stakeholder groups within quarter.
- Positive satisfaction scores from support teams on packet usefulness (survey baseline).

### 5. Operational Hygiene & Observability
**Objectives**
- Ensure the log ingestion pipeline and supporting caches remain healthy, with issues surfaced before they cause data gaps.

**Key Capabilities**
- Ingestion health dashboard (missing logs by site, stale extracts, parse failures, queue depth, disk usage).
- Proactive warnings when log formats drift (e.g., new firmware altering output) with auto-capture of unknown sections for review.
- One-click access from any insight to the underlying raw log segment.
- Parser performance telemetry (per device parse duration, bottleneck detection) with thresholds for alerting.

**Technical Requirements**
- Instrument parser pipeline to emit structured telemetry (event IDs, durations, file counts) stored locally in Access and optionally forwarded via PowerShell to centralized monitoring.
- Implement schema validation/diffing for `.log` formats with fallback capture (store unknown commands separately).
- UI hooks linking normalized data entries back to raw log offsets (store byte ranges per parsed element).
- Add maintenance mode toggles when ingestion intentionally paused (e.g., planned maintenance) to suppress false alarms.

**Success Metrics**
- Reduction in “missing log” incidents by 50% quarter-over-quarter.
- Parser P95 duration baseline established and improved by 20% after optimizations informed by telemetry.
- Operators report =90% confidence in ingestion health (survey/feedback loop).

## Phased Roadmap (Draft)

### Phase 0: Discovery & Design (Weeks 1-3)
- Conduct stakeholder interviews/workshops covering diff expectations, anomaly thresholds, collaboration needs (Owner: Product).
- Inventory current log types, parsing coverage, and data quality issues (Owner: Parser team).
- Draft data model updates for diff snapshots, anomaly events, custom rules, acknowledgements (Owner: Platform). Create ERDs.
- UX produce wireframes/prototypes for diff view, insight cards, checklist modals, incident packets (Owner: UX).
- Define telemetry events required to measure success metrics (Owner: Analytics).

**Exit Criteria:** Stakeholder-aligned PRD, approved data model, wireframes signed off, measurement plan documented.

### Phase 1: Foundational Enhancements (Weeks 4-7)
- Implement snapshot storage & diff engine (persist normalized device/interface states with hash/versioning).
- Extend parser to emit anomaly inputs and record raw-log offsets; add performance telemetry instrumentation.
- Build ingestion health monitoring backend + service to aggregate telemetry and raise warnings.
- Architect knowledge base + runbook mapping storage; seed with top 20 known issues.
- Establish custom rule execution sandbox architecture (without UI yet).

**Deliverables:** Diff API endpoints, anomaly data schema, telemetry dashboards MVP, runbook storage service, sandbox prototype.

### Phase 2: Insight Delivery (Weeks 8-11)
- Implement diff explorer UI (side-by-side view, filters, change summary chips).
- Launch anomaly insight card UI with severity indicators and knowledge base linkage.
- Add timeline charts using stored metrics; ensure performant queries.
- Build checklist UI and persistence for guided troubleshooting; integrate runbook content.
- Release ingestion health dashboard in UI with alerting hooks.

**Deliverables:** Diff UI, insight card component, timeline chart widgets, troubleshooting checklist experience, health dashboard.

### Phase 3: Collaboration & Extensibility (Weeks 12-15)
- Deliver incident packet generator (configurable template) and acknowledgement workflow with activity log.
- Release scheduled digest service (email/webhook) configurable per persona.
- Ship custom rule builder UI + validation harness + rule deployment pipeline.
- Expose REST/PowerShell endpoints for diff/anomaly data with authentication.

**Deliverables:** Packet export feature, acknowledgement workflow GA, digest scheduler, custom rule editor, API documentation.

### Phase 4: Hardening & Rollout (Weeks 16-18)
- Beta program with select operators; gather telemetry and qualitative feedback.
- Tune anomaly thresholds, checklist content, and runbooks based on real incidents.
- Performance profiling and optimization for diff engine and rule execution.
- Documentation/training: updated user guide, runbook authoring instructions, administrator setup for digests/APIs.
- GA launch with staged rollout plan (feature flags, fallback paths).

**Deliverables:** Beta report, tuned heuristics, performance benchmark report, documentation set, GA launch checklist.

## Dependencies & Considerations
- **Schema migrations:** Plan incremental database upgrades, ensure backward compatibility, provide migration scripts.
- **Identity & RBAC:** Collaboration features and custom rules require authenticated users; align with forthcoming RBAC/identity initiative.
- **Performance impact:** Diffing and anomaly computations may increase ingestion time; incorporate profiling, batching, and possibly incremental parsing.
- **Runbook curation:** Need SMEs to author and maintain runbook snippets--establish ownership process.
- **Localization:** If runbooks/digests need localization, design templates accordingly.
- **Telemetry Privacy:** Ensure scheduled digests and incident packets respect data-handling policies (mask sensitive values where required).

## Risks & Mitigations
- **Alert fatigue from noisy anomaly rules:** Start with conservative thresholds, provide per-rule toggle/feedback mechanism.
- **Rule sandbox bypass attempts:** Enforce constrained language mode, static analysis of rules, and execution quotas.
- **Packet exports leaking sensitive data:** Introduce PowerShell-managed redaction rules and review workflows; allow admins to disable export per tenant.
- **Custom rules degrading performance:** Require preview benchmarking, track rule execution time, auto-disable rules exceeding limits.
- **Operator adoption lag:** Provide training, in-product tours, and quick-start templates; capture analytics to spot unused features.

## Resource Needs
- Parser engineering (2 FTE) for diff/anomaly enhancements.
- UI/UX (1 FTE designer, 2 FTE frontend engineers) for new views and workflows.
- Platform/backend (2 FTE) for telemetry, custom rules sandbox, APIs.
- Technical writer/ops SME for runbook curation (~0.5 FTE each during phases 2-4).

## Immediate Next Steps (0-4 Weeks)
1. Schedule cross-functional ideation and scoping workshop (Product, Parser, Ops, Support).
2. Collect top incident postmortems to inform runbook library and anomaly thresholds.
3. Prototype diff data model on sampled logs to validate storage footprint and performance.
4. Define user identity approach for acknowledgement workflow (coordinate with security/IT).
5. Draft success metric dashboards for launch (e.g., diff usage, anomaly accuracy) ready for instrumentation in Phase 1.

## Open Questions
- Do we require per-tenant customization boundaries for custom rules/export templates? (impacts storage design)
- Should diff history retain indefinite versions or prune after N runs per device? (storage policy)
- What external integrations (PagerDuty, Slack, ServiceNow) must be first-class in digests/escalations?
- How will we manage conflicting custom rules across teams (priority system, namespacing)?
- Are there compliance constraints on email digests containing configuration data?









