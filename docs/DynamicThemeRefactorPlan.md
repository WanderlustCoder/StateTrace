# Dynamic Theme Refactor Plan

## Objectives
- Allow switching among multiple visual themes without code edits or application restarts.
- Centralize palette and style tokens so every view and module reads from a single source of truth.
- Preserve existing usability (contrast, accessibility, performance) while enabling future theme additions.
- Minimize regression risk by refactoring in small, verifiable slices with shared resources and automated checks.

## Current Theme Implementation Audit
### Primary entry point
- `Main/MainWindow.xaml`: window background `#EAF0F8`; toolbars and tab headers use `#001F3F`; action buttons use `#FFD700`/`Black`; toolbar text uses `White`; compare sidebar background `#F7FAFC`.

### Views
- `Views/AlertsView.xaml`: outer grid `#001F3F`; DataGrid uses `#F7F9FC`, `#E7ECF5`, `#F1F5FA`, selection highlight `#FFF4BA`; buttons `#FFD700`; text `White`.
- `Views/CompareView.xaml`: header `#001F3F` with `White` text; cards `White` with `#C0C0C0` border; divider `#E0E6F0`; close button `#FFD700`; accent text `#001F3F`; diff text `Red`.
- `Views/InterfacesView.xaml`: global background `#001F3F`; panel buttons `#FFD700`; repeated text labels `White`; DataGrid surfaces `#F7F9FC` etc.; multiple `Style` triggers hardcode `Green`, `Red`, `Blue`, `Purple`, `Goldenrod`, `Gray`; selection highlight `#FFF4BA`.
- `Views/SearchInterfacesView.xaml`: outer background `#001F3F`; inputs `#F7F9FC`/`#C0C0C0`; filters use `White` text; buttons `#FFD700`; DataGrid palette mirrors InterfacesView.
- `Views/SpanView.xaml`, `Views/SummaryView.xaml`, `Views/TemplatesView.xaml`: same navy/gold/light palette; `TemplatesView` duplicates panel/background colors and button styling.
- `Views/HelpWindow.xaml`: background `#F7F9FC`; relies on default button styling but no dynamic hooks.

### Modules and runtime code
- `Modules/InterfaceModule.psm1`: vendor detection maps to `[System.Windows.Media.Brushes]::DodgerBlue`, `Goldenrod`, `MediumSeaGreen`; template fallback color `Gray`; outputs color names consumed by XAML triggers.
- `Modules/CompareViewModule.psm1`: applies `[Brushes]::$color` from `PortColor` fields, defaulting to `Black`.
- Template data (`Templates/*.json`): each template declares a semantic `color` (`Green`, `Blue`, `Purple`, `Red`) that ultimately drives brush selection.

### Palette summary
Hex values in use: `#001F3F`, `#FFD700`, `#F7F9FC`, `#F7FAFC`, `#EAF0F8`, `#E7ECF5`, `#F1F5FA`, `#C0C0C0`, `#E0E6F0`, `#FFF4BA`.
Named brushes in use: `White`, `Black`, `Green`, `Red`, `Blue`, `Purple`, `Goldenrod`, `Gray`, `DodgerBlue`, `MediumSeaGreen`.

## Target Theme System
### Theme tokens
Define a shared vocabulary that maps UI intent to a key. Proposed initial set:
- `Theme.Window.Background`, `Theme.Window.Text`
- `Theme.Toolbar.Background`, `Theme.Toolbar.Text`
- `Theme.Surface.Primary`, `Theme.Surface.Secondary`, `Theme.Surface.Border`
- `Theme.Input.Background`, `Theme.Input.Border`, `Theme.Input.Text`
- `Theme.Button.Primary.Background`, `Theme.Button.Primary.Text`
- `Theme.Button.Secondary.Background`, `Theme.Button.Secondary.Text`
- `Theme.DataGrid.Background`, `Theme.DataGrid.Row`, `Theme.DataGrid.RowAlt`, `Theme.DataGrid.Border`, `Theme.DataGrid.SelectionBackground`, `Theme.DataGrid.SelectionText`
- `Theme.Text.Primary`, `Theme.Text.Muted`, `Theme.Icon.Accent`
- Semantic statuses: `Theme.Status.Success`, `Theme.Status.Warning`, `Theme.Status.Info`, `Theme.Status.Danger`, `Theme.Status.Neutral`
- Template/vendor accents: `Theme.Template.Match`, `Theme.Template.Existing`, `Theme.Template.Missing`, `Theme.Vendor.Cisco`, `Theme.Vendor.Brocade`, `Theme.Vendor.Arista`

### Theme definition format
- Store themes as JSON (e.g., `Themes/blue-angels.json`, `Themes/slate.json`) with key/value pairs for tokens.
- Allow inheritance or fallback to a base theme for missing keys (e.g., `base.json`).
- Include metadata (display name, author, created date) for UI listing and future theming doc generation.
- Example skeleton:
  ```json
  {
    "name": "Blue Angels",
    "extends": "base",
    "tokens": {
      "Theme.Window.Background": "#EAF0F8",
      "Theme.Button.Primary.Background": "#FFD700",
      "Theme.Status.Success": "#2ECC71",
      "Theme.Status.Danger": "#E74C3C"
    }
  }
  ```

Initial bundle: ship the existing "Blue Angels" palette plus a "W40K Salamanders" palette inspired by the chapter's green, black, and flame accents.

### Runtime theme manager
- Create `Modules/ThemeModule.psm1` that exposes:
  - `Get-StateTraceTheme`, `Set-StateTraceTheme -Name <theme>`
  - `Get-ThemeToken -Key <token>` returning color strings or brushes
  - `Get-ThemeBrush` / `Get-ThemeColor` helpers caching `SolidColorBrush` instances
  - Event `StateTraceThemeChanged` to notify modules when resources refresh
