# INC0001 Routing Queue Delay Spike
<!-- LANDMARK: ST-D-005 runbook -->
## Summary
Investigate dispatcher queue delays when PortBatchReady backlog grows; validate queue delay telemetry and dispatcher gaps.

## Preconditions
- Access to Logs/IngestionMetrics/<date>.json and QueueDelaySummary-<date>.json
- Access to Tools/Analyze-DispatcherGaps.ps1 (offline)
- Sanitized bundle path: Data/Postmortems/INC0001/Sanitized

## Steps
1. Review QueueDelaySummary-<date>.json for P95/P99 spikes; confirm the same interval in Logs/IngestionMetrics/<date>.json.
2. Run Tools/Analyze-DispatcherGaps.ps1 against the queue summary and port batch interval report to correlate gaps.
3. In Logs/IngestionMetrics/<date>.json, filter EventName = PortBatchReady and InterfacePortQueueMetrics to confirm dispatcher throughput.
4. Compare InterfaceSyncTiming BulkStageDurationMs and DiffDurationMs for hosts with the delay spike.
5. Capture the queue delay summary path and the Analyze-DispatcherGaps report in the session log.

## Expected Results
- QueueDelaySummary shows elevated P95/P99 for the incident window; dispatcher gap report identifies the same window.
- PortBatchReady events resume after the gap; InterfaceSyncTiming durations return to baseline.

## Escalation
- Escalate to scheduler/dispatcher owners if gaps persist across runs or PortBatchReady stops.
- Escalate to ingestion pipeline owners if InterfaceSyncTiming shows sustained elevated BulkStageDurationMs.
