<!-- LANDMARK: ST-D-003 incremental loading sweep output -->
# PortBatch gap timeline

> Metrics: `C:\Users\Werem\Projects\StateTrace\Logs\IngestionMetrics\2026-01-01.json`
> Generated 2026-01-01 16:28:45 -07:00
> Gap threshold: 1 seconds

## Gap 1 - WLLS-A01-AS-01 -> BOYO-A05-AS-02 (2.189 s)

| Seq | Timestamp (UTC) | Delta seconds | Host | Site | Notes |
|---|---|---|---|---|---|
| 0 | 2026-01-01 23:24:28Z |  | WLLS-A01-AS-01 | WLLS |  |
| 1 | 2026-01-01 23:24:28Z | 0 | WLLS-A01-AS-01 | WLLS | Gap starts after this batch (delta=2.189s) |
|  |  | **2.189 s idle** |  |  |  |
| 2 | 2026-01-01 23:24:31Z | 2.189 | BOYO-A05-AS-02 | BOYO | First batch after gap |
| 3 | 2026-01-01 23:24:31Z | 0 | BOYO-A05-AS-02 | BOYO |  |
| 4 | 2026-01-01 23:24:33Z | 2.452 | WLLS-A01-AS-11 | WLLS |  |
| 5 | 2026-01-01 23:24:33Z | 0 | WLLS-A01-AS-11 | WLLS |  |
| 6 | 2026-01-01 23:24:35Z | 2.18 | BOYO-A05-AS-05 | BOYO |  |

## Gap 2 - BOYO-A05-AS-02 -> WLLS-A01-AS-11 (2.452 s)

| Seq | Timestamp (UTC) | Delta seconds | Host | Site | Notes |
|---|---|---|---|---|---|
| 0 | 2026-01-01 23:24:28Z |  | WLLS-A01-AS-01 | WLLS |  |
| 1 | 2026-01-01 23:24:28Z | 0 | WLLS-A01-AS-01 | WLLS |  |
| 2 | 2026-01-01 23:24:31Z | 2.189 | BOYO-A05-AS-02 | BOYO |  |
| 3 | 2026-01-01 23:24:31Z | 0 | BOYO-A05-AS-02 | BOYO | Gap starts after this batch (delta=2.452s) |
|  |  | **2.452 s idle** |  |  |  |
| 4 | 2026-01-01 23:24:33Z | 2.452 | WLLS-A01-AS-11 | WLLS | First batch after gap |
| 5 | 2026-01-01 23:24:33Z | 0 | WLLS-A01-AS-11 | WLLS |  |
| 6 | 2026-01-01 23:24:35Z | 2.18 | BOYO-A05-AS-05 | BOYO |  |
| 7 | 2026-01-01 23:24:35Z | 0 | BOYO-A05-AS-05 | BOYO |  |
| 8 | 2026-01-01 23:24:38Z | 2.443 | WLLS-A01-AS-21 | WLLS |  |

## Gap 3 - WLLS-A01-AS-11 -> BOYO-A05-AS-05 (2.18 s)

| Seq | Timestamp (UTC) | Delta seconds | Host | Site | Notes |
|---|---|---|---|---|---|
| 1 | 2026-01-01 23:24:28Z | 0 | WLLS-A01-AS-01 | WLLS |  |
| 2 | 2026-01-01 23:24:31Z | 2.189 | BOYO-A05-AS-02 | BOYO |  |
| 3 | 2026-01-01 23:24:31Z | 0 | BOYO-A05-AS-02 | BOYO |  |
| 4 | 2026-01-01 23:24:33Z | 2.452 | WLLS-A01-AS-11 | WLLS |  |
| 5 | 2026-01-01 23:24:33Z | 0 | WLLS-A01-AS-11 | WLLS | Gap starts after this batch (delta=2.18s) |
|  |  | **2.18 s idle** |  |  |  |
| 6 | 2026-01-01 23:24:35Z | 2.18 | BOYO-A05-AS-05 | BOYO | First batch after gap |
| 7 | 2026-01-01 23:24:35Z | 0 | BOYO-A05-AS-05 | BOYO |  |
| 8 | 2026-01-01 23:24:38Z | 2.443 | WLLS-A01-AS-21 | WLLS |  |
| 9 | 2026-01-01 23:24:38Z | 0 | WLLS-A01-AS-21 | WLLS |  |
| 10 | 2026-01-01 23:24:40Z | 2.159 | BOYO-A05-AS-12 | BOYO |  |

