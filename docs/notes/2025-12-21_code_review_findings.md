# Code review findings (2025-12-21)

Scope: static review of Modules/ and Tools/ for reliability, safety, and maintainability. Fixes applied starting 2025-12-21; see status updates.

Status updates:
- 2025-12-21: Addressed findings 18, 78, 79, 80, 87 (rollback warning, pack deletion guards, ParserWorker strict mode).
- 2025-12-21: Addressed findings 55-63 (interface cache synchronization, AllInterfaces snapshot merging, ViewState/FilterState/Insights locking).

## Findings (100)
1. [Medium] Silent catch hides failures to initialize debug telemetry; misconfigurations go unnoticed. `Modules/DatabaseModule.psm1:8`
2. [Medium] Failure to kill timed-out 32-bit helper is swallowed; orphaned processes possible. `Modules/DatabaseModule.psm1:97`
3. [Medium] Dispose failure for ADODB connection is ignored; leaks are silent. `Modules/DatabaseModule.psm1:151`
4. [High] Schema creation failure for DeviceSummary is suppressed; DB can be missing tables without warning. `Modules/DatabaseModule.psm1:467`
5. [High] Schema creation failure for DeviceHistory is suppressed; history data may be missing. `Modules/DatabaseModule.psm1:471`
6. [Medium] Index creation failures are ignored; queries can remain slow without visibility. `Modules/DatabaseModule.psm1:485`
7. [Medium] Database module import errors are swallowed, leading to silent null results. `Modules/DeviceDetailsModule.psm1:19`
8. [Medium] Summary query failures are swallowed, causing empty detail views without diagnostics. `Modules/DeviceDetailsModule.psm1:135`
9. [Medium] Interface detail query failures are swallowed, masking data access issues. `Modules/DeviceDetailsModule.psm1:212`
10. [Medium] ViewStateService import failures are ignored; downstream UI state can be broken silently. `Modules/DeviceInsightsModule.psm1:3`
11. [Medium] PortNormalization import failures are ignored; port sorting can regress silently. `Modules/DeviceInsightsModule.psm1:94`
12. [Low] Sort exceptions are swallowed; search results may be unsorted with no indication. `Modules/DeviceInsightsModule.psm1:191`
13. [Medium] Port row defaulting failures are ignored; rows can be missing required fields without signal. `Modules/DeviceInsightsModule.psm1:458`
14. [Medium] Background thread failure to update AllInterfaces is ignored; view can show stale data. `Modules/DeviceInsightsModule.psm1:1542`
15. [Medium] Connection close failures are ignored; COM connection leaks are possible. `Modules/DeviceLogParserModule.psm1:420`
16. [Medium] CreateDirectory failures are swallowed; history/telemetry writes may silently fail. `Modules/DeviceLogParserModule.psm1:947`
17. [Medium] Mutex release failures are ignored; stale mutexes can block later runs. `Modules/DeviceLogParserModule.psm1:1005`
18. [High] Transaction rollback failures are ignored; database state may be inconsistent. `Modules/DeviceLogParserModule.psm1:1986`
19. [Low] UI SelectedIndex set failures are ignored; filter state can desync silently. `Modules/FilterStateModule.psm1:108`
20. [Medium] DeviceLocationEntries update failures are ignored; filters may rely on stale data. `Modules/FilterStateModule.psm1:330`
21. [Low] Diagnostics emission failures are swallowed; troubleshooting loses signals. `Modules/FilterStateModule.psm1:383`
22. [Low] Stopwatch stop failure ignored; timing metrics can be wrong without warning. `Modules/FilterStateModule.psm1:686`
23. [Medium] Access connection close errors are ignored; connection leaks can build up. `Modules/DeviceRepository.Access.psm1:234`
24. [Medium] Recordset close errors are ignored; recordset leaks can build up. `Modules/DeviceRepository.Access.psm1:285`
25. [Medium] Failure to publish cache store to AppDomain is ignored; shared cache may not propagate. `Modules/DeviceRepository.Cache.psm1:338`
26. [Low] UI automation launch errors are swallowed; failures are silent. `Tools/AutoCapture-PlanHUI.ps1:50`
27. [Low] Quickstart JSON parse errors are suppressed; screenshots may be produced with empty metadata. `Tools/Capture-PlanHScreenshots.ps1:39`
28. [Medium] Port stream status query failures are swallowed; checklist may pass falsely. `Tools/Invoke-InterfacesViewChecklist.ps1:271`
29. [Low] UI window close failures are ignored; smoke tests can leak app instances. `Tools/Invoke-SearchAlertsSmokeTest.ps1:391`
30. [Medium] Interface cache warmup failures are ignored; pipeline warm cache state may be invalid. `Tools/Invoke-StateTracePipeline.ps1:258`
31. [Low] Apartment state probe errors are ignored; STA requirements may fail silently. `Tools/Invoke-StateTracePipeline.ps1:526`
32. [Medium] Warm-run cache hydration failures are swallowed; warm telemetry can be misleading. `Tools/Invoke-WarmRunTelemetry.ps1:2430`
33. [Low] Log directory normalization errors are ignored; diagnostics output path may be invalid. `Tools/Invoke-StateTraceUiDiagnostics.ps1:25`
34. [Medium] ConvertFrom-Json -Depth 5 used; PS5 compatibility and deep parse cost risk. `Tools/Analyze-DispatcherGaps.ps1:44`
35. [Medium] ConvertFrom-Json -Depth 5 used for reports; same compatibility risk. `Tools/Analyze-DispatcherGaps.ps1:58`
36. [Medium] ConvertFrom-Json -Depth 6 used; PS5 compatibility/perf risk. `Tools/Analyze-PortBatchReadyTelemetry.ps1:202`
37. [Medium] ConvertFrom-Json -Depth 6 used; PS5 compatibility/perf risk. `Tools/Analyze-PortBatchGapBreakdown.ps1:42`
38. [Medium] ConvertFrom-Json -Depth 5 used; PS5 compatibility risk. `Tools/Compare-SchedulerAndPortDiversity.ps1:48`
39. [Medium] ConvertFrom-Json -Depth 5 used; PS5 compatibility risk. `Tools/Compare-SchedulerAndPortDiversity.ps1:53`
40. [Medium] ConvertFrom-Json -Depth 6 used; PS5 compatibility risk. `Tools/Show-TelemetryBundleSummary.ps1:70`
41. [Medium] ConvertFrom-Json -Depth 10 used; PS5 compatibility/perf risk. `Tools/Test-TelemetryBundleReadiness.ps1:57`
42. [Medium] ConvertFrom-Json -Depth 10 used; PS5 compatibility/perf risk. `Tools/Test-TelemetryBundleReadiness.ps1:98`
43. [Medium] Reads entire telemetry JSON into memory; large files can spike memory. `Tools/Analyze-FreshnessTelemetry.ps1:40`
44. [Medium] Reads full sweep report at once; large files can exhaust memory. `Tools/Analyze-DispatchHarnessSweep.ps1:41`
45. [Medium] Reads full dispatcher gaps metrics; no streaming for large logs. `Tools/Analyze-DispatcherGaps.ps1:43`
46. [Low] Reads full user action telemetry without error handling; parse failures are not isolated. `Tools/Analyze-UserActionTelemetry.ps1:41`
47. [Medium] Reads entire warm-run telemetry into memory; large runs can spike memory. `Tools/Analyze-WarmRunDiffHotspots.ps1:19`
48. [Medium] Reads full ingestion history into memory; large history files can spike memory. `Tools/Invoke-SharedCacheWarmup.ps1:92`
49. [Medium] Reads full warm telemetry for verification; no streaming or size guard. `Tools/Invoke-StateTraceVerification.ps1:392`
50. [Medium] Reads entire telemetry bundle summary into memory; large bundles can spike memory. `Tools/Show-TelemetryBundleSummary.ps1:69`
51. [Medium] Reads full PortBatch report before parse; streaming would be safer. `Tools/Update-PortBatchHistory.ps1:91`
52. [Medium] Reads full InterfaceSync report before parse; streaming would be safer. `Tools/Update-InterfaceSyncHistory.ps1:83`
53. [Medium] Reads full device history file into memory; large logs can spike memory. `Modules/DeviceLogParserModule.psm1:986`
54. [Medium] Reads full metrics context file into memory; streaming would be safer. `Modules/ParserRunspaceModule.psm1:512`
55. [High] SiteInterfaceCache uses a plain hashtable with no locking; concurrent runspaces can race. `Modules/DeviceRepositoryModule.psm1:322`
56. [High] Global DeviceInterfaceCache is a plain hashtable; async UI updates can race. `Modules/DeviceRepositoryModule.psm1:1721`
57. [High] Global AllInterfaces list is shared with no synchronization; concurrent reads/writes can throw. `Modules/DeviceRepositoryModule.psm1:1725`
58. [High] DeviceInterfaceCache writes are unsynchronized; background refresh can race UI. `Modules/DeviceRepositoryModule.psm1:4922`
59. [High] AllInterfaces list is appended without locking; enumeration can fail under concurrency. `Modules/DeviceRepositoryModule.psm1:4933`
60. [High] Background worker assigns AllInterfaces with no lock; UI could read partial state. `Modules/DeviceInsightsModule.psm1:1542`
61. [High] Background worker resets DeviceInterfaceCache with no lock; UI can see transient nulls. `Modules/DeviceInsightsModule.psm1:941`
62. [Medium] Reads DeviceInterfaceCache without lock while writer can mutate; inconsistent snapshots possible. `Modules/FilterStateModule.psm1:672`
63. [High] SiteInterfaceCache writes are unsynchronized; concurrent site loads can corrupt state. `Modules/DeviceRepositoryModule.psm1:6254`
64. [Medium] SiteInterfaceCache read/contains checks are unsynchronized; race with writers. `Modules/DeviceRepositoryModule.psm1:5398`
65. [Low] SharedSiteInterfaceCacheEvents grows without bound; long sessions can leak memory. `Modules/DeviceRepository.Cache.psm1:153`
66. [Low] SharedSiteInterfaceCacheClearEvents grows without bound; long sessions can leak memory. `Modules/DeviceRepository.Cache.psm1:182`
67. [Low] Global cache event list initialized but never trimmed; no retention policy. `Modules/DeviceRepository.Cache.psm1:189`
68. [Low] Global cache clear event list initialized but never trimmed; no retention policy. `Modules/DeviceRepository.Cache.psm1:192`
69. [Low] Additional appends to SharedSiteInterfaceCacheEvents with no cap; memory growth risk. `Modules/DeviceRepository.Cache.psm1:764`
70. [Medium] Import-Module with -Global and -ErrorAction SilentlyContinue hides missing modules. `Modules/DeviceCatalogModule.psm1:27`
71. [Medium] Fallback import also uses -Global and SilentlyContinue; silent failure likely. `Modules/DeviceCatalogModule.psm1:29`
72. [Medium] DeviceDetails module import failures are hidden; detail views degrade silently. `Modules/DeviceDetailsModule.psm1:15`
73. [Medium] DatabaseModule import failures are hidden; Access helpers may be unavailable silently. `Modules/DeviceRepository.Access.psm1:168`
74. [Medium] InterfaceModule imports PortNormalization with SilentlyContinue; port sort can be wrong with no warning. `Modules/InterfaceModule.psm1:160`
75. [Medium] TemplatesModule import errors are hidden; vendor templates may be missing silently. `Modules/DeviceLogParserModule.psm1:699`
76. [Medium] SpanView imports DeviceRepositoryModule with SilentlyContinue; span view can run without data sources. `Modules/SpanViewModule.psm1:123`
77. [Medium] Removes archive folders with -Recurse -Force without root validation; bad path could delete unintended data. `Modules/DeviceLogParserModule.psm1:871`
78. [High] Removes build directory recursively; no guard against mis-resolved buildDir. `Tools/Pack-StateTrace.ps1:31`
79. [Medium] Removes Logs under buildDir recursively; risk if buildDir points to wrong root. `Tools/Pack-StateTrace.ps1:65`
80. [Medium] Removes Data\\Backups under buildDir recursively; risk if buildDir points to wrong root. `Tools/Pack-StateTrace.ps1:66`
81. [Medium] Removes extracted logs without verifying ExtractedPath; misconfiguration could delete wrong files. `Modules/LogIngestionModule.psm1:157`
82. [Medium] Test ADODB connection creation can fail and close errors are swallowed; COM cleanup is not guaranteed on failure. `Modules/DeviceLogParserModule.psm1:523`
83. [Medium] Cached ADODB connections have no explicit shutdown hook; long-lived sessions can leak COM resources. `Modules/DeviceLogParserModule.psm1:564`
84. [Medium] New-AdodbTextCommand returns COM object with no enforced disposal contract; caller leaks are likely. `Modules/ParserPersistenceModule.psm1:678`
85. [Medium] New-AdodbInterfaceSeedRecordset returns COM recordset with no enforced disposal contract; leak risk on caller error. `Modules/ParserPersistenceModule.psm1:703`
86. [Medium] ADODB.Connection created for schema management relies on Close in error paths; close failures are swallowed and can leak COM resources. `Modules/DatabaseModule.psm1:427`
87. [Medium] ParserWorker lacks Set-StrictMode; undeclared variables can slip through. `Modules/ParserWorker.psm1:1`
88. [Low] Scheduler loop uses fixed Start-Sleep polling; wastes CPU and lacks cancellation. `Modules/ParserRunspaceModule.psm1:1062`
89. [Low] Exclusive lock backoff uses Start-Sleep on caller thread; can block UI flows. `Modules/DeviceRepositoryModule.psm1:2489`
90. [Low] UI automation waits with fixed sleeps during window discovery; timing flakiness likely. `Tools/AutoCapture-PlanHUI.ps1:52`
91. [Low] UI automation uses fixed startup delay instead of readiness signal; can be too short/long. `Tools/AutoCapture-PlanHUI.ps1:101`
92. [Low] UI automation waits fixed 2 seconds for Help window; timing flakiness likely. `Tools/AutoCapture-PlanHUI.ps1:114`
93. [Low] Interface checklist polls with Start-Sleep and no hard timeout; can hang on failures. `Tools/Invoke-InterfacesViewChecklist.ps1:276`
94. [Low] Dispatch harness uses Start-Sleep polling instead of event-driven completion; flaky timing. `Tools/Invoke-InterfaceDispatchHarness.ps1:111`
95. [Low] Warm-run telemetry polling uses Start-Sleep without a max wait; hangs are possible. `Tools/Invoke-WarmRunTelemetry.ps1:920`
96. [Low] Interfaces view smoke test uses fixed sleep; validation timing is brittle. `Tools/Invoke-InterfacesViewSmokeTest.ps1:126`
97. [Low] Plan H simulation uses fixed sleep for sequencing; not event-driven. `Tools/Simulate-PlanHUIRun.ps1:49`
98. [Low] Plan H simulation uses fixed sleep for sequencing; not event-driven. `Tools/Simulate-PlanHUIRun.ps1:68`
99. [Low] MessageBox on export errors blocks headless or automated runs. `Modules/ViewCompositionModule.psm1:94`
100. [Low] MessageBox on export failure blocks headless or automated runs. `Modules/ViewCompositionModule.psm1:124`
