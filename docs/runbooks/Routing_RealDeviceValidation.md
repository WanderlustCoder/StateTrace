# Routing real-device validation (operator-run)

## Summary
Run the operator-approved routing validation flow against real devices using the routing validation orchestrator. **Out of scope for the current offline-only phase**; execute only when device access is approved. This is a networked run and must be performed by an operator with approved access, SSH keys, and a documented change window.
Architecture reference: `docs/StateTrace_Routing_DataArchitecture.md`.
QuickStart: `docs/runbooks/Routing_QuickStart.md`.

## Preconditions
- Operator approval for network access and target device access.
- SSH key-based authentication available (no passwords).
- Routing CLI capture session manifest prepared:
  - See `docs/schemas/routing/RoutingCliCaptureSession.md`.
- Optional: ssh-agent running and loaded with the key used for the target devices.

## Generate session manifest from host list (offline)
Use the manifest generator to avoid hand-editing JSON. This is offline-only.
```powershell
pwsh -NoProfile -File Tools/New-RoutingCliCaptureSession.ps1 `
  -HostsPath <Hosts.txt> `
  -Site <Site> `
  -Vendor CiscoIOSXE `
  -Vrf default `
  -OutputPath Logs/Reports/RoutingCliCaptureSessionManifests/Session-<timestamp>.json `
  -CapturedAt '2025-12-29T00:00:00Z' `
  -PassThru
```

## Quick Start (operator run)
1) Preflight readiness (no network):
   - `pwsh -NoProfile -File Tools/Test-RoutingOnlineCaptureReadiness.ps1 -SessionPath <Session.json> -OutputPath Logs/Reports/RoutingOnlineCaptureReadiness-<timestamp>.json -RequireSsh -SshUser <user> -SshIdentityFile <path> -SshPort 22 -SshExePath ssh`
2) Enable network capture gating (operator only):
   - `setx STATETRACE_ALLOW_NETWORK_CAPTURE 1`
   - New shell required after `setx` (or set `$env:STATETRACE_ALLOW_NETWORK_CAPTURE='1'` in the current shell).
3) Run online routing validation (networked):
   - `pwsh -NoProfile -File Tools/Invoke-RoutingValidationRun.ps1 -SessionPath <Session.json> -Mode Online -AllowNetworkCapture -SshUser <user> -SshIdentityFile <path> -OutputRoot Logs/Reports/RoutingValidationRun/Operator-<yyyyMMdd> -UpdateLatest -PassThru`
4) Validate evidence (offline):
   - `pwsh -NoProfile -File Tools/Test-RoutingRealDeviceEvidence.ps1 -EvidencePath <Evidence.md> -OutputPath Logs/Reports/RoutingRealDeviceEvidence/RoutingRealDeviceEvidence-<timestamp>.json -UpdateLatest -PassThru`

## Detailed steps
1) Verify the session manifest
   - Ensure `Session.json` matches `docs/schemas/routing/routing_cli_capture_session.schema.json`.
   - Required artifacts include `show_ip_route` per host.
2) Preflight
   - Use the preflight tool to confirm vendor support, transcript path safety, and SSH availability.
   - Resolve any failures before continuing.
3) Online capture + validation
   - Use the orchestrator command shown in Quick Start.
   - This orchestrates capture, ingestion, and pipeline for each host.
4) Optional manual steps (if you need to re-run individual phases)
   - Capture only:
     - `pwsh -NoProfile -File Tools/Invoke-RoutingCliCaptureSession.ps1 -Mode Online -AllowNetworkCapture -SessionPath <Session.json> -SshUser <user> -SshIdentityFile <path> -OutputRoot <root> -UpdateLatest -PassThru`
   - Ingestion:
     - `pwsh -NoProfile -File Tools/Convert-RoutingCliCaptureToDiscoveryCapture.ps1 -CapturePath <Capture.json> -OutputPath <RoutingDiscoveryCapture.json> -SummaryPath <IngestionSummary.json> -PassThru`
   - Pipeline:
     - `pwsh -NoProfile -File Tools/Invoke-RoutingDiscoveryPipeline.ps1 -CapturePath <RoutingDiscoveryCapture.json> -OutputRoot <PipelineRoot> -UpdateLatest -PassThru`

## Expected outputs
- Orchestrator summary JSON:
  - `Logs/Reports/RoutingValidationRun/Run-<timestamp>/RoutingValidationRunSummary-<timestamp>.json`
- Latest pointer (if `-UpdateLatest`):
  - `Logs/Reports/RoutingValidationRun/RoutingValidationRunSummary-latest.json`
- Per-host pipeline summaries:
  - `Logs/Reports/RoutingValidationRun/Run-<timestamp>/Pipeline/<hostname>/RoutingDiscoveryPipelineSummary-<timestamp>.json`
- Preflight summary JSON:
  - `Logs/Reports/RoutingValidationRun/Run-<timestamp>/PreflightSummary.json`

## Failure handling
- If preflight fails: resolve the specific check (missing `show_ip_route`, unsupported vendor, missing SSH executable, invalid transcript path).
- If capture fails: inspect the per-host error in the orchestrator summary and the capture session summary.
- If ingestion fails: check the ingestion summary under `Run-<timestamp>/Ingestion/<hostname>/`.
- If pipeline fails: inspect per-host pipeline summary under `Run-<timestamp>/Pipeline/<hostname>/`.

## Evidence attachment
- Use `docs/templates/Routing_RealDeviceEvidence.md` to record:
  - commands run
  - environment settings (gating)
  - summary and log paths
  - any deviations or incidents
- Run `Tools/Test-RoutingRealDeviceEvidence.ps1` on the completed evidence file and record the output JSON in the TaskBoard and session log.

## Escalation
- Escalate to PMO/Routing if:
  - preflight reports unsupported vendor or schema mismatch
  - capture fails for multiple hosts
  - pipeline summaries indicate consistent ingestion failures
