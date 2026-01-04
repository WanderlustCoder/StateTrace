# Fixtures (Repo-tracked)

This folder contains deterministic fixture seeds for harness and test smokes.
See `docs/fixtures/README.md` for the full policy and regeneration rules.

## Available Datasets

### CISmoke (ST-J-001)
Comprehensive CI smoke fixtures with balanced BOYO/WLLS sites (6 hosts total).
- **Path**: `Tests/Fixtures/CISmoke/`
- **Manifest**: `Tests/Fixtures/manifests/CISmoke.json`
- **Files**:
  - `IngestionMetrics.json` - Line-delimited telemetry events (47 events)
  - `WarmRunTelemetry.json` - Sample warm-run comparison output
- **Usage**: `Tools/Invoke-CIHarness.ps1` offline smoke testing
- **Sites**: BOYO (3 hosts), WLLS (3 hosts)

### Synthetic-5.1 (Legacy)
Minimal synthetic metrics corpus for basic harness smoke.
- **Path**: `Tests/Fixtures/Synthetic/5.1/IngestionMetrics.json`
- **Manifest**: `Tests/Fixtures/manifests/Synthetic-5.1.json`
- **Usage**: `Invoke-ScheduledHarnessSmoke.ps1 -DatasetVersion 5.1`

## Generation

All fixtures are pre-generated and committed; no runtime generation required.
If you need to regenerate or extend fixtures:

1. Edit the source JSON files directly
2. Update the manifest with new event counts
3. Run `Tools/Invoke-CIHarness.ps1 -SkipPipeline -SkipWarmRun` to validate

## Validation Criteria

CI fixtures must meet these gates:
- Queue delay p95 <= 120 ms, p99 <= 200 ms
- Site diversity streak <= 8
- Warm improvement >= 60%
- Warm cache hit >= 80%
