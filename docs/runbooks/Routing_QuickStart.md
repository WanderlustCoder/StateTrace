# Routing QuickStart

## Overview
This quickstart covers the routing validation workflow in three modes: offline fixtures, simulated online (no network), and operator-run online (networked). All commands assume you are running from the repo root. **Current phase is offline-only; online/operator steps are OUT OF SCOPE until device access is approved.**

## Demo (offline, deterministic)
Single-command offline demo that exercises diff + bundle + review + explorer using fixtures only.
```powershell
pwsh -NoProfile -File Tools/Invoke-RoutingOfflineDemo.ps1 -UpdateLatest -PassThru
```
Outputs:
- Summary latest pointer: `Logs/Reports/RoutingOfflineDemo/RoutingOfflineDemoSummary-latest.json`
- Explorer markdown: `Logs/Reports/RoutingOfflineDemo/Run-<timestamp>/Outputs/RoutingLogExplorer-latest.md`

## Generate session manifest from host list (offline)
Generate a RoutingCliCaptureSession manifest deterministically from a host list. This is offline-only and does not touch the network.
```powershell
pwsh -NoProfile -File Tools/New-RoutingCliCaptureSession.ps1 `
  -HostsPath Tests/Fixtures/Routing/CliCaptureSession/Hosts.sample.txt `
  -Site WLLS `
  -Vendor CiscoIOSXE `
  -Vrf default `
  -OutputPath Logs/Reports/RoutingCliCaptureSessionManifests/Session-<timestamp>.json `
  -CapturedAt '2025-12-29T00:00:00Z' `
  -PassThru
```

## Offline fixture run (no network)
1) Preflight readiness (offline):
```powershell
pwsh -NoProfile -File Tools/Test-RoutingOnlineCaptureReadiness.ps1 `
  -SessionPath Tests/Fixtures/Routing/CliCaptureSession/CiscoIOSXE/Session.json `
  -OutputPath Logs/Reports/RoutingOnlineCaptureReadiness-<timestamp>.json `
  -PassThru
```

2) Orchestrator offline run:
```powershell
pwsh -NoProfile -File Tools/Invoke-RoutingValidationRun.ps1 `
  -SessionPath Tests/Fixtures/Routing/CliCaptureSession/CiscoIOSXE/Session.json `
  -Mode Offline `
  -OutputRoot Logs/Reports/RoutingValidationRun `
  -UpdateLatest `
  -PassThru
```

3) Outputs
- Summary: `Logs/Reports/RoutingValidationRun/Run-<timestamp>/RoutingValidationRunSummary-<timestamp>.json`
- Latest pointer: `Logs/Reports/RoutingValidationRun/RoutingValidationRunSummary-latest.json`

## View results (offline)
Use the offline routing log viewer to render summaries from the generated JSON artifacts.
```powershell
pwsh -NoProfile -File Tools/Show-RoutingLogSummary.ps1 `
  -Path Logs/Reports/RoutingValidationRun/RoutingValidationRunSummary-latest.json `
  -Format Console
```
Markdown report (optional):
```powershell
pwsh -NoProfile -File Tools/Show-RoutingLogSummary.ps1 `
  -Path Logs/Reports/RoutingValidationRun/RoutingValidationRunSummary-latest.json `
  -Format Markdown `
  -OutputPath Logs/Reports/RoutingLogViewer/RoutingLogViewer-<timestamp>.md
```

## Index your routing summaries (offline)
Build an offline index of routing summaries under `Logs/Reports`, then pick an entry to view with the log viewer.
```powershell
pwsh -NoProfile -File Tools/Build-RoutingLogIndex.ps1 `
  -RootPath Logs/Reports `
  -OutputPath Logs/Reports/RoutingLogIndex/RoutingLogIndex-<timestamp>.json `
  -Recurse `
  -UseLatestPointers `
  -UpdateLatest `
  -PassThru
```
RoutingDiff JSON artifacts are indexable and viewable through the same workflow.
View a specific summary from the index (example):
```powershell
pwsh -NoProfile -File Tools/Show-RoutingLogSummary.ps1 `
  -Path <PathFromIndex.json> `
  -Format Console
```

