# Plan D Addendum - Port Reorg 12-Port Paging Mode

## Context
Port Reorg currently lists all ports in a single scrollable surface. For larger switches, operators must scroll to find ports, which can make “move labels/profiles between ports” workflows harder to follow. Many modern access switches are organized in **12-port blocks**, so a paged view can better match how operators think and work.

This addendum captures a plan to add an **optional 12-port paging mode** while keeping the underlying Port Reorg state and script generation unchanged.

## UX Goals
- Offer a toggle: **Single List** (current) vs **Paged (12)**.
- Make it easy to focus on one 12-port block at a time.
- Keep **Parking** visible/persistent regardless of page, with its own scroll bar.
- Ensure paging only changes presentation (no changes to how scripts are generated).

## Design Outline
### Layout
- Split the window into two panes:
  - **Parking (persistent)**: left pane, independently scrollable.
  - **Ports (paged)**: right pane, includes page controls (Prev/Next + page selector) and the current page’s ports.

### View-state model
- Keep one authoritative model:
  - `AllPorts` (sorted, stable order)
  - `Assignments` (port ⇄ label/profile mapping)
- Add paging state:
  - `PageSize = 12` (only when paging mode enabled)
  - `CurrentPage`
  - `VisiblePorts` computed as the slice of `AllPorts`
- Script generation always uses `AllPorts` + `Assignments` (never `VisiblePorts`).

### Drag/drop semantics
- Use stable port identifiers (port name/key), not visual indices, so paging doesn’t break moves.
- Recommended cross-page approach (lowest complexity): move labels via **Parking** (drag to Parking, switch page, drag onto target port).
- Optional later enhancement: explicit “Move To…” action to avoid cross-page drag.

### Preferences
- Persist the paging mode (and last chosen page size/mode if expanded later) in settings so users don’t re-enable it each session.

## Implementation Steps
1. **Audit current Port Reorg UI/bindings**
   - Identify how ports are rendered and how Parking is represented.
   - Confirm where sorting/order is established and how labels map to ports.
2. **Add paging controls + persistent Parking layout**
   - Add mode toggle (Single vs Paged).
   - Add paging toolbar (Prev/Next + page selector) for the ports pane.
   - Place Parking in a dedicated `ScrollViewer` so it stays visible across pages.
3. **Refactor view-state for paging**
   - Introduce `PageSize`, `CurrentPage`, and computed `VisiblePorts`.
   - Ensure page changes don’t discard in-flight edits.
4. **Update drag/drop handlers for paging**
   - Resolve port targets by stable ID.
   - Keep Parking semantics consistent across modes.
5. **Add tests**
   - Unit tests for paging slice logic (12-per-page), sorting stability, and assignment preservation across page changes.
   - Regression test that `New-PortReorgScripts` output is identical regardless of paging mode.
6. **Document in help**
   - Add a Help section describing paging mode, Parking persistence, and recommended cross-page move workflow.

## Acceptance Criteria
- Toggling paging on/off never changes assignments; it only changes presentation.
- Parking is always visible and independently scrollable.
- Generating scripts produces identical output for the same underlying assignments, regardless of paging mode.
- Paging handles common switch sizes cleanly (24/48/96 ports) with correct page counts.

## Touchpoints
- UI: `Views/PortReorgWindow.xaml`
- Wiring/state: `Modules/PortReorgViewModule.psm1`
- Script generation (must remain mode-independent): `Modules/PortReorgModule.psm1`

