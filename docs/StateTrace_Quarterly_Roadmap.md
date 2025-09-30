# StateTrace Quarterly Roadmap (Q4Â 2025)

This roadmap outlines the highâ€‘level milestones planned for the fourth quarter ofÂ 2025.  Each milestone includes a target date, the primary owner, a brief description of the scope and the exit criteria that define completion.  Refer to this document when planning weekly sprints and retrospectives.

| Milestone | Target date | Owner | Scope highlights | Exit criteria |
|----------|-------------|-------|------------------|--------------|
| **M1Â â€“Â Multiâ€‘DB ingestion foundation** | **2025â€‘10â€‘14** | IngestionÂ Engineer | â€¢ Finalise perâ€‘site queue and adaptive runspace pool<br>â€¢ Implement incremental persistence and parameterised commands<br>â€¢ Ship `Maintainâ€‘AccessDatabases.ps1` and schedule nightly compaction job | âœ… Load test demonstrates no ACE/JET contention at 8 concurrent workers<br>âœ… Throughput drop â‰¤5% when doubling number of databases<br>âœ… Nightly maintenance job runs successfully for 14Â consecutive days |
| **M2Â â€“Â Routing discovery baseline** | **2025â€‘11â€‘15** | ProgramÂ Owner | â€¢ Complete discovery sessions following guidance in `docs/StateTrace_Consolidated_Plans.md#plan-a-routing-reliability`<br>â€¢ Define canonical `RouteRecord` and `RouteHealthSnapshot` schemas<br>â€¢ Produce initial notes and diagrams in `StateTrace_Routing_DataArchitecture.md` | âœ… Stakeholderâ€‘aligned definitions of primary/secondary routes and detection latency<br>âœ… Documented telemetry inventory and gap analysis<br>âœ… Draft data model and service diagrams reviewed by stakeholders |
| **M3Â â€“Â Diff prototype & launch metrics instrumentation** | **2025â€‘12â€‘31** | ParserÂ Team & Analytics | â€¢ Build diff data model prototype and record metrics in `Logs/Research/DiffPrototype`<br>â€¢ Define and implement PhaseÂ 1 telemetry dictionary (see `telemetry/Phase1_metrics.md`)<br>â€¢ Publish initial launch metrics dashboard wireframes | âœ… Diff prototype ingests a representative fixture and produces versioned snapshots with diff metadata<br>âœ… Telemetry events (`ParseDuration`, `RowsWritten`, `DiffUsageRate`, `DriftDetectionTime`) emitted and stored locally<br>âœ… Wireframes validated with beta stakeholders and approved for implementation |

### How to use this roadmap

- **Sync with plans:** Each milestone corresponds to workstreams described in the respective plan documents.  Use the scope bullets as a quick reminder of what must be delivered.
- **Review cadence:** Update progress against each milestone during weekly retrospectives.  Adjust target dates only after discussing impact on downstream milestones.
- **Exit criteria:** Treat exit criteria as acceptance gates.  A milestone is complete only when all listed criteria are demonstrably met.
