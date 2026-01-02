# Routing real-device validation evidence (sample)

## Metadata
- Date/time (local): 2025-12-29 12:00
- Operator: Test Operator
- Site(s): WLLS
- Vendor(s): CiscoIOSXE
- VRF(s): default
- Session manifest path: Tests/Fixtures/Routing/CliCaptureSession/CiscoIOSXE/Session.json

## Commands Executed
1) Preflight:
   - `pwsh -NoProfile -File Tools/Test-RoutingOnlineCaptureReadiness.ps1 -SessionPath Tests/Fixtures/Routing/CliCaptureSession/CiscoIOSXE/Session.json -OutputPath Logs/Reports/RoutingOnlineCaptureReadiness-20251229-120000.json -RequireSsh`
2) Orchestrator (online):
   - `pwsh -NoProfile -File Tools/Invoke-RoutingValidationRun.ps1 -SessionPath Tests/Fixtures/Routing/CliCaptureSession/CiscoIOSXE/Session.json -Mode Online -AllowNetworkCapture -SshUser test -OutputRoot Logs/Reports/RoutingValidationRun/Operator-20251229 -UpdateLatest -PassThru`

## Evidence Artifacts
- Preflight summary JSON: Tests/Fixtures/Routing/RealDeviceEvidence/PreflightSummary.sample.json
- Orchestrator summary JSON (timestamped): Tests/Fixtures/Routing/RealDeviceEvidence/RoutingValidationRunSummary.sample.json
- Orchestrator log: Tests/Fixtures/Routing/RealDeviceEvidence/OperatorRun.sample.log
