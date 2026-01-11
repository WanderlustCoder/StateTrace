# Code review artifact map (2026-01-09)

Map required evidence to its storage location and the plan gate it supports.

| Artifact type | Example path | Plan gate | Consumed by |
|--------------|--------------|-----------|-------------|
| Pester summary | Logs/Verification/<file>.log | Plan K/G | Session log, Plan G |
| Ingestion metrics | Logs/IngestionMetrics/<file>.json | Plan A/B/E | Telemetry gates |
| Ingestion metrics summary | Logs/IngestionMetrics/<dir>/IngestionMetricsSummary-<date>.csv | Plan B/E | Telemetry gates |
| Warm run telemetry | Logs/IngestionMetrics/WarmRunTelemetry-<file>.json | Plan B/G | Release readiness |
| Warm run diff hotspots | Logs/IngestionMetrics/WarmRunDiffHotspots-<date>.json | Plan B | Performance analysis |
| Telemetry integrity report | Logs/Reports/TelemetryIntegrity-<date>.txt | Plan E/G | Readiness evidence |
| Shared cache snapshot | Logs/SharedCacheSnapshot/SharedCacheSnapshot-latest.clixml | Plan G | Release readiness |
| Shared cache store state | Logs/IngestionMetrics/<dir>/SharedCacheStoreState-<date>.json | Plan G | Cache gates |
| Site cache provider reasons | Logs/IngestionMetrics/<dir>/SiteCacheProviderReasons-<date>.json | Plan G | Cache gates |
| Queue delay summary | Logs/IngestionMetrics/<dir>/QueueDelaySummary-<date>.json | Plan A | Routing reliability |
| PortBatch diversity report | Logs/Reports/PortBatchSiteDiversity-<date>.json | Plan A/D/I | Incremental loading |
| PortBatch analyzer outputs | Logs/Reports/PortBatchReady-<date>.json | Plan A/D/I | Incremental loading |
| Scheduler fairness report | Logs/Reports/ParserSchedulerLaunch-<date>.json | Plan A/D/I | Scheduler gate |
| Scheduler vs PortBatch report | Logs/Reports/SchedulerVsPortDiversity-<date>.json | Plan I | Scheduler correlation |
| Plan H bundle | Logs/TelemetryBundles/UI-<date>-planh-sim | Plan H | Onboarding readiness |
| Telemetry bundle readiness | Logs/TelemetryBundles/<bundle>/VerificationSummary.json | Plan E/G | Release readiness |
| DocSync checklist | Logs/Reports/DocSyncChecklist-*.json | Plan G/N | Governance |
