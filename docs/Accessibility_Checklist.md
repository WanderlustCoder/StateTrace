# StateTrace Accessibility Checklist (ST-O-001)

This checklist ensures the WPF shell meets accessibility requirements for keyboard navigation, focus order, color contrast, and screen reader compatibility. Run these checks after UI changes and attach findings to session logs.

## Quick Reference

| Category | Minimum Standard | Tool/Method |
|----------|------------------|-------------|
| Keyboard Navigation | All controls reachable via Tab | Manual + automation |
| Focus Order | Matches visual reading order (LTR, top-to-bottom) | Manual + automation |
| Color Contrast | WCAG AA (4.5:1 text, 3:1 large text) | Contrast analyzer |
| Screen Reader | AutomationProperties set on key controls | XAML inspection |
| Focus Visibility | Visible focus indicator on all focusable elements | Visual inspection |

## Keyboard Navigation Checklist

### Summary View
- [ ] Tab moves focus through: Host dropdown -> Scan Logs button -> Load from DB button -> Site filter -> Status strip
- [ ] Enter activates focused button
- [ ] Escape closes any open dropdown
- [ ] Arrow keys navigate dropdown items

### Interfaces View
- [ ] Tab moves through: Filter input -> Filter button -> DataGrid -> Column headers
- [ ] Arrow keys navigate DataGrid rows
- [ ] Enter on row expands/selects
- [ ] F2 or Enter edits if applicable
- [ ] Ctrl+Home/End jumps to first/last row

### Search View
- [ ] Tab moves through: Search input -> Regex toggle -> Search button -> Results grid
- [ ] Enter in search input triggers search
- [ ] Results grid supports keyboard navigation

### SPAN View
- [ ] Tab reaches Refresh button and data grid
- [ ] DataGrid supports standard keyboard navigation

### Templates View
- [ ] Tab moves through: Template list -> Preview pane -> Copy button
- [ ] Enter loads selected template
- [ ] Copy button accessible via keyboard

### Alerts View
- [ ] Tab moves through: Status filter -> Auth filter -> DataGrid
- [ ] Filter dropdowns operable via keyboard

### Compare View
- [ ] Tab moves through: Host 1 dropdown -> Host 2 dropdown -> Diff list -> Config pane
- [ ] Enter expands/collapses diff items

### Help Dialog
- [ ] Tab moves through dialog controls
- [ ] Escape closes dialog
- [ ] Links accessible via keyboard

## Focus Order Verification

For each view, verify focus order matches visual layout:
1. Set focus to first control (click or Tab from toolbar)
2. Press Tab repeatedly and note the order
3. Compare with visual left-to-right, top-to-bottom order
4. Document any discrepancies

### Expected Focus Order by View
| View | Expected Order |
|------|----------------|
| Summary | Host dropdown -> Scan Logs -> Load from DB -> Site filter -> Metadata labels |
| Interfaces | Filter input -> Apply -> Clear -> DataGrid |
| Search | Query input -> Regex toggle -> Search -> Clear -> Results grid |
| SPAN | Refresh -> DataGrid |
| Templates | Template list -> Preview -> Copy |
| Alerts | Status filter -> Auth filter -> Grid |
| Compare | Host 1 -> Host 2 -> Add -> Diff list -> Config pane |

## Color Contrast Checks

### Light Theme
- [ ] Primary text on background: >= 4.5:1
- [ ] Large text/headers on background: >= 3:1
- [ ] Button text on button background: >= 4.5:1
- [ ] Link text distinguishable from body text
- [ ] Status indicators (red/green/yellow) distinguishable without color alone

### Dark Theme
- [ ] Primary text on dark background: >= 4.5:1
- [ ] Selected row text remains readable
- [ ] Status colors maintain contrast
- [ ] Focus indicators visible against dark background

### Tools for Contrast Checking
- Windows: Colour Contrast Analyser
- Online: WebAIM Contrast Checker
- PowerShell: Measure color values from XAML resources

## Screen Reader Compatibility

### XAML AutomationProperties
Check that key controls have these properties set:
- [ ] `AutomationProperties.Name` on buttons without text labels
- [ ] `AutomationProperties.LabeledBy` on input fields
- [ ] `AutomationProperties.HelpText` on complex controls
- [ ] `AutomationProperties.ItemStatus` on status indicators

### Test with Narrator (Windows)
1. Enable Narrator (Win+Ctrl+Enter)
2. Navigate each view using Tab
3. Verify Narrator reads:
   - Control type (button, textbox, datagrid)
   - Control name/label
   - Current value (for inputs)
   - State (disabled, selected, etc.)

### Key Controls to Verify
| Control | Expected Announcement |
|---------|----------------------|
| Host dropdown | "Host, combo box, [current value]" |
| Scan Logs button | "Scan Logs, button" |
| Filter input | "Filter, text box" |
| DataGrid | "[view name] table, [row count] items" |
| Status bar | "[status text]" |

## Focus Visibility

- [ ] All focusable controls show visible focus indicator
- [ ] Focus indicator has sufficient contrast (3:1 minimum)
- [ ] Focus indicator is consistent across views
- [ ] Focus indicator works in both light and dark themes

## Automated Accessibility Tests

Run `Tools\Test-Accessibility.ps1` to check:
- Focus order matches expected sequence
- Tab key reaches all primary controls
- No orphaned controls (reachable only by mouse)
- AutomationProperties defined on key elements

Example:
```powershell
pwsh -STA -File Tools\Test-Accessibility.ps1 -View Interfaces -PassThru
```

## Findings Template

When documenting accessibility issues, use this format:

```
### [Issue Title]
- **View**: [Summary/Interfaces/Search/etc.]
- **Control**: [Button/DataGrid/etc.]
- **Category**: [Keyboard/FocusOrder/Contrast/ScreenReader]
- **Severity**: [Critical/Major/Minor]
- **Description**: [What is wrong]
- **Expected**: [What should happen]
- **Recommendation**: [How to fix]
```

## Reporting

After completing the checklist:
1. Save findings to `Logs/Accessibility/Accessibility-<date>.md`
2. Link findings in session log
3. Create tasks for any Critical/Major issues found
4. Update Plan O with findings summary

## References

- [WCAG 2.1 Guidelines](https://www.w3.org/WAI/WCAG21/quickref/)
- [WPF Accessibility Best Practices](https://docs.microsoft.com/en-us/dotnet/framework/wpf/advanced/accessibility)
- `docs/plans/PlanO_AccessibilityResponsiveness.md`
- `docs/UI_Smoke_Checklist.md`
