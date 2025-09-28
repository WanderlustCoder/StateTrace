# StateTrace Routing Reliability Plan

## Overview
Primary routing paths have become critical to customer trust. When a primary route fails today, analysts have limited visibility into what broke, what mitigation exists, and who owns remediation. This plan delivers a cohesive routing observability and guidance experience spanning data collection, backend services, diagnostics UI, alerting, and rollout.

## Success Criteria
- Operators can identify any primary route outage within 60 seconds of occurrence, including clear root-cause indicators and next steps.
- Route metadata (owners, identifiers, dependencies, maintenance status) is discoverable via API and surfaced in the UI.
- Alerts contain actionable remediation guidance and link to authoritative runbooks.
- Historical tracking enables trend analysis of route stability and incident response effectiveness.

## Personas & Stakeholders
- **Network Ops On-call:** Needs rapid detection, triage guidance, and escalation controls.
- **Support Engineers:** Requires visibility into customer-facing impact and alternate paths.
- **Platform SRE:** Owns automated checks, telemetry quality, and health scoring models.
- **Product & Customer Success:** Consume historical insights for roadmap prioritisation and customer updates.

## Phase 0 – Discovery & Alignment
1. Workshop with stakeholders to define "primary" vs "secondary" routes, failover expectations, and acceptable detection latency.
2. Inventory routing components: configuration stores, service maps, and existing runbooks.
3. Audit current monitoring hooks (synthetic probes, SNMP, heartbeat jobs) and document gaps.
4. Catalogue escalation channels, tooling integrations (PagerDuty, Slack), and compliance requirements for incident records.

## Phase 1 – Data & Telemetry Strategy
1. Define canonical `RouteRecord` schema (ID, name, environment, primary flag, dependencies, owner, contact, maintenance windows).
2. Establish `RouteHealthSnapshot` schema capturing status enum, signal sources, confidence score, last healthy timestamp, and failure taxonomy.
3. Map ingestion pipeline for each signal type: polling cadence, transport (HTTP, SNMP, message bus), transformation, and correlation by route ID.
4. Design retention strategy: 30-day high-resolution snapshots, 12-month aggregated statistics for trend analysis.
5. Draft telemetry quality dashboards (missing signals, stale data, conflicting statuses) with alert thresholds.

## Phase 2 – Backend Enhancements
1. **Data model & persistence**
   - Introduce tables/collections for routes, health snapshots, outage events, remediation tasks, and notification preferences.
   - Add migration scripts and seed jobs to backfill existing routes with owner metadata.
2. **Health evaluation service**
   - Build service that consolidates signals, runs scoring logic, and emits state transitions (healthy -> degraded -> down -> recovered).
   - Implement debouncing to suppress flapping alerts and configurable grace periods per route class.
3. **Failover tracking**
   - Detect automatic failover activations, log associated secondary routes, and mark when manual intervention is required.
   - Persist remediation checklists run during incident for auditability.
4. **APIs & contracts**
   - REST/GraphQL endpoints for route directory, current status, outage timeline, recommended checks, and related assets.
   - Webhook publisher for state change events consumed by alerting/incident systems.
5. **Access control**
   - Enforce RBAC for sensitive routing data (e.g., customer-specific identifiers) and ensure audit logs for edits.

## Phase 3 – Diagnostic Experience (UI/UX)
1. Create routing dashboard with:
   - Topology view highlighting primary/secondary relationships and current health states.
   - Incident banner for active primary route outages with severity, impact radius, and live timer.
   - Filters for environment, ownership, maintenance, and dependency clusters.
2. Detail panel for each route including:
   - Current health signals, last verification timestamp, and contributing checks with pass/fail state.
   - Suggested remediation steps pulled from linked runbooks plus quick-launch commands (e.g., traceroute, config diff).
   - Ownership metadata (on-call rota, Slack channel) and escalation button.
3. Integrate historical timeline showing outages, suppressions, maintenance windows, and recovery notes.
4. Provide manual acknowledgement & resolution controls that sync with backend event state.

## Phase 4 – Alerting & Communications
1. Define trigger matrix for:
   - Primary route down (critical), degraded (major), flapping (warning), maintenance overlap (info), and recovery (resolve).
   - Include detection of telemetry blind spots (no data beyond SLA) with fallback notifications.
2. Configure channel routing per persona (PagerDuty for on-call, Slack/email for support, webhook for automation).
3. Draft rich alert templates containing route ID, impact summary, downstream dependencies, recommended checks, runbook link, and ack instructions.
4. Implement suppression rules (maintenance mode, acknowledged incidents) and throttling to avoid alert storms.
5. Sync incident lifecycle with existing incident management workflow (auto-create, update, resolve).

## Phase 5 – Reliability & Observability
1. Instrument services with structured logging keyed by `RouteId` and correlation IDs for cross-service tracing.
2. Publish metrics: evaluation latency, snapshot staleness, alert volume, false positive rate, time-to-acknowledge, time-to-resolution.
3. Deploy dashboards (Grafana/PowerBI) for live monitoring plus weekly health reports.
4. Schedule synthetic failover drills to validate detection, alerting, and UI guidance end to end.
5. Document playbook updates and ensure compliance logging (who acknowledged, actions taken, timestamps).

## Phase 6 – Testing & Rollout
1. Testing strategy:
   - Unit tests for scoring logic, status transitions, and API contracts.
   - Integration tests with mocked telemetry feeds and database fixtures.
   - End-to-end scenarios using synthetic route failures to validate UI + alert pipeline.
   - Chaos experiments to simulate partial telemetry loss and verify graceful degradation.
2. Deployment approach:
   - Feature flag for routing experience with progressive exposure (internal -> pilot customers -> GA).
   - Canary environment to validate telemetry ingestion and alert templates before production cutover.
   - Rollback procedure documented for each service component.
3. Training & enablement:
   - Update runbooks and produce short Loom/video walk-throughs.
   - Host training sessions with ops/support, capturing feedback for iteration backlog.

## Milestones & Timeline (Draft)
1. Discovery & schema design complete – Week 2.
2. Backend services & migrations ready in staging – Week 5.
3. UI diagnostics beta + alert templates validated – Week 7.
4. Pilot rollout with selected customers – Week 8.
5. GA launch with full alerting + documentation – Week 10.

## Risks & Mitigations
- **Telemetry gaps:** Some routes may lack reliable probes. Mitigate by prioritising instrumentation workstream and setting "unknown" status fallback alerts.
- **Ownership ambiguity:** Missing route contacts delay remediation. Require ownership field as part of migration and tie to on-call rota.
- **Alert fatigue:** Overly sensitive thresholds could spam teams. Invest in debouncing, severity tuning, and suppression policies.
- **UI complexity:** Dense data may overwhelm support teams. Conduct usability tests and establish progressive disclosure (summaries first, details on demand).
- **Integration friction:** Existing incident tooling may resist new payloads. Engage tooling owners early and offer backward-compatible webhooks.

## Open Questions
1. Do we maintain separate schemas for customer-specific vs core network routes?
2. Are there regulatory requirements for storing route outage history (e.g., retention, privacy)?
3. Which team owns long-term telemetry maintenance and synthetic checks?
4. How do we handle hybrid connectivity routes that cross partner networks with limited visibility?
5. What SLAs must we publish externally once this visibility exists?

## Immediate Next Steps
1. Schedule discovery workshops with network ops, support, and product leads.
2. Draft detailed data model diagrams and service interaction architecture.
3. Prepare resource plan (engineering, UX, SRE) aligning to milestones above.


