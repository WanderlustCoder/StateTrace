# StateTrace Performance Improvement Plan

## Overview
Recent review highlighted several hot spots where the parser pipeline spends unnecessary CPU time, memory, and I/O. Addressing the points below should shorten end-to-end log ingestion while keeping behaviour unchanged.

## Key Opportunities
- **Module warm-up:** Parser workers import every module with -Force, discarding script-scope caches and adding redundant load time per job.
- **Log parsing memory pressure:** Invoke-DeviceLogParsing materialises entire logs and rescans them multiple times; large bundles trigger heavy allocations and garbage collection.
- **Mutex contention:** All database writes share the StateTraceDbWriteMutex, serialising commits across independent site databases.
- **Ingestion disk flushes:** Split-RawLogs writes every line with AutoFlush, forcing synchronous disk I/O.

## Implementation Plan
1. **Parser runspace initialisation**
   - Preload required modules when the runspace pool is created, dropping -Force after the first import.
   - Verify template caches (e.g., VendorTemplatesCache) persist across multiple files in a single session.
2. **Streaming log parser**
   - Replace Get-Content usage with a streaming reader that yields prompt blocks and shared metadata in one pass.
   - Refactor vendor parsers to consume the streamed structures and measure memory/time improvements on large sample logs.
3. **Scoped database mutexes**
   - Base the mutex name on the target database path or site code so unrelated runs proceed in parallel.
   - Cache the detected OLE DB provider per database to avoid repeated COM instantiation.
   - Confirm multi-site processing now shows concurrent commits without collisions.
4. **Buffered log splitting**
   - Remove automatic per-line flushing; flush writers when switching hosts or closing files.
   - Rerun the ingestion smoke test to ensure identical output and capture timing deltas.

## Validation
- Execute existing smoke tests (e.g., Tests\Invoke-MainWindowSmokeTest.ps1) after each change.
- Add regression coverage where missing, especially around template caching and multi-site database writes.
- Capture before/after telemetry for large log bundles to quantify performance gains.
