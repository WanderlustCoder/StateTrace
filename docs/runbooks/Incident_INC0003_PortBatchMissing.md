# INC0003 PortBatchReady Missing
<!-- LANDMARK: ST-D-005 runbook -->
## Summary
Handle incidents where PortBatchReady telemetry is missing and UI loading indicators never resolve.

## Preconditions
- Access to Logs/IngestionMetrics/<date>.json
- Access to Tools/Invoke-StateTracePipeline.ps1 and Tools/Invoke-InterfacesViewChecklist.ps1
- Sanitized bundle path: Data/Postmortems/INC0003/Sanitized

## Steps
1. Inspect Logs/IngestionMetrics/<date>.json for EventName = PortBatchReady and InterfaceSyncTiming; confirm counts are zero for PortBatchReady.
2. Rerun Tools/Invoke-StateTracePipeline.ps1 with -RunQueueDelayHarness and -ForcePortBatchReadySynthesis to seed PortBatchReady events if dispatcher metrics exist.
3. If PortBatchReady is still missing, run Tools/Invoke-InterfacesViewChecklist.ps1 headlessly to seed InterfacePortQueueMetrics and confirm UI binding.
4. Capture DatabaseWriteBreakdown events to ensure persistence writes are occurring.
5. Record the telemetry paths and any synthesized PortBatchReady entries in the session log.

## Expected Results
- PortBatchReady events are present after re-running the harness or synthesis step.
- InterfaceSyncTiming and DatabaseWriteBreakdown show successful persistence activity.

## Escalation
- Escalate to ingestion pipeline owners if PortBatchReady remains absent after harness reruns.
- Escalate to UI owners if the Interfaces view remains stuck despite telemetry recovery.
