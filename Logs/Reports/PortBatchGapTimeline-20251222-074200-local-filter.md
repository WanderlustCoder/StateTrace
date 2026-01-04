# PortBatch gap timeline

> Metrics: `C:\Users\Werem\Projects\StateTrace\Logs\IngestionMetrics\2025-12-22.json`
> Filter (UTC): 2025-12-22T14:42:00.0000000Z -> 2025-12-22T14:44:00.0000000Z
> Generated 2025-12-22 20:48:35 -07:00
> Gap threshold: 2 seconds

## Gap 1 - WLLS-A01-AS-21 -> BOYO-A05-AS-02 (3.244 s)

| Seq | Timestamp (UTC) | Delta seconds | Host | Site | Notes |
|---|---|---|---|---|---|
| 0 | 2025-12-22 14:42:17Z |  | WLLS-A01-AS-21 | WLLS | Gap starts after this batch (delta=3.244s) |
|  |  | **3.244 s idle** |  |  |  |
| 1 | 2025-12-22 14:42:21Z | 3.244 | BOYO-A05-AS-02 | BOYO | First batch after gap |
| 2 | 2025-12-22 14:42:23Z | 2.921 | WLLS-A01-AS-01 | WLLS |  |

## Gap 2 - BOYO-A05-AS-02 -> WLLS-A01-AS-01 (2.921 s)

| Seq | Timestamp (UTC) | Delta seconds | Host | Site | Notes |
|---|---|---|---|---|---|
| 0 | 2025-12-22 14:42:17Z |  | WLLS-A01-AS-21 | WLLS |  |
| 1 | 2025-12-22 14:42:21Z | 3.244 | BOYO-A05-AS-02 | BOYO | Gap starts after this batch (delta=2.921s) |
|  |  | **2.921 s idle** |  |  |  |
| 2 | 2025-12-22 14:42:23Z | 2.921 | WLLS-A01-AS-01 | WLLS | First batch after gap |
| 3 | 2025-12-22 14:42:26Z | 2.667 | BOYO-A05-AS-05 | BOYO |  |

## Gap 3 - WLLS-A01-AS-01 -> BOYO-A05-AS-05 (2.667 s)

| Seq | Timestamp (UTC) | Delta seconds | Host | Site | Notes |
|---|---|---|---|---|---|
| 1 | 2025-12-22 14:42:21Z | 3.244 | BOYO-A05-AS-02 | BOYO |  |
| 2 | 2025-12-22 14:42:23Z | 2.921 | WLLS-A01-AS-01 | WLLS | Gap starts after this batch (delta=2.667s) |
|  |  | **2.667 s idle** |  |  |  |
| 3 | 2025-12-22 14:42:26Z | 2.667 | BOYO-A05-AS-05 | BOYO | First batch after gap |
| 4 | 2025-12-22 14:42:29Z | 2.461 | WLLS-A01-AS-11 | WLLS |  |

## Gap 4 - BOYO-A05-AS-05 -> WLLS-A01-AS-11 (2.461 s)

| Seq | Timestamp (UTC) | Delta seconds | Host | Site | Notes |
|---|---|---|---|---|---|
| 2 | 2025-12-22 14:42:23Z | 2.921 | WLLS-A01-AS-01 | WLLS |  |
| 3 | 2025-12-22 14:42:26Z | 2.667 | BOYO-A05-AS-05 | BOYO | Gap starts after this batch (delta=2.461s) |
|  |  | **2.461 s idle** |  |  |  |
| 4 | 2025-12-22 14:42:29Z | 2.461 | WLLS-A01-AS-11 | WLLS | First batch after gap |
| 5 | 2025-12-22 14:42:31Z | 2.18 | BOYO-A05-AS-12 | BOYO |  |

## Gap 5 - WLLS-A01-AS-11 -> BOYO-A05-AS-12 (2.18 s)