- Manager loads JSON, merges with defaults, then materializes a `ResourceDictionary` containing `SolidColorBrush` entries keyed by token and convenience aliases (e.g., `PrimaryBackgroundBrush`).
- Inject the dictionary into `Application.Current.Resources.MergedDictionaries` so all `DynamicResource` references update when the dictionary is replaced.

### Resource strategy
- Add `Resources/ThemeResources.xaml` that defines `DynamicResource` aliases for shared styles (buttons, DataGrid) referencing tokens.
- Create `Resources/SharedStyles.xaml` with reusable `Style` definitions (primary toolbar, DataGrid baseline) so each view can reference them instead of redefining setters.
- Ensure `MainWindow.ps1` loads shared resources and keeps a handle to the merged dictionary for hot-swapping.

### Data-driven colors
- Map template `color` field to semantic keys rather than raw brush names (e.g., `Success`, `Info`, `Warning`, `Danger`). Maintain backwards compatibility by translating legacy values during load.
- In `InterfaceModule.psm1`, replace brush constants with theme token lookups (e.g., `Get-ThemeBrush -Key 'Theme.Vendor.Cisco'`).
- Update XAML `Style` triggers to set `Foreground` via `{DynamicResource Theme.Status.Success}` rather than literal `Green`/`Red`.

### Theme selection UX
- Add a theme selector (ComboBox or menu) to `Main/MainWindow.xaml` toolbar alongside filters.
- Ship Blue Angels and W40K Salamanders as built-in options so multiple palettes are available immediately.
- Persist last selected theme (e.g., `%AppData%\StateTrace\settings.json`), defaulting to Blue Angels on first startup and reusing the saved choice until the user changes it.
- Display current theme name in Help/About for clarity.

## Refactor Work Breakdown
1. **Scaffolding**
   - Create `Themes` directory with `base.json`, migrated `blue-angels.json` (shipping default), and a new `w40k-salamanders.json` built around the Warhammer 40K Salamanders palette.
   - Add shared resource dictionaries (`Resources/ThemeResources.xaml`, `Resources/SharedStyles.xaml`).
2. **Theme manager module**
   - Implement JSON loader, resource dictionary builder, and helper functions in `Modules/ThemeModule.psm1`.
   - Update `ModulesManifest.psd1` to auto-import the theme module before UI modules.
3. **Main window integration**
   - Load shared dictionaries in `MainWindow.ps1` before rendering child views.
   - Replace hardcoded colors in `Main/MainWindow.xaml` with `DynamicResource` tokens; hook theme selector UI to `Set-StateTraceTheme`.
4. **View refactors (iterate per view)**
   - For each XAML view, swap literal brushes for tokens/styles, remove duplicated inline styles.
   - Use the shared DataGrid style to consolidate common settings (backgrounds, borders, selection).
   - Verify all `Style` triggers reference semantic resources.
5. **Module adjustments**
   - Replace brush constants in PowerShell modules with theme lookups.
   - Translate template color strings to semantic keys when building view models.
   - Ensure runtime-generated controls (e.g., dynamic `ComboBoxItem`s) pick up theme styles.
6. **Template data update**
   - Migrate `Templates/*.json` `color` properties to semantic keys; provide migration script for existing files.
   - Update any documentation about template color meanings.
7. **Runtime switching & persistence**
   - Implement theme switch command handler, settings persistence, and initial theme load (use saved value or default to Blue Angels).
   - Ensure theme changes propagate to already-loaded child views (verify with dynamic resource swap).
8. **Testing and polish**
   - Execute manual regression checks per view for both default and alternate themes.
   - Add Pester tests (or lightweight PowerShell tests) that load each theme file, instantiate the resource dictionary, and confirm required tokens are present.
   - Validate accessibility guidelines (contrast ratios) for each provided theme.

## Testing & Validation Plan
- Automated: PowerShell tests to ensure every token listed in shared styles exists for each theme; validate JSON schema using `Test-Json` with a `themes.schema.json`.
- Manual: run end-to-end flows (parse logs, switch tabs, export data) while toggling themes to confirm live updates.
- Visual regression: capture reference screenshots for critical views under each theme; optionally integrate with image diff tooling for future regressions.
- Accessibility: use WCAG contrast calculators to verify key text/background pairs; adjust tokens as needed.

## Risks & Mitigations
- **Incomplete token coverage**: mitigate by adding a validation script that scans XAML for residual hex codes or named brushes after refactor.
- **Performance lag on theme switch**: keep dictionaries lightweight and reuse `SolidColorBrush` instances; throttle repeated switches via UI disable during update.
- **Template compatibility**: provide backward-compatible translation for legacy color strings and document new semantics for third-party templates.
- **User confusion with multiple styles**: bundle at least two polished themes (Blue Angels default, W40K Salamanders alt) so the selector has meaningful options at launch.

## Open Questions
- Should themes also govern typography (font sizes/families) or remain color-only in v1?
- Do we need per-tenant branding support (logos, imagery) beyond color alterations?
- Where should settings persist in locked-down environments (registry vs JSON in Documents)?
- Are there compliance requirements (e.g., Section 508) that demand specific contrast thresholds for all shipped themes?

## Success Criteria
- All previous hex/named colors replaced by tokenized references.
- Switching themes at runtime updates every visible control without restarting.
- Default (Blue Angels) theme visually matches current UI to avoid regressions.
- Ship the existing Blue Angels theme as the default and include the W40K Salamanders theme to prove extensibility and validate the multi-theme pipeline.
