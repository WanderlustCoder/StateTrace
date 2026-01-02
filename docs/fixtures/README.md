# Fixtures

This document defines fixture expectations for StateTrace.

**Non-negotiable rule:** tests and harness smokes must not rely on untracked or gitignored fixture content.
If large generated logs are excluded, the repo must still contain enough seeds/templates to regenerate them deterministically.

## LANDMARK: Fixture goals
- Deterministic reproduction for:
  - parsing
  - persistence
  - cache behavior
  - warm-run telemetry
  - diff/change tracking
- Fast minimal fixture set for CI smoke.
- Clear provenance: each fixture set has a manifest and a stable ID.

## LANDMARK: Recommended layout

StateTrace standardizes fixtures under `Tests/Fixtures`:

```text
Tests/Fixtures/
  README.md
  manifests/
    Minimal.json
    BalancedWarm.json
  seeds/                      # committed (required)
    templates/                # committed (required)
  generated/                  # gitignored (allowed)
  goldens/                    # committed expected outputs (optional)
```

If `Tests/Fixtures` does not exist yet, create it alongside the first fixture set and commit the manifest + seeds.

## LANDMARK: Fixture manifests

Each fixture set must have a manifest documenting:
- fixture set name and version
- included device/site identities (sanitized)
- what the fixture validates (parser, cache, diff, UI, etc.)
- required generation steps (if any)
- expected telemetry characteristics (e.g., should pass diversity guard)

Minimal manifest fields (example):
```json
{
  "name": "Minimal",
  "version": "1.0.0",
  "description": "Small deterministic set for CI smoke.",
  "includes": [
    { "site": "BOYO", "notes": "Tracked Access DB under Data/BOYO" },
    { "site": "WLLS", "notes": "Tracked Access DB under Data/WLLS" }
  ],
  "generation": {
    "requiresGeneration": false,
    "command": null
  }
}
```

## LANDMARK: Generating synthetic logs (if used)

Plan J references a synthetic corpus generator:
- `Tools/Expand-MockLogCorpus.ps1`

Rules:
- The generator must run offline.
- The generator must not depend on external downloads.
- Templates/seeds must be committed.

Example:
```powershell
# LANDMARK: Expand synthetic corpus
Tools\Expand-MockLogCorpus.ps1 -Force
```

If output logs are gitignored, the generator must:
- create them deterministically from committed templates
- validate checksums or counts
- fail fast with clear remediation guidance

## LANDMARK: Avoiding polluted telemetry inputs

Harnesses should reject telemetry contamination from:
- stray debug slices
- stale prior-run artifacts
- mixed fixture sets

Recommendations:
- use `-ResetExtractedLogs` when running pipeline harnesses
- set `STATETRACE_TELEMETRY_DIR` for run-scoped output
- explicitly log every input path used for a run
- fail if inputs are outside the expected fixture directories

## LANDMARK: Golden outputs (optional but recommended)

For brittle areas (e.g., diff outputs, schema snapshots), maintain goldens:
- store under `Tests/Fixtures/goldens/<fixtureSet>/...`
- provide a deterministic regeneration command
- require review of golden diffs in PRs

## LANDMARK: CI fixture standards

The CI fixture set must:
- run in <= 20 minutes on a clean seat (default target; update as needed)
- pass queue summary + diversity + cache gates
- include enough data to trigger all required summaries (no "0 samples" artifacts)
