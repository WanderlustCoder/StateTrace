# Plan P - Packaging & Deployment Reliability

<!-- LANDMARK: ST-E-001 telemetry gates link -->
Telemetry gates: [docs/telemetry/Automation_Gates.md](../telemetry/Automation_Gates.md).

## Objective
Make packaging, signing, and deployment of StateTrace predictable and reproducible: stable artifacts, consistent versioning, verifiable hashes, and installer smoke tests that match release gates.

## Current status (2025-12)
- Packaging script (`Tools/Pack-StateTrace.ps1`) exists but lacks automated verification of contents, hashes, or install/uninstall smokes.
- Release evidence relies on telemetry bundles (Plan G) but not on installer integrity checks or version stamping.
- No tracked checklist ensures Windows execution policy, required runtimes, and module versions are validated before packaging.

## Active work
| ID | Title | Owner | Status | Notes |
|----|-------|-------|--------|-------|
| ST-P-001 | Package integrity checks | PMO | Ready | Extend packaging to emit hashes/manifest and verify contents (modules, tools, plans, README hashes). Fail build on mismatch. |
| ST-P-002 | Install/uninstall smokes | QA | Backlog | Add a headless install/uninstall smoke (PowerShell 5.1) that validates module import, pipeline invocation on fixtures, and clean removal. |
| ST-P-003 | Version stamping & changelog | PMO | Backlog | Stamp package/build version into a manifest; ensure release notes reference the telemetry bundle + package hash. |
| ST-P-004 | Dependency preflight | Platform | Done - 2026-01-04 | Created `Tools/Test-DependencyPreflight.ps1` to validate: PowerShell version (5.1+), execution policy, required modules (Pester 3.4+), Access OLEDB providers (ACE/Jet), .NET Framework, and disk space. Use `-RequireAllPass` to fail on any issue, `-OutputPath` to save JSON report. |

## Recently delivered
- Plan created to centralize packaging and deployment reliability.

## Automation hooks
- Packaging: `Tools\Pack-StateTrace.ps1 -OutputPath <dir>` (extend to emit manifest/hashes).
- Smoke install (proposed): install package to temp path, `Invoke-Pester Modules/Tests -Tag Smoke`, run pipeline warm/cold on fixtures, then uninstall.
- Hash verify: `Get-FileHash -Algorithm SHA256 <artifact>` added to bundle README.

## Telemetry gates
- Packages include manifest + hashes; verification passes before release upload.
- Install/uninstall smokes succeed on PowerShell 5.1 with tracked fixtures only.
- Version stamps present in package and release notes; telemetry bundle ID referenced.

## References
- `docs/plans/PlanG_ReleaseGovernance.md` (release gates).
- `docs/CODEX_RUNBOOK.md` (bundle/release automation).
- `Tools/Pack-StateTrace.ps1` (packaging entrypoint to extend).

