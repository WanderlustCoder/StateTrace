# StateTrace Multi‑Database Ingestion Plan
> **Status:** [In Progress – 2025-09-30] - Last reviewed 2025-09-30 by Ingestion Engineer

## Objectives
- Sustain fast ingestion even as the number and size of per‑site Access databases grow.
- Prevent write contention and provider errors when many hosts are parsed concurrently.
- Keep the solution within the current PowerShell + Access architecture while creating hooks for future scale‑out.

## Constraints & Current Baseline
- Each site is stored in its own Access `.accdb` under `Data/` (e.g. `WLLS.accdb`).
- Parser workers already stream logs and write in parallel runspaces, but Access requires STA threading and serialised commits per database.
- No new external data stores or compiled components; enhancements must remain script‑based.
- Existing modules assume Access schema parity; changes must be backwards compatible.

## Bottlenecks Observed
- Multiple workers trying to open the same `.accdb` trigger ACE/JET provider issues.
- Per‑host transactions write full interface sets, causing long locks on large tables.
- Database files can grow quickly; compaction and index maintenance are manual.
- Ingestion queue does not prioritise hosts/sites, so heavy sites can starve others.

## Workstream A: Database Topology & Scheduling
1. **Site Directory Structure**
   - [Done – 2025‑09‑29] Site databases now live under `Data/<prefix>/<Site>.accdb` (existing root files have been migrated).
   - [Done – 2025‑09‑29] `DeviceRepositoryModule::Get-DbPathForSite` prefers the grouped layout with automatic fallback to legacy paths.
2. **Ingestion Scheduler**
   - [Done – 2025‑09‑28] `ParserRunspaceModule` now queues device files per site and enforces a configurable per‑site worker limit.
   - Next: capture scheduler metrics (queued vs. active jobs) for telemetry visibility.

## Workstream B: Parser Throughput Enhancements
1. **Change Detection**
   - [Done – 2025‑09‑28] SHA‑256 hashes now drive per‑site ingestion history (`Data/IngestionHistory/<Site>.json`); unchanged bundles are skipped before parsing.
2. **Incremental Updates**
   - [Done – 2025‑09‑28] Parser persistence now diffs interfaces per port, issuing targeted deletes/inserts instead of wiping the table each run.
   - Next: evaluate staging tables (`Interfaces_Staging`) for batching and lock reduction.
3. **Adaptive Runspace Pool**
   - Dynamically size the runspace pool based on CPU count and current queue length.
   - Expose configuration in `StateTraceSettings.json` (e.g. `MaxConcurrentSites`, `MaxWorkersPerSite`).

## Workstream C: Access Write Optimisation
1. **Connection Reuse**
   - [Done – 2025‑09‑28] Parser now acquires cached ADODB connections per database with configurable TTL; connections close automatically when idle.
2. **Parameterized Statements**
   - [Done – 2025‑09‑30] Refactored persistence helpers (`Update-DeviceSummaryInDb`, `Update-InterfacesInDb`) to use parameterised `ADODB.Command` objects with fallback to legacy SQL when mock connections are provided.
3. **Transaction Tuning**
   - Continue batching writes in transactions but flush every N interfaces to shorten lock windows on massive devices.
   - Expose `MaxInterfacesPerBatch` setting to balance throughput vs. locking.

## Workstream D: Maintenance & Health
1. **Automated Compaction**
   - After significant writes, enqueue a background compaction task (`JRO.CompactDatabase`) per site during idle hours.
   - Retain a rolling backup (`Data/Backups/<Site>/<timestamp>.accdb`) before compaction.
2. **Index Audit**
   - Script to ensure key columns (Hostname, RunDate, Port) remain indexed; rebuild if missing.
3. **Disk Monitoring**
   - Collect database size stats post‑ingestion and emit warnings when thresholds are crossed.

## Workstream E: Telemetry & Observability
- Log ingestion metrics (`ParseDuration`, `RowsWritten`, `SkippedDuplicate`) to `Logs/IngestionMetrics/<date>.json`.
- Add Pester/Smoke tests that simulate multi‑site queues to validate scheduler behaviour.
- Surface a lightweight dashboard tab (future) showing site ingest backlog.

## Milestone Outline
1. **Scheduler & STA Validation**
   - [Done – 2025‑09‑28] Per‑site queue implemented; next measure throughput under load tests.
2. **Incremental Persistence Prototype**
   - Demonstrate delta writes on large synthetic datasets; measure DB lock duration.
3. **Maintenance Automations**
   - Ship compaction/index scripts with configuration toggles.
4. **Telemetry Rollup**
   - Capture ingestion metrics and integrate with planned launch dashboard.

## Verification & Definition of Done

The multi‑database ingestion improvements are considered complete when the following acceptance criteria are met and verified through the described approach:

### Acceptance criteria

- **Load test throughput:** Under a synthetic load of 1 GB of logs spread across at least 5 sites, the ingestion scheduler maintains queue depth near zero and processes devices without ACE/JET contention.  Overall ingestion time degrades by no more than 5% when doubling the number of databases.
- **Reduced lock durations:** The use of parameterised statements and batching yields p95 database write latencies (see `DatabaseWriteLatency` metric) below 200 ms.  Lock windows on large devices are reduced compared to the baseline.
- **Maintenance automation:** A new maintenance script (`Tools/Maintain-AccessDatabases.ps1`) successfully runs compaction and index audits across all site databases on a nightly schedule for 14 consecutive days.  Any failures are logged and alerted via the telemetry pipeline.
- **Telemetry visibility:** Scheduler metrics (queued vs. active jobs), ingestion history and database size stats are captured and rolled up into the Phase 1 metrics dashboard.  Missing telemetry generates alerts.
- **Backward compatibility:** Existing modules and UI continue to function without modifications to client code.  Legacy `.accdb` files remain readable.

### Verification approach

- **Load harness:** Create a harness that replays >1 GB of logs across multiple sites with varying device counts.  Capture total ingestion time, per‑site throughput and error rates before and after each workstream.
- **Telemetry inspection:** Emit `ParseDuration`, `RowsWritten`, `SkippedDuplicate` and `DatabaseWriteLatency` events.  Review aggregated metrics in `Logs/IngestionMetrics/<date>.json` and compare against acceptance thresholds.
- **Maintenance validation:** Install the nightly job using Windows Task Scheduler (or `Register-ScheduledTask`) to invoke `Tools/Maintain-AccessDatabases.ps1` with appropriate parameters.  Verify that:
  1. Backups are created under `Data/Backups/` with timestamped filenames.
  2. Compaction reduces file sizes by at least 10% when database size exceeds 500 MB.
  3. Index audit report shows required indexes present; if missing, the script rebuilds them.
  4. The job logs summary output to `Logs/Maintenance/<date>.log`.
- **Smoke & regression tests:** Run existing Pester tests and smoke tests after each change.  Specifically, simulate concurrent ingestion across multiple sites and verify that no deadlocks or unhandled exceptions occur.

## Configuration
- Parser concurrency can be tuned via `Data/StateTraceSettings.json` under `ParserSettings` (keys: `AutoScaleConcurrency`, `MaxWorkersPerSite`, `MaxActiveSites`, `MaxRunspaceCeiling`, `MinRunspaceCount`, `JobsPerThread`, `EnableAdaptiveThreads`).
- Set `AutoScaleConcurrency` to `true` (and leave numeric limits at `0`) to let the parser size the runspace pool from CPU count and the current queue; disable it when you need explicit caps and increase them gradually while monitoring ingestion telemetry.
