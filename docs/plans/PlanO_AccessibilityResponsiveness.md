# Plan O - Accessibility & UI Responsiveness

<!-- LANDMARK: ST-E-001 telemetry gates link -->
Telemetry gates: [docs/telemetry/Automation_Gates.md](../telemetry/Automation_Gates.md).

## Objective
Improve the WPF shell???s accessibility, layout adaptability, and perceived responsiveness across Summary, Interfaces, SPAN, Templates, Alerts, Compare, and Help views while keeping telemetry and smoke coverage in lockstep.

## Current status (2025-12)
- UI smoke scripts exist (`Invoke-SpanViewSmokeTest`, `Invoke-InterfacesViewSmokeTest`) but do not assert accessibility or low-latency interaction thresholds.
- UI freshness indicators and user-action telemetry are planned under Plan H, but accessibility specifics (keyboard nav, screen reader hints, color contrast) are not tracked.
- MainWindow code-behind still contains service logic (telemetry publishing, parser orchestration) that complicates UI-only validation.

## Active work
| ID | Title | Owner | Status | Notes |
|----|-------|-------|--------|-------|
| ST-O-001 | Accessibility audit & checklist | UI | Done - 2026-01-04 | Created `docs/Accessibility_Checklist.md` covering keyboard navigation, focus order, color contrast, and screen reader compatibility per view. Added `Tools/Test-Accessibility.ps1` to run static XAML analysis for AutomationProperties, TabIndex, and FocusVisualStyle. Reports saved to `Logs/Accessibility/`. |
| ST-O-002 | Responsive layout tuning | UI | Done - 2026-01-04 | Created `Tools/Test-ResponsiveLayout.ps1` to validate XAML for: MinWidth/MinHeight settings, Grid flexibility (Star vs fixed sizing), ScrollViewer wrapping, high-DPI settings (UseLayoutRounding), DataGrid column flexibility, TextBlock wrapping. Analyzed 10 views, found 42 recommendations for responsive improvements. Use `-FailOnIssues` for CI. |
| ST-O-003 | UI responsiveness telemetry | Telemetry | Done - 2026-01-04 | Created `Tools/Measure-UiResponsiveness.ps1` for single-action timing and `Tools/Test-UiResponsiveness.ps1` for comprehensive test suite (9 actions: TabSwitch, SearchApply, FilterApply, DataGridSort, HostDropdown, TemplateLoad, SpanRefresh, AlertsRefresh, HelpDialog). Thresholds configurable, `-FailOnSlow` for CI. Reports to `Logs/Reports/UiResponsiveness-*.json`. |
| ST-O-004 | Code-behind reduction | UI | Backlog | Move non-UI logic from `Main/MainWindow.ps1` into services (see Plan L) to reduce UI thread stalls and simplify smoke coverage. |

## Recently delivered
- Plan created to centralize accessibility and responsiveness work.

## Automation hooks
- Smokes: `Tools\Invoke-SpanViewSmokeTest.ps1 -Hostname <host> -PassThru`, `Tools\Invoke-InterfacesViewSmokeTest.ps1 -Verbose` (extend to check keyboard navigation and latency).
- UI latency probes (proposed): wrap key actions with stopwatch logging in smoke scripts; fail if > target thresholds.

## Telemetry gates
- Keyboard navigation covers all primary views; focus order matches visual order.
- Color contrast meets minimum AA for critical text/controls in dark/light themes.
- Tab switches/search apply/Compare load complete under target latency (set thresholds per view).
- UI smokes fail when accessibility checks or latency thresholds regress.

## References
- `docs/plans/PlanH_UserExperience.md` (UX/adoption context).
- `docs/plans/PlanL_ModuleDecomposition.md` (moving services out of MainWindow).
- `docs/UI_Smoke_Checklist.md` (baseline smoke steps to extend).

