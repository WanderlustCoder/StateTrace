# Dispatcher / PortBatch gap correlation

> Generated 2025-11-14 08:19:26 -07:00

## Queue summaries

- Summary file: `C:\Users\Werem\OneDrive\Documents\StateTrace\Logs\IngestionMetrics\QueueDelaySummary-20251114.json`
  - Source telemetry: `C:\Users\Werem\OneDrive\Documents\StateTrace\Logs\IngestionMetrics\2025-11-14.json`
  - Samples: 128
  - QueueBuildDelay p95/p99: 20.01685 ms / 20.7624 ms
  - QueueBuildDuration p95/p99: 26.0284 ms / 26.61448 ms
  - Thresholds (p95/p99): 120 ms / 200 ms

## Idle gaps >= 60 seconds

| Start (UTC) | End (UTC) | Gap seconds | Gap minutes | Start host | End host |
|---|---|---|---|---|---|
| 11/14/2025 14:42:36 | 11/14/2025 14:52:39 | 602.497 | 10.042 | BOYO-A05-AS-55 | BOYO-A05-AS-02 |
| 11/14/2025 15:04:53 | 11/14/2025 15:13:25 | 512.754 | 8.546 | WLLS-A07-AS-07 | BOYO-A05-AS-02 |
| 11/14/2025 14:56:53 | 11/14/2025 15:03:25 | 391.408 | 6.523 | WLLS-A07-AS-07 | WLLS-A01-AS-01 |
| 11/14/2025 14:54:07 | 11/14/2025 14:55:26 | 78.812 | 1.314 | WLLS-A07-AS-07 | WLLS-A01-AS-01 |

> Largest gap: 602.497 seconds (10.042 minutes) from BOYO-A05-AS-55 (11/14/2025 14:42:36) to BOYO-A05-AS-02 (11/14/2025 14:52:39).

