# StateTrace Routing Data Architecture

## Scope and goals
- Provide an end-to-end, offline-first routing reliability pipeline with deterministic artifacts and auditable evidence.
- Standardize routing capture formats, conversions, and health scoring so UI/operations rely on stable schemas.
- Enable operator-run, gated online capture while keeping CI and automated checks offline.
- QuickStart reference: `docs/runbooks/Routing_QuickStart.md`.

## End-to-end lifecycle
```mermaid
flowchart LR
  A[RoutingCliCaptureSession\n(session manifest)] -->|Invoke-RoutingCliCaptureSession| B[RoutingCliCapture\n(Capture.json + transcripts)]
  B -->|Convert-RoutingCliCaptureToDiscoveryCapture| C[RoutingDiscoveryCapture]
  C -->|Convert-RoutingDiscoveryCapture| D[RouteRecord array]
  D -->|Convert-RouteRecordsToHealthSnapshot| E[RouteHealthSnapshot]
  A -->|Test-RoutingOnlineCaptureReadiness| P[Preflight Summary]
  A -->|Invoke-RoutingValidationRun| R[RoutingValidationRun Summary]
  R -->|Test-RoutingRealDeviceEvidence| V[RoutingRealDeviceEvidence Record]
```

## Data contracts and locations
- Routing CLI capture session
  - Doc: `docs/schemas/routing/RoutingCliCaptureSession.md`
  - Schema: `docs/schemas/routing/routing_cli_capture_session.schema.json`
- Routing CLI capture (per host)
  - Doc: `docs/schemas/routing/RoutingCliCapture.md`
  - Schema: `docs/schemas/routing/routing_cli_capture.schema.json`
- Routing discovery capture
  - Doc: `docs/schemas/routing/RoutingDiscoveryCapture.md`
  - Schema: `docs/schemas/routing/routing_discovery_capture.schema.json`
- RouteRecord
  - Doc: `docs/schemas/routing/RouteRecord.md`
  - Schema: `docs/schemas/routing/route_record.schema.json`
- RouteHealthSnapshot
  - Doc: `docs/schemas/routing/RouteHealthSnapshot.md`
  - Schema: `docs/schemas/routing/route_health_snapshot.schema.json`
- Routing discovery pipeline summaries
  - `Logs/Reports/RoutingDiscoveryPipeline/RoutingDiscoveryPipelineSummary-<timestamp>.json`
  - Latest pointer: `Logs/Reports/RoutingDiscoveryPipeline/RoutingDiscoveryPipelineSummary-latest.json`
- Routing validation run summaries
  - `Logs/Reports/RoutingValidationRun/Run-<timestamp>/RoutingValidationRunSummary-<timestamp>.json`
  - Latest pointer: `Logs/Reports/RoutingValidationRun/RoutingValidationRunSummary-latest.json`
- Operator evidence validation
  - `Logs/Reports/RoutingRealDeviceEvidence/RoutingRealDeviceEvidence-<timestamp>.json`
  - Latest pointer: `Logs/Reports/RoutingRealDeviceEvidence/RoutingRealDeviceEvidence-latest.json`

## Route definitions and detection latency
<!-- LANDMARK: ST-A-007 route definitions -->
- Primary route: the preferred egress path for a given site/hostname/vrf tuple, based on the current routing tables captured in RouteRecord entries.
- Secondary route: any alternate egress path for the same tuple that is valid but not selected as the primary route.
- DetectionLatencyMs: computed in RouteHealthSnapshot from the earliest and latest RouteRecord `CapturedAt` timestamps in the snapshot set (0 when only one record is present). See `docs/schemas/routing/RouteHealthSnapshot.md`.
- Alignment: definitions are reflected in the RouteRecord and RouteHealthSnapshot schemas and used by the offline discovery pipeline outputs.

## Routing telemetry inventory and gap analysis
<!-- LANDMARK: ST-A-007 telemetry inventory -->
### Inventory (offline baseline)
- RouteRecord arrays: emitted by `Tools/Convert-RoutingDiscoveryCapture.ps1` and stored with discovery pipeline outputs.
- RouteHealthSnapshot: emitted by `Tools/Convert-RouteRecordsToHealthSnapshot.ps1` and `Tools/Invoke-RoutingDiscoveryPipeline.ps1`.
- RoutingDiscoveryPipelineSummary: summary JSON under `Logs/Reports/RoutingDiscoveryPipeline/`.
- RoutingValidationRunSummary: orchestrator summary JSON under `Logs/Reports/RoutingValidationRun/`.
- RoutingRealDeviceEvidence: operator evidence validation JSON under `Logs/Reports/RoutingRealDeviceEvidence/` (offline validation of real-device runs).

