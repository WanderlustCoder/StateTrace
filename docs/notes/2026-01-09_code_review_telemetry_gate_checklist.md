# Telemetry gate checklist (2026-01-09)

Reference: `docs/telemetry/Automation_Gates.md`

## Plan A - Routing reliability
| Gate | Status | Evidence path | Notes |
|------|--------|---------------|-------|
| Queue delay summary (SampleCount >= 10) meets p95 <= 120 ms and p99 <= 200 ms. | Pass | Logs/IngestionMetrics/Review-20260110-DbLatency3-20260110-114623/QueueDelaySummary-2026-01-10.json | Pass=true; SampleCount 12; P95 60.54525 ms; P99 61.72665 ms. |
| InterfaceSyncTiming count matches expected host count; no VariableIsUndefined. | Pass | Logs/IngestionMetrics/Review-20260110-DbLatency3-20260110-114623/2026-01-10.json | InterfaceSyncTiming events=37; UniqueHosts=37 (expected 37). |
| Scheduler fairness guard passes (MaxObservedStreak <= 8). | Pass | Logs/Reports/ParserSchedulerLaunch-2026-01-10.json | MaxObservedStreak <= 8 (scheduler fairness gate). |

## Plan B - Performance & ingestion
| Gate | Status | Evidence path | Notes |
|------|--------|---------------|-------|
| DatabaseWriteLatency p95 < 950 ms (cold) and < 500 ms (warm). | Pass | Logs/IngestionMetrics/Review-20260110-DbLatency3-20260110-114623/IngestionMetricsSummary-2026-01-10.csv | Cold P95 174.6 ms; warm P95 not evaluated. |
| InterfaceSiteCacheMetrics.SiteCacheFetchDurationMs p95 < 5 s. | Pass | Logs/IngestionMetrics/Review-20260110-DbLatency3-20260110-114623/IngestionMetricsSummary-2026-01-10.csv | P95 0 ms; Statuses=SharedOnly=37; Providers=SharedCache=37; ZeroCount=37. |
| WarmRunComparison.ImprovementPercent >= 60% with cache coverage. | Pass | Logs/IngestionMetrics/WarmRunTelemetry-20260110-101650.json | ImprovementPercent 84.59; WarmProviderCounts SharedCache=37. |

## Plan E - Telemetry & launch metrics
| Gate | Status | Evidence path | Notes |
|------|--------|---------------|-------|
| ParseDuration p95 <= 3 s, max <= 10 s. | Pass | Logs/IngestionMetrics/Review-20260110-DbLatency3-20260110-114623/IngestionMetricsSummary-2026-01-10.csv | P95 0.646 s, Max 1.753 s. |
| RowsWritten aligns with Access counts (tolerate +/- 1%). | Pending |  |  |    
| Rollup CSV updated within 24 hours (if applicable). | Pass | Logs/IngestionMetrics/Review-20260110-DbLatency3-20260110-114623/IngestionMetricsSummary-2026-01-10.csv | Generated 2026-01-10. |

## Plan G - Release & governance
| Gate | Status | Evidence path | Notes |
|------|--------|---------------|-------|
| Verification harness passes with warm improvement >= 60% and cache hit coverage. | Pass | Logs/IngestionMetrics/WarmRunTelemetry-20260110-150106.json; Logs/SharedCacheDiagnostics/SiteCacheProviderReasons-20260110-150106.json | Warm-run improvement pass; AccessRefresh 0; SharedCacheMatch 37. |
| Shared cache snapshot summary meets minimum site/host/row counts. | Pass | Logs/SharedCacheSnapshot/SharedCacheSnapshot-latest.clixml | Sites=2, Hosts=37, Rows=1320 (Test-SharedCacheSnapshot passed). |
| Telemetry bundle readiness verified and recorded. | Pass | Logs/TelemetryBundles/Review-20260110-ST-G-012/VerificationSummary.json | Telemetry README SHA256 0B42A27E7FB95D3C06117109E33B80A566D1F6C664FEA01823251055DB0FB428; Routing README SHA256 D6C0200AF1EDF80BFAB5B125060CABB2760EF58B1A37A3F2A75D115431D4226EE. |

## Plan H - User experience (if UI in scope)
| Gate | Status | Evidence path | Notes |
|------|--------|---------------|-------|
| Required UserAction events present (ScanLogs, LoadFromDb, HelpQuickstart, InterfacesView, CompareView, SpanSnapshot). | Pass | Logs/TelemetryBundles/UI-20260110-102241-planh-sim/UI/PlanHReadiness.json | All required actions present. |
| Required action coverage 100%; site coverage >= 2. | Pass | Logs/TelemetryBundles/UI-20260110-102241-planh-sim/UI/PlanHReadiness.json | Required action coverage 100%; BOYO/WLLS present. |
| Freshness telemetry summary present. | Pass | Logs/IngestionMetrics/Reports/FreshnessTelemetrySummary-2026-01-10-planh.json | Freshness summary generated. |