| Seq | Timestamp (UTC) | Delta seconds | Host | Site | Notes |
|---|---|---|---|---|---|
| 3 | 2025-12-22 14:42:26Z | 2.667 | BOYO-A05-AS-05 | BOYO |  |
| 4 | 2025-12-22 14:42:29Z | 2.461 | WLLS-A01-AS-11 | WLLS | Gap starts after this batch (delta=2.18s) |
|  |  | **2.18 s idle** |  |  |  |
| 5 | 2025-12-22 14:42:31Z | 2.18 | BOYO-A05-AS-12 | BOYO | First batch after gap |
| 6 | 2025-12-22 14:42:33Z | 2.438 | WLLS-A01-AS-31 | WLLS |  |

## Gap 6 - BOYO-A05-AS-12 -> WLLS-A01-AS-31 (2.438 s)

| Seq | Timestamp (UTC) | Delta seconds | Host | Site | Notes |
|---|---|---|---|---|---|
| 4 | 2025-12-22 14:42:29Z | 2.461 | WLLS-A01-AS-11 | WLLS |  |
| 5 | 2025-12-22 14:42:31Z | 2.18 | BOYO-A05-AS-12 | BOYO | Gap starts after this batch (delta=2.438s) |
|  |  | **2.438 s idle** |  |  |  |
| 6 | 2025-12-22 14:42:33Z | 2.438 | WLLS-A01-AS-31 | WLLS | First batch after gap |
| 7 | 2025-12-22 14:42:35Z | 2.234 | BOYO-A05-AS-15 | BOYO |  |

## Gap 7 - WLLS-A01-AS-31 -> BOYO-A05-AS-15 (2.234 s)

| Seq | Timestamp (UTC) | Delta seconds | Host | Site | Notes |
|---|---|---|---|---|---|
| 5 | 2025-12-22 14:42:31Z | 2.18 | BOYO-A05-AS-12 | BOYO |  |
| 6 | 2025-12-22 14:42:33Z | 2.438 | WLLS-A01-AS-31 | WLLS | Gap starts after this batch (delta=2.234s) |
|  |  | **2.234 s idle** |  |  |  |
| 7 | 2025-12-22 14:42:35Z | 2.234 | BOYO-A05-AS-15 | BOYO | First batch after gap |
| 8 | 2025-12-22 14:42:38Z | 2.48 | WLLS-A01-AS-41 | WLLS |  |

## Gap 8 - BOYO-A05-AS-15 -> WLLS-A01-AS-41 (2.48 s)

| Seq | Timestamp (UTC) | Delta seconds | Host | Site | Notes |
|---|---|---|---|---|---|
| 6 | 2025-12-22 14:42:33Z | 2.438 | WLLS-A01-AS-31 | WLLS |  |
| 7 | 2025-12-22 14:42:35Z | 2.234 | BOYO-A05-AS-15 | BOYO | Gap starts after this batch (delta=2.48s) |
|  |  | **2.48 s idle** |  |  |  |
| 8 | 2025-12-22 14:42:38Z | 2.48 | WLLS-A01-AS-41 | WLLS | First batch after gap |
| 9 | 2025-12-22 14:42:40Z | 2.267 | BOYO-A05-AS-22 | BOYO |  |

## Gap 9 - WLLS-A01-AS-41 -> BOYO-A05-AS-22 (2.267 s)

| Seq | Timestamp (UTC) | Delta seconds | Host | Site | Notes |
|---|---|---|---|---|---|
| 7 | 2025-12-22 14:42:35Z | 2.234 | BOYO-A05-AS-15 | BOYO |  |
| 8 | 2025-12-22 14:42:38Z | 2.48 | WLLS-A01-AS-41 | WLLS | Gap starts after this batch (delta=2.267s) |
|  |  | **2.267 s idle** |  |  |  |
| 9 | 2025-12-22 14:42:40Z | 2.267 | BOYO-A05-AS-22 | BOYO | First batch after gap |
| 10 | 2025-12-22 14:42:43Z | 2.472 | WLLS-A01-AS-51 | WLLS |  |

## Gap 10 - BOYO-A05-AS-22 -> WLLS-A01-AS-51 (2.472 s)