### Gaps (offline phase)
- Real-device validation evidence (ST-A-019) remains deferred until device access is approved.
- Detection latency is derived from capture timestamps; there is no live UI freshness SLA enforcement yet.
- No alerting thresholds are defined for routing latency beyond offline summary review.

## Review status
<!-- LANDMARK: ST-A-007 diagram review -->
- Draft data model and service diagram (mermaid flowchart above) reviewed for offline baseline scope; recorded in `docs/agents/sessions/2026-01-02_session-0013.md`.

## Tooling map (scripts and I/O)
- `Tools/Test-RoutingOnlineCaptureReadiness.ps1`
  - Input: RoutingCliCaptureSession manifest
  - Output: Preflight readiness JSON with gating guidance
- `Tools/Invoke-RoutingCliCaptureSession.ps1` (Offline or Online, gated)
  - Input: RoutingCliCaptureSession manifest + transcripts (offline) or SSH (online)
  - Output: per-host RoutingCliCapture bundles + session summary + latest pointer
- `Tools/Convert-RoutingCliCaptureToDiscoveryCapture.ps1`
  - Input: RoutingCliCapture `Capture.json` + transcripts
  - Output: RoutingDiscoveryCapture JSON + summary (CiscoIOSXE + AristaEOS)
- `Tools/Invoke-RoutingDiscoveryPipeline.ps1`
  - Input: RoutingDiscoveryCapture
  - Output: RouteRecords, RouteHealthSnapshot, pipeline summary + latest pointer
- `Tools/Invoke-RoutingValidationRun.ps1`
  - Orchestrates preflight + capture + ingest + pipeline; emits per-host summaries
- `Tools/Test-RoutingRealDeviceEvidence.ps1`
  - Validates operator evidence markdown; emits JSON record + latest pointer
- `Tools/Show-RoutingLogSummary.ps1`
  - Offline summary renderer for routing validation and pipeline summaries

## Operational modes
- Offline fixtures: use the fixtures under `Tests/Fixtures/Routing` for CI and regression.
- Simulated online: use `-TranscriptCaptureScriptBlock` to generate transcripts without network.
- Operator online run: gated by `STATETRACE_ALLOW_NETWORK_CAPTURE=1` and `-AllowNetworkCapture`.

## Directory conventions and latest pointers
- Session capture: `Logs/Reports/RoutingCliCaptureSession/` with `RoutingCliCaptureSessionSummary-latest.json`.
- Discovery pipeline: `Logs/Reports/RoutingDiscoveryPipeline/` with `RoutingDiscoveryPipelineSummary-latest.json`.
- Validation run: `Logs/Reports/RoutingValidationRun/` with `RoutingValidationRunSummary-latest.json`.
- Operator evidence: `Logs/Reports/RoutingRealDeviceEvidence/` with `RoutingRealDeviceEvidence-latest.json`.

## Governance and evidence flow (ST-A-019 closure)
1) Operator runs the online validation orchestrator (`Tools/Invoke-RoutingValidationRun.ps1 -Mode Online`).
2) Operator fills `docs/templates/Routing_RealDeviceEvidence.md` with commands + artifact paths.
3) Validate evidence using `Tools/Test-RoutingRealDeviceEvidence.ps1`.
4) Attach the evidence JSON path to ST-A-019 and the session log.

## Failure modes and troubleshooting
- Gating failures: missing `STATETRACE_ALLOW_NETWORK_CAPTURE=1` or `-AllowNetworkCapture`.
- Missing transcripts: session runner fails with actionable missing path errors.
- Unsupported vendor: ingestion converter rejects vendor and lists supported values.
- SSH not found: readiness preflight warns or fails depending on `-RequireSsh`.
- Identity file missing: readiness preflight fails when `-SshIdentityFile` points to a missing file.

## Future extensions
- Add multi-VRF capture and per-VRF snapshot outputs.
- Expand protocol parsing (BGP/OSPF details, route tags, best path selection).
- Introduce scheduled runs and retention policies for routing evidence.
- Extend vendor support (e.g., Juniper, Aruba) with new fixtures and parsers.
