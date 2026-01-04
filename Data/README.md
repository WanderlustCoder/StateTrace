# Data Directory

This directory contains runtime data, configuration, and tracked fixture samples for StateTrace.

## Directory Structure

```
Data/
├── README.md                    # This file (tracked)
├── Samples/                     # Tracked fixture samples (NOT gitignored)
│   ├── DiffPrototype/           # Diff model prototype fixtures
│   ├── IncrementalLoading/      # Incremental loading test data
│   └── TelemetryBundles/        # Sample telemetry bundles
├── IngestionHistory/            # Parser history (gitignored)
├── StateTraceSettings.json      # Runtime settings (gitignored)
├── RoutingHosts.txt             # Routing host lists (gitignored)
├── BOYO/                        # Site-specific data (gitignored)
└── WLLS/                        # Site-specific data (gitignored)
```

## Gitignore Policy

- `Data/` is gitignored by default
- `Data/Samples/` and subdirectories are explicitly tracked
- All other subdirectories contain runtime/local data

## Fixture Regeneration

### Synthetic Log Corpus

The mock log corpus is generated from template logs to simulate device outputs for testing.

**Required template logs** (gitignored, must exist locally):
- `Logs/mock_cisco_authentic.log` - Template for WLLS sites
- `Logs/mock_brocade_BOYO_73.log` - Template for BOYO sites

**To regenerate the corpus:**

```powershell
# Generate synthetic logs for all hosts in telemetry
Tools\Expand-MockLogCorpus.ps1 -Force

# Specify a different source metrics file
Tools\Expand-MockLogCorpus.ps1 -SourceMetricsPath 'Logs\IngestionMetrics\2025-12-01.json' -Force
```

**If templates are missing:**

1. Obtain authentic device logs from a test environment
2. Sanitize using `Tools\Sanitize-PostmortemLogs.ps1`
3. Save as the template filenames above
4. Re-run `Tools\Expand-MockLogCorpus.ps1 -Force`

### CI Smoke Fixtures

Deterministic fixtures for CI testing are tracked under `Tests/Fixtures/`:

- `Tests/Fixtures/CISmoke/` - Balanced BOYO/WLLS telemetry (47 events, 6 hosts)
- `Tests/Fixtures/manifests/` - Dataset manifests with validation criteria

These fixtures require no regeneration - they are committed and static.

**To validate CI fixtures:**

```powershell
# Run fixture validation tests
Invoke-Pester Modules/Tests/ParserPersistenceModule.Tests.ps1 -Tag Decomposition

# Run CI harness on fixtures
Tools\Invoke-CIHarness.ps1 -SkipPipeline -SkipWarmRun
```

### Ingestion History

Parser state is stored under `Data/IngestionHistory/`. This is gitignored and regenerated during pipeline runs.

**To reset ingestion history:**

```powershell
# Pipeline will reset when using -ResetExtractedLogs
Tools\Invoke-StateTracePipeline.ps1 -ResetExtractedLogs
```

## Related Documentation

- `Tests/Fixtures/README.md` - CI fixture dataset documentation
- `docs/plans/PlanJ_TestFixtureReliability.md` - Fixture reliability plan
- `docs/CODEX_RUNBOOK.md` - Operational runbook

## Troubleshooting

**"Required template log is missing"**

The corpus expansion script needs authentic device log templates. These are gitignored for security. See "Fixture Regeneration" above for how to create them.

**"No hostnames discovered"**

The source metrics file has no parseable hostname fields. Ensure you have run a pipeline pass to generate telemetry, or use the CISmoke fixtures instead.

**"Ingestion history directory not found"**

Run `Tools\Invoke-StateTracePipeline.ps1` once to initialize the directory structure, or create `Data\IngestionHistory\` manually.
