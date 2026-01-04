# INC0002 Shared Cache Refresh Spike
<!-- LANDMARK: ST-D-005 runbook -->
## Summary
Investigate shared-cache refresh spikes when AccessRefresh counts are high and SnapshotImported drops.

## Preconditions
- Access to Logs/IngestionMetrics/<date>.json
- Access to Tools/Analyze-SharedCacheStoreState.ps1 and Tools/Analyze-SiteCacheProviderReasons.ps1
- Sanitized bundle path: Data/Postmortems/INC0002/Sanitized

## Steps
1. Run Tools/Analyze-SharedCacheStoreState.ps1 against the ingestion metrics JSON to confirm SnapshotImported and shared cache GetHit/GetMiss counts.
2. Run Tools/Analyze-SiteCacheProviderReasons.ps1 to summarize provider reasons and confirm AccessRefresh counts.
3. In Logs/IngestionMetrics/<date>.json, filter EventName = InterfaceSyncTiming and DatabaseWriteBreakdown to correlate cache misses with sync duration.
4. Confirm SharedCacheStoreState reports SnapshotImported > 0 for the affected sites; if not, verify STATETRACE_SHARED_CACHE_SNAPSHOT handling.
5. Record the analyzer outputs and summary counts in the session log.

## Expected Results
- Shared cache analyzer reports show AccessRefresh spikes aligned with increased InterfaceSyncTiming durations.
- SnapshotImported is non-zero after a healthy warm snapshot import.

## Escalation
- Escalate to cache/persistence owners if SnapshotImported remains zero or AccessRefresh stays elevated after reruns.
- Escalate to telemetry owners if InterfaceSyncTiming or DatabaseWriteBreakdown events are missing.
