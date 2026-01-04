# StateTrace Acknowledgement Identity Options

## Decision Goal
Choose an authentication/identity approach that enables acknowledgement workflows, auditability, and RBAC without exceeding current infrastructure constraints (PowerShell + Access).

## Evaluation Criteria
- **User Coverage:** supports internal operators, support staff, and optional external customer logins.
- **Implementation Effort:** estimated engineering weeks, dependencies, required libraries.
- **Security Posture:** MFA availability, auditing, least privilege support.
- **Offline Resilience:** behaviour if identity provider is unreachable (cached creds, grace modes).
- **Cost & Licensing:** incremental spend or licensing implications.
- **Tooling Compatibility:** fit with existing PowerShell modules, Access schemas, and offline-first delivery.

## Candidate Options
| Option | Description | Pros | Cons | Dependencies | Notes |
|--------|-------------|------|------|--------------|-------|
| AD Integrated Accounts | Leverage existing Windows AD credentials via `System.DirectoryServices` | Familiar admin tooling; Kerberos-backed auth | Requires domain join; limited for customer installs | IT Security approval; domain connectivity | Evaluate remote/off-domain scenarios |
| Azure AD OAuth Device Code | Use device-code flow with MSAL and token cache | Cloud-friendly, MFA, conditional access | Requires HTTP connectivity; token storage considerations | Azure App Registration; MSAL module | Needs secure secrets storage |
| Local Operator Accounts | Store hashed credentials in Access DB | Works offline; minimal dependencies | Security risk; password rotation burden | Strong hashing (PBKDF2); policy design | Candidate fallback for air-gapped sites |
| External SSO Integration | Abstracted SSO via partner API | Aligns with enterprise customers | High integration cost; requires HTTP services | Partnership agreements | Consider Phase 2 |

## Scoring Model
- Scores use a 1 (poor) to 5 (excellent) scale.
- Weighted totals multiply the score by the criterion weight; higher totals are better.

## Scorecard
| Criterion | Weight | AD Integrated Accounts | Azure AD Device Code | Local Accounts | External SSO |
|-----------|--------|------------------------|----------------------|----------------|--------------|
| User Coverage | 5 | 3 (15) | 4 (20) | 2 (10) | 5 (25) |
| Implementation Effort | 4 | 3 (12) | 2 (8) | 3 (12) | 1 (4) |
| Security Posture | 5 | 4 (20) | 5 (25) | 2 (10) | 4 (20) |
| Offline Resilience | 5 | 2 (10) | 1 (5) | 5 (25) | 1 (5) |
| Cost & Licensing | 3 | 4 (12) | 3 (9) | 5 (15) | 2 (6) |
| Tooling Compatibility | 3 | 4 (12) | 3 (9) | 3 (9) | 2 (6) |
| **Total** | **25** | **81** | **76** | **81** | **66** |

## Recommendation
Adopt **AD integrated accounts** as the primary acknowledgement identity path for Phase 1 deployments, supplemented by a tightly-controlled **local operator account fallback** for air-gapped or lab environments. AD integration keeps parity with existing enterprise controls (audit trails, password policies, MFA via smart cards) while allowing us to reuse the Windows credential stack from PowerShell. Local accounts should remain scoped to non-domain installations, gated behind strong hashing (PBKDF2 + per-user salt), explicit rotation guidance, and telemetry that flags fallback usage.

Azure AD device-code auth remains a viable Phase 2 enhancement once online mode is sanctioned; external SSO integrations defer until customer-driven demand justifies the cost.

## Next Actions
- Draft the Phase 1 implementation spike: AD-backed acknowledgement flow (Access `Audit` table extension, parser telemetry hooks, operator UI prompts).
- Define safeguards for the local fallback (password complexity enforcement, retry throttling, audit logging).
- Capture policy approvals and rollout notes in `docs/StateTrace_Consolidated_Plans.md#plan-f-security-identity-online-mode`.
- Re-evaluate Azure AD device-code viability once online tooling is approved and guardrails (`Tools/NetworkGuard.psm1`) are in use.

## Open Questions
- Do we need to support acknowledgement from headless automation (API tokens)?
- What audit retention period is mandated by compliance?
- Can we rely on an existing secrets vault for token caching?
