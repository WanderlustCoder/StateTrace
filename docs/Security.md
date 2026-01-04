# StateTrace Security & Privacy Guidelines

These guidelines document how sensitive data should be handled within the StateTrace project.  They cover redaction policies, data retention, and repository hygiene.  Follow them when ingesting logs, storing test fixtures and packaging releases.

## Redaction policy

Raw device logs and postmortems may contain secrets such as passwords, community strings, tokens or customer identifiers.  To protect this data:

- Always run `Tools/Sanitize-PostmortemLogs.ps1` before checking incident logs into any repository.  The script redacts lines matching configurable patterns (`password`, `secret`, `token`, `community`) and outputs a sanitisation report.
- Expand the pattern list for known sensitive markers relevant to your environment (e.g. OAuth tokens, SNMP v3 credentials) and share updates with the team.
- Review the sanitisation report to ensure no sensitive information remains before storing or sharing sanitized logs.
- Never store unredacted `.log` or `.accdb` files in version control.  Treat raw postmortem bundles as transient and confidential.

## Data retention & storage

- Retain sanitized postmortem logs only for as long as they are needed for troubleshooting and developing runbooks.  The default retention period is 90 days unless extended by compliance requirements.
- Store sanitized fixtures used in tests under `Tests/Fixtures/` rather than `Logs/`.  Keep them as small as possible to cover edge cases without exposing unnecessary information.
- Rotate and archive Access databases when they grow beyond operational limits.  Nightly maintenance scripts should produce rolling backups under `Data/Backups/` and remove backups older than 30 days.
- Do not commit large binary artefacts or datasets to the repository.  Use the `Data/` directory only for default settings and schemas, not for customer data.

## Repository hygiene

- Update `.gitignore` to exclude `Logs/`, `Data/Backups/`, and other folders containing transient or sensitive information.  This reduces the risk of accidentally committing secrets or large artefacts.
- Move example or mock logs into `Tests/Fixtures/` and document their provenance (e.g. generated, sanitised).  Avoid including any real hostnames, IP addresses or credentials.
- When sharing output (e.g. screenshots, reports), verify that any personal or sensitive information is obscured or removed.

## Incident handling

- Treat all incident bundles and postmortems as confidential.  Limit access to those involved in the analysis and ensure they follow the redaction policy.
- When writing runbooks or knowledge base articles, avoid copying sensitive snippets directly from logs.  Abstract the relevant information or replace it with placeholders.
- Dispose of temporary files securely after use, especially when working on shared or insecure systems.

By following these guidelines, you help ensure that StateTrace respects customer privacy and complies with data‑protection standards.


## Online Mode & NetOps Logging (ST-F-001)

StateTrace is **offline-first**. Online dev mode is opt-in and requires explicit logging of all network operations.

### Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `STATETRACE_AGENT_ALLOW_NET` | `0` | Set to `1` to allow network access |
| `STATETRACE_AGENT_ALLOW_INSTALL` | `0` | Set to `1` to permit local tooling installation |

### Approved Download Workflow

1. **Enable online mode** (only when unavoidable):
   ```powershell
   $env:STATETRACE_AGENT_ALLOW_NET = '1'
   $env:STATETRACE_AGENT_ALLOW_INSTALL = '1'  # if needed
   ```

2. **Use the guarded download cmdlet**:
   ```powershell
   Import-Module Tools/NetworkGuard.psm1
   Invoke-AllowedDownload `
       -Uri https://vendor.example.com/tool.zip `
       -Destination Downloads\tool.zip `
       -ExpectedSha256 <hash> `
       -Reason 'Plan F ST-F-001 - tool update'
   ```

3. **Log the operation** using the schema in `docs/templates/NetOpsLogTemplate.json`:
   - Save to `Logs/NetOps/<date>-<session>.json`
   - Include: Timestamp, SessionId, TaskBoardIds, Action, Arguments, Environment, Result

4. **Reset online mode** immediately after completion:
   ```powershell
   pwsh Tools\Reset-OnlineModeFlags.ps1 -Reason "ST-F-001 download complete"
   ```
   This clears the env vars and creates `Logs/NetOps/Resets/OnlineModeReset-<timestamp>.json`.

5. **Validate evidence** before closing the session:
   ```powershell
   pwsh Tools\Test-NetOpsEvidence.ps1 -RequireEvidence -RequireReason
   # Or via AllChecks:
   pwsh Tools\Invoke-AllChecks.ps1 -RequireNetOpsEvidence
   ```

### Bootstrap & Dev Seat Setup

- Use `Tools/Bootstrap-DevSeat.ps1` to install pinned versions of common tools via `winget`.
- Reference the approved manifest at `Tools/Bootstrap/ApprovedManifest.json`.
- Bootstrap tools are **not** packaged with releases - runtime remains offline-capable.

### Compliance Requirements

- All downloads must use `Tools/NetworkGuard.psm1::Invoke-AllowedDownload` with allowlisted domains.
- Every online session must produce a NetOps log (`Logs/NetOps/<date>.json`).
- Every online session must end with a reset log (`Logs/NetOps/Resets/*.json`).
- Reference NetOps evidence in session logs and Plan F task board entries.
- Runtime deliverables remain offline‑capable (PowerShell + Access only).