| Seq | Timestamp (UTC) | Delta seconds | Host | Site | Notes |
|---|---|---|---|---|---|
| 8 | 2025-12-22 14:42:38Z | 2.48 | WLLS-A01-AS-41 | WLLS |  |
| 9 | 2025-12-22 14:42:40Z | 2.267 | BOYO-A05-AS-22 | BOYO | Gap starts after this batch (delta=2.472s) |
|  |  | **2.472 s idle** |  |  |  |
| 10 | 2025-12-22 14:42:43Z | 2.472 | WLLS-A01-AS-51 | WLLS | First batch after gap |
| 11 | 2025-12-22 14:42:45Z | 2.197 | BOYO-A05-AS-25 | BOYO |  |

## Gap 11 - WLLS-A01-AS-51 -> BOYO-A05-AS-25 (2.197 s)

| Seq | Timestamp (UTC) | Delta seconds | Host | Site | Notes |
|---|---|---|---|---|---|
| 9 | 2025-12-22 14:42:40Z | 2.267 | BOYO-A05-AS-22 | BOYO |  |
| 10 | 2025-12-22 14:42:43Z | 2.472 | WLLS-A01-AS-51 | WLLS | Gap starts after this batch (delta=2.197s) |
|  |  | **2.197 s idle** |  |  |  |
| 11 | 2025-12-22 14:42:45Z | 2.197 | BOYO-A05-AS-25 | BOYO | First batch after gap |
| 12 | 2025-12-22 14:42:47Z | 2.476 | WLLS-A02-AS-02 | WLLS |  |

## Gap 12 - BOYO-A05-AS-25 -> WLLS-A02-AS-02 (2.476 s)

| Seq | Timestamp (UTC) | Delta seconds | Host | Site | Notes |
|---|---|---|---|---|---|
| 10 | 2025-12-22 14:42:43Z | 2.472 | WLLS-A01-AS-51 | WLLS |  |
| 11 | 2025-12-22 14:42:45Z | 2.197 | BOYO-A05-AS-25 | BOYO | Gap starts after this batch (delta=2.476s) |
|  |  | **2.476 s idle** |  |  |  |
| 12 | 2025-12-22 14:42:47Z | 2.476 | WLLS-A02-AS-02 | WLLS | First batch after gap |
| 13 | 2025-12-22 14:42:50Z | 2.228 | BOYO-A05-AS-32 | BOYO |  |

## Gap 13 - WLLS-A02-AS-02 -> BOYO-A05-AS-32 (2.228 s)

| Seq | Timestamp (UTC) | Delta seconds | Host | Site | Notes |
|---|---|---|---|---|---|
| 11 | 2025-12-22 14:42:45Z | 2.197 | BOYO-A05-AS-25 | BOYO |  |
| 12 | 2025-12-22 14:42:47Z | 2.476 | WLLS-A02-AS-02 | WLLS | Gap starts after this batch (delta=2.228s) |
|  |  | **2.228 s idle** |  |  |  |
| 13 | 2025-12-22 14:42:50Z | 2.228 | BOYO-A05-AS-32 | BOYO | First batch after gap |
| 14 | 2025-12-22 14:42:52Z | 2.5 | WLLS-A02-AS-12 | WLLS |  |

## Gap 14 - BOYO-A05-AS-32 -> WLLS-A02-AS-12 (2.5 s)

| Seq | Timestamp (UTC) | Delta seconds | Host | Site | Notes |
|---|---|---|---|---|---|
| 12 | 2025-12-22 14:42:47Z | 2.476 | WLLS-A02-AS-02 | WLLS |  |
| 13 | 2025-12-22 14:42:50Z | 2.228 | BOYO-A05-AS-32 | BOYO | Gap starts after this batch (delta=2.5s) |
|  |  | **2.5 s idle** |  |  |  |
| 14 | 2025-12-22 14:42:52Z | 2.5 | WLLS-A02-AS-12 | WLLS | First batch after gap |
| 15 | 2025-12-22 14:42:54Z | 2.199 | BOYO-A05-AS-35 | BOYO |  |

