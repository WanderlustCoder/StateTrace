# ADR 0004: Controlled Online Mode & Dev-Seat Tooling

## Status
Accepted – 2025-09-30

## Context
The project originally operated in an **offline-only** posture with a “scripts-only runtime.” In practice, development is faster and safer if engineers (and AI agents under supervision) can:
- Fetch documentation, data fixtures, and vendor CLIs from the internet.
- Install local tooling (e.g., Python, Git, Graphviz) on **developer machines**.

Customers still expect a **zero-install runtime** (PowerShell + Access only). We therefore distinguish **runtime dependencies** from **developer tooling**.

## Decision
Adopt a **dual-mode policy**:
- **Runtime (default):** No internet required; no compiled dependencies distributed with the product; outputs remain `.ps1` + `.accdb`.
- **Dev Mode (opt-in):** Internet access and dev-seat binaries are allowed behind guardrails. Dev tools are never packaged with releases.

## Guardrails (Dev Mode)
- Require explicit opt-in via environment flags: `STATETRACE_AGENT_ALLOW_NET=1`, `STATETRACE_AGENT_ALLOW_INSTALL=1`.
- All downloads must go through `Tools/NetworkGuard.psm1` (allowlist + TLS + hash verification + logging).
- Installation is performed by `Tools/Bootstrap-DevSeat.ps1` using pinned versions.
- Record an **Agent Session Log** for each network/install operation (what/why/where, hashes, versions).
- Generated artefacts must remain compatible with the offline runtime.

## Consequences
- **Pros:** Faster iteration; easier metrics/visualisation and test generation; clearer provenance of external assets.
- **Cons:** Larger attack surface on dev seats; more operational policy to maintain.
- **Mitigations:** Strict allowlists, version pinning, SBOM and per-session logs; keep runtime offline-ready.

## Alternatives Considered
- Keep offline-only (slower research and onboarding).
- Ship compiled helpers in runtime (violates distribution simplicity).

## Follow-ups
- Add “Online Mode” section to Security guidelines.
- Provide allowlist + hashes in `Tools/Bootstrap-DevSeat.ps1`.
- Update agent prompt to recognise capability flags.
