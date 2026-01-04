# INC0005 Cache Provider Fallback
<!-- LANDMARK: ST-D-009 runbook -->
## Summary
Investigate incidents where SiteCacheProviderReasons reports AccessRefresh spikes and warm cache reuse drops.

## Preconditions
- Access to Logs/IngestionMetrics/<date>.json
- Access to Tools/Analyze-SharedCacheStoreState.ps1 and Tools/Analyze-SiteCacheProviderReasons.ps1
- Sanitized bundle path: Data/Postmortems/INC0005/Sanitized

## Steps
1. Run Tools/Analyze-SharedCacheStoreState.ps1 against Logs/IngestionMetrics/<date>.json to capture SnapshotImported and GetHit/GetMiss counts.
2. Run Tools/Analyze-SiteCacheProviderReasons.ps1 to confirm AccessRefresh totals and host/provider breakdowns.
3. Filter EventName = InterfaceSyncTiming to compare sync durations when AccessRefresh spikes.
4. Confirm SnapshotImported remains non-zero after the ingestion pass; if zero, verify snapshot import prerequisites.
5. Record analyzer output paths and AccessRefresh counts in the session log.

## Expected Results
- AccessRefresh spikes align with increased InterfaceSyncTiming durations.
- SnapshotImported is non-zero after a healthy run; GetHit counts recover after remediation.

## Escalation
- Escalate to cache/persistence owners if AccessRefresh remains elevated or SnapshotImported stays zero.
- Escalate to telemetry owners if SiteCacheProviderReasons or InterfaceSyncTiming are missing.
