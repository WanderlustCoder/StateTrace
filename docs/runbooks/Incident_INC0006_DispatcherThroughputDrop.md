# INC0006 Dispatcher Throughput Drop
<!-- LANDMARK: ST-D-009 runbook -->
## Summary
Investigate dispatcher throughput drops when InterfacePortQueueMetrics stalls and queue delay spikes recur.

## Preconditions
- Access to Logs/IngestionMetrics/<date>.json and QueueDelaySummary-<date>.json
- Access to Tools/Analyze-DispatcherGaps.ps1 (offline)
- Sanitized bundle path: Data/Postmortems/INC0006/Sanitized

## Steps
1. Review QueueDelaySummary-<date>.json for elevated P95/P99 queue delay windows.
2. Run Tools/Analyze-DispatcherGaps.ps1 using the queue summary and PortBatchIntervals report to identify gap windows.
3. Filter EventName = InterfacePortQueueMetrics and PortBatchReady to confirm dispatcher throughput during the gap.
4. Compare InterfaceSyncTiming DiffDurationMs around the same interval to identify downstream delays.
5. Capture the analyzer report path and gap window timestamps in the session log.

## Expected Results
- Dispatcher gap report aligns with queue delay spikes and reduced InterfacePortQueueMetrics throughput.
- PortBatchReady resumes after the gap window closes.

## Escalation
- Escalate to scheduler/dispatcher owners if gaps persist across reruns.
- Escalate to ingestion pipeline owners if InterfaceSyncTiming delays continue after dispatcher recovery.
