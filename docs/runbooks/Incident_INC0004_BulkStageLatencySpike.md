# INC0004 Bulk Stage Latency Spike
<!-- LANDMARK: ST-D-009 runbook -->
## Summary
Investigate sustained BulkStageDurationMs spikes when interface batches slow down despite normal PortBatchReady counts.

## Preconditions
- Access to Logs/IngestionMetrics/<date>.json
- Access to Tools/Invoke-StateTracePipeline.ps1 (offline)
- Sanitized bundle path: Data/Postmortems/INC0004/Sanitized

## Steps
1. In Logs/IngestionMetrics/<date>.json, filter EventName = InterfaceSyncTiming and capture hosts with elevated BulkStageDurationMs.
2. Review DatabaseWriteBreakdown entries for the same hosts; confirm bulk insert duration and row counts align with the spike window.
3. Cross-check PortBatchReady events to verify PortsCommitted remains consistent while BulkStageDurationMs is elevated.
4. If BulkStageDurationMs stays high across hosts, rerun Tools/Invoke-StateTracePipeline.ps1 with -VerboseParsing to reproduce telemetry.
5. Record the telemetry paths and the worst-case BulkStageDurationMs values in the session log.

## Expected Results
- InterfaceSyncTiming shows a clear spike window that aligns with DatabaseWriteBreakdown bulk insert activity.
- PortBatchReady counts remain steady; the slowdown is isolated to bulk staging/persistence.

## Escalation
- Escalate to persistence owners if BulkStageDurationMs stays elevated after a rerun.
- Escalate to telemetry owners if DatabaseWriteBreakdown is missing during the spike window.
