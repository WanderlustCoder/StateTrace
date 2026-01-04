# RoutingCliCaptureSession Schema (v1)

## Purpose
Defines a routing CLI capture session manifest that references per-host routing
CLI transcripts and emits per-host `RoutingCliCapture` bundles deterministically.
The same contract is used for offline transcript ingestion and for online SSH
capture (gated by explicit policy).

## Schema Version
- `SchemaVersion`: `1.0`

## Required Fields (top-level)
- `SchemaVersion` (string) - schema version, currently `1.0`
- `CapturedAt` (string) - ISO 8601 timestamp when the session was created
- `Site` (string) - site key (uppercase)
- `Vendor` (string) - routing platform identifier (e.g., `CiscoIOSXE`, `AristaEOS`)
- `Vrf` (string) - VRF name (`default` if none)
- `Hosts` (array) - list of host capture entries

## Required Fields (hosts entries)
- `Hostname` (string) - device hostname (uppercase)
- `Artifacts` (array) - list of CLI transcript references

## Required Fields (artifact entries)
- `Name` (string) - logical name of the command output (required: `show_ip_route`)
- `Command` (string) - command executed (e.g., `show ip route`)
- `TranscriptPath` (string) - relative path to the transcript file.
  - **Offline mode:** relative to `Session.json` and must exist before the run.
  - **Online mode:** relative output path under the per-host output directory.

## Mode Notes
- **Offline mode:** session references existing transcript files. The runner
  copies them into the per-host output folder and writes `Capture.json`.
- **Online mode:** the runner captures transcripts via SSH into the per-host
  output folder using the `TranscriptPath` values as relative output paths.
- **Gating:** online capture is disabled by default and requires both
  `STATETRACE_ALLOW_NETWORK_CAPTURE=1` and the `-AllowNetworkCapture` switch.   
- **Credentials:** only key-based SSH is supported; no passwords in logs.       

## Supported Vendors (v1)
- `CiscoIOSXE`
- `AristaEOS`

## Normalization Notes
- `Site` and `Hostname` should be uppercase to match UI filtering.
- Use `default` for `Vrf` when none is provided.
- `CapturedAt` must be ISO 8601 (`Get-Date -Format o`).

## Machine-Readable Schema
- `docs/schemas/routing/routing_cli_capture_session.schema.json`
