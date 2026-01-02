# StateTrace Diff Model Prototype Runbook

## Goal
Validate the storage footprint, Access schema, and performance characteristics of the proposed diff snapshot model before Phase 1 implementation.

## Prerequisites
- Sample log bundles covering at least three sequential captures per device (store under `Data/Samples/DiffPrototype/`).
- Access to Parser modules with recent performance improvements.
- Metrics template ready at `Logs/Research/DiffPrototype/metrics.csv` (CSV headers: CaptureId, DeviceCount, RunTimeSeconds, DbSizeMB, Notes).

## Prototype Steps
1. **Schema Draft**
   - Sketch proposed tables: `DiffRun`, `DiffObject`, `DiffChange`, `DiffMetadata`.
   - Define keys (DeviceId + CaptureId + ObjectHash) and expected columns (ChangeType, BeforeValue, AfterValue, Confidence).
   - Document assumptions in the **Schema Notes** section below.
2. **Parser Extension Spike**
   - Clone `Modules/DeviceLogParserModule.psm1` into a working branch.
   - Instrument parser to emit normalized objects with stable hashes (`System.Security.Cryptography.SHA256`).
   - Capture runtime metrics: lines processed/sec, memory usage (Get-Process), additional parse time per host.
3. **Persistence Test**
   - Create temporary Access DB shells under `Data/Prototypes/` (e.g., `Data/Prototypes/DiffPrototype.accdb`).
   - Implement PowerShell script to insert diff rows and enforce referential integrity.
   - Measure DB growth after each run and note query performance for typical lookups (interfaces changed, alerts changed).
4. **Query Validation**
   - Write sample queries that the UI will require (e.g., retrieve last 5 changes for host, filter by VLAN).
   - Ensure indices support expected query plans (ACCESS: create indexes on Hostname, ChangeType, CaptureTimestamp).
5. **Reporting**
   - Populate `Logs/Research/DiffPrototype/metrics.csv` with run summaries (capture count, runtime, DB size, notable errors).
   - Summarize findings in the **Results Summary** section and flag blockers.

## Schema Notes
- Document column definitions, data types, and relationships as you iterate.
- Capture any Access limitations encountered (e.g., table size, index constraints).

## Results Summary
- 2025-12-31: Fixture kit + telemetry schema validated for DiffUsageRate/DriftDetectionTime rollups; ready for Access baseline persistence run.
- Record overall viability assessment.
- List follow-up actions (e.g., need for incremental diffing, compression strategies).

## Sign-off Checklist
- [ ] Metrics logged for at least two devices with >=3 captures each.
- [ ] Prototype schema reviewed with Backend + Parser leads.
- [ ] Performance delta vs. current parser documented (<20% ingestion regression target).
- [ ] Ready/Not Ready decision communicated to Product.
