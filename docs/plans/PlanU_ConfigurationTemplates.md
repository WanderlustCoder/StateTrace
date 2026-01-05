# Plan U - Configuration Templates & Validation

<!-- LANDMARK: ST-E-001 telemetry gates link -->
Telemetry gates: [docs/telemetry/Automation_Gates.md](../telemetry/Automation_Gates.md).

## Objective
Provide a configuration template system that enables network engineers to create, manage, and validate device configurations offline. Generate deployment-ready configs from templates, validate existing configs against standards, and diff configurations to identify deviations.

## Problem Statement
Network engineers face challenges with:
- Creating consistent configurations across similar devices
- Validating that deployed configs match organizational standards
- Identifying configuration drift between devices that should be identical
- Preparing bulk configuration changes before maintenance windows
- Documenting configuration standards in a reusable format

## Current status (2026-01)
- Templates view exists for port profile templates (Port Reorg)
- No general-purpose configuration templating engine
- Compare view provides diff capabilities for interface data
- No configuration validation or compliance checking

## Proposed Features

### U.1 Template Engine
- **Template Definition**: Create templates with:
  - Variables (hostname, IP, VLAN, interface, etc.)
  - Conditionals (if vendor=Cisco, if has_voice_vlan, etc.)
  - Loops (for each interface in access_ports)
  - Includes (reference other templates)
- **Vendor Support**: Templates for Cisco IOS/IOS-XE, Arista EOS, Brocade, Juniper
- **Template Library**: Organize templates by:
  - Purpose (access switch, distribution, core, WLC)
  - Vendor/platform
  - Site/region
- **Variable Substitution**: Define variables at multiple levels:
  - Global defaults
  - Site-level overrides
  - Device-level specifics

### U.2 Configuration Generation
- **Single Device**: Generate config for one device from template + variables
- **Bulk Generation**: Generate configs for multiple devices from CSV/table
- **Section Generation**: Generate just specific sections (interfaces, VLANs, routing)
- **Delta Generation**: Generate only the commands needed to change from current to desired state
- **Rollback Generation**: Auto-generate rollback commands alongside change commands

### U.3 Configuration Validation
- **Standards Definition**: Define validation rules:
  - Required settings (NTP servers, logging hosts, SNMP config)
  - Prohibited settings (telnet enabled, weak passwords patterns)
  - Naming conventions (hostname format, interface descriptions)
  - Security baselines (SSH version, ACL requirements)
- **Compliance Checking**: Validate configs against standards
- **Violation Reporting**: Generate reports showing:
  - Compliance score (percentage of rules passed)
  - Specific violations with line numbers
  - Remediation commands
- **Batch Validation**: Validate multiple device configs at once

### U.4 Configuration Comparison
- **Config Diff**: Compare two configurations with:
  - Side-by-side view
  - Unified diff view
  - Semantic diff (understand config structure, not just text)
- **Golden Config Comparison**: Compare device config against golden standard
- **Fleet Comparison**: Compare one device against all similar devices
- **Drift Detection**: Identify devices that have drifted from baseline

### U.5 Import & Export
- **Config Import**: Import configurations from:
  - Text files (show run output)
  - Backup archives
  - CSV/Excel for bulk device data
- **Export Formats**: Export generated configs to:
  - Individual text files per device
  - Combined file with separators
  - Zip archive for bulk deployment
- **Template Export/Import**: Share templates between StateTrace instances

## Active work
| ID | Title | Owner | Status | Notes |
|----|-------|-------|--------|-------|
| ST-U-001 | Template engine core | Tools | Pending | Variable substitution and conditional logic |
| ST-U-002 | Template library UI | UI | Pending | Template management view |
| ST-U-003 | Config generation module | Tools | Pending | Generate configs from templates |
| ST-U-004 | Validation rule engine | Tools | Pending | Define and check compliance rules |
| ST-U-005 | Config comparison view | UI | Pending | Enhanced diff view for configurations |
| ST-U-006 | Vendor syntax modules | Parser | Pending | Vendor-specific config parsing |

## Template Syntax (Proposed)

