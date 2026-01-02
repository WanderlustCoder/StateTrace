# Routing real-device validation evidence

## Metadata
- Date/time (local):
- Operator:
- Site(s):
- Vendor(s):
- VRF(s):
- Session manifest path:

## Gating and environment
- STATETRACE_ALLOW_NETWORK_CAPTURE:
- AllowNetworkCapture switch used:
- SSH user:
- SSH identity file path (path only, do not include key contents):
- SSH port:

## Commands executed
1) Preflight:
   - `pwsh -NoProfile -File Tools/Test-RoutingOnlineCaptureReadiness.ps1 -SessionPath <Session.json> -OutputPath <path>.json -RequireSsh -SshUser <user> -SshIdentityFile <path> -SshPort 22 -SshExePath ssh`
2) Orchestrator (online):
   - `pwsh -NoProfile -File Tools/Invoke-RoutingValidationRun.ps1 -SessionPath <Session.json> -Mode Online -AllowNetworkCapture -SshUser <user> -SshIdentityFile <path> -OutputRoot <root> -UpdateLatest -PassThru`

## Evidence artifacts
- Preflight summary JSON:
- Preflight log:
- Orchestrator summary JSON (timestamped):
- Orchestrator latest pointer:
- Capture session summary JSON:
- Ingestion summary JSON(s):
- Pipeline summary JSON(s):
- AllChecks log (if run):
- Validator output JSON:

## Results
- Overall status:
- Hosts processed:
- Any failures or warnings:

## Deviations / incidents
- Describe any deviations from the runbook or unexpected issues.

## Follow-ups
- TaskBoard update:
- Session log entry:
