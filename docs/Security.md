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


## Online Mode Addendum

- Online dev mode is **opt-in**. Set `STATETRACE_AGENT_ALLOW_NET=1` to allow network access and `STATETRACE_AGENT_ALLOW_INSTALL=1` to permit local tooling installation.
- All downloads must use `Tools/NetworkGuard.psm1::Invoke-AllowedDownload` with allowlisted domains and (where possible) pinned SHA‑256 hashes.
- Use `Tools/Bootstrap-DevSeat.ps1` to install pinned versions of common tools via `winget`; these are **not** packaged with releases.
- Record provenance of downloads and installations in agent session logs and `Logs/NetOps/<date>.json`.
- Runtime deliverables remain offline‑capable (PowerShell + Access only).