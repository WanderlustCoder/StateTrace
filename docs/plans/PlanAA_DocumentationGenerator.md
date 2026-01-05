# Plan AA - Network Documentation Generator

<!-- LANDMARK: ST-E-001 telemetry gates link -->
Telemetry gates: [docs/telemetry/Automation_Gates.md](../telemetry/Automation_Gates.md).

## Objective
Automatically generate comprehensive network documentation from collected device data. Produce professional as-built documents, site summaries, device inventories, and operational runbooks without manual data gathering.

## Problem Statement
Network teams spend significant time:
- Creating and maintaining network documentation manually
- Updating documents when network changes occur
- Producing consistent documentation across different sites
- Generating reports for audits, compliance, and management
- Keeping documentation synchronized with actual network state

## Current status (2026-01)
- Device and interface data is collected but not formatted for documentation
- No automated document generation
- Manual documentation quickly becomes stale
- No standardized documentation templates

## Proposed Features

### AA.1 As-Built Documentation
- **Site Summary Documents**: Auto-generate per-site docs with:
  - Executive summary
  - Network architecture overview
  - Device inventory tables
  - VLAN summary
  - IP addressing scheme
  - Physical layout reference
- **Device Documentation**: Per-device detail pages:
  - Hardware specifications
  - Interface inventory
  - Configuration highlights
  - Connected devices
  - Port utilization
- **Network Diagrams**: Integrate with Plan W topology views

### AA.2 Document Templates
- **Template Library**: Pre-built templates for:
  - Site as-built document
  - Device configuration summary
  - VLAN reference guide
  - IP address allocation
  - Cable/port matrix
  - Disaster recovery procedures
- **Custom Templates**: User-defined templates with:
  - Variable placeholders
  - Conditional sections
  - Loop constructs for lists
  - Formatting controls

### AA.3 Report Generation
- **Executive Reports**: High-level summaries for management
- **Technical Reports**: Detailed technical documentation
- **Audit Reports**: Compliance and inventory reports
- **Change Reports**: Documentation of recent changes
- **Comparison Reports**: Current vs baseline state

### AA.4 Output Formats
- **Microsoft Word** (.docx): Formatted documents with styles
- **PDF**: Print-ready documents
- **HTML**: Web-viewable documentation
- **Markdown**: For version control and wikis
- **Excel**: Tabular data exports
- **Confluence/SharePoint**: Wiki-ready format

### AA.5 Documentation Scheduling
- **Scheduled Generation**: Auto-regenerate on schedule
- **Change-Triggered**: Regenerate when data changes
- **Version Control**: Track document versions
- **Distribution**: Auto-save to specified locations

### AA.6 Content Features
- **Table of Contents**: Auto-generated navigation
- **Cross-References**: Links between related sections
- **Index**: Searchable keyword index
- **Glossary**: Technical term definitions
- **Appendices**: Supporting data tables

## Active work
| ID | Title | Owner | Status | Notes |
|----|-------|-------|--------|-------|
| ST-AA-001 | Document template engine | Tools | Pending | Template parsing and rendering |
| ST-AA-002 | As-built generator | Tools | Pending | Site/device documentation |
| ST-AA-003 | Word/PDF export | Tools | Pending | Professional format output |
| ST-AA-004 | Template library | Docs | Pending | Pre-built documentation templates |
| ST-AA-005 | Scheduled generation | Tools | Pending | Automated doc refresh |
| ST-AA-006 | Documentation UI | UI | Pending | Preview and generation interface |

## Data Model (Proposed)

### DocumentTemplate Table
```
TemplateID (PK), TemplateName, TemplateType, Category, Content,
Variables, CreatedDate, ModifiedDate, Author, Version
```

### GeneratedDocument Table
```
DocumentID (PK), TemplateID (FK), Title, Scope, GeneratedDate,
OutputFormat, FilePath, FileHash, Parameters, GeneratedBy
```

### DocumentSchedule Table
```
ScheduleID (PK), TemplateID (FK), Scope, Frequency, NextRunTime,
LastRunTime, OutputPath, IsEnabled, NotifyOnComplete
```

