# StateTrace Acknowledgement Identity Options

## Decision Goal
Choose an authentication/identity approach that enables acknowledgement workflows, auditability, and RBAC without exceeding current infrastructure constraints (PowerShell + Access).

## Evaluation Criteria
- **User Coverage:** supports internal operators, support staff, and optional external customer logins.
- **Implementation Effort:** estimated engineering weeks, dependencies, required libraries.
- **Security Posture:** MFA availability, auditing, least privilege support.
- **Offline Resilience:** behaviour if identity provider is unreachable (cached creds, grace modes).
- **Cost & Licensing:** incremental spend or licensing implications.

## Candidate Options
| Option | Description | Pros | Cons | Dependencies | Notes |
|--------|-------------|------|------|--------------|-------|
| AD Integrated Accounts | Leverage existing Windows AD credentials via `System.DirectoryServices` | Familiar admin tooling; kerberized auth | Requires domain join; limited for customer installs | IT Security approval; domain connectivity | Evaluate remote scenarios |
| Azure AD OAuth Device Code | Use device-code flow with MSAL and token cache | Cloud-friendly, MFA, conditional access | Requires HTTP connectivity; token storage considerations | Azure App Registration; MSAL module | Needs secure secrets storage |
| Local Operator Accounts | Store hashed credentials in Access DB | Works offline; minimal dependencies | Security risk; password rotation burden | Strong hashing (PBKDF2); policy design | Might serve as fallback |
| External SSO Integration | Abstracted SSO via partner API | Aligns with enterprise customers | High integration cost; requires HTTP services | Partnership agreements | Consider Phase 2 |

## Data Flow Considerations
- Where to persist user identity (Access tables vs. config files).
- Mapping identities to acknowledgement actions (who acknowledged, when, result).
- Audit log format and retention (tie into `Logs/` directory or Access `Audit` table).

## Next Actions
- Block dedicated time to score each option using the table below.
- Update the scorecard with notes as you evaluate trade-offs.
- Draft an implementation spike outline for the chosen approach.

## Scorecard Template
| Criterion | Weight | AD Integrated Accounts | Azure AD Device Code | Local Accounts | External SSO |
|-----------|--------|------------------------|----------------------|----------------|--------------|
| User Coverage | | | | | |
| Implementation Effort | | | | | |
| Security Posture | | | | | |
| Offline Resilience | | | | | |
| Cost & Licensing | | | | | |
| Tooling Compatibility | | | | | |
| Total | | | | | |

## Open Questions
- Do we need to support acknowledgement from headless automation (API tokens)?
- What audit retention period is mandated by compliance?
- Can we rely on an existing secrets vault for token caching?
