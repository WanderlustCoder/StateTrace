# StateTrace Quarterly Roadmap (Q4 2025)

This roadmap outlines the high-level milestones planned for the fourth quarter of 2025. Each milestone includes a target date, the primary owner, a brief description of the scope and the exit criteria that define completion. Refer to this document when planning weekly sprints and retrospectives.

| Milestone | Task board ID | Target date | Owner | Scope highlights | Exit criteria |
|----------|---------------|-------------|-------|------------------|--------------|
| **M1 - Multi-DB ingestion foundation** | ST-B-010 | **2025-10-14** | Ingestion Engineer | - Finalise per-site queue and adaptive runspace pool<br>- Implement incremental persistence and parameterised commands<br>- Ship `Maintain-AccessDatabases.psm1` and schedule nightly compaction job | OK Load test demonstrates no ACE/JET contention at 8 concurrent workers<br>OK Throughput drop <=5% when doubling number of databases<br>OK Nightly maintenance job runs successfully for 14 consecutive days |
| **M2 - Routing discovery baseline** | ST-A-007 | **2025-11-15** | Program Owner | - Complete discovery sessions following guidance in `docs/StateTrace_Consolidated_Plans.md#plan-a-routing-reliability`<br>- Define canonical `RouteRecord` and `RouteHealthSnapshot` schemas<br>- Produce initial notes and diagrams in `StateTrace_Routing_DataArchitecture.md` | OK Stakeholder-aligned definitions of primary/secondary routes and detection latency<br>OK Documented telemetry inventory and gap analysis<br>OK Draft data model and service diagrams reviewed by stakeholders |
| **M3 - Diff prototype & launch metrics instrumentation** | ST-C-001 | **2025-12-31** | Parser Team & Analytics | - Build diff data model prototype and record metrics in `Logs/Research/DiffPrototype`<br>- Define and implement Phase 1 telemetry dictionary (see `telemetry/Phase1_metrics.md`)<br>- Publish initial launch metrics dashboard wireframes | OK Diff prototype ingests a representative fixture and produces versioned snapshots with diff metadata<br>OK Telemetry events (`ParseDuration`, `RowsWritten`, `DiffUsageRate`, `DriftDetectionTime`) emitted and stored locally<br>OK Wireframes validated with beta stakeholders and approved for implementation |

### How to use this roadmap

- **Sync with plans:** Each milestone corresponds to workstreams described in the respective plan documents. Use the scope bullets as a quick reminder of what must be delivered.
- **Review cadence:** Update progress against each milestone during weekly retrospectives. Adjust target dates only after discussing impact on downstream milestones.
- **Exit criteria:** Treat exit criteria as acceptance gates. A milestone is complete only when all listed criteria are demonstrably met.
- **Task board linkage:** Keep milestones tied to Task Board IDs and mark entries as done with `Done - YYYY-MM-DD` once exit criteria are met.
- **Change hygiene:** When milestone scope or dates change, update the relevant plan page and Task Board row alongside this roadmap.
