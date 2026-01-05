# Plan AD - Cross-Vendor Command Reference

<!-- LANDMARK: ST-E-001 telemetry gates link -->
Telemetry gates: [docs/telemetry/Automation_Gates.md](../telemetry/Automation_Gates.md).

## Objective
Provide a comprehensive cross-vendor command reference and translation tool. Enable network engineers to quickly find equivalent commands across different network vendors (Cisco, Arista, Juniper, HP, etc.) and understand syntax differences when working in multi-vendor environments.

## Problem Statement
Network teams struggle with:
- Remembering command syntax across multiple vendors
- Translating configurations between vendor platforms
- Training staff on new vendor equipment
- Finding equivalent show commands for troubleshooting
- Understanding output format differences between vendors
- Documenting procedures that work across vendors

## Current status (2026-01)
- **Phase 1 Complete**: Core command reference and translation implemented
- CommandReferenceModule.psm1: 20+ commands across 4 vendors (Cisco, Arista, Juniper, HP)
- CommandReferenceViewModule.psm1: Full UI with 4 tabs (Commands, Compare, Snippets, Quick Reference)
- 50 passing unit tests covering all core functionality
- Config snippet templates with variable expansion
- Command translation between vendors with notes

### Delivered Features
- Command database with task-based organization
- Command translation engine (Convert-NetworkCommand)
- Vendor comparison (Get-CommandComparison)
- Config snippet library with VLAN, trunk, access port templates
- Status code documentation for show commands
- Output format reference

### Pending Features
- Learning mode (quizzes, flash cards)
- PDF/printable cheat sheet export
- Additional vendors (NX-OS, Dell OS10)
- Batch configuration translation

## Proposed Features

### AD.1 Command Database
- **Comprehensive Coverage**: Commands organized by:
  - Category (show, config, debug, clear)
  - Function (interfaces, routing, switching, security)
  - Common task (check port status, show routes, etc.)
- **Supported Vendors**:
  - Cisco IOS / IOS-XE / NX-OS
  - Arista EOS
  - Juniper JunOS
  - HP/Aruba
  - Dell OS10
- **Command Details**:
  - Full syntax with parameters
  - Common variations
  - Output format description
  - Usage examples

### AD.2 Command Translation
- **Direct Translation**: Enter command from one vendor, get equivalent:
  - `show ip route` (Cisco) -> `show ip route` (Arista) -> `show route` (Juniper)
- **Batch Translation**: Convert configuration snippets:
  - VLAN configurations
  - Interface configurations
  - ACL entries
  - Routing configurations
- **Translation Notes**: Highlight differences:
  - Unsupported features
  - Behavioral differences
  - Required prerequisites

### AD.3 Quick Reference Cards
- **Task-Based Lookup**: "How do I..." searches:
  - Show interface status
  - Configure a VLAN
  - Check routing table
  - View MAC address table
  - Check spanning tree
- **Side-by-Side Comparison**: Multi-column view:
  - Same task across 2-4 vendors
  - Syntax differences highlighted
  - Copy-ready commands
- **Printable Cheat Sheets**: Generate PDFs by:
  - Vendor pair (Cisco<->Arista)
  - Category (Layer 2, Layer 3, etc.)
  - Role (Access switch, Core router)

### AD.4 Output Format Reference
- **Show Command Output**: Document output formats:
  - Column headers and meanings
  - Status codes and indicators
  - Common values and their meanings
- **Output Comparison**: Side-by-side output examples:
  - Cisco vs Arista interface output
  - Different ways errors are displayed
  - Status indicator mapping
- **Parsing Guidance**: Regex patterns for extracting data

### AD.5 Configuration Snippets
- **Common Tasks Library**: Ready-to-use configs:
  - VLAN creation
  - Trunk configuration
  - Port-channel setup
  - HSRP/VRRP configuration
  - OSPF/BGP basic setup
  - Access lists
- **Template Variables**: Customizable snippets:
  - Replace placeholders with values
  - Generate complete configs
  - Validate before use

