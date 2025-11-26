# 2025-11-26 – Onboarding quickstart (Plan H ST-H-001)

## Purpose
Document the fastest path for operators to reach a validated Interfaces view, record time-to-first-view, and collect evidence for task board/plan updates.

## Steps (headless or UI)
1. **Seed data (optional):** `pwsh Tools/Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -ResetExtractedLogs` (skip if Access data is current).
2. **Headless checklist:**  
   `pwsh -NoLogo -STA -File Tools/Invoke-InterfacesViewChecklist.ps1 -SiteFilter WLLS,BOYO -MaxHosts 6 -OutputPath Logs/Reports/InterfacesViewChecklist.json -SummaryPath Logs/Reports/InterfacesViewQuickstart.json`  
   - Summary captures `TimeToFirstHostMs`, host success counts, and per-host interface rows.
   - `SiteFreshness` in the summary records the last ingest timestamp/age/source per site (from `Data/IngestionHistory/<site>.json`).
3. **UI confirmation (optional):** Launch `Main/MainWindow.ps1`, click **Scan Logs** once, then use **Load from DB** to hydrate the Interfaces view without rerunning the parser. Confirm host dropdown + freshness indicator populate.
4. **Log evidence:** Record the ingestion log path (if generated) and `Logs/Reports/InterfacesViewQuickstart.json` in your session log and task board update.

## Expected outputs
- `Logs/Reports/InterfacesViewChecklist.json` – per-host interface/batch counts from the headless run.
- `Logs/Reports/InterfacesViewQuickstart.json` – summary with `TimeToFirstHostMs` and host success counts.
- UI help should point to the Operators Runbook “Start here (quickstart)” section when opened from the toolbar.

## References
- Plan H: `docs/plans/PlanH_UserExperience.md`
- Operators Runbook quickstart: `docs/StateTrace_Operators_Runbook.md#start-here-quickstart`
- UI smoke checklist: `docs/UI_Smoke_Checklist.md`