## Gap 4 - BOYO-A05-AS-05 -> WLLS-A01-AS-21 (2.443 s)

| Seq | Timestamp (UTC) | Delta seconds | Host | Site | Notes |
|---|---|---|---|---|---|
| 3 | 2026-01-01 23:24:31Z | 0 | BOYO-A05-AS-02 | BOYO |  |
| 4 | 2026-01-01 23:24:33Z | 2.452 | WLLS-A01-AS-11 | WLLS |  |
| 5 | 2026-01-01 23:24:33Z | 0 | WLLS-A01-AS-11 | WLLS |  |
| 6 | 2026-01-01 23:24:35Z | 2.18 | BOYO-A05-AS-05 | BOYO |  |
| 7 | 2026-01-01 23:24:35Z | 0 | BOYO-A05-AS-05 | BOYO | Gap starts after this batch (delta=2.443s) |
|  |  | **2.443 s idle** |  |  |  |
| 8 | 2026-01-01 23:24:38Z | 2.443 | WLLS-A01-AS-21 | WLLS | First batch after gap |
| 9 | 2026-01-01 23:24:38Z | 0 | WLLS-A01-AS-21 | WLLS |  |
| 10 | 2026-01-01 23:24:40Z | 2.159 | BOYO-A05-AS-12 | BOYO |  |
| 11 | 2026-01-01 23:24:40Z | 0 | BOYO-A05-AS-12 | BOYO |  |
| 12 | 2026-01-01 23:24:42Z | 2.429 | WLLS-A01-AS-31 | WLLS |  |

## Gap 5 - WLLS-A01-AS-21 -> BOYO-A05-AS-12 (2.159 s)

| Seq | Timestamp (UTC) | Delta seconds | Host | Site | Notes |
|---|---|---|---|---|---|
| 5 | 2026-01-01 23:24:33Z | 0 | WLLS-A01-AS-11 | WLLS |  |
| 6 | 2026-01-01 23:24:35Z | 2.18 | BOYO-A05-AS-05 | BOYO |  |
| 7 | 2026-01-01 23:24:35Z | 0 | BOYO-A05-AS-05 | BOYO |  |
| 8 | 2026-01-01 23:24:38Z | 2.443 | WLLS-A01-AS-21 | WLLS |  |
| 9 | 2026-01-01 23:24:38Z | 0 | WLLS-A01-AS-21 | WLLS | Gap starts after this batch (delta=2.159s) |
|  |  | **2.159 s idle** |  |  |  |
| 10 | 2026-01-01 23:24:40Z | 2.159 | BOYO-A05-AS-12 | BOYO | First batch after gap |
| 11 | 2026-01-01 23:24:40Z | 0 | BOYO-A05-AS-12 | BOYO |  |
| 12 | 2026-01-01 23:24:42Z | 2.429 | WLLS-A01-AS-31 | WLLS |  |
| 13 | 2026-01-01 23:24:42Z | 0 | WLLS-A01-AS-31 | WLLS |  |
| 14 | 2026-01-01 23:24:44Z | 2.198 | BOYO-A05-AS-15 | BOYO |  |

## Gap 6 - BOYO-A05-AS-12 -> WLLS-A01-AS-31 (2.429 s)

