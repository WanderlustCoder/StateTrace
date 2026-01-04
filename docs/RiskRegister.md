# StateTrace Risk Register

This register consolidates the top risks identified across all active plans.  Each entry includes a description of the risk, the trigger or early warning signal, the proposed mitigation, the owner responsible for tracking it and the review cadence.  Update this document whenever new risks are discovered or existing risks are retired.

## How to use
- Add a new entry when a risk is identified in a plan, task, or incident.
- Reference the relevant Plan ID and Task Board ID in the risk or mitigation text when available.
- Update mitigations and evidence links as work progresses.

| # | Risk | Trigger | Mitigation | Owner | Review cadence |
|---|------|---------|-----------|-------|---------------|
| 1 | **Telemetry gaps create blind spots** | No data received for a route or ingestion job beyond the defined SLA (e.g. 5 minutes) | Build fallback “unknown” status alerts and prioritise instrumentation of missing probes; expose stale data metrics on dashboards | Platform SRE | Weekly during routing rollout |
| 2 | **Database contention & provider errors** | Ingestion backlog grows or ACE/JET provider throws lock/contention exceptions | Gate per‑site concurrency, reuse ADODB connections and run nightly maintenance script to compact and index databases | Ingestion Engineer | After each ingestion load test |
| 3 | **Slow incident sanitisation** | Time to sanitise postmortem logs exceeds 1 day | Automate redaction with `Sanitize-PostmortemLogs.ps1`; allocate buffer time and parallelise sanitisation tasks | Data Steward | After each incident intake |
| 4 | **Overcommitment of solo operator** | Task board accumulates more than two active items per column or weekly hours exceed capacity | Enforce weekly WIP limits (see resource plan), rotate focus areas and defer lower‑priority work | Program Owner | Friday retrospectives |
| 5 | **Alert fatigue** | High volume of false positives or repeated alerts cause operators to ignore notifications | Implement debouncing and severity tuning in alerting; provide suppression policies and per‑route thresholds | Platform SRE | After each alerting release |
| 6 | **Identity and RBAC uncertainty** | Features requiring user authentication (acknowledgements, custom rules) cannot ship due to unresolved identity approach | Complete evaluation in `StateTrace_Acknowledgement_Identity_Options.md` and define interim identity layer | Product Manager | End of Q4 2025 |
| 7 | **Storage growth exceeds Access limits** | `.accdb` files approach 2 GB or disk utilisation crosses safe thresholds | Run nightly compaction and index rebuild (see maintenance script); archive old data to backups on size alerts | Ingestion Engineer | Nightly via job summary |
| 8 | **Parser performance regressions** | P95 parse time for representative bundles increases >20% over baseline | Maintain baseline benchmarks and run them after each performance change; revert or optimise on regressions | Parser Team | Per change set |
| 9 | **Sensitive data leakage** | Secrets, credentials or customer identifiers appear in stored logs or exported packets | Enforce redaction patterns in sanitiser; move fixtures to `Tests/Fixtures/` and exclude `Logs/` from version control (see Security guidelines) | Data Steward | On each ingest & release |
| 10 | **Feature adoption lag** | New insights, diff tools or runbooks remain unused by intended personas | Provide training sessions, in‑product tours and monitor telemetry; iterate based on feedback | Customer Success | Monthly |
<!-- LANDMARK: ST-B-010 risk register entry -->
| 11 | **Plan B gate drift from missing telemetry** | AllChecks logs show `TelemetryModule not loaded` or missing `C:\data\site.accdb`, or Plan B telemetry bundles lack warm-run metrics | Ensure TelemetryModule auto-loads in offline runs, provide a deterministic sample Access DB path, and re-run AllChecks + publish telemetry bundle; track under Task Board ST-B-010 and bundle `Logs/TelemetryBundles/Release-20260101-ST-B-008-20260101-145226` for Plan G review | Ingestion Lead | Each release candidate |