## Testing Requirements

### Unit Tests (`Modules/Tests/DocumentationGenerator.Tests.ps1`)

```powershell
Describe 'Documentation Generator' -Tag 'Documentation' {

    Describe 'Template Engine' {
        It 'substitutes simple variables' {
            $template = 'Site: {{site_name}}, Location: {{location}}'
            $vars = @{ site_name = 'Campus Main'; location = 'Building A' }

            $result = Expand-DocumentTemplate -Template $template -Variables $vars

            $result | Should -Be 'Site: Campus Main, Location: Building A'
        }

        It 'handles missing variables gracefully' {
            $template = 'Device: {{hostname}}, IP: {{ip_address}}'
            $vars = @{ hostname = 'SW-01' }

            $result = Expand-DocumentTemplate -Template $template -Variables $vars

            $result | Should -Match 'Device: SW-01'
            $result | Should -Match '\{\{ip_address\}\}|N/A'
        }

        It 'processes conditional sections' {
            $template = @'
{{#if has_redundancy}}
Redundancy: Configured
{{else}}
Redundancy: Not configured
{{/if}}
'@
            $result1 = Expand-DocumentTemplate -Template $template -Variables @{ has_redundancy = $true }
            $result2 = Expand-DocumentTemplate -Template $template -Variables @{ has_redundancy = $false }

            $result1 | Should -Match 'Redundancy: Configured'
            $result2 | Should -Match 'Redundancy: Not configured'
        }

        It 'processes loop constructs' {
            $template = @'
VLANs:
{{#each vlans}}
- VLAN {{id}}: {{name}}
{{/each}}
'@
            $vars = @{
                vlans = @(
                    @{ id = 10; name = 'Users' },
                    @{ id = 20; name = 'Voice' }
                )
            }

            $result = Expand-DocumentTemplate -Template $template -Variables $vars

            $result | Should -Match 'VLAN 10: Users'
            $result | Should -Match 'VLAN 20: Voice'
        }
    }

    Describe 'As-Built Generation' {
        It 'generates site summary document' {
            $doc = New-SiteAsBuilt -SiteID 'CAMPUS-MAIN'

            $doc | Should -Not -BeNullOrEmpty
            $doc.Title | Should -Match 'CAMPUS-MAIN'
            $doc.Sections | Should -Contain 'Executive Summary'
            $doc.Sections | Should -Contain 'Device Inventory'
            $doc.Sections | Should -Contain 'VLAN Summary'
        }

        It 'generates device documentation' {
            $doc = New-DeviceDocumentation -DeviceID 'SW-01'

            $doc.Hardware | Should -Not -BeNullOrEmpty
            $doc.Interfaces | Should -Not -BeNullOrEmpty
            $doc.Configuration | Should -Not -BeNullOrEmpty
        }

        It 'includes table of contents' {
            $doc = New-SiteAsBuilt -SiteID 'CAMPUS-MAIN' -IncludeTOC

            $doc.TableOfContents | Should -Not -BeNullOrEmpty
            $doc.TableOfContents.Count | Should -BeGreaterThan 3
        }

        It 'generates cross-references' {
            $doc = New-SiteAsBuilt -SiteID 'CAMPUS-MAIN' -IncludeCrossRefs

            $doc.CrossReferences | Should -Not -BeNullOrEmpty
        }
    }

    Describe 'Output Format Generation' {
        BeforeAll {
            $script:testDoc = New-SiteAsBuilt -SiteID 'TEST-SITE'
            $script:outputPath = Join-Path $env:TEMP 'DocGenTest'
            New-Item -Path $script:outputPath -ItemType Directory -Force | Out-Null
        }

        It 'exports to Word format' {
            $file = Export-Document -Document $testDoc -Format Word `
                -OutputPath (Join-Path $outputPath 'test.docx')

            Test-Path $file | Should -BeTrue
            (Get-Item $file).Length | Should -BeGreaterThan 0
        }

        It 'exports to PDF format' {
            $file = Export-Document -Document $testDoc -Format PDF `
                -OutputPath (Join-Path $outputPath 'test.pdf')

            Test-Path $file | Should -BeTrue
        }

        It 'exports to Markdown format' {
            $file = Export-Document -Document $testDoc -Format Markdown `
                -OutputPath (Join-Path $outputPath 'test.md')

            Test-Path $file | Should -BeTrue
            $content = Get-Content $file -Raw
            $content | Should -Match '^#'  # Starts with heading
        }

        It 'exports to HTML format' {
            $file = Export-Document -Document $testDoc -Format HTML `
                -OutputPath (Join-Path $outputPath 'test.html')

            Test-Path $file | Should -BeTrue
            $content = Get-Content $file -Raw
            $content | Should -Match '<html>'
        }

        AfterAll {
            Remove-Item -Path $script:outputPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Describe 'Report Generation' {
        It 'generates executive summary report' {
            $report = New-ExecutiveReport -Scope 'Enterprise' -Period 'Q4-2025'

            $report.Sections | Should -Contain 'Overview'
            $report.Sections | Should -Contain 'Key Metrics'
            $report.Sections | Should -Contain 'Recommendations'
        }

        It 'generates audit report' {
            $report = New-AuditReport -Standard 'Security-Baseline'

            $report.ComplianceScore | Should -Not -BeNullOrEmpty
            $report.Findings | Should -Not -BeNullOrEmpty
        }

        It 'generates comparison report' {
            $report = New-ComparisonReport -BaselineDate '2025-12-01' -CurrentDate '2026-01-01'

            $report.Changes | Should -Not -BeNullOrEmpty
            $report.Summary | Should -Not -BeNullOrEmpty
        }
    }

    Describe 'Scheduled Generation' {
        It 'creates document schedule' {
            $schedule = New-DocumentSchedule `
                -TemplateID 'SITE-ASBUILT' `
                -Scope 'CAMPUS-MAIN' `
                -Frequency 'Weekly' `
                -OutputPath 'C:\Docs'

            $schedule.ScheduleID | Should -Not -BeNullOrEmpty
            $schedule.NextRunTime | Should -BeGreaterThan (Get-Date)
        }

        It 'calculates next run time correctly' {
            $schedule = New-DocumentSchedule -Frequency 'Daily' -StartTime '06:00'

            $expected = (Get-Date).Date.AddDays(1).AddHours(6)
            $schedule.NextRunTime | Should -BeLessThan $expected.AddMinutes(1)
            $schedule.NextRunTime | Should -BeGreaterThan $expected.AddMinutes(-1)
        }
    }

    Describe 'Template Library' {
        It 'lists available templates' {
            $templates = Get-DocumentTemplates

            $templates.Count | Should -BeGreaterThan 0
            $templates.Name | Should -Contain 'Site-AsBuilt'
            $templates.Name | Should -Contain 'Device-Summary'
        }

        It 'retrieves template by name' {
            $template = Get-DocumentTemplate -Name 'Site-AsBuilt'

            $template | Should -Not -BeNullOrEmpty
            $template.Content | Should -Not -BeNullOrEmpty
            $template.Variables | Should -Not -BeNullOrEmpty
        }
    }
}
```

## UI Mockup Concepts

### Documentation Generator View
```
+------------------------------------------------------------------+
| Network Documentation Generator                                   |
+------------------------------------------------------------------+
| TEMPLATE                          | SCOPE                        |
| [Site As-Built         v]         | Site: [CAMPUS-MAIN    v]     |
|                                   | Devices: [All          v]    |
| FORMAT                            | Include:                     |
| [x] Word (.docx)                  | [x] Table of Contents        |
| [ ] PDF                           | [x] Device Details           |
| [x] Markdown                      | [x] VLAN Summary             |
|                                   | [x] IP Addressing            |
|                                   | [ ] Configurations           |
+------------------------------------------------------------------+
| PREVIEW                                                          |
| +--------------------------------------------------------------+ |
| | # CAMPUS-MAIN Network Documentation                          | |
| |                                                              | |
| | ## Executive Summary                                         | |
| | This document describes the network infrastructure at...     | |
| |                                                              | |
| | ## Device Inventory                                          | |
| | | Hostname | Model | Role | Location |                      | |
| | |----------|-------|------|----------|                      | |
| | | CORE-01  | 9500  | Core | MDF      |                      | |
| +--------------------------------------------------------------+ |
+------------------------------------------------------------------+
| [Generate Document] [Save Template] [Schedule Generation]        |
+------------------------------------------------------------------+
```

### Template Editor
```
+------------------------------------------------------------------+
| Template Editor: Site-AsBuilt                                     |
+------------------------------------------------------------------+
| VARIABLES                         | TEMPLATE CONTENT             |
| site_name (required)              | # {{site_name}} Network Doc  |
| site_location                     |                              |
| generated_date (auto)             | Generated: {{generated_date}}|
| devices[] (list)                  |                              |
| vlans[] (list)                    | ## Device Inventory          |
|                                   | {{#each devices}}            |
| [+ Add Variable]                  | - {{hostname}}: {{model}}    |
|                                   | {{/each}}                    |
|                                   |                              |
|                                   | ## VLAN Summary              |
|                                   | {{#each vlans}}              |
|                                   | | {{id}} | {{name}} |        |
|                                   | {{/each}}                    |
+------------------------------------------------------------------+
| [Validate] [Preview] [Save]                                      |
+------------------------------------------------------------------+
```

### Generated Document Example (Markdown)
```markdown
# CAMPUS-MAIN Network Documentation

**Generated:** 2026-01-04 14:30:00
**Version:** 1.0

## Table of Contents
1. [Executive Summary](#executive-summary)
2. [Device Inventory](#device-inventory)
3. [VLAN Summary](#vlan-summary)
4. [IP Addressing](#ip-addressing)

## Executive Summary
This document provides comprehensive network documentation for the
CAMPUS-MAIN site located at 123 Main Street, Building A.

**Key Statistics:**
- Total Devices: 45
- Total Ports: 2,160
- Active VLANs: 12
- Subnets: 15

## Device Inventory

| Hostname | Vendor | Model | Role | Location | Ports |
|----------|--------|-------|------|----------|-------|
| CORE-01 | Cisco | C9500-24Y4C | Core | MDF-R1-U40 | 28 |
| DS-01 | Cisco | C9300-48P | Distribution | MDF-R1-U38 | 48 |
| DS-02 | Cisco | C9300-48P | Distribution | MDF-R1-U36 | 48 |
...

## VLAN Summary

| ID | Name | Purpose | Subnet | Gateway |
|----|------|---------|--------|---------|
| 10 | Users | End user access | 10.1.10.0/24 | 10.1.10.1 |
| 20 | Voice | VoIP phones | 10.1.20.0/24 | 10.1.20.1 |
| 100 | Management | Device management | 10.1.100.0/24 | 10.1.100.1 |
...
```

## Automation hooks
- `Tools\New-SiteDocumentation.ps1 -Site CAMPUS-MAIN -Format Word`
- `Tools\New-DeviceDocumentation.ps1 -Device SW-01 -Format PDF`
- `Tools\Export-NetworkReport.ps1 -Type Executive -Scope Enterprise`
- `Tools\New-DocumentSchedule.ps1 -Template Site-AsBuilt -Frequency Weekly`
- `Tools\Get-DocumentTemplates.ps1` to list available templates
- `Tools\Test-DocumentTemplate.ps1 -Template custom.tmpl` to validate

## Telemetry gates
- Document generation emits `DocumentGenerated` with type and size
- Export operations emit `DocumentExport` with format and duration
- Template operations emit `TemplateUsage` with template name

## Dependencies
- Device and interface data from existing modules
- Plan V for IP/VLAN data
- Plan W for topology diagrams
- Plan X for inventory data

## References
- `docs/plans/PlanU_ConfigurationTemplates.md` (Template patterns)
- `docs/plans/PlanW_NetworkTopologyVisualization.md` (Diagram integration)
- `docs/plans/PlanX_InventoryAssetTracking.md` (Asset data)