| Seq | Timestamp (UTC) | Delta seconds | Host | Site | Notes |
|---|---|---|---|---|---|
| 7 | 2026-01-01 23:24:35Z | 0 | BOYO-A05-AS-05 | BOYO |  |
| 8 | 2026-01-01 23:24:38Z | 2.443 | WLLS-A01-AS-21 | WLLS |  |
| 9 | 2026-01-01 23:24:38Z | 0 | WLLS-A01-AS-21 | WLLS |  |
| 10 | 2026-01-01 23:24:40Z | 2.159 | BOYO-A05-AS-12 | BOYO |  |
| 11 | 2026-01-01 23:24:40Z | 0 | BOYO-A05-AS-12 | BOYO | Gap starts after this batch (delta=2.429s) |
|  |  | **2.429 s idle** |  |  |  |
| 12 | 2026-01-01 23:24:42Z | 2.429 | WLLS-A01-AS-31 | WLLS | First batch after gap |
| 13 | 2026-01-01 23:24:42Z | 0 | WLLS-A01-AS-31 | WLLS |  |
| 14 | 2026-01-01 23:24:44Z | 2.198 | BOYO-A05-AS-15 | BOYO |  |
| 15 | 2026-01-01 23:24:44Z | 0 | BOYO-A05-AS-15 | BOYO |  |
| 16 | 2026-01-01 23:24:47Z | 2.533 | WLLS-A01-AS-41 | WLLS |  |

## Gap 7 - WLLS-A01-AS-31 -> BOYO-A05-AS-15 (2.198 s)

| Seq | Timestamp (UTC) | Delta seconds | Host | Site | Notes |
|---|---|---|---|---|---|
| 9 | 2026-01-01 23:24:38Z | 0 | WLLS-A01-AS-21 | WLLS |  |
| 10 | 2026-01-01 23:24:40Z | 2.159 | BOYO-A05-AS-12 | BOYO |  |
| 11 | 2026-01-01 23:24:40Z | 0 | BOYO-A05-AS-12 | BOYO |  |
| 12 | 2026-01-01 23:24:42Z | 2.429 | WLLS-A01-AS-31 | WLLS |  |
| 13 | 2026-01-01 23:24:42Z | 0 | WLLS-A01-AS-31 | WLLS | Gap starts after this batch (delta=2.198s) |
|  |  | **2.198 s idle** |  |  |  |
| 14 | 2026-01-01 23:24:44Z | 2.198 | BOYO-A05-AS-15 | BOYO | First batch after gap |
| 15 | 2026-01-01 23:24:44Z | 0 | BOYO-A05-AS-15 | BOYO |  |
| 16 | 2026-01-01 23:24:47Z | 2.533 | WLLS-A01-AS-41 | WLLS |  |
| 17 | 2026-01-01 23:24:47Z | 0 | WLLS-A01-AS-41 | WLLS |  |
| 18 | 2026-01-01 23:24:49Z | 2.22 | BOYO-A05-AS-22 | BOYO |  |

## Gap 8 - BOYO-A05-AS-15 -> WLLS-A01-AS-41 (2.533 s)

| Seq | Timestamp (UTC) | Delta seconds | Host | Site | Notes |
|---|---|---|---|---|---|
| 11 | 2026-01-01 23:24:40Z | 0 | BOYO-A05-AS-12 | BOYO |  |
| 12 | 2026-01-01 23:24:42Z | 2.429 | WLLS-A01-AS-31 | WLLS |  |
| 13 | 2026-01-01 23:24:42Z | 0 | WLLS-A01-AS-31 | WLLS |  |
| 14 | 2026-01-01 23:24:44Z | 2.198 | BOYO-A05-AS-15 | BOYO |  |
| 15 | 2026-01-01 23:24:44Z | 0 | BOYO-A05-AS-15 | BOYO | Gap starts after this batch (delta=2.533s) |
|  |  | **2.533 s idle** |  |  |  |
| 16 | 2026-01-01 23:24:47Z | 2.533 | WLLS-A01-AS-41 | WLLS | First batch after gap |
| 17 | 2026-01-01 23:24:47Z | 0 | WLLS-A01-AS-41 | WLLS |  |
| 18 | 2026-01-01 23:24:49Z | 2.22 | BOYO-A05-AS-22 | BOYO |  |
| 19 | 2026-01-01 23:24:49Z | 0 | BOYO-A05-AS-22 | BOYO |  |
| 20 | 2026-01-01 23:24:52Z | 2.43 | WLLS-A01-AS-51 | WLLS |  |

## Gap 9 - WLLS-A01-AS-41 -> BOYO-A05-AS-22 (2.22 s)

