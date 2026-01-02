# StateTrace Release Guide

This guide describes how to package, version and release StateTrace.  It covers semantic versioning, artefact creation, smoke testing and changelog management.  Follow these steps whenever preparing a new release candidate.

## Release preconditions
- Plans and Task Board are current (doc sync complete).
- Telemetry gates are up to date (`docs/telemetry/Automation_Gates.md`).
- Verification tooling is runnable under PowerShell 5.1.
- Material risks are recorded in `docs/RiskRegister.md`.

## Release evidence checklist (minimum)
- [ ] Plan G gates satisfied (`docs/plans/PlanG_ReleaseGovernance.md`).
- [ ] Verification summary captured (see `Tools/Invoke-StateTraceVerification.ps1` or scheduled verification tasks).
- [ ] Telemetry bundle verification recorded (bundle path, README hashes, readiness summary path, and `Tools/New-TelemetryBundle.ps1` artifact link).
<!-- LANDMARK: Release checklist telemetry bundle verification artifact link -->
- [ ] Shared cache snapshot evidence captured when relevant.
- [ ] Doc sync completed (plans, Task Board, session logs).
- [ ] Risk register reviewed/updated if needed.
- [ ] Release candidate summary references Risk Register entries (RR-###) and lists mitigations/owners.
- [ ] NetOps evidence recorded and reset if online mode was used.

## Release candidate summary (risk register linkage)
<!-- LANDMARK: Release candidate summary - risk register linkage requirement -->
Create a release candidate summary using `docs/templates/Release_Candidate_Summary.md` and include the relevant Risk Register entry IDs (RR-###) from `docs/RiskRegister.md` with mitigation + owner notes. Attach the summary path to the release checklist before approvals.
<!-- LANDMARK: ST-G-007 release checklist ties telemetry bundle verification to RC summary template -->
Record telemetry bundle verification details (bundle path, areas, readiness summary path, README hashes) in the release candidate summary template so the checklist can reference a single artifact.

## Versioning

StateTrace uses [semantic versioning](https://semver.org/) with the format `MAJOR.MINOR.PATCH`:

- **MAJOR** – incremented for breaking changes in the data model, UI contracts or PowerShell APIs.
- **MINOR** – incremented when adding backwards‑compatible features or significant plan milestones.
- **PATCH** – incremented for bug fixes and minor improvements.

Include a pre‑release suffix (e.g. `-beta1`) for internal betas or pilot releases.  Record the chosen version at the top of `CHANGELOG.md`.

## Packaging

Releases are built via a PowerShell script (`Tools/Pack-StateTrace.ps1`) which collects the necessary modules, views, tools and documentation into a zip file.  The script performs the following steps:

1. **Clean build directory** – remove any previous build artefacts.
2. **Copy source files** – include the `Modules/`, `Views/`, `Tools/`, `Data/StateTraceSettings.json` (without personal data), and `docs/` excluding `Logs/` or other ignored folders.
3. **Embed version number** – write the selected version into a `VERSION.txt` file in the root of the package.
4. **Create archive** – use `Compress-Archive` to produce `StateTrace_<version>.zip` in the `dist/` folder.
5. **Generate hash** – compute a SHA‑256 hash of the archive and write to `<package>.sha256` for integrity checking.

Ensure the script itself is version controlled; it lives in `Tools/Pack-StateTrace.ps1`.

## Smoke testing

Before tagging a release, run the following smoke tests to verify that the packaged application works end-to-end:

1. **Unit tests** – execute `Invoke-Pester` in the `Modules/Tests/` folder.  All tests must pass.
2. **Basic parsing** – run `Tools/Invoke-StateTracePipeline.ps1 -SkipParsing:$false` against a representative log bundle.  Confirm that databases are created, logs are parsed and no errors are emitted.
3. **UI load** – launch the main window via `Invoke-StateTraceUI.ps1` (or the appropriate entry point) and load sample data.  Verify that core dashboards render without exceptions.
4. **Version check** – open the `About` dialog or run `Get-StateTraceVersion` to confirm the embedded version matches the intended release.

Document the outcome of each smoke test in the release checklist and attach any relevant logs.

## Shared cache snapshot verification

Release candidates must confirm shared cache snapshot coverage before sign-off:

1. Run `Tools\Invoke-SharedCacheWarmup.ps1 -ShowSharedCacheSummary -RequiredSites BOYO,WLLS` (or run the pipeline with `-ShowSharedCacheSummary`) to write `Logs\SharedCacheSnapshot\SharedCacheSnapshot-*-summary.json` and update `SharedCacheSnapshot-latest-summary.json`.
2. Validate the summary with `pwsh -NoLogo -File Tools\Test-SharedCacheSnapshot.ps1 -Path Logs\SharedCacheSnapshot\SharedCacheSnapshot-latest-summary.json -MinimumSiteCount 2 -MinimumHostCount 37 -MinimumTotalRowCount 1200 -RequiredSites BOYO,WLLS`.
3. Attach the summary JSON path and guard output to the release checklist.

## Telemetry bundle verification

Release candidates must include a verified telemetry bundle before approvals (Plan G ST-G-007). After exporting telemetry via `Tools\Publish-TelemetryBundle.ps1`, follow `docs/runbooks/Telemetry_Bundle_Verification.md`:

1. Run `pwsh Tools\Test-TelemetryBundleReadiness.ps1 -BundlePath Logs\TelemetryBundles\<bundle> -Area Telemetry,Routing -IncludeReadmeHash -SummaryPath Logs\TelemetryBundles\<bundle>\VerificationSummary.json` (or `pwsh Tools\Invoke-AllChecks.ps1 -TelemetryBundlePath Logs\TelemetryBundles\<bundle> -RequireTelemetryBundleReady`) to validate required files and capture README SHA-256 hashes automatically.
2. Paste the hash + readiness output + verification timestamp (and a link to `VerificationSummary.json`) into `docs/plans/PlanE_Telemetry.md`, `docs/plans/PlanG_ReleaseGovernance.md`, and the Task Board release row.
3. Attach the readiness table generated by the script (and/or the JSON summary) to the release checklist.

Releases missing any required artifact must block until the bundle is regenerated and revalidated.

## Changelog

Maintain a human-readable `CHANGELOG.md` at the repository root.  Each entry should note the version, release date and a concise summary of changes.  Link to relevant plan documents or PRs for further details.  When preparing a release, draft the changelog entry first and update it during the release process.

## Tagging & distribution

Once smoke tests pass and the changelog is ready:

1. Commit the version bump and changelog updates.
2. Tag the commit with `v<version>` and push the tag to the repository.
3. Upload the zipped package and its SHA‑256 file to the chosen distribution platform (e.g. internal artefact repository or release manager).  Do not publish `Logs/` or other local data.
4. Announce the release internally with a summary of key changes and any required upgrade steps.

## Rollback procedure

If a critical issue is discovered after release:

1. Communicate the issue to all stakeholders immediately.
2. Revert to the previous stable version by restoring the corresponding package and tag.
3. Investigate the root cause and apply a patch on a new branch; follow the same release process when ready.
