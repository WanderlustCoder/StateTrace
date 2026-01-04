# StateTrace Launch Metrics Dashboard Draft

## Purpose
Outline the initial telemetry and dashboard concepts needed to measure Phase 1 success metrics (diff usage, anomaly accuracy, guided troubleshooting adoption).

## Personas & Views
- **Product Leadership:** overall feature adoption, anomaly accuracy, user engagement.
- **Parser/Platform:** ingestion performance, rule accuracy, error rates.
- **Ops/Support:** incident handling efficiency, checklist completion, runbook usage.

## Metric Inventory
| Metric | Definition | Data Source | Refresh Cadence | Owner | Notes |
|--------|------------|-------------|-----------------|-------|-------|
| Diff Usage Rate | % of incidents where diff view opened | UI telemetry (tab open event) | Daily | Product Analytics | Segment by persona |
| Drift Detection Time | Median time from ingestion to diff card acknowledgement | Parser timestamps + UI events | Daily | Parser Eng | Requires diff metadata timestamps |
| Anomaly Precision | True positive / total anomaly cards | Feedback signals + incident tagging | Weekly | Product Analytics | Needs operator feedback workflow |
| Checklist Completion | % of guided checklists fully completed | UI checklist persistence | Daily | Ops Enablement | Track partial vs full |
| Parser Runtime Delta | Delta vs. baseline ingestion time | Parser logs instrumentation | Daily | Parser Eng | Use performance plan baselines |
| Runbook Click-through | Count of runbook opens per anomaly | UI telemetry | Daily | Support Eng | Flag stale runbooks |

## Dashboard Layout Concepts
1. **Executive Summary Tab**
   - KPI tiles: Diff Usage Rate, Checklist Completion, Anomaly Precision.
   - Trend lines for last 30 days.
   - Alert banner if Parser Runtime Delta > 20% regression.
2. **Parser & Telemetry Tab**
   - Heatmap: ingestion duration by site/device count.
   - Table: anomaly rule performance (precision/recall).
   - Drill-down chart: diff object counts per device.
3. **Operations Effectiveness Tab**
   - Checklist funnel (Started -> In Progress -> Completed).
   - Bar chart: runbook usage by incident category.
   - Time-to-acknowledge distribution.

## Instrumentation Tasks
- Define telemetry schema for UI events (diff open, checklist actions, runbook open) and ship to analytics pipeline.
- Extend parser logging to include diff generation time and anomaly rule output counts.
- Build nightly job to aggregate Access telemetry tables into CSV/JSON for dashboard tooling (Power BI / Grafana).

## Deliverables
- Dashboard wireframes (Figma or Draw.io) linked in this doc.
- Telemetry dictionary stored under `docs/telemetry/Phase1_metrics.md` (to be created).
- Implementation backlog tickets for instrumentation and dashboard build.

## Open Questions
- Which analytics platform will host the dashboard (Power BI, Grafana, custom report)?
- Do we need tenant-level filter controls for customer-facing reporting?
- How will we capture operator feedback on anomaly card accuracy (inline UI vs. external form)?
