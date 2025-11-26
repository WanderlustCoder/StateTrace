# Dispatcher / PortBatch gap correlation

> Generated 2025-11-13 15:17:41 -07:00

## Queue summaries

- Summary file: `C:\Users\Werem\OneDrive\Documents\StateTrace\Logs\IngestionMetrics\QueueDelaySummary-20251113-114756.json`
  - Source telemetry: `C:\Users\Werem\OneDrive\Documents\StateTrace\Logs\IngestionMetrics\2025-11-13.json`
  - Samples: 3
  - QueueBuildDelay p95/p99: 24.8703 ms / 25.26126 ms
  - QueueBuildDuration p95/p99: 26.0404 ms / 26.58488 ms
  - Thresholds (p95/p99): 120 ms / 200 ms

## Idle gaps >= 60 seconds

| Start (UTC) | End (UTC) | Gap seconds | Gap minutes | Start host | End host |
|---|---|---|---|---|---|
| 11/13/2025 18:33:22 | 11/13/2025 21:44:28 | 11465.708 | 191.095 | WLLS-A07-AS-07 | BOYO-A05-AS-02 |
| 11/13/2025 18:26:14 | 11/13/2025 18:31:41 | 327.798 | 5.463 | WLLS-A07-AS-07 | BOYO-A05-AS-02 |
| 11/13/2025 18:14:52 | 11/13/2025 18:20:15 | 322.328 | 5.372 | WLLS-A07-AS-07 | BOYO-A05-AS-02 |
| 11/13/2025 18:21:00 | 11/13/2025 18:25:27 | 267.118 | 4.452 | WLLS-A07-AS-07 | BOYO-A05-AS-02 |

> Largest gap: 11465.708 seconds (191.095 minutes) from WLLS-A07-AS-07 (11/13/2025 18:33:22) to BOYO-A05-AS-02 (11/13/2025 21:44:28).