### AD.6 Learning Mode
- **Interactive Quizzes**: Test knowledge:
  - "What's the Arista equivalent of...?"
  - Flash card style learning
  - Track progress
- **Comparison Drills**: Side-by-side practice:
  - Identify the vendor from syntax
  - Complete missing parameters
- **Certification Prep**: Vendor-specific focus

## Active work
| ID | Title | Owner | Status | Notes |
|----|-------|-------|--------|-------|
| ST-AD-001 | Command database schema | Data | Done | Task-based hashtable structure in CommandReferenceModule.psm1 |
| ST-AD-002 | Core command library | Tools | Done | 20+ commands: Cisco, Arista, Juniper, HP |
| ST-AD-003 | Translation engine | Tools | Done | Convert-NetworkCommand with notes |
| ST-AD-004 | Quick reference UI | UI | Done | 4-tab interface: Commands, Compare, Snippets, Quick Ref |
| ST-AD-005 | Config snippet library | Tools | Done | VLAN, Trunk, Access Port templates |
| ST-AD-006 | Learning mode | UI | Pending | Quiz and practice features |

## Data Model (Proposed)

### CommandEntry Table
```
CommandID (PK), VendorID (FK), CategoryID (FK), CommandText,
Description, FullSyntax, Parameters, OutputFormat, Examples, Notes
```

### CommandEquivalent Table
```
EquivalentID (PK), CommandID1 (FK), CommandID2 (FK),
EquivalenceType, TranslationNotes, Caveats
```

### Vendor Table
```
VendorID (PK), Name, OSFamily, OSVersions, SyntaxStyle, Notes
```

### CommandCategory Table
```
CategoryID (PK), Name, Description, ParentCategoryID
```

### ConfigSnippet Table
```
SnippetID (PK), VendorID (FK), TaskName, Description,
Template, Variables, Prerequisites, Caveats
```

## Testing Requirements

### Unit Tests (`Modules/Tests/CommandReferenceModule.Tests.ps1`)

