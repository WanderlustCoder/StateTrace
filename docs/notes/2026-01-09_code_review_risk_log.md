# Code review risk log (2026-01-09)

Track risks discovered during the review and link them to the formal risk register when needed.

| Risk ID | Description | Impact | Mitigation | Owner | Status | Risk register link | Evidence |
|---------|-------------|--------|------------|-------|--------|--------------------|----------|
| CR-R001 | Decision tree conditions execute via Invoke-Expression (CR-007). | Potential arbitrary code execution if untrusted trees are loaded. | Replace with safe expression evaluator and restrict condition syntax. | Engineering | Mitigated | docs/RiskRegister.md#L?? | Modules/DecisionTreeModule.psm1:512 |
| CR-R002 | API server allows unauthenticated access when ApiKey not set (CR-027). | Data exposure if bound beyond localhost. | Require ApiKey or enforce localhost binding unless explicitly overridden. | Integration | Mitigated | docs/RiskRegister.md#L?? | Tools/Start-StateTraceApi.ps1:200 |
| CR-R003 | Switch tooling embeds RADIUS secrets/test credentials (CR-030). | Credential leakage in repo. | Parameterize secrets and move to secure local config. | Ops | Mitigated | docs/RiskRegister.md#L?? | Tools/Switch-ConfigRadius.ps1:35 |
| CR-R004 | Fixture logs include real-looking device identifiers (CR-032). | Data hygiene/privacy risk if fixtures leak customer identifiers. | Sanitize fixtures and add redaction gate. | QA | Mitigated | docs/RiskRegister.md#L?? | Tests/Fixtures/LiveSwitch/LAB-C9200L-AS-01.log:60 |
| CR-R005 | Runtime .accdb files present in repo tree (CR-033). | Risk of committing sensitive runtime data. | Remove runtime .accdb; enforce gitignore/pre-commit checks; move data to Samples if needed. | Docs/Ops | Mitigated | docs/RiskRegister.md#L?? | Data/BOYO/BOYO.accdb (removed 2026-01-10) |
