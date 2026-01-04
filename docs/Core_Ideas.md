# StateTrace Core Ideas

These pillars mirror the authoritative wording in `docs/StateTrace_AI_Agent_Guide.md`. Update that guide first if the policy changes, then refresh this quick-reference copy and the short summary in `AGENTS.md`.

1. **Documentation Primacy** - Treat repository documentation as the single source of truth. Consult it before every change, record the plan-of-action in docs/task boards, and update the record once work is complete-even when that means pausing other priorities.
2. **Approved PowerShell Verbs** - Exported functions and cmdlets must use verbs from the official `Get-Verb` list. Audit new or renamed commands for verb compliance, update legacy names that slip through, and document any remediation plans alongside code changes.
3. **Offline-first & Access-backed** - Deliver everything with PowerShell scripts and Microsoft Access databases. Avoid compiled components and keep the runtime offline-ready.
4. **Telemetry & verification** - Capture ingestion metrics (for example `ParseDuration`, `DatabaseWriteLatency`) and use them to validate behaviour and performance.
5. **Plan-first collaboration** - Record a multi-step plan before editing code, tests, or docs. Keep the plan active, narrate progress, and sync outcomes with the task board.
6. **Security & data hygiene** - Sanitize sensitive logs, exclude databases from source control, and honour the repository's strict-mode and privacy guardrails.
7. **Parser/UI separation** - Treat the parser pipeline and WPF UI as distinct phases: parse logs and hydrate Access databases first, then surface the stored results in the interface while documenting when fresh ingestion is required.

Refer to `AGENTS.md` for the canonical wording and to keep these pillars updated alongside contributor guidance.
