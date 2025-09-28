# StateTrace Incident Postmortem Intake

## Objective
- Assemble a curated set of recent incidents to seed runbook content, anomaly thresholds, and diff validation scenarios.
- Ensure each postmortem includes sanitized log bundles, customer impact summary, and remediation outcome.

## Intake Workflow
1. Identify candidate incidents from personal incident notes or monitoring alerts (focus on routing/authentication issues).
2. Sanitize raw log bundles using the helper script before bringing them into the repository.
3. Store anonymized bundles under `Data/Postmortems/<IncidentId>/Sanitized` (create directory per incident).
4. Capture summary details in the tracking table below and flag missing artifacts.
5. Review completeness and add lessons learned before considering the incident ready for analysis.

## Supporting Utilities
- Sanitization script: `Tools/Sanitize-PostmortemLogs.ps1`
  - Example usage: `./Tools/Sanitize-PostmortemLogs.ps1 -SourcePath C:\raw_incidents\INC0001 -DestinationPath Data/Postmortems/INC0001`
  - Customize the `-RedactPatterns` parameter to add strings or regexes for environment-specific secrets.
- Storage layout: place each sanitized bundle under `Data/Postmortems/<IncidentId>/Sanitized`. Raw bundles should remain outside the repo.


## Tracking Table
| Incident ID | Date | Source Team | Owner | Log Bundle Path | Sanitization Status | Notes |
|-------------|------|-------------|-------|-----------------|---------------------|-------|
|             |      |             |       |                 |                     |       |
|             |      |             |       |                 |                     |       |
|             |      |             |       |                 |                     |       |

## Acceptance Criteria
- Minimum of 6 incidents collected (mix of diff-friendly config drift and anomaly-heavy outages).
- Each incident includes: run timeline, affected devices/sites, root cause summary, remediation steps, lessons learned.
- Logs validated for parser compatibility (PowerShell ingestion succeeds without manual edits).

## Open Questions
- Do we need customer approval sign-off before storing sanitized bundles in repo?
- Should we standardize naming convention (e.g., `INC2025-####`) across Ops and Support records?
- How frequently should this library be refreshed once initial seeding completes?
