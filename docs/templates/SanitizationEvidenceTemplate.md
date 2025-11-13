# Sanitization Evidence Template

- **Session ID:** `2025-11-13_session-0004`
- **Task Board IDs:** `ST-F-002`, `ST-C-005`, `ST-D-009`
- **Plan references:** `docs/plans/PlanF_SecurityIdentity.md`, `docs/plans/PlanC_ChangeTracking.md`, `docs/plans/PlanD_FeatureExpansion.md`

## Source & Destination
- **Raw bundle path (not checked in):** `D:\SecureDrop\INC2025-1103\Raw`
- **Sanitized output path:** `Data\Postmortems\INC2025-1103\Sanitized`
- **Report path:** `Logs\Sanitization\INC2025-1103.json`

## Command
```powershell
pwsh Tools\Sanitize-PostmortemLogs.ps1 `
    -SourcePath D:\SecureDrop\INC2025-1103\Raw `
    -DestinationPath Data\Postmortems\INC2025-1103\Sanitized `
    -ReportPath Logs\Sanitization\INC2025-1103.json `
    -RedactPatterns @('password','secret','community','token','snmpv3','accesskey')
```

## Redaction summary
| Pattern | Matches | Notes |
|---------|---------|-------|
| `password` | 42 | Cleared device console passwords |
| `community` | 18 | Removed SNMPv2 community strings |
| `snmpv3` | 6 | Redacted auth+priv keys |

## Validation checks
- [x] `Invoke-Pester Tests/Sanitize-PostmortemLogs.Tests.ps1`
- [x] `Tools/Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -InputPath Data\Postmortems\INC2025-1103\Sanitized`

## Follow-up actions
- Linked sanitized bundle in `docs/StateTrace_IncidentPostmortem_Intake.md`.
- Referenced sanitized incident in Plan C ST-C-005 and Plan D ST-D-009.
- Attached `Logs/Sanitization/INC2025-1103.json` and this evidence block to the Task Board update & session log.
