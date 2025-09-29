# StateTrace Multi-Database Ingestion Plan

## Objectives
- Sustain fast ingestion even as the number and size of per-site Access databases grow.
- Prevent write contention and provider errors when many hosts are parsed concurrently.
- Keep the solution within the current PowerShell + Access architecture while creating hooks for future scale-out.

## Constraints & Current Baseline
- Each site is stored in its own Access `.accdb` under `Data/` (e.g., `WLLS.accdb`).
- Parser workers already stream logs and write in parallel runspaces, but Access requires STA threading and serialised commits per database.
- No new external data stores or compiled components; enhancements must remain script-based.
- Existing modules assume Access schema parity; changes must be backwards compatible.

## Bottlenecks Observed
- Multiple workers trying to open the same `.accdb` trigger ACE/JET provider issues.
- Per-host transactions write full interface sets, causing long locks on large tables.
- Database files can grow quickly; compaction and index maintenance are manual.
- Ingestion queue does not prioritise hosts/sites, so heavy sites can starve others.

## Workstream A: Database Topology & Scheduling
1. **Site Directory Structure**
   - Group site databases by leading site prefix (e.g., `Data/WLLS/WLLS.accdb`) to reduce single-directory congestion.
   - Update `DeviceRepositoryModule::Get-DbPathForSite` to honour the new layout (backwards-compatible fallback).
2. **Ingestion Scheduler**
   - [Done - 2025-09-28] ParserRunspaceModule now queues device files per site and enforces a configurable per-site worker limit.
   - Next: capture scheduler metrics (queued vs. active jobs) for telemetry visibility.

## Workstream B: Parser Throughput Enhancements
1. **Change Detection**
   - [Done - 2025-09-28] SHA-256 hashes now drive per-site ingestion history (`Data/IngestionHistory/<Site>.json`); unchanged bundles are skipped before parsing.
2. **Incremental Updates**
   - [Done - 2025-09-28] Parser persistence now diffs interfaces per-port, issuing targeted deletes/inserts instead of wiping the table each run.
   - Next: evaluate staging tables (`Interfaces_Staging`) for batching and lock reduction.
3. **Adaptive Runspace Pool**
   - Dynamically size runspace pool based on CPU count and current queue length.
   - Expose configuration in `StateTraceSettings.json` (e.g., `MaxConcurrentSites`, `MaxWorkersPerSite`).

## Workstream C: Access Write Optimisation
1. **Connection Reuse**
   - [Done - 2025-09-28] Parser now acquires cached ADODB connections per database with configurable TTL; connections close automatically when idle.
2. **Parameterized Statements**
   - Refactor persistence helpers (`Update-DeviceSummaryInDb`, `Update-InterfacesInDb`) to use parameterized `ADODB.Command` objects for repeated inserts, reducing parsing overhead.
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
   - Collect database size stats post-ingestion and emit warnings when thresholds are crossed.

## Workstream E: Telemetry & Observability
- Log ingestion metrics (`ParseDuration`, `RowsWritten`, `SkippedDuplicate`) to `Logs/IngestionMetrics/<date>.json`.
- Add Pester/Smoke tests that simulate multi-site queues to validate scheduler behaviour.
- Surface a lightweight dashboard tab (future) showing site ingest backlog.

## Milestone Outline
1. **Scheduler & STA Validation**
   - [Done - 2025-09-28] Per-site queue implemented; next measure throughput under load tests.
2. **Incremental Persistence Prototype**
   - Demonstrate delta writes on large synthetic datasets; measure DB lock duration.
3. **Maintenance Automations**
   - Ship compaction/index scripts with configuration toggles.
4. **Telemetry Rollup**
   - Capture ingestion metrics and integrate with planned launch dashboard.

## Validation Strategy
- Create load-test harness that replays >1GB of logs across multiple sites.
- Measure total ingestion time, per-site throughput, and error rates before/after each workstream.
- Ensure regression suite (Pester + smoke) covers synchronous and queued ingestion paths.

## Follow-Up Actions (Self-Directed)
- [Done - 2025-09-28] Ingestion scheduler implemented (per-site queue + worker gating).
- Define schema for ingestion history table and update persistence module accordingly.
- Draft automation scripts for compaction and size telemetry; integrate with upcoming dashboard work.

## Configuration
- Parser concurrency can be tuned via `Data/StateTraceSettings.json` under `ParserSettings` (keys: `AutoScaleConcurrency`, `MaxWorkersPerSite`, `MaxActiveSites`, `MaxRunspaceCeiling`, `MinRunspaceCount`, `JobsPerThread`, `EnableAdaptiveThreads`).
- Set `AutoScaleConcurrency` to `true` (and leave numeric limits at `0`) to let the parser size the runspace pool from CPU count and the current queue; disable it when you need explicit caps and increase them gradually while monitoring ingestion telemetry.
