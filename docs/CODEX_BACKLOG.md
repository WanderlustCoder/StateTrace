# Codex Backlog (Automation-Ready)

Use this list to queue work that Codex (or another automation agent) can execute with minimal hand-off. Each entry must also exist on the task board/CSV and in the relevant plan file.

| ID | Plan | Title | Preconditions | Definition of done | Notes |
|----|------|-------|---------------|--------------------|-------|
| ST-B-001 | Plan B | Investigate WLLS snapshot/materialize regression | Cold history reset, access to BOYO/WLLS corpus | Cold + warm run metrics captured, cache adoption proven, Plan B + task board updated | See `docs/plans/PlanB_Performance.md`. |
| ST-B-002 | Plan B | Trial reduced auto-scale ceilings post-batching | Ability to run pipeline with overrides | Benchmark run recorded, recommendation documented, overrides reset | Command examples in `docs/CODEX_RUNBOOK.md`. |
| ST-A-001 | Plan A | Verify InterfaceSync timing completeness | Dispatcher harness ready | 37 InterfaceSyncTiming events logged, queue latency recorded, plan updated | Requires `Tools/Invoke-StateTracePipeline.ps1 -ResetExtractedLogs`. |

Add new items by cloning the row, linking to the appropriate plan, and updating the CSV/task board.
