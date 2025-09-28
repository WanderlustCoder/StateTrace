# StateTrace Routing Data Architecture Draft

## Objective
Capture routing reliability data design notes as a single operator working through discovery and implementation.

## Deliverables
- ER sketch for RouteRecord, RouteHealthSnapshot, OutageEvent, RemediationTask, NotificationPreference.
- Sequence notes for ingestion, scoring, and alert publication flows.
- Integration checklist for Access tables, parser outputs, and upcoming UI requirements.

## Working Assumptions
- Access remains the persistence layer for Phase 1.
- Parser enhancements will emit routing health signals via existing PowerShell modules.
- Telemetry aggregation can begin as scripts before evolving into services.

## Solo Work Breakdown
1. **Domain Modeling (4 hrs)**
   - Draft entity attributes, keys, relationships.
   - Record notes directly in this document under *Domain Modeling Notes*.
2. **Ingestion Flow Outline (3 hrs)**
   - Map signal sources (SNMP, probes, logs) and polling cadence.
   - Identify transformation scripts needed.
3. **Health Scoring Logic (3 hrs)**
   - Describe scoring algorithm, thresholds, debouncing approach.
   - List data required for confidence scores and failover tracking.
4. **API Contract Sketch (2 hrs)**
   - Enumerate commands/endpoints the UI or automation will call.
   - Provide sample PowerShell object shapes/JSON payloads.
5. **Retention Strategy (2 hrs)**
   - Document storage durations for snapshots vs. aggregates.
   - Note archival or cleanup job ideas.

## Documentation Expectations
- Store diagrams/figures under `Resources/architecture/routing/` (PNG + source files).
- Timestamp updates in each section (e.g., `[Updated 2025-10-08]`).

## Review Cadence
- Perform periodic self-reviews; log findings and next steps in this doc.
- Revisit after major design decisions to ensure the model still fits.

## Sections to Populate
- Domain Modeling Notes
- Ingestion Flow Notes
- Health Scoring Notes
- API Concepts
- Retention & Archival
- Open Questions