| Seq | Timestamp (UTC) | Delta seconds | Host | Site | Notes |
|---|---|---|---|---|---|
| 13 | 2026-01-01 23:24:42Z | 0 | WLLS-A01-AS-31 | WLLS |  |
| 14 | 2026-01-01 23:24:44Z | 2.198 | BOYO-A05-AS-15 | BOYO |  |
| 15 | 2026-01-01 23:24:44Z | 0 | BOYO-A05-AS-15 | BOYO |  |
| 16 | 2026-01-01 23:24:47Z | 2.533 | WLLS-A01-AS-41 | WLLS |  |
| 17 | 2026-01-01 23:24:47Z | 0 | WLLS-A01-AS-41 | WLLS | Gap starts after this batch (delta=2.22s) |
|  |  | **2.22 s idle** |  |  |  |
| 18 | 2026-01-01 23:24:49Z | 2.22 | BOYO-A05-AS-22 | BOYO | First batch after gap |
| 19 | 2026-01-01 23:24:49Z | 0 | BOYO-A05-AS-22 | BOYO |  |
| 20 | 2026-01-01 23:24:52Z | 2.43 | WLLS-A01-AS-51 | WLLS |  |
| 21 | 2026-01-01 23:24:52Z | 0 | WLLS-A01-AS-51 | WLLS |  |
| 22 | 2026-01-01 23:24:54Z | 2.248 | BOYO-A05-AS-25 | BOYO |  |

## Gap 10 - BOYO-A05-AS-22 -> WLLS-A01-AS-51 (2.43 s)

| Seq | Timestamp (UTC) | Delta seconds | Host | Site | Notes |
|---|---|---|---|---|---|
| 15 | 2026-01-01 23:24:44Z | 0 | BOYO-A05-AS-15 | BOYO |  |
| 16 | 2026-01-01 23:24:47Z | 2.533 | WLLS-A01-AS-41 | WLLS |  |
| 17 | 2026-01-01 23:24:47Z | 0 | WLLS-A01-AS-41 | WLLS |  |
| 18 | 2026-01-01 23:24:49Z | 2.22 | BOYO-A05-AS-22 | BOYO |  |
| 19 | 2026-01-01 23:24:49Z | 0 | BOYO-A05-AS-22 | BOYO | Gap starts after this batch (delta=2.43s) |
|  |  | **2.43 s idle** |  |  |  |
| 20 | 2026-01-01 23:24:52Z | 2.43 | WLLS-A01-AS-51 | WLLS | First batch after gap |
| 21 | 2026-01-01 23:24:52Z | 0 | WLLS-A01-AS-51 | WLLS |  |
| 22 | 2026-01-01 23:24:54Z | 2.248 | BOYO-A05-AS-25 | BOYO |  |
| 23 | 2026-01-01 23:24:54Z | 0 | BOYO-A05-AS-25 | BOYO |  |

## Gap 11 - WLLS-A01-AS-51 -> BOYO-A05-AS-25 (2.248 s)

| Seq | Timestamp (UTC) | Delta seconds | Host | Site | Notes |
|---|---|---|---|---|---|
| 17 | 2026-01-01 23:24:47Z | 0 | WLLS-A01-AS-41 | WLLS |  |
| 18 | 2026-01-01 23:24:49Z | 2.22 | BOYO-A05-AS-22 | BOYO |  |
| 19 | 2026-01-01 23:24:49Z | 0 | BOYO-A05-AS-22 | BOYO |  |
| 20 | 2026-01-01 23:24:52Z | 2.43 | WLLS-A01-AS-51 | WLLS |  |
| 21 | 2026-01-01 23:24:52Z | 0 | WLLS-A01-AS-51 | WLLS | Gap starts after this batch (delta=2.248s) |
|  |  | **2.248 s idle** |  |  |  |
| 22 | 2026-01-01 23:24:54Z | 2.248 | BOYO-A05-AS-25 | BOYO | First batch after gap |
| 23 | 2026-01-01 23:24:54Z | 0 | BOYO-A05-AS-25 | BOYO |  |

