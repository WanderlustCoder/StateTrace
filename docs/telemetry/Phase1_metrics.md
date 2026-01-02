# StateTrace Phase 1 Telemetry Dictionary

This document defines core telemetry events for product usage and ingestion performance. It also includes a short section on engineering/agent telemetry to help us see how agent contributions perform over time.

## Product & ingestion metrics

| Event/Metric | Description | Schema fields | Source | Aggregation | Target/Alert |
|--------------|-------------|---------------|--------|-------------|--------------|
| **ParseDuration** | Time to parse a single device log bundle | `Hostname` (string), `Site` (string), `StartTime` (datetime), `DurationSeconds` (float) | Parser pipeline | p95 & max per day | p95 ≤ 3 s; alert if max > 10 s |
| **RowsWritten** | Records inserted/updated for a host ingestion | `Hostname`, `Site`, `RunDate`, `Rows` (int), `DeletedRows` (int) | Persistence layer | Sum per site per day | Monitor for outliers |
| **SkippedDuplicate** | Hosts skipped due to unchanged hash | `Site`, `HostCount` (int), `Date` | Ingestion scheduler | Daily total | Expect high skip rate (>50%) after incremental updates |
| **DatabaseWriteLatency** | Time waiting for DB locks/commit | `Site`, `StartTime`, `LatencyMs` (int) | Persistence | Average & p95 | p95 ≤ 200 ms; alert if > 500 ms |
| **DiffUsageRate** | Compare view diff execution usage (one event per executed compare) | `Timestamp` (datetime), `Source` (string), `Status` (string), `UsageNumerator` (int), `UsageDenominator` (int), `Site` (string), `Hostname` (string), `Hostname2` (string), `Port1` (string), `Port2` (string), `Vrf` (string, optional) | Compare view UI | Rolling weekly ratio (sum `UsageNumerator` / sum `UsageDenominator`) | >= 70% in pilot |
| **DiffCompareDurationMs** | Compare view diff execution duration (per executed compare) | `TimestampUtc` (datetime), `Source` (string), `Status` (string), `DurationMs` (int), `Site` (string), `Hostname` (string), `Hostname2` (string), `Port1` (string), `Port2` (string), `Vrf` (string, optional) | Compare view UI | p50/p95 of `DurationMs` for `Status=Executed`, segmented by site | Establish baseline; alert if p95 regresses 2x |
| **DiffCompareResultCounts** | Compare view diff result cardinality (line-level; Added/Removed from Compare-Object, ChangedCount fixed at 0, UnchangedCount for shared trimmed lines; TotalCount is sum) | `TimestampUtc` (datetime), `Source` (string), `Status` (string), `TotalCount` (int), `AddedCount` (int), `RemovedCount` (int), `ChangedCount` (int), `UnchangedCount` (int), `Site` (string), `Hostname` (string), `Hostname2` (string), `Port1` (string), `Port2` (string), `Vrf` (string, optional), `DurationMs` (int, optional on failed compares) | Compare view UI | Sum counts per site/run, filter `Status=Executed` | Establish baseline per site; alert on spike in Added/Removed totals |
| **DriftDetectionTime** | Time between change and detection | `Hostname`, `ChangeDetectedAt`, `ChangedField`, `DurationMinutes` | Diff/anomaly engine | p95 per change type | −40% vs. baseline |

## Engineering / agent metrics (optional)

| Event/Metric | Description | Schema fields | Source | Aggregation | Target |
|--------------|-------------|---------------|--------|-------------|--------|
| **AgentTestPassRate** | Fraction of agent sessions with passing tests | `SessionId`, `Date`, `Passed` (bool) | CI/logs | Weekly ratio | ≥ 95% |
| **AgentChangeSize** | Lines changed per session | `SessionId`, `Files`, `Added`, `Removed` | VCS logs | Weekly p50/p95 | Keep p95 small |
| **AgentRevertRate** | Sessions that required rollback | `SessionId`, `Reason` | VCS/PRs | Weekly count | Near zero |

**Implementation notes:** Emit telemetry locally to `Logs/IngestionMetrics/<date>.json`. Engineering metrics can be derived from CI logs and PR metadata; do not include personal data. Use `Tools/Rollup-IngestionMetrics.ps1` to generate daily CSV summaries (totals, averages, and p95 values) for `ParseDuration`, `DatabaseWriteLatency`, `RowsWritten`, and `SkippedDuplicate`; append `-IncludePerSite` for per-site breakdowns and `-IncludeSiteCache` to surface `SiteCacheFetchDurationMs` status/provider counts and percentile timing.
