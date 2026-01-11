# Code review scope (2026-01-09)

## In scope
- Main/, Modules/, Views/, Tools/, Resources/, Templates/, Themes/, Troubleshooting/
- Tests/ and Modules/Tests (harnesses + fixtures)
- Docs: release/governance/runbooks + core agent guidance (`docs/Release.md`, `docs/telemetry/Automation_Gates.md`, `docs/plans/PlanG_ReleaseGovernance.md`, task board/backlog)

## Out of scope
- Generated artifacts under Logs/ (unless referenced as evidence)
- Access databases (.accdb) and runtime data stores
- dist/ outputs
- Screenshots (unless required for UI evidence)
- Online mode/network actions unless explicitly authorized

## Assumptions
- Offline-first, PowerShell 5.x runtime target
- Access-backed storage is the authoritative data store
- Parser/UI separation remains enforced

## Risk focus areas
- Access write paths (ADODB usage, schema setup, concurrency).
- Parser/runspace scheduling and shared cache hydration.
- UI actions that mutate data or rely on background jobs.
- Tooling that performs destructive operations or touches external systems.

## Review constraints
- No network usage unless explicitly authorized.
- Execute runtime-compatible tests under Windows PowerShell 5.1.

## Review order
1. Parser pipeline + runspaces
2. Repository/Access modules
3. Vendor parsers + detection
4. UI/view modules
5. Tooling/automation scripts
6. Docs/governance alignment

## Readiness gates
- Reference `docs/telemetry/Automation_Gates.md` and Plan G requirements.
- Record evidence paths in the evidence log.
