# StateTrace Task Board (Kanban)

This board tracks work items across their lifecycle from backlog to done. Each card carries a role tag (e.g. [Ingestion], [Docs]) and should link to the relevant deliverable (script, document or test). Respect the **WIP=2** limit for the "In Progress" column as described in the resource plan.

## Backlog

- **Stress-test autoscaling parser settings** - [Ingestion] Measure thread budget metrics under Logs/IngestionMetrics/ using a representative production log bundle. Deliverable: performance report attached to StateTrace_MultiDatabase_Ingestion_Plan.md.
- **Verify database creation flow** - [Data] Remove mock .accdb files and logs, rerun ingestion and ensure hostname normalisation matches policy. Deliverable: updated notes appended to StateTrace_MultiDatabase_Ingestion_Plan.md.
- **Summarise new pipeline script and autoscaling workflow** - [Docs] Document usage steps and troubleshooting hints for Tools/Invoke-StateTracePipeline.ps1 in the multi-database plan. Deliverable: new section in StateTrace_MultiDatabase_Ingestion_Plan.md.

## Ready

_No cards currently in this column._

## In Progress (WIP=2)

_No cards currently in this column._

## Blocked

_No cards currently in this column._ Add a note explaining the dependency or issue for each blocked card.

## Done

- **Fix integer parameter binding in persistence layer** - [Automation] Completed 2025-09-30. Deliverable: parameterised ParserPersistenceModule with passing `Invoke-Pester Modules/Tests` and `Tools/Invoke-StateTracePipeline.ps1 -SkipTests`.
- **Refactored parser persistence to parameterised ADODB commands** - [Automation] Completed 2025-09-30. Deliverable: updated persistence helpers and passing tests.
- **Added orchestration script Tools/Invoke-StateTracePipeline.ps1** - [Automation] Completed 2025-09-30. Validated via `powershell -File Tools/Invoke-StateTracePipeline.ps1 -SkipParsing -VerboseParsing`.
- **Applied plan status header to each active plan** - [Docs] Completed 2025-09-30. All planning documents now include status and last reviewed fields.
