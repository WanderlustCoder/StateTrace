# Plan AF: Tab Consolidation & Navigation Redesign

## Objective
Consolidate 18 top-level tabs into 9 using nested left-side vertical TabControls, reducing cognitive load while preserving access to all features.

## Owner(s)
UI / UX

## Key Telemetry / Automation Hooks
- UI smoke tests: `Tools\Invoke-InterfacesViewChecklist.ps1`
- Tab visibility handlers in `MainWindow.ps1`
- Lazy loading via `IsVisibleChanged` events

---

## Structure

### Before (18 tabs)
Summary | Interfaces | SPAN | Search | Templates | Alerts | Cmd Ref | Calculator | Troubleshoot | Log Analysis | Cables | IPAM | Config | Inventory | Changes | Docs | Capacity | Topology

### After (9 tabs)
| Tab | Type | Contents |
|-----|------|----------|
| Summary | Top-level | Device overview |
| Interfaces | Top-level | Interface details |
| SPAN | Top-level | Spanning tree |
| Search | Top-level | Cross-device search |
| Alerts | Top-level | Issues/anomalies |
| Documentation | Container | Generator, Config Templates, Templates, Cmd Reference |
| Infrastructure | Container | Topology, Cables, IPAM, Inventory |
| Operations | Container | Changes, Capacity, Log Analysis |
| Tools | Container | Troubleshoot, Calculator |

---

## Active Work

| Task ID | Description | Status |
|---------|-------------|--------|
| ST-AF-001 | Create container XAML views (4 files) | Done |
| ST-AF-002 | Create container view modules (4 files) | Done |
| ST-AF-003 | Update MainWindow.xaml with container tabs | Done |
| ST-AF-004 | Update MainWindow.ps1 for container initialization | Done |
| ST-AF-005 | Update ModulesManifest.psd1 | Done |
| ST-AF-006 | UI smoke tests | Done |

---

## Recently Delivered

| Date | Item | Notes |
|------|------|-------|
| 2026-01-05 | Container XAML views | DocumentationContainerView, InfrastructureContainerView, OperationsContainerView, ToolsContainerView |
| 2026-01-05 | Container view modules | With lazy sub-view loading via SelectionChanged events |
| 2026-01-05 | MainWindow.xaml update | Replaced 13 TabItems with 4 container tabs |
| 2026-01-05 | MainWindow.ps1 update | Added container views to priority list, excluded nested views |
| 2026-01-05 | UI smoke tests | ContainerViews.Tests.ps1 with 42 tests validating XAML structure, module exports, and lazy loading |

---

## Files Created/Modified

**New Files (9):**
- `Views/DocumentationContainerView.xaml`
- `Views/InfrastructureContainerView.xaml`
- `Views/OperationsContainerView.xaml`
- `Views/ToolsContainerView.xaml`
- `Modules/DocumentationContainerViewModule.psm1`
- `Modules/InfrastructureContainerViewModule.psm1`
- `Modules/OperationsContainerViewModule.psm1`
- `Modules/ToolsContainerViewModule.psm1`
- `Modules/Tests/ContainerViews.Tests.ps1` - 42 Pester tests for container views

**Modified Files:**
- `Main/MainWindow.xaml` - Replaced 13 TabItems with 4 container tabs
- `Main/MainWindow.ps1` - Added container views, excluded nested views from direct init
- `Modules/ModulesManifest.psd1` - Added container view modules

---

## Implementation Notes

### Left-Side Vertical Tabs
All container views use `TabStripPlacement="Left"` for vertical sub-navigation:
- Horizontal tab headers (no rotation) for readability
- MinWidth="130" for consistent button sizing
- Theme-aware styling via DynamicResource bindings

### Lazy Loading
Sub-views are only initialized when their tab is first selected:
- `$script:InitializedSubViews` hashtable tracks loaded views
- `SelectionChanged` event triggers initialization
- First tab is initialized immediately for responsiveness

### Backward Compatibility
- Original view modules unchanged
- Container modules call existing `Initialize-*View` or `New-*View` functions
- No changes to business logic or data layer
