# StateTrace Core Ideas

These pillars define how agents and developers make changes. They mirror the authoritative list in `AGENTS.md` so the guidance is available inside `docs/`.

1. **Offline-first & Access-backed** - Deliver everything with PowerShell scripts and Microsoft Access databases. Avoid compiled components and keep the runtime offline-ready.
2. **Telemetry & verification** - Capture ingestion metrics (for example `ParseDuration`, `DatabaseWriteLatency`) and use them to validate behaviour and performance.
3. **Plan-first collaboration** - Record a multi-step plan before editing code, tests, or docs. Keep the plan active, narrate progress, and sync outcomes with the task board.
4. **Security & data hygiene** - Sanitize sensitive logs, exclude databases from source control, and honour the repository's strict-mode and privacy guardrails.

Refer to `AGENTS.md` for the canonical wording and to keep these pillars updated alongside contributor guidance.
