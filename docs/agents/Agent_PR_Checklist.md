# Agent PR Checklist

Use this checklist in every agent-generated pull request. Copy and paste, then fill in the items.

- [ ] **Plan reference:** Link to the recorded plan (`update_plan` output) and note which `AGENTS.md` core ideas it satisfied (see `docs/Core_Ideas.md`).
- [ ] **Problem statement:** One-paragraph description of what this change addresses.
- [ ] **Scope of change:** Short bullet list of files touched.
- [ ] **Risk assessment:** What could break? How did you minimise risk?
- [ ] **Tests:** Paste `Invoke-Pester` summary (lines showing Passed/Failed/Skipped).
- [ ] **Smoke run:** If ingestion/UI touched, paste key lines from `Tools/Invoke-StateTracePipeline.ps1` or a UI launch confirmation.
- [ ] **Telemetry:** New/changed metrics (names and fields). Link to dictionary updates if applicable.
- [ ] **Docs updated:** Links to relevant files in `docs/` (plans/guides) and mark the task board card Done (YYYY-MM-DD).
- [ ] **Security review:** Confirm no secrets/logs/.accdb files were committed; fixtures live under `Tests/Fixtures/`.
- [ ] **Rollback plan:** One sentence on how to revert safely if issues arise.


