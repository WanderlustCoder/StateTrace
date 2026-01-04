# PortBatch gap timeline

> Metrics: `C:\Users\Werem\Projects\StateTrace\Logs\IngestionMetrics\Run-20251222-210344\2025-12-22.json`
> Filter (UTC): 2025-12-23T04:03:45.0000000Z -> 2025-12-23T04:04:05.0000000Z
> Generated 2025-12-22 21:08:16 -07:00
> Gap threshold: 1 seconds

## Gap 1 - WLLS-A01-AS-11 -> WLLS-A01-AS-21 (1.78 s)

| Seq | Timestamp (UTC) | Delta seconds | Host | Site | Notes |
|---|---|---|---|---|---|
| 0 | 2025-12-23 04:03:50Z |  | WLLS-A01-AS-11 | WLLS | Gap starts after this batch (delta=1.78s) |
|  |  | **1.78 s idle** |  |  |  |
| 1 | 2025-12-23 04:03:52Z | 1.78 | WLLS-A01-AS-21 | WLLS | First batch after gap |
| 2 | 2025-12-23 04:03:52Z | 0.416 | WLLS-A01-AS-31 | WLLS |  |
| 3 | 2025-12-23 04:03:53Z | 0.406 | WLLS-A01-AS-41 | WLLS |  |