## Explore logs (offline)
Use the offline explorer to list, filter, and select summaries without touching the network. `-Select` uses 0-based indices.
1) Build or rebuild the index (optional):
```powershell
pwsh -NoProfile -File Tools/Build-RoutingLogIndex.ps1 `
  -RootPath Logs/Reports `
  -OutputPath Logs/Reports/RoutingLogIndex/RoutingLogIndex-<timestamp>.json `
  -Recurse `
  -UseLatestPointers `
  -UpdateLatest `
  -PassThru
```
2) List entries:
```powershell
pwsh -NoProfile -File Tools/Invoke-RoutingLogExplorer.ps1 `
  -IndexPath Logs/Reports/RoutingLogIndex/RoutingLogIndex-latest.json `
  -ListOnly `
  -Top 20
```
Filtering for diff artifacts:
```powershell
pwsh -NoProfile -File Tools/Invoke-RoutingLogExplorer.ps1 `
  -IndexPath Logs/Reports/RoutingLogIndex/RoutingLogIndex-latest.json `
  -Type RoutingDiff `
  -ListOnly `
  -Top 10
```
3) View the latest run for a host:
```powershell
pwsh -NoProfile -File Tools/Invoke-RoutingLogExplorer.ps1 `
  -RootPath Logs/Reports `
  -Hostname <host> `
  -Latest `
  -Format Console
```
4) View a selected entry:
```powershell
pwsh -NoProfile -File Tools/Invoke-RoutingLogExplorer.ps1 `
  -IndexPath Logs/Reports/RoutingLogIndex/RoutingLogIndex-latest.json `
  -Select 0 `
  -Format Console
```
5) Write a markdown report for a selected entry:
```powershell
pwsh -NoProfile -File Tools/Invoke-RoutingLogExplorer.ps1 `
  -IndexPath Logs/Reports/RoutingLogIndex/RoutingLogIndex-latest.json `
  -Select 0 `
  -Format Markdown `
  -OutputPath Logs/Reports/RoutingLogExplorer/RoutingLogExplorer-<timestamp>.md
```

## Compare latest two runs (offline)
Use the explorer compare mode to diff the selected entry against the previous run for the same target. This is offline-only.
1) List entries filtered by target:
```powershell
pwsh -NoProfile -File Tools/Invoke-RoutingLogExplorer.ps1 `
  -IndexPath Logs/Reports/RoutingLogIndex/RoutingLogIndex-latest.json `
  -Site WLLS `
  -Vendor CiscoIOSXE `
  -Vrf default `
  -ListOnly `
  -Top 20
```
2) Compare the newest two runs for a host automatically:
```powershell
pwsh -NoProfile -File Tools/Invoke-RoutingLogExplorer.ps1 `
  -RootPath Logs/Reports `
  -Hostname <host> `
  -CompareLatestTwo `
  -DiffOutputPath Logs/Reports/RoutingDiff/RoutingDiff-<timestamp>.json `       
  -DiffMarkdownPath Logs/Reports/RoutingDiff/RoutingDiff-<timestamp>.md `       
  -PassThru
```
3) Review the diff markdown report:
- `Logs/Reports/RoutingDiff/RoutingDiff-<timestamp>.md`

## Compare two runs (offline)
Use the offline diff tool to compare two RouteHealthSnapshot outputs (optionally enriched with RouteRecords). This is offline-only.
1) List candidate runs:
```powershell
pwsh -NoProfile -File Tools/Invoke-RoutingLogExplorer.ps1 `
  -IndexPath Logs/Reports/RoutingLogIndex/RoutingLogIndex-latest.json `
  -ListOnly `
  -Top 20
```
2) Locate the snapshot + route records paths:
```powershell
pwsh -NoProfile -File Tools/Show-RoutingLogSummary.ps1 `
  -Path <SummaryPathFromExplorer.json> `
  -Format Console
```
Open the summary JSON (or the per-host pipeline summary it references) and copy `ArtifactPaths.RouteHealthSnapshotPath` plus `ArtifactPaths.RouteRecordsPath`.
3) Generate a diff report:
```powershell
pwsh -NoProfile -File Tools/Compare-RouteHealthSnapshots.ps1 `
  -OldSnapshotPath <OldRouteHealthSnapshot.json> `
  -NewSnapshotPath <NewRouteHealthSnapshot.json> `
  -OldRouteRecordsPath <OldRouteRecords.json> `
  -NewRouteRecordsPath <NewRouteRecords.json> `
  -OutputPath Logs/Reports/RoutingDiff/RoutingDiff-<timestamp>.json `
  -MarkdownPath Logs/Reports/RoutingDiff/RoutingDiff-<timestamp>.md `
  -UpdateLatest `
  -PassThru
