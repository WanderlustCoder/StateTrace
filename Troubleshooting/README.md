# StateTrace Troubleshooting Suite

## Overview
The troubleshooting suite automates cross-checks that AI operators can run before or after applying changes. It collects diagnostic evidence, normalises errors, and publishes machine-readable artefacts AI agents can triage or hand off to humans.

## Components
- `Invoke-StateTraceDiagnostics.ps1` orchestrates modular phases and emits JSON/Markdown reports.
- `KnowledgeBase.yml` maps recurring error signatures to remediation hints and follow-up probes.
- Phase helpers gather logs, validate module exports, and exercise existing smoke/Pester tests when available.

## Running Diagnostics
```powershell
# From the repository root
powershell -ExecutionPolicy Bypass -File .\Troubleshooting\Invoke-StateTraceDiagnostics.ps1

# Run a subset of phases and choose an output folder
powershell -ExecutionPolicy Bypass -File .\Troubleshooting\Invoke-StateTraceDiagnostics.ps1 -Phases Environment DataLayer -OutputDirectory C:\Temp\StateTraceDiag

# From an existing PowerShell session
.\Troubleshooting\Invoke-StateTraceDiagnostics.ps1 -Phases Environment,DataLayer
```

## Report Outputs
- JSON: structured results under `Logs/Troubleshooting/<timestamp>/diagnostics.json` (or the directory supplied).
- Markdown: operator-friendly summary at the same location.
- Raw artefacts: transcripts, smoke test logs, and module import traces per phase.

## Extending the Suite
1. Add a new phase function inside `Invoke-StateTraceDiagnostics.ps1` returning diagnostic result objects.
2. Update the `$PhaseHandlers` map so the orchestrator recognises the new phase name.
3. Document the probe under a new heading in this README and the knowledge base if error signatures emerge.

## Safety Notes
- Diagnostics are read-only by default; parser routines run in dry mode without mutating Access databases.
- When extending checks, ensure they respect the guardrails in `docs/StateTrace_AI_Agent_Guide.md`.
- Capture supporting evidence for any failure so AI agents have the context needed for remediation.
