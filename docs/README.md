# StateTrace Documentation Index

This index provides a high-level map of the active planning and process documents for the StateTrace project. Use it as your starting point when navigating the repository. Each link below points to a Markdown file under docs/ and summarises its purpose.

## Planning & Strategy

- **[StateTrace Consolidated Plans](StateTrace_Consolidated_Plans.md)** - master dossier covering Plan A (Routing Reliability), Plan B (Performance and Ingestion Scale), Plan C (Change Tracking), Plan D (Feature Expansion and Guided Troubleshooting), Plan E (Telemetry and Launch Metrics), Plan F (Security, Identity and Online Mode), and Plan G (Release and Governance).
- **[Diff Model Prototype](StateTrace_DiffModel_Prototype.md)** - proof-of-concept for change tracking data structures and access patterns.
- **[Feature and Functions Catalogue](StateTrace_Functions_Features.md)** - catalogue of current and proposed UI and workflow capabilities.
- **[Routing Data Architecture](StateTrace_Routing_DataArchitecture.md)** - schemas, diagrams, and integration points for routing telemetry.

## Process & Operations

- **[Task Board](StateTrace_TaskBoard.md)** - Kanban board with WIP limits and deliverable links.
- **[Risk Register](RiskRegister.md)** - centralises the top risks with triggers, mitigations, owners, and review cadences.
- **[Quarterly Roadmap](StateTrace_Quarterly_Roadmap.md)** - milestone dates, owners, scope bullets, and exit criteria.
- **[Release Guide](Release.md)** - packaging and versioning instructions and smoke test requirements.
- **[Security Guidelines](Security.md)** - data-handling rules, redaction policy, and retention expectations.
- **[Architecture Decision Records](adr/)** - authoritative decisions (data store, UI platform, compiled components).

## Using AI Agents

- **[AI Agent Operations Guide](StateTrace_AI_Agent_Guide.md)** - the canonical playbook for agents (what they can and cannot do, safe implementation checklist, validation steps).
- **AGENT_INSTRUCTIONS.txt** - short, step-by-step operating loop for agents running in limited terminal sessions.
- **AI_Agent_Terminal_Prompt.txt** - the exact system prompt to load for terminal agents (command budget, guardrails, output format).
- **[Agent PR Checklist](agents/Agent_PR_Checklist.md)** - what every agent-generated PR must include.
- **[Agent Session Template](agents/Agent_Session_Template.md)** - a lightweight template for logging what the agent did and why.
- **[Core Ideas](Core_Ideas.md)** - quick reference to the project pillars mirrored from `AGENTS.md` for use in plans and reviews.

## Historical & Completed Work

Completed plans are moved to docs/completed/ with a completion summary and date. If other documents still reference them, leave a short stub pointing to the archive.

## Execution & Overrides Quick Reference

- Run `powershell -File Tools/Invoke-StateTracePipeline.ps1 -VerboseParsing` for a full ingestion pass; use `-SkipTests` when the Pester suite already ran.
- Trial manual ceilings by passing `-ThreadCeilingOverride`, `-MaxWorkersPerSiteOverride`, `-MaxActiveSitesOverride`, `-JobsPerThreadOverride`, or `-MinRunspacesOverride`; these temporarily supersede the zero-valued hints in `Data/StateTraceSettings.json`.
- Each run logs telemetry (`ParseDuration`, `DatabaseWriteLatency`, `ConcurrencyProfileResolved`, etc.) to `Logs/IngestionMetrics/<date>.json`; review these files when capturing metrics for plan updates.
- Generate daily metric rollups with `Tools/Rollup-IngestionMetrics.ps1 -MetricsDirectory Logs/IngestionMetrics -OutputPath Logs/IngestionMetrics/IngestionMetricsSummary.csv`; add `-IncludePerSite`/`-IncludeSiteCache` for detailed slices, `-MetricFile <path>` for ad-hoc summaries, or `-MetricFileNameFilter '2025-11-*.json' -Latest 3` to filter the dataset without parsing the full archive.
- Remove the override parameters (or set them to `0`) once experiments finish so autoscaling resumes.
- Adjust bulk staging by setting `ParserSettings.InterfaceBulkChunkSize` in `Data/StateTraceSettings.json`; ParserWorker now pushes the value to ParserPersistenceModule (default 24, use `0` to stage full batches).