### Example Access Switch Template
```
! {{ hostname }} - Access Switch Configuration
! Generated: {{ generated_date }}
! Template: access-switch-standard-v1.2

hostname {{ hostname }}

{% if enable_secret %}
enable secret {{ enable_secret }}
{% endif %}

! Management VLAN
interface Vlan{{ mgmt_vlan }}
 ip address {{ mgmt_ip }} {{ mgmt_mask }}
 no shutdown

! NTP Configuration
{% for ntp_server in ntp_servers %}
ntp server {{ ntp_server }}
{% endfor %}

! Access Ports
{% for port in access_ports %}
interface {{ port.interface }}
 description {{ port.description }}
 switchport mode access
 switchport access vlan {{ port.vlan }}
 {% if port.voice_vlan %}
 switchport voice vlan {{ port.voice_vlan }}
 {% endif %}
 spanning-tree portfast
 no shutdown
{% endfor %}

! Uplinks
{% for uplink in uplinks %}
interface {{ uplink.interface }}
 description {{ uplink.description }}
 switchport mode trunk
 switchport trunk allowed vlan {{ uplink.allowed_vlans }}
 no shutdown
{% endfor %}
```

### Variable File Example (YAML)
```yaml
hostname: SW-BLDG1-FL2-01
mgmt_vlan: 100
mgmt_ip: 10.1.100.10
mgmt_mask: 255.255.255.0
enable_secret: $encrypted$...

ntp_servers:
  - 10.1.1.1
  - 10.1.1.2

access_ports:
  - interface: Gi1/0/1
    description: "Desk 201A"
    vlan: 10
    voice_vlan: 50
  - interface: Gi1/0/2
    description: "Desk 201B"
    vlan: 10
    voice_vlan: 50

uplinks:
  - interface: Gi1/0/48
    description: "To DS-BLDG1-01 Gi1/0/1"
    allowed_vlans: "10,20,50,100"
```

## Validation Rule Syntax (Proposed)

```yaml
# security-baseline.yml
name: Security Baseline v2.0
version: 2.0
vendor: cisco_ios

rules:
  - id: SEC-001
    name: SSH Version 2 Required
    severity: critical
    match: "ip ssh version 2"
    required: true
    remediation: "ip ssh version 2"

  - id: SEC-002
    name: Telnet Disabled
    severity: critical
    match: "transport input telnet"
    prohibited: true
    remediation: "line vty 0 15\n no transport input telnet\n transport input ssh"

  - id: SEC-003
    name: Password Encryption
    severity: high
    match: "service password-encryption"
    required: true

  - id: STD-001
    name: Hostname Format
    severity: medium
    pattern: "hostname [A-Z]{2,4}-[A-Z0-9]+-[A-Z0-9]+-\\d{2}"
    message: "Hostname must follow format: SITE-BLDG-ROLE-##"
```

## UI Mockup Concepts

### Template Editor
```
+----------------------------------------------------------+
| Template: access-switch-standard  [Save] [Test] [Export] |
+----------------------------------------------------------+
| Variables | Template | Preview | Validation              |
+----------------------------------------------------------+
| hostname: SW-TEST-01        |  hostname {{ hostname }}  |
| mgmt_vlan: 100              |  !                        |
| mgmt_ip: 10.1.100.10        |  interface Vlan{{ mgmt... |
| [+ Add Variable]            |                           |
+----------------------------------------------------------+
```

### Compliance Report
```
+----------------------------------------------------------+
| Compliance Report: SW-BLDG1-FL2-01                       |
| Standard: Security Baseline v2.0                          |
| Score: 87% (13/15 rules passed)                          |
+----------------------------------------------------------+
| CRITICAL VIOLATIONS (1)                                   |
| - SEC-002: Telnet enabled on VTY lines (line 245)        |
|   Remediation: transport input ssh                        |
+----------------------------------------------------------+
| HIGH VIOLATIONS (1)                                       |
| - SEC-003: Password encryption not enabled                |
|   Remediation: service password-encryption                |
+----------------------------------------------------------+
| [Generate Remediation Script] [Export Report]             |
+----------------------------------------------------------+
```

## Automation hooks
- `Tools\New-ConfigFromTemplate.ps1 -Template <name> -Variables vars.yml -Output config.txt`
- `Tools\Test-ConfigCompliance.ps1 -Config running.txt -Standard security-baseline.yml`
- `Tools\Compare-Configurations.ps1 -Source config1.txt -Target config2.txt -Format unified`
- `Tools\Export-ComplianceReport.ps1 -Scope Site -Site BLDG1 -Format PDF`

## Telemetry gates
- Template operations emit `TemplateGeneration` events with variable counts
- Validation runs emit `ConfigCompliance` with pass/fail/severity breakdown
- Config comparisons emit `ConfigDiff` with change counts by section

## Dependencies
- Compare view infrastructure
- Templates view for UI patterns
- Vendor-specific parsing modules (leverage existing parser infrastructure)

## References
- `docs/plans/PlanD_FeatureExpansion.md` (Templates view context)
- `docs/plans/PlanC_ChangeTracking.md` (Diff model)
- `Modules/PortReorgModule.psm1` (Script generation patterns)