```
Omit `-OldRouteRecordsPath`/`-NewRouteRecordsPath` to diff snapshots without route detail enrichment.

## Export a bundle (offline)
Package a routing summary or diff (plus referenced artifacts) into a zip for offline sharing. Root path enforcement keeps exports scoped to the repo.
```powershell
pwsh -NoProfile -File Tools/Export-RoutingOfflineBundle.ps1 `
  -SummaryPath Logs/Reports/RoutingDiff/<diff>.json `
  -OutputZipPath Logs/Reports/RoutingBundles/RoutingBundle-<timestamp>.zip `
  -UpdateLatest `
  -PassThru
```

## Export a bundle from explorer (offline)
Use the explorer to export bundles for the newest run or for a compare diff without extra steps.
1) Export the latest run bundle for a host:
```powershell
pwsh -NoProfile -File Tools/Invoke-RoutingLogExplorer.ps1 `
  -RootPath Logs/Reports `
  -Hostname <host> `
  -Latest `
  -ExportBundle `
  -BundleZipPath Logs/Reports/RoutingBundles/RoutingBundle-Explorer-<timestamp>.zip `
  -PassThru
```
2) Compare the latest two runs for a host and export a diff bundle:
```powershell
pwsh -NoProfile -File Tools/Invoke-RoutingLogExplorer.ps1 `
  -RootPath Logs/Reports `
  -Hostname <host> `
  -CompareLatestTwo `
  -DiffOutputPath Logs/Reports/RoutingDiff/RoutingDiff-<timestamp>.json `
  -DiffMarkdownPath Logs/Reports/RoutingDiff/RoutingDiff-<timestamp>.md `
  -ExportDiffBundle `
  -DiffBundleZipPath Logs/Reports/RoutingBundles/RoutingBundle-Diff-<timestamp>.zip `
  -PassThru
```

## Validate a bundle (offline)
Verify a routing bundle zip before sharing or importing. Extra files fail by default; pass `-AllowExtraFiles` if you need to permit extras.
```powershell
pwsh -NoProfile -File Tools/Test-RoutingOfflineBundle.ps1 `
  -BundleZipPath Logs/Reports/RoutingBundles/RoutingBundle-Diff-<timestamp>.zip `
  -OutputPath Logs/Reports/RoutingBundles/RoutingBundleValidation-<timestamp>.json `
  -PassThru
```

## Review a bundle (offline, single command)
Validate, expand, locate the primary summary, and optionally index/render in one offline run.
One-step review + explorer output:
```powershell
pwsh -NoProfile -File Tools/Invoke-RoutingBundleReview.ps1 `
  -BundleZipPath Logs/Reports/RoutingBundles/RoutingBundle-Diff-<timestamp>.zip `
  -WorkspaceRoot Logs/Reports/RoutingBundles/Review/BundleReview-<timestamp> `
  -Overwrite `
  -RunExplorer `
  -UpdateLatest `
  -PassThru
```
OutputsRoot includes:
- `RoutingLogIndex-latest.json`
- `RoutingBundlePrimarySummary-latest.md`
- `RoutingLogExplorer-latest.md`
The review summary emits an ExplorerCommand for the extracted workspace index.

## Review a bundle (offline)
Validate and expand a routing bundle into an offline workspace, then index and explore the extracted content.
1) Validate the bundle:
```powershell
pwsh -NoProfile -File Tools/Test-RoutingOfflineBundle.ps1 `
  -BundleZipPath Logs/Reports/RoutingBundles/RoutingBundle-Diff-<timestamp>.zip `
  -OutputPath Logs/Reports/RoutingBundles/RoutingBundleValidation-<timestamp>.json `
  -PassThru
```
2) Expand the bundle into a workspace:
```powershell
pwsh -NoProfile -File Tools/Expand-RoutingOfflineBundle.ps1 `
  -BundleZipPath Logs/Reports/RoutingBundles/RoutingBundle-Diff-<timestamp>.zip `
  -OutputRoot Logs/Reports/RoutingBundles/Expanded/Bundle-<timestamp> `
  -PassThru
```
3) Build an index over the extracted logs:
```powershell
pwsh -NoProfile -File Tools/Build-RoutingLogIndex.ps1 `
  -RootPath Logs/Reports/RoutingBundles/Expanded/Bundle-<timestamp>/Logs/Reports `
  -OutputPath Logs/Reports/RoutingBundles/Expanded/Bundle-<timestamp>/Logs/Reports/RoutingLogIndex/RoutingLogIndex-<timestamp>.json `
  -Recurse `
  -UseLatestPointers `
  -PassThru
