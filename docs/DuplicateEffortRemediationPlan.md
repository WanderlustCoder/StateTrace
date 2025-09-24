# Duplicate Effort Remediation Plan

## Overview
- Remove redundant function blocks from `Modules/CompareViewModule.psm1` and keep a single maintained implementation.
- Centralize hostname-to-site resolution so tools stop maintaining parallel helpers.

## Workstream 1 – CompareView module cleanup
1. Diff the duplicate function sets (`Resolve-CompareControls`, `Get-HostString`, `Get-HostsFromMain`, `Set-PortsForCombo`, `Get-GridRowFor`, `Get-PortSortKey`, `Get-PortsForHost`, `Get-AuthTemplateFromTooltip`, `Show-CurrentComparison`, `Update-CompareView`, `Get-CompareHandlers`, `Set-CompareSelection`) to confirm there are no behavioral discrepancies and pick the canonical version.
2. Remove the redundant copy and ensure all internal references point to the surviving definitions; consider splitting shared helpers into a dedicated script block for clarity.
3. Add focused tests (Pester or integration smoke) that load `CompareViewModule` and exercise the compare workflow to guard against regression when pruning duplicates.

## Workstream 2 – Shared hostname/site helpers
1. Promote `Get-SiteFromHostname` in `Modules/DeviceRepositoryModule.psm1` as the canonical helper and extend it to cover the additional cases handled today by `Modules/ParserWorker.psm1` (e.g., `SSH@` prefixes, fallback substring logic).
2. Replace the local implementation in `ParserWorker` with calls to the shared helper and add unit tests covering the combined scenarios so future changes stay in sync.
3. Audit other modules for ad-hoc hostname parsing and update them to rely on the shared helper where applicable.

## Validation & rollout
- Run existing module test suites (or add smoke scripts) to ensure the compare view still wires up correctly.
- Perform a targeted regression on parsing workflows to confirm host and site metadata remain accurate after consolidating helpers.
- Update developer notes to mention the new single-source helper and the cleaned compare view surface area.
