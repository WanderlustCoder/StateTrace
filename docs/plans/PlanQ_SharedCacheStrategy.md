# Plan Q - Shared Cache Strategy & Snapshot Governance

## Objective
Stabilize shared cache adoption across cold/warm runs by formalizing snapshot governance (coverage targets, rotation, seeding), eviction policies, and offline snapshot reuse so warm-hit ratios stay high without brittle per-site hacks.

## Current status (2025-12)
- Shared cache snapshots are exported/imported, but coverage for BOYO/WLLS remains uneven; `SnapshotImported` counts fluctuate and `AccessRefresh` spikes after rotations.
- No policy for snapshot rotation, aging, or fallback seeds; warm runs sometimes rebuild from scratch when snapshots are missing or incompatible.
- Eviction and size guards are implicit; no automated check enforces host/row minima before verification.

## Active work
| ID | Title | Owner | Status | Notes |
|----|-------|-------|--------|-------|
| ST-Q-001 | Snapshot governance policy | Ingestion | In Progress | Added `Tools\Test-SharedCacheSnapshot.ps1` to enforce site/host/row minima and required sites (clixml or summary JSON). Next: document rotation cadence and wire guard into verification defaults. |
| ST-Q-002 | Snapshot seeding & fallback | Ingestion | Backlog | Add a lightweight seed bundle (tracked) for fixtures so warm runs never start from empty cache. Detect missing/old snapshots and auto-use the seed with a log note. |
| ST-Q-003 | Eviction/size guard | Performance | Backlog | Add analyzer/check that validates snapshot size, host count, and eviction rate; fail harness if cache shrinks unexpectedly or exceeds size budget. |
| ST-Q-004 | Compatibility checks | Automation | Backlog | Before import, validate schema/version and site list; refuse incompatible snapshots and suggest regeneration. |

## Recently delivered
- Plan created to formalize shared cache governance beyond per-run diagnostics.

## Automation hooks
- Snapshots: `Tools\Invoke-SharedCacheWarmup.ps1 -RequiredSites BOYO,WLLS -MinimumHostCount <n> -MinimumTotalRowCount <n> -ShowSharedCacheSummary`.
- Diagnostics: `Tools\Analyze-SharedCacheStoreState.ps1 -Path Logs\IngestionMetrics\<file>.json -IncludeSiteBreakdown`, `Tools\Analyze-SiteCacheProviderReasons.ps1 -IncludeHostBreakdown`.
- Import guard: `Tools\Test-SharedCacheSnapshot.ps1 -Path Logs\SharedCacheSnapshot-*.clixml -MinimumSiteCount <n> -MinimumHostCount <n> -MinimumTotalRowCount <n> -RequiredSites BOYO,WLLS` (accepts summary JSON too).

## Telemetry gates
- `SnapshotImported > 0` for all parser runspaces; host/row counts meet policy thresholds per site.
- `AccessRefresh` and `SharedCacheUnavailable` stay below defined limits; `GetHit` exceeds `GetMiss`.
- Snapshot age within policy; incompatible or stale snapshots rejected with actionable error.

## References
- `docs/plans/PlanB_Performance.md` (warm-run/shared-cache analyzers).
- `docs/CODEX_SHARED_CACHE_DIAGNOSTICS.md` (analyzer workflow).
- `docs/plans/PlanI_HarnessStability.md` (guarded harness expectations).
