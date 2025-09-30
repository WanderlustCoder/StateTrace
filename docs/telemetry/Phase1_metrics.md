# StateTrace Phase 1 Telemetry Dictionary

This document defines core telemetry events for product usage and ingestion performance. It also includes a short section on engineering/agent telemetry to help us see how agent contributions perform over time.

## Product & ingestion metrics

| Event/Metric | Description | Schema fields | Source | Aggregation | Target/Alert |
|--------------|-------------|---------------|--------|-------------|--------------|
| **ParseDuration** | Time to parse a single device log bundle | `Hostname` (string), `Site` (string), `StartTime` (datetime), `DurationSeconds` (float) | Parser pipeline | p95 & max per day | p95 ≤ 3 s; alert if max > 10 s |
| **RowsWritten** | Records inserted/updated for a host ingestion | `Hostname`, `Site`, `RunDate`, `Rows` (int), `DeletedRows` (int) | Persistence layer | Sum per site per day | Monitor for outliers |
| **SkippedDuplicate** | Hosts skipped due to unchanged hash | `Site`, `HostCount` (int), `Date` | Ingestion scheduler | Daily total | Expect high skip rate (>50%) after incremental updates |
| **DatabaseWriteLatency** | Time waiting for DB locks/commit | `Site`, `StartTime`, `LatencyMs` (int) | Persistence | Average & p95 | p95 ≤ 200 ms; alert if > 500 ms |
| **DiffUsageRate** | Sessions where diff explorer was opened | `SessionId`, `UserId` (pseudonym), `UsedDiff` (bool) | UI | Rolling weekly ratio | ≥ 70% in pilot |
| **DriftDetectionTime** | Time between change and detection | `Hostname`, `ChangeDetectedAt`, `ChangedField`, `DurationMinutes` | Diff/anomaly engine | p95 per change type | −40% vs. baseline |

## Engineering / agent metrics (optional)

| Event/Metric | Description | Schema fields | Source | Aggregation | Target |
|--------------|-------------|---------------|--------|-------------|--------|
| **AgentTestPassRate** | Fraction of agent sessions with passing tests | `SessionId`, `Date`, `Passed` (bool) | CI/logs | Weekly ratio | ≥ 95% |
| **AgentChangeSize** | Lines changed per session | `SessionId`, `Files`, `Added`, `Removed` | VCS logs | Weekly p50/p95 | Keep p95 small |
| **AgentRevertRate** | Sessions that required rollback | `SessionId`, `Reason` | VCS/PRs | Weekly count | Near zero |

**Implementation notes:** Emit telemetry locally to `Logs/IngestionMetrics/<date>.json`. Engineering metrics can be derived from CI logs and PR metadata; do not include personal data.