```
4) Explore the extracted index:
```powershell
pwsh -NoProfile -File Tools/Invoke-RoutingLogExplorer.ps1 `
  -IndexPath Logs/Reports/RoutingBundles/Expanded/Bundle-<timestamp>/Logs/Reports/RoutingLogIndex/RoutingLogIndex-<timestamp>.json `
  -ListOnly `
  -Top 20
```

## Simulated online run (no network)
**OUT OF SCOPE FOR CURRENT PHASE** (retained for future operator validation).
This uses a transcript capture scriptblock instead of SSH. No network operations occur.
```powershell
$env:STATETRACE_ALLOW_NETWORK_CAPTURE = '1'
pwsh -NoProfile -File Tools/Invoke-RoutingValidationRun.ps1 `
  -SessionPath Tests/Fixtures/Routing/CliCaptureSession/CiscoIOSXE/Session.json `
  -Mode Online `
  -AllowNetworkCapture `
  -SshUser test `
  -TranscriptCaptureScriptBlock {
    param($Hostname, $Vendor, $Command, $OutputPath)
    Copy-Item -LiteralPath "Tests/Fixtures/Routing/CliCapture/CiscoIOSXE/show_ip_route.txt" `
      -Destination $OutputPath -Force
  } `
  -OutputRoot Logs/Reports/RoutingValidationRun/SimulatedOnline `
  -UpdateLatest `
  -PassThru
```

## Operator real device online run (networked)
**OUT OF SCOPE FOR CURRENT PHASE**. Operator-run only. Requires approved network access, SSH keys, and a change window.
1) Enable gating (operator only):
```powershell
setx STATETRACE_ALLOW_NETWORK_CAPTURE 1
```
Start a new shell after `setx`, or set `$env:STATETRACE_ALLOW_NETWORK_CAPTURE='1'`.

2) Preflight and run:
```powershell
pwsh -NoProfile -File Tools/Test-RoutingOnlineCaptureReadiness.ps1 `
  -SessionPath <Session.json> `
  -OutputPath Logs/Reports/RoutingOnlineCaptureReadiness-<timestamp>.json `
  -RequireSsh `
  -SshUser <user> `
  -SshIdentityFile <path> `
  -SshPort 22 `
  -SshExePath ssh

pwsh -NoProfile -File Tools/Invoke-RoutingValidationRun.ps1 `
  -SessionPath <Session.json> `
  -Mode Online `
  -AllowNetworkCapture `
  -SshUser <user> `
  -SshIdentityFile <path> `
  -OutputRoot Logs/Reports/RoutingValidationRun/Operator-<yyyyMMdd> `
  -UpdateLatest `
  -PassThru
```

## Evidence closure steps (operator run)
1) Fill the evidence template:
   - `docs/templates/Routing_RealDeviceEvidence.md`
2) Validate and generate the JSON record:
```powershell
pwsh -NoProfile -File Tools/Test-RoutingRealDeviceEvidence.ps1 `
  -EvidencePath <CompletedEvidence.md> `
  -OutputPath Logs/Reports/RoutingRealDeviceEvidence/RoutingRealDeviceEvidence-<timestamp>.json `
  -UpdateLatest `
  -PassThru
```
3) Attach the JSON record path to the TaskBoard + session log.

## Troubleshooting pointers
- Gating failures: ensure `STATETRACE_ALLOW_NETWORK_CAPTURE=1` and `-AllowNetworkCapture`.
- SSH not found: use `-SshExePath` or install OpenSSH client.
- Identity file missing: verify `-SshIdentityFile` path.
- Unsupported vendor: ensure Vendor is `CiscoIOSXE` or `AristaEOS`.
- Missing transcript paths: validate the session manifest and artifact paths.

## References
- Architecture: `docs/StateTrace_Routing_DataArchitecture.md`
- Operator checklist: `docs/runbooks/Routing_RealDeviceValidation.md`
- Evidence template: `docs/templates/Routing_RealDeviceEvidence.md`