```powershell
Describe 'Command Reference' -Tag 'CommandReference' {

    Describe 'Command Database' {
        It 'retrieves command by exact match' {
            $cmd = Get-NetworkCommand -Command 'show ip route' -Vendor 'Cisco'

            $cmd | Should -Not -BeNullOrEmpty
            $cmd.Vendor | Should -Be 'Cisco'
            $cmd.CommandText | Should -Be 'show ip route'
        }

        It 'searches commands by keyword' {
            $results = Search-NetworkCommands -Keyword 'interface' -Vendor 'Cisco'

            $results.Count | Should -BeGreaterThan 5
            $results.CommandText | Should -Match 'interface'
        }

        It 'lists commands by category' {
            $results = Get-NetworkCommands -Category 'Routing' -Vendor 'Arista'

            $results.Count | Should -BeGreaterThan 0
            $results.Category | Should -Contain 'Routing'
        }

        It 'returns full syntax with parameters' {
            $cmd = Get-NetworkCommand -Command 'show ip route' -Vendor 'Cisco'

            $cmd.FullSyntax | Should -Match 'show ip route'
            $cmd.Parameters | Should -Not -BeNullOrEmpty
        }
    }

    Describe 'Command Translation' {
        It 'translates show command between vendors' {
            $translation = Convert-NetworkCommand `
                -Command 'show ip interface brief' `
                -FromVendor 'Cisco' `
                -ToVendor 'Arista'

            $translation.TranslatedCommand | Should -Be 'show ip interface brief'
            $translation.Notes | Should -Match 'identical|same'
        }

        It 'translates command with different syntax' {
            $translation = Convert-NetworkCommand `
                -Command 'show ip route' `
                -FromVendor 'Cisco' `
                -ToVendor 'Juniper'

            $translation.TranslatedCommand | Should -Be 'show route'
        }

        It 'indicates when command has no equivalent' {
            $translation = Convert-NetworkCommand `
                -Command 'show platform' `
                -FromVendor 'Cisco' `
                -ToVendor 'Arista'

            $translation.HasEquivalent | Should -BeTrue  # Arista has 'show platform'
        }

        It 'provides translation notes for behavioral differences' {
            $translation = Convert-NetworkCommand `
                -Command 'spanning-tree mode rapid-pvst' `
                -FromVendor 'Cisco' `
                -ToVendor 'Arista'

            $translation.Notes | Should -Not -BeNullOrEmpty
            # Arista uses 'spanning-tree mode mstp' or 'rapid-pvst'
        }

        It 'translates configuration blocks' {
            $config = @'
interface GigabitEthernet1/0/1
 description Uplink to Core
 switchport mode trunk
 switchport trunk allowed vlan 10,20,30
'@

            $translated = Convert-NetworkConfig `
                -Config $config `
                -FromVendor 'Cisco' `
                -ToVendor 'Arista'

            $translated | Should -Match 'interface Ethernet'
            $translated | Should -Match 'switchport mode trunk'
        }
    }

    Describe 'Quick Reference' {
        It 'finds command by task description' {
            $results = Find-CommandByTask -Task 'check port status'

            $results.Count | Should -BeGreaterThan 0
            $results.Vendors | Should -Contain 'Cisco'
            $results.Vendors | Should -Contain 'Arista'
        }

        It 'generates side-by-side comparison' {
            $comparison = Get-CommandComparison `
                -Task 'show routing table' `
                -Vendors @('Cisco', 'Arista', 'Juniper')

            $comparison.Rows.Count | Should -BeGreaterThan 0
            $comparison.Columns | Should -Contain 'Cisco'
            $comparison.Columns | Should -Contain 'Juniper'
        }

        It 'generates printable cheat sheet' {
            $sheet = New-CommandCheatSheet `
                -VendorPair @('Cisco', 'Arista') `
                -Category 'Layer2'

            $sheet.Content | Should -Not -BeNullOrEmpty
            $sheet.Format | Should -Be 'Markdown'
        }

        It 'exports cheat sheet to PDF' {
            $sheet = New-CommandCheatSheet -VendorPair @('Cisco', 'Arista')
            $path = Export-CheatSheet -Sheet $sheet -Format PDF

            Test-Path $path | Should -BeTrue
        }
    }

    Describe 'Output Format Reference' {
        It 'documents output column meanings' {
            $format = Get-OutputFormat -Command 'show interface status' -Vendor 'Cisco'

            $format.Columns | Should -Not -BeNullOrEmpty
            $format.Columns.Name | Should -Contain 'Status'
            $format.Columns.Name | Should -Contain 'Vlan'
        }

        It 'explains status codes' {
            $codes = Get-StatusCodes -Command 'show ip route' -Vendor 'Cisco'

            $codes.Count | Should -BeGreaterThan 5
            $codes['C'] | Should -Match 'connected'
            $codes['O'] | Should -Match 'OSPF'
        }

        It 'compares output formats between vendors' {
            $comparison = Compare-OutputFormat `
                -Command 'show interface' `
                -Vendors @('Cisco', 'Arista')

            $comparison.Differences | Should -Not -BeNullOrEmpty
        }

        It 'provides regex patterns for parsing' {
            $patterns = Get-OutputParsingPatterns `
                -Command 'show ip route' -Vendor 'Cisco'

            $patterns.RouteEntry | Should -Not -BeNullOrEmpty
            $patterns.NextHop | Should -Not -BeNullOrEmpty
        }
    }

    Describe 'Configuration Snippets' {
        It 'retrieves snippet by task name' {
            $snippet = Get-ConfigSnippet -Task 'VLAN Creation' -Vendor 'Cisco'

            $snippet.Template | Should -Match 'vlan'
            $snippet.Variables | Should -Contain 'vlan_id'
        }

        It 'applies variables to snippet' {
            $snippet = Get-ConfigSnippet -Task 'VLAN Creation' -Vendor 'Cisco'
            $config = Expand-ConfigSnippet -Snippet $snippet -Variables @{
                vlan_id = 100
                vlan_name = 'Users'
            }

            $config | Should -Match 'vlan 100'
            $config | Should -Match 'name Users'
        }

        It 'lists available snippets by category' {
            $snippets = Get-ConfigSnippets -Category 'Switching' -Vendor 'Arista'

            $snippets.Count | Should -BeGreaterThan 3
            $snippets.TaskName | Should -Contain 'VLAN Creation'
            $snippets.TaskName | Should -Contain 'Trunk Configuration'
        }

        It 'validates snippet before use' {
            $snippet = Get-ConfigSnippet -Task 'HSRP Configuration' -Vendor 'Cisco'
            $validation = Test-ConfigSnippet -Snippet $snippet -Variables @{
                hsrp_group = 1
                hsrp_vip = '10.1.1.1'
                # Missing priority
            }

            $validation.IsValid | Should -BeFalse
            $validation.MissingVariables | Should -Contain 'hsrp_priority'
        }
    }

    Describe 'Learning Mode' {
        It 'generates translation quiz questions' {
            $quiz = New-CommandQuiz -Type Translation -Count 10

            $quiz.Questions.Count | Should -Be 10
            $quiz.Questions[0].SourceCommand | Should -Not -BeNullOrEmpty
            $quiz.Questions[0].Options.Count | Should -BeGreaterThan 2
        }

        It 'scores quiz answers correctly' {
            $quiz = New-CommandQuiz -Type Translation -Count 5
            $answers = @(
                @{ QuestionIndex = 0; Answer = $quiz.Questions[0].CorrectAnswer },
                @{ QuestionIndex = 1; Answer = 'wrong answer' }
            )

            $result = Submit-QuizAnswers -Quiz $quiz -Answers $answers

            $result.Correct | Should -Be 1
            $result.Incorrect | Should -Be 1
            $result.Percentage | Should -Be 50
        }

        It 'tracks learning progress' {
            $progress = Get-LearningProgress -User 'testuser'

            $progress.TotalQuizzes | Should -BeGreaterOrEqual 0
            $progress.AverageScore | Should -BeGreaterOrEqual 0
        }

        It 'generates flash cards' {
            $cards = New-FlashCards -Category 'Show Commands' -Count 20

            $cards.Count | Should -Be 20
            $cards[0].Front | Should -Not -BeNullOrEmpty
            $cards[0].Back | Should -Not -BeNullOrEmpty
        }
    }

    Describe 'Multi-Vendor Support' {
        It 'supports all major vendors' {
            $vendors = Get-SupportedVendors

            $vendors | Should -Contain 'Cisco'
            $vendors | Should -Contain 'Arista'
            $vendors | Should -Contain 'Juniper'
            $vendors | Should -Contain 'HP'
        }

        It 'returns vendor-specific syntax style' {
            $cisco = Get-VendorInfo -Name 'Cisco'
            $juniper = Get-VendorInfo -Name 'Juniper'

            $cisco.SyntaxStyle | Should -Be 'IOS'
            $juniper.SyntaxStyle | Should -Be 'JunOS'
        }

        It 'handles vendor aliases' {
            $result1 = Get-NetworkCommand -Command 'show ip route' -Vendor 'Cisco IOS'
            $result2 = Get-NetworkCommand -Command 'show ip route' -Vendor 'IOS-XE'

            $result1.CommandText | Should -Be $result2.CommandText
        }
    }
}
```

## UI Mockup Concepts

### Command Lookup View
```
+------------------------------------------------------------------+
| Network Command Reference                         [Settings][?] |
+------------------------------------------------------------------+
| SEARCH: [show interface status                    ] [Search]     |
| Vendor: [Cisco IOS    v]    Category: [All        v]            |
+------------------------------------------------------------------+
| RESULTS (5 matches)                                              |
+------------------------------------------------------------------+
| show interface status                                            |
| Shows interface status in tabular format                         |
| Syntax: show interface status [module slot/port]                 |
|                                                                  |
| [Copy] [Translate] [Show Output Format] [Examples]              |
+------------------------------------------------------------------+
| show interface Gi1/0/1 status                                    |
| Shows status of specific interface                               |
| ...                                                              |
+------------------------------------------------------------------+
```

### Translation View
```
+------------------------------------------------------------------+
| Command Translation                                              |
+------------------------------------------------------------------+
| FROM: [Cisco IOS     v]        TO: [Arista EOS    v]            |
+------------------------------------------------------------------+
| SOURCE COMMAND:                                                  |
| +--------------------------------------------------------------+ |
| | show ip interface brief                                      | |
| +--------------------------------------------------------------+ |
|                         [Translate]                              |
+------------------------------------------------------------------+
| TRANSLATED COMMAND:                                              |
| +--------------------------------------------------------------+ |
| | show ip interface brief                                      | |
| +--------------------------------------------------------------+ |
| Notes: Command syntax is identical between Cisco and Arista.     |
|        Output format differs slightly in column headers.        |
+------------------------------------------------------------------+
| [Copy] [Show Syntax Details] [Compare Output]                    |
+------------------------------------------------------------------+
```

### Side-by-Side Reference
```
+------------------------------------------------------------------+
| Quick Reference: Show Interface Information                      |
+------------------------------------------------------------------+
| Cisco IOS         | Arista EOS        | Juniper JunOS           |
+------------------------------------------------------------------+
| show interface    | show interface    | show interfaces         |
| brief             | brief             | terse                   |
+------------------------------------------------------------------+
| show interface    | show interface    | show interfaces         |
| status            | status            | brief                   |
+------------------------------------------------------------------+
| show interface    | show interface    | show interfaces         |
| Gi1/0/1           | Ethernet1         | ge-0/0/1                |
+------------------------------------------------------------------+
| show interface    | show interface    | show interfaces         |
| counters          | counters          | statistics              |
+------------------------------------------------------------------+
| [Copy Cisco] [Copy Arista] [Copy Juniper] [Export PDF]          |
+------------------------------------------------------------------+
```

### Configuration Snippet Builder
```
+------------------------------------------------------------------+
| Config Snippet: Trunk Port Configuration                         |
+------------------------------------------------------------------+
| Vendor: [Cisco IOS    v]                                        |
+------------------------------------------------------------------+
| VARIABLES                     | PREVIEW                         |
| Interface: [Gi1/0/24       ]  | interface GigabitEthernet1/0/24 |
| Description: [Uplink to DS ]  |  description Uplink to DS       |
| Mode: [Trunk  v]              |  switchport trunk encapsulation |
| Native VLAN: [1            ]  |   dot1q                         |
| Allowed VLANs: [10,20,30   ]  |  switchport mode trunk          |
|                               |  switchport trunk native vlan 1 |
|                               |  switchport trunk allowed vlan  |
|                               |   10,20,30                      |
+------------------------------------------------------------------+
| [Validate] [Copy Config] [Translate to Arista]                   |
+------------------------------------------------------------------+
```

## Automation hooks
- `Tools\Get-CommandEquivalent.ps1 -Command "show ip route" -From Cisco -To Arista`
- `Tools\Convert-VendorConfig.ps1 -Path config.txt -From Cisco -To Arista`
- `Tools\New-CommandCheatSheet.ps1 -Vendors Cisco,Arista -Category Routing -Format PDF`
- `Tools\Search-NetworkCommands.ps1 -Keyword "spanning" -Vendor Cisco`
- `Tools\Get-ConfigSnippet.ps1 -Task "VLAN Creation" -Vendor Arista -Variables @{vlan_id=100}`

## Telemetry gates
- Command searches emit `CommandSearch` with query and results count
- Translations emit `CommandTranslation` with source/target vendors
- Snippet usage emits `SnippetUsage` with task name and vendor
- Quiz completions emit `QuizComplete` with score

## Dependencies
- Existing parser knowledge of vendor syntax
- Output format documentation

## References
- `docs/plans/PlanU_ConfigurationTemplates.md` (Template engine)
- `Tests/Fixtures/Routing/CliCapture/` (Vendor-specific parsing)
- `docs/plans/PlanAA_DocumentationGenerator.md` (Cheat sheet export)
