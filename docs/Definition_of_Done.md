# Definition of Done

This document defines the minimum completion criteria for StateTrace work items.
It is designed to be mechanical: if each checkbox is satisfied, the task is done.

## LANDMARK: General completion (all tasks)
- [ ] The change has a clear Task Board ID (e.g., `ST-K-001`) and/or Codex backlog ID.
- [ ] The relevant plan page (A-S) has been updated:
  - [ ] "Active work" row updated with status and notes
  - [ ] new/changed commands or gates recorded
  - [ ] links to artifacts added
- [ ] `docs/StateTrace_TaskBoard.md` and `docs/taskboard/TaskBoard.csv` are updated and consistent.
- [ ] All affected scripts/modules include clear error messages and return non-zero exit codes on failure.
- [ ] No secrets, tokens, or customer data are committed.
- [ ] Any new file paths or schema changes are documented in `docs/schemas/**`.

## LANDMARK: Test completion
- [ ] Fast checks pass (`Tools/Invoke-AllChecks.ps1` or equivalent).
- [ ] Unit tests pass (`Invoke-Pester` on `Modules/Tests`).
- [ ] For harness-affecting changes:
  - [ ] Pipeline smoke passes on the tracked corpus (BOYO/WLLS) or the declared fixture set in `docs/fixtures/README.md`.
  - [ ] Verification harness passes.

## LANDMARK: Telemetry / performance work

If the task impacts telemetry, performance, cache behavior, or gating:

- [ ] A warm-run telemetry pass was executed (or explicitly waived with documented reason).
- [ ] Gating thresholds meet expectations (or waiver is documented):
  - [ ] QueueDelaySummary p95/p99 within limits
  - [ ] Port diversity streak <= 8
  - [ ] Warm cache improvement + cache-hit thresholds meet plan gates
  - [ ] SharedCache SnapshotImported > 0
- [ ] Required artifacts are present under `Logs\` (see `docs/Test_Strategy.md`).
- [ ] A telemetry bundle was published with a complete manifest:
  - [ ] `Tools/Publish-TelemetryBundle.ps1` executed
  - [ ] manifest includes plan references + Task Board IDs
  - [ ] artifacts list includes hashes and sizes
  - [ ] bundle path is linked from the plan page and task board row

## LANDMARK: UI work

If the task affects UI:

- [ ] UI smoke checklist completed (`docs/UI_Smoke_Checklist.md`).
- [ ] Accessibility/responsiveness criteria validated (Plan O):
  - [ ] Keyboard navigation reaches all primary views (Summary, Interfaces, Alerts, Search, Compare, Span, Templates).
  - [ ] Focus order matches visual order and focus is visible.
  - [ ] Text/primary controls meet WCAG AA contrast (4.5:1 normal text, 3:1 large text).
  - [ ] Key interactions (tab switch, search apply, compare diff load) complete within 2s on warm cache or measured timings are recorded.
- [ ] Screenshots or automation artifacts captured under `docs/performance/screenshots/` or `Logs/Reports/InterfacesViewChecklist-*.json`.

## LANDMARK: Security / online mode work

If the task touches identity, security, or online mode:

- [ ] Online mode changes are justified with a documented reason (Plan F).
- [ ] Threat/risk notes updated if new attack surface is introduced.
- [ ] Sanitization evidence recorded if logs/incidents were processed (Plan R).

## LANDMARK: Reviewer-ready output

- [ ] The change is packaged as a clean PR/patch:
  - [ ] includes a concise summary
  - [ ] includes the commands run
  - [ ] includes links to artifacts / bundle manifest
  - [ ] notes any waivers and why