## Gap 15 - WLLS-A02-AS-12 -> BOYO-A05-AS-35 (2.199 s)

| Seq | Timestamp (UTC) | Delta seconds | Host | Site | Notes |
|---|---|---|---|---|---|
| 13 | 2025-12-22 14:42:50Z | 2.228 | BOYO-A05-AS-32 | BOYO |  |
| 14 | 2025-12-22 14:42:52Z | 2.5 | WLLS-A02-AS-12 | WLLS | Gap starts after this batch (delta=2.199s) |
|  |  | **2.199 s idle** |  |  |  |
| 15 | 2025-12-22 14:42:54Z | 2.199 | BOYO-A05-AS-35 | BOYO | First batch after gap |
| 16 | 2025-12-22 14:42:57Z | 2.458 | WLLS-A02-AS-22 | WLLS |  |

## Gap 16 - BOYO-A05-AS-35 -> WLLS-A02-AS-22 (2.458 s)

| Seq | Timestamp (UTC) | Delta seconds | Host | Site | Notes |
|---|---|---|---|---|---|
| 14 | 2025-12-22 14:42:52Z | 2.5 | WLLS-A02-AS-12 | WLLS |  |
| 15 | 2025-12-22 14:42:54Z | 2.199 | BOYO-A05-AS-35 | BOYO | Gap starts after this batch (delta=2.458s) |
|  |  | **2.458 s idle** |  |  |  |
| 16 | 2025-12-22 14:42:57Z | 2.458 | WLLS-A02-AS-22 | WLLS | First batch after gap |
| 17 | 2025-12-22 14:42:59Z | 2.21 | BOYO-A05-AS-42 | BOYO |  |

## Gap 17 - WLLS-A02-AS-22 -> BOYO-A05-AS-42 (2.21 s)

| Seq | Timestamp (UTC) | Delta seconds | Host | Site | Notes |
|---|---|---|---|---|---|
| 15 | 2025-12-22 14:42:54Z | 2.199 | BOYO-A05-AS-35 | BOYO |  |
| 16 | 2025-12-22 14:42:57Z | 2.458 | WLLS-A02-AS-22 | WLLS | Gap starts after this batch (delta=2.21s) |
|  |  | **2.21 s idle** |  |  |  |
| 17 | 2025-12-22 14:42:59Z | 2.21 | BOYO-A05-AS-42 | BOYO | First batch after gap |
| 18 | 2025-12-22 14:43:01Z | 2.466 | WLLS-A02-AS-42 | WLLS |  |

## Gap 18 - BOYO-A05-AS-42 -> WLLS-A02-AS-42 (2.466 s)

| Seq | Timestamp (UTC) | Delta seconds | Host | Site | Notes |
|---|---|---|---|---|---|
| 16 | 2025-12-22 14:42:57Z | 2.458 | WLLS-A02-AS-22 | WLLS |  |
| 17 | 2025-12-22 14:42:59Z | 2.21 | BOYO-A05-AS-42 | BOYO | Gap starts after this batch (delta=2.466s) |
|  |  | **2.466 s idle** |  |  |  |
| 18 | 2025-12-22 14:43:01Z | 2.466 | WLLS-A02-AS-42 | WLLS | First batch after gap |
| 19 | 2025-12-22 14:43:04Z | 2.259 | BOYO-A05-AS-45 | BOYO |  |

## Gap 19 - WLLS-A02-AS-42 -> BOYO-A05-AS-45 (2.259 s)

| Seq | Timestamp (UTC) | Delta seconds | Host | Site | Notes |
|---|---|---|---|---|---|
| 17 | 2025-12-22 14:42:59Z | 2.21 | BOYO-A05-AS-42 | BOYO |  |
| 18 | 2025-12-22 14:43:01Z | 2.466 | WLLS-A02-AS-42 | WLLS | Gap starts after this batch (delta=2.259s) |
|  |  | **2.259 s idle** |  |  |  |
| 19 | 2025-12-22 14:43:04Z | 2.259 | BOYO-A05-AS-45 | BOYO | First batch after gap |

